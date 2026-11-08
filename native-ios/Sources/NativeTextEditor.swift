import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Markdown

extension NSAttributedString.Key {
    static let zerusBlock = NSAttributedString.Key("ZerusBlockPrefix")
    static let zerusImageMarkdown = NSAttributedString.Key("ZerusImageMarkdown")
    static let zerusDecoration = NSAttributedString.Key("ZerusDecoration")
    static let zerusRichBlockMarkdown = NSAttributedString.Key("ZerusRichBlockMarkdown")
    static let zerusInlineCode = NSAttributedString.Key("ZerusInlineCode")
}

/// Unsupported structures stay in source mode until their native editor can
/// preserve them. Fenced code is an intact token with its own native editor.
enum MarkdownText {
    /// A screen can ask for the same analysis from several view branches and
    /// callbacks. Keep only its current body; editing invalidates both results.
    @MainActor
    final class Analysis {
        private var body: String?
        private var source: Bool?
        private var references: [String]?

        private func prepare(_ text: String) {
            // Literal comparison keeps canonically equivalent paths distinct.
            if let body, (body as NSString).compare(text, options: .literal) == .orderedSame { return }
            body = text; source = nil; references = nil
        }

        func requiresSource(_ text: String) -> Bool {
            prepare(text)
            if let source { return source }
            let result = MarkdownText.requiresSource(text)
            source = result; return result
        }

        func imageReferences(_ text: String) -> [String] {
            prepare(text)
            if let references { return references }
            let result = MarkdownText.imageReferences(text)
            references = result; return result
        }
    }

    static func withoutCode(_ text: String) -> String {
        let masked = NSMutableString(string: text)
        for block in FencedCode.blocks(in: text).reversed() { masked.replaceCharacters(in: block.range, with: "") }
        return masked as String
    }
    static func withoutRichBlocks(_ text: String) -> String {
        let codeRanges = FencedCode.blocks(in: text).map(\.range)
        let ranges = codeRanges + MarkdownTable.blocks(in: text, excluding: codeRanges).map(\.range)
        let masked = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) { masked.replaceCharacters(in: range, with: "") }
        return masked as String
    }
    static func requiresSource(_ text: String) -> Bool {
        let text = withoutRichBlocks(text)
        func hasHTML(_ node: any Markup) -> Bool {
            node is HTMLBlock || node is InlineHTML || node.children.contains(where: hasHTML)
        }
        if text.contains("<"), hasHTML(Document(parsing: text)) { return true }
        let literal = text as NSString
        func contains(_ marker: String) -> Bool { literal.range(of: marker, options: .literal).location != NSNotFound }
        if (contains("```") || contains("~~~")), text.range(of: #"(?m)^ {0,3}(?:>[ \t]*|[-*+] |\d+[.)] )+[ \t]*(?:`{3,}|~{3,})"#, options: .regularExpression) != nil { return true }
        // This Cocoa precheck can find extra candidates; the original full
        // expression below still decides whether source editing is required.
        if literal.range(of: #"(?m)^[ \t]*(?:```|~~~|\||\[|[-*_]{3})|\n[=-]{3}|\$\$|  \r?\n"#, options: .regularExpression).location != NSNotFound {
            if text.range(of: #"(?m)(^[ \t]*```|^[ \t]*~~~|^[ \t]*\||^[ \t]*\[.+\]:|^[ \t]*[-*_]{3,}\s*$|^.+\n[=-]{3,}\s*$|\$\$|  \r?\n)"#, options: .regularExpression) != nil { return true }
        }
        if contains("\\"), text.range(of: #"(?m)(?<!\\)(?:\\\\)*\\\r?\n"#, options: .regularExpression) != nil { return true }
        if contains("|"), text.range(of: #"(?m)^[ \t]*\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*$"#, options: .regularExpression) != nil { return true }
        guard contains("\t") || contains("    ") else { return false }
        return text.components(separatedBy: "\n").contains { line in
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            return indent >= 4 && !trimmed.isEmpty && trimmed.range(of: #"^(?:[-*+] |\d+[.)] )"#, options: .regularExpression) == nil
        }
    }

    static func font(prefix: String = "", traits: UIFontDescriptor.SymbolicTraits = []) -> UIFont {
        let style: UIFont.TextStyle = prefix.hasPrefix("###") ? .title3 : prefix.hasPrefix("##") ? .title2 : prefix.hasPrefix("#") ? .largeTitle : .body
        let base = UIFont.preferredFont(forTextStyle: style)
        let combined = prefix.hasPrefix("#") ? traits.union(.traitBold) : traits
        return base.fontDescriptor.withSymbolicTraits(combined).map { UIFont(descriptor: $0, size: 0) } ?? base
    }

    static func adaptingFonts(_ value: NSAttributedString, to traits: UITraitCollection) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
            guard let font = attributes[.font] as? UIFont else { return }
            let prefix = attributes[.zerusBlock] as? String ?? ""
            let fallback: UIFont.TextStyle = prefix.hasPrefix("###") ? .title3 : prefix.hasPrefix("##") ? .title2 : prefix.hasPrefix("#") ? .largeTitle : .body
            let style = (font.fontDescriptor.object(forKey: .textStyle) as? String).map { UIFont.TextStyle(rawValue: $0) } ?? fallback
            let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
            let symbolic = font.fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic, .traitMonoSpace])
            let descriptor = symbolic.contains(.traitMonoSpace) ? UIFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular).fontDescriptor : base.fontDescriptor
            result.addAttribute(.font, value: UIFont(descriptor: descriptor.withSymbolicTraits(symbolic) ?? descriptor, size: 0), range: range)
        }
        return result
    }

    static func paragraphStyle(prefix: String) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = prefix.hasPrefix("#") ? 14 : 7
        let marker = prefix.trimmingCharacters(in: .whitespaces)
        let indent = CGFloat(prefix.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }) * 7
        if ["-", "*", "+"].contains(String(marker.prefix(1))) || marker.first?.isNumber == true {
            paragraph.headIndent = indent + 24
            paragraph.firstLineHeadIndent = indent
            if !isChecklist(prefix) {
                let list = NSTextList(markerFormat: marker.first?.isNumber == true ? .decimal : .disc, options: 0)
                list.startingItemNumber = Int(marker.prefix(while: \.isNumber)) ?? 1
                paragraph.textLists = [list]
            }
        }
        if prefix == "> " { paragraph.headIndent = 18; paragraph.firstLineHeadIndent = 18 }
        return paragraph
    }

    static func isChecklist(_ prefix: String) -> Bool {
        prefix.range(of: #"[-*+] \[[ xX]\] $"#, options: .regularExpression) != nil
    }

    static func checkbox(prefix: String, label: String = "Checklist item") -> NSAttributedString {
        let checked = prefix.lowercased().contains("[x]")
        let attachment = ChecklistAttachment(checked: checked, label: label)
        let value = NSMutableAttributedString(attachment: attachment)
        value.append(NSAttributedString(string: " "))
        value.addAttributes([.zerusDecoration: true, .zerusBlock: prefix, .font: font(), .paragraphStyle: paragraphStyle(prefix: prefix)], range: NSRange(location: 0, length: value.length))
        return value
    }

    static func imageReferences(_ markdown: String) -> [String] {
        // Markdown image syntax needs an exclamation mark. Ordinary typing
        // without one does not need a full Markdown parse on every edit.
        guard (markdown as NSString).range(of: "!", options: .literal).location != NSNotFound else { return [] }
        guard let parsed = try? AttributedString(markdown: withoutCode(markdown), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return [] }
        return Array(Set(parsed.runs.compactMap { $0.imageURL?.relativeString })).sorted()
    }
    static func render(_ markdown: String, images: [String: UIImage] = [:], width: CGFloat = 320, codeBlocks: Bool = true) -> NSAttributedString {
        let text = markdown as NSString
        let result = NSMutableAttributedString(string: "")
        var cursor = 0
        let codes = FencedCode.blocks(in: markdown)
        let tables = MarkdownTable.blocks(in: markdown, excluding: codes.map(\.range))
        let blocks = codes.map { block in
            (block.range, codeBlocks ? codeToken(block.code, width: width) : NSAttributedString(string: block.code.markdown, attributes: [.font: font(), .foregroundColor: NativeThemeUIKit.text, .zerusBlock: "", .paragraphStyle: paragraphStyle(prefix: "")]))
        } + tables.map { ($0.range, tableToken($0.table, width: width, images: images)) }
        for (range, token) in blocks.sorted(by: { $0.0.location < $1.0.location }) {
            result.append(renderProse(text.substring(with: NSRange(location: cursor, length: range.location - cursor)), images: images, width: width))
            result.append(token)
            cursor = NSMaxRange(range)
        }
        result.append(renderProse(text.substring(from: cursor), images: images, width: width))
        return result
    }

    static func codeToken(_ code: FencedCode, width: CGFloat) -> NSAttributedString {
        let token = NSMutableAttributedString(attachment: CodeAttachment(code: code, width: width))
        token.addAttributes([.zerusRichBlockMarkdown: code.markdown, .zerusBlock: "", .font: font(), .paragraphStyle: paragraphStyle(prefix: "")], range: NSRange(location: 0, length: token.length))
        return token
    }
    static func tableToken(_ table: MarkdownTable, width: CGFloat, images: [String: UIImage] = [:]) -> NSAttributedString {
        let token = NSMutableAttributedString(attachment: TableAttachment(table: table, width: width, images: images))
        token.addAttributes([.zerusRichBlockMarkdown: table.markdown, .zerusBlock: "", .font: font(), .paragraphStyle: paragraphStyle(prefix: "")], range: NSRange(location: 0, length: token.length))
        return token
    }

    private static func renderProse(_ markdown: String, images: [String: UIImage], width: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let lines = markdown.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let carriageReturn = line.hasSuffix("\r")
            let content = carriageReturn ? String(line.dropLast()) : line
            var prefix = "", text = content
            if let match = content.range(of: #"^(#{1,6} |[ \t]*[-*+] \[[ xX]\] |[ \t]*[-*+] |[ \t]*\d+[.)] |> )"#, options: .regularExpression) {
                prefix = String(content[match]); text = String(content[match.upperBound...])
            }
            let paragraph = paragraphStyle(prefix: prefix)
            let attributes: [NSAttributedString.Key: Any] = [.font: font(prefix: prefix), .foregroundColor: NativeThemeUIKit.text, .paragraphStyle: paragraph, .zerusBlock: prefix]
            let rendered = NSMutableAttributedString(string: "")
            if isChecklist(prefix) {
                let label = (try? AttributedString(markdown: NoteReference.inlineMarkdown(text))).map { String($0.characters) } ?? text
                rendered.append(checkbox(prefix: prefix, label: label))
            }
            rendered.append(NativeInlineMarkdown.render(text, images: images, attributes: attributes, proseWidth: width))
            if carriageReturn { rendered.append(NSAttributedString(string: "\r", attributes: attributes)) }
            if index < lines.count - 1 { rendered.append(NSAttributedString(string: "\n", attributes: attributes)) }
            result.append(rendered)
        }
        return result
    }

    // Ordinary attributed text has no Markdown block intent. Escaping just the
    // structural marker keeps literal writing (including pasted code examples)
    // stable across later edits and reopening; explicit block tokens stay intact.
    private static let literalBlockStart = try! NSRegularExpression(pattern: #"^ {0,3}(?:#{1,6}(?=[ \t]|$)|>|\||[-+](?=[ \t]|$)|[-=]+[ \t]*$|\d{1,9}([.)])(?=[ \t]|$))"#)
    private static let literalTableDelimiter = try! NSRegularExpression(pattern: #"^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*$"#)
    static func escapeLiteralBlockStart(_ value: String) -> String {
        // ASCII letters cannot begin either Markdown block-marker pattern.
        // Leave ordinary prose unchanged without trimming/scanning the line.
        if let first = value.utf8.first,
           (65...90).contains(first) || (97...122).contains(first) { return value }
        let content = value.trimmingCharacters(in: .newlines)
        let spaces = content.prefix(while: { $0 == " " }).count
        guard spaces <= 3, let first = content.dropFirst(spaces).first else { return value }
        let text = content as NSString, range = NSRange(location: 0, length: text.length)
        var marker: Int?
        if "#>|+-=0123456789".contains(first), let match = literalBlockStart.firstMatch(in: content, range: range) {
            let ordered = match.range(at: 1)
            marker = ordered.location == NSNotFound ? spaces : ordered.location
        } else if content.contains("|"), literalTableDelimiter.firstMatch(in: content, range: range) != nil {
            marker = text.range(of: "|").location
        }
        guard let marker else { return value }
        let escaped = NSMutableString(string: value)
        escaped.insert("\\", at: marker)
        return escaped as String
    }

    // Leading code indentation and a Markdown hard-break suffix need literal
    // whitespace too. Entities retain the visible characters without making
    // an ordinary paragraph into an unsupported indented block on reopening.
    private static func escapeLiteralWhitespace(_ value: String) -> String {
        let newline = value.hasSuffix("\r\n") ? "\r\n" : value.hasSuffix("\n") ? "\n" : value.hasSuffix("\r") ? "\r" : ""
        var line = newline.isEmpty ? value : String(value.dropLast())
        if !newline.isEmpty, line.hasSuffix("  ") { line.removeLast(); line += "&#32;" }
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
        if indent.reduce(0, { $0 + ($1 == "\t" ? 4 : 1) }) >= 4, indent.count < line.count {
            line = (line.first == "\t" ? "&#9;" : "&#32;") + line.dropFirst()
        }
        return line + newline
    }

    static func serialize(_ value: NSAttributedString) -> String {
        var output = ""
        serializedLines(value, in: NSRange(location: 0, length: value.length)) { _, line in output += line }
        return output
    }

    // Both full-note and incremental saves use the same paragraph rules.
    // The caller supplies complete lines in the original attributed string so
    // links, attachments and effective attribute ranges retain their context.
    static func serializedLines(_ value: NSAttributedString, in lines: NSRange, emit: (Int, String) -> Void) {
        let text = value.string as NSString
        var cursor = lines.location
        while cursor < NSMaxRange(lines) {
            let range = text.lineRange(for: NSRange(location: cursor, length: 0))
            let prefix = value.attribute(.zerusBlock, at: cursor, effectiveRange: nil) as? String ?? ""
            var line = prefix
            var protectedBlock = false
            var position = range.location
            while position < NSMaxRange(range) {
                var effective = NSRange()
                if let url = value.attribute(.link, at: position, longestEffectiveRange: &effective, in: range) as? URL, let reference = NoteReference(url: url) {
                    let linked = NSIntersectionRange(effective, NSRange(location: position, length: NSMaxRange(range) - position))
                    var styles = Set<Int>()
                    value.enumerateAttributes(in: linked) { attributes, _, _ in
                        let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
                        styles.insert((traits.contains(.traitBold) && !prefix.hasPrefix("#") ? 1 : 0) | (traits.contains(.traitItalic) ? 2 : 0) | (attributes[.strikethroughStyle] != nil ? 4 : 0) | (attributes[.zerusInlineCode] as? Bool == true || traits.contains(.traitMonoSpace) ? 8 : 0))
                    }
                    let label = text.substring(with: linked), style = styles.first ?? 0
                    if styles.count > 1 || style & 8 != 0 {
                        let plain = NSMutableAttributedString(attributedString: value.attributedSubstring(from: linked))
                        plain.removeAttribute(.link, range: NSRange(location: 0, length: plain.length))
                        plain.addAttribute(.zerusBlock, value: "", range: NSRange(location: 0, length: plain.length))
                        if prefix.hasPrefix("#") {
                            plain.enumerateAttribute(.font, in: NSRange(location: 0, length: plain.length)) { font, range, _ in
                                if let font = font as? UIFont { plain.addAttribute(.font, value: MarkdownText.font(traits: font.fontDescriptor.symbolicTraits.subtracting(.traitBold)), range: range) }
                            }
                        }
                        line += reference.markdown(label: label, formattedLabel: serialize(plain))
                    } else {
                        var token = reference.markdown(label: label)
                        if style & 1 != 0 { token = "**" + token + "**" }; if style & 2 != 0 { token = "*" + token + "*" }; if style & 4 != 0 { token = "~~" + token + "~~" }
                        line += token
                    }
                    position = NSMaxRange(linked)
                    continue
                }
                var part = NSRange()
                let attrs = value.attributes(at: position, longestEffectiveRange: &part, in: range)
                part = NSIntersectionRange(part, NSRange(location: position, length: NSMaxRange(range) - position))
                // UIKit can split newly typed text by paragraph metadata or
                // display attributes. Identical inline styles need one pair of
                // Markdown delimiters, including when copying a selection.
                func ordinary(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
                    attributes[.zerusDecoration] as? Bool != true && attributes[.zerusRichBlockMarkdown] == nil && attributes[.zerusImageMarkdown] == nil
                }
                func style(_ attributes: [NSAttributedString.Key: Any]) -> (UInt32, Bool, Bool, Bool, URL?) {
                    let traits = (attributes[.font] as? UIFont ?? Self.font()).fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic, .traitMonoSpace])
                    return (traits.rawValue, attributes[.zerusInlineCode] as? Bool == true, attributes[.strikethroughStyle] != nil, attributes[.underlineStyle] != nil, attributes[.link] as? URL)
                }
                if ordinary(attrs) {
                    while NSMaxRange(part) < NSMaxRange(range) {
                        var next = NSRange()
                        let attributes = value.attributes(at: NSMaxRange(part), longestEffectiveRange: &next, in: range)
                        guard ordinary(attributes), style(attrs) == style(attributes) else { break }
                        part.length = NSMaxRange(next) - part.location
                    }
                }
                position = NSMaxRange(part)
                if attrs[.zerusDecoration] as? Bool == true { continue }
                if let code = attrs[.zerusRichBlockMarkdown] as? String { protectedBlock = true; line += code; continue }
                if let image = attrs[.zerusImageMarkdown] as? String { line += image; continue }
                var string = text.substring(with: part)
                let newline = string.hasSuffix("\n")
                if newline { string.removeLast() }
                guard !string.isEmpty else { if newline { line += "\n" }; continue }
                let font = attrs[.font] as? UIFont ?? Self.font()
                let traits = font.fontDescriptor.symbolicTraits
                let code = attrs[.zerusInlineCode] as? Bool == true || traits.contains(.traitMonoSpace)
                if !code {
                    string = string.replacingOccurrences(of: #"([\\`*_\[\]<>~&$])"#, with: #"\\$1"#, options: .regularExpression)
                    if traits.contains(.traitBold) && !prefix.hasPrefix("#") { string = "**" + string + "**" }
                    if traits.contains(.traitItalic) { string = "*" + string + "*" }
                    if attrs[.strikethroughStyle] != nil { string = "~~" + string + "~~" }
                    if attrs[.underlineStyle] != nil { string = "<u>" + string + "</u>" }
                } else {
                    let fence = string.contains("`") ? "``" : "`"
                    string = fence + string + fence
                }
                if let url = attrs[.link] as? URL { string = "[" + string + "](" + url.absoluteString.replacingOccurrences(of: ")", with: "%29") + ")" }
                line += string + (newline ? "\n" : "")
            }
            emit(range.length, prefix.isEmpty && !protectedBlock ? escapeLiteralWhitespace(escapeLiteralBlockStart(line)) : line)
            cursor = NSMaxRange(range)
        }
    }
}

// Observe the actual backing store without taking over UIKit's storage
// delegate. Unchanged prefix/suffix lengths remain valid across multiple
// edits, including batched replacements and keyboard composition.
@MainActor
private final class MarkdownSerializationCache: NSObject {
    private struct Line { let length: Int; let markdown: String }
    private(set) weak var storage: NSTextStorage?
    private var lines: [Line] = []
    private var length: Int
    private var unchangedPrefix = 0
    private var unchangedSuffix = 0

    init(storage: NSTextStorage) {
        self.storage = storage; length = storage.length
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(edited), name: NSTextStorage.didProcessEditingNotification, object: storage)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func edited(_ notification: Notification) {
        guard let storage else { return }
        let range = storage.editedRange, delta = storage.changeInLength
        defer { length = storage.length }
        guard range.location != NSNotFound, storage.length - length == delta else {
            lines.removeAll(); unchangedPrefix = 0; unchangedSuffix = 0; return
        }
        unchangedPrefix = min(unchangedPrefix, range.location)
        // Conservatively include both old and new edited extents. Attribute
        // fixing may enlarge the range; overlapping edits only reduce the
        // proven unchanged portions, never reuse a changed paragraph.
        let suffix = max(0, min(length, storage.length) - NSMaxRange(range) - abs(delta))
        unchangedSuffix = min(unchangedSuffix, suffix)
    }

    func serialize() -> String {
        guard let storage else { return "" }
        if storage.length != length { lines.removeAll(); unchangedPrefix = 0; unchangedSuffix = 0; length = storage.length }
        var first = 0, prefixLength = 0
        while first < lines.count, prefixLength + lines[first].length < unchangedPrefix {
            prefixLength += lines[first].length; first += 1
        }
        var last = lines.count, suffixLength = 0
        while last > first, suffixLength + lines[last - 1].length < unchangedSuffix {
            last -= 1; suffixLength += lines[last].length
        }
        // Rebuild every line touching the edited extents or their boundaries,
        // including separators that were inserted, removed or joined.
        var changed: [Line] = []
        let range = NSRange(location: prefixLength, length: max(0, length - prefixLength - suffixLength))
        MarkdownText.serializedLines(storage, in: range) { changed.append(Line(length: $0, markdown: $1)) }
        lines.replaceSubrange(first..<last, with: changed)
        unchangedPrefix = length; unchangedSuffix = length
        return lines.map(\.markdown).joined()
    }
}


final class ZerusTextView: AdaptiveTextView {
    var noteLinkKey: ((String) -> Bool)?
    var noteLinkKeyEnabled: ((String) -> Bool)?
    private var consumedNoteLinkKeys = Set<UIKeyboardHIDUsage>()
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var remaining = presses
        for press in presses {
            guard let key = press.key, key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty else { continue }
            let input: String
            switch key.keyCode {
            case .keyboardUpArrow: input = UIKeyCommand.inputUpArrow
            case .keyboardDownArrow: input = UIKeyCommand.inputDownArrow
            case .keyboardEscape: input = UIKeyCommand.inputEscape
            case .keyboardReturnOrEnter, .keypadEnter: input = "\r"
            default: continue
            }
            if noteLinkKeyEnabled?(input) == true, noteLinkKey?(input) == true {
                consumedNoteLinkKeys.insert(key.keyCode); remaining.remove(press)
            }
        }
        if !remaining.isEmpty { super.pressesBegan(remaining, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let remaining = presses.filter { press in
            guard let key = press.key else { return true }
            return consumedNoteLinkKeys.remove(key.keyCode) == nil
        }
        if !remaining.isEmpty { super.pressesEnded(remaining, with: event) }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { consumedNoteLinkKeys.remove(key.keyCode) } }
        super.pressesCancelled(presses, with: event)
    }
    override func insertText(_ text: String) {
        if (text == "\n" || text == "\r"), noteLinkKeyEnabled?("\r") == true, noteLinkKey?("\r") == true { return }
        super.insertText(text)
    }
    var didFinishLayout: (() -> Void)?
    var onImagePaste: ((Data) -> Void)?
    var onSpreadsheetPaste: ((String) -> Void)?
    var onCopySelection: ((NSRange, Bool) -> Void)?
    var onFragmentPaste: ((Data) -> Void)?
    var onRichPaste: ((NSAttributedString) -> Void)?
    var onHTMLPaste: ((Data, [NativeHTMLClipboard.Attachment]) -> Void)?
    var onCodePaste: ((String) -> Bool)?
    var onClipboardError: ((String) -> Void)?
    var onClipboardWaiting: ((Bool) -> Void)?
    var clipboardDocumentID = ""
    private var checklistButtons: [ObjectIdentifier: UIButton] = [:]
    private var blockButtons: [ObjectIdentifier: UIButton] = [:]
    private var findHighlightRange: NSRange?
    private let findHighlightLayer = CAShapeLayer()
    func showFindHighlight(_ range: NSRange?) {
        findHighlightRange = range
        if range == nil { findHighlightLayer.path = nil }
        else { setNeedsLayout(); layoutIfNeeded() }
    }
    private func layoutFindHighlight() {
        guard let range = findHighlightRange, markedTextRange == nil, NSMaxRange(range) <= (attributedText?.length ?? 0),
              let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length), let textRange = textRange(from: start, to: end) else {
            findHighlightLayer.path = nil; return
        }
        if findHighlightLayer.superlayer == nil { layer.addSublayer(findHighlightLayer) }
        let path = UIBezierPath()
        for selection in selectionRects(for: textRange) {
            let rect = convert(selection.rect, from: textInputView)
            if !rect.isEmpty, rect.origin.x.isFinite, rect.origin.y.isFinite {
                path.append(UIBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 3))
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        findHighlightLayer.frame = CGRect(origin: .zero, size: contentSize)
        findHighlightLayer.fillColor = UIColor.systemYellow.withAlphaComponent(0.32).resolvedColor(with: traitCollection).cgColor
        findHighlightLayer.strokeColor = UIColor.systemYellow.resolvedColor(with: traitCollection).cgColor
        findHighlightLayer.lineWidth = 1; findHighlightLayer.path = path.cgPath
        CATransaction.commit()
    }
    private var positioningControls = false
    private var waitingPaste: Task<Void, Never>?
    private var waitingPasteToken: UUID?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSubviews() {
        guard !positioningControls else { return }
        positioningControls = true
        defer { layoutFindHighlight(); positioningControls = false; didFinishLayout?() }
        super.layoutSubviews()
        var retained = Set<ObjectIdentifier>()
        var retainedBlocks = Set<ObjectIdentifier>()
        if !sourceMode, let value = attributedText {
            value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { item, range, _ in
                if let block = item as? MarkdownAttachment,
                   let start = position(from: beginningOfDocument, offset: range.location),
                   let end = position(from: start, offset: 1), let glyph = textRange(from: start, to: end) {
                    let identity = ObjectIdentifier(block)
                    retainedBlocks.insert(identity)
                    let button = blockButtons[identity] ?? UIButton(type: .custom)
                    if blockButtons[identity] == nil {
                        button.addAction(UIAction { [weak block] _ in block?.edit?() }, for: .touchUpInside)
                        blockButtons[identity] = button; addSubview(button)
                    }
                    let rect = firstRect(for: glyph)
                    button.frame = rect
                    button.isHidden = rect.isEmpty || !rect.origin.x.isFinite || !rect.origin.y.isFinite
                    button.accessibilityLabel = block.editLabel
                    button.accessibilityValue = block.summary
                    button.accessibilityHint = "Opens the native editor"
                }
                guard let checkbox = item as? ChecklistAttachment,
                      let start = position(from: beginningOfDocument, offset: range.location),
                      let end = position(from: start, offset: 1), let glyph = textRange(from: start, to: end) else { return }
                let identity = ObjectIdentifier(checkbox)
                retained.insert(identity)
                let rect = firstRect(for: glyph)
                guard !rect.isEmpty, rect.origin.x.isFinite, rect.origin.y.isFinite, rect.intersects(bounds.insetBy(dx: 0, dy: -44)) else {
                    checklistButtons[identity]?.isHidden = true
                    return
                }
                let button: UIButton
                if let existing = checklistButtons[identity] { button = existing }
                else {
                    button = UIButton(type: .custom)
                    // The SF Symbol is rendered by the attachment; this control
                    // supplies native touch and accessibility behavior.
                    button.addAction(UIAction { [weak checkbox] _ in checkbox?.toggle?() }, for: .touchUpInside)
                    checklistButtons[identity] = button
                    addSubview(button)
                    checkbox.button = button
                }
                let target = CGSize(width: max(44, rect.width), height: max(44, rect.height))
                button.frame = CGRect(x: rect.midX - target.width / 2, y: rect.midY - target.height / 2, width: target.width, height: target.height)
                button.isHidden = false
                button.accessibilityLabel = (checkbox.checked ? "Mark incomplete: " : "Complete: ") + checkbox.taskLabel
                button.accessibilityValue = checkbox.checked ? "Completed" : "Not completed"
            }
        }
        for identity in Array(checklistButtons.keys) where !retained.contains(identity) {
            checklistButtons.removeValue(forKey: identity)?.removeFromSuperview()
        }
        for identity in Array(blockButtons.keys) where !retainedBlocks.contains(identity) {
            blockButtons.removeValue(forKey: identity)?.removeFromSuperview()
        }
    }
    override func copy(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        if let onCopySelection { onCopySelection(selectedRange, false); return }
        let operation = NativeClipboard.beginCopy()
        defer { NativeClipboard.finishCopy(operation) }
        do {
            let selected = NativeClipboard.selection(attributedText, range: selectedRange)
            let markdown = sourceMode ? (text as NSString).substring(with: selectedRange) : MarkdownText.serialize(selected)
            UIPasteboard.general.items = try NativeClipboard.items(fragment: NativeClipboardFragment(markdown: markdown), rich: sourceMode ? nil : selected)
            operation.written = true
        } catch { operation.failure = error.localizedDescription; onClipboardError?(error.localizedDescription) }
    }
    override func cut(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        if let onCopySelection { onCopySelection(selectedRange, true); return }
        let originalCount = UIPasteboard.general.changeCount
        copy(sender)
        if !sourceMode, let data = UIPasteboard.general.data(forPasteboardType: NativeClipboardFragment.type),
           let fragment = try? NativeClipboardFragment.decode(data), !fragment.includesLocalResources {
            onClipboardError?("An attachment could not be included. The Markdown was copied; the selected text was kept in place.")
            return
        }
        if UIPasteboard.general.changeCount != originalCount, let range = selectedTextRange { replace(range, withText: "") }
    }
    override func pasteAndMatchStyle(_ sender: Any?) {
        if waitForCopy(matchStyle: true) { return }
        if let string = UIPasteboard.general.string { insertText(string) }
    }
    override func paste(_ sender: Any?) {
        if waitForCopy(matchStyle: false) { return }
        do { pastePayload(try NativeClipboard.snapshot(UIPasteboard.general, source: sourceMode)) }
        catch { onClipboardError?(error.localizedDescription) }
    }
    func pastePayload(_ payload: NativeClipboardPayload) {
        if sourceMode {
            if let string = payload.text { insertText(string); return }
            if let bytes = payload.fragment {
                do { insertText(try NativeClipboardFragment.decode(bytes).markdown) }
                catch { onClipboardError?(error.localizedDescription) }
                return
            }
        }
        if let data = payload.fragment {
            if let onFragmentPaste { onFragmentPaste(data) }
            else {
                do {
                    let fragment = try NativeClipboardFragment.decode(data)
                    let changed = NSMutableAttributedString(attributedString: attributedText)
                    changed.replaceCharacters(in: selectedRange, with: MarkdownText.render(fragment.markdown))
                    attributedText = changed; delegate?.textViewDidChange?(self)
                } catch { onClipboardError?(error.localizedDescription) }
            }
            return
        }
        if let onHTMLPaste, let html = payload.html { onHTMLPaste(html, NativeClipboard.htmlAttachments(payload)); return }
        if let string = payload.text {
            if let onCodePaste, onCodePaste(string) { return }
            if let onSpreadsheetPaste, MarkdownTable.spreadsheet(string) != nil { onSpreadsheetPaste(string); return }
        }
        if let onRichPaste {
            for (data, format) in [(payload.rtfd, NSAttributedString.DocumentType.rtfd), (payload.rtf, .rtf)] {
                if let data, data.count <= NativeClipboardFragment.limit,
                   let rich = try? NSAttributedString(data: data, options: [.documentType: format], documentAttributes: nil) { onRichPaste(rich); return }
            }
        }
        if let image = payload.image { onImagePaste?(image); return }
        if let string = payload.text { insertText(string) }
    }
    func cancelPendingPaste(notify: Bool = true) {
        waitingPaste?.cancel(); waitingPasteToken = nil
        if notify { onClipboardWaiting?(false) }
    }
    private func finishWaiting(_ token: UUID) {
        guard waitingPasteToken == token else { return }
        waitingPasteToken = nil; onClipboardWaiting?(false)
    }
    private func waitForCopy(matchStyle: Bool) -> Bool {
        guard let initial = NativeClipboard.pendingCopy else { return false }
        waitingPaste?.cancel()
        let token = UUID(); waitingPasteToken = token
        let document = clipboardDocumentID, selection = selectedRange, visible = attributedText.string, mode = sourceMode
        onClipboardWaiting?(true)
        waitingPaste = Task { [weak self] in
            defer { self?.finishWaiting(token) }
            var pending = initial
            while !Task.isCancelled {
                if let task = pending.task { await task.value }
                else if !pending.finished { await Task.yield(); continue }
                if let latest = NativeClipboard.pendingCopy { pending = latest; continue }
                break
            }
            guard !Task.isCancelled, let self, self.waitingPasteToken == token else { return }
            guard NativeClipboard.latestCopy?.written == true else {
                self.onClipboardError?(NativeClipboard.latestCopy?.failure ?? "The copy did not finish. Copy again before pasting."); return
            }
            guard self.clipboardDocumentID == document, self.sourceMode == mode, self.selectedRange == selection, self.attributedText.string == visible else {
                self.onClipboardError?("The note changed while copying finished. Paste again at the new position."); return
            }
            self.finishWaiting(token)
            if matchStyle { self.pasteAndMatchStyle(nil) } else { self.paste(nil) }
        }
        return true
    }
}

@MainActor
final class NativeEditorActions: ObservableObject {
    weak var coordinator: NativeTextEditor.Coordinator?
    @Published var noteLink: NativeNoteLinkRequest?
    func copyNote() { if let view = coordinator?.view { coordinator?.copySelection(NSRange(location: 0, length: view.attributedText.length), cut: false, wholeNote: true) } }
    func copyMarkdown() {
        guard let coordinator else { return }
        coordinator.cancelClipboard()
        let operation = NativeClipboard.beginCopy()
        UIPasteboard.general.string = coordinator.parent.wholeNoteMarkdown?(coordinator.lastMarkdown) ?? coordinator.lastMarkdown; operation.written = true; NativeClipboard.finishCopy(operation)
    }
    func finishEditing() {
        guard let coordinator, let view = coordinator.view else { return }
        if view.markedTextRange != nil { view.unmarkText(); coordinator.textViewDidChange(view) }
        view.resignFirstResponder(); coordinator.captureReadingPosition()
    }
    func paste() { coordinator?.view?.paste(nil); coordinator?.view?.becomeFirstResponder() }
    func paste(_ providers: [NSItemProvider]) {
        if NativeClipboard.pendingCopy != nil { paste(); return }
        coordinator?.pasteProviders(providers); coordinator?.view?.becomeFirstResponder()
    }
    func revealHeading(_ fragment: String) { coordinator?.revealHeading(fragment) }
    func findSnapshot() -> NativeNoteFindSnapshot? { coordinator?.findSnapshot() }
    func pastePlainText() { coordinator?.cancelClipboard(); coordinator?.view?.pasteAndMatchStyle(nil); coordinator?.view?.becomeFirstResponder() }
}

struct NativeTextEditor: UIViewRepresentable {
    let markdown: String
    let source: Bool
    var images: [String: UIImage] = [:]
    let onChange: (String) -> Void
    let onImage: (Data) -> Void
    let onLink: (URL) -> Void
    var onCode: (CodeEditRequest) -> Void = { _ in }
    var onTable: (TableEditRequest) -> Void = { _ in }
    var copyFragment: ((String) async throws -> NativeClipboardFragment)?
    var pasteFragment: ((NativeClipboardFragment) async throws -> String)?
    var onClipboardError: (String) -> Void = { _ in }
    var onClipboardBusy: (Bool) -> Void = { _ in }
    var actions: NativeEditorActions?
    var documentID = ""
    var readOnly = false
    var wholeNoteMarkdown: ((String) -> String)? = nil
    var codeBlocksEnabled = false
    var noteLinkShortcuts = true
    var noteLinkOptions: ((String) -> [NativeNoteLinkOption])?
    var resolveNoteLink: ((String) -> NoteReference?)?
    var onNoteLinkIssue: (String) -> Void = { _ in }
    var headingRequest: NativeHeadingRequest?
    var initialPosition: NativeReadingPosition?
    var allowsInitialFocus = true
    var onPosition: ((NativeReadingPosition) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        // The designated initializer initializes Swift subclass storage.
        // A nil container selects TextKit 2 without using UIKit's class factory.
        let view = ZerusTextView(frame: .zero, textContainer: nil)
        view.onImagePaste = onImage
        view.writingToolsBehavior = .complete
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.isEditable = !readOnly
        view.allowsEditingTextAttributes = !source
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 20, left: 22, bottom: 100, right: 22)
        view.textContainer.lineFragmentPadding = 0
        view.keyboardDismissMode = .interactive
        view.linkTextAttributes = [.foregroundColor: NativeThemeUIKit.link]
        view.tintColor = NativeThemeUIKit.accent
        view.accessibilityIdentifier = "note.editor"
        context.coordinator.view = view
        actions?.coordinator = context.coordinator
        view.clipboardDocumentID = documentID
        view.onSpreadsheetPaste = { [weak coordinator = context.coordinator] value in coordinator?.insertTable(pasted: value) }
        view.onCopySelection = { [weak coordinator = context.coordinator] range, cut in coordinator?.copySelection(range, cut: cut) }
        view.onFragmentPaste = { [weak coordinator = context.coordinator] data in coordinator?.pasteFragment(data) }
        view.onHTMLPaste = { [weak coordinator = context.coordinator] data, attachments in coordinator?.pasteHTML(data, attachments: attachments) }
        view.onRichPaste = { [weak coordinator = context.coordinator] value in coordinator?.pasteRich(value) }
        view.onCodePaste = { [weak coordinator = context.coordinator] value in coordinator?.pasteCode(value) ?? false }
        view.onClipboardError = { [weak coordinator = context.coordinator] message in coordinator?.parent.onClipboardError(message) }
        view.onClipboardWaiting = { [weak coordinator = context.coordinator] busy in coordinator?.parent.onClipboardBusy(busy) }
        let links = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.linkTapped(_:)))
        links.delegate = context.coordinator
        view.addGestureRecognizer(links)
        context.coordinator.load(markdown, source: source)
        context.coordinator.prepareReadingPosition(initialPosition)
        view.didFinishLayout = { [weak coordinator = context.coordinator] in coordinator?.scheduleHeadingRequest(); coordinator?.scheduleReadingLayout() }
        context.coordinator.receiveHeading(headingRequest)
        if allowsInitialFocus, initialPosition == nil, markdown.range(of: #"^# [^\n]+\n\n$"#, options: .regularExpression) != nil {
            DispatchQueue.main.async {
                view.becomeFirstResponder()
                view.selectedRange = NSRange(location: view.attributedText.length, length: 0)
                view.typingAttributes = [.font: MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text, .zerusBlock: ""]
            }
        }
        view.inputAccessoryView = context.coordinator.accessory()
        view.noteLinkKey = { [weak coordinator = context.coordinator] input in
            guard let actions = coordinator?.parent.actions, let request = actions.noteLink else { return false }
            switch input {
            case UIKeyCommand.inputEscape: actions.dismissNoteLink()
            case UIKeyCommand.inputUpArrow: actions.moveNoteLink(-1)
            case UIKeyCommand.inputDownArrow: actions.moveNoteLink(1)
            case "\r":
                guard request.options.indices.contains(request.selected) else { return false }
                actions.chooseNoteLink(request.options[request.selected].path)
            default: return false
            }
            return true
        }
        view.noteLinkKeyEnabled = { [weak coordinator = context.coordinator] input in
            guard let request = coordinator?.parent.actions?.noteLink else { return false }
            return input == UIKeyCommand.inputEscape || !request.options.isEmpty
        }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        view.isEditable = !readOnly
        if readOnly && view.isFirstResponder { view.resignFirstResponder() }
        let becameReadOnly = readOnly && !context.coordinator.parent.readOnly
        let documentChanged = context.coordinator.parent.documentID != documentID
        if documentChanged {
            context.coordinator.cancelHeadingRequest(); context.coordinator.prepareReadingPosition(nil)
            context.coordinator.publishNoteLink(nil)
            (view as? ZerusTextView)?.cancelPendingPaste(notify: false)
            if !context.coordinator.clipboardCopyOnly { context.coordinator.cancelClipboard(notify: false) }
        }
        let codePreferenceChanged = context.coordinator.parent.codeBlocksEnabled != codeBlocksEnabled
        context.coordinator.parent = self
        if becameReadOnly {
            // UIKit prevents new typing, but a file-provider paste or cut may
            // already be awaiting IO. Cancel it after this representable update
            // so its busy-state callback does not mutate SwiftUI during layout.
            Task { @MainActor [weak coordinator = context.coordinator] in
                guard let coordinator, coordinator.parent.readOnly else { return }
                (coordinator.view as? ZerusTextView)?.cancelPendingPaste(notify: false)
                if !coordinator.clipboardCopyOnly { coordinator.cancelClipboard() }
            }
        }
        if codePreferenceChanged {
            view.inputAccessoryView = context.coordinator.accessory()
            view.reloadInputViews()
        }
        if !noteLinkShortcuts || readOnly { context.coordinator.publishNoteLink(nil) }
        actions?.coordinator = context.coordinator
        (view as? ZerusTextView)?.onImagePaste = onImage
        (view as? ZerusTextView)?.clipboardDocumentID = documentID
        let identities = MarkdownText.imageIdentities(images)
        if documentChanged || context.coordinator.lastMarkdown != markdown || context.coordinator.source != source {
            let selection = view.selectedRange
            let offset = view.contentOffset
            let modeChanged = context.coordinator.source != source
            let oldLength = view.attributedText.length
            func mapped(_ position: Int) -> Int? {
                // Source includes hidden Markdown markers. Reusing a rich-text
                // offset can move the caret into a heading or link target.
                if position >= oldLength { return nil }
                guard modeChanged else { return position }
                let prefix = view.attributedText.attributedSubstring(from: NSRange(location: 0, length: position))
                let translated = source ? (MarkdownText.serialize(prefix) as NSString).length : MarkdownText.render(prefix.string, images: images).length
                return translated
            }
            // Translate while the old attributed string is still available.
            let start = mapped(selection.location)
            let end = mapped(NSMaxRange(selection))
            context.coordinator.load(markdown, source: source)
            let length = view.attributedText.length
            let newStart = min(start ?? length, length), newEnd = min(end ?? length, length)
            view.selectedRange = NSRange(location: newStart, length: max(0, newEnd - newStart))
            view.setContentOffset(offset, animated: false)
        } else if context.coordinator.imageIdentities != identities {
            context.coordinator.imageIdentities = identities
            if !source { MarkdownText.refreshImageAttachments(in: view, images: images) }
        }
        context.coordinator.receiveHeading(headingRequest)
    }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        coordinator.captureReadingPosition(); coordinator.prepareReadingPosition(nil)
        coordinator.cancelHeadingRequest(); (view as? ZerusTextView)?.didFinishLayout = nil
        coordinator.publishNoteLink(nil)
        (view as? ZerusTextView)?.cancelPendingPaste(notify: false)
        if !coordinator.clipboardCopyOnly { coordinator.cancelClipboard(notify: false) }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: NativeTextEditor
        weak var view: UITextView?
        private var readingPosition: NativeReadingPosition?
        private var readingRestoreFinished = true
        private var readingLayoutScheduled = false
        private var readingBodyHash: String?
        private var renderingText = false
        private var positioningReadingView = false
        func prepareReadingPosition(_ position: NativeReadingPosition?) {
            readingPosition = position; readingRestoreFinished = position == nil
        }
        func scheduleReadingLayout() {
            guard parent.onPosition != nil || readingPosition != nil, !readingLayoutScheduled else { return }
            readingLayoutScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.readingLayoutScheduled = false; self.restoreReadingPosition(); self.captureReadingPosition()
            }
        }
        private func bodyHash() -> String {
            if let readingBodyHash { return readingBodyHash }
            let hash = NativeReadingPosition.hash(lastMarkdown); readingBodyHash = hash; return hash
        }
        func captureReadingPosition() {
            guard let receive = parent.onPosition, readingRestoreFinished, !renderingText, !positioningReadingView, headingRequest == nil,
                  let view, view.window != nil, view.bounds.width > 0, view.bounds.height > 0, view.markedTextRange == nil else { return }
            let length = view.attributedText.length, selected = view.selectedRange
            guard selected.location <= length, NSMaxRange(selected) <= length else { return }
            let point = CGPoint(x: view.textContainerInset.left + 2, y: view.bounds.minY + view.adjustedContentInset.top + 2)
            guard let top = view.closestPosition(to: view.textInputView.convert(point, from: view)),
                  let caret = view.textRange(from: top, to: top) else { return }
            let rect = view.convert(view.firstRect(for: caret), from: view.textInputView)
            guard rect.minY.isFinite, rect.height > 0 else { return }
            let position = NativeReadingPosition(bodyHash: bodyHash(), source: source, selection: selected.location, selectionLength: selected.length,
                                                 top: view.offset(from: view.beginningOfDocument, to: top), lineOffset: view.bounds.minY + view.adjustedContentInset.top - rect.minY)
            if position.valid { receive(position) }
        }
        private func restoreReadingPosition() {
            guard let position = readingPosition, let view, view.window != nil, view.bounds.width > 0, view.bounds.height > 0, view.markedTextRange == nil else { return }
            readingPosition = nil; readingRestoreFinished = true
            let length = view.attributedText.length
            guard position.valid, position.bodyHash == bodyHash(), position.source == source, position.top <= length,
                  position.selection <= length, position.selection + position.selectionLength <= length else { return }
            positioningReadingView = true; defer { positioningReadingView = false }
            view.selectedRange = NSRange(location: position.selection, length: position.selectionLength)
            if let manager = view.textLayoutManager, let content = manager.textContentManager,
               let start = content.location(content.documentRange.location, offsetBy: position.top) {
                if let end = content.location(content.documentRange.location, offsetBy: min(length, position.top + 1)), let range = NSTextRange(location: start, end: end) { manager.ensureLayout(for: range) }
                let anchor = manager.textViewportLayoutController.relocateViewport(to: start)
                if anchor.isFinite { view.setContentOffset(CGPoint(x: view.contentOffset.x, y: max(-view.adjustedContentInset.top, anchor)), animated: false) }
                manager.textViewportLayoutController.layoutViewport()
            }
            view.setNeedsLayout(); view.layoutIfNeeded()
            if let top = view.position(from: view.beginningOfDocument, offset: position.top), let caret = view.textRange(from: top, to: top) {
                let rect = view.convert(view.firstRect(for: caret), from: view.textInputView)
                if rect.minY.isFinite, rect.height > 0 {
                    let minimum = -view.adjustedContentInset.top, maximum = max(minimum, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
                    let offset = min(maximum, max(minimum, rect.minY + position.lineOffset - view.adjustedContentInset.top))
                    view.setContentOffset(CGPoint(x: view.contentOffset.x, y: offset), animated: false)
                }
            }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { scheduleReadingLayout() }
        private var headingRequest: (NativeHeadingRequest, String, Bool)?
        private var receivedHeadingID: UUID?
        private var headingLayoutScheduled = false
        func scheduleHeadingRequest() {
            guard headingRequest != nil, !headingLayoutScheduled else { return }
            headingLayoutScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.headingLayoutScheduled = false; self.applyHeadingRequest()
            }
        }
        func cancelHeadingRequest() { headingRequest = nil; receivedHeadingID = nil }
        func receiveHeading(_ request: NativeHeadingRequest?) {
            guard let request else { if headingRequest?.2 == true { headingRequest = nil }; return }
            guard receivedHeadingID != request.id else { return }
            prepareReadingPosition(nil)
            receivedHeadingID = request.id; headingRequest = (request, parent.documentID, true)
            view?.setNeedsLayout(); scheduleHeadingRequest()
        }
        func revealHeading(_ fragment: String) {
            prepareReadingPosition(nil)
            headingRequest = (NativeHeadingRequest(fragment: fragment), parent.documentID, false)
            view?.setNeedsLayout(); applyHeadingRequest()
        }
        func applyHeadingRequest() {
            guard let (request, document, _) = headingRequest, let view, view.window != nil,
                  view.bounds.width > 0, view.bounds.height > 0, view.markedTextRange == nil else { return }
            headingRequest = nil
            guard parent.documentID == document else { return }
            let range: NSRange
            if request.fragment.isEmpty { range = NSRange(location: 0, length: 0) }
            else {
                guard let heading = NativeHeadings.target(request.fragment, in: lastMarkdown) else { parent.onNoteLinkIssue("This heading is no longer in the note. Open the outline to choose a current heading."); return }
                if source { range = heading.range }
                else {
                    let prefix = (lastMarkdown as NSString).substring(to: heading.range.location)
                    let start = MarkdownText.render(prefix, images: parent.images).length
                    let text = view.attributedText.string as NSString
                    guard start < text.length else { parent.onNoteLinkIssue("This heading could not be located in the editor. Try Markdown source."); return }
                    var paragraph = text.paragraphRange(for: NSRange(location: start, length: 0))
                    while paragraph.length > 0, [10, 13].contains(Int(text.character(at: NSMaxRange(paragraph) - 1))) { paragraph.length -= 1 }
                    range = paragraph
                }
            }
            revealSelection(range)
        }
        func revealSelection(_ range: NSRange) {
            guard let view, view.markedTextRange == nil, range.location != NSNotFound, NSMaxRange(range) <= view.attributedText.length else { return }
            prepareReadingPosition(nil); cancelHeadingRequest()
            if let manager = view.textLayoutManager, let content = manager.textContentManager,
               let start = content.location(content.documentRange.location, offsetBy: range.location) {
                if let end = content.location(content.documentRange.location, offsetBy: NSMaxRange(range)),
                   let target = NSTextRange(location: start, end: end) { manager.ensureLayout(for: target) }
                // A distant destination can lie beyond TextKit's estimated
                // content height, especially after changing editor modes.
                // Move the viewport to the actual text location before using
                // its geometry to position the scroll view.
                let anchor = manager.textViewportLayoutController.relocateViewport(to: start)
                if anchor.isFinite {
                    view.setContentOffset(CGPoint(x: view.contentOffset.x, y: max(-view.adjustedContentInset.top, anchor)), animated: false)
                }
                manager.textViewportLayoutController.layoutViewport()
            }
            view.setNeedsLayout(); view.layoutIfNeeded(); view.selectedRange = range
            if let start = view.position(from: view.beginningOfDocument, offset: range.location),
               let end = view.position(from: start, offset: range.length), let selection = view.textRange(from: start, to: end) {
                let rect = view.convert(view.firstRect(for: selection), from: view.textInputView)
                if rect.origin.x.isFinite, rect.origin.y.isFinite, rect.height > 0 {
                    let minimum = -view.adjustedContentInset.top
                    let maximum = max(minimum, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
                    let target = min(maximum, max(minimum, rect.minY - view.textContainerInset.top - view.adjustedContentInset.top))
                    view.setContentOffset(CGPoint(x: view.contentOffset.x, y: target), animated: false)
                }
                else { view.scrollRangeToVisible(range) }
            } else { view.scrollRangeToVisible(range) }
            publishNoteLink(nil)
        }
        var lastMarkdown = "" { didSet { if oldValue != lastMarkdown { readingBodyHash = nil } } }
        var source = false
        var imageIdentities: [String: ObjectIdentifier] = [:]
        private var originalMarkdown = ""
        private var originalRich = NSAttributedString(string: "")
        private var serialization: MarkdownSerializationCache?
        private var clipboardTask: Task<Void, Never>?
        private var clipboardToken: UUID?
        private(set) var clipboardCopyOnly = false
        var noteLinkGeneration = 0
        var dismissedNoteLink: String?
        init(_ parent: NativeTextEditor) { self.parent = parent }
        func cancelClipboard(notify: Bool = true) {
            clipboardTask?.cancel(); clipboardToken = nil; (view as? ZerusTextView)?.cancelPendingPaste(notify: false)
            if notify { parent.onClipboardBusy(false) }
        }
        private func clipboardOperation(copyOnly: Bool = false, copy: NativeCopyOperation? = nil, _ work: @escaping (Coordinator) async throws -> Void) {
            clipboardTask?.cancel()
            clipboardCopyOnly = copyOnly
            let token = UUID(); clipboardToken = token; parent.onClipboardBusy(true)
            clipboardTask = Task { [weak self] in
                defer { if let copy { NativeClipboard.finishCopy(copy) } }
                guard let self else { return }
                defer { if self.clipboardToken == token { self.clipboardToken = nil; self.parent.onClipboardBusy(false) } }
                do { try await work(self) }
                catch is CancellationError { }
                catch { if !Task.isCancelled { copy?.failure = error.localizedDescription; self.parent.onClipboardError(error.localizedDescription) } }
            }
            copy?.task = clipboardTask
        }
        func copySelection(_ range: NSRange, cut: Bool, wholeNote: Bool = false) {
            guard let view, range.length > 0 || wholeNote else { return }
            if view.markedTextRange != nil { view.unmarkText(); textViewDidChange(view) }
            let original = NSAttributedString(attributedString: view.attributedText), baseline = lastMarkdown, mode = source
            let document = parent.documentID, capture = parent.copyFragment
            var selected = NativeClipboard.selection(original, range: range)
            let selectionMarkdown = range.location == 0 && range.length == original.length ? lastMarkdown : source ? (view.text as NSString).substring(with: range) : MarkdownText.serialize(selected)
            let markdown = wholeNote ? parent.wholeNoteMarkdown?(lastMarkdown) ?? selectionMarkdown : selectionMarkdown
            if wholeNote && markdown != selectionMarkdown { selected = MarkdownText.render(markdown, images: parent.images) }
            let intent = NativeClipboard.beginCopy()
            // Publish useful eager text immediately. Other apps never receive
            // an older clipboard selection while the original assets load.
            guard markdown.utf8.count <= NativeClipboardFragment.limit else { NativeClipboard.finishCopy(intent); parent.onClipboardError("Copy a selection smaller than 50 MB."); return }
            UIPasteboard.general.items = [[UTType.utf8PlainText.identifier: markdown, "net.daringfireball.markdown": Data(markdown.utf8)]]
            let changeCount = UIPasteboard.general.changeCount, richSelection = selected
            clipboardOperation(copyOnly: !cut, copy: intent) { owner in
                let fragment: NativeClipboardFragment
                if let capture { fragment = try await capture(markdown) }
                else { fragment = NativeClipboardFragment(markdown: markdown) }
                try Task.checkCancellation()
                guard NativeClipboard.isCurrentCopy(intent) else { throw CancellationError() }
                guard UIPasteboard.general.changeCount == changeCount else { throw VaultFailure(message: "The clipboard changed while attachments were being copied. Copy the selection again; your note is unchanged.") }
                let portableRich = fragment.markdown == markdown ? richSelection : MarkdownText.render(fragment.markdown, images: owner.parent.images)
                let items = try NativeClipboard.items(fragment: fragment, rich: mode ? nil : portableRich)
                UIPasteboard.general.items = items
                intent.written = true
                if cut {
                    guard mode || fragment.includesLocalResources else { throw VaultFailure(message: "An attachment could not be included. The Markdown was copied; the selected text was kept in place.") }
                    guard let view = owner.view, !owner.parent.readOnly, view.markedTextRange == nil, owner.parent.documentID == document, owner.lastMarkdown == baseline, owner.source == mode, view.selectedRange == range, view.attributedText.string == original.string else {
                        throw VaultFailure(message: "The selection was copied, but the note changed before cutting finished. Its text was kept in place.")
                    }
                    let inverse = view.attributedText!, changed = NSMutableAttributedString(attributedString: inverse)
                    changed.deleteCharacters(in: range)
                    owner.apply(changed, selection: NSRange(location: range.location, length: 0), inverse: inverse)
                }
            }
        }
        func pasteFragment(_ data: Data) {
            do { paste(try NativeClipboardFragment.decode(data)) }
            catch { parent.onClipboardError(error.localizedDescription) }
        }
        func pasteRich(_ rich: NSAttributedString) {
            do { paste(try NativeClipboard.importRich(rich)) }
            catch { parent.onClipboardError(error.localizedDescription) }
        }
        func pasteCode(_ text: String) -> Bool {
            guard parent.codeBlocksEnabled, !parent.readOnly, !source, !FencedCode.blocks(in: text).isEmpty else { return false }
            paste(NativeClipboardFragment(markdown: text))
            return true
        }
        func pasteProviders(_ providers: [NSItemProvider]) {
            guard let view, !parent.readOnly else { return }
            if view.markedTextRange != nil { view.unmarkText(); textViewDidChange(view) }
            let document = parent.documentID, baseline = lastMarkdown, mode = source, selection = view.selectedRange, visible = view.attributedText.string, codeBlocks = parent.codeBlocksEnabled
            clipboardOperation { owner in
                let payload = try await NativeClipboard.payload(providers, source: mode)
                try Task.checkCancellation()
                guard let current = owner.view as? ZerusTextView, !owner.parent.readOnly, current.markedTextRange == nil,
                      owner.parent.documentID == document, owner.lastMarkdown == baseline, owner.source == mode, owner.parent.codeBlocksEnabled == codeBlocks,
                      current.selectedRange == selection, current.attributedText.string == visible else { throw VaultFailure(message: "The note changed while loading the clipboard. Paste again at the new position.") }
                current.pastePayload(payload)
            }
        }
        func pasteHTML(_ data: Data, attachments: [NativeHTMLClipboard.Attachment]) {
            paste {
                let job = Task.detached(priority: .userInitiated) { try await NativeHTMLClipboard.fragment(data, attachments: attachments) }
                return try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
            }
        }
        private func paste(_ fragment: NativeClipboardFragment) { paste { fragment } }
        private func paste(prepare: @escaping () async throws -> NativeClipboardFragment) {
            guard let view, !parent.readOnly else { return }
            if view.markedTextRange != nil { view.unmarkText(); textViewDidChange(view) }
            let baseline = lastMarkdown, selection = view.selectedRange, mode = source, codeBlocks = parent.codeBlocksEnabled
            let visibleText = view.attributedText.string
            let document = parent.documentID, receive = parent.pasteFragment
            clipboardOperation { owner in
                try Task.checkCancellation()
                guard owner.parent.documentID == document else { throw CancellationError() }
                let fragment = try await prepare()
                try Task.checkCancellation()
                guard mode || !MarkdownText.requiresSource(fragment.markdown) else {
                    throw VaultFailure(message: "This selection needs Markdown source editing. Use Paste plain text to keep its available writing.")
                }
                guard let current = owner.view, !owner.parent.readOnly, current.markedTextRange == nil, owner.parent.documentID == document, owner.lastMarkdown == baseline, owner.source == mode, owner.parent.codeBlocksEnabled == codeBlocks, current.selectedRange == selection, current.attributedText.string == visibleText else {
                    throw VaultFailure(message: "The note changed while the clipboard was being prepared. Paste again at the new position.")
                }
                let markdown: String
                if let receive { markdown = try await receive(fragment) }
                else { markdown = fragment.markdown }
                try Task.checkCancellation()
                guard let view = owner.view, !owner.parent.readOnly, view.markedTextRange == nil, view.attributedText.string == visibleText, owner.parent.documentID == document, owner.lastMarkdown == baseline, owner.source == mode, owner.parent.codeBlocksEnabled == codeBlocks, view.selectedRange == selection else {
                    throw VaultFailure(message: "The note or code-block setting changed while attachments were being imported. Your writing is unchanged; paste again at the new position.")
                }
                let original = view.attributedText!, changed = NSMutableAttributedString(attributedString: original)
                let rich = mode ? NSAttributedString(string: markdown, attributes: view.typingAttributes) : MarkdownText.render(markdown, images: owner.parent.images, width: max(140, view.bounds.width - 44), codeBlocks: codeBlocks)
                let insertion = mode ? rich : NativeClipboard.insertion(rich, into: original, range: selection)
                changed.replaceCharacters(in: selection, with: insertion)
                owner.apply(changed, selection: NSRange(location: selection.location + insertion.length, length: 0), inverse: original)
                view.typingAttributes = [.font: MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text, .zerusBlock: ""]
            }
        }
        func load(_ markdown: String, source: Bool) {
            guard let view else { return }
            renderingText = true; defer { renderingText = false }
            serialization = nil
            (view as? ZerusTextView)?.showFindHighlight(nil)
            publishNoteLink(nil)
            self.source = source; lastMarkdown = markdown; originalMarkdown = markdown; imageIdentities = MarkdownText.imageIdentities(parent.images)
            (view as? ZerusTextView)?.sourceMode = source
            if source {
                let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
                view.font = UIFont(descriptor: font.fontDescriptor.withDesign(.monospaced) ?? font.fontDescriptor, size: 0)
                view.textColor = NativeThemeUIKit.text; view.text = markdown
                view.autocorrectionType = .no; view.smartQuotesType = .no; view.smartDashesType = .no
            } else {
                let rich = MarkdownText.render(markdown, images: parent.images, width: view.bounds.width > 0 ? view.bounds.width - 44 : 350); view.attributedText = rich; originalRich = rich
                serialization = MarkdownSerializationCache(storage: view.textStorage)
                view.typingAttributes = [.font: MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text, .zerusBlock: ""]
                view.autocorrectionType = .default; view.smartQuotesType = .default; view.smartDashesType = .default
            }
            view.allowsEditingTextAttributes = !source
            view.selectedRange = NSRange(location: view.attributedText.length, length: 0)
            updateAccessibilityActions()
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", textView.markedTextRange == nil, let request = parent.actions?.noteLink,
               request.options.indices.contains(request.selected), request.insert(request.options[request.selected].path) {
                request.dismiss(); return false
            }
            if !source {
                if text == "\n", typedCode(textView, range: range) { return false }
                if editChecklist(textView, range: range, text: text) { return false }
                textView.typingAttributes.removeValue(forKey: .zerusImageMarkdown)
                textView.typingAttributes.removeValue(forKey: .zerusRichBlockMarkdown)
                textView.typingAttributes.removeValue(forKey: .zerusDecoration)
                textView.typingAttributes.removeValue(forKey: .attachment)
                if ["zerus-image", "zerus-check"].contains((textView.typingAttributes[.link] as? URL)?.scheme ?? "") { textView.typingAttributes.removeValue(forKey: .link) }
            }
            if !source && text == "\n" {
                let current = textView.typingAttributes[.zerusBlock] as? String ?? ""
                if current.hasPrefix("#") || current == "> " {
                    DispatchQueue.main.async {
                        textView.typingAttributes = [.font: MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text, .zerusBlock: ""]
                    }
                }
            }
            return true
        }
        private func typedCode(_ view: UITextView, range: NSRange) -> Bool {
            guard parent.codeBlocksEnabled, !parent.readOnly, view.markedTextRange == nil,
                  range.length == 0, view.attributedText.length > 0 else { return false }
            let value = view.attributedText!, text = value.string as NSString
            let paragraph = text.paragraphRange(for: NSRange(location: range.location, length: 0))
            let marker = text.substring(with: paragraph).trimmingCharacters(in: .newlines)
            guard range.location == paragraph.location + (marker as NSString).length,
                  marker.range(of: #"^```([\w+-]+)?[ \t]?$"#, options: .regularExpression) != nil else { return false }
            var protected = false
            value.enumerateAttributes(in: NSRange(location: paragraph.location, length: (marker as NSString).length)) { attributes, _, _ in
                if attributes[.attachment] != nil || attributes[.link] != nil || attributes[.zerusInlineCode] as? Bool == true ||
                    !(attributes[.zerusBlock] as? String ?? "").isEmpty ||
                    (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true { protected = true }
            }
            guard !protected else { return false }
            insertCode(replacing: NSRange(location: paragraph.location, length: (marker as NSString).length), info: String(marker.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            return true
        }
        private func editChecklist(_ view: UITextView, range: NSRange, text: String) -> Bool {
            let original = view.attributedText!
            guard original.length > 0 else { return false }
            let location = min(range.location, original.length - 1)
            let paragraph = (original.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            let prefix = original.attribute(.zerusBlock, at: paragraph.location, effectiveRange: nil) as? String ?? ""
            var marker = NSRange()
            guard MarkdownText.isChecklist(prefix), original.attribute(.zerusDecoration, at: paragraph.location, effectiveRange: &marker) as? Bool == true else { return false }
            let label = (original.string as NSString).substring(with: NSRange(location: NSMaxRange(marker), length: max(0, NSMaxRange(paragraph) - NSMaxRange(marker)))).trimmingCharacters(in: .whitespacesAndNewlines)
            let removeMarker = text.isEmpty && range.length > 0 && range.location >= marker.location && NSMaxRange(range) <= NSMaxRange(marker)
            if removeMarker || (text == "\n" && label.isEmpty && range.length == 0) {
                let changed = NSMutableAttributedString(attributedString: original)
                changed.deleteCharacters(in: marker)
                let remaining = NSRange(location: paragraph.location, length: paragraph.length - marker.length)
                changed.addAttributes([.zerusBlock: "", .paragraphStyle: MarkdownText.paragraphStyle(prefix: "")], range: remaining)
                var caret = paragraph.location
                if text == "\n" {
                    // A blank line separates an ordinary paragraph from the
                    // preceding list in portable Markdown as well as in TextKit.
                    changed.insert(NSAttributedString(string: "\n", attributes: [.zerusBlock: "", .font: MarkdownText.font(), .paragraphStyle: MarkdownText.paragraphStyle(prefix: "")]), at: caret)
                    caret += 1
                }
                apply(changed, selection: NSRange(location: caret, length: 0), inverse: original)
                view.typingAttributes = [.font: MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text, .zerusBlock: "", .paragraphStyle: MarkdownText.paragraphStyle(prefix: "")]
                return true
            }
            guard text == "\n", range.location >= NSMaxRange(marker) else { return false }
            let nextPrefix = prefix.replacingOccurrences(of: #"\[[xX]\]"#, with: "[ ]", options: .regularExpression)
            let suffix = (original.string as NSString).substring(with: NSRange(location: NSMaxRange(range), length: max(0, NSMaxRange(paragraph) - NSMaxRange(range)))).trimmingCharacters(in: .whitespacesAndNewlines)
            let insertion = NSMutableAttributedString(string: "\n", attributes: [.font: MarkdownText.font(), .zerusBlock: prefix, .paragraphStyle: MarkdownText.paragraphStyle(prefix: prefix)])
            insertion.append(MarkdownText.checkbox(prefix: nextPrefix, label: suffix))
            let changed = NSMutableAttributedString(attributedString: original)
            changed.replaceCharacters(in: range, with: insertion)
            let nextParagraph = (changed.string as NSString).paragraphRange(for: NSRange(location: range.location + 1, length: 0))
            changed.addAttributes([.zerusBlock: nextPrefix, .paragraphStyle: MarkdownText.paragraphStyle(prefix: nextPrefix)], range: nextParagraph)
            apply(changed, selection: NSRange(location: range.location + insertion.length, length: 0), inverse: original)
            view.typingAttributes = [.font: MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text, .zerusBlock: nextPrefix, .paragraphStyle: MarkdownText.paragraphStyle(prefix: nextPrefix)]
            return true
        }
        func textViewDidChange(_ textView: UITextView) {
            (textView as? ZerusTextView)?.showFindHighlight(nil)
            // Marked text belongs to the keyboard's composition session.
            guard textView.markedTextRange == nil else { publishNoteLink(nil); return }
            textView.setNeedsLayout()
            let value: String
            if source { value = textView.text ?? "" }
            else {
                if serialization?.storage !== textView.textStorage { serialization = MarkdownSerializationCache(storage: textView.textStorage) }
                let normalized = serialization!.serialize()
                value = textView.attributedText.isEqual(to: originalRich) ? originalMarkdown : normalized
            }
            lastMarkdown = value; parent.onChange(value)
            updateAccessibilityActions()
            refreshNoteLink(); scheduleReadingLayout()
        }
        func textViewDidChangeSelection(_ textView: UITextView) { (textView as? ZerusTextView)?.showFindHighlight(nil); refreshNoteLink(); scheduleReadingLayout() }
        func textViewDidEndEditing(_ textView: UITextView) { publishNoteLink(nil) }
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            if interaction == .invokeDefaultAction { follow(URL, range: characterRange) }
            return false
        }
        private func link(at point: CGPoint) -> (URL, NSRange)? {
            guard let view, !source, let position = view.closestPosition(to: point), view.attributedText.length > 0 else { return nil }
            let location = min(view.offset(from: view.beginningOfDocument, to: position), view.attributedText.length - 1)
            for index in [location, max(0, location - 1)] {
                var range = NSRange()
                guard let url = view.attributedText.attribute(.link, at: index, effectiveRange: &range) as? URL,
                      let start = view.position(from: view.beginningOfDocument, offset: range.location),
                      let end = view.position(from: start, offset: range.length), let selection = view.textRange(from: start, to: end) else { continue }
                if view.selectionRects(for: selection).contains(where: { $0.rect.insetBy(dx: -4, dy: -5).contains(point) }) { return (url, range) }
            }
            return nil
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view, let (url, _) = link(at: gestureRecognizer.location(in: view)) else { return false }
            return !view.isFirstResponder || url.scheme == "zerus-check"
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var ancestor = touch.view
            while let view = ancestor {
                if view is UIControl { return false }
                ancestor = view.superview
            }
            return true
        }
        @objc func linkTapped(_ sender: UITapGestureRecognizer) {
            guard let view, let (url, range) = link(at: sender.location(in: view)) else { return }
            follow(url, range: range)
        }
        private func follow(_ url: URL, range: NSRange) {
            if let fragment = NativeHeadings.localFragment(url) { revealHeading(fragment); return }
            guard url.scheme == "zerus-check", let view else { parent.onLink(url); return }
            let old = view.attributedText!
            let paragraph = (old.string as NSString).paragraphRange(for: range)
            let current = old.attribute(.zerusBlock, at: paragraph.location, effectiveRange: nil) as? String ?? ""
            guard MarkdownText.isChecklist(current) else { return }
            let target = current.lowercased().contains("[x]") ? current.replacingOccurrences(of: #"\[[xX]\]"#, with: "[ ]", options: .regularExpression) : current.replacingOccurrences(of: "[ ]", with: "[x]")
            let changed = NSMutableAttributedString(attributedString: old)
            changed.addAttribute(.zerusBlock, value: target, range: paragraph)
            var marker = NSRange()
            guard changed.attribute(.zerusDecoration, at: paragraph.location, effectiveRange: &marker) as? Bool == true else { return }
            let label = (old.string as NSString).substring(with: NSRange(location: NSMaxRange(marker), length: max(0, NSMaxRange(paragraph) - NSMaxRange(marker)))).trimmingCharacters(in: .whitespacesAndNewlines)
            changed.replaceCharacters(in: marker, with: MarkdownText.checkbox(prefix: target, label: label))
            let offset = view.contentOffset
            apply(changed, selection: view.selectedRange, inverse: old)
            view.setContentOffset(offset, animated: false)
        }
        private func updateAccessibilityActions() {
            guard let view, !source else { view?.accessibilityCustomActions = nil; return }
            let text = view.attributedText!
            var blockIndex = 0
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                if let block = value as? MarkdownAttachment {
                    let ordinal = blockIndex; blockIndex += 1
                    block.edit = { [weak self, weak block] in
                        guard let self, let block else { return }
                        self.view?.resignFirstResponder()
                        let baseline = self.lastMarkdown, raw = block.markdown, document = self.parent.documentID
                        let width = max(140, (self.view?.bounds.width ?? 394) - 44)
                        if let code = block as? CodeAttachment {
                            self.parent.onCode(CodeEditRequest(code: code.code, save: { [weak self] edited in
                                self?.replaceBlock(MarkdownText.codeToken(edited, width: width), ordinal: ordinal, raw: raw, baseline: baseline, document: document) ?? false
                            }, convertToText: { [weak self] body in
                                let attributes: [NSAttributedString.Key: Any] = [.font: MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text, .zerusBlock: "", .paragraphStyle: MarkdownText.paragraphStyle(prefix: "")]
                                let literal = NSAttributedString(string: body, attributes: attributes)
                                return self?.replaceBlock(literal, ordinal: ordinal, raw: raw, baseline: baseline, document: document) ?? false
                            }))
                        } else if let table = block as? TableAttachment {
                            self.parent.onTable(TableEditRequest(table: table.table, save: { [weak self] edited in
                                guard let self else { return false }
                                return self.replaceBlock(MarkdownText.tableToken(edited, width: width, images: self.parent.images), ordinal: ordinal, raw: raw, baseline: baseline, document: document)
                            }))
                        }
                    }
                }
                guard let checkbox = value as? ChecklistAttachment else { return }
                checkbox.toggle = { [weak self, weak checkbox] in
                    guard let self, let checkbox, let value = self.view?.attributedText else { return }
                    value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { attachment, range, stop in
                        if (attachment as? ChecklistAttachment) === checkbox {
                            self.follow(URL(string: "zerus-check://toggle")!, range: range)
                            stop.pointee = true
                        }
                    }
                }
            }
            var actions: [UIAccessibilityCustomAction] = []
            text.enumerateAttribute(.zerusDecoration, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                guard value as? Bool == true else { return }
                let paragraph = (text.string as NSString).paragraphRange(for: range)
                let prefix = text.attribute(.zerusBlock, at: range.location, effectiveRange: nil) as? String ?? ""
                let labelRange = NSRange(location: NSMaxRange(range), length: max(0, NSMaxRange(paragraph) - NSMaxRange(range)))
                let label = (text.string as NSString).substring(with: labelRange).trimmingCharacters(in: .whitespacesAndNewlines)
                (text.attribute(.attachment, at: range.location, effectiveRange: nil) as? ChecklistAttachment)?.updateLabel(label)
                let action = UIAccessibilityCustomAction(name: (prefix.lowercased().contains("[x]") ? "Mark incomplete: " : "Complete: ") + label) { [weak self] _ in
                    self?.follow(URL(string: "zerus-check://toggle")!, range: range)
                    return true
                }
                actions.append(action)
            }
            view.accessibilityCustomActions = actions
        }
        private func replaceBlock(_ replacement: NSAttributedString, ordinal: Int, raw: String, baseline: String, document: String) -> Bool {
            guard let view, !source, !parent.readOnly, view.markedTextRange == nil,
                  parent.documentID == document, lastMarkdown == baseline else { return false }
            let original = view.attributedText!
            var index = 0, saved = false
            original.enumerateAttribute(.attachment, in: NSRange(location: 0, length: original.length)) { item, range, stop in
                guard let current = item as? MarkdownAttachment else { return }
                defer { index += 1 }
                guard index == ordinal, current.markdown == raw else { return }
                if replacement.length > 0, replacement.attribute(.zerusRichBlockMarkdown, at: 0, effectiveRange: nil) as? String == raw {
                    saved = true; stop.pointee = true; return
                }
                let changed = NSMutableAttributedString(attributedString: original)
                changed.replaceCharacters(in: range, with: replacement)
                let offset = view.contentOffset
                apply(changed, selection: NSRange(location: range.location + replacement.length, length: 0), inverse: original)
                view.typingAttributes = [.font: MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text, .zerusBlock: "", .paragraphStyle: MarkdownText.paragraphStyle(prefix: "")]
                view.setContentOffset(offset, animated: false)
                saved = true; stop.pointee = true
            }
            return saved
        }
        func accessory() -> UIView {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            let heading = UIBarButtonItem(title: "H", style: .plain, target: self, action: #selector(heading))
            heading.accessibilityLabel = "Heading"
            let bold = UIBarButtonItem(image: UIImage(systemName: "bold"), style: .plain, target: self, action: #selector(bold))
            bold.accessibilityLabel = "Bold"
            let italic = UIBarButtonItem(image: UIImage(systemName: "italic"), style: .plain, target: self, action: #selector(italic))
            italic.accessibilityLabel = "Italic"
            let list = UIBarButtonItem(image: UIImage(systemName: "list.bullet"), menu: UIMenu(children: [
                UIAction(title: "Bulleted list", image: UIImage(systemName: "list.bullet")) { [weak self] _ in self?.block("- ") },
                UIAction(title: "Numbered list", image: UIImage(systemName: "list.number")) { [weak self] _ in self?.block("1. ") },
                UIAction(title: "Checklist", image: UIImage(systemName: "checklist")) { [weak self] _ in self?.block("- [ ] ") },
                UIAction(title: "Table", image: UIImage(systemName: "tablecells")) { [weak self] _ in self?.insertTable() },
                ] + (parent.codeBlocksEnabled ? [UIAction(title: "Code block", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")) { [weak self] _ in self?.insertCode() }] : []) + [
                UIAction(title: "Quote", image: UIImage(systemName: "text.quote")) { [weak self] _ in self?.block("> ") }
            ]))
            list.accessibilityLabel = "Paragraph style"
            let undo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.backward"), style: .plain, target: self, action: #selector(undo))
            undo.accessibilityLabel = "Undo"
            let redo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.forward"), style: .plain, target: self, action: #selector(redo))
            redo.accessibilityLabel = "Redo"
            let dismiss = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), style: .plain, target: self, action: #selector(dismissKeyboard))
            dismiss.accessibilityLabel = "Dismiss keyboard"
            if #available(iOS 27.0, *) {
                dismiss.visibilityPriority = .high
            }
            toolbar.items = [heading, .flexibleSpace(), bold, italic, list, .flexibleSpace(), undo, redo, .flexibleSpace(), dismiss]
            return toolbar
        }
        @objc func bold() { if source { wrap("**") } else { view?.toggleBoldface(nil); if let view { textViewDidChange(view) } } }
        @objc func italic() { if source { wrap("*") } else { view?.toggleItalics(nil); if let view { textViewDidChange(view) } } }
        @objc func heading() { block("## ") }
        @objc func undo() { view?.undoManager?.undo() }
        @objc func redo() { view?.undoManager?.redo() }
        @objc func dismissKeyboard() { view?.resignFirstResponder() }
        func insertCode(replacing marker: NSRange? = nil, info: String = "") {
            guard let view, parent.codeBlocksEnabled, !parent.readOnly else { return }
            let empty = FencedCode.blocks(in: "```\n```").first!.code
            if source {
                let selected = (view.text as NSString).substring(with: view.selectedRange)
                view.insertText("\n" + empty.replacing(body: selected, info: "").markdown + "\n")
                textViewDidChange(view); return
            }
            let baseline = lastMarkdown, selection = marker ?? view.selectedRange, document = parent.documentID
            let selected = marker == nil ? MarkdownText.serialize(view.attributedText.attributedSubstring(from: selection)) : ""
            view.resignFirstResponder()
            parent.onCode(CodeEditRequest(code: empty.replacing(body: selected, info: info), save: { [weak self] code in
                guard let self, let view = self.view, !self.source, self.lastMarkdown == baseline,
                      self.parent.documentID == document, self.parent.codeBlocksEnabled, !self.parent.readOnly else { return false }
                let original = view.attributedText!
                let text = original.string as NSString
                let before = text.substring(to: selection.location), after = text.substring(from: NSMaxRange(selection))
                let attributes: [NSAttributedString.Key: Any] = [.font: MarkdownText.font(), .zerusBlock: "", .foregroundColor: NativeThemeUIKit.text, .paragraphStyle: MarkdownText.paragraphStyle(prefix: "")]
                let leading = before.isEmpty || before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
                let trailing = after.hasPrefix("\n\n") ? "" : after.hasPrefix("\n") ? "\n" : "\n\n"
                let insertion = NSMutableAttributedString(string: leading, attributes: attributes)
                insertion.append(MarkdownText.codeToken(code, width: max(140, view.bounds.width - 44)))
                insertion.append(NSAttributedString(string: trailing, attributes: attributes))
                let changed = NSMutableAttributedString(attributedString: original)
                changed.replaceCharacters(in: selection, with: insertion)
                self.apply(changed, selection: NSRange(location: selection.location + insertion.length, length: 0), inverse: original)
                view.typingAttributes = attributes
                return true
            }))
        }
        func insertTable(pasted: String? = nil) {
            guard let view else { return }
            let baseline = lastMarkdown, selection = view.selectedRange
            let selected = source ? (view.text as NSString).substring(with: selection) : MarkdownText.serialize(view.attributedText.attributedSubstring(from: selection))
            var table = MarkdownTable.spreadsheet(pasted ?? selected) ?? MarkdownTable.empty()
            if pasted == nil && !selected.isEmpty && !selected.contains("\t") { table.rows[1][0] = selected.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") }
            let wasSource = source
            view.resignFirstResponder()
            parent.onTable(TableEditRequest(table: table, save: { [weak self] table in
                guard let self, let view = self.view, self.source == wasSource, self.lastMarkdown == baseline else { return false }
                let original = view.attributedText!
                let text = original.string as NSString
                let before = text.substring(to: selection.location), after = text.substring(from: NSMaxRange(selection))
                let attributes: [NSAttributedString.Key: Any] = [.font: MarkdownText.font(), .zerusBlock: "", .foregroundColor: NativeThemeUIKit.text, .paragraphStyle: MarkdownText.paragraphStyle(prefix: "")]
                let leading = before.isEmpty || before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
                let trailing = after.hasPrefix("\n\n") ? "" : after.hasPrefix("\n") ? "\n" : "\n\n"
                let insertion = NSMutableAttributedString(string: leading, attributes: attributes)
                insertion.append(wasSource ? NSAttributedString(string: table.markdown, attributes: attributes) : MarkdownText.tableToken(table, width: max(140, view.bounds.width - 44), images: self.parent.images))
                insertion.append(NSAttributedString(string: trailing, attributes: attributes))
                let changed = NSMutableAttributedString(attributedString: original)
                changed.replaceCharacters(in: selection, with: insertion)
                self.apply(changed, selection: NSRange(location: selection.location + insertion.length, length: 0), inverse: original)
                view.typingAttributes = attributes
                return true
            }))
        }
        func wrap(_ marker: String) {
            guard let view, let range = view.selectedTextRange else { return }
            let selected = view.text(in: range) ?? ""
            view.replace(range, withText: marker + selected + marker); textViewDidChange(view)
        }
        func block(_ prefix: String) {
            guard let view else { return }
            if source { view.insertText(prefix); textViewDidChange(view); return }
            let text = view.attributedText.string as NSString
            let selection = view.selectedRange
            let range = text.paragraphRange(for: selection)
            if range.length == 0 {
                if MarkdownText.isChecklist(prefix) {
                    let old = view.attributedText!
                    let changed = NSMutableAttributedString(attributedString: old)
                    let marker = MarkdownText.checkbox(prefix: prefix)
                    changed.insert(marker, at: selection.location)
                    apply(changed, selection: NSRange(location: selection.location + marker.length, length: 0), inverse: old)
                }
                view.typingAttributes[.zerusBlock] = prefix; view.typingAttributes[.font] = MarkdownText.font(prefix: prefix); view.typingAttributes[.paragraphStyle] = MarkdownText.paragraphStyle(prefix: prefix)
                view.typingAttributes.removeValue(forKey: .zerusDecoration)
                view.typingAttributes.removeValue(forKey: .attachment)
                view.typingAttributes.removeValue(forKey: .link)
                return
            }
            let old = view.attributedText!
            let changed = NSMutableAttributedString(attributedString: old)
            var paragraphs: [NSRange] = [], cursor = range.location
            while cursor < NSMaxRange(range) {
                let paragraph = text.paragraphRange(for: NSRange(location: cursor, length: 0))
                paragraphs.append(paragraph); cursor = NSMaxRange(paragraph)
            }
            var selected = selection
            func adjust(_ edit: NSRange, replacement: Int) {
                func mapped(_ position: Int) -> Int {
                    if position < edit.location { return position }
                    if position >= NSMaxRange(edit) { return position + replacement - edit.length }
                    return edit.location + replacement
                }
                let end = mapped(NSMaxRange(selected)), start = mapped(selected.location)
                selected = NSRange(location: start, length: max(0, end - start))
            }
            for paragraph in paragraphs.reversed() {
                if changed.attribute(.zerusRichBlockMarkdown, at: paragraph.location, effectiveRange: nil) != nil { continue }
                let current = changed.attribute(.zerusBlock, at: paragraph.location, effectiveRange: nil) as? String ?? ""
                let indent = String(current.prefix(while: { $0 == " " || $0 == "\t" }))
                let desired = prefix == "> " || prefix.hasPrefix("#") ? prefix : indent + prefix
                let target = current == desired ? "" : desired
                var editable = paragraph
                if MarkdownText.isChecklist(current) {
                    var marker = NSRange()
                    if changed.attribute(.zerusDecoration, at: paragraph.location, effectiveRange: &marker) as? Bool == true {
                        changed.deleteCharacters(in: marker); editable.length -= marker.length
                        adjust(marker, replacement: 0)
                    }
                }
                changed.addAttributes([.zerusBlock: target, .paragraphStyle: MarkdownText.paragraphStyle(prefix: target)], range: editable)
                if current.hasPrefix("#") || target.hasPrefix("#") { changed.addAttribute(.font, value: MarkdownText.font(prefix: target), range: editable) }
                if MarkdownText.isChecklist(target) {
                    let label = (changed.string as NSString).substring(with: editable).trimmingCharacters(in: .whitespacesAndNewlines)
                    let checkbox = MarkdownText.checkbox(prefix: target, label: label)
                    changed.insert(checkbox, at: editable.location)
                    adjust(NSRange(location: editable.location, length: 0), replacement: checkbox.length)
                }
            }
            apply(changed, selection: selected, inverse: old)
        }
        func apply(_ value: NSAttributedString, selection: NSRange, inverse: NSAttributedString) {
            guard let view else { return }
            let previousSelection = view.selectedRange
            view.undoManager?.registerUndo(withTarget: self) { owner in owner.apply(inverse, selection: previousSelection, inverse: value) }
            view.attributedText = source ? value : MarkdownText.adaptingFonts(value, to: view.traitCollection)
            if !source { MarkdownText.refreshImageAttachments(in: view, images: parent.images) }
            let location = min(selection.location, value.length)
            view.selectedRange = NSRange(location: location, length: min(selection.length, value.length - location))
            textViewDidChange(view)
        }
    }
}
