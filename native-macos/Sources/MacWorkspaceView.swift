import SwiftUI
import AppKit
import PDFKit
import WebKit

struct MacWorkspaceView: View {
    @Environment(\.macTheme) private var theme
    private var macAccent: Color { theme.color(.accent) }
    private var sidebarSurface: Color { theme.color(.sidebarBg) }
    @Bindable var store: MacWorkspace
    @AppStorage("zerus.mac.dateFormat") private var dateFormat = "DD/MM/YYYY"
    @AppStorage("zerus.mac.codeBlocks") private var codeBlocks = false
    @AppStorage("zerus.mac.interfaceZoom") private var interfaceZoom = 100
    /// In full screen the traffic lights leave the title bar, so it needs no
    /// room for them.
    @State private var fullScreen = false
    @StateObject private var editorSessions = MacEditorSessions()
    @State private var clipboardBusy = false
    @State private var showAllRecents = false
    @State private var vaultIconRequest: MacVaultIconRequest?
    @State private var managingVaults = false
    @State private var attachmentImporting = false
    @State private var sidebar = true
    /// Hides the library, list and inspector so the open note fills the window.
    @State private var focusMode = false
    @State private var compactLibrary = false
    @State private var compactInspector = false
    @State private var filtersOpen = false
    @State private var prompt: MacPrompt?
    @State private var input = ""
    @State private var secondInput = ""
    @State private var typedProperty: MacPropertyEdit?
    @State private var relationName: String?
    @State private var relationRemoval: MacRelationRemoval?
    @State private var schemaOwner: String?
    @State private var propertyName = ""
    @State private var propertyValue = ""
    @State private var filePreview: URL?
    @State private var fileLocations = false
    @State private var images = false
    @State private var fileHubRequest: MacFileHubRequest?
    @State private var hubInitialSource: URL?
    @State private var taskEditor: NativeTask?
    @State private var tableRequest: MacTableRequest?
    @State private var codeRequest: MacCodeRequest?
    @State private var folderRequest: MacFolderRequest?
    @State private var folderIconRequest: MacFolderIconRequest?
    @State private var trashBrowser = false
    @State private var emptyTrashPlan: NativeNoteTrashPlan?
    @State private var bulkProperties = false
    @State private var bulkMove = false
    @State private var bulkHistory = false
    @State private var recoveryRequest: MacRecoveryRequest?
    @State private var settings = false
    @State private var newNoteSheet = false
    @State private var exportRequest: MacExportRequest?
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        GeometryReader { geometry in
            let standalone = store.root == nil || ((store.destination == "Tasks" || store.destination == "External Notes") && !store.folderCollection)
            let layout = MacWorkspaceArrangement(width: geometry.size.width, sidebar: sidebar && !focusMode, inspector: store.inspector && !focusMode, hasNote: store.selection != nil, list: store.viewMode == "List" && !focusMode, browsing: store.browsingCollection && !focusMode, standalone: standalone)
            VStack(spacing: 0) {
            titleBar(layout, standalone: standalone)
            Divider()
            ZStack {
                VStack(spacing: 0) {
                    if store.usingStartupCache {
                        HStack(spacing: 8) {
                            if store.startupRefreshing { ProgressView().controlSize(.small) }
                            Text(store.startupIssue == nil ? "Showing cached notes · Checking vault…" : "Showing cached notes · Could not refresh")
                            Spacer()
                            if !store.startupRefreshing { Button("Retry") { Task { await store.refresh() } } }
                        }.macFont(.caption).padding(.horizontal, 12).padding(.vertical, 7).background(.quaternary.opacity(0.3)).help(store.startupIssue ?? "Saved files are being checked. Your edits keep their normal conflict protection.")
                    }
                    workspaceContent(layout)
                }.accessibilityHidden(compactLibrary || compactInspector).environment(\.macEditorInteractionEnabled, !compactLibrary && !compactInspector && !store.busy).disabled(compactLibrary || compactInspector || store.busy)
                if compactLibrary || compactInspector {
                    Color.black.opacity(0.14).onTapGesture { compactLibrary = false; compactInspector = false }
                    HStack(spacing: 0) {
                        if compactInspector { Spacer(minLength: 0) }
                        VStack(spacing: 0) {
                            HStack { Text(compactLibrary ? "Library" : "Inspector").macFont(.headline); Spacer(); Button("Done") { compactLibrary = false; compactInspector = false }.keyboardShortcut(.cancelAction) }.padding(14)
                            Divider()
                            Group { if compactLibrary { sidebarView } else { inspectorView } }.disabled(store.busy)
                        }.frame(width: min(compactLibrary ? 280 : 320, geometry.size.width)).frame(maxHeight: .infinity).background(theme.color(.surface)).shadow(radius: 10)
                        if compactLibrary { Spacer(minLength: 0) }
                    }
                }
            }
            }
            .onChange(of: store.inspectorRequest) { _, _ in toggleInspector(layout) }
            .onChange(of: layout.canInlineSidebar) { _, inline in if inline { compactLibrary = false } }
            .onChange(of: layout.canInlineInspector) { _, inline in if inline { compactInspector = false } }
        }
        .tint(macAccent)
        .foregroundStyle(theme.color(.text))
        .onChange(of: store.activeTab) { _, _ in compactLibrary = false; compactInspector = false }
        .onChange(of: store.browsingCollection) { _, _ in compactLibrary = false; compactInspector = false }
        .onChange(of: store.selection) { _, path in clipboardBusy = false; if path == nil { compactInspector = false } }
        .onChange(of: store.workspaceID) { _, _ in compactLibrary = false; compactInspector = false; clipboardBusy = false; editorSessions.retain(scope: store.workspaceID, paths: Set(store.tabs.compactMap(\.notePath))) }
        .onChange(of: store.tabs, initial: true) { _, tabs in editorSessions.retain(scope: store.workspaceID, paths: Set(tabs.compactMap(\.notePath))) }
        .onDisappear { editorSessions.removeAll() }
        // Presentation changes may cancel this view task after restoration.
        // An accepted OS file event must finish independently of that lifetime.
        .task { MacDesktopFileEvents.deliver(to: store); await store.restore(); Task { await store.desktopFiles.drain(in: store) } }
        .onOpenURL { url in store.desktopFiles.enqueue(url); Task { await store.desktopFiles.drain(in: store) } }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onChange(of: store.busy) { _, busy in if !busy { Task { await store.desktopFiles.drain(in: store) } } }
        .onChange(of: store.editorSheetActive) { _, active in if !active { Task { await store.desktopFiles.drain(in: store) } } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in Task { await store.desktopFiles.drain(in: store) } }
        .modifier(MacVaultRefresh(store: store))
        .modifier(MacLocalAIWorkspace(store: store))
        .onChange(of: store.root) { _, _ in managingVaults = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await store.refresh() } }
        .alert("Zerus", isPresented: Binding(get: { store.issue != nil }, set: { if !$0 { store.issue = nil } })) { Button("OK") { store.issue = nil } } message: { Text(store.issue ?? "") }
        .macSheet(item: $prompt) { item in promptView(item) }
        .macSheet(isPresented: $store.showNoteRecovery) { MacNoteRecoveryView(workspace: store) }
        .macSheet(isPresented: $store.showSearch) { MacSearchView(workspace: store) }
        .macSheet(item: $store.missingNoteLink) { request in MacMissingNoteLinkView(workspace: store, request: request) }
        .macSheet(isPresented: $store.showChat) { MacChatView(store: store) }
        .macSheet(isPresented: $settings) { MacSettingsView(workspace: store) }
        .macSheet(isPresented: $newNoteSheet) { MacNewNoteSheet(workspace: store) }
        .macSheet(item: $exportRequest, onDismiss: { store.editorSheetActive = false; DispatchQueue.main.async { sendEditor("focus") } }) { request in MacNoteExportView(request: request) }
        .macSheet(item: $store.settingsImport, onDismiss: { store.editorSheetActive = false; DispatchQueue.main.async { sendEditor("focus") } }) { review in MacDesktopSettingsImportView(review: review) }
        .macSheet(item: $store.printRequest, onDismiss: { store.editorSheetActive = false; DispatchQueue.main.async { sendEditor("focus") } }) { request in MacNotePrintView(request: request) }
        .macSheet(isPresented: $bulkMove) { MacNoteMovesView(workspace: store, paths: store.selectedPaths) }
        .macSheet(isPresented: $bulkProperties) { MacBulkEditor(store: store, paths: store.selectedPaths) }
        .macSheet(isPresented: $bulkHistory) { MacBulkHistoryView(store: store) }
        .macSheet(item: $recoveryRequest) { MacRecoveryView(workspace: store, request: $0) }
        .macSheet(item: $vaultIconRequest) { request in MacVaultIconPicker(workspace: store, request: request) }

        .macSheet(item: $folderIconRequest, onDismiss: { store.editorSheetActive = false }) { request in MacFolderIconPicker(workspace: store, request: request) }
        .macSheet(item: $folderRequest) { request in MacFolderReview(store: store, request: request) }
        .macSheet(isPresented: $images) { MacImagesView(workspace: store, notePath: store.selection) }
        .macSheet(isPresented: $trashBrowser) { MacTrashBrowser(store: store) }
        .macSheet(item: $tableRequest, onDismiss: { store.editorSheetActive = false; DispatchQueue.main.async { sendEditor("focus") } }) { request in MacTableEditor(request: request) { replacement in try applyTable(request, replacement: replacement) } }
        .macSheet(item: $codeRequest, onDismiss: { store.editorSheetActive = false; DispatchQueue.main.async { sendEditor("focus") } }) { request in MacCodeEditor(request: request) { replacement in try applyCode(request, replacement: replacement) } }
        .macSheet(item: $typedProperty) { edit in MacPropertyEditor(store: store, edit: edit) }
        .macSheet(isPresented: Binding(get: { relationName != nil }, set: { if !$0 { relationName = nil } })) { if let name = relationName { MacRelationEditor(store: store, name: name) } }
        .macSheet(isPresented: Binding(get: { schemaOwner != nil }, set: { if !$0 { schemaOwner = nil } })) { if let owner = schemaOwner { MacSchemaEditor(store: store, owner: owner) } }
        .macSheet(isPresented: $fileLocations) { MacFileLocationsView(workspace: store) }
        .macSheet(item: $fileHubRequest) { request in MacFileHubEditor(workspace: store, request: request, initialSource: hubInitialSource) { note in Task { await store.openNote(note.path) } } }
        .macSheet(item: $store.previewDocument) { lease in MacLeasedPreview(lease: lease) }
        .macSheet(item: $filePreview) { url in MacFilePreview(url: url).frame(minWidth: 800, minHeight: 650) }
        .focusedSceneValue(\.macWorkspace, store)
    }
    @ViewBuilder private func workspaceContent(_ layout: MacWorkspaceArrangement) -> some View {
        if store.root == nil || managingVaults {
            MacZoomSplitView { if layout.sidebar { sidebarView.frame(minWidth: 185, idealWidth: 218, maxWidth: 240) }; welcome.frame(maxWidth: .infinity, maxHeight: .infinity) }
        } else if store.destination == "External Notes" && !store.folderCollection {
            MacZoomSplitView { if layout.sidebar { sidebarView.frame(minWidth: 185, idealWidth: 218, maxWidth: 240) }; MacExternalNotesView(workspace: store).frame(maxWidth: .infinity) }
        } else if store.destination == "Tasks" && !store.folderCollection {
            MacZoomSplitView { if layout.sidebar { sidebarView.frame(minWidth: 185, idealWidth: 218, maxWidth: 240) }; MacTasksView(store: store).frame(maxWidth: .infinity) }
        } else {
            MacWorkspacePanes(layout: layout, interactionEnabled: !compactLibrary && !compactInspector && !store.busy, library: sidebarView, collection: collectionView, editor: editorView, inspector: inspectorView)
        }
    }
    /// The window's title bar, drawn by the app like Firefox's or Outlook's
    /// rather than as a system toolbar: one row in which the tabs take
    /// whatever width the buttons leave, so narrowing the window narrows the
    /// tabs and the buttons stay pinned to the right edge. Empty space drags
    /// the window, and double-clicking it performs the system title-bar
    /// action.
    @ViewBuilder private func titleBar(_ layout: MacWorkspaceArrangement, standalone: Bool) -> some View {
        let factor = MacInterfaceZoom.factor(interfaceZoom)
        HStack(spacing: 8) {
            // Room for the traffic lights, which keep their size at any zoom.
            Color.clear.frame(width: fullScreen ? 0 : 78 / factor, height: 1)
            Button {
                if focusMode { focusMode = false; sidebar = true }
                else if layout.sidebar { sidebar = false }
                else if layout.canInlineSidebar { sidebar = true }
                else { compactInspector = false; compactLibrary.toggle() }
            } label: { Image(systemName: "sidebar.left") }.disabled(store.busy).help("Show or hide folders")
            if store.root != nil {
                MacTitleBarCapsule {
                    Button { Task { await store.historyStep(-1) } } label: { Image(systemName: "chevron.left") }.disabled(!store.canHistoryStep(-1) || store.busy).help("Back")
                    Button { Task { await store.historyStep(1) } } label: { Image(systemName: "chevron.right") }.disabled(!store.canHistoryStep(1) || store.busy).help("Forward")
                }
            }
            // GeometryReader pins its content to the top; centre the 30-point
            // strip in the row so the tabs line up with the 36-point capsules.
            GeometryReader { proxy in
                MacTabBar(store: store, available: proxy.size.width)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            }
            .frame(height: 36)
            trailingControls(layout, standalone: standalone)
        }
        .buttonStyle(MacTitleBarButtonStyle())
        .padding(.trailing, 10)
        .padding(.leading, 8)
        // A system title bar with a toolbar is 52 points tall; the bar grows
        // with larger zoom so its controls keep their margins, and the
        // traffic lights stay centred in it (see `MacTrafficLights`).
        .frame(height: MacTrafficLights.height(zoom: factor) / factor)
        .background {
            Color.clear.contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .simultaneousGesture(TapGesture(count: 2).onEnded { MacTitleBarDoubleClick.perform(in: NSApp.keyWindow) })
        }
        .background(MacTrafficLights(height: MacTrafficLights.height(zoom: factor), fullScreen: $fullScreen))
    }
    @ViewBuilder private func trailingControls(_ layout: MacWorkspaceArrangement, standalone: Bool) -> some View {
        let browseToggle = !standalone && (layout.singleColumn || store.viewMode != "List") && store.selection != nil
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if browseToggle || store.busy {
                    MacTitleBarCapsule {
                        if browseToggle {
                            Button { store.browsingCollection.toggle() } label: {
                                Label(store.browsingCollection ? "Back to note" : "Notes", systemImage: store.browsingCollection ? "doc.text" : "list.bullet").labelStyle(.iconOnly)
                            }.disabled(clipboardBusy || store.busy).help(store.browsingCollection ? "Return to the selected note" : "Browse notes")
                        }
                        if store.busy { ProgressView().controlSize(.small).frame(width: 34) }
                    }
                }
                MacTitleBarCapsule {
                    Button { newNoteSheet = true } label: { Image(systemName: "square.and.pencil") }.disabled(store.root == nil || store.busy).help("New note…")
                }
                MacTitleBarCapsule {
                    Button { store.showSearch = true } label: { Image(systemName: "magnifyingglass") }.disabled(store.busy).help("Search everything (⌘F)")
                    if CloudAIFeature.enabled {
                        Button { store.showChat = true } label: { Label("AI", systemImage: "sparkles").labelStyle(.titleAndIcon).padding(.horizontal, 6) }.foregroundStyle(macAccent).disabled(store.root == nil || store.busy).help("AI chat")
                    } else {
                        MacLocalAIMenu(store: store, settings: $settings)
                    }
                    if let note = store.current {
                        Menu { noteActions(note).labelStyle(.titleAndIcon) } label: { Image(systemName: "ellipsis") }.menuIndicator(.hidden).disabled(store.busy).help("Note actions").accessibilityLabel("Note actions")
                    }
                }
                MacTitleBarCapsule {
                    Button { toggleInspector(layout) } label: { Image(systemName: "sidebar.right") }.disabled(store.selection == nil || store.busy).help("Show or hide inspector")
                }
            }
        }
        .buttonStyle(MacTitleBarButtonStyle())
        .menuStyle(.button)
    }
    private func toggleInspector(_ layout: MacWorkspaceArrangement) {
        guard !store.busy, store.selection != nil else { return }
        if focusMode { focusMode = false; store.inspector = true; return }
        if layout.canInlineInspector { compactInspector = false; store.inspector.toggle() }
        else { compactLibrary = false; compactInspector.toggle() }
    }
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Button("Open Vault…") { store.chooseVault() }
                Button("Note recovery drafts…") { store.showNoteRecovery = true }.disabled(store.root == nil)
                Button("Change Vault Icon…") { if let root = store.root { vaultIconRequest = .init(path: root.path) } }.disabled(store.root == nil)
                Button("Manage Vaults…") { showAllRecents = true; managingVaults = true }.disabled(store.root == nil || managingVaults)
                Divider()
                ForEach(store.recentVaults.filter { $0 != store.root?.path }, id: \.self) { path in
                    Button(MacRecentVaults.menuTitle(path, among: store.recentVaults)) { Task { await store.openRecentVault(path) } }
                }
            } label: { Label(store.vaultTitle, systemImage: "books.vertical.fill").macFont(.system(size: 14, weight: .semibold)) }.menuStyle(.borderlessButton).padding(.horizontal, 8).padding(.top, 14)
            Button { store.showSearch = true } label: {
                HStack { Image(systemName: "magnifyingglass"); Text("Search everything"); Spacer(); Text("⌘F").macFont(.caption) }.foregroundStyle(theme.color(.sidebarFg).opacity(0.72)).padding(8).background(theme.color(.sidebarFg).opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(MacBoxButtonStyle()).padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([("All Notes", "doc.text"), ("Tasks", "checkmark.square"), ("Links", "link"), ("Files", "doc.on.doc"), ("External Notes", "arrow.up.right.square")], id: \.0) { name, icon in navigationRow(name, icon: icon) }
                    HStack { Text("Types").macFont(.caption).foregroundStyle(.secondary); Spacer(); Button { ask(.folder) } label: { Image(systemName: "plus") }.buttonStyle(MacBoxButtonStyle()).help("Create folder") }.padding(.horizontal, 8).padding(.top, 15)
                    if let message = store.folderIconIssue { Text(message).macFont(.caption).foregroundStyle(.secondary).padding(.horizontal, 8) }
                    LazyVStack(spacing: 2) {
                        ForEach(store.visibleFolders.map { MacSidebarFolder(path: $0) }) { folder in folderRow(folder.path) }
                    }
                }
            }
            Spacer(minLength: 0)
            navigationRow("Archive", icon: "archivebox")
            navigationRow("Trash", icon: "trash")
            Button { settings = true } label: { Label("Settings", systemImage: "gearshape").padding(8) }.buttonStyle(MacBoxButtonStyle())
        }.padding(.horizontal, 10).padding(.bottom, 10).foregroundStyle(theme.color(.sidebarFg)).background(sidebarSurface)
    }
    private func folderRow(_ folder: String) -> some View {
        let scope = store.folderOrderScope
        let neighbors = store.folderOrderNeighbors(folder)
        let transfer = MacFolderOrderTransfer(scope: scope, source: folder)
        let children = store.folders.contains { $0.hasPrefix(folder + "/") }
        return HStack(spacing: 0) {
            Button { store.toggleFolder(folder) } label: { Image(systemName: store.collapsedFolders.contains(folder) ? "chevron.right" : "chevron.down").macFont(.system(size: 9, weight: .semibold)).frame(width: 20).frame(maxHeight: .infinity).contentShape(Rectangle()) }
                .buttonStyle(MacBoxButtonStyle()).disabled(!children).opacity(children ? 1 : 0)
                .accessibilityLabel((store.collapsedFolders.contains(folder) ? "Expand " : "Collapse ") + folder)
            Button { compactLibrary = false; store.navigateFolder(folder) } label: {
                HStack(spacing: 7) {
                    MacFolderIcon(value: store.folderIcon(folder)).foregroundStyle(store.folderCollection && store.destination == folder ? macAccent : .secondary).accessibilityHidden(true)
                    Text((folder as NSString).lastPathComponent).lineLimit(1)
                    Spacer()
                    if store.keptFolders.contains(folder) { Image(systemName: "pin.fill").macFont(.system(size: 8)).foregroundStyle(.tertiary) }
                    Text("\(store.noteCount(in: folder))").macFont(.caption).foregroundStyle(.tertiary)
                }.padding(.vertical, 6).padding(.trailing, 6).contentShape(Rectangle())
            }.buttonStyle(MacBoxButtonStyle()).accessibilityAddTraits(store.folderCollection && store.destination == folder ? .isSelected : [])
        }.padding(.leading, CGFloat(folder.filter { $0 == "/" }.count) * 12)
            .background(store.folderCollection && store.destination == folder ? macAccent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(MacAlternateOpen { store.navigateFolder(folder, newTab: true) }.accessibilityHidden(true))
            .draggable(transfer)
            .dropDestination(for: MacFolderOrderTransfer.self) { values, _ in
                guard values.count == 1, store.folderOrderScope == scope, let value = values.first else { return false }
                return store.dropFolder(value, target: folder)
            }
            .contextMenu {
                Button("Open folder in tab") { store.navigateFolder(folder, newTab: true) }
                Button("New note here") { Task { await store.createNote(folder: folder) } }
                Button("Change icon…") { store.editorSheetActive = true; folderIconRequest = .init(folder: folder, workspaceID: store.workspaceID) }
                Button("Folder properties…") { schemaOwner = folder }
                Button("Move up") { if let target = neighbors.previous { store.reorderFolder(transfer, target: target, before: true) } }.disabled(neighbors.previous == nil || store.busy || store.preparingToClose)
                Button("Move down") { if let target = neighbors.next { store.reorderFolder(transfer, target: target, before: false) } }.disabled(neighbors.next == nil || store.busy || store.preparingToClose)
                Button(store.keptFolders.contains(folder) ? "Stop keeping folder open" : "Keep folder open") { store.keepFolderOpen(folder) }
                Button("Rename folder…") { folderRequest = .init(folder: folder, action: .rename, workspaceID: store.workspaceID) }
                Button("Move folder to Trash…", role: .destructive) { folderRequest = .init(folder: folder, action: .trash, workspaceID: store.workspaceID) }
                Button("Reveal in Finder") { if let root = store.root { NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(folder)]) } }
            }
    }
    private func navigationRow(_ name: String, icon: String) -> some View {
        Button { compactLibrary = false; store.navigate(name) } label: {
            HStack(spacing: 9) { Image(systemName: icon).frame(width: 16).foregroundStyle(macAccent).accessibilityHidden(true); Text(name); Spacer() }
                .padding(.horizontal, 8).padding(.vertical, 6).background(!store.folderCollection && store.destination == name ? macAccent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(MacBoxButtonStyle()).accessibilityAddTraits(!store.folderCollection && store.destination == name ? .isSelected : []).overlay(MacAlternateOpen { store.navigate(name, newTab: true) }.accessibilityHidden(true))
            .contextMenu { Button("Open in tab") { store.navigate(name, newTab: true) }; if name == "Trash" { Button("Deleted folders and revisions…") { trashBrowser = true } } }
    }
    /// Wide layouts (table, board, gallery, calendar) get one toolbar row and a
    /// floating selection bar; the narrow List column keeps its stacked header.
    private var collectionView: some View {
        let notes = store.collection, wide = store.viewMode != "List"
        return VStack(spacing: 0) {
            if wide { wideCollectionHeader } else { narrowCollectionHeader }
            Divider()
            if !wide {
                MacCollectionSelectionContent(selection: store.collectionSelection) {
                    if store.selecting || !store.selectedPaths.isEmpty { bulkBar }
                }
            }
            if store.destination == "Files" && !store.folderCollection && store.viewMode == "List" { filesView.modifier(MacCollectionKeyboard(store: store)) }
            else if wide {
                alternateCollection.overlay(alignment: .bottom) {
                    MacCollectionSelectionContent(selection: store.collectionSelection) {
                        if store.selecting || !store.selectedPaths.isEmpty { floatingBulkBar.padding(.bottom, 14).transition(.move(edge: .bottom).combined(with: .opacity)) }
                    }
                }
            }
            else {
                MacProgressiveNoteList(notes: notes, scope: .init(workspace: store.workspaceID, destination: store.destination, folder: store.folderCollection, query: store.query, filters: store.filters, hideSubtypes: store.hideSubtypes), row: noteRow)
                    .modifier(MacCollectionKeyboard(store: store))
                if notes.isEmpty { ContentUnavailableView.search(text: store.query).macFont(.caption).frame(maxHeight: .infinity) }
            }
            HStack { Text("\(notes.count) notes"); if store.filters.activeCount > 0 { Text("· \(store.filters.sort.rawValue) · \(store.filters.activeCount) filter\(store.filters.activeCount == 1 ? "" : "s")") }; Spacer() }.macFont(.caption2).foregroundStyle(.secondary).padding(9)
        }.background(theme.color(.surface))
    }
    private var narrowCollectionHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(store.destination).macFont(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                MacViewModeMenu(store: store)
                emptyTrashButton
                selectButton
                newButton.labelStyle(.iconOnly).buttonStyle(MacBoxButtonStyle())
            }.padding(.horizontal, 14).frame(height: 46)
            Divider()
            VStack(spacing: 8) {
                collectionSearch
                HStack { filterButton(expanded: true); if store.folderCollection { MacSavedViewsMenu(store: store) } }
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
    private var wideCollectionHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(store.destination).macFont(.system(size: 20, weight: .bold)).lineLimit(1)
                Text("\(store.collection.count)").macFont(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 12)
                collectionSearch.frame(minWidth: 160, idealWidth: 240, maxWidth: 260)
                filterButton(expanded: false)
                if store.folderCollection { MacSavedViewsMenu(store: store) }
                emptyTrashButton
                selectButton
                newButton.buttonStyle(.borderedProminent).tint(theme.color(.text)).foregroundStyle(theme.color(.surface)).controlSize(.regular).help("New note")
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        }
    }
    private var collectionSearch: some View {
        HStack { Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.text).opacity(0.72)); MacNoteSearchField(store: store) }.foregroundStyle(theme.color(.text)).padding(7).background(theme.color(.editorBg), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.color(.text).opacity(0.15)))
    }
    private func filterButton(expanded: Bool) -> some View {
        Button { filtersOpen.toggle() } label: {
            HStack { Image(systemName: "line.3.horizontal.decrease"); Text("Sort & filter"); if expanded { Spacer() }; if store.filters.activeCount > 0 { Text("\(store.filters.activeCount)").macFont(.caption).foregroundStyle(.white).padding(.horizontal, 5).background(macAccent, in: Capsule()) }; Image(systemName: "chevron.down").macFont(.caption) }.padding(7).contentShape(Rectangle())
        }.buttonStyle(MacBoxButtonStyle()).overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary)).fixedSize(horizontal: !expanded, vertical: false).macPopover(isPresented: $filtersOpen) { filterView }
    }
    private var selectButton: some View {
        MacCollectionSelectionContent(selection: store.collectionSelection) {
            if store.selecting || !store.selectedPaths.isEmpty {
                Button { store.clearCollectionSelection() } label: { Text("Done").fontWeight(.semibold).foregroundStyle(macAccent).padding(.horizontal, 9).padding(.vertical, 5).overlay(RoundedRectangle(cornerRadius: 7).stroke(macAccent)) }.buttonStyle(MacBoxButtonStyle()).help("Leave selection mode").keyboardShortcut(.cancelAction)
            } else {
                Button { store.selecting = true } label: { Image(systemName: "checkmark.circle").accessibilityHidden(true); Text("Select") }.buttonStyle(MacBoxButtonStyle()).help("Select notes for bulk actions")
            }
        }
    }
    @ViewBuilder private var emptyTrashButton: some View {
        if store.destination == "Trash" && !store.folderCollection {
            Button { Task { emptyTrashPlan = await store.prepareEmptyTrash() } } label: { Text("Empty Trash").foregroundStyle(macAccent) }
                .buttonStyle(MacBoxButtonStyle()).disabled(store.busy || !store.notes.contains(where: \.trashed)).help("Permanently delete every note in Trash")
                .confirmationDialog("Empty Trash?", isPresented: Binding(get: { emptyTrashPlan != nil }, set: { if !$0 { emptyTrashPlan = nil } })) {
                    Button("Delete \(emptyTrashPlan?.deleted.count ?? 0) notes permanently", role: .destructive) { if let plan = emptyTrashPlan { Task { await store.commitEmptyTrash(plan) } } }
                } message: { Text("These notes and their retained versions will be permanently removed. This cannot be undone.") }
        }
    }
    private var newButton: some View {
        Button { if !store.folderCollection && store.destination == "Files" { addDocument() } else if !store.folderCollection && store.destination == "Links" { ask(.link) } else { Task { await store.createNote() } } } label: { Label("New", systemImage: "plus") }
    }
    /// Bulk actions float over wide layouts so selecting does not push the
    /// content down. Same actions as the narrow bar.
    private var floatingBulkBar: some View {
        let count = store.selectedPaths.count, total = store.collection.count
        return HStack(spacing: 12) {
            Text("\(count) selected").fontWeight(.semibold).monospacedDigit()
            Divider().frame(height: 16)
            Button("Edit properties…") { bulkProperties = true }.disabled(count == 0)
            Button("Move…") { bulkMove = true }.disabled(count == 0)
            Menu("More") {
                Button("Pin") { Task { await store.flag(store.selectedPaths, pinned: true) } }
                Button("Unpin") { Task { await store.flag(store.selectedPaths, pinned: false) } }
                Button("Archive") { Task { await store.flag(store.selectedPaths, archived: true) } }
                Button("Unarchive") { Task { await store.flag(store.selectedPaths, archived: false) } }
                Divider()
                Button("Organization history…") { bulkHistory = true }
            }.menuStyle(.borderlessButton).fixedSize().disabled(count == 0)
            if count < total { Button("Select all \(total)") { store.selectAllCollectionNotes() } }
            Divider().frame(height: 16)
            Button { store.clearCollectionSelection() } label: { Image(systemName: "xmark") }.help("Clear selection").accessibilityLabel("Clear selection")
        }
        .buttonStyle(MacBoxButtonStyle()).macFont(.system(size: 12.5))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.color(.text).opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        .fixedSize()
    }
    private func noteRow(_ note: NoteDocument) -> some View {
        MacCollectionSelectionContent(selection: store.collectionSelection) { noteRowContent(note) }
    }
    private func noteRowContent(_ note: NoteDocument) -> some View {
        Button {
            let modifiers = NSApp.currentEvent?.modifierFlags ?? [], origin = store.workspaceID
            Task { guard origin == store.workspaceID else { return }; await store.activateCollectionNote(note.path, modifiers: modifiers) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    if store.selecting { Image(systemName: store.selectedPaths.contains(note.path) ? "checkmark.circle.fill" : "circle").foregroundStyle(macAccent) }
                    if note.pinned { Image(systemName: "pin.fill").macFont(.caption2).foregroundStyle(macAccent) }
                    Text(note.title).macFont(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 3)
                    Text(note.modified, format: .dateTime.month(.abbreviated).day()).macFont(.system(size: 10)).foregroundStyle(.tertiary)
                }
                MacCollectionExcerpt(note: note, workspaceID: store.workspaceID, lines: 2).macFont(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }.padding(.horizontal, 15).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(store.selectedPaths.contains(note.path) ? macAccent.opacity(0.13) : store.selection == note.path ? theme.color(.editorBg) : .clear)
                .overlay(alignment: .leading) { if store.selection == note.path { Rectangle().fill(macAccent).frame(width: 3) } }
        }.buttonStyle(MacBoxButtonStyle()).accessibilityAddTraits(store.selectedPaths.contains(note.path) ? .isSelected : []).overlay(MacAlternateOpen { Task { await store.openNote(note.path, newTab: true) } }.accessibilityHidden(true)).contentShape(Rectangle()).contextMenu { noteMenu(note) }.overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }
    /// The toolbar ⋯ menu: actions on the open note itself. A linked
    /// document's own actions live in its file card's split button.
    @ViewBuilder private func noteActions(_ note: NoteDocument) -> some View {
        Section {
            Button("Find in Note", systemImage: "text.magnifyingglass") { MacNoteFind.show() }
            Button("Version History…", systemImage: "clock.arrow.circlepath") { recoveryRequest = .init(workspaceID: store.workspaceID, path: note.path) }
            Button(focusMode ? "Exit Focus Mode" : "Focus Mode", systemImage: focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { focusMode.toggle() }
            Button("Copy Note Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(NoteReference(target: note.title, label: note.title, explicitLabel: false).markdown(label: note.title), forType: .string)
            }
            Button("Open in New Tab", systemImage: "plus.square.on.square") { Task { await store.openNote(note.path, newTab: true) } }
        }
        Section {
            Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") { Task { await store.flag([note.path], pinned: !note.pinned) } }
            Button(note.archived ? "Unarchive" : "Archive", systemImage: "archivebox") { Task { await store.flag([note.path], archived: !note.archived) } }
            Button("Duplicate", systemImage: "square.on.square") { Task { await store.duplicate(note) } }
            Button("Rename…", systemImage: "pencil") { Task { await store.openNote(note.path); ask(.rename, value: note.title) } }
            Menu("Move to Folder", systemImage: "folder") { Button("Vault root (Inbox)") { Task { await store.move(note, folder: "") } }; ForEach(store.folders, id: \.self) { folder in Button(folder) { Task { await store.move(note, folder: folder) } } } }
            if note.fileHub == nil && !note.trashed {
                Button("Link Document…", systemImage: "paperclip") {
                    Task { do { let request = try await store.prepareFileHub(note); hubInitialSource = nil; fileHubRequest = request } catch { store.issue = error.localizedDescription } }
                }
            }
            Button("Organization History…", systemImage: "clock.arrow.2.circlepath") { bulkHistory = true }
        }
        Section {
            Button("Export…", systemImage: "square.and.arrow.up") {
                guard let root = store.root else { return }
                exportRequest = MacExportRequest(note: note, body: store.body, root: root)
                store.editorSheetActive = true
            }
            Button("Print…", systemImage: "printer") { store.presentPrint() }.disabled(!store.canPrintCurrentNote)
            Button("Show Note in Finder", systemImage: "finder") { store.reveal(note) }
        }
        Section {
            if note.trashed { Button("Restore Note", systemImage: "arrow.uturn.backward") { Task { await store.trash(note) } } }
            else { Button("Move to Trash", systemImage: "trash", role: .destructive) { Task { await store.trash(note) } } }
        }
    }
    @ViewBuilder private func noteMenu(_ note: NoteDocument) -> some View {
        Button("Open in New Tab") { Task { await store.openNote(note.path, newTab: true) } }
        Button(note.pinned ? "Unpin" : "Pin") { Task { await store.flag([note.path], pinned: !note.pinned) } }
        Button(note.archived ? "Unarchive" : "Archive") { Task { await store.flag([note.path], archived: !note.archived) } }
        Button("Duplicate") { Task { await store.duplicate(note) } }
        Button("Rename…") { Task { await store.openNote(note.path); ask(.rename, value: note.title) } }
        Menu("Move to folder") { Button("Vault root (Inbox)") { Task { await store.move(note, folder: "") } }; ForEach(store.folders, id: \.self) { folder in Button(folder) { Task { await store.move(note, folder: folder) } } } }
        if !note.trashed {
            // Closed context menus are evaluated for ordinary collection rows.
            // A hub requires its ID; avoid reparsing the note when the cached
            // metadata already proves that required entry is absent.
            let hasFileHub = note.property(NativeFileHub.keys[0]) != nil && note.fileHub != nil
            Button(hasFileHub ? "Replace linked document…" : "Link document…") {
                Task { do { let request = try await store.prepareFileHub(note); hubInitialSource = nil; fileHubRequest = request } catch { store.issue = error.localizedDescription } }
            }
        }
        Button("Reveal in Finder") { store.reveal(note) }
        Divider()
        Button(note.trashed ? "Restore note" : "Move to Trash", role: note.trashed ? nil : .destructive) { Task { await store.trash(note) } }
    }
    private var bulkBar: some View {
        HStack { Text("\(store.selectedPaths.count)"); Button("All") { store.selectAllCollectionNotes() }; Button("Clear") { store.clearCollectionSelection() }; Menu("Actions") {
            Button("Pin") { Task { await store.flag(store.selectedPaths, pinned: true) } }
            Button("Unpin") { Task { await store.flag(store.selectedPaths, pinned: false) } }
            Button("Archive") { Task { await store.flag(store.selectedPaths, archived: true) } }
            Button("Unarchive") { Task { await store.flag(store.selectedPaths, archived: false) } }
            Divider()
            Button("Move to folder…") { bulkMove = true }.disabled(store.selectedPaths.isEmpty)
            Button("Edit properties…") { bulkProperties = true }.disabled(store.selectedPaths.isEmpty)
            Button("Organization history…") { bulkHistory = true }
        }; Spacer() }.macFont(.caption).padding(9)
    }
    private var filterView: some View { MacFilterPanel(filters: Binding(get: { store.filters }, set: store.changeCollectionFilters), notes: store.notes, schema: store.schema, showsFolders: !store.folderCollection) }
    private var editorView: some View {
        VStack(spacing: 0) {
            if let note = store.current {
                // Note controls live in the window toolbar. A document note shows
                // its folder in the file card; every other note gets a slim line.
                if note.fileHub != nil && !note.trashed {
                    MacFileHubPane(workspace: store, note: note) { noteWritingArea(note) }.id(note.path + store.workspaceID.uuidString)
                } else {
                    MacNoteBreadcrumb(folder: note.folder, vault: store.vaultTitle).padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
                    if note.savedLink != nil && !note.trashed {
                        MacSavedLinkPane(store: store, note: note) { noteWritingArea(note) }.id(note.path + store.workspaceID.uuidString)
                    } else { noteWritingArea(note) }
                }
            } else { ContentUnavailableView("Choose a note", systemImage: "doc.text", description: Text("Your ideas, in files you own.")).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.background(theme.color(.editorBg))
    }
    private func noteWritingArea(_ note: NoteDocument) -> some View {
        MacNoteWritingArea(store: store, draft: store.draftState, note: note, sessions: editorSessions, clipboardBusy: $clipboardBusy, toolbar: formatToolbar)
    }
    private var formatToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 13) {
            editorButton("undo", icon: "arrow.uturn.backward", help: "Undo")
            editorButton("redo", icon: "arrow.uturn.forward", help: "Redo")
            Divider().frame(height: 16)
            Menu("Paragraph") { Button("Indent list item (Tab)") { sendEditor("indent") }; Button("Outdent list item (⇧Tab)") { sendEditor("outdent") }; Divider(); Button("Continue after code or table (⌘Return)") { sendEditor("exitCode") }; Button("Turn code block into text") { sendEditor("codeToText") }; Divider(); ForEach([("Paragraph", "paragraph"), ("Heading 1", "h1"), ("Heading 2", "h2"), ("Heading 3", "h3"), ("Heading 4", "h4"), ("Heading 5", "h5"), ("Heading 6", "h6"), ("Quote", "quote"), ("Numbered list", "ordered")], id: \.0) { name, action in Button(name) { sendEditor(action) } } }.menuStyle(.borderlessButton).fixedSize()
            editorButton("bold", icon: "bold", help: "Bold")
            editorButton("italic", icon: "italic", help: "Italic")
            editorButton("underline", icon: "underline", help: "Underline")
            editorButton("code", icon: "chevron.left.forwardslash.chevron.right", help: "Inline code")
            Divider().frame(height: 16)
            editorButton("bullet", icon: "list.bullet", help: "Bullet list")
            editorButton("checklist", icon: "checklist", help: "Checklist")
            editorButton("rule", icon: "minus", help: "Insert horizontal rule")
            Menu { Button("Insert or edit link…") { sendEditor("link") }; Button("Note link suggestions") { sendEditor("noteLink") } } label: { Image(systemName: "link") }.help("Insert or edit link").accessibilityLabel("Link").menuStyle(.borderlessButton).fixedSize()
            editorButton("insertImage", icon: "photo", help: "Insert image")
            Button { attachFile() } label: { Image(systemName: "paperclip") }.help("Attach a file")
            MacBlockMenu(workspace: store, codeBlocks: codeBlocks, openTable: { tableRequest = $0 }, openCode: { codeRequest = $0 })
                .frame(width: 32, height: 20)
            Spacer(minLength: 0)
        }.buttonStyle(MacBoxButtonStyle()).macFont(.system(size: 12)).padding(.horizontal, 14) }.frame(height: 35)
    }
    private func editorButton(_ action: String, icon: String, help: String) -> some View { Button { sendEditor(action) } label: { Image(systemName: icon) }.help(help) }
    private func sendEditor(_ action: String) {
        guard let path = store.selection else { return }
        NotificationCenter.default.post(name: .macEditorAction, object: MacEditorCommand(scope: store.workspaceID, path: path, action: action))
    }
    private var inspectorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let issue = store.paneLayoutIssue {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(issue).macFont(.system(size: 12)).foregroundStyle(.red)
                        Button("Refresh pane layout") { Task { await store.refreshPaneLayout() } }.controlSize(.small)
                    }.padding(.horizontal, 6).padding(.bottom, 10)
                }
                ForEach(Array(store.paneLayout.order.enumerated()), id: \.element) { index, section in
                    if index > 0 { Divider().opacity(0.6).padding(.vertical, 8) }
                    inspectorSection(section) { inspectorContents(section) }
                }
                if let note = store.current {
                    Divider().opacity(0.6).padding(.vertical, 8)
                    MacInspectorPathFooter(path: note.path)
                }
            }.padding(.horizontal, 10).padding(.vertical, 12)
        }.frame(maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let note = store.current {
                VStack(spacing: 0) { Divider(); MacInspectorNoteStatus(store: store, draft: store.draftState, note: note) }.background(theme.color(.surface))
            }
        }
        .background(theme.color(.surface))
    }
    private func inspectorSection<Content: View>(_ section: MacPaneSection, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MacPaneHeader(workspace: store, section: section)
            if !store.paneLayout.collapsed.contains(section) {
                VStack(alignment: .leading, spacing: 2) { content() }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private var currentDefinitions: [NativePropertyDefinition] {
        guard let note = store.current else { return [] }
        return (try? store.schema?.effective(notePath: note.path)) ?? []
    }
    @ViewBuilder private func inspectorContents(_ section: MacPaneSection) -> some View {
        switch section {
        case .properties:
            if let note = store.current {
                let definitions = currentDefinitions
                let byID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                let frontmatter = NativeFrontmatter(note.content)
                // Relation properties live in the Relations section.
                let entries = frontmatter.entries.filter { !$0.key.lowercased().hasPrefix("zerus-") && byID[$0.id]?.hidden != true && byID[$0.id]?.type != .relation }
                ForEach(entries, id: \.key) { entry in
                    let definition = byID[entry.id]
                    MacInspectorPropertyRow(
                        name: entry.key, type: inspectorType(definition, value: entry.value), value: entry.value,
                        display: propertyText(entry.key, value: entry.value), preserved: entry.value == nil, disabled: store.busy,
                        edit: { editProperty(entry.key, value: entry.value) },
                        toggle: { on in Task { await store.setProperty(entry.key, value: .checkbox(on)) } })
                }
                ForEach(definitions.filter { !$0.hidden && $0.type != .relation && frontmatter.entry($0.name) == nil }) { definition in
                    MacInspectorPropertyRow(
                        name: definition.name, type: definition.type, value: nil, display: "", preserved: false, disabled: store.busy,
                        edit: { editProperty(definition.name, value: nil) },
                        toggle: { on in Task { await store.setProperty(definition.name, value: .checkbox(on)) } })
                }
            }
            MacInspectorAction(title: "Add property", icon: "plus") { typedProperty = .init(name: "", value: nil, definition: nil) }
        case .revisions:
            MacInspectorRecoveryContent(state: store.inspectorRecovery) {
                let live = store.revisions.map { snapshot in snapshot.index.revisions.filter { $0.deletedAt == nil } } ?? []
                let current = store.revisions.flatMap { snapshot in live.first { $0.id == snapshot.index.currentID } }
                if store.revisionIssue != nil { Label("Revisions unavailable — browse for details", systemImage: "exclamationmark.triangle").macFont(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 6) }
                MacInspectorRevisionCard(current: current, count: live.count, browse: {
                    if let path = store.selection { recoveryRequest = .init(workspaceID: store.workspaceID, path: path, selectedID: current?.id) }
                }, history: {
                    if let path = store.selection { recoveryRequest = .init(workspaceID: store.workspaceID, path: path, history: true) }
                })
                if store.historyIssue != nil { Label("History unavailable — browse for details", systemImage: "exclamationmark.triangle").macFont(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 6) }
            }
        case .relations:
            relationsContent
        case .outline:
            MacOutlineView(draft: store.draftState, onSelect: store.revealHeading)
                .id((store.selection ?? "") + store.workspaceID.uuidString)
                .padding(.horizontal, 6)
        case .attachments:
            if let note = store.current {
                ForEach(store.currentResources, id: \.self) { value in
                    MacInspectorFileRow(name: (value as NSString).lastPathComponent) {
                        if let root = store.root, let url = try? VaultFiles.resolveResource(value, notePath: note.path, root: root) { filePreview = url }
                    }
                }
            }
            HStack(spacing: 0) {
                MacInspectorAction(title: "Add file", icon: "paperclip") { attachFile() }
                MacInspectorAction(title: "Images", icon: "photo.on.rectangle") { images = true }
            }
        }
    }
    @ViewBuilder private var relationsContent: some View {
        if let note = store.current {
            let frontmatter = NativeFrontmatter(note.content)
            let relations = currentDefinitions.filter { !$0.hidden && $0.type == .relation }
            if let undo = store.relationUndo, undo.workspaceID == store.workspaceID, undo.sourcePath == note.path {
                MacRelationUndoBanner(text: "Removed “\(undo.title)” from \(undo.relation)", disabled: store.busy,
                                      undo: { Task { await store.undoRelationRemoval() } }, dismiss: { store.relationUndo = nil })
            }
            ForEach(relations) { definition in
                let targets = frontmatter.entry(definition.name)?.value?.selections ?? []
                VStack(alignment: .leading, spacing: 4) {
                    MacInspectorGroupHeader(title: definition.name, count: targets.count) { relationName = definition.name }
                    if targets.isEmpty {
                        Text("None linked").macFont(.system(size: 12)).foregroundStyle(.quaternary).padding(.horizontal, 6)
                    }
                    ForEach(Array(targets.enumerated()), id: \.offset) { _, text in
                        let reference = NoteReference(wikilink: "[[" + text + "]]")
                        let found = reference?.targets(in: store.notes) ?? []
                        let target = found.count == 1 ? found[0] : nil
                        let title = target?.title ?? (reference?.explicitLabel == true ? reference!.label : text)
                        MacInspectorNoteLink(title: title, detail: target?.folder, available: target != nil, icon: target.flatMap { store.folderIcon($0.folder) },
                                             removeHelp: "Remove from " + definition.name,
                                             remove: store.busy ? nil : { Task { relationRemoval = await store.prepareRelationRemoval(definition.name, reference: text, title: title) } }) {
                            if let target { Task { await store.openNote(target.path) } }
                        }
                    }
                }.padding(.bottom, 6)
            }
            VStack(alignment: .leading, spacing: 4) {
                MacInspectorGroupHeader(title: "Backlinks", count: store.backlinks.count, icon: "arrow.uturn.left")
                if store.backlinks.isEmpty { Text("No notes link here yet").macFont(.system(size: 12)).foregroundStyle(.quaternary).padding(.horizontal, 6) }
                ForEach(store.backlinks) { linked in
                    MacInspectorNoteLink(title: linked.title, detail: linked.folder, icon: store.folderIcon(linked.folder)) { Task { await store.openNote(linked.path) } }
                }
            }
            .confirmationDialog("Remove relation?", isPresented: Binding(get: { relationRemoval != nil }, set: { if !$0 { relationRemoval = nil } })) {
                Button("Remove", role: .destructive) { if let removal = relationRemoval { Task { await store.commitRelationRemoval(removal) } } }
            } message: { Text(relationRemovalMessage) }
        }
    }
    private var relationRemovalMessage: String {
        guard let removal = relationRemoval else { return "" }
        var text = removal.resolved
            ? "“\(removal.title)” will be removed from \(removal.relation). The matching link back to this note on “\(removal.title)” is removed too. Neither note is deleted, and you can undo this for both notes afterwards."
            : "The unavailable link “\(removal.title)” will be removed from \(removal.relation)."
        if !removal.otherChanges.isEmpty { text += "\n\nThese notes are also updated to keep their paired links consistent:\n" + removal.otherChanges.joined(separator: "\n") }
        return text
    }
    private func inspectorType(_ definition: NativePropertyDefinition?, value: NativePropertyValue?) -> NativePropertyType {
        if let type = definition?.type, type != .unsupported { return type }
        if case .text(let text)? = value, let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) { return .url }
        return NativePropertyType.inferred(value)
    }
    private var alternateCollection: some View {
        MacCollectionViews(store: store, noteMenu: { note in AnyView(noteMenu(note)) })
    }
    private var filesView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack { Button("Add document…") { addDocument() }; Spacer(); Button("Locations…") { fileLocations = true } }.macFont(.caption).padding(12)
                ForEach(store.collection) { note in noteRow(note) }
            }
        }
    }
    private func addDocument(_ source: URL? = nil) {
        Task { do { let request = try await store.prepareFileHub(); hubInitialSource = source; fileHubRequest = request } catch { store.issue = error.localizedDescription } }
    }
    private var welcome: some View {
        let recents = store.recentVaults, shown = showAllRecents ? recents : Array(recents.prefix(5))
        return GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if managingVaults, store.root != nil {
                        Button { managingVaults = false } label: { Label("Back to " + store.vaultTitle, systemImage: "chevron.left") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).keyboardShortcut(.cancelAction)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 24)
                    }
                    Image(systemName: "books.vertical").macFont(.system(size: 44)).foregroundStyle(macAccent)
                    Text("A little space for everything").macFont(.largeTitle.bold()).multilineTextAlignment(.center).padding(.top, 14)
                    Text("Open a folder of Markdown files to start writing.").foregroundStyle(.secondary).padding(.top, 6)
                    MacPendingDesktopFiles(opener: store.desktopFiles).padding(.top, 12)
                    HStack(spacing: 10) {
                        Button("Open Vault…") { store.chooseVault() }.buttonStyle(.borderedProminent)
                        Button("New Vault…") { store.createVault() }
                    }.controlSize(.large).padding(.top, 18)
                    if !recents.isEmpty {
                        Text("Recent").macFont(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4).padding(.top, 30).padding(.bottom, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element) { index, path in
                                MacRecentVaultRow(path: path, icon: store.vaultIcons[path], current: store.root?.path == path,
                                                  open: { if store.root?.path == path { managingVaults = false } else { Task { await store.openRecentVault(path) } } },
                                                  changeIcon: { vaultIconRequest = .init(path: path) },
                                                  remove: { withAnimation(.snappy) { store.forgetRecentVault(path) } })
                                if index < shown.count - 1 { Divider().padding(.leading, 54) }
                            }
                        }
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.09)))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        if recents.count > 5 {
                            Button(showAllRecents ? "Show Fewer" : "Show All \(recents.count) Recent Vaults…") { withAnimation(.snappy) { showAllRecents.toggle() } }
                                .buttonStyle(.plain).macFont(.callout).foregroundStyle(.secondary).padding(.top, 10)
                        }
                    }
                }
                .frame(width: 400).padding(40)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }
    private func ask(_ value: MacPrompt, value text: String = "") { input = text; secondInput = ""; prompt = value }
    private func promptView(_ kind: MacPrompt) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(kind.title).macFont(.headline)
            if kind == .property { TextField("Property name", text: $propertyName); TextField("Value", text: $propertyValue) }
            else { TextField(kind == .link ? "Title" : "Name", text: $input); if kind == .link { TextField("https://…", text: $secondInput) } }
            HStack { Spacer(); Button("Cancel") { prompt = nil }.keyboardShortcut(.cancelAction); Button("Save") {
                switch kind {
                case .folder: Task { await store.createFolder(input) }
                case .rename: if let note = store.current { Task { await store.rename(note, title: input) } }
                case .link: Task { await store.createLink(address: secondInput, title: input) }
                case .property: Task { await store.setProperty(propertyName, value: .text(propertyValue)) }
                }; prompt = nil
            }.keyboardShortcut(.defaultAction).disabled(kind == .property ? propertyName.isEmpty : input.isEmpty) }
        }.padding(24).frame(width: 420)
    }
    private func applyCode(_ request: MacCodeRequest, replacement: String) throws {
        guard store.workspaceID == request.workspaceID, store.selection == request.path else { throw VaultFailure(message: "The note changed. Copy your code before closing this sheet, then reopen it in the current note.") }
        let command = MacCodeChange(request: request, replacement: replacement)
        NotificationCenter.default.post(name: .macEditorAction, object: command)
        guard let result = command.result else { throw VaultFailure(message: "The editor is unavailable. Copy your code before closing this sheet, then reopen it.") }
        try result.get()
    }
    private func applyTable(_ request: MacTableRequest, replacement: String) throws {
        guard store.workspaceID == request.workspaceID, store.selection == request.path else { throw VaultFailure(message: "The note changed. Copy your table before closing this sheet, then reopen it.") }
        let command = MacTableChange(request: request, replacement: replacement)
        NotificationCenter.default.post(name: .macEditorAction, object: command)
        guard let result = command.result else { throw VaultFailure(message: "The editor is unavailable. Copy your table before closing this sheet, then reopen it.") }
        try result.get()
    }
    private func propertyText(_ name: String, value: NativePropertyValue?) -> String {
        let definition = store.current.flatMap { try? store.schema?.effective(notePath: $0.path).first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
        if definition?.type == .date, let value { return MacNumericDateFormat.validated(dateFormat).display(value.display) }
        guard definition?.type == .relation else { return value?.display ?? "Preserved YAML" }
        return (value?.selections ?? []).map { text in
            guard let reference = NoteReference(wikilink: "[[" + text + "]]") else { return "Unavailable note" }
            let found = reference.targets(in: store.notes)
            return found.count == 1 ? found[0].title : reference.explicitLabel ? reference.label : "Unavailable note"
        }.joined(separator: ", ")
    }
    private func editProperty(_ name: String, value: NativePropertyValue?) {
        let definition = store.current.flatMap { try? store.schema?.effective(notePath: $0.path).first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
        if definition?.type == .relation { relationName = name }
        else { typedProperty = .init(name: name, value: value, definition: definition) }
    }
    private func attachFile() {
        guard !store.busy, !attachmentImporting, store.io != nil, let notePath = store.selection else { return }
        let origin = store.workspaceID
        let panel = NSOpenPanel(); guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !store.busy, store.workspaceID == origin, store.selection == notePath else { return }
        let baseline = store.editorBody(store.body)
        attachmentImporting = true
        Task {
            defer { attachmentImporting = false }
            do {
                let lease = try NativeFileLease(scope: url)
                let bytes = try Data(contentsOf: lease.url), name = MacClipboard.importName(url.lastPathComponent)
                let reference = MarkdownResources.encodedPath("assets/" + name, preservingSuffixOf: "")
                let label = name.replacingOccurrences(of: #"([\\\[\]])"#, with: #"\$1"#, options: .regularExpression)
                let image = ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(url.pathExtension.lowercased())
                let fragment = NativeClipboardFragment(markdown: "\n" + (image ? "!" : "") + "[" + label + "](" + reference + ")\n", resources: [.init(reference: reference, path: nil, name: name, bytes: bytes)])
                guard !store.busy, store.workspaceID == origin, store.selection == notePath else { throw VaultFailure(message: "The selected note changed. Attach the file again to the intended note.") }
                let command = MacAttachmentImport(scope: origin, path: notePath, source: baseline, fragment: fragment)
                NotificationCenter.default.post(name: .macEditorAction, object: command)
                guard let task = command.task else { throw VaultFailure(message: "The editor is unavailable. Reopen the note before attaching the file.") }
                try await task.value
            } catch { if store.workspaceID == origin { store.issue = error.localizedDescription } }
        }
    }
}

private struct MacSidebarFolder: Identifiable { let path: String; var id: Data { Data(path.utf8) } }

private enum MacPrompt: String, Identifiable { case folder, rename, link, property; var id: String { rawValue }; var title: String { switch self { case .folder: "New folder"; case .rename: "Rename note and update references"; case .link: "Save a link"; case .property: "Edit property" } } }
extension URL: @retroactive Identifiable { public var id: String { absoluteString } }


/// Only the live writing area observes every text change. The surrounding
/// folder, collection and saved-note inspector keep workspace-level updates.
@MainActor private struct MacNoteWritingArea<Toolbar: View>: View {
    @Bindable var store: MacWorkspace
    @ObservedObject var draft: MacNoteDraftState
    let note: NoteDocument
    let sessions: MacEditorSessions
    @Binding var clipboardBusy: Bool
    let toolbar: Toolbar
    var body: some View {
        // Coordinator callbacks outlive this visible subtree during navigation.
        // Capture the model/binding, not this view value and its session owner.
        let store = self.store, note = self.note, clipboard = $clipboardBusy
        let origin = store.workspaceID
        let editorBody = store.editorBody(draft.body)
        let current = { store.workspaceID == origin && store.selection == note.path }
        return VStack(spacing: 0) {
            if let change = store.noteDiskChange { MacRetainedNoteBanner(workspace: store, change: change) }
            toolbar
            Divider()
            if store.sourceMode { HStack { Image(systemName: "doc.plaintext"); Text("Markdown source"); Spacer(); Button("Rich text") { store.sourceMode = false } }.macFont(.caption).foregroundStyle(.secondary).padding(8).background(.quaternary.opacity(0.4)) }
            MacRichEditor(markdown: editorBody, source: store.sourceMode, editable: !note.trashed && !store.busy && !store.preparingToClose && !store.schemaMaintenanceSaving && !store.noteMovesSaving, root: store.root, path: note.path, onChange: { if current() { store.changedEditor($0) } }, onEditingIntent: { if current() { store.editingIntent() } }, onLink: { value in Task { if current() { await store.follow(value) } } }, onSourceChange: { if current() { store.sourceMode = $0 } }, onPasteError: { if current() { store.issue = $0 } }, onPasteBusy: { if current() { clipboard.wrappedValue = $0 } }, linkNotes: { store.workspaceID == origin ? store.noteSearchSources().notes : [] }, headingRequest: store.headingRequest, focusRequest: store.editorFocusRequest, onVisibleHeading: { index in if current(), store.draftState.visibleHeading != index { store.draftState.visibleHeading = index } }, commandScope: origin, isCurrent: current, readDocument: { (store.editorBody(store.body), store.sourceMode) }, sessions: sessions, createLink: { title in try await store.createLinkedNote(title: title, folder: (note.path as NSString).deletingLastPathComponent, workspaceID: origin) }).overlay(alignment: .topTrailing) { if clipboardBusy { HStack { ProgressView().controlSize(.small); Text("Preparing clipboard… Esc to cancel").macFont(.caption) }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding() } }.id(note.path + store.workspaceID.uuidString)
        }
    }
}

/// Save state, word count and editing mode, pinned to the bottom of the
/// properties pane. Only this row observes every draft change.
@MainActor private struct MacInspectorNoteStatus: View {
    @Bindable var store: MacWorkspace
    @ObservedObject var draft: MacNoteDraftState
    let note: NoteDocument
    var body: some View {
        HStack(spacing: 8) {
            Text(draft.saveStatus).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            MacWordCountLabel(markdown: store.editorBody(draft.body)).id(note.path + store.workspaceID.uuidString)
            Button(store.sourceMode ? "Source" : "Rich text") { store.sourceMode.toggle() }.buttonStyle(MacBoxButtonStyle())
        }.macFont(.caption2).foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 30)
    }
}

/// Only the collection subtree subscribes to bulk selection changes.
@MainActor private struct MacCollectionSelectionContent<Content: View>: View {
    @ObservedObject var selection: MacCollectionSelectionState
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}

/// Typing updates the field at once and filters the note list after a short
/// pause, so each keystroke does not search the whole vault.
private struct MacNoteSearchField: View {
    @Bindable var store: MacWorkspace
    @State private var text = ""
    @State private var pending: Task<Void, Never>?
    var body: some View {
        TextField("Search notes…", text: $text).textFieldStyle(.plain)
            .onAppear { text = store.query }
            .onChange(of: text) { _, value in
                pending?.cancel()
                guard !store.query.utf8.elementsEqual(value.utf8) else { return }
                // Clearing the field applies at once.
                if value.isEmpty { store.query = value; return }
                pending = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    if !Task.isCancelled, !store.query.utf8.elementsEqual(text.utf8) { store.query = text }
                }
            }
            .onChange(of: store.query) { _, value in if !text.utf8.elementsEqual(value.utf8) { pending?.cancel(); text = value } }
            .onSubmit { pending?.cancel(); if !store.query.utf8.elementsEqual(text.utf8) { store.query = text } }
    }
}

/// Refresh when the vault folder changes, with a slow fallback check. Each
/// refresh re-reads only notes whose file stamps changed.
private struct MacVaultRefresh: ViewModifier {
    @Bindable var store: MacWorkspace
    func body(content: Content) -> some View {
        content.task(id: store.root) {
            guard let root = store.root else { return }
            let watcher = MacVaultWatcher(root: root)
            defer { watcher.stop() }
            for await _ in watcher.changes {
                if Task.isCancelled { break }
                await store.refresh()
            }
        }
    }
}

/// A Liquid Glass capsule grouping title-bar buttons, matching the native
/// toolbar groups the row replaces.
private struct MacTitleBarCapsule<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, 1)
            .frame(height: 36)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// Icon buttons sized like native toolbar items.
private struct MacTitleBarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .macFont(.system(size: 15))
            .frame(minWidth: 34, minHeight: 34)
            .contentShape(Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
    }
}

/// Keeps the traffic lights vertically centred in the app-drawn title bar,
/// which is taller than the bare system title bar, and reports full screen,
/// where the buttons leave the bar. AppKit re-lays out the buttons on resize
/// and appearance changes, so they are re-positioned after each layout.
private struct MacTrafficLights: NSViewRepresentable {
    /// Bar height in window points: 52, or more when zoom enlarges the
    /// 36-point controls.
    static func height(zoom: CGFloat) -> CGFloat { max(52, (36 * zoom + 16).rounded()) }
    var height: CGFloat
    @Binding var fullScreen: Bool
    func makeNSView(context: Context) -> Probe { Probe { value in if fullScreen != value { fullScreen = value } } }
    func updateNSView(_ view: Probe, context: Context) { view.barHeight = height; view.place() }
    final class Probe: NSView {
        var barHeight: CGFloat = 52
        private static let leadingInset: CGFloat = 19
        private static let spacing: CGFloat = 23
        private let onFullScreen: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        init(onFullScreen: @escaping (Bool) -> Void) { self.onFullScreen = onFullScreen; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver); observers = []; watched = nil
            guard let window else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place() }
                })
            }
            place()
            DispatchQueue.main.async { [weak self] in self?.place() }
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
        override func layout() { super.layout(); place() }
        func place() {
            guard let window else { return }
            let full = window.styleMask.contains(.fullScreen)
            onFullScreen(full)
            guard !full, let close = window.standardWindowButton(.closeButton),
                  let bar = close.superview, let container = bar.superview else { return }
            // Grow AppKit's title-bar area to the drawn bar's height so the
            // buttons can sit at its centre, then centre them vertically.
            let height = barHeight
            if let frameView = container.superview {
                let frame = NSRect(x: 0, y: frameView.bounds.height - height, width: frameView.bounds.width, height: height)
                if container.frame != frame { container.frame = frame }
            }
            let barFrame = NSRect(x: 0, y: 0, width: container.bounds.width, height: height)
            if bar.frame != barFrame { bar.frame = barFrame }
            // Horizontally, match where a window with a toolbar puts them.
            for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                let origin = NSPoint(x: Self.leadingInset + CGFloat(index) * Self.spacing, y: ((height - button.frame.height) / 2).rounded())
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
            watch(container)
        }
        /// AppKit re-lays out the title bar on its own (resizing, key state,
        /// appearance), so re-centre whenever its frame changes.
        private weak var watched: NSView?
        private func watch(_ container: NSView) {
            guard watched !== container else { return }
            watched = container
            for view in [container] + container.subviews {
                view.postsFrameChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.placeSoon() }
                })
            }
        }
        private var queued = false
        private func placeSoon() {
            guard !queued else { return }
            queued = true
            DispatchQueue.main.async { [weak self] in self?.queued = false; self?.place() }
        }
    }
}
