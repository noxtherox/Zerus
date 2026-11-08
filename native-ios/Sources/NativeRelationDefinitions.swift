import Foundation

struct NativeRelationDefinitionSnapshot: Sendable {
    let schema: NativeSchemaSnapshot
    let notes: [NoteDocument]

    func plan(owner: String, originalName: String?, definition: NativePropertyDefinition?) throws -> NativeRelationDefinitionPlan {
        try NativeRelationDefinitionMigration(snapshot: self).plan(owner: owner, originalName: originalName, definition: definition)
    }
}

struct NativeRelationDefinitionPlan: Sendable {
    let snapshot: NativeRelationDefinitionSnapshot
    let changes: [VaultFileChange]
    let affectedCount: Int
    let removing: Bool
    var changedNotes: [String] { changes.filter { $0.path.lowercased().hasSuffix(".md") && $0.before != $0.after }.map(\.path) }
    var hasChanges: Bool { changes.contains { $0.before != $0.after } }
}

/// Composes value migrations in memory. Only the final reviewed batch reaches disk.
private final class NativeRelationDefinitionMigration {
    let snapshot: NativeRelationDefinitionSnapshot
    var notes: [NoteDocument]
    var bytes: Data?
    var readPaths = Set<String>()
    init(snapshot: NativeRelationDefinitionSnapshot) {
        self.snapshot = snapshot; notes = snapshot.notes; bytes = snapshot.schema.bytes
    }
    var schema: NativeSchemaSnapshot { NativeSchemaSnapshot(root: snapshot.schema.root, bytes: bytes) }
    func object() throws -> [String: Any] {
        guard let bytes else { return [:] }
        guard let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "The property definitions are not a JSON object.") }
        return result
    }
    func store(_ object: [String: Any]) throws {
        bytes = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
    func consume(_ plan: NativeRelationPlan) throws {
        for change in plan.changes {
            if change.path == ".zerus/properties.json" { bytes = change.after }
            else if let index = notes.firstIndex(where: { $0.path == change.path }), let data = change.after, let text = String(data: data, encoding: .utf8) {
                readPaths.insert(change.path); notes[index].content = text
            }
        }
    }
    func migrateValues(path: String, name: String, clearing: Bool) throws {
        let value = NativeRelationSnapshot(schema: schema, notes: notes, sourcePath: path, name: name)
        let selection = try value.selection()
        try consume(value.plan(selected: clearing ? [] : selection.paths, unresolved: clearing ? [] : Set(selection.unresolved), preservingExistingMultiplicity: !clearing))
    }
    func restoreSourceValue(path: String, name: String, original: String) throws {
        if let index = notes.firstIndex(where: { $0.path == path }) {
            // Retiring a pair clears its source field as well. Keep that field's
            // exact original YAML while accepting generated identities and any
            // other inverse-field changes from the migration.
            let old = NativeFrontmatter(original), updated = NativeFrontmatter(notes[index].content)
            guard old.body == updated.body else { throw VaultFailure(message: "The relation migration changed the note body. Reload folder properties.") }
            var retained = original
            for key in Set(old.entries.map(\.id) + updated.entries.map(\.id)).sorted() where key != name.lowercased() {
                let previous = old.entry(key), next = updated.entry(key)
                guard previous?.value != next?.value else { continue }
                guard next == nil || next?.value != nil else { throw VaultFailure(message: "A related field uses unsupported YAML and cannot be converted safely.") }
                retained = try NativeFrontmatter(retained).setting(next?.key ?? previous!.key, value: next?.value)
            }
            notes[index].content = retained
        }
    }
    func effective(_ note: NoteDocument, in schema: NativeSchemaSnapshot) throws -> [NativePropertyDefinition] {
        let parts = NativeRelationSnapshot.owner(note).split(separator: "/")
        let owners = parts.isEmpty ? [""] : (1...parts.count).map { parts.prefix($0).joined(separator: "/") }
        for owner in owners {
            let definitions = try schema.definitions(owner: owner)
            guard Set(definitions.map(\.id)).count == definitions.count else { throw VaultFailure(message: "\(owner.isEmpty ? "Inbox" : owner) has duplicate definitions. Resolve them before editing relations.") }
        }
        return try schema.effective(notePath: note.path)
    }
    func plan(owner: String, originalName: String?, definition: NativePropertyDefinition?) throws -> NativeRelationDefinitionPlan {
        try NativePropertyDefinition.validateOwner(owner)
        let next = try definition.map { try $0.type == .relation ? $0.validatedRelation() : $0.validated() }
        guard next == nil || next?.owner == owner else { throw VaultFailure(message: "The relation’s folder changed. Reopen its definition.") }
        var object = try object()
        if let raw = object[owner], !(raw is [[String: Any]]) { throw VaultFailure(message: "This folder’s definitions use an unsupported format.") }
        let owned = object[owner] as? [[String: Any]] ?? []
        guard Set(owned.compactMap { ($0["name"] as? String)?.lowercased() }).count == owned.count else { throw VaultFailure(message: "This folder has invalid or duplicate definitions. Resolve them before editing relations.") }
        let index = owned.firstIndex { ($0["name"] as? String)?.caseInsensitiveCompare(originalName ?? "") == .orderedSame }
        if originalName != nil && index == nil { throw VaultFailure(message: "This definition changed. Reload folder properties.") }
        let original = try index.map { try NativePropertyDefinition.decoded(owned[$0], owner: owner) }
        guard original?.type == .relation || next?.type == .relation else { throw VaultFailure(message: "Choose a relation or convert a property to a relation.") }
        guard original?.type != .unsupported else { throw VaultFailure(message: "This property uses an unsupported type and is preserved without changes.") }
        guard next != nil || original != nil else { throw VaultFailure(message: "Choose a definition to remove.") }
        if let next, owned.indices.contains(where: { $0 != index && (owned[$0]["name"] as? String)?.caseInsensitiveCompare(next.name) == .orderedSame }) { throw VaultFailure(message: "This folder already defines \(next.name).") }
        func updatedOwned(_ current: [[String: Any]]) -> [[String: Any]] {
            var result = current
            let position = result.firstIndex { ($0["name"] as? String)?.caseInsensitiveCompare(originalName ?? "") == .orderedSame }
            if let next {
                var raw = position.map { result[$0] } ?? [:]
                raw["name"] = next.name; raw["type"] = next.type.rawValue
                if next.type == .relation {
                    raw["relationTypeKey"] = next.relationTypeKey ?? ""
                    raw["relationMultiple"] = next.relationMultiple
                    raw["relationHidden"] = next.hidden; raw["relationInverseHidden"] = next.relationInverseHidden
                    // A converted ordinary field starts a new pair. Pair identity
                    // is persisted by the migration, never accepted from a form.
                    if original?.type != .relation { raw.removeValue(forKey: "relationPairId") }
                    raw.removeValue(forKey: "listOptions"); raw.removeValue(forKey: "listMultiple")
                } else {
                    for key in ["relationTypeKey", "relationMultiple", "relationHidden", "relationInverseHidden", "relationPairId"] { raw.removeValue(forKey: key) }
                    if next.type == .list { raw["listOptions"] = next.options; raw["listMultiple"] = next.multiple }
                    else { raw.removeValue(forKey: "listOptions"); raw.removeValue(forKey: "listMultiple") }
                }
                if let position { result[position] = raw } else { result.append(raw) }
            } else if let position { result.remove(at: position) }
            return result
        }
        let proposed = updatedOwned(owned)
        if proposed.isEmpty { object.removeValue(forKey: owner) } else { object[owner] = proposed }
        let proposedSchema = NativeSchemaSnapshot(root: schema.root, bytes: try JSONSerialization.data(withJSONObject: object))
        let live = notes.filter { !$0.trashed && !$0.path.hasPrefix(".zerus/") }
        var affected: [String] = [], retainedValues: [(path: String, name: String, original: String)] = []
        for note in live {
            let noteOwner = NativeRelationSnapshot.owner(note)
            guard owner.isEmpty ? noteOwner.isEmpty : (noteOwner == owner || noteOwner.hasPrefix(owner + "/")) else { continue }
            let before = try effective(note, in: snapshot.schema)
            let after = try effective(note, in: proposedSchema)
            let previous = before.first { $0.id == (original?.id ?? next!.id) }
            let replacement = after.first { $0.id == (next?.id ?? original!.id) }
            let applies = original != nil ? previous?.owner == owner : replacement?.owner == owner
            guard applies else { continue }
            affected.append(note.path); readPaths.insert(note.path)
            if let next, original != nil, replacement?.owner != owner {
                throw VaultFailure(message: "\(note.path) overrides \(next.name). Choose another name so the renamed relation remains accessible.")
            }
            let retiring = previous?.type == .relation && (next == nil || original == nil || next?.type != .relation) && (replacement?.type != .relation || previous?.relationPairID == nil || previous?.relationPairID != replacement?.relationPairID)
            if retiring, let previous {
                _ = try NativeRelationSnapshot.values(note, name: previous.name)
                if replacement != nil { retainedValues.append((note.path, previous.name, note.content)) }
                try migrateValues(path: note.path, name: previous.name, clearing: true)
            }
        }
        // A note can be both a converted source and another source's inverse.
        // Restore every frozen value only after the entire old graph is retired.
        for value in retainedValues { try restoreSourceValue(path: value.path, name: value.name, original: value.original) }
        // Clear old pairs before replacing their definition; retain any inverse
        // definitions created during legacy pairing and all unrelated metadata.
        object = try self.object()
        let currentOwned = object[owner] as? [[String: Any]] ?? []
        let result = updatedOwned(currentOwned)
        if result.isEmpty { object.removeValue(forKey: owner) } else { object[owner] = result }
        try store(object)
        if let original, let next, original.name != next.name {
            for path in affected {
                let index = notes.firstIndex { $0.path == path }!
                notes[index].content = try NativeFrontmatter(notes[index].content).renaming(original.name, to: next.name)
            }
        }
        if next == nil, let original {
            for path in affected where try schema.effective(notePath: path).first(where: { $0.id == original.id }) == nil {
                let index = notes.firstIndex { $0.path == path }!
                notes[index].content = try NativeFrontmatter(notes[index].content).setting(original.name, value: nil)
            }
        }
        if let next, next.type == .list, !next.multiple {
            for path in affected {
                let index = notes.firstIndex { $0.path == path }!
                if let entry = NativeFrontmatter(notes[index].content).entry(next.name) {
                    guard let value = entry.value else { throw VaultFailure(message: "\(path) has an unsupported \(next.name) value. Resolve it before converting to a single choice.") }
                    notes[index].content = try NativeFrontmatter(notes[index].content).setting(next.name, value: value.selections.first.map { .text($0) })
                }
            }
        }
        // Reconcile populated fields under the resulting definition. Narrowing
        // constraints preserves existing links, including legacy multiple values.
        for path in affected {
            let note = notes.first { $0.path == path }!
            guard let relation = try effective(note, in: schema).first(where: { $0.id == (next?.id ?? original!.id) }), relation.type == .relation else { continue }
            try migrateValues(path: path, name: relation.name, clearing: false)
        }
        if let next, next.type == .relation, let current = try schema.definitions(owner: owner).first(where: { $0.id == next.id }), let pair = current.relationPairID {
            object = try self.object()
            for key in Array(object.keys) {
                guard var definitions = object[key] as? [[String: Any]] else { continue }
                for index in definitions.indices where definitions[index]["type"] as? String == "relation" && definitions[index]["relationPairId"] as? String == pair && !(key == owner && (definitions[index]["name"] as? String)?.lowercased() == next.id) {
                    definitions[index]["relationHidden"] = next.relationInverseHidden
                }
                object[key] = definitions
            }
            // A same-folder inverse may share this definition. Keep the user's
            // chosen visibility and constraint while retaining all existing values.
            if var owned = object[owner] as? [[String: Any]], let index = owned.firstIndex(where: { ($0["name"] as? String)?.lowercased() == next.id }) {
                owned[index]["relationHidden"] = next.hidden
                owned[index]["relationMultiple"] = next.relationMultiple
                object[owner] = owned
            }
            try store(object)
        }
        let initialObject = try snapshot.schema.bytes.map { try JSONSerialization.jsonObject(with: $0) }
        if let initialObject, try NSDictionary(dictionary: self.object()).isEqual(initialObject) { bytes = snapshot.schema.bytes }
        var changes = readPaths.sorted().map { path in
            VaultFileChange(path: path, before: Data(snapshot.notes.first { $0.path == path }!.content.utf8), after: Data(notes.first { $0.path == path }!.content.utf8))
        }
        changes.append(VaultFileChange(path: ".zerus/properties.json", before: snapshot.schema.bytes, after: bytes))
        return NativeRelationDefinitionPlan(snapshot: snapshot, changes: changes, affectedCount: affected.count, removing: next == nil)
    }
}

extension NativePropertyDefinition {
    static func validateOwner(_ owner: String) throws {
        let segments = owner.split(separator: "/", omittingEmptySubsequences: false)
        guard owner.isEmpty || (segments.count <= 8 && !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("\\") || $0 == ".zerus" || $0 == ".trash" })) else { throw VaultFailure(message: "Choose a valid folder for this relation.") }
    }
    func validatedRelation() throws -> Self {
        guard type == .relation else { throw VaultFailure(message: "Choose a relation definition.") }
        _ = try NativePropertyDefinition(name: name, type: .text).validated()
        try Self.validateOwner(owner)
        try Self.validateOwner(relationTypeKey ?? "")
        return self
    }
}

extension VaultFiles {
    func relationDefinitionSnapshot() throws -> NativeRelationDefinitionSnapshot {
        let notes = try scan().notes
        return NativeRelationDefinitionSnapshot(schema: try schemaSnapshot(), notes: notes)
    }
    func applyRelationDefinition(_ plan: NativeRelationDefinitionPlan) throws -> VaultSnapshot {
        try applyRelationChanges(schema: plan.snapshot.schema, notes: plan.snapshot.notes, changes: plan.changes)
    }
}
