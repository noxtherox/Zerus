import SwiftUI
import UIKit

enum NativeAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
}
enum NativeThemeSlot: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized + " theme" }
    var traits: UITraitCollection { UITraitCollection(userInterfaceStyle: self == .dark ? .dark : .light) }
}
enum NativeThemeRole: String, CaseIterable, Identifiable, Codable, Sendable {
    case accent, link, text, editorBg, surface, sidebarBg, sidebarFg
    var id: String { rawValue }
    var title: String {
        switch self { case .accent: "Accent"; case .link: "Links"; case .text: "Text"; case .editorBg: "Editor background"; case .surface: "List background"; case .sidebarBg: "Library background"; case .sidebarFg: "Library text" }
    }
    var hint: String {
        switch self { case .accent: "Pins, tags, selection and cursor"; case .link: "Note links, URLs and relations"; case .text: "Main editor and list text"; case .editorBg: "Writing surface, note cards and inputs"; case .surface: "Note list and panels"; case .sidebarBg: "Library navigation"; case .sidebarFg: "Library navigation labels" }
    }
}
struct NativeThemePalette: Codable, Equatable, Sendable {
    var accent: String
    var link: String
    var text: String
    var editorBg: String
    var surface: String
    var sidebarBg: String
    var sidebarFg: String
    subscript(_ role: NativeThemeRole) -> String {
        get { switch role { case .accent: accent; case .link: link; case .text: text; case .editorBg: editorBg; case .surface: surface; case .sidebarBg: sidebarBg; case .sidebarFg: sidebarFg } }
        set { switch role { case .accent: accent = newValue; case .link: link = newValue; case .text: text = newValue; case .editorBg: editorBg = newValue; case .surface: surface = newValue; case .sidebarBg: sidebarBg = newValue; case .sidebarFg: sidebarFg = newValue } }
    }
    static func hex(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^#(?:[a-fA-F0-9]{3}|[a-fA-F0-9]{6})$"#, options: .regularExpression) != nil else { return nil }
        let digits = String(value.dropFirst())
        return "#" + (digits.count == 3 ? digits.map { String(repeating: String($0), count: 2) }.joined() : digits).uppercased()
    }
    func validated() throws -> Self {
        var result = self
        for role in NativeThemeRole.allCases {
            guard let hex = Self.hex(self[role]) else { throw VaultFailure(message: "Choose a colour in #RGB or #RRGGBB format for \(role.title).") }
            result[role] = hex
        }
        return result
    }
    static func isDark(_ hex: String) -> Bool {
        guard let value = Self.hex(hex), let rgb = UInt32(value.dropFirst(), radix: 16) else { return false }
        let red = (rgb >> 16) & 255, green = (rgb >> 8) & 255, blue = rgb & 255
        return red * 299 + green * 587 + blue * 114 < 128_000
    }
    static func color(_ hex: String) -> UIColor {
        guard let hex = Self.hex(hex), let rgb = UInt32(hex.dropFirst(), radix: 16) else { return .clear }
        return UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
    static func hex(_ color: UIColor, traits: UITraitCollection) -> String? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let converted = color.resolvedColor(with: traits).cgColor.converted(to: space, intent: .defaultIntent, options: nil), let values = converted.components, values.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", arguments: values.prefix(3).map { Int((max(0, min(1, $0)) * 255).rounded()) })
    }
    static func nativeDefaults(_ slot: NativeThemeSlot) -> Self {
        func hex(_ role: NativeThemeRole) -> String { Self.hex(NativeThemeUIKit.fallback(role, traits: slot.traits), traits: slot.traits)! }
        return .init(accent: hex(.accent), link: hex(.link), text: hex(.text), editorBg: hex(.editorBg), surface: hex(.surface), sidebarBg: hex(.sidebarBg), sidebarFg: hex(.sidebarFg))
    }
}
struct NativeThemePalettes: Codable, Equatable, Sendable {
    var lightTheme: NativeThemePalette?
    var darkTheme: NativeThemePalette?
    subscript(_ slot: NativeThemeSlot) -> NativeThemePalette? {
        get { slot == .dark ? darkTheme : lightTheme }
        set { if slot == .dark { darkTheme = newValue } else { lightTheme = newValue } }
    }
    func palette(_ traits: UITraitCollection) -> NativeThemePalette? { traits.userInterfaceStyle == .dark ? darkTheme : lightTheme }
}
struct NativeNamedTheme: Codable, Equatable, Identifiable {
    let name: String
    let theme: NativeThemePalette
    var id: String { name.lowercased() }
}

/// Shared storage lets SwiftUI and UIKit resolve exactly the same palette.
/// UIKit invalidates dynamic colours and attachment presentation without
/// replacing attributed text, moving the caret or adding an Undo operation.
struct NativeThemeTrait: UITraitDefinition {
    static let defaultValue = NativeThemePalettes()
    static let affectsColorAppearance = true
    static let identifier = "com.zerus.notes.native.palette"
}
private struct NativeThemeEnvironmentKey: UITraitBridgedEnvironmentKey {
    static let defaultValue = NativeThemePalettes()
    static func read(from traitCollection: UITraitCollection) -> NativeThemePalettes { traitCollection[NativeThemeTrait.self] }
    static func write(to mutableTraits: inout any UIMutableTraits, value: NativeThemePalettes) { mutableTraits[NativeThemeTrait.self] = value }
}
extension EnvironmentValues {
    var nativeThemes: NativeThemePalettes {
        get { self[NativeThemeEnvironmentKey.self] }
        set { self[NativeThemeEnvironmentKey.self] = newValue }
    }
}
enum NativeThemeUIKit {
    static func fallback(_ role: NativeThemeRole, traits: UITraitCollection) -> UIColor {
        switch role {
        case .accent, .link:
            return traits.userInterfaceStyle == .dark ? UIColor(red: 0.9, green: 0.6, blue: 0.35, alpha: 1) : UIColor(red: 0.66, green: 0.35, blue: 0.18, alpha: 1)
        case .text, .sidebarFg: return UIColor.label.resolvedColor(with: traits)
        case .editorBg: return UIColor.systemBackground.resolvedColor(with: traits)
        case .surface, .sidebarBg: return UIColor.systemGroupedBackground.resolvedColor(with: traits)
        }
    }
    static func color(_ role: NativeThemeRole) -> UIColor {
        UIColor { traits in
            if let palette = traits[NativeThemeTrait.self].palette(traits) { return NativeThemePalette.color(palette[role]) }
            return fallback(role, traits: traits)
        }
    }
    static let accent = color(.accent), link = color(.link), text = color(.text), editor = color(.editorBg), surface = color(.surface), sidebar = color(.sidebarBg), sidebarText = color(.sidebarFg)
    static let secondaryText = UIColor { traits in text.resolvedColor(with: traits).withAlphaComponent(0.72) }
    static let card = UIColor { traits in
        traits[NativeThemeTrait.self].palette(traits).map { NativeThemePalette.color($0.editorBg) } ?? UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
    }
    static let sidebarCard = UIColor { traits in
        traits[NativeThemeTrait.self].palette(traits).map { NativeThemePalette.color($0.sidebarBg) } ?? UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
    }
    static let relation = UIColor { traits in
        traits[NativeThemeTrait.self].palette(traits).map { NativeThemePalette.color($0.link) } ?? UIColor.secondaryLabel.resolvedColor(with: traits)
    }
    static let revisionBackground = UIColor { traits in
        traits[NativeThemeTrait.self].palette(traits).map { NativeThemePalette.color($0.editorBg) } ?? .clear
    }
    static let tableHeader = UIColor { traits in
        guard let palette = traits[NativeThemeTrait.self].palette(traits) else { return UIColor.tertiarySystemGroupedBackground.resolvedColor(with: traits) }
        let background = NativeThemePalette.color(palette.editorBg).cgColor.components!, foreground = NativeThemePalette.color(palette.text).cgColor.components!
        return UIColor(red: background[0] * 0.94 + foreground[0] * 0.06, green: background[1] * 0.94 + foreground[1] * 0.06, blue: background[2] * 0.94 + foreground[2] * 0.06, alpha: 1)
    }
    static let codeSurface = UIColor { traits in
        traits[NativeThemeTrait.self].palette(traits).map { NativeThemePalette.color($0.surface) } ?? UIColor.secondarySystemBackground.resolvedColor(with: traits)
    }
}

@MainActor
final class NativeAppearanceStore: ObservableObject {
    static let shared = NativeAppearanceStore()
    static let modeKey = "zerus.native.appearance"
    static let palettesKey = "zerus.native.theme-palettes"
    static let savedKey = "zerus.native.saved-themes"
    @Published private(set) var mode: NativeAppearanceMode
    @Published private(set) var palettes = NativeThemePalettes()
    @Published private(set) var saved: [NativeNamedTheme] = []
    @Published private(set) var paletteIssue: String?
    @Published private(set) var savedIssue: String?
    @Published private(set) var undoName: String?
    private let defaults: UserDefaults
    private var deletedRows: [(Int, Any)] = []
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults; mode = NativeAppearanceMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "system") ?? .system
        if let object = defaults.object(forKey: Self.palettesKey) {
            do {
                guard let data = object as? Data else { throw VaultFailure(message: "Unsupported palette storage.") }
                var value = try JSONDecoder().decode(NativeThemePalettes.self, from: data)
                value.lightTheme = try value.lightTheme?.validated(); value.darkTheme = try value.darkTheme?.validated(); palettes = value
            } catch { paletteIssue = "Saved appearance could not be read. Its original data is kept. Reset appearance to return to native defaults." }
        }
        reloadSaved()
    }
    func setMode(_ value: NativeAppearanceMode) {
        mode = value
        if value == .system { defaults.removeObject(forKey: Self.modeKey) } else { defaults.set(value.rawValue, forKey: Self.modeKey) }
    }
    func setPalette(_ value: NativeThemePalette, slot: NativeThemeSlot) throws {
        guard paletteIssue == nil else { throw VaultFailure(message: paletteIssue!) }
        let valid = try value.validated(); var next = palettes; next[slot] = valid
        let bytes = try JSONEncoder().encode(next); defaults.set(bytes, forKey: Self.palettesKey); palettes = next
    }
    func reset() {
        defaults.removeObject(forKey: Self.palettesKey); paletteIssue = nil; palettes = .init(); setMode(.system)
    }
    private func rows() throws -> [Any] {
        guard let object = defaults.object(forKey: Self.savedKey) else { return [] }
        guard let bytes = object as? Data, let rows = try JSONSerialization.jsonObject(with: bytes) as? [Any] else { throw VaultFailure(message: "Saved themes use an unsupported format. Their original data is kept.") }
        return rows
    }
    private func named(_ object: Any) -> NativeNamedTheme? {
        guard let row = object as? [String: Any], let name = row["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 40,
              let bytes = try? JSONSerialization.data(withJSONObject: row), let value = try? JSONDecoder().decode(NativeNamedTheme.self, from: bytes), let theme = try? value.theme.validated() else { return nil }
        return .init(name: name.trimmingCharacters(in: .whitespacesAndNewlines), theme: theme)
    }
    private func same(_ a: String, _ b: String) -> Bool { a.compare(b, options: [.caseInsensitive]) == .orderedSame }
    private func writeRows(_ rows: [Any]) throws {
        if rows.isEmpty { defaults.removeObject(forKey: Self.savedKey) }
        else { defaults.set(try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .withoutEscapingSlashes]), forKey: Self.savedKey) }
        reloadSaved()
    }
    private func reloadSaved() {
        do {
            let rows = try rows(); var values: [NativeNamedTheme] = []
            for row in rows { if let value = named(row), !values.contains(where: { same($0.name, value.name) }) { values.append(value) } }
            saved = values; savedIssue = values.count == rows.count ? nil : "Some saved themes could not be read or have duplicate names. Their original entries are kept."
        } catch { saved = []; savedIssue = error.localizedDescription }
    }
    func save(_ name: String, theme: NativeThemePalette) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, !name.contains(where: { $0.isNewline }), !NativeThemePresets.all.contains(where: { same($0.name, name) }) else { throw VaultFailure(message: "Choose a theme name of up to 40 characters, different from the built-in presets.") }
        let value = NativeNamedTheme(name: name, theme: try theme.validated()); var rows = try rows()
        var next = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        let matches = rows.indices.filter { index in
            guard let stored = (rows[index] as? [String: Any])?["name"] as? String else { return false }
            return same(stored.trimmingCharacters(in: .whitespacesAndNewlines), name)
        }
        guard matches.allSatisfy({ named(rows[$0]) != nil }) else { throw VaultFailure(message: "A saved entry with this name uses an unsupported format. Choose another name; its original data is kept.") }
        if let first = matches.first {
            var original = rows[first] as! [String: Any]; original.merge(next) { _, value in value }; next = original
            rows[first] = next; for index in matches.dropFirst().reversed() { rows.remove(at: index) }
        } else { rows.append(next) }
        try writeRows(rows)
    }
    func delete(_ theme: NativeNamedTheme) throws {
        var rows = try rows(); let matches = rows.indices.filter { named(rows[$0]).map { same($0.name, theme.name) } == true }
        guard !matches.isEmpty else { throw VaultFailure(message: "This saved theme changed. Reopen Appearance.") }
        deletedRows = matches.map { ($0, rows[$0]) }; undoName = theme.name
        for index in matches.reversed() { rows.remove(at: index) }; try writeRows(rows)
    }
    func undoDelete() throws {
        guard let undoName else { return }; var rows = try rows()
        guard !rows.contains(where: { named($0).map { same($0.name, undoName) } == true }) else { throw VaultFailure(message: "A theme with that name was saved again. Rename it before restoring the deleted theme.") }
        for (index, value) in deletedRows { rows.insert(value, at: min(index, rows.count)) }
        try writeRows(rows); self.undoName = nil; deletedRows = []
    }
}


struct NativeAppearancePresentation: ViewModifier {
    @ObservedObject var appearance: NativeAppearanceStore
    func body(content: Content) -> some View {
        content.tint(Accent.color)
            .background(NativeAppearanceWindowBridge(palettes: appearance.palettes).allowsHitTesting(false))
            .preferredColorScheme(appearance.mode.colorScheme)
            .environment(\.nativeThemes, appearance.palettes)
    }
}

/// Presented controllers inherit from the window, rather than from a SwiftUI
/// view's local bridged trait. Keep the palette on that shared native boundary
/// so sheets, popovers and UIKit controls use the same colours as the root.
private struct NativeAppearanceWindowBridge: UIViewRepresentable {
    let palettes: NativeThemePalettes
    func makeUIView(context: Context) -> PaletteWindowView { PaletteWindowView() }
    func updateUIView(_ view: PaletteWindowView, context: Context) { view.palettes = palettes; view.apply() }
    final class PaletteWindowView: UIView {
        var palettes = NativeThemePalettes()
        override func didMoveToWindow() { super.didMoveToWindow(); apply() }
        func apply() {
            guard let window, window.traitCollection[NativeThemeTrait.self] != palettes else { return }
            window.traitOverrides[NativeThemeTrait.self] = palettes
        }
    }
}
