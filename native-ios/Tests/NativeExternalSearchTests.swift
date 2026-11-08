import XCTest
@testable import ZerusNative

final class NativeExternalSearchTests: XCTestCase {
    @MainActor
    func testExternalBodySearchFiltersAndFreshReadsKeepOriginalRegistryAndVaultBytesUnchanged() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vaultURL = root.appendingPathComponent("Vault"), project = root.appendingPathComponent("Project"), storage = root.appendingPathComponent("Private")
        for url in [vaultURL, project] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        let source = project.appendingPathComponent("Café.markdown"), vaultNote = vaultURL.appendingPathComponent("Café.md")
        let text = "---\r\nzerus-id: same-id\r\nstatus: Ready\r\nscore: 42.00\r\nforeign: 'Keep: exact'\r\n---\r\n# Café outside\r\n\r\nNebula [readable alias](https://example.com/private-destination).\r\n"
        let bytes = Data([0xef,0xbb,0xbf]) + Data(text.utf8), vaultBytes = Data("---\nzerus-id: same-id\n---\n# Vault nebula\n".utf8)
        try bytes.write(to: source); try vaultBytes.write(to: vaultNote)
        let external = NativeExternalNotesModel(directory: storage), session = try await external.open(source)
        let registry = try Data(contentsOf: storage.appendingPathComponent("files.json"))
        let vault = VaultStore(); await vault.open(vaultURL)
        let engine = NativeSearchEngine()
        try await engine.rebuild(vault.searchSources(), supplement: .init(files: [], conversations: [], problems: []))
        await external.refreshSearchIndex(); try await engine.replaceExternal(external.searchRecords, workspace: vault.workspaceID)
        let all = try await engine.search(workspace: vault.workspaceID, query: "nebula", filters: .init(), recent: [])
        XCTAssertEqual(Set(all.items.map(\.collection)), [.notes, .external])
        let outside = try XCTUnwrap(all.items.first { $0.collection == .external })
        XCTAssertEqual(outside.id, "external:" + session.id.uuidString)
        XCTAssertTrue(outside.preview.contains("readable alias")); XCTAssertFalse(outside.preview.contains("private-destination"))
        var filters = NativeSearchFilters(); filters.collection = .external; filters.property = "score"; filters.value = "42"; filters.folder = "Project"
        let filtered = try await engine.search(workspace: vault.workspaceID, query: "cafe", filters: filters, recent: [])
        XCTAssertEqual(filtered.items.map(\.id), [outside.id])
        XCTAssertEqual(try Data(contentsOf: source), bytes); XCTAssertEqual(try Data(contentsOf: vaultNote), vaultBytes)
        XCTAssertEqual(try Data(contentsOf: storage.appendingPathComponent("files.json")), registry)
        let changed = Data(text.replacingOccurrences(of: "Nebula", with: "Fresh pulsar").utf8)
        try changed.write(to: source)
        await external.refreshSearchIndex(); try await engine.replaceExternal(external.searchRecords, workspace: vault.workspaceID)
        let refreshed = try await engine.search(workspace: vault.workspaceID, query: "fresh pulsar", filters: .init(), recent: [])
        XCTAssertEqual(refreshed.items.map(\.id), [outside.id], "Search must refresh a clean registered file without adopting or saving its open editor")
        XCTAssertEqual(session.document.content, text)
        let freshContext = try await external.searchRecord(session.id)
        XCTAssertEqual(freshContext.document?.content, String(decoding: changed, as: UTF8.self))
        XCTAssertEqual(try Data(contentsOf: source), changed)
        XCTAssertEqual(try Data(contentsOf: storage.appendingPathComponent("files.json")), registry)
    }

    @MainActor
    func testSlowProviderDoesNotBlockHealthySearchAndForgottenConnectionsCannotReappear() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let slowURL = root.appendingPathComponent("Slow.md"), fastURL = root.appendingPathComponent("Fast.md")
        let slowBytes = Data("# Waiting outside\n\nSlow secret.".utf8)
        try slowBytes.write(to: slowURL); try Data("# Original healthy".utf8).write(to: fastURL)
        let external = NativeExternalNotesModel(directory: root.appendingPathComponent("Private"))
        let slow = try await external.open(slowURL); _ = try await external.open(fastURL)
        let fastBytes = Data("# Healthy outside\n\nFresh pulsar.".utf8); try fastBytes.write(to: fastURL)
        let gate = ExternalSearchProviderGate(url: slowURL)
        NSFileCoordinator.addFilePresenter(gate); defer { gate.release(); NSFileCoordinator.removeFilePresenter(gate) }
        let index = Task { await external.refreshSearchIndex() }
        await fulfillment(of: [gate.requested], timeout: 3)
        let deadline = ContinuousClock.now + .seconds(3)
        while !external.searchRecords.contains(where: { $0.document?.content.contains("Fresh pulsar") == true }), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(external.searchRecords.contains { $0.document?.content.contains("Fresh pulsar") == true })
        XCTAssertTrue(external.searching, "A healthy file becomes searchable while the unrelated original is still held")
        let canceledRefresh = Task { withUnsafeCurrentTask { $0?.cancel() }; await external.refreshSearchIndex() }
        await canceledRefresh.value; await index.value
        XCTAssertFalse(external.searching, "A canceled replacement refresh must not leave the prior progress indicator stuck")
        let restarted = Task { await external.refreshSearchIndex() }
        let restartDeadline = ContinuousClock.now + .seconds(2)
        while !external.searching, ContinuousClock.now < restartDeadline { try await Task.sleep(for: .milliseconds(20)) }
        let forgotten = expectation(description: "Stop tracking is independent of a blocked search reader")
        let remove = Task { try await external.forget(slow.snapshot.entry); forgotten.fulfill() }
        let result = await XCTWaiter.fulfillment(of: [forgotten], timeout: 2)
        gate.release(); try await remove.value; await restarted.value
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(external.searchRecords.contains { $0.entry.id == slow.id })
        let engine = NativeSearchEngine(), workspace = UUID()
        try await engine.rebuild(.init(workspaceID: workspace, notes: [], drafts: [], tasks: []), supplement: .init(files: [], conversations: [], problems: []))
        try await engine.replaceExternal(external.searchRecords, workspace: workspace)
        let stale = try await engine.search(workspace: workspace, query: "slow secret", filters: .init(), recent: [])
        XCTAssertTrue(stale.items.isEmpty)
        XCTAssertEqual(try Data(contentsOf: slowURL), slowBytes); XCTAssertEqual(try Data(contentsOf: fastURL), fastBytes)
    }

    @MainActor
    func testProviderTimeoutKeepsRealDraftSearchableAcrossModelRelaunchWithoutSavingTheOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Draft.md"), storage = root.appendingPathComponent("Private"), bytes = Data("---\nforeign: keep\n---\n# Original\n".utf8)
        try bytes.write(to: source)
        let external = NativeExternalNotesModel(directory: storage), session = try await external.open(source)
        session.updateBody("# Recovery draft\n\nInitial local writing."); await session.flushDraft()
        let changed = Data("---\nforeign: keep\n---\n# Changed by another editor\n".utf8)
        try changed.write(to: source); await session.refresh()
        XCTAssertTrue(session.conflict)
        defer { session.deactivate() }
        let gate = ExternalSearchProviderGate(url: source)
        NSFileCoordinator.addFilePresenter(gate); defer { gate.release(); NSFileCoordinator.removeFilePresenter(gate) }
        let reader = Task { await external.refreshSearchIndex() }
        await fulfillment(of: [gate.requested], timeout: 3)
        session.updateBody("# Recovery draft\n\nUnsent zenith writing.")
        let kept = expectation(description: "Writing reaches private recovery while search waits on the source")
        let keep = Task { await session.flushDraft(); kept.fulfill() }
        let keptResult = await XCTWaiter.fulfillment(of: [kept], timeout: 2)
        await keep.value; XCTAssertEqual(keptResult, .completed)
        let draftStore = NativeExternalNotesStore(directory: storage), draft = try await draftStore.draft(session.id)
        XCTAssertEqual(draft?.content, session.document.content)
        let registry = try Data(contentsOf: storage.appendingPathComponent("files.json"))
        await reader.value
        let restored = NativeExternalNotesModel(directory: storage)
        await restored.refreshSearchIndex()
        let record = try XCTUnwrap(restored.searchRecords.first)
        XCTAssertTrue(record.draft); XCTAssertNotNil(record.issue)
        XCTAssertTrue(record.document?.content.contains("Unsent zenith") == true)
        let context = try await restored.searchRecord(session.id)
        XCTAssertEqual(context.document?.content, draft?.content)
        XCTAssertEqual(try Data(contentsOf: source), changed)
        XCTAssertEqual(try Data(contentsOf: storage.appendingPathComponent("files.json")), registry)
        let after = try await draftStore.draft(session.id)
        XCTAssertEqual(after?.content, draft?.content); XCTAssertEqual(after?.baseline, draft?.baseline); XCTAssertEqual(after?.updated, draft?.updated)
        gate.release(); await session.save(); await session.flushDraft()
        XCTAssertTrue(session.conflict)
        XCTAssertEqual(try Data(contentsOf: source), changed, "Search and recovery must never resolve an original-file conflict by saving the kept draft")
    }
}

private final class ExternalSearchProviderGate: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    let requested = XCTestExpectation(description: "The actual provider receives the indexed file read")
    private let lock = NSLock()
    private var waiting: [@Sendable (Error?) -> Void] = []
    private var released = false
    private var reported = false
    init(url: URL) { presentedItemURL = url; super.init(); presentedItemOperationQueue.maxConcurrentOperationCount = 1 }
    func savePresentedItemChanges(completionHandler: @escaping @Sendable (Error?) -> Void) {
        lock.lock(); let first = !reported; reported = true
        if released { lock.unlock(); completionHandler(nil) }
        else { waiting.append(completionHandler); lock.unlock() }
        if first { requested.fulfill() }
    }
    func release() { lock.lock(); released = true; let callbacks = waiting; waiting = []; lock.unlock(); callbacks.forEach { $0(nil) } }
}
