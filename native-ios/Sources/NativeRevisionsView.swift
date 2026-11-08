import SwiftUI
import UIKit
import QuickLook

struct NativeRevisionsView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: NoteSession
    var initialRevision: String? = nil
    var didTrashNote: (() -> Void)? = nil
    @State private var snapshot: NativeRevisionSnapshot?
    @State private var selected: String?
    @State private var plan: NativeRevisionPlan?
    @State private var action: NativeRevisionAction?
    @State private var busy = false
    @State private var issue: String?
    @State private var review = false
    var body: some View {
        NavigationStack {
            Group {
                if let snapshot {
                    List {
                        Section {
                            Text("Create a revision when you reach a milestone. Earlier revisions keep their own copies of linked files.").font(.subheadline).foregroundStyle(.secondary)
                            Button { prepare(.create) } label: { Label("New revision", systemImage: "plus") }.accessibilityIdentifier("revision.create").disabled(snapshot.note.trashed)
                        }
                        Section("Revisions") {
                            ForEach(snapshot.index.revisions.filter { $0.deletedAt == nil }.sorted { $0.number > $1.number }) { revision in
                                row(revision, snapshot: snapshot)
                            }
                        }
                        let deleted = snapshot.index.revisions.filter { $0.deletedAt != nil }.sorted { $0.number > $1.number }
                        if !deleted.isEmpty {
                            Section("In Trash") { ForEach(deleted) { row($0, snapshot: snapshot) } }
                        }
                        if snapshot.note.trashed { Text("Restore the note from Trash before changing its revisions.").foregroundStyle(.secondary) }
                        if let issue { errorRow(issue) }
                    }
                } else if let issue {
                    ContentUnavailableView { Label("Revisions unavailable", systemImage: "clock.badge.exclamationmark") } description: { Text(issue) } actions: { Button("Try again") { Task { await reload() } } }
                } else { ProgressView("Loading revisions…") }
            }
            .navigationTitle("Revisions").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
            .disabled(busy)
            .overlay { if busy { ProgressView("Preparing revision…").padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
            .navigationDestination(item: $selected) { id in
                if let snapshot, let revision = snapshot.index.revisions.first(where: { $0.id == id }) {
                    NativeRevisionDetail(snapshot: snapshot, revision: revision, busy: busy, issue: issue, prepare: prepare, trashNote: trashWholeNote)
                }
            }
        }
        .task { await reload(); if let initialRevision, snapshot?.index.revisions.contains(where: { $0.id == initialRevision }) == true { selected = initialRevision } }
        .sheet(isPresented: $review) {
            if let plan, let action {
                NativeRevisionReview(plan: plan, action: action) {
                    do {
                        try await vault.saveRevision(plan)
                        review = false; selected = nil; await reload()
                    } catch { throw error }
                }
            }
        }
    }
    private func row(_ revision: NativeNoteRevision, snapshot: NativeRevisionSnapshot) -> some View {
        Button { selected = revision.id; issue = nil } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Revision \(revision.number)").font(.headline).foregroundStyle(.primary)
                    if let date = revision.date { Text(date, format: .dateTime.day().month().year().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if revision.id == snapshot.index.currentID { Text("Current").font(.caption).foregroundStyle(Accent.color) }
                if revision.deletedAt != nil { Image(systemName: "trash").foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }.accessibilityIdentifier("revision.row.\(revision.number)")
    }
    private func errorRow(_ text: String) -> some View { Section { Text(text).foregroundStyle(.red); Button("Reload revisions") { Task { await reload() } } } }
    private func reload() async {
        do { snapshot = try await vault.revisionSnapshot(note: session.document); issue = nil }
        catch { issue = error.localizedDescription }
    }
    private func prepare(_ action: NativeRevisionAction) {
        guard let snapshot, !busy else { return }
        busy = true; issue = nil
        Task {
            defer { busy = false }
            do { plan = try await vault.prepareRevision(snapshot, action: action); self.action = action; review = true }
            catch { issue = error.localizedDescription }
        }
    }
    private func trashWholeNote() {
        guard !busy else { return }
        busy = true; issue = nil
        Task {
            defer { busy = false }
            if await vault.move(session.document, trash: true) { dismiss(); didTrashNote?() }
            else { issue = vault.error ?? "The note could not move to Trash. Reload it before trying again." }
        }
    }
}

private struct NativeRevisionDetail: View {
    let snapshot: NativeRevisionSnapshot
    let revision: NativeNoteRevision
    let busy: Bool
    let issue: String?
    let prepare: (NativeRevisionAction) -> Void
    let trashNote: () -> Void
    @State private var source = false
    @State private var confirmWholeNote = false
    private var onlyRevision: Bool { snapshot.index.revisions.filter { $0.deletedAt == nil }.count == 1 }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Label(revision.id == snapshot.index.currentID ? "Current revision" : revision.deletedAt == nil ? "Earlier revision · Read-only" : "In Trash · Read-only", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
                if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
                if !snapshot.note.trashed {
                    HStack {
                        if revision.deletedAt != nil {
                            Button("Restore revision") { prepare(.restore(revision.id)) }.accessibilityIdentifier("revision.restore")
                        } else {
                            if revision.id != snapshot.index.currentID { Button("Make current") { prepare(.promote(revision.id)) }.accessibilityIdentifier("revision.promote") }
                            Spacer()
                            Button(role: .destructive) { if onlyRevision { confirmWholeNote = true } else { prepare(.trash(revision.id)) } } label: { Label("Move to Trash", systemImage: "trash") }.accessibilityIdentifier("revision.trash")
                        }
                    }.font(.subheadline).buttonStyle(.bordered)
                    if onlyRevision && revision.deletedAt == nil { Text("This is the only revision. Move the whole note to Trash to remove it.").font(.caption).foregroundStyle(.secondary) }
                }
                Toggle("Markdown source", isOn: $source).font(.caption)
            }.padding().background(Accent.paper)
            if let content = try? snapshot.content(for: revision) {
                NativeRevisionPreview(snapshot: snapshot, content: content, source: source)
            } else { ContentUnavailableView("Preview unavailable", systemImage: "doc.questionmark", description: Text("This revision has unsupported file metadata. Its saved data is preserved.")) }
        }.navigationTitle("Revision \(revision.number)").navigationBarTitleDisplayMode(.inline).disabled(busy)
        .confirmationDialog("Move the whole note to Trash?", isPresented: $confirmWholeNote, titleVisibility: .visible) {
            Button("Move note to Trash", role: .destructive, action: trashNote)
            Button("Cancel", role: .cancel) {}
        } message: { Text("This is the note’s only remaining revision. The note and all its versions stay together in Recently Deleted, where you can restore them.") }
    }
}

private struct NativeRevisionReview: View {
    @Environment(\.dismiss) private var dismiss
    let plan: NativeRevisionPlan
    let action: NativeRevisionAction
    let apply: () async throws -> Void
    @State private var saving = false
    @State private var issue: String?
    private var label: String {
        switch action { case .create: "Create revision"; case .promote: "Make current"; case .trash: "Move revision to Trash"; case .restore: "Restore revision" }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Review change") {
                    LabeledContent("Note", value: plan.snapshot.note.title)
                    LabeledContent("Action", value: label)
                    LabeledContent("File snapshots", value: String(plan.copiedFiles))
                    switch action {
                    case .create: Text("Keep the current text and files as the previous revision, then continue in a new revision.")
                    case .promote: Text("Create a new current revision from the selected text and files. Today’s note title and other properties stay in place.")
                    case .trash: Text("Keep this revision and its files in Trash. If it is current, the most recent remaining revision becomes current.")
                    case .restore: Text("Return this revision to the list. The current revision stays selected.")
                    }
                }
                Section("Resulting note") { Text(NoteDocument.split(plan.content).body).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                if let issue { Section { Text(issue).foregroundStyle(.red) } }
            }
            .navigationTitle("Review revision").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(label) {
                        saving = true
                        Task { defer { saving = false }; do { try await apply() } catch { issue = error.localizedDescription } }
                    }.disabled(saving).accessibilityIdentifier("revision.confirm")
                }
            }.interactiveDismissDisabled(saving)
            .overlay { if saving { ProgressView("Saving revision…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
    }
}

private struct NativeRevisionPreview: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.openURL) private var openURL
    let snapshot: NativeRevisionSnapshot
    let content: String
    let source: Bool
    @State private var images: [String: UIImage] = [:]
    @State private var file: URL?
    private struct FileReference: Identifiable {
        let id: String
        let name: String
        let path: String
    }
    private var files: [FileReference] {
        let props = NativeFrontmatter(content)
        var result: [FileReference] = []
        if props.entry("zerus-file-kind")?.value?.display == "vault", let path = props.entry("zerus-file-path")?.value?.display {
            result.append(.init(id: "document", name: props.entry("zerus-file-name")?.value?.display ?? "Document", path: path))
        }
        if case .list(let values) = props.entry("zerus-attachments")?.value {
            for value in values {
                if let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any], let id = object["id"] as? String, let name = object["name"] as? String, object["kind"] as? String == "vault", let path = object["path"] as? String {
                    result.append(.init(id: id, name: name, path: path))
                }
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }
    var body: some View {
        VStack(spacing: 0) {
            if !files.isEmpty {
                ScrollView(.horizontal) {
                    HStack { ForEach(files) { item in Button { openFile(item.path) } label: { Label(item.name, systemImage: "doc") }.buttonStyle(.bordered) } }.padding(.horizontal).padding(.vertical, 8)
                }
            }
            RevisionText(markdown: NoteDocument.split(content).body, source: source, images: images) { url in
                if ["https", "http", "mailto"].contains(url.scheme ?? "") { openURL(url) }
                else if url.scheme == "zerus-attachment", let item = files.first(where: { $0.id == String(url.absoluteString.dropFirst("zerus-attachment:".count)) }) { openFile(item.path) }
                else {
                    let reference = url.scheme == "zerus-image" ? String(url.absoluteString.dropFirst("zerus-image:".count)).removingPercentEncoding : url.scheme == nil ? url.relativeString : nil
                    if let reference { Task { file = await vault.assetURL(reference, notePath: snapshot.note.path, workspace: snapshot.workspaceID) } }
                }
            }
        }
        .quickLookPreview($file)
        .task(id: content) {
            images = [:]
            for reference in MarkdownText.imageReferences(NoteDocument.split(content).body) {
                guard !Task.isCancelled, let data = try? await vault.imageData(reference, notePath: snapshot.note.path, workspace: snapshot.workspaceID), let image = UIImage(data: data) else { continue }
                images[reference] = image
            }
        }
    }
    private func openFile(_ path: String) { Task { file = await vault.fileURL(path, workspace: snapshot.workspaceID) } }
}

struct RevisionText: UIViewRepresentable {
    let markdown: String
    let source: Bool
    let images: [String: UIImage]
    let open: (URL) -> Void
    var accessibilityID = "revision.preview"
    func makeCoordinator() -> Coordinator { Coordinator(open: open) }
    func makeUIView(context: Context) -> UITextView {
        let view = AdaptiveTextView(frame: .zero, textContainer: nil)
        view.isEditable = false; view.isSelectable = true; view.backgroundColor = NativeThemeUIKit.revisionBackground
        view.adjustsFontForContentSizeCategory = true; view.delegate = context.coordinator
        view.textContainerInset = .init(top: 20, left: 22, bottom: 30, right: 22)
        view.accessibilityIdentifier = accessibilityID
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let owner = context.coordinator, imageIDs = images.mapValues { ObjectIdentifier($0) }
        owner.open = open; view.accessibilityIdentifier = accessibilityID
        guard owner.markdown != markdown || owner.source != source || owner.imageIDs != imageIDs else { return }
        let preserveSelection = owner.markdown == markdown && owner.source == source
        let selected = view.selectedRange, offset = view.contentOffset
        (view as? AdaptiveTextView)?.sourceMode = source
        view.traitCollection.performAsCurrent {
            if source {
                let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
                view.attributedText = NSAttributedString(string: markdown, attributes: [.font: UIFont(descriptor: font.fontDescriptor.withDesign(.monospaced) ?? font.fontDescriptor, size: 0), .foregroundColor: NativeThemeUIKit.text])
            } else { view.attributedText = MarkdownText.render(markdown, images: images, width: max(140, view.bounds.width - 54)) }
        }
        owner.markdown = markdown; owner.source = source; owner.imageIDs = imageIDs
        if preserveSelection {
            let start = min(selected.location, view.attributedText.length)
            view.selectedRange = NSRange(location: start, length: min(selected.length, view.attributedText.length - start))
            view.setContentOffset(offset, animated: false)
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var open: (URL) -> Void
        var markdown: String?
        var source = false
        var imageIDs: [String: ObjectIdentifier] = [:]
        init(open: @escaping (URL) -> Void) { self.open = open }
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content else { return defaultAction }
            return UIAction { [open] _ in open(url) }
        }
    }
}
