import SwiftUI

struct MacSavedViewsMenu: View {
    @Bindable var store: MacWorkspace
    @State private var saving = false
    @State private var managing = false
    @State private var name = ""
    @State private var busy = false
    var body: some View {
        Menu {
            ForEach(store.savedViews) { entry in Button(entry.name) { Task { await store.applySavedView(entry) } } }
            if !store.savedViews.isEmpty { Divider() }
            Button("Save current view…") { name = ""; saving = true }
            Button("Manage saved views…") { managing = true }.disabled(store.savedViews.isEmpty)
        } label: { Label("Views", systemImage: "rectangle.stack") }.menuStyle(.borderlessButton).fixedSize()
        .macSheet(isPresented: $saving) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Save current view").macFont(.title2.bold())
                TextField("View name", text: $name)
                if store.savedViews.contains(where: { $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) { Text("Saving replaces the existing view with this name.").macFont(.caption).foregroundStyle(.secondary) }
                HStack { Spacer(); Button("Cancel") { saving = false }; Button("Save") { busy = true; Task { if await store.saveCurrentView(name: name) { saving = false }; busy = false } }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy) }
            }.padding(24).frame(width: 410)
        }
        .macSheet(isPresented: $managing) { MacSavedViewsManager(store: store, owner: store.destination, workspaceID: store.workspaceID) }
    }
}

private struct MacSavedViewsManager: View {
    @Bindable var store: MacWorkspace
    let owner: String
    let workspaceID: UUID
    @State private var renaming: MacSavedView?
    @State private var deleting: MacSavedView?
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    private var connected: Bool { store.workspaceID == workspaceID && store.folderCollection && store.destination == owner }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Saved views · " + owner).macFont(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            if connected {
                List(store.savedViews) { entry in
                    HStack { Text(entry.name); Spacer(); Button("Apply") { Task { await store.applySavedView(entry); dismiss() } }; Button("Rename…") { name = entry.name; renaming = entry }; Button("Delete…", role: .destructive) { deleting = entry } }
                }
            } else { ContentUnavailableView("Collection changed", systemImage: "rectangle.stack", description: Text("Reopen saved views in the collection you want to edit.")) }
        }.padding(24).frame(width: 650, height: 400)
        .alert("Rename saved view", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { if let entry = renaming { Task { _ = await store.changeSavedView(entry, name: name, owner: owner, workspaceID: workspaceID) } }; renaming = nil }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete saved view", role: .destructive) { if let entry = deleting { Task { _ = await store.changeSavedView(entry, name: nil, owner: owner, workspaceID: workspaceID) } }; deleting = nil }
        }
    }
}
