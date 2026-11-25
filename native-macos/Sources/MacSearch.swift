import SwiftUI

extension VaultFiles {
    func macSearchFiles(_ paths: [String]) throws -> NativeSearchSupplement {
        var files: [NativeSearchFile] = [], problems: [String] = []
        for path in paths {
            try Task.checkCancellation()
            do {
                let values = try url(for: path).resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey])
                if values.isSymbolicLink != true { files.append(.init(path: path, modified: values.contentModificationDate ?? .distantPast)) }
            } catch { problems.append("Some file details are unavailable. Refresh to retry.") }
        }
        var chats: [NativeSearchConversation] = []
        if CloudAIFeature.enabled { do {
            let history = try conversations()
            problems += history.issues
            for conversation in history.conversations where conversation.deletedAt == nil {
                try Task.checkCancellation()
                chats.append(.init(id: "shared:" + conversation.id, title: conversation.title,
                    modified: try MacConversations.date(conversation.updatedAt), archived: conversation.archivedAt != nil,
                    messages: conversation.messages.map { ChatMessage(role: $0.role, content: $0.text) }, origin: .shared(conversation.id)))
            }
        } catch is CancellationError { throw CancellationError() }
        catch { problems.append("Conversation history is unavailable. Other results remain searchable; refresh to retry.") } }
        return .init(files: files, conversations: chats, problems: Array(Set(problems)).sorted())
    }
}

@MainActor final class MacSearchModel: ObservableObject {
    @Published var query = ""
    @Published var filters = NativeSearchFilters()
    @Published private(set) var result: NativeSearchResult?
    @Published private(set) var loading = false
    @Published private(set) var externalLoading = false
    @Published private(set) var filesLoading = false
    @Published private(set) var fileNotice: String?
    @Published private(set) var issue: String?
    private let engine = NativeSearchEngine()
    private let external: NativeExternalNotesStore
    private var epoch = UUID(), request = UUID()
    private var workspaceID: UUID?
    private var ready = false
    private var recent: [String] = []
    private var recentKey = ""
    private var limit = 80
    init(external: NativeExternalNotesStore) { self.external = external }
    func rebuild(_ workspace: MacWorkspace) async {
        let epoch = UUID(); self.epoch = epoch; ready = false; result = nil; loading = true; issue = nil; filesLoading = false; fileNotice = nil; externalLoading = false
        let origin = workspace.workspaceID
        workspaceID = origin
        guard let io = workspace.io, let root = workspace.root else { loading = false; return }
        recentKey = "zerus.mac.search.recent." + NativeHistory.hash(root.standardizedFileURL.resolvingSymlinksInPath().path)
        recent = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        do {
            let sources = workspace.searchSources(), paths = workspace.files
            let supplement = try await io.macSearchFiles(paths)
            try Task.checkCancellation()
            guard self.epoch == epoch, workspace.workspaceID == origin else { return }
            try await engine.rebuild(sources, supplement: supplement)
            guard self.epoch == epoch, workspace.workspaceID == origin else { return }
            ready = true; await run()
            filesLoading = !supplement.files.isEmpty
            if filesLoading {
                let index = try await MacFileSearchIndex.build(supplement.files, root: root)
                try Task.checkCancellation()
                guard self.epoch == epoch, workspace.workspaceID == origin else { return }
                try await engine.replaceFiles(index.files, workspace: origin)
                filesLoading = false
                fileNotice = "Content indexed in \(index.indexed) files · \(index.filenameOnly) filename only. Refresh to check file changes."
                await run()
            }
            externalLoading = true
            let entries = try await external.entries(), store = external
            var records: [NativeExternalSearchRecord] = []
            await withTaskGroup(of: NativeExternalSearchRecord.self) { group in
                var iterator = entries.makeIterator()
                for _ in 0..<min(4, entries.count) { if let entry = iterator.next() { group.addTask { await NativeExternalSearchRecord.read(entry, store: store) } } }
                while let record = await group.next() {
                    if Task.isCancelled { group.cancelAll(); break }
                    records.append(record)
                    if let entry = iterator.next() { group.addTask { await NativeExternalSearchRecord.read(entry, store: store) } }
                }
            }
            try Task.checkCancellation()
            guard self.epoch == epoch, workspace.workspaceID == origin else { return }
            try await engine.replaceExternal(records, workspace: origin)
            externalLoading = false; await run()
        } catch is CancellationError { if self.epoch == epoch { loading = false; externalLoading = false; filesLoading = false } }
        catch { if self.epoch == epoch { issue = error.localizedDescription; loading = false; externalLoading = false; filesLoading = false } }
    }
    func run(resetLimit: Bool = true) async {
        guard ready, let workspaceID else { return }
        if resetLimit { limit = 80 }
        let request = UUID(); self.request = request
        let epoch = epoch, query = query, filters = filters
        loading = true
        do {
            let result = try await engine.search(workspace: workspaceID, query: query, filters: filters, recent: recent, limit: limit)
            try Task.checkCancellation()
            guard self.request == request, self.epoch == epoch else { return }
            self.result = result; loading = false
        } catch is CancellationError { if self.request == request { loading = false } }
        catch { if self.request == request { issue = error.localizedDescription; loading = false } }
    }
    func more() async { limit += 80; await run(resetLimit: false) }
    func visited(_ item: NativeSearchItem) {
        recent.removeAll { $0 == item.id }; recent.insert(item.id, at: 0); recent = Array(recent.prefix(50))
        UserDefaults.standard.set(recent, forKey: recentKey)
    }
    func clearRecent() async { recent = []; UserDefaults.standard.set([], forKey: recentKey); await run() }
}
