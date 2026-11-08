import Foundation

enum NativeSearchCollection: String, CaseIterable, Sendable {
    case notes = "Notes", external = "External notes", files = "Files", links = "Saved links", tasks = "Tasks", chats = "AI conversations"
    var icon: String { switch self { case .notes, .external: "doc.text"; case .files: "doc"; case .links: "link"; case .tasks: "checkmark.circle"; case .chats: "sparkles" } }
}
struct NativeSearchConversation: Identifiable, Sendable {
    enum Origin: Sendable { case current, nativeArchive(URL), shared(String) }
    let id: String
    let title: String
    let modified: Date
    let archived: Bool
    let messages: [ChatMessage]
    let origin: Origin
    var text: String { messages.map { $0.role + ": " + $0.content }.joined(separator: "\n\n") }
}
struct NativeSearchItem: Identifiable, Sendable {
    enum Target: Sendable {
        case note(path: String, stableID: String?)
        case external(UUID)
        case task(String)
        case file(String)
        case conversation(NativeSearchConversation)
    }
    let id: String
    let collection: NativeSearchCollection
    let title: String
    let text: String
    let location: String
    let folder: String?
    let modified: Date
    let archived: Bool
    let properties: [String: [String]]
    let propertyExcerpts: [String]
    let completed: Bool?
    let priority: String?
    let draft: Bool
    let target: Target
    var issue: String?
    var preview: String
    var normalizedTitle: String
    var normalizedText: String
    var titleWords: [String]
    var words: [String]
    init(id: String, collection: NativeSearchCollection, title: String, text: String, location: String, folder: String? = nil, modified: Date, archived: Bool = false, properties: [String: [String]] = [:], propertyExcerpts: [String] = [], completed: Bool? = nil, priority: String? = nil, draft: Bool = false, target: Target, preview: String? = nil) {
        self.id = id; self.collection = collection; self.title = title; self.text = text; self.location = location; self.folder = folder; self.modified = modified; self.archived = archived; self.properties = properties; self.propertyExcerpts = propertyExcerpts; self.completed = completed; self.priority = priority; self.draft = draft; self.target = target; self.preview = preview ?? text
        normalizedTitle = NativeSearch.normalize(title)
        normalizedText = NativeSearch.normalize(text + "\n" + location)
        titleWords = NativeSearch.words(normalizedTitle); words = NativeSearch.words(normalizedTitle + "\n" + normalizedText)
    }
}
struct NativeSearchFilters: Equatable, Sendable {
    var collection: NativeSearchCollection?
    var days = 0
    var archived = false
    var folder = ""
    var property = ""
    var value = ""
    var status = ""
    var priority = ""
    var isEmpty: Bool { self == Self() }
}
struct NativeSearchTaskSource: Sendable {
    let id: String
    let title: String
    let category: String
    let list: String
    let priority: String
    let scheduled: String
    let due: String
    let completed: Bool
    let modified: Date
}
struct NativeSearchFile: Sendable { let path: String; let modified: Date }
struct NativeSearchSources: Sendable {
    let workspaceID: UUID
    let notes: [NoteDocument]
    let drafts: Set<String>
    let tasks: [NativeSearchTaskSource]
}
struct NativeSearchSupplement: Sendable {
    let files: [NativeSearchFile]
    let conversations: [NativeSearchConversation]
    let problems: [String]
}
struct NativeSearchResult: Sendable {
    let workspaceID: UUID
    let items: [NativeSearchItem]
    let total: Int
    let folders: [String]
    let properties: [String]
    let problems: [String]
}
struct NativeSearchDocument: Sendable { let name: String; let text: String }
struct NativeSearchAskRequest: Identifiable, Sendable {
    let id = UUID()
    let workspaceID: UUID
    let prompt: String
    let notes: Set<String>
    let document: NativeSearchDocument?
}

enum NativeSearch {
    static func normalize(_ value: String) -> String { value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    static func words(_ text: String) -> [String] { text.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty } }
    private static func near(_ left: String, _ right: String) -> Bool {
        if left == right { return true }
        let a = Array(left), b = Array(right)
        guard a.count >= 4, abs(a.count - b.count) <= 1 else { return false }
        var i = 0
        while i < min(a.count, b.count), a[i] == b[i] { i += 1 }
        if a.count == b.count {
            if a.dropFirst(i + 1) == b.dropFirst(i + 1) { return true }
            return i + 1 < a.count && a[i] == b[i + 1] && a[i + 1] == b[i] && a.dropFirst(i + 2) == b.dropFirst(i + 2)
        }
        return a.count > b.count ? a.dropFirst(i + 1) == b.dropFirst(i) : a.dropFirst(i) == b.dropFirst(i + 1)
    }
    static func score(_ item: NativeSearchItem, query: String) -> Int {
        let q = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines)), title = item.normalizedTitle
        if q.isEmpty { return 1 }
        if title == q { return 600 }; if title.hasPrefix(q) { return 550 }; if title.contains(q) { return 500 }
        let tokens = q.split(whereSeparator: \.isWhitespace).map(String.init)
        if tokens.allSatisfy({ title.contains($0) }) { return 450 }
        if tokens.allSatisfy({ title.contains($0) || item.normalizedText.contains($0) }) { return 300 }
        if tokens.allSatisfy({ token in item.titleWords.contains { $0.contains(token) || near(token, $0) } }) { return 150 }
        return tokens.allSatisfy({ token in item.words.contains { $0.contains(token) || near(token, $0) } }) ? 100 : 0
    }
    static func excerpt(_ item: NativeSearchItem, query: String) -> String {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let metadata = item.propertyExcerpts.filter { line in tokens.contains { normalize(line).contains(normalize($0)) } }
        if !metadata.isEmpty { return String(metadata.joined(separator: " · ").prefix(240)) }
        let text = item.preview
        let match = tokens.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }.first
        let offset = match.map { text.distance(from: text.startIndex, to: $0.lowerBound) } ?? 0
        let start = max(0, offset - 60)
        let excerpt = String(text.dropFirst(start).prefix(240)).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return (start > 0 ? "…" : "") + excerpt
    }
    private static func fields(_ note: NoteDocument) -> (properties: [String: [String]], excerpts: [String]) {
        let fields = NativeFrontmatter(note.content)
        var properties: [String: [String]] = [:], excerpts: [String] = []
        for entry in fields.entries where !entry.key.lowercased().hasPrefix("zerus-") {
            if case .number(let value) = entry.value, let number = Double(value) { properties[entry.key] = [NSNumber(value: number).stringValue] }
            else { properties[entry.key] = entry.value?.selections ?? [] }
            excerpts.append((note.content as NSString).substring(with: entry.range).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " "))
        }
        return (properties, excerpts)
    }
    static func externalItems(_ records: [NativeExternalSearchRecord]) throws -> [NativeSearchItem] {
        try records.map { record in
            try Task.checkCancellation()
            let entry = record.entry
            let note = record.document ?? NoteDocument(path: entry.name, content: "", modified: .distantPast)
            let fields = fields(note)
            var item = NativeSearchItem(id: "external:" + entry.id.uuidString, collection: .external, title: note.title,
                text: note.content + "\n" + entry.name + "\n" + note.path, location: "External notes · " + entry.parent, folder: entry.parent,
                modified: note.modified, archived: note.archived, properties: fields.properties, propertyExcerpts: fields.excerpts,
                draft: record.draft, target: .external(entry.id), preview: record.document == nil ? (record.issue ?? "Checking the selected file…") : note.snippet)
            item.issue = record.issue
            return item
        }
    }
    static func items(_ source: NativeSearchSources, supplement: NativeSearchSupplement) throws -> [NativeSearchItem] {
        let identities = Dictionary(grouping: source.notes.compactMap { $0.stableID }, by: { $0 })
        var items: [NativeSearchItem] = []
        for note in source.notes where !note.trashed {
            try Task.checkCancellation()
            let (properties, excerpts) = fields(note)
            let file = note.fileHub != nil || note.unfiledFileHub
            let collection: NativeSearchCollection = file ? .files : note.savedLink != nil || note.unfiledSavedLink ? .links : .notes
            let stable = note.stableID.flatMap { identities[$0]?.count == 1 ? $0 : nil }
            let key = stable.map { "note-id:" + $0 } ?? "note-path:" + note.path
            let preview = note.snippet
            items.append(.init(id: key, collection: collection, title: note.title, text: note.content + "\n" + note.path, location: note.folder, folder: note.folder, modified: note.modified, archived: note.archived, properties: properties, propertyExcerpts: excerpts, draft: source.drafts.contains(note.path), target: .note(path: note.path, stableID: stable), preview: preview))
        }
        for task in source.tasks {
            let location = [task.list, task.category].filter { !$0.isEmpty }.joined(separator: " · ")
            let text = [task.title, task.category, task.priority, task.scheduled, task.due, task.completed ? "Completed" : "Open"].filter { !$0.isEmpty }.joined(separator: "\n")
            let preview = [task.completed ? "Completed" : "Open", task.priority == "none" ? "" : task.priority.capitalized + " priority", task.scheduled.isEmpty ? "" : "Scheduled " + task.scheduled, task.due.isEmpty ? "" : "Due " + task.due].filter { !$0.isEmpty }.joined(separator: " · ")
            items.append(.init(id: "task:" + task.id, collection: .tasks, title: task.title, text: text, location: location, modified: task.modified, completed: task.completed, priority: task.priority, target: .task(task.id), preview: preview))
        }
        for file in supplement.files {
            let folder = (file.path as NSString).deletingLastPathComponent
            items.append(.init(id: "file:" + file.path, collection: .files, title: (file.path as NSString).lastPathComponent, text: file.path, location: folder.isEmpty ? "Inbox" : folder, folder: folder.isEmpty ? "Inbox" : folder, modified: file.modified, target: .file(file.path)))
        }
        for chat in supplement.conversations {
            items.append(.init(id: "chat:" + chat.id, collection: .chats, title: chat.title, text: chat.text, location: "AI conversations", modified: chat.modified, archived: chat.archived, target: .conversation(chat)))
        }
        return items
    }
}

actor NativeSearchEngine {
    private var workspaceID: UUID?
    private var items: [NativeSearchItem] = []
    private var problems: [String] = []
    func rebuild(_ sources: NativeSearchSources, supplement: NativeSearchSupplement) throws {
        let next = try NativeSearch.items(sources, supplement: supplement)
        try Task.checkCancellation()
        workspaceID = sources.workspaceID; items = next; problems = supplement.problems
    }
    func replaceExternal(_ records: [NativeExternalSearchRecord], workspace expected: UUID) throws {
        guard workspaceID == expected else { throw CancellationError() }
        let next = try NativeSearch.externalItems(records)
        try Task.checkCancellation()
        items = items.filter { $0.collection != .external } + next
    }
    func search(workspace expected: UUID, query: String, filters: NativeSearchFilters, recent: [String], limit: Int = 80, now: Date = Date()) throws -> NativeSearchResult {
        guard workspaceID == expected else { throw CancellationError() }
        var matches: [(item: NativeSearchItem, score: Int)] = []
        for item in items {
            try Task.checkCancellation()
            guard filters.collection == nil || item.collection == filters.collection, !item.archived || filters.archived,
                  filters.days == 0 || item.modified >= now.addingTimeInterval(-Double(filters.days) * 86400), filters.folder.isEmpty || item.folder == filters.folder,
                  filters.property.isEmpty || item.properties[filters.property].map({ values in filters.value.isEmpty || values.contains { NativeSearch.normalize($0) == NativeSearch.normalize(filters.value) } }) == true,
                  filters.status.isEmpty || item.completed == (filters.status == "completed"), filters.priority.isEmpty || item.priority == filters.priority else { continue }
            let score = NativeSearch.score(item, query: query)
            if score > 0 { matches.append((item, score)) }
        }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filters.isEmpty {
            let order = Dictionary(recent.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
            matches = matches.filter { order[$0.item.id] != nil }.sorted { order[$0.item.id]! < order[$1.item.id]! }
        } else { matches.sort { $0.score != $1.score ? $0.score > $1.score : $0.item.modified != $1.item.modified ? $0.item.modified > $1.item.modified : $0.item.id < $1.item.id } }
        let available = items.filter { filters.collection == nil || $0.collection == filters.collection }
        return .init(workspaceID: expected, items: Array(matches.prefix(max(0, limit))).map(\.item), total: matches.count, folders: Array(Set(available.compactMap(\.folder))).sorted(), properties: Array(Set(available.flatMap { $0.properties.keys })).sorted(), problems: problems)
    }
}
