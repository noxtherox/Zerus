import Foundation

struct NativeMoveResourceBinding: Sendable {
    let notePath: String
    let reference: String
    let resolved: String?
    nonisolated static func path(_ reference: String, notePath: String, root: URL) -> String? {
        guard let location = try? VaultFiles.resolveResource(reference, notePath: notePath, root: root) else { return nil }
        return try? VaultFiles.confinedPath(for: location, root: root)
    }
}

extension VaultFiles {
    /// Compose body-link maintenance with relation maintenance before presenting
    /// one review. Attachments remain in place; only destinations change.
    func prepareMove(_ snapshot: NativeRelationDefinitionSnapshot, source: String, destination: String, renaming: Bool = false) throws -> NativeRelationMaintenancePlan {
        guard snapshot.schema.root == root else { throw VaultFailure(message: "The vault changed. Reopen this move.") }
        let relation = try renaming ? snapshot.renameIdentityPlan(source: source, destination: destination) : snapshot.movePlan(source: source, destination: destination)
        let rebasing = (source as NSString).deletingLastPathComponent != (destination as NSString).deletingLastPathComponent
        var notes = Dictionary(uniqueKeysWithValues: snapshot.notes.map { ($0.path, $0) })
        for change in relation.changes where change.path.lowercased().hasSuffix(".md") {
            if let bytes = change.after {
                notes[change.path] = NoteDocument(path: change.path, content: String(decoding: bytes, as: UTF8.self), modified: Date())
            } else { notes.removeValue(forKey: change.path) }
        }
        let prefix = root.standardizedFileURL.path + "/"
        var bindings: [NativeMoveResourceBinding] = [], seen = Set<String>(), rewrites = 0
        func record(_ reference: String, notePath: String, resolved: String?) {
            if seen.insert(notePath + "\n" + reference).inserted { bindings.append(NativeMoveResourceBinding(notePath: notePath, reference: reference, resolved: resolved)) }
        }
        for original in snapshot.notes {
            let path = original.path == source ? destination : original.path
            var edits: [(MarkdownMoveLinks.Link, String)] = []
            for link in try MarkdownMoveLinks.links(in: original.parts.body) {
                let reference: NoteReference?
                switch link.kind {
                case .wiki: reference = NoteReference(wikilink: link.value)
                case .destination: reference = URL(string: link.value).flatMap(NoteReference.init(url:))
                case .html: reference = nil
                }
                if let reference {
                    guard !reference.target.hasPrefix("zerus:") else { continue }
                    let matches = reference.targets(in: snapshot.notes, includeHeadingFragments: true)
                    guard (rebasing && original.path == source) || matches.contains(where: { $0.path == source }) else { continue }
                    guard matches.count <= 1 else {
                        let line = (original.parts.body as NSString).substring(to: link.range.location).components(separatedBy: "\n").count
                        throw VaultFailure(message: "\(original.path) has an ambiguous note link ‘\(reference.target)’ on body line \(line). Resolve its target before moving.")
                    }
                    guard let target = matches.first else { continue }
                    let targetPath = target.path == source ? destination : target.path
                    guard let current = notes[targetPath] else { throw VaultFailure(message: "A linked note changed. Reload this move.") }
                    let (updated, stable) = try NativeRelationSnapshot.stableReference(current, notes: Array(notes.values))
                    notes[targetPath] = updated
                    let id = String(stable.split(separator: "|", maxSplits: 1)[0]) + (reference.heading(in: target).map { "#" + $0 } ?? "")
                    if case .wiki = link.kind { edits.append((link, "[[" + id + "|" + reference.label + "]]")) }
                    else { edits.append((link, NoteReference(target: String(id), label: reference.label, explicitLabel: true).fragmentDestination(label: reference.label))) }
                    continue
                }
                switch link.kind {
                case .wiki: continue
                case .destination, .html:
                    guard let url = URL(string: link.value), url.scheme == nil, !url.relativePath.isEmpty, !url.relativePath.hasPrefix("/") else { continue }
                    // Only Markdown file destinations can be incoming links to
                    // this Markdown note. Avoid probing unrelated cloud assets
                    // in every other note just to prepare one folder move.
                    guard source != destination, (rebasing && original.path == source) || url.pathExtension.lowercased() == "md" else { continue }
                    let location = try? resolveResource(link.value, notePath: original.path)
                    let resolved = location.flatMap { try? Self.confinedPath(for: $0, root: root) }
                    record(link.value, notePath: original.path, resolved: resolved)
                    guard let location else {
                        if original.path == source && rebasing { throw VaultFailure(message: "The linked file ‘\(link.value)’ is unavailable. Restore it or update its link before moving this note.") }
                        continue
                    }
                    let oldPath = String(location.path.dropFirst(prefix.count))
                    guard original.path == source || oldPath == source else { continue }
                    let target = oldPath == source ? destination : oldPath
                    // Leave globally anchored references byte-identical if they
                    // will still resolve to the same existing file.
                    if oldPath != source, let after = try? resolveResource(link.value, notePath: path), try Self.confinedPath(for: after, root: root) == resolved { continue }
                    edits.append((link, MarkdownResources.encodedPath(Self.relativePath(to: target, from: path), preservingSuffixOf: link.value)))
                }
            }
            if !edits.isEmpty, var current = notes[path] {
                current.content = current.replacingBody(MarkdownMoveLinks.replacing(original.parts.body, edits: edits))
                notes[path] = current; rewrites += edits.count
            }
        }
        // Every inspected note is a read dependency: a new incoming link during
        // the review must not survive with a now-invalid path.
        var changes = snapshot.notes.sorted { $0.path < $1.path }.map {
            VaultFileChange(path: $0.path, before: Data($0.content.utf8), after: notes[$0.path].map { Data($0.content.utf8) })
        }
        guard let moved = notes[destination] else { throw VaultFailure(message: "The moved note is unavailable. Reload this move.") }
        if source != destination { changes.insert(VaultFileChange(path: destination, before: nil, after: Data(moved.content.utf8)), at: 0) }
        changes += relation.changes.filter { !$0.path.lowercased().hasSuffix(".md") }
        var summaries = relation.summaries
        if rewrites > 0 { summaries.append("Update \(rewrites) note and attachment destinations. Labels, captions and attachment files are preserved.") }
        changes = try includingSavedLinkIndex(changes)
        if source.hasPrefix(".zerus/links/") { summaries.append("Keep this link in Saved links and update its shared index as it is filed into the vault.") }
        var plan = NativeRelationMaintenancePlan(snapshot: snapshot, changes: changes, sourcePath: source, destination: destination, summaries: summaries, issues: relation.issues)
        plan.resourceBindings = bindings
        return plan
    }
    private nonisolated static func relativePath(to target: String, from notePath: String) -> String {
        let logical = notePath.hasPrefix(".trash/") ? String(notePath.dropFirst(7)) : notePath
        let base = logical.split(separator: "/").dropLast(), parts = target.split(separator: "/")
        let shared = zip(base, parts).prefix { $0 == $1 }.count
        let relative = (Array(repeating: "..", count: base.count - shared) + parts.dropFirst(shared).map(String.init)).joined(separator: "/")
        // Explicitly relative paths bypass the legacy assets/ root-first rule.
        return relative.hasPrefix("../") ? relative : "./" + relative
    }
}
