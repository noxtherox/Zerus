import SwiftUI
import UniformTypeIdentifiers

struct NativeExternalNotesView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var external: NativeExternalNotesModel
    let openVaultNote: (NoteDocument) -> Void
    @State private var query = ""
    @State private var settings = false
    @State private var picker = false
    @State private var creating = false
    @State private var createdURL: URL?
    @State private var locating: NativeExternalEntry?
    @State private var recoveryEntry: NativeExternalEntry?
    @State private var selected: NativeExternalNoteSession?
    @State private var pendingMove: NativeExternalMoveRecord?
    @State private var forgetting: NativeExternalEntry?
    @State private var issue: String?
    @State private var busy = false
    private var entries: [NativeExternalEntry] { external.entries.filter { query.isEmpty || $0.name.localizedStandardContains(query) } }
    var body: some View {
        List {
            Section {
                Button("Open Markdown in Files", systemImage: "doc.badge.plus") { locating = nil; picker = true }.accessibilityIdentifier("external.open")
                Button("New Markdown file…", systemImage: "square.and.pencil") { creating = true }.accessibilityIdentifier("external.new")
            } footer: { Text("Edit the selected file in place. It stays outside your vault; closing or removing it from this list keeps the original file.") }
            if entries.isEmpty, !busy {
                ContentUnavailableView(query.isEmpty ? "Your files, in place." : "No matching files", systemImage: "doc.text", description: Text(query.isEmpty ? "Open a Markdown file from Files to write with the native editor." : "Try another filename."))
            }
            if !external.pendingMoves.isEmpty {
                Section("Pending moves") {
                    ForEach(external.pendingMoves) { record in
                        Button { pendingMove = record } label: { Label(record.sourceName, systemImage: "arrow.triangle.2.circlepath") }
                            .accessibilityIdentifier("external.pendingMove." + record.id.uuidString)
                    }
                }
            }
            ForEach(entries) { entry in
                Button { open(entry) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(entry.name, systemImage: "doc.text").font(.headline).foregroundStyle(.primary)
                        Text(entry.parent).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }.accessibilityIdentifier("external.file." + entry.id.uuidString)
                    .contextMenu {
                        Button("Locate original file…", systemImage: "folder") { locating = entry; picker = true }
                        Button("Recovery draft…", systemImage: "clock.arrow.circlepath") { recoveryEntry = entry }
                        Button("Stop tracking", systemImage: "xmark.circle") { forgetting = entry }
                    }
            }
            if let message = issue ?? external.issue { Section { Text(message).foregroundStyle(.red).textSelection(.enabled); Button("Reload list") { Task { await external.restore() } } } }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Settings") } }
        .sheet(isPresented: $settings) { SettingsView() }
        .navigationTitle("External notes").searchable(text: $query, prompt: "Search filenames")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .disabled(busy).overlay { if busy { ProgressView("Opening file…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .task { await external.restore() }.refreshable { await external.refresh() }
        .fileImporter(isPresented: $picker, allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]) { result in
            switch result {
            case .success(let url):
                run {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let locating { selected = try await external.locate(locating, url: url); self.locating = nil; return }
                    let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                    if let root = vault.root, let note = vault.notes.first(where: { root.appendingPathComponent($0.path).resolvingSymlinksInPath().standardizedFileURL == canonical }) { openVaultNote(note) }
                    else { selected = try await external.open(url) }
                }
            case .failure(let error): issue = error.localizedDescription
            }
        }
        .fullScreenCover(item: $selected, onDismiss: { Task { await external.restore() } }) { NativeExternalEditorScreen(session: $0) }
        .sheet(isPresented: $creating, onDismiss: {
            if let url = createdURL {
                createdURL = nil
                run {
                    await vault.refresh()
                    let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                    if let root = vault.root, let note = vault.notes.first(where: { root.appendingPathComponent($0.path).resolvingSymlinksInPath().standardizedFileURL == canonical }) { openVaultNote(note) }
                    else { selected = try await external.open(url) }
                }
            }
        }) { NativeExternalCreateView { createdURL = $0 } }
        .sheet(item: $recoveryEntry) { NativeExternalRecoveryView(entry: $0) }
        .sheet(item: $pendingMove) { NativeExternalMoveRecoveryView(record: $0) }
        .alert("Stop tracking this file?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
            if let entry = forgetting { Button("Stop tracking") { run { try await external.forget(entry); forgetting = nil } } }
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: { Text("The original Markdown file stays in Files. Unsaved drafts must be kept or reloaded first.") }
    }
    private func open(_ entry: NativeExternalEntry) { run { selected = try await external.open(entry) } }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await work() } catch is CancellationError {} catch { issue = error.localizedDescription } }
    }
}

struct NativeExternalEditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var external: NativeExternalNotesModel
    @EnvironmentObject private var vault: VaultStore
    @ObservedObject var session: NativeExternalNoteSession
    @StateObject private var actions = NativeEditorActions()
    @State private var finding: NativeNoteFindSnapshot?
    @State private var revealFound: (() -> Bool)?
    @State private var findIssue: String?
    @State private var markdownAnalysis = MarkdownText.Analysis()
    @AppStorage("zerus.native.codeBlocks") private var codeBlocks = false
    @State private var source = false
    @State private var clipboardIssue: String?
    @State private var clipboardBusy = false
    @State private var code: CodeEditRequest?
    @State private var table: TableEditRequest?
    @State private var reload = false
    @State private var reviewingIssue = false
    @State private var reloadAfterIssue = false
    @State private var closing = false
    @State private var project: NativeExternalProjectFiles?
    @State private var projectPresentation: UUID?
    @State private var projectPicker = false
    @State private var attachments = false
    @State private var projectIssue: String?
    @State private var imageGeneration = UUID()
    @State private var imagePresentation: UUID?
    @State private var imageProject: UUID?
    @State private var imageLoad = UUID()
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var loadedImageVersions: [String: NativeExternalProjectFiles.ImageVersion] = [:]
    @State private var loadedImageGenerations: [String: UUID] = [:]
    @State private var imageLoading = false
    @State private var unavailableImages = 0
    @State private var preview: NativeFileLease?
    @State private var linkedNote: NativeOpenedNote?
    @State private var transferMode: NativeExternalTransferMode?
    @State private var transferredOriginal = false
    @State private var editorID = UUID()
    private struct ImageRequest: Equatable {
        let presentation: UUID
        let project: UUID?
        let references: [String]
        let resourceRevision: Int
        let generation: UUID
    }
    private var activeProject: NativeExternalProjectFiles? { projectPresentation == session.presentationID ? project : nil }
    private var images: [String: UIImage] { imagePresentation == session.presentationID && imageProject == activeProject?.id ? loadedImages : [:] }
    private var imageRequest: ImageRequest {
        .init(presentation: session.presentationID, project: activeProject?.id,
              references: source || sourceOnly ? [] : markdownAnalysis.imageReferences(session.document.parts.body).filter { URL(string: $0)?.scheme == nil || URL(string: $0)?.isFileURL == true }, resourceRevision: session.resourceRevision, generation: imageGeneration)
    }
    @Environment(\.openURL) private var openURL
    private var sourceOnly: Bool { markdownAnalysis.requiresSource(session.document.parts.body) }
    var body: some View {
        let destination = activeProject
        NavigationStack {
            VStack(spacing: 0) {
                statusLayout {
                    Label("External file", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Text(!session.active ? "Connection closed" : session.saving ? "Saving…" : session.dirty ? (session.canCloseSafely ? "Draft kept on device" : "Unsaved changes") : session.failure != nil ? "Needs attention" : "Saved")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("external.saveStatus")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.vertical, 10)
                if session.failure != nil {
                    Button { actions.finishEditing(); reviewingIssue = true } label: {
                        Label("File needs attention", systemImage: "exclamationmark.triangle")
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                    }.font(.callout).accessibilityIdentifier("external.failure.review").padding(.horizontal, 22)
                }
                if let projectIssue { Text(projectIssue).font(.caption).foregroundStyle(.orange).padding(.horizontal, 22) }
                if !imageRequest.references.isEmpty {
                    if destination == nil {
                        Button("Choose project folder to show images", systemImage: "folder") { actions.finishEditing(); projectPicker = true }.font(.caption).padding(.horizontal, 22).frame(minHeight: 44).accessibilityIdentifier("external.project.choose")
                    } else if imageLoading {
                        ProgressView("Loading images…").font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22)
                    } else if unavailableImages > 0 {
                        Button("Retry unavailable images (\(unavailableImages))", systemImage: "arrow.clockwise") { imageGeneration = UUID() }.font(.caption).frame(minHeight: 44).accessibilityIdentifier("external.images.retry")
                    }
                }
                if sourceOnly { Label("Source editing preserves this file’s advanced Markdown.", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 6) }
                NativeTextEditor(markdown: source ? session.document.content : session.document.parts.body, source: source || sourceOnly, images: images,
                    onChange: { if source { session.updateContent($0) } else { session.updateBody($0) } },
                    onImage: { data in
                        let attachment = NSTextAttachment(data: data, ofType: UTType.png.identifier)
                        actions.coordinator?.pasteRich(NSAttributedString(attachment: attachment))
                    }, onLink: handleLink,
                    onCode: { code = $0 }, onTable: { table = $0 },
                    copyFragment: { markdown in
                        if let destination { return try await destination.fragment(markdown) }
                        return NativeClipboardFragment(markdown: markdown)
                    }, pasteFragment: { fragment in
                        if fragment.resources.isEmpty, MarkdownResources.localReferences(in: fragment.markdown).isEmpty { return fragment.markdown }
                        guard let destination else { throw VaultFailure(message: "Choose this file’s project folder before adding attachments. Your existing text stays unchanged.") }
                        return try await destination.importFragment(fragment)
                    },
                    onClipboardError: { clipboardIssue = $0 }, onClipboardBusy: { clipboardBusy = $0 }, actions: actions,
                    documentID: "external:" + session.id.uuidString + ":" + session.presentationID.uuidString,
                    readOnly: session.transferring || !session.active,
                    wholeNoteMarkdown: { source ? $0 : session.document.replacingBody($0) }, codeBlocksEnabled: codeBlocks, noteLinkShortcuts: false)
            }
            .background(Accent.editor).foregroundStyle(Accent.text)
            .navigationTitle(session.document.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        actions.finishEditing(); closing = true
                        Task { await session.save(); await session.flushDraft(); closing = false; if session.canCloseSafely { dismiss() } }
                    }.disabled(closing).accessibilityIdentifier("external.editor.done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Find in note", systemImage: "doc.text.magnifyingglass") {
                            actions.finishEditing(); finding = actions.findSnapshot()
                        }.keyboardShortcut("f", modifiers: .command).accessibilityIdentifier("external.find")
                        Toggle("Full Markdown source", isOn: $source)
                        Menu("Clipboard", systemImage: "doc.on.clipboard") {
                            Button("Copy file", systemImage: "doc.on.doc") { actions.copyNote() }
                            Button("Copy Markdown", systemImage: "doc.plaintext") { actions.copyMarkdown() }
                            Button("Paste", systemImage: "doc.on.clipboard") { actions.paste() }
                            Button("Paste plain text", systemImage: "text.alignleft") { actions.pastePlainText() }
                        }
                        Button(destination == nil ? "Choose project folder…" : "Change project folder…", systemImage: "folder") { actions.finishEditing(); projectPicker = true }.accessibilityIdentifier("external.project.menu")
                        if let destination { Text(destination.root.lastPathComponent) }
                        Button("Attachments", systemImage: "paperclip") { actions.finishEditing(); attachments = true }.disabled(destination == nil).accessibilityIdentifier("external.attachments.menu")
                        Button("Refresh images", systemImage: "arrow.clockwise") { imageGeneration = UUID() }
                        Button("Copy into vault…", systemImage: "doc.on.doc") { actions.finishEditing(); transferMode = .copy }.disabled(vault.root == nil).accessibilityIdentifier("external.transfer.copy")
                        Button("Move into vault…", systemImage: "folder.badge.plus") { actions.finishEditing(); transferMode = .move }.disabled(vault.root == nil).accessibilityIdentifier("external.transfer.move")
                        Button("Save now", systemImage: "square.and.arrow.down") { actions.finishEditing(); Task { await session.retry() } }.accessibilityIdentifier("external.save")
                        Button("Reload file", systemImage: "arrow.clockwise") { actions.finishEditing(); reload = true }
                        ShareLink(item: session.document.content, preview: SharePreview(session.document.title)) { Label("Share Markdown", systemImage: "square.and.arrow.up") }
                    } label: { Image(systemName: "ellipsis") }.disabled(session.transferring || !session.active).accessibilityLabel("External note actions")
                }
            }
            .onAppear { session.registerEditor(editorID, actions: actions) }
            .onDisappear { actions.finishEditing(); session.unregisterEditor(editorID); Task { await session.save(); await session.flushDraft() } }
            .interactiveDismissDisabled(closing)
            .sheet(item: $transferMode, onDismiss: { if transferredOriginal { dismiss() } }) {
                NativeExternalTransferSheet(session: session, project: activeProject, mode: $0, workspaceID: vault.workspaceID) { transferredOriginal = true }
            }
            .sheet(isPresented: $reviewingIssue, onDismiss: {
                if reloadAfterIssue { reloadAfterIssue = false; reload = true }
            }) {
                NavigationStack {
                    List {
                        Section {
                            Text(session.failure ?? "The file is available again.")
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).accessibilityIdentifier("external.failure")
                        }
                        Section {
                            ShareLink(item: session.document.content, preview: SharePreview(session.document.title)) { Label("Share draft", systemImage: "square.and.arrow.up") }
                            if !session.conflict {
                                Button(session.dirty ? "Retry saving" : "Retry loading", systemImage: "arrow.clockwise") {
                                    Task { await session.retry(); if session.failure == nil { reviewingIssue = false } }
                                }.accessibilityIdentifier("external.retry")
                            }
                            Button("Reload file", systemImage: "arrow.counterclockwise") {
                                actions.finishEditing(); reloadAfterIssue = true; reviewingIssue = false
                            }.accessibilityIdentifier("external.reload")
                        }
                    }
                    .navigationTitle("File recovery").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { reviewingIssue = false } } }
                }
            }
            .sheet(item: $finding, onDismiss: {
                let reveal = revealFound; revealFound = nil
                guard session.active, !session.transferring else { return }
                if let reveal, !reveal() { findIssue = "The file changed. Open Find again to choose a current result." }
            }) { snapshot in NativeNoteFindView(snapshot: snapshot) { match in revealFound = { snapshot.reveal(match) } } }
            .alert("Find in note", isPresented: Binding(get: { findIssue != nil }, set: { if !$0 { findIssue = nil } })) {
                Button("OK") { findIssue = nil }
            } message: { Text(findIssue ?? "") }
            .sheet(item: $code) { CodeEditorSheet(request: $0) }
            .sheet(item: $table) { TableEditorSheet(request: $0, images: images, onLink: handleLink) }
            .sheet(item: $preview) { NativeFilePreview(lease: $0) }
            .sheet(isPresented: $attachments) {
                if let destination { NativeExternalAttachmentsView(project: destination, references: MarkdownResources.localReferences(in: session.document.parts.body)) }
            }
            .fullScreenCover(item: $linkedNote) { NativeNoteNavigationView(navigation: $0.navigation) }
            .sheet(isPresented: $projectPicker) {
                let expected = session.presentationID
                NativeExternalProjectPicker(snapshot: session.snapshot, currentFolder: activeProject?.root.lastPathComponent) { selected in
                    guard expected == session.presentationID else { return }
                    actions.coordinator?.cancelClipboard()
                    project = selected; projectPresentation = expected; projectIssue = nil
                }
            }
            .task(id: session.presentationID) {
                let expected = session.presentationID
                project = nil; projectPresentation = nil
                do {
                    let access = try await external.project(session.snapshot)
                    guard expected == session.presentationID, !Task.isCancelled else { return }
                    project = access; projectPresentation = expected; projectIssue = nil
                } catch { if expected == session.presentationID { projectIssue = error.localizedDescription } }
            }
            .task(id: imageRequest) { await loadImages(imageRequest) }
            .onChange(of: phase) { _, value in if value == .active { imageGeneration = UUID() } }
            .alert("Reload the current file?", isPresented: $reload) {
                Button("Cancel", role: .cancel) {}
                Button("Reload and discard this draft", role: .destructive) { Task { do { try await session.reloadDiscardingDraft() } catch { clipboardIssue = error.localizedDescription } } }
            } message: { Text("Your unsaved text will be replaced by the current file. Share the draft first if you want to keep it.") }
            .alert("External file", isPresented: Binding(get: { clipboardIssue != nil }, set: { if !$0 { clipboardIssue = nil } })) { Button("OK") { clipboardIssue = nil } } message: { Text(clipboardIssue ?? "") }
        }
    }
    private var statusLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())
    }
    private func loadImages(_ request: ImageRequest) async {
        guard !Task.isCancelled, request == imageRequest, session.active, !session.transferring else { return }
        let load = UUID(); imageLoad = load
        if imagePresentation != request.presentation || imageProject != request.project {
            loadedImages = [:]; loadedImageVersions = [:]; loadedImageGenerations = [:]
            imagePresentation = request.presentation; imageProject = request.project
        }
        loadedImages = loadedImages.filter { request.references.contains($0.key) }
        loadedImageVersions = loadedImageVersions.filter { request.references.contains($0.key) }
        loadedImageGenerations = loadedImageGenerations.filter { request.references.contains($0.key) }
        unavailableImages = 0; imageLoading = false
        guard let access = activeProject, request.project == access.id else { return }
        func current() -> Bool { !Task.isCancelled && imageLoad == load && request == imageRequest && session.active && !session.transferring }
        imageLoading = !request.references.isEmpty
        defer { if imageLoad == load { imageLoading = false } }
        for reference in request.references {
            do {
                let version = try await access.imageVersion(reference)
                guard current() else { return }
                if loadedImages[reference] != nil, loadedImageVersions[reference] == version,
                   loadedImageGenerations[reference] == request.generation { continue }
                // Keep the previous bitmap while its replacement downloads.
                // Only a successful, current read updates its cache version.
                let image = try await access.thumbnail(reference)
                guard current() else { return }
                loadedImages[reference] = UIImage(cgImage: image)
                loadedImageVersions[reference] = version
                loadedImageGenerations[reference] = request.generation
            } catch is CancellationError { return }
            catch { if current() { unavailableImages += 1 } }
        }
    }
    private func handleLink(_ url: URL) {
        if ["https", "http", "mailto", "tel"].contains(url.scheme ?? "") { openURL(url); return }
        if let reference = NoteReference(url: url) {
            let targets = vault.targets(for: reference)
            if targets.count == 1, let note = targets.first, let session = vault.session(for: note) { linkedNote = .init(navigation: .init(vault: vault, session: session)) }
            else { clipboardIssue = "This note link is unavailable or ambiguous in the current vault." }
            return
        }
        let reference = url.scheme == "zerus-image" ? String(url.absoluteString.dropFirst("zerus-image:".count)).removingPercentEncoding ?? "" : url.absoluteString
        guard let access = activeProject else { projectIssue = "Choose the project folder to preview local linked files and add attachments."; return }
        let expected = session.presentationID
        Task { do { let lease = try await access.preview(reference); guard expected == session.presentationID else { return }; preview = lease } catch { if expected == session.presentationID { projectIssue = error.localizedDescription } } }
    }

}


private struct NativeExternalRecoveryView: View {
    @EnvironmentObject private var external: NativeExternalNotesModel
    @Environment(\.dismiss) private var dismiss
    let entry: NativeExternalEntry
    @State private var draft: NativeExternalDraft?
    @State private var issue: String?
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            List {
                if let draft, draft.hasUnsavedChanges {
                    Section { Text("Your draft is kept on this device even when the original file is unavailable."); Text(draft.updated.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                    Section { ShareLink(item: draft.content, preview: SharePreview(draft.name)) { Label("Share recovery draft", systemImage: "square.and.arrow.up") } }
                    Section("Saved text") { Text(draft.content).font(.body.monospaced()).textSelection(.enabled) }
                } else if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
                else if loaded { ContentUnavailableView("No unsaved draft", systemImage: "checkmark.circle", description: Text("There is no unsaved recovery draft for this file.")) }
                else { ProgressView("Reading recovery draft…") }
            }.navigationTitle("Recovery draft").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task { defer { loaded = true }; do { draft = try await external.recoveryDraft(entry) } catch { issue = error.localizedDescription } }
        }
    }
}


private struct NativeExternalProjectPicker: View {
    @EnvironmentObject private var external: NativeExternalNotesModel
    @Environment(\.dismiss) private var dismiss
    let snapshot: NativeExternalSnapshot
    let currentFolder: String?
    let selected: (NativeExternalProjectFiles) -> Void
    @State private var picker = false
    @State private var busy = false
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(snapshot.entry.name, systemImage: "doc.text")
                    if let currentFolder { LabeledContent("Project folder", value: currentFolder) }
                }
                Section {
                    Text("Choose the folder containing this Markdown file and its attachments. Zerus can preview linked files and add pasted attachments inside that folder.")
                    Button(currentFolder == nil ? "Choose project folder in Files" : "Choose another project folder", systemImage: "folder") { picker = true }.accessibilityIdentifier("external.project.select")
                }
                if let issue { Section { Text(issue).foregroundStyle(.red).textSelection(.enabled) } }
            }
            .navigationTitle("Project attachments").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("external.project.done") } }
            .disabled(busy).interactiveDismissDisabled(busy)
            .overlay { if busy { ProgressView("Connecting project…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .fileImporter(isPresented: $picker, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    busy = true; issue = nil
                    Task { defer { busy = false }; do { let access = try await external.mapProject(snapshot, folder: url); selected(access); dismiss() } catch { issue = error.localizedDescription } }
                case .failure(let error): issue = error.localizedDescription
                }
            }
            .fileDialogDefaultDirectory(snapshot.access.url.deletingLastPathComponent())
        }
    }
}


private struct NativeExternalAttachmentsView: View {
    @Environment(\.dismiss) private var dismiss
    let project: NativeExternalProjectFiles
    let references: [String]
    @State private var preview: NativeFileLease?
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            List {
                if references.isEmpty { ContentUnavailableView("No local attachments", systemImage: "paperclip") }
                ForEach(Array(Set(references)).sorted(), id: \.self) { reference in
                    Button {
                        Task { do { preview = try await project.preview(reference) } catch { issue = error.localizedDescription } }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(URL(string: reference)?.lastPathComponent ?? reference, systemImage: "doc")
                            Text(reference).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }.padding(.vertical, 5)
                    }.accessibilityIdentifier("external.attachment." + reference)
                }
                if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
            }.navigationTitle("Attachments").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("external.attachments.done") } }
                .sheet(item: $preview) { NativeFilePreview(lease: $0) }
        }
    }
}
