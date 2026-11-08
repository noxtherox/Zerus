import XCTest
@testable import ZerusNative

final class NativeRevisionTrashTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func discardedRevision() async throws -> (VaultFiles, NativeRevisionSnapshot, String, String) {
        let io = VaultFiles(root: root!)
        let content = "---\nzerus-id: discarded\nForeign:\n  keep: true\nzerus-file-id: doc\nzerus-file-name: Original.txt\nzerus-file-kind: vault\nzerus-file-path: Work/files/original.txt\nzerus-file-managed: true\n---\n# Discarded revision\n\n![Plot](assets/plot.png)\n"
        try await io.write("Work/Note.md", data: Data(content.utf8), expected: nil)
        try await io.write("Work/files/original.txt", data: Data("Original text".utf8), expected: nil)
        try await io.write("assets/plot.png", data: Data([137, 80, 78, 71, 1, 2, 3]), expected: nil)
        var snapshot = try await io.revisionSnapshot(notePath: "Work/Note.md")
        _ = try await io.applyRevision(io.prepareRevision(snapshot, action: .create))
        snapshot = try await io.revisionSnapshot(notePath: "Work/Note.md")
        let first = try XCTUnwrap(snapshot.index.revisions.first)
        let file = try XCTUnwrap(NoteDocument(path: "Work/Note.md", content: first.content, modified: .distantPast).property("zerus-file-path"))
        let image = try XCTUnwrap(try MarkdownMoveLinks.links(in: NoteDocument.split(first.content).body).first?.value)
        _ = try await io.applyRevision(io.prepareRevision(snapshot, action: .trash(first.id)))
        return (io, try await io.revisionSnapshot(notePath: "Work/Note.md"), file, image)
    }

    func testPurgeRemovesOnlyDiscardedVersionsAndUnreferencedFilesAcrossTheActualVault() async throws {
        let (io, before, obsoleteFile, sharedImage) = try await discardedRevision()
        let incoming = "# Incoming\n[Original](./files/original.txt)\n[Saved image](../" + sharedImage + ")\n"
        try await io.write("Work/Incoming.md", data: Data(incoming.utf8), expected: nil)
        let currentFile = try XCTUnwrap(before.note.property("zerus-file-path"))
        let currentImage = try XCTUnwrap(try MarkdownMoveLinks.links(in: before.note.parts.body).first?.value)
        var foreign = before.index.object; foreign["foreign"] = ["nested": [1, 2, 3]]
        // Reserved metadata and Markdown notes are never treated as attachment
        // garbage, even if a foreign ownership record mentions them.
        foreign["ownedFiles"] = (foreign["ownedFiles"] as? [String] ?? []) + [".zerus/tasks.json", "Work/Incoming.md"]
        try await io.write(before.indexPath, data: JSONSerialization.data(withJSONObject: foreign), expected: before.indexBytes)
        let tasks = Data("{\"tasks\":[],\"foreign\":true}".utf8)
        try await io.write(".zerus/tasks.json", data: tasks, expected: nil)
        let snapshot = try await io.revisionTrashSnapshot()
        XCTAssertEqual(snapshot.entries.map { $0.revision.number }, [1])
        XCTAssertEqual(snapshot.entries.first?.note?.path, "Work/Note.md")
        let plan = try await io.prepareRevisionTrashPurge(snapshot)
        XCTAssertEqual(plan.deleted.count, 1)
        XCTAssertTrue(plan.removedFiles.contains(obsoleteFile))
        for kept in [sharedImage, currentFile, currentImage, "Work/files/original.txt", ".zerus/tasks.json", "Work/Incoming.md"] { XCTAssertFalse(plan.removedFiles.contains(kept), kept) }
        let reviewed = try await io.read(before.indexPath)
        XCTAssertEqual(reviewed, try JSONSerialization.data(withJSONObject: foreign), "Preparing or canceling a review must not write metadata")
        _ = try await io.applyRevisionTrashPurge(plan)
        let after = try await io.revisionSnapshot(notePath: "Work/Note.md")
        XCTAssertEqual(after.note.content, before.note.content)
        XCTAssertEqual(after.index.currentID, before.index.currentID)
        XCTAssertEqual(after.index.nextNumber, before.index.nextNumber)
        XCTAssertEqual(after.index.revisions.map(\.number), [2])
        XCTAssertNotNil(after.index.object["foreign"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(obsoleteFile).path))
        for kept in [sharedImage, currentFile, currentImage, "Work/files/original.txt"] { let saved = try await io.read(kept); XCTAssertFalse(saved.isEmpty) }
        let actualTasks = try await io.read(".zerus/tasks.json"), actualIncoming = try await io.read("Work/Incoming.md")
        XCTAssertEqual(actualTasks, tasks); XCTAssertEqual(actualIncoming, Data(incoming.utf8))
        let trash = try await VaultFiles(root: root!).revisionTrashSnapshot(); XCTAssertTrue(trash.entries.isEmpty)
    }

    func testPurgeRejectsNewNotesChangedIndexesAndUnsupportedOrPendingRecordsWithoutDeletingFiles() async throws {
        let (io, before, file, _) = try await discardedRevision()
        var snapshot = try await io.revisionTrashSnapshot()
        let plan = try await io.prepareRevisionTrashPurge(snapshot)
        try await io.write("New incoming.md", data: Data(("# Keep\n[File](" + file + ")\n").utf8), expected: nil)
        do { _ = try await io.applyRevisionTrashPurge(plan); XCTFail("A new note can add a live file reference after review") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path))
        snapshot = try await io.revisionTrashSnapshot()
        let indexPlan = try await io.prepareRevisionTrashPurge(snapshot)
        var outside = before.index.object; outside["outside"] = true
        let changed = try JSONSerialization.data(withJSONObject: outside)
        try await io.write(before.indexPath, data: changed, expected: before.indexBytes)
        do { _ = try await io.applyRevisionTrashPurge(indexPlan); XCTFail("Outside index changes must reject the old cleanup") } catch {}
        let retained = try await io.read(before.indexPath); XCTAssertEqual(retained, changed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path))
        let pending = Data("{\"future\":true}".utf8), pendingPath = ".zerus/revisions/notes/discarded/pending.json"
        try await io.write(pendingPath, data: pending, expected: nil)
        let interrupted = try await io.revisionTrashSnapshot()
        XCTAssertEqual(interrupted.pending, [pendingPath])
        do { _ = try await io.prepareRevisionTrashPurge(interrupted); XCTFail("Pending web revisions own their files") } catch {}
        let originalPending = try await io.read(pendingPath); XCTAssertEqual(originalPending, pending)
        let future = Data("{\"schema\":99,\"opaque\":true}".utf8), futurePath = ".zerus/revisions/notes/future/index.json"
        try await io.write(futurePath, data: future, expected: nil)
        let unsupported = try await io.revisionTrashSnapshot()
        XCTAssertFalse(unsupported.problems.isEmpty)
        do { _ = try await io.prepareRevisionTrashPurge(unsupported); XCTFail("Unrecognized records can refer to files we cannot inspect") } catch {}
        let actual = try await io.read(futurePath); XCTAssertEqual(actual, future)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path))
    }

    func testWholeNoteTrashKeepsItsRevisionsGroupedAndAnOrphanKeepsItsSurvivingCurrentFiles() async throws {
        let (io, before, oldFile, _) = try await discardedRevision()
        try await io.move("Work/Note.md", to: ".trash/Work/Note.md", expected: Data(before.note.content.utf8))
        let grouped = try await io.revisionTrashSnapshot(); XCTAssertTrue(grouped.entries.isEmpty)
        XCTAssertEqual(grouped.indexes[before.indexPath]?.revisions.count, 2)
        // A missing source note still leaves discarded text available for export;
        // the active orphaned version and its file bytes stay protected.
        try FileManager.default.removeItem(at: root.appendingPathComponent(".trash/Work/Note.md"))
        let orphan = try await io.revisionTrashSnapshot()
        XCTAssertEqual(orphan.entries.count, 1); XCTAssertNil(orphan.entries.first?.note)
        let currentFile = try XCTUnwrap(before.note.property("zerus-file-path"))
        let plan = try await io.prepareRevisionTrashPurge(orphan)
        XCTAssertTrue(plan.removedFiles.contains(oldFile)); XCTAssertFalse(plan.removedFiles.contains(currentFile))
        _ = try await io.applyRevisionTrashPurge(plan)
        let currentBytes = try await io.read(currentFile); XCTAssertEqual(currentBytes, Data("Original text".utf8))
        let final = try await io.revisionTrashSnapshot()
        XCTAssertEqual(final.indexes[before.indexPath]?.revisions.map(\.number), [2])
    }

    @MainActor
    func testRetainedPermanentCleanupCannotApplyAfterSwitchingAwayAndReturningToTheSameVault() async throws {
        let originalBookmark = UserDefaults.standard.data(forKey: "zerus.native.vault.bookmark")
        defer {
            if let originalBookmark { UserDefaults.standard.set(originalBookmark, forKey: "zerus.native.vault.bookmark") }
            else { UserDefaults.standard.removeObject(forKey: "zerus.native.vault.bookmark") }
        }
        let (io, before, file, _) = try await discardedRevision()
        let other = root.appendingPathComponent("Other vault")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let store = VaultStore(); await store.open(root)
        let snapshot = try await store.revisionTrashSnapshot(workspace: store.workspaceID)
        let plan = try await store.prepareRevisionTrashPurge(snapshot)
        await store.open(other)
        do { try await store.saveRevisionTrashPurge(plan); XCTFail("The new active vault must not accept an old permanent cleanup") } catch {}
        await store.open(root)
        do { try await store.saveRevisionTrashPurge(plan); XCTFail("Reopening the old path must not reauthorize the old review") } catch {}
        let after = try await io.read(before.indexPath); XCTAssertEqual(after, before.indexBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path))
    }
}
