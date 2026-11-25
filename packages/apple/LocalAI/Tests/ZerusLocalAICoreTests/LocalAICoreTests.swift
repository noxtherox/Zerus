import Foundation
import XCTest
@testable import ZerusLocalAICore

final class ModelStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalAIStore-" + UUID().uuidString)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private let hello = Data("hello\n".utf8)
    private var spec: LocalAIModelSpec {
        LocalAIModelSpec(
            id: "test", displayName: "Test", role: .embedding, repository: "org/model", revision: "abc123", license: "MIT",
            files: [
                .init("a.json", size: 6, digest: .gitBlobSHA1("ce013625030ba8dba906f756967f9e9ca394464a")),
                .init("weights/b.safetensors", size: 6, digest: .sha256("5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03")),
            ])
    }

    func testStatesAndChecksums() throws {
        let store = LocalAIModelStore(root: root)
        XCTAssertEqual(store.state(of: spec), .notInstalled)
        XCTAssertEqual(store.remainingBytes(for: spec), 12)
        try store.prepareDirectories(for: spec)
        let dir = store.directory(for: spec)
        XCTAssertTrue(dir.path.hasSuffix("org--model@abc123"))
        try hello.write(to: dir.appendingPathComponent("a.json"))
        XCTAssertEqual(store.state(of: spec), .partial(bytesPresent: 6))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("weights"), withIntermediateDirectories: true)
        try hello.write(to: dir.appendingPathComponent("weights/b.safetensors"))
        XCTAssertNotEqual(store.state(of: spec), .installed, "present but unverified files are not installed")
        try store.verifyAndMarkInstalled(spec)
        XCTAssertEqual(store.state(of: spec), .installed)
        XCTAssertEqual(try store.root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)

        // Same size, different bytes: rejected.
        try Data("HELLO\n".utf8).write(to: dir.appendingPathComponent("a.json"))
        XCTAssertThrowsError(try LocalAIModelStore.verify(dir.appendingPathComponent("a.json"), spec.files[0]))
        try store.delete(spec)
        XCTAssertEqual(store.state(of: spec), .notInstalled)
    }

    func testPinnedCatalogIsComplete() {
        for spec in LocalAIModelSpec.all {
            XCTAssertEqual(spec.revision.count, 40, "\(spec.id) must pin a full commit")
            XCTAssertTrue(spec.files.contains { $0.path == "model.safetensors" })
            XCTAssertTrue(spec.files.contains { $0.path == "tokenizer.json" })
            XCTAssertTrue(spec.files.contains { $0.path == "config.json" })
            for file in spec.files {
                XCTAssertEqual(spec.url(for: file).host, "huggingface.co")
                XCTAssertTrue(spec.url(for: file).path.contains("/resolve/\(spec.revision)/"))
            }
        }
        XCTAssertLessThan(LocalAIModelSpec.qwen35_2B.totalBytes, 2_000_000_000)
        XCTAssertLessThan(LocalAIModelSpec.embeddingGemma300M.totalBytes, 250_000_000)
    }

    /// Exercises the real files when the pinned snapshots are in the local
    /// Hugging Face cache (developer machines); skipped elsewhere.
    func testPinnedSnapshotsInLocalCacheVerify() throws {
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub")
        var checked = 0
        for spec in LocalAIModelSpec.all {
            let snapshot = cache.appendingPathComponent("models--" + spec.repository.replacingOccurrences(of: "/", with: "--") + "/snapshots/" + spec.revision)
            guard FileManager.default.fileExists(atPath: snapshot.appendingPathComponent("config.json").path) else { continue }
            for file in spec.files where file.size < 50_000_000 {
                XCTAssertNoThrow(try LocalAIModelStore.verify(snapshot.appendingPathComponent(file.path).resolvingSymlinksInPath(), file), file.path)
                checked += 1
            }
        }
        if checked == 0 { throw XCTSkip("pinned snapshots not in the local Hugging Face cache") }
    }
}

final class ChunkingTests: XCTestCase {
    func testTitleSectionsAndSizes() {
        let note = LocalAINote(path: "Projects/Trip.md", content: """
            ---
            tags: [travel]
            ---
            # Lisbon trip

            Flights on 3 May.

            ## Budget

            \(String(repeating: "word ", count: 300))
            """)
        XCTAssertEqual(note.title, "Lisbon trip")
        let chunks = LocalAIChunker.chunks(for: note, maxCharacters: 900)
        XCTAssertGreaterThanOrEqual(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 900 && $0.title == "Lisbon trip" })
        XCTAssertFalse(chunks.contains { $0.text.contains("tags:") }, "frontmatter is not embedded")
        XCTAssertEqual(chunks.map(\.ordinal), Array(0 ..< chunks.count))
        XCTAssertEqual(LocalAINote(path: "a/Plain.md", content: "text").title, "Plain")
        XCTAssertEqual(LocalAINote(path: "a/Empty.md", content: "").title, "Empty")
        XCTAssertEqual(LocalAIChunker.chunks(for: LocalAINote(path: "a/Empty.md", content: "")).map(\.text), ["Empty"])
    }

    func testTokensFoldAccentsAndSplitCJK() {
        XCTAssertEqual(LocalAIText.tokens("Café A7 東京都"), ["cafe", "a7", "東京", "京都"])
        XCTAssertTrue(LocalAIText.containsLoosely("Due 11月4日", "11 月 4 日"))
    }

    func testExactTerms() {
        XCTAssertEqual(LocalAISearchIndex.exactTerms(in: "invoice INV-2291 from \"Acme Corp\" 2026"), ["Acme Corp", "INV-2291", "2026"])
        XCTAssertEqual(LocalAISearchIndex.exactTerms(in: "what did I plan for the trip"), [])
        XCTAssertEqual(LocalAISearchIndex.exactTerms(in: "batch A7691B?"), ["A7691B"])
    }
}

/// Bag-of-words hashing embedder: deterministic, normalised, good enough to
/// rank notes sharing words with the query.
final class FakeEmbedder: LocalAIEmbedding, @unchecked Sendable {
    let modelID: String
    private let lock = NSLock()
    private(set) var embeddedTexts = 0

    init(modelID: String = "fake") { self.modelID = modelID }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        lock.withLock { embeddedTexts += texts.count }
        return texts.map { text in
            let body = text.components(separatedBy: "| query: ").last!.components(separatedBy: "| text: ").last!
            var v = [Float](repeating: 0, count: 64)
            for token in LocalAIText.tokens(body) { v[abs(token.hashValue) % 64] += 1 }
            let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
            return norm > 0 ? v.map { $0 / norm } : v
        }
    }
}

final class SearchIndexTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("LocalAIIndex-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    private let notes = [
        LocalAINote(path: "garden.md", content: "# Garden\n\nPlant tomatoes and basil in April."),
        LocalAINote(path: "invoice.md", content: "# Invoices\n\nInvoice INV-2291 paid to the plumber."),
        LocalAINote(path: "trip.md", content: "# Trip\n\nTrain to Porto, hotel near the river."),
    ]

    func testKeywordFallbackThenIncrementalVectorSearch() async throws {
        let embedder = FakeEmbedder()
        let index = try LocalAISearchIndex(url: url, embeddingModelID: embedder.modelID)
        await index.setNotes(notes)
        let before = await index.status()
        XCTAssertEqual(before.indexedNotes, 0)
        // Not indexed yet: BM25.
        var hits = try await index.search("tomatoes", embedder: embedder)
        XCTAssertEqual(hits.first?.path, "garden.md")

        try await index.update(embedder: embedder)
        let after = await index.status()
        XCTAssertTrue(after.isComplete)
        hits = try await index.search("hotel river", embedder: embedder)
        XCTAssertEqual(hits.first?.path, "trip.md")
        XCTAssertEqual(embedder.embeddedTexts, 3 + 1)

        // Only the changed note is re-embedded; deleted notes disappear.
        await index.setNotes([notes[0], notes[1], LocalAINote(path: "trip.md", content: "# Trip\n\nFlight to Madeira.")])
        try await index.update(embedder: embedder)
        XCTAssertEqual(embedder.embeddedTexts, 4 + 1)
        await index.setNotes([notes[0], notes[1]])
        try await index.update(embedder: embedder)
        hits = try await index.search("Madeira flight", embedder: embedder)
        XCTAssertFalse(hits.contains { $0.path == "trip.md" })

        // Reopening keeps the index; a different embedding model resets it.
        let reopened = try LocalAISearchIndex(url: url, embeddingModelID: embedder.modelID)
        await reopened.setNotes([notes[0], notes[1]])
        let reopenedStatus = await reopened.status()
        XCTAssertTrue(reopenedStatus.isComplete)
        let other = try LocalAISearchIndex(url: url, embeddingModelID: "other-model")
        await other.setNotes([notes[0], notes[1]])
        let otherStatus = await other.status()
        XCTAssertEqual(otherStatus.indexedNotes, 0)
    }

    func testExactMatchesRankFirst() async throws {
        let embedder = FakeEmbedder()
        let index = try LocalAISearchIndex(url: url, embeddingModelID: embedder.modelID)
        await index.setNotes(notes + [LocalAINote(path: "other.md", content: "# Plumber\n\nCall the plumber about the invoice.")])
        try await index.update(embedder: embedder)
        let hits = try await index.search("plumber invoice INV-2291", embedder: embedder)
        XCTAssertEqual(hits.first?.path, "invoice.md")
        XCTAssertEqual(hits.first?.exactMatch, true)
        XCTAssertEqual(hits.filter(\.exactMatch).count, 1)
    }
}

/// Returns scripted outputs in order and records prompts.
final class ScriptedModel: LocalAILanguageModel, @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [String]
    private(set) var users: [String] = []

    init(_ outputs: [String]) { self.outputs = outputs }

    private func next(_ user: String) -> String {
        lock.withLock {
            users.append(user)
            return outputs.isEmpty ? "" : outputs.removeFirst()
        }
    }

    func generateJSON(system: String, user: String, schema: String, maxTokens: Int) async throws -> String { next(user) }
    func generateText(system: String, user: String, maxTokens: Int, onText: (@Sendable (String) -> Void)?) async throws -> String { next(user) }
}

final class PipelineTests: XCTestCase {
    func testAskMapsSourcesAndVerifiesEvidence() async throws {
        let model = ScriptedModel([#"{"evidence":["tomatoes and basil"],"answer":"Tomatoes and basil.","found":true,"sources":["garden"]}"#])
        let answer = try await LocalAIPipelines(model: model).ask("What do I plant?", sources: [
            .init(id: "garden", path: "Home/garden.md", content: "Plant **tomatoes** and basil in April."),
            .init(id: "trip", path: "trip.md", content: "Porto"),
        ], language: "en")
        XCTAssertEqual(answer.sources, ["Home/garden.md"])
        XCTAssertTrue(answer.found)
        XCTAssertTrue(answer.verified)
        XCTAssertTrue(model.users[0].contains("<note id=\"garden\">"))
        XCTAssertTrue(model.users[0].hasSuffix("Answer in English."))

        let invented = ScriptedModel([#"{"evidence":["roses in June"],"answer":"Roses.","found":true,"sources":["garden"]}"#])
        let unverified = try await LocalAIPipelines(model: invented).ask("What?", sources: [.init(id: "garden", path: "g.md", content: "tomatoes")], language: "en")
        XCTAssertFalse(unverified.verified)
    }

    func testEditRetriesOnceWithReason() async throws {
        let note = "- [ ] Book tickets\n- [ ] Pack"
        let model = ScriptedModel([
            #"{"edits":[{"find":"Book the tickets","replace":"x"}]}"#,
            #"{"edits":[{"find":"- [ ] Book tickets","replace":"- [x] Book tickets"}]}"#,
        ])
        let result = try await LocalAIPipelines(model: model).edit(note, instruction: "tick booking")
        XCTAssertEqual(result.result, "- [x] Book tickets\n- [ ] Pack")
        XCTAssertTrue(model.users[1].contains("excerpt not found"))

        let failing = ScriptedModel([#"{"edits":[{"find":"- [ ]","replace":"- [x]"}]}"#, #"{"edits":[{"find":"- [ ]","replace":"- [x]"}]}"#])
        do {
            _ = try await LocalAIPipelines(model: failing).edit(note, instruction: "tick")
            XCTFail("ambiguous edits must not apply")
        } catch let error as LocalAIPipelineError {
            guard case .editNotApplicable(let reason) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(reason.contains("2 times"))
        }
    }

    func testPropertiesAndRoute() async throws {
        let model = ScriptedModel([
            #"{"ops":[{"op":"set","key":"tags","value":["a"]},{"op":"set","key":"status","value":["done"]},{"op":"remove","key":"due","value":[]}]}"#,
            #"{"intent":"edit"}"#,
            #"{"intent":"bogus"}"#,
        ])
        let pipelines = LocalAIPipelines(model: model)
        let current: [String: LocalAIPropertyValue] = ["tags": .list(["x", "y"]), "status": .text("open"), "due": .text("2026-01-01")]
        let ops = try await pipelines.properties(current, instruction: "only tag a, mark done, no due date")
        XCTAssertEqual(LocalAIPipelines.applying(ops, to: current), ["tags": .list(["a"]), "status": .text("done")])
        let intent = try await pipelines.route("tick the box")
        XCTAssertEqual(intent, .edit)
        do {
            _ = try await pipelines.route("x")
            XCTFail("invalid intent")
        } catch {}
    }

    func testAppendingAndLanguage() {
        XCTAssertEqual(LocalAIPipelines.appending("New", to: "Old"), "Old\n\nNew\n")
        XCTAssertEqual(LocalAIPipelines.appending("New\n", to: "Old\n\n"), "Old\n\nNew\n")
        XCTAssertEqual(LocalAILanguage.detect("Onde fica o hotel que reservámos para a viagem?"), "pt")
        XCTAssertEqual(LocalAILanguage.name("de"), "German")
    }
}

/// The local AI code may contact the network only to download models
/// (docs/local-ai-plan.md, PRIVACY). Fails if networking appears anywhere else.
final class NetworkGuardTests: XCTestCase {
    static let allowed: Set<String> = ["ModelDownloader.swift", "LocalAIModels.swift"]
    static let patterns = [
        "URLSession", "URLRequest", "NWConnection", "NWPathMonitor", "CFStream", "WebSocket",
        "http://", "https://", "Data(contentsOf: URL(string", "HubApi", "HubClient", "#hubDownloader",
    ]

    func testOnlyTheDownloaderUsesTheNetwork() throws {
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = packageRoot.appendingPathComponent("Sources")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let file as URL in walker where file.pathExtension == "swift" {
            scanned += 1
            guard !Self.allowed.contains(file.lastPathComponent) else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for pattern in Self.patterns where text.contains(pattern) {
                XCTFail("\(file.lastPathComponent) uses \(pattern); only the model downloader may use the network")
            }
        }
        XCTAssertGreaterThan(scanned, 5)
    }

    func testDownloaderHostIsHuggingFaceOnly() throws {
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try String(contentsOf: packageRoot.appendingPathComponent("Sources/ZerusLocalAICore/LocalAIModels.swift"), encoding: .utf8)
        let downloader = try String(contentsOf: packageRoot.appendingPathComponent("Sources/ZerusLocalAICore/ModelDownloader.swift"), encoding: .utf8)
        XCTAssertFalse(catalog.contains("http://"))
        XCTAssertFalse(downloader.contains("http://") || downloader.contains("https://"), "the downloader only fetches catalog URLs")
        XCTAssertTrue(downloader.contains("URLSessionConfiguration.ephemeral"))
    }
}
