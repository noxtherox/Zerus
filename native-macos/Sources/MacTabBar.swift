import SwiftUI
import AppKit

/// Width rules for the title-bar tab strip. Tabs share the available width
/// between a minimum and maximum; once they reach the minimum, the tabs that
/// no longer fit move into the overflow chip. The strip never scrolls.
struct MacTabBarMetrics: Equatable {
    static let minimum: CGFloat = 110
    static let maximum: CGFloat = 200
    static let spacing: CGFloat = 4
    static let chip: CGFloat = 58
    let overflowing: Bool
    /// Number of tabs drawn in the strip; the rest are listed by the chip.
    let shown: Int
    let strip: CGFloat
    let tab: CGFloat
    let active: CGFloat
    /// `activeIdeal` is the width the active tab needs to show its full title.
    init(available: CGFloat, count: Int, activeIdeal: CGFloat) {
        let available = max(0, available)
        guard count > 0 else { overflowing = false; shown = 0; strip = 0; tab = 0; active = 0; return }
        var active = min(Self.maximum, max(Self.minimum, activeIdeal))
        let others = CGFloat(count - 1)
        overflowing = active + others * (Self.minimum + Self.spacing) > available
        let room = overflowing ? max(0, available - Self.chip - 6) : available
        active = min(active, room)
        let fit = Int(max(0, (room - active) / (Self.minimum + Self.spacing)))
        shown = overflowing ? min(count, 1 + fit) : count
        let rest = CGFloat(shown - 1), gaps = Self.spacing * rest
        var tab = rest == 0 ? active : min(Self.maximum, max(Self.minimum, (room - active - gaps) / rest))
        // With room to spare, the active tab matches the others rather than standing out.
        if tab > active { tab = min(Self.maximum, (room - gaps) / CGFloat(shown)); active = tab }
        self.tab = tab
        self.active = active
        strip = min(room, active + rest * tab + gaps)
    }
    /// The tabs drawn in the strip: leading tabs in order, always including the active one.
    func visible(_ tabs: [MacTab], active: MacTab?) -> [MacTab] {
        var result = Array(tabs.prefix(shown))
        if let active, tabs.contains(active), !result.contains(active), !result.isEmpty { result[result.count - 1] = active }
        return result
    }
}

struct MacTabBar: View {
    let store: MacWorkspace
    /// Width the toolbar can give the strip, in toolbar (unzoomed) points.
    let available: CGFloat
    @Environment(\.macTheme) private var theme
    @Environment(\.macTextScale) private var textScale
    @State private var listOpen = false

    var body: some View {
        let tabs = store.tabs
        let metrics = MacTabBarMetrics(available: available, count: tabs.count, activeIdeal: store.activeTab.map(idealWidth) ?? 0)
        HStack(spacing: 6) {
            HStack(spacing: MacTabBarMetrics.spacing) {
                ForEach(metrics.visible(tabs, active: store.activeTab)) { tab in
                    MacTabButton(store: store, tab: tab, title: title(tab))
                        .frame(width: store.activeTab == tab ? metrics.active : metrics.tab)
                }
            }
            .frame(width: metrics.strip, height: 30, alignment: .leading)
            .clipped()
            if metrics.overflowing { overflowChip(hidden: max(0, tabs.count - metrics.shown)) }
            // The strip fills the title bar between the leading and trailing
            // controls, so its empty part acts as title bar there.
            Color.clear.frame(maxWidth: .infinity).frame(height: 30)
                .overlay(MacTitleBarDoubleClick().accessibilityHidden(true))
        }
        // Fill the reserved width so the trailing toolbar items stay at the window edge.
        .frame(width: max(0, available), alignment: .leading)
        .accessibilityElement(children: .contain).accessibilityLabel("Open tabs")
    }

    private func overflowChip(hidden: Int) -> some View {
        Button { listOpen.toggle() } label: {
            HStack(spacing: 3) {
                if hidden > 0 { Text("+\(hidden)").monospacedDigit() }
                Image(systemName: "chevron.down").macFont(.system(size: 8, weight: .semibold))
            }
            .macFont(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.color(.sidebarFg).opacity(0.85))
            .frame(width: MacTabBarMetrics.chip - 14, height: 22)
            .background(theme.color(.sidebarFg).opacity(listOpen ? 0.16 : 0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(MacBoxButtonStyle())
        .frame(width: MacTabBarMetrics.chip - 6)
        .help("Show all open tabs")
        .accessibilityLabel(hidden > 0 ? "\(hidden) more tabs" : "All tabs")
        .popover(isPresented: $listOpen, arrowEdge: .bottom) {
            MacTabList(store: store, title: title) { listOpen = false }
        }
    }
    private func title(_ tab: MacTab) -> String { MacTabBar.title(tab, in: store) }
    static func title(_ tab: MacTab, in store: MacWorkspace) -> String {
        tab.notePath.flatMap { path in store.notes.first { $0.path == path }?.title ?? (store.current?.path == path ? store.current?.title : nil) } ?? tab.target
    }
    private func idealWidth(_ tab: MacTab) -> CGFloat {
        let text = (title(tab) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12 * textScale)]).width
        let icon: CGFloat = store.pinnedTabs.contains(tab) || { if case .folder = tab { return true }; return false }() ? 20 : 0
        return ceil(text) + icon + 46
    }
}

private struct MacTabButton: View {
    let store: MacWorkspace
    let tab: MacTab
    let title: String
    @Environment(\.macTheme) private var theme
    @State private var hovering = false
    var body: some View {
        let active = store.activeTab == tab, pinned = store.pinnedTabs.contains(tab)
        let foreground = theme.color(.sidebarFg)
        HStack(spacing: 4) {
            Button { Task { await store.activateTab(tab) } } label: {
                HStack(spacing: 6) {
                    if pinned { Image(systemName: "pin.fill").macFont(.system(size: 9)).accessibilityLabel("Pinned tab") }
                    if case .folder(let path) = tab { MacFolderLabel(path: title, icon: store.folderIcon(path)) }
                    else { Text(title) }
                    Spacer(minLength: 0)
                }.lineLimit(1).truncationMode(.tail).frame(maxHeight: .infinity)
            }
            // Only reserve room for the close button when it is shown, so
            // narrow inactive tabs keep as much of their title as possible.
            if !pinned && (hovering || active) {
                Button { Task { await store.closeTab(tab) } } label: {
                    Image(systemName: "xmark").macFont(.system(size: 8, weight: .semibold)).frame(width: 16, height: 16)
                        .background(foreground.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 4))
                }
                .opacity(0.6)
                .accessibilityLabel("Close " + title)
            }
        }
        .buttonStyle(MacBoxButtonStyle())
        .macFont(.system(size: 12, weight: active ? .medium : .regular))
        .foregroundStyle(foreground.opacity(active ? 0.95 : 0.6))
        .padding(.leading, 10).padding(.trailing, !pinned && (hovering || active) ? 5 : 10)
        .frame(height: 26)
        .background(foreground.opacity(active ? 0.11 : hovering ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(title)
        .draggable(tab.id)
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, let source = store.tabs.first(where: { $0.id == value }) else { return false }
            store.reorderTab(source, before: tab); return true
        }
        .overlay(MacAlternateOpen(action: { Task { await store.closeTab(tab) } }, handlesTripleClick: false).accessibilityHidden(true))
        // The strip is hosted in the window toolbar, where NSToolbar claims
        // right-clicks before SwiftUI's `.contextMenu` sees them.
        .overlay(MacTabContextMenu(items: menuItems).accessibilityHidden(true))
        .accessibilityAction(named: pinned ? "Unpin tab" : "Pin tab") { store.togglePinnedTab(tab) }
    }
    private func menuItems() -> [MacTabContextMenu.Item] {
        let pinned = store.pinnedTabs.contains(tab), tabs = store.tabs
        return [
            .init(title: pinned ? "Unpin Tab" : "Pin Tab") { store.togglePinnedTab(tab) },
            .init(title: "Close Tab", enabled: !pinned) { Task { await store.closeTab(tab) } },
            .separator,
            .init(title: "Move Tab Left", enabled: tabs.first != tab) {
                if let index = store.tabs.firstIndex(of: tab), index > 0 { store.reorderTab(tab, before: store.tabs[index - 1]) }
            },
            .init(title: "Move Tab Right", enabled: tabs.last != tab) {
                if let index = store.tabs.firstIndex(of: tab), index + 1 < store.tabs.count { store.reorderTab(store.tabs[index + 1], before: tab) }
            },
        ]
    }
}

/// Double-clicking empty title-bar space performs the system's title-bar
/// action (Desktop & Dock › "Double-click a window's title bar to"). Only
/// double-clicks are claimed, so single clicks still drag the window.
struct MacTitleBarDoubleClick: NSViewRepresentable {
    func makeNSView(context: Context) -> ClickView { ClickView() }
    func updateNSView(_ view: ClickView, context: Context) {}
    final class ClickView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard super.hitTest(point) != nil, let event = NSApp.currentEvent,
                  event.type == .leftMouseDown, event.clickCount == 2 else { return nil }
            return self
        }
        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2 else { return }
            MacTitleBarDoubleClick.perform(in: window)
        }
    }
    /// Performs the action chosen in Desktop & Dock for title-bar double-clicks.
    static func perform(in window: NSWindow?) {
        guard let window else { return }
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "AppleActionOnDoubleClick") {
        case "None": return
        case "Minimize": window.performMiniaturize(nil)
        case nil where defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick"): window.performMiniaturize(nil)
        default: window.performZoom(nil)
        }
    }
}

/// AppKit context menu for views placed in the window toolbar. Only
/// right-clicks and Control-clicks are claimed; other events pass through.
private struct MacTabContextMenu: NSViewRepresentable {
    struct Item {
        var title = ""
        var enabled = true
        var action: (() -> Void)?
        static let separator = Item()
        init(title: String, enabled: Bool = true, action: @escaping () -> Void) { self.title = title; self.enabled = enabled; self.action = action }
        private init() {}
    }
    let items: () -> [Item]
    func makeNSView(context: Context) -> MenuView { let view = MenuView(); view.items = items; return view }
    func updateNSView(_ view: MenuView, context: Context) { view.items = items }
    final class MenuView: NSView {
        var items: (() -> [Item])?
        private var actions: [() -> Void] = []
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard super.hitTest(point) != nil, let event = NSApp.currentEvent else { return nil }
            if event.type == .rightMouseDown || event.type == .leftMouseDown && event.modifierFlags.contains(.control) { return self }
            return nil
        }
        override func rightMouseDown(with event: NSEvent) { show(event) }
        override func mouseDown(with event: NSEvent) { if event.modifierFlags.contains(.control) { show(event) } }
        private func show(_ event: NSEvent) {
            let menu = NSMenu(); menu.autoenablesItems = false; actions = []
            for item in items?() ?? [] {
                guard let action = item.action else { menu.addItem(.separator()); continue }
                let entry = NSMenuItem(title: item.title, action: #selector(fire(_:)), keyEquivalent: "")
                entry.target = self; entry.isEnabled = item.enabled; entry.tag = actions.count
                actions.append(action); menu.addItem(entry)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
        @objc private func fire(_ sender: NSMenuItem) { if actions.indices.contains(sender.tag) { actions[sender.tag]() } }
    }
}

/// Every open tab, filterable, for when the strip cannot show them all.
private struct MacTabList: View {
    let store: MacWorkspace
    let title: (MacTab) -> String
    let dismiss: () -> Void
    @State private var filter = ""
    @FocusState private var focused: Bool
    var body: some View {
        let query = filter.trimmingCharacters(in: .whitespaces)
        let matches = store.tabs.filter { query.isEmpty || title($0).localizedCaseInsensitiveContains(query) }
        VStack(alignment: .leading, spacing: 6) {
            TextField("Filter open tabs", text: $filter).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { if let first = matches.first { open(first) } }
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(matches) { tab in row(tab) }
                    if matches.isEmpty { Text("No matching tabs").foregroundStyle(.secondary).padding(8) }
                }
            }.frame(maxHeight: 360).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8).frame(width: 340)
        .onAppear { focused = true }
    }
    private func row(_ tab: MacTab) -> some View {
        let active = store.activeTab == tab
        return HStack(spacing: 6) {
            Button { open(tab) } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon(tab)).frame(width: 14).foregroundStyle(.secondary)
                    Text(title(tab)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if store.pinnedTabs.contains(tab) { Image(systemName: "pin.fill").macFont(.system(size: 9)).foregroundStyle(.secondary) }
                }.padding(.vertical, 5).padding(.leading, 6)
            }
            if !store.pinnedTabs.contains(tab) {
                Button { Task { await store.closeTab(tab) } } label: { Image(systemName: "xmark").macFont(.system(size: 8, weight: .semibold)).frame(width: 18, height: 18) }
                    .foregroundStyle(.secondary).help("Close tab").accessibilityLabel("Close " + title(tab))
            }
        }
        .buttonStyle(MacBoxButtonStyle()).macFont(.system(size: 12, weight: active ? .semibold : .regular))
        .padding(.trailing, 4)
        .background(active ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
    private func icon(_ tab: MacTab) -> String {
        switch tab { case .note: "doc.text"; case .folder: "folder"; case .collection: "tray.full" }
    }
    private func open(_ tab: MacTab) { dismiss(); Task { await store.activateTab(tab) } }
}

extension MacWorkspace {
    /// Tab navigation shared by the menu commands.
    func selectTab(at index: Int) async {
        guard !tabs.isEmpty else { return }
        await activateTab(tabs[min(max(0, index), tabs.count - 1)])
    }
    func cycleTab(by step: Int) async {
        guard !tabs.isEmpty else { return }
        let current = activeTab.flatMap { tabs.firstIndex(of: $0) } ?? 0
        await activateTab(tabs[(current + step + tabs.count) % tabs.count])
    }
}
