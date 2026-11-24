import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacExternalNotesView: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject var library: MacExternalLibrary
    @State private var query = ""
    @State private var forgetting: NativeExternalEntry?
    @State private var recovery: MacExternalRecovery?
    @State private var pendingMove: NativeExternalMoveRecord?
    @State private var pendingEntry: NativeExternalEntry?
    init(workspace: MacWorkspace) { self.workspace = workspace; library = workspace.external }
    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("External notes").font(.title2.bold()); Spacer(); connectionActions }
                VStack(alignment: .leading, spacing: 12) { Text("External notes").font(.title2.bold()); connectionActions }
            }.padding(20)
            HStack { TextField("Search filenames or paths", text: $query).textFieldStyle(.roundedBorder); Button("Refresh") { Task { await library.restore() } } }.padding(.horizontal, 20).padding(.bottom, 14)
            Divider()
            if let issue = library.moveIssue { Text(issue).font(.caption).foregroundStyle(.red).padding(14) }
            if let issue = library.issue { HStack { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled); Spacer() }.padding(14) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !library.pendingMoves.isEmpty {
                        HStack { Text("Pending moves").font(.headline); Spacer() }.padding(18)
                        ForEach(library.pendingMoves) { record in
                            Button { pendingMove = record } label: {
                                HStack { Image(systemName: "arrow.right.doc.on.clipboard"); VStack(alignment: .leading) { Text(record.sourceName).font(.headline); Text(record.destinationPath).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("Review…") }.padding(18).contentShape(Rectangle())
                            }.buttonStyle(MacBoxButtonStyle())
                        }
                        Divider()
                    }
                    ForEach(library.entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.location.localizedCaseInsensitiveContains(query) }) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Button { Task { await library.open(entry) } } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 5) { Text(entry.name).font(.headline); Text(URL(string: entry.location)?.path ?? entry.location).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                    Spacer()
                                }.contentShape(Rectangle())
                            }.buttonStyle(MacBoxButtonStyle())
                            Menu {
                                Button("Recovery draft…") { Task { do { recovery = .init(entry: entry, draft: try await library.store.draft(entry.id)) } catch { library.issue = error.localizedDescription } } }
                                Button("Locate original…") { chooseFile(replacing: entry) }
                                Button("Reveal") { if let url = URL(string: entry.location) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                                Button("Stop tracking…") { forgetting = entry }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for " + entry.name)
                        }.padding(18)
                        Divider()
                    }
                    if library.entries.isEmpty { ContentUnavailableView("Your files, in place", systemImage: "doc.text", description: Text("Connect a Markdown file to edit its original. Connections and recovery drafts stay on this Mac; your file stays where it is.")).padding(30) }
                }
            }
            HStack { Text("Original files stay outside the vault. Stop tracking keeps the file.").font(.caption).foregroundStyle(.secondary); Spacer(); if library.busy { ProgressView().controlSize(.small) } }.padding(14)
        }.disabled(library.busy)
        .task { await library.restore() }
        .macSheet(item: $recovery) { MacExternalRecoveryView(recovery: $0) }
        .macSheet(item: $pendingMove, onDismiss: {
            if let entry = pendingEntry { pendingEntry = nil; Task { await library.open(entry) } }
        }) { record in MacExternalMoveRecoveryView(workspace: workspace, library: library, record: record) { pendingEntry = $0 } }
        .macSheet(item: $library.selected, onDismiss: { Task { await library.restore() } }) { session in MacExternalEditor(workspace: workspace, library: library, session: session) }
        .alert("Stop tracking this file?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
            Button("Cancel", role: .cancel) { forgetting = nil }
            Button("Stop tracking") { if let forgetting { Task { await library.forget(forgetting) } }; forgetting = nil }
        } message: { Text("The original stays in place. A file with an unsaved recovery draft cannot be removed from this list until that draft is saved or reviewed.") }
    }
    private var connectionActions: some View {
        HStack {
            Button("New Markdown file…") { createFile() }
            Button("Connect Markdown…") { chooseFile() }.buttonStyle(.borderedProminent)
        }
    }
    private func chooseFile(replacing entry: NativeExternalEntry? = nil) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]
        panel.prompt = entry == nil ? "Connect" : "Locate"; panel.message = "Choose the original Markdown file. Zerus edits it in place."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openSelected(url, replacing: entry)
    }
    private func openSelected(_ url: URL, replacing entry: NativeExternalEntry? = nil) {
        Task {
            if entry == nil {
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                if let root = workspace.root, canonical.path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path + "/") { await workspace.refresh() }
                if let root = workspace.root, let note = workspace.notes.first(where: { root.appendingPathComponent($0.path).resolvingSymlinksInPath().standardizedFileURL == canonical }) { await workspace.openNote(note.path); return }
            }
            await library.open(url, replacing: entry)
        }
    }

    private func createFile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]; panel.nameFieldStringValue = "Untitled.md"; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard !FileManager.default.fileExists(atPath: url.path) else { throw VaultFailure(message: "Choose a new filename. Existing files can be connected without replacing them.") }
            let title = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "\n", with: " ")
            try Data(("# " + title + "\n\n").utf8).write(to: url, options: .withoutOverwriting)
            openSelected(url)
        } catch { library.issue = error.localizedDescription }
    }
}

struct MacExternalEditor: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject var library: MacExternalLibrary
    @ObservedObject var session: MacExternalSession
    @AppStorage("zerus.mac.codeBlocks") private var codeBlocks = false
    @State private var tableRequest: MacTableRequest?
    @State private var codeRequest: MacCodeRequest?
    @State private var transferRequest: MacExternalTransferRequest?
    @State private var copiedPath: (path: String, workspace: UUID)?
    @State private var clipboardBusy = false
    @State private var source = false
    @State private var discardReview = false
    @State private var error: String?
    @StateObject private var imagePreview = MacExternalImages()
    private var pendingMove: NativeExternalMoveRecord? { library.pendingMoves.first { $0.sourceID == session.id } }
    private var usesSource: Bool { source || MacMarkdown.requiresSource(session.document.parts.body) }
    private var editorMarkdown: String { usesSource ? session.document.content : session.document.parts.body }
    private var current: Bool { library.selected === session && session.active && !session.transferring && !session.agentLocked }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text(session.snapshot.entry.name).font(.headline); Text(session.snapshot.access.canonical.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                Spacer()
                Button(session.exporting ? "Exporting…" : "Export draft…") { exportDraft() }.disabled(session.exporting || clipboardBusy || !session.active)
                Menu("Import into vault") {
                    Button("Copy into vault…") { transferRequest = .init(mode: .copy) }
                    if let pendingMove { Button("Finish pending move…") { transferRequest = .init(mode: .move, pending: pendingMove) } }
                    else { Button("Move into vault…") { transferRequest = .init(mode: .move) } }
                }.disabled(workspace.root == nil || clipboardBusy || session.exporting || !session.active)
                Button("Reload original…") { discardReview = true }.disabled(!session.active)
                Button("Save") { Task { await session.save() } }.disabled(!session.dirty || session.conflict)
                Button("Done") { Task { _ = await library.close() } }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            if let message = error ?? session.failure ?? session.projectFailure ?? imagePreview.issue {
                HStack { Image(systemName: "exclamationmark.triangle"); Text(message).font(.caption).textSelection(.enabled); Spacer(); Button("Retry") { Task { error = nil; await session.retry(); await session.restoreProject(); await imagePreview.load(project: session.project, markdown: session.document.parts.body) } } }.foregroundStyle(.red).padding(12)
            }
            HStack(spacing: 14) {
                ForEach([("bold", "bold"), ("italic", "italic"), ("underline", "underline"), ("code", "chevron.left.forwardslash.chevron.right"), ("bullet", "list.bullet"), ("checklist", "checklist")], id: \.0) { action, icon in Button { sendEditor(action) } label: { Image(systemName: icon) }.help(action.capitalized) }
                Menu("Paragraph") {
                    Button("Indent list item (Tab)") { sendEditor("indent") }
                    Button("Outdent list item (⇧Tab)") { sendEditor("outdent") }
                    Divider()
                    Button("Continue after code or table (⌘Return)") { sendEditor("exitCode") }
                    Button("Turn code block into text") { sendEditor("codeToText") }
                    Button("Horizontal rule") { sendEditor("rule") }
                    Divider()
                    ForEach([("Paragraph", "paragraph"), ("Heading 1", "h1"), ("Heading 2", "h2"), ("Heading 3", "h3"), ("Heading 4", "h4"), ("Heading 5", "h5"), ("Heading 6", "h6"), ("Quote", "quote"), ("Numbered list", "ordered")], id: \.0) { title, action in Button(title) { sendEditor(action) } } }.menuStyle(.borderlessButton).fixedSize()
                Menu { Button("Insert or edit link…") { sendEditor("link") }; Button("Note link suggestions") { sendEditor("noteLink") } } label: { Image(systemName: "link") }.help("Insert or edit link").accessibilityLabel("Link").menuStyle(.borderlessButton).fixedSize()
                Button { sendEditor("insertImage") } label: { Image(systemName: "photo") }.help("Insert image").accessibilityLabel("Insert image")
                MacBlockMenu(codeBlocks: codeBlocks, snapshot: {
                    guard current, !clipboardBusy else { return nil }
                    return .init(scope: session.presentationID, path: session.snapshot.entry.name, source: editorMarkdown)
                }, prepare: { snapshot in
                    guard current, !clipboardBusy, snapshot.scope == session.presentationID,
                          snapshot.path == session.snapshot.entry.name,
                          snapshot.source.utf8.elementsEqual(editorMarkdown.utf8) else {
                        error = "The note changed. Open the menu again to choose a current block."
                        return false
                    }
                    return true
                }, openTable: { tableRequest = $0 }, openCode: { codeRequest = $0 })
                .fixedSize()
                Button(session.project == nil ? "Choose project folder…" : "Change project folder…") { Task { await chooseProject() } }.disabled(clipboardBusy)
                    .help("Read local images and add pasted image files inside the chosen project folder")
                if let project = session.project { Text(project.root.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if imagePreview.loading { ProgressView().controlSize(.small) }
                Spacer()
                Button(usesSource ? "Show rich text" : "Edit full source") { if MacMarkdown.requiresSource(session.document.parts.body) { error = "This file uses structures currently edited as Markdown source." } else { source.toggle() } }
            }.buttonStyle(MacBoxButtonStyle()).padding(12)
            Divider()
            MacRichEditor(markdown: editorMarkdown, source: usesSource, editable: session.active && !session.transferring && !session.agentLocked, path: session.snapshot.entry.name, project: session.project, images: imagePreview.images, onChange: { value in if usesSource { session.changeContent(value) } else { session.changeBody(value) } }, onLink: { value in Task { await workspace.follow(value) } }, onSourceChange: { source = $0 }, onPasteError: { error = $0 }, onPasteBusy: { clipboardBusy = $0 }, sourceHeader: session.document.parts.header, onModeChange: { value, full in if full { session.changeContent(value) } else { session.changeBody(value) } }, linkNotes: { [notes = workspace.notes] in notes }, commandScope: session.presentationID,
                          isCurrent: { current }, readDocument: { (editorMarkdown, usesSource) }, chooseImageProject: { await chooseProject() }).overlay(alignment: .topTrailing) { if clipboardBusy { HStack { ProgressView().controlSize(.small); Text("Preparing clipboard… Esc to cancel").font(.caption) }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding() } }.id(session.presentationID)
            Divider()
            HStack {
                Text(session.moved ? "Moved into vault" : !session.active ? "Connection closed" : session.saving ? "Saving original…" : !session.dirty ? "Saved to original" : session.exportReady ? "Exported draft verified" : session.draftKept ? "Draft kept on this Mac" : "Keeping recovery draft…")
                Spacer(); Text(usesSource ? "Full Markdown source" : "Rich text · frontmatter preserved")
            }.font(.caption).foregroundStyle(.secondary).padding(12)
        }.frame(minWidth: 900, minHeight: 680).disabled(session.transferring || session.agentLocked)
        .onAppear { if MacMarkdown.requiresSource(session.document.parts.body) { source = true } }
        .interactiveDismissDisabled(session.dirty || session.agentLocked || workspace.externalCopySaving)
        .macSheet(item: $transferRequest, onDismiss: {
            if let copy = copiedPath {
                copiedPath = nil
                Task {
                    guard copy.workspace == workspace.workspaceID, await library.close(), copy.workspace == workspace.workspaceID else { return }
                    await workspace.openNote(copy.path)
                }
            }
        }) { request in MacExternalTransferView(workspace: workspace, session: session, mode: request.mode, pending: request.pending) { copiedPath = ($0, workspace.workspaceID) } }
        .macSheet(item: $tableRequest, onDismiss: { DispatchQueue.main.async { sendEditor("focus") } }) { request in
            MacTableEditor(request: request) { replacement in
                guard current, request.workspaceID == session.presentationID else { throw VaultFailure(message: "This connection closed. Copy your table before closing the sheet.") }
                let command = MacTableChange(request: request, replacement: replacement)
                NotificationCenter.default.post(name: .macEditorAction, object: command)
                guard let result = command.result else { throw VaultFailure(message: "The editor is unavailable. Copy your table before closing the sheet.") }
                try result.get()
            }
        }
        .macSheet(item: $codeRequest, onDismiss: { DispatchQueue.main.async { sendEditor("focus") } }) { request in
            MacCodeEditor(request: request) { replacement in
                guard current, request.workspaceID == session.presentationID else { throw VaultFailure(message: "This connection closed. Copy your code before closing the sheet.") }
                let command = MacCodeChange(request: request, replacement: replacement)
                NotificationCenter.default.post(name: .macEditorAction, object: command)
                guard let result = command.result else { throw VaultFailure(message: "The editor is unavailable. Copy your code before closing the sheet.") }
                try result.get()
            }
        }
        .task(id: session.presentationID) {
            await session.restoreProject()
            while !Task.isCancelled {
                await imagePreview.load(project: session.project, markdown: session.document.parts.body)
                do { try await Task.sleep(for: .seconds(8)); await session.refresh() } catch { return }
            }
        }
        .task(id: (session.project?.id.uuidString ?? "") + MacExternalImages.references(in: session.document.parts.body).joined(separator: "|")) {
            await imagePreview.load(project: session.project, markdown: session.document.parts.body)
        }
        .onDisappear { Task { _ = await session.checkpoint(); session.deactivate() } }
        .alert("Discard this draft and reload?", isPresented: $discardReview) {
            Button("Cancel", role: .cancel) {}
            Button("Reload original", role: .destructive) { Task { do { try await session.reloadDiscardingDraft(); error = nil } catch { self.error = error.localizedDescription } } }
        } message: { Text("The current file is read first. Export the draft if you want to keep its unsaved changes.") }
    }
    private func sendEditor(_ action: String) {
        guard current else { return }
        NotificationCenter.default.post(name: .macEditorAction, object: MacEditorCommand(scope: session.presentationID, path: session.snapshot.entry.name, action: action))
    }
    private func chooseProject() async {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Use project folder"; panel.directoryURL = session.project?.root ?? session.snapshot.access.canonical.deletingLastPathComponent()
        panel.message = "Choose the folder containing this Markdown file and its images. Zerus can read images and add pasted images inside that folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        error = nil; await session.chooseProject(url)
    }
    private func exportDraft() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]; panel.nameFieldStringValue = (session.snapshot.entry.name as NSString).deletingPathExtension + " draft.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { error = nil; do { try await session.exportDraft(to: url) } catch { self.error = error.localizedDescription } }
    }
}


private struct MacExternalRecovery: Identifiable {
    let id = UUID()
    let entry: NativeExternalEntry
    let draft: NativeExternalDraft?
}
private struct MacExternalRecoveryView: View {
    let recovery: MacExternalRecovery
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Recovery draft — " + recovery.entry.name).font(.headline); Spacer(); Button("Done") { dismiss() } }
            if let draft = recovery.draft {
                Text(draft.hasUnsavedChanges ? "Unsaved text kept on this Mac. Export it even when the original is unavailable." : "Last saved checkpoint. No unsaved changes were recorded.").font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(draft.content).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.background(.quaternary.opacity(0.3))
                if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
                HStack { Text(draft.updated, style: .date).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Export draft…") { export(draft) } }
            } else { ContentUnavailableView("No recovery draft", systemImage: "doc", description: Text("The original file is unchanged.")) }
        }.padding(22).frame(width: 700, height: 500)
    }
    private func export(_ draft: NativeExternalDraft) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]; panel.nameFieldStringValue = (recovery.entry.name as NSString).deletingPathExtension + " draft.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard url.resolvingSymlinksInPath().standardizedFileURL != URL(string: recovery.entry.location)?.resolvingSymlinksInPath().standardizedFileURL else { throw VaultFailure(message: "Choose a different file to keep the original protected.") }
            let bom = draft.baseline.starts(with: [0xef, 0xbb, 0xbf]) ? Data([0xef, 0xbb, 0xbf]) : Data()
            try (bom + Data(draft.content.utf8)).write(to: url, options: .atomic)
            issue = nil
        } catch { issue = error.localizedDescription }
    }
}
