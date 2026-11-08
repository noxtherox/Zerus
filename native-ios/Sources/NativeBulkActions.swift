import Foundation

enum NativeBulkOperation: String, Codable, CaseIterable, Identifiable, Sendable {
    case set = "Set", clear = "Clear", add = "Add", remove = "Remove"
    var id: String { rawValue }
}
struct NativeBulkPropertyChange: Identifiable, Sendable {
    var name: String
    var operation: NativeBulkOperation = .set
    var value: NativePropertyValue?
    var id: String { name.lowercased() }
}
struct NativeBulkMutation: Sendable {
    var pinned: Bool?
    var archived: Bool?
    var properties: [NativeBulkPropertyChange] = []
    var label: String { pinned.map { $0 ? "Pin notes" : "Unpin notes" } ?? archived.map { $0 ? "Archive notes" : "Unarchive notes" } ?? "Update properties" }
}
struct NativeBulkField: Codable, Sendable {
    let name: String
    let before: NativePropertyValue?
    let after: NativePropertyValue?
    let operation: NativeBulkOperation
    let delta: [String]
    let relation: Bool
    var applied = true
}
struct NativeBulkEntry: Codable, Identifiable, Sendable {
    let stableID: String
    let title: String
    var fields: [NativeBulkField]
    var id: String { stableID }
}
struct NativeBulkRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let label: String
    var entries: [NativeBulkEntry]
    var appliedCount: Int { entries.flatMap(\.fields).filter(\.applied).count }
    var fieldCount: Int { entries.flatMap(\.fields).count }
    var status: String { appliedCount == 0 ? "Undone" : appliedCount == fieldCount ? "Applied" : "Partially undone" }
}
struct NativeBulkIssue: Identifiable, Sendable {
    let path: String
    let reason: String
    var id: String { path + reason }
}
struct NativeBulkSnapshot: Sendable {
    let source: NativeRelationDefinitionSnapshot
    let historyBytes: Data?
    let records: [NativeBulkRecord]
    func plan(selected: [NoteDocument], mutation: NativeBulkMutation) throws -> NativeBulkPlan { try NativeBulkPlanner(self).apply(selected, mutation: mutation) }
    func transition(_ id: UUID, undo: Bool) throws -> NativeBulkPlan { try NativeBulkPlanner(self).transition(id, undo: undo) }
    func commonProperties(_ selected: [NoteDocument]) throws -> [NativePropertyDefinition] {
        let resolved = selected.compactMap { selection -> NoteDocument? in
            let found = source.notes.filter { selection.stableID == nil ? $0.path == selection.path : $0.stableID == selection.stableID }
            return found.count == 1 && !found[0].trashed ? found[0] : nil
        }
        guard resolved.count == selected.count, let first = resolved.first else { return [] }
        let selected = resolved
        return try source.schema.checkedEffective(notePath: first.path).filter { candidate in
            guard !candidate.hidden, candidate.type != .unsupported, !candidate.name.lowercased().hasPrefix("zerus-") else { return false }
            return try selected.dropFirst().allSatisfy { note in
                guard let other = try source.schema.checkedEffective(notePath: note.path).first(where: { $0.id == candidate.id }) else { return false }
                return !other.hidden && other.type == candidate.type && other.multiple == candidate.multiple && other.relationMultiple == candidate.relationMultiple && other.relationTypeKey == candidate.relationTypeKey
            }
        }.map { candidate in
            var result = candidate
            if result.type == .list {
                result.options = try candidate.options.filter { option in try selected.allSatisfy { note in
                    try source.schema.checkedEffective(notePath: note.path).first { $0.id == candidate.id }?.options.contains { $0.caseInsensitiveCompare(option) == .orderedSame } == true
                } }
            }
            return result
        }
    }
}
struct NativeBulkPlan: Identifiable, Sendable {
    let id = UUID()
    let snapshot: NativeBulkSnapshot
    let label: String
    let changes: [VaultFileChange]
    let issues: [NativeBulkIssue]
    let changedFields: [String: [String]]
    var hasChanges: Bool { changes.contains { $0.before != $0.after } }
    var changedNotes: [String] { changes.filter { $0.path.lowercased().hasSuffix(".md") && $0.before != $0.after }.map(\.path) }
}

enum NativeBulkHistory {
    static let path = ".zerus/native-bulk-history.json"
    static func read(_ data: Data?) throws -> [NativeBulkRecord] {
        guard let data else { return [] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], NativeHistory.integer(object["version"]) == 1,
              let records = object["records"] as? [[String: Any]] else { throw VaultFailure(message: "Bulk action history uses an unsupported format. Its file and your notes were left unchanged.") }
        let decoded = try JSONDecoder().decode([NativeBulkRecord].self, from: JSONSerialization.data(withJSONObject: records))
        guard Set(decoded.map(\.id)).count == decoded.count else { throw VaultFailure(message: "Bulk action history contains duplicate actions and is preserved without changes.") }
        for record in decoded {
            guard record.date.timeIntervalSince1970.isFinite, !record.entries.isEmpty, Set(record.entries.map(\.stableID)).count == record.entries.count else { throw VaultFailure(message: "A bulk action has unsupported note records and was preserved.") }
            for entry in record.entries {
                guard entry.stableID.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil, !entry.fields.isEmpty, Set(entry.fields.map { $0.name.lowercased() }).count == entry.fields.count,
                      entry.fields.allSatisfy({ field in field.name.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_ .-]{0,59}$"#, options: .regularExpression) != nil && (!field.name.lowercased().hasPrefix("zerus-") || ["zerus-pinned", "zerus-archived"].contains(field.name) && !field.relation && field.operation == .set && field.delta.isEmpty) }) else { throw VaultFailure(message: "A bulk action contains unsupported fields and was preserved without applying it.") }
            }
        }
        return decoded
    }
    static func encode(_ records: [NativeBulkRecord], original: Data?) throws -> Data {
        var object = try original.map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] ?? [:] } ?? [:]
        // Preserve unmodified records verbatim, including future optional fields.
        let oldRaw = object["records"] as? [[String: Any]] ?? []
        let old = try read(original)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let next = try records.map { record -> [String: Any] in
            if let index = old.firstIndex(where: { $0.id == record.id }), try encoder.encode(old[index]) == encoder.encode(record), index < oldRaw.count { return oldRaw[index] }
            var raw = old.firstIndex(where: { $0.id == record.id }).flatMap { $0 < oldRaw.count ? oldRaw[$0] : nil } ?? [:]
            let updated = try JSONSerialization.jsonObject(with: encoder.encode(record)) as! [String: Any]
            raw.merge(updated) { _, value in value }; return raw
        }
        object["version"] = 1; object["records"] = next
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

private final class NativeBulkPlanner {
    let snapshot: NativeBulkSnapshot
    var notes: [NoteDocument]
    var schemaBytes: Data?
    var reads = Set<String>()
    var issues: [NativeBulkIssue] = []
    var changedFields: [String: [String]] = [:]
    var schema: NativeSchemaSnapshot { .init(root: snapshot.source.schema.root, bytes: schemaBytes) }
    init(_ snapshot: NativeBulkSnapshot) { self.snapshot = snapshot; notes = snapshot.source.notes; schemaBytes = snapshot.source.schema.bytes }
    func note(_ selected: NoteDocument) throws -> NoteDocument {
        let found = notes.filter { selected.stableID == nil ? $0.path == selected.path : $0.stableID == selected.stableID }
        guard found.count == 1, let note = found.first, !note.trashed, !note.unfiledSavedLink, (!note.path.hasPrefix(".zerus/") || note.fileHub != nil) else { throw VaultFailure(message: "This note is missing, ambiguous, deleted or managed by a collection.") }
        return note
    }
    func set(_ path: String, name: String, value: NativePropertyValue?, relation: Bool, restoringUnresolved: Bool = false) throws {
        let index = notes.firstIndex { $0.path == path }!
        reads.insert(path)
        if relation {
            let current = NativeRelationSnapshot(schema: schema, notes: notes, sourcePath: path, name: name)
            var paths = Set<String>(), unresolved = Set<String>()
            let oldReferences = try current.references()
            for reference in value?.selections ?? [] {
                let matches = current.matches(reference)
                if matches.count == 1, !matches[0].trashed, matches[0].path != path { paths.insert(matches[0].path) }
                else if restoringUnresolved || oldReferences.contains(reference) { unresolved.insert(reference) }
                else { throw VaultFailure(message: "A requested relation target is missing or ambiguous.") }
            }
            let retained = unresolved.intersection(Set(try current.selection().unresolved))
            let plan = try current.plan(selected: paths, unresolved: retained)
            for change in plan.changes {
                if change.path == ".zerus/properties.json" { schemaBytes = change.after }
                else if let i = notes.firstIndex(where: { $0.path == change.path }), let data = change.after {
                    reads.insert(change.path); notes[i].content = String(decoding: data, as: UTF8.self)
                }
            }
            // Receipt restoration can bring back a dangling reference that the
            // ordinary picker cannot create. It never creates a missing note
            // or invents an inverse for an unresolved target.
            let extra = (value?.selections ?? []).filter { unresolved.contains($0) && !retained.contains($0) }
            if !extra.isEmpty {
                let definition = try schema.checkedEffective(notePath: path).first { $0.id == name.lowercased() }!
                let references = try NativeRelationSnapshot.values(notes[index], name: name) + extra
                guard definition.relationMultiple || references.count <= 1 else { throw VaultFailure(message: "This relation now allows only one note; its previous references were not restored.") }
                notes[index].content = try NativeFrontmatter(notes[index].content).setting(name, value: definition.relationMultiple ? .list(references) : .text(references[0]))
            }
        } else { notes[index].content = try NativeFrontmatter(notes[index].content).setting(name, value: value) }
    }
    func value(_ note: NoteDocument, name: String) throws -> NativePropertyValue? {
        guard let entry = NativeFrontmatter(note.content).entry(name) else { return nil }
        guard let value = entry.value else { throw VaultFailure(message: "\(name) has a complex or duplicate value and was left unchanged.") }; return value
    }
    func key(_ reference: String, relation: Bool) -> String {
        if relation, let first = notes.first {
            let matches = NativeRelationSnapshot(schema: schema, notes: notes, sourcePath: first.path, name: "").matches(reference)
            if matches.count == 1 { return matches[0].stableID.map { "id:" + $0 } ?? "path:" + matches[0].path }
        }
        return reference.lowercased()
    }
    func equivalent(_ a: NativePropertyValue?, _ b: NativePropertyValue?, relation: Bool) -> Bool {
        guard relation else { return a == b }
        return Set((a?.selections ?? []).map { key($0, relation: true) }) == Set((b?.selections ?? []).map { key($0, relation: true) })
    }
    func canonical(_ value: NativePropertyValue?, source: String) throws -> NativePropertyValue? {
        guard let value else { return nil }
        let resolver = NativeRelationSnapshot(schema: schema, notes: notes, sourcePath: source, name: "")
        let references = try value.selections.map { reference -> String in
            let found = resolver.matches(reference)
            guard found.count == 1, let target = found.first else { return reference }
            let (identified, stable) = try NativeRelationSnapshot.stableReference(target, notes: notes)
            if identified.content != target.content { notes[notes.firstIndex { $0.path == target.path }!] = identified; reads.insert(target.path) }
            return stable
        }
        if case .list = value { return .list(references) }
        return .text(references.first ?? "")
    }
    func updated(_ before: NativePropertyValue?, change: NativeBulkPropertyChange, relation: Bool) throws -> (NativePropertyValue?, [String]) {
        switch change.operation {
        case .clear: return (nil, [])
        case .set: return (change.value, [])
        case .add, .remove:
            let existing = before?.selections ?? [], wanted = change.value?.selections ?? []
            let existingKeys = Set(existing.map { key($0, relation: relation) }), wantedKeys = Set(wanted.map { key($0, relation: relation) })
            var addedKeys = existingKeys
            let delta = change.operation == .add ? wanted.filter { addedKeys.insert(key($0, relation: relation)).inserted } : existing.filter { wantedKeys.contains(key($0, relation: relation)) }
            return (.list(change.operation == .add ? existing + delta : existing.filter { !wantedKeys.contains(key($0, relation: relation)) }), delta)
        }
    }
    func validate(_ change: NativeBulkPropertyChange, definition: NativePropertyDefinition) throws {
        guard !definition.hidden && definition.type != .unsupported else { throw VaultFailure(message: "This property is hidden or unsupported.") }
        guard change.operation != .add && change.operation != .remove || (definition.type == .list && definition.multiple || definition.type == .relation && definition.relationMultiple) else { throw VaultFailure(message: "Add and Remove require a multiple-value list or relation.") }
        guard change.operation != .clear else { return }
        guard let value = change.value else { throw VaultFailure(message: "Choose a value for \(change.name).") }
        try definition.validateValue(value)
    }

    func apply(_ selected: [NoteDocument], mutation: NativeBulkMutation) throws -> NativeBulkPlan {
        guard !selected.isEmpty, Set(selected.map(\.path)).count == selected.count, selected.allSatisfy({ $0.workspaceID == nil || $0.workspaceID == snapshot.source.schema.workspaceID }) else { throw VaultFailure(message: "Select distinct notes first.") }
        guard Set(mutation.properties.map(\.id)).count == mutation.properties.count else { throw VaultFailure(message: "A property can appear only once in a bulk change.") }
        var entries: [NativeBulkEntry] = []
        for selected in selected {
            let oldNotes = notes, oldBytes = schemaBytes, oldReads = reads
            do {
                let original = try note(selected)
                var fields: [NativeBulkField] = []
                for (name, enabled) in [("zerus-pinned", mutation.pinned), ("zerus-archived", mutation.archived)] {
                    guard let enabled else { continue }
                    let before = try value(original, name: name)
                    guard before == nil || before == .checkbox(true) || before == .checkbox(false) || before == .text("true") || before == .text("false") else { throw VaultFailure(message: "This note has an unsupported organization flag.") }
                    if (original.property(name) == "true") != enabled { fields.append(.init(name: name, before: before, after: .checkbox(enabled), operation: .set, delta: [], relation: false)) }
                }
                for change in mutation.properties {
                    guard !change.name.lowercased().hasPrefix("zerus-"), let definition = try schema.checkedEffective(notePath: original.path).first(where: { $0.id == change.id }) else { throw VaultFailure(message: "\(change.name) is not defined for this note.") }
                    try validate(change, definition: definition)
                    let before = try value(original, name: definition.name), relation = definition.type == .relation
                    let (after, delta) = try updated(before, change: change, relation: relation)
                    if !equivalent(before, after, relation: relation) { fields.append(.init(name: definition.name, before: before, after: after, operation: change.operation, delta: delta, relation: relation)) }
                }
                guard !fields.isEmpty else { issues.append(.init(path: original.path, reason: "Already has the requested values.")); continue }
                let (identified, _) = try NativeRelationSnapshot.stableReference(original, notes: notes)
                notes[notes.firstIndex { $0.path == original.path }!] = identified
                for field in fields { try set(original.path, name: field.name, value: field.after, relation: field.relation) }
                // Record the actual canonical values emitted by reciprocal linking.
                let saved = notes.first { $0.path == original.path }!
                fields = try fields.map { field in
                    let before = field.relation ? try canonical(field.before, source: original.path) : field.before
                    let delta = field.relation ? try canonical(.list(field.delta), source: original.path)?.selections ?? [] : field.delta
                    return .init(name: field.name, before: before, after: try value(saved, name: field.name), operation: field.operation, delta: delta, relation: field.relation)
                }
                entries.append(.init(stableID: saved.stableID!, title: original.title, fields: fields))
                changedFields[original.path] = fields.map { Self.display($0.name) }
            } catch { notes = oldNotes; schemaBytes = oldBytes; reads = oldReads; issues.append(.init(path: selected.path, reason: error.localizedDescription)) }
        }
        var records = snapshot.records
        if !entries.isEmpty { records.insert(.init(id: UUID(), date: Date(), label: mutation.label, entries: entries), at: 0) }
        return try finish(label: mutation.label, records: records)
    }
    func transition(_ id: UUID, undo: Bool) throws -> NativeBulkPlan {
        var records = snapshot.records
        guard let recordIndex = records.firstIndex(where: { $0.id == id }) else { throw VaultFailure(message: "This action is no longer in history.") }
        for entryIndex in records[recordIndex].entries.indices {
            let entry = records[recordIndex].entries[entryIndex]
            for fieldIndex in entry.fields.indices {
                let field = entry.fields[fieldIndex]
                guard field.applied == undo else { continue }
                let oldNotes = notes, oldBytes = schemaBytes, oldReads = reads
                do {
                    let matches = notes.filter { $0.stableID == entry.stableID }
                    guard matches.count == 1, let note = matches.first, !note.trashed, !note.unfiledSavedLink, (!note.path.hasPrefix(".zerus/") || note.fileHub != nil) else { throw VaultFailure(message: "The note is missing, deleted or has an ambiguous identity.") }
                    let current = try value(note, name: field.name)
                    var target = undo ? field.before : field.after
                    if (field.operation == .add || field.operation == .remove) && !field.delta.isEmpty {
                        switch current { case nil, .text, .list: break; default: throw VaultFailure(message: "This list changed to an unsupported value and was not overwritten.") }
                        let shouldAdd = (field.operation == .add) != undo
                        let currentValues = current?.selections ?? [], keys = Set(field.delta.map { key($0, relation: field.relation) })
                        let values = shouldAdd ? currentValues + field.delta.filter { value in !currentValues.contains { key($0, relation: field.relation) == key(value, relation: field.relation) } } : currentValues.filter { !keys.contains(key($0, relation: field.relation)) }
                        target = values.isEmpty && target == nil ? nil : .list(values)
                    } else {
                        let expected = undo ? field.after : field.before
                        guard equivalent(current, expected, relation: field.relation) || equivalent(current, target, relation: field.relation) else { throw VaultFailure(message: "\(Self.display(field.name)) changed later and was not overwritten.") }
                    }
                    if !field.name.hasPrefix("zerus-") {
                        guard let definition = try schema.checkedEffective(notePath: note.path).first(where: { $0.id == field.name.lowercased() }), (definition.type == .relation) == field.relation else { throw VaultFailure(message: "The property definition changed. Review it before undoing this action.") }
                        try validate(.init(name: field.name, operation: target == nil ? .clear : .set, value: target), definition: definition)
                    }
                    if equivalent(current, target, relation: field.relation) { reads.insert(note.path) }
                    else { try set(note.path, name: field.name, value: target, relation: field.relation, restoringUnresolved: true) }
                    records[recordIndex].entries[entryIndex].fields[fieldIndex].applied = !undo
                    changedFields[note.path, default: []].append(Self.display(field.name))
                } catch { notes = oldNotes; schemaBytes = oldBytes; reads = oldReads; issues.append(.init(path: entry.title, reason: error.localizedDescription)) }
            }
        }
        return try finish(label: (undo ? "Undo “" : "Redo “") + records[recordIndex].label + "”", records: records)
    }
    func finish(label: String, records: [NativeBulkRecord]) throws -> NativeBulkPlan {
        var changes = reads.sorted().map { path in VaultFileChange(path: path, before: snapshot.source.notes.first { $0.path == path }.map { Data($0.content.utf8) }, after: notes.first { $0.path == path }.map { Data($0.content.utf8) }) }
        changes.append(.init(path: ".zerus/properties.json", before: snapshot.source.schema.bytes, after: schemaBytes))
        let cutoff = Date().addingTimeInterval(-90 * 86400), retained = Array(records.filter { $0.date >= cutoff }.prefix(10))
        if !changedFields.isEmpty { changes.append(.init(path: NativeBulkHistory.path, before: snapshot.historyBytes, after: try NativeBulkHistory.encode(retained, original: snapshot.historyBytes))) }
        var seen = Set<String>()
        return .init(snapshot: snapshot, label: label, changes: changes, issues: issues.filter { seen.insert($0.id).inserted }, changedFields: changedFields)
    }
    static func display(_ name: String) -> String { name == "zerus-pinned" ? "Pinned" : name == "zerus-archived" ? "Archived" : name }
}

extension VaultFiles {
    func bulkSnapshot() throws -> NativeBulkSnapshot {
        let source = try relationDefinitionSnapshot(), location = try url(for: NativeBulkHistory.path)
        let bytes = FileManager.default.fileExists(atPath: location.path) ? try read(NativeBulkHistory.path) : nil
        return .init(source: source, historyBytes: bytes, records: try NativeBulkHistory.read(bytes))
    }
    func applyBulk(_ plan: NativeBulkPlan) throws -> VaultSnapshot {
        try applyRelationChanges(schema: plan.snapshot.source.schema, notes: plan.snapshot.source.notes, changes: plan.changes)
    }
}
