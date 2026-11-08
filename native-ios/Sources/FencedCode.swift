import SwiftUI
import UIKit

/// Keeps the exact Markdown token until the user explicitly edits this block.
struct FencedCode {
    let markdown: String
    let body: String
    let info: String
    let opening: String
    let fence: String
    let newline: String

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
        var lines: [(NSRange, String)] = [], cursor = 0
        while cursor < text.length {
            let range = text.lineRange(for: NSRange(location: cursor, length: 0))
            let line = text.substring(with: range).trimmingCharacters(in: .newlines)
            lines.append((range, line)); cursor = NSMaxRange(range)
        }
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
            if closed {
                if body.hasSuffix("\r\n") { body.removeLast() }
                else if body.hasSuffix("\n") || body.hasSuffix("\r") { body.removeLast() }
            }
            let range = NSRange(location: start.location, length: end - start.location)
            output.append(Located(range: range, code: FencedCode(markdown: text.substring(with: range), body: body, info: info, opening: line, fence: fence, newline: text.substring(with: start).hasSuffix("\r\n") ? "\r\n" : "\n")))
            index = closed ? closing + 1 : lines.count
        }
        return output
    }

    func replacing(body: String, info: String) -> FencedCode {
        if body == self.body && info == self.info { return self }
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

final class CodeAttachment: MarkdownAttachment, AdaptiveTextAttachment {
    let code: FencedCode
    init(code: FencedCode, width: CGFloat) {
        self.code = code
        super.init(markdown: code.markdown, editLabel: "Edit \(code.language) code", summary: code.body)
        refreshPresentation(width: width)
    }
    func refreshPresentation(width: CGFloat) {
        let width = max(140, min(width, 700))
        let padding: CGFloat = 16
        let traits = UITraitCollection.current
        let bodyFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 14, weight: .regular), compatibleWith: traits)
        let headerFont = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        let lines = code.body.components(separatedBy: .newlines)
        let preview = lines.prefix(12).joined(separator: "\n")
        let style = NSMutableParagraphStyle(); style.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: NativeThemeUIKit.text, .paragraphStyle: style]
        let available = width - padding * 2
        let textHeight = min(480, max(bodyFont.lineHeight, (preview as NSString).boundingRect(with: CGSize(width: available, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height))
        let headerHeight = headerFont.lineHeight + 14
        let height = padding * 2 + headerHeight + textHeight + headerFont.lineHeight + 14
        image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in
            NativeThemeUIKit.codeSurface.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: 12).fill()
            (code.language as NSString).draw(in: CGRect(x: padding, y: padding, width: available, height: headerFont.lineHeight), withAttributes: [.font: headerFont, .foregroundColor: UIColor.secondaryLabel])
            (preview as NSString).draw(with: CGRect(x: padding, y: padding + headerHeight, width: available, height: textHeight), options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], attributes: attributes, context: nil)
            let footer = lines.count > 12 ? "View & edit all \(lines.count) lines" : "Tap to edit code"
            (footer as NSString).draw(in: CGRect(x: padding, y: height - padding - headerFont.lineHeight, width: available, height: headerFont.lineHeight), withAttributes: [.font: headerFont, .foregroundColor: NativeThemeUIKit.accent])
        }
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
    }
    required init?(coder: NSCoder) { return nil }
}

struct CodeEditRequest: Identifiable {
    let id = UUID()
    let code: FencedCode
    let save: (FencedCode) -> Bool
    var convertToText: ((String) -> Bool)? = nil
}

struct CodeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: CodeEditRequest
    @State private var bodyText: String
    @State private var info: String
    @State private var conflict = false
    init(request: CodeEditRequest) {
        self.request = request
        _bodyText = State(initialValue: request.code.body)
        _info = State(initialValue: request.code.info)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Language").foregroundStyle(.secondary)
                    TextField("Plain text", text: $info).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("code.language")
                }.font(.subheadline).padding()
                if let convert = request.convertToText {
                    HStack {
                        Button("Turn back into text", systemImage: "text.alignleft") {
                            if convert(bodyText) { dismiss() }
                            else { conflict = true }
                        }.buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("code.toText")
                        Spacer()
                    }.padding(.horizontal).padding(.bottom, 8)
                }
                Divider()
                if conflict {
                    Text("The note changed while this editor was open. Your code is kept here; share or copy it before reopening the block.")
                        .font(.callout).foregroundStyle(.orange).padding()
                }
                CodeTextView(text: $bodyText)
            }
            .navigationTitle("Edit code").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(bodyText != request.code.body || info != request.code.info)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if request.save(request.code.replacing(body: bodyText, info: info)) { dismiss() }
                    else { conflict = true }
                }.accessibilityIdentifier("code.save") }
                ToolbarItem(placement: .bottomBar) { ShareLink(item: bodyText) { Label("Share code", systemImage: "square.and.arrow.up") } }
            }
        }
    }
}

private struct CodeTextView: UIViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(frame: .zero, textContainer: nil)
        view.delegate = context.coordinator
        view.font = UIFont.preferredFont(forTextStyle: .body).fontDescriptor.withDesign(.monospaced).map { UIFont(descriptor: $0, size: 0) }
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = NativeThemeUIKit.editor; view.textColor = NativeThemeUIKit.text; view.tintColor = NativeThemeUIKit.accent
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 40, right: 16)
        view.autocapitalizationType = .none; view.autocorrectionType = .no
        view.smartQuotesType = .no; view.smartDashesType = .no; view.smartInsertDeleteType = .no
        view.writingToolsBehavior = .none
        view.keyboardDismissMode = .interactive
        view.accessibilityLabel = "Code"; view.accessibilityIdentifier = "code.body"
        view.text = text
        let toolbar = UIToolbar(); toolbar.sizeToFit()
        let tab = UIBarButtonItem(title: "Tab", primaryAction: UIAction { [weak view] _ in view?.insertText("\t") })
        let done = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), primaryAction: UIAction { [weak view] _ in view?.resignFirstResponder() })
        done.accessibilityLabel = "Dismiss keyboard"
        toolbar.items = [tab, .flexibleSpace(), done]; view.inputAccessoryView = toolbar
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text && view.markedTextRange == nil { view.text = text }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeTextView
        init(_ parent: CodeTextView) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) { parent.text = view.text }
    }
}
