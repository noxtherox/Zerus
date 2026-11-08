import XCTest
import Combine
@testable import ZerusNative

final class NativeNoteLinkEditingTests: XCTestCase {
    @MainActor
    private func attach(_ coordinator: NativeTextEditor.Coordinator) throws -> (UIWindow, UIWindow?) {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let scene = try XCTUnwrap(previous?.windowScene)
        let window = UIWindow(windowScene: scene), controller = UIViewController()
        window.rootViewController = controller
        let view = try XCTUnwrap(coordinator.view)
        controller.view.addSubview(view); view.frame = CGRect(x: 0, y: 0, width: 390, height: 400)
        window.makeKeyAndVisible(); XCTAssertTrue(view.becomeFirstResponder())
        return (window, previous)
    }
    @MainActor
    private func request(_ actions: NativeEditorActions, coordinator: NativeTextEditor.Coordinator) async throws -> NativeNoteLinkRequest {
        let ready = expectation(description: "Committed text offers a note link")
        let observation = actions.$noteLink.compactMap { $0 }.prefix(1).sink { _ in ready.fulfill() }
        coordinator.refreshNoteLink()
        await fulfillment(of: [ready], timeout: 3)
        withExtendedLifetime(observation) {}
        return try XCTUnwrap(actions.noteLink)
    }

    @MainActor
    func testLinkInsertionAtUnicodeCaretPreservesSavedMarkdownUndoAndRejectsStaleSelectionsAndDocuments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "---\nzerus-id: compose\nforeign: keep\n---\n# Compose\n\n**Before 😀** @Al after."
        try Data(original.utf8).write(to: root.appendingPathComponent("Compose.md"))
        let io = VaultFiles(root: root), actions = NativeEditorActions()
        var destination = NoteReference(target: "zerus:alpha", label: "Alpha", explicitLabel: true)
        var linkIssues: [String] = []
        let session = NoteSession(note: .init(path: "Compose.md", content: original, modified: .now), root: root, io: io, onSave: { _ in })
        defer { session.deactivate() }
        let editor = NativeTextEditor(markdown: session.document.parts.body, source: false, onChange: session.updateBody, onImage: { _ in }, onLink: { _ in }, actions: actions, documentID: "vault-a|Compose.md",
            noteLinkOptions: { _ in [.init(path: "Alpha.md", title: "Alpha")] },
            resolveNoteLink: { $0 == "Alpha.md" ? destination : nil }, onNoteLinkIssue: { linkIssues.append($0) })
        let coordinator = editor.makeCoordinator(), view = ZerusTextView(frame: .zero, textContainer: nil)
        coordinator.view = view; actions.coordinator = coordinator; view.delegate = coordinator; coordinator.load(editor.markdown, source: false)
        let (window, previous) = try attach(coordinator)
        defer { view.resignFirstResponder(); window.isHidden = true; previous?.makeKeyAndVisible() }
        let token = (view.text as NSString).range(of: "@Al")
        view.selectedRange = NSRange(location: NSMaxRange(token), length: 0)
        let offered = try await request(actions, coordinator: coordinator)
        XCTAssertEqual(offered.query, "Al"); XCTAssertTrue(offered.insert("Alpha.md"))
        await session.save()
        let expected = "---\nzerus-id: compose\nforeign: keep\n---\n# Compose\n\n**Before 😀** [[zerus:alpha|Alpha]] after."
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Compose.md"), encoding: .utf8), expected)
        XCTAssertNil(view.typingAttributes[.link], "Following prose must not inherit the note link")
        view.undoManager?.undo(); await session.save()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Compose.md"), encoding: .utf8), original)
        view.undoManager?.redo(); await session.save()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Compose.md"), encoding: .utf8), expected)

        // A pending menu must not replace a different selection or another
        // document that happens to have identical visible text.
        coordinator.load(editor.markdown, source: false); view.selectedRange = NSRange(location: NSMaxRange(token), length: 0)
        let stale = try await request(actions, coordinator: coordinator)
        destination = NoteReference(target: "zerus:replacement", label: "Replacement", explicitLabel: true)
        XCTAssertFalse(stale.insert("Alpha.md"), "An outside replacement at the same path must not receive a link intended for the old note")
        destination = NoteReference(target: "zerus:alpha", label: "Alpha", explicitLabel: true)
        view.selectedRange = NSRange(location: 0, length: 0)
        XCTAssertFalse(stale.insert("Alpha.md")); XCTAssertEqual(view.text, "Compose\n\nBefore 😀 @Al after.")
        view.selectedRange = NSRange(location: NSMaxRange(token), length: 0)
        coordinator.parent.documentID = "vault-b|Compose.md"
        XCTAssertFalse(stale.insert("Alpha.md")); XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Compose.md"), encoding: .utf8), expected)
        coordinator.parent.documentID = editor.documentID

        // A selected alias keeps each run's style while becoming one link.
        for (source, selected, expectedBody) in [
            (editor.markdown, "Before 😀 @Al", "# Compose\n\n[**Before 😀** @Al](#zerus-note:zerus%3Aalpha%7CBefore%20%F0%9F%98%80%20%40Al) after."),
            ("# Compose\n\nSee **bold** and `code` after.", "bold and code", "# Compose\n\nSee [**bold** and `code`](#zerus-note:zerus%3Aalpha%7Cbold%20and%20code) after.")
        ] {
            coordinator.load(source, source: false)
            session.updateBody(source); await session.save()
            let before = try Data(contentsOf: root.appendingPathComponent("Compose.md"))
            view.selectedRange = (view.text as NSString).range(of: selected)
            let manual = try XCTUnwrap(coordinator.manualNoteLink())
            XCTAssertTrue(manual("Alpha.md")); await session.save()
            XCTAssertEqual(session.document.parts.body, expectedBody)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Compose.md"), encoding: .utf8), "---\nzerus-id: compose\nforeign: keep\n---\n" + expectedBody)
            view.undoManager?.undo(); await session.save()
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Compose.md")), before)
            view.undoManager?.redo(); await session.save()
            XCTAssertEqual(session.document.parts.body, expectedBody)
        }
        // A prose link must never consume an image or a paragraph boundary.
        let saved = try Data(contentsOf: root.appendingPathComponent("Compose.md"))
        for (source, selected) in [("# Compose\n\nBefore ![Plot](assets/plot.png) after.", "\u{fffc}"), ("# Compose\n\nFirst.\n\nSecond.", "First.\n\nSecond.")] {
            coordinator.load(source, source: false)
            view.selectedRange = (view.text as NSString).range(of: selected)
            let unchanged = NSAttributedString(attributedString: view.attributedText)
            linkIssues = []
            XCTAssertNil(coordinator.manualNoteLink(), "Choose inline prose without consuming attachments or paragraph breaks")
            XCTAssertFalse(linkIssues.last?.isEmpty ?? true, "A refused selection needs visible guidance")
            XCTAssertTrue(view.attributedText.isEqual(to: unchanged))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Compose.md")), saved)
        }

    }

    @MainActor
    func testTypingSuggestionsRespectCommittedProseContextAndPreferenceWithoutChangingText() async throws {
        let actions = NativeEditorActions()
        let editor = NativeTextEditor(markdown: "", source: false, onChange: { _ in }, onImage: { _ in }, onLink: { _ in }, actions: actions, documentID: "contexts",
            noteLinkOptions: { _ in [.init(path: "Archive/Álpha.md", title: "Álpha")] },
            resolveNoteLink: { _ in NoteReference(target: "zerus:alpha", label: "Álpha", explicitLabel: true) })
        let coordinator = editor.makeCoordinator(), view = ZerusTextView(frame: .zero, textContainer: nil)
        coordinator.view = view; actions.coordinator = coordinator; view.delegate = coordinator; coordinator.load("", source: false)
        let (window, previous) = try attach(coordinator)
        defer { view.resignFirstResponder(); window.isHidden = true; previous?.makeKeyAndVisible() }
        for (body, token, query) in [("😀 [[Ál", "[[Ál", "Ál"), ("Meet (@Al", "@Al", "Al")] {
            coordinator.load(body, source: false); view.selectedRange = NSRange(location: NSMaxRange((view.text as NSString).range(of: token)), length: 0)
            let offered = try await request(actions, coordinator: coordinator)
            XCTAssertEqual(offered.query, query); offered.dismiss()
            XCTAssertEqual(view.text, body)
        }
        for body in ["email@Al", "`@Al`", "[@Al](https://example.com)", "[[[Al", "@Al\nElsewhere"] {
            coordinator.load(body, source: false)
            let token = (view.text as NSString).range(of: "Al", options: .backwards)
            view.selectedRange = NSRange(location: body.contains("\n") ? view.attributedText.length : NSMaxRange(token), length: 0)
            let hidden = expectation(description: "Excluded context does not offer a link")
            coordinator.refreshNoteLink(); DispatchQueue.main.async { hidden.fulfill() }
            await fulfillment(of: [hidden], timeout: 3)
            XCTAssertNil(actions.noteLink, body)
        }
        coordinator.load("@Al", source: false); view.selectedRange = NSRange(location: 3, length: 0)
        let active = try await request(actions, coordinator: coordinator)
        coordinator.parent.noteLinkShortcuts = false
        XCTAssertFalse(active.insert("Archive/Álpha.md")); coordinator.refreshNoteLink()
        let cleared = expectation(description: "Disabled suggestions clear")
        DispatchQueue.main.async { cleared.fulfill() }; await fulfillment(of: [cleared], timeout: 3)
        XCTAssertNil(actions.noteLink); XCTAssertEqual(view.text, "@Al")
        coordinator.parent.noteLinkShortcuts = true; coordinator.load("@Al", source: true)
        coordinator.refreshNoteLink()
        let source = expectation(description: "Source has no typing suggestions")
        DispatchQueue.main.async { source.fulfill() }; await fulfillment(of: [source], timeout: 3)
        XCTAssertNil(actions.noteLink)
        coordinator.load("@Al", source: false); view.selectedRange = NSRange(location: 3, length: 0)
        let beforeComposition = try await request(actions, coordinator: coordinator)
        view.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0))
        XCTAssertFalse(beforeComposition.insert("Archive/Álpha.md")); coordinator.refreshNoteLink()
        let composition = expectation(description: "IME owns its marked text")
        DispatchQueue.main.async { composition.fulfill() }; await fulfillment(of: [composition], timeout: 3)
        XCTAssertNil(actions.noteLink); view.unmarkText()
    }
}
