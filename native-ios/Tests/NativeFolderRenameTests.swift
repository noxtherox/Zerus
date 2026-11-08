import XCTest
@testable import ZerusNative

final class NativeFolderRenameTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func disk(_ path: String, _ data: Data) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
    private func text(_ path: String, _ value: String) throws { try disk(path, Data(value.utf8)) }

    func testReviewedWholeFolderRenamePreservesOpaqueFilesAndRebasesLinksRelationsDocumentsTasksAndMetadata() async throws {
        let io = VaultFiles(root: root)
        let source = "---\r\nzerus-id: a\r\nForeign: keep\r\n---\r\n# A\r\n\r\n![Plot](./assets/p.png \"Caption\")\r\n[Shared](../Shared/report.pdf#page=2)\r\n`Work/A.md`\r\n```md\r\n[Literal](Work/A.md)\r\n```\r\n"
        try text("Work/A.md", source); try text("Work/B.md", "# Legacy B\n\nKeep this body.\n")
        try text("Outside.md", "---\nzerus-id: outside\n---\n# Outside\n\n[[Work/B.md|Legacy label]]\n[Plot](Work/assets/p.png)\n")
        try text("Projects/P.md", "---\nzerus-id: project\nRelated: [\"Work/A.md\"]\n---\n# Project\nOriginal body.\n")
        try text("Document.md", "---\nzerus-id: document\nzerus-file-id: document\nzerus-file-name: report.pdf\nzerus-file-kind: vault\nzerus-file-path: Work/report.pdf\nzerus-attachments: ['{\"id\":\"backup\",\"name\":\"backup\",\"kind\":\"vault\",\"path\":\"Work/report.pdf\",\"future\":42}']\n---\n# Document\n")
        try text(".trash/Work/Old.md", "---\nzerus-id: old\n---\n# Old\n![Plot](./assets/p.png)\n")
        let binary = Data([0, 1, 2, 255, 4]); try disk("Work/assets/p.png", binary)
        try disk("Work/report.pdf", Data("PDF original bytes".utf8)); try disk("Work/.foreign", Data("Opaque foreign file".utf8))
        try text("Shared/report.pdf", "Shared file remains")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work/Empty/Child"), withIntermediateDirectories: true)
        let schema = #"{"Work":[{"name":"Owner","type":"text","foreign":42}],"Projects":[{"name":"Related","type":"relation","relationTypeKey":"Work","relationPairId":"pair","relationMultiple":true}],"metadata":{"keep":true}}"#
        try text(".zerus/properties.json", schema)
        for file in ["type-icons.json", "views.json", "saved-views.json"] { try text(".zerus/" + file, #"{"Work":{"future":"keep"},"Work/Empty":"tabler:Star","Other":[1,2]}"#) }
        try text(".zerus/tasks.json", #"{"future":{"keep":true},"tasks":[{"id":"task","title":"Task","linkedNoteIds":["Work/A.md","missing"]}]}"#)
        let snapshot = try await io.relationDefinitionSnapshot()
        let plan = try await io.prepareFolderRename(snapshot, source: "Work", destination: "Archive/Done")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.utf8), "Preparing or canceling must not mutate the source")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(".zerus/properties.json"), encoding: .utf8), schema)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Archive/Done").path))
        let result = try await io.applyFolderRename(plan)
        let a = try XCTUnwrap(result.notes.first { $0.path == "Archive/Done/A.md" })
        XCTAssertEqual(a.property("Foreign"), "keep")
        XCTAssertTrue(a.content.contains("![Plot](./assets/p.png \"Caption\")\r\n"))
        XCTAssertTrue(a.content.contains("../../Shared/report.pdf#page=2"))
        XCTAssertTrue(a.content.contains("`Work/A.md`\r\n```md\r\n[Literal](Work/A.md)\r\n```"))
        let legacy = try XCTUnwrap(result.notes.first { $0.path == "Archive/Done/B.md" })
        let legacyID = try XCTUnwrap(legacy.stableID)
        XCTAssertEqual(legacy.parts.body, "# Legacy B\n\nKeep this body.\n")
        let outside = try XCTUnwrap(result.notes.first { $0.path == "Outside.md" })
        XCTAssertTrue(outside.content.contains("[[zerus:" + legacyID + "|Legacy label]]"))
        XCTAssertTrue(outside.content.contains("./Archive/Done/assets/p.png"))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Archive/Done/assets/p.png")), binary)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Archive/Done/.foreign"), encoding: .utf8), "Opaque foreign file")
        XCTAssertTrue(result.folders.contains("Archive/Done/Empty/Child")); XCTAssertFalse(result.folders.contains("Work"))
        let project = try XCTUnwrap(result.notes.first { $0.path == "Projects/P.md" })
        XCTAssertEqual(project.property("Related"), "[\"zerus:a\"]")
        let document = try XCTUnwrap(result.notes.first { $0.path == "Document.md" })
        XCTAssertEqual(document.fileHub?.path, "Archive/Done/report.pdf")
        XCTAssertEqual(NativeFileAttachment.all(in: document.content).first?.path, "Archive/Done/report.pdf")
        XCTAssertTrue(document.content.contains("42"))
        let deleted = try XCTUnwrap(result.notes.first { $0.path == ".trash/Archive/Done/Old.md" })
        XCTAssertEqual(deleted.stableID, "old")
        let deletedImage = try await io.resolveResource("./assets/p.png", notePath: deleted.path)
        XCTAssertEqual(try Data(contentsOf: deletedImage), binary)
        let afterSchema = try await io.schemaSnapshot()
        XCTAssertEqual(try afterSchema.definitions(owner: "Archive/Done").first?.name, "Owner")
        XCTAssertEqual(try afterSchema.definitions(owner: "Projects").first?.relationTypeKey, "Archive/Done")
        for file in ["type-icons.json", "views.json", "saved-views.json"] {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/" + file))) as? [String: Any])
            XCTAssertNil(object["Work"]); XCTAssertEqual((object["Archive/Done"] as? [String: String])?["future"], "keep"); XCTAssertEqual(object["Archive/Done/Empty"] as? String, "tabler:Star"); XCTAssertEqual(object["Other"] as? [Int], [1, 2])
        }
        let tasks = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))) as? [String: Any])
        XCTAssertEqual((tasks["tasks"] as? [[String: Any]])?.first?["linkedNoteIds"] as? [String], ["a", "missing"])
        XCTAssertEqual((tasks["future"] as? [String: Bool])?["keep"], true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work").path))
    }

    func testChangedTreesMetadataAndDestinationsRejectTheWholeReviewBeforeWrites() async throws {
        let io = VaultFiles(root: root)
        try text("Work/A.md", "---\nzerus-id: a\n---\n# A\nKeep me.\n")
        try text(".zerus/type-icons.json", #"{"Work":"tabler:Star"}"#)
        let snapshot = try await io.relationDefinitionSnapshot(), plan = try await io.prepareFolderRename(snapshot, source: "Work", destination: "Renamed")
        try text("Work/New.bin", "Outside new file")
        do { _ = try await io.applyFolderRename(plan); XCTFail("New files make the reviewed tree stale") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Renamed").path))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Work/New.bin"))
        try text(".zerus/type-icons.json", #"{"Work":"📚","future":42}"#)
        do { _ = try await io.applyFolderRename(plan); XCTFail("A stale icon file must prevent all writes") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/A.md").path))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(".zerus/type-icons.json"), encoding: .utf8), #"{"Work":"📚","future":42}"#)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Renamed"), withIntermediateDirectories: true)
        let fresh = try await io.relationDefinitionSnapshot()
        for destination in ["Renamed", "Work/Sub", "../Outside", ".zerus/Bad", "work"] {
            do { _ = try await io.prepareFolderRename(fresh, source: "Work", destination: destination); XCTFail("Invalid/colliding destination must be refused: \(destination)") } catch {}
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Work/Link"), withDestinationURL: root.appendingPathComponent("Renamed"))
        do { _ = try await io.prepareFolderRename(fresh, source: "Work", destination: "Other"); XCTFail("Linked descendants must not be relocated silently") } catch {}
    }

    func testColdScannerFinishesAnActualCommittedDirectoryReceiptAndPreservesOutsideEditsWhileBlocked() async throws {
        let io = VaultFiles(root: root)
        try text("Work/A.md", "---\nzerus-id: a\n---\n# A\nOriginal\n")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work/Empty"), withIntermediateDirectories: true)
        let plan = try await io.prepareFolderRename(io.relationDefinitionSnapshot(), source: "Work", destination: "Renamed")
        // Commit the actual planner-produced file changes through the production
        // journal writer, then end this owner before its directory phase.
        try await io.applyTransaction(plan.changes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Renamed").path))
        let reviewed = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
        try text("Work/A.md", "# Outside edit must survive")
        let cold = VaultFiles(root: root)
        do { _ = try await cold.scan(); XCTFail("Changed files keep the rename pending without overwriting") } catch {}
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8), "# Outside edit must survive")
        let suspended = await cold.writesSuspendedForRecovery; XCTAssertTrue(suspended)
        try disk("Work/A.md", reviewed)
        let result = try await cold.scan()
        XCTAssertTrue(result.folders.contains("Renamed/Empty")); XCTAssertTrue(result.notes.contains { $0.path == "Renamed/A.md" })
        let next = try await cold.prepareFolderRename(cold.relationDefinitionSnapshot(), source: "Renamed", destination: "Done")
        try await cold.applyTransaction(next.changes)
        try FileManager.default.moveItem(at: root.appendingPathComponent("Renamed"), to: root.appendingPathComponent("Done"))
        let finished = try await VaultFiles(root: root).scan()
        XCTAssertTrue(finished.folders.contains("Done/Empty"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".zerus/native-folder-renames").path).isEmpty)
    }

    @MainActor
    func testStoreKeepsOpenEditorsDefaultsAndOrderingConnectedAndRejectsAnOldWorkspaceReview() async throws {
        try text("Work/Sub/A.md", "# Legacy editor\n\nOriginal\n"); try text("Root.md", "# Root\n")
        let store = VaultStore(); await store.open(root)
        let originalWorkspace = store.workspaceID, id = try XCTUnwrap(store.activeVaultID)
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: NativeFolderOrder.key(id)); UserDefaults.standard.removeObject(forKey: NativeNoteDefaults.key(id)) }
        UserDefaults.standard.set("Work/Sub", forKey: NativeNoteDefaults.key(id))
        store.reorderFolder("Work", direction: -1, workspace: originalWorkspace)
        let originalNote = try XCTUnwrap(store.notes.first { $0.path == "Work/Sub/A.md" }), editor = try XCTUnwrap(store.session(for: originalNote))
        let snapshot = try await store.relationDefinitionSnapshot(), plan = try await store.prepareFolderRename(snapshot, source: "Work", destination: "Archive/Done")
        let other = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: other) }
        await store.open(other)
        do { try await store.saveFolderRename(plan); XCTFail("An old review must not write after switching vaults") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/Sub/A.md").path))
        await store.open(root)
        let currentEditor = try XCTUnwrap(store.session(for: XCTUnwrap(store.notes.first { $0.path == originalNote.path })))
        let current = try await store.prepareFolderRename(store.relationDefinitionSnapshot(), source: "Work", destination: "Archive/Done")
        try await store.saveFolderRename(current)
        XCTAssertEqual(currentEditor.document.path, "Archive/Done/Sub/A.md"); XCTAssertNotNil(currentEditor.document.stableID)
        XCTAssertEqual(NativeNoteDefaults.load(id), "Archive/Done/Sub")
        XCTAssertTrue(store.folderOrder.contains("Archive/Done")); XCTAssertFalse(store.folderOrder.contains("Work"))
        XCTAssertEqual(editor.document.parts.body, originalNote.parts.body, "The retired previous-workspace editor must not be overwritten")
    }
}
