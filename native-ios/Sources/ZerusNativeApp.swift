import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import UIKit
import ImageIO

@main
struct ZerusNativeApp: App {
    @StateObject private var vault = VaultStore()
    @StateObject private var external = NativeExternalNotesModel()
    @Environment(\.scenePhase) private var phase
    @StateObject private var appearance = NativeAppearanceStore.shared
    var body: some Scene {
        WindowGroup("Zerus", id: "workspace") {
            WorkspaceView().environmentObject(vault).environmentObject(external).environmentObject(appearance)
                .modifier(NativeAppearancePresentation(appearance: appearance))
                .task { await vault.restore(); await external.restore(); if phase == .active { vault.startForegroundRefresh(); external.startRefresh() } }
                .onChange(of: phase) { _, value in
                    Task {
                        if value == .active {
                            vault.startForegroundRefresh(); external.startRefresh()
                            if vault.root == nil { await vault.restore() } else { await vault.refresh() }
                        } else { vault.stopForegroundRefresh(); external.stopRefresh(); await vault.flush(); await external.flush() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                    Task { await vault.restore() }
                }
        }
    }
}

enum Accent {
    static let color = Color(uiColor: NativeThemeUIKit.accent)
    static let link = Color(uiColor: NativeThemeUIKit.link)
    static let relation = Color(uiColor: NativeThemeUIKit.relation)
    static let text = Color(uiColor: NativeThemeUIKit.text)
    static let paper = Color(uiColor: NativeThemeUIKit.surface)
    static let editor = Color(uiColor: NativeThemeUIKit.editor)
    static let card = Color(uiColor: NativeThemeUIKit.card)
    static let sidebar = Color(uiColor: NativeThemeUIKit.sidebar)
    static let sidebarCard = Color(uiColor: NativeThemeUIKit.sidebarCard)
    static let sidebarText = Color(uiColor: NativeThemeUIKit.sidebarText)
    static let secondaryText = Color(uiColor: NativeThemeUIKit.secondaryText)
}

struct NativeOpenedNote: Identifiable {
    let id = UUID()
    let navigation: NativeNoteNavigation
}

struct NativeWorkspaceEditorPresentation: Identifiable {
    let id = UUID()
    enum Content { case vault(NativeNoteNavigation), external(NativeExternalNoteSession) }
    let content: Content
    init(navigation: NativeNoteNavigation) { content = .vault(navigation) }
    init(external: NativeExternalNoteSession) { content = .external(external) }
}

enum NativeNotesRoute: Hashable {
    case allNotes, pinned, archive, folder(String), externalNotes, files, savedLinks, trash
}

private struct NativeWorkspaceNavigation: View {
    @Binding var tab: Int
    let compose: () -> Void
    private let destinations = [(0, "Notes", "square.stack", "notes"), (1, "Tasks", "checkmark.circle", "tasks"), (3, "Ask", "sparkles", "ask"), (4, "Search", "magnifyingglass", "search")]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(destinations, id: \.0) { value, title, symbol, identifier in
                Button { tab = value } label: {
                    Label { Text(title).font(.caption2.weight(.medium)) } icon: { Image(systemName: symbol).font(.system(size: 21)) }
                        .labelStyle(NativeNavigationLabelStyle())
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(tab == value ? Accent.color : Accent.text)
                        .background(tab == value ? Accent.color.opacity(0.12) : Color.clear, in: Capsule())
                }
                .accessibilityIdentifier("navigation." + identifier)
                .accessibilityAddTraits(tab == value ? .isSelected : [])
            }
            Button(action: compose) {
                Label { Text("New note").font(.caption2.weight(.medium)) } icon: { Image(systemName: "square.and.pencil").font(.system(size: 21)) }
                    .labelStyle(NativeNavigationLabelStyle())
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Accent.text)
            }.accessibilityIdentifier("navigation.newNote")
        }
        .buttonStyle(.plain)
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Accent.text.opacity(0.08), lineWidth: 1) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("workspace.navigation")
        .accessibilityLabel("Main navigation")
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

private struct NativeNavigationLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

struct WorkspaceView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var external: NativeExternalNotesModel
    @State private var externalPicker = false
    @State private var openingExternal = false
    @State private var externalJob: Task<Void, Never>?
    @State private var pendingExternal: NativeExternalNoteSession?
    @State private var tab = 0
    @State private var notesPath: [NativeNotesRoute] = [.allNotes]
    @State private var picker = false
    @State private var drivePicker = false
    @State private var driveDetails = false
    @State private var settings = false
    @State private var vaults = false
    @State private var newNote = false
    @State private var opened: NativeWorkspaceEditorPresentation?
    @State private var restoredWorkspace: UUID?
    @State private var askRequest: NativeSearchAskRequest?
    var body: some View {
        Group {
            if let recovery = vault.recovery {
                VaultRecoveryScreen(review: recovery, switchVault: { picker = true }).id(recovery.id)
            } else if vault.root == nil { welcome }
            else if let root = vault.root {
                TabView(selection: $tab) {
                    Tab("Notes", systemImage: "square.stack", value: 0) {
                        NavigationStack(path: $notesPath) {
                            LibraryView(workspaceID: vault.workspaceID, chooseVault: { vaults = true }, settings: { settings = true })
                                .navigationDestination(for: NativeNotesRoute.self) { route in
                                    Group {
                                    switch route {
                                    case .allNotes: NotesView(vault: vault, open: open, compose: { newNote = true })
                                    case .pinned: NativeNoteCollectionView(title: "Pinned", scope: .pinned, open: open)
                                    case .archive: NativeNoteCollectionView(title: "Archive", scope: .archive, open: open)
                                    case .folder(let folder): NativeNoteCollectionView(title: folder, scope: .folder(folder), open: open)
                                    case .externalNotes: NativeExternalNotesView(openVaultNote: open)
                                    case .files: NativeFilesView(workspaceID: vault.workspaceID, open: open)
                                    case .savedLinks: NativeSavedLinksView(workspaceID: vault.workspaceID, open: open)
                                    case .trash: NativeRecentlyDeletedView(workspaceID: vault.workspaceID)
                                    }
                                    }
                                    .environmentObject(vault)
                                    .environmentObject(external)
                                }
                        }.toolbar(.hidden, for: .tabBar)
                    }
                    Tab("Tasks", systemImage: "checkmark.circle", value: 1) { TasksView(open: open, library: showLibrary, settings: { settings = true }).toolbar(.hidden, for: .tabBar) }
                    Tab("Ask", systemImage: "sparkles", value: 3) {
                        Group {
                        if vault.chatStorageReady { NativeChatView(workspaceID: vault.workspaceID, chat: NativeChat.shared(for: root), searchRequest: askRequest, searchRequestHandled: { askRequest = nil }, library: showLibrary, settings: { settings = true }).id(vault.workspaceID) }
                        else if let issue = vault.chatStorageIssue { ContentUnavailableView { Label("Conversations unavailable", systemImage: "bubble.left.and.exclamationmark.bubble.right") } description: { Text(issue) } actions: { Button("Retry") { Task { await vault.prepareChatStorage() } }.accessibilityIdentifier("chat.storage.retry") } }
                        else { ProgressView("Opening conversations…") }
                        }.toolbar(.hidden, for: .tabBar)
                    }
                    Tab("Search", systemImage: "magnifyingglass", value: 4) { NativeSearchView(open: open, ask: { askRequest = $0; tab = 3 }, library: showLibrary, settings: { settings = true }).toolbar(.hidden, for: .tabBar) }
                }
                .tabViewStyle(.tabBarOnly)
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NativeWorkspaceNavigation(tab: $tab, compose: { newNote = true })
                }
                .id(vault.workspaceID)
            }
        }
        .disabled(vault.switchingVault)
        .onAppear { restoreNoteView() }
        .onChange(of: vault.loading) { _, loading in if !loading { restoreNoteView() } }
        .overlay {
            if vault.switchingVault && vault.root != nil { ProgressView("Opening your vault…").padding(25).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) }
        }
        .fileImporter(isPresented: $picker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await vault.open(url) }
            case .failure(let error): vault.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $vaults) { NativeVaultsSheet() }
        .sheet(isPresented: $drivePicker) { NativeDriveFolderBrowser(vaultPurpose: true) { selection in
            let opened = await vault.openDrive(selection); try Task.checkCancellation(); guard opened else { let message = vault.error ?? "The Drive vault could not be opened."; vault.error = nil; throw VaultFailure(message: message) }
        } }
        .sheet(isPresented: $driveDetails) { NativeDriveSyncSheet() }
        .safeAreaInset(edge: .top) {
            if let status = vault.driveStatus {
                Button { driveDetails = true } label: { HStack { Image(systemName: vault.driveSyncing ? "arrow.triangle.2.circlepath" : "externaldrive.badge.icloud"); Text(status).font(.caption).lineLimit(2); Spacer(); Image(systemName: "chevron.right") }.padding(.horizontal, 18).padding(.vertical, 8) }.accessibilityIdentifier("drive.sync.open").background(.regularMaterial)
            }
        }
        .sheet(isPresented: $newNote) { NewNoteView(workspaceID: vault.workspaceID, folder: compositionFolder, open: open) }
        .fullScreenCover(item: $opened) { request in
            Group {
                switch request.content {
                case .vault(let navigation): NativeNoteNavigationView(navigation: navigation).id(navigation.root.id)
                case .external(let session): NativeExternalEditorScreen(session: session)
                }
            }.overlay { externalProgress }
        }
        .fileImporter(isPresented: $externalPicker, allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]) { result in
            if case .success(let url) = result { openExternal(url) }
        }
        .onOpenURL { url in if url.isFileURL { openExternal(url) } }
        .overlay { externalProgress }
        .onChange(of: settings || vaults || drivePicker || driveDetails || newNote || picker || externalPicker) { _, busy in
            if !busy, let pendingExternal { self.pendingExternal = nil; presentExternal(pendingExternal) }
            else if !busy { restoreNoteView() }
        }
        .alert("Zerus needs your attention", isPresented: Binding(get: { vault.error != nil }, set: { if !$0 { vault.error = nil } })) {
            Button("OK") { vault.error = nil }
        } message: { Text(vault.error ?? "") }
        .onChange(of: vault.recovery?.id) { _, value in
            if value != nil {
                if let opened, case .vault = opened.content { self.opened = nil }
                settings = false; newNote = false
            }
        }
        .onChange(of: vault.workspaceID) { _, _ in
            restoredWorkspace = nil
            // External files have device-wide sessions. Restoring or switching
            // a vault invalidates its editor, not an independent file handoff.
            if let opened, case .vault = opened.content { self.opened = nil }
            settings = false; vaults = false; drivePicker = false; driveDetails = false; newNote = false; askRequest = nil; tab = 0; notesPath = [.allNotes]
        }
    }
    private var compositionFolder: String {
        if tab == 0, case .folder(let folder) = notesPath.last { return folder }
        return NativeNoteDefaults.load(vault.activeVaultID)
    }
    private func showLibrary() { notesPath = []; tab = 0 }
    @ViewBuilder private var externalProgress: some View {
        if openingExternal {
            VStack(spacing: 12) {
                ProgressView("Opening Markdown…")
                Button("Cancel") { externalJob?.cancel(); externalJob = nil; openingExternal = false }
            }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
    private func openExternal(_ url: URL) {
        externalJob?.cancel(); openingExternal = true
        externalJob = Task {
            defer { if !Task.isCancelled { openingExternal = false; externalJob = nil } }
            do {
                await vault.flush(); try Task.checkCancellation()
                let scope = url.startAccessingSecurityScopedResource(); defer { if scope { url.stopAccessingSecurityScopedResource() } }
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                if let root = vault.root, let note = vault.notes.first(where: { root.appendingPathComponent($0.path).resolvingSymlinksInPath().standardizedFileURL == canonical }) { open(note); return }
                let session = try await external.open(url); try Task.checkCancellation()
                if settings || vaults || drivePicker || newNote || picker || externalPicker { pendingExternal = session }
                else { presentExternal(session) }
            } catch is CancellationError {} catch { vault.error = error.localizedDescription }
        }
    }
    private func restoreNoteView() {
        guard vault.root != nil, vault.activeVaultID != nil, !vault.loading, !vault.switchingVault, vault.recovery == nil else { return }
        if let opened, case .external = opened.content {
            if restoredWorkspace != vault.workspaceID { supersedeSavedVaultView() }
            return
        }
        guard opened == nil, !openingExternal, pendingExternal == nil, !settings, !vaults, !newNote, !picker, !externalPicker, !drivePicker, !driveDetails, restoredWorkspace != vault.workspaceID else { return }
        restoredWorkspace = vault.workspaceID
        do {
            if let navigation = try NativeNoteNavigation.restore(vault: vault) {
                if navigation.originTab == 2 { showLibrary() } else { tab = navigation.originTab }; navigation.activatePersistence(); opened = .init(navigation: navigation)
            }
        } catch { vault.error = error.localizedDescription }
    }
    private func presentExternal(_ session: NativeExternalNoteSession) {
        if let opened, case .vault(let navigation) = opened.content { navigation.close() }
        supersedeSavedVaultView(); opened = .init(external: session)
    }
    private func supersedeSavedVaultView() {
        guard vault.root != nil, !vault.loading, !vault.switchingVault, let id = vault.activeVaultID else { return }
        restoredWorkspace = vault.workspaceID
        // A successful, explicit Files handoff supersedes the vault view even
        // if it arrived before vault startup could present that saved view.
        // An unreadable future record stays intact.
        if let record = try? NativeNoteResumeStore.load(id) { try? NativeNoteResumeStore.close(id, owner: record.owner) }
    }
    private func open(_ note: NoteDocument) {
        guard note.workspaceID == vault.workspaceID else { return }
        guard let session = vault.session(for: note) else {
            vault.error = "This note is no longer available, or more than one file has its note ID. Refresh Library and check the original files."
            return
        }
        restoredWorkspace = vault.workspaceID
        let navigation = NativeNoteNavigation(vault: vault, session: session, originTab: tab); navigation.activatePersistence()
        opened = NativeWorkspaceEditorPresentation(navigation: navigation)
    }
    private var welcome: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        Spacer()
                        Image(systemName: "square.and.pencil").font(.system(size: 52, weight: .light)).foregroundStyle(Accent.color)
                        Text("A space for\nyour thoughts.").font(.system(.largeTitle, design: .serif, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        Text("Your notes, connected. Your files, always yours.").font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { externalPicker = true } label: {
                            Label("Open a Markdown file", systemImage: "doc.text").fixedSize(horizontal: false, vertical: true)
                        }.accessibilityIdentifier("welcome.external")
                        Spacer()
                        VStack(spacing: 14) {
                            if let issue = vault.restorationIssue {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Couldn’t reopen your vault", systemImage: "exclamationmark.triangle").font(.headline)
                                    Text(issue).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("vault.restore.issue")
                                    Button("Try again") { Task { await vault.restore() } }.fixedSize(horizontal: false, vertical: true).disabled(vault.restoringVault || vault.loading)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                            }
                            if !vault.savedVaults.isEmpty {
                                Button { vaults = true } label: {
                                    Label("Saved vaults", systemImage: "books.vertical").fixedSize(horizontal: false, vertical: true)
                                }.accessibilityIdentifier("vaults.saved")
                            }
                            Button { picker = true } label: { Label("Open a vault in Files", systemImage: "folder").fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.vertical, 9) }.buttonStyle(.borderedProminent).accessibilityIdentifier("vault.open")
                            Button("Open a Google Drive vault", systemImage: "externaldrive.badge.icloud") { drivePicker = true }.accessibilityIdentifier("vault.drive")
                            Button { Task { await vault.createLocal() } } label: { Text("Start on this iPhone").fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.vertical, 9) }.buttonStyle(.bordered).accessibilityIdentifier("vault.create")
                            Text("Open an existing folder of Markdown notes, or create a private library on this device.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(30).padding(.bottom, 24)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .background(Accent.paper)
                .overlay { if vault.loading || vault.restoringVault { ProgressView("Opening your vault…").padding(25).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)).allowsHitTesting(false) } }
            }
            .navigationTitle("Zerus").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct NotesView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var vault: VaultStore
    let open: (NoteDocument) -> Void
    let compose: () -> Void
    @State private var settings = false
    @StateObject private var selection = NativeBulkSelection()
    @State private var query = ""
    @State private var filter = "All notes"
    @State private var filters = NativeCollectionFilters()
    private var collectionPicker: some View {
        Picker("Collection", selection: $filter) {
            ForEach(["All notes", "Pinned", "Archive"], id: \.self) { Text($0) }
        }
    }
    private var candidates: [NoteDocument] {
        vault.searchableNotes.filter { !$0.trashed && !$0.unfiledSavedLink && (filter != "Pinned" || $0.pinned) }
    }
    var body: some View {
        let collection = candidates
        let visible = filters.apply(collection, query: query, archiveOnly: filter == "Archive")
        return List {
            Section {
                Group {
                    if dynamicTypeSize.isAccessibilitySize { collectionPicker.pickerStyle(.inline) }
                    else { collectionPicker.pickerStyle(.segmented) }
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                if selection.active { NativeBulkControls(selection: selection, visible: visible) }
            }.listRowBackground(Color.clear).listRowInsets(.init(top: 6, leading: 20, bottom: 6, trailing: 20))
            if visible.isEmpty {
                emptyCollection.foregroundStyle(Accent.text).listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(visible) { note in
                        NativeBulkNoteRow(selection: selection, note: note, open: open)
                            .listRowBackground(Accent.card).contextMenu { if !selection.active { NoteActions(note: note) } }
                            .swipeActions(edge: .leading) { if !selection.active { Button(note.pinned ? "Unpin" : "Pin", systemImage: "pin") { Task { await vault.setFlag("zerus-pinned", note: note, value: !note.pinned) } }.tint(Accent.color) } }
                            .swipeActions { if !selection.active { Button("Trash", systemImage: "trash", role: .destructive) { Task { await vault.move(note, trash: true) } } } }
                    }
                } header: {
                    HStack { Text(query.isEmpty ? filter : "Results"); Spacer(); Text("\(visible.count)") }.font(.headline).foregroundStyle(Accent.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped).listSectionSpacing(.compact).scrollContentBackground(.hidden).background(Accent.paper)
        .navigationTitle("Notes")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .nativeSearchContrast("Search notes")
        .refreshable { await vault.refresh() }
        .onChange(of: query) { _, _ in selection.clear() }
        .onChange(of: filters) { _, _ in selection.clear() }
        .onChange(of: filter) { _, _ in selection.clear() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Settings") }
        }
        .sheet(isPresented: $settings) {
            SettingsView(collection: .init(filters: $filters, notes: collection, selection: selection, archiveOnly: filter == "Archive"))
        }
        .modifier(NativeBulkPresentation(selection: selection))
    }
    @ViewBuilder private var emptyCollection: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filters.activeCount > 0 {
            ContentUnavailableView {
                Label("No matching notes", systemImage: "doc.text.magnifyingglass")
            } description: { Text("Try another search or clear your filters.") }
            actions: { Button("Clear search and filters") { query = ""; filters = .init() } }
        } else if filter == "Archive" {
            ContentUnavailableView {
                Label("No archived notes", systemImage: "archivebox")
            } description: { Text("Notes you archive will appear here.") }
            actions: { Button("Show all notes") { filter = "All notes" } }
        } else if filter == "Pinned" {
            ContentUnavailableView {
                Label("No pinned notes", systemImage: "pin")
            } description: { Text("Pin a note to keep it close at hand.") }
            actions: { Button("Show all notes") { filter = "All notes" } }
        } else {
            ContentUnavailableView {
                Label("Your notes start here", systemImage: "square.and.pencil")
            } description: { Text("Capture an idea with your first note.") }
            actions: { Button("New note", action: compose) }
        }
    }
}

struct NoteRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let note: NoteDocument
    var body: some View {
        let snippet = note.snippet
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.title).font(.headline).foregroundStyle(Accent.text).lineLimit(2)
                Spacer(minLength: 8)
                if note.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Accent.color).accessibilityLabel("Pinned") }
            }
            if !snippet.isEmpty { Text(snippet).font(.subheadline).foregroundStyle(Accent.secondaryText).lineLimit(2) }
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(note.folder, systemImage: "folder").fixedSize(horizontal: false, vertical: true)
                        Text(note.modified, style: .relative).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "folder").font(.caption2)
                        Text(note.folder).lineLimit(1)
                        Text("·")
                        Text(note.modified, style: .relative).lineLimit(1)
                    }
                }
            }.font(.caption).foregroundStyle(Accent.secondaryText)
        }.padding(.vertical, 9).contentShape(Rectangle())
    }
}

struct NoteActions: View {
    @EnvironmentObject private var vault: VaultStore
    let note: NoteDocument
    var body: some View {
        if note.trashed {
            Button("Restore note", systemImage: "arrow.uturn.backward") { Task { await vault.move(note, restore: true) } }
        } else {
            Button(note.pinned ? "Unpin" : "Pin", systemImage: "pin") { Task { await vault.setFlag("zerus-pinned", note: note, value: !note.pinned) } }
            Button(note.archived ? "Unarchive" : "Archive", systemImage: "archivebox") { Task { await vault.setFlag("zerus-archived", note: note, value: !note.archived) } }
            Button("Duplicate", systemImage: "plus.square.on.square") { Task { await vault.duplicate(note) } }
            Button("Move to Recently Deleted", systemImage: "trash", role: .destructive) { Task { await vault.move(note, trash: true) } }
        }
    }
}

struct NewNoteView: View {
    let workspaceID: UUID
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var folder: String
    @State private var creating = false
    @FocusState private var focused: Bool
    let open: (NoteDocument) -> Void
    init(workspaceID: UUID, folder: String = "Inbox", open: @escaping (NoteDocument) -> Void) {
        self.workspaceID = workspaceID; self.open = open
        _folder = State(initialValue: (try? NativeNoteDefaults.folder(folder)) ?? "Inbox")
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Give your note a title", text: $title).focused($focused).accessibilityIdentifier("note.title")
                Picker("Folder", selection: $folder) { ForEach(Array(Set(["Inbox", folder] + vault.folders)).sorted(), id: \.self) { Text($0) } }.accessibilityIdentifier("note.folder")
            }
            .navigationTitle("New note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") {
                    creating = true
                    Task { if let note = await vault.createNote(title: title, folder: folder, workspace: workspaceID) { dismiss(); open(note) }; creating = false }
                }.disabled(creating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("note.create") }
            }
            .onAppear { focused = true }
        }.presentationDetents([.medium, .large])
    }
}

struct NoteEditorScreen: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @ObservedObject var session: NoteSession
    @EnvironmentObject private var navigation: NativeNoteNavigation
    let visitID: UUID
    let closeNote: () -> Void
    let openNote: (NoteDocument) -> Void
    let initialPosition: NativeReadingPosition?
    let allowsInitialFocus: Bool
    init(session: NoteSession, visitID: UUID, initialPosition: NativeReadingPosition? = nil, allowsInitialFocus: Bool = true, closeNote: @escaping () -> Void, openNote: @escaping (NoteDocument) -> Void) {
        self._session = ObservedObject(wrappedValue: session); self.visitID = visitID
        self.initialPosition = initialPosition; self.allowsInitialFocus = allowsInitialFocus
        self.closeNote = closeNote; self.openNote = openNote; self._source = State(initialValue: initialPosition?.source ?? false)
    }
    @State private var source = false
    @State private var inspector = false
    @State private var finding: NativeNoteFindSnapshot?
    @State private var revealFound: (() -> Bool)?
    @State private var findIssue: String?
    @State private var outline = false
    @State private var pendingOutlineHeading: String?
    @State private var linkPicker = false
    @State private var insertNoteLink: ((String) -> Bool)?
    @AppStorage("zerus.native.noteLinkShortcuts") private var noteLinkShortcuts = true
    @AppStorage("zerus.native.codeBlocks") private var codeBlocks = false
    @State private var movePicker = false
    @State private var renaming = false
    @State private var revisions = false
    @State private var history = false
    @State private var attachmentPicker = false
    @State private var fileHubForm = false
    @State private var attachmentPreview: NativeFileLease?
    private struct ImageScope: Hashable {
        let workspace: UUID
        let owner: UUID?
        let path: String
        let identity: String?
    }
    private struct ImageRequest: Hashable {
        let scope: ImageScope
        let references: [String]
        let resourceRevision: Int
        let retry: UUID
    }
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var loadedImageRevisions: [String: Int] = [:]
    @State private var loadedImageRetry: UUID?
    @State private var loadedImageScope: ImageScope?
    @State private var imageGeneration = UUID()
    @State private var imageRetry = UUID()
    @State private var imageLoading = false
    @State private var unavailableImages: [String] = []
    @State private var previewURL: URL?
    @State private var unresolvedReference: NoteReference?
    @State private var codeEditor: CodeEditRequest?
    @State private var tableEditor: TableEditRequest?
    @State private var tableLink: URL?
    @State private var clipboardError: String?
    @State private var clipboardPaste = false
    @State private var clipboardProviders: [NSItemProvider]?
    @State private var noteLinkIssue: String?
    @State private var clipboardBusy = false
    @State private var exporting = false
    @State private var imageManagement = false
    @StateObject private var editorActions = NativeEditorActions()
    @State private var markdownAnalysis = MarkdownText.Analysis()
    private var statusLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
    }
    private var saveStatus: some View {
        HStack {
            if clipboardBusy { ProgressView().controlSize(.mini).accessibilityLabel("Preparing clipboard") }
            if session.saving { ProgressView().controlSize(.mini).accessibilityLabel("Saving note") }
            Text(session.failure != nil ? "Draft kept" : session.dirty ? "Saving…" : vault.driveSelection == nil ? "Saved" : "Saved on iPhone")
                .foregroundStyle(session.failure == nil ? Accent.secondaryText : .orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var imageScope: ImageScope {
        ImageScope(workspace: vault.workspaceID, owner: session.document.workspaceID, path: session.document.path, identity: session.document.stableID)
    }
    private var imageRequest: ImageRequest {
        ImageRequest(scope: imageScope, references: markdownAnalysis.imageReferences(session.document.parts.body).filter { URL(string: $0)?.scheme == nil }, resourceRevision: vault.resourceRevision, retry: imageRetry)
    }
    private var images: [String: UIImage] { loadedImageScope == imageScope ? loadedImages : [:] }
    @ViewBuilder private var imageStatus: some View {
        if !source, !complex {
            if imageLoading {
                statusLayout {
                    ProgressView("Loading images…").frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("note.images.loading")
                    Button("Retry images") { imageRetry = UUID() }.frame(minHeight: 44).accessibilityIdentifier("note.images.retry")
                }.font(.caption).padding(.horizontal, 24).padding(.vertical, 6)
            } else if !unavailableImages.isEmpty {
                statusLayout {
                    Label(unavailableImages.contains(where: { images[$0] != nil }) ? "Image previews couldn’t refresh" : unavailableImages.count == 1 ? "1 image unavailable" : "\(unavailableImages.count) images unavailable", systemImage: "photo")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("note.images.unavailable")
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Button("Retry images") { imageRetry = UUID() }.frame(minHeight: 44).accessibilityIdentifier("note.images.retry")
                }.font(.caption).padding(.horizontal, 24)
            }
        }
    }
    private var complex: Bool { markdownAnalysis.requiresSource(session.document.parts.body) }
    private var editableBody: String {
        guard !source, !complex, let saved = session.document.savedLink else { return session.document.parts.body }
        return NativeSavedLink.withoutURL(session.document.parts.body, address: saved.address)
    }
    private func updateEditableBody(_ body: String) {
        if !source, !complex, let saved = session.document.savedLink { session.updateBody(NativeSavedLink.withURL(body, address: saved.address)) }
        else { session.updateBody(body) }
    }
    @ViewBuilder private var connectionDetails: some View {
        if let failure = session.failure {
            VStack(alignment: .leading, spacing: 8) {
                Text(failure).font(.caption)
                Button("Try saving again") { Task { await session.retrySave() } }.font(.caption.bold())
                Button("Keep draft as a new note and reload") {
                    Task {
                        if await vault.createNote(title: session.document.title + " recovered draft", body: session.document.parts.body, workspace: session.document.workspaceID) != nil { await session.reload() }
                    }
                }.font(.caption.bold())
            }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color.orange.opacity(0.12))
        }
        NativeSavedLinkCard(session: session)
        if session.document.fileHub != nil || NativeFrontmatter(session.document.content).entries.contains(where: { NativeFileHub.keys.contains($0.key.lowercased()) }) || !NativeFileAttachment.all(in: session.document.content).isEmpty {
            NativeFileHubCard(session: session)
        }
        if complex {
            Label("Source editing preserves this note’s advanced Markdown.", systemImage: "doc.text")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 6)
        }
        imageStatus
    }
    var body: some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    saveStatus.font(.caption)
                    Button(session.failure == nil ? "Note details" : "Review draft", systemImage: session.failure == nil ? "info.circle" : "exclamationmark.triangle") {
                        editorActions.finishEditing(); inspector = true
                    }.buttonStyle(.bordered).accessibilityIdentifier("note.details.open")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 8)
            } else {
                statusLayout {
                    Label(session.document.folder, systemImage: "folder")
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    saveStatus
                }.font(.caption).foregroundStyle(Accent.secondaryText).padding(.horizontal, 24).padding(.vertical, 10)
                connectionDetails
            }
            NativeTextEditor(markdown: editableBody, source: source || complex, images: images, onChange: updateEditableBody, onImage: { bytes in
                Task { if let path = await vault.importImage(bytes, workspace: session.document.workspaceID) { appendAttachment(path, image: true) } }
            }, onLink: handleLink, onCode: { codeEditor = $0 }, onTable: { tableEditor = $0 },
                copyFragment: vault.clipboardProvider(notePath: session.document.path),
                pasteFragment: { try await vault.importClipboard($0, workspace: session.document.workspaceID) },
                onClipboardError: { clipboardError = $0 }, onClipboardBusy: { clipboardBusy = $0 }, actions: editorActions,
                documentID: (session.document.workspaceID?.uuidString ?? "") + "|" + session.document.path, readOnly: vault.schemaSaving,
                wholeNoteMarkdown: { body in
                    var result = body
                    if !source, !complex, let saved = session.document.savedLink { result = NativeSavedLink.withURL(result, address: saved.address) }
                    if let file = session.document.fileHub { result = file.portableBody(result) }
                    return result
                }, codeBlocksEnabled: codeBlocks, noteLinkShortcuts: noteLinkShortcuts, noteLinkOptions: linkOptions, resolveNoteLink: resolveNoteLink, onNoteLinkIssue: { noteLinkIssue = $0 }, headingRequest: navigation.headingRequest(for: visitID), initialPosition: initialPosition, allowsInitialFocus: allowsInitialFocus, onPosition: { navigation.recordPosition($0, for: visitID) })
            NativeNoteLinkSuggestions(actions: editorActions)
        }
        .background(Accent.editor).foregroundStyle(Accent.text)
        .onChange(of: session.document.path) { _, _ in clipboardBusy = false }
        .alert("Clipboard", isPresented: Binding(get: { clipboardError != nil }, set: { if !$0 { clipboardError = nil } })) {
            Button("OK") { clipboardError = nil }
        } message: { Text(clipboardError ?? "") }
        .alert("Note link", isPresented: Binding(get: { noteLinkIssue != nil }, set: { if !$0 { noteLinkIssue = nil } })) {
            Button("OK") { noteLinkIssue = nil }
        } message: { Text(noteLinkIssue ?? "") }
        .navigationTitle(session.document.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: visitID == navigation.root.id ? .topBarLeading : .topBarTrailing) {
                Button { editorActions.finishEditing(); Task { await session.save(); closeNote() } } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Close note")
            }
            ToolbarItem(placement: .topBarTrailing) { Button { inspector = true } label: { Image(systemName: "sidebar.right") }.accessibilityLabel("Note information") }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if navigation.history.count > 1 { NativeNoteNavigationMenu(visitID: visitID, finishEditing: editorActions.finishEditing) }
                    Button("Find in note", systemImage: "doc.text.magnifyingglass") {
                        editorActions.finishEditing(); finding = editorActions.findSnapshot()
                    }.keyboardShortcut("f", modifiers: .command).accessibilityIdentifier("note.find")
                    Button("On this note", systemImage: "list.bullet.indent") { pendingOutlineHeading = nil; editorActions.finishEditing(); outline = true }.accessibilityIdentifier("note.outline")
                    Button("Rename note", systemImage: "pencil") { renaming = true }.accessibilityIdentifier("note.rename")
                    Button("Images", systemImage: "photo.on.rectangle") { editorActions.finishEditing(); imageManagement = true }.accessibilityIdentifier("note.images.manage")
                    if !imageRequest.references.isEmpty {
                        Button("Refresh images", systemImage: "arrow.clockwise") { imageRetry = UUID() }.accessibilityIdentifier("note.images.refresh")
                    }
                    Button("Export note", systemImage: "square.and.arrow.up") { exporting = true }.accessibilityIdentifier("note.export")
                    Toggle("Markdown source", isOn: $source).disabled(complex)
                    Menu("Clipboard", systemImage: "doc.on.clipboard") {
                        Button("Copy note", systemImage: "doc.on.doc") { editorActions.copyNote() }
                        Button("Copy Markdown", systemImage: "doc.plaintext") { editorActions.copyMarkdown() }
                        Button("Paste", systemImage: "doc.on.clipboard") { editorActions.finishEditing(); clipboardPaste = true }
                        Button("Paste plain text", systemImage: "text.alignleft") { editorActions.pastePlainText() }
                    }
                    Menu("Attach", systemImage: "paperclip") {
                        if session.document.fileHub == nil { Button("Attach a document", systemImage: "doc.badge.plus") { fileHubForm = true } }
                        Button("Attach a file", systemImage: "paperclip") { attachmentPicker = true }
                    }
                    Button("Insert note link", systemImage: "link") {
                        insertNoteLink = editorActions.coordinator?.manualNoteLink()
                        linkPicker = insertNoteLink != nil
                    }
                    Button("Move to folder", systemImage: "folder") { movePicker = true }
                    Button("Version history", systemImage: "clock") { history = true }.accessibilityIdentifier("note.history")
                    Button("Revisions", systemImage: "clock.arrow.circlepath") { revisions = true }.accessibilityIdentifier("note.revisions")
                    Button(session.document.pinned ? "Unpin" : "Pin", systemImage: "pin") { Task { await vault.setFlag("zerus-pinned", note: session.document, value: !session.document.pinned) } }
                    ShareLink(item: session.document.content, preview: SharePreview(session.document.title)) { Label("Share Markdown", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Note actions")
            }
        }
        .sheet(isPresented: $inspector) {
            NoteInspector(session: session, open: { target in inspector = false; editorActions.finishEditing(); Task { await session.save(); openNote(target) } }) {
                if dynamicTypeSize.isAccessibilitySize {
                    connectionDetails
                }
            }
        }
        .sheet(isPresented: $history) { NativeHistoryView(session: session) }
        .sheet(isPresented: $clipboardPaste, onDismiss: {
            if let providers = clipboardProviders { clipboardProviders = nil; editorActions.paste(providers) }
        }) { NativeClipboardPasteSheet { clipboardProviders = $0 } }
        .sheet(isPresented: $imageManagement) { NativeImageManagementView(session: session) }
        .sheet(isPresented: $exporting) { NativeExportView(session: session) }
        .sheet(isPresented: $renaming) { NativeNoteRenameView(session: session) }
        .sheet(isPresented: $revisions) { NativeRevisionsView(session: session, didTrashNote: { revisions = false; closeNote() }) }
        .sheet(item: $codeEditor) { CodeEditorSheet(request: $0) }
        .sheet(item: $tableEditor, onDismiss: {
            if let url = tableLink { tableLink = nil; handleLink(url) }
        }) { TableEditorSheet(request: $0, images: images, onLink: { tableLink = $0 }) }
        .sheet(item: $finding, onDismiss: {
            let reveal = revealFound; revealFound = nil
            guard session.document.workspaceID == vault.workspaceID, navigation.current.id == visitID else { return }
            if let reveal, !reveal() { findIssue = "The note changed. Open Find again to choose a current result." }
        }) { snapshot in NativeNoteFindView(snapshot: snapshot) { match in revealFound = { snapshot.reveal(match) } } }
        .alert("Find in note", isPresented: Binding(get: { findIssue != nil }, set: { if !$0 { findIssue = nil } })) {
            Button("OK") { findIssue = nil }
        } message: { Text(findIssue ?? "") }
        .sheet(isPresented: $outline, onDismiss: {
            let fragment = pendingOutlineHeading; pendingOutlineHeading = nil
            guard let fragment, session.document.workspaceID == vault.workspaceID, navigation.current.id == visitID else { return }
            editorActions.revealHeading(fragment)
        }) {
            NativeNoteOutline(headings: NativeHeadings.entries(editableBody)) { pendingOutlineHeading = $0 }
        }
        .sheet(isPresented: $linkPicker) {
            NotePicker(title: "Link to a note", multiple: false, selected: [], selectNote: { note in
                guard let current = resolveNoteLink(note.path), current == noteReference(note) else {
                    noteLinkIssue = "This note changed while you were choosing it. Open the picker again to choose its current version."; return
                }
                if insertNoteLink?(note.path) != true { noteLinkIssue = "The note or selection changed. Place the caret and choose the link again." }
                insertNoteLink = nil
            }) { _ in }
        }
        .sheet(item: $unresolvedReference) { reference in
            NoteReferenceSheet(workspaceID: vault.workspaceID, reference: reference) { target in
                unresolvedReference = nil
                if let stableID = target.stableID {
                    session.updateBody(NoteReference.retarget(session.document.parts.body, from: reference, to: stableID, heading: reference.heading(in: target)))
                }
                follow(target, heading: reference.heading(in: target))
            }
        }
        .sheet(isPresented: $movePicker) {
            NativeMoveNoteView(notePath: session.document.path, workspace: session.document.workspaceID) { movePicker = false; closeNote() }
        }
        .fileImporter(isPresented: $attachmentPicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                Task {
                    if let path = await vault.importFile(url, workspace: session.document.workspaceID) {
                        let image = ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(url.pathExtension.lowercased())
                        appendAttachment(path, image: image)
                    }
                }
            case .failure(let error): vault.error = error.localizedDescription
            }
        }
        .quickLookPreview($previewURL)
        .task(id: imageRequest) { await loadImages(imageRequest) }
        .onChange(of: scenePhase) { _, phase in
            // A pending provider must not hide changes to images already shown.
            if phase == .active { imageRetry = UUID() }
            if phase != .active { editorActions.finishEditing(); navigation.checkpoint() }
        }
        .sheet(isPresented: $fileHubForm) { NativeFileNoteForm(workspaceID: vault.workspaceID, session: session) { _ in } }
        .sheet(item: $attachmentPreview) { NativeFilePreview(lease: $0) }
        .onChange(of: session.saving) { _, saving in if !saving { navigation.checkpoint() } }
        .onDisappear { imageGeneration = UUID(); imageLoading = false; editorActions.finishEditing(); navigation.checkpoint(); Task { await session.save() } }
    }
    private func loadImages(_ request: ImageRequest) async {
        guard !Task.isCancelled, imageRequest == request else { return }
        let generation = UUID(); imageGeneration = generation
        if loadedImageScope != request.scope { loadedImages = [:]; loadedImageRevisions = [:]; loadedImageScope = request.scope }
        if loadedImageRetry != request.retry {
            // Explicit and foreground refresh must also reread loaded images,
            // including current-revision assets outside the Files inventory.
            // Keep their old bitmaps visible until successful replacement.
            loadedImageRevisions = [:]; loadedImageRetry = request.retry
        }
        loadedImages = loadedImages.filter { request.references.contains($0.key) }
        loadedImageRevisions = loadedImageRevisions.filter { request.references.contains($0.key) }
        unavailableImages = []; imageLoading = false
        guard request.scope.owner == request.scope.workspace else { return }
        func current() -> Bool { !Task.isCancelled && imageGeneration == generation && imageRequest == request }
        var stalled = Set<String>()
        // Keep the last preview visible while its replacement downloads. Only
        // successful current reads acquire the new resource revision.
        func pending() -> [String] { request.references.filter { loadedImages[$0] == nil || loadedImageRevisions[$0] != request.resourceRevision } }
        var missing = pending()
        guard !missing.isEmpty else { return }
        imageLoading = true
        defer { if imageGeneration == generation { imageLoading = false } }
        // A provider can expose a path before its bytes are ready. Retry in the
        // same open editor, with bounded backoff; never retry a departed view.
        for delay in [0.0, 0.5, 1.5, 4.0, 8.0] {
            do { if delay > 0 { try await Task.sleep(for: .seconds(delay)) } }
            catch { return }
            guard current() else { return }
            for reference in missing {
                guard current() else { return }
                let data: Data
                do {
                    guard let bytes = try await vault.imageData(reference, notePath: request.scope.path, workspace: request.scope.owner) else { continue }
                    data = bytes
                } catch NativeCoordinatedReadFailure.timedOut { stalled.insert(reference); continue }
                catch is CancellationError { return }
                catch { continue }
                guard current() else { return }
                let job = Task.detached(priority: .userInitiated) { () -> UIImage? in
                    guard !Task.isCancelled, let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), !Task.isCancelled else { return nil }
                    return UIImage(cgImage: image)
                }
                let thumbnail = await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
                guard current() else { return }
                if let thumbnail { loadedImages[reference] = thumbnail; loadedImageRevisions[reference] = request.resourceRevision }
            }
            missing = pending().filter { !stalled.contains($0) }
            if missing.isEmpty {
                if current() { unavailableImages = pending() }
                return
            }
        }
        if current() { unavailableImages = pending() }
    }
    private func follow(_ note: NoteDocument, heading: String? = nil) {
        editorActions.finishEditing()
        Task { await session.save(); if let heading { await navigation.open(note, from: visitID, heading: heading) } else { openNote(note) } }
    }
    private func linkOptions(_ query: String) -> [NativeNoteLinkOption] {
        guard vault.workspaceID == session.document.workspaceID else { return [] }
        let terms = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).split(whereSeparator: \.isWhitespace)
        let options = vault.notes.filter { !$0.trashed }.map { NativeNoteLinkOption(path: $0.path, title: $0.title) }
        return Array(options.filter { option in
            let text = (option.title + " " + option.path).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return terms.allSatisfy { text.contains($0) }
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedSame ? $0.path < $1.path : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .prefix(8))
    }
    private func resolveNoteLink(_ path: String) -> NoteReference? {
        guard vault.workspaceID == session.document.workspaceID, !vault.switchingVault,
              !vault.schemaSaving, !vault.recoverySaving, vault.recovery == nil,
              let note = vault.notes.first(where: { $0.path == path && !$0.trashed }) else { return nil }
        return noteReference(note)
    }
    private func noteReference(_ note: NoteDocument) -> NoteReference? {
        let target: String
        if let id = note.stableID, !id.contains("|"), vault.notes.filter({ !$0.trashed && $0.stableID == id }).count == 1 { target = "zerus:" + id }
        else { guard !note.path.contains("|") else { return nil }; target = note.path }
        return NoteReference(target: target, label: note.title, explicitLabel: true)
    }
    private func handleLink(_ url: URL) {
        if let fragment = NativeHeadings.localFragment(url) { editorActions.revealHeading(fragment) }
        else if ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") { openURL(url) }
        else if let reference = NoteReference(url: url) {
            let targets = vault.targets(for: reference)
            if targets.count == 1, let target = targets.first { follow(target, heading: reference.heading(in: target)) }
            else if targets.isEmpty, reference.target.hasPrefix("#") { editorActions.revealHeading(String(reference.target.dropFirst())) }
            else { unresolvedReference = reference }
        }
        else if url.scheme == "zerus-attachment" {
            let id = String(url.absoluteString.dropFirst("zerus-attachment:".count))
            guard let item = NativeFileAttachment.all(in: session.document.content).first(where: { $0.id == id }), let origin = session.document.workspaceID else { return }
            Task { do { attachmentPreview = try await vault.attachmentLease(item, workspace: origin) } catch is CancellationError {} catch { vault.error = error.localizedDescription } }
        }
        else if url.scheme == "zerus-image" {
            let reference = String(url.absoluteString.dropFirst("zerus-image:".count)).removingPercentEncoding ?? ""
            if let external = URL(string: reference), ["https", "http"].contains(external.scheme ?? "") { openURL(external) }
            else { Task { previewURL = await vault.assetURL(reference, notePath: session.document.path, workspace: session.document.workspaceID) } }
        }
        else if url.scheme == nil {
            Task {
                if let target = await vault.linkedNote(url.relativeString, notePath: session.document.path, workspace: session.document.workspaceID) { follow(target, heading: URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment) }
                else { previewURL = await vault.assetURL(url.relativeString, notePath: session.document.path, workspace: session.document.workspaceID) }
            }
        }
    }
    private func appendAttachment(_ path: String, image: Bool) {
        let name = (path as NSString).lastPathComponent.components(separatedBy: "-").dropFirst(5).joined(separator: "-")
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        session.updateBody(session.document.parts.body + "\n" + (image ? "!" : "") + "[" + (name.isEmpty ? "Attachment" : name) + "](" + escaped + ")\n")
    }
}

struct NoteInspector<Details: View>: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var session: NoteSession
    @State private var propertyEdit: NativePropertyEdit?
    @State private var relationEdit: NativeRelationEdit?
    @State private var schemaManager = false
    private var note: NoteDocument { session.document }
    let open: (NoteDocument) -> Void
    let details: Details
    init(session: NoteSession, open: @escaping (NoteDocument) -> Void, @ViewBuilder details: () -> Details) {
        self.session = session; self.open = open; self.details = details()
    }
    private var backlinks: [NoteDocument] {
        vault.notes.filter { candidate in
            candidate.id != note.id && !candidate.trashed && NoteReference.references(in: candidate.parts.body).contains { vault.targets(for: $0).contains(where: { $0.id == note.id }) }
        }
    }
    var body: some View {
        NavigationStack {
            List {
                details.buttonStyle(.borderless).listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                Section("Note") {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Folder").foregroundStyle(.secondary)
                            Text(note.folder).fixedSize(horizontal: false, vertical: true)
                        }
                    } else { LabeledContent("Folder", value: note.folder) }
                    LabeledContent("Words", value: String(note.parts.body.split(whereSeparator: \.isWhitespace).count))
                    LabeledContent("Modified") { NativeDateText(note.modified, time: true) }
                    Text(note.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                NativePropertiesSection(session: session, editing: $propertyEdit, editRelation: { relationEdit = NativeRelationEdit(notePath: note.path, name: $0.name) }, openRelated: open)
                Section("Links in this note") {
                    let ids = Set(NoteReference.references(in: note.parts.body).flatMap { vault.targets(for: $0).map(\.id) })
                    let targets = vault.notes.filter { $0.id != note.id && ids.contains($0.id) }
                    if targets.isEmpty { Text("No linked notes").foregroundStyle(.secondary) }
                    ForEach(targets) { target in Button { open(target) } label: { Label(target.title, systemImage: "arrow.up.right") } }
                }
                Section("Backlinks") {
                    if backlinks.isEmpty { Text("No incoming links yet").foregroundStyle(.secondary) }
                    ForEach(backlinks) { target in Button { open(target) } label: { Label(target.title, systemImage: "arrow.turn.down.right") } }
                }
            }.navigationTitle("Note information").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Folder definitions", systemImage: "slider.horizontal.3") { schemaManager = true }
                            .labelStyle(.iconOnly).accessibilityIdentifier("schema.manage").disabled(vault.schemaSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("note.info.done") }
                }
        }
        .sheet(item: $propertyEdit) { edit in NativePropertyEditor(edit: edit, save: edit.save) }
        .sheet(item: $relationEdit) { edit in NativeRelationEditor(edit: edit) }
        .sheet(isPresented: $schemaManager) { NativeSchemaManager(notePath: note.path) }
    }
}

struct NotePicker: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let title: String
    let multiple: Bool
    @State var selected: Set<String>
    var selectNote: ((NoteDocument) -> Void)? = nil
    @State var reference: NativeSearchDocument? = nil
    var selectReference: ((NativeSearchDocument?) -> Void)? = nil
    let done: (Set<String>) -> Void
    @State private var query = ""
    @State private var externalPicker = false
    @FocusState private var searchFocused: Bool
    var body: some View {
        NavigationStack {
            List {
                if selectReference != nil {
                    Section {
                        if let reference {
                            Label(reference.name, systemImage: "doc.text").accessibilityIdentifier("context.reference")
                            Button("Remove reference", role: .destructive) { self.reference = nil }
                        }
                        Button("Choose external file", systemImage: "doc.badge.plus") { searchFocused = false; externalPicker = true }.accessibilityIdentifier("context.external.choose")
                    } footer: { Text("Add one read-only external reference alongside vault notes. Choosing context leaves your message unsent. References are snapshots; choose the file again to refresh its text.") }
                }
                ForEach(vault.notes.filter { !$0.trashed && (query.isEmpty || $0.title.localizedStandardContains(query)) }) { note in
                Button {
                    searchFocused = false
                    if multiple { if selected.contains(note.id) { selected.remove(note.id) } else { selected.insert(note.id) } }
                    else { if let selectNote { selectNote(note) } else { done([note.id]) }; dismiss() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text(note.title).foregroundStyle(.primary); Text(note.path).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); if selected.contains(note.id) { Image(systemName: "checkmark.circle.fill") }
                    }
                }.accessibilityLabel(note.title).accessibilityValue(note.path).accessibilityIdentifier("note.picker.option." + note.path)
                }
            }.scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a note", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($searchFocused).submitLabel(.done).onSubmit { searchFocused = false }.accessibilityIdentifier("note.picker.search")
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear note search") }
                        if searchFocused { Button("Done") { searchFocused = false }.accessibilityLabel("Dismiss note search keyboard") }
                    }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20).padding(.vertical, 8).background(.bar)
                }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    if multiple { ToolbarItem(placement: .confirmationAction) { Button("Done") { done(selected); selectReference?(reference); dismiss() } } }
                }
                .sheet(isPresented: $externalPicker) { NativeExternalReferencePicker { reference = $0 } }
        }
    }
}
