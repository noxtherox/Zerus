import Foundation

struct NativeSchemaSnapshot: Sendable {
    let root: URL
    let bytes: Data?
    var workspaceID: UUID? = nil
    var owners: [String] {
        guard let object = try? object() else { return [] }
        return object.keys.filter { object[$0] is [[String: Any]] }.sorted()
    }
    func definitions(owner: String) throws -> [NativePropertyDefinition] {
        let raw = try object()[owner]
        guard let raw else { return [] }
        guard let values = raw as? [[String: Any]] else { throw VaultFailure(message: "This folder’s definitions use an unsupported format.") }
        return try values.map { try NativePropertyDefinition.decoded($0, owner: owner) }
    }
    func effective(notePath: String) throws -> [NativePropertyDefinition] { try NativePropertyDefinition.effective(path: notePath, data: bytes) }
    private func object() throws -> [String: Any] {
        guard let bytes else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "The property definitions are not a JSON object.") }
        return object
    }

    func changes(owner: String, originalName: String?, definition: NativePropertyDefinition?, notes: [NoteDocument]) throws -> [VaultFileChange] {
        let segments = owner.split(separator: "/", omittingEmptySubsequences: false)
        guard owner.isEmpty || (segments.count <= 8 && !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("\\") })) else { throw VaultFailure(message: "Choose a valid folder for this property.") }
        var object = try object()
        if let existing = object[owner], !(existing is [[String: Any]]) { throw VaultFailure(message: "This folder’s definitions use an unsupported format.") }
        var owned = object[owner] as? [[String: Any]] ?? []
        let matches = owned.indices.filter { (owned[$0]["name"] as? String)?.caseInsensitiveCompare(originalName ?? "") == .orderedSame }
        if originalName != nil, matches.count != 1 { throw VaultFailure(message: "This definition changed or has duplicate names. Reload folder properties before editing it.") }
        let index = matches.first
        let original = try index.map { try NativePropertyDefinition.decoded(owned[$0], owner: owner) }
        if let original, original.type == .relation || original.type == .unsupported { throw VaultFailure(message: "This definition needs its dedicated editor and is preserved without changes.") }
        let next = try definition?.validated()
        if let next {
            guard !owned.indices.contains(where: { $0 != index && (owned[$0]["name"] as? String)?.caseInsensitiveCompare(next.name) == .orderedSame }) else { throw VaultFailure(message: "This folder already defines \(next.name).") }
            // Retain fields introduced by other clients or future versions.
            var raw = index.map { owned[$0] } ?? [:]
            raw["name"] = next.name; raw["type"] = next.type.rawValue
            if next.type == .list { raw["listOptions"] = next.options; raw["listMultiple"] = next.multiple }
            else { raw.removeValue(forKey: "listOptions"); raw.removeValue(forKey: "listMultiple") }
            if let index { owned[index] = raw } else { owned.append(raw) }
        } else if let index { owned.remove(at: index) }
        else { throw VaultFailure(message: "Choose a definition to remove.") }
        if owned.isEmpty { object.removeValue(forKey: owner) } else { object[owner] = owned }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let updated = NativeSchemaSnapshot(root: root, bytes: data)
        var changes: [VaultFileChange] = []
        if let original {
            for note in notes where !note.trashed && !note.path.hasPrefix(".zerus/") {
                guard owner.isEmpty ? !note.path.contains("/") : note.path.hasPrefix(owner + "/") else { continue }
                guard try effective(notePath: note.path).first(where: { $0.id == original.id })?.owner == owner else { continue }
                var content = note.content
                if let next {
                    if next.type == .list && !next.multiple, let entry = NativeFrontmatter(content).entry(original.name) {
                        guard let value = entry.value else { throw VaultFailure(message: "\(note.path) has a complex or duplicate \(original.name) value. Resolve it before changing this list to a single choice.") }
                        content = try NativeFrontmatter(content).setting(original.name, value: value.selections.first.map { .text($0) })
                    }
                    if original.name != next.name { content = try NativeFrontmatter(content).renaming(original.name, to: next.name) }
                } else if try updated.effective(notePath: note.path).first(where: { $0.id == original.id }) == nil {
                    content = try NativeFrontmatter(content).setting(original.name, value: nil)
                }
                if content != note.content { changes.append(VaultFileChange(path: note.path, before: Data(note.content.utf8), after: Data(content.utf8))) }
            }
        }
        if data != bytes { changes.append(VaultFileChange(path: ".zerus/properties.json", before: bytes, after: data)) }
        return changes
    }
}

extension NativePropertyDefinition {
    static func decoded(_ raw: [String: Any], owner: String) throws -> Self {
        guard let name = raw["name"] as? String, let type = raw["type"] as? String else { throw VaultFailure(message: "A property definition is missing its name or type.") }
        if type == "relation" {
            for key in ["relationTypeKey", "relationPairId"] where raw[key] != nil && !(raw[key] is String) { throw VaultFailure(message: "The \(name) relation has unsupported settings and is preserved without changes.") }
            for key in ["relationMultiple", "relationHidden", "relationInverseHidden"] where raw[key] != nil && !(raw[key] is Bool) { throw VaultFailure(message: "The \(name) relation has unsupported settings and is preserved without changes.") }
        }
        return Self(name: name, type: NativePropertyType(rawValue: type) ?? .unsupported, owner: owner, options: raw["listOptions"] as? [String] ?? [], multiple: raw["listMultiple"] as? Bool ?? false, hidden: raw["relationHidden"] as? Bool ?? false, relationTypeKey: raw["relationTypeKey"] as? String, relationMultiple: raw["relationMultiple"] as? Bool ?? false, relationPairID: (raw["relationPairId"] as? String).flatMap { $0.isEmpty ? nil : $0 }, relationInverseHidden: raw["relationInverseHidden"] as? Bool ?? false)
    }
    func validated() throws -> Self {
        guard name.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_ .-]{0,59}$"#, options: .regularExpression) != nil, name == name.trimmingCharacters(in: .whitespacesAndNewlines), !name.lowercased().hasPrefix("zerus-") else { throw VaultFailure(message: "Use up to 60 letters, numbers, spaces, dots, hyphens or underscores. Zerus-managed names are reserved.") }
        guard type != .relation && type != .unsupported else { throw VaultFailure(message: "Choose a supported property type.") }
        var normalized: [String] = []
        for choice in options {
            let value = choice.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && !normalized.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { normalized.append(value) }
        }
        guard type != .list || !normalized.isEmpty else { throw VaultFailure(message: "Add at least one list choice.") }
        return Self(name: name, type: type, owner: owner, options: normalized, multiple: multiple, hidden: hidden)
    }
}

extension VaultFiles {
    func schemaSnapshot() throws -> NativeSchemaSnapshot {
        let location = try url(for: ".zerus/properties.json")
        let bytes = FileManager.default.fileExists(atPath: location.path) ? try read(".zerus/properties.json") : nil
        let snapshot = NativeSchemaSnapshot(root: root, bytes: bytes)
        // Validate the JSON container before exposing edit actions.
        _ = try NativePropertyDefinition.effective(path: "note.md", data: bytes)
        return snapshot
    }
    func applySchemaChange(snapshot: NativeSchemaSnapshot, owner: String, originalName: String?, definition: NativePropertyDefinition?) throws -> VaultSnapshot {
        guard snapshot.root == root else { throw VaultFailure(message: "The vault changed. Reopen folder properties.") }
        let current = try scan()
        let changes = try snapshot.changes(owner: owner, originalName: originalName, definition: definition, notes: current.notes)
        try applyTransaction(changes)
        return try scan()
    }
}
