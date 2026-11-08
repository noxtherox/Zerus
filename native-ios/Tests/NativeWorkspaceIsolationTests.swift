import XCTest
import Combine
@testable import ZerusNative

final class NativeWorkspaceIsolationTests: XCTestCase {
    private var root: URL!
    private var bookmark: Data?
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        bookmark = UserDefaults.standard.data(forKey: "zerus.native.vault.bookmark")
    }
    override func tearDownWithError() throws {
        if let bookmark { UserDefaults.standard.set(bookmark, forKey: "zerus.native.vault.bookmark") }
        else { UserDefaults.standard.removeObject(forKey: "zerus.native.vault.bookmark") }
        try FileManager.default.removeItem(at: root)
    }
    private func vaults() async throws -> (VaultFiles, VaultFiles) {
        let a = VaultFiles(root: root.appendingPathComponent("A")), b = VaultFiles(root: root.appendingPathComponent("B"))
        let shared = Data("---\nzerus-id: shared\n---\n# Shared\nOriginal in this vault.\n".utf8)
        let tasks = Data(#"{"tasks":[{"id":"same-task","title":"Original task","completed":false}],"foreign":{"keep":true}}"#.utf8)
        for io in [a, b] { try await io.write("Shared.md", data: shared, expected: nil); try await io.write(".zerus/tasks.json", data: tasks, expected: nil) }
        return (a, b)
    }
    @MainActor
    func testRetainedEditorAndTaskCannotMutateAnotherVaultEvenWithIdenticalPathsAndIDs() async throws {
        let (a, b) = try await vaults(), store = VaultStore()
        let original = try await a.read("Shared.md"), tasks = try await b.read(".zerus/tasks.json")
        await store.open(root.appendingPathComponent("A"))
        let note = try XCTUnwrap(store.notes.first), session = try XCTUnwrap(store.session(for: note))
        let oldSchema = try await store.schemaSnapshot(), oldWorkspace = store.workspaceID
        let oldRevisions = try await store.revisionSnapshot(note: note)
        let oldRevisionPlan = try await store.prepareRevision(oldRevisions, action: .create)
        var task = try XCTUnwrap(store.tasks.first)
        await store.open(root.appendingPathComponent("B"))
        do { try await store.saveRevision(oldRevisionPlan); XCTFail("A retained revision review must not save in a new vault") }
        catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
        session.updateBody("# Shared\nA late edit from the previous editor.\n")
        await session.save()
        await store.duplicate(note)
        await store.setFlag("zerus-pinned", note: note, value: true)
        await store.move(note, trash: true)
        task.title = "A late task from the previous vault"; await store.saveTask(task)
        let diskA = try await a.read("Shared.md"), snapshotB = try await b.scan(), tasksB = try await b.read(".zerus/tasks.json")
        XCTAssertEqual(diskA, original)
        XCTAssertEqual(snapshotB.notes.map(\.path), ["Shared.md"])
        XCTAssertEqual(snapshotB.notes.first?.content, String(decoding: original, as: UTF8.self))
        XCTAssertEqual(store.notes.map(\.path), ["Shared.md"])
        XCTAssertEqual(store.notes.first?.content, String(decoding: original, as: UTF8.self))
        XCTAssertEqual(tasksB, tasks); XCTAssertEqual(store.tasks.first?.title, "Original task")
        XCTAssertNil(store.error, "A stale view must not put its error over the new workspace")
        let lateNote = await store.createNote(title: "Late note", workspace: oldWorkspace)
        let lateImage = await store.importImage(Data([0, 255, 17]), workspace: oldWorkspace)
        XCTAssertNil(lateNote); XCTAssertNil(lateImage)
        await store.open(root.appendingPathComponent("A"))
        XCTAssertNotEqual(store.workspaceID, oldWorkspace)
        do { try await store.saveRevision(oldRevisionPlan); XCTFail("Returning to the same root must not reactivate a revision review") }
        catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
        do {
            try await store.saveSchema(snapshot: oldSchema, owner: "", originalName: nil, definition: NativePropertyDefinition(name: "Stale", type: .text))
            XCTFail("Returning to the same root must not reactivate a previous review")
        } catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
        await store.duplicate(note)
        XCTAssertNil(store.session(for: note))
        let finalA = try await a.scan(), finalB = try await b.scan()
        XCTAssertEqual(finalA.notes.map(\.path), ["Shared.md"]); XCTAssertEqual(finalB.notes.map(\.path), ["Shared.md"])
        XCTAssertFalse(finalA.files.contains { $0.hasPrefix("assets/") }); XCTAssertFalse(finalB.files.contains { $0.hasPrefix("assets/") })
        let currentNote = try XCTUnwrap(store.notes.first), currentEditor = try XCTUnwrap(store.session(for: currentNote))
        await store.refresh()
        currentEditor.updateBody("# Shared\nCurrent workspace still saves after refresh.\n")
        await currentEditor.save()
        XCTAssertFalse(currentEditor.dirty); XCTAssertNil(currentEditor.failure)
    }
    @MainActor
    func testPendingCreateCompletesOnlyInItsOriginalVaultAndReturnsNoNewWorkspaceNote() async throws {
        let (a, b) = try await vaults(), store = VaultStore()
        await store.open(root.appendingPathComponent("A"))
        let gate = FileWriteGate(url: root.appendingPathComponent("A/Created in A.md"))
        defer { gate.release() }
        await fulfillment(of: [gate.acquired], timeout: 5)
        let started = expectation(description: "Create entered the original workspace")
        let creation = Task { @MainActor in
            started.fulfill()
            return await store.createNote(title: "Created in A", body: "Captured from A.")
        }
        await fulfillment(of: [started], timeout: 5)
        await store.open(root.appendingPathComponent("B"))
        gate.release()
        let result = await creation.value
        await fulfillment(of: [gate.finished], timeout: 5)
        XCTAssertNil(result, "The caller must not open an old-vault result in the new workspace")
        XCTAssertEqual(store.notes.map(\.path), ["Shared.md"])
        let snapshotA = try await a.scan(), snapshotB = try await b.scan()
        XCTAssertEqual(Set(snapshotA.notes.map(\.path)), ["Shared.md", "Created in A.md"])
        XCTAssertEqual(snapshotB.notes.map(\.path), ["Shared.md"])
        XCTAssertNil(store.error)
    }
    @MainActor
    func testExternalRefreshFinishingAfterVaultSwitchCannotPublishOrCaptureTheOldScan() async throws {
        let (a, _) = try await vaults(), store = VaultStore()
        await store.open(root.appendingPathComponent("A"))
        let original = try await a.read("Shared.md")
        let external = String(decoding: original, as: UTF8.self) + "\nExternal edit before switching.\n"
        try Data(external.utf8).write(to: root.appendingPathComponent("A/Shared.md"), options: .atomic)
        let gate = FileWriteGate(url: root.appendingPathComponent("A/Shared.md"))
        defer { gate.release() }
        await fulfillment(of: [gate.acquired], timeout: 5)
        let began = expectation(description: "Refresh began reading the old vault")
        let observation = store.$loading.filter { $0 }.prefix(1).sink { _ in began.fulfill() }
        defer { observation.cancel() }
        let refresh = Task { @MainActor in await store.refresh() }
        await fulfillment(of: [began], timeout: 5)
        await store.open(root.appendingPathComponent("B"))
        let expected = store.notes
        gate.release(); await refresh.value
        await fulfillment(of: [gate.finished], timeout: 5)
        XCTAssertEqual(store.root, root.appendingPathComponent("B"))
        XCTAssertEqual(store.notes, expected)
        XCTAssertNil(store.historyWarning); XCTAssertNil(store.error)
        let history = try await a.historySnapshot(notePath: "Shared.md")
        XCTAssertTrue(history.records.isEmpty, "A stale scan must not create external history after its origin vault has been replaced")
    }
    @MainActor
    func testFlushWaitsForAnAlreadyRunningCoordinatedSave() async throws {
        let (a, _) = try await vaults(), store = VaultStore()
        await store.open(root.appendingPathComponent("A"))
        let session = try XCTUnwrap(store.session(for: try XCTUnwrap(store.notes.first)))
        let gate = FileWriteGate(url: root.appendingPathComponent("A/Shared.md"))
        defer { gate.release() }
        await fulfillment(of: [gate.acquired], timeout: 5)
        let saving = expectation(description: "The editor began its actual save")
        let observation = session.$saving.filter { $0 }.prefix(1).sink { _ in saving.fulfill() }
        defer { observation.cancel() }
        session.updateBody("# Shared\nThe latest saved text.\n")
        let save = Task { @MainActor in await session.save() }
        await fulfillment(of: [saving], timeout: 5)
        session.updateBody("# Shared\nThe final edit made during the save.\n")
        let premature = expectation(description: "Flush cannot finish while the write is coordinated elsewhere"); premature.isInverted = true
        var checking = true
        let flush = Task { @MainActor in await store.flush(); if checking { premature.fulfill() } }
        await fulfillment(of: [premature], timeout: 0.15)
        checking = false
        gate.release()
        await flush.value; await save.value
        await fulfillment(of: [gate.finished], timeout: 5)
        let written = try await a.read("Shared.md")
        XCTAssertEqual(String(decoding: written, as: UTF8.self), "---\nzerus-id: shared\n---\n# Shared\nThe final edit made during the save.\n")
        XCTAssertFalse(session.dirty); XCTAssertFalse(session.saving); XCTAssertNil(session.failure)
    }
}

/// Holds the real coordination boundary, without replacing any production IO.
final class FileWriteGate: @unchecked Sendable {
    let acquired = XCTestExpectation(description: "File coordination acquired")
    let finished = XCTestExpectation(description: "File coordination released")
    private let semaphore = DispatchSemaphore(value: 0)
    init(url: URL) {
        DispatchQueue.global().async { [self] in
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { _ in
                acquired.fulfill()
                _ = semaphore.wait(timeout: .now() + 20)
            }
            finished.fulfill()
        }
    }
    func release() { semaphore.signal() }
}
