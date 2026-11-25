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
    @StateObject private var editorSessions = MacEditorSessions()
    @State private var clipboardBusy = false
    @State private var attachmentImporting = false
    @State private var sidebar = true
    @State private var compactLibrary = false
    @State private var compactInspector = false
    @State private var filtersOpen = false
    @State private var prompt: MacPrompt?
    @State private var input = ""
    @State private var secondInput = ""
    @State private var typedProperty: MacPropertyEdit?
    @State private var relationName: String?
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
    @State private var bulkProperties = false
    @State private var bulkMove = false
    @State private var bulkHistory = false
    @State private var recoveryRequest: MacRecoveryRequest?
    @State private var settings = false
    @State private var exportRequest: MacExportRequest?
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        GeometryReader { geometry in
            let standalone = store.root == nil || ((store.destination == "Tasks" || store.destination == "External Notes") && !store.folderCollection)
            let layout = MacWorkspaceArrangement(width: geometry.size.width, sidebar: sidebar, inspector: store.inspector, hasNote: store.selection != nil, list: store.viewMode == "List", browsing: store.browsingCollection, standalone: standalone)
            ZStack {
                VStack(spacing: 0) {
                    if store.usingStartupCache {
                        HStack(spacing: 8) {
                            if store.startupRefreshing { ProgressView().controlSize(.small) }
                            Text(store.startupIssue == nil ? "Showing cached notes · Checking vault…" : "Showing cached notes · Could not refresh")
                            Spacer()
                            if !store.startupRefreshing { Button("Retry") { Task { await store.refresh() } } }
                        }.font(.caption).padding(.horizontal, 12).padding(.vertical, 7).background(.quaternary.opacity(0.3)).help(store.startupIssue ?? "Saved files are being checked. Your edits keep their normal conflict protection.")
                    }
                    workspaceContent(layout)
                }.accessibilityHidden(compactLibrary || compactInspector).environment(\.macEditorInteractionEnabled, !compactLibrary && !compactInspector && !store.busy).disabled(compactLibrary || compactInspector || store.busy)
                if compactLibrary || compactInspector {
                    Color.black.opacity(0.14).onTapGesture { compactLibrary = false; compactInspector = false }
                    HStack(spacing: 0) {
                        if compactInspector { Spacer(minLength: 0) }
                        VStack(spacing: 0) {
                            HStack { Text(compactLibrary ? "Library" : "Inspector").font(.headline); Spacer(); Button("Done") { compactLibrary = false; compactInspector = false }.keyboardShortcut(.cancelAction) }.padding(14)
                            Divider()
                            Group { if compactLibrary { sidebarView } else { inspectorView } }.disabled(store.busy)
                        }.frame(width: min(compactLibrary ? 280 : 320, geometry.size.width)).frame(maxHeight: .infinity).background(theme.color(.surface)).shadow(radius: 10)
                        if compactLibrary { Spacer(minLength: 0) }
                    }
                }
            }
            .toolbar { workspaceToolbar(layout, standalone: standalone) }
            .toolbar(removing: .title)
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await store.refresh() } }
        .alert("Zerus", isPresented: Binding(get: { store.issue != nil }, set: { if !$0 { store.issue = nil } })) { Button("OK") { store.issue = nil } } message: { Text(store.issue ?? "") }
        .macSheet(item: $prompt) { item in promptView(item) }
        .macSheet(isPresented: $store.showNoteRecovery) { MacNoteRecoveryView(workspace: store) }
        .macSheet(isPresented: $store.showSearch) { MacSearchView(workspace: store) }
        .macSheet(item: $store.missingNoteLink) { request in MacMissingNoteLinkView(workspace: store, request: request) }
        .macSheet(isPresented: $store.showChat) { MacChatView(store: store) }
        .macSheet(isPresented: $settings) { MacSettingsView(workspace: store) }
        .macSheet(item: $exportRequest, onDismiss: { store.editorSheetActive = false; DispatchQueue.main.async { sendEditor("focus") } }) { request in MacNoteExportView(request: request) }
        .macSheet(item: $store.settingsImport, onDismiss: { store.editorSheetActive = false; DispatchQueue.main.async { sendEditor("focus") } }) { review in MacDesktopSettingsImportView(review: review) }
        .macSheet(item: $store.printRequest, onDismiss: { store.editorSheetActive = false; DispatchQueue.main.async { sendEditor("focus") } }) { request in MacNotePrintView(request: request) }
        .macSheet(isPresented: $bulkMove) { MacNoteMovesView(workspace: store, paths: store.selectedPaths) }
        .macSheet(isPresented: $bulkProperties) { MacBulkEditor(store: store, paths: store.selectedPaths) }
        .macSheet(isPresented: $bulkHistory) { MacBulkHistoryView(store: store) }
        .macSheet(item: $recoveryRequest) { MacRecoveryView(workspace: store, request: $0) }
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
        if store.root == nil {
            MacZoomSplitView { if layout.sidebar { sidebarView.frame(minWidth: 185, idealWidth: 218, maxWidth: 240) }; welcome.frame(maxWidth: .infinity, maxHeight: .infinity) }
        } else if store.destination == "External Notes" && !store.folderCollection {
            MacZoomSplitView { if layout.sidebar { sidebarView.frame(minWidth: 185, idealWidth: 218, maxWidth: 240) }; MacExternalNotesView(workspace: store).frame(maxWidth: .infinity) }
        } else if store.destination == "Tasks" && !store.folderCollection {
            MacZoomSplitView { if layout.sidebar { sidebarView.frame(minWidth: 185, idealWidth: 218, maxWidth: 240) }; MacTasksView(store: store).frame(maxWidth: .infinity) }
        } else {
            MacWorkspacePanes(layout: layout, interactionEnabled: !compactLibrary && !compactInspector && !store.busy, library: sidebarView, collection: collectionView, editor: editorView, inspector: inspectorView)
        }
    }
    @ToolbarContentBuilder private func workspaceToolbar(_ layout: MacWorkspaceArrangement, standalone: Bool) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                if layout.sidebar { sidebar = false }
                else if layout.canInlineSidebar { sidebar = true }
                else { compactInspector = false; compactLibrary.toggle() }
            } label: { Image(systemName: "sidebar.left") }.disabled(store.busy).help("Show or hide folders").modifier(MacToolbarZoom())
        }
        ToolbarItem(placement: .navigation) {
            MacTabBar(store: store, available: tabBarWidth(layout, standalone: standalone)).modifier(MacToolbarZoom())
        }.sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .primaryAction) {
            if !standalone && (layout.singleColumn || store.viewMode != "List") && store.selection != nil {
                Button {
                    store.browsingCollection.toggle()
                } label: { Label(store.browsingCollection ? "Back to note" : "Notes", systemImage: store.browsingCollection ? "doc.text" : "list.bullet") }.disabled(clipboardBusy || store.busy).help(store.browsingCollection ? "Return to the selected note" : "Browse notes").modifier(MacToolbarZoom())
            }
            if store.busy { ProgressView().controlSize(.small).modifier(MacToolbarZoom()) }
            Button { store.showSearch = true } label: { Image(systemName: "magnifyingglass") }.disabled(store.busy).help("Search everything (⌘F)").modifier(MacToolbarZoom())
            Button { Task { await store.createNote() } } label: { Image(systemName: "square.and.pencil") }.disabled(store.root == nil || store.busy).help("New note").modifier(MacToolbarZoom())
            Button { toggleInspector(layout) } label: { Image(systemName: "sidebar.right") }.disabled(store.selection == nil || store.busy).help("Show or hide inspector").modifier(MacToolbarZoom())
        }
    }
    /// The tab strip is one toolbar item, so it is sized from the window width
    /// minus the traffic lights and the other toolbar items. Overestimating the
    /// reserve only leaves extra space before the trailing buttons; an item that
    /// is too wide would push them into the toolbar's overflow menu.
    private func tabBarWidth(_ layout: MacWorkspaceArrangement, standalone: Bool) -> CGFloat {
        var reserved: CGFloat = 150 + 150
        if !standalone && (layout.singleColumn || store.viewMode != "List") && store.selection != nil { reserved += 130 }
        if store.busy { reserved += 36 }
        return layout.width - reserved / MacInterfaceZoom.factor(interfaceZoom)
    }
    private func toggleInspector(_ layout: MacWorkspaceArrangement) {
        guard !store.busy, store.selection != nil else { return }
        if layout.canInlineInspector { compactInspector = false; store.inspector.toggle() }
        else { compactLibrary = false; compactInspector.toggle() }
    }
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Button("Open Vault…") { store.chooseVault() }
                Button("Note recovery drafts…") { store.showNoteRecovery = true }.disabled(store.root == nil)
                Divider()
                ForEach(store.recentVaults, id: \.self) { path in Button(URL(fileURLWithPath: path).lastPathComponent) { Task { await store.openRecentVault(path) } } }
            } label: { Label(store.vaultTitle, systemImage: "books.vertical.fill").font(.system(size: 14, weight: .semibold)) }.menuStyle(.borderlessButton).padding(.horizontal, 8).padding(.top, 14)
            Button { store.showSearch = true } label: {
                HStack { Image(systemName: "magnifyingglass"); Text("Search everything"); Spacer(); Text("⌘F").font(.caption) }.foregroundStyle(theme.color(.sidebarFg).opacity(0.72)).padding(8).background(theme.color(.sidebarFg).opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(MacBoxButtonStyle()).padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([("All Notes", "doc.text"), ("Tasks", "checkmark.square"), ("Links", "link"), ("Files", "doc.on.doc"), ("External Notes", "arrow.up.right.square"), ("Pinned", "pin")], id: \.0) { name, icon in navigationRow(name, icon: icon) }
                    HStack { Text("Types").font(.caption).foregroundStyle(.secondary); Spacer(); Button { ask(.folder) } label: { Image(systemName: "plus") }.buttonStyle(MacBoxButtonStyle()).help("Create folder") }.padding(.horizontal, 8).padding(.top, 15)
                    if let message = store.folderIconIssue { Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8) }
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
            Button { store.toggleFolder(folder) } label: { Image(systemName: store.collapsedFolders.contains(folder) ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold)).frame(width: 20).frame(maxHeight: .infinity).contentShape(Rectangle()) }
                .buttonStyle(MacBoxButtonStyle()).disabled(!children).opacity(children ? 1 : 0)
                .accessibilityLabel((store.collapsedFolders.contains(folder) ? "Expand " : "Collapse ") + folder)
            Button { compactLibrary = false; store.navigateFolder(folder) } label: {
                HStack(spacing: 7) {
                    MacFolderIcon(value: store.folderIcon(folder)).foregroundStyle(store.folderCollection && store.destination == folder ? macAccent : .secondary).accessibilityHidden(true)
                    Text((folder as NSString).lastPathComponent).lineLimit(1)
                    Spacer()
                    if store.keptFolders.contains(folder) { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.tertiary) }
                    Text("\(store.noteCount(in: folder))").font(.caption).foregroundStyle(.tertiary)
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
            .contextMenu { Button("Open in tab") { store.navigate(name, newTab: true) } }
    }
    private var collectionView: some View {
        let notes = store.collection
        return VStack(spacing: 0) {

            HStack(spacing: 8) {
                Text(store.destination).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Menu { ForEach(["List", "Gallery", "Kanban", "Table", "Calendar"], id: \.self) { value in Button(value) { Task { await store.updateCollectionLayout(store.collectionLayout, mode: value) } } }; if store.folderCollection { Divider(); Toggle("Hide subtype notes", isOn: $store.hideSubtypes) } } label: { Text(store.viewMode) }.fixedSize().menuStyle(.borderlessButton)
                MacCollectionSelectionContent(selection: store.collectionSelection) {
                    Button { store.selecting.toggle() } label: { Image(systemName: "checkmark.circle").accessibilityHidden(true); Text("Select") }.buttonStyle(MacBoxButtonStyle()).accessibilityAddTraits(store.selecting ? .isSelected : []).help("Select notes for bulk actions")
                }
                Button { if !store.folderCollection && store.destination == "Files" { addDocument() } else if !store.folderCollection && store.destination == "Links" { ask(.link) } else { Task { await store.createNote() } } } label: { Image(systemName: "plus") }.buttonStyle(MacBoxButtonStyle())
            }.padding(.horizontal, 14).frame(height: 46)
            Divider()
            VStack(spacing: 7) {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.text).opacity(0.72)); MacNoteSearchField(store: store) }.foregroundStyle(theme.color(.text)).padding(7).background(theme.color(.editorBg), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.color(.text).opacity(0.15)))
                HStack {
                Button { filtersOpen.toggle() } label: {
                    HStack { Image(systemName: "line.3.horizontal.decrease"); Text("Sort & filter"); Spacer(); if store.filters.activeCount > 0 { Text("\(store.filters.activeCount)").font(.caption).foregroundStyle(.white).padding(.horizontal, 5).background(macAccent, in: Capsule()) }; Image(systemName: "chevron.down").font(.caption) }.padding(7).contentShape(Rectangle())
                }.buttonStyle(MacBoxButtonStyle()).overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary)).macPopover(isPresented: $filtersOpen) { filterView }
                if store.folderCollection { MacSavedViewsMenu(store: store) }
                }
            }.padding(.horizontal, 12).padding(.bottom, 10)
            Divider()
            if store.destination == "Trash" && !store.folderCollection { Button("Recently deleted…") { trashBrowser = true }.font(.caption).padding(9) }
            MacCollectionSelectionContent(selection: store.collectionSelection) {
                if store.selecting || !store.selectedPaths.isEmpty { bulkBar }
            }
            if store.destination == "Files" && !store.folderCollection && store.viewMode == "List" { filesView.modifier(MacCollectionKeyboard(store: store)) }
            else if store.viewMode != "List" { alternateCollection }
            else {
                MacProgressiveNoteList(notes: notes, scope: .init(workspace: store.workspaceID, destination: store.destination, folder: store.folderCollection, query: store.query, filters: store.filters, hideSubtypes: store.hideSubtypes), row: noteRow)
                    .modifier(MacCollectionKeyboard(store: store))
                if notes.isEmpty { ContentUnavailableView.search(text: store.query).font(.caption).frame(maxHeight: .infinity) }
            }
            HStack { Text("\(notes.count) notes"); Spacer() }.font(.caption2).foregroundStyle(.secondary).padding(9)
        }.background(theme.color(.surface))
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
                    if note.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(macAccent) }
                    Text(note.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 3)
                    Text(note.modified, format: .dateTime.month(.abbreviated).day()).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                MacCollectionExcerpt(note: note, workspaceID: store.workspaceID, lines: 2).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }.padding(.horizontal, 15).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(store.selectedPaths.contains(note.path) ? macAccent.opacity(0.13) : store.selection == note.path ? theme.color(.editorBg) : .clear)
                .overlay(alignment: .leading) { if store.selection == note.path { Rectangle().fill(macAccent).frame(width: 3) } }
        }.buttonStyle(MacBoxButtonStyle()).accessibilityAddTraits(store.selectedPaths.contains(note.path) ? .isSelected : []).overlay(MacAlternateOpen { Task { await store.openNote(note.path, newTab: true) } }.accessibilityHidden(true)).contentShape(Rectangle()).contextMenu { noteMenu(note) }.overlay(alignment: .bottom) { Divider().opacity(0.4) }
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
        }; Spacer() }.font(.caption).padding(9)
    }
    private var filterView: some View { MacFilterPanel(filters: Binding(get: { store.filters }, set: store.changeCollectionFilters), notes: store.notes, schema: store.schema, showsFolders: !store.folderCollection) }
    private var editorView: some View {
        VStack(spacing: 0) {
            if let note = store.current {
                HStack(spacing: 14) {
                    Button { Task { await store.historyStep(-1) } } label: { Image(systemName: "chevron.left") }
                    Button { Task { await store.historyStep(1) } } label: { Image(systemName: "chevron.right") }
                    Text(note.folder.replacingOccurrences(of: "/", with: " / ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { store.showChat = true } label: { Label("AI chat", systemImage: "sparkles") }.foregroundStyle(macAccent)
                    Menu {
                        noteMenu(note); Divider()
                        Button("Organization history…") { bulkHistory = true }
                        Button("Export…") {
                            guard let root = store.root else { return }
                            exportRequest = MacExportRequest(note: note, body: store.body, root: root)
                            store.editorSheetActive = true
                        }
                        Button("Print…") { store.presentPrint() }.disabled(!store.canPrintCurrentNote)
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }.buttonStyle(MacBoxButtonStyle()).padding(.horizontal, 18).frame(height: 44)
                Divider()
                if note.fileHub != nil && !note.trashed {
                    MacFileHubPane(workspace: store, note: note) { noteWritingArea(note) }.id(note.path + store.workspaceID.uuidString)
                } else if note.savedLink != nil && !note.trashed {
                    MacSavedLinkPane(store: store, note: note) { noteWritingArea(note) }.id(note.path + store.workspaceID.uuidString)
                } else { noteWritingArea(note) }
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
        }.buttonStyle(MacBoxButtonStyle()).font(.system(size: 12)).padding(.horizontal, 14) }.frame(height: 35)
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
                        Text(issue).font(.system(size: 12)).foregroundStyle(.red)
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
        }.background(theme.color(.surface))
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
                if store.revisionIssue != nil { Label("Revisions unavailable — browse for details", systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 6) }
                MacInspectorRevisionCard(current: current, count: live.count, browse: {
                    if let path = store.selection { recoveryRequest = .init(workspaceID: store.workspaceID, path: path, selectedID: current?.id) }
                }, history: {
                    if let path = store.selection { recoveryRequest = .init(workspaceID: store.workspaceID, path: path, history: true) }
                })
                if store.historyIssue != nil { Label("History unavailable — browse for details", systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 6) }
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
            ForEach(relations) { definition in
                let targets = frontmatter.entry(definition.name)?.value?.selections ?? []
                VStack(alignment: .leading, spacing: 4) {
                    MacInspectorGroupHeader(title: definition.name, count: targets.count) { relationName = definition.name }
                    if targets.isEmpty {
                        Text("None linked").font(.system(size: 12)).foregroundStyle(.quaternary).padding(.horizontal, 6)
                    }
                    ForEach(Array(targets.enumerated()), id: \.offset) { _, text in
                        let reference = NoteReference(wikilink: "[[" + text + "]]")
                        let found = reference?.targets(in: store.notes) ?? []
                        let target = found.count == 1 ? found[0] : nil
                        MacInspectorNoteLink(title: target?.title ?? (reference?.explicitLabel == true ? reference!.label : text), detail: target?.folder, available: target != nil) {
                            if let target { Task { await store.openNote(target.path) } }
                        }
                    }
                }.padding(.bottom, 6)
            }
            VStack(alignment: .leading, spacing: 4) {
                MacInspectorGroupHeader(title: "Backlinks", count: store.backlinks.count, icon: "arrow.uturn.left")
                if store.backlinks.isEmpty { Text("No notes link here yet").font(.system(size: 12)).foregroundStyle(.quaternary).padding(.horizontal, 6) }
                ForEach(store.backlinks) { linked in
                    MacInspectorNoteLink(title: linked.title, detail: linked.folder) { Task { await store.openNote(linked.path) } }
                }
            }
        }
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
        let represented = Set(store.notes.filter { !$0.trashed && $0.fileHub?.kind == .vault }.compactMap { $0.fileHub?.path })
        let rawFiles = store.files.filter { !represented.contains($0) && (store.query.isEmpty || $0.localizedCaseInsensitiveContains(store.query)) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack { Button("Add document…") { addDocument() }; Spacer(); Button("Locations…") { fileLocations = true } }.font(.caption).padding(12)
                ForEach(store.collection) { note in noteRow(note) }
                if !rawFiles.isEmpty { Text("Other vault files").font(.caption.bold()).foregroundStyle(.secondary).padding(12) }
                ForEach(rawFiles, id: \.self) { path in
                    HStack {
                        Button { if let root = store.root { filePreview = root.appendingPathComponent(path) } } label: { Label((path as NSString).lastPathComponent, systemImage: "doc").lineLimit(2) }.buttonStyle(MacBoxButtonStyle())
                        Spacer()
                        Button { if let root = store.root { addDocument(root.appendingPathComponent(path)) } } label: { Image(systemName: "note.text.badge.plus") }.buttonStyle(MacBoxButtonStyle()).help("Add notes for " + (path as NSString).lastPathComponent)
                    }.padding(12)
                }
            }
        }
    }
    private func addDocument(_ source: URL? = nil) {
        Task { do { let request = try await store.prepareFileHub(); hubInitialSource = source; fileHubRequest = request } catch { store.issue = error.localizedDescription } }
    }
    private var welcome: some View {
        VStack(spacing: 18) { Image(systemName: "books.vertical").font(.system(size: 48)).foregroundStyle(macAccent); Text("A little space for everything").font(.largeTitle.bold()); Text("Open a folder of Markdown files to start writing.").foregroundStyle(.secondary); MacPendingDesktopFiles(opener: store.desktopFiles); Button("Open Vault…") { store.chooseVault() }.buttonStyle(.borderedProminent); ForEach(store.recentVaults, id: \.self) { path in Button(URL(fileURLWithPath: path).lastPathComponent) { Task { await store.openRecentVault(path) } } } }.padding(40)
    }
    private func ask(_ value: MacPrompt, value text: String = "") { input = text; secondInput = ""; prompt = value }
    private func promptView(_ kind: MacPrompt) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(kind.title).font(.headline)
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
            if store.sourceMode { HStack { Image(systemName: "doc.plaintext"); Text("Markdown source"); Spacer(); Button("Rich text") { store.sourceMode = false } }.font(.caption).foregroundStyle(.secondary).padding(8).background(.quaternary.opacity(0.4)) }
            MacRichEditor(markdown: editorBody, source: store.sourceMode, editable: !note.trashed && !store.busy && !store.preparingToClose && !store.schemaMaintenanceSaving && !store.noteMovesSaving, root: store.root, path: note.path, onChange: { if current() { store.changedEditor($0) } }, onEditingIntent: { if current() { store.editingIntent() } }, onLink: { value in Task { if current() { await store.follow(value) } } }, onSourceChange: { if current() { store.sourceMode = $0 } }, onPasteError: { if current() { store.issue = $0 } }, onPasteBusy: { if current() { clipboard.wrappedValue = $0 } }, linkNotes: { store.workspaceID == origin ? store.noteSearchSources().notes : [] }, headingRequest: store.headingRequest, focusRequest: store.editorFocusRequest, onVisibleHeading: { index in if current(), store.draftState.visibleHeading != index { store.draftState.visibleHeading = index } }, commandScope: origin, isCurrent: current, readDocument: { (store.editorBody(store.body), store.sourceMode) }, sessions: sessions, createLink: { title in try await store.createLinkedNote(title: title, folder: (note.path as NSString).deletingLastPathComponent, workspaceID: origin) }).overlay(alignment: .topTrailing) { if clipboardBusy { HStack { ProgressView().controlSize(.small); Text("Preparing clipboard… Esc to cancel").font(.caption) }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding() } }.id(note.path + store.workspaceID.uuidString)
            Divider()
            HStack { Text(draft.saveStatus); Spacer(); MacWordCountLabel(markdown: editorBody).id(note.path + origin.uuidString); Button(store.sourceMode ? "Source" : "Rich text") { store.sourceMode.toggle() }.buttonStyle(MacBoxButtonStyle()) }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 26)
        }
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
