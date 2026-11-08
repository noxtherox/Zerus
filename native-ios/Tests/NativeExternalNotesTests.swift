import XCTest
@testable import ZerusNative

final class NativeExternalNotesTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var storage: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NativeExternal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        source = root.appendingPathComponent("Project notes.markdown"); storage = root.appendingPathComponent("Private access")
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    private func file(_ text: String = "---\r\nforeign: 'Keep: this'\r\n---\r\n# Outside\r\n\r\nBefore 😀.\r\n", bom: Bool = false) throws -> Data {
        let data = (bom ? Data([0xef, 0xbb, 0xbf]) : Data()) + Data(text.utf8)
        try data.write(to: source); return data
    }
    func testSelectedFileSavesInPlacePreservesBOMForeignYAMLAndOtherRegistrationsAcrossReopening() async throws {
        let original = try file(bom: true), store = NativeExternalNotesStore(directory: storage)
        var snapshot = try await store.open(selected: source)
        XCTAssertEqual(snapshot.bytes, original); XCTAssertTrue(snapshot.hasBOM)
        XCTAssertFalse(snapshot.content.contains("zerus-id")); XCTAssertEqual(try Data(contentsOf: source), original)
        let secondURL = root.appendingPathComponent("Another.md"), secondBytes = Data("# Other\nUnchanged".utf8)
        try secondBytes.write(to: secondURL); _ = try await store.open(selected: secondURL)
        let registry = storage.appendingPathComponent("files.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as? [String: Any])
        object["foreign"] = ["value": 42]
        var rows = try XCTUnwrap(object["entries"] as? [[String: Any]])
        for index in rows.indices { rows[index]["extension"] = "keep me" }; object["entries"] = rows
        try JSONSerialization.data(withJSONObject: object).write(to: registry, options: .atomic)
        for text in [snapshot.content + "First edit.\n", snapshot.content + "Second edit.\n"] {
            snapshot = try await store.save(snapshot, content: text)
            XCTAssertEqual(try Data(contentsOf: source), Data([0xef, 0xbb, 0xbf]) + Data(text.utf8))
        }
        let reopened = NativeExternalNotesStore(directory: storage)
        let entry = try await reopened.reopen(snapshot.entry.id)
        XCTAssertEqual(entry.entry.id, snapshot.entry.id); XCTAssertEqual(entry.bytes, try Data(contentsOf: source))
        let same = try await reopened.open(selected: source); XCTAssertEqual(same.entry.id, entry.entry.id)
        let entries = try await reopened.entries(); XCTAssertEqual(entries.count, 2)
        let final = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as? [String: Any])
        XCTAssertEqual((final["foreign"] as? [String: Int])?["value"], 42)
        XCTAssertTrue((final["entries"] as! [[String: Any]]).allSatisfy { $0["extension"] as? String == "keep me" })
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus").path))
    }
    func testChangedReplacedAndSymlinkedSourcesCannotBeOverwrittenByAnOldEditingCapability() async throws {
        for change in ["outside edit", "replacement", "symlink"] {
            let original = try file(), store = NativeExternalNotesStore(directory: storage)
            let snapshot = try await store.open(selected: source)
            let outside = root.appendingPathComponent("Protected.md"); try Data("Outside original".utf8).write(to: outside)
            if change == "outside edit" { try Data("Other editor content".utf8).write(to: source, options: .atomic) }
            else if change == "replacement" { try FileManager.default.removeItem(at: source); try original.write(to: source) }
            else { try FileManager.default.removeItem(at: source); try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside) }
            let expected = try Data(contentsOf: source)
            do { _ = try await store.save(snapshot, content: "Must not replace it"); XCTFail(change) } catch {}
            XCTAssertEqual(try Data(contentsOf: source), expected, change)
            XCTAssertEqual(try Data(contentsOf: outside), Data("Outside original".utf8))
            try FileManager.default.removeItem(at: source)
        }
    }
    @MainActor
    func testDraftRecoveryConflictReloadAndCleanExternalRefreshPreserveBothWriters() async throws {
        let original = try file(), model = NativeExternalNotesModel(directory: storage)
        let session = try await model.open(source)
        session.updateBody(session.document.parts.body + "Private draft.\n"); await session.flushDraft()
        let draftText = session.document.content; session.deactivate()
        XCTAssertEqual(try Data(contentsOf: source), original, "Draft persistence does not need an original-file write")
        let outside = original + Data("An outside edit.\n".utf8); try outside.write(to: source, options: .atomic)
        let restarted = NativeExternalNotesModel(directory: storage); await restarted.restore()
        let entry = try XCTUnwrap(restarted.entries.first), recovered = try await restarted.open(entry)
        XCTAssertEqual(recovered.document.content, draftText); XCTAssertTrue(recovered.dirty); XCTAssertTrue(recovered.conflict)
        await recovered.save(); XCTAssertEqual(try Data(contentsOf: source), outside)
        do { try await restarted.forget(entry); XCTFail("A dirty recovery draft must keep its registration") } catch {}
        try await recovered.reloadDiscardingDraft(); XCTAssertFalse(recovered.dirty); XCTAssertFalse(recovered.conflict)
        XCTAssertEqual(recovered.document.content, String(decoding: outside, as: UTF8.self))
        recovered.updateBody(recovered.document.parts.body + "Accepted edit.\n"); await recovered.save()
        let saved = try Data(contentsOf: source); XCTAssertTrue(String(decoding: saved, as: UTF8.self).contains("Accepted edit."))
        recovered.deactivate()
        let later = saved + Data("A later clean change.\n".utf8); try later.write(to: source, options: .atomic)
        let third = NativeExternalNotesModel(directory: storage); await third.restore(); let clean = try await third.open(try XCTUnwrap(third.entries.first))
        XCTAssertEqual(clean.document.content, String(decoding: later, as: UTF8.self)); XCTAssertFalse(clean.dirty); XCTAssertFalse(clean.conflict, "A clean saved draft cannot replace a newer external file on reopening")
        try await third.forget(entry); XCTAssertEqual(try Data(contentsOf: source), later)
        let removed = try await NativeExternalNotesStore(directory: storage).entries(); XCTAssertTrue(removed.isEmpty)
    }
    @MainActor
    func testCleanRetryRetainsUnavailableFailureAndLoadsExternalChangesWhenAccessReturns() async throws {
        let original = try file(), model = NativeExternalNotesModel(directory: storage)
        let session = try await model.open(source)
        let held = root.appendingPathComponent("Temporarily unavailable.markdown")
        try FileManager.default.moveItem(at: source, to: held)
        await session.refresh()
        XCTAssertNotNil(session.failure)
        await session.retry()
        XCTAssertNotNil(session.failure, "Retry must read the unavailable file before clearing its error")
        XCTAssertEqual(session.document.content, String(decoding: original, as: UTF8.self))
        XCTAssertFalse(session.dirty)
        try FileManager.default.moveItem(at: held, to: source)
        let current = original + Data("Written elsewhere while unavailable.\n".utf8)
        try current.write(to: source)
        await session.retry()
        XCTAssertNil(session.failure)
        XCTAssertEqual(session.document.content, String(decoding: current, as: UTF8.self), "A clean retry loads the returned file, including external edits")
        XCTAssertFalse(session.dirty)
        XCTAssertFalse(session.conflict)
        XCTAssertEqual(try Data(contentsOf: source), current, "Retry does not overwrite the returned file")
    }

    func testUnsupportedListsDraftsInvalidUTF8AndOversizedFilesKeepTheirOriginalBytes() async throws {
        let original = try file(), store = NativeExternalNotesStore(directory: storage), snapshot = try await store.open(selected: source)
        let registry = storage.appendingPathComponent("files.json"), good = try Data(contentsOf: registry)
        let unsupported = Data(#"{"version":99,"entries":[{"foreign":"Keep"}]}"#.utf8); try unsupported.write(to: registry, options: .atomic)
        do { _ = try await store.open(selected: source); XCTFail("A newer registry must not be replaced") } catch {}
        XCTAssertEqual(try Data(contentsOf: registry), unsupported); XCTAssertEqual(try Data(contentsOf: source), original)
        try good.write(to: registry, options: .atomic)
        let drafts = storage.appendingPathComponent("Drafts"); try FileManager.default.createDirectory(at: drafts, withIntermediateDirectories: true)
        let draftURL = drafts.appendingPathComponent(snapshot.entry.id.uuidString + ".json"), malformed = Data("unreadable draft".utf8)
        try malformed.write(to: draftURL)
        do { _ = try await store.draft(snapshot.entry.id); XCTFail("An unreadable draft cannot be discarded by loading") } catch {}
        do { try await store.forget(snapshot.entry.id); XCTFail("Removing access cannot orphan an unreadable draft") } catch {}
        XCTAssertEqual(try Data(contentsOf: draftURL), malformed)
        for bytes in [Data([0xff, 0xfe, 0x80]), Data(repeating: 65, count: 10 * 1024 * 1024 + 1)] {
            try bytes.write(to: source, options: .atomic)
            do { _ = try await store.open(selected: source); XCTFail("Only bounded UTF-8 Markdown is editable") } catch {}
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
    }
    @MainActor
    func testSavedFileBookmarkFollowsRenameWithoutCreatingASecondTrackedFile() async throws {
        _ = try file()
        let model = NativeExternalNotesModel(directory: storage), session = try await model.open(source)
        let id = session.id, presentation = session.presentationID
        session.updateBody(session.document.parts.body + "A saved edit before moving.\n"); await session.save()
        XCTAssertFalse(session.dirty); XCTAssertNil(session.failure)
        let moved = root.appendingPathComponent("Renamed original.md")
        try FileManager.default.moveItem(at: source, to: moved)
        let restarted = NativeExternalNotesModel(directory: storage); await restarted.restore()
        let entry = try XCTUnwrap(restarted.entries.first)
        let reopened = try await restarted.open(entry)
        XCTAssertEqual(reopened.id, id); XCTAssertEqual(reopened.document.path, "Renamed original.md")
        XCTAssertTrue(reopened.document.content.contains("A saved edit before moving."))
        let selectedAgain = try await restarted.open(moved); XCTAssertEqual(selectedAgain.id, id)
        XCTAssertEqual(restarted.entries.count, 1)
        let activeAgain = try await model.open(entry)
        XCTAssertTrue(activeAgain === session); XCTAssertNotEqual(activeAgain.presentationID, presentation)
        activeAgain.updateBody(activeAgain.document.parts.body + "Saved after moving.\n"); await activeAgain.save()
        XCTAssertTrue(String(decoding: try Data(contentsOf: moved), as: UTF8.self).contains("Saved after moving."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "A retained editor must never recreate the old filename")
    }

    @MainActor
    func testPrivateDraftPersistsWhileTheOriginalFileProviderHoldsAnAutosave() async throws {
        let original = try file(), model = NativeExternalNotesModel(directory: storage)
        let session = try await model.open(source)
        session.updateBody(session.document.parts.body + "First pending edit.\n"); await session.flushDraft()
        let gate = ExternalSaveGate(url: source)
        NSFileCoordinator.addFilePresenter(gate)
        defer { gate.release(); NSFileCoordinator.removeFilePresenter(gate) }
        let saving = Task { await session.save() }
        await fulfillment(of: [gate.requested], timeout: 5)
        session.updateBody(session.document.parts.body + "A later local draft.\n")
        let kept = expectation(description: "The later text reaches local recovery while the provider is still held")
        let persistence = Task { await session.flushDraft(); kept.fulfill() }
        await fulfillment(of: [kept], timeout: 2)
        XCTAssertEqual(try Data(contentsOf: source), original, "The held provider has not allowed the original write")
        gate.release()
        await persistence.value; await saving.value
        XCTAssertFalse(session.dirty); XCTAssertNil(session.failure)
        let stored = try await NativeExternalNotesStore(directory: storage).draft(session.id)
        XCTAssertEqual(stored?.content, session.document.content)
        XCTAssertEqual(stored?.baseline, try Data(contentsOf: source))
        XCTAssertTrue(String(decoding: try Data(contentsOf: source), as: UTF8.self).contains("A later local draft."))
    }

}


private final class ExternalSaveGate: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    let requested = XCTestExpectation(description: "The original file provider holds its first write")
    private let lock = NSLock()
    private var used = false
    private let semaphore = DispatchSemaphore(value: 0)
    init(url: URL) { presentedItemURL = url; super.init(); presentedItemOperationQueue.maxConcurrentOperationCount = 1 }
    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        let wait = lock.withLock { if used { return false }; used = true; return true }
        if wait { requested.fulfill(); _ = semaphore.wait(timeout: .now() + 20) }
        writer(nil)
    }
    func release() { semaphore.signal() }
}
