import Foundation
import CryptoKit

enum NativeFolderPath {
    static func clean(_ input: String) throws -> String {
        let path = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, parts.count <= 8, path != "assets", !path.hasPrefix("assets/"),
              parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && $0.utf8.count <= 240 && $0.range(of: #"[:\\\x00-\x1F]"#, options: .regularExpression) == nil }) else {
            throw VaultFailure(message: "Use up to eight ordinary folder names separated by /. Hidden folders, assets, empty names, colons and control characters are unavailable.")
        }
        return path
    }
    static func remap(_ path: String, from source: String, to destination: String) -> String {
        if path == source { return destination }
        if path.hasPrefix(source + "/") { return destination + path.dropFirst(source.count) }
        return path
    }
    static func location(_ path: String, root: URL) throws -> URL {
        let location = root.appendingPathComponent(path)
        _ = try VaultFiles.confinedPath(for: location, root: root)
        let parts = path.split(separator: "/")
        for count in 1...parts.count {
            let parent = root.appendingPathComponent(parts.prefix(count).joined(separator: "/"))
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: parent.path)) == nil else { throw VaultFailure(message: "Linked folders must be reconnected before renaming. Their files are unchanged.") }
        }
        return location
    }
}

/// Hashes opaque files without loading an entire attachment into memory.
/// Empty directories are part of the review, including ones without notes.
struct NativeFolderTree: Codable, Equatable, Sendable {
    var files: [String: String]
    let directories: [String]
    static func inspect(_ folder: String, root: URL) throws -> Self {
        let start = try NativeFolderPath.location(folder, root: root)
        guard try start.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw VaultFailure(message: "This folder is unavailable. Reconnect it in Files and reload the review.") }
        var pending = [""], directories: [String] = [], files: [String: String] = [:]
        while let relative = pending.popLast() {
            try Task.checkCancellation(); directories.append(relative)
            let directory = relative.isEmpty ? start : start.appendingPathComponent(relative)
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]) {
                let path = relative.isEmpty ? file.lastPathComponent : relative + "/" + file.lastPathComponent
                _ = try VaultFiles.confinedPath(for: file, root: root)
                let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw VaultFailure(message: "\(folder)/\(path) is a linked file. Resolve its location before renaming this folder.") }
                if values.isDirectory == true { pending.append(path) }
                else {
                    guard values.isRegularFile == true else { throw VaultFailure(message: "\(folder)/\(path) is not an ordinary file. Its contents are preserved.") }
                    let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
                    var hash = SHA256()
                    while true {
                        try Task.checkCancellation()
                        let part = try handle.read(upToCount: 1024 * 1024) ?? Data()
                        if part.isEmpty { break }; hash.update(data: part)
                    }
                    files[path] = hash.finalize().map { String(format: "%02x", $0) }.joined()
                }
            }
        }
        return .init(files: files, directories: directories.sorted())
    }
}

struct NativeFolderRenameReceipt: Codable, Sendable {
    let version: Int
    let source: String
    let destination: String
    let tree: NativeFolderTree
}

struct NativeFolderRenamePlan: Identifiable, Sendable {
    let id = UUID()
    let snapshot: NativeRelationDefinitionSnapshot
    let source: String
    let destination: String
    let tree: NativeFolderTree
    let changes: [VaultFileChange]
    let bindings: [NativeMoveResourceBinding]
    let updatedNotes: [String]
    let rewrittenLinks: Int
    static func notePath(_ path: String, source: String, destination: String) -> String {
        NativeFolderPath.remap(NativeFolderPath.remap(path, from: source, to: destination), from: ".trash/" + source, to: ".trash/" + destination)
    }
}

extension VaultFiles {
    /// The ordinary transaction journals the metadata, note edits and receipt
    /// together. Recovery finishes the physical directory move before scanning
    /// or admitting another write, retaining empty folders and opaque files.
    func finishFolderRenames() throws {
        let directory = try url(for: ".zerus/native-folder-renames")
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let bytes = try read(".zerus/native-folder-renames/" + file.lastPathComponent)
            let record = try JSONDecoder().decode(NativeFolderRenameReceipt.self, from: bytes)
            guard record.version == 1, try NativeFolderPath.clean(record.source) == record.source,
                  try NativeFolderPath.clean(record.destination) == record.destination,
                  record.source.caseInsensitiveCompare(record.destination) != .orderedSame,
                  !record.destination.lowercased().hasPrefix(record.source.lowercased() + "/"),
                  record.tree.directories.contains(""), record.tree.files.values.allSatisfy({ $0.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil }) else {
                throw VaultFailure(message: "An unsupported folder-rename record is preserved. Reconnect the original vault before continuing.")
            }
            let from = try NativeFolderPath.location(record.source, root: root), to = try NativeFolderPath.location(record.destination, root: root)
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            let originalRoot = root
            try Self.coordinateTransaction(locations: [from, to, file], root: root) { urls in
                guard try Data(contentsOf: urls[2]) == bytes else { throw VaultFailure(message: "The pending folder rename changed. Reopen the vault to retry.") }
                let sourceExists = FileManager.default.fileExists(atPath: urls[0].path), destinationExists = FileManager.default.fileExists(atPath: urls[1].path)
                if sourceExists, !destinationExists {
                    guard try NativeFolderTree.inspect(record.source, root: originalRoot) == record.tree else { throw VaultFailure(message: "The confirmed folder rename is waiting because its original files changed. Your files and rename record are kept. Restore the reviewed files in Files, then reopen this vault to finish.") }
                    try FileManager.default.moveItem(at: urls[0], to: urls[1])
                } else if !sourceExists, destinationExists {
                    guard try NativeFolderTree.inspect(record.destination, root: originalRoot) == record.tree else { throw VaultFailure(message: "The renamed folder changed before its rename record was cleared. Both the folder and record are preserved for recovery.") }
                } else { throw VaultFailure(message: "The confirmed folder rename is waiting for its original or destination folder. Keep both locations in Files and reconnect this vault to retry; the rename record is preserved.") }
                try FileManager.default.removeItem(at: urls[2])
            }
        }
    }

    func prepareFolderRename(_ snapshot: NativeRelationDefinitionSnapshot, source: String, destination input: String) throws -> NativeFolderRenamePlan {
        guard snapshot.schema.root == root, try NativeFolderPath.clean(source) == source else { throw VaultFailure(message: "The vault changed. Reopen Rename folder.") }
        let destination = try NativeFolderPath.clean(input)
        guard source.caseInsensitiveCompare(destination) != .orderedSame, !destination.lowercased().hasPrefix(source.lowercased() + "/") else { throw VaultFailure(message: "Choose a different folder name or parent, outside this folder’s own subtree. Case-only changes keep the existing spelling.") }
        let target = try NativeFolderPath.location(destination, root: root)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw VaultFailure(message: "A file or folder already exists at the destination. Choose another name.") }
        let tree = try NativeFolderTree.inspect(source, root: root)
        func path(_ value: String) -> String { NativeFolderRenamePlan.notePath(value, source: source, destination: destination) }
        var content = Dictionary(uniqueKeysWithValues: snapshot.notes.map { ($0.path, $0.content) })
        var stable: [String: String] = [:]
        for note in snapshot.notes where path(note.path) != note.path {
            try NativePropertyDefinition.validateOwner((path(note.path.hasPrefix(".trash/") ? String(note.path.dropFirst(7)) : note.path) as NSString).deletingLastPathComponent)
            let value = try NativeRelationSnapshot.stableReference(note, notes: snapshot.notes)
            content[note.path] = value.0.content; stable[note.path] = value.0.stableID
        }
        // Upgrade incoming legacy relation values before changing their paths.
        for original in snapshot.notes {
            var text = content[original.path]!
            for definition in (try? snapshot.schema.checkedEffective(notePath: original.path)) ?? [] where definition.type == .relation {
                guard NativeFrontmatter(text).entry(definition.name) != nil else { continue }
                let references = try NativeRelationSnapshot.values(original, name: definition.name)
                let resolver = NativeRelationSnapshot(schema: snapshot.schema, notes: snapshot.notes, sourcePath: original.path, name: definition.name)
                var values = references
                for index in references.indices {
                    let matches = resolver.matches(references[index])
                    guard matches.contains(where: { stable[$0.path] != nil }) else { continue }
                    guard matches.count == 1, let next = stable[matches[0].path] else { throw VaultFailure(message: "\(original.path) has an ambiguous relation into this folder. Resolve it before renaming.") }
                    values[index] = "zerus:" + next
                }
                if values != references {
                    let value: NativePropertyValue
                    if case .list = NativeFrontmatter(text).entry(definition.name)?.value { value = .list(values) }
                    else { value = .text(values.first ?? "") }
                    text = try NativeFrontmatter(text).setting(definition.name, value: value)
                }
            }
            content[original.path] = text
        }
        var bindings: [NativeMoveResourceBinding] = [], rewrites = 0
        let canonicalPrefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let movedNotePaths = Dictionary(uniqueKeysWithValues: snapshot.notes.filter { path($0.path) != $0.path }.map { ($0.path, path($0.path)) })
        let futureFiles = Set(tree.files.keys.map { destination + "/" + $0 }).union(movedNotePaths.values)
        func futureExists(_ file: String) -> Bool {
            if futureFiles.contains(file) { return true }
            if file.hasPrefix(source + "/") || movedNotePaths[file] != nil { return false }
            return FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path)
        }
        for original in snapshot.notes {
            var document = NoteDocument(path: original.path, content: content[original.path]!, modified: original.modified)
            let nextPath = path(original.path), moved = nextPath != original.path
            var edits: [(MarkdownMoveLinks.Link, String)] = []
            for link in try MarkdownMoveLinks.links(in: original.parts.body) {
                let reference: NoteReference?
                switch link.kind {
                case .wiki: reference = NoteReference(wikilink: link.value)
                case .destination: reference = URL(string: link.value).flatMap(NoteReference.init(url:))
                case .html: reference = nil
                }
                if let reference {
                    if reference.target.hasPrefix("zerus:") { continue }
                    let matches = reference.targets(in: snapshot.notes, includeHeadingFragments: true)
                    guard matches.contains(where: { stable[$0.path] != nil }) else { continue }
                    guard matches.count == 1, let id = stable[matches[0].path] else { throw VaultFailure(message: "\(original.path) contains an ambiguous note link into this folder. Resolve it before renaming.") }
                    let target = "zerus:" + id + (reference.heading(in: matches[0]).map { "#" + $0 } ?? "")
                    if case .wiki = link.kind { edits.append((link, "[[" + target + "|" + reference.label + "]]")) }
                    else { edits.append((link, NoteReference(target: target, label: reference.label, explicitLabel: true).fragmentDestination(label: reference.label))) }
                    continue
                }
                if case .wiki = link.kind { continue }
                guard let url = URL(string: link.value), url.scheme == nil, !url.relativePath.isEmpty, !url.relativePath.hasPrefix("/") else { continue }
                let resolved = try? resolveResource(link.value, notePath: original.path)
                let canonical = try resolved.map { try Self.confinedPath(for: $0, root: root) }
                guard let canonical else {
                    if moved { throw VaultFailure(message: "\(original.path) links to unavailable file ‘\(link.value)’. Reconnect it or update the link before renaming this folder.") }
                    continue
                }
                let previous = String(canonical.dropFirst(canonicalPrefix.count))
                let next = movedNotePaths[previous] ?? NativeFolderPath.remap(previous, from: source, to: destination)
                guard moved || previous != next else { continue }
                bindings.append(.init(notePath: original.path, reference: link.value, resolved: canonical))
                let candidates = try Self.resourceCandidates(link.value, notePath: nextPath, root: root)
                let untouched = try candidates.compactMap { url -> String? in
                    let candidate = String(try Self.confinedPath(for: url, root: root).dropFirst(canonicalPrefix.count))
                    return futureExists(candidate) ? candidate : nil
                }.first
                if untouched != next { edits.append((link, MarkdownResources.encodedPath(Self.folderRelativePath(to: next, from: nextPath), preservingSuffixOf: link.value))) }
            }
            document.content = document.replacingBody(MarkdownMoveLinks.replacing(original.parts.body, edits: edits)); rewrites += edits.count
            if let hub = document.fileHub, hub.kind == .vault, let previous = hub.path {
                let next = NativeFolderPath.remap(previous, from: source, to: destination)
                if next != previous { document.content = try NativeFrontmatter(document.content).setting("zerus-file-path", value: .text(next)) }
            }
            if case .list(let rows) = NativeFrontmatter(document.content).entry("zerus-attachments")?.value {
                var updated = rows
                for index in rows.indices {
                    guard var object = try? JSONSerialization.jsonObject(with: Data(rows[index].utf8)) as? [String: Any], object["kind"] as? String == "vault", let previous = object["path"] as? String else { continue }
                    let next = NativeFolderPath.remap(previous, from: source, to: destination)
                    if next != previous { object["path"] = next; updated[index] = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self) }
                }
                if updated != rows { document.content = try NativeFrontmatter(document.content).setting("zerus-attachments", value: .list(updated)) }
            }
            content[original.path] = document.content
        }
        var changes: [VaultFileChange] = [], updatedNotes: [String] = []
        for original in snapshot.notes {
            let next = content[original.path]!, nextPath = path(original.path)
            if next != original.content || nextPath != original.path { updatedNotes.append(nextPath) }
            if original.trashed, nextPath != original.path {
                guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(nextPath).path) else { throw VaultFailure(message: "A deleted note already exists at \(nextPath). Resolve that collision before renaming.") }
                changes.append(.init(path: nextPath, before: nil, after: Data(next.utf8)))
                changes.append(.init(path: original.path, before: Data(original.content.utf8), after: nil))
            } else { changes.append(.init(path: original.path, before: Data(original.content.utf8), after: Data(next.utf8))) }
        }
        for metadata in [".zerus/properties.json", ".zerus/type-icons.json", ".zerus/views.json", ".zerus/saved-views.json"] {
            let before = try metadata == ".zerus/properties.json" ? snapshot.schema.bytes : historyData(metadata)
            var after = before
            if let before {
                guard let object = try JSONSerialization.jsonObject(with: before) as? [String: Any] else { throw VaultFailure(message: "\(metadata) uses an unsupported format. Its bytes are preserved; resolve it before renaming.") }
                var next: [String: Any] = [:]
                for (key, raw) in object {
                    let newKey = NativeFolderPath.remap(key, from: source, to: destination)
                    guard !next.keys.contains(where: { $0.caseInsensitiveCompare(newKey) == .orderedSame }) else { throw VaultFailure(message: "Folder metadata already exists at \(newKey). Resolve the collision before renaming.") }
                    var value = raw
                    if metadata == ".zerus/properties.json", var definitions = raw as? [[String: Any]] {
                        for index in definitions.indices where definitions[index]["type"] as? String == "relation" {
                            if let target = definitions[index]["relationTypeKey"] as? String { definitions[index]["relationTypeKey"] = NativeFolderPath.remap(target, from: source, to: destination) }
                        }
                        value = definitions
                    }
                    next[newKey] = value
                }
                if !NSDictionary(dictionary: object).isEqual(to: next) { after = try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) }
            }
            changes.append(.init(path: metadata, before: before, after: after))
        }
        let taskBytes = try historyData(".zerus/tasks.json")
        var taskAfter = taskBytes
        if let taskBytes {
            let raw = try JSONSerialization.jsonObject(with: taskBytes)
            var object = raw as? [String: Any]
            guard var rows = (object?["tasks"] ?? raw) as? [[String: Any]] else { throw VaultFailure(message: "The tasks file uses an unsupported format. Its bytes are preserved; resolve it before renaming.") }
            var changed = false
            for index in rows.indices {
                guard let value = rows[index]["linkedNoteIds"] else { continue }
                guard let links = value as? [String] else { throw VaultFailure(message: "A task has unsupported supporting-note links. Resolve it before renaming.") }
                let next = links.map { stable[$0] ?? $0 }
                if next != links { rows[index]["linkedNoteIds"] = next; changed = true }
            }
            if changed { if object != nil { object!["tasks"] = rows }; taskAfter = try JSONSerialization.data(withJSONObject: object.map { $0 as Any } ?? rows, options: [.sortedKeys, .withoutEscapingSlashes]) }
        }
        changes.append(.init(path: ".zerus/tasks.json", before: taskBytes, after: taskAfter))
        var afterTree = tree
        for change in changes where change.path.hasPrefix(source + "/") {
            let relative = String(change.path.dropFirst(source.count + 1))
            if let bytes = change.after { afterTree.files[relative] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
        }
        let receipt = NativeFolderRenameReceipt(version: 1, source: source, destination: destination, tree: afterTree)
        changes.append(.init(path: ".zerus/native-folder-renames/" + UUID().uuidString.lowercased() + ".json", before: nil, after: try JSONEncoder().encode(receipt)))
        return .init(snapshot: snapshot, source: source, destination: destination, tree: tree, changes: changes, bindings: bindings, updatedNotes: updatedNotes.sorted(), rewrittenLinks: rewrites)
    }

    func applyFolderRename(_ plan: NativeFolderRenamePlan) throws -> VaultSnapshot {
        let source = plan.source, destination = plan.destination, tree = plan.tree, bindings = plan.bindings, originalRoot = root
        let notePaths = Set(plan.snapshot.notes.map(\.path))
        return try applyRelationChanges(schema: plan.snapshot.schema, notes: plan.snapshot.notes, changes: plan.changes) {
            guard try NativeFolderTree.inspect(source, root: originalRoot) == tree,
                  !FileManager.default.fileExists(atPath: originalRoot.appendingPathComponent(destination).path) else { throw VaultFailure(message: "The folder or destination changed since review. No files were changed; reload Rename folder.") }
            for binding in bindings where NativeMoveResourceBinding.path(binding.reference, notePath: binding.notePath, root: originalRoot) != binding.resolved { throw VaultFailure(message: "A linked file changed since review. No files were changed; reload Rename folder.") }
            guard try Self.notePathInventory(root: originalRoot) == notePaths else { throw VaultFailure(message: "Notes changed since review. No files were changed; reload Rename folder.") }
        }
    }

    private nonisolated static func folderRelativePath(to target: String, from note: String) -> String {
        let logical = note.hasPrefix(".trash/") ? String(note.dropFirst(7)) : note
        let base = logical.split(separator: "/").dropLast(), parts = target.split(separator: "/")
        let common = zip(base, parts).prefix { $0 == $1 }.count
        let result = (Array(repeating: "..", count: base.count - common) + parts.dropFirst(common).map(String.init)).joined(separator: "/")
        return result.hasPrefix("../") ? result : "./" + result
    }
}
