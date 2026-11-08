import Foundation
import Markdown

/// An occurrence, rather than a filename: deleting one of two identical images
/// must not delete the other image or reserialize the surrounding Markdown.
struct NativeInlineImage: Identifiable, Sendable {
    let range: NSRange
    let imageRange: NSRange
    let markdown: String
    let reference: String
    let caption: String
    let title: String?
    var id: String { "\(range.location):\(range.length)" }

    static func occurrences(in source: String) -> [Self] {
        let text = source as NSString
        var lines: [NSRange] = [], position = 0
        while position < text.length {
            let line = text.lineRange(for: NSRange(location: position, length: 0)); lines.append(line); position = NSMaxRange(line)
        }
        func range(_ origin: SourceRange?, offset: Int) -> NSRange? {
            guard let origin else { return nil }
            func index(_ location: SourceLocation) -> Int? {
                let line = location.line + offset - 1
                guard lines.indices.contains(line) else { return nil }
                var bytes = 0, units = 0
                for scalar in text.substring(with: lines[line]).unicodeScalars {
                    if bytes >= location.column - 1 { break }
                    bytes += scalar.utf8.count; units += scalar.utf16.count
                }
                return min(NSMaxRange(lines[line]), lines[line].location + units)
            }
            guard let start = index(origin.lowerBound), let end = index(origin.upperBound), end >= start else { return nil }
            return NSRange(location: start, length: end - start)
        }
        var result: [Self] = []
        func visit(_ node: any Markup, offset: Int = 0, enclosing: NSRange? = nil) {
            if node is CodeBlock || node is InlineCode || node is HTMLBlock || node is InlineHTML { return }
            if let image = node as? Markdown.Image, let imageRange = range(node.range, offset: offset), let reference = image.source {
                let selected = enclosing ?? imageRange, spelling = text.substring(with: selected)
                guard text.substring(with: imageRange).hasPrefix("!["), spelling.hasPrefix("![") || spelling.hasPrefix("[![") else { return }
                result.append(.init(range: selected, imageRange: imageRange, markdown: spelling, reference: reference, caption: image.plainText, title: image.title)); return
            }
            var childOffset = offset
            if node is Paragraph, let end = node.range?.upperBound.line, let inlineEnd = node.children.compactMap({ $0.range?.upperBound.line }).max() { childOffset += max(0, end - inlineEnd) }
            let outer = node is Markdown.Link && node.childCount == 1 && node.child(at: 0) is Markdown.Image ? range(node.range, offset: offset) : nil
            for child in node.children { visit(child, offset: childOffset, enclosing: outer) }
        }
        visit(Document(parsing: source))
        return result
    }
}

struct NativeTrashedImage: Identifiable, Sendable {
    let id: String
    let name: String
    let originalPath: String
    let trashPath: String
    let deletedAt: String
    let noteID: String?
    let markdown: String?
}
struct NativeImageTrashIndex: @unchecked Sendable {
    static let path = ".zerus/trashed-images.json"
    let bytes: Data?
    let objects: [[String: Any]]
    let entries: [NativeTrashedImage]
    init(_ bytes: Data?) throws {
        self.bytes = bytes
        guard let bytes else { objects = []; entries = []; return }
        guard let rows = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] else { throw VaultFailure(message: "The deleted-image index is unsupported. Its original data is preserved.") }
        var entries: [NativeTrashedImage] = [], identities = Set<String>(), paths = Set<String>()
        for row in rows {
            guard let id = row["id"] as? String, !id.isEmpty, identities.insert(id).inserted,
                  let name = row["name"] as? String, let original = row["originalPath"] as? String,
                  let path = row["trashPath"] as? String, path.hasPrefix(".trash/assets/"), Self.safePath(path), paths.insert(path).inserted,
                  let decoded = original.removingPercentEncoding, Self.safePath(decoded), !decoded.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
                  let date = row["deletedAt"] as? String, NativeRevisionIndex.date(date) != nil,
                  row["noteId"] == nil || row["noteId"] is String, row["markdown"] == nil || row["markdown"] is String else {
                throw VaultFailure(message: "A deleted-image record has an unsafe or unsupported path or identity. The index and files are preserved.")
            }
            entries.append(.init(id: id, name: name, originalPath: original, trashPath: path, deletedAt: date, noteID: row["noteId"] as? String, markdown: row["markdown"] as? String))
        }
        objects = rows; self.entries = entries
    }
    static func safePath(_ path: String) -> Bool {
        NativeRevisionIndex.validPath(path) && !path.contains("\\") && !path.contains(":") && !path.contains("?") && !path.contains("#") && !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) && !["md", "markdown"].contains((path as NSString).pathExtension.lowercased())
    }
    static func encode(_ objects: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) }
}
struct NativeImageSnapshot: Sendable {
    let history: NativeHistoryMaintenanceSnapshot
    var workspaceID: UUID?
    let index: NativeImageTrashIndex
    let markdown: [String: Data]
    let linkedPaths: Set<String>
    var root: URL { history.root }
}
enum NativeImageChange: Sendable { case remove(note: String, occurrence: NativeInlineImage), restore(id: String, reattach: Bool), purge(ids: Set<String>), undo }
struct NativeImagePlan: Sendable {
    let snapshot: NativeImageSnapshot
    let action: NativeImageChange
    let changes: [VaultFileChange]
    let title: String
    let explanation: String
    let files: [String]
    var permanent: Bool { if case .purge = action { return true }; return false }
}

extension VaultFiles {
    /// Include hidden saved Markdown as well as current and trashed notes. A
    /// linked child is never traversed or deleted, and prevents file collection.
    nonisolated static func imageMarkdownInventory(root: URL) throws -> (paths: Set<String>, linked: Set<String>) {
        var paths = Set<String>(), linked = Set<String>(), directories = [""]
        while let directory = directories.popLast() {
            let folder = root.appendingPathComponent(directory)
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]) {
                let path = directory.isEmpty ? file.lastPathComponent : directory + "/" + file.lastPathComponent
                let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { linked.insert(path); continue }
                if values.isDirectory == true {
                    if [".git", ".zerus/native-transactions", ".zerus/history/blobs"].contains(path) { continue }
                    directories.append(path)
                } else if values.isRegularFile == true, ["md", "markdown"].contains(file.pathExtension.lowercased()) { paths.insert(path) }
            }
        }
        return (paths, linked)
    }
    func imageSnapshot() throws -> NativeImageSnapshot {
        let history = try historyMaintenanceSnapshot()
        let inventory = try Self.imageMarkdownInventory(root: root)
        var markdown: [String: Data] = [:]
        var total = 0
        for path in inventory.paths {
            try Task.checkCancellation()
            let location = try url(for: path), size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10 * 1024 * 1024, total + size <= 128 * 1024 * 1024 else { throw VaultFailure(message: "This vault has large saved Markdown files. Image file changes are unavailable until those files can be checked safely.") }
            let bytes = try read(path); total += bytes.count
            guard bytes.count <= 10 * 1024 * 1024, total <= 128 * 1024 * 1024 else { throw VaultFailure(message: "Saved Markdown changed size. Reload Images.") }
            markdown[path] = bytes
        }
        let index = try NativeImageTrashIndex(history.metadata[NativeImageTrashIndex.path])
        return .init(history: history, index: index, markdown: markdown, linkedPaths: inventory.linked)
    }
    private func imagePathWithoutAliases(_ path: String) throws {
        guard NativeImageTrashIndex.safePath(path) else { throw VaultFailure(message: "This file path cannot be changed safely.") }
        var parent = root
        for part in path.split(separator: "/") {
            parent.appendPathComponent(String(part))
            if (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw VaultFailure(message: "Linked image files are preserved. Reconnect the original file before changing it.") }
        }
    }
    private func imageBytes(_ path: String) throws -> Data {
        try imagePathWithoutAliases(path)
        let location = try url(for: path), values = try location.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 50 * 1024 * 1024 else { throw VaultFailure(message: "This image is unavailable or exceeds the 50 MB file limit. The original is preserved.") }
        let bytes = try read(path)
        guard bytes.count <= 50 * 1024 * 1024 else { throw VaultFailure(message: "The image grew while reading. Reopen its review.") }
        return bytes
    }
    private func imageRelative(_ target: String, from note: String) -> String {
        let logical = note.hasPrefix(".trash/") ? String(note.dropFirst(7)) : note
        let base = logical.split(separator: "/").dropLast(), parts = target.split(separator: "/")
        var shared = 0
        while shared < min(base.count, parts.count), base[base.index(base.startIndex, offsetBy: shared)] == parts[shared] { shared += 1 }
        let relative = (Array(repeating: "..", count: base.count - shared) + parts.dropFirst(shared).map(String.init)).joined(separator: "/")
        return relative.hasPrefix("../") ? relative : "./" + relative
    }
    private func imageReferenced(_ path: String, snapshot: NativeImageSnapshot, replacing: [String: Data] = [:], excludingEntries: Set<String> = []) throws -> Bool {
        if !snapshot.linkedPaths.isEmpty || !snapshot.history.problems.isEmpty { return true }
        let wanted = try url(for: path).resolvingSymlinksInPath().standardizedFileURL
        for (notePath, bytes) in snapshot.markdown.merging(replacing, uniquingKeysWith: { _, new in new }) {
            guard let text = String(data: bytes, encoding: .utf8) else { return true }
            let parts = NoteDocument.split(text)
            for link in try MarkdownMoveLinks.links(in: parts.body) {
                if case .wiki = link.kind { continue }
                if let location = try? resolveResource(link.value, notePath: notePath), location.resolvingSymlinksInPath().standardizedFileURL == wanted { return true }
            }
            let filename = (path as NSString).lastPathComponent
            if try Self.retentionStrings(parts.header).contains(where: { $0.contains(path) || $0.removingPercentEncoding?.contains(filename) == true }) { return true }
        }
        var metadata = snapshot.history.metadata
        metadata.removeValue(forKey: NativeImageTrashIndex.path)
        // History image paths describe provenance; the actual bytes live in
        // immutable history blobs. Deliberate revisions and foreign metadata
        // remain conservative references, including any extension fields.
        var values: [String] = []
        for bytes in metadata.values {
            guard let object = try? JSONSerialization.jsonObject(with: bytes), let strings = try? Self.retentionStrings(object) else { return true }
            values += strings
        }
        for bytes in snapshot.history.records.values {
            guard var object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], NativeHistory.integer(object["schema"]) == 1 else { return true }
            if let images = object["images"] as? [[String: Any]] {
                for var image in images {
                    for key in ["path", "hash", "extension"] { image.removeValue(forKey: key) }
                    values += try Self.retentionStrings(image)
                }
            } else { return true }
            for key in ["schema", "id", "noteId", "timestamp", "source", "originId", "parentId", "depth", "kind", "baseHash", "resultHash", "images", "kept", "label", "content", "delta"] { object.removeValue(forKey: key) }
            values += try Self.retentionStrings(object)
        }
        for bytes in snapshot.history.localDrafts.values {
            guard let object = try? JSONSerialization.jsonObject(with: bytes), let strings = try? Self.retentionStrings(object) else { return true }
            values += strings
        }
        for var row in snapshot.index.objects {
            let excluded = (row["id"] as? String).map(excludingEntries.contains) == true
            for key in ["id", "name", "originalPath", "deletedAt", "noteId", "markdown", "nativeCaption", "nativeTitle"] { row.removeValue(forKey: key) }
            if excluded { row.removeValue(forKey: "trashPath") }
            values += try Self.retentionStrings(row)
        }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        // Basename matching covers relative references in unrecognized saved
        // metadata, where no reliable originating note folder is available.
        let filename = (path as NSString).lastPathComponent
        return values.contains { $0.contains(path) || $0.contains(encoded) || $0.removingPercentEncoding?.contains(filename) == true }
    }
    func prepareImageChange(_ snapshot: NativeImageSnapshot, action: NativeImageChange) throws -> NativeImagePlan {
        try Task.checkCancellation()
        guard snapshot.root == root else { throw VaultFailure(message: "The vault changed. Reopen Images.") }
        var changes: [VaultFileChange] = [], rows = snapshot.index.objects, files: [String] = [], title = "", explanation = ""
        func change(_ path: String, _ before: Data?, _ after: Data?) { changes.append(.init(path: path, before: before, after: after)) }
        switch action {
        case .remove(let notePath, let occurrence):
            guard let bytes = snapshot.markdown[notePath], let text = String(data: bytes, encoding: .utf8) else { throw VaultFailure(message: "The note is unavailable. Reopen it before removing an image.") }
            var note = NoteDocument(path: notePath, content: text, modified: Date())
            guard let actual = NativeInlineImage.occurrences(in: note.parts.body).first(where: { $0.id == occurrence.id }), actual.markdown == occurrence.markdown, actual.reference == occurrence.reference else { throw VaultFailure(message: "The image or note changed. Choose the image again.") }
            let body = NSMutableString(string: note.parts.body); body.replaceCharacters(in: actual.range, with: "")
            note.content = note.replacingBody(body as String)
            title = "Remove image?"; explanation = "Only this image occurrence will be removed from the note. Its surrounding Markdown stays intact."
            if let location = try? resolveResource(actual.reference, notePath: notePath) {
                let prefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/", resolved = location.resolvingSymlinksInPath().standardizedFileURL.path
                if resolved.hasPrefix(prefix) {
                    let path = String(resolved.dropFirst(prefix.count))
                    if NativeImageTrashIndex.safePath(path), !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
                       !(try imageReferenced(path, snapshot: snapshot, replacing: [notePath: Data(note.content.utf8)])), let asset = try? imageBytes(path) {
                        let id = note.stableID ?? UUID().uuidString.lowercased()
                        guard NativeHistory.identity(id), snapshot.history.notes.filter({ $0.stableID == id }).count <= 1 else { throw VaultFailure(message: "The note has an invalid or duplicate identity. Resolve it before moving its image.") }
                        if note.stableID == nil { note.content = try note.setting("zerus-id", to: id) }
                        let filename = location.lastPathComponent, stem = (filename as NSString).deletingPathExtension, ext = (filename as NSString).pathExtension
                        var destination = ".trash/assets/" + filename, suffix = 2
                        while FileManager.default.fileExists(atPath: try url(for: destination).path) || snapshot.index.entries.contains(where: { $0.trashPath == destination }) {
                            destination = ".trash/assets/" + stem + "-\(suffix)" + (ext.isEmpty ? "" : "." + ext); suffix += 1
                        }
                        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#%"))) ?? path
                        var row: [String: Any] = ["id": UUID().uuidString.lowercased(), "name": filename, "originalPath": encoded, "trashPath": destination, "deletedAt": ISO8601DateFormatter().string(from: Date()), "noteId": id, "markdown": actual.markdown, "nativeCaption": actual.caption]
                        if let value = actual.title { row["nativeTitle"] = value }; rows.append(row)
                        change(path, asset, nil); change(destination, nil, asset); files = [path, destination]
                        explanation += " The unused local file will move to Recently Deleted, where it can be restored."
                    } else { explanation += " The file is shared, managed, linked, or unavailable and will stay in its current location." }
                }
            } else { explanation += " The remote or missing image file will stay unchanged." }
            change(notePath, bytes, Data(note.content.utf8))
        case .restore(let id, let reattach):
            guard let entry = snapshot.index.entries.first(where: { $0.id == id }), let target = entry.originalPath.removingPercentEncoding else { throw VaultFailure(message: "This deleted image changed. Reload Recently Deleted.") }
            guard !FileManager.default.fileExists(atPath: try url(for: target).path) else { throw VaultFailure(message: "A file already exists at \(target). Rename or move it before restoring this image.") }
            try imagePathWithoutAliases(target)
            let bytes = try imageBytes(entry.trashPath)
            change(target, nil, bytes); files = [target]
            if !(try imageReferenced(entry.trashPath, snapshot: snapshot, excludingEntries: [id])) { change(entry.trashPath, bytes, nil) }
            title = "Restore image?"; explanation = "Restore \(entry.name) to \(target)."
            if reattach, let noteID = entry.noteID {
                let matches = snapshot.history.notes.filter { $0.stableID == noteID }
                guard matches.count <= 1 else { throw VaultFailure(message: "Multiple notes share this identity. Restore the file without reattaching, or resolve the note identity first.") }
                if var note = matches.first {
                    let alreadyAttached = NativeInlineImage.occurrences(in: note.parts.body).contains { image in
                        (try? Self.resourceCandidates(image.reference, notePath: note.path, root: root).contains(where: { $0.standardizedFileURL == root.appendingPathComponent(target).standardizedFileURL })) == true
                    }
                    if !alreadyAttached {
                        let uri = imageRelative(target, from: note.path).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#%")))!
                        let row = rows.first { $0["id"] as? String == id } ?? [:]
                        let caption = (row["nativeCaption"] as? String ?? entry.name).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                        let original = entry.markdown ?? "", parsed = NativeInlineImage.occurrences(in: original)
                        let savedTitle = (row["nativeTitle"] as? String).map { " \"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" } ?? ""
                        var markdown = "![\(caption)](<\(uri)>\(savedTitle))"
                        if let image = parsed.first, parsed.count == 1 {
                            // Rebase the original spelling when it is inline;
                            // reference-style images become self-contained.
                            let links = try MarkdownMoveLinks.links(in: original).filter { $0.range.location >= image.imageRange.location && NSMaxRange($0.range) <= NSMaxRange(image.imageRange) }
                            if !links.isEmpty { markdown = MarkdownMoveLinks.replacing(original, edits: links.map { ($0, uri) }) }
                        }
                        let before = Data(note.content.utf8), separator = note.parts.body.hasSuffix("\n\n") ? "" : note.parts.body.hasSuffix("\n") ? "\n" : "\n\n"
                        note.content = note.replacingBody(note.parts.body + separator + markdown + "\n")
                        change(note.path, before, Data(note.content.utf8)); explanation += " Reattach it to \(note.title)."
                    }
                } else { explanation += " The original note is unavailable; only the file will be restored." }
            }
            rows.removeAll { $0["id"] as? String == id }
        case .purge(let ids):
            let entries = snapshot.index.entries.filter { ids.contains($0.id) }
            guard !ids.isEmpty, entries.count == ids.count else { throw VaultFailure(message: "The deleted images changed. Reload the review.") }
            for entry in entries {
                guard !(try imageReferenced(entry.trashPath, snapshot: snapshot, excludingEntries: ids)) else { throw VaultFailure(message: "\(entry.name) is still referenced by saved data or recovery metadata. Its file and deleted-image record are preserved.") }
                let location = try url(for: entry.trashPath)
                if FileManager.default.fileExists(atPath: location.path) { change(entry.trashPath, try imageBytes(entry.trashPath), nil); files.append(entry.trashPath) }
            }
            rows.removeAll { ($0["id"] as? String).map(ids.contains) == true }
            title = "Delete images permanently?"; explanation = "Permanently delete \(entries.count) image file(s) from Recently Deleted. This cannot be undone. Notes and saved history remain unchanged."
        case .undo: throw VaultFailure(message: "Use the saved Undo review for this image change.")
        }
        if try NativeImageTrashIndex.encode(rows) != NativeImageTrashIndex.encode(snapshot.index.objects) { change(NativeImageTrashIndex.path, snapshot.index.bytes, try NativeImageTrashIndex.encode(rows)) }
        guard changes.reduce(0, { $0 + ($1.before?.count ?? 0) + ($1.after?.count ?? 0) }) <= 128 * 1024 * 1024 else { throw VaultFailure(message: "This image change is too large to save safely at once. Review fewer images.") }
        return .init(snapshot: snapshot, action: action, changes: changes, title: title, explanation: explanation, files: files)
    }
    func applyImageChange(_ plan: NativeImagePlan) throws -> VaultSnapshot {
        guard root == plan.snapshot.root else { throw VaultFailure(message: "The vault changed. Reopen the image review.") }
        var dependencies = plan.snapshot.markdown.merging(plan.snapshot.history.records, uniquingKeysWith: { a, _ in a }).merging(plan.snapshot.history.metadata, uniquingKeysWith: { a, _ in a }).mapValues { Optional($0) }
        dependencies[NativeImageTrashIndex.path] = .some(plan.snapshot.index.bytes)
        var changes = dependencies.map { VaultFileChange(path: $0.key, before: $0.value, after: $0.value) }
        let modified = Set(plan.changes.map(\.path)); changes.removeAll { modified.contains($0.path) }; changes += plan.changes
        let snapshot = plan.snapshot
        try applyTransaction(changes, historySource: "mobile", validate: {
            try Self.validateHistoryMaintenance(snapshot.history)
            let inventory = try Self.imageMarkdownInventory(root: snapshot.root)
            guard inventory.paths == Set(snapshot.markdown.keys), inventory.linked == snapshot.linkedPaths else { throw VaultFailure(message: "Saved Markdown or linked files changed. Reopen the image review.") }
        })
        return try scan()
    }
    func prepareImageUndo(_ original: NativeImagePlan) throws -> NativeImagePlan {
        guard original.snapshot.root == root, !original.permanent else { throw VaultFailure(message: "This image change cannot be undone here.") }
        let snapshot = try imageSnapshot()
        for change in original.changes {
            let location = try url(for: change.path), current = FileManager.default.fileExists(atPath: location.path) ? try read(change.path) : nil
            guard current == change.after else { throw VaultFailure(message: "The note or image changed after removal. Restore the image through Recently Deleted instead.") }
        }
        // A new reference to the Trash copy must survive Undo too.
        for change in original.changes where change.before == nil && change.after != nil && change.path.hasPrefix(".trash/assets/") {
            let ids = Set(snapshot.index.entries.filter { $0.trashPath == change.path }.map(\.id))
            guard !(try imageReferenced(change.path, snapshot: snapshot, excludingEntries: ids)) else { throw VaultFailure(message: "Another saved item now uses the deleted copy. Restore it through Recently Deleted instead.") }
        }
        return .init(snapshot: snapshot, action: .undo, changes: original.changes.map { .init(path: $0.path, before: $0.after, after: $0.before) }, title: "Undo image removal", explanation: "Restore the previous note and image bytes.", files: original.files)
    }
}
