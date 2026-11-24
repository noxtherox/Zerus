import Foundation
import Markdown

enum MacAgentTextFallback {
    struct Parsed { let reply: MacAgentCompletion; let source: String? }
    private static let names = ["zerus_tool", "note_get", "note_list", "search", "note_append", "note_set_body"]
    private static let pattern = try! NSRegularExpression(pattern: #"^ {0,3}<(zerus_tool|note_get|note_list|search|note_append|note_set_body)>(.*?)</\1>"#, options: [.anchorsMatchLines, .caseInsensitive, .dotMatchesLineSeparators])
    private static let marker = try! NSRegularExpression(pattern: #"</?(zerus_tool|note_get|note_list|search|note_append|note_set_body)(?=>|\s|$)"#, options: [.caseInsensitive])
    private static let opening = try! NSRegularExpression(pattern: #"^ {0,3}<(zerus_tool|note_get|note_list|search|note_append|note_set_body)(?=>|\s|$)"#, options: [.anchorsMatchLines, .caseInsensitive])
    private struct LiteralRanges {
        let ranges: [NSRange]
        init(_ text: String) {
            var byteToUnit = [Int](repeating: 0, count: text.utf8.count + 1), starts = [0], byte = 0, unit = 0, wasCR = false
            for scalar in text.unicodeScalars {
                for _ in scalar.utf8 { byteToUnit[byte] = unit; byte += 1 }
                unit += scalar.utf16.count
                if scalar.value == 13 { starts.append(byte); wasCR = true }
                else if scalar.value == 10 { if wasCR { starts[starts.count - 1] = byte } else { starts.append(byte) }; wasCR = false }
                else { wasCR = false }
            }
            byteToUnit[byte] = unit
            func offset(_ location: SourceLocation) -> Int? {
                guard location.line > 0, location.line <= starts.count, location.column > 0 else { return nil }
                let position = starts[location.line - 1] + location.column - 1
                return position <= byte ? byteToUnit[position] : nil
            }
            var found: [NSRange] = [], stack: [Markup] = [Document(parsing: text)]
            while let node = stack.popLast() {
                if node is CodeBlock || node is InlineCode {
                    if let range = node.range, let a = offset(range.lowerBound), let b = offset(range.upperBound), b > a { found.append(NSRange(location: a, length: b - a)) }
                } else { stack.append(contentsOf: node.children) }
            }
            ranges = found.sorted { $0.location < $1.location }
        }
        func contains(_ location: Int) -> Bool {
            var low = 0, high = ranges.count
            while low < high { let mid = (low + high) / 2; if ranges[mid].location <= location { low = mid + 1 } else { high = mid } }
            return low > 0 && location < NSMaxRange(ranges[low - 1])
        }
    }
    static func visible(_ text: String) -> String {
        let string = text as NSString, all = NSRange(location: 0, length: string.length)
        let candidates = opening.matches(in: text, range: all)
        let newline = string.range(of: "\n", options: .backwards)
        let lastStart = newline.location == NSNotFound ? 0 : NSMaxRange(newline)
        let line = string.substring(from: lastStart), spaces = line.prefix(while: { $0 == " " }).count
        let tail = String(line.dropFirst(spaces)).lowercased()
        let partial = spaces <= 3 && tail.hasPrefix("<") && names.contains { ("<" + $0).hasPrefix(tail) }
        guard !candidates.isEmpty || partial else { return text }
        let literal = LiteralRanges(text)
        if let match = candidates.first(where: { !literal.contains($0.range.location) }) { return string.substring(to: match.range.location) }
        if partial, !literal.contains(lastStart + spaces) { return string.substring(to: lastStart) }
        return text
    }
    static func parse(_ reply: MacAgentCompletion, run: NativeAgentRun) throws -> Parsed {
        guard run.preferences?.textFallback == true else { return .init(reply: reply, source: nil) }
        let raw = reply.content, text = raw as NSString
        let failure = VaultFailure(message: "The model returned a malformed or ambiguous text tool call. No call from this reply was executed; its response is kept in the run journal.")
        guard reply.calls.isEmpty else { throw failure }
        let literal = LiteralRanges(raw), all = NSRange(location: 0, length: text.length)
        let matches = pattern.matches(in: raw, range: all).filter { !literal.contains($0.range.location) }
        let markers = marker.matches(in: raw, range: all).filter { !literal.contains($0.range.location) }
        if matches.isEmpty {
            guard markers.isEmpty else { throw failure }
            return .init(reply: reply, source: nil)
        }
        guard matches.count == 1, let match = matches.first,
              !markers.contains(where: { $0.range.location < match.range.location }),
              text.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure }
        let tag = text.substring(with: match.range(at: 1)).lowercased(), value = text.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        var name = tag, arguments: [String: Any]
        if tag == "zerus_tool" {
            guard let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                  Set(object.keys).isSubset(of: ["name", "arguments"]), let declared = object["name"] as? String,
                  object["arguments"] == nil || object["arguments"] is [String: Any] else { throw failure }
            name = declared; arguments = object["arguments"] as? [String: Any] ?? [:]
        } else {
            guard value.utf16.count <= 100_000 else { throw failure }
            switch tag {
            case "note_get": arguments = ["selector": value.isEmpty ? "current" : value]
            case "note_list": let number = Double(value); arguments = ["limit": number.map { $0.isFinite ? Int(max(1, min(50, $0.rounded(.down)))) : 20 } ?? 20]
            case "search": guard !value.isEmpty else { throw failure }; arguments = ["query": value, "limit": 10]
            case "note_append", "note_set_body":
                guard !value.isEmpty, let current = run.currentTargetID,
                      let read = run.reads.first(where: { $0.id == current }) else { throw VaultFailure(message: "The text tool must read the current note before proposing an edit. No call from this reply was executed.") }
                arguments = ["selector": current, "revision": read.revision, tag == "note_append" ? "text" : "body": value]
            default: throw failure
            }
        }
        let call = NativeAgentCall(id: "text-" + UUID().uuidString.lowercased(), name: name, arguments: String(decoding: try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self))
        var usage: [String: Any] = [:]
        if let input = reply.inputTokens { usage["inputTokens"] = input }; if let output = reply.outputTokens { usage["outputTokens"] = output }
        let object: [String: Any] = ["content": text.substring(to: match.range.location).trimmingCharacters(in: .whitespacesAndNewlines), "reasoning": reply.reasoning, "toolCalls": try JSONSerialization.jsonObject(with: JSONEncoder().encode([call])), "usage": usage]
        let parsed = try MacAgentCompletion(json: String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        return .init(reply: parsed, source: raw)
    }
}
