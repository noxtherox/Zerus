import SwiftUI
import AppKit

struct MacRecoveryView: View {
    @Bindable var workspace: MacWorkspace
    let request: MacRecoveryRequest
    @State private var snapshot: MacRecoverySnapshot?
    @State private var history: Bool
    @State private var selected: String?
    @State private var review: MacRecoveryReview?
    @State private var source = false
    @State private var compareParent = false
    @State private var kept = false
    @State private var label = ""
    @State private var management = false
    @State private var busy = false
    @State private var issue: String?
    @State private var notice: String?
    @State private var file: NativeFileLease?
    @Environment(\.dismiss) private var dismiss
    init(workspace: MacWorkspace, request: MacRecoveryRequest) {
        self.workspace = workspace; self.request = request
        _history = State(initialValue: request.history); _selected = State(initialValue: request.selectedID)
    }
    private var revision: NativeNoteRevision? { snapshot?.revisions?.index.revisions.first { $0.id == selected && $0.deletedAt == nil } }
    private var version: NativeHistoryVersion? { snapshot?.history?.versions.first { $0.id == selected } }
    private var previewContent: String? {
        guard let snapshot else { return nil }
        if history { return version?.content }
        guard let revision else { return nil }
        return try? snapshot.revisions?.content(for: revision)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(review == nil ? "Revisions & history" : "Review recovery").macFont(.title2.bold()); Spacer(); if busy { ProgressView().controlSize(.small) }; Button("Done") { dismiss() }.disabled(busy) }
            if let review { reviewPane(review) }
            else if let snapshot { browser(snapshot) }
            else { ContentUnavailableView("Loading recovery", systemImage: "clock.arrow.circlepath", description: Text("Save the current note and read its saved versions.")) }
            if let notice { Text(notice).macFont(.caption).foregroundStyle(.secondary) }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(20).frame(width: 1080, height: 720).disabled(busy).interactiveDismissDisabled(busy)
        .task { await reload() }
        .onChange(of: workspace.workspaceID) { snapshot = nil; review = nil; issue = "The vault changed. Close and reopen recovery." }
        .macSheet(item: $file) { MacLeasedPreview(lease: $0) }
        .macSheet(isPresented: $management, onDismiss: { Task { await reload() } }) { MacHistoryManagementView(workspace: workspace, noteID: snapshot?.note.stableID) }
        .onChange(of: selected) { loadAnnotation() }
    }
    private func browser(_ snapshot: MacRecoverySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Saved versions", selection: $history) { Text("Revisions").tag(false); Text("Automatic history").tag(true) }.pickerStyle(.segmented).frame(width: 370).onChange(of: history) { selected = history ? snapshot.history?.versions.first?.id : snapshot.revisions?.index.currentID; loadAnnotation(); issue = nil }
                Spacer(); Button("Refresh") { Task { await reload() } }
            }
            Text(snapshot.note.title).macFont(.headline)
            if let unavailable = history ? snapshot.historyIssue : snapshot.revisionIssue { Text(unavailable).macFont(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if let other = history ? snapshot.revisionIssue : snapshot.historyIssue { Text((history ? "Revisions are unavailable: " : "Automatic history is unavailable: ") + other).macFont(.caption).foregroundStyle(.secondary).lineLimit(2) }
            MacZoomSplitView {
                ScrollView { VStack(alignment: .leading, spacing: 5) {
                    if history {
                        ForEach(snapshot.history?.versions ?? []) { version in
                            versionButton(version.id, title: version.label ?? version.timestamp, detail: (version.source == "mobile" ? "Apple app" : version.source) + (version.kept ? " · kept" : "") + (version.incomplete ? " · incomplete" : ""))
                        }
                        if snapshot.history?.versions.isEmpty == true { Text("No automatic versions yet.").macFont(.caption).foregroundStyle(.secondary).padding() }
                    } else {
                        ForEach((snapshot.revisions?.index.revisions ?? []).filter { $0.deletedAt == nil }) { revision in
                            versionButton(revision.id, title: "v\(revision.number)" + (revision.id == snapshot.revisions?.index.currentID ? " · current" : ""), detail: revision.createdAt)
                        }
                    }
                }.padding(5) }.frame(minWidth: 245, idealWidth: 270, maxWidth: 310)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Toggle(history && compareParent ? "Show internal properties" : "Show Markdown & properties", isOn: $source).toggleStyle(.checkbox); Spacer(); if history { Toggle("Compare with parent", isOn: $compareParent).toggleStyle(.checkbox) } }
                    if history && compareParent, let version {
                        parentComparison(version, snapshot: snapshot)
                    } else if let content = previewContent {
                        if history, let version {
                            MacHistoryVersionBody(workspace: workspace, snapshot: snapshot, version: version, source: source, onLink: { previewLink($0, content: content) })
                                .id(request.workspaceID.uuidString + version.id + NativeHistory.hash(version.bytes))
                        } else {
                            MacRecoveryText(content: content, source: source, root: snapshot.root, path: request.path, images: [:], onLink: { previewLink($0, content: content) })
                            savedFiles(content)
                        }
                    } else { ContentUnavailableView("Select a saved version", systemImage: "doc.text.magnifyingglass") }
                }.frame(minWidth: 580, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.frame(maxHeight: .infinity)
            if history {
                if let version {
                    HStack { Toggle("Keep version", isOn: $kept).toggleStyle(.checkbox); TextField("Version label (optional)", text: $label).textFieldStyle(.roundedBorder); Button("Save label & keep") { saveAnnotation(snapshot, version: version) }.disabled(kept == version.kept && label.trimmingCharacters(in: .whitespacesAndNewlines) == (version.label ?? "")) }
                }
                if let problems = snapshot.history?.problems, !problems.isEmpty { Text(problems.joined(separator: "\n")).macFont(.caption).foregroundStyle(.orange).lineLimit(3) }
                HStack { Button("History settings…") { management = true }; Text("Restoring requires a review first.").macFont(.caption).foregroundStyle(.secondary); Spacer(); Button("Review restore…") { prepareHistory(snapshot) }.disabled(version == nil || version?.incomplete == true) }
            } else {
                HStack {
                    Button("New revision…") { prepare(snapshot, action: .create) }.disabled(snapshot.revisions == nil)
                    Spacer()
                    Button("Move revision to Trash…") { if let revision { prepare(snapshot, action: .trash(revision.id)) } }.disabled(revision == nil)
                    Button("Make current…") { if let revision { prepare(snapshot, action: .promote(revision.id)) } }.disabled(revision == nil || revision?.id == snapshot.revisions?.index.currentID)
                }
            }
        }
    }
    @ViewBuilder private func parentComparison(_ version: NativeHistoryVersion, snapshot: MacRecoverySnapshot) -> some View {
        if let content = version.content {
            if let id = version.parentID {
                let parents = snapshot.history?.versions.filter { $0.id == id } ?? []
                if parents.count == 1, let parent = parents.first, let before = parent.content {
                    Text("Compared with " + (parent.label ?? parent.timestamp)).macFont(.caption).foregroundStyle(.secondary)
                    MacHistoryDifferenceView(before: source ? before : NativeHistory.stripped(before), after: source ? content : NativeHistory.stripped(content))
                } else { ContentUnavailableView("Parent version unavailable", systemImage: "doc.badge.exclamationmark", description: Text("Restore the missing or incomplete parent record to compare these versions. Its saved data is preserved.")) }
            } else {
                Text("Initial version · compared with an empty note").macFont(.caption).foregroundStyle(.secondary)
                MacHistoryDifferenceView(before: "", after: source ? content : NativeHistory.stripped(content))
            }
        } else { ContentUnavailableView("Saved text unavailable", systemImage: "doc.badge.exclamationmark", description: Text("This version has missing text. Restore its required history records before comparing.")) }
    }
    private func versionButton(_ id: String, title: String, detail: String) -> some View {
        Button { selected = id; issue = nil; notice = nil } label: {
            VStack(alignment: .leading, spacing: 4) { Text(title).macFont(.headline); Text(detail).macFont(.caption).foregroundStyle(.secondary) }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(selected == id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(MacBoxButtonStyle()).accessibilityLabel(title + ", " + detail).accessibilityAddTraits(selected == id ? .isSelected : [])
    }
    private func reviewPane(_ review: MacRecoveryReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(review.label + " · " + review.note.title).macFont(.headline)
            Text(review.explanation).macFont(.callout).foregroundStyle(.secondary)
            Toggle("Show Markdown & properties", isOn: $source).toggleStyle(.checkbox)
            MacZoomSplitView {
                comparison("Current note", content: review.note.content, root: workspace.root, images: [:])
                comparison("Result after confirmation", content: review.content, root: nil, images: review.images)
            }
            if !review.resources.isEmpty {
                Text("New saved file snapshots: \(review.resources.filter { $0.before == nil }.count)").macFont(.caption.bold())
                ScrollView(.horizontal) { HStack { ForEach(review.resources.filter { $0.before == nil }, id: \.path) { item in Button(resourceLabel(item, review: review)) { do { file = try workspace.recoveryResource(item, review: review) } catch { issue = error.localizedDescription } }.help(item.path) } } }.frame(maxHeight: 32)
            }
            HStack { Button("Back") { self.review = nil; issue = nil }; Spacer(); Button("Cancel") { self.review = nil; issue = nil }; Button(review.label) { commit(review) }.keyboardShortcut(.defaultAction) }
        }
    }
    private func comparison(_ title: String, content: String, root: URL?, images: [String: NSImage]) -> some View {
        VStack(alignment: .leading) { Text(title).macFont(.caption.bold()); MacRecoveryText(content: content, source: source, root: root, path: request.path, images: images, onLink: { previewLink($0, content: content, review: review) }) }.frame(minWidth: 450, maxWidth: .infinity)
    }
    private func resourceLabel(_ item: VaultFileChange, review: MacRecoveryReview) -> String {
        let name = (item.path as NSString).lastPathComponent.replacingOccurrences(of: #"^\d+-"#, with: "", options: .regularExpression)
        let note = NoteDocument(path: review.note.path, content: review.content, modified: Date())
        let paths = Set(NativeFileAttachment.all(in: review.content).map(\.path) + (note.fileHub?.path.map { [$0] } ?? []) + MarkdownText.imageReferences(note.parts.body).compactMap { URL(string: $0)?.relativePath })
        let result = paths.contains(item.path)
        return (result ? "Result: " : "Current backup: ") + name
    }
    private func previewLink(_ value: String, content: String, review: MacRecoveryReview? = nil) {
        if let url = URL(string: value), ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url); return }
        guard value.hasPrefix("zerus-attachment:"), let attachment = NativeFileAttachment.all(in: content).first(where: { $0.id == String(value.dropFirst("zerus-attachment:".count)) }) else { issue = "Use the saved-file buttons to preview resources. Open note links from the workspace after closing recovery."; return }
        Task { do {
            if let review, let item = review.resources.first(where: { $0.path == attachment.path }) { file = try workspace.recoveryResource(item, review: review) }
            else { file = try await workspace.imageLease(attachment.path, workspaceID: request.workspaceID) }
        } catch { issue = error.localizedDescription } }
    }
    @ViewBuilder private func savedFiles(_ content: String) -> some View {
        let note = NoteDocument(path: request.path, content: content, modified: Date())
        let files = (note.fileHub.map { [$0] } ?? []) + NativeFileAttachment.all(in: content).map { NativeFileHub(id: $0.id, name: $0.name, kind: .vault, path: $0.path) }
        if !files.isEmpty { ScrollView(.horizontal) { HStack { ForEach(files, id: \.id) { item in Button(item.name) { Task { do { guard let path = item.path, item.kind == .vault else { throw VaultFailure(message: "This saved revision refers to an external connection.") }; file = try await workspace.imageLease(path, workspaceID: request.workspaceID) } catch { issue = error.localizedDescription } } } } } }.frame(maxHeight: 32) }
    }
    private func reload() async {
        busy = true; issue = nil; defer { busy = false }
        do {
            snapshot = try await workspace.recoverySnapshot(request)
            let available = history
                ? snapshot?.history?.versions.contains { $0.id == selected } == true
                : snapshot?.revisions?.index.revisions.contains { $0.id == selected && $0.deletedAt == nil } == true
            // A removed revision must not remain as an unlisted preview with
            // live actions. Keep valid selection; otherwise show the current one.
            if !available { selected = history ? snapshot?.history?.versions.first?.id : snapshot?.revisions?.index.currentID }
            loadAnnotation()
        }
        catch { issue = error.localizedDescription }
    }
    private func loadAnnotation() { kept = version?.kept ?? false; label = version?.label ?? "" }
    private func saveAnnotation(_ snapshot: MacRecoverySnapshot, version: NativeHistoryVersion) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await workspace.saveHistoryAnnotation(snapshot, id: version.id, kept: kept, label: label); notice = "Version label and Keep saved."; await reload() } catch { issue = error.localizedDescription } }
    }
    private func prepare(_ snapshot: MacRecoverySnapshot, action: NativeRevisionAction) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { review = try await workspace.prepareRecovery(snapshot, action: action) } catch { issue = error.localizedDescription } }
    }
    private func prepareHistory(_ snapshot: MacRecoverySnapshot) {
        guard let selected else { return }; busy = true; issue = nil
        Task { defer { busy = false }; do { review = try await workspace.prepareHistoryRecovery(snapshot, id: selected) } catch { issue = error.localizedDescription } }
    }
    private func commit(_ review: MacRecoveryReview) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await workspace.commitRecovery(review); notice = review.label + " saved."; self.review = nil; await reload() } catch { issue = error.localizedDescription } }
    }
}

/// Selection identity resets page state. SwiftUI cancels old reads when leaving
/// a version, and the model checks the vault activation again after each await.
private struct MacHistoryVersionBody: View {
    @Bindable var workspace: MacWorkspace
    let snapshot: MacRecoverySnapshot
    let version: NativeHistoryVersion
    let source: Bool
    let onLink: (String) -> Void
    @State private var page = 0
    @State private var preview: MacHistoryPreview?
    @State private var loadedPage: Int?
    @State private var loading = false
    @State private var issue: String?
    @State private var retry = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MacRecoveryText(content: source ? (version.content ?? "") : (preview?.content ?? version.content ?? ""), source: source, root: nil, path: snapshot.note.path, images: loadedPage == page ? preview?.images ?? [:] : [:], onLink: onLink)
            HStack {
                if loading { ProgressView().controlSize(.mini); Text("Loading saved images…").macFont(.caption) }
                if let preview, preview.imageCount > 0 {
                    Text("Saved images \(preview.page * MacHistoryPreview.pageSize + 1)–\(min(preview.imageCount, (preview.page + 1) * MacHistoryPreview.pageSize)) of \(preview.imageCount)").macFont(.caption).foregroundStyle(.secondary)
                    if preview.pages > 1 {
                        Button("Previous images") { page = max(0, page - 1) }.disabled(loading || page == 0)
                        Button("Next images") { page += 1 }.disabled(loading || page + 1 >= preview.pages)
                    }
                }
                Spacer(); Button("Reload saved images") { retry = UUID() }.disabled(loading)
            }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if loadedPage == page, let preview, !preview.warnings.isEmpty { Text(preview.warnings.joined(separator: "\n")).macFont(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }
        .task(id: "\(page):\(retry)") {
            let requestedPage = page, request = retry
            loading = true; issue = nil
            do {
                let value = try await workspace.historyPreview(snapshot, id: version.id, page: requestedPage)
                try Task.checkCancellation()
                guard page == requestedPage, retry == request else { return }
                preview = value; loadedPage = requestedPage
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, page == requestedPage, retry == request else { return }
                preview = nil; loadedPage = nil; issue = error.localizedDescription
            }
            loading = false
        }
    }
}

/// Read-only TextKit surface also renders staged image bytes before their vault
/// destination exists. It never participates in the active editor's undo stack.
private struct MacRecoveryText: NSViewRepresentable {
    let content: String
    let source: Bool
    let root: URL?
    let path: String
    let images: [String: NSImage]
    var onLink: (String) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(onLink) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var open: (String) -> Void
        init(_ open: @escaping (String) -> Void) { self.open = open }
        func textView(_ view: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            open((link as? URL)?.absoluteString ?? String(describing: link)); return true
        }
    }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true
        let text = NSTextView(); text.isEditable = false; text.isSelectable = true; text.isRichText = true
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 18, height: 18); text.delegate = context.coordinator; scroll.documentView = text
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let text = view.documentView as? NSTextView else { return }
        context.coordinator.open = onLink
        let body = NoteDocument.split(content).body
        let rich = source || MacMarkdown.requiresSource(body) ? NSAttributedString(string: source ? content : body, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.labelColor]) : MacMarkdown.render(body, root: root, path: path, images: images)
        if !text.attributedString().isEqual(to: rich) { text.textStorage?.setAttributedString(rich) }
    }
}
