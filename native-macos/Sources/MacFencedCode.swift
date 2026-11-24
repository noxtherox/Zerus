import Foundation
struct FencedCode {
    let markdown: String
    let body: String
    let info: String
    let opening: String
    let fence: String
    let newline: String
    var closed = true

    struct Located {
        let range: NSRange
        let code: FencedCode
    }

    static func blocks(in source: String) -> [Located] {
        let text = source as NSString
        // A fence needs at least three identical literal markers; retain the
        // full line parser for every candidate, including unmatched fences.
        guard text.range(of: "```", options: .literal).location != NSNotFound ||
              text.range(of: "~~~", options: .literal).location != NSNotFound else { return [] }
        let sourceLines = MacMarkdownLines(source)
        let lines = sourceLines.lines.map { ($0.range, $0.text) }
        var output: [Located] = [], index = 0
        while index < lines.count {
            let (start, line) = lines[index]
            guard let match = line.range(of: #"^ {0,3}(`{3,}|~{3,})"#, options: .regularExpression) else { index += 1; continue }
            let opening = String(line[match])
            let fence = opening.trimmingCharacters(in: .whitespaces)
            let info = String(line[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            if fence.first == "`" && info.contains("`") { index += 1; continue }
            let marker = fence.first!
            var closing = index + 1
            while closing < lines.count {
                let candidate = lines[closing].1
                let indentation = candidate.prefix(while: { $0 == " " }).count
                let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                if indentation <= 3 && trimmed.count >= fence.count && trimmed.allSatisfy({ $0 == marker }) { break }
                closing += 1
            }
            let closed = closing < lines.count
            let end = closed ? lines[closing].0.location + (lines[closing].1 as NSString).length : text.length
            let bodyStart = NSMaxRange(start)
            var body = text.substring(with: NSRange(location: min(bodyStart, end), length: max(0, (closed ? lines[closing].0.location : end) - bodyStart)))
            if body.hasSuffix("\r\n") { body.removeLast() }
            else if body.hasSuffix("\n") || body.hasSuffix("\r") { body.removeLast() }
            let range = NSRange(location: start.location, length: end - start.location)
            output.append(Located(range: range, code: FencedCode(markdown: text.substring(with: range), body: body, info: info, opening: line, fence: fence, newline: sourceLines.ending(at: index), closed: closed)))
            index = closed ? closing + 1 : lines.count
        }
        return output
    }

    func replacing(body: String, info: String, closing: Bool = false) -> FencedCode {
        if body == self.body && info == self.info && (!closing || closed) { return self }
        // Native input uses LF for inserted rows. Uniform source bodies retain
        // their convention; existing mixed bodies keep their individual bytes.
        let uniform = MacMarkdownLines(self.body).lines.allSatisfy { $0.ending.isEmpty || $0.ending == newline }
        let body = uniform ? MacMarkdownLines.normalized(body, to: newline) : body
        let info = info.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        let marker: Character = info.contains("`") ? "~" : fence.first!
        let longest = body.components(separatedBy: .newlines).map { line in
            line.trimmingCharacters(in: .whitespaces).prefix(while: { $0 == marker }).count
        }.max() ?? 0
        let delimiter = String(repeating: String(marker), count: max(fence.count, max(longest + 1, 3)))
        let indent = String(opening.prefix(while: { $0 == " " }))
        let first = delimiter == fence && info == self.info ? opening : indent + delimiter + info
        let raw = first + newline + body + (body.isEmpty ? "" : newline) + indent + delimiter
        return FencedCode.blocks(in: raw).first!.code
    }

    var language: String { info.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "Plain text" }
}
