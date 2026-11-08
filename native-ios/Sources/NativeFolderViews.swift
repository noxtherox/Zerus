import SwiftUI

struct NativeFolderDestination: Identifiable {
    let path: String
    var id: String { path }
}

struct NativeFolderCreation: Identifiable {
    let id = UUID()
    let parent: String
}

struct NativeFolderGlyph: View {
    let value: String?
    static let choices: [(name: String, symbol: String)] = [
        ("Briefcase", "briefcase"), ("Building", "building.2"), ("FolderCode", "folder.badge.gearshape"),
        ("Checklist", "checklist"), ("Target", "target"), ("Notebook", "book.closed"),
        ("Calendar", "calendar"), ("Bulb", "lightbulb"), ("Inbox", "tray"),
        ("Archive", "archivebox"), ("Users", "person.2"), ("User", "person"),
        ("Book", "book"), ("School", "graduationcap"), ("Writing", "pencil.line"),
        ("MessageCircle", "bubble.left"), ("ChefHat", "fork.knife"), ("Coffee", "cup.and.saucer"),
        ("Plane", "airplane"), ("Mountain", "mountain.2"), ("Wallet", "wallet.pass"),
        ("ChartLine", "chart.xyaxis.line"), ("ShoppingCart", "cart"), ("Gift", "gift"),
        ("HeartRateMonitor", "heart"), ("Barbell", "dumbbell"), ("Moon", "moon"),
        ("Code", "chevron.left.forwardslash.chevron.right"), ("Bug", "ladybug"), ("Server", "server.rack"),
        ("Palette", "paintpalette"), ("Pencil", "pencil"), ("Camera", "camera"),
        ("Photo", "photo"), ("Music", "music.note"), ("Microphone", "mic"),
        ("Plant", "leaf"), ("Paw", "pawprint"), ("Car", "car"),
        ("Home", "house"), ("Mail", "envelope"), ("Key", "key"),
        ("Star", "star"), ("Lock", "lock"), ("Rocket", "paperplane"), ("Flame", "flame")
    ]
    var body: some View {
        if let value, value.count == 1, value.unicodeScalars.contains(where: { !$0.isASCII }) {
            Text(value).accessibilityHidden(true)
        } else {
            Image(systemName: Self.choices.first { "tabler:" + $0.name == value }?.symbol ?? "folder").accessibilityHidden(true)
        }
    }
}

struct NativeNewFolderView: View {
    let parent: String
    let workspaceID: UUID
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var issue: String?
    private var path: String { parent.isEmpty ? name : parent + "/" + name }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name", text: $name).textInputAutocapitalization(.words).autocorrectionDisabled().accessibilityIdentifier("folder.new.name")
                    if !parent.isEmpty { LabeledContent("Inside", value: parent) }
                } footer: { Text("Creates an empty folder in your vault. Use / for nested folders. No note is added.") }
                if let issue { Section { Text(issue).foregroundStyle(.red).textSelection(.enabled) } }
            }.navigationTitle(parent.isEmpty ? "New folder" : "New subfolder").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            busy = true; issue = nil
                            Task {
                                do { try await vault.createFolder(path, workspace: workspaceID); dismiss() }
                                catch { issue = error.localizedDescription }
                                busy = false
                            }
                        }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("folder.new.create")
                    }
                }.disabled(busy)
                .overlay { if busy { ProgressView("Creating folder…") } }
                .onChange(of: vault.workspaceID) { _, value in if value != workspaceID { dismiss() } }
        }
    }
}

struct NativeFolderIconView: View {
    let folder: String
    let workspaceID: UUID
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: NativeFolderIconSnapshot?
    @State private var emoji = ""
    @State private var query = ""
    @State private var busy = false
    @State private var issue: String?
    private var choices: [(name: String, symbol: String)] { NativeFolderGlyph.choices.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label { Text(folder) } icon: { NativeFolderGlyph(value: snapshot?.icons[folder]) }
                    if let value = snapshot?.icons[folder], value.hasPrefix("tabler:"), !NativeFolderGlyph.choices.contains(where: { "tabler:" + $0.name == value }) {
                        Text("Saved icon: \(String(value.dropFirst(7))). This icon is kept until you choose a replacement.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Use default folder icon") { save(nil) }.accessibilityIdentifier("folder.icon.reset")
                }
                Section("Emoji") {
                    HStack {
                        TextField("One emoji", text: $emoji).autocorrectionDisabled().accessibilityIdentifier("folder.icon.emoji")
                        Button("Use emoji") { save(emoji.trimmingCharacters(in: .whitespacesAndNewlines)) }.disabled(emoji.isEmpty)
                    }
                }
                if let issue { Section { Text(issue).foregroundStyle(.red).textSelection(.enabled) } }
                Section("Icons") {
                    ForEach(choices, id: \.name) { item in
                        Button { save("tabler:" + item.name) } label: {
                            HStack { Label(item.name, systemImage: item.symbol); Spacer(); if snapshot?.icons[folder] == "tabler:" + item.name { Image(systemName: "checkmark") } }.frame(minHeight: 36)
                        }.accessibilityAddTraits(snapshot?.icons[folder] == "tabler:" + item.name ? .isSelected : [])
                    }
                }
            }.navigationTitle("Folder icon").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Find an icon")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
                .disabled(busy)
                .overlay { if busy { ProgressView("Saving icon…") } }
                .task {
                    do { snapshot = try await vault.folderIconSnapshot(workspace: workspaceID) }
                    catch { issue = error.localizedDescription }
                }
                .onChange(of: vault.workspaceID) { _, value in if value != workspaceID { dismiss() } }
        }
    }
    private func save(_ value: String?) {
        guard let snapshot else { return }; busy = true; issue = nil
        Task {
            do { try await vault.setFolderIcon(snapshot, folder: folder, value: value); dismiss() }
            catch { issue = error.localizedDescription; self.snapshot = try? await vault.folderIconSnapshot(workspace: workspaceID) }
            busy = false
        }
    }
}
