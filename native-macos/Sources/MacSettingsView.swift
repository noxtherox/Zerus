import SwiftUI
import AppKit

extension EnvironmentValues {
    /// True when a settings view is shown as a pane of the Settings window
    /// rather than as its own sheet; the view then omits its title, Done
    /// button and fixed sheet size.
    @Entry var macSettingsEmbedded = false
}

/// Sheet chrome for settings views that can also be embedded as a pane.
struct MacSettingsChrome: ViewModifier {
    let width: CGFloat
    var height: CGFloat? = nil
    @Environment(\.macSettingsEmbedded) private var embedded
    func body(content: Content) -> some View {
        if embedded { content.frame(maxWidth: .infinity, maxHeight: height == nil ? nil : .infinity, alignment: .topLeading) }
        else { content.padding(24).frame(width: width, height: height) }
    }
}
extension View {
    func macSettingsChrome(width: CGFloat, height: CGFloat? = nil) -> some View { modifier(MacSettingsChrome(width: width, height: height)) }
}

enum MacSettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, editor, ai, newNotes, properties, history, cli, maintenance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .editor: "Editor"
        case .ai: "On-device AI"
        case .newNotes: "New notes"
        case .properties: "Properties pane"
        case .history: "Version history"
        case .cli: "CLI & agents"
        case .maintenance: "Maintenance"
        }
    }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .editor: "pencil.line"
        case .ai: "sparkles"
        case .newNotes: "square.and.pencil"
        case .properties: "sidebar.right"
        case .history: "clock.arrow.circlepath"
        case .cli: "terminal"
        case .maintenance: "wrench.and.screwdriver"
        }
    }
    var needsVault: Bool { [.newNotes, .properties, .history, .maintenance].contains(self) }
}

struct MacSettingsView: View {
    var workspace: MacWorkspace? = nil
    @SceneStorage("zerus.mac.settingsPane") private var storedPane = MacSettingsPane.general.rawValue
    @AppStorage("zerus.mac.appearance") private var appearance = "light"
    @Environment(\.dismiss) private var dismiss
    private var vault: MacWorkspace? { workspace?.root != nil ? workspace : nil }
    private var groups: [[MacSettingsPane]] {
        [[.general, .appearance, .editor, .ai], vault == nil ? [] : [.newNotes, .properties, .history], vault == nil ? [.cli] : [.cli, .maintenance]].filter { !$0.isEmpty }
    }
    private var pane: MacSettingsPane {
        let value = MacSettingsPane(rawValue: storedPane) ?? .general
        return value.needsVault && vault == nil ? .general : value
    }
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 { Divider().padding(.horizontal, 8).padding(.vertical, 6) }
                        ForEach(group) { item in MacSettingsSidebarRow(pane: item, selected: item == pane) { storedPane = item.rawValue } }
                    }
                }.padding(10)
            }
            .frame(width: 200).background(.background.secondary)
            .accessibilityElement(children: .contain).accessibilityIdentifier("settings.sidebar")
            Divider()
            VStack(spacing: 0) {
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if workspace != nil {
                    Divider()
                    HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(.horizontal, 20).padding(.vertical, 12)
                }
            }
        }
        .frame(width: 820, height: 600)
        .environment(\.macSettingsEmbedded, true)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general: MacGeneralSettingsPane()
        case .appearance: MacAppearanceSettingsPane()
        case .editor: MacEditorSettingsPane()
        case .ai: MacLocalAISettingsPane(workspace: workspace)
        case .newNotes: if let vault { framed(.newNotes) { ScrollView { MacNewNoteSettingsView(workspace: vault) } } }
        case .properties: if let vault { framed(.properties) { ScrollView { MacPaneSettingsView(workspace: vault) } } }
        case .history: if let vault { framed(.history) { MacHistoryManagementView(workspace: vault) } }
        case .cli: framed(.cli) { MacCLISettingsView(workspace: workspace) }
        case .maintenance: if let vault { MacMaintenanceSettingsPane(workspace: vault) }
        }
    }
    /// Embedded views keep their own controls; the pane supplies the title.
    private func framed<Content: View>(_ pane: MacSettingsPane, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(pane.title).macFont(.title2.bold())
            content()
        }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16).id(pane)
    }
}

private struct MacSettingsSidebarRow: View {
    let pane: MacSettingsPane
    let selected: Bool
    let action: () -> Void
    @Environment(\.macTheme) private var theme
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: pane.icon).macFont(.system(size: 12, weight: .medium)).frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)))
                Text(pane.title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? theme.color(.accent) : hovering ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.pane." + pane.rawValue)
    }
}

private struct MacSettingsHelp: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).macFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

private struct MacGeneralSettingsPane: View {
    @AppStorage("zerus.mac.dateFormat") private var dateFormat = "DD/MM/YYYY"
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { short + " (" + $0 + ")" } ?? short
    }
    var body: some View {
        Form {
            Section("Format") {
                Picker(selection: Binding(get: { MacNumericDateFormat.validated(dateFormat).rawValue }, set: { dateFormat = $0 })) {
                    ForEach(MacNumericDateFormat.allCases, id: \.self) { format in Text(format.rawValue + " · " + format.calendarDay("2026-12-31")).tag(format.rawValue) }
                } label: { Text("Date format"); MacSettingsHelp("Used for date and completion date fields on this Mac.") }
            }
            Section {
                LabeledContent("Notes") { Text("Markdown files in your vault") }
                LabeledContent("Recovery drafts") { Text("This Mac’s Application Support folder") }
            } header: { Text("Storage") }
            Section {
                LabeledContent("Version") { Text(version).textSelection(.enabled) }
            } header: { Text("About") } footer: { MacSettingsHelp("Native macOS migration build") }
        }.formStyle(.grouped)
    }
}

private struct MacAppearanceSettingsPane: View {
    @AppStorage("zerus.mac.appearance") private var appearance = "light"
    @AppStorage("zerus.mac.interfaceZoom") private var interfaceZoom = 100
    @AppStorage(MacInterfaceText.key) private var interfaceTextSize = 100
    @Environment(\.macTheme) private var theme
    @State private var colours = false
    var body: some View {
        Form {
            Section("Display") {
                Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    .pickerStyle(.segmented).fixedSize()
                Picker(selection: Binding(get: { MacInterfaceZoom.validated(interfaceZoom) }, set: { interfaceZoom = $0 })) {
                    ForEach(MacInterfaceZoom.options, id: \.self) { Text("\($0)%").tag($0) }
                } label: { Text("Interface zoom"); MacSettingsHelp("Resize navigation, lists and controls on this Mac. Note content uses its own size.") }
                Picker(selection: Binding(get: { MacInterfaceText.validated(interfaceTextSize) }, set: { interfaceTextSize = $0 })) {
                    ForEach(MacInterfaceText.options, id: \.self) { Text("\($0)%").tag($0) }
                } label: { Text("Interface text"); MacSettingsHelp("Resize text in navigation, lists, panes and settings without changing button or control sizes. Note content uses its own size.") }
            }
            Section("Colours") {
                LabeledContent {
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
                            ForEach([MacThemeRole.accent, .link, .editorBg, .text], id: \.self) { role in
                                Circle().fill(theme.color(role)).overlay(Circle().strokeBorder(.separator)).frame(width: 14, height: 14)
                            }
                        }.accessibilityHidden(true)
                        Button("Customise…") { colours = true }
                    }
                } label: { Text("Palette"); MacSettingsHelp("Separate light and dark palettes, presets and saved themes.") }
            }
        }.formStyle(.grouped)
        .macSheet(isPresented: $colours) { MacThemeSettingsView().environment(\.macSettingsEmbedded, false) }
    }
}

private struct MacEditorSettingsPane: View {
    @AppStorage("zerus.mac.noteLinkShortcuts") private var noteLinkShortcuts = true
    @AppStorage("zerus.mac.codeBlocks") private var codeBlocks = false
    @AppStorage("zerus.mac.noteTextSize") private var noteTextSize = 100
    @AppStorage("zerus.mac.noteWidth") private var noteWidth = 100
    @AppStorage("zerus.mac.noteAlignment") private var noteAlignment = "center"
    var body: some View {
        Form {
            Section("Layout") {
                Picker(selection: Binding(get: { MacInterfaceZoom.validated(noteTextSize) }, set: { noteTextSize = $0 })) {
                    ForEach(MacInterfaceZoom.options, id: \.self) { Text("\($0)%").tag($0) }
                } label: { Text("Note size"); MacSettingsHelp("Resize note text and images independently of the interface. Saved formatting stays unchanged.") }
                Picker("Writing width", selection: Binding(get: { MacNoteLayout(width: noteWidth).width }, set: { noteWidth = $0 })) {
                    ForEach(MacNoteLayout.widths.sorted(), id: \.self) { width in Text(width == 100 ? "Full" : "\(width)%").tag(width) }
                }.pickerStyle(.segmented).fixedSize()
                Picker(selection: Binding(get: { noteAlignment == "left" ? "left" : "center" }, set: { noteAlignment = $0 })) {
                    Label("Left", systemImage: "text.alignleft").tag("left")
                    Label("Center", systemImage: "text.aligncenter").tag("center")
                } label: { Text("Column alignment"); MacSettingsHelp("Applies when the writing column is narrower than the window.") }
                .pickerStyle(.segmented).fixedSize()
            }
            Section("Writing") {
                Toggle(isOn: $noteLinkShortcuts) { Text("Note link shortcuts"); MacSettingsHelp("Type @ or [[ to find and link a note while writing. The Link button stays available.") }
                    .toggleStyle(.switch)
                Toggle(isOn: $codeBlocks) { Text("Code blocks"); MacSettingsHelp("Add code blocks from the toolbar, triple backticks or formatted paste. Existing code blocks stay editable when this is off.") }
                    .toggleStyle(.switch)
            }
        }.formStyle(.grouped)
    }
}

private struct MacMaintenanceSettingsPane: View {
    let workspace: MacWorkspace
    @State private var relationRepair = false
    var body: some View {
        Form {
            Section("Vault") {
                LabeledContent {
                    Button("Review…") { relationRepair = true }
                } label: { Text("Repair relations"); MacSettingsHelp("Restore relation definitions left behind after notes moved between folders. You review every change first.") }
            }
        }.formStyle(.grouped)
        .macSheet(isPresented: $relationRepair) { MacRelationRepairView(workspace: workspace).environment(\.macSettingsEmbedded, false) }
    }
}
