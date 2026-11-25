import Accelerate
import Foundation

/// Produces L2-normalised embeddings (the MLX embedder in `ZerusLocalAI`, or a
/// fake in tests).
public protocol LocalAIEmbedding: Sendable {
    var modelID: String { get }
    func embed(_ texts: [String]) async throws -> [[Float]]
}

public struct LocalAISearchHit: Sendable, Hashable {
    public let path: String
    public let title: String
    public let score: Double
    /// The best-matching passage, for snippets and Ask context.
    public let passage: String
    /// True when every quoted phrase / distinctive code in the query occurs in the note.
    public let exactMatch: Bool
}

public struct LocalAIIndexStatus: Sendable, Equatable {
    public let notes: Int
    public let indexedNotes: Int
    public var isComplete: Bool { indexedNotes >= notes }
}

/// The per-device search index for one vault: chunk embeddings in SQLite
/// (Application Support, never synced), incremental by content hash.
///
/// Ranking: embeddings when every note is indexed (rank fusion with BM25
/// lowered recall in phase 1), BM25 while the index builds or without an
/// embedder. Either way, notes containing every quoted phrase or distinctive
/// code/number of the query move to the top.
public actor LocalAISearchIndex {
    private let database: SQLiteDatabase
    private let embeddingModelID: String

    /// Current corpus (all notes, indexed or not).
    private var chunks: [LocalAIChunk] = []
    private var notes: [String: LocalAINote] = [:]
    private var normalizedContent: [String: String] = [:]
    private var bm25: LocalAIBM25?

    /// Indexed vectors, row-major, aligned with `vectorChunks`.
    private var vectorChunks: [LocalAIChunk] = []
    private var matrix: [Float] = []
    private var dimension = 0
    private var vectorsLoaded = false
    private var indexedHashes: [String: String] = [:]

    public init(url: URL, embeddingModelID: String) throws {
        database = try SQLiteDatabase(url: url)
        self.embeddingModelID = embeddingModelID
        try database.execute("""
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS notes(path TEXT PRIMARY KEY, hash TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS chunks(
              path TEXT NOT NULL REFERENCES notes(path) ON DELETE CASCADE,
              ordinal INTEGER NOT NULL, title TEXT NOT NULL, text TEXT NOT NULL, vector BLOB NOT NULL,
              PRIMARY KEY(path, ordinal));
            """)
        var stored: String?
        try database.prepare("SELECT value FROM meta WHERE key = 'embedding_model'").bind([]).rows { stored = $0.string(0) }
        if stored != embeddingModelID {
            // A different embedding model: vectors are incompatible; start over.
            try database.transaction {
                try database.execute("DELETE FROM chunks; DELETE FROM notes;")
                try database.prepare("INSERT OR REPLACE INTO meta(key, value) VALUES('embedding_model', ?)").bind([embeddingModelID]).run()
            }
        }
        try database.prepare("SELECT path, hash FROM notes").bind([]).rows { indexedHashes[$0.string(0)] = $0.string(1) }
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// `Application Support/Zerus/LocalAI/Index/<vaultKey>.sqlite`.
    public static func standardURL(vaultKey: String) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let safe = vaultKey.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return support.appendingPathComponent("Zerus/LocalAI/Index/\(safe).sqlite")
    }

    // MARK: Corpus

    /// Replaces the corpus with the vault's current notes. Cheap (no
    /// embedding); keyword search works immediately afterwards.
    public func setNotes(_ current: [LocalAINote]) {
        notes = Dictionary(current.map { ($0.path, $0) }, uniquingKeysWith: { _, new in new })
        normalizedContent = notes.mapValues { LocalAIText.normalize($0.content) }
        chunks = notes.values.sorted { $0.path < $1.path }.flatMap { LocalAIChunker.chunks(for: $0) }
        bm25 = nil
    }

    public func status() -> LocalAIIndexStatus {
        LocalAIIndexStatus(
            notes: notes.count,
            indexedNotes: notes.values.filter { indexedHashes[$0.path] == $0.contentHash }.count)
    }

    /// Embeds new or changed notes and drops deleted ones. Cancellable; work
    /// already written survives cancellation. `progress(done, total)` counts notes.
    public func update(
        embedder: LocalAIEmbedding, batchSize: Int = 16,
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws {
        precondition(embedder.modelID == embeddingModelID, "embedder does not match the index")
        let removed = Set(indexedHashes.keys).subtracting(notes.keys)
        if !removed.isEmpty {
            try database.transaction {
                let delete = try database.prepare("DELETE FROM notes WHERE path = ?")
                for path in removed { try delete.bind([path]).run() }
            }
            removed.forEach { indexedHashes.removeValue(forKey: $0) }
            vectorsLoaded = false
        }
        let stale = notes.values.filter { indexedHashes[$0.path] != $0.contentHash }.sorted { $0.path < $1.path }
        var done = 0
        progress(done, stale.count)
        for start in stride(from: 0, to: stale.count, by: batchSize) {
            try Task.checkCancellation()
            let batch = Array(stale[start ..< min(stale.count, start + batchSize)])
            let batchChunks = batch.map { LocalAIChunker.chunks(for: $0) }
            let vectors = try await embedder.embed(batchChunks.flatMap { $0.map(\.embeddingText) })
            try Task.checkCancellation()
            var offset = 0
            try database.transaction {
                let upsertNote = try database.prepare("INSERT OR REPLACE INTO notes(path, hash) VALUES(?, ?)")
                let deleteChunks = try database.prepare("DELETE FROM chunks WHERE path = ?")
                let insertChunk = try database.prepare("INSERT INTO chunks(path, ordinal, title, text, vector) VALUES(?, ?, ?, ?, ?)")
                for (note, noteChunks) in zip(batch, batchChunks) {
                    try deleteChunks.bind([note.path]).run()
                    try upsertNote.bind([note.path, note.contentHash]).run()
                    for chunk in noteChunks {
                        let vector = vectors[offset].withUnsafeBufferPointer { Data(buffer: $0) }
                        offset += 1
                        try insertChunk.bind([chunk.path, chunk.ordinal, chunk.title, chunk.text, vector]).run()
                    }
                }
            }
            for note in batch { indexedHashes[note.path] = note.contentHash }
            vectorsLoaded = false
            done += batch.count
            progress(done, stale.count)
        }
    }

    /// Removes every stored vector (Settings → Delete models / rebuild).
    public func reset() throws {
        try database.transaction { try database.execute("DELETE FROM chunks; DELETE FROM notes;") }
        indexedHashes = [:]
        vectorsLoaded = false
    }

    // MARK: Search

    public func search(_ query: String, embedder: LocalAIEmbedding?, limit: Int = 10) async throws -> [LocalAISearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chunks.isEmpty else { return [] }
        var best: [String: (score: Double, chunk: LocalAIChunk)] = [:]
        if let embedder, status().isComplete {
            try loadVectors()
            let queryVector = try await embedder.embed([EmbeddingPrompt.query(trimmed)])[0]
            let scores = similarity(queryVector)
            for (chunk, score) in zip(vectorChunks, scores) where notes[chunk.path] != nil {
                if Double(score) > best[chunk.path]?.score ?? -.infinity { best[chunk.path] = (Double(score), chunk) }
            }
        } else {
            if bm25 == nil { bm25 = LocalAIBM25(chunks.map { "\($0.title)\n\($0.text)" }) }
            for (chunk, score) in zip(chunks, bm25!.scores(trimmed)) where score > 0 {
                if score > best[chunk.path]?.score ?? -.infinity { best[chunk.path] = (score, chunk) }
            }
        }
        let exactTerms = Self.exactTerms(in: trimmed).map(LocalAIText.normalize)
        func exact(_ path: String) -> Bool {
            guard !exactTerms.isEmpty, let content = normalizedContent[path] else { return false }
            return exactTerms.allSatisfy { content.contains($0) }
        }
        // Exact matches the ranker missed still surface.
        if !exactTerms.isEmpty {
            for chunk in chunks where best[chunk.path] == nil && exact(chunk.path) {
                best[chunk.path] = (-.infinity, chunk)
            }
        }
        let ranked = best.map { path, entry in
            LocalAISearchHit(
                path: path, title: entry.chunk.title, score: entry.score, passage: entry.chunk.text,
                exactMatch: exact(path))
        }.sorted {
            if $0.exactMatch != $1.exactMatch { return $0.exactMatch }
            return $0.score != $1.score ? $0.score > $1.score : $0.path < $1.path
        }
        return Array(ranked.prefix(limit))
    }

    /// Passages of `path` ranked by similarity to `query` (Ask context).
    public func passages(of path: String, for query: String, embedder: LocalAIEmbedding?, limit: Int) async throws -> [String] {
        let noteChunks = chunks.filter { $0.path == path }
        guard noteChunks.count > limit else { return noteChunks.map(\.text) }
        if let embedder, indexedHashes[path] == notes[path]?.contentHash {
            try loadVectors()
            let q = try await embedder.embed([EmbeddingPrompt.query(query)])[0]
            let scores = similarity(q)
            let ranked = zip(vectorChunks, scores).filter { $0.0.path == path }.sorted { $0.1 > $1.1 }
            return ranked.prefix(limit).sorted { $0.0.ordinal < $1.0.ordinal }.map(\.0.text)
        }
        let scores = LocalAIBM25(noteChunks.map(\.text)).scores(query)
        return zip(noteChunks, scores).sorted { $0.1 > $1.1 }.prefix(limit).sorted { $0.0.ordinal < $1.0.ordinal }.map(\.0.text)
    }

    /// Quoted phrases plus tokens that look like codes or numbers
    /// ("INV-2291", "A7691B", "2026", "3.14").
    static func exactTerms(in query: String) -> [String] {
        var terms: [String] = []
        var rest = query
        for (open, close) in [("\"", "\""), ("“", "”"), ("«", "»"), ("「", "」")] {
            while let start = rest.range(of: open),
                  let end = rest.range(of: close, range: start.upperBound ..< rest.endIndex) {
                let phrase = rest[start.upperBound ..< end.lowerBound].trimmingCharacters(in: .whitespaces)
                if !phrase.isEmpty { terms.append(phrase) }
                rest.removeSubrange(start.lowerBound ..< end.upperBound)
            }
        }
        for raw in rest.split(whereSeparator: { $0.isWhitespace || ",;:!?()[]".contains($0) }) {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".'’"))
            let digits = token.filter(\.isNumber).count
            let letters = token.filter(\.isLetter).count
            let codeLike = digits > 0 && (letters > 0 || token.contains("-") || token.contains("/"))
            if (digits >= 3 && letters == 0) || (codeLike && token.count >= 3) { terms.append(token) }
        }
        return terms
    }

    // MARK: Vectors

    private func loadVectors() throws {
        guard !vectorsLoaded else { return }
        var loadedChunks: [LocalAIChunk] = []
        var loaded: [Float] = []
        var dim = 0
        try database.prepare("SELECT path, ordinal, title, text, vector FROM chunks ORDER BY path, ordinal").bind([]).rows { row in
            let data = row.data(4)
            let count = data.count / MemoryLayout<Float>.size
            if dim == 0 { dim = count }
            guard count == dim else { return }
            loadedChunks.append(LocalAIChunk(path: row.string(0), ordinal: row.int(1), title: row.string(2), text: row.string(3)))
            data.withUnsafeBytes { loaded.append(contentsOf: $0.bindMemory(to: Float.self)) }
        }
        vectorChunks = loadedChunks
        matrix = loaded
        dimension = dim
        vectorsLoaded = true
    }

    private func similarity(_ query: [Float]) -> [Float] {
        let rows = vectorChunks.count
        guard rows > 0, query.count == dimension else { return Array(repeating: 0, count: rows) }
        var out = [Float](repeating: 0, count: rows)
        matrix.withUnsafeBufferPointer { m in
            query.withUnsafeBufferPointer { q in
                out.withUnsafeMutableBufferPointer { o in
                    cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(rows), Int32(dimension), 1,
                                m.baseAddress, Int32(dimension), q.baseAddress, 1, 0, o.baseAddress, 1)
                }
            }
        }
        return out
    }
}
