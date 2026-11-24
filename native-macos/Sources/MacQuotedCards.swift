import Foundation
import Markdown

/// Quote spelling belongs to the card, independently of its editable body.
/// Original prefixes survive untouched; changed rows keep the same quote depth.
struct MacQuoteContext {
    let prefix: String
    let depth: Int
    let original: String
    let inner: String
    func spelling(_ value: String) -> String {
        if value == inner { return original }
        return MacMarkdownLines(value).lines.map { line in
            line.text.isEmpty && line.ending.isEmpty ? "" : prefix + line.text + line.ending
        }.joined()
    }
}
struct MacQuotedCard {
    let range: NSRange
    let nodeLine: Int
    let quote: MacQuoteContext
    let code: MacCodeBlock?
    let table: MarkdownTable?
}

enum MacQuotedCards {
    // Consume the same optional single whitespace column as cmark. A partially
    // consumed tab leaves virtual spaces in the body instead of losing indent.
    static func strippingPrefix(_ line: String, depth: Int) -> (text: String, prefix: String) {
        let chars = Array(line)
        var index = 0, column = 0, pending = 0
        func peek() -> Character? { pending > 0 ? " " : index < chars.count ? chars[index] : nil }
        func advance() {
            if pending > 0 { pending -= 1; column += 1 }
            else if index < chars.count {
                if chars[index] == "\t" { pending = 4 - column % 4 - 1 }
                index += 1; column += 1
            }
        }
        for _ in 0..<depth {
            let checkpoint = (index, column, pending)
            var indent = 0
            while let next = peek(), next == " " || next == "\t" {
                advance(); indent += 1
                if indent > 3 { break }
            }
            guard indent <= 3, peek() == ">" else { (index, column, pending) = checkpoint; break }
            advance()
            if peek() == " " || peek() == "\t" { advance() }
        }
        let body = String(repeating: " ", count: pending) + String(chars[index...])
        let prefix = pending == 0 && chars[..<index].filter({ $0 == ">" }).count == depth ? String(chars[..<index]) : String(repeating: "> ", count: depth)
        return (body, prefix)
    }
    static func blocks(in source: String, document: Document? = nil) -> [MacQuotedCard] {
        guard source.contains(">") else { return [] }
        let document = document ?? Document(parsing: source), lines = MacMarkdownLines(source)
        var output: [MacQuotedCard] = []
        func walk(_ node: any Markup, depth: Int = 0) {
            if node is BlockQuote { for child in node.children { walk(child, depth: depth + 1) }; return }
            if node is Document { for child in node.children { walk(child) }; return }
            guard depth > 0, node is CodeBlock || node is Markdown.Table, let span = node.range else { return }
            var first = span.lowerBound.line - 1
            let last = min(span.upperBound.line - 1, lines.lines.count - 1)
            guard first >= 0, first <= last else { return }
            if node is Markdown.Table, let parent = node.parent {
                let siblings = Array(parent.children)
                if let index = siblings.firstIndex(where: { $0.range == node.range }), index > 0,
                   let comment = siblings[index - 1] as? HTMLBlock,
                   comment.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!-- zerus-table-widths:"),
                   let start = comment.range?.lowerBound.line { first = start - 1 }
            }
            let outer = lines.fragment(first..<(last + 1), includeLastEnding: false)
            let rows = MacMarkdownLines(outer)
            let inner = rows.lines.map { strippingPrefix($0.text, depth: depth).text + $0.ending }.joined()
            let parsed = Document(parsing: inner)
            let quote = MacQuoteContext(prefix: strippingPrefix(rows.lines[0].text, depth: depth).prefix, depth: depth, original: outer, inner: inner)
            if let code = node as? CodeBlock, let check = parsed.child(at: 0) as? CodeBlock,
               parsed.childCount == 1,
               var block = MacCodeBlock.rootBlocks(in: inner, document: parsed).first {
                let ending = lines.ending(at: first)
                if block.code.newline != ending {
                    let seed = FencedCode(markdown: block.code.markdown, body: block.code.body, info: block.code.info, opening: block.code.opening, fence: block.code.fence, newline: ending, closed: block.code.closed)
                    block = MacCodeBlock(range: block.range, code: seed, indented: block.indented.map { MacIndentedCode(range: $0.range, code: seed, indent: $0.indent) })
                }
                if block.indented != nil || check.code != code.code || block.code.opening.first == " " {
                    // An indented fence strips its opening indentation from
                    // body rows in CommonMark. Use the parser's logical body,
                    // retaining raw source until an edit canonically respells it.
                    var body = code.code
                    if body.hasSuffix("\n") { body.removeLast() }
                    if block.indented == nil { body = MacMarkdownLines.normalized(body, to: block.code.newline) }
                    let logical = FencedCode(markdown: block.code.markdown, body: body, info: block.code.info, opening: block.code.opening.trimmingCharacters(in: .whitespaces), fence: block.code.fence, newline: block.code.newline, closed: block.code.closed)
                    let indented = block.indented.map { MacIndentedCode(range: $0.range, code: logical, indent: "    ") }
                    block = MacCodeBlock(range: block.range, code: logical, indented: indented)
                }
                // Indented ranges can omit trailing blank rows. Use the actual
                // inner token's rows to keep those separators outside the card.
                let count = MacMarkdownLines(block.code.markdown).lines.count
                let end = min(first + count, last + 1)
                let raw = lines.fragment(first..<end, includeLastEnding: false)
                let context = MacQuoteContext(prefix: quote.prefix, depth: depth, original: raw, inner: block.code.markdown)
                output.append(.init(range: NSRange(location: lines.lines[first].offset, length: raw.utf16.count), nodeLine: span.lowerBound.line, quote: context, code: block, table: nil))
            } else if node is Markdown.Table,
                      let table = MacTableBlock.rootBlocks(in: inner, excluding: []).first {
                first += MacMarkdownLines(inner).lines.lastIndex(where: { $0.offset <= table.range.location }) ?? 0
                let count = MacMarkdownLines(table.table.markdown).lines.count, end = min(first + count, last + 1)
                let raw = lines.fragment(first..<end, includeLastEnding: false)
                let context = MacQuoteContext(prefix: strippingPrefix(lines.lines[first].text, depth: depth).prefix, depth: depth, original: raw, inner: table.table.markdown)
                output.append(.init(range: NSRange(location: lines.lines[first].offset, length: raw.utf16.count), nodeLine: span.lowerBound.line, quote: context, code: nil, table: table.table))
            }
        }
        walk(document)
        return output
    }
}
