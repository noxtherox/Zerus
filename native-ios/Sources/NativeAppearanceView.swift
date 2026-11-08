import SwiftUI

struct NativeAppearanceView: View {
    @EnvironmentObject private var appearance: NativeAppearanceStore
    @Environment(\.colorScheme) private var scheme
    @State private var editing = NativeThemeSlot.light
    @State private var name = ""
    @State private var issue: String?
    @State private var savedMessage: String?
    @State private var replacement: NativeNamedTheme?
    private var theme: NativeThemePalette { appearance.palettes[editing] ?? .nativeDefaults(editing) }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var reserved: Bool { NativeThemePresets.all.contains { $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame } }
    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: Binding(get: { appearance.mode }, set: { appearance.setMode($0); chooseMode($0) })) {
                    ForEach(NativeAppearanceMode.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("appearance.mode")
                Picker("Customize", selection: Binding(get: { editing }, set: { editing = $0; appearance.setMode($0 == .dark ? .dark : .light) })) {
                    ForEach(NativeThemeSlot.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("appearance.slot")
            } footer: { Text("Light and dark colours are saved separately on this device. Customizing a theme shows that appearance while you edit. Choose System to follow your device again.") }
            Section("Preview") { NativePalettePreview(theme: theme) }
            Section("Presets for the \(editing.rawValue) theme") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(NativeThemePresets.all) { preset in
                        Button { apply(preset.theme) } label: {
                            HStack(spacing: 8) { NativePaletteSwatch(theme: preset.theme); Text(preset.name).foregroundStyle(.primary).font(.subheadline); Spacer(minLength: 0) }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("appearance.preset." + preset.name)
                    }
                }.disabled(appearance.paletteIssue != nil)
            }
            Section("Colours") {
                ForEach(NativeThemeRole.allCases) { role in
                    ColorPicker(selection: Binding(get: { Color(uiColor: NativeThemePalette.color(theme[role])) }, set: { color in
                        guard let hex = NativeThemePalette.hex(UIColor(color), traits: editing.traits) else { issue = "This colour could not be converted to sRGB."; return }
                        var next = theme; next[role] = hex; apply(next)
                    }), supportsOpacity: false) {
                        VStack(alignment: .leading, spacing: 4) { Text(role.title); Text(role.hint).font(.caption).foregroundStyle(.secondary); Text(theme[role]).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("appearance.color." + role.rawValue)
                }
            }.disabled(appearance.paletteIssue != nil)
            if !appearance.saved.isEmpty || appearance.undoName != nil || appearance.savedIssue != nil {
                Section("Saved themes") {
                    ForEach(appearance.saved) { saved in
                        HStack {
                            Button { apply(saved.theme) } label: { HStack { NativePaletteSwatch(theme: saved.theme); Text(saved.name).foregroundStyle(.primary); Spacer() }.frame(minHeight: 44).contentShape(Rectangle()) }
                                .buttonStyle(.plain).accessibilityIdentifier("appearance.saved." + saved.name)
                            Button("Delete \(saved.name)", systemImage: "trash", role: .destructive) { perform { try appearance.delete(saved) } }
                                .labelStyle(.iconOnly).buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("appearance.saved.delete." + saved.name)
                        }
                    }
                    if let undoName = appearance.undoName { Button("Undo deleting \(undoName)", systemImage: "arrow.uturn.backward") { perform { try appearance.undoDelete() } }.accessibilityIdentifier("appearance.saved.undo") }
                    if let message = appearance.savedIssue { Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                }
            }
            Section {
                TextField("Theme name", text: $name).textInputAutocapitalization(.words).autocorrectionDisabled().accessibilityIdentifier("appearance.name")
                    .onSubmit { save() }
                Button("Save current theme", systemImage: "square.and.arrow.down") { save() }
                    .disabled(cleanName.isEmpty || cleanName.count > 40 || reserved || appearance.paletteIssue != nil).accessibilityIdentifier("appearance.save")
                if reserved { Text("Choose a different name from the built-in presets.").font(.caption).foregroundStyle(.orange) }
                if let savedMessage { Text(savedMessage).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Save this theme") } footer: { Text("Use a name of up to 40 characters. Saving an existing name asks before replacing it. Saved themes can be applied to either appearance.") }
            Section {
                Button("Reset appearance", systemImage: "arrow.counterclockwise") { appearance.reset(); chooseMode(.system); savedMessage = nil }.accessibilityIdentifier("appearance.reset")
                if let message = appearance.paletteIssue { Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            } footer: { Text("Restores the current native colours and follows this device. Your saved themes stay available.") }
        }.navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
            .onAppear { chooseMode(appearance.mode) }
            .onChange(of: appearance.mode) { _, value in chooseMode(value) }
            .onChange(of: scheme) { _, _ in if appearance.mode == .system { chooseMode(.system) } }
            .alert("Appearance", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) { Button("OK") { issue = nil } } message: { Text(issue ?? "") }
            .confirmationDialog("Replace saved theme?", isPresented: Binding(get: { replacement != nil }, set: { if !$0 { replacement = nil } }), titleVisibility: .visible) {
                if let replacement { Button("Replace \(replacement.name)") { store(replacement) } }
                Button("Cancel", role: .cancel) { replacement = nil }
            } message: { Text("The saved theme’s colours will be replaced. Its name stays available.") }
    }
    private func chooseMode(_ mode: NativeAppearanceMode) { editing = mode == .system ? (scheme == .dark ? .dark : .light) : mode == .dark ? .dark : .light }
    private func apply(_ palette: NativeThemePalette) { perform { try appearance.setPalette(palette, slot: editing) }; savedMessage = nil }
    private func perform(_ work: () throws -> Void) { do { try work() } catch { issue = error.localizedDescription } }
    private func save() {
        guard !cleanName.isEmpty, cleanName.count <= 40, !reserved else { return }
        let saved = NativeNamedTheme(name: cleanName, theme: theme)
        if appearance.saved.contains(where: { $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame }) { replacement = saved }
        else { store(saved) }
    }
    private func store(_ saved: NativeNamedTheme) {
        do { try appearance.save(saved.name, theme: saved.theme); name = ""; replacement = nil; savedMessage = "Saved \(saved.name)" }
        catch { issue = error.localizedDescription }
    }
}

private struct NativePaletteSwatch: View {
    let theme: NativeThemePalette
    var body: some View {
        HStack(spacing: 0) { ForEach([NativeThemeRole.sidebarBg, .surface, .accent]) { role in Color(uiColor: NativeThemePalette.color(theme[role])) } }
            .frame(width: 42, height: 25).clipShape(Capsule()).overlay(Capsule().stroke(.primary.opacity(0.15), lineWidth: 0.5)).accessibilityHidden(true)
    }
}
private struct NativePalettePreview: View {
    let theme: NativeThemePalette
    private func color(_ role: NativeThemeRole) -> Color { Color(uiColor: NativeThemePalette.color(theme[role])) }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) { Image(systemName: "books.vertical"); Text("Library").font(.caption.weight(.semibold)); Image(systemName: "folder"); Spacer(minLength: 0) }
                .foregroundStyle(color(.sidebarFg)).padding(12).frame(width: 82).frame(maxHeight: .infinity).background(color(.sidebarBg))
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Room to think.").font(.headline); Spacer(); Image(systemName: "pin.fill").foregroundStyle(color(.accent)) }
                Text("Your writing, in your colours.").font(.subheadline)
                Text("A connected idea").font(.subheadline).foregroundStyle(color(.link))
            }.foregroundStyle(color(.text)).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(color(.editorBg), in: RoundedRectangle(cornerRadius: 12)).padding(10).background(color(.surface))
        }.fixedSize(horizontal: false, vertical: true).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
