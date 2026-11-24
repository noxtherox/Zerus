import AppKit
import Markdown

/// Parser-owned positions and prefixes shared by Source sheets and native
/// card placement. Native item contexts provide the live editing identities.
struct MacListCardOwner {
    let line: Int
    let column: Int
    let prefix: String
    var key: String { "\(line):\(column)" }
}
struct MacListCardSource {
    let range: NSRange
    let ownerLine: Int
    let ownerColumn: Int
    let ownerIndex: Int
    let signature: [String]
    let firstPrefix: String
    let continuationPrefix: String
    let original: String
    let inner: String
    let ownerSuffix: String
    let owners: [MacListCardOwner]
    func spelling(_ value: String) -> String {
        if value.utf8.elementsEqual(inner.utf8) { return original }
        return MacMarkdownLines(value).lines.enumerated().map { index, line in
            line.text.isEmpty && line.ending.isEmpty ? "" : (index == 0 ? firstPrefix : continuationPrefix) + line.text + line.ending
        }.joined()
    }
    func accepts(_ inner: String, in source: String, replacement: String, table: Bool) -> Bool {
        let candidate = (source as NSString).replacingCharacters(in: range, with: replacement)
        guard MacListCards.parents(in: candidate) == MacListCards.parents(in: source),
              let card = MacListCards.blocks(in: candidate).first(where: { $0.source.range.location == range.location }),
              card.source.ownerIndex == ownerIndex, card.source.signature == signature else { return false }
        if table {
            guard let expected = MacTableBlock.rootBlocks(in: inner, excluding: []).first?.table, let actual = card.table else { return false }
            return actual.rows == expected.rows && actual.alignments == expected.alignments && actual.widths == expected.widths
        }
        guard let expected = Document(parsing: inner).child(at: 0) as? CodeBlock else { return false }
        return card.body == expected.code
    }
}
struct MacListOwnedCard {
    let source: MacListCardSource
    let code: MacCodeBlock?
    let body: String?
    let table: MarkdownTable?
    let rule: String?
}

enum MacListCards {
    private struct Cursor {
        let chars: [Character]
        var index = 0, column = 0, pending = 0
        init(_ line: String) { chars = Array(line) }
        var peek: Character? { pending > 0 ? " " : index < chars.count ? chars[index] : nil }
        var whitespace: Bool { peek == " " || peek == "\t" }
        mutating func advance() {
            if pending > 0 { pending -= 1; column += 1 }
            else if index < chars.count {
                if chars[index] == "\t" { pending = 4 - column % 4 - 1 }
                index += 1; column += 1
            }
        }
        mutating func spaces(_ count: Int) -> Bool {
            let before = self
            var consumed = 0
            while consumed < count, whitespace { advance(); consumed += 1 }
            if consumed < count, peek != nil { self = before; return false }
            return true
        }
        var remainder: String { String(repeating: " ", count: pending) + String(chars[index...]) }
    }
    private enum Step {
        case quote
        case item(line: Int, column: Int, ordinal: Int, indent: Int, marker: String, padding: Int)
        var signature: String {
            switch self { case .quote: return "q"; case .item(_, _, _, let indent, let marker, let padding): return "i:\(indent):\(marker):\(padding)" }
        }
        var continuation: String {
            switch self { case .quote: return "> "; case .item(_, _, _, let indent, let marker, let padding): return String(repeating: " ", count: indent + marker.count + padding) }
        }
        func prefix(on line: Int) -> String {
            if case .item(let start, _, _, let indent, let marker, let padding) = self, start == line { return String(repeating: " ", count: indent) + marker + String(repeating: " ", count: padding) }
            return continuation
        }
        func consume(_ cursor: inout Cursor, on line: Int) -> Bool {
            switch self {
            case .quote:
                var next = cursor, indent = 0
                while next.whitespace, indent < 4 { next.advance(); indent += 1 }
                guard indent <= 3, next.peek == ">" else { return false }
                next.advance(); if next.whitespace { next.advance() }; cursor = next; return true
            case .item(let start, _, _, let indent, let marker, let padding):
                guard start == line else { return cursor.spaces(indent + marker.count + padding) }
                var next = cursor
                guard next.spaces(indent) else { return false }
                for character in marker { guard next.peek == character else { return false }; next.advance() }
                guard next.spaces(padding) else { return false }
                cursor = next; return true
            }
        }
    }
    private static let marker = try! NSRegularExpression(pattern: #"^(?:[-+*]|[0-9]{1,9}[.)])(?=[ \t]|$)"#)
    static func parents(in source: String) -> [Int?] {
        var result: [Int?] = []
        func walk(_ node: any Markup, owner: Int? = nil) {
            var next = owner
            if node is ListItem { next = result.count; result.append(owner) }
            for child in node.children { walk(child, owner: next) }
        }
        walk(Document(parsing: source)); return result
    }
    static func blocks(in source: String, document: Document? = nil) -> [MacListOwnedCard] {
        let document = document ?? Document(parsing: source), lines = MacMarkdownLines(source)
        var result: [MacListOwnedCard] = [], ordinal = 0
        var taskSyntax: [Int: String] = [:]
        func item(_ node: any Markup, path: [Step], ordinal: Int) -> Step? {
            guard let start = node.range?.lowerBound, lines.lines.indices.contains(start.line - 1) else { return nil }
            let text = lines.lines[start.line - 1].text
            guard let before = String(bytes: text.utf8.prefix(start.column - 1), encoding: .utf8) else { return nil }
            let position = before.count
            var cursor = Cursor(text)
            for step in path { if !step.consume(&cursor, on: start.line) { return nil } }
            let base = cursor.column
            while cursor.index < position || cursor.pending > 0 { guard cursor.whitespace else { return nil }; cursor.advance() }
            guard cursor.index == position else { return nil }
            let tail = String(cursor.chars[cursor.index..<min(cursor.chars.count, cursor.index + 12)]), raw = tail as NSString
            guard let match = marker.firstMatch(in: tail, range: NSRange(location: 0, length: raw.length)) else { return nil }
            let token = raw.substring(with: match.range), indent = cursor.column - base
            for _ in token { cursor.advance() }
            var check = cursor, count = 0
            while check.whitespace, count <= 5 { check.advance(); count += 1 }
            let padding = count >= 1 && count <= 4 && check.peek != nil ? count : 1
            return .item(line: start.line, column: start.column, ordinal: ordinal, indent: indent, marker: token, padding: padding)
        }
        func walk(_ node: any Markup, path: [Step] = []) {
            if node is BlockQuote { for child in node.children { walk(child, path: path + [.quote]) }; return }
            if node is ListItem {
                let id = ordinal; ordinal += 1
                if node.child(at: 0) is Paragraph, let start = node.range?.lowerBound,
                   lines.lines.indices.contains(start.line - 1),
                   let tail = String(bytes: lines.lines[start.line - 1].text.utf8.dropFirst(start.column - 1), encoding: .utf8),
                   let prefix = MacBlockPrefix(tail), prefix.checklist {
                    // Task syntax belongs to a paragraph head, never to literal
                    // bracket text inside an item-owned indented code block.
                    taskSyntax[id] = String(prefix.marker.dropFirst(prefix.listPadding))
                }
                guard let step = item(node, path: path, ordinal: id) else { return }
                for child in node.children { walk(child, path: path + [step]) }; return
            }
            if node is Document || node is OrderedList || node is UnorderedList { for child in node.children { walk(child, path: path) }; return }
            guard node is CodeBlock || node is Markdown.Table || node is ThematicBreak, let span = node.range,
                  let owner = path.last(where: { if case .item = $0 { return true }; return false }),
                  case .item(let ownerLine, let ownerColumn, let ownerIndex, _, _, _) = owner else { return }
            var first = span.lowerBound.line - 1
            // A thematic break occupies one physical line. cmark can report
            // its upper bound on the following blank line; that gap belongs to
            // the next body block and must not be consumed with the card.
            let last = node is ThematicBreak ? first : min(span.upperBound.line - 1, lines.lines.count - 1)
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
            let unwrapped = rows.lines.enumerated().map { index, row -> String in
                var cursor = Cursor(row.text)
                for step in path { if !step.consume(&cursor, on: first + index + 1) { break } }
                return cursor.remainder + row.ending
            }.joined()
            let innerDoc = Document(parsing: unwrapped)
            var code: MacCodeBlock?, table: MarkdownTable?, rule: String?, inner: String
            if let node = node as? CodeBlock,
               let block = MacCodeBlock.rootBlocks(in: unwrapped, document: innerDoc).first, block.range.location == 0 {
                var body = node.code; if body.hasSuffix("\n") { body.removeLast() }
                let ending = lines.ending(at: first)
                if block.indented == nil { body = MacMarkdownLines.normalized(body, to: ending) }
                let logical = FencedCode(markdown: block.code.markdown, body: body, info: block.code.info, opening: block.code.opening.trimmingCharacters(in: .whitespaces), fence: block.code.fence, newline: ending, closed: block.code.closed)
                code = .init(range: block.range, code: logical, indented: block.indented.map { MacIndentedCode(range: $0.range, code: logical, indent: "    ") })
                inner = logical.markdown
            } else if node is Markdown.Table, let block = MacTableBlock.rootBlocks(in: unwrapped, excluding: []).first {
                // GFM can report the preceding paragraph's line as a table's
                // start when its header interrupts that paragraph. The source
                // table parser identifies the real header (and width marker).
                first += MacMarkdownLines(unwrapped).lines.lastIndex(where: { $0.offset <= block.range.location }) ?? 0
                table = block.table; inner = block.table.markdown
            } else if node is ThematicBreak, innerDoc.childCount == 1, innerDoc.child(at: 0) is ThematicBreak {
                rule = unwrapped; inner = unwrapped
            } else { return }
            let count = MacMarkdownLines(inner).lines.count, end = min(first + count, last + 1)
            let raw = lines.fragment(first..<end, includeLastEnding: false)
            let range = NSRange(location: lines.lines[first].offset, length: raw.utf16.count)
            let owners = path.enumerated().compactMap { index, step -> MacListCardOwner? in
                guard case .item(let line, let column, let ordinal, let indent, let marker, let padding) = step else { return nil }
                let prefix = path[..<index].map(\.continuation).joined() + String(repeating: " ", count: indent) + marker + String(repeating: " ", count: padding) + (taskSyntax[ordinal] ?? "")
                return MacListCardOwner(line: line, column: column, prefix: prefix)
            }
            let context = MacListCardSource(range: range, ownerLine: ownerLine, ownerColumn: ownerColumn, ownerIndex: ownerIndex, signature: path.map(\.signature), firstPrefix: path.map { $0.prefix(on: first + 1) }.joined(), continuationPrefix: path.map(\.continuation).joined(), original: raw, inner: inner, ownerSuffix: path.suffix(from: path.lastIndex(where: { if case .item = $0 { return true }; return false })! + 1).map(\.continuation).joined(), owners: owners)
            result.append(.init(source: context, code: code, body: (node as? CodeBlock)?.code, table: table, rule: rule))
        }
        walk(document)
        return result
    }
}


extension NSAttributedString.Key {
    static let macListCard = Self("ZerusMacListCard")
}

/// Placement is independent of the immutable code/table model. The live list
/// context can change in Undo snapshots without rebuilding table-cell objects.
final class MacListCardPlacement: NSObject {
    let source: MacListCardSource
    let initialHead: String
    let inlineHeads: [(id: UUID, source: String)]
    let ownerSuffix: String
    private let originalPlacement: Bool
    init(source: MacListCardSource, head: MacListContext, inlineHeads: [MacListContext]) {
        self.source = source; initialHead = head.source; self.inlineHeads = inlineHeads.map { ($0.id, $0.source) }
        ownerSuffix = source.ownerSuffix; originalPlacement = true
    }
    private init(_ previous: MacListCardPlacement, ownerSuffix: String) {
        source = previous.source; initialHead = previous.initialHead; inlineHeads = previous.inlineHeads
        self.ownerSuffix = ownerSuffix; originalPlacement = false
    }
    func replacingOwnerSuffix(_ suffix: String) -> MacListCardPlacement { .init(self, ownerSuffix: suffix) }
    func markdown(_ inner: String, attributes: [NSAttributedString.Key: Any], head: MacListContext?, joined: [MacListContext] = []) -> String {
        let sameHeads = joined.count == inlineHeads.count && zip(joined, inlineHeads).allSatisfy { $0.id == $1.id && $0.source == $1.source }
        let inherited = (attributes[.macListContext] as? MacListContext)?.suffix ?? ""
        if originalPlacement, inherited.isEmpty, head?.source == initialHead, sameHeads { return source.spelling(inner) }
        let prefix = head.flatMap { MacBlockPrefix($0.source)?.listContinuation } ?? (MacBlockPrefix(attributes[.macBlock] as? String ?? "")?.quotes ?? "")
        var first = prefix
        if let start = joined.first {
            first = start.source
            for (previous, next) in zip(joined, joined.dropFirst()) {
                let continuation = MacBlockPrefix(previous.source)?.listContinuation ?? ""
                first += next.source.hasPrefix(continuation) ? String(next.source.dropFirst(continuation.count)) : next.source
            }
        }
        return MacMarkdownLines(inner).lines.enumerated().map { index, line in
            line.text.isEmpty && line.ending.isEmpty ? "" : (index == 0 ? first : prefix) + inherited + ownerSuffix + line.text + line.ending
        }.joined()
    }
    /// Empty native heads can share the card's first source line. A typed body
    /// or a different head ends that compact spelling, without deleting rows.
    static func joinedHeads(in text: NSAttributedString) -> (offsets: Set<Int>, cards: [Int: [MacListContext]]) {
        let raw = text.string as NSString
        var offsets = Set<Int>(), cards: [Int: [MacListContext]] = [:]
        text.enumerateAttribute(.macListCard, in: NSRange(location: 0, length: text.length)) { item, range, _ in
            guard let placement = item as? MacListCardPlacement,
                  let owner = text.attribute(.macListContext, at: range.location, effectiveRange: nil) as? MacListContext,
                  var expected = placement.inlineHeads.firstIndex(where: { $0.id == owner.id }) else { return }
            var position = range.location, selected: [MacListContext] = []
            while position > 0 {
                let row = raw.paragraphRange(for: NSRange(location: position - 1, length: 0))
                guard let head = text.attribute(.macListContext, at: row.location, effectiveRange: nil) as? MacListContext,
                      !head.continuation, head.id == placement.inlineHeads[expected].id,
                      let prefix = MacBlockPrefix(head.source), prefix.list, !prefix.checklist,
                      raw.substring(with: row).trimmingCharacters(in: .whitespacesAndNewlines) == prefix.display.trimmingCharacters(in: .whitespaces) else { break }
                offsets.insert(row.location); selected.insert(head, at: 0); position = row.location
                if expected == 0 { break }; expected -= 1
            }
            if !selected.isEmpty { cards[range.location] = selected }
        }
        return (offsets, cards)
    }
    /// A copied card without its head becomes standalone while retaining the
    /// quote containers around it. Its source-side list prefix is not copied.
    static func detached(_ value: NSAttributedString, from attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        guard value.length > 0, let placement = attrs[.macListCard] as? MacListCardPlacement else { return value }
        let output = NSMutableAttributedString(attributedString: value), full = NSRange(location: 0, length: value.length)
        let context = attrs[.macListContext] as? MacListContext
        // Ancestor list padding is not part of a standalone quote. In
        // particular four inherited spaces would turn the quote into code.
        let depth = MacBlockPrefix(context?.source ?? attrs[.macBlock] as? String ?? "")?.depth ?? 0
        let quotes = String(repeating: "> ", count: depth)
        output.removeAttribute(.macListContext, range: full)
        output.addAttributes([.macListCard: placement, .macBlock: quotes], range: full)
        restyle(output); return output
    }
    static func carrying(_ value: NSAttributedString, from original: NSAttributedString) -> NSAttributedString {
        guard value.length > 0, original.length > 0, original.attribute(.macListCard, at: 0, effectiveRange: nil) != nil else { return value }
        let output = NSMutableAttributedString(attributedString: value), attrs = original.attributes(at: 0, effectiveRange: nil)
        for key in [NSAttributedString.Key.macListCard, .macListContext, .macBlock] {
            if let item = attrs[key] { output.addAttribute(key, value: item, range: NSRange(location: 0, length: output.length)) }
        }
        restyle(output); return output
    }
    static func placed(_ value: NSAttributedString, source: MacListCardSource?, head: MacListContext?, inlineHeads: [MacListContext] = []) -> NSAttributedString {
        guard let source, let head, value.length > 0 else { return value }
        let output = NSMutableAttributedString(attributedString: value)
        let context = MacListContext(id: head.id, source: head.source, continuation: true, quoteParents: head.quoteParents)
        output.addAttributes([.macListCard: MacListCardPlacement(source: source, head: head, inlineHeads: inlineHeads), .macListContext: context, .macBlock: context.block], range: NSRange(location: 0, length: output.length))
        restyle(output); return output
    }
    static func inheriting(_ base: [NSAttributedString.Key: Any], from attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        guard attrs[.macListCard] != nil else { return base }
        var result = base
        for key in [NSAttributedString.Key.macListCard, .macListContext, .macBlock] { result[key] = attrs[key] }
        let value = NSMutableAttributedString(string: "x", attributes: result); restyle(value)
        result[.paragraphStyle] = value.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
        return result
    }
    static func restyle(_ value: NSMutableAttributedString) {
        // Ordinary prose has no card layout. Avoid bridging every attribute
        // dictionary merely to discover that its card attribute is absent.
        value.enumerateAttribute(.macListCard, in: NSRange(location: 0, length: value.length)) { token, span, _ in
            guard token is MacListCardPlacement else { return }
            value.enumerateAttributes(in: span) { attrs, range, _ in
                guard let placement = attrs[.macListCard] as? MacListCardPlacement,
                      let old = attrs[.paragraphStyle] as? NSParagraphStyle else { return }
                let context = attrs[.macListContext] as? MacListContext
                let indent = context?.style.headIndent ?? MacMarkdown.paragraphStyle(attrs[.macBlock] as? String ?? "").headIndent
                let base = (attrs[.macCell] as? MacRichTable.Cell)?.attributes[.paragraphStyle] as? NSParagraphStyle ?? old
                let style = base.mutableCopy() as! NSMutableParagraphStyle
                style.headIndent = indent + CGFloat(placement.ownerSuffix.filter { $0 == ">" }.count * 18) + (attrs[.macCode] == nil ? 0 : 14)
                style.firstLineHeadIndent = style.headIndent
                // Publishing a prose edit also checks card placement. An equal
                // style must not create a text-storage edit and invalidate the
                // card's layout again; compare the complete style so changed
                // cell geometry and other paragraph properties still apply.
                if !old.isEqual(style) { value.addAttribute(.paragraphStyle, value: style, range: range) }
            }
        }
    }
}
