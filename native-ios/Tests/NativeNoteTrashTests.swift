import XCTest
@testable import ZerusNative

final class NativeNoteTrashTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func deletedDocument() async throws -> VaultFiles {
        let io = VaultFiles(root: root!)
        let content = "---\nzerus-id: doomed\nforeign: keep\nzerus-file-id: owned\nzerus-file-name: Original.txt\nzerus-file-kind: vault\nzerus-file-path: Work/files/original.txt\nzerus-file-managed: true\n---\n# Doomed\n\n![Plot](assets/plot.png)\n"
        try await io.write("Work/Note.md", data: Data(content.utf8), expected: nil)
        try await io.write("Work/files/original.txt", data: Data("Original file".utf8), expected: nil)
        try await io.write("assets/plot.png", data: Data([137, 80, 78, 71, 1, 2, 3]), expected: nil)
        let revision = try await io.revisionSnapshot(notePath: "Work/Note.md")
        _ = try await io.applyRevision(io.prepareRevision(revision, action: .create))
        let before = try await io.read("Work/Note.md"), after = before + Data("\nA later version.".utf8)
        try await io.write("Work/Note.md", data: after, expected: before)
        try await io.move("Work/Note.md", to: ".trash/Work/Note.md", expected: after)
        return io
    }

    func testReviewedNoteDeletionRemovesItsVersionsAndOnlyItsUnusedManagedFilesWithoutChangingSurvivors() async throws {
        let io = try await deletedDocument()
        let initial = try await io.revisionTrashSnapshot(), index = try XCTUnwrap(initial.indexes.values.first)
        let frozen = try XCTUnwrap(try MarkdownMoveLinks.links(in: NoteDocument.split(index.revisions[0].content).body).first?.value)
        let incoming = Data(("---\nforeign: untouched\n---\n# Survivor\n[Shared original](files/original.txt)\n[Shared frozen image](../" + frozen + ")\n").utf8)
        try await io.write("Work/Survivor.md", data: incoming, expected: nil)
        let orphan = ".zerus/history/blobs/" + String(repeating: "a", count: 64), orphanBytes = Data("Unrelated orphan".utf8)
        try await io.write(orphan, data: orphanBytes, expected: nil)
        let snapshot = try await io.revisionTrashSnapshot()
        let before = try await io.read(".trash/Work/Note.md")
        let plan = try await io.prepareNoteTrashPurge(snapshot, paths: [".trash/Work/Note.md"])
        XCTAssertEqual(plan.deleted.map(\.path), [".trash/Work/Note.md"])
        XCTAssertEqual(plan.removedRevisions, 2); XCTAssertGreaterThan(plan.removedHistory, 0)
        XCTAssertTrue(plan.removedFiles.contains { $0.hasPrefix(".zerus/history/blobs/") }, "The deleted note’s unused history images are included")
        XCTAssertTrue(plan.retainedFiles.contains("Work/files/original.txt")); XCTAssertTrue(plan.retainedFiles.contains(frozen))
        XCTAssertFalse(plan.removedFiles.contains(orphan), "A per-note review cannot collect unrelated history images")
        let canceled = try await io.read(".trash/Work/Note.md"); XCTAssertEqual(canceled, before, "Preparing a review must not delete anything")
        let final = try await io.applyNoteTrashPurge(plan)
        XCTAssertEqual(final.notes.map(\.path), ["Work/Survivor.md"])
        for path in plan.changes.filter({ $0.after == nil }).map(\.path) { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), path) }
        for (path, expected) in [("Work/Survivor.md", incoming), ("Work/files/original.txt", Data("Original file".utf8)), (orphan, orphanBytes)] { let bytes = try await io.read(path); XCTAssertEqual(bytes, expected, path) }
        let image = try await io.read(frozen); XCTAssertEqual(image, Data([137, 80, 78, 71, 1, 2, 3]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/plot.png").path), "An ordinary inline asset is not an owned file")
        let reopened = try await VaultFiles(root: root!).revisionTrashSnapshot(); XCTAssertTrue(reopened.indexes.isEmpty)
        let history = try await io.historyMaintenanceSnapshot(); XCTAssertFalse(history.records.keys.contains { $0.hasPrefix(".zerus/history/notes/doomed/") })
    }

    @MainActor
    func testNewIncomingNotesMetadataAndRevisionFilesInvalidateDeletionBeforeAnyFileChanges() async throws {
        let io = try await deletedDocument()
        let note = ".trash/Work/Note.md", expected = try await io.read(note)
        let initial = try await io.revisionTrashSnapshot()
        let canceled = Task { @MainActor in try await io.prepareNoteTrashPurge(initial, paths: [note]) }
        canceled.cancel()
        do { _ = try await canceled.value; XCTFail("Canceled preparation must not publish a permanent-deletion review") } catch is CancellationError {}
        let stillPresent = try await io.read(note); XCTAssertEqual(stillPresent, expected)
        let additions: [(String, Data)] = [
            ("New incoming.md", Data("# New\n[Shared](Work/files/original.txt)".utf8)),
            (".zerus/recovery-copy.json", Data(#"{"content":"Work/files/original.txt"}"#.utf8)),
            (".zerus/revisions/notes/doomed/files/new.txt", Data("Arrived after review".utf8))
        ]
        for (path, bytes) in additions {
            let snapshot = try await io.revisionTrashSnapshot(), plan = try await io.prepareNoteTrashPurge(snapshot, paths: [note])
            try await io.write(path, data: bytes, expected: nil)
            do { _ = try await io.applyNoteTrashPurge(plan); XCTFail("An added reference or revision file must invalidate the review: " + path) } catch {}
            let kept = try await io.read(note); XCTAssertEqual(kept, expected)
            let outside = try await io.read(path); XCTAssertEqual(outside, bytes)
            try FileManager.default.removeItem(at: root.appendingPathComponent(path))
        }
        let snapshot = try await io.revisionTrashSnapshot(), plan = try await io.prepareNoteTrashPurge(snapshot, paths: [note])
        let indexPath = ".zerus/revisions/notes/doomed/index.json", prior = try await io.read(indexPath)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: prior) as? [String: Any]); object["foreign"] = "outside edit"
        let changed = try JSONSerialization.data(withJSONObject: object)
        try await io.write(indexPath, data: changed, expected: prior)
        do { _ = try await io.applyNoteTrashPurge(plan); XCTFail("A changed revision index must reject a prepared deletion") } catch {}
        let kept = try await io.read(note); XCTAssertEqual(kept, expected)
    }

    func testCleanupPreservesExternalOriginalsAndRecoveryReferencedCopiesAndRejectsLiveOrDuplicateIdentities() async throws {
        let io = VaultFiles(root: root!)
        let connected = "---\nzerus-id: external\nzerus-file-id: x\nzerus-file-name: Original.pdf\nzerus-file-kind: location\nzerus-file-location: folder\nzerus-file-path: original.pdf\n---\n# Connected\n"
        let managed = "---\nzerus-id: managed\nzerus-file-id: x\nzerus-file-name: Copy.pdf\nzerus-file-kind: vault\nzerus-file-path: assets/copy.pdf\nzerus-file-managed: true\n---\n# Managed\n"
        try await io.write(".trash/Connected.md", data: Data(connected.utf8), expected: nil)
        try await io.write(".trash/Managed.md", data: Data(managed.utf8), expected: nil)
        let original = Data("External original remains".utf8), copy = Data("Recovery copy remains".utf8)
        try await io.write("original.pdf", data: original, expected: nil); try await io.write("assets/copy.pdf", data: copy, expected: nil)
        let recovery = try JSONSerialization.data(withJSONObject: ["content": Data("![Kept](assets/copy.pdf)".utf8).base64EncodedString()])
        try await io.write(".zerus/recovery-copy.json", data: recovery, expected: nil)
        try await io.write("Live.md", data: Data("---\nzerus-id: managed\n---\n# Live duplicate\n".utf8), expected: nil)
        var snapshot = try await io.revisionTrashSnapshot()
        do { _ = try await io.prepareNoteTrashPurge(snapshot, paths: ["Live.md"]); XCTFail("A live note cannot enter permanent cleanup") } catch {}
        do { _ = try await io.prepareNoteTrashPurge(snapshot, paths: [".trash/Managed.md"]); XCTFail("A survivor owns the same identity") } catch {}
        try FileManager.default.removeItem(at: root.appendingPathComponent("Live.md"))
        snapshot = try await io.revisionTrashSnapshot()
        let plan = try await io.prepareNoteTrashPurge(snapshot, paths: [".trash/Connected.md", ".trash/Managed.md"])
        XCTAssertEqual(plan.retainedFiles, ["assets/copy.pdf"]); XCTAssertTrue(plan.removedFiles.isEmpty)
        _ = try await io.applyNoteTrashPurge(plan)
        for (path, expected) in [("original.pdf", original), ("assets/copy.pdf", copy), (".zerus/recovery-copy.json", recovery)] { let bytes = try await io.read(path); XCTAssertEqual(bytes, expected) }
        // A note-only deletion owns no shared resource cleanup. An unreadable
        // unrelated metadata record must remain outside its read/write scope.
        let plain = Data("---\nzerus-id: plain\nforeign: kept\n---\n# Plain\nFirst version.".utf8)
        try await io.write(".trash/Plain.md", data: plain, expected: nil)
        try await io.write(".trash/Plain.md", data: plain + Data("\nSecond version.".utf8), expected: plain)
        let unrelatedPath = ".zerus/unrelated-record.json", unrelated = Data("{\"foreign\":true}".utf8)
        try await io.write(unrelatedPath, data: unrelated, expected: nil)
        let protected = root.appendingPathComponent(unrelatedPath)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: protected.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: protected.path) }
        XCTAssertFalse(FileManager.default.isReadableFile(atPath: protected.path))
        snapshot = try await io.revisionTrashSnapshot()
        let noteOnly = try await io.prepareNoteTrashPurge(snapshot, paths: [".trash/Plain.md"])
        XCTAssertEqual(noteOnly.removedHistory, 2); XCTAssertTrue(noteOnly.removedFiles.isEmpty)
        _ = try await io.applyNoteTrashPurge(noteOnly)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".trash/Plain.md").path))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: protected.path)
        XCTAssertEqual(try Data(contentsOf: protected), unrelated)
    }

    @MainActor
    func testRetainedCleanupCannotCrossVaultActivationsOrReviveADeletedEditorsFile() async throws {
        let io = try await deletedDocument(), store = VaultStore()
        let other = root.appendingPathComponent("Other"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await store.open(root)
        let snapshot = try await store.revisionTrashSnapshot(workspace: store.workspaceID)
        let plan = try await store.prepareNoteTrashPurge(snapshot, paths: [".trash/Work/Note.md"])
        await store.open(other); await store.open(root)
        do { try await store.saveNoteTrashPurge(plan); XCTFail("Returning to the same vault must not reauthorize an old permanent deletion") } catch {}
        let intact = try await io.read(".trash/Work/Note.md"); XCTAssertFalse(intact.isEmpty)
        let note = try XCTUnwrap(store.notes.first { $0.trashed }), editor = try XCTUnwrap(store.session(for: note))
        let fresh = try await store.revisionTrashSnapshot(workspace: store.workspaceID)
        try await store.saveNoteTrashPurge(store.prepareNoteTrashPurge(fresh, paths: [note.path]))
        XCTAssertFalse(store.notes.contains { $0.path == note.path })
        editor.updateBody("A stale editor must not recreate a deleted note."); await editor.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(note.path).path))
    }
}
