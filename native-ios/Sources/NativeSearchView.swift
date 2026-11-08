import SwiftUI
import QuickLook
import UIKit

extension View {
    func nativeSearchContrast(_ prompt: String) -> some View {
        background(NativeSearchContrast(prompt: prompt).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

/// Keep UIKit's native search behavior and semantic colors, asking only this
/// search field to resolve its colors with higher accessibility contrast.
private struct NativeSearchContrast: UIViewControllerRepresentable {
    let prompt: String
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.prompt = prompt
        controller.refresh()
    }
    final class Controller: UIViewController {
        var prompt = ""
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); refresh() }
        func refresh() {
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }
        private func apply() {
            guard let window = viewIfLoaded?.window else { return }
            var owner = parent
            while let controller = owner {
                if let field = controller.navigationItem.searchController?.searchBar.searchTextField,
                   field.window === window, field.placeholder == prompt {
                    if field.traitCollection.accessibilityContrast != .high {
                        field.traitOverrides.accessibilityContrast = .high
                    }
                    return
                }
                owner = controller.parent
            }
        }
    }
}

struct NativeSearchView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var external: NativeExternalNotesModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let open: (NoteDocument) -> Void
    let ask: (NativeSearchAskRequest) -> Void
    let library: () -> Void
    let settings: () -> Void
    @StateObject private var model = NativeSearchModel()
    @State private var query = ""
    @State private var filters = NativeSearchFilters()
    @State private var filtering = false
    @State private var preview: NativeSearchPreviewSelection?
    @State private var task: NativeTask?
    @State private var file: URL?
    @State private var externalSession: NativeExternalNoteSession?
    @State private var openingExternal = false
    @State private var externalAction = UUID()
    @State private var externalTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    private var recent: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filters.isEmpty }
    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    actionLayout {
                        Button { focused = false; filtering = true } label: {
                            if dynamicTypeSize.isAccessibilitySize {
                                Text(filters.isEmpty ? "Filters" : "Filters applied")
                                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            } else { Label(filters.isEmpty ? "Filters" : "Filters applied", systemImage: "line.3.horizontal.decrease") }
                        }
                            .buttonStyle(.bordered).accessibilityIdentifier("search.filters")
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        if !filters.isEmpty { Button("Reset") { filters = .init() }.buttonStyle(.borderless) }
                        if focused { Button("Done") { focused = false }.buttonStyle(.borderless).accessibilityLabel("Dismiss search keyboard").accessibilityIdentifier("search.keyboard.dismiss") }
                    }.font(.subheadline).listRowBackground(Color.clear).listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                if let issue = external.issue {
                    Section {
                        Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                        Button("Retry external files") { Task { await external.refreshSearchIndex() } }
                    }
                }
                if let problem = model.problem { Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary); Button("Try again") { model.rebuild(vault: vault) } } }
                if let result = model.result, result.workspaceID == vault.workspaceID {
                    if !result.problems.isEmpty { Section { ForEach(result.problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) } } }
                    if !result.items.isEmpty {
                        Section {
                            ForEach(result.items) { item in
                                Button { openResult(item, workspace: result.workspaceID) } label: { row(item) }.buttonStyle(.plain).listRowBackground(Accent.card).accessibilityIdentifier("search.result." + item.id)
                                    .contextMenu {
                                        Button("Open", systemImage: "arrow.up.forward.app") { openResult(item, workspace: result.workspaceID) }
                                        Button("Preview", systemImage: "eye") { preview = .init(item: item, workspaceID: result.workspaceID) }
                                        if case .file = item.target {} else { Button("Ask Zerus about this", systemImage: "sparkles") { askAbout(item, workspace: result.workspaceID) } }
                                        ShareLink(item: item.text) { Label("Share text", systemImage: "square.and.arrow.up") }
                                    }
                            }
                            if result.total > result.items.count { Button("Show more results (\(result.total - result.items.count) remaining)") { model.more() } }
                        } header: {
                            actionLayout {
                                Text(recent ? "Recently opened" : result.total == 1 ? "1 result" : "\(result.total) results")
                                    .fixedSize(horizontal: false, vertical: true)
                                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                                if recent { Button("Clear") { model.clearRecent() }.textCase(nil).frame(minHeight: 44) }
                            }
                        }
                    } else if !model.loading {
                        ContentUnavailableView(recent ? "Find a thought." : "No results", systemImage: "magnifyingglass", description: Text(recent ? "Search notes, external notes, saved links, tasks, files, and AI conversations." : "Try another phrase or change your filters."))
                    }
                }
                if external.searching { ProgressView("Checking external files…").font(.caption).accessibilityIdentifier("search.external.loading") }
                if openingExternal {
                    HStack { ProgressView("Opening external note…"); Spacer(); Button("Cancel") { cancelExternalAction() }.accessibilityIdentifier("search.external.cancel") }
                }
                if model.loading { HStack { Spacer(); ProgressView("Searching…"); Spacer() }.listRowBackground(Color.clear) }
            }
            .scrollContentBackground(.hidden).background(Accent.paper)
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NativeLibraryButton(action: library) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Search") { Button("Filters", systemImage: "line.3.horizontal.decrease") { focused = false; filtering = true } }
                        Section { Button("Settings", systemImage: "gearshape", action: settings) }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Settings")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .nativeSearchContrast("Search")
            .searchFocused($focused)
            .background { Button("Find") { focused = true }.keyboardShortcut("f", modifiers: .command).hidden() }
            .task(id: vault.searchRevision) { model.rebuild(vault: vault, external: external.searchRecords) }
            .task { await external.refreshSearchIndex() }
            .onChange(of: external.searchRevision) { _, _ in model.updateExternal(external.searchRecords) }
            .onChange(of: phase) { _, value in if value == .active { Task { await external.refreshSearchIndex() } } }
            .onChange(of: query) { _, _ in model.search(query: query, filters: filters) }
            .onChange(of: filters) { _, _ in model.search(query: query, filters: filters) }
            .onAppear { model.search(query: query, filters: filters) }
            .refreshable { await vault.refresh(); model.rebuild(vault: vault, external: external.searchRecords); await external.refreshSearchIndex() }
            .sheet(isPresented: $filtering) { NativeSearchFilterView(filters: $filters, folders: model.result?.folders ?? [], properties: model.result?.properties ?? []) }
            .sheet(item: $preview) { selection in NativeSearchPreview(item: selection.item, busy: $openingExternal, cancel: cancelExternalAction, ask: { askAbout(selection.item, workspace: selection.workspaceID) }) }
            .sheet(item: $task) { value in TaskDetailView(task: value) }
            .fullScreenCover(item: $externalSession, onDismiss: { Task { await external.refreshSearchIndex() } }) { NativeExternalEditorScreen(session: $0) }
            .quickLookPreview($file)
            .onDisappear { cancelExternalAction() }
        }
    }
    private func row(_ item: NativeSearchItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.collection.icon).foregroundStyle(Accent.color).font(.title3).frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 25).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.headline).lineLimit(2)
                Text(NativeSearch.excerpt(item, query: query)).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                if let issue = item.issue { Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                actionLayout {
                    Text(item.location.isEmpty ? item.collection.rawValue : item.location).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    if item.draft { Text("Draft").foregroundStyle(Accent.color) }
                    if item.archived { Text("Archived") }
                    if item.completed == true { Image(systemName: "checkmark.circle.fill").accessibilityLabel("Completed") }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    if item.modified != .distantPast { Text(item.modified, style: .date).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1) }
                }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
        }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private func openResult(_ item: NativeSearchItem, workspace: UUID) {
        guard workspace == vault.workspaceID else { return }
        focused = false
        switch item.target {
        case .note(let path, let stable):
            let matches = vault.searchableNotes.filter { stable == nil ? $0.path == path : $0.stableID == stable }
            guard matches.count == 1, let note = matches.first, !note.trashed else { vault.error = "This result changed. Refresh search and try again."; return }
            model.visited(item); open(note)
        case .external(let id): performExternalAction(item, id: id, workspace: workspace, reference: false)
        case .task(let id):
            guard let value = vault.tasks.first(where: { $0.id == id }) else { vault.error = "This task changed. Refresh search and try again."; return }
            model.visited(item); task = value
        case .file(let path):
            let origin = vault.workspaceID
            Task {
                let url = await vault.fileURL(path, workspace: origin)
                guard origin == vault.workspaceID else { return }
                if let url { model.visited(item); file = url }
                else { vault.error = "This file is unavailable. Refresh search or check its download in Files." }
            }
        case .conversation: model.visited(item); preview = .init(item: item, workspaceID: workspace)
        }
    }
    private func cancelExternalAction() { externalTask?.cancel(); externalAction = UUID(); openingExternal = false }
    private func performExternalAction(_ item: NativeSearchItem, id: UUID, workspace: UUID, reference: Bool) {
        cancelExternalAction()
        guard workspace == vault.workspaceID else { return }
        guard let entry = external.entries.first(where: { $0.id == id }) else { vault.error = "This external file is no longer tracked. Open it again in Files."; return }
        let action = UUID(); externalAction = action; openingExternal = true
        externalTask = Task {
            defer { if externalAction == action { openingExternal = false } }
            @MainActor func current() -> Bool { !Task.isCancelled && externalAction == action && vault.workspaceID == workspace && external.entries.contains(where: { $0.id == id }) }
            do {
                if reference {
                    let record = try await external.searchRecord(id)
                    guard current() else { return }
                    guard let note = record.document else { vault.error = record.issue ?? "This external file is unavailable."; return }
                    preview = nil; focused = false; model.visited(item)
                    ask(.init(workspaceID: workspace, prompt: "Help me understand \"\(note.title)\".", notes: [], document: try record.referenceDocument()))
                } else {
                    let session = try await external.open(entry)
                    guard current() else { return }
                    model.visited(item); externalSession = session
                }
            } catch is CancellationError {} catch { if current() { vault.error = error.localizedDescription } }
        }
    }
    private func askAbout(_ item: NativeSearchItem, workspace: UUID) {
        guard workspace == vault.workspaceID else { return }
        let origin = workspace
        if case .external(let id) = item.target { performExternalAction(item, id: id, workspace: origin, reference: true); return }
        var notes: Set<String> = [], document: NativeSearchDocument?
        if case .note(let path, let stable) = item.target {
            let current = vault.searchableNotes.filter { stable == nil ? $0.path == path : $0.stableID == stable }
            guard current.count == 1, let note = current.first, !note.trashed else { vault.error = "This result changed. Refresh search and try again."; return }
            notes = [note.path]
        } else { document = .init(name: item.title, text: String(item.text.prefix(20_000))) }
        preview = nil; focused = false; model.visited(item)
        ask(.init(workspaceID: origin, prompt: "Help me understand \"\(item.title)\".", notes: notes, document: document))
    }
}

private struct NativeSearchFilterView: View {
    @Binding var filters: NativeSearchFilters
    let folders: [String]
    let properties: [String]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Search in") {
                    Picker("Collection", selection: $filters.collection) {
                        Text("Everything").tag(Optional<NativeSearchCollection>.none)
                        ForEach(NativeSearchCollection.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }.accessibilityIdentifier("search.collection")
                    Picker("Modified", selection: $filters.days) { Text("Any time").tag(0); Text("Last day").tag(1); Text("Last 7 days").tag(7); Text("Last 30 days").tag(30); Text("Last 90 days").tag(90) }
                    Toggle("Include archived", isOn: $filters.archived)
                }
                if filters.collection == nil || [.notes, .external, .links, .files].contains(filters.collection!) {
                    Section("Location and properties") {
                        Picker("Folder", selection: $filters.folder) { Text("Any folder").tag(""); ForEach(folders, id: \.self) { Text($0).tag($0) } }
                        Picker("Property", selection: $filters.property) { Text("Any property").tag(""); ForEach(properties, id: \.self) { Text($0).tag($0) } }
                        if !filters.property.isEmpty { TextField("Exact value (optional)", text: $filters.value).autocorrectionDisabled() }
                    }
                }
                if filters.collection == nil || filters.collection == .tasks {
                    Section("Tasks") {
                        Picker("Status", selection: $filters.status) { Text("Any status").tag(""); Text("Open").tag("open"); Text("Completed").tag("completed") }
                        Picker("Priority", selection: $filters.priority) { Text("Any priority").tag(""); ForEach(["high", "medium", "low", "none"], id: \.self) { Text($0.capitalized).tag($0) } }
                    }
                }
                Button("Reset filters") { filters = .init() }.disabled(filters.isEmpty)
            }.navigationTitle("Search filters").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onChange(of: filters.collection) { _, _ in filters.folder = ""; filters.property = ""; filters.value = ""; filters.status = ""; filters.priority = "" }
                .onChange(of: filters.property) { _, _ in filters.value = "" }
        }
    }
}

private struct NativeSearchPreview: View {
    let item: NativeSearchItem
    @Binding var busy: Bool
    let cancel: () -> Void
    let ask: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(item.title).font(.system(.title, design: .serif)).textSelection(.enabled)
                    Label(item.location.isEmpty ? item.collection.rawValue : item.location, systemImage: item.collection.icon).font(.caption).foregroundStyle(.secondary)
                    if let issue = item.issue { Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary) }
                    if case .external = item.target { Text("Preview from the last search refresh. Open the file to see its current writing.").font(.caption).foregroundStyle(.secondary) }
                    if case .conversation(let conversation) = item.target {
                        ForEach(conversation.messages) { message in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(message.role == "user" ? "YOU" : "ZERUS").font(.caption.bold()).foregroundStyle(.secondary)
                                rendered(message.content)
                            }
                        }
                    } else { rendered(item.preview) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.navigationTitle("Preview").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if busy { Button("Cancel", action: cancel).accessibilityIdentifier("search.reference.cancel") }
                        else { Button("Done") { dismiss() } }
                    }
                    ToolbarItem(placement: .primaryAction) { Button(busy ? "Preparing reference…" : "Ask Zerus", systemImage: "sparkles", action: ask).disabled(busy) }
                }
        }.onDisappear { if busy { cancel() } }
    }
    private func rendered(_ text: String) -> some View { Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)).textSelection(.enabled).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading) }
}

private struct NativeSearchPreviewSelection: Identifiable {
    let item: NativeSearchItem
    let workspaceID: UUID
    var id: String { workspaceID.uuidString + ":" + item.id }
}
