import SwiftUI
import UIKit

struct NativeNoteLinkOption: Identifiable, Equatable {
    let path: String
    let title: String
    var id: String { path }
}

struct NativeNoteLinkRequest: Identifiable {
    let id = UUID()
    let query: String
    let options: [NativeNoteLinkOption]
    var selected = 0
    let insert: (String) -> Bool
    let dismiss: () -> Void
}

extension NativeEditorActions {
    func chooseNoteLink(_ path: String) {
        guard let request = noteLink else { return }
        if !request.insert(path) { coordinator?.parent.onNoteLinkIssue("The note or selection changed. Place the caret and choose the link again.") }
        request.dismiss()
    }
    func moveNoteLink(_ direction: Int) {
        guard var request = noteLink, !request.options.isEmpty else { return }
        request.selected = (request.selected + direction + request.options.count) % request.options.count
        noteLink = request
    }
    func dismissNoteLink() { noteLink?.dismiss() }
}

struct NativeNoteLinkSuggestions: View {
    @ObservedObject var actions: NativeEditorActions
    var body: some View {
        if let request = actions.noteLink {
            VStack(spacing: 0) {
                HStack {
                    Text("Link a note").font(.caption.bold())
                    Spacer()
                    Button { actions.dismissNoteLink() } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Dismiss note suggestions").accessibilityIdentifier("note.links.dismiss")
                }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8)
                if request.options.isEmpty {
                    Text("No matching notes. Try another title or folder.").font(.callout).foregroundStyle(.secondary).padding(16)
                } else {
                    ScrollViewReader { scroll in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(request.options.enumerated()), id: \.element.id) { index, option in
                                    Button { actions.chooseNoteLink(option.path) } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(option.title).font(.callout.weight(.medium)).foregroundStyle(.primary)
                                                Text(option.path).font(.caption2).foregroundStyle(.secondary)
                                            }.lineLimit(1)
                                            Spacer()
                                            if index == request.selected { Image(systemName: "return").font(.caption).foregroundStyle(.secondary) }
                                        }.padding(.horizontal, 20).padding(.vertical, 9).frame(minHeight: 44)
                                            .background(index == request.selected ? Accent.color.opacity(0.08) : .clear).contentShape(Rectangle())
                                    }.buttonStyle(.plain).id(option.path).accessibilityIdentifier("note.links.option." + option.path)
                                        .accessibilityAddTraits(index == request.selected ? .isSelected : [])
                                }
                            }
                        }.frame(maxHeight: 160)
                            .onChange(of: request.selected) { _, index in
                                if request.options.indices.contains(index) { scroll.scrollTo(request.options[index].path) }
                            }
                    }
                }
            }.background(.bar).accessibilityIdentifier("note.links.suggestions")
        }
    }
}

extension NativeTextEditor.Coordinator {
    /// Only committed prose immediately before a collapsed caret can trigger.
    /// Existing links, inline code, attachments, source and IME text are excluded.
    func refreshNoteLink() {
        guard let view, view.isFirstResponder, !source, !parent.readOnly, parent.noteLinkShortcuts,
              view.markedTextRange == nil, view.selectedRange.length == 0,
              let provider = parent.noteLinkOptions, parent.resolveNoteLink != nil else { publishNoteLink(nil); return }
        let caret = view.selectedRange.location, value = view.attributedText!
        guard caret <= value.length else { publishNoteLink(nil); return }
        let text = value.string as NSString
        let line = text.substring(to: caret).components(separatedBy: .newlines).last ?? ""
        guard let expression = Self.noteLinkTrigger,
              let match = expression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { publishNoteLink(nil); return }
        let capture = match.range(at: 1).location == NSNotFound ? 3 : 1
        let token = match.range(at: capture), query = (line as NSString).substring(with: match.range(at: capture + 1))
        let range = NSRange(location: caret - token.length, length: token.length)
        var excluded = false
        value.enumerateAttributes(in: range) { attributes, _, stop in
            if attributes[.link] != nil || attributes[.attachment] != nil || attributes[.zerusRichBlockMarkdown] != nil || attributes[.zerusInlineCode] as? Bool == true ||
                (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true {
                excluded = true; stop.pointee = true
            }
        }
        guard !excluded else { publishNoteLink(nil); return }
        let signature = parent.documentID + "|" + lastMarkdown + "|" + String(caret)
        guard dismissedNoteLink != signature else { publishNoteLink(nil); return }
        let options = provider(query)
        let references = Dictionary(uniqueKeysWithValues: options.compactMap { option in
            parent.resolveNoteLink?(option.path).map { (option.path, $0) }
        })
        let insert = noteLinkInsertion(range: range, shortcut: true, references: references)
        publishNoteLink(.init(query: query, options: options, insert: insert, dismiss: { [weak self] in
            self?.dismissedNoteLink = signature; self?.publishNoteLink(nil)
        }))
    }

    private static let noteLinkTrigger = try? NSRegularExpression(pattern: #"(?:^|[\s(])(@([^@\[\]\n]{0,100}))$|(?:^|[^\[])(\[\[([^\[\]\n]{0,100}))$"#)

    func publishNoteLink(_ request: NativeNoteLinkRequest?) {
        noteLinkGeneration += 1
        let generation = noteLinkGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.noteLinkGeneration == generation, let actions = self.parent.actions, actions.coordinator === self else { return }
            if request != nil || actions.noteLink != nil { actions.noteLink = request }
        }
    }

    func manualNoteLink() -> ((String) -> Bool)? {
        guard let view, !parent.readOnly else { return nil }
        if view.markedTextRange != nil { view.unmarkText(); textViewDidChange(view) }
        if view.selectedRange.length > 0 {
            let selected = view.attributedText.attributedSubstring(from: view.selectedRange)
            var protected = selected.string.contains("\n") || selected.string.contains("\r")
            if !source {
                selected.enumerateAttributes(in: NSRange(location: 0, length: selected.length)) { attributes, _, _ in
                    if attributes[.attachment] != nil || attributes[.zerusRichBlockMarkdown] != nil || attributes[.zerusImageMarkdown] != nil || attributes[.zerusDecoration] as? Bool == true { protected = true }
                }
            }
            guard !protected else {
                parent.onNoteLinkIssue("Choose text within one paragraph, without images, tables, code blocks or checklist controls.")
                return nil
            }
        }
        let insert = noteLinkInsertion(range: view.selectedRange, shortcut: false)
        publishNoteLink(nil); view.resignFirstResponder()
        return insert
    }

    private func noteLinkInsertion(range: NSRange, shortcut: Bool, references: [String: NoteReference]? = nil) -> (String) -> Bool {
        guard let view else { return { _ in false } }
        let original = NSAttributedString(attributedString: view.attributedText)
        let document = parent.documentID, baseline = lastMarkdown, selection = view.selectedRange, mode = source
        return { [weak self] path in
            guard let self, let view = self.view, !self.parent.readOnly, self.parent.documentID == document,
                  self.source == mode, self.lastMarkdown == baseline, view.markedTextRange == nil,
                  view.selectedRange == selection, view.attributedText.isEqual(to: original),
                  !shortcut || view.isFirstResponder && self.parent.noteLinkShortcuts,
                  var reference = self.parent.resolveNoteLink?(path) else { return false }
            if let references, references[path] != reference { return false }
            let selected = range.length > 0 ? original.attributedSubstring(from: range).string : ""
            let useSelection = !shortcut && !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let label = useSelection ? selected : reference.label
            reference = NoteReference(target: reference.target, label: label, explicitLabel: true)
            let insertion: NSAttributedString
            if mode {
                insertion = NSAttributedString(string: reference.markdown(label: label), attributes: view.typingAttributes)
            } else {
                var attributes = view.typingAttributes
                if range.location < original.length { attributes = original.attributes(at: range.location, effectiveRange: nil) }
                for key: NSAttributedString.Key in [.attachment, .zerusDecoration, .zerusRichBlockMarkdown, .zerusImageMarkdown] { attributes.removeValue(forKey: key) }
                if attributes.removeValue(forKey: .zerusInlineCode) != nil || (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true {
                    let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
                    attributes[.font] = MarkdownText.font(prefix: attributes[.zerusBlock] as? String ?? "", traits: traits.subtracting(.traitMonoSpace))
                }
                let rich = useSelection ? NSMutableAttributedString(attributedString: original.attributedSubstring(from: range)) : NSMutableAttributedString(string: label, attributes: attributes)
                rich.addAttribute(.link, value: reference.url, range: NSRange(location: 0, length: rich.length))
                let suffix = (original.string as NSString).substring(from: NSMaxRange(range))
                if shortcut && (suffix.isEmpty || suffix.first?.isLetter == true || suffix.first?.isNumber == true) {
                    attributes.removeValue(forKey: .link); rich.append(NSAttributedString(string: " ", attributes: attributes))
                }
                insertion = rich
            }
            let changed = NSMutableAttributedString(attributedString: original)
            changed.replaceCharacters(in: range, with: insertion)
            self.apply(changed, selection: NSRange(location: range.location + insertion.length, length: 0), inverse: original)
            view.typingAttributes.removeValue(forKey: .link)
            self.publishNoteLink(nil); view.becomeFirstResponder()
            return true
        }
    }
}
