import Foundation
import Markdown

struct NativeSavedLink: Sendable {
    let id: String
    let address: String
    var url: URL? { Self.normalizedURL(address) }
    var displayName: String {
        guard let host = url?.host else { return address }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    init?(_ note: NoteDocument) {
        let fields = NativeFrontmatter(note.content)
        guard case .text(let id) = fields.entry("zerus-link-id")?.value,
              case .text(let address) = fields.entry("zerus-link-url")?.value,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.id = id; self.address = address
    }
    static func normalizedURL(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<") { value.removeFirst() }; if value.hasSuffix(">") { value.removeLast() }
        guard !value.isEmpty, value.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        if value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) == nil { value = "https://" + value }
        guard let parsed = URL(string: value), var parts = URLComponents(url: parsed, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme), let host = parts.host, !host.isEmpty else { return nil }
        if let port = parts.port, !(0...65535).contains(port) { return nil }
        parts.scheme = scheme; parts.host = host.lowercased()
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        if parts.path.isEmpty { parts.path = "/" }
        return parts.url?.standardized
    }

    /// Remove only top-level paragraphs consisting of the managed link. Prose,
    /// reference definitions, code and other destinations retain their bytes.
    static func withoutURL(_ body: String, address: String) -> String {
        guard let expected = normalizedURL(address)?.absoluteString else { return body }
        let text = body as NSString, document = Document(parsing: body)
        var starts = [0], cursor = 0
        while cursor < text.length {
            cursor = NSMaxRange(text.lineRange(for: NSRange(location: cursor, length: 0)))
            starts.append(cursor)
        }
        func offset(_ location: SourceLocation, lineOffset: Int) -> Int? {
            let line = location.line + lineOffset - 1
            guard starts.indices.contains(line), starts[line] <= text.length else { return nil }
            let range = text.lineRange(for: NSRange(location: starts[line], length: 0)), raw = text.substring(with: range)
            let prefix = String(decoding: raw.utf8.prefix(max(0, location.column - 1)), as: UTF8.self)
            return min(NSMaxRange(range), starts[line] + prefix.utf16.count)
        }
        var ranges: [NSRange] = []
        for child in document.children {
            guard let paragraph = child as? Paragraph, paragraph.childCount == 1, let link = paragraph.child(at: 0) as? Markdown.Link,
                  let destination = link.destination, normalizedURL(destination)?.absoluteString == expected,
                  let range = link.range, let endLine = paragraph.range?.upperBound.line else { continue }
            let lineOffset = max(0, endLine - range.upperBound.line)
            guard let start = offset(range.lowerBound, lineOffset: lineOffset), let end = offset(range.upperBound, lineOffset: lineOffset), end >= start else { continue }
            ranges.append(NSRange(location: start, length: end - start))
        }
        let output = NSMutableString(string: body)
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            var start = range.location, end = NSMaxRange(range), following = 0
            while following < 2 && end < output.length {
                if output.character(at: end) == 13 && end + 1 < output.length && output.character(at: end + 1) == 10 { end += 2 }
                else if output.character(at: end) == 10 { end += 1 }
                else { break }
                following += 1
            }
            if following == 0 {
                for _ in 0..<2 {
                    guard start > 0, output.character(at: start - 1) == 10 else { break }
                    start -= 1; if start > 0 && output.character(at: start - 1) == 13 { start -= 1 }
                }
            }
            output.replaceCharacters(in: NSRange(location: start, length: end - start), with: "")
        }
        return output as String
    }
    static func withURL(_ body: String, address: String) -> String {
        guard let url = normalizedURL(address)?.absoluteString else { return body }
        let cleaned = withoutURL(body, address: url), newline = body.contains("\r\n") ? "\r\n" : "\n"
        let text = cleaned as NSString
        guard let first = cleaned.range(of: #"(?m)^ {0,3}#{1,6}[ \t]+[^\r\n]*"#, options: .regularExpression),
              String(cleaned[..<first.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "<" + url + ">" + newline + newline + cleaned
        }
        var insertion = NSMaxRange(text.lineRange(for: NSRange(first, in: cleaned)))
        if insertion == text.length && !cleaned.hasSuffix("\n") {
            return cleaned + newline + newline + "<" + url + ">"
        }
        while insertion < text.length {
            let line = text.lineRange(for: NSRange(location: insertion, length: 0))
            guard text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            insertion = NSMaxRange(line)
        }
        // Only insert bytes owned by the URL card. Removing that paragraph
        // must reproduce the editor buffer exactly, including its final newline.
        return text.replacingCharacters(in: NSRange(location: insertion, length: 0), with: "<" + url + ">" + newline + newline)

    }
}

extension NoteDocument {
    var savedLink: NativeSavedLink? { NativeSavedLink(self) }
    var unfiledSavedLink: Bool { !trashed && path.hasPrefix(".zerus/links/") }
    var regularCollectionNote: Bool { !trashed && !path.hasPrefix(".zerus/") }
}

extension VaultFiles {
    /// The shared index is part of every managed link write/move, including
    /// ordinary editing, deliberate revisions, Trash, restore and filing.
    func includingSavedLinkIndex(_ changes: [VaultFileChange]) throws -> [VaultFileChange] {
        let index = ".zerus/links.json"
        guard !changes.contains(where: { $0.path == index }) else { return changes }
        let links = changes.filter { $0.path.hasPrefix(".zerus/links/") && $0.path.lowercased().hasSuffix(".md") && $0.before != $0.after }
        guard !links.isEmpty else { return changes }
        let bytes = try historyData(index)
        let paths: [String]
        if let bytes {
            guard let values = try JSONSerialization.jsonObject(with: bytes) as? [String] else { throw VaultFailure(message: "The saved-link index uses an unsupported format. Its bytes and your links are preserved.") }
            paths = values
        } else { paths = [] }
        var next = paths
        for link in links {
            if link.after == nil { next.removeAll { $0 == link.path } }
            else if let data = link.after, let text = String(data: data, encoding: .utf8), NativeSavedLink(NoteDocument(path: link.path, content: text, modified: Date())) != nil, !next.contains(link.path) { next.append(link.path) }
        }
        let after = next == paths ? bytes : try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .withoutEscapingSlashes])
        return changes + [.init(path: index, before: bytes, after: after)]
    }

    func createSavedLink(address: String, title: String) throws -> NoteDocument {
        guard let url = NativeSavedLink.normalizedURL(address) else { throw VaultFailure(message: "Enter a valid http or https web address.") }
        let snapshot = try scan()
        if let existing = snapshot.notes.first(where: { !$0.trashed && $0.savedLink?.url == url }) { return existing }
        let id = UUID().uuidString.lowercased(), path = ".zerus/links/" + id + ".md"
        let host = url.host ?? "Link", fallback = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
        var content = "# " + (name.isEmpty ? fallback : name) + "\n\n<" + url.absoluteString + ">\n"
        for (key, value) in [("zerus-id", id), ("zerus-link-id", id), ("zerus-link-url", url.absoluteString)] { content = try NativeFrontmatter(content).setting(key, value: .text(value)) }
        let paths = Set(snapshot.notes.map(\.path)), root = root
        let reads = snapshot.notes.map { VaultFileChange(path: $0.path, before: Data($0.content.utf8), after: Data($0.content.utf8)) }
        try applyTransaction(reads + [.init(path: path, before: nil, after: Data(content.utf8))], validate: {
            guard try Self.notePathInventory(root: root) == paths else { throw VaultFailure(message: "Links or notes changed. Try saving the address again.") }
        })
        return NoteDocument(path: path, content: content, modified: Date())
    }

    func updateSavedLink(_ note: NoteDocument, address: String) throws -> VaultSnapshot {
        guard !note.trashed, let saved = note.savedLink, let url = NativeSavedLink.normalizedURL(address) else { throw VaultFailure(message: "Enter a valid http or https web address.") }
        if saved.url == url { return try scan() }
        let snapshot = try scan()
        guard !snapshot.notes.contains(where: { !$0.trashed && $0.path != note.path && $0.savedLink?.url == url }) else { throw VaultFailure(message: "That address is already saved. Open its existing link instead.") }
        let body = NativeSavedLink.withURL(NativeSavedLink.withoutURL(note.parts.body, address: saved.address), address: url.absoluteString)
        let content = try NativeFrontmatter(note.replacingBody(body)).setting("zerus-link-url", value: .text(url.absoluteString))
        let changes = snapshot.notes.map { item in VaultFileChange(path: item.path, before: Data(item.content.utf8), after: Data((item.path == note.path ? content : item.content).utf8)) }
        guard snapshot.notes.first(where: { $0.path == note.path })?.content == note.content else { throw VaultFailure(message: "This saved link changed outside Zerus. Reload it before updating its address.") }
        let paths = Set(snapshot.notes.map(\.path)), root = root
        try applyTransaction(changes, validate: {
            guard try Self.notePathInventory(root: root) == paths else { throw VaultFailure(message: "Links or notes changed. Reload before updating this address.") }
        })
        return try scan()
    }
}
