import XCTest
import SwiftUI
import UIKit
@testable import ZerusNative

final class NativeEditorClipboardConcurrencyTests: XCTestCase {
    @MainActor
    func testBecomingReadOnlyWhileAProjectProviderIsReadingCannotApplyTheDelayedPasteOrRewriteTheFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("figures"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Writing.md"), image = root.appendingPathComponent("figures/chart.png")
        let original = "---\nzerus-id: readonly-paste\nforeign: keep\n---\n# Writing\n\nBefore the delayed paste.\n"
        let bytes = Data("Original project image bytes".utf8); try bytes.write(to: image); try Data(original.utf8).write(to: file)
        let session = NoteSession(note: .init(path: "Writing.md", content: original, modified: .now), root: root, io: VaultFiles(root: root), onSave: { _ in })
        defer { session.deactivate() }
        let project = try NativeExternalProjectFiles(selectedProject: root, source: file), locked = ClipboardEditorLock(), actions = NativeEditorActions()
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        let finished = expectation(description: "The clipboard request completes or is cancelled")
        let host = UIHostingController(rootView: ClipboardWritingView(session: session, locked: locked, receive: { try await project.importFragment($0) }, actions: actions, busy: { if !$0 { finished.fulfill() } }))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        await waitUntil { actions.coordinator?.view?.window != nil }
        let view = try XCTUnwrap(actions.coordinator?.view); XCTAssertTrue(view.becomeFirstResponder())
        let before = view.text, selection = view.selectedRange
        let gate = ClipboardProjectReaderGate(url: image)
        NSFileCoordinator.addFilePresenter(gate)
        defer { gate.release(); NSFileCoordinator.removeFilePresenter(gate) }
        let fragment = NativeClipboardFragment(markdown: "![Chart](figures/chart.png)", vault: NativeClipboardFragment.vaultID(root), resources: [.init(reference: "figures/chart.png", path: "figures/chart.png", name: "chart.png", bytes: bytes)])
        actions.coordinator?.pasteFragment(try JSONEncoder().encode(fragment))
        await fulfillment(of: [gate.requested], timeout: 5)
        locked.value = true
        await waitUntil { !view.isEditable }
        XCTAssertFalse(view.isEditable, "The hosted editor must receive its actual read-only transition before the provider finishes")
        gate.release()
        await fulfillment(of: [finished, gate.readFinished], timeout: 5)
        await session.save()
        XCTAssertEqual(view.text, before, "A delayed clipboard completion cannot insert into the now read-only editor")
        XCTAssertEqual(view.selectedRange, selection)
        XCTAssertEqual(try Data(contentsOf: file), Data(original.utf8), "Read-only presentation must also prevent the delayed paste from rewriting its actual Markdown file")
        XCTAssertEqual(try Data(contentsOf: image), bytes)
    }
    @MainActor
    func testHTMLOnlyPasteKeepsFormattedBlocksAndImageBytesThroughNativeUndoAndActualNoteSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Writing.md")
        let original = "---\nzerus-id: html-clipboard\nForeign: keep # unchanged\n---\n# Writing\n\nKeep this independent paragraph.\n"
        try Data(original.utf8).write(to: file)
        let io = VaultFiles(root: root)
        let session = NoteSession(note: .init(path: "Writing.md", content: original, modified: .now), root: root, io: io, onSave: { _ in })
        defer { session.deactivate() }
        let board = UIPasteboard.general; board.items = []; defer { board.items = [] }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 3)).image { context in UIColor.systemPurple.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3, height: 3)) }
        let png = try XCTUnwrap(image.pngData())
        let imageAlt = String(repeating: "é", count: 120) + " *chart* <new> [detail] & caption"
        let html = """
        <html><head><style>p { font-weight: bold }</style></head><body>
        <h2>Pasted <em>heading</em></h2>
        <p>Nested <strong>outer <em>inner</em> tail</strong> text.</p>
        <p>Unspaced <b>one</b><em>two</em><s>three</s> ending.</p>
        <div hidden>Hidden writing<img src="https://native-html-hidden.invalid/image.png"></div>
        <script>Never execute this.</script>
        <p>A <strong>bold</strong> thought &amp; <a href="https://example.com/a?q=x&amp;y=2">link</a>.</p>
        <ol start="3"><li>Third<ul><li>Nested <s>old</s></li></ul></li><li>Fourth</li></ol>
        <blockquote><p>Quoted words.</p></blockquote>
        <table><caption>Table caption</caption><tr><th>Item</th><th>Value</th></tr><tr><td><strong>First</strong></td><td><code>a | b</code></td></tr></table>
        <pre><code class="language-swift">let html = &quot;&lt;literal&gt;&quot;\n</code></pre>
        <p><img alt="Provided original &lt;new&gt; *chart* :?&quot;|" src="file:///private/clipboard/Original.png"></p>
        <p><img alt="\(imageAlt)" src="data:image/png;base64,\(png.base64EncodedString())"></p>
        <p>Literal **stars** and [brackets].</p>
        </body></html>
        """
        let actions = NativeEditorActions(), locked = ClipboardEditorLock()
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        var busy = false, issues: [String] = []
        let host = UIHostingController(rootView: ClipboardWritingView(session: session, locked: locked, receive: { try await io.importClipboard($0) }, actions: actions, busy: { busy = $0 }, issue: { issues.append($0) }, codeBlocks: true))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        await waitUntil { actions.coordinator?.view?.window != nil }
        let view = try XCTUnwrap(actions.coordinator?.view)
        XCTAssertTrue(view.becomeFirstResponder()); view.selectedRange = NSRange(location: view.attributedText.length, length: 0)
        let attachment = NSTextAttachment(data: png, ofType: "public.png")
        attachment.image = image; attachment.fileWrapper = FileWrapper(regularFileWithContents: png); attachment.fileWrapper?.preferredFilename = "Original.png"
        let rtfd = try NSAttributedString(attachment: attachment).data(from: NSRange(location: 0, length: 1), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        board.items = [["public.html": Data(html.utf8), "com.apple.flat-rtfd": rtfd, "public.utf8-plain-text": "Pasted heading\nA bold thought & link."]]
        actions.paste()
        await waitUntil { !busy && (view.text.contains("Pasted heading") || !issues.isEmpty) }
        await session.save()
        let saved = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
        XCTAssertTrue(saved.contains("## Pasted"), "HTML-only clipboard formatting must reach the real note, rather than falling back to its plain representation: " + saved)
        guard saved.contains("## Pasted") else { return }
        XCTAssertTrue(saved.hasPrefix("---\nzerus-id: html-clipboard\nForeign: keep # unchanged\n---\n# Writing\n\nKeep this independent paragraph."))
        XCTAssertTrue(saved.contains("**bold**")); XCTAssertTrue(saved.contains("[link](https://example.com/a?q=x&y=2)"))
        XCTAssertTrue(saved.contains("3. Third")); XCTAssertTrue(saved.contains("  - Nested ~~old~~")); XCTAssertTrue(saved.contains("4. Fourth"))
        XCTAssertTrue(saved.contains("> Quoted words.")); XCTAssertTrue(saved.contains("| **First** | `a \\| b` |"), saved)
        XCTAssertTrue(saved.contains("```swift\nlet html = \"<literal>\"\n```"), saved)
        XCTAssertTrue(saved.contains("Literal \\*\\*stars\\*\\* and \\[brackets\\]."), saved)
        XCTAssertTrue(saved.contains("Table caption")); XCTAssertFalse(saved.contains("Hidden writing")); XCTAssertFalse(saved.contains("Never execute"))
        XCTAssertTrue(saved.contains("\\*chart\\*"), "An HTML image alt label is literal text, including its Markdown punctuation")
        XCTAssertFalse(saved.contains("data:image")); XCTAssertFalse(saved.contains("\u{fffc}"))
        let imagePaths = MarkdownResources.localReferences(in: saved)
        XCTAssertEqual(imagePaths.count, 2)
        for path in imagePaths {
            let decoded = path.removingPercentEncoding ?? path
            XCTAssertLessThanOrEqual((decoded as NSString).lastPathComponent.decomposedStringWithCanonicalMapping.utf8.count, 255)
            XCTAssertNil((decoded as NSString).lastPathComponent.range(of: #"[<>:\"/\\|?*]"#, options: .regularExpression))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(decoded)), png)
        }
        view.undoManager?.undo(); await session.save()
        XCTAssertEqual(try Data(contentsOf: file), Data(original.utf8), "One native Undo must restore the entire original note")
        view.undoManager?.redo(); await session.save()
        XCTAssertEqual(try Data(contentsOf: file), Data(saved.utf8))
        let restored = try String(contentsOf: file, encoding: .utf8)
        let reopened = NoteSession(note: .init(path: "Writing.md", content: restored, modified: .now), root: root, io: io, onSave: { _ in })
        defer { reopened.deactivate() }
        let reopenedActions = NativeEditorActions()
        window.rootViewController = UIHostingController(rootView: ClipboardWritingView(session: reopened, locked: locked, receive: { try await io.importClipboard($0) }, actions: reopenedActions, busy: { _ in }, codeBlocks: true))
        await waitUntil { reopenedActions.coordinator?.view?.window != nil }
        let reopenedText = try XCTUnwrap(reopenedActions.coordinator?.view?.attributedText)
        XCTAssertTrue(reopenedText.string.contains("Unspaced onetwothree ending."), reopenedText.string)
        XCTAssertTrue(reopenedText.string.contains("Nested outer inner tail text."), reopenedText.string)
        for (word, trait) in [("one", UIFontDescriptor.SymbolicTraits.traitBold), ("two", .traitItalic), ("outer", .traitBold), ("inner", [.traitBold, .traitItalic]), ("tail", .traitBold)] {
            let range = (reopenedText.string as NSString).range(of: word)
            XCTAssertNotEqual(range.location, NSNotFound)
            if range.location != NSNotFound { XCTAssertTrue((reopenedText.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont)?.fontDescriptor.symbolicTraits.contains(trait) == true, "Preserve adjacent HTML formatting after actual-file reopening: " + word) }
        }
        let struck = (reopenedText.string as NSString).range(of: "three")
        XCTAssertNotEqual(struck.location, NSNotFound)
        if struck.location != NSNotFound { XCTAssertNotNil(reopenedText.attribute(.strikethroughStyle, at: struck.location, effectiveRange: nil)) }
        for path in imagePaths {
            let decoded = path.removingPercentEncoding ?? path
            XCTAssertLessThanOrEqual((decoded as NSString).lastPathComponent.decomposedStringWithCanonicalMapping.utf8.count, 255)
            XCTAssertNil((decoded as NSString).lastPathComponent.range(of: #"[<>:\"/\\|?*]"#, options: .regularExpression))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(decoded)), png)
        }
    }
    @MainActor
    func testFreshlyTypedBoldParagraphCopiesPastesAndReopensWithoutLiteralDelimiters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Writing.md")
        let original = "---\nzerus-id: typed-clipboard\nforeign: keep\n---\n# Writing\n\n"
        try Data(original.utf8).write(to: file)
        let io = VaultFiles(root: root), actions = NativeEditorActions(), locked = ClipboardEditorLock()
        let session = NoteSession(note: .init(path: "Writing.md", content: original, modified: .now), root: root, io: io, onSave: { _ in })
        defer { session.deactivate() }
        let board = UIPasteboard.general; board.items = []
        defer { board.items = [] }
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        var busy = false, issues: [String] = []
        window.rootViewController = UIHostingController(rootView: ClipboardWritingView(session: session, locked: locked, receive: { try await io.importClipboard($0) }, actions: actions, busy: { busy = $0 }, issue: { issues.append($0) }))
        window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        await waitUntil { actions.coordinator?.view?.window != nil }
        let coordinator = try XCTUnwrap(actions.coordinator), view = try XCTUnwrap(coordinator.view)
        XCTAssertTrue(view.becomeFirstResponder()); view.selectedRange = NSRange(location: view.attributedText.length, length: 0)
        let start = view.selectedRange.location, sentence = "Native clipboard keeps bold words."
        view.insertText("N"); coordinator.textViewDidChange(view)
        view.insertText(String(sentence.dropFirst())); coordinator.textViewDidChange(view)
        view.selectedRange = NSRange(location: start, length: (sentence as NSString).length)
        coordinator.bold(); await session.save()
        let formatted = original + "**" + sentence + "**"
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), formatted, "Formatting freshly typed text must not introduce literal delimiters at UIKit run boundaries")
        view.selectedRange = NSRange(location: start, length: (sentence as NSString).length)
        view.copy(nil)
        await waitUntil { NativeClipboard.pendingCopy == nil }
        let payload = try NativeClipboardFragment.decode(try XCTUnwrap(board.data(forPasteboardType: NativeClipboardFragment.type)))
        XCTAssertEqual(payload.markdown, "**" + sentence + "**")
        view.selectedRange = NSRange(location: view.attributedText.length, length: 0)
        view.insertText("\n\n"); coordinator.textViewDidChange(view)
        let beforePaste = session.document.parts.body
        actions.paste()
        await waitUntil { !busy && view.text.components(separatedBy: sentence).count == 3 }
        await session.save()
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
        let saved = formatted + "\n\n**" + sentence + "**"
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), saved)
        view.undoManager?.undo(); await session.save()
        XCTAssertEqual(session.document.parts.body, beforePaste)
        view.undoManager?.redo(); await session.save()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), saved)
        let reopened = NoteSession(note: .init(path: "Writing.md", content: try String(contentsOf: file, encoding: .utf8), modified: .now), root: root, io: io, onSave: { _ in })
        defer { reopened.deactivate() }
        let reopenedActions = NativeEditorActions()
        window.rootViewController = UIHostingController(rootView: ClipboardWritingView(session: reopened, locked: locked, receive: { try await io.importClipboard($0) }, actions: reopenedActions, busy: { _ in }))
        await waitUntil { reopenedActions.coordinator?.view?.window != nil }
        let rich = try XCTUnwrap(reopenedActions.coordinator?.view?.attributedText)
        XCTAssertEqual(rich.string, "Writing\n\n" + sentence + "\n\n" + sentence)
        let range = (rich.string as NSString).range(of: sentence, options: .backwards)
        if range.location != NSNotFound {
            rich.enumerateAttribute(.font, in: range) { font, _, _ in
                XCTAssertTrue((font as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
            }
        }
    }
    @MainActor private func waitUntil(_ check: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !check(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }
}

@MainActor private final class ClipboardEditorLock: ObservableObject { @Published var value = false }
private struct ClipboardWritingView: View {
    @ObservedObject var session: NoteSession
    @ObservedObject var locked: ClipboardEditorLock
    let receive: (NativeClipboardFragment) async throws -> String
    let actions: NativeEditorActions
    let busy: (Bool) -> Void
    var issue: (String) -> Void = { _ in }
    var codeBlocks = false
    var body: some View {
        NativeTextEditor(markdown: session.document.parts.body, source: false, onChange: session.updateBody,
                         onImage: { _ in }, onLink: { _ in }, pasteFragment: receive, onClipboardError: issue,
                         onClipboardBusy: busy, actions: actions, documentID: "readonly-project-writing", readOnly: locked.value, codeBlocksEnabled: codeBlocks)
    }
}
private final class ClipboardProjectReaderGate: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    let requested = XCTestExpectation(description: "The project provider holds the clipboard resource read")
    let readFinished = XCTestExpectation(description: "The project read actually finishes")
    private let lock = NSLock()
    private var used = false
    private let semaphore = DispatchSemaphore(value: 0)
    init(url: URL) { presentedItemURL = url; super.init(); presentedItemOperationQueue.maxConcurrentOperationCount = 1 }
    func relinquishPresentedItem(toReader reader: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        let first = lock.withLock { if used { return false }; used = true; return true }
        if first { requested.fulfill(); _ = semaphore.wait(timeout: .now() + 10) }
        reader { [self] in if first { readFinished.fulfill() } }
    }
    func release() { semaphore.signal() }
}
