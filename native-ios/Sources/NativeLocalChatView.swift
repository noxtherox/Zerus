import SwiftUI
import ZerusLocalAICore

/// The Ask tab with on-device AI: a chat with your notes. Conversations use
/// the existing chat history storage (`NativeChat`: current conversation plus
/// previous ones, searchable), so they are saved per vault on this iPhone.
/// Answers cite notes as links; summaries and edits use the same pipelines and
/// reviewed edits as the rest of the app. Nothing leaves the device.
struct NativeLocalChatView: View {
    @Environment(VaultStore.self) private var vault
    @ObservedObject var chat: NativeChat
    let open: (NoteDocument) -> Void
    let library: () -> Void
    let settings: () -> Void
    @State private var work: Task<Void, Never>?
    @State private var choices: [UUID: (hits: [LocalAISearchHit], instruction: String)] = [:]
    @State private var createRequest: NativeLocalAIRequest?
    @State private var history = false
    @FocusState private var focused: Bool
    @Environment(\.nativeWorkspaceChromeVisible) private var chromeVisible
    @Environment(\.nativeWorkspaceNavigationVisible) private var setNavigationVisible
    private var ai: NativeLocalAI { .shared }
    /// Room for the floating workspace navigation, which overlays content.
    private let navigationClearance: CGFloat = 76

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if chat.messages.isEmpty { emptyState }
                            ForEach(chat.messages) { message in bubble(message) }
                            if let error = chat.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(22)
                    }
                    .nativeWorkspaceScroll()
                    .scrollDismissesKeyboard(.interactively)
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .onChange(of: chat.messages.last?.content) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: chat.conversationID) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    .accessibilityIdentifier("localChat.history")
                }
                composer
            }
            .background { Accent.paper.ignoresSafeArea() }
            .toolbarBackground(Accent.paper, for: .navigationBar)
            .navigationTitle("Ask").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NativeLibraryButton(action: library) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New conversation", systemImage: "square.and.pencil") { work?.cancel(); choices = [:]; chat.clear() }
                            .disabled(chat.running || chat.messages.isEmpty).accessibilityIdentifier("localChat.new")
                        Button("Previous conversations", systemImage: "clock") { history = true }.disabled(chat.archives.isEmpty || chat.running)
                        Section { Button("On-device AI settings", systemImage: "gearshape", action: settings) }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Conversation actions")
                }
            }
            .environment(\.openURL, OpenURLAction { url in handle(url) })
            .sheet(isPresented: $history) { historySheet }
            .sheet(item: $createRequest) { request in NativeLocalAIActionView(request: request, openNote: open) }
        }
        .onDisappear { focused = false; setNavigationVisible(true) }
        // The composer sits where the navigation floats; hide it while typing.
        .onChange(of: focused) { _, value in setNavigationVisible(!value) }
    }

    // MARK: Messages

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Accent.color)
            Text("Ask your notes.").font(.system(.largeTitle, design: .serif))
            if ai.canGenerate {
                Text("Questions are answered from your notes, with links to them. Ask for a summary or a change to a note too. Everything runs on this iPhone, and conversations are saved with this vault on this device.")
                    .foregroundStyle(.secondary)
                ForEach(["What did I decide about the trip?", "Summarize my notes on the project", "Add “call the bank” to my to-do note"], id: \.self) { suggestion in
                    Button { chat.draft = suggestion; focused = true } label: {
                        HStack { Text(suggestion).multilineTextAlignment(.leading); Spacer(); Image(systemName: "arrow.up.left") }
                            .font(.subheadline).padding(14).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            } else {
                Text(ai.installed || ai.searchModelInstalled ? (ai.capabilities.limitation ?? "Preparing on-device AI…") : "Download the on-device models once to chat with your notes. Nothing is sent to a server.")
                    .foregroundStyle(.secondary)
                Button("Set up on-device AI", systemImage: "arrow.down.circle", action: settings).buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("localChat.setup")
            }
        }.padding(.top, 30)
    }

    @ViewBuilder private func bubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.role == "user" ? "YOU" : "ZERUS").font(.caption2.bold()).tracking(1.5).foregroundStyle(.secondary)
            if message.content.isEmpty {
                ProgressView(status).accessibilityIdentifier("localChat.thinking")
            } else {
                Text((try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.content))
                    .textSelection(.enabled).lineSpacing(5).tint(Accent.color).frame(maxWidth: .infinity, alignment: .leading)
                if let choice = choices[message.id] {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(choice.hits, id: \.path) { hit in
                            Button { edit(hit.path, instruction: choice.instruction) } label: { Label("Change “\(hit.title)”", systemImage: "doc.text") }
                        }
                        Button { createRequest = NativeLocalAIRequest(kind: .create, path: nil, markdown: "", content: "", selection: nil, instruction: choice.instruction, autoRun: true) } label: {
                            Label("Create a new note instead", systemImage: "square.and.pencil")
                        }
                    }.buttonStyle(.bordered).font(.subheadline)
                }
                if message.role == "assistant" {
                    HStack(spacing: 16) {
                        Button { UIPasteboard.general.string = Self.plain(message.content) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        Button { Task { _ = await vault.createNote(title: "From Zerus · " + Date().formatted(date: .abbreviated, time: .omitted), body: Self.plain(message.content), workspace: vault.workspaceID) } } label: {
                            Label("Save as note", systemImage: "square.and.pencil")
                        }
                    }.font(.caption).foregroundStyle(.secondary).disabled(chat.running)
                }
            }
        }
        .padding(message.role == "user" ? 14 : 0)
        .background(message.role == "user" ? Color.secondary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 18))
        .id(message.id)
    }

    @State private var status = "Searching your notes…"

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField(ai.canGenerate ? "Ask about your notes…" : "Set up on-device AI to ask", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...6).focused($focused).disabled(!ai.canGenerate).accessibilityIdentifier("localChat.prompt")
                if chat.running {
                    Button { work?.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title) }.accessibilityLabel("Stop")
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(!ai.canGenerate || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send message").accessibilityIdentifier("localChat.send")
                }
            }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .padding(.horizontal, 16).padding(.top, 8)
        .padding(.bottom, chromeVisible && !focused ? navigationClearance : 8)
        .animation(.easeInOut(duration: 0.2), value: chromeVisible && !focused)
    }

    private var historySheet: some View {
        NavigationStack {
            List(chat.archives) { archive in
                Button {
                    if chat.open(archive) { choices = [:]; history = false }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(archive.title).lineLimit(2)
                        Text(archive.modified, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Previous conversations").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { history = false } } }
        }
    }

    // MARK: Sending

    private func send() {
        let text = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.running, ai.canGenerate else { return }
        // Earlier answered turns give follow-ups their context.
        var previous: [String] = []
        var pendingQuestion: String?
        for message in chat.messages {
            if message.role == "user" { pendingQuestion = message.content }
            else if let question = pendingQuestion, !message.content.isEmpty {
                previous.append("Q: \(question)\nA: \(Self.plain(message.content).prefix(600))")
                pendingQuestion = nil
            }
        }
        guard let id = chat.beginAgentTurn(text) else { return }
        chat.draft = ""
        focused = false
        status = "Searching your notes…"
        work = Task {
            let outcome = await LocalAIAsk.respond(text, previous: Array(previous.suffix(2)), vault: vault) { status = $0 }
            if Task.isCancelled { chat.finishAgentTurn(id, fallback: "Stopped."); return }
            switch outcome {
            case .answer(let answer, let titles):
                var reply = answer.answer
                if answer.found, !answer.verified { reply += "\n\n_Check the cited notes: some quoted text wasn't found verbatim._" }
                if !answer.sources.isEmpty {
                    reply += "\n\nSources: " + answer.sources.map { "[\(Self.escape(titles[$0] ?? $0))](\(Self.link($0)))" }.joined(separator: " · ")
                }
                chat.updateAgentTurn(id, content: reply)
            case .summary(let text, let path, let title):
                chat.updateAgentTurn(id, content: text + "\n\nSource: [\(Self.escape(title))](\(Self.link(path)))")
            case .chooseNote(let hits, let instruction):
                let names = hits.map { "[\(Self.escape($0.title))](\(Self.link($0.path)))" }.joined(separator: " · ")
                chat.updateAgentTurn(id, content: hits.isEmpty ? "Which note should change? Open it and use ⋯ → On-device AI → Edit Note." : "Which note should change? " + names)
                choices[id] = (hits, instruction)
            case .failed(let message):
                chat.updateAgentTurn(id, content: message)
            }
            chat.finishAgentTurn(id, fallback: "No answer.")
        }
    }

    // MARK: Links

    static let scheme = "zerus-local-note"

    static func link(_ path: String) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url?.absoluteString ?? ""
    }

    static func escape(_ title: String) -> String {
        title.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
    }

    /// Message text without link targets (for copy and "Save as note").
    static func plain(_ markdown: String) -> String {
        guard let attributed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return markdown }
        return String(attributed.characters)
    }

    private func handle(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == Self.scheme,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "path" })?.value else { return .systemAction }
        guard let note = vault.notes.first(where: { $0.path == path && !$0.trashed }) else {
            chat.error = "That note is no longer in this vault."
            return .handled
        }
        open(note)
        return .handled
    }

    private func edit(_ path: String, instruction: String) {
        guard let note = vault.notes.first(where: { $0.path == path && !$0.trashed }) else { chat.error = "That note is no longer in this vault."; return }
        NativeLocalAI.shared.handOff = .init(workspaceID: vault.workspaceID, kind: .edit, instruction: instruction, path: path)
        open(note)
    }
}
