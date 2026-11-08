import XCTest
import SwiftUI
@testable import ZerusNative

@MainActor
final class NativeReadingPositionTests: XCTestCase {
    func testRealTextKitRestoresReadingPositionAndSelectionWithoutEditingAndRejectsChangedBodyOrMode() async throws {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene)); window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let body = "# Resume\n\n" + String(repeating: "Before the saved reading position.\n\n", count: 35) + "## Reading anchor\n\nKeep the reading cursor.\n\n" + String(repeating: "Following context keeps the anchor visible.\n\n", count: 15)
        var edits: [String] = [], positions: [NativeReadingPosition] = []
        func mount(_ text: String, source: Bool, position: NativeReadingPosition? = nil) async throws -> NativeEditorActions {
            let actions = NativeEditorActions()
            let editor = NativeTextEditor(markdown: text, source: source, onChange: { edits.append($0) }, onImage: { _ in }, onLink: { _ in }, actions: actions, documentID: UUID().uuidString,
                                          initialPosition: position, allowsInitialFocus: false, onPosition: { positions.append($0) })
            window.rootViewController = UIHostingController(rootView: editor.frame(width: 390, height: 360)); window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertNotNil(actions.coordinator?.view); return actions
        }
        for source in [false, true] {
            let first = try await mount(body, source: source), view = try XCTUnwrap(first.coordinator?.view)
            first.revealHeading("reading-anchor"); try await Task.sleep(for: .milliseconds(100)); first.finishEditing()
            let saved = try XCTUnwrap(positions.last), selected = view.selectedRange, offset = view.contentOffset.y
            XCTAssertGreaterThan(offset, 100); XCTAssertEqual(saved.source, source)
            let beforeStart = try XCTUnwrap(view.position(from: view.beginningOfDocument, offset: selected.location))
            let beforeCaret = try XCTUnwrap(view.textRange(from: beforeStart, to: beforeStart))
            let beforeY = view.convert(view.firstRect(for: beforeCaret), from: view.textInputView).minY - view.bounds.minY
            let restored = try await mount(body, source: source, position: saved), fresh = try XCTUnwrap(restored.coordinator?.view)
            XCTAssertEqual(fresh.selectedRange, selected)
            let start = try XCTUnwrap(fresh.position(from: fresh.beginningOfDocument, offset: selected.location))
            let caret = try XCTUnwrap(fresh.textRange(from: start, to: start))
            let restoredRect = fresh.convert(fresh.firstRect(for: caret), from: fresh.textInputView)
            XCTAssertTrue(restoredRect.intersects(fresh.bounds))
            XCTAssertEqual(restoredRect.minY - fresh.bounds.minY, beforeY, accuracy: 3, "The same text should retain its visible position even when TextKit adjusts global layout estimates")
            XCTAssertFalse(fresh.isFirstResponder); XCTAssertFalse(fresh.undoManager?.canUndo ?? false)
            for (text, mode) in [(body + "Outside edit.\n", source), (body, !source)] {
                let ignored = try await mount(text, source: mode, position: saved), guarded = try XCTUnwrap(ignored.coordinator?.view)
                XCTAssertEqual(guarded.selectedRange, NSRange(location: guarded.attributedText.length, length: 0), "A position for different content or editor mode must not supply a selection")
                XCTAssertFalse(guarded.isFirstResponder)
            }
        }
        XCTAssertTrue(edits.isEmpty, "Restoring UI state must not call the document editing path")
    }
}
