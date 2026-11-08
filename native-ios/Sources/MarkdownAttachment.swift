import UIKit

/// Bitmap-backed text tokens redraw for their containing editor's traits and
/// width without replacing its text, selection, marked input or Undo entries.
protocol AdaptiveTextAttachment: AnyObject {
    var presentationRevision: UInt64 { get }
    func refreshPresentation(width: CGFloat)
}

extension AdaptiveTextAttachment { var presentationRevision: UInt64 { 0 } }

protocol ImagePresentingTextAttachment: AdaptiveTextAttachment {
    func updateImages(_ images: [String: UIImage])
}

/// A native touch/accessibility control is positioned over this TextKit token.
/// The exact source stays attached through unrelated edits and Undo/Redo.
class MarkdownAttachment: NSTextAttachment {
    let markdown: String
    let editLabel: String
    let summary: String
    var edit: (() -> Void)?
    init(markdown: String, editLabel: String, summary: String) {
        self.markdown = markdown; self.editLabel = editLabel; self.summary = summary
        super.init(data: nil, ofType: nil)
    }
    required init?(coder: NSCoder) { return nil }
}

/// Image availability is presentation state, including while an IME owns marked
/// text. The containing view applies pending pixels at its next safe layout.
final class NativeImageAttachment: NSTextAttachment, ImagePresentingTextAttachment {
    let reference: String
    private let prose: Bool
    private var loadedImage: UIImage?
    private(set) var presentationRevision: UInt64 = 0
    init(reference: String, images: [String: UIImage], proseWidth: CGFloat?) {
        self.reference = reference; prose = proseWidth != nil
        super.init(data: nil, ofType: nil)
        updateImages(images); refreshPresentation(width: proseWidth ?? 160)
    }
    required init?(coder: NSCoder) { return nil }
    func updateImages(_ images: [String: UIImage]) {
        let next = images[reference] ?? URL(string: reference).flatMap { images[$0.relativeString] }
        guard next !== loadedImage else { return }
        loadedImage = next; presentationRevision &+= 1
    }
    func refreshPresentation(width availableWidth: CGFloat) {
        image = loadedImage ?? UIImage(systemName: "photo")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
        if prose {
            let available = max(100, min(availableWidth, 700)), size = loadedImage?.size ?? CGSize(width: 160, height: 100)
            let width = loadedImage == nil ? min(available, 180) : min(available, size.width)
            bounds = CGRect(x: 0, y: 0, width: width, height: width * size.height / max(size.width, 1))
        } else {
            let size = image?.size ?? CGSize(width: 80, height: 60), scale = min(1, 160 / max(size.width, size.height))
            bounds = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        }
    }
}

extension MarkdownText {
    static func imageIdentities(_ images: [String: UIImage]) -> [String: ObjectIdentifier] {
        images.mapValues(ObjectIdentifier.init)
    }
    static func refreshImageAttachments(in view: UITextView, images: [String: UIImage]) {
        guard let text = view.attributedText else { return }
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            (value as? ImagePresentingTextAttachment)?.updateImages(images)
        }
        view.setNeedsLayout()
    }
}
