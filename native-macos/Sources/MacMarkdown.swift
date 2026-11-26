import AppKit
import SwiftUI
import Markdown

extension NSAttributedString.Key {
    static let macBlock = Self("ZerusMacBlock")
    static let macLinkTitle = Self("ZerusMacLinkTitle")
    static let macOriginal = Self("ZerusMacOriginal")
    static let macSignature = Self("ZerusMacSignature")
    static let macLiteral = Self("ZerusMacLiteral")
    static let macStrong = Self("ZerusMacStrong")
    static let macParagraphID = Self("ZerusMacParagraphID")
    static let macParagraphSource = Self("ZerusMacParagraphSource")
    static let macParagraphSignature = Self("ZerusMacParagraphSignature")
    static let macIndependentParagraph = Self("ZerusMacIndependentParagraph")
    static let macEmptyParagraph = Self("ZerusMacEmptyParagraph")
    static let macUnterminated = Self("ZerusMacUnterminated")
    static let macLineEnding = Self("ZerusMacLineEnding")
    static let macHardBreak = Self("ZerusMacHardBreak")
    static let macListBreak = Self("ZerusMacListBreak")
    static let macListContext = Self("ZerusMacListContext")
    static let macListGap = Self("ZerusMacListGap")
    static let macCompactList = Self("ZerusMacCompactList")
    static let macOrderedMarker = Self("ZerusMacOrderedMarker")
}

/// Several source items can start on one line. Each still has a native row;
/// this immutable token preserves their shared source spelling until edited.
final class MacCompactList: NSObject {
    let original: String
    let prefix: String
    let fingerprint: String
    let heads: [(UUID, String)]
    init(original: String, prefix: String, fingerprint: String, heads: [(UUID, String)]) {
        self.original = original; self.prefix = prefix; self.fingerprint = fingerprint; self.heads = heads
    }
}

/// A blank paragraph before an item's first child stays in the native document.
/// Its source spelling depends on whether that parent currently has a body.
final class MacListGap: NSObject {
    let parent: UUID
    let child: UUID
    init(parent: UUID, child: UUID) { self.parent = parent; self.child = child }
}

/// A marker paragraph and its paragraphs after child lists share one item.
/// Immutable contexts remain valid in native Undo snapshots; a changed marker
/// keeps its identity while replacing its source spelling.
final class MacListContext: NSObject {
    let id: UUID
    let source: String
    let continuation: Bool
    let gap: String
    let originatedAfterChildren: Bool
    let suffix: String
    /// A live paragraph inside an item, rather than the flat item text.
    let blockParagraph: Bool
    /// The current block is the quote itself, rather than its child paragraph.
    /// Toolbar factories create this live role; empty parsed quotes infer it.
    let quoteLeaf: Bool
    /// List items crossed before entering inner quotes. Immutable snapshots
    /// supply layout only; source ownership still comes from the Markdown tree.
    let quoteParents: [MacListContext]
    init(id: UUID = UUID(), source: String, continuation: Bool = false, gap: String = "", originatedAfterChildren: Bool = false, suffix: String = "", blockParagraph: Bool = false, quoteLeaf: Bool = false, quoteParents: [MacListContext] = []) {
        self.id = id; self.source = source; self.continuation = continuation; self.gap = gap
        self.originatedAfterChildren = originatedAfterChildren; self.suffix = suffix; self.blockParagraph = blockParagraph; self.quoteLeaf = quoteLeaf; self.quoteParents = quoteParents
    }
    var parentQuotes: String {
        let quotes = String(suffix.prefix { $0 == ">" || $0.isWhitespace })
        guard quoteLeaf, let last = quotes.lastIndex(of: ">") else { return quotes }
        return String(quotes[..<last])
    }
    var block: String {
        guard continuation, let prefix = MacBlockPrefix(source) else { return source }
        return prefix.listContinuation + suffix
    }
    /// The item marker and its inner heading/quote have independent roles.
    /// Keep the marker as the structural block while styling the actual text.
    var textBlock: String { suffix.isEmpty ? source : (MacBlockPrefix(source)?.quotes ?? "") + suffix }
    var style: NSParagraphStyle {
        let style = (MacMarkdown.paragraphStyle(source).mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let inherited = quoteParents.reduce(CGFloat.zero) { offset, owner in
            guard let prefix = MacBlockPrefix(owner.source) else { return offset }
            return offset + MacMarkdown.paragraphStyle(owner.source).headIndent - CGFloat(prefix.depth * 18)
        }
        style.firstLineHeadIndent += inherited
        style.headIndent += inherited + CGFloat(suffix.filter { $0 == ">" }.count * 18)
        if continuation { style.firstLineHeadIndent = style.headIndent }
        if MacBlockPrefix(textBlock)?.heading == true { style.paragraphSpacing = 12 }
        return style
    }
    func replacing(source: String, quoteParents: [MacListContext]? = nil) -> MacListContext {
        var gap = self.gap
        if source != self.source, let previous = MacBlockPrefix(self.source), let prefix = MacBlockPrefix(source) {
            gap = MacMarkdownLines(gap).lines.map { row in
                guard row.text.contains(">"), row.text.unicodeScalars.allSatisfy({ [9, 32, 62].contains($0.value) }),
                      let gapPrefix = MacBlockPrefix(row.text), gapPrefix.depth >= previous.depth else { return row.text + row.ending }
                if gapPrefix.depth == previous.depth {
                    // A shared quote can inherit padding from a wider ancestor
                    // marker even when this item's own marker is unchanged.
                    guard previous.quotes != prefix.quotes else { return row.text + row.ending }
                    let quotes = gapPrefix.quotes.hasSuffix(">") && prefix.quotes.hasSuffix("> ") ? String(prefix.quotes.dropLast()) : prefix.quotes
                    return quotes + gapPrefix.indentation + row.ending
                }
                // These rows contain only quote markers and whitespace. Strip
                // shared quote levels without treating ancestor list padding as
                // root Markdown indentation (which is limited to three spaces).
                let relative = (row.text.split(separator: ">", maxSplits: previous.depth, omittingEmptySubsequences: false).last ?? "").drop(while: { $0 == " " || $0 == "\t" })
                return prefix.listContinuation + relative + row.ending
            }.joined()
        }
        return MacListContext(id: id, source: source, continuation: continuation, gap: gap, originatedAfterChildren: originatedAfterChildren, suffix: suffix, blockParagraph: blockParagraph, quoteLeaf: quoteLeaf, quoteParents: quoteParents ?? self.quoteParents)
    }
}

/// Native rich text is deliberately constrained to portable Markdown semantics.
/// Original paragraph tokens survive untouched; unsupported blocks use source editing.
enum MacMarkdown {
    /// Only use for a parser-owned ListItem. A bare marker has no literal
    /// following space, but needs the ordinary native marker presentation.
    private static func listPrefix(_ node: any Markup, lines: [String]) -> MacBlockPrefix? {
        guard let start = node.range?.lowerBound.line, lines.indices.contains(start - 1) else { return nil }
        let line = lines[start - 1]
        if let prefix = MacBlockPrefix(line), prefix.list { return prefix }
        guard let paragraph = node.child(at: 0) as? Paragraph,
              let bodyLine = paragraph.range?.lowerBound.line, bodyLine > start,
              let prefix = MacBlockPrefix(line + " "), prefix.list else { return nil }
        return prefix
    }
    private static func listParagraphs(_ node: any Markup, lines: [String]) -> [Paragraph]? {
        guard let start = node.range?.lowerBound.line, lines.indices.contains(start - 1),
              let prefix = listPrefix(node, lines: lines),
              !prefix.source.contains("\t") else { return nil }
        let paragraphs = node.children.prefix(while: { $0 is Paragraph }).compactMap { $0 as? Paragraph }
        if let first = paragraphs.first, first.range?.lowerBound.line != start,
           !lines[start - 1].dropFirst(prefix.source.count).trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        return paragraphs
    }
    static func codeRanges(in source: String) -> [NSRange] {
        MacCodeBlock.blocks(in: source).map(\.range)
    }
    static func tables(in source: String) -> [MacTableBlock] {
        MacTableBlock.blocks(in: source, excluding: codeRanges(in: source))
    }
    private static func tableBlocks(in source: String, excluding ranges: [NSRange], document: Markdown.Document) -> [MacTableBlock] {
        MacTableBlock.blocks(in: source, excluding: ranges, document: document).filter { $0.container == nil }
    }
    static let accent = NSColor(red: 0.36, green: 0.42, blue: 0.93, alpha: 1)
    /// Plain quoted lists additionally prove their rendered item mapping.
    /// Mixed card admission retains its independent container checks.
    private static func supportedItemQuote(_ node: any Markup, allowNestedLists: Bool = false) -> Bool {
        node.children.allSatisfy { child in
            child is Paragraph || child is Heading || child is CodeBlock || child is Markdown.Table || child is ThematicBreak ||
                allowNestedLists && (child is OrderedList || child is UnorderedList) ||
                child is BlockQuote && supportedItemQuote(child, allowNestedLists: allowNestedLists)
        }
    }
    /// Rich text is the default even when saving normalizes Markdown syntax.
    /// Source mode is an explicit user choice, never a preservation requirement.
    static func requiresSource(_ source: String) -> Bool { false }

    /// Capability check for optimizations that splice exact source ranges.
    /// This must not control whether a note can be opened in rich text.
    fileprivate static func requiresLosslessSource(_ source: String) -> Bool {
        // Frontmatter can supply an NSString-backed slice. Materialize its
        // unchanged UTF-8 once rather than bridge each character during scans.
        var source = source
        source.makeContiguousUTF8()
        // Removing a recognized code/table token first can hide its actual
        // list ownership. Validate list cards against the original parser tree.
        let document = Document(parsing: source)
        if source.contains("\t"), tabbedListRender(source, document: document, root: nil, path: "", images: [:]) != nil { return false }
        let owned = MacListCards.blocks(in: source, document: document)
        if !owned.isEmpty { return listCardsRequireSource(source, document: document, cards: owned) }
        let quoted = Set(MacQuotedCards.blocks(in: source, document: document).map(\.nodeLine))
        func hasEmbeddedBlock(_ node: any Markup) -> Bool {
            for child in node.children {
                if !(node is Markdown.Document), child is CodeBlock || child is Markdown.Table, !quoted.contains(child.range?.lowerBound.line ?? 0) { return true }
                if hasEmbeddedBlock(child) { return true }
            }
            return false
        }
        if hasEmbeddedBlock(document) { return true }
        func hasHTML(_ node: any Markup, pairedFormat: Bool = false) -> Bool {
            if let html = node as? HTMLBlock { return MacInlineImage(html: html.rawHTML) == nil }
            if let html = node as? InlineHTML { return !pairedFormat && html.rawHTML.range(of: #"(?i)^<br\s*/?>$"#, options: .regularExpression) == nil && MacInlineImage(html: html.rawHTML) == nil }
            let tags = NativeInlineHTML.paired(in: node)
            return node.children.enumerated().contains { hasHTML($0.element, pairedFormat: tags[$0.offset] != nil) }
        }
        let codes = MacCodeBlock.blocks(in: source, document: document).map(\.range)
        let tables = tableBlocks(in: source, excluding: codes, document: document)
        if tables.contains(where: { $0.table.rows.contains(where: { $0.contains(where: { hasHTML(Document(parsing: "x " + $0)) }) }) }) { return true }
        let prose = NSMutableString(string: source)
        for range in (codes + tables.map(\.range)).sorted(by: { $0.location > $1.location }) { prose.replaceCharacters(in: range, with: "") }
        source = prose as String
        source.makeContiguousUTF8()
        // The original tree still describes the prose when no token was removed.
        // A stripped document needs its own tree, shared by the remaining checks.
        let proseDocument = codes.isEmpty && tables.isEmpty ? document : Document(parsing: source)
        let lines = MacMarkdownLines(source).contents
        var listLines = Set<Int>(), wrappedLines = Set<Int>(), ruleLines = Set<Int>()
        var itemHeadingRanges = MacItemHeadingRanges(lines: lines)
        var nestedItemQuotes = false, sharedListLines = false
        func unsupported(_ node: any Markup, inList: Bool = false, insideItemQuote: Bool = false) -> Bool {
            if node is CodeBlock || node is Markdown.Table { return true }
            if node is ThematicBreak, let line = node.range?.lowerBound.line { ruleLines.insert(line) }
            if node is ListItem {
                if insideItemQuote { nestedItemQuotes = true }
                guard listParagraphs(node, lines: lines) != nil else { return true }
                if let line = node.range?.lowerBound.line, !listLines.insert(line).inserted { sharedListLines = true }
                // Headings and text quotes keep their item identity separately
                // from their visible block role, including later body blocks.
                for child in node.children {
                    if child is Paragraph || child is Heading || child is OrderedList || child is UnorderedList ||
                        child is BlockQuote && supportedItemQuote(child, allowNestedLists: true) { continue }
                    return true
                }
            }
            if inList, let heading = node as? Heading {
                guard let span = itemHeadingRanges.range(for: heading) else { return true }
                wrappedLines.formUnion((span.start + 1)...span.end)
            } else if inList, node is BlockQuote, let span = node.range {
                wrappedLines.formUnion(span.lowerBound.line...max(span.lowerBound.line, span.upperBound.line))
            }
            // Known item paragraphs own their indentation, including hard breaks
            // and paragraph separators represented inside the native item.
            if inList, node is Paragraph, let range = node.range,
               range.lowerBound.line <= range.upperBound.line {
                wrappedLines.formUnion(range.lowerBound.line...range.upperBound.line)
            }
            return node.children.contains { unsupported($0, inList: inList || node is ListItem, insideItemQuote: insideItemQuote || inList && node is BlockQuote) }
        }
        if unsupported(proseDocument) { return true }
        for (index, line) in lines.enumerated() { if MacBlockPrefix(line)?.list == true, !listLines.contains(index + 1), !ruleLines.contains(index + 1) { return true } }
        // CommonMark permits up to three layout spaces before root prose and
        // headings. Their native paragraphs already retain untouched source and
        // track independence from preceding lists. Do not mistake this layout
        // for unsupported indentation; tabs and deeper indentation stay guarded.
        var rootProseLines = Set<Int>()
        for node in proseDocument.children where node is Paragraph || node is Heading {
            if let range = node.range, range.lowerBound.line <= range.upperBound.line {
                rootProseLines.formUnion(range.lowerBound.line...range.upperBound.line)
            }
        }
        let indentationCheck = lines.enumerated().map { index, line -> String in
            if wrappedLines.contains(index + 1) || ruleLines.contains(index + 1) { return "" }
            if line.hasPrefix("  "), rootProseLines.contains(index + 1) {
                return line.replacingOccurrences(of: #"^ {2,3}(?=\S)"#, with: "", options: .regularExpression)
            }
            guard let prefix = MacBlockPrefix(line), prefix.list else { return line }
            return String(line.dropFirst(prefix.source.count))
        }.joined(separator: "\n")
        // Each alternative needs one of these literal bytes. Ordinary prose
        // cannot match, so avoid a whole-document regex scan in that case.
        let possibleIndentation: Bool = {
            var previous: UInt8 = 0
            for byte in indentationCheck.utf8 {
                if byte == 9 || byte == 91 || byte == 32 && previous == 32 { return true }
                previous = byte
            }
            return false
        }()
        if (source.contains("<") && hasHTML(proseDocument)) ||
            possibleIndentation && indentationCheck.range(of: #"(?m)^ {2,}\S|^\t|^\[.+\]:"#, options: .regularExpression) != nil { return true }
        guard nestedItemQuotes || sharedListLines else { return false }
        // Compact marker/quote/list heads may share one physical line. Keep
        // Source when native rows cannot represent every parser-owned item.
        // Original source reuse alone cannot prove that item mapping.
        var parents: [Int?] = []
        func collectParents(_ node: any Markup, owner: Int? = nil) {
            var current = owner
            if node is ListItem { current = parents.count; parents.append(owner) }
            for child in node.children { collectParents(child, owner: current) }
        }
        collectParents(proseDocument)
        let rich = render(source), serialized = serializedMarkdown(rich)
        return !serialized.text.utf8.elementsEqual(source.utf8) ||
            nativeListItems(in: rich, using: serialized)?.map(\.parent) != parents
    }

    /// Admit list cards from the original tree, before removing any source
    /// ranges. Native identities and model contents must preserve that tree.
    private static func listCardsRequireSource(_ source: String, document: Markdown.Document, cards: [MacListOwnedCard]) -> Bool {
        let lines = MacMarkdownLines(source)
        var parents: [Int?] = [], owners: [Int] = [], kinds: [Int] = []
        var listLines = Set<Int>(), literalLines = Set<Int>()
        let tableRanges = tables(in: source).filter { !$0.table.widthMarker.isEmpty }.map(\.range)
        func cover(_ node: any Markup, into set: inout Set<Int>) {
            guard let span = node.range else { return }
            set.formUnion(span.lowerBound.line...max(span.lowerBound.line, span.upperBound.line))
        }
        func unsupported(_ node: any Markup, owner: Int? = nil, pairedFormat: Bool = false) -> Bool {
            var owner = owner
            if node is ListItem {
                let parent = owner; owner = parents.count; parents.append(parent)
                cover(node, into: &listLines)
                if node.children.contains(where: { !($0 is Paragraph || $0 is Heading || $0 is OrderedList || $0 is UnorderedList || $0 is CodeBlock || $0 is Markdown.Table || $0 is ThematicBreak || $0 is BlockQuote && supportedItemQuote($0, allowNestedLists: true)) }) { return true }
            }
            if node is BlockQuote, owner != nil, !supportedItemQuote(node, allowNestedLists: true) { return true }
            if node is CodeBlock || node is Markdown.Table || node is ThematicBreak {
                cover(node, into: &literalLines)
                if let owner { owners.append(owner); kinds.append(node is Markdown.Table ? 1 : node is ThematicBreak ? 2 : 0) }
                if node is CodeBlock { return false }
            }
            if node is ThematicBreak { cover(node, into: &literalLines) }
            if let html = node as? HTMLBlock, MacInlineImage(html: html.rawHTML) == nil {
                guard let line = html.range?.lowerBound.line, lines.lines.indices.contains(line - 1),
                      tableRanges.contains(where: { NSLocationInRange(lines.lines[line - 1].offset, $0) }),
                      html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!-- zerus-table-widths:") else { return true }
            }
            if let html = node as? InlineHTML, !pairedFormat,
               html.rawHTML.range(of: #"(?i)^<br\s*/?>$"#, options: .regularExpression) == nil,
               MacInlineImage(html: html.rawHTML) == nil { return true }
            let tags = NativeInlineHTML.paired(in: node)
            return node.children.enumerated().contains { unsupported($0.element, owner: owner, pairedFormat: tags[$0.offset] != nil) }
        }
        guard !unsupported(document), owners.count == cards.count,
              zip(owners, cards).allSatisfy({ $0 == $1.source.ownerIndex }),
              zip(kinds, cards).allSatisfy({ $0 == ($1.table != nil ? 1 : $1.rule != nil ? 2 : 0) }) else { return true }
        for (index, row) in lines.lines.enumerated() where !literalLines.contains(index + 1) {
            let line = row.text
            if line.range(of: #"^[ \t]*\[.+\]:"#, options: .regularExpression) != nil { return true }
            if !listLines.contains(index + 1), line.range(of: #"^ {2,}\S|^\t"#, options: .regularExpression) != nil { return true }
        }
        let rich = render(source), serialized = serializedMarkdown(rich)
        guard serialized.text.utf8.elementsEqual(source.utf8),
              let items = nativeListItems(in: rich, using: serialized), items.map(\.parent) == parents else { return true }
        var heads: [UUID: Int] = [:]
        for (index, item) in items.enumerated() {
            guard let context = rich.attribute(.macListContext, at: item.range.location, effectiveRange: nil) as? MacListContext else { return true }
            heads[context.id] = index
        }
        var index = 0, valid = true
        rich.enumerateAttribute(.macListCard, in: NSRange(location: 0, length: rich.length)) { value, range, _ in
            guard value is MacListCardPlacement else { return }
            guard index < cards.count, let context = rich.attribute(.macListContext, at: range.location, effectiveRange: nil) as? MacListContext,
                  heads[context.id] == owners[index] else { valid = false; return }
            let expected = cards[index], body = rich.attributedSubstring(from: range)
            if let code = MacRichCode.at(rich, range.location), let original = expected.body {
                let canonical = original.hasSuffix("\n") ? String(original.dropLast()) : original
                valid = valid && MacMarkdownLines.normalized(MacRichCode.body(body), to: "\n") == canonical && code.original.info == expected.code?.code.info
            } else if let cell = MacRichTable.at(rich, range.location), let table = expected.table {
                let actual = cell.table.model(body)
                valid = valid && actual.rows == table.rows && actual.alignments == table.alignments && actual.widths == table.widths
            } else if rich.attribute(.macRule, at: range.location, effectiveRange: nil) != nil, let rule = expected.rule {
                valid = valid && rich.attribute(.macLiteral, at: range.location, effectiveRange: nil) as? String == rule
            } else { valid = false }
            index += 1
        }
        return !valid || index != cards.count
    }

    static func lineEnding(in original: NSAttributedString, at position: Int) -> String {
        guard original.length > 0 else { return "\n" }
        let row = (original.string as NSString).paragraphRange(for: NSRange(location: min(position, original.length - 1), length: 0))
        let attrs = original.attributes(at: NSMaxRange(row) - 1, effectiveRange: nil)
        return attrs[.macLineEnding] as? String ?? (attrs[.macCode] as? MacRichCode)?.original.newline ?? (attrs[.macTable] as? MacRichTable)?.original.newline ?? "\n"
    }

    static func font(_ block: String) -> NSFont {
        let block = MacBlockPrefix(block)?.marker ?? block
        let size: CGFloat = block.hasPrefix("# ") ? 32 : block.hasPrefix("## ") ? 23 : block.hasPrefix("### ") ? 19 : 15
        return NSFont.systemFont(ofSize: size, weight: block.hasPrefix("#") ? .bold : .regular)
    }
    static func displayPrefix(_ block: String) -> String {
        MacBlockPrefix(block)?.display ?? ""
    }
    private static func firstHeading(_ node: any Markup) -> Heading? {
        if let heading = node as? Heading { return heading }
        for child in node.children { if let heading = firstHeading(child) { return heading } }
        return nil
    }
    static func paragraphStyle(_ block: String) -> NSParagraphStyle {
        if let prefix = MacBlockPrefix(block) { return prefix.style }
        let style = NSMutableParagraphStyle(); style.paragraphSpacing = 7; style.lineSpacing = 5; return style
    }
    static func inlineBold(_ attrs: [NSAttributedString.Key: Any], block: String) -> Bool {
        if let explicit = attrs[.macStrong] as? Bool { return explicit }
        let font = attrs[.font] as? NSFont ?? self.font(block)
        return MacBlockPrefix(block)?.heading != true && NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }
    static func inlineFont(block: String, bold: Bool, italic: Bool, code: Bool) -> NSFont {
        let heading = MacBlockPrefix(block)?.heading == true
        var value = code ? NSFont.monospacedSystemFont(ofSize: heading ? font(block).pointSize : 14, weight: .regular) : font(block)
        if bold || code && heading { value = NSFontManager.shared.convert(value, toHaveTrait: .boldFontMask) }
        if italic { value = NSFontManager.shared.convert(value, toHaveTrait: .italicFontMask) }
        return value
    }
    /// Retain inline runs while changing a paragraph's block semantics and visible marker.
    static func settingBlock(_ paragraph: NSAttributedString, to block: String, removingMarker: Bool = true, collapsingParagraphs: Bool = true) -> NSAttributedString {
        if paragraph.length > 0, paragraph.attribute(.macRule, at: 0, effectiveRange: nil) != nil { return paragraph }
        if paragraph.length > 0, paragraph.attribute(.macListCard, at: 0, effectiveRange: nil) != nil {
            let output = NSMutableAttributedString(attributedString: paragraph), full = NSRange(location: 0, length: paragraph.length)
            output.removeAttribute(.macListContext, range: full)
            output.addAttribute(.macBlock, value: MacBlockPrefix(block)?.quotes ?? block, range: full)
            MacListCardPlacement.restyle(output)
            return output
        }
        let rich = NSMutableAttributedString(attributedString: paragraph)
        let orderedMarker = rich.length > 0 ? rich.attribute(.macOrderedMarker, at: 0, effectiveRange: nil) as? String : nil
        rich.removeAttribute(.macOrderedMarker, range: NSRange(location: 0, length: rich.length))
        let old = rich.length > 0 ? rich.attribute(.macBlock, at: 0, effectiveRange: nil) as? String ?? "" : ""
        let previousContext = rich.length > 0 ? rich.attribute(.macListContext, at: 0, effectiveRange: nil) as? MacListContext : nil
        let listContext = MacBlockPrefix(block)?.list == true ? MacListContext(id: previousContext?.continuation == false ? previousContext!.id : UUID(), source: block, suffix: previousContext?.continuation == false ? previousContext!.suffix : "", blockParagraph: previousContext?.continuation == false && previousContext!.blockParagraph, quoteLeaf: previousContext?.continuation == false && previousContext!.quoteLeaf, quoteParents: previousContext?.quoteParents ?? []) : nil
        let prefix = displayPrefix(old)
        if removingMarker && !prefix.isEmpty && rich.string.hasPrefix(prefix) { rich.deleteCharacters(in: NSRange(location: 0, length: (prefix as NSString).length)) }
        if collapsingParagraphs, MacBlockPrefix(block)?.heading == true {
            let raw = rich.string as NSString
            let gaps = try! NSRegularExpression(pattern: "\u{2028}+").matches(in: rich.string, range: NSRange(location: 0, length: raw.length))
            for gap in gaps.reversed() {
                var attrs = rich.attributes(at: gap.range.location, effectiveRange: nil)
                attrs.removeValue(forKey: .macListBreak); attrs.removeValue(forKey: .macHardBreak)
                rich.replaceCharacters(in: gap.range, with: NSAttributedString(string: " ", attributes: attrs))
            }
        }
        let full = NSRange(location: 0, length: rich.length)
        rich.removeAttribute(.macListContext, range: full)
        if let listContext { rich.addAttribute(.macListContext, value: listContext, range: full) }
        rich.enumerateAttributes(in: full) { attrs, range, _ in
            let oldFont = attrs[.font] as? NSFont ?? font(old), traits = NSFontManager.shared.traits(of: oldFont)
            let bold = inlineBold(attrs, block: old)
            let style = listContext?.style ?? paragraphStyle(block)
            rich.addAttributes([.macBlock: block, .macIndependentParagraph: listContext == nil, .macStrong: bold, .font: inlineFont(block: listContext?.textBlock ?? block, bold: bold, italic: traits.contains(.italicFontMask), code: traits.contains(.fixedPitchFontMask)), .paragraphStyle: style], range: range)
        }
        rich.removeAttribute(.macOriginal, range: full); rich.removeAttribute(.macSignature, range: full)
        let marker = displayPrefix(block)
        if !marker.isEmpty {
            var attributes: [NSAttributedString.Key: Any] = [.macBlock: block, .macIndependentParagraph: false, .font: font(listContext?.textBlock ?? block), .foregroundColor: NSColor.labelColor, .macStrong: false]
            if rich.length > 0, let style = rich.attribute(.paragraphStyle, at: 0, effectiveRange: nil) { attributes[.paragraphStyle] = style }
            if let listContext { attributes[.macListContext] = listContext }
            rich.insert(NSAttributedString(string: marker, attributes: attributes), at: 0)
        }
        if let orderedMarker, let previous = MacBlockPrefix(old), previous.checklist, previous.toggledChecklist == block {
            let checked = block.contains("[ ]") ? "[ ]" : "[x]"
            let marker = orderedMarker.replacingOccurrences(of: #"\[[ xX]\]"#, with: checked, options: .regularExpression)
            rich.addAttribute(.macOrderedMarker, value: marker, range: NSRange(location: 0, length: rich.length))
        }
        return rich
    }
    struct NativeListItem {
        let range: NSRange
        let block: MacBlockPrefix
        let parent: Int?
        let container: Int
    }
    /// Establish boundaries only for native empty heads absent from the parsed
    /// tree. Valid empty siblings keep their existing tight/loose spelling. The
    /// locations address the original text so callers can map selections back.
    static func insertingEmptyListBoundaries(in rich: NSAttributedString) -> (text: NSAttributedString, locations: [Int]) {
        let raw = rich.string as NSString, output = NSMutableAttributedString(attributedString: rich)
        let serialized = serializedMarkdown(rich, protectEmptyHeads: false)
        let locations = Set(protectingEmptyHeads(serialized).insertedEmptyBoundaries)
        var rows: [(NSRange, MacBlockPrefix)] = [], offset = 0
        while offset < raw.length {
            let range = raw.paragraphRange(for: NSRange(location: offset, length: 0))
            if let block = MacBlockPrefix(rich.attribute(.macBlock, at: offset, effectiveRange: nil) as? String ?? ""), block.list,
               locations.contains(offset),
               raw.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines) == block.display.trimmingCharacters(in: .whitespaces) { rows.append((range, block)) }
            offset = NSMaxRange(range)
        }
        for (range, block) in rows.reversed() {
            let newline = raw.substring(with: range).hasSuffix("\n") ? NSMaxRange(range) - 1 : max(0, range.location - 1)
            let ending = rich.attribute(.macLineEnding, at: newline, effectiveRange: nil) as? String ?? "\n"
            output.insert(NSAttributedString(string: "\n", attributes: [.macBlock: block.quotes, .paragraphStyle: paragraphStyle(block.quotes), .macLineEnding: ending]), at: range.location)
        }
        return (output, rows.map { $0.0.location })
    }
    /// Native marker paragraphs follow the Markdown tree's item preorder.
    /// Container commands share this mapping instead of inferring ancestry from
    /// source columns, which can differ even between real sibling markers.
    static func nativeListItems(in rich: NSAttributedString, allowEmptyItemBoundaries: Bool = false) -> [NativeListItem]? {
        nativeListItems(in: rich, using: nil, allowEmptyItemBoundaries: allowEmptyItemBoundaries)
    }
    /// Admission has already exported this same immutable render for its exact
    /// source check. Reuse its source/head mapping without weakening ownership.
    private static func nativeListItems(in rich: NSAttributedString, using serialization: SerializedMarkdown?, allowEmptyItemBoundaries: Bool = false) -> [NativeListItem]? {
        let raw = rich.string as NSString
        var rows: [(NSRange, MacBlockPrefix)] = [], offset = 0
        while offset < raw.length {
            let range = raw.paragraphRange(for: NSRange(location: offset, length: 0))
            let value = rich.attribute(.macBlock, at: offset, effectiveRange: nil) as? String ?? ""
            if let block = MacBlockPrefix(value), block.list { rows.append((range, block)) }
            offset = NSMaxRange(range)
        }
        var parents: [Int?] = [], containers: [Int] = [], lines: [Int] = [], nextContainer = 0
        func collect(_ node: any Markup, parent: Int? = nil, container: Int = -1) {
            var owner = parent, list = container
            if node is OrderedList || node is UnorderedList { list = nextContainer; nextContainer += 1 }
            if node is ListItem { owner = parents.count; parents.append(parent); containers.append(list); lines.append(node.range?.lowerBound.line ?? 0) }
            for child in node.children { collect(child, parent: owner, container: list) }
        }
        let serialized = serialization ?? serializedMarkdown(rich)
        collect(Document(parsing: serialized.text))
        let matched = parents.count == rows.count && rows.enumerated().allSatisfy { serialized.headLines[$0.element.0.location] == lines[$0.offset] }
        if !matched, allowEmptyItemBoundaries {
            // Copy can establish intended empty-marker boundaries in a private
            // snapshot. Its returned rows still address the unchanged note.
            let normalized = insertingEmptyListBoundaries(in: rich).text
            guard let mapped = nativeListItems(in: normalized), mapped.count == rows.count else { return nil }
            return rows.enumerated().map { index, row in NativeListItem(range: row.0, block: row.1, parent: mapped[index].parent, container: mapped[index].container) }
        }
        guard matched else { return nil }
        return rows.enumerated().map { index, row in NativeListItem(range: row.0, block: row.1, parent: parents[index], container: containers[index]) }
    }
    /// Isolate the parser-owned list region around a native head when an
    /// unrelated temporary row prevents a whole-document item mapping.
    static func nativeListRegion(in rich: NSAttributedString, around location: Int) -> NSRange? {
        guard location < rich.length else { return nil }
        let raw = rich.string as NSString, paragraph = raw.paragraphRange(for: NSRange(location: location, length: 0))
        let source = serializedMarkdown(rich)
        guard let line = source.headLines[paragraph.location] else { return nil }
        var target: (any Markup)?
        func find(_ node: any Markup) {
            guard target == nil else { return }
            if node is ListItem, node.range?.lowerBound.line == line { target = node; return }
            for child in node.children { find(child) }
        }
        find(Document(parsing: source.text))
        guard var root = target else { return nil }
        while let parent = root.parent, parent is ListItem || parent is OrderedList || parent is UnorderedList { root = parent }
        guard root is OrderedList || root is UnorderedList, let span = root.range, let parent = root.parent else { return nil }
        let siblings = Array(parent.children)
        guard let index = siblings.firstIndex(where: { $0.range?.lowerBound == span.lowerBound && $0.range?.upperBound == span.upperBound }) else { return nil }
        var first = index, last = index
        while first > 0, siblings[first - 1] is OrderedList || siblings[first - 1] is UnorderedList { first -= 1 }
        while last + 1 < siblings.count, siblings[last + 1] is OrderedList || siblings[last + 1] is UnorderedList { last += 1 }
        guard let lower = siblings[first].range?.lowerBound.line, let upper = siblings[last].range?.upperBound.line else { return nil }
        let selected = Set(source.headLines.filter { $0.value >= lower && $0.value <= upper }.keys)
        var latest: [UUID: Int] = [:], start: Int?, end = 0, offset = 0
        while offset < raw.length {
            let range = raw.paragraphRange(for: NSRange(location: offset, length: 0))
            let context = rich.attribute(.macListContext, at: offset, effectiveRange: nil) as? MacListContext
            if let context, !context.continuation { latest[context.id] = offset }
            let owned = context.flatMap { $0.continuation ? latest[$0.id] : nil }.map { selected.contains($0) } ?? false
            if selected.contains(offset) || owned { start = min(start ?? offset, offset); end = NSMaxRange(range) }
            offset = NSMaxRange(range)
        }
        guard let start, start <= paragraph.location, end >= NSMaxRange(paragraph) else { return nil }
        return NSRange(location: start, length: end - start)
    }
    /// Resolve a continuation to its nearest preceding owning head.
    static func listHeadParagraph(in text: NSAttributedString, paragraph: NSRange) -> NSRange? {
        guard paragraph.length > 0, NSMaxRange(paragraph) <= text.length else { return nil }
        guard let context = text.attribute(.macListContext, at: paragraph.location, effectiveRange: nil) as? MacListContext,
              context.continuation else { return paragraph }
        let raw = text.string as NSString
        var offset = paragraph.location
        while offset > 0 {
            let previous = raw.paragraphRange(for: NSRange(location: offset - 1, length: 0))
            if let head = text.attribute(.macListContext, at: previous.location, effectiveRange: nil) as? MacListContext,
               head.id == context.id, !head.continuation { return previous }
            offset = previous.location
        }
        // A non-list conversion can leave spacing context on former tails.
        // With no head left, the paragraph is independent prose and may itself
        // become a new list item; its old context still preserves boundary gaps.
        return paragraph
    }
    private static func listHeads(_ text: NSAttributedString) -> [UUID: MacListContext] {
        var heads: [UUID: MacListContext] = [:]
        text.enumerateAttribute(.macListContext, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let context = value as? MacListContext, !context.continuation { heads[context.id] = context }
        }
        return heads
    }
    static func refreshingListContexts(_ text: NSAttributedString) -> NSAttributedString {
        let heads = listHeads(text), output = NSMutableAttributedString(attributedString: text)
        text.enumerateAttribute(.macListContext, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let context = value as? MacListContext, context.continuation || !context.quoteParents.isEmpty else { return }
            if let head = heads[context.id] {
                // Resolve current immutable heads once per context. Reading only
                // their own source offsets avoids recursion or another parse.
                let inherited = head.quoteParents.compactMap { heads[$0.id] }
                let updated = context.replacing(source: head.source, quoteParents: inherited)
                output.addAttributes([.macListContext: updated, .macBlock: updated.block], range: range)
                text.enumerateAttribute(.macListCard, in: range) { card, part, _ in
                    if card == nil { output.addAttribute(.paragraphStyle, value: updated.style, range: part) }
                }
            } else {
                // Explicitly deleting an item's head must not leave its former
                // paragraphs indented as code or attached to a different item.
                text.enumerateAttribute(.macListCard, in: range) { card, part, _ in
                    if card == nil { output.addAttributes([.macBlock: "", .paragraphStyle: paragraphStyle("")], range: part) }
                    else {
                        output.removeAttribute(.macListContext, range: part)
                        output.addAttribute(.macBlock, value: MacBlockPrefix(context.source)?.quotes ?? "", range: part)
                    }
                }
            }
        }
        MacListCardPlacement.restyle(output)
        return output
    }
    /// Structural commands deliberately change parentage. Rebind physical gaps
    /// to their validated new first-child relationship rather than carrying a
    /// previous parent's spacing rule through an outdent or deletion.
    static func refreshingListGapOwners(_ text: NSAttributedString) -> NSAttributedString {
        var hasHead = false
        text.enumerateAttribute(.macListContext, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if let context = value as? MacListContext, !context.continuation { hasHead = true; stop.pointee = true }
        }
        guard hasHead else { return text }
        guard let items = nativeListItems(in: text), !items.isEmpty else { return text }
        let output = NSMutableAttributedString(attributedString: text), raw = text.string as NSString
        output.removeAttribute(.macListGap, range: NSRange(location: 0, length: text.length))
        var seen: Set<Int> = []
        for child in items.indices {
            guard let parent = items[child].parent, seen.insert(parent).inserted,
                  let owner = text.attribute(.macListContext, at: items[parent].range.location, effectiveRange: nil) as? MacListContext,
                  let target = text.attribute(.macListContext, at: items[child].range.location, effectiveRange: nil) as? MacListContext else { continue }
            let start = NSMaxRange(items[parent].range), end = items[child].range.location
            guard end > start else { continue }
            let gap = NSRange(location: start, length: end - start)
            if raw.substring(with: gap).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.addAttribute(.macListGap, value: MacListGap(parent: owner.id, child: target.id), range: gap)
            }
        }
        text.enumerateAttribute(.macListCard, in: NSRange(location: 0, length: text.length)) { card, range, _ in
            guard card != nil, let owner = text.attribute(.macListContext, at: range.location, effectiveRange: nil) as? MacListContext,
                  let head = items.last(where: { item in
                      guard item.range.location < range.location else { return false }
                      return (text.attribute(.macListContext, at: item.range.location, effectiveRange: nil) as? MacListContext)?.id == owner.id
                  }) else { return }
            let start = NSMaxRange(head.range), end = range.location
            if end > start {
                let gap = NSRange(location: start, length: end - start)
                if raw.substring(with: gap).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    output.addAttribute(.macListGap, value: MacListGap(parent: owner.id, child: owner.id), range: gap)
                }
            }
        }
        return output
    }
    private struct SignatureKeys {
        let font = NSAttributedString.Key.font.rawValue as NSString
        let context = NSAttributedString.Key.macListContext.rawValue as NSString
        let empty = NSAttributedString.Key.macEmptyParagraph.rawValue as NSString
        let unterminated = NSAttributedString.Key.macUnterminated.rawValue as NSString
        let independent = NSAttributedString.Key.macIndependentParagraph.rawValue as NSString
        let link = NSAttributedString.Key.link.rawValue as NSString
        let linkTitle = NSAttributedString.Key.macLinkTitle.rawValue as NSString
        let strike = NSAttributedString.Key.strikethroughStyle.rawValue as NSString
        let underline = NSAttributedString.Key.underlineStyle.rawValue as NSString
        let strong = NSAttributedString.Key.macStrong.rawValue as NSString
        let literal = NSAttributedString.Key.macLiteral.rawValue as NSString
        let block = NSAttributedString.Key.macBlock.rawValue as NSString
        let hardBreak = NSAttributedString.Key.macHardBreak.rawValue as NSString
        let listBreak = NSAttributedString.Key.macListBreak.rawValue as NSString
    }
    static func signature(_ text: NSAttributedString) -> String { signature(text, keys: SignatureKeys()) }
    private static func signature(_ text: NSAttributedString, keys: SignatureKeys) -> String {
        // Image previews may change display glyphs without changing portable text.
        var imageRanges: [(NSRange, [NSAttributedString.Key: Any])] = []
        text.enumerateAttribute(.macLiteral, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let literal = value as? String, MacInlineImage.parse(literal) != nil { imageRanges.append((range, text.attributes(at: range.location, effectiveRange: nil))) }
        }
        let canonical: NSAttributedString
        if imageRanges.isEmpty { canonical = text }
        else {
            let copy = NSMutableAttributedString(attributedString: text)
            for (range, attrs) in imageRanges.reversed() { copy.replaceCharacters(in: range, with: NSAttributedString(string: "\u{fffc}", attributes: attrs)) }
            canonical = copy
        }
        // These in-memory fingerprints are lossless, not hashes. Length-prefixed
        // fields avoid formatting numbers and concatenating strings on every run.
        func integer(_ value: UInt64, into data: inout Data) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        func string(_ value: String, into data: inout Data) {
            integer(UInt64(value.utf8.count), into: &data); data.append(contentsOf: value.utf8)
        }
        var result = Data()
        string(canonical.string, into: &result)
        var pending: Data?, pendingRange = NSRange(location: 0, length: 0)
        func flush() {
            if let pending {
                integer(UInt64(pendingRange.location), into: &result); integer(UInt64(pendingRange.length), into: &result)
                integer(UInt64(pending.count), into: &result); result.append(pending)
            }
        }
        var offset = 0
        while offset < canonical.length {
            var effective = CFRange()
            let attrs = CFAttributedStringGetAttributes(canonical as CFAttributedString, offset, &effective) as NSDictionary
            let range = NSRange(location: effective.location, length: effective.length)
            let font = attrs.object(forKey: keys.font) as? NSFont ?? NSFont.systemFont(ofSize: 15)
            let traits = NSFontManager.shared.traits(of: font).intersection([.boldFontMask, .italicFontMask, .fixedPitchFontMask]).rawValue
            let context = attrs.object(forKey: keys.context) as? MacListContext
            var semantic = Data(); semantic.reserveCapacity(128)
            string(context?.source ?? "", into: &semantic)
            semantic.append(context?.continuation == true ? 1 : 0)
            string(context?.gap ?? "", into: &semantic)
            semantic.append(context?.originatedAfterChildren == true ? 1 : 0)
            string(context?.suffix ?? "", into: &semantic)
            semantic.append(context?.blockParagraph == true ? 1 : 0)
            semantic.append(context?.quoteLeaf == true ? 1 : 0)
            semantic.append(attrs.object(forKey: keys.empty) as? Bool == true ? 1 : 0)
            semantic.append(attrs.object(forKey: keys.unterminated) as? Bool == true ? 1 : 0)
            semantic.append(attrs.object(forKey: keys.independent) as? Bool == true ? 1 : 0)
            integer(UInt64(traits), into: &semantic); integer(Double(font.pointSize).bitPattern, into: &semantic)
            string(String(describing: attrs.object(forKey: keys.link) ?? ""), into: &semantic)
            string(attrs.object(forKey: keys.linkTitle) as? String ?? "", into: &semantic)
            integer(UInt64(bitPattern: Int64(attrs.object(forKey: keys.strike) as? Int ?? 0)), into: &semantic)
            integer(UInt64(bitPattern: Int64(attrs.object(forKey: keys.underline) as? Int ?? 0)), into: &semantic)
            semantic.append(attrs.object(forKey: keys.strong) as? Bool == true ? 1 : 0)
            string(attrs.object(forKey: keys.literal) as? String ?? "", into: &semantic)
            string(attrs.object(forKey: keys.block) as? String ?? "", into: &semantic)
            semantic.append(attrs.object(forKey: keys.hardBreak) as? Bool == true ? 1 : 0)
            integer(UInt64(bitPattern: Int64(attrs.object(forKey: keys.listBreak) as? Int ?? 0)), into: &semantic)
            // Incidental color/layout run splits must not invalidate source reuse.
            if semantic == pending, NSMaxRange(pendingRange) == range.location { pendingRange.length += range.length }
            else { flush(); pending = semantic; pendingRange = range }
            offset = NSMaxRange(range)
        }
        flush()
        return result.base64EncodedString()
    }
    /// CommonMark tabs advance to four-column stops. Render supported list
    /// structure with spaces, then restore each original source token. Edits
    /// invalidate only the affected tokens through their existing signatures.
    private static func tabbedListRender(_ source: String, document: Markdown.Document, root: URL?, path: String, images: [String: NSImage]) -> NSAttributedString? {
        guard source.contains("\t") else { return nil }
        let original = MacMarkdownLines(source)
        var ownedLines = Set<Int>(), literalLines = Set<Int>(), prefixEnds: [Int: Int] = [:]
        func collect(_ node: any Markup) {
            if node is CodeBlock || node is Markdown.Table, let range = node.range {
                let end = min(original.lines.count, range.upperBound.line)
                if range.lowerBound.line <= end { literalLines.formUnion(range.lowerBound.line...end) }
            }
            if node is ListItem, let range = node.range {
                let end = min(original.lines.count, range.upperBound.line)
                if range.lowerBound.line <= end { ownedLines.formUnion(range.lowerBound.line...end) }
                let line = range.lowerBound.line, column = range.lowerBound.column - 1
                if original.lines.indices.contains(line - 1), column >= 0,
                   let tail = String(bytes: original.lines[line - 1].text.utf8.dropFirst(column), encoding: .utf8),
                   let prefix = MacBlockPrefix(tail), prefix.list {
                    prefixEnds[line] = max(prefixEnds[line] ?? 0, column + prefix.source.utf8.count)
                }
            }
            for child in node.children { collect(child) }
        }
        collect(document)
        guard !ownedLines.isEmpty else { return nil }
        let normalized = original.lines.enumerated().map { index, row -> String in
            guard ownedLines.contains(index + 1), !literalLines.contains(index + 1), row.text.contains("\t") else { return row.text + row.ending }
            let prefix = prefixEnds[index + 1].flatMap { String(bytes: row.text.utf8.prefix($0), encoding: .utf8) }
                ?? MacBlockPrefix(row.text)?.source ?? String(row.text.prefix { $0 == " " || $0 == "\t" })
            guard prefix.contains("\t") else { return row.text + row.ending }
            var expanded = "", column = 0
            for character in prefix {
                if character == "\t" { let width = 4 - column % 4; expanded += String(repeating: " ", count: width); column += width }
                else { expanded.append(character); column += 1 }
            }
            return expanded + row.text.dropFirst(prefix.count) + row.ending
        }.joined()
        guard !normalized.utf8.elementsEqual(source.utf8), !requiresLosslessSource(normalized) else { return nil }
        let parsed = Document(parsing: normalized), originalDocument = Document(parsing: source)
        guard HTMLFormatter.format(originalDocument).utf8.elementsEqual(HTMLFormatter.format(parsed).utf8) else { return nil }
        let rich = NSMutableAttributedString(attributedString: renderRaw(normalized, root: root, path: path, images: images))
        guard markdown(rich).utf8.elementsEqual(normalized.utf8) else { return nil }
        let canonical = MacMarkdownLines(normalized), text = rich.string as NSString
        var offset = 0, line = 0
        while offset < rich.length {
            if rich.attribute(.macCompactList, at: offset, effectiveRange: nil) is MacCompactList {
                var range = NSRange()
                guard let compact = rich.attribute(.macCompactList, at: offset, longestEffectiveRange: &range, in: NSRange(location: 0, length: rich.length)) as? MacCompactList,
                      range.location == offset else { return nil }
                let rows = MacMarkdownLines(compact.original).lines
                let count = rows.count - (rows.last?.text.isEmpty == true && rows.last?.ending.isEmpty == true ? 1 : 0)
                guard count > 0, line + count <= canonical.lines.count,
                      canonical.fragment(line..<(line + count)).utf8.elementsEqual(compact.original.utf8),
                      let end = prefixEnds[line + 1],
                      let prefix = String(bytes: original.lines[line].text.utf8.prefix(end), encoding: .utf8),
                      original.lines[line].text.dropFirst(prefix.count).utf8.elementsEqual(canonical.lines[line].text.dropFirst(compact.prefix.count).utf8) else { return nil }
                // The visible heads retain canonical column widths. Their
                // shared token keeps the original marker chain until expansion.
                let restored = MacCompactList(original: original.fragment(line..<(line + count)), prefix: prefix, fingerprint: compact.fingerprint, heads: compact.heads)
                rich.addAttribute(.macCompactList, value: restored, range: range)
                line += count; offset = NSMaxRange(range); continue
            }
            let cardKey: NSAttributedString.Key? = rich.attribute(.macCode, at: offset, effectiveRange: nil) != nil ? .macCode : rich.attribute(.macTable, at: offset, effectiveRange: nil) != nil ? .macTable : nil
            if let cardKey {
                var range = NSRange()
                _ = rich.attribute(cardKey, at: offset, longestEffectiveRange: &range, in: NSRange(location: 0, length: rich.length))
                guard range.location == offset else { return nil }
                // Cards keep their own source models. Advance only across an
                // unchanged spelling; never expand tabs in literal code/cells.
                let token = markdown(rich.attributedSubstring(from: range))
                let rows = MacMarkdownLines(token).lines
                let count = rows.count - (rows.last?.text.isEmpty == true && rows.last?.ending.isEmpty == true ? 1 : 0)
                guard count > 0, line + count <= canonical.lines.count,
                      canonical.fragment(line..<(line + count)).utf8.elementsEqual(token.utf8),
                      original.fragment(line..<(line + count)).utf8.elementsEqual(token.utf8) else { return nil }
                line += count; offset = NSMaxRange(range); continue
            }
            if rich.attribute(.macParagraphID, at: offset, effectiveRange: nil) != nil {
                var range = NSRange()
                _ = rich.attribute(.macParagraphID, at: offset, longestEffectiveRange: &range, in: NSRange(location: 0, length: rich.length))
                guard range.location == offset, let token = rich.attribute(.macParagraphSource, at: offset, effectiveRange: nil) as? String else { return nil }
                let rows = MacMarkdownLines(token).lines
                let count = rows.count - (rows.last?.text.isEmpty == true && rows.last?.ending.isEmpty == true ? 1 : 0)
                guard count > 0, line + count <= canonical.lines.count,
                      canonical.fragment(line..<(line + count)).utf8.elementsEqual(token.utf8) else { return nil }
                rich.addAttribute(.macParagraphSource, value: original.fragment(line..<(line + count)), range: range)
                line += count; offset = NSMaxRange(range)
            } else {
                let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
                guard line < canonical.lines.count, let token = rich.attribute(.macOriginal, at: offset, effectiveRange: nil) as? String,
                      canonical.lines[line].text.utf8.elementsEqual(token.utf8) else { return nil }
                rich.addAttribute(.macOriginal, value: original.lines[line].text, range: range)
                line += 1; offset = NSMaxRange(range)
            }
        }
        guard canonical.fragment(line..<canonical.lines.count).isEmpty, markdown(rich).utf8.elementsEqual(source.utf8) else { return nil }
        var parents: [Int?] = []
        func collectParents(_ node: any Markup, parent: Int? = nil) {
            var owner = parent
            if node is ListItem { owner = parents.count; parents.append(parent) }
            for child in node.children { collectParents(child, parent: owner) }
        }
        collectParents(originalDocument)
        guard nativeListItems(in: rich)?.map(\.parent) == parents else { return nil }
        return rich
    }

    private static func compactListRender(_ markdown: String, document: Markdown.Document, root: URL?, path: String, images: [String: NSImage]) -> NSAttributedString? {
        let source = MacMarkdownLines(markdown)
        var items: [Int: [ListItem]] = [:]
        func collect(_ node: any Markup) {
            if let item = node as? ListItem, let line = item.range?.lowerBound.line { items[line - 1, default: []].append(item) }
            for child in node.children { collect(child) }
        }
        collect(document)
        guard items.values.contains(where: { $0.count > 1 }) else { return nil }
        var compactTasks: [String: (Checkbox, Paragraph)] = [:]
        func location(_ node: any Markup) -> String {
            guard let start = node.range?.lowerBound else { return "" }
            return "\(start.line):\(start.column)"
        }
        var expanded = "", expandedLine = 1
        var groups: [(line: Int, start: Int, count: Int, prefix: String)] = []
        for (line, row) in source.lines.enumerated() {
            let owners = (items[line] ?? []).sorted { $0.range!.lowerBound.column < $1.range!.lowerBound.column }
            guard owners.count > 1, let first = owners.last?.child(at: 0),
                  first is Paragraph || first is Heading else {
                expanded += row.text + row.ending; expandedLine += 1; continue
            }
            var markers: [(NSRange, String)] = []
            for owner in owners {
                guard let column = owner.range?.lowerBound.column,
                      let before = String(bytes: row.text.utf8.prefix(column - 1), encoding: .utf8),
                      !before.contains("\t"),
                      let tail = String(bytes: row.text.utf8.dropFirst(column - 1), encoding: .utf8),
                      let prefix = MacBlockPrefix(tail), prefix.list, prefix.quotes.isEmpty, prefix.indent == 0,
                      !prefix.source.contains("\t") else { return nil }
                markers.append((NSRange(location: before.utf16.count, length: prefix.source.utf16.count), prefix.source))
            }
            // cmark omits the GFM checkbox on a shared marker line. The web
            // importer recognizes it. Adapt only that exact leaf marker and
            // its leading text; every other node still has to match below.
            if let owner = owners.last, owner.checkbox == nil,
               let marker = markers.last?.1, let prefix = MacBlockPrefix(marker), prefix.checklist,
               let paragraph = owner.child(at: 0) as? Paragraph,
               let first = paragraph.child(at: 0) as? Markdown.Text,
               let task = first.string.range(of: #"^\[[ xX]\][ \t]+"#, options: .regularExpression) {
                var children = paragraph.children.compactMap { $0 as? any InlineMarkup }
                let remaining = String(first.string[task.upperBound...])
                children.removeFirst()
                if !remaining.isEmpty { children.insert(Markdown.Text(remaining), at: 0) }
                compactTasks[location(owner)] = (prefix.marker.contains("[ ]") ? .unchecked : .checked, Paragraph(children))
            }
            let normalized = NSMutableString(string: row.text)
            for (range, _) in markers.dropLast() { normalized.replaceCharacters(in: range, with: String(repeating: " ", count: range.length)) }
            let last = markers.last!
            let prefix = (row.text as NSString).substring(to: NSMaxRange(last.0))
            groups.append((line, expandedLine, markers.count, prefix))
            for (range, marker) in markers.dropLast() {
                expanded += normalized.substring(to: range.location) + marker + source.ending(at: line)
                expandedLine += 1
            }
            expanded += (normalized as String) + row.ending; expandedLine += 1
        }
        guard !groups.isEmpty else { return nil }
        // Expanding only marker spelling must preserve the complete block tree
        // and paragraph text before native original-source tokens are attached.
        func structure(_ node: any Markup, adaptingCompactTasks: Bool) -> [String] {
            let adaptation = adaptingCompactTasks && node is ListItem ? compactTasks[location(node)] : nil
            var children = Array(node.children)
            if let adaptation { children[0] = adaptation.1 }
            let value = (node as? Paragraph)?.plainText ?? (node as? Heading)?.plainText ?? ""
            let task = (node as? ListItem).map { String(describing: adaptation?.0 ?? $0.checkbox) } ?? ""
            return ["\(type(of: node)):\(children.count):\(task):\(value)"] + children.flatMap { structure($0, adaptingCompactTasks: adaptingCompactTasks) }
        }
        let expandedDocument = Document(parsing: NoteReference.inlineMarkdown(expanded))
        let expandedStructure = structure(expandedDocument, adaptingCompactTasks: false)
        // Quoted task trees can already agree: preserve that exact match
        // before correcting a checkbox omitted only on the compact side.
        guard structure(document, adaptingCompactTasks: false) == expandedStructure ||
              structure(document, adaptingCompactTasks: true) == expandedStructure else { return nil }
        let rich = NSMutableAttributedString(attributedString: renderRaw(expanded, root: root, path: path, images: images))
        let mapping = serializedMarkdown(rich), raw = rich.string as NSString
        for group in groups {
            let positions = (0..<group.count).compactMap { line in mapping.headLines.first { $0.value == group.start + line }?.key }
            guard positions.count == group.count, positions == positions.sorted(),
                  let last = positions.last,
                  let token = rich.attribute(.macParagraphSource, at: last, effectiveRange: nil) as? String else { return nil }
            let range = NSRange(location: positions[0], length: NSMaxRange(raw.paragraphRange(for: NSRange(location: last, length: 0))) - positions[0])
            let rows = MacMarkdownLines(token).lines
            let count = rows.count - (rows.last?.text.isEmpty == true && rows.last?.ending.isEmpty == true ? 1 : 0)
            guard count > 0, group.line + count <= source.lines.count else { return nil }
            let heads = positions.compactMap { position -> (UUID, String)? in
                guard let context = rich.attribute(.macListContext, at: position, effectiveRange: nil) as? MacListContext else { return nil }
                return (context.id, context.source)
            }
            guard heads.count == group.count else { return nil }
            let original = source.fragment(group.line..<(group.line + count))
            let compact = MacCompactList(original: original, prefix: group.prefix, fingerprint: signature(rich.attributedSubstring(from: range), keys: SignatureKeys()), heads: heads)
            rich.addAttribute(.macCompactList, value: compact, range: range)
        }
        return rich
    }

    static func render(_ markdown: String, root: URL? = nil, path: String = "", images: [String: NSImage] = [:], initialExport: ((Export) -> Void)? = nil) -> NSAttributedString {
        var initial: Export?
        let value = renderRaw(markdown, root: root, path: path, images: images, initialExport: initialExport == nil ? nil : { initial = $0 })
        guard let numbered = normalizingOrderedLists(value) else {
            if let initial { initialExport?(initial) }
            return value
        }
        initialExport?(Export(numbered.text))
        return numbered.text
    }
    private static func renderRaw(_ markdown: String, root: URL? = nil, path: String = "", images: [String: NSImage] = [:], initialExport: ((Export) -> Void)? = nil) -> NSAttributedString {
        var markdown = markdown
        markdown.makeContiguousUTF8()
        let linkedSource = NoteReference.inlineMarkdown(markdown)
        let sourceDocument = Document(parsing: markdown)
        // Physical card ranges belong to raw source. Reference rendering may
        // change columns, so share its tree only when the bytes are identical.
        let sharesSourceTree = linkedSource.utf8.elementsEqual(markdown.utf8)
        let document = sharesSourceTree ? sourceDocument : Document(parsing: linkedSource)
        if markdown.contains("\t"), let rich = tabbedListRender(markdown, document: document, root: root, path: path, images: images) { return rich }
        let output = NSMutableAttributedString(), signatureKeys = SignatureKeys()
        let sourceLines = MacMarkdownLines(markdown), lines = sourceLines.contents
        let offsets = sourceLines.lines.map(\.offset)
        var consumed = 0
        let rootProse = sourceDocument.children.allSatisfy { $0 is Paragraph || $0 is Heading }
        // A standalone root paragraph has the same inline parse as its line.
        // Bracket syntax can depend on reference definitions elsewhere in the
        // document; keep that and normalized note references on the line path.
        var rootParagraphs: [Int: Paragraph] = [:]
        if sharesSourceTree {
            for case let paragraph as Paragraph in sourceDocument.children {
                guard let range = paragraph.range, range.lowerBound.line == range.upperBound.line else { continue }
                let index = range.lowerBound.line - 1
                guard lines.indices.contains(index), !lines[index].contains("["), MacBlockPrefix(lines[index]) == nil else { continue }
                rootParagraphs[index] = paragraph
            }
        }
        // These root nodes cannot own code or list/quote cards. The raw table
        // scanner still handles its own accepted pipe syntax independently.
        let ownedCards = rootProse ? [] : MacListCards.blocks(in: markdown, document: sourceDocument)
        let ownedRules = Dictionary(uniqueKeysWithValues: ownedCards.filter { $0.rule != nil }.map { ($0.source.range.location, $0) })
        let allCodes: [MacCodeBlock] = rootProse ? [] : MacCodeBlock.blocks(in: markdown, document: sourceDocument, ownedCards: ownedCards)
        let allTables = rootProse ? MacTableBlock.rootBlocks(in: markdown, excluding: []) :
            MacTableBlock.blocks(in: markdown, excluding: allCodes.map(\.range), document: sourceDocument, ownedCards: ownedCards)
        let codeBlocks = Dictionary(uniqueKeysWithValues: allCodes.map { ($0.range.location, $0) })
        let tables = Dictionary(uniqueKeysWithValues: allTables.map { ($0.range.location, $0) })
        // Fresh rendering knows each native row's original UTF-16 source span.
        // Keep a sparse map of independent root rows and canonical item heads;
        // untouched gaps retain their original bytes. Edits outside a mapped row
        // invalidate this export and use the complete serializer as before.
        var initialRows: [ExportRow] = []
        func recordInitialRow(from start: Int, source range: NSRange, block: String, independent: Bool, empty: Bool, text: NSString, bodyLength: Int, singleSource: Bool) {
            guard initialExport != nil, bodyLength > 0, !empty, singleSource else { return }
            let context = output.attribute(.macListContext, at: start, effectiveRange: nil) as? MacListContext
            let root = independent && context == nil && exportRootBlock(block)
            let list: Bool
            if let context, let prefix = exportListPrefix(context) {
                let marker = prefix.display.utf16.count
                list = bodyLength > marker && text.substring(to: marker) == prefix.display &&
                    !text.substring(with: NSRange(location: marker, length: bodyLength - marker)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } else { list = false }
            guard root || list else { return }
            // An edited root paragraph after a quote or item continuation may
            // need a separator that is not in its imported source. Let the full
            // serializer establish that boundary before caching it.
            if block.isEmpty, start > 0 {
                let previous = output.attributes(at: start - 1, effectiveRange: nil)
                let prefix = MacBlockPrefix(previous[.macBlock] as? String ?? "")
                if prefix?.list == true || (prefix?.depth ?? 0) > 0 ||
                    (previous[.macListContext] as? MacListContext)?.continuation == true { return }
            }
            let body = NSRange(location: start, length: bodyLength)
            var attached = false
            output.enumerateAttribute(.attachment, in: body) { value, _, stop in
                if value != nil { attached = true; stop.pointee = true }
            }
            guard !attached,
                  text.rangeOfCharacter(from: .newlines, options: [], range: NSRange(location: 0, length: bodyLength)).location == NSNotFound else { return }
            // Full row/context eligibility is checked when an edit touches it.
            initialRows.append(.init(native: NSRange(location: start, length: output.length - start), source: range, listContext: list ? context : nil, rootBlock: root ? block : nil))
        }
        var sharedItemLines = false
        var cardHeads: [String: MacListContext] = [:]
        for source in ownedCards.map(\.source) {
            for owner in source.owners where cardHeads[owner.key] == nil { cardHeads[owner.key] = MacListContext(source: owner.prefix) }
        }
        var quoted: [Int: (paragraph: Paragraph, end: Int, block: String)] = [:]
        var independentLines = Set<Int>(), ruleLines = Set<Int>()
        var rootHeadings: [Int: (node: Heading, end: Int, block: String)] = [:]
        var wrapped: [Int: (blocks: [any Markup], end: Int, context: MacListContext)] = [:]
        var itemHeads: [Int: MacListContext] = [:]
        var childGaps: [Int: (parent: UUID, childLine: Int)] = [:]
        var quoteGaps: [Int: MacListContext] = [:]
        var firstChildList: [UUID: Int] = [:]
        var headingRanges = MacItemHeadingRanges(lines: lines)
        func itemHeadingRange(_ heading: Heading) -> (start: Int, end: Int)? { headingRanges.range(for: heading) }
        func firstBodyPrefix(_ node: any Markup) -> String {
            if let heading = node as? Heading { return itemHeadingRange(heading) == nil ? "" : String(repeating: "#", count: heading.level) + " " }
            if node is BlockQuote { return "> " + (node.child(at: 0).map { firstBodyPrefix($0) } ?? "") }
            return ""
        }
        func firstBodyIsQuoteLeaf(_ node: any Markup) -> Bool {
            guard node is BlockQuote else { return false }
            return node.childCount == 0 || node.child(at: 0).map { firstBodyIsQuoteLeaf($0) } == true
        }
        func blankSeparator(_ line: String) -> Bool {
            // Foundation treats the intentional empty-paragraph anchor as
            // whitespace. It is content, never a gap for the following block.
            if line.contains(emptyParagraphMarker) { return false }
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            guard let prefix = MacBlockPrefix(line), prefix.depth > 0, !prefix.list, !prefix.heading else { return false }
            return line.dropFirst(prefix.source.count).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        func collectQuotes(_ node: any Markup, depth: Int = 0, inList: Bool = false, owner: MacListContext? = nil, ownerDepth: Int = 0) {
            var nextOwner = owner, nextOwnerDepth = ownerDepth
            let depth = depth + (node is BlockQuote ? 1 : 0)
            if !inList, node is ThematicBreak, let line = node.range?.lowerBound.line { ruleLines.insert(line - 1) }
            if !inList, let heading = node as? Heading, let span = itemHeadingRange(heading) {
                let start = span.start, end = span.end
                let prefix = MacBlockPrefix(lines[start])
                independentLines.formUnion(start..<end)
                let indentation = prefix?.indentation ?? String(lines[start].prefix { $0 == " " || $0 == "\t" })
                let block = prefix?.heading == true ? prefix!.source : (prefix?.quotes ?? "") + indentation + String(repeating: "#", count: heading.level) + " "
                rootHeadings[start] = (heading, end, block)
            } else if !inList, node is Paragraph || (node as? HTMLBlock).map({ MacInlineImage(html: $0.rawHTML) != nil }) == true, let range = node.range {
                let start = range.lowerBound.line - 1
                if node is HTMLBlock { independentLines.insert(start) }
                else if start >= 0, range.upperBound.line <= lines.count { independentLines.formUnion(start..<range.upperBound.line) }
            }
            if node is ListItem, let markerLine = node.range.map({ $0.lowerBound.line - 1 }),
               lines.indices.contains(markerLine), let originalPrefix = listPrefix(node, lines: lines) {
                let key = "\(markerLine + 1):\(node.range!.lowerBound.column)"
                func hasInnerText(_ child: any Markup) -> Bool {
                    if child is Heading || child is Paragraph { return true }
                    return child.children.contains(where: hasInnerText)
                }
                let textContainers = node.children.contains { $0 is Heading || $0 is BlockQuote && hasInnerText($0) }
                // Cards share item identity, while the head's own text keeps
                // its independent heading/quote role.
                let cardHead = cardHeads[key]
                let head = MacListContext(id: cardHead?.id ?? UUID(), source: cardHead?.source ?? originalPrefix.source, suffix: node.child(at: 0).map { child in
                    let start = (child as? Heading).flatMap { itemHeadingRange($0)?.start } ?? child.range.map { $0.lowerBound.line - 1 }
                    return start == markerLine ? firstBodyPrefix(child) : ""
                } ?? "", blockParagraph: textContainers && node.child(at: 0).map(isEmptyParagraphMarker) == true, quoteLeaf: node.child(at: 0).map(firstBodyIsQuoteLeaf) == true,
                    quoteParents: (owner?.quoteParents ?? []) + (depth > ownerDepth ? owner.map { [$0] } ?? [] : []))
                let prefix = MacBlockPrefix(head.source) ?? originalPrefix
                if itemHeads[markerLine] != nil { sharedItemLines = true }
                itemHeads[markerLine] = head
                firstChildList[head.id] = node.children.filter { $0 is OrderedList || $0 is UnorderedList }.compactMap { $0.range?.lowerBound.line }.min()
                nextOwner = head; nextOwnerDepth = depth
                var precedingEnd = markerLine + 1
                for child in node.children {
                    if let paragraph = child as? Paragraph, let range = paragraph.range {
                        precedingEnd = range.upperBound.line
                    } else if child is OrderedList || child is UnorderedList {
                        if let start = child.range.map({ $0.lowerBound.line - 1 }), precedingEnd < start {
                            for index in precedingEnd..<start where lines.indices.contains(index) && blankSeparator(lines[index]) {
                                childGaps[index] = (head.id, start)
                            }
                        }
                        break
                    } else { break }
                }
                var group: [Paragraph] = [], sawChildList = false
                func appendGroup() {
                    defer { group.removeAll() }
                    guard let first = group.first?.range, let last = group.last?.range else { return }
                    let start = first.lowerBound.line - 1, end = last.upperBound.line
                    guard start >= 0, end <= lines.count, end > start else { return }
                    // A paragraph after an otherwise empty source marker is
                    // still this item's first body, not another editable row.
                    let delayedHead = start > markerLine && node.child(at: 0) is Paragraph &&
                        node.child(at: 0)?.range?.lowerBound.line == first.lowerBound.line &&
                        lines[markerLine].dropFirst(prefix.source.count).trimmingCharacters(in: .whitespaces).isEmpty
                    let continuation = start != markerLine && !delayedHead
                    // A marker-looking line can be a lazy paragraph continuation
                    // in CommonMark. Keep the existing per-line fallback for that
                    // source-only shape instead of swallowing its visible marker.
                    if !continuation, end > start + 1,
                       lines[(start + 1)..<end].contains(where: { MacBlockPrefix($0)?.list == true }) {
                        group.removeAll(); return
                    }
                    var begin = delayedHead ? markerLine : start
                    if continuation { while begin > markerLine + 1 && blankSeparator(lines[begin - 1]) { begin -= 1 } }
                    let gap = sourceLines.fragment(begin..<start)
                    let context = continuation ? MacListContext(id: head.id, source: prefix.source, continuation: true, gap: gap, originatedAfterChildren: sawChildList, blockParagraph: textContainers, quoteParents: head.quoteParents) : head
                    wrapped[begin] = (group, end, context)
                    group.removeAll()
                }
                for child in node.children {
                    if let paragraph = child as? Paragraph {
                        group.append(paragraph)
                        if textContainers { appendGroup() }
                    }
                    else { appendGroup(); if child is OrderedList || child is UnorderedList || child is ThematicBreak { sawChildList = true } }
                }
                appendGroup()
            }
            if inList, node is BlockQuote, node.childCount > 0, let owner, let span = node.range,
               let prefix = MacBlockPrefix(owner.source) {
                let continuation = prefix.listContinuation
                for index in max(0, span.lowerBound.line - 1)..<min(lines.count, span.upperBound.line) {
                    let line = lines[index]
                    if blankSeparator(line), line.hasPrefix(continuation),
                       let blank = MacBlockPrefix(line), blank.depth > prefix.depth {
                        quoteGaps[index] = MacListContext(id: owner.id, source: owner.source, continuation: true,
                            suffix: String(line.dropFirst(continuation.count)).trimmingCharacters(in: .newlines), quoteParents: owner.quoteParents)
                    }
                }
            }
            let innerHeading = inList ? (node as? Heading).flatMap { itemHeadingRange($0) } : nil
            if inList, innerHeading != nil || (node is Paragraph && node.parent is BlockQuote && depth > ownerDepth) || (node is BlockQuote && node.childCount == 0), let owner,
               let start = innerHeading?.start ?? node.range.map({ $0.lowerBound.line - 1 }),
               let end = innerHeading?.end ?? node.range?.upperBound.line {
                if start >= 0, end <= lines.count, end > start {
                    let isHead = itemHeads[start]?.id == owner.id
                    var begin = start
                    if !isHead { while begin > 0 && blankSeparator(lines[begin - 1]) { begin -= 1 } }
                    let suffix = String(repeating: "> ", count: max(0, depth - ownerDepth)) + ((node as? Heading).map { String(repeating: "#", count: $0.level) + " " } ?? "")
                    let context = isHead ? itemHeads[start]! : MacListContext(id: owner.id, source: owner.source, continuation: true, gap: sourceLines.fragment(begin..<start), originatedAfterChildren: firstChildList[owner.id].map { $0 < start + 1 } ?? false, suffix: suffix, quoteLeaf: node is BlockQuote && node.childCount == 0, quoteParents: owner.quoteParents)
                    wrapped[begin] = ([node], end, context)
                }
            }
            if let paragraph = node as? Paragraph, depth > 0, !inList, let range = node.range {
                let start = range.lowerBound.line - 1, end = range.upperBound.line
                if start >= 0, end <= lines.count, end > start + 1 {
                    let prefix = MacBlockPrefix(lines[start])
                    let block = prefix?.depth == depth ? prefix!.source : String(repeating: "> ", count: depth)
                    quoted[start] = (paragraph, end, block)
                }
            }
            for child in node.children { collectQuotes(child, depth: depth, inList: inList || node is ListItem, owner: nextOwner, ownerDepth: nextOwnerDepth) }
        }
        collectQuotes(document)
        if sharedItemLines, let compact = compactListRender(markdown, document: document, root: root, path: path, images: images) { return compact }
        func appendParagraph(_ parsed: any Markup, from index: Int, to end: Int, block: String, item: [any Markup]? = nil, context: MacListContext? = nil) {
            let original = sourceLines.fragment(index..<end)
            var base: [NSAttributedString.Key: Any] = [.font: font(context?.textBlock ?? block), .foregroundColor: NSColor.labelColor, .paragraphStyle: context?.style ?? paragraphStyle(block), .macBlock: block, .macLineEnding: sourceLines.ending(at: index)]
            if let context, MacBlockPrefix(context.textBlock)?.heading == true { base[.macStrong] = false }
            base[.macIndependentParagraph] = independentLines.contains(index)
            if isEmptyParagraphMarker(parsed) { base[.macEmptyParagraph] = true }
            if let context { base[.macListContext] = context }
            let paragraph = NSMutableAttributedString()
            if let item {
                for (number, node) in item.enumerated() {
                    if number > 0 {
                        var attrs = base; attrs[.macListBreak] = 2
                        paragraph.append(NSAttributedString(string: "\u{2028}\u{2028}", attributes: attrs))
                    }
                    let part = NSMutableAttributedString(attributedString: inline(node, attributes: base, root: root, path: path, images: images))
                    if number == 0, context?.continuation != true,
                       let prefix = MacBlockPrefix(block), prefix.checklist,
                       (node.parent as? ListItem)?.checkbox == nil {
                        // cmark removes parsed task syntax itself. Only strip a
                        // still-literal marker (not another bracketed body value),
                        // including all of its original marker whitespace.
                        let syntax = String(prefix.marker.dropFirst(prefix.listPadding))
                        if !syntax.isEmpty, part.string.hasPrefix(syntax) {
                            part.deleteCharacters(in: NSRange(location: 0, length: syntax.utf16.count))
                        } else if part.string == syntax.trimmingCharacters(in: .whitespaces) {
                            // An empty quoted task loses its trailing marker space
                            // in cmark's paragraph text. It still has no body text.
                            part.deleteCharacters(in: NSRange(location: 0, length: part.length))
                        }
                    }
                    let raw = part.string as NSString
                    for location in (0..<raw.length).reversed() where raw.character(at: location) == 10 {
                        let hard = part.attribute(.macHardBreak, at: location, effectiveRange: nil) as? Bool == true
                        part.replaceCharacters(in: NSRange(location: location, length: 1), with: hard ? "\u{2028}" : " ")
                        if hard { part.addAttribute(.macListBreak, value: 1, range: NSRange(location: location, length: 1)) }
                    }
                    paragraph.append(part)
                }
                paragraph.insert(NSAttributedString(string: displayPrefix(block), attributes: base), at: 0)
            } else {
                let part = NSMutableAttributedString(attributedString: inline(parsed, attributes: base, root: root, path: path, images: images))
                if MacBlockPrefix(block)?.heading == true {
                    let raw = part.string as NSString
                    for location in (0..<raw.length).reversed() where raw.character(at: location) == 10 {
                        part.replaceCharacters(in: NSRange(location: location, length: 1), with: " ")
                        part.removeAttribute(.macHardBreak, range: NSRange(location: location, length: 1))
                    }
                }
                paragraph.append(part)
            }
            let bodyLength = paragraph.length
            if end < lines.count { paragraph.append(NSAttributedString(string: "\n", attributes: base)) }
            else if paragraph.length == 0, !original.isEmpty {
                // An empty final block still needs a native row for its role
                // and source token. This newline has no source bytes.
                var terminal = base; terminal[.macUnterminated] = true
                paragraph.append(NSAttributedString(string: "\n", attributes: terminal))
            }
            let text = paragraph.string as NSString
            var lineIndex = item != nil ? end - 1 : index
            for location in 0..<text.length where text.character(at: location) == 10 {
                paragraph.addAttribute(.macLineEnding, value: sourceLines.ending(at: min(lineIndex, end - 1)), range: NSRange(location: location, length: 1)); lineIndex += 1
            }
            let range = NSRange(location: 0, length: paragraph.length), fingerprint = signature(paragraph, keys: signatureKeys)
            paragraph.addAttributes([.macParagraphID: UUID().uuidString, .macParagraphSource: original, .macParagraphSignature: fingerprint], range: range)
            let start = output.length
            output.append(paragraph)
            if initialExport != nil {
                recordInitialRow(from: start, source: NSRange(location: offsets[index], length: original.utf16.count), block: block,
                    independent: base[.macIndependentParagraph] as? Bool == true, empty: base[.macEmptyParagraph] as? Bool == true,
                    text: text, bodyLength: bodyLength, singleSource: end == index + 1)
            }
        }
        func appendCard(_ value: NSAttributedString, source: MacListCardSource?) {
            let head = source.flatMap { cardHeads["\($0.ownerLine):\($0.ownerColumn)"] ?? itemHeads[$0.ownerLine - 1] }
            let inline = source.map { source in source.owners.filter { sourceLines.lines[$0.line - 1].offset == source.range.location }.compactMap { cardHeads[$0.key] } } ?? []
            for head in inline {
                let attrs: [NSAttributedString.Key: Any] = [.macListContext: head, .macBlock: head.source, .macLineEnding: sourceLines.ending(at: source!.ownerLine - 1), .font: font(head.source), .foregroundColor: NSColor.labelColor, .paragraphStyle: head.style]
                output.append(NSAttributedString(string: displayPrefix(head.source) + "\n", attributes: attrs))
            }
            let placed = MacListCardPlacement.placed(value, source: source, head: head, inlineHeads: inline)
            if let head {
                var start: Int?
                output.enumerateAttribute(.macListContext, in: NSRange(location: 0, length: output.length)) { item, range, _ in
                    if let context = item as? MacListContext, context.id == head.id, !context.continuation {
                        start = NSMaxRange((output.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 0)))
                    }
                }
                if let start, start < output.length {
                    let gap = NSRange(location: start, length: output.length - start)
                    if output.attributedSubstring(from: gap).string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        output.addAttribute(.macListGap, value: MacListGap(parent: head.id, child: head.id), range: gap)
                    }
                }
            }
            output.append(placed)
        }
        func plainLine(_ line: String, at index: Int) -> Bool {
            if rootParagraphs[index] != nil { return true }
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  MacBlockPrefix(line) == nil else { return false }
            let parsed = Document(parsing: NoteReference.inlineMarkdown(line))
            return parsed.childCount == 1 && parsed.child(at: 0) is Paragraph
        }
        for (index, original) in lines.enumerated() {
            if index < consumed { continue }
            if let card = ownedRules[offsets[index]], let rule = card.rule {
                appendCard(MacHorizontalRule.render(rule, ending: sourceLines.lines[index].ending, preferredEnding: sourceLines.ending(at: index)), source: card.source)
                consumed = index + MacMarkdownLines(card.source.original).lines.count
                continue
            }
            if let block = tables[offsets[index]] {
                let suffix = (markdown as NSString).substring(from: NSMaxRange(block.range))
                let ending = MacMarkdownLines.leadingEnding(suffix)
                appendCard(MacRichTable.render(block.table, ending: ending, root: root, path: path, images: images, quote: block.quote), source: block.container)
                consumed = index + MacMarkdownLines(block.container?.original ?? block.quote?.original ?? block.table.markdown).lines.count; continue
            }
            if let block = codeBlocks[offsets[index]] {
                let suffix = (markdown as NSString).substring(from: NSMaxRange(block.range))
                let ending = MacMarkdownLines.leadingEnding(suffix)
                appendCard(MacRichCode.render(block.code, ending: ending, indented: block.indented, quote: block.quote), source: block.container)
                consumed = index + MacMarkdownLines(block.container?.original ?? block.code.markdown).lines.count
                continue
            }
            if ruleLines.contains(index) {
                output.append(MacHorizontalRule.render(original, ending: sourceLines.lines[index].ending, preferredEnding: sourceLines.ending(at: index)))
                continue
            }
            if let item = wrapped[index] {
                appendParagraph(item.blocks[0], from: index, to: item.end, block: item.context.block, item: item.blocks, context: item.context)
                consumed = item.end; continue
            }
            if let context = quoteGaps[index] {
                appendParagraph(Paragraph(), from: index, to: index + 1, block: context.block, context: context)
                continue
            }
            if let heading = rootHeadings[index], heading.end > index, heading.end <= lines.count {
                appendParagraph(heading.node, from: index, to: heading.end, block: heading.block)
                consumed = heading.end; continue
            }
            if let quote = quoted[index] {
                appendParagraph(quote.paragraph, from: index, to: quote.end, block: quote.block)
                consumed = quote.end; continue
            }
            if plainLine(original, at: index) {
                var end = index + 1
                while end < lines.count, tables[offsets[end]] == nil, codeBlocks[offsets[end]] == nil,
                      rootHeadings[end] == nil, !ruleLines.contains(end), plainLine(lines[end], at: end) { end += 1 }
                if end > index + 1 {
                    let original = sourceLines.fragment(index..<end)
                    appendParagraph(Document(parsing: NoteReference.inlineMarkdown(original)), from: index, to: end, block: "")
                    consumed = end; continue
                }
            }
            var text = original, block = ""
            if let prefix = MacBlockPrefix(text) { block = prefix.source; text.removeFirst(block.count) }
            let style = paragraphStyle(block)
            var base: [NSAttributedString.Key: Any] = [.font: font(block), .foregroundColor: NSColor.labelColor, .paragraphStyle: style, .macBlock: block, .macLineEnding: sourceLines.ending(at: index)]
            base[.macIndependentParagraph] = independentLines.contains(index)
            if let context = itemHeads[index] { base[.macListContext] = context }
            if let gap = childGaps[index], let child = itemHeads[gap.childLine] {
                base[.macListGap] = MacListGap(parent: gap.parent, child: child.id)
            }
            let line = NSMutableAttributedString(string: text, attributes: base)
            let heading = MacBlockPrefix(block)?.heading == true
            let parsed: any Markup = rootParagraphs[index] ?? Document(parsing: NoteReference.inlineMarkdown(heading ? original : text))
            if isEmptyParagraphMarker(parsed) { base[.macEmptyParagraph] = true }
            if heading, let node = firstHeading(parsed) {
                line.setAttributedString(inline(node, attributes: base, root: root, path: path, images: images))
            } else { line.setAttributedString(inline(parsed, attributes: base, root: root, path: path, images: images)) }
            let prefix = displayPrefix(block)
            if !prefix.isEmpty { line.insert(NSAttributedString(string: prefix, attributes: base), at: 0) }
            let signature = signature(line, keys: signatureKeys)
            if line.length > 0 { line.addAttributes([.macOriginal: original, .macSignature: signature], range: NSRange(location: 0, length: line.length)) }
            let start = output.length
            output.append(line)
            if index < lines.count - 1 || line.length == 0 && !original.isEmpty {
                var newlineAttrs = base; newlineAttrs[.macLineEnding] = sourceLines.ending(at: index)
                if index == lines.count - 1 { newlineAttrs[.macUnterminated] = true }
                if line.length == 0 { newlineAttrs[.macOriginal] = original; newlineAttrs[.macSignature] = signature }
                output.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
            }
            if initialExport != nil {
                let source = sourceLines.lines[index]
                recordInitialRow(from: start, source: source.range, block: block,
                    independent: base[.macIndependentParagraph] as? Bool == true, empty: base[.macEmptyParagraph] as? Bool == true,
                    text: line.string as NSString, bodyLength: line.length, singleSource: true)
            }
        }
        initialExport?(Export(renderedSource: markdown, rows: initialRows))
        return output
    }
    static func renderTableCell(_ source: String, attributes: [NSAttributedString.Key: Any], root: URL?, path: String, images: [String: NSImage]) -> NSAttributedString {
        let rich = NSMutableAttributedString(attributedString: inline(Document(parsing: "x " + NoteReference.inlineMarkdown(source), options: [.disableSmartOpts]), attributes: attributes, root: root, path: path, images: images, tableBreaks: true))
        if rich.length > 0 { rich.deleteCharacters(in: NSRange(location: 0, length: min(2, rich.length))) }
        return rich
    }
    static func tableCellMarkdown(_ rich: NSAttributedString) -> String {
        let raw = rich.string as NSString
        var start = 0, lines: [String] = []
        for index in 0..<raw.length where [10, 13, 0x2028, 0x2029].contains(Int(raw.character(at: index))) {
            lines.append(serializeInline(rich.attributedSubstring(from: NSRange(location: start, length: index - start)), block: "")); start = index + 1
        }
        lines.append(serializeInline(rich.attributedSubstring(from: NSRange(location: start, length: raw.length - start)), block: ""))
        return lines.joined(separator: "<br>")
    }
    /// Paragraph payloads have block boundaries, unlike inline hard breaks.
    /// Parse them together so soft wrapping and cross-line styles stay intact.
    struct PasteParagraph {
        let text: NSAttributedString
        let empty: Bool
    }
    static func pasteParagraphs(_ markdown: String, root: URL?, path: String, images: [String: NSImage], minimumCount: Int = 2) -> [PasteParagraph]? {
        let document = Document(parsing: NoteReference.inlineMarkdown(markdown))
        let nodes = Array(document.children)
        guard nodes.count >= minimumCount, nodes.enumerated().allSatisfy({ $0.element is Paragraph || nodes.count > 1 && $0.offset == 0 && $0.element is Heading }) else { return nil }
        return nodes.map { pasteParagraph($0, root: root, path: path, images: images) }
    }
    private static func pasteParagraph(_ node: any Markup, root: URL?, path: String, images: [String: NSImage]) -> PasteParagraph {
        var attrs: [NSAttributedString.Key: Any] = [.font: font(""), .foregroundColor: NSColor.labelColor, .macBlock: "", .macIndependentParagraph: true, .paragraphStyle: paragraphStyle("")]
        if isEmptyParagraphMarker(node) { attrs[.macEmptyParagraph] = true }
        let value = NSMutableAttributedString(attributedString: inline(node, attributes: attrs, root: root, path: path, images: images))
        let raw = value.string as NSString
        for location in (0..<raw.length).reversed() where raw.character(at: location) == 10 {
            let hard = value.attribute(.macHardBreak, at: location, effectiveRange: nil) as? Bool == true
            value.replaceCharacters(in: NSRange(location: location, length: 1), with: hard ? "\u{2028}" : " ")
            if hard { value.addAttribute(.macListBreak, value: 1, range: NSRange(location: location, length: 1)) }
        }
        return PasteParagraph(text: value, empty: isEmptyParagraphMarker(node))
    }
    /// Preserve endpoint bodies separately from the intervening block nodes.
    /// Lower bounds delimit source slices, avoiding setext heading end ranges.
    static func pasteStructure(_ markdown: String, root: URL?, path: String, images: [String: NSImage]) -> (first: PasteParagraph?, last: PasteParagraph?, middle: String)? {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var offset = 0
        let lineOffsets = lines.map { line in defer { offset += line.utf16.count + 1 }; return offset }
        let metadata = Dictionary(uniqueKeysWithValues: tables(in: normalized).filter { !$0.table.widthMarker.isEmpty }.map { ($0.range.location, $0.table.widthMarker.trimmingCharacters(in: .whitespacesAndNewlines)) })
        func tableMetadata(_ node: any Markup) -> Bool {
            guard let html = node as? HTMLBlock, let line = html.range?.lowerBound.line, line > 0, line <= lineOffsets.count,
                  let marker = metadata[lineOffsets[line - 1]] else { return false }
            return html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines) == marker
        }
        let nodes = Array(Document(parsing: NoteReference.inlineMarkdown(normalized)).children)
        guard !nodes.isEmpty, nodes.count > 1 || nodes[0] is OrderedList || nodes[0] is UnorderedList || nodes[0] is BlockQuote || nodes[0] is CodeBlock || nodes[0] is Markdown.Table || nodes[0] is ThematicBreak || tableMetadata(nodes[0]),
              nodes.allSatisfy({ $0 is Paragraph || $0 is Heading || $0 is OrderedList || $0 is UnorderedList || $0 is BlockQuote || $0 is CodeBlock || $0 is Markdown.Table || $0 is ThematicBreak || tableMetadata($0) }) else { return nil }
        let leading = nodes.count > 1 && (nodes[0] is Paragraph || nodes[0] is Heading)
        let trailing = nodes.count > 1 && nodes.last is Paragraph
        let start = leading ? 1 : 0, end = nodes.count - (trailing ? 1 : 0)
        guard start < end, nodes[start..<end].contains(where: { !($0 is Paragraph) }) else { return nil }
        guard let lower = nodes[start].range?.lowerBound.line else { return nil }
        let upper = end < nodes.count ? nodes[end].range?.lowerBound.line : lines.count + 1
        guard let upper, lower > 0, lower <= upper, upper <= lines.count + 1 else { return nil }
        let middle = lines[(lower - 1)..<(upper - 1)].joined(separator: "\n")
        guard !requiresLosslessSource(middle) else { return nil }
        return (leading ? pasteParagraph(nodes[0], root: root, path: path, images: images) : nil,
                trailing ? pasteParagraph(nodes[nodes.count - 1], root: root, path: path, images: images) : nil, middle)
    }
    private static func inline(_ node: any Markup, attributes: [NSAttributedString.Key: Any], root: URL?, path: String, images: [String: NSImage], tableBreaks: Bool = false) -> NSAttributedString {
        var attrs = attributes
        if let text = node as? Markdown.Text {
            let emptyMarker = text.string == emptyParagraphMarker && text.parent.map { isEmptyParagraphMarker($0) } == true
            return NSAttributedString(string: emptyMarker ? "" : text.string, attributes: attrs)
        }
        if let html = node as? InlineHTML, html.rawHTML.range(of: #"(?i)^<br\s*/?>$"#, options: .regularExpression) != nil {
            if !tableBreaks { attrs[.macListBreak] = 3 }
            return NSAttributedString(string: "\u{2028}", attributes: attrs)
        }
        if let code = node as? InlineCode {
            let block = attrs[.macBlock] as? String ?? "", inherited = attrs[.font] as? NSFont ?? font(block)
            attrs[.font] = inlineFont(block: block, bold: inlineBold(attrs, block: block), italic: NSFontManager.shared.traits(of: inherited).contains(.italicFontMask), code: true)
            attrs[.backgroundColor] = NSColor.quaternaryLabelColor
            return NSAttributedString(string: code.code, attributes: attrs)
        }
        if node is SoftBreak || node is LineBreak { if node is LineBreak { attrs[.macHardBreak] = true }; return NSAttributedString(string: "\n", attributes: attrs) }
        if let html = node as? InlineHTML {
            if let image = MacInlineImage(html: html.rawHTML) { return renderImage(image, literal: html.rawHTML, attributes: attrs, root: root, path: path, images: images) }
            return NSAttributedString(string: html.rawHTML, attributes: attrs)
        }
        if let html = node as? HTMLBlock,
           html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"(?i)^<br\s*/?>$"#, options: .regularExpression) != nil {
            attrs[.macListBreak] = 3
            return NSAttributedString(string: "\u{2028}", attributes: attrs)
        }
        if let html = node as? HTMLBlock, let image = MacInlineImage(html: html.rawHTML) { return renderImage(image, literal: html.rawHTML.trimmingCharacters(in: .newlines), attributes: attrs, root: root, path: path, images: images) }
        if let imageNode = node as? Markdown.Image {
            let image = MacInlineImage(imageNode)
            return renderImage(image, literal: image.markdown, attributes: attrs, root: root, path: path, images: images)
        }
        if node is Strong { attrs[.macStrong] = true; attrs[.font] = NSFontManager.shared.convert(attrs[.font] as? NSFont ?? .systemFont(ofSize: 15), toHaveTrait: .boldFontMask) }
        if node is Emphasis { attrs[.font] = NSFontManager.shared.convert(attrs[.font] as? NSFont ?? .systemFont(ofSize: 15), toHaveTrait: .italicFontMask) }
        if node is Strikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = node as? Markdown.Link, let destination = link.destination { attrs[.link] = destination; attrs[.macLinkTitle] = link.title; attrs[.foregroundColor] = accent }
        let output = NSMutableAttributedString(), tags = NativeInlineHTML.paired(in: node)
        var current = attrs, stack: [[NSAttributedString.Key: Any]] = []
        for (index, child) in node.children.enumerated() {
            if let tag = tags[index] {
                if tag.closing { current = stack.removeLast() }
                else {
                    stack.append(current)
                    var font = current[.font] as? NSFont ?? self.font(current[.macBlock] as? String ?? "")
                    if tag.flags & 1 != 0 { current[.macStrong] = true; font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                    if tag.flags & 2 != 0 { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                    current[.font] = font
                    if tag.flags & 4 != 0 { current[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    if tag.flags & 16 != 0 { current[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                }
            } else { output.append(inline(child, attributes: current, root: root, path: path, images: images, tableBreaks: tableBreaks)) }
        }
        return output
    }
    private static func renderImage(_ image: MacInlineImage, literal: String, attributes: [NSAttributedString.Key: Any], root: URL?, path: String, images: [String: NSImage]) -> NSAttributedString {
        var attrs = attributes; attrs[.macLiteral] = literal
        let stored = root.flatMap { try? VaultFiles.resolveResource(image.reference, notePath: path, root: $0) }.flatMap(NSImage.init(contentsOf:))
        if let loaded = images[image.reference] ?? stored {
            let token = NSMutableAttributedString(attachment: MacImageAttachment(image: loaded, size: image.size(for: loaded)))
            token.addAttributes(attrs, range: NSRange(location: 0, length: token.length)); return token
        }
        let placeholder = MacUnavailableImage.image(caption: image.caption)
        let token = NSMutableAttributedString(attachment: MacImageAttachment(image: placeholder, size: placeholder.size))
        attrs[.macImageUnavailable] = true
        token.addAttributes(attrs, range: NSRange(location: 0, length: token.length)); return token
    }
    private static func codeLiteral(_ text: String) -> String {
        var longest = 0, run = 0
        let bytes = text.utf8
        for byte in bytes { if byte == 96 { run += 1; longest = max(longest, run) } else { run = 0 } }
        let fence = String(repeating: "`", count: max(1, longest + 1))
        // CommonMark trims one edge space only when both ends are spaces and
        // the content is not all spaces. Padding also separates edge backticks.
        let padding = bytes.first == 96 || bytes.last == 96 || (bytes.first == 32 && bytes.last == 32 && bytes.contains { $0 != 32 })
        return fence + (padding ? " " : "") + text + (padding ? " " : "") + fence
    }
    private static func serializeInline(_ line: NSAttributedString, block: String, continuation override: String? = nil) -> String {
        var output = "", active: [String] = [], cursor = 0, whitespace = ""
        var logicalStart = 0
        func protectLogicalLine() {
            let raw = output as NSString
            var body = raw.substring(from: logicalStart)
            if body.unicodeScalars.allSatisfy({ $0.value == 32 || $0.value == 9 }) {
                // A blank line is structural Markdown, not literal prose content.
                output = raw.substring(to: logicalStart) + body
                return
            }
            body = body.replacingOccurrences(of: #"^([ \t]{0,3})(#{1,6}|[-+])(?=\s|$)"#, with: #"$1\\$2"#, options: .regularExpression)
            body = body.replacingOccurrences(of: #"^([ \t]{0,3})(\d{1,9})([.)])(?=\s|$)"#, with: #"$1$2\\$3"#, options: .regularExpression)
            body = body.replacingOccurrences(of: #"^([ \t]{0,3})([-=])(?=[-=]*\s*$)"#, with: #"$1\\$2"#, options: .regularExpression)
            if body.range(of: #"^[ \t]{0,3}(?=[^\n]*\|)\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$"#, options: .regularExpression) != nil {
                body = body.replacingOccurrences(of: #"[-|]"#, with: #"\\$0"#, options: .regularExpression)
            }
            if MacBlockPrefix(block)?.heading == true,
               let closing = body.range(of: #"(?<![^ \t])#+(?=[ \t]*$)"#, options: .regularExpression) {
                let literal = body[closing].map { "\\" + String($0) }.joined()
                body.replaceSubrange(closing, with: literal)
            }
            let indentation = body.unicodeScalars.prefix { $0.value == 32 || $0.value == 9 }
            if !indentation.isEmpty {
                // These are literal spaces in native prose, not Markdown block
                // indentation. Entities keep them visible without creating code.
                body = indentation.map { $0.value == 9 ? "&#9;" : "&#32;" }.joined() + String(body.unicodeScalars.dropFirst(indentation.count))
            }
            let trailing = body.unicodeScalars.reversed().prefix { $0.value == 32 || $0.value == 9 }
            if !trailing.isEmpty {
                body = String(body.unicodeScalars.dropLast(trailing.count)) + trailing.reversed().map { $0.value == 9 ? "&#9;" : "&#32;" }.joined()
            }
            output = raw.substring(to: logicalStart) + body
        }
        let full = NSRange(location: 0, length: line.length)
        func styles(_ attrs: [NSAttributedString.Key: Any]) -> [String] {
            let font = attrs[.font] as? NSFont ?? self.font(block), traits = NSFontManager.shared.traits(of: font)
            var wanted: [String] = []
            if (attrs[.underlineStyle] as? Int ?? 0) != 0 { wanted.append("<u>") }
            if inlineBold(attrs, block: block) { wanted.append("**") }
            if traits.contains(.italicFontMask) { wanted.append("*") }
            if (attrs[.strikethroughStyle] as? Int ?? 0) != 0 { wanted.append("~~") }
            return wanted
        }
        func transition(_ wanted: [String]) {
            var common = 0
            while common < active.count && common < wanted.count && active[common] == wanted[common] { common += 1 }
            for token in active.dropFirst(common).reversed() { output += token == "<u>" ? "</u>" : token }
            output += whitespace; whitespace = ""
            for token in wanted.dropFirst(common) { output += token }
            active = wanted
        }
        while cursor < line.length {
            var range = NSRange()
            let attrs = line.attributes(at: cursor, effectiveRange: &range)
            range = NSRange(location: cursor, length: NSMaxRange(range) - cursor)
            let rawText = line.string as NSString
            if let value = attrs[.link] {
                // Treat the complete label as one link, independently of its
                // font runs. A partial bold/italic/code selection cannot change
                // the URL metadata or turn the remaining label into another link.
                var linkRange = NSRange()
                _ = line.attribute(.link, at: cursor, longestEffectiveRange: &linkRange, in: full)
                let label = NSMutableAttributedString(attributedString: line.attributedSubstring(from: linkRange))
                let labelRange = NSRange(location: 0, length: label.length)
                label.removeAttribute(.link, range: labelRange)
                label.removeAttribute(.macLinkTitle, range: labelRange)
                var styled = false
                label.enumerateAttributes(in: labelRange) { attrs, _, _ in
                    let font = attrs[.font] as? NSFont ?? self.font(block), traits = NSFontManager.shared.traits(of: font)
                    if inlineBold(attrs, block: block) || traits.contains(.italicFontMask) || traits.contains(.fixedPitchFontMask) || (attrs[.strikethroughStyle] as? Int ?? 0) != 0 || (attrs[.underlineStyle] as? Int ?? 0) != 0 || attrs[.macLiteral] != nil { styled = true }
                }
                transition([])
                let destination = String(describing: value)
                if let url = URL(string: destination), let reference = NoteReference(url: url) {
                    output += reference.markdown(label: label.string, formattedLabel: styled ? serializeInline(label, block: block) : nil)
                } else { output += "[" + serializeInline(label, block: block) + "](" + MacLinkEditRequest.webMarkdownDestination(destination) + MacLinkEditRequest.titleSuffix(attrs[.macLinkTitle] as? String) + ")" }
                cursor = NSMaxRange(linkRange); continue
            }
            if rawText.character(at: cursor) == 0x2028 {
                let kind = attrs[.macListBreak] as? Int ?? 1
                transition([])
                let prefix = MacBlockPrefix(block)
                if kind == 3 {
                    protectLogicalLine(); output += "<br>"; logicalStart = output.utf16.count
                    cursor += 1; continue
                }
                if prefix.map({ $0.list || $0.depth > 0 }) == true,
                   output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Emptying an item's first paragraph promotes the remaining
                    // paragraph; a marker-only line would detach that content.
                    output = ""; logicalStart = 0
                    repeat { cursor += 1 } while cursor < line.length && rawText.character(at: cursor) == 0x2028
                    continue
                }
                if prefix?.heading == true {
                    output += " "
                    repeat { cursor += 1 } while cursor < line.length && rawText.character(at: cursor) == 0x2028
                    continue
                }
                protectLogicalLine()
                let continuation = override ?? prefix.map { $0.list ? $0.listContinuation : $0.source } ?? ""
                let ending = attrs[.macLineEnding] as? String ?? line.attribute(.macLineEnding, at: 0, effectiveRange: nil) as? String ?? "\n"
                output += kind == 2 ? ending + (prefix?.quotes ?? "") + ending + continuation : "  " + ending + continuation
                logicalStart = output.utf16.count
                cursor += 1
                if kind == 2, cursor < line.length, rawText.character(at: cursor) == 0x2028,
                   line.attribute(.macListBreak, at: cursor, effectiveRange: nil) as? Int == 2 { cursor += 1 }
                continue
            }
            let separator = rawText.range(of: "\u{2028}", options: [], range: range)
            if separator.location != NSNotFound { range.length = separator.location - cursor }
            if let literal = attrs[.macLiteral] as? String { transition([]); output += literal; cursor = NSMaxRange(range); continue }
            let wanted = styles(attrs)
            let font = attrs[.font] as? NSFont ?? self.font(block), traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.fixedPitchFontMask) {
                // Attribute bookkeeping can split a single code span. Choose a
                // delimiter from its entire content, not one attributed run.
                var end = NSMaxRange(range)
                while end < line.length {
                    if rawText.character(at: end) == 0x2028 { break }
                    var nextRange = NSRange()
                    let next = line.attributes(at: end, effectiveRange: &nextRange)
                    let nextFont = next[.font] as? NSFont ?? self.font(block)
                    guard next[.link] == nil, next[.macLiteral] == nil, styles(next) == wanted,
                          NSFontManager.shared.traits(of: nextFont).contains(.fixedPitchFontMask) else { break }
                    let nextSeparator = rawText.range(of: "\u{2028}", options: [], range: NSRange(location: end, length: NSMaxRange(nextRange) - end))
                    end = nextSeparator.location == NSNotFound ? NSMaxRange(nextRange) : nextSeparator.location
                }
                transition(wanted)
                output += codeLiteral((line.string as NSString).substring(with: NSRange(location: cursor, length: end - cursor)))
                cursor = end; continue
            }
            else {
                // Display-only attribute splits must not let an entity form
                // across two otherwise identical plain-text runs.
                var end = NSMaxRange(range)
                while end < line.length {
                    if rawText.character(at: end) == 0x2028 { break }
                    var nextRange = NSRange()
                    let next = line.attributes(at: end, effectiveRange: &nextRange)
                    let nextFont = next[.font] as? NSFont ?? self.font(block)
                    guard next[.link] == nil, next[.macLiteral] == nil, styles(next) == wanted,
                          !NSFontManager.shared.traits(of: nextFont).contains(.fixedPitchFontMask) else { break }
                    let separator = rawText.range(of: "\u{2028}", options: [], range: NSRange(location: end, length: NSMaxRange(nextRange) - end))
                    end = separator.location == NSNotFound ? NSMaxRange(nextRange) : separator.location
                }
                range.length = end - range.location
                let raw = rawText.substring(with: range)
                let leading = String(raw.prefix(while: { $0.isWhitespace }))
                let rest = String(raw.dropFirst(leading.count)), trailing = String(rest.reversed().prefix(while: { $0.isWhitespace }).reversed())
                let core = String(rest.dropLast(trailing.count))
                // HTML underline can contain literal whitespace; Markdown
                // emphasis cannot. Preserve that distinction rather than moving
                // styled spaces outside the tag or bridging an unstyled gap.
                let underlined = wanted.contains("<u>")
                func literalWhitespace(_ text: String) -> String {
                    text.map { $0 == " " ? "&#32;" : $0 == "\t" ? "&#9;" : String($0) }.joined()
                }
                if underlined, !leading.isEmpty {
                    transition(["<u>"]); output += literalWhitespace(leading)
                } else {
                    if !leading.isEmpty, active.contains("<u>") { transition([]) }
                    whitespace += leading
                }
                if !core.isEmpty {
                    transition(wanted)
                    let literal = core.replacingOccurrences(of: #"&(?=(?:#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});)"#, with: "&amp;", options: .regularExpression)
                    output += literal.replacingOccurrences(of: #"([\\*_`~\[\]<>])"#, with: #"\\$1"#, options: .regularExpression)
                    if underlined, !trailing.isEmpty {
                        transition(["<u>"]); output += literalWhitespace(trailing)
                    } else { whitespace = trailing }
                }
            }
            cursor = NSMaxRange(range)
        }
        transition([]); protectLogicalLine(); return output
    }
    /// Insignificant syntax padding is separate from literal leading spaces,
    /// which the inline encoder writes as entities. Retain compact quote syntax.
    static func withoutStructuralIndentation(_ value: String) -> String {
        let raw = value as NSString
        var cursor = 0, quotes = ""
        while cursor < raw.length {
            while cursor < raw.length, raw.character(at: cursor) == 32 || raw.character(at: cursor) == 9 { cursor += 1 }
            guard cursor < raw.length, raw.character(at: cursor) == 62 else { break }
            quotes += ">"; cursor += 1
            if cursor < raw.length, raw.character(at: cursor) == 32 { quotes += " "; cursor += 1 }
        }
        return quotes + raw.substring(from: cursor)
    }
    private static func endsInBlankSourceLine(_ value: String) -> Bool {
        // Only the final source row matters. Bridging a growing Unicode export
        // to NSString here repeatedly prepares UTF-16 indices for its prefix.
        let bytes = value.utf8
        guard let last = bytes.last, last == 10 || last == 13 else { return false }
        var end = bytes.index(before: bytes.endIndex)
        if last == 10, end > bytes.startIndex, bytes[bytes.index(before: end)] == 13 { end = bytes.index(before: end) }
        var start = end
        while start > bytes.startIndex {
            let previous = bytes.index(before: start)
            if bytes[previous] == 10 || bytes[previous] == 13 { break }
            start = previous
        }
        var cursor = start
        while cursor < end, bytes[cursor] == 62 {
            cursor = bytes.index(after: cursor)
            if cursor < end, bytes[cursor] == 32 { cursor = bytes.index(after: cursor) }
        }
        return bytes[cursor..<end].allSatisfy { $0 == 32 || $0 == 9 }
    }
    /// Return the quote depth outside the owning list. A canonical root line
    /// may still be a lazy continuation when its native blank rows were deleted.
    private static func adoptingList(in prefix: String, value: String) -> Int? {
        var target = 1, previousCR = false
        for byte in prefix.utf8 {
            if byte == 13 { target += 1; previousCR = true }
            else { if byte == 10 && !previousCR { target += 1 }; previousCR = false }
        }
        var depth: Int?
        func inspect(_ node: any Markup) {
            if node is Paragraph || node is Heading || node is HTMLBlock, let range = node.range,
               range.lowerBound.line <= target, range.upperBound.line >= target {
                var ancestors: [any Markup] = [], parent = node.parent
                while let ancestor = parent { ancestors.append(ancestor); parent = ancestor.parent }
                if let owner = ancestors.lastIndex(where: { $0 is ListItem }) { depth = ancestors.suffix(from: owner + 1).filter { $0 is BlockQuote }.count }
            }
            for child in node.children { inspect(child) }
        }
        inspect(Document(parsing: prefix + value)); return depth
    }
    private static func quotePrefix(_ value: String, depth: Int) -> String {
        guard depth > 0 else { return "" }
        let quotes = MacBlockPrefix(value)?.quotes ?? ""
        var count = 0, end = quotes.startIndex
        while end < quotes.endIndex {
            let character = quotes[end]; end = quotes.index(after: end)
            if character == ">" { count += 1 }
            if count == depth {
                if end < quotes.endIndex, quotes[end] == " " { end = quotes.index(after: end) }
                return String(quotes[..<end])
            }
        }
        return String(repeating: "> ", count: depth)
    }
    private struct EmptyHeadBoundary {
        let sourceOffset: Int
        let prefixRange: NSRange
        let prefixLine: Int
        let text: String
    }
    /// Renumbering changes presentation only. Retain the original inline and
    /// paragraph provenance so restoring source prefixes can reuse soft wraps,
    /// emphasis spelling and deliberate whitespace exactly.
    private static func replacingOrderedPrefix(_ paragraph: NSAttributedString, to source: String) -> NSAttributedString {
        let output = NSMutableAttributedString(attributedString: paragraph)
        guard output.length > 0, let head = output.attribute(.macListContext, at: 0, effectiveRange: nil) as? MacListContext,
              !head.continuation else { return settingBlock(paragraph, to: source) }
        let prefix = displayPrefix(head.source), next = head.replacing(source: source)
        var attrs = output.attributes(at: 0, effectiveRange: nil)
        attrs[.macBlock] = next.block; attrs[.macListContext] = next; attrs[.paragraphStyle] = next.style
        if output.string.hasPrefix(prefix) { output.replaceCharacters(in: NSRange(location: 0, length: prefix.utf16.count), with: NSAttributedString(string: displayPrefix(source), attributes: attrs)) }
        output.addAttributes([.macBlock: next.block, .macListContext: next, .paragraphStyle: next.style], range: NSRange(location: 0, length: output.length))
        return output
    }
    fileprivate struct OrderedListEdit {
        let text: NSAttributedString
        let prefixes: [(NSRange, Int, Int)]
        func selection(_ range: NSRange) -> NSRange {
            func mapped(_ position: Int) -> Int {
                var result = position
                for (row, old, new) in prefixes {
                    if position >= row.location + old { result += new - old }
                    else if position > row.location { result += min(new, position - row.location) - (position - row.location) }
                }
                return result
            }
            let start = mapped(range.location), end = mapped(NSMaxRange(range))
            return NSRange(location: start, length: end - start)
        }
    }
    /// Presentation follows each parser-owned ordered container's start and
    /// item sequence. Descendant indentation follows the actual parent padding.
    /// This runs on load and explicit commands, never ordinary body typing.
    fileprivate static func normalizingOrderedLists(_ text: NSAttributedString) -> OrderedListEdit? {
        var numbered = false
        text.enumerateAttribute(.macBlock, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if let value = value as? String, MacBlockPrefix(value)?.marker.first?.isNumber == true { numbered = true; stop.pointee = true }
        }
        guard numbered, let items = nativeListItems(in: text) else { return nil }
        var ordinals: [Int: Int] = [:], planned: [MacBlockPrefix] = [], changes: [(NSRange, Int, Int)] = []
        let raw = text.string as NSString
        for item in items {
            var target = item.block
            if let parent = item.parent {
                let old = items[parent].block, next = planned[parent]
                let delta = next.indent + next.listPadding - old.indent - old.listPadding
                if delta != 0 { target = MacBlockPrefix(target.shiftingIndentation(by: delta, atQuoteDepth: old.depth))! }
            }
            let digits = target.marker.prefix(while: \.isNumber)
            if let original = Int(digits) {
                let ordinal = ordinals[item.container] ?? original
                target = MacBlockPrefix(target.replacingMarker(String(ordinal) + target.marker.dropFirst(digits.count)))!
                ordinals[item.container] = min(999_999_999, ordinal + 1)
            }
            planned.append(target)
            if target.source != item.block.source {
                guard raw.substring(with: item.range).hasPrefix(item.block.display) else { return nil }
                changes.append((item.range, item.block.display.utf16.count, target.display.utf16.count))
            }
        }
        guard !changes.isEmpty else { return nil }
        let output = NSMutableAttributedString(attributedString: text)
        for index in items.indices.reversed() where planned[index].source != items[index].block.source {
            let row = items[index].range
            let marker = text.attribute(.macOrderedMarker, at: row.location, effectiveRange: nil) as? String ?? items[index].block.marker
            let rewritten = NSMutableAttributedString(attributedString: replacingOrderedPrefix(output.attributedSubstring(from: row), to: planned[index].source))
            if items[index].block.marker.first?.isNumber == true { rewritten.addAttribute(.macOrderedMarker, value: marker, range: NSRange(location: 0, length: rewritten.length)) }
            output.replaceCharacters(in: row, with: rewritten)
        }
        let prepared = refreshingListContexts(output)
        guard nativeListItems(in: prepared)?.map(\.parent) == items.map(\.parent) else { return nil }
        return OrderedListEdit(text: prepared, prefixes: changes)
    }

    /// Materialize source prefixes in a private copy. A child's indentation is
    /// relative to the current parent's source content column, not its visual
    /// ordinal width. Existing markers survive body edits and sibling changes.
    private static func sourceOrderedLists(_ text: NSAttributedString) -> OrderedListEdit? {
        var hasSource = false
        text.enumerateAttribute(.macOrderedMarker, in: NSRange(location: 0, length: text.length)) { value, _, stop in if value != nil { hasSource = true; stop.pointee = true } }
        guard hasSource else { return nil }
        let canonical = serializedMarkdown(text, protectEmptyHeads: false, restoreOrdered: false)
        guard let items = nativeListItems(in: text, using: canonical) else { return nil }
        var planned: [MacBlockPrefix] = [], changes: [(NSRange, Int, Int)] = []
        for item in items {
            var target = item.block
            if let parent = item.parent {
                let old = items[parent].block, next = planned[parent]
                let delta = next.indent + next.listPadding - old.indent - old.listPadding
                if delta != 0 { target = MacBlockPrefix(target.shiftingIndentation(by: delta, atQuoteDepth: old.depth))! }
            }
            if let marker = text.attribute(.macOrderedMarker, at: item.range.location, effectiveRange: nil) as? String, target.marker.first?.isNumber == true {
                target = MacBlockPrefix(target.replacingMarker(marker))!
            }
            planned.append(target)
            if target.source != item.block.source { changes.append((item.range, item.block.display.utf16.count, target.display.utf16.count)) }
        }
        guard !changes.isEmpty else { return nil }
        let output = NSMutableAttributedString(attributedString: text)
        output.removeAttribute(.macOrderedMarker, range: NSRange(location: 0, length: output.length))
        for index in items.indices.reversed() where planned[index].source != items[index].block.source {
            let row = items[index].range
            output.replaceCharacters(in: row, with: replacingOrderedPrefix(output.attributedSubstring(from: row), to: planned[index].source))
        }
        return OrderedListEdit(text: refreshingListContexts(output), prefixes: changes)
    }

    private struct SerializedMarkdown {
        let text: String
        let headLines: [Int: Int]
        let emptyHeadBoundaries: [Int: EmptyHeadBoundary]
        let insertedEmptyBoundaries: [Int]
        var rootRows: [ExportRow] = []
    }
    /// An edited empty native head must remain a list item in the autosave.
    /// Parse its containing list plus preceding independent paragraph, not every
    /// earlier note paragraph. Native owned continuations never cut this scope.
    private static func protectingEmptyHeads(_ source: SerializedMarkdown) -> SerializedMarkdown {
        guard !source.emptyHeadBoundaries.isEmpty else { return source }
        let raw = source.text as NSString
        let scopes = Dictionary(grouping: source.emptyHeadBoundaries.map { (offset: $0.key, boundary: $0.value) }, by: { $0.boundary.prefixRange.location })
        var chosen: [(offset: Int, line: Int, boundary: EmptyHeadBoundary)] = []
        for (start, entries) in scopes.sorted(by: { $0.key < $1.key }) {
            let entries = entries.sorted { source.headLines[$0.offset]! < source.headLines[$1.offset]! }
            let end = entries.map { NSMaxRange($0.boundary.prefixRange) }.max()!
            let prefixLine = entries[0].boundary.prefixLine
            let context = NSMutableString(string: raw.substring(with: NSRange(location: start, length: end - start)))
            var inserted: [(offset: Int, line: Int, boundary: EmptyHeadBoundary)] = []
            while true {
                var parsed = Set<Int>()
                func collect(_ node: any Markup) {
                    if node is ListItem, let line = node.range?.lowerBound.line { parsed.insert(line + prefixLine - 1) }
                    for child in node.children { collect(child) }
                }
                collect(Document(parsing: context as String))
                guard let missing = entries.first(where: { entry in
                    let line = source.headLines[entry.offset]!
                    return !parsed.contains(line + inserted.filter { $0.line <= line }.count)
                }), !inserted.contains(where: { $0.offset == missing.offset }) else { break }
                // An earlier separator may already repair a whole empty chain.
                // Re-parse before considering the next head, so an unnecessary
                // blank cannot close its empty parent and promote the child.
                let shift = inserted.filter { $0.boundary.sourceOffset <= missing.boundary.sourceOffset }.reduce(0) { $0 + $1.boundary.text.utf16.count }
                context.insert(missing.boundary.text, at: missing.boundary.sourceOffset - start + shift)
                inserted.append((missing.offset, source.headLines[missing.offset]!, missing.boundary))
            }
            chosen += inserted
        }
        guard !chosen.isEmpty else { return source }
        let lines = chosen.map(\.line).sorted(), output = NSMutableString(string: source.text)
        for entry in chosen.sorted(by: { $0.boundary.sourceOffset > $1.boundary.sourceOffset }) { output.insert(entry.boundary.text, at: entry.boundary.sourceOffset) }
        var heads: [Int: Int] = [:], shift = 0
        for (offset, line) in source.headLines.sorted(by: { $0.value < $1.value }) {
            while shift < lines.count, lines[shift] <= line { shift += 1 }
            heads[offset] = line + shift
        }
        return SerializedMarkdown(text: output as String, headLines: heads, emptyHeadBoundaries: source.emptyHeadBoundaries, insertedEmptyBoundaries: chosen.map(\.offset).sorted())
    }
    static func isEmptyParagraphMarker(_ node: any Markup) -> Bool {
        let paragraph: Paragraph?
        if let value = node as? Paragraph { paragraph = value }
        else if node is Markdown.Document, node.childCount == 1 { paragraph = node.child(at: 0) as? Paragraph }
        else { return false }
        guard let paragraph, let first = paragraph.child(at: 0) as? Markdown.Text, first.string == emptyParagraphMarker else { return false }
        return paragraph.children.dropFirst().allSatisfy { child in
            (child as? InlineHTML)?.rawHTML.range(of: #"(?i)^<br\s*/?>$"#, options: .regularExpression) != nil
        }
    }
    static let emptyParagraphMarker = "\u{200B}"
    static func markdown(_ rich: NSAttributedString) -> String { serializedMarkdown(rich).text }
    fileprivate struct ExportRow {
        var native: NSRange
        var source: NSRange
        var listContext: MacListContext? = nil
        var sourceContext: MacListContext? = nil
        var rootBlock: String? = nil
    }
    /// Reuse a completed export or fresh source with a sparse rendered-row map.
    /// Every later storage edit must fit a mapped row and pass eligibility checks;
    /// otherwise the caller rebuilds from the complete serializer.
    struct Export {
        private var text: String
        private var rows: [ExportRow]
        private var dirty: Int?
        private var valid = true
        fileprivate init(renderedSource: String, rows: [ExportRow]) {
            text = renderedSource; self.rows = rows
        }
        init(_ rich: NSAttributedString) {
            let result = serializedMarkdown(rich, recordExportRows: true)
            text = result.text; rows = result.rootRows
        }
        mutating func edited(_ range: NSRange, delta: Int) {
            guard valid else { return }
            let oldLength = range.length - delta
            guard oldLength >= 0 else { valid = false; return }
            // Ranges reported by NSTextStorage use the edited coordinates.
            // Locate the containing row in the previous coordinates first.
            var low = 0, high = rows.count
            while low < high {
                let middle = (low + high) / 2
                if rows[middle].native.location <= range.location { low = middle + 1 } else { high = middle }
            }
            let index = low - 1
            guard index >= 0, range.location >= rows[index].native.location,
                  range.location + oldLength <= NSMaxRange(rows[index].native),
                  dirty == nil || dirty == index else { valid = false; return }
            dirty = index; rows[index].native.length += delta
            if delta != 0 { for later in (index + 1)..<rows.count { rows[later].native.location += delta } }
        }
        mutating func value(_ rich: NSAttributedString) -> String? {
            guard valid else { return nil }
            guard let dirty else { return text }
            let row = rows[dirty]
            if let context = row.listContext {
                guard reusableListRow(rich, range: row.native, context: context) else { return nil }
            } else {
                guard reusableRootRow(rich, range: row.native),
                      rich.attribute(.macBlock, at: row.native.location, effectiveRange: nil) as? String == row.rootBlock else { return nil }
            }
            var fragment = rich.attributedSubstring(from: row.native)
            if let live = row.listContext, let actual = row.sourceContext, let prefix = exportListPrefix(live) {
                let copy = NSMutableAttributedString(attributedString: fragment)
                copy.replaceCharacters(in: NSRange(location: 0, length: prefix.display.utf16.count), with: NSAttributedString(string: displayPrefix(actual.source), attributes: copy.attributes(at: 0, effectiveRange: nil)))
                copy.addAttributes([.macListContext: actual, .macBlock: actual.block], range: NSRange(location: 0, length: copy.length))
                copy.removeAttribute(.macOrderedMarker, range: NSRange(location: 0, length: copy.length)); fragment = copy
            }
            let replacement = markdown(fragment)
            // This path cannot create a source block or paragraph boundary.
            guard singleSourceRow(replacement) else { return nil }
            let result = NSMutableString(string: text)
            result.replaceCharacters(in: row.source, with: replacement)
            let delta = replacement.utf16.count - row.source.length
            text = result as String; rows[dirty].source.length = replacement.utf16.count
            if delta != 0 { for later in (dirty + 1)..<rows.count { rows[later].source.location += delta } }
            self.dirty = nil
            return text
        }
    }
    private static func singleSourceRow(_ value: String) -> Bool {
        var body = value
        if body.hasSuffix("\r\n") { body.removeLast() }
        else if body.hasSuffix("\n") || body.hasSuffix("\r") { body.removeLast() }
        return !body.isEmpty && !body.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
    }
    private static func standaloneExportBlock(_ source: String) -> Bool {
        if source.isEmpty { return true }
        guard let prefix = MacBlockPrefix(source) else { return false }
        return prefix.heading && !prefix.list && prefix.depth == 0 && prefix.indent == 0
    }
    /// A root quote's fixed prefix can be emitted locally too. Keep this
    /// separate from the whole-document standalone optimization: a mixed
    /// document still needs all of its list/card boundary bookkeeping.
    private static func exportRootBlock(_ source: String) -> Bool {
        if standaloneExportBlock(source) { return true }
        guard source.first == ">", source.utf8.allSatisfy({ $0 == 32 || $0 == 62 }),
              let prefix = MacBlockPrefix(source), prefix.depth > 0,
              prefix.marker.isEmpty, prefix.indent == 0 else { return false }
        return true
    }
    private static func reusableRootRow(_ rich: NSAttributedString, range: NSRange, text: NSString? = nil) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= rich.length else { return false }
        let raw = text ?? rich.string as NSString
        guard raw.paragraphRange(for: NSRange(location: range.location, length: 0)) == range else { return false }
        let value = raw.substring(with: range)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.contains("\u{2028}"), !value.contains("\u{2029}"), !value.contains(emptyParagraphMarker) else { return false }
        let first = rich.attributes(at: range.location, effectiveRange: nil)
        guard let block = first[.macBlock] as? String, exportRootBlock(block) else { return false }
        // Imported indentation can have been normalized by the preceding list
        // boundary. A standalone export must not resurrect that old spelling.
        for key in [NSAttributedString.Key.macOriginal, .macParagraphSource] {
            if let original = first[key] as? String {
                if let start = original.unicodeScalars.first, CharacterSet.whitespacesAndNewlines.contains(start) { return false }
                if block.first == ">", withoutStructuralIndentation(original) != original { return false }
            }
        }
        var eligible = true
        rich.enumerateAttributes(in: range) { attrs, _, stop in
            if attrs[.macBlock] as? String != block || attrs[.macIndependentParagraph] as? Bool != true ||
                [.macListContext, .macListGap, .macCode, .macTable, .macRule, .macRuleGap, .macLiteral, .attachment, .macHardBreak, .macListBreak].contains(where: { attrs[$0] != nil }) {
                eligible = false; stop.pointee = true
            }
        }
        guard eligible else { return false }
        // A changed preceding block must not alter the next paragraph's lazy
        // continuation boundary. Structural neighbors use the full serializer.
        if NSMaxRange(range) < rich.length {
            let next = raw.paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))
            let attrs = rich.attributes(at: next.location, effectiveRange: nil)
            let nextBlock = attrs[.macBlock] as? String ?? ""
            let quotedBlank = block.first == ">" && nextBlock.first == ">" && exportRootBlock(nextBlock) &&
                MacBlockPrefix(nextBlock)?.depth == MacBlockPrefix(block)?.depth
            guard raw.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  [.macListContext, .macListGap, .macCode, .macTable, .macRule, .macListCard].allSatisfy({ attrs[$0] == nil }),
                  nextBlock.isEmpty || quotedBlank else { return false }
        }
        return true
    }
    private static let exportExcludedCharacters = CharacterSet(charactersIn: "\u{2028}\u{2029}\u{200B}")
    private static func exportListPrefix(_ context: MacListContext) -> MacBlockPrefix? {
        guard !context.continuation, context.gap.isEmpty, context.suffix.isEmpty,
              !context.blockParagraph, !context.quoteLeaf, context.quoteParents.isEmpty,
              let prefix = MacBlockPrefix(context.source), prefix.list,
              prefix.quotes.utf8.allSatisfy({ $0 == 32 || $0 == 62 }),
              prefix.indentation.utf8.allSatisfy({ $0 == 32 }) else { return nil }
        let symbol = String(prefix.marker.prefix { !$0.isWhitespace })
        let task = prefix.checklist ? (prefix.marker.contains("[ ]") ? "[ ] " : prefix.marker.contains("[x]") ? "[x] " : "[X] ") : ""
        guard symbol.utf8.allSatisfy({ $0 < 128 }), prefix.marker == symbol + " " + task else { return nil }
        return prefix
    }
    /// A stable, nonempty item head can replace its own source line without
    /// changing its fixed quote/space prefix, marker padding or ownership.
    private static func reusableListRow(_ rich: NSAttributedString, range: NSRange, context: MacListContext, text: NSString? = nil) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= rich.length,
              let prefix = exportListPrefix(context) else { return false }
        let raw = text ?? rich.string as NSString
        guard raw.paragraphRange(for: NSRange(location: range.location, length: 0)) == range else { return false }
        let value = raw.substring(with: range)
        guard value.hasPrefix(prefix.display),
              !value.dropFirst(prefix.display.count).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (value as NSString).rangeOfCharacter(from: exportExcludedCharacters).location == NSNotFound else { return false }
        var eligible = true
        rich.enumerateAttributes(in: range) { attrs, _, stop in
            if attrs[.macBlock] as? String != context.source ||
                (attrs[.macListContext] as? MacListContext) !== context ||
                attrs[.macIndependentParagraph] as? Bool != false ||
                [.macListGap, .macCompactList, .macListCard, .macCode, .macTable, .macRule, .macRuleGap, .macLiteral, .attachment, .macHardBreak, .macListBreak, .macEmptyParagraph].contains(where: { attrs[$0] != nil }) ||
                (NSMaxRange(range) < rich.length && attrs[.macUnterminated] as? Bool == true) {
                eligible = false; stop.pointee = true
            }
        }
        guard eligible else { return false }
        if NSMaxRange(range) < rich.length {
            let next = raw.paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))
            let attrs = rich.attributes(at: next.location, effectiveRange: nil)
            if let head = attrs[.macListContext] as? MacListContext,
               !head.continuation, MacBlockPrefix(attrs[.macBlock] as? String ?? "")?.list == true {
                return attrs[.macCode] == nil && attrs[.macTable] == nil
            }
            // Leave the blank row's source untouched. Only an unowned blank
            // at the same quote depth is safe; contextual gaps still use export.
            let nextBlock = attrs[.macBlock] as? String ?? ""
            let quotedBlank = prefix.depth > 0 && nextBlock.utf8.allSatisfy({ $0 == 32 || $0 == 62 }) &&
                MacBlockPrefix(nextBlock).map { $0.marker.isEmpty && $0.depth == prefix.depth } == true
            guard raw.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  nextBlock.isEmpty || quotedBlank,
                  [.macListContext, .macListGap, .macCode, .macTable, .macRule].allSatisfy({ attrs[$0] == nil }) else { return false }
        }
        return true
    }
    /// Inspect the body that will actually be emitted: an emptied first logical
    /// paragraph can promote a later paragraph into the item's first line.
    static func listBodyState(_ paragraph: NSAttributedString, block: MacBlockPrefix, continuation: Bool = false) -> (emptyFirstLine: Bool, hasContent: Bool) {
        if block.checklist { return (false, true) }
        let raw = paragraph.string as NSString
        let marker = !continuation && paragraph.string.hasPrefix(block.display) ? block.display.utf16.count : 0
        let end = raw.length - (paragraph.string.hasSuffix("\n") ? 1 : 0)
        guard end >= marker else { return (true, false) }
        let body = serializeInline(paragraph.attributedSubstring(from: NSRange(location: marker, length: end - marker)), block: block.marker)
        let first = body.unicodeScalars.prefix { $0.value != 10 && $0.value != 13 }
        return (first.allSatisfy { $0.value == 32 || $0.value == 9 }, body.unicodeScalars.contains { ![9, 10, 13, 32].contains($0.value) })
    }
    /// Record native head positions against the source actually emitted, including
    /// reused tokens, logical breaks, quote gaps, code cards and CRLF endings.
    private static func serializedMarkdown(_ rich: NSAttributedString, protectEmptyHeads: Bool = true, recordExportRows: Bool = false, restoreOrdered: Bool = true) -> SerializedMarkdown {
        let text = rich.string as NSString, signatureKeys = SignatureKeys()
        if restoreOrdered, let restored = sourceOrderedLists(rich) {
            let actual = serializedMarkdown(restored.text, protectEmptyHeads: protectEmptyHeads, recordExportRows: recordExportRows, restoreOrdered: false)
            let canonical = serializedMarkdown(rich, protectEmptyHeads: false, restoreOrdered: false)
            if let before = nativeListItems(in: rich, using: canonical), let after = nativeListItems(in: restored.text, using: actual), before.map(\.parent) == after.map(\.parent) {
                var lines: [Int: Int] = [:]
                for (old, new) in zip(before, after) { lines[old.range.location] = actual.headLines[new.range.location] }
                var result = SerializedMarkdown(text: actual.text, headLines: lines, emptyHeadBoundaries: [:], insertedEmptyBoundaries: [])
                if recordExportRows {
                    var locations: [Int: NSRange] = [:], offset = 0
                    while offset < text.length {
                        let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
                        locations[restored.selection(range).location] = range; offset = NSMaxRange(range)
                    }
                    result.rootRows = actual.rootRows.compactMap { row in
                        guard let native = locations[row.native.location] else { return nil }
                        let context = rich.attribute(.macListContext, at: native.location, effectiveRange: nil) as? MacListContext
                        return ExportRow(native: native, source: row.source, listContext: context, sourceContext: row.listContext, rootBlock: row.rootBlock)
                    }
                }
                return result
            }
        }
        // Root prose/heading exports cannot encounter list or card boundaries.
        // Prove absence once, rather than repeating those attribute lookups and
        // ownership bookkeeping for every paragraph in a long ordinary note.
        var standalone = true
        let containers: [NSAttributedString.Key] = [.macListContext, .macListGap, .macCompactList, .macCode, .macTable, .macRule, .macRuleGap, .macListCard, .attachment]
        rich.enumerateAttributes(in: NSRange(location: 0, length: rich.length)) { attrs, _, stop in
            if !standaloneExportBlock(attrs[.macBlock] as? String ?? "") || containers.contains(where: { attrs[$0] != nil }) {
                standalone = false; stop.pointee = true
            }
        }
        let heads = standalone ? [:] : listHeads(rich)
        let joinedCards = standalone ? (offsets: Set<Int>(), cards: [Int: [MacListContext]]()) : MacListCardPlacement.joinedHeads(in: rich)
        var hasRules = false, ruleWindow = ""
        var gapParents: Set<UUID> = [], emptyParents: Set<UUID> = []
        if !standalone {
            rich.enumerateAttribute(.macRule, in: NSRange(location: 0, length: rich.length)) { value, _, stop in
                if value != nil { hasRules = true; stop.pointee = true }
            }
            rich.enumerateAttribute(.macListGap, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
                if let gap = value as? MacListGap { gapParents.insert(gap.parent) }
            }
        }
        var joiningContinuation: (id: UUID, target: Int)?
        func promotionTarget(at index: Int) -> Int? {
            guard let context = rich.attribute(.macListContext, at: index, effectiveRange: nil) as? MacListContext, !context.continuation, context.suffix.isEmpty,
                  let prefix = MacBlockPrefix(rich.attribute(.macBlock, at: index, effectiveRange: nil) as? String ?? ""), prefix.list, !prefix.checklist else { return nil }
            let paragraph = text.paragraphRange(for: NSRange(location: index, length: 0))
            guard text.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines) == prefix.display.trimmingCharacters(in: .whitespaces) else { return nil }
            var next = NSMaxRange(paragraph)
            while next < rich.length {
                let attrs = rich.attributes(at: next, effectiveRange: nil)
                if let tail = attrs[.macListContext] as? MacListContext {
                    return tail.continuation && tail.id == context.id && tail.originatedAfterChildren ? next : nil
                }
                let row = text.paragraphRange(for: NSRange(location: next, length: 0))
                guard attrs[.macCode] == nil, attrs[.macTable] == nil,
                      text.substring(with: row).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                next = NSMaxRange(row)
            }
            return nil
        }
        func reusableContext(at index: Int) -> Bool {
            let row = text.paragraphRange(for: NSRange(location: index, length: 0))
            if NSMaxRange(row) < rich.length, rich.attribute(.macUnterminated, at: NSMaxRange(row) - 1, effectiveRange: nil) as? Bool == true { return false }
            if standalone { return true }
            guard let context = rich.attribute(.macListContext, at: index, effectiveRange: nil) as? MacListContext,
                  context.continuation else { return true }
            return joiningContinuation?.target != index && heads[context.id]?.source == context.source
        }
        var rootRows: [ExportRow] = []
        func recordRootRow(_ range: NSRange, start: Int, emitted: String) {
            guard recordExportRows, range.length > 0,
                  text.paragraphRange(for: NSRange(location: range.location, length: 0)) == range else { return }
            let attrs = rich.attributes(at: range.location, effectiveRange: nil)
            let context = attrs[.macListContext] as? MacListContext
            let plain = (attrs[.macBlock] as? String).map(exportRootBlock) == true && context == nil &&
                attrs[.macIndependentParagraph] as? Bool == true && attrs[.macEmptyParagraph] as? Bool != true
            guard plain || context.map({ reusableListRow(rich, range: range, context: $0, text: text) }) == true else { return }
            // Full eligibility is checked only when this candidate is edited.
            // Contextual blank/quote separators belong to the boundary, not
            // the local paragraph replacement. Keep them in the cached prefix.
            let padded = emitted.utf8.first.map { [9, 10, 13, 32, 62].contains($0) } ?? false
            let prefix = padded ? (emitted as NSString).range(of: #"^(?:[ \t>]*(?:\r\n|\r|\n))*"#, options: .regularExpression).length : 0
            let content = (emitted as NSString).substring(from: prefix)
            guard singleSourceRow(content), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            rootRows.append(ExportRow(native: range, source: NSRange(location: start + prefix, length: content.utf16.count), listContext: context, rootBlock: context == nil ? attrs[.macBlock] as? String : nil))
        }
        var result = "", sourceLine = 1, sourceOffset = 0, headLines: [Int: Int] = [:], previousCR = false
        var independentStart = 0, independentLine = 1, mayFollowList = false
        var contextualEmptyHeads: [Int: EmptyHeadBoundary] = [:]
        let independentWhitespace = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ">"))
        // The context starts at the previous independent block. Each block is
        // parsed at most with its successor list, rather than with the whole note.
        func independentSpelling(_ value: String, range: NSRange) -> String {
            if standalone { return value }
            let attrs = rich.attributes(at: range.location, effectiveRange: nil)
            let block = attrs[.macBlock] as? String ?? "", context = attrs[.macListContext] as? MacListContext
            if MacBlockPrefix(block)?.list == true || context.map({ heads[$0.id] != nil }) == true { mayFollowList = true; return value }
            guard attrs[.macIndependentParagraph] as? Bool == true, context == nil,
                  !value.trimmingCharacters(in: independentWhitespace).isEmpty else { return value }
            var output = value
            if mayFollowList {
                let normalized = withoutStructuralIndentation(value), blank = endsInBlankSourceLine(result)
                if normalized != value || !blank {
                    var prefix = (result as NSString).substring(from: independentStart)
                    if !contextualEmptyHeads.isEmpty {
                        var boundaries: [Int: EmptyHeadBoundary] = [:], lines: [Int: Int] = [:]
                        for (index, boundary) in contextualEmptyHeads {
                            let start = max(independentStart, boundary.prefixRange.location)
                            boundaries[index] = EmptyHeadBoundary(sourceOffset: boundary.sourceOffset - independentStart,
                                prefixRange: NSRange(location: start - independentStart, length: NSMaxRange(boundary.prefixRange) - start),
                                prefixLine: boundary.prefixRange.location < independentStart ? 1 : boundary.prefixLine - independentLine + 1, text: boundary.text)
                            lines[index] = headLines[index]! - independentLine + 1
                        }
                        // Establish the same empty heads the final export will
                        // recover before deciding whether they adopt root prose.
                        prefix = protectingEmptyHeads(SerializedMarkdown(text: prefix, headLines: lines, emptyHeadBoundaries: boundaries, insertedEmptyBoundaries: [])).text
                    }
                    if let depth = adoptingList(in: prefix, value: value) {
                        let ending = attrs[.macLineEnding] as? String ?? (result.hasSuffix("\r\n") ? "\r\n" : "\n")
                        let terminate = result.utf8.last.map { $0 == 10 || $0 == 13 } ?? true
                        output = (blank ? "" : (terminate ? "" : ending) + quotePrefix(normalized, depth: depth) + ending) + normalized
                    }
                }
            }
            independentStart = sourceOffset; independentLine = sourceLine; mayFollowList = false
            contextualEmptyHeads.removeAll(keepingCapacity: true)
            return output
        }
        var scopeStart = (line: 1, offset: 0), scopeHasRoot = false, emptyHeadBoundaries: [Int: EmptyHeadBoundary] = [:]
        func append(_ value: String) {
            result += value; if hasRules { ruleWindow += value }; sourceOffset += value.utf16.count
            // Root-only exports have no head/card/rule line bookkeeping.
            // Source offsets still serve the incremental paragraph cache.
            if !standalone {
                for byte in value.utf8 {
                    if byte == 13 { sourceLine += 1; previousCR = true }
                    else { if byte == 10 && !previousCR { sourceLine += 1 }; previousCR = false }
                }
            }
        }
        func separateTableFromQuote(at index: Int, placement: MacListCardPlacement?, head: MacListContext?, quote: String, ending: String) {
            guard index > 0, !result.isEmpty else { return }
            let previous = rich.attributes(at: index - 1, effectiveRange: nil)
            let context = previous[.macListContext] as? MacListContext
            let previousDepth = MacBlockPrefix(context?.textBlock ?? previous[.macBlock] as? String ?? "")?.depth ?? 0
            let owner = MacBlockPrefix(head?.source ?? rich.attribute(.macBlock, at: index, effectiveRange: nil) as? String ?? "")
            let suffix = placement?.ownerSuffix ?? ""
            let separator = placement == nil ? quote : suffix.isEmpty ? owner?.quotes ?? "" : (owner?.list == true ? owner!.listContinuation : owner?.quotes ?? "") + suffix
            let depth = separator.filter { $0 == ">" }.count
            guard previousDepth > depth else { return }
            if endsInBlankSourceLine(result) {
                let raw = result as NSString
                let last = raw.substring(with: raw.paragraphRange(for: NSRange(location: raw.length - 1, length: 0)))
                if last.filter({ $0 == ">" }).count <= depth { return }
            }
            // A table following quote text can be a lazy quote paragraph.
            // End only the deeper quote, preserving the card's own container.
            append(separator + ending)
        }
        func recordParagraph(_ index: Int, emitted: String, changed: Bool, emptyHead: Bool = true) {
            if standalone { return }
            let attrs = rich.attributes(at: index, effectiveRange: nil)
            let block = MacBlockPrefix(attrs[.macBlock] as? String ?? "")
            let paragraph = text.paragraphRange(for: NSRange(location: index, length: 0))
            guard let block, block.list else {
                let context = attrs[.macListContext] as? MacListContext
                let owned = context.map { $0.continuation && heads[$0.id] != nil } ?? false
                if !owned, !text.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { scopeStart = (sourceLine, sourceOffset); scopeHasRoot = false }
                return
            }
            if block.indent == 0 {
                if scopeHasRoot { scopeStart = (sourceLine, sourceOffset) }
                scopeHasRoot = true
            }
            headLines[index] = sourceLine
            let context = attrs[.macListContext] as? MacListContext
            if let context, !context.continuation, gapParents.contains(context.id),
               !listBodyState(rich.attributedSubstring(from: paragraph), block: block).hasContent { emptyParents.insert(context.id) }
            guard emptyHead, changed || !protectEmptyHeads || context?.continuation == false else { return }
            if text.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines) == block.display.trimmingCharacters(in: .whitespaces) {
                let newline = text.substring(with: paragraph).hasSuffix("\n") ? NSMaxRange(paragraph) - 1 : max(0, index - 1)
                let ending = rich.attribute(.macLineEnding, at: newline, effectiveRange: nil) as? String ?? "\n"
                emptyHeadBoundaries[index] = EmptyHeadBoundary(sourceOffset: sourceOffset, prefixRange: NSRange(location: scopeStart.offset, length: sourceOffset + emitted.utf16.count - scopeStart.offset), prefixLine: scopeStart.line, text: block.quotes + ending)
                contextualEmptyHeads[index] = emptyHeadBoundaries[index]
            }
        }
        var offset = 0, previousBlock = "", previousChanged = false, previousContinuation = false
        while offset < text.length {
            if joinedCards.offsets.contains(offset) {
                recordParagraph(offset, emitted: "", changed: false, emptyHead: false)
                offset = NSMaxRange(text.paragraphRange(for: NSRange(location: offset, length: 0))); continue
            }
            if !standalone, rich.attribute(.macRuleGap, at: offset, effectiveRange: nil) != nil {
                let inputRow = text.paragraphRange(for: NSRange(location: offset, length: 0))
                if text.substring(with: inputRow).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    offset = NSMaxRange(inputRow); continue
                }
            }
            if let joiningContinuation, offset < joiningContinuation.target {
                // The prepared target owns these blank native rows. Only their
                // source spelling is omitted; Undo and refill retain the rows.
                offset = NSMaxRange(text.paragraphRange(for: NSRange(location: offset, length: 0))); continue
            }
            let promotion = standalone ? nil : promotionTarget(at: offset)
            if !standalone, let gap = rich.attribute(.macListGap, at: offset, effectiveRange: nil) as? MacListGap,
               emptyParents.contains(gap.parent) {
                let blank = text.paragraphRange(for: NSRange(location: offset, length: 0))
                if text.substring(with: blank).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var next = NSMaxRange(blank), childMatches = false
                    while next < text.length {
                        let row = text.paragraphRange(for: NSRange(location: next, length: 0))
                        if let context = rich.attribute(.macListContext, at: next, effectiveRange: nil) as? MacListContext,
                           !context.continuation || rich.attribute(.macListCard, at: next, effectiveRange: nil) != nil {
                            childMatches = context.id == gap.child; break
                        }
                        if !text.substring(with: row).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
                        next = NSMaxRange(row)
                    }
                    if childMatches { offset = NSMaxRange(blank); continue }
                }
            }
            if !standalone, rich.attribute(.attachment, at: offset, effectiveRange: nil) is MacRuleAttachment {
                let row = text.paragraphRange(for: NSRange(location: offset, length: 0))
                let attrs = rich.attributes(at: offset, effectiveRange: nil)
                let quotes = attrs[.macBlock] as? String ?? ""
                var ending = text.substring(with: row).hasSuffix("\n") ? attrs[.macLineEnding] as? String ?? "\n" : ""
                if !ending.isEmpty, let original = attrs[.macParagraphSource] as? String,
                   !original.hasSuffix("\n"), !original.hasSuffix("\r"),
                   rich.attribute(.macRuleGap, at: NSMaxRange(row) - 1, effectiveRange: nil) != nil, NSMaxRange(row) < rich.length {
                    let next = text.paragraphRange(for: NSRange(location: NSMaxRange(row), length: 0))
                    if rich.attribute(.macRuleGap, at: next.location, effectiveRange: nil) != nil, text.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { ending = "" }
                }
                let placement = attrs[.macListCard] as? MacListCardPlacement
                let context = attrs[.macListContext] as? MacListContext
                let literal = attrs[.macLiteral] as? String ?? "***"
                let value = (placement?.markdown(literal, attributes: attrs, head: context.flatMap { heads[$0.id] }, joined: joinedCards.cards[offset] ?? []) ?? (quotes + literal)) + ending
                func endsWithRule(_ node: any Markup) -> Bool {
                    if node is ThematicBreak { return true }
                    return Array(node.children).last.map(endsWithRule) ?? false
                }
                // A heading changed into prose must not turn the following
                // dash rule into a setext heading on its next save.
                if !endsWithRule(Document(parsing: ruleWindow + value)) {
                    let line = ending.isEmpty ? "\n" : ending
                    if let last = result.utf8.last, last != 10, last != 13 { append(line) }
                    append(quotes + line)
                }
                recordParagraph(offset, emitted: value, changed: false); append(value)
                ruleWindow = ""
                offset = NSMaxRange(row); previousBlock = quotes; previousChanged = false; previousContinuation = false
                continue
            }
            var tableRange = NSRange()
            if !standalone, rich.attribute(.macTable, at: offset, effectiveRange: nil) is MacRichTable,
               let table = rich.attribute(.macTable, at: offset, longestEffectiveRange: &tableRange, in: NSRange(location: 0, length: rich.length)) as? MacRichTable {
                if !result.isEmpty && ![10, 13].contains(result.utf8.last ?? 0) { append(table.original.newline + table.original.newline) }
                let tableText = rich.attributedSubstring(from: tableRange), attrs = rich.attributes(at: offset, effectiveRange: nil)
                let placement = attrs[.macListCard] as? MacListCardPlacement
                let context = attrs[.macListContext] as? MacListContext
                let head = context.flatMap { heads[$0.id] }
                let inner = table.markdown(tableText)
                separateTableFromQuote(at: offset, placement: placement, head: head, quote: table.quote?.prefix ?? "", ending: table.original.newline)
                append(placement?.markdown(inner, attributes: attrs, head: head, joined: joinedCards.cards[offset] ?? []) ?? inner)
                var ending = table.ending
                if NSMaxRange(tableRange) < rich.length {
                    let suffix = (rich.string as NSString).substring(from: NSMaxRange(tableRange))
                    if ending.isEmpty { ending = table.original.newline }
                    let count = suffix.prefix { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }.count + 1
                    let next = rich.attributes(at: NSMaxRange(tableRange), effectiveRange: nil)
                    let prefix = MacBlockPrefix(next[.macBlock] as? String ?? "")
                    let isBlock = prefix?.heading == true || prefix?.list == true || next[.macCode] != nil || next[.macRule] != nil
                    let fencedCode = (next[.macCode] as? MacRichCode).map { $0.indented == nil } ?? false
                    let needsGap = table.quote == nil ? !fencedCode : !isBlock
                    if placement == nil, count < 2, needsGap { for _ in 0..<(2 - count) { ending += (table.quote?.prefix ?? "") + table.original.newline } }
                }
                append(ending); scopeStart = (sourceLine, sourceOffset); scopeHasRoot = false; offset = NSMaxRange(tableRange); previousBlock = table.quote?.prefix ?? ""; previousChanged = false; previousContinuation = false; continue
            }
            var codeRange = NSRange()
            if !standalone, rich.attribute(.macCode, at: offset, effectiveRange: nil) is MacRichCode,
               let code = rich.attribute(.macCode, at: offset, longestEffectiveRange: &codeRange, in: NSRange(location: 0, length: rich.length)) as? MacRichCode {
                let body = MacRichCode.body(rich, in: codeRange)
                let attrs = rich.attributes(at: offset, effectiveRange: nil)
                let placement = attrs[.macListCard] as? MacListCardPlacement
                let head = (attrs[.macListContext] as? MacListContext).flatMap { heads[$0.id] }
                var value = placement?.markdown(code.markdown(body: body), attributes: attrs, head: head, joined: joinedCards.cards[offset] ?? []) ?? code.markdown(body: body)
                if !result.isEmpty && ![10, 13].contains(result.utf8.last ?? 0) { append(code.original.newline + code.original.newline) }
                if let indented = code.indented {
                    var last: (CodeBlock, Int)?
                    func inspect(_ node: any Markup, depth: Int = 0) {
                        let depth = depth + (node is BlockQuote ? 1 : 0)
                        if let block = node as? CodeBlock { last = (block, depth) }
                        for child in node.children { inspect(child, depth: depth) }
                    }
                    inspect(Document(parsing: result + value))
                    let normalized = MacMarkdownLines.normalized(body, to: "\n")
                    let depth = placement.map { (MacBlockPrefix(head?.source ?? attrs[.macBlock] as? String ?? "")?.depth ?? 0) + $0.ownerSuffix.filter { $0 == ">" }.count } ?? code.quote?.depth ?? 0
                    if last?.0.range?.lowerBound.line != sourceLine || last?.0.code != (normalized.isEmpty ? "" : normalized + "\n") || last?.1 != depth {
                        let fenced = indented.fenced(body: body)
                        value = placement?.markdown(fenced, attributes: attrs, head: head, joined: joinedCards.cards[offset] ?? []) ?? code.quote?.spelling(fenced) ?? fenced
                    }
                }
                append(value + (code.ending.isEmpty && NSMaxRange(codeRange) < rich.length ? code.original.newline : code.ending))
                scopeStart = (sourceLine, sourceOffset); scopeHasRoot = false
                // A closed fence cannot accept the following root prose as
                // a lazy quote continuation. Keep the conservative boundary for
                // indented code, whose spelling may still depend on its neighbor.
                offset = NSMaxRange(codeRange); previousBlock = code.indented == nil ? "" : code.quote?.prefix ?? ""; previousChanged = false; previousContinuation = false; continue
            }
            var compactRange = NSRange()
            if !standalone, rich.attribute(.macCompactList, at: offset, effectiveRange: nil) != nil,
               let compact = rich.attribute(.macCompactList, at: offset, longestEffectiveRange: &compactRange, in: NSRange(location: 0, length: rich.length)) as? MacCompactList,
               compactRange.location == offset {
                var positions: [(Int, MacListContext)] = [], cursor = offset
                while cursor < NSMaxRange(compactRange) {
                    if let context = rich.attribute(.macListContext, at: cursor, effectiveRange: nil) as? MacListContext, !context.continuation { positions.append((cursor - offset, context)) }
                    cursor = NSMaxRange(text.paragraphRange(for: NSRange(location: cursor, length: 0)))
                }
                if cursor == NSMaxRange(compactRange), positions.count == compact.heads.count,
                   zip(positions, compact.heads).allSatisfy({ $0.0.1.id == $0.1.0 && $0.0.1.source == $0.1.1 }) {
                    let group = rich.attributedSubstring(from: compactRange)
                    var emitted = compact.original, relativeLines = Array(repeating: 0, count: positions.count)
                    if signature(group, keys: signatureKeys) != compact.fingerprint {
                        let unpacked = NSMutableAttributedString(attributedString: group)
                        unpacked.removeAttribute(.macCompactList, range: NSRange(location: 0, length: unpacked.length))
                        let canonical = serializedMarkdown(unpacked)
                        let rows = MacMarkdownLines(canonical.text)
                        let consecutive = positions.enumerated().allSatisfy { canonical.headLines[$0.element.0] == $0.offset + 1 }
                        let emptyHeads = rows.lines.count >= positions.count && compact.heads.dropLast().enumerated().allSatisfy { rows.lines[$0.offset].text == $0.element.1 }
                        if consecutive, emptyHeads, let last = compact.heads.last,
                           rows.lines[positions.count - 1].text.hasPrefix(last.1),
                           !rows.lines[positions.count - 1].text.dropFirst(last.1.count).allSatisfy(\.isWhitespace) {
                            let row = rows.lines[positions.count - 1]
                            emitted = compact.prefix + row.text.dropFirst(last.1.count) + row.ending + rows.fragment(positions.count..<rows.lines.count)
                        } else {
                            emitted = canonical.text
                            relativeLines = positions.map { (canonical.headLines[$0.0] ?? 1) - 1 }
                        }
                    }
                    let firstLine = sourceLine, firstOffset = sourceOffset, emittedRows = MacMarkdownLines(emitted)
                    for (index, head) in positions.enumerated() {
                        sourceLine = firstLine + relativeLines[index]
                        sourceOffset = firstOffset + emittedRows.lines[relativeLines[index]].offset
                        recordParagraph(offset + head.0, emitted: "", changed: false, emptyHead: false)
                    }
                    sourceLine = firstLine; sourceOffset = firstOffset; append(emitted)
                    previousBlock = positions.last!.1.source; previousChanged = emitted != compact.original; previousContinuation = false
                    offset = NSMaxRange(compactRange); continue
                }
            }
            // Appending at EOF can leave the old token on only the marker or
            // text prefix. Reuse requires a whole native paragraph boundary.
            var paragraphRange = NSRange()
            if promotion == nil, rich.attribute(.macParagraphID, at: offset, effectiveRange: nil) != nil,
               rich.attribute(.macParagraphID, at: offset, longestEffectiveRange: &paragraphRange, in: NSRange(location: 0, length: rich.length)) != nil,
               paragraphRange.location == offset,
               NSMaxRange(paragraphRange) == rich.length || [10, 13, 0x2029].contains(Int(text.character(at: NSMaxRange(paragraphRange) - 1))),
               let original = rich.attribute(.macParagraphSource, at: offset, effectiveRange: nil) as? String,
               let fingerprint = rich.attribute(.macParagraphSignature, at: offset, effectiveRange: nil) as? String,
               reusableContext(at: offset), fingerprint == signature(rich.attributedSubstring(from: paragraphRange), keys: signatureKeys) {
                let context = rich.attribute(.macListContext, at: offset, effectiveRange: nil) as? MacListContext
                let block = rich.attribute(.macBlock, at: offset, effectiveRange: nil) as? String ?? ""
                if block.isEmpty, context?.continuation != true,
                   !text.substring(with: paragraphRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   previousContinuation || ((!displayPrefix(previousBlock).isEmpty || previousBlock.hasPrefix(">") && MacBlockPrefix(previousBlock)?.heading != true) && previousChanged) {
                    append(rich.attribute(.macLineEnding, at: offset, effectiveRange: nil) as? String ?? "\n")
                }
                previousContinuation = context.map { $0.continuation && heads[$0.id] != nil } ?? false
                let emitted = independentSpelling(original, range: paragraphRange)
                recordRootRow(paragraphRange, start: sourceOffset, emitted: emitted)
                recordParagraph(offset, emitted: emitted, changed: emitted != original); append(emitted); offset = NSMaxRange(paragraphRange); previousBlock = block; previousChanged = emitted != original; continue
            }
            var full = text.paragraphRange(for: NSRange(location: offset, length: 0))
            if !standalone {
                var nextCode: Int?
                rich.enumerateAttribute(.macCode, in: full) { value, range, stop in if value != nil { nextCode = range.location; stop.pointee = true } }
                rich.enumerateAttribute(.macTable, in: full) { value, range, stop in if value != nil { nextCode = min(nextCode ?? range.location, range.location); stop.pointee = true } }
                if let nextCode, nextCode > offset { full.length = nextCode - full.location }
            }
            let ends = text.substring(with: full).hasSuffix("\n")
            let range = NSRange(location: full.location, length: full.length - (ends ? 1 : 0))
            let line = rich.attributedSubstring(from: range)
            let attrs = line.length > 0 ? line.attributes(at: 0, effectiveRange: nil) : rich.attributes(at: full.location, effectiveRange: nil)
            let original = attrs[.macOriginal] as? String
            let unchanged = promotion == nil && original != nil && reusableContext(at: offset) && attrs[.macSignature] as? String == signature(line, keys: signatureKeys)
            let context = attrs[.macListContext] as? MacListContext
            let owner = context.flatMap { heads[$0.id] }
            let joinsPrevious = context.map { $0.continuation && joiningContinuation?.id == $0.id && joiningContinuation?.target == offset } ?? false
            var block = attrs[.macBlock] as? String ?? "", serialized: String
            if unchanged { serialized = original! }
            else {
                let marker = displayPrefix(block)
                let body = !marker.isEmpty && line.string.hasPrefix(marker) ? line.attributedSubstring(from: NSRange(location: marker.utf16.count, length: line.length - marker.utf16.count)) : line
                if let context, context.continuation { block = owner.map { context.replacing(source: $0.source).block } ?? (context.suffix.isEmpty ? "" : (MacBlockPrefix(context.source)?.quotes ?? "") + context.suffix) }
                var content = serializeInline(body, block: context?.continuation == true ? owner?.source ?? "" : block, continuation: context?.suffix.isEmpty == false ? block : nil)
                if joinsPrevious {
                    // Literal task-looking body text is safe below a child list,
                    // but at the marker line cmark would interpret it as a task.
                    content = content.replacingOccurrences(of: #"^\[([ xX])\](?=\s|$)"#, with: #"\\[$1\\]"#, options: .regularExpression)
                }
                if block.isEmpty {
                    // A literal paragraph must not become a heading or list when another editor parses it.
                    content = content.replacingOccurrences(of: #"^(#{1,6}|[-+])(?=\s)"#, with: #"\\$1"#, options: .regularExpression)
                    content = content.replacingOccurrences(of: #"^(\d+)([.)])(?=\s)"#, with: #"$1\\$2"#, options: .regularExpression)
                }
                let gap = joinsPrevious ? "" : context?.continuation == true ? (owner == nil ? (attrs[.macLineEnding] as? String ?? "\n") : context!.replacing(source: owner!.source).gap) : ""
                let onlyBreaks = content.range(of: #"^(?:<br>)+$"#, options: .regularExpression) != nil
                let emptyAnchor = MacBlockPrefix(context?.textBlock ?? block)?.heading != true && (onlyBreaks || content.isEmpty && attrs[.macEmptyParagraph] as? Bool == true)
                let innerPrefix = joinsPrevious || context?.continuation == false ? context?.suffix ?? "" : ""
                let bodyText = (emptyAnchor ? emptyParagraphMarker : "") + content
                if !joinsPrevious, context?.continuation == false, !innerPrefix.isEmpty,
                   let prefix = MacBlockPrefix(block), prefix.checklist {
                    // GFM parses block syntax after a checkbox as literal task
                    // text. Put the inner role below an explicit task paragraph.
                    let ending = attrs[.macLineEnding] as? String ?? "\n"
                    serialized = gap + block + emptyParagraphMarker + ending + prefix.listContinuation + innerPrefix + bodyText
                } else {
                    serialized = gap + (joinsPrevious ? "" : block) + innerPrefix + bodyText
                }
            }
            // CommonMark otherwise accepts the following paragraph as a lazy list/quote continuation.
            // Preserve imported tokens exactly until either side of this boundary is edited.
            if block.isEmpty, context?.continuation != true, !line.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               previousContinuation || ((!MacMarkdown.displayPrefix(previousBlock).isEmpty || previousBlock.hasPrefix(">") && MacBlockPrefix(previousBlock)?.heading != true) && (!unchanged || previousChanged)) {
                append(rich.attribute(.macLineEnding, at: offset, effectiveRange: nil) as? String ?? "\n")
            }
            // With the last child gone, the next owned paragraph can become
            // the item's first body. Keep its native gap for refill/Undo while
            // promoting its source onto an emptied marker line. A blank source
            // gap here would close the empty item and orphan that paragraph.
            let joinsNext = promotion != nil
            if let promotion, let context {
                joiningContinuation = (context.id, promotion)
                // Blank head text has no source paragraph of its own. Leaving
                // its spaces before the promoted body could turn that body into
                // indented code; its native text still survives refill and Undo.
                serialized = block
            }
            let protected = independentSpelling(serialized, range: full)
            let rootStart = sourceOffset
            var rootEmitted = protected
            recordParagraph(offset, emitted: protected, changed: !unchanged || protected != serialized, emptyHead: !joinsNext); append(protected)
            if joinsPrevious { joiningContinuation = nil; if let context { emptyParents.remove(context.id) } }
            if ends, !joinsNext {
                let newline = rich.attributes(at: NSMaxRange(full) - 1, effectiveRange: nil)
                if !unchanged, newline[.macHardBreak] as? Bool == true { append("  "); rootEmitted += "  " }
                // A reused line token can come from an inline paste without
                // its own terminator. Keep the receiving note's newline; only
                // append a bare LF when the reused spelling already ends in CR.
                let omitted = NSMaxRange(full) == rich.length && newline[.macUnterminated] as? Bool == true
                let ending = omitted ? "" : unchanged && protected.hasSuffix("\r") ? "\n" : newline[.macLineEnding] as? String ?? "\n"
                append(ending); rootEmitted += ending
            }
            recordRootRow(full, start: rootStart, emitted: rootEmitted)
            previousBlock = block; previousChanged = !unchanged || protected != serialized
            previousContinuation = context?.continuation == true && owner != nil
            offset = NSMaxRange(full)
        }
        let serialized = SerializedMarkdown(text: result, headLines: headLines, emptyHeadBoundaries: emptyHeadBoundaries, insertedEmptyBoundaries: [], rootRows: rootRows)
        return protectEmptyHeads ? protectingEmptyHeads(serialized) : serialized
    }
}

extension Notification.Name { static let macEditorAction = Notification.Name("zerus.mac.editorAction") }

struct MacRichEditor: NSViewRepresentable {
    @AppStorage("zerus.mac.interfaceZoom") private var interfaceZoom = 100
    @AppStorage("zerus.mac.noteTextSize") private var noteTextSize = 100
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macTheme) private var theme
    @Environment(\.macEditorInteractionEnabled) private var interactionEnabled
    @AppStorage("zerus.mac.noteLinkShortcuts") private var noteLinkShortcuts = true
    @AppStorage("zerus.mac.codeBlocks") private var codeBlocks = false
    @AppStorage("zerus.mac.noteWidth") private var noteWidth = 100
    @AppStorage("zerus.mac.noteAlignment") private var noteAlignment = "center"
    let markdown: String
    let source: Bool
    let editable: Bool
    var root: URL? = nil
    var path: String = ""
    var project: NativeExternalProjectFiles? = nil
    var images: [String: NSImage] = [:]
    var onChange: (String) -> Void
    var onEditingIntent: () -> Void = {}
    var onLink: (String) -> Void
    var onSourceChange: (Bool) -> Void = { _ in }
    var onPasteError: (String) -> Void = { _ in NSSound.beep() }
    var onPasteBusy: (Bool) -> Void = { _ in }
    var sourceHeader = ""
    var onModeChange: ((String, Bool) -> Void)? = nil
    // Resolve note snapshots only when completion or preview is requested.
    var linkNotes: () -> [NoteDocument] = { [] }
    var headingRequest: MacHeadingRequest?
    var focusRequest: UUID? = nil
    /// Reports the index of the heading at the top of the viewport.
    var onVisibleHeading: ((Int?) -> Void)? = nil
    var commandScope: UUID? = nil
    var isCurrent: () -> Bool = { true }
    // SwiftUI can deliver an already-queued view value after a native command
    // publishes a newer draft. A live model reader keeps that update coherent.
    var readDocument: (() -> (markdown: String, source: Bool))? = nil
    private var resolvedDocument: (markdown: String, source: Bool) {
        guard isCurrent(), let readDocument else { return (markdown, source) }
        return readDocument()
    }
    var sessions: MacEditorSessions? = nil
    var createLink: ((String) async throws -> NoteDocument)?
    var chooseImageProject: (() async -> Void)?
    func makeCoordinator() -> Coordinator { sessions?.acquire(self) ?? Coordinator(self) }
    private func applyNoteSize(_ scroll: NSScrollView) {
        // Compensate for the surrounding interface transform without changing
        // attributed text, Markdown, selection or the editor undo history.
        let scale = MacInterfaceZoom.factor(noteTextSize) / MacInterfaceZoom.factor(interfaceZoom)
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 4
        if abs(scroll.magnification - scale) > 0.0001 { scroll.magnification = scale }
    }
    func makeNSView(context: Context) -> NSScrollView {
        defer { if let scroll = context.coordinator.retainedScroll { applyNoteSize(scroll) } }
        context.coordinator.updateParent(self)
        context.coordinator.active = true
        let document = resolvedDocument
        if let scroll = context.coordinator.retainedScroll, let view = scroll.documentView as? MacEditorTextView {
            context.coordinator.view = view; view.delegate = context.coordinator; view.textStorage?.delegate = context.coordinator
            context.coordinator.environment = context.environment
            context.coordinator.environment.colorScheme = colorScheme
            context.coordinator.updateInteraction()
            view.setNoteLayout(MacNoteLayout(width: noteWidth, alignment: noteAlignment))
            if isCurrent(), !context.coordinator.lastMarkdown.utf8.elementsEqual(document.markdown.utf8) || context.coordinator.source != document.source { context.coordinator.load(document.markdown, source: document.source) }
            context.coordinator.refreshImages(force: true, includingStored: true)
            context.coordinator.observeImageViewport(scroll.contentView); context.coordinator.scheduleRemoteImages(); context.coordinator.scheduleVisibleHeading()
            context.coordinator.applyTheme(theme)
            context.coordinator.receiveHeading(headingRequest)
            context.coordinator.receiveFocus(focusRequest)
            return scroll
        }
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = MacEditorTextView(); view.isRichText = !document.source; view.importsGraphics = false; view.allowsUndo = true
        view.layoutManager?.delegate = view
        // Lay out visible/requested ranges, rather than filling the whole note
        // during idle time. Jumps can skip preceding offscreen paragraphs.
        view.layoutManager?.allowsNonContiguousLayout = true
        view.layoutManager?.backgroundLayoutEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = true; view.isContinuousSpellCheckingEnabled = true
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 46, height: 38); view.drawsBackground = false
        view.prepareCompositionRange = { [weak coordinator = context.coordinator] range in coordinator?.parent.onEditingIntent(); return coordinator?.prepareComposition(range) ?? range }
        view.hasSelectionComposition = { [weak coordinator = context.coordinator] in coordinator?.selectionCompositionActive == true }
        view.normalizedInputRange = { [weak coordinator = context.coordinator] range in coordinator?.caretInputRange(range) ?? range }
        view.handleCopy = { [weak coordinator = context.coordinator] cut in coordinator?.handleCopy(cut: cut) }
        view.cancelPaste = { [weak coordinator = context.coordinator] in coordinator?.clipboardTask?.cancel() }
        view.handlePaste = { [weak coordinator = context.coordinator] plain in coordinator?.handlePaste(plain: plain) }
        view.toggleChecklist = { [weak coordinator = context.coordinator] index in coordinator?.toggleChecklist(at: index) }
        view.imageAction = { [weak coordinator = context.coordinator] index, action in coordinator?.imageAction(at: index, action: action) }
        view.beginImageResize = { [weak coordinator = context.coordinator] index in
            guard let coordinator, coordinator.editorPanel == nil, let request = try? coordinator.prepareImageEdit(at: index) else { return nil }
            return { [weak coordinator] size in
                guard let coordinator, let size else { return }
                var value = request.value; value.width = Int(size.width.rounded())
                value.height = request.value.height == nil ? nil : Int(size.height.rounded())
                do { try coordinator.applyImage(request, value: value); coordinator.view?.setSelectedRange(request.range) }
                catch { coordinator.parent.onPasteError(error.localizedDescription) }
            }
        }
        view.previewLink = { [weak coordinator = context.coordinator] index, immediate in coordinator?.previewLink(at: index, immediate: immediate) }
        view.linkRevision = { [weak coordinator = context.coordinator] in coordinator?.loadToken }
        view.editLink = { [weak coordinator = context.coordinator] index, remove, revision in
            guard let coordinator, coordinator.loadToken == revision else { return }
            if remove {
                do { let request = try coordinator.prepareLinkEdit(at: index); try coordinator.applyLink(request, destination: nil, label: request.label.string) }
                catch { coordinator.parent.onPasteError(error.localizedDescription) }
            } else { coordinator.showLinkEditor(at: index) }
        }
        view.leaveLink = { [weak coordinator = context.coordinator] in coordinator?.notePreview.leave() }
        view.dismissLinkPreview = { [weak coordinator = context.coordinator] in coordinator?.notePreview.hide() }
        view.handleTableKey = { [weak coordinator = context.coordinator] backward in guard let coordinator else { return false }; return coordinator.moveTableCell(backward: backward) || coordinator.indentList(backward: backward) }
        view.handleCodeExit = { [weak coordinator = context.coordinator] in coordinator?.exitCode() ?? false }
        view.handleBlockBackspace = { [weak coordinator = context.coordinator] in coordinator?.backspaceTextBlock() ?? false }
        view.handleSelectedReturn = { [weak coordinator = context.coordinator] in
            guard let coordinator, let view = coordinator.view, !coordinator.source, view.isEditable, !view.hasMarkedText() else { return false }
            return !coordinator.textView(view, shouldChangeTextIn: view.selectedRange(), replacementString: "\n")
        }
        view.handleLinkKey = { [weak coordinator = context.coordinator] code in coordinator?.linkCompletion.key(code) ?? false }
        view.delegate = context.coordinator; view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        context.coordinator.environment = context.environment
        context.coordinator.environment.colorScheme = colorScheme
        view.isEditable = editable && interactionEnabled && isCurrent(); scroll.documentView = view; context.coordinator.view = view
        context.coordinator.retainedScroll = scroll
        view.setNoteLayout(MacNoteLayout(width: noteWidth, alignment: noteAlignment))
        context.coordinator.applyTheme(theme)
        context.coordinator.load(document.markdown, source: document.source)
        context.coordinator.receiveHeading(headingRequest)
        context.coordinator.receiveFocus(focusRequest)
        view.onCompositionEnded = { [weak coordinator = context.coordinator] text in coordinator?.compositionEnded(text) }
        view.onReady = { [weak coordinator = context.coordinator] in coordinator?.applyHeadingRequest(); coordinator?.applyFocusRequest(); coordinator?.scheduleRemoteImages(); coordinator?.scheduleVisibleHeading() }
        context.coordinator.observeImageViewport(scroll.contentView)
        return scroll
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if coordinator.sessions?.contains(coordinator) == true { coordinator.suspend() } else { coordinator.detach() }
        (scroll.documentView as? NSTextView)?.delegate = nil
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        applyNoteSize(scroll)
        context.coordinator.updateParent(self)
        context.coordinator.environment = context.environment
        context.coordinator.environment.colorScheme = colorScheme
        context.coordinator.refreshEditorPanel?(context.coordinator.environment)
        guard let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.updateInteraction()
        guard isCurrent() else { return }
        (view as? MacEditorTextView)?.setNoteLayout(MacNoteLayout(width: noteWidth, alignment: noteAlignment))
        let document = resolvedDocument
        if !context.coordinator.lastMarkdown.utf8.elementsEqual(document.markdown.utf8) || context.coordinator.source != document.source { context.coordinator.load(document.markdown, source: document.source) }
        context.coordinator.applyTheme(theme)
        context.coordinator.refreshImages()
        if !noteLinkShortcuts { context.coordinator.linkCompletion.hide() }
        context.coordinator.receiveHeading(headingRequest)
        context.coordinator.receiveFocus(focusRequest)
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, @MainActor NSTextStorageDelegate {
        var parent: MacRichEditor; weak var view: NSTextView?
        weak var sessions: MacEditorSessions?
        var retainedScroll: NSScrollView?
        var active = true
        func updateParent(_ value: MacRichEditor) {
            sessions = value.sessions
            var current = value; current.sessions = nil
            parent = current
        }
        var environment = EnvironmentValues()
        var refreshEditorPanel: ((EnvironmentValues) -> Void)?
        private var remoteImageTask: Task<Void, Never>?
        private var remoteImages: [String: NSImage] = [:]
        private var remoteImageCaps: [String: Int] = [:]
        private var remoteWanted: [String: Int] = [:]
        private var remoteFailures = Set<String>()
        private var remoteScanScheduled = false
        private var imageViewportObserver: NSObjectProtocol?
        private var visibleHeadingScheduled = false
        private var visibleHeadingCache: (markdown: String, starts: [Int])?
        var lastMarkdown = ""; var source = false; var loading = false
        private var ruleComposition: (text: NSAttributedString, selection: NSRange, typing: [NSAttributedString.Key: Any], markdown: String)?
        private var selectionComposition: (text: NSAttributedString, range: NSRange, selection: NSRange, typing: [NSAttributedString.Key: Any])?
        var selectionCompositionActive: Bool { selectionComposition != nil }
        private var receivedFocus: UUID?
        private var pendingFocus: UUID?
        private var focusScheduled = false
        func receiveFocus(_ request: UUID?) {
            if receivedFocus != request { receivedFocus = request; pendingFocus = request }
            applyFocusRequest()
        }
        func applyFocusRequest() {
            guard !focusScheduled, let request = pendingFocus, active, parent.isCurrent(),
                  parent.editable, parent.interactionEnabled, !pasting, let view,
                  view.isEditable, !view.hasMarkedText(), let window = view.window else { return }
            // Focus is a navigation event, not a layout side effect. If another
            // control gains focus before this callback, the user's action wins.
            focusScheduled = true
            DispatchQueue.main.async { [weak self, weak view, weak window, weak responder = window.firstResponder] in
                guard let self else { return }
                self.focusScheduled = false
                guard self.pendingFocus == request else { self.applyFocusRequest(); return }
                self.pendingFocus = nil
                guard let view, let window, self.view === view, view.window === window,
                      self.parent.focusRequest == request, self.active, self.parent.isCurrent(),
                      self.parent.editable, self.parent.interactionEnabled, view.isEditable,
                      !self.pasting, !view.hasMarkedText(), window.attachedSheet == nil else { return }
                let current = window.firstResponder
                guard current === responder || current == nil || current === view || current === window || current === window.contentView else { return }
                window.makeFirstResponder(view)
            }
        }
        private var restoreTypingFocus = false
        private var theme = MacTheme()
        private var appliedTheme: MacTheme?
        private let themeColors = MacEditorThemeColors()
        var observer: NSObjectProtocol?
        private var undoObservers: [NSObjectProtocol] = []
        fileprivate var clipboardTask: Task<Void, Never>?
        fileprivate var loadToken = UUID()
        private var displayedImages: [String: NSImage] = [:]
        private(set) var pasting = false
        let linkCompletion = MacNoteLinkCompletion()
        let notePreview = MacNotePreview()
        private var completionCaret: NSRange?
        private var typedCharacter: String?
        private var exported: MacMarkdown.Export?
        private var stylingExport = false
        // nil requests a complete pass after load/structural changes. Otherwise
        // retain only immutable block identities touched since the last publish.
        private var dirtyCodeBlocks: Set<ObjectIdentifier>?
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            if stylingExport && !editedMask.contains(.editedCharacters) { return }
            guard textStorage === view?.textStorage, !loading, !source else { exported = nil; dirtyCodeBlocks = nil; return }
            // Track AppKit's provisional edits too. Commit removes marked-text
            // attributes before publish validates the final row; edits spanning
            // rows or changing its structure still invalidate the sparse map.
            if dirtyCodeBlocks != nil {
                // Include neighbours at insertion/deletion boundaries. Code
                // edits need a whole-block lexical pass; prose edits do not.
                let lower = max(0, min(editedRange.location, textStorage.length) - 1)
                let upper = min(textStorage.length, NSMaxRange(editedRange) + 1)
                if upper > lower {
                    textStorage.enumerateAttribute(.macCode, in: NSRange(location: lower, length: upper - lower)) { code, _, _ in
                        if let code = code as? MacRichCode { dirtyCodeBlocks?.insert(ObjectIdentifier(code)) }
                    }
                }
            }
            exported?.edited(editedRange, delta: delta)
        }
        private var pendingHeading: MacHeadingRequest?
        private var receivedHeadingID: UUID?
        fileprivate var editorPanel: NSWindow?
        private let editorUndo = UndoManager()
        private var typingAfterBlockFormat = false
        func undoManager(for view: NSTextView) -> UndoManager? { active && parent.isCurrent() ? editorUndo : nil }
        init(_ parent: MacRichEditor) {
            var current = parent; current.sessions = nil
            self.parent = current; self.sessions = parent.sessions; super.init()
            observer = NotificationCenter.default.addObserver(forName: .macEditorAction, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, self.active, self.parent.isCurrent() else { return }
                    if let command = note.object as? MacTableChange {
                        guard self.parent.commandScope == command.scope, self.parent.path == command.request.path else { return }
                        do { try self.applyTable(command); command.result = .success(()) }
                        catch { command.result = .failure(error) }
                    } else if let command = note.object as? MacCodeChange {
                        guard self.parent.commandScope == command.scope, self.parent.path == command.request.path else { return }
                        do { try self.applyCode(command); command.result = .success(()) }
                        catch { command.result = .failure(error) }
                    } else if let command = note.object as? MacLocalAIEditorRequest {
                        guard self.parent.commandScope == command.scope, self.parent.path == command.path else { return }
                        command.result = Result { try self.handleLocalAI(command) }
                    } else if let command = note.object as? MacAttachmentImport {
                        guard self.parent.commandScope == command.scope, self.parent.path == command.path else { return }
                        command.task = Task { try await self.importAttachment(command) }
                    } else if let command = note.object as? MacEditorCommand {
                        guard self.parent.commandScope == command.scope, self.parent.path == command.path, self.view?.window?.attachedSheet == nil else { return }
                        if let view = self.view { view.window?.makeFirstResponder(view) }
                        if command.action != "focus" { self.action(command.action) }
                    } else if let action = note.object as? String, self.view?.window?.isKeyWindow == true { self.action(action) }
                }
            }
            for name in [Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
                undoObservers.append(NotificationCenter.default.addObserver(forName: name, object: editorUndo, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.publishAfterUndo() }
                })
            }
        }
        deinit { remoteImageTask?.cancel(); if let imageViewportObserver { NotificationCenter.default.removeObserver(imageViewportObserver) }; if let observer { NotificationCenter.default.removeObserver(observer) }; for observer in undoObservers { NotificationCenter.default.removeObserver(observer) } }
        private func publishAfterUndo() {
            guard active, parent.isCurrent(), !loading, let view else { return }
            refreshImages(force: true, includingStored: true)
            applyTheme(theme, force: true)
            let value = source ? view.string : MacMarkdown.markdown(view.attributedString())
            if Data(value.utf8) != Data(lastMarkdown.utf8) { exported = nil; publish() }
        }
        func importAttachment(_ command: MacAttachmentImport) async throws {
            guard let view, active, parent.isCurrent(), parent.editable, !pasting, !view.hasMarkedText(),
                  parent.commandScope == command.scope, parent.path == command.path,
                  Data(lastMarkdown.utf8) == Data(command.source.utf8), let root = parent.root else {
                throw VaultFailure(message: "The note changed while choosing the attachment. Attach it again to the intended note.")
            }
            let token = loadToken
            pasting = true; view.isEditable = false
            defer { pasting = false; if self.view === view { updateInteraction() } }
            // The file chooser retains its existing file-size behavior; the
            // clipboard's 50 MB transport limit does not apply to local files.
            guard command.fragment.resources.count == 1, let resource = command.fragment.resources.first,
                  let bytes = resource.bytes else { throw VaultFailure(message: "The attachment could not be read. Choose the file again.") }
            let importedPath = "assets/" + UUID().uuidString.lowercased() + "-" + MacClipboard.importName(resource.name)
            try await VaultFiles(root: root).write(importedPath, data: bytes, expected: nil)
            let reference = MarkdownResources.encodedPath(importedPath, preservingSuffixOf: "")
            let markdown = MarkdownResources.replacing(command.fragment.markdown, references: [resource.reference: reference])
            guard active, parent.isCurrent(), parent.editable, loadToken == token, self.view === view,
                  Data(lastMarkdown.utf8) == Data(command.source.utf8) else {
                throw VaultFailure(message: "The note changed. The imported attachment is kept in its original vault; attach it again to the intended note.")
            }
            let lines = MacMarkdownLines(command.source), ending = lines.ending(at: lines.lines.count - 1)
            let boundary = command.source.isEmpty || command.source.hasSuffix(ending + ending) ? "" : command.source.hasSuffix(ending) ? ending : ending + ending
            let updated = command.source + boundary + MacMarkdownLines.normalized(markdown.trimmingCharacters(in: .newlines), to: ending) + ending
            let nextSource = source || MacMarkdown.requiresSource(updated)
            let output = nextSource ? NSAttributedString(string: updated, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor]) : MacMarkdown.render(updated, root: root, path: parent.path, images: parent.images)
            commit(output, selection: NSRange(location: output.length, length: 0), name: "Attach file", asSource: nextSource == source ? nil : nextSource)
        }
        /// On-device AI: report the selection, or apply an approved rewrite of
        /// the whole note as one undo step ("Undo AI Edit").
        func handleLocalAI(_ command: MacLocalAIEditorRequest) throws -> MacLocalAIEditorRequest.Snapshot {
            guard let view, active, parent.isCurrent() else { throw VaultFailure(message: "Open the note in the editor and try again.") }
            switch command.kind {
            case .read:
                let range = view.selectedRange()
                var selection: String?
                if range.length > 0, NSMaxRange(range) <= view.textStorage?.length ?? 0 {
                    selection = source ? (view.string as NSString).substring(with: range)
                        : MacMarkdown.markdown(view.attributedString().attributedSubstring(from: range))
                }
                return .init(markdown: lastMarkdown, selection: selection)
            case .replace(let expected, let replacement, let actionName):
                guard parent.editable, !pasting, !view.hasMarkedText() else { throw VaultFailure(message: "The note can't be edited right now. Try again in a moment.") }
                guard Data(lastMarkdown.utf8) == Data(expected.utf8) else {
                    throw VaultFailure(message: "The note changed while the suggestion was being reviewed. Run the action again.")
                }
                let nextSource = source || MacMarkdown.requiresSource(replacement)
                let output = nextSource
                    ? NSAttributedString(string: replacement, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor])
                    : MacMarkdown.render(replacement, root: parent.root, path: parent.path, images: parent.images)
                let caret = min(view.selectedRange().location, output.length)
                commit(output, selection: NSRange(location: caret, length: 0), name: actionName, asSource: nextSource == source ? nil : nextSource)
                return .init(markdown: lastMarkdown, selection: nil)
            }
        }
        func applyTable(_ command: MacTableChange) throws {
            guard let view, parent.editable, !pasting, !view.hasMarkedText(), parent.commandScope == command.scope,
                  parent.path == command.request.path, Data(lastMarkdown.utf8) == Data(command.request.source.utf8) else {
                throw VaultFailure(message: "The note changed while this sheet was open. Your table stays here; copy it before closing, then reopen it.")
            }
            let existing = command.request.range.flatMap { requested in MacMarkdown.tables(in: lastMarkdown).first { $0.range == requested } }
            let incoming = MacMarkdown.tables(in: command.replacement)
            let replacementMarkdown = existing?.container?.spelling(command.replacement) ?? existing?.quote.flatMap { incoming.first?.quote == nil ? $0.spelling(command.replacement) : nil } ?? command.replacement
            if let container = existing?.container, !container.accepts(command.replacement, in: lastMarkdown, replacement: replacementMarkdown, table: true) {
                throw VaultFailure(message: "This draft would change the surrounding list or quote. Your draft stays in the sheet; copy it before closing.")
            }
            let parsed = MacMarkdown.tables(in: replacementMarkdown)
            guard parsed.count == 1, parsed[0].range.location == 0, NSMaxRange(parsed[0].range) == replacementMarkdown.utf16.count else { throw VaultFailure(message: "The table could not be prepared. Your table stays in this sheet.") }
            let before = view.attributedString(), output = NSMutableAttributedString(attributedString: view.attributedString())
            var selection: NSRange
            if let requested = command.request.range {
                let blocks = MacMarkdown.tables(in: lastMarkdown)
                guard let index = blocks.firstIndex(where: { $0.range == requested }) else { throw VaultFailure(message: "This table changed. Copy your draft and reopen it.") }
                if source {
                    output.replaceCharacters(in: requested, with: NSAttributedString(string: replacementMarkdown, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]))
                    selection = NSRange(location: requested.location, length: replacementMarkdown.utf16.count)
                } else {
                    var ranges: [(MacRichTable, NSRange)] = []
                    before.enumerateAttribute(.macTable, in: NSRange(location: 0, length: before.length)) { value, range, _ in if let table = value as? MacRichTable { ranges.append((table, range)) } }
                    guard ranges.indices.contains(index) else { throw VaultFailure(message: "This table changed. Copy your draft and reopen it.") }
                    let (table, range) = ranges[index]
                    guard existing?.container == nil || before.attribute(.macListCard, at: range.location, effectiveRange: nil) != nil else { throw VaultFailure(message: "Open this note in Source to edit this list-owned card.") }
                    let model: MacTableBlock
                    if existing?.container != nil {
                        guard incoming.count == 1 else { throw VaultFailure(message: "The table could not be prepared. Your table stays in this sheet.") }
                        model = incoming[0]
                    } else { model = parsed[0] }
                    let replacement = MacListCardPlacement.carrying(MacRichTable.render(model.table, ending: table.ending, root: parent.root, path: parent.path, images: parent.images, quote: model.quote), from: before.attributedSubstring(from: range))
                    output.replaceCharacters(in: range, with: replacement); selection = NSRange(location: range.location, length: replacement.length)
                }
                let expected = (lastMarkdown as NSString).replacingCharacters(in: requested, with: replacementMarkdown)
                if !source, existing?.container == nil || MacMarkdown.requiresSource(command.replacement), MacMarkdown.requiresSource(expected) {
                    commit(NSAttributedString(string: expected, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]), selection: NSRange(location: requested.location, length: replacementMarkdown.utf16.count), name: "Edit table", asSource: true); return
                }
                guard Data((source ? output.string : MacMarkdown.markdown(output)).utf8) == Data(expected.utf8) else { throw VaultFailure(message: "The surrounding note changed. Copy your draft and reopen the table.") }
            } else {
                var range = view.selectedRange()
                if source {
                    let blocks = MacMarkdown.tables(in: lastMarkdown).map(\.range) + MacMarkdown.codeRanges(in: lastMarkdown)
                    if let existing = blocks.first(where: { NSLocationInRange(range.location, $0) }) { range = NSRange(location: NSMaxRange(existing), length: 0) }
                    let raw = before.string as NSString, prefix = raw.substring(to: range.location), suffix = raw.substring(from: NSMaxRange(range))
                    let leading = prefix.isEmpty ? "" : String(repeating: "\n", count: max(0, 2 - prefix.reversed().prefix { $0 == "\n" }.count))
                    let trailing = suffix.isEmpty ? "\n" : String(repeating: "\n", count: max(0, 2 - suffix.prefix { $0 == "\n" }.count))
                    let replacement = leading + command.replacement + trailing
                    output.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)])); selection = NSRange(location: range.location, length: replacement.utf16.count)
                } else {
                    if range.location < before.length {
                        for key in [NSAttributedString.Key.macTable, .macCode] where before.attribute(key, at: range.location, effectiveRange: nil) != nil {
                            var block = NSRange(); _ = before.attribute(key, at: range.location, longestEffectiveRange: &block, in: NSRange(location: 0, length: before.length)); range = NSRange(location: NSMaxRange(block), length: 0); break
                        }
                    }
                    let replacement = MacClipboard.insertion(MacRichTable.render(parsed[0].table, ending: "\n", root: parent.root, path: parent.path, images: parent.images, quote: parsed[0].quote), into: before, range: range)
                    output.replaceCharacters(in: range, with: replacement); selection = NSRange(location: range.location, length: replacement.length)
                    let value = MacMarkdown.markdown(output)
                    if MacMarkdown.requiresSource(value) { commit(NSAttributedString(string: value, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]), selection: NSRange(location: 0, length: 0), name: "Insert table", asSource: true); return }
                }
            }
            guard Data((source ? output.string : MacMarkdown.markdown(output)).utf8) != Data(lastMarkdown.utf8) else { return }
            commit(output, selection: selection, name: command.request.range == nil ? "Insert table" : "Edit table")
        }
        func applyCode(_ command: MacCodeChange) throws {
            guard let view, parent.editable, !pasting, !view.hasMarkedText(), parent.commandScope == command.scope,
                  parent.path == command.request.path, Data(lastMarkdown.utf8) == Data(command.request.source.utf8) else {
                throw VaultFailure(message: "The note changed while this sheet was open. Your code stays here; copy it before closing, then reopen the block.")
            }
            let existing = command.request.range.flatMap { requested in MacCodeBlock.blocks(in: lastMarkdown).first { $0.range == requested } }
            let incoming = MacCodeBlock.blocks(in: command.replacement)
            let replacementMarkdown = existing?.container?.spelling(command.replacement) ?? existing?.quote.flatMap { incoming.first?.quote == nil ? $0.spelling(command.replacement) : nil } ?? command.replacement
            if let container = existing?.container, !container.accepts(command.replacement, in: lastMarkdown, replacement: replacementMarkdown, table: false) {
                throw VaultFailure(message: "This draft would change the surrounding list or quote. Your draft stays in the sheet; copy it before closing.")
            }
            let parsed = MacCodeBlock.blocks(in: replacementMarkdown)
            guard parsed.count == 1, parsed[0].range.location == 0, NSMaxRange(parsed[0].range) == replacementMarkdown.utf16.count else { throw VaultFailure(message: "The code block could not be prepared. Your code stays in this sheet.") }
            let before = view.attributedString(), output = NSMutableAttributedString(attributedString: view.attributedString())
            let selection: NSRange
            if let requested = command.request.range {
                let blocks = MacCodeBlock.blocks(in: lastMarkdown)
                guard let index = blocks.firstIndex(where: { $0.range == requested }) else { throw VaultFailure(message: "This code block changed. Copy your draft and reopen it.") }
                if source {
                    output.replaceCharacters(in: requested, with: NSAttributedString(string: replacementMarkdown, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor]))
                    selection = NSRange(location: requested.location, length: replacementMarkdown.utf16.count)
                } else {
                    var ranges: [(MacRichCode, NSRange)] = []
                    before.enumerateAttribute(.macCode, in: NSRange(location: 0, length: before.length)) { value, range, _ in if let code = value as? MacRichCode { ranges.append((code, range)) } }
                    guard ranges.indices.contains(index) else { throw VaultFailure(message: "This code block changed. Copy your draft and reopen it.") }
                    let (code, range) = ranges[index]
                    guard existing?.container == nil || before.attribute(.macListCard, at: range.location, effectiveRange: nil) != nil else { throw VaultFailure(message: "Open this note in Source to edit this list-owned card.") }
                    let model: MacCodeBlock
                    if existing?.container != nil {
                        guard incoming.count == 1 else { throw VaultFailure(message: "The code block could not be prepared. Your code stays in this sheet.") }
                        model = incoming[0]
                    } else { model = parsed[0] }
                    let replacement = MacListCardPlacement.carrying(MacRichCode.render(model.code, ending: code.ending, indented: model.indented, quote: model.quote), from: before.attributedSubstring(from: range))
                    output.replaceCharacters(in: range, with: replacement)
                    selection = NSRange(location: range.location, length: max(0, replacement.length - 1))
                }
                let expected = (lastMarkdown as NSString).replacingCharacters(in: requested, with: replacementMarkdown)
                let actual = source ? output.string : MacMarkdown.markdown(output)
                guard Data(actual.utf8) == Data(expected.utf8) else { throw VaultFailure(message: "The surrounding note changed. Copy your draft and reopen the block.") }
            } else {
                guard parent.codeBlocks else { throw VaultFailure(message: "Code block creation was turned off. Your code stays here; copy it or enable code blocks and try again.") }
                var range = view.selectedRange()
                if source {
                    let blocks = MacMarkdown.codeRanges(in: lastMarkdown) + MacMarkdown.tables(in: lastMarkdown).map(\.range)
                    if let existing = blocks.first(where: { NSLocationInRange(range.location, $0) }) { range = NSRange(location: NSMaxRange(existing), length: 0) }
                }
                if !source, range.location < before.length {
                    for key in [NSAttributedString.Key.macCode, .macTable] where before.attribute(key, at: range.location, effectiveRange: nil) != nil {
                        var block = NSRange(); _ = before.attribute(key, at: range.location, longestEffectiveRange: &block, in: NSRange(location: 0, length: before.length))
                        range = NSRange(location: NSMaxRange(block), length: 0); break
                    }
                }
                let ending: String
                if source {
                    let lines = MacMarkdownLines(lastMarkdown)
                    let row = lines.lines.lastIndex(where: { $0.offset <= range.location }) ?? 0
                    ending = lines.ending(at: row)
                } else { ending = MacMarkdown.lineEnding(in: before, at: range.location) }
                let markdown = MacMarkdownLines.normalized(command.replacement, to: ending)
                let replacement: NSAttributedString
                if source {
                    let raw = before.string as NSString, prefix = raw.substring(to: range.location), suffix = raw.substring(from: NSMaxRange(range))
                    func breaks(_ value: String) -> Int { value.reversed().prefix { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }.count }
                    let leading = prefix.isEmpty ? "" : String(repeating: ending, count: max(0, 2 - breaks(prefix)))
                    let trailing = suffix.isEmpty ? ending : String(repeating: ending, count: max(0, 2 - breaks(String(suffix.reversed()))))
                    replacement = NSAttributedString(string: leading + markdown + trailing, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor])
                } else {
                    guard let block = MacCodeBlock.blocks(in: markdown).first else { throw VaultFailure(message: "The code block could not be prepared. Your code stays in this sheet.") }
                    replacement = MacClipboard.insertion(MacRichCode.render(block.code, ending: ending, indented: block.indented, quote: block.quote), into: before, range: range)
                }
                output.replaceCharacters(in: range, with: replacement)
                selection = NSRange(location: range.location, length: replacement.length)
            }
            let value = source ? output.string : MacMarkdown.markdown(output)
            guard Data(value.utf8) != Data(lastMarkdown.utf8) else { return }
            commit(output, selection: selection, typing: source ? [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)] : typingAttributes(block: ""), name: command.request.range == nil ? "Insert code block" : "Edit code block")
        }
        func prepareImageEdit(at index: Int) throws -> MacImageEditRequest {
            guard let view, !source, !pasting, !view.hasMarkedText(), index >= 0, index < view.attributedString().length else { throw VaultFailure(message: "Select an image in rich text first.") }
            let attrs = view.attributedString().attributes(at: index, effectiveRange: nil)
            guard attrs[.macImageUnavailable] == nil, let attachment = attrs[.attachment] as? NSTextAttachment, let image = attachment.image,
                  let literal = attrs[.macLiteral] as? String, let value = MacInlineImage.parse(literal) else { throw VaultFailure(message: "This image is unavailable in the editor. Check its saved address in Source.") }
            return .init(range: NSRange(location: index, length: 1), literal: literal, baseline: lastMarkdown, token: loadToken, value: value, image: image)
        }
        func applyImage(_ request: MacImageEditRequest, value: MacInlineImage?) throws {
            guard let view, parent.editable, !pasting, !view.hasMarkedText(), request.token == loadToken, request.baseline == lastMarkdown,
                  NSMaxRange(request.range) <= view.attributedString().length,
                  view.attributedString().attribute(.macLiteral, at: request.range.location, effectiveRange: nil) as? String == request.literal else { throw VaultFailure(message: "The note or image changed. Reopen Edit image; your current text is kept.") }
            let output = NSMutableAttributedString(attributedString: view.attributedString())
            let replacement: NSAttributedString
            if let value {
                let value = try value.validated(), token = NSMutableAttributedString(attributedString: MacMarkdown.render(value.markdown, root: parent.root, path: parent.path, images: value.reference == request.value.reference ? parent.images.merging([value.reference: request.image]) { _, current in current } : parent.images))
                let original = view.attributedString().attributes(at: request.range.location, effectiveRange: nil)
                for key in [NSAttributedString.Key.macBlock, .font, .paragraphStyle, .macStrong, .link, .macTable, .macCell] { if let attr = original[key] { token.addAttribute(key, value: attr, range: NSRange(location: 0, length: token.length)) } }
                replacement = token
            }
            else { replacement = NSAttributedString(string: "") }
            output.replaceCharacters(in: request.range, with: replacement)
            commit(output, selection: NSRange(location: request.range.location + replacement.length, length: 0), name: value == nil ? "Remove image" : "Edit image")
        }
        private func closeEditorPanel() {
            if let panel = editorPanel { panel.sheetParent?.endSheet(panel); panel.close() }; editorPanel = nil; refreshEditorPanel = nil
        }
        private func editorPanelContent<Content: View>(_ content: Content, panel: NSPanel, environment: EnvironmentValues) -> some View {
            MacZoomPresentation { content }.environment(\.self, environment)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self, weak panel] size in
                    DispatchQueue.main.async { [weak self, weak panel] in
                        guard let self, let panel, let panelContent = panel.contentView, self.editorPanel === panel, size.width > 0, size.height > 0 else { return }
                        if abs(panelContent.bounds.width - size.width) > 0.5 || abs(panelContent.bounds.height - size.height) > 0.5 { panel.setContentSize(size) }
                    }
                }
        }
        private func editorPanelView<Content: View>(_ content: Content, panel: NSPanel) -> NSView {
            let host = NSHostingView(rootView: editorPanelContent(content, panel: panel, environment: environment))
            refreshEditorPanel = { [weak self, weak host, weak panel] environment in
                guard let self, let host, let panel else { return }
                host.rootView = self.editorPanelContent(content, panel: panel, environment: environment)
            }
            return host
        }
        func imageAction(at index: Int, action: String) {
            do {
                guard let window = view?.window, editorPanel == nil else { return }
                notePreview.hide(); linkCompletion.hide()
                if action == "retry" {
                    guard active, parent.isCurrent(), !source, !pasting, let view, !view.hasMarkedText(),
                          index >= 0, index < view.attributedString().length,
                          let literal = view.attributedString().attribute(.macLiteral, at: index, effectiveRange: nil) as? String,
                          let image = MacInlineImage.parse(literal),
                          ["http", "https"].contains(URL(string: image.reference)?.scheme?.lowercased() ?? "") else { return }
                    let reference = image.reference, token = loadToken
                    Task { [weak self] in
                        await MacRemoteImageStore.shared.forget(reference)
                        guard let self, self.active, self.parent.isCurrent(), self.loadToken == token else { return }
                        self.remoteFailures.remove(reference); self.remoteImageCaps.removeValue(forKey: reference); self.remoteWanted = [:]; self.scheduleRemoteImages()
                    }
                    return
                }
                let request = try prepareImageEdit(at: index)
                if action == "remove" {
                    guard parent.editable else { return }
                    let alert = NSAlert(); alert.messageText = "Remove image from note?"; alert.informativeText = "The original image file is kept. You can undo this change in the editor."
                    alert.addButton(withTitle: "Remove image"); alert.addButton(withTitle: "Cancel")
                    alert.beginSheetModal(for: window) { [weak self] response in
                        guard response == .alertFirstButtonReturn else { return }
                        do { try self?.applyImage(request, value: nil) } catch { self?.parent.onPasteError(error.localizedDescription) }
                    }; return
                }
                let expandSize = NSSize(width: max(760, window.frame.width * 0.94), height: max(560, window.frame.height * 0.92 - 28))
                let panel = NSPanel(contentRect: NSRect(origin: .zero, size: action == "expand" ? expandSize : NSSize(width: 580, height: 520)), styleMask: action == "expand" ? [.titled, .resizable] : [.titled], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false; panel.title = action == "expand" ? "Image preview" : "Edit image"; editorPanel = panel
                if action == "expand" {
                    panel.contentMinSize = NSSize(width: 480, height: 360)
                    panel.contentView = editorPanelView(MacImagePreviewPanel(image: request.image) { [weak self] in self?.closeEditorPanel() }.frame(minWidth: 480, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity), panel: panel)
                } else {
                    guard parent.editable else { editorPanel = nil; return }
                    panel.contentView = editorPanelView(MacImageEditView(request: request, apply: { [weak self] value in guard let self else { throw CancellationError() }; try self.applyImage(request, value: value); self.closeEditorPanel() }, cancel: { [weak self] in self?.closeEditorPanel() }), panel: panel)
                }
                window.beginSheet(panel)
            } catch { parent.onPasteError(error.localizedDescription) }
        }
        func receiveHeading(_ request: MacHeadingRequest?) {
            guard let request, request.path == parent.path, receivedHeadingID != request.id else { return }
            receivedHeadingID = request.id; pendingHeading = request
            applyHeadingRequest()
            DispatchQueue.main.async { [weak self] in self?.applyHeadingRequest() }
        }
        func applyHeadingRequest() {
            guard let request = pendingHeading, let view, view.window != nil, !view.hasMarkedText(), view.bounds.width > 0 else { return }
            pendingHeading = nil
            guard request.path == parent.path else { return }
            var range = NSRange(location: 0, length: 0)
            if !request.fragment.isEmpty {
                let headings = MacHeadings.entries(lastMarkdown)
                guard let heading = MacHeadings.target(request.fragment, in: headings) else { parent.onPasteError("This heading is no longer in the note. Choose a current heading in Outline."); return }
                if source { range = heading.range }
                else {
                    guard let located = richHeadingRange(heading, headings: headings, in: view.attributedString()) else { parent.onPasteError("The heading could not be located. Try Source mode."); return }
                    range = located
                }
            }
            guard NSMaxRange(range) <= view.attributedString().length else { return }
            linkCompletion.hide(); view.window?.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: range.location, length: 0)); view.scrollRangeToVisible(range)
            if range.length > 0 { view.showFindIndicator(for: range) }
        }
        /// Full source and native heading rows share document order. Rendering
        /// a truncated prefix can erase compact ancestors and shift the target.
        private func richHeadingRange(_ target: MacHeading, headings: [MacHeading], in rich: NSAttributedString) -> NSRange? {
            let text = rich.string as NSString
            var offset = 0, index = 0, located: NSRange?
            while offset < text.length {
                let paragraph = text.paragraphRange(for: NSRange(location: offset, length: 0))
                let block = rich.attribute(.macBlock, at: offset, effectiveRange: nil) as? String ?? ""
                let context = rich.attribute(.macListContext, at: offset, effectiveRange: nil) as? MacListContext
                if let role = MacBlockPrefix(context?.textBlock ?? block), role.heading {
                    guard index < headings.count, role.marker.prefix(while: { $0 == "#" }).count == headings[index].level else { return nil }
                    if headings[index].id == target.id {
                        let marker = MacBlockPrefix(block)?.display ?? "", count = marker.utf16.count
                        let hasMarker = count <= paragraph.length && text.substring(with: NSRange(location: offset, length: count)) == marker
                        let start = offset + (hasMarker ? count : 0)
                        located = NSRange(location: start, length: NSMaxRange(paragraph) - start)
                    }
                    index += 1
                }
                offset = NSMaxRange(paragraph)
            }
            return index == headings.count ? located : nil
        }
        func suspend() {
            active = false; pendingFocus = nil
            remoteImageTask?.cancel(); remoteImages = [:]; remoteImageCaps = [:]; remoteWanted = [:]; remoteFailures = []
            abandonComposition(); closeEditorPanel(); pendingHeading = nil; notePreview.hide(); linkCompletion.hide()
            clipboardTask?.cancel(); loadToken = UUID(); view?.breakUndoCoalescing()
            view?.isEditable = false; view?.textStorage?.delegate = nil
        }
        func detach() { suspend(); editorUndo.removeAllActions(); exported = nil; view = nil; retainedScroll = nil }
        func load(_ markdown: String, source: Bool) {
            guard let view else { return }; closeEditorPanel(); pendingHeading = nil; notePreview.hide(); linkCompletion.hide(); loadToken = UUID(); clipboardTask?.cancel(); loading = true; defer { loading = false; normalizeCaretSelection(); updateWritingContext() }
            remoteImageTask?.cancel(); remoteImages = [:]; remoteImageCaps = [:]; remoteWanted = [:]; remoteFailures = []
            exported = nil; view.textStorage?.delegate = self
            abandonComposition(); view.breakUndoCoalescing(); editorUndo.removeAllActions(); typingAfterBlockFormat = false
            self.source = source; lastMarkdown = markdown; view.isRichText = !source; displayedImages = parent.images
            let selected = view.selectedRange()
            var initialExport: MacMarkdown.Export?
            let value = source ? NSAttributedString(string: markdown, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor]) : MacMarkdown.render(markdown, root: parent.root, path: parent.path, images: parent.images, initialExport: { initialExport = $0 })
            view.textStorage?.setAttributedString(value)
            // Rendering already supplies code colours and paragraph styles.
            // Do not repeat that work on the first ordinary prose keystroke.
            dirtyCodeBlocks = []
            view.setSelectedRange(NSRange(location: min(selected.location, value.length), length: 0))
            var typing: [NSAttributedString.Key: Any] = [.font: source ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) : NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor]
            let cursor = view.selectedRange().location
            if !source, value.length > 0, cursor < value.length || !value.string.hasSuffix("\n") {
                let raw = value.string as NSString, row = raw.paragraphRange(for: NSRange(location: min(cursor, value.length - 1), length: 0))
                let block = value.attribute(.macBlock, at: row.location, effectiveRange: nil) as? String ?? ""
                let body = row.location + MacMarkdown.displayPrefix(block).utf16.count
                let at = min(value.length - 1, cursor > body ? cursor - 1 : body)
                typing = value.attributes(at: at, effectiveRange: nil)
                for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macLiteral, .attachment, .macImageUnavailable, .macRule, .macRuleGap, .macHardBreak, .macListBreak, .macUnterminated, .macCodePlaceholder, .macCodeSeparator, .macCellPlaceholder, .macCellEnd] { typing.removeValue(forKey: key) }
            }
            view.typingAttributes = typing
            applyTheme(theme, force: true)
            scheduleVisibleHeading()
            updateWritingContext()
            // Loading/theme storage notifications have finished. Only now can
            // subsequent edits be tracked against the freshly rendered mapping.
            exported = initialExport; scheduleRemoteImages()
        }
        func prepareImageInsertion() throws -> MacImageInsertRequest {
            guard active, parent.isCurrent(), parent.editable, let view, !pasting, !view.hasMarkedText() else { throw VaultFailure(message: "Finish the current edit before inserting an image.") }
            guard codeAtCaret() == nil else { throw VaultFailure(message: "Code keeps literal text. Insert an image in prose or Source.") }
            return .init(baseline: lastMarkdown, token: loadToken, range: view.selectedRange())
        }
        func insertImage(_ request: MacImageInsertRequest, value: MacInlineImage, file: MacImageFile? = nil) async throws {
            guard active, parent.isCurrent(), parent.editable, let view, !pasting, !view.hasMarkedText(),
                  request.token == loadToken, request.baseline.utf8.elementsEqual(lastMarkdown.utf8), request.range == view.selectedRange() else { throw VaultFailure(message: "The note or insertion point changed. Reopen Insert image; your draft is kept.") }
            var value = try value.validated(), resources: [NativeClipboardFragment.Resource] = []
            if let file {
                value.reference = "assets/insert-" + UUID().uuidString.lowercased()
                resources = [.init(reference: value.reference, path: nil, name: file.name, bytes: file.bytes)]
            } else if ["http", "https"].contains(URL(string: value.reference)?.scheme?.lowercased() ?? "") {
                guard let reference = MacWebAddress.canonical(value.reference) else { throw VaultFailure(message: "Enter a valid image URL.") }
                value.reference = reference
            }
            let fragment = NativeClipboardFragment(markdown: value.markdown, resources: resources)
            try await paste(.fragment(fragment), localReferencesAllowed: true, undoName: "Insert image")
        }
        func showImageInsertion() {
            do {
                guard let window = view?.window, editorPanel == nil else { return }
                let request = try prepareImageInsertion()
                notePreview.hide(); linkCompletion.hide()
                let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false; panel.title = "Insert image"; editorPanel = panel
                panel.contentView = editorPanelView(MacImageInsertView(apply: { [weak self] value, file in
                    guard let self else { throw CancellationError() }
                    try await self.insertImage(request, value: value, file: file); self.closeEditorPanel()
                }, chooseProject: parent.chooseImageProject, cancel: { [weak self] in self?.closeEditorPanel() }), panel: panel)
                panel.setContentSize(panel.contentView!.fittingSize); window.beginSheet(panel)
            } catch { parent.onPasteError(error.localizedDescription) }
        }
        func observeImageViewport(_ clip: NSClipView) {
            if let imageViewportObserver { NotificationCenter.default.removeObserver(imageViewportObserver) }
            clip.postsBoundsChangedNotifications = true
            imageViewportObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRemoteImages(); self?.scheduleVisibleHeading() }
            }
        }
        /// Coalesce scroll and typing bursts; counting headings above the
        /// viewport walks paragraphs, so it runs at most every 80 ms.
        func scheduleVisibleHeading() {
            guard parent.onVisibleHeading != nil, !visibleHeadingScheduled else { return }
            visibleHeadingScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.visibleHeadingScheduled = false
                    self.updateVisibleHeading()
                }
            }
        }
        private func updateVisibleHeading() {
            guard active, parent.isCurrent(), let report = parent.onVisibleHeading, let view, view.window != nil,
                  !view.hasMarkedText(), let manager = view.layoutManager, let container = view.textContainer else { return }
            let rich = view.attributedString(), text = rich.string as NSString
            guard text.length > 0 else { report(nil); return }
            // Match the Tauri outline: a heading counts once it is within 48 pt of the top.
            let point = NSPoint(x: 0, y: max(0, view.visibleRect.minY + 48 - view.textContainerOrigin.y))
            let limit = manager.characterIndexForGlyph(at: manager.glyphIndex(for: point, in: container))
            var count = 0
            if source {
                if visibleHeadingCache?.markdown != lastMarkdown { visibleHeadingCache = (lastMarkdown, MacHeadings.entries(lastMarkdown).map(\.range.location)) }
                count = visibleHeadingCache?.starts.prefix { $0 <= limit }.count ?? 0
            } else {
                // Rich headings appear in document order, as in richHeadingRange.
                var offset = 0
                while offset < text.length, offset <= limit {
                    let paragraph = text.paragraphRange(for: NSRange(location: offset, length: 0))
                    let block = rich.attribute(.macBlock, at: offset, effectiveRange: nil) as? String ?? ""
                    let context = rich.attribute(.macListContext, at: offset, effectiveRange: nil) as? MacListContext
                    if MacBlockPrefix(context?.textBlock ?? block)?.heading == true { count += 1 }
                    offset = NSMaxRange(paragraph)
                }
            }
            report(count == 0 ? nil : count - 1)
        }
        func scheduleRemoteImages() {
            guard !remoteScanScheduled else { return }; remoteScanScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.remoteScanScheduled = false }
                self.updateRemoteImages()
            }
        }
        private func updateRemoteImages() {
            guard active, parent.isCurrent(), let view, view.window != nil, !source else {
                remoteImageTask?.cancel(); remoteWanted = [:]; return
            }
            guard !pasting, !view.hasMarkedText(), let manager = view.layoutManager, let container = view.textContainer else { return }
            refreshImages()
            let rect = view.visibleRect.insetBy(dx: 0, dy: -view.visibleRect.height / 2).offsetBy(dx: -view.textContainerOrigin.x, dy: -view.textContainerOrigin.y)
            let glyphs = manager.glyphRange(forBoundingRect: rect, in: container)
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let rich = view.attributedString(), count = rich.length
            let visible = NSIntersectionRange(characters, NSRange(location: 0, length: count))
            var wanted: [String: Int] = [:]
            rich.enumerateAttribute(.macLiteral, in: visible) { literal, _, _ in
                guard let literal = literal as? String, let image = MacInlineImage.parse(literal),
                      ["http", "https"].contains(URL(string: image.reference)?.scheme?.lowercased() ?? "") else { return }
                let points = max(image.width ?? 0, image.height ?? 0, Int(view.bounds.width))
                let pixels = min(2048, max(128, ((points * Int(view.window?.backingScaleFactor ?? 2) + 127) / 128) * 128))
                wanted[image.reference] = max(wanted[image.reference] ?? 0, pixels)
            }
            guard wanted != remoteWanted else { return }
            remoteWanted = wanted; remoteImageTask?.cancel()
            let jobs = wanted.sorted { $0.key < $1.key }.filter { (remoteImageCaps[$0.key] ?? 0) < $0.value && !remoteFailures.contains($0.key) }
            guard !jobs.isEmpty else { return }
            let token = loadToken
            remoteImageTask = Task { [weak self] in
                guard let self else { return }
                await withTaskGroup(of: (String, Int, MacImagePixels?).self) { group in
                    var cursor = 0
                    func add(_ job: (key: String, value: Int)) {
                        group.addTask {
                            do { return (job.key, job.value, try await MacRemoteImageStore.shared.load(job.key, maximumPixel: job.value)) }
                            catch {
                                let failure = error as NSError
                                NSLog("Remote image preview failed (%@ %ld)", failure.domain, failure.code)
                                return (job.key, job.value, nil)
                            }
                        }
                    }
                    while cursor < min(2, jobs.count) { add(jobs[cursor]); cursor += 1 }
                    for await (reference, cap, pixels) in group {
                        guard !Task.isCancelled, self.active, self.parent.isCurrent(), !self.source, self.loadToken == token else {
                            NSLog("Remote image preview discarded (cancelled=%d active=%d current=%d source=%d revision=%d)", Task.isCancelled ? 1 : 0, self.active ? 1 : 0, self.parent.isCurrent() ? 1 : 0, self.source ? 1 : 0, self.loadToken == token ? 1 : 0)
                            group.cancelAll(); return
                        }
                        if self.remoteWanted[reference] == cap {
                            if let pixels {
                                self.remoteImages[reference] = NSImage(cgImage: pixels.image, size: .zero); self.remoteImageCaps[reference] = cap
                                self.refreshImages()
                            } else { self.remoteFailures.insert(reference) }
                        }
                        if cursor < jobs.count { add(jobs[cursor]); cursor += 1 }
                    }
                }
            }
        }
        func refreshImages(force: Bool = false, includingStored: Bool = false) {
            guard let view, !source, !pasting, !view.hasMarkedText() else { return }
            let images = parent.images.merging(remoteImages) { _, remote in remote }, previousImages = displayedImages
            guard includingStored || parent.root == nil || !images.isEmpty || !displayedImages.isEmpty else { return }
            guard force || displayedImages.count != images.count || images.contains(where: { displayedImages[$0.key] !== $0.value }) else { return }
            displayedImages = images
            let before = view.attributedString(), output = NSMutableAttributedString(attributedString: view.attributedString())
            var ranges: [(NSRange, String)] = []
            before.enumerateAttribute(.macLiteral, in: NSRange(location: 0, length: before.length)) { value, range, _ in
                if let literal = value as? String, MacInlineImage.parse(literal) != nil { ranges.append((range, literal)) }
            }
            var start = view.selectedRange().location, end = NSMaxRange(view.selectedRange())
            for (range, literal) in ranges.reversed() {
                guard let value = MacInlineImage.parse(literal), force || includingStored || previousImages[value.reference] !== images[value.reference] else { continue }
                var attrs = before.attributes(at: range.location, effectiveRange: nil); attrs.removeValue(forKey: .attachment); attrs.removeValue(forKey: .macImageUnavailable)
                let replacement = NSMutableAttributedString(attributedString: MacMarkdown.render(literal, root: parent.root, path: parent.path, images: images))
                replacement.addAttributes(attrs, range: NSRange(location: 0, length: replacement.length))
                output.replaceCharacters(in: range, with: replacement)
                func mapped(_ position: Int) -> Int {
                    if position <= range.location { return position }
                    if position >= NSMaxRange(range) { return position + replacement.length - range.length }
                    return range.location + min(position - range.location, replacement.length)
                }
                start = mapped(start); end = mapped(end)
            }
            guard !ranges.isEmpty else { return }
            let wasLoading = loading, typing = view.typingAttributes; loading = true
            view.textStorage?.setAttributedString(output); view.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
            view.typingAttributes = typing; loading = wasLoading
        }
        // Presentation changes never reload Markdown or register an Undo edit.
        // Keep marked text under AppKit's ownership until composition finishes.
        private func abandonComposition() {
            if ruleComposition != nil || selectionComposition != nil { ruleComposition = nil; selectionComposition = nil; editorUndo.enableUndoRegistration() }
        }
        func compositionEnded(_ committed: String? = nil) {
            if let pending = selectionComposition, let view, !view.hasMarkedText() {
                let current = view.attributedString(), length = current.length - pending.text.length + pending.range.length
                let inferred = length >= 0 && pending.range.location + length <= current.length ? (current.string as NSString).substring(with: NSRange(location: pending.range.location, length: length)) : ""
                let text = committed ?? inferred
                selectionComposition = nil
                loading = true; view.textStorage?.setAttributedString(pending.text); view.setSelectedRange(pending.selection); view.typingAttributes = pending.typing; loading = false
                editorUndo.enableUndoRegistration()
                if !text.isEmpty {
                    switch MacListEditing.replacingSelection(pending.text, range: pending.range, replacement: NSAttributedString(string: text, attributes: pending.typing), typing: pending.typing) {
                    case .changed(let edit): commit(edit.text, selection: edit.selection, typing: edit.typing, name: "Typing")
                    case .refused(let issue): if let issue { parent.onPasteError(issue) } else { NSSound.beep() }
                    case .notList, .unchanged: parent.onPasteError("This input needs Markdown source editing to preserve its paragraph and card boundaries.")
                    }
                }
                updateWritingContext(); applyTheme(theme); return
            }
            if let pending = ruleComposition, let view, !view.hasMarkedText() {
                ruleComposition = nil
                view.breakUndoCoalescing(); editorUndo.enableUndoRegistration()
                if MacMarkdown.markdown(view.attributedString()) == pending.markdown {
                    // Cancellation removes the temporary native paragraph too.
                    loading = true; view.textStorage?.setAttributedString(pending.text)
                    view.setSelectedRange(pending.selection); view.typingAttributes = pending.typing; loading = false
                    updateWritingContext()
                } else {
                    // Composition may span several input events. Record one
                    // immutable snapshot, rather than AppKit's transient ranges.
                    editorUndo.registerUndo(withTarget: self) { target in target.restore(pending.text, selection: pending.selection, typing: pending.typing) }
                    editorUndo.setActionName("Typing")
                }
                publish()
            }
            applyTheme(theme)
        }
        func applyTheme(_ theme: MacTheme, force: Bool = false) {
            // Remember the request even while AppKit owns marked text. unmarkText
            // and committed input both retry it, including cancelled composition.
            self.theme = theme
            guard let view, !view.hasMarkedText(), let storage = view.textStorage, force || appliedTheme != theme else { return }
            let install = force || appliedTheme == nil
            appliedTheme = theme; themeColors.theme = theme
            let wasLoading = loading, wasStyling = stylingExport; loading = true; stylingExport = true; defer { loading = wasLoading; stylingExport = wasStyling }
            if install {
                let copy = NSAttributedString(attributedString: storage)
                storage.beginEditing()
                copy.enumerateAttributes(in: NSRange(location: 0, length: copy.length)) { attrs, range, _ in
                    guard attrs[.macCode] == nil, attrs[.attachment] == nil else { return }
                    storage.addAttribute(.foregroundColor, value: themeColors.color(attrs[.link] == nil ? .text : .link), range: range)
                }
                storage.endEditing()
            }
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                if let rule = value as? MacRuleAttachment { rule.image?.recache() }
            }
            var typing = view.typingAttributes
            if typing[.macCode] == nil { typing[.foregroundColor] = themeColors.color(typing[.link] == nil ? .text : .link) }
            view.typingAttributes = typing
            view.linkTextAttributes = [.foregroundColor: themeColors.color(.link)]
            view.insertionPointColor = theme.nsColor(.accent)
            (view as? MacEditorTextView)?.markerColor = themeColors.color(.accent)
            MacRuleAttachment.strokeColor = themeColors.rule
            view.backgroundColor = theme.nsColor(.editorBg)
            // MacEditorTextView paints the writing surface before code cards.
            view.drawsBackground = false
            view.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length))
            view.needsDisplay = true
        }
        private func publish() {
            guard active, parent.isCurrent(), selectionComposition == nil, let view else { return }
            if !source, let storage = view.textStorage {
                let previous = loading, wasStyling = stylingExport; loading = true; stylingExport = true
                if let dirtyCodeBlocks, dirtyCodeBlocks.isEmpty { MacListCardPlacement.restyle(storage) }
                else { MacRichCode.style(storage, only: dirtyCodeBlocks) }
                dirtyCodeBlocks = []
                stylingExport = wasStyling; loading = previous
            }
            normalizeCaretSelection()
            updateWritingContext()
            applyTheme(theme)
            let value: String
            if source { exported = nil; value = view.string }
            else if let storage = view.textStorage {
                if let reused = exported?.value(storage) { value = reused }
                else { var fresh = MacMarkdown.Export(storage); value = fresh.value(storage)!; exported = fresh }
            } else { exported = nil; value = MacMarkdown.markdown(view.attributedString()) }
            lastMarkdown = value
            if let onModeChange = parent.onModeChange { onModeChange(value, source) } else { parent.onChange(value) }
        }
        private func updateWritingContext() {
            guard let view else { return }
            defer { applyTypingTheme() }
            let literal = source || codeAtCaret() != nil
            view.isAutomaticSpellingCorrectionEnabled = !literal
            view.isContinuousSpellCheckingEnabled = !literal
            if !source {
                var typing = view.typingAttributes
                typing.removeValue(forKey: .macListBreak); typing.removeValue(forKey: .macHardBreak); typing.removeValue(forKey: .macUnterminated)
                view.typingAttributes = typing
            }
            if view.selectedRange().length == 0, !source {
                if let storage = view.textStorage, storage.length > 0 {
                    let raw = storage.string as NSString, cursor = view.selectedRange().location
                    if cursor < raw.length || cursor == raw.length && !raw.hasSuffix("\n") {
                        let row = raw.paragraphRange(for: NSRange(location: min(cursor, raw.length - 1), length: 0))
                        let receiving = storage.attributes(at: row.location, effectiveRange: nil)
                        let block = receiving[.macBlock] as? String ?? ""
                        let content = raw.substring(with: row).trimmingCharacters(in: .whitespacesAndNewlines)
                        let marker = MacMarkdown.displayPrefix(block).trimmingCharacters(in: .whitespacesAndNewlines)
                        if content.isEmpty || !marker.isEmpty && content == marker {
                            var typing = view.typingAttributes
                            if typing[.macBlock] as? String != block { typing[.font] = MacMarkdown.font((receiving[.macListContext] as? MacListContext)?.textBlock ?? block) }
                            // A loaded empty heading's weight belongs to its
                            // role. Preserve an explicit user Bold choice, but
                            // do not infer strong markup from that role font.
                            if typing[.macStrong] == nil { typing[.macStrong] = receiving[.macStrong] }
                            for key in [NSAttributedString.Key.macBlock, .paragraphStyle, .macIndependentParagraph, .macListContext, .macLineEnding] { typing[key] = receiving[key] }
                            view.typingAttributes = typing
                        }
                    }
                }
                if let code = codeAtCaret() { view.typingAttributes = MacListCardPlacement.inheriting(MacRichCode.attributes(code), from: view.attributedString().attributes(at: view.selectedRange().location, effectiveRange: nil)) }
                else if let cell = cellAtCaret() {
                    var attrs = view.typingAttributes
                    for key in [NSAttributedString.Key.macCellEnd, .macCellPlaceholder, .macOriginal, .macSignature, .macLiteral] { attrs.removeValue(forKey: key) }
                    attrs[.macCell] = cell; attrs[.macTable] = cell.table; attrs[.paragraphStyle] = cell.attributes[.paragraphStyle]; attrs[.macBlock] = cell.table.quote?.prefix ?? ""
                    view.typingAttributes = MacListCardPlacement.inheriting(attrs, from: view.attributedString().attributes(at: view.selectedRange().location, effectiveRange: nil))
                } else if view.typingAttributes[.macCode] != nil || view.typingAttributes[.macTable] != nil { view.typingAttributes = typingAttributes(block: "") }
            }
        }
        private func applyTypingTheme() {
            guard let view, !view.hasMarkedText() else { return }
            var attrs = view.typingAttributes
            if attrs[.macCode] == nil { attrs[.foregroundColor] = themeColors.color(attrs[.link] == nil ? .text : .link) }
            view.typingAttributes = attrs
        }
        private func cellAtCaret() -> MacRichTable.Cell? {
            guard !source, let view else { return nil }
            return MacRichTable.at(view.attributedString(), view.selectedRange().location)
        }
        @discardableResult func moveTableCell(backward: Bool) -> Bool {
            guard let view, !source, !pasting, !view.hasMarkedText(), let cell = cellAtCaret() else { return false }
            var cells: [(MacRichTable.Cell, NSRange)] = []
            view.attributedString().enumerateAttribute(.macCell, in: NSRange(location: 0, length: view.attributedString().length)) { value, range, _ in if let value = value as? MacRichTable.Cell, value.table === cell.table { cells.append((value, range)) } }
            guard let index = cells.firstIndex(where: { $0.0 === cell }) else { return false }
            let next = index + (backward ? -1 : 1)
            if cells.indices.contains(next) { view.setSelectedRange(NSRange(location: cells[next].1.location, length: 0)); view.typingAttributes = cells[next].0.attributes; view.scrollRangeToVisible(view.selectedRange()) }
            else if !backward {
                var range = NSRange(); _ = view.attributedString().attribute(.macTable, at: view.selectedRange().location, longestEffectiveRange: &range, in: NSRange(location: 0, length: view.attributedString().length))
                var model = cell.table.model(view.attributedString().attributedSubstring(from: range)); let row = model.rows.count; model.insertRow(at: row)
                let replacement = MacListCardPlacement.carrying(MacRichTable.render(model, ending: cell.table.ending, root: parent.root, path: parent.path, images: parent.images, quote: cell.table.quote), from: view.attributedString().attributedSubstring(from: range))
                var first: Int?
                replacement.enumerateAttribute(.macCell, in: NSRange(location: 0, length: replacement.length)) { value, range, stop in if let value = value as? MacRichTable.Cell, value.row == row, value.column == 0 { first = range.location; stop.pointee = true } }
                let output = NSMutableAttributedString(attributedString: view.attributedString()); output.replaceCharacters(in: range, with: replacement)
                commit(output, selection: NSRange(location: range.location + (first ?? 0), length: 0), name: "Add table row")
            }
            return true
        }
        @discardableResult func indentList(backward: Bool) -> Bool {
            guard let view, parent.editable, !source, !pasting, !view.hasMarkedText(), cellAtCaret() == nil, codeAtCaret() == nil else { return false }
            switch MacListEditing.indent(view.attributedString(), selection: view.selectedRange(), backward: backward) {
            case .notList: return false
            case .unchanged: return true
            case .refused(let message):
                if let message { parent.onPasteError(message) } else { NSSound.beep() }
                return true
            case .changed(let edit):
                commit(edit.text, selection: edit.selection, name: backward ? "Outdent list" : "Indent list")
                typingAfterBlockFormat = true
                return true
            }
        }
        private func codeAtCaret() -> MacRichCode? {
            guard !source, let view else { return nil }
            return MacRichCode.at(view.attributedString(), view.selectedRange().location)
        }
        func textDidChange(_ notification: Notification) {
            guard !loading, selectionComposition == nil, let view else { return }; notePreview.hide()
            if !source && codeAtCaret() == nil && !view.hasMarkedText() && view.undoManager?.isUndoing != true && view.undoManager?.isRedoing != true { applyTypedShortcut(view); applyInlineShortcut(view) }
            publish(); scheduleVisibleHeading()
            if view.undoManager?.isUndoing != true && view.undoManager?.isRedoing != true { showNoteLinks(automatic: true) }
        }
        func prepareComposition(_ range: NSRange) -> NSRange {
            if selectionComposition == nil, ruleComposition == nil, !source, !loading, !pasting, parent.editable,
               let view, view.isEditable, !view.hasMarkedText() {
                let original = NSAttributedString(attributedString: view.attributedString())
                let raw = original.string as NSString
                let crossesParagraphs = range.length > 0 && range.location < raw.length && range.length <= raw.length - range.location &&
                    raw.paragraphRange(for: NSRange(location: range.location, length: 0)) != raw.paragraphRange(for: NSRange(location: min(NSMaxRange(range), raw.length - 1), length: 0))
                let outcome: MacListEditing.Outcome
                if let edit = MacHorizontalRule.removingOwnedRule(original, range: range) { outcome = .changed(edit) }
                else {
                    outcome = crossesParagraphs
                        ? MacListEditing.replacingSelection(original, range: range, replacement: NSAttributedString(), typing: view.typingAttributes)
                        : MacListEditing.replacingCardSelection(original, range: range, replacement: NSAttributedString(), typing: view.typingAttributes)
                }
                switch outcome {
                case .changed, .refused:
                    view.breakUndoCoalescing()
                    selectionComposition = (original, range, view.selectedRange(), view.typingAttributes)
                    editorUndo.disableUndoRegistration(); return range
                case .notList, .unchanged: break
                }
            }
            return prepareRuleComposition(range)
        }
        private func prepareRuleComposition(_ range: NSRange) -> NSRange {
            guard ruleComposition == nil, !source, !loading, !pasting, range.length == 0, let view, view.isEditable, !view.hasMarkedText(),
                  view.attributedString().length > 0 else { return range }
            let original = view.attributedString(), raw = view.string as NSString
            guard range.location < raw.length || range.location == raw.length && !raw.hasSuffix("\n") else { return range }
            let row = raw.paragraphRange(for: NSRange(location: min(range.location, raw.length - 1), length: 0))
            guard original.attribute(.macRule, at: row.location, effectiveRange: nil) != nil else { return range }
            let typing = MacHorizontalRule.continuationAttributes(original.attributes(at: row.location, effectiveRange: nil))
            var gap = typing; gap[.macRuleGap] = true
            let before = range.location == row.location, terminated = raw.substring(with: row).hasSuffix("\n")
            let at = before ? row.location : NSMaxRange(row)
            let output = NSMutableAttributedString(attributedString: original)
            output.insert(NSAttributedString(string: before || terminated ? "\n" : "\n\n", attributes: gap), at: at)
            let selected = NSRange(location: at + (!before && !terminated ? 1 : 0), length: 0)
            // Empty input scaffolding has no Markdown bytes. Keep AppKit's
            // provisional ranges out of Undo until the whole composition ends.
            view.breakUndoCoalescing()
            ruleComposition = (NSAttributedString(attributedString: original), view.selectedRange(), view.typingAttributes, MacMarkdown.markdown(original))
            editorUndo.disableUndoRegistration()
            loading = true; view.textStorage?.setAttributedString(output); view.setSelectedRange(selected)
            view.typingAttributes = typing; loading = false; updateWritingContext()
            return selected
        }
        func caretInputRange(_ range: NSRange) -> NSRange {
            guard !loading, !source, !pasting, parent.editable, parent.interactionEnabled,
                  let view, !view.hasMarkedText(), let storage = view.textStorage else { return range }
            return MacListEditing.caretInputRange(in: storage, range: range)
        }
        private func normalizeCaretSelection() {
            guard let view = view as? MacEditorTextView else { return }
            let range = view.selectedRange(), checked = caretInputRange(range)
            guard checked != range else { return }
            loading = true; view.setSelectedRange(checked); loading = false
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !loading, let view else { return }
            normalizeCaretSelection()
            updateWritingContext()
            if linkCompletion.shown, completionCaret != view.selectedRange() { linkCompletion.hide() }
        }
        func prepareLinkEdit(at index: Int? = nil) throws -> MacLinkEditRequest {
            guard active, parent.isCurrent(), parent.editable, let view, !pasting, !view.hasMarkedText() else { throw VaultFailure(message: "Finish the current edit before changing a link.") }
            let original = view.attributedString(), selection = view.selectedRange()
            var range = index.map { NSRange(location: $0, length: 0) } ?? selection
            guard range.location <= original.length, NSMaxRange(range) <= original.length else { throw VaultFailure(message: "Choose the link again in the current note.") }
            var destination: String?, title: String?, sourceLabel: String?
            if source {
                let parsed = MacLinkEditRequest.sourceLinks(lastMarkdown)
                if let link = parsed.links.first(where: { candidate in
                    range.length == 0 ? range.location >= candidate.range.location && range.location <= NSMaxRange(candidate.range) : range.location >= candidate.range.location && NSMaxRange(range) <= NSMaxRange(candidate.range)
                }) {
                    range = link.range; destination = link.destination; title = link.title; sourceLabel = link.label
                }
                guard !parsed.code.contains(where: { range.length == 0 ? NSLocationInRange(range.location, $0) : NSIntersectionRange(range, $0).length > 0 }) else { throw VaultFailure(message: "Code keeps its literal text. Select prose to insert a link.") }
                sourceLabel = sourceLabel ?? (lastMarkdown as NSString).substring(with: range)
                guard !(sourceLabel ?? "").contains(where: { $0 == "\n" || $0 == "\r" }) else { throw VaultFailure(message: "Select inline text in Source to edit one link.") }
            } else {
                let probe = range.location < original.length && original.attribute(.link, at: range.location, effectiveRange: nil) != nil ? range.location : range.length == 0 && range.location > 0 ? range.location - 1 : range.location
                if probe < original.length {
                    var linked = NSRange()
                    if let value = original.attribute(.link, at: probe, longestEffectiveRange: &linked, in: NSRange(location: 0, length: original.length)),
                       range.length == 0 || range.location >= linked.location && NSMaxRange(range) <= NSMaxRange(linked) {
                        range = linked; destination = String(describing: value); title = original.attribute(.macLinkTitle, at: linked.location, effectiveRange: nil) as? String
                    }
                }
                var forbidden = false, cells = Set<String>()
                original.enumerateAttributes(in: range) { attrs, _, _ in
                    if attrs[.macCode] != nil || attrs[.macRule] != nil || attrs[.macTable] != nil && attrs[.macCell] == nil { forbidden = true }
                    if let cell = attrs[.macCell] { cells.insert(String(describing: cell)) }
                }
                if range.length == 0, range.location < original.length, original.attribute(.macCode, at: range.location, effectiveRange: nil) != nil { forbidden = true }
                guard !forbidden, cells.count <= 1 else { throw VaultFailure(message: "Select prose or text inside one table cell to edit a link.") }
            }
            let label = source ? MacMarkdown.render(sourceLabel ?? "") : original.attributedSubstring(from: range)
            var formats = Set<String>(), attachment = false
            label.enumerateAttributes(in: NSRange(location: 0, length: label.length)) { attrs, _, _ in
                let traits = (attrs[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0).rawValue } ?? 0
                formats.insert("\(traits):\(attrs[.macStrong] as? Bool ?? false):\(attrs[.underlineStyle] as? Int ?? 0):\(attrs[.strikethroughStyle] as? Int ?? 0)")
                if attrs[.attachment] != nil { attachment = true }
            }
            let canEdit = !attachment && !label.string.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" }) && formats.count <= 1 && (sourceLabel == nil || sourceLabel == label.string)
            return .init(baseline: lastMarkdown, token: loadToken, range: range, selection: selection, source: source, label: label, sourceLabel: sourceLabel, destination: destination, title: title, canEditLabel: canEdit)
        }
        func applyLink(_ request: MacLinkEditRequest, destination rawDestination: String?, label editedLabel: String) throws {
            guard active, parent.isCurrent(), parent.editable, let view, !pasting, !view.hasMarkedText(), request.token == loadToken,
                  request.source == source, request.baseline.utf8.elementsEqual(lastMarkdown.utf8), view.selectedRange() == request.selection,
                  NSMaxRange(request.range) <= view.attributedString().length else { throw VaultFailure(message: "The note or selection changed. Reopen the link dialog; your current text is kept.") }
            let destination: String?
            if let rawDestination {
                if let url = URL(string: rawDestination), let reference = NoteReference(url: url) {
                    guard reference.targets(in: parent.linkNotes()).count == 1 else { throw VaultFailure(message: "This note is unavailable or ambiguous. Choose a current vault note.") }
                    destination = reference.url.absoluteString
                } else {
                    guard let canonical = MacWebAddress.canonical(rawDestination) else { throw VaultFailure(message: "Enter a valid http or https web URL.") }
                    destination = canonical
                }
            } else { destination = nil }
            let changedLabel = request.canEditLabel && !editedLabel.utf8.elementsEqual(request.label.string.utf8)
            let label = changedLabel ? editedLabel : request.label.string
            let fallback = label.isEmpty && destination != nil ? destination! : label
            guard !fallback.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\u{2028}" }) || !request.canEditLabel else { throw VaultFailure(message: "Display text must stay on one line.") }
            let original = view.attributedString(), output = NSMutableAttributedString(attributedString: original)
            var typing = request.range.location < original.length ? original.attributes(at: request.range.location, effectiveRange: nil) : view.typingAttributes
            for key in [NSAttributedString.Key.link, .macLinkTitle, .macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macLiteral, .attachment] { typing.removeValue(forKey: key) }
            var selection = request.range
            if source {
                let literal = changedLabel || request.label.length == 0 ? MacMarkdown.markdown(NSAttributedString(string: fallback, attributes: [.font: NSFont.systemFont(ofSize: 15)])) : request.sourceLabel ?? fallback
                let markdown: String
                if let destination {
                    if let url = URL(string: destination), let reference = NoteReference(url: url) { markdown = reference.markdown(label: fallback, formattedLabel: literal == fallback ? nil : literal) }
                    else { markdown = "[" + literal + "](" + MacLinkEditRequest.webMarkdownDestination(destination) + MacLinkEditRequest.titleSuffix(request.title) + ")" }
                } else { markdown = literal }
                output.replaceCharacters(in: request.range, with: NSAttributedString(string: markdown, attributes: typing)); selection = NSRange(location: request.range.location, length: markdown.utf16.count)
            } else {
                if changedLabel || request.range.length == 0 {
                    output.replaceCharacters(in: request.range, with: NSAttributedString(string: fallback, attributes: typing)); selection = NSRange(location: request.range.location, length: fallback.utf16.count)
                }
                // Each selected paragraph keeps its block marker and terminator.
                // Links decorate the selected body, including inline formatting.
                let text = output.string as NSString
                var cursor = selection.location
                while cursor < NSMaxRange(selection) {
                    let paragraph = text.paragraphRange(for: NSRange(location: cursor, length: 0))
                    let block = output.attribute(.macBlock, at: paragraph.location, effectiveRange: nil) as? String ?? ""
                    let marker = MacBlockPrefix(block)?.display ?? ""
                    let start = paragraph.location + (marker.isEmpty || !text.substring(with: paragraph).hasPrefix(marker) ? 0 : marker.utf16.count)
                    var end = NSMaxRange(paragraph)
                    while end > start && [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
                    let body = NSIntersectionRange(selection, NSRange(location: start, length: max(0, end - start)))
                    if body.length > 0 {
                        output.removeAttribute(.link, range: body); output.removeAttribute(.macLinkTitle, range: body)
                        if let destination {
                            output.addAttribute(.link, value: destination, range: body)
                            if let title = request.title { output.addAttribute(.macLinkTitle, value: title, range: body) }
                        }
                    }
                    cursor = NSMaxRange(paragraph)
                }
            }
            guard !(source ? output.string : MacMarkdown.markdown(output)).utf8.elementsEqual(lastMarkdown.utf8) else { return }
            view.window?.makeFirstResponder(view)
            commit(output, selection: selection, typing: typing, name: destination == nil ? "Remove link" : request.destination == nil ? "Insert link" : "Edit link")
        }
        func showLinkEditor(at index: Int? = nil) {
            do {
                guard let window = view?.window, editorPanel == nil else { return }
                let request = try prepareLinkEdit(at: index)
                notePreview.hide(); linkCompletion.hide()
                let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 340), styleMask: [.titled], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false; panel.title = "Edit link"; editorPanel = panel
                panel.contentView = editorPanelView(MacInlineLinkEditView(request: request, notes: parent.linkNotes(), apply: { [weak self] destination, label in
                    guard let self else { throw CancellationError() }
                    try self.applyLink(request, destination: destination, label: label); self.closeEditorPanel()
                }, cancel: { [weak self] in self?.closeEditorPanel() }), panel: panel)
                panel.setContentSize(panel.contentView!.fittingSize)
                window.beginSheet(panel)
            } catch { parent.onPasteError(error.localizedDescription) }
        }
        func previewLink(at index: Int, immediate: Bool) {
            guard let view, !source, !view.hasMarkedText(), !pasting, !linkCompletion.shown,
                  index >= 0, index < view.attributedString().length else { notePreview.leave(); return }
            var range = NSRange()
            guard let link = view.attributedString().attribute(.link, at: index, effectiveRange: &range) else { notePreview.leave(); return }
            let value = String(describing: link), token = loadToken
            let notes = parent.linkNotes()
            guard MacNotePreviewSnapshot(value: value, notes: notes, currentPath: parent.path) != nil else {
                notePreview.hide()
                if immediate { parent.onPasteError("This linked note is unavailable or ambiguous in the current vault.") }
                return
            }
            notePreview.show(value: value, at: range, view: view, notes: notes, path: parent.path, immediate: immediate) { [weak self] in
                guard let self, self.loadToken == token else { return }; self.parent.onLink(value)
            }
        }
        func showNoteLinks(automatic: Bool) {
            notePreview.hide()
            guard let view, view.isEditable, codeAtCaret() == nil, !view.hasMarkedText(), !pasting, !automatic || (!source && parent.noteLinkShortcuts) else { linkCompletion.hide(); return }
            let selection = view.selectedRange(), trigger = automatic ? MacNoteLinkTrigger.match(view.string, caret: selection) : nil
            if automatic && trigger == nil { linkCompletion.hide(); return }
            if automatic, selection.location > 0 {
                let attrs = view.attributedString().attributes(at: selection.location - 1, effectiveRange: nil)
                if attrs[.link] != nil || (attrs[.font] as? NSFont).map({ NSFontManager.shared.traits(of: $0).contains(.fixedPitchFontMask) }) == true { linkCompletion.hide(); return }
            }
            let range = trigger?.range ?? selection, query = trigger?.query ?? (view.string as NSString).substring(with: selection)
            let baseline = lastMarkdown, token = loadToken
            completionCaret = selection
            linkCompletion.show(view: view, query: query, notes: parent.linkNotes(), canCreate: parent.createLink != nil, manual: !automatic) { [weak self] note, chosenQuery in
                guard let self else { return }; self.linkCompletion.hide()
                if let note { self.insertNoteLink(note, range: range, baseline: baseline, caret: selection, token: token, space: automatic) }
                else if let create = self.parent.createLink {
                    Task { [weak self] in
                        do {
                            guard let self, let view = self.view, view.window != nil, self.loadToken == token, self.lastMarkdown == baseline, view.selectedRange() == selection else { return }
                            let note = try await create(chosenQuery)
                            self.insertNoteLink(note, range: range, baseline: baseline, caret: selection, token: token, space: automatic)
                        } catch { self?.parent.onPasteError(error.localizedDescription) }
                    }
                }
            }
        }
        func insertNoteLink(_ note: NoteDocument, range: NSRange, baseline: String, caret: NSRange, token: UUID, space: Bool = false) {
            guard let view, parent.editable, !pasting, !view.hasMarkedText(), token == loadToken, baseline == lastMarkdown, caret == view.selectedRange(), NSMaxRange(range) <= view.attributedString().length else { parent.onPasteError("The note or insertion point changed. Choose the link again; the typed text is kept."); return }
            let target = note.stableID.map { "zerus:" + $0 } ?? (note.path as NSString).deletingPathExtension
            let reference = NoteReference(target: target, label: note.title, explicitLabel: true), markdown = reference.markdown(label: note.title)
            let original = view.attributedString(), output = NSMutableAttributedString(attributedString: original)
            var attributes = view.typingAttributes
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macLiteral, .attachment, .link] { attributes.removeValue(forKey: key) }
            let insertion = NSMutableAttributedString(attributedString: source ? NSAttributedString(string: markdown, attributes: attributes) : MacClipboard.insertion(MacMarkdown.render(markdown), into: original, range: range))
            if space { insertion.append(NSAttributedString(string: " ", attributes: attributes)) }
            if let cell = cellAtCaret() { insertion.setAttributedString(MacRichTable.insertion(insertion, cell: cell)) }
            output.replaceCharacters(in: range, with: insertion)
            linkCompletion.hide(); view.window?.makeFirstResponder(view)
            commit(output, selection: NSRange(location: range.location + insertion.length, length: 0), typing: attributes, name: "Insert note link")
        }
        func updateInteraction() {
            guard let view else { return }
            let enabled = active && parent.isCurrent() && parent.editable && parent.interactionEnabled
            if !enabled, view.window?.firstResponder === view {
                restoreTypingFocus = true
                // Resigning may commit marked text. Do that outside the SwiftUI update.
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view, self.view === view, !self.active || !self.parent.isCurrent() || !self.parent.editable || !self.parent.interactionEnabled,
                          view.window?.firstResponder === view else { return }
                    view.window?.makeFirstResponder(nil)
                }
            }
            view.isEditable = enabled && !pasting
            if enabled, restoreTypingFocus {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view, self.view === view, self.active, self.parent.isCurrent(), self.parent.editable, self.parent.interactionEnabled,
                          view.isEditable, let window = view.window, window.attachedSheet == nil else { return }
                    // A user who has focused another control keeps that focus.
                    if window.firstResponder == nil || window.firstResponder === window.contentView || window.firstResponder === window {
                        window.makeFirstResponder(view)
                    }
                    self.restoreTypingFocus = false
                }
            }
        }
        @MainActor func handleCopy(cut: Bool) {
            guard !pasting else { return }
            clipboardTask = Task { [weak self] in
                do { try await self?.copy(cut: cut) } catch is CancellationError {} catch { self?.parent.onPasteError(error.localizedDescription) }
            }
        }
        func backspaceTextBlock() -> Bool {
            guard let view, !source, view.isEditable, !pasting, !view.hasMarkedText(),
                  view.undoManager?.isUndoing != true, view.undoManager?.isRedoing != true else { return false }
            let original = view.attributedString()
            switch MacListEditing.backspacingEmptyBlock(original, caret: view.selectedRange()) {
            case .changed(let edit):
                typedCharacter = nil
                commit(edit.text, selection: edit.selection, typing: edit.typing, name: "Remove empty block")
                return true
            case .refused(let message):
                if let message { parent.onPasteError(message) } else { NSSound.beep() }
                return true
            case .notList, .unchanged:
                switch MacQuoteEditing.mergingAtStart(original, caret: view.selectedRange(), source: lastMarkdown) {
                case .changed(let edit):
                    typedCharacter = nil
                    commit(edit.text, selection: edit.selection, typing: edit.typing, name: "Merge quote paragraph")
                    return true
                case .refused(let message):
                    if let message { parent.onPasteError(message) } else { NSSound.beep() }
                    return true
                case .notList, .unchanged: break
                }
                switch MacQuoteEditing.removingAtStart(original, caret: view.selectedRange(), source: lastMarkdown, root: parent.root, path: parent.path, images: parent.images) {
                case .changed(let edit):
                    typedCharacter = nil
                    commit(edit.text, selection: edit.selection, typing: edit.typing, name: "Remove quote")
                    return true
                case .refused(let message):
                    if let message { parent.onPasteError(message) } else { NSSound.beep() }
                    return true
                case .notList, .unchanged: return false
                }
            }
        }
        private func commitListDeletion(_ edit: MacListEditing.Edit, original: NSAttributedString, range: NSRange, name: String) {
            if let typing = edit.typing { commit(edit.text, selection: edit.selection, typing: typing, name: name); return }
            let quotes = MacBlockPrefix(original.attribute(.macBlock, at: range.location, effectiveRange: nil) as? String ?? "")?.quotes ?? ""
            let at = min(edit.selection.location, max(0, edit.text.length - 1))
            var typing = edit.selection.location < edit.text.length ? edit.text.attributes(at: at, effectiveRange: nil) : typingAttributes(block: edit.text.length > 0 ? quotes : "")
            if edit.selection.location == edit.text.length, edit.text.length > 0 {
                typing[.macLineEnding] = edit.text.attribute(.macLineEnding, at: edit.text.length - 1, effectiveRange: nil) ?? "\n"
            }
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature] { typing.removeValue(forKey: key) }
            commit(edit.text, selection: edit.selection, typing: typing, name: name)
        }
        @MainActor func copy(cut: Bool) async throws {
            guard let view, !pasting, !cut || parent.editable, !view.hasMarkedText() else { throw VaultFailure(message: "Finish text composition before copying or cutting.") }
            let range = view.selectedRange()
            guard range.length > 0 else { return }
            let token = loadToken, operation = MacClipboard.beginCopy(), board = NSPasteboard.general, count = board.changeCount
            let original = NSAttributedString(attributedString: view.attributedString()), baseline = lastMarkdown
            var listDeletion: MacListEditing.Outcome = .notList
            if cut, !source {
                if let edit = MacListEditing.clearingFinalTextBlock(original, range: range) { listDeletion = .changed(edit) }
                else { listDeletion = MacListEditing.deletingParagraph(original, range: range, cut: true) }
                switch listDeletion {
                case .notList, .unchanged:
                    listDeletion = MacListEditing.replacingSelection(original, range: range, replacement: NSAttributedString(string: ""), typing: view.typingAttributes)
                case .changed, .refused: break
                }
            }
            if case .refused(let issue) = listDeletion { throw VaultFailure(message: issue ?? "This list selection cannot be cut without changing its structure.") }
            let grid = source ? nil : MacTableClipboard.selection(original, range: range, root: parent.root, path: parent.path, images: parent.images)
            let rich = source ? nil : grid?.rich ?? MacClipboard.selection(original, range: range)
            let markdown = rich.map(MacMarkdown.markdown) ?? (view.string as NSString).substring(with: range)
            pasting = true; view.isEditable = false; parent.onPasteBusy(true)
            defer { pasting = false; parent.onPasteBusy(false); if self.view === view { updateInteraction() } }
            let fragment: NativeClipboardFragment
            if let project = parent.project { fragment = try await project.fragment(markdown) }
            else if let root = parent.root { fragment = try await VaultFiles(root: root).clipboardFragment(markdown, notePath: parent.path) }
            else { fragment = .init(markdown: markdown) }
            try Task.checkCancellation()
            guard fragment.includesLocalResources else { throw VaultFailure(message: "A selected attachment is unavailable. The selection and clipboard are unchanged. Locate its file or select only the text before copying.") }
            let item = try MacClipboard.item(fragment, rich: rich)
            if let grid { item.setString(grid.tsv, forType: .tabularText); item.setString(grid.tsv, forType: .string) }
            guard !cut || parent.editable, loadToken == token, self.view === view, baseline == lastMarkdown, range == view.selectedRange(), MacClipboard.currentCopy(operation), board.changeCount == count else { throw VaultFailure(message: "The note, selection or clipboard changed while copying. Copy the selection again; your writing is unchanged.") }
            board.clearContents()
            guard board.writeObjects([item]) else { throw VaultFailure(message: "The clipboard could not be written. Your selection is unchanged.") }
            if cut {
                if case .changed(let edit) = listDeletion { commitListDeletion(edit, original: original, range: range, name: "Cut") }
                else {
                    let next = MacRichTable.replacing(original, range: range, with: NSAttributedString(string: ""))
                    commit(next, selection: NSRange(location: range.location, length: 0), name: "Cut")
                }
            }
        }
        @MainActor func handlePaste(plain: Bool) {
            guard parent.editable, !pasting else { return }
            do {
                let board = NSPasteboard.general
                guard let payload = try MacClipboard.payload(board, plain: plain || (source || codeAtCaret() != nil) && board.string(forType: .string) != nil) else { NSSound.beep(); return }
                clipboardTask = Task { [weak self] in
                    do { try await self?.paste(payload) } catch is CancellationError {} catch { self?.parent.onPasteError(error.localizedDescription) }
                }
            } catch { parent.onPasteError(error.localizedDescription) }
        }
        @MainActor func paste(_ payload: MacClipboard.Payload, localReferencesAllowed: Bool = false, undoName: String = "Paste") async throws {
            guard let view, parent.editable, !pasting, !view.hasMarkedText() else { throw VaultFailure(message: "Finish text composition before pasting.") }
            let token = loadToken, original = NSAttributedString(attributedString: view.attributedString()), range = view.selectedRange(), baseline = lastMarkdown
            pasting = true; view.isEditable = false; parent.onPasteBusy(true)
            defer {
                pasting = false; parent.onPasteBusy(false)
                if self.view === view {
                    updateInteraction()
                    // Paste may introduce another occurrence of a loaded image,
                    // or finish after its download was deferred while busy.
                    refreshImages(force: true); scheduleRemoteImages()
                }
            }
            let fragment: NativeClipboardFragment?
            let plain: String?
            let html: Bool
            if case .html = payload { html = true } else { html = false }
            switch payload {
            case .plain(let text): fragment = nil; plain = text
            case .fragment(let value): fragment = value; plain = nil
            case .html(let bytes, let attachments): fragment = try await NativeHTMLClipboard.fragment(bytes, attachments: attachments); plain = nil
            }
            try Task.checkCancellation()
            guard parent.editable, loadToken == token, self.view === view, lastMarkdown == baseline, view.selectedRange() == range else { throw VaultFailure(message: "The note or insertion point changed. Paste again at the new position.") }
            var markdown: String?
            if let fragment {
                try fragment.validate()
                guard source || localReferencesAllowed || fragment.includesLocalResources else { throw VaultFailure(message: "Copied local resources were not included. Paste into Markdown source to retain those references, or copy their files too.") }
                if !fragment.resources.isEmpty, !source {
                    // Resource references render as atomic placeholders here;
                    // reject a deterministic list edit before writing any files.
                    let preview = normalizedPasteMarkdown(fragment.markdown, html: html)
                    let insertion = MacClipboard.insertion(MacMarkdown.render(preview, path: parent.path), into: original, range: range)
                    _ = try inlinePastePlan(insertion, formatted: true, original: original, range: range, typing: view.typingAttributes, markdown: preview)
                }
                if fragment.resources.isEmpty { markdown = fragment.markdown }
                else if let project = parent.project {
                    let portable = NativeClipboardFragment(markdown: fragment.markdown, vault: fragment.vault, resources: fragment.resources.map { .init(reference: $0.reference, path: $0.path, name: MacClipboard.importName($0.name), bytes: $0.bytes) })
                    markdown = try await project.importFragment(portable)
                }
                else {
                    guard let root = parent.root else { throw VaultFailure(message: "Choose this file’s project folder before adding images, or paste into a vault note. Your text is unchanged.") }
                    markdown = try await VaultFiles(root: root).importClipboard(fragment)
                }
            }
            try Task.checkCancellation()
            guard parent.editable, loadToken == token, self.view === view, lastMarkdown == baseline, view.selectedRange() == range else { throw VaultFailure(message: "The note or insertion point changed. Paste again at the new position.") }
            if let pasted = markdown { markdown = normalizedPasteMarkdown(pasted, html: html) }
            if !source, let markdown, !MacMarkdown.requiresLosslessSource(markdown), let table = MacTableClipboard.table(markdown),
               let (output, selection) = try MacTableClipboard.pasting(table, into: original, range: range, root: parent.root, path: parent.path, images: parent.images) {
                commit(output, selection: selection, name: "Paste table cells"); return
            }
            let output = NSMutableAttributedString(attributedString: original)
            var nextSource = source
            let insertion: NSAttributedString
            if let code = codeAtCaret() {
                let rendered = MacMarkdown.render(markdown ?? "")
                insertion = NSAttributedString(string: plain ?? MacRichCode.literalBody(rendered), attributes: MacRichCode.attributes(code))
            }
            else if source { insertion = NSAttributedString(string: markdown ?? plain ?? "", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor]) }
            else if let markdown {
                insertion = MacClipboard.insertion(MacMarkdown.render(markdown, root: parent.root, path: parent.path, images: parent.images), into: original, range: range)
            } else {
                var attributes = view.typingAttributes
                for key in [NSAttributedString.Key.macOriginal, .macSignature, .macLiteral, .attachment, .macListBreak, .macHardBreak] { attributes.removeValue(forKey: key) }
                insertion = NSAttributedString(string: plain ?? "", attributes: attributes)
            }
            let cell = cellAtCaret()
            let cellInsertion = cell.map { MacRichTable.insertion(insertion, cell: $0) } ?? insertion
            let plan = try inlinePastePlan(cellInsertion, formatted: markdown != nil, original: original, range: range, typing: view.typingAttributes, markdown: markdown)
            let checked = plan.edit
            let pasted = checked?.text ?? MacRichTable.replacing(original, range: range, with: plan.insertion)
            output.setAttributedString(pasted)
            var result: NSAttributedString = output
            var cursor = checked?.selection.location ?? (range.location + plan.insertion.length)
            if !source, MacMarkdown.requiresSource(MacMarkdown.markdown(output)) {
                let before = MacMarkdown.markdown(output.attributedSubstring(from: NSRange(location: 0, length: cursor)))
                let full = parent.sourceHeader + MacMarkdown.markdown(output)
                nextSource = true; cursor = (parent.sourceHeader as NSString).length + (before as NSString).length
                result = NSAttributedString(string: full, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor])
            }
            var typing = checked?.typing ?? typingAttributes(block: "")
            if plan.inline, !nextSource, result.length > 0 {
                let paragraph = (result.string as NSString).paragraphRange(for: NSRange(location: min(cursor, result.length - 1), length: 0))
                let actual = result.attributes(at: paragraph.location, effectiveRange: nil)
                if checked == nil { typing[.font] = MacMarkdown.font(actual[.macBlock] as? String ?? "") }
                for key in [NSAttributedString.Key.macBlock, .macListContext, .macIndependentParagraph, .paragraphStyle] { typing[key] = actual[key] }
            }
            commit(result, selection: NSRange(location: min(cursor, result.length), length: 0), typing: nextSource ? [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)] : typing, name: undoName, asSource: nextSource)
        }
        @MainActor private func normalizedPasteMarkdown(_ value: String, html: Bool) -> String {
            var result = value, inlineHTML = false
            if html {
                let document = Document(parsing: value)
                let onlyBreak = (document.child(at: 0) as? HTMLBlock).map {
                    $0.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"(?i)^<br\s*/?>$"#, options: .regularExpression) != nil
                } ?? false
                let paragraph = document.child(at: 0) as? Paragraph
                let emptyMarker = paragraph.map { MacMarkdown.isEmptyParagraphMarker($0) } ?? false
                inlineHTML = document.childCount == 1 && (paragraph != nil && !emptyMarker || onlyBreak)
                if document.childCount == 1, onlyBreak, !source, cellAtCaret() == nil, codeAtCaret() == nil, let view {
                    let original = view.attributedString(), raw = original.string as NSString, selection = view.selectedRange()
                    if raw.length == 0 { result = MacMarkdown.emptyParagraphMarker + "\n"; inlineHTML = false }
                    else {
                        let row = raw.paragraphRange(for: NSRange(location: min(selection.location, raw.length - 1), length: 0))
                        let block = original.attribute(.macBlock, at: row.location, effectiveRange: nil) as? String ?? ""
                        if block.isEmpty, original.attribute(.macListContext, at: row.location, effectiveRange: nil) == nil, NSMaxRange(selection) <= NSMaxRange(row) {
                            let remaining = NSMutableString(string: raw.substring(with: row))
                            remaining.replaceCharacters(in: NSRange(location: selection.location - row.location, length: selection.length), with: "")
                            if (remaining as String).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result = MacMarkdown.emptyParagraphMarker + "\n"; inlineHTML = false }
                        }
                    }
                }
            }
            if !source, !parent.codeBlocks { result = MacClipboard.withoutCodeBlocks(result) }
            // Keep selected native endings and source-mode HTML terminators.
            if !source, inlineHTML, result.hasSuffix("\n") { result.removeLast() }
            return result
        }
        @MainActor private func inlinePastePlan(_ insertion: NSAttributedString, formatted: Bool, original: NSAttributedString, range: NSRange, typing: [NSAttributedString.Key: Any], markdown: String? = nil) throws -> (edit: MacListEditing.Edit?, inline: Bool, insertion: NSAttributedString) {
            if !source, MacRichCode.at(original, range.location) != nil || MacRichTable.at(original, range.location) != nil {
                switch MacListEditing.replacingCardSelection(original, range: range, replacement: insertion, typing: typing) {
                case .changed(let edit): return (edit, true, insertion)
                case .refused(let issue): throw VaultFailure(message: issue ?? "This paste cannot preserve its card boundaries.")
                case .notList, .unchanged: break
                }
            }
            guard !source, cellAtCaret() == nil, codeAtCaret() == nil else { return (nil, false, insertion) }
            if let markdown {
                if let structure = MacMarkdown.pasteStructure(markdown, root: parent.root, path: parent.path, images: parent.images), original.length > 0, range.location < original.length || range.location == original.length && !original.string.hasSuffix("\n") {
                    let row = (original.string as NSString).paragraphRange(for: NSRange(location: min(range.location, original.length - 1), length: 0))
                    let ending = original.attribute(.macLineEnding, at: NSMaxRange(row) - 1, effectiveRange: nil) as? String ?? "\n"
                    let normalized = structure.middle.replacingOccurrences(of: "\n", with: ending)
                    let blocks = MacMarkdown.render(normalized, root: parent.root, path: parent.path, images: parent.images)
                    switch MacListEditing.pastingBlocks(original, range: range, blocks: blocks, firstBody: structure.first, lastBody: structure.last, typing: typing) {
                    case .changed(let edit): return (edit, false, insertion)
                    case .refused: throw VaultFailure(message: "This paste needs Markdown source editing to preserve its block boundaries.")
                    case .notList, .unchanged: break
                    }
                }
            }
            if let markdown, let paragraphs = MacMarkdown.pasteParagraphs(markdown, root: parent.root, path: parent.path, images: parent.images) {
                switch MacListEditing.pastingParagraphs(original, range: range, paragraphs: paragraphs, typing: typing) {
                case .changed(let edit): return (edit, false, insertion)
                case .refused: throw VaultFailure(message: "This paste needs Markdown source editing to preserve its paragraph boundaries.")
                case .notList, .unchanged: break
                }
            }
            let receivingRow = original.length > 0 && (range.location < original.length || range.location == original.length && !original.string.hasSuffix("\n")) ? (original.string as NSString).paragraphRange(for: NSRange(location: min(range.location, original.length - 1), length: 0)) : nil
            let wholeRow = receivingRow == range
            var inlineInsertion = insertion
            if wholeRow, let markdown,
               let bodies = MacMarkdown.pasteParagraphs(markdown, root: parent.root, path: parent.path, images: parent.images, minimumCount: 1),
               bodies.count == 1, !bodies[0].empty {
                inlineInsertion = bodies[0].text
            }
            var replacementRange = range
            if wholeRow, let row = receivingRow {
                let block = original.attribute(.macBlock, at: row.location, effectiveRange: nil) as? String ?? ""
                let prefix = MacMarkdown.displayPrefix(block).utf16.count
                let terminated = (original.string as NSString).character(at: NSMaxRange(row) - 1) == 10
                replacementRange = NSRange(location: row.location + prefix, length: max(0, row.length - prefix - (terminated ? 1 : 0)))
            }
            // A plain-text newline and an explicit inline hard break remain
            // inside the receiving item. Physical paragraph separators belong
            // to structured paste and must keep its separate insertion path.
            let candidate = NSMutableAttributedString(attributedString: inlineInsertion)
            let endings = try! NSRegularExpression(pattern: "\\r\\n|[\\r\\n]").matches(in: inlineInsertion.string, range: NSRange(location: 0, length: inlineInsertion.length))
            for match in endings.reversed() {
                if formatted, inlineInsertion.attribute(.macHardBreak, at: match.range.location, effectiveRange: nil) as? Bool != true { return (nil, false, insertion) }
                candidate.replaceCharacters(in: match.range, with: "\u{2028}")
                candidate.addAttribute(.macListBreak, value: 1, range: NSRange(location: match.range.location, length: 1))
            }
            guard candidate.string.rangeOfCharacter(from: CharacterSet.newlines.subtracting(CharacterSet(charactersIn: "\u{2028}"))) == nil else { return (nil, false, insertion) }
            // Markdown hard breaks cannot represent empty first/last logical
            // lines or consecutive breaks without changing paragraph structure.
            // Keep those visible lines as explicit inline HTML breaks instead.
            let paragraph = original.length > 0 ? (original.string as NSString).paragraphRange(for: NSRange(location: min(range.location, original.length - 1), length: 0)) : nil
            let atEmptyEnd = range.location == original.length && original.string.hasSuffix("\n")
            let heading = paragraph.map { !atEmptyEnd && MacBlockPrefix(original.attribute(.macBlock, at: $0.location, effectiveRange: nil) as? String ?? "")?.heading == true } ?? false
            let explicitBreaks = heading || candidate.string.hasPrefix("\u{2028}") || candidate.string.hasSuffix("\u{2028}") || candidate.string.contains("\u{2028}\u{2028}")
            if !candidate.string.isEmpty, candidate.string.unicodeScalars.allSatisfy({ $0.value == 0x2028 }) {
                for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature] { candidate.removeAttribute(key, range: NSRange(location: 0, length: candidate.length)) }
            }
            if explicitBreaks {
                let raw = candidate.string as NSString
                for location in 0..<raw.length where raw.character(at: location) == 0x2028 {
                    candidate.addAttribute(.macListBreak, value: 3, range: NSRange(location: location, length: 1))
                }
            }
            if let paragraph {
                let rawOriginal = original.string as NSString
                let terminated = rawOriginal.character(at: NSMaxRange(paragraph) - 1) == 10
                let endingOffset = !terminated && paragraph.location > 0 ? paragraph.location - 1 : NSMaxRange(paragraph) - 1
                let ending = original.attribute(.macLineEnding, at: endingOffset, effectiveRange: nil) as? String ?? "\n"
                let raw = candidate.string as NSString
                for location in 0..<raw.length where raw.character(at: location) == 0x2028 {
                    candidate.addAttribute(.macLineEnding, value: ending, range: NSRange(location: location, length: 1))
                }
            }
            var block = false
            if formatted {
                inlineInsertion.enumerateAttributes(in: NSRange(location: 0, length: inlineInsertion.length)) { attrs, _, stop in
                    if attrs[.macCode] != nil || attrs[.macTable] != nil || !(attrs[.macBlock] as? String ?? "").isEmpty { block = true; stop.pointee = true }
                }
            }
            guard !block else { return (nil, false, insertion) }
            // Inline payloads inherit the receiving paragraph's ownership even
            // when they replace its first character. Inline styles stay local.
            var inheritedTyping = typing
            if let row = receivingRow, NSMaxRange(replacementRange) <= NSMaxRange(row) {
                let attrs = original.attributes(at: row.location, effectiveRange: nil)
                let source = attrs[.macBlock] as? String ?? ""
                let all = NSRange(location: 0, length: candidate.length)
                candidate.enumerateAttributes(in: all) { local, part, _ in
                    let old = local[.macBlock] as? String ?? ""
                    let font = local[.font] as? NSFont ?? MacMarkdown.font(old)
                    let traits = NSFontManager.shared.traits(of: font), bold = MacMarkdown.inlineBold(local, block: old)
                    candidate.addAttributes([.font: MacMarkdown.inlineFont(block: source, bold: bold, italic: traits.contains(.italicFontMask), code: traits.contains(.fixedPitchFontMask)), .macStrong: bold], range: part)
                }
                for key in [NSAttributedString.Key.macBlock, .macListContext, .macIndependentParagraph, .paragraphStyle] {
                    candidate.removeAttribute(key, range: all)
                    if let value = attrs[key] { candidate.addAttribute(key, value: value, range: all) }
                    inheritedTyping[key] = attrs[key]
                }
                inheritedTyping[.font] = MacMarkdown.font(source)
            }
            switch MacListEditing.replacingSelection(original, range: replacementRange, replacement: candidate, typing: inheritedTyping) {
            case .changed(let edit): return (edit, true, candidate)
            case .refused(let message): throw VaultFailure(message: message ?? "This paste needs Markdown source editing to preserve its list items.")
            case .notList, .unchanged:
                if replacementRange != range {
                    let output = NSMutableAttributedString(attributedString: original)
                    output.replaceCharacters(in: replacementRange, with: candidate)
                    return (MacListEditing.Edit(text: output, selection: NSRange(location: replacementRange.location + candidate.length, length: 0), typing: inheritedTyping), true, candidate)
                }
                return (nil, true, candidate)
            }
        }
        private func blockPrefix(for action: String) -> String {
            if let index = ["h1", "h2", "h3", "h4", "h5", "h6"].firstIndex(of: action) {
                return String(repeating: "#", count: index + 1) + " "
            }
            switch action {
            case "quote": return "> "
            case "bullet": return "- "
            case "ordered": return "1. "
            case "checklist": return "- [ ] "
            default: return ""
            }
        }
        private func typingAttributes(block: String) -> [NSAttributedString.Key: Any] {
            [.font: MacMarkdown.font(block), .foregroundColor: NSColor.labelColor, .macBlock: block, .macIndependentParagraph: MacBlockPrefix(block)?.list != true, .macStrong: false, .paragraphStyle: MacMarkdown.paragraphStyle(block)]
        }
        private func commit(_ value: NSAttributedString, selection: NSRange, typing: [NSAttributedString.Key: Any]? = nil, name: String, asSource: Bool? = nil) {
            guard active, parent.isCurrent() else { return }
            guard let view else { return }; linkCompletion.hide()
            typingAfterBlockFormat = false
            view.breakUndoCoalescing()
            // Each completed editor command gets its own undo event, even when
            // two asynchronous paste operations finish in the same run-loop turn.
            if !editorUndo.isUndoing, !editorUndo.isRedoing, editorUndo.groupingLevel == 1 { editorUndo.endUndoGrouping(); editorUndo.beginUndoGrouping() }
            let before = NSAttributedString(attributedString: view.attributedString()), previousSelection = view.selectedRange(), previousTyping = view.typingAttributes, previousSource = source
            view.undoManager?.registerUndo(withTarget: self) { target in target.restore(before, selection: previousSelection, typing: previousTyping, asSource: previousSource) }
            view.undoManager?.setActionName(name)
            loading = true
            if let asSource { source = asSource; view.isRichText = !asSource; parent.onSourceChange(asSource) }
            let contextual = asSource == true ? value : MacMarkdown.refreshingListGapOwners(MacMarkdown.refreshingListContexts(value))
            let ordered = asSource == true ? nil : MacMarkdown.normalizingOrderedLists(contextual)
            let prepared = ordered?.text ?? contextual, mapped = ordered?.selection(selection) ?? selection
            view.textStorage?.setAttributedString(prepared); view.setSelectedRange(mapped)
            if var typing {
                if ordered != nil, prepared.length > 0 {
                    let attrs = prepared.attributes(at: min(mapped.location, prepared.length - 1), effectiveRange: nil)
                    for key in [NSAttributedString.Key.macBlock, .macListContext, .paragraphStyle] { typing[key] = attrs[key] }
                }
                view.typingAttributes = typing
            }
            applyTheme(theme, force: true)
            loading = false; publish(); scheduleRemoteImages()
        }
        private func applyTypedShortcut(_ view: NSTextView) {
            guard cellAtCaret() == nil else { return }
            guard view.selectedRange().length == 0, !view.string.isEmpty else { return }
            let cursor = view.selectedRange().location, raw = view.string as NSString
            let paragraph = raw.paragraphRange(for: NSRange(location: max(0, cursor - 1), length: 0))
            let value = raw.substring(with: paragraph).trimmingCharacters(in: .newlines)
            guard cursor == paragraph.location + (value as NSString).length else { return }
            let previousAttributes = view.attributedString().attributes(at: min(paragraph.location, raw.length - 1), effectiveRange: nil)
            // Block shortcuts target flat list text. Text inside an owned
            // heading, quote or explicit paragraph must not replace its item.
            if let context = previousAttributes[.macListContext] as? MacListContext,
               !context.suffix.isEmpty || context.blockParagraph { return }
            let currentBlock = previousAttributes[.macBlock] as? String ?? ""
            if MacBlockPrefix(currentBlock)?.list != true, MacBlockPrefix(currentBlock)?.heading != true,
               value.hasSuffix(" "), value.range(of: #"^(---|\*\*\*|___) $"#, options: .regularExpression) != nil {
                let original = view.attributedString(), output = NSMutableAttributedString(attributedString: original)
                let attrs = original.attributes(at: paragraph.location, effectiveRange: nil)
                let quotes = MacBlockPrefix(currentBlock)?.quotes ?? ""
                let ending = attrs[.macLineEnding] as? String ?? "\n"
                let replacement = NSMutableAttributedString(attributedString: MacHorizontalRule.render(quotes + String(value.dropLast()), ending: ending))
                var typing = typingAttributes(block: quotes); typing[.macLineEnding] = ending
                let caret = paragraph.location + replacement.length
                replacement.append(NSAttributedString(string: NSMaxRange(paragraph) < original.length ? "\n\n" : "\n", attributes: typing))
                output.replaceCharacters(in: paragraph, with: replacement)
                commit(output, selection: NSRange(location: caret, length: 0), typing: typing, name: "Insert horizontal rule")
                return
            }
            var block: String?
            if currentBlock.isEmpty, let prefix = MacBlockPrefix(value, inheritedQuoteIndentation: false), prefix.source == value { block = value }
            else if let current = MacBlockPrefix(currentBlock), !current.list, !current.heading, let prefix = MacBlockPrefix(value, inheritedQuoteIndentation: false), prefix.source == value { block = currentBlock + value }
            else if let current = MacBlockPrefix(currentBlock), current.list, !current.checklist, value == current.display + "[ ] " || value == current.display + "[x] " || value == current.display + "[X] " { block = current.replacingMarker(current.marker + (value.contains("[ ]") ? "[ ] " : "[x] ")) }
            guard let block else { return }
            var typing = typingAttributes(block: block)
            let hasNewline = raw.substring(with: paragraph).hasSuffix("\n")
            let endingAttributes = hasNewline ? view.attributedString().attributes(at: NSMaxRange(paragraph) - 1, effectiveRange: nil) : previousAttributes
            typing[.macLineEnding] = endingAttributes[.macLineEnding] ?? "\n"
            if MacBlockPrefix(block)?.list == true {
                let previous = previousAttributes[.macListContext] as? MacListContext
                let context = MacListContext(id: previous?.continuation == false ? previous!.id : UUID(), source: block, quoteParents: previous?.quoteParents ?? [])
                typing[.macListContext] = context
            }
            // This shortcut contains only a source prefix. Build its empty body
            // directly: parsing a quoted, empty checkbox trims marker whitespace
            // and can mistake the checkbox syntax for literal body text.
            let replacement = NSAttributedString(string: MacMarkdown.displayPrefix(block) + (hasNewline ? "\n" : ""), attributes: typing)
            let rich = NSMutableAttributedString(attributedString: view.attributedString()); rich.replaceCharacters(in: paragraph, with: replacement)
            commit(rich, selection: NSRange(location: paragraph.location + (MacMarkdown.displayPrefix(block) as NSString).length, length: 0), typing: typing, name: "Markdown shortcut")
        }
        private func applyInlineShortcut(_ view: NSTextView) {
            defer { typedCharacter = nil }
            guard let typedCharacter, ["*", "_", "`", ")", ">"].contains(typedCharacter), view.selectedRange().length == 0 else { return }
            let cursor = view.selectedRange().location, raw = view.string as NSString
            guard cursor > 0 else { return }
            let line = raw.paragraphRange(for: NSRange(location: cursor - 1, length: 0))
            let value = raw.substring(with: NSRange(location: line.location, length: cursor - line.location))
            let document = Document(parsing: value)
            guard let paragraph = document.child(at: 0) as? Paragraph, paragraph.childCount > 0, let node = paragraph.child(at: paragraph.childCount - 1),
                  node is Strong || node is Emphasis || node is InlineCode || node is Markdown.Link,
                  let range = node.range, range.lowerBound.line == 1, range.upperBound.column == value.utf8.count + 1 else { return }
            let byteOffset = range.lowerBound.column - 1, bytes = Array(value.utf8)
            let candidate = String(decoding: bytes.dropFirst(byteOffset), as: UTF8.self)
            if let marker = candidate.first, marker == "*" || marker == "_" {
                if byteOffset > 0, bytes[byteOffset - 1] == marker.asciiValue { return }
                if candidate.prefix(while: { $0 == marker }).count != candidate.reversed().prefix(while: { $0 == marker }).count { return }
            }
            let prefix = String(decoding: bytes.prefix(byteOffset), as: UTF8.self)
            let affected = NSRange(location: line.location + (prefix as NSString).length, length: (candidate as NSString).length)
            let inherited = view.attributedString().attributes(at: affected.location, effectiveRange: nil)
            guard inherited[.macLiteral] == nil, inherited[.link] == nil else { return }
            let block = inherited[.macBlock] as? String ?? "", inheritedFont = inherited[.font] as? NSFont ?? MacMarkdown.font(block), inheritedTraits = NSFontManager.shared.traits(of: inheritedFont)
            guard !inheritedTraits.contains(.fixedPitchFontMask) else { return }
            let rendered = NSMutableAttributedString(attributedString: MacMarkdown.render(candidate))
            guard rendered.string != candidate else { return }
            rendered.enumerateAttributes(in: NSRange(location: 0, length: rendered.length)) { attrs, range, _ in
                let font = attrs[.font] as? NSFont ?? MacMarkdown.font(""), traits = NSFontManager.shared.traits(of: font)
                let bold = MacMarkdown.inlineBold(inherited, block: block) || MacMarkdown.inlineBold(attrs, block: "")
                rendered.addAttributes([.macBlock: block, .macStrong: bold, .font: MacMarkdown.inlineFont(block: block, bold: bold, italic: traits.contains(.italicFontMask) || inheritedTraits.contains(.italicFontMask), code: traits.contains(.fixedPitchFontMask))], range: range)
                for key in [NSAttributedString.Key.macTable, .macCell, .macListContext, .macLineEnding, .underlineStyle] { if let value = inherited[key] { rendered.addAttribute(key, value: value, range: range) } }
                if let style = inherited[.paragraphStyle] { rendered.addAttribute(.paragraphStyle, value: style, range: range) }
                rendered.removeAttribute(.macOriginal, range: range); rendered.removeAttribute(.macSignature, range: range)
            }
            let rich = NSMutableAttributedString(attributedString: view.attributedString()); rich.replaceCharacters(in: affected, with: rendered)
            commit(rich, selection: NSRange(location: affected.location + rendered.length, length: 0), typing: view.typingAttributes, name: "Markdown formatting")
        }
        private func admittingNativeTyping(_ textView: NSTextView) -> Bool {
            if typingAfterBlockFormat, !loading, !pasting, textView.isEditable, !editorUndo.isUndoing, !editorUndo.isRedoing {
                typingAfterBlockFormat = false
                if !textView.hasMarkedText() {
                    textView.breakUndoCoalescing()
                    if editorUndo.groupingLevel == 1 { editorUndo.endUndoGrouping(); editorUndo.beginUndoGrouping() }
                }
            }
            return true
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard active, parent.isCurrent() else { return false }
            if !loading { parent.onEditingIntent() }
            if selectionComposition != nil { return admittingNativeTyping(textView) }
            if !source, parent.editable, !pasting, !textView.hasMarkedText(), replacementString == "", affectedCharRange.length == 1,
               textView.selectedRange().length == 0, textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true {
                let original = textView.attributedString(), raw = original.string as NSString
                if affectedCharRange.location < raw.length, raw.character(at: affectedCharRange.location) == 10 {
                    let rows = [raw.paragraphRange(for: affectedCharRange)] + (NSMaxRange(affectedCharRange) < raw.length ? [raw.paragraphRange(for: NSRange(location: NSMaxRange(affectedCharRange), length: 0))] : [])
                    if let row = rows.first(where: { original.attribute(.macRule, at: $0.location, effectiveRange: nil) != nil }),
                       let edit = MacHorizontalRule.removingOwnedRule(original, range: row) {
                        let old = textView.selectedRange().location
                        let caret = old >= NSMaxRange(row) ? old - row.length : min(old, row.location)
                        commitListDeletion(MacListEditing.Edit(text: edit.text, selection: NSRange(location: max(0, caret), length: 0), typing: edit.typing), original: original, range: textView.selectedRange(), name: "Remove horizontal rule")
                        return false
                    }
                }
            }
            var ruleReturn: MacListEditing.Edit?
            var ruleReturnChild: UUID?
            var cardReturn: MacListEditing.Edit?
            if !source, parent.editable, !pasting, !textView.hasMarkedText(), replacementString == "\n",
               textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true,
               let selected = MacHorizontalRule.selectedReturn(textView.attributedString(), range: affectedCharRange) {
                switch selected {
                case .splitItem(let edit): ruleReturn = edit
                case .completed(let edit):
                    commit(edit.text, selection: edit.selection, typing: edit.typing, name: "Continue after horizontal rule")
                    return false
                }
            }
            if ruleReturn == nil, !source, parent.editable, !pasting, !textView.hasMarkedText(), textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true, let replacementString {
                switch MacListEditing.replacingCardSelection(textView.attributedString(), range: affectedCharRange, replacement: NSAttributedString(string: replacementString, attributes: textView.typingAttributes), typing: textView.typingAttributes) {
                case .changed(let edit): commit(edit.text, selection: edit.selection, typing: edit.typing, name: replacementString.isEmpty ? "Delete selection" : "Typing"); return false
                case .refused(let issue): if let issue { parent.onPasteError(issue) } else { NSSound.beep() }; return false
                case .notList, .unchanged:
                    if replacementString == "\n" {
                        switch MacListEditing.replacingCardSelection(textView.attributedString(), range: affectedCharRange, replacement: NSAttributedString(), typing: textView.typingAttributes) {
                        case .changed(let edit): cardReturn = edit
                        case .refused(let issue): if let issue { parent.onPasteError(issue) } else { NSSound.beep() }; return false
                        case .notList, .unchanged: break
                        }
                    }
                }
            }
            if !source, cardReturn == nil, let replacementString {
                let rich = textView.attributedString()
                var touchesTable = MacRichTable.at(rich, affectedCharRange.location) != nil
                if affectedCharRange.length > 0 { rich.enumerateAttribute(.macTable, in: affectedCharRange) { value, _, stop in if value != nil { touchesTable = true; stop.pointee = true } } }
                // A complete table between two prose/list endpoints belongs
                // to the checked list-selection transaction below. Cell edits
                // and partial table selections retain their table semantics.
                if touchesTable, parent.editable, !pasting, !textView.hasMarkedText(),
                   textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true, affectedCharRange.length > 0,
                   MacRichTable.at(rich, affectedCharRange.location) == nil,
                   MacRichTable.at(rich, NSMaxRange(affectedCharRange)) == nil {
                    var list = false, complete = true
                    rich.enumerateAttribute(.macListContext, in: affectedCharRange) { value, _, _ in if value != nil { list = true } }
                    rich.enumerateAttribute(.macTable, in: affectedCharRange) { value, part, _ in
                        guard value != nil else { return }
                        var token = NSRange()
                        _ = rich.attribute(.macTable, at: part.location, longestEffectiveRange: &token, in: NSRange(location: 0, length: rich.length))
                        if NSIntersectionRange(affectedCharRange, token) != token { complete = false }
                    }
                    if list && complete { touchesTable = false }
                }
                if touchesTable {
                    let cell = MacRichTable.at(rich, affectedCharRange.location)
                    if let cell {
                        var attrs = textView.typingAttributes
                        for key in [NSAttributedString.Key.macCellEnd, .macCellPlaceholder, .macOriginal, .macSignature] { attrs.removeValue(forKey: key) }
                        attrs[.macTable] = cell.table; attrs[.macCell] = cell; attrs[.paragraphStyle] = cell.attributes[.paragraphStyle]; attrs[.macBlock] = cell.table.quote?.prefix ?? ""
                        textView.typingAttributes = attrs
                    }
                    var range = affectedCharRange
                    let placeholder = [range.location, range.location - 1].first { $0 >= 0 && $0 < rich.length && rich.attribute(.macCellPlaceholder, at: $0, effectiveRange: nil) != nil && MacRichTable.at(rich, $0) === cell }
                    if range.length == 0, let placeholder { range = NSRange(location: placeholder, length: 1) }
                    var structural = range.length > 0 && placeholder != nil
                    if range.length > 0 { rich.enumerateAttribute(.macCellEnd, in: range) { value, _, stop in if value != nil { structural = true; stop.pointee = true } } }
                    if structural || replacementString.contains("\n") || replacementString.contains("\r") {
                        let plain = NSAttributedString(string: replacementString.replacingOccurrences(of: "\r\n", with: "\u{2028}").replacingOccurrences(of: "\n", with: "\u{2028}").replacingOccurrences(of: "\r", with: "\u{2028}"), attributes: textView.typingAttributes)
                        var insertion: NSAttributedString = cell.map { MacRichTable.insertion(plain, cell: $0) } ?? plain
                        if range.length > 0, let cell {
                            var tableRange = NSRange(); _ = rich.attribute(.macTable, at: range.location, longestEffectiveRange: &tableRange, in: NSRange(location: 0, length: rich.length))
                            if NSIntersectionRange(range, tableRange) == tableRange { insertion = NSAttributedString(string: replacementString, attributes: typingAttributes(block: "")); _ = cell }
                        }
                        let output = MacRichTable.replacing(rich, range: range, with: insertion)
                        commit(output, selection: NSRange(location: min(output.length, range.location + insertion.length), length: 0), name: replacementString.isEmpty ? "Clear table selection" : "Edit table cell")
                        return false
                    }
                }
            }
            if !source, parent.editable, !pasting, !textView.hasMarkedText(), replacementString == "",
               textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true,
               let length = textView.textStorage?.length, NSMaxRange(affectedCharRange) >= max(0, length - 1),
               let edit = MacListEditing.clearingFinalTextBlock(textView.attributedString(), range: affectedCharRange) {
                typedCharacter = nil
                commit(edit.text, selection: edit.selection, typing: edit.typing, name: "Typing")
                return false
            }
            if !source, parent.editable, !pasting, !textView.hasMarkedText(), textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true,
               replacementString == "", affectedCharRange.length == 1, NSMaxRange(affectedCharRange) == textView.selectedRange().location,
               let move = MacListEditing.innerBackspaceNavigation(in: textView.attributedString(), caret: textView.selectedRange()) {
                typedCharacter = nil
                textView.setSelectedRange(move.selection); textView.typingAttributes = move.typing
                updateWritingContext(); textView.scrollRangeToVisible(move.selection)
                return false
            }
            if !source, parent.editable, !pasting, !textView.hasMarkedText(), textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true, let replacementString {
                switch MacListEditing.editingBody(textView.attributedString(), range: affectedCharRange, replacement: NSAttributedString(string: replacementString, attributes: textView.typingAttributes), typing: textView.typingAttributes) {
                case .changed(let edit):
                    typedCharacter = nil
                    commit(edit.text, selection: edit.selection, typing: edit.typing, name: "Typing")
                    return false
                case .refused(let message):
                    typedCharacter = nil
                    if let message { parent.onPasteError(message) } else { NSSound.beep() }
                    return false
                case .notList, .unchanged: break
                }
            }
            if !source, replacementString == "", affectedCharRange.length > 0, !textView.hasMarkedText() {
                let original = textView.attributedString(), raw = textView.string as NSString
                if let edit = MacHorizontalRule.removingOwnedRule(original, range: affectedCharRange) {
                    commitListDeletion(edit, original: original, range: affectedCharRange, name: "Remove horizontal rule")
                    return false
                }
                if affectedCharRange.location < raw.length {
                    let paragraph = raw.paragraphRange(for: NSRange(location: affectedCharRange.location, length: 0))
                    let block = original.attribute(.macBlock, at: paragraph.location, effectiveRange: nil) as? String ?? ""
                    if let prefix = MacBlockPrefix(block), prefix.list, raw.substring(with: paragraph).hasPrefix(prefix.display) {
                        if affectedCharRange == paragraph {
                            switch MacListEditing.deletingParagraph(original, range: paragraph) {
                            case .changed(let edit): commitListDeletion(edit, original: original, range: paragraph, name: raw.substring(with: paragraph) == prefix.display ? "Lift list item" : "Remove list paragraph")
                            case .refused(let issue): if let issue { parent.onPasteError(issue) } else { NSSound.beep() }
                            case .notList, .unchanged: break
                            }
                            return false
                        }
                        let selected = textView.selectedRange(), body = paragraph.location + prefix.display.utf16.count
                        let backspace = selected.length == 0 && selected.location == body && NSMaxRange(affectedCharRange) == body
                        let markerSelected = selected == NSRange(location: paragraph.location, length: prefix.display.utf16.count) && affectedCharRange == selected
                        if backspace || markerSelected {
                            switch MacListEditing.backspaceLift(original, paragraph: paragraph) {
                            case .changed(let edit): commitListDeletion(edit, original: original, range: paragraph, name: "Lift list item")
                            case .refused(let issue): if let issue { parent.onPasteError(issue) } else { NSSound.beep() }
                            case .notList, .unchanged: break
                            }
                            return false
                        }
                    }
                }
            }
            if !source, affectedCharRange.length == 0, let replacementString, !replacementString.isEmpty, !textView.hasMarkedText() {
                let original = textView.attributedString(), raw = textView.string as NSString
                if raw.length > 0, affectedCharRange.location < raw.length || affectedCharRange.location == raw.length && !raw.hasSuffix("\n") {
                    let row = raw.paragraphRange(for: NSRange(location: min(affectedCharRange.location, raw.length - 1), length: 0))
                    if original.attribute(.macRule, at: row.location, effectiveRange: nil) != nil {
                        if replacementString == "\n", let prepared = MacHorizontalRule.preparingItemReturn(original, row: row, before: affectedCharRange.location == row.location) {
                            if prepared.completesReturn {
                                commit(prepared.edit.text, selection: prepared.edit.selection, typing: prepared.edit.typing, name: "Continue paragraph")
                                return false
                            }
                            ruleReturn = prepared.edit; ruleReturnChild = prepared.receivingChild
                        } else {
                        let output = NSMutableAttributedString(attributedString: original)
                        let attributes = original.attributes(at: row.location, effectiveRange: nil)
                        let typing = MacHorizontalRule.continuationAttributes(attributes)
                        // Root caret Return keeps the selected side of the rule.
                        // Item-owned boundaries retain their own split policy.
                        let before = affectedCharRange.location == row.location && (replacementString != "\n" || attributes[.macListContext] == nil)
                        let at = before ? row.location : NSMaxRange(row)
                        let terminated = raw.substring(with: row).hasSuffix("\n")
                        let prefix = before || terminated ? "" : "\n"
                        let inserted = prefix + (replacementString == "\n" ? "" : replacementString) + "\n"
                        output.insert(NSAttributedString(string: inserted, attributes: typing), at: at)
                        let caret = at + prefix.utf16.count + (replacementString == "\n" ? 0 : replacementString.utf16.count)
                        commit(output, selection: NSRange(location: caret, length: 0), typing: typing, name: before ? "Continue before horizontal rule" : "Continue after horizontal rule")
                        return false
                        }
                    }
                }
            }
            if !source, replacementString == "", affectedCharRange.length > 0 {
                let rich = textView.attributedString()
                if MacRichCode.at(rich, affectedCharRange.location) != nil {
                    var block = NSRange()
                    _ = rich.attribute(.macCode, at: affectedCharRange.location, longestEffectiveRange: &block, in: NSRange(location: 0, length: rich.length))
                    if block == affectedCharRange {
                        let updated = NSMutableAttributedString(attributedString: rich); updated.deleteCharacters(in: block)
                        commit(updated, selection: NSRange(location: block.location, length: 0), typing: typingAttributes(block: ""), name: "Remove code block")
                        return false
                    }
                }
                // A single Backspace/Delete keeps structural block boundaries intact.
                // Selecting the entire block removes it, including an emptied block.
                if affectedCharRange.length == 1 {
                    if affectedCharRange.location < rich.length, rich.attribute(.macCodeSeparator, at: affectedCharRange.location, effectiveRange: nil) != nil { return false }
                    if NSMaxRange(affectedCharRange) < rich.length, MacRichCode.at(rich, NSMaxRange(affectedCharRange)) != nil, MacRichCode.at(rich, affectedCharRange.location) == nil { return false }
                    let raw = rich.string as NSString
                    if !textView.hasMarkedText(), affectedCharRange.location < raw.length, raw.character(at: affectedCharRange.location) == 10 {
                        let current = raw.paragraphRange(for: affectedCharRange)
                        var rule: NSRange?
                        if rich.attribute(.macRule, at: current.location, effectiveRange: nil) != nil { rule = current }
                        else if NSMaxRange(affectedCharRange) < rich.length, rich.attribute(.macRule, at: NSMaxRange(affectedCharRange), effectiveRange: nil) != nil {
                            rule = raw.paragraphRange(for: NSRange(location: NSMaxRange(affectedCharRange), length: 0))
                        }
                        if let rule {
                            guard textView.selectedRange().length == 0 else { return false }
                            let attrs = MacHorizontalRule.continuationAttributes(rich.attributes(at: rule.location, effectiveRange: nil))
                            let previous = rule.location > 0 ? raw.paragraphRange(for: NSRange(location: rule.location - 1, length: 0)) : nil
                            let next = NSMaxRange(rule) < raw.length ? raw.paragraphRange(for: NSRange(location: NSMaxRange(rule), length: 0)) : nil
                            let separate = previous.map { !raw.substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } == true && next.map { !raw.substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } == true
                            let separator = separate ? "\n" : ""
                            let output = NSMutableAttributedString(attributedString: rich)
                            output.replaceCharacters(in: rule, with: NSAttributedString(string: separator, attributes: attrs))
                            let oldCaret = textView.selectedRange().location
                            let caret = oldCaret >= NSMaxRange(rule) ? oldCaret - rule.length + separator.utf16.count : oldCaret
                            commit(output, selection: NSRange(location: caret, length: 0), typing: textView.typingAttributes, name: "Remove horizontal rule")
                            return false
                        }
                    }
                }
            }
            if !source, let code = MacRichCode.at(textView.attributedString(), affectedCharRange.location), let replacementString {
                let rich = textView.attributedString()
                let attrs = MacListCardPlacement.inheriting(MacRichCode.attributes(code), from: rich.attributes(at: affectedCharRange.location, effectiveRange: nil))
                typedCharacter = nil; textView.typingAttributes = attrs
                if affectedCharRange.length == 0 {
                    let candidate = [affectedCharRange.location, affectedCharRange.location - 1].first { index in index >= 0 && index < rich.length && rich.attribute(.macCodePlaceholder, at: index, effectiveRange: nil) != nil }
                    if let candidate {
                        let updated = NSMutableAttributedString(attributedString: rich)
                        updated.replaceCharacters(in: NSRange(location: candidate, length: 1), with: NSAttributedString(string: replacementString, attributes: attrs))
                        commit(updated, selection: NSRange(location: candidate + replacementString.utf16.count, length: 0), typing: attrs, name: "Type in code")
                        return false
                    }
                }
                return admittingNativeTyping(textView)
            }
            if ruleReturn == nil, !source, parent.editable, !pasting, !textView.hasMarkedText(), textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true, let replacementString {
                switch MacListEditing.replacingSelection(textView.attributedString(), range: affectedCharRange, replacement: NSAttributedString(string: replacementString, attributes: textView.typingAttributes), typing: textView.typingAttributes) {
                case .changed(let edit):
                    typedCharacter = nil
                    commit(edit.text, selection: edit.selection, typing: edit.typing, name: replacementString.isEmpty && textView.selectedRange().length > 0 ? "Delete selection" : "Typing")
                    return false
                case .refused(let message):
                    typedCharacter = nil
                    if let message { parent.onPasteError(message) } else { NSSound.beep() }
                    return false
                case .notList, .unchanged: break
                }
            }
            typedCharacter = !source && affectedCharRange.length == 0 && replacementString?.count == 1 && !textView.hasMarkedText() ? replacementString : nil
            guard !source, replacementString == "\n", !textView.hasMarkedText() else { return admittingNativeTyping(textView) }
            var original = ruleReturn?.text ?? NSAttributedString(attributedString: textView.attributedString())
            var cursor = ruleReturn?.selection.location ?? affectedCharRange.location
            let selectedReturn = affectedCharRange.length > 0 && ruleReturn == nil
            var receivingTyping = ruleReturn?.typing ?? textView.typingAttributes
            if selectedReturn {
                switch MacListEditing.splittingSelectedInnerBlocks(original, range: affectedCharRange, typing: receivingTyping) {
                case .changed(let edit):
                    commit(edit.text, selection: edit.selection, typing: edit.typing, name: "Split inner paragraph")
                    return false
                case .refused(let issue):
                    if let issue { parent.onPasteError(issue) } else { NSSound.beep() }
                    return false
                case .notList, .unchanged: break
                }
                // Plan removal without publishing an intermediate document or
                // registering a second Undo event. Return then splits that plan.
                let planned = cardReturn.map(MacListEditing.Outcome.changed) ?? MacListEditing.replacingSelection(original, range: affectedCharRange, replacement: NSAttributedString(), typing: receivingTyping, forParagraphSplit: true)
                switch planned {
                case .changed(let edit):
                    original = edit.text; cursor = edit.selection.location
                    receivingTyping = edit.typing ?? receivingTyping
                case .refused(let message):
                    if let message { parent.onPasteError(message) } else { NSSound.beep() }
                    return false
                case .notList, .unchanged: return admittingNativeTyping(textView)
                }
            }
            var raw = original.string as NSString
            guard cursor <= raw.length else { return admittingNativeTyping(textView) }
            var paragraph = raw.paragraphRange(for: NSRange(location: cursor, length: 0))
            var mappedItems: [MacMarkdown.NativeListItem]?
            if paragraph.length > 0, let prefix = MacBlockPrefix(original.attribute(.macBlock, at: paragraph.location, effectiveRange: nil) as? String ?? ""), prefix.list,
               raw.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines) == prefix.display.trimmingCharacters(in: .whitespaces) {
                mappedItems = MacMarkdown.nativeListItems(in: original)
                if mappedItems == nil, let prepared = MacListEditing.prepareEmptyItemBoundary(original, paragraph: paragraph),
                   MacListEditing.hasOwnedContent(in: prepared.text, paragraph: prepared.paragraph, items: prepared.items) {
                    cursor += prepared.paragraph.location - paragraph.location
                    original = prepared.text; raw = original.string as NSString; paragraph = prepared.paragraph; mappedItems = prepared.items
                }
            }
            var attrs = paragraph.length > 0 ? original.attributes(at: paragraph.location, effectiveRange: nil) : receivingTyping
            let hasNewline = paragraph.length > 0 && raw.substring(with: paragraph).hasSuffix("\n")
            let endingIndex = hasNewline ? NSMaxRange(paragraph) - 1 : max(0, paragraph.location - 1)
            if endingIndex < original.length, let ending = original.attribute(.macLineEnding, at: endingIndex, effectiveRange: nil) { attrs[.macLineEnding] = ending }
            attrs.removeValue(forKey: .macUnterminated)
            let storedContext = attrs[.macListContext] as? MacListContext
            var context = storedContext
            if let stored = context, stored.continuation {
                var hasHead = false
                original.enumerateAttribute(.macListContext, in: NSRange(location: 0, length: paragraph.location)) { value, _, _ in
                    if let head = value as? MacListContext, !head.continuation, head.id == stored.id { hasHead = true }
                }
                if !hasHead { context = nil }
            }
            let block = context?.continuation == true ? context!.source : attrs[.macBlock] as? String ?? ""
            let marker = context?.continuation == true ? "" : MacMarkdown.displayPrefix(block)
            if let context {
                switch MacListEditing.splittingInnerBlock(original, paragraph: paragraph, cursor: cursor, context: context, ending: attrs[.macLineEnding] as? String ?? "\n") {
                case .changed(let edit):
                    commit(edit.text, selection: edit.selection, typing: edit.typing, name: "Split inner paragraph")
                    return false
                case .refused(let issue):
                    if let issue { parent.onPasteError(issue) } else { NSSound.beep() }
                    return false
                case .notList, .unchanged: break
                }
            }
            if parent.codeBlocks, block.isEmpty, cursor == NSMaxRange(paragraph) || cursor == NSMaxRange(paragraph) - 1 {
                let line = raw.substring(with: paragraph).trimmingCharacters(in: .newlines)
                if line.range(of: #"^```[A-Za-z0-9_+.-]*$"#, options: .regularExpression) != nil {
                    let ending = attrs[.macLineEnding] as? String ?? "\n"
                    let rawBlock = line + ending + ending + "```"
                    guard let code = FencedCode.blocks(in: rawBlock).first?.code else { return admittingNativeTyping(textView) }
                    let updated = NSMutableAttributedString(attributedString: original)
                    updated.replaceCharacters(in: paragraph, with: MacRichCode.render(code, ending: ending))
                    let token = MacRichCode.at(updated, paragraph.location)!
                    commit(updated, selection: NSRange(location: paragraph.location, length: 0), typing: MacRichCode.attributes(token), name: "Insert code block")
                    return false
                }
            }
            guard !block.isEmpty else {
                var typing = typingAttributes(block: "")
                typing[.macLineEnding] = attrs[.macLineEnding] ?? "\n"
                if let orphan = storedContext, orphan.continuation, context == nil {
                    let rich = NSMutableAttributedString(attributedString: original)
                    let right = NSRange(location: cursor, length: NSMaxRange(paragraph) - cursor)
                    rich.removeAttribute(.macListContext, range: right)
                    var newline = typing; newline[.macListContext] = orphan
                    rich.insert(NSAttributedString(string: "\n", attributes: newline), at: cursor)
                    commit(rich, selection: NSRange(location: cursor + 1, length: 0), typing: typing, name: "Split paragraph")
                    return false
                }
                if selectedReturn {
                    let rich = NSMutableAttributedString(attributedString: original)
                    rich.insert(NSAttributedString(string: "\n\n", attributes: typing), at: cursor)
                    commit(rich, selection: NSRange(location: cursor + 2, length: 0), typing: typing, name: "Split paragraph")
                    return false
                }
                textView.typingAttributes = typing
                return admittingNativeTyping(textView)
            }
            let line = raw.substring(with: paragraph).trimmingCharacters(in: .newlines)
            let rich = NSMutableAttributedString(attributedString: original)
            let blankHead = context?.continuation != true && line.trimmingCharacters(in: .whitespaces) == marker.trimmingCharacters(in: .whitespaces)
            let hasOwnedContent = blankHead && MacBlockPrefix(block)?.list == true && MacListEditing.hasOwnedContent(in: original, paragraph: paragraph, items: mappedItems)
            if blankHead, !hasOwnedContent, !marker.isEmpty || (MacBlockPrefix(block)?.depth ?? 0) > 0 {
                if MacBlockPrefix(block)?.list == true {
                    switch MacListEditing.lift(original, paragraph: paragraph) {
                    case .changed(let edit):
                        let at = min(edit.selection.location, max(0, edit.text.length - 1))
                        let nextAttrs = edit.text.length > 0 ? edit.text.attributes(at: at, effectiveRange: nil) : [:]
                        var typing = typingAttributes(block: nextAttrs[.macBlock] as? String ?? MacBlockPrefix(block)?.leavingEmpty ?? "")
                        typing[.macLineEnding] = nextAttrs[.macLineEnding] ?? attrs[.macLineEnding] ?? "\n"
                        if let context = nextAttrs[.macListContext] { typing[.macListContext] = context }
                        commit(edit.text, selection: edit.selection, typing: typing, name: "End list")
                    case .refused(let issue): if let issue { parent.onPasteError(issue) } else { NSSound.beep() }
                    case .notList, .unchanged: break
                    }
                    return false
                }
                let next = MacBlockPrefix(block)?.leavingEmpty ?? ""
                let plain = MacMarkdown.settingBlock(original.attributedSubstring(from: paragraph), to: next)
                rich.replaceCharacters(in: paragraph, with: plain)
                commit(rich, selection: NSRange(location: paragraph.location + MacMarkdown.displayPrefix(next).utf16.count, length: 0), typing: typingAttributes(block: next), name: "End list")
                return false
            }
            let next = MacBlockPrefix(block)?.next ?? block
            let delta = (MacBlockPrefix(next)?.listPadding ?? 0) - (MacBlockPrefix(block)?.listPadding ?? 0)
            var followingDescendants: [MacMarkdown.NativeListItem] = []
            if MacBlockPrefix(next)?.list == true, delta != 0 {
                guard let items = MacMarkdown.nativeListItems(in: original) else {
                    parent.onPasteError("This list needs Markdown source editing before another item can be inserted safely.")
                    return false
                }
                let owner: Int?
                if let context, context.continuation {
                    owner = items.indices.last(where: { index in
                        let range = items[index].range
                        return range.location < paragraph.location && (original.attribute(.macListContext, at: range.location, effectiveRange: nil) as? MacListContext)?.id == context.id
                    })
                } else { owner = items.firstIndex(where: { $0.range.location == paragraph.location }) }
                guard let owner else {
                    parent.onPasteError("This list needs Markdown source editing before another item can be inserted safely.")
                    return false
                }
                followingDescendants = items.filter { item in
                    guard item.range.location >= NSMaxRange(paragraph) else { return false }
                    var ancestor = item.parent
                    while let index = ancestor {
                        if index == owner { return true }
                        ancestor = items[index].parent
                    }
                    return false
                }
            }
            let left = NSMutableAttributedString(attributedString: original.attributedSubstring(from: NSRange(location: paragraph.location, length: cursor - paragraph.location)))
            let right = NSMutableAttributedString(attributedString: original.attributedSubstring(from: NSRange(location: cursor, length: NSMaxRange(paragraph) - cursor)))
            var replacementRange = paragraph
            if blankHead, hasOwnedContent, NSMaxRange(paragraph) < original.length {
                let next = raw.paragraphRange(for: NSRange(location: NSMaxRange(paragraph), length: 0))
                if let tail = original.attribute(.macListContext, at: next.location, effectiveRange: nil) as? MacListContext,
                   let context, tail.continuation, tail.id == context.id {
                    right.setAttributedString(original.attributedSubstring(from: next))
                    replacementRange.length = NSMaxRange(next) - paragraph.location
                }
            }
            while left.length > 0, (left.string as NSString).character(at: left.length - 1) == 0x2028 { left.deleteCharacters(in: NSRange(location: left.length - 1, length: 1)) }
            while right.length > 0, (right.string as NSString).character(at: 0) == 0x2028 { right.deleteCharacters(in: NSRange(location: 0, length: 1)) }
            let emptyContinuation = context?.continuation == true && line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if emptyContinuation {
                left.deleteCharacters(in: NSRange(location: 0, length: left.length))
                right.setAttributedString(NSAttributedString(string: hasNewline ? "\n" : "", attributes: attrs))
            }
            if MacBlockPrefix(block)?.checklist == true, context?.continuation != true,
               left.length == MacMarkdown.displayPrefix(block).utf16.count, left.length > 0 {
                left.addAttribute(.macEmptyParagraph, value: true, range: NSRange(location: 0, length: left.length))
            }
            let replacement = NSMutableAttributedString(attributedString: left)
            let emptyRuleBoundary = ruleReturn != nil && context?.continuation == true && cursor == paragraph.location
            if !emptyContinuation && !emptyRuleBoundary { replacement.append(NSAttributedString(string: "\n", attributes: attrs)) }
            let splitQuote = selectedReturn && MacBlockPrefix(block)?.list != true && MacBlockPrefix(block)?.heading != true
            if splitQuote { replacement.append(NSAttributedString(string: "\n", attributes: attrs)) }
            let nextParagraph = NSMutableAttributedString(attributedString: MacMarkdown.settingBlock(right, to: next, removingMarker: cursor == paragraph.location))
            nextParagraph.addAttribute(.macLineEnding, value: attrs[.macLineEnding] ?? "\n", range: NSRange(location: 0, length: nextParagraph.length))
            if MacBlockPrefix(next)?.list == true {
                let newItem = MacListContext(source: next, quoteParents: context?.quoteParents ?? [])
                nextParagraph.addAttribute(.macListContext, value: newItem, range: NSRange(location: 0, length: nextParagraph.length))
                // The right sibling owns only the remaining content, never a
                // continuation before this split. Keep those identities distinct.
                let following = NSRange(location: NSMaxRange(paragraph), length: original.length - NSMaxRange(paragraph))
                original.enumerateAttribute(.macListContext, in: following) { value, range, _ in
                    guard let context, let tail = value as? MacListContext else { return }
                    if tail.continuation, tail.id == context.id {
                        let rebased = tail.replacing(source: next)
                        rich.addAttribute(.macListContext, value: MacListContext(id: newItem.id, source: next, continuation: true, gap: rebased.gap, originatedAfterChildren: tail.originatedAfterChildren, suffix: tail.suffix, blockParagraph: tail.blockParagraph, quoteLeaf: tail.quoteLeaf, quoteParents: tail.quoteParents), range: range)
                    } else if tail.quoteParents.contains(where: { $0.id == context.id }) {
                        // Inner quoted lists follow the right sibling, including
                        // its current marker width, rather than the split head.
                        let parents = tail.quoteParents.map { $0.id == context.id ? newItem : $0 }
                        rich.addAttribute(.macListContext, value: tail.replacing(source: tail.source, quoteParents: parents), range: range)
                    }
                }
                original.enumerateAttribute(.macListGap, in: following) { value, range, _ in
                    if let context, let gap = value as? MacListGap, gap.parent == context.id {
                        rich.addAttribute(.macListGap, value: MacListGap(parent: newItem.id, child: gap.child), range: range)
                    }
                }
                // A markerless native row may grow when its marker is restored.
                // Apply original ranges backwards so later rows keep their text.
                for item in followingDescendants.reversed() {
                    let prefix = item.block.shiftingIndentation(by: delta, atQuoteDepth: MacBlockPrefix(block)?.depth ?? 0)
                    rich.replaceCharacters(in: item.range, with: MacMarkdown.settingBlock(rich.attributedSubstring(from: item.range), to: prefix))
                }
            }
            replacement.append(nextParagraph)
            rich.replaceCharacters(in: replacementRange, with: replacement)
            var typing = typingAttributes(block: next)
            typing[.macLineEnding] = attrs[.macLineEnding] ?? "\n"
            if nextParagraph.length > 0, let context = nextParagraph.attribute(.macListContext, at: 0, effectiveRange: nil) { typing[.macListContext] = context }
            var selection = NSRange(location: paragraph.location + left.length + (emptyContinuation || emptyRuleBoundary ? 0 : 1) + (splitQuote ? 1 : 0) + (MacMarkdown.displayPrefix(next) as NSString).length, length: 0)
            if let target = ruleReturnChild {
                let minimum = paragraph.location + replacement.length
                var receiver: (NSRange, MacListContext)?
                rich.enumerateAttribute(.macListContext, in: NSRange(location: minimum, length: rich.length - minimum)) { value, range, stop in
                    if let head = value as? MacListContext, !head.continuation, head.id == target {
                        receiver = (range, head); stop.pointee = true
                    }
                }
                guard let (range, head) = receiver else {
                    parent.onPasteError("This list needs Markdown source editing before another item can be inserted safely.")
                    return false
                }
                let marker = MacMarkdown.displayPrefix(head.block)
                guard (rich.string as NSString).substring(with: range).hasPrefix(marker) else { NSSound.beep(); return false }
                selection = NSRange(location: range.location + marker.utf16.count, length: 0)
                // Range selection before a child's first text run starts plain;
                // existing bold/code/link text keeps its own inline attributes.
                typing = typingAttributes(block: head.block)
                typing[.macListContext] = head; typing[.paragraphStyle] = head.style
                typing[.font] = MacMarkdown.font(head.textBlock)
                typing[.macLineEnding] = rich.attribute(.macLineEnding, at: range.location, effectiveRange: nil) ?? attrs[.macLineEnding] ?? "\n"
            }
            commit(rich, selection: selection, typing: typing, name: "Continue paragraph")
            return false
        }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let value = String(describing: link)
            if let url = URL(string: value), let fragment = MacHeadings.localFragment(url) {
                receiveHeading(.init(fragment: fragment, path: parent.path)); return true
            }
            if let url = URL(string: value), let reference = NoteReference(url: url) { parent.onLink(reference.target) } else { parent.onLink(value) }; return true
        }
        func toggleChecklist(at index: Int) {
            guard !source, let view, view.isEditable, index < (view.string as NSString).length else { return }
            let selectedParagraph = (view.string as NSString).paragraphRange(for: NSRange(location: index, length: 0))
            guard let paragraph = MacMarkdown.listHeadParagraph(in: view.attributedString(), paragraph: selectedParagraph) else { NSSound.beep(); return }
            let current = view.attributedString().attributedSubstring(from: paragraph)
            let block = current.attribute(.macBlock, at: 0, effectiveRange: nil) as? String ?? ""
            guard block.contains("[ ]") || block.contains("[x]") || block.contains("[X]") else { return }
            let next = MacBlockPrefix(block)?.toggledChecklist ?? block
            let rich = NSMutableAttributedString(attributedString: view.attributedString())
            rich.replaceCharacters(in: paragraph, with: MacMarkdown.settingBlock(current, to: next))
            commit(rich, selection: view.selectedRange(), name: next.contains("[x]") ? "Complete item" : "Reopen item")
        }
        private func continuationTyping(in rich: NSAttributedString, after range: NSRange, block: String, ending: String, table: Bool, reuseFollowing: Bool = true) -> [NSAttributedString.Key: Any]? {
            let next = NSMaxRange(range)
            if reuseFollowing, next < rich.length {
                let attrs = rich.attributes(at: next, effectiveRange: nil)
                if attrs[.macCode] != nil || attrs[.macTable] != nil { return nil }
                let row = (rich.string as NSString).paragraphRange(for: NSRange(location: next, length: 0))
                if !rich.attributedSubstring(from: row).string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var typing = typingAttributes(block: attrs[.macBlock] as? String ?? "")
                    for key in [NSAttributedString.Key.macListContext, .macLineEnding, .paragraphStyle, .macIndependentParagraph] { typing[key] = attrs[key] }
                    return typing
                }
            }
            let attrs = rich.attributes(at: range.location, effectiveRange: nil)
            if let placement = attrs[.macListCard] as? MacListCardPlacement,
               let owner = attrs[.macListContext] as? MacListContext {
                let suffix = owner.suffix + placement.ownerSuffix
                let target = MacListContext(id: owner.id, source: owner.source, continuation: true, suffix: suffix, quoteParents: owner.quoteParents)
                let gapPrefix = suffix.isEmpty ? MacBlockPrefix(owner.source)?.quotes ?? "" : target.block
                let context = MacListContext(id: owner.id, source: owner.source, continuation: true, gap: table ? gapPrefix + ending : "", suffix: suffix, quoteParents: owner.quoteParents)
                var typing = typingAttributes(block: context.block)
                typing[.macListContext] = context; typing[.paragraphStyle] = context.style; typing[.macLineEnding] = ending
                return typing
            }
            var typing = typingAttributes(block: block); typing[.macLineEnding] = ending
            return typing
        }
        private func continueAfterCard(_ rich: NSAttributedString, range: NSRange, block: String, ending: String, table: Bool, changed: Bool = false) -> Bool {
            guard let view else { return false }
            let next = NSMaxRange(range)
            var insertParagraph = false
            if next < rich.length {
                let attrs = rich.attributes(at: next, effectiveRange: nil)
                let owner = rich.attribute(.macListContext, at: range.location, effectiveRange: nil) as? MacListContext
                let following = attrs[.macListContext] as? MacListContext
                let row = (rich.string as NSString).paragraphRange(for: NSRange(location: next, length: 0))
                let nonempty = !rich.attributedSubstring(from: row).string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                // A following card or item is not a prose destination. Keep it
                // intact and create a continuation of the current card's owner.
                insertParagraph = attrs[.macCode] != nil || attrs[.macTable] != nil ||
                    MacBlockPrefix(attrs[.macBlock] as? String ?? "")?.list == true ||
                    following?.continuation == false || nonempty && owner != nil && owner?.id != following?.id
            }
            let typing = continuationTyping(in: rich, after: range, block: block, ending: ending, table: table, reuseFollowing: !insertParagraph)
            if insertParagraph || changed {
                let output = NSMutableAttributedString(attributedString: rich)
                if insertParagraph { output.insert(NSAttributedString(string: "\n", attributes: typing ?? typingAttributes(block: block)), at: next) }
                commit(output, selection: NSRange(location: next, length: 0), typing: typing, name: table ? "Continue after table" : "Continue after code")
                view.breakUndoCoalescing()
                if editorUndo.groupingLevel == 1 { editorUndo.endUndoGrouping(); editorUndo.beginUndoGrouping() }
            } else {
                view.setSelectedRange(NSRange(location: next, length: 0)); updateWritingContext()
                if let typing { view.typingAttributes = typing }
            }
            view.scrollRangeToVisible(view.selectedRange()); return true
        }
        @discardableResult func exitCode() -> Bool {
            guard let view, view.isEditable, !view.hasMarkedText() else { return false }
            if let cell = cellAtCaret() {
                var range = NSRange(); _ = view.attributedString().attribute(.macTable, at: view.selectedRange().location, longestEffectiveRange: &range, in: NSRange(location: 0, length: view.attributedString().length))
                return continueAfterCard(view.attributedString(), range: range, block: cell.table.quote?.prefix ?? "", ending: cell.table.original.newline, table: true)
            }
            guard let code = codeAtCaret() else { return false }
            var range = NSRange()
            _ = view.attributedString().attribute(.macCode, at: view.selectedRange().location, longestEffectiveRange: &range, in: NSRange(location: 0, length: view.attributedString().length))
            if !code.original.closed {
                let rich = view.attributedString(), body = MacRichCode.body(rich, in: range)
                let closed = code.original.replacing(body: body, info: code.original.info, closing: true)
                let terminated = code.original.markdown.utf8.last.map { $0 == 10 || $0 == 13 } ?? false
                let ending = code.ending.isEmpty && terminated ? closed.newline : code.ending
                let card = MacListCardPlacement.carrying(MacRichCode.render(closed, ending: ending, quote: code.quote), from: rich.attributedSubstring(from: range))
                let output = NSMutableAttributedString(attributedString: rich); output.replaceCharacters(in: range, with: card)
                return continueAfterCard(output, range: NSRange(location: range.location, length: card.length), block: code.quote?.prefix ?? "", ending: closed.newline, table: false, changed: true)
            }
            return continueAfterCard(view.attributedString(), range: range, block: code.quote?.prefix ?? "", ending: code.original.newline, table: false)
        }
        private func codeToText() {
            guard let view, !source, let code = codeAtCaret(), !view.hasMarkedText() else { return }
            let before = view.attributedString(), position = min(view.selectedRange().location, before.length - 1)
            var range = NSRange()
            _ = before.attribute(.macCode, at: position, longestEffectiveRange: &range, in: NSRange(location: 0, length: before.length))
            let inherited = before.attributes(at: range.location, effectiveRange: nil)
            let body = MacMarkdownLines.normalized(MacRichCode.body(before, in: range), to: "\n").replacingOccurrences(of: "\n", with: "\u{2028}")
            var attrs = typingAttributes(block: code.quote?.prefix ?? "")
            attrs[.macLineEnding] = code.original.newline
            attrs[.macIndependentParagraph] = code.quote == nil
            // Explicit breaks keep leading, trailing and empty code lines as
            // literal paragraph content, rather than Markdown block boundaries.
            attrs[.macListBreak] = 3
            if let owner = inherited[.macListContext] as? MacListContext,
               let placement = inherited[.macListCard] as? MacListCardPlacement {
                let context = MacListContext(id: owner.id, source: owner.source, continuation: true,
                    gap: code.original.newline, suffix: owner.suffix + placement.ownerSuffix, quoteParents: owner.quoteParents)
                attrs[.macListContext] = context; attrs[.macBlock] = context.block
                attrs[.paragraphStyle] = context.style; attrs[.macIndependentParagraph] = false
            }
            var text = body
            // A fence on an otherwise empty item's marker line renders with a
            // native head row. Replace that row too, so conversion fills the
            // existing item instead of leaving an empty head above its text.
            if let owner = inherited[.macListContext] as? MacListContext,
               let placement = inherited[.macListCard] as? MacListCardPlacement,
               placement.ownerSuffix.isEmpty, owner.suffix.isEmpty,
               MacListCardPlacement.joinedHeads(in: before).cards[range.location]?.last?.id == owner.id,
               range.location > 0, let prefix = MacBlockPrefix(owner.source) {
                let head = (before.string as NSString).paragraphRange(for: NSRange(location: range.location - 1, length: 0))
                range = NSRange(location: head.location, length: NSMaxRange(range) - head.location)
                let context = MacListContext(id: owner.id, source: owner.source, quoteParents: owner.quoteParents)
                attrs[.macListContext] = context; attrs[.macBlock] = context.block; attrs[.paragraphStyle] = context.style
                text = prefix.display + body
            }
            let replacement = NSAttributedString(string: text + "\n", attributes: attrs)
            let output = NSMutableAttributedString(attributedString: before)
            output.replaceCharacters(in: range, with: replacement)
            let markdown = MacMarkdown.markdown(output)
            guard MacListCards.parents(in: markdown) == MacListCards.parents(in: lastMarkdown),
                  MacCodeBlock.blocks(in: markdown).count == MacCodeBlock.blocks(in: lastMarkdown).count - 1 else {
                parent.onPasteError("This code block needs Source editing before it can become text without changing its surrounding items.")
                return
            }
            commit(output, selection: NSRange(location: range.location + text.utf16.count, length: 0), typing: attrs, name: "Turn code block into text")
        }
        func action(_ name: String) {
            guard active, parent.isCurrent() else { return }
            guard !pasting else { return }
            guard let view, view.window?.firstResponder === view, view.isEditable else { return }
            if name == "insertImage" { showImageInsertion(); return }
            if name == "link" { showLinkEditor(); return }
            if name == "exitCode" { _ = exitCode(); return }
            if name == "codeToText" { codeToText(); return }
            if name == "indent" || name == "outdent" { _ = indentList(backward: name == "outdent"); return }
            if cellAtCaret() != nil && !["undo", "redo", "find", "bold", "italic", "underline", "code", "noteLink"].contains(name) { NSSound.beep(); return }
            if codeAtCaret() != nil && !["undo", "redo", "find"].contains(name) { NSSound.beep(); return }
            if name == "noteLink" { showNoteLinks(automatic: false); return }
            if name == "toggleChecklist" { toggleChecklist(at: min(view.selectedRange().location, max(0, (view.string as NSString).length - 1))); return }
            if name == "find" { MacNoteFind.show(in: view); return }
            if name == "undo" { view.undoManager?.undo(); return }
            if name == "redo" { view.undoManager?.redo(); return }
            if name == "rule" {
                let selected = view.selectedRange(), original = view.attributedString()
                if source { view.insertText("\n\n***\n\n", replacementRange: selected); return }
                do {
                    let insertion = MacMarkdown.render("***\n")
                    let plan = try inlinePastePlan(insertion, formatted: true, original: original, range: selected, typing: view.typingAttributes, markdown: "***\n")
                    if let edit = plan.edit { commit(edit.text, selection: edit.selection, typing: edit.typing, name: "Insert horizontal rule") }
                    else {
                        let output = NSMutableAttributedString(attributedString: original); output.replaceCharacters(in: selected, with: insertion)
                        commit(output, selection: NSRange(location: selected.location + insertion.length, length: 0), typing: typingAttributes(block: ""), name: "Insert horizontal rule")
                    }
                } catch { parent.onPasteError(error.localizedDescription) }
                return
            }
            let selected = view.selectedRange()
            let before = NSAttributedString(attributedString: view.attributedString())
            guard selected.location <= before.length else { return }
            if !source, selected.location < before.length {
                let row = (before.string as NSString).paragraphRange(for: NSRange(location: selected.location, length: 0))
                if before.attribute(.macRule, at: row.location, effectiveRange: nil) != nil, NSMaxRange(selected) <= NSMaxRange(row) { return }
            }
            if source {
                let wrap = name == "bold" ? "**" : name == "italic" ? "*" : name == "code" ? "`" : ""
                if name == "underline" { view.insertText("<u>" + (view.string as NSString).substring(with: selected) + "</u>", replacementRange: selected) }
                else if !wrap.isEmpty { view.insertText(wrap + (view.string as NSString).substring(with: selected) + wrap, replacementRange: selected) }
                else {
                    let prefix = blockPrefix(for: name)
                    let raw = view.string as NSString
                    let selection = selected.length > 0 ? NSRange(location: selected.location, length: selected.length - 1) : selected
                    let paragraphs = raw.paragraphRange(for: selection), fragment = raw.substring(with: paragraphs), lines = MacMarkdownLines(fragment).lines
                    let replacement = lines.enumerated().map { index, line in
                        if index > 0, index == lines.count - 1, line.text.isEmpty, line.ending.isEmpty { return "" }
                        return prefix + line.text.replacingOccurrences(of: #"^(#{1,6} |[-*+] \[[ xX]\] |[-*+] |\d+[.)] |> )"#, with: "", options: .regularExpression) + line.ending
                    }.joined()
                    view.insertText(replacement, replacementRange: paragraphs)
                }
                return
            }
            let rich = NSMutableAttributedString(attributedString: before)
            if ["bold", "italic", "underline", "code"].contains(name) {
                func active(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
                    let block = attrs[.macBlock] as? String ?? "", font = attrs[.font] as? NSFont ?? MacMarkdown.font(block)
                    let traits = NSFontManager.shared.traits(of: font)
                    if name == "underline" { return (attrs[.underlineStyle] as? Int ?? 0) != 0 }
                    return name == "bold" ? MacMarkdown.inlineBold(attrs, block: block) : traits.contains(name == "italic" ? .italicFontMask : .fixedPitchFontMask)
                }
                var allActive = true
                if selected.length == 0 { allActive = active(view.typingAttributes) }
                else { before.enumerateAttributes(in: selected) { attrs, _, _ in if !active(attrs) { allActive = false } } }
                func changed(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
                    var result = attrs
                    let block = attrs[.macBlock] as? String ?? "", font = attrs[.font] as? NSFont ?? MacMarkdown.font(block), traits = NSFontManager.shared.traits(of: font)
                    let bold = name == "bold" ? !allActive : MacMarkdown.inlineBold(attrs, block: block)
                    let italic = name == "italic" ? !allActive : traits.contains(.italicFontMask)
                    let code = name == "code" ? !allActive : traits.contains(.fixedPitchFontMask)
                    result[.font] = MacMarkdown.inlineFont(block: block, bold: bold, italic: italic, code: code); result[.macStrong] = bold
                    if name == "underline" { result[.underlineStyle] = allActive ? nil : NSUnderlineStyle.single.rawValue }
                    result.removeValue(forKey: .macOriginal); result.removeValue(forKey: .macSignature)
                    if code { result[.backgroundColor] = NSColor.quaternaryLabelColor } else { result.removeValue(forKey: .backgroundColor) }
                    return result
                }
                if selected.length == 0 { view.typingAttributes = changed(view.typingAttributes); return }
                before.enumerateAttributes(in: selected) { attrs, range, _ in rich.setAttributes(changed(attrs), range: range) }
                commit(rich, selection: selected, name: "Format text")
            } else {
                let prefix = blockPrefix(for: name)
                let raw = view.string as NSString
                if before.length == 0 || selected.location == before.length && raw.hasSuffix("\n") {
                    let marker = MacMarkdown.displayPrefix(prefix)
                    if marker.isEmpty {
                        var typing = typingAttributes(block: prefix)
                        if before.length > 0 {
                            let last = before.attributes(at: before.length - 1, effectiveRange: nil)
                            typing[.macLineEnding] = last[.macLineEnding] ?? "\n"
                            let block = last[.macBlock] as? String ?? "", previous = MacBlockPrefix(block)
                            if prefix.isEmpty, previous?.list == true || (previous?.depth ?? 0) > 0 || !block.isEmpty && last[.macListContext] != nil {
                                rich.append(NSAttributedString(string: "\n", attributes: typing))
                                commit(rich, selection: NSRange(location: rich.length, length: 0), typing: typing, name: "Format paragraph")
                                return
                            }
                        }
                        view.typingAttributes = typing
                    }
                    else { rich.append(NSAttributedString(string: marker, attributes: typingAttributes(block: prefix))); commit(rich, selection: NSRange(location: rich.length, length: 0), typing: typingAttributes(block: prefix), name: "Format paragraph") }
                    return
                }
                if MacBlockPrefix(prefix)?.list != true {
                    switch MacListEditing.formatting(before, selection: selected, to: prefix) {
                    case .changed(let edit):
                        let at = min(edit.selection.location, max(0, edit.text.length - 1))
                        var typing = edit.typing ?? (edit.text.length > 0 ? edit.text.attributes(at: at, effectiveRange: nil) : typingAttributes(block: prefix))
                        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListBreak, .macHardBreak] { typing.removeValue(forKey: key) }
                        commit(edit.text, selection: edit.selection, typing: typing, name: "Format paragraph")
                        typingAfterBlockFormat = true
                    case .refused(let issue): if let issue { parent.onPasteError(issue) } else { NSSound.beep() }
                    case .notList, .unchanged: break
                    }
                    return
                }
                let selectionRange = selected.length > 0 ? NSRange(location: selected.location, length: selected.length - 1) : selected
                let full = raw.paragraphRange(for: selectionRange)
                var ranges: [NSRange] = [], offset = full.location
                while offset < NSMaxRange(full) { let range = raw.paragraphRange(for: NSRange(location: offset, length: 0)); ranges.append(range); offset = NSMaxRange(range) }
                if MacBlockPrefix(prefix)?.list == true {
                    var heads: [Int: NSRange] = [:]
                    for range in ranges {
                        guard let head = MacMarkdown.listHeadParagraph(in: before, paragraph: range) else { NSSound.beep(); return }
                        heads[head.location] = head
                    }
                    ranges = heads.values.sorted { $0.location < $1.location }
                }
                var targets = Dictionary(uniqueKeysWithValues: ranges.map { ($0.location, prefix) })
                if let requested = MacBlockPrefix(prefix), requested.list {
                    // Source indentation alone cannot establish ownership: sibling
                    // markers may use different columns or quote-prefix spellings.
                    // Pair native item paragraphs with the parser's item order before
                    // changing marker widths, then propagate through actual parents.
                    guard let items = MacMarkdown.nativeListItems(in: before) else { NSSound.beep(); return }
                    var shifts: [[Int: Int]] = []
                    for item in items {
                        let block = item.block, range = item.range
                        var inherited = item.parent.map { shifts[$0] } ?? [:]
                        let chosen = targets[range.location] != nil
                        if chosen || inherited.values.contains(where: { $0 != 0 }) {
                            var shifted = block
                            for level in inherited.keys.sorted() {
                                shifted = MacBlockPrefix(shifted.shiftingIndentation(by: inherited[level]!, atQuoteDepth: level))!
                            }
                            let next = shifted.replacingMarker(chosen ? requested.marker : block.marker)
                            targets[range.location] = next
                            if !chosen { ranges.append(range) }
                            if chosen { inherited[block.depth, default: 0] += MacBlockPrefix(next)!.listPadding - block.listPadding }
                        }
                        shifts.append(inherited)
                    }
                    ranges.sort { $0.location < $1.location }
                }
                var start = selected.location, end = NSMaxRange(selected)
                func mapped(_ position: Int, range: NSRange, oldPrefix: Int, newPrefix: Int) -> Int {
                    if position < range.location { return position }
                    if position >= NSMaxRange(range) { return position + newPrefix - oldPrefix }
                    return range.location + newPrefix + max(0, position - range.location - oldPrefix)
                }
                for range in ranges.reversed() {
                    let paragraph = before.attributedSubstring(from: range), block = paragraph.attribute(.macBlock, at: 0, effectiveRange: nil) as? String ?? ""
                    let marker = MacMarkdown.displayPrefix(block), oldPrefix = paragraph.string.hasPrefix(marker) ? (marker as NSString).length : 0
                    let target = targets[range.location] ?? prefix
                    let replacement = MacMarkdown.settingBlock(paragraph, to: target), newPrefix = (MacMarkdown.displayPrefix(target) as NSString).length
                    rich.replaceCharacters(in: range, with: replacement)
                    start = mapped(start, range: range, oldPrefix: oldPrefix, newPrefix: newPrefix); end = mapped(end, range: range, oldPrefix: oldPrefix, newPrefix: newPrefix)
                }
                let typingBlock = targets[full.location] ?? prefix
                let prepared = MacMarkdown.refreshingListContexts(rich)
                var typing = typingAttributes(block: typingBlock)
                if MacBlockPrefix(prefix)?.list == true, prepared.length > 0 {
                    let at = min(start, prepared.length - 1)
                    if let context = prepared.attribute(.macListContext, at: at, effectiveRange: nil) as? MacListContext {
                        typing = typingAttributes(block: context.block)
                        typing[.macListContext] = context; typing[.paragraphStyle] = context.style; typing[.font] = MacMarkdown.font(context.textBlock)
                    }
                }
                commit(prepared, selection: NSRange(location: start, length: max(0, end - start)), typing: typing, name: "Format paragraph")
            }
        }
        func restore(_ value: NSAttributedString, selection: NSRange? = nil, typing: [NSAttributedString.Key: Any]? = nil, asSource: Bool? = nil) {
            guard active, parent.isCurrent() else { return }
            guard let view else { return }; linkCompletion.hide()
            typingAfterBlockFormat = false
            view.breakUndoCoalescing()
            let before = NSAttributedString(attributedString: view.attributedString()), previousSelection = view.selectedRange(), previousTyping = view.typingAttributes, previousSource = source
            view.undoManager?.registerUndo(withTarget: self) { target in target.restore(before, selection: previousSelection, typing: previousTyping, asSource: previousSource) }
            loading = true
            if let asSource { source = asSource; view.isRichText = !asSource; parent.onSourceChange(asSource) }
            view.textStorage?.setAttributedString(value)
            let selected = selection ?? NSRange(location: min(view.selectedRange().location, value.length), length: 0)
            view.setSelectedRange(NSRange(location: min(selected.location, value.length), length: min(selected.length, max(0, value.length - selected.location))))
            if let typing { view.typingAttributes = typing }
            applyTheme(theme, force: true)
            loading = false; refreshImages(force: true); publish(); scheduleRemoteImages()
        }
    }
}

/// Native selection with explicit controls for checkboxes, image handles and link previews.
private final class MacEditorTextView: NSTextView, NSLayoutManagerDelegate {
    private var noteLayout = MacNoteLayout()
    /// Theme color for list markers. Applied only while drawing, so the
    /// stored text, Markdown export and clipboard never carry it.
    var markerColor: NSColor = MacMarkdown.accent
    /// The visible marker at the start of a list item's first paragraph.
    private func listMarker(atParagraph start: Int, in text: NSAttributedString) -> String? {
        guard isRichText, start < text.length else { return nil }
        let attrs = text.attributes(at: start, effectiveRange: nil)
        guard attrs[.macCode] == nil, attrs[.macTable] == nil, attrs[.attachment] == nil else { return nil }
        let context = attrs[.macListContext] as? MacListContext
        guard context?.continuation != true, let source = context?.source ?? attrs[.macBlock] as? String,
              let prefix = MacBlockPrefix(source), prefix.list else { return nil }
        let display = prefix.display, length = display.utf16.count
        guard length > 1, start + length <= text.length,
              (text.string as NSString).substring(with: NSRange(location: start, length: length)) == display else { return nil }
        return display
    }
    func layoutManager(_ layoutManager: NSLayoutManager, shouldUseTemporaryAttributes attrs: [NSAttributedString.Key: Any] = [:], forDrawingToScreen toScreen: Bool, atCharacterIndex charIndex: Int, effectiveRange effectiveCharRange: NSRangePointer?) -> [NSAttributedString.Key: Any]? {
        guard isRichText, let text = layoutManager.textStorage, charIndex < text.length else { return attrs }
        let raw = text.string as NSString, paragraph = raw.paragraphRange(for: NSRange(location: charIndex, length: 0))
        var applied = NSRange(location: charIndex, length: NSMaxRange(paragraph) - charIndex)
        var result = attrs
        if let marker = listMarker(atParagraph: paragraph.location, in: text) {
            // Exclude the separating space so selection and spelling marks stay ordinary.
            let glyphs = NSRange(location: paragraph.location, length: marker.utf16.count - 1)
            if NSLocationInRange(charIndex, glyphs) {
                applied = NSRange(location: charIndex, length: NSMaxRange(glyphs) - charIndex)
                // The bullet glyph is replaced by a larger drawn dot (see drawListBullets).
                result[.foregroundColor] = marker == "• " ? NSColor.clear : markerColor
            } else if charIndex < glyphs.location {
                applied.length = glyphs.location - charIndex
            }
        }
        if let effective = effectiveCharRange {
            let incoming = effective.pointee
            effective.pointee = incoming.length > 0 && NSLocationInRange(charIndex, incoming) ? NSIntersectionRange(incoming, applied) : applied
        }
        return result
    }
    private func drawListBullets(_ dirtyRect: NSRect) {
        guard isRichText, let manager = layoutManager, let container = textContainer else { return }
        let rich = attributedString(), raw = rich.string as NSString
        guard rich.length > 0 else { return }
        let area = NSRect(x: 0, y: dirtyRect.minY - textContainerOrigin.y, width: container.size.width, height: dirtyRect.height)
        let visibleGlyphs = manager.glyphRange(forBoundingRect: area, in: container)
        guard visibleGlyphs.location != NSNotFound, visibleGlyphs.length > 0 else { return }
        let visible = raw.paragraphRange(for: manager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil))
        markerColor.setFill()
        raw.enumerateSubstrings(in: visible, options: [.byParagraphs, .substringNotRequired]) { _, paragraph, _, _ in
            guard self.listMarker(atParagraph: paragraph.location, in: rich) == "• " else { return }
            let glyph = manager.glyphIndexForCharacter(at: paragraph.location)
            guard glyph < manager.numberOfGlyphs, !manager.notShownAttribute(forGlyphAt: glyph) else { return }
            let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let bullet = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let font = rich.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont ?? MacMarkdown.font("")
            let baseline = line.minY + manager.location(forGlyphAt: glyph).y
            let diameter = (font.pointSize * 0.42).rounded()
            let center = NSPoint(x: bullet.midX + self.textContainerOrigin.x, y: baseline - font.xHeight / 2 + self.textContainerOrigin.y)
            NSBezierPath(ovalIn: NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)).fill()
        }
    }
    func setNoteLayout(_ value: MacNoteLayout) {
        guard value != noteLayout || textContainer?.widthTracksTextView == true else { return }
        noteLayout = value; updateWritingWidth(); needsDisplay = true
    }
    private func updateWritingWidth() {
        guard bounds.width > 92, let container = textContainer else { return }
        let width = noteLayout.contentWidth(in: bounds.width)
        container.widthTracksTextView = false
        if abs(container.containerSize.width - width) > 0.01 { container.containerSize.width = width }
    }
    override var textContainerOrigin: NSPoint {
        var point = super.textContainerOrigin
        point.x = noteLayout.origin(in: bounds.width)
        return point
    }
    override func setFrameSize(_ size: NSSize) {
        let old = frame.width
        super.setFrameSize(size)
        if abs(old - size.width) > 0.01 { updateWritingWidth(); needsLayout = true; needsDisplay = true }
    }

    private func drawCodeBlocks(_ dirtyRect: NSRect) {
        if isRichText, let manager = layoutManager, let container = textContainer {
            let rich = attributedString()
            let full = NSRange(location: 0, length: rich.length)
            // Headers and rounded borders extend beyond the code glyphs. Query
            // the whole writing width so a margin-only repaint still finds them.
            let area = NSRect(x: 0, y: dirtyRect.minY - textContainerOrigin.y - 28,
                              width: container.size.width, height: dirtyRect.height + 56)
            let visibleGlyphs = manager.glyphRange(forBoundingRect: area, in: container)
            guard visibleGlyphs.location != NSNotFound, visibleGlyphs.length > 0 else { return }
            let visible = NSIntersectionRange(full, manager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil))
            rich.enumerateAttribute(.macCode, in: visible) { value, visibleRange, _ in
                guard let code = value as? MacRichCode else { return }
                // A viewport can start inside a card. Keep its complete bounds
                // and header position, rather than treating the clipped run as a card.
                var range = NSRange()
                _ = rich.attribute(.macCode, at: visibleRange.location, longestEffectiveRange: &range, in: full)
                let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let bounds = manager.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                let style = rich.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                let inset = max(0, (style?.headIndent ?? CGFloat(14 + (code.quote?.depth ?? 0) * 18)) - 14)
                let card = NSRect(x: self.textContainerOrigin.x + inset, y: bounds.minY - 22, width: max(80, container.size.width - inset), height: bounds.height + 28)
                guard card.intersects(dirtyRect) else { return }
                NSColor.textBackgroundColor.setFill()
                NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
                NSColor.quaternaryLabelColor.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
                ((code.original.language + " · ⌘Return to continue writing") as NSString).draw(at: NSPoint(x: card.minX + 14, y: card.minY + 4), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor])
            }
        }
    }
    var imageAction: ((Int, String) -> Void)?
    var beginImageResize: ((Int) -> ((NSSize?) -> Void)?)?
    private struct ImageDrag {
        let original: NSRect
        let start: NSPoint
        let finish: (NSSize?) -> Void
        var preview: NSRect
    }
    private var imageDrag: ImageDrag?
    private func selectedImageRect() -> NSRect? {
        let selection = selectedRange()
        guard isEditable, isRichText, !hasMarkedText(), selection.length == 1,
              selection.location < attributedString().length,
              attributedString().attribute(.attachment, at: selection.location, effectiveRange: nil) is MacImageAttachment,
              let manager = layoutManager, let container = textContainer else { return nil }
        let glyphs = manager.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        let size = manager.attachmentSize(forGlyphAt: glyphs.location)
        return NSRect(origin: NSPoint(x: rect.minX + textContainerOrigin.x, y: rect.minY + textContainerOrigin.y), size: size)
    }
    private func resizeHandle(_ rect: NSRect) -> NSRect { NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 12, height: 12) }
    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill(); dirtyRect.fill()
        drawCodeBlocks(dirtyRect)
        super.draw(dirtyRect)
        drawListBullets(dirtyRect)
        guard let rect = imageDrag?.preview ?? selectedImageRect(), rect.width > 0, rect.height > 0 else { return }
        NSColor.controlAccentColor.setStroke(); let outline = NSBezierPath(rect: rect); outline.lineWidth = 1.5; outline.stroke()
        let handle = NSBezierPath(roundedRect: resizeHandle(rect), xRadius: 2, yRadius: 2)
        NSColor.windowBackgroundColor.setFill(); handle.fill(); NSColor.controlAccentColor.setStroke(); handle.stroke()
        if imageDrag != nil {
            let label = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor, .backgroundColor: NSColor.windowBackgroundColor]
            (label as NSString).draw(at: NSPoint(x: rect.minX, y: max(visibleRect.minY, rect.minY - 20)), withAttributes: attrs)
        }
    }
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard var drag = imageDrag else { super.mouseDragged(with: event); return }
        let point = convert(event.locationInWindow, from: nil), ratio = drag.original.height / max(1, drag.original.width)
        let available = max(16, (textContainer?.containerSize.width ?? (bounds.width - textContainerOrigin.x * 2)) - (textContainer?.lineFragmentPadding ?? 0) * 2)
        let width = min(8192, available, 1000 / max(0.001, ratio), max(16, drag.original.width + point.x - drag.start.x))
        drag.preview.size = NSSize(width: width, height: max(1, width * ratio)); imageDrag = drag; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let drag = imageDrag else { super.mouseUp(with: event); return }
        imageDrag = nil; needsDisplay = true
        drag.finish(abs(drag.preview.width - drag.original.width) >= 1 ? drag.preview.size : nil)
    }
    private var menuImageIndex: Int?
    @objc private func editMenuImage() { if let index = menuImageIndex { imageAction?(index, "edit") } }
    @objc private func expandMenuImage() { if let index = menuImageIndex { imageAction?(index, "expand") } }
    @objc private func retryMenuImage() { if let index = menuImageIndex { imageAction?(index, "retry") } }
    @objc private func removeMenuImage() { if let index = menuImageIndex { imageAction?(index, "remove") } }
    private func imageIndex(at point: NSPoint) -> Int? {
        guard let manager = layoutManager, let container = textContainer else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = manager.glyphIndex(for: local, in: container)
        guard glyph < manager.numberOfGlyphs else { return nil }
        let index = manager.characterIndexForGlyph(at: glyph)
        guard index < attributedString().length, attributedString().attribute(.attachment, at: index, effectiveRange: nil) is MacImageAttachment,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) else { return nil }
        return index
    }
    var previewLink: ((Int, Bool) -> Void)?
    var editLink: ((Int, Bool, UUID) -> Void)?
    var linkRevision: (() -> UUID?)?
    private var menuLinkRevision: UUID?
    private var menuLinkText: String?
    private var menuLinkDestination: String?
    var leaveLink: (() -> Void)?
    var dismissLinkPreview: (() -> Void)?
    private var linkTracking: NSTrackingArea?
    private var menuLinkIndex: Int?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let linkTracking { removeTrackingArea(linkTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); linkTracking = area
    }
    private func linkIndex(at point: NSPoint) -> Int? {
        guard isRichText, let manager = layoutManager, let container = textContainer else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = manager.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < attributedString().length, attributedString().attribute(.link, at: index, effectiveRange: nil) != nil else { return nil }
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: glyphs, in: container).contains(local) ? index : nil
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if let index = linkIndex(at: convert(event.locationInWindow, from: nil)) { previewLink?(index, false) }
        else { leaveLink?() }
    }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); leaveLink?() }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menuImageIndex = imageIndex(at: convert(event.locationInWindow, from: nil))
        if menuImageIndex != nil {
            for (title, selector) in [("Remove image…", #selector(removeMenuImage)), ("Edit image…", #selector(editMenuImage)), ("Expand image", #selector(expandMenuImage))] {
                if !isEditable && selector != #selector(expandMenuImage) { continue }
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.insertItem(item, at: 0)
            }
            if let index = menuImageIndex, let literal = attributedString().attribute(.macLiteral, at: index, effectiveRange: nil) as? String,
               let image = MacInlineImage.parse(literal), ["http", "https"].contains(URL(string: image.reference)?.scheme?.lowercased() ?? "") {
                let retry = NSMenuItem(title: "Reload image", action: #selector(retryMenuImage), keyEquivalent: ""); retry.target = self; menu.insertItem(retry, at: 0)
            }
            menu.insertItem(.separator(), at: min(3, menu.items.count))
        }
        menuLinkIndex = linkIndex(at: convert(event.locationInWindow, from: nil))
        menuLinkRevision = linkRevision?(); menuLinkText = string
        menuLinkDestination = menuLinkIndex.flatMap { attributedString().attribute(.link, at: $0, effectiveRange: nil).map { String(describing: $0) } }
        if menuLinkIndex != nil {
            // AppKit supplies its own link panel/actions. Replace those entries
            // with the same guarded commands used by the toolbar and keyboard.
            for item in menu.items {
                let action = item.action.map(NSStringFromSelector) ?? ""
                if ["orderFrontLinkPanel:", "copyLink:", "removeLink:"].contains(action) ||
                    ["Edit Link…", "Remove Link", "Copy Link"].contains(where: { item.title.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
                    menu.removeItem(item)
                }
            }
            let copy = NSMenuItem(title: "Copy link", action: #selector(copyMenuLink), keyEquivalent: ""); copy.target = self; menu.insertItem(copy, at: 0)
            if isEditable {
                for (title, selector) in [("Edit link…", #selector(editMenuLink)), ("Remove link", #selector(removeMenuLink))] {
                    let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.insertItem(item, at: 0)
                }
            }
            if !["http", "https"].contains(URL(string: menuLinkDestination ?? "")?.scheme?.lowercased() ?? "") {
                let item = NSMenuItem(title: "Preview linked note", action: #selector(previewMenuLink), keyEquivalent: "")
                item.target = self; menu.insertItem(item, at: 0)
            }
        }
        return menu
    }
    private var currentMenuLink: Int? {
        guard let index = menuLinkIndex, index < attributedString().length,
              menuLinkText?.utf8.elementsEqual(string.utf8) == true,
              String(describing: attributedString().attribute(.link, at: index, effectiveRange: nil) ?? "") == menuLinkDestination else { return nil }
        return index
    }
    @objc private func editMenuLink() { if let index = currentMenuLink, let revision = menuLinkRevision { editLink?(index, false, revision) } }
    @objc private func removeMenuLink() { if let index = currentMenuLink, let revision = menuLinkRevision { editLink?(index, true, revision) } }
    @objc private func copyMenuLink() {
        guard let index = currentMenuLink, let destination = menuLinkDestination else { return }
        var range = NSRange()
        _ = attributedString().attribute(.link, at: index, longestEffectiveRange: &range, in: NSRange(location: 0, length: attributedString().length))
        let reference = URL(string: destination).flatMap(NoteReference.init(url:))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reference.map { $0.markdown(label: (string as NSString).substring(with: range)) } ?? destination, forType: .string)
    }
    @objc private func previewMenuLink() { if let index = currentMenuLink { previewLink?(index, true) } }
    var prepareCompositionRange: ((NSRange) -> NSRange)?
    var normalizedInputRange: ((NSRange) -> NSRange)?
    private func inputRange(_ range: NSRange) -> NSRange {
        guard !hasMarkedText(), isEditable else { return range }
        if typingAttributes[.attachment] is MacRuleAttachment || typingAttributes[.macRule] != nil {
            var typing = typingAttributes
            for key in [NSAttributedString.Key.attachment, .macRule, .macRuleGap, .macLiteral, .macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature] { typing.removeValue(forKey: key) }
            typingAttributes = typing
        }
        let resolved = range.location == NSNotFound ? selectedRange() : range
        let checked = normalizedInputRange?(resolved) ?? resolved
        guard checked != resolved else { return range }
        setSelectedRange(checked)
        return checked
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        var range = inputRange(replacementRange)
        if !hasMarkedText() {
            let resolved = range.location == NSNotFound ? self.selectedRange() : range
            range = prepareCompositionRange?(resolved) ?? range
        }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: range)
        if !committingInput && !hasMarkedText() { onCompositionEnded?(nil) }
    }
    var onCompositionEnded: ((String?) -> Void)?
    var hasSelectionComposition: (() -> Bool)?
    private var committingInput = false
    private func cancelMarkedSelection() -> Bool {
        guard hasMarkedText(), hasSelectionComposition?() == true else { return false }
        // Discard the input method state without committing its literal accent.
        // The coordinator then restores its immutable structural selection.
        let nested = committingInput; committingInput = true
        inputContext?.discardMarkedText()
        super.unmarkText()
        committingInput = nested
        onCompositionEnded?("")
        return true
    }
    override func unmarkText() {
        let range = markedRange(), text = range.location != NSNotFound && NSMaxRange(range) <= attributedString().length ? (string as NSString).substring(with: range) : nil
        super.unmarkText()
        if !committingInput { onCompositionEnded?(text) }
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let nested = committingInput; committingInput = true
        super.insertText(insertString, replacementRange: inputRange(replacementRange))
        committingInput = nested
        if !nested && !hasMarkedText() { onCompositionEnded?((insertString as? String) ?? (insertString as? NSAttributedString)?.string) }
    }
    var onReady: (() -> Void)?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.acceptsMouseMovedEvents = true; onReady?() }
    override func layout() { super.layout(); updateWritingWidth(); onReady?() }
    var handleBlockBackspace: (() -> Bool)?
    override func deleteBackward(_ sender: Any?) {
        if !hasMarkedText(), handleBlockBackspace?() == true { return }
        super.deleteBackward(sender)
    }
    var handleSelectedReturn: (() -> Bool)?
    override func insertNewline(_ sender: Any?) {
        if selectedRange().length > 0, !hasMarkedText(), handleSelectedReturn?() == true { return }
        super.insertNewline(sender)
    }
    var handleTableKey: ((Bool) -> Bool)?
    var handleCodeExit: (() -> Bool)?
    var handleLinkKey: ((UInt16) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if let drag = imageDrag { imageDrag = nil; drag.finish(nil); needsDisplay = true; if event.keyCode == 53 { return } }
        dismissLinkPreview?()
        if event.keyCode == 53, cancelMarkedSelection() { return }
        if !hasMarkedText(), event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty, handleLinkKey?(event.keyCode) == true { return }
        if event.keyCode == 48, !event.modifierFlags.contains(.command), handleTableKey?(event.modifierFlags.contains(.shift)) == true { return }
        if event.keyCode == 36, event.modifierFlags.contains(.command), handleCodeExit?() == true { return }
        super.keyDown(with: event)
    }
    var toggleChecklist: ((Int) -> Void)?
    var handlePaste: ((Bool) -> Void)?
    var handleCopy: ((Bool) -> Void)?
    override func copy(_ sender: Any?) { handleCopy?(false) }
    override func cut(_ sender: Any?) { handleCopy?(true) }
    var cancelPaste: (() -> Void)?
    override func cancelOperation(_ sender: Any?) {
        if let drag = imageDrag { imageDrag = nil; drag.finish(nil); needsDisplay = true; return }
        if cancelMarkedSelection() { return }
        if !isEditable { cancelPaste?() }
        else { _ = nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender) }
    }
    override func paste(_ sender: Any?) { handlePaste?(false) }
    override func pasteAsPlainText(_ sender: Any?) { handlePaste?(true) }
    override func pasteAsRichText(_ sender: Any?) { handlePaste?(false) }
    override func mouseDown(with event: NSEvent) {
        dismissLinkPreview?()
        let point = convert(event.locationInWindow, from: nil), raw = string as NSString
        if let rect = selectedImageRect(), resizeHandle(rect).insetBy(dx: -4, dy: -4).contains(point),
           let finish = beginImageResize?(selectedRange().location) {
            window?.makeFirstResponder(self); imageDrag = .init(original: rect, start: point, finish: finish, preview: rect); return
        }
        if let index = imageIndex(at: point), isEditable, isRichText {
            if event.clickCount == 2 { imageAction?(index, "edit") }
            else { window?.makeFirstResponder(self); setSelectedRange(NSRange(location: index, length: 1)); needsDisplay = true }
            return
        }
        let index = min(characterIndexForInsertion(at: point), raw.length)
        if isEditable, isRichText, raw.length > 0 {
            let paragraph = raw.paragraphRange(for: NSRange(location: index, length: 0))
            if paragraph.length > 0,
               let block = MacBlockPrefix(attributedString().attribute(.macBlock, at: paragraph.location, effectiveRange: nil) as? String ?? ""), block.checklist,
               let checkbox = block.display.firstIndex(where: { $0 == "☐" || $0 == "☑" }),
               let layoutManager, let textContainer {
                let character = paragraph.location + block.display[..<checkbox].utf16.count
                guard character < NSMaxRange(paragraph), ["☐", "☑"].contains(raw.substring(with: NSRange(location: character, length: 1))) else { super.mouseDown(with: event); return }
                let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: character, length: 1), actualCharacterRange: nil)
                let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                if bounds.contains(point) { window?.makeFirstResponder(self); toggleChecklist?(paragraph.location); return }
            }
        }
        super.mouseDown(with: event)
    }
}
