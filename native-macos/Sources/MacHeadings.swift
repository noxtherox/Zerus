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
/// Indent guides, weight and colour carry the hierarchy; the editor reports
/// the heading at the top of its viewport, which the outline highlights.
@MainActor struct MacOutlineView: View {
    @ObservedObject var draft: MacNoteDraftState
    let onSelect: (String) -> Void
    private static let queue = DispatchQueue(label: "com.zerus.notes.outline", qos: .userInitiated)
    private static let maximumHeight: CGFloat = 320
    @StateObject private var state = MacMarkdownSnapshotState<[MacHeading]>(queue: queue, compute: { MacHeadings.entries($0) })
    @State private var contentHeight: CGFloat = 0
    var body: some View {
        Group {
            if let headings = state.value {
                if headings.isEmpty {
                    SwiftUI.Text("No headings in this note.").macFont(.system(size: 12)).foregroundStyle(.quaternary).padding(.horizontal, 6)
                } else { list(headings) }
            } else { ProgressView().controlSize(.mini).accessibilityLabel("Updating outline") }
        }
        .onChange(of: draft.body, initial: true) { _, value in state.request(value) }
        .onDisappear { state.cancel() }
    }
    private func list(_ headings: [MacHeading]) -> some View {
        let base = headings.map(\.level).min() ?? 1
        let current = draft.visibleHeading.flatMap { headings.indices.contains($0) ? $0 : nil }
        let scrolls = contentHeight > Self.maximumHeight
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(headings.enumerated()), id: \.element.id) { index, heading in
                        let depth = heading.level - base
                        // Leave air where the outline climbs back out of a section.
                        let gap = index > 0 && depth < headings[index - 1].level - base
                        MacOutlineRow(heading: heading, depth: depth, current: index == current) { onSelect(heading.id) }
                            .padding(.top, gap ? 6 : 0).id(heading.id)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollDisabled(!scrolls).scrollIndicators(scrolls ? .automatic : .hidden)
            .frame(height: min(max(contentHeight, 1), Self.maximumHeight))
            .onChange(of: current) { _, value in
                // Only the capped list scrolls; never move the surrounding inspector.
                guard scrolls, let value, headings.indices.contains(value) else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(headings[value].id) }
            }
        }
    }
}

private struct MacOutlineRow: View {
    @Environment(\.macTheme) private var theme
    let heading: MacHeading
    let depth: Int
    let current: Bool
    let action: () -> Void
    @State private var hovering = false
    private var title: String { heading.title.isEmpty ? "Untitled heading" : heading.title }
    private var accent: Color { theme.color(.accent) }
    private var textStyle: AnyShapeStyle {
        if current { return AnyShapeStyle(accent) }
        return depth >= 2 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }
    private var fill: Color { current ? accent.opacity(0.14) : Color.primary.opacity(hovering ? 0.07 : 0) }
    private var guides: some View {
        ForEach(0..<max(0, depth), id: \.self) { _ in
            Color.clear.frame(width: 12).overlay(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.2)).frame(width: 1).padding(.leading, 4)
            }
        }
    }
    private var label: some View {
        SwiftUI.Text(title)
            .macFont(.system(size: 12, weight: depth == 0 ? .semibold : .regular))
            .foregroundStyle(textStyle)
            .multilineTextAlignment(.leading).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 3.5)
    }
    @ViewBuilder private var marker: some View {
        if current { RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: 2).padding(.vertical, 3) }
    }
    private var row: some View {
        HStack(alignment: .top, spacing: 0) { guides; label; Spacer(minLength: 0) }
            .padding(.leading, 8).padding(.trailing, 6)
            .background(RoundedRectangle(cornerRadius: 5).fill(fill))
            .overlay(alignment: .leading) { marker }
            .contentShape(Rectangle())
    }
    var body: some View {
        let jump = "Jump to \(title)"
        let detail = "Heading level \(heading.level), \(heading.id)"
        let traits: AccessibilityTraits = current ? .isSelected : []
        Button(action: action) { row }
            .buttonStyle(.plain).onHover { hovering = $0 }
            .help(jump).accessibilityLabel(jump).accessibilityValue(detail)
            .accessibilityAddTraits(traits)
            .accessibilityIdentifier("note.heading.\(heading.id)")
    }
}
