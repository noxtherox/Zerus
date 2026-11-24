import SwiftUI

/// Like the desktop preference, this is local to this Mac and vault location.
enum MacNewNotePreferences {
    static func key(_ root: URL) -> String { "zerus.mac.defaultNoteFolder." + NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.path) }
    static func ordinary(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && path != "assets" && !path.hasPrefix("assets/") && parts.allSatisfy {
            !$0.isEmpty && !$0.hasPrefix(".") && $0.range(of: #"[:\\\x00-\x1F]"#, options: .regularExpression) == nil
        }
    }
    static func folder(_ root: URL) -> String {
        guard let saved = UserDefaults.standard.object(forKey: key(root)) as? String, ordinary(saved) else { return "Inbox" }
        return saved
    }
}

extension MacWorkspace {
    var inboxNoteFolder: String {
        if folders.contains("Inbox") { return "Inbox" }
        return folders.sorted().first { $0.caseInsensitiveCompare("Inbox") == .orderedSame } ?? "Inbox"
    }
    var defaultNoteFolder: String {
        _ = preferenceRevision
        guard let root else { return "Inbox" }
        let saved = MacNewNotePreferences.folder(root)
        return saved.caseInsensitiveCompare("Inbox") == .orderedSame && !folders.contains(saved) ? inboxNoteFolder : saved
    }
    var defaultNoteFolderOptions: [String] {
        Set(folders + [inboxNoteFolder, defaultNoteFolder]).filter(MacNewNotePreferences.ordinary).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    func setDefaultNoteFolder(_ folder: String, workspace expected: UUID) throws {
        guard expected == workspaceID, root != nil, !busy, !preparingToClose else { throw VaultFailure(message: "The vault changed or is busy. Reopen New notes settings.") }
        guard MacNewNotePreferences.ordinary(folder), folder == inboxNoteFolder || folders.contains(folder) || folder == defaultNoteFolder else { throw VaultFailure(message: "Choose an available note folder.") }
        persistDefaultNoteFolder(folder)
    }
    private func persistDefaultNoteFolder(_ folder: String) {
        guard let root else { return }
        let key = MacNewNotePreferences.key(root)
        UserDefaults.standard.set(folder, forKey: key)
        // There is no cached copy for a peer to overwrite with an older value.
        for peer in Self.windows.compactMap(\.value) where peer.root.map(MacNewNotePreferences.key) == key { peer.preferenceRevision &+= 1 }
    }
    func remapDefaultNoteFolder(from source: String, to destination: String?) {
        let current = defaultNoteFolder
        guard current == source || current.hasPrefix(source + "/") else { return }
        persistDefaultNoteFolder(destination.map { NativeFolderPath.remap(current, from: source, to: $0) } ?? "Inbox")
    }
}

struct MacNewNoteSettingsView: View {
    @Bindable var workspace: MacWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var issue: String?
    @State private var workspaceID: UUID
    init(workspace: MacWorkspace) { self.workspace = workspace; _workspaceID = State(initialValue: workspace.workspaceID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New notes").font(.title2.bold())
            Text("Choose the default folder for this vault on this Mac. It is used in All Notes and other sections without a selected folder.").foregroundStyle(.secondary)
            Picker("Default folder", selection: Binding(get: { workspace.defaultNoteFolder }, set: {
                do { try workspace.setDefaultNoteFolder($0, workspace: workspaceID); issue = nil }
                catch { issue = error.localizedDescription }
            })) {
                ForEach(workspace.defaultNoteFolderOptions, id: \.self) { folder in
                    Text(folder == workspace.inboxNoteFolder ? folder + " (default)" : folder.replacingOccurrences(of: "/", with: " / ")).tag(folder)
                }
            }.disabled(workspace.workspaceID != workspaceID || workspace.busy || workspace.preparingToClose)
            Text("When you are browsing a folder, new notes stay in that folder. Explicit destinations such as Create linked note take precedence.").font(.caption).foregroundStyle(.secondary)
            if !workspace.folders.contains(workspace.defaultNoteFolder), workspace.defaultNoteFolder != workspace.inboxNoteFolder {
                Text("The saved folder is currently absent. Creating a note will recreate it.").font(.caption).foregroundStyle(.secondary)
            }
            if workspace.workspaceID != workspaceID { Text("The vault changed. Close and reopen New notes settings.").font(.caption).foregroundStyle(.red) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 460)
    }
}
