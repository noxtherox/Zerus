import XCTest
@testable import ZerusNative

final class NativeCodeCreationTests: XCTestCase {
    @MainActor
    func testConvertingCodeKeepsLiteralDraftContentsOtherBlocksAndSavedUndoWhileRejectingStaleSheets() async throws {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene)), controller = UIViewController()
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let cases: [(body: String, markdown: String)] = [
            ("# Literal heading\n\n- [ ] Task\n**bold** [[do not link]]\nA | B\n--- | ---\n```swift\nprint(42)\n```\n  spaces\t🪴.",
             "\\# Literal heading\n\n\\- \\[ \\] Task\n\\*\\*bold\\*\\* \\[\\[do not link\\]\\]\nA | B\n--- \\| ---\n\\`\\`\\`swift\nprint(42)\n\\`\\`\\`\n  spaces\t🪴."),
            ("", ""),
            ("# Header\r\n\r\n- [ ] Task\r\n\"A\" -- B 🪴", "\\# Header\r\n\r\n\\- \\[ \\] Task\r\n\"A\" -- B 🪴"),
            ("func greet() {\n    print(\"hi\")\n}\n\tIndented\nTrailing  \nnext", "func greet() {\n&#32;   print(\"hi\")\n}\n&#9;Indented\nTrailing &#32;\nnext"),
            ("<b> &amp; &#32; &copy; A & B\n$$ literal\nbackslash \\\nnext", "\\<b\\> \\&amp; \\&#32; \\&copy; A \\& B\n\\$\\$ literal\nbackslash \\\\\nnext")
        ]
        for fixture in cases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let header = "---\nzerus-id: conversion\nforeign: keep\n---\n"
            let prefix = "# Conversion 😀\n\nBefore.\n\n~~~text\noriginal\n~~~\n\n| A | B |\n| --- | --- |\n| one | two |\n\n"
            let suffix = "\n\nAfter."
            let original = header + prefix + "~~~text\noriginal\n~~~" + suffix
            let path = root.appendingPathComponent("Code.md")
            try Data(original.utf8).write(to: path)
            let session = NoteSession(note: .init(path: "Code.md", content: original, modified: .now), root: root, io: VaultFiles(root: root), onSave: { _ in })
            defer { session.deactivate() }
            var request: CodeEditRequest?
            let editor = NativeTextEditor(markdown: session.document.parts.body, source: false, onChange: session.updateBody,
                onImage: { _ in }, onLink: { _ in }, onCode: { request = $0 }, documentID: "vault|Code.md")
            let owner = editor.makeCoordinator(), view = ZerusTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 400), textContainer: nil)
            controller.view.addSubview(view); defer { view.resignFirstResponder(); view.removeFromSuperview() }
            owner.view = view; view.delegate = owner; owner.load(editor.markdown, source: false)
            var codes: [CodeAttachment] = []
            view.attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.attributedText.length)) { value, _, _ in
                if let code = value as? CodeAttachment { codes.append(code) }
            }
            XCTAssertEqual(codes.count, 2)
            try XCTUnwrap(codes.last?.edit)()
            let opened = try XCTUnwrap(request), convert = try XCTUnwrap(opened.convertToText)
            owner.parent.documentID = "other-vault|Code.md"
            XCTAssertFalse(convert(fixture.body)); XCTAssertFalse(opened.save(opened.code))
            owner.parent.documentID = "vault|Code.md"; owner.parent.readOnly = true
            XCTAssertFalse(convert(fixture.body)); XCTAssertFalse(opened.save(opened.code))
            owner.parent.readOnly = false
            owner.load(editor.markdown, source: true); XCTAssertFalse(convert(fixture.body))
            owner.load(editor.markdown + "\nOutside edit.", source: false); XCTAssertFalse(convert(fixture.body))
            XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), original)
            owner.load(editor.markdown, source: false)
            XCTAssertTrue(view.becomeFirstResponder())
            view.undoManager?.removeAllActions()
            XCTAssertTrue(convert(fixture.body), "Existing block conversion is available with creation disabled")
            let expected = header + prefix + fixture.markdown + suffix
            XCTAssertFalse(MarkdownText.requiresSource(session.document.parts.body), "Converting code must leave an ordinary editable note, including indented code lines")
            await session.save()
            XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), expected)
            let caret = view.selectedRange.location
            let literalLength = (fixture.body as NSString).length
            XCTAssertEqual((view.text as NSString).substring(with: NSRange(location: caret - literalLength, length: literalLength)), fixture.body)
            XCTAssertEqual((view.text as NSString).substring(from: caret), suffix)
            XCTAssertTrue(try XCTUnwrap(view.undoManager).canUndo)
            view.undoManager?.undo(); await session.save()
            XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), original)
            view.undoManager?.redo(); await session.save()
            XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), expected)
            owner.load(session.document.parts.body, source: false)
            if !fixture.body.isEmpty { XCTAssertTrue(view.text.contains(fixture.body), "Literal Markdown must remain text after reopening") }
            var remainingCodes = 0, tables = 0
            view.attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.attributedText.length)) { value, _, _ in
                if value is CodeAttachment { remainingCodes += 1 }; if value is TableAttachment { tables += 1 }
            }
            XCTAssertEqual(remainingCodes, 1); XCTAssertEqual(tables, 1)
        }
    }

    @MainActor
    func testCodeCreationPreferenceProtectsExistingBlocksAndControlsTypedAndPastedCodeWithoutChangingSavedProse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = "# Code preference\n\nBefore 😀.\n\n"
        let original = "---\nzerus-id: code-preference\nforeign: keep\n---\n" + prefix + "```swift\nlet x = 1\n```\n\nAfter."
        let path = root.appendingPathComponent("Code.md")
        try Data(original.utf8).write(to: path)
        let session = NoteSession(note: .init(path: "Code.md", content: original, modified: .now), root: root, io: VaultFiles(root: root), onSave: { _ in })
        defer { session.deactivate() }
        var request: CodeEditRequest?, issues: [String] = []
        let editor = NativeTextEditor(markdown: session.document.parts.body, source: false, onChange: session.updateBody,
            onImage: { _ in }, onLink: { _ in }, onCode: { request = $0 }, onClipboardError: { issues.append($0) }, documentID: "vault|Code.md")
        let coordinator = editor.makeCoordinator(), view = ZerusTextView(frame: .zero, textContainer: nil)
        coordinator.view = view; view.delegate = coordinator; coordinator.load(editor.markdown, source: false)
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene)), controller = UIViewController()
        window.rootViewController = controller; controller.view.addSubview(view); view.frame = CGRect(x: 0, y: 0, width: 390, height: 400)
        window.makeKeyAndVisible(); XCTAssertTrue(view.becomeFirstResponder())
        defer { view.resignFirstResponder(); window.isHidden = true; previous?.makeKeyAndVisible() }

        coordinator.insertCode()
        XCTAssertNil(request, "New creation is off by default")
        var existing: CodeAttachment?
        view.attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.attributedText.length)) { value, _, _ in
            if let code = value as? CodeAttachment { existing = code }
        }
        try XCTUnwrap(existing?.edit)()
        let edit = try XCTUnwrap(request); request = nil
        XCTAssertTrue(edit.save(edit.code.replacing(body: "let x = 2", info: "swift")), "Existing blocks remain editable when creation is off")
        await session.save()
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), original.replacingOccurrences(of: "let x = 1", with: "let x = 2"))

        // Exercise the committed-edit delegate boundary; the UI journey covers
        // keyboard delivery and native undo. Opening the sheet keeps the marker.
        func type(_ text: String) {
            if coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: text) { view.insertText(text); coordinator.textViewDidChange(view) }
        }
        coordinator.load(prefix, source: false); XCTAssertTrue(view.becomeFirstResponder())
        type("```swift"); type("\n")
        XCTAssertNil(request, "Off leaves a typed fence as ordinary writing")
        coordinator.parent.codeBlocksEnabled = true
        coordinator.load(prefix, source: false); type("```swift")
        XCTAssertEqual(view.text, "Code preference\n\nBefore 😀.\n\n```swift")
        XCTAssertEqual(view.selectedRange, NSRange(location: (view.text as NSString).length, length: 0))
        type("\n")
        let typed = try XCTUnwrap(request); request = nil
        XCTAssertEqual(typed.code.info, "swift"); XCTAssertEqual(typed.code.body, "")
        XCTAssertTrue(view.text.hasSuffix("```swift"), "Opening a code sheet does not save an empty block")
        XCTAssertTrue(typed.save(typed.code.replacing(body: "let plant = \"🪴\"", info: "swift")))
        await session.save()
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), "---\nzerus-id: code-preference\nforeign: keep\n---\n" + prefix + "```swift\nlet plant = \"🪴\"\n```\n\n")

        coordinator.load(prefix, source: false); XCTAssertTrue(view.becomeFirstResponder())
        coordinator.insertCode(); let pending = try XCTUnwrap(request); request = nil
        coordinator.parent.codeBlocksEnabled = false
        XCTAssertFalse(pending.save(pending.code.replacing(body: "late", info: "swift")))
        coordinator.parent.codeBlocksEnabled = true; coordinator.parent.documentID = "other-vault|Code.md"
        XCTAssertFalse(pending.save(pending.code.replacing(body: "late", info: "swift")), "A retained sheet cannot create code in another document")
        coordinator.parent.documentID = "vault|Code.md"
        coordinator.parent.readOnly = true; coordinator.insertCode(); XCTAssertNil(request)
        coordinator.parent.readOnly = false
        coordinator.load("```swift", source: true); type("\n"); XCTAssertNil(request, "Source typing is never intercepted")
        coordinator.load("# Heading\n\n", source: false); coordinator.block("> "); type("```swift"); type("\n"); XCTAssertNil(request, "Quoted and list paragraphs do not become top-level code")

        let payload = "```swift\nlet raw = \"**literal** [[not a link]]\";\n```"
        for enabled in [false, true] {
            coordinator.parent.codeBlocksEnabled = enabled; coordinator.load(prefix, source: false)
            let pasted = expectation(description: "Clipboard import completes")
            coordinator.parent.onClipboardBusy = { if !$0 { pasted.fulfill() } }
            coordinator.pasteFragment(try JSONEncoder().encode(NativeClipboardFragment(markdown: payload)))
            await fulfillment(of: [pasted], timeout: 5)
            XCTAssertTrue(issues.isEmpty, issues.joined(separator: ", "))
            await session.save()
            let saved = try String(contentsOf: path, encoding: .utf8)
            if enabled {
                XCTAssertEqual(saved, "---\nzerus-id: code-preference\nforeign: keep\n---\n" + prefix + payload + "\n\n")
                XCTAssertFalse(view.text.contains("```swift"))
            } else {
                XCTAssertEqual(saved, "---\nzerus-id: code-preference\nforeign: keep\n---\n" + prefix + "\\`\\`\\`swift\nlet raw = \"\\*\\*literal\\*\\* \\[\\[not a link\\]\\]\";\n\\`\\`\\`")
                XCTAssertTrue(view.text.hasSuffix(payload))
            }
        }
        // Code examples containing Markdown syntax must stay literal after a
        // later save/reopen when creation is disabled, too.
        let markdownExample = "```markdown\n# Literal heading\nA -- B and \"literal\" quotes.\n1. item\n- item\nA | B\n:--- | ---:\n---\n```"
        coordinator.parent.codeBlocksEnabled = false; coordinator.load(prefix, source: false)
        let literalPaste = expectation(description: "Literal Markdown code is pasted")
        coordinator.parent.onClipboardBusy = { if !$0 { literalPaste.fulfill() } }
        coordinator.pasteFragment(try JSONEncoder().encode(NativeClipboardFragment(markdown: markdownExample)))
        await fulfillment(of: [literalPaste], timeout: 5); await session.save()
        let literalFile = try String(contentsOf: path, encoding: .utf8)
        let literalBody = NoteDocument(path: "Code.md", content: literalFile, modified: .now).parts.body
        XCTAssertFalse(MarkdownText.requiresSource(literalBody), "Disabled code creation must not turn pasted Markdown examples into native block syntax on reopening")
        XCTAssertEqual(MarkdownText.render(literalBody).string, "Code preference\n\nBefore 😀.\n\n" + markdownExample)
        coordinator.parent.codeBlocksEnabled = false
        XCTAssertFalse(coordinator.pasteCode(payload))
        coordinator.parent.codeBlocksEnabled = true
        coordinator.load(prefix, source: false)
        let plain = expectation(description: "Plain fenced paste completes")
        coordinator.parent.onClipboardBusy = { if !$0 { plain.fulfill() } }
        XCTAssertTrue(coordinator.pasteCode(payload))
        await fulfillment(of: [plain], timeout: 5)
        await session.save()
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), "---\nzerus-id: code-preference\nforeign: keep\n---\n" + prefix + payload + "\n\n")
    }
}
