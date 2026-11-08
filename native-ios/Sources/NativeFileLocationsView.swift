import SwiftUI
import UniformTypeIdentifiers

struct NativeFileLocationsView: View {
    @EnvironmentObject private var vault: VaultStore
    let workspaceID: UUID
    @State private var labels: [String: String] = [:]
    @State private var naming = false
    @State private var editing: NativeFileLocation?
    @State private var name = ""
    @State private var mapping: NativeFileLocation?
    @State private var choosingFolder = false
    @State private var driveMapping: NativeFileLocation?
    @State private var driveAccount = false
    @State private var removing: NativeFileLocation?
    @State private var confirmingRemoval = false
    @State private var busy = false
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                Text("Map a shared location to its folder on this iPhone. Notes keep portable relative paths; folder access stays on this device.").font(.subheadline).foregroundStyle(.secondary)
                if let warning = vault.fileLocationIssue { Text(warning).font(.caption).foregroundStyle(.orange) }
                if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            }
            ForEach(vault.fileLocations) { location in
                Section {
                    LabeledContent("Location", value: location.name)
                    LabeledContent("On this device", value: labels[location.id] ?? "Not mapped")
                    let usages = vault.notes.filter { $0.property("zerus-file-location") == location.id }
                    Text("\(usages.count) connected \(usages.count == 1 ? "note" : "notes"), including Recently Deleted.").font(.caption).foregroundStyle(.secondary)
                    Button("Choose folder") { mapping = location; choosingFolder = true }.accessibilityIdentifier("filelocation.map." + location.id)
                    Button("Choose Google Drive folder", systemImage: "externaldrive.badge.icloud") { driveMapping = location }.accessibilityIdentifier("filelocation.drive." + location.id)
                    Button("Rename") { editing = location; name = location.name; naming = true }.accessibilityIdentifier("filelocation.rename." + location.id)
                    if labels[location.id] != nil { Button("Disconnect on this device") { perform { try await vault.mapFileLocation(location.id, folder: nil, workspace: workspaceID) } } }
                    Button("Remove unused location", role: .destructive) { removing = location; confirmingRemoval = true }.disabled(!usages.isEmpty)
                }
            }
            Section { Button("Add file location", systemImage: "folder.badge.plus") { editing = nil; name = ""; naming = true }.accessibilityIdentifier("filelocation.add") }
            Section { Button("Google Drive", systemImage: "externaldrive.badge.icloud") { driveAccount = true }.accessibilityIdentifier("filelocation.drive.account") }
        }.navigationTitle("File locations").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .disabled(busy)
            .sheet(item: $driveMapping, onDismiss: { Task { await reloadLabels() } }) { location in
                NativeDriveFolderBrowser { selection in try await vault.mapDriveLocation(location.id, selection: selection, workspace: workspaceID) }
            }
            .sheet(isPresented: $driveAccount) { NativeDriveFolderBrowser(choose: nil) }
            .task { await vault.refreshFileLocations(); await reloadLabels() }
            .refreshable { await vault.refresh(); await vault.refreshFileLocations(); await reloadLabels() }
            .alert(editing == nil ? "New file location" : "Rename location", isPresented: $naming) {
                TextField("Name", text: $name).accessibilityIdentifier("filelocation.name")
                Button("Cancel", role: .cancel) {}
                Button("Save") { let original = editing, name = name; perform { try await vault.changeFileLocation(original.map { .rename($0, name: name) } ?? .add(id: UUID().uuidString.lowercased(), name: name), workspace: workspaceID) } }
            } message: { Text("This name is shared with the vault. Each device chooses its own folder.") }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                guard let mapping else { return }
                switch result { case .success(let folder): perform { try await vault.mapFileLocation(mapping.id, folder: folder, workspace: workspaceID) }; case .failure(let error): issue = error.localizedDescription }
            }
            .confirmationDialog("Remove this unused location?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remove location", role: .destructive) { guard let removing else { return }; perform { try await vault.changeFileLocation(.remove(removing), workspace: workspaceID) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes its shared name. Original folders and files stay in place. A location used by any note cannot be removed.") }
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true; issue = nil
        Task { defer { busy = false }; do { try await action(); await reloadLabels() } catch is CancellationError {} catch { issue = error.localizedDescription } }
    }
    private func reloadLabels() async {
        var result: [String: String] = [:]
        for location in vault.fileLocations {
            do { result[location.id] = try await vault.locationMappingLabel(location.id, workspace: workspaceID) }
            catch is CancellationError { return } catch { issue = error.localizedDescription }
        }
        guard workspaceID == vault.workspaceID else { return }; labels = result
    }
}
