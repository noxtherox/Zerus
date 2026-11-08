import XCTest
@testable import ZerusNative

final class NativeBulkActionsTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testReviewedBatchPersistsReciprocalRelationsAndFieldWiseUndoAcrossRelaunchRenameAndLaterEdits() async throws {
        let io = VaultFiles(root: root)
        let a = "---\r\nOwner: \"Keep me\" # foreign comment\r\nLabels: [Original]\r\nScore: 1\r\n---\r\n# Alpha\r\n\r\nOriginal body.\r\n"
        let b = "---\nLabels: [Original]\nScore: 2\n---\n# Beta\nKeep Beta."
        let invalid = "---\nScore: 1\nScore: 2\n---\n# Invalid\nDo not change."
        for (path, content) in ["Projects/A.md": a, "Projects/B.md": b, "Projects/Invalid.md": invalid, "People/Sam.md": "# Sam\nKeep contact."] { try await io.write(path, data: Data(content.utf8), expected: nil) }
        let schema = Data(#"{"Projects":[{"name":"Score","type":"number"},{"name":"Labels","type":"list","listMultiple":true,"listOptions":["Original","Blue","Green"]},{"name":"Contacts","type":"relation","relationTypeKey":"People","relationMultiple":true,"relationInverseName":"Projects"}],"foreign":{"keep":true}}"#.utf8)
        try await io.write(".zerus/properties.json", data: schema, expected: nil)
        let snapshot = try await io.bulkSnapshot(), selected = snapshot.source.notes.filter { $0.folder == "Projects" }
        let mutation = NativeBulkMutation(pinned: true, archived: true, properties: [.init(name: "Score", value: .number("8")), .init(name: "Labels", operation: .add, value: .list(["Blue", "blue"])), .init(name: "Contacts", operation: .add, value: .list(["People/Sam.md"]))])
        let plan = try snapshot.plan(selected: selected, mutation: mutation)
        XCTAssertEqual(plan.issues.count, 1); XCTAssertTrue(plan.issues[0].reason.contains("duplicate")); XCTAssertTrue(plan.hasChanges)
        let receiptBefore = try? await io.read(NativeBulkHistory.path); XCTAssertNil(receiptBefore, "Review must not write its receipt")
        let alphaBytes = try await io.read("Projects/A.md"); XCTAssertEqual(alphaBytes, Data(a.utf8))
        // Any touched-file change after review rejects the entire batch.
        try Data((b + "\nOutside during review.").utf8).write(to: root.appendingPathComponent("Projects/B.md"), options: .atomic)
        do { _ = try await io.applyBulk(plan); XCTFail("A stale review must not apply") } catch { XCTAssertTrue(error.localizedDescription.contains("changed")) }
        let unchangedAlpha = try await io.read("Projects/A.md"), noReceipt = try? await io.read(NativeBulkHistory.path); XCTAssertEqual(unchangedAlpha, Data(a.utf8)); XCTAssertNil(noReceipt)
        let current = try await io.bulkSnapshot(), fresh = try current.plan(selected: selected, mutation: mutation)
        _ = try await io.applyBulk(fresh)
        let reopened = VaultFiles(root: root), saved = try await reopened.bulkSnapshot()
        XCTAssertEqual(saved.records.count, 1); XCTAssertEqual(saved.records[0].entries.count, 2)
        XCTAssertEqual(saved.records[0].appliedCount, 10)
        let invalidBytes = try await io.read("Projects/Invalid.md"); XCTAssertEqual(invalidBytes, Data(invalid.utf8))
        let alpha = try XCTUnwrap(saved.source.notes.first { $0.path == "Projects/A.md" }), beta = try XCTUnwrap(saved.source.notes.first { $0.path == "Projects/B.md" }), contact = try XCTUnwrap(saved.source.notes.first { $0.path == "People/Sam.md" })
        XCTAssertTrue(alpha.pinned && alpha.archived && beta.pinned && beta.archived)
        XCTAssertTrue(alpha.content.contains("Owner: \"Keep me\" # foreign comment\r\n")); XCTAssertTrue(alpha.content.hasSuffix("Original body.\r\n"))
        XCTAssertNotNil(alpha.stableID); XCTAssertNotNil(beta.stableID); XCTAssertNotNil(contact.stableID)
        let forward = try NativeRelationSnapshot.values(alpha, name: "Contacts")
        XCTAssertTrue(forward.first?.contains("zerus:" + contact.stableID!) == true)
        let inverse = try XCTUnwrap(saved.source.schema.effective(notePath: contact.path).first { $0.type == .relation })
        let links = try NativeRelationSnapshot.values(contact, name: inverse.name)
        XCTAssertEqual(links.count, 2); XCTAssertTrue(links.contains { $0.contains(alpha.stableID!) }); XCTAssertTrue(links.contains { $0.contains(beta.stableID!) })
        let object = try JSONSerialization.jsonObject(with: saved.source.schema.bytes!) as! [String: Any]
        XCTAssertNotNil(object["foreign"])
        var edited = try NativeFrontmatter(alpha.content).setting("Labels", value: .list(["Original", "Blue", "Green"]))
        edited += "A later body edit.\r\n"
        try await reopened.write(alpha.path, data: Data(edited.utf8), expected: Data(alpha.content.utf8))
        try await reopened.move(contact.path, to: "People/Renamed Sam.md", expected: Data(contact.content.utf8))
        let undoSnapshot = try await reopened.bulkSnapshot(), undo = try undoSnapshot.transition(saved.records[0].id, undo: true)
        XCTAssertTrue(undo.issues.isEmpty, undo.issues.map(\.reason).joined(separator: "; "))
        _ = try await reopened.applyBulk(undo)
        let undone = try await VaultFiles(root: root).bulkSnapshot(), undoneAlpha = try XCTUnwrap(undone.source.notes.first { $0.path == alpha.path })
        XCTAssertEqual(undone.records[0].appliedCount, 0); XCTAssertFalse(undoneAlpha.pinned || undoneAlpha.archived)
        XCTAssertEqual(NativeFrontmatter(undoneAlpha.content).entry("Labels")?.value, .list(["Original", "Green"]))
        XCTAssertEqual(NativeFrontmatter(undoneAlpha.content).entry("Score")?.value, .number("1"))
        XCTAssertTrue(undoneAlpha.content.hasSuffix("A later body edit.\r\n")); XCTAssertNil(NativeFrontmatter(undoneAlpha.content).entry("Contacts"))
        let unlinkedContact = try XCTUnwrap(undone.source.notes.first { $0.path == "People/Renamed Sam.md" })
        XCTAssertTrue(try NativeRelationSnapshot.values(unlinkedContact, name: inverse.name).isEmpty)
        _ = try await reopened.applyBulk(undone.transition(saved.records[0].id, undo: false))
        let redone = try await reopened.bulkSnapshot(), redoneAlpha = try XCTUnwrap(redone.source.notes.first { $0.path == alpha.path })
        XCTAssertEqual(redone.records[0].appliedCount, 10); XCTAssertTrue(redoneAlpha.pinned && redoneAlpha.archived)
        XCTAssertEqual(NativeFrontmatter(redoneAlpha.content).entry("Labels")?.value, .list(["Original", "Green", "Blue"]))
        XCTAssertTrue(try NativeRelationSnapshot.values(redoneAlpha, name: "Contacts").contains { $0.contains(contact.stableID!) })
        let newer = try NativeFrontmatter(redoneAlpha.content).setting("Score", value: .number("77"))
        try await reopened.write(alpha.path, data: Data(newer.utf8), expected: Data(redoneAlpha.content.utf8))
        let partial = try await reopened.bulkSnapshot().transition(saved.records[0].id, undo: true)
        XCTAssertEqual(partial.issues.count, 1); XCTAssertTrue(partial.issues[0].reason.contains("changed later"))
        _ = try await reopened.applyBulk(partial)
        let last = try await reopened.bulkSnapshot(), lastAlpha = try XCTUnwrap(last.source.notes.first { $0.path == alpha.path })
        XCTAssertEqual(last.records[0].appliedCount, 1); XCTAssertEqual(NativeFrontmatter(lastAlpha.content).entry("Score")?.value, .number("77"))
        XCTAssertTrue(lastAlpha.content.contains("A later body edit.")); XCTAssertFalse(lastAlpha.pinned)
        let fileContent = "---\nzerus-file-id: manual\nzerus-file-name: Manual.pdf\nzerus-file-kind: local\n---\n# Manual\nKeep this document connection."
        try await io.write(".zerus/files/Manual.md", data: Data(fileContent.utf8), expected: nil)
        let fileSnapshot = try await io.bulkSnapshot(), file = try XCTUnwrap(fileSnapshot.source.notes.first { $0.path == ".zerus/files/Manual.md" })
        _ = try await io.applyBulk(fileSnapshot.plan(selected: [file], mutation: .init(pinned: true)))
        let pinnedFiles = try await io.bulkSnapshot(), pinnedFile = try XCTUnwrap(pinnedFiles.source.notes.first { $0.path == file.path })
        XCTAssertTrue(pinnedFile.pinned); XCTAssertEqual(pinnedFile.fileHub, file.fileHub); XCTAssertEqual(pinnedFile.parts.body, file.parts.body)
        _ = try await io.applyBulk(pinnedFiles.transition(pinnedFiles.records[0].id, undo: true))
        let restoredFile = try await io.scan().notes.first { $0.path == file.path }!
        XCTAssertFalse(restoredFile.pinned); XCTAssertEqual(restoredFile.fileHub, file.fileHub); XCTAssertEqual(restoredFile.parts.body, file.parts.body)
        let missingBase = try await io.scan().notes.first { $0.path == alpha.path }!
        let missingText = try NativeFrontmatter(missingBase.content).setting("Contacts", value: .list(["Missing contact"]))
        try await io.write(alpha.path, data: Data(missingText.utf8), expected: Data(missingBase.content.utf8))
        let missingSnapshot = try await io.bulkSnapshot()
        _ = try await io.applyBulk(missingSnapshot.plan(selected: [missingBase], mutation: .init(properties: [.init(name: "Contacts", operation: .clear)])))
        let cleared = try await io.bulkSnapshot(), restoreMissing = try cleared.transition(cleared.records[0].id, undo: true)
        XCTAssertTrue(restoreMissing.issues.isEmpty, "Undo must restore a recorded missing reference without creating its note")
        _ = try await io.applyBulk(restoreMissing)
        let missingRestored = try await io.scan().notes.first { $0.path == alpha.path }!
        XCTAssertEqual(try NativeRelationSnapshot.values(missingRestored, name: "Contacts"), ["Missing contact"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Missing contact.md").path))
    }

    @MainActor
    func testBulkReviewRejectsObsoleteActivationsUnsavedReviewChangesAndNewerHistoryWithoutLosingDrafts() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let io = VaultFiles(root: root), original = "---\nzerus-id: one\n---\n# One\nOriginal."
        try await io.write("One.md", data: Data(original.utf8), expected: nil)
        let store = VaultStore(); await store.open(root)
        let selected = try XCTUnwrap(store.notes.first)
        let beforeSwitch = try await store.bulkSnapshot(workspace: store.workspaceID), oldPlan = try beforeSwitch.plan(selected: [selected], mutation: .init(pinned: true))
        let other = root.appendingPathComponent("Other", isDirectory: true); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await store.open(other); await store.open(root)
        do { try await store.saveBulk(oldPlan); XCTFail("Old activation should not apply") } catch {}
        let unchanged = try await io.read("One.md"); XCTAssertEqual(unchanged, Data(original.utf8))
        let current = try XCTUnwrap(store.notes.first { $0.path == "One.md" }), review = try await store.bulkSnapshot(workspace: store.workspaceID)
        let plan = try review.plan(selected: [current], mutation: .init(pinned: true)), editor = try XCTUnwrap(store.session(for: current))
        editor.updateBody("# One\nTyped after reviewing.")
        do { try await store.saveBulk(plan); XCTFail("A changed editor must invalidate the review") } catch {}
        XCTAssertTrue(editor.document.content.contains("Typed after reviewing.")); XCTAssertFalse(editor.dirty)
        let noReceipt = try? await io.read(NativeBulkHistory.path); XCTAssertFalse(editor.document.pinned); XCTAssertNil(noReceipt)
        let fresh = try await store.bulkSnapshot(workspace: store.workspaceID), commit = try fresh.plan(selected: [current], mutation: .init(pinned: true))
        try await store.saveBulk(commit)
        let receipt = try await store.bulkSnapshot(workspace: store.workspaceID), undo = try receipt.transition(receipt.records[0].id, undo: true)
        var history = try JSONSerialization.jsonObject(with: receipt.historyBytes!) as! [String: Any]; history["foreign"] = "Keep newer bytes"
        let newerBytes = try JSONSerialization.data(withJSONObject: history)
        try await io.write(NativeBulkHistory.path, data: newerBytes, expected: receipt.historyBytes)
        do { try await store.saveBulk(undo); XCTFail("A stale receipt review must not overwrite newer history") } catch {}
        let stillPinned = try await io.scan().notes.first { $0.path == "One.md" }!.pinned; XCTAssertTrue(stillPinned)
        let keptReceipt = try await io.read(NativeBulkHistory.path); XCTAssertEqual(keptReceipt, newerBytes)
        let freshUndo = try await store.bulkSnapshot(workspace: store.workspaceID)
        try await store.saveBulk(freshUndo.transition(receipt.records[0].id, undo: true))
        let kept = try JSONSerialization.jsonObject(with: await io.read(NativeBulkHistory.path)) as! [String: Any]
        XCTAssertEqual(kept["foreign"] as? String, "Keep newer bytes")
        let unsupported = Data(#"{"version":2,"records":[],"foreign":"Keep"}"#.utf8)
        try await io.write(NativeBulkHistory.path, data: unsupported, expected: try await io.read(NativeBulkHistory.path))
        do { _ = try await store.bulkSnapshot(workspace: store.workspaceID); XCTFail("A future history format must be preserved") } catch {}
        let keptUnsupported = try await io.read(NativeBulkHistory.path); XCTAssertEqual(keptUnsupported, unsupported)
    }
}
