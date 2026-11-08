import Foundation
import Markdown
import SwiftUI

struct NativeHeading: Identifiable {
    let id: String
    let title: String
    let level: Int
    let range: NSRange
}
struct NativeHeadingRequest: Equatable {
    let id = UUID()
    let fragment: String
}
enum NativeHeadings {
    static func localFragment(_ url: URL) -> String? {
        guard url.scheme == nil, url.relativeString.hasPrefix("#"), NoteReference(url: url) == nil else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
    }
    static func entries(_ source: String) -> [NativeHeading] {
        let bytes = Array(source.utf8)
        var starts = [0], cursor = 0
        while cursor < bytes.count {
            if bytes[cursor] == 13 {
                cursor += 1; if cursor < bytes.count, bytes[cursor] == 10 { cursor += 1 }
                starts.append(cursor)
            } else if bytes[cursor] == 10 { cursor += 1; starts.append(cursor) }
            else { cursor += 1 }
        }
        func offset(_ location: SourceLocation) -> Int? {
            guard starts.indices.contains(location.line - 1) else { return nil }
            let position = starts[location.line - 1] + location.column - 1
            guard position >= 0, position <= bytes.count else { return nil }
            return String(decoding: bytes.prefix(position), as: UTF8.self).utf16.count
        }
        var used = Set<String>()
        return Document(parsing: source).children.compactMap { node in
            guard let heading = node as? Heading, let range = heading.range,
                  let start = offset(range.lowerBound), let limit = offset(range.upperBound), limit >= start else { return nil }
            let text = source as NSString
            var end = limit
            while end > start, [10, 13].contains(Int(text.character(at: end - 1))) { end -= 1 }
            let rawHeading = (source as NSString).substring(with: NSRange(location: start, length: end - start))
            let display = rawHeading.contains("[[") ? Document(parsing: NoteReference.inlineMarkdown(rawHeading)).children.compactMap { $0 as? Heading }.first?.plainText ?? heading.plainText : heading.plainText
            let title = display.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = slug(title), root = base.isEmpty ? "section" : base
            var id = root, suffix = 0
            while used.contains(id) { suffix += 1; id = root + "-" + String(suffix) }
            used.insert(id)
            return NativeHeading(id: id, title: title, level: heading.level, range: NSRange(location: start, length: end - start))
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
    static func target(_ fragment: String, in source: String) -> NativeHeading? {
        let headings = entries(source), query = fragment.precomposedStringWithCanonicalMapping
        return headings.first { $0.id == query.lowercased(with: Locale(identifier: "en_US_POSIX")) }
            ?? headings.first { $0.title.precomposedStringWithCanonicalMapping.compare(query, options: [.caseInsensitive]) == .orderedSame }
    }
}

struct NativeNoteOutline: View {
    @Environment(\.dismiss) private var dismiss
    let headings: [NativeHeading]
    let choose: (String) -> Void
    var body: some View {
        NavigationStack {
            List {
                if headings.isEmpty { ContentUnavailableView("No headings yet", systemImage: "list.bullet.indent", description: Text("Add headings to move quickly through a longer note.")) }
                ForEach(headings) { heading in
                    Button { dismiss(); choose(heading.id) } label: {
                        Text(heading.title.isEmpty ? "Untitled heading" : heading.title)
                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                    }.accessibilityValue("Heading level " + String(heading.level)).accessibilityIdentifier("note.heading." + heading.id)
                }
            }.navigationTitle("On this note").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
