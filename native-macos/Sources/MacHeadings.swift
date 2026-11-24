import Foundation
import SwiftUI
import Markdown

struct MacHeading: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let level: Int
    let range: NSRange
}
struct MacHeadingRequest: Equatable {
    let id = UUID()
    let fragment: String
    let path: String
}
enum MacHeadings {
    static func localFragment(_ url: URL) -> String? {
        guard url.scheme == nil, url.relativeString.hasPrefix("#"), NoteReference(url: url) == nil else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
    }
    static func entries(_ source: String) -> [MacHeading] {
        let rows = MacMarkdownLines(source).lines
        func offset(_ location: SourceLocation) -> Int? {
            guard rows.indices.contains(location.line - 1), location.column > 0 else { return nil }
            let row = rows[location.line - 1], column = location.column - 1
            let bytes = Array((row.text + row.ending).utf8)
            guard column <= bytes.count, let prefix = String(bytes: bytes.prefix(column), encoding: .utf8) else { return nil }
            return row.offset + prefix.utf16.count
        }
        func collect(_ document: any Markup) -> [Heading] {
            var result: [Heading] = []
            func walk(_ node: any Markup) {
                if let heading = node as? Heading { result.append(heading) }
                for child in node.children { walk(child) }
            }
            walk(document); return result
        }
        let headings = collect(Document(parsing: source))
        // Use the same inline-reference conversion as the editor while keeping
        // original source ranges. Code spans and formatting retain their roles.
        let display = headings.contains { $0.plainText.contains("[[") }
            ? collect(Document(parsing: NoteReference.inlineMarkdown(source))) : headings
        func visibleText(_ node: any Markup) -> String {
            // Swift Markdown's InlineCode.plainText retains source backticks.
            // The editor displays the code contents without those delimiters.
            if let code = node as? InlineCode { return code.code }
            if node.childCount == 0 { return (node as? any InlineMarkup)?.plainText ?? "" }
            return node.children.map { visibleText($0) }.joined()
        }
        let text = source as NSString
        var used = Set<String>()
        return headings.enumerated().compactMap { index, heading in
            guard let range = heading.range,
                  let start = offset(range.lowerBound), let limit = offset(range.upperBound), limit >= start else { return nil }
            var end = limit
            while end > start, [10, 13].contains(Int(text.character(at: end - 1))) { end -= 1 }
            let title = visibleText(display.count == headings.count ? display[index] : heading).trimmingCharacters(in: .whitespacesAndNewlines)
            let base = slug(title), root = base.isEmpty ? "section" : base
            var id = root, suffix = 0
            while used.contains(id) { suffix += 1; id = root + "-" + String(suffix) }
            used.insert(id)
            return MacHeading(id: id, title: title, level: heading.level, range: NSRange(location: start, length: end - start))
        }
    }
    static func slug(_ title: String) -> String {
        let allowed = CharacterSet.letters.union(.decimalDigits).union(.nonBaseCharacters).union(CharacterSet(charactersIn: "_-"))
        let normalized = title.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let words = normalized.split(whereSeparator: \.isWhitespace).map { word in
            word.reduce(into: "") { result, character in
                guard character.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "_" || $0 == "-" }) else { return }
                result += String(String.UnicodeScalarView(character.unicodeScalars.filter { allowed.contains($0) && !(0xFE00...0xFE0F).contains($0.value) && !(0xE0100...0xE01EF).contains($0.value) }))
            }
        }
        return words.filter { !$0.isEmpty }.joined(separator: "-")
    }
    static func target(_ fragment: String, in source: String) -> MacHeading? {
        target(fragment, in: entries(source))
    }
    static func target(_ fragment: String, in headings: [MacHeading]) -> MacHeading? {
        let query = fragment.precomposedStringWithCanonicalMapping
        return headings.first { $0.id == query.lowercased(with: Locale(identifier: "en_US_POSIX")) }
            ?? headings.first { $0.title.precomposedStringWithCanonicalMapping.compare(query, options: [.caseInsensitive]) == .orderedSame }
    }
}

/// Outline presentation may lag a typing burst; clicks resolve the fragment
/// against the current draft instead of using a background snapshot's range.
@MainActor struct MacOutlineView: View {
    @ObservedObject var draft: MacNoteDraftState
    let onSelect: (String) -> Void
    private static let queue = DispatchQueue(label: "com.zerus.notes.outline", qos: .userInitiated)
    @StateObject private var state = MacMarkdownSnapshotState<[MacHeading]>(queue: queue, compute: { MacHeadings.entries($0) })
    var body: some View {
        Group {
            if let headings = state.value {
                ForEach(headings) { heading in
                    let title = heading.title.isEmpty ? "Untitled heading" : heading.title
                    let detail = "Heading level " + String(heading.level) + ", " + heading.id
                    Button { onSelect(heading.id) } label: {
                        SwiftUI.Text(title).font(.body).padding(.leading, CGFloat(max(0, heading.level - 1)) * 10)
                    }.buttonStyle(MacBoxButtonStyle()).help("Jump to " + title)
                        .accessibilityLabel("Jump to " + title).accessibilityValue(detail)
                        .accessibilityIdentifier("note.heading." + heading.id)
                }
            } else { ProgressView().controlSize(.mini).accessibilityLabel("Updating outline") }
        }
        .onChange(of: draft.body, initial: true) { _, value in state.request(value) }
        .onDisappear { state.cancel() }
    }
}
