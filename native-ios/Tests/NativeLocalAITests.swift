import XCTest
import ZerusLocalAICore
@testable import ZerusNative

final class NativeLocalAITests: XCTestCase {
    @MainActor
    func testEditorBridgeReadsSelectionAppliesOneUndoableEditAndRejectsStaleReplacements() async throws {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene)), controller = UIViewController()
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "---\nzerus-id: ai\ntags: [travel]\n---\n# Plan\n\nBook the train to Porto.\n\n- [ ] Pack the bags\n"
        try Data(original.utf8).write(to: root.appendingPathComponent("Plan.md"))
        let session = NoteSession(note: .init(path: "Plan.md", content: original, modified: .now), root: root, io: VaultFiles(root: root), onSave: { _ in })
        defer { session.deactivate() }
        let actions = NativeEditorActions()
        let editor = NativeTextEditor(markdown: session.document.parts.body, source: false, onChange: session.updateBody,
                                      onImage: { _ in }, onLink: { _ in }, actions: actions, documentID: "vault|Plan.md")
        let owner = editor.makeCoordinator(), view = ZerusTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 400), textContainer: nil)
        controller.view.addSubview(view); defer { view.resignFirstResponder(); view.removeFromSuperview() }
        owner.view = view; view.delegate = owner; actions.coordinator = owner; owner.load(editor.markdown, source: false)
        XCTAssertTrue(view.becomeFirstResponder())

        view.selectedRange = (view.attributedText.string as NSString).range(of: "train to Porto")
        let snapshot = try XCTUnwrap(actions.localAISnapshot())
        XCTAssertEqual(snapshot.selection, "train to Porto")
        XCTAssertTrue(snapshot.markdown.contains("Book the train to Porto."))
        let request = try NativeLocalAIRequest.make(.rewrite, session: session, editor: actions)
        XCTAssertEqual(request.selection, "train to Porto")
        XCTAssertEqual(request.content, original)

        let replacement = snapshot.markdown.replacingOccurrences(of: "train to Porto", with: "flight to Madeira")
        try actions.applyLocalAI(expected: snapshot.markdown, replacement: replacement)
        XCTAssertTrue(session.document.content.contains("Book the flight to Madeira."))
        XCTAssertTrue(session.document.content.hasPrefix("---\nzerus-id: ai\ntags: [travel]\n---\n"), "frontmatter is kept")
        XCTAssertTrue(session.document.content.contains("- [ ] Pack the bags"))
        XCTAssertThrowsError(try actions.applyLocalAI(expected: snapshot.markdown, replacement: replacement), "a stale review is refused")

        view.undoManager?.undo()
        XCTAssertTrue(session.document.content.contains("Book the train to Porto."), "one undo step reverts the AI edit")
    }

    @MainActor
    func testPropertyOperationsUseDefinitionsAndBodiesDropRepeatedTitles() throws {
        let content = "---\nzerus-id: x\ntags: [travel]\nstatus: open\ndone: false\n---\n# Porto\n\nBody\n"
        XCTAssertEqual(LocalAIActions.properties(content), ["tags": .list(["travel"]), "status": .text("open"), "done": .text("false")])
        let ops = [LocalAIPropertyOperation(kind: .set, key: "tags", values: ["travel", "porto"]),
                   LocalAIPropertyOperation(kind: .remove, key: "status", values: []),
                   LocalAIPropertyOperation(kind: .set, key: "done", values: ["true"])]
        let definitions = [NativePropertyDefinition(name: "done", type: .checkbox)]
        let updated = try LocalAIActions.applying(ops, to: content, definitions: definitions)
        XCTAssertTrue(updated.contains("zerus-id: x"))
        XCTAssertFalse(updated.contains("status:"))
        XCTAssertEqual(NativeFrontmatter(updated).entries.first { $0.key == "done" }?.value, .checkbox(true))
        XCTAssertEqual(LocalAIActions.properties(updated)["tags"], .list(["travel", "porto"]))
        XCTAssertTrue(updated.hasSuffix("# Porto\n\nBody\n"))
        XCTAssertEqual(LocalAIActions.bodyWithoutTitle("# Packing list\n\n- Passport", title: "packing list"), "- Passport")
        XCTAssertEqual(LocalAIActions.bodyWithoutTitle("- Passport", title: "Packing list"), "- Passport")
        XCTAssertThrowsError(try LocalAIActions.validateRewrite(selection: "the", in: "the cat and the dog"))
        XCTAssertThrowsError(try LocalAIActions.validateRewrite(selection: nil, in: "x"))
    }

    func testDiffShowsChangedLinesWithContext() {
        let lines = NativeLocalAIDiffView.lines(before: "a\nb\nc\nd\ne\nf", after: "a\nb\nc\nD\ne\nf")
        XCTAssertEqual(lines.map(\.kind), [0, 0, -1, 1, 0, 0])
        XCTAssertEqual(lines.map(\.text), ["b", "c", "d", "D", "e", "f"])
    }
}
