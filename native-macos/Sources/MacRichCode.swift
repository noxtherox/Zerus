import AppKit

extension NSAttributedString.Key {
    static let macCode = Self("ZerusMacCode")
    static let macCodeSeparator = Self("ZerusMacCodeSeparator")
    static let macCodePlaceholder = Self("ZerusMacCodePlaceholder")
}

/// An immutable token keeps fence spelling separate from the editable native text.
final class MacRichCode: NSObject {
    let original: FencedCode
    let ending: String
    let indented: MacIndentedCode?
    let quote: MacQuoteContext?
    init(_ code: FencedCode, ending: String, indented: MacIndentedCode? = nil, quote: MacQuoteContext? = nil) { original = code; self.ending = ending; self.indented = indented; self.quote = quote }
    func markdown(body: String) -> String {
        let inner = indented?.markdown(body: body) ?? original.replacing(body: body, info: original.info).markdown
        return quote?.spelling(inner) ?? inner
    }
    static func attributes(_ code: MacRichCode) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle(); style.headIndent = 14 + CGFloat((code.quote?.depth ?? 0) * 18); style.firstLineHeadIndent = style.headIndent
        style.paragraphSpacing = 4; style.lineSpacing = 3
        return [.macCode: code, .macBlock: code.quote?.prefix ?? "", .macStrong: false, .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
    }
    static func render(_ code: FencedCode, ending: String, indented: MacIndentedCode? = nil, quote: MacQuoteContext? = nil) -> NSAttributedString {
        let token = MacRichCode(code, ending: ending, indented: indented, quote: quote), attrs = attributes(token)
        let value = NSMutableAttributedString(string: code.body.isEmpty ? "\u{200b}" : code.body, attributes: attrs)
        if code.body.isEmpty { value.addAttribute(.macCodePlaceholder, value: true, range: NSRange(location: 0, length: 1)) }
        if value.length > 0 {
            let first = (value.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            let style = (attrs[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
            style.paragraphSpacingBefore = 24
            value.addAttribute(.paragraphStyle, value: style, range: first)
        }
        MacCodeHighlight.apply(value, range: NSRange(location: 0, length: value.length), language: code.language)
        var separator = attrs; separator[.macCodeSeparator] = true
        value.append(NSAttributedString(string: "\n", attributes: separator))
        return value
    }
    static func style(_ storage: NSTextStorage, only codes: Set<ObjectIdentifier>? = nil) {
        var spans: [(MacRichCode, NSRange)] = []
        storage.enumerateAttribute(.macCode, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let code = value as? MacRichCode, codes?.contains(ObjectIdentifier(code)) ?? true { spans.append((code, range)) }
        }
        storage.beginEditing(); defer { storage.endEditing() }
        for (code, range) in spans {
            MacCodeHighlight.apply(storage, range: range, language: code.original.language)
            let style = attributes(code)[.paragraphStyle] as! NSParagraphStyle
            storage.addAttribute(.paragraphStyle, value: style, range: range)
            let first = NSIntersectionRange((storage.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 0)), range)
            let header = style.mutableCopy() as! NSMutableParagraphStyle; header.paragraphSpacingBefore = 24
            storage.addAttribute(.paragraphStyle, value: header, range: first)
        }
        MacListCardPlacement.restyle(storage)
    }
    /// Code stores portable image markup as literal text, never attachment glyphs.
    static func literalBody(_ rich: NSAttributedString) -> String {
        let value = NSMutableAttributedString(attributedString: rich)
        rich.enumerateAttributes(in: NSRange(location: 0, length: rich.length), options: .reverse) { attrs, range, _ in
            if attrs[.attachment] != nil, let literal = attrs[.macLiteral] as? String {
                value.replaceCharacters(in: range, with: literal)
            }
        }
        return body(value).replacingOccurrences(of: "\u{2028}", with: "\n")
    }
    static func body(_ rich: NSAttributedString, in range: NSRange? = nil) -> String {
        let range = range ?? NSRange(location: 0, length: rich.length)
        let raw = rich.string as NSString
        // Only these two attributes contain editor-only characters. Read their
        // effective runs in the original storage rather than copying every
        // syntax-coloured run or looking up attributes for every character.
        var removed = IndexSet()
        for (key, character) in [(NSAttributedString.Key.macCodeSeparator, UInt16(10)), (.macCodePlaceholder, UInt16(0x200b))] {
            rich.enumerateAttribute(key, in: range) { value, span, _ in
                guard value != nil else { return }
                for index in span.location..<NSMaxRange(span) where raw.character(at: index) == character { removed.insert(index) }
            }
        }
        let value = NSMutableString(string: raw.substring(with: range))
        for index in removed.reversed() { value.deleteCharacters(in: NSRange(location: index - range.location, length: 1)) }
        return value as String
    }
    static func at(_ text: NSAttributedString, _ index: Int) -> MacRichCode? {
        guard index >= 0, index < text.length else { return nil }
        return text.attribute(.macCode, at: index, effectiveRange: nil) as? MacRichCode
    }
}
