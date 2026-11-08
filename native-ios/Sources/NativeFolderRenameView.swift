import SwiftUI

struct NativeFolderRenameView: View {
    let folder: String
    let workspaceID: UUID
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var snapshot: NativeRelationDefinitionSnapshot?
    @State private var review: NativeFolderRenamePlan?
    @State private var busy = false
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            Form {
                if let review {
                    Section {
                        LabeledContent("From", value: review.source)
                        LabeledContent("To", value: review.destination)
                        Text("Move \(review.tree.files.count) \(review.tree.files.count == 1 ? "file" : "files") and \(review.tree.directories.count) \(review.tree.directories.count == 1 ? "folder" : "folders") together. Empty folders and other file contents are retained.")
                        Text("Update \(review.rewrittenLinks) \(review.rewrittenLinks == 1 ? "link destination" : "link destinations"). Folder definitions, icons, saved views and supporting-note references follow the new path. Files are checked again before saving.").foregroundStyle(.secondary)
                    }
                    if !review.updatedNotes.isEmpty {
                        Section("Notes to update") { ForEach(review.updatedNotes, id: \.self) { Text($0).font(.subheadline).textSelection(.enabled) } }
                    }
                    Button("Edit destination") { self.review = nil }
                } else {
                    Section {
                        LabeledContent("Current folder", value: folder)
                        TextField("New folder path", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("folder.rename.name")
                    } footer: { Text("Use / to choose another parent. The review includes subfolders and updates portable links. Cancel leaves the folder and its files unchanged.") }
                }
                if let issue { Section { Text(issue).foregroundStyle(.orange).textSelection(.enabled); Button("Reload current files") { Task { await reload() } } } }
            }.navigationTitle(review == nil ? "Rename folder" : "Review folder rename").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if let review { Button("Rename") { commit(review) }.accessibilityIdentifier("folder.rename.commit") }
                        else { Button("Review") { prepare() }.disabled(snapshot == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("folder.rename.review") }
                    }
                }.disabled(busy).interactiveDismissDisabled(busy)
                .overlay { if busy { ProgressView("Preparing folder…") } }
                .task { name = folder; await reload() }
                .onChange(of: vault.workspaceID) { _, value in if value != workspaceID { dismiss() } }
        }
    }
    private func reload() async {
        busy = true; issue = nil; review = nil; defer { busy = false }
        guard workspaceID == vault.workspaceID else { return }
        do { snapshot = try await vault.relationDefinitionSnapshot() }
        catch { snapshot = nil; issue = error.localizedDescription }
    }
    private func prepare() {
        guard let snapshot else { return }; busy = true; issue = nil
        Task { defer { busy = false }; do { review = try await vault.prepareFolderRename(snapshot, source: folder, destination: name) } catch { issue = error.localizedDescription } }
    }
    private func commit(_ plan: NativeFolderRenamePlan) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await vault.saveFolderRename(plan); dismiss() } catch { issue = error.localizedDescription } }
    }
}
