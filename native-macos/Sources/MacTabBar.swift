import SwiftUI
import AppKit

/// Width rules for the title-bar tab strip. Tabs share the available width
/// between a minimum and maximum; once they reach the minimum the strip
/// scrolls and an overflow chip lists every open tab.
struct MacTabBarMetrics: Equatable {
    static let minimum: CGFloat = 110
    static let maximum: CGFloat = 200
    static let spacing: CGFloat = 4
    static let chip: CGFloat = 58
    let overflowing: Bool
    let strip: CGFloat
    let tab: CGFloat
    let active: CGFloat
    /// `activeIdeal` is the width the active tab needs to show its full title.
    init(available: CGFloat, count: Int, activeIdeal: CGFloat) {
        let available = max(0, available)
        guard count > 0 else { overflowing = false; strip = 0; tab = 0; active = 0; return }
        let active = min(Self.maximum, max(Self.minimum, activeIdeal))
        let others = CGFloat(count - 1), gaps = Self.spacing * others
        overflowing = active + others * Self.minimum + gaps > available
        let strip = overflowing ? max(0, available - Self.chip - 6) : available
        let tab = others == 0 ? active : min(Self.maximum, max(Self.minimum, (strip - active - gaps) / others))
        self.tab = tab
        // With room to spare, the active tab matches the others rather than standing out.
        self.active = max(active, tab)
        self.strip = overflowing ? strip : min(strip, self.active + others * tab + gaps)
    }
}

struct MacTabBar: View {
    let store: MacWorkspace
    /// Width the toolbar can give the strip, in toolbar (unzoomed) points.
    let available: CGFloat
    @Environment(\.macTheme) private var theme
    @State private var visible: Set<MacTab> = []
    @State private var listOpen = false
    @State private var edges = (leading: false, trailing: false)

    var body: some View {
        let tabs = store.tabs
        let metrics = MacTabBarMetrics(available: available, count: tabs.count, activeIdeal: store.activeTab.map(idealWidth) ?? 0)
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MacTabBarMetrics.spacing) {
                        ForEach(tabs) { tab in
                            MacTabButton(store: store, tab: tab, title: title(tab))
                                .frame(width: store.activeTab == tab ? metrics.active : metrics.tab)
                                .id(tab)
                                .onScrollVisibilityChange(threshold: 0.6) { shown in
                                    if shown { visible.insert(tab) } else { visible.remove(tab) }
                                }
                        }
                    }
                }
                .scrollDisabled(!metrics.overflowing)
                .onScrollGeometryChange(for: [Bool].self) { geometry in
                    [geometry.contentOffset.x > 1, geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 1]
                } action: { _, clipped in edges = (clipped[0], clipped[1]) }
                .frame(width: metrics.strip, height: 30)
                .mask(fade(leading: metrics.overflowing && edges.leading, trailing: metrics.overflowing && edges.trailing))
                .onChange(of: store.activeTab) { _, tab in reveal(tab, proxy) }
                .onChange(of: metrics) { _, _ in reveal(store.activeTab, proxy) }
                .onAppear { reveal(store.activeTab, proxy) }
            }
            if metrics.overflowing { overflowChip(hidden: max(0, tabs.count - visible.intersection(tabs).count)) }
        }
        // Fill the reserved width so the trailing toolbar items stay at the window edge.
        .frame(width: max(0, available), alignment: .leading)
        .accessibilityElement(children: .contain).accessibilityLabel("Open tabs")
    }

    private func reveal(_ tab: MacTab?, _ proxy: ScrollViewProxy) {
        guard let tab else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(tab) }
    }
    /// Fade the strip's clipped edges so partly hidden tabs read as scrollable.
    private func fade(leading: Bool, trailing: Bool) -> some View {
        HStack(spacing: 0) {
            if leading { LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 28) }
            Rectangle()
            if trailing { LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28) }
        }
    }
    private func overflowChip(hidden: Int) -> some View {
        Button { listOpen.toggle() } label: {
            HStack(spacing: 3) {
                if hidden > 0 { Text("+\(hidden)").monospacedDigit() }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 11, weight: .medium))
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
        let text = (title(tab) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
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
                    if pinned { Image(systemName: "pin.fill").font(.system(size: 9)).accessibilityLabel("Pinned tab") }
                    if case .folder(let path) = tab { MacFolderLabel(path: title, icon: store.folderIcon(path)) }
                    else { Text(title) }
                    Spacer(minLength: 0)
                }.lineLimit(1).truncationMode(.tail).frame(maxHeight: .infinity)
            }
            // Only reserve room for the close button when it is shown, so
            // narrow inactive tabs keep as much of their title as possible.
            if !pinned && (hovering || active) {
                Button { Task { await store.closeTab(tab) } } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)).frame(width: 16, height: 16)
                        .background(foreground.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 4))
                }
                .opacity(0.6)
                .accessibilityLabel("Close " + title)
            }
        }
        .buttonStyle(MacBoxButtonStyle())
        .font(.system(size: 12, weight: active ? .medium : .regular))
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
        .contextMenu {
            Button(pinned ? "Unpin tab" : "Pin tab") { store.togglePinnedTab(tab) }
            Button("Close tab") { Task { await store.closeTab(tab) } }
            Button("Move tab left") { if let index = store.tabs.firstIndex(of: tab), index > 0 { store.reorderTab(tab, before: store.tabs[index - 1]) } }.disabled(store.tabs.first == tab)
            Button("Move tab right") { if let index = store.tabs.firstIndex(of: tab), index + 1 < store.tabs.count { let next = store.tabs[index + 1]; store.reorderTab(next, before: tab) } }.disabled(store.tabs.last == tab)
        }
        .overlay(MacAlternateOpen(action: { Task { await store.closeTab(tab) } }, handlesTripleClick: false).accessibilityHidden(true))
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
                    if store.pinnedTabs.contains(tab) { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.padding(.vertical, 5).padding(.leading, 6)
            }
            if !store.pinnedTabs.contains(tab) {
                Button { Task { await store.closeTab(tab) } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)).frame(width: 18, height: 18) }
                    .foregroundStyle(.secondary).help("Close tab").accessibilityLabel("Close " + title(tab))
            }
        }
        .buttonStyle(MacBoxButtonStyle()).font(.system(size: 12, weight: active ? .semibold : .regular))
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
