import Foundation
import MLX
import ZerusLocalAI
import ZerusLocalAICore

/// Production retrieval: the app's `LocalAISearchIndex` (chunking, SQLite
/// vectors, exact-match boost) with EmbeddingGemma 300M loaded by
/// `MLXEmbedder`. Reports keyword fallback (before indexing) and semantic
/// recall, indexing speed, query latency and peak memory.
func runRetrieval(fixtures: Fixtures, extraNotes: [Note]) async throws -> JSON {
    let spec = LocalAIModelSpec.embeddingGemma300M
    let notes = (fixtures.orderedNotes + extraNotes).map { LocalAINote(path: $0.id, content: $0.raw) }
    let tasks = try fixtures.tasks("retrieval")
    let indexURL = FileManager.default.temporaryDirectory.appendingPathComponent("zerus-eval-\(UUID().uuidString).sqlite")
    defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: indexURL.path + suffix) } }

    Memory.peakMemory = 0
    let loadStart = Date()
    let embedder = try await MLXEmbedder(spec: spec, directory: try await productionDirectory(spec))
    let loadSeconds = Date().timeIntervalSince(loadStart)
    let index = try LocalAISearchIndex(url: indexURL, embeddingModelID: embedder.modelID)
    await index.setNotes(notes)
    let chunkCount = notes.reduce(0) { $0 + LocalAIChunker.chunks(for: $1).count }

    var keyword = RetrievalMetrics()
    for task in tasks {
        let hits = try await index.search(task["query"] as! String, embedder: nil, limit: 10)
        keyword.add(id: task["id"] as! String, ranking: hits.map(\.path), expected: task["expected"] as! [String])
    }
    log("keyword recall@5 \(keyword.summary["recall@5"]!)")

    _ = try await embedder.embed(Array(notes.prefix(4)).map { EmbeddingPrompt.document(title: $0.title, text: $0.content) })  // warm up kernels
    let indexStart = Date()
    try await index.update(embedder: embedder)
    let indexSeconds = Date().timeIntervalSince(indexStart)

    var semantic = RetrievalMetrics()
    var byLang: [String: RetrievalMetrics] = [:]
    let queryStart = Date()
    for task in tasks {
        let id = task["id"] as! String, expected = task["expected"] as! [String]
        let ranking = try await index.search(task["query"] as! String, embedder: embedder, limit: 10).map(\.path)
        semantic.add(id: id, ranking: ranking, expected: expected)
        byLang[task["lang"] as? String ?? "?", default: RetrievalMetrics()].add(id: id, ranking: ranking, expected: expected)
    }
    let queryMs = Date().timeIntervalSince(queryStart) / Double(max(1, tasks.count)) * 1000
    log("semantic recall@5 \(semantic.summary["recall@5"]!), \(Int(Double(chunkCount) / indexSeconds)) chunks/s, \(Int(queryMs)) ms/query")
    let report: JSON = [
        "model": spec.id, "revision": spec.revision, "notes": notes.count, "chunks": chunkCount, "queries": tasks.count,
        "keyword": keyword.summary, "semantic": semantic.summary,
        "semantic_by_lang": byLang.mapValues { $0.summary["recall@5"]! },
        "load_s": loadSeconds, "index_chunks_per_s": Double(chunkCount) / indexSeconds, "query_ms": queryMs,
        "peak_mb": Double(Memory.peakMemory) / 1_048_576,
    ]
    Memory.clearCache()
    return report
}
