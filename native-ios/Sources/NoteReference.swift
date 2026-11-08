import Foundation

/// A native link carries the same target and optional label as the Markdown.
/// Editing URLs stay private; vault files use wikilinks or shared fragment links.
struct NoteReference: Equatable, Identifiable {
    var id: String { target }
    let target: String
    let label: String
    let explicitLabel: Bool
    init(target: String, label: String, explicitLabel: Bool) {
        self.target = target; self.label = label; self.explicitLabel = explicitLabel
    }

    init?(wikilink: String) {
        guard wikilink.hasPrefix("[["), wikilink.hasSuffix("]]"), !wikilink.contains("\n") else { return nil }
        let parts = wikilink.dropFirst(2).dropLast(2).split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first else { return nil }
        let target = first.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        self.target = target
        explicitLabel = parts.count == 2
        label = explicitLabel ? String(parts[1]) : target
    }

    init?(url: URL) {
        let prefix = "#zerus-note:"
        if url.scheme == nil, url.relativeString.hasPrefix(prefix),
           let decoded = String(url.relativeString.dropFirst(prefix.count)).removingPercentEncoding {
            let parts = decoded.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard let target = parts.first, !target.isEmpty else { return nil }
            self.init(target: String(target), label: parts.count == 2 ? String(parts[1]) : String(target), explicitLabel: parts.count == 2)
            return
        }
        guard url.scheme == "zerus-note", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = components.queryItems?.first(where: { $0.name == "target" })?.value, !target.isEmpty else { return nil }
        self.init(target: target, label: components.queryItems?.first(where: { $0.name == "label" })?.value ?? target,
                  explicitLabel: components.queryItems?.first(where: { $0.name == "alias" })?.value == "1")
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "zerus-note"; components.host = "open"
        components.queryItems = [URLQueryItem(name: "target", value: target), URLQueryItem(name: "label", value: label), URLQueryItem(name: "alias", value: explicitLabel ? "1" : "0")]
        return components.url!
    }
    func fragmentDestination(label: String) -> String {
        "#zerus-note:" + (target + "|" + label).addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }

    func markdown(label edited: String, formattedLabel: String? = nil) -> String {
        if formattedLabel != nil || target.rangeOfCharacter(from: CharacterSet(charactersIn: "[]|\\\r\n")) != nil || edited.rangeOfCharacter(from: CharacterSet(charactersIn: "[]|\\\r\n<>&")) != nil {
            let escaped = formattedLabel ?? edited.replacingOccurrences(of: #"([\\\[\]*_`~<>&])"#, with: #"\\$1"#, options: .regularExpression)
            return "[" + escaped + "](" + fragmentDestination(label: edited) + ")"
        }
        if !explicitLabel && edited == target { return "[[" + target + "]]" }
        return "[[" + target + "|" + edited + "]]"
    }

    private func exactTargets(in candidates: [NoteDocument]) -> [NoteDocument] {
        if target.hasPrefix("zerus:") { return candidates.filter { $0.stableID == String(target.dropFirst(6)) } }
        let normalized = target.lowercased().replacingOccurrences(of: "\\", with: "/")
        let paths = candidates.filter { $0.path.lowercased() == normalized || ($0.path as NSString).deletingPathExtension.lowercased() == normalized }
        return paths.isEmpty ? candidates.filter { $0.title.localizedCaseInsensitiveCompare(target) == .orderedSame } : paths
    }

    func targets(in notes: [NoteDocument], includeTrash: Bool = false, includeHeadingFragments: Bool = false) -> [NoteDocument] {
        let candidates = notes.filter { includeTrash || !$0.trashed }
        let direct = exactTargets(in: candidates)
        if !direct.isEmpty || !includeHeadingFragments { return direct }
        for index in target.indices.reversed() where target[index] == "#" {
            let base = String(target[..<index]); guard !base.isEmpty else { continue }
            let found = NoteReference(target: base, label: label, explicitLabel: explicitLabel).exactTargets(in: candidates)
            if !found.isEmpty { return found }
        }
        return []
    }
    func heading(in note: NoteDocument) -> String? {
        if !exactTargets(in: [note]).isEmpty { return nil }
        for index in target.indices.reversed() where target[index] == "#" {
            let base = String(target[..<index]); guard !base.isEmpty else { continue }
            if !NoteReference(target: base, label: label, explicitLabel: explicitLabel).exactTargets(in: [note]).isEmpty { return String(target[target.index(after: index)...]) }
        }
        return nil
    }
    static func references(in source: String) -> [NoteReference] {
        let codes = FencedCode.blocks(in: source), tables = MarkdownTable.blocks(in: source, excluding: codes.map(\.range))
        let ranges = (codes.map(\.range) + tables.map(\.range)).sorted { $0.location < $1.location }
        let text = source as NSString
        var parts = tables.flatMap { $0.table.rows.flatMap { $0 } }, cursor = 0
        for range in ranges {
            parts.append(text.substring(with: NSRange(location: cursor, length: range.location - cursor))); cursor = NSMaxRange(range)
        }
        parts.append(text.substring(from: cursor))
        var targets = Set<String>()
        return parts.flatMap { part -> [NoteReference] in
            guard let parsed = try? AttributedString(markdown: inlineMarkdown(part), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return [] }
            return parsed.runs.compactMap { run in
                guard let url = run.link, let reference = NoteReference(url: url), targets.insert(reference.target).inserted else { return nil }
                return reference
            }
        }
    }

    static func inlineMarkdown(_ source: String) -> String {
        transform(source) { reference in
            let escaped = reference.label.replacingOccurrences(of: #"([\\\[\]*_`~<>&])"#, with: #"\\$1"#, options: .regularExpression)
            return "[" + escaped + "](" + reference.url.absoluteString + ")"
        }
    }

    static func retarget(_ source: String, from reference: NoteReference, to stableID: String, heading: String? = nil) -> String {
        let edits: [(MarkdownMoveLinks.Link, String)] = ((try? MarkdownMoveLinks.links(in: source)) ?? []).compactMap { link in
            let candidate: NoteReference?
            switch link.kind {
            case .wiki: candidate = NoteReference(wikilink: link.value)
            case .destination: candidate = URL(string: link.value).flatMap(NoteReference.init(url:))
            case .html: candidate = nil
            }
            guard let candidate, candidate.target == reference.target else { return nil }
            let updated = NoteReference(target: "zerus:" + stableID + (heading.map { "#" + $0 } ?? ""), label: candidate.label, explicitLabel: true)
            if case .wiki = link.kind { return (link, updated.markdown(label: candidate.label)) }
            return (link, updated.fragmentDestination(label: candidate.label))
        }
        return MarkdownMoveLinks.replacing(source, edits: edits)
    }

    private static func transform(_ source: String, replacement: (NoteReference) -> String?) -> String {
        var output = "", cursor = source.startIndex
        while cursor < source.endIndex {
            let next = source.index(after: cursor)
            if source[cursor] == "\\", next < source.endIndex {
                output += source[cursor...next]; cursor = source.index(after: next); continue
            }
            if source[cursor] == "`" {
                var end = next
                while end < source.endIndex && source[end] == "`" { end = source.index(after: end) }
                let delimiter = String(source[cursor..<end])
                if let closing = source.range(of: delimiter, range: end..<source.endIndex) {
                    output += source[cursor..<closing.upperBound]; cursor = closing.upperBound; continue
                }
                output += delimiter; cursor = end; continue
            }
            if source[cursor...].hasPrefix("[["), let end = source.range(of: "]]", range: next..<source.endIndex),
               let reference = NoteReference(wikilink: String(source[cursor..<end.upperBound])) {
                output += replacement(reference) ?? String(source[cursor..<end.upperBound])
                cursor = end.upperBound; continue
            }
            output.append(source[cursor]); cursor = next
        }
        return output
    }
}
