import SwiftUI

struct NativeNoteTrashReview: View {
    @Environment(\.dismiss) private var dismiss
    let plan: NativeNoteTrashPlan
    let apply: () async throws -> Void
    @State private var confirmation = false
    @State private var saving = false
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This permanently removes the listed notes and their saved versions. Review the files below; deletion cannot be undone.")
                    LabeledContent("Notes", value: String(plan.deleted.count))
                    LabeledContent("Revisions", value: String(plan.removedRevisions))
                    LabeledContent("Automatic versions", value: String(plan.removedHistory))
                    LabeledContent("Unused files", value: String(plan.removedFiles.count))
                    LabeledContent("File space", value: ByteCountFormatter.string(fromByteCount: Int64(plan.removedBytes), countStyle: .file))
                }
                Section("Notes to remove") { ForEach(plan.deleted) { note in NoteRow(note: note) } }
                if !plan.removedFiles.isEmpty {
                    Section("Files to remove") { ForEach(plan.removedFiles, id: \.self) { file($0) } }
                }
                if !plan.retainedFiles.isEmpty {
                    Section("Shared or referenced files kept") { ForEach(plan.retainedFiles, id: \.self) { file($0) } }
                }
                Section("Kept outside this cleanup") { ForEach(plan.warnings, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) } }
                if let issue { Section { Text(issue).foregroundStyle(.red).textSelection(.enabled) } }
            }
            .navigationTitle("Review note cleanup").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving).accessibilityIdentifier("trash.notes.cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("Delete", role: .destructive) { confirmation = true }.disabled(saving).accessibilityIdentifier("trash.notes.delete") }
            }
            .confirmationDialog("Permanently delete \(plan.deleted.count) \(plan.deleted.count == 1 ? "note" : "notes")?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Delete notes and listed files", role: .destructive) {
                    saving = true
                    Task { defer { saving = false }; do { try await apply() } catch { issue = error.localizedDescription } }
                }.accessibilityIdentifier("trash.notes.confirm")
                Button("Cancel", role: .cancel) {}
            } message: { Text("The listed notes, their saved versions and \(plan.removedFiles.count) unused files cannot be recovered after deletion.") }
            .interactiveDismissDisabled(saving)
            .overlay { if saving { ProgressView("Deleting notes…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
    }
    private func file(_ path: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text((path as NSString).lastPathComponent)
            Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
