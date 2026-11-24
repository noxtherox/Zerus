import XCTest
import SwiftUI
import AppKit
@testable import Zerus_Native

@MainActor final class MacInterfaceZoomTests: XCTestCase {
    func testWorkspaceZoomKeepsHeaderAndFooterInsideTheToolbarContentArea() throws {
        let suite = "Zerus-workspace-toolbar-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        func column(_ name: String) -> some View {
            VStack(spacing: 0) {
                TextField("Header", text: .constant("Workspace header")).frame(height: 36).background(ToolbarControlProbe(name: name + ".header"))
                Spacer(minLength: 0)
                Text("Saved").frame(height: 24).background(ToolbarControlProbe(name: name + ".footer"))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        let host = NSHostingView(rootView: MacZoomViewport {
            GeometryReader { viewport in
                let layout = MacWorkspaceArrangement(width: viewport.size.width, sidebar: true, inspector: true, hasNote: true, list: true, browsing: false)
                MacWorkspacePanes(layout: layout, library: column("library"), collection: column("collection"), editor: column("editor"), inspector: column("inspector"), tabs: EmptyView())
                    .toolbar { ToolbarItem { Button("Workspace") {} } }
            }
        }.defaultAppStorage(preferences))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "Workspace layout fixture")
        window.toolbarStyle = .unified
        window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
        for zoom in [100, 80, 150, 100] {
            preferences.set(zoom, forKey: "zerus.mac.interfaceZoom")
            window.setContentSize(NSSize(width: zoom == 150 ? 2200 : 1400, height: 850))
            for _ in 0..<12 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            let available = window.contentLayoutRect
            XCTAssertLessThan(available.maxY, window.frame.height, "The fixture must reserve a native title/toolbar area")
            for name in ["library.header", "library.footer", "collection.header", "collection.footer", "editor.header", "editor.footer", "inspector.header", "inspector.footer"] {
                let marker = try XCTUnwrap(nodes(host).first { $0.identifier?.rawValue == name })
                let frame = marker.convert(marker.bounds, to: nil)
                XCTAssertGreaterThan(frame.height, 10)
                if name.hasSuffix(".header") { XCTAssertGreaterThanOrEqual(frame.maxY, available.maxY - 12, "Headers must sit directly below the toolbar") }
                XCTAssertGreaterThanOrEqual(frame.minY, available.minY - 1, "\(name), zoom \(zoom)")
                XCTAssertLessThanOrEqual(frame.maxY, available.maxY + 1, "\(name), zoom \(zoom)")
            }
        }
    }
    func testOpenSheetRefitsForLiveZoomAndItsOwnStateGrowth() throws {
        try withLiveSheet { state, preferences, window, content, settle in
            func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
            let field = try XCTUnwrap(nodes(content).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Live title" })
            let sheet = try XCTUnwrap(window.attachedSheet)
            XCTAssertTrue(sheet.makeFirstResponder(field))
            let editor = try XCTUnwrap(sheet.fieldEditor(true, for: field) as? NSTextView)
            editor.insertText("Typed title", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            let caret = editor.selectedRange()
            let initial = content.bounds.size
            func footerInsideWindow() throws {
                let footer = try XCTUnwrap(nodes(content).first { $0.identifier?.rawValue == "dialog.done.frame" })
                let rect = footer.convert(footer.bounds, to: content)
                XCTAssertGreaterThanOrEqual(rect.minX, -1); XCTAssertLessThanOrEqual(rect.maxX, content.bounds.maxX + 1)
                XCTAssertGreaterThanOrEqual(rect.minY, -1); XCTAssertLessThanOrEqual(rect.maxY, content.bounds.maxY + 1)
            }
            for (zoom, factor): (Int, CGFloat) in [(150, 1.5), (100, 1)] {
                preferences.set(zoom, forKey: "zerus.mac.interfaceZoom"); settle()
                XCTAssertEqual(content.bounds.width, initial.width * factor, accuracy: 2, "An already open sheet must resize with zoom")
                XCTAssertEqual(content.bounds.height, initial.height * factor, accuracy: 2)
                XCTAssertEqual(field.convert(NSRect(x: 0, y: 0, width: 100, height: 100), to: content).width, 100 * factor, accuracy: 0.5)
                try footerInsideWindow()
                XCTAssertTrue(sheet.firstResponder === editor); XCTAssertEqual(editor.selectedRange(), caret); XCTAssertEqual(editor.string, "Typed title")
            }
            let expand = try XCTUnwrap(state.expand); expand(true); settle()
            XCTAssertGreaterThan(content.bounds.height, initial.height + 100, "Inner validation/content changes must refit the native sheet")
            try footerInsideWindow()
            expand(false); settle(); XCTAssertEqual(content.bounds.height, initial.height, accuracy: 2)
            sheet.makeFirstResponder(nil)
            XCTAssertTrue(nodes(content).contains { $0 === field }); XCTAssertEqual(field.stringValue, "Typed title")
            XCTAssertNotNil(window.attachedSheet)
        }
    }
    func testOpenSheetUpdatesBothSwiftUIAndNativeAppearance() throws {
        for innerPreference in [false, true] {
            try withLiveSheet(innerPreference: innerPreference) { state, preferences, window, content, settle in
                func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
                let field = try XCTUnwrap(nodes(content).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Live title" })
                for appearance in ["dark", "light"] {
                    preferences.set(appearance, forKey: "zerus.mac.appearance"); settle()
                    let expected: NSAppearance.Name = appearance == "dark" ? .darkAqua : .aqua
                    XCTAssertEqual(window.attachedSheet?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
                    XCTAssertEqual(field.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected, "Native form controls must follow live appearance")
                    XCTAssertEqual(state.scheme, appearance == "dark" ? .dark : .light)
                }
            }
        }
    }
    private func withLiveSheet(innerPreference: Bool = false, operation: (LiveSheetState, UserDefaults, NSWindow, NSView, () -> Void) throws -> Void) throws {
        let suite = "Zerus-live-sheet-" + UUID().uuidString, preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences.set(100, forKey: "zerus.mac.interfaceZoom"); preferences.set("light", forKey: "zerus.mac.appearance")
        defer { preferences.removePersistentDomain(forName: suite) }
        let state = LiveSheetState(), host = NSHostingView(rootView: LiveSheetFixture(state: state, innerPreference: innerPreference).defaultAppStorage(preferences))
        let display = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 1000)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: display.maxY - 740, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        func settle() { for _ in 0..<25 { host.layoutSubtreeIfNeeded(); window.attachedSheet?.contentView?.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)) } }
        defer { state.presented = false; settle(); state.expand = nil; window.contentView = nil; window.close() }
        state.presented = true; settle()
        let content = try XCTUnwrap(window.attachedSheet?.contentView)
        try operation(state, preferences, window, content, settle)
    }
    func testLargeTableSheetKeepsItsGridLazyAndCanResizeAtDefaultZoom() throws {
        let table = MarkdownTable(rows: (0..<400).map { row in (0..<6).map { "Row \(row) column \($0)" } })
        let request = MacTableRequest(workspaceID: UUID(), path: "Fixture.md", source: "", range: nil, table: table)
        let suite = "Zerus-table-sheet-" + UUID().uuidString, preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences.set(100, forKey: "zerus.mac.interfaceZoom")
        defer { preferences.removePersistentDomain(forName: suite) }
        let state = ZoomSheetState(), host = NSHostingView(rootView: ZoomTableSheetFixture(state: state, request: request).defaultAppStorage(preferences))
        let display = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 1000)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: display.maxY - 740, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { state.dismissDialog = nil; state.dismissNested = nil; window.attachedSheet?.orderOut(nil); window.contentView = nil; window.close() }
        func settle() { for _ in 0..<20 { host.layoutSubtreeIfNeeded(); window.attachedSheet?.contentView?.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)) } }
        func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
        state.presented = true; settle()
        let sheet = try XCTUnwrap(window.attachedSheet), content = try XCTUnwrap(sheet.contentView)
        let cells = nodes(content).compactMap { $0 as? NSTextField }.filter { $0.stringValue.hasPrefix("Row ") }
        XCTAssertGreaterThan(cells.count, 6, "The sheet must show its editable grid")
        XCTAssertLessThan(cells.count, 200, "Opening a large table must build visible rows, not thousands of cell editors")
        XCTAssertTrue(sheet.styleMask.contains(.resizable), "Flexible table sheets must retain native resizing")
        let first = try XCTUnwrap(cells.first { $0.stringValue == "Row 0 column 0" })
        XCTAssertTrue(sheet.makeFirstResponder(first))
        let editor = try XCTUnwrap(sheet.fieldEditor(true, for: first) as? NSTextView)
        editor.insertText("Retained cell", replacementRange: NSRange(location: 0, length: editor.string.utf16.count)); sheet.makeFirstResponder(nil)
        let before = content.bounds.size
        sheet.setContentSize(.init(width: before.width + 100, height: before.height + 80)); settle()
        XCTAssertGreaterThan(content.bounds.width, before.width + 50); XCTAssertGreaterThan(content.bounds.height, before.height + 40)
        XCTAssertTrue(nodes(content).contains { $0 === first }); XCTAssertEqual(first.stringValue, "Retained cell")
        state.presented = false; settle(); XCTAssertNil(window.attachedSheet)
    }
    func testFlexibleListAndSplitDialogsReceiveAUsableViewport() throws {
        for split in [false, true] {
            let host = NSHostingView(rootView: MacPresentationViewport(factor: 1, availableSize: .init(width: 900, height: 700)) {
                if split { HSplitView { FlexibleDialogFrame(name: "left"); FlexibleDialogFrame(name: "right") } }
                else { VStack { List(0..<100, id: \.self) { Text("Row \($0)") }.background(FlexibleDialogFrame(name: "list")); Text("Footer") }.frame(minWidth: 620) }
            })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.contentView = nil; window.close() }
            for _ in 0..<10 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
            for name in split ? ["left", "right"] : ["list"] {
                let frame = try XCTUnwrap(nodes(host).first { $0.identifier?.rawValue == name })
                XCTAssertGreaterThan(frame.bounds.height, 300, "Flexible dialog content must not collapse to a strip")
                XCTAssertGreaterThan(frame.bounds.width, 100)
            }
        }
    }
    func testToolbarZoomReservesSpaceForScaledNativeControls() throws {
        let suite = "Zerus-toolbar-zoom-" + UUID().uuidString, preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let host = NSHostingView(rootView: HStack(spacing: 10) {
            ToolbarControlProbe(name: "first").frame(width: 100, height: 32).modifier(MacToolbarZoom())
            ToolbarControlProbe(name: "second").frame(width: 100, height: 32).modifier(MacToolbarZoom())
        }.defaultAppStorage(preferences))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
        for (zoom, width): (Int, CGFloat) in [(80, 80), (150, 150), (100, 100)] {
            preferences.set(zoom, forKey: "zerus.mac.interfaceZoom")
            for _ in 0..<8 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            let first = try XCTUnwrap(nodes(host).first { $0.identifier?.rawValue == "first" }), second = try XCTUnwrap(nodes(host).first { $0.identifier?.rawValue == "second" })
            let a = first.convert(first.bounds, to: host), b = second.convert(second.bounds, to: host)
            XCTAssertEqual(a.width, width, accuracy: 0.5); XCTAssertEqual(b.width, width, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(b.minX - a.maxX, 9.5, "Toolbar drawing and its reserved layout must scale together")
        }
    }
    func testZoomedBooleanAndItemSheetsKeepNativeDismissalAndStayInsideTheDisplay() throws {
        let suite = "Zerus-sheet-zoom-" + UUID().uuidString, preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences.set(150, forKey: "zerus.mac.interfaceZoom")
        defer { preferences.removePersistentDomain(forName: suite) }
        let state = ZoomSheetState(), host = NSHostingView(rootView: ZoomSheetFixture(state: state).defaultAppStorage(preferences))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: (NSScreen.main?.visibleFrame.minY ?? 0) + 100, width: 700, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { state.dismissDialog = nil; state.dismissNested = nil; window.attachedSheet?.orderOut(nil); window.contentView = nil; window.close() }
        func settle() { for _ in 0..<20 { host.layoutSubtreeIfNeeded(); window.attachedSheet?.contentView?.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)) } }
        func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
        for itemSheet in [false, true] {
            if itemSheet { state.item = .init() } else { state.presented = true }
            settle()
            let sheet = try XCTUnwrap(window.attachedSheet), content = try XCTUnwrap(sheet.contentView)
            let field = try XCTUnwrap(nodes(content).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Sheet title" })
            XCTAssertEqual(field.convert(NSRect(x: 0, y: 0, width: 100, height: 100), to: content).width, 150, accuracy: 0.5, "The saved zoom must reach a separate sheet window")
            if let display = (window.screen ?? NSScreen.main)?.visibleFrame {
                XCTAssertLessThanOrEqual(sheet.frame.width, display.width); XCTAssertLessThanOrEqual(sheet.frame.height, display.height)
                XCTAssertGreaterThanOrEqual(sheet.frame.minY, display.minY, "A sheet anchored to a low parent must stay above the display bottom")
            }
            if !itemSheet {
                state.nested = true; settle()
                let nested = try XCTUnwrap((window.sheets + sheet.sheets).first { $0 !== sheet }), nestedContent = try XCTUnwrap(nested.contentView)
                XCTAssertTrue(nested.isVisible, "The nested sheet must be presented, not queued behind its parent")
                let nestedField = try XCTUnwrap(nodes(nestedContent).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Nested title" })
                XCTAssertEqual(nestedField.convert(NSRect(x: 0, y: 0, width: 100, height: 100), to: nestedContent).width, 150, accuracy: 0.5, "Nested sheets must scale once")
                let dismissNested = try XCTUnwrap(state.dismissNested); dismissNested(); settle()
                XCTAssertNil(sheet.attachedSheet); XCTAssertNotNil(window.attachedSheet); XCTAssertTrue(state.presented)
            }
            let dismiss = try XCTUnwrap(state.dismissDialog); dismiss(); settle()
            XCTAssertNil(window.attachedSheet); XCTAssertFalse(state.presented); XCTAssertNil(state.item)
        }
        XCTAssertEqual(state.dismissals, 2, "Both sheet overloads must preserve their onDismiss callback")
    }
    func testAnchoredCalendarPopoverKeepsItsZoomAndParentSheetWhileChoosingDay() throws {
        for zoom in [100, 150] {
            let suite = "Zerus-popover-zoom-" + UUID().uuidString
            let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
            preferences.set(zoom, forKey: "zerus.mac.interfaceZoom")
            let state = PopoverHostState(), host = NSHostingView(rootView: PopoverHostFixture(state: state).defaultAppStorage(preferences))
            let display = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let window = NSWindow(contentRect: NSRect(x: 60, y: display.maxY - 360, width: 600, height: 240), styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            func settle() {
                for _ in 0..<15 {
                    host.layoutSubtreeIfNeeded(); window.attachedSheet?.contentView?.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                }
            }
            defer {
                state.openPopover = nil; state.selectedDate = nil; state.presented = false; settle()
                window.attachedSheet?.orderOut(nil); window.contentView = nil; window.close()
                preferences.removePersistentDomain(forName: suite)
            }
            state.presented = true; settle()
            let sheet = try XCTUnwrap(window.attachedSheet)
            try XCTUnwrap(state.openPopover)(); settle()
            func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
            let picker = try XCTUnwrap(NSApp.windows.filter { $0.isVisible && $0 !== window && $0 !== sheet }
                .compactMap(\.contentView).flatMap(nodes).compactMap { $0 as? NSDatePicker }.first,
                "The anchored calendar must remain visible inside its parent sheet at \(zoom)%")
            let popup = try XCTUnwrap(picker.window)
            XCTAssertTrue(window.attachedSheet === sheet); XCTAssertTrue(sheet.isVisible)
            XCTAssertGreaterThan(picker.bounds.width, 0); XCTAssertGreaterThan(picker.bounds.height, 0)
            XCTAssertEqual(picker.convert(NSRect(x: 0, y: 0, width: 100, height: 100), to: popup.contentView).width, Double(zoom), accuracy: 1)
            XCTAssertLessThanOrEqual(popup.frame.width, display.width); XCTAssertLessThanOrEqual(popup.frame.height, display.height)
            let chosen = try XCTUnwrap(NativeTask.parseDay("2027-01-02"))
            DispatchQueue.main.async {
                picker.dateValue = chosen
                XCTAssertTrue(picker.sendAction(picker.action, to: picker.target))
            }
            settle()
            XCTAssertEqual(try XCTUnwrap(state.selectedDate)(), chosen)
            XCTAssertFalse(popup.isVisible, "Choosing a day closes only the calendar")
            XCTAssertTrue(window.attachedSheet === sheet); XCTAssertTrue(sheet.isVisible)
        }
    }
    func testEnlargedDialogKeepsItsActionsReachableAndItsFormStateIntact() throws {
        let state = ZoomDialogState(), host = NSHostingView(rootView: ZoomDialogFixture(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
        func settle() { for _ in 0..<8 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) } }
        settle()
        let field = try XCTUnwrap(nodes(host).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Title" })
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(window.fieldEditor(true, for: field) as? NSTextView)
        editor.insertText("Retained title", replacementRange: NSRange(location: 0, length: editor.string.utf16.count)); window.makeFirstResponder(nil)
        for factor: CGFloat in [1.5, 0.8, 1] {
            state.factor = factor; settle()
            let button = try XCTUnwrap(nodes(host).first { $0.identifier?.rawValue == "dialog.done.frame" })
            XCTAssertEqual(field.stringValue, "Retained title")
            XCTAssertTrue(nodes(host).contains { $0 === field }, "Changing zoom must retain the form")
            XCTAssertEqual(field.convert(NSRect(x: 0, y: 0, width: 100, height: 100), to: host).width, factor * 100, accuracy: 0.5)
            XCTAssertLessThanOrEqual(host.fittingSize.width, 640.5); XCTAssertLessThanOrEqual(host.fittingSize.height, 480.5)
            button.scrollToVisible(button.bounds); settle()
            let rect = button.convert(button.bounds, to: host)
            XCTAssertGreaterThanOrEqual(rect.minX, -1); XCTAssertLessThanOrEqual(rect.maxX, 641)
            XCTAssertGreaterThanOrEqual(rect.minY, -1); XCTAssertLessThanOrEqual(rect.maxY, 481)
        }
    }
}
private final class ZoomDialogState: ObservableObject {
    @Published var factor: CGFloat = 1
    @Published var title = "Original title"
}
private struct ZoomDialogFixture: View {
    @ObservedObject var state: ZoomDialogState
    var body: some View {
        MacPresentationViewport(factor: state.factor, availableSize: .init(width: 640, height: 480)) {
            VStack {
                TextField("Title", text: $state.title)
                Spacer()
                HStack { Spacer(); Button("Done") {}.background(ZoomActionFrame()) }
            }.padding(20).frame(width: 1000, height: 720)
        }
    }
}

/// Observe the real SwiftUI action's frame without depending on whether macOS
/// renders Button through NSButton or a SwiftUI accessibility element.
private struct ZoomActionFrame: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { let view = NSView(); view.identifier = .init("dialog.done.frame"); return view }
    func updateNSView(_ view: NSView, context: Context) {}
}

private struct ZoomSheetItem: Identifiable { let id = UUID() }
private final class ZoomSheetState: ObservableObject {
    @Published var presented = false
    @Published var item: ZoomSheetItem?
    @Published var nested = false
    var dismissNested: (() -> Void)?
    var dismissDialog: (() -> Void)?
    var dismissals = 0
}
private struct ZoomSheetFixture: View {
    @ObservedObject var state: ZoomSheetState
    var body: some View {
        Color.clear.frame(minWidth: 500, minHeight: 200)
            .macSheet(isPresented: $state.presented, onDismiss: { state.dismissals += 1 }) { ZoomSheetContent(state: state) }
            .macSheet(item: $state.item, onDismiss: { state.dismissals += 1 }) { _ in ZoomSheetContent(state: state) }
    }
}
private struct ZoomSheetContent: View {
    @ObservedObject var state: ZoomSheetState
    @State private var title = "Sheet"
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack { TextField("Sheet title", text: $title); Spacer(); Button("Done") { dismiss() } }
            .padding(20).frame(width: 1000, height: 720)
            .macSheet(isPresented: Binding(get: { state.nested }, set: { state.nested = $0 })) { ZoomNestedSheetContent(state: state) }
            .onAppear { state.dismissDialog = { dismiss() } }
            .onDisappear { state.dismissDialog = nil }
    }
}

private struct ToolbarControlProbe: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSButton { let button = NSButton(title: name, target: nil, action: nil); button.identifier = .init(name); return button }
    func updateNSView(_ button: NSButton, context: Context) {}
}

private struct FlexibleDialogFrame: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView { let view = NSView(); view.identifier = .init(name); return view }
    func updateNSView(_ view: NSView, context: Context) {}
}

private struct ZoomTableSheetFixture: View {
    @ObservedObject var state: ZoomSheetState
    let request: MacTableRequest
    var body: some View {
        Color.clear.frame(minWidth: 500, minHeight: 300)
            .macSheet(isPresented: $state.presented) { MacTableEditor(request: request, save: { _ in }) }
    }
}

private struct ZoomNestedSheetContent: View {
    let state: ZoomSheetState
    @State private var title = "Nested"
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TextField("Nested title", text: $title).padding(20).frame(width: 400, height: 200)
            .onAppear { state.dismissNested = { dismiss() } }
            .onDisappear { state.dismissNested = nil }
    }
}

private final class LiveSheetState: ObservableObject {
    @Published var presented = false
    var expand: ((Bool) -> Void)?
    var scheme = ColorScheme.light
}
private struct LiveSheetFixture: View {
    @ObservedObject var state: LiveSheetState
    let innerPreference: Bool
    @AppStorage("zerus.mac.appearance") private var appearance = "light"
    var body: some View {
        Color.clear.frame(minWidth: 500, minHeight: 300)
            .macSheet(isPresented: $state.presented) { LiveSheetContent(state: state, innerPreference: innerPreference) }
            .preferredColorScheme(appearance == "dark" ? .dark : .light)
    }
}
private struct LiveSheetContent: View {
    let state: LiveSheetState
    let innerPreference: Bool
    @State private var expanded = false
    @State private var title = "Original title"
    @AppStorage("zerus.mac.appearance") private var appearance = "light"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Live title", text: $title)
            if expanded { ForEach(0..<12, id: \.self) { Text("Validation detail \($0)") } }
            HStack { Spacer(); Button("Done") {}.background(ZoomActionFrame()) }
            LiveSchemeProbe(state: state).frame(width: 1, height: 1)
        }.padding(20).frame(width: 460)
            .preferredColorScheme(innerPreference ? (appearance == "dark" ? .dark : .light) : nil)
            .onAppear { state.expand = { expanded = $0 } }
    }
}
private struct LiveSchemeProbe: NSViewRepresentable {
    let state: LiveSheetState
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) { state.scheme = context.environment.colorScheme }
}

private final class PopoverHostState: ObservableObject {
    @Published var presented = false
    var openPopover: (() -> Void)?
    var selectedDate: (() -> Date)?
}
private struct PopoverHostFixture: View {
    @ObservedObject var state: PopoverHostState
    var body: some View {
        Color.clear.frame(width: 600, height: 240)
            .macSheet(isPresented: $state.presented) { PopoverHostContent(state: state) }
    }
}
private struct PopoverHostContent: View {
    @ObservedObject var state: PopoverHostState
    @State private var presented = false
    @State private var date = Date(timeIntervalSince1970: 1795910400)
    var body: some View {
        VStack {
            Text("Calendar anchor")
                .macPopover(isPresented: $presented) {
                    DatePicker("Due", selection: Binding(get: { date }, set: {
                        date = $0
                        presented = false
                    }), displayedComponents: .date)
                        .datePickerStyle(.graphical).labelsHidden().padding(12).frame(width: 280)
                }
            Spacer()
        }.padding(24).frame(width: 400, height: 160)
        .onAppear { state.openPopover = { presented = true }; state.selectedDate = { date } }
        .onDisappear { state.openPopover = nil; state.selectedDate = nil }
    }
}
