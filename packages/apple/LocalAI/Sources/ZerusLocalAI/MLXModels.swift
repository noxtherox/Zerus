import Foundation
import MLX
import MLXEmbedders
import MLXGuidedGeneration
import MLXLLM
import MLXLMCommon
import Tokenizers
import ZerusLocalAICore

// MARK: - Tokenizer (local folder only; no Hub client)

/// Loads `tokenizer.json` from a downloaded model folder with
/// swift-transformers. Equivalent to `#huggingFaceTokenizerLoader()` without
/// the macro (no macro trust prompts in the app projects) and without the Hub
/// client, so it cannot reach the network.
struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer
    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] { upstream.encode(text: text, addSpecialTokens: addSpecialTokens) }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

// MARK: - Language model

/// Generation statistics for the last call (evals and diagnostics).
public struct LocalAIGenerationStats: Sendable {
    public var promptTokens = 0
    public var outputTokens = 0
    public var timeToFirstToken: TimeInterval = 0
    public var tokensPerSecond: Double = 0
}

/// Qwen3.5-2B (or another chat model) loaded from a verified local folder.
/// Calls are serialised by the model container. Greedy decoding with a mild
/// repetition penalty; thinking disabled.
public final class MLXLanguageModel: LocalAILanguageModel, @unchecked Sendable {
    public let modelID: String
    public let loadSeconds: TimeInterval
    private let container: ModelContainer
    private let grammar = GrammarCache()
    private let statsLock = NSLock()
    private var _lastStats = LocalAIGenerationStats()
    public var lastStats: LocalAIGenerationStats { statsLock.withLock { _lastStats } }

    public convenience init(spec: LocalAIModelSpec, directory: URL) async throws {
        try await self.init(modelID: spec.id, directory: directory)
    }

    /// Any MLX chat model folder (evals compare other candidates this way).
    public init(modelID: String, directory: URL) async throws {
        self.modelID = modelID
        let start = Date()
        container = try await LLMModelFactory.shared.loadContainer(from: directory, using: LocalTokenizerLoader())
        loadSeconds = Date().timeIntervalSince(start)
    }

    private func input(system: String, user: String) -> UserInput {
        UserInput(chat: [.system(system), .user(user)], additionalContext: ["enable_thinking": false])
    }

    public func generateText(system: String, user: String, maxTokens: Int, onText: (@Sendable (String) -> Void)?) async throws -> String {
        let input = input(system: system, user: user)
        let (text, stats) = try await container.perform { context -> (String, LocalAIGenerationStats) in
            let prepared = try await context.processor.prepare(input: input)
            var parameters = GenerateParameters()
            parameters.maxTokens = maxTokens
            parameters.temperature = 0
            parameters.repetitionPenalty = 1.05
            let start = Date()
            var stats = LocalAIGenerationStats()
            var text = ""
            for await item in try generate(input: prepared, parameters: parameters, context: context) {
                if Task.isCancelled { break }
                switch item {
                case .chunk(let piece):
                    if text.isEmpty { stats.timeToFirstToken = Date().timeIntervalSince(start) }
                    text += piece
                    onText?(text)
                case .info(let info):
                    stats.promptTokens = info.promptTokenCount
                    stats.outputTokens = info.generationTokenCount
                    stats.tokensPerSecond = info.tokensPerSecond
                default: break
                }
            }
            return (text, stats)
        }
        try Task.checkCancellation()
        statsLock.withLock { _lastStats = stats }
        return LocalAIPipelines.stripThinking(text)
    }

    public func generateJSON(system: String, user: String, schema: String, maxTokens: Int) async throws -> String {
        let input = input(system: system, user: user)
        let cache = grammar
        let (text, stats) = try await container.perform { context -> (String, LocalAIGenerationStats) in
            let prepared = try await context.processor.prepare(input: input)
            let tokenizer = try cache.tokenizer(for: context.tokenizer)
            let constraint = try GrammarConstraint(
                tokenizer: tokenizer.grammar, jsonSchema: schema, fastForward: true, hostTokenizer: context.tokenizer)
            let start = Date()
            var stats = LocalAIGenerationStats()
            var text = ""
            let produced = try GuidedGenerationLoop.run(
                input: prepared, context: context, constraint: constraint, maxTokens: maxTokens,
                vocabSize: tokenizer.vocabSize,
                logitProcessor: GenerateParameters(repetitionPenalty: 1.05, repetitionContextSize: 64).processor()
            ) { delta in
                if text.isEmpty { stats.timeToFirstToken = Date().timeIntervalSince(start) }
                text += delta
                return !Task.isCancelled
            }
            let elapsed = Date().timeIntervalSince(start)
            stats.promptTokens = prepared.text.tokens.size
            stats.outputTokens = produced
            stats.tokensPerSecond = Double(produced) / max(0.001, elapsed - stats.timeToFirstToken)
            return (text, stats)
        }
        try Task.checkCancellation()
        statsLock.withLock { _lastStats = stats }
        return text
    }
}

/// The grammar tokenizer is built once per model (xgrammar caches schemas).
private final class GrammarCache: @unchecked Sendable {
    struct Entry { let grammar: GrammarTokenizer; let vocabSize: Int }
    private let lock = NSLock()
    private var entry: Entry?

    func tokenizer(for host: any MLXLMCommon.Tokenizer) throws -> Entry {
        try lock.withLock {
            if let entry { return entry }
            let vocab = TokenizerVocabExtractor.extractForGrammar(from: host)
            let made = Entry(
                grammar: try GrammarTokenizer(vocab: vocab.vocab, vocabType: vocab.vocabType, eosTokenId: Int32(host.eosTokenId ?? 0)),
                vocabSize: vocab.vocab.count)
            entry = made
            return made
        }
    }
}

// MARK: - Embedder

/// EmbeddingGemma loaded from a verified local folder; L2-normalised outputs.
public final class MLXEmbedder: LocalAIEmbedding, @unchecked Sendable {
    public let modelID: String
    private let container: EmbedderModelContainer
    private let batchSize: Int
    private let maxTokens: Int

    public init(spec: LocalAIModelSpec, directory: URL, batchSize: Int = 8, maxTokens: Int = 512) async throws {
        modelID = spec.id
        self.batchSize = batchSize
        self.maxTokens = maxTokens
        container = try await EmbedderModelFactory.shared.loadContainer(from: directory, using: LocalTokenizerLoader())
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        var out: [[Float]] = []
        out.reserveCapacity(texts.count)
        let limit = maxTokens
        for start in stride(from: 0, to: texts.count, by: batchSize) {
            try Task.checkCancellation()
            let slice = Array(texts[start ..< min(texts.count, start + batchSize)])
            let vectors = try await container.perform { context -> [[Float]] in
                let inputs = slice.map { Array(context.tokenizer.encode(text: $0, addSpecialTokens: true).prefix(limit)) }
                let length = inputs.map(\.count).max() ?? 1
                let pad = context.tokenizer.eosTokenId ?? 0
                let padded = stacked(inputs.map { MLXArray($0 + Array(repeating: pad, count: length - $0.count)) })
                let mask = stacked(inputs.map {
                    MLXArray(Array(repeating: true, count: $0.count) + Array(repeating: false, count: length - $0.count))
                })
                let output = context.model(padded, positionIds: nil, tokenTypeIds: MLXArray.zeros(like: padded), attentionMask: mask)
                let pooled = context.pooling(output, mask: mask, normalize: true)
                try withError { pooled.eval() }
                return pooled.map { $0.asArray(Float.self) }
            }
            out.append(contentsOf: vectors)
        }
        return out
    }
}
