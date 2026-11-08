import XCTest
@testable import ZerusNative

final class NativeFolderTrashTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func disk(_ path: String, _ bytes: Data) throws {
        let file = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true); try bytes.write(to: file, options: .atomic)
    }
    private func text(_ path: String, _ value: String) throws { try disk(path, Data(value.utf8)) }
    private func data(_ path: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(path)) }
    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) }
    private func object(_ path: String) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data(path)) as? [String: Any]) }

    func testFolderTrashRetainsEveryByteEmptyDirectoryAndOwnedSettingsThenRestoresWithoutOverwritingUnrelatedChanges() async throws {
        let io = VaultFiles(root: root), note = Data("\u{feff}---\r\nzerus-id: a\r\nForeign: keep\r\n---\r\n# A\r\n![Plot](assets/p.png)\r\n".utf8), image = Data([0, 1, 255, 4, 0])
        try disk("Work/Sub/A.md", note); try disk("Work/Sub/assets/p.png", image); try text("Work/.foreign", "opaque bytes")
        try text("Outside.md", "---\nzerus-id: outside\n---\n# Outside\n[[Work/Sub/A.md|Kept reference]]\n")
        try text(".trash/Work/Old.md", "# Already deleted\n")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work/Empty/Child"), withIntermediateDirectories: true)
        let schema = #"{"Work":[{"name":"Owner","type":"text","foreign":42}],"Work/Sub":[],"Projects":[{"name":"Related","type":"relation","relationTypeKey":"Work"}],"future":{"keep":true}}"#
        try text(".zerus/properties.json", schema)
        for file in ["type-icons.json", "views.json", "saved-views.json"] { try text(".zerus/" + file, #"{"Work":{"future":"kept"},"Work/Sub":"tabler:Star","Other":[1,2]}"#) }
        var outside = try data("Outside.md")
        let oldTrash = try data(".trash/Work/Old.md")
        let plan = try await io.prepareFolderTrash("Work")
        XCTAssertEqual(try data("Work/Sub/A.md"), note); XCTAssertEqual(try data(".zerus/properties.json"), Data(schema.utf8)); XCTAssertFalse(exists(plan.entry.record.path), "Cancel/preparation does not create a recovery record")
        let removed = try await io.applyFolderTrash(plan)
        XCTAssertFalse(exists("Work")); XCTAssertFalse(removed.notes.contains { $0.path.hasPrefix("Work/") })
        XCTAssertEqual(try data(plan.entry.record.files + "/Sub/A.md"), note); XCTAssertEqual(try data(plan.entry.record.files + "/Sub/assets/p.png"), image)
        XCTAssertTrue(exists(plan.entry.record.files + "/Empty/Child")); XCTAssertEqual(try data(plan.entry.record.files + "/.foreign"), Data("opaque bytes".utf8))
        XCTAssertEqual(try data("Outside.md"), outside); XCTAssertEqual(try data(".trash/Work/Old.md"), oldTrash)
        XCTAssertNil(try object(".zerus/properties.json")["Work"])
        XCTAssertEqual(((try object(".zerus/properties.json")["Projects"]) as? [[String: Any]])?.first?["relationTypeKey"] as? String, "Work")
        let entries = try await VaultFiles(root: root).folderTrashSnapshot(), entry = try XCTUnwrap(entries.entries.first)
        XCTAssertEqual(entry.record.notes, ["Sub/A.md"])
        // A damaged retained archive is a Trash-recovery issue, not a reason
        // to read every archive or block saving an unrelated active note.
        var futureArchive = try object(entry.record.path); futureArchive["version"] = 999
        try disk(entry.record.path, JSONSerialization.data(withJSONObject: futureArchive, options: [.sortedKeys]))
        let changedOutside = outside + Data("Another paragraph.\n".utf8)
        do { try await io.write("Outside.md", data: changedOutside, expected: outside) }
        catch { XCTFail("Unrelated identified-note save read a retained archive: " + error.localizedDescription); return }
        outside = changedOutside
        let unsupported = try await io.folderTrashSnapshot()
        XCTAssertTrue(unsupported.entries.isEmpty); XCTAssertEqual(unsupported.issues.count, 1)
        try disk(entry.record.path, entry.bytes)
        // An unrelated settings edit made while this folder is deleted survives.
        var icons = try object(".zerus/type-icons.json"); icons["Other"] = "📚"; icons["Future"] = ["new": 42]
        try disk(".zerus/type-icons.json", JSONSerialization.data(withJSONObject: icons, options: [.sortedKeys]))
        let restored = try await io.applyFolderTrash(io.prepareFolderRestore(entry))
        XCTAssertTrue(restored.notes.contains { $0.path == "Work/Sub/A.md" }); XCTAssertTrue(restored.folders.contains("Work/Empty/Child"))
        XCTAssertEqual(try data("Work/Sub/A.md"), note); XCTAssertEqual(try data("Work/Sub/assets/p.png"), image); XCTAssertEqual(try data("Work/.foreign"), Data("opaque bytes".utf8))
        XCTAssertEqual(try data(".zerus/properties.json"), Data(schema.utf8), "Unchanged surrounding metadata restores its exact original encoding")
        let restoredIcons = try object(".zerus/type-icons.json")
        XCTAssertEqual(restoredIcons["Other"] as? String, "📚"); XCTAssertEqual((restoredIcons["Future"] as? [String: Int])?["new"], 42)
        XCTAssertEqual((restoredIcons["Work"] as? [String: String])?["future"], "kept"); XCTAssertEqual(restoredIcons["Work/Sub"] as? String, "tabler:Star")
        XCTAssertFalse(exists(entry.record.path)); XCTAssertEqual(try data("Outside.md"), outside); XCTAssertEqual(try data(".trash/Work/Old.md"), oldTrash)
    }

    func testStaleReviewsConflictingRestorationAndPermanentCleanupPreserveOtherCopiesAndForeignEdits() async throws {
        let io = VaultFiles(root: root); try text("Work/A.md", "# Original\n"); try text(".zerus/type-icons.json", #"{"Work":"tabler:Star","Other":"📚"}"#)
        let stale = try await io.prepareFolderTrash("Work")
        try text("Work/new.bin", "new outside file")
        do { _ = try await io.applyFolderTrash(stale); XCTFail("A new file invalidates the complete review") } catch {}
        XCTAssertTrue(exists("Work/A.md")); XCTAssertFalse(exists(stale.entry.record.path))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Work/new.bin"))
        try text(".zerus/type-icons.json", #"{"Work":"📁","Other":"📚"}"#)
        do { _ = try await io.applyFolderTrash(stale); XCTFail("Changed metadata prevents the directory change") } catch {}
        XCTAssertTrue(exists("Work/A.md"))
        _ = try await io.applyFolderTrash(io.prepareFolderTrash("Work"))
        let entries = try await io.folderTrashSnapshot(), entry = try XCTUnwrap(entries.entries.first)
        try text("Work/A.md", "# New active folder\n")
        do { _ = try await io.prepareFolderRestore(entry); XCTFail("An occupied original location must never be overwritten") } catch {}
        XCTAssertEqual(try data("Work/A.md"), Data("# New active folder\n".utf8))
        let purge = try await io.prepareFolderRestore(entry, purge: true)
        try text(entry.record.files + "/A.md", "outside edit to deleted file")
        do { _ = try await io.applyFolderTrash(purge); XCTFail("Permanent cleanup rejects an altered archive") } catch {}
        XCTAssertEqual(try data(entry.record.files + "/A.md"), Data("outside edit to deleted file".utf8))
        try text(entry.record.files + "/A.md", "# Original\n")
        _ = try await io.applyFolderTrash(io.prepareFolderRestore(entry, purge: true))
        XCTAssertFalse(exists(entry.record.path)); XCTAssertFalse(exists(entry.record.files))
        XCTAssertEqual(try data("Work/A.md"), Data("# New active folder\n".utf8)); XCTAssertEqual(try object(".zerus/type-icons.json")["Other"] as? String, "📚")
        // A same-folder second deletion has its own archive and cannot collide
        // with notes already in ordinary Recently Deleted.
        _ = try await io.applyFolderTrash(io.prepareFolderTrash("Work"))
        let secondEntries = try await io.folderTrashSnapshot(), second = try XCTUnwrap(secondEntries.entries.first)
        XCTAssertNotEqual(second.id, entry.id)
        try text(".zerus/type-icons.json", #"{"Work":"tabler:Heart","Other":"📚"}"#)
        // This archive has no owned icon, so it leaves a newly created setting alone.
        _ = try await io.applyFolderTrash(io.prepareFolderRestore(second))
        XCTAssertEqual(try object(".zerus/type-icons.json")["Work"] as? String, "tabler:Heart")
        let withIcon = try await io.prepareFolderTrash("Work"); _ = try await io.applyFolderTrash(withIcon)
        let thirdEntries = try await io.folderTrashSnapshot(), third = try XCTUnwrap(thirdEntries.entries.first)
        try text(".zerus/type-icons.json", #"{"Work":"tabler:Folder","Other":"📚"}"#)
        do { _ = try await io.prepareFolderRestore(third); XCTFail("Conflicting owned settings must not be replaced") } catch {}
        XCTAssertFalse(exists("Work")); XCTAssertTrue(exists(third.record.path)); XCTAssertEqual(try object(".zerus/type-icons.json")["Work"] as? String, "tabler:Folder")
    }

    func testColdRecoveryCompletesActualMoveAndRestoreReceiptsAndResumesOnlyReviewedPermanentRemoval() async throws {
        let io = VaultFiles(root: root); try text("Work/A.md", "# A\n"); try text("Work/asset.bin", "binary bytes")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work/Empty"), withIntermediateDirectories: true)
        let plan = try await io.prepareFolderTrash("Work")
        try await io.applyTransaction(plan.changes)
        try text("Work/A.md", "outside edit")
        let blocked = VaultFiles(root: root)
        do { _ = try await blocked.scan(); XCTFail("An outside edit after the metadata commit keeps the move pending") } catch {}
        XCTAssertEqual(try data("Work/A.md"), Data("outside edit".utf8)); XCTAssertTrue(exists(plan.entry.record.pendingPath))
        let suspended = await blocked.writesSuspendedForRecovery; XCTAssertTrue(suspended)
        try text("Work/A.md", "# A\n")
        _ = try await blocked.scan(); XCTAssertFalse(exists("Work"))
        let archived = try await blocked.folderTrashSnapshot(), entry = try XCTUnwrap(archived.entries.first)
        let restore = try await blocked.prepareFolderRestore(entry)
        try await blocked.applyTransaction(restore.changes)
        // Simulate termination after the directory move but before record retirement.
        try FileManager.default.moveItem(at: root.appendingPathComponent(entry.record.files), to: root.appendingPathComponent("Work"))
        let restored = try await VaultFiles(root: root).scan()
        XCTAssertTrue(restored.folders.contains("Work/Empty")); XCTAssertEqual(try data("Work/A.md"), Data("# A\n".utf8)); XCTAssertFalse(exists(entry.record.path))
        let nextIO = VaultFiles(root: root); _ = try await nextIO.applyFolderTrash(nextIO.prepareFolderTrash("Work"))
        let removed = try await nextIO.folderTrashSnapshot(), nextEntry = try XCTUnwrap(removed.entries.first)
        let cleanup = try await nextIO.prepareFolderRestore(nextEntry, purge: true)
        try await nextIO.applyTransaction(cleanup.changes)
        try FileManager.default.removeItem(at: root.appendingPathComponent(nextEntry.record.files + "/A.md"))
        try text(nextEntry.record.files + "/asset.bin", "outside replacement")
        let cold = VaultFiles(root: root)
        do { _ = try await cold.scan(); XCTFail("Recovery must not purge a changed remaining file") } catch {}
        XCTAssertEqual(try data(nextEntry.record.files + "/asset.bin"), Data("outside replacement".utf8)); XCTAssertTrue(exists(nextEntry.record.path))
        try text(nextEntry.record.files + "/asset.bin", "binary bytes")
        _ = try await cold.scan(); XCTAssertFalse(exists(nextEntry.record.files)); XCTAssertFalse(exists(nextEntry.record.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".zerus/native-folder-trash-pending").path).isEmpty)
    }

    @MainActor
    func testStoreRejectsRetiredWorkspaceReviewAndRetiresDeletedEditorsDefaultsAndOrderWithoutRecreatingNotes() async throws {
        try text("Work/Sub/A.md", "# Original\n"); try text("Root.md", "# Root\n")
        let store = VaultStore(); await store.open(root)
        let id = try XCTUnwrap(store.activeVaultID), workspace = store.workspaceID
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: NativeFolderOrder.key(id)); UserDefaults.standard.removeObject(forKey: NativeNoteDefaults.key(id)) }
        UserDefaults.standard.set("Work/Sub", forKey: NativeNoteDefaults.key(id)); store.reorderFolder("Work", direction: -1, workspace: workspace)
        let oldPlan = try await store.prepareFolderTrash("Work", workspace: workspace)
        let other = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: other) }
        await store.open(other)
        do { try await store.saveFolderTrash(oldPlan); XCTFail("A review from another workspace must never write") } catch {}
        XCTAssertTrue(exists("Work/Sub/A.md"))
        await store.open(root)
        let note = try XCTUnwrap(store.notes.first { $0.path == "Work/Sub/A.md" }), editor = try XCTUnwrap(store.session(for: note))
        let current = try await store.prepareFolderTrash("Work", workspace: store.workspaceID)
        try await store.saveFolderTrash(current)
        XCTAssertFalse(store.notes.contains { $0.path == note.path }); XCTAssertFalse(store.folderOrder.contains("Work")); XCTAssertEqual(NativeNoteDefaults.load(id), "Inbox")
        editor.updateContent("# Retired editor must not recreate deleted file\n"); await editor.save()
        XCTAssertFalse(exists(note.path))
        let trash = try await store.folderTrashSnapshot(workspace: store.workspaceID), entry = try XCTUnwrap(trash.entries.first)
        let restore = try await store.prepareFolderRestore(entry, purge: false, workspace: store.workspaceID)
        try await store.saveFolderTrash(restore)
        XCTAssertEqual(try data(note.path), Data("# Original\n".utf8))
        let reopened = try XCTUnwrap(store.session(for: XCTUnwrap(store.notes.first { $0.path == note.path })))
        XCTAssertFalse(reopened === editor); XCTAssertEqual(reopened.document.parts.body, "# Original\n")
    }
}
