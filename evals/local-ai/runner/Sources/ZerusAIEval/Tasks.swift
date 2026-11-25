import Foundation
import ZerusLocalAICore

// Task runners. Every call goes through the production pipelines
// (`LocalAIPipelines` in packages/apple/LocalAI): same prompts, schemas,
// post-processing and retries as the apps. The checks below only grade.

struct TaskResult {
    let id: String
    let kind: String
    let lang: String
    let pass: Bool
    let reasons: [String]
    let output: Any

    var json: JSON {
        ["id": id, "kind": kind, "lang": lang, "pass": pass, "reasons": reasons, "output": output]
    }
}

// MARK: - Runners

func runRoute(_ llm: LLM, _ f: Fixtures) async throws -> [TaskResult] {
    var results: [TaskResult] = []
    for t in try f.tasks("route") {
        let got = (try? await llm.pipelines.route(t["request"] as! String))?.rawValue ?? "<invalid>"
        let expected = t["expected"] as! String
        results.append(TaskResult(
            id: t["id"] as! String, kind: "route", lang: t["lang"] as? String ?? "?",
            pass: got == expected, reasons: got == expected ? [] : ["expected \(expected), got \(got)"],
            output: got))
    }
    return results
}

func runAsk(_ llm: LLM, _ f: Fixtures) async throws -> [TaskResult] {
    var results: [TaskResult] = []
    for t in try f.tasks("ask") {
        let ids = t["notes"] as! [String]
        let sources = ids.compactMap { id in f.notes[id].map { LocalAIAskSource(id: id, path: id, content: $0.raw) } }
        let lang = t["lang"] as? String ?? "en"
        let answerable = t["answerable"] as? Bool ?? true
        var reasons: [String] = []
        var output: Any = NSNull()
        do {
            let answer = try await llm.pipelines.ask(t["query"] as! String, sources: sources, language: lang)
            output = ["answer": answer.answer, "found": answer.found, "evidence": answer.evidence,
                      "sources": answer.sources, "verified": answer.verified] as JSON
            if answerable {
                if !answer.found { reasons.append("said not found") }
                reasons += failedGroups(answer.answer, t["must_include"]).map { "missing: \($0)" }
            } else if answer.found {
                reasons.append("claimed an answer for an unanswerable question")
            }
            reasons += presentForbidden(answer.answer, t["must_not"]).map { "forbidden: \($0)" }
            let corpus = sources.map(\.content).joined(separator: "\n")
            groundingStats.quotes += answer.evidence.count
            groundingStats.ungrounded += answer.evidence.filter { !LocalAIGrounding.isGrounded($0, in: corpus) }.count
        } catch {
            reasons.append("invalid output: \(error.localizedDescription)")
        }
        results.append(TaskResult(
            id: t["id"] as! String, kind: answerable ? "ask" : "ask-unanswerable",
            lang: lang, pass: reasons.isEmpty, reasons: reasons, output: output))
    }
    return results
}

func runSummarize(_ llm: LLM, _ f: Fixtures) async throws -> [TaskResult] {
    var results: [TaskResult] = []
    for t in try f.tasks("summarize") {
        guard let note = f.notes[t["note"] as! String] else { continue }
        let lang = t["lang"] as? String ?? "en"
        let maxWords = t["max_words"] as? Int ?? 80
        let out = (try? await llm.pipelines.summarize(note.raw, language: lang, maxWords: maxWords)) ?? ""
        var reasons = failedGroups(out, t["must_include"]).map { "missing: \($0)" }
        reasons += presentForbidden(out, t["must_not"]).map { "forbidden: \($0)" }
        let words = approxWordCount(out)
        if Double(words) > Double(maxWords) * 1.5 { reasons.append("too long: \(words) words") }
        if out.isEmpty { reasons.append("empty") }
        results.append(TaskResult(
            id: t["id"] as! String, kind: "summarize", lang: lang, pass: reasons.isEmpty,
            reasons: reasons, output: out))
    }
    return results
}

func runEdits(_ llm: LLM, _ f: Fixtures) async throws -> [TaskResult] {
    var results: [TaskResult] = []
    let pipelines = llm.pipelines
    for t in try f.tasks("edit") {
        let kind = t["kind"] as! String
        let id = t["id"] as! String
        let instruction = t["instruction"] as! String
        let expect = t["expect"] as? JSON ?? [:]
        let note = (t["note"] as? String).flatMap { f.notes[$0] }
        var reasons: [String] = []
        var output: Any = NSNull()

        do {
            switch kind {
            case "rewrite_selection":
                guard let note, let selection = t["selection"] as? String else { continue }
                let text = try await pipelines.rewrite(selection: selection, in: note.raw, instruction: instruction)
                output = text
                reasons += failedGroups(text, expect["contains"]).map { "missing: \($0)" }
                reasons += presentForbidden(text, expect["not_contains"]).map { "forbidden: \($0)" }

            case "append":
                guard let note else { continue }
                let text = try await pipelines.append(to: note.raw, instruction: instruction)
                output = text
                reasons += failedGroups(text, expect["contains"]).map { "missing: \($0)" }
                reasons += presentForbidden(text, expect["not_contains"]).map { "forbidden: \($0)" }

            case "instruction":
                guard let note else { continue }
                let edit = try await pipelines.edit(note.raw, instruction: instruction)
                output = ["edits": edit.edits.map { ["find": $0.find, "replace": $0.replace] }, "result": edit.result] as JSON
                reasons += failedGroups(edit.result, expect["contains"]).map { "missing: \($0)" }
                reasons += presentForbidden(edit.result, expect["not_contains"]).map { "forbidden: \($0)" }
                for p in expect["preserve"] as? [String] ?? [] where !edit.result.contains(p) {
                    reasons.append("damaged: \(p.prefix(60))")
                }

            case "create":
                let created = try await pipelines.create(instruction: instruction, reference: note?.raw)
                output = ["title": created.title, "body": created.body] as JSON
                reasons += failedGroups(created.title, expect["title_contains"]).map { "title missing: \($0)" }
                reasons += failedGroups(created.body, expect["contains"]).map { "missing: \($0)" }
                reasons += presentForbidden(created.body, expect["not_contains"]).map { "forbidden: \($0)" }

            case "properties":
                guard let note else { continue }
                let current = parseYAMLProperties(note.frontmatter)
                let ops = try await pipelines.properties(current, instruction: instruction)
                output = ops.map { ["op": $0.kind.rawValue, "key": $0.key, "value": $0.values] }
                let updated = LocalAIPipelines.applying(ops, to: current)
                for (k, v) in expect["properties"] as? JSON ?? [:] where !propertyMatches(updated[k], v) {
                    reasons.append("property \(k): expected \(v), got \(updated[k].map { "\($0)" } ?? "nil")")
                }
                for k in expect["removed_properties"] as? [String] ?? [] where updated[k] != nil {
                    reasons.append("property \(k) not removed")
                }
                let allowed = Set((expect["properties"] as? JSON ?? [:]).keys).union(expect["removed_properties"] as? [String] ?? [])
                let collateral = Set(ops.map(\.key)).subtracting(allowed).filter { updated[$0] != current[$0] }
                if !collateral.isEmpty { reasons.append("changed unrelated: \(collateral.sorted())") }

            default:
                continue
            }
        } catch {
            reasons.append(error.localizedDescription)
        }
        results.append(TaskResult(
            id: id, kind: kind, lang: t["lang"] as? String ?? "?", pass: reasons.isEmpty,
            reasons: reasons, output: output))
    }
    return results
}

// MARK: - Grading helpers

/// Minimal YAML frontmatter reader: scalars, inline lists and dash lists.
func parseYAMLProperties(_ yaml: String) -> [String: LocalAIPropertyValue] {
    var out: [String: LocalAIPropertyValue] = [:]
    var listKey: String?
    for raw in yaml.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("- "), let key = listKey {
            if case .list(var list) = out[key] {
                list.append(unquote(String(line.dropFirst(2))))
                out[key] = .list(list)
            }
            continue
        }
        guard let colon = raw.firstIndex(of: ":"), !raw.hasPrefix(" ") else { continue }
        let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
        let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        if value.isEmpty {
            listKey = key
            out[key] = .list([])
        } else if value.hasPrefix("["), value.hasSuffix("]") {
            listKey = nil
            out[key] = .list(value.dropFirst().dropLast().split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) })
        } else {
            listKey = nil
            out[key] = .text(unquote(value))
        }
    }
    return out
}

func unquote(_ s: String) -> String {
    s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
}

func propertyMatches(_ actual: LocalAIPropertyValue?, _ expected: Any) -> Bool {
    let values: [String]? = switch actual {
    case .text(let s): [s]
    case .list(let l): l
    case nil: nil
    }
    if let e = expected as? [String] {
        return Set((values ?? []).map(normalize)) == Set(e.map(normalize))
    }
    guard let values else { return expected is NSNull }
    return values.count == 1 && normalize(values[0]) == normalize("\(expected)")
}

/// Evidence grounding is reported, not graded: quotes may drop Markdown or
/// join excerpts with ellipses.
nonisolated(unsafe) var groundingStats = (quotes: 0, ungrounded: 0)
