import UIKit

/// Shared by writing and read-only previews. Presentation changes invalidate
/// TextKit layout without replacing attributed text or registering an edit.
class AdaptiveTextView: UITextView {
    var sourceMode = false { didSet { setNeedsLayout() } }
    private var presentationTraits: UITraitCollection?
    private var presentationWidth: CGFloat = -1
    private var presentedAttachments: [ObjectIdentifier: UInt64] = [:]

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        observePresentation()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); observePresentation() }
    private func observePresentation() {
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance +
            [NativeThemeTrait.self, UITraitPreferredContentSizeCategory.self, UITraitLegibilityWeight.self, UITraitDisplayScale.self]) {
            (view: AdaptiveTextView, _: UITraitCollection) in view.setNeedsLayout()
        }
    }
    override var bounds: CGRect {
        didSet { if abs(oldValue.width - bounds.width) > 0.5 { setNeedsLayout() } }
    }
    override var frame: CGRect {
        didSet { if abs(oldValue.width - frame.width) > 0.5 { setNeedsLayout() } }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !sourceMode, markedTextRange == nil, window != nil, let text = attributedText else { return }
        let width = max(140, min(700, bounds.width - textContainerInset.left - textContainerInset.right - 2 * textContainer.lineFragmentPadding))
        let traits = traitCollection
        let changed = presentationTraits.map {
            traits.hasDifferentColorAppearance(comparedTo: $0) || traits.preferredContentSizeCategory != $0.preferredContentSizeCategory ||
                traits.legibilityWeight != $0.legibilityWeight || traits.displayScale != $0.displayScale
        } ?? true
        let resized = abs(width - presentationWidth) > 0.5
        var identities: [ObjectIdentifier: UInt64] = [:]
        var refreshed = false
        traits.performAsCurrent {
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { item, _, _ in
                guard let attachment = item as? AdaptiveTextAttachment else { return }
                let identity = ObjectIdentifier(attachment); identities[identity] = attachment.presentationRevision
                if changed || resized || presentedAttachments[identity] != attachment.presentationRevision {
                    attachment.refreshPresentation(width: width); refreshed = true
                }
            }
        }
        presentationTraits = traits; presentationWidth = width; presentedAttachments = identities
        if refreshed, let manager = textLayoutManager, let range = manager.textContentManager?.documentRange {
            manager.invalidateLayout(for: range)
            setNeedsLayout()
        }
    }
}
