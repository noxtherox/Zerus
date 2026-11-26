import SwiftUI
import AppKit

struct MacFileLocationsView: View {
    @Bindable var workspace: MacWorkspace
    @State private var workspaceID: UUID
    @State private var snapshot: MacFileLocationsSnapshot?
    @State private var editing: MacLocationNameRequest?
    @State private var disconnecting: NativeFileLocation?
    @State private var removing: NativeFileLocation?
    @State private var issue: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    init(workspace: MacWorkspace) { self.workspace = workspace; _workspaceID = State(initialValue: workspace.workspaceID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("File locations").macFont(.title2.bold()); Spacer(); Button("Refresh") { Task { await reload() } }; Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Share a location name across your vault, then choose its folder on this Mac. Connected notes keep relative paths; folder access stays on this device.").macFont(.callout).foregroundStyle(.secondary)
            if let warning = snapshot?.definitions.warning { Text(warning).macFont(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(snapshot?.definitions.locations ?? []) { location in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Image(systemName: "folder"); Text(location.name).macFont(.headline); Spacer(); Button("Rename…") { editing = .init(location: location) }.accessibilityLabel("Rename " + location.name) }
                            Text("On this Mac: " + (snapshot?.labels[location.id] ?? "Not mapped")).macFont(.callout).foregroundStyle(.secondary)
                            let count = snapshot?.usages[location.id] ?? 0
                            Text("\(count) connected \(count == 1 ? "note" : "notes"), including Trash.").macFont(.caption).foregroundStyle(.secondary)
                            if let problem = snapshot?.mappingIssues[location.id] { Text(problem).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
                            HStack {
                                Button("Choose folder…") { choose(location) }.accessibilityLabel("Choose folder for " + location.name)
                                if snapshot?.labels[location.id] != nil { Button("Disconnect on this Mac…") { disconnecting = location }.accessibilityLabel("Disconnect " + location.name + " on this Mac") }
                                Spacer()
                                Button("Remove unused…") { removing = location }.disabled(count > 0).accessibilityLabel("Remove unused location " + location.name)
                            }.macFont(.caption)
                        }.padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if snapshot?.definitions.locations.isEmpty == true { ContentUnavailableView("No file locations", systemImage: "folder", description: Text("Add a shared location for documents that live outside your vault.")) }
                }.padding(.vertical, 5)
            }
            HStack { Button("Add location…") { editing = .init(location: nil) }; Spacer(); if busy { ProgressView().controlSize(.small) } }
            Text("New original connections inside a mapped folder use its relative paths. Existing device-only connections keep their binding; replace their document to use a new location.").macFont(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 730, height: 590).disabled(busy).interactiveDismissDisabled(busy)
        .task { await reload() }
        .onChange(of: workspace.workspaceID) { snapshot = nil; issue = "The vault changed. Close and reopen File locations." }
        .macSheet(item: $editing) { request in MacLocationNameEditor(workspace: workspace, workspaceID: workspaceID, request: request) { await reload() } }
        .alert("Disconnect this folder on this Mac?", isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } })) {
            Button("Cancel", role: .cancel) { disconnecting = nil }
            Button("Disconnect") { if let location = disconnecting { perform { try await workspace.mapFileLocation(location, folder: nil, workspaceID: workspaceID) } }; disconnecting = nil }
        } message: { Text("The shared location, note paths and original files stay in place. Choose its folder again to restore access on this Mac.") }
        .alert("Remove this unused location?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Remove location") { if let location = removing { perform { try await workspace.changeFileLocation(.remove(location), workspaceID: workspaceID) } }; removing = nil }
        } message: { Text("This removes its shared name. Folders and files stay in place. A location used by any note, including Trash, cannot be removed.") }
    }
    private func choose(_ location: NativeFileLocation) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "Map folder"; panel.message = "Choose the folder for “" + location.name + "” on this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try await workspace.mapFileLocation(location, folder: url, workspaceID: workspaceID) }
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await action(); await reload() } catch { issue = error.localizedDescription } }
    }
    private func reload() async {
        do { let fresh = try await workspace.fileLocationsSnapshot(workspaceID: workspaceID); snapshot = fresh; issue = nil } catch { issue = error.localizedDescription }
    }
}
private struct MacLocationNameRequest: Identifiable {
    let id = UUID()
    let location: NativeFileLocation?
}
private struct MacLocationNameEditor: View {
    @Bindable var workspace: MacWorkspace
    let workspaceID: UUID
    let request: MacLocationNameRequest
    var saved: () async -> Void
    @State private var name = ""
    @State private var issue: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.location == nil ? "New file location" : "Rename file location").macFont(.title2.bold())
            TextField("Shared name", text: $name).textFieldStyle(.roundedBorder)
            Text("This name is shared with the vault. Each device chooses its own folder.").macFont(.caption).foregroundStyle(.secondary)
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save name") {
                busy = true
                Task { defer { busy = false }; do { let change = request.location.map { NativeFileLocationChange.rename($0, name: name) } ?? .add(id: UUID().uuidString.lowercased(), name: name); try await workspace.changeFileLocation(change, workspaceID: workspaceID); await saved(); dismiss() } catch { issue = error.localizedDescription } }
            }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 440).disabled(busy).interactiveDismissDisabled(busy).onAppear { name = request.location?.name ?? "" }
    }
}
