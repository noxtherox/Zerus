import XCTest
import CryptoKit
@testable import ZerusNative

final class NativeExternalHistoryTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func disk(_ path: String, _ text: String) throws { try disk(path, Data(text.utf8)) }
    private func disk(_ path: String, _ bytes: Data) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file, options: .atomic)
    }
    private func text(_ body: String, id: String = "external-note") -> String { "---\nzerus-id: \(id)\nforeign: {nested: true}\n---\n# External\n\n" + body }
    private func reconcile(_ io: VaultFiles, _ previous: VaultSnapshot) async throws -> NativeExternalHistoryResult {
        try await io.reconcileExternalHistory(previous: previous.notes, scanned: io.scan())
    }

    func testObservedLegacyEditPreservesForeignBytesDeduplicatesAndRecordsARevert() async throws {
        let io = VaultFiles(root: root)
        let before = "---\nforeign: {nested: true} # Keep this comment\n---\n# Legacy\n\nOld 😀 text\n"
        let after = before.replacingOccurrences(of: "Old 😀", with: "Changed 🇵🇹")
        try disk("Legacy.md", before)
        let basis = try await io.scan()
        try disk("Legacy.md", after)
        let result = try await reconcile(io, basis)
        XCTAssertTrue(result.warnings.isEmpty); XCTAssertEqual(result.addedVersions, 2)
        let note = try XCTUnwrap(result.snapshot.notes.first), id = try XCTUnwrap(note.stableID)
        XCTAssertEqual(note.parts.body, NoteDocument.split(after).body)
        XCTAssertTrue(note.content.contains("foreign: {nested: true} # Keep this comment"))
        var history = try await io.historySnapshot(notePath: note.path)
        XCTAssertEqual(Set(history.versions.compactMap(\.content)), [before, note.content])
        XCTAssertTrue(history.versions.allSatisfy { $0.source == "external" })
        // A second client can report the same before/after pair; the saved tip
        // is authoritative and must not produce duplicate versions.
        let duplicate = try await reconcile(io, basis)
        XCTAssertEqual(duplicate.addedVersions, 0)
        let reverted = text("Old 😀 text\n", id: id)
        try disk(note.path, reverted)
        let revert = try await reconcile(io, result.snapshot)
        XCTAssertEqual(revert.addedVersions, 1)
        history = try await io.historySnapshot(notePath: note.path)
        XCTAssertEqual(history.versions.count, 3)
        XCTAssertEqual(history.versions.first?.content, reverted)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(note.path), encoding: .utf8), reverted)
    }

    func testMovesKeepIdentityAndDuplicateIdentitiesDoNotAcquireHistory() async throws {
        let io = VaultFiles(root: root), old = text("Original")
        try disk("Old.md", old)
        let basis = try await io.scan()
        try FileManager.default.removeItem(at: root.appendingPathComponent("Old.md"))
        let moved = text("Changed while moving")
        try disk("Work/Moved.md", moved)
        let result = try await reconcile(io, basis)
        XCTAssertEqual(result.addedVersions, 2); XCTAssertTrue(result.warnings.isEmpty)
        let history = try await io.historySnapshot(notePath: "Work/Moved.md")
        XCTAssertEqual(Set(history.versions.compactMap(\.content)), [old, moved])
        try disk("Copy.md", moved)
        try disk("Work/Moved.md", text("Ambiguous edit"))
        let duplicate = try await reconcile(io, result.snapshot)
        XCTAssertEqual(duplicate.addedVersions, 0); XCTAssertFalse(duplicate.warnings.isEmpty)
        let unchanged = try await io.historySnapshot(notePath: "Work/Moved.md")
        XCTAssertEqual(unchanged.records, history.records)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/Moved.md"), encoding: .utf8), text("Ambiguous edit"))
    }

    func testColdLaunchUsesPersistedTipAndDisabledCaptureDoesNotRewriteNotes() async throws {
        let io = VaultFiles(root: root), old = text("Old"), native = text("Native"), external = text("Changed while closed")
        try disk("Note.md", old)
        try await io.write("Note.md", data: Data(native.utf8), expected: Data(old.utf8))
        try disk("Note.md", external)
        let reopened = VaultFiles(root: root)
        let captured = try await reopened.reconcileExternalHistory(previous: [], scanned: reopened.scan())
        XCTAssertEqual(captured.addedVersions, 1)
        let history = try await reopened.historySnapshot(notePath: "Note.md")
        XCTAssertEqual(history.versions.first?.content, external)
        try disk(".zerus/history-settings.json", "{\"enabled\":false,\"checkpointLimit\":null}")
        let disabled = text("Do not capture")
        try disk("Note.md", disabled)
        let result = try await reconcile(reopened, captured.snapshot)
        XCTAssertEqual(result.addedVersions, 0); XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Note.md"), encoding: .utf8), disabled)
        let unchanged = try await reopened.historySnapshot(notePath: "Note.md")
        XCTAssertEqual(unchanged.records, history.records)
    }

    func testHistoryFailureRetainsObservedBaselineAcrossANativeSaveAndExplicitClearCancelsRetry() async throws {
        let io = VaultFiles(root: root), old = text("Original observed state"), outside = text("Outside edit"), native = text("Subsequent native edit")
        try disk("Note.md", old)
        let basis = try await io.scan()
        try disk("Note.md", outside); try disk(".zerus/history-settings.json", "unsupported")
        let failed = try await reconcile(io, basis)
        XCTAssertEqual(failed.addedVersions, 0); XCTAssertFalse(failed.warnings.isEmpty)
        XCTAssertEqual(failed.snapshot.notes.first?.content, outside)
        try disk(".zerus/history-settings.json", "{\"enabled\":true,\"checkpointLimit\":null}")
        try await io.write("Note.md", data: Data(native.utf8), expected: Data(outside.utf8))
        let retry = try await reconcile(io, failed.snapshot)
        XCTAssertTrue(retry.warnings.isEmpty); XCTAssertEqual(retry.addedVersions, 1)
        let history = try await io.historySnapshot(notePath: "Note.md")
        XCTAssertEqual(history.versions.count, 3)
        XCTAssertEqual(history.versions.filter { $0.content == native }.count, 1)
        XCTAssertTrue(history.versions.contains { $0.content == old })
        XCTAssertEqual(history.versions.first?.content, native)
        // A deliberate clear must not resurrect a queued earlier version.
        try disk("Note.md", text("Another external edit")); try disk(".zerus/history-settings.json", "unsupported")
        let queued = try await reconcile(io, retry.snapshot)
        XCTAssertFalse(queued.warnings.isEmpty)
        try disk(".zerus/history-settings.json", "{\"enabled\":true,\"checkpointLimit\":null}")
        let snapshot = try await io.historyMaintenanceSnapshot()
        let clear = try await io.prepareHistoryMaintenance(snapshot, intent: .clearAll)
        let cleared = try await io.applyHistoryMaintenance(clear)
        let refresh = try await reconcile(io, cleared)
        XCTAssertEqual(refresh.addedVersions, 0)
        let empty = try await io.historySnapshot(notePath: "Note.md")
        XCTAssertTrue(empty.records.isEmpty)
    }

    func testExternalImageReplacementReusesFrozenEarlierBytesAndMarksUnknownBaselinesIncomplete() async throws {
        let io = VaultFiles(root: root), image = "![Picture](assets/picture.png)", old = text("Old\n" + image), first = text("First\n" + image), after = text("External\n" + image)
        let originalBytes = Data([1,2,3,4]), replacedBytes = Data([9,8,7,6])
        try disk("assets/picture.png", originalBytes); try disk("Note.md", old)
        try await io.write("Note.md", data: Data(first.utf8), expected: Data(old.utf8))
        let metadataFirst = first.replacingOccurrences(of: "foreign: {nested: true}", with: "foreign: {nested: true}\nzerus-pinned: true")
        try disk("Note.md", metadataFirst)
        let basis = try await io.scan()
        try disk("assets/picture.png", replacedBytes); try disk("Note.md", after)
        _ = try await reconcile(io, basis)
        let history = try await io.historySnapshot(notePath: "Note.md")
        let oldVersion = try XCTUnwrap(history.versions.first { $0.content == metadataFirst })
        let newVersion = try XCTUnwrap(history.versions.first { $0.content == after })
        let oldImage = try XCTUnwrap((oldVersion.object["images"] as? [[String: Any]])?.first?["hash"] as? String)
        let newImage = try XCTUnwrap((newVersion.object["images"] as? [[String: Any]])?.first?["hash"] as? String)
        XCTAssertNotEqual(oldImage, newImage)
        XCTAssertFalse(oldVersion.incomplete)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/history/blobs/" + oldImage)), originalBytes)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/history/blobs/" + newImage)), replacedBytes)
        try disk("Unknown.md", text("Before\n" + image, id: "unknown-image"))
        let unknownBasis = try await io.scan()
        try disk("Unknown.md", text("After\n" + image, id: "unknown-image"))
        _ = try await reconcile(io, unknownBasis)
        let unknown = try await io.historySnapshot(notePath: "Unknown.md")
        let baseline = try XCTUnwrap(unknown.versions.first { $0.label == "History started" })
        XCTAssertTrue(baseline.incomplete)
        XCTAssertTrue((baseline.object["images"] as? [[String: Any]])?.first?["hash"] is NSNull)
        let preview = try await io.historyPreview(baseline)
        XCTAssertFalse(MarkdownText.imageReferences(NoteDocument.split(preview).body).contains("assets/picture.png"), "An unavailable historical image must never fall back to the current image bytes")
    }

    @MainActor
    func testRefreshKeepsDirtyDraftsAndFollowsCleanMovedEditorsWithoutReusingAliasesForNewNotes() async throws {
        let path = "Note.md", old = text("Before"), outside = text("External change")
        try disk(path, old)
        let store = VaultStore(); await store.open(root)
        let note = try XCTUnwrap(store.notes.first), session = try XCTUnwrap(store.session(for: note))
        let draft = text("Unsaved phone draft")
        session.updateContent(draft); session.holdForMutation(true)
        try disk(path, outside)
        await store.refresh()
        XCTAssertEqual(store.notes.first?.content, outside)
        XCTAssertEqual(session.document.content, draft); XCTAssertTrue(session.dirty)
        XCTAssertTrue(session.failure?.contains("another editor") == true)
        await session.reload(); session.holdForMutation(false)
        XCTAssertEqual(session.document.content, outside); XCTAssertFalse(session.dirty)
        try FileManager.default.moveItem(at: root.appendingPathComponent(path), to: root.appendingPathComponent("Moved.md"))
        await store.refresh()
        XCTAssertEqual(session.document.path, "Moved.md")
        XCTAssertTrue(store.session(for: note) === session)
        try disk(path, text("A separate note", id: "new-note"))
        await store.refresh()
        let replacement = try XCTUnwrap(store.notes.first { $0.path == path })
        XCTAssertFalse(store.session(for: replacement) === session)
        let saved = text("Saved at moved path")
        session.updateContent(saved); await session.save()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Moved.md"), encoding: .utf8), saved)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8), replacement.content)
        session.deactivate()
    }
}
