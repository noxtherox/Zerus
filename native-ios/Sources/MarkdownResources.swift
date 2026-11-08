import Foundation

/// Only actual inline destinations are rewritten. Code, escaped examples, link
/// labels, titles, and remote URLs retain their original text.
enum MarkdownResources {
    static func localReferences(in source: String, includeNoteFiles: Bool = false) -> [String] {
        var references = Set<String>()
        _ = transform(source) { url, image in
            if isLocalAsset(url, image: image, includeNoteFiles: includeNoteFiles) { references.insert(url.relativeString) }
            return nil
        }
        return references.sorted()
    }

    static func attachmentReferences(in source: String) -> [String] {
        var references = Set<String>()
        _ = transform(source) { url, _ in
            if url.scheme?.lowercased() == "zerus-attachment" { references.insert(url.absoluteString) }
            return nil
        }
        return references.sorted()
    }

    static func replacing(_ source: String, references: [String: String]) -> String {
        transform(source) { url, _ in references[url.relativeString] }
    }

    static func encodedPath(_ path: String, preservingSuffixOf reference: String) -> String {
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/-._~")
        var result = path.addingPercentEncoding(withAllowedCharacters: safe) ?? path
        if let parts = URLComponents(string: reference) {
            if let query = parts.percentEncodedQuery { result += "?" + query }
            if let fragment = parts.percentEncodedFragment { result += "#" + fragment }
        }
        return result
    }

    private static func isLocalAsset(_ url: URL, image: Bool, includeNoteFiles: Bool) -> Bool {
        guard url.scheme == nil, !url.relativePath.isEmpty, !url.relativePath.hasPrefix("/") else { return false }
        // Markdown-note destinations are connections, not attachment copies.
        return image || includeNoteFiles || !(url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown")
    }

    private static func transform(_ source: String, replacement: (URL, Bool) -> String?) -> String {
        let codes = FencedCode.blocks(in: source)
        let tables = MarkdownTable.blocks(in: source, excluding: codes.map(\.range))
        var blocks = codes.map { ($0.range, $0.code.markdown) }
        for block in tables {
            var table = block.table
            for row in table.rows.indices {
                for column in table.rows[row].indices { table.rows[row][column] = inline(table.rows[row][column], replacement: replacement) }
            }
            blocks.append((block.range, table.markdown))
        }
        let text = source as NSString
        var output = "", cursor = 0
        for (range, value) in blocks.sorted(by: { $0.0.location < $1.0.location }) {
            output += inline(text.substring(with: NSRange(location: cursor, length: range.location - cursor)), replacement: replacement) + value
            cursor = NSMaxRange(range)
        }
        return output + inline(text.substring(from: cursor), replacement: replacement)
    }

    private static func inline(_ source: String, depth: Int = 0, replacement: (URL, Bool) -> String?) -> String {
        guard depth < 32 else { return source }
        let text = source as NSString, output = NSMutableString(string: source)
        var edits: [(NSRange, String)] = [], cursor = 0
        func escaped(_ index: Int) -> Bool {
            var position = index - 1, count = 0
            while position >= 0 && text.character(at: position) == 92 { count += 1; position -= 1 }
            return count % 2 == 1
        }
        while cursor < text.length {
            let character = text.character(at: cursor)
            if character == 92 { cursor += 2; continue }
            if character == 96 {
                var end = cursor + 1
                while end < text.length && text.character(at: end) == 96 { end += 1 }
                let delimiter = text.substring(with: NSRange(location: cursor, length: end - cursor))
                let closing = text.range(of: delimiter, range: NSRange(location: end, length: text.length - end))
                cursor = closing.location == NSNotFound ? end : NSMaxRange(closing)
                continue
            }
            guard character == 91 else { cursor += 1; continue }
            let image = cursor > 0 && text.character(at: cursor - 1) == 33 && !escaped(cursor - 1)
            let beginning = image ? cursor - 1 : cursor
            var labelEnd = cursor + 1, brackets = 1
            while labelEnd < text.length && brackets > 0 {
                let next = text.character(at: labelEnd)
                if next == 92 { labelEnd += 2; continue }
                if next == 91 { brackets += 1 }
                if next == 93 { brackets -= 1 }
                labelEnd += 1
            }
            guard brackets == 0, labelEnd < text.length, text.character(at: labelEnd) == 40 else { cursor += 1; continue }
            let labelRange = NSRange(location: cursor + 1, length: labelEnd - cursor - 2)
            let label = text.substring(with: labelRange)
            var start = labelEnd + 1
            while start < text.length && [9, 10, 13, 32].contains(text.character(at: start)) { start += 1 }
            let angled = start < text.length && text.character(at: start) == 60
            if angled { start += 1 }
            var end = start, parentheses = 0
            while end < text.length {
                let next = text.character(at: end)
                if next == 92 { end += 2; continue }
                if angled { if next == 62 { break } }
                else {
                    if next == 40 { parentheses += 1 }
                    if next == 41 { if parentheses == 0 { break }; parentheses -= 1 }
                    if [9, 10, 13, 32].contains(next) { break }
                }
                end += 1
            }
            guard end > start && end < text.length else { cursor = labelEnd; continue }
            var close = angled ? end + 1 : end
            var quote: unichar?, depth = 0
            while close < text.length {
                let next = text.character(at: close)
                if next == 92 { close += 2; continue }
                if let active = quote { if next == active { quote = nil } }
                else if next == 34 || next == 39 { quote = next }
                else if next == 40 { depth += 1 }
                else if next == 41 { if depth == 0 { break }; depth -= 1 }
                close += 1
            }
            guard close < text.length else { cursor = labelEnd; continue }
            let markup = text.substring(with: NSRange(location: beginning, length: close + 1 - beginning))
            let destination = "[Resource]" + text.substring(with: NSRange(location: labelEnd, length: close + 1 - labelEnd))
            let expected = (try? AttributedString(markdown: destination, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))?.runs.compactMap(\.link).first
            let parsed = try? AttributedString(markdown: markup, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            let url = parsed?.runs.compactMap({ image ? $0.imageURL : $0.link }).first(where: { $0 == expected })
            // An image's alt text is descriptive text. A Markdown-looking link
            // inside that label must not copy an unrelated local file.
            if !image || url == nil {
                let nested = inline(label, depth: depth + 1, replacement: replacement)
                if nested != label { edits.append((labelRange, nested)) }
            }
            if let url, let value = replacement(url, image) {
                edits.append((NSRange(location: start, length: end - start), value))
            }
            cursor = close + 1
        }
        for (range, value) in edits.reversed() { output.replaceCharacters(in: range, with: value) }
        return output as String
    }
}
