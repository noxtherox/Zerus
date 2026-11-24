import XCTest
@testable import Zerus_Native

@MainActor final class MacImagesTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    private let image = "![Caption](../assets/plot.png \"Title\")"
    func testImageReviewSavesDraftProtectsAnotherOccurrenceAndUndoReconcilesTheEditor() async throws {
        for second in [image, "<img src=\"../assets/plot.png\" alt=\"Sized image\" width=\"240\" />"] {
        try await fixture(body: "# Image note 🧑🏽‍💻\n\nBefore.\n" + image + "\n\nKeep second " + second + ".\n") { root, workspace in
            workspace.body += "\nSaved draft text.\n"
            let snapshot = try await workspace.imageSnapshot(workspaceID: workspace.workspaceID)
            let saved = try Data(contentsOf: root.appendingPathComponent("Work/Note.md"))
            XCTAssertTrue(String(decoding: saved, as: UTF8.self).contains("Saved draft text."))
            let occurrence = try XCTUnwrap(NativeInlineImage.occurrences(in: workspace.body).first)
            let review = try await workspace.prepareImageChange(snapshot, action: .remove(note: "Work/Note.md", occurrence: occurrence))
            XCTAssertTrue(review.plan.files.isEmpty)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Note.md")), saved, "Preparing a review must not remove the image")
            try await workspace.applyImageChange(review)
            XCTAssertEqual(NativeInlineImage.occurrences(in: workspace.body).count, 1)
            XCTAssertTrue(workspace.body.contains("Keep second " + second)); XCTAssertTrue(workspace.body.contains("Saved draft text."))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/plot.png")), self.png)
            let undo = try await workspace.prepareImageUndo(try XCTUnwrap(workspace.imageUndo))
            try await workspace.applyImageChange(undo)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Note.md")), saved)
            XCTAssertEqual(workspace.current?.parts.body, workspace.body); XCTAssertNil(workspace.imageUndo)
        }
        }
    }
    func testSizedHtmlOccurrenceRemovalUndoAndTrashRestoreRetainMarkupAndResourceBytes() async throws {
        let html = "<img src=\"../assets/plot.png\" alt=\"Café &amp; notes\" title=\"Review\" width=\"240\" height=\"90\" />"
        try await fixture(body: "# Sized image 🧑🏽‍💻\r\n\r\n" + html + "\r\n\r\nKeep _this spelling_.\r\n") { root, workspace in
            let original = try Data(contentsOf: root.appendingPathComponent("Work/Note.md")), origin = workspace.workspaceID
            let snapshot = try await workspace.imageSnapshot(workspaceID: origin), occurrence = try XCTUnwrap(NativeInlineImage.occurrences(in: workspace.body).first)
            XCTAssertEqual(occurrence.markdown, html); XCTAssertEqual(occurrence.caption, "Café & notes"); XCTAssertEqual(occurrence.title, "Review")
            try await workspace.applyImageChange(workspace.prepareImageChange(snapshot, action: .remove(note: "Work/Note.md", occurrence: occurrence)))
            XCTAssertTrue(NativeInlineImage.occurrences(in: workspace.body).isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/plot.png").path))
            let undo = try await workspace.prepareImageUndo(try XCTUnwrap(workspace.imageUndo)); try await workspace.applyImageChange(undo)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Note.md")), original)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/plot.png")), self.png)
            let fresh = try await workspace.imageSnapshot(workspaceID: origin), image = try XCTUnwrap(NativeInlineImage.occurrences(in: workspace.body).first)
            try await workspace.applyImageChange(workspace.prepareImageChange(fresh, action: .remove(note: "Work/Note.md", occurrence: image)))
            let deleted = try await workspace.imageSnapshot(workspaceID: origin), entry = try XCTUnwrap(deleted.index.entries.first)
            try await workspace.applyImageChange(workspace.prepareImageChange(deleted, action: .restore(id: entry.id, reattach: true)))
            let restored = try XCTUnwrap(NativeInlineImage.occurrences(in: workspace.body).first)
            XCTAssertEqual(restored.markdown, html); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/plot.png")), self.png)
        }
    }
    func testUnusedImageRestoreAndStaleReviewsKeepVaultsAndOutsideChangesIntact() async throws {
        try await fixture(body: "# Image note\n\n" + image + "\n\nKeep annotation.\n") { root, workspace in
            let origin = workspace.workspaceID, original = try Data(contentsOf: root.appendingPathComponent("Work/Note.md"))
            let snapshot = try await workspace.imageSnapshot(workspaceID: origin), occurrence = try XCTUnwrap(NativeInlineImage.occurrences(in: workspace.body).first)
            try await workspace.applyImageChange(workspace.prepareImageChange(snapshot, action: .remove(note: "Work/Note.md", occurrence: occurrence)))
            XCTAssertTrue(NativeInlineImage.occurrences(in: workspace.body).isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/plot.png").path))
            let removed = try await workspace.imageSnapshot(workspaceID: origin), entry = try XCTUnwrap(removed.index.entries.first)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(entry.trashPath)), self.png)
            let restore = try await workspace.prepareImageChange(removed, action: .restore(id: entry.id, reattach: true))
            try await workspace.applyImageChange(restore)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/plot.png")), self.png)
            XCTAssertEqual(NativeInlineImage.occurrences(in: workspace.body).count, 1)
            XCTAssertTrue(workspace.body.contains("Keep annotation.")); XCTAssertTrue(workspace.current?.content.hasPrefix("---\r\nzerus-id: image-note\r\nforeign: 'Keep: this'\r\n---\r\n") == true)
            let restored = try await workspace.imageSnapshot(workspaceID: origin), current = try XCTUnwrap(NativeInlineImage.occurrences(in: workspace.body).first)
            let stale = try await workspace.prepareImageChange(restored, action: .remove(note: "Work/Note.md", occurrence: current))
            let outside = try Data(contentsOf: root.appendingPathComponent("Work/Note.md")) + Data("\nOutside edit.\n".utf8)
            try outside.write(to: root.appendingPathComponent("Work/Note.md"))
            do { try await workspace.applyImageChange(stale); XCTFail("Outside changes must invalidate the review") } catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("changed")) }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Note.md")), outside)
            let other = root.appendingPathComponent("OtherVault"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true); try original.write(to: other.appendingPathComponent("Other.md"))
            defer { UserDefaults.standard.removeObject(forKey: MacNavigationState.key(other)); UserDefaults.standard.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(other.path)) }
            await workspace.openVault(other)
            let directory = workspace.taskDraftStore?.directory
            defer { if let directory { try? FileManager.default.removeItem(at: directory) } }
            do { try await workspace.applyImageChange(stale); XCTFail("A review must remain bound to its original vault") } catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
            XCTAssertEqual(try Data(contentsOf: other.appendingPathComponent("Other.md")), original)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Note.md")), outside)
        }
    }
    private func fixture(body: String, operation: (URL, MacWorkspace) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-image-management-" + UUID().uuidString), defaults = UserDefaults.standard
        let recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true); try FileManager.default.createDirectory(at: root.appendingPathComponent("Work"), withIntermediateDirectories: true)
        try png.write(to: root.appendingPathComponent("assets/plot.png"))
        try Data(("---\r\nzerus-id: image-note\r\nforeign: 'Keep: this'\r\n---\r\n" + body).utf8).write(to: root.appendingPathComponent("Work/Note.md"))
        let workspace = MacWorkspace(); await workspace.openVault(root); await workspace.openNote("Work/Note.md")
        let directory = workspace.taskDraftStore?.directory
        defer { if let directory { try? FileManager.default.removeItem(at: directory) }; defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path)); try? FileManager.default.removeItem(at: root) }
        try await operation(root, workspace)
    }
}
