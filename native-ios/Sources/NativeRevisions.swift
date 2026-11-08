import Foundation

struct NativeNoteRevision: Identifiable, Sendable {
    let id: String
    let number: Int
    let createdAt: String
    let content: String
    let deletedAt: String?
    var date: Date? { NativeRevisionIndex.date(createdAt) }
}

/// Keep foreign fields in the shared JSON format when changing known fields.
struct NativeRevisionIndex: Sendable {
    let bytes: Data
    let noteID: String
    let currentID: String
    let nextNumber: Int
    let revisions: [NativeNoteRevision]
    var object: [String: Any] { (try! JSONSerialization.jsonObject(with: bytes)) as! [String: Any] }
    static func date(_ value: String) -> Date? {
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func timestamp(_ date: Date = Date()) -> String {
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: date)
    }
    init(_ bytes: Data, noteID: String) throws {
        func invalid() -> VaultFailure { VaultFailure(message: "This note’s revision data is incomplete or unsupported. Its original files are preserved.") }
        guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let schema = value["schema"] as? NSNumber, CFGetTypeID(schema) != CFBooleanGetTypeID(), schema.intValue == 1, schema.doubleValue == 1,
              value["noteId"] as? String == noteID,
              let current = value["currentId"] as? String,
              let number = value["nextNumber"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == Double(number.intValue), number.intValue >= 2, number.intValue < Int.max,
              let rows = value["revisions"] as? [[String: Any]] else { throw invalid() }
        var revisions: [NativeNoteRevision] = []
        for row in rows {
            guard let id = row["id"] as? String, !id.isEmpty,
                  let n = row["number"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == Double(n.intValue), n.intValue > 0, n.intValue < number.intValue,
                  let created = row["createdAt"] as? String, Self.date(created) != nil,
                  let content = row["content"] as? String,
                  row["deletedAt"] == nil || (row["deletedAt"] as? String).flatMap(Self.date) != nil else { throw invalid() }
            revisions.append(.init(id: id, number: n.intValue, createdAt: created, content: content, deletedAt: row["deletedAt"] as? String))
        }
        guard Set(revisions.map(\.id)).count == rows.count, Set(revisions.map(\.number)).count == rows.count,
              revisions.contains(where: { $0.id == current && $0.deletedAt == nil }),
              value["commitToken"] == nil || value["commitToken"] is String else { throw invalid() }
        if let files = value["ownedFiles"] {
            guard let paths = files as? [String], paths.allSatisfy({ Self.validPath($0) }) else { throw invalid() }
        }
        self.bytes = bytes; self.noteID = noteID; currentID = current; nextNumber = number.intValue; self.revisions = revisions
    }
    static func validPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") &&
        !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) &&
        path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil
    }
}

enum NativeRevisionAction: Sendable {
    case create, promote(String), trash(String), restore(String)
    var target: String? { switch self { case .create: nil; case .promote(let id), .trash(let id), .restore(let id): id } }
}

struct NativeRevisionSnapshot: Sendable {
    let root: URL
    var workspaceID: UUID?
    let note: NoteDocument
    let index: NativeRevisionIndex
    let indexBytes: Data?
    var indexPath: String { ".zerus/revisions/notes/" + index.noteID + "/index.json" }
    func content(for revision: NativeNoteRevision) throws -> String {
        if revision.id == index.currentID { return note.content }
        return try NativeRevisions.content(revision.content, in: note)
    }
}

struct NativeRevisionPlan: Sendable {
    let snapshot: NativeRevisionSnapshot
    let changes: [VaultFileChange]
    let next: NativeRevisionIndex
    let content: String
    let resourceBindings: [NativeMoveResourceBinding]
    var copiedFiles: Int { changes.filter { $0.path.contains("/files/") && $0.before == nil && $0.after != nil }.count }
}

enum NativeRevisions {
    static let tokenKey = "zerus-revision-transaction"
    static let fileKeys = ["zerus-file-id", "zerus-file-name", "zerus-file-kind", "zerus-file-location", "zerus-file-path", "zerus-file-managed", "zerus-attachments"]
    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    static func content(_ frozen: String, in note: NoteDocument) throws -> String {
        var body = NoteDocument.split(frozen).body
        let pattern = #"^\s*\S[^\r\n]*"#
        let current = note.parts.body as NSString
        let regex = try NSRegularExpression(pattern: pattern)
        if let title = regex.firstMatch(in: note.parts.body, range: NSRange(location: 0, length: current.length)) {
            let line = current.substring(with: title.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let original = body as NSString
            if let first = regex.firstMatch(in: body, range: NSRange(location: 0, length: original.length)) { body = original.replacingCharacters(in: first.range, with: line) }
            else { body = line + "\n\n" + body }
        }
        var content = note.replacingBody(body)
        let stored = NativeFrontmatter(frozen)
        for key in fileKeys {
            let entry = stored.entry(key)
            if let entry, entry.value == nil { throw VaultFailure(message: "A revision has unsupported file metadata. Its original data is preserved.") }
            content = try NativeFrontmatter(content).setting(key, value: entry?.value)
        }
        return content
    }
}

extension VaultFiles {
    private func revisionData(_ path: String) throws -> Data? {
        let location = try url(for: path)
        return FileManager.default.fileExists(atPath: location.path) ? try read(path) : nil
    }
    private func recoverWebRevision(note: NoteDocument, noteID: String) throws {
        let directory = ".zerus/revisions/notes/" + noteID
        let pendingPath = directory + "/pending.json", indexPath = directory + "/index.json"
        guard let pendingBytes = try revisionData(pendingPath) else { return }
        guard let pending = try JSONSerialization.jsonObject(with: pendingBytes) as? [String: Any],
              let token = pending["token"] as? String, !token.isEmpty,
              let before = pending["before"] as? String, let after = pending["after"] as? String,
              let previous = pending["previous"] as? [String: Any], let next = pending["next"] as? [String: Any] else {
            throw VaultFailure(message: "An unsupported interrupted revision was preserved. Resolve its pending.json before changing revisions.")
        }
        let previousBytes = try JSONSerialization.data(withJSONObject: previous), nextBytes = try JSONSerialization.data(withJSONObject: next)
        _ = try NativeRevisionIndex(previousBytes, noteID: noteID)
        let nextIndex = try NativeRevisionIndex(nextBytes, noteID: noteID)
        guard nextIndex.object["commitToken"] as? String == token,
              NoteDocument(path: note.path, content: after, modified: note.modified).property(NativeRevisions.tokenKey) == token else {
            throw VaultFailure(message: "The interrupted revision has mismatched commit identities. Its original files are preserved.")
        }
        let intended: Data
        if note.property(NativeRevisions.tokenKey) == token { intended = nextBytes }
        else if note.content == before { intended = previousBytes }
        else { throw VaultFailure(message: "An interrupted revision conflicts with an outside edit. The note, index and pending record are kept unchanged.") }
        try applyTransaction([
            .init(path: note.path, before: Data(note.content.utf8), after: Data(note.content.utf8)),
            .init(path: indexPath, before: try revisionData(indexPath), after: intended),
            .init(path: pendingPath, before: pendingBytes, after: nil)
        ])
    }
    func revisionSnapshot(notePath: String) throws -> NativeRevisionSnapshot {
        try recoverTransactions()
        let bytes = try read(notePath)
        guard let content = String(data: bytes, encoding: .utf8) else { throw VaultFailure(message: "The note is not UTF-8 Markdown.") }
        let location = try url(for: notePath)
        let note = NoteDocument(path: notePath, content: content, modified: (try? location.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date())
        let id = note.stableID ?? UUID().uuidString.lowercased()
        guard id.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else { throw VaultFailure(message: "The note has an unsupported revision identity. Its original data is preserved.") }
        if note.stableID != nil { try recoverWebRevision(note: note, noteID: id) }
        let indexPath = ".zerus/revisions/notes/" + id + "/index.json"
        let stored = try revisionData(indexPath)
        let index: NativeRevisionIndex
        if let stored {
            index = try NativeRevisionIndex(stored, noteID: id)
            if let token = index.object["commitToken"] as? String, token != note.property(NativeRevisions.tokenKey) {
                throw VaultFailure(message: "The note and its revisions are still syncing. Wait for both files, then retry.")
            }
        } else {
            guard note.property(NativeRevisions.tokenKey) == nil else { throw VaultFailure(message: "This note’s revision folder has not arrived. Sync or restore .zerus/revisions, then retry.") }
            index = try NativeRevisionIndex(JSONSerialization.data(withJSONObject: ["schema": 1, "noteId": id, "currentId": "initial", "nextNumber": 2, "revisions": [["id": "initial", "number": 1, "createdAt": NativeRevisionIndex.timestamp(note.modified), "content": note.content]]]), noteID: id)
        }
        return NativeRevisionSnapshot(root: root, note: note, index: index, indexBytes: stored)
    }

    func prepareRevision(_ snapshot: NativeRevisionSnapshot, action: NativeRevisionAction) throws -> NativeRevisionPlan {
        guard snapshot.root == root, !snapshot.note.trashed else { throw VaultFailure(message: "Restore this note from Trash before changing revisions.") }
        let id = snapshot.index.noteID
        let live = try scan().notes
        guard !live.contains(where: { $0.path != snapshot.note.path && $0.stableID == id }) else { throw VaultFailure(message: "More than one note has this identity. Resolve the duplicate before changing revisions.") }
        guard try read(snapshot.note.path) == Data(snapshot.note.content.utf8), try revisionData(snapshot.indexPath) == snapshot.indexBytes else { throw VaultFailure(message: "The note or its revisions changed. Reload before trying again.") }
        guard try revisionData(".zerus/revisions/notes/" + id + "/pending.json") == nil else { throw VaultFailure(message: "An interrupted revision needs recovery. Reload revisions first.") }
        var object = snapshot.index.object, rows = object["revisions"] as! [[String: Any]]
        let current = rows.firstIndex { $0["id"] as? String == snapshot.index.currentID }!
        guard let target = rows.firstIndex(where: { $0["id"] as? String == (action.target ?? snapshot.index.currentID) }) else { throw VaultFailure(message: "This revision is no longer available.") }
        var content = try snapshot.note.setting("zerus-id", to: id)
        var dependencies: [String: Data] = [:], copies: [String: Data] = [:], bindings: [NativeMoveResourceBinding] = []
        var owned = Set(object["ownedFiles"] as? [String] ?? [])
        if snapshot.note.property("zerus-file-kind") == "vault", NativeFrontmatter(snapshot.note.content).entry("zerus-file-managed")?.value == .checkbox(true), let path = snapshot.note.property("zerus-file-path"), NativeRevisionIndex.validPath(path) { owned.insert(path) }
        if case .list(let values) = NativeFrontmatter(snapshot.note.content).entry("zerus-attachments")?.value {
            for value in values {
                if let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any], object["kind"] as? String == "vault", NativeRevisions.boolean(object["managed"]) == true, let path = object["path"] as? String, NativeRevisionIndex.validPath(path) { owned.insert(path) }
            }
        }
        func freeze(_ original: String) throws -> String {
            var next = original, copied: [String: String] = [:]
            let directory = ".zerus/revisions/notes/" + id + "/files/" + UUID().uuidString.lowercased()
            func copy(_ reference: String, metadata: Bool = false) throws -> String {
                let source: String
                if metadata { guard NativeRevisionIndex.validPath(reference) else { throw VaultFailure(message: "A linked file is outside the vault.") }; source = reference }
                else if let parsed = URL(string: reference), copies[parsed.relativePath] != nil { source = parsed.relativePath }
                else {
                    let location: URL
                    do { location = try resolveResource(reference, notePath: snapshot.note.path) }
                    catch { throw VaultFailure(message: "Cannot preserve ‘\(reference)’. Restore the linked file before creating this revision.") }
                    source = String(location.path.dropFirst(root.standardizedFileURL.path.count + 1))
                    bindings.append(.init(notePath: snapshot.note.path, reference: reference, resolved: try Self.confinedPath(for: location, root: root)))
                }
                if let existing = copied[source] { return existing }
                let bytes: Data
                if let staged = copies[source] { bytes = staged }
                else { bytes = try read(source); dependencies[source] = bytes }
                let originalName = (source as NSString).lastPathComponent.replacingOccurrences(of: #"^(?:\d+-)+"#, with: "", options: .regularExpression)
                let clean = originalName.replacingOccurrences(of: #"[^a-zA-Z0-9._-]"#, with: "_", options: .regularExpression)
                let destination = directory + "/\(copied.count)-" + clean
                copies[destination] = bytes; copied[source] = destination; return destination
            }
            let props = NativeFrontmatter(next)
            for key in NativeRevisions.fileKeys where props.entry(key) != nil && props.entry(key)?.value == nil {
                throw VaultFailure(message: "The revision uses complex or duplicate file metadata. Its original data is preserved.")
            }
            if let kind = props.entry("zerus-file-kind")?.value?.display {
                guard kind == "vault", let path = props.entry("zerus-file-path")?.value?.display else { throw VaultFailure(message: "Copy linked external files into the vault before creating a revision.") }
                if props.entry("zerus-file-managed")?.value == .checkbox(true) { owned.insert(path) }
                next = try NativeFrontmatter(next).setting("zerus-file-path", value: .text(copy(path, metadata: true)))
                next = try NativeFrontmatter(next).setting("zerus-file-managed", value: nil)
            }
            if let entry = props.entry("zerus-attachments") {
                guard case .list(let values) = entry.value else { throw VaultFailure(message: "The attachment metadata is unsupported. Its original data is preserved.") }
                var saved: [String] = []
                for value in values {
                    guard let data = value.data(using: .utf8), var item = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          item["kind"] as? String == "vault", let path = item["path"] as? String,
                          item["id"] is String, item["name"] is String, NativeRevisions.boolean(item["managed"]) != nil else { throw VaultFailure(message: "The attachment metadata is unsupported or refers to an external file. Copy external files into the vault before creating a revision.") }
                    if NativeRevisions.boolean(item["managed"]) == true { owned.insert(path) }
                    item["path"] = try copy(path, metadata: true); item["managed"] = false
                    saved.append(String(decoding: try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self))
                }
                next = try NativeFrontmatter(next).setting("zerus-attachments", value: saved.isEmpty ? nil : .list(saved))
            }
            let body = NoteDocument.split(next).body
            var edits: [(MarkdownMoveLinks.Link, String)] = []
            for link in try MarkdownMoveLinks.links(in: body) {
                if case .wiki = link.kind { continue }
                guard let url = URL(string: link.value) else { throw VaultFailure(message: "An attachment link is invalid: \(link.value)") }
                if let scheme = url.scheme {
                    guard scheme.lowercased() != "file", link.value.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) == nil else { throw VaultFailure(message: "Copy external files into the vault before creating a revision.") }
                    continue
                }
                if link.value.hasPrefix("//") || link.value.hasPrefix("#") { continue }
                guard !url.relativePath.hasPrefix("/") else { throw VaultFailure(message: "Use a vault-relative attachment link before creating a revision.") }
                if ["md", "markdown"].contains(url.pathExtension.lowercased()) { continue }
                guard !url.relativePath.isEmpty else { continue }
                edits.append((link, MarkdownResources.encodedPath(try copy(link.value), preservingSuffixOf: link.value)))
            }
            return NoteDocument(path: snapshot.note.path, content: next, modified: Date()).replacingBody(MarkdownMoveLinks.replacing(body, edits: edits))
        }
        switch action {
        case .create, .promote:
            guard rows[target]["deletedAt"] == nil else { throw VaultFailure(message: "Restore this revision from Trash first.") }
            rows[current]["content"] = try freeze(content)
            let source = action.target == nil ? current : target
            content = try freeze(NativeRevisions.content(rows[source]["content"] as! String, in: NoteDocument(path: snapshot.note.path, content: content, modified: Date())))
            let newID = UUID().uuidString.lowercased()
            rows.append(["id": newID, "number": snapshot.index.nextNumber, "createdAt": NativeRevisionIndex.timestamp(), "content": content])
            object["nextNumber"] = snapshot.index.nextNumber + 1; object["currentId"] = newID
        case .trash:
            guard rows[target]["deletedAt"] == nil else { throw VaultFailure(message: "This revision is already in Trash.") }
            let remaining = rows.indices.filter { $0 != target && rows[$0]["deletedAt"] == nil }
            guard let latest = remaining.max(by: { (rows[$0]["number"] as! Int) < (rows[$1]["number"] as! Int) }) else { throw VaultFailure(message: "This is the only revision. Move the whole note to Trash instead.") }
            if target == current {
                rows[current]["content"] = try freeze(content)
                content = try freeze(NativeRevisions.content(rows[latest]["content"] as! String, in: NoteDocument(path: snapshot.note.path, content: content, modified: Date())))
                object["currentId"] = rows[latest]["id"]
            }
            rows[target]["deletedAt"] = NativeRevisionIndex.timestamp()
        case .restore:
            guard rows[target]["deletedAt"] != nil else { throw VaultFailure(message: "This revision is not in Trash.") }
            rows[target].removeValue(forKey: "deletedAt")
        }
        let token = UUID().uuidString.lowercased()
        content = try NativeFrontmatter(content).setting(NativeRevisions.tokenKey, value: .text(token))
        object["commitToken"] = token; object["revisions"] = rows; object["ownedFiles"] = owned.sorted()
        let next = try NativeRevisionIndex(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), noteID: id)
        // Publish frozen files before either live pointer refers to them, as in
        // the shared web commit. The journal still owns the whole batch.
        var changes = copies.sorted { $0.key < $1.key }.map { VaultFileChange(path: $0.key, before: nil, after: $0.value) }
        changes += dependencies.sorted { $0.key < $1.key }.map { .init(path: $0.key, before: $0.value, after: $0.value) }
        changes += [.init(path: snapshot.note.path, before: Data(snapshot.note.content.utf8), after: Data(content.utf8)), .init(path: snapshot.indexPath, before: snapshot.indexBytes, after: next.bytes)]
        changes.append(.init(path: ".zerus/revisions/notes/" + id + "/pending.json", before: nil, after: nil))
        return NativeRevisionPlan(snapshot: snapshot, changes: changes, next: next, content: content, resourceBindings: bindings)
    }
    func applyRevision(_ plan: NativeRevisionPlan) throws -> VaultSnapshot {
        guard root == plan.snapshot.root else { throw VaultFailure(message: "The vault changed. Reopen revisions.") }
        let current = try scan().notes, id = plan.snapshot.index.noteID
        guard !current.contains(where: { $0.path != plan.snapshot.note.path && $0.stableID == id }) else { throw VaultFailure(message: "Another note now has this revision identity. Resolve the duplicate before continuing.") }
        let bindings = plan.resourceBindings, originalRoot = root
        var locations: [URL] = [], seen = Set<String>()
        for binding in bindings {
            for location in try Self.resourceCandidates(binding.reference, notePath: binding.notePath, root: root) where seen.insert(location.path).inserted { locations.append(location) }
        }
        try applyTransaction(plan.changes, reading: locations) {
            for binding in bindings where NativeMoveResourceBinding.path(binding.reference, notePath: binding.notePath, root: originalRoot) != binding.resolved {
                throw VaultFailure(message: "A linked file changed while this revision was being reviewed. Reload the revision before saving.")
            }
        }
        return try scan()
    }
}
