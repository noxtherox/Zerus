import Foundation

struct NativeNoteTrashPlan: Sendable {
    let snapshot: NativeRevisionTrashSnapshot
    let history: NativeHistoryMaintenanceSnapshot
    let deleted: [NoteDocument]
    let identities: Set<String>
    let changes: [VaultFileChange]
    let revisionFiles: Set<String>
    let removedRevisions: Int
    let removedHistory: Int
    let removedFiles: [String]
    let retainedFiles: [String]
    let warnings: [String]
    var removedBytes: Int { changes.filter { $0.after == nil }.reduce(0) { $0 + ($1.before?.count ?? 0) } }
}

extension VaultFiles {
    nonisolated static func noteTrashRevisionFiles(root: URL, identities: Set<String>) throws -> Set<String> {
        var result = Set<String>()
        var directories = identities.sorted().map { ".zerus/revisions/notes/" + $0 + "/files" }
        while let directory = directories.popLast() {
            let folder = root.appendingPathComponent(directory)
            _ = try confinedPath(for: folder, root: root)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "A linked revision folder must be reconnected before deleting its note.") }
            for file in try FileManager.default.contentsOfDirectory(at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]) {
                let path = directory + "/" + file.lastPathComponent
                let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw VaultFailure(message: "A linked revision file must be reconnected before deleting its note.") }
                if values.isDirectory == true { directories.append(path) }
                else if values.isRegularFile == true { result.insert(path) }
            }
        }
        return result
    }

    private func noteTrashHistorySnapshot(notes: [NoteDocument], identities: Set<String>) throws -> NativeHistoryMaintenanceSnapshot {
        let inventory = try Self.historyMaintenanceInventory(root: root)
        var records: [String: Data] = [:]
        for path in inventory.records where identities.contains(path.components(separatedBy: "/")[3]) {
            try Task.checkCancellation(); records[path] = try read(path)
        }
        return .init(root: root, inventory: inventory, notes: notes, records: records, metadata: [:], groups: [], configuration: try historyConfiguration(), localDrafts: try Self.historyRecoveryDrafts())
    }
    private func noteTrashHistoryImages(_ history: NativeHistoryMaintenanceSnapshot, identities: Set<String>) -> Set<String> {
        Set(history.records.flatMap { path, data -> [String] in
            guard identities.contains(path.components(separatedBy: "/")[3]),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let images = object["images"] as? [[String: Any]] else { return [] }
            return images.compactMap { image in
                guard let hash = image["hash"] as? String, hash.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else { return nil }
                return ".zerus/history/blobs/" + hash
            }
        })
    }

    func prepareNoteTrashPurge(_ snapshot: NativeRevisionTrashSnapshot, paths: Set<String>) throws -> NativeNoteTrashPlan {
        try Task.checkCancellation()
        guard snapshot.root == root, !paths.isEmpty else { throw VaultFailure(message: "Choose deleted notes to review.") }
        guard snapshot.problems.isEmpty, snapshot.pending.isEmpty else { throw VaultFailure(message: "Revision records need recovery or repair before permanent note cleanup. Their files are preserved.") }
        let current = try revisionTrashSnapshot()
        let expected = Dictionary(uniqueKeysWithValues: snapshot.notes.map { ($0.path, $0.content) })
        guard Dictionary(uniqueKeysWithValues: current.notes.map { ($0.path, $0.content) }) == expected,
              current.problems.isEmpty, current.pending.isEmpty,
              current.indexes.mapValues(\.bytes) == snapshot.indexes.mapValues(\.bytes) else {
            throw VaultFailure(message: "Notes or revisions changed. Reload Recently Deleted before reviewing cleanup.")
        }
        let deleted = snapshot.notes.filter { paths.contains($0.path) }.sorted { $0.path < $1.path }
        guard deleted.count == paths.count, deleted.allSatisfy(\.trashed) else { throw VaultFailure(message: "Only notes in Recently Deleted can be permanently removed.") }
        let identities = Set(deleted.compactMap(\.stableID))
        guard identities.allSatisfy(NativeHistory.identity), !snapshot.notes.contains(where: { !paths.contains($0.path) && $0.stableID.map(identities.contains) == true }) else {
            throw VaultFailure(message: "A note identity is invalid or shared with another note. Resolve it before deleting its revisions or history.")
        }
        var changes = snapshot.notes.map { note -> VaultFileChange in
            let bytes = Data(note.content.utf8)
            return .init(path: note.path, before: bytes, after: paths.contains(note.path) ? nil : bytes)
        }
        let revisionFiles = try Self.noteTrashRevisionFiles(root: root, identities: identities)
        var candidates = revisionFiles, removedRevisions = 0
        for note in deleted {
            if let hub = note.fileHub, hub.kind == .vault, hub.managed, let path = hub.path { candidates.insert(path) }
            if case .list(let rows) = NativeFrontmatter(note.content).entry("zerus-attachments")?.value {
                for row in rows {
                    if let value = try? JSONSerialization.jsonObject(with: Data(row.utf8)) as? [String: Any], value["kind"] as? String == "vault", NativeRevisions.boolean(value["managed"]) == true, let path = value["path"] as? String, NativeRevisionIndex.validPath(path) { candidates.insert(path) }
                }
            }
        }
        for (path, index) in snapshot.indexes where identities.contains(index.noteID) {
            changes.append(.init(path: path, before: index.bytes, after: nil))
            candidates.formUnion(index.object["ownedFiles"] as? [String] ?? [])
            removedRevisions += index.revisions.count
        }
        var history = try noteTrashHistorySnapshot(notes: current.notes, identities: identities)
        // Note/version deletion needs no unrelated file contents. Inspect the
        // wider vault only when shared resources might actually be removed.
        if !candidates.isEmpty || !noteTrashHistoryImages(history, identities: identities).isEmpty {
            history = try historyMaintenanceSnapshot(includeVersions: false)
            guard Dictionary(uniqueKeysWithValues: history.notes.map { ($0.path, $0.content) }) == expected else { throw VaultFailure(message: "Notes changed. Reload the cleanup review.") }
        }
        let records = history.records.keys.filter { path in identities.contains(path.components(separatedBy: "/")[3]) }
        for path in records { changes.append(.init(path: path, before: history.records[path], after: nil)) }
        let known = Set(changes.filter { $0.after == nil }.map(\.path))
        var references: [String] = [], linked = Set<String>()
        var canCollect = history.inventory.unexpected.isEmpty, warnings: [String] = []
        if !candidates.isEmpty {
            for (path, bytes) in history.records.merging(history.metadata, uniquingKeysWith: { a, _ in a }) where !known.contains(path) {
                guard let object = try? JSONSerialization.jsonObject(with: bytes), let values = try? Self.retentionStrings(object) else { canCollect = false; continue }
                references += values
            }
            for bytes in history.localDrafts.values {
                guard let object = try? JSONSerialization.jsonObject(with: bytes), let values = try? Self.retentionStrings(object) else { canCollect = false; continue }
                references += values
            }
            for note in snapshot.notes where !paths.contains(note.path) {
                try Task.checkCancellation()
                references += try Self.retentionStrings(note.content)
                for link in try MarkdownMoveLinks.links(in: note.parts.body) {
                    if case .wiki = link.kind { continue }
                    if let location = try? resolveResource(link.value, notePath: note.path) {
                        let resolved = try Self.confinedPath(for: location, root: root)
                        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
                        if resolved.hasPrefix(resolvedRoot) { linked.insert(String(resolved.dropFirst(resolvedRoot.count))) }
                    }
                }
            }
        }
        var removed: [String] = [], retained: [String] = []
        let notePaths = Set(snapshot.notes.map(\.path))
        let safeURI = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#%"))
        for path in candidates.sorted() {
            try Task.checkCancellation()
            guard NativeRevisionIndex.validPath(path), !notePaths.contains(path) else { continue }
            let hidden = path.split(separator: "/").contains { $0.hasPrefix(".") }
            guard !hidden || path.hasPrefix(".zerus/files/") || revisionFiles.contains(path) else { continue }
            let location = try url(for: path)
            guard FileManager.default.fileExists(atPath: location.path) else { continue }
            let values = try location.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { retained.append(path); continue }
            guard canCollect, !linked.contains(path), !references.contains(where: { $0.contains(path) || $0.contains(path.addingPercentEncoding(withAllowedCharacters: safeURI) ?? path) }) else { retained.append(path); continue }
            changes.append(.init(path: path, before: try read(path), after: nil)); removed.append(path)
        }
        if !canCollect { warnings.append("Unrecognized metadata keeps managed files protected. Note files and their listed versions can still be deleted.") }
        // Only images owned by the selected note histories participate in this
        // review. Scanning every vault blob first is quadratic on large vaults.
        let historyImages = noteTrashHistoryImages(history, identities: identities)
        let cleanup = try historyBlobCleanup(changes, snapshot: history, blobCandidates: historyImages)
        warnings += cleanup.warnings
        warnings.append("External original files, ordinary inline attachments, and existing recovery or action history copies are kept.")
        return .init(snapshot: snapshot, history: history, deleted: deleted, identities: identities, changes: cleanup.changes, revisionFiles: revisionFiles, removedRevisions: removedRevisions, removedHistory: records.count, removedFiles: (removed + cleanup.removed).sorted(), retainedFiles: retained, warnings: Array(Set(warnings)).sorted())
    }

    func applyNoteTrashPurge(_ plan: NativeNoteTrashPlan) throws -> VaultSnapshot {
        guard root == plan.snapshot.root else { throw VaultFailure(message: "The vault changed. Reload the note cleanup.") }
        let root = root, identities = plan.identities, files = plan.revisionFiles
        try applyTransaction(plan.changes, historyCleanupSnapshot: plan.history, validate: {
            guard try Self.noteTrashRevisionFiles(root: root, identities: identities) == files else { throw VaultFailure(message: "Revision files changed after this review. Reload it before deleting anything.") }
        })
        for id in identities { forgetExternalHistory(.clearNote(id)) }
        return try scan()
    }
}
