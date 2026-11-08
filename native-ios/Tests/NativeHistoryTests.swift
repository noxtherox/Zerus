import XCTest
import CryptoKit
@testable import ZerusNative

final class NativeHistoryTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func webEntry(id: String, text: String, parent: String? = nil, before: String? = nil, delta: [String: Any]? = nil, time: String = "2026-11-01T12:00:00.000Z", images: [[String: Any]] = []) throws -> Data {
        var object: [String: Any] = ["schema":1, "id":id, "noteId":"history-note", "timestamp":time, "source":"browser", "originId":"browser-fixture", "parentId":parent as Any? ?? NSNull(), "depth":parent == nil ? 0 : 1, "kind":delta == nil ? "checkpoint" : "delta", "baseHash":before.map(hash) as Any? ?? NSNull(), "resultHash":hash(text), "images":images, "kept":false, "label":NSNull(), "foreign":["keep":true]]
        if let delta { object["delta"] = delta } else { object["content"] = text }
        return try JSONSerialization.data(withJSONObject: object)
    }
    private func writeWeb(_ io: VaultFiles, id: String, bytes: Data) async throws {
        try await io.write(".zerus/history/notes/history-note/" + id + ".json", data: bytes, expected: nil)
    }

    func testActualSavesCaptureCompatibleUnicodeDeltasAndCheckpointFamiliesWhileProtectingKeptAndUnknownRecords() async throws {
        let io = VaultFiles(root: root!), path = "Note.md"
        var text = "---\nzerus-id: history-note\n---\n# Note\n😀 first\n"
        try await io.write(path, data: Data(text.utf8), expected: nil)
        _ = try await io.applyHistoryMaintenance(io.prepareHistoryMaintenance(io.historyMaintenanceSnapshot(), intent: .settings(enabled: true, limit: 1)))
        let states = ["😀 second", "😁 second", "👩🏽‍💻 third", "Fourth", "Fifth", "Sixth"]
        for (index, state) in states.enumerated() {
            let next = "---\nzerus-id: history-note\n---\n# Note\n" + state + "\n"
            try await io.write(path, data: Data(next.utf8), expected: Data(text.utf8)); text = next
            let snapshot = try await io.historySnapshot(notePath: path)
            XCTAssertEqual(snapshot.versions.first?.content, text)
            XCTAssertTrue(snapshot.versions.allSatisfy { !$0.incomplete })
            if index == 0 {
                let initial = try XCTUnwrap(snapshot.versions.last)
                _ = try await io.applyHistory(io.prepareHistory(snapshot, action: .update(initial.id, kept: true, label: "Before editing")))
            }
        }
        var snapshot = try await VaultFiles(root: root!).historySnapshot(notePath: path)
        XCTAssertEqual(snapshot.versions.filter { $0.checkpoint && !$0.kept }.count, 1)
        XCTAssertTrue(snapshot.versions.contains { $0.label == "Before editing" && $0.content?.contains("😀 first") == true })
        let count = snapshot.records.count
        let metadata = try NativeFrontmatter(text).setting("zerus-pinned", value: .checkbox(true))
        try await io.write(path, data: Data(metadata.utf8), expected: Data(text.utf8)); text = metadata
        snapshot = try await io.historySnapshot(notePath: path); XCTAssertEqual(snapshot.records.count, count)
        let future = Data("{\"schema\":99,\"opaque\":true}".utf8)
        try await writeWeb(io, id: "future", bytes: future)
        for value in ["Seven", "Eight", "Nine", "Ten"] {
            let next = text + value + "\n"; try await io.write(path, data: Data(next.utf8), expected: Data(text.utf8)); text = next
        }
        snapshot = try await io.historySnapshot(notePath: path)
        XCTAssertFalse(snapshot.problems.isEmpty)
        let retained = try await io.read(".zerus/history/notes/history-note/future.json"); XCTAssertEqual(retained, future)
        XCTAssertGreaterThan(snapshot.versions.filter { $0.checkpoint && !$0.kept }.count, 1, "Unknown history suppresses automatic pruning")
        _ = try await io.applyHistoryMaintenance(io.prepareHistoryMaintenance(io.historyMaintenanceSnapshot(), intent: .settings(enabled: false, limit: nil)))
        let disabled = try await io.historySnapshot(notePath: path), next = text + "Unrecorded edit\n"
        try await io.write(path, data: Data(next.utf8), expected: Data(text.utf8))
        let final = try await io.historySnapshot(notePath: path); XCTAssertEqual(final.records, disabled.records)
    }

    func testWebDeltaBranchesCorruptChainsAndFrozenImagesRestoreWithoutLosingTodaysMetadataOrCurrentText() async throws {
        let io = VaultFiles(root: root!), path = "Work/Note.md"
        let historical = "---\nzerus-id: old-id\nzerus-pinned: false\nCategory: draft\n---\n# Old title\n😀 first\n![Plot](assets/plot.png)\n"
        let changed = historical.replacingOccurrences(of: "first", with: "second")
        let current = "---\r\nzerus-id: history-note\r\nzerus-pinned: true\r\nzerus-future:\r\n  nested: [keep, me] # comment\r\nCategory: approved\r\n---\r\n# Today\r\nCurrent text\r\n"
        let image = Data([137, 80, 78, 71, 5, 6]), imageHash = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        try await io.write(path, data: Data(current.utf8), expected: nil)
        try await io.write("assets/plot.png", data: Data([9]), expected: nil)
        try await io.write(".zerus/history/blobs/" + imageHash, data: image, expected: nil)
        let images: [[String: Any]] = [["path":"assets/plot.png", "hash":imageHash, "extension":"png"]]
        try await writeWeb(io, id: "web-base", bytes: webEntry(id: "web-base", text: historical, images: images))
        let offset = (historical as NSString).range(of: "first").location
        try await writeWeb(io, id: "web-delta", bytes: webEntry(id: "web-delta", text: changed, parent: "web-base", before: historical, delta: ["start":offset,"removed":"first","inserted":"second"], time: "2026-11-01T12:00:01.000Z", images: images))
        try await writeWeb(io, id: "alternate", bytes: webEntry(id: "alternate", text: "Alternate body", time: "2026-11-01T11:00:00.000Z"))
        try await writeWeb(io, id: "broken", bytes: webEntry(id: "broken", text: "Unrecoverable", parent: "missing", before: "Missing", delta: ["start":0,"removed":"Missing","inserted":"Unrecoverable"], time: "2026-11-01T10:00:00.000Z"))
        for copy in ["duplicate-a", "duplicate-b"] { try await writeWeb(io, id: copy, bytes: webEntry(id: "duplicate", text: "Conflicting history copy", time: "2026-11-01T09:00:00.000Z")) }
        var snapshot = try await io.historySnapshot(notePath: path)
        XCTAssertTrue(snapshot.versions.filter { $0.id == "duplicate" }.allSatisfy(\.incomplete))
        do { _ = try await io.prepareHistory(snapshot, action: .update("duplicate", kept: true, label: "Wrong copy")); XCTFail("Ambiguous history identities must not select an arbitrary record") } catch {}
        XCTAssertEqual(snapshot.versions.first { $0.id == "web-delta" }?.content, changed)
        XCTAssertTrue(snapshot.versions.first { $0.id == "alternate" }?.alternate == true)
        XCTAssertTrue(snapshot.versions.first { $0.id == "broken" }?.incomplete == true)
        let preview = try await io.historyPreview(XCTUnwrap(snapshot.versions.first { $0.id == "web-delta" }))
        XCTAssertTrue(preview.contains(".zerus/history/blobs/" + imageHash))
        _ = try await io.applyHistoryMaintenance(io.prepareHistoryMaintenance(io.historyMaintenanceSnapshot(), intent: .settings(enabled: false, limit: 10)))
        snapshot = try await io.historySnapshot(notePath: path)
        let plan = try await io.prepareHistory(snapshot, action: .restore("web-delta"))
        let unchanged = try await io.read(path); XCTAssertEqual(unchanged, Data(current.utf8))
        try Data([99]).write(to: root.appendingPathComponent(".zerus/history/blobs/" + imageHash))
        do { _ = try await io.applyHistory(plan); XCTFail("Changed frozen image bytes must invalidate a restore") } catch {}
        let retainedCurrent = try await io.read(path); XCTAssertEqual(retainedCurrent, Data(current.utf8))
        try image.write(to: root.appendingPathComponent(".zerus/history/blobs/" + imageHash))
        _ = try await io.applyHistory(plan)
        let saved = try await io.historySnapshot(notePath: path)
        XCTAssertTrue(saved.note.content.contains("# Old title\n😀 second"))
        XCTAssertTrue(saved.note.content.contains("Category: draft"))
        XCTAssertTrue(saved.note.content.contains("zerus-future:\r\n  nested: [keep, me] # comment\r\n"))
        XCTAssertEqual(saved.note.stableID, "history-note"); XCTAssertTrue(saved.note.pinned)
        XCTAssertTrue(saved.versions.contains { $0.content == current }, "Restore preserves the displaced current note even with automatic capture disabled")
        XCTAssertTrue(saved.versions.contains { $0.content == saved.note.content && $0.source == "restore" && !$0.incomplete })
        let originalImage = try await io.read("assets/plot.png"); XCTAssertEqual(originalImage, Data([9]))
        let restoredPath = try XCTUnwrap(try MarkdownMoveLinks.links(in: saved.note.parts.body).first?.value)
        let restoredImage = try await io.read(restoredPath); XCTAssertEqual(restoredImage, image)
        let updated = try await io.prepareHistory(saved, action: .update("web-delta", kept: true, label: "Milestone"))
        _ = try await io.applyHistory(updated)
        let labeled = try await io.historySnapshot(notePath: path), entry = try XCTUnwrap(labeled.versions.first { $0.id == "web-delta" })
        XCTAssertEqual(entry.label, "Milestone"); XCTAssertNotNil(entry.object["foreign"])
    }

    func testRestoreAndClearReviewsRejectChangedRecordsAndNoteBytesWithoutPartialWrites() async throws {
        let io = VaultFiles(root: root!), path = "Note.md", original = "---\nzerus-id: history-note\n---\n# Note\nBefore\n", after = "---\nzerus-id: history-note\n---\n# Note\nAfter\n"
        try await io.write(path, data: Data(original.utf8), expected: nil)
        try await io.write(path, data: Data(after.utf8), expected: Data(original.utf8))
        var snapshot = try await io.historySnapshot(notePath: path)
        let initial = try XCTUnwrap(snapshot.versions.first { $0.content == original })
        let plan = try await io.prepareHistory(snapshot, action: .restore(initial.id))
        let external = Data((after + "Outside edit\n").utf8)
        // Write directly to model a file-provider edit rather than another app save.
        try external.write(to: root.appendingPathComponent(path))
        do { _ = try await io.applyHistory(plan); XCTFail("Outside note edits must reject the restore") } catch {}
        let actual = try await io.read(path); XCTAssertEqual(actual, external)
        snapshot = try await io.historySnapshot(notePath: path)
        let clear = try await io.prepareHistory(snapshot, action: .clear)
        try await writeWeb(io, id: "late", bytes: webEntry(id: "late", text: "Late incoming version"))
        do { _ = try await io.applyHistory(clear); XCTFail("A new incoming version must invalidate permanent deletion") } catch {}
        let preserved = try await io.read(initial.path); XCTAssertEqual(preserved, initial.bytes)
        snapshot = try await io.historySnapshot(notePath: path)
        let validClear = try await io.prepareHistory(snapshot, action: .clear)
        _ = try await io.applyHistory(validClear)
        let empty = try await io.historySnapshot(notePath: path); XCTAssertTrue(empty.records.isEmpty)
        XCTAssertEqual(empty.note.content, String(data: external, encoding: .utf8))
        _ = try await io.applyHistoryMaintenance(io.prepareHistoryMaintenance(io.historyMaintenanceSnapshot(), intent: .settings(enabled: true, limit: 1)))
        let first = empty.note.content + "First new save\n", second = empty.note.content + "Second new save\n"
        try await io.write(path, data: Data(first.utf8), expected: external)
        try await io.write(path, data: Data(second.utf8), expected: Data(first.utf8))
        let beforeRestore = try await io.historySnapshot(notePath: path)
        let old = try XCTUnwrap(beforeRestore.versions.first { $0.content == empty.note.content })
        let restorePlan = try await io.prepareHistory(beforeRestore, action: .restore(old.id))
        _ = try await io.applyHistory(restorePlan)
        let restored = try await io.historySnapshot(notePath: path)
        XCTAssertTrue(restored.versions.contains { $0.content == second }, "Restoring at a checkpoint boundary must retain the displaced current text even with a one-family limit")
    }

    @MainActor
    func testOldHistoryRestoreCannotApplyAfterVaultSwitchIncludingReturnToSamePath() async throws {
        let bookmark = UserDefaults.standard.data(forKey: "zerus.native.vault.bookmark")
        defer { if let bookmark { UserDefaults.standard.set(bookmark, forKey: "zerus.native.vault.bookmark") } else { UserDefaults.standard.removeObject(forKey: "zerus.native.vault.bookmark") } }
        let io = VaultFiles(root: root!), path = "Note.md", before = "---\nzerus-id: history-note\n---\n# Note\nBefore\n", after = "---\nzerus-id: history-note\n---\n# Note\nAfter\n"
        try await io.write(path, data: Data(before.utf8), expected: nil); try await io.write(path, data: Data(after.utf8), expected: Data(before.utf8))
        let other = root.appendingPathComponent("Other"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let store = VaultStore(); await store.open(root)
        let note = try XCTUnwrap(store.notes.first { $0.path == path }), snapshot = try await store.historySnapshot(note: note)
        let version = try XCTUnwrap(snapshot.versions.first { $0.content == before }), plan = try await store.prepareHistory(snapshot, action: .restore(version.id))
        await store.open(other)
        do { try await store.saveHistory(plan); XCTFail("New vault must reject the old history review") } catch {}
        await store.open(root)
        do { try await store.saveHistory(plan); XCTFail("Returning to the same path must not reauthorize the old review") } catch {}
        let retained = try await io.read(path); XCTAssertEqual(retained, Data(after.utf8))
    }
}
