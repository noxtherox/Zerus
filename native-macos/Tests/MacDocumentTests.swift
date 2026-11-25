import XCTest
import AppKit
import Markdown
import SwiftUI
@testable import Zerus_Native

/// User-visible file contracts: rendering cannot normalize unedited Markdown,
/// and a native save cannot overwrite another editor's changes.
final class MacDocumentTests: XCTestCase {
    @MainActor func testCodeBlockCanBecomeLiteralTextWithoutLosingContainersOrUndo() throws {
        let cases: [(String, String)] = [
            ("Before\n\n```swift\n# literal\nsecond *line*\n```\n\nAfter\n", "Before\n\n\\# literal<br>second \\*line\\*\n\nAfter\n"),
            ("> ```\n> First\n> Second\n> ```\n> \n> After\n", "> First<br>Second\n> \n> After\n"),
            ("- Parent\n  ```\n  First\n  Second\n  ```\n  - Child\n- Sibling\n", "- Parent\n\n  First<br>Second\n  - Child\n- Sibling\n"),
            ("Before\n\n    First\n    Second\n\nAfter\n", "Before\n\nFirst<br>Second\n\nAfter\n"),
            ("```\nFirst\n\nLast\n\n```\n", "First<br><br>Last<br>\n"),
            ("```\n```\n", "\n"),
            ("- ```\n  First\n  ```\n- Sibling\n", "- First\n- Sibling\n"),
            ("- ```\n  [x] literal\n  ```\n- Sibling\n", "- \\[x\\] literal\n- Sibling\n"),
            ("- Parent\n  > ```\n  > First\n  > ```\n- Sibling\n", "- Parent\n\n  > First\n- Sibling\n")
        ]
        func parents(_ markdown: String) -> [Int?] {
            var result: [Int?] = []
            func walk(_ node: any Markup, parent: Int? = nil) {
                var owner = parent
                if node is ListItem { owner = result.count; result.append(parent) }
                for child in node.children { walk(child, parent: owner) }
            }
            walk(Document(parsing: markdown)); return result
        }
        for (input, output) in cases { for ending in ["\n", "\r\n"] {
            let original = input.replacingOccurrences(of: "\n", with: ending), expected = output.replacingOccurrences(of: "\n", with: ending)
            try withEditor(original) { view, coordinator in
                let caret = (view.string as NSString).range(of: input.contains("# literal") ? "# literal" : input.contains("First") ? "First" : input.contains("[x] literal") ? "[x] literal" : "\u{200b}")
                XCTAssertNotEqual(caret.location, NSNotFound)
                view.setSelectedRange(NSRange(location: caret.location, length: 0))
                let originalSelection = view.selectedRange()
                let beforeParents = parents(original)
                coordinator.action("codeToText")
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(MacCodeBlock.blocks(in: coordinator.lastMarkdown).count, 0)
                XCTAssertEqual(parents(coordinator.lastMarkdown), beforeParents)
                XCTAssertNil(view.attributedString().attribute(.macCode, at: view.selectedRange().location, effectiveRange: nil))
                XCTAssertFalse(coordinator.source)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original); XCTAssertEqual(view.selectedRange(), originalSelection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original); XCTAssertEqual(view.selectedRange(), originalSelection)
            }
        } }
        let original = cases[0].0
        try withEditor(original) { view, coordinator in
            let prose = (view.string as NSString).range(of: "Before")
            view.setSelectedRange(prose); view.insertText("Kept", replacementRange: prose)
            let edited = original.replacingOccurrences(of: "Before", with: "Kept")
            let code = (view.string as NSString).range(of: "# literal")
            view.setSelectedRange(NSRange(location: code.location, length: 0)); coordinator.action("codeToText")
            XCTAssertEqual(coordinator.lastMarkdown, cases[0].1.replacingOccurrences(of: "Before", with: "Kept"))
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, edited)
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
        }
    }
    @MainActor func testFindInNoteShowsNativeBarWithoutChangingContentOrSelection() throws {
        for sourceMode in [false, true] {
            let text = "Alpha needle, then another needle.\n"
            let editor = MacRichEditor(markdown: text, source: sourceMode, editable: true, onChange: { _ in }, onLink: { _ in })
            try withHostedEditor(editor) { view, coordinator, host in
                let scroll = try XCTUnwrap(view.enclosingScrollView)
                let selection = (view.string as NSString).range(of: "Alpha")
                view.setSelectedRange(selection)
                let before = view.attributedString(), undoable = view.undoManager?.canUndo
                XCTAssertFalse(scroll.isFindBarVisible)
                coordinator.action("find")
                host.layoutSubtreeIfNeeded()
                XCTAssertTrue(scroll.isFindBarVisible, "Find in Note must open the native find interface in rich and Source modes")
                XCTAssertNotNil(scroll.findBarView)
                XCTAssertEqual(view.attributedString(), before)
                XCTAssertEqual(coordinator.lastMarkdown, text)
                XCTAssertEqual(view.selectedRange(), selection)
                XCTAssertEqual(view.undoManager?.canUndo, undoable)
            }
        }
    }
    @MainActor func testImageDialogInheritsZoomAndResizesWithoutChangingTheNote() throws {
        let suite = "Zerus-image-zoom-" + UUID().uuidString, preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences.set(150, forKey: "zerus.mac.interfaceZoom")
        defer { preferences.removePersistentDomain(forName: suite) }
        let source = "![Caption](diagram.png)\n", image = NSImage(size: .init(width: 800, height: 400))
        let editor = MacRichEditor(markdown: source, source: false, editable: true, images: ["diagram.png": image], onChange: { _ in }, onLink: { _ in }).defaultAppStorage(preferences)
        try withHostedEditor(editor) { view, coordinator, host in
            let window = try XCTUnwrap(view.window)
            window.setFrameOrigin(NSPoint(x: -20000, y: 0)); window.title = "Image zoom fixture"; window.orderFront(nil)
            func settle() { for _ in 0..<20 { host.layoutSubtreeIfNeeded(); window.attachedSheet?.contentView?.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)) } }
            func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
            coordinator.imageAction(at: (view.string as NSString).range(of: "\u{fffc}").location, action: "edit"); settle()
            let panel = try XCTUnwrap(window.attachedSheet), content = try XCTUnwrap(panel.contentView)
            let caption = try XCTUnwrap(nodes(content).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Caption" })
            for (zoom, width): (Int, CGFloat) in [(150, 150), (80, 80)] {
                preferences.set(zoom, forKey: "zerus.mac.interfaceZoom"); settle()
                XCTAssertEqual(caption.convert(NSRect(x: 0, y: 0, width: 100, height: 100), to: content).width, width, accuracy: 0.5)
                let expectedWidth = min(580 * CGFloat(zoom) / 100, (NSScreen.main?.visibleFrame.width ?? 1280) - 80)
                XCTAssertEqual(content.bounds.width, expectedWidth, accuracy: 2, "The AppKit image panel must resize with its zoomed content")
                XCTAssertEqual(coordinator.lastMarkdown, source)
            }
            coordinator.detach(); settle(); XCTAssertNil(window.attachedSheet)
        }
    }
    @MainActor func testInterfaceZoomScalesNativePanesWhileKeepingWritingSelectionAndUndo() throws {
        let suite = "Zerus-zoom-" + UUID().uuidString, state = MacCompactFixtureState()
        state.markdown += "\n- [ ] Zoom check\n\n10. [ ] Numbered check\n\n>1) [ ] Quoted check\n"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        try withHostedEditor(MacZoomViewport { MacCompactFixture(state: state) }.defaultAppStorage(preferences)) { view, coordinator, host in
            func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
            func settle() { for _ in 0..<8 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) } }
            view.window?.setContentSize(NSSize(width: 1100, height: 700)); settle()
            let original = coordinator.lastMarkdown, target = (view.string as NSString).range(of: "Original")
            view.setSelectedRange(target); view.insertText("Zoomed", replacementRange: target)
            let saved = coordinator.lastMarkdown, selection = view.selectedRange()
            for (percentage, factor): (Int, CGFloat) in [(80, 0.8), (150, 1.5), (100, 1), (125, 1.25), (90, 0.9), (110, 1.1), (115, 1)] {
                preferences.set(percentage, forKey: "zerus.mac.interfaceZoom"); settle()
                XCTAssertTrue(nodes(host).contains { $0 === view }, "Zoom cannot recreate the editor")
                XCTAssertEqual(view.selectedRange(), selection); XCTAssertEqual(coordinator.lastMarkdown, saved)
                XCTAssertEqual(view.convert(NSRect(x: 0, y: 0, width: 100, height: 100), to: host).width, 100, accuracy: 0.5, "Interface zoom must keep note content at its chosen size")
                let collection = try XCTUnwrap(nodes(host).first { $0.identifier?.rawValue == "collection" })
                XCTAssertEqual(collection.convert(NSRect(x: 0, y: 0, width: 100, height: 100), to: host).width, 100 * factor, accuracy: 0.5, "The note list must scale along with the editor")
                let scroll = try XCTUnwrap(view.enclosingScrollView), rect = scroll.convert(scroll.bounds, to: host)
                XCTAssertGreaterThanOrEqual(rect.minX, -1); XCTAssertLessThanOrEqual(rect.maxX, host.bounds.maxX + 1)
                let manager = try XCTUnwrap(view.layoutManager), container = try XCTUnwrap(view.textContainer)
                manager.ensureLayout(for: container)
                XCTAssertTrue(view.window?.firstResponder === view)
                if percentage == 80 || percentage == 150 {
                    for (label, expected) in [("☐ Zoom check", "- [x] Zoom check"), ("☐ Numbered check", "10. [x] Numbered check"), ("☐ Quoted check", ">1) [x] Quoted check")] {
                        let text = (view.string as NSString).range(of: label)
                        guard text.location != NSNotFound else { XCTFail("Missing checkbox label: " + label); continue }
                        let check = NSRange(location: text.location, length: 1)
                        view.scrollRangeToVisible(check); settle()
                        manager.ensureLayout(for: container)
                        let glyphs = manager.glyphRange(forCharacterRange: check, actualCharacterRange: nil)
                        let glyph = manager.boundingRect(forGlyphRange: glyphs, in: container)
                        let point = NSPoint(x: view.textContainerOrigin.x + glyph.midX, y: view.textContainerOrigin.y + glyph.midY)
                        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                        XCTAssertTrue(view.visibleRect.contains(point), "The checkbox click must target the visible viewport")
                        // An unhandled click enters AppKit's tracking loop. Give
                        // it the matching release so a miss fails instead of hanging.
                        let release = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: event.locationInWindow, modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
                        NSApp.postEvent(release, atStart: true)
                        view.mouseDown(with: event)
                        XCTAssertTrue(coordinator.lastMarkdown.contains(expected), "A scaled native checkbox click must reach the correct item, including a numbered marker")
                        coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
                        view.setSelectedRange(selection)
                    }
                }
            }
            for size in [80, 125, 150, 100] {
                preferences.set(size, forKey: "zerus.mac.noteTextSize"); settle()
                XCTAssertEqual(view.convert(NSRect(x: 0, y: 0, width: 100, height: 100), to: host).width, CGFloat(size), accuracy: 0.5)
                XCTAssertEqual(view.selectedRange(), selection)
                XCTAssertEqual(coordinator.lastMarkdown, saved)
                XCTAssertTrue(nodes(host).contains { $0 === view })
                let collection = try XCTUnwrap(nodes(host).first { $0.identifier?.rawValue == "collection" })
                XCTAssertEqual(collection.convert(NSRect(x: 0, y: 0, width: 100, height: 100), to: host).width, 100, accuracy: 0.5, "Note size must leave navigation unchanged")
            }
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
            coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
        }
    }
    @MainActor func testCompactPanesKeepTheSameNativeEditorAndUndoWhileHiddenOrResized() throws {
        let state = MacCompactFixtureState()
        let original = state.markdown
        try withHostedEditor(MacCompactFixture(state: state)) { view, coordinator, host in
            @MainActor func settle(_ width: CGFloat? = nil) {
                if let width { view.window?.setContentSize(NSSize(width: width, height: 600)) }
                for _ in 0..<5 { RunLoop.current.run(until: Date().addingTimeInterval(0.01)); host.layoutSubtreeIfNeeded() }
            }
            func findEditor(_ node: NSView) -> NSTextView? { (node as? NSTextView) ?? node.subviews.lazy.compactMap { findEditor($0) }.first }
            func probe(_ name: String, in node: NSView) -> NSView? {
                if node.identifier?.rawValue == name { return node }
                return node.subviews.lazy.compactMap { probe(name, in: $0) }.first
            }
            @MainActor func visible(_ name: String) throws -> Bool { (probe(name, in: host)?.visibleRect.width ?? 0) > 1 }
            settle(1400)
            XCTAssertTrue(try visible("library")); XCTAssertTrue(try visible("collection")); XCTAssertTrue(try visible("inspector"))
            let target = (view.string as NSString).range(of: "Original")
            view.setSelectedRange(target); view.insertText("Edited", replacementRange: target)
            let saved = coordinator.lastMarkdown, selected = view.selectedRange()
            for width: CGFloat in [980, 650, 500, 1400] {
                settle(width)
                XCTAssertTrue(findEditor(host) === view, "Reflow must not recreate the native editor")
                XCTAssertEqual(view.selectedRange(), selected)
                XCTAssertEqual(coordinator.lastMarkdown, saved)
                XCTAssertTrue(view.isEditable)
                for name in ["library", "collection", "inspector"] {
                    guard let node = probe(name, in: host) else { XCTAssertEqual(name, "collection"); continue }
                    if node.visibleRect.width > 1 {
                        let rect = node.convert(node.bounds, to: host)
                        XCTAssertGreaterThanOrEqual(rect.minX, -1)
                        XCTAssertLessThanOrEqual(rect.maxX, host.bounds.maxX + 1, "Visible panes must fit the viewport")
                    }
                }
                let scroll = try XCTUnwrap(view.enclosingScrollView), editorRect = scroll.convert(scroll.bounds, to: host)
                XCTAssertGreaterThanOrEqual(editorRect.minX, -1); XCTAssertLessThanOrEqual(editorRect.maxX, host.bounds.maxX + 1)
                if width == 980 { XCTAssertTrue(try visible("collection")); XCTAssertFalse(try visible("inspector")) }
                if width == 650 { XCTAssertTrue(try visible("library")); XCTAssertFalse(try visible("collection")) }
                if width == 500 { XCTAssertFalse(try visible("library")); XCTAssertFalse(try visible("collection")) }
            }
            settle(500); state.browsing = true; settle()
            XCTAssertTrue(findEditor(host) === view)
            XCTAssertTrue(try visible("collection")); XCTAssertFalse(view.isEditable)
            XCTAssertFalse(view.window?.firstResponder === view)
            coordinator.action("bold"); XCTAssertEqual(coordinator.lastMarkdown, saved)
            state.browsing = false; settle()
            XCTAssertTrue(view.isEditable); XCTAssertTrue(view.window?.firstResponder === view, "Returning to the note must restore its typing focus")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
            coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
            for mode in ["Gallery", "Kanban", "Table", "Calendar"] {
                state.mode = mode
                for width: CGFloat in [1400, 650] {
                    state.browsing = false; settle(width)
                    let caret = view.selectedRange()
                    XCTAssertFalse(try visible("collection"), "\(mode) must not share the note's editing pane")
                    XCTAssertTrue(findEditor(host) === view); XCTAssertTrue(view.isEditable)
                    state.browsing = true; settle()
                    XCTAssertTrue(try visible("collection")); XCTAssertFalse(view.isEditable)
                    XCTAssertLessThan(view.visibleRect.width, 1, "Browsing \(mode) hides the note")
                    XCTAssertFalse(view.window?.firstResponder === view)
                    state.browsing = false; settle()
                    XCTAssertFalse(try visible("collection")); XCTAssertTrue(view.isEditable)
                    XCTAssertTrue(findEditor(host) === view); XCTAssertEqual(view.selectedRange(), caret)
                    XCTAssertEqual(coordinator.lastMarkdown, saved)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
                }
            }
            state.mode = "List"; settle(1400)
            XCTAssertTrue(try visible("collection")); XCTAssertTrue(view.isEditable)
            state.interactive = false; settle()
            XCTAssertFalse(view.isEditable); XCTAssertFalse(view.window?.firstResponder === view)
            state.interactive = true; settle()
            XCTAssertTrue(view.isEditable); XCTAssertTrue(view.window?.firstResponder === view, "Closing a drawer must restore the previously focused editor")
        }
    }
    @MainActor func testWritingColumnPreferencesReflowTheNativeEditorWithoutChangingTextSelectionOrUndo() throws {
        let suite = "Zerus-layout-test-" + UUID().uuidString, preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let original = "# Heading\n\nA **bold** paragraph with a [link](https://example.com).\n\n- First\n\n  Second\n\n```swift\nlet value = 42\n```\n\n| A | B |\n| --- | --- |\n| One | Two |\n"
        for source in [false, true] {
            preferences.set(100, forKey: "zerus.mac.noteWidth"); preferences.set("center", forKey: "zerus.mac.noteAlignment")
            try withHostedEditor(MacLayoutEditorFixture(markdown: original, source: source, preferences: preferences)) { view, coordinator, host in
                let paragraph = (view.string as NSString).range(of: "paragraph")
                view.setSelectedRange(paragraph); view.insertText("changed", replacementRange: paragraph)
                let saved = coordinator.lastMarkdown, selected = view.selectedRange()
                @MainActor func settle() {
                    for _ in 0..<3 { RunLoop.current.run(until: Date().addingTimeInterval(0.01)); host.layoutSubtreeIfNeeded(); view.layoutSubtreeIfNeeded() }
                    view.layoutManager?.ensureLayout(for: view.textContainer!)
                }
                @MainActor func check(width: Int, centered: Bool) throws {
                    settle()
                    let container = try XCTUnwrap(view.textContainer), manager = try XCTUnwrap(view.layoutManager)
                    let expected = (view.bounds.width - 92) * CGFloat(width) / 100
                    XCTAssertEqual(container.containerSize.width, expected, accuracy: 0.5)
                    XCTAssertEqual(view.textContainerOrigin.x, centered ? (view.bounds.width - expected) / 2 : 46, accuracy: 0.5)
                    XCTAssertEqual(view.selectedRange(), selected)
                    XCTAssertEqual(coordinator.lastMarkdown, saved)
                    XCTAssertEqual(source ? view.string : MacMarkdown.markdown(view.attributedString()), saved)
                    let glyph = manager.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: container)
                    let hit = NSPoint(x: view.textContainerOrigin.x + glyph.minX + glyph.width * 0.2, y: view.textContainerOrigin.y + glyph.midY)
                    XCTAssertEqual(view.characterIndexForInsertion(at: hit), 0, "Hit testing must follow the writing column")
                }
                for width in [100, 85, 75, 60] {
                    for alignment in ["left", "center"] {
                        preferences.set(width, forKey: "zerus.mac.noteWidth"); preferences.set(alignment, forKey: "zerus.mac.noteAlignment")
                        try check(width: width, centered: alignment == "center")
                    }
                }
                view.setFrameSize(NSSize(width: 32, height: view.frame.height)); view.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(view.textContainer?.containerSize.width ?? 0, 1, "An initial zero/small frame must not lay out one glyph per line")
                view.setFrameSize(NSSize(width: 700, height: view.frame.height))
                XCTAssertEqual(view.textContainer?.containerSize.width ?? 0, (700 - 92) * 0.6, accuracy: 0.5, "Geometry must be ready before a heading request can run")
                view.window?.setContentSize(NSSize(width: 900, height: 500)); try check(width: 60, centered: true)
                preferences.set(999, forKey: "zerus.mac.noteWidth"); preferences.set("invalid", forKey: "zerus.mac.noteAlignment")
                try check(width: 100, centered: true)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
            }
        }
        preferences.set(75, forKey: "zerus.mac.noteWidth"); preferences.set("left", forKey: "zerus.mac.noteAlignment")
        try withHostedEditor(MacLayoutEditorFixture(markdown: original, source: false, preferences: preferences)) { view, _, host in
            for _ in 0..<3 { RunLoop.current.run(until: Date().addingTimeInterval(0.01)); host.layoutSubtreeIfNeeded(); view.layoutSubtreeIfNeeded() }
            XCTAssertEqual(view.textContainer?.containerSize.width ?? 0, (view.bounds.width - 92) * 0.75, accuracy: 0.5)
            XCTAssertEqual(view.textContainerOrigin.x, 46, accuracy: 0.5)
        }
    }
    @MainActor func testImageDragAtColumnLimitDoesNotRewriteItsSavedSizeAndShrinkingIsUndoable() throws {
        let suite = "Zerus-image-column-test-" + UUID().uuidString, preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let original = "<img src=\"figure.png\" width=\"1600\" height=\"800\" />\n"
        for width in [100, 60] {
            preferences.set(width, forKey: "zerus.mac.noteWidth")
            let editor = MacLayoutEditorFixture(markdown: original, source: false, preferences: preferences, images: ["figure.png": NSImage(size: NSSize(width: 1600, height: 800))])
            try withHostedEditor(editor) { view, coordinator, host in
                for _ in 0..<3 { host.layoutSubtreeIfNeeded(); view.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                let manager = try XCTUnwrap(view.layoutManager), container = try XCTUnwrap(view.textContainer)
                func imageRect() -> NSRect {
                    manager.ensureLayout(for: container)
                    let glyph = manager.glyphIndexForCharacter(at: 0), bounds = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
                    return NSRect(x: bounds.minX + view.textContainerOrigin.x, y: bounds.minY + view.textContainerOrigin.y, width: manager.attachmentSize(forGlyphAt: glyph).width, height: manager.attachmentSize(forGlyphAt: glyph).height)
                }
                func event(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
                    try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                }
                func drag(_ delta: CGFloat) throws {
                    view.setSelectedRange(NSRange(location: 0, length: 1))
                    let rect = imageRect(), start = NSPoint(x: rect.maxX, y: rect.maxY), finish = NSPoint(x: start.x + delta, y: start.y)
                    view.mouseDown(with: try event(.leftMouseDown, at: start))
                    view.mouseDragged(with: try event(.leftMouseDragged, at: finish))
                    view.mouseUp(with: try event(.leftMouseUp, at: finish))
                }
                try drag(2000)
                XCTAssertEqual(coordinator.lastMarkdown, original, "Dragging outward at the visible limit must not replace a larger saved image size")
                XCTAssertFalse(view.undoManager?.canUndo ?? true)
                try drag(-60)
                let saved = coordinator.lastMarkdown
                XCTAssertNotEqual(saved, original)
                let markup = try XCTUnwrap(MacInlineImage.parse(saved.trimmingCharacters(in: .whitespacesAndNewlines)))
                XCTAssertEqual(CGFloat(try XCTUnwrap(markup.width)), imageRect().width, accuracy: 1)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
            }
        }
    }
    @MainActor func testThemeChangesDuringCompositionAndCodeCardDrawingUseTheNativeView() throws {
        let editor = MacRichEditor(markdown: "```swift\nlet answer = 42\n```\n", source: false, editable: true, onChange: { _ in }, onLink: { _ in })
        try withHostedEditor(editor) { view, coordinator, _ in
            var palette = MacThemePalette.defaults(dark: false)
            palette.colors[.text] = "#123456"; palette.colors[.editorBg] = "#EFEADD"; palette.colors[.accent] = "#AA3344"
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            view.setMarkedText("z", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.selectedRange())
            XCTAssertTrue(view.hasMarkedText())
            coordinator.applyTheme(.init(palette: palette))
            view.unmarkText()
            XCTAssertFalse(view.hasMarkedText())
            XCTAssertEqual(view.insertionPointColor.usingColorSpace(.sRGB), palette.color(.accent).usingColorSpace(.sRGB))
            XCTAssertEqual(view.backgroundColor.usingColorSpace(.sRGB), palette.color(.editorBg).usingColorSpace(.sRGB))
            coordinator.applyTheme(.init(palette: palette))
            view.appearance = NSAppearance(named: .aqua)
            view.layoutManager?.ensureLayout(for: view.textContainer!)
            let rich = view.attributedString(), manager = try XCTUnwrap(view.layoutManager), container = try XCTUnwrap(view.textContainer)
            var codeRange = NSRange(location: NSNotFound, length: 0)
            rich.enumerateAttribute(.macCode, in: NSRange(location: 0, length: rich.length)) { value, range, stop in if value != nil { codeRange = range; stop.pointee = true } }
            XCTAssertNotEqual(codeRange.location, NSNotFound)
            let glyphs = manager.glyphRange(forCharacterRange: codeRange, actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: bitmap)
            var ink = 0
            let scaleX = CGFloat(bitmap.pixelsWide) / view.bounds.width, scaleY = CGFloat(bitmap.pixelsHigh) / view.bounds.height
            for x in Int((rect.minX + 14) * scaleX)..<Int((rect.minX + 250) * scaleX) {
                for y in max(0, Int((rect.minY - 18) * scaleY))..<max(0, Int((rect.minY - 6) * scaleY)) where x < bitmap.pixelsWide && y < bitmap.pixelsHigh {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.redComponent < 0.75 && color.greenComponent < 0.75 && color.blueComponent < 0.75 { ink += 1 }
                }
            }
            XCTAssertGreaterThan(ink, 20, "The language/continue-writing label must remain visible above the code text.")
        }
    }
    @MainActor func testOrdinaryTypingDoesNotRecolourUntouchedParagraphs() {
        withEditor(String(repeating: "A paragraph with a [link](https://example.com).\n\n", count: 1000)) { view, coordinator in
            let storage = view.textStorage!
            var wideAttributeEdits = 0
            let observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { _ in
                if storage.editedMask.contains(.editedAttributes), storage.editedRange.length > 100 { wideAttributeEdits += 1 }
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            view.setSelectedRange(NSRange(location: 1, length: 0)); view.insertText("X", replacementRange: view.selectedRange())
            XCTAssertTrue(coordinator.lastMarkdown.hasPrefix("AX paragraph"))
            XCTAssertEqual(wideAttributeEdits, 0, "A keystroke must not restyle the rest of a long note.")
        }
    }
    @MainActor func testRepeatedBodyEditsKeepEarlierFormattingAndExternalStorageChanges() throws {
        let sources = [
            "# Title\n\nAlpha **bold** and [link](https://e.invalid).\n\nBeta 😀.\n\nOmega.\n",
            "# Title\n\n> Alpha **bold** and [link](https://e.invalid).\n>\n> Beta 😀.\n>\n\nOmega.\n",
            "# Title\n\n>>Alpha **bold** and [link](https://e.invalid).\n>>\n>>Beta 😀.\n>>\n\nOmega.\n",
            "# Title\n\n> > Alpha **bold** and [link](https://e.invalid).\n> >\n> > Beta 😀.\n> >\n\nOmega.\n",
            "# Title\n\n> - Parent\n>\n> Alpha **bold** and [link](https://e.invalid).\n>\n> Beta 😀.\n>\n\nOmega.\n",
            "# Title\n\n> Alpha **bold** and [link](https://e.invalid).\n> - Child\n>\n> Beta 😀.\n> ```text\n> keep\n> ```\n\nOmega.\n",
            "# Title\n\n> Alpha **bold** and [link](https://e.invalid).\n>\n> Beta 😀.\n>\n> Omega.",
            "Title\n=====\n\nAlpha **bold** and [link](https://e.invalid).\n\nBeta 😀.\n\nOmega.",
            "# Title\n \nAlpha **bold** and [link](https://e.invalid).\n\nBeta 😀.\n\nOmega.\n\n",
            "# Title\n\nAlpha **bold** and [link](https://e.invalid).\nwrapped continuation.\n\nBeta 😀.\n\nOmega.\n",
            "# Title\n\nAlpha **bold** and [link](https://e.invalid).\n\nBeta 😀.\n\n- Parent\n  ```swift\n  keep\n  ```\n\nOmega.\n",
            "# Title\n\n- Alpha **bold** and [link](https://e.invalid).\n- Beta 😀.\n  - Child\n\n- Parent\n  ```swift\n  keep\n  ```\n\nOmega.\n",
            "# Title\n\n10. Alpha **bold** and [link](https://e.invalid).\n11. Beta 😀.\n    - Child\n\n12. Parent\n    ```swift\n    keep\n    ```\n\nOmega.\n",
            "# Title\n\n- [ ] Alpha **bold** and [link](https://e.invalid).\n- [x] Beta 😀.\n  - Child\n\n- Parent\n  ```swift\n  keep\n  ```\n\nOmega.\n",
            "# Title\n\nAlpha **bold** and [link](https://e.invalid).\n\n```swift\nkeep 🧑🏽‍💻\n```\n\n| A | B |\n| --- | --- |\n| keep | 日本語 |\n\nBeta 😀.\n\nOmega.\n",
            "# Title\n\n```text\nkeep 🧑🏽‍💻\n```\n\n- Parent\n  - Child\n\nAlpha **bold** and [link](https://e.invalid).\n\nBeta 😀.\n\nOmega.",
            "# Title\n\n- Alpha **bold** and [link](https://e.invalid).\n  - Nested keep\n- Beta 😀.\n  - Child\n\nOmega.\n",
            "# Title\n\n```swift\nkeep 🧑🏽‍💻\n```\n\n9. [ ] Alpha **bold** and [link](https://e.invalid).\n   - Nested keep\n10. [x] Beta 😀.\n    - Child\n\nOmega.\n",
            "# Title\n\n- Parent\n  - Alpha **bold** and [link](https://e.invalid).\n    - Grandchild\n  - Beta 😀.\n    - Child\n- Sibling\n\nOmega.\n",
            "# Title\n\n10. Parent\n    9. Alpha **bold** and [link](https://e.invalid).\n       - Grandchild\n    10. Beta 😀.\n        - Child\n11. Sibling\n\nOmega.\n",
            "# Title\n\n- Parent\n  - [ ] Alpha **bold** and [link](https://e.invalid).\n  - [x] Beta 😀.\n    - Child\n- Sibling\n\nOmega.\n",
            "# Title\n\n- Parent\n  - Branch\n    - Alpha **bold** and [link](https://e.invalid).\n    - Beta 😀.\n\nOmega.",
            "# Title\n\n- Parent\n\n  - Alpha **bold** and [link](https://e.invalid).\n\n  - Beta 😀.\n\nOmega.\n",
            "# Title\n\n- Parent\n  - Alpha **bold** and [link](https://e.invalid).\n\n    Tail paragraph.\n  - Beta 😀.\n\nOmega.\n",
            "# Title\n\n> - Parent\n>   - Alpha **bold** and [link](https://e.invalid).\n>     - Grandchild\n>   - Beta 😀.\n>     - Child\n> - Sibling\n>\n\nOmega.\n",
            "# Title\n\n> 10. Parent\n>     9. Alpha **bold** and [link](https://e.invalid).\n>        - Grandchild\n>     10. Beta 😀.\n>         - Child\n> 11. Sibling\n>\n\nOmega.\n",
            "# Title\n\n> - Parent\n>   - [ ] Alpha **bold** and [link](https://e.invalid).\n>   - [x] Beta 😀.\n>     - Child\n> - Sibling\n>\n\nOmega.\n",
            "# Title\n\n>>- Parent\n>>   - Alpha **bold** and [link](https://e.invalid).\n>>   - Beta 😀.\n\nOmega.",
            "# Title\n\n> > - Alpha **bold** and [link](https://e.invalid).\n> > - [x] Beta 😀.\n> >\n\nOmega.\n",
            "# Title\n\n  > - Alpha **bold** and [link](https://e.invalid).\n  > - Beta 😀.\n  >\n\nOmega.\n"
        ]
        for ending in ["\n", "\r\n", "\r"] { for template in sources {
            let source = template.replacingOccurrences(of: "\n", with: ending)
            try withEditor(source) { view, coordinator in
                var expected = source
                @MainActor func check() {
                    XCTAssertEqual(coordinator.lastMarkdown, expected)
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected)
                }
                @MainActor func replace(_ needle: String, with replacement: String) throws {
                    let range = (view.string as NSString).range(of: needle)
                    guard range.location != NSNotFound else { XCTFail("Missing edited text: " + needle); return }
                    view.breakUndoCoalescing()
                    if let undo = view.undoManager, undo.groupingLevel == 1 { undo.endUndoGrouping(); undo.beginUndoGrouping() }
                    view.setSelectedRange(range); view.insertText(replacement, replacementRange: range)
                    expected = expected.replacingOccurrences(of: needle, with: replacement)
                    check()
                }
                try replace("Alpha", with: "Alphax")
                try replace("😀", with: "é")
                try replace("Beta", with: "BetaY")
                view.setSelectedRange((view.string as NSString).range(of: "BetaY")); coordinator.action("bold")
                expected = expected.replacingOccurrences(of: "BetaY", with: "**BetaY**"); check()
                let formatted = expected
                try replace("Alphax", with: "Alphaxy")
                let typed = expected
                view.undoManager?.undo(); expected = formatted; check()
                view.undoManager?.redo(); expected = typed; check()
                try replace("é", with: "😀é")
                // A storage edit can bypass shouldChangeTextIn, and can change
                // several paragraphs in one transaction. It must reach autosave.
                let storage = try XCTUnwrap(view.textStorage)
                let alpha = (storage.string as NSString).range(of: "Alphaxy")
                let omega = (storage.string as NSString).range(of: "Omega")
                storage.beginEditing()
                storage.replaceCharacters(in: omega, with: "Last")
                storage.replaceCharacters(in: alpha, with: "First")
                storage.endEditing(); view.didChangeText()
                expected = expected.replacingOccurrences(of: "Omega", with: "Last").replacingOccurrences(of: "Alphaxy", with: "First"); check()
                try replace("First", with: "FirstZ")
                coordinator.load("Other document." + ending, source: false)
                expected = "Other document." + ending
                try replace("Other", with: "New")
                try replace("document", with: "note")
            }
        } }
        // Headings and closed code blocks already terminate their quote.
        // Editing the following root prose must not insert a source separator.
        for (prefix, quotedText) in [
            ("> # Quoted heading\n", "Quoted heading"),
            ("> ## Quoted heading\n", "Quoted heading"),
            ("> > ### Quoted heading\n", "Quoted heading"),
            ("> ```swift\n> keep\n> ```\n", "keep"),
            ("> ~~~text\n> keep\n> ~~~\n", "keep"),
            ("> > ```swift\n> > keep\n> > ```\n", "keep")
        ] {
            for ending in ["\n", "\r\n", "\r"] {
                let source = (prefix + "Alpha.\n\nOmega.\n").replacingOccurrences(of: "\n", with: ending)
                let expected = (prefix + "Alphax.\n\nOmega.\n").replacingOccurrences(of: "\n", with: ending)
                let undone = source
                withEditor(source) { view, coordinator in
                    let target = (view.string as NSString).range(of: "Alpha")
                    let caret = NSRange(location: NSMaxRange(target), length: 0)
                    view.setSelectedRange(caret); view.insertText("x", replacementRange: caret)
                    XCTAssertEqual(coordinator.lastMarkdown, expected)
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected)
                    // Undo restores the imported bytes as well as the text.
                    view.undoManager?.undo(); XCTAssertEqual(coordinator.lastMarkdown, undone)
                    view.undoManager?.redo(); XCTAssertEqual(coordinator.lastMarkdown, expected)
                    view.undoManager?.undo(); XCTAssertEqual(coordinator.lastMarkdown, source)
                    // Editing the quoted predecessor takes the unchanged-root
                    // token path, which must preserve the same boundary.
                    view.breakUndoCoalescing()
                    let quoted = (view.string as NSString).range(of: quotedText)
                    guard quoted.location != NSNotFound else { return XCTFail("Missing quoted target") }
                    view.setSelectedRange(NSRange(location: NSMaxRange(quoted), length: 0))
                    view.insertText("y", replacementRange: view.selectedRange())
                    let changedQuote = source.replacingOccurrences(of: quotedText, with: quotedText + "y")
                    XCTAssertEqual(coordinator.lastMarkdown, changedQuote)
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), changedQuote)
                    let rootBodies = Document(parsing: coordinator.lastMarkdown).children.compactMap { ($0 as? Paragraph)?.plainText }
                    XCTAssertEqual(rootBodies, ["Alpha.", "Omega."])
                    view.undoManager?.undo(); XCTAssertEqual(coordinator.lastMarkdown, source)
                }
            }
        }
        // After an ordinary edit has seeded export reuse, external storage
        // mutations can empty and refill the same item without delegate hooks.
        for (before, empty, filled) in [
            ("- Alpha\n- Beta\n", "- \n- Beta\n", "- Again\n- Beta\n"),
            ("1. Alpha\n2. Beta\n", "1. \n2. Beta\n", "1. Again\n2. Beta\n"),
            ("- [ ] Alpha\n- [x] Beta\n", "- [ ] \n- [x] Beta\n", "- [ ] Again\n- [x] Beta\n"),
            ("- Beta\n- Alpha", "- Beta\n- ", "- Beta\n- Again"),
            ("Intro\n\n- Alpha\n\n- Beta\n", "Intro\n\n- \n\n- Beta\n", "Intro\n\n- Again\n\n- Beta\n"),
            ("- Beta\n- Alpha\n\nOutside\n", "- Beta\n- \n\nOutside\n", "- Beta\n- Again\n\nOutside\n")
        ] { for ending in ["\n", "\r\n", "\r"] {
            let source = before.replacingOccurrences(of: "\n", with: ending)
            try withEditor(source) { view, coordinator in
                @MainActor func check(_ expected: String) {
                    XCTAssertEqual(coordinator.lastMarkdown, expected)
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected)
                    var parents: [Int?] = []
                    func collect(_ node: any Markup, parent: Int? = nil) {
                        var owner = parent
                        if node is ListItem { owner = parents.count; parents.append(parent) }
                        for child in node.children { collect(child, parent: owner) }
                    }
                    collect(Document(parsing: coordinator.lastMarkdown))
                    XCTAssertEqual(parents, [nil, nil])
                }
                let alpha = (view.string as NSString).range(of: "Alpha")
                guard alpha.location != NSNotFound else { XCTFail("Missing item body"); return }
                view.setSelectedRange(NSRange(location: NSMaxRange(alpha), length: 0))
                view.insertText("X", replacementRange: view.selectedRange())
                check(source.replacingOccurrences(of: "Alpha", with: "AlphaX"))
                // Escaping changes source offsets by more than native offsets.
                view.insertText("*", replacementRange: view.selectedRange())
                check(source.replacingOccurrences(of: "Alpha", with: "AlphaX\\*"))
                view.deleteBackward(nil)
                check(source.replacingOccurrences(of: "Alpha", with: "AlphaX"))
                let storage = try XCTUnwrap(view.textStorage)
                let body = (storage.string as NSString).range(of: "AlphaX")
                storage.replaceCharacters(in: body, with: ""); view.didChangeText()
                check(empty.replacingOccurrences(of: "\n", with: ending))
                storage.replaceCharacters(in: NSRange(location: body.location, length: 0), with: "Again"); view.didChangeText()
                check(filled.replacingOccurrences(of: "\n", with: ending))
            }
        } }
    }
    @MainActor func testLivePaletteChangesKeepMarkdownSelectionCodeColoursAndUndo() throws {
        let original = "# Title\n\nBody [Link](https://example.com) `code`.\n\n```swift\nlet answer = 42\n```\n\n| A | B |\n| --- | --- |\n| One | Two |\n"
        for source in [false, true] {
            withEditor(original, sourceMode: source) { view, coordinator in
                let body = (view.string as NSString).range(of: "Body")
                view.setSelectedRange(body); view.insertText("Changed", replacementRange: body)
                let saved = coordinator.lastMarkdown, selection = view.selectedRange()
                let before = NSAttributedString(attributedString: view.attributedString())
                var palette = MacThemePalette.defaults(dark: false)
                palette.colors[.text] = "#123456"; palette.colors[.link] = "#654321"
                palette.colors[.editorBg] = "#EFEADD"; palette.colors[.accent] = "#AA3344"
                coordinator.applyTheme(.init(palette: palette))
                XCTAssertEqual(view.selectedRange(), selection)
                XCTAssertEqual(coordinator.lastMarkdown, saved)
                XCTAssertEqual(source ? view.string : MacMarkdown.markdown(view.attributedString()), saved)
                let changed = (view.string as NSString).range(of: "Changed")
                XCTAssertEqual((view.attributedString().attribute(.foregroundColor, at: changed.location, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB), palette.color(.text).usingColorSpace(.sRGB))
                XCTAssertEqual(view.backgroundColor, palette.color(.editorBg))
                XCTAssertEqual(view.insertionPointColor, palette.color(.accent))
                if !source {
                    let link = (view.string as NSString).range(of: "Link")
                    XCTAssertEqual((view.attributedString().attribute(.foregroundColor, at: link.location, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB), palette.color(.link).usingColorSpace(.sRGB))
                    before.enumerateAttributes(in: NSRange(location: 0, length: before.length)) { attrs, range, _ in
                        if attrs[.macCode] != nil { XCTAssertEqual(view.attributedString().attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor, attrs[.foregroundColor] as? NSColor) }
                    }
                }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                coordinator.applyTheme(MacTheme())
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
                XCTAssertEqual(source ? view.string : MacMarkdown.markdown(view.attributedString()), saved)
            }
        }
    }
    @MainActor func testBlankWhitespaceKeepsParagraphBoundariesAndHashOnlyHeadingsKeepText() {
        for blank in ["   ", "\t"] {
            withEditor("Hello\n\nWorld\n") { view, coordinator in
                let start = (view.string as NSString).range(of: "Hello").upperBound + 1
                view.setSelectedRange(NSRange(location: start, length: 0)); view.insertText(blank, replacementRange: view.selectedRange())
                let parsed = Document(parsing: coordinator.lastMarkdown)
                XCTAssertEqual(parsed.children.filter { $0 is Paragraph }.count, 2, coordinator.lastMarkdown)
                XCTAssertEqual(coordinator.lastMarkdown, "Hello\n" + blank + "\nWorld\n")
            }
            for prefix in ["- ", "# ", "> # "] {
                withEditor(prefix + "Target\n") { view, coordinator in
                    let word = (view.string as NSString).range(of: "Target"); view.setSelectedRange(word); view.insertText(blank, replacementRange: word)
                    XCTAssertEqual(coordinator.lastMarkdown, prefix + blank + "\n")
                }
            }
        }
        for prefix in ["# ", "> ## "] {
            for hashes in ["#######", "##########"] {
                withEditor(prefix + "Target\n") { view, coordinator in
                    let word = (view.string as NSString).range(of: "Target"); view.setSelectedRange(word); view.insertText(hashes, replacementRange: word)
                    func headings(_ node: any Markup) -> [String] {
                        if let heading = node as? Heading { return [heading.plainText] }
                        return node.children.flatMap(headings)
                    }
                    XCTAssertEqual(headings(Document(parsing: coordinator.lastMarkdown)), [hashes], coordinator.lastMarkdown)
                    XCTAssertEqual(MacMarkdown.render(coordinator.lastMarkdown).string, view.string)
                }
            }
        }
    }
    @MainActor func testLiteralIndentationStaysTextThroughSaveReopenAndUndo() {
        for original in ["First\n\nTarget\n", "- First\n\n  Target\n", "> First\n>\n> Target\n", "# Target\n"] {
            for literal in ["    code", "\tcode", "  code", "code    ", "code\t", " code ", " \u{301}code"] {
                withEditor(original) { view, coordinator in
                    let target = (view.string as NSString).range(of: "Target")
                    view.setSelectedRange(target); view.insertText(literal, replacementRange: target)
                    let saved = coordinator.lastMarkdown
                    func codeBlocks(_ node: any Markup) -> Int { (node is CodeBlock ? 1 : 0) + node.children.map(codeBlocks).reduce(0,+) }
                    XCTAssertEqual(codeBlocks(Document(parsing: saved)), 0, saved)
                    XCTAssertFalse(MacMarkdown.requiresSource(saved), saved)
                    XCTAssertEqual(MacMarkdown.render(saved).string, view.string, saved)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
                }
            }
        }
        let code = "    code\n"
        for literal in ["&#32;literal", "&#9;literal", "&amp; text", "&copy;", "&#x23;"] {
            withEditor("Target\n") { view, coordinator in
                let target = (view.string as NSString).range(of: "Target"); view.setSelectedRange(target); view.insertText(literal, replacementRange: target)
                XCTAssertEqual(MacMarkdown.render(coordinator.lastMarkdown).string, literal + "\n")
                view.textStorage?.addAttribute(.foregroundColor, value: NSColor.textColor, range: NSRange(location: 0, length: 1))
                XCTAssertEqual(MacMarkdown.render(MacMarkdown.markdown(view.attributedString())).string, literal + "\n")
            }
        }
        withEditor(code, sourceMode: true) { view, coordinator in
            let word = (view.string as NSString).range(of: "code"); view.setSelectedRange(word); view.insertText("new", replacementRange: word)
            XCTAssertEqual(coordinator.lastMarkdown, "    new\n")
        }
    }
    @MainActor func testClearingFirstListParagraphPromotesRemainingContentWithoutSplittingItem() {
        for (marker, continuation, separator) in [("- ", "  ", "\n\n"), ("10. ", "    ", "\n\n"), ("> - ", ">   ", "\n>\n"), ("- ", "  ", "  \n")] {
            let source = marker + "one" + separator + continuation + "two\n" + continuation + "- child\n"
            for characterByCharacter in [false, true] {
                withEditor(source) { view, coordinator in
                    let word = (view.string as NSString).range(of: "one")
                    if characterByCharacter {
                        view.setSelectedRange(NSRange(location: word.upperBound, length: 0))
                        for _ in 0..<3 { view.deleteBackward(nil) }
                    } else { view.setSelectedRange(word); view.deleteBackward(nil) }
                    XCTAssertEqual(coordinator.lastMarkdown, marker + "two\n" + continuation + "- child\n")
                    XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
                }
            }
        }
    }
    @MainActor func testLiteralTableDelimiterAfterHardBreakCannotBecomeATable() {
      for (header, delimiter) in [("a | b", "--- | ---"), ("a |", "--- |"), ("| a |", "| --- |"), ("a", "| ---"), ("a |", ":-: |"), ("a", "| :--")] {
        withEditor("- one  \n  two\n- Sib\n") { view, coordinator in
            let two = (view.string as NSString).range(of: "two"); view.setSelectedRange(two); view.insertText(delimiter, replacementRange: two)
            let one = (view.string as NSString).range(of: "one"); view.setSelectedRange(one); view.insertText(header, replacementRange: one)
            let parsed = Document(parsing: coordinator.lastMarkdown)
            func tables(_ node: any Markup) -> Int { (node is Markdown.Table ? 1 : 0) + node.children.map(tables).reduce(0,+) }
            XCTAssertEqual(tables(parsed), 0, coordinator.lastMarkdown)
            XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
            XCTAssertEqual(MacMarkdown.render(coordinator.lastMarkdown).string, view.string)
        }
      }
    }
    @MainActor func testListSeparatorsCannotPromoteLiteralTextOrRepeatHeadingPrefixes() {
        for source in ["Title\r===\r", "a\rb\n# H\n", "Title\r---\r- After\r"] {
            XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(source)), source, "Lone CR input must not trap or duplicate heading content")
        }
        XCTAssertEqual(MacMarkdown.render("a\rb\n# H\n").string, "a\nb\nH\n", "A heading after a CR-containing row must appear exactly once")
        for (source, visible, expected) in [
            ("Title\n===\nAfter\n", "Title\nAfter\n", "# New\nAfter\n"),
            ("Title\n===\n\nAfter\n", "Title\n\nAfter\n", "# New\n\nAfter\n"),
            ("Title\n---\n- After\n- Sibling\n", "Title\n• After\n• Sibling\n", "## New\n- After\n- Sibling\n"),
            ("Title\n===\nNext\n===\nAfter\n", "Title\nNext\nAfter\n", "# New\nNext\n===\nAfter\n"),
            ("> Title\n> ---\n> After\n", "Title\nAfter\n", "> ## New\n> After\n"),
            ("Title\ncontinued\n===\nAfter\n", "Title continued\nAfter\n", "# New continued\nAfter\n")
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                XCTAssertEqual(view.string, visible, "A heading must not swallow its following source line")
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                let title = (view.string as NSString).range(of: "Title")
                guard title.location != NSNotFound else { XCTFail("Heading text must remain visible"); return }
                view.setSelectedRange(title); view.insertText("New", replacementRange: title)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(MacMarkdown.render(coordinator.lastMarkdown).string, visible.replacingOccurrences(of: "Title", with: "New"))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.string, visible); XCTAssertEqual(view.selectedRange(), title)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } }
        for prefix in ["# ", "> ## "] {
            let originalClosing = prefix + "Title ###\n"
            withEditor(originalClosing) { view, coordinator in
                XCTAssertEqual(view.string, "Title\n")
                let title = (view.string as NSString).range(of: "Title"); view.setSelectedRange(title); view.insertText("New", replacementRange: title)
                XCTAssertEqual(coordinator.lastMarkdown, prefix + "New\n")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, originalClosing)
            }
            for hashes in ["#", "###"] {
                let escaped = hashes.map { "\\" + String($0) }.joined()
                let original = prefix + "Title " + escaped + "\n"
                withEditor(original) { view, coordinator in
                    let title = (view.string as NSString).range(of: "Title"); view.setSelectedRange(title); view.insertText("New", replacementRange: title)
                    let saved = coordinator.lastMarkdown
                    func headings(_ node: any Markup) -> [String] {
                        if let heading = node as? Heading { return [heading.plainText] }
                        return node.children.flatMap(headings)
                    }
                    XCTAssertEqual(headings(Document(parsing: saved)), ["New " + hashes], saved)
                    XCTAssertEqual(MacMarkdown.render(saved).string, view.string)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
                }
            }
        }
        for (separator, literal, expected) in [("\n\n", "\\- b", "\\- b"), ("\n\n", "1\\. b", "1\\. b"), ("  \n", "\\# b", "\\# b"), ("  \n", "\\=\\=\\=", "\\===")] {
            let source = "- a" + separator + "  " + literal + "\n- Sib\n"
            withEditor(source) { view, coordinator in
                let a = (view.string as NSString).range(of: "a"); view.setSelectedRange(a); view.insertText("A", replacementRange: a)
                XCTAssertTrue(coordinator.lastMarkdown.contains(expected), coordinator.lastMarkdown)
                let document = Document(parsing: coordinator.lastMarkdown)
                func count(_ node: any Markup, _ predicate: (any Markup) -> Bool) -> Int { (predicate(node) ? 1 : 0) + node.children.map { count($0, predicate) }.reduce(0,+) }
                XCTAssertEqual(count(document, { $0 is ListItem }), 2)
                XCTAssertEqual(count(document, { $0 is Heading }), 0)
            }
        }
      for typed in ["more", "#", "###"] {
        withEditor("# Title\n") { view, coordinator in
            view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "Title").upperBound, length: 0))
            view.insertLineBreak(nil); view.insertText(typed, replacementRange: view.selectedRange())
            let expected = typed == "more" ? typed : typed.map { "\\" + String($0) }.joined()
            XCTAssertEqual(coordinator.lastMarkdown, "# Title " + expected + "\n")
        }
      }
        withEditor("- one\n\n  two\n- Sib\n") { view, coordinator in
            view.setSelectedRange((view.string as NSString).range(of: "one")); coordinator.action("h2")
            XCTAssertEqual(coordinator.lastMarkdown, "## one two\n- Sib\n")
        }
        withEditor("- one\n\n  two #\n- Sib\n") { view, coordinator in
            view.setSelectedRange((view.string as NSString).range(of: "one")); coordinator.action("h2")
            XCTAssertEqual(coordinator.lastMarkdown, "## one two \\#\n- Sib\n")
        }
        withEditor("Para\n") { view, coordinator in
            view.setSelectedRange(NSRange(location: 4, length: 0)); view.insertLineBreak(nil); view.insertText("# x", replacementRange: view.selectedRange())
            XCTAssertEqual(coordinator.lastMarkdown, "Para  \n\\# x\n")
        }
    }
    @MainActor func testLooseListBoundaryEditsAndClipboardNeverLeakNativeSeparators() {
        let source = "- First\n\n  Second\n- Sib\n"
        for boundary in [0, 1, 2] {
            withEditor(source) { view, coordinator in
                let first = (view.string as NSString).range(of: "First")
                view.setSelectedRange(NSRange(location: NSMaxRange(first) + boundary, length: 0)); view.insertNewline(nil)
                XCTAssertEqual(coordinator.lastMarkdown, "- First\n- Second\n- Sib\n")
                XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
            }
        }
        withEditor(source) { view, coordinator in
            let first = (view.string as NSString).range(of: "First")
            let start = NSMaxRange(first) + 1
            let end = (view.string as NSString).range(of: "Second").location + 2
            let selected = NSRange(location: start, length: end - start)
            view.setSelectedRange(selected); view.insertText("X", replacementRange: selected)
            XCTAssertEqual(coordinator.lastMarkdown, "- First\n\n  Xcond\n- Sib\n")
        }
        withEditor(source) { view, _ in
            let begin = (view.string as NSString).range(of: "First").location + 1
            let end = (view.string as NSString).range(of: "Second").location + 3
            XCTAssertEqual(MacMarkdown.markdown(MacClipboard.selection(view.attributedString(), range: NSRange(location: begin, length: end - begin))), "irst\n\nSec")
        }
        withEditor(source) { view, coordinator in
            let begin = (view.string as NSString).range(of: "First").location
            let end = (view.string as NSString).range(of: "Second").upperBound
            view.setSelectedRange(NSRange(location: begin, length: end - begin)); coordinator.action("code")
            XCTAssertEqual(coordinator.lastMarkdown, "- `First`\n\n  `Second`\n- Sib\n")
        }
        withEditor("- First\n") { view, coordinator in
            view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "First").upperBound, length: 0))
            view.insertLineBreak(nil); view.insertText("more", replacementRange: view.selectedRange())
            XCTAssertEqual(coordinator.lastMarkdown, "- First  \n  more\n")
        }
        withEditor("- First  \r\n  wrapped\r\n\r\n  Two\r\n- Sib\r\n") { view, coordinator in
            let word = (view.string as NSString).range(of: "First"); view.setSelectedRange(word); view.insertText("One", replacementRange: word)
            XCTAssertEqual(coordinator.lastMarkdown, "- One  \r\n  wrapped\r\n\r\n  Two\r\n- Sib\r\n")
        }
    }
    @MainActor func testChecklistLiteralBracketTextAndMarkerWhitespaceSurviveNativeEdits() {
        for (source, visible, word, expected) in [
            ("- [ ] [x] literal\n- Sib\n", "☐ [x] literal", "literal", "- [ ] \\[x\\] literal!\n- Sib\n"),
            ("- a\n  - [x] [ ] keep\n", "☑ [ ] keep", "keep", "- a\n  - [x] \\[ \\] keep!\n"),
            ("> - [ ]  task\n", "☐ task", "task", "> - [ ]  task!\n"),
            ("> - [ ] [x] literal\n", "☐ [x] literal", "literal", "> - [ ] \\[x\\] literal!\n"),
            ("- [x] [X] literal\n", "☑ [X] literal", "literal", "- [x] \\[X\\] literal!\n")
        ] {
            XCTAssertFalse(MacMarkdown.requiresSource(source))
            withEditor(source) { view, coordinator in
                XCTAssertTrue(view.string.components(separatedBy: "\n").contains(visible), view.string)
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                let target = (view.string as NSString).range(of: word)
                view.setSelectedRange(NSRange(location: NSMaxRange(target), length: 0))
                view.insertText("!", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            }
        }
        var emptyTasks = [("- [ ]", "• [ ]", "- \\[ \\]New")]
        for ending in ["\n", "\r\n"] {
            emptyTasks.append(("> - [ ] " + ending, "☐ \n", "> - [ ] New" + ending))
            emptyTasks.append(("> 1. [x] " + ending, "1. ☑ \n", "> 1. [x] New" + ending))
        }
        for (source, visible, edited) in emptyTasks {
            withEditor(source) { view, coordinator in
                XCTAssertEqual(view.string, visible)
                XCTAssertEqual(coordinator.lastMarkdown, source)
                view.setSelectedRange(NSRange(location: view.string.hasSuffix("\n") ? view.string.utf16.count - 1 : view.string.utf16.count, length: 0))
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, edited)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.string, visible)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, edited)
            }
        }
    }
    @MainActor func testInterleavedItemParagraphsKeepNativeEditingAndSharedMarkerWidth() {
        for (marker, bodyPrefix, child, ordered, orderedBody, orderedChild) in [
            ("- ", "  ", "  - ", "1. ", "   ", "   - "),
            ("10. ", "    ", "    - ", "1. ", "   ", "   - "),
            ("> - ", ">   ", ">   - ", "> 1. ", ">    ", ">    - "),
            (">- ", ">   ", ">   - ", ">1. ", ">    ", ">    - "),
            ("- [ ] ", "  ", "  - ", "1. ", "   ", "   - ")
        ] { for ending in ["\n", "\r\n"] {
            let gap = marker.hasPrefix(">") ? ">\n" : "\n"
            let source = (marker + "Parent\n" + child + "Child\n" + gap + bodyPrefix + "Tail paragraph.\n" + marker + "Sibling\n").replacingOccurrences(of: "\n", with: ending)
            let formatted = (ordered + "Parent\n" + orderedChild + "Child\n" + gap + orderedBody + "Updated paragraph.\n" + marker + "Sibling\n").replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                XCTAssertTrue(view.string.components(separatedBy: "\n").contains("Tail paragraph."), "Continuation indentation is layout, not literal spaces or a duplicate bullet")
                let tail = (view.string as NSString).range(of: "Tail")
                view.setSelectedRange(tail); view.insertText("Updated", replacementRange: tail)
                let updated = source.replacingOccurrences(of: "Tail", with: "Updated")
                XCTAssertEqual(coordinator.lastMarkdown, updated)
                func paragraphCounts(_ node: any Markup) -> [Int] {
                    let own = node is ListItem ? [node.children.filter { $0 is Paragraph }.count] : []
                    return own + node.children.flatMap(paragraphCounts)
                }
                XCTAssertEqual(paragraphCounts(Document(parsing: coordinator.lastMarkdown)), [2, 1, 1])
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, updated)
                let parent = (view.string as NSString).range(of: "Parent")
                view.setSelectedRange(NSRange(location: NSMaxRange(parent), length: 0))
                coordinator.action("ordered")
                XCTAssertEqual(coordinator.lastMarkdown, formatted)
                XCTAssertEqual(paragraphCounts(Document(parsing: coordinator.lastMarkdown)), [2, 1, 1])
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, updated)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, formatted)
                let copied = (view.string as NSString).range(of: "Updated paragraph.")
                XCTAssertEqual(MacMarkdown.markdown(MacClipboard.selection(view.attributedString(), range: copied)), "Updated paragraph.")
            }
        } }
        for imported in ["- \n  Tail.\n", "- \n  Tail.\n\n  More.\n", "> - \n>   Tail.\n"] {
            XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(imported)), imported, "Untouched leading paragraphs keep their source spelling")
        }
        for (prelude, marker, bodyPrefix, child, paragraphs, laterChild, promotedFirst) in [
            ("", "- ", "  ", "  - ", ["Tail paragraph."], false, nil as String?),
            ("", "10. ", "    ", "    - ", ["Tail paragraph."], false, nil as String?),
            ("", "> - ", ">   ", ">   - ", ["Tail paragraph."], false, nil as String?),
            ("", ">- ", ">   ", ">   - ", ["Tail paragraph."], false, nil as String?),
            ("- Root\n", "  - ", "    ", "    - ", ["Tail paragraph."], false, nil as String?),
            ("", "10. ", "    ", "    - ", ["Tail paragraph.", "Second paragraph."], false, nil as String?),
            ("", "- ", "  ", "  - ", ["[ ] Tail paragraph."], false, "\\[ \\] Tail paragraph."),
            ("", "10. ", "    ", "    - ", ["[x] Tail paragraph."], false, "\\[x\\] Tail paragraph."),
            ("", "> - ", ">   ", ">   - ", ["[X] Tail paragraph."], false, "\\[X\\] Tail paragraph."),
            ("", "- ", "  ", "  - ", ["Tail paragraph."], true, nil as String?)
        ] { for ending in ["\n", "\r\n"] { for blank in ["", "    "] { for initiallyEmpty in [false, true] { for loose in [false, true] {
            // An imported empty head separated from an indented item by a blank
            // does not own that item in CommonMark. Loose fixtures start filled.
            if initiallyEmpty && (!blank.isEmpty || loose) { continue }
            let gap = marker.contains(">") ? ">\n" : "\n", headGap = loose ? gap : ""
            let body = paragraphs.map { bodyPrefix + $0 + "\n" }.joined(separator: gap)
            let promoted = paragraphs.enumerated().map { index, text in
                // This is literal body text, never a request to create a task.
                let literal = index == 0 ? promotedFirst ?? text : text
                return (index == 0 ? marker : bodyPrefix) + literal + "\n"
            }.joined(separator: gap)
            let later = laterChild ? child + "Later\n" : ""
            let label = initiallyEmpty ? "" : "Parent"
            let originalPrelude = initiallyEmpty && !prelude.isEmpty ? prelude + gap : prelude
            let source = (originalPrelude + marker + label + "\n" + headGap + child + "Child\n" + gap + body + later + marker + "Sibling\n").replacingOccurrences(of: "\n", with: ending)
            let removed = (originalPrelude + marker + "Parent\n" + headGap + gap + body + later + marker + "Sibling\n").replacingOccurrences(of: "\n", with: ending)
            let emptied = (originalPrelude + promoted + later + marker + "Sibling\n").replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let raw = view.string as NSString, child = raw.range(of: "Child")
                let row = raw.paragraphRange(for: NSRange(location: child.location, length: 0))
                var head = raw.paragraphRange(for: NSRange(location: row.location - 1, length: 0))
                while raw.substring(with: head).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    head = raw.paragraphRange(for: NSRange(location: head.location - 1, length: 0))
                }
                let headCaret = head.location + MacMarkdown.displayPrefix(marker).utf16.count
                view.setSelectedRange(row); view.insertText("", replacementRange: row)
                var originalSelection = row
                if !initiallyEmpty {
                    XCTAssertEqual(coordinator.lastMarkdown, removed)
                    let parent = (view.string as NSString).range(of: "Parent")
                    originalSelection = parent
                    view.setSelectedRange(parent); view.insertText(blank, replacementRange: parent)
                }
                XCTAssertEqual(coordinator.lastMarkdown, emptied, "A former tail becomes the item's first nonempty paragraph")
                func bodies(_ node: any Markup) -> [[String]] {
                    let own = node is ListItem ? [node.children.compactMap { ($0 as? Paragraph)?.plainText }] : []
                    return own + node.children.flatMap(bodies)
                }
                let outer = prelude.isEmpty ? [] : [["Root"]], laterBody = laterChild ? [["Later"]] : []
                XCTAssertEqual(bodies(Document(parsing: coordinator.lastMarkdown)), outer + [paragraphs] + laterBody + [["Sibling"]])
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), emptied)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, initiallyEmpty ? source : removed)
                XCTAssertEqual(view.selectedRange(), originalSelection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, emptied)
                if initiallyEmpty { view.setSelectedRange(NSRange(location: headCaret, length: 0)) }
                view.insertText("Again", replacementRange: view.selectedRange())
                let refill = blank.isEmpty ? "Again" : "&#32;&#32;&#32;&#32;Again"
                XCTAssertEqual(coordinator.lastMarkdown, removed.replacingOccurrences(of: "Parent", with: refill))
                XCTAssertEqual(bodies(Document(parsing: coordinator.lastMarkdown)), outer + [[blank + "Again"] + paragraphs] + laterBody + [["Sibling"]])
            }
        } } } } }
    }
    @MainActor func testInlineFirstListCardsKeepNativeHeadsAndSourceOwnership() throws {
        let cases: [(source: String, ordered: String, named: String, table: Bool, parents: [Int?], owner: Int, bodyEdit: String?)] = [
            ("- ```swift\n  old\n  ```\n- Sibling\n", "1. ```swift\n   new\n   ```\n- Sibling\n", "- Parent\n  ```swift\n  new\n  ```\n- Sibling\n", false, [nil, nil], 0, nil),
            ("-     old\n- Sibling\n", "1.     new\n- Sibling\n", "- Parent\n  ```\n  new\n  ```\n- Sibling\n", false, [nil, nil], 0, nil),
            ("> 10. ```swift\n>     old\n>     ```\n> 11. Sibling\n", "> 1. ```swift\n>    new\n>    ```\n> 11. Sibling\n", "> 10. Parent\n>     ```swift\n>     new\n>     ```\n> 11. Sibling\n", false, [nil, nil], 0, nil),
            ("- | A | B |\n  | --- | --- |\n  | old | __Other__ |\n- Sibling\n", "1. | A | B |\n   | --- | --- |\n   | new | __Other__ |\n- Sibling\n", "- Parent\n  | A | B |\n  | --- | --- |\n  | new | __Other__ |\n- Sibling\n", true, [nil, nil], 0, nil),
            ("- - ```swift\n    old\n    ```\n- Sibling\n", "- 1. ```swift\n     new\n     ```\n- Sibling\n", "- \n  - Parent\n    ```swift\n    new\n    ```\n- Sibling\n", false, [nil, 0, nil], 1, nil),
            ("-\t```swift\n\told\n\t```\n- Sibling\n", "1. ```swift\n   new\n   ```\n- Sibling\n", "- Parent\n  ```swift\n  new\n  ```\n- Sibling\n", false, [nil, nil], 0, "-   ```swift\n    new\n    ```\n- Sibling\n"),
            (">10. ```swift\n>     old\n>     ```\n>11. Sibling\n", "> 1. ```swift\n>    new\n>    ```\n>11. Sibling\n", "> 10. Parent\n>     ```swift\n>     new\n>     ```\n>11. Sibling\n", false, [nil, nil], 0, "> 10. ```swift\n>     new\n>     ```\n>11. Sibling\n"),
            ("- ```swift\n  old", "1. ```swift\n   new\n   ```", "- Parent\n  ```swift\n  new\n  ```", false, [nil], 0, "- ```swift\n  new\n  ```"),
            ("- > ```swift\n  > old\n  > ```\n- Sibling\n", "1. > ```swift\n   > new\n   > ```\n- Sibling\n", "- Parent\n  > ```swift\n  > new\n  > ```\n- Sibling\n", false, [nil, nil], 0, nil),
            ("-     [x] old\n- Sibling\n", "1.     [x] new\n- Sibling\n", "- Parent\n  ```\n  [x] new\n  ```\n- Sibling\n", false, [nil, nil], 0, nil)
        ]
        func structure(_ source: String) -> (parents: [Int?], cards: [Int?]) {
            var parents: [Int?] = [], cards: [Int?] = []
            func collect(_ node: any Markup, parent: Int? = nil) {
                var owner = parent
                if node is ListItem { owner = parents.count; parents.append(parent) }
                if node is CodeBlock || node is Markdown.Table { cards.append(owner) }
                for child in node.children { collect(child, parent: owner) }
            }
            collect(Document(parsing: source)); return (parents, cards)
        }
        for row in cases { for ending in ["\n", "\r\n", "\r"] {
            let source = row.source.replacingOccurrences(of: "\n", with: ending), changed = (row.bodyEdit ?? row.source.replacingOccurrences(of: "old", with: "new")).replacingOccurrences(of: "\n", with: ending)
            try withEditor(source) { view, coordinator in
                let target = (view.string as NSString).range(of: "old")
                guard target.location != NSNotFound else { XCTFail("The inline-first card must remain visible"); return }
                if row.table { guard MacRichTable.at(view.attributedString(), target.location) != nil else { XCTFail("The inline-first table must have native cells"); return } }
                else { guard MacRichCode.at(view.attributedString(), target.location) != nil else { XCTFail("The inline-first code must have a native card"); return } }
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                XCTAssertEqual(MacMarkdown.nativeListItems(in: view.attributedString())?.map(\.parent), row.parents)
                view.setSelectedRange(target); view.insertText("new", replacementRange: target)
                XCTAssertEqual(coordinator.lastMarkdown, changed)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, changed)
                let head = try XCTUnwrap(MacMarkdown.nativeListItems(in: view.attributedString())?[row.owner])
                let caret = NSRange(location: head.range.location + head.block.display.utf16.count, length: 0)
                view.setSelectedRange(caret); coordinator.action("ordered")
                let ordered = row.ordered.replacingOccurrences(of: "\n", with: ending)
                XCTAssertEqual(coordinator.lastMarkdown, ordered)
                XCTAssertEqual(structure(coordinator.lastMarkdown).parents, row.parents); XCTAssertEqual(structure(coordinator.lastMarkdown).cards, [row.owner])
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, changed); XCTAssertEqual(view.selectedRange(), caret)
                if row.source == "- ```swift\n  old\n  ```\n- Sibling\n" {
                    coordinator.action("checklist")
                    XCTAssertEqual(coordinator.lastMarkdown, "- [ ] \n  ```swift\n  new\n  ```\n- Sibling\n".replacingOccurrences(of: "\n", with: ending))
                    XCTAssertEqual(structure(coordinator.lastMarkdown).cards, [0])
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, changed)
                }
                view.insertText("Parent", replacementRange: caret)
                let named = row.named.replacingOccurrences(of: "\n", with: ending)
                XCTAssertEqual(coordinator.lastMarkdown, named)
                XCTAssertEqual(structure(coordinator.lastMarkdown).parents, row.parents); XCTAssertEqual(structure(coordinator.lastMarkdown).cards, [row.owner])
                XCTAssertFalse(coordinator.source)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, changed)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, named)
            }
        } }
    }
    @MainActor func testNativeListCardBodiesKeepTheirOwnersAndFollowMarkerWidthChanges() throws {
        let cases: [(String, String, Bool, Int)] = [
            ("- Parent\n  ```swift\n  old\n  ```\n- Sibling\n", "1. Parent\n   ```swift\n   new\n   ```\n- Sibling\n", false, 0),
            ("- Parent\n\n      old\n\n  Tail\n- Sibling\n", "1. Parent\n\n       new\n\n   Tail\n- Sibling\n", false, 0),
            ("- Parent\n  | A | B |\n  | --- | --- |\n  | old | __Other__ |\n- Sibling\n", "1. Parent\n   | A | B |\n   | --- | --- |\n   | new | __Other__ |\n- Sibling\n", true, 0),
            ("> - Parent\n>   > ```swift\n>   > old\n>   > ```\n> - Sibling\n", "> 1. Parent\n>    > ```swift\n>    > new\n>    > ```\n> - Sibling\n", false, 0),
            ("- Grand\n  - Parent\n    | A | B |\n    | --- | --- |\n    | old | __Other__ |\n- Sibling\n", "- Grand\n  1. Parent\n     | A | B |\n     | --- | --- |\n     | new | __Other__ |\n- Sibling\n", true, 1),
            ("- [x] Parent\n  ```swift\n  old\n  ```\n- Sibling\n", "1. Parent\n   ```swift\n   new\n   ```\n- Sibling\n", false, 0)
        ]
        func owners(_ source: String) -> [Int?] {
            var cards: [Int?] = [], ordinal = 0
            func walk(_ node: any Markup, owner: Int? = nil) {
                var owner = owner
                if node is ListItem { owner = ordinal; ordinal += 1 }
                if node is CodeBlock || node is Markdown.Table { cards.append(owner) }
                for child in node.children { walk(child, owner: owner) }
            }
            walk(Document(parsing: source)); return cards
        }
        for (template, numbered, table, owner) in cases { for ending in ["\n", "\r\n", "\r"] {
            let original = template.replacingOccurrences(of: "\n", with: ending), changed = original.replacingOccurrences(of: "old", with: "new")
            let expected = numbered.replacingOccurrences(of: "\n", with: ending)
            if template.hasPrefix("- [x] Parent") {
                try withEditor(changed) { view, coordinator in
                    XCTAssertTrue(view.string.hasPrefix("☑ Parent"), "The native item must retain its checked state")
                    let title = (view.string as NSString).range(of: "Parent"); view.setSelectedRange(title); view.insertText("Named", replacementRange: title)
                    let named = changed.replacingOccurrences(of: "Parent", with: "Named")
                    XCTAssertEqual(coordinator.lastMarkdown, named)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, changed)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, named)
                }
            }
            try withEditor(original) { view, coordinator in
                let target = (view.string as NSString).range(of: "old")
                guard target.location != NSNotFound else { XCTFail("The list card body must remain visible"); return }
                if table { guard MacRichTable.at(view.attributedString(), target.location) != nil else { XCTFail("The list-owned table needs native cells"); return } }
                else { guard MacRichCode.at(view.attributedString(), target.location) != nil else { XCTFail("The list-owned code needs a native card"); return } }
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), original)
                view.setSelectedRange(target); view.insertText("new", replacementRange: target)
                XCTAssertEqual(coordinator.lastMarkdown, changed); XCTAssertEqual(owners(coordinator.lastMarkdown), [owner])
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, changed)
                let parent = (view.string as NSString).range(of: "Parent"); view.setSelectedRange(parent)
                coordinator.action("ordered")
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(owners(coordinator.lastMarkdown), [owner])
                let card = (view.string as NSString).range(of: "new")
                let style = try XCTUnwrap(view.attributedString().attribute(.paragraphStyle, at: card.location, effectiveRange: nil) as? NSParagraphStyle)
                if table { XCTAssertEqual(style.textBlocks.count, 1, "Following a marker must retain the native cell layout") }
                else { XCTAssertTrue(NSFontManager.shared.traits(of: try XCTUnwrap(view.attributedString().attribute(.font, at: card.location, effectiveRange: nil) as? NSFont)).contains(.fixedPitchFontMask)) }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, changed); XCTAssertEqual(view.selectedRange(), parent)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                let after = (view.string as NSString).range(of: "new"); view.setSelectedRange(after); view.insertText("again", replacementRange: after)
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "new", with: "again")); XCTAssertEqual(owners(coordinator.lastMarkdown), [owner])
                let final = expected.replacingOccurrences(of: "new", with: "again")
                if table {
                    let last = (view.string as NSString).range(of: "Other")
                    view.setSelectedRange(NSRange(location: NSMaxRange(last), length: 0))
                    XCTAssertTrue(coordinator.moveTableCell(backward: false))
                    XCTAssertEqual(MacMarkdown.tables(in: coordinator.lastMarkdown).first?.table.rows.count, 3)
                    XCTAssertEqual(owners(coordinator.lastMarkdown), [owner])
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, final)
                }
                let title = (view.string as NSString).range(of: "Parent"); view.setSelectedRange(title)
                view.insertText("", replacementRange: title)
                XCTAssertEqual(owners(coordinator.lastMarkdown), [owner], "An emptied head must retain its card through autosave")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, final)
                view.setSelectedRange((view.string as NSString).range(of: "Parent"))
                coordinator.action("h1")
                XCTAssertEqual(owners(coordinator.lastMarkdown), [nil], "Closing an item must promote its card, preserving the model")
                let promoted = (view.string as NSString).range(of: "again")
                XCTAssertNotEqual(promoted.location, NSNotFound)
                if table { XCTAssertEqual((view.attributedString().attribute(.paragraphStyle, at: promoted.location, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.count, 1) }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, final)
            }
        } }
    }
    @MainActor func testListCardModelsFollowWholeItemMovesAndHeadRemoval() throws {
        let cases: [(String, String, String, [Int?], Int?)] = [
            ("- Previous\n- Parent\n{2}\n- Sibling\n", "indent", "- Previous\n  - Parent\n{4}\n- Sibling\n", [nil, 0, nil], 1),
            ("- Root\n  - Parent\n{4}\n  - Later\n- Sibling\n", "outdent", "- Root\n  - Later\n- Parent\n{2}\n- Sibling\n", [nil, 0, nil, nil], 2),
            ("- Root\n  - Parent\n{4}\n  - Later\n- Sibling\n", "delete", "- Root\n{2}\n  - Later\n- Sibling\n", [nil, 0, nil], 0),
            ("- Root\n  - Parent\n{4}\n  - Later\n- Sibling\n", "backspace", "- Root\n- Parent\n{2}\n  - Later\n- Sibling\n", [nil, nil, 1, nil], 1),
            ("- Root\n  > - Previous\n  > - Parent\n{q2}\n- Sibling\n", "indent", "- Root\n  > - Previous\n  >   - Parent\n{q4}\n- Sibling\n", [nil, 0, 1, nil], 2),
            ("- Root\n  > - Previous\n  >   - Parent\n{q4}\n  >   - Later\n- Sibling\n", "outdent", "- Root\n  > - Previous\n  >   - Later\n  > - Parent\n{q2}\n- Sibling\n", [nil, 0, 1, 0, nil], 3),
            ("- Root\n  > - Parent\n{q2}\n  > - Later\n- Sibling\n", "delete", "- Root\n{q0}\n  > - Later\n- Sibling\n", [nil, 0, nil], 0)
        ]
        func graph(_ source: String) -> (parents: [Int?], cards: [Int?]) {
            var parents: [Int?] = [], cards: [Int?] = []
            func walk(_ node: any Markup, parent: Int? = nil) {
                var owner = parent
                if node is ListItem { owner = parents.count; parents.append(parent) }
                if node is CodeBlock || node is Markdown.Table || node is ThematicBreak { cards.append(owner) }
                for child in node.children { walk(child, parent: owner) }
            }
            walk(Document(parsing: source)); return (parents, cards)
        }
        for kind in [0, 1, 2] { for ending in ["\n", "\r\n", "\r"] { for (before, action, after, parents, owner) in cases {
            let table = kind == 1, rule = kind == 2
            let card = rule ? "***" : table ? "| A |\n| :---: |\n| old |" : "```swift\nold\n```"
            func expanded(_ value: String) -> String {
                var result = value
                for width in [2, 4] { result = result.replacingOccurrences(of: "{\(width)}", with: card.components(separatedBy: "\n").map { String(repeating: " ", count: width) + $0 }.joined(separator: "\n")) }
                for (token, prefix) in [("{q0}", "  > "), ("{q2}", "  >   "), ("{q4}", "  >     ")] {
                    result = result.replacingOccurrences(of: token, with: card.components(separatedBy: "\n").map { prefix + $0 }.joined(separator: "\n"))
                }
                return result.replacingOccurrences(of: "\n", with: ending)
            }
            let source = expanded(before), expected = expanded(after)
            try withEditor(source) { view, coordinator in
                let parent = (view.string as NSString).range(of: "Parent"), row = (view.string as NSString).paragraphRange(for: parent)
                if action == "delete" { view.setSelectedRange(row) }
                else if action == "backspace" {
                    let block = try XCTUnwrap(MacMarkdown.nativeListItems(in: view.attributedString())?.first { $0.range == row })
                    view.setSelectedRange(NSRange(location: row.location + block.block.display.utf16.count, length: 0))
                } else { view.setSelectedRange(parent) }
                let selected = view.selectedRange()
                if action == "delete" { view.insertText("", replacementRange: selected) }
                else if action == "backspace" { view.deleteBackward(nil) }
                else { XCTAssertTrue(coordinator.indentList(backward: action == "outdent")) }
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(graph(coordinator.lastMarkdown).parents, parents); XCTAssertEqual(graph(coordinator.lastMarkdown).cards, [owner])
                let old = (view.string as NSString).range(of: rule ? "\u{FFFC}" : "old")
                guard old.location != NSNotFound else { XCTFail("Moving the item must retain its native card body"); return }
                if rule { XCTAssertTrue(view.attributedString().attribute(.attachment, at: old.location, effectiveRange: nil) is MacRuleAttachment) }
                else if table {
                    let style = try XCTUnwrap(view.attributedString().attribute(.paragraphStyle, at: old.location, effectiveRange: nil) as? NSParagraphStyle)
                    XCTAssertEqual(style.textBlocks.count, 1, "Owner transfer must keep the native table layout")
                    XCTAssertEqual(style.alignment, .center, "Owner transfer must keep the column alignment")
                } else { XCTAssertNotNil(MacRichCode.at(view.attributedString(), old.location)) }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } } }
    }
    @MainActor func testSelectionsAcrossListCardsRemoveOrTransferWholeModelsWithoutChangingTheirBodies() throws {
        let cases: [(String, String, String, Int, Int, String, [Int?], Int?)] = [
            ("- ## Heading\n{2}\n- Sibling\n", "Heading", "Sibling", 3, 3, "- ## Hea{X}ling\n", [nil], nil),
            ("- First\n- ## Heading\n{2}\n- Sibling\n", "First", "Heading", 2, 3, "- Fi{X}ding\n{2}\n- Sibling\n", [nil, nil], 0),
            ("- ## Heading\n- Parent\n{2}\n- Sibling\n", "Heading", "Parent", 3, 3, "- ## Hea{X}ent\n{2}\n- Sibling\n", [nil, nil], 0),
            ("- > Quote\n\n{2}\n- Sibling\n", "Quote", "Sibling", 3, 3, "- > Quo{X}ling\n", [nil], nil),
            ("- First\n- > Quote\n\n{2}\n- Sibling\n", "First", "Quote", 2, 3, "- Fi{X}te\n\n{2}\n- Sibling\n", [nil, nil], 0),
            ("- > Quote\n- Parent\n{2}\n- Sibling\n", "Quote", "Parent", 3, 3, "- > Quo{X}ent\n{gap}{2}\n- Sibling\n", [nil, nil], 0),
            ("- Parent\n{2}\n- Sibling\n", "Parent", "Sibling", 3, 3, "- Par{X}ling\n", [nil], nil),
            ("- First\n- Parent\n{2}\n- Sibling\n", "First", "Parent", 2, 3, "- Fi{X}ent\n{2}\n- Sibling\n", [nil, nil], 0),
            ("- Root\n  - First\n- Parent\n{2}\n- Sibling\n", "First", "Parent", 2, 3, "- Root\n  - Fi{X}ent\n{4}\n- Sibling\n", [nil, 0, nil], 1),
            ("Intro\n\n- Parent\n{2}\n- Sibling\n", "Intro", "Parent", 2, 3, "In{X}ent\n\n{0}\n\n- Sibling\n", [nil], nil),
            ("- Parent\n{2}\n\n  Tail\n- Sibling\n", "Parent", "Tail", 3, 2, "- Par{X}il\n- Sibling\n", [nil, nil], nil),
            ("> - Parent\n{q}\n\n- Sibling\n", "Parent", "Sibling", 3, 3, "> - Par{X}ling\n", [nil], nil),
            ("- First\n- Parent\n{inner}\n- Sibling\n", "First", "Parent", 2, 3, "- Fi{X}ent\n{inner}\n- Sibling\n", [nil, nil], 0),
            ("> - First\n\n- Parent\n{2}\n- Sibling\n", "First", "Parent", 2, 3, "> - Fi{X}ent\n{q}\n- Sibling\n", [nil, nil], 0),
            ("- First\n\n> - Parent\n{q}\n- Sibling\n", "First", "Parent", 2, 3, "- Fi{X}ent\n{2}\n- Sibling\n", [nil, nil], 0)
        ]
        for kind in [0, 1, 2] { for ending in ["\n", "\r\n", "\r"] { for replacement in ["", "X"] { for (before, from, through, a, b, after, parents, owner) in cases {
            let table = kind == 1, rule = kind == 2
            let body = rule ? "***" : table ? "| A |\n| :---: |\n| old |" : "```swift\nold\n```"
            func expanded(_ value: String) -> String {
                // A fence interrupts quote prose; a table needs a blank line
                // to avoid becoming a lazy continuation of that quote.
                var value = value.replacingOccurrences(of: "{X}", with: replacement).replacingOccurrences(of: "{gap}", with: table ? "\n" : "")
                for (token, prefix) in [("{0}", ""), ("{2}", "  "), ("{4}", "    "), ("{q}", ">   "), ("{inner}", "  > ")] {
                    value = value.replacingOccurrences(of: token, with: body.components(separatedBy: "\n").map { prefix + $0 }.joined(separator: "\n"))
                }
                return value.replacingOccurrences(of: "\n", with: ending)
            }
            let source = expanded(before), expected = expanded(after)
            var errors: [String] = []
            try withEditor(source, onPasteError: { errors.append($0) }) { view, coordinator in
                let raw = view.string as NSString, first = raw.range(of: from), last = raw.range(of: through)
                let selected = NSRange(location: first.location + a, length: last.location + b - first.location - a)
                view.setSelectedRange(selected); view.insertText(replacement, replacementRange: selected)
                XCTAssertTrue(errors.isEmpty, "\(before): \(errors)")
                XCTAssertEqual(coordinator.lastMarkdown, expected, "\(before), table=\(table), replacement=\(replacement)")
                var actual: [Int?] = [], cardOwners: [Int?] = []
                func walk(_ node: any Markup, parent: Int? = nil) {
                    var owner = parent
                    if node is ListItem { owner = actual.count; actual.append(parent) }
                    if node is CodeBlock || node is Markdown.Table || node is ThematicBreak { cardOwners.append(owner) }
                    for child in node.children { walk(child, parent: owner) }
                }
                walk(Document(parsing: coordinator.lastMarkdown)); XCTAssertEqual(actual, parents)
                XCTAssertEqual(cardOwners, after.contains("{0}") || owner != nil ? [owner] : [])
                if owner != nil || after.contains("{0}") {
                    let old = (view.string as NSString).range(of: rule ? "\u{FFFC}" : "old")
                    XCTAssertNotEqual(old.location, NSNotFound)
                    if old.location != NSNotFound {
                        if rule { XCTAssertTrue(view.attributedString().attribute(.attachment, at: old.location, effectiveRange: nil) is MacRuleAttachment) }
                        else if table {
                            let style = try XCTUnwrap(view.attributedString().attribute(.paragraphStyle, at: old.location, effectiveRange: nil) as? NSParagraphStyle)
                            XCTAssertEqual(style.textBlocks.count, 1); XCTAssertEqual(style.alignment, .center)
                        } else { XCTAssertNotNil(MacRichCode.at(view.attributedString(), old.location)) }
                    }
                }
                let caret = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                view.insertText("Z", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: String(from.prefix(a)) + replacement, with: String(from.prefix(a)) + replacement + "Z"))
            }
        } } } }
    }
    @MainActor func testPartialCodeSelectionsKeepSurvivingBodiesAndTheirNativeBlockBoundaries() throws {
        let cases: [(String, String, Int, String, Int, String, String, String, String, String, String, Int?)] = [
            ("- Parent\n{code}\n- Sibling\n", "Parent", 3, "abcdef", 3, "- Par{X}\n{kept}\n- Sibling\n", "abcdef", "def", "  ", "  ", "swift", 0),
            ("- Parent\n{code}\n- Sibling\n", "abcdef", 3, "Sibling", 3, "- Parent\n{kept}\n", "abcdef", "abc{X}ling", "  ", "  ", "swift", 0),
            ("> - Parent\n{code}\n> - Sibling\n", "Parent", 3, "abcdef", 3, "> - Par{X}\n{kept}\n> - Sibling\n", "abcdef", "def", ">   ", ">   ", "swift", 0),
            ("> - Parent\n{code}\n> - Sibling\n", "abcdef", 3, "Sibling", 3, "> - Parent\n{kept}\n", "abcdef", "abc{X}ling", ">   ", ">   ", "swift", 0),
            ("- First\n- Parent\n{code}\n- Sibling\n", "First", 2, "abcdef", 3, "- Fi{X}\n{kept}\n- Sibling\n", "abcdef", "def", "  ", "  ", "swift", 0),
            ("- Root\n  - First\n- Parent\n{code}\n- Sibling\n", "First", 2, "abcdef", 3, "- Root\n  - Fi{X}\n{kept}\n- Sibling\n", "abcdef", "def", "  ", "    ", "swift", 1),
            ("- Root\n  - Parent\n{code}\n- Sibling\n  - Child\n", "abcdef", 3, "Sibling", 3, "- Root\n  - Parent\n{kept}\n  - Child\n", "abcdef", "abc{X}ling", "    ", "    ", "swift", 1),
            ("- Parent\n{code}\n- Sibling\n", "Parent", 3, "abcdef", 3, "- Par{X}\n{kept}\n- Sibling\n", "before\nabcdef\nafter", "def\nafter", "  ", "  ", "swift", 0),
            ("- Parent\n{code}\n- Sibling\n", "abcdef", 3, "Sibling", 3, "- Parent\n{kept}\n", "😀 before\nabcdef\nafter", "😀 before\nabc{X}ling", "  ", "  ", "swift", 0),
            ("- Parent\n{code}\n- Sibling\n", "abcdef", 3, "Sibling", 3, "- Parent\n{kept}\n", "abcdef", "abc{X}ling", "  > ", "  > ", "swift", 0),
            ("Parent\n\n{code}\n\nSibling\n", "Parent", 3, "abcdef", 3, "Par{X}\n{kept}\n\nSibling\n", "abcdef", "def", "", "", "swift", nil),
            ("Parent\n\n{code}\n\nSibling\n", "abcdef", 3, "Sibling", 3, "Parent\n\n{kept}\n", "abcdef", "abc{X}ling", "", "", "swift", nil),
            ("- Parent\n\n      abcdef\n- Sibling\n", "Parent", 3, "abcdef", 3, "- Par{X}\n{kept}\n- Sibling\n", "abcdef", "def", "  ", "  ", "", 0),
            ("- Parent\n\n      abcdef\n- Sibling\n", "abcdef", 3, "Sibling", 3, "- Parent\n\n      abc{X}ling\n", "abcdef", "abc{X}ling", "  ", "  ", "", 0),
            ("- Parent\n{code}\n- Sibling\n", "abcdef", 0, "Sibling", 3, "- Parent\n{kept}\n", "abcdef", "{X}ling", "  ", "  ", "swift", 0),
            ("- Parent\n{code}\n- Sibling\n", "Parent", 3, "abcdef", 6, "- Par{X}\n{kept}\n- Sibling\n", "abcdef", "", "  ", "  ", "swift", 0),
            ("- Parent\n{code}\n- Sib![Caption](./image.png)\n", "abcdef", 3, "Sib", 3, "- Parent\n{kept}\n", "abcdef", "abc{X}![Caption](<./image.png>)", "  ", "  ", "swift", 0)
        ]
        for ending in ["\n", "\r\n", "\r"] { for replacement in ["", "X"] { for (before, from, a, through, b, after, originalBody, survivingBodyTemplate, sourcePrefix, targetPrefix, language, owner) in cases {
            let survivingBody = survivingBodyTemplate.replacingOccurrences(of: "{X}", with: replacement)
            func expanded(_ source: String, inserted: String = replacement) -> String {
                var source = source.replacingOccurrences(of: "{X}", with: inserted)
                for (token, body, prefix) in [("{code}", originalBody, sourcePrefix), ("{kept}", survivingBodyTemplate.replacingOccurrences(of: "{X}", with: inserted), targetPrefix)] {
                    source = source.replacingOccurrences(of: token, with: (["```" + language] + (body.isEmpty ? [] : body.components(separatedBy: "\n")) + ["```"]).map { prefix + $0 }.joined(separator: "\n"))
                }
                return source.replacingOccurrences(of: "\n", with: ending)
            }
            let source = expanded(before), expected = expanded(after)
            try withEditor(source) { view, coordinator in
                let raw = view.string as NSString, first = raw.range(of: from), last = raw.range(of: through)
                let selected = NSRange(location: first.location + a, length: last.location + b - first.location - a)
                view.setSelectedRange(selected); view.insertText(replacement, replacementRange: selected)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                var bodies: [String] = [], owners: [Int?] = [], count = 0
                func walk(_ node: any Markup, owner: Int? = nil) {
                    var owner = owner
                    if node is ListItem { owner = count; count += 1 }
                    if let code = node as? CodeBlock { bodies.append(code.code); owners.append(owner) }
                    for child in node.children { walk(child, owner: owner) }
                }
                walk(Document(parsing: coordinator.lastMarkdown))
                XCTAssertEqual(bodies, [survivingBody.isEmpty ? "" : survivingBody + "\n"]); XCTAssertEqual(owners, [owner])
                let body = (view.string as NSString).range(of: survivingBody.isEmpty ? "\u{200b}" : from != "abcdef" ? "def" : a == 0 ? "ling" : "abc")
                guard body.location != NSNotFound else { XCTFail("The unselected code body must survive"); return }
                var token = NSRange(); XCTAssertNotNil(view.attributedString().attribute(.macCode, at: body.location, longestEffectiveRange: &token, in: NSRange(location: 0, length: view.string.utf16.count)))
                XCTAssertEqual((view.string as NSString).paragraphRange(for: NSRange(location: token.location, length: 0)).location, token.location, "A surviving code token starts on its own native paragraph")
                let caret = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                view.insertText("Z", replacementRange: view.selectedRange())
                let typed = expanded(after, inserted: replacement + "Z")
                XCTAssertEqual(coordinator.lastMarkdown, typed)
            }
        } } }
        for ending in ["\n", "\r\n", "\r"] { for replacement in ["", "X"] {
            let source = "- Parent\n  ```swift\n  abcdef\n  ```\n- Sibling\n  ```swift\n  uvwxyz\n  ```\n- Other\n".replacingOccurrences(of: "\n", with: ending)
            let expected = "- Parent\n  ```swift\n  abc\(replacement)\n  ```\n  ```swift\n  xyz\n  ```\n- Other\n".replacingOccurrences(of: "\n", with: ending)
            try withEditor(source) { view, coordinator in
                let raw = view.string as NSString, a = raw.range(of: "abcdef"), b = raw.range(of: "uvwxyz")
                let selected = NSRange(location: a.location + 3, length: b.location - a.location)
                view.setSelectedRange(selected); view.insertText(replacement, replacementRange: selected)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                var bodies: [String] = [], owners: [Int?] = [], items = 0
                func collect(_ node: any Markup, owner: Int? = nil) {
                    var owner = owner
                    if node is ListItem { owner = items; items += 1 }
                    if let code = node as? CodeBlock { bodies.append(code.code); owners.append(owner) }
                    for child in node.children { collect(child, owner: owner) }
                }
                collect(Document(parsing: coordinator.lastMarkdown)); XCTAssertEqual(bodies, ["abc" + replacement + "\n", "xyz\n"]); XCTAssertEqual(owners, [0, 0]); XCTAssertEqual(items, 2)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                view.insertText("Z", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "abc" + replacement, with: "abc" + replacement + "Z"))
            }
        } }
    }
    @MainActor func testPartialTableSelectionsKeepTheGridAndSurvivingItemOwnership() throws {
        for quoted in [false, true] { for ending in ["\n", "\r\n", "\r"] { for replacement in ["", "X"] { for outgoing in [false, true] { for scope in ["same", "nested", "inner", "root", "header", "formatted", "image"] {
            if ["header", "formatted", "image"].contains(scope) && !outgoing { continue }
            let quote = quoted ? "> " : ""
            let head = scope == "root" ? "Parent\n\n" : scope == "nested" ? (outgoing ? "- Root\n  - Parent\n" : "- Root\n  - First\n- Parent\n") : "- Parent\n"
            let prefix = scope == "root" ? "" : scope == "nested" && outgoing ? "    " : scope == "inner" ? "  > " : "  "
            let tail = scope == "formatted" ? "- Sib**ling**\n" : scope == "image" ? "- Sib![Caption](./image.png)\n" : scope == "root" ? "\nSibling\n" : scope == "nested" && outgoing ? "- Sibling\n  - Child\n" : "- Sibling\n"
            let source = (head + ["| A | B |", "| :---: | ---: |", "| abcdef | _Keep_ |"].map { prefix + $0 }.joined(separator: "\n") + "\n" + tail).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map { quote + $0 }.joined(separator: ending) + ending
            try withEditor(source) { view, coordinator in
                let raw = view.string as NSString, first = raw.range(of: outgoing ? (scope == "header" ? "A" : "abcdef") : scope == "nested" ? "First" : "Parent"), last = raw.range(of: outgoing ? (scope == "image" ? "Sib" : "Sibling") : "abcdef"), offset = scope == "header" ? 0 : !outgoing && scope == "nested" ? 2 : 3
                let selected = NSRange(location: first.location + offset, length: last.location + 3 - first.location - offset)
                view.setSelectedRange(selected); view.insertText(replacement, replacementRange: selected)
                func content(_ source: String) -> (cells: [String], prose: [String], owners: [Int?], parents: [Int?]) {
                    var cells: [String] = [], prose: [String] = [], owners: [Int?] = [], parents: [Int?] = []
                    func text(_ node: any Markup) -> String { (node as? Markdown.Text)?.string ?? node.children.map(text).joined() }
                    func walk(_ node: any Markup, owner: Int? = nil, table: Bool = false) {
                        var owner = owner
                        if node is ListItem { parents.append(owner); owner = parents.count - 1 }
                        if node is Markdown.Table { owners.append(owner) }
                        if node is Markdown.Table.Cell { cells.append(text(node)) }
                        if !table, !(node is Markdown.Table), let value = node as? Markdown.Text { prose.append(value.string) }
                        for child in node.children { walk(child, owner: owner, table: table || node is Markdown.Table) }
                    }
                    walk(Document(parsing: source)); return (cells, prose, owners, parents)
                }
                let saved = coordinator.lastMarkdown, actual = content(saved), endingText = scope == "image" ? "Caption" : "ling"
                XCTAssertEqual(actual.cells, outgoing ? (scope == "header" ? [replacement + "ling", "", "", ""] : ["A", "B", "abc" + replacement + endingText, ""]) : ["", "", "def", "Keep"])
                let expectedProse = outgoing ? (scope == "nested" ? ["Root", "Parent", "Child"] : ["Parent"]) : (scope == "nested" ? ["Root", "Fi" + replacement, "Sibling"] : ["Par" + replacement, "Sibling"])
                let expectedParents: [Int?] = scope == "root" ? [] : scope == "nested" ? (outgoing ? [nil, 0, 0] : [nil, 0, nil]) : (outgoing ? [nil] : [nil, nil])
                if scope == "formatted" || scope == "image" {
                    var strong: [String] = [], images: [String] = []
                    func inspect(_ node: any Markup) {
                        if let node = node as? Strong { strong.append(node.plainText) }
                        if let node = node as? Markdown.Image { images.append(node.source ?? "") }
                        for child in node.children { inspect(child) }
                    }
                    inspect(Document(parsing: saved))
                    XCTAssertEqual(strong, scope == "formatted" ? ["ling"] : [])
                    XCTAssertEqual(images, scope == "image" ? ["./image.png"] : [])
                }
                XCTAssertEqual(actual.prose, expectedProse)
                XCTAssertEqual(actual.owners, [scope == "root" ? nil : scope == "nested" ? 1 : 0]); XCTAssertEqual(actual.parents, expectedParents)
                let word = (view.string as NSString).range(of: outgoing ? (scope == "header" ? "ling" : "abc") : "def")
                guard word.location != NSNotFound else { XCTFail("Unselected cell text must remain visible"); return }
                let cell = try XCTUnwrap(MacRichTable.at(view.attributedString(), word.location))
                var tableRange = NSRange(); _ = view.attributedString().attribute(.macTable, at: word.location, longestEffectiveRange: &tableRange, in: NSRange(location: 0, length: view.string.utf16.count))
                XCTAssertEqual((view.string as NSString).paragraphRange(for: NSRange(location: tableRange.location, length: 0)).location, tableRange.location)
                XCTAssertEqual(cell.table.layout.numberOfColumns, 2)
                let style = try XCTUnwrap(view.attributedString().attribute(.paragraphStyle, at: word.location, effectiveRange: nil) as? NSParagraphStyle)
                XCTAssertEqual(style.textBlocks.count, 1); XCTAssertEqual(style.alignment, .center)
                let caret = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved); XCTAssertEqual(view.selectedRange(), caret)
                view.insertText("Z", replacementRange: view.selectedRange())
                let typed = content(coordinator.lastMarkdown)
                XCTAssertEqual(typed.cells, outgoing ? (scope == "header" ? [replacement + "Zling", "", "", ""] : ["A", "B", "abc" + replacement + "Z" + endingText, ""]) : ["", "", "def", "Keep"])
                XCTAssertEqual(typed.prose, outgoing ? expectedProse : expectedProse.map { $0 == "Par" + replacement || $0 == "Fi" + replacement ? $0 + "Z" : $0 })
                if !outgoing {
                    let keep = (view.string as NSString).range(of: "Keep")
                    let font = try XCTUnwrap(view.attributedString().attribute(.font, at: keep.location, effectiveRange: nil) as? NSFont)
                    XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
                }
            }
        } } } } }
        for (firstTable, lastTable) in [(false, true), (true, false), (true, true)] { for quoted in [false, true] { for ending in ["\n", "\r\n", "\r"] { for replacement in ["", "X"] {
            let quote = quoted ? "> " : ""
            func card(_ table: Bool, body: String, other: String) -> String {
                (table ? ["| A | B |", "| :---: | ---: |", "| \(body) | \(other) |"] : ["```swift", body, "```"]).map { quote + "  " + $0 }.joined(separator: ending) + ending
            }
            let source = quote + "- Parent" + ending + card(firstTable, body: "abcdef", other: "Keep") + quote + "- Sibling" + ending + card(lastTable, body: "uvwxyz", other: "Tail") + quote + "- Other" + ending
            try withEditor(source) { view, coordinator in
                let raw = view.string as NSString, first = raw.range(of: "abcdef"), last = raw.range(of: "uvwxyz")
                let selected = NSRange(location: first.location + 3, length: last.location - first.location)
                view.setSelectedRange(selected); view.insertText(replacement, replacementRange: selected)
                func content(_ source: String) -> (codes: [String], cells: [String], owners: [Int?], parents: [Int?]) {
                    var codes: [String] = [], cells: [String] = [], owners: [Int?] = [], parents: [Int?] = []
                    func text(_ node: any Markup) -> String { (node as? Markdown.Text)?.string ?? node.children.map(text).joined() }
                    func walk(_ node: any Markup, owner: Int? = nil) {
                        var owner = owner
                        if node is ListItem { parents.append(owner); owner = parents.count - 1 }
                        if let code = node as? CodeBlock { codes.append(code.code); owners.append(owner) }
                        if node is Markdown.Table { owners.append(owner) }
                        if node is Markdown.Table.Cell { cells.append(text(node)) }
                        for child in node.children { walk(child, owner: owner) }
                    }
                    walk(Document(parsing: source)); return (codes, cells, owners, parents)
                }
                let saved = coordinator.lastMarkdown, graph = content(saved)
                XCTAssertEqual(graph.codes, (firstTable ? [] : ["abc" + replacement + "\n"]) + (lastTable ? [] : ["xyz\n"]))
                XCTAssertEqual(graph.cells, (firstTable ? ["A", "B", "abc" + replacement, ""] : []) + (lastTable ? ["", "", "xyz", "Tail"] : []))
                XCTAssertEqual(graph.owners, [0, 0]); XCTAssertEqual(graph.parents, [nil, nil])
                for (word, table) in [("abc", firstTable), ("xyz", lastTable)] {
                    let body = (view.string as NSString).range(of: word)
                    guard body.location != NSNotFound else { XCTFail("The unselected card body must survive"); return }
                    var range = NSRange(); XCTAssertNotNil(view.attributedString().attribute(table ? .macTable : .macCode, at: body.location, longestEffectiveRange: &range, in: NSRange(location: 0, length: view.string.utf16.count)))
                    XCTAssertEqual((view.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 0)).location, range.location)
                }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
                view.insertText("Z", replacementRange: view.selectedRange())
                let typed = content(coordinator.lastMarkdown)
                XCTAssertEqual(typed.codes, (firstTable ? [] : ["abc" + replacement + "Z\n"]) + (lastTable ? [] : ["xyz\n"]))
                XCTAssertEqual(typed.cells, (firstTable ? ["A", "B", "abc" + replacement + "Z", ""] : []) + (lastTable ? ["", "", "xyz", "Tail"] : []))
                XCTAssertEqual(typed.owners, graph.owners); XCTAssertEqual(typed.parents, graph.parents)
            }
        } } } }
    }
    @MainActor func testReturnAcrossPartialCardsKeepsTheReceivingRoleAndSingleUndo() throws {
        for table in [false, true] { for outgoing in [false, true] { for standalone in [false, true] { for ending in ["\n", "\r\n", "\r"] {
            let prefix = standalone ? "" : "  "
            let card = (table ? ["| A | B |", "| :---: | ---: |", "| abcdef | Keep |"] : ["```swift", "abcdef", "```"]).map { prefix + $0 }.joined(separator: "\n")
            let source = ((standalone ? "Parent\n\n" : "- Parent\n") + card + (standalone ? "\n\nSibling\n" : "\n- Sibling\n")).replacingOccurrences(of: "\n", with: ending)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                let raw = view.string as NSString, first = raw.range(of: outgoing ? "abcdef" : "Parent"), last = raw.range(of: outgoing ? "Sibling" : "abcdef")
                let selected = NSRange(location: first.location + 3, length: last.location - first.location)
                view.setSelectedRange(selected); XCTAssertEqual(view.selectedRange(), selected); view.insertNewline(nil)
                func inspect(_ source: String) -> (code: [String], cells: [String], owners: [Int?], parents: [Int?], prose: [String]) {
                    var codes: [String] = [], cells: [String] = [], owners: [Int?] = [], parents: [Int?] = [], prose: [String] = []
                    func text(_ node: any Markup) -> String { (node as? Markdown.Text)?.string ?? node.children.map(text).joined() }
                    func walk(_ node: any Markup, owner: Int? = nil, insideTable: Bool = false) {
                        var owner = owner
                        if node is ListItem { parents.append(owner); owner = parents.count - 1 }
                        if let code = node as? CodeBlock { codes.append(code.code); owners.append(owner) }
                        if node is Markdown.Table { owners.append(owner) }
                        if node is Markdown.Table.Cell { cells.append(text(node)) }
                        if !insideTable, let value = node as? Markdown.Text { prose.append(value.string) }
                        for child in node.children { walk(child, owner: owner, insideTable: insideTable || node is Markdown.Table) }
                    }
                    walk(Document(parsing: source)); return (codes, cells, owners, parents, prose)
                }
                let saved = coordinator.lastMarkdown, graph = inspect(saved)
                XCTAssertEqual(graph.code, table ? [] : [outgoing ? "abc\nling\n" : "def\n"])
                XCTAssertEqual(graph.cells, table ? (outgoing ? ["A", "B", "abcling", ""] : ["", "", "def", "Keep"]) : [])
                XCTAssertEqual(graph.owners, [standalone ? nil : outgoing ? 0 : 1])
                XCTAssertEqual(graph.parents, standalone ? [] : outgoing ? [nil] : [nil, nil, nil])
                XCTAssertEqual(graph.prose, outgoing ? ["Parent"] : ["Par", "Sibling"])
                let word = (view.string as NSString).range(of: outgoing ? "abc" : "def")
                guard word.location != NSNotFound else { XCTFail("The unselected card text must survive Return"); return }
                var cardRange = NSRange(); XCTAssertNotNil(view.attributedString().attribute(table ? .macTable : .macCode, at: word.location, longestEffectiveRange: &cardRange, in: NSRange(location: 0, length: view.string.utf16.count)))
                XCTAssertEqual((view.string as NSString).paragraphRange(for: NSRange(location: cardRange.location, length: 0)).location, cardRange.location)
                if outgoing, table {
                    let cell = try XCTUnwrap(MacRichTable.at(view.attributedString(), word.location))
                    var range = NSRange(); _ = view.attributedString().attribute(.macCell, at: word.location, longestEffectiveRange: &range, in: NSRange(location: 0, length: view.string.utf16.count))
                    XCTAssertEqual(MacRichTable.body(view.attributedString().attributedSubstring(from: range)).string, "abc\u{2028}ling")
                    XCTAssertEqual(cell.table.layout.numberOfColumns, 2)
                }
                let caret = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved); XCTAssertEqual(view.selectedRange(), caret)
                view.insertText("Z", replacementRange: view.selectedRange())
                let typed = inspect(coordinator.lastMarkdown)
                XCTAssertEqual(typed.code, table ? [] : [outgoing ? "abc\nZling\n" : "def\n"])
                XCTAssertEqual(typed.cells, table ? (outgoing ? ["A", "B", "abcZling", ""] : ["", "", "def", "Keep"]) : [])
                XCTAssertEqual(typed.prose, outgoing ? ["Parent"] : ["Par", "Z", "Sibling"])
                XCTAssertEqual(typed.owners, graph.owners); XCTAssertEqual(typed.parents, graph.parents)
            }
        } } } }
    }
    @MainActor func testListOwnedCardsKeepTheirSourceParentsThroughCodeAndTableSheets() throws {
        let cases: [(String, String, Bool)] = [
            ("- Parent\n  ```swift\n  old\n  ```\n  - Child\n- Sibling\n", "- Parent\n  ```swift\n  new\n  ```\n  - Child\n- Sibling\n", false),
            ("- [[zerus:parent-id|Parent 😀]]\n  ```swift\n  old\n  ```\n- Sibling\n", "- [[zerus:parent-id|Parent 😀]]\n  ```swift\n  new\n  ```\n- Sibling\n", false),
            ("> - [[zerus:parent-id|Parent 😀]]\n>   | A | B |\n>   | --- | --- |\n>   | old | Other |\n> - Sibling\n", "> - [[zerus:parent-id|Parent 😀]]\n>   | A | B |\n>   | --- | --- |\n>   | new | Other |\n> - Sibling\n", true),
            ("10. Parent\n\n        old\n\n    Tail\n11. Sibling\n", "10. Parent\n\n        new\n\n    Tail\n11. Sibling\n", false),
            ("- ```swift\n  old\n  ```\n- Sibling\n", "- ```swift\n  new\n  ```\n- Sibling\n", false),
            ("-     old\n- Sibling\n", "-     new\n- Sibling\n", false),
            ("- - ```swift\n    old\n    ```\n- Sibling\n", "- - ```swift\n    new\n    ```\n- Sibling\n", false),
            ("> - Parent\n>   > ```swift\n>   > old\n>   > ```\n>   - Child\n> - Sibling\n", "> - Parent\n>   > ```swift\n>   > new\n>   > ```\n>   - Child\n> - Sibling\n", false),
            ("> 10. ```swift\n>     old\n>     ```\n> 11. Sibling\n", "> 10. ```swift\n>     new\n>     ```\n> 11. Sibling\n", false),
            ("-\t```swift\n\told\n\t```\n- Sibling\n", "-   ```swift\n    new\n    ```\n- Sibling\n", false),
            ("- Parent\n  | A | B |\n  | --- | --- |\n  | old | Other |\n  - Child\n- Sibling\n", "- Parent\n  | A | B |\n  | --- | --- |\n  | new | Other |\n  - Child\n- Sibling\n", true),
            ("- | A | B |\n  | --- | --- |\n  | old | Other |\n- Sibling\n", "- | A | B |\n  | --- | --- |\n  | new | Other |\n- Sibling\n", true),
            ("> - Parent\n>   <!-- zerus-table-widths: 180,160 -->\n>   \n>   | A | B |\n>   | --- | --- |\n>   | old | Other |\n> - Sibling\n", "> - Parent\n>   <!-- zerus-table-widths: 180,160 -->\n>   \n>   | A | B |\n>   | --- | --- |\n>   | new | Other |\n> - Sibling\n", true),
            ("```swift\nfirst\n```\n\n- ```swift\n  old\n  ```\n\n```swift\nlast\n```\n", "```swift\nfirst\n```\n\n- ```swift\n  new\n  ```\n\n```swift\nlast\n```\n", false),
            ("- Parent\n  > - Nested child\n  >   ```swift\n  >   old\n  >   ```\n- Sibling\n", "- Parent\n  > - Nested child\n  >   ```swift\n  >   new\n  >   ```\n- Sibling\n", false),
            ("> 10. Parent\n>     > Quote\n>     >\n>     > 9. Child\n>     >    ```swift\n>     >    old\n>     >    ```\n> 11. Sibling\n", "> 10. Parent\n>     > Quote\n>     >\n>     > 9. Child\n>     >    ```swift\n>     >    new\n>     >    ```\n> 11. Sibling\n", false),
            ("- Parent\n  > - Nested child\n  >\n  >   | A | B |\n  >   | --- | --- |\n  >   | old | Other |\n- Sibling\n", "- Parent\n  > - Nested child\n  >\n  >   | A | B |\n  >   | --- | --- |\n  >   | new | Other |\n- Sibling\n", true),
            ("- > - Nested child\n  >   ```swift\n  >   old\n  >   ```\n- Sibling\n", "- > - Nested child\n  >   ```swift\n  >   new\n  >   ```\n- Sibling\n", false)
        ]
        func parents(_ source: String) -> [Int?] {
            var values: [Int?] = []
            func walk(_ node: any Markup, owner: Int? = nil) {
                var next = owner
                if node is ListItem { next = values.count; values.append(owner) }
                for child in node.children { walk(child, owner: next) }
            }
            walk(Document(parsing: source)); return values
        }
        for (template, changed, table) in cases { for ending in ["\n", "\r\n", "\r"] { for sourceMode in [true, false] {
            let original = template.replacingOccurrences(of: "\n", with: ending), expected = changed.replacingOccurrences(of: "\n", with: ending), scope = UUID()
            try withEditor(original, sourceMode: sourceMode, path: "Owned.md", scope: scope) { view, coordinator in
                let selected = (view.string as NSString).range(of: "old"); view.setSelectedRange(selected)
                let requestRange: NSRange, replacement: String
                if table {
                    guard let block = MacMarkdown.tables(in: original).first(where: { $0.table.rows.contains { $0.contains("old") } }) else { XCTFail("A list-owned table must appear in the source sheet menu"); return }
                    requestRange = block.range
                    var model = block.table; model.rows[1][0] = "new"; replacement = model.markdown
                    let unchanged = MacTableChange(request: .init(workspaceID: scope, path: "Owned.md", source: original, range: block.range, table: block.table), replacement: block.table.markdown)
                    NotificationCenter.default.post(name: .macEditorAction, object: unchanged)
                    do { try XCTUnwrap(unchanged.result).get() } catch { XCTFail("An unchanged owned table must save: \(error)"); return }
                    XCTAssertEqual(coordinator.lastMarkdown, original); XCTAssertEqual(view.selectedRange(), selected)
                    let command = MacTableChange(request: unchanged.request, replacement: replacement)
                    NotificationCenter.default.post(name: .macEditorAction, object: command)
                    do { try XCTUnwrap(command.result).get() } catch { XCTFail("The table sheet must retain its source parent: \(error)"); return }
                } else {
                    let blocks = MacCodeBlock.blocks(in: original)
                    if template.hasPrefix("```swift") { XCTAssertEqual(blocks.map { $0.code.body }, ["first", "old", "last"]) }
                    guard let block = blocks.first(where: { $0.code.body == "old" }) else { XCTFail("A list-owned code block must appear in the source sheet menu"); return }
                    requestRange = block.range
                    let request = MacCodeRequest(workspaceID: scope, path: "Owned.md", source: original, range: block.range, code: block.code)
                    let unchanged = MacCodeChange(request: request, replacement: request.replacing(body: "old", info: block.code.info))
                    NotificationCenter.default.post(name: .macEditorAction, object: unchanged)
                    do { try XCTUnwrap(unchanged.result).get() } catch { XCTFail("An unchanged owned code block must save: \(error)"); return }
                    XCTAssertEqual(coordinator.lastMarkdown, original); XCTAssertEqual(view.selectedRange(), selected)
                    replacement = request.replacing(body: "new", info: block.code.info)
                    let command = MacCodeChange(request: request, replacement: replacement)
                    NotificationCenter.default.post(name: .macEditorAction, object: command)
                    do { try XCTUnwrap(command.result).get() } catch { XCTFail("The code sheet must retain its source parent: \(error)"); return }
                }
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(coordinator.source, sourceMode)
                XCTAssertEqual(parents(coordinator.lastMarkdown), parents(original))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                if template.hasPrefix("- Parent\n  ") {
                    let beforeSelection = view.selectedRange(), beforeVisible = view.string, undoName = view.undoManager?.undoActionName
                    let injected = (table ? "| A | B |\n| --- | --- |\n| new | Other |\n- injected" : "```swift\nnew\n```\n- injected").replacingOccurrences(of: "\n", with: ending)
                    let rejection: Result<Void, Error>?
                    if table {
                        let block = try XCTUnwrap(MacMarkdown.tables(in: expected).first)
                        let command = MacTableChange(request: .init(workspaceID: scope, path: "Owned.md", source: expected, range: block.range, table: block.table), replacement: injected)
                        NotificationCenter.default.post(name: .macEditorAction, object: command); rejection = command.result
                    } else {
                        let block = try XCTUnwrap(MacCodeBlock.blocks(in: expected).first { $0.code.body == "new" })
                        let command = MacCodeChange(request: .init(workspaceID: scope, path: "Owned.md", source: expected, range: block.range, code: block.code), replacement: injected)
                        NotificationCenter.default.post(name: .macEditorAction, object: command); rejection = command.result
                    }
                    XCTAssertThrowsError(try XCTUnwrap(rejection).get()) { XCTAssertTrue($0.localizedDescription.contains("surrounding list or quote")) }
                    XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.string, beforeVisible); XCTAssertEqual(view.selectedRange(), beforeSelection)
                    XCTAssertEqual(view.undoManager?.undoActionName, undoName)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                }
                if table {
                    let stale = MacTableChange(request: .init(workspaceID: scope, path: "Owned.md", source: original, range: requestRange, table: .empty()), replacement: replacement)
                    NotificationCenter.default.post(name: .macEditorAction, object: stale)
                    XCTAssertThrowsError(try XCTUnwrap(stale.result).get()) { XCTAssertTrue($0.localizedDescription.contains("note changed")) }
                } else {
                    let stale = MacCodeChange(request: .init(workspaceID: scope, path: "Owned.md", source: original, range: requestRange, code: nil), replacement: replacement)
                    NotificationCenter.default.post(name: .macEditorAction, object: stale)
                    XCTAssertThrowsError(try XCTUnwrap(stale.result).get()) { XCTAssertTrue($0.localizedDescription.contains("note changed")) }
                }
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                if !sourceMode, table, template.hasPrefix("- Parent\n  |") {
                    let block = try XCTUnwrap(MacMarkdown.tables(in: expected).first)
                    var model = block.table; model.rows[1][0] = "<div>raw</div>"
                    let command = MacTableChange(request: .init(workspaceID: scope, path: "Owned.md", source: expected, range: block.range, table: block.table), replacement: model.markdown)
                    NotificationCenter.default.post(name: .macEditorAction, object: command)
                    try XCTUnwrap(command.result).get()
                    XCTAssertFalse(coordinator.source, "Rich text is the default; Source is only an explicit choice")
                    XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "| new | Other |", with: "| <div>raw</div> | Other |"))
                    coordinator.action("undo"); XCTAssertFalse(coordinator.source); XCTAssertEqual(coordinator.lastMarkdown, expected)
                }
            }
        } } }
    }
    @MainActor func testQuotedCodeAndTablesKeepTheirContainersThroughEditingAndSheets() throws {
        for (inner, role) in [
            ("~~~swift extra\nlet old = 1\nlet other = 2\n~~~", "code"),
            ("    let old = 1\n    let other = 2", "indented"),
            ("<!-- zerus-table-widths: 180,160 -->\n\n| A | B |\n| --- | --- |\n| old | Other |", "table")
        ] { for quotes in ["> ", "> > ", ">> "] { for ending in ["\n", "\r\n", "\r"] {
            func quoted(_ value: String) -> String { value.components(separatedBy: "\n").map { quotes + $0 }.joined(separator: ending) }
            let card = quoted(inner), source = "# Outside" + ending + ending + quotes + "Before" + ending + quotes + ending + card + ending + quotes + ending + quotes + "After" + ending + ending + "Outside" + ending
            XCTAssertFalse(MacMarkdown.requiresSource(source), "Quote-owned \(role) should have a native editor")
            let scope = UUID()
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, path: "Note.md", onChange: { _ in }, onLink: { _ in }, commandScope: scope)) { view, coordinator, _ in
                let target = (view.string as NSString).range(of: "old")
                guard target.location != NSNotFound else { XCTFail("The quote-owned \(role) body must remain visible"); return }
                if role == "table" { XCTAssertNotNil(MacRichTable.at(view.attributedString(), target.location)) }
                else { XCTAssertNotNil(MacRichCode.at(view.attributedString(), target.location)) }
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                view.setSelectedRange(target); view.insertText("new", replacementRange: target)
                let expected = source.replacingOccurrences(of: "old", with: "new")
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertFalse(coordinator.source)
                func cards(_ node: any Markup, depth: Int = 0) -> [Int] {
                    let depth = depth + (node is BlockQuote ? 1 : 0)
                    if node is CodeBlock || node is Markdown.Table { return [depth] }
                    return node.children.flatMap { cards($0, depth: depth) }
                }
                XCTAssertEqual(cards(Document(parsing: coordinator.lastMarkdown)), [quotes.filter { $0 == ">" }.count])
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), target)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo")
                let range = (source as NSString).range(of: card)
                let replacement = inner.replacingOccurrences(of: "old", with: "sheet").replacingOccurrences(of: "\n", with: ending)
                let result: Result<Void, Error>?
                if role == "table" {
                    let table = try XCTUnwrap(MarkdownTable.blocks(in: inner).first?.table)
                    let command = MacTableChange(request: .init(workspaceID: scope, path: "Note.md", source: source, range: range, table: table), replacement: replacement)
                    NotificationCenter.default.post(name: .macEditorAction, object: command); result = command.result
                } else {
                    let code = role == "code" ? try XCTUnwrap(FencedCode.blocks(in: inner).first?.code) : try XCTUnwrap(MacIndentedCode.blocks(in: inner).first?.code)
                    let command = MacCodeChange(request: .init(workspaceID: scope, path: "Note.md", source: source, range: range, code: code), replacement: replacement)
                    NotificationCenter.default.post(name: .macEditorAction, object: command); result = command.result
                }
                do { try XCTUnwrap(result).get() }
                catch { XCTFail("The \(role) sheet must keep its quote: \(error)"); return }
                let saved = source.replacingOccurrences(of: "old", with: "sheet")
                XCTAssertEqual(coordinator.lastMarkdown, saved); XCTAssertEqual(cards(Document(parsing: saved)), [quotes.filter { $0 == ">" }.count])
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
                if role == "table" {
                    let last = (view.string as NSString).range(of: "Other")
                    view.setSelectedRange(NSRange(location: last.location, length: 0)); XCTAssertTrue(coordinator.moveTableCell(backward: false))
                    view.insertText("Added", replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, saved.replacingOccurrences(of: card.replacingOccurrences(of: "old", with: "sheet"), with: quoted(inner.replacingOccurrences(of: "old", with: "sheet")) + ending + quotes + "| Added |  |"))
                }
            }
        } } }
    }
    @MainActor func testQuotedCardEdgesRetainLogicalBodiesAndContinuationDepth() throws {
        for ending in ["\n", "\r\n", "\r"] { for (template, body) in [
            (">\t```\n>\told\n>\t```", " old"),
            (">   ~~~swift\n>   old\n>   ~~~", "old"),
            (">>> ```\n>>> old\n>>> ```", "old"),
            (">     old", "old")
        ] {
            let source = template.replacingOccurrences(of: "\n", with: ending)
            XCTAssertFalse(MacMarkdown.requiresSource(source))
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                let target = (view.string as NSString).range(of: body)
                guard target.location != NSNotFound else { XCTFail("The logical quoted code body must remain visible"); return }
                XCTAssertEqual(view.string.trimmingCharacters(in: .newlines), body)
                view.setSelectedRange(target); view.insertText("new", replacementRange: target)
                func codes(_ node: any Markup) -> [String] { (node as? CodeBlock).map { [$0.code] } ?? node.children.flatMap(codes) }
                XCTAssertEqual(codes(Document(parsing: coordinator.lastMarkdown)), ["new\n"])
                XCTAssertEqual(MacMarkdown.render(coordinator.lastMarkdown).string.trimmingCharacters(in: .newlines), "new")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            }
        } }
        for ending in ["\n", "\r\n", "\r"] {
            let source = "> Before\n> | A | B |\n> | --- | --- |\n> | old | Other |\n>\n> After\n".replacingOccurrences(of: "\n", with: ending)
            XCTAssertFalse(MacMarkdown.requiresSource(source))
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                let target = (view.string as NSString).range(of: "old")
                guard target.location != NSNotFound else { XCTFail("An interrupting quote-table header must not consume the preceding paragraph"); return }
                XCTAssertNotNil(MacRichTable.at(view.attributedString(), target.location))
                XCTAssertTrue(view.string.hasPrefix("Before\n")); view.setSelectedRange(target); view.insertText("new", replacementRange: target)
                XCTAssertEqual(coordinator.lastMarkdown, source.replacingOccurrences(of: "old", with: "new"))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            }
        }
        for ending in ["\n", "\r\n", "\r"] { for kind in ["code", "indented", "table"] {
            let table = kind == "table"
            let source = (table ? "> | A |\n> | --- |\n> | old |" : kind == "indented" ? "> Before\n>\n>     old" : "> ```swift\n> old\n> ```").replacingOccurrences(of: "\n", with: ending)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                let target = (view.string as NSString).range(of: "old")
                guard target.location != NSNotFound else { XCTFail("The EOF quoted card must remain editable"); return }
                view.setSelectedRange(NSRange(location: target.location, length: 0)); XCTAssertTrue(coordinator.exitCode())
                view.insertText("After", replacementRange: view.selectedRange())
                let expected = source + ending + (table ? "> " + ending : "") + "> After"
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            }
        } }
    }
    @MainActor func testContinueBetweenCardsAndFollowingItemsCreatesProseInTheReceivingContainer() throws {
        for table in [false, true] { for following in ["sibling", "child", "code", "table"] { for quote in ["", "> "] { for ending in ["\n", "\r\n", "\r"] { for list in [false, true] {
            if !list, following == "sibling" || following == "child" { continue }
            let indent = list ? "  " : ""
            let card = table ? ["| A |", "| --- |", "| old |"] : ["```swift", "old", "```"]
            let next = following == "code" ? ["```swift", "second", "```"] : following == "table" ? ["| B |", "| --- |", "| second |"] : following == "child" ? ["  - Child"] : []
            let source = ([list ? "- Parent" : "Parent"] + card.map { indent + $0 } + (table && following == "table" ? [""] : []) + next.map { $0 == "  - Child" ? $0 : indent + $0 } + (!list && following == "table" ? [""] : []) + [list ? "- Sibling" : "Sibling"]).map { quote + $0 }.joined(separator: ending) + ending
            XCTAssertFalse(MacMarkdown.requiresSource(source))
            try withEditor(source) { view, coordinator in
                let old = (view.string as NSString).range(of: "old")
                guard old.location != NSNotFound else { XCTFail("The first card must remain editable"); return }
                let selection = NSRange(location: old.location, length: 0)
                view.setSelectedRange(selection); XCTAssertTrue(coordinator.exitCode())
                let prepared = coordinator.lastMarkdown
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                view.insertText("After", replacementRange: view.selectedRange())
                let saved = coordinator.lastMarkdown
                var parents: [Int?] = [], after: [Int?] = [], siblings: [Int?] = [], codes: [String] = [], cells: [String] = []
                func walk(_ node: any Markup, owner: Int? = nil) {
                    var owner = owner
                    if node is ListItem { let parent = owner; owner = parents.count; parents.append(parent) }
                    if let text = node as? Markdown.Text, text.string == "After" { after.append(owner) }
                    if let text = node as? Markdown.Text, text.string == "Sibling" { siblings.append(owner) }
                    if let code = node as? CodeBlock { codes.append(code.code) }
                    if let cell = node as? Markdown.Table.Cell { cells.append(cell.plainText) }
                    for child in node.children { walk(child, owner: owner) }
                }
                let document = Document(parsing: saved)
                walk(document)
                if !quote.isEmpty { XCTAssertEqual(document.childCount, 1); XCTAssertTrue(document.child(at: 0) is BlockQuote) }
                XCTAssertEqual(parents, list ? (following == "child" ? [nil, 0, nil] : [nil, nil]) : [])
                XCTAssertEqual(after, [list ? 0 : nil], "Continue must create prose in the first card's container")
                XCTAssertEqual(siblings, [list ? (following == "child" ? 2 : 1) : nil])
                XCTAssertEqual(codes, (table ? [] : ["old\n"]) + (following == "code" ? ["second\n"] : []))
                XCTAssertEqual(cells, (table ? ["A", "old"] : []) + (following == "table" ? ["B", "second"] : []))
                let caret = view.selectedRange()
                XCTAssertNil(MacRichCode.at(view.attributedString(), max(0, caret.location - 1)))
                XCTAssertNil(MacRichTable.at(view.attributedString(), max(0, caret.location - 1)))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, prepared)
                if prepared != source { coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selection); coordinator.action("redo") }
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved); XCTAssertEqual(view.selectedRange(), caret)
            }
        } } } } }
        for table in [false, true] { for list in [false, true] {
            let indent = list ? "  " : ""
            let card = table ? ["| A |", "| --- |", "| old |"] : ["```swift", "old", "```"]
            let source = ([list ? "- Parent" : "Parent"] + card.map { indent + $0 } + ["", list ? "- Sibling" : "Sibling"]).joined(separator: "\n") + "\n"
            var published: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { published.append($0) }, onLink: { _ in })) { view, coordinator, _ in
                let old = (view.string as NSString).range(of: "old")
                guard old.location != NSNotFound else { XCTFail("Composition requires the native card body"); return }
                view.setSelectedRange(NSRange(location: old.location, length: 0))
                view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.selectedRange())
                let marked = view.markedRange(), selection = view.selectedRange(), visible = view.string
                XCTAssertTrue(view.hasMarkedText()); XCTAssertTrue(published.isEmpty)
                let continued = coordinator.exitCode()
                XCTAssertFalse(continued, "Continue must leave unfinished input under AppKit's control")
                guard !continued else { return }
                XCTAssertTrue(view.hasMarkedText()); XCTAssertEqual(view.markedRange(), marked)
                XCTAssertEqual(view.string, visible); XCTAssertEqual(view.selectedRange(), selection)
                XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertTrue(published.isEmpty)
                view.insertText("é", replacementRange: view.markedRange())
                let committed = source.replacingOccurrences(of: "old", with: "éold")
                XCTAssertFalse(view.hasMarkedText()); XCTAssertEqual(coordinator.lastMarkdown, committed)
                XCTAssertEqual(published.last, committed)
            }
        } }
    }
    @MainActor func testContinuingAfterListCardsKeepsTheNewParagraphWithItsItem() throws {
        let cases: [(source: String, closed: String?, after: String, ordered: String, owner: Int)] = [
            ("- Parent\n  ```swift\n  old\n  ```", nil, "- Parent\n  ```swift\n  old\n  ```\n  After", "1. Parent\n   ```swift\n   old\n   ```\n   After", 0),
            ("- ```swift\n  old\n  ```", nil, "- ```swift\n  old\n  ```\n  After", "1. ```swift\n   old\n   ```\n   After", 0),
            ("- ```swift\n  old", "- ```swift\n  old\n  ```", "- ```swift\n  old\n  ```\n  After", "1. ```swift\n   old\n   ```\n   After", 0),
            ("> - Parent\n>   ```swift\n>   old\n>   ```", nil, "> - Parent\n>   ```swift\n>   old\n>   ```\n>   After", "> 1. Parent\n>    ```swift\n>    old\n>    ```\n>    After", 0),
            ("- Parent\n  > ```swift\n  > old\n  > ```", nil, "- Parent\n  > ```swift\n  > old\n  > ```\n  > After", "1. Parent\n   > ```swift\n   > old\n   > ```\n   > After", 0),
            ("- Parent\n  | A |\n  | --- |\n  | old |", nil, "- Parent\n  | A |\n  | --- |\n  | old |\n\n  After", "1. Parent\n   | A |\n   | --- |\n   | old |\n\n   After", 0),
            ("- | A |\n  | --- |\n  | old |", nil, "- | A |\n  | --- |\n  | old |\n\n  After", "1. | A |\n   | --- |\n   | old |\n\n   After", 0),
            ("- Parent\n  > | A |\n  > | --- |\n  > | old |", nil, "- Parent\n  > | A |\n  > | --- |\n  > | old |\n  > \n  > After", "1. Parent\n   > | A |\n   > | --- |\n   > | old |\n   > \n   > After", 0),
            ("- Root\n  > - Parent\n  >   ```swift\n  >   old\n  >   ```", nil, "- Root\n  > - Parent\n  >   ```swift\n  >   old\n  >   ```\n  >   After", "1. Root\n   > - Parent\n   >   ```swift\n   >   old\n   >   ```\n   >   After", 1),
            ("- Root\n  > - Parent\n  >   | A |\n  >   | --- |\n  >   | old |", nil, "- Root\n  > - Parent\n  >   | A |\n  >   | --- |\n  >   | old |\n  > \n  >   After", "1. Root\n   > - Parent\n   >   | A |\n   >   | --- |\n   >   | old |\n   > \n   >   After", 1),
            ("10. Root\n    > - Parent\n    >   > | A |\n    >   > | --- |\n    >   > | old |", nil, "10. Root\n    > - Parent\n    >   > | A |\n    >   > | --- |\n    >   > | old |\n    >   > \n    >   > After", "1. Root\n   > - Parent\n   >   > | A |\n   >   > | --- |\n   >   > | old |\n   >   > \n   >   > After", 1)
        ]
        func owners(_ source: String) -> (cards: [Int?], after: [Int?]) {
            var cards: [Int?] = [], after: [Int?] = [], count = 0
            func collect(_ node: any Markup, owner: Int? = nil) {
                var owner = owner
                if node is ListItem { owner = count; count += 1 }
                if node is CodeBlock || node is Markdown.Table { cards.append(owner) }
                if (node as? Markdown.Text)?.string == "After" { after.append(owner) }
                for child in node.children { collect(child, owner: owner) }
            }
            collect(Document(parsing: source)); return (cards, after)
        }
        for row in cases { for ending in ["\n", "\r\n", "\r"] {
            let source = row.source.replacingOccurrences(of: "\n", with: ending), after = row.after.replacingOccurrences(of: "\n", with: ending)
            let closed = row.closed?.replacingOccurrences(of: "\n", with: ending)
            try withEditor(source) { view, coordinator in
                let old = (view.string as NSString).range(of: "old")
                guard old.location != NSNotFound else { XCTFail("Continue requires the native card body"); return }
                view.setSelectedRange(NSRange(location: old.location, length: 0)); XCTAssertTrue(coordinator.exitCode())
                XCTAssertEqual(coordinator.lastMarkdown, closed ?? source)
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                view.insertText("After", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, after)
                XCTAssertEqual(owners(coordinator.lastMarkdown).cards, [row.owner]); XCTAssertEqual(owners(coordinator.lastMarkdown).after, [row.owner])
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, closed ?? source)
                if closed != nil { coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); coordinator.action("redo") }
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, after)
                try withEditor(coordinator.lastMarkdown) { reopened, controller in
                    let head = try XCTUnwrap(MacMarkdown.nativeListItems(in: reopened.attributedString())?.first)
                    reopened.setSelectedRange(NSRange(location: head.range.location + head.block.display.utf16.count, length: 0)); controller.action("ordered")
                    XCTAssertEqual(controller.lastMarkdown, row.ordered.replacingOccurrences(of: "\n", with: ending))
                    XCTAssertEqual(owners(controller.lastMarkdown).cards, [row.owner]); XCTAssertEqual(owners(controller.lastMarkdown).after, [row.owner])
                }
            }
        } }
    }
    @MainActor func testContinuingAfterUnclosedCodeClosesItsFenceWithoutChangingItsBody() throws {
        for quote in ["", "> "] { for ending in ["\n", "\r\n", "\r"] { for terminated in [false, true] {
            let source = quote + "```swift" + ending + quote + "old" + (terminated ? ending : "")
            let closed = quote + "```swift" + ending + quote + "old" + ending + quote + "```" + (terminated ? ending : "")
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                let body = (view.string as NSString).range(of: "old")
                guard body.location != NSNotFound else { XCTFail("The unclosed code body must remain editable"); return }
                view.setSelectedRange(NSRange(location: body.location, length: 0)); XCTAssertTrue(coordinator.exitCode())
                XCTAssertEqual(coordinator.lastMarkdown, closed)
                // Separate the command and subsequent typing as real input events.
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                view.insertText("After", replacementRange: view.selectedRange())
                let expected = quote + "```swift" + ending + quote + "old" + ending + quote + "```" + ending + quote + "After"
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                var bodies: [String] = []
                func collect(_ node: any Markup) { if let code = node as? CodeBlock { bodies.append(code.code) }; for child in node.children { collect(child) } }
                collect(Document(parsing: coordinator.lastMarkdown)); XCTAssertEqual(bodies, ["old\n"])
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, closed)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } } }
    }
    @MainActor func testRichSourceLineEndingsPreserveEveryBlockThroughEditingAndUndo() throws {
        for (template, changed, role) in [
            ("Before α\nsecond **old** line\n\nAfter\n", "Before α\nsecond **new** line\n\nAfter\n", "prose"),
            ("Title\n===\nAfter old\n\n***\nTail\n", "Title\n===\nAfter new\n\n***\nTail\n", "heading"),
            ("- Parent\n  - Child\n\n  Tail old\n- Sibling\n", "- Parent\n  - Child\n\n  Tail new\n- Sibling\n", "list"),
            ("> Before old  \n> after\n", "> Before new  \n> after\n", "quote"),
            ("# Before\n\n~~~swift extra\nlet old = 1\nlet value = 2\n~~~\n\nAfter\n", "# Before\n\n~~~swift extra\nlet new = 1\nlet value = 2\n~~~\n\nAfter\n", "code"),
            ("# Before\n\n    let old = 1\n    let value = 2\n\nAfter\n", "# Before\n\n    let new = 1\n    let value = 2\n\nAfter\n", "code"),
            ("# Before\n\n| A | B |\n| --- | --- |\n| old | C |\n\nAfter\n", "# Before\n\n| A | B |\n| --- | --- |\n| new | C |\n\nAfter\n", "table"),
            ("Before\n\n---\n\nAfter old\n", "Before\n\n---\n\nAfter new\n", "rule")
        ] { for ending in ["\n", "\r\n", "\r"] { for terminated in [true, false] {
            let source = (terminated ? template : String(template.dropLast())).replacingOccurrences(of: "\n", with: ending)
            let expected = (terminated ? changed : String(changed.dropLast())).replacingOccurrences(of: "\n", with: ending)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source, role)
                let target = (view.string as NSString).range(of: "old")
                guard target.location != NSNotFound else { XCTFail("The editable \(role) body must remain visible for \(ending.debugDescription)"); return }
                if template.contains("After") { XCTAssertTrue(view.string.contains("After"), "A block cannot consume the following paragraph") }
                if role == "code" { XCTAssertNotNil(MacRichCode.at(view.attributedString(), target.location)) }
                if role == "table" { XCTAssertNotNil(MacRichTable.at(view.attributedString(), target.location)) }
                view.setSelectedRange(target); view.insertText("new", replacementRange: target)
                XCTAssertEqual(coordinator.lastMarkdown, expected, "\(role), \(ending.debugDescription)")
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
                if role == "list" {
                    var parents: [Int?] = []
                    func collect(_ node: any Markup, owner: Int? = nil) {
                        var next = owner
                        if node is ListItem { next = parents.count; parents.append(owner) }
                        for child in node.children { collect(child, owner: next) }
                    }
                    collect(Document(parsing: coordinator.lastMarkdown)); XCTAssertEqual(parents, [nil, 0, nil])
                }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), target)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } } }
        let mixed = "# Before\r\n\rParagraph old\r\n\r***\n\rAfter\r"
        try withHostedEditor(MacRichEditor(markdown: mixed, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), mixed)
            let target = (view.string as NSString).range(of: "old")
            guard target.location != NSNotFound else { XCTFail("Mixed-ending prose must stay visible"); return }
            view.setSelectedRange(target); view.insertText("new", replacementRange: target)
            XCTAssertEqual(coordinator.lastMarkdown, mixed.replacingOccurrences(of: "old", with: "new"))
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, mixed)
        }
        for (source, target, expected) in [
            ("9. Parent\r   - Child\r10. Sibling\r", "Parent", "9. Parent\r10. New\r    - Child\r10. Sibling\r"),
            ("# Before\r\r```swift\rlet a = 1\r```\r", "let a = 1", "# Before\r\r```swift\rlet a = 1\rNew\r```\r"),
            ("# Before\r\rLast", "Last", "# Before\r\rLast\rNew")
        ] {
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                let body = (view.string as NSString).range(of: target)
                guard body.location != NSNotFound else { XCTFail("A CR body must remain editable"); return }
                view.setSelectedRange(NSRange(location: NSMaxRange(body), length: 0))
                view.insertNewline(nil); view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        }
    }
    @MainActor func testOrderedListPresentationKeepsOriginalSourceUntilEditingAndRestoresItWithUndo() throws {
        let cases: [(String, String, String, String)] = [
            ("1. First\n1. Second\n1. Last\n", "1. First\n2. Second\n3. Last\n", "1. First\n1. Second!\n1. Last\n", "1. First\n1. Second\n3. New\n1. Last\n"),
            ("9. First\n1. Second\n   - Child\n1. Last\n", "9. First\n10. Second\n• Child\n11. Last\n", "9. First\n1. Second!\n   - Child\n1. Last\n", "9. First\n1. Second\n11. New\n    - Child\n1. Last\n")
        ]
        for (body, visible, edited, split) in cases { for quotes in ["", "> "] { for ending in ["\n", "\r\n"] {
            func spelled(_ text: String) -> String { text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map { quotes + $0 + ending }.joined() }
            let source = spelled(body)
            try withEditor(source) { view, coordinator in
                XCTAssertEqual(view.string, visible)
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source, "Opening Rich mode must not rewrite source marker spelling")
                let word = (view.string as NSString).range(of: "Second")
                guard word.location != NSNotFound else { XCTFail("The item must stay visible"); return }
                let caret = NSRange(location: NSMaxRange(word), length: 0)
                view.setSelectedRange(caret); view.insertText("!", replacementRange: caret)
                XCTAssertEqual(coordinator.lastMarkdown, spelled(edited))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.string, visible)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, spelled(edited))
                coordinator.action("undo"); view.setSelectedRange(caret); view.insertNewline(nil)
                let receiving = view.selectedRange()
                view.breakUndoCoalescing(); if let undo = view.undoManager, undo.groupingLevel == 1 { undo.endUndoGrouping(); undo.beginUndoGrouping() }
                view.insertText("New", replacementRange: receiving)
                XCTAssertEqual(coordinator.lastMarkdown, spelled(split))
                let saved = coordinator.lastMarkdown
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(saved)), saved)
                coordinator.action("undo"); coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.string, visible)
            }
        } } }
        try withEditor("1. [ ] First\n1. [ ] Second\n") { view, coordinator in
            XCTAssertEqual(view.string, "1. ☐ First\n2. ☐ Second\n")
            let second = (view.string as NSString).range(of: "Second")
            guard second.location != NSNotFound else { return XCTFail("The second task remains visible") }
            coordinator.toggleChecklist(at: second.location)
            XCTAssertEqual(coordinator.lastMarkdown, "1. [ ] First\n1. [x] Second\n", "Checking a task preserves its original number spelling")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "1. [ ] First\n1. [ ] Second\n")
        }
        let mixed = "1. First\n1. Second\n\n```swift\nold\n```\n"
        let rich = NSMutableAttributedString(attributedString: MacMarkdown.render(mixed))
        rich.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: rich.length))
        XCTAssertEqual(MacMarkdown.markdown(rich), mixed, "Presentation colours do not replace original source numbering")
        let body = (rich.string as NSString).range(of: "old")
        guard body.location != NSNotFound, let token = MacRichCode.at(rich, body.location) else { return XCTFail("The code model must remain native") }
        var codeRange = NSRange()
        _ = rich.attribute(.macCode, at: body.location, longestEffectiveRange: &codeRange, in: NSRange(location: 0, length: rich.length))
        rich.replaceCharacters(in: codeRange, with: MacRichCode.render(token.original.replacing(body: token.original.body, info: "python"), ending: token.ending))
        XCTAssertEqual(MacMarkdown.markdown(rich), "1. First\n1. Second\n\n```python\nold\n```\n", "A language-only model change must invalidate untouched-document source reuse")
    }

    @MainActor func testNativeHorizontalRulesRetainTheirBlockAndEditingBoundaries() throws {
        // A rule is an item-owned block, including compact first-child rules.
        // Check its parser owner independently from native source-token reuse.
        func ownedBlocks(_ source: String) -> [String] {
            var result: [String] = [], ordinal = 0
            func walk(_ node: any Markup, owner: Int? = nil) {
                var next = owner
                if node is ListItem { next = ordinal; ordinal += 1; result.append("item:\(next!):\(owner ?? -1)") }
                if node is ThematicBreak { result.append("rule:\(owner ?? -1)") }
                if let heading = node as? Heading { result.append("heading:\(owner ?? -1):\(heading.level):" + heading.plainText) }
                if let paragraph = node as? Paragraph { result.append("text:\(owner ?? -1):" + paragraph.plainText) }
                for child in node.children { walk(child, owner: next) }
            }
            walk(Document(parsing: source)); return result
        }
        let returnCases: [(String, String, String, String?)] = [
            ("9. ***\n   - Child\n     - Grandchild\n   - Peer\n10. Sibling\n", "9. New\n10. ***\n    - Child\n      - Grandchild\n    - Peer\n10. Sibling\n", "9. ***\n10. \n    - NewChild\n      - Grandchild\n    - Peer\n10. Sibling\n", nil),
            ("- ***\n\n  Tail\n- Sibling\n", "- New\n- ***\n\n  Tail\n- Sibling\n", "- ***\n- NewTail\n- Sibling\n", nil),
            ("- > ***\n  >\n  > Tail\n- Sibling\n", "- New\n- > ***\n  >\n  > Tail\n- Sibling\n", "- > ***\n- NewTail\n- Sibling\n", nil),
            ("- Parent\n\n  ***\n  - \n- Sibling\n", "- Parent\n\n- New\n  ***\n  - \n- Sibling\n", "- Parent\n\n  ***\n- New\n\n  - \n- Sibling\n", nil),
            ("- Parent\n  > Before\n  >\n  > ***\n  > - \n- Sibling\n", "- Parent\n  > Before\n- New\n  ***\n  - \n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n  - New\n- Sibling\n", nil),
            ("- Parent\n  > Before\n  >\n  > ***\n  > - Child\n  >\n  > Tail\n- Sibling\n", "- Parent\n  > Before\n- New\n  ***\n  - Child\n\n  Tail\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n- \n  - NewChild\n\n  Tail\n- Sibling\n", nil),
            ("- Parent\n  > Before\n  >\n  > ***\n  > - Child\n  >   - Grandchild\n  >\n  > Tail\n- Sibling\n", "- Parent\n  > Before\n- New\n  ***\n  - Child\n    - Grandchild\n\n  Tail\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n- \n  - NewChild\n    - Grandchild\n\n  Tail\n- Sibling\n", nil),
            ("- Parent\n  > > Before\n  > >\n  > > ***\n  > > - Child\n  > >\n  > > Tail\n- Sibling\n", "- Parent\n  > > Before\n- New\n  ***\n  - Child\n\n  Tail\n- Sibling\n", "- Parent\n  > > Before\n  > >\n  > > ***\n- \n  - NewChild\n\n  Tail\n- Sibling\n", nil),
            ("- Parent\n\n  ***\n  - Child\n\n  Tail\n- Sibling\n", "- Parent\n\n- New\n  ***\n  - Child\n\n  Tail\n- Sibling\n", "- Parent\n\n  ***\n- \n  - NewChild\n\n  Tail\n- Sibling\n", nil),
            ("- Parent\n  > Before\n  >\n  > ***\n  > - **Child**\n  >\n  > Tail\n- Sibling\n", "- Parent\n  > Before\n- New\n  ***\n  - **Child**\n\n  Tail\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n- \n  - New**Child**\n\n  Tail\n- Sibling\n", nil),
            ("- Parent\n  > Before\n  >\n  > ***\n  > - [Child](https://example.test/)\n  >\n  > Tail\n- Sibling\n", "- Parent\n  > Before\n- New\n  ***\n  - [Child](https://example.test/)\n\n  Tail\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n- \n  - New[Child](https://example.test/)\n\n  Tail\n- Sibling\n", nil),
            ("- Parent\n  > Before\n  >\n  > ***\n  > - `Child`\n  >\n  > Tail\n- Sibling\n", "- Parent\n  > Before\n- New\n  ***\n  - `Child`\n\n  Tail\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n- \n  - New`Child`\n\n  Tail\n- Sibling\n", nil),
            ("- Parent\n  > Before\n  >\n  > ***\n  > - Child\n  >   > Inner\n  >\n  > Tail\n- Sibling\n", "- Parent\n  > Before\n- New\n  ***\n  - Child\n    > Inner\n\n  Tail\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n- \n  - NewChild\n    > Inner\n\n  Tail\n- Sibling\n", nil),
            ("- Parent\n  > Before\n  >\n  > ***\n  > - Child\n  >   > - Grandchild\n  >\n  > Tail\n- Sibling\n", "- Parent\n  > Before\n- New\n  ***\n  - Child\n    > - Grandchild\n\n  Tail\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n- \n  - NewChild\n    > - Grandchild\n\n  Tail\n- Sibling\n", nil),
            ("- Parent\n  > > Before\n  > >\n  > > ***\n  > >\n  > > Tail\n- Sibling\n", "- Parent\n  > > Before\n- New\n  ***\n\n  Tail\n- Sibling\n", "- Parent\n  > > Before\n  > >\n  > > ***\n- NewTail\n- Sibling\n", nil),
            ("- Parent\n  > Outer\n  >\n  > > Before\n  > >\n  > > ***\n  > >\n  > > Tail\n  >\n  > Outer tail\n- Sibling\n", "- Parent\n  > Outer\n  >\n  > > Before\n- New\n  ***\n\n  Tail\n\n  Outer tail\n- Sibling\n", "- Parent\n  > Outer\n  >\n  > > Before\n  > >\n  > > ***\n- NewTail\n\n  Outer tail\n- Sibling\n", nil),
            ("- Parent\n  > Before\n  >\n  > ***\n  >\n  > Tail\n- Sibling\n", "- Parent\n  > Before\n- New\n  ***\n\n  Tail\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n- NewTail\n- Sibling\n", nil),
            ("- Parent\n\n  ***\n\n  Tail\n- Sibling\n", "- Parent\n\n- New\n  ***\n\n  Tail\n- Sibling\n", "- Parent\n\n  ***\n- NewTail\n- Sibling\n", "- Parent\n\n  ***\n\n  Tail\n- New\n- Sibling\n"),
            ("9. Parent\n\n   * * *\n\n   Tail\n10. Sibling\n", "9. Parent\n\n10. New\n    * * *\n\n    Tail\n10. Sibling\n", "9. Parent\n\n   * * *\n10. NewTail\n10. Sibling\n", "9. Parent\n\n   * * *\n\n   Tail\n10. New\n10. Sibling\n"),
            ("- Parent\n  - Child\n\n    ___\n\n    Tail\n- Sibling\n", "- Parent\n  - Child\n\n  - New\n    ___\n\n    Tail\n- Sibling\n", "- Parent\n  - Child\n\n    ___\n  - NewTail\n- Sibling\n", "- Parent\n  - Child\n\n    ___\n\n    Tail\n  - New\n- Sibling\n")
        ]
        for (body, before, after, selected) in returnCases { for quotes in ["", "> "] { for ending in ["\n", "\r\n"] { for mode in ["before", "after", "selected"] {
            func spelled(_ source: String) -> String { source.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map { quotes + $0 + ending }.joined() }
            let expectedBody: String
            if mode == "selected" { guard let selected else { continue }; expectedBody = selected }
            else { expectedBody = mode == "after" ? after : before }
            let source = spelled(body), expected = spelled(expectedBody)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                let rule = (view.string as NSString).range(of: "\u{fffc}")
                guard rule.location != NSNotFound else { XCTFail("The divider must be native"); return }
                let caret = NSRange(location: rule.location + (mode == "after" ? 1 : 0), length: mode == "selected" ? 1 : 0)
                view.setSelectedRange(caret); view.insertNewline(nil)
                let entered = coordinator.lastMarkdown, receiving = view.selectedRange()
                view.breakUndoCoalescing()
                if let undo = view.undoManager, undo.groupingLevel == 1 { undo.endUndoGrouping(); undo.beginUndoGrouping() }
                view.insertText("New", replacementRange: receiving)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), ownedBlocks(expected))
                XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, entered); XCTAssertEqual(view.selectedRange(), receiving)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), caret)
                coordinator.action("redo"); coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } } } }
        let selectedCases = [
            ("- Parent\n  > Before\n  >\n  > ***\n  >\n  > Tail\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n  >\n  > \u{200b}\n  >\n  > NewTail\n- Sibling\n"),
            ("- > ***\n  >\n  > Tail\n- Sibling\n", "- > ***\n  >\n  > \u{200b}\n  >\n  > NewTail\n- Sibling\n"),
            ("- Parent\n\n  ***\n\n  # Heading\n\n  Tail\n- Sibling\n", "- Parent\n\n  ***\n\n  \u{200b}\n  # NewHeading\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  ***\n  - Child\n- Sibling\n", "- Parent\n\n  ***\n- New\n  - Child\n- Sibling\n"),
            ("- Parent\n\n  ***\n\n  ```\n  code\n  ```\n- Sibling\n", "- Parent\n\n  ***\n- New\n\n  ```\n  code\n  ```\n- Sibling\n"),
            ("- Parent\n  > Before\n  >\n  > ***\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n- New\n- Sibling\n"),
            ("***\n\nTail\n", "***\n\n\u{200b}\n\nNewTail\n"),
            ("- Parent\n\n  ***\n\n  **Tail**\n- Sibling\n", "- Parent\n\n  ***\n\n  **Tail**\n- New\n- Sibling\n"),
            ("- Parent\n  > Before\n  >\n  > ***\n  >\n  > **Tail**\n- Sibling\n", "- Parent\n  > Before\n  >\n  > ***\n  >\n  > \u{200b}\n  >\n  > **NewTail**\n- Sibling\n"),
            ("***\n\n**Tail**\n", "***\n\n\u{200b}\n\n**NewTail**\n"),
            ("***\n\n`Tail`\n", "***\n\n\u{200b}\n\n`NewTail`\n"),
            ("***\n\n[Tail](https://example.test/)\n", "***\n\n\u{200b}\n\nNew[Tail](https://example.test/)\n"),
            ("***", "***\nNew\n")
        ]
        for (body, typed) in selectedCases { for quotes in ["", "> "] { for ending in (body == "***" ? ["\n"] : ["\n", "\r\n"]) {
            func spelled(_ value: String) -> String {
                let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
                return lines.enumerated().map { i, line in i == lines.count - 1 && line.isEmpty ? "" : quotes + line }.joined(separator: ending)
            }
            let source = spelled(body)
            let expected = body == "***" && !quotes.isEmpty ? quotes + "***" + ending + ending + "New" + ending : spelled(typed)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                let rule = (view.string as NSString).range(of: "\u{fffc}")
                guard rule.location != NSNotFound else { XCTFail("Selected Return needs a native divider"); return }
                view.setSelectedRange(rule); view.insertNewline(nil)
                let entered = coordinator.lastMarkdown, caret = view.selectedRange()
                XCTAssertTrue(ownedBlocks(entered).contains { $0.hasPrefix("rule:") }, "Return must keep the selected divider")
                view.breakUndoCoalescing(); if let undo = view.undoManager, undo.groupingLevel == 1 { undo.endUndoGrouping(); undo.beginUndoGrouping() }
                view.insertText("New", replacementRange: caret)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), ownedBlocks(expected))
                XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, entered); XCTAssertEqual(view.selectedRange(), caret)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), rule)
                coordinator.action("redo"); coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } } }
        let owned: [(String, [String], Bool, Int)] = [
            ("- Parent\n\n  ***\n\n  Tail\n- Sibling\n", ["item:0:-1", "text:0:Parent", "rule:0", "text:0:Tail", "item:1:-1", "text:1:Sibling"], true, 0),
            ("9. Parent\n\n   * * *\n\n   Tail\n10. Sibling\n", ["item:0:-1", "text:0:Parent", "rule:0", "text:0:Tail", "item:1:-1", "text:1:Sibling"], true, 0),
            ("- ***\n\n  Tail\n- Sibling\n", ["item:0:-1", "rule:0", "text:0:Tail", "item:1:-1", "text:1:Sibling"], true, 0),
            ("- Parent\n  - Child\n\n    ___\n\n    Tail\n- Sibling\n", ["item:0:-1", "text:0:Parent", "item:1:0", "text:1:Child", "rule:1", "text:1:Tail", "item:2:-1", "text:2:Sibling"], true, 0),
            ("- Parent\n\n  ```\n  code\n  ```\n\n  ***\n\n  | A |\n  | - |\n  | cell |\n\n  Tail\n- Sibling\n", ["item:0:-1", "text:0:Parent", "rule:0", "text:0:Tail", "item:1:-1", "text:1:Sibling"], false, 0),
            ("- Parent\n  > Before\n  >\n  > ***\n  >\n  > Tail\n- Sibling\n", ["item:0:-1", "text:0:Parent", "text:0:Before", "rule:0", "text:0:Tail", "item:1:-1", "text:1:Sibling"], true, 1),
            ("- > ***\n  >\n  > Tail\n- Sibling\n", ["item:0:-1", "rule:0", "text:0:Tail", "item:1:-1", "text:1:Sibling"], true, 1)
        ]
        func ruleAndInputDepths(_ source: String) -> [String] {
            var result: [String] = []
            func walk(_ node: any Markup, depth: Int = 0) {
                let next = depth + (node is BlockQuote ? 1 : 0)
                if node is ThematicBreak { result.append("rule:\(depth)") }
                if let paragraph = node as? Paragraph, ["New", "Text"].contains(paragraph.plainText) { result.append(paragraph.plainText + ":\(depth)") }
                for child in node.children { walk(child, depth: next) }
            }
            walk(Document(parsing: source)); return result
        }
        // An unowned divider has two distinct caret boundaries. Return must
        // open text on the requested side, including a root quote and EOF.
        for quotes in ["", "> ", "> > "] { for marker in ["***", "---", "___"] {
            for (prefix, suffix) in [("", ""), ("", "\n\nTail\n"), ("Before\n\n", "\n\nTail\n")] {
                for ending in ["\n", "\r\n"] { for after in [false, true] {
                    // A bare EOF rule has no imported line-ending evidence.
                    if prefix.isEmpty && suffix.isEmpty && ending == "\r\n" { continue }
                    func spelled(_ value: String) -> String {
                        let rows = value.split(separator:"\n",omittingEmptySubsequences:false)
                        return rows.enumerated().map { index,row in index == rows.count - 1 && row.isEmpty ? "" : quotes + row }.joined(separator:ending)
                    }
                    let source = spelled(prefix + marker + suffix)
                    let beforeGap = marker == "---" ? "\n\n" : "\n"
                    let typed = after ? prefix + marker + "\nNew" + (suffix.isEmpty ? "\n" : suffix) : prefix + "New" + beforeGap + marker + suffix
                    let expected = spelled(typed), depth = quotes.filter { $0 == ">" }.count
                    let blocks = (prefix.isEmpty ? [] : ["text:-1:Before"]) + (after ? ["rule:-1", "text:-1:New"] : ["text:-1:New", "rule:-1"]) + (suffix.isEmpty ? [] : ["text:-1:Tail"])
                    try withHostedEditor(MacRichEditor(markdown:source,source:false,editable:true,onChange:{_ in},onLink:{_ in})) { view,coordinator,_ in
                        let rule = (view.string as NSString).range(of:"\u{fffc}")
                        guard rule.location != NSNotFound else { XCTFail("Return needs the native divider");return }
                        let caret = NSRange(location:rule.location + (after ? 1 : 0),length:0)
                        view.setSelectedRange(caret);view.insertNewline(nil)
                        let entered = coordinator.lastMarkdown, receiving = view.selectedRange()
                        view.breakUndoCoalescing()
                        if let undo = view.undoManager,undo.groupingLevel == 1 { undo.endUndoGrouping();undo.beginUndoGrouping() }
                        view.insertText("New",replacementRange:receiving)
                        XCTAssertEqual(coordinator.lastMarkdown,expected)
                        XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown),blocks)
                        XCTAssertEqual(ruleAndInputDepths(coordinator.lastMarkdown),after ? ["rule:\(depth)","New:\(depth)"] : ["New:\(depth)","rule:\(depth)"])
                        XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
                        coordinator.action("undo");XCTAssertEqual(coordinator.lastMarkdown,entered);XCTAssertEqual(view.selectedRange(),receiving)
                        coordinator.action("undo");XCTAssertEqual(coordinator.lastMarkdown,source);XCTAssertEqual(view.selectedRange(),caret)
                        coordinator.action("redo");coordinator.action("redo");XCTAssertEqual(coordinator.lastMarkdown,expected)
                    }
                } }
            }
        } }
        for (body, expected, ruleBeforeTail, innerDepth) in owned { for quotes in ["", "> "] { for ending in ["\n", "\r\n"] {
            let source = body.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map { quotes + $0 + ending }.joined()
            let depth = innerDepth + (quotes.isEmpty ? 0 : 1)
            XCTAssertEqual(ruleAndInputDepths(source), ["rule:\(depth)"])
            XCTAssertEqual(ownedBlocks(source), expected)
            XCTAssertFalse(MacMarkdown.requiresSource(source), source)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                func ruleRange() -> NSRange? {
                    var found: NSRange?
                    view.attributedString().enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.string.utf16.count)) { value, range, _ in
                        if value is MacRuleAttachment { XCTAssertNil(found); found = range }
                    }
                    return found
                }
                guard ruleRange() != nil else { XCTFail("The item rule must be a visible native attachment: " + source); return }
                XCTAssertEqual(coordinator.lastMarkdown, source)
                let tail = (view.string as NSString).range(of: "Tail")
                XCTAssertNotEqual(tail.location, NSNotFound)
                view.setSelectedRange(NSRange(location: NSMaxRange(tail), length: 0)); view.insertText("!", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, source.replacingOccurrences(of: "Tail", with: "Tail!"))
                XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), expected.map { $0.hasSuffix(":Tail") ? $0 + "!" : $0 })
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, source.replacingOccurrences(of: "Tail", with: "Tail!"))
                coordinator.action("undo")
                let conversions: [String: (String, String)] = [
                    "- Parent\n\n  ***\n\n  Tail\n- Sibling\n": ("ordered", "1. Parent\n\n   ***\n\n   Tail\n- Sibling\n"),
                    "9. Parent\n\n   * * *\n\n   Tail\n10. Sibling\n": ("bullet", "- Parent\n\n  * * *\n\n  Tail\n10. Sibling\n"),
                    "- Parent\n  - Child\n\n    ___\n\n    Tail\n- Sibling\n": ("ordered", "1. Parent\n   - Child\n\n     ___\n\n     Tail\n- Sibling\n")
                ]
                if let (command, converted) = conversions[body] {
                    let parent = (view.string as NSString).range(of: "Parent")
                    let expectedSource = converted.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map { quotes + $0 + ending }.joined()
                    view.setSelectedRange(parent); coordinator.action(command)
                    XCTAssertEqual(coordinator.lastMarkdown, expectedSource)
                    XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), expected)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), parent)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expectedSource)
                    coordinator.action("undo")
                }
                if body.hasPrefix("- Parent\n\n") {
                    let parent = (view.string as NSString).range(of: "Parent")
                    view.setSelectedRange(parent); coordinator.action("h1")
                    let promoted = ["heading:-1:1:Parent", "rule:-1", "text:-1:Tail", "item:0:-1", "text:0:Sibling"]
                    XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), promoted, coordinator.lastMarkdown)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), parent)
                    coordinator.action("redo"); XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), promoted)
                    coordinator.action("undo")
                }
                guard let rule = ruleRange() else { XCTFail("Undo must restore the rule"); return }
                view.breakUndoCoalescing()
                if let undo = view.undoManager, undo.groupingLevel == 1 { undo.endUndoGrouping(); undo.beginUndoGrouping() }
                view.setSelectedRange(rule); view.deleteBackward(nil)
                XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), expected.filter { !$0.hasPrefix("rule:") })
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), rule)
                coordinator.action("redo"); XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), expected.filter { !$0.hasPrefix("rule:") })
                coordinator.action("undo")
                if ruleBeforeTail {
                let tailStart = (view.string as NSString).range(of: "Tail").location
                view.setSelectedRange(NSRange(location: tailStart, length: 0)); view.deleteBackward(nil)
                XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), expected.filter { !$0.hasPrefix("rule:") })
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.selectedRange(), NSRange(location: tailStart, length: 0))
                coordinator.action("redo"); XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), expected.filter { !$0.hasPrefix("rule:") })
                coordinator.action("undo")
                }
                for wholeRow in [false, true] { for marked in [false, true] {
                    guard let rule = ruleRange() else { XCTFail("Replacement needs the rule attachment"); return }
                    let selected = wholeRow ? (view.string as NSString).paragraphRange(for: rule) : rule
                    view.setSelectedRange(selected)
                    if marked {
                        view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: selected)
                        XCTAssertEqual(coordinator.lastMarkdown, source)
                        view.insertText("Text", replacementRange: view.markedRange())
                    } else { view.insertText("Text", replacementRange: selected) }
                    let owner = String(expected.first { $0.hasPrefix("rule:") }!.dropFirst(5))
                    XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), expected.map { $0 == "rule:" + owner ? "text:" + owner + ":Text" : $0 })
                    XCTAssertEqual(ruleAndInputDepths(coordinator.lastMarkdown), ["Text:\(depth)"])
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                    coordinator.action("redo"); XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), expected.map { $0 == "rule:" + owner ? "text:" + owner + ":Text" : $0 })
                    coordinator.action("undo")
                } }
                for after in [false, true] { for marked in [false, true] {
                    guard let rule = ruleRange() else { XCTFail("The rule must remain available for typing"); return }
                    let caret = NSRange(location: rule.location + (after ? rule.length : 0), length: 0)
                    view.setSelectedRange(caret)
                    let beforeTyping = coordinator.lastMarkdown, typingCaret = view.selectedRange()
                    if marked {
                        view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: typingCaret)
                        XCTAssertEqual(coordinator.lastMarkdown, beforeTyping, "Composition must not save provisional rule scaffolding")
                        view.insertText("New", replacementRange: view.markedRange())
                    } else { view.insertText("New", replacementRange: typingCaret) }
                    let owner = expected.first { $0.hasPrefix("rule:") }!.dropFirst(5)
                    var blocks = expected
                    let index = blocks.firstIndex(of: "rule:" + owner)!
                    let continuesAfter = after
                    blocks.insert("text:" + owner + ":New", at: index + (continuesAfter ? 1 : 0))
                    XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), blocks, coordinator.lastMarkdown)
                    XCTAssertEqual(ruleAndInputDepths(coordinator.lastMarkdown), continuesAfter ? ["rule:\(depth)", "New:\(depth)"] : ["New:\(depth)", "rule:\(depth)"])
                    XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, beforeTyping); XCTAssertEqual(view.selectedRange(), typingCaret)
                    coordinator.action("redo"); XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), blocks)
                    coordinator.action("undo")
                } }
                if ruleBeforeTail {
                    guard let rule = ruleRange() else { XCTFail("The edge selection needs a rule"); return }
                    let tail = (view.string as NSString).range(of: "Tail")
                    let selected = NSRange(location: NSMaxRange(rule), length: tail.location + 2 - NSMaxRange(rule))
                    view.setSelectedRange(selected); view.insertText("X", replacementRange: selected)
                    XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), expected.map { $0.hasSuffix(":Tail") ? String($0.dropLast(4)) + "Xil" : $0 }, coordinator.lastMarkdown)
                    XCTAssertTrue(view.string.contains("Xil"))
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                    coordinator.action("redo"); XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), expected.map { $0.hasSuffix(":Tail") ? String($0.dropLast(4)) + "Xil" : $0 })
                    coordinator.action("undo")
                }
                if body == "- Parent\n\n  ***\n\n  Tail\n- Sibling\n" {
                    for includesRule in [false, true] {
                        guard let rule = ruleRange() else { XCTFail("The ending endpoint needs a rule"); return }
                        let parent = (view.string as NSString).range(of: "Parent")
                        let start = parent.location + 3, end = rule.location + (includesRule ? rule.length : 0)
                        let selected = NSRange(location: start, length: end - start)
                        view.setSelectedRange(selected); view.insertText("X", replacementRange: selected)
                        let blocks = ["item:0:-1", "text:0:ParX"] + (includesRule ? [] : ["rule:0"]) + ["text:0:Tail", "item:1:-1", "text:1:Sibling"]
                        XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), blocks, coordinator.lastMarkdown)
                        coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                        coordinator.action("redo"); XCTAssertEqual(ownedBlocks(coordinator.lastMarkdown), blocks)
                        coordinator.action("undo")
                    }
                }
                guard let cancelledRule = ruleRange() else { XCTFail("Cancellation needs the rule"); return }
                view.setSelectedRange(cancelledRule)
                view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: cancelledRule)
                XCTAssertEqual(coordinator.lastMarkdown, source)
                view.cancelOperation(nil)
                XCTAssertFalse(view.hasMarkedText()); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.selectedRange(), cancelledRule)
                XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
            }
        } } }
        for spelling in ["---", "***", "___", "* * *", "  - - -"] { for quotes in ["", "> ", "> > "] { for ending in ["\n", "\r\n"] {
            let source = quotes + "Before" + ending + quotes + ending + quotes + spelling + ending + quotes + ending + quotes + "After" + ending
            XCTAssertFalse(MacMarkdown.requiresSource(source))
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                var attachments: [(NSTextAttachment, NSRange)] = []
                view.attributedString().enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.string.utf16.count)) { value, range, _ in
                    if let value = value as? NSTextAttachment { attachments.append((value, range)) }
                }
                XCTAssertEqual(attachments.count, 1, "A horizontal rule is a visible native block")
                guard let (attachment, rule) = attachments.first else { return }
                XCTAssertEqual(attachment.image?.accessibilityDescription, "Horizontal rule")
                XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                let small = attachment.attachmentBounds(for: view.textContainer, proposedLineFragment: NSRect(x: 0, y: 0, width: 300, height: 30), glyphPosition: .zero, characterIndex: rule.location)
                let wide = attachment.attachmentBounds(for: view.textContainer, proposedLineFragment: NSRect(x: 0, y: 0, width: 600, height: 30), glyphPosition: .zero, characterIndex: rule.location)
                XCTAssertGreaterThan(wide.width, small.width); XCTAssertLessThanOrEqual(wide.width, 600)
                let before = (view.string as NSString).range(of: "Before")
                view.setSelectedRange(NSRange(location: NSMaxRange(before), length: 0)); view.insertText("!", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, source.replacingOccurrences(of: "Before", with: "Before!"))
                view.breakUndoCoalescing()
                if let undo = view.undoManager, undo.groupingLevel == 1 { undo.endUndoGrouping(); undo.beginUndoGrouping() }
                view.setSelectedRange((view.string as NSString).range(of: "\u{FFFC}")); view.deleteBackward(nil)
                XCTAssertFalse(coordinator.lastMarkdown.contains(spelling)); coordinator.action("undo")
                XCTAssertEqual(coordinator.lastMarkdown, source.replacingOccurrences(of: "Before", with: "Before!"))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            }
        } } }
        for marker in ["---", "***", "___"] { for quotes in ["", "> "] { for ending in ["\n", "\r\n"] {
            try withHostedEditor(MacRichEditor(markdown: quotes + ending, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                for character in marker + " " { view.insertText(String(character), replacementRange: view.selectedRange()) }
                XCTAssertEqual(coordinator.lastMarkdown, quotes + marker + ending + quotes + ending)
                view.breakUndoCoalescing()
                if let undo = view.undoManager, undo.groupingLevel == 1 { undo.endUndoGrouping(); undo.beginUndoGrouping() }
                view.insertText("After", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, quotes + marker + ending + quotes + "After" + ending)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, quotes + marker + ending + quotes + ending)
                coordinator.action("undo"); XCTAssertTrue(view.string.contains(marker + " "))
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, quotes + marker + ending + quotes + ending)
            }
        } } }
        for offset in [0, 1] { for marked in [false, true] {
            try withHostedEditor(MacRichEditor(markdown: "***", source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                guard offset <= view.string.utf16.count else { XCTFail("A rule must provide a native input boundary"); return }
                view.setSelectedRange(NSRange(location: offset, length: 0)); if marked {
                    view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, "***")
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                    view.insertText("Text", replacementRange: view.markedRange())
                } else { view.insertText("Text", replacementRange: view.selectedRange()) }
                XCTAssertEqual(coordinator.lastMarkdown, offset == 0 ? "Text\n***" : "***\nText\n")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "***"); XCTAssertEqual(view.string, "\u{FFFC}")
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, offset == 0 ? "Text\n***" : "***\nText\n")
            }
        } }
        for offset in [0, 1] {
            try withHostedEditor(MacRichEditor(markdown: "***", source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                guard offset <= view.string.utf16.count else { XCTFail("A rule must provide a composition boundary"); return }
                view.setSelectedRange(NSRange(location: offset, length: 0))
                view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, "***")
                view.insertText("", replacementRange: view.markedRange())
                XCTAssertFalse(view.hasMarkedText()); XCTAssertEqual(coordinator.lastMarkdown, "***", "Cancelled composition must not save input scaffolding")
                XCTAssertFalse(view.undoManager?.canUndo ?? true); XCTAssertEqual(view.string, "\u{FFFC}")
            }
        }
        for marked in [false, true] {
            try withHostedEditor(MacRichEditor(markdown: "***", source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                guard view.string.utf16.count == 1 else { XCTFail("A selected rule must be a native block"); return }
                view.setSelectedRange(NSRange(location: 0, length: 1))
                if marked {
                    view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, "***")
                    view.insertText("Text", replacementRange: view.markedRange())
                } else { view.insertText("Text", replacementRange: view.selectedRange()) }
                XCTAssertEqual(coordinator.lastMarkdown, "Text")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "***")
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, "Text")
            }
        }
        try withHostedEditor(MacRichEditor(markdown: "***\n", source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
            view.setSelectedRange(NSRange(location: 0, length: 1)); coordinator.action("h1")
            XCTAssertEqual(coordinator.lastMarkdown, "***\n"); XCTAssertFalse(view.undoManager?.canUndo ?? true)
        }
        for quotes in ["", "> "] { for ending in ["\n", "\r\n"] { for backward in [false, true] {
            let source = (quotes + "Before\n" + quotes + "***\n" + quotes + "After\n").replacingOccurrences(of: "\n", with: ending)
            let expected = (quotes + "Before\n" + quotes + "\n" + quotes + "After\n").replacingOccurrences(of: "\n", with: ending)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                let raw = view.string as NSString, before = raw.range(of: "Before"), after = raw.range(of: "After")
                let caret = NSRange(location: backward ? after.location : NSMaxRange(before), length: 0)
                view.setSelectedRange(caret)
                if backward { view.deleteBackward(nil) } else { view.deleteForward(nil) }
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), caret)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } } }
        // Changing a heading above a dash rule must not turn it into setext syntax.
        try withHostedEditor(MacRichEditor(markdown: "# Before\n---\nAfter\n", source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
            view.setSelectedRange((view.string as NSString).range(of: "Before")); coordinator.action("paragraph")
            XCTAssertEqual(coordinator.lastMarkdown, "Before\n\n---\nAfter\n")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "# Before\n---\nAfter\n")
        }
        for ending in ["\n", "\r\n"] {
            let source = "Before abcd after\n".replacingOccurrences(of: "\n", with: ending)
            let expected = "Before a\n\n***\n\nd after\n".replacingOccurrences(of: "\n", with: ending)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                let selected = (view.string as NSString).range(of: "bc")
                view.setSelectedRange(selected); coordinator.action("rule")
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        }
    }
    @MainActor func testNativeMarkerCaretInputUsesTheBodyBoundaryAndRetainsOwners() throws {
        func parents(_ source: String) -> [Int?] {
            var result: [Int?] = []
            func collect(_ node: any Markup, owner: Int? = nil) {
                var next = owner
                if node is ListItem { next = result.count; result.append(owner) }
                for child in node.children { collect(child, owner: next) }
            }
            collect(Document(parsing: source)); return result
        }
        for (source, returned, lifted, originalOwners, returnOwners, liftedOwners) in [
            ("- Parent\n  - Child\n- Sibling\n", "- \n- Parent\n  - Child\n- Sibling\n", "Parent\n\n- Child\n- Sibling\n", [nil, 0, nil] as [Int?], [nil, nil, 1, nil], [nil, nil]),
            ("9. Parent\n   - Child\n10. Sibling\n", "9. \n10. Parent\n    - Child\n10. Sibling\n", "Parent\n\n- Child\n10. Sibling\n", [nil, 0, nil], [nil, nil, 1, nil], [nil, nil]),
            ("- [x] Parent\n  - Child\n- Sibling\n", "- [x] \u{200B}\n- [ ] Parent\n  - Child\n- Sibling\n", "Parent\n\n- Child\n- Sibling\n", [nil, 0, nil], [nil, nil, 1, nil], [nil, nil]),
            ("9. [x] Parent\n   - Child\n10. Sibling\n", "9. [x] \u{200B}\n10. [ ] Parent\n    - Child\n10. Sibling\n", "Parent\n\n- Child\n10. Sibling\n", [nil, 0, nil], [nil, nil, 1, nil], [nil, nil]),
            ("> - Parent\n>   - Child\n> - Sibling\n", "> - \n> - Parent\n>   - Child\n> - Sibling\n", "> Parent\n> \n> - Child\n> - Sibling\n", [nil, 0, nil], [nil, nil, 1, nil], [nil, nil]),
            ("- Root\n  - Parent\n    - Child\n- Sibling\n", "- Root\n\n  - \n  - Parent\n    - Child\n- Sibling\n", "- Root\n- Parent\n  - Child\n- Sibling\n", [nil, 0, 1, nil], [nil, 0, 0, 2, nil], [nil, nil, 1, nil])
        ] { for ending in ["\n", "\r\n"] { for action in ["type", "explicit", "return", "backspace", "forward", "marked", "markedExplicit"] {
            let source = source.replacingOccurrences(of: "\n", with: ending)
            let expected = (action == "return" ? returned.replacingOccurrences(of: "\n", with: ending) : action == "backspace" ? lifted.replacingOccurrences(of: "\n", with: ending) : source.replacingOccurrences(of: "Parent", with: ["type", "explicit"].contains(action) ? "XParent" : action.hasPrefix("marked") ? "éParent" : "arent"))
            let owners = action == "return" ? returnOwners : action == "backspace" ? liftedOwners : originalOwners
            // Observe all real prefix positions, without duplicating its spelling.
            let visible = MacMarkdown.render(source).string as NSString, body = visible.range(of: "Parent")
            let row = visible.paragraphRange(for: body)
            for offset in row.location..<body.location {
                var published: [String] = [], issues: [String] = []
                let editor = MacRichEditor(markdown: source, source: false, editable: true, onChange: { published.append($0) }, onLink: { _ in }, onPasteError: { issues.append($0) })
                try withHostedEditor(editor) { view, coordinator, _ in
                    let start = (view.string as NSString).range(of: "Parent").location
                    view.setSelectedRange(NSRange(location: offset, length: 0))
                    if ["type", "explicit"].contains(action) { view.insertText("X", replacementRange: action == "explicit" ? NSRange(location: offset, length: 0) : view.selectedRange()) }
                    else if action == "return" { view.insertNewline(nil) }
                    else if action == "backspace" { view.deleteBackward(nil) }
                    else if action == "forward" { view.deleteForward(nil) }
                    else {
                        view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: action == "markedExplicit" ? NSRange(location: offset, length: 0) : NSRange(location: NSNotFound, length: 0))
                        XCTAssertTrue(view.hasMarkedText()); XCTAssertEqual(coordinator.lastMarkdown, source)
                        view.setMarkedText("é", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.markedRange())
                        XCTAssertEqual(coordinator.lastMarkdown, source)
                        view.insertText("é", replacementRange: view.markedRange())
                        XCTAssertFalse(view.hasMarkedText()); XCTAssertFalse(published.contains { $0.contains("´") })
                    }
                    XCTAssertEqual(coordinator.lastMarkdown, expected, "\(action) at marker offset \(offset)")
                    XCTAssertEqual(parents(coordinator.lastMarkdown), owners); XCTAssertTrue(issues.isEmpty)
                    XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), expected)
                    if action == "return", !source.hasPrefix("- Root") { XCTAssertEqual(view.string, MacMarkdown.render(expected).string) }
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                    XCTAssertEqual(view.selectedRange(), NSRange(location: start, length: action == "forward" ? 1 : 0), "Undo restores the legal body boundary, not an input position inside presentation")
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                    view.insertText("!", replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: action == "forward" ? "arent" : "Parent", with: action == "forward" ? "!arent" : "!Parent"))
                }
            }
        } } }
        for offset in [0, 1] {
            try withHostedEditor(MacRichEditor(markdown: "- ", source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                view.setSelectedRange(NSRange(location: offset, length: 0)); view.insertText("X", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, "- X"); XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 0))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "- "); XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 0))
            }
        }
        try withHostedEditor(MacRichEditor(markdown: "- Parent\n", source: true, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
            view.setSelectedRange(NSRange(location: 1, length: 0)); view.insertText("X", replacementRange: view.selectedRange())
            XCTAssertEqual(coordinator.lastMarkdown, "-X Parent\n")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "- Parent\n"); XCTAssertEqual(view.selectedRange(), NSRange(location: 1, length: 0))
        }
    }
    @MainActor func testMarkedListReplacementCommitsOnlyTheFinishedTextAndKeepsOwnership() throws {
        // Ordinary caret input shares the storage/export path with structural
        // replacement, but AppKit retains ownership of its provisional edits.
        for (template, sourceMode) in [
            ("Before\n\nTail\n\n```swift\nlet x = 0\n```\n", false),
            ("# Tail\n\nKeep\n", false),
            ("> Tail\n>\n> Keep\n", false),
            ("> > Tail\n> >\n> > Keep\n", false),
            ("- Tail\n  - Child\n- Sibling\n", false),
            ("- Parent\n  - Tail\n- Sibling\n", false),
            ("> - Parent\n>   - Tail\n> - Sibling\n", false),
            ("> - Parent\n>   - Tail\n>\n\nOutside\n", false),
            ("Before\n\nTail\n", true)
        ] { for ending in ["\n", "\r\n", "\r"] { for cancel in [false, true] {
            let source = template.replacingOccurrences(of: "\n", with: ending)
            let expected = source.replacingOccurrences(of: "Tail", with: "Tailéã")
            var published: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: sourceMode, editable: true, onChange: { published.append($0) }, onLink: { _ in })) { view, coordinator, _ in
                let tail = (view.string as NSString).range(of: "Tail")
                guard tail.location != NSNotFound else { return XCTFail("Missing composition target") }
                let caret = NSRange(location: NSMaxRange(tail), length: 0)
                view.setSelectedRange(caret); view.breakUndoCoalescing()
                view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: caret)
                XCTAssertTrue(view.hasMarkedText()); XCTAssertEqual(coordinator.lastMarkdown, source)
                if cancel {
                    view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: view.markedRange()); view.unmarkText()
                    XCTAssertFalse(view.hasMarkedText()); XCTAssertEqual(coordinator.lastMarkdown, source)
                    XCTAssertEqual(view.string.contains("´"), false); XCTAssertEqual(view.selectedRange(), caret)
                    return
                }
                view.insertText("é", replacementRange: view.markedRange())
                view.setMarkedText("~", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, source.replacingOccurrences(of: "Tail", with: "Tailé"))
                view.insertText("ã", replacementRange: view.markedRange()); view.breakUndoCoalescing()
                XCTAssertFalse(view.hasMarkedText()); XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(published.last, expected); XCTAssertFalse(published.contains { $0.contains("´") || $0.contains("~") })
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                if !sourceMode { XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected) }
            }
        } } }
        for (template, from, a, through, b, committed, role) in [
            ("- a1\n  - b1\n- c1\n  - d1\n", "b1", 1, "c1", 1, "- a1\n  - bé1\n  - d1\n", ""),
            ("- ## Heading\n\n  Tail\n- Sibling\n", "Heading", 3, "Tail", 2, "- ## Heaéil\n- Sibling\n", "heading"),
            ("- > Quote\n\n  Tail\n- Sibling\n", "Quote", 3, "Tail", 2, "- > Quoéil\n- Sibling\n", "quote"),
            ("- ## Heading\n- Sibling\n", "Heading", 3, "Sibling", 3, "- ## Heaéling\n", "heading"),
            ("- > Quote\n- Sibling\n", "Quote", 3, "Sibling", 3, "- > Quoéling\n", "quote"),
            ("- Parent\n\n  ## Heading\n- Sibling\n", "Heading", 3, "Sibling", 3, "- Parent\n\n  ## Heaéling\n", "heading"),
            ("- Parent\n\n  > Quote\n- Sibling\n", "Quote", 3, "Sibling", 3, "- Parent\n\n  > Quoéling\n", "quote")
        ] { for ending in ["\n", "\r\n", "\r"] { for completion in ["commit", "empty", "escape"] {
            let source = template.replacingOccurrences(of: "\n", with: ending)
            let expected = committed.replacingOccurrences(of: "\n", with: ending)
            var published: [String] = []
            let editor = MacRichEditor(markdown: source, source: false, editable: true, onChange: { published.append($0) }, onLink: { _ in })
            try withHostedEditor(editor) { view, coordinator, host in
                let raw = view.string as NSString, start = raw.range(of: from), end = raw.range(of: through)
                let selection = NSRange(location: start.location + a, length: end.location + b - start.location - a)
                let originalFont = try XCTUnwrap(view.attributedString().attribute(.font, at: start.location, effectiveRange: nil) as? NSFont)
                func checkHeadingStyle() {
                    guard role == "heading" else { return }
                    let text = view.string as NSString, committed = text.range(of: "é")
                    guard committed.location != NSNotFound else { return XCTFail("Missing committed accent") }
                    let row = text.paragraphRange(for: committed)
                    let length = row.length - (text.character(at: NSMaxRange(row) - 1) == 10 ? 1 : 0)
                    view.attributedString().enumerateAttribute(.font, in: NSRange(location: row.location, length: length)) { font, _, _ in
                        let font = font as? NSFont
                        XCTAssertEqual(font?.pointSize, originalFont.pointSize, "The merged heading suffix must retain its native heading size")
                        XCTAssertEqual(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) }, NSFontManager.shared.traits(of: originalFont).contains(.boldFontMask))
                    }
                }
                view.setSelectedRange(selection)
                view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: selection)
                XCTAssertTrue(view.hasMarkedText(), "The first dead-key update must remain owned by the text input system")
                XCTAssertEqual(coordinator.lastMarkdown, source, "Provisional marked text must not reach autosave")
                view.setMarkedText("é", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.markedRange())
                XCTAssertEqual(coordinator.lastMarkdown, source)
                if completion != "commit" {
                    if completion == "empty" { view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: view.markedRange()); view.unmarkText() }
                    else {
                        let window = try XCTUnwrap(host.window)
                        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
                        view.keyDown(with: event)
                    }
                    XCTAssertFalse(view.hasMarkedText(), "Escape must finish cancellation in the native input client")
                    XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                    XCTAssertEqual(view.selectedRange(), selection); XCTAssertFalse(view.undoManager?.canUndo ?? true)
                    return
                }
                view.insertText("é", replacementRange: view.markedRange())
                XCTAssertFalse(view.hasMarkedText()); XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(published.last, expected); XCTAssertFalse(published.contains { $0.contains("´") })
                var roles: [String] = []
                func walk(_ node: any Markup) {
                    if node is Heading { roles.append("heading") }
                    if node is BlockQuote { roles.append("quote") }
                    for child in node.children { walk(child) }
                }
                walk(Document(parsing: coordinator.lastMarkdown)); XCTAssertEqual(roles, role.isEmpty ? [] : [role]); checkHeadingStyle()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); checkHeadingStyle()
            }
        } } }
        for table in [false, true] { for outgoing in [false, true] { for completion in ["commit", "empty", "escape"] { for standalone in [false, true] {
            let prefix = standalone ? "" : "  "
            let rows = table ? ["| A | B |", "| --- | --- |", "| abcdef | Keep |"] : ["```swift", "abcdef", "```"]
            let card = rows.map { prefix + $0 }.joined(separator: "\n") + "\n"
            let source = (standalone ? "Parent\n\n" : "- Parent\n") + card + (standalone ? "\nSibling\n" : "- Sibling\n")
            var published: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { published.append($0) }, onLink: { _ in })) { view, coordinator, host in
                let raw = view.string as NSString, first = raw.range(of: outgoing ? "abcdef" : "Parent"), last = raw.range(of: outgoing ? "Sibling" : "abcdef")
                let selected = NSRange(location: first.location + 3, length: last.location - first.location)
                view.setSelectedRange(selected); view.undoManager?.removeAllActions()
                view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: selected)
                guard view.hasMarkedText() else { XCTFail("Card-boundary input must stay owned by the input method"); return }
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertFalse(published.contains { $0.contains("´") })
                if completion != "commit" {
                    if completion == "empty" { view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: view.markedRange()); view.unmarkText() }
                    else {
                        let window = try XCTUnwrap(host.window)
                        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
                        view.keyDown(with: event)
                    }
                    XCTAssertFalse(view.hasMarkedText(), "Escape must finish cancellation in the native input client")
                    XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source); XCTAssertEqual(view.selectedRange(), selected)
                    XCTAssertFalse(view.undoManager?.canUndo ?? true)
                } else {
                    view.setMarkedText("é", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.markedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, source)
                    view.insertText("é", replacementRange: view.markedRange())
                    XCTAssertFalse(view.hasMarkedText()); XCTAssertFalse(published.contains { $0.contains("´") })
                    if table {
                        var cells: [String] = []
                        func text(_ node: any Markup) -> String { (node as? Markdown.Text)?.string ?? node.children.map(text).joined() }
                        func collect(_ node: any Markup) { if node is Markdown.Table.Cell { cells.append(text(node)) }; for child in node.children { collect(child) } }
                        collect(Document(parsing: coordinator.lastMarkdown)); XCTAssertEqual(cells, outgoing ? ["A", "B", "abcéling", ""] : ["", "", "def", "Keep"])
                    } else {
                        let expected = standalone ? (outgoing ? "Parent\n\n```swift\nabcéling\n```\n" : "Paré\n```swift\ndef\n```\n\nSibling\n") : (outgoing ? "- Parent\n  ```swift\n  abcéling\n  ```\n" : "- Paré\n  ```swift\n  def\n  ```\n- Sibling\n")
                        XCTAssertEqual(coordinator.lastMarkdown, expected)
                    }
                    let saved = coordinator.lastMarkdown
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
                }
            }
        } } } }
        for sourceMode in [false, true] {
            let source = "Plain text.\n"
            try withHostedEditor(MacRichEditor(markdown: source, source: sourceMode, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, host in
                let selected = NSRange(location: 1, length: 2); view.setSelectedRange(selected)
                let window = try XCTUnwrap(host.window)
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
                view.keyDown(with: event)
                XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                XCTAssertFalse(view.hasMarkedText()); XCTAssertFalse(view.undoManager?.canUndo ?? true)
            }
        }
    }
    @MainActor func testReturnInsideItemOwnedBlocksKeepsRolesCaretAndLaterContent() throws {
        // Public Markdown structure is the oracle, independently of native contexts.
        func tree(_ source: String) -> [String] {
            var result: [String] = [], next = 0
            func walk(_ node: any Markup, owner: Int? = nil, depth: Int = 0) {
                var owner = owner, depth = depth
                if node is ListItem { owner = next; next += 1 }
                if node is BlockQuote { depth += 1 }
                if let owner, node is Paragraph || node is Heading {
                    let role = (node as? Heading).map { "h\($0.level)" } ?? "p"
                    func text(_ node: any Markup) -> String {
                        if let text = node as? Markdown.Text { return text.string }
                        return node.children.map { text($0) }.joined()
                    }
                    result.append("\(owner):\(depth):\(role):\(text(node))")
                }
                for child in node.children { walk(child, owner: owner, depth: depth) }
            }
            walk(Document(parsing: source)); return result
        }
        let rows: [(String, String, Int, String, String)] = [
            ("> 9. ## Heading\n> 10. Sibling\n", "Heading", 3, "> 9. ## Hea\n>    ## ding\n> 10. Sibling\n", "> 9. ## Hea\n>    ## Newding\n> 10. Sibling\n"),
            ("- Root\n  - # Heading\n  - Peer\n", "Heading", 3, "- Root\n  - # Hea\n    # ding\n  - Peer\n", "- Root\n  - # Hea\n    # Newding\n  - Peer\n"),
            ("- # **Heading**\n- Sibling\n", "Heading", 3, "- # **Hea**\n  # **ding**\n- Sibling\n", "- # **Hea**\n  # **Newding**\n- Sibling\n"),
            ("- # Heading\n- Sibling\n", "Heading", 0, "- \u{200b}\n  # Heading\n- Sibling\n", "- \u{200b}\n  # NewHeading\n- Sibling\n"),
            ("- # Heading\n- Sibling\n", "Heading", 3, "- # Hea\n  # ding\n- Sibling\n", "- # Hea\n  # Newding\n- Sibling\n"),
            ("- # Heading\n- Sibling\n", "Heading", 7, "- # Heading\n  \u{200b}\n- Sibling\n", "- # Heading\n  New\n- Sibling\n"),
            ("- > Quote\n- Sibling\n", "Quote", 0, "- > \u{200b}\n  >\n  > Quote\n- Sibling\n", "- > \u{200b}\n  >\n  > NewQuote\n- Sibling\n"),
            ("- > Quote\n- Sibling\n", "Quote", 3, "- > Quo\n  >\n  > te\n- Sibling\n", "- > Quo\n  >\n  > Newte\n- Sibling\n"),
            ("- > Quote\n- Sibling\n", "Quote", 5, "- > Quote\n  >\n  > \u{200b}\n- Sibling\n", "- > Quote\n  >\n  > New\n- Sibling\n"),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", 0, "- Parent\n\n  \u{200b}\n  ## Heading\n\n  Tail\n- Sibling\n", "- Parent\n\n  \u{200b}\n  ## NewHeading\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", 3, "- Parent\n\n  ## Hea\n  ## ding\n\n  Tail\n- Sibling\n", "- Parent\n\n  ## Hea\n  ## Newding\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", 7, "- Parent\n\n  ## Heading\n  \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  ## Heading\n  New\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", 0, "- Parent\n\n  > \u{200b}\n  >\n  > Quote\n\n  Tail\n- Sibling\n", "- Parent\n\n  > \u{200b}\n  >\n  > NewQuote\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", 3, "- Parent\n\n  > Quo\n  >\n  > te\n\n  Tail\n- Sibling\n", "- Parent\n\n  > Quo\n  >\n  > Newte\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", 5, "- Parent\n\n  > Quote\n  >\n  > \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  > Quote\n  >\n  > New\n\n  Tail\n- Sibling\n")
        ]
        for ending in ["\n", "\r\n", "\r"] { for (input, word, offset, split, typed) in rows {
            let source = input.replacingOccurrences(of: "\n", with: ending), expected = split.replacingOccurrences(of: "\n", with: ending), typed = typed.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let wordRange = (view.string as NSString).range(of: word)
                guard wordRange.location != NSNotFound else { XCTFail("Missing Return endpoint"); return }
                let caret = NSRange(location: wordRange.location + offset, length: 0)
                view.setSelectedRange(caret); view.insertNewline(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected, source)
                XCTAssertEqual(tree(coordinator.lastMarkdown), tree(expected))
                let after = NSRange(location: caret.location + 1, length: 0)
                XCTAssertEqual(view.selectedRange(), after)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), caret)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), after)
                view.insertText("New", replacementRange: after)
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                XCTAssertEqual(tree(coordinator.lastMarkdown), tree(typed))
                let typedFont = view.attributedString().attribute(.font, at: after.location, effectiveRange: nil) as? NSFont
                let role = word == "Heading" && offset < word.utf16.count ? (input.contains("##") ? "## " : "# ") : ""
                XCTAssertEqual(typedFont?.pointSize, MacMarkdown.font(role).pointSize, "Typing must retain the receiving block's visual role")
                XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, typedFont?.pointSize)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(typed)), typed, "Reopening must retain the saved source and roles")
                if offset == word.utf16.count {
                    let repeated: String
                    if word == "Heading" { repeated = typed.replacingOccurrences(of: "New" + ending, with: "New" + ending + ending + "  \u{200b}" + ending) }
                    else { repeated = typed.replacingOccurrences(of: "New" + ending, with: "New" + ending + "  >" + ending + "  > \u{200b}" + ending) }
                    let before = view.selectedRange()
                    view.insertNewline(nil)
                    XCTAssertEqual(coordinator.lastMarkdown, repeated, "A live inner paragraph must remain in the same item on repeated Return")
                    XCTAssertEqual(tree(coordinator.lastMarkdown), tree(repeated))
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, typed); XCTAssertEqual(view.selectedRange(), before)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, repeated)
                }
            }
        } }
        for ending in ["\n", "\r\n", "\r"] {
            for (input, expected) in [
                ("- # Heading\n  \u{200b}\n- Sibling\n", "- # Heading\n  New\n\n  \u{200b}\n- Sibling\n"),
                ("- Parent\n\n  ## Heading\n  \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  ## Heading\n  New\n\n  \u{200b}\n\n  Tail\n- Sibling\n")
            ] {
                let source = input.replacingOccurrences(of: "\n", with: ending)
                withEditor(source) { view, coordinator in
                    let heading = (view.string as NSString).range(of: "Heading")
                    let blank = NSMaxRange((view.string as NSString).paragraphRange(for: heading))
                    view.setSelectedRange(NSRange(location: blank, length: 0)); view.insertText("New", replacementRange: view.selectedRange())
                    view.insertNewline(nil)
                    XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "\n", with: ending), "A reopened explicit paragraph must retain its role")
                }
            }
            for (source, expected, word, offset) in [
                ("Intro\n\n- # Heading", "Intro\n\n- # Heading\n  \u{200b}\n", "Heading", 7),
                ("Intro\n\n- > Quote", "Intro\n\n- > Quote\n  >\n  > \u{200b}\n", "Quote", 5),
                ("9. ## 😀Plan\n10. Sibling\n", "9. ## 😀P\n   ## lan\n10. Sibling\n", "😀Plan", 3)
            ] {
                withEditor(source.replacingOccurrences(of: "\n", with: ending)) { view, coordinator in
                    let word = (view.string as NSString).range(of: word)
                    let caret = NSRange(location: word.location + offset, length: 0)
                    view.setSelectedRange(caret); view.insertNewline(nil)
                    let expected = expected.replacingOccurrences(of: "\n", with: ending)
                    XCTAssertEqual(coordinator.lastMarkdown, expected)
                    XCTAssertEqual(tree(coordinator.lastMarkdown), tree(expected))
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source.replacingOccurrences(of: "\n", with: ending)); XCTAssertEqual(view.selectedRange(), caret)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                }
            }
        }
        // Return replaces the selected body atomically, then splits its inner
        // block. Marker ownership, following containers and a single Undo survive.
        for (input, word, offset, length, split, typed) in [
            ("- # Heading\n- Sibling\n", "Heading", 0, 2, "- \u{200b}\n  # ading\n- Sibling\n", "- \u{200b}\n  # Newading\n- Sibling\n"),
            ("- # Heading\n- Sibling\n", "Heading", 2, 2, "- # He\n  # ing\n- Sibling\n", "- # He\n  # Newing\n- Sibling\n"),
            ("- # Heading\n- Sibling\n", "Heading", 5, 2, "- # Headi\n  \u{200b}\n- Sibling\n", "- # Headi\n  New\n- Sibling\n"),
            ("- # Heading\n- Sibling\n", "Heading", 0, 7, "- # \n  \u{200b}\n- Sibling\n", "- # \n  New\n- Sibling\n"),
            ("- > Quote\n- Sibling\n", "Quote", 0, 2, "- > \u{200b}\n  >\n  > ote\n- Sibling\n", "- > \u{200b}\n  >\n  > Newote\n- Sibling\n"),
            ("- > Quote\n- Sibling\n", "Quote", 2, 2, "- > Qu\n  >\n  > e\n- Sibling\n", "- > Qu\n  >\n  > Newe\n- Sibling\n"),
            ("- > Quote\n- Sibling\n", "Quote", 3, 2, "- > Quo\n  >\n  > \u{200b}\n- Sibling\n", "- > Quo\n  >\n  > New\n- Sibling\n"),
            ("- > Quote\n- Sibling\n", "Quote", 0, 5, "- > \u{200b}\n  >\n  > \u{200b}\n- Sibling\n", "- > \u{200b}\n  >\n  > New\n- Sibling\n"),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", 0, 2, "- Parent\n\n  \u{200b}\n  ## ading\n\n  Tail\n- Sibling\n", "- Parent\n\n  \u{200b}\n  ## Newading\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", 2, 2, "- Parent\n\n  ## He\n  ## ing\n\n  Tail\n- Sibling\n", "- Parent\n\n  ## He\n  ## Newing\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", 5, 2, "- Parent\n\n  ## Headi\n  \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  ## Headi\n  New\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", 0, 7, "- Parent\n\n  ## \n  \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  ## \n  New\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", 0, 2, "- Parent\n\n  > \u{200b}\n  >\n  > ote\n\n  Tail\n- Sibling\n", "- Parent\n\n  > \u{200b}\n  >\n  > Newote\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", 2, 2, "- Parent\n\n  > Qu\n  >\n  > e\n\n  Tail\n- Sibling\n", "- Parent\n\n  > Qu\n  >\n  > Newe\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", 3, 2, "- Parent\n\n  > Quo\n  >\n  > \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  > Quo\n  >\n  > New\n\n  Tail\n- Sibling\n"),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", 0, 5, "- Parent\n\n  > \u{200b}\n  >\n  > \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  > \u{200b}\n  >\n  > New\n\n  Tail\n- Sibling\n"),
            ("- # **Heading**\n- Sibling\n", "Heading", 2, 2, "- # **He**\n  # **ing**\n- Sibling\n", "- # **He**\n  # **Newing**\n- Sibling\n"),
            ("> 9. ## 😀Plan\n> 10. Sibling\n", "😀Plan", 2, 2, "> 9. ## 😀\n>    ## an\n> 10. Sibling\n", "> 9. ## 😀\n>    ## Newan\n> 10. Sibling\n")
        ] { for ending in ["\n", "\r\n", "\r"] {
            let source = input.replacingOccurrences(of: "\n", with: ending), expected = split.replacingOccurrences(of: "\n", with: ending), typed = typed.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let body = (view.string as NSString).range(of: word)
                guard body.location != NSNotFound else { XCTFail("Missing selected Return endpoint"); return }
                let selection = NSRange(location: body.location + offset, length: length)
                view.setSelectedRange(selection); view.insertNewline(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected, "Selected Return: \(source)")
                XCTAssertEqual(tree(coordinator.lastMarkdown), tree(expected))
                let after = NSRange(location: selection.location + 1, length: 0)
                XCTAssertEqual(view.selectedRange(), after)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), after)
                view.insertText("New", replacementRange: after)
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                XCTAssertEqual(tree(coordinator.lastMarkdown), tree(typed))
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(typed)), typed)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } }
        for (input, first, offset, last, through, split, typed, advance) in [
            ("- Parent\n\n  ## Heading\n\n  Tail", "Heading", 3, "Tail", 4, "- Parent\n\n  ## Hea\n  \u{200b}\n", "- Parent\n\n  ## Hea\n  New\n", 1),
            ("- Parent\n\n  ## Heading", "Parent", 3, "Heading", 7, "- Par\n- ## \n", "- Par\n- ## New\n", 3),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Parent", 3, "Tail", 2, "- Par\n- il\n- Sibling\n", "- Par\n- Newil\n- Sibling\n", 3),
            ("- # Heading\n- Sibling\n", "Heading", 3, "Sibling", 3, "- # Hea\n  # ling\n", "- # Hea\n  # Newling\n", 1),
            ("- > Quote\n- Sibling\n", "Quote", 2, "Sibling", 3, "- > Qu\n  >\n  > ling\n", "- > Qu\n  >\n  > Newling\n", 1),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", 3, "Tail", 2, "- Parent\n\n  ## Hea\n  \u{200b}\n\n  il\n- Sibling\n", "- Parent\n\n  ## Hea\n  New\n\n  il\n- Sibling\n", 1),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", 2, "Tail", 2, "- Parent\n\n  > Qu\n  >\n  > \u{200b}\n\n  il\n- Sibling\n", "- Parent\n\n  > Qu\n  >\n  > New\n\n  il\n- Sibling\n", 1),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Parent", 3, "Heading", 3, "- Par\n- ## ding\n\n  Tail\n- Sibling\n", "- Par\n- ## Newding\n\n  Tail\n- Sibling\n", 3),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Parent", 3, "Quote", 2, "- Par\n- > ote\n\n  Tail\n- Sibling\n", "- Par\n- > Newote\n\n  Tail\n- Sibling\n", 3),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", 3, "Tail", 4, "- Parent\n\n  ## Hea\n  \u{200b}\n- Sibling\n", "- Parent\n\n  ## Hea\n  New\n- Sibling\n", 1),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", 2, "Tail", 4, "- Parent\n\n  > Qu\n  >\n  > \u{200b}\n- Sibling\n", "- Parent\n\n  > Qu\n  >\n  > New\n- Sibling\n", 1),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Parent", 3, "Heading", 7, "- Par\n- ## \n\n  Tail\n- Sibling\n", "- Par\n- ## New\n\n  Tail\n- Sibling\n", 3),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Parent", 3, "Quote", 5, "- Par\n- > \u{200b}\n\n  Tail\n- Sibling\n", "- Par\n- > New\n\n  Tail\n- Sibling\n", 3),
            ("9. Parent\n\n   ## Heading\n   - Child\n\n   Tail\n10. Sibling\n", "Parent", 3, "Heading", 3, "9. Par\n10. ## ding\n    - Child\n\n    Tail\n10. Sibling\n", "9. Par\n10. ## Newding\n    - Child\n\n    Tail\n10. Sibling\n", 5),
            ("9. Parent\n\n   > Quote\n   > - Child\n   >\n   > Quoted tail\n10. Sibling\n", "Parent", 3, "Quote", 2, "9. Par\n10. > ote\n    > - Child\n    >\n    > Quoted tail\n10. Sibling\n", "9. Par\n10. > Newote\n    > - Child\n    >\n    > Quoted tail\n10. Sibling\n", 5),
            ("> 9. Parent\n>\n>    > Quote\n>    > - Child\n>    >\n>    > Quoted tail\n> 10. Sibling\n", "Parent", 3, "Quote", 2, "> 9. Par\n> 10. > ote\n>     > - Child\n>     >\n>     > Quoted tail\n> 10. Sibling\n", "> 9. Par\n> 10. > Newote\n>     > - Child\n>     >\n>     > Quoted tail\n> 10. Sibling\n", 5),
            ("9. [x] Parent\n\n   > Quote\n   > - Child\n   >\n   > Quoted tail\n10. Sibling\n", "Parent", 3, "Quote", 2, "9. [x] Par\n10. [ ] \u{200b}\n    > ote\n    > - Child\n    >\n    > Quoted tail\n10. Sibling\n", "9. [x] Par\n10. [ ] \u{200b}\n    > Newote\n    > - Child\n    >\n    > Quoted tail\n10. Sibling\n", 7),
            ("- Parent\n\n  > Quote\n  > - Child\n  >\n  > Quoted tail\n- Sibling\n", "Parent", 3, "Quote", 2, "- Par\n- > ote\n  > - Child\n  >\n  > Quoted tail\n- Sibling\n", "- Par\n- > Newote\n  > - Child\n  >\n  > Quoted tail\n- Sibling\n", 3),
            ("> - Parent\n>\n>   > Quote\n>\n>   Tail\n> - Sibling\n", "Parent", 3, "Quote", 2, "> - Par\n> - > ote\n>\n>   Tail\n> - Sibling\n", "> - Par\n> - > Newote\n>\n>   Tail\n> - Sibling\n", 3)
        ] { for ending in ["\n", "\r\n", "\r"] {
            let source = input.replacingOccurrences(of: "\n", with: ending), expected = split.replacingOccurrences(of: "\n", with: ending), typed = typed.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let raw = view.string as NSString, from = raw.range(of: first), to = raw.range(of: last)
                guard from.location != NSNotFound, to.location != NSNotFound else { XCTFail("Missing cross-block endpoints"); return }
                let selection = NSRange(location: from.location + offset, length: to.location + through - from.location - offset)
                view.setSelectedRange(selection); view.insertNewline(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected, "Cross-block Return: \(input)")
                XCTAssertEqual(tree(coordinator.lastMarkdown), tree(expected))
                let after = NSRange(location: selection.location + advance, length: 0)
                XCTAssertEqual(view.selectedRange(), after)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), after)
                view.insertText("New", replacementRange: after)
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                XCTAssertEqual(tree(coordinator.lastMarkdown), tree(typed))
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(typed)), typed)
                if input.contains("Quoted tail") {
                    let text = view.string as NSString, child = text.range(of: "Child"), tail = text.range(of: "Quoted tail")
                    guard child.location != NSNotFound, tail.location != NSNotFound,
                          let childStyle = view.attributedString().attribute(.paragraphStyle, at: child.location, effectiveRange: nil) as? NSParagraphStyle,
                          let tailStyle = view.attributedString().attribute(.paragraphStyle, at: tail.location, effectiveRange: nil) as? NSParagraphStyle else { XCTFail("Missing transferred quoted content"); return }
                    XCTAssertEqual(childStyle.firstLineHeadIndent, tailStyle.firstLineHeadIndent, accuracy: 0.01,
                                   "Selected Return must align the child with text in its new containing quote")
                }
                if first == "Parent", last == "Tail" {
                    view.insertNewline(nil)
                    let repeated = "- Par\n- New\n- il\n- Sibling\n".replacingOccurrences(of: "\n", with: ending)
                    XCTAssertEqual(coordinator.lastMarkdown, repeated, "A plain new sibling keeps ordinary list Return")
                    XCTAssertEqual(tree(coordinator.lastMarkdown), tree(repeated))
                }
            }
        } }
        for (input, split, typed, later) in [
            ("- #\n- Sibling\n", "- # \n  \u{200b}\n- Sibling\n", "- # \n  New\n- Sibling\n", false),
            ("- > \u{200b}\n- Sibling\n", "- > \u{200b}\n  >\n  > \u{200b}\n- Sibling\n", "- > \u{200b}\n  >\n  > New\n- Sibling\n", false),
            ("- Parent\n\n  ##\n\n  Tail\n- Sibling\n", "- Parent\n\n  ## \n  \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  ## \n  New\n\n  Tail\n- Sibling\n", true),
            ("- Parent\n\n  > \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  > \u{200b}\n  >\n  > \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  > \u{200b}\n  >\n  > New\n\n  Tail\n- Sibling\n", true)
        ] { for ending in ["\n", "\r\n", "\r"] {
            let source = input.replacingOccurrences(of: "\n", with: ending), expected = split.replacingOccurrences(of: "\n", with: ending), typed = typed.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let raw = view.string as NSString
                let at = later ? NSMaxRange(raw.paragraphRange(for: raw.range(of: "Parent"))) : 2
                let caret = NSRange(location: at, length: 0)
                view.setSelectedRange(caret); view.insertNewline(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected, "Empty inner Return: \(input)")
                XCTAssertEqual(tree(coordinator.lastMarkdown), tree(expected))
                let after = NSRange(location: at + 1, length: 0)
                XCTAssertEqual(view.selectedRange(), after)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), caret)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), after)
                view.insertText("New", replacementRange: after)
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                XCTAssertEqual(tree(coordinator.lastMarkdown), tree(typed))
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(typed)), typed)
            }
        } }
        // Return leaves a newly created quote leaf while retaining its empty
        // left block and the same owning item. Imported quote paragraphs above
        // keep their original within-quote Return behavior.
        for (source, formatted, splits, emptySplit) in [
            ("- # Inner\n- Sibling\n", "- > Inner\n- Sibling\n", ["- > \n\n  |Inner\n- Sibling\n", "- > In\n\n  |ner\n- Sibling\n", "- > Inner\n\n  |\u{200b}\n- Sibling\n"], "- > \n\n  |\u{200b}\n- Sibling\n"),
            ("- > Inner\n- Sibling\n", "- > > Inner\n- Sibling\n", ["- > > \n  >\n  > |Inner\n- Sibling\n", "- > > In\n  >\n  > |ner\n- Sibling\n", "- > > Inner\n  >\n  > |\u{200b}\n- Sibling\n"], "- > > \n  >\n  > |\u{200b}\n- Sibling\n"),
            ("- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", "- Parent\n\n  > Inner\n\n  Tail\n- Sibling\n", ["- Parent\n\n  > \n\n  |Inner\n\n  Tail\n- Sibling\n", "- Parent\n\n  > In\n\n  |ner\n\n  Tail\n- Sibling\n", "- Parent\n\n  > Inner\n\n  |\u{200b}\n\n  Tail\n- Sibling\n"], "- Parent\n\n  > \n\n  |\u{200b}\n\n  Tail\n- Sibling\n"),
            ("> - # Inner\n> - Sibling\n", "> - > Inner\n> - Sibling\n", ["> - > \n>\n>   |Inner\n> - Sibling\n", "> - > In\n>\n>   |ner\n> - Sibling\n", "> - > Inner\n>\n>   |\u{200b}\n> - Sibling\n"], "> - > \n>\n>   |\u{200b}\n> - Sibling\n"),
            ("- # Inner", "- > Inner", ["- > \n\n  |Inner", "- > In\n\n  |ner", "- > Inner\n\n  |\u{200b}\n"], "- > \n\n  |\u{200b}\n")
        ] { for ending in (source.contains("\n") ? ["\n", "\r\n", "\r"] : ["\n"]) { for plainFirst in (source == "- # Inner" ? [false, true] : [false]) { for position in [0, 2, 5, -1] {
            let source = source.replacingOccurrences(of: "\n", with: ending), formatted = formatted.replacingOccurrences(of: "\n", with: ending)
            let marked = (position < 0 ? emptySplit : splits[position == 0 ? 0 : position == 2 ? 1 : 2]).replacingOccurrences(of: "\n", with: ending)
            let expected = marked.replacingOccurrences(of: "|", with: ""), typed = marked.replacingOccurrences(of: "|", with: "New").replacingOccurrences(of: "\u{200b}", with: "")
            var issues: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in }, onPasteError: { issues.append($0) })) { view, coordinator, _ in
                view.setSelectedRange((view.string as NSString).range(of: "Inner"))
                if plainFirst { coordinator.action("paragraph") }
                coordinator.action("quote")
                XCTAssertEqual(coordinator.lastMarkdown, formatted)
                let word = (view.string as NSString).range(of: "Inner")
                guard word.location != NSNotFound else { XCTFail("Missing created quote"); return }
                if position < 0 {
                    view.setSelectedRange(word); view.insertText("", replacementRange: word)
                    XCTAssertEqual(coordinator.lastMarkdown, formatted.replacingOccurrences(of: "Inner", with: ""), "Clearing a quote leaf retains an empty quote without a paragraph anchor")
                }
                else { view.setSelectedRange(NSRange(location: word.location + position, length: 0)) }
                let before = coordinator.lastMarkdown, selected = view.selectedRange()
                let oldIndent = (view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? 0
                view.insertNewline(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertTrue(issues.isEmpty)
                XCTAssertEqual(tree(coordinator.lastMarkdown), tree(expected))
                let after = view.selectedRange()
                XCTAssertEqual(after.length, 0)
                XCTAssertLessThan((view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? 0, oldIndent)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), after)
                view.insertText("New", replacementRange: after); XCTAssertEqual(coordinator.lastMarkdown, typed)
                XCTAssertEqual(tree(coordinator.lastMarkdown), tree(typed))
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(typed)), typed)
            }
        } } } }

    }

    @MainActor func testCompactQuotedListHeadsKeepSeparateItemsAndPortableEdits() throws {
        let rows = [
            ("> - - [x] Child\n>     - Grandchild\n> - Sibling\n", "> - Parent\n>   - [x] Child\n>     - Grandchild\n> - Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("- > - [ ] **Child**\n  >   - Grandchild\n- Sibling\n", "- Parent\n  > - [ ] **Child**\n  >   - Grandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("> -\t-\t[x] Child\n>       - Grandchild\n> - Sibling\n", "> - Parent\n>   -   [x] Child\n>       - Grandchild\n> - Sibling\n", [nil, 0, 1, nil] as [Int?]),

            ("- - [x] Child\n    - Grandchild\n- Sibling\n", "- Parent\n  - [x] Child\n    - Grandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("- - [ ] Child\n    - Grandchild\n- Sibling\n", "- Parent\n  - [ ] Child\n    - Grandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("- - [X] **Child**\n    - Grandchild\n- Sibling\n", "- Parent\n  - [X] **Child**\n    - Grandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("-\t-\t[x] Child\n\t\t-\tGrandchild\n- Sibling\n", "-   Parent\n    -   [x] Child\n\t\t-\tGrandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),

            ("-   - Child\n      - Grandchild\n- Sibling\n", "-   Parent\n    - Child\n      - Grandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("-\t-\tChild\n\t\t-\tGrandchild\n- Sibling\n", "-   Parent\n    -   Child\n\t\t-\tGrandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("10.\t-\tChild\n        - Grandchild\n11. Sibling\n", "10. Parent\n    -   Child\n        - Grandchild\n11. Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("> -\t-\tChild\n>       - Grandchild\n> - Sibling\n", "> - Parent\n>   -   Child\n>       - Grandchild\n> - Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("-\t> -\tChild\n    >   - Grandchild\n- Sibling\n", "-   Parent\n    > - Child\n    >   - Grandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("- - # Child\n    - Grandchild\n- Sibling\n", "- Parent\n  - # Child\n    - Grandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("- > - # Child\n  >   - Grandchild\n- Sibling\n", "- Parent\n  > - # Child\n  >   - Grandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("10. > 7. ## Child\n    >    - Grandchild\n11. Sibling\n", "10. Parent\n    > 7. ## Child\n    >    - Grandchild\n11. Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("> - > - ## Child\n>   >   - Grandchild\n> - Sibling\n", "> - Parent\n>   > - ## Child\n>   >   - Grandchild\n> - Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("- - Child\n    - Grandchild\n- Sibling\n", "- Parent\n  - Child\n    - Grandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("- - - Child\n      - Grandchild\n- Sibling\n", "- Parent\n\n  - \n    - Child\n      - Grandchild\n- Sibling\n", [nil, 0, 1, 2, nil]),
            ("- > - Child\n  >   - Grandchild\n- Sibling\n", "- Parent\n  > - Child\n  >   - Grandchild\n- Sibling\n", [nil, 0, 1, nil] as [Int?]),
            ("10. > 7. Child\n    >    - Grandchild\n11. Sibling\n", "10. Parent\n    > 7. Child\n    >    - Grandchild\n11. Sibling\n", [nil, 0, 1, nil]),
            ("> - > - Child\n>   >   - Grandchild\n> - Sibling\n", "> - Parent\n>   > - Child\n>   >   - Grandchild\n> - Sibling\n", [nil, 0, 1, nil]),
            ("- > - > - Child\n  >   >   - Grandchild\n- Sibling\n", "- Parent\n  > - \n  >   > - Child\n  >   >   - Grandchild\n- Sibling\n", [nil, 0, 1, 2, nil])
        ]
        func parents(_ source: String) -> [Int?] {
            var result: [Int?] = []
            func walk(_ node: any Markup, owner: Int? = nil) {
                var current = owner
                if node is ListItem { current = result.count; result.append(owner) }
                for child in node.children { walk(child, owner: current) }
            }
            walk(Document(parsing: source)); return result
        }
        for ending in ["\n", "\r\n"] { for (raw, expanded, owners) in rows {
            let source = raw.replacingOccurrences(of: "\n", with: ending)
            let markerWidth = raw.hasPrefix("10.") ? 4 : 2
            withEditor(source) { view, coordinator in
                XCTAssertFalse(MacMarkdown.requiresSource(source), source)
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                if raw.contains("# Child") { XCTAssertFalse(view.string.contains("# Child"), "Heading syntax must render as a heading rather than literal body text") }
                if raw.contains("[x]") || raw.contains("[X]") || raw.contains("[ ]") {
                    XCTAssertTrue(view.string.contains(raw.contains("[ ]") ? "☐ Child" : "☑ Child"), "Compact task syntax must display a checkbox and retain its body")
                }
                let native = view.string as NSString
                XCTAssertEqual(native.paragraphRange(for: NSRange(location: 0, length: 0)).length, markerWidth + 1, "The empty outer item needs its own editable row")
                let word = native.range(of: "Child"), caret = NSRange(location: NSMaxRange(word), length: 0)
                view.setSelectedRange(caret); view.insertText("!", replacementRange: caret)
                let edited = source.replacingOccurrences(of: "Child", with: "Child!")
                XCTAssertEqual(coordinator.lastMarkdown, edited); XCTAssertEqual(parents(coordinator.lastMarkdown), owners)
                let after = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), caret)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, edited); XCTAssertEqual(view.selectedRange(), after)
                let clear = (view.string as NSString).range(of: "Child!")
                view.setSelectedRange(clear); view.insertText("", replacementRange: clear)
                XCTAssertFalse(coordinator.lastMarkdown.contains("Child"), "Clearing the compact child's body must commit")
                XCTAssertEqual(parents(coordinator.lastMarkdown), owners, "Empty compact heads must remain items rather than a thematic break")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, edited)
                coordinator.action("undo")
                let outer = NSRange(location: markerWidth, length: 0)
                view.setSelectedRange(outer); view.insertText("Parent", replacementRange: outer)
                XCTAssertEqual(coordinator.lastMarkdown, expanded.replacingOccurrences(of: "\n", with: ending))
                XCTAssertEqual(parents(coordinator.lastMarkdown), owners)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), outer)
            }
        } }
    }

    @MainActor func testListsInsideItemQuotesKeepTheirBodyEditsAndSourceParents() throws {
        let rows: [(source: String, ordered: String, nested: Bool)] = [
            ("- Parent\n  > Quote\n  >\n  > - Child\n- Sibling\n", "1. Parent\n   > Quote\n   >\n   > - Child!\n- Sibling\n", false),
            ("10. Parent\n    > Quote\n    >\n    > - Child\n11. Sibling\n", "1. Parent\n   > Quote\n   >\n   > - Child!\n11. Sibling\n", false),
            ("10. Parent\n    > Quote\n    >\n    > 9. Child\n11. Sibling\n", "1. Parent\n   > Quote\n   >\n   > 9. Child!\n11. Sibling\n", false),
            ("> 10. Parent\n>     > Quote\n>     >\n>     > - Child\n> 11. Sibling\n", "> 1. Parent\n>    > Quote\n>    >\n>    > - Child!\n> 11. Sibling\n", false),
            ("10. Parent\n    > Quote\n    >\n    > > - Child\n11. Sibling\n", "1. Parent\n   > Quote\n   >\n   > > - Child!\n11. Sibling\n", false),
            ("- Parent\n  > Quote\n  >\n  > - Child\n  >   - Grandchild\n- Sibling\n", "1. Parent\n   > Quote\n   >\n   > 1. Child!\n   >    - Grandchild\n- Sibling\n", true),
            ("- Parent\n  > Quote\n  >\n  > - Child\n  >   ```swift\n  >   old\n  >   ```\n  >   - Grandchild\n- Sibling\n", "1. Parent\n   > Quote\n   >\n   > 1. Child!\n   >    ```swift\n   >    old\n   >    ```\n   >    - Grandchild\n- Sibling\n", true),
            ("> 10. Parent\n>     > Quote\n>     >\n>     > 9. Child\n>     >    ```swift\n>     >    old\n>     >    ```\n> 11. Sibling\n", "> 1. Parent\n>    > Quote\n>    >\n>    > 9. Child!\n>    >    ```swift\n>    >    old\n>    >    ```\n> 11. Sibling\n", false),
            ("- Parent\n  > Quote\n  >\n  > - Child\n  >\n  >   | A | B |\n  >   | --- | --- |\n  >   | old | Other |\n- Sibling\n", "1. Parent\n   > Quote\n   >\n   > - Child!\n   >\n   >   | A | B |\n   >   | --- | --- |\n   >   | old | Other |\n- Sibling\n", false)
        ]
        func parents(_ source: String) -> [Int?] {
            var result: [Int?] = []
            func collect(_ node: any Markup, parent: Int? = nil) {
                var owner = parent
                if node is ListItem { owner = result.count; result.append(parent) }
                for child in node.children { collect(child, parent: owner) }
            }
            collect(Document(parsing: source)); return result
        }
        func checkAlignment(_ view: NSTextView, extraQuote: Bool, grandchild: Bool) {
            let text = view.string as NSString
            let quote = text.range(of: "Quote"), child = text.range(of: "Child")
            guard quote.location != NSNotFound, child.location != NSNotFound,
                  let quoteStyle = view.attributedString().attribute(.paragraphStyle, at: quote.location, effectiveRange: nil) as? NSParagraphStyle,
                  let childStyle = view.attributedString().attribute(.paragraphStyle, at: child.location, effectiveRange: nil) as? NSParagraphStyle else {
                XCTFail("Missing rendered quote/list paragraphs"); return
            }
            XCTAssertEqual(childStyle.firstLineHeadIndent, quoteStyle.firstLineHeadIndent + (extraQuote ? 18 : 0), accuracy: 0.01,
                           "The child marker aligns with text in its containing quote")
            if grandchild {
                let nested = text.range(of: "Grandchild")
                guard nested.location != NSNotFound,
                      let style = view.attributedString().attribute(.paragraphStyle, at: nested.location, effectiveRange: nil) as? NSParagraphStyle else { XCTFail("Missing rendered grandchild"); return }
                XCTAssertGreaterThan(style.firstLineHeadIndent, childStyle.firstLineHeadIndent)
            }
        }
        for ending in ["\n", "\r\n"] { for row in rows {
            let source = row.source.replacingOccurrences(of: "\n", with: ending)
            let expected = source.replacingOccurrences(of: "Child\n", with: "Child!\n").replacingOccurrences(of: "Child\r\n", with: "Child!\r\n")
            let ordered = row.ordered.replacingOccurrences(of: "\n", with: ending)
            let expectedParents: [Int?] = row.nested ? [nil, 0, 1, nil] : [nil, 0, nil]
            withEditor(source) { view, coordinator in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                XCTAssertFalse(view.string.contains(">"), "Quote markers are structure, not body text")
                checkAlignment(view, extraQuote: row.source.contains("> > -"), grandchild: row.nested)
                XCTAssertEqual(MacMarkdown.nativeListItems(in: view.attributedString())?.map(\.parent), expectedParents)
                let child = (view.string as NSString).range(of: "Child")
                guard child.location != NSNotFound else { XCTFail("Missing child body"); return }
                let selected = NSRange(location: NSMaxRange(child), length: 0)
                view.setSelectedRange(selected); view.insertText("!", replacementRange: selected)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(parents(coordinator.lastMarkdown), expectedParents)
                let after = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), after)
                let parent = (view.string as NSString).range(of: "Parent")
                let last = (view.string as NSString).range(of: "Child")
                let formatSelection = NSRange(location: parent.location + 1, length: row.nested ? last.location - parent.location : 0)
                view.setSelectedRange(formatSelection); coordinator.action("ordered")
                XCTAssertEqual(coordinator.lastMarkdown, ordered)
                XCTAssertEqual(parents(coordinator.lastMarkdown), expectedParents)
                checkAlignment(view, extraQuote: row.source.contains("> > -"), grandchild: row.nested)
                let formattedSelection = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), formatSelection)
                checkAlignment(view, extraQuote: row.source.contains("> > -"), grandchild: row.nested)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, ordered); XCTAssertEqual(view.selectedRange(), formattedSelection)
                checkAlignment(view, extraQuote: row.source.contains("> > -"), grandchild: row.nested)
                if !row.nested {
                    view.insertText("Z", replacementRange: formattedSelection)
                    XCTAssertEqual(coordinator.lastMarkdown, ordered.replacingOccurrences(of: "Parent", with: "PZarent"))
                    XCTAssertEqual(parents(coordinator.lastMarkdown), expectedParents)
                }
            }
        } }
    }

    @MainActor func testItemOwnedHeadingsAndQuotesKeepRolesThroughBodyEditsAndMarkerWidthChanges() throws {
        func roles(_ source: String) -> [String] {
            var result: [String] = [], next = 0
            func walk(_ node: any Markup, owner: Int? = nil) {
                var owner = owner
                if node is ListItem { owner = next; next += 1 }
                if let owner, let heading = node as? Heading { result.append("h\(heading.level):\(owner)") }
                if let owner, node is BlockQuote { result.append("quote:\(owner)") }
                for child in node.children { walk(child, owner: owner) }
            }
            walk(Document(parsing: source)); return result
        }
        let rows: [(source: String, body: String, head: String, level: Int, edited: String, ordered: String)] = [
            ("- # Heading\n- Sibling\n", "Heading", "Heading", 1, "- # Heading!\n- Sibling\n", "1. # Heading!\n- Sibling\n"),
            ("- Heading\n  - \n- Sibling\n", "Heading", "Heading", 2, "- ## Heading!\n- Sibling\n", "1. ## Heading!\n- Sibling\n"),
            ("- Parent\n\n  Heading\n  -\n- Sibling\n", "Heading", "Parent", 2, "- Parent\n\n  ## Heading!\n- Sibling\n", "1. Parent\n\n   ## Heading!\n- Sibling\n"),
            ("- \n  ## Heading\n- Sibling\n", "Heading", "Heading", 2, "- \n  ## Heading!\n- Sibling\n", "1. \n   ## Heading!\n- Sibling\n"),
            ("- \n  > Quote\n- Sibling\n", "Quote", "Quote", 0, "- \n  > Quote!\n- Sibling\n", "1. \n   > Quote!\n- Sibling\n"),
            ("- > Quote\n- Sibling\n", "Quote", "Quote", 0, "- > Quote!\n- Sibling\n", "1. > Quote!\n- Sibling\n"),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", "Parent", 2, "- Parent\n\n  ## Heading!\n\n  Tail\n- Sibling\n", "1. Parent\n\n   ## Heading!\n\n   Tail\n- Sibling\n"),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", "Parent", 0, "- Parent\n\n  > Quote!\n\n  Tail\n- Sibling\n", "1. Parent\n\n   > Quote!\n\n   Tail\n- Sibling\n"),
            ("> - Parent\n>\n>   ## Heading\n>\n>   Tail\n> - Sibling\n", "Heading", "Parent", 2, "> - Parent\n>\n>   ## Heading!\n>\n>   Tail\n> - Sibling\n", "> 1. Parent\n>\n>    ## Heading!\n>\n>    Tail\n> - Sibling\n"),
            ("- Parent\n\n  > ## Heading\n  > Text\n- Sibling\n", "Heading", "Parent", 2, "- Parent\n\n  > ## Heading!\n  > Text\n- Sibling\n", "1. Parent\n\n   > ## Heading!\n   > Text\n- Sibling\n"),
            ("- Parent\n\n  Heading\n  ===\n\n  Tail\n- Sibling\n", "Heading", "Parent", 1, "- Parent\n\n  # Heading!\n\n  Tail\n- Sibling\n", "1. Parent\n\n   # Heading!\n\n   Tail\n- Sibling\n"),
            ("- Root\n  - ## Heading\n  - Peer\n- Sibling\n", "Heading", "Heading", 2, "- Root\n  - ## Heading!\n  - Peer\n- Sibling\n", "- Root\n  1. ## Heading!\n  - Peer\n- Sibling\n")
        ]
        for ending in ["\n", "\r\n"] { for row in rows {
            let source = row.source.replacingOccurrences(of: "\n", with: ending), edited = row.edited.replacingOccurrences(of: "\n", with: ending), ordered = row.ordered.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                XCTAssertFalse(view.string.contains("# "), source)
                XCTAssertFalse(view.string.contains("> "), source)
                let body = (view.string as NSString).range(of: row.body)
                guard body.location != NSNotFound else { XCTFail("Missing visible body: \(source)"); return }
                if row.level > 0 {
                    let font = view.attributedString().attribute(.font, at: body.location, effectiveRange: nil) as? NSFont
                    XCTAssertEqual(font?.pointSize, MacMarkdown.font(String(repeating: "#", count: row.level) + " ").pointSize)
                }
                view.setSelectedRange(NSRange(location: NSMaxRange(body), length: 0)); view.insertText("!", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, edited, source)
                XCTAssertEqual(roles(coordinator.lastMarkdown), roles(source))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, edited)
                let head = (view.string as NSString).range(of: row.head)
                guard head.location != NSNotFound else { XCTFail("Missing list head"); return }
                let selected = NSRange(location: head.location + 1, length: 0)
                view.setSelectedRange(selected); coordinator.action("ordered")
                XCTAssertEqual(coordinator.lastMarkdown, ordered, source)
                XCTAssertEqual(roles(coordinator.lastMarkdown), roles(source))
                let after = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, edited); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, ordered); XCTAssertEqual(view.selectedRange(), after)
                view.insertText("Z", replacementRange: after)
                let typedHead = String(row.head.prefix(1)) + "Z" + row.head.dropFirst()
                XCTAssertEqual(coordinator.lastMarkdown, ordered.replacingOccurrences(of: row.head, with: typedHead))
                XCTAssertEqual(roles(coordinator.lastMarkdown), roles(source))
                if row.level > 0 {
                    let heading = (view.string as NSString).range(of: row.head == row.body ? typedHead : row.body)
                    guard heading.location != NSNotFound else { XCTFail("Missing styled heading after typing"); return }
                    let font = view.attributedString().attribute(.font, at: heading.location, effectiveRange: nil) as? NSFont
                    XCTAssertEqual(font?.pointSize, MacMarkdown.font(String(repeating: "#", count: row.level) + " ").pointSize)
                }
            }
        } }
        for ending in ["\n", "\r\n"] {
            for (source, word, expected) in [
                ("- #\n- Sibling\n", "Heading", "- # Heading\n- Sibling\n"),
                ("- ## \n- Sibling\n", "Heading", "- ## Heading\n- Sibling\n"),
                ("> - ###\n> - Sibling\n", "Heading", "> - ### Heading\n> - Sibling\n"),
                ("- Root\n  - ##\n- Sibling\n", "Heading", "- Root\n  - ## Heading\n- Sibling\n"),
                ("- >\n- Sibling\n", "Quote", "- > Quote\n- Sibling\n"),
                ("- #\n  ##\n- Sibling\n", "Heading", "- # Heading\n  ##\n- Sibling\n"),
                ("- ##\n  ##\n- Sibling\n", "Heading", "- ## Heading\n  ##\n- Sibling\n")
            ] {
                let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
                withEditor(source) { view, coordinator in
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                    let empty = (view.string as NSString).range(of: "• \n")
                    guard empty.location != NSNotFound else { XCTFail("An empty inner block must hide its syntax: \(source)"); return }
                    view.setSelectedRange(NSRange(location: empty.location + 2, length: 0)); view.insertText(word, replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, expected)
                    XCTAssertEqual(roles(coordinator.lastMarkdown), roles(source))
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                }
            }
        }
        // An empty EOF block still needs a real editable text-system row.
        // Use the production view here so Cmd-End and input normalization run.
        for (input, nativePrefix, filled, block, split) in [
            ("- Parent\n\n  ##", "• Parent\n", "- Parent\n\n  ## Refill", "## ", "- Parent\n\n  ## Ref\n  ## ill" as String?),
            ("- Parent\n\n  >", "• Parent\n", "- Parent\n\n  > Refill", "> ", "- Parent\n\n  > Ref\n\n  ill"),
            ("- Parent\n\n  > \u{200b}", "• Parent\n", "- Parent\n\n  > Refill", "> ", "- Parent\n\n  > Ref\n  >\n  > ill"),
            ("- Root\n  - Parent\n\n    ###", "• Root\n• Parent\n", "- Root\n  - Parent\n\n    ### Refill", "### ", "- Root\n  - Parent\n\n    ### Ref\n    ### ill"),
            ("> - Parent\n>\n>   ##", "• Parent\n", "> - Parent\n>\n>   ## Refill", "## ", "> - Parent\n>\n>   ## Ref\n>   ## ill"),
            ("- Parent\n\n  > ##", "• Parent\n", "- Parent\n\n  > ## Refill", "## ", "- Parent\n\n  > ## Ref\n  > ## ill"),
            ("- Parent\n\n  ##\n  ###", "• Parent\n\n", "- Parent\n\n  ##\n  ### Refill", "### ", "- Parent\n\n  ##\n  ### Ref\n  ### ill"),
            ("##", "", "## Refill", "## ", nil),
            (">", "", ">Refill", "> ", nil),
            ("> ##", "", "> ## Refill", "## ", nil),
            ("\u{200b}", "", "Refill", "", nil)
        ] { for ending in (input.contains("\n") ? ["\n", "\r\n", "\r"] : ["\n"]) {
            let source = input.replacingOccurrences(of: "\n", with: ending), filled = filled.replacingOccurrences(of: "\n", with: ending)
            try autoreleasepool {
                try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source, "An unchanged empty EOF block must keep its source")
                    XCTAssertEqual(view.string, nativePrefix + "\n", "The last block needs its own editable row")
                    view.moveToEndOfDocument(nil)
                    let caret = NSRange(location: nativePrefix.utf16.count, length: 0)
                    XCTAssertEqual(view.selectedRange(), caret, "Cmd-End must land inside the final block")
                    XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, MacMarkdown.font(block).pointSize)
                    view.insertText("Refill", replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, filled, "Refilling keeps the role and does not add a source terminator")
                    XCTAssertEqual(roles(coordinator.lastMarkdown), roles(source))
                    XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), filled)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), caret)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, filled)
                    if let split {
                        let caret = NSRange(location: nativePrefix.utf16.count + 3, length: 0)
                        view.setSelectedRange(caret); view.insertNewline(nil)
                        let expected = split.replacingOccurrences(of: "\n", with: ending)
                        XCTAssertEqual(coordinator.lastMarkdown, expected, "A real Return adds only its separator, preserving the final source ending")
                        XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), expected)
                        let after = NSRange(location: caret.location + 1, length: 0)
                        XCTAssertEqual(view.selectedRange(), after)
                        coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, filled); XCTAssertEqual(view.selectedRange(), caret)
                        coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), after)
                    }
                }
            }
        } }
    }

    func testRichAdmissionKeepsUnsupportedIndentationAndContainersInSource() {
        for source in ["[target]: https://example.com\n\n[Link][target]\n"] { XCTAssertFalse(MacMarkdown.requiresSource(source), source) } // Rich text is the default; Source is only an explicit choice.
        XCTAssertFalse(MacMarkdown.requiresSource("- P\n\nOutside\n\n  Kept\n"))
        for source in ["- P\n  > Quote\n  >\n  > - Child\n", "- P\n  > Quote\n", "- # Heading\n", "- Parent\n\n  ## Later heading\n", "- P\n  ```\n  code\n  ```\n", "***\r", "> ***\r", "Before\r***\rAfter\r", "- P\n\nOutside\n\n\tKept\n", "> - P\n>\n> Outside\n>\n>   Kept\n", "Kept\n===\n", "> Kept\n> ---\n"] { XCTAssertFalse(MacMarkdown.requiresSource(source), source) }
    }
    @MainActor func testIndependentParagraphOwnershipSurvivesBoundaryEdits() {
        func ownership(_ source: String) -> (text: String, depth: Int, list: Bool, kind: String, level: Int)? {
            var found: [(String, Int, Bool, String, Int)] = []
            func walk(_ node: any Markup, depth: Int = 0, list: Bool = false) {
                let depth = depth + (node is BlockQuote ? 1 : 0), list = list || node is ListItem
                if let paragraph = node as? Paragraph, paragraph.plainText.contains("Kept") { found.append((paragraph.plainText, depth, list, "paragraph", 0)) }
                if let heading = node as? Heading, heading.plainText.contains("Kept") { found.append((heading.plainText, depth, list, "heading", heading.level)) }
                if let html = node as? HTMLBlock, html.rawHTML.contains("Kept") { found.append((html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines), depth, list, "html", 0)) }
                for child in node.children { walk(child, depth: depth, list: list) }
            }
            walk(Document(parsing: source)); XCTAssertEqual(found.count, 1)
            return found.first
        }
        for (source, expected, quoteDepth) in [
            ("> - Parent\n>\n> Outside\n>   Kept tail\n", "> - Parent\n>\n> \n> Kept tail\n", 1),
            ("- Parent\n\nOutside\n\nKept heading\n===\n", "- Parent\n\n\n\nKept heading\n===\n", 0),
            ("> - Parent\n>\n> Outside\n>\n>   Kept heading\n>   ===\n", "> - Parent\n>\n> \n>\n> Kept heading\n>   ===\n", 1),
            ("> - Parent\n>\n> Outside\n>\n>   Kept heading\n>   ---\n", "> - Parent\n>\n> \n>\n> Kept heading\n>   ---\n", 1),
            ("> - Parent\n>\n> Outside\n>\n>   <img src=\"./x.png\" alt=\"Kept image\" width=\"128\" />\n", "> - Parent\n>\n> \n>\n> <img src=\"./x.png\" alt=\"Kept image\" width=\"128\" />\n", 1),
            ("> - Parent\n>\n> Outside\n>\n>   > Kept tail\n", "> - Parent\n>\n> \n>\n> > Kept tail\n", 2),
            ("> - Parent\n>\n> Outside\n>\n>   &#32;Kept tail\n", "> - Parent\n>\n> \n>\n> &#32;Kept tail\n", 1),
            ("> - Parent\n>\n> Outside\n>\n>   ## Kept heading\n", "> - Parent\n>\n> \n>\n> ## Kept heading\n", 1),
            ("> - Parent\n>\n> Outside\n>\n>   Kept *emphasis* [link](https://e/) ![img](./x.png)\n", "> - Parent\n>\n> \n>\n> Kept *emphasis* [link](https://e/) ![img](./x.png)\n", 1),
            ("> - Parent\n>\n> Outside\n>\n>   Kept [link](https://e/) <img src=\"./x.png\" alt=\"img\" width=\"128\" />\n", "> - Parent\n>\n> \n>\n> Kept [link](https://e/) <img src=\"./x.png\" alt=\"img\" width=\"128\" />\n", 1),
            ("> - Parent\n>\n> Outside\n>\n>   Kept wrapped\n>   more text\n", "> - Parent\n>\n> \n>\n> Kept wrapped\n>   more text\n", 1),
            ("- Parent\n\nOutside\n\n  Kept tail\n", "- Parent\n\n\n\nKept tail\n", 0),
            ("- Parent\n\nOutside\n\n   Kept tail\n", "- Parent\n\n\n\nKept tail\n", 0),
            ("1. Parent\n\nOutside\n\n   Kept tail\n", "1. Parent\n\n\n\nKept tail\n", 0),
            ("- Parent\n  - Child\n\nOutside\n\n  Kept tail\n", "- Parent\n  - Child\n\n\n\nKept tail\n", 0),
            ("> - Parent\n>\n> Outside\n>\n>   Kept tail\n", "> - Parent\n>\n> \n>\n> Kept tail\n", 1),
            (">> - Parent\n>>\n>> Outside\n>>\n>>   Kept tail\n", ">> - Parent\n>>\n>> \n>>\n>> Kept tail\n", 2),
            ("- Parent\n\nOutside\n\n  ## Kept heading\n", "- Parent\n\n\n\n## Kept heading\n", 0),
            ("- Parent\n\nOutside\n\n  Kept *emphasis* [link](https://e/) ![img](./x.png)\n", "- Parent\n\n\n\nKept *emphasis* [link](https://e/) ![img](./x.png)\n", 0),
            ("- Parent\n\nOutside\n\n  Kept wrapped\n  more text\n", "- Parent\n\n\n\nKept wrapped\n  more text\n", 0),
            ("- Parent\n\nOutside\n\n  Kept hard  \n  more text\n", "- Parent\n\n\n\nKept hard  \n  more text\n", 0)
        ] { for ending in ["\n", "\r\n"] { for gesture in ["body", "row", "span", "backspace"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            let originalRole = ownership(source)
            let keptText = ownership(expected)?.text
            XCTAssertEqual(originalRole?.depth, quoteDepth); XCTAssertEqual(originalRole?.list, false)
            withEditor(source) { view, coordinator in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source, "Untouched indentation remains byte exact")
                if let level = originalRole?.level, level > 0 {
                    let title = (view.string as NSString).range(of: "Kept")
                    XCTAssertEqual((view.attributedString().attribute(.font, at: title.location, effectiveRange: nil) as? NSFont)?.pointSize, MacMarkdown.font(String(repeating: "#", count: level) + " ").pointSize)
                }
                let originalVisible = view.string
                let raw = view.string as NSString, word = raw.range(of: "Outside"), row = raw.paragraphRange(for: word)
                let nativeKept = raw.range(of: "Kept"), kept = nativeKept.location == NSNotFound ? raw.range(of: "\u{fffc}") : nativeKept
                let keptRow = raw.paragraphRange(for: kept)
                let sourceText = source as NSString, sourceWord = sourceText.range(of: "Outside"), sourceRow = sourceText.paragraphRange(for: sourceWord)
                let sourceKept = sourceText.paragraphRange(for: sourceText.range(of: "Kept"))
                let outsidePrefix = sourceText.substring(with: NSRange(location: sourceRow.location, length: sourceWord.location - sourceRow.location))
                let suffixStart = sourceKept.location - "Outside".utf16.count
                var expectedSource = expected
                let selection: NSRange
                if gesture == "body" { selection = word }
                else if gesture == "span" { selection = NSRange(location: row.location, length: keptRow.location - row.location) }
                else { selection = row }
                if gesture == "row" {
                    let value = NSMutableString(string: expected)
                    value.deleteCharacters(in: NSRange(location: sourceRow.location, length: outsidePrefix.utf16.count + ending.utf16.count)); expectedSource = value as String
                } else if gesture == "span" {
                    let value = NSMutableString(string: expected)
                    value.deleteCharacters(in: NSRange(location: sourceRow.location, length: suffixStart - sourceRow.location)); expectedSource = value as String
                } else if gesture == "backspace" {
                    let blankBefore = sourceText.paragraphRange(for: NSRange(location: sourceRow.location - 1, length: 0))
                    expectedSource = sourceText.substring(to: blankBefore.location) + outsidePrefix + ending + (expected as NSString).substring(from: suffixStart)
                }
                view.setSelectedRange(selection); view.insertText("", replacementRange: selection)
                var undoSteps = 1
                if gesture == "backspace" {
                    while true {
                        let value = view.string as NSString, word = value.range(of: "Kept")
                        let content = word.location == NSNotFound ? value.range(of: "\u{fffc}") : word
                        let current = value.paragraphRange(for: content)
                        guard current.location > 0 else { break }
                        let previous = value.paragraphRange(for: NSRange(location: current.location - 1, length: 0))
                        guard value.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
                        view.setSelectedRange(NSRange(location: current.location, length: 0)); view.deleteBackward(nil); undoSteps += 1
                    }
                }
                XCTAssertEqual(coordinator.lastMarkdown, expectedSource, gesture)
                let role = ownership(coordinator.lastMarkdown)
                XCTAssertEqual(role?.text, keptText); XCTAssertEqual(role?.depth, quoteDepth); XCTAssertEqual(role?.list, false); XCTAssertEqual(role?.kind, originalRole?.kind); XCTAssertEqual(role?.level, originalRole?.level)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), expectedSource)
                let afterSelection = view.selectedRange()
                if gesture != "backspace" { XCTAssertEqual(afterSelection, NSRange(location: selection.location, length: 0)) }
                let finalVisible = view.string
                var undoCount = 0
                while undoCount < undoSteps, view.string != originalVisible || coordinator.lastMarkdown != source { coordinator.action("undo"); undoCount += 1 }
                XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.string, originalVisible)
                if gesture != "backspace" { XCTAssertEqual(view.selectedRange(), selection) }
                for _ in 0..<undoCount { coordinator.action("redo") }
                XCTAssertEqual(coordinator.lastMarkdown, expectedSource); XCTAssertEqual(view.string, finalVisible); XCTAssertEqual(view.selectedRange(), afterSelection)
                if originalRole?.kind == "html" { return }
                let text = (view.string as NSString).range(of: "Kept")
                guard text.location != NSNotFound else { XCTFail("The kept paragraph must remain editable"); return }
                view.setSelectedRange(NSRange(location: NSMaxRange(text), length: 0)); view.insertText("!", replacementRange: view.selectedRange())
                let edited = ownership(coordinator.lastMarkdown)
                XCTAssertEqual(edited?.text, keptText?.replacingOccurrences(of: "Kept", with: "Kept!")); XCTAssertEqual(edited?.depth, quoteDepth); XCTAssertEqual(edited?.list, false); XCTAssertEqual(edited?.kind, originalRole?.kind); XCTAssertEqual(edited?.level, originalRole?.level)
                if source.contains("![img]") {
                    var images: [Markdown.Image] = [], links: [Markdown.Link] = []
                    func collect(_ node: any Markup) {
                        if let image = node as? Markdown.Image { images.append(image) }
                        if let link = node as? Markdown.Link { links.append(link) }
                        for child in node.children { collect(child) }
                    }
                    collect(Document(parsing: coordinator.lastMarkdown))
                    XCTAssertEqual(images.map { $0.source ?? "" }, ["./x.png"]); XCTAssertEqual(images.map(\.plainText), ["img"])
                    XCTAssertEqual(links.map { $0.destination ?? "" }, ["https://e/"]); XCTAssertEqual(links.map(\.plainText), ["link"])
                }
                if source.contains("width=\"128\"") { XCTAssertTrue(coordinator.lastMarkdown.contains("<img src=\"./x.png\" alt=\"img\" width=\"128\" />")) }
            }
        } } }
        withEditor("> - Parent\n>\n> Kept tail\n") { view, coordinator in
            let first = (view.string as NSString).range(of: "Kept")
            view.setSelectedRange(NSRange(location: first.location, length: 0)); view.deleteBackward(nil)
            XCTAssertEqual(ownership(coordinator.lastMarkdown)?.list, false)
            let kept = (view.string as NSString).range(of: "Kept")
            view.setSelectedRange(NSRange(location: kept.location, length: 0)); view.deleteBackward(nil)
            XCTAssertEqual(coordinator.lastMarkdown, "> - ParentKept tail\n", "Deleting the paragraph boundary intentionally joins the item")
        }
        // A newly empty native list head needs its own source boundary. That
        // late recovery must not adopt the independent paragraph that follows.
        withEditor("> Intro\n>\n> - Item\n>\n> Outside\n>\n>   Kept tail\n") { view, coordinator in
            let item = (view.string as NSString).range(of: "Item")
            view.setSelectedRange(item); view.insertText("", replacementRange: item)
            let outside = (view.string as NSString).range(of: "Outside"), outsideRow = (view.string as NSString).paragraphRange(for: outside)
            view.setSelectedRange(outsideRow); view.insertText("", replacementRange: outsideRow)
            while true {
                let raw = view.string as NSString, kept = raw.paragraphRange(for: raw.range(of: "Kept"))
                let before = raw.paragraphRange(for: NSRange(location: kept.location - 1, length: 0))
                guard raw.substring(with: before).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
                view.setSelectedRange(before); view.insertText("", replacementRange: before)
            }
            let raw = view.string as NSString, marker = raw.range(of: "• "), row = raw.paragraphRange(for: marker)
            let before = raw.paragraphRange(for: NSRange(location: row.location - 1, length: 0))
            view.setSelectedRange(before); view.insertText("", replacementRange: before)
            XCTAssertEqual(ownership(coordinator.lastMarkdown)?.list, false, coordinator.lastMarkdown)
            var items = 0
            func count(_ node: any Markup) { if node is ListItem { items += 1 }; for child in node.children { count(child) } }
            count(Document(parsing: coordinator.lastMarkdown)); XCTAssertEqual(items, 1)
        }
        for affected in [false, true] { for ending in ["\n", "\r\n"] {
            let main = affected ? "> 9. Parent\n>    - Child\n>\n> Outside\n>\n>    Kept tail\n" : "> - Parent\n>\n> Outside\n>\n>   Kept tail\n\nTop\n\n9. Other\n   - Child\n"
            let source = main.replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            withEditor(source, onPasteError: { issues.append($0) }) { view, coordinator in
                let child = (view.string as NSString).range(of: "Child"), row = (view.string as NSString).paragraphRange(for: child)
                view.setSelectedRange(NSRange(location: row.location, length: 0)); view.insertNewline(nil)
                let before = coordinator.lastMarkdown, selected = (view.string as NSString).range(of: "Outside")
                view.setSelectedRange(selected); view.insertText("", replacementRange: selected)
                if affected {
                    XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.selectedRange(), selected)
                    XCTAssertEqual(issues, ["This list needs Markdown source editing before this selection can preserve its item relationships."])
                } else {
                    let expected = before.replacingOccurrences(of: "> Outside", with: "> ").replacingOccurrences(of: ">   Kept", with: "> Kept")
                    XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertTrue(issues.isEmpty)
                    XCTAssertEqual(ownership(coordinator.lastMarkdown)?.list, false)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.selectedRange(), selected)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                }
            }
        } }

    }
    @MainActor func testReplacingListRelatedSelectionsKeepsSurvivingContentAndOwners() {
        func parents(_ source: String) -> [Int?] {
            var result: [Int?] = []
            func collect(_ node: any Markup, owner: Int? = nil) {
                var owner = owner
                if node is ListItem { let index = result.count; result.append(owner); owner = index }
                for child in node.children { collect(child, owner: owner) }
            }
            collect(Document(parsing: source)); return result
        }
        // Removing an inner item head must preserve its unselected quoted
        // tail, just as whole-head deletion does. Public admission stays guarded.
        for ending in ["\n", "\r\n"] { for replacement in ["", "X"] {
            let source = "- Root\n  > - Parent\n  >   - Child\n  >\n  >   Tail\n- Sibling\n".replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let raw = view.string as NSString, root = raw.range(of: "Root"), parent = raw.range(of: "Parent")
                guard root.location != NSNotFound, parent.location != NSNotFound else { XCTFail("Selection endpoints must exist"); return }
                let selection = NSRange(location: root.location + 2, length: parent.location + 3 - root.location - 2)
                view.setSelectedRange(selection); view.insertText(replacement, replacementRange: selection)
                var tailQuotes: [Int] = []
                func collect(_ node: any Markup, quotes: Int = 0) {
                    let quotes = quotes + (node is BlockQuote ? 1 : 0)
                    if let paragraph = node as? Paragraph, paragraph.plainText == "Tail" { tailQuotes.append(quotes) }
                    for child in node.children { collect(child, quotes: quotes) }
                }
                collect(Document(parsing: coordinator.lastMarkdown))
                XCTAssertEqual(tailQuotes, [1], "Unselected Tail must retain its enclosing quote: \(coordinator.lastMarkdown)")
                let saved = coordinator.lastMarkdown
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
            }
        } }
        for (source, first, from, last, through, deleted, replaced, owners, _, caretShift, checkTypingStyle) in [
            ("- ## Heading\n\n  Tail\n- Sibling\n", "Heading", 3, "Tail", 2, "- ## Heail\n- Sibling\n", "- ## HeaXil\n- Sibling\n", [nil, nil] as [Int?], true, 0, true),
            ("- > Quote\n\n  Tail\n- Sibling\n", "Quote", 3, "Tail", 2, "- > Quoil\n- Sibling\n", "- > QuoXil\n- Sibling\n", [nil, nil] as [Int?], true, 0, true),
            ("- ## Heading\n\n  > Quote\n- Sibling\n", "Heading", 3, "Quote", 3, "- ## Heate\n- Sibling\n", "- ## HeaXte\n- Sibling\n", [nil, nil] as [Int?], true, 0, true),
            ("- > Quote\n\n  ## Heading\n- Sibling\n", "Quote", 3, "Heading", 3, "- > Quoding\n- Sibling\n", "- > QuoXding\n- Sibling\n", [nil, nil] as [Int?], true, 0, true),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", 3, "Tail", 2, "- Parent\n\n  ## Heail\n- Sibling\n", "- Parent\n\n  ## HeaXil\n- Sibling\n", [nil, nil] as [Int?], true, 0, true),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", 3, "Tail", 2, "- Parent\n\n  > Quoil\n- Sibling\n", "- Parent\n\n  > QuoXil\n- Sibling\n", [nil, nil] as [Int?], true, 0, true),
            ("- Parent\n  - Child\n    - Grand\n- Sibling\n", "Parent", -1, "Child", 2, "- ild\n  - Grand\n- Sibling\n", "- Xild\n  - Grand\n- Sibling\n", [nil, 0, nil] as [Int?], true, 1, true),
            ("- Parent\n  - Child\n    - Grand\n- Sibling\n", "Parent", 3, "Child", -1, "- ParChild\n  - Grand\n- Sibling\n", "- ParXChild\n  - Grand\n- Sibling\n", [nil, 0, nil], true, 0, true),
            ("- Parent\n  - Child\n    - Grand\n- Sibling\n", "Parent", -1, "Child", -1, "- Child\n  - Grand\n- Sibling\n", "- XChild\n  - Grand\n- Sibling\n", [nil, 0, nil], true, 1, true),
            ("1. Parent\n   1. Child\n      - Grand\n2. Sibling\n", "Parent", -2, "Child", -1, "1. Child\n   1. Grand\n2. Sibling\n", "1. XChild\n   1. Grand\n2. Sibling\n", [nil, 0, nil], true, 2, true),
            ("Intro\n\n- Parent\n  - Child\n- Sibling\n", "Intro", 2, "Parent", -1, "InParent\n\n- Child\n- Sibling\n", "InXParent\n\n- Child\n- Sibling\n", [nil, nil], true, 0, true),
            ("> - Parent\n>   - Child\n> - Sibling\n", "Parent", -1, "Child", 2, "> - ild\n> - Sibling\n", "> - Xild\n> - Sibling\n", [nil, nil], true, 1, true),
            ("- Parent\n- Sibling\n", "Parent", -1, "Parent", 3, "- ent\n- Sibling\n", "- Xent\n- Sibling\n", [nil, nil], true, 1, true),
            ("- [x] Parent\n- [ ] Sibling\n", "Parent", -1, "Sibling", -1, "- [x] Sibling\n", "- [x] XSibling\n", [nil], true, 1, true),
            ("- Parent\n- Sibling\n", "Parent", -1, "Parent", 0, "- Parent\n- Sibling\n", "- XParent\n- Sibling\n", [nil, nil], true, 1, true),
            ("Intro\n\n5. a1\n6. b1\n", "Intro", 2, "a1", 1, "In1\n\n5. b1\n", "InX1\n\n5. b1\n", [nil] as [Int?], true, 0, false),
            ("Intro\n\n5. a1\n6. b1\n1) c1\n", "Intro", 2, "a1", 1, "In1\n\n5. b1\n6. c1\n", "InX1\n\n5. b1\n6. c1\n", [nil, nil], true, 0, false),
            ("- a1\n  1. b1\n\n  Tail\n- c1\n  - [x] d1\n", "Tail", 2, "c1", 1, "- a1\n  1. b1\n\n  Ta1\n  - [x] d1\n", "- a1\n  1. b1\n\n  TaX1\n  - [x] d1\n", [nil, 0, 0] as [Int?], false, 0, false),
            ("1. [ ] a1\n- [ ] b1\n- [ ] c1\n", "b1", 1, "c1", 1, "1. [ ] a1\n- [ ] b1\n", "1. [ ] a1\n- [ ] bX1\n", [nil, nil] as [Int?], true, 0, false),
            ("- a1\n* b1\n* c1\n", "b1", 1, "c1", 1, "- a1\n- b1\n", "- a1\n- bX1\n", [nil, nil] as [Int?], true, 0, false),
            ("> - a1\n> * b1\n> * c1\n", "b1", 1, "c1", 1, "> - a1\n> - b1\n", "> - a1\n> - bX1\n", [nil, nil] as [Int?], true, 0, false),
            ("- p1\n  - a1\n  * b1\n  * c1\n", "b1", 1, "c1", 1, "- p1\n  - a1\n  * b1\n", "- p1\n  - a1\n  * bX1\n", [nil, 0, 0] as [Int?], true, 0, false),
            ("- Root\n  1. A1\n  1. B1\n  1. C1\n  1. D1\n  1. E1\n  1. F1\n  1. G1\n  1. H1\n  1. I1\n  1. J1\n     - Nested\n  1. K1\n- c1\n  - d1\n", "K1", 1, "c1", 1, "- Root\n  1. A1\n  2. B1\n  3. C1\n  4. D1\n  5. E1\n  6. F1\n  7. G1\n  8. H1\n  9. I1\n  10. J1\n      - Nested\n  11. K1\n  12. d1\n", "- Root\n  1. A1\n  2. B1\n  3. C1\n  4. D1\n  5. E1\n  6. F1\n  7. G1\n  8. H1\n  9. I1\n  10. J1\n      - Nested\n  11. KX1\n  12. d1\n", [nil, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0] as [Int?], true, 2, true),
            ("- Root\n  1. A1\n  1. B1\n  1. C1\n  1. D1\n  1. E1\n  1. F1\n  1. G1\n  1. H1\n  1. I1\n  1. J1\n     > - Nested\n     >   - Leaf\n  1. K1\n- c1\n  - d1\n", "K1", 1, "c1", 1, "- Root\n  1. A1\n  2. B1\n  3. C1\n  4. D1\n  5. E1\n  6. F1\n  7. G1\n  8. H1\n  9. I1\n  10. J1\n      > - Nested\n      >   - Leaf\n  11. K1\n  12. d1\n", "- Root\n  1. A1\n  2. B1\n  3. C1\n  4. D1\n  5. E1\n  6. F1\n  7. G1\n  8. H1\n  9. I1\n  10. J1\n      > - Nested\n      >   - Leaf\n  11. KX1\n  12. d1\n", [nil, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 11, 0, 0] as [Int?], true, 2, true),
            ("- Root\n  1. A1\n  1. B1\n  1. C1\n  1. D1\n  1. E1\n  1. F1\n  1. G1\n  1. H1\n  1. I1\n  1. J1\n     - Nested\n  1. K1\n     - KChild\n\n     Tail\n- c1\n  - d1\n", "Tail", 2, "c1", 1, "- Root\n  1. A1\n  2. B1\n  3. C1\n  4. D1\n  5. E1\n  6. F1\n  7. G1\n  8. H1\n  9. I1\n  10. J1\n      - Nested\n  11. K1\n      - KChild\n\n      Ta1\n  12. d1\n", "- Root\n  1. A1\n  2. B1\n  3. C1\n  4. D1\n  5. E1\n  6. F1\n  7. G1\n  8. H1\n  9. I1\n  10. J1\n      - Nested\n  11. K1\n      - KChild\n\n      TaX1\n  12. d1\n", [nil, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 12, 0] as [Int?], false, 2, true),
            ("- a1\n  1. b1\n  100. z1\n- c1\n  - d1\n", "z1", 1, "c1", 1, "- a1\n  1. b1\n  2. z1\n  3. d1\n", "- a1\n  1. b1\n  2. zX1\n  3. d1\n", [nil, 0, 0, 0] as [Int?], true, -2, false),
            ("- a1\n  1. b1\n  100. y1\n  101. z1\n- c1\n  - d1\n", "z1", 1, "c1", 1, "- a1\n  1. b1\n  2. y1\n  3. z1\n  4. d1\n", "- a1\n  1. b1\n  2. y1\n  3. zX1\n  4. d1\n", [nil, 0, 0, 0, 0], true, -4, false),
            ("- a1\n  1. b1\n- c1\n  - d1\n  - e1\n", "b1", 1, "c1", 1, "- a1\n  1. b1\n  2. d1\n  3. e1\n", "- a1\n  1. bX1\n  2. d1\n  3. e1\n", [nil, 0, 0, 0] as [Int?], true, 0, false),
            ("- a1\n  1. b1\n- c1\n  - d1\n", "a1", 1, "c1", 1, "- a1\n  - d1\n", "- aX1\n  - d1\n", [nil, 0], true, 0, false),
            ("- a1\n- c1\n  1. d1\n", "a1", 1, "c1", 1, "- a1\n  1. d1\n", "- aX1\n  1. d1\n", [nil, 0], true, 0, false),
            ("1. a1\n2. c1\n   - d1\n", "a1", 1, "c1", 1, "1. a1\n   - d1\n", "1. aX1\n   - d1\n", [nil, 0], true, 0, false),
            ("- a1\n  - b1\n* c1\n  1. d1\n", "b1", 1, "c1", 1, "- a1\n  - b1\n  - d1\n", "- a1\n  - bX1\n  - d1\n", [nil, 0, 0], true, 0, false),
            ("1. a1\n   - b1\n2) c1\n   - d1\n", "b1", 1, "c1", 1, "1. a1\n   - b1\n   - d1\n", "1. a1\n   - bX1\n   - d1\n", [nil, 0, 0], true, 0, false),
            ("- a1\n  - [x] b1\n- c1\n  1. d1\n", "b1", 1, "c1", 1, "- a1\n  - [x] b1\n  - [ ] d1\n", "- a1\n  - [x] bX1\n  - [ ] d1\n", [nil, 0, 0], true, 0, false),
            ("- a1\n  - b1\n- c1\n  - [x] d1\n", "b1", 1, "c1", 1, "- a1\n  - b1\n  - d1\n", "- a1\n  - bX1\n  - d1\n", [nil, 0, 0], true, 0, false),
            ("- a1\n- c1\n  - [x] d1\n", "a1", 1, "c1", 1, "- a1\n  - [x] d1\n", "- aX1\n  - [x] d1\n", [nil, 0], true, 0, false),
            ("Intro\n\n- a1\n  - [x] d1\n- s1\n", "Intro", 2, "a1", 1, "In1\n\n- [x] d1\n- s1\n", "InX1\n\n- [x] d1\n- s1\n", [nil, nil], true, 0, false),
            ("- a1\n  - b1\n  - [x] z1\n- c1\n  1. d1\n", "z1", 1, "c1", 1, "- a1\n  - [ ] b1\n  - [x] z1\n  - [ ] d1\n", "- a1\n  - [ ] b1\n  - [x] zX1\n  - [ ] d1\n", [nil, 0, 0, 0], true, 0, false),
            ("Intro\n\n- Parent\n  1. Child\n- Sibling\n", "Intro", 2, "Parent", 3, "Inent\n\n- Child\n- Sibling\n", "InXent\n\n- Child\n- Sibling\n", [nil, nil], true, 0, false),
            ("Intro\n\n1. Parent\n   - Child\n2. Sibling\n", "Intro", 2, "Parent", 3, "Inent\n\n1. Child\n2. Sibling\n", "InXent\n\n1. Child\n2. Sibling\n", [nil, nil], true, 0, false),
            ("- a1\n  - b1\n- c1\n  - d1\n\nOutside\n\n* u1\n+ v1\n", "b1", 1, "c1", 1, "- a1\n  - b1\n  - d1\n\nOutside\n\n* u1\n+ v1\n", "- a1\n  - bX1\n  - d1\n\nOutside\n\n* u1\n+ v1\n", [nil, 0, 0, nil, nil], true, 0, false),
            ("- Parent\n\nOutside\n\n    code\n", "Outside", 0, "Outside", 7, "- Parent\n\n\n\n```\ncode\n```\n", "- Parent\n\nX\n\n    code\n", [nil] as [Int?], true, 0, false),
            ("- Parent\n\n# Outside\n\n  - Sibling\n", "Outside", 0, "Outside", 7, "- Parent\n\n# \n\n  - Sibling\n", "- Parent\n\n# X\n\n  - Sibling\n", [nil, nil] as [Int?], true, 0, false),
            ("- Parent\n\nOutside\n\n  - Sibling\n", "Outside", 0, "Outside", 7, "- Parent\n\n\n\n- Sibling\n", "- Parent\n\nX\n\n  - Sibling\n", [nil, nil], true, 0, false),
            ("> - Parent\n>\n> Outside\n>\n>   - Sibling\n", "Outside", 0, "Outside", 7, "> - Parent\n>\n> \n>\n> - Sibling\n", "> - Parent\n>\n> X\n>\n>   - Sibling\n", [nil, nil], true, 0, false),
            ("1. Parent\n\nOutside\n\n   2. Sibling\n", "Outside", 0, "Outside", 7, "1. Parent\n\n\n\n2. Sibling\n", "1. Parent\n\nX\n\n   2. Sibling\n", [nil, nil], true, 0, false),
            ("- a1\n  - b1\n- c1\n  - d1\n\n  Tail\n- s1\n", "b1", 1, "c1", 1, "- a1\n  - b1\n  - d1\n\n  Tail\n- s1\n", "- a1\n  - bX1\n  - d1\n\n  Tail\n- s1\n", [nil, 0, 0, nil], false, 0, false),
            ("Intro\n\n> - Parent\n>   - Child\n>\n>   Tail\n> - Sib\n", "Intro", 2, "Parent", 3, "Inent\n\n> - Child\n> \n> Tail\n> \n> - Sib\n", "InXent\n\n> - Child\n> \n> Tail\n> \n> - Sib\n", [nil, nil], false, 0, false),
            ("- a1\n  - b1\n- c1\n  - d1\n", "b1", 1, "c1", 1, "- a1\n  - b1\n  - d1\n", "- a1\n  - bX1\n  - d1\n", [nil, 0, 0], true, 0, false),
            ("- a1\n  - b1\n- c1\n  - d1\n  - e1\n", "b1", 1, "c1", 1, "- a1\n  - b1\n  - d1\n  - e1\n", "- a1\n  - bX1\n  - d1\n  - e1\n", [nil, 0, 0, 0], true, 0, false),
            ("> q1\n\n- a1\n  - c1\n- s1\n", "q1", 1, "a1", 1, "> q1\n\n- c1\n- s1\n", "> qX1\n\n- c1\n- s1\n", [nil, nil], true, 0, false),
            ("> - a1\n\n- b1\n  - c1\n", "a1", 1, "b1", 1, "> - a1\n\n- c1\n", "> - aX1\n\n- c1\n", [nil, nil], true, 0, false),
            ("- Parent\n  - Child\n- Sibling\n", "Parent", 3, "Child", 2, "- Parild\n- Sibling\n", "- ParXild\n- Sibling\n", [nil, nil] as [Int?], true, 0, false),
            ("- Parent\n  - Child\n    - Grand\n- Sibling\n", "Parent", 3, "Child", 2, "- Parild\n  - Grand\n- Sibling\n", "- ParXild\n  - Grand\n- Sibling\n", [nil, 0, nil], true, 0, false),
            ("- Parent\n  - Child\n- Sibling\n", "Child", 2, "Sibling", 3, "- Parent\n  - Chling\n", "- Parent\n  - ChXling\n", [nil, 0], true, 0, false),
            ("- First\n- Second\n  - Child\n- Sibling\n", "First", 2, "Second", 3, "- Fiond\n  - Child\n- Sibling\n", "- FiXond\n  - Child\n- Sibling\n", [nil, 0, nil], true, 0, false),
            ("Intro\n\n- Parent\n  - Child\n- Sibling\n", "Intro", 2, "Parent", 3, "Inent\n\n- Child\n- Sibling\n", "InXent\n\n- Child\n- Sibling\n", [nil, nil], true, 0, false),
            ("> - Parent\n>   - Child\n> - Sibling\n", "Parent", 3, "Child", 2, "> - Parild\n> - Sibling\n", "> - ParXild\n> - Sibling\n", [nil, nil], true, 0, false),
            ("- 😀 Parent\n  - Child\n- Sibling\n", "😀 Parent", 5, "Child", 2, "- 😀 Paild\n- Sibling\n", "- 😀 PaXild\n- Sibling\n", [nil, nil], true, 0, false),
            ("9. Parent\n   1. Child\n      - Grand\n10. Sibling\n", "Parent", 3, "Child", 2, "9. Parild\n   1. Grand\n10. Sibling\n", "9. ParXild\n   1. Grand\n10. Sibling\n", [nil, 0, nil], true, 0, false),
            ("- Parent\n\n  10. Child\n      - Grand\n- Sibling\n", "Parent", 3, "Child", 2, "- Parild\n  1. Grand\n- Sibling\n", "- ParXild\n  1. Grand\n- Sibling\n", [nil, 0, nil], true, 0, false),
            ("-   Parent\n    - Child\n  - Sibling\n", "Parent", 0, "Child", 5, "- \n- Sibling\n", "-   X\n  - Sibling\n", [nil, nil], true, 0, false),
            ("- First\n- Second\n\n  - Child\n- Sibling\n", "First", 0, "Second", 6, "- \n  - Child\n- Sibling\n", "- X\n\n  - Child\n- Sibling\n", [nil, 0, nil], true, 0, false),
            ("- Parent\n\n  More\n  - Child\n- Sibling\n", "Parent", 3, "Child", 2, "- Parild\n- Sibling\n", "- ParXild\n- Sibling\n", [nil, nil], true, 0, false),
            ("- Parent\n\n  More\n  - Child\n    - Grand\n- Sibling\n", "More", 2, "Child", 2, "- Parent\n\n  Moild\n  - Grand\n- Sibling\n", "- Parent\n\n  MoXild\n  - Grand\n- Sibling\n", [nil, 0, nil], true, 0, false),
            ("- **Parent**\n  - Child\n- Sibling\n", "Parent", 3, "Child", 2, "- **Par**ild\n- Sibling\n", "- **ParX**ild\n- Sibling\n", [nil, nil], true, 0, false),
            ("- First\n  - Child\n\n  Tail\n- Second\n  - Grand\n\n  End tail\n- Sibling\n", "First", 2, "Second", 3, "- Fiond\n  - Grand\n\n  End tail\n- Sibling\n", "- FiXond\n  - Grand\n\n  End tail\n- Sibling\n", [nil, 0, nil], false, 0, false),
            ("- First\n  - Child\n\n  Tail\n- Second\n  - Grand\n\n  End tail\n- Sibling\n", "Tail", 2, "Second", 3, "- First\n  - Child\n\n  Taond\n  - Grand\n\n  End tail\n- Sibling\n", "- First\n  - Child\n\n  TaXond\n  - Grand\n\n  End tail\n- Sibling\n", [nil, 0, 0, nil], false, 0, false),
            ("Intro\n\n- Parent\n  - Child\n\n  Tail\n- Sibling\n", "Intro", 2, "Parent", 3, "Inent\n\n- Child\n\nTail\n\n- Sibling\n", "InXent\n\n- Child\n\nTail\n\n- Sibling\n", [nil, nil], false, 0, false),
            ("> Intro\n>\n> - Parent\n>   - Child\n>\n>   Tail\n> - Sibling\n", "Intro", 2, "Parent", 3, "> Inent\n> \n> - Child\n> \n> Tail\n> \n> - Sibling\n", "> InXent\n> \n> - Child\n> \n> Tail\n> \n> - Sibling\n", [nil, nil], false, 0, false)
        ] { for replacement in ["", "X"] { for ending in (first == "Heading" || first == "Quote" ? ["\n", "\r\n", "\r"] : ["\n", "\r\n"]) {
            let source = source.replacingOccurrences(of: "\n", with: ending)
            let expected = (replacement.isEmpty ? deleted : replaced).replacingOccurrences(of: "\n", with: ending)
            // Inner headings/quotes are exercised through the guarded rich
            // core. Public admission is owned by the workspace opening test.
            if first != "Heading", first != "Quote", !source.contains("> - Nested") {
                XCTAssertFalse(MacMarkdown.requiresSource(source), "Supported list paragraphs must remain in rich editing")
            }
            withEditor(source) { view, coordinator in
                let raw = view.string as NSString, start = raw.range(of: first), end = raw.range(of: last)
                guard start.location != NSNotFound, end.location != NSNotFound else { XCTFail("Selection endpoints must exist"); return }
                let selection = NSRange(location: start.location + from, length: end.location + through - start.location - from)
                view.setSelectedRange(selection); view.insertText(replacement, replacementRange: selection)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(parents(coordinator.lastMarkdown), owners)
                if source.contains("> - Nested") {
                    var quoteDepths: [Int] = []
                    func quotedNested(_ node: any Markup, depth: Int = 0) {
                        let depth = depth + (node is BlockQuote ? 1 : 0)
                        if let paragraph = node as? Paragraph, paragraph.plainText == "Nested" { quoteDepths.append(depth) }
                        for child in node.children { quotedNested(child, depth: depth) }
                    }
                    quotedNested(Document(parsing: coordinator.lastMarkdown))
                    XCTAssertEqual(quoteDepths, [1], "Renumbering the earlier parent must keep Nested inside its quote")
                }
                if first == "Heading" || first == "Quote" {
                    var headings: [Int] = [], quotes = 0
                    func roles(_ node: any Markup) {
                        if let heading = node as? Heading { headings.append(heading.level) }
                        if node is BlockQuote { quotes += 1 }
                        for child in node.children { roles(child) }
                    }
                    roles(Document(parsing: coordinator.lastMarkdown))
                    XCTAssertEqual(headings, first == "Heading" ? [2] : [])
                    XCTAssertEqual(quotes, first == "Quote" ? 1 : 0)
                    XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, MacMarkdown.font(first == "Heading" ? "## " : "").pointSize)
                }
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), expected)
                let leftBody = String(decoding: first.utf16.prefix(max(0, from)), as: UTF16.self)
                let rightBody = String(decoding: last.utf16.dropFirst(max(0, through)), as: UTF16.self)
                let joinedBody = leftBody + replacement + rightBody
                if !joinedBody.isEmpty {
                    let retained = (view.string as NSString).range(of: joinedBody)
                    guard retained.location != NSNotFound else { XCTFail("The intended receiving body must remain visible"); return }
                    XCTAssertEqual(view.selectedRange(), NSRange(location: retained.location + leftBody.utf16.count + replacement.utf16.count, length: 0), "The caret belongs between the retained prefix and suffix, independent of displayed ordinal width")
                } else {
                    XCTAssertEqual(view.selectedRange(), NSRange(location: selection.location + replacement.utf16.count + caretShift, length: 0))
                }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                if checkTypingStyle {
                    let at = min(view.selectedRange().location, view.string.utf16.count - 1)
                    let paragraph = (view.string as NSString).paragraphRange(for: NSRange(location: at, length: 0))
                    guard let paragraphStyle = view.attributedString().attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle,
                          let typingStyle = view.typingAttributes[.paragraphStyle] as? NSParagraphStyle else { XCTFail("The writing paragraph and typing state must both have layout"); return }
                    // These public text-system states must agree even when the
                    // app's paragraph metrics change; no fixed pixel constants.
                    XCTAssertEqual(typingStyle.headIndent, paragraphStyle.headIndent)
                    XCTAssertEqual(typingStyle.firstLineHeadIndent, paragraphStyle.firstLineHeadIndent)
                }
                if caretShift != 0 || from < 0 || through < 0 || first == "Heading" || first == "Quote" {
                    let prefix = (first as NSString).substring(to: max(0, from)) + replacement
                    let suffix = (last as NSString).substring(from: max(0, through))
                    let typed = expected.replacingOccurrences(of: prefix + suffix, with: prefix + "!" + suffix)
                    view.insertText("!", replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, typed, "Typing must continue at the caret after marker widths change")
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                }
            }
        } } }
        for ending in ["\n", "\r\n"] {
            let source = "- Parent\n\nX\n\n  - Sibling\n".replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let word = (view.string as NSString).range(of: "X"), caret = NSRange(location: NSMaxRange(word), length: 0)
                view.setSelectedRange(caret); view.deleteBackward(nil)
                let expected = "- Parent\n\n\n\n- Sibling\n".replacingOccurrences(of: "\n", with: ending)
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(parents(coordinator.lastMarkdown), [nil, nil])
                XCTAssertEqual(view.selectedRange(), NSRange(location: word.location, length: 0)); XCTAssertEqual(view.undoManager?.undoActionName, "Typing")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), caret)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        }
        // An unrelated unmappable neighbour must not block a harmless plain
        // delete on either side, across quote containers or below its margin.
        for (prefix, suffix) in [
            ("9. Parent\n   - Child\n\n", "\n\nAfter\n"),
            ("Before\n\n", "\n\n9. Parent\n   - Child\n"),
            ("9. Parent\n   - Child\n\n", "\n\n  Kept tail\n"),
            ("9. Parent\n   - Child\n\n", "\n\n  - Sibling\n"),
            ("9. Parent\n   - Child\n\n", "\n\n>   - Sibling\n")
        ] {
            var issues: [String] = []
            withEditor(prefix + "Outside" + suffix, onPasteError: { issues.append($0) }) { view, coordinator in
                let child = (view.string as NSString).range(of: "Child"), row = (view.string as NSString).paragraphRange(for: child)
                view.setSelectedRange(NSRange(location: row.location, length: 0)); view.insertNewline(nil)
                let before = coordinator.lastMarkdown, word = (view.string as NSString).range(of: "Outside")
                view.setSelectedRange(word); view.insertText("", replacementRange: word)
                XCTAssertEqual(coordinator.lastMarkdown, before.replacingOccurrences(of: "Outside", with: ""))
                XCTAssertEqual(view.selectedRange(), NSRange(location: word.location, length: 0)); XCTAssertTrue(issues.isEmpty)
            }
        }
        for separator in [false, true] { for ending in ["\n", "\r\n"] { for replacement in (separator ? [""] : ["", "X"]) {
            let main = (separator ? "- Parent\n\nOutside\n\n  - Sibling\n" : "- Parent\n  - Child\n    - Grand\n- Sibling\n").replacingOccurrences(of: "\n", with: ending)
            let source = main + "\nTop\n\n9. Other\n   - Last child\n".replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            withEditor(source, onPasteError: { issues.append($0) }) { view, coordinator in
                let last = (view.string as NSString).range(of: "Last child")
                let row = (view.string as NSString).paragraphRange(for: NSRange(location: last.location, length: 0))
                view.setSelectedRange(NSRange(location: row.location, length: 0)); view.insertNewline(nil)
                let before = coordinator.lastMarkdown
                let raw = view.string as NSString, first = raw.range(of: separator ? "Outside" : "Parent"), end = raw.range(of: "Child")
                let selection = separator ? first : NSRange(location: first.location + 3, length: end.location + 2 - first.location - 3)
                view.setSelectedRange(selection); view.insertText(replacement, replacementRange: selection)
                let boundary = replacement.isEmpty ? "- Parent\n\n\n\n- Sibling\n" : "- Parent\n\nX\n\n  - Sibling\n"
                let changed = (separator ? boundary : "- Par" + replacement + "ild\n  - Grand\n- Sibling\n").replacingOccurrences(of: "\n", with: ending)
                let expected = before.replacingOccurrences(of: main, with: changed)
                XCTAssertEqual(coordinator.lastMarkdown, expected, "An unrelated temporary row cannot veto or be changed by this local replacement")
                XCTAssertTrue(issues.isEmpty)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } } }
        for separator in [false, true] {
            var issues: [String] = []
            withEditor(separator ? "9. Parent\n   - Child\n\nOutside\n\n   - Sibling\n" : "9. Parent\n   - Child\n", onPasteError: { issues.append($0) }) { view, coordinator in
                let word = (view.string as NSString).range(of: "Child")
                let row = (view.string as NSString).paragraphRange(for: NSRange(location: word.location, length: 0))
                view.setSelectedRange(NSRange(location: row.location, length: 0)); view.insertNewline(nil)
                let before = coordinator.lastMarkdown
                let raw = view.string as NSString, first = raw.range(of: "Parent"), last = raw.range(of: "Child")
                let selection = separator ? raw.range(of: "Outside") : NSRange(location: first.location + 3, length: last.location + 2 - first.location - 3)
                view.setSelectedRange(selection); view.insertText(separator ? "" : "X", replacementRange: selection)
                XCTAssertEqual(coordinator.lastMarkdown, before)
                XCTAssertEqual(view.selectedRange(), selection)
                XCTAssertEqual(issues, ["This list needs Markdown source editing before this selection can preserve its item relationships."])
            }
        }
    }
    @MainActor func testListCommandsFromContinuationsChangeTheirHeadAndKeepCaretOwnership() {
        for (source, action, expected) in [
            ("- [ ] Parent\n  - Child\n\n  Tail.\n- Sibling\n", "toggleChecklist", "- [x] Parent\n  - Child\n\n  Tail.\n- Sibling\n"),
            ("- Parent\n  - Child\n\n  Tail.\n- Sibling\n", "checklist", "- [ ] Parent\n  - Child\n\n  Tail.\n- Sibling\n"),
            ("- Parent\n  - Child\n\n  Tail.\n- Sibling\n", "ordered", "1. Parent\n   - Child\n\n   Tail.\n- Sibling\n"),
            ("> - Root\n>\n>   10. Parent\n>       - Child\n>\n>       Tail.\n> - Sibling\n", "bullet", "> - Root\n>\n>   - Parent\n>     - Child\n>\n>     Tail.\n> - Sibling\n")
        ] { for ending in ["\n", "\r\n"] { for caret in [false, true] {
            let source = source.replacingOccurrences(of: "\n", with: ending)
            let expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let tail = (view.string as NSString).range(of: "Tail.")
                let selected = caret ? NSRange(location: tail.location + 2, length: 0) : tail
                view.setSelectedRange(selected)
                coordinator.action(action)
                XCTAssertEqual(coordinator.lastMarkdown, expected, action)
                if caret { XCTAssertEqual(view.selectedRange().length, 0) }
                else { XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "Tail.") }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                view.insertText(caret ? "X" : "Edited.", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "Tail.", with: caret ? "TaXil." : "Edited."))
                var paragraphs: [Int] = []
                func walk(_ node: any Markup) {
                    if node is ListItem { paragraphs.append(node.children.filter { $0 is Paragraph }.count) }
                    for child in node.children { walk(child) }
                }
                walk(Document(parsing: coordinator.lastMarkdown))
                XCTAssertEqual(paragraphs, action == "bullet" ? [1, 2, 1, 1] : [2, 1, 1])
            }
        } } }
        for (action, expected) in [
            ("bullet", "- Parent\n  - Child\n\n  Tail.\n- Sibling\n"),
            ("checklist", "- [ ] Parent\n  - [ ] Child\n\n  Tail.\n- Sibling\n"),
            ("ordered", "1. Parent\n   1. Child\n\n   Tail.\n- Sibling\n"),
            ("toggleChecklist", "- [x] Parent\n  - Child\n\n  Tail.\n- Sibling\n")
        ] { for ending in ["\n", "\r\n"] {
            let source = (action == "toggleChecklist" ? "- [ ] Parent\n  - Child\n\n  Tail.\n- Sibling\n" : "- Parent\n  - Child\n\n  Tail.\n- Sibling\n").replacingOccurrences(of: "\n", with: ending)
            let expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let raw = view.string as NSString, parent = raw.range(of: "Parent"), tail = raw.range(of: "Tail.")
                let selected = NSRange(location: parent.location, length: NSMaxRange(tail) - parent.location)
                view.setSelectedRange(selected); coordinator.action(action)
                XCTAssertEqual(coordinator.lastMarkdown, expected, "A head and its continuation must be one target")
                XCTAssertTrue((view.string as NSString).substring(with: view.selectedRange()).hasSuffix("Tail."))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } }
        // Converting the head to a non-list block leaves its old continuation
        // as plain prose. That paragraph must remain available to list commands.
        for headAction in ["h1", "quote"] { for (action, marker) in [("bullet", "- "), ("ordered", "1. "), ("checklist", "- [ ] ")] { for ending in ["\n", "\r\n"] {
            let source = "- Parent\n  - Child\n\n  Tail.\n- Sibling\n".replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                view.setSelectedRange((view.string as NSString).range(of: "Parent")); coordinator.action(headAction)
                let plain = coordinator.lastMarkdown
                let tail = (view.string as NSString).range(of: "Tail.")
                view.setSelectedRange(tail); coordinator.action(action)
                XCTAssertTrue(coordinator.lastMarkdown.contains(marker + "Tail."), coordinator.lastMarkdown)
                func tailItems(_ node: any Markup) -> Int {
                    let own = (node as? ListItem)?.children.compactMap { ($0 as? Paragraph)?.plainText }.contains("Tail.") == true ? 1 : 0
                    return own + node.children.map(tailItems).reduce(0,+)
                }
                XCTAssertEqual(tailItems(Document(parsing: coordinator.lastMarkdown)), 1)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, plain)
                XCTAssertEqual(view.selectedRange(), tail)
                coordinator.action("redo")
                view.insertText("New tail.", replacementRange: view.selectedRange())
                XCTAssertTrue(coordinator.lastMarkdown.contains(marker + "New tail."), coordinator.lastMarkdown)
            }
        } } }
    }
    @MainActor func testReturnInInterleavedItemsTransfersOnlyFollowingContentToTheNewSibling() throws {
        // Selected Return is one edit: remove the selected bodies, then split
        // the surviving item without reparenting its retained descendants.
        for (source, first, from, last, through, planned, owners) in [
            ("- Parent\n- Sibling\n", "Parent", 3, "Sibling", -2, "- Par\n- |Sibling\n", [nil, nil] as [Int?]),
            ("- Parent\n- Sibling\n", "Parent", -2, "Sibling", -2, "- \n- |Sibling\n", [nil, nil]),
            ("- Parent\n- Sibling\n", "Parent", 6, "Sibling", -2, "- Parent\n- |Sibling\n", [nil, nil]),
            ("- Parent\n  - Child\n    - Grand\n- Sibling\n", "Parent", 3, "Child", -2, "- Par\n- |Child\n  - Grand\n- Sibling\n", [nil, nil, 1, nil]),
            ("- Parent\n  - Child\n    - Grand\n- Sibling\n", "Parent", 3, "Child", 2, "- Par\n- |ild\n  - Grand\n- Sibling\n", [nil, nil, 1, nil] as [Int?]),
            ("- a1\n  - b1\n- c1\n  - d1\n", "b1", 1, "c1", 1, "- a1\n  - b\n  - |1\n  - d1\n", [nil, 0, 0, 0]),
            ("Intro\n\n- Parent\n  - Child\n- Sibling\n", "Intro", 2, "Parent", 3, "In\n\n|ent\n\n- Child\n- Sibling\n", [nil, nil]),
            ("> q1\n\n- a1\n  - c1\n- s1\n", "q1", 1, "a1", 1, "> q\n> \n> |1\n\n- c1\n- s1\n", [nil, nil]),
            ("9. Parent\n   - Child\n10. Sibling\n", "Parent", 3, "Child", 2, "9. Par\n10. |ild\n10. Sibling\n", [nil, nil, nil]),
            ("- [x] Parent\n- [ ] Sibling\n", "Parent", 3, "Sibling", 3, "- [x] Par\n- [ ] |ling\n", [nil, nil]),
            ("- Parent\n  - Child\n- Sibling\n", "Parent", 2, "Parent", 4, "- Pa\n- |nt\n  - Child\n- Sibling\n", [nil, nil, 1, nil]),
            ("- Parent\n- Sibling\n", "Parent", 0, "Sibling", 0, "- \n- |Sibling\n", [nil, nil]),
            ("- Parent\n  - Child\n- Sibling\n", "Parent", -1, "Child", 2, "- \n- |ild\n- Sibling\n", [nil, nil, nil]),
            ("- Parent\n- Sibling\n", "Parent", -1, "Parent", 0, "- \n- |Parent\n- Sibling\n", [nil, nil, nil])
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending)
            let expected = planned.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "\n", with: ending)
            let typed = planned.replacingOccurrences(of: "|", with: "!").replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in }, onPasteError: { issues.append($0) })) { view, coordinator, _ in
                let raw = view.string as NSString, start = raw.range(of: first), end = raw.range(of: last)
                let range = NSRange(location: start.location + from, length: end.location + through - start.location - from)
                view.setSelectedRange(range); view.insertNewline(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertTrue(issues.isEmpty)
                var actual: [Int?] = []
                func parents(_ node: any Markup, owner: Int? = nil) {
                    var next = owner
                    if node is ListItem { next = actual.count; actual.append(owner) }
                    for child in node.children { parents(child, owner: next) }
                }
                let parsed = Document(parsing: coordinator.lastMarkdown)
                parents(parsed); XCTAssertEqual(actual, owners)
                if source.hasPrefix("Intro") { XCTAssertTrue(parsed.child(at: 0) is Paragraph); XCTAssertTrue(parsed.child(at: 1) is Paragraph) }
                if source.hasPrefix("> q") { XCTAssertEqual((parsed.child(at: 0) as? BlockQuote)?.childCount, 2) }
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), range)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(view.selectedRange().length, 0)
                view.insertText("!", replacementRange: view.selectedRange()); XCTAssertEqual(coordinator.lastMarkdown, typed)
            }
        } }

        for (source, caret, expected, beforeMarker) in [
            ("- Parent\n  - Child\n\n  Tail\n  - Later\n\n  Last\n- Sib\n", "Tail", "- Parent\n  - Child\n\n  Tail\n- New\n  - Later\n\n  Last\n- Sib\n", nil as String?),
            ("9. Parent\n   - Child\n\n   Tail\n   - Later\n\n   Last\n- Sib\n", "Tail", "9. Parent\n   - Child\n\n   Tail\n10. New\n    - Later\n\n    Last\n- Sib\n", nil as String?),
            ("9. Parent\n   - Child\n\n   Tail\n- Sib\n", "Parent", "9. Parent\n10. New\n    - Child\n\n    Tail\n- Sib\n", nil as String?),
            ("> - Parent\n>   - Child\n>\n>   Tail\n>   - Later\n>\n>   Last\n> - Sib\n", "Tail", "> - Parent\n>   - Child\n>\n>   Tail\n> - New\n>   - Later\n>\n>   Last\n> - Sib\n", nil as String?),
            ("- [x] Parent\n  - Child\n\n  Tail\n  - Later\n\n  Last\n- Sib\n", "Tail", "- [x] Parent\n  - Child\n\n  Tail\n- [ ] New\n  - Later\n\n  Last\n- Sib\n", nil as String?),
            ("9. Parent\n   - Child\n- Sib\n", "Parent", "9. Parent\n10. New\n    - Child\n- Sib\n", nil as String?),
            ("9. Parent\n   > Quoted\n   > - Child\n   >\n   > Tail\n", "Parent", "9. Parent\n10. New\n    > Quoted\n    > - Child\n    >\n    > Tail\n", nil as String?),
            ("> 9. Parent\n>    > Quoted\n>    > - Child\n>    >\n>    > Tail\n", "Parent", "> 9. Parent\n> 10. New\n>     > Quoted\n>     > - Child\n>     >\n>     > Tail\n", nil as String?),
            ("9. Parent\n   > 9. Child\n   >    > Quoted\n   >    > - Grandchild\n", "Child", "9. Parent\n   > 9. Child\n   > 10. New\n   >     > Quoted\n   >     > - Grandchild\n", nil as String?),
            ("- Parent\n  > Quoted\n  > - Child\n", "Parent", "- Parent\n- New\n  > Quoted\n  > - Child\n", nil as String?),
            ("- Parent• literal\n  - Child\n\n  Tail\n- Sib\n", "Parent", "- Parent\n- New• literal\n  - Child\n\n  Tail\n- Sib\n", nil as String?),
            ("- Parent\n\n  - Child\n- Sib\n", "Parent", "- Parent\n- New\n\n  - Child\n- Sib\n", nil),
            ("9. Parent9. literal\n   - Child\n- Sib\n", "Parent", "9. Parent\n10. New9. literal\n    - Child\n- Sib\n", nil as String?),
            ("9. Parent\n\n   - Child\n   - Peer\n", "Parent", "9. Parent\n10. New\n\n    - \n    - Child\n    - Peer\n", "Child"),
            ("99. Parent\n    - Child\n      - Grandchild\n101. Peer\n     - Peer child\n", "Parent", "99. Parent\n100. New\n     - Child\n       - Grandchild\n101. Peer\n     - Peer child\n", nil as String?),
            (">9. Parent\n>    - Child\n>\n>    Tail\n>    - Later\n>\n>    Last\n>- Sib\n", "Tail", ">9. Parent\n>    - Child\n>\n>    Tail\n>10. New\n>     - Later\n>\n>     Last\n>- Sib\n", nil as String?)
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending)
            let expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                if let beforeMarker {
                    let word = (view.string as NSString).range(of: beforeMarker)
                    let start = (view.string as NSString).paragraphRange(for: NSRange(location: word.location, length: 0)).location
                    view.setSelectedRange(NSRange(location: start, length: 0))
                    view.insertText("\n", replacementRange: view.selectedRange())
                }
                let prepared = coordinator.lastMarkdown
                let target = (view.string as NSString).range(of: caret)
                view.setSelectedRange(NSRange(location: NSMaxRange(target), length: 0))
                view.insertText("\n", replacementRange: view.selectedRange())
                let split = coordinator.lastMarkdown
                if source == "- Parent" + ending + ending + "  - Child" + ending + "- Sib" + ending {
                    XCTAssertEqual(split, "- Parent" + ending + "- " + ending + "  - Child" + ending + "- Sib" + ending)
                }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, prepared)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, split)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), expected)
                if expected.contains("> Quoted") {
                    let raw = view.string as NSString
                    let quote = raw.range(of: "Quoted"), child = raw.range(of: expected.contains("Grandchild") ? "Grandchild" : "Child")
                    guard quote.location != NSNotFound, child.location != NSNotFound,
                          let quoteStyle = view.attributedString().attribute(.paragraphStyle, at: quote.location, effectiveRange: nil) as? NSParagraphStyle,
                          let childStyle = view.attributedString().attribute(.paragraphStyle, at: child.location, effectiveRange: nil) as? NSParagraphStyle else { XCTFail("Missing quoted descendants after Return"); return }
                    XCTAssertEqual(childStyle.firstLineHeadIndent, quoteStyle.firstLineHeadIndent, accuracy: 0.01,
                                   "A transferred child marker must align with its containing quote")
                }
            }
        } }
        for (source, expected) in [
            ("- Parent\n  - Child\n\n  Tail\n- Sib\n", "- Parent\n  - Child\n- New\n- Sib\n"),
            ("9. Parent\n   - Child\n\n   Tail\n- Sib\n", "9. Parent\n   - Child\n10. New\n- Sib\n"),
            ("> - Parent\n>   - Child\n>\n>   Tail\n> - Sib\n", "> - Parent\n>   - Child\n> - New\n> - Sib\n"),
            ("- [x] Parent\n  - Child\n\n  Tail\n- Sib\n", "- [x] Parent\n  - Child\n- [ ] New\n- Sib\n"),
            ("- Root\n  - Parent\n    - Child\n\n    Tail\n- Sib\n", "- Root\n  - Parent\n    - Child\n  - New\n- Sib\n"),
            ("9. Parent\n   - Child\n\n   Tail\n   - Later\n\n   Last\n- Sib\n", "9. Parent\n   - Child\n10. New\n    - Later\n\n    Last\n- Sib\n"),
            ("9. Parent\n   - Child\n\n   Tail", "9. Parent\n   - Child\n10. New")
        ] { for ending in ["\n", "\r\n"] { for blank in ["", "  "] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let tail = (view.string as NSString).range(of: "Tail")
                view.setSelectedRange(tail); view.insertText(blank, replacementRange: tail)
                let erased = coordinator.lastMarkdown, caret = view.selectedRange()
                view.insertNewline(nil)
                let split = expected.replacingOccurrences(of: "New", with: "")
                XCTAssertEqual(coordinator.lastMarkdown, split, "An empty continuation must not leave an old paragraph gap")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, erased)
                XCTAssertEqual(view.selectedRange(), caret)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, split)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), expected)
            }
        } } }
        for (source, expected) in [
            ("- Parent\n  - Child\n\n  Tail\n- Sib\n", "- Parent\n  - Child\n\nOutside\n\n- Sib\n"),
            ("- Root\n  - Parent\n    - Child\n\n    Tail\n- Sib\n", "- Root\n  - Parent\n    - Child\n- Outside\n- Sib\n"),
            ("> - Parent\n>   - Child\n>\n>   Tail\n> - Sib\n", "> - Parent\n>   - Child\n> \n> Outside\n> \n> - Sib\n")
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let tail = (view.string as NSString).range(of: "Tail")
                view.setSelectedRange(tail); view.insertText("", replacementRange: tail)
                view.insertNewline(nil)
                let sibling = coordinator.lastMarkdown
                view.insertNewline(nil)
                let outside = coordinator.lastMarkdown
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, sibling)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, outside)
                view.insertText("Outside", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } }
        for ending in ["\n", "\r\n"] {
            let source = "9. Parent\n   - Child\n\n   Tail\n   - Later\n\n   Last\n- Sib\n".replacingOccurrences(of: "\n", with: ending)
            let expected = "9. Parent\n   - Child\n10. \n11. New\n    - Later\n\n    Last\n- Sib\n".replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let tail = (view.string as NSString).range(of: "Tail")
                view.setSelectedRange(tail); view.insertText("", replacementRange: tail)
                view.insertNewline(nil)
                let before = coordinator.lastMarkdown
                view.insertNewline(nil)
                let split = coordinator.lastMarkdown
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, split)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected, "An empty head with owned content must split instead of discarding its container")
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
            }
            for offset in [0, 2, 4] {
                withEditor("- Parent\n  - Child\n\n  Tail\n".replacingOccurrences(of: "\n", with: ending)) { view, coordinator in
                    view.setSelectedRange((view.string as NSString).range(of: "Parent")); coordinator.action("h1")
                    // The host invokes both interactions in one XCTest event.
                    // End it before AppKit registers the separate Return event.
                    view.breakUndoCoalescing()
                    if let undo = view.undoManager {
                        if undo.groupingLevel > 0 { undo.endUndoGrouping() }
                        undo.beginUndoGrouping()
                    }
                    let before = coordinator.lastMarkdown
                    let tail = (view.string as NSString).range(of: "Tail")
                    let selected = NSRange(location: tail.location + offset, length: 0)
                    view.setSelectedRange(selected); view.insertNewline(nil)
                    let left = String("Tail".prefix(offset)), right = String("Tail".dropFirst(offset))
                    let split = before.replacingOccurrences(of: "Tail" + ending, with: left + ending + right + ending)
                    XCTAssertEqual(coordinator.lastMarkdown, split, "Detached Return must have the same newline meaning as plain Return")
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                    XCTAssertEqual(view.selectedRange(), selected)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, split)
                    view.insertText("After", replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, before.replacingOccurrences(of: "Tail" + ending, with: left + ending + "After" + right + ending), "A detached paragraph must not revive its old list")
                }
            }
        }
        for ending in ["\n", "\r\n"] {
            let source = "- Root\n  - Empty\n  - Child\n- Sib\n".replacingOccurrences(of: "\n", with: ending)
            let expected = "- Root\n- Outside\n  - Child\n- Sib\n".replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let empty = (view.string as NSString).range(of: "Empty")
                view.setSelectedRange(empty); view.insertText("", replacementRange: empty)
                let before = coordinator.lastMarkdown
                view.insertNewline(nil)
                let lifted = coordinator.lastMarkdown
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, lifted)
                view.insertText("Outside", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected, "Empty-item exit must carry the following nested list under its new outer item")
            }
        }
        for ending in ["\n", "\r\n"] {
            withEditor("Para" + ending) { view, coordinator in
                view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0)); coordinator.action("bullet")
                let draft = coordinator.lastMarkdown
                view.insertNewline(nil)
                XCTAssertEqual(coordinator.lastMarkdown, "Para" + ending + ending, "An unparsed empty root marker must still exit to an independent paragraph")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, draft)
                coordinator.action("redo")
                view.insertText("After", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, "Para" + ending + ending + "After")
            }
        }
        for quoted in [false, true] { for ending in ["\n", "\r\n"] {
            let source = quoted ? "> Para\n> \n> After\n" : "Para\n\nAfter\n"
            withEditor(source.replacingOccurrences(of: "\n", with: ending)) { view, coordinator in
                let gap = (view.string as NSString).range(of: "\n\n")
                guard gap.location != NSNotFound else { XCTFail("Missing paragraph gap"); return }
                view.setSelectedRange(NSRange(location: gap.location + 1, length: 0))
                if quoted { view.insertText("- ", replacementRange: view.selectedRange()) }
                else { coordinator.action("bullet") }
                let before = coordinator.lastMarkdown
                view.insertNewline(nil)
                let split = coordinator.lastMarkdown
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, split)
                view.insertText("New", replacementRange: view.selectedRange())
                let expected = (quoted ? "> Para\n> \n> New\n> \n> After\n" : "Para\n\nNew\n\nAfter\n").replacingOccurrences(of: "\n", with: ending)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                let para = (view.string as NSString).range(of: "Para")
                view.setSelectedRange(para); view.insertText("Changed", replacementRange: para)
                let edited = expected.replacingOccurrences(of: "Para", with: "Changed")
                XCTAssertEqual(coordinator.lastMarkdown, edited)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(edited)), edited)
            }
        } }
        for ending in ["\n", "\r\n"] {
            withEditor("- Root\n  - B\n    - C\n- Sib\n".replacingOccurrences(of: "\n", with: ending)) { view, coordinator in
                let b = (view.string as NSString).range(of: "B")
                view.setSelectedRange(b); view.insertText("", replacementRange: b)
                let before = coordinator.lastMarkdown, selected = view.selectedRange()
                view.insertNewline(nil)
                let split = "- Root\n\n  - \n  - \n    - C\n- Sib\n".replacingOccurrences(of: "\n", with: ending)
                XCTAssertEqual(coordinator.lastMarkdown, split, "An empty first child with children must split just like a later child")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, split)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, "- Root\n\n  - \n  - New\n    - C\n- Sib\n".replacingOccurrences(of: "\n", with: ending))
            }
            for removeChild in [false, true] {
                let source = removeChild ? "- A\n  - Child\n\n  Tail\n- Sib\n" : "- A\n\n  Tail\n- Sib\n"
                withEditor(source.replacingOccurrences(of: "\n", with: ending)) { view, coordinator in
                    if removeChild {
                        let child = (view.string as NSString).range(of: "Child")
                        guard child.location != NSNotFound else { XCTFail("Missing child fixture"); return }
                        let row = (view.string as NSString).paragraphRange(for: child)
                        view.setSelectedRange(row); view.insertText("", replacementRange: row)
                    }
                    let a = (view.string as NSString).range(of: "A")
                    view.setSelectedRange(a); view.insertText("", replacementRange: a)
                    let before = coordinator.lastMarkdown
                    view.insertNewline(nil)
                    let split = "- \n- Tail\n- Sib\n".replacingOccurrences(of: "\n", with: ending)
                    XCTAssertEqual(coordinator.lastMarkdown, split, "A continuation-only owner must split independently of its native paragraph grouping")
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, split)
                    view.insertText("New", replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, "- \n- NewTail\n- Sib\n".replacingOccurrences(of: "\n", with: ending))
                }
            }
        }
    }
    @MainActor func testWidthChangingReturnRefusesAnUnmatchedNativeListWithoutChangingTheDraft() {
        var errors: [String] = []
        withEditor("9. Parent\n   - Child\n", onPasteError: { errors.append($0) }) { view, coordinator in
            let child = (view.string as NSString).range(of: "Child")
            let start = (view.string as NSString).paragraphRange(for: NSRange(location: child.location, length: 0)).location
            view.setSelectedRange(NSRange(location: start, length: 0))
            view.insertText("\n", replacementRange: view.selectedRange())
            let before = coordinator.lastMarkdown
            let parent = (view.string as NSString).range(of: "Parent")
            let caret = NSRange(location: NSMaxRange(parent), length: 0)
            view.setSelectedRange(caret)
            view.insertText("\n", replacementRange: view.selectedRange())
            XCTAssertEqual(coordinator.lastMarkdown, before)
            XCTAssertEqual(view.selectedRange(), caret)
            XCTAssertEqual(errors, ["This list needs Markdown source editing before another item can be inserted safely."])
            let last = (view.string as NSString).range(of: "Child")
            let selected = NSRange(location: parent.location + 3, length: last.location + 2 - parent.location - 3)
            view.undoManager?.removeAllActions(); view.setSelectedRange(selected)
            view.insertNewline(nil)
            XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.selectedRange(), selected)
            XCTAssertEqual(errors.last, "This list needs Markdown source editing before this selection can preserve its item relationships.")
            XCTAssertFalse(view.undoManager?.canUndo ?? true, "A refused selected Return must not leave an intermediate deletion in Undo")
        }
    }
    @MainActor func testInterleavedContinuationCannotAbsorbTheFollowingPlainParagraph() {
        for ending in ["\n", "\r\n"] {
            let source = "- Parent\n  - Child\n\n  Tail.\n\nPlain\n".replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let gap = (view.string as NSString).range(of: "\n\nPlain")
                XCTAssertNotEqual(gap.location, NSNotFound)
                guard gap.location != NSNotFound else { return }
                view.setSelectedRange(NSRange(location: gap.location + 1, length: 1))
                view.insertText("", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, source, "Deleting visual spacing must not change the plain paragraph's container")
                let tail = (view.string as NSString).range(of: "Tail.")
                view.setSelectedRange(NSRange(location: NSMaxRange(tail), length: 0))
                view.insertText("!", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, source.replacingOccurrences(of: "Tail.", with: "Tail.!"))
                let last = Array(Document(parsing: coordinator.lastMarkdown).children).last as? Paragraph
                XCTAssertEqual(last?.plainText, "Plain")
            }
        }
    }
    @MainActor func testInterleavedIndentationMovesTheWholeItemAndKeepsEveryParagraphOwner() throws {
        func ownership(_ node: any Markup) -> [String: String] {
            var result: [String: String] = [:]
            if node is ListItem {
                let paragraphs = node.children.compactMap { ($0 as? Paragraph)?.plainText }
                if let head = paragraphs.first { for paragraph in paragraphs { result[paragraph] = head } }
            }
            for child in node.children { result.merge(ownership(child)) { _, new in new } }
            return result
        }
        for (source, word, through, backward, expected) in [
            ("- Root\n- Parent\n  - Child\n\n  Tail\n- Sib\n", "Tail", nil as String?, false, "- Root\n  - Parent\n    - Child\n\n    Tail\n- Sib\n"),
            ("- Root\n  - Parent\n    - Child\n\n    Tail\n\n  Root tail\n- Sib\n", "Tail", nil, true, "- Root\n\n  Root tail\n- Parent\n  - Child\n\n  Tail\n- Sib\n"),
            ("- Parent\n  - Child\n    - Grandchild\n\n  Parent tail\n- Sib\n", "Child", nil, true, "- Parent\n\n  Parent tail\n- Child\n  - Grandchild\n- Sib\n"),
            ("- Parent\n  - One\n  - Two\n\n  Parent tail\n- Sib\n", "One", nil, true, "- Parent\n  - Two\n\n  Parent tail\n- One\n- Sib\n"),
            ("10. Root\n11. Parent\n    - Child\n\n    Tail\n12. Sib\n", "Tail", nil, false, "10. Root\n    1. Parent\n       - Child\n\n       Tail\n12. Sib\n"),
            ("> - Parent\n>   - Child\n>\n>   Tail\n> - Sib\n", "Child", nil, true, "> - Parent\n>\n>   Tail\n> - Child\n> - Sib\n"),
            ("  - Root\n   - Parent\n     - Child\n\n     Tail\n  - Sib\n", "Tail", nil, false, "  - Root\n    - Parent\n      - Child\n\n      Tail\n  - Sib\n"),
            ("- Root\n- First\n  - First child\n\n  First tail\n- Second\n  - Second child\n\n  Second tail\n- After\n", "First tail", "Second tail", false, "- Root\n  - First\n    - First child\n\n    First tail\n  - Second\n    - Second child\n\n    Second tail\n- After\n"),
            ("- Root\n  - Existing\n\n  Root tail\n- Parent\n  - Child\n\n  Tail\n- Sib\n", "Tail", nil, false, "- Root\n  - Existing\n\n  Root tail\n  - Parent\n    - Child\n\n    Tail\n- Sib\n"),
            ("10. Parent\n    1. Child\n       - Grandchild\n\n    Tail\n12. Sib\n", "Child", nil, true, "10. Parent\n\n    Tail\n11. Child\n    - Grandchild\n12. Sib\n"),
            ("- [ ] Root\n- [x] Parent\n  - Child\n\n  Tail\n- [ ] Sib\n", "Tail", nil, false, "- [ ] Root\n  - [x] Parent\n    - Child\n\n    Tail\n- [ ] Sib\n"),
            ("- Parent\n  - Child\n\n  Tail", "Child", nil, true, "- Parent\n\n  Tail\n- Child\n"),
            (">- Root\n>- Parent\n>   - Child\n>\n>   Tail\n>- Sib\n", "Tail", nil, false, ">- Root\n>   - Parent\n>     - Child\n>\n>     Tail\n>- Sib\n"),
            ("- Root\n- Parent\n  > Quote\n  > - Leaf\n  >\n  > Tail\n- Sib\n", "Parent", nil, false, "- Root\n  - Parent\n    > Quote\n    > - Leaf\n    >\n    > Tail\n- Sib\n"),
            ("- Root\n  - Parent\n    > Quote\n    > - Leaf\n    >\n    > Tail\n- Sib\n", "Parent", nil, true, "- Root\n- Parent\n  > Quote\n  > - Leaf\n  >\n  > Tail\n- Sib\n"),
            ("10. Root\n11. Parent\n    > Quote\n    > - Leaf\n    >\n    > Tail\n12. Sib\n", "Parent", nil, false, "10. Root\n    1. Parent\n       > Quote\n       > - Leaf\n       >\n       > Tail\n12. Sib\n"),
            ("10. Root\n\n    9. Parent\n       > Quote\n       > - Leaf\n       >\n       > Tail\n12. Sib\n", "Parent", nil, true, "10. Root\n\n11. Parent\n    > Quote\n    > - Leaf\n    >\n    > Tail\n12. Sib\n"),
            ("> - Root\n> - Parent\n>   > Quote\n>   > - Leaf\n>   >\n>   > Tail\n> - Sib\n", "Parent", nil, false, "> - Root\n>   - Parent\n>     > Quote\n>     > - Leaf\n>     >\n>     > Tail\n> - Sib\n"),
            ("- Root\n- Parent\n  > 9. Child\n  >    > Quote\n  >    > - Leaf\n- Sib\n", "Parent", nil, false, "- Root\n  - Parent\n    > 9. Child\n    >    > Quote\n    >    > - Leaf\n- Sib\n"),
            ("1. P\n\n   9. C\n   10. D\n       > Quote\n       > - Leaf\n2. Q\n", "C", nil, true, "1. P\n\n   9. D\n      > Quote\n      > - Leaf\n2. C\n2. Q\n"),
            ("- Parent\n  > Quote\n  >\n  > - Leaf\n  > - Peer\n- Sibling\n", "Leaf", nil, true, "- Parent\n  > Quote\n  >\n  > - Leaf\n  > - Peer\n- Sibling\n"),
            ("10. Parent\n    > Quote\n    >\n    > - Leaf\n11. Sibling\n", "Leaf", nil, true, "10. Parent\n    > Quote\n    >\n    > - Leaf\n11. Sibling\n"),
            ("- > Quote\n  >\n  > - Leaf\n- Sibling\n", "Leaf", nil, true, "- > Quote\n  >\n  > - Leaf\n- Sibling\n"),
            ("> Quote\n> - Leaf\n> - Peer\n", "Leaf", nil, true, "> Quote\n> - Leaf\n> - Peer\n"),
            ("- Parent\n  > Quote\n  >\n  > - Leaf\n  >   - Grand\n- Sibling\n", "Leaf", nil, true, "- Parent\n  > Quote\n  >\n  > - Leaf\n  >   - Grand\n- Sibling\n"),
            ("- Parent\n  > Quote\n  >\n  > - Leaf\n  >   - Grand\n- Sibling\n", "Grand", nil, true, "- Parent\n  > Quote\n  >\n  > - Leaf\n  > - Grand\n- Sibling\n"),
            ("- P\n  - C\n  - D\n- Q\n", "C", nil, true, "- P\n  - D\n- C\n- Q\n"),
            ("1. P\n   1. C\n   2. D\n2. Q\n", "C", nil, true, "1. P\n   1. D\n2. C\n2. Q\n"),
            ("1. P\n\n   10. C\n   11. D\n2. Q\n", "C", nil, true, "1. P\n\n   10. D\n2. C\n2. Q\n"),
            ("1. P\n\n   9. C\n   10. D\n       - G\n2. Q\n", "C", nil, true, "1. P\n\n   9. D\n      - G\n2. C\n2. Q\n"),
            ("1. P\n   1) C\n   2) D\n2. Q\n", "C", nil, true, "1. P\n   1) D\n2) C\n2. Q\n"),
            ("- P\n  - C\n\n  - D\n- Q\n", "C", "C\n\n", true, "- P\n  - D\n- C\n\n- Q\n")
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            withEditor(source, onPasteError: { issues.append($0) }) { view, coordinator in
                let raw = view.string as NSString, first = raw.range(of: word), last = through.map { raw.range(of: $0) } ?? first
                let selection = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
                view.setSelectedRange(selection)
                let selected = raw.substring(with: selection)
                if source.contains("> Quote") {
                    XCTAssertEqual(ownership(Document(parsing: source))[word], word, "The selected fixture item must exist in the source parser tree")
                }
                coordinator.action(backward ? "outdent" : "indent")
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertTrue(issues.isEmpty, "A supported move or boundary no-op must not warn: " + issues.joined(separator: "; "))
                if source == expected { XCTAssertFalse(view.undoManager?.canUndo ?? true, "A quote-boundary no-op must not create an Undo step") }
                XCTAssertEqual(ownership(Document(parsing: coordinator.lastMarkdown)), ownership(Document(parsing: source)))
                if source.contains("> Quote") {
                    let text = view.string as NSString, quote = text.range(of: "Quote"), leaf = text.range(of: "Leaf")
                    guard quote.location != NSNotFound, leaf.location != NSNotFound,
                          let quoteStyle = view.attributedString().attribute(.paragraphStyle, at: quote.location, effectiveRange: nil) as? NSParagraphStyle,
                          let leafStyle = view.attributedString().attribute(.paragraphStyle, at: leaf.location, effectiveRange: nil) as? NSParagraphStyle else { XCTFail("Missing moved quote/list paragraphs"); return }
                    XCTAssertEqual(leafStyle.firstLineHeadIndent, quoteStyle.headIndent, accuracy: 0.01,
                                   "Moving a whole item must keep a child marker aligned with its quote text")
                }
                XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), selected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                if through == nil {
                    view.setSelectedRange(NSRange(location: NSMaxRange(view.selectedRange()), length: 0))
                    view.insertText("!", replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: word, with: word + "!"))
                } else if through?.contains("\n") == true {
                    view.insertText("Replacement", replacementRange: view.selectedRange())
                    XCTAssertTrue(view.string.contains("• D\n"), "The remaining sibling must not be replaced")
                    XCTAssertTrue(coordinator.lastMarkdown.contains("  - D" + ending))
                }
            }
        } }
        // Inner roles move with their complete item, including when the
        // command starts in a continuation. Parsing saved Markdown is the oracle.
        func shape(_ source: String) -> [String] {
            var result: [String] = [], next = 0
            func walk(_ node: any Markup, owner: Int? = nil) {
                var owner = owner
                if node is ListItem { let index = next; next += 1; result.append("item:\(index):\(owner.map(String.init) ?? "root")"); owner = index }
                if let heading = node as? Heading { result.append("h\(heading.level):\(owner.map(String.init) ?? "root"):\(heading.plainText)") }
                if let paragraph = node as? Paragraph { result.append("p:\(owner.map(String.init) ?? "root"):\(paragraph.plainText)") }
                if node is BlockQuote { result.append("quote:\(owner.map(String.init) ?? "root")") }
                for child in node.children { walk(child, owner: owner) }
            }
            walk(Document(parsing: source)); return result
        }
        for (source, prepare, baseline, backward, expected, role) in [
            ("- Root\n- Inner\n- After\n", "", "- Root\n- Inner\n- After\n", false, "- Root\n  - Inner\n- After\n", ""),
            ("- Root\n  - Inner\n- After\n", "", "- Root\n  - Inner\n- After\n", true, "- Root\n- Inner\n- After\n", ""),
            ("- Root\n- # Inner\n- After\n", "", "- Root\n- # Inner\n- After\n", false, "- Root\n  - # Inner\n- After\n", "# "),
            ("- Root\n  - # Inner\n- After\n", "", "- Root\n  - # Inner\n- After\n", true, "- Root\n- # Inner\n- After\n", "# "),
            ("- Root\n- Parent\n\n  ## Inner\n  - Child\n\n  Tail\n- After\n", "", "- Root\n- Parent\n\n  ## Inner\n  - Child\n\n  Tail\n- After\n", false, "- Root\n  - Parent\n\n    ## Inner\n    - Child\n\n    Tail\n- After\n", "## "),
            ("- Root\n  - Parent\n\n    ## Inner\n    - Child\n\n    Tail\n\n  Root tail\n- After\n", "", "- Root\n  - Parent\n\n    ## Inner\n    - Child\n\n    Tail\n\n  Root tail\n- After\n", true, "- Root\n\n  Root tail\n- Parent\n\n  ## Inner\n  - Child\n\n  Tail\n- After\n", "## "),
            ("- Root\n- > Inner\n- After\n", "", "- Root\n- > Inner\n- After\n", false, "- Root\n  - > Inner\n- After\n", "> "),
            ("- Root\n  - > Inner\n- After\n", "", "- Root\n  - > Inner\n- After\n", true, "- Root\n- > Inner\n- After\n", "> "),
            ("- Root\n- Parent\n\n  > Inner\n  > ## Deeper\n\n  Tail\n- After\n", "", "- Root\n- Parent\n\n  > Inner\n  > ## Deeper\n\n  Tail\n- After\n", false, "- Root\n  - Parent\n\n    > Inner\n    > ## Deeper\n\n    Tail\n- After\n", "> "),
            ("> - Root\n> - Parent\n>\n>   ## Inner\n> - After\n", "", "> - Root\n> - Parent\n>\n>   ## Inner\n> - After\n", false, "> - Root\n>   - Parent\n>\n>     ## Inner\n> - After\n", "> ## "),
            ("10. Root\n11. Parent\n\n    ## Inner\n12. After\n", "", "10. Root\n11. Parent\n\n    ## Inner\n12. After\n", false, "10. Root\n    1. Parent\n\n       ## Inner\n12. After\n", "## "),
            ("- Root\n- # Inner\n- After\n", "quote", "- Root\n- > Inner\n- After\n", false, "- Root\n  - > Inner\n- After\n", "> ")
        ] { for ending in ["\n", "\r\n", "\r"] { for caretOnly in [false, true] { for laterEvent in [false, true] {
            let source = source.replacingOccurrences(of: "\n", with: ending), baseline = baseline.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in }, onPasteError: { issues.append($0) })) { view, coordinator, _ in
                if !prepare.isEmpty { view.setSelectedRange((view.string as NSString).range(of: "Inner")); coordinator.action(prepare) }
                XCTAssertEqual(coordinator.lastMarkdown, baseline)
                let word = (view.string as NSString).range(of: "Inner")
                guard word.location != NSNotFound else { XCTFail("Missing inner indentation endpoint"); return }
                let selection = caretOnly ? NSRange(location: word.location + 2, length: 0) : word
                view.setSelectedRange(selection); view.undoManager?.removeAllActions()
                coordinator.action(backward ? "outdent" : "indent")
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertTrue(issues.isEmpty)
                XCTAssertEqual(shape(coordinator.lastMarkdown), shape(expected))
                let after = view.selectedRange()
                XCTAssertEqual((view.string as NSString).substring(with: after), caretOnly ? "" : "Inner")
                let insertion = NSRange(location: NSMaxRange(after), length: 0)
                view.setSelectedRange(insertion)
                if laterEvent { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                view.insertText("!", replacementRange: insertion)
                let typed = expected.replacingOccurrences(of: "Inner", with: caretOnly ? "In!ner" : "Inner!")
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                XCTAssertEqual(shape(coordinator.lastMarkdown), shape(typed))
                XCTAssertEqual((view.attributedString().attribute(.font, at: insertion.location, effectiveRange: nil) as? NSFont)?.pointSize, MacMarkdown.font(role).pointSize)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected, "Typing after indentation is its own Undo event")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, baseline); XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), insertion)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, typed)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(typed)), typed)
                if prepare == "quote" {
                    // A toolbar-created quote must keep its live Return role
                    // through the item move and its complete Undo/Redo cycle.
                    let text = caretOnly ? "In!ner" : "Inner!"
                    let word = (view.string as NSString).range(of: text)
                    guard word.location != NSNotFound else { XCTFail("Missing moved quote"); return }
                    view.setSelectedRange(NSRange(location: NSMaxRange(word), length: 0)); view.insertNewline(nil)
                    let split = ("- Root\n  - > " + text + "\n\n    \u{200b}\n- After\n").replacingOccurrences(of: "\n", with: ending)
                    XCTAssertEqual(coordinator.lastMarkdown, split)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, typed)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, split)
                    view.insertText("New", replacementRange: view.selectedRange())
                    let filled = split.replacingOccurrences(of: "\u{200b}", with: "New")
                    XCTAssertEqual(coordinator.lastMarkdown, filled); XCTAssertEqual(shape(coordinator.lastMarkdown), shape(filled))
                }
            }
        } } } }
        let source = "- Root\n- Parent\n  - Child\n\n  Tail"
        withEditor(source) { view, coordinator in
            let caret = NSRange(location: (view.string as NSString).length, length: 0)
            view.setSelectedRange(caret)
            coordinator.action("indent")
            XCTAssertEqual(coordinator.lastMarkdown, "- Root\n  - Parent\n    - Child\n\n    Tail")
            XCTAssertEqual(view.selectedRange(), NSRange(location: (view.string as NSString).length, length: 0))
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            XCTAssertEqual(view.selectedRange(), caret)
        }
    }
    @MainActor func testListBodyEditsKeepTheirItemsAndParentsThroughAutosave() {
        func parents(_ source: String) -> [Int?] {
            var result: [Int?] = []
            func collect(_ node: any Markup, owner: Int? = nil) {
                var owner = owner
                if node is ListItem { let index = result.count; result.append(owner); owner = index }
                for child in node.children { collect(child, owner: owner) }
            }
            collect(Document(parsing: source)); return result
        }
        for original in ["Para\n- ", "- Parent\n  - "] { for ending in ["\n", "\r\n"] {
            let imported = original.replacingOccurrences(of: "\n", with: ending)
            XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(imported)), imported, "Unchanged imported tokens must not be normalized")
        } }
        for (source, word, replacement, expected, refilled, owners) in [
            ("- Parent\n  - Child\n", "Child" as String?, "", "- Parent\n\n  - \n", nil as String?, [nil, 0] as [Int?]),
            ("10. Parent\n    1. Child\n", "Child", "", "10. Parent\n\n    1. \n", nil, [nil, 0]),
            ("> - Parent\n>   - Child\n", "Child", "", "> - Parent\n> \n>   - \n", nil, [nil, 0]),
            ("- Root\n  - B\n    - C\n- Sib\n", "B", "", "- Root\n\n  - \n    - C\n- Sib\n", nil, [nil, 0, 1, nil]),
            ("- First\n- Empty\n- Keep\n", "Empty", "", "- First\n- \n- Keep\n", nil, [nil, nil, nil]),
            ("- [ ] Parent\n  - [ ] Child\n", "Child", "", "- [ ] Parent\n  - [ ] \n", nil, [nil, 0]),
            ("> 10. [x] Parent\n>     1. [ ] Child\n", "Child", "", "> 10. [x] Parent\n>     1. [ ] \n", nil, [nil, 0]),
            ("- Parent\n  - Child", "Child", "", "- Parent\n\n  - ", nil, [nil, 0]),
            ("-  Parent\n  - Sibling\n", "Parent", "", "- \n- Sibling\n", "- Again\n- Sibling\n", [nil, nil]),
            ("-    Parent\n     - Child\n       - Grand\n  - Sibling\n", "Parent", "", "- \n  - Child\n    - Grand\n- Sibling\n", "- Again\n  - Child\n    - Grand\n- Sibling\n", [nil, 0, 1, nil]),
            ("10.   Parent\n      - Child\n   - Sibling\n", "Parent", "", "10. \n    - Child\n   - Sibling\n", "10. Again\n    - Child\n   - Sibling\n", [nil, 0, nil]),
            ("> -   Parent\n>    - Sibling\n", "Parent", "", "> - \n> - Sibling\n", "> - Again\n> - Sibling\n", [nil, nil]),
            ("-   Parent\n\n    More\n    - Child\n  - Sibling\n", "Parent", "", "-   More\n    - Child\n  - Sibling\n", "-   Again\n\n    More\n    - Child\n  - Sibling\n", [nil, 0, nil]),
            ("-   Parent\n\n    More\n\n    - Child\n  - Sibling\n", "Parent", "", "-   More\n\n    - Child\n  - Sibling\n", "-   Again\n\n    More\n\n    - Child\n  - Sibling\n", [nil, 0, nil]),
            ("-   [ ] Parent\n    - Child\n  - Sibling\n", "Parent", "", "-   [ ] \n    - Child\n  - Sibling\n", nil, [nil, 0, nil]),
            ("-   \n  - Child\n", nil, "P", "- P\n  - Child\n", "- PAgain\n  - Child\n", [nil, 0]),
            ("10.   \n    - Child\n", nil, "P", "10. P\n    - Child\n", "10. PAgain\n    - Child\n", [nil, 0])
            , ("- Root\n  -   Parent\n      - Child\n    - Peer\n- Sib\n", "Parent", "", "- Root\n\n  - \n    - Child\n  - Peer\n- Sib\n", "- Root\n  - Again\n    - Child\n  - Peer\n- Sib\n", [nil, 0, 1, 0, nil])
            , ("- Parent\n\n  * \n", "Parent", "", "- \n  * \n", "- Again\n\n  * \n", [nil, 0])
            , ("- Parent\n\n  - Child\n", "Parent", "", "- \n  - Child\n", "- Again\n\n  - Child\n", [nil, 0])
            , ("- \n  * \n", nil, "P", "- P\n\n  * \n", "- PAgain\n\n  * \n", [nil, 0])
            , ("> - \n>   * \n", nil, "P", "> - P\n> \n>   * \n", "> - PAgain\n> \n>   * \n", [nil, 0])
            , ("- \n\n  * Child\n", nil, "P", "- P\n\n* Child\n", "- PAgain\n\n* Child\n", [nil, nil])
            , ("- \nOutside one\nOutside two\n", nil, "P", "- P\n\nOutside one\nOutside two\n", "- PAgain\n\nOutside one\nOutside two\n", [nil])
        ] { for prelude in ["", "Intro **strong**.\n\n```text\nx\ry\n```\n\n"] { for ending in ["\n", "\r\n"] {
            let typed = (prelude + (refilled ?? source.replacingOccurrences(of: word!, with: "Again"))).replacingOccurrences(of: "\n", with: ending)
            let source = (prelude + source).replacingOccurrences(of: "\n", with: ending), expected = (prelude + expected).replacingOccurrences(of: "\n", with: ending)
            XCTAssertFalse(MacMarkdown.requiresSource(source), "The body edit must start in a supported rich document")
            withEditor(source) { view, coordinator in
                let raw = view.string as NSString
                let body: NSRange
                if let word { body = raw.range(of: word) }
                else {
                    let marker = raw.range(of: source.contains("10.   ") ? "10.   " : "• ")
                    guard marker.location != NSNotFound else { XCTFail("Missing empty item marker"); return }
                    body = NSRange(location: NSMaxRange(marker), length: 0)
                }
                guard body.location != NSNotFound else { XCTFail("Missing item body"); return }
                view.setSelectedRange(body); view.insertText(replacement, replacementRange: body)
                XCTAssertEqual(coordinator.lastMarkdown, expected, "The published autosave must retain the item's intended parent graph")
                XCTAssertEqual(parents(coordinator.lastMarkdown), owners)
                let caret = view.selectedRange()
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), body)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                view.insertText("Again", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                XCTAssertEqual(parents(coordinator.lastMarkdown), owners)
            }
        } } }
        var bodyIssues: [String] = []
        withEditor("-   Parent\n   - Sibling\n\nTop\n\n9. Other\n   - Child\n", onPasteError: { bodyIssues.append($0) }) { view, coordinator in
            let child = (view.string as NSString).range(of: "Child")
            let beginning = (view.string as NSString).paragraphRange(for: child).location
            view.setSelectedRange(NSRange(location: beginning, length: 0)); view.insertNewline(nil)
            let before = coordinator.lastMarkdown, body = (view.string as NSString).range(of: "Parent")
            view.setSelectedRange(body); view.insertText("", replacementRange: body)
            let expected = before.replacingOccurrences(of: "-   Parent\n   - Sibling\n", with: "- \n- Sibling\n")
            XCTAssertEqual(coordinator.lastMarkdown, expected, "An unrelated temporary markerless row must not veto this local body edit")
            XCTAssertTrue(bodyIssues.isEmpty)
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.selectedRange(), body)
            coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
        }
        for clearFirst in [false, true] { for unmapped in [false, true] { for ending in ["\n", "\r\n"] {
            let suffix = unmapped ? "\nTop\n\n9. Other\n   - Else child\n" : ""
            let source = ("- Parent\n\n  - Child\n  - Peer\n" + suffix).replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                if unmapped {
                    let word = (view.string as NSString).range(of: "Else child")
                    let row = (view.string as NSString).paragraphRange(for: NSRange(location: word.location, length: 0))
                    view.setSelectedRange(NSRange(location: row.location, length: 0)); view.insertNewline(nil)
                }
                func clearParent() {
                    let word = (view.string as NSString).range(of: "Parent")
                    guard word.location != NSNotFound else { XCTFail("Parent must remain available"); return }
                    view.setSelectedRange(word); view.insertText("", replacementRange: word)
                }
                if clearFirst { clearParent() }
                let child = (view.string as NSString).range(of: "Child")
                let row = (view.string as NSString).paragraphRange(for: NSRange(location: child.location, length: 0))
                view.setSelectedRange(row); view.insertText("", replacementRange: row)
                XCTAssertFalse(view.string.contains("Child"), "Deleting the first child must be accepted even after clearing its parent")
                let removed = coordinator.lastMarkdown
                if !clearFirst { clearParent() }
                let expected = "- " + ending + "  - Peer" + ending
                XCTAssertTrue(coordinator.lastMarkdown.hasPrefix(expected), "The first-child gap must follow the remaining child: " + coordinator.lastMarkdown)
                XCTAssertEqual(Array(parents(coordinator.lastMarkdown).prefix(2)), [nil, 0])
                if !clearFirst {
                    let saved = coordinator.lastMarkdown
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, removed)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, saved)
                }
            }
        } } }
        for (source, expected, owners) in [
            ("1. a\n   1. b\n      1. c\n", "1. a\n\n   1. \n      1. \n", [nil, 0, 1] as [Int?]),
            ("- a\n  * b\n    * c\n", "- a\n\n  * \n    * \n", [nil, 0, 1]),
            ("> 1. a\n>    1. b\n>       1. c\n", "> 1. a\n> \n>    1. \n>       1. \n", [nil, 0, 1]),
            ("- a\n  - b\n- d\n  - c\n", "- a\n\n  - \n- d\n\n  - \n", [nil, 0, nil, 2]),
            ("> - a\n>   - b\n- d\n  - c\n", "> - a\n> \n>   - \n- d\n\n  - \n", [nil, 0, nil, 2])
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let b = (view.string as NSString).range(of: "b")
                view.setSelectedRange(b); view.insertText("", replacementRange: b)
                let first = coordinator.lastMarkdown
                XCTAssertEqual(parents(first), owners)
                // Model separate user edit events before erasing the next head.
                view.breakUndoCoalescing()
                if let undo = view.undoManager {
                    if undo.groupingLevel > 0 { undo.endUndoGrouping() }
                    undo.beginUndoGrouping()
                }
                let c = (view.string as NSString).range(of: "c")
                view.setSelectedRange(c); view.insertText("", replacementRange: c)
                XCTAssertEqual(coordinator.lastMarkdown, expected, "A separator before the empty parent must not detach its empty child")
                XCTAssertEqual(parents(coordinator.lastMarkdown), owners)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), expected)
                let caret = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, first); XCTAssertEqual(view.selectedRange(), c)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                view.insertText("Again", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, first.replacingOccurrences(of: "c", with: "Again"))
                XCTAssertEqual(parents(coordinator.lastMarkdown), owners)
            }
        } }
        for ending in ["\n", "\r\n"] {
            withEditor("Para" + ending) { view, coordinator in
                view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0)); coordinator.action("bullet")
                let expected = "Para" + ending + ending + "- "
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(parents(coordinator.lastMarkdown), [nil])
                let caret = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "Para" + ending)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                view.insertText("Again", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, "Para" + ending + "- Again")
                XCTAssertEqual(parents(coordinator.lastMarkdown), [nil])
            }
        }
    }
    @MainActor func testIndentingAnEmptyFirstChildAddsTheRequiredMarkdownSeparation() {
        withEditor("- Parent\n- \n") { view, coordinator in
            view.setSelectedRange(NSRange(location: (view.string as NSString).length - 1, length: 0))
            coordinator.action("indent")
            XCTAssertEqual(coordinator.lastMarkdown, "- Parent\n\n  - \n")
            let root = Document(parsing: coordinator.lastMarkdown).child(at: 0) as? UnorderedList
            let parent = root?.child(at: 0) as? ListItem
            XCTAssertTrue(parent?.children.contains { $0 is UnorderedList } == true)
            XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "- Parent\n- \n")
            coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, "- Parent\n\n  - \n")
            view.insertText("\n", replacementRange: view.selectedRange())
            XCTAssertEqual(coordinator.lastMarkdown, "- Parent\n- \n")
            let lifted = Document(parsing: coordinator.lastMarkdown).child(at: 0) as? UnorderedList
            XCTAssertEqual(lifted?.childCount, 2, "The empty child becomes a second root item")
        }
    }
    @MainActor func testChangingListTypeKeepsChildrenAndQuotedNestedItemsWithTheirParents() {
        for (source, word, command, expected) in [
            ("- Parent\n  - Child\n    - Grandchild\n- Sibling\n", "Parent", "ordered", "1. Parent\n   - Child\n     - Grandchild\n- Sibling\n"),
            ("- Root\n  - Parent\n    - Child\n- Sibling\n", "Parent", "ordered", "- Root\n  1. Parent\n     - Child\n- Sibling\n"),
            ("> - Root\n>\n>   10. Parent\n>       - Child\n> - Sibling\n", "Parent", "checklist", "> - Root\n>\n>   - [ ] Parent\n>     - Child\n> - Sibling\n"),
            ("- Parent\n\n  More **text**.\n  - Child\n- Sibling\n", "Parent", "ordered", "1. Parent\n\n   More **text**.\n   - Child\n- Sibling\n"),
            ("  - Parent\n   - Sibling\n", "Parent", "ordered", "  1. Parent\n   - Sibling\n"),
            (">- Parent\n>   - Child\n", "Parent", "ordered", ">1. Parent\n>    - Child\n"),
            ("- Parent\n  + Child\n", "Parent", "checklist", "- [ ] Parent\n  + Child\n"),
            ("1. Parent\n   - Child\n", "Parent", "bullet", "- Parent\n  - Child\n"),
            ("-\tParent\n\t-\tChild\n", "Parent", "ordered", "1. Parent\n   -   Child\n"),
            ("9.\tParent\n\t-\tChild\n", "Parent", "bullet", "- Parent\n  -   Child\n"),
            ("> -\tParent\n>\t-\tChild\n", "Parent", "ordered", "> 1. Parent\n>    -   Child\n"),
            ("```\nx\ry\n```\n\n- Parent\n  - Child\n", "Parent", "ordered", "```\nx\ry\n```\n\n1. Parent\n   - Child\n")
        ] {
            XCTAssertFalse(MacMarkdown.requiresSource(source))
            func outline(_ node: any Markup, depth: Int = 0) -> [Int] {
                var result = node is ListItem ? [depth] : []
                for child in node.children { result += outline(child, depth: depth + (node is ListItem ? 1 : 0)) }
                return result
            }
            withEditor(source) { view, coordinator in
                if source.contains("x\ry") { XCTAssertTrue(view.string.hasSuffix("• Parent\n• Child\n"), "Code-body CR must not shift the following displayed paragraphs") }
                let target = (view.string as NSString).range(of: word)
                view.setSelectedRange(NSRange(location: NSMaxRange(target), length: 0))
                coordinator.action(command)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(outline(Document(parsing: coordinator.lastMarkdown)), outline(Document(parsing: source)))
                XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                // The command must retain the caret's paragraph context for the next edit.
                view.insertText("!", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: word, with: word + "!"))
            }
        }
    }
    @MainActor func testChangingSelectedNestedListTypesAppliesAncestorPaddingOnlyOnce() {
        let source = "- Parent\n  - Child\n    - Grandchild\n- Sibling\n"
        withEditor(source) { view, coordinator in
            let raw = view.string as NSString, start = raw.range(of: "Parent").location, end = NSMaxRange(raw.range(of: "Grandchild"))
            view.setSelectedRange(NSRange(location: start, length: end - start))
            coordinator.action("ordered")
            XCTAssertEqual(coordinator.lastMarkdown, "1. Parent\n   1. Child\n      1. Grandchild\n- Sibling\n")
            XCTAssertFalse(MacMarkdown.requiresSource(coordinator.lastMarkdown))
            XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "Parent\n1. Child\n1. Grandchild")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            XCTAssertEqual(view.selectedRange(), NSRange(location: start, length: end - start))
        }
    }
    @MainActor func testLooseListParagraphsAndHardBreaksStayInOneItemWhenMoved() {
        for (marker, continuation, child) in [("- ", "  ", "  - "), ("- [ ] ", "  ", "  - "), ("10. ", "    ", "    - "), ("> - ", ">   ", ">   - "), (">- ", ">   ", ">   - ")] {
            let separator = marker.hasPrefix(">") ? "\n>\n" : "\n\n"
            let source = marker + "Root\n" + marker + "First **bold  \n" + continuation + "continued** text." + separator + continuation + "Second paragraph.\n" + child + "Child\n"
            XCTAssertFalse(MacMarkdown.requiresSource(source), source)
            withEditor(source) { view, coordinator in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                // Text-system presentation updates must not invalidate source tokens.
                view.textStorage?.addAttribute(.foregroundColor, value: NSColor.textColor, range: (view.string as NSString).range(of: "ontin"))
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                if marker.contains("[ ]"), let glyphFont = NSFont(name: "AppleColorEmoji", size: 15) {
                    // AppKit substitutes display fonts for checkbox glyphs during layout.
                    view.textStorage?.addAttribute(.font, value: glyphFont, range: NSRange(location: (view.string as NSString).range(of: "☐ First").location, length: 1))
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                }
                let word = (view.string as NSString).range(of: "Second")
                view.setSelectedRange(word); view.insertText("Updated", replacementRange: word)
                coordinator.action("indent")
                if marker.contains("[ ]") { coordinator.action("toggleChecklist") }
                let document = Document(parsing: coordinator.lastMarkdown)
                var counts: [(Int, Int)] = []
                func walk(_ node: any Markup, depth: Int = 0) {
                    if node is ListItem { counts.append((depth, node.children.filter { $0 is Paragraph }.count)) }
                    for child in node.children { walk(child, depth: depth + (node is ListItem ? 1 : 0)) }
                }
                walk(document)
                XCTAssertEqual(counts.map(\.0), [0, 1, 2], coordinator.lastMarkdown)
                XCTAssertEqual(counts.map(\.1), [1, 2, 1], coordinator.lastMarkdown)
                XCTAssertTrue(coordinator.lastMarkdown.contains("Updated paragraph."))
                func breaks(_ node: any Markup) -> Int { (node is LineBreak ? 1 : 0) + node.children.map(breaks).reduce(0,+) }
                XCTAssertEqual(breaks(document), 1)
                let indented = coordinator.lastMarkdown
                coordinator.action("outdent")
                counts.removeAll(); walk(Document(parsing: coordinator.lastMarkdown))
                XCTAssertEqual(counts.map(\.0), [0, 0, 1])
                XCTAssertEqual(counts.map(\.1), [1, 2, 1])
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, indented)
                if marker.contains("[ ]") { coordinator.action("undo") }
                coordinator.action("undo"); coordinator.action("undo")
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
            }
        }
    }
    @MainActor func testWrappedListParagraphKeepsOneItemThroughEditingIndentationAndUndo() {
        for marker in ["- ", "10. ", "> - "] {
            let source = marker + "Root\n" + marker + "First **bold\ncontinued** text.\n"
            XCTAssertFalse(MacMarkdown.requiresSource(source))
            withEditor(source) { view, coordinator in
                XCTAssertTrue(view.string.contains("First bold continued text."))
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                let word = (view.string as NSString).range(of: "continued")
                guard word.location != NSNotFound else { return XCTFail("Wrapped text must stay editable") }
                view.setSelectedRange(word); view.insertText("updated", replacementRange: word)
                XCTAssertTrue(coordinator.lastMarkdown.contains("First **bold updated** text."), coordinator.lastMarkdown)
                coordinator.action("indent")
                let parsed = Document(parsing: coordinator.lastMarkdown)
                func items(_ node: any Markup) -> Int { (node is ListItem ? 1 : 0) + node.children.map(items).reduce(0,+) }
                XCTAssertEqual(items(parsed), 2)
                XCTAssertTrue(coordinator.lastMarkdown.contains(marker.hasPrefix("10") ? "    1. First" : marker.hasPrefix(">") ? ">   - First" : "  - First"), coordinator.lastMarkdown)
                coordinator.action("undo"); coordinator.action("undo")
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
            }
        }
    }
    @MainActor func testUneditedRichDocumentsKeepExactMarkdown() {
        let examples = [
            "***\n---\n___\n",
            "```swift\ncode\n```\n---\n",
            "> Before\n>\n> ***\n> ---\n> After\n",
            "````md\n```literal\n````",
            "~~~swift\r\n\r\n~~~\r\n",
            "```swift\nlast line",
            "# A title\n\nHello **bold**, *italic* and `code`.\n",
            "## Heading\n\n- one\n- two\n\n- [ ] next\n- [x] done\n",
            "> A quote\n\n[Apple](https://apple.com) and [[zerus:some-id|A note]].\n",
            "# Unicode 🧑🏽‍💻\r\n\r\nA café — 日本語.\r\n",
            "No final newline",
            "# Literal pipes\n\nLeft | right and `inline code` remain prose.\n",
            "\n\nBlank lines\n\n\n",
            "A **bold and *italic* phrase** with _underscores_.\n",
        ]
        for text in examples { XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(text)), text, text) }
    }
    @MainActor func testNestedListAndQuoteEditsPreserveDepthMarkersAndUnchangedMarkdown() {
        for newline in ["\n", "\r\n"] {
            let original = ["# Outline", "", "- Parent", "  - **Child** and *style*.", "    1. Grandchild", "  - [ ] Review", "", "> First quote", "> > Deep quote", "> ## Quoted heading", "> - Quoted list", "", "After _spelling_.", ""].joined(separator: newline)
            XCTAssertFalse(MacMarkdown.requiresSource(original))
            withEditor(original) { view, coordinator in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), original)
                let range = (view.string as NSString).range(of: "Child"); view.setSelectedRange(range); view.insertText("Updated", replacementRange: range)
                let expected = original.replacingOccurrences(of: "Child", with: "Updated")
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                let deep = (view.string as NSString).range(of: "Deep"); view.setSelectedRange(deep); view.insertText("Nested", replacementRange: deep)
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "Deep", with: "Nested"))
                let heading = (view.string as NSString).range(of: "Quoted heading"); view.setSelectedRange(heading); view.insertText("Native heading", replacementRange: heading)
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "Deep", with: "Nested").replacingOccurrences(of: "Quoted heading", with: "Native heading"))
            }
        }
    }
    @MainActor func testNativeListIndentationContinuationAndNestedChecklistKeepUndoAndSourceDepth() {
        let original = "- Parent\n- Child\n\n> - [ ] Review\n> > Deep quote\n"
        withEditor(original) { view, coordinator in
            let child = (view.string as NSString).range(of: "Child"); view.setSelectedRange(NSRange(location: NSMaxRange(child), length: 0))
            coordinator.action("indent"); XCTAssertEqual(coordinator.lastMarkdown, original.replacingOccurrences(of: "- Child", with: "  - Child"))
            view.insertText("\n", replacementRange: view.selectedRange()); view.insertText("Sibling", replacementRange: view.selectedRange())
            XCTAssertTrue(coordinator.lastMarkdown.contains("- Parent\n  - Child\n  - Sibling"), coordinator.lastMarkdown)
            coordinator.action("outdent"); XCTAssertTrue(coordinator.lastMarkdown.contains("  - Child\n- Sibling"), coordinator.lastMarkdown)
            coordinator.action("undo"); XCTAssertTrue(coordinator.lastMarkdown.contains("  - Child\n  - Sibling"))
            let review = (view.string as NSString).range(of: "Review"); coordinator.toggleChecklist(at: review.location)
            XCTAssertTrue(coordinator.lastMarkdown.contains("> - [x] Review"), coordinator.lastMarkdown)
            coordinator.action("undo"); XCTAssertTrue(coordinator.lastMarkdown.contains("> - [ ] Review"))
        }
        let subtree = "- Root\n- Parent\n  - Child\n- Sibling\n"
        withEditor(subtree) { view, coordinator in
            let parent = (view.string as NSString).range(of: "Parent"); view.setSelectedRange(NSRange(location: NSMaxRange(parent), length: 0))
            coordinator.action("indent"); XCTAssertEqual(coordinator.lastMarkdown, "- Root\n  - Parent\n    - Child\n- Sibling\n")
            coordinator.action("outdent"); XCTAssertEqual(coordinator.lastMarkdown, subtree)
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "- Root\n  - Parent\n    - Child\n- Sibling\n")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, subtree)
        }
        withEditor("> > Quote\n") { view, coordinator in
            let quote = (view.string as NSString).range(of: "Quote"); view.setSelectedRange(NSRange(location: NSMaxRange(quote), length: 0))
            view.insertText("\n", replacementRange: view.selectedRange()); view.insertText("\n", replacementRange: view.selectedRange())
            XCTAssertEqual(coordinator.lastMarkdown, "> > Quote\n> \n")
        }
        withEditor("10. Parent\n    1. \n") { view, coordinator in
            let empty = (view.string as NSString).range(of: "1. "); view.setSelectedRange(NSRange(location: NSMaxRange(empty), length: 0))
            view.insertText("\n", replacementRange: view.selectedRange())
            XCTAssertEqual(coordinator.lastMarkdown, "10. Parent\n11. \n")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "10. Parent\n    1. \n")
        }
        withEditor("10. Parent\n11. Child\n") { view, coordinator in
            let child = (view.string as NSString).range(of: "Child"); view.setSelectedRange(NSRange(location: NSMaxRange(child), length: 0))
            coordinator.action("indent"); XCTAssertEqual(coordinator.lastMarkdown, "10. Parent\n    1. Child\n")
            func lists(_ node: any Markup) -> Int { (node is OrderedList ? 1 : 0) + node.children.map(lists).reduce(0, +) }
            XCTAssertEqual(lists(Document(parsing: coordinator.lastMarkdown)), 2, "The saved indentation must parse as a child list")
            coordinator.action("outdent"); XCTAssertEqual(coordinator.lastMarkdown, "10. Parent\n11. Child\n")
        }
    }
    @MainActor func testNativeTabSelectionPreservesBlankLinesAndNeverReplacesMixedContent() throws {
        for kind in 0..<3 {
            let mixed = kind > 0
            let original = "- Parent\n- One\n\n" + (mixed ? "A paragraph.\n" : "") + "- Two\n\nAfter.\n"
            var latest = original
            let editor = MacRichEditor(markdown: original, source: false, editable: true, root: nil, onChange: { latest = $0 }, onLink: { _ in })
            let host = NSHostingView(rootView: editor)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            func textView(_ view: NSView) -> NSTextView? { if let text = view as? NSTextView { return text }; return view.subviews.lazy.compactMap(textView).first }
            let view = try XCTUnwrap(textView(host)); window.makeFirstResponder(view)
            let first = (view.string as NSString).range(of: kind == 2 ? "A paragraph." : "One"), last = (view.string as NSString).range(of: "Two")
            let selection = NSRange(location: first.location, length: NSMaxRange(last) - first.location); view.setSelectedRange(selection)
            func tab(_ shift: Bool) throws { view.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))) }
            try tab(false)
            let expected = mixed ? original : "- Parent\n  - One\n\n  - Two\n\nAfter.\n"
            XCTAssertEqual(latest, expected); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected)
            let selectedText = kind == 2 ? "A paragraph.\n• Two" : "One\n\n" + (mixed ? "A paragraph.\n" : "") + "• Two"
            XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), selectedText, "The selection must survive Tab")
            if !mixed {
                try tab(true); XCTAssertEqual(latest, original)
                view.undoManager?.undo(); XCTAssertEqual(latest, expected)
                view.undoManager?.undo(); XCTAssertEqual(latest, original)
            }
        }
    }
    @MainActor func testImageInsertionDialogOpensWithoutChangingTheCurrentDraft() throws {
        var model = "Before target after.\n"
        try withHostedEditor(MacRichEditor(markdown: model, source: false, editable: true, onChange: { model = $0 }, onLink: { _ in }, readDocument: { (model, false) })) { view, coordinator, _ in
            view.setSelectedRange((view.string as NSString).range(of: "target")); coordinator.action("insertImage")
            let panel = try XCTUnwrap(view.window?.attachedSheet)
            XCTAssertEqual(panel.title, "Insert image"); XCTAssertEqual(model, "Before target after.\n")
            @MainActor func nodes(_ value: NSView) -> [NSView] { [value] + value.subviews.flatMap(nodes) }
            @MainActor func settle() { for _ in 0..<8 { panel.contentView?.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) } }
            @MainActor func field(_ name: String, _ text: String) throws {
                let field = try XCTUnwrap(panel.contentView.flatMap { nodes($0).compactMap { $0 as? NSTextField }.first { $0.placeholderString == name } })
                panel.makeFirstResponder(field)
                let editor = try XCTUnwrap(panel.fieldEditor(true, for: field) as? NSTextView)
                editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count)); panel.makeFirstResponder(nil); settle()
            }
            settle(); try field("Image address", "assets/chart.png"); try field("Description", "Chart"); try field("Title", "Quarterly")
            panel.makeKey()
            let save = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            panel.sendEvent(save); settle()
            let expected = "Before ![Chart](<assets/chart.png> \"Quarterly\") after.\n"
            XCTAssertNil(view.window?.attachedSheet); XCTAssertEqual(model, expected)
            coordinator.action("undo"); XCTAssertEqual(model, "Before target after.\n")
            coordinator.action("redo"); XCTAssertEqual(model, expected)
        }
    }
    @MainActor func testRemoteImagesLoadInTheActualEditorWithoutChangingMarkdownOrUndo() async throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 220, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let visiblePNG = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let peer = try HTMLHTTPFixture { path in if path == "/late.png" { Thread.sleep(forTimeInterval: 0.25) }; return ("image/png", visiblePNG) }, port = try await peer.start()
        defer { peer.stop() }
        let original = "Before target after.\n\nBefore <img src=\"http://127.0.0.1:\(port)/image.png\" alt=\"Remote\" width=\"200\" /> after.\n"
        var model = original, source = false, issues: [String] = []
        try await withAsyncHostedEditor(MacRichEditor(markdown: model, source: false, editable: true, onChange: { model = $0 }, onLink: { _ in }, onPasteError: { issues.append($0) }, readDocument: { (model, source) })) { view, coordinator, host in
            let imageRange = (view.string as NSString).range(of: "\u{fffc}")
            coordinator.imageAction(at: imageRange.location, action: "retry")
            XCTAssertTrue(issues.isEmpty, "Reload image must work for an unavailable placeholder: \(issues)")
            view.setSelectedRange((view.string as NSString).range(of: "target")); coordinator.action("bold")
            @MainActor func loaded() -> Bool {
                var found = false
                view.attributedString().enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.attributedString().length)) { value, _, _ in
                    if let image = value as? MacImageAttachment, image.image?.size == NSSize(width: 400, height: 220) { found = true }
                }
                return found
            }
            for _ in 0..<100 where !loaded() { try await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
            XCTAssertTrue(loaded(), "A remote image replaces its unavailable placeholder with fetched pixels")
            XCTAssertTrue(peer.paths.contains("/image.png"))
            XCTAssertEqual(model, original.replacingOccurrences(of: "target", with: "**target**"))
            coordinator.action("undo"); XCTAssertEqual(model, original)
            coordinator.action("redo"); XCTAssertEqual(model, original.replacingOccurrences(of: "target", with: "**target**"))
            view.setSelectedRange((view.string as NSString).range(of: "target"))
            let insertion = try coordinator.prepareImageInsertion()
            try await coordinator.insertImage(insertion, value: .init(reference: "http://127.0.0.1:\(port)/image.png", caption: "Inserted", width: 200))
            @MainActor func insertedLoaded() -> Bool {
                var found = 0
                view.attributedString().enumerateAttribute(.macLiteral, in: NSRange(location: 0, length: view.attributedString().length)) { value, range, _ in
                    if let value = value as? String, value.contains("/image.png"), let attachment = view.attributedString().attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
                       attachment.image?.size == NSSize(width: 400, height: 220) { found += 1 }
                }
                return found == 2
            }
            for _ in 0..<100 where !insertedLoaded() { try await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
            XCTAssertTrue(insertedLoaded(), "A second insertion of a loaded remote image displays pixels instead of keeping a placeholder")
            let requests = peer.paths.filter { $0 == "/image.png" }.count
            coordinator.imageAction(at: (view.string as NSString).range(of: "\u{fffc}").location, action: "retry")
            for _ in 0..<100 where peer.paths.filter({ $0 == "/image.png" }).count == requests { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertGreaterThan(peer.paths.filter { $0 == "/image.png" }.count, requests, "Reload must refetch an image that already has displayed pixels")
            model = "![Late](http://127.0.0.1:\(port)/late.png)\n"; coordinator.load(model, source: false); host.layoutSubtreeIfNeeded()
            for _ in 0..<100 where !peer.paths.contains("/late.png") { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertTrue(peer.paths.contains("/late.png"))
            model = "Another note.\n"; coordinator.load(model, source: false)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(view.string, "Another note.\n"); XCTAssertEqual(model, "Another note.\n")
            source = true; model = "![Source](http://127.0.0.1:\(port)/source.png)\n"; coordinator.load(model, source: true)
            try await Task.sleep(for: .milliseconds(100)); XCTAssertFalse(peer.paths.contains("/source.png"), "Literal Source does not load image URLs")
            source = false; model = "Start\n\n" + String(repeating: "Paragraph keeps scrolling separate.\n\n", count: 200) + "![Offscreen](http://127.0.0.1:\(port)/offscreen.png)\n"
            coordinator.load(model, source: false); view.scrollRangeToVisible(NSRange(location: 0, length: 0)); host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100)); XCTAssertFalse(peer.paths.contains("/offscreen.png"))
            view.scrollRangeToVisible(NSRange(location: max(0, view.string.utf16.count - 1), length: 0)); host.layoutSubtreeIfNeeded()
            for _ in 0..<100 where !peer.paths.contains("/offscreen.png") { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertTrue(peer.paths.contains("/offscreen.png"), "Scrolling the actual editor starts the visible image request")
        }
    }
    @MainActor func testImageInsertionImportsExactFilesAtTheSelectionAndRejectsStaleDrafts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-image-insert-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!, url = root.appendingPathComponent("Chart.png")
        try bytes.write(to: url)
        let file: MacImageFile
        do { file = try await MacImageFile.read(url) } catch { XCTFail("Staging selected image failed: \(error)"); return }
        for source in [false, true] { for ending in ["\n", "\r\n"] {
            let original = (source ? "\u{feff}---" + ending + "foreign: retained" + ending + "---" + ending : "") + "Before target after." + ending
            var model = original
            let before = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("assets").path)) ?? []
            try await withAsyncHostedEditor(MacRichEditor(markdown: model, source: source, editable: true, root: root, path: "Note.md", onChange: { model = $0 }, onLink: { _ in }, readDocument: { (model, source) })) { view, coordinator, _ in
                view.setSelectedRange((view.string as NSString).range(of: "target"))
                let request = try coordinator.prepareImageInsertion()
                do { try await coordinator.insertImage(request, value: .init(reference: "staged", caption: "Chart", title: "Kept", width: 42), file: file) }
                catch { XCTFail("Inserting staged image failed (Source=\(source)): \(error)"); return }
                let pattern = try NSRegularExpression(pattern: #"src="([^"]+)""#)
                let match = try XCTUnwrap(pattern.firstMatch(in: model, range: NSRange(location: 0, length: model.utf16.count)))
                let reference = (model as NSString).substring(with: match.range(at: 1))
                let image = "<img src=\"" + reference + "\" alt=\"Chart\" title=\"Kept\" width=\"42\" />"
                let expected = original.replacingOccurrences(of: "target", with: image)
                XCTAssertEqual(model, expected); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(reference)), bytes)
                XCTAssertEqual(try Data(contentsOf: url), bytes)
                coordinator.action("undo"); XCTAssertEqual(model, original)
                coordinator.action("redo"); XCTAssertEqual(model, expected)
                let assets = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("assets").path)
                XCTAssertEqual(assets.count, before.count + 1)
                do { try await coordinator.insertImage(request, value: .init(reference: "staged", caption: "Wrong"), file: file); XCTFail("A stale image draft must not import another resource") }
                catch { XCTAssertTrue(error.localizedDescription.contains("changed")) }
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("assets").path).sorted(), assets.sorted())
            }
        } }
    }
    @MainActor func testRemoteImageTransportHonorsCacheAndRejectsOversizedOrInvalidImages() async throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20_000, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let wide = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\" fill=\"red\"/></svg>".utf8)
        let peer = try HTMLHTTPFixture(cacheControl: { $0 == "/cached.png" ? "max-age=60" : "no-store" }) { path in
            switch path {
            case "/huge.png": return ("image/png", Data(repeating: 0, count: 50 * 1024 * 1024 + 1))
            case "/wide.png": return ("image/png", wide)
            case "/invalid.png": return ("image/png", Data("Not an image".utf8))
            case "/vector.svg": return ("image/svg+xml", svg)
            default: return ("image/png", png)
            }
        }, port = try await peer.start()
        defer { peer.stop() }
        let store = MacRemoteImageStore(), base = "http://127.0.0.1:\(port)"
        for path in ["/cached.png", "/no-store.png"] {
            let first = try await store.load(base + path, maximumPixel: 128), second = try await store.load(base + path, maximumPixel: 128)
            XCTAssertEqual(first.image.width, 1); XCTAssertEqual(second.image.height, 1)
            XCTAssertEqual(peer.paths.filter { $0 == path }.count, path == "/cached.png" ? 1 : 2)
        }
        let vector = try await store.load(base + "/vector.svg", maximumPixel: 128); XCTAssertEqual(vector.image.width, 10); XCTAssertEqual(vector.image.height, 10)
        for path in ["/huge.png", "/wide.png", "/invalid.png"] {
            do { _ = try await store.load(base + path, maximumPixel: 128); XCTFail("Invalid or oversized images must not decode: " + path) }
            catch { XCTAssertTrue(error.localizedDescription.contains(path == "/huge.png" ? "50 MB" : "supported image"), error.localizedDescription) }
        }
        do { _ = try await store.load("file:///not-an-image", maximumPixel: 128); XCTFail("Remote loading must not read a local file") }
        catch { XCTAssertTrue(error.localizedDescription.contains("http or https")) }
    }

    @MainActor func testDelayedImagePreviewKeepsMarkdownCaretAndEarlierUndoHistory() throws {
        let original = "# Preview\n\nKeep _spelling_.\n\n![A missing image](image.png)\n\nAfter.\n"
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let image = try XCTUnwrap(NSImage(data: bytes))
        withEditor(original) { view, coordinator in
            XCTAssertEqual((view.string as NSString).range(of: "[Image:").location, NSNotFound, "An unavailable image must stay an atomic image token")
            let word = (view.string as NSString).range(of: "Keep"); view.setSelectedRange(word); view.insertText("Retain", replacementRange: word)
            let edited = original.replacingOccurrences(of: "Keep", with: "Retain").replacingOccurrences(of: "_spelling_", with: "*spelling*")
            let end = (view.string as NSString).range(of: "After."); view.setSelectedRange(NSRange(location: NSMaxRange(end), length: 0))
            coordinator.parent.images = ["image.png": image]; coordinator.refreshImages()
            XCTAssertEqual(coordinator.lastMarkdown, edited); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), edited)
            XCTAssertEqual(view.selectedRange().location, NSMaxRange((view.string as NSString).range(of: "After.")))
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
            coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, edited)
            coordinator.parent.images = [:]; coordinator.refreshImages()
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), edited)
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
        }
    }
    @MainActor func testNativeTableCellEditsKeepWidthMetadataAlignmentsExtraCellsAndSurroundingBytes() {
        for newline in ["\n", "\r\n"] {
            let original = ["# Table", "", "<!-- zerus-table-widths: 200,160 -->", "| Name | Status |", "| :--- | ---: |", "| _Café_ | old |", "| Extra | stays | hidden |", "", "After _spelling_.", ""].joined(separator: newline)
            withEditor(original) { view, coordinator in
                XCTAssertFalse(MacMarkdown.requiresSource(original))
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), original)
                let range = (view.string as NSString).range(of: "old")
                view.setSelectedRange(range); view.insertText("new 🧑🏽‍💻", replacementRange: range)
                let expected = original.replacingOccurrences(of: "old", with: "new 🧑🏽‍💻")
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        }
    }
    @MainActor func testTableCellReturnTabNewRowAndExitKeepPortableGridAndUndo() throws {
        let original = "# Table\n\n| A | B |\n| --- | --- |\n|  | x |\n\nAfter.\n"
        try withEditor(original) { view, coordinator in
            var empty: NSRange?
            view.attributedString().enumerateAttribute(.macCell, in: NSRange(location: 0, length: view.string.utf16.count)) { value, range, _ in if let cell = value as? MacRichTable.Cell, cell.row == 1 && cell.column == 0 { empty = range } }
            view.setSelectedRange(NSRange(location: try XCTUnwrap(empty).location, length: 0)); view.insertText("left", replacementRange: view.selectedRange())
            XCTAssertTrue(coordinator.moveTableCell(backward: false))
            let x = (view.string as NSString).range(of: "x"); view.setSelectedRange(NSRange(location: NSMaxRange(x), length: 0))
            view.insertText("\n", replacementRange: view.selectedRange()); view.insertText("tail", replacementRange: view.selectedRange())
            let beforeRow = "# Table\n\n| A | B |\n| --- | --- |\n| left | x<br>tail |\n\nAfter.\n"
            XCTAssertEqual(coordinator.lastMarkdown, beforeRow)
            XCTAssertTrue(coordinator.moveTableCell(backward: false)); view.insertText("Added", replacementRange: view.selectedRange())
            XCTAssertTrue(coordinator.lastMarkdown.contains("| Added |  |")); XCTAssertTrue(coordinator.lastMarkdown.hasSuffix("After.\n"))
            coordinator.action("undo"); coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, beforeRow)
            coordinator.action("exitCode"); view.insertText("Outside table.\n", replacementRange: view.selectedRange())
            XCTAssertTrue(coordinator.lastMarkdown.contains("| left | x<br>tail |\n\nOutside table."), coordinator.lastMarkdown)
        }
    }
    @MainActor func testClearingAcrossCellsKeepsTheGridAndWholeTableDeletionSupportsUndo() {
        let original = "| H1 | H2 |\n| --- | --- |\n| Alpha | Beta |\n"
        withEditor(original) { view, coordinator in
            let a = (view.string as NSString).range(of: "Alpha"), b = (view.string as NSString).range(of: "Beta")
            let range = NSRange(location: a.location, length: NSMaxRange(b) - a.location)
            view.setSelectedRange(range); view.insertText("", replacementRange: range)
            XCTAssertEqual(coordinator.lastMarkdown, "| H1 | H2 |\n| --- | --- |\n|  |  |\n")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
            let all = NSRange(location: 0, length: view.string.utf16.count); view.setSelectedRange(all); view.insertText("", replacementRange: all)
            XCTAssertEqual(coordinator.lastMarkdown, "")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
        }
    }
    @MainActor func testTableSheetKeepsEarlierHistoryAndRejectsStaleDraftsInBothModes() throws {
        let basic = "# Table\n\nKeep this prose.\n\n| A | B |\n| --- | --- |\n| one | two |\n\nAfter.\n"
        for operation in ["custom", "reorder", "promoteExtra"] {
        let reorder = operation == "reorder"
        let original = operation == "promoteExtra" ? "# Table\n\nKeep this prose.\n\n<!-- zerus-table-widths: 120,220 -->\n| A | B |\n| :--- | ---: |\n| one | changed | extra |\n| four | five | six |\n\nAfter.\n" : reorder ? "# Table\n\nKeep this prose.\n\n<!-- zerus-table-widths: 120,220,320 -->\n| A | B | C |\n| :--- | :---: | ---: |\n| one | changed | three |\n| four | five | six |\n\nAfter.\n" : basic
        for sourceMode in [false, true] {
            let scope = UUID()
            try withEditor(original, sourceMode: sourceMode, path: "Note.md", scope: scope) { view, coordinator in
                let word = (view.string as NSString).range(of: "Keep")
                view.setSelectedRange(word); view.insertText("Retain", replacementRange: word)
                let before = original.replacingOccurrences(of: "Keep", with: "Retain")
                let located = try XCTUnwrap(MarkdownTable.blocks(in: before).first)
                let request = MacTableRequest(workspaceID: scope, path: "Note.md", source: before, range: located.range, table: located.table)
                let replacement: String
                if operation != "custom" {
                    var draft = located.table
                    XCTAssertTrue(draft.moveRow(from: reorder ? 2 : 1, to: reorder ? 1 : 0))
                    XCTAssertTrue(draft.moveColumn(from: 0, to: 2))
                    replacement = draft.markdown
                    let expectedTable = reorder ? "<!-- zerus-table-widths: 220,320,120 -->\n| B | C | A |\n| :---: | ---: | :--- |\n| five | six | four |\n| changed | three | one |" : "<!-- zerus-table-widths: 220,160,120 -->\n| changed | extra | one |\n| ---: | --- | :--- |\n| B |  | A |\n| five | six | four |"
                    XCTAssertEqual(replacement, expectedTable)
                } else { replacement = "<!-- zerus-table-widths: 200,160 -->\n| A | B |\n| :--- | ---: |\n| one | changed |\n| added | row |" }
                let command = MacTableChange(request: request, replacement: replacement)
                NotificationCenter.default.post(name: .macEditorAction, object: command); try XCTUnwrap(command.result).get()
                let expected = (before as NSString).replacingCharacters(in: located.range, with: replacement)
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(coordinator.source, sourceMode)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                coordinator.action("redo"); coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                let stale = MacTableChange(request: request, replacement: "| Wrong |\n| --- |\n| stale |")
                NotificationCenter.default.post(name: .macEditorAction, object: stale)
                XCTAssertThrowsError(try XCTUnwrap(stale.result).get()); XCTAssertEqual(coordinator.lastMarkdown, expected)
                let inside = (view.string as NSString).range(of: "changed"); view.setSelectedRange(NSRange(location: inside.location, length: 0))
                let newTable = "| New |\n| --- |\n| cell |"
                let insertion = MacTableChange(request: .init(workspaceID: scope, path: "Note.md", source: expected, range: nil, table: .empty()), replacement: newTable)
                NotificationCenter.default.post(name: .macEditorAction, object: insertion); try XCTUnwrap(insertion.result).get()
                XCTAssertEqual(MarkdownTable.blocks(in: coordinator.lastMarkdown).count, 2)
                XCTAssertTrue(coordinator.lastMarkdown.contains(replacement)); XCTAssertTrue(coordinator.lastMarkdown.contains(newTable))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } }
    }
    @MainActor func testCodeSheetChangesRetainEarlierUndoHistoryInRichAndSourceModes() throws {
        let original = "# Title\n\nKeep this prose.\n\n    Untouched indented code.\n\n~~~swift extra\nlet value = \"Old\"\n~~~\n\nAfter _spelling_.\n"
        for sourceMode in [false, true] { for ending in ["\n", "\r\n", "\r"] { for kind in ["fenced", "indented", "conversion"] {
            let original = original.replacingOccurrences(of: "\n", with: ending), scope = UUID()
            try withEditor(original, sourceMode: sourceMode, path: "Note.md", scope: scope) { view, coordinator in
                let word = (view.string as NSString).range(of: "Keep")
                view.setSelectedRange(word); view.insertText("Retain", replacementRange: word)
                let before = original.replacingOccurrences(of: "Keep", with: "Retain")
                XCTAssertEqual(coordinator.lastMarkdown, before)
                let located: FencedCode.Located
                if kind == "fenced" { located = try XCTUnwrap(FencedCode.blocks(in: before).first) }
                else {
                    let indented = try XCTUnwrap(MacIndentedCode.blocks(in: before).first)
                    located = .init(range: indented.range, code: indented.code)
                }
                let request = MacCodeRequest(workspaceID: scope, path: "Note.md", source: before, range: located.range, code: located.code)
                let unchanged = MacCodeChange(request: request, replacement: located.code.markdown)
                NotificationCenter.default.post(name: .macEditorAction, object: unchanged)
                do { try XCTUnwrap(unchanged.result).get() }
                catch { XCTFail("An unchanged \(kind) sheet must save for \(ending.debugDescription): \(error)"); return }
                XCTAssertEqual(coordinator.lastMarkdown, before)
                XCTAssertEqual(view.selectedRange(), NSRange(location: word.location + "Retain".utf16.count, length: 0))
                let replacement = (kind == "indented" ? "    Changed indented.\n    Second line." : "~~~python metadata\nvalue = \"New\"\n~~~").replacingOccurrences(of: "\n", with: ending)
                let command = MacCodeChange(request: request, replacement: replacement)
                NotificationCenter.default.post(name: .macEditorAction, object: command)
                do { try XCTUnwrap(command.result).get() }
                catch { XCTFail("The \(kind) sheet must apply for \(ending.debugDescription): \(error)"); return }
                let expected = (before as NSString).replacingCharacters(in: located.range, with: replacement)
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(coordinator.source, sourceMode)
                let code = Document(parsing: expected).children.compactMap { $0 as? CodeBlock }
                XCTAssertEqual(code.count, 2)
                XCTAssertEqual(code[kind == "fenced" ? 1 : 0].code, kind == "indented" ? "Changed indented.\nSecond line.\n" : "value = \"New\"\n")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                coordinator.action("undo"); XCTAssertEqual(sourceMode ? view.string : MacMarkdown.markdown(view.attributedString()), original, "Earlier prose must return in the native view"); XCTAssertEqual(coordinator.lastMarkdown, original, "The earlier prose edit must publish after Undo")
                coordinator.action("redo"); coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        } } }
        let scope = UUID()
        try withEditor(original, path: "Note.md", scope: scope) { view, coordinator in
            let target = (view.string as NSString).range(of: "Untouched indented code.")
            view.setSelectedRange(target); view.insertText("\nConverted", replacementRange: target)
            XCTAssertEqual(FencedCode.blocks(in: coordinator.lastMarkdown).count, 2)
            for first in [false, true] {
                let before = coordinator.lastMarkdown
                let located = try XCTUnwrap(first ? FencedCode.blocks(in: before).first : FencedCode.blocks(in: before).last)
                let replacement = "```swift\nEdited sheet\n```"
                let request = MacCodeRequest(workspaceID: scope, path: "Note.md", source: before, range: located.range, code: located.code)
                let command = MacCodeChange(request: request, replacement: replacement)
                NotificationCenter.default.post(name: .macEditorAction, object: command)
                try XCTUnwrap(command.result).get()
                let expected = (before as NSString).replacingCharacters(in: located.range, with: replacement)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
        }
    }
    @MainActor func testCodeSheetDraftPreservesIndentedSpellingAndUsesFencesWhenRequired() throws {
        for ending in ["\n", "\r\n", "\r"] { for (body, language, expected) in [
            ("Changed\nSecond", "", "    Changed\n    Second"),
            ("Changed\nSecond", "swift", "```swift\nChanged\nSecond\n```"),
            ("\nChanged", "", "```\n\nChanged\n```")
        ] {
            let source = "# Before" + ending + ending + "    Original" + ending + ending + "After" + ending
            let located = try XCTUnwrap(MacIndentedCode.blocks(in: source).first)
            let request = MacCodeRequest(workspaceID: UUID(), path: "Note.md", source: source, range: located.range, code: located.code)
            var saved: String?
            let host = NSHostingView(rootView: MacCodeEditor(request: request) { saved = $0 })
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 760, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            func settle() { for _ in 0..<8 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) } }
            func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
            settle()
            let text = try XCTUnwrap(nodes(host).compactMap { $0 as? NSTextView }.first { $0.string == "Original" })
            XCTAssertTrue(window.makeFirstResponder(text))
            text.insertText(body, replacementRange: NSRange(location: 0, length: text.string.utf16.count))
            window.makeFirstResponder(nil); settle()
            if !language.isEmpty {
                let field = try XCTUnwrap(nodes(host).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Language (optional)" })
                XCTAssertTrue(window.makeFirstResponder(field))
                let editor = try XCTUnwrap(window.fieldEditor(true, for: field) as? NSTextView)
                editor.insertText(language, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                window.makeFirstResponder(nil); settle()
            }
            window.makeKey()
            let save = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            window.sendEvent(save); settle()
            let result = try XCTUnwrap(saved)
            XCTAssertEqual(result, expected.replacingOccurrences(of: "\n", with: ending))
            let blocks = Document(parsing: result).children.compactMap { $0 as? CodeBlock }
            XCTAssertEqual(blocks.count, 1); XCTAssertEqual(blocks.first?.code, body + "\n")
        } }
    }
    @MainActor func testCodeSheetCommandsTargetOnlyTheirWindowAndRejectAnOutdatedSnapshot() throws {
        let original = "# Same note\n\n```swift\nlet value = 1\n```\n"
        let owner = UUID(), peer = UUID()
        try withEditor(original, path: "Note.md", scope: owner) { first, a in
            try withEditor(original, path: "Note.md", scope: peer) { second, b in
                let located = try XCTUnwrap(FencedCode.blocks(in: original).first)
                let request = MacCodeRequest(workspaceID: owner, path: "Note.md", source: original, range: located.range, code: located.code)
                let command = MacCodeChange(request: request, replacement: "```python\nvalue = 2\n```")
                NotificationCenter.default.post(name: .macEditorAction, object: command)
                try XCTUnwrap(command.result).get()
                let changed = a.lastMarkdown
                XCTAssertTrue(changed.contains("```python\nvalue = 2")); XCTAssertEqual(b.lastMarkdown, original)
                XCTAssertEqual(MacMarkdown.markdown(second.attributedString()), original)
                let stale = MacCodeChange(request: request, replacement: "```rust\nlet stale = true;\n```")
                NotificationCenter.default.post(name: .macEditorAction, object: stale)
                let rejected = try XCTUnwrap(stale.result)
                XCTAssertThrowsError(try rejected.get()) { XCTAssertTrue($0.localizedDescription.contains("note changed")) }
                XCTAssertEqual(a.lastMarkdown, changed); XCTAssertEqual(b.lastMarkdown, original)
                XCTAssertEqual(MacMarkdown.markdown(first.attributedString()), changed)
            }
        }
    }
    @MainActor func testCodeSheetInsertionUsesTheCaretAndCreationPreferenceWithoutClearingUndo() throws {
        let defaults = UserDefaults.standard, key = "zerus.mac.codeBlocks", previous = defaults.object(forKey: key)
        defer { if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) } }
        let insertion = "```swift\nlet created = true\n```"
        let examples = [
            ("# Title\n\nBefore target after.\n", "target", "# Title\n\nBefore \n\n" + insertion + "\n\n after.\n"),
            ("# Title\n\n~~~sh\necho prior\n~~~\n\nAfter.\n", "echo prior", "# Title\n\n~~~sh\necho prior\n~~~\n\n" + insertion + "\n\nAfter.\n")
        ]
        for sourceMode in [false, true] {
            for (original, target, expected) in examples { for ending in ["\n", "\r\n", "\r"] {
                let original = original.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
                defaults.set(true, forKey: key)
                let scope = UUID()
                try withEditor(original, sourceMode: sourceMode, path: "Note.md", scope: scope) { view, coordinator in
                    view.setSelectedRange((view.string as NSString).range(of: target))
                    let request = MacCodeRequest(workspaceID: scope, path: "Note.md", source: original, range: nil, code: nil)
                    let command = MacCodeChange(request: request, replacement: insertion.replacingOccurrences(of: "\n", with: ending))
                    NotificationCenter.default.post(name: .macEditorAction, object: command)
                    try XCTUnwrap(command.result).get()
                    let portable = sourceMode ? expected : expected.replacingOccurrences(of: "Before " + ending + ending, with: "Before&#32;" + ending + ending).replacingOccurrences(of: ending + ending + " after.", with: ending + ending + "&#32;after.")
                    XCTAssertEqual(coordinator.lastMarkdown, portable); XCTAssertEqual(coordinator.source, sourceMode)
                    if !sourceMode { XCTAssertEqual(MacMarkdown.render(portable).string, view.string) }
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                    defaults.set(false, forKey: key)
                    let disabled = MacCodeChange(request: request, replacement: insertion.replacingOccurrences(of: "\n", with: ending))
                    NotificationCenter.default.post(name: .macEditorAction, object: disabled)
                    let rejected = try XCTUnwrap(disabled.result)
                    XCTAssertThrowsError(try rejected.get()) { XCTAssertTrue($0.localizedDescription.contains("turned off")) }
                    XCTAssertEqual(coordinator.lastMarkdown, original)
                }
            } }
        }
    }
    @MainActor func testDeletingAnEmptiedCodeBlockRemovesItsFenceAndUndoRestoresIt() {
        withEditor("```swift\nx\n```\n") { view, coordinator in
            let character = (view.string as NSString).range(of: "x")
            view.setSelectedRange(character); view.insertText("", replacementRange: character)
            let empty = "```swift\n```\n"
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), empty)
            let all = NSRange(location: 0, length: view.string.utf16.count)
            view.setSelectedRange(all); view.insertText("", replacementRange: all)
            let deleted = MacMarkdown.markdown(view.attributedString())
            XCTAssertEqual(deleted, "", "Selecting the entire empty code block must remove it")
            if deleted.isEmpty {
                coordinator.action("undo"); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), empty)
                coordinator.action("redo"); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), "")
            }
        }
    }
    @MainActor func testIndentedCodeEditsNativelyWithoutChangingUntouchedMarkdownOrUndo() {
        let tableLiteral = " \t| A | B |\n \t| --- | --- |\n \t| C | D |\n"
        let renderedTableLiteral = MacMarkdown.render(tableLiteral)
        XCTAssertTrue(renderedTableLiteral.string.contains("| --- | --- |"), "Table-shaped indented code must remain literal native code")
        XCTAssertFalse(MacMarkdown.requiresSource(tableLiteral))
        XCTAssertEqual(MacMarkdown.markdown(renderedTableLiteral), tableLiteral)

        let widthsLiteral = "    x\n    <!-- zerus-table-widths: 120, 120 -->\n\n| a | b |\n| - | - |\n"
        XCTAssertFalse(MacMarkdown.requiresSource(widthsLiteral))
        XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(widthsLiteral)), widthsLiteral)
        for intro in ["Intro", "# Intro"] { for action in ["bullet", "ordered"] {
            let source = intro + "\n\n    code\n"
            withEditor(source) { view, coordinator in
                let target = (view.string as NSString).range(of: "Intro")
                view.setSelectedRange(target); coordinator.action(action)
                XCTAssertEqual(Document(parsing: coordinator.lastMarkdown).children.compactMap { $0 as? CodeBlock }.map(\.code), ["code\n"], "Formatting before a code card cannot absorb it into a list: " + coordinator.lastMarkdown)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            }
        } }
        withEditor("    old\r\n") { view, coordinator in
            let target = (view.string as NSString).range(of: "old")
            view.setSelectedRange(target); view.insertText("\na\nb", replacementRange: target)
            XCTAssertFalse(coordinator.lastMarkdown.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "Fenced fallback must preserve the CRLF convention")
            XCTAssertEqual(Document(parsing: coordinator.lastMarkdown).children.compactMap { $0 as? CodeBlock }.map(\.code), ["\na\nb\n"])
        }

        for newline in ["\n", "\r\n"] { for indent in ["    ", "\t", " \t"] {
            let source = ["Before _spelling_.", "", indent + "print(\"old\")", indent + "**literal** @Cafe", "", "After _spelling_.", ""].joined(separator: newline)
            XCTAssertFalse(MacMarkdown.requiresSource(source), "Top-level indented code must open in native mode")
            guard !MacMarkdown.requiresSource(source) else { continue }
            withEditor(source) { view, coordinator in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                let target = (view.string as NSString).range(of: "old")
                XCTAssertNotNil(view.attributedString().attribute(.macCode, at: target.location, effectiveRange: nil))
                view.setSelectedRange(target); view.insertText("new 🧑🏽‍💻", replacementRange: target)
                let changed = MacMarkdown.markdown(view.attributedString())
                XCTAssertEqual(changed, source.replacingOccurrences(of: "old", with: "new 🧑🏽‍💻"))
                let code = Document(parsing: changed).children.compactMap { $0 as? CodeBlock }
                XCTAssertEqual(code.map(\.code), ["print(\"new 🧑🏽‍💻\")\n**literal** @Cafe\n"])
                XCTAssertTrue(view.string.contains("**literal** @Cafe")); XCTAssertFalse(coordinator.linkCompletion.shown)
                coordinator.action("undo"); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                coordinator.action("redo"); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), changed)
                let prose = (view.string as NSString).range(of: "After")
                view.setSelectedRange(prose); view.insertText("Following", replacementRange: prose)
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), changed.replacingOccurrences(of: "After _spelling_.", with: "Following *spelling*."))
            }
        } }
        for body in ["", "\nfirst", "first\n", " \nfirst\n ", "``` literal\n# literal", "\n```\n", "first\n\nlast"] {
            let source = "# Heading\n\n    original\n\nAfter.\n"
            withEditor(source) { view, coordinator in
                let target = (view.string as NSString).range(of: "original")
                view.setSelectedRange(target); view.insertText(body, replacementRange: target)
                let saved = MacMarkdown.markdown(view.attributedString())
                let blocks = Document(parsing: saved).children.compactMap { $0 as? CodeBlock }
                XCTAssertEqual(blocks.map(\.code), [body.isEmpty ? "" : body + "\n"], saved)
                XCTAssertFalse(MacMarkdown.requiresSource(saved))
                XCTAssertTrue(saved.hasSuffix("After.\n"))
                coordinator.action("undo"); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
            }
        }
        for source in ["    EOF", "# Heading\n    EOF", "    first\n\n    EOF\n", "\tfirst\r\n\r\n\tEOF"] {
            XCTAssertFalse(MacMarkdown.requiresSource(source))
            withEditor(source) { view, coordinator in
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                let target = (view.string as NSString).range(of: "EOF")
                view.setSelectedRange(target); view.insertText("Changed", replacementRange: target)
                let saved = coordinator.lastMarkdown
                XCTAssertEqual(Document(parsing: saved).children.compactMap { $0 as? CodeBlock }.map(\.code), Document(parsing: source.replacingOccurrences(of: "EOF", with: "Changed")).children.compactMap { $0 as? CodeBlock }.map(\.code))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            }
        }
    }
    @MainActor func testRichCodeEditingKeepsFenceSpellingLiteralTextAndSurroundingParagraphs() {
        for newline in ["\n", "\r\n"] {
            let source = ["# Café", "", "~~~swift extra", "    let value = \"old\"", "**literal** @Cafe", "~~~", "", "After _spelling_.", ""].joined(separator: newline)
            withEditor(source) { view, coordinator in
                XCTAssertFalse(MacMarkdown.requiresSource(source))
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                let rich = view.attributedString()
                let keyword = (view.string as NSString).range(of: "let")
                let string = (view.string as NSString).range(of: "old")
                let keywordColour = rich.attribute(.foregroundColor, at: keyword.location, effectiveRange: nil) as? NSColor
                let stringColour = rich.attribute(.foregroundColor, at: string.location, effectiveRange: nil) as? NSColor
                XCTAssertNotEqual(keywordColour, .labelColor); XCTAssertNotEqual(stringColour, .labelColor)
                XCTAssertNotEqual(keywordColour, stringColour)
                let target = (view.string as NSString).range(of: "old")
                view.setSelectedRange(target); view.insertText("new 🧑🏽‍💻", replacementRange: target)
                let changed = MacMarkdown.markdown(view.attributedString())
                XCTAssertEqual(changed, source.replacingOccurrences(of: "old", with: "new 🧑🏽‍💻"))
                XCTAssertTrue(view.string.contains("**literal** @Cafe")); XCTAssertFalse(coordinator.linkCompletion.shown)
                let edited = (view.string as NSString).range(of: "new 🧑🏽‍💻")
                XCTAssertEqual(view.attributedString().attribute(.foregroundColor, at: edited.location, effectiveRange: nil) as? NSColor, stringColour)
                coordinator.action("undo"); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                coordinator.action("redo"); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), changed)
                let prose = (view.string as NSString).range(of: "After")
                view.setSelectedRange(prose); view.insertText("Following", replacementRange: prose)
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), changed.replacingOccurrences(of: "After _spelling_.", with: "Following *spelling*."))
            }
        }
    }
    @MainActor func testCodeColoursRespectLanguageTokensAndNeverLeakIntoNeighbouringProse() {
        let samples: [(String, String, [String])] = [
            ("json", #"{"url":"https://example.test/#anchor","enabled":true,"count":42}"#, ["#anchor", "true", "42"]),
            ("python", "# A comment\nvalue = \"not # a comment\"\nprint(value)", ["# A comment", "not # a comment"]),
            ("html", #"<!-- A comment --><a href="https://example.test">Hello</a>"#, ["A comment", "<a", "https://example.test"]),
            ("sql", "select 'not -- a comment', 42 -- A comment", ["select", "not -- a comment", "A comment"]),
            ("unknown-language", "let literal = 42", ["let", "42"]),
        ]
        for (language, code, tokens) in samples {
            let source = "```" + language + "\n" + code + "\n```\n\nAfter prose.\n"
            let rich = MacMarkdown.render(source)
            XCTAssertEqual(MacMarkdown.markdown(rich), source)
            var colours: [NSColor] = []
            for word in tokens {
                let range = (rich.string as NSString).range(of: word)
                XCTAssertNotEqual(range.location, NSNotFound)
                if range.location != NSNotFound, let colour = rich.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor { colours.append(colour) }
            }
            XCTAssertEqual(colours.count, tokens.count)
            if language == "unknown-language" { XCTAssertTrue(colours.allSatisfy { $0 == .labelColor }) }
            else {
                XCTAssertTrue(colours.allSatisfy { $0 != .labelColor })
                for i in colours.indices { for j in colours.indices where i != j { XCTAssertNotEqual(colours[i], colours[j], language) } }
            }
            let prose = (rich.string as NSString).range(of: "After prose.")
            XCTAssertEqual(rich.attribute(.foregroundColor, at: prose.location, effectiveRange: nil) as? NSColor, .labelColor)
        }
        // Live prose edits keep code presentation, while later code edits
        // must still reclassify tokens and survive Undo/Redo.
        let source = "Before prose.\n\n```swift\nlet answer = 42\n```\n\nAfter prose.\n"
        withEditor(source) { view, coordinator in
            func colour(_ word: String) -> NSColor? {
                let range = (view.string as NSString).range(of: word)
                guard range.location != NSNotFound else { XCTFail("Missing token: " + word); return nil }
                return view.attributedString().attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
            }
            let keyword = colour("let"), number = colour("42")
            let prose = (view.string as NSString).range(of: "Before")
            view.setSelectedRange(prose); view.insertText("Updated", replacementRange: prose)
            XCTAssertEqual(colour("let"), keyword); XCTAssertEqual(colour("42"), number)
            XCTAssertEqual(coordinator.lastMarkdown, source.replacingOccurrences(of: "Before", with: "Updated"))
            let token = (view.string as NSString).range(of: "let")
            view.setSelectedRange(token); view.insertText("plain", replacementRange: token)
            XCTAssertEqual(colour("plain"), .labelColor, "A token that stops being a keyword must lose its keyword colour")
            XCTAssertEqual(colour("42"), number)
            coordinator.action("undo"); XCTAssertEqual(colour("let"), keyword)
            coordinator.action("redo"); XCTAssertEqual(colour("plain"), .labelColor)
            XCTAssertTrue(coordinator.lastMarkdown.contains("plain answer = 42"))
        }
    }

    @MainActor func testEditingOneParagraphKeepsOtherTokens() {
        let examples = [
            "# Title\n\nA *word*.\n\nUnusual **spelling** and [[zerus:id|Link]].\n",
            "\\# Literal word\n", "\\- Literal word\n", "1\\. Literal word\n",
        ]
        for source in examples {
            let rich = NSMutableAttributedString(attributedString: MacMarkdown.render(source))
            let range = (rich.string as NSString).range(of: "word")
            rich.replaceCharacters(in: range, with: "sentence")
            XCTAssertEqual(MacMarkdown.markdown(rich), source.replacingOccurrences(of: "word", with: "sentence"))
        }
    }
    @MainActor func testFormattingSelectionPersistsAsMarkdown() {
        let rich = NSMutableAttributedString(attributedString: MacMarkdown.render("A plain word.\n"))
        let range = (rich.string as NSString).range(of: "plain")
        rich.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 15), range: range)
        XCTAssertEqual(MacMarkdown.markdown(rich), "A **plain** word.\n")
    }
    @MainActor func testMultilineEmphasisRendersAndEditingEitherLinePreservesItsMeaning() {
      for (prefix, continuation, depth) in [("", "", 0), ("> ", "> ", 1), ("> ", "", 1), ("> > ", "> > ", 2), ("> > ", "> ", 2)] {
        for newline in ["\n", "\r\n"] {
          for breakMarker in ["", "  ", "\\"] {
            let source = prefix + "First **bold" + breakMarker + newline + continuation + "and *nested* text** end." + newline + newline + "Keep _this spelling_." + newline
            XCTAssertFalse(MacMarkdown.requiresSource(source), source)
            for word in ["bold", "nested"] {
                withEditor(source) { view, coordinator in
                    XCTAssertEqual(view.string, "First bold\nand nested text end.\n\nKeep this spelling.\n")
                    let raw = view.string as NSString, selected = raw.range(of: word)
                    guard selected.location != NSNotFound else { return XCTFail("Multiline delimiters must be rendered, not displayed") }
                    let initial = view.attributedString().attributes(at: selected.location, effectiveRange: nil)
                    XCTAssertTrue(MacMarkdown.inlineBold(initial, block: ""))
                    if word == "nested" { XCTAssertTrue(NSFontManager.shared.traits(of: initial[.font] as? NSFont ?? .systemFont(ofSize: 15)).contains(.italicFontMask)) }
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                    view.setSelectedRange(selected); coordinator.action("italic")
                    let saved = MacMarkdown.markdown(view.attributedString())
                    let parsed = Document(parsing: saved)
                    func styles(_ node: any Markup, strong: Bool = false, emphasis: Bool = false, quoteDepth: Int = 0) -> [(String, Bool, Bool, Int)] {
                        let strong = strong || node is Strong, emphasis = emphasis || node is Emphasis
                        let quoteDepth = quoteDepth + (node is BlockQuote ? 1 : 0)
                        if let text = node as? Markdown.Text { return [(text.string, strong, emphasis, quoteDepth)] }
                        return node.children.flatMap { styles($0, strong: strong, emphasis: emphasis, quoteDepth: quoteDepth) }
                    }
                    let runs = styles(parsed), run = runs.first { $0.0.contains(word) }
                    XCTAssertEqual(run?.1, true, saved); XCTAssertEqual(run?.2, word == "bold", saved)
                    XCTAssertEqual(run?.3, depth, saved)
                    for other in ["bold", "nested", "text"] { XCTAssertEqual(runs.first { $0.0.contains(other) }?.1, true, saved) }
                    func hardBreaks(_ node: any Markup) -> Int { (node is LineBreak ? 1 : 0) + node.children.reduce(0) { $0 + hardBreaks($1) } }
                    XCTAssertEqual(hardBreaks(parsed), breakMarker.isEmpty ? 0 : 1, saved)
                    XCTAssertTrue(saved.hasSuffix(newline + newline + "Keep _this spelling_." + newline))
                    let reopened = MacMarkdown.render(saved)
                    XCTAssertEqual(reopened.string, view.string)
                    let range = (reopened.string as NSString).range(of: word)
                    let attrs = reopened.attributes(at: range.location, effectiveRange: nil)
                    XCTAssertTrue(MacMarkdown.inlineBold(attrs, block: ""))
                    view.undoManager?.undo(); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                    view.undoManager?.redo(); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), saved)
                }
            }
          }
        }
      }
    }
    @MainActor func testFormattingWhitespaceAcrossLinesProducesValidCommonMark() {
        withEditor("Café one\nsecond line.\n\nLeave _this spelling_.\n") { view, coordinator in
            view.setSelectedRange((view.string as NSString).range(of: " one\nsecond ")); coordinator.action("bold")
            let saved = MacMarkdown.markdown(view.attributedString())
            func strongWords(_ node: any Markup) -> [String] {
                if let strong = node as? Strong { return [strong.plainText] }
                return node.children.flatMap(strongWords)
            }
            XCTAssertEqual(strongWords(Document(parsing: saved)), ["one", "second"], saved)
            XCTAssertTrue(saved.hasSuffix("\n\nLeave _this spelling_.\n"))
            XCTAssertEqual(MacMarkdown.render(saved).string, view.string)
        }
    }
    @MainActor func testInlineCodeFormattingRetainsLiteralBackticksSpacesAndNestedTraits() {
        let literals = ["simple", "a`\u{0301}b", "`\u{0301}edge", "a``b", "x```y", "`edge`", "  keep  ", " leading", "trailing ", "   ", "Café **tag** [x] \\ end"]
        for literal in literals {
            let escaped = literal.replacingOccurrences(of: #"([\\*_`~\[\]<>])"#, with: #"\\$1"#, options: .regularExpression)
            let source = "Before " + escaped + " after.\n\nKeep _this spelling_.\n"
            for nested in [false, true] {
                withEditor(source) { view, coordinator in
                    XCTAssertEqual(view.string, "Before " + literal + " after.\n\nKeep this spelling.\n")
                    let selection = NSRange(location: 7, length: (literal as NSString).length)
                    view.setSelectedRange(selection)
                    if nested { coordinator.action("bold"); coordinator.action("italic") }
                    let beforeCode = MacMarkdown.markdown(view.attributedString())
                    view.undoManager?.removeAllActions()
                    coordinator.action("code")
                    let saved = MacMarkdown.markdown(view.attributedString())
                    func codes(_ node: any Markup) -> [InlineCode] { if let code = node as? InlineCode { return [code] }; return node.children.flatMap(codes) }
                    let spans = codes(Document(parsing: saved))
                    XCTAssertEqual(spans.map(\.code), [literal], saved)
                    XCTAssertTrue(saved.hasSuffix("\n\nKeep _this spelling_.\n"))
                    let reopened = MacMarkdown.render(saved)
                    XCTAssertEqual(reopened.string, view.string, saved)
                    let font = reopened.attribute(.font, at: selection.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
                    let traits = NSFontManager.shared.traits(of: font)
                    XCTAssertTrue(traits.contains(.fixedPitchFontMask), saved)
                    if nested { XCTAssertTrue(traits.contains(.boldFontMask), saved); XCTAssertTrue(traits.contains(.italicFontMask), saved) }
                    view.undoManager?.undo(); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), beforeCode)
                    view.undoManager?.redo(); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), saved)
                }
            }
        }
    }
    @MainActor func testPortableImageSizesKeepAspectRatioAndTitlesWithoutEnablingOtherHtml() throws {
        let image = NSImage(size: NSSize(width: 800, height: 400))
        for (source, width, height) in [
            ("![Caption|240](assets/image.png \"Original title\")", 240.0, 120.0),
            ("<img src=\"assets/image.png\" alt=\"Caption\" title=\"Original title\" width=\"240\" />", 240.0, 120.0),
            ("<img src=\"assets/image.png\" alt=\"Caption\" height=\"60\" />", 120.0, 60.0),
            ("<img src=\"assets/image.png\" alt=\"Caption\" width=\"240\" height=\"90\" />", 240.0, 90.0)
        ] {
            XCTAssertFalse(MacMarkdown.requiresSource(source))
            let rich = MacMarkdown.render(source, images: ["assets/image.png": image])
            let attachment = try XCTUnwrap(rich.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
            XCTAssertEqual(attachment.bounds.size, NSSize(width: width, height: height))
            XCTAssertEqual(MacMarkdown.markdown(rich), source)
            let narrowed = attachment.attachmentBounds(for: nil, proposedLineFragment: NSRect(x: 0, y: 0, width: 100, height: 1000), glyphPosition: .zero, characterIndex: 0)
            XCTAssertLessThanOrEqual(narrowed.width, 100)
            XCTAssertEqual(narrowed.width / narrowed.height, width / height, accuracy: 0.001)
        }
        for source in ["<div>HTML</div>", "<img src=\"x\" onerror=\"run()\" />", "<img src=\"x\" width=\"huge\" />", "<img src=\"x\" /><script>x</script>"] { XCTAssertFalse(MacMarkdown.requiresSource(source), "Rich text is the default; Source is only an explicit choice") }
    }
    @MainActor func testQueuedEditorSnapshotsReadTheCurrentDraftWithoutClearingImageUndo() throws {
        for ending in ["\n", "\r\n"] {
            let source = "Before\n\n![Caption](diagram.png)\n\nAfter.\n".replacingOccurrences(of: "\n", with: ending)
            let changed = "Before\n\n![Changed](<diagram.png>)\n\nAfter.\n".replacingOccurrences(of: "\n", with: ending)
            var model = source, modelSource = false
            let image = NSImage(size: NSSize(width: 200, height: 100))
            func surface(_ snapshot: String) -> MacRichEditor {
                MacRichEditor(markdown: snapshot, source: false, editable: true, images: ["diagram.png": image], onChange: { model = $0 }, onLink: { _ in }, readDocument: { (model, modelSource) })
            }
            try withHostedEditor(surface(source)) { view, coordinator, host in
                func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) } }
                let index = (view.string as NSString).range(of: "\u{fffc}").location
                let request = try coordinator.prepareImageEdit(at: index)
                var edited = request.value; edited.caption = "Changed"
                try coordinator.applyImage(request, value: edited)
                XCTAssertEqual(model, changed)
                // Window updates can already be queued with the pre-edit value.
                // The bridge must read the live model rather than replay it.
                host.rootView = surface(source); settle()
                XCTAssertEqual(coordinator.lastMarkdown, changed)
                XCTAssertTrue(view.undoManager?.canUndo == true)
                view.undoManager?.undo(); host.rootView = surface(changed); settle()
                XCTAssertEqual(model, source); XCTAssertEqual(coordinator.lastMarkdown, source)
                view.undoManager?.redo(); host.rootView = surface(source); settle()
                XCTAssertEqual(model, changed); XCTAssertEqual(coordinator.lastMarkdown, changed)
                model = "# Outside\n\nPeer text.\n".replacingOccurrences(of: "\n", with: ending); modelSource = true
                host.rootView = surface(changed); settle()
                XCTAssertEqual(coordinator.lastMarkdown, model, "A real replacement must still reload even when its view snapshot is old")
                XCTAssertEqual(view.string, model); XCTAssertTrue(coordinator.source)
                XCTAssertFalse(view.undoManager?.canUndo == true)
                XCTAssertThrowsError(try coordinator.applyImage(request, value: edited))
                modelSource = false; host.rootView = surface(changed); settle()
                XCTAssertFalse(coordinator.source); XCTAssertTrue(view.string.contains("Peer text."))
            }
        }
    }
    @MainActor func testEditingOneImagePreservesOtherOccurrencesFilesAndUndoAndRejectsStaleRequests() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), file = root.appendingPathComponent("assets/image.png")
        try bytes.write(to: file)
        let source = "Before ![Caption](assets/image.png \"Original title\") after.\n\nKeep _this spelling_.\n\n![Second](assets/image.png)\n"
        try withEditor(source, root: root, path: "Work/note.md") { view, coordinator in
            let index = (view.string as NSString).range(of: "\u{fffc}").location
            let request = try coordinator.prepareImageEdit(at: index)
            XCTAssertEqual(request.value.title, "Original title")
            let edited = MacInlineImage(reference: request.value.reference, caption: "Diagram [Q4] & café", title: "Updated title", width: 240)
            try coordinator.applyImage(request, value: edited)
            let saved = MacMarkdown.markdown(view.attributedString())
            XCTAssertTrue(saved.contains("width=\"240\"")); XCTAssertTrue(saved.contains("Diagram [Q4] &amp; café")); XCTAssertTrue(saved.contains("title=\"Updated title\""))
            XCTAssertTrue(saved.hasSuffix("\n\nKeep _this spelling_.\n\n![Second](assets/image.png)\n"))
            let reopened = MacMarkdown.render(saved, root: root, path: "Work/note.md")
            let first = try XCTUnwrap(reopened.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment)
            XCTAssertEqual(first.bounds.size, NSSize(width: 240, height: 120)); XCTAssertFalse(MacMarkdown.requiresSource(saved))
            view.undoManager?.undo(); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
            view.undoManager?.redo(); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), saved)
            let resized = try coordinator.prepareImageEdit(at: index); try coordinator.applyImage(resized, value: nil)
            XCTAssertFalse(MacMarkdown.markdown(view.attributedString()).contains("width=")); view.undoManager?.undo()
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), saved)
            coordinator.load("Another document", source: false)
            XCTAssertThrowsError(try coordinator.applyImage(request, value: edited)); XCTAssertEqual(view.string, "Another document")
        }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    @MainActor func testNativeImageHandleDragCommitsOnceAndEscapeLeavesSourceUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), file = root.appendingPathComponent("image.png")
        try bytes.write(to: file)
        let source = "# Drag\n\n<img src=\"image.png\" alt=\"Café &amp; notes\" title=\"Keep title\" width=\"240\" />\n\nKeep _this spelling_.\n\n![Second|80](image.png)\n"
        var latest = source
        let editor = MacRichEditor(markdown: source, source: false, editable: true, root: root, path: "note.md", onChange: { latest = $0 }, onLink: { _ in })
        let host = NSHostingView(rootView: editor)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func textView(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { textView($0) }.first
        }
        let view = try XCTUnwrap(textView(host)); window.makeFirstResponder(view)
        let index = (view.string as NSString).range(of: "\u{fffc}").location
        let manager = try XCTUnwrap(view.layoutManager), container = try XCTUnwrap(view.textContainer)
        func imageRect() -> NSRect {
            manager.ensureLayout(for: container)
            let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            let bounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
            return NSRect(origin: NSPoint(x: bounds.minX + view.textContainerOrigin.x, y: bounds.minY + view.textContainerOrigin.y), size: manager.attachmentSize(forGlyphAt: glyphs.location))
        }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let initial = imageRect(); XCTAssertEqual(initial.width, 240, accuracy: 1)
        view.mouseDown(with: try mouse(.leftMouseDown, NSPoint(x: initial.midX, y: initial.midY)))
        XCTAssertEqual(view.selectedRange(), NSRange(location: index, length: 1))
        let start = NSPoint(x: initial.maxX, y: initial.maxY)
        view.mouseDown(with: try mouse(.leftMouseDown, start))
        for delta in [20.0, 40.0, 60.0] { view.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: start.x - delta, y: start.y - delta / 2))) }
        XCTAssertEqual(latest, source, "A drag preview must not write intermediate edits")
        view.mouseUp(with: try mouse(.leftMouseUp, NSPoint(x: start.x - 60, y: start.y - 30)))
        let resized = source.replacingOccurrences(of: "width=\"240\"", with: "width=\"180\"")
        XCTAssertEqual(latest, resized); XCTAssertEqual(imageRect().size, NSSize(width: 180, height: 90))
        view.undoManager?.undo(); XCTAssertEqual(latest, source)
        view.undoManager?.redo(); XCTAssertEqual(latest, resized)
        view.setSelectedRange(NSRange(location: index, length: 1))
        let cancelRect = imageRect(), cancelStart = NSPoint(x: cancelRect.maxX, y: cancelRect.maxY)
        view.mouseDown(with: try mouse(.leftMouseDown, cancelStart))
        view.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: cancelStart.x - 50, y: cancelStart.y - 25)))
        view.cancelOperation(nil)
        view.mouseUp(with: try mouse(.leftMouseUp, cancelStart))
        XCTAssertEqual(latest, resized); XCTAssertEqual(imageRect().size, NSSize(width: 180, height: 90))
        view.undoManager?.undo(); XCTAssertEqual(latest, source, "Cancellation must not add an undo step")
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    @MainActor func testAutolinksUseRichTextWhileActualHTMLKeepsSourceFallback() {
        let source = "# Saved page\n\n<https://example.com/>\n\nAnnotations.\n"
        XCTAssertFalse(MacMarkdown.requiresSource(source))
        XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(source)), source)
        for html in ["<div>content</div>", "<!-- retained comment -->", "Inline <span>HTML</span>"] { XCTAssertFalse(MacMarkdown.requiresSource(html), "Rich text is the default; Source is only an explicit choice") }
    }
    @MainActor func testStyledNoteLabelsRemainOneLinkWithCompleteIdentityAfterSaveAndReopen() {
        for (link, label, word) in [
            ("[[zerus:target|Project plan]]", "Project plan", "Project"),
            ("[Plan \\[Q4\\] | café](#zerus-note:zerus%3Atarget%7CPlan%20%5BQ4%5D%20%7C%20caf%C3%A9)", "Plan [Q4] | café", "Plan")
        ] {
            for style in ["bold", "italic", "code"] {
                let source = "Read " + link + " now.\n\nKeep _this spelling_.\n"
                withEditor(source) { view, coordinator in
                    view.setSelectedRange((view.string as NSString).range(of: word)); coordinator.action(style)
                    let saved = MacMarkdown.markdown(view.attributedString())
                    func links(_ node: any Markup) -> [Markdown.Link] {
                        if let link = node as? Markdown.Link { return [link] }
                        return node.children.flatMap(links)
                    }
                    let stored = links(Document(parsing: NoteReference.inlineMarkdown(saved)))
                    XCTAssertEqual(stored.count, 1, "Mixed formatting must not split a note link")
                    func visible(_ node: any Markup) -> String {
                        if let text = node as? Markdown.Text { return text.string }
                        if let code = node as? InlineCode { return code.code }
                        return node.children.map(visible).joined()
                    }
                    XCTAssertEqual(stored.first.map(visible), label)
                    XCTAssertEqual(stored.first?.destination.flatMap(URL.init(string:)).flatMap(NoteReference.init(url:))?.target, "zerus:target")
                    XCTAssertEqual(stored.first?.destination.flatMap(URL.init(string:)).flatMap(NoteReference.init(url:))?.label, label)
                    XCTAssertTrue(saved.hasSuffix("\n\nKeep _this spelling_.\n"))
                    let reopened = MacMarkdown.render(saved), range = (reopened.string as NSString).range(of: word)
                    XCTAssertEqual(reopened.string, "Read " + label + " now.\n\nKeep this spelling.\n")
                    let attributes = reopened.attributes(at: range.location, effectiveRange: nil), font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 15)
                    let traits = NSFontManager.shared.traits(of: font)
                    if style == "bold" { XCTAssertTrue(MacMarkdown.inlineBold(attributes, block: "")) }
                    if style == "italic" { XCTAssertTrue(traits.contains(.italicFontMask)) }
                    if style == "code" { XCTAssertTrue(traits.contains(.fixedPitchFontMask)) }
                    view.undoManager?.undo(); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
                    view.undoManager?.redo(); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), saved)
                    if label == "Project plan" {
                        view.setSelectedRange((view.string as NSString).range(of: "plan")); view.insertText("roadmap", replacementRange: view.selectedRange())
                        let edited = MacMarkdown.markdown(view.attributedString()), updatedLinks = links(Document(parsing: NoteReference.inlineMarkdown(edited)))
                        XCTAssertEqual(updatedLinks.count, 1)
                        let reference = updatedLinks.first?.destination.flatMap(URL.init(string:)).flatMap(NoteReference.init(url:))
                        XCTAssertEqual(reference?.target, "zerus:target"); XCTAssertEqual(reference?.label, "Project roadmap")
                        XCTAssertEqual(MacMarkdown.render(edited).string, "Read Project roadmap now.\n\nKeep this spelling.\n")
                    }
                }
            }
        }
    }
    @MainActor func testNativeBlockFormattingShowsMarkersAndRetainsInlineTraits() {
        let quoted = "> First line\n> Second line\n\nAfter.\n"
        withEditor(quoted) { view, coordinator in
            view.setSelectedRange((view.string as NSString).range(of: "First"))
            coordinator.action("paragraph")
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), "First line\n\n> Second line\n\nAfter.\n")
            coordinator.action("undo"); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), quoted)
            coordinator.action("redo"); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), "First line\n\n> Second line\n\nAfter.\n")
        }
        withEditor("A **bold** word.\nSecond *thought*.\n\nLeave _this spelling_.\n") { view, coordinator in
            view.setSelectedRange((view.string as NSString).range(of: "A bold word.\nSecond thought."))
            coordinator.action("checklist")
            XCTAssertTrue(view.string.hasPrefix("☐ A bold word.\n☐ Second thought."))
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), "- [ ] A **bold** word.\n- [ ] Second *thought*.\n\nLeave _this spelling_.\n")
            coordinator.action("toggleChecklist")
            XCTAssertTrue(MacMarkdown.markdown(view.attributedString()).hasPrefix("- [x] A **bold** word."))
            coordinator.action("toggleChecklist")
            coordinator.action("h2")
            XCTAssertTrue(view.string.hasPrefix("A bold word.\nSecond thought."))
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), "## A **bold** word.\n## Second *thought*.\n\nLeave _this spelling_.\n")
            coordinator.action("paragraph")
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), "A **bold** word.\n\nSecond *thought*.\n\nLeave _this spelling_.\n")
            XCTAssertEqual(Document(parsing: coordinator.lastMarkdown).children.compactMap { ($0 as? Paragraph)?.plainText }, ["A bold word.", "Second thought.", "Leave this spelling."])
        }
        for (command, prefix, level) in [("h1", "# ", 1), ("h2", "## ", 2), ("h3", "### ", 3), ("h4", "#### ", 4), ("h5", "##### ", 5), ("h6", "###### ", 6)] {
            for sourceMode in [false, true] { for ending in ["\n", "\r\n", "\r"] {
                let source = "Start **bold** finish.\n\nKeep _this spelling_.\n".replacingOccurrences(of: "\n", with: ending)
                let expected = prefix + source
                withEditor(source, sourceMode: sourceMode) { view, coordinator in
                    view.setSelectedRange((view.string as NSString).range(of: "Start"))
                    coordinator.action(command)
                    XCTAssertEqual(coordinator.lastMarkdown, expected)
                    let heading = Document(parsing: coordinator.lastMarkdown).children.compactMap { $0 as? Heading }.first
                    XCTAssertEqual(heading?.level, level); XCTAssertEqual(heading?.plainText, "Start bold finish.")
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                    let word = (view.string as NSString).range(of: "Start")
                    guard word.location != NSNotFound else { XCTFail("The heading text must remain editable"); return }
                    view.setSelectedRange(word); view.insertText("New", replacementRange: word)
                    XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "Start", with: "New"))
                }
            } }
        }
    }
    @MainActor func testNonListFormattingPreservesFollowingContentAndMapsTheSelection() throws {
        for (source, word, through, command, expected, typed, expectedParents) in [
            ("10. Parent\n    - Child\n\n    Tail\n11. Sib\n", "Parent", nil as String?, "h1", "# Parent\n- Child\n\nTail\n\n11. Sib\n", "# New\n- Child\n\nTail\n\n11. Sib\n", [nil, nil] as [Int?]),
            ("- Before\n- Parent\n  - Child\n\n  Tail\n- Sib\n", "Parent", nil, "paragraph", "- Before\n\nParent\n\n- Child\n\nTail\n\n- Sib\n", "- Before\n\nNew\n\n- Child\n\nTail\n\n- Sib\n", [nil, nil, nil]),
            ("- Root\n  - Parent\n    - Child\n\n    Tail\n  - Peer\n\n  Root tail\n- Sib\n", "Parent", nil, "h1", "- Root\n# Parent\n- Child\n\nTail\n\n- Peer\n\nRoot tail\n\n- Sib\n", "- Root\n# New\n- Child\n\nTail\n\n- Peer\n\nRoot tail\n\n- Sib\n", [nil, nil, nil, nil]),
            ("> 10. Parent\n>     - Child\n>\n>     Tail\n> 11. Sib\n", "Parent", nil, "h2", "> ## Parent\n> - Child\n> \n> Tail\n> \n> 11. Sib\n", "> ## New\n> - Child\n> \n> Tail\n> \n> 11. Sib\n", [nil, nil]),
            ("- Parent\n  - Child\n\n  Tail\n- Sib\n", "Parent", nil, "quote", "> Parent\n\n- Child\n\nTail\n\n- Sib\n", "> New\n\n- Child\n\nTail\n\n- Sib\n", [nil, nil]),
            ("- Parent\n  - Child\n\n  Tail\n  - Later\n- Sib\n", "Tail", nil, "h2", "- Parent\n  - Child\n\n## Tail\n- Later\n- Sib\n", "- Parent\n  - Child\n\n## New\n- Later\n- Sib\n", [nil, 0, nil, nil]),
            ("10. 😀 Parent\n\n    More\n    - Child\n\n    Tail\n11. Sib\n", "More", nil, "h1", "# 😀 Parent More\n- Child\n\nTail\n\n11. Sib\n", "# 😀 Parent New\n- Child\n\nTail\n\n11. Sib\n", [nil, nil]),
            ("- Parent\n  - Child\n\n  Tail\n- Sib\n", "Parent", "Tail", "h1", "# Parent\n# Child\n\n# Tail\n- Sib\n", "# New\n- Sib\n", [nil]),
            ("> - A\n> - Parent\n>   - Child\n>\n>   Tail\n> - Sib\n", "Parent", nil, "quote", "> - A\n> \n> Parent\n> \n> - Child\n> \n> Tail\n> \n> - Sib\n", "> - A\n> \n> New\n> \n> - Child\n> \n> Tail\n> \n> - Sib\n", [nil, nil, nil]),
            ("10. Parent\n    - Child\n11. Sib\n", "Parent", nil, "h1", "# Parent\n- Child\n11. Sib\n", "# New\n- Child\n11. Sib\n", [nil, nil])
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending), typed = typed.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let first = (view.string as NSString).range(of: word), last = through.map { (view.string as NSString).range(of: $0) } ?? first
                let selection = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
                view.setSelectedRange(selection); coordinator.action(command)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                let mapped = view.selectedRange(), selected = (view.string as NSString).substring(with: mapped)
                if through == nil { XCTAssertEqual(selected, word, "Collapsed logical gaps must not shift the selected word") }
                else { XCTAssertTrue(selected.hasPrefix(word)); XCTAssertTrue(selected.hasSuffix(through!)); XCTAssertFalse(selected.contains("Sib")) }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), mapped)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                var parents: [Int?] = []
                func collect(_ node: any Markup, owner: Int? = nil) {
                    var owner = owner
                    if node is ListItem { let index = parents.count; parents.append(owner); owner = index }
                    for child in node.children { collect(child, owner: owner) }
                }
                collect(Document(parsing: coordinator.lastMarkdown)); XCTAssertEqual(parents, expectedParents)
                XCTAssertFalse(MacMarkdown.requiresSource(typed))
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), coordinator.lastMarkdown)
            }
        } }
        // Existing inner roles stay in their item; the earlier rows continue
        // to own ordinary flat-list wrapper removal. Public admission is tested
        // separately by the workspace's Source-mode owner.
        func innerShape(_ source: String) -> (parents: [Int?], roles: [String]) {
            var parents: [Int?] = [], roles: [String] = []
            func walk(_ node: any Markup, owner: Int? = nil) {
                var owner = owner
                if node is ListItem { let next = parents.count; parents.append(owner); owner = next }
                if let heading = node as? Heading { roles.append("h\(heading.level):" + (owner.map(String.init) ?? "root")) }
                if node is BlockQuote { roles.append("q:" + (owner.map(String.init) ?? "root")) }
                for child in node.children { walk(child, owner: owner) }
            }
            walk(Document(parsing: source)); return (parents, roles)
        }
        for (source, command, expected, roles, parents) in [
            ("- # Inner\n- Sibling\n", "h2", "- ## Inner\n- Sibling\n", ["h2:0"], [nil, nil] as [Int?]),
            ("- # Inner\n- Sibling\n", "paragraph", "- Inner\n- Sibling\n", [], [nil, nil]),
            ("- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", "h1", "- Parent\n\n  # Inner\n\n  Tail\n- Sibling\n", ["h1:0"], [nil, nil]),
            ("- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", "paragraph", "- Parent\n\n  Inner\n\n  Tail\n- Sibling\n", [], [nil, nil]),
            ("- > Inner\n- Sibling\n", "h2", "- > ## Inner\n- Sibling\n", ["q:0", "h2:0"], [nil, nil]),
            ("- > Inner\n- Sibling\n", "paragraph", "- > Inner\n- Sibling\n", ["q:0"], [nil, nil]),
            ("- > Inner\n- Sibling\n", "quote", "- > > Inner\n- Sibling\n", ["q:0", "q:0"], [nil, nil]),
            ("- # Inner\n- Sibling\n", "quote", "- > Inner\n- Sibling\n", ["q:0"], [nil, nil]),
            ("- Parent\n\n  > Inner\n\n  Tail\n- Sibling\n", "paragraph", "- Parent\n\n  > Inner\n\n  Tail\n- Sibling\n", ["q:0"], [nil, nil]),
            ("- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", "quote", "- Parent\n\n  > Inner\n\n  Tail\n- Sibling\n", ["q:0"], [nil, nil]),
            ("- Root\n  - ## Inner\n  - Peer\n- Sibling\n", "h1", "- Root\n  - # Inner\n  - Peer\n- Sibling\n", ["h1:1"], [nil, 0, 0, nil]),
            ("> - Parent\n>\n>   ## Inner\n>\n>   Tail\n> - Sibling\n", "h1", "> - Parent\n>\n>   # Inner\n>\n>   Tail\n> - Sibling\n", ["q:root", "h1:0"], [nil, nil]),
            ("- Parent\n\n  > ## Inner\n  > Text\n- Sibling\n", "paragraph", "- Parent\n\n  > Inner\n  >\n  > Text\n- Sibling\n", ["q:0"], [nil, nil]),
            ("- Parent\n\n  > ## Inner\n  > Text\n- Sibling\n", "quote", "- Parent\n\n  > > Inner\n  >\n  > Text\n- Sibling\n", ["q:0", "q:0"], [nil, nil]),
            ("- Parent\n\n  > Inner  \n  > Next\n\n  Tail\n- Sibling\n", "h2", "- Parent\n\n  > ## Inner<br>Next\n\n  Tail\n- Sibling\n", ["q:0", "h2:0"], [nil, nil]),
            ("10. 😀 Parent\n\n    ## **Inner**\n\n    Tail\n11. Sibling\n", "h1", "10. 😀 Parent\n\n    # **Inner**\n\n    Tail\n11. Sibling\n", ["h1:0"], [nil, nil]),
            ("- Parent\n\n  Inner\n  ===\n\n  Tail\n- Sibling\n", "h2", "- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", ["h2:0"], [nil, nil]),
            ("- ## Inner", "paragraph", "- Inner", [], [nil])
        ] { for ending in (source.contains("\n") ? ["\n", "\r\n", "\r"] : ["\n"]) { for selected in [false, true] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in }, onPasteError: { issues.append($0) })) { view, coordinator, _ in
                let word = (view.string as NSString).range(of: "Inner")
                guard word.location != NSNotFound else { XCTFail("Missing inner formatting endpoint"); return }
                let selection = selected ? word : NSRange(location: NSMaxRange(word), length: 0)
                view.setSelectedRange(selection); coordinator.action(command)
                XCTAssertEqual(coordinator.lastMarkdown, expected, source); XCTAssertTrue(issues.isEmpty)
                let shape = innerShape(coordinator.lastMarkdown); XCTAssertEqual(shape.parents, parents); XCTAssertEqual(shape.roles, roles)
                let afterWord = (view.string as NSString).range(of: "Inner"), mapped = view.selectedRange()
                XCTAssertEqual(mapped, selected ? afterWord : NSRange(location: NSMaxRange(afterWord), length: 0))
                let role = command == "h1" ? "# " : command == "h2" ? "## " : ""
                XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, MacMarkdown.font(role).pointSize)
                XCTAssertEqual(view.undoManager?.undoActionName, "Format paragraph")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), mapped)
                view.insertText("New", replacementRange: mapped)
                let typed = expected.replacingOccurrences(of: "Inner", with: selected ? "New" : "InnerNew")
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                XCTAssertEqual(innerShape(coordinator.lastMarkdown).roles, roles)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(typed)), typed)
            }
        } } }
        for (source, word, through, command, expected, parents, roles) in [
            ("- # Inner\n- ## Second\n- Sibling\n", "Inner", "Second", "paragraph", "- Inner\n- Second\n- Sibling\n", [nil, nil, nil] as [Int?], [] as [String]),
            ("- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", "Parent", "Inner", "h1", "# Parent\n\n# Inner\n\nTail\n\n- Sibling\n", [nil], ["h1:root", "h1:root"]),
            ("- Parent\n\n  > Inner\n\n  Tail\n- Sibling\n", "Parent", "Parent", "h1", "# Parent\n\n> Inner\n\nTail\n\n- Sibling\n", [nil], ["h1:root", "q:root"]),
            ("- Parent\n\n  ## Inner<br>Next\n\n  Tail\n- Sibling\n", "Parent", "Parent", "h1", "# Parent\n\n## Inner<br>Next\n\nTail\n\n- Sibling\n", [nil], ["h1:root", "h2:root"]),
            ("- Parent\n\n  ## Inner\n\n  > ## Second\n\n  Tail\n- Sibling\n", "Inner", "Second", "h2", "- Parent\n\n  ## Inner\n\n  > ## Second\n\n  Tail\n- Sibling\n", [nil, nil], ["h2:0", "q:0", "h2:0"])
        ] { for ending in ["\n", "\r\n", "\r"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in }, onPasteError: { issues.append($0) })) { view, coordinator, _ in
                let first = (view.string as NSString).range(of: word), last = (view.string as NSString).range(of: through)
                guard first.location != NSNotFound, last.location != NSNotFound else { XCTFail("Missing mixed formatting endpoints"); return }
                let selection = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
                view.setSelectedRange(selection); coordinator.action(command)
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertTrue(issues.isEmpty)
                let shape = innerShape(coordinator.lastMarkdown); XCTAssertEqual(shape.parents, parents); XCTAssertEqual(shape.roles, roles)
                let mapped = view.selectedRange(), text = (view.string as NSString).substring(with: mapped)
                XCTAssertTrue(text.hasPrefix(word)); XCTAssertTrue(text.hasSuffix(through)); XCTAssertFalse(text.contains("Sibling"))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), mapped)
                let point = NSRange(location: NSMaxRange((view.string as NSString).range(of: word)), length: 0)
                view.setSelectedRange(point); view.insertText("New", replacementRange: point)
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: word, with: word + "New"))
            }
        } }
        // Converting a heading to a paragraph retains its live paragraph role
        // for the next Return instead of creating a sibling list item.
        for (source, formatted, typed, roles) in [
            ("- # Inner\n- Sibling\n", "- Inner\n- Sibling\n", "- Inner\n\n  New\n- Sibling\n", [] as [String]),
            ("- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", "- Parent\n\n  Inner\n\n  Tail\n- Sibling\n", "- Parent\n\n  Inner\n\n  New\n\n  Tail\n- Sibling\n", []),
            ("- Parent\n\n  > ## Inner\n\n  Tail\n- Sibling\n", "- Parent\n\n  > Inner\n\n  Tail\n- Sibling\n", "- Parent\n\n  > Inner\n  >\n  > New\n\n  Tail\n- Sibling\n", ["q:0"])
        ] { for ending in ["\n", "\r\n", "\r"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), formatted = formatted.replacingOccurrences(of: "\n", with: ending), typed = typed.replacingOccurrences(of: "\n", with: ending)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                let body = (view.string as NSString).range(of: "Inner")
                view.setSelectedRange(NSRange(location: NSMaxRange(body), length: 0)); coordinator.action("paragraph")
                XCTAssertEqual(coordinator.lastMarkdown, formatted)
                view.insertNewline(nil); view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                let shape = innerShape(coordinator.lastMarkdown); XCTAssertEqual(shape.parents, [nil, nil]); XCTAssertEqual(shape.roles, roles)
            }
        } }
        for ending in ["\n", "\r\n", "\r"] {
            let source = "> - Parent\n>\n>   > ## Inner\n>   > Text\n> - Sibling\n".replacingOccurrences(of: "\n", with: ending)
            let formatted = "> - Parent\n>\n>   > > Inner\n>   >\n>   > Text\n> - Sibling\n".replacingOccurrences(of: "\n", with: ending)
            let ordered = "> 1. Parent\n>\n>    > > Inner\n>    >\n>    > Text\n> - Sibling\n".replacingOccurrences(of: "\n", with: ending)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                view.setSelectedRange((view.string as NSString).range(of: "Inner"))
                coordinator.action("quote")
                XCTAssertEqual(coordinator.lastMarkdown, formatted)
                view.setSelectedRange((view.string as NSString).range(of: "Parent")); coordinator.action("ordered")
                XCTAssertEqual(coordinator.lastMarkdown, ordered)
                let shape = innerShape(coordinator.lastMarkdown); XCTAssertEqual(shape.parents, [nil, nil]); XCTAssertEqual(shape.roles, ["q:root", "q:0", "q:0"])
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, formatted)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, ordered)
            }
        }
        for (source, command, formatted, typed, roles) in [
            ("- # Inner\n- Sibling\n", "paragraph", "- \u{200b}\n- Sibling\n", "- New\n- Sibling\n", [] as [String]),
            ("- # Inner", "quote", "- > ", "- > New", ["q:0"]),
            ("- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", "paragraph", "- Parent\n\n  \u{200b}\n\n  Tail\n- Sibling\n", "- Parent\n\n  New\n\n  Tail\n- Sibling\n", []),
            ("- > Inner\n- Sibling\n", "h1", "- > # \n- Sibling\n", "- > # New\n- Sibling\n", ["q:0", "h1:0"])
        ] { for ending in (source.contains("\n") ? ["\n", "\r\n", "\r"] : ["\n"]) { for laterEvent in [false, true] {
            let source = source.replacingOccurrences(of: "\n", with: ending), formatted = formatted.replacingOccurrences(of: "\n", with: ending), typed = typed.replacingOccurrences(of: "\n", with: ending)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                view.setSelectedRange((view.string as NSString).range(of: "Inner")); view.insertText("", replacementRange: view.selectedRange())
                let cleared = coordinator.lastMarkdown, selection = view.selectedRange()
                coordinator.action(command); XCTAssertEqual(coordinator.lastMarkdown, formatted)
                if laterEvent { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
                let shape = innerShape(coordinator.lastMarkdown); XCTAssertEqual(shape.roles, roles)
                view.insertText("New", replacementRange: view.selectedRange()); XCTAssertEqual(coordinator.lastMarkdown, typed)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, formatted)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, cleared); XCTAssertEqual(view.selectedRange(), selection)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            }
        } } }
        // A toolbar-created quote is a leaf block. A later factory replaces
        // that leaf; it does not format a paragraph inside an imported quote.
        for (source, actions, expectedSteps) in [
            ("- # Inner\n- Sibling\n", ["quote", "paragraph"], ["- > Inner\n- Sibling\n", "- Inner\n- Sibling\n"]),
            ("- # Inner\n- Sibling\n", ["quote", "h2"], ["- > Inner\n- Sibling\n", "- ## Inner\n- Sibling\n"]),
            ("- # Inner\n- Sibling\n", ["quote", "quote"], ["- > Inner\n- Sibling\n", "- > Inner\n- Sibling\n"]),
            ("- > Inner\n- Sibling\n", ["quote", "paragraph"], ["- > > Inner\n- Sibling\n", "- > Inner\n- Sibling\n"]),
            ("- > Inner\n- Sibling\n", ["quote", "h2"], ["- > > Inner\n- Sibling\n", "- > ## Inner\n- Sibling\n"]),
            ("- # Inner\n- Sibling\n", ["paragraph", "quote", "paragraph"], ["- Inner\n- Sibling\n", "- > Inner\n- Sibling\n", "- Inner\n- Sibling\n"]),
            ("- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", ["quote", "paragraph"], ["- Parent\n\n  > Inner\n\n  Tail\n- Sibling\n", "- Parent\n\n  Inner\n\n  Tail\n- Sibling\n"]),
            ("- # Inner", ["quote", "paragraph"], ["- > Inner", "- Inner"]),
            ("- # Inner\n- Sibling\n", ["quote", "ordered", "paragraph"], ["- > Inner\n- Sibling\n", "1. > Inner\n- Sibling\n", "1. Inner\n- Sibling\n"]),
            ("- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", ["quote", "ordered", "paragraph"], ["- Parent\n\n  > Inner\n\n  Tail\n- Sibling\n", "1. Parent\n\n   > Inner\n\n   Tail\n- Sibling\n", "1. Parent\n\n   Inner\n\n   Tail\n- Sibling\n"]),
            ("- # Inner\n- Sibling\n", ["quote", "paragraph", "h1"], ["- > Inner\n- Sibling\n", "- Inner\n- Sibling\n", "- # Inner\n- Sibling\n"])
        ] { for ending in (source.contains("\n") ? ["\n", "\r\n", "\r"] : ["\n"]) {
            let source = source.replacingOccurrences(of: "\n", with: ending)
            let parents = innerShape(source).parents
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                view.setSelectedRange((view.string as NSString).range(of: "Inner"))
                for (command, expected) in zip(actions, expectedSteps) {
                    let before = coordinator.lastMarkdown, selected = view.selectedRange()
                    let expected = expected.replacingOccurrences(of: "\n", with: ending)
                    coordinator.action(command); XCTAssertEqual(coordinator.lastMarkdown, expected)
                    XCTAssertEqual(innerShape(coordinator.lastMarkdown).parents, parents)
                    let after = view.selectedRange(); XCTAssertEqual((view.string as NSString).substring(with: after), "Inner")
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.selectedRange(), selected)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), after)
                }
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expectedSteps.last!.replacingOccurrences(of: "Inner", with: "New").replacingOccurrences(of: "\n", with: ending))
            }
        } }
        for ending in ["\n", "\r\n", "\r"] {
            let input = "- # Inner\n- Sibling\n".replacingOccurrences(of: "\n", with: ending)
            let quoted = "- > Inner\n- Sibling\n".replacingOccurrences(of: "\n", with: ending)
            try withHostedEditor(MacRichEditor(markdown: input, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                view.setSelectedRange((view.string as NSString).range(of: "Inner")); coordinator.action("quote")
                XCTAssertEqual(coordinator.lastMarkdown, quoted)
                coordinator.load(quoted, source: false)
                view.setSelectedRange((view.string as NSString).range(of: "Inner")); coordinator.action("paragraph")
                XCTAssertEqual(coordinator.lastMarkdown, quoted, "Markdown import reconstructs a paragraph inside the quote")
            }
        }
        for (command, expected) in [
            ("paragraph", "> - Parent\n>\n>   Inner\n>\n>   Tail\n> - Sibling\n"),
            ("quote", "> - Parent\n>\n>   > Inner\n>\n>   Tail\n> - Sibling\n")
        ] { for ending in ["\n", "\r\n", "\r"] {
            let source = "> - Parent\n>   ## Inner\n>   Tail\n> - Sibling\n".replacingOccurrences(of: "\n", with: ending)
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                view.setSelectedRange((view.string as NSString).range(of: "Inner")); coordinator.action(command)
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "\n", with: ending))
                XCTAssertEqual(innerShape(coordinator.lastMarkdown).parents, [nil, nil])
            }
        } }
        for (source, command, expected) in [
            ("- A\n- ", "h1", "- A\n# New"),
            ("> - A\n> - ", "h2", "> - A\n> ## New"),
            ("- A\n- ", "paragraph", "- A\n\nNew"),
            ("- ", "h1", "# New"),
            ("Plain", "h1", "# PlainNew"),
            ("- A\n", "paragraph", "- A\n\nNew"),
            ("> A\n", "paragraph", "> A\n\nNew"),
            ("> - A\n> - ", "quote", "> - A\n> \n> New")
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let selected = NSRange(location: view.string.utf16.count, length: 0)
                view.setSelectedRange(selected); coordinator.action(command)
                let formatted = coordinator.lastMarkdown
                if source == "> A" + ending { coordinator.action(command); XCTAssertEqual(coordinator.lastMarkdown, formatted) }
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, formatted)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected, "Empty and EOF conversions must keep their requested typing style")
            }
        } }
        let codeSource = "- Parent\n  - Child\n\n```swift\nlet x = 1\n```\n\nAfter\n"
        withEditor(codeSource) { view, coordinator in
            let first = (view.string as NSString).range(of: "Parent"), last = (view.string as NSString).range(of: "After")
            let selection = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
            view.setSelectedRange(selection); coordinator.action("h2")
            let expected = "## Parent\n## Child\n\n```swift\nlet x = 1\n```\n\n## After\n"
            XCTAssertEqual(coordinator.lastMarkdown, expected, "Paragraph formatting must leave selected code cards intact")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, codeSource); XCTAssertEqual(view.selectedRange(), selection)
            coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
        }
        for command in ["paragraph", "h1"] { for ending in ["\n", "\r\n"] {
            withEditor("- Before\n- Parent\n  - Child\n- Sib\n".replacingOccurrences(of: "\n", with: ending)) { view, coordinator in
                let word = (view.string as NSString).range(of: "Parent")
                view.setSelectedRange(word); view.insertText("", replacementRange: word)
                let before = coordinator.lastMarkdown, selected = view.selectedRange()
                coordinator.action(command)
                let formatted = coordinator.lastMarkdown
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, formatted)
                view.insertText("New", replacementRange: view.selectedRange())
                let expected = command == "paragraph" ? "- Before\n\nNew\n\n- Child\n- Sib\n" : "- Before\n# New\n- Child\n- Sib\n"
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "\n", with: ending))
            }
        } }
        for ending in ["\n", "\r\n"] {
            withEditor("- Parent\n- A\n  - Empty".replacingOccurrences(of: "\n", with: ending)) { view, coordinator in
                let empty = (view.string as NSString).range(of: "Empty")
                view.setSelectedRange(empty); view.insertText("", replacementRange: empty)
                view.setSelectedRange((view.string as NSString).range(of: "Parent")); coordinator.action("h1")
                XCTAssertEqual(coordinator.lastMarkdown, "# Parent\n- A\n\n  - ".replacingOccurrences(of: "\n", with: ending))
            }
        }
        // Recovery of one unmapped empty child must not loosen an unrelated
        // tight list whose empty item already has a parser-owned boundary.
        for ending in ["\n", "\r\n"] {
            let source = "- First\n- \n- Keep\n\n- Parent\n- A\n  - Empty\n".replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let empty = (view.string as NSString).range(of: "Empty")
                view.setSelectedRange(empty); view.insertText("", replacementRange: empty)
                let before = coordinator.lastMarkdown
                let first = (view.string as NSString).range(of: "First")
                view.setSelectedRange(first); coordinator.action("h1")
                let expected = "# First\n- \n- Keep\n\n- Parent\n- A\n\n  - \n".replacingOccurrences(of: "\n", with: ending)
                XCTAssertEqual(coordinator.lastMarkdown, expected, "Only the unmapped empty child needs a new boundary")
                let formatted = coordinator.lastMarkdown, mapped = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.selectedRange(), first)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, formatted); XCTAssertEqual(view.selectedRange(), mapped)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "First", with: "New"))
                var parents: [Int?] = []
                func collect(_ node: any Markup, parent: Int? = nil) {
                    var parent = parent
                    if node is ListItem { let row = parents.count; parents.append(parent); parent = row }
                    for child in node.children { collect(child, parent: parent) }
                }
                collect(Document(parsing: coordinator.lastMarkdown)); XCTAssertEqual(parents, [nil, nil, nil, nil, 3])
            }
        }
        let tableSource = "- Parent\n\n| H |\n| --- |\n| x |\n\nAfter\n"
        withEditor(tableSource) { view, coordinator in
            let first = (view.string as NSString).range(of: "Parent"), last = (view.string as NSString).range(of: "After")
            let selection = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
            view.setSelectedRange(selection); coordinator.action("h2")
            let expected = "## Parent\n\n| H |\n| --- |\n| x |\n\n## After\n"
            XCTAssertEqual(coordinator.lastMarkdown, expected)
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, tableSource); XCTAssertEqual(view.selectedRange(), selection)
            coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
        }
        for (source, label, offset, expected) in [
            ("- [link](https://example.com) tail\n", "link", 0, "# New[link](https://example.com) tail\n"),
            ("- `code` tail\n", "code", 0, "# New`code` tail\n"),
            ("- ![image](pic.png) tail\n", "\u{fffc}", 0, "# New![image](<pic.png>) tail\n"),
            ("- **bold** tail\n", "bold", 2, "# **boNewld** tail\n"),
            ("- *ital* tail\n", "ital", 2, "# *itNewal* tail\n")
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let text = (view.string as NSString).range(of: label)
                guard text.location != NSNotFound else { XCTFail("Missing inline fixture"); return }
                let caret = NSRange(location: text.location + offset, length: 0)
                view.setSelectedRange(caret); coordinator.action("h1")
                let formatted = coordinator.lastMarkdown, mapped = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), caret)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, formatted); XCTAssertEqual(view.selectedRange(), mapped)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected, "Typing must use the preceding text style, not the following inline object")
            }
        } }
        for ending in ["\n", "\r\n"] {
            var issues: [String] = []
            withEditor("Top\n\n9. Parent\n   - Child\n".replacingOccurrences(of: "\n", with: ending), onPasteError: { issues.append($0) }) { view, coordinator in
                let child = (view.string as NSString).range(of: "Child")
                let start = (view.string as NSString).paragraphRange(for: child).location
                view.setSelectedRange(NSRange(location: start, length: 0)); view.insertText("\n", replacementRange: view.selectedRange())
                let before = coordinator.lastMarkdown, selected = (view.string as NSString).range(of: "Top")
                view.setSelectedRange(selected); coordinator.action("h1")
                let expected = before.replacingOccurrences(of: "Top", with: "# Top")
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertTrue(issues.isEmpty)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                issues.removeAll()
                let parent = (view.string as NSString).range(of: "Parent")
                view.setSelectedRange(parent); coordinator.action("h2")
                XCTAssertEqual(issues, ["This list needs Markdown source editing before its paragraph format can be changed."])
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected); XCTAssertEqual(view.selectedRange(), parent)
            }
        }
        let inlineTailSource = "10. Parent\n    - Child\n      - Grandchild\n\n      Tail **bold** [link](https://example.com)\n- Sib\n"
        withEditor(inlineTailSource) { view, coordinator in
            view.setSelectedRange((view.string as NSString).range(of: "Parent")); coordinator.action("h1")
            let expected = "# Parent\n- Child\n  - Grandchild\n\n  Tail **bold** [link](https://example.com)\n- Sib\n"
            XCTAssertEqual(coordinator.lastMarkdown, expected)
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, inlineTailSource)
            coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
        }
    }
    @MainActor func testDeletingAWholeListHeadPromotesChildrenAndRetainsRemainingParagraphs() {
        for (source, expected, roles) in [
            ("- Root\n  > Quote\n  >\n  > - Parent\n  >   - Child\n  >\n  >   Tail\n  > - Peer\n- Sib\n", "- Root\n  > Quote\n  >\n  > - Child\n  >\n  > Tail\n  > - Peer\n- Sib\n", [("New Child", 1, 2), ("Tail", 1, 1)]),
            ("10. Root\n    > Quote\n    >\n    > 9. Parent\n    >    - Child\n    >\n    >    Tail\n    >\n    > 10. Peer\n11. Sib\n", "10. Root\n    > Quote\n    >\n    > - Child\n    >\n    > Tail\n    >\n    > 9. Peer\n11. Sib\n", [("New Child", 1, 2), ("Tail", 1, 1)]),
            ("> - Root\n>   > Quote\n>   >\n>   > - Parent\n>   >   - Child\n>   >\n>   >   Tail\n>   > - Peer\n> - Sib\n", "> - Root\n>   > Quote\n>   >\n>   > - Child\n>   >\n>   > Tail\n>   > - Peer\n> - Sib\n", [("New Child", 2, 2), ("Tail", 2, 1)]),
            ("- Parent\n  > Child\n  >\n  > - Leaf\n  >\n  > Tail\n- Sib\n", "> Child\n>\n> - Leaf\n> \n> Tail\n\n- Sib\n", [("New Child", 1, 0), ("Leaf", 1, 1), ("Tail", 1, 0)]),
            ("- Root\n  - Parent\n    > Child\n    >\n    > - Leaf\n    >\n    > Tail\n  - Peer\n- Sib\n", "- Root\n  > Child\n  >\n  > - Leaf\n  >\n  > Tail\n  - Peer\n- Sib\n", [("New Child", 1, 1), ("Leaf", 1, 2), ("Tail", 1, 1)]),
            ("- Parent\n  > Child\n  >\n  > > Nested\n  > > - Leaf\n- Sib\n", "> Child\n> \n> > Nested\n> > \n> > - Leaf\n- Sib\n", [("New Child", 1, 0), ("Nested", 2, 0), ("Leaf", 2, 1)]),
            ("- Parent\n  - Child\n    - Grandchild\n\n  Tail\n- Sib\n", "- Child\n  - Grandchild\n\nTail\n\n- Sib\n", nil as [(String, Int, Int)]?),
            ("- Root\n  - Parent\n    - Child\n\n    Tail\n  - Peer\n- Sib\n", "- Root\n  - Child\n\n  Tail\n  - Peer\n- Sib\n", nil),
            ("> - Parent\n>   - Child\n>\n>   Tail\n> - Sib\n", "> - Child\n> \n> Tail\n> \n> - Sib\n", nil),
            ("10. [x] Parent\n    - Child\n\n    Tail\n11. [ ] Sib\n", "- Child\n\nTail\n\n11. [ ] Sib\n", nil),
            ("- Root\n  - Parent\n    1. Child\n    2. Peer\n  - After\n- Sib\n", "- Root\n  1. Child\n  2. Peer\n  - After\n- Sib\n", nil),
            ("- Parent\n  - Child", "- Child", nil),
            ("- Parent\n  - Child\n\n  Tail", "- Child\n\nTail", nil),
            ("- Before\n- Parent\n  - Child\n- Sib\n", "- Before\n- Child\n- Sib\n", nil),
            ("- Parent\n\n  2. Child\n\n  Tail\n- Sib\n", "\n\n2. Child\n\nTail\n\n- Sib\n", nil),
            ("- Parent\n  - Child\n    - Grandchild\n\n    Child tail\n- Sib\n", "- Child\n  - Grandchild\n\n  Child tail\n- Sib\n", nil),
            ("> - Root\n>   - Parent\n>     - Child\n>\n>     Tail\n>   - Peer\n> - Sib\n", "> - Root\n>   - Child\n>\n>   Tail\n>   - Peer\n> - Sib\n", nil)
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            withEditor(source, onPasteError: { issues.append($0) }) { view, coordinator in
                let word = (view.string as NSString).range(of: "Parent")
                guard word.location != NSNotFound else { XCTFail("Missing parent"); return }
                let row = (view.string as NSString).paragraphRange(for: word)
                view.setSelectedRange(row); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertTrue(issues.isEmpty, issues.joined(separator: "; "))
                let caret = view.selectedRange()
                XCTAssertEqual(caret, NSRange(location: expected.hasPrefix(ending) ? 0 : (view.string as NSString).range(of: "Child").location, length: 0))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.selectedRange(), row)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(view.selectedRange(), caret)
                view.insertText(expected.hasPrefix(ending) ? "New" : "New ", replacementRange: view.selectedRange())
                let typed = expected.hasPrefix(ending) ? "New" + expected : expected.replacingOccurrences(of: "Child", with: "New Child", range: expected.range(of: "Child"))
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                if let roles {
                    var nextQuote = 0, actual: [String: [(quotes: [Int], items: Int)]] = [:]
                    func collect(_ node: any Markup, quotes: [Int] = [], items: Int = 0) {
                        var quotes = quotes
                        if node is BlockQuote { quotes.append(nextQuote); nextQuote += 1 }
                        let items = items + (node is ListItem ? 1 : 0)
                        if let paragraph = node as? Paragraph { actual[paragraph.plainText, default: []].append((quotes, items)) }
                        for child in node.children { collect(child, quotes: quotes, items: items) }
                    }
                    collect(Document(parsing: coordinator.lastMarkdown))
                    for (text, quotes, items) in roles {
                        XCTAssertEqual(actual[text]?.count, 1)
                        XCTAssertEqual(actual[text]?.first?.quotes.count, quotes, text)
                        XCTAssertEqual(actual[text]?.first?.items, items, text)
                    }
                    if let tail = actual["Tail"]?.first, let child = actual["New Child"]?.first { XCTAssertEqual(tail.quotes, child.quotes, "The tail stays in the same quote") }
                    if let nested = actual["Nested"]?.first, let leaf = actual["Leaf"]?.first {
                        XCTAssertEqual(nested.quotes, leaf.quotes, "A promoted list must not split its nested quote")
                        XCTAssertEqual(Array(nested.quotes.prefix(1)), actual["New Child"]?.first?.quotes)
                    }
                }
                func structure(_ source: String) -> [String] {
                    var next = 0, result: [String] = []
                    func walk(_ node: any Markup, owner: Int? = nil) {
                        var owner = owner
                        if node is ListItem { result.append("item:\(String(describing: owner))"); owner = next; next += 1 }
                        if let paragraph = node as? Paragraph { result.append("paragraph:\(String(describing: owner)):\(paragraph.plainText)") }
                        for child in node.children { walk(child, owner: owner) }
                    }
                    walk(Document(parsing: source)); return result
                }
                XCTAssertEqual(structure(coordinator.lastMarkdown), structure(typed))
                func itemCount(_ node: any Markup) -> Int { (node is ListItem ? 1 : 0) + node.children.reduce(0) { $0 + itemCount($1) } }
                XCTAssertEqual(itemCount(Document(parsing: coordinator.lastMarkdown)), itemCount(Document(parsing: expected)), "Typing must not turn a surviving item into prose")
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(coordinator.lastMarkdown)), coordinator.lastMarkdown)
            }
        } }
        for (source, expected) in [("- Parent\n", ""), ("- Parent", ""), ("- Parent\n- Sib\n", "- Sib\n")] {
            withEditor(source) { view, coordinator in
                let row = (view.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
                view.setSelectedRange(row); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected.isEmpty ? "New" : "- NewSib\n")
            }
        }
        for (source, word, expected) in [
            ("1. Root\n   1. Parent\n   2. Peer\n", "Parent", "1. Root\n   1. Peer\n"),
            ("1. Parent\n2. Peer\n3. Last\n", "Parent", "1. Peer\n2. Last\n"),
            ("9. Parent\n10. Peer\n    - Child\n\n    Tail\n11. Last\n", "Parent", "9. Peer\n   - Child\n\n   Tail\n10. Last\n"),
            ("3. Parent\n4. Peer\n", "Parent", "3. Peer\n"),
            ("1. Root\n   1. Parent\n      - Child\n\n      Tail\n   2. Peer\n", "Parent", "1. Root\n   - Child\n\n   Tail\n   1. Peer\n"),
            ("- X\n- A\n  - Empty", "X", "- A\n\n  - "),
            ("- A\n- Parent\n", "Parent", "- A\n\n"),
            ("> - A\n> - Parent\n", "Parent", "> - A\n> \n")
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let empty = (view.string as NSString).range(of: "Empty")
                if empty.location != NSNotFound { view.setSelectedRange(empty); view.insertText("", replacementRange: empty) }
                let before = coordinator.lastMarkdown
                let row = (view.string as NSString).paragraphRange(for: (view.string as NSString).range(of: word))
                view.setSelectedRange(row); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                let caret = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(view.selectedRange(), caret)
                if word == "Parent", expected == "- A" + ending + ending || expected == "> - A" + ending + "> " + ending {
                    view.insertText("New", replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, expected + (expected.hasPrefix(">") ? "> New" : "New"))
                }
            }
        } }
        for ending in ["\n", "\r\n"] {
            withEditor(("- A\n  - Empty").replacingOccurrences(of: "\n", with: ending)) { view, coordinator in
                let empty = (view.string as NSString).range(of: "Empty")
                view.setSelectedRange(empty); view.insertText("", replacementRange: empty)
                let before = coordinator.lastMarkdown
                XCTAssertEqual(before, "- A" + ending + ending + "  - ")
                let row = (view.string as NSString).paragraphRange(for: NSRange(location: view.string.utf16.count - 1, length: 0))
                view.setSelectedRange(row); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, "- A" + ending + "- ")
                XCTAssertEqual(view.undoManager?.undoActionName, "Lift list item")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, "- A" + ending + "- ")
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, "- A" + ending + "- New")
            }
        }
    }
    @MainActor func testBackspaceAtListBodyStartLiftsTheItemWithoutLosingOwnedContent() throws {
        for (source, expected, word) in [
            ("- Parent\n  > Quote\n  >\n  > - Item\n  > - Peer\n- Sibling\n", "- Parent\n  > Quote\n  >\n  > Item\n  > \n  > - Peer\n- Sibling\n", "Item"),
            ("10. Parent\n    > Quote\n    >\n    > - Item\n11. Sibling\n", "10. Parent\n    > Quote\n    >\n    > Item\n11. Sibling\n", "Item"),
            ("- > Quote\n  >\n  > - Item\n- Sibling\n", "- > Quote\n  >\n  > Item\n- Sibling\n", "Item"),
            ("> Quote\n>\n> - Item\n> - Peer\n> Sibling\n", "> Quote\n>\n> Item\n> \n> - Peer\n> Sibling\n", "Item"),
            ("- Parent\n  > Quote\n  >\n  > - Item\n  >   - Leaf\n- Sibling\n", "- Parent\n  > Quote\n  >\n  > Item\n  > \n  > - Leaf\n- Sibling\n", "Item"),
            ("- Parent\n  > Quote\n  >\n  > - Before\n  >   - Item\n- Sibling\n", "- Parent\n  > Quote\n  >\n  > - Before\n  > - Item\n- Sibling\n", "Item"),
            ("- Parent\n  > - Item\n- Sibling\n", "- Parent\n  > Item\n- Sibling\n", "Item"),
            ("- Parent\n  > Quote\n  >\n  > - Item\n  >   > Nested\n  >   > - Leaf\n- Sibling\n", "- Parent\n  > Quote\n  >\n  > Item\n  > \n  > > Nested\n  > > \n  > > - Leaf\n- Sibling\n", "Item"),

            ("- Parent\n  - Child\n    - Grandchild\n\n  Tail.\n- Sibling\n", "Parent\n\n- Child\n  - Grandchild\n\nTail.\n\n- Sibling\n", "Parent"),
            ("10. Parent\n    - Child\n\n    Tail.\n11. Sibling\n", "Parent\n\n- Child\n\nTail.\n\n11. Sibling\n", "Parent"),
            ("- Before\n- Parent\n  - Child\n\n  Tail.\n- Sibling\n", "- Before\n\nParent\n\n- Child\n\nTail.\n\n- Sibling\n", "Parent"),
            ("> - Parent\n>   - Child\n>\n>   Tail.\n> - Sibling\n", "> Parent\n> \n> - Child\n> \n> Tail.\n> \n> - Sibling\n", "Parent"),
            (">- Parent\n>   - Child\n>\n>   Tail.\n>- Sibling\n", ">Parent\n>\n> - Child\n>\n>Tail.\n>\n>- Sibling\n", "Parent"),
            ("10. [x] Parent **bold**\n    - Child\n\n    Tail.\n11. [ ] Sibling\n", "Parent **bold**\n\n- Child\n\nTail.\n\n11. [ ] Sibling\n", "Parent"),
            ("10. Parent\n\n    2. Child\n\n    Tail.\n11. Sibling\n", "Parent\n\n2. Child\n\nTail.\n\n11. Sibling\n", "Parent"),
            ("- Parent  \n  More\n\n  Second\n  - Child\n\n  Tail.\n- Sibling\n", "Parent  \nMore\n\nSecond\n\n- Child\n\nTail.\n\n- Sibling\n", "Parent"),
            ("  - Parent\n    - Child\n  - Sibling\n", "Parent\n\n  - Child\n  - Sibling\n", "Parent"),
            (" - Parent\n   - Child\n - Sibling\n", "Parent\n\n - Child\n - Sibling\n", "Parent"),
            ("   - Parent\n     - Child\n   - Sibling\n", "Parent\n\n   - Child\n   - Sibling\n", "Parent"),
            (">   - Parent\n>     - Child\n>   - Sibling\n", "> Parent\n> \n>   - Child\n>   - Sibling\n", "Parent"),
            ("- Root\n  - A\n  - Parent\n  - Child\n- Sibling\n", "- Root\n  - A\n- Parent\n  - Child\n- Sibling\n", "Parent"),
            ("- Root\n  - Parent\n  - Child\n- Sibling\n", "- Root\n- Parent\n  - Child\n- Sibling\n", "Parent"),
            ("1. Root\n   1. A\n   2. Parent\n   3. Child\n2. Sibling\n", "1. Root\n   1. A\n2. Parent\n   1. Child\n2. Sibling\n", "Parent"),
            ("- Parent\n  - Child\n- Sibling\n", "Parent\n\n- Child\n- Sibling\n", "Parent"),
            ("- Before\n\n- Parent\n\n- Sibling\n", "- Before\n\nParent\n\n- Sibling\n", "Parent"),
            ("- Root\n  - A\n  - Parent\n  - Child\n\n  Root tail\n- Sibling\n", "- Root\n  - A\n\n  Root tail\n- Parent\n  - Child\n- Sibling\n", "Parent"),
            ("- Root\n  - Parent\n    - Child\n- Sibling\n", "- Root\n- Parent\n  - Child\n- Sibling\n", "Parent")
        ] { for ending in ["\n", "\r\n"] { for selectMarker in [false, true] {
            let source = source.replacingOccurrences(of: "\n", with: ending)
            let expected = expected.replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            withEditor(source, onPasteError: { issues.append($0) }) { view, coordinator in
                let body = (view.string as NSString).range(of: word)
                let paragraph = (view.string as NSString).paragraphRange(for: NSRange(location: body.location, length: 0))
                let selected = selectMarker ? NSRange(location: paragraph.location, length: body.location - paragraph.location) : NSRange(location: body.location, length: 0)
                view.setSelectedRange(selected); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertTrue(issues.isEmpty, issues.joined(separator: "; "))
                XCTAssertEqual((view.string as NSString).substring(from: view.selectedRange().location).prefix(word.count), Substring(word))
                let liftedCaret = view.selectedRange()
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(view.selectedRange(), liftedCaret)
                view.insertText("New ", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: word, with: "New " + word))
                if word == "Item" {
                    var roles: [String: [(quotes: Int, items: Int)]] = [:]
                    func walk(_ node: any Markup, quotes: Int = 0, items: Int = 0) {
                        let quotes = quotes + (node is BlockQuote ? 1 : 0), items = items + (node is ListItem ? 1 : 0)
                        if let paragraph = node as? Paragraph { roles[paragraph.plainText, default: []].append((quotes, items)) }
                        for child in node.children { walk(child, quotes: quotes, items: items) }
                    }
                    walk(Document(parsing: coordinator.lastMarkdown))
                    XCTAssertEqual(roles["New Item"]?.count, 1)
                    XCTAssertEqual(roles["New Item"]?.first?.quotes, 1, "Removing a list wrapper must keep its text in the quote")
                    let owners = source.hasPrefix(">") ? 0 : source.contains("Before") ? 2 : 1
                    XCTAssertEqual(roles["New Item"]?.first?.items, owners, "Only the intended list wrapper is removed or lifted")
                    if source.contains("Leaf") {
                        XCTAssertEqual(roles["Leaf"]?.count, 1)
                        XCTAssertEqual(roles["Leaf"]?.first?.quotes, source.contains("Nested") ? 2 : 1)
                        XCTAssertEqual(roles["Leaf"]?.first?.items, 2, "Children are promoted inside the surviving outer item")
                    }
                } else {
                    func texts(_ node: any Markup) -> [String] {
                        let own = node is Paragraph ? [(node as! Paragraph).plainText] : []
                        return own + node.children.flatMap(texts)
                    }
                    XCTAssertEqual(texts(Document(parsing: coordinator.lastMarkdown)).filter { $0 == "Child" || $0 == "Grandchild" || $0 == "Tail." || $0 == "Sibling" }.sorted(), source.contains("Grandchild") ? ["Child", "Grandchild", "Sibling", "Tail."] : source.contains("Tail.") ? ["Child", "Sibling", "Tail."] : source.contains("Child") ? ["Child", "Sibling"] : ["Sibling"])
                }
            }
        } } }
        for (source, expected) in [
            ("- \n  - Child\n\n  Tail.\n", "\n\n- Child\n\nTail.\n"),
            ("10. \n    2. Child\n\n    Tail.\n", "\n\n2. Child\n\nTail.\n"),
            ("> - [ ] \n>   - Child\n>\n>   Tail.\n", "> \n> \n> - Child\n> \n> Tail.\n")
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending)
            let expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let first = (view.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
                view.setSelectedRange(NSRange(location: NSMaxRange(first) - 1, length: 0))
                view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                view.insertText("New", replacementRange: view.selectedRange())
                let typed = source.hasPrefix(">") ? "> New" + String(expected.dropFirst(2)) : "New" + expected
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                func itemCount(_ node: any Markup) -> Int { (node is ListItem ? 1 : 0) + node.children.map(itemCount).reduce(0,+) }
                XCTAssertEqual(itemCount(Document(parsing: coordinator.lastMarkdown)), 1, "Typing into the lifted empty head cannot absorb its numbered child")
            }
        } }
        for ending in ["\n", "\r\n"] { for selectMarker in [false, true] {
            let source = "10. Parent\n    1. \n".replacingOccurrences(of: "\n", with: ending)
            let expected = "10. Parent\n11. \n".replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let marker = (view.string as NSString).range(of: "1. ")
                let selected = selectMarker ? marker : NSRange(location: NSMaxRange(marker), length: 0)
                view.setSelectedRange(selected); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                view.insertText("Next", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, "10. Parent" + ending + "11. Next" + ending)
            }
        } }
        for ending in ["\n", "\r\n"] { for selectMarker in [false, true] {
            let source = "- Before\n- \n- Sibling\n".replacingOccurrences(of: "\n", with: ending)
            let expected = "- Before\n\n\n\n- Sibling\n".replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let empty = (view.string as NSString).range(of: "• \n")
                let selected = NSRange(location: empty.location + (selectMarker ? 0 : 2), length: selectMarker ? 2 : 0)
                view.setSelectedRange(selected); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                XCTAssertEqual(view.selectedRange(), selected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, "- Before\n\nNew\n\n- Sibling\n".replacingOccurrences(of: "\n", with: ending))
                let paragraphs = Document(parsing: coordinator.lastMarkdown).children.compactMap { ($0 as? Paragraph)?.plainText }
                XCTAssertEqual(paragraphs, ["New"], "Typing into an empty lifted head must not join the previous item")
            }
        } }
        func shape(_ source: String) -> [String] {
            var result: [String] = [], next = 0
            func text(_ node: any Markup) -> String {
                if let value = node as? Markdown.Text { return value.string }
                return node.children.map(text).joined()
            }
            func walk(_ node: any Markup, owner: Int? = nil) {
                var owner = owner
                if node is ListItem { result.append("item:\(next):\(owner.map(String.init) ?? "root")"); owner = next; next += 1 }
                let id = owner.map(String.init) ?? "root"
                if let h = node as? Heading { result.append("h\(h.level):\(id):\(text(node))") }
                if node is Paragraph { result.append("p:\(id):\(text(node))") }
                if node is BlockQuote { result.append("quote:\(id)") }
                for child in node.children { walk(child, owner: owner) }
            }
            walk(Document(parsing: source)); return result
        }
        let roleRows: [(source: String, word: String, expected: String, destination: String, offset: Int, typed: String, font: String, marker: Bool)] = [
            ("- # Heading\n- Sibling\n", "Heading", "# Heading\n\n- Sibling\n", "Heading", 0, "# NewHeading\n\n- Sibling\n", "# ", true),
            ("- > Quote\n- Sibling\n", "Quote", "> Quote\n\n- Sibling\n", "Quote", 0, "> NewQuote\n\n- Sibling\n", "> ", true),
            ("- # Heading\n\n  Tail\n- Sibling\n", "Heading", "# Heading\n\nTail\n\n- Sibling\n", "Heading", 0, "# NewHeading\n\nTail\n\n- Sibling\n", "# ", true),
            ("- > Quote\n\n  Tail\n- Sibling\n", "Quote", "> Quote\n\nTail\n\n- Sibling\n", "Quote", 0, "> NewQuote\n\nTail\n\n- Sibling\n", "> ", true),
            ("> - ## Heading\n> - Sibling\n", "Heading", "> ## Heading\n> \n> - Sibling\n", "Heading", 0, "> ## NewHeading\n> \n> - Sibling\n", "## ", true),
            ("10. # Heading\n11. Sibling\n", "Heading", "# Heading\n\n11. Sibling\n", "Heading", 0, "# NewHeading\n\n11. Sibling\n", "# ", true),
            ("- ## Heading", "Heading", "## Heading", "Heading", 0, "## NewHeading", "## ", true),
            ("- Root\n  - ## Heading\n  - Peer\n- Sibling\n", "Heading", "- Root\n- ## Heading\n  - Peer\n- Sibling\n", "Heading", 0, "- Root\n- ## NewHeading\n  - Peer\n- Sibling\n", "## ", true),
            ("- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", "- Parent\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Parent", 6, "- ParentNew\n\n  ## Heading\n\n  Tail\n- Sibling\n", "", false),
            ("- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Quote", "- Parent\n\n  > Quote\n\n  Tail\n- Sibling\n", "Parent", 6, "- ParentNew\n\n  > Quote\n\n  Tail\n- Sibling\n", "", false),
            ("- Parent\n\n  > ## Heading\n  > Text\n- Sibling\n", "Heading", "- Parent\n\n  > ## Heading\n  > Text\n- Sibling\n", "Parent", 6, "- ParentNew\n\n  > ## Heading\n  > Text\n- Sibling\n", "", false),
            ("- 😀 Parent\n\n  ## Heading\n- Sibling\n", "Heading", "- 😀 Parent\n\n  ## Heading\n- Sibling\n", "😀 Parent", 9, "- 😀 ParentNew\n\n  ## Heading\n- Sibling\n", "", false),
            ("- Parent\n  - Child\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Heading", "- Parent\n  - Child\n\n  ## Heading\n\n  Tail\n- Sibling\n", "Child", 5, "- Parent\n  - ChildNew\n\n  ## Heading\n\n  Tail\n- Sibling\n", "", false),
            ("- Parent\n\n  ## Before\n  ### Heading\n\n  Tail\n- Sibling\n", "Heading", "- Parent\n\n  ## BeforeHeading\n\n  Tail\n- Sibling\n", "Before", 6, "- Parent\n\n  ## BeforeNewHeading\n\n  Tail\n- Sibling\n", "## ", false),
            ("- ## Before\n  ### Heading\n- Sibling\n", "Heading", "- ## BeforeHeading\n- Sibling\n", "Before", 6, "- ## BeforeNewHeading\n- Sibling\n", "## ", false),
            ("- > Before\n  >\n  > Quote\n- Sibling\n", "Quote", "- > BeforeQuote\n- Sibling\n", "Before", 6, "- > BeforeNewQuote\n- Sibling\n", "> ", false),
            ("- Parent\n\n  > Before\n\n  > Quote\n- Sibling\n", "Quote", "- Parent\n\n  > BeforeQuote\n- Sibling\n", "Before", 6, "- Parent\n\n  > BeforeNewQuote\n- Sibling\n", "> ", false),
            ("- Parent\n\n  > Before\n  > ## Heading\n- Sibling\n", "Heading", "- Parent\n\n  > BeforeHeading\n- Sibling\n", "Before", 6, "- Parent\n\n  > BeforeNewHeading\n- Sibling\n", "> ", false),
            // Keep the explicit live paragraph role across reopen. The web's
            // importer flattens it, but its live Return-created paragraph merges.
            ("- ## Heading\n  Tail\n- Sibling\n", "Tail", "- ## HeadingTail\n- Sibling\n", "Heading", 7, "- ## HeadingNewTail\n- Sibling\n", "## ", false)
        ]
        for row in roleRows { for ending in (row.source.contains("\n") ? ["\n", "\r\n", "\r"] : ["\n"]) { for marker in (row.marker ? [false, true] : [false]) {
            let source = row.source.replacingOccurrences(of: "\n", with: ending), expected = row.expected.replacingOccurrences(of: "\n", with: ending), typed = row.typed.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let raw = view.string as NSString, body = raw.range(of: row.word)
                guard body.location != NSNotFound else { XCTFail("Missing inner Backspace endpoint"); return }
                let paragraph = raw.paragraphRange(for: body)
                let selected = marker ? NSRange(location: paragraph.location, length: body.location - paragraph.location) : NSRange(location: body.location, length: 0)
                view.setSelectedRange(selected); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected, source)
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected)
                XCTAssertEqual(shape(coordinator.lastMarkdown), shape(expected))
                let destination = (view.string as NSString).range(of: row.destination)
                guard destination.location != NSNotFound else { XCTFail("Missing Backspace caret destination"); return }
                let caret = NSRange(location: destination.location + row.offset, length: 0)
                XCTAssertEqual(view.selectedRange(), caret)
                XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, MacMarkdown.font(row.font).pointSize)
                if expected == source {
                    XCTAssertFalse(view.undoManager?.canUndo == true, "Crossing an inner boundary only moves the caret")
                } else {
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), selected)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                }
                view.insertText("New", replacementRange: caret)
                XCTAssertEqual(coordinator.lastMarkdown, typed)
                XCTAssertEqual(shape(coordinator.lastMarkdown), shape(typed))
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(typed)), typed)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
            }
        } } }

        // Empty blocks are created by a real body edit, then use the actual
        // text-view command route (including document start with no prior byte).
        for (source, expectedMarked, role) in [
            ("- # Empty\n- Sibling\n", "# |\n\n- Sibling\n", "# "),
            ("- # Empty", "# |", "# "),
            ("- > Empty", "> |", "> "),
            ("- > Empty\n- Sibling\n", "> |\n\n- Sibling\n", "> "),
            ("- Parent\n\n  ## Empty\n\n  Tail\n- Sibling\n", "- Parent|\n\n  Tail\n- Sibling\n", ""),
            ("- Parent\n\n  > Empty\n\n  Tail\n- Sibling\n", "- Parent|\n\n  Tail\n- Sibling\n", ""),
            ("- Root\n  - ## Empty\n  - Peer\n- Sibling\n", "- Root\n- ## |\n  - Peer\n- Sibling\n", "## "),
            ("- Root\n  - > Empty\n  - Peer\n- Sibling\n", "- Root\n- > |\n  - Peer\n- Sibling\n", "> "),
            ("# Empty\n\nTail\n", "|\u{200b}\n\nTail\n", ""),
            ("# Empty", "|\u{200b}", ""),
            ("> Empty", "|\u{200b}", ""),
            ("> Empty\n\nTail\n", "|\u{200b}\n\nTail\n", ""),
            ("> Empty\n>\n> Tail\n", "> |Tail\n", "> "),
            ("> Before\n>\n> Empty\n>\n> Tail\n", "> Before|\n>\n> Tail\n", "> "),
            ("> Empty\n>\n> ## Tail\n", "> ## |Tail\n", "## "),
            ("> Empty\n>\n> ## \n", "> ## |\n", "## "),
            ("Before\n\n## Empty\n\nTail\n", "Before|\n\nTail\n", ""),
            ("Before\n\n> Empty\n\nTail\n", "Before|\n\nTail\n", ""),
            ("- Parent\n\n  ## Empty", "- Parent|", ""),
            ("- Parent\n\n  > Empty", "- Parent|", "")
        ] { for ending in (source.contains("\n") ? ["\n", "\r\n", "\r"] : ["\n"]) {
            let source = source.replacingOccurrences(of: "\n", with: ending)
            let expected = expectedMarked.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "\n", with: ending)
            let typed = expectedMarked.replacingOccurrences(of: "|", with: "New").replacingOccurrences(of: "\u{200b}", with: "").replacingOccurrences(of: "\n", with: ending)
            try autoreleasepool {
                try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                    let body = (view.string as NSString).range(of: "Empty")
                    guard body.location != NSNotFound else { XCTFail("Missing empty-block setup"); return }
                    view.setSelectedRange(body); view.insertText("", replacementRange: body)
                    let cleared = coordinator.lastMarkdown, selected = view.selectedRange()
                    view.deleteBackward(nil)
                    XCTAssertEqual(coordinator.lastMarkdown, expected, source)
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected)
                    XCTAssertEqual(shape(coordinator.lastMarkdown), shape(expected))
                    let caret = view.selectedRange()
                    XCTAssertEqual(caret.length, 0)
                    guard view.attributedString().length > 0 else { XCTFail("The empty block must retain a native editing row"); return }
                    let location: Int
                    if expectedMarked.contains("Parent|") { location = NSMaxRange((view.string as NSString).range(of: "Parent")) }
                    else if expectedMarked.contains("Before|") { location = NSMaxRange((view.string as NSString).range(of: "Before")) }
                    else {
                        let raw = view.string as NSString
                        let row = expectedMarked.hasPrefix("- Root") ? raw.paragraphRange(for: NSRange(location: NSMaxRange(raw.range(of: "Root")) + 1, length: 0)) : NSRange(location: 0, length: 0)
                        let block = view.attributedString().attribute(.macBlock, at: row.location, effectiveRange: nil) as? String ?? ""
                        location = row.location + MacMarkdown.displayPrefix(block).utf16.count
                    }
                    XCTAssertEqual(caret.location, location)
                    XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, MacMarkdown.font(role).pointSize)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, cleared); XCTAssertEqual(view.selectedRange(), selected)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                    view.insertText("New", replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, typed)
                    XCTAssertEqual(shape(coordinator.lastMarkdown), shape(typed))
                    XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(typed)), typed)
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                }
            }
        } }

        // Document-start Backspace removes the nearest quote wrapper while
        // preserving the paragraphs, lists and cards that wrapper contained.
        for (source, expected, typedOverride) in [
            ("> Quote", "Quote", nil as String?),
            ("> Quote\n\nAfter\n", "Quote\n\nAfter\n", nil),
            ("> Quote\n>\n> Tail\n\nAfter\n", "Quote\n\nTail\n\nAfter\n", nil),
            ("> Quote\n> ## Heading\n\nAfter\n", "Quote\n## Heading\n\nAfter\n", nil),
            ("> Quote\n>\n> Title\n> ===\n\nAfter\n", "Quote\n\nTitle\n===\n\nAfter\n", nil),
            ("> > Quote\n> >\n> > Tail\n>\n> Outer\n\nAfter\n", "> Quote\n>\n> Tail\n>\n> Outer\n\nAfter\n", nil),
            (">>Quote\n>>\n>>Tail\n>\n>Outer\n", ">Quote\n>\n>Tail\n>\n>Outer\n", nil),
            ("  > Quote\n  >\n  > Tail\n\nAfter\n", "Quote\n\nTail\n\nAfter\n", nil),
            (">\tQuote\n>\tTail\n\nAfter\n", "  Quote\n  Tail\n\nAfter\n", "NewQuote\nTail\n\nAfter\n"),
            ("> Quote\nlazy continuation\n\nAfter\n", "Quote\nlazy continuation\n\nAfter\n", nil),
            ("> Quote 😀\n>\n> Tail\n\nAfter\n", "Quote 😀\n\nTail\n\nAfter\n", nil),
            ("> Quote e\u{301}\n\nAfter e\u{301}\n", "Quote e\u{301}\n\nAfter e\u{301}\n", nil),
            ("> **Quote**\n\nAfter\n", "**Quote**\n\nAfter\n", nil),
            ("> [Quote](https://example.com)\n\nAfter\n", "[Quote](https://example.com)\n\nAfter\n", nil),
            ("> Quote\n>\n> ```swift\n> code\n> ```\n\nAfter\n", "Quote\n\n```swift\ncode\n```\n\nAfter\n", nil),
            ("> Quote\n>\n> | A | B |\n> | --- | --- |\n> | v | w |\n\nAfter\n", "Quote\n\n| A | B |\n| --- | --- |\n| v | w |\n\nAfter\n", nil),
            ("> Quote\n>\n>     code\n>\n> Tail\n\nAfter\n", "Quote\n\n    code\n\nTail\n\nAfter\n", nil),
            ("> Quote\n>\n> ---\n>\n> Tail\n\nAfter\n", "Quote\n\n---\n\nTail\n\nAfter\n", nil),
            ("> Quote\n>\n> - Child\n> - Peer\n\nAfter\n", "Quote\n\n- Child\n- Peer\n\nAfter\n", nil),
            ("> Quote\n>\n> 5. Child\n\n10. After\n", "Quote\n\n5) Child\n\n10. After\n", nil),
            ("> Quote\n>\n> - Child\n\n- After\n", "Quote\n\n* Child\n\n- After\n", nil)
        ] { for ending in (source.contains("\n") ? ["\n", "\r\n", "\r"] : ["\n"]) {
            let typed = (typedOverride ?? expected.replacingOccurrences(of: "Quote", with: "NewQuote")).replacingOccurrences(of: "\n", with: ending)
            let source = source.replacingOccurrences(of: "\n", with: ending)
            let expected = expected.replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            try autoreleasepool {
                try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in }, onPasteError: { issues.append($0) })) { view, coordinator, _ in
                    let word = (view.string as NSString).range(of: "Quote")
                    guard word.location != NSNotFound else { XCTFail("Missing quote endpoint"); return }
                    let caret = NSRange(location: word.location, length: 0)
                    view.setSelectedRange(caret); view.deleteBackward(nil)
                    XCTAssertEqual(coordinator.lastMarkdown, expected, source); XCTAssertTrue(issues.isEmpty)
                    XCTAssertEqual(Data(coordinator.lastMarkdown.utf8), Data(expected.utf8), "Source bytes outside the changed wrapper stay exact")
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected)
                    XCTAssertEqual(view.selectedRange(), caret)
                    XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, MacMarkdown.font("").pointSize)
                    XCTAssertEqual(view.undoManager?.undoActionName, "Remove quote")
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), caret)
                    coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                    view.insertText("New", replacementRange: caret)
                    XCTAssertEqual(coordinator.lastMarkdown, typed)
                    XCTAssertEqual(Data(coordinator.lastMarkdown.utf8), Data(typed.utf8))
                    coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                    coordinator.load(expected, source: false)
                    let reopened = (view.string as NSString).range(of: "Quote")
                    guard reopened.location != NSNotFound else { XCTFail("The first paragraph must survive reopening"); return }
                    view.setSelectedRange(NSRange(location: reopened.location, length: 0)); view.insertText("New", replacementRange: view.selectedRange())
                    XCTAssertEqual(coordinator.lastMarkdown, typed)
                    XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
                }
            }
        } }
        // A quote after text merges only its current paragraph into the
        // preceding block. Later quote children keep their own roles.
        for (source, expected, preceding, role, typedOverride) in [
            ("Intro\n\n> Quote\n", "IntroQuote\n", "Intro", "", nil as String?),
            (">\n\nIntro\n\n> Quote\n", ">\n\nIntroQuote\n", "Intro", "", nil),
            ("Intro\n\n> Quote", "IntroQuote", "Intro", "", nil),
            ("## Intro\n\n> Quote\n", "## IntroQuote\n", "Intro", "## ", nil),
            ("Intro\n===\n\n> Quote\n", "# IntroQuote\n", "Intro", "# ", nil),
            ("- Intro\n\n> Quote\n", "- IntroQuote\n", "Intro", "", nil),
            ("9. Intro\n\n> Quote\n", "9. IntroQuote\n", "Intro", "", nil),
            ("- [x] Intro\n\n> Quote\n", "- [x] IntroQuote\n", "Intro", "", nil),
            ("Intro\n\n> Quote\n>\n> Tail\n", "IntroQuote\n\n> Tail\n", "Intro", "", nil),
            ("## Intro\n\n> Quote\n> ## Heading\n", "## IntroQuote\n\n> ## Heading\n", "Intro", "## ", nil),
            ("- Intro\n\n> Quote\n> - Child\n", "- IntroQuote\n\n> - Child\n", "Intro", "", nil),
            ("Intro\n\n> > Quote\n> >\n> > Tail\n", "IntroQuote\n\n> > Tail\n", "Intro", "", nil),
            ("> Intro\n>\n> > Quote\n", "> IntroQuote\n", "Intro", "> ", nil),
            ("> Before\n>\n> Quote\n>\n> Tail\n", "> BeforeQuote\n>\n> Tail\n", "Before", "> ", nil),
            ("Intro\n\n> # Quote\n", "IntroQuote\n", "Intro", "", nil),
            ("> ## Intro\n>\n> Quote\n", "> ## IntroQuote\n", "Intro", "> ## ", nil),
            ("Intro 😀\n\n> **Quote**\n\nAfter\n", "Intro 😀**Quote**\n\nAfter\n", "Intro 😀", "", nil),
            ("Intro\n\n> [Quote](https://example.com)\n", "Intro[Quote](https://example.com)\n", "Intro", "", "IntroNew[Quote](https://example.com)\n"),
            ("- Intro\n  - Child\n\n> Quote\n", "- Intro\n  - ChildQuote\n", "Child", "", nil),
            ("- Intro\n\n  Tail\n\n> Quote\n", "- Intro\n\n  TailQuote\n", "Tail", "", nil),
            ("**Intro**\n\n> Quote\n", "**Intro**Quote\n", "Intro", "", "**Intro**NewQuote\n"),
            ("[Intro](https://example.com)\n\n> Quote\n", "[Intro](https://example.com)Quote\n", "Intro", "", "[Intro](https://example.com)NewQuote\n"),
            ("Intro\n\n> Quote\n>\n> ```swift\n> code\n> ```\n\nAfter\n", "IntroQuote\n\n> ```swift\n> code\n> ```\n\nAfter\n", "Intro", "", nil),
            ("Intro\n\n> Quote\n>\n> | A | B |\n> | --- | --- |\n> | v | w |\n\nAfter\n", "IntroQuote\n\n> | A | B |\n> | --- | --- |\n> | v | w |\n\nAfter\n", "Intro", "", nil)
        ] { for ending in (source.contains("\n") ? ["\n", "\r\n", "\r"] : ["\n"]) {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            let typed = typedOverride.map { $0.replacingOccurrences(of: "\n", with: ending) } ?? expected.replacingOccurrences(of: "Quote", with: "NewQuote")
            var issues: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in }, onPasteError: { issues.append($0) })) { view, coordinator, _ in
                let word = (view.string as NSString).range(of: "Quote"), before = (view.string as NSString).range(of: preceding)
                guard word.location != NSNotFound, before.location != NSNotFound else { XCTFail("Missing merge endpoint"); return }
                let initial = NSRange(location: word.location, length: 0), caret = NSRange(location: NSMaxRange(before), length: 0)
                view.setSelectedRange(initial); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected, source); XCTAssertTrue(issues.isEmpty)
                XCTAssertEqual(Data(MacMarkdown.markdown(view.attributedString()).utf8), Data(expected.utf8))
                XCTAssertEqual(view.selectedRange(), caret)
                XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, MacMarkdown.font(role).pointSize)
                XCTAssertEqual(view.undoManager?.undoActionName, "Merge quote paragraph")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), initial)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                view.insertText("New", replacementRange: caret); XCTAssertEqual(coordinator.lastMarkdown, typed)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
            }
        } }
        for (source, expected) in [
            ("\u{200b}\n\n> Quote\n", "> Quote\n"),
            ("# \n\n> Quote\n", "> Quote\n"),
            ("- \n\n> Quote\n", "- Quote\n"),
            ("1. \n\n> Quote\n", "1. Quote\n"),
            ("Intro\n\n# \n\n> Quote\n", "Intro\n\n> Quote\n")
        ] { for ending in ["\n", "\r\n", "\r"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in }, onPasteError: { issues.append($0) })) { view, coordinator, _ in
                let word = (view.string as NSString).range(of: "Quote")
                guard word.location != NSNotFound else { XCTFail("Missing quote after empty block"); return }
                let initial = NSRange(location: word.location, length: 0)
                view.setSelectedRange(initial); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertTrue(issues.isEmpty)
                let after = (view.string as NSString).range(of: "Quote"), caret = view.selectedRange()
                XCTAssertEqual(caret, NSRange(location: after.location, length: 0))
                XCTAssertEqual(view.undoManager?.undoActionName, "Merge quote paragraph")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertEqual(view.selectedRange(), initial)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                view.insertText("New", replacementRange: caret); XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "Quote", with: "NewQuote"))
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
            }
        } }
        for source in ["> ## Heading\n> Text\n", "## Heading\n\nAfter\n"] {
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                view.setSelectedRange(NSRange(location: 0, length: 0)); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, source); XCTAssertFalse(view.undoManager?.canUndo == true)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, source.replacingOccurrences(of: "Heading", with: "NewHeading"))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
            }
        }

        for prefix in ["", "Intro\n\n"] { for ending in ["\n", "\r\n", "\r"] {
            let source = (prefix + "> Quote\n\n9. Parent\n   - Child\n").replacingOccurrences(of: "\n", with: ending)
            var issues: [String] = []
            try withHostedEditor(MacRichEditor(markdown: source, source: false, editable: true, onChange: { _ in }, onLink: { _ in }, onPasteError: { issues.append($0) })) { view, coordinator, _ in
                let raw = view.string as NSString, child = raw.range(of: "Child")
                let row = raw.paragraphRange(for: child)
                view.setSelectedRange(NSRange(location: row.location, length: 0)); view.insertNewline(nil)
                let before = coordinator.lastMarkdown, visible = view.string
                func outside(_ value: String) -> String {
                    let raw = value as NSString, start = raw.range(of: "Parent").location
                    return start == NSNotFound ? "" : raw.substring(from: start)
                }
                XCTAssertNotEqual(before, source, "The prior native Return edit must remain in history")
                let quote = (view.string as NSString).range(of: "Quote")
                view.setSelectedRange(NSRange(location: quote.location, length: 0)); view.deleteBackward(nil)
                let expected: String
                if prefix.isEmpty { expected = "Quote" + String(before.dropFirst("> Quote".count)) }
                else { expected = before.replacingOccurrences(of: prefix.replacingOccurrences(of: "\n", with: ending) + "> Quote", with: "IntroQuote") }
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertTrue(issues.isEmpty)
                XCTAssertEqual(outside(view.string), outside(visible), "The quote command must preserve the unrelated in-progress native row")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.string, visible)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, before); XCTAssertEqual(view.string, visible)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(outside(view.string), outside(visible))
            }
        } }
        for editable in [false, true] {
            let source = "> Quote\n"
            try withHostedEditor(MacRichEditor(markdown: source, source: editable, editable: editable, onChange: { _ in }, onLink: { _ in })) { view, coordinator, _ in
                view.setSelectedRange(NSRange(location: editable ? 2 : 0, length: 0)); view.deleteBackward(nil)
                XCTAssertEqual(coordinator.lastMarkdown, editable ? ">Quote\n" : source, "Source and read-only input retain their existing command behavior")
            }
        }
    }
    @MainActor func testNativeListReturnContinuesAndEmptyReturnEndsTheList() {
        for prefix in ["> ", "> > "] {
            let source = prefix + "First line\n" + prefix + "Second line\n"
            withEditor(source) { view, coordinator in
                view.setSelectedRange(NSRange(location: view.string.utf16.count - 1, length: 0))
                view.insertNewline(nil)
                XCTAssertEqual(coordinator.lastMarkdown, source + prefix + "\n")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, source + prefix + "\n")
                view.insertNewline(nil)
                let outer = MacBlockPrefix(prefix)?.leavingEmpty ?? ""
                XCTAssertEqual(coordinator.lastMarkdown, source + outer + "\n")
            }
        }
        for (source, expected) in [("- first", "- first\n- second\n"), ("3. first", "3. first\n4. second\n"), ("- [x] first", "- [x] first\n- [ ] second\n"), ("9. [x] first", "9. [x] first\n10. [ ] second\n")] {
            withEditor(source) { view, _ in
                view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
                view.insertNewline(nil); view.insertText("second", replacementRange: view.selectedRange())
                view.insertNewline(nil); view.insertNewline(nil)
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected + "\n", "Exiting materializes the independent paragraph boundary before typing")
                view.insertText("Plain paragraph", replacementRange: view.selectedRange())
                let saved = MacMarkdown.markdown(view.attributedString())
                XCTAssertEqual(saved, expected + "\nPlain paragraph")
                let document = Document(parsing: saved)
                XCTAssertTrue(document.child(at: document.childCount - 1) is Paragraph, "A paragraph after the list must be a separate CommonMark block")
            }
        }
        for (prefix, next) in [(">9. [x] ", ">10. [ ] "), ("> 1) [ ] ", "> 2) [ ] ")] { for ending in ["\n", "\r\n"] {
            let source = prefix + "first" + ending
            let expected = source + next + "second" + ending
            withEditor(source) { view, coordinator in
                view.setSelectedRange(NSRange(location: view.string.utf16.count - 1, length: 0))
                view.insertNewline(nil); view.insertText("second", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertTrue(view.string.contains(next.contains("10.") ? "10. ☐ second" : "2) ☐ second"))
                coordinator.action("undo"); coordinator.action("redo")
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
            }
        } }
    }
    @MainActor func testNativeTypedShortcutsAndBlockUndo() {
        for (typed, expected) in [("- [ ] plan", "- [ ] plan"), ("1. plan", "1. plan"), ("## Heading", "## Heading")] {
            withEditor("") { view, _ in
                for character in typed { view.insertText(String(character), replacementRange: view.selectedRange()) }
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected)
                if typed.hasPrefix("- ") { XCTAssertEqual(view.string, "☐ plan") }
                if typed.hasPrefix("##") { XCTAssertEqual(view.string, "Heading") }
            }
        }
        // Parsed inner quotes may inherit wide list indentation, but raw
        // typing must not interpret an indented code-looking prefix as a quote.
        for (typed, visible) in [("    > ", "    > "), (">     > ", "     > ")] {
            withEditor("") { view, _ in
                for character in typed { view.insertText(String(character), replacementRange: view.selectedRange()) }
                XCTAssertEqual(view.string, visible)
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(view.string, visible + "New")
            }
        }
        for ending in ["\n", "\r\n"] { for typed in ["- ", "1. [ ] ", "> - [ ] ", ">1) [x] "] {
            let other = ending == "\n" ? "\r\n" : "\n"
            let source = other + ending + ending + "After." + other
            withEditor(source) { view, coordinator in
                view.setSelectedRange(NSRange(location: 1, length: 0))
                // AppKit can carry typing attributes from the preceding paragraph.
                // The existing paragraph terminator still owns its actual ending.
                var attributes = view.typingAttributes; attributes[.macLineEnding] = other; view.typingAttributes = attributes
                for character in typed { view.insertText(String(character), replacementRange: view.selectedRange()) }
                view.insertText("New", replacementRange: view.selectedRange())
                let expected = other + typed + "New" + ending + ending + "After." + other
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo")
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
            }
        } }
        for (head, child, gap, tail) in [
            ("- ", "  - ", "\n", "  "),
            ("10. ", "    - ", "\n", "    "),
            ("> - ", ">   - ", ">\n", ">   "),
            (">- ", ">   - ", ">\n", ">   ")
        ] { for ending in ["\n", "\r\n"] { for checked in [false, true] {
            let source = (head + "Parent\n" + child + "Child\n" + gap + tail + "Tail.\n" + head + "Sibling\n").replacingOccurrences(of: "\n", with: ending)
            let marker = head + (checked ? "[x] " : "[ ] ")
            let expected = (marker + "New\n" + child + "Child\n" + gap + tail + "Tail.\n" + head + "Sibling\n").replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let parent = (view.string as NSString).range(of: "Parent")
                view.setSelectedRange(parent); view.insertText("", replacementRange: parent)
                for character in checked ? "[x] " : "[ ] " { view.insertText(String(character), replacementRange: view.selectedRange()) }
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                if head == "10. " {
                    let visible = checked ? "10. ☑ New" : "10. ☐ New"
                    XCTAssertTrue(view.string.hasPrefix(visible))
                    XCTAssertTrue(MacMarkdown.render(expected).string.hasPrefix(visible), "Reopening must keep both the number and checkbox")
                }
                var paragraphs: [Int] = []
                func walk(_ node: any Markup) {
                    if node is ListItem { paragraphs.append(node.children.filter { $0 is Paragraph }.count) }
                    for child in node.children { walk(child) }
                }
                walk(Document(parsing: coordinator.lastMarkdown))
                XCTAssertEqual(paragraphs, [2, 1, 1], coordinator.lastMarkdown)
                let continuation = (view.string as NSString).range(of: "Tail.")
                view.setSelectedRange(NSRange(location: continuation.location + 2, length: 0))
                coordinator.action("toggleChecklist")
                let toggled = expected.replacingOccurrences(of: marker + "New", with: head + (checked ? "[ ] New" : "[x] New"))
                XCTAssertEqual(coordinator.lastMarkdown, toggled)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, toggled)
                view.insertText("X", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, toggled.replacingOccurrences(of: "Tail.", with: "TaXil."))
            }
        } } }
        // Checkbox-looking text belongs to the inner block, not the outer
        // list marker. Use real typing and formatting producers; no context is
        // installed by the test. Existing flat-list cases above still transform.
        for (source, action, expectedPrefix, expectedSuffix, role) in [
            ("- # Inner\n- Sibling\n", "", "- # ", "\n- Sibling\n", "# "),
            ("- > Inner\n- Sibling\n", "", "- > ", "\n- Sibling\n", "> "),
            ("- Root\n  - ## Inner\n  - Peer\n", "", "- Root\n  - ## ", "\n  - Peer\n", "## "),
            ("> 10. ### Inner\n> 11. Sibling\n", "", "> 10. ### ", "\n> 11. Sibling\n", "> ### "),
            ("- Parent\n\n  ## Inner\n\n  Tail\n- Sibling\n", "", "- Parent\n\n  ## ", "\n\n  Tail\n- Sibling\n", "## "),
            ("- Parent\n\n  > Inner\n\n  Tail\n- Sibling\n", "", "- Parent\n\n  > ", "\n\n  Tail\n- Sibling\n", "> "),
            ("- # Inner\n- Sibling\n", "quote", "- > ", "\n- Sibling\n", "> "),
            ("- # Inner\n- Sibling\n", "paragraph", "- ", "\n- Sibling\n", ""),
            ("- # Inner", "", "- # ", "", "# ")
        ] { for ending in (source.contains("\n") ? ["\n", "\r\n", "\r"] : ["\n"]) { for (box, escaped) in [("[ ] ", "\\[ \\] "), ("[x] ", "\\[x\\] "), ("[X] ", "\\[X\\] "), ("- ", "\\- "), ("## ", "\\## "), ("> ", "\\> "), ("--- ", "--- ")] {
            let source = source.replacingOccurrences(of: "\n", with: ending)
            // Brackets are ordinary literal Markdown text in the saved block.
            let expected = (expectedPrefix + escaped + "New" + expectedSuffix).replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                view.setSelectedRange((view.string as NSString).range(of: "Inner"))
                if !action.isEmpty { coordinator.action(action) }
                let word = (view.string as NSString).range(of: "Inner")
                guard word.location != NSNotFound else { XCTFail("Missing inner shortcut endpoint"); return }
                view.setSelectedRange(word); view.insertText("", replacementRange: word)
                for character in box { view.insertText(String(character), replacementRange: view.selectedRange()) }
                view.insertText("New", replacementRange: view.selectedRange())
                XCTAssertEqual(coordinator.lastMarkdown, expected, source)
                XCTAssertTrue(view.string.contains(box + "New"), "A block shortcut must not consume the inner block's literal text")
                func shape(_ source: String) -> [String] {
                    var result: [String] = []
                    func walk(_ node: any Markup) {
                        if let item = node as? ListItem { result.append(item.checkbox == nil ? "item" : "task") }
                        if let heading = node as? Heading { result.append("h\(heading.level)") }
                        if node is BlockQuote { result.append("quote") }
                        for child in node.children { walk(child) }
                    }
                    walk(Document(parsing: source)); return result
                }
                XCTAssertEqual(shape(coordinator.lastMarkdown), shape(expected))
                XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, MacMarkdown.font(role).pointSize)
                let caret = view.selectedRange()
                coordinator.action("undo"); coordinator.action("redo")
                XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), caret)
                view.insertText("!", replacementRange: caret)
                XCTAssertEqual(coordinator.lastMarkdown, expected.replacingOccurrences(of: "New", with: "New!"))
                XCTAssertEqual(MacMarkdown.markdown(MacMarkdown.render(expected)), expected)
            }
        } } }
        withEditor("A paragraph") { view, coordinator in
            view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
            coordinator.action("checklist")
            XCTAssertNotNil(view.undoManager)
            XCTAssertTrue(view.undoManager?.canUndo == true)
            view.undoManager?.undo()
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), "A paragraph")
            view.undoManager?.redo()
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), "- [ ] A paragraph")
        }
    }
    @MainActor func testUnderlineFormattingPreservesRichRolesLinksTypingAndUndo() {
        for (source, expected) in [
            ("A Café.", "A <u>Café</u>."),
            ("A **Café**.", "A <u>**Café**</u>."),
            ("A [Café](https://example.com).", "A [<u>Café</u>](https://example.com)."),
            ("- Café\n- Other\n", "- <u>Café</u>\n- Other\n"),
            ("> Café\n", "> <u>Café</u>\n"),
            ("# Café\n", "# <u>Café</u>\n"),
            ("| Name |\n| --- |\n| Café |\n", "| Name |\n| --- |\n| <u>Café</u> |\n")
        ] { for ending in ["\n", "\r\n"] {
            let source = source.replacingOccurrences(of: "\n", with: ending), expected = expected.replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let word = (view.string as NSString).range(of: "Café")
                guard word.location != NSNotFound else { XCTFail("Missing underline target"); return }
                let original = view.attributedString().attributes(at: word.location, effectiveRange: nil)
                view.setSelectedRange(word); coordinator.action("underline")
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                XCTAssertEqual(view.attributedString().attribute(.underlineStyle, at: word.location, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
                XCTAssertEqual(view.attributedString().attribute(.link, at: word.location, effectiveRange: nil) as? String, original[.link] as? String)
                XCTAssertFalse(MacMarkdown.requiresSource(expected), "Balanced formatting emitted by the editor must reopen rich")
                let reopened = MacMarkdown.render(expected), target = (reopened.string as NSString).range(of: "Café")
                guard target.location != NSNotFound else { XCTFail("Missing reopened underlined text"); return }
                XCTAssertEqual(reopened.attribute(.underlineStyle, at: target.location, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
                XCTAssertFalse(reopened.string.contains("<u>"))
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, source)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected); XCTAssertEqual(view.selectedRange(), word)
                coordinator.action("underline"); XCTAssertEqual(coordinator.lastMarkdown, source)
            }
        } }
        withEditor("") { view, coordinator in
            view.insertText("A ", replacementRange: view.selectedRange()); coordinator.action("underline")
            view.insertText("Café", replacementRange: view.selectedRange())
            XCTAssertEqual(coordinator.lastMarkdown, "A <u>Café</u>")
            coordinator.action("underline"); view.insertText(" plain", replacementRange: view.selectedRange())
            XCTAssertEqual(coordinator.lastMarkdown, "A <u>Café</u> plain")
        }
        withEditor("A B") { view, coordinator in
            for word in ["A", "B"] { view.setSelectedRange((view.string as NSString).range(of: word)); coordinator.action("underline") }
            let expected = "<u>A</u> <u>B</u>"
            XCTAssertEqual(coordinator.lastMarkdown, expected)
            let reopened = MacMarkdown.render(coordinator.lastMarkdown)
            XCTAssertEqual(reopened.string, "A B")
            XCTAssertEqual(reopened.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int ?? 0, 0, "An unselected gap must not gain underline on reopen")
            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "<u>A</u> B")
            coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
        }
        withEditor("Word", sourceMode: true) { view, coordinator in
            view.setSelectedRange(NSRange(location: 0, length: 4)); coordinator.action("underline")
            XCTAssertEqual(coordinator.lastMarkdown, "<u>Word</u>")
        }
        for (open, close, bold, italic) in [("<u>", "</u>", false, false), ("<u><strong>", "</strong></u>", true, false), ("<u><em>", "</em></u>", false, true)] {
            let source = "A " + open + "Word" + close + "."
            XCTAssertFalse(MacMarkdown.requiresSource(source))
            let rich = MacMarkdown.render(source), word = (rich.string as NSString).range(of: "Word")
            guard word.location != NSNotFound else { XCTFail("Missing imported format target"); continue }
            XCTAssertEqual(rich.attribute(.underlineStyle, at: word.location, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
            let traits = NSFontManager.shared.traits(of: rich.attribute(.font, at: word.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15))
            XCTAssertEqual(traits.contains(.boldFontMask), bold); XCTAssertEqual(traits.contains(.italicFontMask), italic)
            XCTAssertEqual(MacMarkdown.markdown(rich), source, "Untouched imported tag spelling stays exact")
        }
        for source in ["A <u title=\"x\">Word</u>.", "A <u>Word.", "A <u><em>Word</u></em>."] {
            XCTAssertFalse(MacMarkdown.requiresSource(source), "Rich text is the default; Source is only an explicit choice")
        }
    }
    @MainActor func testNativeInlineMarkdownShortcutsPreserveUnicodeAndFollowingPlainText() {
        for (typed, display, expected) in [
            ("Café **bold**", "Café bold", "Café **bold**"),
            ("日本語 ***both***", "日本語 both", "日本語 ***both***"),
            ("A _word_", "A word", "A *word*"),
            ("A `code`", "A code", "A `code`"),
            ("See [site](https://example.com)", "See site", "See [site](https://example.com)"),
        ] {
            withEditor("") { view, _ in
                for character in typed { view.insertText(String(character), replacementRange: view.selectedRange()) }
                XCTAssertEqual(view.string, display)
                view.insertText(" after", replacementRange: view.selectedRange())
                XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), expected + " after")
            }
        }
    }
    @MainActor func testInlineShortcutAtTheStartOfAnInterleavedContinuationKeepsItsParent() {
        for ending in ["\n", "\r\n"] {
            let source = "- Parent\n  - Child\n\n  Tail paragraph.\n- Sib\n".replacingOccurrences(of: "\n", with: ending)
            withEditor(source) { view, coordinator in
                let tail = (view.string as NSString).range(of: "Tail")
                view.setSelectedRange(NSRange(location: tail.location, length: 0))
                for character in "**Note** " { view.insertText(String(character), replacementRange: view.selectedRange()) }
                XCTAssertTrue(view.string.contains("Note Tail paragraph."))
                XCTAssertFalse(view.string.contains("**"), "The actual inline shortcut must have run")
                XCTAssertEqual(coordinator.lastMarkdown, "- Parent\n  - Child\n\n  **Note** Tail paragraph.\n- Sib\n".replacingOccurrences(of: "\n", with: ending))
                let list = Document(parsing: coordinator.lastMarkdown).child(at: 0) as? UnorderedList
                XCTAssertEqual(list?.child(at: 0)?.children.filter { $0 is Paragraph }.count, 2)
            }
        }
    }
    @MainActor func testLoadingAnotherDocumentDiscardsThePreviousUndoHistory() {
        withEditor("First document") { view, coordinator in
            view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
            coordinator.action("checklist")
            coordinator.load("Second document", source: false)
            XCTAssertFalse(view.undoManager?.canUndo == true)
            view.undoManager?.undo()
            XCTAssertEqual(view.string, "Second document")
        }
    }
    @MainActor func testSourceParagraphCommandsUseTheRequestedHeadingAndKeepFrontmatter() {
        let source = "---\nforeign: retained\n---\n# Title\n\nA paragraph.\n"
        withEditor(source, sourceMode: true) { view, coordinator in
            view.setSelectedRange((view.string as NSString).range(of: "A paragraph."))
            coordinator.action("h2")
            XCTAssertEqual(view.string, source.replacingOccurrences(of: "A paragraph.", with: "## A paragraph."))
            view.setSelectedRange((view.string as NSString).range(of: "A paragraph."))
            coordinator.action("paragraph")
            XCTAssertEqual(view.string, source)
        }
    }
    @MainActor func testLinkDialogCreatesAndEditsWebLinksWithoutChangingInlineFormatting() throws {
        let defaults = UserDefaults.standard, key = "zerus.mac.editor.linkOption", previous = UserDefaults.standard.object(forKey: "zerus.mac.editor.linkOption")
        defer { if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) } }
        defaults.set("web", forKey: key)
        let source = "😀 Before Café **plan** after.\n"
        var model = source
        try withHostedEditor(MacRichEditor(markdown: model, source: false, editable: true, onChange: { model = $0 }, onLink: { _ in }, readDocument: { (model, false) })) { view, coordinator, _ in
            let selection = (view.string as NSString).range(of: "Café plan")
            for (address, expected) in [("example.test", "😀 Before [Café **plan**](https://example.test/) after.\n"), ("https://example.test/new", "😀 Before [Café **plan**](https://example.test/new) after.\n")] {
                if address.hasPrefix("https:") { defaults.set("note", forKey: key) } // An existing web link overrides the last-used note choice.
                view.window?.makeFirstResponder(view); view.setSelectedRange(selection)
                let before = coordinator.lastMarkdown
                coordinator.action("link")
                guard let panel = view.window?.attachedSheet else { XCTFail("The shared link action must present an editable native link dialog"); return }
                XCTAssertEqual(panel.title, "Edit link"); XCTAssertEqual(coordinator.lastMarkdown, before)
                func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
                func settle() { for _ in 0..<8 { panel.contentView?.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) } }
                settle()
                let field = try XCTUnwrap(panel.contentView.flatMap { nodes($0).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Web URL" } })
                XCTAssertTrue(panel.makeFirstResponder(field))
                let fieldEditor = try XCTUnwrap(panel.fieldEditor(true, for: field) as? NSTextView)
                fieldEditor.insertText(address, replacementRange: NSRange(location: 0, length: fieldEditor.string.utf16.count))
                panel.makeFirstResponder(nil); settle(); panel.makeKey()
                let save = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
                panel.sendEvent(save); settle()
                XCTAssertNil(view.window?.attachedSheet)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, before)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
            }
            view.window?.makeFirstResponder(view)
            let range = (view.string as NSString).range(of: "Café plan")
            let screen = view.firstRect(forCharacterRange: range, actualRange: nil)
            let local = try XCTUnwrap(view.window).convertFromScreen(screen)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: local.minX + 2, y: local.midY), modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let menu = try XCTUnwrap(view.menu(for: event))
            for title in ["Edit link…", "Remove link", "Copy link"] {
                XCTAssertEqual(menu.items.filter { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }.count, 1, "One shared action for " + title)
            }
        }
    }
    @MainActor func testLinkEditsKeepSourceSpellingNoteIdentityOwnershipAndStaleDraftsSafe() throws {
        let note = NoteDocument(path: "Work/Café.md", content: "---\nzerus-id: cafe-id\n---\n# Café\n", modified: Date())
        let examples = [
            ("😀 Before Café **plan** after.\n", "Café plan", "Café **plan**", "😀 Before [Café **plan**](https://example.test/a\\)) after.\n"),
            ("- Café **plan**\n  - Child\n", "Café plan", "Café **plan**", "- [Café **plan**](https://example.test/a\\))\n  - Child\n"),
            ("> Café **plan**\n", "Café plan", "Café **plan**", "> [Café **plan**](https://example.test/a\\))\n"),
            ("| Name |\n| --- |\n| Café **plan** |\n", "Café plan", "Café **plan**", "| Name |\n| --- |\n| [Café **plan**](https://example.test/a\\)) |\n")
        ]
        for (template, visible, literal, expectedTemplate) in examples { for sourceMode in [false, true] { for ending in ["\n", "\r\n"] {
            let original = template.replacingOccurrences(of: "\n", with: ending), expected = expectedTemplate.replacingOccurrences(of: "\n", with: ending)
            try withEditor(original, sourceMode: sourceMode, notes: [note]) { view, coordinator in
                view.setSelectedRange((view.string as NSString).range(of: sourceMode ? literal : visible))
                let request = try coordinator.prepareLinkEdit()
                XCTAssertFalse(request.canEditLabel, "Mixed formatting stays intact")
                XCTAssertThrowsError(try coordinator.applyLink(request, destination: "javascript:alert(1)", label: request.label.string))
                XCTAssertEqual(coordinator.lastMarkdown, original)
                try coordinator.applyLink(request, destination: "example.test/a)", label: request.label.string)
                XCTAssertEqual(coordinator.lastMarkdown, expected)
                var links: [Markdown.Link] = []
                func collect(_ node: any Markup) { if let link = node as? Markdown.Link { links.append(link) }; for child in node.children { collect(child) } }
                collect(Document(parsing: expected)); XCTAssertEqual(links.count, 1); XCTAssertEqual(links.first?.destination, "https://example.test/a)")
                XCTAssertEqual(links.first?.plainText, visible)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                let currentRange = (view.string as NSString).range(of: sourceMode ? literal : visible)
                view.setSelectedRange(NSRange(location: currentRange.location + 1, length: 0))
                let existing = try coordinator.prepareLinkEdit()
                try coordinator.applyLink(existing, destination: nil, label: existing.label.string)
                XCTAssertEqual(coordinator.lastMarkdown, original)
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, expected)
                coordinator.action("redo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                view.setSelectedRange((view.string as NSString).range(of: sourceMode ? literal : visible))
                let target = try coordinator.prepareLinkEdit()
                try coordinator.applyLink(target, destination: NoteReference(target: "zerus:cafe-id", label: "Café", explicitLabel: true).url.absoluteString, label: target.label.string)
                let refs = NoteReference.references(in: coordinator.lastMarkdown)
                XCTAssertEqual(refs.map(\.target), ["zerus:cafe-id"]); XCTAssertEqual(refs.map(\.label), [visible])
                let saved = coordinator.lastMarkdown
                XCTAssertThrowsError(try coordinator.applyLink(target, destination: "example.test/stale", label: "wrong")) { XCTAssertTrue($0.localizedDescription.contains("changed")) }
                XCTAssertEqual(coordinator.lastMarkdown, saved)
            }
        } } }
        for sourceMode in [false, true] {
            let original = "😀 [Café **plan**](https://old.test/ \"Kept title\") after.\r\n"
            try withEditor(original, sourceMode: sourceMode) { view, coordinator in
                let range = (view.string as NSString).range(of: "Café")
                view.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                let request = try coordinator.prepareLinkEdit(); XCTAssertEqual(request.title, "Kept title")
                try coordinator.applyLink(request, destination: "new.test", label: request.label.string)
                XCTAssertEqual(coordinator.lastMarkdown, "😀 [Café **plan**](https://new.test/ \"Kept title\") after.\r\n")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, original)
                coordinator.load(original, source: sourceMode)
                XCTAssertThrowsError(try coordinator.applyLink(request, destination: "new.test", label: request.label.string))
            }
        }
        for sourceMode in [false, true] {
            try withEditor("Before target after.\n", sourceMode: sourceMode, notes: [note]) { view, coordinator in
                view.setSelectedRange((view.string as NSString).range(of: "target"))
                let request = try coordinator.prepareLinkEdit(); XCTAssertTrue(request.canEditLabel)
                try coordinator.applyLink(request, destination: NoteReference(target: "zerus:cafe-id", label: "Café", explicitLabel: true).url.absoluteString, label: "Alias")
                XCTAssertEqual(coordinator.lastMarkdown, "Before [[zerus:cafe-id|Alias]] after.\n")
                view.setSelectedRange((view.string as NSString).range(of: "Alias"))
                let alias = try coordinator.prepareLinkEdit()
                try coordinator.applyLink(alias, destination: "example.test", label: "Renamed")
                XCTAssertEqual(coordinator.lastMarkdown, "Before [Renamed](https://example.test/) after.\n")
                view.setSelectedRange((view.string as NSString).range(of: "Renamed"))
                let renamed = try coordinator.prepareLinkEdit()
                try coordinator.applyLink(renamed, destination: nil, label: renamed.label.string)
                XCTAssertEqual(coordinator.lastMarkdown, "Before Renamed after.\n")
            }
            try withEditor("Before  after.\n", sourceMode: sourceMode) { view, coordinator in
                view.setSelectedRange(NSRange(location: 7, length: 0))
                let request = try coordinator.prepareLinkEdit()
                try coordinator.applyLink(request, destination: "example.test", label: "Visit")
                XCTAssertEqual(coordinator.lastMarkdown, "Before [Visit](https://example.test/) after.\n")
                coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, "Before  after.\n")
            }
            try withEditor("```swift\nliteral\n```\n", sourceMode: sourceMode) { view, coordinator in
                view.setSelectedRange((view.string as NSString).range(of: "literal"))
                XCTAssertThrowsError(try coordinator.prepareLinkEdit()) { XCTAssertTrue($0.localizedDescription.contains(sourceMode ? "Code" : "prose")) }
            }
        }
        try withEditor("- First\n- Second\n") { view, coordinator in
            let raw = view.string as NSString, first = raw.range(of: "First"), second = raw.range(of: "Second")
            view.setSelectedRange(NSRange(location: first.location, length: NSMaxRange(second) - first.location))
            let request = try coordinator.prepareLinkEdit(); XCTAssertFalse(request.canEditLabel)
            try coordinator.applyLink(request, destination: "example.test", label: request.label.string)
            XCTAssertEqual(coordinator.lastMarkdown, "- [First](https://example.test/)\n- [Second](https://example.test/)\n")
            let list = Document(parsing: coordinator.lastMarkdown).children.compactMap { $0 as? UnorderedList }.first
            XCTAssertEqual(list?.childCount, 2)
        }
    }

    @MainActor func testNotePickerReplacesUnicodeSelectionAtCaretAndSupportsUndoRedo() {
        let note = NoteDocument(path: "Work/chosen.md", content: "---\nzerus-id: chosen-note\n---\n# chosen\n", modified: Date())
        let original = "😀 Before chosen after.\n\nKeep _this spelling_.\n"
        withEditor(original, notes: [note]) { view, coordinator in
            view.setSelectedRange((view.string as NSString).range(of: "chosen"))
            coordinator.showNoteLinks(automatic: false)
            XCTAssertTrue(coordinator.linkCompletion.key(36))
            let inserted = MacMarkdown.markdown(view.attributedString())
            XCTAssertEqual(view.string, "😀 Before chosen after.\n\nKeep this spelling.\n")
            XCTAssertTrue(inserted.hasPrefix("😀 Before ")); XCTAssertTrue(inserted.hasSuffix(" after.\n\nKeep _this spelling_.\n"))
            XCTAssertEqual(NoteReference.references(in: inserted).map(\.target), ["zerus:chosen-note"])
            XCTAssertTrue(inserted.contains("[[zerus:chosen-note|chosen]]"), "Plain note links must remain discoverable by other clients’ backlink scans")
            view.undoManager?.undo(); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), original)
            view.undoManager?.redo(); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), inserted)
            view.setSelectedRange(NSRange(location: 0, length: 0)); coordinator.showNoteLinks(automatic: false)
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            _ = coordinator.linkCompletion.key(36)
            XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), inserted, "A moved caret must not receive a stale picker insertion")
        }
    }
    @MainActor func testTypedNoteCompletionUsesTriggersWithoutInterceptingEmailOrCode() {
        let note = NoteDocument(path: "Work/Café.md", content: "---\nzerus-id: cafe-note\n---\n# Café\n", modified: Date())
        for trigger in ["@Cafe", "[[Cafe"] {
            withEditor("😀 Prefix " + trigger, notes: [note]) { view, coordinator in
                view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
                coordinator.showNoteLinks(automatic: true)
                XCTAssertTrue(coordinator.linkCompletion.key(36))
                XCTAssertEqual(view.string, "😀 Prefix Café ")
                let links = NoteReference.references(in: MacMarkdown.markdown(view.attributedString()))
                XCTAssertEqual(links.map(\.target), ["zerus:cafe-note"]); XCTAssertEqual(links.map(\.label), ["Café"])
            }
        }
        for source in ["me@example.com", "`@Cafe`", "Already [[zerus:cafe-note|@Cafe]]"] {
            withEditor(source, notes: [note]) { view, coordinator in
                view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0)); coordinator.showNoteLinks(automatic: true)
                XCTAssertFalse(coordinator.linkCompletion.shown); XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), source)
            }
        }
    }
    @MainActor func testDisablingAutomaticNoteLinksLeavesManualPickerAvailableAndReenablesLive() {
        let defaults = UserDefaults.standard, key = "zerus.mac.noteLinkShortcuts", previous = defaults.object(forKey: key)
        defer { if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) } }
        let note = NoteDocument(path: "Work/Café.md", content: "---\nzerus-id: cafe-note\n---\n# Café\n", modified: Date())
        defaults.set(false, forKey: key)
        withEditor("😀 Prefix @Cafe", notes: [note]) { view, coordinator in
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            coordinator.showNoteLinks(automatic: true)
            XCTAssertFalse(coordinator.linkCompletion.shown); XCTAssertEqual(view.string, "😀 Prefix @Cafe")
            coordinator.showNoteLinks(automatic: false)
            XCTAssertTrue(coordinator.linkCompletion.key(36))
            XCTAssertEqual(NoteReference.references(in: MacMarkdown.markdown(view.attributedString())).map(\.target), ["zerus:cafe-note"])
            coordinator.action("undo")
            defaults.set(true, forKey: key)
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            coordinator.showNoteLinks(automatic: true)
            XCTAssertTrue(coordinator.linkCompletion.shown)
        }
    }
    @MainActor func testCodeFenceReturnRespectsCreationPreferenceAndUndoRestoresRichText() {
        let defaults = UserDefaults.standard, key = "zerus.mac.codeBlocks", previous = defaults.object(forKey: key)
        defer { if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) } }
        for enabled in [false, true] {
            defaults.set(enabled, forKey: key)
            withEditor("# Café\n\n") { view, coordinator in
                view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
                for character in "```swift" { view.insertText(String(character), replacementRange: view.selectedRange()) }
                let before = MacMarkdown.markdown(view.attributedString())
                view.insertText("\n", replacementRange: view.selectedRange())
                XCTAssertFalse(coordinator.source)
                if enabled {
                    XCTAssertEqual(FencedCode.blocks(in: MacMarkdown.markdown(view.attributedString())).map(\.code.info), ["swift"])
                    XCTAssertNotNil(MacRichCode.at(view.attributedString(), view.selectedRange().location))
                    coordinator.action("undo"); XCTAssertFalse(coordinator.source)
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), before)
                    coordinator.action("redo"); XCTAssertFalse(coordinator.source)
                    view.insertText("let marker = \"**literal**\"", replacementRange: view.selectedRange())
                    XCTAssertEqual(FencedCode.blocks(in: MacMarkdown.markdown(view.attributedString())).first?.code.body, "let marker = \"**literal**\"")
                    coordinator.action("exitCode")
                    view.insertText("After code", replacementRange: view.selectedRange())
                    let saved = MacMarkdown.markdown(view.attributedString())
                    XCTAssertTrue(saved.hasSuffix("```\nAfter code"), saved)
                    XCTAssertNil(MacRichCode.at(view.attributedString(), view.selectedRange().location - 1))
                } else { XCTAssertTrue(view.string.contains("```swift\n")); XCTAssertTrue(FencedCode.blocks(in: MacMarkdown.markdown(view.attributedString())).isEmpty) }
            }
        }
    }
    @MainActor func testHeadingNavigationRevealsUnicodeDuplicateHeadingWithoutEditing() {
        let markdown = "# Long note\r\n\r\n😀 Text before.\r\n\r\n## Café plan\r\nFirst.\r\n\r\n```md\r\n## Fake heading\r\n```\r\n\r\n## Café plan\r\nSecond.\r\n"
        for source in [false, true] {
            withEditor(markdown, sourceMode: source) { view, coordinator in
                let before = MacMarkdown.markdown(view.attributedString())
                let headings = MacHeadings.entries(markdown)
                XCTAssertEqual(headings.map(\.id), ["long-note", "café-plan", "café-plan-1"])
                let request = MacHeadingRequest(fragment: "café-plan-1", path: "")
                coordinator.receiveHeading(request)
                let expected = (view.string as NSString).range(of: source ? "## Café plan" : "Café plan", options: .backwards).location
                XCTAssertEqual(view.selectedRange(), NSRange(location: expected, length: 0))
                XCTAssertEqual(source ? view.string : MacMarkdown.markdown(view.attributedString()), source ? markdown : before)
                XCTAssertFalse(view.undoManager?.canUndo ?? true, "Reading navigation must not become a text edit")
                view.setSelectedRange(NSRange(location: 0, length: 0)); coordinator.receiveHeading(request)
                XCTAssertEqual(view.selectedRange().location, 0, "A consumed request must not hijack later caret movement")
                coordinator.receiveHeading(.init(fragment: "café-plan", path: "another-note.md"))
                XCTAssertEqual(view.selectedRange().location, 0)
                if !source {
                    XCTAssertTrue(coordinator.textView(view, clickedOnLink: "#caf%C3%A9-plan-1", at: 0))
                    XCTAssertEqual(view.selectedRange().location, expected, "Local links must navigate the actual editor, including external-note editors")
                }
            }
        }

        let nested: [(String, [String], [String], [Int], String, String, String, Int, Int, Int, String?)] = [
            ("# Root\n\n> ## Quoted café\n> text\n\n- ### Item heading\n- Sibling\n", ["root", "quoted-café", "item-heading"], ["Root", "Quoted café", "Item heading"], [1, 2, 3], "item-heading", "### Item heading", "Item heading", 0, 0, 0, "# Root\n\n> ## Quoted café\n> text\n\n- ### !Item heading\n- Sibling\n"),
            ("# Root\n\n- > - # Child\n  >   - Grandchild\n- Sibling\n", ["root", "child"], ["Root", "Child"], [1, 1], "child", "# Child", "Child", 0, 0, 0, "# Root\n\n- > - # !Child\n  >   - Grandchild\n- Sibling\n"),
            ("# Root\n\n10. > 7. ## Child\n11. Sibling\n", ["root", "child"], ["Root", "Child"], [1, 2], "child", "## Child", "Child", 0, 0, 0, "# Root\n\n10. > 7. ## !Child\n11. Sibling\n"),
            ("# Root\n\n> ## Repeat\n\n- ## Repeat\n\n## Repeat\n", ["root", "repeat", "repeat-1", "repeat-2"], ["Root", "Repeat", "Repeat", "Repeat"], [1, 2, 2, 2], "repeat-1", "## Repeat", "Repeat", 1, 1, 0, "# Root\n\n> ## Repeat\n\n- ## !Repeat\n\n## Repeat\n"),
            ("# Root\n\n> Café title\n> ===\n>\n> text\n", ["root", "café-title"], ["Root", "Café title"], [1, 1], "café-title", "Café title", "Café title", 0, 0, 0, nil),
            ("# Root\n\n> ## [[Target|Alias]] and `**literal**`\n", ["root", "alias-and-literal"], ["Root", "Alias and **literal**"], [1, 2], "alias-and-literal", "## [[Target|Alias]]", "Alias", 0, 0, 0, nil),
            ("# Root\n\n- > - ## \n", ["root", "section"], ["Root", ""], [1, 2], "section", "## ", "• \n", 0, 1, 2, "# Root\n\n- > - ## !\n"),
            ("# Root\n\n> ## **Café** and &amp; text\n", ["root", "café-and-text"], ["Root", "Café and & text"], [1, 2], "café-and-text", "## **Café**", "Café and & text", 0, 0, 0, nil)
        ]
        func occurrence(_ needle: String, in value: String, index: Int) -> NSRange? {
            let text = value as NSString; var offset = 0
            for current in 0...index {
                let range = text.range(of: needle, range: NSRange(location: offset, length: text.length - offset))
                guard range.location != NSNotFound else { return nil }
                if current == index { return range }; offset = NSMaxRange(range)
            }
            return nil
        }
        for ending in ["\n", "\r\n"] { for (raw, ids, titles, levels, fragment, sourceText, richText, sourceIndex, richIndex, richOffset, typed) in nested {
            let markdown = raw.replacingOccurrences(of: "\n", with: ending)
            for source in [false, true] {
                withEditor(markdown, sourceMode: source) { view, coordinator in
                    let headings = MacHeadings.entries(markdown)
                    XCTAssertEqual(headings.map(\.id), ids, raw); XCTAssertEqual(headings.map(\.title), titles); XCTAssertEqual(headings.map(\.level), levels)
                    let needle = source ? sourceText : richText
                    guard let location = occurrence(needle, in: view.string, index: source ? sourceIndex : richIndex) else { return XCTFail("Missing expected heading text: " + needle) }
                    let expected = location.location + (source ? 0 : richOffset)
                    let before = source ? view.string : MacMarkdown.markdown(view.attributedString())
                    coordinator.receiveHeading(.init(fragment: fragment, path: ""))
                    XCTAssertEqual(view.selectedRange(), NSRange(location: expected, length: 0), raw)
                    XCTAssertEqual(source ? view.string : MacMarkdown.markdown(view.attributedString()), before)
                    XCTAssertFalse(view.undoManager?.canUndo ?? true)
                    if !source {
                        view.setSelectedRange(NSRange(location: 0, length: 0))
                        let url = "#" + fragment.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)!
                        XCTAssertTrue(coordinator.textView(view, clickedOnLink: url, at: 0))
                        XCTAssertEqual(view.selectedRange(), NSRange(location: expected, length: 0))
                        if let typed {
                            view.insertText("!", replacementRange: view.selectedRange())
                            XCTAssertEqual(coordinator.lastMarkdown, typed.replacingOccurrences(of: "\n", with: ending))
                            coordinator.action("undo"); XCTAssertEqual(coordinator.lastMarkdown, markdown)
                        }
                    }
                }
            }
        } }
    }
    @MainActor func testDelayedNotePreviewKeepsTypingFocusAndCannotReappearAfterDismissal() async throws {
        let note = NoteDocument(path: "Work/Target.md", content: "---\nzerus-id: target\n---\n# Target\nPreview body.\n", modified: Date())
        let markdown = "Read [[zerus:target|Target]].", rich = MacMarkdown.render(markdown)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.textStorage?.setAttributedString(rich)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false), scroll = NSScrollView()
        window.isReleasedWhenClosed = false; scroll.documentView = view; window.contentView = scroll; window.makeFirstResponder(view)
        let preview = MacNotePreview(), range = (view.string as NSString).range(of: "Target")
        let value = String(describing: try XCTUnwrap(rich.attribute(.link, at: range.location, effectiveRange: nil)))
        defer { preview.hide(); window.close() }
        preview.show(value: value, at: range, view: view, notes: [note], path: "Work/Source.md", open: {})
        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertTrue(preview.shown)
        XCTAssertTrue(window.firstResponder === view, "Hover must preserve typing focus")
        XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), markdown)
        preview.hide(); XCTAssertFalse(preview.shown)
        preview.show(value: value, at: range, view: view, notes: [note], path: "Work/Source.md", open: {})
        preview.hide()
        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertFalse(preview.shown, "A pending hover must not attach a late preview after navigation or editing dismisses it")
    }
    func testNotePreviewResolvesIdentityHeadingAndRelativePathsWithoutAmbiguousFallback() {
        let first = NoteDocument(path: "Work/Original.md", content: "---\nzerus-id: original\n---\n# Plan\n\n## Details\nCurrent draft detail.\n", modified: Date())
        let duplicate = NoteDocument(path: "Other/Plan.md", content: "---\nzerus-id: other\n---\n# Plan\nReplacement.\n", modified: Date())
        let notes = [first, duplicate]
        let preview = MacNotePreviewSnapshot(value: "zerus:original#details", notes: notes, currentPath: "Work/Source.md")
        XCTAssertEqual(preview?.note.path, first.path); XCTAssertEqual(preview?.heading, "details")
        XCTAssertEqual(preview?.excerpt, "## Details\nCurrent draft detail.")
        XCTAssertEqual(MacNotePreviewSnapshot(value: "Original.md#details", notes: notes, currentPath: "Work/Source.md")?.excerpt, preview?.excerpt)
        XCTAssertEqual(MacNotePreviewSnapshot(value: "#details", notes: notes, currentPath: first.path)?.note.path, first.path)
        XCTAssertNil(MacNotePreviewSnapshot(value: "Plan", notes: notes, currentPath: first.path))
        XCTAssertNil(MacNotePreviewSnapshot(value: "zerus:missing", notes: notes, currentPath: first.path))
    }
    @MainActor private func withAsyncHostedEditor<Root: View>(_ editor: Root, operation: (NSTextView, MacRichEditor.Coordinator, NSHostingView<Root>) async throws -> Void) async throws {
        let host = NSHostingView(rootView: editor)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 750, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        func nodes(_ value: NSView) -> [NSView] { [value] + value.subviews.flatMap(nodes) }
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(nodes(host).compactMap { $0 as? NSTextView }.first), coordinator = try XCTUnwrap(view.delegate as? MacRichEditor.Coordinator)
        window.makeFirstResponder(view)
        try await operation(view, coordinator, host)
    }
    @MainActor private func withHostedEditor<Root: View>(_ editor: Root, operation: (NSTextView, MacRichEditor.Coordinator, NSHostingView<Root>) throws -> Void) throws {
        let host = NSHostingView(rootView: editor)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        func textView(_ view: NSView) -> NSTextView? { (view as? NSTextView) ?? view.subviews.lazy.compactMap { textView($0) }.first }
        for _ in 0..<20 where textView(host) == nil { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        let view = try XCTUnwrap(textView(host)), coordinator = try XCTUnwrap(view.delegate as? MacRichEditor.Coordinator)
        window.makeFirstResponder(view)
        defer { window.contentView = nil }
        try operation(view, coordinator, host)
    }
    // Bare NSTextView fixtures also exercise coordinator recovery from malformed native rows.
    @MainActor private func withEditor(_ source: String, sourceMode: Bool = false, notes: [NoteDocument] = [], root: URL? = nil, path: String = "", scope: UUID? = nil, onPasteError: @escaping (String) -> Void = { _ in }, operation: (NSTextView, MacRichEditor.Coordinator) throws -> Void) rethrows {
        try autoreleasepool {
            let editor = MacRichEditor(markdown: source, source: sourceMode, editable: true, root: root, path: path, onChange: { _ in }, onLink: { _ in }, onPasteError: onPasteError, linkNotes: { notes }, commandScope: scope)
            let coordinator = MacRichEditor.Coordinator(editor), view = NSTextView()
            view.isRichText = !sourceMode; view.allowsUndo = true; view.delegate = coordinator; coordinator.view = view
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
            let scroll = NSScrollView(); view.frame = NSRect(x: 0, y: 0, width: 600, height: 500); scroll.documentView = view
            window.isReleasedWhenClosed = false; window.contentView = scroll; window.makeFirstResponder(view)
            defer { coordinator.detach(); window.close() }
            coordinator.load(source, source: sourceMode)
            try operation(view, coordinator)
        }
    }
    func testVaultSavePreservesForeignFrontmatterAndRejectsOutsideEdit() async throws {
        // Metadata reads must retain exact bytes even after warming a cache
        // with a canonically equivalent Unicode spelling.
        for title in ["Caf\u{e9}", "Cafe\u{301}"] {
            let text = "\u{feff}---\r\nOwner: \(title)\r\n---\r\n# \(title)\r\n"
            var note = NoteDocument(path: "Cached.md", content: text, modified: .distantPast)
            XCTAssertEqual(Data((note.parts.header + note.parts.body).utf8), Data(text.utf8))
            XCTAssertEqual(note.property("Owner").map { Data($0.utf8) }, Data(title.utf8))
            XCTAssertEqual(Data(note.title.utf8), Data(title.utf8))
            note.content = text.replacingOccurrences(of: "Owner: ", with: "Changed: ")
            XCTAssertNil(note.property("Owner"), "A changed note must not reuse its previous metadata")
            XCTAssertEqual(Data((note.parts.header + note.parts.body).utf8), Data(note.content.utf8))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        let source = "---\nzerus-id: test-native-save\ncustom: {complex: [1, 2]} # keep\n---\n# Title\n\nBody.\n"
        try Data(source.utf8).write(to: file)
        let io = VaultFiles(root: root), snapshot = try await io.scan()
        let note = try XCTUnwrap(snapshot.notes.first)
        XCTAssertEqual(note.content, source)
        let edited = note.replacingBody("# Title\n\nChanged.\n")
        try await io.write(note.path, data: Data(edited.utf8), expected: Data(source.utf8))
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("custom: {complex: [1, 2]} # keep"))
        let outside = edited + "External edit.\n"; try Data(outside.utf8).write(to: file)
        do { try await io.write(note.path, data: Data((edited + "Local edit").utf8), expected: Data(edited.utf8)); XCTFail("An external edit must block saving") }
        catch { XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), outside) }
    }
}

/// Uses real SwiftUI State and AppStorage so preference changes exercise normal
/// representable updates with the current edited document, not a fixed fixture.
private struct MacLayoutEditorFixture: View {
    @State var markdown: String
    let source: Bool
    let preferences: UserDefaults
    var images: [String: NSImage] = [:]
    var body: some View {
        MacRichEditor(markdown: markdown, source: source, editable: true, images: images, onChange: { markdown = $0 }, onLink: { _ in })
            .defaultAppStorage(preferences)
    }
}

private final class MacCompactFixtureState: ObservableObject {
    @Published var markdown = "# Compact note\n\nOriginal paragraph.\n"
    @Published var browsing = false
    @Published var mode = "List"
    @Published var interactive = true
}
private struct MacCompactFixture: View {
    @ObservedObject var state: MacCompactFixtureState
    var body: some View {
        GeometryReader { geometry in
            MacWorkspacePanes(
                layout: MacWorkspaceArrangement(width: geometry.size.width, sidebar: true, inspector: true, hasNote: true, list: state.mode == "List", browsing: state.browsing),
                interactionEnabled: state.interactive,
                library: MacPaneFrameProbe(name: "library"),
                collection: MacPaneFrameProbe(name: "collection"),
                editor: MacRichEditor(markdown: state.markdown, source: false, editable: true, onChange: { state.markdown = $0 }, onLink: { _ in }),
                inspector: MacPaneFrameProbe(name: "inspector"))
        }
    }
}
private struct MacPaneFrameProbe: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView { let view = NSView(); view.identifier = .init(name); return view }
    func updateNSView(_ view: NSView, context: Context) {}
}
