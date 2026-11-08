import SwiftUI

enum NativeDateFormat: String, CaseIterable, Identifiable {
    case dayFirst = "DD/MM/YYYY", monthFirst = "MM/DD/YYYY", iso = "YYYY-MM-DD", dotted = "DD.MM.YYYY"
    static let key = "zerus.native.dateFormat"
    var id: String { rawValue }

    func string(day: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard NativeTask.parseDay(day, calendar: calendar) != nil else { return day }
        let parts = day.split(separator: "-").map(String.init)
        return rawValue.replacingOccurrences(of: "YYYY", with: parts[0])
            .replacingOccurrences(of: "MM", with: parts[1]).replacingOccurrences(of: "DD", with: parts[2])
    }
    func string(date: Date, calendar: Calendar = .current, time: Bool = false) -> String {
        let day = string(day: NativeTask.day(date, calendar: calendar))
        return time ? day + " · " + date.formatted(date: .omitted, time: .shortened) : day
    }
}

/// Display preferences never change the ISO calendar days kept in vault files.
struct NativeDateText: View {
    @AppStorage(NativeDateFormat.key) private var format = NativeDateFormat.dayFirst.rawValue
    private let day: String?
    private let date: Date?
    private let time: Bool
    init(day: String) { self.day = day; date = nil; time = false }
    init(_ date: Date, time: Bool = false) { day = nil; self.date = date; self.time = time }
    var body: some View {
        let choice = NativeDateFormat(rawValue: format) ?? .dayFirst
        Text(day.map { choice.string(day: $0) } ?? choice.string(date: date!, time: time))
    }
}

enum NativeNoteDefaults {
    static func key(_ vault: UUID) -> String { "zerus.native.defaultNoteFolder." + vault.uuidString.lowercased() }
    static func folder(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.isEmpty, value.utf8.count <= 500, parts.count <= 8,
              !parts.contains(where: { $0.isEmpty || $0.hasPrefix(".") || $0.contains("\\") || $0.contains(":") || $0.utf8.count > 100 || $0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else {
            throw VaultFailure(message: "Use a folder path such as Work/Projects, with up to eight folder names. Hidden folders, empty names and parent paths are unavailable.")
        }
        return value
    }
    static func load(_ vault: UUID?) -> String {
        guard let vault, let saved = UserDefaults.standard.string(forKey: key(vault)) else { return "Inbox" }
        return (try? folder(saved)) ?? "Inbox"
    }
}

struct NativeGeneralSettingsView: View {
    @EnvironmentObject private var vault: VaultStore
    @AppStorage(NativeDateFormat.key) private var dateFormat = NativeDateFormat.dayFirst.rawValue
    @AppStorage("zerus.native.noteLinkShortcuts") private var noteLinkShortcuts = true
    @AppStorage("zerus.native.codeBlocks") private var codeBlocks = false
    @AppStorage private var folder: String
    let vaultID: UUID
    let workspaceID: UUID
    init(vaultID: UUID, workspaceID: UUID) {
        self.vaultID = vaultID; self.workspaceID = workspaceID
        _folder = AppStorage(wrappedValue: "Inbox", NativeNoteDefaults.key(vaultID))
    }
    private var active: Bool { vault.activeVaultID == vaultID && vault.workspaceID == workspaceID && !vault.switchingVault }
    var body: some View {
        Form {
            Section {
                Toggle("Note link shortcuts", isOn: $noteLinkShortcuts).accessibilityIdentifier("settings.noteLinkShortcuts")
                Toggle("Code blocks", isOn: $codeBlocks).accessibilityIdentifier("settings.codeBlocks")
            } header: { Text("Editor") } footer: { Text("Type @ or [[ to find and link a note. Code blocks enables toolbar insertion, typing ``` followed by Return, and pasting fenced code. When off, pasted fences stay text and existing blocks remain editable. Markdown source always keeps its exact syntax.") }
            Section {
                Picker("Date format", selection: $dateFormat) {
                    ForEach(NativeDateFormat.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }.accessibilityIdentifier("settings.dateFormat")
                LabeledContent("Example") { NativeDateText(day: "2026-12-31").accessibilityIdentifier("settings.dateExample") }
            } header: { Text("Dates") } footer: {
                Text("Used for date properties, task dates and completion dates on this device. Calendar dates in your files keep their original format. System date pickers follow your iPhone’s region settings.")
            }
            Section {
                NavigationLink {
                    NativeDefaultFolderView(selection: $folder, folders: vault.folders).disabled(!active)
                } label: { LabeledContent("Default folder", value: (try? NativeNoteDefaults.folder(folder)) ?? "Inbox") }
                    .accessibilityIdentifier("settings.defaultFolder")
            } header: { Text("New notes") } footer: {
                Text("Used when creating a note from All notes. Saved for this vault on this device. Inbox is the vault’s root; a new folder is created only when you save a note there.")
            }
        }.navigationTitle("General").navigationBarTitleDisplayMode(.inline).disabled(!active)
    }
}

private struct NativeDefaultFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    let folders: [String]
    @State private var path = ""
    @State private var issue: String?
    private var choices: [String] {
        Array(Set(["Inbox", selection] + folders)).filter { (try? NativeNoteDefaults.folder($0)) != nil }.sorted()
    }
    var body: some View {
        Form {
            Section("Choose a folder") {
                ForEach(choices, id: \.self) { folder in
                    Button { selection = folder; dismiss() } label: {
                        HStack { Label(folder, systemImage: "folder"); Spacer(); if selection == folder { Image(systemName: "checkmark") } }
                    }.accessibilityIdentifier("settings.folder." + folder)
                }
            }
            Section {
                TextField("Work/Projects", text: $path).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("New default folder path").accessibilityIdentifier("settings.folder.path")
                if let issue { Text(issue).font(.caption).foregroundStyle(.red).accessibilityIdentifier("settings.folder.error") }
                Button("Use this folder") {
                    do { selection = try NativeNoteDefaults.folder(path); dismiss() }
                    catch { issue = error.localizedDescription }
                }.disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("settings.folder.use")
            } header: { Text("Another folder") } footer: { Text("Separate nested folder names with /. Your notes stay where they are.") }
        }.navigationTitle("Default folder").navigationBarTitleDisplayMode(.inline)
    }
}
