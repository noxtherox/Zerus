import Foundation
import Observation
import ZerusLocalAI
import ZerusLocalAICore

// On-device AI shared by the native iOS and macOS apps (docs/local-ai-plan.md):
// model downloads, the per-vault search index, semantic search, the action
// runner and the Ask engine. Each app supplies only its UI. Everything runs
// locally; the only network use is the opt-in model download.

/// What the AI layer needs from an open vault.
@MainActor protocol LocalAIVaultSource: AnyObject {
    var root: URL? { get }
    /// Every note of the vault, trashed ones included (they are filtered out).
    var localAINotes: [NoteDocument] { get }
}

@MainActor @Observable final class NativeLocalAI {
    static let shared = NativeLocalAI()

    enum ModelState: Equatable {
        case notInstalled
        case partial
        case downloading(Double)
        case installed
    }

    struct IndexProgress: Equatable {
        var indexed = 0
        var total = 0
        var running = false
        var issue: String?
    }

    /// An edit or new-note request from Ask, picked up by its window or note screen.
    struct HandOff: Equatable {
        let id = UUID()
        let workspaceID: UUID
        let kind: LocalAIActionKind
        let instruction: String
        let path: String?
    }

    private(set) var states: [String: ModelState] = [:]
    private(set) var downloadIssue: String?
    private(set) var capabilities = LocalAICapabilities(semanticSearch: false, languageModel: false, limitation: nil)
    private(set) var index = IndexProgress()
    private(set) var diskUsage: Int64 = 0
    var handOff: HandOff?
    /// Off by default: downloads wait for Wi-Fi or Ethernet.
    var allowExpensiveNetwork = UserDefaults.standard.bool(forKey: "zerus.localAI.allowExpensiveNetwork") {
        didSet { UserDefaults.standard.set(allowExpensiveNetwork, forKey: "zerus.localAI.allowExpensiveNetwork") }
    }

    private let store: LocalAIModelStore?
    private let runtime: LocalAIRuntime?
    private let indexDirectory: URL?
    private var downloadTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var indexes: [String: LocalAISearchIndex] = [:]
    private var idleUnload: Task<Void, Never>?

    private convenience init() {
        self.init(store: try? LocalAIModelStore.standard(), indexDirectory: nil)
    }

    /// Tests use a temporary model store and index folder.
    init(store: LocalAIModelStore?, indexDirectory: URL?) {
        self.store = store
        self.indexDirectory = indexDirectory
        runtime = store.map { LocalAIRuntime(store: $0) }
        refreshStates()
        Task { await refreshCapabilities() }
    }

    // MARK: Status

    var specs: [LocalAIModelSpec] { LocalAIModelSpec.all }
    var installed: Bool { specs.allSatisfy { states[$0.id] == .installed } }
    /// The embedding model alone (enough for semantic search on 4 GB iPhones).
    var searchModelInstalled: Bool { states[LocalAIModelSpec.embeddingGemma300M.id] == .installed }
    var downloading: Bool { downloadTask != nil }
    /// Semantic search is ready for the current vault.
    var searchReady: Bool { searchModelInstalled && capabilities.semanticSearch && index.total > 0 && index.indexed >= index.total }
    /// Ask, summaries and edits can run.
    var canGenerate: Bool { installed && capabilities.languageModel }
    /// Models this device can use (no language model below 6 GB).
    var usefulSpecs: [LocalAIModelSpec] {
        ProcessInfo.processInfo.physicalMemory >= LocalAIRuntime.languageModelMinimumMemory ? specs : [.embeddingGemma300M]
    }

    func refreshStates() {
        guard let store else { return }
        for spec in specs {
            if case .downloading = states[spec.id] { continue }
            switch store.state(of: spec) {
            case .installed: states[spec.id] = .installed
            case .partial: states[spec.id] = .partial
            case .notInstalled: states[spec.id] = .notInstalled
            }
        }
        diskUsage = store.diskUsage()
    }

    func refreshCapabilities() async {
        guard let runtime else { return }
        if searchModelInstalled { await runtime.ensureSelfTest() }
        capabilities = await runtime.capabilities()
    }

    /// Runs the MLX self-test now (before offering a download on iPhone).
    func checkDevice() async {
        guard let runtime else { return }
        await runtime.ensureSelfTest()
        capabilities = await runtime.capabilities()
    }

    // MARK: Downloads

    func download() {
        guard downloadTask == nil, let store else { return }
        downloadIssue = nil
        let policy: LocalAIModelDownloader.NetworkPolicy = allowExpensiveNetwork ? .anyNetwork : .wifiOnly
        let wanted = usefulSpecs
        downloadTask = Task { [weak self] in
            let downloader = LocalAIModelDownloader(store: store, policy: policy)
            do {
                for spec in wanted where store.state(of: spec) != .installed {
                    self?.states[spec.id] = .downloading(0)
                    try await downloader.install(spec) { progress in
                        Task { @MainActor in self?.states[spec.id] = .downloading(progress.fraction) }
                    }
                    self?.states[spec.id] = .installed
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .notConnectedToInternet || error.networkUnavailableReason != nil {
                self?.downloadIssue = "No Wi-Fi connection. Connect to Wi-Fi, or allow downloads on other networks."
            } catch {
                self?.downloadIssue = error.localizedDescription
            }
            self?.downloadTask = nil
            self?.refreshStates()
            await self?.refreshCapabilities()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Removes the models and every vault index on this device.
    func deleteModels() async {
        cancelDownload()
        indexTask?.cancel()
        await runtime?.unloadAll()
        for index in indexes.values { try? await index.reset() }
        indexes = [:]
        try? store?.deleteAll()
        if let directory = indexDirectory ?? (try? LocalAISearchIndex.standardURL(vaultKey: "x").deletingLastPathComponent()) {
            try? FileManager.default.removeItem(at: directory)
        }
        index = IndexProgress()
        refreshStates()
        await refreshCapabilities()
    }

    /// Frees the language model (memory warnings, background).
    func releaseMemory() async {
        idleUnload?.cancel()
        await runtime?.unloadLanguageModel()
    }

    // MARK: Index

    private func vaultKey(_ root: URL) -> String {
        NativeHistory.hash(root.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    private func searchIndex(for root: URL) throws -> LocalAISearchIndex {
        let key = vaultKey(root)
        if let existing = indexes[key] { return existing }
        let url = try indexDirectory.map { $0.appendingPathComponent(key + ".sqlite") } ?? LocalAISearchIndex.standardURL(vaultKey: key)
        let created = try LocalAISearchIndex(url: url, embeddingModelID: LocalAIModelSpec.embeddingGemma300M.id)
        indexes[key] = created
        return created
    }

    /// Hands the vault's notes to its index and embeds what changed.
    /// Called (debounced) whenever the vault's notes change.
    @discardableResult
    func sync(_ vault: LocalAIVaultSource) -> Task<Void, Never>? {
        guard let root = vault.root else { return nil }
        let notes = vault.localAINotes.filter { !$0.trashed }.map { LocalAINote(path: $0.path, content: $0.content) }
        indexTask?.cancel()
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let index = try self.searchIndex(for: root)
                await index.setNotes(notes)
                let status = await index.status()
                self.index = IndexProgress(indexed: status.indexedNotes, total: status.notes, running: false)
                guard self.searchModelInstalled, let runtime = self.runtime else { return }
                await self.refreshCapabilities()
                guard self.capabilities.semanticSearch, !status.isComplete else { return }
                self.index.running = true
                let embedder = try await runtime.embedder()
                try await index.update(embedder: embedder) { done, total in
                    Task { @MainActor in self.index.indexed = status.notes - total + done }
                }
                let final = await index.status()
                self.index = IndexProgress(indexed: final.indexedNotes, total: final.notes, running: false)
            } catch is CancellationError {
                self.index.running = false
            } catch {
                self.index.running = false
                self.index.issue = error.localizedDescription
            }
        }
        indexTask = task
        return task
    }

    /// Stops indexing (app leaving the foreground); written work is kept.
    func pauseIndexing() { indexTask?.cancel() }

    /// Waits for the current indexing pass (tests, background tasks).
    func waitForIndex() async { await indexTask?.value }

    func rebuildIndex(_ vault: LocalAIVaultSource) async {
        guard let root = vault.root, let index = try? searchIndex(for: root) else { return }
        indexTask?.cancel()
        try? await index.reset()
        sync(vault)
    }

    // MARK: Search and pipelines

    /// Semantic hits for search; empty unless the index is ready.
    func search(_ query: String, in vault: LocalAIVaultSource, limit: Int = 5) async -> [LocalAISearchHit] {
        guard searchReady, let root = vault.root, let runtime, let index = try? searchIndex(for: root) else { return [] }
        do {
            let embedder = try await runtime.embedder()
            return try await index.search(query, embedder: embedder, limit: limit)
        } catch { return [] }
    }

    /// Notes for Ask: best hits with their most relevant passages.
    func askSources(for query: String, in vault: LocalAIVaultSource, notes: Int = 4, passages: Int = 3) async throws -> [LocalAIAskSource] {
        guard let root = vault.root, let runtime else { return [] }
        let index = try searchIndex(for: root)
        let embedder: LocalAIEmbedding? = searchReady ? try await runtime.embedder() : nil
        let hits = try await index.search(query, embedder: embedder, limit: notes)
        var ids = Set<String>()
        var sources: [LocalAIAskSource] = []
        let notesByPath = Dictionary(vault.localAINotes.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        for hit in hits {
            // Properties always go along (tags, status, dates…), then the best passages.
            let properties = notesByPath[hit.path].map { LocalAINote(path: $0.path, content: $0.content).properties } ?? ""
            let parts = try await index.passages(of: hit.path, for: query, embedder: embedder, limit: passages + 1)
                .filter { !$0.hasPrefix("Properties:\n") }.prefix(passages)
            var id = Self.slug(hit.title)
            var n = 2
            while !ids.insert(id).inserted { id = Self.slug(hit.title) + "-\(n)"; n += 1 }
            let header = "# \(hit.title)\n\n" + (properties.isEmpty ? "" : "Properties:\n\(properties)\n\n")
            sources.append(LocalAIAskSource(id: id, path: hit.path, content: header + parts.joined(separator: "\n…\n")))
        }
        return sources
    }

    /// The top notes for a request (edit target confirmation).
    func candidates(for query: String, in vault: LocalAIVaultSource, limit: Int = 3) async -> [LocalAISearchHit] {
        guard let root = vault.root, let runtime, let index = try? searchIndex(for: root) else { return [] }
        let embedder: LocalAIEmbedding? = searchReady ? try? await runtime.embedder() : nil
        return (try? await index.search(query, embedder: embedder, limit: limit)) ?? []
    }

    func pipelines() async throws -> LocalAIPipelines {
        guard let runtime else { throw LocalAIRuntime.Failure.unsupportedDevice("On-device AI storage is unavailable.") }
        guard installed else { throw LocalAIRuntime.Failure.notInstalled(.qwen35_2B) }
        let model = try await runtime.languageModel()
        scheduleIdleUnload()
        return LocalAIPipelines(model: model)
    }

    /// Frees the language model's memory after idle minutes.
    private func scheduleIdleUnload() {
        idleUnload?.cancel()
        #if os(iOS)
        let idle: Duration = .seconds(120)
        #else
        let idle: Duration = .seconds(300)
        #endif
        idleUnload = Task { [runtime] in
            try? await Task.sleep(for: idle)
            guard !Task.isCancelled else { return }
            await runtime?.unloadLanguageModel()
        }
    }

    static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let words = folded.split { !$0.isLetter && !$0.isNumber }.prefix(4)
        return words.isEmpty ? "note" : words.joined(separator: "-")
    }
}

// MARK: - Actions on one note

enum LocalAIActionKind: String, Equatable, Sendable {
    case summarize, rewrite, append, edit, properties, create

    var title: String {
        switch self {
        case .summarize: "Summarize Note"
        case .rewrite: "Rewrite Selection"
        case .append: "Add to Note"
        case .edit: "Edit Note"
        case .properties: "Change Properties"
        case .create: "New Note"
        }
    }
    var prompt: String {
        switch self {
        case .rewrite: "How should the selection change?"
        case .append: "What should be added at the end?"
        case .edit: "What should change in this note?"
        case .properties: "Which properties should change?"
        case .create: "What should the new note contain?"
        case .summarize: ""
        }
    }
    var presets: [String] {
        switch self {
        case .rewrite: ["Fix spelling and grammar", "Make it shorter", "Make it clearer", "Turn into a bulleted list", "Translate to English"]
        case .append: ["Add a short summary", "Add a list of action items"]
        case .edit: ["Mark completed tasks as done", "Fix spelling and grammar"]
        case .properties: ["Add a tag for the main topic"]
        case .create, .summarize: []
        }
    }
    var icon: String {
        switch self {
        case .summarize: "text.alignleft"
        case .rewrite: "pencil.and.scribble"
        case .append: "text.append"
        case .edit: "wand.and.stars"
        case .properties: "tag"
        case .create: "square.and.pencil"
        }
    }
}

/// A proposal the user reviews before anything is written.
enum LocalAIActionOutcome {
    case summary(String)
    /// The note's new Markdown (editor body).
    case text(String)
    case properties([LocalAIPropertyOperation], before: [String: LocalAIPropertyValue])
    case newNote(title: String, body: String)
}

enum LocalAIActions {
    /// Checks a rewrite request before running the model.
    static func validateRewrite(selection: String?, in markdown: String) throws -> String {
        guard let selection, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VaultFailure(message: "Select the text to rewrite first.")
        }
        guard markdown.components(separatedBy: selection).count == 2 else {
            throw VaultFailure(message: "The selection appears more than once or spans formatting the rewrite can't place. Select a passage within one section.")
        }
        return selection
    }

    /// Runs one action. `markdown` is the editor's text (body), `content` the
    /// whole note including frontmatter.
    @MainActor static func run(
        _ kind: LocalAIActionKind, markdown: String, content: String, selection: String?, instruction: String,
        reference: Bool, onSummary: (@Sendable (String) -> Void)? = nil
    ) async throws -> LocalAIActionOutcome {
        let pipelines = try await NativeLocalAI.shared.pipelines()
        switch kind {
        case .summarize:
            return .summary(try await pipelines.summarize(markdown, onText: onSummary))
        case .rewrite:
            let selection = try validateRewrite(selection: selection, in: markdown)
            var rewritten = try await pipelines.rewrite(selection: selection, in: content, instruction: instruction)
            if selection.hasSuffix("\n"), !rewritten.hasSuffix("\n") { rewritten += "\n" }
            return .text(markdown.replacingOccurrences(of: selection, with: rewritten))
        case .append:
            let addition = try await pipelines.append(to: content, instruction: instruction)
            return .text(LocalAIPipelines.appending(addition, to: markdown))
        case .edit:
            return .text(try await pipelines.edit(markdown, instruction: instruction).result)
        case .properties:
            let before = properties(content)
            let ops = try await pipelines.properties(before, instruction: instruction).filter { !$0.key.lowercased().hasPrefix("zerus-") }
            guard !ops.isEmpty else { throw LocalAIPipelineError.invalidOutput }
            return .properties(ops, before: before)
        case .create:
            let created = try await pipelines.create(instruction: instruction, reference: reference && !content.isEmpty ? content : nil)
            return .newNote(title: created.title, body: created.body)
        }
    }

    /// User-visible properties (Zerus-managed keys are hidden from the model).
    static func properties(_ content: String) -> [String: LocalAIPropertyValue] {
        var out: [String: LocalAIPropertyValue] = [:]
        for entry in NativeFrontmatter(content).entries where !entry.key.lowercased().hasPrefix("zerus-") {
            switch entry.value {
            case .list(let values): out[entry.key] = .list(values)
            case .some(let value): out[entry.key] = .text(value.display)
            case nil: break
            }
        }
        return out
    }

    /// `content` with the operations written into its frontmatter, typed by
    /// the vault's property definitions.
    static func applying(_ ops: [LocalAIPropertyOperation], to content: String, definitions: [NativePropertyDefinition]) throws -> String {
        let updated = LocalAIPipelines.applying(ops, to: properties(content))
        var text = content
        for key in Set(ops.map(\.key)) {
            let definition = definitions.first { $0.name.caseInsensitiveCompare(key) == .orderedSame }
            if definition?.type == .relation { throw VaultFailure(message: "Relations need their dedicated editor; \(key) was left unchanged.") }
            var value: NativePropertyValue?
            switch updated[key] {
            case nil: value = nil
            case .list(let list): value = .list(list)
            case .text(let s):
                switch definition?.type {
                case .checkbox?: value = .checkbox(["true", "yes", "1"].contains(s.lowercased()))
                case .number?: value = .number(s)
                default: value = definition?.type == .list ? .list([s]) : .text(s)
                }
            }
            if let value, let definition { try definition.validateValue(value) }
            text = try NativeFrontmatter(text).setting(key, value: value)
        }
        return text
    }

    /// A new note's body without a repeated "# Title" heading.
    static func bodyWithoutTitle(_ body: String, title: String) -> String {
        var text = body.trimmingCharacters(in: .newlines)
        if let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
           first.hasPrefix("# "), first.dropFirst(2).trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(title) == .orderedSame {
            text = String(text.dropFirst(first.count)).trimmingCharacters(in: .newlines)
        }
        return text
    }
}

// MARK: - Ask

/// One answer in an Ask conversation.
enum LocalAIAskOutcome {
    case answer(LocalAIAnswer, titles: [String: String])
    case summary(String, path: String, title: String)
    /// Edit requests: the user picks the note (top 3) or a new note.
    case chooseNote([LocalAISearchHit], instruction: String)
    case failed(String)
}

enum LocalAIAsk {
    /// Routes and answers `text`; `previous` holds earlier "Q/A" pairs
    /// (follow-ups skip the router and stay questions).
    @MainActor static func respond(_ text: String, previous: [String], vault: LocalAIVaultSource, progress: @MainActor (String) -> Void) async -> LocalAIAskOutcome {
        let ai = NativeLocalAI.shared
        do {
            let pipelines = try await ai.pipelines()
            let intent = previous.isEmpty ? try await pipelines.route(text) : .ask
            switch intent {
            case .edit:
                return .chooseNote(await ai.candidates(for: text, in: vault), instruction: text)
            case .summarize:
                guard let hit = await ai.candidates(for: text, in: vault, limit: 1).first,
                      let note = vault.localAINotes.first(where: { $0.path == hit.path }) else { return .failed("No matching note to summarize.") }
                progress("Summarizing \(hit.title)…")
                let summary = try await pipelines.summarize(note.parts.body, language: LocalAILanguage.detect(text))
                return .summary(summary, path: hit.path, title: hit.title)
            case .ask:
                let retrieval = ([text] + previous.map { String($0.prefix(300)) }).joined(separator: "\n")
                let sources = try await ai.askSources(for: retrieval, in: vault)
                guard !sources.isEmpty else { return .failed("No notes to answer from yet.") }
                progress("Reading \(sources.count) notes…")
                let question = previous.isEmpty ? text : "Earlier in this conversation:\n\(previous.joined(separator: "\n"))\n\nQuestion: \(text)"
                let answer = try await pipelines.ask(question, sources: sources, language: LocalAILanguage.detect(text))
                let notes = vault.localAINotes
                let titles = Dictionary(uniqueKeysWithValues: sources.map { source in (source.path, notes.first { $0.path == source.path }?.title ?? source.id) })
                return .answer(answer, titles: titles)
            }
        } catch is CancellationError {
            return .failed("Cancelled.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
