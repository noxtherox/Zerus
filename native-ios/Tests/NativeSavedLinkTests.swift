import XCTest
import UIKit
@testable import ZerusNative

final class NativeSavedLinkTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func disk(_ path: String, _ text: String) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file, options: .atomic)
    }
    private func paths() throws -> [String] { try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/links.json"))) as! [String] }

    func testCreationNormalizesDeduplicatesAndPreservesForeignIndexEntriesWithoutFollowingThem() async throws {
        let io = VaultFiles(root: root)
        let foreign = ["future:entry", ".zerus/links/../../outside.md"]
        try disk(".zerus/links.json", String(decoding: try JSONSerialization.data(withJSONObject: foreign), as: UTF8.self))
        let note = try await io.createSavedLink(address: " <HTTPS://WWW.Example.com:443/read?q=one#top> ", title: "")
        XCTAssertEqual(note.title, "example.com")
        XCTAssertEqual(note.savedLink?.url?.absoluteString, "https://www.example.com/read?q=one#top")
        XCTAssertEqual(note.savedLink?.id, note.stableID)
        XCTAssertTrue(note.unfiledSavedLink); XCTAssertFalse(note.regularCollectionNote)
        XCTAssertEqual(try paths(), foreign + [note.path])
        let bytes = try await io.read(note.path)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), note.content)
        XCTAssertTrue(note.parts.body.contains("<https://www.example.com/read?q=one#top>"))
        let duplicate = try await io.createSavedLink(address: "https://www.example.com/read?q=one#top", title: "Do not replace its title")
        XCTAssertEqual(duplicate.path, note.path); XCTAssertEqual(duplicate.content, note.content)
        XCTAssertEqual(try paths(), foreign + [note.path])
        for invalid in ["", "javascript:alert(1)", "file:///private/test", "data:text/html,hello", "https://", "https://example.com:65536/", "https://example.com\nunsafe"] {
            do { _ = try await io.createSavedLink(address: invalid, title: "Invalid"); XCTFail("Accepted unsafe address: " + invalid) } catch {}
        }
        let unchanged = try await io.scan()
        XCTAssertEqual(unchanged.notes.count, 1)
        XCTAssertEqual(try paths(), foreign + [note.path])
        try disk(".zerus/links.json", "{\"future\":true}")
        do { _ = try await io.createSavedLink(address: "another.example/new", title: "Blocked"); XCTFail("Unsupported index must not be overwritten") } catch {}
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(".zerus/links.json"), encoding: .utf8), "{\"future\":true}")
        let blocked = try await io.scan(); XCTAssertEqual(blocked.notes.count, 1)
    }

    func testAddressChangePreservesYAMLCodeProseReferencesAndHistoryAndRejectsDuplicatesAndStaleNotes() async throws {
        let io = VaultFiles(root: root), old = "https://example.com/old", new = "https://example.com/new?q=one&two=2"
        let created = try await io.createSavedLink(address: old, title: "My research 😀")
        let header = created.parts.header
        let foreignHeader = try NativeFrontmatter(header).setting("Foreign", value: .text("Keep this value"))
        let body = "# My research 😀\n\n<\(old)>\n\nSee [the source](\(old)) for details.\n\n```md\n<\(old)>\n```\n\n[ref]: \(old) \"Keep definition\"\n\n[Read again][ref]\n\nOriginal **notes**.\n"
        let content = (foreignHeader + body).replacingOccurrences(of: "\n", with: "\r\n")
        try disk(created.path, content)
        let note = NoteDocument(path: created.path, content: content, modified: Date())
        let indexBefore = try Data(contentsOf: root.appendingPathComponent(".zerus/links.json"))
        let result = try await io.updateSavedLink(note, address: new)
        let saved = try XCTUnwrap(result.notes.first { $0.path == note.path })
        XCTAssertEqual(saved.title, "My research 😀")
        XCTAssertEqual(saved.property("Foreign"), "Keep this value")
        XCTAssertEqual(saved.savedLink?.url?.absoluteString, new)
        XCTAssertTrue(saved.parts.body.contains("<\(new)>\r\n"))
        XCTAssertTrue(saved.parts.body.contains("See [the source](\(old)) for details.\r\n"))
        XCTAssertTrue(saved.parts.body.contains("```md\r\n<\(old)>\r\n```"))
        XCTAssertTrue(saved.parts.body.contains("[ref]: \(old) \"Keep definition\""))
        XCTAssertFalse(saved.parts.body.contains("[Read again][ref]"), "Only the standalone managed link usage is replaced; its definition stays")
        XCTAssertTrue(saved.parts.body.contains("Original **notes**."))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/links.json")), indexBefore)
        let history = try await io.historySnapshot(notePath: note.path)
        XCTAssertTrue(history.versions.contains { $0.content == content }); XCTAssertTrue(history.versions.contains { $0.content == saved.content })
        let duplicate = try await io.createSavedLink(address: "https://duplicate.example/", title: "Other")
        do { _ = try await io.updateSavedLink(saved, address: duplicate.savedLink!.address); XCTFail("A duplicate URL must be rejected") } catch {}
        do { _ = try await io.updateSavedLink(note, address: "https://new.example/"); XCTFail("A stale note must not overwrite later text") } catch {}
        let actual = try await io.read(note.path); XCTAssertEqual(actual, Data(saved.content.utf8))
    }

    func testFilingReviewsIndexBytesAndTrashRestoreKeepTheSharedCollectionAndHiddenNotesConsistent() async throws {
        let io = VaultFiles(root: root), note = try await io.createSavedLink(address: "example.com/first", title: "First link")
        let other = try await io.createSavedLink(address: "example.com/second", title: "Second link")
        let review = try await io.prepareMove(io.relationDefinitionSnapshot(), source: note.path, destination: "Work/First link.md")
        XCTAssertTrue(review.changes.contains { $0.path == ".zerus/links.json" && $0.before != $0.after })
        let originalIndex = try String(contentsOf: root.appendingPathComponent(".zerus/links.json"), encoding: .utf8)
        try disk(".zerus/links.json", "[\"Changed externally\"]")
        do { _ = try await io.applyRelationMaintenance(review); XCTFail("A reviewed move must reject a changed shared index") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(note.path).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/First link.md").path))
        try disk(".zerus/links.json", originalIndex)
        let fresh = try await io.prepareMove(io.relationDefinitionSnapshot(), source: note.path, destination: "Work/First link.md")
        let filed = try await io.applyRelationMaintenance(fresh)
        let moved = try XCTUnwrap(filed.notes.first { $0.path == "Work/First link.md" })
        XCTAssertEqual(moved.savedLink?.id, note.savedLink?.id)
        XCTAssertTrue(moved.regularCollectionNote); XCTAssertFalse(moved.unfiledSavedLink)
        XCTAssertEqual(try paths(), [other.path])
        let trash = ".trash/" + other.path
        try await io.move(other.path, to: trash, expected: Data(other.content.utf8))
        XCTAssertEqual(try paths(), [])
        let deleted = try await io.scan()
        XCTAssertTrue(deleted.notes.contains { $0.path == trash && $0.trashed })
        XCTAssertEqual(try VaultFiles.notePathInventory(root: root), Set(deleted.notes.map(\.path)))
        try await io.move(trash, to: other.path, expected: Data(other.content.utf8))
        XCTAssertEqual(try paths(), [other.path])
        let restored = try await io.scan()
        XCTAssertTrue(restored.notes.contains { $0.path == other.path && !$0.trashed })
    }

    @MainActor
    func testStoreAddressEditPreservesTheEditorAndOldWorkspaceFormsCannotMutateAfterReactivation() async throws {
        let store = VaultStore(); await store.open(root)
        let origin = store.workspaceID
        let note = try await store.createSavedLink(address: "example.com/original", title: "Original", workspace: origin)
        let session = try XCTUnwrap(store.session(for: note))
        for typed in ["# Original", "# Original\n", "# Original\n\nN", "# Original\n\nNotes", "No heading\nAnother line", "\n\n", "", "# Title\r\n\r\nNotes without a final newline"] {
            session.updateBody(NativeSavedLink.withURL(typed, address: note.savedLink!.address))
            XCTAssertEqual(NativeSavedLink.withoutURL(session.document.parts.body, address: note.savedLink!.address), typed, "The managed URL must not alter the live editor buffer between keystrokes")
        }
        let body = "# Original\n\nNotes typed on the phone.\n"
        session.updateBody(NativeSavedLink.withURL(body, address: note.savedLink!.address)); await session.save()
        try await store.updateSavedLink(session: session, address: "example.com/updated", originalAddress: note.savedLink!.address, workspace: origin)
        XCTAssertEqual(session.document.savedLink?.url?.absoluteString, "https://example.com/updated")
        XCTAssertEqual(NativeSavedLink.withoutURL(session.document.parts.body, address: session.document.savedLink!.address), body)
        XCTAssertFalse(session.dirty)
        let second = root.appendingPathComponent("OtherVault")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        await store.open(second); await store.open(root)
        do { _ = try await store.createSavedLink(address: "example.com/stale", title: "Stale", workspace: origin); XCTFail("The old form cannot create after A → B → A") } catch {}
        do { try await store.updateSavedLink(session: session, address: "example.com/stale", originalAddress: session.document.savedLink!.address, workspace: origin); XCTFail("A retained editor cannot update the reactivated vault") } catch {}
        let io = VaultFiles(root: root), current = try await io.scan()
        XCTAssertEqual(current.notes.count, 1)
        XCTAssertEqual(current.notes.first?.savedLink?.url?.absoluteString, "https://example.com/updated")
    }
    @MainActor
    func testFullNoteClipboardIncludesTheURLCardInMarkdownAndRichTextWhileSelectionRemainsSelectionOnly() async throws {
        let board = UIPasteboard.general
        board.items = []
        defer { board.items = [] }
        let visible = "# Saved page\n\nPersonal notes.\n", address = "https://example.com/saved"
        let actions = NativeEditorActions()
        var linkCompletion: XCTestExpectation?
        let linked = NativeTextEditor(markdown: visible, source: false, onChange: { _ in }, onImage: { _ in }, onLink: { _ in },
            onClipboardBusy: { if !$0 { let pending = linkCompletion; linkCompletion = nil; pending?.fulfill() } }, wholeNoteMarkdown: { NativeSavedLink.withURL($0, address: address) }).makeCoordinator()
        let linkedView = ZerusTextView(frame: .zero, textContainer: nil)
        linked.view = linkedView; linkedView.delegate = linked; linked.load(visible, source: false); actions.coordinator = linked
        let copiedNote = expectation(description: "Copy note includes the canonical address"); linkCompletion = copiedNote
        actions.copyNote(); await fulfillment(of: [copiedNote], timeout: 10)
        let copied = try NativeClipboardFragment.decode(try XCTUnwrap(board.data(forPasteboardType: NativeClipboardFragment.type)))
        XCTAssertTrue(copied.markdown.contains("<" + address + ">")); XCTAssertTrue(copied.markdown.contains("Personal notes."))
        let rtf = try XCTUnwrap(board.data(forPasteboardType: "public.rtf"))
        let rich = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        XCTAssertTrue(rich.string.contains(address))
        actions.copyMarkdown(); XCTAssertTrue(board.string?.contains(address) == true)
        let copiedSelection = expectation(description: "Copy selection excludes the separate URL card"); linkCompletion = copiedSelection
        let selection = (linkedView.attributedText.string as NSString).range(of: "Personal notes.")
        linked.copySelection(selection, cut: false); await fulfillment(of: [copiedSelection], timeout: 10)
        let selected = try NativeClipboardFragment.decode(try XCTUnwrap(board.data(forPasteboardType: NativeClipboardFragment.type)))
        XCTAssertEqual(selected.markdown, "Personal notes."); XCTAssertFalse(selected.markdown.contains(address))
    }

}
