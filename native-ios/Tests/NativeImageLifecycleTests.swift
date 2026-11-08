import XCTest
import UIKit
@testable import ZerusNative

final class NativeImageLifecycleTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NativeImageLifecycle-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    private func fixture(body: String = "Before 😀\r\n\r\n![Caption](../assets/plot.png \"Title\")\r\n\r\nAfter.") async throws -> (VaultFiles, Data, Data) {
        let io = VaultFiles(root: root)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { context in UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 10)) }
        let png = try XCTUnwrap(image.pngData())
        try await io.write("assets/plot.png", data: png, expected: nil)
        let note = Data(("---\r\nzerus-id: image-note\r\nforeign: 'Keep: this'\r\n---\r\n" + body).utf8)
        try await io.write("Work/Note.md", data: note, expected: nil)
        return (io, png, note)
    }
    private func removal(_ io: VaultFiles) async throws -> NativeImagePlan {
        let snapshot = try await io.imageSnapshot()
        let body = try XCTUnwrap(snapshot.history.notes.first { $0.path == "Work/Note.md" }).parts.body
        return try await io.prepareImageChange(snapshot, action: .remove(note: "Work/Note.md", occurrence: try XCTUnwrap(NativeInlineImage.occurrences(in: body).first)))
    }
    func testReviewedRemovalUndoRestoreAndPurgePreserveBinaryBytesForeignFieldsAndSurroundingMarkdown() async throws {
        let (io, png, original) = try await fixture()
        let plan = try await removal(io)
        XCTAssertEqual(plan.files, ["assets/plot.png", ".trash/assets/plot.png"])
        let before = try await io.read("Work/Note.md"); XCTAssertEqual(before, original, "Review alone does not mutate files")
        _ = try await io.applyImageChange(plan)
        let removed = try await io.read("Work/Note.md")
        XCTAssertEqual(String(decoding: removed, as: UTF8.self), String(decoding: original, as: UTF8.self).replacingOccurrences(of: "![Caption](../assets/plot.png \"Title\")", with: ""))
        let deletedBytes = try await io.read(".trash/assets/plot.png"); XCTAssertEqual(deletedBytes, png)
        let savedHistory = try await io.historySnapshot(notePath: "Work/Note.md")
        let captured = savedHistory.versions.flatMap { ($0.object["images"] as? [[String: Any]] ?? []).compactMap { $0["hash"] as? String } }
        XCTAssertFalse(captured.isEmpty)
        for hash in Set(captured) { let frozen = try await io.read(".zerus/history/blobs/" + hash); XCTAssertEqual(frozen, png, "History must retain the image after its live file moves to Trash") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/plot.png").path))
        _ = try await io.applyImageChange(io.prepareImageUndo(plan))
        let undone = try await io.read("Work/Note.md"); XCTAssertEqual(undone, original)
        let restoredBytes = try await io.read("assets/plot.png"); XCTAssertEqual(restoredBytes, png)
        let second = try await removal(io); _ = try await io.applyImageChange(second)
        var snapshot = try await io.imageSnapshot(), entry = try XCTUnwrap(snapshot.index.entries.first)
        var rows = snapshot.index.objects; rows[0]["foreign"] = ["value": "retained extension"]
        let customIndex = try NativeImageTrashIndex.encode(rows)
        try await io.write(NativeImageTrashIndex.path, data: customIndex, expected: snapshot.index.bytes)
        // Another application's unrelated row and fields survive native edits.
        let otherID = "other-image", otherPNG = Data([1, 2, 3])
        try await io.write(".trash/assets/other.png", data: otherPNG, expected: nil)
        rows.append(["id": otherID, "name": "other.png", "originalPath": "assets/other.png", "trashPath": ".trash/assets/other.png", "deletedAt": "2026-11-06T12:00:00Z", "foreign": ["value": 42]])
        try await io.write(NativeImageTrashIndex.path, data: NativeImageTrashIndex.encode(rows), expected: customIndex)
        snapshot = try await io.imageSnapshot()
        let noteBytes = try await io.read("Work/Note.md")
        try await io.move("Work/Note.md", to: "Moved/Deeper/Note.md", expected: noteBytes)
        snapshot = try await io.imageSnapshot()
        let restore = try await io.prepareImageChange(snapshot, action: .restore(id: entry.id, reattach: true))
        _ = try await io.applyImageChange(restore)
        let moved = String(decoding: try await io.read("Moved/Deeper/Note.md"), as: UTF8.self)
        XCTAssertTrue(moved.contains("![Caption](../../assets/plot.png \"Title\")"), moved)
        XCTAssertTrue(moved.contains("foreign: 'Keep: this'")); XCTAssertTrue(moved.contains("Before 😀\r\n\r\n\r\n\r\nAfter."))
        let reopened = try await VaultFiles(root: root).imageSnapshot()
        XCTAssertEqual(reopened.index.entries.map(\.id), [otherID]); XCTAssertEqual((reopened.index.objects[0]["foreign"] as? [String: Int])?["value"], 42)
        let purge = try await io.prepareImageChange(reopened, action: .purge(ids: [otherID]))
        _ = try await io.applyImageChange(purge)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".trash/assets/other.png").path))
        let finalBytes = try await io.read("assets/plot.png"); XCTAssertEqual(finalBytes, png)
        let history = try await io.historySnapshot(notePath: "Moved/Deeper/Note.md")
        XCTAssertFalse(history.versions.isEmpty, "Image operations keep automatic history available")
        entry = try XCTUnwrap(snapshot.index.entries.first); XCTAssertEqual(entry.name, "plot.png")
    }
    func testSharedCurrentTrashedHiddenAndMetadataReferencesKeepTheOriginalFile() async throws {
        for (path, text) in [("Work/Other.md", "![Other](../assets/plot.png)"), (".trash/Other.md", "![Other](assets/plot.png)"), (".zerus/private/saved.md", "[Original](../../assets/plot.png)"), (".zerus/custom.json", #"{"recovery":"assets/plot.png"}"#)] {
            let caseRoot = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: caseRoot, withIntermediateDirectories: true)
            let previous = root; root = caseRoot
            let (io, png, _) = try await fixture(); try await io.write(path, data: Data(text.utf8), expected: nil)
            let plan = try await removal(io); XCTAssertTrue(plan.files.isEmpty, path)
            _ = try await io.applyImageChange(plan)
            let bytes = try await io.read("assets/plot.png"); XCTAssertEqual(bytes, png, path)
            let snapshot = try await io.imageSnapshot(); XCTAssertTrue(snapshot.index.entries.isEmpty, path)
            root = previous
        }
        let (io, png, _) = try await fixture(body: "![One](../assets/plot.png)\n![Two](../assets/plot.png)")
        _ = try await io.applyImageChange(removal(io))
        let note = String(decoding: try await io.read("Work/Note.md"), as: UTF8.self)
        XCTAssertFalse(note.contains("![One]")); XCTAssertTrue(note.contains("![Two]"))
        let bytes = try await io.read("assets/plot.png"); XCTAssertEqual(bytes, png)
    }
    func testExactImageOccurrencesExcludeCodeAndKeepLinkedImagesTablesUnicodeAndReferenceDefinitions() throws {
        let cases: [(String, [String])] = [
            ("😀 ![One](a.png) and ![Two](a.png)\r\n`![literal](x.png)`", ["![One](a.png)", "![Two](a.png)"]),
            ("[![Caption](a.png)](https://example.com)\n", ["[![Caption](a.png)](https://example.com)"]),
            ("[pic]: assets/plot.png \"Saved title\"\n\nBefore ![Caption][pic]\n", ["![Caption][pic]"]),
            ("| Image |\n| --- |\n| ![Cell](a.png) |\n\n```md\n![Code](x.png)\n```", ["![Cell](a.png)"])
        ]
        for (source, expected) in cases {
            let images = NativeInlineImage.occurrences(in: source)
            XCTAssertEqual(images.map(\.markdown), expected, source)
            for image in images { XCTAssertEqual((source as NSString).substring(with: image.range), image.markdown) }
        }
    }
    func testOutsideChangesCollisionsAndMalformedIndexesCancelWithoutPartialWrites() async throws {
        let (io, png, original) = try await fixture()
        let plan = try await removal(io)
        try await io.write("New.md", data: Data("![New](assets/plot.png)".utf8), expected: nil)
        do { _ = try await io.applyImageChange(plan); XCTFail("New references must invalidate a prepared move") } catch {}
        let note = try await io.read("Work/Note.md"); XCTAssertEqual(note, original)
        let bytes = try await io.read("assets/plot.png"); XCTAssertEqual(bytes, png)
        try FileManager.default.removeItem(at: root.appendingPathComponent("New.md"))
        _ = try await io.applyImageChange(removal(io))
        let snapshot = try await io.imageSnapshot(), entry = try XCTUnwrap(snapshot.index.entries.first)
        try await io.write("assets/plot.png", data: Data("Other file".utf8), expected: nil)
        do { _ = try await io.prepareImageChange(snapshot, action: .restore(id: entry.id, reattach: true)); XCTFail("Restore must not replace a file") } catch {}
        let trash = try await io.read(entry.trashPath); XCTAssertEqual(trash, png)
        let corrupted = Data(#"[{"id":"unsafe","name":"x","originalPath":"../outside.png","trashPath":".trash/assets/x.png","deletedAt":"2026-11-06T12:00:00Z"}]"#.utf8)
        try await io.write(NativeImageTrashIndex.path, data: corrupted, expected: snapshot.index.bytes)
        do { _ = try await io.imageSnapshot(); XCTFail("Unsafe records must be preserved and block image mutations") } catch {}
        let preserved = try await io.read(NativeImageTrashIndex.path); XCTAssertEqual(preserved, corrupted)
    }
    @MainActor
    func testReviewAndUndoCannotCrossVaultSwitchEvenWhenOriginalPathIsReopened() async throws {
        let bookmark = UserDefaults.standard.data(forKey: "zerus.native.vault.bookmark")
        defer { if let bookmark { UserDefaults.standard.set(bookmark, forKey: "zerus.native.vault.bookmark") } else { UserDefaults.standard.removeObject(forKey: "zerus.native.vault.bookmark") } }
        let (io, png, original) = try await fixture()
        let other = FileManager.default.temporaryDirectory.appendingPathComponent("NativeImageOther-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: other) }
        let store = VaultStore(); await store.open(root)
        let snapshot = try await store.imageSnapshot(workspace: store.workspaceID)
        let image = try XCTUnwrap(NativeInlineImage.occurrences(in: try XCTUnwrap(store.notes.first).parts.body).first)
        let plan = try await store.prepareImageChange(snapshot, action: .remove(note: "Work/Note.md", occurrence: image))
        await store.open(other); await store.open(root)
        do { try await store.saveImageChange(plan); XCTFail("A stale review cannot be reauthorized by reopening its path") } catch {}
        do { try await store.undoImageChange(plan); XCTFail("Undo belongs to the original workspace session") } catch {}
        let note = try await io.read("Work/Note.md"); XCTAssertEqual(note, original)
        let bytes = try await io.read("assets/plot.png"); XCTAssertEqual(bytes, png)
    }

    func testNewReferencesProtectDeletedCopiesFromPurgeAndUndoWhileRestoreKeepsThemAvailable() async throws {
        let (io, png, _) = try await fixture()
        let removal = try await removal(io); _ = try await io.applyImageChange(removal)
        try await io.write("Survivor.md", data: Data("![Keep](.trash/assets/plot.png)".utf8), expected: nil)
        let snapshot = try await io.imageSnapshot(), entry = try XCTUnwrap(snapshot.index.entries.first)
        do { _ = try await io.prepareImageChange(snapshot, action: .purge(ids: [entry.id])); XCTFail("Referenced Trash images cannot be permanently deleted") } catch {}
        do { _ = try await io.prepareImageUndo(removal); XCTFail("Undo cannot remove a newly shared Trash copy") } catch {}
        _ = try await io.applyImageChange(io.prepareImageChange(snapshot, action: .restore(id: entry.id, reattach: true)))
        for path in ["assets/plot.png", ".trash/assets/plot.png"] { let bytes = try await io.read(path); XCTAssertEqual(bytes, png, path) }
        let survivor = try await io.read("Survivor.md"); XCTAssertEqual(String(decoding: survivor, as: UTF8.self), "![Keep](.trash/assets/plot.png)")
        let restored = try await io.imageSnapshot(); XCTAssertTrue(restored.index.entries.isEmpty)
    }

}
