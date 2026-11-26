import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacDesktopSettingsSnapshot: Decodable {
    struct Vault: Decodable {
        let name: String
        let defaultNoteFolder: String
        let folderOrder: [String]
        let keptOpenFolders: [String]
        let hideSubtypeNotes: Bool
    }
    let vault: Vault?
    struct Named: Decodable { let name: String; let theme: [String: String] }
    struct Settings: Decodable {
        let dateFormat: String
        let interfaceZoom: Int
        let noteWidth: Int
        let noteAlignment: String
        let codeBlocks: Bool
        let noteLinkShortcuts: Bool
        let appearance: String
        let lightTheme: [String: String]
        let darkTheme: [String: String]
        let savedThemes: [Named]
    }
    let format: String
    let version: Int
    let settings: Settings
    static func read(_ data: Data) throws -> Self {
        guard data.count <= 256 * 1024 else { throw VaultFailure(message: "Choose a desktop settings export smaller than 256 KB.") }
        let value = try JSONDecoder().decode(Self.self, from: data), s = value.settings
        guard value.format == "zerus-desktop-settings", value.version == 1 else { throw VaultFailure(message: "This is not a supported Zerus desktop settings export.") }
        guard MacNumericDateFormat(rawValue: s.dateFormat) != nil, MacInterfaceZoom.options.contains(s.interfaceZoom), MacNoteLayout.widths.contains(s.noteWidth), ["left", "center"].contains(s.noteAlignment), ["light", "dark", "system"].contains(s.appearance), s.savedThemes.count <= 100 else { throw VaultFailure(message: "The export contains unsupported desktop settings. Nothing was changed.") }
        _ = try palette(s.lightTheme); _ = try palette(s.darkTheme)
        var names: Set<String> = []
        for theme in s.savedThemes {
            let name = try MacThemePreferences.checkedName(theme.name)
            guard names.insert(name.lowercased()).inserted else { throw VaultFailure(message: "The export contains duplicate saved theme names.") }
            _ = try palette(theme.theme)
        }
        if let v = value.vault {
            guard !v.name.isEmpty, v.name.utf8.count <= 1024, v.folderOrder.count <= 2000, v.keptOpenFolders.count <= 2000,
                  ([v.defaultNoteFolder] + v.folderOrder + v.keptOpenFolders).allSatisfy({ MacNewNotePreferences.ordinary($0) && $0.utf8.count <= 2048 }) else { throw VaultFailure(message: "The export contains invalid vault preferences. Nothing was changed.") }
        }
        return value
    }
    static func palette(_ values: [String: String]) throws -> MacThemePalette {
        var palette = MacThemePalette(colors: [:])
        for role in MacThemeRole.allCases {
            guard let raw = values[role.rawValue], let hex = MacThemePalette.hex(raw) else { throw VaultFailure(message: "The export contains an incomplete or invalid colour palette.") }
            palette.colors[role] = hex
        }
        return palette
    }
}

/// A vault-bearing export is deliberately bound to the open destination, not
/// to a path embedded in the file. All guards run before any preferences change.
@MainActor struct MacVaultSettingsReview {
    let source: MacDesktopSettingsSnapshot.Vault
    let destination: String
    let missing: [String]
    private let workspace: MacWorkspace.Weak
    private let stamp: Data
    init(_ source: MacDesktopSettingsSnapshot.Vault, workspace: MacWorkspace) throws {
        self.source = source; self.workspace = .init(workspace)
        destination = try workspace.vaultSettingsDestination()
        stamp = try workspace.vaultSettingsStamp()
        missing = (source.folderOrder + source.keptOpenFolders).filter { path in !workspace.folders.contains { MacFolderOrdering.samePath($0, path) } }
    }
    func validate() throws {
        guard let store = workspace.value, try store.vaultSettingsStamp() == stamp else { throw VaultFailure(message: "The destination vault or its preferences changed after review. Import the file again; nothing was replaced.") }
    }
    func applyValidated() { workspace.value?.applyImportedVaultPreferences(source) }
}

@MainActor struct MacDesktopSettingsReview: Identifiable {
    let id = UUID()
    let name: String
    let snapshot: MacDesktopSettingsSnapshot
    private let before: Data
    private let themes: String
    let vaultReview: MacVaultSettingsReview?
    static let keys = ["dateFormat", "interfaceZoom", "noteWidth", "noteAlignment", "codeBlocks", "noteLinkShortcuts", "appearance", "themes"].map { "zerus.mac." + $0 }
    private static func observed(_ defaults: UserDefaults) throws -> Data {
        try JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0) ?? NSNull()) }), options: [.sortedKeys])
    }
    init(data: Data, name: String, defaults: UserDefaults = .standard, workspace: MacWorkspace? = nil) throws {
        snapshot = try .read(data); self.name = name; before = try Self.observed(defaults)
        if let vault = snapshot.vault {
            guard let workspace else { throw VaultFailure(message: "Open the destination vault before importing vault settings.") }
            vaultReview = try MacVaultSettingsReview(vault, workspace: workspace)
        } else { vaultReview = nil }
        var merged = try MacThemePreferences.decode(defaults.string(forKey: "zerus.mac.themes") ?? "")
        let light = try MacDesktopSettingsSnapshot.palette(snapshot.settings.lightTheme), dark = try MacDesktopSettingsSnapshot.palette(snapshot.settings.darkTheme)
        var newLight = light, newDark = dark
        newLight.additionalColors = merged.lightTheme?.additionalColors ?? [:]; newDark.additionalColors = merged.darkTheme?.additionalColors ?? [:]
        merged.lightTheme = newLight; merged.darkTheme = newDark
        for theme in snapshot.settings.savedThemes {
            var palette = try MacDesktopSettingsSnapshot.palette(theme.theme)
            let name = try MacThemePreferences.checkedName(theme.name)
            if let index = merged.saved.firstIndex(where: { $0.id == name.lowercased() }) {
                palette.additionalColors = merged.saved[index].palette.additionalColors
                merged.saved[index] = .init(name: name, palette: palette)
            } else { merged.saved.append(.init(name: name, palette: palette)) }
        }
        themes = try merged.encoded()
    }
    func apply(defaults: UserDefaults = .standard) throws {
        guard try Self.observed(defaults) == before else { throw VaultFailure(message: "Desktop settings changed after review. Import the file again to review the latest settings; nothing was replaced.") }
        try vaultReview?.validate()
        let s = snapshot.settings
        let values: [String: Any] = ["dateFormat": s.dateFormat, "interfaceZoom": s.interfaceZoom, "noteWidth": s.noteWidth, "noteAlignment": s.noteAlignment, "codeBlocks": s.codeBlocks, "noteLinkShortcuts": s.noteLinkShortcuts, "appearance": s.appearance, "themes": themes]
        for (key, value) in values { defaults.set(value, forKey: "zerus.mac." + key) }
        vaultReview?.applyValidated()
    }
}

extension MacWorkspace {
    func importDesktopSettings() {
        guard !busy, !preparingToClose, !editorSheetActive else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "Choose the file from Export desktop settings in Zerus."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let lease = try NativeFileLease(scope: url)
            let size = try lease.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 256 * 1024 else { throw VaultFailure(message: "Choose a desktop settings export smaller than 256 KB.") }
            settingsImport = try .init(data: Data(contentsOf: lease.url), name: url.lastPathComponent, workspace: self)
            editorSheetActive = true
        } catch { issue = error.localizedDescription }
    }
}

struct MacDesktopSettingsImportView: View {
    let review: MacDesktopSettingsReview
    @Environment(\.dismiss) private var dismiss
    @State private var issue: String?
    var body: some View {
        let s = review.snapshot.settings
        VStack(alignment: .leading, spacing: 16) {
            Text("Import desktop settings").macFont(.title2.bold())
            Text(review.name).macFont(.caption).foregroundStyle(.secondary)
            Text("Apply these preferences on this Mac. Current editor text and vault files are kept.")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let vault = review.vaultReview {
                        Text("Vault preferences: " + vault.source.name + " → " + vault.destination).macFont(.headline)
                        LabeledContent("Default folder", value: vault.source.defaultNoteFolder)
                        Text("Folder order: " + vault.source.folderOrder.joined(separator: ", ")).macFont(.caption)
                        Text("Keep open: " + vault.source.keptOpenFolders.joined(separator: ", ")).macFont(.caption)
                        LabeledContent("Hide subtype notes", value: vault.source.hideSubtypeNotes ? "On" : "Off")
                        if !vault.missing.isEmpty { Text("Absent folders are skipped for order and keep-open: " + vault.missing.joined(separator: ", ")).macFont(.caption).foregroundStyle(.secondary) }
                        Text("Tabs, current filters and editor drafts are kept. The default folder may be created when you next make a note.").macFont(.caption).foregroundStyle(.secondary)
                        Divider()
                    }
                    LabeledContent("Appearance", value: s.appearance.capitalized)
                    LabeledContent("Date format", value: s.dateFormat)
                    LabeledContent("Interface zoom", value: "\(s.interfaceZoom)%")
                    LabeledContent("Writing width", value: "\(s.noteWidth)%")
                    LabeledContent("Column alignment", value: s.noteAlignment.capitalized)
                    LabeledContent("Code blocks", value: s.codeBlocks ? "On" : "Off")
                    LabeledContent("Note link shortcuts", value: s.noteLinkShortcuts ? "On" : "Off")
                    ForEach([("Light colours", s.lightTheme), ("Dark colours", s.darkTheme)], id: \.0) { label, values in
                        HStack { Text(label); Spacer(); ForEach(MacThemeRole.allCases) { role in
                            if let palette = try? MacDesktopSettingsSnapshot.palette(values) { Circle().fill(Color(nsColor: palette.color(role))).frame(width: 18, height: 18).help(role.title + ": " + (values[role.rawValue] ?? "")) }
                        } }
                    }
                    Text("Saved themes: " + (s.savedThemes.isEmpty ? "None" : s.savedThemes.map(\.name).joined(separator: ", "))).macFont(.caption)
                    Text("Matching saved theme names are replaced. Other saved themes are kept.").macFont(.caption).foregroundStyle(.secondary)
                }.padding(.trailing, 8)
            }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Apply settings") { do { try review.apply(); dismiss() } catch { issue = error.localizedDescription } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 560, height: 550)
    }
}
