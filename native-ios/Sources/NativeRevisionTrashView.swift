import SwiftUI

struct NativeRecentlyDeletedView: View {
    @EnvironmentObject private var vault: VaultStore
    let workspaceID: UUID
    @State private var snapshot: NativeRevisionTrashSnapshot?
    @State private var issue: String?
    @State private var busy = false
    @State private var imagePlan: NativeImagePlan?
    @State private var imagePreview: NativeFileLease?
    @State private var selection: Selection?
    @State private var plan: NativeRevisionTrashPlan?
    @State private var review = false
    @State private var notePlan: NativeNoteTrashPlan?
    @State private var noteReview = false
    @State private var preparation: Task<Void, Never>?
    @State private var preparationID = UUID()
    private enum Cleanup { case notes(NativeNoteTrashPlan), revisions(NativeRevisionTrashPlan) }
    private struct Selection: Identifiable {
        let note: NoteDocument
        let revision: String
        var id: String { note.path + ":" + revision }
    }
    var body: some View {
        List {
            NativeImageTrashSection(workspaceID: workspaceID, reviewImage: { imagePlan = $0 }, previewImage: { imagePreview = $0 })
            NativeFolderTrashSection(workspaceID: workspaceID)
            Section("Notes") {
                let notes = vault.notes.filter(\.trashed)
                if notes.isEmpty { Text("No deleted notes").foregroundStyle(.secondary) }
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 10) {
                        NoteRow(note: note)
                        HStack {
                            Button("Restore note", systemImage: "arrow.uturn.backward") {
                                Task { await vault.move(note, restore: true); await reload() }
                            }.accessibilityIdentifier("trash.restoreNote." + note.path)
                            Spacer()
                            Button("Delete permanently", systemImage: "trash.slash", role: .destructive) {
                                reviewNotes([note.path])
                            }.accessibilityIdentifier("trash.note.review." + note.path).disabled(snapshot == nil)
                        }.buttonStyle(.borderless).font(.subheadline)
                    }
                }
            }
            if vault.notes.contains(where: \.trashed) {
                Section {
                    Button("Review all deleted notes", systemImage: "trash.slash", role: .destructive) {
                        reviewNotes(Set(vault.notes.filter(\.trashed).map(\.path)))
                    }.accessibilityIdentifier("trash.notes.review").disabled(snapshot == nil)
                } footer: { Text("Review the note files, revisions, automatic history and unused vault copies before deleting them permanently. External originals and shared files are kept.") }
            }
            Section {
                if let snapshot {
                    if snapshot.entries.isEmpty { Text("No discarded revisions").foregroundStyle(.secondary) }
                    ForEach(snapshot.entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            if let origin = entry.note, let note = vault.notes.first(where: { $0.path == origin.path && $0.stableID == entry.noteID }) {
                                Button { selection = Selection(note: note, revision: entry.revision.id) } label: {
                                    HStack { Text(entry.title).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                                }.accessibilityIdentifier("trash.revision." + entry.id)
                            } else {
                                Text(entry.title)
                                Text("Restore or reconnect the original note to restore this revision.").font(.caption).foregroundStyle(.secondary)
                                ShareLink(item: entry.revision.content, preview: SharePreview(entry.title)) { Label("Share saved text", systemImage: "square.and.arrow.up") }
                            }
                            if let date = entry.revision.deletedAt.flatMap(NativeRevisionIndex.date) { Text("Deleted \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }
                } else if issue == nil { ProgressView("Loading discarded revisions…") }
            } header: { Text("Revisions") } footer: { Text("Moving a note to Recently Deleted keeps its revisions grouped until the note is restored or permanently deleted.") }
            if let snapshot, !snapshot.entries.isEmpty {
                Section {
                    Button("Review permanent revision cleanup", systemImage: "trash.slash", role: .destructive) {
                        prepare { .revisions(try await vault.prepareRevisionTrashPurge(snapshot)) }
                    }.accessibilityIdentifier("trash.revisions.review").disabled(!snapshot.problems.isEmpty || !snapshot.pending.isEmpty)
                } footer: { Text("Review discarded revisions and their unused files before deleting them permanently. Deleted notes are handled separately.") }
            }
            if let snapshot {
                ForEach(snapshot.problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                if !snapshot.pending.isEmpty { Text("An interrupted revision needs recovery. Open the original note’s revisions before permanent cleanup.").font(.caption).foregroundStyle(.orange) }
            }
            if let issue { Section { Text(issue).foregroundStyle(.red); Button("Try again") { Task { await reload() } } } }
        }
        .navigationTitle("Recently Deleted")
        .disabled(busy)
        .overlay {
            if busy {
                VStack(spacing: 16) {
                    ProgressView("Preparing cleanup…")
                    Button("Cancel") { cancelPreparation() }.buttonStyle(.bordered).accessibilityIdentifier("trash.preparation.cancel")
                }.padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .onDisappear { cancelPreparation() }
        .task(id: vault.schemaRevision) { await reload() }
        .refreshable { await vault.refresh(); await reload() }
        .sheet(item: $imagePreview) { NativeFilePreview(lease: $0) }
        .sheet(isPresented: Binding(get: { imagePlan != nil }, set: { if !$0 { imagePlan = nil } })) {
            if let plan = imagePlan { NativeImageChangeReview(plan: plan) { try await vault.saveImageChange(plan); imagePlan = nil; await reload() } }
        }
        .sheet(item: $selection, onDismiss: { Task { await reload() } }) { selected in
            if let session = vault.session(for: selected.note) { NativeRevisionsView(session: session, initialRevision: selected.revision) }
        }
        .sheet(isPresented: $review) {
            if let plan {
                NativeRevisionTrashReview(plan: plan) {
                    try await vault.saveRevisionTrashPurge(plan)
                    review = false; await reload()
                }
            }
        }
        .sheet(isPresented: $noteReview, onDismiss: { notePlan = nil }) {
            if let notePlan {
                NativeNoteTrashReview(plan: notePlan) {
                    try await vault.saveNoteTrashPurge(notePlan)
                    noteReview = false; await reload()
                }
            }
        }
    }
    private func reviewNotes(_ paths: Set<String>) {
        guard let snapshot else { return }
        prepare { .notes(try await vault.prepareNoteTrashPurge(snapshot, paths: paths)) }
    }
    private func cancelPreparation() {
        preparationID = UUID(); preparation?.cancel(); preparation = nil; busy = false
    }
    private func prepare(_ work: @escaping @MainActor () async throws -> Cleanup) {
        cancelPreparation()
        let generation = UUID(); preparationID = generation; busy = true; issue = nil
        preparation = Task {
            defer { if preparationID == generation { busy = false; preparation = nil } }
            do {
                let result = try await work()
                try Task.checkCancellation()
                guard preparationID == generation else { return }
                switch result {
                case .notes(let value): notePlan = value; noteReview = true
                case .revisions(let value): plan = value; review = true
                }
            } catch is CancellationError { }
            catch { if preparationID == generation { issue = error.localizedDescription } }
        }
    }
    private func reload() async {
        do { snapshot = try await vault.revisionTrashSnapshot(workspace: workspaceID); issue = nil }
        catch { issue = error.localizedDescription }
    }
}

private struct NativeRevisionTrashReview: View {
    @Environment(\.dismiss) private var dismiss
    let plan: NativeRevisionTrashPlan
    let apply: () async throws -> Void
    @State private var confirmation = false
    @State private var saving = false
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This permanently removes discarded revisions and files that no surviving note or revision uses. It cannot be undone.")
                    LabeledContent("Revisions", value: String(plan.deleted.count))
                    LabeledContent("Unused files", value: String(plan.removedFiles.count))
                    LabeledContent("File space", value: ByteCountFormatter.string(fromByteCount: Int64(plan.removedBytes), countStyle: .file))
                }
                Section("Discarded revisions") { ForEach(plan.deleted) { Text($0.title) } }
                if !plan.removedFiles.isEmpty {
                    Section("Files no longer used") {
                        ForEach(plan.removedFiles, id: \.self) { path in
                            VStack(alignment: .leading, spacing: 5) { Text((path as NSString).lastPathComponent); Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                    }
                }
                if let issue { Section { Text(issue).foregroundStyle(.red) } }
            }
            .navigationTitle("Review revision cleanup").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving).accessibilityIdentifier("trash.revisions.cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("Delete permanently", role: .destructive) { confirmation = true }.disabled(saving).accessibilityIdentifier("trash.revisions.delete") }
            }
            .confirmationDialog("Permanently delete \(plan.deleted.count) discarded revisions?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Delete revisions and unused files", role: .destructive) {
                    saving = true
                    Task { defer { saving = false }; do { try await apply() } catch { issue = error.localizedDescription } }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("These saved versions and \(plan.removedFiles.count) unused files cannot be recovered after deletion.") }
            .interactiveDismissDisabled(saving)
            .overlay { if saving { ProgressView("Deleting discarded revisions…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
    }
}
