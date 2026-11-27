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
    @Environment(\.macSettingsEmbedded) private var embedded
    init(workspace: MacWorkspace) { self.workspace = workspace; _workspaceID = State(initialValue: workspace.workspaceID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !embedded { Text("New notes").macFont(.title2.bold()) }
            Text("Choose the default folder for this vault on this Mac. It is used in All Notes and other sections without a selected folder.").foregroundStyle(.secondary)
            Picker("Default folder", selection: Binding(get: { workspace.defaultNoteFolder }, set: {
                do { try workspace.setDefaultNoteFolder($0, workspace: workspaceID); issue = nil }
                catch { issue = error.localizedDescription }
            })) {
                ForEach(workspace.defaultNoteFolderOptions, id: \.self) { folder in
                    Text(folder == workspace.inboxNoteFolder ? folder + " (default)" : folder.replacingOccurrences(of: "/", with: " / ")).tag(folder)
                }
            }.disabled(workspace.workspaceID != workspaceID || workspace.busy || workspace.preparingToClose)
            Text("When you are browsing a folder, new notes stay in that folder. Explicit destinations such as Create linked note take precedence.").macFont(.caption).foregroundStyle(.secondary)
            if !workspace.folders.contains(workspace.defaultNoteFolder), workspace.defaultNoteFolder != workspace.inboxNoteFolder {
                Text("The saved folder is currently absent. Creating a note will recreate it.").macFont(.caption).foregroundStyle(.secondary)
            }
            if workspace.workspaceID != workspaceID { Text("The vault changed. Close and reopen New notes settings.").macFont(.caption).foregroundStyle(.red) }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red) }
            if !embedded { HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) } }
        }.macSettingsChrome(width: 460)
    }
}

/// Shown by the toolbar's New note button so the destination folder (the
/// note's type) is chosen before the file is created.
struct MacNewNoteSheet: View {
    @Bindable var workspace: MacWorkspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.macTheme) private var theme
    @State private var title = ""
    @State private var folder: String
    @State private var collapsed: Set<String>
    @State private var creating = false
    @FocusState private var focus: Field?
    private enum Field: Hashable { case title, tree }
    private let workspaceID: UUID
    init(workspace: MacWorkspace) {
        self.workspace = workspace
        workspaceID = workspace.workspaceID
        let current = workspace.folderCollection && MacNewNotePreferences.ordinary(workspace.destination) ? workspace.destination : workspace.defaultNoteFolder
        _folder = State(initialValue: current)
        // Mirror the sidebar's collapsed folders, but always reveal the
        // preselected destination.
        _collapsed = State(initialValue: workspace.collapsedFolders.filter { !MacFolderOrdering.within(current, $0) || current == $0 })
    }
    /// Every destination plus its ancestors, in the sidebar's order.
    private var tree: [String] {
        var paths = Set(workspace.defaultNoteFolderOptions + [folder])
        for path in paths {
            var parts = path.split(separator: "/").map(String.init)
            while parts.count > 1 { parts.removeLast(); paths.insert(parts.joined(separator: "/")) }
        }
        return MacFolderOrdering(folders: Array(paths), preference: workspace.orderedFolders).ordered
    }
    private var visible: [String] {
        tree.filter { path in !collapsed.contains { path.hasPrefix($0 + "/") } }
    }
    private func hasChildren(_ path: String, in all: [String]) -> Bool { all.contains { $0.hasPrefix(path + "/") } }
    private var text: Color { theme.color(.text) }
    private var accent: Color { theme.color(.accent) }
    var body: some View {
        let all = tree, rows = visible
        VStack(alignment: .leading, spacing: 14) {
            Text("New note").macFont(.title2.bold())
            TextField("Title", text: $title, prompt: Text("Untitled").foregroundStyle(text.opacity(0.4)))
                .textFieldStyle(.plain).focused($focus, equals: .title).onSubmit(create)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(text.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(focus == .title ? accent.opacity(0.8) : text.opacity(0.15), lineWidth: focus == .title ? 2 : 1))
                .onKeyPress(.downArrow) { move(1, rows); return .handled }
                .onKeyPress(.upArrow) { move(-1, rows); return .handled }
            Text("Folder").macFont(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(rows, id: \.self) { path in row(path, expandable: hasChildren(path, in: all)).id(path) }
                    }.padding(5)
                }
                .frame(height: 260)
                .background(text.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focus == .tree ? accent.opacity(0.6) : text.opacity(0.12)))
                .focusable().focused($focus, equals: .tree).focusEffectDisabled()
                .onKeyPress(.downArrow) { move(1, rows); return .handled }
                .onKeyPress(.upArrow) { move(-1, rows); return .handled }
                .onKeyPress(.rightArrow) { setCollapsed(folder, false, all); return .handled }
                .onKeyPress(.leftArrow) {
                    if hasChildren(folder, in: all), !collapsed.contains(folder) { collapsed.insert(folder) }
                    else if let slash = folder.lastIndex(of: "/") { folder = String(folder[..<slash]) }
                    return .handled
                }
                .onAppear { proxy.scrollTo(folder, anchor: .center) }
                .onChange(of: folder) { _, value in withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(value) } }
            }
            if workspace.workspaceID != workspaceID { Text("The vault changed. Close and try again.").macFont(.caption).foregroundStyle(.red) }
            HStack {
                if creating { ProgressView().controlSize(.small) }
                Text(folder.replacingOccurrences(of: "/", with: " › ")).macFont(.caption).foregroundStyle(text.opacity(0.55)).lineLimit(1).truncationMode(.head)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create", action: create).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(accent)
                    .disabled(creating || workspace.busy || workspace.workspaceID != workspaceID)
            }
        }
        .foregroundStyle(text)
        .padding(24).frame(width: 440)
        .background(theme.color(.surface))
        .onAppear { focus = .title }
    }
    private func row(_ path: String, expandable: Bool) -> some View {
        let selected = path == folder
        let depth = path.filter { $0 == "/" }.count
        return HStack(spacing: 0) {
            Button { setCollapsed(path, !collapsed.contains(path), tree) } label: {
                Image(systemName: collapsed.contains(path) ? "chevron.right" : "chevron.down")
                    .macFont(.system(size: 9, weight: .semibold)).foregroundStyle(text.opacity(0.5))
                    .frame(width: 18).frame(maxHeight: .infinity).contentShape(Rectangle())
            }.buttonStyle(MacBoxButtonStyle()).disabled(!expandable).opacity(expandable ? 1 : 0)
                .accessibilityLabel((collapsed.contains(path) ? "Expand " : "Collapse ") + path)
            Button { folder = path } label: {
                HStack(spacing: 7) {
                    MacFolderIcon(value: workspace.folderIcon(path), size: 15).foregroundStyle(selected ? accent : text.opacity(0.6))
                    Text((path as NSString).lastPathComponent).lineLimit(1)
                    Spacer(minLength: 4)
                    if path == workspace.defaultNoteFolder { Text("Default").macFont(.caption).foregroundStyle(text.opacity(0.5)) }
                }.padding(.vertical, 5).padding(.trailing, 8).contentShape(Rectangle())
            }.buttonStyle(MacBoxButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
                .simultaneousGesture(TapGesture(count: 2).onEnded { folder = path; create() })
        }
        .padding(.leading, CGFloat(depth) * 14)
        .background(selected ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
    private func move(_ step: Int, _ rows: [String]) {
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex(of: folder) ?? (step > 0 ? -1 : rows.count)
        folder = rows[max(0, min(rows.count - 1, index + step))]
    }
    private func setCollapsed(_ path: String, _ value: Bool, _ all: [String]) {
        guard hasChildren(path, in: all) else { return }
        if value {
            collapsed.insert(path)
            if folder.hasPrefix(path + "/") { folder = path }
        } else { collapsed.remove(path) }
    }
    private func create() {
        guard !creating, workspace.workspaceID == workspaceID else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        creating = true
        Task {
            let created = await workspace.createNote(title: name.isEmpty ? "Untitled" : name, folder: folder)
            creating = false
            if created != nil { dismiss() }
        }
    }
}
