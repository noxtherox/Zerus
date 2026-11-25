import Foundation

// Chunking, BM25 and ranking now live in packages/apple/LocalAI
// (ZerusLocalAICore); this file keeps the metrics.

struct RetrievalMetrics {
    var hits5 = 0
    var hits1 = 0
    var mrr = 0.0
    var total = 0
    var failures: [String] = []

    mutating func add(id: String, ranking: [String], expected: [String]) {
        total += 1
        let top5 = Set(ranking.prefix(5))
        if expected.allSatisfy(top5.contains) { hits5 += 1 } else { failures.append(id) }
        if let first = ranking.first, expected.contains(first) { hits1 += 1 }
        if let r = ranking.firstIndex(where: expected.contains) { mrr += 1 / Double(r + 1) }
    }

    var summary: JSON {
        [
            "recall@5": Double(hits5) / Double(max(1, total)),
            "top1": Double(hits1) / Double(max(1, total)),
            "mrr": mrr / Double(max(1, total)),
            "n": total, "failures": failures,
        ]
    }
}
