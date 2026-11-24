import Foundation
import Markdown

/// Top-level indented blocks share the native code editor, while retaining the
/// original token until edited. Container code still needs container ownership.
struct MacIndentedCode {
    let range: NSRange
    let code: FencedCode
    let indent: String

    static func blocks(in source: String, document: Document? = nil) -> [Self] {
        let sourceLines = MacMarkdownLines(source), lines = sourceLines.contents
        let offsets = sourceLines.lines.map(\.offset)
        return (document ?? Document(parsing: source)).children.compactMap { node in
            guard let block = node as? CodeBlock, let span = block.range else { return nil }
            let first = span.lowerBound.line - 1
            var last = span.upperBound.line - 1
            guard lines.indices.contains(first), lines.indices.contains(last), first <= last else { return nil }
            // cmark's source range may include trailing blank lines that are
            // not part of CodeBlock.code. Keep those as ordinary separators.
            while last > first && lines[last].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { last -= 1 }
            var columns = 0, indent = ""
            for character in lines[first] {
                guard columns < 4, character == " " || character == "\t" else { break }
                indent.append(character); columns = character == "\t" ? columns + 4 - columns % 4 : columns + 1
            }
            guard columns == 4 else { return nil }
            let raw = sourceLines.fragment(first..<(last + 1), includeLastEnding: false)
            let newline = sourceLines.ending(at: first)
            var body = block.code
            if body.hasSuffix("\n") { body.removeLast() }
            // The fence is used only if an edit needs an empty/blank-edged code
            // body that indented Markdown cannot represent without losing text.
            let code = FencedCode(markdown: raw, body: body, info: "", opening: "```", fence: "```", newline: newline)
            return .init(range: NSRange(location: offsets[first], length: raw.utf16.count), code: code, indent: indent)
        }
    }
    func markdown(body: String) -> String {
        if body == code.body { return code.markdown }
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces).isEmpty != false || lines.last?.trimmingCharacters(in: .whitespaces).isEmpty != false {
            return fenced(body: normalized)
        }
        return lines.map { indent + $0 }.joined(separator: code.newline)
    }
    func fenced(body: String) -> String {
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.replacingOccurrences(of: "\n", with: code.newline)
        let seed = FencedCode(markdown: "```" + code.newline + "```", body: "", info: "", opening: "```", fence: "```", newline: code.newline)
        return seed.replacing(body: lines, info: "").markdown
    }

}
