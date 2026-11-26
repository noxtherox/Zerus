import SwiftUI
import ZerusLocalAI
import ZerusLocalAICore

// MARK: - Settings

struct MacLocalAISettingsPane: View {
    var workspace: MacWorkspace?
    @State private var confirmDelete = false
    private var ai: MacLocalAI { .shared }

    var body: some View {
        Form {
            Section {
                Text("Search by meaning, ask questions about your notes, summarize and edit with a model that runs entirely on this Mac. Notes and questions never leave it; the models download once from Hugging Face.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let limitation = ai.capabilities.limitation, ai.installed {
                    Label(limitation, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            Section("Models") {
                ForEach(ai.specs) { spec in
                    LabeledContent {
                        state(spec)
                    } label: {
                        Text(spec.displayName)
                        Text("\(spec.role == .language ? "Ask, summaries and edits" : "Semantic search") · \(ByteCountFormatter.string(fromByteCount: spec.totalBytes, countStyle: .file)) · \(spec.license)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    if ai.downloading {
                        Button("Cancel Download") { ai.cancelDownload() }
                    } else if !ai.installed {
                        Button("Download Models (\(ByteCountFormatter.string(fromByteCount: ai.specs.reduce(0) { $0 + $1.totalBytes }, countStyle: .file)))") { ai.download() }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    if ai.diskUsage > 0 {
                        Button("Delete Models…", role: .destructive) { confirmDelete = true }.disabled(ai.downloading)
                    }
                }
                if let issue = ai.downloadIssue { Text(issue).font(.caption).foregroundStyle(.red) }
                Toggle(isOn: Binding(get: { ai.allowExpensiveNetwork }, set: { ai.allowExpensiveNetwork = $0 })) {
                    Text("Download on any network")
                    Text("Off: downloads only over Wi-Fi or Ethernet, not over personal hotspot or Low Data Mode.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let workspace, workspace.root != nil, ai.installed {
                Section("This vault") {
                    LabeledContent("Search index") {
                        if ai.index.running { HStack { ProgressView().controlSize(.small); Text("\(ai.index.indexed) of \(ai.index.total) notes") } }
                        else { Text(ai.index.total == 0 ? "Not built yet" : "\(ai.index.indexed) of \(ai.index.total) notes") }
                    }
                    if let issue = ai.index.issue { Text(issue).font(.caption).foregroundStyle(.red) }
                    Button("Rebuild Index") { Task { await ai.rebuildIndex(workspace) } }.disabled(ai.index.running)
                    Text("The index is stored only on this Mac (Application Support) and is never synced. Keyword search works while it builds.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { ai.refreshStates() }
        .confirmationDialog("Delete the on-device models and search indexes?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await ai.deleteModels() } }
        } message: { Text("Your notes are not affected. You can download the models again later.") }
    }

    @ViewBuilder private func state(_ spec: LocalAIModelSpec) -> some View {
        switch ai.states[spec.id] ?? .notInstalled {
        case .installed: Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .downloading(let fraction): ProgressView(value: fraction).frame(width: 140)
        case .partial: Text("Partly downloaded").foregroundStyle(.secondary)
        case .notInstalled: Text("Not downloaded").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Actions on the open note

/// One on-device AI action on the open note. Captured when the menu item is
/// chosen, so the review compares against exactly what was there.
struct MacLocalAIRequest: Identifiable {
    typealias Kind = LocalAIActionKind

    let id = UUID()
    let kind: Kind
    let workspaceID: UUID
    let path: String?
    /// Editor Markdown (note body) when the request was made.
    let markdown: String
    /// Full note text including frontmatter (context and properties).
    let content: String
    let selection: String?
    var instruction = ""
    /// Run immediately (instruction already given, e.g. from Ask).
    var autoRun = false

    @MainActor static func make(_ kind: Kind, store: MacWorkspace, instruction: String = "", autoRun: Bool = false) throws -> MacLocalAIRequest {
        guard let note = store.current else {
            if kind == .create { return .init(kind: kind, workspaceID: store.workspaceID, path: nil, markdown: "", content: "", selection: nil, instruction: instruction, autoRun: autoRun) }
            throw VaultFailure(message: "Open a note first.")
        }
        let snapshot = try MacLocalAIEditorRequest.perform(scope: store.workspaceID, path: note.path, kind: .read)
        if kind == .rewrite { _ = try LocalAIActions.validateRewrite(selection: snapshot.selection, in: snapshot.markdown) }
        return .init(kind: kind, workspaceID: store.workspaceID, path: note.path, markdown: snapshot.markdown, content: note.content,
                     selection: snapshot.selection, instruction: instruction, autoRun: autoRun)
    }
}

struct MacLocalAIActionView: View {
    let store: MacWorkspace
    let initial: MacLocalAIRequest
    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var phase = Phase.input
    @State private var work: Task<Void, Never>?
    @State private var useReference = true

    enum Phase {
        case input
        case running(String)
        case summary(String, done: Bool)
        case textReview(after: String)
        case propertyReview([LocalAIPropertyOperation], before: [String: LocalAIPropertyValue])
        case createReview(title: String, body: String)
        case propertiesApplied(before: String, after: String)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(initial.kind.title, systemImage: "sparkles").font(.title3.bold())
                Spacer()
                Text("On this Mac").font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding(20)
        .frame(width: 640)
        .frame(minHeight: 260, maxHeight: 640)
        .onAppear {
            instruction = initial.instruction
            if initial.kind == .summarize || initial.autoRun { run() }
        }
        .onDisappear { work?.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .input:
            if let selection = initial.selection, initial.kind == .rewrite {
                Text(selection).lineLimit(4).font(.callout).foregroundStyle(.secondary).padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            Text(initial.kind.prompt).font(.headline)
            TextField("Instruction", text: $instruction, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder).onSubmit(run)
            if !initial.kind.presets.isEmpty {
                HStack { ForEach(initial.kind.presets, id: \.self) { preset in Button(preset) { instruction = preset; run() }.controlSize(.small) } }
            }
            if initial.kind == .create, initial.path != nil { Toggle("Use the open note as reference", isOn: $useReference) }
            footer { Button("Cancel") { dismiss() }; Button("Run") { run() }.keyboardShortcut(.defaultAction).disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty) }
        case .running(let message):
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text(message).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, minHeight: 120)
            footer { Button("Cancel") { work?.cancel(); dismiss() } }
        case .summary(let text, let done):
            ScrollView { Text(text.isEmpty ? " " : text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(minHeight: 120, maxHeight: 360)
            footer {
                Button("Done") { dismiss() }
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }.disabled(!done)
                Button("Add to Note…") { phase = .textReview(after: LocalAIPipelines.appending("## Summary\n\n" + text, to: initial.markdown)) }.disabled(!done || initial.path == nil)
            }
        case .textReview(let after):
            Text("Review the change. Apply saves it to the note; Edit ▸ Undo reverts it.").font(.caption).foregroundStyle(.secondary)
            MacHistoryDifferenceView(before: initial.markdown, after: after).frame(minHeight: 220, maxHeight: 440)
            footer { Button("Discard") { dismiss() }; Button("Try Again") { run() }; Button("Apply") { applyText(after) }.keyboardShortcut(.defaultAction) }
        case .propertyReview(let ops, let before):
            let after = LocalAIPipelines.applying(ops, to: before)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(Set(ops.map(\.key))).sorted(), id: \.self) { key in
                    HStack(alignment: .firstTextBaseline) {
                        Text(key).bold().frame(width: 120, alignment: .leading)
                        Text(display(before[key])).strikethrough(before[key] != nil).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(after[key].map(display) ?? "removed").foregroundStyle(after[key] == nil ? .red : .primary)
                    }
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            footer { Button("Discard") { dismiss() }; Button("Try Again") { run() }; Button("Apply") { applyProperties(ops, before: before) }.keyboardShortcut(.defaultAction) }
        case .createReview(let title, let body):
            Text(title.isEmpty ? "Untitled" : title).font(.headline)
            ScrollView { Text(body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(minHeight: 120, maxHeight: 360)
            footer { Button("Discard") { dismiss() }; Button("Try Again") { run() }; Button("Create Note") { create(title: title, body: body) }.keyboardShortcut(.defaultAction) }
        case .propertiesApplied(let before, let after):
            Label("Properties updated.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            footer {
                Button("Undo") { Task { if await store.revertLocalAIWrite(before: before, after: after) { dismiss() } } }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            footer { Button("Close") { dismiss() }; Button("Try Again") { phase = .input } }
        }
    }

    private func footer<Buttons: View>(@ViewBuilder _ buttons: () -> Buttons) -> some View {
        HStack { Spacer(); buttons() }
    }

    private func display(_ value: LocalAIPropertyValue?) -> String {
        switch value {
        case .text(let s): s
        case .list(let l): l.joined(separator: ", ")
        case nil: "—"
        }
    }

    // MARK: Run

    private func run() {
        let request = initial, text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard request.kind == .summarize || !text.isEmpty else { return }
        work?.cancel()
        phase = .running(request.kind == .summarize ? "Summarizing…" : "Thinking…")
        if request.kind == .summarize { phase = .summary("", done: false) }
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
                case .text(let after): phase = .textReview(after: after)
                case .properties(let ops, let before): phase = .propertyReview(ops, before: before)
                case .newNote(let title, let body): phase = .createReview(title: title, body: body)
                }
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    static func properties(_ content: String) -> [String: LocalAIPropertyValue] { LocalAIActions.properties(content) }

    // MARK: Apply

    private func applyText(_ after: String) {
        guard let path = initial.path, store.workspaceID == initial.workspaceID, store.current?.path == path else {
            phase = .failed("The note is no longer open. Run the action again.")
            return
        }
        do {
            try MacLocalAIEditorRequest.perform(scope: initial.workspaceID, path: path, kind: .replace(expected: initial.markdown, replacement: after, actionName: "AI Edit"))
            dismiss()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func applyProperties(_ ops: [LocalAIPropertyOperation], before: [String: LocalAIPropertyValue]) {
        Task {
            do {
                let written = try await store.applyLocalAIProperties(ops, expectedPath: initial.path, workspaceID: initial.workspaceID)
                phase = .propertiesApplied(before: written.before, after: written.after)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func create(title: String, body: String) {
        Task {
            let folder = initial.path.map { ($0 as NSString).deletingLastPathComponent }
            if await store.createLocalAINote(title: title.isEmpty ? "Untitled" : title, body: body, folder: folder) { dismiss() }
            else { phase = .failed(store.issue ?? "The note could not be created.") }
        }
    }
}

// MARK: - Workspace writes

extension MacWorkspace {
    /// Applies property operations to the open note in one write. Returns the
    /// text before and after for Undo.
    func applyLocalAIProperties(_ ops: [LocalAIPropertyOperation], expectedPath: String?, workspaceID origin: UUID) async throws -> (before: String, after: String) {
        guard origin == workspaceID, await save(), let note = current, note.path == expectedPath, let io else {
            throw VaultFailure(message: "The note changed. Run the action again.")
        }
        let text = try LocalAIActions.applying(ops, to: note.content, definitions: (try? schema?.effective(notePath: note.path)) ?? [])
        try await io.write(note.path, data: Data(text.utf8), expected: Data(note.content.utf8))
        apply(try await io.scan()); await reloadCurrent()
        return (note.content, text)
    }

    /// Restores the open note's text written by `applyLocalAIProperties`.
    func revertLocalAIWrite(before: String, after: String) async -> Bool {
        guard await save(), let note = current, let io, Data(note.content.utf8) == Data(after.utf8) else {
            issue = "The note changed since the AI change, so it was not undone. Use Version History to restore it."
            return false
        }
        do {
            try await io.write(note.path, data: Data(before.utf8), expected: Data(after.utf8))
            apply(try await io.scan()); await reloadCurrent()
            return true
        } catch { issue = error.localizedDescription; return false }
    }

    /// Creates and opens a note with the AI-written body.
    func createLocalAINote(title: String, body: String, folder: String?) async -> Bool {
        guard let path = await createNote(title: title, folder: folder), let note = current, note.path == path, let io else { return false }
        // The template already has the "# Title" heading.
        let text = LocalAIActions.bodyWithoutTitle(body, title: note.title)
        let content = note.content.trimmingCharacters(in: .newlines) + "\n\n" + text + "\n"
        do {
            try await io.write(path, data: Data(content.utf8), expected: Data(note.content.utf8))
            apply(try await io.scan()); await reloadCurrent()
            return true
        } catch { issue = error.localizedDescription; return false }
    }
}

// MARK: - Ask

/// "Ask" from global search: answers from the notes with citations, a few
/// follow-ups, nothing persisted. Edit requests ask which note to change.
struct MacLocalAskView: View {
    let workspace: MacWorkspace
    let question: String
    /// Opens a note (closes search).
    let open: (String) -> Void
    /// Hands an edit or new-note request to the workspace window.
    let handOff: (MacLocalAIRequest.Kind, String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [Turn] = []
    @State private var followUp = ""
    @State private var work: Task<Void, Never>?

    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var state: State = .thinking("Searching your notes…")
        enum State {
            case thinking(String)
            case answer(LocalAIAnswer, titles: [String: String])
            case summary(String, path: String, title: String)
            case chooseNote([LocalAISearchHit], instruction: String)
            case failed(String)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ask your notes", systemImage: "sparkles").font(.title3.bold())
                Spacer()
                Text("Answers come only from your notes, on this Mac").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { ForEach(turns) { turn in view(turn) } }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 200, maxHeight: 460)
            HStack {
                TextField("Ask a follow-up", text: $followUp).textFieldStyle(.roundedBorder).onSubmit(askFollowUp)
                    .disabled(busy || turns.count >= 6)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 640)
        .onAppear { if turns.isEmpty { start(question) } }
        .onDisappear { work?.cancel() }
    }

    private var busy: Bool { if case .thinking = turns.last?.state { true } else { false } }

    @ViewBuilder private func view(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.question).font(.headline)
            switch turn.state {
            case .thinking(let message):
                HStack { ProgressView().controlSize(.small); Text(message).foregroundStyle(.secondary) }
            case .answer(let answer, let titles):
                Text(answer.answer).textSelection(.enabled)
                if answer.found, !answer.verified {
                    Label("Check the cited notes: some quoted text wasn't found verbatim.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                if !answer.sources.isEmpty {
                    HStack { ForEach(answer.sources, id: \.self) { path in Button(titles[path] ?? path) { open(path) }.controlSize(.small) } }
                }
            case .summary(let text, let path, let title):
                Text(text).textSelection(.enabled)
                Button(title) { open(path) }.controlSize(.small)
            case .chooseNote(let hits, let instruction):
                Text("Which note should change?").foregroundStyle(.secondary)
                ForEach(hits, id: \.path) { hit in
                    Button { handOff(.edit, instruction, hit.path) } label: { Label(hit.title, systemImage: "doc.text") }
                }
                Button { handOff(.create, instruction, nil) } label: { Label("Create a new note instead", systemImage: "square.and.pencil") }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
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
            if case .answer(let answer, _) = turn.state { return "Q: \(turn.question)\nA: \(answer.answer)" }
            return nil
        }.suffix(2)
        turns.append(Turn(question: text))
        let index = turns.count - 1
        work = Task {
            let outcome = await LocalAIAsk.respond(text, previous: Array(previous), vault: workspace) { message in
                if turns.indices.contains(index) { turns[index].state = .thinking(message) }
            }
            guard !Task.isCancelled, turns.indices.contains(index) else { return }
            switch outcome {
            case .answer(let answer, let titles): turns[index].state = .answer(answer, titles: titles)
            case .summary(let text, let path, let title): turns[index].state = .summary(text, path: path, title: title)
            case .chooseNote(let hits, let instruction): turns[index].state = .chooseNote(hits, instruction: instruction)
            case .failed(let message): turns[index].state = .failed(message)
            }
        }
    }
}

// MARK: - Workspace hooks

/// Toolbar menu with the on-device AI actions for the open note.
struct MacLocalAIMenu: View {
    let store: MacWorkspace
    @Binding var settings: Bool
    private var ai: MacLocalAI { .shared }

    var body: some View {
        Menu {
            if ai.canGenerate {
                Section {
                    Button("Ask Your Notes…", systemImage: "magnifyingglass") { store.showSearch = true }
                }
                if store.current != nil {
                    Section {
                        item(.summarize, "text.alignleft")
                        item(.rewrite, "pencil.and.scribble")
                        item(.edit, "wand.and.stars")
                        item(.append, "text.append")
                        item(.properties, "tag")
                    }
                }
                Section { item(.create, "square.and.pencil") }
            } else {
                Text(ai.installed ? (ai.capabilities.limitation ?? "Preparing on-device AI…") : "On-device AI isn't set up.")
            }
            Section { Button("On-device AI Settings…", systemImage: "gearshape") { settings = true } }
        } label: {
            Image(systemName: "sparkles")
        }
        .menuIndicator(.hidden)
        .disabled(store.root == nil || store.busy)
        .help("On-device AI")
        .accessibilityLabel("On-device AI")
    }

    private func item(_ kind: MacLocalAIRequest.Kind, _ icon: String) -> some View {
        Button(kind == .create ? "New Note with AI…" : kind.title + (kind == .summarize ? "" : "…"), systemImage: icon) {
            do { MacLocalAIPresentation.shared.requests[store.workspaceID] = try MacLocalAIRequest.make(kind, store: store) }
            catch { store.issue = error.localizedDescription }
        }
    }
}

/// Presents AI action sheets for this window, picks up edits handed over
/// from Ask, and keeps the vault's search index current.
struct MacLocalAIWorkspace: ViewModifier {
    let store: MacWorkspace
    private var ai: MacLocalAI { .shared }

    func body(content: Content) -> some View {
        content
            .modifier(MacLocalAIIndexing(store: store))
            .macSheet(item: Binding(get: { MacLocalAIPresentation.shared.requests[store.workspaceID] }, set: { MacLocalAIPresentation.shared.requests[store.workspaceID] = $0 })) { request in
                MacLocalAIActionView(store: store, initial: request)
            }
            .onChange(of: ai.handOff) { _, handOff in
                guard let handOff, handOff.workspaceID == store.workspaceID else { return }
                ai.handOff = nil
                Task { await pickUp(handOff) }
            }
    }

    private func pickUp(_ handOff: MacLocalAI.HandOff) async {
        if let path = handOff.path {
            await store.openNote(path)
            // The editor loads asynchronously; wait briefly for it to answer.
            for _ in 0 ..< 30 {
                if store.current?.path == path,
                   (try? MacLocalAIEditorRequest.perform(scope: store.workspaceID, path: path, kind: .read)) != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        do { MacLocalAIPresentation.shared.requests[store.workspaceID] = try MacLocalAIRequest.make(handOff.kind, store: store, instruction: handOff.instruction, autoRun: true) }
        catch { store.issue = error.localizedDescription }
    }
}
