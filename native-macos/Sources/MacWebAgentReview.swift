import Foundation

extension VaultFiles {
    /// Imported changes retain the web planner's exact snapshots. They are never
    /// replayed as if the native planner had authored the original operation.
    func reviewMacWebAgentProposals(_ record: NativeAgentRecord, owner: String, ids: Set<UUID>, automatic: Bool) throws -> NativeAgentReview {
        var run = try agentChecked(record, owner: owner)
        guard let migration = run.webMigration, ids.isSubset(of: Set(migration.proposalIDs)), !automatic, run.mode != .ask else {
            throw VaultFailure(message: "Imported proposals require their own explicit review in a writable mode. They are never applied automatically.")
        }
        let chosen = run.pending.filter { ids.contains($0.id) }
        guard !chosen.isEmpty, chosen.count == ids.count else { throw VaultFailure(message: "Choose pending imported proposals to review.") }
        let notes = try scan().notes
        var changes: [VaultFileChange] = []
        for proposal in chosen {
            var remainingBefore: [NativeAgentNote] = [], remainingAfter: [NativeAgentNote] = []
            for (index, after) in proposal.afters.enumerated() {
                let before = proposal.befores.indices.contains(index) ? proposal.befores[index] : nil
                try importedAccess(before: before, after: after, run: run)
                let actual = try importedData(after.path), original = try before.map { try importedData($0.path) } ?? nil
                let old = before.map { Data($0.content.utf8) }, next = Data(after.content.utf8)
                let alreadySaved = actual == next && (before == nil || before!.path == after.path || original == nil)
                if !alreadySaved {
                    guard original == old, before?.path == after.path || actual == nil else { throw VaultFailure(message: "An imported proposal target changed or its destination is occupied. No files were changed; request a fresh proposal.") }
                    if let before, before.path != after.path { try Self.mergeAgentChanges([.init(path: before.path, before: old, after: nil)], into: &changes) }
                    try Self.mergeAgentChanges([.init(path: after.path, before: before?.path == after.path ? old : nil, after: next)], into: &changes)
                }
                // Preserve per-note receipts from an interrupted web apply. A
                // matching after-state without a receipt is acknowledged once.
                let receiptExists = run.receipts.contains { $0.undoneAt == nil && $0.proposalIDs.contains(proposal.id) && $0.after.contains(after) && (before == nil || $0.before.contains(before!)) }
                if !receiptExists {
                    if let before { remainingBefore.append(before) }
                    remainingAfter.append(after)
                }
                if let before { rebindImportedIdentity(&run, before: before, after: after) }
                else {
                    if !run.readIDs.contains(after.id) { run.readIDs.append(after.id) }
                    if !run.writeIDs.contains(after.id) { run.writeIDs.append(after.id) }
                }
            }
            if !remainingAfter.isEmpty { run.receipts.append(.init(id: UUID(), date: Date(), proposalIDs: [proposal.id], before: remainingBefore, after: remainingAfter)) }
            if let index = run.proposals.firstIndex(where: { $0.id == proposal.id }) { run.proposals[index].status = "applied" }
        }
        run.status = "waiting"; run.event("Verified explicitly reviewed imported proposal snapshots; retained earlier partial receipts.")
        run.messages.append(.init(role: "user", content: "Runtime verified the user's reviewed imported proposals: " + chosen.map { $0.id.uuidString }.joined(separator: ", ") + ". Exact receipts are saved. Re-read affected notes before more edits."))
        let guards = try notes.filter { note in !changes.contains { $0.path == note.path } }.map { note -> VaultFileChange in let bytes = try read(note.path); return .init(path: note.path, before: bytes, after: bytes) }
        try Self.mergeAgentChanges(guards, into: &changes)
        try importedUniqueIdentities(notes: notes, changes: changes)
        let storage = try agentJournalChanges(agentEncode(run, previous: record.bytes), previous: record.bytes, id: run.id)
        changes += storage.changes
        return .init(root: root, record: record, next: storage.record.run, changes: changes, label: "Apply reviewed web-run changes", identities: notes)
    }

    func reviewMacWebAgentUndo(_ record: NativeAgentRecord, owner: String, receiptID: UUID) throws -> NativeAgentReview {
        var run = try agentChecked(record, owner: owner)
        guard run.webMigration != nil, run.mode != .ask,
              let index = run.receipts.firstIndex(where: { $0.id == receiptID && $0.undoneAt == nil }) else { throw VaultFailure(message: "This imported receipt is unavailable, read-only or already undone.") }
        let receipt = run.receipts[index], notes = try scan().notes
        var changes: [VaultFileChange] = []
        for after in receipt.after {
            let before = receipt.before.first { $0.id == after.id } ?? (receipt.before.count == receipt.after.count ? receipt.before[receipt.after.firstIndex(of: after)!] : nil)
            try importedAccess(before: before, after: after, run: run, undo: true)
            guard try importedData(after.path) == Data(after.content.utf8) else { throw VaultFailure(message: "This note changed after the imported receipt. Undo kept the newer work.") }
            if let before {
                if before.path != after.path {
                    guard try importedData(before.path) == nil else { throw VaultFailure(message: "The original path is occupied. Undo did not replace that file.") }
                    try Self.mergeAgentChanges([.init(path: after.path, before: Data(after.content.utf8), after: nil), .init(path: before.path, before: nil, after: Data(before.content.utf8))], into: &changes)
                } else { try Self.mergeAgentChanges([.init(path: before.path, before: Data(after.content.utf8), after: Data(before.content.utf8))], into: &changes) }
                rebindImportedIdentity(&run, before: after, after: before)
            } else {
                guard NativeAgentNote.ordinary(after.path) else { throw VaultFailure(message: "This created-note receipt has no ordinary path to move to Trash.") }
                let destination = ".trash/" + after.path
                guard try importedData(destination) == nil else { throw VaultFailure(message: "The Trash destination is occupied. Undo preserved both notes.") }
                try Self.mergeAgentChanges([.init(path: after.path, before: Data(after.content.utf8), after: nil), .init(path: destination, before: nil, after: Data(after.content.utf8))], into: &changes)
            }
        }
        run.receipts[index].undoneAt = Date(); run.event("Undid the exact imported receipt; newer affected-file edits were refused.")
        try importedUniqueIdentities(notes: notes, changes: changes)
        run.messages.append(.init(role: "user", content: "Runtime: the user undid imported receipt " + receiptID.uuidString + ". Re-read affected notes before making another proposal."))
        let storage = try agentJournalChanges(agentEncode(run, previous: record.bytes), previous: record.bytes, id: run.id)
        changes += storage.changes
        return .init(root: root, record: record, next: storage.record.run, changes: changes, label: "Undo reviewed web-run receipt", identities: notes)
    }
    private func importedData(_ path: String) throws -> Data? {
        FileManager.default.fileExists(atPath: try url(for: path).path) ? try read(path) : nil
    }
    private func importedAccess(before: NativeAgentNote?, after: NativeAgentNote, run: NativeAgentRun, undo: Bool = false) throws {
        guard run.mode != .ask, NativeAgentOrganization.notePath(after.path), before.map({ NativeAgentOrganization.notePath($0.path) }) ?? true else { throw VaultFailure(message: "An imported change is outside ordinary note storage.") }
        if let before {
            let grant = run.writeIDs.contains(before.id) || run.writeIDs.contains(after.id)
            let beforePath = before.path.hasPrefix(".trash/") ? String(before.path.dropFirst(7)) : before.path
            let afterPath = after.path.hasPrefix(".trash/") ? String(after.path.dropFirst(7)) : after.path
            guard grant, run.permitsPath(beforePath), run.permitsPath(afterPath), before.document.fileHub == nil, after.document.fileHub == nil else { throw VaultFailure(message: "An imported change is outside the run's frozen writable note and folder grants.") }
        } else {
            guard run.permitsCreation((after.path as NSString).deletingLastPathComponent), after.document.stableID != nil else { throw VaultFailure(message: "This imported new note is outside its frozen creation permission.") }
        }
    }
    private func rebindImportedIdentity(_ run: inout NativeAgentRun, before: NativeAgentNote, after: NativeAgentNote) {
        run.rebindWebIdentity(from: before.id, to: after.id)
    }
    private func importedUniqueIdentities(notes: [NoteDocument], changes: [VaultFileChange]) throws {
        var files = Dictionary(uniqueKeysWithValues: notes.map { ($0.path, $0) })
        for change in changes where NativeAgentOrganization.notePath(change.path) {
            files[change.path] = change.after.map { NoteDocument(path: change.path, content: String(decoding: $0, as: UTF8.self), modified: .distantPast) }
        }
        let groups = Dictionary(grouping: files.values.filter { !$0.trashed }, by: NativeAgentNote.identity)
        let touched = Set(changes.filter { $0.before != $0.after }.map(\.path))
        guard !groups.values.contains(where: { $0.count > 1 && $0.contains { touched.contains($0.path) } }) else { throw VaultFailure(message: "An imported change would duplicate a live note identity. No files were changed.") }
    }
}
