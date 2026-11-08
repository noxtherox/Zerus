import XCTest
@testable import ZerusNative

@MainActor
final class NativeHeadingNavigationTests: XCTestCase {
    func testLocalHeadingLinksRevealTheRightDuplicateWithoutWritingOrOpeningTheKeyboard() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NativeHeading-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let body = "# Heading navigation\n\n[Jump](#repeated-caf%C3%A9-1)\n\n## Repeated **café** ☕️\n\n" + String(repeating: "A paragraph to scroll past.\n\n", count: 35) + "```md\n## Repeated café ☕️\n```\n\n## Repeated **café** ☕️\n\nTarget paragraph.\n"
        let original = "---\nzerus-id: heading-owner\nforeign: keep\n---\n" + body
        try Data(original.utf8).write(to: root.appendingPathComponent("Note.md"))
        let io = VaultFiles(root: root), session = NoteSession(note: .init(path: "Note.md", content: original, modified: .now), root: root, io: io, onSave: { _ in })
        defer { session.deactivate() }
        let actions = NativeEditorActions(); var opened: [URL] = [], issues: [String] = []
        let editor = NativeTextEditor(markdown: body, source: false, onChange: session.updateBody, onImage: { _ in }, onLink: { opened.append($0) }, actions: actions, documentID: "heading-owner", onNoteLinkIssue: { issues.append($0) })
        let coordinator = editor.makeCoordinator(), view = ZerusTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 360), textContainer: nil)
        coordinator.view = view; view.delegate = coordinator; actions.coordinator = coordinator; coordinator.load(body, source: false)
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene)), controller = UIViewController(); window.rootViewController = controller
        controller.view.addSubview(view); window.makeKeyAndVisible(); view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        defer { window.isHidden = true; previous?.makeKey() }
        let expected = (view.attributedText.string as NSString).range(of: "Repeated café ☕️", options: .backwards)
        XCTAssertNotEqual(expected.location, NSNotFound)
        _ = coordinator.textView(view, shouldInteractWith: try XCTUnwrap(URL(string: "#repeated-caf%C3%A9-1")), in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction)
        view.layoutIfNeeded()
        XCTAssertEqual(view.selectedRange, expected); XCTAssertGreaterThan(view.contentOffset.y, 100)
        XCTAssertFalse(view.isFirstResponder); XCTAssertTrue(opened.isEmpty); XCTAssertTrue(issues.isEmpty)
        await session.save(); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Note.md")), Data(original.utf8))
        XCTAssertFalse(view.undoManager?.canUndo ?? false)
        let selected = view.selectedRange
        _ = coordinator.textView(view, shouldInteractWith: try XCTUnwrap(URL(string: "#missing-heading")), in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction)
        XCTAssertEqual(view.selectedRange, selected); XCTAssertEqual(issues.count, 1); XCTAssertTrue(opened.isEmpty)
        let sourceEditor = NativeTextEditor(markdown: body, source: true, onChange: session.updateBody, onImage: { _ in }, onLink: { opened.append($0) }, actions: actions, documentID: "heading-owner", onNoteLinkIssue: { issues.append($0) })
        coordinator.parent = sourceEditor; coordinator.load(body, source: true)
        _ = coordinator.textView(view, shouldInteractWith: try XCTUnwrap(URL(string: "#repeated-caf%C3%A9-1")), in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction)
        let sourceExpected = (body as NSString).range(of: "## Repeated **café** ☕️", options: .backwards)
        XCTAssertEqual(view.selectedRange, sourceExpected)
        let sourceStart = try XCTUnwrap(view.position(from: view.beginningOfDocument, offset: sourceExpected.location))
        let sourceEnd = try XCTUnwrap(view.position(from: sourceStart, offset: sourceExpected.length))
        let sourceSelection = try XCTUnwrap(view.textRange(from: sourceStart, to: sourceEnd))
        XCTAssertTrue(view.firstRect(for: sourceSelection).intersects(view.bounds.inset(by: view.adjustedContentInset)))
        _ = coordinator.textView(view, shouldInteractWith: try XCTUnwrap(URL(string: "#Repeated%20caf%C3%A9%20%E2%98%95%EF%B8%8F")), in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction)
        XCTAssertEqual(view.selectedRange, (body as NSString).range(of: "## Repeated **café** ☕️"))
        _ = coordinator.textView(view, shouldInteractWith: try XCTUnwrap(URL(string: "#")), in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction)
        XCTAssertEqual(view.selectedRange, NSRange(location: 0, length: 0)); XCTAssertFalse(view.isFirstResponder)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Note.md")), Data(original.utf8))
        let setext = "😀 preface\r\n\r\nSetext **café**\r\n===============\r\n\r\n## [[zerus:another|Visible alias]]\r\n"
        coordinator.load(setext, source: true)
        _ = coordinator.textView(view, shouldInteractWith: try XCTUnwrap(URL(string: "#setext-caf%C3%A9")), in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction)
        XCTAssertEqual((setext as NSString).substring(with: view.selectedRange), "Setext **café**\r\n===============")
        _ = coordinator.textView(view, shouldInteractWith: try XCTUnwrap(URL(string: "#visible-alias")), in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction)
        XCTAssertEqual((setext as NSString).substring(with: view.selectedRange), "## [[zerus:another|Visible alias]]")
        XCTAssertEqual(issues.count, 1)
        session.updateBody(setext); await session.save()
        view.selectedRange = NSRange(location: view.attributedText.length, length: 0)
        XCTAssertTrue(view.becomeFirstResponder()); view.insertText("Typed before navigating."); coordinator.textViewDidChange(view)
        actions.finishEditing(); XCTAssertTrue(view.undoManager?.canUndo == true)
        actions.revealHeading("setext-café")
        XCTAssertTrue(view.undoManager?.canUndo == true); XCTAssertFalse(view.isFirstResponder)
        view.undoManager?.undo(); coordinator.textViewDidChange(view); await session.save()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Note.md"), encoding: .utf8), "---\nzerus-id: heading-owner\nforeign: keep\n---\n" + setext)
    }
}
