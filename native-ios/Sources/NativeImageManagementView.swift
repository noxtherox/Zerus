import SwiftUI

struct NativeImageManagementView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: NoteSession
    @State private var selected: NativeInlineImage?
    @State private var review: NativeImagePlan?
    @State private var undo: NativeImagePlan?
    @State private var preview: NativeFileLease?
    @State private var issue: String?
    @State private var busy = false
    private var occurrences: [NativeInlineImage] { NativeInlineImage.occurrences(in: session.document.parts.body) }
    var body: some View {
        NavigationStack {
            List {
                if let selected {
                    Section {
                        Label(selected.caption.isEmpty ? "Image" : selected.caption, systemImage: "photo").font(.headline)
                        Text(selected.reference).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Preview image", systemImage: "eye") {
                            run { guard let origin = session.document.workspaceID else { throw CancellationError() }; preview = try await vault.imageLease(selected.reference, notePath: session.document.path, workspace: origin) }
                        }.accessibilityIdentifier("image.preview").disabled(URL(string: selected.reference)?.scheme != nil)
                        Button("Remove from note…", systemImage: "trash", role: .destructive) {
                            run {
                                guard let origin = session.document.workspaceID else { throw CancellationError() }
                                let fresh = try await vault.imageSnapshot(workspace: origin)
                                review = try await vault.prepareImageChange(fresh, action: .remove(note: session.document.path, occurrence: selected))
                            }
                        }.accessibilityIdentifier("image.remove.review")
                        Button("All images", systemImage: "photo.on.rectangle") { self.selected = nil }
                    }
                } else {
                    Section {
                        if occurrences.isEmpty { ContentUnavailableView("No images", systemImage: "photo", description: Text("Inline Markdown images in this note appear here.")) }
                        ForEach(occurrences) { image in
                            Button { selected = image } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Label(image.caption.isEmpty ? "Image" : image.caption, systemImage: "photo")
                                    Text(image.reference).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                            }.accessibilityIdentifier("image.item." + image.id)
                        }
                    } footer: { Text("Choose an image occurrence to preview it or review its removal. Shared files stay available to other notes.") }
                }
                if let undo {
                    Section {
                        Label("Image removed", systemImage: "checkmark.circle")
                        Button("Undo removal", systemImage: "arrow.uturn.backward") { run { try await vault.undoImageChange(undo); self.undo = nil; selected = nil } }.accessibilityIdentifier("image.undo")
                    }
                }
                if let issue { Section { Text(issue).foregroundStyle(.red).textSelection(.enabled) } }
                if busy { ProgressView("Preparing image change…") }
            }
            .navigationTitle("Images").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("images.done").disabled(busy) } }
            .disabled(busy).interactiveDismissDisabled(busy)
            .sheet(item: $preview) { NativeFilePreview(lease: $0) }
            .sheet(isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } })) {
                if let plan = review {
                    NativeImageChangeReview(plan: plan) {
                        try await vault.saveImageChange(plan); undo = plan; selected = nil; review = nil
                    }
                }
            }
        }
    }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await work() } catch is CancellationError {} catch { issue = error.localizedDescription } }
    }
}

struct NativeImageTrashSection: View {
    @EnvironmentObject private var vault: VaultStore
    let workspaceID: UUID
    let reviewImage: (NativeImagePlan) -> Void
    let previewImage: (NativeFileLease) -> Void
    @State private var snapshot: NativeImageSnapshot?
    @State private var issue: String?
    @State private var busy = false
    @State private var reattach = true
    var body: some View {
        Section {
            if let snapshot {
                if snapshot.index.entries.isEmpty { Text("No deleted images").foregroundStyle(.secondary) }
                ForEach(snapshot.index.entries.sorted(by: { $0.deletedAt > $1.deletedAt })) { entry in
                    VStack(alignment: .leading, spacing: 9) {
                        Label(entry.name, systemImage: "photo").font(.headline)
                        Text(entry.originalPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let date = NativeRevisionIndex.date(entry.deletedAt) { Text("Deleted \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        Button("Preview deleted image", systemImage: "eye") {
                            busy = true; issue = nil
                            Task { defer { busy = false }; do { previewImage(try await vault.imageLease(entry.trashPath, workspace: workspaceID)) } catch { issue = error.localizedDescription } }
                        }.buttonStyle(.borderless).accessibilityIdentifier("trash.image.preview." + entry.id)
                        HStack {
                            Button("Restore", systemImage: "arrow.uturn.backward") { prepare(.restore(id: entry.id, reattach: reattach)) }.frame(minHeight: 44).accessibilityIdentifier("trash.image.restore." + entry.id)
                            Spacer()
                            Button("Delete permanently", systemImage: "trash.slash", role: .destructive) { prepare(.purge(ids: [entry.id])) }.frame(minHeight: 44).accessibilityIdentifier("trash.image.delete." + entry.id)
                        }.buttonStyle(.borderless).font(.subheadline)
                    }.padding(.vertical, 5)
                }
                if !snapshot.index.entries.isEmpty {
                    Toggle("Reattach restored images to their notes", isOn: $reattach)
                    Button("Review all deleted images", systemImage: "trash.slash", role: .destructive) { prepare(.purge(ids: Set(snapshot.index.entries.map(\.id)))) }.accessibilityIdentifier("trash.images.review")
                }
            } else if issue == nil { ProgressView("Loading deleted images…") }
            if let issue { Text(issue).font(.callout).foregroundStyle(.red); Button("Reload images") { Task { await reload() } } }
            if busy { ProgressView("Preparing image review…") }
        } header: { Text("Images") } footer: { Text("Restore images to their original vault paths. Permanent deletion checks saved notes and recovery data before removing files.") }
        .disabled(busy)
        .task(id: vault.schemaRevision) { await reload() }
    }
    private func reload() async {
        do { snapshot = try await vault.imageSnapshot(workspace: workspaceID); issue = nil } catch is CancellationError {} catch { issue = error.localizedDescription }
    }
    private func prepare(_ action: NativeImageChange) {
        guard let snapshot else { return }; busy = true; issue = nil
        Task { defer { busy = false }; do { reviewImage(try await vault.prepareImageChange(snapshot, action: action)) } catch is CancellationError {} catch { issue = error.localizedDescription } }
    }
}

struct NativeImageChangeReview: View {
    @Environment(\.dismiss) private var dismiss
    let plan: NativeImagePlan
    let apply: () async throws -> Void
    @State private var confirmation = false
    @State private var saving = false
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            List {
                Section { Text(plan.explanation) }
                if !plan.files.isEmpty { Section("Vault files") { ForEach(plan.files, id: \.self) { Text($0).font(.callout).textSelection(.enabled) } } }
                if let issue { Section { Text(issue).foregroundStyle(.red).textSelection(.enabled) } }
                Section {
                    Button(plan.permanent ? "Continue to permanent deletion…" : "Confirm", role: plan.permanent ? .destructive : nil) {
                        if plan.permanent { confirmation = true } else { save() }
                    }.accessibilityIdentifier("image.change.confirm")
                }
            }
            .navigationTitle(plan.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("image.change.cancel") } }
            .disabled(saving).interactiveDismissDisabled(saving)
            .overlay { if saving { ProgressView("Saving…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .confirmationDialog("Delete images permanently?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Delete images permanently", role: .destructive) { save() }; Button("Cancel", role: .cancel) {}
            } message: { Text("These deleted image files cannot be recovered through Recently Deleted after this step.") }
        }
    }
    private func save() {
        saving = true; issue = nil
        Task { defer { saving = false }; do { try await apply(); dismiss() } catch { issue = error.localizedDescription } }
    }
}
