import UIKit

/// On-device AI access to the open note's editor: read the selection, or
/// apply an approved replacement as one undoable edit ("Undo AI Edit").
extension NativeEditorActions {
    struct LocalAISnapshot {
        /// The editor's Markdown (the editable body).
        let markdown: String
        /// The selected passage as Markdown, if any text is selected.
        let selection: String?
    }

    func localAISnapshot() -> LocalAISnapshot? {
        guard let coordinator, let view = coordinator.view else { return nil }
        let range = view.selectedRange
        var selection: String?
        if range.length > 0, NSMaxRange(range) <= view.attributedText.length {
            selection = coordinator.source ? (view.text as NSString).substring(with: range)
                : MarkdownText.serialize(view.attributedText.attributedSubstring(from: range))
        }
        return LocalAISnapshot(markdown: coordinator.lastMarkdown, selection: selection)
    }

    func applyLocalAI(expected: String, replacement: String) throws {
        guard let coordinator, let view = coordinator.view else { throw VaultFailure(message: "Open the note and try again.") }
        guard !coordinator.parent.readOnly, view.markedTextRange == nil else { throw VaultFailure(message: "The note can't be edited right now. Try again in a moment.") }
        guard coordinator.lastMarkdown == expected else {
            throw VaultFailure(message: "The note changed while the suggestion was being reviewed. Run the action again.")
        }
        let value: NSAttributedString
        if coordinator.source {
            value = NSAttributedString(string: replacement, attributes: [.font: view.font ?? UIFont.monospacedSystemFont(ofSize: 17, weight: .regular), .foregroundColor: NativeThemeUIKit.text])
        } else {
            value = MarkdownText.render(replacement, images: coordinator.parent.images, width: view.bounds.width > 0 ? view.bounds.width - 44 : 350)
        }
        let caret = min(view.selectedRange.location, value.length)
        coordinator.apply(value, selection: NSRange(location: caret, length: 0), inverse: NSAttributedString(attributedString: view.attributedText))
        view.undoManager?.setActionName("AI Edit")
    }
}
