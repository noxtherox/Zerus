import AppKit
import Markdown

/// Quote boundary commands retain child block roles and untouched native state.
/// Markdown must encode the intended parser tree before one Undo transaction
/// is admitted.
@MainActor enum MacQuoteEditing {
    /// Backspace after preceding text merges just this quoted text block into
    /// that text. Empty quote ancestors disappear; later quote children remain.
    static func mergingAtStart(_ original: NSAttributedString, caret: NSRange, source: String) -> MacListEditing.Outcome {
        guard caret.length == 0, caret.location > 0, caret.location < original.length else { return .notList }
        let raw = original.string as NSString, current = raw.paragraphRange(for: caret)
        let attrs = original.attributes(at: current.location, effectiveRange: nil)
        guard caret.location == current.location, attrs[.macListContext] == nil,
              (MacBlockPrefix(attrs[.macBlock] as? String ?? "")?.depth ?? 0) > 0,
              attrs[.macCode] == nil, attrs[.macTable] == nil, attrs[.macRule] == nil,
              !raw.substring(with: current).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notList }
        var before = current.location, previous: NSRange?
        while before > 0 {
            let row = raw.paragraphRange(for: NSRange(location: before - 1, length: 0))
            let values = original.attributes(at: row.location, effectiveRange: nil)
            before = row.location
            if values[.macCode] != nil || values[.macTable] != nil || values[.macRule] != nil { return .notList }
            if raw.substring(with: row).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               values[.macEmptyParagraph] as? Bool != true,
               MacBlockPrefix(values[.macBlock] as? String ?? "")?.heading != true { continue }
            previous = row; break
        }
        guard let previous else { return .notList }
        let issue = "This quote paragraph could not be merged without changing its blocks. Use Markdown source to edit this boundary."
        // Match native rows to source blocks through exact exported prefixes.
        // This avoids pairing by visible text or repeatedly rendering the note.
        func sourceLine(_ row: NSRange) -> Int? {
            let prefix = MacMarkdown.markdown(original.attributedSubstring(from: NSRange(location: 0, length: row.location)))
            guard Data(source.utf8).starts(with: Data(prefix.utf8)) else { return nil }
            return MacMarkdownLines(prefix).lines.count
        }
        guard let currentLine = sourceLine(current), let previousLine = sourceLine(previous) else { return .refused(issue) }
        let previousAttrs = original.attributes(at: previous.location, effectiveRange: nil)
        let block = previousAttrs[.macBlock] as? String ?? ""
        let context = previousAttrs[.macListContext] as? MacListContext
        let visible = raw.substring(with: previous).dropFirst(MacMarkdown.displayPrefix(block).utf16.count)
        let emptyPrevious = context == nil && visible.replacingOccurrences(of: MacMarkdown.emptyParagraphMarker, with: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let document = Document(parsing: source)
        var currentPath: [Int]?, previousPath: [Int]?, currentNode: (any Markup)?, previousNode: (any Markup)?
        func collect(_ node: any Markup, path: [Int]) {
            if node is Paragraph || node is Heading, let line = node.range?.lowerBound.line {
                if line == currentLine { currentPath = path; currentNode = node }
                // A native item row can contain several logical paragraphs. The
                // quote joins its final paragraph, rather than the item head.
                if line >= previousLine, line < currentLine { previousPath = path; previousNode = node }
            }
            if node is ListItem, node.childCount == 0, let line = node.range?.lowerBound.line, line >= previousLine, line < currentLine { previousPath = path; previousNode = node }
            for (index, child) in node.children.enumerated() { collect(child, path: path + [index]) }
        }
        collect(document, path: [])
        guard let currentPath, let previousPath, currentPath != previousPath,
              let currentNode, let previousNode else { return .refused(issue) }
        var inline: [any Markup] = []
        for child in Array(previousNode.children) + Array(currentNode.children) {
            if let text = child as? Text, let last = inline.last as? Text { inline[inline.count - 1] = Text(last.string + text.string) }
            else { inline.append(child) }
        }
        func changing(_ node: any Markup, path: [Int]) -> (any Markup)? {
            if path == currentPath { return emptyPrevious ? node : nil }
            if path == previousPath {
                if emptyPrevious { return nil }
                if node is ListItem { return node.withUncheckedChildren([Paragraph(inline.compactMap { $0 as? any InlineMarkup })] as [any Markup]) }
                return node.withUncheckedChildren(inline)
            }
            let children = node.children.enumerated().compactMap { changing($0.element, path: path + [$0.offset]) }
            if node is BlockQuote, children.isEmpty, node.childCount > 0 { return nil }
            return node.withUncheckedChildren(children)
        }
        guard let expected = changing(document, path: []) else { return .refused(issue) }
        if emptyPrevious {
            let output = NSMutableAttributedString(attributedString: original)
            output.deleteCharacters(in: NSRange(location: previous.location, length: current.location - previous.location))
            guard Document(parsing: MacMarkdown.markdown(output)).hasSameStructure(as: expected) else { return .refused(issue) }
            var typing = attrs
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macEmptyParagraph, .macLiteral, .attachment, .macImageUnavailable, .macHardBreak, .macListBreak, .macUnterminated] { typing.removeValue(forKey: key) }
            return .changed(.init(text: output, selection: NSRange(location: previous.location, length: 0), typing: typing))
        }
        let body = NSMutableAttributedString(attributedString: MacMarkdown.settingBlock(original.attributedSubstring(from: current), to: block))
        let marker = MacMarkdown.displayPrefix(block).utf16.count
        if marker > 0 { body.deleteCharacters(in: NSRange(location: 0, length: marker)) }
        let full = NSRange(location: 0, length: body.length)
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListContext, .macListGap] { body.removeAttribute(key, range: full) }
        if let context {
            body.addAttributes([.macListContext: context, .macIndependentParagraph: false, .paragraphStyle: context.style], range: full)
        }
        let join = NSMaxRange(previous) - (raw.substring(with: previous).hasSuffix("\n") ? 1 : 0)
        let joined = NSMutableAttributedString(attributedString: original.attributedSubstring(from: NSRange(location: previous.location, length: join - previous.location)))
        joined.append(body)
        let output = NSMutableAttributedString(attributedString: original)
        output.replaceCharacters(in: NSRange(location: previous.location, length: NSMaxRange(current) - previous.location), with: joined)
        // A retained deeper quote starts a new block after the merged text. Keep
        // its separator outside that quote rather than retaining an empty child.
        let boundary = previous.location + joined.length
        if boundary < output.length {
            let text = output.string as NSString
            let next = text.paragraphRange(for: NSRange(location: boundary, length: 0))
            let nextAttrs = output.attributes(at: next.location, effectiveRange: nil)
            let quotes = MacBlockPrefix(block)?.quotes ?? ""
            let depth = MacBlockPrefix(block)?.depth ?? 0
            if (MacBlockPrefix(nextAttrs[.macBlock] as? String ?? "")?.depth ?? 0) > depth {
                if text.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, nextAttrs[.macEmptyParagraph] as? Bool != true {
                    output.replaceCharacters(in: next, with: MacMarkdown.settingBlock(output.attributedSubstring(from: next), to: quotes))
                } else {
                    output.insert(NSAttributedString(string: "\n", attributes: [.macBlock: quotes, .font: MacMarkdown.font(quotes), .paragraphStyle: MacMarkdown.paragraphStyle(quotes), .macLineEnding: attrs[.macLineEnding] ?? "\n"]), at: boundary)
                }
            }
        }
        let value = MacMarkdown.markdown(output)
        guard Document(parsing: value).hasSameStructure(as: expected) else { return .refused(issue) }
        // The registered web key retains the quoted caret's inline format,
        // while its block role comes from the receiving paragraph. Links do
        // not extend across this newly merged boundary.
        var typing = body.attributes(at: 0, effectiveRange: nil)
        typing.removeValue(forKey: .link)
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListGap, .macEmptyParagraph, .macLiteral, .attachment, .macImageUnavailable, .macHardBreak, .macListBreak, .macUnterminated] { typing.removeValue(forKey: key) }
        return .changed(.init(text: output, selection: NSRange(location: join, length: 0), typing: typing))
    }

    static func removingAtStart(_ original: NSAttributedString, caret: NSRange, source: String, root: URL?, path: String, images: [String: NSImage]) -> MacListEditing.Outcome {
        guard caret.length == 0, caret.location < original.length else { return .notList }
        let raw = original.string as NSString, paragraph = raw.paragraphRange(for: caret)
        guard caret.location == paragraph.location,
              !raw.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              original.attribute(.macListContext, at: caret.location, effectiveRange: nil) == nil,
              let prefix = MacBlockPrefix(original.attribute(.macBlock, at: caret.location, effectiveRange: nil) as? String ?? ""), prefix.depth > 0, !prefix.heading else { return .notList }
        let document = Document(parsing: source), lines = MacMarkdownLines(source)
        guard var quote = document.child(at: 0) as? BlockQuote else { return .notList }
        var ancestors: [BlockQuote] = []
        while let nested = quote.child(at: 0) as? BlockQuote { ancestors.append(quote); quote = nested }
        guard let first = quote.child(at: 0) as? Paragraph, let firstLine = first.range?.lowerBound.line,
              let span = quote.range, lines.lines.indices.contains(firstLine - 1), lines.lines.indices.contains(span.lowerBound.line - 1) else { return .notList }
        let startLine = span.lowerBound.line - 1, depth = ancestors.count + 1
        guard caret.location == MacMarkdown.render(lines.fragment(0..<(firstLine - 1))).length else { return .notList }
        let start = MacMarkdown.render(lines.fragment(0..<startLine)).length
        let issue = "This quote could not be removed without changing its blocks. Use Markdown source to edit this boundary."
        guard start <= caret.location, start < original.length else { return .refused(issue) }
        var end = start
        while end < original.length {
            let attrs = original.attributes(at: end, effectiveRange: nil)
            guard (MacBlockPrefix(attrs[.macBlock] as? String ?? "")?.depth ?? 0) >= depth else { break }
            var token: NSRange?
            for key in [NSAttributedString.Key.macCode, .macTable] where attrs[key] != nil {
                var range = NSRange()
                _ = original.attribute(key, at: end, longestEffectiveRange: &range, in: NSRange(location: 0, length: original.length))
                token = range; break
            }
            end = token.map(NSMaxRange) ?? NSMaxRange(raw.paragraphRange(for: NSRange(location: end, length: 0)))
        }
        guard end > caret.location else { return .refused(issue) }
        let nativeRange = NSRange(location: start, length: end - start)
        let previous = original.attributedSubstring(from: nativeRange)
        let oldPart = MacMarkdown.markdown(previous), sourceStart = lines.lines[startLine].offset, sourceRaw = source as NSString
        guard sourceStart + oldPart.utf16.count <= sourceRaw.length,
              Data(sourceRaw.substring(with: NSRange(location: sourceStart, length: oldPart.utf16.count)).utf8) == Data(oldPart.utf8) else { return .refused(issue) }
        let sourceRange = NSRange(location: sourceStart, length: oldPart.utf16.count)
        let partLines = MacMarkdownLines(oldPart)
        let stripped = partLines.lines.map { row -> String in
            guard !row.text.isEmpty || !row.ending.isEmpty else { return "" }
            let outer = MacQuotedCards.strippingPrefix(row.text, depth: depth - 1).prefix
            let body = MacQuotedCards.strippingPrefix(row.text, depth: depth).text
            return (body.isEmpty ? outer.trimmingCharacters(in: .whitespaces) : outer + body) + row.ending
        }.joined()
        var children: [BlockMarkup] = Array(quote.blockChildren)
        for var ancestor in ancestors.reversed() {
            ancestor.replaceChildrenInRange(0..<1, with: children); children = [ancestor]
        }
        var expected = document; expected.replaceChildrenInRange(0..<1, with: children)
        var candidates = [stripped]
        // A quote boundary can separate same-marker lists. Keep their independent
        // starts by changing only the removed wrapper's final list delimiter.
        if let list = Array(quote.children).last, list is OrderedList || list is UnorderedList {
            var rows = MacMarkdownLines(stripped).lines.map { ($0.text, $0.ending) }, changed = false
            for item in list.children {
                guard let line = item.range?.lowerBound.line else { continue }
                let index = line - 1 - startLine
                guard rows.indices.contains(index), let marker = MacBlockPrefix(rows[index].0), marker.list else { continue }
                var value = marker.marker
                let digits = value.prefix(while: { $0.isNumber })
                if !digits.isEmpty {
                    let at = value.index(value.startIndex, offsetBy: digits.count)
                    value.replaceSubrange(at...at, with: value[at] == "." ? ")" : ".")
                } else { value.replaceSubrange(value.startIndex...value.startIndex, with: value.first == "-" ? "*" : "-") }
                rows[index].0 = marker.replacingMarker(value) + String(rows[index].0.dropFirst(marker.source.count)); changed = true
            }
            if changed { candidates.append(rows.map { $0.0 + $0.1 }.joined()) }
        }
        let ending = partLines.ending(at: max(0, partLines.lines.count - 2))
        let outer = MacQuotedCards.strippingPrefix(partLines.lines[0].text, depth: depth - 1).prefix
        if NSMaxRange(sourceRange) < sourceRaw.length {
            candidates += candidates.map { $0 + ($0.hasSuffix("\n") || $0.hasSuffix("\r") ? "" : ending) + outer + ending }
        }
        for part in candidates {
            let value = sourceRaw.replacingCharacters(in: sourceRange, with: part)
            guard Document(parsing: value).hasSameStructure(as: expected) else { continue }
            let replacement = MacMarkdown.render(part, root: root, path: path, images: images)
            let offset = caret.location - start
            guard offset < replacement.length,
                  (replacement.string as NSString).substring(to: offset) == (previous.string as NSString).substring(to: offset) else { continue }
            let output = NSMutableAttributedString(attributedString: original); output.replaceCharacters(in: nativeRange, with: replacement)
            guard Data(MacMarkdown.markdown(output).utf8) == Data(value.utf8) else { continue }
            var typing = replacement.attributes(at: offset, effectiveRange: nil)
            for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macListGap, .macLiteral, .attachment, .macImageUnavailable, .macHardBreak, .macListBreak, .macUnterminated] { typing.removeValue(forKey: key) }
            return .changed(.init(text: output, selection: caret, typing: typing))
        }
        return .refused(issue)
    }
}
