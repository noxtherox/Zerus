import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacChatView: View {
    @Bindable var store: MacWorkspace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if let root = store.root { MacConversationChatView(workspace: store, chat: .shared(root: root)).id(store.workspaceID) }
        else { VStack(spacing: 16) { Text("Open a vault to use AI conversations."); Button("Done") { dismiss() } }.padding(30) }
    }
}
struct MacConversationChatView: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject var chat: MacChatController
    var launchNotice: String? = nil
    @AppStorage("zerus.mac.ai.endpoint") private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("zerus.mac.ai.model") private var model = ""
    @AppStorage("zerus.mac.ai.context-window") private var contextWindow = 32_768
    @AppStorage("zerus.mac.ai.use-chatgpt") private var usingChatGPT = false
    @AppStorage("zerus.mac.ai.format") private var apiFormat = MacAIFormat.compatible.rawValue
    @State private var configuration = false
    @State private var agentControls = false
    private var selectedPaths: Set<String> { chat.contextPaths ?? [] }
    @State private var contextPicker = false
    @State private var show = "Active"
    @State private var rename = false
    @State private var name = ""
    @State private var claim = false
    @State private var busy = false
    @State private var documentPreview: MacChatDocument?
    @State private var requestID = UUID()
    @State private var attachmentTask: Task<Void, Never>?
    @State private var fileDrag = false
    @Environment(\.dismiss) private var dismiss
    private var visible: [MacConversationListEntry] { chat.conversations.filter { show == "Trash" ? $0.deletedAt != nil : show == "Archived" ? $0.deletedAt == nil && $0.archivedAt != nil : $0.deletedAt == nil && $0.archivedAt == nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI conversations", systemImage: "sparkles").font(.title2.bold())
                Button("Agent runs…") { agentControls = true }.disabled(busy || chat.isBusy)
                Spacer(); if chat.isBusy { ProgressView().controlSize(.small) }; Button("Connection") { configuration = true }; Button("Done") { Task { if await chat.prepareToLeave() { dismiss() } } }
            }
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Conversations", selection: $show) { ForEach(["Active", "Archived", "Trash"], id: \.self) { Text($0).tag($0) } }.labelsHidden()
                    if show == "Trash" { Text("Chats owned by this Mac are permanently removed after 30 days when history refreshes. Unsent drafts and active work delay cleanup.").font(.caption).foregroundStyle(.secondary) }
                    Button("New conversation") { select(nil) }.disabled(chat.isBusy || chat.hasUnsavedReply || busy)
                    ScrollView { LazyVStack(alignment: .leading, spacing: 5) { ForEach(visible) { item in Button { select(item.id) } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.headline).lineLimit(2); Text(item.owner.id == chat.device.id ? "This Mac" : item.owner.name).font(.caption).foregroundStyle(.secondary) }
                            .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(chat.selectedID == item.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(MacBoxButtonStyle()).disabled(chat.isBusy || chat.hasUnsavedReply || busy) } } }
                    Button("Refresh") { Task { await chat.reload() } }.disabled(chat.isBusy || busy)
                }.frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(chat.conversation?.title ?? "New conversation").font(.headline).lineLimit(2); Spacer()
                        if let item = chat.conversation {
                            Menu("Conversation") {
                                Button("Rename…") { name = item.title; rename = true }
                                if item.archivedAt == nil && item.deletedAt == nil { Button("Archive") { change(.archive) }; Button("Move to Trash") { change(.delete) } }
                                else { Button("Restore conversation") { change(.restore) } }
                            }.disabled(chat.isBusy || item.owner.id != chat.device.id || chat.hasUnsavedReply)
                        }
                    }
                    if let item = chat.conversation, item.owner.id != chat.device.id {
                        HStack { Text("Read-only · owned by " + item.owner.name).font(.caption).foregroundStyle(.secondary); Button("Move to this Mac…") { claim = true } }.disabled(chat.isBusy)
                    } else if chat.conversation?.archivedAt != nil || chat.conversation?.deletedAt != nil { Text("Restore this conversation to continue.").font(.caption).foregroundStyle(.secondary) }
                    ScrollViewReader { proxy in
                        ScrollView { LazyVStack(alignment: .leading, spacing: 20) {
                            if chat.messages.isEmpty { ContentUnavailableView("Think it through.", systemImage: "sparkles", description: Text("Ask a question and choose the notes to share as context.")) }
                            ForEach(chat.messages) { message in VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(message.role == "user" ? "YOU" : "ZERUS").font(.caption.bold()).foregroundStyle(.secondary); if message.interrupted { Text("Interrupted").font(.caption).foregroundStyle(.secondary) } }
                                if message.text.isEmpty { if chat.running && message.id == chat.live?.id { ProgressView("Waiting for reply…") } else { Text("Stopped before text was received.").font(.caption).foregroundStyle(.secondary) } }
                                else { MacChatMessageText(text: message.text) }
                                if message.role == "user", let id = chat.selectedID { MacChatMessageImages(root: chat.root, conversationID: id, message: message, version: chat.attachmentEpoch) }
                                if message.role == "assistant", !message.text.isEmpty { HStack { Button("Copy reply") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) }; Button("Save as note") { saveNote(message.text) } }.font(.caption).disabled(chat.isBusy || busy) }
                            }.frame(maxWidth: .infinity, alignment: .leading).id(message.id) }
                            Color.clear.frame(height: 1).id("reply-bottom")
                        }.padding(12) }
                        .onChange(of: chat.live?.text) { if chat.running { proxy.scrollTo("reply-bottom", anchor: .bottom) } }
                    }
                    if !chat.recoveryArchive.isEmpty || chat.hasUnsavedReply {
                        DisclosureGroup("Local reply recovery (\(chat.recoveryArchive.count))") {
                            ScrollView { VStack(alignment: .leading, spacing: 10) { ForEach(chat.recoveryArchive) { recovery in VStack(alignment: .leading) { Text(recovery.text).font(.caption).textSelection(.enabled).lineLimit(5); Button("Export recovery…") { export(recovery.text) } } } } }.frame(maxHeight: 150)
                            if chat.hasUnsavedReply { Button("Keep recovery and continue") { do { try chat.keepRecoveryAndContinue() } catch { chat.issue = error.localizedDescription } } }
                        }.font(.caption)
                    }
                    if !chat.selectedImages.isEmpty {
                        ScrollView(.horizontal) { HStack(alignment: .top) { ForEach(chat.selectedImages) { image in VStack(spacing: 4) {
                            MacChatPendingThumbnail(id: image.id, bytes: image.bytes)
                            Text(image.name).font(.caption2).lineLimit(1).frame(width: 100)
                            Button { do { try chat.removeImage(image.id) } catch { chat.issue = error.localizedDescription } } label: { Label("Remove", systemImage: "xmark") }.font(.caption2).accessibilityLabel("Remove " + image.name).disabled(chat.isBusy || busy)
                        } } } }
                    }
                    if !chat.selectedDocuments.isEmpty {
                        ScrollView(.horizontal) { HStack { ForEach(chat.selectedDocuments) { document in HStack(spacing: 6) {
                            Button { documentPreview = document } label: { Label(document.name, systemImage: "doc.text").lineLimit(1) }.buttonStyle(.bordered)
                            Button { do { try chat.removeDocument(document.id) } catch { chat.issue = error.localizedDescription } } label: { Image(systemName: "xmark") }.accessibilityLabel("Remove " + document.name).disabled(chat.isBusy || busy)
                        } } } }.frame(maxHeight: 36)
                    }
                    if let launchNotice { Text(launchNotice).font(.caption).foregroundStyle(.secondary) }
                    if let status = chat.documentContextStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                    HStack { Button("Context: \(selectedPaths.count) notes…") { contextPicker = true }.disabled(chat.isBusy || busy); Button("Add images…") { importImages() }.disabled(chat.isBusy || busy || !chat.writable || chat.selectedImages.count >= 4); Button("Add documents…") { importDocuments() }.disabled(chat.isBusy || busy || !chat.writable); Spacer(); if chat.messages.last?.role == "user" || chat.messages.last?.interrupted == true { Button("Retry reply") { retry() }.disabled(chat.isBusy || busy || !chat.writable || chat.hasUnsavedReply) } }.font(.caption)
                    HStack(alignment: .bottom) {
                        MacChatComposer(text: $chat.draft, enabled: !busy, acceptsAttachments: !chat.isBusy && chat.writable && !chat.hasUnsavedReply, attach: importAttachments, issue: { chat.issue = $0 }).id(chat.selectedID ?? "new").frame(height: 72)
                        if chat.isBusy { Button("Stop") { chat.stop() } }
                        else { Button("Send") { send() }.keyboardShortcut(.return, modifiers: .command).disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.selectedImages.isEmpty && chat.selectedDocuments.isEmpty || !chat.writable || chat.hasUnsavedReply || busy) }
                    }
                    Text("Paste images or drop image, PDF and text files into chat. Send shares this conversation, image attachments, document text or excerpts, and selected note snapshots with the configured provider. Images need a vision-capable model. Credentials stay in Keychain; saved conversations travel with the vault.").font(.caption2).foregroundStyle(.secondary)
                }.frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
            }.frame(maxHeight: .infinity)
            if let issue = chat.issue { HStack { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled); Spacer(); Button("Export prompt…") { export(chat.draft) } } }
            if !chat.warnings.isEmpty { DisclosureGroup("Preserved conversation data (\(chat.warnings.count))") { ForEach(chat.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) } } }
        }.padding(20).frame(width: 1040, height: 740).interactiveDismissDisabled(chat.isBusy || chat.hasUnsavedReply)
        .macSheet(isPresented: $agentControls) { MacAgentRunHost(workspace: workspace, chat: chat) }
        .task(id: chat.selectedID) { await chat.reload(); await refreshContext() }
        .onDisappear { requestID = UUID(); attachmentTask?.cancel(); chat.stop() }
        .overlay { if fileDrag { RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 3).allowsHitTesting(false) } }
        .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier], isTargeted: $fileDrag) { providers in
            guard !busy, !chat.isBusy, chat.writable, !chat.hasUnsavedReply else { return false }
            importAttachments { try await MacChatAttachmentInput.read(providers) }; return true
        }
        .macSheet(isPresented: $configuration) { MacChatConnection(workspace: workspace, endpoint: endpoint, model: model, contextWindow: contextWindow, usingChatGPT: usingChatGPT, format: MacAIFormat(rawValue: apiFormat) ?? .compatible) { _, _, _, accountMode, _ in usingChatGPT = accountMode } }
        .macSheet(item: $documentPreview) { document in MacChatDocumentPreview(document: document) }
        .macSheet(isPresented: $contextPicker) { MacChatContextPicker(workspace: workspace, chat: chat) }
        .alert("Rename conversation", isPresented: $rename) { TextField("Name", text: $name); Button("Cancel", role: .cancel) {}; Button("Save") { change(.rename(name)) } }
        .confirmationDialog("Move this conversation to this Mac?", isPresented: $claim, titleVisibility: .visible) { Button("Move to this Mac") { change(.claim) }; Button("Cancel", role: .cancel) {} } message: { Text("The event history stays intact. Other devices will see this Mac as the current owner when they sync.") }
    }
    private func initializeContext(_ snapshot: MacChatContextSnapshot) throws {
        guard chat.contextReferences == nil else { return }
        let current = snapshot.drafts.first(where: { $0.baseline.path == workspace.selection })?.baseline ?? workspace.current
        try chat.setContextReferences(try current.map { try MacChatNoteReference.capture([$0.path], notes: [$0]) } ?? [])
    }
    private func refreshContext() async {
        guard !chat.isBusy else { return }
        let origin = workspace.workspaceID, before = chat.inputStamp
        busy = true; defer { busy = false }
        do {
            let snapshot = try await workspace.chatContextSnapshot()
            guard !Task.isCancelled, origin == workspace.workspaceID, before == chat.inputStamp else { return }
            try initializeContext(snapshot); _ = try chat.resolveNoteContext(snapshot)
        } catch is CancellationError {} catch { chat.issue = error.localizedDescription }
    }
    private func select(_ id: String?) { busy = true; Task { defer { busy = false }; do { try await chat.select(id) } catch { chat.issue = error.localizedDescription } } }
    private func change(_ action: MacConversationChange) { Task { do { try await chat.change(action) } catch { chat.issue = error.localizedDescription } } }
    private func send() {
        busy = true; let origin = workspace.workspaceID, request = UUID(), before = chat.inputStamp; requestID = request
        let accountMode = usingChatGPT
        var address = endpoint, chosenModel = model, capacity = contextWindow, format = MacAIFormat(rawValue: apiFormat) ?? .compatible
        Task { defer { busy = false }; do {
            let snapshot = try await workspace.chatContextSnapshot()
            guard requestID == request, origin == workspace.workspaceID, before == chat.inputStamp else { return }
            try initializeContext(snapshot)
            let sources = try chat.resolveNoteContext(snapshot), prepared = chat.inputStamp
            let key: String
            if accountMode { key = "" } else {
                let selected = try await workspace.aiProfile(legacy: .legacy(endpoint: address, model: chosenModel, contextWindow: capacity, format: format))
                address = selected.endpoint; chosenModel = selected.model; capacity = selected.contextWindow; format = selected.provider.format
                key = try await MacCredentials.read(address)
            }
            guard requestID == request, origin == workspace.workspaceID, prepared == chat.inputStamp else { return }
            try await chat.send(endpoint: address, model: chosenModel, apiKey: key, sources: sources, contextWindow: capacity, format: format, chatGPT: accountMode ? .shared : nil)
        } catch is CancellationError {} catch { if requestID == request { chat.issue = error.localizedDescription } } }
    }
    private func retry() {
        busy = true; let request = UUID(), origin = workspace.workspaceID, selected = chat.selectedID, message = chat.messages.last?.id; requestID = request
        let accountMode = usingChatGPT
        var address = endpoint, chosenModel = model, capacity = contextWindow, format = MacAIFormat(rawValue: apiFormat) ?? .compatible
        Task { defer { busy = false }; do {
            let key: String
            if accountMode { key = "" } else {
                let selected = try await workspace.aiProfile(legacy: .legacy(endpoint: address, model: chosenModel, contextWindow: capacity, format: format))
                address = selected.endpoint; chosenModel = selected.model; capacity = selected.contextWindow; format = selected.provider.format
                key = try await MacCredentials.read(address)
            }
            guard requestID == request, origin == workspace.workspaceID, selected == chat.selectedID, message == chat.messages.last?.id else { return }
            try await chat.retry(endpoint: address, model: chosenModel, apiKey: key, contextWindow: capacity, format: format, chatGPT: accountMode ? .shared : nil)
        } catch is CancellationError {} catch { if requestID == request { chat.issue = error.localizedDescription } } }
    }
    private func importDocuments() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.item]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false; panel.prompt = "Choose PDF or text files"
        guard panel.runModal() == .OK else { return }; importAttachments(panel.urls.map(MacChatAttachmentInput.file))
    }
    private func importImages() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }; importAttachments(panel.urls.map(MacChatAttachmentInput.file))
    }
    private func importAttachments(_ inputs: [MacChatAttachmentInput]) { importAttachments { inputs } }
    private func importAttachments(_ read: @escaping @MainActor () async throws -> [MacChatAttachmentInput]) {
        guard !busy, !chat.isBusy, chat.writable, !chat.hasUnsavedReply else { chat.issue = "Finish the current operation in a writable conversation before adding attachments."; return }
        let origin = workspace.workspaceID, selected = chat.selectedID, epoch = chat.attachmentEpoch
        let imageCount = chat.selectedImages.count, documentCount = chat.selectedDocuments.count, documentBytes = chat.selectedDocuments.reduce(0) { $0 + $1.text.utf8.count }
        busy = true; chat.issue = nil
        attachmentTask = Task { defer { busy = false; attachmentTask = nil }; do {
            let inputs = try await read()
            let prepared = try await MacChatAttachmentInput.prepare(inputs, imageCount: imageCount, documentCount: documentCount, documentBytes: documentBytes)
            try Task.checkCancellation()
            guard origin == workspace.workspaceID, workspace.root?.standardizedFileURL == chat.root.standardizedFileURL, selected == chat.selectedID, epoch == chat.attachmentEpoch else { throw VaultFailure(message: "The vault or conversation changed. Add the attachments again in the current chat.") }
            try chat.addAttachments(images: prepared.images, documents: prepared.documents)
        } catch is CancellationError {} catch { chat.issue = error.localizedDescription } }
    }
    private func saveNote(_ text: String) {
        guard !workspace.busy else { chat.issue = "Finish opening the vault before saving this reply. Your reply is kept in the conversation."; return }
        let origin = workspace.workspaceID
        busy = true
        Task { defer { busy = false }; if let path = await workspace.createNote(title: "From Zerus · " + Date().formatted(date: .abbreviated, time: .omitted)) {
            guard workspace.workspaceID == origin, workspace.selection == path, !workspace.busy else { chat.issue = "The selected note changed. Your reply is kept in the conversation; save it again when ready."; return }
            workspace.changed(workspace.body + "\n\n" + text); _ = await workspace.save() } }
    }
    private func export(_ text: String) { let panel = NSSavePanel(); panel.nameFieldStringValue = "Zerus chat recovery.md"; guard panel.runModal() == .OK, let url = panel.url else { return }; do { try Data(text.utf8).write(to: url, options: .atomic) } catch { chat.issue = error.localizedDescription } }
}

/// Parsed once per text value. Unchanged messages are skipped by SwiftUI's
/// view diffing, so streaming a reply re-parses only the live message.
private struct MacChatMessageText: View, Equatable {
    let text: String
    var body: some View {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .textSelection(.enabled).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
    }
}
/// Decodes a selected image's thumbnail once instead of on every render.
private struct MacChatPendingThumbnail: View {
    let id: String
    let bytes: Data
    @State private var bitmap: (id: String, image: NSImage?)?
    var body: some View {
        Group {
            if let image = bitmap?.image, bitmap?.id == id { Image(nsImage: image).resizable().scaledToFit().frame(width: 90, height: 65) }
            else { Color.clear.frame(width: 90, height: 65) }
        }.task(id: id) { if bitmap?.id != id { bitmap = (id, NSImage(data: bytes)) } }
    }
}
