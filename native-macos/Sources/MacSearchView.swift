import SwiftUI

struct MacSearchView: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject private var external: MacExternalLibrary
    @StateObject private var model: MacSearchModel
    @State private var refresh = UUID()
    @State private var advanced = false
    @State private var openedTask: NativeTask?
    @State private var openedFile: NativeFileLease?
    @State private var openedExternal: MacExternalSession?
    @State private var openedChat: MacChatController?
    @State private var selectedKey: String?
    @State private var includeResult = true
    @State private var chatNotice: String?
    @State private var action: Task<Void, Never>?
    @State private var actionID = UUID()
    @State private var issue: String?
    @State private var opening = false
    @FocusState private var focused: Bool
    init(workspace: MacWorkspace) {
        self.workspace = workspace; external = workspace.external
        _model = StateObject(wrappedValue: MacSearchModel(external: workspace.external.store))
    }
    private var request: String { model.query + String(describing: model.filters) }
    private var selected: NativeSearchItem? { model.result?.items.first(where: { $0.id == selectedKey }) ?? model.result?.items.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search everything", text: $model.query).textFieldStyle(.plain).font(.title3).focused($focused).disabled(opening)
                    .onSubmit { if let item = selected { open(item) } }
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                if model.loading { ProgressView().controlSize(.small) }
                Button("Refresh") { Task { await workspace.refresh(); refresh = UUID() } }.disabled(opening)
                Button("Done") { workspace.showSearch = false }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Picker("Search", selection: $model.filters.collection) {
                    Text("Everything").tag(NativeSearchCollection?.none)
                    ForEach(NativeSearchCollection.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }.frame(width: 240)
                Picker("Modified", selection: $model.filters.days) { Text("Any time").tag(0); Text("Last 7 days").tag(7); Text("Last 30 days").tag(30); Text("Last year").tag(365) }.frame(width: 230)
                Toggle("Include archived", isOn: $model.filters.archived)
                Spacer(); Button(advanced ? "Hide filters" : "More filters") { advanced.toggle() }
            }.font(.caption).disabled(opening)
            if advanced { advancedFilters.disabled(opening) }
            Divider()
            if let message = issue ?? model.issue { Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if let warning = model.result?.problems.first { Text(warning).font(.caption).foregroundStyle(.orange) }
            if model.filesLoading { HStack { ProgressView().controlSize(.small); Text("Indexing file contents… Notes and filenames are searchable.").font(.caption).foregroundStyle(.secondary) } }
            else if let notice = model.fileNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if model.externalLoading { HStack { ProgressView().controlSize(.small); Text("Checking connected external files… Local results are ready.").font(.caption).foregroundStyle(.secondary) } }
            if let result = model.result {
                HStack { Text(model.query.isEmpty && model.filters.isEmpty ? "Recent results" : "\(result.total) " + (result.total == 1 ? "result" : "results")).font(.caption).foregroundStyle(.secondary); Spacer(); if model.query.isEmpty && model.filters.isEmpty { Button("Clear recent") { Task { await model.clearRecent() } }.font(.caption) } }
                MacZoomSplitView {
                    ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(result.items) { item in resultRow(item).id(item.id); Divider() }
                            if result.items.isEmpty { ContentUnavailableView(model.query.isEmpty && model.filters.isEmpty ? "Search across your workspace" : "No results", systemImage: "magnifyingglass", description: Text("Search notes, tasks, saved links, AI conversations, PDF/text file contents and connected external Markdown. Use filters to narrow results.")) }
                            if result.total > result.items.count { Button("Show more results") { Task { await model.more() } }.padding(.vertical, 12) }
                        }
                    }.onChange(of: selectedKey) { if let selectedKey { proxy.scrollTo(selectedKey, anchor: .center) } }
                    }.frame(minWidth: 360)
                    if let selected { resultPreview(selected).frame(minWidth: 260, idealWidth: 290) }
                }
                Divider()
                HStack {
                    Toggle("Use selected result as context", isOn: $includeResult).toggleStyle(.checkbox).disabled(selected == nil || opening)
                    Spacer()
                    Button("Ask AI ↗", action: ask).disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.loading || opening)
                }.font(.caption)

            } else { Spacer(); ProgressView("Preparing search…").frame(maxWidth: .infinity); Spacer() }
        }.padding(22).frame(width: 850, height: 650)
        .onAppear { model.query = workspace.globalQuery; focused = true }
        .onChange(of: model.query) { workspace.globalQuery = model.query; selectedKey = nil }
        .onChange(of: model.filters) { selectedKey = nil }
        .onDisappear { actionID = UUID(); action?.cancel() }
        .onChange(of: workspace.workspaceID) { refresh = UUID(); openedTask = nil; openedFile = nil; openedChat = nil; action?.cancel(); actionID = UUID(); selectedKey = nil; opening = false }
        .task(id: refresh) { await model.rebuild(workspace) }
        .task(id: request) { do { try await Task.sleep(for: .milliseconds(140)); await model.run() } catch {} }
        .macSheet(item: $openedTask, onDismiss: { refresh = UUID() }) { task in MacTaskEditor(store: workspace, task: task) }
        .macSheet(item: $openedFile) { lease in MacLeasedPreview(lease: lease) }
        .macSheet(item: $openedChat, onDismiss: { refresh = UUID() }) { chat in MacConversationChatView(workspace: workspace, chat: chat, launchNotice: chatNotice) }
        .onChange(of: external.selected?.id) { if external.selected == nil { openedExternal = nil } }
        .macSheet(item: $openedExternal, onDismiss: { refresh = UUID() }) { session in MacExternalEditor(workspace: workspace, library: external, session: session) }
    }
    private func resultRow(_ item: NativeSearchItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { selectedKey = item.id } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.collection.icon).frame(width: 20).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(item.title).font(.headline); if item.draft { Text("Draft").font(.caption2).foregroundStyle(.orange) }; if item.archived { Text("Archived").font(.caption2).foregroundStyle(.secondary) } }
                        Text(NativeSearch.excerpt(item, query: model.query)).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        Text(item.collection.rawValue + (item.location.isEmpty || item.location == item.collection.rawValue ? "" : " · " + item.location)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let problem = item.issue { Text(problem).font(.caption).foregroundStyle(.orange).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(MacBoxButtonStyle()).accessibilityLabel("Preview " + item.title).accessibilityHint(item.issue ?? "")
            Button { open(item) } label: { Image(systemName: "arrow.up.forward") }.buttonStyle(MacBoxButtonStyle()).accessibilityLabel("Open " + item.title).padding(.top, 3)
        }.padding(10).background(selected?.id == item.id ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7)).disabled(opening)
    }
    private func resultPreview(_ item: NativeSearchItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(item.collection.rawValue, systemImage: item.collection.icon).font(.caption).foregroundStyle(.secondary)
                Text(item.title).font(.title3.bold()).textSelection(.enabled)
                Text(item.location).font(.caption).foregroundStyle(.secondary)
                if let issue = item.issue { Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                if item.draft { Text("Includes an unsaved local draft.").font(.caption).foregroundStyle(.orange) }
                ForEach(item.propertyExcerpts, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                Text(String(item.text.prefix(16_000))).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if item.text.count > 16_000 { Text("Preview shows the first 16,000 characters. Ask AI prepares the selected source within chat’s context limits.").font(.caption).foregroundStyle(.secondary) }
                Button("Open result") { open(item) }.disabled(opening)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .id(item.id + NativeHistory.hash(item.title + "\n" + String(item.text.prefix(16_000))))
        }
    }
    private func moveSelection(_ direction: Int) {
        guard let items = model.result?.items, !items.isEmpty else { return }
        let index = items.firstIndex(where: { $0.id == selected?.id }) ?? 0
        selectedKey = items[max(0, min(items.count - 1, index + direction))].id
    }
    private func ask() {
        guard let result = model.result, result.workspaceID == workspace.workspaceID, let root = workspace.root else { issue = "The vault changed. Refresh search."; return }
        let origin = result.workspaceID, item = includeResult ? selected : nil, query = model.query, token = UUID()
        actionID = token; opening = true; issue = nil
        action = Task { defer { if actionID == token { opening = false; action = nil } }; do {
            let request = try await workspace.searchChatRequest(query: query, item: item, workspaceID: origin)
            try Task.checkCancellation()
            guard actionID == token, workspace.workspaceID == origin else { return }
            let chat = MacChatController.shared(root: root), appended = try chat.prepareSearchQuestion(request)
            chatNotice = (appended ? "Search question appended to your unsent draft. " : "Question prepared from search. ") + "Existing unsent attachments are kept. Review context and press Send when ready."
            if let item { model.visited(item) }
            openedChat = chat
        } catch is CancellationError {} catch { if actionID == token { issue = error.localizedDescription } } }
    }
    private var advancedFilters: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Folder", selection: $model.filters.folder) { Text("Any folder").tag(""); ForEach(model.result?.folders ?? [], id: \.self) { Text($0).tag($0) } }
                Picker("Property", selection: $model.filters.property) { Text("Any property").tag(""); ForEach(model.result?.properties ?? [], id: \.self) { Text($0).tag($0) } }
                TextField("Exact property value", text: $model.filters.value).disabled(model.filters.property.isEmpty).textFieldStyle(.roundedBorder)
            }
            HStack {
                Picker("Task status", selection: $model.filters.status) { Text("Any status").tag(""); Text("Open").tag("open"); Text("Completed").tag("completed") }
                Picker("Task priority", selection: $model.filters.priority) { Text("Any priority").tag(""); ForEach(["none", "low", "medium", "high"], id: \.self) { Text($0.capitalized).tag($0) } }
                Spacer(); Button("Reset filters") { model.filters = .init() }
            }
        }.font(.caption)
    }
    private func open(_ item: NativeSearchItem) {
        guard let result = model.result, result.workspaceID == workspace.workspaceID else { issue = "The vault changed. Refresh search."; return }
        let origin = result.workspaceID
        opening = true; issue = nil
        Task {
            defer { opening = false }
            do {
                switch item.target {
                case .note(let path, let stable):
                    try await workspace.openSearchNote(path: path, stableID: stable, workspaceID: origin)
                    model.visited(item); workspace.showSearch = false
                case .task(let id):
                    openedTask = try await workspace.reloadTask(id: id, workspaceID: origin); model.visited(item)
                case .file(let path):
                    openedFile = try await workspace.searchFile(path, workspaceID: origin); model.visited(item)
                case .external(let id):
                    let entries = try await external.store.entries()
                    guard workspace.workspaceID == origin, let entry = entries.first(where: { $0.id == id }) else { throw VaultFailure(message: "This external connection changed. Refresh search.") }
                    await external.open(entry)
                    guard external.selected?.id == id else { throw VaultFailure(message: external.issue ?? "The original is unavailable. Open External Notes to locate it or export its recovery draft.") }
                    openedExternal = external.selected; model.visited(item)
                case .conversation(let conversation):
                    chatNotice = nil
                    openedChat = try await workspace.openSearchConversation(conversation, workspaceID: origin)
                    model.visited(item)
                }
            } catch { issue = error.localizedDescription }
        }
    }
}
