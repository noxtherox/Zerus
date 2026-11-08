import XCTest
import SwiftUI
import UIKit
@testable import ZerusNative

final class NativeNoteFindTests: XCTestCase {
    @MainActor
    func testRealEditorFindsFullBlocksAndUnicodeRevealsWithoutWritingPreservesUndoAndRefusesStaleResults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let code = (1...13).map { "let line\($0) = \($0)" }.joined(separator: "\r\n") + "\r\nlet deep = \"café\""
        let rows = (1...6).map { "| Row \($0) | \($0 == 6 ? "café" : "ordinary") |" }.joined(separator: "\r\n")
        let source = "---\r\nzerus-id: find-owner\r\nforeign: preserve\r\n---\r\n# Find 🧭\r\n\r\n**CAFÉ** and cafe in prose.\r\n\r\n- [ ] Keep this\r\n\r\n```swift\r\n" + code + "\r\n```\r\n\r\n| Name | Value |\r\n| --- | --- |\r\n" + rows + "\r\n\r\n" + Array(repeating: "Writing stays unchanged.", count: 60).joined(separator: "\r\n\r\n") + "\r\n\r\nFar NEEDLE 🧭 stays here.\r\n"
        let file = root.appendingPathComponent("Find.md"); try Data(source.utf8).write(to: file)
        let session = NoteSession(note: .init(path: "Find.md", content: source, modified: .now), root: root, io: VaultFiles(root: root), onSave: { _ in })
        defer { session.deactivate() }
        let actions = NativeEditorActions()
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        let host = UIHostingController(rootView: FindWritingFixture(session: session, actions: actions))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        await settle { actions.coordinator?.view?.window != nil }
        let view = try XCTUnwrap(actions.coordinator?.view); view.layoutIfNeeded()
        let toggle = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Complete: Keep this" })
        toggle.sendActions(for: .touchUpInside); await session.save()
        let checked = source.replacingOccurrences(of: "- [ ] Keep this", with: "- [x] Keep this")
        XCTAssertEqual(try Data(contentsOf: file), Data(checked.utf8)); XCTAssertTrue(try XCTUnwrap(view.undoManager).canUndo)
        actions.finishEditing()
        let originalSelection = view.selectedRange, visible = view.attributedText.string
        let snapshot = try XCTUnwrap(actions.findSnapshot())
        XCTAssertTrue(snapshot.matches("").isEmpty); XCTAssertTrue(snapshot.matches("missing token").isEmpty)
        let cafes = snapshot.matches("cafe")
        XCTAssertEqual(cafes.count, 4); XCTAssertEqual(cafes.map(\.matched), ["CAFÉ", "cafe", "café", "café"])
        XCTAssertEqual(snapshot.matches("CAFÉ", matchCase: true).count, 1)
        XCTAssertTrue(cafes[2].label.contains("code")); XCTAssertEqual(cafes[3].label, "Table · row 6, column 2")
        XCTAssertEqual(view.selectedRange, originalSelection, "Querying alone must not move the caret")
        XCTAssertTrue(snapshot.reveal(cafes[0])); XCTAssertEqual((view.attributedText.string as NSString).substring(with: view.selectedRange), "CAFÉ")
        XCTAssertTrue(snapshot.reveal(cafes[2])); XCTAssertTrue(view.attributedText.attribute(.attachment, at: view.selectedRange.location, effectiveRange: nil) is CodeAttachment)
        XCTAssertTrue(snapshot.reveal(cafes[3])); XCTAssertTrue(view.attributedText.attribute(.attachment, at: view.selectedRange.location, effectiveRange: nil) is TableAttachment)
        let far = try XCTUnwrap(snapshot.matches("NEEDLE 🧭").first)
        XCTAssertTrue(snapshot.reveal(far)); XCTAssertEqual((view.attributedText.string as NSString).substring(with: view.selectedRange), "NEEDLE 🧭")
        XCTAssertGreaterThan(view.contentOffset.y, 300, "A distant result must actually be brought into the viewport")
        XCTAssertEqual(view.attributedText.string, visible); XCTAssertFalse(view.isFirstResponder); XCTAssertFalse(session.dirty)
        XCTAssertEqual(try Data(contentsOf: file), Data(checked.utf8)); XCTAssertTrue(try XCTUnwrap(view.undoManager).canUndo)
        view.undoManager?.undo(); await session.save(); XCTAssertEqual(try Data(contentsOf: file), Data(source.utf8))
        XCTAssertFalse(snapshot.reveal(far), "A result from before Undo must not select the changed document")
        view.undoManager?.redo(); await session.save(); XCTAssertEqual(try Data(contentsOf: file), Data(checked.utf8))
        host.rootView = FindWritingFixture(session: session, actions: actions, source: true)
        await settle { actions.coordinator?.source == true }
        XCTAssertFalse(snapshot.reveal(far), "A rich result must not select source offsets")
        let literal = try XCTUnwrap(actions.findSnapshot()), fences = literal.matches("```swift")
        XCTAssertEqual(fences.count, 1); XCTAssertTrue(literal.reveal(try XCTUnwrap(fences.first)))
        XCTAssertEqual((view.attributedText.string as NSString).substring(with: view.selectedRange), "```swift")
        host.rootView = FindWritingFixture(session: session, actions: actions, source: true, document: "other")
        await settle { actions.coordinator?.parent.documentID == "other" }
        XCTAssertFalse(literal.reveal(try XCTUnwrap(fences.first)), "Identical text in a different document must not accept the old result")
        let current = try XCTUnwrap(actions.findSnapshot()), currentMatch = try XCTUnwrap(current.matches("NEEDLE").first)
        view.setMarkedText("composing", selectedRange: NSRange(location: 0, length: 0))
        XCTAssertNotNil(view.markedTextRange); XCTAssertNil(actions.findSnapshot()); XCTAssertFalse(current.reveal(currentMatch))
    }
    @MainActor private func settle(_ predicate: () -> Bool) async {
        let end = ContinuousClock.now + .seconds(5)
        while !predicate(), ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(predicate())
    }
}
private struct FindWritingFixture: View {
    @ObservedObject var session: NoteSession
    let actions: NativeEditorActions
    var source = false
    var document = "find-owner"
    var body: some View {
        NativeTextEditor(markdown: session.document.parts.body, source: source, onChange: session.updateBody, onImage: { _ in }, onLink: { _ in }, actions: actions, documentID: document, allowsInitialFocus: false)
    }
}
