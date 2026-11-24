import Foundation

/// Exact review records, large messages and field groups live beside the small
/// CAS journal. Paths derive from the run and digest, never from a synced path.
enum MacAgentPayloads {
    static let maximum = 128 * 1024 * 1024
    static func path(_ id: UUID, digest: String) -> String { ".zerus/native-ai/payloads/" + id.uuidString.lowercased() + "/" + digest + ".json" }
    static func expanded(_ object: [String: Any], id: UUID, read: ((String) throws -> Data)?) throws -> [String: Any] {
        var result = object, total = 0
        func load(_ value: Any) throws -> Data {
            guard let reference = value as? [String: Any], Set(reference.keys) == ["digest", "bytes"],
                  let digest = reference["digest"] as? String, digest.count == 64, digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
                  let count = NativeHistory.integer(reference["bytes"]), count > 0, count <= maximum - total,
                  let read else { throw VaultFailure(message: "This AI history/review payload is unavailable or unsupported. Its journal is preserved.") }
            total += count
            let bytes = try read(path(id, digest: digest))
            guard bytes.count == count, NativeHistory.hash(bytes) == digest else { throw VaultFailure(message: "An exact AI history/review payload changed or is incomplete. Nothing was applied.") }
            return bytes
        }
        if NativeHistory.integer(object["version"]) == 8 || object["macFieldGroups"] != nil || object["macRunVersion"] != nil {
            guard NativeHistory.integer(object["version"]) == 8,
                  let version = NativeHistory.integer(object["macRunVersion"]), (1...7).contains(version),
                  let groups = object["macFieldGroups"] as? [[String: Any]], !groups.isEmpty, groups.count <= maximum / 32_000 + 1 else {
                throw VaultFailure(message: "This AI field-payload manifest is unsupported. Its journal is preserved.")
            }
            result["version"] = version; result["macFieldGroups"] = nil; result["macRunVersion"] = nil
            for group in groups {
                guard let fields = try NativeJSON.object(with: load(group)) as? [String: Any], !fields.isEmpty else {
                    throw VaultFailure(message: "This AI field payload is unsupported. Its journal is preserved.")
                }
                for (key, value) in fields {
                    guard !["version", "id", "chatID", "owner", "macFieldGroups", "macRunVersion"].contains(key), result[key] == nil else {
                        throw VaultFailure(message: "This AI field payload conflicts with its manifest. Nothing was applied.")
                    }
                    result[key] = value
                }
            }
        }
        for key in ["proposals", "receipts", "messages"] {
            guard let rows = result[key] as? [[String: Any]] else { continue }
            result[key] = try rows.map { row -> [String: Any] in
                guard let payload = row["macPayload"] else { return row }
                let identity = key == "messages" ? "role" : "id"
                let version = NativeHistory.integer(result["version"]) ?? 0
                guard (key == "messages" ? [6, 7].contains(version) : [5, 6, 7].contains(version)), Set(row.keys) == [identity, "macPayload"] else {
                    throw VaultFailure(message: "This AI history/review payload is unavailable or unsupported. Its journal is preserved.")
                }
                guard let value = try NativeJSON.object(with: load(payload)) as? [String: Any], value["macPayload"] == nil,
                      value[identity] as? String == row[identity] as? String else { throw VaultFailure(message: "An exact AI history/review payload changed or is incomplete. Nothing was applied.") }
                return value
            }
        }
        return result
    }
    static func prepare(_ bytes: Data, previous: Data?, id: UUID, read: @escaping (String) throws -> Data, exists: (String) throws -> Bool) throws -> NativeAgentStoragePlan {
        guard bytes.count <= maximum, var object = try NativeJSON.object(with: bytes) as? [String: Any] else { throw VaultFailure(message: "This AI journal exceeds the bounded review storage allowance. Its previous journal is preserved.") }
        object = try expanded(object, id: id, read: read)
        if bytes.count <= 6_000_000, (NativeHistory.integer(object["version"]) ?? 0) < 5 {
            return .init(record: try NativeAgentJournal.decode(bytes, id: id), changes: [.init(path: NativeAgentJournal.path(id), before: previous, after: bytes)])
        }
        // Guard old referenced records as well as new records at transaction time.
        var dependencies: [String: Data] = [:]
        if let previous, let old = try NativeJSON.object(with: previous) as? [String: Any] {
            _ = try expanded(old, id: id, read: { path in let bytes = try read(path); dependencies[path] = bytes; return bytes })
        }
        var payloads: [String: Data] = [:]
        if bytes.count > 6_000_000 || (NativeHistory.integer(object["version"]) ?? 0) >= 5 {
            object["version"] = max(5, NativeHistory.integer(object["version"]) ?? 0)
            for key in ["proposals", "receipts", "messages"] {
                guard let rows = object[key] as? [[String: Any]] else { continue }
                object[key] = try rows.map { row -> [String: Any] in
                    let value = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
                    guard value.count >= 32_000 else { return row }
                    let digest = NativeHistory.hash(value), path = path(id, digest: digest)
                    payloads[path] = value
                    let identity = key == "messages" ? "role" : "id"
                    if key == "messages" { object["version"] = max(6, NativeHistory.integer(object["version"]) ?? 0) }
                    return [identity: row[identity]!, "macPayload": ["digest": digest, "bytes": value.count]]
                }
            }
        }
        // Format 8 is a storage envelope. Keep the logical run version (and
        // therefore legacy import/index policy) separate from field placement.
        if (NativeHistory.integer(object["version"]) ?? 0) >= 5 {
            var groups: [[String: Any]] = []
            func store(_ fields: [String: Any]) throws {
                let value = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
                let digest = NativeHistory.hash(value)
                payloads[path(id, digest: digest)] = value
                groups.append(["digest": digest, "bytes": value.count])
            }
            let identities: Set<String> = ["version", "id", "chatID", "owner"]
            var small: [(String, Any, Int)] = []
            for key in object.keys.sorted() where !identities.contains(key) {
                let field = [key: object[key]!]
                let count = try JSONSerialization.data(withJSONObject: field, options: [.sortedKeys, .withoutEscapingSlashes]).count
                if count >= 32_000 { try store(field); object[key] = nil }
                else { small.append((key, field[key]!, count)) }
            }
            // A wide metadata object can exceed the manifest limit even when
            // none of its values is large. Batch its small fields as well.
            if try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]).count > 6_000_000 {
                var fields: [String: Any] = [:], count = 2
                for (key, value, size) in small {
                    let addition = size - 2 + (fields.isEmpty ? 0 : 1)
                    if count + addition > 32_000, !fields.isEmpty { try store(fields); fields = [:]; count = 2 }
                    count += size - 2 + (fields.isEmpty ? 0 : 1)
                    fields[key] = value; object[key] = nil
                }
                if !fields.isEmpty { try store(fields) }
            }
            if !groups.isEmpty {
                object["macRunVersion"] = object["version"]; object["version"] = 8; object["macFieldGroups"] = groups
            }
        }
        let stored = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        let record = try NativeAgentJournal.decode(stored, id: id, readPayload: { path in if let value = payloads[path] { return value }; return try read(path) })
        var changes: [VaultFileChange] = []
        for (path, value) in payloads.sorted(by: { $0.key < $1.key }) {
            let before = try exists(path) ? read(path) : nil
            guard before == nil || before == value else { throw VaultFailure(message: "An immutable AI history/review payload changed. Nothing was replaced.") }
            changes.append(.init(path: path, before: before, after: value))
        }
        for (path, value) in dependencies.sorted(by: { $0.key < $1.key }) where payloads[path] == nil {
            changes.append(.init(path: path, before: value, after: value))
        }
        changes.append(.init(path: NativeAgentJournal.path(id), before: previous, after: stored))
        return .init(record: record, changes: changes)
    }
}
