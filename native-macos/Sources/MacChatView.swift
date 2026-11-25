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
    @Environment(\.macTheme) private var theme
    @State private var query = ""
    @State private var modelLabel = ""
    @State private var privacyInfo = false
    private var locked: Bool { chat.isBusy || chat.hasUnsavedReply || busy }
    private var filtered: [MacConversationListEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? visible : visible.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }
    private var contextReferences: [MacChatNoteReference] { chat.contextReferences ?? [] }
    private func noteTitle(_ path: String) -> String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    private var canSend: Bool {
        !(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.selectedImages.isEmpty && chat.selectedDocuments.isEmpty) && chat.writable && !chat.hasUnsavedReply && !busy
    }
    var body: some View {
        let palette = MacChatPalette(theme)
        VStack(spacing: 0) {
            header(palette)
            Rectangle().fill(palette.line).frame(height: 1)
            HSplitView {
                sidebar(palette).frame(minWidth: 200, idealWidth: 232, maxWidth: 290, maxHeight: .infinity)
                conversationPane(palette).frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            }.frame(maxHeight: .infinity)
            if chat.issue != nil || !chat.warnings.isEmpty {
                Rectangle().fill(palette.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    if let issue = chat.issue { HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red); Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled); Spacer(); Button("Export prompt…") { export(chat.draft) }.controlSize(.small) } }
                    if !chat.warnings.isEmpty { DisclosureGroup("Preserved conversation data (\(chat.warnings.count))") { ForEach(chat.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) } }.font(.caption) }
                }.padding(.horizontal, 16).padding(.vertical, 8).background(palette.sidebar)
            }
        }
        .background(palette.editor).foregroundStyle(palette.text)
        .frame(width: 1040, height: 740).interactiveDismissDisabled(chat.isBusy || chat.hasUnsavedReply)
        .environment(\.openURL, OpenURLAction { url in
            guard let target = MacChatLinks.target(url) else { return .systemAction }
            openLinkedNote(target); return .handled
        })
        .macSheet(isPresented: $agentControls) { MacAgentRunHost(workspace: workspace, chat: chat) }
        .task(id: chat.selectedID) { await chat.reload(); await refreshContext() }
        .task { await loadModelLabel() }
        .onChange(of: configuration) { if !configuration { Task { await loadModelLabel() } } }
        .onChange(of: usingChatGPT) { Task { await loadModelLabel() } }
        .onDisappear { requestID = UUID(); attachmentTask?.cancel(); chat.stop() }
        .overlay { if fileDrag { RoundedRectangle(cornerRadius: 10).stroke(palette.accent, lineWidth: 3).allowsHitTesting(false) } }
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

    // MARK: Header and list

    private func header(_ palette: MacChatPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(palette.accent)
            Text("AI conversations").font(.headline).foregroundStyle(palette.text)
            Spacer()
            if chat.isBusy { ProgressView().controlSize(.small) }
            MacChatChip(title: modelLabel.isEmpty ? "Set up connection" : modelLabel, systemImage: "cpu", palette: palette, action: { configuration = true })
                .help("Connection settings")
            MacChatIconButton(systemImage: "gearshape.2", help: "Agent runs", palette: palette) { agentControls = true }.disabled(busy || chat.isBusy)
            Button("Done") { Task { if await chat.prepareToLeave() { dismiss() } } }.buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).background(palette.sidebar)
    }

    private func sidebar(_ palette: MacChatPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(palette.sidebarMuted)
                    TextField("Search", text: $query).textFieldStyle(.plain).font(.callout).foregroundStyle(palette.sidebarText)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(palette.hover, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.line))
                MacChatIconButton(systemImage: "arrow.clockwise", help: "Refresh conversations", palette: palette) { Task { await chat.reload() } }.disabled(chat.isBusy || busy)
                MacChatIconButton(systemImage: "square.and.pencil", help: "New conversation", palette: palette) { select(nil) }.disabled(locked)
            }
            Picker("Conversations", selection: $show) { ForEach(["Active", "Archived", "Trash"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            if show == "Trash" { Text("Chats owned by this Mac are permanently removed after 30 days when history refreshes. Unsent drafts and active work delay cleanup.").font(.caption).foregroundStyle(palette.sidebarMuted) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(MacChatListGroup.sections(filtered)) { section in
                        Text(section.group.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.4).foregroundStyle(palette.sidebarMuted)
                            .padding(.horizontal, 9).padding(.top, 10).padding(.bottom, 3).accessibilityAddTraits(.isHeader)
                        ForEach(section.items) { item in
                            Button { select(item.id) } label: { MacChatConversationRow(item: item, selected: chat.selectedID == item.id, ownedHere: item.owner.id == chat.device.id, palette: palette) }
                                .buttonStyle(MacBoxButtonStyle()).disabled(locked)
                        }
                    }
                    if filtered.isEmpty { Text(query.isEmpty ? "No conversations" : "No matching conversations").font(.caption).foregroundStyle(palette.sidebarMuted).padding(9) }
                }
            }
        }
        .padding(10).background(palette.sidebar)
    }

    // MARK: Conversation

    private func conversationPane(_ palette: MacChatPalette) -> some View {
        VStack(spacing: 0) {
            if let item = chat.conversation {
                HStack(spacing: 8) {
                    Text(item.title).font(.headline).foregroundStyle(palette.text).lineLimit(1)
                    Spacer()
                    Menu {
                        Button("Rename…") { name = item.title; rename = true }
                        if item.archivedAt == nil && item.deletedAt == nil { Button("Archive") { change(.archive) }; Button("Move to Trash") { change(.delete) } }
                        else { Button("Restore conversation") { change(.restore) } }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(palette.muted) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(palette.muted).help("Conversation actions").accessibilityLabel("Conversation actions")
                        .disabled(chat.isBusy || item.owner.id != chat.device.id || chat.hasUnsavedReply)
                }.padding(.horizontal, 18).padding(.vertical, 10)
                Rectangle().fill(palette.line).frame(height: 1)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if chat.messages.isEmpty {
                            MacChatEmptyState(contextTitles: contextReferences.map { noteTitle($0.path) }, palette: palette) { chat.draft = $0.prompt }
                                .disabled(!chat.writable || locked)
                        }
                        ForEach(chat.messages) { message in messageView(message, palette).id(message.id) }
                        if let agent = workspace.agentController, agent.workspace.owner == chat.device.id {
                            MacChatPendingProposals(controller: agent, chat: chat, palette: palette, locked: locked,
                                review: { record, ids in reviewProposals(agent, record, ids) },
                                reject: { record, id in rejectProposal(agent, record, id) })
                        }
                        if !chat.isBusy, chat.writable, chat.messages.last?.role == "user" || chat.messages.last?.interrupted == true {
                            HStack { Spacer(); Button { retry() } label: { Label("Retry reply", systemImage: "arrow.clockwise") }.controlSize(.small).disabled(busy || !chat.writable || chat.hasUnsavedReply) }
                        }
                        Color.clear.frame(height: 1).id("reply-bottom")
                    }
                    .frame(maxWidth: 680).padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: .infinity)
                }
                .onChange(of: chat.live?.text) { if chat.running { proxy.scrollTo("reply-bottom", anchor: .bottom) } }
            }
            VStack(alignment: .leading, spacing: 8) {
                if !chat.recoveryArchive.isEmpty || chat.hasUnsavedReply {
                    DisclosureGroup("Local reply recovery (\(chat.recoveryArchive.count))") {
                        ScrollView { VStack(alignment: .leading, spacing: 10) { ForEach(chat.recoveryArchive) { recovery in VStack(alignment: .leading) { Text(recovery.text).font(.caption).textSelection(.enabled).lineLimit(5); Button("Export recovery…") { export(recovery.text) } } } } }.frame(maxHeight: 150)
                        if chat.hasUnsavedReply { Button("Keep recovery and continue") { do { try chat.keepRecoveryAndContinue() } catch { chat.issue = error.localizedDescription } } }
                    }.font(.caption)
                }
                if let launchNotice { Text(launchNotice).font(.caption).foregroundStyle(palette.muted) }
                if let status = chat.documentContextStatus { Text(status).font(.caption).foregroundStyle(palette.muted) }
                composer(palette)
                HStack(spacing: 4) {
                    Spacer()
                    Text("Sent to your AI provider: this conversation, attachments and selected notes.").font(.caption2).foregroundStyle(palette.muted)
                    Button { privacyInfo.toggle() } label: { Image(systemName: "info.circle").font(.caption2).foregroundStyle(palette.muted) }
                        .buttonStyle(.plain).accessibilityLabel("What is shared").help("What is shared")
                        .popover(isPresented: $privacyInfo) {
                            Text("Paste images or drop image, PDF and text files into chat. Send shares this conversation, image attachments, document text or excerpts, and selected note snapshots with the configured provider. Images need a vision-capable model. Credentials stay in Keychain; saved conversations travel with the vault.")
                                .font(.callout).fixedSize(horizontal: false, vertical: true).frame(width: 320).padding(14)
                        }
                    Spacer()
                }
            }
            .frame(maxWidth: 720).padding(.horizontal, 20).padding(.bottom, 12).frame(maxWidth: .infinity)
        }
        .background(palette.editor)
    }

    @ViewBuilder private func messageView(_ message: MacConversationMessage, _ palette: MacChatPalette) -> some View {
        if message.role == "user" {
            VStack(alignment: .trailing, spacing: 6) {
                if !message.text.isEmpty {
                    MacChatMessageText(text: message.text).foregroundStyle(palette.text)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(palette.accentSoft, in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, bottomTrailingRadius: 4, topTrailingRadius: 14))
                        .frame(maxWidth: 520, alignment: .trailing)
                }
                if let id = chat.selectedID { MacChatMessageImages(root: chat.root, conversationID: id, message: message, version: chat.attachmentEpoch) }
                if message.interrupted { Text("Interrupted").font(.caption).foregroundStyle(palette.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing).accessibilityElement(children: .contain).accessibilityLabel("You")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if message.text.isEmpty {
                    if chat.running && message.id == chat.live?.id { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(palette.muted) } }
                    else { Text("Stopped before text was received.").font(.caption).foregroundStyle(palette.muted) }
                } else { MacChatMessageText(text: message.text).foregroundStyle(palette.text).frame(maxWidth: .infinity, alignment: .leading) }
                if message.interrupted { Text("Interrupted").font(.caption).foregroundStyle(palette.muted) }
                if !message.text.isEmpty {
                    HStack(spacing: 2) {
                        MacChatIconButton(systemImage: "doc.on.doc", help: "Copy reply", palette: palette, size: 24) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) }
                        MacChatIconButton(systemImage: "square.and.arrow.down", help: "Save as note", palette: palette, size: 24) { saveNote(message.text) }
                    }.padding(.leading, -5).disabled(chat.isBusy || busy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain).accessibilityLabel("Zerus")
        }
    }

    // MARK: Composer

    @ViewBuilder private func composer(_ palette: MacChatPalette) -> some View {
        if let item = chat.conversation, item.owner.id != chat.device.id {
            MacChatBanner(systemImage: "lock", message: "Read-only · owned by " + item.owner.name, palette: palette) {
                Button("Move to this Mac…") { claim = true }.buttonStyle(.borderedProminent).disabled(chat.isBusy)
            }
        } else if let item = chat.conversation, item.archivedAt != nil || item.deletedAt != nil {
            MacChatBanner(systemImage: item.deletedAt != nil ? "trash" : "archivebox", message: item.deletedAt != nil ? "This conversation is in the Trash. Restore it to continue." : "This conversation is archived. Restore it to continue.", palette: palette) {
                Button("Restore") { change(.restore) }.buttonStyle(.borderedProminent).disabled(chat.isBusy || chat.hasUnsavedReply)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(contextReferences, id: \.path) { reference in
                            MacChatChip(title: noteTitle(reference.path), systemImage: "doc.text", palette: palette, emphasized: true, remove: { removeContext(reference.path) }).help(reference.path)
                        }
                        ForEach(chat.selectedImages) { image in
                            ZStack(alignment: .topTrailing) {
                                MacChatPendingThumbnail(id: image.id, bytes: image.bytes, width: 40, height: 28).clipShape(RoundedRectangle(cornerRadius: 5))
                                Button { do { try chat.removeImage(image.id) } catch { chat.issue = error.localizedDescription } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(palette.text, palette.surface)
                                }.buttonStyle(.plain).offset(x: 5, y: -5).accessibilityLabel("Remove " + image.name)
                            }.help(image.name)
                        }
                        ForEach(chat.selectedDocuments) { document in
                            MacChatChip(title: document.name, systemImage: "doc.richtext", palette: palette, action: { documentPreview = document },
                                        remove: { do { try chat.removeDocument(document.id) } catch { chat.issue = error.localizedDescription } })
                        }
                        MacChatChip(title: "Add notes", systemImage: "plus", palette: palette, action: { contextPicker = true })
                    }.padding(.vertical, 4).padding(.trailing, 6)
                }.disabled(chat.isBusy || busy)
                ZStack(alignment: .topLeading) {
                    MacChatComposer(text: $chat.draft, enabled: !busy, acceptsAttachments: !chat.isBusy && chat.writable && !chat.hasUnsavedReply, textColor: theme.nsColor(.text), attach: importAttachments, issue: { chat.issue = $0 }).id(chat.selectedID ?? "new").frame(height: 54)
                    if chat.draft.isEmpty { Text("Ask about your notes…").font(.system(size: 13)).foregroundStyle(palette.muted).padding(.leading, 5).allowsHitTesting(false).accessibilityHidden(true) }
                }
                HStack(spacing: 2) {
                    Menu {
                        Button("Add images…") { importImages() }.disabled(chat.selectedImages.count >= 4)
                        Button("Add documents…") { importDocuments() }
                    } label: { Image(systemName: "paperclip").foregroundStyle(palette.muted) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(palette.muted).frame(width: 26, height: 26)
                        .help("Attach images or documents").accessibilityLabel("Attach").disabled(chat.isBusy || busy || !chat.writable)
                    MacChatIconButton(systemImage: "at", help: "Choose notes to share", palette: palette) { contextPicker = true }.disabled(chat.isBusy || busy)
                    Spacer()
                    if chat.isBusy {
                        Button { chat.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 26, height: 26).background(palette.accent, in: Circle()) }
                            .buttonStyle(.plain).help("Stop").accessibilityLabel("Stop")
                    } else {
                        Button { send() } label: {
                            Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(canSend ? Color.white : palette.muted)
                                .frame(width: 26, height: 26).background(canSend ? palette.accent : palette.hover, in: Circle())
                        }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command).disabled(!canSend).help("Send (⌘↩)").accessibilityLabel("Send")
                    }
                }
            }
            .padding(10).background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line))
        }
    }

    // MARK: Actions

    private func loadModelLabel() async {
        if usingChatGPT { modelLabel = "ChatGPT account"; return }
        let legacy = MacAIProfile.legacy(endpoint: endpoint, model: model, contextWindow: contextWindow, format: MacAIFormat(rawValue: apiFormat) ?? .compatible)
        do {
            let profile = try await workspace.aiProfile(legacy: legacy)
            modelLabel = profile.model.isEmpty ? profile.provider.label : profile.model + " · " + profile.provider.label
        } catch { modelLabel = "" }
    }
    private func removeContext(_ path: String) {
        do { try chat.setContextReferences(contextReferences.filter { $0.path != path }) } catch { chat.issue = error.localizedDescription }
    }
    private func openLinkedNote(_ target: String) {
        guard !chat.isBusy else { chat.issue = "Wait for the reply to finish before opening a note."; return }
        Task { if await chat.prepareToLeave() { dismiss(); await workspace.follow(target) } }
    }
    private func reviewProposals(_ agent: MacAgentController, _ record: NativeAgentRecord, _ ids: Set<UUID>) {
        busy = true
        Task { defer { busy = false }; do {
            try await chat.validateAgentConversation(record); try await agent.reviewProposals(ids); agentControls = true
        } catch { chat.issue = error.localizedDescription } }
    }
    private func rejectProposal(_ agent: MacAgentController, _ record: NativeAgentRecord, _ id: UUID) {
        busy = true
        Task { defer { busy = false }; do {
            try await chat.validateAgentConversation(record); try await agent.reject(id)
        } catch { chat.issue = error.localizedDescription } }
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
        let source = MacChatLinks.linked(text)
        Text((try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .textSelection(.enabled).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
    }
}
/// Decodes a selected image's thumbnail once instead of on every render.
private struct MacChatPendingThumbnail: View {
    let id: String
    let bytes: Data
    var width: CGFloat = 90
    var height: CGFloat = 65
    @State private var bitmap: (id: String, image: NSImage?)?
    var body: some View {
        Group {
            if let image = bitmap?.image, bitmap?.id == id { Image(nsImage: image).resizable().scaledToFill().frame(width: width, height: height).clipped() }
            else { Color.clear.frame(width: width, height: height) }
        }.task(id: id) { if bitmap?.id != id { bitmap = (id, NSImage(data: bytes)) } }
    }
}
