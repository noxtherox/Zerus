import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import Tokenizers
import ZerusLocalAI
import ZerusLocalAICore

struct LLMSpec {
    let key: String
    let repo: String
    let note: String
    /// The production catalog entry (pinned + verified), when this is the shipped model.
    var production: LocalAIModelSpec? = nil
}

let llmSpecs: [LLMSpec] = [
    LLMSpec(key: "qwen3.5-2b", repo: "mlx-community/Qwen3.5-2B-4bit", note: "production model", production: .qwen35_2B),
    LLMSpec(key: "lfm3-1.7b", repo: "mlx-community/LFM3-1.7B-OptiQ-4bit", note: "1.73B, LFM Open License"),
    LLMSpec(key: "qwen3-1.7b", repo: "mlx-community/Qwen3-1.7B-4bit", note: "August 2026 baseline"),
    LLMSpec(key: "lfm2.5-1.2b", repo: "mlx-community/LFM2.5-1.2B-Instruct-4bit", note: "LFM Open License"),
    LLMSpec(key: "qwen3.5-0.8b", repo: "mlx-community/Qwen3.5-0.8B-4bit", note: "speed floor"),
    LLMSpec(key: "minicpm5-1b", repo: "mlx-community/MiniCPM5-1B-OptiQ-4bit", note: "Apache-2.0"),
]

// MARK: - Model folders

/// Production models live in a runner-local `LocalAIModelStore`
/// (`local/models`, gitignored) exactly as in the app: pinned revision,
/// every file checksum-verified. The store is seeded from the Hugging Face
/// cache when the pinned snapshot is there (APFS clones), otherwise
/// downloaded with the app's `LocalAIModelDownloader`.
func productionDirectory(_ spec: LocalAIModelSpec, storeRoot: URL? = nil) async throws -> URL {
    let store = LocalAIModelStore(root: storeRoot ?? evalModelStoreRoot)
    if store.state(of: spec) != .installed {
        let snapshot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache/huggingface/hub/models--\(spec.repository.replacingOccurrences(of: "/", with: "--"))/snapshots/\(spec.revision)")
        let target = store.directory(for: spec)
        if FileManager.default.fileExists(atPath: snapshot.path) {
            log("seeding \(spec.id) from the Hugging Face cache")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for file in spec.files {
                let destination = target.appendingPathComponent(file.path)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: snapshot.appendingPathComponent(file.path).resolvingSymlinksInPath(), to: destination)
            }
            try store.verifyAndMarkInstalled(spec)
        } else {
            log("downloading \(spec.id) (\(spec.totalBytes / 1_000_000) MB)")
            final class Decile: @unchecked Sendable { var value = -1 }
            let last = Decile()
            try await LocalAIModelDownloader(store: store, policy: .anyNetwork).install(spec) { p in
                let decile = Int(p.fraction * 10)
                if decile != last.value { last.value = decile; log("  \(decile * 10)%") }
            }
        }
    }
    return store.directory(for: spec)
}

nonisolated(unsafe) var evalModelStoreRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("local/models")

/// Other candidates (comparisons only) come from the Hugging Face cache.
func candidateDirectory(_ repo: String) async throws -> URL {
    try await #hubDownloader().download(
        id: repo, revision: nil, matching: ["*.safetensors", "*.json", "*.jinja"], useLatest: false,
        progressHandler: { _ in })
}

// MARK: - Stats

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

/// The production `MLXLanguageModel` plus per-run statistics. Pipelines take
/// it as their `LocalAILanguageModel`.
final class LLM: LocalAILanguageModel, @unchecked Sendable {
    let spec: LLMSpec
    let model: MLXLanguageModel
    private let lock = NSLock()
    private var _stats = GenStats()
    var stats: GenStats { lock.withLock { _stats } }
    var loadSeconds: Double { model.loadSeconds }
    var pipelines: LocalAIPipelines { LocalAIPipelines(model: self) }

    init(_ spec: LLMSpec) async throws {
        self.spec = spec
        let directory: URL
        if let production = spec.production { directory = try await productionDirectory(production) }
        else { directory = try await candidateDirectory(spec.repo) }
        model = try await MLXLanguageModel(modelID: spec.key, directory: directory)
    }

    func generateJSON(system: String, user: String, schema: String, maxTokens: Int) async throws -> String {
        do {
            let out = try await model.generateJSON(system: system, user: user, schema: schema, maxTokens: maxTokens)
            record()
            return out
        } catch {
            lock.withLock { _stats.calls += 1; _stats.failures += 1 }
            log("  generation error: \(error)")
            throw error
        }
    }

    func generateText(system: String, user: String, maxTokens: Int, onText: (@Sendable (String) -> Void)?) async throws -> String {
        let out = try await model.generateText(system: system, user: user, maxTokens: maxTokens, onText: onText)
        record()
        return out
    }

    private func record() {
        let s = model.lastStats
        lock.withLock {
            _stats.calls += 1
            _stats.promptTokens += s.promptTokens
            _stats.outputTokens += s.outputTokens
            _stats.ttft.append(s.timeToFirstToken)
            if s.outputTokens > 4 { _stats.decodeTPS.append(s.tokensPerSecond) }
        }
    }
}
