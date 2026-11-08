import XCTest
@testable import ZerusNative

final class NativeTaskDraftsTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    @MainActor private func drafts(_ root: URL, id: UUID? = nil) throws -> NativeTaskDraftStore {
        let store = try NativeTaskDraftStore(vaultRoot: root, vaultID: id)
        let folder = store.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return store
    }
    private func write(_ value: Any, root: URL? = nil) throws {
        let file = (root ?? self.root!).appendingPathComponent(".zerus/tasks.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: .sortedKeys).write(to: file, options: .atomic)
    }

    @MainActor
    func testTaskDraftRelaunchVaultIsolationCopyCommitAndExplicitDiscardUseActualPrivateFiles() async throws {
        try write(["tasks": [Any](), "lists": [["id": "work", "name": "Work"]], "categoryOptions": ["Research"]])
        let file = root.appendingPathComponent(".zerus/tasks.json"), untouched = try Data(contentsOf: file), vaultID = UUID()
        let store = try drafts(root, id: vaultID), workspace = UUID()
        var task = NativeTask(title: ""); task.workspaceID = workspace
        let editing = NativeTaskDraftSession(task: task, store: store)
        editing.task.title = "Recovered research"
        editing.task.listID = "work"; editing.task.category = "Research"; editing.task.priority = "high"
        editing.task.date = "2026-11-07"; editing.task.dueDate = "2026-11-09"
        editing.task.linkedNoteIDs = ["retained-unavailable-note"]; editing.task.completed = true
        XCTAssertNil(editing.issue); XCTAssertEqual(try Data(contentsOf: file), untouched)
        let persisted = try XCTUnwrap(store.records.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(persisted).path))
        let reopened = try NativeTaskDraftStore(vaultRoot: root, vaultID: nil)
        XCTAssertEqual(reopened.directory, store.directory, "Removing and re-registering the same folder retains drafts")
        let relocated = root.appendingPathComponent("MovedVault")
        try FileManager.default.createDirectory(at: relocated, withIntermediateDirectories: true)
        XCTAssertEqual(try NativeTaskDraftStore(vaultRoot: relocated, vaultID: vaultID).directory, store.directory)
        let otherRoot = root.appendingPathComponent("OtherVault")
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        let other = try drafts(otherRoot)
        XCTAssertNotEqual(other.directory, store.directory); XCTAssertTrue(other.records.isEmpty)
        // A different saved vault may reuse the old location and even the same task IDs.
        let privateBytes = try Data(contentsOf: store.url(persisted)), replacementID = UUID()
        let replacement = try drafts(root, id: replacementID)
        let replacementForm = NativeTaskDraftSession(task: task, store: replacement)
        XCTAssertFalse(replacementForm.recovered, "Reusing a location cannot recover another saved vault’s private draft")
        XCTAssertEqual(replacementForm.task.title, "")
        XCTAssertTrue(replacement.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.url(persisted)), privateBytes)
        let movedStore = try NativeTaskDraftStore(vaultRoot: relocated, vaultID: vaultID)
        XCTAssertEqual(NativeTaskDraftSession(task: task, store: movedStore).task.title, "Recovered research")
        let recovered = NativeTaskDraftSession(task: task, store: reopened)
        XCTAssertTrue(recovered.recovered); XCTAssertTrue(NativeTaskData.equal(recovered.task.raw, editing.task.draftFields))
        XCTAssertEqual(recovered.task.workspaceID, workspace)
        let io = VaultFiles(root: root)
        let copy = try recovered.copyIntent()
        XCTAssertNotEqual(copy.id, task.id); XCTAssertNotNil(copy.completedAt)
        let saved = try await io.changeTasks(.save(copy, delete: false))
        // Simulate termination after the shared write, before removing the private draft.
        let interrupted = NativeTaskDraftSession(task: task, store: try NativeTaskDraftStore(vaultRoot: root, vaultID: vaultID))
        let recognized = try XCTUnwrap(interrupted.completedCopy(in: saved.tasks))
        XCTAssertEqual(recognized.id, copy.id); interrupted.committed(recognized)
        reopened.reload(); XCTAssertTrue(reopened.records.isEmpty)
        let actual = try await io.taskData(); XCTAssertEqual(actual.tasks.map(\.id), [copy.id])
        XCTAssertEqual(actual.tasks.first?.linkedNoteIDs, ["retained-unavailable-note"])
        let baseline = try XCTUnwrap(actual.tasks.first), afterSave = try Data(contentsOf: file)
        let discard = NativeTaskDraftSession(task: baseline, store: reopened, canonical: baseline)
        discard.task.title = "Discard this change"
        XCTAssertEqual(reopened.records.count, 1)
        try discard.discard(); discard.keep()
        XCTAssertTrue(reopened.records.isEmpty, "Disappearance after discard cannot recreate the draft")
        XCTAssertEqual(try Data(contentsOf: file), afterSave)
        // Future or malformed draft files remain shareable without replacing their contents.
        let future = reopened.directory.appendingPathComponent(UUID().uuidString + ".json")
        let futureBytes = Data("{\"version\":99,\"future\":true}".utf8); try futureBytes.write(to: future)
        reopened.reload(); XCTAssertTrue(reopened.unreadable.contains(future)); XCTAssertEqual(try Data(contentsOf: future), futureBytes)
        // Earlier versions could bind two saved IDs to one folder without recording draft ownership.
        let independent = NativeTaskDraftSession(task: task, store: replacement)
        independent.task.title = "Replacement vault draft"
        let independentRecord = try XCTUnwrap(independent.record)
        let independentBytes = try Data(contentsOf: replacement.url(independentRecord))
        let descriptor = replacement.directory.appendingPathComponent("vault.json")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: descriptor)) as? [String: Any])
        legacy["vaultIDs"] = [replacementID.uuidString.lowercased(), UUID().uuidString.lowercased()]
        let ambiguousBytes = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
        try ambiguousBytes.write(to: descriptor, options: .atomic)
        XCTAssertThrowsError(try NativeTaskDraftStore(vaultRoot: root, vaultID: replacementID))
        XCTAssertEqual(try Data(contentsOf: descriptor), ambiguousBytes)
        XCTAssertEqual(try Data(contentsOf: replacement.url(independentRecord)), independentBytes)
    }

    @MainActor
    func testConcurrentDraftVersionsAndExternalTaskEditsPreserveBothIntentsAndForeignData() async throws {
        let original: [String: Any] = ["id": "a", "title": "Original", "createdAt": "2026-11-01T12:00:00Z", "priority": "none", "foreign": ["original": true]]
        try write(["tasks": [original], "foreignEnvelope": 17])
        let io = VaultFiles(root: root), initial = try await io.taskData(), baseline = try XCTUnwrap(initial.tasks.first), store = try drafts(root)
        let first = NativeTaskDraftSession(task: baseline, store: store, canonical: baseline)
        first.task.title = "First window"
        let second = NativeTaskDraftSession(task: baseline, store: try NativeTaskDraftStore(vaultRoot: root, vaultID: nil), canonical: baseline)
        first.task.title = "Newer first window"
        second.task.title = "Second window"
        store.reload(); XCTAssertEqual(Set(store.records.map { $0.task.title }), ["Newer first window", "Second window"])
        XCTAssertNotNil(second.issue)
        let staleRecord = try XCTUnwrap(first.record)
        first.task.priority = "high"
        XCTAssertFalse(try store.remove(staleRecord), "A stale discard cannot delete a newer version")
        var external = original; external["priority"] = "low"; external["foreign"] = ["external": true]
        try write(["tasks": [external], "foreignEnvelope": 19])
        let currentData = try await io.taskData(), current = try XCTUnwrap(currentData.tasks.first)
        let recovered = NativeTaskDraftSession(task: baseline, store: store, canonical: current, recovered: try XCTUnwrap(second.record))
        XCTAssertEqual(recovered.task.priority, "low", "Independent outside edits rebase into the recovered form")
        let merged = try await io.changeTasks(.save(recovered.task, delete: false))
        XCTAssertEqual(merged.tasks.first?.title, "Second window"); XCTAssertEqual(merged.tasks.first?.priority, "low")
        XCTAssertEqual(merged.tasks.first?.raw["foreign"] as? [String: Bool], ["external": true]); XCTAssertEqual(merged.object["foreignEnvelope"] as? Int, 19)
        recovered.committed(try XCTUnwrap(merged.tasks.first)); store.reload()
        XCTAssertEqual(store.records.map { $0.task.title }, ["Newer first window"])
        let bytes = try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))
        do { _ = try await io.changeTasks(.save(first.task, delete: false)); XCTFail("Conflicting changes must retain the shared task and private draft") } catch {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), bytes)
        store.reload(); XCTAssertEqual(store.records.first?.task.priority, "high")
        // Changing a staged copy must use a fresh identity rather than collide with a previously committed intent.
        let staged = try first.copyIntent(); first.task.title = "Changed copy intent"
        let changedCopy = try first.copyIntent(); XCTAssertNotEqual(changedCopy.id, staged.id)
        first.task.listID = "deleted-list"
        let beforeFailure = try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))
        do { _ = try await io.changeTasks(.save(first.copyIntent(), delete: false)); XCTFail("Deleted lists cannot be recreated by recovery") } catch {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), beforeFailure)
        XCTAssertEqual(store.records.first?.task.listID, "deleted-list")
        let vault = VaultStore(); await vault.open(root)
        var stale = first.task; stale.workspaceID = vault.workspaceID
        let otherRoot = root.appendingPathComponent("Other"); try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        await vault.open(otherRoot); let otherFolder = vault.taskDraftStore?.directory
        await vault.open(root)
        if let otherFolder { addTeardownBlock { try? FileManager.default.removeItem(at: otherFolder) } }
        let accepted = await vault.saveTask(stale); XCTAssertFalse(accepted)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), beforeFailure)
    }
}
