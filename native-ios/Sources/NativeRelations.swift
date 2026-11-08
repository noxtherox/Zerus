import Foundation

struct NativeRelationSnapshot: Sendable {
    let schema: NativeSchemaSnapshot
    let notes: [NoteDocument]
    let sourcePath: String
    let name: String
    var source: NoteDocument? { notes.first { $0.path == sourcePath } }
    func definition() throws -> NativePropertyDefinition {
        guard let source, !source.trashed, !source.path.hasPrefix(".zerus/"),
              let definition = try schema.effective(notePath: sourcePath).first(where: { $0.id == name.lowercased() }),
              definition.type == .relation, !definition.name.lowercased().hasPrefix("zerus-") else { throw VaultFailure(message: "This relation changed or is unavailable. Reload note information.") }
        return definition
    }
    func references() throws -> [String] {
        guard let source else { throw VaultFailure(message: "The source note is unavailable.") }
        return try Self.values(source, name: name)
    }
    func matches(_ reference: String) -> [NoteDocument] {
        guard let link = NoteReference(wikilink: "[[" + reference + "]]") else { return [] }
        if link.target.hasPrefix("zerus:") { return notes.filter { $0.stableID == String(link.target.dropFirst(6)) } }
        return notes.filter { $0.title.caseInsensitiveCompare(link.target) == .orderedSame || $0.path.caseInsensitiveCompare(link.target) == .orderedSame || ($0.path as NSString).deletingPathExtension.caseInsensitiveCompare(link.target) == .orderedSame }
    }
    func selection() throws -> (paths: Set<String>, unresolved: [String]) {
        var paths = Set<String>(), unresolved: [String] = []
        for reference in try references() {
            let found = matches(reference)
            if found.count == 1, found[0].path != sourcePath { paths.insert(found[0].path) }
            else if !unresolved.contains(reference) { unresolved.append(reference) }
        }
        return (paths, unresolved)
    }
    static func values(_ note: NoteDocument, name: String) throws -> [String] {
        guard let entry = NativeFrontmatter(note.content).entry(name) else { return [] }
        switch entry.value {
        case .text(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [value]
        case .list(let values): return values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        default: throw VaultFailure(message: "\(note.path) has a complex or duplicate \(name) value. It was left unchanged.")
        }
    }
    static func owner(_ note: NoteDocument) -> String {
        let path = note.trashed ? String(note.path.dropFirst(7)) : note.path
        return path.split(separator: "/").dropLast().prefix(8).joined(separator: "/")
    }
    static func eligible(_ note: NoteDocument, for definition: NativePropertyDefinition) -> Bool {
        guard !note.trashed, !note.path.hasPrefix(".zerus/") else { return false }
        guard let key = definition.relationTypeKey, !key.isEmpty else { return true }
        let owner = owner(note)
        return owner == key || owner.hasPrefix(key + "/")
    }
    static func stableReference(_ original: NoteDocument, notes: [NoteDocument]) throws -> (NoteDocument, String) {
        var note = original
        let id: String
        if let entry = NativeFrontmatter(note.content).entry("zerus-id") {
            guard case .text(let existing) = entry.value, existing.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else { throw VaultFailure(message: "\(note.path) has an unsupported note identifier. It was left unchanged.") }
            guard notes.filter({ $0.stableID == existing }).count == 1 else { throw VaultFailure(message: "\(note.path) shares a note identifier with another note. Resolve the duplicate before linking it.") }
            id = existing
        } else {
            id = UUID().uuidString.lowercased()
            note.content = try note.setting("zerus-id", to: id)
        }
        let label = note.title.replacingOccurrences(of: #"[\[\]\r\n]"#, with: " ", options: .regularExpression)
        return (note, "zerus:" + id + "|" + label)
    }
    func plan(selected: Set<String>, unresolved retained: Set<String>, preservingExistingMultiplicity: Bool = false) throws -> NativeRelationPlan {
        try NativeRelationPlanner(snapshot: self).plan(selected: selected, retained: retained, preservingExistingMultiplicity: preservingExistingMultiplicity)
    }
}

struct NativeRelationPlan: Sendable {
    let snapshot: NativeRelationSnapshot
    let changes: [VaultFileChange]
    var changedNotes: [String] { changes.filter { $0.path.lowercased().hasSuffix(".md") && $0.before != $0.after }.map(\.path) }
    var updatesDefinitions: Bool { changes.contains { $0.path == ".zerus/properties.json" && $0.before != $0.after } }
}

/// Builds both directions in memory first. One coordinated transaction checks
/// the schema and every affected note before any version is replaced.
private final class NativeRelationPlanner {
    let snapshot: NativeRelationSnapshot
    var notes: [String: NoteDocument]
    var schemas: [String: Any]
    var readPaths = Set<String>()
    init(snapshot: NativeRelationSnapshot) throws {
        self.snapshot = snapshot
        notes = Dictionary(uniqueKeysWithValues: snapshot.notes.map { ($0.path, $0) })
        schemas = try snapshot.schema.bytes.map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] ?? [:] } ?? [:]
    }
    func schemaData() throws -> Data { try JSONSerialization.data(withJSONObject: schemas, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) }
    func definitions(_ path: String) throws -> [NativePropertyDefinition] {
        let note = notes[path]!, owner = NativeRelationSnapshot.owner(note)
        let parts = owner.split(separator: "/")
        let owners = parts.isEmpty ? [""] : (1...parts.count).map { parts.prefix($0).joined(separator: "/") }
        for owner in owners {
            guard let raw = schemas[owner] as? [[String: Any]] else { continue }
            let names = raw.compactMap { ($0["name"] as? String)?.lowercased() }
            guard Set(names).count == names.count else { throw VaultFailure(message: "\(owner.isEmpty ? "Inbox" : owner) has duplicate property definitions. Resolve them before changing relations.") }
        }
        return try NativePropertyDefinition.effective(path: path, data: schemaData())
    }
    func replace(_ definition: NativePropertyDefinition, fields: [String: Any]) throws -> NativePropertyDefinition {
        guard var owned = schemas[definition.owner] as? [[String: Any]] else { throw VaultFailure(message: "The relation’s owner definition is unavailable.") }
        let matches = owned.indices.filter { (owned[$0]["name"] as? String)?.lowercased() == definition.id }
        guard matches.count == 1 else { throw VaultFailure(message: "This relation has duplicate definitions. Resolve them before changing its values.") }
        for (key, value) in fields { owned[matches[0]][key] = value }
        schemas[definition.owner] = owned
        return try NativePropertyDefinition.decoded(owned[matches[0]], owner: definition.owner)
    }
    func values(_ path: String, _ definition: NativePropertyDefinition) throws -> [String] {
        guard let note = notes[path] else { throw VaultFailure(message: "A related note is unavailable.") }
        readPaths.insert(path)
        return try NativeRelationSnapshot.values(note, name: definition.name)
    }
    func set(_ path: String, _ definition: NativePropertyDefinition, _ references: [String]) throws {
        guard var note = notes[path] else { throw VaultFailure(message: "A related note is unavailable.") }
        guard definition.relationMultiple || references.count <= 1 else { throw VaultFailure(message: "This inverse needs multiple-note support to retain its existing links.") }
        readPaths.insert(path)
        let value: NativePropertyValue? = references.isEmpty ? nil : definition.relationMultiple ? .list(references) : .text(references[0])
        note.content = try NativeFrontmatter(note.content).setting(definition.name, value: value)
        notes[path] = note
    }
    func stableReference(_ path: String) throws -> String {
        guard let note = notes[path] else { throw VaultFailure(message: "A related note is unavailable.") }
        let (updated, reference) = try NativeRelationSnapshot.stableReference(note, notes: Array(notes.values))
        notes[path] = updated
        readPaths.insert(path)
        return reference
    }
    func referencesSource(_ reference: String) throws -> Bool {
        let matches = snapshot.matches(reference)
        guard matches.contains(where: { $0.path == snapshot.sourcePath }) else { return false }
        guard matches.count == 1 else { throw VaultFailure(message: "A legacy inverse link has an ambiguous title. Resolve it to a stable note link before changing this relation.") }
        return true
    }
    func reverse(_ target: String, source: NativePropertyDefinition, create: Bool) throws -> NativePropertyDefinition? {
        readPaths.insert(target)
        let definitions = try definitions(target), pair = source.relationPairID!
        let paired = definitions.filter { $0.type == .relation && $0.relationPairID == pair }
        guard paired.count <= 1 else { throw VaultFailure(message: "\(target) has more than one inverse for this relation. No files were changed.") }
        if let first = paired.first { return first }
        var legacy: [NativePropertyDefinition] = []
        for definition in definitions where definition.type == .relation && definition.relationPairID == nil {
            guard let references = try? values(target, definition) else { continue }
            if try references.contains(where: referencesSource) { legacy.append(definition) }
        }
        guard legacy.count <= 1 else { throw VaultFailure(message: "\(target) has several unpaired inverse fields. Resolve the intended pair before changing this relation.") }
        if let definition = legacy.first {
            return try replace(definition, fields: ["relationPairId": pair, "relationHidden": source.relationInverseHidden])
        }
        guard create else { return nil }
        let sourceKey = NativeRelationSnapshot.owner(snapshot.source!)
        var candidates: [NativePropertyDefinition] = []
        for definition in definitions where definition.type == .relation && (definition.relationPairID == nil || definition.relationPairID == pair) {
            let key = definition.relationTypeKey ?? ""
            guard key.isEmpty || sourceKey == key || sourceKey.hasPrefix(key + "/"),
                  let existing = try? values(target, definition), definition.relationMultiple || existing.isEmpty else { continue }
            candidates.append(definition)
        }
        if let candidate = candidates.enumerated().sorted(by: {
            let left = $0.element.relationTypeKey?.count ?? 0, right = $1.element.relationTypeKey?.count ?? 0
            return left == right ? $0.offset < $1.offset : left > right
        }).first?.element {
            return try replace(candidate, fields: ["relationPairId": pair, "relationHidden": source.relationInverseHidden])
        }
        let occupied = Set(definitions.map(\.id) + NativeFrontmatter(notes[target]!.content).entries.map(\.id))
        var base = sourceKey.split(separator: "/").last.map(String.init) ?? "Related notes"
        base = base.replacingOccurrences(of: #"[^A-Za-z0-9_ .-]"#, with: "", options: .regularExpression).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        if base.isEmpty { base = "Related notes" }; base = String(base.prefix(60))
        var name = base, suffix = 2
        while occupied.contains(name.lowercased()) { let ending = " \(suffix)"; name = String(base.prefix(60 - ending.count)) + ending; suffix += 1 }
        let owner = NativeRelationSnapshot.owner(notes[target]!)
        if let existing = schemas[owner], !(existing is [[String: Any]]) { throw VaultFailure(message: "The related folder’s definitions use an unsupported format.") }
        var raw: [String: Any] = ["name": name, "type": "relation", "relationMultiple": true, "relationPairId": pair, "relationHidden": source.relationInverseHidden]
        if !sourceKey.isEmpty { raw["relationTypeKey"] = sourceKey }
        var owned = schemas[owner] as? [[String: Any]] ?? []; owned.append(raw); schemas[owner] = owned
        return try NativePropertyDefinition.decoded(raw, owner: owner)
    }
    func plan(selected: Set<String>, retained: Set<String>, preservingExistingMultiplicity: Bool) throws -> NativeRelationPlan {
        var definition = try snapshot.definition()
        let initial = try snapshot.selection(), oldReferences = try snapshot.references()
        if selected.isEmpty && retained.isEmpty && oldReferences.isEmpty { return NativeRelationPlan(snapshot: snapshot, changes: []) }
        guard retained.isSubset(of: Set(initial.unresolved)) else { throw VaultFailure(message: "An unresolved relation changed. Reload it before saving.") }
        for path in selected {
            guard let target = notes[path], path != snapshot.sourcePath,
                  initial.paths.contains(path) || NativeRelationSnapshot.eligible(target, for: definition) else { throw VaultFailure(message: "Choose a note from this relation’s folder.") }
        }
        let preservesSelection = preservingExistingMultiplicity && selected == initial.paths && retained == Set(initial.unresolved)
        guard definition.relationMultiple || selected.count + retained.count <= 1 || preservesSelection else { throw VaultFailure(message: "This relation allows one note. Remove the other selections before saving.") }
        definition = try replace(definition, fields: ["relationPairId": definition.relationPairID ?? UUID().uuidString.lowercased()])
        let sourceReference = try stableReference(snapshot.sourcePath)
        var before = Set<String>(), ordered: [String] = []
        for reference in oldReferences {
            let found = snapshot.matches(reference)
            if !retained.contains(reference) { before.formUnion(found.map(\.path)) }
            if found.count == 1, selected.contains(found[0].path), !ordered.contains(found[0].path) { ordered.append(found[0].path) }
        }
        ordered += selected.subtracting(ordered).sorted { (notes[$0]!.title, $0) < (notes[$1]!.title, $1) }
        var after = try ordered.map(stableReference)
        after += initial.unresolved.filter { retained.contains($0) }
        for path in before.subtracting(selected).sorted() where path != snapshot.sourcePath {
            guard var inverse = try reverse(path, source: definition, create: false) else { continue }
            let remaining = try values(path, inverse).filter { try !referencesSource($0) }
            if remaining.count > 1 && !inverse.relationMultiple { inverse = try replace(inverse, fields: ["relationMultiple": true]) }
            try set(path, inverse, remaining)
        }
        for path in ordered {
            guard var inverse = try reverse(path, source: definition, create: true) else { continue }
            let existing = try values(path, inverse)
            var references: [String] = [], included = false
            for reference in existing {
                if try referencesSource(reference) { if !included { references.append(sourceReference); included = true } }
                else { references.append(reference) }
            }
            if !included { references.append(sourceReference) }
            if references.count > 1 && !inverse.relationMultiple { inverse = try replace(inverse, fields: ["relationMultiple": true]) }
            try set(path, inverse, references)
        }
        // A shared inverse may have promoted a same-folder single relation.
        if let current = try definitions(snapshot.sourcePath).first(where: { $0.id == definition.id }) { definition = current }
        if preservesSelection && after.count > 1 { definition.relationMultiple = true }
        try set(snapshot.sourcePath, definition, after)
        let schema = try schemaData()
        let originalSchema = try snapshot.schema.bytes.map { try JSONSerialization.jsonObject(with: $0) }
        let unchangedSchema = originalSchema.map { NSDictionary(dictionary: schemas).isEqual($0) } ?? schemas.isEmpty
        let schemaAfter = unchangedSchema ? snapshot.schema.bytes : schema
        var changes = readPaths.sorted().map { path in VaultFileChange(path: path, before: Data(snapshot.notes.first { $0.path == path }!.content.utf8), after: Data(notes[path]!.content.utf8)) }
        changes.append(VaultFileChange(path: ".zerus/properties.json", before: snapshot.schema.bytes, after: schemaAfter))
        return NativeRelationPlan(snapshot: snapshot, changes: changes)
    }
}

extension VaultFiles {
    func relationSnapshot(notePath: String, name: String) throws -> NativeRelationSnapshot {
        let notes = try scan().notes, schema = try schemaSnapshot()
        let snapshot = NativeRelationSnapshot(schema: schema, notes: notes, sourcePath: notePath, name: name)
        _ = try snapshot.definition(); _ = try snapshot.references()
        return snapshot
    }
    func applyRelation(_ plan: NativeRelationPlan) throws -> VaultSnapshot {
        try applyRelationChanges(schema: plan.snapshot.schema, notes: plan.snapshot.notes, changes: plan.changes)
    }
    func applyRelationChanges(schema: NativeSchemaSnapshot, notes: [NoteDocument], changes: [VaultFileChange], reading: [URL] = [], validate: @escaping @Sendable () throws -> Void = {}) throws -> VaultSnapshot {
        guard schema.root == root else { throw VaultFailure(message: "The vault changed. Reload this relation.") }
        let current = try scan()
        struct Identity: Hashable { let path: String; let title: String; let stableID: String? }
        let before = Set(notes.map { Identity(path: $0.path, title: $0.title, stableID: $0.stableID) })
        let now = Set(current.notes.map { Identity(path: $0.path, title: $0.title, stableID: $0.stableID) })
        guard before == now else { throw VaultFailure(message: "Notes were added, moved or renamed while this relation was being reviewed. Reload it to use the latest targets.") }
        try applyTransaction(changes, reading: reading, validate: validate)
        return try scan()
    }
}
