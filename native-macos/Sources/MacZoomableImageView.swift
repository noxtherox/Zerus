import AppKit
import SwiftUI

/// Zoom state shared between the image scroll view and its toolbar.
@MainActor
final class MacImageZoomModel: ObservableObject {
    static let minimum: CGFloat = 0.1, maximum: CGFloat = 8
    @Published fileprivate(set) var magnification: CGFloat = 1
    fileprivate weak var scrollView: NSScrollView?

    func zoom(by factor: CGFloat) { set((scrollView?.magnification ?? magnification) * factor) }
    func actualSize() { set(1) }
    func fit() {
        guard let scrollView, let document = scrollView.documentView, document.bounds.width > 0, document.bounds.height > 0 else { return }
        let visible = scrollView.contentSize
        let scale = min(visible.width / document.bounds.width, visible.height / document.bounds.height, 1)
        set(scale)
    }
    private func set(_ value: CGFloat) {
        guard let scrollView else { return }
        let clamped = min(max(value, Self.minimum), Self.maximum)
        let center = NSPoint(x: scrollView.documentVisibleRect.midX, y: scrollView.documentVisibleRect.midY)
        scrollView.setMagnification(clamped, centeredAt: center)
        magnification = clamped
    }
    fileprivate func sync() { if let value = scrollView?.magnification, value != magnification { magnification = value } }
}

/// Centers the document when it is smaller than the visible area.
private final class MacCenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        return rect
    }
}

/// Scroll view that zooms around the pointer on ⌘-scroll.
private final class MacZoomScrollView: NSScrollView {
    var onMagnify: (() -> Void)?
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let document = documentView else { return super.scrollWheel(with: event) }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 200 : event.scrollingDeltaY / 20
        let value = min(max(magnification * (1 + delta), minMagnification), maxMagnification)
        setMagnification(value, centeredAt: document.convert(event.locationInWindow, from: nil))
        onMagnify?()
    }
}

/// Image view that supports pinch, ⌘-scroll and double-click zoom plus panning.
struct MacZoomableImage: NSViewRepresentable {
    let image: NSImage
    @ObservedObject var model: MacImageZoomModel

    final class Coordinator: NSObject {
        let model: MacImageZoomModel
        var fitted = false
        init(model: MacImageZoomModel) { self.model = model }
        @MainActor @objc func magnified() { model.sync() }
        @MainActor @objc func toggle(_ gesture: NSClickGestureRecognizer) {
            guard let scrollView = model.scrollView else { return }
            if scrollView.magnification < 1.5 {
                let point = gesture.location(in: scrollView.documentView)
                scrollView.setMagnification(min(max(scrollView.magnification * 2.5, 2), MacImageZoomModel.maximum), centeredAt: point)
                model.sync()
            } else { model.fit() }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MacZoomScrollView()
        scrollView.onMagnify = { [weak model] in model?.sync() }
        scrollView.contentView = MacCenteringClipView()
        scrollView.hasVerticalScroller = true; scrollView.hasHorizontalScroller = true; scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false; scrollView.borderType = .noBorder
        scrollView.allowsMagnification = true
        scrollView.minMagnification = MacImageZoomModel.minimum; scrollView.maxMagnification = MacImageZoomModel.maximum
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = NSRect(origin: .zero, size: pixelSize(image))
        scrollView.documentView = imageView
        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.toggle(_:)))
        doubleClick.numberOfClicksRequired = 2
        imageView.addGestureRecognizer(doubleClick)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.magnified), name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
        model.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        model.scrollView = scrollView
        guard !context.coordinator.fitted, scrollView.contentSize.width > 0 else { return }
        context.coordinator.fitted = true
        DispatchQueue.main.async { model.fit() }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    /// Uses the bitmap's pixel size (at 2x density) so screenshots keep their detail when zoomed.
    private func pixelSize(_ image: NSImage) -> NSSize {
        let pixels = image.representations.reduce(NSSize.zero) { best, rep in
            rep.pixelsWide * rep.pixelsHigh > Int(best.width * best.height) ? NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) : best
        }
        guard pixels.width > 0, pixels.height > 0 else { return image.size }
        return NSSize(width: max(image.size.width, pixels.width / 2), height: max(image.size.height, pixels.height / 2))
    }
}

/// Expanded image preview with zoom controls.
struct MacImagePreviewPanel: View {
    let image: NSImage
    let done: () -> Void
    @StateObject private var zoom = MacImageZoomModel()

    var body: some View {
        VStack(spacing: 0) {
            MacZoomableImage(image: image, model: zoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            HStack(spacing: 8) {
                Button { zoom.zoom(by: 1 / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .keyboardShortcut("-", modifiers: .command).help("Zoom out (⌘−)")
                Text("\(Int((zoom.magnification * 100).rounded()))%").monospacedDigit().frame(minWidth: 44)
                Button { zoom.zoom(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .keyboardShortcut("=", modifiers: .command).help("Zoom in (⌘+)")
                Button("Fit") { zoom.fit() }.keyboardShortcut("9", modifiers: .command).help("Fit to window (⌘9)")
                Button("Actual Size") { zoom.actualSize() }.keyboardShortcut("0", modifiers: .command).help("Actual size (⌘0)")
                Text("Pinch, ⌘-scroll or double-click to zoom").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Done", action: done).keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}
