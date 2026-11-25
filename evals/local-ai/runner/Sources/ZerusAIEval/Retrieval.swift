import Foundation

// MARK: - Chunking

struct Chunk {
    let noteID: String
    let title: String
    let text: String
}

/// Split a note into heading sections, then into paragraphs packed up to
/// `maxChars`. Every chunk carries the note title for context.
func chunk(_ note: Note, maxChars: Int = 900) -> [Chunk] {
    var sections: [String] = []
    var current = ""
    for line in note.body.components(separatedBy: "\n") {
        if line.hasPrefix("#"), !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(current)
            current = ""
        }
        current += line + "\n"
    }
    if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sections.append(current) }

    var chunks: [Chunk] = []
    for section in sections {
        var buffer = ""
        for para in section.components(separatedBy: "\n\n") {
            if buffer.count + para.count > maxChars, !buffer.isEmpty {
                chunks.append(Chunk(noteID: note.id, title: note.title, text: buffer))
                buffer = ""
            }
            if para.count > maxChars {
                var start = para.startIndex
                while start < para.endIndex {
                    let end = para.index(start, offsetBy: maxChars, limitedBy: para.endIndex) ?? para.endIndex
                    chunks.append(Chunk(noteID: note.id, title: note.title, text: String(para[start ..< end])))
                    start = end
                }
            } else {
                buffer += (buffer.isEmpty ? "" : "\n\n") + para
            }
        }
        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(Chunk(noteID: note.id, title: note.title, text: buffer))
        }
    }
    if chunks.isEmpty { chunks.append(Chunk(noteID: note.id, title: note.title, text: note.title)) }
    return chunks
}

// MARK: - Lexical (BM25)

/// Lowercased, diacritic-folded word tokens; CJK runs become character bigrams.
func lexTokens(_ s: String) -> [String] {
    var tokens: [String] = []
    var word = ""
    var cjkRun: [Character] = []
    func flushWord() {
        if word.count > 1 || (word.count == 1 && word.first!.isNumber) { tokens.append(word) }
        word = ""
    }
    func flushCJK() {
        if cjkRun.count == 1 { tokens.append(String(cjkRun)) }
        if cjkRun.count > 1 {
            for i in 0 ..< cjkRun.count - 1 { tokens.append(String(cjkRun[i ... i + 1])) }
        }
        cjkRun = []
    }
    for ch in normalize(s) {
        if let u = ch.unicodeScalars.first, isCJK(u) {
            flushWord()
            cjkRun.append(ch)
        } else if ch.isLetter || ch.isNumber {
            flushCJK()
            word.append(ch)
        } else {
            flushWord()
            flushCJK()
        }
    }
    flushWord()
    flushCJK()
    return tokens
}

struct BM25 {
    let docs: [[String: Int]]
    let lengths: [Int]
    let df: [String: Int]
    let avgLen: Double

    init(_ texts: [String]) {
        var docs: [[String: Int]] = []
        var df: [String: Int] = [:]
        for t in texts {
            var tf: [String: Int] = [:]
            for tok in lexTokens(t) { tf[tok, default: 0] += 1 }
            for k in tf.keys { df[k, default: 0] += 1 }
            docs.append(tf)
        }
        self.docs = docs
        self.df = df
        self.lengths = docs.map { $0.values.reduce(0, +) }
        self.avgLen = Double(lengths.reduce(0, +)) / Double(max(1, docs.count))
    }

    func scores(_ query: String, k1: Double = 1.2, b: Double = 0.75) -> [Double] {
        let q = Set(lexTokens(query))
        let n = Double(docs.count)
        return docs.indices.map { i in
            var s = 0.0
            for term in q {
                guard let f = docs[i][term] else { continue }
                let d = Double(df[term] ?? 0)
                let idf = log(1 + (n - d + 0.5) / (d + 0.5))
                let tf = Double(f)
                s += idf * tf * (k1 + 1) / (tf + k1 * (1 - b + b * Double(lengths[i]) / avgLen))
            }
            return s
        }
    }
}

// MARK: - Ranking

/// Collapse chunk scores to note ranking (max chunk score per note).
func rankNotes(_ chunks: [Chunk], _ scores: [Double]) -> [String] {
    var best: [String: Double] = [:]
    for (c, s) in zip(chunks, scores) { best[c.noteID] = max(best[c.noteID] ?? -.infinity, s) }
    return best.sorted { $0.value > $1.value }.map(\.key)
}

func reciprocalRankFusion(_ rankings: [[String]], weights: [Double]? = nil, k: Double = 60) -> [String] {
    var score: [String: Double] = [:]
    for (n, r) in rankings.enumerated() {
        let w = weights?[n] ?? 1
        for (i, id) in r.enumerated() { score[id, default: 0] += w / (k + Double(i + 1)) }
    }
    return score.sorted { $0.value > $1.value }.map(\.key)
}

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
