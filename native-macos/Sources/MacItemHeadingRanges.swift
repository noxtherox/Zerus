import Foundation
import Markdown

/// Resolve canonical heading source, including cmark's omitted ranges for
/// bare empty ATX headings. In-flight rows retain their own native contexts;
/// file import follows the parser rather than inferring unfinished edits.
struct MacItemHeadingRanges {
    typealias Span = (start: Int, end: Int)
    private let lines: [String]
    private var empty: [[Int]: [Int: Span]] = [:]
    init(lines: [String]) { self.lines = lines }

    mutating func range(for heading: Heading) -> Span? {
        guard let range = heading.range else {
            guard heading.childCount == 0, let parent = heading.parent else { return nil }
            var path: [Int] = [], ancestor: (any Markup)? = parent
            while let node = ancestor, node.parent != nil { path.append(node.indexInParent); ancestor = node.parent }
            if empty[path] == nil { empty[path] = emptyRanges(in: parent) }
            return empty[path]?[heading.indexInParent]
        }
        let start = range.lowerBound.line - 1
        guard lines.indices.contains(start) else { return nil }
        let content = String(decoding: lines[start].utf8.dropFirst(range.lowerBound.column - 1), as: UTF8.self)
        let atx = content.range(of: #"^#{1,6}(?:[ \t]|$)"#, options: .regularExpression) != nil
        let end = atx ? range.upperBound.line : heading.children.compactMap { $0.range?.upperBound.line }.last.map { $0 + 1 } ?? range.upperBound.line
        guard end > start, end <= lines.count else { return nil }
        return (start, end)
    }

    private mutating func emptyRanges(in parent: any Markup) -> [Int: Span] {
        guard let span = parent.range else { return [:] }
        let children = Array(parent.children), upper = min(lines.count, span.upperBound.line)
        var cursor = max(0, span.lowerBound.line - 1), next = upper
        var limits = Array(repeating: upper, count: children.count)
        for index in children.indices.reversed() {
            limits[index] = next
            if let range = children[index].range { next = max(0, range.lowerBound.line - 1) }
        }
        var result: [Int: Span] = [:]
        for (index, child) in children.enumerated() {
            if let heading = child as? Heading, heading.range == nil {
                let limit = min(upper, limits[index])
                while cursor < limit {
                    let line = cursor; cursor += 1
                    if emptyLevel(lines[line]) == heading.level { result[index] = (line, line + 1); break }
                }
            } else if let span = child.range {
                let end = (child as? Heading).flatMap { range(for: $0)?.end } ?? span.upperBound.line
                cursor = max(cursor, end)
            }
        }
        return result
    }

    private func emptyLevel(_ source: String) -> Int? {
        var text = source.trimmingCharacters(in: .whitespaces)
        while !text.isEmpty {
            let hashes = text.prefix { $0 == "#" }
            if (1...6).contains(hashes.count), text.dropFirst(hashes.count).allSatisfy(\.isWhitespace) { return hashes.count }
            guard let prefix = MacBlockPrefix(text), !prefix.source.isEmpty, !prefix.heading else { return nil }
            text = String(text.dropFirst(prefix.source.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
