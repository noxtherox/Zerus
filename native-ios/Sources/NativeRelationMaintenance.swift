import Foundation

struct NativeRelationRepairIssue: Identifiable, Sendable {
    let path: String
    let name: String
    let reason: String
    var id: String { path + "\n" + name }
}

struct NativeRelationMaintenancePlan: Identifiable, Sendable {
    let id = UUID()
    let snapshot: NativeRelationDefinitionSnapshot
    let changes: [VaultFileChange]
    let sourcePath: String?
    let destination: String?
    let summaries: [String]
    let issues: [NativeRelationRepairIssue]
    var resourceBindings: [NativeMoveResourceBinding] = []
    var changedNotes: [String] { changes.filter { $0.path.lowercased().hasSuffix(".md") && $0.before != $0.after }.map(\.path) }
    var hasChanges: Bool { changes.contains { $0.before != $0.after } }
}

extension NativeSchemaSnapshot {
    func checkedEffective(notePath: String) throws -> [NativePropertyDefinition] {
        let logical = notePath.hasPrefix(".trash/") ? String(notePath.dropFirst(7)) : notePath
        let parts = logical.split(separator: "/").dropLast().prefix(8)
        let owners = parts.isEmpty ? [""] : (1...parts.count).map { parts.prefix($0).joined(separator: "/") }
        for owner in owners {
            let values = try definitions(owner: owner)
            guard Set(values.map(\.id)).count == values.count else { throw VaultFailure(message: "\(owner.isEmpty ? "Inbox" : owner) has duplicate definitions. Resolve them before changing relations.") }
        }
        return try effective(notePath: notePath)
    }
}

/// Uses the same reciprocal planner for moves and reviewed legacy repairs.
/// Intermediate schemas and values never escape this in-memory workspace.
private final class NativeRelationMaintenance {
    let snapshot: NativeRelationDefinitionSnapshot
    var notes: [NoteDocument]
    var bytes: Data?
    var reads = Set<String>()
    var summaries: [String] = []
    init(_ snapshot: NativeRelationDefinitionSnapshot) { self.snapshot = snapshot; notes = snapshot.notes; bytes = snapshot.schema.bytes }
    var schema: NativeSchemaSnapshot { NativeSchemaSnapshot(root: snapshot.schema.root, bytes: bytes) }
    func object() throws -> [String: Any] {
        guard let bytes else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "The property definitions are not a JSON object.") }
        return object
    }
    func store(_ object: [String: Any]) throws { bytes = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) }
    func raw(_ definition: NativePropertyDefinition) throws -> [String: Any] {
        guard let owned = try object()[definition.owner] as? [[String: Any]] else { throw VaultFailure(message: "This relation’s folder definition is unavailable.") }
        let matches = owned.filter { ($0["name"] as? String)?.lowercased() == definition.id }
        guard matches.count == 1 else { throw VaultFailure(message: "This relation has duplicate definitions. Reload folder properties.") }
        return matches[0]
    }
    func add(_ raw: [String: Any], owner: String) throws {
        try NativePropertyDefinition.validateOwner(owner)
        var object = try object()
        if let existing = object[owner], !(existing is [[String: Any]]) { throw VaultFailure(message: "\(owner) has unsupported folder definitions.") }
        var owned = object[owner] as? [[String: Any]] ?? []
        owned.append(raw); object[owner] = owned; try store(object)
    }
    func consume(_ plan: NativeRelationPlan) {
        for change in plan.changes {
            if change.path == ".zerus/properties.json" { bytes = change.after }
            else if let index = notes.firstIndex(where: { $0.path == change.path }), let data = change.after {
                reads.insert(change.path); notes[index].content = String(decoding: data, as: UTF8.self)
            }
        }
    }
    func reconcile(_ path: String, name: String, clearing: Bool = false) throws {
        let value = NativeRelationSnapshot(schema: schema, notes: notes, sourcePath: path, name: name)
        let selected = try value.selection()
        consume(try value.plan(selected: clearing ? [] : selected.paths, unresolved: clearing ? [] : Set(selected.unresolved), preservingExistingMultiplicity: !clearing))
    }
    func finish(source: String? = nil, destination: String? = nil, issues: [NativeRelationRepairIssue] = []) throws -> NativeRelationMaintenancePlan {
        if let original = try snapshot.schema.bytes.map({ try JSONSerialization.jsonObject(with: $0) }), try NSDictionary(dictionary: object()).isEqual(original) { bytes = snapshot.schema.bytes }
        if snapshot.schema.bytes == nil, try object().isEmpty { bytes = nil }
        var changes = reads.filter { $0 != destination }.sorted().map { path in
            VaultFileChange(path: path, before: snapshot.notes.first { $0.path == path }.map { Data($0.content.utf8) }, after: notes.first { $0.path == path }.map { Data($0.content.utf8) })
        }
        if let destination, let note = notes.first(where: { $0.path == destination }) {
            changes.insert(VaultFileChange(path: destination, before: source == destination ? snapshot.notes.first { $0.path == source }.map { Data($0.content.utf8) } : nil, after: Data(note.content.utf8)), at: 0)
        }
        changes.append(VaultFileChange(path: ".zerus/properties.json", before: snapshot.schema.bytes, after: bytes))
        if bytes != snapshot.schema.bytes && summaries.isEmpty { summaries.append("Folder definitions are updated to keep both directions synchronized.") }
        return NativeRelationMaintenancePlan(snapshot: snapshot, changes: changes, sourcePath: source, destination: destination, summaries: summaries, issues: issues)
    }
    func move(source: String, destination: String, renaming: Bool = false) throws -> NativeRelationMaintenancePlan {
        guard (source != destination || renaming), let original = notes.first(where: { $0.path == source }), !original.trashed, (!source.hasPrefix(".zerus/") || source.hasPrefix(".zerus/links/") || source.hasPrefix(".zerus/files/")), (!destination.hasPrefix(".zerus/") || renaming && source == destination), !destination.hasPrefix(".trash/"), destination.lowercased().hasSuffix(".md") else { throw VaultFailure(message: "Choose a regular note and another folder.") }
        guard !notes.contains(where: { $0.path != source && $0.path.caseInsensitiveCompare(destination) == .orderedSame }) else { throw VaultFailure(message: "A note already exists at the destination.") }
        if renaming, source == destination, source.hasPrefix(".zerus/") { return try finish(source: source, destination: destination) }
        let destinationOwner = (destination as NSString).deletingLastPathComponent
        try NativePropertyDefinition.validateOwner(destinationOwner)
        let sourceOwner = NativeRelationSnapshot.owner(original)
        let managed = source.hasPrefix(".zerus/")
        var incomingFields: [(String, String)] = []
        // Upgrade incoming legacy path/title references before changing the path.
        for note in notes where !note.trashed && !note.path.hasPrefix(".zerus/") && note.path != source {
            guard let definitions = try? schema.checkedEffective(notePath: note.path) else { continue }
            for definition in definitions where definition.type == .relation {
                guard let references = try? NativeRelationSnapshot.values(note, name: definition.name) else { continue }
                let resolver = NativeRelationSnapshot(schema: schema, notes: notes, sourcePath: note.path, name: definition.name)
                var incoming = false, referencesAfter: [String] = []
                for reference in references {
                    let matches = resolver.matches(reference)
                    if matches.contains(where: { $0.path == source }) {
                        guard matches.count == 1 else { throw VaultFailure(message: "\(note.path) has an ambiguous incoming relation to this note. Resolve its target before moving.") }
                        incoming = true
                        let index = notes.firstIndex { $0.path == source }!
                        let (updated, stable) = try NativeRelationSnapshot.stableReference(notes[index], notes: notes)
                        notes[index] = updated; reads.insert(source); referencesAfter.append(stable)
                    } else { referencesAfter.append(reference) }
                }
                if incoming {
                    let index = notes.firstIndex { $0.path == note.path }!
                    let entry = NativeFrontmatter(notes[index].content).entry(definition.name)
                    let value: NativePropertyValue = { if case .list = entry?.value { return .list(referencesAfter) }; return referencesAfter.count > 1 ? .list(referencesAfter) : .text(referencesAfter[0]) }()
                    notes[index].content = try NativeFrontmatter(notes[index].content).setting(definition.name, value: value)
                    reads.insert(note.path); incomingFields.append((note.path, definition.name))
                }
            }
        }
        var definitions = managed ? [] : try schema.checkedEffective(notePath: source)
        for definition in definitions where definition.type == .relation && NativeFrontmatter(notes.first { $0.path == source }!.content).entry(definition.name) != nil {
            try reconcile(source, name: definition.name)
        }
        definitions = managed ? [] : try schema.checkedEffective(notePath: source)
        let destinationDefinitions = try schema.checkedEffective(notePath: destination)
        var restores: [(String, NativePropertyValue?)] = []
        for definition in definitions where definition.type == .relation {
            let current = notes.first { $0.path == source }!
            guard let entry = NativeFrontmatter(current.content).entry(definition.name) else { continue }
            if let target = destinationDefinitions.first(where: { $0.id == definition.id }) {
                if target.type != .relation || target.relationPairID == nil || target.relationPairID != definition.relationPairID {
                    restores.append((definition.name, entry.value))
                    try reconcile(source, name: definition.name, clearing: true)
                    summaries.append("\(definition.name) uses the destination’s \(target.type.label.lowercased()) definition; previous paired links are removed and relation values are synchronized under the destination pair when applicable.")
                }
            } else {
                try add(raw(definition), owner: destinationOwner)
                summaries.append("Keep \(definition.name) as a relation on \(destinationOwner.isEmpty ? "Inbox" : destinationOwner).")
            }
        }
        let index = notes.firstIndex { $0.path == source }!
        for (name, value) in restores { notes[index].content = try NativeFrontmatter(notes[index].content).setting(name, value: value) }
        notes[index].path = destination; reads.insert(source)
        let moved = notes[index]
        let carried = try schema.checkedEffective(notePath: destination).filter { $0.type == .relation && NativeFrontmatter(moved.content).entry($0.name) != nil }
        for definition in carried { try reconcile(destination, name: definition.name) }
        for (path, name) in incomingFields { try reconcile(path, name: name) }
        let pairs = Set(try schema.checkedEffective(notePath: destination).filter { $0.type == .relation && NativeFrontmatter(notes.first { $0.path == destination }!.content).entry($0.name) != nil }.compactMap(\.relationPairID))
        try broaden(pairs: pairs, sourceOwners: [sourceOwner], destinationOwner: destinationOwner)
        return try finish(source: source, destination: destination)
    }
    func broaden(pairs: Set<String>, sourceOwners: Set<String>, destinationOwner: String) throws {
        var object = try object()
        for owner in Array(object.keys).sorted() {
            guard var owned = object[owner] as? [[String: Any]] else { continue }
            for index in owned.indices {
                guard owned[index]["type"] as? String == "relation", let pair = owned[index]["relationPairId"] as? String, pairs.contains(pair),
                      let key = owned[index]["relationTypeKey"] as? String, !key.isEmpty,
                      sourceOwners.contains(where: { $0 == key || $0.hasPrefix(key + "/") }), !(destinationOwner == key || destinationOwner.hasPrefix(key + "/")) else { continue }
                let left = key.split(separator: "/"), right = destinationOwner.split(separator: "/")
                let common = zip(left, right).prefix(while: { $0.0 == $0.1 }).map { String($0.0) }.joined(separator: "/")
                owned[index]["relationTypeKey"] = common
                summaries.append("\(owner.isEmpty ? "Inbox" : owner) · \(owned[index]["name"] as? String ?? "Relation") will accept \(common.isEmpty ? "any folder" : common) so these notes can be linked again.")
            }
            object[owner] = owned
        }
        try store(object)
    }
    func repair() throws -> NativeRelationMaintenancePlan {
        var templates: [String: [(NativePropertyDefinition, [String: Any])]] = [:], invalidNames = Set<String>()
        let knownKeys = Set(["name", "type", "relationTypeKey", "relationMultiple", "relationPairId", "relationHidden", "relationInverseHidden"])
        func otherSettings(_ raw: [String: Any]) -> NSDictionary { NSDictionary(dictionary: raw.filter { !knownKeys.contains($0.key) }) }
        for (owner, raw) in try object() {
            guard let owned = raw as? [[String: Any]] else { continue }
            for raw in owned {
                guard let definition = try? NativePropertyDefinition.decoded(raw, owner: owner) else {
                    if let name = raw["name"] as? String { invalidNames.insert(name.lowercased()) }
                    continue
                }
                templates[definition.id, default: []].append((definition, raw))
            }
        }
        struct Candidate { let path: String; let name: String; let owner: String }
        var candidates: [Candidate] = [], issues: [NativeRelationRepairIssue] = [], visited = Set<String>()
        for note in notes where !note.trashed && !note.path.hasPrefix(".zerus/") {
            guard let definitions = try? schema.checkedEffective(notePath: note.path) else { continue }
            for entry in NativeFrontmatter(note.content).entries where !entry.id.hasPrefix("zerus-") && !definitions.contains(where: { $0.id == entry.id }) && templates[entry.id]?.contains(where: { $0.0.type == .relation }) == true {
                candidates.append(Candidate(path: note.path, name: entry.key, owner: NativeRelationSnapshot.owner(note)))
            }
        }
        for candidate in candidates.sorted(by: { ($0.owner.split(separator: "/").count, $0.owner, $0.name) < ($1.owner.split(separator: "/").count, $1.owner, $1.name) }) {
            let id = candidate.name.lowercased(), group = candidate.owner + "\n" + id
            guard visited.insert(group).inserted else { continue }
            let issue = { (reason: String) in NativeRelationRepairIssue(path: candidate.path, name: candidate.name, reason: reason) }
            guard try schema.checkedEffective(notePath: candidate.path).first(where: { $0.id == id }) == nil else { continue }
            let choices = (templates[id] ?? []).sorted { $0.0.owner < $1.0.owner }
            guard !invalidNames.contains(id), let first = choices.first, choices.allSatisfy({
                $0.0.type == .relation && ($0.0.relationTypeKey ?? "") == (first.0.relationTypeKey ?? "") && $0.0.relationMultiple == first.0.relationMultiple && $0.0.relationPairID == first.0.relationPairID && $0.0.hidden == first.0.hidden && $0.0.relationInverseHidden == first.0.relationInverseHidden && otherSettings($0.1).isEqual(otherSettings(first.1))
            }) else { issues.append(issue("Definitions with this name disagree about the relation or its pair. Choose the intended relation in Folder properties.")); continue }
            let savedNotes = notes, savedBytes = bytes, savedReads = reads, savedSummaryCount = summaries.count
            do {
                var raw = first.1; raw["name"] = candidate.name
                try add(raw, owner: candidate.owner)
                var targets: [String] = [], populated = false
                for note in notes where !note.trashed && !note.path.hasPrefix(".zerus/") {
                    let owner = NativeRelationSnapshot.owner(note)
                    guard candidate.owner.isEmpty ? owner.isEmpty : (owner == candidate.owner || owner.hasPrefix(candidate.owner + "/")) else { continue }
                    guard let definition = try schema.checkedEffective(notePath: note.path).first(where: { $0.id == id }), definition.owner == candidate.owner else { continue }
                    reads.insert(note.path)
                    guard NativeFrontmatter(note.content).entry(candidate.name) != nil else { continue }
                    let resolver = NativeRelationSnapshot(schema: schema, notes: notes, sourcePath: note.path, name: candidate.name)
                    let values = try resolver.references()
                    if !values.isEmpty { populated = true }
                    for reference in values {
                        let matches = resolver.matches(reference)
                        guard matches.count == 1, let target = matches.first, target.path != note.path, NativeRelationSnapshot.eligible(target, for: definition) else { throw VaultFailure(message: "A value in \(note.path) is missing, ambiguous or outside the target folder. It was left unchanged.") }
                    }
                    targets.append(note.path)
                }
                guard populated else { throw VaultFailure(message: "No populated relation could be inferred from this folder’s values.") }
                for path in targets { try reconcile(path, name: candidate.name) }
                let pairs = Set(try schema.definitions(owner: candidate.owner).filter { $0.id == id }.compactMap(\.relationPairID))
                try broaden(pairs: pairs, sourceOwners: Set(choices.map { $0.0.owner }), destinationOwner: candidate.owner)
                summaries.append("Restore \(candidate.name) on \(candidate.owner.isEmpty ? "Inbox" : candidate.owner) and synchronize its paired links.")
            } catch { notes = savedNotes; bytes = savedBytes; reads = savedReads; summaries = Array(summaries.prefix(savedSummaryCount)); issues.append(issue(error.localizedDescription)) }
        }
        return try finish(issues: issues)
    }
}

extension NativeRelationDefinitionSnapshot {
    func movePlan(source: String, destination: String) throws -> NativeRelationMaintenancePlan { try NativeRelationMaintenance(self).move(source: source, destination: destination) }
    func renameIdentityPlan(source: String, destination: String) throws -> NativeRelationMaintenancePlan { try NativeRelationMaintenance(self).move(source: source, destination: destination, renaming: true) }
    func repairPlan() throws -> NativeRelationMaintenancePlan { try NativeRelationMaintenance(self).repair() }
}

extension VaultFiles {
    func applyRelationMaintenance(_ plan: NativeRelationMaintenancePlan) throws -> VaultSnapshot {
        let bindings = plan.resourceBindings, originalRoot = root
        var locations: [URL] = [], seen = Set<String>()
        for binding in bindings {
            for location in (try? Self.resourceCandidates(binding.reference, notePath: binding.notePath, root: root)) ?? [] where seen.insert(location.path).inserted { locations.append(location) }
        }
        return try applyRelationChanges(schema: plan.snapshot.schema, notes: plan.snapshot.notes, changes: plan.changes, reading: locations) {
            for binding in bindings where NativeMoveResourceBinding.path(binding.reference, notePath: binding.notePath, root: originalRoot) != binding.resolved {
                throw VaultFailure(message: "A linked file changed while this move was being reviewed. No note files were changed; reload the move.")
            }
        }
    }
}
