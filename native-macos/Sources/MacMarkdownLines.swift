import Foundation

/// CommonMark source rows use CR, LF or CRLF. Native paragraph separators stay
/// LF; each row retains its own source terminator and UTF-16 position.
struct MacMarkdownLines {
    struct Line {
        let offset: Int
        let text: String
        let ending: String
        var range: NSRange { NSRange(location: offset, length: text.utf16.count + ending.utf16.count) }
    }
    private let source: NSString
    let lines: [Line]
    var contents: [String] { lines.map(\.text) }
    init(_ value: String) {
        let source = value as NSString
        self.source = source
        // Scan contiguous UTF-16 once. Repeated NSString character lookups on a
        // bridged non-ASCII Swift string otherwise keep translating its indices.
        let units = Array(value.utf16)
        var rows: [Line] = [], start = 0, cursor = 0
        while cursor < units.count {
            let character = units[cursor]
            guard character == 10 || character == 13 else { cursor += 1; continue }
            let length = character == 13 && cursor + 1 < units.count && units[cursor + 1] == 10 ? 2 : 1
            rows.append(Line(offset: start, text: String(decoding: units[start..<cursor], as: UTF16.self), ending: length == 2 ? "\r\n" : character == 13 ? "\r" : "\n"))
            cursor += length; start = cursor
        }
        rows.append(Line(offset: start, text: String(decoding: units[start...], as: UTF16.self), ending: ""))
        lines = rows
    }
    func fragment(_ rows: Range<Int>, includeLastEnding: Bool = true) -> String {
        guard !rows.isEmpty else { return "" }
        let first = lines[rows.lowerBound], last = lines[rows.upperBound - 1]
        let end = last.offset + last.text.utf16.count + (includeLastEnding ? last.ending.utf16.count : 0)
        return source.substring(with: NSRange(location: first.offset, length: end - first.offset))
    }
    func ending(at index: Int) -> String {
        if !lines[index].ending.isEmpty { return lines[index].ending }
        return lines[..<index].last(where: { !$0.ending.isEmpty })?.ending ?? "\n"
    }
    static func leadingEnding(_ value: String) -> String {
        if value.hasPrefix("\r\n") { return "\r\n" }
        if value.hasPrefix("\r") { return "\r" }
        return value.hasPrefix("\n") ? "\n" : ""
    }
    static func normalized(_ value: String, to ending: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: ending)
    }
}
