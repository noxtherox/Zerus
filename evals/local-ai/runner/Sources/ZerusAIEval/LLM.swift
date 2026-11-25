import Foundation
import HuggingFace
import MLX
import MLXGuidedGeneration
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

struct LLMSpec {
    let key: String
    let repo: String
    let note: String
}

let llmSpecs: [LLMSpec] = [
    LLMSpec(key: "qwen3.5-2b", repo: "mlx-community/Qwen3.5-2B-4bit", note: "2.27B incl. vision tower"),
    LLMSpec(key: "lfm3-1.7b", repo: "mlx-community/LFM3-1.7B-OptiQ-4bit", note: "1.73B, LFM Open License"),
    LLMSpec(key: "qwen3-1.7b", repo: "mlx-community/Qwen3-1.7B-4bit", note: "August 2026 baseline"),
    LLMSpec(key: "lfm2.5-1.2b", repo: "mlx-community/LFM2.5-1.2B-Instruct-4bit", note: "LFM Open License"),
    LLMSpec(key: "qwen3.5-0.8b", repo: "mlx-community/Qwen3.5-0.8B-4bit", note: "speed floor"),
    LLMSpec(key: "minicpm5-1b", repo: "mlx-community/MiniCPM5-1B-OptiQ-4bit", note: "Apache-2.0"),
]

struct GenStats {
    var calls = 0
    var promptTokens = 0
    var outputTokens = 0
    var ttft: [Double] = []
    var decodeTPS: [Double] = []
    var failures = 0

    var summary: JSON {
        func median(_ a: [Double]) -> Double {
            guard !a.isEmpty else { return 0 }
            let s = a.sorted()
            return s[s.count / 2]
        }
        return [
            "calls": calls, "prompt_tokens": promptTokens, "output_tokens": outputTokens,
            "ttft_median_s": median(ttft), "ttft_max_s": ttft.max() ?? 0,
            "decode_tps_median": median(decodeTPS), "generation_errors": failures,
        ]
    }
}

final class LLM {
    let spec: LLMSpec
    let container: ModelContainer
    let loadSeconds: Double
    var stats = GenStats()
    private let grammar = GrammarBox()

    init(_ spec: LLMSpec) async throws {
        self.spec = spec
        let t = Date()
        container = try await #huggingFaceLoadModelContainer(
            configuration: ModelConfiguration(id: spec.repo))
        loadSeconds = Date().timeIntervalSince(t)
    }

    private func userInput(system: String, user: String) -> UserInput {
        UserInput(
            chat: [.system(system), .user(user)],
            additionalContext: ["enable_thinking": false])
    }

    /// Unconstrained greedy generation.
    func text(system: String, user: String, maxTokens: Int = 400) async throws -> String {
        let input = userInput(system: system, user: user)
        let (out, ttft, prompt, produced, tps) = try await container.perform {
            context -> (String, Double, Int, Int, Double) in
            let lmInput = try await context.processor.prepare(input: input)
            var params = GenerateParameters()
            params.maxTokens = maxTokens
            params.temperature = 0
            params.repetitionPenalty = 1.05
            let start = Date()
            var first: Double?
            var text = ""
            var prompt = 0
            var produced = 0
            var tps = 0.0
            for await item in try generate(input: lmInput, parameters: params, context: context) {
                switch item {
                case .chunk(let s):
                    if first == nil { first = Date().timeIntervalSince(start) }
                    text += s
                case .info(let info):
                    prompt = info.promptTokenCount
                    produced = info.generationTokenCount
                    tps = info.tokensPerSecond
                default: break
                }
            }
            return (text, first ?? Date().timeIntervalSince(start), prompt, produced, tps)
        }
        record(ttft: ttft, prompt: prompt, produced: produced, tps: tps)
        return stripThinking(out)
    }

    /// Grammar-constrained JSON generation. Returns the parsed object or nil.
    func json(system: String, user: String, schema: String, maxTokens: Int = 600) async -> JSON? {
        let input = userInput(system: system, user: user)
        let box = grammar
        do {
            let (out, ttft, prompt, produced, elapsed) = try await container.perform {
                context -> (String, Double, Int, Int, Double) in
                let lmInput = try await context.processor.prepare(input: input)
                if box.tokenizer == nil {
                    let vocab = TokenizerVocabExtractor.extractForGrammar(from: context.tokenizer)
                    box.tokenizer = try GrammarTokenizer(
                        vocab: vocab.vocab, vocabType: vocab.vocabType,
                        eosTokenId: Int32(context.tokenizer.eosTokenId ?? 0))
                    box.vocabSize = vocab.vocab.count
                }
                let grammarTokenizer = box.tokenizer!
                let constraint = try GrammarConstraint(
                    tokenizer: grammarTokenizer, jsonSchema: schema, fastForward: true,
                    hostTokenizer: context.tokenizer)
                let start = Date()
                var first: Double?
                var text = ""
                let produced = try GuidedGenerationLoop.run(
                    input: lmInput, context: context, constraint: constraint,
                    maxTokens: maxTokens, vocabSize: box.vocabSize,
                    logitProcessor: GenerateParameters(repetitionPenalty: 1.05, repetitionContextSize: 64).processor()
                ) { delta in
                    if first == nil { first = Date().timeIntervalSince(start) }
                    text += delta
                    return true
                }
                let elapsed = Date().timeIntervalSince(start)
                return (text, first ?? elapsed, lmInput.text.tokens.size, produced, elapsed)
            }
            let decode = max(0.001, elapsed - ttft)
            record(ttft: ttft, prompt: prompt, produced: produced, tps: Double(produced) / decode)
            return try JSONSerialization.jsonObject(with: Data(out.utf8)) as? JSON
        } catch {
            stats.calls += 1
            stats.failures += 1
            log("  json generation error: \(error)")
            return nil
        }
    }

    private func record(ttft: Double, prompt: Int, produced: Int, tps: Double) {
        stats.calls += 1
        stats.promptTokens += prompt
        stats.outputTokens += produced
        stats.ttft.append(ttft)
        if produced > 4 { stats.decodeTPS.append(tps) }
    }
}

func stripThinking(_ s: String) -> String {
    var out = s
    while let open = out.range(of: "<think>"),
        let close = out.range(of: "</think>", range: open.upperBound ..< out.endIndex)
    {
        out.removeSubrange(open.lowerBound ..< close.upperBound)
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Per-model grammar tokenizer cache (built once; xgrammar caches compiled schemas).
final class GrammarBox: @unchecked Sendable {
    var tokenizer: GrammarTokenizer?
    var vocabSize = 0
}
