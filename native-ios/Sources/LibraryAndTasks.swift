import SwiftUI
import QuickLook

struct LibraryView: View {
    let workspaceID: UUID
    @Environment(\.nativeThemes) private var palettes
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var vault: VaultStore
    let chooseVault: () -> Void
    let settings: () -> Void
    @State private var expandedFolders: Set<String> = []
    @State private var newFolder: NativeFolderCreation?
    @State private var iconFolder: NativeFolderDestination?
    @State private var renameFolder: NativeFolderDestination?
    @State private var trashFolder: NativeFolderTrashRequest?
    private var libraryChrome: ColorScheme? {
        guard let palette = palettes[scheme == .dark ? .dark : .light] else { return nil }
        return NativeThemePalette.isDark(palette.sidebarBg) ? .dark : .light
    }
    var body: some View {
        let folderNotes = NativeCollectionFilters().apply(vault.searchableNotes.filter(\.regularCollectionNote))
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "books.vertical").font(.title).foregroundStyle(Accent.color).accessibilityHidden(true)
                    Text(vault.vaultName).font(.system(.title2, design: .serif))
                    Text("A place for everything you keep.").font(.subheadline).foregroundStyle(Accent.secondaryText)
                }.padding(.vertical, 12)
                Button("Vaults", systemImage: "folder.badge.gearshape", action: chooseVault).accessibilityIdentifier("library.vaults")
            }.listRowBackground(Accent.sidebarCard)
            Section {
                NavigationLink(value: NativeNotesRoute.allNotes) { Label("All notes", systemImage: "square.stack") }.accessibilityIdentifier("library.notes")
                NavigationLink(value: NativeNotesRoute.externalNotes) { Label("External notes", systemImage: "doc.text") }.accessibilityIdentifier("library.external")
                NavigationLink(value: NativeNotesRoute.files) { Label("Files", systemImage: "doc") }.accessibilityIdentifier("library.files")
                NavigationLink(value: NativeNotesRoute.savedLinks) { Label("Saved links", systemImage: "link") }.accessibilityIdentifier("library.links")
                NavigationLink(value: NativeNotesRoute.pinned) { Label("Pinned", systemImage: "pin") }
                NavigationLink(value: NativeNotesRoute.archive) { Label("Archive", systemImage: "archivebox") }
                NavigationLink(value: NativeNotesRoute.trash) { Label("Recently Deleted", systemImage: "trash") }.accessibilityIdentifier("library.trash")
            } header: { Text("Collections").foregroundStyle(Accent.sidebarText.opacity(0.72)) }.listRowBackground(Accent.sidebarCard)
            Section {
                ForEach(NativeLibraryFolderRow.visible(vault.folders, expanded: expandedFolders)) { row in
                    let folder = row.path
                    HStack(spacing: 0) {
                    if row.hasChildren {
                        Button {
                            if !expandedFolders.insert(folder).inserted { expandedFolders.remove(folder) }
                        } label: {
                            Image(systemName: expandedFolders.contains(folder) ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Accent.sidebarText.opacity(0.6))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(expandedFolders.contains(folder) ? "Collapse" : "Expand") \(folder)")
                        .accessibilityValue(expandedFolders.contains(folder) ? "Expanded" : "Collapsed")
                        .accessibilityIdentifier("library.folder.toggle.\(folder)")
                    } else {
                        Color.clear.frame(width: 44, height: 1).accessibilityHidden(true)
                    }
                    NavigationLink(value: NativeNotesRoute.folder(folder)) {
                        let count = folderNotes.filter { $0.folder == folder || $0.folder.hasPrefix(folder + "/") }.count
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 6) {
                                Label { Text(row.name) } icon: { NativeFolderGlyph(value: vault.folderIcons[folder]) }
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(count) \(count == 1 ? "note" : "notes")")
                                    .font(.caption).foregroundStyle(Accent.secondaryText)
                            }
                        } else {
                            HStack { Label { Text(row.name) } icon: { NativeFolderGlyph(value: vault.folderIcons[folder]) }; Spacer(); Text("\(count)").foregroundStyle(Accent.secondaryText) }
                        }
                    }
                    Menu {
                        Button("Move up", systemImage: "arrow.up") { vault.reorderFolder(folder, direction: -1, workspace: workspaceID) }
                            .disabled(NativeFolderOrder.adjacent(folder, in: vault.folders, direction: -1) == nil)
                        Button("Move down", systemImage: "arrow.down") { vault.reorderFolder(folder, direction: 1, workspace: workspaceID) }
                            .disabled(NativeFolderOrder.adjacent(folder, in: vault.folders, direction: 1) == nil)
                        Button("Change icon", systemImage: "face.smiling") { iconFolder = .init(path: folder) }
                        if vault.folderPaths.contains(folder) {
                            Button("Rename folder", systemImage: "pencil") { renameFolder = .init(path: folder) }
                            Button("Delete folder", systemImage: "trash", role: .destructive) { trashFolder = .trash(folder) }
                        }
                        Button("Add subfolder", systemImage: "folder.badge.plus") { newFolder = .init(parent: folder == "Inbox" && !vault.folderPaths.contains("Inbox") ? "" : folder) }
                    } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Actions for \(folder)").buttonStyle(.borderless)
                    }
                    .padding(.leading, CGFloat(row.depth) * 16)
                }
                Button("New folder", systemImage: "folder.badge.plus") { newFolder = .init(parent: "") }.accessibilityIdentifier("library.folder.new")
                if let issue = vault.folderIssue { Text(issue).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Folders").foregroundStyle(Accent.sidebarText.opacity(0.72)) }.listRowBackground(Accent.sidebarCard)
        }
        .scrollContentBackground(.hidden).background(Accent.sidebar).foregroundStyle(Accent.sidebarText)
        .navigationTitle("Library").toolbarColorScheme(libraryChrome, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(action: settings) { Image(systemName: "ellipsis") }.accessibilityLabel("Settings") } }
        .refreshable { await vault.refresh() }
        .onChange(of: vault.activeVaultID) { _, _ in expandedFolders.removeAll() }
        .sheet(item: $newFolder) { request in NativeNewFolderView(parent: request.parent, workspaceID: workspaceID) }
        .sheet(item: $iconFolder) { request in NativeFolderIconView(folder: request.path, workspaceID: workspaceID) }
        .sheet(item: $renameFolder) { request in NativeFolderRenameView(folder: request.path, workspaceID: workspaceID) }
        .sheet(item: $trashFolder) { request in NativeFolderTrashReview(request: request, workspaceID: workspaceID) }
    }

}

private struct NativeLibraryFolderRow: Identifiable {
    let path: String
    let depth: Int
    let hasChildren: Bool
    var id: String { path }
    var name: String { String(path.split(separator: "/").last ?? "") }

    static func visible(_ folders: [String], expanded: Set<String>) -> [Self] {
        var paths = Set<String>()
        var parents = Set<String>()
        for folder in folders {
            let parts = folder.split(separator: "/")
            for depth in parts.indices {
                let path = parts.prefix(depth + 1).joined(separator: "/")
                paths.insert(path)
                if depth < parts.count - 1 { parents.insert(path) }
            }
        }
        return NativeFolderOrder.sorted(paths, order: folders).compactMap { path in
            let parts = path.split(separator: "/")
            for depth in 1..<parts.count {
                guard expanded.contains(parts.prefix(depth).joined(separator: "/")) else { return nil }
            }
            return Self(path: path, depth: parts.count - 1, hasChildren: parents.contains(path))
        }
    }
}

struct NativeCollectionSettingsContext {
    let filters: Binding<NativeCollectionFilters>
    let notes: [NoteDocument]
    var selection: NativeBulkSelection? = nil
    var archiveOnly = false
    var fileTypes = false
    var otherFiles: [String] = []
}

private struct NativeCollectionSettingsSection: View {
    @EnvironmentObject private var vault: VaultStore
    let context: NativeCollectionSettingsContext
    @State private var history = false
    var body: some View {
        Section("Notes") {
            NativeCollectionFilterButton(filters: context.filters, notes: context.notes, archiveOnly: context.archiveOnly, fileTypes: context.fileTypes, otherFiles: context.otherFiles)
            if let selection = context.selection { NativeCollectionSelectionButton(selection: selection) }
            Button("Recent actions", systemImage: "clock.arrow.circlepath") { history = true }.accessibilityIdentifier("bulk.history")
        }
        .sheet(isPresented: $history) { NativeBulkHistoryView(workspaceID: vault.workspaceID) }
    }
}

private struct NativeCollectionSelectionButton: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var selection: NativeBulkSelection
    var body: some View {
        Button(selection.active ? "Done selecting" : "Select notes", systemImage: "checkmark.circle") {
            if selection.active { selection.finish() } else { selection.active = true }
            dismiss()
        }.accessibilityIdentifier("bulk.select")
    }
}

struct NativeLibraryButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "chevron.left") }
            .accessibilityLabel("Back to Library").accessibilityIdentifier("navigation.library")
    }
}

struct SettingsView: View {
    var collection: NativeCollectionSettingsContext? = nil
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var aiGuidance = false
    @State private var aiLimits = false
    @State private var aiWorkflows = false
    var body: some View {
        NavigationStack {
            Form {
                if let collection { NativeCollectionSettingsSection(context: collection) }
                Section {
                    LabeledContent("Vault", value: vault.vaultName)
                    NavigationLink { NativeVaultsView() } label: { Label("Vaults", systemImage: "books.vertical") }.accessibilityIdentifier("settings.vaults")
                    if supportsMultipleWindows { Button("Open another window", systemImage: "macwindow.badge.plus") { openWindow(id: "workspace") }.accessibilityIdentifier("workspace.newWindow") }
                    Button("Refresh files", systemImage: "arrow.clockwise") { Task { await vault.refresh() } }
                    NavigationLink { NativeFileLocationsView(workspaceID: vault.workspaceID) } label: { Label("File locations", systemImage: "folder.badge.gearshape") }.accessibilityIdentifier("settings.fileLocations")
                    if vault.driveSelection != nil { NavigationLink { NativeDriveSyncView() } label: { Label("Google Drive sync", systemImage: "arrow.triangle.2.circlepath") }.accessibilityIdentifier("settings.driveSync") }
                    NavigationLink { NativeHistorySettingsView(workspaceID: vault.workspaceID) } label: { Label("Version history", systemImage: "clock") }.accessibilityIdentifier("settings.history")
                    NavigationLink { RecoveryCopiesView() } label: { Label("Recovery copies", systemImage: "clock.arrow.circlepath") }.accessibilityIdentifier("recovery.copies")
                    NavigationLink { NativeRelationRepairView() } label: { Label("Review legacy relations", systemImage: "point.3.connected.trianglepath.dotted") }.accessibilityIdentifier("relations.repair")
                } header: { Text("Your workspace") } footer: {
                    if supportsMultipleWindows { Text("All windows share the active vault. Choosing another vault updates every window.") }
                }
                if let id = vault.activeVaultID {
                    Section {
                        NavigationLink { NativeGeneralSettingsView(vaultID: id, workspaceID: vault.workspaceID) }
                            label: { Label("General", systemImage: "gearshape") }.accessibilityIdentifier("settings.general")
                    }
                }
                Section {
                    NavigationLink { NativeAppearanceView() } label: { Label("Appearance", systemImage: "paintpalette") }.accessibilityIdentifier("settings.appearance")
                }
                Section("AI") {
                    Button("Workflows", systemImage: "list.bullet.rectangle") { aiWorkflows = true }.accessibilityIdentifier("settings.aiWorkflows")
                    Button("AI limits", systemImage: "gauge.with.dots.needle.33percent") { aiLimits = true }.accessibilityIdentifier("settings.aiLimits")
                    Button("AI instructions and memory", systemImage: "text.bubble") { aiGuidance = true }.accessibilityIdentifier("settings.aiGuidance")
                }
                Section {
                    LabeledContent("Version", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")")
                    NavigationLink("Open-source licenses") { NativeLicensesView() }.accessibilityIdentifier("settings.licenses")
                } header: { Text("Zerus Native · Preview") } footer: { Text("This native preview opens Files vaults and includes Ask, reviewed AI edits and on-device dictation. Direct Google Drive sign-in and remaining mobile features are still being ported. The existing Zerus app remains available alongside it.") }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $aiGuidance) { NativeAgentGuidanceView(workspaceID: vault.workspaceID) }
                .sheet(isPresented: $aiWorkflows) { NativeAgentWorkflowsView(workspaceID: vault.workspaceID) }
                .sheet(isPresented: $aiLimits) { NativeAgentLimitsView(workspaceID: vault.workspaceID) }
        }
    }
}


private struct NativeLicensesView: View {
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "The licenses could not be opened." }
        return text
    }
    var body: some View {
        ScrollView { Text(notices).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
            .navigationTitle("Open-source licenses").navigationBarTitleDisplayMode(.inline)
    }
}
