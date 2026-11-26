import SwiftUI
import AppKit

/// Match the desktop client's device-local zoom choices. Document text and
/// Markdown stay at their original sizes; the whole application canvas scales.
enum MacInterfaceZoom {
    static let options = [80, 90, 100, 110, 125, 150]
    static func validated(_ value: Int) -> Int { options.contains(value) ? value : 100 }
    static func factor(_ value: Int) -> CGFloat { CGFloat(validated(value)) / 100 }
}

struct MacZoomViewport<Content: View>: View {
    @AppStorage("zerus.mac.interfaceZoom") private var percentage = 100
    /// False when the content draws its own title bar and the divider under
    /// it, as the workspace window does.
    var separatesToolbar = true
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { viewport in
            let factor = MacInterfaceZoom.factor(percentage)
            // Separate the native toolbar from the scaled canvas. This also
            // keeps split views inside the window's usable safe area.
            VStack(spacing: 0) {
                if separatesToolbar { Divider() }
                content()
            }.frame(width: viewport.size.width / factor, height: viewport.size.height / factor)
                .scaleEffect(factor, anchor: .topLeading)
        }.clipped()
    }
}

/// Keep AppKit's split-view hosting boundaries at native window scale. Applying
/// an ancestor transform to NSSplitView can leave its hosted controls drawing at
/// one scale and hit-testing at another. Scale each pane inside its own graph,
/// while cancelling the surrounding canvas transform for the native divider.
struct MacZoomSplitView<Content: View>: View {
    var axis: Axis = .horizontal
    @AppStorage("zerus.mac.interfaceZoom") private var percentage = 100
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            let factor = MacInterfaceZoom.factor(percentage)
            Group(subviews: content()) { panes in
                if axis == .horizontal {
                    HSplitView {
                        ForEach(panes) { pane in
                            MacScaledLayout(factor: factor) { pane.scaleEffect(factor, anchor: .topLeading) }
                        }
                    }
                } else {
                    VSplitView {
                        ForEach(panes) { pane in
                            MacScaledLayout(factor: factor) { pane.scaleEffect(factor, anchor: .topLeading) }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width * factor, height: geometry.size.height * factor)
            .scaleEffect(1 / factor, anchor: .topLeading)
        }
    }
}

/// Toolbar items live outside the window's SwiftUI canvas. Scale their layout
/// as well as their drawing so adjacent native toolbar items cannot overlap.
struct MacToolbarZoom: ViewModifier {
    @AppStorage("zerus.mac.interfaceZoom") private var percentage = 100
    @ViewBuilder func body(content: Content) -> some View {
        let factor = MacInterfaceZoom.factor(percentage)
        if factor == 1 { content }
        else { MacScaledLayout(factor: factor) { content.scaleEffect(factor, anchor: .topLeading) } }
    }
}
private struct MacScaledLayout: Layout {
    let factor: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(.init(width: proposal.width.map { $0 / factor }, height: proposal.height.map { $0 / factor }))
        return .init(width: size.width * factor, height: size.height * factor)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: bounds.width / factor, height: bounds.height / factor))
    }
}

/// Keep the presentation content in its original SwiftUI graph. The finite
/// layout proposal keeps lazy tables bounded while overflow belongs to the outer scroll view.
struct MacPresentationViewport<Content: View>: View {
    let factor: CGFloat
    let availableSize: CGSize
    var resizesWindow = false
    @ViewBuilder let content: () -> Content
    @State private var viewport: CGSize?
    @State private var minimum: CGSize?
    @State private var ideal: CGSize?
    @State private var maximum: CGSize?
    var body: some View {
        // Geometry arrives after the initial layout and each metric can change
        // independently. Keep every intermediate frame proposal consistent.
        let lower = CGSize(width: min(availableSize.width, minimum?.width ?? 0), height: min(availableSize.height, minimum?.height ?? 0))
        let upper = CGSize(width: max(lower.width, min(availableSize.width, maximum?.width ?? availableSize.width)),
                           height: max(lower.height, min(availableSize.height, maximum?.height ?? availableSize.height)))
        let preferred = CGSize(width: min(upper.width, max(lower.width, ideal?.width ?? 760)),
                               height: min(upper.height, max(lower.height, ideal?.height ?? 600)))
        ScrollView([.horizontal, .vertical]) {
            MacPresentationLayout(factor: factor, available: availableSize, viewport: viewport) {
                content().scaleEffect(factor, anchor: .topLeading)
                Color.clear.allowsHitTesting(false).accessibilityHidden(true).onGeometryChange(for: CGSize.self) { $0.size } action: { minimum = $0 }
                Color.clear.allowsHitTesting(false).accessibilityHidden(true).onGeometryChange(for: CGSize.self) { $0.size } action: { ideal = $0 }
                Color.clear.allowsHitTesting(false).accessibilityHidden(true).onGeometryChange(for: CGSize.self) { $0.size } action: { maximum = $0 }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        .frame(minWidth: lower.width, idealWidth: preferred.width, maxWidth: upper.width,
               minHeight: lower.height, idealHeight: preferred.height, maxHeight: upper.height)
        .background(MacPresentationWindowSizing(factor: factor, minimum: minimum, ideal: ideal, maximum: maximum, enabled: resizesWindow).frame(width: 0, height: 0))
    }
}
private struct MacPresentationLayout: Layout {
    let factor: CGFloat
    let available: CGSize
    let viewport: CGSize?
    struct Cache { var minimum = CGSize.zero; var ideal = CGSize.zero; var maximum = CGSize.zero; var logical = CGSize.zero }
    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let minimum = child.sizeThatFits(.zero)
        func fitting(_ proposed: CGSize?) -> CGSize {
            let logical = proposed.map { CGSize(width: $0.width / factor, height: $0.height / factor) }
                ?? CGSize(width: min(available.width / factor, minimum.width >= 240 ? minimum.width : 760),
                          height: min(available.height / factor, minimum.height >= 240 ? minimum.height : 600))
            let result = child.sizeThatFits(.init(width: logical.width, height: logical.height))
            return CGSize(width: min(available.width, max(0, result.width * factor)), height: min(available.height, max(0, result.height * factor)))
        }
        cache.minimum = fitting(.zero); cache.ideal = fitting(nil); cache.maximum = fitting(available)
        let physical = viewport ?? cache.ideal
        cache.logical = CGSize(width: physical.width / factor, height: physical.height / factor)
        let fitted = child.sizeThatFits(.init(width: cache.logical.width, height: cache.logical.height))
        return CGSize(width: max(physical.width, fitted.width * factor), height: max(physical.height, fitted.height * factor))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: cache.logical.width, height: cache.logical.height))
        for (index, size) in [cache.minimum, cache.ideal, cache.maximum].enumerated() where subviews.count > index + 1 {
            subviews[index + 1].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: size.width, height: size.height))
        }
    }
}
private struct MacPresentationWindowSizing: NSViewRepresentable {
    let factor: CGFloat
    let minimum: CGSize?
    let ideal: CGSize?
    let maximum: CGSize?
    let enabled: Bool
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        view.configuration = self; view.schedule()
    }
    final class Probe: NSView {
        var configuration: MacPresentationWindowSizing?
        private var scheduled = false
        private weak var sizedWindow: NSWindow?
        private var lastIdeal: CGSize?
        private var lastFactor: CGFloat?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); schedule() }
        func schedule() {
            guard !scheduled else { return }; scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }; self.scheduled = false; self.synchronize()
            }
        }
        private func synchronize() {
            guard let c = configuration, let ideal = c.ideal, let minimum = c.minimum, let maximum = c.maximum else { return }
            let previous = lastIdeal, previousFactor = lastFactor
            lastIdeal = ideal; lastFactor = c.factor
            guard c.enabled, let window, let content = window.contentView else { return }
            let first = sizedWindow !== window; sizedWindow = window
            let current = content.bounds.size
            var desired = current
            if first { desired = ideal }
            else if let previousFactor, abs(previousFactor - c.factor) > 0.0001 {
                desired = .init(width: current.width * c.factor / previousFactor, height: current.height * c.factor / previousFactor)
            } else if let previous, abs(current.width - previous.width) < 2, abs(current.height - previous.height) < 2 { desired = ideal }
            desired.width = min(maximum.width, max(minimum.width, desired.width))
            desired.height = min(maximum.height, max(minimum.height, desired.height))
            if abs(current.width - desired.width) > 0.5 || abs(current.height - desired.height) > 0.5 { window.setContentSize(desired) }
        }
    }
}
struct MacZoomPresentation<Content: View>: View {
    @AppStorage("zerus.mac.appearance") private var appearance = "light"
    @AppStorage("zerus.mac.interfaceZoom") private var percentage = 100
    @State private var availableSize = MacPresentationScreen.availableSize(nil)
    var resizesWindow = true
    @ViewBuilder let content: () -> Content
    var body: some View {
        MacPresentationViewport(factor: MacInterfaceZoom.factor(percentage), availableSize: availableSize, resizesWindow: resizesWindow, content: content)
            .background(MacPresentationScreen { availableSize = $0 }.frame(width: 0, height: 0))
            .modifier(MacInterfaceTextHost())
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}
private struct MacPresentationScreen: NSViewRepresentable {
    let changed: (CGSize) -> Void
    static func availableSize(_ screen: NSScreen?, parent: NSWindow? = nil) -> CGSize {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let belowAnchor = parent.map { $0.convertToScreen($0.contentLayoutRect).maxY - visible.minY - 64 } ?? (visible.height - 120)
        return .init(width: max(1, visible.width - 80), height: max(1, min(visible.height - 120, belowAnchor)))
    }
    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed; view.report() }
    final class Probe: NSView {
        var changed: (CGSize) -> Void
        private var observers: [NSObjectProtocol] = []
        private weak var observedWindow: NSWindow?
        private weak var observedParent: NSWindow?
        init(changed: @escaping (CGSize) -> Void) { self.changed = changed; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); bindObservers(); report()
            DispatchQueue.main.async { [weak self] in self?.report() }
        }
        private func bindObservers() {
            guard observedWindow !== window || observedParent !== window?.sheetParent else { return }
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            observedWindow = window; observedParent = window?.sheetParent
            for owner in [observedWindow, observedParent].compactMap({ $0 }) {
                for name in [NSWindow.didChangeScreenNotification, NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: owner, queue: .main) { [weak self] _ in self?.report() })
                }
            }
        }
        func report() {
            bindObservers()
            let size = MacPresentationScreen.availableSize(window?.sheetParent?.screen ?? window?.screen, parent: window?.sheetParent)
            DispatchQueue.main.async { [weak self] in self?.changed(size) }
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

extension View {
    func macPopover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        // AppKit owns the anchored window. Resizing it directly competes with
        // NSPopover's constraint pass and can hide or invalidate its content.
        popover(isPresented: isPresented) { MacZoomPresentation(resizesWindow: false, content: content) }
    }
    func macSheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) { MacZoomPresentation(content: content).presentationSizing(.fitted) }
    }
    func macSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in MacZoomPresentation { content(item) }.presentationSizing(.fitted) }
    }
}
