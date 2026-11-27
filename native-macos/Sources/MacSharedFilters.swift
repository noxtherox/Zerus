import Foundation

/// Portable desktop filter keys differ from the native controls' display labels.
/// Patch only fields owned by these controls, retaining future client metadata.
enum MacSharedFilters {
    static let sorts: [NativeNoteSort: String] = [.updatedDescending: "updated-desc", .updatedAscending: "updated-asc", .createdDescending: "created-desc", .createdAscending: "created-asc", .titleAscending: "title-asc", .titleDescending: "title-desc"]
    static let dates: [NativePropertyDateComparison: String] = [.on: "on", .before: "before", .after: "after", .onOrBefore: "on-or-before", .onOrAfter: "on-or-after", .between: "between"]
    static let conditions: [NativePropertyCondition: String] = [.empty: "empty", .notEmpty: "not-empty", .checked: "checked", .unchecked: "unchecked", .number: "number", .relativeDate: "relative-date"]
    static let numbers: [NativeNumberComparison: String] = [.equal: "eq", .notEqual: "neq", .greater: "gt", .greaterOrEqual: "gte", .less: "lt", .lessOrEqual: "lte", .between: "between"]
    static let relativeDates: [NativeRelativeDate: String] = [.overdue: "before-today", .today: "today", .tomorrow: "tomorrow", .yesterday: "yesterday", .next7: "next-7-days", .last7: "last-7-days", .thisWeek: "this-week", .thisMonth: "this-month", .next30: "next-30-days", .last30: "last-30-days", .upcoming: "after-today"]
    static func canPersist(_ filters: NativeCollectionFilters) -> Bool {
        filters.properties.allSatisfy { filter in
            if filter.condition != nil { return filter.isComplete }
            if let comparison = filter.dateComparison { return NativeCollectionPropertyFilter.isDate(filter.date) && (comparison != .between || NativeCollectionPropertyFilter.isDate(filter.endDate)) }
            return filter.values?.isEmpty != true
        }
    }
    static func decode(_ value: Any?) -> NativeCollectionFilters {
        let raw = value as? [String: Any] ?? [:]
        var filters = NativeCollectionFilters(sort: sorts.first { $0.value == raw["sort"] as? String }?.key ?? .createdDescending)
        switch raw["date"] as? String { case "today": filters.date = .today; case "last-7-days": filters.date = .week; case "last-30-days": filters.date = .month; default: break }
        filters.includeArchived = raw["showArchived"] as? Bool ?? false
        filters.matchAnyProperty = raw["propertyMatch"] as? String == "any"
        filters.properties = (raw["properties"] as? [[String: Any]] ?? []).compactMap { property in
            guard let name = (property["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            if let condition = decodeCondition(property["condition"], name: name) { return condition }
            let date = property["date"] as? [String: Any]
            let comparison = dates.first { $0.value == date?["operator"] as? String }?.key
            let start = date?["date"] as? String ?? "", end = date?["endDate"] as? String ?? ""
            let validDate = comparison != nil && NativeCollectionPropertyFilter.isDate(start) && (comparison != .between || NativeCollectionPropertyFilter.isDate(end))
            let keys = property["valueKeys"] as? [String] ?? (property["valueKey"] as? String).map { [$0] }
            // Desktop normalization discards an empty accepted-value set.
            if keys?.isEmpty == true && !validDate { return nil }
            return .init(name: name, values: keys.map { Set($0.compactMap(decodeValue)) }, dateComparison: validDate ? comparison : nil, date: validDate ? start : "", endDate: validDate ? end : "")
        }
        return filters
    }
    /// Conditions are stored beside `valueKeys: null`, so a client that predates
    /// them still reads the filter as "has property" instead of dropping it.
    static func decodeCondition(_ value: Any?, name: String) -> NativeCollectionPropertyFilter? {
        guard let raw = value as? [String: Any], let condition = conditions.first(where: { $0.value == raw["kind"] as? String })?.key else { return nil }
        var filter = NativeCollectionPropertyFilter(name: name, condition: condition)
        switch condition {
        case .number:
            guard let comparison = numbers.first(where: { $0.value == raw["operator"] as? String })?.key, let number = numberText(raw["value"]) else { return nil }
            filter.numberComparison = comparison; filter.number = number
            if comparison == .between { guard let end = numberText(raw["endValue"]) else { return nil }; filter.endNumber = end }
        case .relativeDate:
            guard let range = relativeDates.first(where: { $0.value == raw["range"] as? String })?.key else { return nil }
            filter.relativeDate = range
        default: break
        }
        return filter
    }
    private static func numberText(_ value: Any?) -> String? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.stringValue
    }
    static func encodeCondition(_ filter: NativeCollectionPropertyFilter) -> [String: Any]? {
        guard let condition = filter.condition, let kind = conditions[condition] else { return nil }
        var raw: [String: Any] = ["kind": kind]
        switch condition {
        case .number:
            raw["operator"] = numbers[filter.numberComparison]
            raw["value"] = NativeCollectionPropertyFilter.parseNumber(filter.number) ?? 0
            if filter.numberComparison == .between { raw["endValue"] = NativeCollectionPropertyFilter.parseNumber(filter.endNumber) ?? 0 }
        case .relativeDate: raw["range"] = relativeDates[filter.relativeDate]
        default: break
        }
        return raw
    }
    static func decodeValue(_ key: String) -> NativeCollectionValue? {
        guard let separator = key.firstIndex(of: ":") else { return nil }
        let kind: NativeCollectionValue.Kind
        switch key[..<separator] { case "string": kind = .text; case "number": kind = .number; case "boolean": kind = .checkbox; default: return nil }
        return .init(kind: kind, value: String(key[key.index(after: separator)...]))
    }
    static func valueKey(_ value: NativeCollectionValue) -> String {
        let kind: String = switch value.kind { case .text: "string"; case .number: "number"; case .checkbox: "boolean" }
        return kind + ":" + value.value
    }
    static func patch(_ filters: NativeCollectionFilters, into value: Any?) -> [String: Any] {
        var raw = value as? [String: Any] ?? [:]
        raw["sort"] = sorts[filters.sort] ?? "created-desc"
        switch filters.date { case .any: raw["date"] = NSNull(); case .today: raw["date"] = "today"; case .week: raw["date"] = "last-7-days"; case .month: raw["date"] = "last-30-days" }
        raw["showArchived"] = filters.includeArchived; raw["propertyMatch"] = filters.matchAnyProperty ? "any" : "all"
        let old = raw["properties"] as? [[String: Any]] ?? []
        raw["properties"] = filters.properties.map { filter -> [String: Any] in
            var property = old.first { ($0["name"] as? String)?.caseInsensitiveCompare(filter.name) == .orderedSame } ?? [:]
            property["name"] = filter.name
            if let condition = encodeCondition(filter) {
                property["condition"] = condition; property["valueKeys"] = NSNull()
                property.removeValue(forKey: "valueKey"); property.removeValue(forKey: "date")
                return property
            }
            property.removeValue(forKey: "condition")
            property["valueKeys"] = filter.values.map { $0.sorted { $0.id < $1.id }.map(valueKey) } as Any? ?? NSNull()
            property.removeValue(forKey: "valueKey")
            if let comparison = filter.dateComparison {
                var date = property["date"] as? [String: Any] ?? [:]
                date["operator"] = dates[comparison]; date["date"] = filter.date
                if comparison == .between { date["endDate"] = filter.endDate } else { date.removeValue(forKey: "endDate") }
                property["date"] = date
            } else { property.removeValue(forKey: "date") }
            return property
        }
        return raw
    }
}

extension MacViewSnapshot {
    func filters(_ owner: String) -> NativeCollectionFilters? {
        guard let config = object[owner] as? [String: Any] else { return nil }
        return MacSharedFilters.decode(config["filters"])
    }
}
extension VaultFiles {
    func macSaveFilters(owner: String, filters: NativeCollectionFilters) throws -> MacViewSnapshot {
        let snapshot = try macViewSnapshot()
        guard snapshot.object[owner] == nil || snapshot.object[owner] is [String: Any] else { throw VaultFailure(message: "This folder’s saved view has an unsupported format.") }
        var object = snapshot.object, raw = object[owner] as? [String: Any] ?? [:]
        raw["filters"] = MacSharedFilters.patch(filters, into: raw["filters"]); object[owner] = raw
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try applyTransaction([.init(path: ".zerus/views.json", before: snapshot.bytes, after: bytes)], historySource: "macos")
        return .init(bytes: bytes, object: object)
    }
}
