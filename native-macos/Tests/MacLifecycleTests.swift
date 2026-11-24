import XCTest
import AppKit
@testable import Zerus_Native

@MainActor final class MacLifecycleTests: XCTestCase {
    private final class OriginalDelegate: NSObject, NSWindowDelegate {
        var decisionCount = 0
        var allowsClose = true
        var decided: (() -> Void)?
        var closed: (() -> Void)?
        func windowShouldClose(_ sender: NSWindow) -> Bool { decisionCount += 1; decided?(); return allowsClose }
        func windowWillClose(_ notification: Notification) { closed?() }
    }
    func testWindowCloseSavesForwardsDelegateAndRestoresAgentAdmissionAfterAVeto() async throws {
        try await withWorkspace { root, store, original in
            let file = root.appendingPathComponent("Note.md"), changed = "# Note\n\nSaved before the window closes.\n"
            let controller = try MacAgentController(workspace: store, owner: "lifecycle-owner")
            let record = try await controller.workspace.start(objective: "Keep this run available", mode: .ask, scope: .init(paths: ["Note.md"]), chatID: "lifecycle")
            try await controller.open(record)
            store.changed(changed)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let previous = OriginalDelegate()
            window.delegate = previous
            let guardDelegate = MacWindowCloseGuard(workspace: store, window: window)
            defer { previous.closed = nil; guardDelegate.detach(); window.close() }
            let vetoed = self.expectation(description: "Original delegate refused the saved close")
            previous.allowsClose = false
            previous.decided = { DispatchQueue.main.async { vetoed.fulfill() } }
            window.orderFront(nil); window.performClose(nil)
            XCTAssertTrue(window.isVisible, "The first close must wait for asynchronous persistence")
            await fulfillment(of: [vetoed], timeout: 5)
            XCTAssertTrue(window.isVisible); XCTAssertFalse(store.isDirty)
            XCTAssertEqual(previous.decisionCount, 1)
            do { try await controller.open(record) }
            catch { XCTFail("A vetoed close must leave the saved run usable: " + error.localizedDescription); return }
            XCTAssertEqual(controller.current?.id, record.id, "A vetoed close must leave the saved run usable")
            let closed = self.expectation(description: "Saved window closed")
            previous.closed = { XCTAssertEqual(try? String(contentsOf: file, encoding: .utf8), NoteDocument(path: "Note.md", content: original, modified: .distantPast).replacingBody(changed)); closed.fulfill() }
            previous.decided = nil; previous.allowsClose = true
            window.performClose(nil)
            await fulfillment(of: [closed], timeout: 5)
            XCTAssertFalse(window.isVisible); XCTAssertEqual(previous.decisionCount, 2)
            XCTAssertFalse(store.isDirty); previous.closed = nil
        }
    }
    func testWindowCloseKeepsAConflictingDraftUntilItsExportIsVerifiedEvenWhenTheOriginalIsUnreadable() async throws {
      for kind in ["changed", "binary", "unavailable"] {
        try await withWorkspace { root, store, original in
            let file = root.appendingPathComponent("Note.md")
            let outside = kind == "binary" ? Data([255, 254, 0]) : kind == "unavailable" ? Data(original.utf8) : Data((original + "\nOutside edit.\n").utf8)
            let movedRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            var savedFile = file
            defer { if kind == "unavailable" { try? FileManager.default.moveItem(at: movedRoot, to: root) } }
            store.changed("# Note\n\nLocal retained text.\n")
            if kind == "unavailable" { try FileManager.default.moveItem(at: root, to: movedRoot); savedFile = movedRoot.appendingPathComponent("Note.md") }
            else { try outside.write(to: file) }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let previous = OriginalDelegate(), blocked = self.expectation(description: "Conflicting window remains open"); blocked.isInverted = true
            previous.closed = { blocked.fulfill() }; window.delegate = previous
            let guardDelegate = MacWindowCloseGuard(workspace: store, window: window)
            defer { previous.closed = nil; guardDelegate.detach(); window.close() }
            window.orderFront(nil); window.performClose(nil)
            await fulfillment(of: [blocked], timeout: 0.5)
            XCTAssertTrue(window.isVisible); XCTAssertEqual(previous.decisionCount, 0)
            XCTAssertEqual(store.noteDiskChange, kind == "unavailable" ? .unavailable : .modified); XCTAssertTrue(store.body.contains("Local retained text."))
            XCTAssertEqual(try Data(contentsOf: savedFile), outside)
            let record = try XCTUnwrap(MacNoteRecoveryStore.snapshot(root: root).records.first)
            XCTAssertEqual(record.body, store.body)
            let copy = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".md")
            defer { try? FileManager.default.removeItem(at: copy) }
            XCTAssertThrowsError(try store.exportRetainedNote(to: record.file))
            XCTAssertEqual(try Data(contentsOf: record.file), record.bytes)
            if kind != "changed" { try store.exportNoteRecovery(record, to: copy, workspaceID: store.workspaceID) }
            else { try store.exportRetainedNote(to: copy) }
            let closed = self.expectation(description: "Export-backed window closes")
            previous.closed = { closed.fulfill() }; window.performClose(nil)
            await fulfillment(of: [closed], timeout: 5)
            XCTAssertFalse(window.isVisible); XCTAssertEqual(previous.decisionCount, 1)
            XCTAssertEqual(try Data(contentsOf: savedFile), outside)
            XCTAssertEqual(try Data(contentsOf: copy), Data(record.content.utf8))
            XCTAssertEqual(try Data(contentsOf: record.file), record.bytes)
        }
      }
    }
    func testConcurrentWindowsKeepIndependentDraftsAndOneSaveCannotRemoveTheOtherCheckpoint() async throws {
        try await withWorkspace { root, first, original in
            let second = MacWorkspace(); await second.openVault(root); await second.openNote("Note.md")
            let firstBody = "# Note\n\nFirst window café.\n", secondBody = "# Note\n\nSecond window independent text.\n"
            first.changed(firstBody); second.changed(secondBody)
            let beforeSave = try MacNoteRecoveryStore.snapshot(root: root)
            XCTAssertEqual(Set(beforeSave.records.map(\.body)), Set([firstBody, secondBody]))
            // A burst must keep its registration order without letting an
            // older queued checkpoint reappear after the final value is saved.
            for edit in 0..<12 { first.changed("# Note\n\nQueued \(edit). " + String(repeating: "café 🧪 ", count: 4096)) }
            first.changed(firstBody)
            let saved = await first.save(); XCTAssertTrue(saved)
            let afterSave = try MacNoteRecoveryStore.snapshot(root: root)
            XCTAssertTrue(afterSave.records.contains { $0.body == secondBody }, "Saving one window must not remove the other window’s durable text")
            XCTAssertFalse(afterSave.records.contains { $0.body == firstBody })
            await second.refresh()
            XCTAssertEqual(second.body, secondBody); XCTAssertEqual(second.noteDiskChange, .modified)
            let blocked = await second.save(); XCTAssertFalse(blocked)
            let file = root.appendingPathComponent("Note.md"), expected = NoteDocument(path: "Note.md", content: original, modified: .distantPast).replacingBody(firstBody)
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), expected)
            let third = MacWorkspace(); await third.openVault(root); await third.openNote("Note.md")
            XCTAssertEqual(third.body, firstBody, "A new window must not silently adopt another live window’s draft")
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Moved"), withIntermediateDirectories: true)
            let move = try await third.prepareNoteMoves(paths: ["Note.md"], folder: "Moved", workspaceID: third.workspaceID)
            XCTAssertTrue(move.moves.isEmpty); XCTAssertTrue(move.skipped.contains { $0.path == "Note.md" && $0.reason.contains("recovery draft") })
        }
    }
    func testRestartRecoversOneHistoricalValueButKeepsConflictingValuesForReview() async throws {
        for ambiguous in [false, true] {
            try await withWorkspace { root, _, original in
                let note = NoteDocument(path: "Note.md", content: original, modified: .distantPast)
                let body = "# Note\n\nHistorical café.\n"
                try MacNoteRecoveryStore.checkpoint(root: root, note: note, body: body, windowID: UUID().uuidString.lowercased())
                try MacNoteRecoveryStore.checkpoint(root: root, note: note, body: ambiguous ? "# Note\n\nA different historical value.\n" : body, windowID: UUID().uuidString.lowercased())
                let reopened = MacWorkspace(); await reopened.openVault(root); await reopened.openNote("Note.md")
                XCTAssertEqual(reopened.body, ambiguous ? note.parts.body : body)
                if ambiguous {
                    XCTAssertEqual(try MacNoteRecoveryStore.snapshot(root: root).records.count, 2)
                    XCTAssertNotNil(reopened.issue)
                    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Note.md")), Data(original.utf8))
                } else {
                    let saved = await reopened.save(); XCTAssertTrue(saved, reopened.issue ?? reopened.saveStatus)
                    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Note.md")), Data(note.replacingBody(body).utf8))
                    XCTAssertTrue(try MacNoteRecoveryStore.snapshot(root: root).records.isEmpty)
                }
            }
        }
    }
    func testRecoveryReadsLegacyAndCurrentDraftsAfterRestartAndExportsWithoutChangingOriginals() async throws {
        try await withWorkspace { root, store, original in
            let source = root.appendingPathComponent("Note.md"), body = "# Note\r\n\r\nRetained café 🧑🏽‍💻.\r\n"
            store.changed(body)
            try FileManager.default.removeItem(at: source); await store.refresh()
            let reopened = MacWorkspace(); await reopened.openVault(root)
            XCTAssertNil(reopened.current)
            let snapshot = try MacNoteRecoveryStore.snapshot(root: root), record = try XCTUnwrap(snapshot.records.first)
            let currentOnly = try MacNoteRecoveryStore.snapshot(root: root, notePath: "Note.md")
            XCTAssertEqual(currentOnly.records.map(\.bytes), [record.bytes])
            XCTAssertTrue(currentOnly.warnings.isEmpty)
            XCTAssertEqual(record.body, body); XCTAssertEqual(record.content, NoteDocument(path: "Note.md", content: original, modified: .distantPast).replacingBody(body))
            let otherRoot = root.appendingPathComponent("Other", isDirectory: true)
            XCTAssertTrue(try MacNoteRecoveryStore.snapshot(root: otherRoot).records.isEmpty)
            let exported = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".md")
            defer { try? FileManager.default.removeItem(at: exported) }
            XCTAssertThrowsError(try MacNoteRecoveryStore.export(record, root: otherRoot, to: exported))
            XCTAssertThrowsError(try MacNoteRecoveryStore.export(record, root: root, to: source))
            try MacNoteRecoveryStore.export(record, root: root, to: exported)
            XCTAssertEqual(try Data(contentsOf: exported), Data(record.content.utf8)); XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try Data(contentsOf: record.file), record.bytes)
            var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: record.bytes) as? [String: String]); legacy.removeValue(forKey: "vaultRoot"); legacy.removeValue(forKey: "windowID")
            let legacyFile = MacNoteRecoveryStore.location(root: root, path: "Note.md")
            try JSONSerialization.data(withJSONObject: legacy).write(to: legacyFile)
            try FileManager.default.removeItem(at: record.file)
            let legacyRecord = try XCTUnwrap(MacNoteRecoveryStore.snapshot(root: root).records.first)
            XCTAssertEqual(legacyRecord.body, body)
            XCTAssertThrowsError(try MacNoteRecoveryStore.export(legacyRecord, root: root, to: legacyRecord.file))
            XCTAssertEqual(try Data(contentsOf: legacyRecord.file), legacyRecord.bytes)
            let linked = MacNoteRecoveryStore.directory.appendingPathComponent(NativeHistory.hash(root.standardizedFileURL.path + "/Linked.md") + ".json")
            let linkedTarget = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".json")
            let linkedBytes = try JSONSerialization.data(withJSONObject: ["baseline": original, "body": "Linked text", "path": "Linked.md", "vaultRoot": root.path])
            try linkedBytes.write(to: linkedTarget); try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: linkedTarget)
            defer { try? FileManager.default.removeItem(at: linked); try? FileManager.default.removeItem(at: linkedTarget) }
            let guarded = try MacNoteRecoveryStore.snapshot(root: root)
            XCTAssertFalse(guarded.records.contains { $0.note.path == "Linked.md" }); XCTAssertFalse(guarded.warnings.isEmpty)
            let legacyOnly = try MacNoteRecoveryStore.snapshot(root: root, notePath: "Note.md")
            XCTAssertEqual(legacyOnly.records.map(\.bytes), [legacyRecord.bytes])
            XCTAssertTrue(legacyOnly.warnings.isEmpty, "An unrelated unreadable draft must not be read during automatic note recovery")
            XCTAssertTrue(try MacNoteRecoveryStore.snapshot(root: root, notePath: "Missing.md").records.isEmpty)
            let linkedOnly = try MacNoteRecoveryStore.snapshot(root: root, notePath: "Linked.md")
            XCTAssertTrue(linkedOnly.records.isEmpty); XCTAssertFalse(linkedOnly.warnings.isEmpty)
            XCTAssertEqual(try Data(contentsOf: linkedTarget), linkedBytes)
            XCTAssertThrowsError(try MacNoteRecoveryStore.export(record, root: root, to: exported), "A changed private draft invalidates an old preview")
            XCTAssertEqual(try Data(contentsOf: exported), Data(record.content.utf8))
            try MacNoteRecoveryStore.export(legacyRecord, root: root, to: exported)
            XCTAssertEqual(try Data(contentsOf: exported), Data(legacyRecord.content.utf8))
            // Restore the source to let fixture cleanup save/checkpoint normally.
            try Data(original.utf8).write(to: source)
        }
    }
    private func withWorkspace(_ operation: (URL, MacWorkspace, String) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-Lifecycle-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = "---\nzerus-id: lifecycle-note\nforeign: preserved\n---\n# Note\n\nOriginal.\n"
        try Data(original.utf8).write(to: root.appendingPathComponent("Note.md"))
        let oldRecent = UserDefaults.standard.object(forKey: "zerus.mac.recentVaults")
        let store = MacWorkspace(); await store.openVault(root); await store.openNote("Note.md")
        let draft = MacNoteRecoveryStore.directory.appendingPathComponent(NativeHistory.hash(root.standardizedFileURL.path + "/Note.md") + ".json")
        defer {
            try? FileManager.default.removeItem(at: draft)
            for file in (try? MacNoteRecoveryStore.locations(root: root, path: "Note.md")) ?? [] { try? FileManager.default.removeItem(at: file) }
            if let directory = store.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            UserDefaults.standard.set(oldRecent, forKey: "zerus.mac.recentVaults")
            UserDefaults.standard.removeObject(forKey: MacNavigationState.key(root)); UserDefaults.standard.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
            try? FileManager.default.removeItem(at: root)
        }
        try await operation(root, store, original)
    }
}
