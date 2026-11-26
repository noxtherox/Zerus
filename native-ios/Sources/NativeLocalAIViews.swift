import BackgroundTasks
import SwiftUI
import ZerusLocalAI
import ZerusLocalAICore

extension VaultStore: LocalAIVaultSource {
    var localAINotes: [NoteDocument] { notes }
}

// MARK: - Settings

struct NativeLocalAISettingsView: View {
    @Environment(VaultStore.self) private var vault
    @State private var confirmDelete = false
    private var ai: NativeLocalAI { .shared }
    private var downloadSize: Int64 { ai.usefulSpecs.reduce(0) { $0 + $1.totalBytes } }
    private var ready: Bool { ai.usefulSpecs.allSatisfy { ai.states[$0.id] == .installed } }

    var body: some View {
        Form {
            Section {
                Text("Search by meaning, ask questions about your notes, summarize and edit with models that run entirely on this iPhone. Notes and questions never leave it; the models download once from Hugging Face.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let limitation = ai.capabilities.limitation {
                    Label(limitation, systemImage: ai.capabilities.semanticSearch ? "info.circle" : "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(ai.capabilities.semanticSearch ? Color.secondary : Color.orange)
                }
            }
            if ai.capabilities.semanticSearch {
                Section {
                    ForEach(ai.usefulSpecs) { spec in
                        LabeledContent {
                            state(spec)
                        } label: {
                            Text(spec.displayName)
                            Text("\(spec.role == .language ? "Ask, summaries and edits" : "Semantic search") · \(ByteCountFormatter.string(fromByteCount: spec.totalBytes, countStyle: .file))")
                        }
                    }
                    if ai.downloading {
                        Button("Cancel download", role: .cancel) { ai.cancelDownload() }
                    } else if !ready {
                        Button("Download (\(ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)))") { ai.download() }
                            .accessibilityIdentifier("localAI.download")
                    }
                    if let issue = ai.downloadIssue { Text(issue).font(.footnote).foregroundStyle(.red) }
                    Toggle("Download over cellular", isOn: Binding(get: { ai.allowExpensiveNetwork }, set: { ai.allowExpensiveNetwork = $0 }))
                } header: { Text("Models") } footer: {
                    Text("Downloads use Wi-Fi only unless cellular is allowed. Licenses: Qwen3.5 (Apache-2.0), EmbeddingGemma (Gemma Terms of Use).")
                }
                if ai.searchModelInstalled, vault.root != nil {
                    Section {
                        LabeledContent("Search index") {
                            if ai.index.running { Text("\(ai.index.indexed) of \(ai.index.total)") }
                            else { Text(ai.index.total == 0 ? "Not built yet" : "\(ai.index.indexed) of \(ai.index.total) notes") }
                        }
                        if let issue = ai.index.issue { Text(issue).font(.footnote).foregroundStyle(.red) }
                        Button("Rebuild index") { Task { await ai.rebuildIndex(vault) } }.disabled(ai.index.running)
                    } header: { Text("This vault") } footer: {
                        Text("The index stays on this iPhone and is never synced. It builds while Zerus is open, or in the background while charging. Keyword search works meanwhile.")
                    }
                }
            }
            if ai.diskUsage > 0 {
                Section {
                    Button("Delete models", role: .destructive) { confirmDelete = true }.disabled(ai.downloading)
                } footer: { Text("Uses \(ByteCountFormatter.string(fromByteCount: ai.diskUsage, countStyle: .file)). Your notes are not affected.") }
            }
        }
        .navigationTitle("On-device AI")
        .task { ai.refreshStates(); await ai.checkDevice() }
        .confirmationDialog("Delete the on-device models and search indexes?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await ai.deleteModels() } }
        }
    }

    @ViewBuilder private func state(_ spec: LocalAIModelSpec) -> some View {
        switch ai.states[spec.id] ?? .notInstalled {
        case .installed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Installed")
        case .downloading(let fraction): ProgressView(value: fraction).frame(width: 90)
        case .partial: Text("Partial").foregroundStyle(.secondary)
        case .notInstalled: Text("Not downloaded").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Actions

struct NativeLocalAIRequest: Identifiable {
    let id = UUID()
    let kind: LocalAIActionKind
    let path: String?
    let markdown: String
    let content: String
    let selection: String?
    var instruction = ""
    var autoRun = false

    /// Captures the open note's editor state when the action is chosen.
    @MainActor static func make(_ kind: LocalAIActionKind, session: NoteSession?, editor: NativeEditorActions?, instruction: String = "", autoRun: Bool = false) throws -> NativeLocalAIRequest {
        guard let session else {
            guard kind == .create else { throw VaultFailure(message: "Open a note first.") }
            return .init(kind: kind, path: nil, markdown: "", content: "", selection: nil, instruction: instruction, autoRun: autoRun)
        }
        guard let snapshot = editor?.localAISnapshot() else { throw VaultFailure(message: "Open the note and try again.") }
        if kind == .rewrite { _ = try LocalAIActions.validateRewrite(selection: snapshot.selection, in: snapshot.markdown) }
        return .init(kind: kind, path: session.document.path, markdown: snapshot.markdown, content: session.document.content,
                     selection: snapshot.selection, instruction: instruction, autoRun: autoRun)
    }
}

struct NativeLocalAIActionView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss
    let request: NativeLocalAIRequest
    var session: NoteSession?
    var editor: NativeEditorActions?
    let openNote: (NoteDocument) -> Void
    @State private var instruction = ""
    @State private var phase = Phase.input
    @State private var work: Task<Void, Never>?
    @State private var useReference = true

    enum Phase {
        case input
        case running(String)
        case summary(String, done: Bool)
        case textReview(String)
        case propertyReview([LocalAIPropertyOperation], before: [String: LocalAIPropertyValue])
        case createReview(title: String, body: String)
        case propertiesApplied(before: String, after: String)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(request.kind.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .onAppear {
            instruction = request.instruction
            if request.kind == .summarize || request.autoRun { run() }
        }
        .onDisappear { work?.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .input:
            if let selection = request.selection, request.kind == .rewrite {
                Section("Selection") { Text(selection).lineLimit(6).foregroundStyle(.secondary) }
            }
            Section {
                TextField("Instruction", text: $instruction, axis: .vertical).lineLimit(2...6).submitLabel(.go).onSubmit(run)
                    .accessibilityIdentifier("localAI.instruction")
                if request.kind == .create, request.path != nil { Toggle("Use the open note as reference", isOn: $useReference) }
            } header: { Text(request.kind.prompt) }
            if !request.kind.presets.isEmpty {
                Section("Suggestions") { ForEach(request.kind.presets, id: \.self) { preset in Button(preset) { instruction = preset; run() } } }
            }
        case .running(let message):
            Section { HStack(spacing: 12) { ProgressView(); Text(message).foregroundStyle(.secondary) } }
        case .summary(let text, let done):
            Section { Text(text.isEmpty ? "…" : text).textSelection(.enabled) } footer: { Text("Written on this iPhone from this note only.") }
            if done {
                Section {
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                    if request.path != nil {
                        Button("Add to note…", systemImage: "text.append") { phase = .textReview(LocalAIPipelines.appending("## Summary\n\n" + text, to: request.markdown)) }
                    }
                }
            }
        case .textReview(let after):
            Section { NativeLocalAIDiffView(before: request.markdown, after: after) } header: { Text("Review") } footer: {
                Text("Apply saves the change; use Undo in the editor to revert it.")
            }
        case .propertyReview(let ops, let before):
            let after = LocalAIPipelines.applying(ops, to: before)
            Section("Review") {
                ForEach(Array(Set(ops.map(\.key))).sorted(), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key).font(.headline)
                        Text(display(before[key])).strikethrough(before[key] != nil).foregroundStyle(.secondary)
                        Text(after[key].map(display) ?? "removed").foregroundStyle(after[key] == nil ? .red : .primary)
                    }
                }
            }
        case .createReview(let title, let body):
            Section("New note") {
                Text(title.isEmpty ? "Untitled" : title).font(.headline)
                Text(body).textSelection(.enabled)
            }
        case .propertiesApplied:
            Section { Label("Properties updated.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        case .failed(let message):
            Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            switch phase {
            case .propertiesApplied(let before, let after):
                Button("Undo") { undoProperties(before: before, after: after) }
            default:
                Button(isReview ? "Discard" : "Cancel") { work?.cancel(); dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch phase {
            case .input: Button("Run") { run() }.disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("localAI.run")
            case .textReview(let after): Button("Apply") { applyText(after) }.accessibilityIdentifier("localAI.apply")
            case .propertyReview(let ops, _): Button("Apply") { applyProperties(ops) }
            case .createReview(let title, let body): Button("Create") { create(title: title, body: body) }
            case .summary(_, true), .propertiesApplied: Button("Done") { dismiss() }
            case .failed: Button("Try again") { phase = .input }
            default: EmptyView()
            }
        }
    }

    private var isReview: Bool {
        switch phase {
        case .textReview, .propertyReview, .createReview: true
        default: false
        }
    }

    private func display(_ value: LocalAIPropertyValue?) -> String {
        switch value {
        case .text(let s): s
        case .list(let l): l.joined(separator: ", ")
        case nil: "—"
        }
    }

    private func run() {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard request.kind == .summarize || !text.isEmpty else { return }
        work?.cancel()
        phase = request.kind == .summarize ? .summary("", done: false) : .running("Working on this iPhone…")
        let request = request
        work = Task {
            do {
                let outcome = try await LocalAIActions.run(
                    request.kind, markdown: request.markdown, content: request.content, selection: request.selection,
                    instruction: text, reference: useReference && request.path != nil
                ) { partial in
                    Task { @MainActor in if case .summary(_, false) = phase { phase = .summary(LocalAIPipelines.stripThinking(partial), done: false) } }
                }
                try Task.checkCancellation()
                switch outcome {
                case .summary(let summary): phase = .summary(summary, done: true)
                case .text(let after): phase = .textReview(after)
                case .properties(let ops, let before): phase = .propertyReview(ops, before: before)
                case .newNote(let title, let body): phase = .createReview(title: title, body: body)
                }
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func applyText(_ after: String) {
        guard let editor, session?.document.path == request.path else { phase = .failed("The note is no longer open. Run the action again."); return }
        do { try editor.applyLocalAI(expected: request.markdown, replacement: after); dismiss() }
        catch { phase = .failed(error.localizedDescription) }
    }

    private func applyProperties(_ ops: [LocalAIPropertyOperation]) {
        guard let session, session.document.path == request.path else { phase = .failed("The note is no longer open. Run the action again."); return }
        Task {
            do {
                let before = session.document.content
                let definitions = try await vault.propertyDefinitions(notePath: session.document.path, workspace: session.document.workspaceID)
                let after = try LocalAIActions.applying(ops, to: before, definitions: definitions)
                session.updateContent(after)
                phase = .propertiesApplied(before: before, after: after)
            } catch { phase = .failed(error.localizedDescription) }
        }
    }

    private func undoProperties(before: String, after: String) {
        guard let session, session.document.content == after else {
            phase = .failed("The note changed since, so it was not undone. Use Version history to restore it.")
            return
        }
        session.updateContent(before)
        dismiss()
    }

    private func create(title: String, body: String) {
        Task {
            let folder = request.path.map { ($0 as NSString).deletingLastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? "Inbox"
            let name = title.isEmpty ? "Untitled" : title
            if let note = await vault.createNote(title: name, folder: folder, body: LocalAIActions.bodyWithoutTitle(body, title: name) + "\n", workspace: vault.workspaceID) {
                dismiss(); openNote(note)
            } else { phase = .failed(vault.error ?? "The note could not be created.") }
        }
    }
}

/// Line diff of the proposed change (added green, removed red).
struct NativeLocalAIDiffView: View {
    let before: String
    let after: String

    var body: some View {
        let lines = Self.lines(before: before, after: after)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text((line.kind == 1 ? "+ " : line.kind == -1 ? "− " : "  ") + (line.text.isEmpty ? " " : line.text))
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .background(line.kind == 1 ? Color.green.opacity(0.15) : line.kind == -1 ? Color.red.opacity(0.15) : .clear)
                    .accessibilityLabel((line.kind == 1 ? "Added: " : line.kind == -1 ? "Removed: " : "") + line.text)
            }
        }
    }

    /// Changed lines with two lines of context (LCS on the changed middle).
    static func lines(before: String, after: String) -> [(kind: Int, text: String)] {
        let a = before.components(separatedBy: "\n"), b = after.components(separatedBy: "\n")
        var prefix = 0, suffix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let left = Array(a[prefix ..< a.count - suffix]), right = Array(b[prefix ..< b.count - suffix])
        var middle: [(Int, String)] = []
        if left.count * right.count <= 40_000 {
            var table = [[Int]](repeating: [Int](repeating: 0, count: right.count + 1), count: left.count + 1)
            for i in stride(from: left.count - 1, through: 0, by: -1) {
                for j in stride(from: right.count - 1, through: 0, by: -1) {
                    table[i][j] = left[i] == right[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
            var i = 0, j = 0
            while i < left.count || j < right.count {
                if i < left.count, j < right.count, left[i] == right[j] { middle.append((0, left[i])); i += 1; j += 1 }
                else if i < left.count, j == right.count || table[i + 1][j] >= table[i][j + 1] { middle.append((-1, left[i])); i += 1 }
                else { middle.append((1, right[j])); j += 1 }
            }
        } else {
            middle = left.map { (-1, $0) } + right.map { (1, $0) }
        }
        let head = a[max(0, prefix - 2) ..< prefix].map { (0, $0) }
        let tail = a[(a.count - suffix) ..< min(a.count, a.count - suffix + 2)].map { (0, $0) }
        return (head + middle + tail).map { (kind: $0.0, text: $0.1) }
    }
}

/// The ✦ submenu in a note's actions menu.
struct NativeLocalAIMenu: View {
    let start: (LocalAIActionKind) -> Void
    private var ai: NativeLocalAI { .shared }

    var body: some View {
        if ai.canGenerate {
            Menu("On-device AI", systemImage: "sparkles") {
                ForEach([LocalAIActionKind.summarize, .rewrite, .edit, .append, .properties, .create], id: \.self) { kind in
                    Button(kind == .create ? "New note with AI" : kind.title, systemImage: kind.icon) { start(kind) }
                        .accessibilityIdentifier("localAI.action." + kind.rawValue)
                }
            }
        }
    }
}

// MARK: - Ask

struct NativeLocalAskView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss
    let question: String
    let open: (String) -> Void
    let create: (String) -> Void
    @State private var turns: [Turn] = []
    @State private var followUp = ""
    @State private var work: Task<Void, Never>?

    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var state: State = .thinking("Searching your notes…")
        enum State {
            case thinking(String)
            case done(LocalAIAskOutcome)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(turns) { turn in Section { row(turn) } header: { Text(turn.question).textCase(nil).font(.headline) } }
                if turns.count < 6, !busy {
                    Section { TextField("Ask a follow-up", text: $followUp).submitLabel(.send).onSubmit(askFollowUp) }
                }
            }
            .navigationTitle("Ask your notes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { if turns.isEmpty { start(question) } }
        .onDisappear { work?.cancel() }
    }

    private var busy: Bool { if case .thinking = turns.last?.state { true } else { false } }

    @ViewBuilder private func row(_ turn: Turn) -> some View {
        switch turn.state {
        case .thinking(let message):
            HStack(spacing: 10) { ProgressView(); Text(message).foregroundStyle(.secondary) }
        case .done(.answer(let answer, let titles)):
            Text(answer.answer).textSelection(.enabled)
            if answer.found, !answer.verified {
                Label("Check the cited notes: some quoted text wasn't found verbatim.", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            ForEach(answer.sources, id: \.self) { path in Button(titles[path] ?? path, systemImage: "doc.text") { open(path) } }
        case .done(.summary(let text, let path, let title)):
            Text(text).textSelection(.enabled)
            Button(title, systemImage: "doc.text") { open(path) }
        case .done(.chooseNote(let hits, let instruction)):
            Text("Which note should change?").foregroundStyle(.secondary)
            ForEach(hits, id: \.path) { hit in
                Button(hit.title, systemImage: "doc.text") {
                    NativeLocalAI.shared.handOff = .init(workspaceID: vault.workspaceID, kind: .edit, instruction: instruction, path: hit.path)
                    open(hit.path)
                }
            }
            Button("Create a new note instead", systemImage: "square.and.pencil") { create(instruction) }
        case .done(.failed(let message)):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    private func askFollowUp() {
        let text = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        followUp = ""
        start(text)
    }

    private func start(_ text: String) {
        let previous = turns.compactMap { turn -> String? in
            if case .done(.answer(let answer, _)) = turn.state { return "Q: \(turn.question)\nA: \(answer.answer)" }
            return nil
        }.suffix(2)
        turns.append(Turn(question: text))
        let index = turns.count - 1
        work = Task {
            let outcome = await LocalAIAsk.respond(text, previous: Array(previous), vault: vault) { message in
                if turns.indices.contains(index) { turns[index].state = .thinking(message) }
            }
            guard !Task.isCancelled, turns.indices.contains(index) else { return }
            turns[index].state = .done(outcome)
        }
    }
}

// MARK: - Lifecycle

/// Keeps the vault's index current while the app is open, builds it in the
/// background while charging, and frees the language model under memory
/// pressure or when the app leaves the foreground.
struct NativeLocalAILifecycle: ViewModifier {
    let vault: VaultStore
    @Environment(\.scenePhase) private var phase
    @State private var pending: Task<Void, Never>?
    private var ai: NativeLocalAI { .shared }

    func body(content: Content) -> some View {
        content
            .onAppear { NativeLocalAIBackground.vault = vault; schedule(delay: .seconds(3)) }
            .onChange(of: vault.notes) { schedule() }
            .onChange(of: vault.workspaceID) { schedule(delay: .seconds(1)) }
            .onChange(of: ai.searchModelInstalled) { schedule(delay: .zero) }
            .onChange(of: phase) { _, value in
                if value == .active { schedule(delay: .seconds(1)) }
                else if value == .background {
                    pending?.cancel(); ai.pauseIndexing()
                    Task { await ai.releaseMemory() }
                    if ai.searchModelInstalled, !ai.searchReady { NativeLocalAIBackground.schedule() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                Task { await ai.releaseMemory() }
            }
    }

    private func schedule(delay: Duration = .seconds(3)) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, vault.root != nil, !vault.loading else { return }
            ai.sync(vault)
        }
    }
}

/// `BGProcessingTask` that finishes the search index while charging.
enum NativeLocalAIBackground {
    static let identifier = "com.zerus.notes.localAI.index"
    @MainActor static weak var vault: VaultStore?

    /// Call once at launch, before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            Task { @MainActor in
                guard let vault, vault.root != nil, let indexing = NativeLocalAI.shared.sync(vault) else {
                    task.setTaskCompleted(success: true); return
                }
                task.expirationHandler = { Task { @MainActor in NativeLocalAI.shared.pauseIndexing() } }
                await indexing.value
                task.setTaskCompleted(success: NativeLocalAI.shared.searchReady)
            }
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }
}
