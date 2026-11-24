import Foundation

extension VaultFiles {
    private func organizationData(_ path: String) throws -> Data? {
        let location = try url(for: path)
        return FileManager.default.fileExists(atPath: location.path) ? try read(path) : nil
    }
    private func organizationAccess(_ note: NoteDocument, run: NativeAgentRun, unarchiving: Bool = false) throws {
        guard run.mode != .ask, NativeAgentNote.ordinary(note.path), !note.trashed, note.fileHub == nil,
              run.writeIDs.contains(NativeAgentNote.identity(note)), run.permitsPath(note.path), !note.archived || unarchiving,
              run.reads.contains(where: { $0.id == NativeAgentNote.identity(note) && $0.revision == NativeAgentNote.hash(note.content) }) else {
            throw VaultFailure(message: "Read every affected ordinary note at its current revision inside the writable context. Archived notes can only be explicitly unarchived.")
        }
    }
    private func organizationSchemaSemantics(_ proposal: NativeAgentProposal) throws -> [String: String] {
        let schema = try relationDefinitionSnapshot().schema
        var result: [String: String] = [:]
        let filing = proposal.before.map { $0.path != proposal.after.path && !proposal.after.document.trashed } ?? false
        for note in proposal.befores + proposal.afters {
            let frontmatter = NativeFrontmatter(note.content)
            let names = Set(frontmatter.entries.map(\.id).filter { !$0.hasPrefix("zerus-") })
            guard filing, !names.isEmpty else { continue }
            let definitions = try schema.checkedEffective(notePath: note.path).filter { names.contains($0.id) }
            let values: [[String: Any]] = definitions.sorted { $0.id < $1.id }.map {
                ["id": $0.id, "type": $0.type.rawValue, "options": $0.options, "multiple": $0.multiple,
                 "hidden": $0.hidden, "relationTypeKey": $0.relationTypeKey ?? "", "relationMultiple": $0.relationMultiple,
                 "relationPairID": $0.relationPairID ?? "", "relationInverseHidden": $0.relationInverseHidden]
            }
            result[note.path] = NativeHistory.hash(try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]))
        }
        return result
    }
    func macOrganizationProposal(_ call: NativeAgentCall, run: NativeAgentRun) throws -> NativeAgentProposal? {
        guard let args = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any],
              Set(args.keys).isSubset(of: ["selector", "revision", "typePath", "title", "pinned", "archived", "trash"]),
              let revision = args["revision"] as? String, !revision.isEmpty,
              args["selector"] == nil || (args["selector"] as? String).map({ !$0.isEmpty && $0.utf16.count <= 1000 }) == true else { throw VaultFailure(message: "Use an exact selector and current revision for organization.") }
        for name in ["pinned", "archived", "trash"] where args[name] != nil {
            guard let value = args[name], CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else { throw VaultFailure(message: "Use a boolean for \(name).") }
        }
        let snapshot = try relationDefinitionSnapshot(), notes = snapshot.notes
        let source = try agentResolve(args["selector"] as? String, run: run, notes: notes)
        try organizationAccess(source, run: run, unarchiving: args["archived"] as? Bool == false)
        guard revision == NativeAgentNote.hash(source.content) else { throw VaultFailure(message: "The organization revision changed. Read the note again.") }
        let title: String?
        if let raw = args["title"] { guard let text = raw as? String else { throw VaultFailure(message: "Use a single-line title.") }; title = try NativeNoteRename.cleanTitle(text) } else { title = nil }
        var destination = source.path
        if let raw = args["typePath"] {
            guard let parts = raw as? [String], parts.count <= 8, parts.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") }) else { throw VaultFailure(message: "Use a folder path array, or [] for Inbox.") }
            let folder = parts.joined(separator: "/"); try NativePropertyDefinition.validateOwner(folder)
            destination = (folder.isEmpty ? "" : folder + "/") + (source.path as NSString).lastPathComponent
            if destination != source.path {
                guard (run.organizationFolders ?? []).contains(where: { $0 == "*" || $0 == folder || !$0.isEmpty && folder.hasPrefix($0 + "/") }) else { throw VaultFailure(message: "That filing destination is outside this run's explicit organization permission.") }
            }
        }
        let trash = args["trash"] as? Bool == true
        let original = Dictionary(uniqueKeysWithValues: notes.map { ($0.path, $0) })
        var working = original, seeded: [String: NoteDocument] = [:], assigned: [String: String] = [:]
        if title != nil || destination != source.path || trash {
            for note in notes where note.stableID == nil && run.writeIDs.contains(NativeAgentNote.identity(note)) && NativeAgentNote.ordinary(note.path) {
                let id = "agent-" + NativeHistory.hash(run.id.uuidString + "\u{0}" + note.path).prefix(32)
                guard !notes.contains(where: { $0.stableID == id }) else { throw VaultFailure(message: "A generated stable note identity is already occupied.") }
                if let content = try? NativeFrontmatter(note.content).setting("zerus-id", value: .text(id)) {
                    var updated = note; updated.content = content; working[note.path] = updated; seeded[note.path] = updated; assigned[note.path] = id
                }
            }
        }
        var metadata: [String: VaultFileChange] = [:], bindings: [NativeAgentOrganization.Binding] = []
        func currentSnapshot() -> NativeRelationDefinitionSnapshot { .init(schema: snapshot.schema, notes: working.values.sorted { $0.path < $1.path }) }
        func consume(_ plan: NativeRelationMaintenancePlan) throws {
            for change in plan.changes {
                if change.path.lowercased().hasSuffix(".md") {
                    if let bytes = change.after { working[change.path] = NoteDocument(path: change.path, content: String(decoding: bytes, as: UTF8.self), modified: .distantPast) }
                    else { working.removeValue(forKey: change.path) }
                } else if change.before != change.after {
                    guard change.path != ".zerus/properties.json" else { throw VaultFailure(message: "The destination needs a relation-definition change. Configure compatible folder properties before asking the agent to file this note.") }
                    metadata[change.path] = change
                }
            }
            bindings += plan.resourceBindings.map { .init(notePath: $0.notePath, reference: $0.reference, resolved: $0.resolved) }
        }
        if let title {
            let plan: NativeRelationMaintenancePlan
            do { plan = try prepareRename(currentSnapshot(), source: source.path, title: title, renameFile: false).maintenance }
            catch { throw VaultFailure(message: "Native link/relation planning needs attention. Resolve ambiguous links or compatible folder properties before organizing; no files were changed.") }
            try consume(plan)
        }
        if destination != source.path {
            guard try organizationData(destination) == nil else { throw VaultFailure(message: "A file already occupies the filing destination. No file was replaced.") }
            let plan: NativeRelationMaintenancePlan
            do { plan = try prepareMove(currentSnapshot(), source: source.path, destination: destination) }
            catch { throw VaultFailure(message: "Native link/relation planning needs attention. Resolve ambiguous links or compatible folder properties before organizing; no files were changed.") }
            try consume(plan)
        }
        if trash {
            let target = ".trash/" + destination
            guard try organizationData(target) == nil, working[target] == nil else { throw VaultFailure(message: "A note already occupies the Trash destination. No note was replaced.") }
            var note = working.removeValue(forKey: destination)!
            note.path = target; working[target] = note; destination = target
        }
        guard var after = working[destination] else { throw VaultFailure(message: "The organized note is unavailable.") }
        for (argument, key) in [("pinned", "zerus-pinned"), ("archived", "zerus-archived")] {
            if let value = args[argument] as? Bool { after.content = try NativeFrontmatter(after.content).setting(key, value: .checkbox(value)) }
        }
        working[destination] = after
        // Seed IDs deterministically for planner replay, but commit an upgrade
        // only where a real edit or a rewritten reference actually needs it.
        var needed = Set<String>()
        let expression = try NSRegularExpression(pattern: #"agent-[a-f0-9]{32}"#)
        for note in working.values {
            let content = assigned.values.contains(note.stableID ?? "") ? (try NativeFrontmatter(note.content).setting("zerus-id", value: nil)) : note.content
            let text = content as NSString
            for match in expression.matches(in: content, range: NSRange(location: 0, length: text.length)) { needed.insert(text.substring(with: match.range)) }
        }
        for (path, seed) in seeded where path != source.path && !needed.contains(assigned[path]!) {
            guard var note = working[path] else { continue }
            if note.content == seed.content { working[path] = original[path]; continue }
            note.content = try NativeFrontmatter(note.content).setting("zerus-id", value: nil)
            let header = NativeFrontmatter(note.content)
            if !NativeFrontmatter(original[path]!.content).hasHeader && header.entries.isEmpty { note.content = header.byteOrderPrefix + header.body }
            working[path] = note
        }
        for (path, note) in working where note.stableID != nil {
            let previousPath = path == destination ? source.path : path
            guard let previous = original[previousPath], previous.stableID == nil else { continue }
            guard note.stableID == assigned[previousPath] else { throw VaultFailure(message: "A legacy note could not receive a repeatable identity. Resolve its frontmatter before organization.") }
        }
        var changes: [VaultFileChange] = []
        for path in Set(original.keys).union(working.keys).sorted() {
            let before = original[path]?.content, next = working[path]?.content
            if before != next { changes.append(.init(path: path, before: before.map { Data($0.utf8) }, after: next.map { Data($0.utf8) })) }
        }
        after = working[destination]!
        if destination != source.path, let tasks = try organizationData(".zerus/tasks.json"),
           let bytes = try NativeAgentOrganization.reboundTasks(tasks, source: source.path, target: after.stableID ?? destination) {
            metadata[".zerus/tasks.json"] = .init(path: ".zerus/tasks.json", before: tasks, after: bytes)
        }
        let changedBefore = changes.compactMap { change in original[change.path] }
        for note in changedBefore { try organizationAccess(note, run: run, unarchiving: note.path == source.path && args["archived"] as? Bool == false) }
        for change in changes where change.before != nil {
            guard try read(change.path) == change.before else { throw VaultFailure(message: "An affected note uses different disk bytes or changed during planning. Its file was kept.") }
        }
        for path in metadata.keys { guard [".zerus/tasks.json"].contains(path) else { throw VaultFailure(message: "This organization operation needs an unsupported shared-file change.") } }
        changes += metadata.values.sorted { $0.path < $1.path }
        guard !changes.isEmpty else { return nil }
        let companions = changedBefore.filter { $0.path != source.path }.compactMap { before -> NativeAgentCompanion? in
            guard let next = working[before.path] else { return nil }
            return .init(before: .init(before), after: .init(next))
        }
        let dependencies = try [".zerus/properties.json", ".zerus/links.json", ".zerus/tasks.json"].map { path in NativeAgentOrganization.Dependency(path: path, sha256: try organizationData(path).map(NativeHistory.hash)) }
        let mapping = destination == source.path ? [:] : [source.path: destination]
        var created: [String: Double] = [:]
        for before in changedBefore { created[mapping[before.path] ?? before.path] = before.created?.timeIntervalSince1970 }
        var organization = NativeAgentOrganization(changes: changes, dependencies: dependencies, mappings: mapping, bindings: bindings.sorted { ($0.notePath, $0.reference) < ($1.notePath, $1.reference) }, created: created)
        try organization.validate()
        var proposal = NativeAgentProposal(id: UUID(), call: call, before: .init(source), after: .init(after), companions: companions.isEmpty ? nil : companions, organization: organization)
        organization.schemaSemantics = try organizationSchemaSemantics(proposal)
        proposal.organization = organization
        return proposal
    }

    func macAgentOrganize(_ record: NativeAgentRecord, owner: String, call: NativeAgentCall) throws -> NativeAgentRecord {
        var run = try agentChecked(record, owner: owner)
        guard run.pendingCalls.contains(call) else { throw VaultFailure(message: "This organization call is not pending.") }
        let result: [String: Any]
        do {
            guard run.question == nil, run.withinBudget else { throw VaultFailure(message: "This run is waiting or reached its saved limit.") }
            if let proposal = try macOrganizationProposal(call, run: run) {
                run.version = max(run.version, 2)
                var prospective = run; prospective.proposals.append(proposal)
                _ = try agentEncode(prospective, previous: record.bytes)
                run.proposals.append(proposal)
                result = ["ok": true, "proposalId": proposal.id.uuidString, "saved": false, "affectedNoteCount": proposal.afters.count, "affectedNotes": proposal.afters.prefix(20).map { ["id": $0.id, "path": $0.path, "title": $0.title] }]
            } else { result = ["ok": true, "changed": false, "saved": false] }
        } catch is CancellationError { throw CancellationError() }
        catch { result = ["ok": false, "error": error.localizedDescription] }
        let content = String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        run.messages.append(.init(role: "tool", content: content, toolCallId: call.id)); run.event("Tool: note_organize")
        return try agentStore(run, previous: record.bytes)
    }

    private func organizationReviewDependencies(_ notes: [NoteDocument], metadata: [NativeAgentOrganization.Dependency]) throws -> [VaultFileChange] {
        var changes: [VaultFileChange] = []
        for note in notes {
            let bytes = try read(note.path)
            guard NoteDocument.decodeUTF8(bytes) == note.content else { throw VaultFailure(message: "Vault notes changed while preparing organization. Review again.") }
            changes.append(.init(path: note.path, before: bytes, after: bytes))
        }
        for dependency in metadata {
            let data = try organizationData(dependency.path)
            guard data.map(NativeHistory.hash) == dependency.sha256 else { throw VaultFailure(message: "Shared organization settings changed while preparing review.") }
            changes.append(.init(path: dependency.path, before: data, after: data))
        }
        return changes
    }
    func macAgentReview(_ record: NativeAgentRecord, owner: String, ids: Set<UUID>, automatic: Bool) throws -> NativeAgentReview {
        if let migration = record.run.webMigration, !ids.isDisjoint(with: migration.proposalIDs) {
            return try reviewMacWebAgentProposals(record, owner: owner, ids: ids, automatic: automatic)
        }
        var run = try agentChecked(record, owner: owner)
        let proposals = run.proposals.filter { ids.contains($0.id) }, organized = proposals.filter { $0.organization != nil }
        guard !organized.isEmpty else { return try agentReview(record, owner: owner, ids: ids, automatic: automatic) }
        guard !proposals.isEmpty, proposals.count == ids.count, proposals.allSatisfy({ $0.status == "pending" }), run.mode != .ask else { throw VaultFailure(message: "Choose pending organization proposals to review.") }
        if automatic {
            guard !organized.contains(where: { $0.after.document.trashed }) else { throw VaultFailure(message: "Moving a note to Trash always requires explicit native review.") }
            let affected = Set(run.receipts.filter { $0.undoneAt == nil }.flatMap { $0.after.map(\.id) } + proposals.flatMap(\.afters).map(\.id))
            guard run.mode == .edit, run.question == nil, run.withinBudget, run.pending.count == 1, proposals.count == 1, affected.count == 1 else { throw VaultFailure(message: "These organization changes require explicit native review.") }
        }
        let ordinary = Set(proposals.filter { $0.organization == nil }.map(\.id)), notes = try scan().notes
        var changes: [VaultFileChange] = []
        if !ordinary.isEmpty {
            let review = try agentReview(record, owner: owner, ids: ordinary)
            run = review.next; changes = review.changes.filter { !$0.path.hasPrefix(".zerus/native-ai/") }
        }
        for proposal in organized {
            guard let expected = proposal.organization, let actual = try macOrganizationProposal(proposal.call, run: record.run), let planned = actual.organization,
                  expected.changes.filter({ NativeAgentOrganization.notePath($0.path) }) == planned.changes.filter({ NativeAgentOrganization.notePath($0.path) }), expected.schemaSemantics == planned.schemaSemantics, expected.mappings == planned.mappings, expected.bindings == planned.bindings, expected.created == planned.created,
                  proposal.befores == actual.befores, proposal.afters == actual.afters else {
                throw VaultFailure(message: "An organization target, link or setting changed. Request a fresh proposal; no files were changed.")
            }
            for binding in expected.bindings where NativeMoveResourceBinding.path(binding.reference, notePath: binding.notePath, root: root) != binding.resolved { throw VaultFailure(message: "A linked resource moved after the organization proposal. Request a fresh proposal.") }
            try Self.mergeAgentChanges(organizationReviewDependencies(notes, metadata: planned.dependencies), into: &changes)
            try Self.mergeAgentChanges(planned.changes, into: &changes)
            if let index = run.proposals.firstIndex(where: { $0.id == proposal.id }) { run.proposals[index].organization = planned }
            run.receipts.append(.init(id: UUID(), date: Date(), proposalIDs: [proposal.id], before: proposal.befores, after: proposal.afters))
            for (before, after) in zip(proposal.befores, proposal.afters) {
                run.rebindWebIdentity(from: before.id, to: after.id)
                if !run.readIDs.contains(after.id) { run.readIDs.append(after.id) }
                if run.writeIDs.contains(before.id), !run.writeIDs.contains(after.id) { run.writeIDs.append(after.id) }
                if run.currentReadID == before.id { run.currentReadID = after.id }
            }
        }
        for index in run.proposals.indices where ids.contains(run.proposals[index].id) { run.proposals[index].status = "applied" }
        run.status = automatic ? "running" : "waiting"
        run.event("Saved and verified reviewed organization changes.")
        run.messages.append(.init(role: "user", content: "Runtime verified organization proposals: " + organized.map { $0.id.uuidString }.joined(separator: ", ") + ". Exact changes and Undo receipts are saved."))
        let storage = try agentJournalChanges(agentEncode(run, previous: record.bytes), previous: record.bytes, id: run.id)
        changes += storage.changes
        return .init(root: root, record: record, next: storage.record.run, changes: changes, label: automatic ? "Save requested organization" : "Apply reviewed organization", identities: notes)
    }
    func macAgentUndoReview(_ record: NativeAgentRecord, owner: String, receiptID: UUID) throws -> NativeAgentReview {
        if let migration = record.run.webMigration,
           migration.receiptIDs.contains(receiptID) || record.run.receipts.first(where: { $0.id == receiptID })?.proposalIDs.contains(where: { migration.proposalIDs.contains($0) }) == true {
            return try reviewMacWebAgentUndo(record, owner: owner, receiptID: receiptID)
        }
        var run = try agentChecked(record, owner: owner)
        guard let index = run.receipts.firstIndex(where: { $0.id == receiptID && $0.undoneAt == nil }) else { throw VaultFailure(message: "This receipt is unavailable or already undone.") }
        let receipt = run.receipts[index]
        let proposals = run.proposals.filter { receipt.proposalIDs.contains($0.id) && $0.organization != nil }
        guard !proposals.isEmpty else { return try agentUndoReview(record, owner: owner, receiptID: receiptID) }
        guard receipt.before == proposals.flatMap(\.befores), receipt.after == proposals.flatMap(\.afters),
              proposals.flatMap(\.befores).allSatisfy({ run.readIDs.contains($0.id) && run.writeIDs.contains($0.id) && run.permitsPath($0.path) }) else { throw VaultFailure(message: "This organization receipt no longer matches the run's exact writable snapshots.") }
        let notes = try scan().notes
        var changes: [VaultFileChange] = []
        for proposal in proposals {
            let plan = proposal.organization!
            if let expected = plan.schemaSemantics {
                guard try organizationSchemaSemantics(proposal) == expected else { throw VaultFailure(message: "Relevant folder property definitions changed. Request a fresh organization review before Undo.") }
            } else if let dependency = plan.dependencies.first(where: { $0.path == ".zerus/properties.json" }) {
                guard try organizationData(dependency.path).map(NativeHistory.hash) == dependency.sha256 else { throw VaultFailure(message: "Shared organization settings changed. This older receipt needs a fresh review.") }
            }
            for change in plan.changes where change.path != ".zerus/tasks.json" {
                guard try organizationData(change.path) == change.after else { throw VaultFailure(message: "A file changed after this organization receipt. Undo would replace newer work.") }
                try Self.mergeAgentChanges([.init(path: change.path, before: change.after, after: change.before)], into: &changes)
            }
            let affected = Set(plan.changes.map(\.path))
            // A newly written incoming link must never be broken by removing
            // an assigned identity or restoring an old folder path.
            for (before, after) in zip(proposal.befores, proposal.afters) where before.id != after.id {
                guard !notes.contains(where: { !affected.contains($0.path) && $0.content.contains(after.id) }) else { throw VaultFailure(message: "New links use an identity assigned by this receipt. Use a fresh organization review instead of removing those links with Undo.") }
            }
            for (before, after) in zip(proposal.befores, proposal.afters) where before.title != after.title && !after.document.trashed {
                let reverse = try prepareRename(relationDefinitionSnapshot(), source: after.path, title: before.title, renameFile: false)
                guard reverse.maintenance.changes.filter({ $0.before != $0.after }).allSatisfy({ affected.contains($0.path) }) else { throw VaultFailure(message: "New title links need repair. Use a fresh organization review before restoring this title.") }
            }
            for (source, destination) in plan.mappings where !destination.hasPrefix(".trash/") {
                let reverse = try prepareMove(relationDefinitionSnapshot(), source: destination, destination: source)
                guard reverse.changes.filter({ $0.before != $0.after }).allSatisfy({ affected.contains($0.path) }) else { throw VaultFailure(message: "New incoming links need repair. Use a fresh organization review before restoring this path.") }
            }
            let taskPath = ".zerus/tasks.json"
            if let current = try organizationData(taskPath), let source = proposal.before {
                let written = plan.changes.first { $0.path == taskPath }
                let restored = try NativeAgentOrganization.undoTasks(before: written?.before, after: written?.after, current: current, source: source, target: proposal.after)
                if restored != current { try Self.mergeAgentChanges([.init(path: taskPath, before: current, after: restored)], into: &changes) }
            }
            let dependencies = try plan.dependencies.map { NativeAgentOrganization.Dependency(path: $0.path, sha256: try organizationData($0.path).map(NativeHistory.hash)) }
            try Self.mergeAgentChanges(organizationReviewDependencies(notes, metadata: dependencies), into: &changes)
            for (before, after) in zip(proposal.befores, proposal.afters) {
                run.rebindWebIdentity(from: after.id, to: before.id)
                if !run.readIDs.contains(before.id) { run.readIDs.append(before.id) }
                if run.writeIDs.contains(after.id), !run.writeIDs.contains(before.id) { run.writeIDs.append(before.id) }
                if run.currentReadID == after.id { run.currentReadID = before.id }
            }
        }
        run.receipts[index].undoneAt = Date(); run.event("Undid the exact organization receipt; newer affected-file edits were refused.")
        run.messages.append(.init(role: "user", content: "Runtime: the user undid organization receipt " + receiptID.uuidString + ". Re-read the affected notes before proposing another change."))
        let storage = try agentJournalChanges(agentEncode(run, previous: record.bytes), previous: record.bytes, id: run.id)
        changes += storage.changes
        return .init(root: root, record: record, next: storage.record.run, changes: changes, label: "Undo reviewed organization", identities: notes)
    }
}

enum MacAgentOrganizationReconciliation {
    private static func transitions(_ review: NativeAgentReview) -> [(NativeAgentOrganization, Bool)] {
        review.next.proposals.compactMap { proposal in
            guard let plan = proposal.organization else { return nil }
            let forward = review.record.run.proposals.first { $0.id == proposal.id }?.status == "pending" && proposal.status == "applied"
            let undone = review.next.receipts.contains { receipt in receipt.undoneAt != nil && receipt.proposalIDs.contains(proposal.id) && review.record.run.receipts.first(where: { $0.id == receipt.id })?.undoneAt == nil }
            return forward || undone ? (plan, undone) : nil
        }
    }
    static func mappings(_ review: NativeAgentReview) -> [String: String] {
        var result: [String: String] = [:]
        for (plan, undo) in transitions(review) {
            for (from, to) in plan.mappings { result[undo ? to : from] = undo ? from : to }
        }
        return result
    }
    static func creationDates(_ review: NativeAgentReview) -> [String: Date] {
        var result: [String: Date] = [:]
        for (plan, undo) in transitions(review) {
            for (path, date) in plan.created { result[undo ? plan.mappings.first(where: { $0.value == path })?.key ?? path : path] = Date(timeIntervalSince1970: date) }
        }
        return result
    }
}
