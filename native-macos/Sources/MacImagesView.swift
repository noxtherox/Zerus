import SwiftUI

struct MacImagesView: View {
    @Bindable var workspace: MacWorkspace
    let notePath: String?
    @State private var workspaceID: UUID
    /// The vault-wide reference check. It is loaded only when a change is
    /// reviewed, so listing and previewing images never waits for it.
    @State private var snapshot: NativeImageSnapshot?
    @State private var trash: NativeImageTrashIndex?
    @State private var review: MacImageReview?
    @State private var preview: NativeFileLease?
    @State private var page: String
    @State private var reattach = true
    @State private var issue: String?
    @State private var busy = false
    @State private var checking = false
    @Environment(\.dismiss) private var dismiss
    init(workspace: MacWorkspace, notePath: String? = nil) {
        self.workspace = workspace; self.notePath = notePath
        _workspaceID = State(initialValue: workspace.workspaceID); _page = State(initialValue: notePath == nil ? "Deleted" : "Note")
    }
    /// Saved note text from the last vault check, else the open note as shown.
    private var noteTitle: String? { workspace.notes.first { $0.path == notePath }?.title }
    private var noteBody: String {
        guard let notePath else { return "" }
        if let data = snapshot?.markdown[notePath], let content = NoteDocument.decodeUTF8(data) { return NoteDocument(path: notePath, content: content, modified: .distantPast).parts.body }
        if workspace.selection == notePath { return workspace.body }
        return workspace.notes.first { $0.path == notePath }?.parts.body ?? ""
    }
    private var entries: [NativeTrashedImage] { (snapshot?.index ?? trash)?.entries.sorted { $0.deletedAt > $1.deletedAt } ?? [] }
    var body: some View {
        let images = page == "Note" ? NativeInlineImage.occurrences(in: noteBody) : []
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Images").font(.title2.bold()); Spacer()
                if busy || checking { ProgressView().controlSize(.small); if checking { Text("Checking vault…").font(.caption).foregroundStyle(.secondary) } }
                Button("Refresh") { snapshot = nil; loadTrash() }.disabled(busy)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if notePath != nil { Picker("Images", selection: $page) { Text("In this note").tag("Note"); Text("Recently deleted").tag("Deleted") }.pickerStyle(.segmented) }
            if page == "Note" {
                Text(noteTitle ?? notePath ?? "Note").font(.headline)
                Text("Remove a single occurrence after review. Shared and retained image files stay available to saved notes and recovery data.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Restore deleted files to their original vault paths. Permanent deletion checks saved notes and recovery data again.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ScrollView { LazyVStack(alignment: .leading, spacing: 14) {
                if page == "Note" {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        HStack(alignment: .top) {
                            Image(systemName: "photo").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) { Text(image.caption.isEmpty ? "Image" : image.caption).font(.headline); Text(image.reference).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                            Spacer()
                            Button("Preview") { open { try await workspace.imageLease(image.reference, notePath: notePath, workspaceID: workspaceID) } }.disabled(URL(string: image.reference)?.scheme != nil).accessibilityLabel("Preview " + (image.caption.isEmpty ? "image" : image.caption) + ", occurrence " + String(index + 1))
                            Button("Remove…") { if let notePath { prepareRemoval(notePath, index: index, image: image) } }.disabled(busy).accessibilityLabel("Remove " + (image.caption.isEmpty ? "image" : image.caption) + ", occurrence " + String(index + 1))
                        }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if images.isEmpty { ContentUnavailableView("No images", systemImage: "photo", description: Text("Inline Markdown images in this note appear here.")) }
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 9) {
                            Label(entry.name, systemImage: "photo").font(.headline)
                            Text(entry.originalPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if let date = NativeRevisionIndex.date(entry.deletedAt) { Text(date, format: .dateTime).font(.caption).foregroundStyle(.secondary) }
                            HStack {
                                Button("Preview") { open { try await workspace.imageLease(entry.trashPath, workspaceID: workspaceID) } }.accessibilityLabel("Preview deleted " + entry.name).accessibilityIdentifier("image.preview.deleted." + entry.id)
                                Button("Restore…") { prepare(.restore(id: entry.id, reattach: reattach)) }.disabled(busy).accessibilityLabel("Restore " + entry.name).accessibilityIdentifier("image.restore." + entry.id)
                                Spacer(); Button("Delete permanently…", role: .destructive) { prepare(.purge(ids: [entry.id])) }.disabled(busy)
                            }.font(.caption)
                        }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if (snapshot?.index ?? trash)?.entries.isEmpty == true { ContentUnavailableView("No deleted images", systemImage: "photo", description: Text("Unused local images moved to Recently Deleted appear here.")) }
                }
            } }
            if let undo = workspace.imageUndo, undo.workspaceID == workspaceID {
                Button("Review undo of last removal…") { run { review = try await workspace.prepareImageUndo(undo) } }.disabled(busy)
            }
            if page == "Deleted", !entries.isEmpty { Toggle("Reattach restored images to their notes", isOn: $reattach).font(.caption) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(24).frame(width: 780, height: 570).interactiveDismissDisabled(busy)
        .task { loadTrash() }
        .onChange(of: workspace.workspaceID) { snapshot = nil; trash = nil; issue = "The vault changed. Close and reopen Images." }
        .macSheet(item: $preview) { MacLeasedPreview(lease: $0) }
        .macSheet(item: $review) { value in MacImageReviewView(workspace: workspace, review: value) { review = nil; snapshot = nil; loadTrash() } }
    }
    private func loadTrash() {
        Task { do { trash = try await workspace.imageTrashIndex(workspaceID: workspaceID) } catch { issue = error.localizedDescription } }
    }
    /// The full reference check runs when a change is reviewed. It saves the
    /// open note first, so a removal is located again in the saved text.
    private func currentSnapshot() async throws -> NativeImageSnapshot {
        if let snapshot { return snapshot }
        checking = true; defer { checking = false }
        let fresh = try await workspace.imageSnapshot(workspaceID: workspaceID)
        snapshot = fresh; trash = fresh.index
        return fresh
    }
    private func prepareRemoval(_ notePath: String, index: Int, image: NativeInlineImage) {
        run {
            let snapshot = try await currentSnapshot()
            let saved = snapshot.markdown[notePath].flatMap(NoteDocument.decodeUTF8).map { NoteDocument(path: notePath, content: $0, modified: .distantPast).parts.body } ?? ""
            let occurrences = NativeInlineImage.occurrences(in: saved)
            guard occurrences.indices.contains(index), occurrences[index].reference == image.reference, occurrences[index].caption == image.caption else {
                throw VaultFailure(message: "The note changed. Review the image again.")
            }
            review = try await workspace.prepareImageChange(snapshot, action: .remove(note: notePath, occurrence: occurrences[index]))
        }
    }
    private func prepare(_ action: NativeImageChange) { run { review = try await workspace.prepareImageChange(try await currentSnapshot(), action: action) } }
    private func open(_ lease: @escaping () async throws -> NativeFileLease) {
        Task { do { preview = try await lease() } catch { issue = error.localizedDescription } }
    }
    private func run(_ work: @escaping () async throws -> Void) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await work() } catch { issue = error.localizedDescription } }
    }
}

private struct MacImageReviewView: View {
    @Bindable var workspace: MacWorkspace
    let review: MacImageReview
    let applied: () -> Void
    @State private var busy = false
    @State private var issue: String?
    @State private var confirmed = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(review.plan.title).font(.title2.bold())
            Text(review.plan.explanation).textSelection(.enabled)
            ScrollView { VStack(alignment: .leading, spacing: 8) {
                let notes = review.plan.changes.map(\.path).filter { ["md", "markdown"].contains(($0 as NSString).pathExtension.lowercased()) }
                if !notes.isEmpty { Text("Notes").font(.headline); ForEach(notes, id: \.self) { Text($0).font(.caption).textSelection(.enabled) } }
                if !review.plan.files.isEmpty { Text("Vault files").font(.headline); ForEach(review.plan.files, id: \.self) { Text($0).font(.caption).textSelection(.enabled) } }
            }.frame(maxWidth: .infinity, alignment: .leading) }
            if review.plan.permanent { Toggle("I understand these deleted image files cannot be recovered after deletion.", isOn: $confirmed).font(.callout) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack { if busy { ProgressView().controlSize(.small) }; Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button(review.plan.permanent ? "Delete permanently" : "Confirm", role: review.plan.permanent ? .destructive : nil) {
                busy = true; issue = nil
                Task { defer { busy = false }; do { try await workspace.applyImageChange(review); applied(); dismiss() } catch { issue = error.localizedDescription } }
            }.disabled(review.plan.permanent && !confirmed) }
        }.padding(24).frame(width: 620, height: 430).disabled(busy).interactiveDismissDisabled(busy)
    }
}
