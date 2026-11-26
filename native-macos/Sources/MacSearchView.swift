import SwiftUI
import ZerusLocalAICore

/// Command-palette search. Results stay a compact grouped list until a row is
/// clicked; the panel then widens into list + preview. Clicking the previewed
/// row again (or double-clicking any row) opens it.
struct MacSearchView: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject private var external: MacExternalLibrary
    @StateObject private var model: MacSearchModel
    @Environment(\.macTheme) private var theme
    @State private var refresh = UUID()
    @State private var openedTask: NativeTask?
    @State private var openedFile: NativeFileLease?
    @State private var openedExternal: MacExternalSession?
    @State private var openedChat: MacChatController?
    @State private var selectedKey: String?
    @State private var previewing = false
    @State private var includeResult = true
    @State private var chatNotice: String?
    @State private var action: Task<Void, Never>?
    @State private var actionID = UUID()
    @State private var issue: String?
    @State private var opening = false
    /// On-device semantic matches shown as "Best matches" above keyword groups.
    @State private var semantic: [LocalAISearchHit] = []
    @State private var askQuestion: MacLocalAskQuestion?
    @FocusState private var focused: Bool
    init(workspace: MacWorkspace) {
        self.workspace = workspace; external = workspace.external
        _model = StateObject(wrappedValue: MacSearchModel(external: workspace.external.store))
    }
    private var request: String { model.query + String(describing: model.filters) }
    private var browsingRecent: Bool { model.query.isEmpty && model.filters.isEmpty }
    private var trimmedQuery: String { model.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Results grouped by kind, groups ordered by their best-ranked item.
    /// On-device semantic matches lead as "Best matches" when the index is ready.
    private var groups: [(title: String, collection: NativeSearchCollection?, items: [NativeSearchItem])] {
        guard let items = model.result?.items else { return [] }
        if browsingRecent { return items.isEmpty ? [] : [("Recent", nil, items)] }
        let best = semanticItems
        let bestPaths = Set(best.compactMap { if case .note(let path, _) = $0.target { path } else { nil } })
        var order: [NativeSearchCollection] = [], buckets: [NativeSearchCollection: [NativeSearchItem]] = [:]
        for item in items {
            if case .note(let path, _) = item.target, bestPaths.contains(path) { continue }
            if buckets[item.collection] == nil { order.append(item.collection) }
            buckets[item.collection, default: []].append(item)
        }
        return (best.isEmpty ? [] : [("Best matches", nil, best)]) + order.map { ($0.rawValue, $0, buckets[$0] ?? []) }
    }
    private var semanticItems: [NativeSearchItem] {
        guard model.filters.collection == nil || model.filters.collection == .notes else { return [] }
        return semantic.compactMap { hit in
            guard let note = workspace.notes.first(where: { $0.path == hit.path }), !note.trashed, model.filters.archived || !note.archived else { return nil }
            return NativeSearchItem(id: "semantic:" + hit.path, collection: .notes, title: note.title, text: note.parts.body, location: note.folder,
                                    folder: note.folder, modified: note.modified, archived: note.archived,
                                    target: .note(path: note.path, stableID: note.stableID), preview: hit.passage)
        }
    }
    private var localAsk: Bool { !CloudAIFeature.enabled && MacLocalAI.shared.canGenerate && !trimmedQuery.isEmpty }
    private var ordered: [NativeSearchItem] { groups.flatMap(\.items) }
    private var selected: NativeSearchItem? { ordered.first(where: { $0.id == selectedKey }) ?? ordered.first }
    private var showsPreview: Bool { previewing && selected != nil }
    private var palette: MacSearchPalette { MacSearchPalette(theme) }

    var body: some View {
        let p = palette
        VStack(spacing: 0) {
            header(p)
            filterBar(p)
            notices(p)
            if let result = model.result {
                HStack(spacing: 0) {
                    resultList(result, p).frame(width: showsPreview ? 420 : nil).frame(maxWidth: showsPreview ? nil : .infinity)
                    if showsPreview, let selected {
                        Rectangle().fill(p.line).frame(width: 1)
                        resultPreview(selected, p).frame(maxWidth: .infinity, maxHeight: .infinity).background(p.surface)
                    }
                }.frame(maxHeight: .infinity)
            } else { ProgressView("Preparing search…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            footer(p)
        }
        .frame(width: showsPreview ? 940 : 640, height: 600)
        .foregroundStyle(p.text).background(p.background).presentationBackground(p.background)
        .onAppear { model.query = workspace.globalQuery; focused = true }
        .onChange(of: model.query) { workspace.globalQuery = model.query; selectedKey = nil; previewing = false }
        .onChange(of: model.filters) { selectedKey = nil; previewing = false }
        .onDisappear { actionID = UUID(); action?.cancel() }
        .onChange(of: workspace.workspaceID) { refresh = UUID(); openedTask = nil; openedFile = nil; openedChat = nil; action?.cancel(); actionID = UUID(); selectedKey = nil; previewing = false; opening = false }
        .task(id: refresh) { await model.rebuild(workspace) }
        .task(id: request) { do { try await Task.sleep(for: .milliseconds(140)); await model.run() } catch {} }
        .task(id: trimmedQuery) {
            guard !trimmedQuery.isEmpty, MacLocalAI.shared.searchReady else { semantic = []; return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            let hits = await MacLocalAI.shared.search(trimmedQuery, in: workspace)
            if !Task.isCancelled { semantic = hits }
        }
        .macSheet(item: $askQuestion) { ask in
            MacLocalAskView(workspace: workspace, question: ask.text, open: { path in openLocal(path) }, handOff: { kind, instruction, path in
                MacLocalAI.shared.handOff = .init(workspaceID: workspace.workspaceID, kind: kind, instruction: instruction, path: path)
                askQuestion = nil; workspace.showSearch = false
            })
        }
        .macSheet(item: $openedTask, onDismiss: { refresh = UUID() }) { task in MacTaskEditor(store: workspace, task: task) }
        .macSheet(item: $openedFile) { lease in MacLeasedPreview(lease: lease) }
        .macSheet(item: $openedChat, onDismiss: { refresh = UUID() }) { chat in MacConversationChatView(workspace: workspace, chat: chat, launchNotice: chatNotice) }
        .onChange(of: external.selected?.id) { if external.selected == nil { openedExternal = nil } }
        .macSheet(item: $openedExternal, onDismiss: { refresh = UUID() }) { session in MacExternalEditor(workspace: workspace, library: external, session: session) }
    }

    // MARK: Header and filters

    private func header(_ p: MacSearchPalette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(p.muted)
            TextField(CloudAIFeature.enabled ? "Search notes, tasks, links, files, chats…" : "Search notes, tasks, links, files…", text: $model.query).textFieldStyle(.plain).font(.system(size: 18)).focused($focused).disabled(opening)
                .onSubmit { if let item = selected { open(item) } }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            if model.loading || opening { ProgressView().controlSize(.small) }
            Button(action: close) { MacSearchKey(label: showsPreview ? "esc  hide preview" : "esc", palette: p) }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction).help(showsPreview ? "Hide preview" : "Close search")
            // ⌘↵ asks AI from anywhere in the panel.
            if CloudAIFeature.enabled {
                Button("Ask AI", action: ask).keyboardShortcut(.return, modifiers: .command).hidden().frame(width: 0, height: 0)
                    .disabled(trimmedQuery.isEmpty || model.loading || opening)
            } else if localAsk {
                Button("Ask your notes") { askQuestion = .init(text: trimmedQuery) }.keyboardShortcut(.return, modifiers: .command).hidden().frame(width: 0, height: 0)
            }
        }.padding(.horizontal, 16).padding(.vertical, 13).overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }
    }

    private func filterBar(_ p: MacSearchPalette) -> some View {
        HStack(spacing: 6) {
            chipMenu(model.filters.collection?.rawValue ?? "Everything", active: model.filters.collection != nil, p) {
                Picker("Kind", selection: $model.filters.collection) {
                    Text("Everything").tag(NativeSearchCollection?.none)
                    ForEach(NativeSearchCollection.visibleCases, id: \.self) { Label($0.rawValue, systemImage: $0.icon).tag(Optional($0)) }
                }.pickerStyle(.inline)
            }
            chipMenu(daysTitle, active: model.filters.days != 0, p) {
                Picker("Modified", selection: $model.filters.days) { Text("Any time").tag(0); Text("Last 7 days").tag(7); Text("Last 30 days").tag(30); Text("Last year").tag(365) }.pickerStyle(.inline)
            }
            chipMenu(model.filters.folder.isEmpty ? "Folder" : model.filters.folder, active: !model.filters.folder.isEmpty, p) {
                Picker("Folder", selection: $model.filters.folder) { Text("Any folder").tag(""); ForEach(model.result?.folders ?? [], id: \.self) { Text($0).tag($0) } }.pickerStyle(.inline)
            }
            chipMenu(model.filters.property.isEmpty ? "Property" : model.filters.property, active: !model.filters.property.isEmpty, p) {
                Picker("Property", selection: $model.filters.property) { Text("Any property").tag(""); ForEach(model.result?.properties ?? [], id: \.self) { Text($0).tag($0) } }.pickerStyle(.inline)
            }
            if !model.filters.property.isEmpty {
                TextField("Exact value", text: $model.filters.value).textFieldStyle(.plain).font(.system(size: 11.5)).frame(width: 110)
                    .padding(.horizontal, 9).padding(.vertical, 3).overlay(Capsule().stroke(p.line))
            }
            if model.filters.collection == .tasks {
                chipMenu(model.filters.status.isEmpty ? "Status" : model.filters.status.capitalized, active: !model.filters.status.isEmpty, p) {
                    Picker("Task status", selection: $model.filters.status) { Text("Any status").tag(""); Text("Open").tag("open"); Text("Completed").tag("completed") }.pickerStyle(.inline)
                }
                chipMenu(model.filters.priority.isEmpty ? "Priority" : model.filters.priority.capitalized, active: !model.filters.priority.isEmpty, p) {
                    Picker("Task priority", selection: $model.filters.priority) { Text("Any priority").tag(""); ForEach(["none", "low", "medium", "high"], id: \.self) { Text($0.capitalized).tag($0) } }.pickerStyle(.inline)
                }
            }
            Button { model.filters.archived.toggle() } label: { MacSearchChip(title: "Archived", active: model.filters.archived, palette: p) }.buttonStyle(.plain)
                .accessibilityAddTraits(model.filters.archived ? .isSelected : []).help("Include archived results")
            Spacer(minLength: 0)
            if !model.filters.isEmpty { Button("Reset") { model.filters = .init() }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(p.accent) }
        }.disabled(opening).padding(.horizontal, 14).padding(.vertical, 8).overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }
    }
    private var daysTitle: String { switch model.filters.days { case 7: "Last 7 days"; case 30: "Last 30 days"; case 365: "Last year"; default: "Any time" } }
    private func chipMenu<Content: View>(_ title: String, active: Bool, _ p: MacSearchPalette, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: { MacSearchChip(title: title, active: active, chevron: true, palette: p) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    @ViewBuilder private func notices(_ p: MacSearchPalette) -> some View {
        let messages: [(String, Color)] = [(issue ?? model.issue).map { ($0, Color.red) }, model.result?.problems.first.map { ($0, Color.orange) }].compactMap { $0 }
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages, id: \.0) { Text($0.0).foregroundStyle($0.1).textSelection(.enabled) }
            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
                .background(p.surface).overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }
        }
    }

    // MARK: Results

    private func resultList(_ result: NativeSearchResult, _ p: MacSearchPalette) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(groups, id: \.title) { group in
                        HStack {
                            Text(group.title).textCase(.uppercase).tracking(0.6)
                            Spacer()
                            if browsingRecent { Button("Clear") { Task { await model.clearRecent() } }.buttonStyle(.plain).foregroundStyle(p.accent).textCase(nil) }
                            else { Text("\(group.items.count)") }
                        }.font(.system(size: 10.5, weight: .medium)).foregroundStyle(p.muted).padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 3)
                        ForEach(group.items) { item in
                            MacSearchRow(item: item, query: browsingRecent ? "" : model.query, selected: selected?.id == item.id, palette: p) { activate(item) }
                                .id(item.id).disabled(opening)
                        }
                    }
                    if result.items.isEmpty { emptyState(p) }
                    if result.total > result.items.count {
                        Button("Show more results") { Task { await model.more() } }.buttonStyle(.plain).foregroundStyle(p.accent).font(.caption).padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    if CloudAIFeature.enabled, !trimmedQuery.isEmpty { askRow(p) }
                    if localAsk { localAskRow(p) }
                }.padding(.vertical, 4)
            }.onChange(of: selectedKey) { if let selectedKey { proxy.scrollTo(selectedKey, anchor: .center) } }
        }
    }

    private func emptyState(_ p: MacSearchPalette) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(p.muted)
            Text(browsingRecent ? "Search across your workspace" : "No results").font(.headline)
            Text(browsingRecent ? (CloudAIFeature.enabled ? "Notes, tasks, saved links, AI conversations, PDF/text file contents and connected external Markdown." : "Notes, tasks, saved links, PDF/text file contents and connected external Markdown.") : "Try fewer words or remove a filter.")
                .font(.callout).foregroundStyle(p.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.horizontal, 40).padding(.vertical, 60)
    }

    private func askRow(_ p: MacSearchPalette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(p.accent).frame(width: 22)
            Button(action: ask) {
                Text("Ask AI about “\(trimmedQuery)”").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.loading || opening)
            if let selected {
                Button { includeResult.toggle() } label: {
                    HStack(spacing: 4) { Image(systemName: includeResult ? "checkmark.square.fill" : "square"); Text("with " + selected.title).lineLimit(1) }
                        .font(.system(size: 11)).foregroundStyle(includeResult ? p.accent : p.muted)
                }.buttonStyle(.plain).help("Use the selected result as context").frame(maxWidth: 220, alignment: .trailing)
            }
            MacSearchKey(label: "⌘↵", palette: p)
        }.font(.system(size: 12.5)).padding(.horizontal, 12).padding(.vertical, 9)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(p.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 6)
    }

    private func localAskRow(_ p: MacSearchPalette) -> some View {
        Button { askQuestion = .init(text: trimmedQuery) } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(p.accent).frame(width: 22)
                Text("Ask your notes: “\(trimmedQuery)”").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                MacSearchKey(label: "⌘↵", palette: p)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).font(.system(size: 12.5)).padding(.horizontal, 12).padding(.vertical, 9)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(p.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 6)
    }

    private func openLocal(_ path: String) {
        let origin = workspace.workspaceID
        askQuestion = nil
        Task {
            do { try await workspace.openSearchNote(path: path, stableID: nil, workspaceID: origin); workspace.showSearch = false }
            catch { issue = error.localizedDescription }
        }
    }

    private func resultPreview(_ item: NativeSearchItem, _ p: MacSearchPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Label(item.collection.rawValue + (item.location.isEmpty || item.location == item.collection.rawValue ? "" : " · " + item.location), systemImage: item.collection.icon)
                        .font(.caption).foregroundStyle(p.muted).lineLimit(1)
                    Text(item.title).font(.title3.bold()).textSelection(.enabled)
                    let properties = item.properties.filter { !$0.value.isEmpty }.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                    if !properties.isEmpty {
                        MacSearchFlow(spacing: 5) {
                            ForEach(properties, id: \.key) { entry in
                                HStack(spacing: 4) { Text(entry.key).foregroundStyle(p.muted); Text(entry.value.joined(separator: ", ")).lineLimit(1) }
                                    .font(.system(size: 11)).padding(.horizontal, 7).padding(.vertical, 2).background(p.hover, in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                    if let issue = item.issue { Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    if item.draft { Text("Includes an unsaved local draft.").font(.caption).foregroundStyle(.orange) }
                    MacSearchMarkdown(source: previewBody(item), title: item.title, palette: p)
                        .id(item.id + NativeHistory.hash(item.title + "\n" + String(item.text.prefix(16_000))))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            HStack(spacing: 8) {
                Button { open(item) } label: { Text("Open  ↵").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 11).padding(.vertical, 5).foregroundStyle(p.onAccent).background(p.accent, in: RoundedRectangle(cornerRadius: 6)) }
                    .buttonStyle(.plain).disabled(opening)
                if CloudAIFeature.enabled { Button(action: ask) { Text("Ask AI  ⌘↵").font(.system(size: 12)).padding(.horizontal, 11).padding(.vertical, 5).overlay(RoundedRectangle(cornerRadius: 6).stroke(p.line)) }
                    .buttonStyle(.plain).disabled(trimmedQuery.isEmpty || model.loading || opening) }
                Spacer()
                Text("Click again to open").font(.caption).foregroundStyle(p.muted)
            }.padding(.horizontal, 16).padding(.vertical, 10).overlay(alignment: .top) { Rectangle().fill(p.line).frame(height: 1) }
        }
    }

    /// Note text without its trailing search-only path lines and frontmatter.
    private func previewBody(_ item: NativeSearchItem) -> String {
        var text = item.text
        switch item.target {
        case .note(let path, _): if text.hasSuffix("\n" + path) { text.removeLast(path.count + 1) }
        case .external: for _ in 0..<2 { if let cut = text.range(of: "\n", options: .backwards) { text = String(text[..<cut.lowerBound]) } }
        case .file, .task, .conversation: return String(item.preview.prefix(16_000))
        }
        return String(NativeFrontmatter(text).body.prefix(16_000))
    }

    private func footer(_ p: MacSearchPalette) -> some View {
        HStack(spacing: 14) {
            Text("↑↓ navigate"); Text("click preview"); Text("↵ open"); Text("⌘↵ ask AI")
            Spacer(minLength: 8)
            if model.filesLoading || model.externalLoading {
                ProgressView().controlSize(.mini)
                Text(model.filesLoading ? "Indexing file contents…" : "Checking external files…").lineLimit(1)
            } else if let notice = model.fileNotice { Text(notice.replacingOccurrences(of: " Refresh to check file changes.", with: "")).lineLimit(1).help(notice) }
            if let result = model.result, !browsingRecent { Text("\(result.total) " + (result.total == 1 ? "result" : "results")) }
            Button { Task { await workspace.refresh(); refresh = UUID() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).disabled(opening).help("Refresh search index")
        }.font(.system(size: 11)).foregroundStyle(p.muted).padding(.horizontal, 16).padding(.vertical, 8)
            .background(p.surface).overlay(alignment: .top) { Rectangle().fill(p.line).frame(height: 1) }
    }

    // MARK: Actions

    /// First click previews; clicking the previewed row again opens it.
    private func activate(_ item: NativeSearchItem) {
        if previewing, selected?.id == item.id { open(item) }
        else { selectedKey = item.id; previewing = true }
    }
    private func close() {
        if showsPreview { previewing = false; focused = true } else { workspace.showSearch = false }
    }
    private func moveSelection(_ direction: Int) {
        let items = ordered
        guard !items.isEmpty else { return }
        let index = items.firstIndex(where: { $0.id == selected?.id }) ?? 0
        selectedKey = items[max(0, min(items.count - 1, index + direction))].id
    }
    private func ask() {
        guard !trimmedQuery.isEmpty else { return }
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

// MARK: - Theme

/// Search surfaces derived from the seven user theme roles.
struct MacSearchPalette {
    let background, surface, text, muted, line, hover, accent, accentSoft, onAccent: Color
    init(_ theme: MacTheme) {
        background = theme.color(.editorBg); surface = theme.color(.surface); text = theme.color(.text); accent = theme.color(.accent)
        muted = text.opacity(0.6); line = text.opacity(0.11); hover = text.opacity(0.06); accentSoft = accent.opacity(0.15)
        onAccent = theme.color(.editorBg)
    }
}

private struct MacSearchChip: View {
    let title: String
    let active: Bool
    var chevron = false
    let palette: MacSearchPalette
    var body: some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)) }
        }.font(.system(size: 11.5)).foregroundStyle(active ? palette.accent : palette.muted)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(active ? palette.accentSoft : .clear, in: Capsule())
            .overlay(Capsule().stroke(active ? .clear : palette.line))
            .contentShape(Capsule())
    }
}

private struct MacSearchKey: View {
    let label: String
    let palette: MacSearchPalette
    var body: some View {
        Text(label).font(.system(size: 10.5)).foregroundStyle(palette.muted).padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.line)).fixedSize()
    }
}

private struct MacSearchRow: View {
    let item: NativeSearchItem
    let query: String
    let selected: Bool
    let palette: MacSearchPalette
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        let p = palette
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.collection.icon).font(.system(size: 11)).frame(width: 22, height: 22)
                    .foregroundStyle(selected ? p.onAccent : p.muted)
                    .background(selected ? p.accent : p.hover, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(MacSearchHighlight.apply(item.title, query: query, palette: p)).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        if item.draft { Text("Draft").font(.caption2).foregroundStyle(.orange) }
                        if item.archived { Text("Archived").font(.caption2).foregroundStyle(p.muted) }
                    }
                    Text(MacSearchHighlight.apply(subtitle, query: query, palette: p)).font(.system(size: 11.5)).foregroundStyle(p.muted).lineLimit(1)
                    if let problem = item.issue { Text(problem).font(.caption).foregroundStyle(.orange).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Text(Self.date(item.modified)).font(.system(size: 10.5)).foregroundStyle(p.muted).padding(.top, 2)
            }.padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? p.accentSoft : hovering ? p.hover : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 6).onHover { hovering = $0 }
            .accessibilityLabel(item.title).accessibilityHint(selected ? "Click again to open" : "Preview")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var subtitle: String {
        let excerpt = query.isEmpty ? "" : NativeSearch.excerpt(item, query: query)
        let location = item.location.isEmpty || item.location == item.collection.rawValue ? "" : item.location
        return [excerpt, location].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty(item.collection.rawValue)
    }
    static func date(_ date: Date) -> String {
        guard date > .distantPast.addingTimeInterval(1) else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
        return sameYear ? date.formatted(.dateTime.day().month(.abbreviated)) : date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private extension String { func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self } }

enum MacSearchHighlight {
    static func apply(_ text: String, query: String, palette: MacSearchPalette) -> AttributedString {
        var result = AttributedString(text)
        for token in query.split(whereSeparator: \.isWhitespace).map(String.init) where !token.isEmpty {
            var search = text.startIndex..<text.endIndex
            while let range = text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive], range: search) {
                if let target = Range(range, in: result) { result[target].backgroundColor = palette.accent.opacity(0.28) }
                search = range.upperBound..<text.endIndex
            }
        }
        return result
    }
}

/// Lightweight, read-only Markdown for the preview pane: headings, bullets,
/// checkboxes, quotes and inline styling. The note's own H1 title is omitted.
private struct MacSearchMarkdown: View {
    let source: String
    let title: String
    let palette: MacSearchPalette
    var body: some View {
        let blocks = Self.blocks(source, title: title)
        if blocks.isEmpty { Text("No body content.").font(.callout).foregroundStyle(palette.muted) }
        else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in view(block) }
            }.textSelection(.enabled)
        }
    }
    enum Block { case heading(Int, String), bullet(String, Int), check(Bool, String, Int), quote(String), code(String), rule, paragraph(String) }
    @ViewBuilder private func view(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text)).font(.system(size: [17, 15, 13.5, 13, 13, 13][min(level, 6) - 1], weight: .semibold)).padding(.top, 4)
        case .bullet(let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•").foregroundStyle(palette.muted); Text(Self.inline(text)) }.padding(.leading, CGFloat(depth) * 14)
        case .check(let done, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: done ? "checkmark.square.fill" : "square").foregroundStyle(done ? palette.accent : palette.muted)
                Text(Self.inline(text)).strikethrough(done).foregroundStyle(done ? palette.muted : palette.text)
            }.padding(.leading, CGFloat(depth) * 14)
        case .quote(let text):
            Text(Self.inline(text)).foregroundStyle(palette.muted).padding(.leading, 10).overlay(alignment: .leading) { Rectangle().fill(palette.line).frame(width: 2) }
        case .code(let text):
            Text(text).font(.system(size: 11.5, design: .monospaced)).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(palette.hover, in: RoundedRectangle(cornerRadius: 6))
        case .rule: Rectangle().fill(palette.line).frame(height: 1).padding(.vertical, 4)
        case .paragraph(let text): Text(Self.inline(text))
        }
    }
    static func inline(_ text: String) -> AttributedString {
        // Wiki links read as plain titles in a preview.
        let cleaned = text.replacingOccurrences(of: #"\[\[([^\]|]+)\|?([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
        return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(cleaned)
    }
    static func blocks(_ source: String, title: String) -> [Block] {
        var blocks: [Block] = [], paragraph: [String] = [], code: [String]? = nil, skippedTitle = false
        func flush() { if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] } }
        for raw in source.components(separatedBy: .newlines) {
            if var lines = code {
                if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") { blocks.append(.code(lines.joined(separator: "\n"))); code = nil } else { lines.append(raw); code = lines }
                continue
            }
            let line = raw.trimmingCharacters(in: .whitespaces)
            let depth = (raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }) / 2
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("```") { flush(); code = []; continue }
            if let match = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flush()
                let text = String(match.2)
                if !skippedTitle, blocks.isEmpty, match.1.count == 1, text.trimmingCharacters(in: .whitespaces) == title { skippedTitle = true; continue }
                blocks.append(.heading(match.1.count, text)); continue
            }
            if line.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil { flush(); blocks.append(.rule); continue }
            if let match = line.firstMatch(of: /^[-*+]\s+\[([ xX])\]\s+(.*)$/) { flush(); blocks.append(.check(match.1 != " ", String(match.2), depth)); continue }
            if let match = line.firstMatch(of: /^(?:[-*+]|\d+[.)])\s+(.*)$/) { flush(); blocks.append(.bullet(String(match.1), depth)); continue }
            if line.hasPrefix(">") { flush(); blocks.append(.quote(String(line.drop { $0 == ">" || $0 == " " }))); continue }
            paragraph.append(line)
        }
        flush()
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        return blocks
    }
}

/// Wrapping row of property pills.
private struct MacSearchFlow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews) {
            for (index, x) in row.items { subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified) }
        }
    }
    private struct Row { var items: [(Int, CGFloat)] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }
    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width > 0, rows[rows.count - 1].width + spacing + size.width > width {
                let previous = rows[rows.count - 1]
                rows.append(Row(y: previous.y + previous.height + spacing))
            }
            let x = rows[rows.count - 1].width == 0 ? 0 : rows[rows.count - 1].width + spacing
            rows[rows.count - 1].items.append((index, x))
            rows[rows.count - 1].width = x + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

struct MacLocalAskQuestion: Identifiable {
    let id = UUID()
    let text: String
}
