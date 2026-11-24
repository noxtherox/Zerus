import Foundation

struct MacSavedView: Identifiable {
    let id: String
    let name: String
    let recordBytes: Data
}
struct MacSavedViewSnapshot: @unchecked Sendable {
    let bytes: Data?
    let object: [String: Any]
    func entries(_ owner: String) -> [MacSavedView] {
        var seen = Set<String>()
        return (object[owner] as? [[String: Any]] ?? []).compactMap { raw in
            guard let id = raw["id"] as? String, !id.isEmpty, seen.insert(id).inserted, let name = raw["name"] as? String, !name.isEmpty, raw["config"] is [String: Any], let data = try? Self.encode(raw) else { return nil }
            return .init(id: id, name: name, recordBytes: data)
        }
    }
    static func encode(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
    func checked(_ owner: String, entry: MacSavedView) throws -> (Int, [[String: Any]]) {
        guard let records = object[owner] as? [[String: Any]] else { throw VaultFailure(message: "This folder’s saved views have changed. Reload them.") }
        let matches = records.indices.filter { records[$0]["id"] as? String == entry.id }
        guard matches.count == 1, let index = matches.first, try Self.encode(records[index]) == entry.recordBytes else { throw VaultFailure(message: "This saved view changed elsewhere. Reload it before applying this action.") }
        return (index, records)
    }
}
extension MacCollectionLayout {
    func patch(mode: String, into raw: [String: Any]) -> [String: Any] {
        var result = raw
        result["mode"] = Self.modes[mode] ?? "list"
        result["groupBy"] = groupBy.map { $0 as Any } ?? NSNull()
        result["dateProperty"] = dateProperty.map { $0 as Any } ?? NSNull()
        result["visibleProperties"] = visibleProperties; result["boardColumnOrder"] = boardColumnOrder
        return result
    }
}
extension VaultFiles {
    func macSavedViewSnapshot() throws -> MacSavedViewSnapshot {
        let path = ".zerus/saved-views.json", location = try url(for: path)
        guard FileManager.default.fileExists(atPath: location.path) else { return .init(bytes: nil, object: [:]) }
        let bytes = try read(path)
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "Named views have an unsupported format. They were left unchanged.") }
        return .init(bytes: bytes, object: object)
    }
    func macSavePreset(owner: String, name: String, mode: String, layout: MacCollectionLayout, filters: NativeCollectionFilters) throws -> MacSavedViewSnapshot {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw VaultFailure(message: "Enter a view name.") }
        let snapshot = try macSavedViewSnapshot(), active = try macViewSnapshot()
        guard snapshot.object[owner] == nil || snapshot.object[owner] is [[String: Any]] else { throw VaultFailure(message: "This folder’s named views have an unsupported format.") }
        var object = snapshot.object, records = object[owner] as? [[String: Any]] ?? []
        let matches = records.indices.filter { (records[$0]["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }
        guard matches.count <= 1 else { throw VaultFailure(message: "Several saved views have this name. Choose another name.") }
        var record = matches.first.map { records[$0] } ?? ["id": UUID().uuidString.lowercased()]
        if let index = matches.first {
            guard let id = record["id"] as? String, !id.isEmpty, record["config"] is [String: Any], records.indices.filter({ records[$0]["id"] as? String == id }).count == 1, records[index]["name"] is String else { throw VaultFailure(message: "This saved view uses an unsupported or ambiguous format. Choose a new name.") }
        }
        record["name"] = name
        var base = record["config"] as? [String: Any] ?? [:]
        let current = active.object[owner] as? [String: Any] ?? [:]
        var filterMetadata = base["filters"] as? [String: Any] ?? [:]
        filterMetadata.merge(current["filters"] as? [String: Any] ?? [:]) { _, new in new }
        base.merge(current) { _, new in new }; base["filters"] = filterMetadata
        var config = layout.patch(mode: mode, into: base)
        config["filters"] = MacSharedFilters.patch(filters, into: config["filters"]); record["config"] = config
        if let index = matches.first { records[index] = record } else { records.append(record) }
        object[owner] = records
        return try macWritePresets(snapshot, object: object)
    }
    func macRenamePreset(owner: String, entry: MacSavedView, name: String) throws -> MacSavedViewSnapshot {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw VaultFailure(message: "Enter a view name.") }
        let snapshot = try macSavedViewSnapshot(); var (index, records) = try snapshot.checked(owner, entry: entry)
        guard !records.indices.contains(where: { $0 != index && (records[$0]["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }) else { throw VaultFailure(message: "A saved view already uses this name.") }
        records[index]["name"] = name; var object = snapshot.object; object[owner] = records
        return try macWritePresets(snapshot, object: object)
    }
    func macDeletePreset(owner: String, entry: MacSavedView) throws -> MacSavedViewSnapshot {
        let snapshot = try macSavedViewSnapshot(); var (index, records) = try snapshot.checked(owner, entry: entry)
        records.remove(at: index); var object = snapshot.object
        if records.isEmpty { object.removeValue(forKey: owner) } else { object[owner] = records }
        return try macWritePresets(snapshot, object: object)
    }
    private func macWritePresets(_ snapshot: MacSavedViewSnapshot, object: [String: Any]) throws -> MacSavedViewSnapshot {
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try applyTransaction([.init(path: ".zerus/saved-views.json", before: snapshot.bytes, after: bytes)], historySource: "macos")
        return .init(bytes: bytes, object: object)
    }
    func macApplyPreset(owner: String, entry: MacSavedView) throws -> MacViewSnapshot {
        let saved = try macSavedViewSnapshot(), (index, records) = try saved.checked(owner, entry: entry)
        guard let config = records[index]["config"] as? [String: Any] else { throw VaultFailure(message: "This view uses an unsupported format.") }
        let active = try macViewSnapshot()
        guard active.object[owner] == nil || active.object[owner] is [String: Any] else { throw VaultFailure(message: "This folder’s active view has an unsupported format.") }
        var object = active.object, raw = object[owner] as? [String: Any] ?? [:]
        raw.merge(config) { _, value in value }; object[owner] = raw
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let savedURL = try url(for: ".zerus/saved-views.json")
        try applyTransaction([.init(path: ".zerus/views.json", before: active.bytes, after: bytes)], historySource: "macos", reading: [savedURL]) {
            guard try Data(contentsOf: savedURL) == saved.bytes else { throw VaultFailure(message: "Saved views changed during this action. Reload them.") }
        }
        return .init(bytes: bytes, object: object)
    }
}
