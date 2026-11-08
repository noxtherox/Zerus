import Foundation

enum NativeNoteSort: String, CaseIterable, Identifiable, Sendable {
    case updatedDescending = "Recently updated", updatedAscending = "Least recently updated"
    case createdDescending = "Newest", createdAscending = "Oldest", titleAscending = "Title: A–Z", titleDescending = "Title: Z–A"
    var id: String { rawValue }
}
enum NativeNoteDate: String, CaseIterable, Identifiable, Sendable {
    case any = "Any time", today = "Today", week = "Last 7 days", month = "Last 30 days"
    var id: String { rawValue }
    var days: Int { switch self { case .any: 0; case .today: 1; case .week: 7; case .month: 30 } }
}
enum NativePropertyDateComparison: String, CaseIterable, Identifiable, Sendable {
    case on = "On", before = "Before", after = "After", onOrBefore = "On or before", onOrAfter = "On or after", between = "Between"
    var id: String { rawValue }
}
struct NativeCollectionValue: Hashable, Identifiable, Sendable {
    enum Kind: String, Sendable { case text, number, checkbox }
    let kind: Kind
    let value: String
    var id: String { kind.rawValue + ":" + value }
    var label: String { value.isEmpty ? "Empty" : value }
    static func values(_ property: NativePropertyValue) -> [Self] {
        switch property {
        case .text(let value): return [.init(kind: .text, value: value)]
        case .list(let values): return values.map { .init(kind: .text, value: $0) }
        case .checkbox(let value): return [.init(kind: .checkbox, value: value ? "true" : "false")]
        case .number(let value): return [.init(kind: .number, value: Double(value).map { NSNumber(value: $0).stringValue } ?? value)]
        }
    }
}
struct NativeCollectionPropertyFilter: Equatable, Identifiable, Sendable {
    let id = UUID()
    var name: String
    // nil means present, an empty set deliberately matches no values.
    var values: Set<NativeCollectionValue>?
    var dateComparison: NativePropertyDateComparison?
    var date = ""
    var endDate = ""
    func matches(_ fields: NativeFrontmatter) -> Bool {
        guard let property = fields.entry(name)?.value else { return false }
        if let comparison = dateComparison {
            guard Self.isDate(date) else { return false }
            return NativeCollectionValue.values(property).contains { value in
                guard value.kind == .text, Self.isDate(value.value) else { return false }
                switch comparison {
                case .on: return value.value == date
                case .before: return value.value < date
                case .after: return value.value > date
                case .onOrBefore: return value.value <= date
                case .onOrAfter: return value.value >= date
                case .between: return Self.isDate(endDate) && value.value >= min(date, endDate) && value.value <= max(date, endDate)
                }
            }
        }
        return values.map { !$0.isDisjoint(with: NativeCollectionValue.values(property)) } ?? true
    }
    static func isDate(_ value: String) -> Bool { value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
}
struct NativeCollectionPropertyOption: Identifiable {
    let name: String
    var values: Set<NativeCollectionValue>
    var isDate: Bool
    var id: String { name.lowercased() }
}
struct NativeCollectionFilters: Equatable, Sendable {
    var sort: NativeNoteSort = .updatedDescending
    var date: NativeNoteDate = .any
    var includeArchived = false
    var folders: Set<String> = []
    var extensions: Set<String> = []
    var matchAnyProperty = false
    var properties: [NativeCollectionPropertyFilter] = []
    var activeCount: Int { (sort == .updatedDescending ? 0 : 1) + (date == .any ? 0 : 1) + (includeArchived ? 1 : 0) + folders.count + extensions.count + properties.count }
    func apply(_ notes: [NoteDocument], query: String = "", archiveOnly: Bool = false, fileNames: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> [NoteDocument] {
        let threshold = calendar.date(byAdding: .day, value: -(date.days - 1), to: calendar.startOfDay(for: now)) ?? now
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortingByTitle = sort == .titleAscending || sort == .titleDescending
        // Read immutable sort keys once per note, not on every comparison.
        // Frontmatter parsing inside an O(n log n) comparator caused sustained
        // UI-thread CPU use when browsing a real vault on iPhone 11.
        return notes.filter { note in
            guard !note.trashed, archiveOnly ? note.archived : (includeArchived || !note.archived),
                  folders.isEmpty || folders.contains(note.folder),
                  extensions.isEmpty || note.fileHub.map({ extensions.contains(($0.name as NSString).pathExtension.lowercased()) }) == true,
                  date == .any || note.modified >= threshold,
                  search.isEmpty || (note.title + " " + note.content + " " + note.folder).localizedStandardContains(search) else { return false }
            if properties.isEmpty { return true }
            let fields = NativeFrontmatter(note.content)
            return matchAnyProperty ? properties.contains { $0.matches(fields) } : properties.allSatisfy { $0.matches(fields) }
        }.map { note in
            (note: note, pinned: note.pinned, title: sortingByTitle ? (fileNames ? (note.fileHub?.name ?? note.title) : note.title) : "")
        }.sorted { left, right in
            if left.pinned != right.pinned { return left.pinned }
            let a = left.note, b = right.note
            switch sort {
            case .updatedDescending: if a.modified != b.modified { return a.modified > b.modified }
            case .updatedAscending: if a.modified != b.modified { return a.modified < b.modified }
            case .createdDescending: if (a.created ?? a.modified) != (b.created ?? b.modified) { return (a.created ?? a.modified) > (b.created ?? b.modified) }
            case .createdAscending: if (a.created ?? a.modified) != (b.created ?? b.modified) { return (a.created ?? a.modified) < (b.created ?? b.modified) }
            case .titleAscending, .titleDescending:
                let result = left.title.localizedStandardCompare(right.title)
                if result != .orderedSame { return sort == .titleAscending ? result == .orderedAscending : result == .orderedDescending }
            }
            return a.path < b.path
        }.map(\.note)
    }
    func applyFiles(_ paths: [String], dates: [String: NativeFileDates], query: String = "", now: Date = Date(), calendar: Calendar = .current) -> [String] {
        guard properties.isEmpty else { return [] }
        let threshold = calendar.date(byAdding: .day, value: -(date.days - 1), to: calendar.startOfDay(for: now)) ?? now
        return paths.filter { path in
            let parent = (path as NSString).deletingLastPathComponent
            return (query.isEmpty || path.localizedStandardContains(query)) &&
                (folders.isEmpty || folders.contains(parent.isEmpty ? "Inbox" : parent)) &&
                (extensions.isEmpty || extensions.contains((path as NSString).pathExtension.lowercased())) &&
                (date == .any || (dates[path]?.modified ?? .distantPast) >= threshold)
        }.sorted { a, b in
            let left = dates[a], right = dates[b]
            switch sort {
            case .updatedDescending: if left?.modified != right?.modified { return (left?.modified ?? .distantPast) > (right?.modified ?? .distantPast) }
            case .updatedAscending: if left?.modified != right?.modified { return (left?.modified ?? .distantPast) < (right?.modified ?? .distantPast) }
            case .createdDescending, .createdAscending:
                let l = left?.created ?? left?.modified ?? .distantPast, r = right?.created ?? right?.modified ?? .distantPast
                if l != r { return sort == .createdDescending ? l > r : l < r }
            case .titleAscending, .titleDescending:
                let result = (a as NSString).lastPathComponent.localizedStandardCompare((b as NSString).lastPathComponent)
                if result != .orderedSame { return sort == .titleAscending ? result == .orderedAscending : result == .orderedDescending }
            }
            return a < b
        }
    }
    static func options(_ notes: [NoteDocument], schema: NativeSchemaSnapshot? = nil) -> [NativeCollectionPropertyOption] {
        var options: [String: NativeCollectionPropertyOption] = [:]
        var types: [String: Set<String>] = [:]
        for note in notes {
            let definitions = (try? schema?.effective(notePath: note.path)) ?? []
            for entry in NativeFrontmatter(note.content).entries where !entry.key.lowercased().hasPrefix("zerus-") {
                guard let value = entry.value else { continue }
                let key = entry.key.lowercased()
                var option = options[key] ?? .init(name: entry.key, values: [], isDate: false)
                option.values.formUnion(NativeCollectionValue.values(value))
                options[key] = option
                if let definition = definitions.first(where: { $0.id == key }) { types[key, default: []].insert(definition.type.rawValue) }
            }
        }
        return options.map { key, option in
            var result = option
            result.isDate = types[key] == [NativePropertyType.date.rawValue] || (types[key, default: []].isEmpty && !option.values.isEmpty && option.values.allSatisfy { $0.kind == .text && NativeCollectionPropertyFilter.isDate($0.value) })
            return result
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
