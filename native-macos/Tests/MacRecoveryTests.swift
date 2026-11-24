import XCTest
import AppKit
@testable import Zerus_Native

@MainActor final class MacRecoveryTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    func testRevisionReviewIsReadOnlyAndRestoresFrozenImageWithCurrentTitleAndProperties() async throws {
        try await fixture { root, workspace, request in
            let noteFile = root.appendingPathComponent(request.path), original = try Data(contentsOf: noteFile)
            let initial = try await workspace.recoverySnapshot(request), create = try await workspace.prepareRecovery(initial, action: .create)
            XCTAssertEqual(try Data(contentsOf: noteFile), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(try XCTUnwrap(initial.revisions).indexPath).path))
            XCTAssertTrue(create.resources.contains { $0.after == self.png })
            let lease = try workspace.recoveryResource(try XCTUnwrap(create.resources.first), review: create)
            XCTAssertEqual(try lease.readForCopy(), self.png)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(create.resources[0].path).path))
            try await workspace.commitRecovery(create)
            workspace.changed("# Renamed today\n\nNew text.\n"); let saved = await workspace.save(); XCTAssertTrue(saved)
            let bytes = self.png + Data([1]); try bytes.write(to: root.appendingPathComponent("assets/plot.png"))
            let snapshot = try await workspace.recoverySnapshot(request), revisions = try XCTUnwrap(snapshot.revisions), old = try XCTUnwrap(revisions.index.revisions.first { $0.id != revisions.index.currentID })
            let review = try await workspace.prepareRecovery(snapshot, action: .promote(old.id))
            XCTAssertTrue(review.content.contains("# Renamed today")); XCTAssertTrue(review.content.contains("Old text.")); XCTAssertTrue(review.content.contains("foreign: {keep: [1, 2]} # retained"))
            XCTAssertTrue(review.resources.contains { $0.before == nil && $0.after == self.png })
            XCTAssertFalse(review.images.isEmpty)
            let rendered = MacMarkdown.render(NoteDocument.split(review.content).body, images: review.images)
            var attachments = 0; rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in if value is NSTextAttachment { attachments += 1 } }
            XCTAssertEqual(attachments, 1, "The result preview must render saved bytes before its future file exists")
            try await workspace.commitRecovery(review)
            XCTAssertTrue(workspace.body.contains("Old text.")); XCTAssertTrue(workspace.body.contains("# Renamed today"))
            let reference = try XCTUnwrap(MarkdownText.imageReferences(workspace.body).first)
            XCTAssertEqual(try Data(contentsOf: VaultFiles.resolveResource(reference, notePath: request.path, root: root)), self.png)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/plot.png")), bytes)
            XCTAssertEqual(workspace.current?.stableID, "recovery-note")
        }
    }
    func testReviewedRecoveryRejectsOutsideIndexResourceChangesAndOldVaultActivation() async throws {
        try await fixture { root, workspace, request in
            let initial = try await workspace.recoverySnapshot(request), create = try await workspace.prepareRecovery(initial, action: .create)
            try await workspace.commitRecovery(create)
            let snapshot = try await workspace.recoverySnapshot(request), revisions = try XCTUnwrap(snapshot.revisions), old = try XCTUnwrap(revisions.index.revisions.first { $0.id != revisions.index.currentID })
            let review = try await workspace.prepareRecovery(snapshot, action: .promote(old.id))
            let noteFile = root.appendingPathComponent(request.path), before = try Data(contentsOf: noteFile), indexFile = root.appendingPathComponent(revisions.indexPath), indexBytes = try Data(contentsOf: indexFile)
            var index = try XCTUnwrap(JSONSerialization.jsonObject(with: indexBytes) as? [String: Any]); index["outsideField"] = "Keep"
            let outsideIndex = try JSONSerialization.data(withJSONObject: index); try outsideIndex.write(to: indexFile)
            do { try await workspace.commitRecovery(review); XCTFail("An index edit must invalidate the exact approved plan") } catch {}
            XCTAssertEqual(try Data(contentsOf: noteFile), before); XCTAssertEqual(try Data(contentsOf: indexFile), outsideIndex)
            try indexBytes.write(to: indexFile)
            let resource = try XCTUnwrap(review.changes.first { $0.before != nil && $0.before == self.png }), resourceFile = root.appendingPathComponent(resource.path), outsideBytes = self.png + Data([2])
            try outsideBytes.write(to: resourceFile)
            do { try await workspace.commitRecovery(review); XCTFail("A saved resource edit must invalidate the review") } catch {}
            XCTAssertEqual(try Data(contentsOf: noteFile), before); XCTAssertEqual(try Data(contentsOf: resourceFile), outsideBytes)
            await workspace.openVault(root)
            do { try await workspace.commitRecovery(review); XCTFail("The old activation must not be accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
            XCTAssertEqual(try Data(contentsOf: noteFile), before)
        }
    }
    func testAutomaticHistoryReviewRestoresSavedImageAndRejectsLaterNoteEdit() async throws {
        try await fixture { root, workspace, request in
            workspace.changed("# Today\n\nNew text.\n"); let saved = await workspace.save(); XCTAssertTrue(saved)
            try (self.png + Data([3])).write(to: root.appendingPathComponent("assets/plot.png"))
            let snapshot = try await workspace.recoverySnapshot(request), old = try XCTUnwrap(try XCTUnwrap(snapshot.history).versions.first { $0.content?.contains("Old text.") == true })
            let noteBefore = try Data(contentsOf: root.appendingPathComponent(request.path))
            let browser = try await workspace.historyPreview(snapshot, id: old.id)
            XCTAssertEqual(browser.imageCount, 1); XCTAssertTrue(browser.warnings.isEmpty)
            let blob = try XCTUnwrap(browser.images.keys.first)
            XCTAssertEqual(blob, ".zerus/history/blobs/" + NativeHistory.hash(self.png))
            XCTAssertTrue(browser.content.contains(blob)); XCTAssertFalse(browser.content.contains("../assets/plot.png"))
            let rendered = MacMarkdown.render(NoteDocument.split(browser.content).body, root: nil, path: request.path, images: browser.images)
            var available = 0
            rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, range, _ in
                if value is NSTextAttachment, rendered.attribute(.macImageUnavailable, at: range.location, effectiveRange: nil) == nil { available += 1 }
            }
            XCTAssertEqual(available, 1, "The browser must show the frozen image before any restore review")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(request.path)), noteBefore)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/plot.png")), self.png + Data([3]))
            let blobFile = root.appendingPathComponent(blob)
            for corrupt in [true, false] {
                if corrupt { try Data("Changed snapshot".utf8).write(to: blobFile) }
                else { try FileManager.default.removeItem(at: blobFile) }
                let unavailable = try await workspace.historyPreview(snapshot, id: old.id)
                XCTAssertTrue(unavailable.images.isEmpty); XCTAssertEqual(unavailable.warnings.count, 1)
                if corrupt { XCTAssertTrue(unavailable.warnings[0].contains("saved bytes changed")) }
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(request.path)), noteBefore)
            }
            try self.png.write(to: blobFile)
            let review = try await workspace.prepareHistoryRecovery(snapshot, id: old.id)
            XCTAssertTrue(review.resources.contains { $0.after == self.png }); XCTAssertFalse(review.images.isEmpty)
            let noteFile = root.appendingPathComponent(request.path), current = try Data(contentsOf: noteFile), outside = current + Data("\nOutside edit.\n".utf8)
            try outside.write(to: noteFile)
            do { try await workspace.commitRecovery(review); XCTFail("The outside edit must survive") } catch {}
            XCTAssertEqual(try Data(contentsOf: noteFile), outside)
            await workspace.refresh(); await workspace.reloadCurrent()
            let fresh = try await workspace.recoverySnapshot(request), accepted = try await workspace.prepareHistoryRecovery(fresh, id: old.id)
            try await workspace.commitRecovery(accepted)
            XCTAssertTrue(workspace.body.contains("Old text.")); XCTAssertEqual(workspace.current?.stableID, "recovery-note")
            let reference = try XCTUnwrap(MarkdownText.imageReferences(workspace.body).first)
            XCTAssertEqual(try Data(contentsOf: VaultFiles.resolveResource(reference, notePath: request.path, root: root)), self.png)
            let history = try await workspace.recoverySnapshot(request)
            XCTAssertTrue(try XCTUnwrap(history.history).versions.contains { $0.content?.contains("Outside edit.") == true })
            await workspace.openVault(root)
            do { _ = try await workspace.historyPreview(snapshot, id: old.id); XCTFail("An old activation must not load saved images") }
            catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
        }
    }
    func testHistoryBrowserPagesAllFrozenImagesWithoutWritingAndRejectsChangedRecords() async throws {
        try await fixture { root, workspace, request in
            var content = "# Nine images\n", expected = Set<String>()
            for index in 0..<9 {
                let bytes = self.png + Data([UInt8(index)])
                try bytes.write(to: root.appendingPathComponent("assets/page-\(index).png"))
                content += "\n![Image \(index)](../assets/page-\(index).png)\n"
                expected.insert(".zerus/history/blobs/" + NativeHistory.hash(bytes))
            }
            workspace.changed(content); let saved = await workspace.save(); XCTAssertTrue(saved)
            let snapshot = try await workspace.recoverySnapshot(request)
            let version = try XCTUnwrap(snapshot.history?.versions.first { $0.content?.contains("# Nine images") == true })
            let paths = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { path in
                var directory: ObjCBool = false
                return FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path, isDirectory: &directory) && !directory.boolValue
            }
            let before = try Dictionary(uniqueKeysWithValues: paths.map { ($0, try Data(contentsOf: root.appendingPathComponent($0))) })
            let first = try await workspace.historyPreview(snapshot, id: version.id)
            XCTAssertEqual(first.page, 0); XCTAssertEqual(first.pages, 2); XCTAssertEqual(first.imageCount, 9)
            XCTAssertEqual(first.images.count, 8); XCTAssertTrue(first.warnings.isEmpty)
            let last = try await workspace.historyPreview(snapshot, id: version.id, page: 1)
            XCTAssertEqual(last.page, 1); XCTAssertEqual(last.images.count, 1); XCTAssertTrue(last.warnings.isEmpty)
            XCTAssertTrue(Set(first.images.keys).isDisjoint(with: last.images.keys))
            XCTAssertEqual(Set(first.images.keys).union(last.images.keys), expected, "Every saved image must remain reachable across pages")
            let again = try await workspace.historyPreview(snapshot, id: version.id, page: 0)
            XCTAssertEqual(Set(again.images.keys), Set(first.images.keys))
            for (path, bytes) in before { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), bytes, path) }
            let after = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { path in
                var directory: ObjCBool = false
                return FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path, isDirectory: &directory) && !directory.boolValue
            }
            XCTAssertEqual(Set(after), Set(before.keys), "Browsing must not create restore copies or other vault files")
            let record = root.appendingPathComponent(version.path), changed = version.bytes + Data(" ".utf8)
            try changed.write(to: record)
            do { _ = try await workspace.historyPreview(snapshot, id: version.id); XCTFail("A changed record requires reloading the version") }
            catch { XCTAssertTrue(error.localizedDescription.contains("history record changed")) }
            XCTAssertEqual(try Data(contentsOf: record), changed)
            try version.bytes.write(to: record)
            let canceled = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await workspace.historyPreview(snapshot, id: version.id)
            }
            do { _ = try await canceled.value; XCTFail("A canceled preview must not publish images") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
    }
    func testDamagedRevisionIndexDoesNotHideOrBlockAutomaticHistoryRecovery() async throws {
        try await fixture { root, workspace, request in
            workspace.changed("# Today\n\nA newer draft.\n"); let saved = await workspace.save(); XCTAssertTrue(saved)
            let index = root.appendingPathComponent(".zerus/revisions/notes/recovery-note/index.json"), broken = Data("{\"unsupported\":true}".utf8)
            try FileManager.default.createDirectory(at: index.deletingLastPathComponent(), withIntermediateDirectories: true); try broken.write(to: index)
            let snapshot = try await workspace.recoverySnapshot(request), history = try XCTUnwrap(snapshot.history)
            XCTAssertNil(snapshot.revisions)
            let old = try XCTUnwrap(history.versions.first { $0.content?.contains("Old text.") == true })
            let review = try await workspace.prepareHistoryRecovery(snapshot, id: old.id)
            try await workspace.commitRecovery(review)
            XCTAssertTrue(workspace.body.contains("Old text.")); XCTAssertEqual(try Data(contentsOf: index), broken)
            try FileManager.default.removeItem(at: index)
            let settings = root.appendingPathComponent(".zerus/history-settings.json"), unsupported = Data("{\"enabled\":\"unsupported\",\"checkpointLimit\":10}".utf8)
            try unsupported.write(to: settings)
            let other = try await workspace.recoverySnapshot(request), revisions = try XCTUnwrap(other.revisions)
            XCTAssertNil(other.history)
            XCTAssertTrue(try revisions.content(for: XCTUnwrap(revisions.index.revisions.first)).contains("Old text."))
            XCTAssertEqual(try Data(contentsOf: settings), unsupported)
        }
    }
    private func fixture(operation: (URL, MacWorkspace, MacRecoveryRequest) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-recovery-" + UUID().uuidString), defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work"), withIntermediateDirectories: true); try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data("---\nzerus-id: recovery-note\nforeign: {keep: [1, 2]} # retained\n---\n# Original\n\nOld text.\n\n![Plot](../assets/plot.png)\n".utf8).write(to: root.appendingPathComponent("Work/Note.md")); try png.write(to: root.appendingPathComponent("assets/plot.png"))
        let workspace = MacWorkspace(); await workspace.openVault(root); await workspace.openNote("Work/Note.md"); let drafts = workspace.taskDraftStore?.directory
        defer { if let drafts { try? FileManager.default.removeItem(at: drafts) }; defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path)); try? FileManager.default.removeItem(at: root) }
        try await operation(root, workspace, .init(workspaceID: workspace.workspaceID, path: "Work/Note.md"))
    }
}
