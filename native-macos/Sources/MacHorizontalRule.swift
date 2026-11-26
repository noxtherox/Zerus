import AppKit

extension NSAttributedString.Key {
    static let macRule = Self("ZerusMacRule")
    static let macRuleGap = Self("ZerusMacRuleGap")
}

/// A block attachment fills the current writing column without becoming an image asset.
final class MacRuleAttachment: NSTextAttachment {
    /// Follows the editor theme; the editor recaches rule images when it changes.
    static var strokeColor: NSColor = .separatorColor
    init() {
        super.init(data: nil, ofType: nil)
        bounds = NSRect(x: 0, y: 0, width: 800, height: 22)
        image = NSImage(size: bounds.size, flipped: false) { rect in
            MacRuleAttachment.strokeColor.setStroke()
            let path = NSBezierPath(); path.move(to: NSPoint(x: 0, y: rect.midY))
            path.line(to: NSPoint(x: rect.width, y: rect.midY)); path.lineWidth = 1; path.stroke()
            return true
        }
        image?.accessibilityDescription = "Horizontal rule"
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(x: 0, y: 0, width: max(1, lineFrag.width - (textContainer?.lineFragmentPadding ?? 0) * 2), height: 22)
    }
}

enum MacHorizontalRule {
    /// Text beside a rule keeps its item/quote role without inheriting the
    /// attachment or the card placement token.
    static func continuationAttributes(_ original: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        let block = original[.macBlock] as? String ?? ""
        var attrs: [NSAttributedString.Key: Any] = [.macBlock: block, .font: MacMarkdown.font(block), .foregroundColor: NSColor.labelColor, .paragraphStyle: MacMarkdown.paragraphStyle(block), .macStrong: false, .macIndependentParagraph: true]
        if let owner = original[.macListContext] as? MacListContext {
            let suffix = (original[.macListCard] as? MacListCardPlacement)?.ownerSuffix ?? owner.suffix
            let context = MacListContext(id: owner.id, source: owner.source, continuation: true, suffix: suffix, quoteParents: owner.quoteParents)
            attrs[.macListContext] = context; attrs[.macBlock] = context.block
            attrs[.paragraphStyle] = context.style; attrs[.font] = MacMarkdown.font(context.textBlock)
            attrs[.macIndependentParagraph] = false
        }
        attrs[.macLineEnding] = original[.macLineEnding] ?? "\n"
        return attrs
    }
    enum SelectedReturn {
        case splitItem(MacListEditing.Edit)
        case completed(MacListEditing.Edit)
    }
    /// Selecting the attachment is a node selection: Enter keeps the rule and
    /// selects its next block before splitting, rather than replacing the node.
    static func selectedReturn(_ text: NSAttributedString, range: NSRange) -> SelectedReturn? {
        guard range.length == 1, range.location < text.length,
              text.attribute(.macRule, at: range.location, effectiveRange: nil) != nil else { return nil }
        let raw = text.string as NSString, row = raw.paragraphRange(for: range)
        guard range.location == row.location else { return nil }
        let attrs = text.attributes(at: row.location, effectiveRange: nil)
        let owner = attrs[.macListContext] as? MacListContext
        var next = NSMaxRange(row)
        while next < text.length {
            let candidate = raw.paragraphRange(for: NSRange(location: next, length: 0))
            let values = text.attributes(at: next, effectiveRange: nil)
            if !raw.substring(with: candidate).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || values[.macEmptyParagraph] as? Bool == true { break }
            next = NSMaxRange(candidate)
        }
        if let owner {
            if next < text.length {
                let values = text.attributes(at: next, effectiveRange: nil)
                if let tail = values[.macListContext] as? MacListContext, tail.id == owner.id, tail.continuation,
                   values[.macRule] == nil, values[.macCode] == nil, values[.macTable] == nil {
                    let paragraph = raw.paragraphRange(for: NSRange(location: next, length: 0))
                    let position = tail.suffix.isEmpty && !tail.blockParagraph
                        ? NSMaxRange(paragraph) - (raw.substring(with: paragraph).hasSuffix("\n") ? 1 : 0) : next
                    return .splitItem(MacListEditing.Edit(text: text, selection: NSRange(location: position, length: 0), typing: continuationAttributes(values)))
                }
            }
            // A child list/card stays on the right of the split. At the end of
            // an inner quote, the new item is outside that quote.
            let context = MacListContext(id: owner.id, source: owner.source, continuation: true, quoteParents: owner.quoteParents)
            var typing = continuationAttributes(attrs)
            typing[.macListContext] = context; typing[.macBlock] = context.block; typing[.paragraphStyle] = context.style
            let output = NSMutableAttributedString(attributedString: text)
            let at = NSMaxRange(row), boundary = raw.substring(with: row).hasSuffix("\n") ? "" : "\n"
            output.insert(NSAttributedString(string: boundary + "\n", attributes: typing), at: at)
            return .splitItem(MacListEditing.Edit(text: output, selection: NSRange(location: at + boundary.utf16.count, length: 0), typing: typing))
        }
        // Root paragraphs have no item Return transaction. Keep an explicit
        // empty paragraph before the selected next block, including in quotes.
        if next < text.length {
            let values = text.attributes(at: next, effectiveRange: nil)
            if values[.macListContext] == nil, values[.macCode] == nil, values[.macTable] == nil, values[.macRule] == nil {
                var typing = continuationAttributes(values)
                // The next paragraph's inline format continues at its start,
                // but a link boundary does not extend to the newly typed text.
                for key in [NSAttributedString.Key.font, .macStrong, .underlineStyle, .strikethroughStyle, .backgroundColor] {
                    if let value = values[key] { typing[key] = value }
                }
                let quotes = MacBlockPrefix(typing[.macBlock] as? String ?? "")?.quotes ?? ""
                var empty = continuationAttributes([.macBlock: quotes, .macLineEnding: typing[.macLineEnding]!]); empty[.macEmptyParagraph] = true
                var gap = empty; gap.removeValue(forKey: .macEmptyParagraph)
                let inserted = NSMutableAttributedString(string: "\n", attributes: empty); inserted.append(NSAttributedString(string: "\n", attributes: gap))
                let output = NSMutableAttributedString(attributedString: text); output.insert(inserted, at: next)
                return .completed(MacListEditing.Edit(text: output, selection: NSRange(location: next + inserted.length, length: 0), typing: typing))
            }
        }
        var typing = continuationAttributes([.macLineEnding: attrs[.macLineEnding] ?? "\n"])
        typing[.macEmptyParagraph] = true
        let output = NSMutableAttributedString(attributedString: text), at = NSMaxRange(row)
        let boundary = raw.substring(with: row).hasSuffix("\n") ? "" : "\n"
        output.insert(NSAttributedString(string: boundary + "\n", attributes: typing), at: at)
        return .completed(MacListEditing.Edit(text: output, selection: NSRange(location: at + boundary.utf16.count, length: 0), typing: typing))
    }
    struct PreparedItemReturn {
        let edit: MacListEditing.Edit
        let receivingChild: UUID?
        var completesReturn = false
    }
    /// Resolve the first following child by parser ownership, never indentation.
    /// A selected rule has a separate node-selection path and does not use this.
    private static func receivingChild(_ text: NSAttributedString, row: NSRange, head: NSRange) -> (id: UUID, items: [MacMarkdown.NativeListItem], empty: Bool)? {
        let next = NSMaxRange(row)
        guard next < text.length, text.attribute(.macCompactList, at: next, effectiveRange: nil) == nil,
              let child = text.attribute(.macListContext, at: next, effectiveRange: nil) as? MacListContext,
              !child.continuation, let prefix = MacBlockPrefix(child.source), prefix.list,
              let items = MacMarkdown.nativeListItems(in: text),
              let parent = items.firstIndex(where: { $0.range.location == head.location }),
              let index = items.firstIndex(where: { $0.range.location == next }), items[index].parent == parent else { return nil }
        let raw = text.string as NSString, part = raw.paragraphRange(for: NSRange(location: next, length: 0))
        let empty = !prefix.checklist && raw.substring(with: part).trimmingCharacters(in: .whitespacesAndNewlines) == prefix.display.trimmingCharacters(in: .whitespaces)
        return (child.id, items, empty)
    }
    /// An item boundary beside a rule uses ordinary list Return semantics.
    /// Prepare without publishing an intermediate edit or a second Undo event.
    static func preparingItemReturn(_ text: NSAttributedString, row: NSRange, before: Bool) -> PreparedItemReturn? {
        let attrs = text.attributes(at: row.location, effectiveRange: nil)
        guard attrs[.macListCard] is MacListCardPlacement,
              let context = attrs[.macListContext] as? MacListContext,
              let prefix = MacBlockPrefix(context.source), prefix.list,
              let head = MacMarkdown.listHeadParagraph(in: text, paragraph: row) else { return nil }
        let raw = text.string as NSString
        if raw.substring(with: head).trimmingCharacters(in: .whitespacesAndNewlines) == prefix.display.trimmingCharacters(in: .whitespaces), before {
            return preparingCompactBefore(text, row: row, head: head, context: context, prefix: prefix)
        }
        let typing = continuationAttributes(attrs)
        guard let receiving = typing[.macListContext] as? MacListContext else { return nil }
        let followingChild = before ? nil : receivingChild(text, row: row, head: head)
        let child = followingChild?.empty == true && receiving.suffix.isEmpty ? nil : followingChild
        if !receiving.suffix.isEmpty {
            return preparingQuotedItemReturn(text, row: row, before: before, context: context, quotes: receiving.suffix, child: child)
        }
        let at = before ? row.location : NSMaxRange(row)
        if !before, at < text.length {
            let next = text.attributes(at: at, effectiveRange: nil)
            if let tail = next[.macListContext] as? MacListContext, tail.id == context.id, tail.continuation, tail.suffix.isEmpty,
               next[.macRule] == nil, next[.macCode] == nil, next[.macTable] == nil {
                return .init(edit: MacListEditing.Edit(text: text, selection: NSRange(location: at, length: 0), typing: typing), receivingChild: child?.id)
            }
        }
        let output = NSMutableAttributedString(attributedString: text)
        let boundary = !before && !raw.substring(with: row).hasSuffix("\n") ? "\n" : ""
        output.insert(NSAttributedString(string: boundary + "\n", attributes: typing), at: at)
        return .init(edit: MacListEditing.Edit(text: output, selection: NSRange(location: at + boundary.utf16.count, length: 0), typing: typing), receivingChild: child?.id)
    }
    /// A first-block divider has an empty native head. Keep that head as the
    /// receiving item before the divider, and move its existing identity with
    /// the divider and all owned content to the following item.
    private static func preparingCompactBefore(_ text: NSAttributedString, row: NSRange, head: NSRange, context: MacListContext, prefix: MacBlockPrefix) -> PreparedItemReturn? {
        guard NSMaxRange(head) == row.location,
              let items = MacMarkdown.nativeListItems(in: text),
              let owner = items.firstIndex(where: { $0.range.location == head.location }) else { return nil }
        let next = prefix.next, right = MacListContext(id: context.id, source: next, quoteParents: context.quoteParents)
        let receiving = MacListContext(source: context.source, quoteParents: context.quoteParents)
        let output = NSMutableAttributedString(attributedString: text)
        let following = NSRange(location: NSMaxRange(head), length: text.length - NSMaxRange(head))
        text.enumerateAttribute(.macListContext, in: following) { value, range, _ in
            guard let tail = value as? MacListContext else { return }
            if tail.id == context.id, tail.continuation {
                let changed = tail.replacing(source: next)
                output.addAttributes([.macListContext: changed, .macBlock: changed.block, .paragraphStyle: changed.style], range: range)
            } else if tail.quoteParents.contains(where: { $0.id == context.id }) {
                let parents = tail.quoteParents.map { $0.id == context.id ? right : $0 }
                output.addAttribute(.macListContext, value: tail.replacing(source: tail.source, quoteParents: parents), range: range)
            }
        }
        let delta = (MacBlockPrefix(next)?.listPadding ?? 0) - prefix.listPadding
        if delta != 0 {
            for item in items.reversed() where item.range.location > head.location {
                var ancestor = item.parent, owned = false
                while let index = ancestor { if index == owner { owned = true; break }; ancestor = items[index].parent }
                if owned {
                    let source = item.block.shiftingIndentation(by: delta, atQuoteDepth: prefix.depth)
                    output.replaceCharacters(in: item.range, with: MacMarkdown.settingBlock(output.attributedSubstring(from: item.range), to: source))
                }
            }
        }
        let originalHead = text.attributedSubstring(from: head)
        let left = NSMutableAttributedString(attributedString: MacMarkdown.settingBlock(originalHead, to: context.source))
        let nextHead = NSMutableAttributedString(attributedString: MacMarkdown.settingBlock(originalHead, to: next))
        left.addAttribute(.macListContext, value: receiving, range: NSRange(location: 0, length: left.length))
        nextHead.addAttribute(.macListContext, value: right, range: NSRange(location: 0, length: nextHead.length))
        left.append(nextHead); output.replaceCharacters(in: head, with: left)
        let prepared = MacMarkdown.refreshingListContexts(output)
        let expected = items.enumerated().map { index, item -> Int? in
            guard let parent = item.parent else { return nil }
            return parent >= owner ? parent + 1 : parent
        }
        var parents = expected; parents.insert(items[owner].parent, at: owner)
        guard MacMarkdown.nativeListItems(in: prepared)?.map(\.parent) == parents else { return nil }
        var typing = continuationAttributes(text.attributes(at: head.location, effectiveRange: nil))
        typing[.macListContext] = receiving; typing[.macBlock] = receiving.block
        typing[.paragraphStyle] = receiving.style; typing[.font] = MacMarkdown.font(receiving.textBlock)
        return .init(edit: MacListEditing.Edit(text: prepared, selection: NSRange(location: head.location + prefix.display.utf16.count, length: 0), typing: typing), receivingChild: nil, completesReturn: true)
    }
    private static func droppingQuotes(_ source: String, count: Int) -> String? {
        var at = source.startIndex
        for _ in 0..<count {
            guard let marker = source[at...].firstIndex(of: ">"), source[at..<marker].allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
            at = source.index(after: marker)
            if at < source.endIndex, source[at] == " " { at = source.index(after: at) }
        }
        return String(source[at...])
    }
    /// A caret boundary in an item-owned quote splits the item outside that
    /// quote. Rebase its remaining direct blocks before the ordinary split.
    private static func preparingQuotedItemReturn(_ text: NSAttributedString, row: NSRange, before: Bool, context: MacListContext, quotes: String, child: (id: UUID, items: [MacMarkdown.NativeListItem], empty: Bool)?) -> PreparedItemReturn? {
        guard let quote = MacBlockPrefix(quotes), quote.depth > 0, quote.marker.isEmpty,
              let owner = MacBlockPrefix(context.source),
              let head = MacMarkdown.listHeadParagraph(in: text, paragraph: row) else { return nil }
        let raw = text.string as NSString
        let output = NSMutableAttributedString(attributedString: text)
        var at = before ? row.location : NSMaxRange(row)
        var rebasedHeads: [UUID: MacListContext] = [:], rebasedChild = false
        while at < text.length {
            let part = raw.paragraphRange(for: NSRange(location: at, length: 0)), attrs = text.attributes(at: at, effectiveRange: nil)
            guard let tail = attrs[.macListContext] as? MacListContext else { break }
            if tail.id != context.id {
                guard let crossed = tail.quoteParents.firstIndex(where: { $0.id == context.id }) else { break }
                guard attrs[.macCompactList] == nil, tail.source.hasPrefix(owner.listContinuation) else { return nil }
                let local = String(tail.source.dropFirst(owner.listContinuation.count))
                guard let prefix = MacBlockPrefix(local), prefix.depth > 0 else { return nil }
                // Quotes owned by a later child item remain inside that item.
                let nestedOwner = tail.quoteParents.dropFirst(crossed + 1).first
                let depth = nestedOwner.flatMap { MacBlockPrefix($0.source) }.map { $0.depth - owner.depth } ?? prefix.depth
                guard depth > 0, depth <= prefix.depth, let remainder = droppingQuotes(local, count: depth) else { return nil }
                let parents = tail.quoteParents.filter { $0.id != context.id }.map { rebasedHeads[$0.id] ?? $0 }
                let rebased = tail.replacing(source: owner.listContinuation + remainder, quoteParents: parents)
                output.addAttributes([.macListContext: rebased, .macBlock: rebased.block, .paragraphStyle: rebased.style], range: part)
                if !tail.continuation { rebasedHeads[tail.id] = rebased }
                rebasedChild = true; at = NSMaxRange(part); continue
            }
            guard tail.continuation else { break }
            let placement = attrs[.macListCard] as? MacListCardPlacement
            let suffix = placement?.ownerSuffix ?? tail.suffix
            guard let prefix = MacBlockPrefix(suffix), prefix.depth >= 1 else { break }
            // The item split leaves every direct inner quote on its right.
            // Retain distinct paragraph gaps when quote depths change.
            let remaining = String(suffix.dropFirst(prefix.quotes.count))
            let gap = MacMarkdownLines(tail.gap).lines.map { line -> String in
                let base = owner.listContinuation
                guard line.text.hasPrefix(base), let quote = MacBlockPrefix(String(line.text.dropFirst(base.count))), quote.depth > 0 else { return line.text + line.ending }
                let body = String(line.text.dropFirst(base.count + quote.quotes.count))
                return (body.trimmingCharacters(in: .whitespaces).isEmpty ? owner.quotes : base + body) + line.ending
            }.joined()
            let rebased = MacListContext(id: tail.id, source: tail.source, continuation: true, gap: gap, originatedAfterChildren: tail.originatedAfterChildren, suffix: placement == nil ? remaining : tail.suffix, blockParagraph: tail.blockParagraph, quoteParents: tail.quoteParents)
            output.addAttributes([.macListContext: rebased, .macBlock: rebased.block, .paragraphStyle: rebased.style], range: part)
            if let placement { output.addAttribute(.macListCard, value: placement.replacingOwnerSuffix(remaining), range: part) }
            at = NSMaxRange(part)
        }
        var target = row
        if before, row.location > 0 {
            let previous = raw.paragraphRange(for: NSRange(location: row.location - 1, length: 0))
            if raw.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let tail = text.attribute(.macListContext, at: previous.location, effectiveRange: nil) as? MacListContext,
               tail.id == context.id, tail.suffix.trimmingCharacters(in: .whitespaces) == quotes.trimmingCharacters(in: .whitespaces) {
                output.deleteCharacters(in: previous); target.location -= previous.length
            }
        }
        if rebasedChild {
            // Child lookup and this check share the exact unchanged input
            // snapshot. The transformed output still needs its own parse.
            guard let old = child?.items ?? MacMarkdown.nativeListItems(in: text), let updated = MacMarkdown.nativeListItems(in: output),
                  old.map(\.parent) == updated.map(\.parent),
                  old.map({ (text.attribute(.macListContext, at: $0.range.location, effectiveRange: nil) as? MacListContext)?.id }) == updated.map({ (output.attribute(.macListContext, at: $0.range.location, effectiveRange: nil) as? MacListContext)?.id }) else { return nil }
        }
        if before { return preparingItemReturn(output, row: target, before: true) }
        let next = NSMaxRange(row)
        // An existing empty child is the receiving paragraph. Leaving its
        // inner quote does not create another wrapper or split the parent.
        if child?.empty == true, next < output.length,
           let head = output.attribute(.macListContext, at: next, effectiveRange: nil) as? MacListContext,
           !head.continuation, head.id == child?.id {
            let caret = next + MacMarkdown.displayPrefix(head.block).utf16.count
            var typing = continuationAttributes(output.attributes(at: next, effectiveRange: nil))
            typing[.macListContext] = head; typing[.macBlock] = head.block
            typing[.paragraphStyle] = head.style; typing[.font] = MacMarkdown.font(head.textBlock)
            return .init(edit: MacListEditing.Edit(text: output, selection: NSRange(location: caret, length: 0), typing: typing), receivingChild: nil, completesReturn: true)
        }
        if next < output.length,
           let tail = output.attribute(.macListContext, at: next, effectiveRange: nil) as? MacListContext,
           tail.id == context.id, tail.continuation, tail.suffix.isEmpty,
           output.attribute(.macListCard, at: next, effectiveRange: nil) == nil {
            return .init(edit: MacListEditing.Edit(text: output, selection: NSRange(location: next, length: 0), typing: continuationAttributes(output.attributes(at: next, effectiveRange: nil))), receivingChild: child?.id)
        }
        let plain = MacListContext(id: context.id, source: context.source, continuation: true, quoteParents: context.quoteParents)
        var typing = continuationAttributes(text.attributes(at: row.location, effectiveRange: nil))
        typing[.macListContext] = plain; typing[.macBlock] = plain.block; typing[.paragraphStyle] = plain.style
        let boundary = raw.substring(with: row).hasSuffix("\n") ? "" : "\n"
        output.insert(NSAttributedString(string: boundary + "\n", attributes: typing), at: next)
        return .init(edit: MacListEditing.Edit(text: output, selection: NSRange(location: next + boundary.utf16.count, length: 0), typing: typing), receivingChild: child?.id)
    }
    /// Removing the whole attachment also retires its native terminator. A
    /// leftover card-only blank row must not hide a following owned paragraph.
    static func removingOwnedRule(_ text: NSAttributedString, range: NSRange) -> MacListEditing.Edit? {
        replacingOwnedRule(text, range: range, with: NSAttributedString())
    }
    static func replacingOwnedRule(_ text: NSAttributedString, range: NSRange, with replacement: NSAttributedString) -> MacListEditing.Edit? {
        guard range.length > 0, range.location < text.length, NSMaxRange(range) <= text.length else { return nil }
        let row = (text.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 0))
        let attrs = text.attributes(at: row.location, effectiveRange: nil)
        guard attrs[.macRule] != nil, attrs[.macListCard] is MacListCardPlacement,
              range == row || range == NSRange(location: row.location, length: 1) else { return nil }
        guard replacement.string.rangeOfCharacter(from: CharacterSet.newlines.subtracting(CharacterSet(charactersIn: "\u{2028}"))) == nil else { return nil }
        let typing = continuationAttributes(attrs)
        let output = NSMutableAttributedString(attributedString: text), value = NSMutableAttributedString(attributedString: replacement)
        if value.length > 0 {
            let full = NSRange(location: 0, length: value.length)
            for key in [NSAttributedString.Key.macRule, .macRuleGap, .macListCard, .macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macUnterminated] { value.removeAttribute(key, range: full) }
            var role = typing
            for key in [NSAttributedString.Key.font, .foregroundColor, .macStrong] { role.removeValue(forKey: key) }
            value.addAttributes(role, range: full)
            value.enumerateAttributes(in: full) { attrs, range, _ in
                if attrs[.font] == nil { value.addAttribute(.font, value: typing[.font]!, range: range) }
                if attrs[.foregroundColor] == nil { value.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
            }
            if (text.string as NSString).substring(with: row).hasSuffix("\n") { value.append(NSAttributedString(string: "\n", attributes: typing)) }
        }
        output.replaceCharacters(in: row, with: value)
        return MacListEditing.Edit(text: output, selection: NSRange(location: min(row.location + replacement.length, output.length), length: 0), typing: typing)
    }
    static func render(_ source: String, ending: String, preferredEnding: String? = nil) -> NSAttributedString {
        let raw = source.hasSuffix("\r") ? String(source.dropLast()) : source
        let quotes = MacBlockPrefix(raw)?.quotes ?? ""
        let marker = String(raw.dropFirst(quotes.count))
        let block: [NSAttributedString.Key: Any] = [.macBlock: quotes, .font: MacMarkdown.font(quotes), .paragraphStyle: MacMarkdown.paragraphStyle(quotes), .macLineEnding: preferredEnding ?? (ending.isEmpty ? "\n" : ending)]
        let value = NSMutableAttributedString(attachment: MacRuleAttachment())
        value.addAttributes(block.merging([.macRule: true, .macLiteral: marker], uniquingKeysWith: { _, new in new }), range: NSRange(location: 0, length: value.length))
        if !ending.isEmpty { value.append(NSAttributedString(string: "\n", attributes: block)) }
        value.addAttributes([.macParagraphID: UUID().uuidString, .macParagraphSource: raw + ending, .macParagraphSignature: MacMarkdown.signature(value)], range: NSRange(location: 0, length: value.length))
        return value
    }
}
