import UIKit

/// The marker occupies a TextKit glyph. ZerusTextView positions a native button
/// over that glyph, with at least a 44-point target and the item's accessible label.
@objc(ZerusChecklistAttachment)
final class ChecklistAttachment: NSTextAttachment, AdaptiveTextAttachment {
    let checked: Bool
    private(set) var taskLabel: String
    weak var button: UIButton?
    var toggle: (() -> Void)?

    init(checked: Bool, label: String) {
        self.checked = checked; taskLabel = label
        super.init(data: nil, ofType: nil)
        refreshPresentation(width: 0)
    }
    func refreshPresentation(width: CGFloat) {
        let size = UIFont.preferredFont(forTextStyle: .body, compatibleWith: .current).pointSize + 4
        image = UIImage(systemName: checked ? "checkmark.square.fill" : "square", withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular))?.withTintColor(checked ? NativeThemeUIKit.accent : .secondaryLabel, renderingMode: .alwaysOriginal)
        bounds = CGRect(x: 0, y: -4, width: size, height: size)
    }
    required init?(coder: NSCoder) {
        checked = coder.decodeBool(forKey: "checked")
        taskLabel = coder.decodeObject(of: NSString.self, forKey: "taskLabel") as String? ?? "Checklist item"
        super.init(coder: coder)
    }
    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(checked, forKey: "checked"); coder.encode(taskLabel, forKey: "taskLabel")
    }
    func updateLabel(_ label: String) {
        taskLabel = label
        button?.accessibilityLabel = (checked ? "Mark incomplete: " : "Complete: ") + label
    }
}
