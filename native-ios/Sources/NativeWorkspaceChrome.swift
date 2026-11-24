import SwiftUI

/// The drawer and bottom navigation belong to the workspace, never to a sheet
/// or an editor. Only the main content scroll views opt into this callback.
private struct NativeWorkspaceScrollKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

private struct NativeWorkspaceChromeVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var nativeWorkspaceChromeVisible: Bool {
        get { self[NativeWorkspaceChromeVisibleKey.self] }
        set { self[NativeWorkspaceChromeVisibleKey.self] = newValue }
    }

    var nativeWorkspaceNavigationVisible: (Bool) -> Void {
        get { self[NativeWorkspaceScrollKey.self] }
        set { self[NativeWorkspaceScrollKey.self] = newValue }
    }
}

extension View {
    func nativeWorkspaceScroll() -> some View { modifier(NativeWorkspaceScroll()) }
}

private struct NativeWorkspaceScroll: ViewModifier {
    @Environment(\.nativeWorkspaceNavigationVisible) private var setVisible
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    // Gesture bookkeeping must not invalidate the view on every scroll frame.
    @State private var tracking = NativeWorkspaceScrollTracking()

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                tracking.scrolling = phase == .interacting || phase == .decelerating
                if phase == .interacting || phase == .idle { tracking.distance = 0 }
            }
            .onScrollGeometryChange(for: NativeWorkspaceScrollMetrics.self) { geometry in
                // Clamp rubber-banding so a bounce at either edge cannot flip
                // the direction. Geometry changes while idle are ignored.
                let end = max(0, geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom - geometry.containerSize.height)
                return NativeWorkspaceScrollMetrics(
                    offset: min(end, max(0, geometry.contentOffset.y + geometry.contentInsets.top)),
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height,
                    topInset: geometry.contentInsets.top,
                    bottomInset: geometry.contentInsets.bottom
                )
            } action: { old, new in
                // Content updates, keyboard changes and streaming replies
                // must not count as a change in scroll direction.
                guard old.contentHeight == new.contentHeight,
                      old.containerHeight == new.containerHeight,
                      old.topInset == new.topInset,
                      old.bottomInset == new.bottomInset else { tracking.distance = 0; return }
                // Check the top only after rejecting navigation layout changes.
                if new.offset < 8 { tracking.distance = 0; setVisible(true); return }
                guard tracking.scrolling, !voiceOver else { return }
                let delta = new.offset - old.offset
                if (delta > 0 && tracking.distance < 0) || (delta < 0 && tracking.distance > 0) { tracking.distance = 0 }
                tracking.distance += delta
                if tracking.distance > 28 { setVisible(false); tracking.distance = 0 }
                else if tracking.distance < -16 { setVisible(true); tracking.distance = 0 }
            }
    }
}

private final class NativeWorkspaceScrollTracking {
    var scrolling = false
    var distance: CGFloat = 0
}

private struct NativeWorkspaceScrollMetrics: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
}

struct NativeWorkspaceDrawer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var translation: CGFloat = 0
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, min(360, geometry.size.width - 64))
            let offset = min(width, max(0, (isOpen ? width : 0) + translation))
            let progress = width > 0 ? offset / width : 0
            ZStack(alignment: .leading) {
                Accent.sidebar.ignoresSafeArea()
                sidebar()
                    .frame(width: width)
                    .offset(x: -width * 0.18 * (1 - progress))
                    .opacity(progress == 0 ? 0 : 1)
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(!isOpen)
                    .allowsHitTesting(isOpen)
                    .accessibilityIdentifier("workspace.drawer")
                    .simultaneousGesture(drawerGesture(width: width, opening: false))
                content()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Accent.paper)
                    .clipShape(.rect(cornerRadius: 24 * progress))
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(isOpen)
                    .disabled(isOpen)
                    .overlay {
                        if isOpen {
                            Button { isOpen = false } label: {
                                Color.black.opacity(0.24 * progress).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close folders")
                            .accessibilityIdentifier("workspace.drawer.dismiss")
                            .simultaneousGesture(drawerGesture(width: width, opening: false))
                        }
                    }
                    .shadow(color: .black.opacity(isOpen ? 0.18 : 0), radius: 16, x: -4)
                    .offset(x: offset)
                if !isOpen {
                    // Reserve only the edge, preserving list swipes and other
                    // horizontal gestures throughout the rest of the screen.
                    Color.clear.frame(width: 20)
                        .contentShape(Rectangle())
                        .gesture(drawerGesture(width: width, opening: true))
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: isOpen)
            .accessibilityAction(.escape) { isOpen = false }
        }
    }

    private func drawerGesture(width: CGFloat, opening: Bool) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .updating($translation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = opening ? max(0, value.translation.width) : min(0, value.translation.width)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let travel = value.predictedEndTranslation.width
                if opening { isOpen = travel > width * 0.3 }
                else { isOpen = travel > -width * 0.3 }
            }
    }
}
