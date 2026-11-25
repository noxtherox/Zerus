import Foundation
import MLX

// Usage:
//   zerus-ai-eval retrieval [--embedders a,b] [--root PATH]
//   zerus-ai-eval llm [--models a,b] [--tasks route,ask,summarize,edit] [--root PATH]
//   zerus-ai-eval list
// Results are written to <root>/results/<timestamp>-<suite>-<key>.json

func log(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

func option(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func list(_ name: String, default value: [String]) -> [String] {
    option(name).map { $0.split(separator: ",").map(String.init) } ?? value
}

let root = URL(fileURLWithPath: option("--root") ?? FileManager.default.currentDirectoryPath)
let resultsDir = root.appendingPathComponent("results")
try FileManager.default.createDirectory(at: resultsDir, withIntermediateDirectories: true)
let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")

func write(_ object: JSON, _ name: String) throws {
    let url = resultsDir.appendingPathComponent("\(stamp)-\(name).json")
    let data = try JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: url)
    log("wrote \(url.path)")
}

func summarize(_ results: [TaskResult]) -> JSON {
    var byKind: [String: [Bool]] = [:]
    var byLang: [String: [Bool]] = [:]
    for r in results {
        byKind[r.kind, default: []].append(r.pass)
        byLang[r.lang, default: []].append(r.pass)
    }
    func rate(_ a: [Bool]) -> String { "\(a.filter { $0 }.count)/\(a.count)" }
    return [
        "overall": rate(results.map(\.pass)),
        "by_kind": byKind.mapValues(rate),
        "by_lang": byLang.mapValues(rate),
    ]
}

let command = CommandLine.arguments.dropFirst().first ?? "list"
let fixtures = try Fixtures(root: root)
log("\(fixtures.notes.count) notes")

switch command {
case "retrieval":
    // --extra-notes DIR adds unlabeled distractor notes (e.g. a frozen vault copy).
    var extra: [Note] = []
    if let dir = option("--extra-notes") {
        let base = URL(fileURLWithPath: dir)
        let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "md", !url.path.contains("/."),
                let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            extra.append(Note(id: "extra:" + url.path.dropFirst(base.path.count), raw: raw))
        }
        log("\(extra.count) extra notes")
    }
    let report = try await runRetrieval(
        fixtures: fixtures, embedderKeys: list("--embedders", default: embedderSpecs.map(\.key)),
        extraNotes: extra)
    try write(report, "retrieval")

case "llm":
    let tasks = list("--tasks", default: ["route", "ask", "summarize", "edit"])
    for key in list("--models", default: llmSpecs.map(\.key)) {
        guard let spec = llmSpecs.first(where: { $0.key == key }) else {
            log("unknown model \(key)")
            continue
        }
        log("== \(key) (\(spec.repo))")
        Memory.peakMemory = 0
        groundingStats = (0, 0)
        let llm: LLM
        do { llm = try await LLM(spec) } catch {
            log("load failed: \(error)")
            try write(["model": key, "load_error": "\(error)"], "llm-\(key)")
            continue
        }
        let started = Date()
        var results: [TaskResult] = []
        for task in tasks {
            let part: [TaskResult]
            switch task {
            case "route": part = try await runRoute(llm, fixtures)
            case "ask": part = try await runAsk(llm, fixtures)
            case "summarize": part = try await runSummarize(llm, fixtures)
            case "edit": part = try await runEdits(llm, fixtures)
            default: part = []
            }
            log("  \(task): \(part.filter(\.pass).count)/\(part.count)")
            results += part
        }
        try write([
            "model": key, "repo": spec.repo, "note": spec.note,
            "load_s": llm.loadSeconds, "wall_s": Date().timeIntervalSince(started),
            "peak_mb": Double(Memory.peakMemory) / 1_048_576,
            "summary": summarize(results), "perf": llm.stats.summary,
            "grounding": ["quotes": groundingStats.quotes, "ungrounded": groundingStats.ungrounded],
            "results": results.map(\.json),
        ], "llm-\(key)")
        Memory.clearCache()
    }

default:
    print("LLMs:", llmSpecs.map(\.key).joined(separator: ", "))
    print("Embedders:", embedderSpecs.map(\.key).joined(separator: ", "))
}
