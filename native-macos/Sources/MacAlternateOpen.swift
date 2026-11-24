import SwiftUI
import AppKit

/// Let normal clicks reach SwiftUI; handle middle-click open-in-tab gestures
/// without turning the whole row into an AppKit control.
struct MacAlternateOpen: NSViewRepresentable {
    let action: () -> Void
    var handlesTripleClick = false
    func makeNSView(context: Context) -> AlternateOpenView {
        let view = AlternateOpenView(); view.action = action; view.handlesTripleClick = handlesTripleClick; return view
    }
    func updateNSView(_ view: AlternateOpenView, context: Context) { view.action = action; view.handlesTripleClick = handlesTripleClick }
    final class AlternateOpenView: NSView {
        var action: (() -> Void)?
        var handlesTripleClick = false
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard super.hitTest(point) != nil, let event = NSApp.currentEvent else { return nil }
            if event.type == .otherMouseDown && event.buttonNumber == 2 { return self }
            if handlesTripleClick && event.type == .leftMouseDown && event.clickCount == 3 { return self }
            return nil
        }
        override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { action?() } }
        override func mouseDown(with event: NSEvent) { if handlesTripleClick && event.clickCount == 3 { action?() } }
    }
}

/// Gallery cards share one native event surface. Per-card NSView overlays
/// otherwise join SwiftUI's focus-responder traversal even though they never
/// accept ordinary keyboard focus. Anchors follow grid layout and scrolling.
private struct MacGalleryAlternateRegion {
    let anchor: Anchor<CGRect>
    let action: () -> Void
}
private struct MacGalleryAlternateRegions: PreferenceKey {
    static let defaultValue: [MacGalleryAlternateRegion] = []
    static func reduce(value: inout [MacGalleryAlternateRegion], nextValue: () -> [MacGalleryAlternateRegion]) {
        // One note can have a card in several relation/property groups.
        // Retain every visible occurrence instead of coalescing by path.
        value.append(contentsOf: nextValue())
    }
}
struct MacGalleryAlternateOpenTarget: ViewModifier {
    let shared: Bool
    let action: () -> Void
    func body(content: Content) -> some View {
        if shared {
            content.anchorPreference(key: MacGalleryAlternateRegions.self, value: .bounds) { [.init(anchor: $0, action: action)] }
        } else { content.overlay(MacAlternateOpen(action: action).accessibilityHidden(true)) }
    }
}
struct MacGalleryAlternateOpenHost: ViewModifier {
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(MacGalleryAlternateRegions.self) { regions in
            GeometryReader { geometry in
                MacGalleryAlternateOpenSurface(regions: regions.map { (geometry[$0.anchor], $0.action) })
                    .accessibilityHidden(true)
            }
        }
    }
}
private struct MacGalleryAlternateOpenSurface: NSViewRepresentable {
    let regions: [(CGRect, () -> Void)]
    func makeNSView(context: Context) -> EventView { EventView() }
    func updateNSView(_ view: EventView, context: Context) { view.regions = regions }
    final class EventView: NSView {
        var regions: [(CGRect, () -> Void)] = []
        override var isFlipped: Bool { true }
        private func alternate(_ event: NSEvent) -> Bool {
            event.type == .otherMouseDown && event.buttonNumber == 2
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard super.hitTest(point) != nil, let event = NSApp.currentEvent, alternate(event),
                  regions.contains(where: { $0.0.contains(convert(point, from: superview)) }) else { return nil }
            return self
        }
        private func open(_ event: NSEvent) {
            guard alternate(event), let region = regions.first(where: { $0.0.contains(convert(event.locationInWindow, from: nil)) }) else { return }
            region.1()
        }
        override func otherMouseDown(with event: NSEvent) { open(event) }
        override func mouseDown(with event: NSEvent) { open(event) }
    }
}

/// Keyboard commands belong to the collection content, outside search fields.
struct MacCollectionKeyboard: ViewModifier {
    @Bindable var store: MacWorkspace
    @ObservedObject private var selection: MacCollectionSelectionState
    init(store: MacWorkspace) { self.store = store; self.selection = store.collectionSelection }
    @State private var focusRequest = 0
    func body(content: Content) -> some View {
        content.background(MacCollectionKeyTarget(store: store, request: focusRequest))
            .simultaneousGesture(TapGesture().onEnded { focusRequest += 1 })
            .onChange(of: selection.selecting) { _, selecting in if selecting { focusRequest += 1 } }
    }
}

private struct MacCollectionKeyTarget: NSViewRepresentable {
    let store: MacWorkspace
    let request: Int
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) {
        view.store = store; view.enabled = enabled
        let previous = view.workspace; view.workspace = store.workspaceID
        if previous != nil && previous != view.workspace, view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
        guard view.request != request else { return }
        view.request = request
        let origin = store.workspaceID
        DispatchQueue.main.async { [weak view] in
            guard let view, view.request == request, view.workspace == origin, view.enabled,
                  let window = view.window, window.attachedSheet == nil else { return }
            // Choose a responder within this window; do not activate it or
            // change which application/window receives the keyboard.
            window.makeFirstResponder(view)
        }
    }
    final class KeyView: NSView, NSUserInterfaceValidations {
        weak var store: MacWorkspace?
        var enabled = true
        var request = 0
        var workspace: UUID?
        override var acceptsFirstResponder: Bool { enabled }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func selectAll(_ sender: Any?) { if enabled { store?.selectAllCollectionNotes() } }
        override func cancelOperation(_ sender: Any?) {
            if enabled, let store { store.clearCollectionSelection() }
            else { super.cancelOperation(sender) }
        }
        private func isSelectAll(_ event: NSEvent) -> Bool {
            event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command && event.charactersIgnoringModifiers?.lowercased() == "a"
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard enabled, window?.firstResponder === self, isSelectAll(event) else { return super.performKeyEquivalent(with: event) }
            selectAll(nil); return true
        }
        override func keyDown(with event: NSEvent) {
            if enabled, isSelectAll(event) { selectAll(nil); return }
            if enabled, event.keyCode == 53 { cancelOperation(nil); return }
            super.keyDown(with: event)
        }
        func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool { enabled }
    }
}
