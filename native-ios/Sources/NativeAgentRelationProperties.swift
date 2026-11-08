import Foundation

struct NativeAgentPropertyPlan: Sendable {
    let source: NoteDocument
    let companions: [NativeAgentCompanion]
    let dependencies: [NativeAgentNote]
    let relationSchema: Data?
    func matches(_ proposal: NativeAgentProposal) -> Bool {
        NativeAgentNote(source) == proposal.after && companions == (proposal.companions ?? []) && dependencies == (proposal.dependencies ?? []) && relationSchema == proposal.relationSchema
    }
}

extension NativeAgentProperties {
    /// Pure planning: the caller supplies live authorization before the planner
    /// can inspect an inverse. Snapshot replay during Undo has no write effect.
    static func plan(_ call: NativeAgentCall, note: NoteDocument, notes: [NoteDocument], schema: NativeSchemaSnapshot, authorize: (NoteDocument) throws -> Void) throws -> NativeAgentPropertyPlan {
        guard let arguments = try JSONSerialization.jsonObject(with:Data(call.arguments.utf8)) as? [String:Any], arguments["revision"] as? String == NativeAgentNote.hash(note.content) else { throw VaultFailure(message:"This property call no longer matches its original read revision.") }
        let values = try changes(call), definitions = try schema.checkedEffective(notePath:note.path)
        let relationNames = values.keys.filter { name in definitions.contains { $0.id == name.lowercased() && $0.type == .relation } }.sorted()
        if relationNames.isEmpty { return .init(source:.init(path:note.path,content:try applying(call,to:note,schema:schema),modified:note.modified),companions:[],dependencies:[],relationSchema:nil) }
        guard schema.bytes != nil else { throw VaultFailure(message:"Configure the reciprocal relation in note information first.") }
        try authorize(note)
        let originals = Dictionary(uniqueKeysWithValues:notes.map { ($0.path,$0) })
        var working = originals, readPaths = Set([note.path])
        var content = note.content
        for name in values.keys.sorted() where !relationNames.contains(name) {
            try validateOrdinary(name,value:values[name]!,definitions:definitions)
            content = try NativeFrontmatter(content).setting(name,value:values[name]!)
        }
        working[note.path]?.content = content
        for name in relationNames {
            guard let definition = definitions.first(where:{$0.id == name.lowercased()}), !definition.hidden, let pair = definition.relationPairID,
                  definitions.filter({$0.type == .relation && $0.relationPairID == pair}).count == 1 else { throw VaultFailure(message:"Configure one unambiguous reciprocal pair in the native relation editor first.") }
            try definition.validateValue(values[name]!)
            let snapshot = NativeRelationSnapshot(schema:schema,notes:Array(working.values),sourcePath:note.path,name:name)
            func target(_ reference: String, existing: Bool) throws -> NoteDocument? {
                let found = snapshot.matches(reference)
                if existing && found.isEmpty { return nil }
                guard found.count == 1, let target = found.first, target.path != note.path else { throw VaultFailure(message:"A relation target is missing, ambiguous or points to the source note.") }
                try authorize(target)
                let reverse = try schema.checkedEffective(notePath:target.path).filter { $0.type == .relation && $0.relationPairID == pair }
                guard reverse.count == 1 else { throw VaultFailure(message:"Configure the matching inverse on every linked note in the native relation editor first.") }
                return target
            }
            for reference in try snapshot.references() { _ = try target(reference,existing:true) }
            var selected = Set<String>()
            for reference in values[name]!.map(\.selections) ?? [] { if let target = try target(reference,existing:false) { selected.insert(target.path) } }
            let relation = try snapshot.plan(selected:selected,unresolved:[])
            guard !relation.updatesDefinitions else { throw VaultFailure(message:"This relation needs a schema or multiplicity update. Configure it in the native relation editor before requesting agent changes.") }
            for change in relation.changes where change.path != ".zerus/properties.json" {
                guard let original = originals[change.path], original.stableID != nil else { throw VaultFailure(message:"Use the native relation editor to identify legacy linked notes before agent editing.") }
                try authorize(original); readPaths.insert(change.path)
                if let bytes = change.after { working[change.path]?.content = String(decoding:bytes,as:UTF8.self) }
            }
        }
        let source = working[note.path]!
        guard source.parts.body == note.parts.body, NativeAgentNote.identity(source) == NativeAgentNote.identity(note) else { throw VaultFailure(message:"Property planning must preserve writing and note identity.") }
        let companions = try working.values.filter { updated in updated.path != note.path && updated.content != originals[updated.path]?.content }.sorted { $0.path < $1.path }.map { updated -> NativeAgentCompanion in
            let original = originals[updated.path]!
            guard original.parts.body == updated.parts.body, NativeAgentNote.identity(original) == NativeAgentNote.identity(updated) else { throw VaultFailure(message:"Reciprocal updates must preserve linked writing and identity.") }
            return .init(before:.init(original),after:.init(updated))
        }
        return .init(source:source,companions:companions,dependencies:readPaths.sorted().map { NativeAgentNote(originals[$0]!) },relationSchema:schema.bytes)
    }

    static func undoLinked(_ proposal: NativeAgentProposal, receipt: NativeAgentReceipt, notes: [NoteDocument], schema: NativeSchemaSnapshot, authorize: (NoteDocument) throws -> Void) throws -> [VaultFileChange] {
        guard let before = proposal.before, let bytes = proposal.relationSchema, let dependencies = proposal.dependencies else { throw VaultFailure(message:"This linked-note receipt is incomplete and was preserved.") }
        let originalSchema = NativeSchemaSnapshot(root:schema.root,bytes:bytes)
        let replay = try plan(proposal.call,note:before.document,notes:dependencies.map(\.document),schema:originalSchema,authorize:{ _ in })
        guard replay.matches(proposal), proposal.befores.count == proposal.afters.count else { throw VaultFailure(message:"The saved relation call and its exact note snapshots disagree. No files were changed.") }
        var changes: [VaultFileChange] = []
        for after in proposal.afters {
            guard receipt.after.contains(after), let before = proposal.befores.first(where:{$0.id == after.id}), receipt.before.contains(before) else { throw VaultFailure(message:"This linked receipt does not contain the original coordinated note group.") }
            let found = notes.filter { NativeAgentNote.identity($0) == after.id }
            guard found.count == 1, let current = found.first else { throw VaultFailure(message:"A linked note is missing or has an ambiguous identity.") }
            try authorize(current)
            let old = NativeFrontmatter(before.content), saved = NativeFrontmatter(after.content), fresh = NativeFrontmatter(current.content)
            let originalDefinitions = try originalSchema.checkedEffective(notePath:before.path), definitions = try schema.checkedEffective(notePath:current.path)
            let keys = Set((old.entries+saved.entries).map(\.id)).filter { old.entry($0)?.value != saved.entry($0)?.value }.sorted()
            var content = current.content
            for name in keys {
                guard !name.hasPrefix("zerus-") else { throw VaultFailure(message:"A linked receipt cannot restore managed note properties.") }
                let a = old.entry(name), b = saved.entry(name), c = fresh.entry(name)
                guard a == nil || a?.value != nil, b == nil || b?.value != nil, c == nil || c?.value != nil, c?.value == b?.value else { throw VaultFailure(message:"A linked property changed after this receipt. Undo would replace newer work.") }
                let original = originalDefinitions.first { $0.id == name }, currentDefinition = definitions.first { $0.id == name }
                if original?.type == .relation {
                    guard let original, var definition = currentDefinition, definition.type == .relation, definition.relationPairID == original.relationPairID,
                          definition.relationTypeKey == original.relationTypeKey, definition.relationMultiple == original.relationMultiple, definition.hidden == original.hidden else { throw VaultFailure(message:"A reciprocal definition changed. Review it before undoing this relation.") }
                    definition.hidden = false // The verified pair may own a hidden inverse.
                    try definition.validateValue(a?.value)
                    guard definition.relationMultiple || (a?.value?.selections.count ?? 0) <= 1 else { throw VaultFailure(message:"This relation no longer accepts its previous values.") }
                    let resolver = NativeRelationSnapshot(schema:schema,notes:notes,sourcePath:current.path,name:name)
                    let oldResolver = NativeRelationSnapshot(schema:originalSchema,notes:dependencies.map(\.document),sourcePath:before.path,name:name)
                    let retained = Set(b?.value?.selections ?? [])
                    for reference in a?.value?.selections ?? [] where !retained.contains(reference) {
                        let targets = resolver.matches(reference)
                        if targets.isEmpty && oldResolver.matches(reference).isEmpty { continue } // Restore an originally dangling reference verbatim.
                        guard targets.count == 1, let target = targets.first, NativeRelationSnapshot.eligible(target,for:definition) else { throw VaultFailure(message:"A previous relation target moved, disappeared or became ambiguous.") }
                        try authorize(target)
                    }
                } else { try validateOrdinary(name,value:a?.value,definitions:definitions) }
                content = try NativeFrontmatter(content).setting(a?.key ?? b!.key,value:a?.value)
            }
            if fresh.header == saved.header { content = old.header + fresh.body }
            changes.append(.init(path:current.path,before:Data(current.content.utf8),after:Data(content.utf8)))
        }
        return changes
    }
}

extension VaultFiles {
    func agentPropertyAccess(_ note: NoteDocument, run: NativeAgentRun, notes: [NoteDocument], currentRead: Bool) throws {
        let current = try agentResolve(NativeAgentNote.identity(note),run:run,notes:notes)
        guard current.path == note.path, current.stableID != nil, run.writeIDs.contains(NativeAgentNote.identity(current)), NativeAgentNote.ordinary(current.path), !current.archived, current.fileHub == nil else { throw VaultFailure(message:"Every linked note must be identified and inside this run’s writable context.") }
        if currentRead {
            guard run.reads.contains(where:{$0.id == NativeAgentNote.identity(current) && $0.revision == NativeAgentNote.hash(current.content)}) else { throw VaultFailure(message:"Read every existing and chosen inverse note at its current revision before proposing a reciprocal change.") }
        }
    }
    func agentPropertyPlan(_ call: NativeAgentCall, note: NoteDocument, notes: [NoteDocument], schema: NativeSchemaSnapshot, run: NativeAgentRun) throws -> NativeAgentPropertyPlan {
        try NativeAgentProperties.plan(call,note:note,notes:notes,schema:schema) { target in
            try agentPropertyAccess(target,run:run,notes:notes,currentRead:true)
        }
    }
    static func mergeAgentChanges(_ next: [VaultFileChange], into changes: inout [VaultFileChange]) throws {
        for change in next {
            if let index = changes.firstIndex(where:{$0.path == change.path}) {
                let prior = changes[index]
                guard prior.before == change.before, prior.before == prior.after || change.before == change.after || prior.after == change.after else { throw VaultFailure(message:"The selected AI proposals overlap. Review them separately.") }
                if prior.before == prior.after { changes[index] = change }
            } else { changes.append(change) }
        }
    }
}
