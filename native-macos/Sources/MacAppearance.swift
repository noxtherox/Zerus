import SwiftUI
import AppKit

enum MacThemeRole: String, CaseIterable, Identifiable, Codable, Hashable {
    case accent, link, text, editorBg, surface, sidebarBg, sidebarFg
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accent: "Accent"
        case .link: "Links"
        case .text: "Editor and list text"
        case .editorBg: "Editor background"
        case .surface: "List background"
        case .sidebarBg: "Sidebar background"
        case .sidebarFg: "Sidebar text"
        }
    }
    var fallback: NSColor {
        switch self {
        case .accent, .link: MacMarkdown.accent
        case .text, .sidebarFg: .labelColor
        case .editorBg: .textBackgroundColor
        case .surface: .controlBackgroundColor
        case .sidebarBg: .windowBackgroundColor
        }
    }
}

struct MacThemePalette: Codable, Equatable {
    var colors: [MacThemeRole: String]
    var additionalColors: [String: String] = [:]
    private enum CodingKeys: String, CodingKey { case colors }
    init(colors: [MacThemeRole: String]) { self.colors = colors }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let values: [String: String]
        if let object = try? container.decode([String: String].self, forKey: .colors) { values = object }
        else {
            // Accept the alternating-key/value representation written by the
            // earliest development builds, without rejecting future role names.
            let array = try container.decode([String].self, forKey: .colors)
            guard array.count % 2 == 0 else { throw VaultFailure(message: "The saved palette is incomplete.") }
            var object: [String: String] = [:]
            for index in stride(from: 0, to: array.count, by: 2) { object[array[index]] = array[index + 1] }
            values = object
        }
        colors = [:]
        for (key, value) in values {
            if let role = MacThemeRole(rawValue: key) { colors[role] = value }
            else { additionalColors[key] = value }
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self), values = additionalColors
        for (role, value) in colors { values[role.rawValue] = value }
        try container.encode(values, forKey: .colors)
    }
    static func hex(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", options: .regularExpression) != nil else { return nil }
        let digits = String(value.dropFirst())
        return "#" + (digits.count == 3 ? digits.map { String(repeating: String($0), count: 2) }.joined() : digits).uppercased()
    }
    static func hex(_ color: NSColor) -> String? {
        guard let color = color.usingColorSpace(.sRGB) else { return nil }
        let values = [color.redComponent, color.greenComponent, color.blueComponent]
        return String(format: "#%02X%02X%02X", arguments: values.map { Int((max(0, min(1, $0)) * 255).rounded()) })
    }
    func validated() throws -> Self {
        var result = self
        for role in MacThemeRole.allCases {
            guard let input = colors[role] else { continue }
            guard let value = Self.hex(input) else { throw VaultFailure(message: "Enter #RGB or #RRGGBB for \(role.title).") }
            result.colors[role] = value
        }
        return result
    }
    func color(_ role: MacThemeRole) -> NSColor {
        guard let hex = colors[role].flatMap(Self.hex), let rgb = UInt32(hex.dropFirst(), radix: 16) else { return role.fallback }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
    static func defaults(dark: Bool) -> Self {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var colors: [MacThemeRole: String] = [:]
        appearance.performAsCurrentDrawingAppearance {
            for role in MacThemeRole.allCases {
                let color = role.fallback.usingColorSpace(.sRGB)!
                let surface = (role == .sidebarFg ? NSColor.windowBackgroundColor : NSColor.textBackgroundColor).usingColorSpace(.sRGB)!
                func byte(_ value: CGFloat, _ background: CGFloat) -> Int { Int(((value * color.alphaComponent + background * (1 - color.alphaComponent)) * 255).rounded()) }
                colors[role] = String(format: "#%02X%02X%02X", byte(color.redComponent, surface.redComponent), byte(color.greenComponent, surface.greenComponent), byte(color.blueComponent, surface.blueComponent))
            }
        }
        return .init(colors: colors)
    }
}

struct MacNamedTheme: Codable, Equatable, Identifiable {
    var name: String
    var palette: MacThemePalette
    var id: String { name.lowercased() }
}

/// One local preferences record. Unsupported or damaged records are retained
/// until the user explicitly resets them; editing never silently discards them.
struct MacThemePreferences: Codable, Equatable {
    var version = 1
    var lightTheme: MacThemePalette?
    var darkTheme: MacThemePalette?
    var saved: [MacNamedTheme] = []
    static func decode(_ string: String) throws -> Self {
        if string.isEmpty { return Self() }
        guard let data = string.data(using: .utf8) else { throw VaultFailure(message: "The saved colour settings cannot be read.") }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1 else { throw VaultFailure(message: "These colour settings use an unsupported version. The original settings have been preserved.") }
        _ = try result.lightTheme?.validated(); _ = try result.darkTheme?.validated()
        var names: Set<String> = []
        for theme in result.saved {
            _ = try theme.palette.validated()
            let name = try checkedName(theme.name)
            guard names.insert(name.lowercased()).inserted else { throw VaultFailure(message: "Saved theme names must be unique.") }
        }
        return result
    }
    func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        let string = String(decoding: data, as: UTF8.self)
        _ = try Self.decode(string)
        return string
    }
    static func checkedName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw VaultFailure(message: "Use a theme name of 1–80 characters without line breaks.") }
        return name
    }
    mutating func save(name: String, palette: MacThemePalette, replacing: Bool = false) throws {
        let name = try Self.checkedName(name)
        guard !MacThemePresets.all.contains(where: { $0.id == name.lowercased() }) else { throw VaultFailure(message: "Choose a name different from a built-in theme.") }
        let value = MacNamedTheme(name: name, palette: try palette.validated())
        if let index = saved.firstIndex(where: { $0.id == name.lowercased() }) {
            guard replacing else { throw VaultFailure(message: "A theme with that name already exists. Choose another name.") }
            saved[index] = value
        } else { saved.append(value) }
    }
}

struct MacTheme: Equatable {
    var palette: MacThemePalette?
    func nsColor(_ role: MacThemeRole) -> NSColor { palette?.color(role) ?? role.fallback }
    func color(_ role: MacThemeRole) -> Color { Color(nsColor: nsColor(role)) }
}

/// Existing attributed strings, typing attributes and Undo snapshots share these
/// dynamic colours. Updating a palette invalidates display, not document layout.
final class MacEditorThemeColors {
    private var current = MacTheme()
    private let lock = NSLock()
    var theme: MacTheme {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }
    private lazy var text = dynamic(.text)
    private lazy var link = dynamic(.link)
    func color(_ role: MacThemeRole) -> NSColor { role == .link ? link : text }
    private func dynamic(_ role: MacThemeRole) -> NSColor {
        NSColor(name: nil) { [weak self] appearance in
            let chosen = self?.theme.nsColor(role) ?? role.fallback
            var resolved = chosen
            appearance.performAsCurrentDrawingAppearance { resolved = chosen.usingColorSpace(.sRGB) ?? chosen }
            return resolved
        }
    }
}
private struct MacThemeKey: EnvironmentKey { static let defaultValue = MacTheme() }
extension EnvironmentValues {
    var macTheme: MacTheme { get { self[MacThemeKey.self] } set { self[MacThemeKey.self] = newValue } }
}
struct MacThemeHost: ViewModifier {
    @AppStorage("zerus.mac.themes") private var serialized = ""
    @AppStorage("zerus.mac.appearance") private var appearance = "light"
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let preferences = try? MacThemePreferences.decode(serialized)
        let dark = appearance == "dark" || appearance != "light" && scheme == .dark
        let theme = MacTheme(palette: dark ? preferences?.darkTheme : preferences?.lightTheme)
        content.environment(\.macTheme, theme).tint(theme.color(.accent))
            .toolbarBackground(theme.color(.sidebarBg), for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .background(MacThemeWindowBackground(color: theme.nsColor(.sidebarBg)).frame(width: 0, height: 0))
    }
}

/// Keep AppKit's title bar on the same opaque surface as the themed toolbar.
/// The probe also applies when SwiftUI attaches a newly created window, and
/// locks the toolbar display mode so right-clicking it shows no menu.
private struct MacThemeWindowBackground: NSViewRepresentable {
    let color: NSColor
    func makeNSView(context: Context) -> Probe { Probe(color: color) }
    func updateNSView(_ view: Probe, context: Context) { view.color = color; view.apply() }
    final class Probe: NSView {
        var color: NSColor
        init(color: NSColor) { self.color = color; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply(); DispatchQueue.main.async { [weak self] in self?.apply() } }
        func apply() {
            window?.titlebarAppearsTransparent = true
            window?.backgroundColor = color
            // The toolbar is icon-only by design; hide AppKit's "Icon and Text / Icon Only" context menu.
            if let toolbar = window?.toolbar { toolbar.allowsDisplayModeCustomization = false; toolbar.displayMode = .iconOnly }
        }
    }
}

struct MacThemeSettingsView: View {
    @AppStorage("zerus.mac.themes") private var serialized = ""
    @AppStorage("zerus.mac.appearance") private var appearance = "light"
    @State private var dark = false
    @State private var draft = MacThemePalette.defaults(dark: false)
    @State private var name = ""
    @State private var issue: String?
    @State private var unreadable = false
    @FocusState private var focusedRole: MacThemeRole?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    private var replacing: Bool { ((try? MacThemePreferences.decode(serialized))?.saved ?? []).contains { $0.id == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Colours").font(.title2.bold())
            Text("Light and dark palettes are separate. System appearance follows your Mac. Changes apply to all Zerus windows.").foregroundStyle(.secondary)
            Picker("Palette", selection: Binding(get: { dark }, set: { dark = $0; load() })) { Text("Light").tag(false); Text("Dark").tag(true) }.pickerStyle(.segmented).disabled(unreadable)
            HStack {
                Menu("Load preset") { ForEach(MacThemePresets.all) { preset in Button(preset.name) { apply(preset.palette) } } }
                Text("Presets also select light or dark appearance.").font(.caption).foregroundStyle(.secondary)
            }.disabled(unreadable)
            Form {
                ForEach(MacThemeRole.allCases) { role in
                    HStack {
                        Text(role.title).frame(width: 160, alignment: .leading)
                        ColorPicker(role.title, selection: Binding(get: { Color(nsColor: savedPalette.color(role)) }, set: { color in
                            if let hex = MacThemePalette.hex(NSColor(color)) { change(role, input: hex) }
                            else { issue = "This colour cannot be represented in sRGB. Choose another colour." }
                        }), supportsOpacity: false).labelsHidden().frame(width: 36).accessibilityLabel(role.title)
                        TextField("#RRGGBB", text: Binding(get: { draft.colors[role] ?? MacThemePalette.defaults(dark: dark).colors[role] ?? "" }, set: { change(role, input: $0) })).font(.system(.body, design: .monospaced)).accessibilityLabel(role.title).focused($focusedRole, equals: role).onSubmit { restoreField(role) }
                    }
                }
            }.disabled(unreadable)
            HStack {
                Button("Use Mac defaults") { perform { var preferences = try MacThemePreferences.decode(serialized); if dark { preferences.darkTheme = nil } else { preferences.lightTheme = nil }; serialized = try preferences.encoded(); draft = .defaults(dark: dark) } }
            }.disabled(unreadable)
            Divider()
            HStack { TextField("Theme name", text: $name); Button(replacing ? "Update palette" : "Save palette") { perform { var preferences = try MacThemePreferences.decode(serialized); try preferences.save(name: name, palette: savedPalette, replacing: replacing); serialized = try preferences.encoded(); name = "" } } }.disabled(unreadable)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach((try? MacThemePreferences.decode(serialized))?.saved ?? []) { theme in
                        HStack { Text(theme.name); Spacer(); Button("Load") { apply(theme.palette) }; Button("Delete") { perform { var preferences = try MacThemePreferences.decode(serialized); preferences.saved.removeAll { $0.id == theme.id }; serialized = try preferences.encoded() } } }
                    }
                }
            }.frame(maxHeight: 100)
            Text("Loading a preset or saved palette selects its matching appearance, including window controls. Incomplete hex text resets when you leave its field.").font(.caption).foregroundStyle(.secondary)
            if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
            if unreadable { Button("Reset unreadable colour settings") { serialized = ""; load() } }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 530).onAppear { dark = appearance == "dark" || appearance != "light" && scheme == .dark; load() }
            .onChange(of: serialized) { _, _ in load(keepingFocusedInput: true) }
            .onChange(of: focusedRole) { previous, next in if previous != next, let previous { restoreField(previous) } }
    }
    private func perform(_ action: () throws -> Void) { do { try action(); issue = nil } catch { issue = error.localizedDescription } }
    private var savedPalette: MacThemePalette {
        let preferences = try? MacThemePreferences.decode(serialized)
        return (dark ? preferences?.darkTheme : preferences?.lightTheme) ?? .defaults(dark: dark)
    }
    private func change(_ role: MacThemeRole, input: String) {
        draft.colors[role] = input
        guard let hex = MacThemePalette.hex(input) else { return }
        perform {
            var preferences = try MacThemePreferences.decode(serialized)
            var palette = (dark ? preferences.darkTheme : preferences.lightTheme) ?? .defaults(dark: dark)
            palette.colors[role] = hex
            if dark { preferences.darkTheme = palette } else { preferences.lightTheme = palette }
            serialized = try preferences.encoded()
        }
    }
    private func apply(_ chosen: MacThemePalette) {
        perform {
            var preferences = try MacThemePreferences.decode(serialized)
            let hasBackground = chosen.colors[.surface] != nil || chosen.colors[.editorBg] != nil
            var targetDark = dark
            if hasBackground, let background = chosen.color(chosen.colors[.surface] != nil ? .surface : .editorBg).usingColorSpace(.sRGB) {
                targetDark = 0.2126 * background.redComponent + 0.7152 * background.greenComponent + 0.0722 * background.blueComponent < 0.5
            }
            var palette = (targetDark ? preferences.darkTheme : preferences.lightTheme) ?? .defaults(dark: targetDark)
            palette.colors.merge(chosen.colors) { _, new in new }
            palette.additionalColors.merge(chosen.additionalColors) { _, new in new }
            palette = try palette.validated()
            if targetDark { preferences.darkTheme = palette } else { preferences.lightTheme = palette }
            dark = targetDark
            serialized = try preferences.encoded(); draft = palette
            if hasBackground { appearance = targetDark ? "dark" : "light" }
        }
    }
    private func restoreField(_ role: MacThemeRole) { draft.colors[role] = savedPalette.colors[role] ?? MacThemePalette.defaults(dark: dark).colors[role] }
    private func load(keepingFocusedInput: Bool = false) {
        do {
            let preferences = try MacThemePreferences.decode(serialized)
            var palette = (dark ? preferences.darkTheme : preferences.lightTheme) ?? .defaults(dark: dark)
            if keepingFocusedInput, let role = focusedRole, let input = draft.colors[role] { palette.colors[role] = input }
            draft = palette; unreadable = false; issue = nil
        } catch { unreadable = true; issue = "Colour settings could not be read and have been preserved. \(error.localizedDescription)" }
    }
}
