import SwiftUI

enum NativeFolderTrashRequest: Identifiable {
    case trash(String), restore(NativeFolderTrashEntry), purge(NativeFolderTrashEntry)
    var id: String {
        switch self { case .trash(let path): "trash:" + path; case .restore(let entry): "restore:" + entry.id.uuidString; case .purge(let entry): "purge:" + entry.id.uuidString }
    }
}

struct NativeFolderTrashReview: View {
    let request: NativeFolderTrashRequest
    let workspaceID: UUID
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var plan: NativeFolderTrashPlan?
    @State private var issue: String?
    @State private var preparing = false
    @State private var saving = false
    @State private var confirmPurge = false
    private var title: String { switch request { case .trash: "Review folder deletion"; case .restore: "Restore folder"; case .purge: "Review folder cleanup" } }
    private var action: String { switch request { case .trash: "Move to Trash"; case .restore: "Restore"; case .purge: "Delete permanently" } }
    var body: some View {
        NavigationStack {
            List {
                if let plan {
                    let record = plan.entry.record
                    Section {
                        Text(record.folder).font(.headline).textSelection(.enabled)
                        switch request {
                        case .trash: Text("Move this folder and all its contents to Recently Deleted. Restore the folder there to recover its notes, files, empty subfolders and folder settings together.")
                        case .restore: Text("Restore the complete folder to its original location. Its notes, files, empty subfolders and folder settings return together. Existing files or conflicting settings are kept and prevent restoration.")
                        case .purge: Text("Permanently remove this deleted folder, its files and its archived folder settings. This cannot be undone. Other saved revisions and automatic history are kept.")
                        }
                        LabeledContent("Notes", value: String(record.notes.count))
                        LabeledContent("All files", value: String(record.tree.files.count))
                        LabeledContent("Folders", value: String(record.tree.directories.count))
                    }
                    if !record.notes.isEmpty { Section("Notes") { ForEach(record.notes, id: \.self) { Text($0).textSelection(.enabled) } } }
                    let other = record.tree.files.keys.filter { !record.notes.contains($0) }.sorted()
                    if !other.isEmpty { Section("Other files") { ForEach(other, id: \.self) { Text($0).font(.subheadline).textSelection(.enabled) } } }
                    if !record.tree.directories.filter({ !$0.isEmpty }).isEmpty {
                        Section("Subfolders") { ForEach(record.tree.directories.filter { !$0.isEmpty }, id: \.self) { Text($0).font(.subheadline) } }
                    }
                } else if preparing { ProgressView("Reading folder…") }
                if let issue { Section { Text(issue).foregroundStyle(.orange).textSelection(.enabled); Button("Reload review") { Task { await reload() } } } }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving).accessibilityIdentifier("folder.trash.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action, role: request.isRestore ? nil : .destructive) {
                        if case .purge = request { confirmPurge = true } else { commit() }
                    }.disabled(plan == nil || saving || preparing).accessibilityIdentifier("folder.trash.apply")
                }
            }
            .disabled(saving)
            .interactiveDismissDisabled(saving)
            .overlay { if saving { ProgressView("Updating folder…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .task { await reload() }
            .onChange(of: vault.workspaceID) { _, value in if value != workspaceID { dismiss() } }
            .confirmationDialog("Permanently delete this folder and all its stored files?", isPresented: $confirmPurge, titleVisibility: .visible) {
                Button("Delete folder permanently", role: .destructive) { commit() }.accessibilityIdentifier("folder.trash.purge.confirm")
                Button("Cancel", role: .cancel) {}
            } message: { Text("This folder’s Trash copy cannot be recovered after deletion.") }
        }
    }
    private func reload() async {
        preparing = true; issue = nil; plan = nil; defer { preparing = false }
        do {
            let next: NativeFolderTrashPlan
            switch request {
            case .trash(let folder): next = try await vault.prepareFolderTrash(folder, workspace: workspaceID)
            case .restore(let entry): next = try await vault.prepareFolderRestore(entry, purge: false, workspace: workspaceID)
            case .purge(let entry): next = try await vault.prepareFolderRestore(entry, purge: true, workspace: workspaceID)
            }
            try Task.checkCancellation(); plan = next
        } catch is CancellationError {} catch { issue = error.localizedDescription }
    }
    private func commit() {
        guard let plan else { return }; saving = true; issue = nil
        Task { defer { saving = false }; do { try await vault.saveFolderTrash(plan); dismiss() } catch { issue = error.localizedDescription; self.plan = nil } }
    }
}
private extension NativeFolderTrashRequest {
    var isRestore: Bool { if case .restore = self { true } else { false } }
}

struct NativeFolderTrashSection: View {
    let workspaceID: UUID
    @EnvironmentObject private var vault: VaultStore
    @State private var snapshot: NativeFolderTrashSnapshot?
    @State private var issue: String?
    @State private var request: NativeFolderTrashRequest?
    var body: some View {
        Section {
            if let snapshot {
                if snapshot.entries.isEmpty && snapshot.issues.isEmpty { Text("No deleted folders").foregroundStyle(.secondary) }
                ForEach(snapshot.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                ForEach(snapshot.entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(entry.record.folder, systemImage: "folder").font(.headline)
                        Text("Notes: \(entry.record.notes.count) · Files: \(entry.record.tree.files.count)").font(.caption).foregroundStyle(.secondary)
                        Text("Deleted \(entry.record.deletedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Restore folder", systemImage: "arrow.uturn.backward") { request = .restore(entry) }.accessibilityIdentifier("folder.trash.restore." + entry.id.uuidString)
                            Spacer()
                            Button("Delete permanently", systemImage: "trash.slash", role: .destructive) { request = .purge(entry) }.accessibilityIdentifier("folder.trash.purge." + entry.id.uuidString)
                        }.font(.subheadline).buttonStyle(.borderless)
                    }.padding(.vertical, 4)
                }
            } else if issue == nil { ProgressView("Loading deleted folders…") }
            if let issue { Text(issue).foregroundStyle(.orange); Button("Reload folders") { Task { await reload() } } }
        } header: { Text("Folders") } footer: { Text("Deleted folders keep their notes, attachments, empty subfolders and folder settings together until you restore or permanently delete them.") }
        .task(id: vault.schemaRevision) { await reload() }
        .sheet(item: $request, onDismiss: { Task { await reload() } }) { request in NativeFolderTrashReview(request: request, workspaceID: workspaceID) }
    }
    private func reload() async {
        do { snapshot = try await vault.folderTrashSnapshot(workspace: workspaceID); issue = nil }
        catch { issue = error.localizedDescription }
    }
}
