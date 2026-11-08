import Foundation
import Markdown

/// Source ranges, rather than a Markdown serialization, keep a folder move
/// from changing unrelated prose, table padding, captions, or line endings.
enum MarkdownMoveLinks {
    enum Kind { case destination, html, wiki(table: Bool) }
    struct Link {
        let range: NSRange
        let value: String
        let kind: Kind
        func replacement(_ value: String) -> String {
            switch kind {
            case .destination: return value
            case .html: return value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
            case .wiki(let table): return table ? MarkdownTable.escapePipes(value) : value
            }
        }
    }
    static func replacing(_ source: String, edits: [(Link, String)]) -> String {
        let output = NSMutableString(string: source)
        for (link, value) in edits.sorted(by: { $0.0.range.location > $1.0.range.location }) {
            output.replaceCharacters(in: link.range, with: link.replacement(value))
        }
        return output as String
    }
    static func links(in source: String) throws -> [Link] {
        let text = source as NSString, length = text.length
        let parsed = Document(parsing: source)
        var code = [Bool](repeating: false, count: length), masked = code, rendered = code
        var lines: [NSRange] = [], position = 0
        while position < length { let line = text.lineRange(for: NSRange(location: position, length: 0)); lines.append(line); position = NSMaxRange(line) }
        func mark(_ range: NSRange, in mask: inout [Bool]) {
            guard range.location != NSNotFound else { return }
            for index in max(0, range.location)..<min(length, NSMaxRange(range)) { mask[index] = true }
        }
        func sourceRange(_ origin: SourceRange, lineOffset: Int) -> NSRange? {
            guard origin.lowerBound.line + lineOffset > 0, origin.upperBound.line >= origin.lowerBound.line,
                  origin.lowerBound.line + lineOffset <= lines.count else { return nil }
            func offset(_ location: SourceLocation) -> Int {
                guard location.line + lineOffset <= lines.count else { return length }
                let range = lines[location.line + lineOffset - 1], value = text.substring(with: range)
                var bytes = 0, units = 0
                for scalar in value.unicodeScalars {
                    if bytes >= location.column - 1 { break }
                    bytes += scalar.utf8.count; units += scalar.utf16.count
                }
                return min(NSMaxRange(range), range.location + units)
            }
            let start = offset(origin.lowerBound), end = offset(origin.upperBound)
            return end >= start ? NSRange(location: start, length: end - start) : nil
        }
        // cmark removes leading reference definitions before parsing a
        // paragraph's inline children. Its block bounds still name the original
        // lines; reconcile the children against the block's unchanged end line.
        // Only source bytes are edited, never a Markdown reserialization.
        func visit(_ node: any Markup, lineOffset: Int = 0, imageLabel: Bool = false) {
            if let origin = node.range, let range = sourceRange(origin, lineOffset: lineOffset) {
                if node.childCount == 0 { mark(range, in: &rendered) }
                if imageLabel { mark(range, in: &masked) }
                if node is CodeBlock || node is InlineCode { mark(range, in: &code); mark(range, in: &masked) }
                if node is HTMLBlock || node is InlineHTML { mark(range, in: &masked) }
            }
            var childOffset = lineOffset
            if node is Paragraph, let end = node.range?.upperBound.line, let inlineEnd = node.children.compactMap({ $0.range?.upperBound.line }).max() {
                childOffset += max(0, end - inlineEnd)
            }
            for child in node.children { visit(child, lineOffset: childOffset, imageLabel: imageLabel || node is Markdown.Image) }
        }
        visit(parsed)
        func escaped(_ index: Int) -> Bool {
            var cursor = index - 1, count = 0
            while cursor >= 0 && text.character(at: cursor) == 92 { count += 1; cursor -= 1 }
            return count % 2 == 1
        }
        var links: [Link] = []
        // HTML destinations are independent of Markdown interpretation. Content
        // of comments and literal HTML elements is never treated as Markdown.
        let tag = try NSRegularExpression(pattern: #"(?is)<!--.*?(?:-->|$)|<\s*(/?)\s*([a-z][a-z0-9:-]*)\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>"#)

        var literal: String?
        for match in tag.matches(in: source, range: NSRange(location: 0, length: length)) {
            guard !code[match.range.location], !escaped(match.range.location) else { continue }
            let markup = text.substring(with: match.range)
            if markup.hasPrefix("<!--") { mark(match.range, in: &masked); continue }
            let name = text.substring(with: match.range(at: 2)).lowercased(), closing = match.range(at: 1).length > 0
            if let active = literal {
                mark(match.range, in: &masked)
                if closing && name == active { literal = nil }
                continue
            }
            mark(match.range, in: &masked)
            guard !closing else { continue }
            let allowed: Set<String>
            switch name {
            case "a", "link": allowed = ["href"]
            case "img", "source": allowed = ["src", "srcset"]
            case "video": allowed = ["src", "poster"]
            case "audio", "track", "embed", "iframe", "script", "input": allowed = ["src"]
            case "object": allowed = ["data"]
            default: allowed = []
            }
            // Lex complete attributes so data-src and text such as
            // alt="src='example.png'" cannot become destinations.
            var attributes: [(String, NSRange)] = [], position = NSMaxRange(match.range(at: 2))
            while position < NSMaxRange(match.range) {
                while position < NSMaxRange(match.range) && [9, 10, 12, 13, 32, 47].contains(text.character(at: position)) { position += 1 }
                let beginning = position
                while position < NSMaxRange(match.range) && ![9, 10, 12, 13, 32, 47, 61, 62].contains(text.character(at: position)) { position += 1 }
                guard position > beginning else { break }
                let key = text.substring(with: NSRange(location: beginning, length: position - beginning)).lowercased()
                while position < NSMaxRange(match.range) && [9, 10, 12, 13, 32].contains(text.character(at: position)) { position += 1 }
                guard position < NSMaxRange(match.range), text.character(at: position) == 61 else { continue }
                position += 1
                while position < NSMaxRange(match.range) && [9, 10, 12, 13, 32].contains(text.character(at: position)) { position += 1 }
                guard position < NSMaxRange(match.range) else { break }
                let quote = text.character(at: position), quoted = quote == 34 || quote == 39
                if quoted { position += 1 }
                let start = position
                while position < NSMaxRange(match.range) && (quoted ? text.character(at: position) != quote : ![9, 10, 12, 13, 32, 62].contains(text.character(at: position))) { position += 1 }
                attributes.append((key, NSRange(location: start, length: position - start)))
                if quoted { position += 1 }
            }
            for (key, range) in attributes where allowed.contains(key) {
                if key == "srcset" {
                    // A URL token may contain commas (notably a data URL). Only
                    // whitespace ends it; trailing commas separate candidates.
                    var offset = range.location
                    while offset < NSMaxRange(range) {
                        while offset < NSMaxRange(range) && ([9, 10, 12, 13, 32].contains(text.character(at: offset)) || text.character(at: offset) == 44) { offset += 1 }
                        let start = offset
                        while offset < NSMaxRange(range) && ![9, 10, 13, 32].contains(text.character(at: offset)) { offset += 1 }
                        var end = offset
                        while end > start && text.character(at: end - 1) == 44 { end -= 1 }
                        if end > start { let urlRange = NSRange(location: start, length: end - start); links.append(Link(range: urlRange, value: htmlDecoded(text.substring(with: urlRange)), kind: .html)) }
                        if end != offset { continue }
                        var depth = 0
                        while offset < NSMaxRange(range) {
                            let character = text.character(at: offset); offset += 1
                            if character == 40 { depth += 1 }; if character == 41 { depth -= 1 }; if character == 44 && depth == 0 { break }
                        }
                    }
                } else { links.append(Link(range: range, value: htmlDecoded(text.substring(with: range)), kind: .html)) }
            }
            if ["pre", "code", "script", "style", "textarea"].contains(name) {
                literal = name
                let closing = text.range(of: "</" + name, options: .caseInsensitive, range: NSRange(location: NSMaxRange(match.range), length: length - NSMaxRange(match.range)))
                mark(NSRange(location: NSMaxRange(match.range), length: (closing.location == NSNotFound ? length : closing.location) - NSMaxRange(match.range)), in: &masked)
            }
        }
        let tables = MarkdownTable.blocks(in: source, excluding: FencedCode.blocks(in: source).map(\.range)).map(\.range)
        func destination(at start: Int) -> NSRange? {
            var beginning = start
            while beginning < length && [9, 10, 13, 32].contains(text.character(at: beginning)) { beginning += 1 }
            let angle = beginning < length && text.character(at: beginning) == 60
            if angle { beginning += 1 }
            var end = beginning, parentheses = 0
            while end < length {
                let next = text.character(at: end)
                if next == 92 { end += 2; continue }
                if angle { if next == 62 { break } }
                else {
                    if next == 40 { parentheses += 1 }
                    if next == 41 { if parentheses == 0 { break }; parentheses -= 1 }
                    if [9, 10, 13, 32].contains(next) { break }
                }
                end += 1
            }
            guard end > beginning && end < length else { return nil }
            return NSRange(location: beginning, length: end - beginning)
        }
        func scan(_ bounds: NSRange, depth: Int = 0) {
            guard depth < 32 else { return }
            var index = bounds.location
            while index < NSMaxRange(bounds) {
                if masked[index] { index += 1; continue }
                let character = text.character(at: index)
                if character == 92 { index += 2; continue }
                guard character == 91 else { index += 1; continue }
                if index + 1 < NSMaxRange(bounds), text.character(at: index + 1) == 91 {
                    let closing = text.range(of: "]]", range: NSRange(location: index + 2, length: NSMaxRange(bounds) - index - 2))
                    if closing.location != NSNotFound {
                        let range = NSRange(location: index, length: NSMaxRange(closing) - index), table = tables.contains { NSLocationInRange(index, $0) }
                        let value = text.substring(with: range), normalized = table ? value.replacingOccurrences(of: "\\|", with: "|") : value
                        if NoteReference(wikilink: normalized) != nil, !(range.location..<NSMaxRange(range)).contains(where: { masked[$0] }) {
                            links.append(Link(range: range, value: normalized, kind: .wiki(table: table))); index = NSMaxRange(range); continue
                        }
                    }
                }
                let image = index > 0 && text.character(at: index - 1) == 33 && !escaped(index - 1)
                var labelEnd = index + 1, brackets = 1
                while labelEnd < NSMaxRange(bounds) && brackets > 0 {
                    if text.character(at: labelEnd) == 92 { labelEnd += 2; continue }
                    if text.character(at: labelEnd) == 91 { brackets += 1 }
                    if text.character(at: labelEnd) == 93 { brackets -= 1 }
                    labelEnd += 1
                }
                guard brackets == 0, labelEnd < NSMaxRange(bounds) else { index += 1; continue }
                if text.character(at: labelEnd) == 58, !rendered[index], let range = destination(at: labelEnd + 1) {
                    let value = text.substring(with: range)
                    // Foundation already excluded a valid reference definition
                    // from rendered text; decode its destination using a real link.
                    if let url = markdownURL(value) { links.append(Link(range: range, value: url.relativeString, kind: .destination)) }
                    index = NSMaxRange(range); continue
                }
                guard text.character(at: labelEnd) == 40, let range = destination(at: labelEnd + 1) else { index += 1; continue }
                var close = NSMaxRange(range), quote: unichar?, parentheses = 0
                if text.character(at: close) == 62 { close += 1 }
                while close < NSMaxRange(bounds) {
                    let next = text.character(at: close)
                    if next == 92 { close += 2; continue }
                    if let active = quote { if next == active { quote = nil } }
                    else if next == 34 || next == 39 { quote = next }
                    else if next == 40 { parentheses += 1 }
                    else if next == 41 { if parentheses == 0 { break }; parentheses -= 1 }
                    close += 1
                }
                guard close < NSMaxRange(bounds) else { index = labelEnd; continue }
                let start = image ? index - 1 : index, markup = text.substring(with: NSRange(location: start, length: close + 1 - start))
                let attributed = try? AttributedString(markdown: markup, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
                let expected = markdownURL(text.substring(with: range))
                if let url = attributed?.runs.compactMap({ image ? $0.imageURL : $0.link }).first(where: { $0 == expected }) {
                    links.append(Link(range: range, value: url.relativeString, kind: .destination))
                    if !image { scan(NSRange(location: index + 1, length: labelEnd - index - 2), depth: depth + 1) }
                    index = close + 1
                } else { index += 1 }
            }
        }
        scan(NSRange(location: 0, length: length))
        return links.sorted { $0.range.location < $1.range.location }
    }
    private static func markdownURL(_ value: String) -> URL? {
        (try? AttributedString(markdown: "[Resource](<" + value + ">)", options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))?.runs.compactMap(\.link).first
    }
    private static func htmlDecoded(_ value: String) -> String {
        let text = value as NSString, output = NSMutableString(string: value)
        let regex = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|amp|quot|apos|lt|gt);"#)
        for match in regex.matches(in: value, range: NSRange(location: 0, length: text.length)).reversed() {
            let entity = text.substring(with: match.range(at: 1)), decoded: String?
            if entity.hasPrefix("#") {
                let hex = entity.hasPrefix("#x"), number = UInt32(entity.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10)
                decoded = number.flatMap(UnicodeScalar.init).map(String.init)
            } else { decoded = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">"][entity] }
            if let decoded { output.replaceCharacters(in: match.range, with: decoded) }
        }
        return output as String
    }
}
