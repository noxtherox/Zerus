import Foundation

struct NativeTrashedRevision: Identifiable, Sendable {
    let noteID: String
    let revision: NativeNoteRevision
    let note: NoteDocument?
    var id: String { noteID + ":" + revision.id }
    var title: String { (note?.title ?? NoteDocument(path: "Note.md", content: revision.content, modified: .distantPast).title) + " · Revision \(revision.number)" }
}

struct NativeRevisionTrashSnapshot: Sendable {
    let root: URL
    var workspaceID: UUID?
    let notes: [NoteDocument]
    let indexes: [String: NativeRevisionIndex]
    let problems: [String]
    let pending: [String]
    var entries: [NativeTrashedRevision] {
        indexes.values.flatMap { index -> [NativeTrashedRevision] in
            let matches = notes.filter { $0.stableID == index.noteID }
            // A trashed note carries its revisions as a group.
            if matches.contains(where: \.trashed) { return [] }
            let note = matches.count == 1 ? matches.first : nil
            return index.revisions.filter { $0.deletedAt != nil }.map { .init(noteID: index.noteID, revision: $0, note: note) }
        }.sorted { ($0.revision.deletedAt ?? "") > ($1.revision.deletedAt ?? "") }
    }
}

struct NativeRevisionTrashPlan: Sendable {
    let snapshot: NativeRevisionTrashSnapshot
    let changes: [VaultFileChange]
    let deleted: [NativeTrashedRevision]
    let removedFiles: [String]
    let indexPaths: Set<String>
    var removedBytes: Int { changes.filter { $0.after == nil && $0.before != nil }.reduce(0) { $0 + ($1.before?.count ?? 0) } }
}

extension VaultFiles {
    nonisolated static func retentionStrings(_ value: Any, depth: Int = 0) throws -> [String] {
        guard depth < 64 else { throw VaultFailure(message: "A revision record has deeply nested metadata. Its files are preserved; cleanup was canceled.") }
        if let object = value as? [String: Any] { return try object.values.flatMap { try retentionStrings($0, depth: depth + 1) } }
        if let array = value as? [Any] { return try array.flatMap { try retentionStrings($0, depth: depth + 1) } }
        guard let text = value as? String else { return [] }
        var result = [text, text.replacingOccurrences(of: "\\/", with: "/"), text.removingPercentEncoding ?? text]
        // YAML quoted strings and serialized attachment records can escape
        // slashes. Inspect their decoded values before deciding a file is unused.
        if let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)), json is [String: Any] || json is [Any] {
            result += try retentionStrings(json, depth: depth + 1)
        }
        // Recovery records encode saved UTF-8 JSON/Markdown as base64.
        if text.count >= 8, let bytes = Data(base64Encoded: text), let decoded = String(data: bytes, encoding: .utf8), decoded != text {
            result += try retentionStrings(decoded, depth: depth + 1)
        }
        let header = NativeFrontmatter(text)
        for entry in header.entries {
            if let value = entry.value {
                for item in value.selections { result += try retentionStrings(item, depth: depth + 1) }
            }
        }
        return result
    }
    private func revisionDirectories() throws -> [String] {
        let directory = try url(for: ".zerus/revisions/notes")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).compactMap { location in
            let values = try location.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return ".zerus/revisions/notes/" + location.lastPathComponent
        }.sorted()
    }
    private func revisionIndexInventory() throws -> Set<String> {
        var paths = Set<String>()
        for directory in try revisionDirectories() {
            for name in ["index.json", "pending.json"] {
                let path = directory + "/" + name
                if FileManager.default.fileExists(atPath: try url(for: path).path) { paths.insert(path) }
            }
        }
        return paths
    }
    func revisionTrashSnapshot() throws -> NativeRevisionTrashSnapshot {
        let notes = try scan().notes
        var indexes: [String: NativeRevisionIndex] = [:], problems: [String] = [], pending: [String] = []
        for directory in try revisionDirectories() {
            let id = (directory as NSString).lastPathComponent
            guard id.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else {
                problems.append("An unsupported revision folder was preserved: \(directory)"); continue
            }
            let indexPath = directory + "/index.json", pendingPath = directory + "/pending.json"
            if FileManager.default.fileExists(atPath: try url(for: pendingPath).path) { pending.append(pendingPath) }
            guard FileManager.default.fileExists(atPath: try url(for: indexPath).path) else { continue }
            do {
                let index = try NativeRevisionIndex(read(indexPath), noteID: id)
                indexes[indexPath] = index
                let matches = notes.filter { $0.stableID == id }
                if matches.count > 1 { problems.append("More than one note uses revision identity \(id). Resolve the duplicate before cleanup.") }
                if let note = matches.first, let token = index.object["commitToken"] as? String, token != note.property(NativeRevisions.tokenKey) {
                    problems.append("\(note.title) and its revision index are still syncing. Wait for both files, then reload.")
                }
            }
            catch { problems.append("\(indexPath): \(error.localizedDescription)") }
        }
        return .init(root: root, notes: notes, indexes: indexes, problems: problems, pending: pending)
    }

    func prepareRevisionTrashPurge(_ snapshot: NativeRevisionTrashSnapshot) throws -> NativeRevisionTrashPlan {
        guard snapshot.root == root else { throw VaultFailure(message: "The vault changed. Reload Recently Deleted.") }
        guard snapshot.problems.isEmpty else { throw VaultFailure(message: "Some revision records are unsupported. Restore or repair them before permanent cleanup; every original file is kept.") }
        guard snapshot.pending.isEmpty else { throw VaultFailure(message: "An interrupted revision needs recovery. Open that note’s revisions before permanent cleanup.") }
        let current = try revisionTrashSnapshot()
        guard current.problems.isEmpty, current.pending.isEmpty, Set(current.indexes.keys) == Set(snapshot.indexes.keys), current.notes.map(\.path).sorted() == snapshot.notes.map(\.path).sorted() else {
            throw VaultFailure(message: "The vault changed. Reload Recently Deleted before reviewing cleanup.")
        }
        let inventory = Set(snapshot.indexes.keys)
        guard try revisionIndexInventory() == inventory else { throw VaultFailure(message: "Revision records changed. Reload Recently Deleted before cleanup.") }
        let entries = snapshot.entries
        guard !entries.isEmpty else { throw VaultFailure(message: "There are no discarded revisions to delete.") }
        let discarded = Set(entries.map(\.id))
        var retained = try snapshot.notes.flatMap { try Self.retentionStrings($0.content) }, candidates = Set<String>(), changes: [VaultFileChange] = []
        for (path, index) in snapshot.indexes.sorted(by: { $0.key < $1.key }) {
            var object = index.object
            let rows = object["revisions"] as! [[String: Any]]
            let remaining = rows.filter { !discarded.contains(index.noteID + ":" + ($0["id"] as! String)) }
            object["revisions"] = remaining
            let after = try NativeRevisionIndex(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), noteID: index.noteID)
            // Unchanged manifests are also coordinated read dependencies.
            changes.append(.init(path: path, before: index.bytes, after: remaining.count == rows.count ? index.bytes : after.bytes))
            candidates.formUnion(object["ownedFiles"] as? [String] ?? [])
            let folder = try url(for: (path as NSString).deletingLastPathComponent + "/files")
            if FileManager.default.fileExists(atPath: folder.path) {
                guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { throw VaultFailure(message: "Could not inspect revision files before cleanup.") }
                while let file = files.nextObject() as? URL {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values.isSymbolicLink == true { files.skipDescendants(); continue }
                    if values.isRegularFile == true { candidates.insert(String(file.path.dropFirst(root.standardizedFileURL.path.count + 1))) }
                }
            }
            // Ownership bookkeeping is not a live reference. Retain unknown
            // fields, and keep orphaned current versions available for recovery.
            var references = object; references.removeValue(forKey: "ownedFiles")
            let hasLiveNote = snapshot.notes.contains { $0.stableID == index.noteID }
            references["revisions"] = remaining.map { row -> [String: Any] in
                var row = row
                if hasLiveNote && row["id"] as? String == index.currentID { row.removeValue(forKey: "content") }
                return row
            }
            retained += try Self.retentionStrings(references)
        }
        var linked = Set<String>()
        // Resolve ordinary note-relative links as well as globally anchored
        // revision paths. Literal references are kept conservatively above.
        let prefix = root.standardizedFileURL.path + "/"
        for note in snapshot.notes {
            changes.append(.init(path: note.path, before: Data(note.content.utf8), after: Data(note.content.utf8)))
            for link in try MarkdownMoveLinks.links(in: note.parts.body) {
                if case .wiki = link.kind { continue }
                if let file = try? resolveResource(link.value, notePath: note.path) { linked.insert(String(file.path.dropFirst(prefix.count))) }
            }
        }
        var removed: [String] = []
        let safeURI = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#%"))
        for path in candidates.sorted() {
            guard NativeRevisionIndex.validPath(path), !["md", "markdown"].contains((path as NSString).pathExtension.lowercased()) else { continue }
            let managedHidden = path.hasPrefix(".zerus/files/") || path.range(of: #"^\.zerus/revisions/notes/[A-Za-z0-9_-]{1,128}/files/.+"#, options: .regularExpression) != nil
            guard !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) || managedHidden else { continue }
            guard !linked.contains(path), !retained.contains(where: { $0.contains(path) || $0.contains(path.addingPercentEncoding(withAllowedCharacters: safeURI) ?? path) }) else { continue }
            let location = try url(for: path)
            guard FileManager.default.fileExists(atPath: location.path) else { continue }
            let values = try location.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            changes.append(.init(path: path, before: try read(path), after: nil)); removed.append(path)
        }
        return .init(snapshot: snapshot, changes: changes, deleted: entries, removedFiles: removed, indexPaths: inventory)
    }

    func applyRevisionTrashPurge(_ plan: NativeRevisionTrashPlan) throws -> VaultSnapshot {
        guard root == plan.snapshot.root else { throw VaultFailure(message: "The vault changed. Reload Recently Deleted.") }
        let current = try scan()
        guard Set(current.notes.map(\.path)) == Set(plan.snapshot.notes.map(\.path)), try revisionIndexInventory() == plan.indexPaths else {
            throw VaultFailure(message: "Notes or revisions were added or moved after this review. Reload it before deleting anything.")
        }
        try applyTransaction(plan.changes)
        return try scan()
    }
}
