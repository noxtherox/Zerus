import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct NativeFileShare: UIViewControllerRepresentable {
    let lease: NativeFileLease
    /// Keep the snapshot alive until the system reports that sharing finished,
    /// including cancellation. The presenting note/window may close earlier.
    static func controller(for lease: NativeFileLease) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [lease.url], applicationActivities: nil)
        var retained: NativeFileLease? = lease
        controller.completionWithItemsHandler = { _, _, _, _ in
            withExtendedLifetime(retained) {}
            retained = nil
        }
        return controller
    }
    func makeUIViewController(context: Context) -> UIActivityViewController { Self.controller(for: lease) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct NativeFilePreview: View {
    let lease: NativeFileLease
    var addNotes: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var sharing: NativeFileLease?
    var body: some View {
        NavigationStack {
            NativeQuickLook(lease: lease).navigationTitle(lease.url.lastPathComponent).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("file.preview.done") }
                    ToolbarItem(placement: .primaryAction) { Button { sharing = lease } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share document") }
                    if let addNotes { ToolbarItem(placement: .primaryAction) { Button("Add notes", systemImage: "square.and.pencil", action: addNotes).accessibilityIdentifier("file.preview.addNotes") } }
                }
        }.sheet(item: $sharing) { NativeFileShare(lease: $0) }
    }
}
private struct NativeQuickLook: UIViewControllerRepresentable {
    let lease: NativeFileLease
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let lease: NativeFileLease
        init(_ lease: NativeFileLease) { self.lease = lease }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { lease.url as NSURL }
    }
    func makeCoordinator() -> Coordinator { Coordinator(lease) }
    func makeUIViewController(context: Context) -> QLPreviewController { let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
}

struct NativeFileNoteRequest: Identifiable { let id = UUID(); let source: NativeFileLease? }

struct NativeFilesView: View {
    @EnvironmentObject private var vault: VaultStore
    let workspaceID: UUID
    let open: (NoteDocument) -> Void
    @StateObject private var bulkSelection = NativeBulkSelection()
    @State private var query = ""
    @State private var settings = false
    @State private var filters = NativeCollectionFilters()
    @State private var adding: NativeFileNoteRequest?
    @State private var selected: NativeFileLease?
    @State private var preview: NativeFileLease?
    @State private var created: NoteDocument?
    private var candidates: [NoteDocument] { vault.searchableNotes.filter { !$0.trashed && ($0.fileHub != nil || $0.unfiledFileHub) } }
    private var hubs: [NoteDocument] { filters.apply(candidates, query: query, fileNames: true) }
    private var rawFiles: [String] {
        let represented = Set(vault.notes.filter { !$0.trashed && $0.fileHub?.kind == .vault }.compactMap { $0.fileHub?.path })
        return filters.applyFiles(vault.files.filter { !represented.contains($0) }, dates: vault.fileDates, query: query)
    }
    var body: some View {
        List {
            Section {
                HStack {
                    Button("Add document", systemImage: "plus") { selected = nil; adding = .init(source: nil) }.accessibilityIdentifier("files.add")
                }.font(.subheadline).buttonStyle(.borderless)
            }
            if bulkSelection.active { Section { NativeBulkControls(selection: bulkSelection, visible: hubs) } }
            if !filters.properties.isEmpty { Text("Property filters show documents with notes. Add notes to other files to include them.").font(.caption).foregroundStyle(.secondary) }
            if hubs.isEmpty && rawFiles.isEmpty {
                ContentUnavailableView(query.isEmpty ? "Keep a document close." : "No matching files", systemImage: "doc", description: Text(query.isEmpty ? "Bring a file into your vault, connect its original, and keep your notes beside it." : "Try another name or phrase."))
            }
            if !hubs.isEmpty {
                Section("Documents with notes") {
                    ForEach(hubs) { note in
                        if bulkSelection.active { NativeBulkNoteRow(selection: bulkSelection, note: note, open: open) }
                        else {
                        Button { open(note) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "doc.text").foregroundStyle(Accent.color).font(.title3).frame(width: 28)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(note.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                    Text(note.fileHub?.name ?? "File details need attention; note preserved").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    Text(note.fileHub.map { $0.kind == .vault ? ($0.managed ? "Vault copy" : "Vault link") : $0.kind == .location ? "Folder connection" : "Device connection" } ?? "Preserved metadata").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("files.note." + (note.stableID ?? note.path))
                            .contextMenu { NoteActions(note: note) }
                            .swipeActions { Button("Trash", systemImage: "trash", role: .destructive) { Task { await vault.move(note, trash: true) } } }
                        }
                    }
                }
            }
            if !rawFiles.isEmpty {
                Section {
                    ForEach(rawFiles, id: \.self) { path in
                        Button { previewFile(path) } label: {
                            VStack(alignment: .leading, spacing: 5) { Label((path as NSString).lastPathComponent, systemImage: "doc"); Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(2) }.padding(.vertical, 4)
                        }.foregroundStyle(.primary).accessibilityIdentifier("files.raw." + path)
                            .contextMenu { Button("Add notes to this file", systemImage: "square.and.pencil") { addFile(path) } }
                    }
                } header: { Text("Other files in the vault") } footer: { Text("Preview a file or add a note that keeps its document connection. Files already used as a document are listed above.") }
            }
        }.navigationTitle("Files")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Settings") } }
        .sheet(isPresented: $settings) { SettingsView(collection: .init(filters: $filters, notes: candidates, selection: bulkSelection, fileTypes: true, otherFiles: vault.files)) }
        .searchable(text: $query, prompt: "Search files and their notes")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
            .scrollContentBackground(.hidden).background(Accent.paper)
            .refreshable { await vault.refresh(); await vault.refreshFileLocations() }
            .onChange(of: query) { _, _ in bulkSelection.clear() }
            .onChange(of: filters) { _, _ in bulkSelection.clear() }
            .modifier(NativeBulkPresentation(selection: bulkSelection))
            .sheet(item: $adding, onDismiss: { if let created { self.created = nil; open(created) } }) { request in NativeFileNoteForm(workspaceID: workspaceID, source: request.source) { created = $0 } }
            .sheet(item: $preview, onDismiss: { if let selected { adding = .init(source: selected); self.selected = nil } }) { lease in NativeFilePreview(lease: lease, addNotes: { selected = lease; preview = nil }) }
    }
    private func previewFile(_ path: String) {
        selected = nil
        Task {
            guard let url = await vault.fileURL(path, workspace: workspaceID) else { return }
            do { preview = try await vault.selectFile(url, workspace: workspaceID) }
            catch is CancellationError {} catch { vault.error = error.localizedDescription }
        }
    }
    private func addFile(_ path: String) {
        Task {
            guard let url = await vault.fileURL(path, workspace: workspaceID) else { return }
            do { let source = try await vault.selectFile(url, workspace: workspaceID); adding = .init(source: source) }
            catch is CancellationError {} catch { vault.error = error.localizedDescription }
        }
    }
}

struct NativeFileNoteForm: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let workspaceID: UUID
    let session: NoteSession?
    @State private var original: NativeFileHub?
    let saved: (NoteDocument) -> Void
    @State private var source: NativeFileLease?
    @State private var storage = NativeFileStorage.copy
    @State private var title = ""
    @State private var folder = "Inbox"
    @State private var picking = false
    @State private var vaultPicking = false
    @State private var busy = false
    @State private var issue: String?
    @State private var selectionID = UUID()
    @FocusState private var titleFocused: Bool
    init(workspaceID: UUID, session: NoteSession? = nil, source: NativeFileLease? = nil, saved: @escaping (NoteDocument) -> Void) {
        self.workspaceID = workspaceID; self.session = session; _original = State(initialValue: session?.document.fileHub); self.saved = saved; _source = State(initialValue: source)
        _title = State(initialValue: source.map { $0.url.deletingPathExtension().lastPathComponent } ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                if let original { Section("Current document") { Text(original.name); Text("Replacing the connection preserves your note and existing files.").font(.caption).foregroundStyle(.secondary) } }
                Section("Document") {
                    if let source { Label(source.url.lastPathComponent, systemImage: "doc").accessibilityIdentifier("file.selected"); Text(ByteCountFormatter.string(fromByteCount: source.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                    Button(source == nil ? "Choose a document in Files" : "Choose another document") { titleFocused = false; picking = true }.accessibilityIdentifier("file.choose")
                    if !vault.files.isEmpty { Button("Choose from this vault") { titleFocused = false; vaultPicking = true }.accessibilityIdentifier("file.chooseVault") }
                }
                Section {
                    Picker("Storage", selection: $storage) { ForEach(source?.temporaryDirectory == nil ? NativeFileStorage.allCases : [.copy], id: \.self) { Text($0.shortName).tag($0) } }.accessibilityIdentifier("file.storage")
                } footer: { Text(storage.detail) }
                if session == nil {
                    Section("Your note") {
                        HStack {
                            TextField("Title", text: $title).focused($titleFocused).accessibilityIdentifier("file.title")
                            if titleFocused { Button("Done") { titleFocused = false }.buttonStyle(.borderless).accessibilityLabel("Dismiss document keyboard").accessibilityIdentifier("file.keyboard.dismiss") }
                        }
                        Picker("Folder", selection: $folder) { ForEach(Array(Set(["Inbox"] + vault.folders)).sorted(), id: \.self) { Text($0).tag($0) } }
                    }
                }
                if let issue { Section { Text(issue).foregroundStyle(.red).textSelection(.enabled) } }
            }.navigationTitle(session == nil ? "Add document" : "Replace document").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("file.cancel") }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(source == nil).accessibilityIdentifier("file.save") }
                }
                .disabled(busy).interactiveDismissDisabled(busy)
                .overlay { if busy { ProgressView("Saving document…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
                .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
                    switch result { case .success(let url): choose(url); case .failure(let error): issue = error.localizedDescription }
                }
                .sheet(isPresented: $vaultPicking) { NativeVaultFilePicker(workspaceID: workspaceID) { choose($0) } }
        }
    }
    private func choose(_ url: URL) {
        let request = UUID(); selectionID = request; source = nil
        Task {
            do { let value = try await vault.selectFile(url, workspace: workspaceID); guard request == selectionID else { return }; source = value; if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }; issue = nil }
            catch is CancellationError {} catch { issue = error.localizedDescription }
        }
    }
    private func save() {
        guard !busy else { return }; busy = true; titleFocused = false
        Task {
            defer { busy = false }
            do { let note = try await vault.saveFileHub(session: session, original: original, source: source, storage: storage, title: title, folder: folder, workspace: workspaceID); saved(note); dismiss() }
            catch is CancellationError {} catch { issue = error.localizedDescription }
        }
    }
}

private struct NativeVaultFilePicker: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let workspaceID: UUID
    let selected: (URL) -> Void
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List(vault.files.filter { query.isEmpty || $0.localizedStandardContains(query) }, id: \.self) { path in
                Button { Task { if let url = await vault.fileURL(path, workspace: workspaceID) { selected(url); dismiss() } } } label: { VStack(alignment: .leading) { Text((path as NSString).lastPathComponent); Text(path).font(.caption).foregroundStyle(.secondary) } }
            }.navigationTitle("Choose a vault file").searchable(text: $query)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
