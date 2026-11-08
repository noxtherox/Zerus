import XCTest
@testable import ZerusNative

final class NativeNoteRenameTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testReviewedRenameKeepsRelationsTaskLinksResourcesRevisionsHistoryAndExactUnrelatedBytes() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"foreign":{"keep":true},"Work":[{"name":"Epic","type":"relation","relationTypeKey":"Epics","relationPairId":"pair","relationInverseHidden":true}],"Epics":[{"name":"Tasks","type":"relation","relationTypeKey":"Work","relationPairId":"pair","relationMultiple":true,"relationHidden":true}]}"#
        let source = "---\r\n# foreign comment\r\nzerus-id: renamed\r\nEpic: 'zerus:epic|Epic'\r\nForeign:\r\n  nested: [one, two]\r\n---\r\n# Old\r\n\r\nKeep **body**. ![Plot](./assets/plot.png \"Caption\")\r\n[Self](Old.MD#details)\r\n"
        let epic = "---\nzerus-id: epic\nTasks: [\"Old\"]\n---\n# Epic\nKeep epic body.\n"
        let incoming = "# Incoming\r\n[[Old|Keep caption]] [[Old#details|Section caption]] [Open](../Work/Old.MD?view=1#details \"Title\")\r\n`[[Old]]` and `../Work/Old.MD`\r\n"
        let task = Data(#"{"tasks":[{"id":"task","title":"Read it","linkedNoteIds":["Work/Old.MD","missing"],"foreign":{"retain":7}},"future task"],"foreign":{"preserve":true}}"#.utf8)
        for (path, text) in [("Work/Old.MD", source), ("Epics/E.md", epic), ("Inbox/Incoming.md", incoming), (".zerus/properties.json", schema)] { try await io.write(path, data: Data(text.utf8), expected: nil) }
        try await io.write(".zerus/tasks.json", data: task, expected: nil)
        let image = Data([137,80,78,71,0,255]); try await io.write("Work/assets/plot.png", data: image, expected: nil)
        let revisions = try await io.revisionSnapshot(notePath: "Work/Old.MD")
        _ = try await io.applyRevision(io.prepareRevision(revisions, action: .create))
        let revisionIndex = try await io.read(".zerus/revisions/notes/renamed/index.json")
        let baseline = String(decoding: try await io.read("Work/Old.MD"), as: UTF8.self)
        let snapshot = try await io.relationDefinitionSnapshot()
        let plan = try await io.prepareRename(snapshot, source: "Work/Old.MD", title: "New title", renameFile: true)
        XCTAssertEqual(plan.destination, "Work/New title.MD"); XCTAssertEqual(plan.taskLinksUpdated, 1)
        let before = try await io.read("Work/Old.MD"); XCTAssertEqual(before, Data(baseline.utf8), "Preparing or Cancel must not mutate files")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/New title.MD").path))
        // A task saved during the review must reject the whole rename.
        let outside = Data(#"{"tasks":[{"id":"new","title":"New outside task","linkedNoteIds":["Work/Old.MD"]}]}"#.utf8)
        try await io.write(".zerus/tasks.json", data: outside, expected: task)
        do { _ = try await io.applyRelationMaintenance(plan.maintenance); XCTFail("A stale task review must not rename any file") }
        catch { XCTAssertTrue(error.localizedDescription.contains("tasks.json")) }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Old.MD")), Data(baseline.utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Inbox/Incoming.md")), Data(incoming.utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/New title.MD").path))
        try await io.write(".zerus/tasks.json", data: task, expected: outside)
        let saved = try await io.applyRelationMaintenance(plan.maintenance)
        let renamed = try XCTUnwrap(saved.notes.first { $0.path == "Work/New title.MD" })
        XCTAssertEqual(renamed.title, "New title"); XCTAssertEqual(renamed.stableID, "renamed")
        XCTAssertEqual(renamed.content, baseline.replacingOccurrences(of: "# Old\r\n", with: "# New title\r\n").replacingOccurrences(of: "(Old.MD#details)", with: "(./New%20title.MD#details)"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/Old.MD").path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/assets/plot.png")), image)
        let savedIncoming = try String(contentsOf: root.appendingPathComponent("Inbox/Incoming.md"), encoding: .utf8)
        XCTAssertEqual(savedIncoming, incoming.replacingOccurrences(of: "[[Old|Keep caption]]", with: "[[zerus:renamed|Keep caption]]").replacingOccurrences(of: "[[Old#details|Section caption]]", with: "[[zerus:renamed#details|Section caption]]").replacingOccurrences(of: "../Work/Old.MD?", with: "../Work/New%20title.MD?"))
        let savedEpic = try String(contentsOf: root.appendingPathComponent("Epics/E.md"), encoding: .utf8)
        XCTAssertEqual(try NativeRelationSnapshot.values(NoteDocument(path: "Epics/E.md", content: savedEpic, modified: Date()), name: "Tasks"), ["zerus:renamed|Old"])
        XCTAssertTrue(savedEpic.hasSuffix("# Epic\nKeep epic body.\n"))
        let actualTask = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))) as! [String: Any]
        let rows = actualTask["tasks"] as! [Any], first = rows[0] as! [String: Any]
        XCTAssertEqual(first["linkedNoteIds"] as? [String], ["renamed", "missing"]); XCTAssertEqual((first["foreign"] as? [String:Int])?["retain"], 7)
        XCTAssertEqual(rows[1] as? String, "future task"); XCTAssertEqual((actualTask["foreign"] as? [String:Bool])?["preserve"], true)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/revisions/notes/renamed/index.json")), revisionIndex)
        let history = try await io.historySnapshot(notePath: renamed.path)
        XCTAssertTrue(history.versions.contains { $0.content == baseline }); XCTAssertEqual(history.versions.first?.content, renamed.content)
        let reopened = try await io.revisionSnapshot(notePath: renamed.path)
        XCTAssertEqual(reopened.index.noteID, "renamed")
    }

    func testTitleOnlyRenamesPreserveLiteralExamplesUnsupportedBodyAndManagedRecordPaths() async throws {
        let io = VaultFiles(root: root!)
        let cases = [
            ("# Old\r\n\r\nBody ![Missing](assets/missing.png)\r\n", "# New\r\n\r\nBody ![Missing](assets/missing.png)\r\n"),
            ("Old\n===\n\nBody.", "# New\n\nBody."),
            ("```md\n# Example\n```\n\n# Actual\nBody.\n", "# New\n\n```md\n# Example\n```\n\n# Actual\nBody.\n"),
            ("<!-- # Example -->\n\n<script>\n# Literal\n</script>\nBody.", "# New\n\n<!-- # Example -->\n\n<script>\n# Literal\n</script>\nBody.")
        ]
        for (number, fixture) in cases.enumerated() {
            let path = "Case\(number).md", header = "---\nzerus-id: case\(number)\nForeign: keep\n---\n"
            try await io.write(path, data: Data((header + fixture.0).utf8), expected: nil)
            let snapshot = try await io.relationDefinitionSnapshot(), plan = try await io.prepareRename(snapshot, source: path, title: "New", renameFile: false)
            _ = try await io.applyRelationMaintenance(plan.maintenance)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8), header + fixture.1)
        }
        let link = try await io.createSavedLink(address: "https://example.com/path", title: "Original link")
        let index = try await io.read(".zerus/links.json"), snapshot = try await io.relationDefinitionSnapshot()
        let plan = try await io.prepareRename(snapshot, source: link.path, title: "A clearer link title", renameFile: true)
        let saved = try await io.applyRelationMaintenance(plan.maintenance), renamed = try XCTUnwrap(saved.notes.first { $0.path == link.path })
        XCTAssertEqual(plan.destination, link.path); XCTAssertEqual(renamed.title, "A clearer link title")
        XCTAssertEqual(renamed.savedLink?.address, "https://example.com/path"); XCTAssertEqual(renamed.stableID, link.stableID)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/links.json")), index)
        // A filename collision and an invalid title leave both notes intact.
        let collision = try await io.relationDefinitionSnapshot()
        do { _ = try await io.prepareRename(collision, source: "Case1.md", title: "Case0", renameFile: true); XCTFail("An occupied file must be protected") }
        catch { XCTAssertTrue(error.localizedDescription.contains("already exists")) }
        for invalid in ["Two\nlines", "Two\u{2028}lines"] {
            do { _ = try await io.prepareRename(collision, source: "Case1.md", title: invalid, renameFile: false); XCTFail("Titles must stay on one line") }
            catch { XCTAssertTrue(error.localizedDescription.contains("one line")) }
        }
        for (number, pair) in [("Plan: [draft]?*", "Plan- -draft---.md"), ("CON", "_CON.md"), ("...", "Untitled.md")].enumerated() {
            let path = "Portable\(number).md"
            try await io.write(path, data: Data("# Portable\nExisting prose.".utf8), expected: nil)
            let current = try await io.relationDefinitionSnapshot(), plan = try await io.prepareRename(current, source: path, title: pair.0, renameFile: true)
            XCTAssertEqual(plan.destination, pair.1)
            _ = try await io.applyRelationMaintenance(plan.maintenance)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(pair.1).path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Case0.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Case1.md").path))
    }

    @MainActor
    func testAnOpenEditorFollowsItsRenamedFileAndContinuesSavingWithoutRecreatingTheOldPath() async throws {
        let io = VaultFiles(root: root!); try await io.write("Original.md", data: Data("# Original\n\nExisting body.".utf8), expected: nil)
        let store = VaultStore(); await store.open(root)
        let editor = try XCTUnwrap(store.session(for: XCTUnwrap(store.notes.first)))
        let snapshot = try await store.relationDefinitionSnapshot()
        let plan = try await store.prepareRename(snapshot, source: "Original.md", title: "Renamed", renameFile: true)
        try await store.saveRelationMaintenance(plan.maintenance)
        XCTAssertEqual(editor.document.path, "Renamed.md"); XCTAssertEqual(editor.document.title, "Renamed")
        XCTAssertTrue(store.session(for: try XCTUnwrap(store.notes.first { $0.path == "Renamed.md" })) === editor)
        editor.updateBody(editor.document.parts.body + "\nTyped after renaming."); await editor.save()
        XCTAssertFalse(editor.dirty); XCTAssertNil(editor.failure)
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("Renamed.md"), encoding: .utf8).hasSuffix("Typed after renaming."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Original.md").path))
    }
}
