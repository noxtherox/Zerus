import XCTest
@testable import Zerus_Native

@MainActor final class MacRelationRepairTests: XCTestCase {
    private func fixture(_ work: (URL, MacWorkspace) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-Mac-repair-" + UUID().uuidString)
        let files = [
            ".zerus/properties.json": #"{"metadata":{"keep":7},"Tasks":[{"name":"Product","type":"relation","relationTypeKey":"Products","relationPairId":"product-pair","futureFlag":42}],"Products":[{"name":"Tasks","type":"relation","relationTypeKey":"Tasks","relationPairId":"product-pair","relationMultiple":true}]}"#,
            "Clean/Good.md": "---\nzerus-id: feedback\nProduct: Fleet\nForeign:\n  nested: [keep]\n---\n# Feedback\n\nOriginal feedback body.\n",
            "Products/Fleet.md": "---\nzerus-id: fleet\n---\n# Fleet\n\nOriginal product body.\n",
            "Unsafe/Unknown.md": "---\nProduct: Missing\n---\n# Unresolved\n",
        ]
        for (path, text) in files { let url = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(text.utf8).write(to: url) }
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        let workspace = MacWorkspace(); await workspace.openVault(root)
        defer {
            if let drafts = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: drafts) }
            defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root))
            defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
            try? FileManager.default.removeItem(at: root)
        }
        try await work(root, workspace)
    }
    func testMacRepairPublishesInferredDefinitionsAndPairedValuesToBothOpenWindows() async throws {
        try await fixture { root, workspace in
            await workspace.openNote("Products/Fleet.md")
            let peer = MacWorkspace(); await peer.openVault(root); await peer.openNote("Clean/Good.md")
            let originalBody = peer.body, beforeUnsafe = try Data(contentsOf: root.appendingPathComponent("Unsafe/Unknown.md"))
            let plan = try await workspace.prepareRelationRepair()
            XCTAssertTrue(plan.hasChanges); XCTAssertTrue(plan.issues.contains { $0.path == "Unsafe/Unknown.md" })
            let beforeSchema = try Data(contentsOf: root.appendingPathComponent(".zerus/properties.json"))
            XCTAssertFalse(try XCTUnwrap(peer.schema).definitions(owner: "Clean").contains { $0.type == .relation })
            try await workspace.commitSchemaMaintenance(plan)
            XCTAssertEqual(peer.body, originalBody)
            XCTAssertEqual(peer.current?.property("Product"), "zerus:fleet|Fleet")
            let repaired = try XCTUnwrap(peer.schema)
            XCTAssertEqual(try repaired.definitions(owner: "Clean").first { $0.id == "product" }?.relationPairID, "product-pair")
            let product = try XCTUnwrap(workspace.current)
            XCTAssertTrue(try NativeRelationSnapshot.values(product, name: "Tasks").contains("zerus:feedback|Feedback"))
            XCTAssertTrue(try XCTUnwrap(peer.current).content.contains("Foreign:\n  nested: [keep]"))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Unsafe/Unknown.md")), beforeUnsafe)
            XCTAssertNotEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/properties.json")), beforeSchema)
            XCTAssertFalse(workspace.schemaMaintenanceSaving); XCTAssertFalse(peer.schemaMaintenanceSaving)
            do { try await workspace.commitSchemaMaintenance(plan); XCTFail("An applied review cannot overwrite subsequent schema state") } catch {}
        }
    }
    func testMacRepairRejectsOutsideEditsRetainedDraftsAndPreviousWorkspaceReviews() async throws {
        try await fixture { root, workspace in
            let originalSchema = try Data(contentsOf: root.appendingPathComponent(".zerus/properties.json")), noteURL = root.appendingPathComponent("Clean/Good.md"), original = try Data(contentsOf: noteURL)
            let plan = try await workspace.prepareRelationRepair()
            try (original + Data("Outside text.\n".utf8)).write(to: noteURL)
            do { try await workspace.commitSchemaMaintenance(plan); XCTFail("An outside edit must remain untouched") } catch {}
            XCTAssertEqual(try Data(contentsOf: noteURL), original + Data("Outside text.\n".utf8))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/properties.json")), originalSchema)
            XCTAssertFalse(workspace.schemaMaintenanceSaving)
            try original.write(to: noteURL)
            let note = NoteDocument(path: "Clean/Good.md", content: String(decoding: original, as: UTF8.self), modified: .now), owner = UUID().uuidString
            try MacNoteRecoveryStore.checkpoint(root: root, note: note, body: "Retained unsaved writing.", windowID: owner)
            let draft = MacNoteRecoveryStore.location(root: root, path: note.path, windowID: owner), draftBytes = try Data(contentsOf: draft)
            defer { try? FileManager.default.removeItem(at: draft) }
            do { try await workspace.commitSchemaMaintenance(plan); XCTFail("Private retained text must be resolved before relation repair") } catch { XCTAssertTrue(error.localizedDescription.contains("draft")) }
            XCTAssertEqual(try Data(contentsOf: draft), draftBytes)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/properties.json")), originalSchema)
            try FileManager.default.removeItem(at: draft)
            await workspace.openVault(root)
            do { try await workspace.commitSchemaMaintenance(plan); XCTFail("Reopening the same folder invalidates an old repair review") } catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
            XCTAssertEqual(try Data(contentsOf: noteURL), original)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/properties.json")), originalSchema)
        }
    }
}
