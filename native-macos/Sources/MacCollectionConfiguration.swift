import Foundation

/// The folder-backed layout fields use the desktop's views.json wire format.
/// Filters and fields introduced by other clients are retained byte-for-value.
struct MacCollectionLayout: Codable, Equatable {
    var groupBy: String? = nil
    var dateProperty: String? = nil
    var visibleProperties: [String] = []
    var boardColumnOrder: [String: [String]] = [:]
    init() {}
    init(_ raw: [String: Any]) {
        func name(_ value: Any?) -> String? {
            guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }; return text
        }
        groupBy = name(raw["groupBy"]); dateProperty = name(raw["dateProperty"])
        var seen = Set<String>()
        visibleProperties = (raw["visibleProperties"] as? [String] ?? []).compactMap { value in
            guard let value = name(value), seen.insert(value.lowercased()).inserted else { return nil }; return value
        }
        for (key, values) in raw["boardColumnOrder"] as? [String: [String]] ?? [:] {
            guard let key = name(key)?.lowercased() else { continue }; var seen = Set<String>()
            boardColumnOrder[key] = values.filter { seen.insert($0).inserted }
        }
    }
    static let modes = ["List": "list", "Gallery": "gallery", "Kanban": "board", "Table": "table", "Calendar": "calendar"]
}
struct MacViewSnapshot: @unchecked Sendable {
    let bytes: Data?
    let object: [String: Any]
    func layout(_ owner: String) -> MacCollectionLayout? { (object[owner] as? [String: Any]).map(MacCollectionLayout.init) }
    func mode(_ owner: String) -> String? {
        guard let config = object[owner] as? [String: Any] else { return nil }; let raw = config["mode"] as? String ?? "list"
        return MacCollectionLayout.modes.first { $0.value == raw }?.key ?? "List"
    }
}
extension VaultFiles {
    func macViewSnapshot() throws -> MacViewSnapshot {
        let path = ".zerus/views.json", location = try url(for: path)
        guard FileManager.default.fileExists(atPath: location.path) else { return .init(bytes: nil, object: [:]) }
        let bytes = try read(path)
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "Saved collection views have an unsupported format. They were left unchanged.") }
        return .init(bytes: bytes, object: object)
    }
    func macSaveView(owner: String, mode: String, layout: MacCollectionLayout) throws -> MacViewSnapshot {
        let snapshot = try macViewSnapshot()
        guard snapshot.object[owner] == nil || snapshot.object[owner] is [String: Any] else { throw VaultFailure(message: "This folder’s saved view has an unsupported format.") }
        var object = snapshot.object, raw = object[owner] as? [String: Any] ?? [:]
        raw["mode"] = MacCollectionLayout.modes[mode] ?? "list"
        raw["groupBy"] = layout.groupBy.map { $0 as Any } ?? NSNull()
        raw["dateProperty"] = layout.dateProperty.map { $0 as Any } ?? NSNull()
        raw["visibleProperties"] = layout.visibleProperties; raw["boardColumnOrder"] = layout.boardColumnOrder
        object[owner] = raw
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try applyTransaction([.init(path: ".zerus/views.json", before: snapshot.bytes, after: bytes)], historySource: "macos")
        return .init(bytes: bytes, object: object)
    }
}

struct MacCollectionGroup: Identifiable {
    let value: String?
    var notes: [NoteDocument]
    var checkbox: Bool? = nil
    var relationPath: String? = nil
    var id: String { relationPath.map { "relation:" + $0 } ?? checkbox.map { "checkbox:" + String($0) } ?? value.map { "value:" + $0 } ?? "absent" }
}

/// Shared interpretation for all three layouts: absent values are distinct from
/// a literal “No value”, and dates are local calendar days, never UTC instants.
enum MacCollectionValues {
    static func definitions(notes: [NoteDocument], schema: NativeSchemaSnapshot?) -> [NativePropertyDefinition] {
        var fields: [String: NativePropertyDefinition] = [:]
        // Effective definitions depend on the containing folder, not the note
        // filename. Reuse them within this inventory only; the next calculation
        // reads its current schema snapshot, including outside edits.
        var folderDefinitions: [String: [NativePropertyDefinition]] = [:]
        for note in notes {
            let defined: [NativePropertyDefinition]
            if schema?.bytes == nil { defined = [] }
            else {
                let folder = note.path.lastIndex(of: "/").map { String(note.path[..<$0]) } ?? ""
                if let cached = folderDefinitions[folder] { defined = cached }
                else {
                    defined = (try? schema?.effective(notePath: note.path)) ?? []
                    folderDefinitions[folder] = defined
                }
            }
            for field in defined where !field.hidden && field.type != .unsupported { fields[field.id] = field }
            for entry in MacNoteFrontmatter.read(note.content).entries where !entry.key.lowercased().hasPrefix("zerus-") {
                if let value = entry.value, fields[entry.key.lowercased()] == nil, !defined.contains(where: { $0.id == entry.id && ($0.hidden || $0.type == .unsupported) }) { fields[entry.key.lowercased()] = .init(name: entry.key, type: .inferred(value)) }
            }
        }
        return fields.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func value(_ note: NoteDocument, name: String) -> NativePropertyValue? { MacNoteFrontmatter.read(note.content).entry(name)?.value }
    static func boardValues(_ note: NoteDocument, name: String) -> [String] {
        var seen = Set<String>()
        return (value(note, name: name)?.selections ?? []).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    /// Gallery groups contain only observed values, in collection order. A
    /// relation list places one card in each distinct related-note group.
    static func galleryGroups(notes: [NoteDocument], name: String, relationNotes: [NoteDocument]? = nil) -> [MacCollectionGroup] {
        var result: [MacCollectionGroup] = [], indexes: [String: Int] = [:], resolutions: [String: String] = [:]
        func target(_ raw: String) -> String? {
            guard let relationNotes else { return nil }
            if let path = resolutions[raw] { return path.isEmpty ? nil : path }
            let literal = raw.hasPrefix("[[") && raw.hasSuffix("]]") ? raw : "[[" + raw + "]]"
            let matches = NoteReference(wikilink: literal)?.targets(in: relationNotes) ?? []
            let path = matches.count == 1 ? matches[0].path : ""
            resolutions[raw] = path
            return path.isEmpty ? nil : path
        }
        for note in notes {
            var seen = Set<String>()
            let property = value(note, name: name)
            let checkbox: Bool?
            if case .checkbox(let flag) = property { checkbox = flag } else { checkbox = nil }
            let values = (property?.selections ?? []).filter { !$0.isEmpty && seen.insert($0).inserted }
            var groups = Set<String>()
            for value in values.isEmpty ? [nil] : values.map(Optional.some) {
                let relationPath = checkbox == nil ? value.flatMap(target) : nil
                let group = MacCollectionGroup(value: value, notes: [], checkbox: checkbox, relationPath: relationPath)
                guard groups.insert(group.id).inserted else { continue }
                if let index = indexes[group.id] { result[index].notes.append(note) }
                else { indexes[group.id] = result.count; result.append(.init(value: value, notes: [note], checkbox: checkbox, relationPath: relationPath)) }
            }
        }
        return result
    }
    /// Array-valued notes appear once per distinct value, even when the
    /// current schema offers a single-value picker. A comma in scalar text is
    /// part of that one label. Empty arrays retain the native No value group.
    static func boardGroups(notes: [NoteDocument], field: NativePropertyDefinition, order: [String], overrides: [String: [String]] = [:]) -> [MacCollectionGroup] {
        var labels = field.options, members: [String: [NoteDocument]] = [:], absent: [NoteDocument] = []
        for note in notes {
            let values = overrides[note.path] ?? boardValues(note, name: field.name)
            if values.isEmpty { absent.append(note) }
            for value in values {
                if !labels.contains(value) { labels.append(value) }
                members[value, default: []].append(note)
            }
        }
        let keys = ["__no_value__"] + labels
        var seen = Set<String>()
        let sorted = (order.filter { keys.contains($0) } + keys).filter { seen.insert($0).inserted }
        return sorted.map { key in
            MacCollectionGroup(value: key == "__no_value__" ? nil : key, notes: key == "__no_value__" ? absent : members[key] ?? [])
        }
    }
    /// Build one render's dated groups and navigation order together. The
    /// formatter belongs to this calculation, so locale/time-zone changes are
    /// read afresh without rebuilding it for every note or keeping global state.
    static func calendar(notes: [NoteDocument], name: String, month: Date) -> (dated: [String: [NoteDocument]], order: [String]) {
        let formatter = dateFormatter(), calendar = Calendar.current
        var dated: [String: [NoteDocument]] = [:], ordered: [(note: NoteDocument, date: Date?)] = []
        for note in notes {
            let date = day(note, name: name, formatter: formatter)
            dated[date.map { formatter.string(from: $0) } ?? "", default: []].append(note)
            if let date, !calendar.isDate(date, equalTo: month, toGranularity: .month) { continue }
            ordered.append((note, date))
        }
        let order = ordered.enumerated().sorted { left, right in
            let a = left.element.date ?? .distantFuture, b = right.element.date ?? .distantFuture
            return a == b ? left.offset < right.offset : a < b
        }.map { $0.element.note.path }
        return (dated, order)
    }
    static func day(_ note: NoteDocument, name: String) -> Date? { day(note, name: name, formatter: dateFormatter()) }
    private static func day(_ note: NoteDocument, name: String, formatter: @autoclosure () -> DateFormatter) -> Date? {
        guard case .text(let value) = value(note, name: name), value.count >= 10 else { return nil }
        let day = String(value.prefix(10)), formatter = formatter()
        guard NativeCollectionPropertyFilter.isDate(day), let date = formatter.date(from: day), formatter.string(from: date) == day else { return nil }
        return date
    }
    static func dateFormatter() -> DateFormatter {
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX"); value.calendar = Calendar(identifier: .gregorian); value.dateFormat = "yyyy-MM-dd"; value.isLenient = false; return value
    }
    static func wireDate(_ date: Date) -> String { dateFormatter().string(from: date) }
}
