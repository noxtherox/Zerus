import Foundation

struct NativePendingExternalHistory: Sendable {
    let before: NoteDocument
    let identity: String
}

struct NativeExternalHistoryResult: Sendable {
    let snapshot: VaultSnapshot
    let addedVersions: Int
    let warnings: [String]
}

extension VaultFiles {
    /// The scan is the new disk state; `previous` is the last state published
    /// to editors. Keep the oldest observed state until its history commits.
    func reconcileExternalHistory(previous: [NoteDocument], scanned: VaultSnapshot) throws -> NativeExternalHistoryResult {
        let oldByPath = Dictionary(uniqueKeysWithValues: previous.map { ($0.path, $0) })
        let oldByID = Dictionary(grouping: previous.compactMap { note in note.stableID.map { ($0, note) } }, by: { $0.0 })
        let newByID = Dictionary(grouping: scanned.notes.compactMap { note in note.stableID.map { ($0, note) } }, by: { $0.0 })
        let currentPaths = Set(scanned.notes.map(\.path))
        var observations: [String: NativeHistoryObservation] = [:], identities: [String: String] = [:], warnings: [String] = []
        for note in scanned.notes {
            var before: NoteDocument?
            if let id = note.stableID, newByID[id]?.count == 1, oldByID[id]?.count == 1 { before = oldByID[id]!.first!.1 }
            else if let old = oldByPath[note.path], old.stableID == nil || note.stableID == nil || old.stableID == note.stableID { before = old }
            guard let before, NativeHistory.stripped(before.content) != NativeHistory.stripped(note.content) else { continue }
            let id = note.stableID ?? before.stableID ?? UUID().uuidString.lowercased()
            guard NativeHistory.identity(id), (newByID[id]?.count ?? 0) <= 1, (oldByID[id]?.count ?? 0) <= 1 else {
                warnings.append(note.title + ": history was skipped because its note identity is ambiguous."); continue
            }
            // Find a queued observation by identity across a subsequent rename.
            let queued = pendingExternalHistory.values.first { $0.identity == id } ?? pendingExternalHistory[note.path]
            let earliest = queued?.before ?? before
            pendingExternalHistory[note.path] = .init(before: earliest, identity: id)
            observations[note.path] = .init(before: earliest, retrying: queued != nil)
            identities[note.path] = id
        }
        do {
            let configuration = try historyConfiguration()
            if !configuration.enabled {
                pendingExternalHistory.removeAll(); externalHistoryBootstrapped = true
                return .init(snapshot: scanned, addedVersions: 0, warnings: [])
            }
            for note in scanned.notes where observations[note.path] == nil {
                let queued = pendingExternalHistory[note.path] ?? pendingExternalHistory.values.first { $0.identity == note.stableID }
                if let queued, note.stableID == nil || note.stableID == queued.identity,
                   (newByID[queued.identity]?.count ?? 0) <= 1,
                   NativeHistory.stripped(queued.before.content) != NativeHistory.stripped(note.content) {
                    observations[note.path] = .init(before: queued.before, retrying: true); identities[note.path] = queued.identity
                } else if !externalHistoryBootstrapped, let id = note.stableID, NativeHistory.identity(id), newByID[id]?.count == 1 {
                    // After a cold launch the newest stored version is the only
                    // recoverable prior state. Intermediate edits are unknown.
                    let history = try historySnapshot(notePath: note.path)
                    if let last = history.versions.first(where: { $0.content != nil }), let content = last.content,
                       NativeHistory.stripped(content) != NativeHistory.stripped(note.content) {
                        let old = NoteDocument(path: note.path, content: content, modified: NativeRevisionIndex.date(last.timestamp) ?? .distantPast)
                        observations[note.path] = .init(before: old, retrying: false); identities[note.path] = id
                        pendingExternalHistory[note.path] = .init(before: old, identity: id)
                    }
                }
            }
            guard !observations.isEmpty else {
                externalHistoryBootstrapped = true
                return .init(snapshot: scanned, addedVersions: 0, warnings: warnings)
            }
            let inventory = try Self.historyMaintenanceInventory(root: root)
            let changes = try scanned.notes.map { note -> VaultFileChange in
                var text = note.content
                if let id = identities[note.path], note.stableID == nil { text = try NativeFrontmatter(text).setting("zerus-id", value: .text(id)) }
                return .init(path: note.path, before: Data(note.content.utf8), after: Data(text.utf8))
            }
            let prepared = try includingAutomaticHistory(changes, source: "external", observations: observations)
            let root = root
            try applyTransaction(prepared, historySource: "external", validate: {
                guard try Self.notePathInventory(root: root) == currentPaths,
                      try Self.historyMaintenanceInventory(root: root) == inventory else {
                    throw VaultFailure(message: "Files changed again while external history was being saved. Zerus will retry.")
                }
            })
            let ids = Set(identities.values)
            pendingExternalHistory = pendingExternalHistory.filter { !ids.contains($0.value.identity) }
            externalHistoryBootstrapped = true
            let added = prepared.filter { $0.path.hasPrefix(".zerus/history/notes/") && $0.before == nil && $0.after != nil }.count
            return .init(snapshot: try scan(), addedVersions: added, warnings: warnings)
        } catch let required as VaultRecoveryRequired { throw required }
        catch {
            // The external file already exists. Show it even when saving its
            // history fails; retain the observed baseline for the next retry.
            return .init(snapshot: try scan(), addedVersions: 0, warnings: warnings + ["Some external changes could not be added to history yet. " + error.localizedDescription])
        }
    }

    func forgetExternalHistory(_ intent: NativeHistoryMaintenanceIntent) {
        switch intent {
        case .clearAll, .settings(enabled: false, limit: _): pendingExternalHistory.removeAll()
        case .clearNote(let id): pendingExternalHistory = pendingExternalHistory.filter { $0.value.identity != id }
        default: break
        }
    }
}
