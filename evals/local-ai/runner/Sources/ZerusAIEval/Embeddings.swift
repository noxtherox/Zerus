import Foundation
import HuggingFace
import MLX
import MLXEmbedders
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

struct EmbedderSpec {
    let key: String
    let repo: String
    let query: (String) -> String
    let document: (Chunk) -> String
}

let embedderSpecs: [EmbedderSpec] = [
    EmbedderSpec(
        key: "embeddinggemma-2", repo: "mlx-community/embeddinggemma-2-4bit",
        query: { "task: search result | query: \($0)" },
        document: { "title: \($0.title) | text: \($0.text)" }),
    EmbedderSpec(
        key: "embeddinggemma-300m", repo: "mlx-community/embeddinggemma-300m-4bit",
        query: { "task: search result | query: \($0)" },
        document: { "title: \($0.title) | text: \($0.text)" }),
    EmbedderSpec(
        key: "qwen3-embedding-0.6b", repo: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
        query: {
            "Instruct: Given a search query, retrieve the personal notes that answer it\nQuery:\($0)"
        },
        document: { "\($0.title)\n\($0.text)" }),
    EmbedderSpec(
        key: "lfm2.5-embedding-350m", repo: "mlx-community/LFM2.5-Embedding-350M-4bit",
        query: { "query: \($0)" },
        document: { "document: \($0.title)\n\($0.text)" }),
    EmbedderSpec(
        key: "multilingual-e5-small", repo: "intfloat/multilingual-e5-small",
        query: { "query: \($0)" },
        document: { "passage: \($0.title)\n\($0.text)" }),
]

final class Embedder {
    let spec: EmbedderSpec
    let container: EmbedderModelContainer
    let loadSeconds: Double

    init(_ spec: EmbedderSpec) async throws {
        self.spec = spec
        let t = Date()
        container = try await EmbedderModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: spec.repo))
        loadSeconds = Date().timeIntervalSince(t)
    }

    /// L2-normalized embeddings, batched, inputs truncated to `maxTokens`.
    func embed(_ texts: [String], batch: Int = 8, maxTokens: Int = 512) async throws -> [[Float]] {
        var out: [[Float]] = []
        for start in stride(from: 0, to: texts.count, by: batch) {
            let slice = Array(texts[start ..< min(texts.count, start + batch)])
            let vectors = try await container.perform { context -> [[Float]] in
                let inputs = slice.map {
                    Array(context.tokenizer.encode(text: $0, addSpecialTokens: true).prefix(maxTokens))
                }
                let maxLength = inputs.map(\.count).max() ?? 1
                let pad = context.tokenizer.eosTokenId ?? 0
                let padded = stacked(inputs.map { MLXArray($0 + Array(repeating: pad, count: maxLength - $0.count)) })
                let mask = stacked(inputs.map {
                    MLXArray(Array(repeating: true, count: $0.count) + Array(repeating: false, count: maxLength - $0.count))
                })
                let output = context.model(
                    padded, positionIds: nil, tokenTypeIds: MLXArray.zeros(like: padded),
                    attentionMask: mask)
                let pooled = context.pooling(output, mask: mask, normalize: true)
                try withError { pooled.eval() }
                return pooled.map { $0.asArray(Float.self) }
            }
            out.append(contentsOf: vectors)
        }
        return out
    }
}

func dot(_ a: [Float], _ b: [Float]) -> Double {
    var s: Float = 0
    for i in 0 ..< min(a.count, b.count) { s += a[i] * b[i] }
    return Double(s)
}

/// BM25 weights tried in weighted reciprocal rank fusion (vector weight is 1).
let fusionWeights: [Double] = [1.0, 0.5, 0.25]

func runRetrieval(fixtures: Fixtures, embedderKeys: [String], extraNotes: [Note]) async throws -> JSON {
    let chunks = (fixtures.orderedNotes + extraNotes).flatMap { chunk($0) }
    let tasks = try fixtures.tasks("retrieval")
    let bm25 = BM25(chunks.map { "\($0.title)\n\($0.text)" })

    var lexical = RetrievalMetrics()
    var lexicalRankings: [String: [String]] = [:]
    for task in tasks {
        let id = task["id"] as! String
        let ranking = rankNotes(chunks, bm25.scores(task["query"] as! String))
        lexicalRankings[id] = ranking
        lexical.add(id: id, ranking: ranking, expected: task["expected"] as! [String])
    }
    var report: JSON = ["chunks": chunks.count, "queries": tasks.count, "bm25": lexical.summary]
    log("bm25 recall@5 \(lexical.summary["recall@5"]!)")

    for key in embedderKeys {
        guard let spec = embedderSpecs.first(where: { $0.key == key }) else {
            log("unknown embedder \(key)")
            continue
        }
        Memory.peakMemory = 0
        let embedder = try await Embedder(spec)
        _ = try await embedder.embed(Array(chunks.prefix(16)).map(spec.document))  // warm up kernels
        let t0 = Date()
        let docVectors = try await embedder.embed(chunks.map(spec.document))
        let indexSeconds = Date().timeIntervalSince(t0)
        var vector = RetrievalMetrics()
        var fused: [Double: RetrievalMetrics] = [:]
        var byLang: [String: RetrievalMetrics] = [:]
        let t1 = Date()
        let queryVectors = try await embedder.embed(tasks.map { spec.query($0["query"] as! String) })
        let querySeconds = Date().timeIntervalSince(t1) / Double(max(1, tasks.count))
        for (task, qv) in zip(tasks, queryVectors) {
            let id = task["id"] as! String
            let expected = task["expected"] as! [String]
            let ranking = rankNotes(chunks, docVectors.map { dot($0, qv) })
            vector.add(id: id, ranking: ranking, expected: expected)
            for w in fusionWeights {
                fused[w, default: RetrievalMetrics()].add(
                    id: id, ranking: reciprocalRankFusion([ranking, lexicalRankings[id]!], weights: [1, w]),
                    expected: expected)
            }
            byLang[task["lang"] as? String ?? "?", default: RetrievalMetrics()]
                .add(id: id, ranking: ranking, expected: expected)
        }
        report[key] = [
            "repo": spec.repo,
            "vector": vector.summary,
            "hybrid": Dictionary(uniqueKeysWithValues: fused.map { ("bm25_w\($0.key)", $0.value.summary) }),
            "vector_by_lang": byLang.mapValues { $0.summary["recall@5"]! },
            "load_s": embedder.loadSeconds,
            "index_chunks_per_s": Double(chunks.count) / indexSeconds,
            "query_ms": querySeconds * 1000,
            "peak_mb": Double(Memory.peakMemory) / 1_048_576,
        ] as JSON
        log("\(key): vector \(vector.summary["recall@5"]!) " + fusionWeights.map {
            "w\($0)=\(fused[$0]!.summary["recall@5"]!)" }.joined(separator: " "))
        Memory.clearCache()
    }
    return report
}
