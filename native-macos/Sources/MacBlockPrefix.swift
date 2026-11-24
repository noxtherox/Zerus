import AppKit

/// The portable source prefix and its native presentation are kept separately.
/// Quotes can inherit indentation from an outer list item. The Markdown tree,
/// not this spelling parser, decides whether a source line is code or a quote.
struct MacBlockPrefix {
    private static let markerPattern = #"([ \t]*)(#{1,6} |(?:[-*+]|\d{1,9}[.)])[ \t]+\[[ xX]\][ \t]+|[-*+][ \t]+|\d{1,9}[.)][ \t]+)?"#
    private static let pattern = try! NSRegularExpression(pattern: #"^((?:[ \t]*> ?)*)"# + markerPattern)
    private static let typedPattern = try! NSRegularExpression(pattern: #"^((?: {0,3}> ?)*)"# + markerPattern)
    let quotes: String
    let indentation: String
    let marker: String
    var source: String { quotes + indentation + marker }
    init?(_ text: String, inheritedQuoteIndentation: Bool = true) {
        // Root prose has no prefix. The regular expression can only return nil
        // for this common case, so avoid creating its match and substrings.
        guard !text.isEmpty else { return nil }
        // Every ASCII prefix starts with layout whitespace, a quote, heading
        // or list marker. Unicode stays on the regex path (including digits).
        if let first = text.utf8.first, first < 128 {
            switch first {
            case 9, 32, 35, 42, 43, 45, 48...57, 62: break
            default: return nil
            }
        }
        let raw = text as NSString
        let expression = inheritedQuoteIndentation ? Self.pattern : Self.typedPattern
        guard let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: raw.length)) else { return nil }
        quotes = raw.substring(with: match.range(at: 1)); indentation = raw.substring(with: match.range(at: 2))
        marker = match.range(at: 3).location == NSNotFound ? "" : raw.substring(with: match.range(at: 3))
        guard !quotes.isEmpty || !marker.isEmpty else { return nil }
    }
    var depth: Int { quotes.filter { $0 == ">" }.count }
    var indent: Int { indentation.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }
    var heading: Bool { marker.hasPrefix("#") }
    var list: Bool { marker.first.map { "-*+".contains($0) || $0.isNumber } ?? false }
    var checklist: Bool { marker.contains("[ ]") || marker.contains("[x]") || marker.contains("[X]") }
    var display: String {
        guard list else { return "" }
        if checklist {
            let number = marker.first?.isNumber == true ? String(marker.prefix(while: { $0 != "[" })) : ""
            return number + (marker.contains("[ ]") ? "☐ " : "☑ ")
        }
        return marker.first?.isNumber == true ? marker : "• "
    }
    var listPadding: Int {
        let raw = marker as NSString
        return marker.range(of: #"^(?:[-*+]|\d+[.)])[ \t]+"#, options: .regularExpression).map { raw.substring(with: NSRange($0, in: marker)).utf16.count } ?? 2
    }
    private var separatedQuotes: String { quotes.hasSuffix(">") ? quotes + " " : quotes }
    var listContinuation: String { separatedQuotes + indentation + String(repeating: " ", count: listPadding) }
    func replacingMarker(_ value: String) -> String { quotes + indentation + value }
    func indented(_ width: Int) -> String { (width > 0 ? separatedQuotes : quotes) + String(repeating: " ", count: max(0, width)) + marker }
    /// Move the whitespace at an ancestor's quote depth, rather than after
    /// every quote in a descendant's prefix.
    func shiftingIndentation(by delta: Int, atQuoteDepth level: Int) -> String {
        guard delta != 0, level <= depth else { return source }
        if level == depth { return indented(indent + delta) }
        var start = quotes.startIndex
        for _ in 0..<level {
            guard let quote = quotes[start...].firstIndex(of: ">") else { return source }
            start = quotes.index(after: quote)
            if start < quotes.endIndex, quotes[start] == " " { start = quotes.index(after: start) }
        }
        guard let end = quotes[start...].firstIndex(of: ">") else { return source }
        let width = quotes[start..<end].reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        return String(quotes[..<start]) + String(repeating: " ", count: max(0, width + delta)) + String(quotes[end...]) + indentation + marker
    }
    var next: String {
        if heading { return quotes }
        let continued = checklist ? marker.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]") : marker
        let digits = continued.prefix(while: \.isNumber)
        if let number = Int(digits), number < 999_999_999 { return replacingMarker(String(number + 1) + continued.dropFirst(digits.count)) }
        return replacingMarker(continued)
    }
    var leavingEmpty: String {
        if list { return indent > 0 ? indented(max(0, indent - 2)) : quotes }
        guard let last = quotes.lastIndex(of: ">") else { return "" }
        return String(quotes[..<last])
    }
    var toggledChecklist: String { replacingMarker(marker.contains("[ ]") ? marker.replacingOccurrences(of: "[ ]", with: "[x]") : marker.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")) }
    var style: NSParagraphStyle {
        let style = NSMutableParagraphStyle(); style.paragraphSpacing = heading ? 12 : 7; style.lineSpacing = 5
        let offset = CGFloat(depth * 18 + indent * 9)
        style.firstLineHeadIndent = offset; style.headIndent = offset + (list ? CGFloat(max(20, display.utf16.count * 8)) : 0)
        return style
    }
}
