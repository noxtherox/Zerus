import ZerusIOSServices
import SwiftUI
import CryptoKit

struct ChatMessage: Identifiable, Codable, Sendable {
    var id = UUID()
    let role: String
    var content: String
    var attachments: [NativeChatAttachment]? = nil
    var attachmentContext: String? = nil
}

struct NativeChatArchive: Identifiable, Sendable {
    let url: URL
    let modified: Date
    let messages: [ChatMessage]?
    var id: URL { url }
    var title: String {
        let first = messages?.first(where: { $0.role == "user" })?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return first.isEmpty ? "Saved conversation" : String(first.prefix(90))
    }
}

@MainActor
final class NativeChat: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var archives: [NativeChatArchive] = []
    @Published var draft = "" {
        didSet {
            persistDraft()
            if let lease = dictationDraft, lease.lastWritten != draft { dictation.promptChanged() }
        }
    }
    @Published private(set) var draftProblem: String?
    @Published var running = false
    @Published var error: String?
    @Published var status: CloudAIStatusResponse
    let provider = CloudAIManager()
    let agent = NativeAgentController()
    let dictation = NativeDictationController()
    private var dictationDraft: NativeDictationDraft?
    var dictating: Bool { dictationDraft != nil }
    private let emptyConversationID = UUID().uuidString
    var conversationID: String { messages.first?.id.uuidString ?? emptyConversationID }
    let attachmentStore: NativeChatAttachmentStore
    @Published private(set) var attachments: [NativeChatAttachment] = []
    @Published private(set) var attachmentProblem: String?
    @Published private(set) var importingAttachments = false
    private var attachmentDraftBytes: Data?
    var attachmentDraftAvailable: Bool { attachmentDraftWritable }
    var outgoingPrompt: String { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !attachments.isEmpty ? "Please help me understand the attached files and images." : draft }
    private var attachmentDraftWritable = true
    private var attachmentImport: (id: UUID, conversation: String)?
    var attachmentRecoveryURL: URL? { attachmentProblem != nil && FileManager.default.fileExists(atPath: attachmentStore.draftURL.path) ? attachmentStore.draftURL : nil }
    private let historyURL: URL
    private let earlierURL: URL
    private var historyBytes: Data?
    private var historyWritable = true
    private var draftWritable = true
    private var draftURL: URL { historyURL.deletingLastPathComponent().appendingPathComponent("prompt.txt") }
    var draftRecoveryURL: URL? { draftProblem != nil && FileManager.default.fileExists(atPath: draftURL.path) ? draftURL : nil }
    private final class WeakChat { weak var value: NativeChat?; init(_ value: NativeChat) { self.value = value } }
    private static var openChats: [URL: WeakChat] = [:]
    private static var chatVaultIDs: [URL: UUID] = [:]
    @Published private(set) var storageProblem: String?

    // Windows showing the same vault observe one live conversation, so one
    // streaming answer cannot overwrite another window's independent copy.
    static func shared(for vaultRoot: URL) -> NativeChat {
        let root = vaultRoot.standardizedFileURL
        let id = NativeChatStorage.registeredID(for: root)
        if let chat = openChats[root]?.value, chat.storageProblem == nil, chatVaultIDs[root] == id { return chat }
        let directory: URL
        do { directory = try NativeChatStorage.location(for: root) ?? Self.legacyDirectory(for: root) }
        catch { return NativeChat(vaultRoot: root) }
        if let chat = openChats.values.compactMap(\.value).first(where: { $0.storageProblem == nil && $0.attachmentStore.directory.standardizedFileURL.path == directory.standardizedFileURL.path }) { openChats[root] = WeakChat(chat); chatVaultIDs[root] = id; return chat }
        openChats = openChats.filter { $0.value.value != nil }
        let chat = NativeChat(vaultRoot: root); openChats[root] = WeakChat(chat); chatVaultIDs[root] = id
        return chat
    }
    nonisolated static func directory(for vaultRoot: URL) -> URL { (try? NativeChatStorage.location(for: vaultRoot)) ?? legacyDirectory(for: vaultRoot) }
    nonisolated static func legacyDirectory(for vaultRoot: URL) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let key = SHA256.hash(data: Data(vaultRoot.standardizedFileURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return support.appendingPathComponent("NativeChats/" + key)
    }
    static func liveSearchConversation(for root: URL) -> NativeSearchConversation? {
        guard let chat = openChats[root.standardizedFileURL]?.value, !chat.messages.isEmpty else { return nil }
        let modified = chat.running ? Date() : (try? chat.historyURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return .init(id: "native-current", title: String((chat.messages.first { $0.role == "user" }?.content ?? "Current conversation").prefix(90)), modified: modified, archived: false, messages: chat.messages, origin: .current)
    }
    init(vaultRoot: URL) {
        status = provider.status()
        let location: URL
        do { location = try NativeChatStorage.location(for: vaultRoot) ?? Self.legacyDirectory(for: vaultRoot) }
        catch { location = Self.legacyDirectory(for: vaultRoot); storageProblem = error.localizedDescription }
        attachmentStore = NativeChatAttachmentStore(directory: location)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        historyURL = location.appendingPathComponent("current.json")
        earlierURL = support.appendingPathComponent("native-chat.json")
        if let storageProblem { historyWritable = false; draftWritable = false; attachmentDraftWritable = false; self.error = storageProblem; attachmentProblem = storageProblem; return }
        do {
            if FileManager.default.fileExists(atPath: historyURL.path) {
                let bytes = try Data(contentsOf: historyURL); historyBytes = bytes
                messages = try JSONDecoder().decode([ChatMessage].self, from: bytes)
            }
        } catch {
            historyWritable = false
            self.error = "The saved conversation couldn’t be read. Start a new conversation to keep a recovery copy of the original."
        }
        if FileManager.default.fileExists(atPath: draftURL.path) {
            do { draft = try String(contentsOf: draftURL, encoding: .utf8) }
            catch { draftWritable = false; draftProblem = "The saved prompt couldn’t be read. The original file is kept for recovery." }
        }
        do { let saved = try attachmentStore.loadDraft(); attachmentDraftBytes = saved.0; attachments = saved.1 }
        catch { attachmentDraftWritable = false; attachmentProblem = error.localizedDescription }
        loadArchives()
    }
    func beginAttachmentImport() -> UUID? {
        guard attachmentDraftWritable, !running, !agent.running, !dictating, !importingAttachments else { return nil }
        let id = UUID(); attachmentImport = (id, conversationID); importingAttachments = true; return id
    }
    func cancelAttachmentImport(_ id: UUID) {
        if attachmentImport?.id == id { attachmentImport = nil; importingAttachments = false }
    }
    func addAttachments(_ inputs: [NativePreparedChatAttachment], importID: UUID) async throws -> Bool {
        guard let lease = attachmentImport, lease.id == importID, lease.conversation == conversationID, !running, !agent.running, !dictating else { return false }
        try NativeChatAttachment.validateBatch(attachments + inputs.map(\.descriptor))
        let added = try await attachmentStore.commit(inputs)
        guard !Task.isCancelled, attachmentImport?.id == importID, lease.conversation == conversationID, !running, !agent.running, !dictating else {
            for item in added { attachmentStore.discardUnreferenced(item) }; return false
        }
        do {
            let next = attachments + added, bytes = try attachmentStore.saveDraft(next, expected: attachmentDraftBytes)
            attachments = next; attachmentDraftBytes = bytes; attachmentProblem = nil; return true
        } catch { for item in added { attachmentStore.discardUnreferenced(item) }; throw error }
    }
    func removeAttachment(_ id: UUID) {
        guard attachmentDraftWritable, !running, !agent.running, !dictating, !importingAttachments else { return }
        let removed = attachments.first { $0.id == id }, next = attachments.filter { $0.id != id }
        do {
            let bytes = try attachmentStore.saveDraft(next, expected: attachmentDraftBytes); attachments = next; attachmentDraftBytes = bytes; attachmentProblem = nil
            if let removed, historyWritable, archives.allSatisfy({ $0.messages != nil }), !(messages + archives.flatMap { $0.messages ?? [] }).flatMap({ $0.attachments ?? [] }).contains(where: { $0.id == removed.id }) {
                let store = attachmentStore; Task.detached(priority: .utility) { store.discardUnreferenced(removed) }
            }
        }
        catch { attachmentProblem = error.localizedDescription }
    }
    func reuseAttachment(_ item: NativeChatAttachment) {
        guard attachmentDraftWritable, !running, !agent.running, !dictating, !importingAttachments, !attachments.contains(where: { $0.id == item.id }) else { return }
        do { try attachmentStore.manifest(item); let next = attachments + [item]; try NativeChatAttachment.validateBatch(next); let bytes = try attachmentStore.saveDraft(next, expected: attachmentDraftBytes); attachments = next; attachmentDraftBytes = bytes; attachmentProblem = nil }
        catch { attachmentProblem = error.localizedDescription }
    }
    func recoverAttachmentDraft() {
        guard storageProblem == nil, !running, !agent.running, !dictating, !importingAttachments else { return }
        do { try attachmentStore.recoverDraft(); let saved = try attachmentStore.loadDraft(); attachments = saved.1; attachmentDraftBytes = saved.0; attachmentDraftWritable = true; attachmentProblem = nil }
        catch { attachmentProblem = error.localizedDescription }
    }
    func consumeAttachments(_ expected: [NativeChatAttachment]) {
        guard attachments == expected, attachmentDraftWritable else { return }
        do { let bytes = try attachmentStore.saveDraft([], expected: attachmentDraftBytes); attachments = []; attachmentDraftBytes = bytes; attachmentProblem = nil }
        catch { attachmentProblem = "The sent attachments remain in the draft because its saved file changed. " + error.localizedDescription }
    }
    private func persistDraft() {
        guard draftWritable else { return }
        do {
            try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(draft.utf8).write(to: draftURL, options: .atomic)
            draftProblem = nil
        } catch { draftProblem = "Could not keep this prompt on disk. Copy your text before closing this workspace." }
    }
    var hasEarlierConversation: Bool {
        guard let bytes = try? Data(contentsOf: earlierURL), let messages = try? JSONDecoder().decode([ChatMessage].self, from: bytes) else { return false }
        return !messages.isEmpty
    }
    func refresh() { status = provider.status() }
    @discardableResult
    func restoreEarlierConversation() -> Bool {
        guard !running, !agent.running, !dictating, !importingAttachments, messages.isEmpty, historyWritable else { return false }
        do {
            let bytes = try Data(contentsOf: earlierURL), earlier = try JSONDecoder().decode([ChatMessage].self, from: bytes)
            guard !earlier.isEmpty else { return false }
            let previous = messages; messages = earlier
            if persist() { error = nil; return true }
            messages = previous
        } catch { self.error = "Could not restore the earlier conversation: \(error.localizedDescription)" }
        return false
    }
    func clear() {
        guard storageProblem == nil, !running, !agent.running, !dictating, !importingAttachments else { return }
        do {
            try archiveCurrent()
            let previous = messages, writable = historyWritable
            messages = []; historyWritable = true
            if persist() { error = nil } else { messages = previous; historyWritable = writable }
        } catch { self.error = "Could not start a new conversation: \(error.localizedDescription)" }
    }
    @discardableResult
    func open(_ archive: NativeChatArchive) -> Bool {
        guard !running, !agent.running, !dictating, !importingAttachments, archives.contains(where: { $0.url == archive.url }) else { return false }
        do {
            let bytes = try Data(contentsOf: archive.url), selected = try JSONDecoder().decode([ChatMessage].self, from: bytes)
            try archiveCurrent()
            let previous = messages, writable = historyWritable
            messages = selected; historyWritable = true
            if persist() { error = nil; return true }
            messages = previous; historyWritable = writable
        } catch { self.error = "Could not open this conversation: \(error.localizedDescription)" }
        return false
    }
    private func archiveCurrent() throws {
        let current = FileManager.default.fileExists(atPath: historyURL.path) ? try Data(contentsOf: historyURL) : nil
        guard current == historyBytes else { throw VaultFailure(message: "The saved conversation changed. Reopen it before continuing.") }
        guard let current, !messages.isEmpty || !historyWritable else { return }
        let directory = historyURL.deletingLastPathComponent().appendingPathComponent("Previous", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Reopening the same history does not create duplicate snapshots.
        if !archives.contains(where: { (try? Data(contentsOf: $0.url)) == current }) {
            try current.write(to: directory.appendingPathComponent(UUID().uuidString.lowercased() + ".json"), options: .atomic)
        }
        loadArchives()
    }
    private func loadArchives() {
        let directory = historyURL.deletingLastPathComponent().appendingPathComponent("Previous", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { archives = []; return }
        do {
            archives = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]).filter { $0.pathExtension == "json" }.map {
                let bytes = try Data(contentsOf: $0), date = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                return NativeChatArchive(url: $0, modified: date, messages: try? JSONDecoder().decode([ChatMessage].self, from: bytes))
            }.sorted { $0.modified > $1.modified }
        } catch { self.error = "Could not load previous conversations: \(error.localizedDescription)" }
    }
    @discardableResult
    private func persist() -> Bool {
        guard historyWritable else { return false }
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let current = FileManager.default.fileExists(atPath: historyURL.path) ? try Data(contentsOf: historyURL) : nil
            guard current == historyBytes else { throw VaultFailure(message: "The saved conversation changed. Reopen it before continuing.") }
            let bytes = try JSONEncoder().encode(messages)
            try bytes.write(to: historyURL, options: .atomic); historyBytes = bytes
            return true
        } catch { self.error = "Could not save this conversation: \(error.localizedDescription)"; return false }
    }
    func beginDictation(workspace: UUID) -> UUID? {
        guard draftWritable, !running, !agent.running, !importingAttachments, dictationDraft == nil else { return nil }
        let lease = NativeDictationDraft(workspace: workspace, conversationID: conversationID, prefix: draft)
        dictationDraft = lease; return lease.id
    }
    @discardableResult
    func acceptDictation(_ transcript: String, id: UUID, workspace: UUID) -> Bool {
        guard var lease = dictationDraft, lease.id == id, lease.workspace == workspace,
              lease.conversationID == conversationID, draft == lease.lastWritten,
              draftWritable, !running, !agent.running else { return false }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 100_000 else { return false }
        let next = lease.prefix + (!lease.prefix.isEmpty && !text.isEmpty && lease.prefix.last?.isWhitespace != true ? " " : "") + text
        lease.lastWritten = next; dictationDraft = lease
        if draft != next { draft = next }
        return true
    }
    func endDictation(_ id: UUID) { if dictationDraft?.id == id { dictationDraft = nil } }
    func beginAgentTurn(_ prompt: String, attachments: [NativeChatAttachment] = [], context: String? = nil) -> UUID? {
        guard historyWritable, !running, !dictating, !importingAttachments else { return nil }
        if !attachments.isEmpty {
            do {
                guard attachments == self.attachments, try attachmentStore.loadDraft().0 == attachmentDraftBytes else { throw VaultFailure(message: "The attachment draft changed. Reopen Ask before sending.") }
                for item in attachments { try attachmentStore.retain(item) }
            } catch { self.error = error.localizedDescription; return nil }
        }
        let previous = messages
        messages.append(.init(role: "user", content: prompt, attachments: attachments.isEmpty ? nil : attachments, attachmentContext: context)); messages.append(.init(role: "assistant", content: ""))
        let id = messages.last!.id
        guard persist() else { messages = previous; return nil }; running = true; return id
    }
    func updateAgentTurn(_ id: UUID, content: String) { if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].content = content } }
    func appendAgentDelta(_ id: UUID, text: String) { if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].content += text } }
    func finishAgentTurn(_ id: UUID, fallback: String) {
        running = false
        if let index = messages.firstIndex(where: { $0.id == id }), messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages[index].content = fallback }
        persist()
    }
}

struct NativeChatView: View {
    @EnvironmentObject private var vault: VaultStore
    let workspaceID: UUID
    @ObservedObject var chat: NativeChat
    @ObservedObject var agent: NativeAgentController
    var searchRequest: NativeSearchAskRequest? = nil
    var searchRequestHandled: () -> Void = {}
    let library: () -> Void
    let settings: () -> Void
    init(workspaceID: UUID, chat: NativeChat, searchRequest: NativeSearchAskRequest? = nil, searchRequestHandled: @escaping () -> Void = {}, library: @escaping () -> Void, settings: @escaping () -> Void) {
        self.workspaceID = workspaceID; self._chat = ObservedObject(wrappedValue: chat); self._agent = ObservedObject(wrappedValue: chat.agent)
        _dictation = ObservedObject(wrappedValue: chat.dictation)
        self.searchRequest = searchRequest; self.searchRequestHandled = searchRequestHandled
        self.library = library; self.settings = settings
    }
    @State private var sending = false
    @State private var agentPermissions = false
    @State private var aiGuidance = false
    @State private var aiLimits = false
    @State private var aiWorkflows = false
    @State private var agentRuns = false
    @ObservedObject private var dictation: NativeDictationController
    @State private var scopeChoice: NativeAgentScopeChoice = .selected
    @State private var scopeFolder = ""
    @State private var allowCreate = false
    @State private var createFolder = ""
    @State private var currentOnly = false
    @State private var currentWritePath = ""
    @State private var opened: NativeOpenedNote?
    @State private var referenceDocument: NativeSearchDocument?
    @State private var context: Set<String> = []
    @State private var contextPicker = false
    @State private var config = false
    @State private var history = false
    @State private var followingReply = true
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if chat.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Accent.color)
                                    Text("Think it through.").font(.system(.largeTitle, design: .serif))
                                    Text("Bring a question. Add a few notes. Find the thread that connects them.").foregroundStyle(.secondary)
                                    if chat.hasEarlierConversation {
                                        Button("Restore earlier conversation") { chat.restoreEarlierConversation() }.accessibilityIdentifier("chat.restoreEarlier")
                                        Text("Restore it here if this is the vault it belongs to. Its history is included when you continue the conversation.").font(.caption).foregroundStyle(.secondary)
                                    }
                                    ForEach(["Help me reflect on my notes", "Find the next step in my project", "Summarize the ideas I’ve selected"], id: \.self) { suggestion in
                                        Button { chat.draft = suggestion; focused = true } label: { HStack { Text(suggestion).multilineTextAlignment(.leading); Spacer(); Image(systemName: "arrow.up.left") }.font(.subheadline).padding(14).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14)) }
                                    }
                                }.padding(.top, 40)
                            }
                            ForEach(chat.messages) { message in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(message.role == "user" ? "YOU" : "ZERUS").font(.caption2.bold()).tracking(1.5).foregroundStyle(.secondary)
                                    if let items = message.attachments, !items.isEmpty { NativeChatMessageAttachments(items: items, chat: chat) }
                                    if message.content.isEmpty { ProgressView("Thinking…") }
                                    else {
                                        Text((try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.content))
                                            .textSelection(.enabled).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                                        if message.role == "assistant" {
                                            HStack {
                                                ShareLink(item: message.content) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share answer")
                                                Button { Task { _ = await vault.createNote(title: "From Zerus · " + Date().formatted(date: .abbreviated, time: .omitted), body: message.content, workspace: workspaceID) } } label: { Label("Save as note", systemImage: "square.and.pencil") }
                                            }.font(.caption).foregroundStyle(.secondary).padding(.top, 5).disabled(chat.running || agent.running)
                                        }
                                    }
                                }.padding(message.role == "user" ? 16 : 0).background(message.role == "user" ? Color.secondary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 18)).id(message.id)
                            }
                            if let error = chat.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .onAppear { followingReply = true; proxy.scrollTo("bottom", anchor: .bottom) }
                    .accessibilityLabel("Conversation").accessibilityIdentifier("chat.history")
                    .onScrollPhaseChange { _, phase, context in
                        if phase == .tracking || phase == .interacting {
                            followingReply = false
                        } else if phase == .idle {
                            followingReply = context.geometry.visibleRect.maxY >= context.geometry.contentSize.height - 24
                        }
                    }
                    .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { before, after in
                        if after.visibleRect.maxY >= after.contentSize.height - 24 {
                            followingReply = true
                        } else if after.contentSize == before.contentSize,
                                  after.containerSize == before.containerSize,
                                  after.contentOffset.y < before.contentOffset.y - 1 {
                            // Accessibility scrolling can move history without a touch phase.
                            // Ignore reflow when new reply text or the keyboard changes its size.
                            followingReply = false
                        }
                    }
                    .onChange(of: chat.messages.last?.content) { _, _ in
                        if followingReply { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: chat.running) { _, running in
                        if running { followingReply = true }
                        if followingReply { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: chat.conversationID) { _, _ in
                        followingReply = true
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    .onChange(of: agentRuns) { _, presented in
                        if !presented && followingReply { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !followingReply && !chat.messages.isEmpty {
                            Button("Latest message", systemImage: "arrow.down") {
                                followingReply = true
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                                .accessibilityIdentifier("chat.latest").padding(12)
                        }
                    }
                }
                VStack(spacing: 10) {
                    Picker("Agent mode", selection: $agent.mode) { ForEach(NativeAgentMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(agent.running || chat.running || dictation.active || chat.importingAttachments).accessibilityIdentifier("agent.mode")
                    HStack(alignment: .top) {
                        Text(agent.mode.explanation).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button { agentPermissions = true } label: { Label(scopeChoice == .selected ? "Permissions" : scopeChoice.rawValue, systemImage: "scope") }.font(.caption).disabled(agent.running || chat.running || dictation.active || chat.importingAttachments).accessibilityIdentifier("agent.permissions")
                    }
                    if let current = agent.current {
                        Button { agentRuns = true } label: { Label(agent.running ? "Working · \(current.run.steps) model steps" : NativeAgentRunsView.status(current, controller: agent), systemImage: current.run.pending.isEmpty ? "list.bullet.rectangle" : "doc.text.magnifyingglass") }.font(.caption).accessibilityIdentifier("agent.current")
                    }
                    if let issue = agent.issue { Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled).accessibilityIdentifier("agent.issue") }
                    if let document = referenceDocument {
                        HStack { Label(document.name, systemImage: "doc.text").lineLimit(1); Spacer(); Button("Remove reference", systemImage: "xmark.circle") { referenceDocument = nil }.labelStyle(.iconOnly) }.font(.caption).accessibilityIdentifier("chat.reference")
                    }
                    NativeChatAttachmentComposer(chat: chat, workspaceID: workspaceID)
                    HStack {
                        Button { if scopeChoice == .selected { contextPicker = true } else { agentPermissions = true } } label: { Label(scopeChoice == .vault ? "Entire vault" : scopeChoice == .folder ? "Folder: " + (scopeFolder.isEmpty ? "Inbox" : scopeFolder) : context.isEmpty ? "Add note context" : "\(context.count) \(context.count == 1 ? "note" : "notes") selected", systemImage: "plus.circle") }.disabled(agent.running || chat.running || dictation.active || chat.importingAttachments).accessibilityIdentifier("chat.chooseContext")
                        Spacer()
                        if focused {
                            Button("Done") { focused = false }.accessibilityLabel("Dismiss message keyboard").accessibilityIdentifier("chat.keyboard.dismiss")
                        } else {
                            Text(chat.status.configured ? (chat.status.model.isEmpty ? "ChatGPT" : chat.status.model) : "Connect to begin").accessibilityIdentifier("chat.connection.status").lineLimit(1).foregroundStyle(.secondary).onTapGesture { if !dictation.active { config = true } }
                        }
                    }.font(.caption)
                    if dictation.active {
                        HStack(alignment: .top) {
                            Label(dictation.phase.label, systemImage: dictation.phase == .listening ? "waveform" : "mic").accessibilityIdentifier("voice.status")
                            Spacer()
                            Button("Cancel") { dictation.cancel() }.accessibilityIdentifier("voice.cancel")
                        }.font(.caption).foregroundStyle(Accent.color)
                    }
                    if let issue = dictation.issue {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(issue).accessibilityIdentifier("voice.error")
                            if dictation.needsSettings, let url = URL(string: UIApplication.openSettingsURLString) { Link("Open Settings", destination: url) }
                            Button("Dismiss") { dictation.dismissIssue() }.accessibilityIdentifier("voice.error.dismiss")
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField("Ask anything about your notes…", text: $chat.draft, axis: .vertical).lineLimit(1...6).focused($focused).accessibilityIdentifier("chat.prompt")
                        if dictation.active {
                            Button { dictation.stop() } label: { Image(systemName: "stop.circle.fill").font(.title) }.accessibilityLabel("Stop dictation").disabled(dictation.phase != .listening).accessibilityIdentifier("voice.stop")
                        } else if chat.running || agent.running {
                            Button { agent.stop() } label: { Image(systemName: "stop.circle.fill").font(.title) }.accessibilityLabel("Stop generating")
                        } else {
                            Button { startDictation() } label: { Image(systemName: "mic.fill").font(.title3).frame(minWidth: 32, minHeight: 32) }.disabled(sending || chat.importingAttachments).accessibilityLabel("Dictate message").accessibilityIdentifier("voice.start")
                            Button {
                                sendAgent()
                            } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(sending || chat.importingAttachments || !chat.attachmentDraftAvailable || (chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.attachments.isEmpty)).accessibilityLabel("Send message")
                        }
                    }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    if let problem = chat.draftProblem {
                        Text(problem).font(.caption).foregroundStyle(.orange)
                        if let original = chat.draftRecoveryURL { ShareLink(item: original) { Label("Share saved prompt", systemImage: "square.and.arrow.up") }.font(.caption) }
                    }
                    Text("Your chosen context, attachments and this conversation are shared with the AI provider.").font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
                    .accessibilityElement(children: .contain).accessibilityLabel("Message composer").accessibilityIdentifier("chat.composer")
            }.background(Accent.paper).navigationTitle("Ask Zerus")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { NativeLibraryButton(action: library) }
                    ToolbarItem(placement: .topBarTrailing) { Menu {
                        Section("Conversations") {
                            Button("New conversation", systemImage: "square.and.pencil") { chat.clear() }.disabled(chat.running || agent.running || dictation.active || chat.importingAttachments)
                            Button("Previous conversations", systemImage: "clock.arrow.circlepath") { history = true }.accessibilityIdentifier("chat.history").disabled(dictation.active || chat.importingAttachments)
                        }
                        Section("AI") {
                            Button("AI connection") { config = true }.disabled(agent.running || chat.running || dictation.active || chat.importingAttachments)
                            Button("AI instructions and memory") { aiGuidance = true }.disabled(dictation.active || chat.importingAttachments).accessibilityIdentifier("chat.aiGuidance")
                            Button("Workflows") { aiWorkflows = true }.disabled(dictation.active || chat.importingAttachments).accessibilityIdentifier("chat.aiWorkflows")
                            Button("AI limits") { aiLimits = true }.disabled(dictation.active || chat.importingAttachments).accessibilityIdentifier("chat.aiLimits")
                            Button("Agent permissions") { agentPermissions = true }.disabled(dictation.active || chat.importingAttachments)
                            Button("AI runs") { agentRuns = true }.disabled(dictation.active || chat.importingAttachments).accessibilityIdentifier("agent.runs")
                        }
                        Section { Button("Settings", systemImage: "gearshape", action: settings) }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Settings") }
                }
                .sheet(isPresented: $agentPermissions) { NativeAgentPermissionsView(scope: $scopeChoice, folder: $scopeFolder, create: $allowCreate, creationFolder: $createFolder, currentOnly: $currentOnly, currentPath: $currentWritePath, selected: context) }
                .sheet(isPresented: $aiGuidance) { NativeAgentGuidanceView(workspaceID: workspaceID) }
                .sheet(isPresented: $aiWorkflows) { NativeAgentWorkflowsView(workspaceID: workspaceID) }
                .sheet(isPresented: $aiLimits) { NativeAgentLimitsView(workspaceID: workspaceID) }
                .sheet(isPresented: $agentRuns) { NativeAgentRunsView(controller: agent, chat: chat, workspaceID: workspaceID) }
                .fullScreenCover(item: $opened) { request in NativeNoteNavigationView(navigation: request.navigation) }
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "zerus-note" else { return .systemAction }
                    guard vault.workspaceID == workspaceID, let id = String(url.absoluteString.dropFirst("zerus-note:".count)).removingPercentEncoding else { return .handled }
                    let found = vault.notes.filter { !$0.trashed && NativeAgentNote.identity($0) == id }
                    if found.count == 1, let session = vault.session(for: found[0]) { opened = NativeOpenedNote(navigation: NativeNoteNavigation(vault: vault, session: session)) }
                    return .handled
                })
                .task(id: vault.loading || vault.switchingVault) { await agent.reload(vault: vault, workspace: workspaceID) }
                .sheet(isPresented: $contextPicker) { NotePicker(title: "Choose context", multiple: true, selected: context, reference: referenceDocument, selectReference: { referenceDocument = $0 }) { context = $0 } }
                .sheet(isPresented: $history) { NativeChatHistoryView(chat: chat) }
                .sheet(isPresented: $config, onDismiss: chat.refresh) { AISettingsView(chat: chat) }
                .task(id: searchRequest?.id) {
                    guard let request = searchRequest, request.workspaceID == workspaceID, vault.workspaceID == workspaceID else { return }
                    dictation.cancel()
                    scopeChoice = .selected
                    context.formUnion(request.notes); referenceDocument = request.document
                    if chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chat.draft = request.prompt }
                    else { chat.draft += "\n\n" + request.prompt }
                    searchRequestHandled(); focused = true
                }
                .onDisappear { focused = false; dictation.cancel() }
        }
    }
    private func startDictation() {
        guard !sending, !dictation.active, !agent.running, !chat.running, !chat.importingAttachments, vault.workspaceID == workspaceID, !vault.switchingVault else { return }
        let origin = workspaceID
        sending = true; focused = false
        Task { @MainActor in
            await Task.yield()
            defer { sending = false }
            guard vault.workspaceID == origin, !vault.switchingVault else { return }
            dictation.start(chat: chat, vault: vault, workspace: origin)
        }
    }
    private func sendAgent() {
        guard !dictation.active, !sending, !agent.running, !chat.running, !chat.importingAttachments, vault.workspaceID == workspaceID, !vault.switchingVault else { return }
        guard chat.status.configured else { config = true; return }
        let selectedMode = agent.mode, origin = workspaceID, reference = referenceDocument
        let scope = NativeAgentScope(paths: context, folder: scopeChoice == .folder ? scopeFolder : nil, entireVault: scopeChoice == .vault,
            currentWritePath: currentOnly ? currentWritePath : nil, createFolder: scopeChoice == .selected && allowCreate ? createFolder : nil)
        sending = true; focused = false
        Task {
            await Task.yield(); defer { sending = false }
            guard vault.workspaceID == origin, !vault.switchingVault else { return }
            _ = agent.start(prompt: chat.outgoingPrompt, mode: selectedMode, scope: scope, chat: chat, vault: vault, workspace: origin, reference: reference)
        }
    }

}

struct NativeChatHistoryView: View {
    @ObservedObject var chat: NativeChat
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if chat.archives.isEmpty { ContentUnavailableView("No previous conversations", systemImage: "bubble.left.and.bubble.right", description: Text("Starting a new conversation keeps the previous one here.")) }
                ForEach(chat.archives) { archive in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { if chat.open(archive) { dismiss() } } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(archive.title).foregroundStyle(.primary).lineLimit(2)
                                Text(archive.modified, format: .dateTime.day().month().year().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(chat.running || archive.messages == nil)
                        if archive.messages == nil { Text("This saved file uses an unreadable or newer format. The original is kept for recovery.").font(.caption).foregroundStyle(.secondary) }
                        ShareLink(item: archive.url) { Label("Share saved conversation", systemImage: "square.and.arrow.up") }.font(.caption)
                    }.padding(.vertical, 4)
                }
                if let error = chat.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            }.navigationTitle("Previous conversations").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct AISettingsView: View {
    @ObservedObject var chat: NativeChat
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var model = ""
    @State private var key = ""
    @State private var busy = false
    @State private var error: String?
    @State private var models: [CloudAIModelResponse] = []
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        busy = true
                        Task {
                            do { _ = try await chat.provider.handleChatGPT(ChatGPTCommand(operation: "connect", accountID: nil)); chat.refresh(); endpoint = chat.status.endpoint; model = chat.status.model; models = try await chat.provider.models().models }
                            catch { self.error = error.localizedDescription }; busy = false
                        }
                    } label: { HStack { Text("Continue with ChatGPT"); Spacer(); if busy { ProgressView() } else { Image(systemName: "arrow.up.right") } } }.disabled(busy)
                    if let account = chat.status.account { LabeledContent("Account", value: account) }
                } footer: { Text("Sign in using your ChatGPT account, or configure an API provider below.") }
                Section("Provider") {
                    TextField("API endpoint", text: $endpoint).accessibilityIdentifier("ai.endpoint").textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Model identifier", text: $model).accessibilityIdentifier("ai.model").textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API key (stored in Keychain)", text: $key).accessibilityIdentifier("ai.key").textInputAutocapitalization(.never)
                    Button("Save connection") {
                        do { _ = try chat.provider.configure(CloudAIConfigureRequest(endpoint: endpoint, model: model, apiKey: key.isEmpty ? nil : key)); chat.refresh(); key = ""; self.error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                    Button("Load available models") {
                        busy = true
                        Task { do { models = try await chat.provider.models().models } catch { self.error = error.localizedDescription }; busy = false }
                    }.disabled(busy)
                }
                if !models.isEmpty {
                    Section("Available models") {
                        Picker("Model", selection: $model) { Text("Choose").tag(""); ForEach(models, id: \.id) { Text($0.name).tag($0.id) } }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
            }.navigationTitle("AI connection").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { endpoint = chat.status.endpoint; model = chat.status.model }
        }
    }
}
