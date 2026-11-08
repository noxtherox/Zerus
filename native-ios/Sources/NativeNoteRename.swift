import Foundation
import Markdown

struct NativeNoteRenamePlan: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let maintenance: NativeRelationMaintenancePlan
    let taskLinksUpdated: Int
    var destination: String { maintenance.destination! }
    var changedFiles: [String] { maintenance.changes.filter { $0.before != $0.after }.map(\.path) }
}

enum NativeNoteRename {
    static func cleanTitle(_ value: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 250, !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }) else { throw VaultFailure(message: "Enter a title on one line, up to 250 characters.") }
        return title
    }
    static func suggestedFilename(_ title: String, path: String) -> String {
        var stem = title.replacingOccurrences(of: #"[/\\:*?"<>|#\[\]\x00-\x1F]"#, with: "-", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        while stem.hasPrefix(".") { stem.removeFirst() }
        while stem.utf8.count > 180 { stem.removeLast() }
        while stem.hasSuffix(".") || stem.hasSuffix(" ") { stem.removeLast() }
        if stem.range(of: #"(?i)^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$"#, options: .regularExpression) != nil { stem = "_" + stem }
        if stem.isEmpty { stem = "Untitled" }
        return stem + "." + (path as NSString).pathExtension
    }
    static func content(_ original: String, title: String) -> String {
        let parts = NoteDocument.split(original), body = parts.body as NSString
        let newline = parts.body.contains("\r\n") ? "\r\n" : "\n"
        var lines: [NSRange] = [], offset = 0
        while offset < body.length { let line = body.lineRange(for: NSRange(location: offset, length: 0)); lines.append(line); offset = NSMaxRange(line) }
        let heading = Document(parsing: parts.body).children.compactMap { $0 as? Heading }.first { $0.level == 1 }
        if let range = heading?.range, range.lowerBound.line > 0, range.lowerBound.line <= lines.count {
            let finalLine = range.upperBound.column == 1 && range.upperBound.line > range.lowerBound.line ? range.upperBound.line - 1 : range.upperBound.line
            let start = lines[range.lowerBound.line - 1].location, last = lines[min(finalLine, lines.count) - 1]
            let legacyTitle = lines.first { body.substring(with: $0).hasPrefix("# ") }
            // A literal heading in an earlier fenced example is not the title.
            // Add a real title before it instead of editing the example.
            if legacyTitle == nil || legacyTitle!.location >= start {
                let whole = NSRange(location: start, length: NSMaxRange(last) - start)
                let source = body.substring(with: whole), ending = source.hasSuffix("\r\n") ? "\r\n" : source.hasSuffix("\n") ? "\n" : ""
                return parts.header + body.replacingCharacters(in: whole, with: "# " + title + ending)
            }
        }
        return parts.header + "# " + title + newline + newline + parts.body
    }
}

extension VaultFiles {
    func prepareRename(_ snapshot: NativeRelationDefinitionSnapshot, source: String, title input: String, renameFile: Bool) throws -> NativeNoteRenamePlan {
        let title = try NativeNoteRename.cleanTitle(input)
        guard let original = snapshot.notes.first(where: { $0.path == source }), !original.trashed else { throw VaultFailure(message: "Restore the note before renaming it.") }
        var destination = source
        if renameFile && !source.hasPrefix(".zerus/") {
            let name = NativeNoteRename.suggestedFilename(title, path: source), parent = (source as NSString).deletingLastPathComponent
            destination = parent.isEmpty ? name : parent + "/" + name
            // Case-insensitive filesystems treat this as the existing file.
            // Keep its spelling and show the exact destination in the review.
            if destination.caseInsensitiveCompare(source) == .orderedSame { destination = source }
        }
        let base = try prepareMove(snapshot, source: source, destination: destination, renaming: true)
        var changes = base.changes
        guard let index = changes.firstIndex(where: { $0.path == destination }), let bytes = changes[index].after, let text = String(data: bytes, encoding: .utf8) else { throw VaultFailure(message: "The note changed. Reload Rename.") }
        var renamed = NoteDocument(path: destination, content: text, modified: Date())
        let resulting = snapshot.notes.filter { $0.path != source } + [renamed]
        renamed = try NativeRelationSnapshot.stableReference(renamed, notes: resulting).0
        renamed.content = NativeNoteRename.content(renamed.content, title: title)
        changes[index] = .init(path: destination, before: changes[index].before, after: Data(renamed.content.utf8))
        var taskCount = 0
        if source != destination {
            let before = try historyData(".zerus/tasks.json")
            var after = before
            if let before {
                let value = try JSONSerialization.jsonObject(with: before)
                var object = value as? [String: Any]
                guard var rows = (object?["tasks"] ?? value) as? [Any] else { throw VaultFailure(message: "The tasks file uses an unsupported format. Keep the file name or resolve its format before renaming.") }
                for row in rows.indices {
                    guard var task = rows[row] as? [String: Any], let raw = task["linkedNoteIds"] else { continue }
                    guard let links = raw as? [String] else { throw VaultFailure(message: "A task has unsupported supporting-note links. Keep the file name or resolve those links first.") }
                    var updated = links
                    for item in links.indices where links[item] == source {
                        let matches = snapshot.notes.filter { !$0.trashed && ($0.path == links[item] || $0.stableID == links[item]) }
                        guard matches.count == 1 else { throw VaultFailure(message: "A task’s supporting-note target is ambiguous. Resolve it before renaming the file.") }
                        updated[item] = renamed.stableID!; taskCount += 1
                    }
                    if updated != links { task["linkedNoteIds"] = updated; rows[row] = task }
                }
                if taskCount > 0 {
                    if object != nil { object!["tasks"] = rows }
                    after = try JSONSerialization.data(withJSONObject: object.map { $0 as Any } ?? rows, options: [.sortedKeys, .withoutEscapingSlashes])
                }
            }
            changes.append(.init(path: ".zerus/tasks.json", before: before, after: after))
        }
        if source != destination {
            // Capture the title edit under the existing note identity while
            // the journal moves its file. No intermediate title write escapes.
            let capture = try includingAutomaticHistory([.init(path: source, before: Data(original.content.utf8), after: Data(renamed.content.utf8))], source: "mobile")
            for dependency in capture where dependency.path != source {
                if let existing = changes.first(where: { $0.path == dependency.path }) {
                    guard existing.before == dependency.before, existing.after == dependency.after else { throw VaultFailure(message: "History dependencies changed. Reload Rename.") }
                } else { changes.append(dependency) }
            }
        }
        let summaries = base.summaries + ["Change the note title to “\(title)”. Existing link labels and local attachment files are kept."] + (taskCount == 0 ? [] : ["Keep \(taskCount) task supporting-note links connected by stable note identity."])
        var maintenance = NativeRelationMaintenancePlan(snapshot: snapshot, changes: changes, sourcePath: source, destination: destination, summaries: summaries, issues: base.issues)
        maintenance.resourceBindings = base.resourceBindings
        return NativeNoteRenamePlan(title: title, maintenance: maintenance, taskLinksUpdated: taskCount)
    }
}
