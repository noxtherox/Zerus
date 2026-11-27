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
/// Conditions stored beside value and fixed-date filters. Saved views persist
/// them under the portable `condition` key that desktop and web also read.
enum NativePropertyCondition: String, CaseIterable, Identifiable, Sendable {
    case empty = "Is empty", notEmpty = "Is not empty", checked = "Is checked", unchecked = "Is unchecked"
    case number = "Number comparison", relativeDate = "Relative date"
    var id: String { rawValue }
}
enum NativeNumberComparison: String, CaseIterable, Identifiable, Sendable {
    case equal = "=", notEqual = "≠", greater = ">", greaterOrEqual = "≥", less = "<", lessOrEqual = "≤", between = "Between"
    var id: String { rawValue }
}
/// Ranges are resolved against the local calendar day each time a view is
/// evaluated, so a saved "Overdue" view never goes stale. Weeks start Monday
/// on every platform so a shared view selects the same notes everywhere.
enum NativeRelativeDate: String, CaseIterable, Identifiable, Sendable {
    case overdue = "Before today", today = "Today", tomorrow = "Tomorrow", yesterday = "Yesterday"
    case next7 = "Next 7 days", last7 = "Last 7 days", thisWeek = "This week", thisMonth = "This month"
    case next30 = "Next 30 days", last30 = "Last 30 days", upcoming = "After today"
    var id: String { rawValue }
    /// Inclusive yyyy-MM-dd bounds; nil leaves that side open.
    func bounds(now: Date, calendar: Calendar) -> (String?, String?) {
        var calendar = calendar; calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, from base: Date? = nil) -> String { NativeTask.day(calendar.date(byAdding: .day, value: offset, to: base ?? today) ?? today, calendar: calendar) }
        switch self {
        case .overdue: return (nil, day(-1))
        case .today: return (day(0), day(0))
        case .tomorrow: return (day(1), day(1))
        case .yesterday: return (day(-1), day(-1))
        case .next7: return (day(0), day(6))
        case .last7: return (day(-6), day(0))
        case .next30: return (day(0), day(29))
        case .last30: return (day(-29), day(0))
        case .upcoming: return (day(1), nil)
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            return (day(0, from: start), day(6, from: start))
        case .thisMonth:
            let interval = calendar.dateInterval(of: .month, for: today)
            let start = interval?.start ?? today
            let length = calendar.range(of: .day, in: .month, for: today)?.count ?? 1
            return (day(0, from: start), day(length - 1, from: start))
        }
    }
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
    var condition: NativePropertyCondition?
    var numberComparison: NativeNumberComparison = .equal
    var number = ""
    var endNumber = ""
    var relativeDate: NativeRelativeDate = .today
    /// A blank, missing or unparseable value counts as empty.
    static func isEmpty(_ property: NativePropertyValue?) -> Bool {
        switch property {
        case nil: return true
        case .text(let value), .number(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .list(let values): return values.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case .checkbox: return false
        }
    }
    static func parseNumber(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^-?(\d+\.?\d*|\.\d+)$"#, options: .regularExpression) != nil else { return nil }
        return Double(trimmed)
    }
    /// An incomplete number condition cannot be saved or applied.
    var isComplete: Bool {
        guard condition == .number else { return true }
        return Self.parseNumber(number) != nil && (numberComparison != .between || Self.parseNumber(endNumber) != nil)
    }
    func matches(_ fields: NativeFrontmatter, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let condition {
            let property = fields.entry(name)?.value
            switch condition {
            case .empty: return Self.isEmpty(property)
            case .notEmpty: return !Self.isEmpty(property)
            case .checked: return property == .checkbox(true)
            case .unchecked: return property == .checkbox(false) || Self.isEmpty(property)
            case .number:
                // An unfinished number leaves the list unchanged while typing.
                guard isComplete, let target = Self.parseNumber(number) else { return true }
                guard case .number(let raw)? = property, let value = Self.parseNumber(raw) else { return false }
                switch numberComparison {
                case .equal: return value == target
                case .notEqual: return value != target
                case .greater: return value > target
                case .greaterOrEqual: return value >= target
                case .less: return value < target
                case .lessOrEqual: return value <= target
                case .between:
                    let end = Self.parseNumber(endNumber) ?? target
                    return value >= min(target, end) && value <= max(target, end)
                }
            case .relativeDate:
                guard let property else { return false }
                let (start, end) = relativeDate.bounds(now: now, calendar: calendar)
                return NativeCollectionValue.values(property).contains { value in
                    value.kind == .text && Self.isDate(value.value) && start.map { value.value >= $0 } != false && end.map { value.value <= $0 } != false
                }
            }
        }
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
    var isNumber = false
    var isCheckbox = false
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
    /// A query without whitespace cannot match across the joining spaces, so
    /// each part is searched in place instead of building a joined copy of
    /// every note. A spaced query keeps the joined form and its exact result.
    private static func matches(_ note: NoteDocument, search: String, spaced: Bool) -> Bool {
        if spaced { return (note.title + " " + note.content + " " + note.folder).localizedStandardContains(search) }
        return note.title.localizedStandardContains(search) || note.content.localizedStandardContains(search) || note.folder.localizedStandardContains(search)
    }
    func apply(_ notes: [NoteDocument], query: String = "", archiveOnly: Bool = false, fileNames: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> [NoteDocument] {
        let threshold = calendar.date(byAdding: .day, value: -(date.days - 1), to: calendar.startOfDay(for: now)) ?? now
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortingByTitle = sort == .titleAscending || sort == .titleDescending
        let spaced = search.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
        // Read immutable sort keys once per note, not on every comparison.
        // Frontmatter parsing inside an O(n log n) comparator caused sustained
        // UI-thread CPU use when browsing a real vault on iPhone 11.
        return notes.filter { note in
            guard !note.trashed, archiveOnly ? note.archived : (includeArchived || !note.archived),
                  folders.isEmpty || folders.contains(note.folder),
                  extensions.isEmpty || note.fileHub.map({ extensions.contains(($0.name as NSString).pathExtension.lowercased()) }) == true,
                  date == .any || note.modified >= threshold,
                  search.isEmpty || Self.matches(note, search: search, spaced: spaced) else { return false }
            if properties.isEmpty { return true }
            let fields = NativeFrontmatterCache.read(note.content)
            return matchAnyProperty ? properties.contains { $0.matches(fields, now: now, calendar: calendar) } : properties.allSatisfy { $0.matches(fields, now: now, calendar: calendar) }
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
            let declared = types[key, default: []]
            result.isDate = declared == [NativePropertyType.date.rawValue] || (declared.isEmpty && !option.values.isEmpty && option.values.allSatisfy { $0.kind == .text && NativeCollectionPropertyFilter.isDate($0.value) })
            result.isNumber = declared == [NativePropertyType.number.rawValue] || (declared.isEmpty && !option.values.isEmpty && option.values.allSatisfy { $0.kind == .number })
            result.isCheckbox = declared == [NativePropertyType.checkbox.rawValue] || (declared.isEmpty && !option.values.isEmpty && option.values.allSatisfy { $0.kind == .checkbox })
            return result
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
