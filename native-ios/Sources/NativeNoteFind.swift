import SwiftUI
import UIKit

struct NativeNoteFindMatch: Identifiable {
    let id: String
    let label: String
    let before: String
    let matched: String
    let after: String
    let selection: NSRange
}

/// Search the current displayed text, expanding bitmap-backed code and tables
/// so content beyond their short previews remains discoverable.
struct NativeNoteFindSnapshot: Identifiable {
    let id = UUID()
    struct Segment {
        let text: String
        let label: String
        let selection: NSRange
        let direct: Bool
    }
    let segments: [Segment]
    let reveal: (NativeNoteFindMatch) -> Bool
    func matches(_ query: String, matchCase: Bool = false) -> [NativeNoteFindMatch] {
        guard !query.isEmpty else { return [] }
        let options: NSString.CompareOptions = matchCase ? [.diacriticInsensitive] : [.caseInsensitive, .diacriticInsensitive]
        var results: [NativeNoteFindMatch] = []
        for (index, segment) in segments.enumerated() {
            let text = segment.text as NSString
            var cursor = 0
            while cursor < text.length {
                let range = text.range(of: query, options: options, range: NSRange(location: cursor, length: text.length - cursor))
                guard range.location != NSNotFound, range.length > 0 else { break }
                let context = text.rangeOfComposedCharacterSequences(for: NSRange(location: max(0, range.location - 65), length: min(text.length, NSMaxRange(range) + 65) - max(0, range.location - 65)))
                func flatten(_ value: String) -> String { value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") }
                let before = (context.location > 0 ? "…" : "") + flatten(text.substring(with: NSRange(location: context.location, length: range.location - context.location)))
                let after = flatten(text.substring(with: NSRange(location: NSMaxRange(range), length: NSMaxRange(context) - NSMaxRange(range)))) + (NSMaxRange(context) < text.length ? "…" : "")
                results.append(.init(id: "\(index):\(range.location)", label: segment.label, before: before, matched: text.substring(with: range), after: after,
                                     selection: segment.direct ? NSRange(location: segment.selection.location + range.location, length: range.length) : segment.selection))
                cursor = NSMaxRange(range)
            }
        }
        return results
    }
}

extension NativeTextEditor.Coordinator {
    func findSnapshot() -> NativeNoteFindSnapshot? {
        guard let view, view.markedTextRange == nil, view.window != nil else { return nil }
        let value = view.attributedText ?? NSAttributedString(string: "")
        var segments: [NativeNoteFindSnapshot.Segment] = []
        let plain = value.string as NSString
        var cursor = 0
        func prose(_ range: NSRange) {
            guard range.length > 0 else { return }
            segments.append(.init(text: plain.substring(with: range), label: source ? "Markdown source" : "Note text", selection: range, direct: true))
        }
        if source { prose(NSRange(location: 0, length: value.length)) }
        else {
            value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { attachment, range, _ in
                guard let attachment = attachment as? NSTextAttachment else { return }
                prose(NSRange(location: cursor, length: range.location - cursor)); cursor = NSMaxRange(range)
                if let code = attachment as? CodeAttachment {
                    segments.append(.init(text: code.code.body, label: code.code.language + " code", selection: range, direct: false))
                } else if let table = attachment as? TableAttachment {
                    for (rowIndex, row) in table.table.rows.enumerated() {
                        for (columnIndex, cell) in row.enumerated() {
                            segments.append(.init(text: TableCellContent.plain(cell), label: rowIndex == 0 ? "Table · heading \(columnIndex + 1)" : "Table · row \(rowIndex), column \(columnIndex + 1)", selection: range, direct: false))
                        }
                    }
                }
            }
            prose(NSRange(location: cursor, length: value.length - cursor))
        }
        let document = parent.documentID, markdown = lastMarkdown, mode = source, visible = value.string
        return NativeNoteFindSnapshot(segments: segments) { [weak self, weak view] match in
            guard let self, let view, self.view === view, view.window != nil, view.markedTextRange == nil,
                  self.parent.documentID == document, self.source == mode,
                  (self.lastMarkdown as NSString).compare(markdown, options: .literal) == .orderedSame,
                  (view.attributedText.string as NSString).compare(visible, options: .literal) == .orderedSame,
                  match.selection.location != NSNotFound, NSMaxRange(match.selection) <= view.attributedText.length else { return false }
            self.revealSelection(match.selection)
            (view as? ZerusTextView)?.showFindHighlight(match.selection)
            return true
        }
    }
}

struct NativeNoteFindView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: NativeNoteFindSnapshot
    let choose: (NativeNoteFindMatch) -> Void
    @State private var query = ""
    @State private var matchCase = false
    private var matches: [NativeNoteFindMatch] { snapshot.matches(query, matchCase: matchCase) }
    var body: some View {
        NavigationStack {
            let results = matches
            List {
                if query.isEmpty {
                    ContentUnavailableView("Find in this note", systemImage: "doc.text.magnifyingglass", description: Text("Search note text, complete code blocks and table cells. Choose a result to show its text or block in the note."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section("\(results.count) \(results.count == 1 ? "match" : "matches")") {
                        ForEach(results) { result in
                            Button { choose(result); dismiss() } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(result.label).font(.caption).foregroundStyle(.secondary)
                                    Text("\(result.before)\(Text(result.matched).bold().foregroundColor(Accent.color))\(result.after)")
                                        .foregroundStyle(Accent.text).fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            }.accessibilityIdentifier("note.find.result." + result.id)
                        }
                    }
                }
            }.navigationTitle("Find in note").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Find in note").textInputAutocapitalization(.never).autocorrectionDisabled()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Toggle("Match case", isOn: $matchCase).toggleStyle(.button).font(.subheadline).accessibilityIdentifier("note.find.case") }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}
