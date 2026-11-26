import SwiftUI

enum MacHistoryDifference {
    enum Kind: Sendable { case same, added, removed }
    struct Line: Identifiable, Sendable {
        let id: Int
        let kind: Kind
        let text: String
        let before: Int?
        let after: Int?
    }
    struct Report: Sendable {
        let lines: [Line]
        let coarse: Bool
        var added: Int { lines.filter { $0.kind == .added }.count }
        var removed: Int { lines.filter { $0.kind == .removed }.count }
    }
    struct Highlight: Equatable { let prefix: String; let changed: String; let suffix: String }
    static func highlight(_ text: String, comparedWith other: String) -> Highlight {
        var start = text.startIndex, otherStart = other.startIndex
        while start < text.endIndex, otherStart < other.endIndex, text[start] == other[otherStart] { text.formIndex(after: &start); other.formIndex(after: &otherStart) }
        var end = text.endIndex, otherEnd = other.endIndex
        while end > start, otherEnd > otherStart {
            let left = text.index(before: end), right = other.index(before: otherEnd)
            guard text[left] == other[right] else { break }; end = left; otherEnd = right
        }
        return .init(prefix: String(text[..<start]), changed: String(text[start..<end]), suffix: String(text[end...]))
    }
    static func compare(before: String, after: String) throws -> Report {
        let left = before.isEmpty ? [] : before.components(separatedBy: "\n"), right = after.isEmpty ? [] : after.components(separatedBy: "\n")
        var prefix = 0, suffix = 0
        while prefix < min(left.count, right.count), left[prefix] == right[prefix] { try Task.checkCancellation(); prefix += 1 }
        while suffix < min(left.count, right.count) - prefix, left[left.count - suffix - 1] == right[right.count - suffix - 1] { try Task.checkCancellation(); suffix += 1 }
        let n = left.count - prefix - suffix, m = right.count - prefix - suffix
        var result: [Line] = [], i = 0, j = 0
        func append(_ kind: Kind) {
            let text = kind == .added ? right[j] : left[i]
            result.append(.init(id: result.count, kind: kind, text: text, before: kind == .added ? nil : i + 1, after: kind == .removed ? nil : j + 1))
            if kind != .added { i += 1 }; if kind != .removed { j += 1 }
        }
        for _ in 0..<prefix { append(.same) }
        // Bound quadratic work to a small changed section, preserving common
        // prefixes/suffixes even for very large notes with a localized edit.
        let coarse = n > 0 && m > 120_000 / n
        if n == 0 || m == 0 || coarse {
            for _ in 0..<n { try Task.checkCancellation(); append(.removed) }
            for _ in 0..<m { try Task.checkCancellation(); append(.added) }
        } else {
            let width = m + 1
            var table = [Int32](repeating: 0, count: (n + 1) * width)
            for a in stride(from: n - 1, through: 0, by: -1) {
                try Task.checkCancellation()
                for b in stride(from: m - 1, through: 0, by: -1) {
                    table[a * width + b] = left[prefix + a] == right[prefix + b] ? table[(a + 1) * width + b + 1] + 1 : max(table[(a + 1) * width + b], table[a * width + b + 1])
                }
            }
            var a = 0, b = 0
            while a < n || b < m {
                try Task.checkCancellation()
                if a < n, b < m, left[i] == right[j] { append(.same); a += 1; b += 1 }
                else if b < m, a == n || table[a * width + b + 1] >= table[(a + 1) * width + b] { append(.added); b += 1 }
                else { append(.removed); a += 1 }
            }
        }
        for _ in 0..<suffix { append(.same) }
        return .init(lines: result, coarse: coarse)
    }
}

struct MacHistoryDifferenceView: View {
    let before: String
    let after: String
    @State private var report: MacHistoryDifference.Report?
    @State private var issue: String?
    private struct Input: Equatable { let before: String; let after: String }
    var body: some View {
        Group {
            if let report {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(report.added) added · \(report.removed) removed").macFont(.caption).foregroundStyle(.secondary)
                    if report.coarse { Text("Large changed section shown as removed and added blocks.").macFont(.caption).foregroundStyle(.secondary) }
                    ScrollView { LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(report.lines) { line in row(line, report: report) }
                    }.frame(maxWidth: .infinity, alignment: .leading) }
                }
            } else if let issue { Text(issue).foregroundStyle(.red) }
            else { ProgressView("Comparing saved versions…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.task(id: Input(before: before, after: after)) {
            report = nil; issue = nil
            let original = before, result = after
            let worker = Task.detached(priority: .userInitiated) { try MacHistoryDifference.compare(before: original, after: result) }
            do {
                let next = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }; report = next
            } catch is CancellationError {} catch { issue = error.localizedDescription }
        }
    }
    private func row(_ line: MacHistoryDifference.Line, report: MacHistoryDifference.Report) -> some View {
        let neighbor = report.lines.indices.contains(line.id + 1) && report.lines[line.id + 1].kind != .same && report.lines[line.id + 1].kind != line.kind ? report.lines[line.id + 1] : line.id > 0 && report.lines[line.id - 1].kind != .same && report.lines[line.id - 1].kind != line.kind ? report.lines[line.id - 1] : nil
        let highlight = line.kind == .same ? nil : neighbor.map { MacHistoryDifference.highlight(line.text, comparedWith: $0.text) }
        let text: Text = highlight.map { Text($0.prefix) + Text($0.changed.isEmpty ? " " : $0.changed).bold().underline() + Text($0.suffix) } ?? Text(line.text.isEmpty ? " " : line.text)
        return HStack(alignment: .top, spacing: 8) {
            Text(line.before.map(String.init) ?? "").frame(width: 32, alignment: .trailing).foregroundStyle(.secondary)
            Text(line.after.map(String.init) ?? "").frame(width: 32, alignment: .trailing).foregroundStyle(.secondary)
            Text(line.kind == .added ? "+" : line.kind == .removed ? "−" : " ").frame(width: 12)
            text.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.macFont(.system(size: 12, design: .monospaced)).padding(.vertical, 4).padding(.horizontal, 8)
            .background(line.kind == .added ? Color.green.opacity(0.12) : line.kind == .removed ? Color.red.opacity(0.12) : .clear)
    }
}
