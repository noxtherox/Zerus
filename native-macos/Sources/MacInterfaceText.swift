import SwiftUI

/// Device-local interface text size. Unlike interface zoom, which scales the
/// whole canvas (controls, spacing and text together), this only resizes the
/// text of navigation, lists, panes, sheets and settings. Note content keeps
/// its own size (`zerus.mac.noteTextSize`).
enum MacInterfaceText {
    static let key = "zerus.mac.interfaceTextSize"
    static let options = [80, 90, 100, 110, 125, 150]
    static func validated(_ value: Int) -> Int { options.contains(value) ? value : 100 }
    static func factor(_ value: Int) -> CGFloat { CGFloat(validated(value)) / 100 }
    /// macOS's body size; text without an explicit font uses it.
    static let bodySize: CGFloat = 13
}

private struct MacTextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var macTextScale: CGFloat { get { self[MacTextScaleKey.self] } set { self[MacTextScaleKey.self] = newValue } }
}

/// Publish the chosen text scale and the matching default font to a window
/// or presentation root.
struct MacInterfaceTextHost: ViewModifier {
    @AppStorage(MacInterfaceText.key) private var percentage = 100
    func body(content: Content) -> some View {
        let scale = MacInterfaceText.factor(percentage)
        content.environment(\.macTextScale, scale).font(.system(size: MacInterfaceText.bodySize * scale))
    }
}

/// A SwiftUI font description that can be resolved at the interface text
/// scale. It mirrors the `Font` members the app uses so call sites read the
/// same: `.macFont(.caption.bold())`, `.macFont(.system(size: 12, weight: .medium))`.
struct MacFont {
    var size: CGFloat
    var weight: Font.Weight? = nil
    var design: Font.Design? = nil
    var isItalic = false
    var monospacedDigits = false

    static let largeTitle = MacFont(size: 26)
    static let title = MacFont(size: 22)
    static let title2 = MacFont(size: 17)
    static let title3 = MacFont(size: 15)
    static let headline = MacFont(size: 13, weight: .bold)
    static let body = MacFont(size: 13)
    static let callout = MacFont(size: 12)
    static let subheadline = MacFont(size: 11)
    static let footnote = MacFont(size: 10)
    static let caption = MacFont(size: 10)
    static let caption2 = MacFont(size: 10, weight: .medium)

    static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> MacFont {
        MacFont(size: size, weight: weight, design: design)
    }
    static func system(_ style: MacFont, design: Font.Design? = nil, weight: Font.Weight? = nil) -> MacFont {
        var font = style; if let design { font.design = design }; if let weight { font.weight = weight }; return font
    }

    func weight(_ weight: Font.Weight) -> MacFont { var font = self; font.weight = weight; return font }
    func bold() -> MacFont { weight(.bold) }
    func italic() -> MacFont { var font = self; font.isItalic = true; return font }
    func monospaced() -> MacFont { var font = self; font.design = .monospaced; return font }
    func monospacedDigit() -> MacFont { var font = self; font.monospacedDigits = true; return font }

    func resolved(_ scale: CGFloat) -> Font {
        var font = Font.system(size: size * scale, weight: weight ?? .regular, design: design ?? .default)
        if isItalic { font = font.italic() }
        if monospacedDigits { font = font.monospacedDigit() }
        return font
    }
}

private struct MacFontModifier: ViewModifier {
    let font: MacFont?
    @Environment(\.macTextScale) private var scale
    func body(content: Content) -> some View { content.font(font?.resolved(scale)) }
}

extension View {
    /// `font(_:)` at the interface text size.
    func macFont(_ font: MacFont?) -> some View { modifier(MacFontModifier(font: font)) }
}
