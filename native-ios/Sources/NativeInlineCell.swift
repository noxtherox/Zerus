import SwiftUI
import UIKit
import Markdown

private extension NSAttributedString.Key {
    static let cellCode = NSAttributedString.Key("ZerusCellCode")
    static let cellLinkTitle = NSAttributedString.Key("ZerusCellLinkTitle")
    static let cellImageSource = NSAttributedString.Key("ZerusCellImageSource")
    static let cellImageAlt = NSAttributedString.Key("ZerusCellImageAlt")
}

/// Only balanced, attribute-free inline formatting tags are interpreted. Other
/// HTML stays protected source in cells and inert text in document exports.
enum NativeInlineHTML {
    struct Tag { let name: String; let flags: Int; let closing: Bool }
    static func paired(in node: any Markup) -> [Int: Tag] {
        var opened: [(Int, Tag)] = [], pairs: [Int: Tag] = [:]
        for (index, child) in node.children.enumerated() {
            guard let html = child as? InlineHTML else { continue }
            let raw = html.rawHTML, closing = raw.hasPrefix("</")
            guard raw.hasSuffix(">") else { continue }
            let name = String(raw.dropFirst(closing ? 2 : 1).dropLast())
            let flags: Int
            switch name { case "strong", "b": flags = 1; case "em", "i": flags = 2; case "s", "del", "strike": flags = 4; default: continue }
            let tag = Tag(name: name, flags: flags, closing: closing)
            if !closing { opened.append((index, tag)) }
            else if let last = opened.last, last.1.name == name { opened.removeLast(); pairs[last.0] = last.1; pairs[index] = tag }
            else { opened = [] }
        }
        return pairs
    }
}

/// One inline renderer preserves nested styles inside links. Foundation Markdown
/// currently drops those label intents, including in full parsing mode.
enum NativeInlineMarkdown {
    static func prepared(_ source: String) -> String {
        let wrapped = "cell " + source + " end"
        let edits = ((try? MarkdownMoveLinks.links(in: wrapped)) ?? []).compactMap { link -> (MarkdownMoveLinks.Link, String)? in
            guard case .wiki = link.kind else { return nil }
            return (link, NoteReference.inlineMarkdown(link.value))
        }
        return MarkdownMoveLinks.replacing(wrapped, edits: edits)
    }
    static func render(_ source: String, images: [String: UIImage] = [:], attributes: [NSAttributedString.Key: Any]? = nil, proseWidth: CGFloat? = nil) -> NSAttributedString {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NSAttributedString(string: source, attributes: attributes ?? [.font: MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text])
        }
        let prepared = prepared(source)
        let output = NSMutableAttributedString(string: "")
        func visit(_ node: any Markup, attributes: [NSAttributedString.Key: Any]) {
            if let text = node as? Markdown.Text { output.append(NSAttributedString(string: text.string, attributes: attributes)); return }
            if let code = node as? InlineCode {
                var attributes = attributes
                let base = attributes[.font] as? UIFont ?? MarkdownText.font(), mono = UIFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
                attributes[.cellCode] = true; attributes[.zerusInlineCode] = true; attributes[.font] = mono.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.traitMonoSpace)).map { UIFont(descriptor: $0, size: base.pointSize) } ?? mono
                output.append(NSAttributedString(string: code.code, attributes: attributes)); return
            }
            if node is InlineHTML { return }
            var attributes = attributes
            if node is Strong || node is Emphasis {
                let base = attributes[.font] as? UIFont ?? MarkdownText.font()
                var traits = base.fontDescriptor.symbolicTraits; traits.insert(node is Strong ? .traitBold : .traitItalic)
                attributes[.font] = base.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
            }
            if node is Strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = node as? Markdown.Link, let address = link.destination, let url = URL(string: address) {
                attributes[.link] = url; attributes[.foregroundColor] = NativeThemeUIKit.link
                if let title = link.title { attributes[.cellLinkTitle] = title }
            }
            if let image = node as? Markdown.Image, let address = image.source, let range = image.range {
                let lower = range.lowerBound.column - 1, upper = range.upperBound.column - 1
                let utf8 = Array(prepared.utf8)
                guard lower >= 0, upper <= utf8.count, upper >= lower else { return }
                let markup = String(decoding: utf8[lower..<upper], as: UTF8.self)
                let attachment = NativeImageAttachment(reference: address, images: images, proseWidth: proseWidth)
                let token = NSMutableAttributedString(attachment: attachment)
                attributes[.zerusImageMarkdown] = markup; attributes[.cellImageSource] = address; attributes[.cellImageAlt] = image.plainText; attributes.removeValue(forKey: .link)
                if proseWidth != nil {
                    let reference = URL(string: address)?.relativeString ?? address
                    attributes[.link] = URL(string: "zerus-image:" + (reference.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))
                }
                token.addAttributes(attributes, range: NSRange(location: 0, length: token.length)); output.append(token); return
            }
            let tags = NativeInlineHTML.paired(in: node)
            var current = attributes, stack: [[NSAttributedString.Key: Any]] = []
            for (index, child) in node.children.enumerated() {
                if let tag = tags[index] {
                    if tag.closing { current = stack.removeLast() }
                    else {
                        stack.append(current)
                        let base = current[.font] as? UIFont ?? MarkdownText.font()
                        var traits = base.fontDescriptor.symbolicTraits
                        if tag.flags & 1 != 0 { traits.insert(.traitBold) }; if tag.flags & 2 != 0 { traits.insert(.traitItalic) }
                        current[.font] = base.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
                        if tag.flags & 4 != 0 { current[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    }
                } else { visit(child, attributes: current) }
            }
        }
        visit(Document(parsing: prepared, options: [.disableSmartOpts]), attributes: attributes ?? [.font: MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text])
        if output.length >= 9 { output.deleteCharacters(in: NSRange(location: output.length - 4, length: 4)); output.deleteCharacters(in: NSRange(location: 0, length: 5)) }
        return output
    }
}

/// A table cell is inline content even when its first characters look like a
/// heading or list. Source positions keep image captions/titles intact, and
/// wiki conversion excludes literal code and escaped examples.
enum NativeCellMarkdown {
    static func supports(_ source: String) -> Bool {
        guard !source.contains("\n"), !source.contains("\r") else { return false }
        let prepared = NativeInlineMarkdown.prepared(source), document = Document(parsing: prepared)
        func containsImage(_ node: any Markup) -> Bool { node is Markdown.Image || node.children.contains(where: containsImage) }
        func supported(_ node: any Markup) -> Bool {
            if node is InlineCode || node is Markdown.Image { return true }
            if let link = node as? Markdown.Link, link.destination.flatMap(URL.init(string:)) == nil { return false }
            if node is Markdown.Link, containsImage(node) { return false }
            if node is Markdown.Text, let range = node.range {
                let bytes = Array(prepared.utf8), start = range.lowerBound.column - 1, end = range.upperBound.column - 1
                if start >= 0, end <= bytes.count, String(decoding: bytes[start..<end], as: UTF8.self).range(of: #"(?<!\\)\]\s*\["#, options: .regularExpression) != nil { return false }
            }
            guard node is Markdown.Document || node is Paragraph || node is Markdown.Text || node is Emphasis || node is Strong || node is Strikethrough || node is Markdown.Link else { return false }
            let tags = NativeInlineHTML.paired(in: node)
            return node.children.enumerated().allSatisfy { index, child in child is InlineHTML ? tags[index] != nil : supported(child) }
        }
        return document.childCount == 1 && document.children.allSatisfy(supported)
    }
    static func render(_ source: String, images: [String: UIImage] = [:]) -> NSAttributedString {
        NativeInlineMarkdown.render(source, images: images)
    }
    static func serialize(_ value: NSAttributedString) throws -> String {
        var output = ""
        let text = value.string as NSString
        var runs: [(String, Int, URL?, String?, String?)] = []
        var unsupportedUnderline = false
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attrs, range, _ in
            if (attrs[.underlineStyle] as? Int ?? 0) != 0 { unsupportedUnderline = true }
            let font = attrs[.font] as? UIFont ?? MarkdownText.font(), traits = font.fontDescriptor.symbolicTraits
            let flags = (traits.contains(.traitBold) ? 1 : 0) | (traits.contains(.traitItalic) ? 2 : 0) | ((attrs[.strikethroughStyle] as? Int ?? 0) != 0 ? 4 : 0) | ((attrs[.cellCode] as? Bool == true || traits.contains(.traitMonoSpace)) ? 8 : 0)
            let link = attrs[.link] as? URL ?? (attrs[.link] as? String).flatMap(URL.init(string:))
            let run = (text.substring(with: range), flags, link, attrs[.cellLinkTitle] as? String, attrs[.zerusImageMarkdown] as? String)
            if let last = runs.last, last.1 == run.1, last.2 == run.2, last.3 == run.3, last.4 == nil, run.4 == nil { runs[runs.count - 1].0 += run.0 }
            else { runs.append(run) }
        }
        guard !unsupportedUnderline else { throw VaultFailure(message: "Underline needs HTML source editing. Undo that formatting, or use bold, italic or strikethrough.") }
        var position = 0, skipUntil = 0
        for (index, run) in runs.enumerated() {
            let start = position; position += (run.0 as NSString).length
            guard index >= skipUntil else { continue }
            let (plain, flags, link, title, image) = run
            if image == nil, let link, let reference = NoteReference(url: link) {
                guard !reference.target.contains("|") else { throw VaultFailure(message: "This note link cannot be represented in a table cell. Choose another note.") }
                var end = index + 1, label = plain
                while end < runs.count && runs[end].2 == link && runs[end].4 == nil { label += runs[end].0; end += 1 }
                if end > index + 1 || flags & 8 != 0 {
                    let richLabel = NSMutableAttributedString(attributedString: value.attributedSubstring(from: NSRange(location: start, length: (label as NSString).length)))
                    richLabel.removeAttribute(.link, range: NSRange(location: 0, length: richLabel.length))
                    output += reference.markdown(label: label, formattedLabel: try serialize(richLabel))
                    skipUntil = end
                    continue
                }
            }
            guard !plain.contains("\n"), !plain.contains("\r") else { throw VaultFailure(message: "Keep a table cell on one line. Paste text without paragraph breaks.") }
            if plain.contains("\u{fffc}"), image == nil { throw VaultFailure(message: "This pasted attachment cannot be stored in the cell. Undo the paste and add the image to the note first.") }
            var leading = "", trailing = "", content = image ?? plain
            if image == nil && flags & 8 == 0 {
                leading = String(content.prefix(while: \.isWhitespace)); content.removeFirst(leading.count)
                trailing = String(content.reversed().prefix(while: \.isWhitespace).reversed()); content.removeLast(trailing.count)
                content = content.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: #"([\\`*_\[\]<>~])"#, with: #"\\$1"#, options: .regularExpression)
            } else if image == nil {
                let matches = (try? NSRegularExpression(pattern: "`+"))?.matches(in: content, range: NSRange(location: 0, length: (content as NSString).length)) ?? []
                let fence = String(repeating: "`", count: (matches.map { $0.range.length }.max() ?? 0) + 1)
                let pad = content.hasPrefix("`") || content.hasSuffix("`") || (content.hasPrefix(" ") && content.hasSuffix(" ") && !content.allSatisfy(\.isWhitespace))
                content = fence + (pad ? " " : "") + content + (pad ? " " : "") + fence
            }
            if let link, image == nil {
                if let reference = NoteReference(url: link) {
                    content = reference.markdown(label: plain); leading = ""; trailing = ""
                } else {
                    let address = link.relativeString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
                    let caption = title.map { " \"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" } ?? ""
                    content = "[" + leading + content + trailing + "](" + address + caption + ")"; leading = ""; trailing = ""
                }
            }
            if !content.isEmpty {
                // Markdown flanking rules cannot express every adjacent style
                // boundary. Balanced basic HTML keeps those boundaries portable
                // without adding hidden characters or literal comment markers.
                let before = index > 0 ? runs[index - 1].0.last : nil, after = index + 1 < runs.count ? runs[index + 1].0.first : nil
                let html = (leading.isEmpty && before?.isWhitespace == false) || (trailing.isEmpty && after?.isWhitespace == false)
                if flags & 1 != 0 { content = html ? "<strong>" + content + "</strong>" : "**" + content + "**" }
                if flags & 2 != 0 { content = html ? "<em>" + content + "</em>" : "*" + content + "*" }
                if flags & 4 != 0 { content = html ? "<s>" + content + "</s>" : "~~" + content + "~~" }
            }
            let token = leading + content + trailing
            output += token
        }
        return output
    }
    static func preview(_ source: String) -> AttributedString {
        let rich = render(source); var output = AttributedString("")
        rich.enumerateAttributes(in: NSRange(location: 0, length: rich.length)) { attrs, range, _ in
            var run = AttributedString(attrs[.cellImageAlt] as? String ?? (rich.string as NSString).substring(with: range))
            let traits = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            var intent: InlinePresentationIntent = []
            if traits.contains(.traitBold) { intent.insert(.stronglyEmphasized) }; if traits.contains(.traitItalic) { intent.insert(.emphasized) }
            if traits.contains(.traitMonoSpace) { intent.insert(.code) }; if (attrs[.strikethroughStyle] as? Int ?? 0) != 0 { intent.insert(.strikethrough) }
            run.inlinePresentationIntent = intent
            if let link = attrs[.link] as? URL { run.link = link }
            if let image = attrs[.cellImageSource] as? String { run.imageURL = URL(string: image) }
            output.append(run)
        }
        return output
    }
}

struct NativeCellLinkRequest: Identifiable {
    let id = UUID()
    let label: String
    let url: URL?
    let apply: (String, URL?) -> Bool
}

final class NativeCellEditorActions: ObservableObject {
    weak var coordinator: NativeCellTextEditor.Coordinator?
    func commit() -> String? { coordinator?.commit() }
}

struct NativeCellTextEditor: UIViewRepresentable {
    let markdown: String
    let source: Bool
    let images: [String: UIImage]
    let changed: (String) -> Void
    let issue: (String?) -> Void
    let link: (NativeCellLinkRequest) -> Void
    let actions: NativeCellEditorActions
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = AdaptiveTextView(frame: .zero, textContainer: nil)
        view.backgroundColor = .clear; view.adjustsFontForContentSizeCategory = true
        view.linkTextAttributes = [.foregroundColor: NativeThemeUIKit.link]
        view.tintColor = NativeThemeUIKit.accent; view.delegate = context.coordinator
        view.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 24, right: 0)
        view.textContainer.lineFragmentPadding = 0; view.keyboardDismissMode = .interactive
        view.accessibilityIdentifier = "table.cell.content"; view.accessibilityLabel = "Cell content"
        context.coordinator.view = view; actions.coordinator = context.coordinator; context.coordinator.load()
        view.inputAccessoryView = context.coordinator.accessory()
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let changedMode = context.coordinator.parent.source != source
        context.coordinator.parent = self
        actions.coordinator = context.coordinator
        if changedMode || context.coordinator.last != markdown { context.coordinator.load() }
        if !source { MarkdownText.refreshImageAttachments(in: view, images: images) }
        if changedMode { view.undoManager?.removeAllActions(); view.inputAccessoryView = context.coordinator.accessory(); view.reloadInputViews() }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeCellTextEditor
        weak var view: UITextView?
        var last = "", original = ""
        var originalRich = NSAttributedString(string: "")
        init(_ parent: NativeCellTextEditor) { self.parent = parent }
        func load() {
            guard let view else { return }
            (view as? AdaptiveTextView)?.sourceMode = parent.source
            last = parent.markdown; original = last
            view.attributedText = parent.source ? NSAttributedString(string: last, attributes: [.font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular), .foregroundColor: NativeThemeUIKit.text]) : NativeCellMarkdown.render(last, images: parent.images)
            originalRich = NSAttributedString(attributedString: view.attributedText)
            view.allowsEditingTextAttributes = !parent.source
            view.autocorrectionType = parent.source ? .no : .default; view.smartQuotesType = .no; view.smartDashesType = .no
            view.autocapitalizationType = parent.source ? .none : .sentences
            view.typingAttributes = [.font: parent.source ? UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular) : MarkdownText.font(), .foregroundColor: NativeThemeUIKit.text]
            view.selectedRange = NSRange(location: view.attributedText.length, length: 0)
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" { textView.resignFirstResponder(); return false }
            if !parent.source {
                textView.typingAttributes.removeValue(forKey: .attachment); textView.typingAttributes.removeValue(forKey: .zerusImageMarkdown)
            }
            return true
        }
        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            _ = publish(textView)
        }
        func commit() -> String? {
            guard let view else { return nil }
            if view.markedTextRange != nil { view.unmarkText() }
            return publish(view)
        }
        private func publish(_ textView: UITextView) -> String? {
            do {
                let next = parent.source ? textView.text ?? "" : textView.attributedText.isEqual(to: originalRich) ? original : try NativeCellMarkdown.serialize(textView.attributedText)
                guard !next.contains("\n"), !next.contains("\r") else { throw VaultFailure(message: "Keep the cell on one line. Remove pasted paragraph breaks before saving.") }
                last = next; parent.changed(next); parent.issue(nil); return next
            } catch { parent.issue(error.localizedDescription); return nil }
        }
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool { false }
        func accessory() -> UIView {
            let toolbar = UIToolbar(); toolbar.sizeToFit()
            func button(_ title: String, _ image: String, _ selector: Selector, _ id: String) -> UIBarButtonItem {
                let item = UIBarButtonItem(image: UIImage(systemName: image), style: .plain, target: self, action: selector)
                item.accessibilityLabel = title; item.accessibilityIdentifier = "table.cell." + id; return item
            }
            toolbar.items = [button("Bold", "bold", #selector(bold), "bold"), button("Italic", "italic", #selector(italic), "italic"), button("Inline code", "chevron.left.forwardslash.chevron.right", #selector(code), "code"), button("Strikethrough", "strikethrough", #selector(strike), "strike"), button("Edit link", "link", #selector(editLink), "link"), .flexibleSpace(), button("Undo cell edit", "arrow.uturn.backward", #selector(undo), "undo"), button("Redo cell edit", "arrow.uturn.forward", #selector(redo), "redo"), button("Dismiss keyboard", "keyboard.chevron.compact.down", #selector(dismissKeyboard), "keyboard.dismiss")]
            if parent.source { for item in toolbar.items?.prefix(5) ?? [] { item.isEnabled = false } }
            return toolbar
        }
        private func enabled(_ flag: Int) -> Bool {
            guard let view else { return false }
            if view.markedTextRange != nil { view.unmarkText(); textViewDidChange(view) }
            func contains(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
                let traits = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
                switch flag { case 1: return traits.contains(.traitBold); case 2: return traits.contains(.traitItalic); case 4: return (attrs[.strikethroughStyle] as? Int ?? 0) != 0; default: return attrs[.cellCode] as? Bool == true || traits.contains(.traitMonoSpace) }
            }
            if view.selectedRange.length == 0 { return contains(view.typingAttributes) }
            var all = true
            view.attributedText.enumerateAttributes(in: view.selectedRange) { attrs, _, _ in if !contains(attrs) { all = false } }
            return all
        }
        @objc func bold() { let remove = enabled(1); format { attrs in
            let font = attrs[.font] as? UIFont ?? MarkdownText.font(); var traits = font.fontDescriptor.symbolicTraits
            if remove { traits.remove(.traitBold) } else { traits.insert(.traitBold) }
            attrs[.font] = font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
        } }
        @objc func italic() { let remove = enabled(2); format { attrs in
            let font = attrs[.font] as? UIFont ?? MarkdownText.font(); var traits = font.fontDescriptor.symbolicTraits
            if remove { traits.remove(.traitItalic) } else { traits.insert(.traitItalic) }
            attrs[.font] = font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
        } }
        @objc func code() { let remove = enabled(8); format { attrs in
            guard attrs[.attachment] == nil else { return }
            let font = attrs[.font] as? UIFont ?? MarkdownText.font(), traits = font.fontDescriptor.symbolicTraits
            if remove { attrs.removeValue(forKey: .cellCode); attrs[.font] = MarkdownText.font(traits: traits.subtracting(.traitMonoSpace)) }
            else {
                attrs[.cellCode] = true
                let mono = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                attrs[.font] = mono.fontDescriptor.withSymbolicTraits(traits.union(.traitMonoSpace)).map { UIFont(descriptor: $0, size: font.pointSize) } ?? mono
            }
        } }
        @objc func strike() { let remove = enabled(4); format { attrs in if remove { attrs.removeValue(forKey: .strikethroughStyle) } else { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue } } }
        private func format(_ edit: (inout [NSAttributedString.Key: Any]) -> Void) {
            guard let view, !parent.source else { return }
            if view.markedTextRange != nil { view.unmarkText() }
            let selection = view.selectedRange
            if selection.length == 0 { var attrs = view.typingAttributes; edit(&attrs); view.typingAttributes = attrs; view.becomeFirstResponder(); return }
            let original = NSAttributedString(attributedString: view.attributedText), changed = NSMutableAttributedString(attributedString: original)
            original.enumerateAttributes(in: selection) { attrs, range, _ in var attrs = attrs; edit(&attrs); changed.setAttributes(attrs, range: range) }
            apply(changed, selection: selection, inverse: original)
        }
        private func apply(_ value: NSAttributedString, selection: NSRange, inverse: NSAttributedString) {
            guard let view else { return }
            let oldSelection = view.selectedRange
            view.undoManager?.registerUndo(withTarget: self) { owner in owner.apply(inverse, selection: oldSelection, inverse: value) }
            view.attributedText = value; view.selectedRange = selection; textViewDidChange(view)
        }
        @objc func undo() { view?.undoManager?.undo(); if let view { textViewDidChange(view) } }
        @objc func redo() { view?.undoManager?.redo(); if let view { textViewDidChange(view) } }
        @objc func dismissKeyboard() { view?.resignFirstResponder() }
        @objc func editLink() {
            guard let view, !parent.source else { return }
            if view.markedTextRange != nil { view.unmarkText() }
            let baseline = NSAttributedString(attributedString: view.attributedText)
            var range = view.selectedRange, address: URL?
            if baseline.length > 0 {
                var linked = NSRange(); let value = baseline.attribute(.link, at: min(range.location, baseline.length - 1), effectiveRange: &linked)
                address = value as? URL ?? (value as? String).flatMap(URL.init(string:))
                if address != nil && range.length == 0 { range = linked }
            }
            let label = (baseline.string as NSString).substring(with: range)
            view.resignFirstResponder()
            parent.link(.init(label: label, url: address, apply: { [weak self, weak view] label, url in
                guard let self, let view, view.attributedText.isEqual(to: baseline) else { return false }
                let changed = NSMutableAttributedString(attributedString: baseline)
                let replacement: NSMutableAttributedString
                if label == (baseline.string as NSString).substring(with: range) { replacement = NSMutableAttributedString(attributedString: baseline.attributedSubstring(from: range)) }
                else {
                    let attrs = range.location < baseline.length ? baseline.attributes(at: range.location, effectiveRange: nil) : view.typingAttributes
                    replacement = NSMutableAttributedString(string: label, attributes: attrs)
                }
                let all = NSRange(location: 0, length: replacement.length)
                for key in [NSAttributedString.Key.link, .attachment, .zerusImageMarkdown] { replacement.removeAttribute(key, range: all) }
                if url == nil { replacement.removeAttribute(.cellLinkTitle, range: all) }
                replacement.addAttribute(.foregroundColor, value: url == nil ? NativeThemeUIKit.text : NativeThemeUIKit.link, range: all)
                if let url { replacement.addAttribute(.link, value: url, range: all) }
                changed.replaceCharacters(in: range, with: replacement)
                self.apply(changed, selection: NSRange(location: range.location + (label as NSString).length, length: 0), inverse: baseline)
                return true
            }))
        }
    }
}
