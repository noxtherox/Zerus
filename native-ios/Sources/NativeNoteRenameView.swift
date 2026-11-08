import SwiftUI

struct NativeNoteRenameView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: NoteSession
    @State private var title = ""
    @State private var renameFile = true
    @State private var snapshot: NativeRelationDefinitionSnapshot?
    @State private var review: NativeNoteRenamePlan?
    @State private var busy = false
    @State private var failure: String?
    private var managed: Bool { session.document.path.hasPrefix(".zerus/") }
    var body: some View {
        NavigationStack {
            Form {
                if let review {
                    Section {
                        LabeledContent("Title", value: review.title)
                        if managed { LabeledContent("File", value: "Managed record · unchanged") }
                        else {
                            LabeledContent("Current file", value: session.document.path)
                            LabeledContent("Resulting file", value: review.destination)
                        }
                        Text("These files are checked again and saved together. Cancel keeps the current title and files.").font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Changes") {
                        ForEach(Array(review.maintenance.summaries.enumerated()), id: \.offset) { _, item in Text(item) }
                        if review.changedFiles.contains(where: { $0.hasPrefix(".zerus/history/") }) { Label("Record this title change in Version history", systemImage: "clock") }
                    }
                    Section("Notes to update") {
                        ForEach(review.maintenance.changedNotes, id: \.self) { path in
                            Text(path.hasPrefix(".zerus/") ? review.title : path).font(.subheadline).textSelection(.enabled)
                        }
                    }
                    Button("Edit title") { self.review = nil }.disabled(busy).accessibilityIdentifier("rename.edit")
                } else {
                    Section {
                        TextField("Note title", text: $title).submitLabel(.done).accessibilityIdentifier("rename.title")
                        Toggle("Rename Markdown file", isOn: $renameFile).disabled(managed).accessibilityIdentifier("rename.file")
                    } footer: {
                        Text(managed ? "This managed record keeps its file name. Its title can change freely." : "The file stays in its current folder. Unsupported filename characters are replaced with dashes; the review shows the exact result. Case-only title changes keep the existing file spelling.")
                    }
                    if !managed { LabeledContent("Current file", value: session.document.path).font(.caption) }
                }
                if let failure { Section { Text(failure).foregroundStyle(.orange).textSelection(.enabled); Button("Reload current files") { Task { await reload(resetTitle: false) } }.disabled(busy).accessibilityIdentifier("rename.reload") } }
            }
            .navigationTitle(review == nil ? "Rename note" : "Review rename").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy).accessibilityIdentifier("rename.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() }
                    else if let review { Button("Rename") { commit(review) }.disabled(!review.maintenance.hasChanges).accessibilityIdentifier("rename.commit") }
                    else { Button("Review") { prepare() }.disabled(snapshot == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("rename.review") }
                }
            }
            .disabled(busy).interactiveDismissDisabled(busy)
            .task { await reload(resetTitle: true) }
        }
    }
    private func reload(resetTitle: Bool) async {
        busy = true; failure = nil; review = nil
        defer { busy = false }
        guard session.document.workspaceID == vault.workspaceID else { failure = "The vault changed. Reopen Rename."; return }
        if resetTitle { title = session.document.title; renameFile = !managed }
        await session.save()
        guard !session.dirty else { failure = session.failure ?? "Save or keep your draft before renaming."; return }
        do { snapshot = try await vault.relationDefinitionSnapshot() }
        catch { snapshot = nil; failure = error.localizedDescription }
    }
    private func prepare() {
        guard let snapshot else { return }
        busy = true; failure = nil
        Task {
            defer { busy = false }
            do { review = try await vault.prepareRename(snapshot, source: session.document.path, title: title, renameFile: renameFile) }
            catch { failure = error.localizedDescription }
        }
    }
    private func commit(_ plan: NativeNoteRenamePlan) {
        busy = true; failure = nil
        Task {
            defer { busy = false }
            do { try await vault.saveRelationMaintenance(plan.maintenance); dismiss() }
            catch { failure = error.localizedDescription }
        }
    }
}
