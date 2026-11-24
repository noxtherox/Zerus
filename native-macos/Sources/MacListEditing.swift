import AppKit
import Markdown

/// Structural list moves operate on native paragraph payloads, not just source
/// indentation. An outdented child goes after all of its parent's content.
@MainActor enum MacListEditing {
    struct Edit {
        let text: NSAttributedString
        let selection: NSRange
        let typing: [NSAttributedString.Key: Any]?
        init(text: NSAttributedString, selection: NSRange, typing: [NSAttributedString.Key: Any]? = nil) {
            self.text = text; self.selection = selection; self.typing = typing
        }
    }
    enum Outcome {
        case notList, unchanged, refused(String?), changed(Edit)
    }
    private static func innerParagraphGap(source: String, quotes: String, ending: String) -> String {
        let prefix = MacBlockPrefix(source)
        if quotes.isEmpty { return (prefix?.quotes ?? "").trimmingCharacters(in: .whitespaces) + ending }
        return (prefix?.listContinuation ?? "") + quotes.trimmingCharacters(in: .whitespaces) + ending
    }

    /// An inner text block splits inside its existing item. Ordinary flat-list
    /// Return still creates a sibling through the coordinator's existing path.
    static func splittingInnerBlock(_ original: NSAttributedString, paragraph: NSRange, cursor: Int, context: MacListContext, ending: String) -> Outcome {
        guard !context.suffix.isEmpty || context.blockParagraph else { return .notList }
        let raw = original.string as NSString
        let terminated = raw.substring(with: paragraph).hasSuffix("\n")
        let sourceTerminated = terminated && !(NSMaxRange(paragraph) == original.length && original.attribute(.macUnterminated, at: NSMaxRange(paragraph) - 1, effectiveRange: nil) as? Bool == true)
        let bodyStart = paragraph.location + (context.continuation ? 0 : MacMarkdown.displayPrefix(context.source).utf16.count)
        let bodyEnd = NSMaxRange(paragraph) - (terminated ? 1 : 0)
        guard cursor >= bodyStart, cursor <= bodyEnd else { return .refused(nil) }
        let heading = MacBlockPrefix(context.textBlock)?.heading == true
        let quotes = String(context.suffix.prefix { $0 == ">" || $0.isWhitespace })
        let leftPlain = heading && cursor == bodyStart && bodyEnd > bodyStart
        let rightPlain = context.quoteLeaf || heading && cursor == bodyEnd
        let rightQuotes = context.quoteLeaf ? context.parentQuotes : quotes
        let leftContext = MacListContext(id: context.id, source: context.source, continuation: context.continuation, gap: context.gap, originatedAfterChildren: context.originatedAfterChildren, suffix: leftPlain ? quotes : context.suffix, blockParagraph: context.blockParagraph || leftPlain, quoteLeaf: !leftPlain && context.quoteLeaf, quoteParents: context.quoteParents)
        // Explicit paragraphs need a separator only when neither half is a
        // heading. Inside quotes that separator must keep the quote container.
        let separator = heading ? "" : innerParagraphGap(source: context.source, quotes: rightQuotes, ending: ending)
        let rightContext = MacListContext(id: context.id, source: context.source, continuation: true, gap: separator, originatedAfterChildren: context.originatedAfterChildren, suffix: rightPlain ? rightQuotes : context.suffix, blockParagraph: context.blockParagraph || rightPlain, quoteLeaf: !rightPlain && context.quoteLeaf, quoteParents: context.quoteParents)
        func attributes(_ context: MacListContext) -> [NSAttributedString.Key: Any] {
            [.macListContext: context, .macBlock: context.block, .macLineEnding: ending, .paragraphStyle: context.style, .font: MacMarkdown.font(context.textBlock), .foregroundColor: NSColor.labelColor, .macStrong: false, .macIndependentParagraph: false]
        }
        func half(_ range: NSRange, context: MacListContext, empty: Bool, newline: Bool) -> NSAttributedString {
            let result = NSMutableAttributedString(attributedString: original.attributedSubstring(from: range))
            let all = NSRange(location: 0, length: result.length)
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macEmptyParagraph, .macListGap, .macHardBreak] { result.removeAttribute(key, range: all) }
            result.enumerateAttributes(in: all) { old, part, _ in
                let font = old[.font] as? NSFont ?? MacMarkdown.font(context.textBlock)
                let traits = NSFontManager.shared.traits(of: font)
                result.addAttribute(.font, value: MacMarkdown.inlineFont(block: context.textBlock, bold: old[.macStrong] as? Bool ?? false, italic: traits.contains(.italicFontMask), code: traits.contains(.fixedPitchFontMask)), range: part)
            }
            var attrs = attributes(context)
            // Font and inline traits stay local to their original text runs.
            attrs.removeValue(forKey: .font); attrs.removeValue(forKey: .macStrong)
            result.addAttributes(attrs, range: all)
            if empty && !context.quoteLeaf { result.addAttribute(.macEmptyParagraph, value: true, range: all) }
            if newline {
                var terminator = attributes(context)
                if empty && !context.quoteLeaf { terminator[.macEmptyParagraph] = true }
                result.append(NSAttributedString(string: "\n", attributes: terminator))
            }
            return result
        }
        let left = half(NSRange(location: paragraph.location, length: cursor - paragraph.location), context: leftContext, empty: cursor == bodyStart, newline: true)
        // A final empty paragraph needs a real native row to carry its role and
        // invisible source anchor. Return intentionally terminates that row.
        let right = half(NSRange(location: cursor, length: bodyEnd - cursor), context: rightContext, empty: cursor == bodyEnd, newline: sourceTerminated || cursor == bodyEnd)
        let replacement = NSMutableAttributedString(attributedString: left); replacement.append(right)
        let result = NSMutableAttributedString(attributedString: original); result.replaceCharacters(in: paragraph, with: replacement)
        var typing = attributes(rightContext)
        if bodyEnd > bodyStart {
            let at = min(cursor, bodyEnd - 1), inline = original.attributes(at: at, effectiveRange: nil)
            let font = inline[.font] as? NSFont ?? MacMarkdown.font(context.textBlock)
            let traits = NSFontManager.shared.traits(of: font)
            let bold = MacMarkdown.inlineBold(inline, block: context.textBlock)
            typing[.macStrong] = bold
            typing[.font] = MacMarkdown.inlineFont(block: rightContext.textBlock, bold: bold, italic: traits.contains(.italicFontMask), code: traits.contains(.fixedPitchFontMask))
            typing[.strikethroughStyle] = inline[.strikethroughStyle]
            // A split within a link keeps its inline identity. At an edge,
            // ordinary text typed into the new paragraph starts without a link.
            if cursor > bodyStart, cursor < bodyEnd { typing[.link] = inline[.link] }
        }
        return .changed(Edit(text: result, selection: NSRange(location: paragraph.location + left.length, length: 0), typing: typing))
    }

    /// Selections crossing inner roles retain the final block instead of
    /// flattening its suffix into the first block. First ask the ordinary list
    /// planner to validate removal and reconcile any intervening item structure.
    static func splittingSelectedInnerBlocks(_ original: NSAttributedString, range: NSRange, typing: [NSAttributedString.Key: Any]) -> Outcome {
        guard range.length > 0, range.location < original.length, NSMaxRange(range) <= original.length else { return .notList }
        let raw = original.string as NSString
        let first = raw.paragraphRange(for: NSRange(location: range.location, length: 0)), last = raw.paragraphRange(for: NSRange(location: min(NSMaxRange(range), raw.length - 1), length: 0))
        guard first != last,
              let start = original.attribute(.macListContext, at: first.location, effectiveRange: nil) as? MacListContext,
              let end = original.attribute(.macListContext, at: last.location, effectiveRange: nil) as? MacListContext,
              start.id == end.id, end.continuation,
              start.suffix != end.suffix else { return .notList }
        let removal: Edit
        switch replacingSelection(original, range: range, replacement: NSAttributedString(), typing: typing, forParagraphSplit: true) {
        case .changed(let edit): removal = edit
        case .refused(let issue): return .refused(issue)
        case .notList, .unchanged: return .notList
        }
        let message = "This list needs Markdown source editing before this selection can preserve its item relationships."
        let checked = removal.text, cursor = removal.selection.location
        guard checked.length > 0, cursor <= checked.length else { return .refused(message) }
        let merged = (checked.string as NSString).paragraphRange(for: NSRange(location: min(cursor, checked.length - 1), length: 0))
        guard let head = checked.attribute(.macListContext, at: merged.location, effectiveRange: nil) as? MacListContext,
              let prefix = MacBlockPrefix(head.source) else { return .refused(message) }
        let nativeTerminated = raw.substring(with: last).hasSuffix("\n")
        let terminated = nativeTerminated && !(NSMaxRange(last) == original.length && original.attribute(.macUnterminated, at: NSMaxRange(last) - 1, effectiveRange: nil) as? Bool == true)
        let bodyEnd = NSMaxRange(last) - (nativeTerminated ? 1 : 0)
        guard NSMaxRange(range) <= bodyEnd else { return .notList }
        let endingAt = nativeTerminated ? NSMaxRange(last) - 1 : max(0, first.location - 1)
        let ending = original.attribute(.macLineEnding, at: endingAt, effectiveRange: nil) as? String ?? "\n"
        let left = NSMutableAttributedString(attributedString: checked.attributedSubstring(from: NSRange(location: merged.location, length: cursor - merged.location)))
        let right = NSMutableAttributedString(attributedString: original.attributedSubstring(from: NSRange(location: NSMaxRange(range), length: bodyEnd - NSMaxRange(range))))
        func attributes(_ context: MacListContext) -> [NSAttributedString.Key: Any] {
            [.macListContext: context, .macBlock: context.block, .macLineEnding: ending, .paragraphStyle: context.style, .font: MacMarkdown.font(context.textBlock), .macStrong: false, .foregroundColor: NSColor.labelColor, .macIndependentParagraph: false]
        }
        func restyle(_ value: NSMutableAttributedString, context: MacListContext) {
            let all = NSRange(location: 0, length: value.length)
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListGap] { value.removeAttribute(key, range: all) }
            value.enumerateAttributes(in: all) { old, part, _ in
                let font = old[.font] as? NSFont ?? MacMarkdown.font(end.textBlock), traits = NSFontManager.shared.traits(of: font)
                let bold = MacMarkdown.inlineBold(old, block: end.textBlock)
                value.addAttributes([.font: MacMarkdown.inlineFont(block: context.textBlock, bold: bold, italic: traits.contains(.italicFontMask), code: traits.contains(.fixedPitchFontMask)), .macStrong: bold, .macListContext: context, .macBlock: context.block, .paragraphStyle: context.style, .macLineEnding: ending], range: part)
            }
        }
        func items(_ text: NSAttributedString) -> [MacMarkdown.NativeListItem]? {
            if let items = MacMarkdown.nativeListItems(in: text) { return items }
            guard let region = MacMarkdown.nativeListRegion(in: text, around: merged.location),
                  let local = MacMarkdown.nativeListItems(in: text.attributedSubstring(from: region)) else { return nil }
            return local.map { MacMarkdown.NativeListItem(range: NSRange(location: region.location + $0.range.location, length: $0.range.length), block: $0.block, parent: $0.parent, container: $0.container) }
        }
        func edges(_ text: NSAttributedString, _ items: [MacMarkdown.NativeListItem]) -> [UUID: String]? {
            var result: [UUID: String] = [:]
            for item in items {
                guard let context = text.attribute(.macListContext, at: item.range.location, effectiveRange: nil) as? MacListContext, result[context.id] == nil else { return nil }
                let parent = item.parent.flatMap { text.attribute(.macListContext, at: items[$0].range.location, effectiveRange: nil) as? MacListContext }
                result[context.id] = parent?.id.uuidString ?? ""
            }
            return result
        }
        guard let before = items(checked), var expected = edges(checked, before) else { return .refused(message) }
        let output = NSMutableAttributedString(attributedString: checked)
        let result: Edit
        if !head.suffix.isEmpty || head.blockParagraph {
            // Keep the surviving final block after the new paragraph created
            // inside the first role. In particular, plain text stays out of quotes.
            let tail = end.replacing(source: head.source)
            restyle(right, context: tail)
            left.append(NSAttributedString(string: "\n", attributes: attributes(head)))
            if right.length > 0 {
                if terminated { right.append(NSAttributedString(string: "\n", attributes: attributes(tail))) }
                left.append(right)
            }
            output.replaceCharacters(in: merged, with: left)
            let row = (output.string as NSString).paragraphRange(for: NSRange(location: merged.location, length: 0))
            guard case .changed(let edit) = splittingInnerBlock(output, paragraph: row, cursor: cursor, context: head, ending: ending) else { return .refused(message) }
            result = edit
        } else {
            // A flat item's Return creates a sibling. The surviving final role
            // becomes that sibling's first block, rather than losing its role.
            let next = prefix.next, padding = (MacBlockPrefix(next)?.listPadding ?? 0) - prefix.listPadding
            let sibling = MacListContext(source: next, suffix: end.suffix, blockParagraph: end.blockParagraph, quoteLeaf: end.quoteLeaf, quoteParents: end.quoteParents)
            expected[sibling.id] = expected[head.id]
            let descendants = before.filter { item in
                guard item.range.location >= NSMaxRange(merged) else { return false }
                var parent = item.parent
                while let index = parent {
                    let context = checked.attribute(.macListContext, at: before[index].range.location, effectiveRange: nil) as? MacListContext
                    if context?.id == head.id { return true }
                    parent = before[index].parent
                }
                return false
            }
            for item in descendants where item.parent.map({ (checked.attribute(.macListContext, at: before[$0].range.location, effectiveRange: nil) as? MacListContext)?.id == head.id }) == true {
                if let context = checked.attribute(.macListContext, at: item.range.location, effectiveRange: nil) as? MacListContext { expected[context.id] = sibling.id.uuidString }
            }
            let following = NSRange(location: NSMaxRange(merged), length: checked.length - NSMaxRange(merged))
            checked.enumerateAttribute(.macListContext, in: following) { value, range, _ in
                guard let tail = value as? MacListContext else { return }
                if tail.id == head.id, tail.continuation {
                    let rebased = tail.replacing(source: next)
                    let context = MacListContext(id: sibling.id, source: next, continuation: true, gap: rebased.gap, originatedAfterChildren: tail.originatedAfterChildren, suffix: tail.suffix, blockParagraph: tail.blockParagraph, quoteLeaf: tail.quoteLeaf, quoteParents: tail.quoteParents)
                    output.addAttributes([.macListContext: context, .macBlock: context.block, .paragraphStyle: context.style], range: range)
                } else if tail.quoteParents.contains(where: { $0.id == head.id }) {
                    let parents = tail.quoteParents.map { $0.id == head.id ? sibling : $0 }
                    let context = tail.replacing(source: tail.source, quoteParents: parents)
                    output.addAttributes([.macListContext: context, .macBlock: context.block, .paragraphStyle: context.style], range: range)
                }
            }
            checked.enumerateAttribute(.macListGap, in: following) { value, range, _ in
                if let gap = value as? MacListGap, gap.parent == head.id { output.addAttribute(.macListGap, value: MacListGap(parent: sibling.id, child: gap.child), range: range) }
            }
            if padding != 0 {
                for item in descendants.reversed() {
                    let source = item.block.shiftingIndentation(by: padding, atQuoteDepth: prefix.depth)
                    output.replaceCharacters(in: item.range, with: MacMarkdown.settingBlock(output.attributedSubstring(from: item.range), to: source))
                }
            }
            restyle(right, context: sibling)
            let marker = MacMarkdown.displayPrefix(next)
            var siblingAttributes = attributes(sibling)
            if right.length == 0 { siblingAttributes[.macEmptyParagraph] = true }
            right.insert(NSAttributedString(string: marker, attributes: siblingAttributes), at: 0)
            if terminated || right.length == marker.utf16.count { right.append(NSAttributedString(string: "\n", attributes: siblingAttributes)) }
            left.append(NSAttributedString(string: "\n", attributes: attributes(head))); let caret = merged.location + left.length + marker.utf16.count
            var typing = right.attributes(at: min(marker.utf16.count, right.length - 1), effectiveRange: nil)
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macLiteral, .attachment] { typing.removeValue(forKey: key) }
            left.append(right); output.replaceCharacters(in: merged, with: left)
            result = Edit(text: output, selection: NSRange(location: caret, length: 0), typing: typing)
        }
        guard let after = items(result.text), edges(result.text, after) == expected else { return .refused(message) }
        return .changed(result)
    }

    private struct Unit {
        let range: NSRange
        var text: NSAttributedString
        let owner: Int?
    }
    private struct Anchor { let unit: Int; let local: Int }
    private static func unitRange(in text: NSAttributedString, at offset: Int) -> NSRange {
        for key in [NSAttributedString.Key.macCode, .macTable] where text.attribute(key, at: offset, effectiveRange: nil) != nil {
            var range = NSRange()
            _ = text.attribute(key, at: offset, longestEffectiveRange: &range, in: NSRange(location: 0, length: text.length))
            if range.location == offset { return range }
        }
        return (text.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
    }
    private static let issue = "This list needs Markdown source editing before its items can be moved safely."
    private static let formattingIssue = "This list needs Markdown source editing before its paragraph format can be changed."

    private struct IndependentParagraph {
        let range: NSRange
        let text: NSAttributedString
        let source: String
    }
    /// A root paragraph's imported spelling may contain insignificant spaces.
    /// Re-spell just its prefix when a preceding boundary edit would make those
    /// spaces attach it to a list. Inline attributes and image literals stay put.
    private static func independentParagraph(in original: NSAttributedString, at paragraph: NSRange) -> IndependentParagraph? {
        let attrs = original.attributes(at: paragraph.location, effectiveRange: nil)
        guard attrs[.macListContext] == nil, attrs[.macCode] == nil, attrs[.macTable] == nil, attrs[.macCodeSeparator] == nil,
              MacBlockPrefix(attrs[.macBlock] as? String ?? "")?.list != true else { return nil }
        var range = paragraph
        if attrs[.macParagraphID] != nil {
            var group = NSRange()
            _ = original.attribute(.macParagraphID, at: paragraph.location, longestEffectiveRange: &group, in: NSRange(location: 0, length: original.length))
            if group.location == paragraph.location { range = group }
        }
        let value = original.attributedSubstring(from: range), source = MacMarkdown.markdown(value)
        let normalized = MacMarkdown.withoutStructuralIndentation(source)
        guard normalized != source else { return nil }
        let document = Document(parsing: source)
        guard document.childCount == 1, var block = document.child(at: 0) else { return nil }
        while block is BlockQuote, block.childCount == 1, let child = block.child(at: 0) { block = child }
        guard block is Paragraph || block is Heading || block is HTMLBlock else { return nil }
        let result = NSMutableAttributedString(attributedString: value), full = NSRange(location: 0, length: value.length)
        let prefix = MacMarkdown.withoutStructuralIndentation(attrs[.macBlock] as? String ?? "")
        result.addAttributes([.macBlock: prefix, .paragraphStyle: MacMarkdown.paragraphStyle(prefix)], range: full)
        // This is a new source spelling of the same native paragraph, using the
        // same invalidation rule as imported paragraph tokens. Later text or
        // style edits invalidate it normally; Undo keeps the original snapshot.
        result.addAttributes([.macParagraphID: UUID().uuidString, .macParagraphSource: normalized, .macParagraphSignature: MacMarkdown.signature(result)], range: full)
        return IndependentParagraph(range: range, text: result, source: source)
    }
    private static func wouldAdopt(_ paragraph: IndependentParagraph, prefix: NSAttributedString, range: NSRange, replacement: NSAttributedString) -> Bool {
        let before = NSMutableAttributedString(attributedString: prefix)
        before.replaceCharacters(in: range, with: replacement)
        let source = MacMarkdown.markdown(before)
        var line = 1, previousCR = false
        for byte in source.utf8 {
            if byte == 13 { line += 1; previousCR = true }
            else { if byte == 10 && !previousCR { line += 1 }; previousCR = false }
        }
        var adopted = false
        func inspect(_ node: any Markup) {
            if (node is Paragraph || node is Heading || node is HTMLBlock), node.range?.lowerBound.line == line {
                var owner = node.parent
                while let ancestor = owner { if ancestor is ListItem { adopted = true; break }; owner = ancestor.parent }
            }
            for child in node.children { inspect(child) }
        }
        inspect(Document(parsing: source + paragraph.source))
        return adopted
    }

    private enum ListKind { case bullet, number, check, numberedCheck }
    /// Lexical merges adjacent lists of the same kind even when CommonMark
    /// gives their different bullet/delimiter spellings separate containers.
    /// Only document/blockquote siblings alias; nested list wrappers retain
    /// their source order and identity. Numbered native tasks remain distinct.
    private static func semanticContainers(_ items: [MacMarkdown.NativeListItem], in text: NSAttributedString) -> (aliases: [Int: Int], kinds: [Int: ListKind]) {
        let grouped = Dictionary(grouping: items.indices, by: { items[$0].container })
        let kinds: [Int: ListKind] = grouped.mapValues { rows in
            let ordered = items[rows[0]].block.marker.first?.isNumber == true
            return rows.contains { items[$0].block.checklist } ? (ordered ? .numberedCheck : .check) : (ordered ? .number : .bullet)
        }
        var next = 0, aliases: [Int: Int] = [:]
        func collect(_ node: any Markup, alias: Int? = nil) {
            if node is OrderedList || node is UnorderedList { aliases[next] = alias ?? next; next += 1 }
            var previous: (kind: ListKind, container: Int)?
            for child in node.children {
                if child is OrderedList || child is UnorderedList {
                    let id = next, kind = kinds[id] ?? .bullet
                    let canonical = (node is Document || node is BlockQuote) && previous?.kind == kind ? previous!.container : id
                    collect(child, alias: canonical); previous = (kind, canonical)
                } else { collect(child); previous = nil }
            }
        }
        collect(Document(parsing: MacMarkdown.markdown(text)))
        return (aliases, kinds)
    }

    private static func paragraphPasteTyping(_ previous: [NSAttributedString.Key: Any], block: String, ending: String) -> [NSAttributedString.Key: Any] {
        var attributes = previous
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListContext, .macListGap, .macLiteral, .attachment, .macImageUnavailable, .macHardBreak, .macListBreak, .link, .backgroundColor] { attributes.removeValue(forKey: key) }
        attributes[.macBlock] = block; attributes[.paragraphStyle] = MacMarkdown.paragraphStyle(block); attributes[.font] = MacMarkdown.font(block); attributes[.macStrong] = false; attributes[.macLineEnding] = ending
        return attributes
    }

    /// Keep carets outside presentation-only prefixes and the EOF row terminator.
    static func caretInputRange(in original: NSAttributedString, range: NSRange) -> NSRange {
        if range.length == 0, range.location == original.length, original.length > 0,
           original.attribute(.macUnterminated, at: original.length - 1, effectiveRange: nil) as? Bool == true {
            return NSRange(location: original.length - 1, length: 0)
        }
        guard range.length == 0, range.location < original.length,
              MacBlockPrefix(original.attribute(.macBlock, at: range.location, effectiveRange: nil) as? String ?? "")?.list == true else { return range }
        if case .range(let checked, _) = bodySelection(in: original, range: range) { return checked }
        return range
    }

    private enum BodySelection {
        case range(NSRange, marker: Bool)
        case boundary, missingMarker
    }
    /// Structural prefixes are presentation. Both inline replacement and block
    /// paste select the same body bytes, with an exclusive next-row end kept out.
    private static func bodySelection(in original: NSAttributedString, range: NSRange, forParagraphSplit: Bool = false) -> BodySelection {
        let raw = original.string as NSString, end = NSMaxRange(range)
        let first = raw.paragraphRange(for: NSRange(location: min(range.location, raw.length - 1), length: 0))
        let last = raw.paragraphRange(for: NSRange(location: min(end, raw.length - 1), length: 0))
        let firstMarker = MacMarkdown.displayPrefix(original.attribute(.macBlock, at: first.location, effectiveRange: nil) as? String ?? "")
        let lastMarker = MacMarkdown.displayPrefix(original.attribute(.macBlock, at: last.location, effectiveRange: nil) as? String ?? "")
        guard forParagraphSplit || range.length == 0 || end != last.location || lastMarker.isEmpty else { return .boundary }
        let lower = first.location + firstMarker.utf16.count, upper = last.location + lastMarker.utf16.count
        let marker = range.location < lower || end < upper
        guard marker else { return .range(range, marker: false) }
        guard raw.substring(with: first).hasPrefix(firstMarker), raw.substring(with: last).hasPrefix(lastMarker) else { return .missingMarker }
        let start = max(range.location, lower)
        return .range(NSRange(location: start, length: max(end, upper) - start), marker: true)
    }

    /// A heading/quote inside an item accepts pasted text bodies without
    /// closing its item or promoting its existing children. Inline traits and
    /// explicit breaks remain on their own runs; source tokens cannot be reused.
    private static func pastingInnerText(_ original: NSAttributedString, range: NSRange, body: NSAttributedString, context: MacListContext, ending: String, typing: [NSAttributedString.Key: Any]) -> Edit {
        let value = NSMutableAttributedString(attributedString: body)
        let raw = value.string as NSString
        for index in (0..<raw.length).reversed() where raw.character(at: index) == 10 {
            var attrs = value.attributes(at: index, effectiveRange: nil)
            attrs[.macListBreak] = 3
            value.replaceCharacters(in: NSRange(location: index, length: 1), with: NSAttributedString(string: "\u{2028}", attributes: attrs))
        }
        let all = NSRange(location: 0, length: value.length)
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListContext, .macListGap, .macEmptyParagraph] { value.removeAttribute(key, range: all) }
        value.enumerateAttributes(in: all) { attrs, part, _ in
            let block = attrs[.macBlock] as? String ?? "", font = attrs[.font] as? NSFont ?? MacMarkdown.font(block)
            let traits = NSFontManager.shared.traits(of: font), bold = MacMarkdown.inlineBold(attrs, block: block)
            value.addAttributes([.font: MacMarkdown.inlineFont(block: context.textBlock, bold: bold, italic: traits.contains(.italicFontMask), code: traits.contains(.fixedPitchFontMask)), .macStrong: bold], range: part)
        }
        value.addAttributes([.macListContext: context, .macBlock: context.block, .paragraphStyle: context.style, .macIndependentParagraph: false, .macLineEnding: ending], range: all)
        let output = NSMutableAttributedString(attributedString: original)
        output.replaceCharacters(in: range, with: value)
        var next = paragraphPasteTyping(typing, block: context.block, ending: ending)
        next[.macListContext] = context; next[.macIndependentParagraph] = false
        next[.paragraphStyle] = context.style; next[.font] = MacMarkdown.font(context.textBlock)
        return Edit(text: output, selection: NSRange(location: range.location + value.length, length: 0), typing: next)
    }

    /// Insert paragraph blocks as one checked edit. First merge the selected
    /// bodies using the existing ownership planner, then close their containers
    /// at the new paragraph boundary with the block-formatting planner.
    static func pastingParagraphs(_ original: NSAttributedString, range: NSRange, paragraphs: [MacMarkdown.PasteParagraph], flattenQuote: Bool = true, typing: [NSAttributedString.Key: Any]) -> Outcome {
        guard paragraphs.count > 1, original.length > 0, range.location < original.length || range.location == original.length && !original.string.hasSuffix("\n"), NSMaxRange(range) <= original.length else { return .notList }
        var range = range
        let raw = original.string as NSString
        let first = raw.paragraphRange(for: NSRange(location: min(range.location, raw.length - 1), length: 0))
        let last = raw.paragraphRange(for: NSRange(location: min(NSMaxRange(range), original.length - 1), length: 0))
        let block = original.attribute(.macBlock, at: first.location, effectiveRange: nil) as? String ?? ""
        switch bodySelection(in: original, range: range) {
        case .range(let checked, _): range = checked
        case .boundary: return .notList
        case .missingMarker: return .refused("This paste needs Markdown source editing to preserve its paragraph boundaries.")
        }
        let endingIndex = raw.substring(with: first).hasSuffix("\n") ? NSMaxRange(first) - 1 : max(0, first.location - 1)
        let ending = original.attribute(.macLineEnding, at: endingIndex, effectiveRange: nil) as? String ?? "\n"
        if flattenQuote, first == last,
           let context = original.attribute(.macListContext, at: first.location, effectiveRange: nil) as? MacListContext, !context.suffix.isEmpty {
            let joined = NSMutableAttributedString()
            for paragraph in paragraphs { joined.append(paragraph.text) }
            return .changed(pastingInnerText(original, range: range, body: joined, context: context, ending: ending, typing: typing))
        }
        // Lexical's plain quote node accepts inline children: pasted paragraph
        // bodies join inside that quote rather than creating outside paragraphs.
        if flattenQuote, first == last, let prefix = MacBlockPrefix(block), prefix.depth > 0, !prefix.list, !prefix.heading,
           original.attribute(.macListContext, at: first.location, effectiveRange: nil) == nil {
            let joined = NSMutableAttributedString()
            for paragraph in paragraphs { joined.append(paragraph.text) }
            let output = NSMutableAttributedString(attributedString: original)
            output.replaceCharacters(in: range, with: joined)
            let row = (output.string as NSString).paragraphRange(for: NSRange(location: first.location, length: 0))
            let value = NSMutableAttributedString(attributedString: MacMarkdown.settingBlock(output.attributedSubstring(from: row), to: block, collapsingParagraphs: false))
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature] { value.removeAttribute(key, range: NSRange(location: 0, length: value.length)) }
            let delta = value.length - row.length
            output.replaceCharacters(in: row, with: value)
            return .changed(Edit(text: output, selection: NSRange(location: range.location + joined.length + delta, length: 0), typing: paragraphPasteTyping(typing, block: block, ending: ending)))
        }
        let flat = NSMutableAttributedString()
        var breaks: [Int] = []
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 {
                breaks.append(flat.length)
                flat.append(NSAttributedString(string: "\u{2028}\u{2028}", attributes: [.macListBreak: 2, .macLineEnding: ending]))
            }
            flat.append(paragraph.text)
        }
        flat.addAttribute(.macLineEnding, value: ending, range: NSRange(location: 0, length: flat.length))
        var merged: NSAttributedString, caret: Int
        switch replacingSelection(original, range: range, replacement: flat, typing: typing) {
        case .changed(let edit): merged = edit.text; caret = edit.selection.location
        case .refused(let message): return .refused(message)
        case .notList, .unchanged:
            guard first == last else { return .notList }
            let value = NSMutableAttributedString(attributedString: original)
            value.replaceCharacters(in: range, with: flat)
            let row = (value.string as NSString).paragraphRange(for: NSRange(location: first.location, length: 0))
            let payload = NSMutableAttributedString(attributedString: MacMarkdown.settingBlock(value.attributedSubstring(from: row), to: block, collapsingParagraphs: false))
            if let context = original.attribute(.macListContext, at: first.location, effectiveRange: nil) as? MacListContext,
               context.continuation, let head = MacMarkdown.listHeadParagraph(in: original, paragraph: first), head != first {
                payload.addAttributes([.macListContext: context, .macBlock: context.block, .paragraphStyle: context.style, .macIndependentParagraph: false], range: NSRange(location: 0, length: payload.length))
            }
            let delta = payload.length - row.length
            value.replaceCharacters(in: row, with: payload); merged = value
            caret = range.location + flat.length + delta
        }
        let output = NSMutableAttributedString(attributedString: merged)
        let start = caret - flat.length
        guard start >= 0, caret <= output.length, let firstBreak = breaks.first else { return .notList }
        let headRange = (output.string as NSString).paragraphRange(for: NSRange(location: start, length: 0))
        let head = output.attributes(at: headRange.location, effectiveRange: nil)
        let context = head[.macListContext] as? MacListContext
        let source = context?.source ?? (head[.macBlock] as? String ?? block)
        for local in breaks.reversed() {
            var attrs = head; attrs[.macLineEnding] = ending
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListBreak, .macHardBreak] { attrs.removeValue(forKey: key) }
            output.replaceCharacters(in: NSRange(location: start + local, length: 2), with: NSAttributedString(string: "\n", attributes: attrs))
        }
        caret -= breaks.count
        // Retain the receiving paragraph's final terminator when a complete
        // replacement selected it; paragraph bodies omit clipboard terminators.
        if NSMaxRange(range) == original.length, raw.substring(from: NSMaxRange(last) - 1) == "\n", !output.string.hasSuffix("\n") {
            output.append(NSAttributedString(string: "\n", attributes: [.macBlock: source, .macLineEnding: ending]))
        }
        let right = start + firstBreak + 1
        let starts = [start] + breaks.enumerated().map { start + $0.element + 1 - $0.offset }
        for (index, position) in starts.enumerated() {
            // A synthetic empty suffix still needs its own row: formatting
            // an EOF position would otherwise change the preceding list head.
            if position == output.length, index > 0 || paragraphs[index].empty {
                output.append(NSAttributedString(string: "\n", attributes: [.macEmptyParagraph: true, .macLineEnding: ending]))
            }
            guard position < output.length else { continue }
            let row = (output.string as NSString).paragraphRange(for: NSRange(location: position, length: 0))
            output.addAttribute(.macEmptyParagraph, value: index > 0 || paragraphs[index].empty || head[.macEmptyParagraph] as? Bool == true, range: row)
            if index > 0 {
                if let context {
                    let tail = MacListContext(id: context.id, source: source, continuation: true, gap: "", originatedAfterChildren: false, quoteParents: context.quoteParents)
                    output.addAttributes([.macListContext: tail, .macBlock: tail.block, .paragraphStyle: tail.style], range: row)
                } else {
                    output.addAttributes([.macBlock: source, .paragraphStyle: MacMarkdown.paragraphStyle(source)], range: row)
                }
                for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature] { output.removeAttribute(key, range: row) }
            }
        }
        switch formatting(output, selection: NSRange(location: right, length: max(0, caret - right)), to: "", separateParagraphs: true) {
        case .changed(let edit):
            let prepared = NSMutableAttributedString(attributedString: edit.text)
            var position = NSMaxRange(edit.selection)
            let text = prepared.string as NSString
            // An unselected body tail can still carry the item's logical
            // paragraph separators. Once outside its item, give each paragraph
            // a native row now, matching reopening and later block commands.
            let scope = text.paragraphRange(for: NSRange(location: min(edit.selection.location, max(0, text.length - 1)), length: max(0, edit.selection.length - 1)))
            var breaks: [NSRange] = [], cursor = scope.location
            while cursor < NSMaxRange(scope) {
                let attrs = prepared.attributes(at: cursor, effectiveRange: nil)
                if text.character(at: cursor) == 0x2028, attrs[.macListBreak] as? Int == 2,
                   attrs[.macListContext] == nil, MacBlockPrefix(attrs[.macBlock] as? String ?? "")?.list != true {
                    let pair = cursor + 1 < NSMaxRange(scope) && text.character(at: cursor + 1) == 0x2028 && prepared.attribute(.macListBreak, at: cursor + 1, effectiveRange: nil) as? Int == 2
                    let range = NSRange(location: cursor, length: pair ? 2 : 1)
                    breaks.append(range); cursor = NSMaxRange(range)
                } else { cursor += 1 }
            }
            if !breaks.isEmpty {
                for key in [NSAttributedString.Key.macParagraphID, .macParagraphSource, .macParagraphSignature] { prepared.removeAttribute(key, range: scope) }
                for range in breaks.reversed() {
                    var attrs = prepared.attributes(at: range.location, effectiveRange: nil)
                    for key in [NSAttributedString.Key.macOriginal, .macSignature, .macListBreak, .macHardBreak, .macListGap, .macEmptyParagraph] { attrs.removeValue(forKey: key) }
                    prepared.replaceCharacters(in: range, with: NSAttributedString(string: "\n\n", attributes: attrs))
                    if range.location < position { position += 2 - range.length }
                }
            }
            let target = prepared.attribute(.macBlock, at: min(position, prepared.length - 1), effectiveRange: nil) as? String ?? ""
            let attributes = paragraphPasteTyping(typing, block: target, ending: ending)
            return .changed(Edit(text: prepared, selection: NSRange(location: position, length: 0), typing: attributes))
        case .refused(let message): return .refused(message)
        case .notList, .unchanged: return .notList
        }
    }

    /// Structured payloads retain their blocks and native code/table cards.
    /// First close the receiving item at a real prose boundary, then insert the
    /// independent blocks before its retained suffix and promoted descendants.
    static func pastingBlocks(_ original: NSAttributedString, range: NSRange, blocks: NSAttributedString, firstBody: MacMarkdown.PasteParagraph? = nil, lastBody: MacMarkdown.PasteParagraph? = nil, typing: [NSAttributedString.Key: Any]) -> Outcome {
        guard original.length > 0, range.location < original.length || range.location == original.length && !original.string.hasSuffix("\n"), blocks.length > 0,
              NSMaxRange(range) <= original.length else { return .notList }
        let raw = original.string as NSString
        let first = raw.paragraphRange(for: NSRange(location: min(range.location, raw.length - 1), length: 0))
        let firstBlock = original.attribute(.macBlock, at: first.location, effectiveRange: nil) as? String ?? ""
        var hasCards = false
        blocks.enumerateAttributes(in: NSRange(location: 0, length: blocks.length)) { attrs, _, stop in
            if attrs[.macCode] is MacRichCode || attrs[.macTable] is MacRichTable || attrs[.macRule] != nil { hasCards = true; stop.pointee = true }
        }
        // Quote nodes and item-owned text containers accept the inline
        // bodies of pasted list items. Cards keep the structural path below.
        let context = original.attribute(.macListContext, at: first.location, effectiveRange: nil) as? MacListContext
        let inner = context.map { !$0.suffix.isEmpty } == true
        let quote = MacBlockPrefix(firstBlock).map { $0.depth > 0 && !$0.list && !$0.heading } == true && context == nil
        if !hasCards, inner || quote,
           first == raw.paragraphRange(for: NSRange(location: min(NSMaxRange(range), raw.length - 1), length: 0)) {
            let joined = NSMutableAttributedString(), blockRaw = blocks.string as NSString
            if let firstBody { joined.append(firstBody.text) }
            var offset = 0
            while offset < blocks.length {
                let row = blockRaw.paragraphRange(for: NSRange(location: offset, length: 0))
                let source = blocks.attribute(.macBlock, at: row.location, effectiveRange: nil) as? String ?? ""
                let marker = MacMarkdown.displayPrefix(source).utf16.count
                let terminated = blockRaw.character(at: NSMaxRange(row) - 1) == 10
                let body = NSRange(location: row.location + marker, length: max(0, row.length - marker - (terminated ? 1 : 0)))
                joined.append(blocks.attributedSubstring(from: body))
                // Inner text containers join imported paragraph bodies. Keep
                // explicit inline breaks on their runs, not row separators.
                if !inner, terminated, NSMaxRange(row) < blocks.length, let quote = MacBlockPrefix(source), quote.depth > 0, !quote.list {
                    joined.append(NSAttributedString(string: "\n"))
                }
                offset = NSMaxRange(row)
            }
            if let lastBody { joined.append(lastBody.text) }
            if inner, let context {
                let selected: NSRange
                switch bodySelection(in: original, range: range) {
                case .range(let checked, _): selected = checked
                case .boundary: return .notList
                case .missingMarker: return .refused("This paste needs Markdown source editing to preserve its paragraph boundaries.")
                }
                let ending = original.attribute(.macLineEnding, at: NSMaxRange(first) - 1, effectiveRange: nil) as? String ?? "\n"
                return .changed(pastingInnerText(original, range: selected, body: joined, context: context, ending: ending, typing: typing))
            }
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListContext] { joined.removeAttribute(key, range: NSRange(location: 0, length: joined.length)) }
            joined.addAttributes([.macBlock: firstBlock, .macIndependentParagraph: true, .paragraphStyle: MacMarkdown.paragraphStyle(firstBlock)], range: NSRange(location: 0, length: joined.length))
            let output = NSMutableAttributedString(attributedString: original)
            output.replaceCharacters(in: range, with: joined)
            let ending = original.attribute(.macLineEnding, at: NSMaxRange(first) - 1, effectiveRange: nil) as? String ?? "\n"
            output.addAttribute(.macLineEnding, value: ending, range: NSRange(location: range.location, length: joined.length))
            return .changed(Edit(text: output, selection: NSRange(location: range.location + joined.length, length: 0), typing: paragraphPasteTyping(typing, block: firstBlock, ending: ending)))
        }
        let empty = MacMarkdown.PasteParagraph(text: NSAttributedString(string: ""), empty: false)
        var split: Edit
        switch pastingParagraphs(original, range: range, paragraphs: [firstBody ?? empty, lastBody ?? empty], flattenQuote: !hasCards, typing: typing) {
        case .changed(let edit): split = edit
        case .refused(let issue): return .refused(issue)
        case .notList, .unchanged: return .notList
        }
        let output = NSMutableAttributedString(attributedString: split.text)
        var splitRaw = output.string as NSString
        guard split.selection.location <= output.length else { return .notList }
        var right = splitRaw.paragraphRange(for: split.selection)
        if firstBody == nil, first.location < right.location {
            let left = splitRaw.paragraphRange(for: NSRange(location: first.location, length: 0))
            let source = output.attribute(.macBlock, at: left.location, effectiveRange: nil) as? String ?? ""
            let display = MacMarkdown.displayPrefix(source)
            let text = splitRaw.substring(with: left)
            let body = text.hasPrefix(display) ? String(text.dropFirst(display.count)) : text
            let gap = NSRange(location: NSMaxRange(left), length: max(0, right.location - NSMaxRange(left)))
            var unowned = MacBlockPrefix(source)?.list != true
            if !unowned, let items = MacMarkdown.nativeListItems(in: output), let head = items.firstIndex(where: { $0.range.location == left.location }) {
                unowned = !items.contains(where: { $0.parent == head })
            }
            if unowned, body.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n")).isEmpty,
               splitRaw.substring(with: gap).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let removed = NSRange(location: left.location, length: right.location - left.location)
                output.deleteCharacters(in: removed)
                split = Edit(text: NSAttributedString(attributedString: output), selection: NSRange(location: split.selection.location - removed.length, length: 0), typing: split.typing)
                splitRaw = output.string as NSString
                right = splitRaw.paragraphRange(for: split.selection)
            }
        }
        let rightBlock = right.location < output.length ? output.attribute(.macBlock, at: right.location, effectiveRange: nil) as? String ?? "" : split.typing?[.macBlock] as? String ?? ""
        let rightText = splitRaw.substring(with: right)
        let suffix = String(rightText.dropFirst(MacMarkdown.displayPrefix(rightBlock).count)).trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        let keepRight = NSMaxRange(right) < output.length || !suffix.isEmpty || lastBody?.empty == true
        if !keepRight {
            output.deleteCharacters(in: right)
            split = Edit(text: NSAttributedString(attributedString: output), selection: NSRange(location: right.location, length: 0), typing: split.typing)
            splitRaw = output.string as NSString
            right.length = 0
        }
        let ending = original.attribute(.macLineEnding, at: NSMaxRange(first) - 1, effectiveRange: nil) as? String ?? "\n"
        let payload = NSMutableAttributedString(attributedString: blocks)
        // A quoted list closes into its surrounding quote. Keep pasted blocks
        // in that same quote without changing their own nested list ownership.
        // Native cards are independent root blocks. A surrounding quote can
        // resume in the suffix, but must not absorb or flatten the card body.
        if !rightBlock.isEmpty && !hasCards {
            var offset = 0
            while offset < payload.length {
                let row = (payload.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
                let block = payload.attribute(.macBlock, at: row.location, effectiveRange: nil) as? String ?? ""
                let value = MacMarkdown.settingBlock(payload.attributedSubstring(from: row), to: rightBlock + block, collapsingParagraphs: false)
                payload.replaceCharacters(in: row, with: value)
                offset = row.location + value.length
            }
            payload.setAttributedString(MacMarkdown.refreshingListContexts(payload))
        }
        var insertion = right.location
        // Adjacent lists of the same kind share a container. Preserve a tight
        // list when the receiving head was tight; tails still need their gap.
        if insertion > 0 {
            let gap = splitRaw.paragraphRange(for: NSRange(location: insertion - 1, length: 0))
            if splitRaw.substring(with: gap).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, gap.location > 0 {
                let left = splitRaw.paragraphRange(for: NSRange(location: gap.location - 1, length: 0))
                let leftSource = output.attribute(.macBlock, at: left.location, effectiveRange: nil) as? String ?? ""
                let rightSource = payload.attribute(.macBlock, at: 0, effectiveRange: nil) as? String ?? ""
                if let a = MacBlockPrefix(leftSource), let b = MacBlockPrefix(rightSource), a.list, b.list,
                   a.quotes == b.quotes, a.indent == b.indent, a.checklist == b.checklist,
                   a.marker.first?.isNumber == b.marker.first?.isNumber {
                    if let items = MacMarkdown.nativeListItems(in: payload), let firstItem = items.first {
                        var planned: [Int: MacBlockPrefix] = [:]
                        var ordinal = (Int(a.marker.prefix(while: \.isNumber)) ?? 0) + 1
                        for (index, item) in items.enumerated() {
                            var next = item.block
                            if item.container == firstItem.container, item.parent == nil {
                                let stem = a.marker.first?.isNumber == true ? String(min(999_999_999, ordinal)) + a.marker.dropFirst(a.marker.prefix(while: \.isNumber).count).prefix(1) + " " : String(a.marker.prefix(1)) + " "
                                let checked = item.block.checklist ? (item.block.marker.contains("[ ]") ? "[ ] " : "[x] ") : ""
                                next = MacBlockPrefix(item.block.replacingMarker(stem + checked))!
                                ordinal += 1
                            } else if let parent = item.parent, let target = planned[parent] {
                                let old = items[parent].block
                                next = MacBlockPrefix(item.block.indented(item.block.indent + target.indent + target.listPadding - old.indent - old.listPadding))!
                            }
                            planned[index] = next
                        }
                        for index in items.indices.reversed() where planned[index]?.source != items[index].block.source {
                            payload.replaceCharacters(in: items[index].range, with: MacMarkdown.settingBlock(payload.attributedSubstring(from: items[index].range), to: planned[index]!.source))
                        }
                        payload.setAttributedString(MacMarkdown.refreshingListContexts(payload))
                    }
                    output.deleteCharacters(in: gap); insertion = gap.location
                }
            }
        }
        let payloadRaw = payload.string as NSString
        var contentEnd = payloadRaw.length
        while contentEnd > 0 {
            let attrs = payload.attributes(at: contentEnd - 1, effectiveRange: nil)
            if attrs[.macCodeSeparator] != nil || attrs[.macCellEnd] != nil { contentEnd -= 1; continue }
            if attrs[.macCode] is MacRichCode || attrs[.macCell] is MacRichTable.Cell { break }
            guard [10, 13].contains(payloadRaw.character(at: contentEnd - 1)) else { break }
            contentEnd -= 1
        }
        guard contentEnd > 0 else { return .notList }
        // A card's editable trailing blank lines are content, not the blank
        // paragraph separating that card from the retained suffix.
        var trailing = 0, boundary = payload.length
        while boundary > 0, payloadRaw.character(at: boundary - 1) == 10 {
            let attrs = payload.attributes(at: boundary - 1, effectiveRange: nil)
            if attrs[.macCodeSeparator] != nil || attrs[.macCellEnd] != nil { trailing += 1; break }
            if attrs[.macCode] is MacRichCode || attrs[.macCell] is MacRichTable.Cell { break }
            trailing += 1; boundary -= 1
        }
        while keepRight && trailing < 2 {
            payload.append(NSAttributedString(string: "\n", attributes: [.macBlock: rightBlock, .font: MacMarkdown.font(rightBlock), .paragraphStyle: MacMarkdown.paragraphStyle(rightBlock), .macLineEnding: ending]))
            trailing += 1
        }
        output.insert(payload, at: insertion)
        let caret = lastBody != nil ? insertion + payload.length + split.selection.location - right.location : insertion + contentEnd
        let row = (output.string as NSString).paragraphRange(for: NSRange(location: max(insertion, caret - 1), length: 0))
        let attrs = output.attributes(at: row.location, effectiveRange: nil)
        let block = attrs[.macBlock] as? String ?? ""
        var nextTyping = paragraphPasteTyping(typing, block: block, ending: ending)
        nextTyping[.macListContext] = attrs[.macListContext]
        nextTyping[.paragraphStyle] = attrs[.paragraphStyle]
        // The final card receives follow-up typing inside its body/cell, never
        // in its structural terminator. Middle cards leave prose typing intact.
        if let code = attrs[.macCode] as? MacRichCode { nextTyping = MacRichCode.attributes(code) }
        else if let cell = attrs[.macCell] as? MacRichTable.Cell { nextTyping = cell.attributes }
        nextTyping[.macLineEnding] = ending
        let prepared = MacMarkdown.refreshingListGapOwners(MacMarkdown.refreshingListContexts(output))
        func graph(_ text: NSAttributedString) -> (ids: Set<UUID>, parents: [UUID: UUID])? {
            guard let items = MacMarkdown.nativeListItems(in: text) else { return nil }
            var ids = Set<UUID>(), parents: [UUID: UUID] = [:]
            for item in items {
                guard let context = text.attribute(.macListContext, at: item.range.location, effectiveRange: nil) as? MacListContext else { return nil }
                guard ids.insert(context.id).inserted else { return nil }
                if let parent = item.parent, let owner = text.attribute(.macListContext, at: items[parent].range.location, effectiveRange: nil) as? MacListContext { parents[context.id] = owner.id }
            }
            return (ids, parents)
        }
        let issue = "This paste needs Markdown source editing to preserve its block boundaries."
        guard let added = graph(payload) else { return .refused(issue) }
        if let before = graph(split.text), let after = graph(prepared) {
            guard before.ids.isDisjoint(with: added.ids), before.ids.union(added.ids) == after.ids,
                  before.parents.merging(added.parents, uniquingKeysWith: { a, _ in a }) == after.parents else { return .refused(issue) }
        } else {
            // A temporary list elsewhere cannot change a local prose split.
            // Validate just its prefix, pasted blocks and suffix; no original
            // item is removed or moved by this same-paragraph insertion.
            let last = raw.paragraphRange(for: NSRange(location: min(NSMaxRange(range), raw.length - 1), length: 0))
            let context = original.attribute(.macListContext, at: first.location, effectiveRange: nil) as? MacListContext
            guard first == last, MacBlockPrefix(firstBlock)?.list != true,
                  context == nil || MacMarkdown.listHeadParagraph(in: original, paragraph: first) == first else { return .refused(issue) }
            let end = insertion + payload.length + right.length
            guard first.location <= insertion, end <= prepared.length,
                  let local = graph(prepared.attributedSubstring(from: NSRange(location: first.location, length: end - first.location))),
                  local.ids == added.ids, local.parents == added.parents else { return .refused(issue) }
        }
        return .changed(Edit(text: prepared, selection: NSRange(location: caret, length: 0), typing: nextTyping))
    }

    private struct CardEndpoint {
        let range: NSRange
        let code: MacRichCode?
        let cell: MacRichTable.Cell?
        var key: NSAttributedString.Key { code == nil ? .macTable : .macCode }
        var token: NSObject { if let code { return code }; return cell!.table }
        var ending: String { code?.ending ?? cell!.table.ending }
        var newline: String { code?.original.newline ?? cell!.table.original.newline }
        var quotes: String { code?.quote?.prefix ?? cell?.table.quote?.prefix ?? "" }
    }
    /// Editable text can cross the edge of a structural card. Project partial
    /// endpoints onto plain continuations for the list transaction, then put the
    /// merged text back in the starting model. A partial table preserves every
    /// cell terminator. The projection never reaches the view or Undo.
    /// Atomic rules have no editable body. Project an endpoint onto a plain
    /// paragraph beside the rule, then use the ordinary checked item planner.
    /// This prevents AppKit joining visible text onto an attachment's native row.
    private static func replacingRuleBoundary(_ original: NSAttributedString, range: NSRange, replacement: NSAttributedString, typing: [NSAttributedString.Key: Any]) -> Outcome? {
        let raw = original.string as NSString
        func rule(at index: Int) -> NSRange? {
            guard index < raw.length else { return nil }
            let row = raw.paragraphRange(for: NSRange(location: index, length: 0))
            let attrs = original.attributes(at: row.location, effectiveRange: nil)
            return attrs[.macRule] != nil && attrs[.macListCard] is MacListCardPlacement ? row : nil
        }
        let first = rule(at: range.location), last = rule(at: NSMaxRange(range))
        guard first != range, first != last, first != nil || last != nil else { return nil }
        let selectedRow = raw.paragraphRange(for: NSRange(location: range.location, length: 0))
        if selectedRow == range, let prefix = MacBlockPrefix(original.attribute(.macBlock, at: range.location, effectiveRange: nil) as? String ?? ""), prefix.list,
           raw.substring(with: range).hasPrefix(prefix.display) { return nil }
        let start = first.map { range.location == $0.location ? $0.location : NSMaxRange($0) }
        let end = last.map { NSMaxRange(range) == $0.location ? $0.location : NSMaxRange($0) }
        var insertions: [Int: [NSAttributedString.Key: Any]] = [:]
        if let first, let start { insertions[start] = MacHorizontalRule.continuationAttributes(original.attributes(at: first.location, effectiveRange: nil)) }
        if let last, let end { insertions[end] = MacHorizontalRule.continuationAttributes(original.attributes(at: last.location, effectiveRange: nil)) }
        let projected = NSMutableAttributedString(attributedString: original)
        for location in insertions.keys.sorted(by: >) { projected.insert(NSAttributedString(string: "\n", attributes: insertions[location]), at: location) }
        func position(_ location: Int, inserted: Bool) -> Int { location + insertions.keys.filter { inserted ? $0 < location : $0 <= location }.count }
        let lower = start.map { position($0, inserted: true) } ?? position(range.location, inserted: false)
        let upper = end.map { position($0, inserted: true) } ?? position(NSMaxRange(range), inserted: false)
        guard upper >= lower else { return .refused("This rule selection needs Markdown source editing to preserve its blocks.") }
        switch replacingSelection(projected, range: NSRange(location: lower, length: upper - lower), replacement: replacement, typing: typing) {
        case .changed(let edit): return .changed(edit)
        case .refused(let message): return .refused(message)
        case .notList, .unchanged: return .refused("This rule selection needs Markdown source editing to preserve its blocks.")
        }
    }
    static func replacingCardSelection(_ original: NSAttributedString, range: NSRange, replacement: NSAttributedString, typing: [NSAttributedString.Key: Any]) -> Outcome {
        guard range.length > 0, range.location < original.length, NSMaxRange(range) <= original.length,
              range != NSRange(location: 0, length: original.length) else { return .notList }
        if let rule = replacingRuleBoundary(original, range: range, replacement: replacement, typing: typing) { return rule }
        func endpoint(_ index: Int) -> CardEndpoint? {
            let code = MacRichCode.at(original, index), cell = MacRichTable.at(original, index)
            guard code != nil || cell != nil else { return nil }
            let key: NSAttributedString.Key = code == nil ? .macTable : .macCode
            var span = NSRange()
            _ = original.attribute(key, at: index, longestEffectiveRange: &span, in: NSRange(location: 0, length: original.length))
            return CardEndpoint(range: span, code: code, cell: cell)
        }
        let first = endpoint(range.location), last = endpoint(NSMaxRange(range))
        guard first?.token !== last?.token, first != nil || last != nil else { return .notList }
        if first == nil, replacement.string.rangeOfCharacter(from: CharacterSet.newlines.subtracting(CharacterSet(charactersIn: "\u{2028}"))) != nil { return .notList }
        if let first, NSMaxRange(range) <= NSMaxRange(first.range) { return .notList }
        if let last, NSMaxRange(range) == last.range.location { return .notList }
        func continuation(_ card: CardEndpoint) -> [NSAttributedString.Key: Any] {
            let old = original.attributes(at: card.range.location, effectiveRange: nil)
            var attrs: [NSAttributedString.Key: Any] = [.macBlock: card.quotes, .paragraphStyle: MacMarkdown.paragraphStyle(card.quotes), .macLineEnding: card.ending.isEmpty ? card.newline : card.ending]
            if let tail = old[.macListContext] as? MacListContext {
                let suffix = (old[.macListCard] as? MacListCardPlacement)?.ownerSuffix ?? tail.suffix
                let context = MacListContext(id: tail.id, source: tail.source, continuation: true, suffix: suffix, quoteParents: tail.quoteParents)
                attrs[.macListContext] = context; attrs[.macBlock] = context.block; attrs[.paragraphStyle] = context.style
            } else { attrs[.macIndependentParagraph] = true }
            return attrs
        }
        func renderedCode(_ body: String, code: MacRichCode, from old: NSAttributedString) -> NSAttributedString {
            MacListCardPlacement.carrying(MacRichCode.render(code.original.replacing(body: body, info: code.original.info), ending: code.ending, indented: code.indented, quote: code.quote), from: old)
        }
        let projected = NSMutableAttributedString(attributedString: original)
        var lower = range.location, upper = NSMaxRange(range)
        if let last {
            let old = original.attributedSubstring(from: last.range), value = NSMutableAttributedString(string: "\n", attributes: continuation(last))
            if let code = last.code {
                let suffix = MacRichCode.body(original.attributedSubstring(from: NSRange(location: upper, length: NSMaxRange(last.range) - upper)))
                value.append(renderedCode(suffix, code: code, from: old))
            } else { value.append(MacRichTable.replacing(old, range: NSRange(location: 0, length: upper - last.range.location), with: NSAttributedString())) }
            projected.replaceCharacters(in: last.range, with: value); upper = last.range.location
        }
        var prefix = "", prefixToken: NSObject?
        if let first {
            let old = original.attributedSubstring(from: first.range), value: NSMutableAttributedString
            if let code = first.code {
                prefix = MacRichCode.body(original.attributedSubstring(from: NSRange(location: first.range.location, length: range.location - first.range.location)))
                value = NSMutableAttributedString(attributedString: renderedCode(prefix, code: code, from: old))
                prefixToken = MacRichCode.at(value, 0)
            } else {
                value = NSMutableAttributedString(attributedString: MacRichTable.replacing(old, range: NSRange(location: range.location - first.range.location, length: NSMaxRange(first.range) - range.location), with: NSAttributedString(), preservingGrid: true))
                prefixToken = first.token
            }
            lower = first.range.location + value.length
            value.append(NSAttributedString(string: "\n", attributes: continuation(first)))
            projected.replaceCharacters(in: first.range, with: value); upper += value.length - first.range.length
        }
        let selected = NSRange(location: lower, length: upper - lower)
        let insertion = first == nil ? replacement : NSAttributedString()
        let checked: Edit
        switch replacingSelection(projected, range: selected, replacement: insertion, typing: typing) {
        case .changed(let edit): checked = edit
        case .refused(let issue): return .refused(issue)
        case .notList, .unchanged:
            let raw = projected.string as NSString
            let row = raw.paragraphRange(for: NSRange(location: lower, length: 0))
            let source = projected.attribute(.macBlock, at: row.location, effectiveRange: nil) as? String ?? ""
            let output = NSMutableAttributedString(attributedString: projected)
            output.replaceCharacters(in: selected, with: insertion)
            let merged = (output.string as NSString).paragraphRange(for: NSRange(location: row.location, length: 0))
            let value = MacMarkdown.settingBlock(output.attributedSubstring(from: merged), to: source, collapsingParagraphs: false)
            output.replaceCharacters(in: merged, with: value)
            checked = Edit(text: MacMarkdown.refreshingListContexts(output), selection: NSRange(location: lower + insertion.length + value.length - merged.length, length: 0), typing: typing)
        }
        guard let first, let prefixToken else { return .changed(checked) }
        var retained: NSRange?
        checked.text.enumerateAttribute(first.key, in: NSRange(location: 0, length: checked.text.length)) { value, range, _ in
            if let value = value as? NSObject, value === prefixToken { retained = range }
        }
        let issue = "This card selection cannot preserve its block boundary."
        guard let retained, checked.selection.location == NSMaxRange(retained), checked.selection.location < checked.text.length else { return .refused(issue) }
        let row = (checked.text.string as NSString).paragraphRange(for: NSRange(location: checked.selection.location, length: 0))
        guard row.location == NSMaxRange(retained) else { return .refused(issue) }
        let suffix = NSMutableAttributedString(attributedString: checked.text.attributedSubstring(from: row))
        if suffix.string.hasSuffix("\r\n") { suffix.deleteCharacters(in: NSRange(location: suffix.length - 2, length: 2)) }
        else if suffix.string.hasSuffix("\n") || suffix.string.hasSuffix("\r") { suffix.deleteCharacters(in: NSRange(location: suffix.length - 1, length: 1)) }
        let value: NSAttributedString, caret: Int, attrs: [NSAttributedString.Key: Any]
        let old = checked.text.attributedSubstring(from: retained)
        if let code = first.code {
            let inserted = MacRichCode.literalBody(replacement), body = prefix + inserted + MacRichCode.literalBody(suffix)
            value = renderedCode(body, code: code, from: old)
            caret = retained.location + MacMarkdownLines.normalized(prefix + inserted, to: code.original.newline).utf16.count
            let token = MacRichCode.at(value, 0)!
            attrs = MacListCardPlacement.inheriting(MacRichCode.attributes(token), from: value.attributes(at: 0, effectiveRange: nil))
        } else {
            let cell = first.cell!, merged = NSMutableAttributedString(attributedString: replacement)
            merged.append(suffix)
            let inline = NSMutableAttributedString(attributedString: MacRichTable.insertion(merged, cell: cell))
            for key in [NSAttributedString.Key.macListCard, .macListContext] { inline.removeAttribute(key, range: NSRange(location: 0, length: inline.length)) }
            let local = range.location - first.range.location
            value = MacListCardPlacement.carrying(MacRichTable.replacing(old, range: NSRange(location: local, length: 0), with: inline), from: old)
            caret = retained.location + local + MacRichTable.insertion(replacement, cell: cell).length
            attrs = MacListCardPlacement.inheriting(cell.attributes, from: value.attributes(at: 0, effectiveRange: nil))
        }
        let output = NSMutableAttributedString(attributedString: checked.text)
        output.replaceCharacters(in: NSRange(location: retained.location, length: retained.length + row.length), with: value)
        // Adjacent pipe tables parse as one table. Keep a real native/source
        // separator when deleting their intervening item wrapper joins them.
        if first.cell != nil, NSMaxRange(row) < checked.text.length,
           checked.text.attribute(.macTable, at: NSMaxRange(row), effectiveRange: nil) != nil {
            let old = checked.text.attributes(at: row.location, effectiveRange: nil)
            var blank: [NSAttributedString.Key: Any] = [.macBlock: old[.macBlock] ?? "", .paragraphStyle: old[.paragraphStyle] ?? MacMarkdown.paragraphStyle(""), .macLineEnding: first.ending.isEmpty ? first.newline : first.ending]
            if let context = old[.macListContext] { blank[.macListContext] = context }
            output.insert(NSAttributedString(string: "\n", attributes: blank), at: retained.location + value.length)
        }
        return .changed(Edit(text: MacMarkdown.refreshingListContexts(output), selection: NSRange(location: caret, length: 0), typing: attrs))
    }

    /// A body-to-body replacement keeps the starting paragraph and merges the
    /// ending paragraph's suffix into it. Removed wrappers leave their children
    /// with the previous surviving sibling in that list, or its retained parent.
    /// A subsequent paragraph split needs a checked deletion even within one
    /// item; its endpoint at the next marker maps to that item's body start.
    static func replacingSelection(_ original: NSAttributedString, range: NSRange, replacement: NSAttributedString, typing: [NSAttributedString.Key: Any], forParagraphSplit: Bool = false) -> Outcome {
        if !forParagraphSplit, let edit = MacHorizontalRule.replacingOwnedRule(original, range: range, with: replacement) { return .changed(edit) }
        if !forParagraphSplit {
            switch replacingCardSelection(original, range: range, replacement: replacement, typing: typing) {
            case .notList, .unchanged: break
            case .changed(let edit): return .changed(edit)
            case .refused(let issue): return .refused(issue)
            }
        }
        var range = range
        let lineBreaks = replacement.string.contains("\u{2028}")
        guard (range.length > 0 || lineBreaks || forParagraphSplit), range.location < original.length, NSMaxRange(range) <= original.length,
              replacement.string.rangeOfCharacter(from: CharacterSet.newlines.subtracting(CharacterSet(charactersIn: "\u{2028}"))) == nil else { return .notList }
        let raw = original.string as NSString
        var end = NSMaxRange(range)
        let first = raw.paragraphRange(for: NSRange(location: range.location, length: 0))
        let last = raw.paragraphRange(for: NSRange(location: min(end, raw.length - 1), length: 0))
        let firstAttrs = original.attributes(at: first.location, effectiveRange: nil)
        let firstSource = firstAttrs[.macBlock] as? String ?? ""
        let message = "This list needs Markdown source editing before this selection can preserve its item relationships."
        let markerSelection: Bool
        switch bodySelection(in: original, range: range, forParagraphSplit: forParagraphSplit) {
        case .range(let checked, let marker):
            markerSelection = marker
            if !forParagraphSplit, marker, first == last, replacement.length == 0,
               range == NSRange(location: first.location, length: MacMarkdown.displayPrefix(firstSource).utf16.count) { return lift(original, paragraph: first) }
            range = checked; end = NSMaxRange(checked)
        case .boundary: return .notList
        case .missingMarker: return .refused(message)
        }
        // A logical break inside one unchanged item paragraph cannot move an
        // item. Reuse the body editor's local padding/empty-head check instead
        // of requiring every temporary list elsewhere to map successfully.
        if !forParagraphSplit, !markerSelection, first == last, lineBreaks,
           case .unchanged = editingBody(original, range: range, replacement: replacement, typing: typing) { return .notList }
        // Clearing an independent paragraph can expose a list to following
        // indented items or independent prose. Capture that boundary even though
        // the selection has no list context. Nonempty prose uses its usual path.
        var neighbors: [NSRange] = []
        var independent: IndependentParagraph?
        if first == last && !markerSelection && !((lineBreaks || forParagraphSplit) && (MacBlockPrefix(firstSource)?.list == true || (firstAttrs[.macListContext] as? MacListContext)?.continuation == true)) {
            guard MacBlockPrefix(firstSource)?.list != true, MacBlockPrefix(firstSource)?.heading != true,
                  (firstAttrs[.macListContext] as? MacListContext)?.continuation != true else { return .notList }
            let value = NSMutableString(string: raw.substring(with: first))
            value.replaceCharacters(in: NSRange(location: range.location - first.location, length: range.length), with: replacement.string)
            guard (value as String).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notList }
            var previousList: NSRange?, following: NSRange?
            for backward in [true, false] {
                var cursor = backward ? first.location : NSMaxRange(last)
                while backward ? cursor > 0 : cursor < raw.length {
                    let paragraph = raw.paragraphRange(for: NSRange(location: backward ? cursor - 1 : cursor, length: 0))
                    cursor = backward ? paragraph.location : NSMaxRange(paragraph)
                    if raw.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    let head = MacMarkdown.listHeadParagraph(in: original, paragraph: paragraph) ?? paragraph
                    if MacBlockPrefix(original.attribute(.macBlock, at: head.location, effectiveRange: nil) as? String ?? "")?.list == true {
                        neighbors.append(head)
                        if backward { previousList = head }
                    }
                    if !backward { following = paragraph }
                    break
                }
            }
            if let previousList, let following,
               let paragraph = independentParagraph(in: original, at: following) {
                let prefix = original.attributedSubstring(from: NSRange(location: 0, length: paragraph.range.location))
                guard wouldAdopt(paragraph, prefix: prefix, range: range, replacement: replacement) else { return .notList }
                neighbors = [previousList]; independent = paragraph
            } else {
                guard neighbors.count == 2,
                      var before = MacBlockPrefix(original.attribute(.macBlock, at: neighbors[0].location, effectiveRange: nil) as? String ?? ""),
                      let after = MacBlockPrefix(original.attribute(.macBlock, at: neighbors[1].location, effectiveRange: nil) as? String ?? ""),
                      before.depth == after.depth else { return .notList }
                // A later root can only be adopted at an active ancestor's content
                // column. Find that ancestor without requiring a whole-note map;
                // unrelated or one-sided temporary lists must not veto plain edits.
                var cursor = neighbors[0].location
                while cursor > 0 {
                    let paragraph = raw.paragraphRange(for: NSRange(location: cursor - 1, length: 0)); cursor = paragraph.location
                    if raw.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    let head = MacMarkdown.listHeadParagraph(in: original, paragraph: paragraph) ?? paragraph
                    guard let prefix = MacBlockPrefix(original.attribute(.macBlock, at: head.location, effectiveRange: nil) as? String ?? ""), prefix.list, prefix.depth == before.depth else { break }
                    if prefix.indent < before.indent { before = prefix }
                }
                guard after.indent >= before.indent + before.listPadding else { return .notList }
            }
        }
        let full = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        var touches = !neighbors.isEmpty, partialCard = false
        original.enumerateAttributes(in: full) { attrs, _, _ in
            if MacBlockPrefix(attrs[.macBlock] as? String ?? "")?.list == true { touches = true }
        }
        for paragraph in [first, last] {
            if let head = MacMarkdown.listHeadParagraph(in: original, paragraph: paragraph), head != paragraph { touches = true }
        }
        // Fully selected cards are atomic units in the same checked edit as
        // their surrounding item text. Selections starting or ending in a
        // card keep their existing code/cell and whole-card paths.
        for key in [NSAttributedString.Key.macCode, .macTable, .macRule] {
            original.enumerateAttribute(key, in: full) { value, part, _ in
                guard value != nil else { return }
                var token = NSRange()
                _ = original.attribute(key, at: part.location, longestEffectiveRange: &token, in: NSRange(location: 0, length: original.length))
                if NSIntersectionRange(range, token) != token || NSLocationInRange(first.location, token) || NSLocationInRange(last.location, token) { partialCard = true }
            }
        }
        guard touches, !partialCard else { return .notList }
        let scope: NSRange, items: [MacMarkdown.NativeListItem]
        if let mapped = MacMarkdown.nativeListItems(in: original) { scope = NSRange(location: 0, length: original.length); items = mapped }
        else {
            var lower = first.location, upper = max(NSMaxRange(last), independent.map { NSMaxRange($0.range) } ?? 0)
            for paragraph in [first, last] + neighbors {
                let head = MacMarkdown.listHeadParagraph(in: original, paragraph: paragraph) ?? paragraph
                if let region = MacMarkdown.nativeListRegion(in: original, around: head.location) { lower = min(lower, region.location); upper = max(upper, NSMaxRange(region)) }
                else if neighbors.contains(paragraph) { return .refused(message) }
            }
            scope = NSRange(location: lower, length: upper - lower)
            guard let mapped = MacMarkdown.nativeListItems(in: original.attributedSubstring(from: scope)) else { return .refused(message) }
            items = mapped.map { MacMarkdown.NativeListItem(range: NSRange(location: scope.location + $0.range.location, length: $0.range.length), block: $0.block, parent: $0.parent, container: $0.container) }
        }
        let heads = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.range.location, $0.offset) })
        var units: [Unit] = [], latest: [UUID: Int] = [:], offset = scope.location
        while offset < NSMaxRange(scope) {
            let paragraph = unitRange(in: original, at: offset)
            let context = original.attribute(.macListContext, at: offset, effectiveRange: nil) as? MacListContext
            var owner = heads[offset]
            if let owner, let context { latest[context.id] = owner }
            else if let context, context.continuation { owner = latest[context.id] }
            units.append(Unit(range: paragraph, text: original.attributedSubstring(from: paragraph), owner: owner)); offset = NSMaxRange(paragraph)
        }
        let semantic = semanticContainers(items, in: original.attributedSubstring(from: scope))
        func container(_ row: Int) -> Int { semantic.aliases[items[row].container] ?? items[row].container }
        let startOwner = units.first(where: { $0.range.location == first.location })?.owner
        let removed = Set(items.indices.filter { items[$0].range.location > first.location && items[$0].range.location <= last.location })
        let remaining = items.indices.filter { !removed.contains($0) }
        func destination(for owner: Int) -> Int? {
            if let sibling = items.indices.prefix(owner).last(where: { !removed.contains($0) && container($0) == container(owner) }) { return sibling }
            guard let ancestor = items[owner].parent else { return nil }
            return removed.contains(ancestor) ? destination(for: ancestor) : ancestor
        }
        func parent(_ row: Int) -> Int? {
            guard let old = items[row].parent else { return nil }
            return removed.contains(old) ? destination(for: old) : old
        }
        var resolved: [Int: Int] = [:], joinedExisting = Set<Int>()
        func survivingContainer(_ row: Int) -> Int {
            if let value = resolved[row] { return value }
            var value = container(row)
            if let owner = items[row].parent, removed.contains(owner) {
                let previous = items.indices.prefix(owner).last { !removed.contains($0) && container($0) == container(owner) }
                if let previous {
                    // An existing child list absorbs the moved children. Without
                    // one, their own list kind remains under the surviving item.
                    if let child = remaining.last(where: { items[$0].parent == previous }) {
                        // A retained parent paragraph after its last child list
                        // separates that list from the incoming children. Their
                        // kind and checkbox state must survive across that text.
                        let separated = units.contains { unit in
                            guard unit.owner == previous, unit.range.location > items[child].range.location else { return false }
                            if unit.range.location == first.location { return true }
                            let deleted = range.location <= unit.range.location && end >= NSMaxRange(unit.range)
                            return !deleted && !unit.text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                        if !separated { value = survivingContainer(child); joinedExisting.insert(row) }
                    }
                } else { value = survivingContainer(owner) }
            }
            resolved[row] = value; return value
        }
        let groups = Dictionary(grouping: items.indices, by: survivingContainer)
        let output = NSMutableAttributedString(attributedString: original)
        output.replaceCharacters(in: range, with: replacement)
        var merged = (output.string as NSString).paragraphRange(for: NSRange(location: first.location, length: 0))
        var source = firstSource, context = firstAttrs[.macListContext] as? MacListContext
        let payload = NSMutableAttributedString(attributedString: output.attributedSubstring(from: merged))
        let payloadRange = NSRange(location: 0, length: payload.length)
        payload.enumerateAttributes(in: payloadRange) { attrs, part, _ in
            let old = attrs[.macBlock] as? String ?? "", font = attrs[.font] as? NSFont ?? MacMarkdown.font(old)
            let traits = NSFontManager.shared.traits(of: font), bold = MacMarkdown.inlineBold(attrs, block: (attrs[.macListContext] as? MacListContext)?.textBlock ?? old)
            payload.addAttributes([.macBlock: source, .macStrong: bold, .font: MacMarkdown.inlineFont(block: context?.textBlock ?? source, bold: bold, italic: traits.contains(.italicFontMask), code: traits.contains(.fixedPitchFontMask)), .paragraphStyle: context?.style ?? MacMarkdown.paragraphStyle(source)], range: part)
        }
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListContext, .macListGap] { payload.removeAttribute(key, range: payloadRange) }
        if let context { payload.addAttribute(.macListContext, value: context, range: payloadRange) }
        if let prefix = MacBlockPrefix(source), prefix.list, !prefix.checklist, !MacMarkdown.listBodyState(payload, block: prefix).hasContent {
            source = prefix.replacingMarker(String(prefix.marker.prefix(while: { !$0.isWhitespace })) + " ")
            payload.setAttributedString(MacMarkdown.settingBlock(payload, to: source))
            context = payload.attribute(.macListContext, at: 0, effectiveRange: nil) as? MacListContext
        }
        var markerDelta = payload.length - merged.length
        output.replaceCharacters(in: merged, with: payload)
        merged.length = payload.length
        var delta = replacement.length - range.length + markerDelta
        var markers: [Int: String] = [:]
        for container in Set(items.map(\.container)) {
            let rows = items.indices.filter { items[$0].container == container }
            if let first = rows.first, removed.contains(first), var ordinal = Int(items[first].block.marker.prefix(while: \.isNumber)) {
                for row in rows where !removed.contains(row) {
                    let marker = items[row].block.marker
                    markers[row] = String(ordinal) + marker.dropFirst(marker.prefix(while: \.isNumber).count)
                    ordinal = min(999_999_999, ordinal + 1)
                }
            }
        }
        for (_, rows) in groups {
            guard let first = rows.first, Set(rows.map { items[$0].container }).count > 1,
                  rows.contains(where: { removed.contains($0) || survivingContainer($0) != container($0) }) else { continue }
            let prototype = items[first].block
            let kind = semantic.kinds[items[first].container] ?? .bullet
            // Preserve a root list's saved start consistently whether or not
            // another source container joins it. A newly promoted nested list
            // starts at one so it can interrupt its parent's paragraph.
            var ordinal = removed.contains(first) && items[first].parent != nil ? 1 : Int(prototype.marker.prefix(while: \.isNumber)) ?? 1
            for row in rows where !removed.contains(row) {
                let old = items[row].block
                let checked = old.checklist && !old.marker.contains("[ ]")
                // Flattening a wrapper keeps task state. Appending into an
                // existing list adopts its task/bullet/number kind instead.
                let task = kind == .check || kind == .numberedCheck || old.checklist && !joinedExisting.contains(row)
                let stem: String
                if kind == .number || kind == .numberedCheck {
                    let delimiter = prototype.marker.dropFirst(prototype.marker.prefix(while: \.isNumber).count).prefix(1)
                    stem = String(ordinal) + delimiter + " "
                } else { stem = String(prototype.marker.prefix(1)) + " " }
                markers[row] = stem + (task ? (checked ? "[x] " : "[ ] ") : "")
                ordinal = min(999_999_999, ordinal + 1)
            }
        }
        var planned: [Int: MacBlockPrefix] = [:]
        var movements: [Int: [(delta: Int, depth: Int)]] = [:]
        for row in remaining {
            let old = items[row].block, ancestor = parent(row)
            let moved: String
            if let oldParent = items[row].parent, !removed.contains(oldParent) {
                let target = planned[oldParent] ?? items[oldParent].block
                // Carry each ancestor's movement at its own quote depth. A
                // quoted descendant's final indent is inside the quote, not
                // the whitespace that belongs to its enclosing list item.
                let steps = (movements[oldParent] ?? []) + [(target.listPadding - items[oldParent].block.listPadding, items[oldParent].block.depth)]
                moved = steps.reduce(old.source) { source, step in
                    MacBlockPrefix(source)!.shiftingIndentation(by: step.delta, atQuoteDepth: step.depth)
                }
                movements[row] = steps
            } else if let oldParent = items[row].parent {
                let margin = max(0, old.indent - items[oldParent].block.indent - items[oldParent].block.listPadding)
                let indent = ancestor.flatMap { planned[$0] }.map { $0.indent + $0.listPadding + margin } ?? margin
                moved = old.indented(indent)
                movements[row] = [(indent - old.indent, old.depth)]
            } else {
                moved = old.source
                movements[row] = []
            }
            let value = row == startOwner && items[row].range.location == first.location
                ? (markers[row].map { MacBlockPrefix(source)!.replacingMarker($0) } ?? source)
                : (markers[row].map { MacBlockPrefix(moved)!.replacingMarker($0) } ?? moved)
            guard let prefix = MacBlockPrefix(value) else { return .refused(message) }
            planned[row] = prefix
        }
        if let startOwner, items[startOwner].range.location == first.location,
           let target = planned[startOwner],
           target.source != source || markers[startOwner] != nil && output.attribute(.macOrderedMarker, at: merged.location, effectiveRange: nil) != nil {
            let updated = MacMarkdown.settingBlock(output.attributedSubstring(from: merged), to: target.source)
            let change = updated.length - merged.length
            output.replaceCharacters(in: merged, with: updated); merged.length = updated.length
            markerDelta += change; delta += change; source = target.source
            context = updated.attribute(.macListContext, at: 0, effectiveRange: nil) as? MacListContext
        }
        var leadingDelta = 0
        for unit in units.reversed() where unit.range.location >= NSMaxRange(last) || NSMaxRange(unit.range) <= first.location {
            let before = NSMaxRange(unit.range) <= first.location
            let position = NSRange(location: unit.range.location + (before ? 0 : delta), length: unit.range.length)
            // A surviving decorator follows the merged starting paragraph;
            // nested item heads still use the surviving-sibling rule above.
            let transferOwner = unit.owner.flatMap { owner in
                unit.text.attribute(.macListCard, at: 0, effectiveRange: nil) != nil ? startOwner : destination(for: owner)
            }
            if let independent, NSLocationInRange(unit.range.location, independent.range) {
                if unit.range.location == independent.range.location {
                    output.replaceCharacters(in: NSRange(location: position.location, length: independent.range.length), with: independent.text)
                }
                continue
            }
            if let row = heads[unit.range.location], let prefix = planned[row],
               prefix.source != items[row].block.source || markers[row] != nil && unit.text.attribute(.macOrderedMarker, at: 0, effectiveRange: nil) != nil {
                let updated = MacMarkdown.settingBlock(unit.text, to: prefix.source)
                output.replaceCharacters(in: position, with: updated)
                if before { leadingDelta += updated.length - unit.text.length }
            } else if let owner = unit.owner, removed.contains(owner),
                      let target = transferOwner,
                      let head = original.attribute(.macListContext, at: items[target].range.location, effectiveRange: nil) as? MacListContext,
                      let tail = unit.text.attribute(.macListContext, at: 0, effectiveRange: nil) as? MacListContext, tail.continuation {
                let targetSource = planned[target]?.source ?? head.source
                // The removed item may sit inside a quote owned by its surviving
                // ancestor. That quote becomes part of the tail's relative block;
                // replacing its source alone would silently turn it into prose.
                var quoteDepth = max(0, items[owner].block.depth - (MacBlockPrefix(targetSource)?.depth ?? 0))
                if unit.text.attribute(.macListCard, at: 0, effectiveRange: nil) != nil {
                    // Cards follow the merged starting paragraph. Quotes before
                    // a removed, unrelated item close with that item; only a
                    // surviving ancestor continues to own those outer quotes.
                    var ancestor = items[owner].parent
                    while let row = ancestor, row != target { ancestor = items[row].parent }
                    if ancestor != target { quoteDepth = 0 }
                }
                let inheritedQuotes = String(repeating: "> ", count: quoteDepth)
                let updated = MacListContext(id: head.id, source: targetSource, continuation: true, gap: tail.gap, originatedAfterChildren: tail.originatedAfterChildren, suffix: inheritedQuotes + tail.suffix, blockParagraph: tail.blockParagraph, quoteLeaf: tail.quoteLeaf, quoteParents: head.quoteParents)
                output.addAttributes([.macListContext: updated, .macBlock: updated.block, .paragraphStyle: updated.style], range: position)
            } else if let owner = unit.owner, removed.contains(owner),
                      transferOwner == nil,
                      (unit.text.attribute(.macListContext, at: 0, effectiveRange: nil) as? MacListContext)?.continuation == true {
                // With no surviving item, this is independent prose in the
                // removed item's quote container. Give it real paragraph boundaries;
                // an orphan list context would erase its quote on serialization.
                let quotes = items[owner].block.quotes
                let value = MacMarkdown.settingBlock(unit.text, to: quotes)
                output.replaceCharacters(in: position, with: value)
                let ending = (unit.text.attribute(.macCode, at: 0, effectiveRange: nil) as? MacRichCode)?.ending
                    ?? (unit.text.attribute(.macTable, at: 0, effectiveRange: nil) as? MacRichTable)?.ending
                    ?? unit.text.attribute(.macLineEnding, at: unit.text.length - 1, effectiveRange: nil) as? String ?? "\n"
                let separator = NSAttributedString(string: "\n", attributes: [.macBlock: quotes, .paragraphStyle: MacMarkdown.paragraphStyle(quotes), .macLineEnding: ending])
                if let index = units.firstIndex(where: { $0.range == unit.range }) {
                    if index + 1 < units.count {
                        let next = units[index + 1]
                        let orphan = next.owner.map { removed.contains($0) } == true && (next.text.attribute(.macListContext, at: 0, effectiveRange: nil) as? MacListContext)?.continuation == true
                        if !orphan, !next.text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { output.insert(separator, at: position.location + value.length) }
                    }
                    let previousBlank = index > 0 && units[index - 1].range.location >= NSMaxRange(last) && units[index - 1].text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if !previousBlank { output.insert(separator, at: position.location) }
                }
            }
            if unit.range.location == NSMaxRange(last), let row = heads[unit.range.location], parent(row) == nil,
               startOwner == nil || planned[row]?.quotes != MacBlockPrefix(context?.source ?? source)?.quotes {
                let beforeQuotes = MacBlockPrefix(context?.source ?? source)?.quotes ?? "", afterQuotes = planned[row]?.quotes ?? ""
                let quotes = beforeQuotes == afterQuotes ? afterQuotes : "", ending = original.attribute(.macLineEnding, at: NSMaxRange(last) - 1, effectiveRange: nil) as? String ?? "\n"
                output.insert(NSAttributedString(string: "\n", attributes: [.macBlock: quotes, .paragraphStyle: MacMarkdown.paragraphStyle(quotes), .macLineEnding: ending]), at: position.location)
            }
        }
        let removedOwners = Dictionary(uniqueKeysWithValues: removed.compactMap { row -> (UUID, Int)? in
            (original.attribute(.macListContext, at: items[row].range.location, effectiveRange: nil) as? MacListContext).map { ($0.id, row) }
        })
        let changedScope = NSRange(location: scope.location, length: scope.length + output.length - original.length)
        output.enumerateAttribute(.macListGap, in: changedScope) { value, part, _ in
            guard let gap = value as? MacListGap, let owner = removedOwners[gap.parent] else { return }
            let target = destination(for: owner)
            let id = target.flatMap { (original.attribute(.macListContext, at: items[$0].range.location, effectiveRange: nil) as? MacListContext)?.id }
            let gapQuotes = items[owner].block.quotes
            if let id { output.addAttribute(.macListGap, value: MacListGap(parent: id, child: gap.child), range: part) }
            else { output.removeAttribute(.macListGap, range: part) }
            if output.attributedSubstring(from: part).string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.addAttributes([.macBlock: gapQuotes, .paragraphStyle: MacMarkdown.paragraphStyle(gapQuotes)], range: part)
            }
        }
        var prepared = rebindingGaps(MacMarkdown.refreshingListContexts(output), original: original, items: items, order: remaining, parent: parent)
        let currentScope = NSRange(location: scope.location, length: scope.length + prepared.length - original.length)
        let indices = Dictionary(uniqueKeysWithValues: remaining.enumerated().map { ($0.element, $0.offset) })
        let expected = remaining.map { parent($0).flatMap { indices[$0] } }
        var valid = false
        for _ in 0...remaining.count {
            let scoped = prepared.attributedSubstring(from: currentScope)
            guard let actual = MacMarkdown.nativeListItems(in: scoped), actual.count == remaining.count else { return .refused(message) }
            guard let wrong = actual.indices.first(where: { actual[$0].parent != expected[$0] }) else { valid = true; break }
            let target: Int
            if let ancestor = expected[wrong] {
                var parsed: [ListItem] = []
                func collect(_ node: any Markup) {
                    if let item = node as? ListItem { parsed.append(item) }
                    for child in node.children { collect(child) }
                }
                collect(Document(parsing: MacMarkdown.markdown(scoped)))
                guard parsed.indices.contains(ancestor) else { return .refused(message) }
                let item = parsed[ancestor], block = actual[ancestor].block
                let paragraph = item.child(at: 0) as? Paragraph
                let content = paragraph?.range?.lowerBound.line == item.range?.lowerBound.line ? block.listPadding : block.marker.prefix(while: { !$0.isWhitespace }).utf16.count + 1
                target = block.indent + content
            } else { target = 0 }
            let shift = target - actual[wrong].block.indent
            guard shift != 0 else { return .refused(message) }
            var roots: [Int: Int] = [wrong: shift]
            // Peers in the same old list share this boundary repair. Moving
            // the group avoids re-parsing once for every identically indented
            // sibling after an empty-marker padding change.
            for peer in actual.indices where peer > wrong && expected[peer] == expected[wrong] && items[remaining[peer]].container == items[remaining[wrong]].container {
                if actual[peer].block.indent <= target { break }
                roots[peer] = target - actual[peer].block.indent
            }
            let updated = NSMutableAttributedString(attributedString: prepared)
            for row in actual.indices.reversed() {
                var ancestor: Int? = row, move: Int?
                while let current = ancestor { if let shift = roots[current] { move = shift; break }; ancestor = expected[current] }
                guard let move else { continue }
                let entry = actual[row], position = NSRange(location: scope.location + entry.range.location, length: entry.range.length)
                let payload = prepared.attributedSubstring(from: position)
                let moved = MacMarkdown.settingBlock(payload, to: entry.block.indented(max(0, entry.block.indent + move)))
                guard moved.length == payload.length else { return .refused(message) }
                updated.replaceCharacters(in: position, with: moved)
            }
            prepared = rebindingGaps(MacMarkdown.refreshingListContexts(updated), original: original, items: items, order: remaining, parent: parent)
        }
        guard valid else { return .refused(message) }
        let previousTextBlock = (typing[.macListContext] as? MacListContext)?.textBlock ?? typing[.macBlock] as? String ?? ""
        var typing = typing
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListContext, .macListGap, .macLiteral, .attachment, .macImageUnavailable, .macHardBreak, .macListBreak] { typing.removeValue(forKey: key) }
        let caret = range.location + replacement.length + markerDelta + leadingDelta
        typing[.macBlock] = source; typing[.paragraphStyle] = context?.style ?? MacMarkdown.paragraphStyle(source)
        if let context { typing[.macListContext] = context }
        if prepared.length > 0 {
            let paragraph = (prepared.string as NSString).paragraphRange(for: NSRange(location: min(caret, prepared.length - 1), length: 0))
            let actual = prepared.attributes(at: paragraph.location, effectiveRange: nil)
            for key in [NSAttributedString.Key.macBlock, .macListContext, .macIndependentParagraph, .paragraphStyle] { typing[key] = actual[key] }
        }
        let textBlock = (typing[.macListContext] as? MacListContext)?.textBlock ?? typing[.macBlock] as? String ?? source
        let font = typing[.font] as? NSFont ?? MacMarkdown.font(previousTextBlock), traits = NSFontManager.shared.traits(of: font)
        let bold = MacMarkdown.inlineBold(typing, block: previousTextBlock)
        typing[.font] = MacMarkdown.inlineFont(block: textBlock, bold: bold, italic: traits.contains(.italicFontMask), code: traits.contains(.fixedPitchFontMask))
        typing[.macStrong] = bold
        return .changed(Edit(text: prepared, selection: NSRange(location: caret, length: 0), typing: typing))
    }

    /// Validate structural output using the graph the command intends, before
    /// the parser sees a stale first-child spacing tag from the old graph.
    private static func rebindingGaps(_ text: NSAttributedString, original: NSAttributedString, items: [MacMarkdown.NativeListItem], order: [Int], parent: (Int) -> Int?) -> NSAttributedString {
        var owners: Set<UUID> = [], firstChildren: [UUID: UUID] = [:]
        func identity(_ row: Int) -> UUID? {
            (original.attribute(.macListContext, at: items[row].range.location, effectiveRange: nil) as? MacListContext)?.id
        }
        for row in order {
            guard let id = identity(row) else { continue }
            owners.insert(id)
            if let ancestor = parent(row).flatMap(identity), firstChildren[ancestor] == nil { firstChildren[ancestor] = id }
        }
        let output = NSMutableAttributedString(attributedString: text)
        text.enumerateAttribute(.macListGap, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let gap = value as? MacListGap, owners.contains(gap.parent) else { return }
            if let child = firstChildren[gap.parent] {
                output.addAttribute(.macListGap, value: MacListGap(parent: gap.parent, child: child), range: range)
            } else { output.removeAttribute(.macListGap, range: range) }
        }
        return output
    }

    /// Keep a body edit's parser-owned graph when empty marker padding would
    /// otherwise adopt siblings or detach children. This transaction captures
    /// parentage before the text changes; structural commands need no stale
    /// parent UUIDs carried through their deliberate reparenting operations.
    static func editingBody(_ original: NSAttributedString, range: NSRange, replacement: NSAttributedString, typing: [NSAttributedString.Key: Any]) -> Outcome {
        guard original.length > 0, range.location < original.length, NSMaxRange(range) <= original.length,
              !replacement.string.contains("\n"), !replacement.string.contains("\r") else { return .notList }
        let raw = original.string as NSString, paragraph = raw.paragraphRange(for: NSRange(location: range.location, length: 0))
        guard let block = MacBlockPrefix(original.attribute(.macBlock, at: paragraph.location, effectiveRange: nil) as? String ?? ""), block.list, !block.checklist else { return .notList }
        let marker = block.display, symbol = String(block.marker.prefix(while: { !$0.isWhitespace }))
        let canonical = block.replacingMarker(symbol + " "), padding = symbol.utf16.count + 1
        let contentEnd = NSMaxRange(paragraph) - (raw.substring(with: paragraph).hasSuffix("\n") ? 1 : 0)
        guard raw.substring(with: paragraph).hasPrefix(marker),
              range.location >= paragraph.location + marker.utf16.count, NSMaxRange(range) <= contentEnd else { return .notList }
        // Ordinary edits to a canonical, nonempty head cannot change marker
        // padding. Avoid parsing or copying the document on that hot path.
        if block.listPadding == padding, replacement.length > 0, range.length == 0,
           contentEnd > paragraph.location + marker.utf16.count { return .unchanged }
        func startsEmpty(_ value: NSAttributedString, block: MacBlockPrefix) -> Bool {
            MacMarkdown.listBodyState(value, block: block).emptyFirstLine
        }
        let before = original.attributedSubstring(from: paragraph)
        let edited = NSMutableAttributedString(attributedString: before)
        edited.replaceCharacters(in: NSRange(location: range.location - paragraph.location, length: range.length), with: replacement)
        let wasEmpty = startsEmpty(before, block: block), isEmpty = startsEmpty(edited, block: block)
        guard wasEmpty || isEmpty, block.listPadding != padding || wasEmpty != isEmpty else { return .unchanged }
        let output = NSMutableAttributedString(attributedString: original)
        output.replaceCharacters(in: range, with: replacement)
        let changedRange = (output.string as NSString).paragraphRange(for: NSRange(location: paragraph.location, length: 0))
        let message = "This list needs Markdown source editing before this body edit can preserve its item relationships."
        let scope: NSRange, items: [MacMarkdown.NativeListItem]
        if let mapped = MacMarkdown.nativeListItems(in: original) { scope = NSRange(location: 0, length: original.length); items = mapped }
        else {
            guard let region = MacMarkdown.nativeListRegion(in: original, around: paragraph.location),
                  let mapped = MacMarkdown.nativeListItems(in: original.attributedSubstring(from: region)) else { return .refused(message) }
            scope = region
            items = mapped.map { MacMarkdown.NativeListItem(range: NSRange(location: region.location + $0.range.location, length: $0.range.length), block: $0.block, parent: $0.parent, container: $0.container) }
        }
        guard let owner = items.firstIndex(where: { $0.range.location == paragraph.location }) else { return .refused(message) }
        // A canonical or compact empty head needs no structural transaction
        // when its existing metadata already exports the same complete graph.
        // Keep its marker width and first character in native typing/Undo.
        if wasEmpty, !isEmpty,
           block.source == canonical || original.attribute(.macCompactList, at: paragraph.location, effectiveRange: nil) is MacCompactList,
           let native = MacMarkdown.nativeListItems(in: output.attributedSubstring(from: NSRange(location: scope.location, length: scope.length + replacement.length - range.length))),
           native.map(\.parent) == items.map(\.parent) { return .unchanged }
        output.setAttributedString(rebindingGaps(output, original: original, items: items, order: Array(items.indices), parent: { items[$0].parent }))
        let head = block.source == canonical ? output.attributedSubstring(from: changedRange) : MacMarkdown.settingBlock(output.attributedSubstring(from: changedRange), to: canonical)
        let markerDelta = head.length - changedRange.length
        output.replaceCharacters(in: changedRange, with: head)
        let delta = replacement.length - range.length + markerDelta
        let currentScope = NSRange(location: scope.location, length: scope.length + delta)
        func rowRange(_ row: Int) -> NSRange {
            let old = items[row].range
            return NSRange(location: old.location + (row > owner ? delta : 0), length: old.length + (row == owner ? delta : 0))
        }
        func prefix(_ row: Int) -> MacBlockPrefix? { MacBlockPrefix(output.attribute(.macBlock, at: rowRange(row).location, effectiveRange: nil) as? String ?? "") }
        func descends(_ row: Int, from ancestor: Int) -> Bool {
            var parent = items[row].parent
            while let index = parent { if index == ancestor { return true }; parent = items[index].parent }
            return false
        }
        func move(_ shifts: [Int: Int]) -> Bool {
            for row in items.indices.reversed() {
                guard let shift = shifts[row], shift != 0, let block = prefix(row) else { continue }
                let range = rowRange(row), payload = output.attributedSubstring(from: range)
                guard payload.string.hasPrefix(block.display) else { return false }
                let changed = MacMarkdown.settingBlock(payload, to: block.indented(max(0, block.indent + shift)))
                guard changed.length == payload.length else { return false }
                output.replaceCharacters(in: range, with: changed)
            }
            output.setAttributedString(MacMarkdown.refreshingListContexts(output))
            return true
        }
        let paddingDelta = padding - (wasEmpty ? padding : block.listPadding)
        let descendants = Dictionary(uniqueKeysWithValues: items.indices.filter { descends($0, from: owner) }.map { ($0, paddingDelta) })
        guard move(descendants) else { return .refused(message) }
        var valid = false
        for _ in 0...items.count {
            guard let after = MacMarkdown.nativeListItems(in: output.attributedSubstring(from: currentScope)), after.count == items.count else { return .refused(message) }
            guard let row = items.indices.first(where: { after[$0].parent != items[$0].parent }) else { valid = true; break }
            let target: Int
            if let parent = items[row].parent, let parentBlock = prefix(parent) {
                let parentText = output.attributedSubstring(from: rowRange(parent))
                let symbol = parentBlock.marker.prefix(while: { !$0.isWhitespace }).utf16.count
                let content = !parentBlock.checklist && startsEmpty(parentText, block: parentBlock) ? symbol + 1 : parentBlock.listPadding
                target = parentBlock.indent + content
            } else { target = 0 }
            guard let first = prefix(row), target != first.indent else { return .refused(message) }
            var roots: [Int: Int] = [:]
            for sibling in row..<items.count where items[sibling].parent == items[row].parent && items[sibling].container == items[row].container {
                guard let block = prefix(sibling) else { return .refused(message) }
                if sibling != row, block.indent <= target { break }
                roots[sibling] = target - block.indent
            }
            var shifts: [Int: Int] = [:]
            for index in items.indices {
                var ancestor: Int? = index
                while let row = ancestor {
                    if let shift = roots[row] { shifts[index] = shift; break }
                    ancestor = items[row].parent
                }
            }
            guard move(shifts) else { return .refused(message) }
        }
        guard valid else { return .refused(message) }
        let caret = range.location + replacement.length + markerDelta
        var typing = typing
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macLiteral, .attachment, .macImageUnavailable, .macHardBreak, .macListBreak] { typing.removeValue(forKey: key) }
        typing[.macBlock] = canonical; typing[.paragraphStyle] = MacMarkdown.paragraphStyle(canonical)
        typing[.macListContext] = output.attribute(.macListContext, at: paragraph.location, effectiveRange: nil)
        let newline = raw.substring(with: paragraph).hasSuffix("\n") ? NSMaxRange(paragraph) - 1 : max(0, paragraph.location - 1)
        typing[.macLineEnding] = original.attribute(.macLineEnding, at: newline, effectiveRange: nil) ?? "\n"
        return .changed(Edit(text: output, selection: NSRange(location: caret, length: 0), typing: typing))
    }

    struct EmptyItemBoundary {
        let text: NSAttributedString
        let paragraph: NSRange
        let items: [MacMarkdown.NativeListItem]
        let row: Int
        fileprivate let token: String
    }
    /// Establish a parser-owned boundary for an empty marker before deciding
    /// whether its item is empty. The repaired mapping is the authority.
    static func prepareEmptyItemBoundary(_ original: NSAttributedString, paragraph: NSRange) -> EmptyItemBoundary? {
        guard paragraph.length > 0, NSMaxRange(paragraph) <= original.length,
              let prefix = MacBlockPrefix(original.attribute(.macBlock, at: paragraph.location, effectiveRange: nil) as? String ?? ""), prefix.list,
              original.attributedSubstring(from: paragraph).string.trimmingCharacters(in: .whitespacesAndNewlines) == prefix.display.trimmingCharacters(in: .whitespaces) else { return nil }
        let token = UUID().uuidString
        let hasNewline = original.attributedSubstring(from: paragraph).string.hasSuffix("\n")
        let endingIndex = hasNewline ? NSMaxRange(paragraph) - 1 : max(0, paragraph.location - 1)
        let ending = original.attribute(.macLineEnding, at: endingIndex, effectiveRange: nil) as? String ?? "\n"
        let repaired = NSMutableAttributedString(attributedString: original)
        repaired.insert(NSAttributedString(string: "\n", attributes: [.macBlock: prefix.quotes, .paragraphStyle: MacMarkdown.paragraphStyle(prefix.quotes), .macLineEnding: ending, .macParagraphID: token]), at: paragraph.location)
        let shifted = NSRange(location: paragraph.location + 1, length: paragraph.length)
        guard let items = MacMarkdown.nativeListItems(in: repaired), let row = items.firstIndex(where: { $0.range.location == shifted.location }) else { return nil }
        return EmptyItemBoundary(text: repaired, paragraph: shifted, items: items, row: row, token: token)
    }
    static func hasOwnedContent(in text: NSAttributedString, paragraph: NSRange, items: [MacMarkdown.NativeListItem]? = nil) -> Bool {
        if let items = items ?? MacMarkdown.nativeListItems(in: text), let owner = items.firstIndex(where: { $0.range.location == paragraph.location }), items.contains(where: { item in
            var parent = item.parent
            while let index = parent { if index == owner { return true }; parent = items[index].parent }
            return false
        }) { return true }
        guard paragraph.length > 0, let context = text.attribute(.macListContext, at: paragraph.location, effectiveRange: nil) as? MacListContext else { return false }
        var content = false
        let raw = text.string as NSString
        text.enumerateAttribute(.macListContext, in: NSRange(location: NSMaxRange(paragraph), length: text.length - NSMaxRange(paragraph))) { value, range, _ in
            if let tail = value as? MacListContext, tail.continuation, tail.id == context.id,
               !raw.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { content = true }
        }
        return content
    }

    /// A non-list block closes its enclosing lists at this position. Following
    /// items and paragraphs stay in order rather than being merged into the new
    /// heading or moved ahead of it to retain a container that has now ended.
    private static func preservingHeadingBreaks(_ text: NSMutableAttributedString) {
        let raw = text.string as NSString
        for index in 0..<raw.length where raw.character(at: index) == 0x2028 && text.attribute(.macListBreak, at: index, effectiveRange: nil) as? Int != 2 {
            text.addAttribute(.macListBreak, value: 3, range: NSRange(location: index, length: 1))
        }
    }

    private static func formattingInnerBlock(_ paragraph: NSAttributedString, context: MacListContext, to prefix: String) -> (text: NSAttributedString, context: MacListContext) {
        let quotes = context.parentQuotes
        let suffix = quotes + prefix, heading = MacBlockPrefix(suffix)?.heading == true
        let ending = MacMarkdown.lineEnding(in: paragraph, at: max(0, paragraph.length - 1))
        var gap = context.gap
        if context.continuation, !heading, gap.isEmpty {
            gap = innerParagraphGap(source: context.source, quotes: quotes, ending: ending)
        }
        let next = MacListContext(id: context.id, source: context.source, continuation: context.continuation, gap: gap, originatedAfterChildren: context.originatedAfterChildren, suffix: suffix, blockParagraph: prefix.isEmpty, quoteLeaf: (MacBlockPrefix(prefix)?.depth ?? 0) > 0 && MacBlockPrefix(prefix)?.heading != true, quoteParents: context.quoteParents)
        let output = NSMutableAttributedString(attributedString: paragraph), full = NSRange(location: 0, length: paragraph.length)
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macEmptyParagraph] { output.removeAttribute(key, range: full) }
        paragraph.enumerateAttributes(in: full) { attrs, range, _ in
            let font = attrs[.font] as? NSFont ?? MacMarkdown.font(context.textBlock), traits = NSFontManager.shared.traits(of: font)
            let bold = MacMarkdown.inlineBold(attrs, block: context.textBlock)
            output.addAttributes([.macListContext: next, .macBlock: next.block, .macIndependentParagraph: false, .paragraphStyle: next.style, .macStrong: bold, .font: MacMarkdown.inlineFont(block: next.textBlock, bold: bold, italic: traits.contains(.italicFontMask), code: traits.contains(.fixedPitchFontMask))], range: range)
        }
        // Hard line breaks remain inside the new heading, rather than becoming
        // another heading or disappearing into a space.
        if heading { preservingHeadingBreaks(output) } else {
            let raw = paragraph.string as NSString, marker = context.continuation ? 0 : MacMarkdown.displayPrefix(context.source).utf16.count
            if !next.quoteLeaf, raw.substring(from: min(marker, raw.length)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { output.addAttribute(.macEmptyParagraph, value: true, range: full) }
        }
        return (output, next)
    }

    static func formatting(_ original: NSAttributedString, selection: NSRange, to prefix: String, separateParagraphs: Bool = false) -> Outcome {
        guard original.length > 0, selection.location <= original.length, NSMaxRange(selection) <= original.length,
              MacBlockPrefix(prefix)?.list != true else { return .notList }
        let raw = original.string as NSString, at = min(selection.location, original.length - 1)
        let full = raw.paragraphRange(for: NSRange(location: at, length: max(0, selection.length - 1)))
        let direct = MacMarkdown.nativeListItems(in: original)
        let mapping = direct ?? MacMarkdown.nativeListItems(in: original, allowEmptyItemBoundaries: true)
        let localOnly = mapping == nil
        if localOnly {
            // An unrelated unsupported list must not veto a local paragraph
            // action. Only units with no live native list owner can use this
            // path, and none of the unmapped rows are re-indented or removed.
            var live = Set<UUID>(), owned = false
            original.enumerateAttribute(.macListContext, in: NSRange(location: 0, length: original.length)) { value, _, _ in
                if let context = value as? MacListContext, !context.continuation { live.insert(context.id) }
            }
            original.enumerateAttributes(in: full) { attrs, _, stop in
                let context = attrs[.macListContext] as? MacListContext
                if MacBlockPrefix(attrs[.macBlock] as? String ?? "")?.list == true || context.map({ !$0.continuation || live.contains($0.id) }) == true { owned = true; stop.pointee = true }
            }
            if owned { return .refused(formattingIssue) }
        }
        let items = mapping ?? []
        let emptyBoundaries = direct == nil && !localOnly ? Set(MacMarkdown.insertingEmptyListBoundaries(in: original).locations) : []
        let heads = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.range.location, $0.offset) })
        var units: [Unit] = [], latest: [UUID: Int] = [:], offset = 0
        while offset < raw.length {
            let range = unitRange(in: original, at: offset)
            let context = original.attribute(.macListContext, at: offset, effectiveRange: nil) as? MacListContext
            var owner = heads[offset]
            if let row = owner, let context { latest[context.id] = row }
            else if let context, context.continuation { owner = latest[context.id] }
            units.append(Unit(range: range, text: original.attributedSubstring(from: range), owner: owner)); offset = NSMaxRange(range)
        }
        func anchor(_ position: Int, end: Bool) -> Anchor {
            let index = units.indices.first { end ? position > units[$0].range.location && position <= NSMaxRange(units[$0].range) : position < NSMaxRange(units[$0].range) } ?? units.count - 1
            return Anchor(unit: index, local: max(0, position - units[index].range.location))
        }
        let startAnchor = anchor(selection.location, end: false)
        let endAnchor = selection.length == 0 ? startAnchor : anchor(NSMaxRange(selection), end: true)
        let output = NSMutableAttributedString()
        var closed = Set<Int>(), removed = Set<Int>(), parents: [Int: Int] = [:], sources: [Int: String] = [:]
        var locations: [Int] = [], values: [NSAttributedString] = [], chosenBlocks: [Int: String] = [:]
        var changes: [Int: (old: Int, new: Int, collapse: Bool)] = [:]
        var previousBlank = true, previousAfter = false, previousQuotes = ""
        var innerAfter: MacListContext?
        for index in units.indices {
            let unit = units[index], old = unit.text.attribute(.macBlock, at: 0, effectiveRange: nil) as? String ?? ""
            var context = unit.text.attribute(.macListContext, at: 0, effectiveRange: nil) as? MacListContext
            let oldPrefix = MacMarkdown.displayPrefix(old)
            let oldLength = unit.text.string.hasPrefix(oldPrefix) ? oldPrefix.utf16.count : 0
            var card = false
            unit.text.enumerateAttributes(in: NSRange(location: 0, length: unit.text.length)) { attrs, _, stop in
                if attrs[.macCode] != nil || attrs[.macCodeSeparator] != nil || attrs[.macTable] != nil { card = true; stop.pointee = true }
            }
            let spacing = selection.length > 0 && unit.text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && context == nil && MacBlockPrefix(old)?.heading != true && unit.text.attribute(.macEmptyParagraph, at: 0, effectiveRange: nil) as? Bool != true
            let chosen = !card && !spacing && NSIntersectionRange(unit.range, full).length > 0
            var value = unit.text, before = false, after = false, target: String?
            let inner = chosen && context.map { !$0.suffix.isEmpty || $0.blockParagraph } == true && unit.owner.map { !closed.contains($0) } == true
            if let previous = innerAfter, let current = context, current.id == previous.id, current.continuation, current.gap.isEmpty, !card, !chosen || inner {
                let depth = min(previous.suffix.filter { $0 == ">" }.count, current.suffix.filter { $0 == ">" }.count)
                let ending = MacMarkdown.lineEnding(in: unit.text, at: max(0, unit.text.length - 1))
                let gap = innerParagraphGap(source: current.source, quotes: String(repeating: "> ", count: depth), ending: ending)
                let updated = MacListContext(id: current.id, source: current.source, continuation: current.continuation, gap: gap, originatedAfterChildren: current.originatedAfterChildren, suffix: current.suffix, blockParagraph: current.blockParagraph, quoteLeaf: current.quoteLeaf, quoteParents: current.quoteParents)
                let changed = NSMutableAttributedString(attributedString: value)
                changed.addAttribute(.macListContext, value: updated, range: NSRange(location: 0, length: changed.length)); value = changed; context = updated
            }
            if chosen && !inner {
                if let owner = unit.owner {
                    var row: Int? = owner
                    while let current = row { closed.insert(current); row = items[current].parent }
                }
                if let row = heads[unit.range.location] { removed.insert(row) }
                let quotes = unit.owner.map { items[$0].block.quotes } ?? ""
                let quoteTarget = (MacBlockPrefix(prefix)?.depth ?? 0) > 0
                if let context, !context.suffix.isEmpty || context.blockParagraph {
                    target = quotes + String(context.suffix.prefix { $0 == ">" || $0.isWhitespace }) + prefix
                } else { target = quoteTarget ? prefix : quotes + prefix }
                chosenBlocks[index] = target!
                let changed = old != target! || context != nil
                before = separateParagraphs || context?.continuation == true || changed && (prefix.isEmpty || quoteTarget && !quotes.isEmpty)
                after = separateParagraphs || changed && (prefix.isEmpty || MacBlockPrefix(prefix)?.heading != true)
            } else if let row = heads[unit.range.location] {
                var parent = items[row].parent
                while let current = parent, closed.contains(current) { parent = items[current].parent }
                if let parent { parents[row] = parent }
                let indent: Int
                if let parent {
                    let shifted = MacBlockPrefix(sources[parent] ?? items[parent].block.source)!.indent - items[parent].block.indent
                    indent = items[row].block.indent + shifted
                } else { indent = items[row].parent == nil ? items[row].block.indent : 0 }
                let next = items[row].block.indented(max(0, indent))
                sources[row] = next
                if next != old { target = next }
                before = emptyBoundaries.contains(unit.range.location)
            } else if let owner = unit.owner, closed.contains(owner) {
                target = items[owner].block.quotes + (context?.suffix ?? ""); before = true; after = true
            }
            var formattedContext: MacListContext?
            if inner, let context, let owner = unit.owner {
                let retained = context.replacing(source: sources[owner] ?? context.source)
                let changed = formattingInnerBlock(value, context: retained, to: prefix)
                value = changed.text; formattedContext = changed.context; target = nil
                chosenBlocks[index] = changed.context.block
                changes[index] = (oldLength, MacMarkdown.displayPrefix(changed.context.block).utf16.count, false)
            }
            if let target {
                let retainsBlocks = context.map { !$0.suffix.isEmpty || $0.blockParagraph } == true
                let collapse = chosen && !retainsBlocks
                value = MacMarkdown.settingBlock(value, to: target, collapsingParagraphs: collapse)
                if retainsBlocks, MacBlockPrefix(target)?.heading == true {
                    let kept = NSMutableAttributedString(attributedString: value); preservingHeadingBreaks(kept); value = kept
                }
                changes[index] = (oldLength, MacMarkdown.displayPrefix(target).utf16.count, collapse && MacBlockPrefix(target)?.heading == true)
            }
            let blank = value.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let block = value.length > 0 ? value.attribute(.macBlock, at: 0, effectiveRange: nil) as? String ?? "" : target ?? old
            let quotes = MacBlockPrefix(block)?.quotes ?? ""
            if output.length > 0, before && !previousBlank || previousAfter && !blank {
                let depth = min(previousQuotes.filter { $0 == ">" }.count, quotes.filter { $0 == ">" }.count)
                let shared = depth == quotes.filter({ $0 == ">" }).count ? quotes : String(repeating: "> ", count: depth)
                let endingIndex = unit.text.string.hasSuffix("\n") ? NSMaxRange(unit.range) - 1 : max(0, unit.range.location - 1)
                let newline = original.attribute(.macLineEnding, at: endingIndex, effectiveRange: nil) as? String ?? MacMarkdown.lineEnding(in: original, at: endingIndex)
                output.append(NSAttributedString(string: "\n", attributes: [.macBlock: shared, .font: MacMarkdown.font(shared), .paragraphStyle: MacMarkdown.paragraphStyle(shared), .macLineEnding: newline]))
            }
            locations.append(output.length); values.append(value); output.append(value)
            previousBlank = blank; previousAfter = after; previousQuotes = quotes
            innerAfter = formattedContext.flatMap { MacBlockPrefix($0.textBlock)?.heading == true ? nil : $0 }
        }
        let remaining = items.indices.filter { !removed.contains($0) }
        let prepared = rebindingGaps(MacMarkdown.refreshingListContexts(output), original: original, items: items, order: remaining, parent: { parents[$0] })
        let mapped = Dictionary(uniqueKeysWithValues: remaining.enumerated().map { ($0.element, $0.offset) })
        func valid(_ text: NSAttributedString) -> Bool {
            if localOnly { return true }
            guard let actual = MacMarkdown.nativeListItems(in: text), actual.count == remaining.count else { return false }
            return remaining.enumerated().allSatisfy { actual[$0.offset].parent == parents[$0.element].flatMap { mapped[$0] } }
        }
        guard valid(prepared) else { return .refused(formattingIssue) }
        func position(_ anchor: Anchor) -> Int {
            let unit = units[anchor.unit]
            guard let change = changes[anchor.unit] else { return locations[anchor.unit] + min(anchor.local, unit.text.length) }
            let raw = unit.text.string as NSString
            let count = min(max(0, anchor.local - change.old), max(0, raw.length - change.old))
            var body = raw.substring(with: NSRange(location: change.old, length: count))
            if change.collapse { body = body.replacingOccurrences(of: "\u{2028}+", with: " ", options: .regularExpression) }
            return locations[anchor.unit] + change.new + body.utf16.count
        }
        let start = position(startAnchor), end = position(endAnchor)
        var typing: [NSAttributedString.Key: Any]?
        if let block = chosenBlocks[startAnchor.unit] {
            let value = values[startAnchor.unit], range = units[startAnchor.unit].range
            let point = max(0, start - locations[startAnchor.unit])
            let inherited: [NSAttributedString.Key: Any]
            if value.length > 0, selection.length > 0 || point > 0 {
                inherited = value.attributes(at: min(selection.length == 0 ? point - 1 : point, value.length - 1), effectiveRange: nil)
            } else { inherited = [:] }
            let context = start < prepared.length ? prepared.attribute(.macListContext, at: start, effectiveRange: nil) as? MacListContext : nil
            let role = context?.textBlock ?? block
            let font = inherited[.font] as? NSFont ?? MacMarkdown.font(role), traits = NSFontManager.shared.traits(of: font)
            let bold = MacMarkdown.inlineBold(inherited, block: role)
            let image = inherited[.macLiteral] != nil || inherited[.attachment] != nil
            let code = !image && traits.contains(.fixedPitchFontMask)
            typing = [.macBlock: context?.block ?? block, .font: MacMarkdown.inlineFont(block: role, bold: bold, italic: traits.contains(.italicFontMask), code: code), .foregroundColor: NSColor.labelColor, .paragraphStyle: context?.style ?? MacMarkdown.paragraphStyle(block), .macStrong: bold]
            if let context { typing?[.macListContext] = context; typing?[.macIndependentParagraph] = false }
            if code { typing?[.backgroundColor] = NSColor.quaternaryLabelColor }
            if !image, let link = inherited[.link] { typing?[.link] = link }
            if let strike = inherited[.strikethroughStyle] { typing?[.strikethroughStyle] = strike }
            let newline = raw.substring(with: range).hasSuffix("\n") ? NSMaxRange(range) - 1 : max(0, range.location - 1)
            typing?[.macLineEnding] = original.attribute(.macLineEnding, at: newline, effectiveRange: nil) ?? "\n"
        }
        return .changed(Edit(text: prepared, selection: NSRange(location: min(start, end), length: abs(end - start)), typing: typing))
    }

    /// Keyboard clearing and Cut share the final body's role/ending lifecycle.
    /// The edit is prepared from the retained note; clipboard export still uses
    /// the original selection. A synthetic terminator adds no Markdown newline.
    static func clearingFinalTextBlock(_ original: NSAttributedString, range: NSRange) -> Edit? {
        guard range.length > 0, range.location < original.length, NSMaxRange(range) <= original.length else { return nil }
        let raw = original.string as NSString, row = raw.paragraphRange(for: NSRange(location: range.location, length: 0))
        guard NSMaxRange(row) == original.length else { return nil }
        let terminated = raw.substring(with: row).hasSuffix("\n")
        let bodyEnd = NSMaxRange(row) - (terminated ? 1 : 0)
        let attrs = original.attributes(at: row.location, effectiveRange: nil)
        let context = attrs[.macListContext] as? MacListContext, block = attrs[.macBlock] as? String ?? ""
        let role = MacBlockPrefix(context?.textBlock ?? block)
        let bodyStart = row.location + MacMarkdown.displayPrefix(block).utf16.count
        guard range.location == bodyStart, NSMaxRange(range) == bodyEnd,
              role?.heading == true || (role?.depth ?? 0) > 0 || context?.blockParagraph == true,
              attrs[.macCode] == nil, attrs[.macTable] == nil, attrs[.macRule] == nil else { return nil }
        var carrier = attrs
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macLiteral, .attachment, .macImageUnavailable] { carrier.removeValue(forKey: key) }
        carrier[.macUnterminated] = terminated ? original.attribute(.macUnterminated, at: bodyEnd, effectiveRange: nil) : true
        if context?.blockParagraph == true, context?.quoteLeaf != true, role?.heading != true { carrier[.macEmptyParagraph] = true }
        let output = NSMutableAttributedString(attributedString: original)
        output.replaceCharacters(in: range, with: NSAttributedString(string: terminated ? "" : "\n", attributes: carrier))
        output.setAttributes(carrier, range: NSRange(location: bodyStart, length: 1))
        var typing = carrier; typing.removeValue(forKey: .macUnterminated)
        return Edit(text: output, selection: NSRange(location: bodyStart, length: 0), typing: typing)
    }

    /// Empty text-block Backspace is a command even at document start, where
    /// AppKit has no character to offer to shouldChangeTextIn. It removes just
    /// that block, preserving a following explicit paragraph and one Undo step.
    static func backspacingEmptyBlock(_ original: NSAttributedString, caret: NSRange) -> Outcome {
        guard caret.length == 0, caret.location < original.length else { return .notList }
        let raw = original.string as NSString, row = raw.paragraphRange(for: caret)
        guard caret.location == row.location else { return .notList }
        let attrs = original.attributes(at: row.location, effectiveRange: nil)
        let context = attrs[.macListContext] as? MacListContext
        let block = attrs[.macBlock] as? String ?? ""
        let prefix = MacBlockPrefix(block)
        let inner = context.map { $0.continuation && (!$0.suffix.isEmpty || $0.blockParagraph) } ?? false
        guard inner || context == nil && (prefix?.heading == true && prefix?.depth == 0 || prefix?.heading != true && prefix?.depth == 1),
              raw.substring(with: row).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              attrs[.macCode] == nil, attrs[.macTable] == nil, attrs[.macRule] == nil else { return .notList }
        let output = NSMutableAttributedString(attributedString: original)
        var previous: NSRange?, before = row.location
        while before > 0 {
            let candidate = raw.paragraphRange(for: NSRange(location: before - 1, length: 0))
            let values = original.attributes(at: candidate.location, effectiveRange: nil)
            before = candidate.location
            if values[.macCode] != nil || values[.macTable] != nil || values[.macRule] != nil { return .notList }
            let candidateBlock = values[.macBlock] as? String ?? ""
            let quoteGap = context == nil && prefix?.depth == 1 && MacBlockPrefix(candidateBlock)?.depth == 1 && MacBlockPrefix(candidateBlock)?.marker.isEmpty == true
            if raw.substring(with: candidate).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               values[.macListContext] == nil, values[.macEmptyParagraph] as? Bool != true,
               candidateBlock.isEmpty || quoteGap { continue }
            previous = candidate; break
        }
        let position: Int
        var typing: [NSAttributedString.Key: Any]
        if let previous {
            let end = NSMaxRange(previous)
            position = end - (raw.substring(with: previous).hasSuffix("\n") ? 1 : 0)
            typing = original.attributes(at: max(previous.location, position - 1), effectiveRange: nil)
            output.deleteCharacters(in: NSRange(location: end, length: NSMaxRange(row) - end))
            if NSMaxRange(row) == original.length,
               attrs[.macUnterminated] as? Bool == true, end > position {
                output.addAttribute(.macUnterminated, value: true, range: NSRange(location: position, length: 1))
            }
        } else {
            guard context == nil, row.location == 0 else { return .notList }
            var nextQuoteParagraph: NSRange?, after = NSMaxRange(row)
            if prefix?.heading != true, prefix?.depth == 1 {
                while after < original.length {
                    let candidate = raw.paragraphRange(for: NSRange(location: after, length: 0))
                    let values = original.attributes(at: candidate.location, effectiveRange: nil)
                    guard let candidatePrefix = MacBlockPrefix(values[.macBlock] as? String ?? ""), candidatePrefix.depth > 0 else { break }
                    guard candidatePrefix.depth == 1 else { return .notList }
                    // Cards and child lists keep their existing command path
                    // until their quote-boundary keyboard behavior is verified.
                    guard values[.macListContext] == nil, values[.macCode] == nil, values[.macTable] == nil, values[.macRule] == nil else { return .notList }
                    after = NSMaxRange(candidate)
                    if candidatePrefix.marker.isEmpty,
                       raw.substring(with: candidate).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       values[.macEmptyParagraph] as? Bool != true { continue }
                    nextQuoteParagraph = candidate; break
                }
            }
            if let next = nextQuoteParagraph {
                typing = original.attributes(at: next.location, effectiveRange: nil)
                output.deleteCharacters(in: NSRange(location: row.location, length: next.location - row.location))
                position = 0
            } else {
                let plain = NSMutableAttributedString(attributedString: MacMarkdown.settingBlock(original.attributedSubstring(from: row), to: ""))
                plain.addAttribute(.macEmptyParagraph, value: true, range: NSRange(location: 0, length: plain.length))
                output.replaceCharacters(in: row, with: plain)
                position = 0; typing = plain.attributes(at: 0, effectiveRange: nil)
            }
        }
        if let items = MacMarkdown.nativeListItems(in: original) {
            guard let after = MacMarkdown.nativeListItems(in: output), after.count == items.count,
                  zip(items, after).allSatisfy({ $0.parent == $1.parent }) else { return .refused(issue) }
        } else { return .refused(issue) }
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListGap, .macEmptyParagraph, .macLiteral, .attachment, .macImageUnavailable, .macHardBreak, .macListBreak, .macUnterminated] { typing.removeValue(forKey: key) }
        return .changed(Edit(text: output, selection: NSRange(location: position, length: 0), typing: typing))
    }

    /// A nonempty inner block cannot absorb the item's flat leading text (or
    /// a preceding child item) when Backspace crosses its boundary. Move to that
    /// visible text without manufacturing an edit or an Undo event. Structured
    /// paragraph/heading peers still use the ordinary checked merge path.
    static func innerBackspaceNavigation(in original: NSAttributedString, caret: NSRange) -> (selection: NSRange, typing: [NSAttributedString.Key: Any])? {
        guard caret.length == 0, caret.location > 0, caret.location < original.length else { return nil }
        let raw = original.string as NSString, current = raw.paragraphRange(for: caret)
        guard current.location == caret.location,
              !raw.substring(with: current).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let context = original.attribute(.macListContext, at: current.location, effectiveRange: nil) as? MacListContext,
              context.continuation, !context.suffix.isEmpty,
              let head = MacMarkdown.listHeadParagraph(in: original, paragraph: current), head != current,
              MacBlockPrefix(original.attribute(.macBlock, at: head.location, effectiveRange: nil) as? String ?? "")?.list == true else { return nil }
        var before = current.location
        while before > head.location {
            let row = raw.paragraphRange(for: NSRange(location: before - 1, length: 0))
            let attrs = original.attributes(at: row.location, effectiveRange: nil)
            before = row.location
            if attrs[.macCode] != nil || attrs[.macTable] != nil || attrs[.macRule] != nil { return nil }
            if attrs[.macListGap] != nil, raw.substring(with: row).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            guard let previous = attrs[.macListContext] as? MacListContext,
                  previous.id != context.id || previous.suffix.isEmpty && !previous.blockParagraph else { return nil }
            let at = NSMaxRange(row) - (raw.substring(with: row).hasSuffix("\n") ? 1 : 0)
            var typing = original.attributes(at: max(row.location, at - 1), effectiveRange: nil)
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListGap, .macLiteral, .attachment, .macImageUnavailable, .macHardBreak, .macListBreak, .macUnterminated] { typing.removeValue(forKey: key) }
            return (NSRange(location: at, length: 0), typing)
        }
        return nil
    }

    /// Backspace at the body's start removes a root list wrapper, or lifts a
    /// nested item one level. Child subtrees and later paragraphs keep their text.
    static func lift(_ original: NSAttributedString, paragraph: NSRange) -> Outcome {
        lifting(original, paragraph: paragraph, removingHead: false)
    }
    /// Delete and Cut share the same exact-paragraph ownership boundary.
    static func deletingParagraph(_ original: NSAttributedString, range: NSRange, cut: Bool = false) -> Outcome {
        if let edit = MacHorizontalRule.removingOwnedRule(original, range: range) { return .changed(edit) }
        guard range.length > 0, NSMaxRange(range) <= original.length else { return .notList }
        let raw = original.string as NSString, paragraph = raw.paragraphRange(for: NSRange(location: range.location, length: 0))
        guard range == paragraph,
              let prefix = MacBlockPrefix(original.attribute(.macBlock, at: range.location, effectiveRange: nil) as? String ?? ""), prefix.list,
              raw.substring(with: paragraph).hasPrefix(prefix.display) else { return .notList }
        if cut, NSMaxRange(range) == original.length,
           raw.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines) == prefix.display.trimmingCharacters(in: .whitespaces) {
            // Cut removes the selected final row. Delete on a selected marker
            // still lifts it, matching the keyboard command's existing policy.
            let output = NSMutableAttributedString(attributedString: original); output.deleteCharacters(in: range)
            if output.length > 0 {
                let newline = raw.substring(with: range).hasSuffix("\n") ? NSMaxRange(range) - 1 : max(0, range.location - 1)
                let ending = original.attribute(.macLineEnding, at: newline, effectiveRange: nil) as? String ?? "\n"
                output.append(NSAttributedString(string: "\n", attributes: [.macBlock: prefix.quotes, .font: MacMarkdown.font(prefix.quotes), .paragraphStyle: MacMarkdown.paragraphStyle(prefix.quotes), .macLineEnding: ending]))
            }
            return .changed(Edit(text: output, selection: NSRange(location: output.length, length: 0)))
        }
        return raw.substring(with: paragraph) == prefix.display ? lift(original, paragraph: paragraph) : removeHead(original, paragraph: paragraph)
    }
    /// Removing a complete head promotes its children into the old parent and
    /// transfers its trailing paragraphs to that parent, preserving their order.
    static func removeHead(_ original: NSAttributedString, paragraph: NSRange) -> Outcome {
        if MacMarkdown.nativeListItems(in: original) == nil,
           let region = MacMarkdown.nativeListRegion(in: original, around: paragraph.location),
           let _ = MacMarkdown.nativeListItems(in: original.attributedSubstring(from: region)) {
            let local = NSRange(location: paragraph.location - region.location, length: paragraph.length)
            switch lifting(original.attributedSubstring(from: region), paragraph: local, removingHead: true) {
            case .changed(let edit):
                let output = NSMutableAttributedString(attributedString: original)
                output.replaceCharacters(in: region, with: edit.text)
                return .changed(Edit(text: output, selection: NSRange(location: region.location + edit.selection.location, length: edit.selection.length), typing: edit.typing))
            case let outcome: return outcome
            }
        }
        return lifting(original, paragraph: paragraph, removingHead: true)
    }
    private static func lifting(_ original: NSAttributedString, paragraph: NSRange, removingHead: Bool) -> Outcome {
        let block = original.attribute(.macBlock, at: paragraph.location, effectiveRange: nil) as? String ?? ""
        let caret = NSRange(location: paragraph.location + MacMarkdown.displayPrefix(block).utf16.count, length: 0)
        guard let items = MacMarkdown.nativeListItems(in: original) else {
            if removingHead {
                // Native empty markers can temporarily be setext/lazy text in
                // Markdown. Establish their intended boundaries before mapping
                // an unrelated deletion, rather than refusing that deletion.
                let normalized = MacMarkdown.insertingEmptyListBoundaries(in: original)
                var shifted = paragraph
                shifted.location += normalized.locations.filter { $0 <= paragraph.location }.count
                guard MacMarkdown.nativeListItems(in: normalized.text) != nil else { return .refused(issue) }
                return lifting(normalized.text, paragraph: shifted, removingHead: true)
            }
            let recovered = indent(original, selection: caret, backward: true, adoptingFollowingSiblings: true)
            if case .changed = recovered { return recovered }
            guard let prepared = prepareEmptyItemBoundary(original, paragraph: paragraph) else { return recovered }
            let lifted = lift(prepared.text, paragraph: prepared.paragraph)
            guard prepared.items[prepared.row].parent != nil, case .changed(let edit) = lifted else { return lifted }
            var inserted: NSRange?
            edit.text.enumerateAttribute(.macParagraphID, in: NSRange(location: 0, length: edit.text.length)) { value, range, _ in
                if value as? String == prepared.token { inserted = range }
            }
            guard let inserted else { return lifted }
            let clean = NSMutableAttributedString(attributedString: edit.text); clean.deleteCharacters(in: inserted)
            guard let before = MacMarkdown.nativeListItems(in: edit.text), let after = MacMarkdown.nativeListItems(in: clean),
                  before.count == after.count, zip(before, after).allSatisfy({ $0.parent == $1.parent }) else { return lifted }
            let at = edit.selection.location >= NSMaxRange(inserted) ? edit.selection.location - inserted.length : edit.selection.location
            return .changed(Edit(text: clean, selection: NSRange(location: at, length: 0)))
        }
        guard let root = items.firstIndex(where: { $0.range.location == paragraph.location }) else { return .refused(issue) }
        let head = items[root]
        let quoteBoundary = head.parent.map { items[$0].block.depth < head.block.depth } == true
        if head.parent != nil, !removingHead, !quoteBoundary { return indent(original, selection: caret, backward: true, adoptingFollowingSiblings: true) }
        let parentContext = head.parent.flatMap { original.attribute(.macListContext, at: items[$0].range.location, effectiveRange: nil) as? MacListContext }
        let promotedParent = removingHead || quoteBoundary ? head.parent : nil
        func descendant(_ row: Int) -> Bool {
            var parent = items[row].parent
            while let index = parent { if index == root { return true }; parent = items[index].parent }
            return false
        }
        var numbers: [Int: Int] = [:]
        if removingHead, head.block.marker.first?.isNumber == true,
           !(head.parent == nil && hasOwnedContent(in: original, paragraph: paragraph, items: items)),
           let first = items.first(where: { $0.container == head.container }), let start = Int(first.block.marker.prefix(while: \.isNumber)) {
            var number = start
            for row in items.indices where row != root && items[row].container == head.container {
                numbers[row] = number; number = min(999_999_999, number + 1)
            }
        }
        var prefixes: [Int: String] = [:], paddingChanges: [Int: Int] = [:]
        for row in items.indices where row != root {
            let prefix = items[row].block
            var source = prefix.source, parent = items[row].parent
            if descendant(row) { source = prefix.shiftingIndentation(by: -head.block.listPadding, atQuoteDepth: head.block.depth) }
            while let ancestor = parent {
                if let delta = paddingChanges[ancestor], delta != 0 {
                    source = MacBlockPrefix(source)!.shiftingIndentation(by: delta, atQuoteDepth: items[ancestor].block.depth)
                }
                parent = items[ancestor].parent
            }
            let marker = numbers[row].map { String($0) + prefix.marker.dropFirst(prefix.marker.prefix(while: \.isNumber).count) } ?? prefix.marker
            let updated = MacBlockPrefix(source)!
            let positioned = updated.replacingMarker(marker)
            prefixes[row] = positioned
            paddingChanges[row] = (MacBlockPrefix(positioned)?.listPadding ?? prefix.listPadding) - prefix.listPadding
        }
        func promotedGap(_ gap: String) -> String {
            MacMarkdownLines(gap).lines.map { row in
                guard row.text.unicodeScalars.allSatisfy({ [9, 32, 62].contains($0.value) }),
                      let prefix = MacBlockPrefix(row.text), prefix.depth > head.block.depth else { return row.text + row.ending }
                return prefix.shiftingIndentation(by: -head.block.listPadding, atQuoteDepth: head.block.depth) + row.ending
            }.joined()
        }
        let heads = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.range.location, $0.offset) })
        let raw = original.string as NSString
        var units: [Unit] = [], latest: [UUID: Int] = [:], offset = 0
        while offset < raw.length {
            let range = unitRange(in: original, at: offset)
            let context = original.attribute(.macListContext, at: offset, effectiveRange: nil) as? MacListContext
            var owner = heads[offset]
            if let row = owner, let context { latest[context.id] = row }
            else if let context, context.continuation { owner = latest[context.id] }
            if removingHead, offset == paragraph.location { offset = NSMaxRange(range); continue }
            var text = original.attributedSubstring(from: range)
            if owner == root {
                text = MacMarkdown.settingBlock(text, to: head.block.quotes + (context?.suffix ?? ""))
                if removingHead || quoteBoundary, let parentContext {
                    let inheritedQuotes = quoteBoundary ? String(repeating: "> ", count: max(0, head.block.depth - (MacBlockPrefix(parentContext.source)?.depth ?? 0))) : ""
                    let tail = MacListContext(id: parentContext.id, source: parentContext.source, continuation: true, gap: promotedGap(context?.gap ?? ""), originatedAfterChildren: context?.originatedAfterChildren ?? false, suffix: inheritedQuotes + (context?.suffix ?? ""), blockParagraph: context?.blockParagraph ?? false, quoteLeaf: context?.quoteLeaf ?? false, quoteParents: parentContext.quoteParents)
                    let updated = NSMutableAttributedString(attributedString: text)
                    updated.addAttributes([.macListContext: tail, .macBlock: tail.block, .paragraphStyle: tail.style], range: NSRange(location: 0, length: updated.length))
                    text = updated
                }
            }
            else if let row = heads[offset], let source = prefixes[row], source != items[row].block.source {
                text = MacMarkdown.settingBlock(text, to: source)
            }
            units.append(Unit(range: range, text: text, owner: owner)); offset = NSMaxRange(range)
        }
        let output = NSMutableAttributedString()
        var position = min(paragraph.location, output.length), previousConverted = false, previousBlank = true, previousDepth = 0
        for unit in units {
            let converted = unit.owner == root && !(removingHead && parentContext != nil)
            let blank = unit.text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // An emptied head still reserves a paragraph boundary for typing;
            // otherwise a following ordered start other than 1 becomes prose.
            let attrs = unit.text.length > 0 ? unit.text.attributes(at: 0, effectiveRange: nil) : [:]
            let context = attrs[.macListContext] as? MacListContext
            let block = attrs[.macBlock] as? String ?? ""
            let depth = MacBlockPrefix(context?.textBlock ?? block)?.depth ?? 0
            let originalContext = original.attribute(.macListContext, at: unit.range.location, effectiveRange: nil) as? MacListContext
            let quoteGap = blank && originalContext?.continuation == true && originalContext?.suffix.isEmpty == false && originalContext?.quoteLeaf != true && original.attribute(.macEmptyParagraph, at: unit.range.location, effectiveRange: nil) as? Bool != true
            let beforeConverted = converted && !quoteGap && !previousBlank && (!quoteBoundary || previousDepth >= head.block.depth)
            let afterConverted = previousConverted && !blank && (!quoteBoundary || depth >= head.block.depth)
            if output.length > 0, beforeConverted || afterConverted {
                let newline = raw.substring(with: unit.range).hasSuffix("\n") ? NSMaxRange(unit.range) - 1 : max(0, unit.range.location - 1)
                let ending = original.attribute(.macLineEnding, at: newline, effectiveRange: nil) as? String ?? "\n"
                let separator: String
                if quoteBoundary, let parentContext, let parent = MacBlockPrefix(parentContext.source) {
                    // Keep every quote shared by the neighboring blocks, without
                    // inventing a quote line when either side is outside it.
                    separator = parent.listContinuation + String(repeating: "> ", count: max(0, min(previousDepth, depth) - parent.depth))
                } else {
                    separator = head.block.quotes + String(repeating: "> ", count: max(0, min(previousDepth, depth) - head.block.depth))
                }
                let attributes: [NSAttributedString.Key: Any] = [.macBlock: separator, .font: MacMarkdown.font(separator), .paragraphStyle: MacMarkdown.paragraphStyle(separator), .macLineEnding: ending]
                output.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            if unit.range.location == head.range.location || (removingHead && unit.range.location < paragraph.location) { position = output.length + (removingHead ? unit.text.length : 0) }
            output.append(unit.text)
            previousConverted = converted && !quoteGap; previousBlank = blank; previousDepth = depth
        }
        if removingHead, position == output.length, output.length > 0 {
            let ending = output.attribute(.macLineEnding, at: output.length - 1, effectiveRange: nil) as? String ?? "\n"
            output.append(NSAttributedString(string: "\n", attributes: [.macBlock: head.block.quotes, .font: MacMarkdown.font(head.block.quotes), .paragraphStyle: MacMarkdown.paragraphStyle(head.block.quotes), .macLineEnding: ending]))
            position += 1
        }
        if removingHead, position < output.length {
            let raw = output.string as NSString
            let empty = raw.paragraphRange(for: NSRange(location: position, length: 0))
            let following = NSMaxRange(empty)
            if raw.substring(with: empty).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, following < output.length,
               MacBlockPrefix(output.attribute(.macBlock, at: following, effectiveRange: nil) as? String ?? "")?.list == true {
                var attrs = output.attributes(at: empty.location, effectiveRange: nil)
                for key in [NSAttributedString.Key.macListContext, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macOriginal, .macSignature] { attrs.removeValue(forKey: key) }
                output.insert(NSAttributedString(string: "\n", attributes: attrs), at: following)
            }
        }
        // Removing one wrapper promotes only its direct children. All other
        // relationships must survive the source spelling generated above.
        let remaining = items.indices.filter { $0 != root }
        let indices = Dictionary(uniqueKeysWithValues: remaining.enumerated().map { ($0.element, $0.offset) })
        let prepared = rebindingGaps(MacMarkdown.refreshingListContexts(output), original: original, items: items, order: remaining, parent: { row in
            items[row].parent == root ? promotedParent : items[row].parent
        })
        guard let after = MacMarkdown.nativeListItems(in: prepared), after.count == remaining.count,
              remaining.enumerated().allSatisfy({ index, row in
                  let parent = items[row].parent
                  return after[index].parent == (parent == root ? promotedParent.flatMap { indices[$0] } : parent.flatMap { indices[$0] })
              }) else { return .refused(issue) }
        if removingHead, position < prepared.length {
            let next = (prepared.string as NSString).paragraphRange(for: NSRange(location: position, length: 0))
            let block = prepared.attribute(.macBlock, at: next.location, effectiveRange: nil) as? String ?? ""
            let marker = MacMarkdown.displayPrefix(block)
            if position == next.location, prepared.attributedSubstring(from: next).string.hasPrefix(marker) { position += marker.utf16.count }
        }
        return .changed(Edit(text: prepared, selection: NSRange(location: position, length: 0)))
    }

    static func indent(_ original: NSAttributedString, selection: NSRange, backward: Bool, adoptingFollowingSiblings: Bool = false) -> Outcome {
        let raw = original.string as NSString
        guard raw.length > 0, selection.location <= raw.length, NSMaxRange(selection) <= raw.length else { return .notList }
        let atTextEnd = selection.location == raw.length && !original.string.hasSuffix("\n")
        let selected = NSRange(location: atTextEnd ? raw.length - 1 : selection.location, length: max(0, selection.length - 1))
        let full = raw.paragraphRange(for: selected)
        guard full.length > 0 else { return .notList }
        var touchesList = false
        original.enumerateAttributes(in: full) { attrs, _, stop in
            if MacBlockPrefix(attrs[.macBlock] as? String ?? "")?.list == true || (attrs[.macListContext] as? MacListContext)?.continuation == true {
                touchesList = true; stop.pointee = true
            }
        }
        guard touchesList else { return .notList }
        guard let items = MacMarkdown.nativeListItems(in: original) else {
            return recoverEmptyLastItem(original, selection: selection, full: full, backward: backward)
        }
        let byStart = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.range.location, $0.offset) })
        var units: [Unit] = [], headUnits = [Int](repeating: 0, count: items.count)
        var latestHead: [UUID: Int] = [:], chosen = Set<Int>(), mixed = false, offset = 0
        while offset < raw.length {
            let range = unitRange(in: original, at: offset)
            let context = original.attribute(.macListContext, at: offset, effectiveRange: nil) as? MacListContext
            var owner = byStart[offset]
            if let row = owner {
                headUnits[row] = units.count
                if let context { latestHead[context.id] = row }
            } else if let context, context.continuation { owner = latestHead[context.id] }
            if NSIntersectionRange(range, full).length > 0 {
                if let owner { chosen.insert(owner) }
                else if !raw.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { mixed = true }
            }
            units.append(Unit(range: range, text: original.attributedSubstring(from: range), owner: owner))
            offset = NSMaxRange(range)
        }
        guard !mixed else { return .refused(nil) }
        guard !chosen.isEmpty else { return .refused(issue) }
        func descends(_ row: Int, from root: Int) -> Bool {
            var current: Int? = row
            while let index = current {
                if index == root { return true }
                current = items[index].parent
            }
            return false
        }
        let roots = chosen.filter { row in
            var parent = items[row].parent
            while let index = parent {
                if chosen.contains(index) { return false }
                parent = items[index].parent
            }
            return true
        }.sorted()
        guard let first = roots.first, let last = roots.last,
              roots.allSatisfy({ items[$0].container == items[first].container }) else { return .refused(nil) }
        let oldParent = items[first].parent
        let newParent: Int?
        let width: Int
        if backward {
            guard let parent = oldParent else { return .unchanged }
            // List indentation stops at a quote boundary, as in the web list
            // command. Backspace's separate lifting policy remains independent.
            if !adoptingFollowingSiblings, items[parent].block.depth < items[first].block.depth { return .unchanged }
            newParent = items[parent].parent; width = items[parent].block.indent
        } else {
            guard let previous = items.indices.prefix(first).last(where: { items[$0].container == items[first].container }) else { return .unchanged }
            newParent = previous; width = items[previous].block.indent + items[previous].block.listPadding
        }
        let rootSet = Set(roots)
        let oldContainer = items.indices.filter { items[$0].container == items[first].container }
        guard !adoptingFollowingSiblings || backward && roots.count == 1 else { return .refused(issue) }
        // Lexical's Backspace lifts in place: its following sibling list is
        // attached below the lifted item. Tab keeps its whole-item move policy.
        let adopted = adoptingFollowingSiblings ? oldContainer.filter { $0 > last } : []
        let adoptedSet = Set(adopted)
        func adoptedRoot(_ row: Int) -> Int? { adopted.first { descends(row, from: $0) } }
        func movedRoot(_ row: Int) -> Int? { roots.first { descends(row, from: $0) } ?? (adoptedRoot(row) == nil ? nil : first) }
        let movedRows = Set(items.indices.filter { movedRoot($0) != nil })
        let remaining = oldContainer.filter { !rootSet.contains($0) && !adoptedSet.contains($0) }
        var lastUnit = units.indices.filter { units[$0].owner.map { movedRows.contains($0) } == true }.max() ?? headUnits[last]
        // A selected trailing blank travels with the payload, so the selection
        // cannot stretch backwards over a sibling left behind by the reorder.
        while lastUnit + 1 < units.count, units[lastUnit + 1].owner == nil,
              units[lastUnit + 1].range.location < NSMaxRange(selection),
              units[lastUnit + 1].text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lastUnit += 1 }
        var firstUnit = headUnits[first]
        let retainContainerGap = oldContainer.first.map { rootSet.contains($0) } == true && !remaining.isEmpty
        // An old list's leading separator stays with its remaining items unless
        // the user explicitly selected that separator as part of the move.
        let laterParentContent = oldParent.map { parent in
            units.indices.contains { $0 > lastUnit && units[$0].owner.map { descends($0, from: parent) } == true }
        } ?? false
        if backward && laterParentContent {
            while firstUnit > 0, units[firstUnit - 1].owner == nil,
                  units[firstUnit - 1].text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if retainContainerGap, NSIntersectionRange(units[firstUnit - 1].range, selection).length == 0 { break }
                firstUnit -= 1
            }
        }
        let moving = Array(firstUnit...lastUnit), movingSet = Set(moving)
        guard moving.allSatisfy({ units[$0].owner != nil || units[$0].text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return .refused(issue) }
        func anchor(_ position: Int, previous: Bool) -> Anchor {
            let probe = min(raw.length - 1, max(0, position - (previous ? 1 : 0)))
            let unit = units.firstIndex { NSLocationInRange(probe, $0.range) }!
            return Anchor(unit: unit, local: position - units[unit].range.location)
        }
        let startAnchor = anchor(selection.location, previous: false)
        let endAnchor = selection.length == 0 ? startAnchor : anchor(NSMaxRange(selection), previous: true)
        var rootBlocks: [Int: MacBlockPrefix] = [:]
        var number = backward ? oldParent.flatMap { Int(items[$0].block.marker.prefix(while: \.isNumber)) }.map { $0 + 1 } ?? 1 : 1
        for root in roots {
            let old = items[root].block
            var marker = old.marker
            if marker.first?.isNumber == true {
                marker = String(min(999_999_999, number)) + marker.dropFirst(marker.prefix(while: \.isNumber).count)
                number += 1
            }
            let positioned = MacBlockPrefix(old.indented(width))!
            rootBlocks[root] = MacBlockPrefix(positioned.replacingMarker(marker))!
        }
        var prefixChanges: [Int: (old: Int, new: Int)] = [:]
        func rewrite(_ row: Int, to block: String) {
            let unit = headUnits[row], oldMarker = MacMarkdown.displayPrefix(items[row].block.source), newMarker = MacMarkdown.displayPrefix(block)
            prefixChanges[unit] = (units[unit].text.string.hasPrefix(oldMarker) ? oldMarker.utf16.count : 0, newMarker.utf16.count)
            units[unit].text = MacMarkdown.settingBlock(units[unit].text, to: block)
        }
        for row in items.indices where movedRows.contains(row) {
            let root = movedRoot(row)!, oldRoot = items[root].block, target = rootBlocks[root]!
            let old = items[row].block
            let delta = target.indent - oldRoot.indent + (row == root ? 0 : target.listPadding - oldRoot.listPadding) + (adoptedRoot(row) == nil ? 0 : oldRoot.listPadding)
            rewrite(row, to: row == root ? target.source : old.shiftingIndentation(by: delta, atQuoteDepth: oldRoot.depth))
        }
        if let originalFirst = oldContainer.first,
           var ordinal = Int(items[originalFirst].block.marker.prefix(while: \.isNumber)) {
            for root in adopted {
                let unit = headUnits[root]
                let old = MacBlockPrefix(units[unit].text.attribute(.macBlock, at: 0, effectiveRange: nil) as? String ?? "")!
                let digits = old.marker.prefix(while: \.isNumber)
                let target = MacBlockPrefix(old.replacingMarker(String(ordinal) + old.marker.dropFirst(digits.count)))!
                for row in items.indices where descends(row, from: root) {
                    let current = MacBlockPrefix(units[headUnits[row]].text.attribute(.macBlock, at: 0, effectiveRange: nil) as? String ?? "")!
                    rewrite(row, to: row == root ? target.source : current.shiftingIndentation(by: target.listPadding - old.listPadding, atQuoteDepth: old.depth))
                }
                ordinal = min(999_999_999, ordinal + 1)
            }
        }
        if backward, let originalFirst = oldContainer.first,
           var ordinal = Int(items[originalFirst].block.marker.prefix(while: \.isNumber)) {
            // Removing a first ordered child must not leave a >1 marker trying
            // to interrupt its parent's paragraph. Preserve the old list start,
            // updating descendant padding whenever a remaining marker shrinks.
            for root in remaining {
                let old = items[root].block, digits = old.marker.prefix(while: \.isNumber)
                if Int(digits) != ordinal {
                    let target = MacBlockPrefix(old.replacingMarker(String(ordinal) + old.marker.dropFirst(digits.count)))!
                    for row in items.indices where descends(row, from: root) {
                        rewrite(row, to: row == root ? target.source : items[row].block.shiftingIndentation(by: target.listPadding - old.listPadding, atQuoteDepth: old.depth))
                    }
                }
                ordinal = min(999_999_999, ordinal + 1)
            }
        }
        var order = Array(units.indices)
        let quotes = items[first].block.quotes.trimmingCharacters(in: .whitespaces)
        let head = original.attributes(at: NSMaxRange(items[first].range) - 1, effectiveRange: nil)
        let ending = head[.macLineEnding] as? String ?? "\n"
        func separator() -> Int {
            let index = units.count
            units.append(Unit(range: NSRange(location: 0, length: 0), text: NSAttributedString(string: "\n", attributes: [.macBlock: quotes, .macLineEnding: ending, .paragraphStyle: MacMarkdown.paragraphStyle(quotes)]), owner: nil))
            return index
        }
        if backward, let parent = oldParent, laterParentContent {
            guard let destination = units.indices.last(where: { !movingSet.contains($0) && units[$0].owner.map { descends($0, from: parent) } == true }) else { return .refused(issue) }
            order.removeAll { movingSet.contains($0) }
            guard let target = order.firstIndex(of: destination) else { return .refused(issue) }
            order.insert(contentsOf: moving, at: target + 1)
        }
        func rebuild() -> (NSAttributedString, [Int: Int]) {
            let output = NSMutableAttributedString()
            var locations: [Int: Int] = [:]
            for index in order {
                locations[index] = output.length
                let unit = units[index]
                output.append(unit.text)
                if index != order.last, !unit.text.string.hasSuffix("\n") {
                    var attrs = unit.text.length > 0 ? unit.text.attributes(at: unit.text.length - 1, effectiveRange: nil) : [:]
                    attrs[.macLineEnding] = attrs[.macLineEnding] ?? ending
                    output.append(NSAttributedString(string: "\n", attributes: attrs))
                }
            }
            let byUnit = Dictionary(uniqueKeysWithValues: headUnits.enumerated().map { ($0.element, $0.offset) })
            let rows = order.compactMap { byUnit[$0] }
            let prepared = rebindingGaps(MacMarkdown.refreshingListContexts(output), original: original, items: items, order: rows, parent: { row in
                adoptedSet.contains(row) ? first : rootSet.contains(row) ? newParent : items[row].parent
            })
            return (prepared, locations)
        }
        func valid(_ text: NSAttributedString, locations: [Int: Int], through row: Int? = nil) -> Bool {
            let limit = row.map { min(text.length, locations[headUnits[$0]]! + units[headUnits[$0]].text.length) } ?? text.length
            let expectedRows = items.indices.filter { locations[headUnits[$0]]! < limit }
            guard let actual = MacMarkdown.nativeListItems(in: text.attributedSubstring(from: NSRange(location: 0, length: limit))), actual.count == expectedRows.count else { return false }
            let byLocation = Dictionary(uniqueKeysWithValues: actual.enumerated().map { ($0.element.range.location, $0.offset) })
            for row in expectedRows {
                guard let location = locations[headUnits[row]], let index = byLocation[location] else { return false }
                let expected = adoptedSet.contains(row) ? first : rootSet.contains(row) ? newParent : items[row].parent
                if let expected {
                    guard let parent = actual[index].parent, actual[parent].range.location == locations[headUnits[expected]] else { return false }
                } else if actual[index].parent != nil { return false }
            }
            return true
        }
        var (output, locations) = rebuild()
        func ensureStart(_ row: Int) -> Bool {
            if valid(output, locations: locations, through: row) { return true }
            guard let position = order.firstIndex(of: headUnits[row]) else { return false }
            order.insert(separator(), at: position)
            (output, locations) = rebuild()
            return valid(output, locations: locations, through: row)
        }
        if backward, let firstRemaining = remaining.first, !ensureStart(firstRemaining) { return .refused(issue) }
        guard ensureStart(first) else { return .refused(issue) }
        if let firstAdopted = adopted.first, !ensureStart(firstAdopted) { return .refused(issue) }
        // A moved ')' list may split an enclosing '.' list. Its following
        // sibling must still be able to start its own original list afterward.
        let rowByUnit = Dictionary(uniqueKeysWithValues: headUnits.enumerated().map { ($0.element, $0.offset) })
        if let end = moving.last.flatMap({ order.firstIndex(of: $0) }),
           let following = order.dropFirst(end + 1).compactMap({ rowByUnit[$0] }).first,
           !ensureStart(following) { return .refused(issue) }
        guard valid(output, locations: locations) else { return .refused(issue) }
        func mapped(_ anchor: Anchor) -> Int {
            var local = anchor.local
            if let change = prefixChanges[anchor.unit] {
                local = local < change.old ? min(local, change.new) : change.new + local - change.old
            }
            return locations[anchor.unit]! + min(max(0, local), units[anchor.unit].text.length)
        }
        let start = mapped(startAnchor), end = mapped(endAnchor)
        return .changed(Edit(text: output, selection: NSRange(location: min(start, end), length: abs(end - start))))
    }

    /// Recover an empty final native row created by an earlier split, even when
    /// CommonMark still sees that marker as the preceding paragraph's text.
    private static func recoverEmptyLastItem(_ text: NSAttributedString, selection: NSRange, full: NSRange, backward: Bool) -> Outcome {
        let raw = text.string as NSString
        guard backward, selection.length == 0, full.location < raw.length,
              raw.substring(from: NSMaxRange(full)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let block = MacBlockPrefix(text.attribute(.macBlock, at: full.location, effectiveRange: nil) as? String ?? ""), block.list, block.indent > 0,
              raw.substring(with: full).trimmingCharacters(in: .whitespacesAndNewlines) == block.display.trimmingCharacters(in: .whitespaces) else { return .refused(issue) }
        var previous = full.location, ancestor: MacBlockPrefix?, ancestorLocation: Int?
        while previous > 0 {
            let range = raw.paragraphRange(for: NSRange(location: previous - 1, length: 0)); previous = range.location
            if raw.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            guard let candidate = MacBlockPrefix(text.attribute(.macBlock, at: range.location, effectiveRange: nil) as? String ?? ""), candidate.list, candidate.depth == block.depth else { break }
            if candidate.indent < block.indent { ancestor = candidate; ancestorLocation = range.location; break }
        }
        guard let ancestor, let ancestorLocation else { return .refused(issue) }
        var marker = block.marker
        if marker.first?.isNumber == true {
            let number = Int(ancestor.marker.prefix(while: \.isNumber)).map { min(999_999_999, $0 + 1) } ?? 1
            marker = String(number) + marker.dropFirst(marker.prefix(while: \.isNumber).count)
        }
        let next = block.quotes + String(repeating: " ", count: ancestor.indent) + marker
        let output = NSMutableAttributedString(attributedString: text)
        output.replaceCharacters(in: full, with: MacMarkdown.settingBlock(text.attributedSubstring(from: full), to: next))
        guard let actual = MacMarkdown.nativeListItems(in: output),
              let recovered = actual.first(where: { $0.range.location == full.location }),
              let previousParent = actual.first(where: { $0.range.location == ancestorLocation }),
              recovered.parent == previousParent.parent else { return .refused(issue) }
        let caret = full.location + MacMarkdown.displayPrefix(next).utf16.count
        return .changed(Edit(text: output, selection: NSRange(location: caret, length: 0)))
    }
}
