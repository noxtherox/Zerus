import AppKit
import UniformTypeIdentifiers
import Markdown

extension VaultFiles {
    func clipboardFragment(_ markdown: String, notePath: String) throws -> NativeClipboardFragment {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        guard markdown.utf8.count <= NativeClipboardFragment.limit else { throw VaultFailure(message: "Copy a selection smaller than 50 MB.") }
        var portable = markdown, forced = Set<String>()
        let attachments = MarkdownResources.attachmentReferences(in: markdown)
        let ordinary = Set(MarkdownResources.localReferences(in: markdown))
        let all = Set(MarkdownResources.localReferences(in: markdown, includeNoteFiles: true))
        if !attachments.isEmpty || all != ordinary {
            let content = (try? read(notePath)).flatMap { NoteDocument.decodeUTF8($0) } ?? ""
            let note = NoteDocument(path: notePath, content: content, modified: Date())
            let records = NativeFileAttachment.all(in: content)
            var replacements: [String: String] = [:]
            for reference in attachments {
                let id = String(reference.dropFirst("zerus-attachment:".count))
                guard let record = records.first(where: { $0.id == id }) else { throw VaultFailure(message: "A copied attachment needs the original note's file details. Reopen the source note before copying it.") }
                let path = MarkdownResources.encodedPath(record.path, preservingSuffixOf: "")
                replacements[reference] = path; forced.insert(path)
            }
            portable = MarkdownResources.replacing(markdown, references: replacements)
            if let file = note.fileHub, file.kind == .vault, let path = file.path { forced.insert(MarkdownResources.encodedPath(path, preservingSuffixOf: "")) }
        }
        let available = Set(MarkdownResources.localReferences(in: portable, includeNoteFiles: true))
        let references = Set(MarkdownResources.localReferences(in: portable)).union(available.intersection(forced))
        var resources: [NativeClipboardFragment.Resource] = [], size = portable.utf8.count
        for reference in references.sorted() {
            try Task.checkCancellation()
            do {
                let location = try resolveResource(reference, notePath: notePath)
                let bytes = try resourceData(reference, notePath: notePath)
                size += bytes.count
                guard size <= NativeClipboardFragment.limit else { throw VaultFailure(message: "Copy a selection with less than 50 MB of attachments.") }
                let path = String(location.path.dropFirst(root.standardizedFileURL.path.count + 1))
                resources.append(.init(reference: reference, path: path, name: location.lastPathComponent, bytes: bytes))
            } catch let error as VaultFailure where error.message.contains("50 MB") { throw error }
            catch { resources.append(.init(reference: reference, path: nil, name: URL(string: reference)?.lastPathComponent ?? "Attachment", bytes: nil)) }
        }
        let fragment = NativeClipboardFragment(markdown: portable, vault: NativeClipboardFragment.vaultID(root), resources: resources)
        try fragment.validate(); return fragment
    }

    func importClipboard(_ fragment: NativeClipboardFragment) throws -> String {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        try fragment.validate()
        let references = Set(MarkdownResources.localReferences(in: fragment.markdown))
        guard references.isSubset(of: Set(fragment.resources.map(\.reference))) else {
            throw VaultFailure(message: "The copied attachments were not included. Paste into Markdown source to keep the references unchanged.")
        }
        guard fragment.resources.allSatisfy({ $0.bytes != nil }) else {
            throw VaultFailure(message: "An attachment was unavailable when copied. The clipboard still contains the Markdown; paste into source mode to keep those references.")
        }
        var replacements: [String: String] = [:], created: [(String, Data)] = []
        do {
            for resource in fragment.resources {
                try Task.checkCancellation()
                let bytes = resource.bytes!
                let path: String
                if fragment.vault == NativeClipboardFragment.vaultID(root), let existing = resource.path, (existing.hasPrefix("assets/") || existing.hasPrefix(".zerus/attachments/")), (try? read(existing)) == bytes {
                    path = existing
                } else {
                    let name = MacClipboard.importName(resource.name)
                    let opaqueNote = ["md", "markdown"].contains((name as NSString).pathExtension.lowercased())
                    path = (opaqueNote ? ".zerus/attachments/clipboard-" : "assets/") + UUID().uuidString.lowercased() + "-" + name
                    try write(path, data: bytes, expected: nil); created.append((path, bytes))
                }
                replacements[resource.reference] = MarkdownResources.encodedPath(path, preservingSuffixOf: resource.reference)
            }
            let markdown = MarkdownResources.replacing(fragment.markdown, references: replacements)
            try Task.checkCancellation()
            return markdown
        } catch {
            for (path, bytes) in created { try? removeClipboardAsset(path, expected: bytes) }
            throw error
        }
    }

    private func removeClipboardAsset(_ path: String, expected: Data) throws {
        let location = try url(for: path)
        var coordinationError: NSError?, failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: location, options: .forDeleting, error: &coordinationError) { url in
            do {
                guard try Data(contentsOf: url) == expected else { return }
                try FileManager.default.removeItem(at: url)
            } catch { failure = error }
        }
        if let failure { throw failure }; if let coordinationError { throw coordinationError }
    }
}

@MainActor enum MacClipboard {
    nonisolated static func importName(_ original: String) -> String {
        let clean = original.replacingOccurrences(of: #"[/\\:\x00-\x1F]"#, with: "-", options: .regularExpression)
        let ext = (clean as NSString).pathExtension
        let stem = (clean as NSString).deletingPathExtension.replacingOccurrences(of: #"(?i)^(?:[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}-)+"#, with: "", options: .regularExpression)
        func bounded(_ text: String, bytes: Int) -> String {
            var result = ""
            for character in text { let next = result + String(character); guard next.decomposedStringWithCanonicalMapping.utf8.count <= bytes else { break }; result = next }
            return result
        }
        let base = bounded(stem, bytes: 160).trimmingCharacters(in: CharacterSet(charactersIn: " .")), suffix = bounded(ext, bytes: 24)
        return (base.isEmpty ? "Attachment" : base) + (suffix.isEmpty ? "" : "." + suffix)
    }
    /// Keep formatted code paste as literal prose while creation is disabled.
    /// Only the pasted fragment is transformed; existing note blocks are untouched.
    static func withoutCodeBlocks(_ markdown: String) -> String {
        let result = NSMutableString(string: markdown)
        let supported = MacCodeBlock.blocks(in: markdown)
        let legacy = FencedCode.blocks(in: markdown).filter { block in !supported.contains { NSIntersectionRange($0.range, block.range).length > 0 } }
        let blocks = supported + legacy.map { MacCodeBlock(range: $0.range, code: $0.code, indented: nil) }
        for located in blocks.sorted(by: { $0.range.location > $1.range.location }) {
            let lines = MacMarkdownLines(located.code.body).contents.map { line in
                let indentation = line.prefix { $0 == " " || $0 == "\t" }
                let prefix = indentation.map { $0 == "\t" ? "&#9;" : "&#32;" }.joined()
                let text = String(line.dropFirst(indentation.count)).replacingOccurrences(of: #"([\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E])"#, with: #"\\$1"#, options: .regularExpression)
                return prefix + text
            }
            let prose = lines.joined(separator: "  " + located.code.newline)
            let value = prose.isEmpty && located.container.map({ $0.firstPrefix != $0.continuationPrefix }) == true ? MacMarkdown.emptyParagraphMarker : prose
            result.replaceCharacters(in: located.range, with: located.container?.spelling(value) ?? located.quote?.spelling(value) ?? value)
        }
        return result as String
    }
    private static var latestCopy = UUID()
    static func beginCopy() -> UUID { latestCopy = UUID(); return latestCopy }
    static func currentCopy(_ id: UUID) -> Bool { latestCopy == id }
    static func selection(_ text: NSAttributedString, range: NSRange) -> NSAttributedString {
        let selected = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
        var endsWithinBody = false
        if range.length > 0 {
            let source = text.string as NSString
            let last = source.paragraphRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0))
            let bodyEnd = NSMaxRange(last) - (source.substring(with: last).hasSuffix("\n") ? 1 : 0)
            endsWithinBody = NSMaxRange(range) < bodyEnd
            if NSMaxRange(range) < NSMaxRange(last) {
                // The selected body excludes its original terminator. Saved
                // CRLF spelling can carry the CR on the body token. Keep inline
                // image/link spelling while omitting that unselected terminator.
                let local = (selected.string as NSString).paragraphRange(for: NSRange(location: selected.length - 1, length: 0))
                selected.enumerateAttribute(.macOriginal, in: local) { value, part, _ in
                    if let original = value as? String {
                        var source = original.hasSuffix("\r") ? String(original.dropLast()) : original
                        if selected.attribute(.macIndependentParagraph, at: part.location, effectiveRange: nil) as? Bool == true { source = MacMarkdown.withoutStructuralIndentation(source) }
                        if source != original { selected.addAttribute(.macOriginal, value: source, range: part) }
                    }
                }
                for key in [NSAttributedString.Key.macParagraphID, .macParagraphSource, .macParagraphSignature] { selected.removeAttribute(key, range: local) }
            }
        }
        let partialFirst = range.length > 0 && (text.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 0)).location != range.location
        if partialFirst {
            let first = (selected.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            let source = text.string as NSString
            let row = source.paragraphRange(for: NSRange(location: range.location, length: 0))
            let context = text.attribute(.macListContext, at: row.location, effectiveRange: nil) as? MacListContext
            let role = context.flatMap { MacBlockPrefix($0.suffix) }
            let bodyEnd = NSMaxRange(row) - (source.substring(with: row).hasSuffix("\n") ? 1 : 0)
            let completeHeading = role?.heading == true && context.map { range.location == row.location + MacMarkdown.displayPrefix($0.block).utf16.count } == true && NSMaxRange(range) >= bodyEnd
            let block = completeHeading ? role!.marker : ""
            selected.addAttribute(.macBlock, value: block, range: first)
            if completeHeading { selected.addAttribute(.paragraphStyle, value: MacMarkdown.paragraphStyle(block), range: first) }
            selected.removeAttribute(.macListContext, range: first)
        }
        text.enumerateAttribute(.macTable, in: NSRange(location: 0, length: text.length)) { table, full, _ in
            let overlap = NSIntersectionRange(range, full)
            guard table != nil, overlap.length > 0, overlap != full else { return }
            let local = NSRange(location: overlap.location - range.location, length: overlap.length)
            for key in [NSAttributedString.Key.macTable, .macCell, .macCellEnd, .macCellPlaceholder, .macListCard] { selected.removeAttribute(key, range: local) }
            selected.enumerateAttribute(.paragraphStyle, in: local) { value, range, _ in
                if let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle { style.textBlocks = []; selected.addAttribute(.paragraphStyle, value: style, range: range) }
            }
        }
        // The clipboard is a standalone document. A retained child whose
        // ancestors were not selected starts at the root, rather than becoming
        // four-column code or attaching to the selected prose above it.
        var touchesList = false
        selected.enumerateAttribute(.macBlock, in: NSRange(location: 0, length: selected.length)) { value, _, stop in
            if MacBlockPrefix(value as? String ?? "")?.list == true { touchesList = true; stop.pointee = true }
        }
        var detachedStarts = Set<Int>(), promotedStarts = Set<Int>()
        var omittedQuoteOwners: [UUID: [MacListContext]] = [:]
        func removingInheritedWidth(_ source: String, owners: [MacListContext]) -> String {
            owners.reduce(source) { value, owner in
                guard let prefix = MacBlockPrefix(owner.source), let current = MacBlockPrefix(value) else { return value }
                return current.shiftingIndentation(by: -(prefix.indent + prefix.listPadding), atQuoteDepth: prefix.depth)
            }
        }
        if touchesList, let items = MacMarkdown.nativeListItems(in: text, allowEmptyItemBoundaries: true) {
            let retained = Set(items.indices.filter { index in
                let row = items[index]
                return row.range.location >= range.location && row.range.location < NSMaxRange(range) && row.range.location + row.block.display.utf16.count <= NSMaxRange(range)
            })
            for index in items.indices where !retained.contains(index) {
                let overlap = NSIntersectionRange(items[index].range, range)
                guard overlap.length > 0 else { continue }
                let local = NSRange(location: overlap.location - range.location, length: overlap.length)
                detachedStarts.insert((selected.string as NSString).paragraphRange(for: NSRange(location: local.location, length: 0)).location)
                let current = selected.attribute(.macBlock, at: local.location, effectiveRange: nil) as? String ?? ""
                // The first selection pass already established whether this
                // unselected head contributes a complete standalone heading.
                let block = partialFirst && local.location == 0 && MacBlockPrefix(current)?.heading == true ? current : ""
                selected.removeAttribute(.macListContext, range: local)
                selected.addAttributes([.macBlock: block, .paragraphStyle: MacMarkdown.paragraphStyle(block)], range: local)
            }
            let retainedIDs = Set(retained.compactMap { index in
                (text.attribute(.macListContext, at: items[index].range.location, effectiveRange: nil) as? MacListContext)?.id
            })
            for index in retained.sorted().reversed() {
                let item = items[index]
                var root = index
                while let parent = items[root].parent, retained.contains(parent) { root = parent }
                let shift = items[root].parent == nil ? 0 : items[root].block.indent
                if shift > 0, root == index { promotedStarts.insert(item.range.location - range.location) }
                var next = item.block.indented(max(0, item.block.indent - shift))
                // An item's outer list can sit before a quote marker. That
                // inherited width lives in `quotes`, not the final indent.
                // Remove only unselected owners, at each owner's quote depth.
                if let context = text.attribute(.macListContext, at: item.range.location, effectiveRange: nil) as? MacListContext {
                    let omitted = context.quoteParents.filter { !retainedIDs.contains($0.id) }
                    if !omitted.isEmpty { omittedQuoteOwners[context.id] = omitted }
                    next = removingInheritedWidth(next, owners: omitted)
                }
                let local = NSRange(location: item.range.location - range.location, length: min(NSMaxRange(item.range), NSMaxRange(range)) - item.range.location)
                if next != item.block.source { selected.replaceCharacters(in: local, with: MacMarkdown.settingBlock(selected.attributedSubstring(from: local), to: next)) }
            }
        }
        var heads = Set<UUID>()
        selected.enumerateAttribute(.macListContext, in: NSRange(location: 0, length: selected.length)) { value, _, _ in
            if let context = value as? MacListContext, !context.continuation { heads.insert(context.id) }
        }
        // Continuation gaps are source fragments too. A quote-only separator
        // must lose the same omitted list widths as its retained head.
        if !omittedQuoteOwners.isEmpty { selected.enumerateAttribute(.macListContext, in: NSRange(location: 0, length: selected.length)) { value, range, _ in
            guard let context = value as? MacListContext, let omitted = omittedQuoteOwners[context.id] else { return }
            let gap = MacMarkdownLines(context.gap).lines.map { removingInheritedWidth($0.text, owners: omitted) + $0.ending }.joined()
            let parents = context.quoteParents.filter { heads.contains($0.id) }
            let updated = MacListContext(id: context.id, source: context.source, continuation: context.continuation, gap: gap, originatedAfterChildren: context.originatedAfterChildren, suffix: context.suffix, blockParagraph: context.blockParagraph, quoteLeaf: context.quoteLeaf, quoteParents: parents)
            selected.addAttribute(.macListContext, value: updated, range: range)
        } }
        var originalPlacements: [ObjectIdentifier: [NSAttributedString.Key: Any]] = [:]
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, _, _ in
            if let placement = attrs[.macListCard] as? MacListCardPlacement { originalPlacements[ObjectIdentifier(placement)] = attrs }
        }
        selected.enumerateAttribute(.macListCard, in: NSRange(location: 0, length: selected.length)) { value, local, _ in
            guard let placement = value as? MacListCardPlacement,
                  let attrs = originalPlacements[ObjectIdentifier(placement)],
                  let context = attrs[.macListContext] as? MacListContext,
                  !heads.contains(context.id) else { return }
            selected.replaceCharacters(in: local, with: MacListCardPlacement.detached(selected.attributedSubstring(from: local), from: attrs))
        }
        var orphanStarts = Set<Int>()
        let singleParagraph = selected.length == 0 || (selected.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0)).length == selected.length
        selected.enumerateAttribute(.macListContext, in: NSRange(location: 0, length: selected.length)) { value, local, _ in
            if let context = value as? MacListContext, context.continuation, !heads.contains(context.id) {
                orphanStarts.insert((selected.string as NSString).paragraphRange(for: NSRange(location: local.location, length: 0)).location)
                selected.removeAttribute(.macListContext, range: local)
                let quotes = singleParagraph ? "" : MacBlockPrefix(context.source)?.quotes ?? ""
                // The copied heading is a standalone block even though its
                // unselected item/quote ancestors are no longer present.
                let role = MacBlockPrefix(context.suffix)
                let completeHeading = role?.heading == true && !(endsWithinBody && NSMaxRange(local) == selected.length)
                let block = quotes + (completeHeading ? role!.marker : "")
                selected.addAttributes([.macBlock: block, .paragraphStyle: MacMarkdown.paragraphStyle(block)], range: local)
            }
        }
        selected.setAttributedString(MacMarkdown.refreshingListContexts(selected))
        let raw = selected.string as NSString
        var offset = 0, previousPlain = false, previousBlank = true, previousDetached = false, previousQuotes = ""
        var boundaries: [(Int, String)] = []
        while offset < raw.length {
            let row = raw.paragraphRange(for: NSRange(location: offset, length: 0))
            let blank = raw.substring(with: row).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let block = selected.attribute(.macBlock, at: offset, effectiveRange: nil) as? String ?? ""
            let prefix = MacBlockPrefix(block), list = prefix?.list == true, quotes = prefix?.quotes ?? ""
            let detached = orphanStarts.contains(offset) || detachedStarts.contains(offset)
            if offset > 0, !blank, !previousBlank, orphanStarts.contains(offset) || detachedStarts.contains(offset) && !previousPlain || list && previousPlain && (partialFirst || promotedStarts.contains(offset) || previousDetached) {
                let depth = min(previousQuotes.filter { $0 == ">" }.count, quotes.filter { $0 == ">" }.count)
                let shared = depth == (prefix?.depth ?? 0) ? quotes : String(repeating: "> ", count: depth)
                boundaries.append((offset, shared))
            }
            previousPlain = !list && selected.attribute(.macListContext, at: offset, effectiveRange: nil) == nil
            previousBlank = blank; previousDetached = detached; previousQuotes = quotes; offset = NSMaxRange(row)
        }
        for (offset, quotes) in boundaries.reversed() {
            let ending = selected.attribute(.macLineEnding, at: offset - 1, effectiveRange: nil) as? String ?? "\n"
            selected.insert(NSAttributedString(string: "\n", attributes: [.macBlock: quotes, .font: MacMarkdown.font(quotes), .paragraphStyle: MacMarkdown.paragraphStyle(quotes), .macLineEnding: ending]), at: offset)
        }
        return selected
    }


    static func insertion(_ value: NSAttributedString, into original: NSAttributedString, range: NSRange) -> NSAttributedString {
        let text = value.string as NSString
        guard text.length > 0 else { return value }
        if value.string.trimmingCharacters(in: .newlines).isEmpty,
           MacRichTable.at(original, range.location) == nil, MacRichCode.at(original, range.location) == nil {
            var marker = false
            value.enumerateAttribute(.macEmptyParagraph, in: NSRange(location: 0, length: value.length)) { raw, _, _ in
                if raw as? Bool == true { marker = true }
            }
            if marker {
                let full = original.string as NSString
                let before = full.substring(to: range.location), after = full.substring(from: NSMaxRange(range))
                let leading = before.isEmpty ? 0 : max(0, 2 - before.reversed().prefix(while: { $0 == "\n" }).count)
                let trailing = after.isEmpty ? 0 : max(0, 1 - after.prefix(while: { $0 == "\n" }).count)
                var ending = "\n"
                if original.length > 0 {
                    let row = full.paragraphRange(for: NSRange(location: min(range.location, original.length - 1), length: 0))
                    ending = original.attribute(.macLineEnding, at: NSMaxRange(row) - 1, effectiveRange: nil) as? String ?? "\n"
                }
                let attrs: [NSAttributedString.Key: Any] = [.font: MacMarkdown.font(""), .foregroundColor: NSColor.labelColor, .macBlock: "", .macIndependentParagraph: true, .paragraphStyle: MacMarkdown.paragraphStyle(""), .macLineEnding: ending]
                let result = NSMutableAttributedString(string: String(repeating: "\n", count: leading), attributes: attrs)
                let blank = NSMutableAttributedString(attributedString: value)
                blank.addAttribute(.macLineEnding, value: ending, range: NSRange(location: 0, length: blank.length))
                result.append(blank)
                result.append(NSAttributedString(string: String(repeating: "\n", count: trailing), attributes: attrs))
                return result
            }
        }
        var first = 0, last = text.length - 1
        while first < text.length && [10, 13].contains(text.character(at: first)) { first += 1 }
        while last >= 0 && [10, 13].contains(text.character(at: last)) { last -= 1 }
        guard first < text.length, last >= 0 else { return value }
        func block(_ index: Int) -> Bool {
            if MacRichCode.at(value, index) != nil || MacRichTable.at(value, index) != nil { return true }
            return !(value.attribute(.macBlock, at: index, effectiveRange: nil) as? String ?? "").isEmpty
        }
        let full = original.string as NSString
        let before = full.substring(to: range.location), after = full.substring(from: NSMaxRange(range))
        func normalized(_ string: String) -> String { string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
        let beforeLines = normalized(before).reversed().prefix(while: { $0 == "\n" }).count
        let afterLines = normalized(after).prefix(while: { $0 == "\n" }).count
        let firstLines = normalized(text.substring(to: first)).count
        let lastLines = normalized(text.substring(from: last + 1)).count
        let leading = block(first) && !before.isEmpty ? max(0, 2 - firstLines - beforeLines) : 0
        let trailing = block(last) ? max(0, 2 - lastLines - afterLines) : 0
        let attributes: [NSAttributedString.Key: Any] = [.font: MacMarkdown.font(""), .foregroundColor: NSColor.labelColor, .macBlock: "", .macLineEnding: MacMarkdown.lineEnding(in: original, at: range.location)]
        let result = NSMutableAttributedString(string: String(repeating: "\n", count: leading), attributes: attributes)
        result.append(value)
        result.append(NSAttributedString(string: String(repeating: "\n", count: trailing), attributes: attributes))
        return result
    }


    static func rich(_ value: NSAttributedString) throws -> NativeClipboardFragment {
        let rich = NSMutableAttributedString(attributedString: value), all = NSRange(location: 0, length: value.length)
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macLiteral, .macStrong] { rich.removeAttribute(key, range: all) }
        rich.addAttribute(.macBlock, value: "", range: all)
        var resources: [NativeClipboardFragment.Resource] = [], failure: Error?
        value.enumerateAttribute(.attachment, in: all) { item, range, _ in
            guard let attachment = item as? NSTextAttachment else { return }
            let imageData = attachment.image?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
            guard let bytes = attachment.fileWrapper?.regularFileContents ?? attachment.contents ?? imageData else { failure = VaultFailure(message: "A copied attachment could not be read. Your writing is unchanged. Use Paste and Match Style for text only."); return }
            let image = NSImage(data: bytes) != nil
            let name = attachment.fileWrapper?.preferredFilename ?? (image ? "Image.png" : "Attachment")
            let reference = "assets/clipboard-" + UUID().uuidString.lowercased()
            let label = name.replacingOccurrences(of: #"([\\\[\]])"#, with: #"\\$1"#, options: .regularExpression)
            rich.addAttribute(.macLiteral, value: (image ? "!" : "") + "[" + label + "](" + reference + ")", range: range)
            resources.append(.init(reference: reference, path: nil, name: name, bytes: bytes))
        }
        if let failure { throw failure }
        // Cocoa paragraph terminators are block boundaries. A single Markdown
        // newline would fold them into one paragraph after saving/reopening.
        // U+2028 is an inline line break and stays inside its paragraph.
        let raw = rich.string as NSString, terminators = CharacterSet(charactersIn: "\r\n\u{2029}")
        let paragraphs = NSMutableAttributedString()
        var cursor = 0
        while cursor < raw.length {
            let separator = raw.rangeOfCharacter(from: terminators, range: NSRange(location: cursor, length: raw.length - cursor))
            guard separator.location != NSNotFound else {
                paragraphs.append(rich.attributedSubstring(from: NSRange(location: cursor, length: raw.length - cursor))); break
            }
            if separator.location > cursor {
                paragraphs.append(rich.attributedSubstring(from: NSRange(location: cursor, length: separator.location - cursor)))
            }
            var end = NSMaxRange(separator)
            if raw.character(at: separator.location) == 13, end < raw.length, raw.character(at: end) == 10 { end += 1 }
            let attributes = rich.attributes(at: separator.location, effectiveRange: nil)
            paragraphs.append(NSAttributedString(string: end == raw.length ? "\n" : "\n\n", attributes: attributes))
            cursor = end
        }
        let markdown = MacMarkdown.markdown(paragraphs)
        guard !markdown.contains("\u{fffc}") else { throw VaultFailure(message: "An unsupported attachment could not be converted. Your writing is unchanged.") }
        let fragment = NativeClipboardFragment(markdown: markdown, resources: resources)
        try fragment.validate(); return fragment
    }
    static func image(_ bytes: Data, name: String) throws -> NativeClipboardFragment {
        guard NSImage(data: bytes) != nil else { throw VaultFailure(message: "The clipboard image could not be read.") }
        let reference = "assets/clipboard-" + UUID().uuidString.lowercased()
        let fragment = NativeClipboardFragment(markdown: "![Image](" + reference + ")", resources: [.init(reference: reference, path: nil, name: name, bytes: bytes)])
        try fragment.validate(); return fragment
    }
    static func item(_ fragment: NativeClipboardFragment, rich: NSAttributedString?) throws -> NSPasteboardItem {
        try fragment.validate()
        let encoded = try JSONEncoder().encode(fragment)
        guard encoded.count <= NativeClipboardFragment.limit * 3 / 2 else { throw VaultFailure(message: "Copy a smaller selection; its attachments are too large.") }
        let item = NSPasteboardItem()
        item.setData(encoded, forType: .init(NativeClipboardFragment.type))
        item.setString(fragment.markdown, forType: .string)
        item.setData(Data(fragment.markdown.utf8), forType: .init("net.daringfireball.markdown"))
        if let rich {
            var hasRule = false, hasSemanticCard = false, hasHeading = false
            rich.enumerateAttributes(in: NSRange(location: 0, length: rich.length)) { attrs, _, _ in
                let block = (attrs[.macListContext] as? MacListContext)?.textBlock ?? attrs[.macBlock] as? String ?? ""
                if MacBlockPrefix(block)?.heading == true { hasHeading = true }
                if (attrs[.macCode] as? MacRichCode)?.quote != nil || (attrs[.macTable] as? MacRichTable)?.quote != nil || attrs[.macListCard] != nil && (attrs[.macCode] != nil || attrs[.macTable] != nil) { hasSemanticCard = true }
            }
            rich.enumerateAttribute(.macRule, in: NSRange(location: 0, length: rich.length)) { value, _, stop in
                if value != nil { hasRule = true; stop.pointee = true }
            }
            if hasRule || hasSemanticCard || hasHeading, fragment.resources.isEmpty {
                var parser = NativeExportParser()
                let blocks = parser.blocks(Document(parsing: NoteReference.inlineMarkdown(fragment.markdown)))
                if parser.imageReferences.isEmpty, parser.warnings.isEmpty {
                    let document = NativeExportDocument(title: "", blocks: blocks, properties: [])
                    let html = Data(NativeHTMLExport.render(document).utf8)
                    if html.count <= NativeClipboardFragment.limit { item.setData(html, forType: .html) }
                }
            }
            let portable = NSMutableAttributedString(attributedString: rich), all = NSRange(location: 0, length: rich.length)
            var complete = true, size = rich.string.utf8.count
            rich.enumerateAttributes(in: all) { attrs, range, _ in
                if let attachment = attrs[.attachment] as? NSTextAttachment {
                    let reference = (attrs[.macLiteral] as? String).flatMap { MarkdownResources.localReferences(in: $0).first }
                    let resource = fragment.resources.first { $0.reference == reference }
                    let imageBytes = attachment.image?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
                    guard let bytes = resource?.bytes ?? imageBytes else { complete = false; return }
                    size += bytes.count
                    guard size <= NativeClipboardFragment.limit else { complete = false; return }
                    let wrapper = FileWrapper(regularFileWithContents: bytes); wrapper.preferredFilename = resource?.name ?? "Image.png"
                    let replacement = NSTextAttachment(fileWrapper: wrapper); replacement.image = NSImage(data: bytes); replacement.bounds = attachment.bounds
                    portable.addAttribute(.attachment, value: replacement, range: range)
                }
                for key in attrs.keys where key.rawValue.hasPrefix("Zerus") { portable.removeAttribute(key, range: range) }
            }
            if complete {
                for (type, format) in [(NSPasteboard.PasteboardType.rtfd, NSAttributedString.DocumentType.rtfd), (.rtf, .rtf)] {
                    if let data = try? portable.data(from: all, documentAttributes: [.documentType: format]), data.count <= NativeClipboardFragment.limit { item.setData(data, forType: type) }
                }
            }
        }
        return item
    }
    enum Payload {
        case fragment(NativeClipboardFragment), html(Data, attachments: [NativeHTMLClipboard.Attachment] = []), plain(String)
    }
    static func payload(_ board: NSPasteboard, plain: Bool) throws -> Payload? {
        if !plain {
            if let data = board.data(forType: .init(NativeClipboardFragment.type)) { return .fragment(try NativeClipboardFragment.decode(data)) }
            if let text = board.string(forType: .tabularText) ?? board.string(forType: .string), let grid = try MacTableClipboard.spreadsheet(text, explicit: board.data(forType: .tabularText) != nil) { return .fragment(.init(markdown: grid.markdown)) }
            if let data = board.data(forType: .html) {
                var attachments: [NativeHTMLClipboard.Attachment] = []
                if let rtfd = board.data(forType: .rtfd), rtfd.count <= NativeClipboardFragment.limit,
                   let attributed = try? NSAttributedString(data: rtfd, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil),
                   let fragment = try? rich(attributed) {
                    attachments = fragment.resources.compactMap { resource in resource.bytes.map { .init(name: resource.name, bytes: $0) } }
                }
                return .html(data, attachments: attachments)
            }
            for (type, document) in [(NSPasteboard.PasteboardType.rtfd, NSAttributedString.DocumentType.rtfd), (.rtf, .rtf)] {
                if let data = board.data(forType: type) {
                    guard data.count <= NativeClipboardFragment.limit else { throw VaultFailure(message: "Copy a smaller passage; this rich selection exceeds 50 MB.") }
                    return .fragment(try rich(NSAttributedString(data: data, options: [.documentType: document], documentAttributes: nil)))
                }
            }
            if let data = board.data(forType: .png) { return .fragment(try image(data, name: "Image.png")) }
            if let data = board.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) { return .fragment(try image(png, name: "Image.png")) }
        }
        return board.string(forType: .string).map(Payload.plain)
    }
}
