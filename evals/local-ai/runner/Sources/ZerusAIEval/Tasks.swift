import Foundation

// Prototype prompts for the local harness pipelines. These are what we tune;
// the app's `packages/apple/` implementation should start from the winners.

enum Prompts {
    static let route = """
        You classify a request made to a notes app. Choose exactly one intent:
        - ask: a question or search about information in the user's notes.
        - summarize: the user wants a summary of a note or of text.
        - edit: the user wants to change, add to, append, tag, rename, mark done, or create a note.
        The request may be in any language.
        """

    static let ask = """
        You answer questions using only the notes provided. Each note is wrapped in <note id="..."> tags.
        Steps:
        1. "evidence": copy, word for word, up to three short passages from the notes that answer the question. Read every note carefully before deciding nothing is relevant.
        2. "answer": answer in one to three sentences using only that evidence, in the language requested.
        3. "found": true if the evidence answers the question, false if the notes do not contain the answer (then evidence is empty and the answer says the notes don't say).
        4. "sources": the ids of the notes the evidence came from.
        """

    static func summarize(language: String, maxWords: Int) -> String {
        """
        You summarize a note for its author. Use only facts stated in the note; never add details.
        Keep names, dates, numbers and decisions exact. Write at most \(maxWords) words, in \(languageName(language)).
        Write one plain paragraph with no headings or lists. Output only the summary.
        """
    }

    static let rewrite = """
        You rewrite a selected passage from a note according to the user's instruction.
        Keep every fact, name, number and link unless the instruction says otherwise.
        Return in "text" only the rewritten selection — never the rest of the note. Keep Markdown formatting.
        """

    static let append = """
        You write new text to append to the end of a note, following the user's instruction.
        Use only facts from the note. Return only the new text in "text", as Markdown.
        Write in the language of the note unless the instruction asks otherwise.
        """

    static let findReplace = """
        You edit a note precisely, following the user's instruction.
        Return a list of edits. Each edit has:
        - "find": an exact excerpt copied character for character from the note (including Markdown such as "- [ ]" or "**"). It must occur only once in the note, so include enough of the line to be unique.
        - "replace": the new text that takes its place. To add a new line, find the line before it and replace it with that same line, a newline, and the new line.
        Examples: tick a checkbox: find "- [ ] Book tickets" replace "- [x] Book tickets". Change a date: find "Deadline: 3 May" replace "Deadline: 9 May".
        Change only what the instruction asks for.
        """

    static let create = """
        You create a new note from the user's instruction. Return a short "title" and a Markdown "body".
        Write in the language the instruction asks for, otherwise in the language of the instruction.
        Use facts from the reference note when one is given; never invent personal facts.
        """

    static let properties = """
        You change a note's properties (YAML frontmatter). Current properties are shown as JSON.
        Return a list of operations:
        - {"op": "set", "key": name, "value": [values]}: add or overwrite a property. "value" is always a list; use one item for a single value. For tags, give the complete new list.
        - {"op": "remove", "key": name, "value": []}: delete a property.
        Only include properties the instruction asks to change.
        """
}

func languageName(_ code: String) -> String {
    Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
}

enum Schemas {
    static let route = #"{"type":"object","properties":{"intent":{"type":"string","enum":["ask","summarize","edit"]}},"required":["intent"],"additionalProperties":false}"#
    static func ask(ids: [String]) -> String {
        let idEnum = ids.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"type":"object","properties":{"evidence":{"type":"array","maxItems":3,"items":{"type":"string","maxLength":400}},"answer":{"type":"string","maxLength":600},"found":{"type":"boolean"},"sources":{"type":"array","maxItems":3,"items":{"enum":["#
            + idEnum + #"]}}},"required":["evidence","answer","found","sources"],"additionalProperties":false}"#
    }
    static let text = #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"],"additionalProperties":false}"#
    static let findReplace = #"{"type":"object","properties":{"edits":{"type":"array","minItems":1,"maxItems":8,"items":{"type":"object","properties":{"find":{"type":"string","minLength":1},"replace":{"type":"string"}},"required":["find","replace"],"additionalProperties":false}}},"required":["edits"],"additionalProperties":false}"#
    static let create = #"{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"}},"required":["title","body"],"additionalProperties":false}"#
    static let properties = #"{"type":"object","properties":{"ops":{"type":"array","minItems":1,"maxItems":6,"items":{"type":"object","properties":{"op":{"type":"string","enum":["set","remove"]},"key":{"type":"string"},"value":{"type":"array","items":{"type":"string"}}},"required":["op","key","value"],"additionalProperties":false}}},"required":["ops"],"additionalProperties":false}"#
}

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

func noteBlock(_ note: Note) -> String {
    "<note id=\"\(note.id)\">\n\(note.raw)\n</note>"
}

// MARK: - Runners

func runRoute(_ llm: LLM, _ f: Fixtures) async throws -> [TaskResult] {
    var results: [TaskResult] = []
    for t in try f.tasks("route") {
        let out = await llm.json(system: Prompts.route, user: t["request"] as! String, schema: Schemas.route, maxTokens: 40)
        let got = out?["intent"] as? String ?? "<invalid>"
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
        let context = ids.compactMap { f.notes[$0] }.map(noteBlock).joined(separator: "\n\n")
        let lang = t["lang"] as? String ?? "en"
        let user = "\(context)\n\nQuestion: \(t["query"] as! String)\nAnswer in \(languageName(lang))."
        let out = await llm.json(system: Prompts.ask, user: user, schema: Schemas.ask(ids: ids), maxTokens: 700)
        var reasons: [String] = []
        let answerable = t["answerable"] as? Bool ?? true
        if let out {
            let answer = out["answer"] as? String ?? ""
            let found = out["found"] as? Bool ?? true
            let sources = out["sources"] as? [String] ?? []
            if answerable {
                if !found { reasons.append("said not found") }
                reasons += failedGroups(answer, t["must_include"]).map { "missing: \($0)" }
            } else if found {
                reasons.append("claimed an answer for an unanswerable question")
            }
            reasons += presentForbidden(answer, t["must_not"]).map { "forbidden: \($0)" }
            let bogus = sources.filter { !ids.contains($0) }
            if !bogus.isEmpty { reasons.append("invented sources: \(bogus)") }
            // Grounding: every evidence quote must appear in a provided note.
            let corpus = ids.compactMap { f.notes[$0]?.raw }.joined(separator: "\n")
            let quotes = out["evidence"] as? [String] ?? []
            let ungrounded = quotes.filter { !isGrounded($0, in: corpus) }
            groundingStats.quotes += quotes.count
            groundingStats.ungrounded += ungrounded.count
        } else {
            reasons.append("invalid output")
        }
        results.append(TaskResult(
            id: t["id"] as! String, kind: answerable ? "ask" : "ask-unanswerable",
            lang: t["lang"] as? String ?? "?", pass: reasons.isEmpty, reasons: reasons,
            output: out ?? NSNull()))
    }
    return results
}

func runSummarize(_ llm: LLM, _ f: Fixtures) async throws -> [TaskResult] {
    var results: [TaskResult] = []
    for t in try f.tasks("summarize") {
        guard let note = f.notes[t["note"] as! String] else { continue }
        let lang = t["lang"] as? String ?? "en"
        let maxWords = t["max_words"] as? Int ?? 80
        let out = try await llm.text(
            system: Prompts.summarize(language: lang, maxWords: maxWords),
            user: "\(note.raw)\n\n(Write the summary in \(languageName(lang)).)",
            maxTokens: maxWords * 2 + 40)
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
    for t in try f.tasks("edit") {
        let kind = t["kind"] as! String
        let id = t["id"] as! String
        let instruction = t["instruction"] as! String
        let expect = t["expect"] as? JSON ?? [:]
        let note = (t["note"] as? String).flatMap { f.notes[$0] }
        var reasons: [String] = []
        var output: Any = NSNull()

        switch kind {
        case "rewrite_selection":
            guard let note, let selection = t["selection"] as? String else { continue }
            let user = "Note (context only):\n\(note.raw)\n\nSelection to rewrite:\n\(selection)\n\nInstruction: \(instruction)\nReturn only the rewritten selection."
            if let out = await llm.json(system: Prompts.rewrite, user: user, schema: Schemas.text),
                let text = out["text"] as? String
            {
                output = text
                reasons += failedGroups(text, expect["contains"]).map { "missing: \($0)" }
                reasons += presentForbidden(text, expect["not_contains"]).map { "forbidden: \($0)" }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reasons.append("empty") }
            } else { reasons.append("invalid output") }

        case "append":
            guard let note else { continue }
            let user = "Note:\n\(note.raw)\n\nInstruction: \(instruction)"
            if let out = await llm.json(system: Prompts.append, user: user, schema: Schemas.text),
                let text = out["text"] as? String
            {
                output = text
                reasons += failedGroups(text, expect["contains"]).map { "missing: \($0)" }
                reasons += presentForbidden(text, expect["not_contains"]).map { "forbidden: \($0)" }
            } else { reasons.append("invalid output") }

        case "instruction":
            guard let note else { continue }
            let user = "Note:\n\(note.raw)\n\nInstruction: \(instruction)"
            if let out = await llm.json(system: Prompts.findReplace, user: user, schema: Schemas.findReplace),
                let edits = out["edits"] as? [JSON]
            {
                output = out
                switch applyFindReplace(note.raw, edits) {
                case .failure(let error): reasons.append(error.description)
                case .success(let result):
                    output = ["edits": edits, "result": result] as JSON
                    reasons += failedGroups(result, expect["contains"]).map { "missing: \($0)" }
                    reasons += presentForbidden(result, expect["not_contains"]).map { "forbidden: \($0)" }
                    for p in expect["preserve"] as? [String] ?? [] where !result.contains(p) {
                        reasons.append("damaged: \(p.prefix(60))")
                    }
                    if result == note.raw { reasons.append("no change") }
                }
            } else { reasons.append("invalid output") }

        case "create":
            let reference = note.map { "Reference note:\n\($0.raw)\n\n" } ?? ""
            if let out = await llm.json(
                system: Prompts.create, user: "\(reference)Instruction: \(instruction)",
                schema: Schemas.create, maxTokens: 1200)
            {
                output = out
                let title = out["title"] as? String ?? ""
                let body = out["body"] as? String ?? ""
                reasons += failedGroups(title, expect["title_contains"]).map { "title missing: \($0)" }
                reasons += failedGroups(body, expect["contains"]).map { "missing: \($0)" }
                reasons += presentForbidden(body, expect["not_contains"]).map { "forbidden: \($0)" }
            } else { reasons.append("invalid output") }

        case "properties":
            guard let note else { continue }
            let current = parseYAMLProperties(note.frontmatter)
            let currentJSON = String(
                data: try JSONSerialization.data(withJSONObject: current, options: [.sortedKeys]),
                encoding: .utf8)!
            let user = "Current properties:\n\(currentJSON)\n\nInstruction: \(instruction)"
            if let out = await llm.json(system: Prompts.properties, user: user, schema: Schemas.properties, maxTokens: 200) {
                output = out
                var updated = current
                var touched = Set<String>()
                for op in out["ops"] as? [JSON] ?? [] {
                    guard let k = op["key"] as? String else { continue }
                    touched.insert(k)
                    let values = op["value"] as? [String] ?? []
                    if op["op"] as? String == "remove" {
                        updated.removeValue(forKey: k)
                    } else if current[k] is [String] || values.count != 1 {
                        updated[k] = values
                    } else {
                        updated[k] = values[0]
                    }
                }
                for (k, v) in expect["properties"] as? JSON ?? [:] where !propertyMatches(updated[k], v) {
                    reasons.append("property \(k): expected \(v), got \(updated[k] ?? "nil")")
                }
                for k in expect["removed_properties"] as? [String] ?? [] where updated[k] != nil {
                    reasons.append("property \(k) not removed")
                }
                let allowed = Set((expect["properties"] as? JSON ?? [:]).keys)
                    .union(expect["removed_properties"] as? [String] ?? [])
                let collateral = touched.subtracting(allowed).filter {
                    !propertyMatches(updated[$0], current[$0] as Any)
                }
                if !collateral.isEmpty { reasons.append("changed unrelated: \(collateral.sorted())") }
            } else { reasons.append("invalid output") }

        default:
            continue
        }
        results.append(TaskResult(
            id: id, kind: kind, lang: t["lang"] as? String ?? "?", pass: reasons.isEmpty,
            reasons: reasons, output: output))
    }
    return results
}

// MARK: - Edit helpers

func applyFindReplace(_ text: String, _ edits: [JSON]) -> Result<String, EditError> {
    var text = text
    for e in edits {
        let find = e["find"] as? String ?? ""
        let replace = e["replace"] as? String ?? ""
        let count = text.components(separatedBy: find).count - 1
        guard count == 1, let range = text.range(of: find) else {
            return .failure(EditError(count == 0 ? "find not in note: \(find.prefix(50))" : "find not unique (\(count)x): \(find.prefix(50))"))
        }
        text.replaceSubrange(range, with: replace)
    }
    return .success(text)
}

func applyLineEdits(_ lines: [String], _ edits: [JSON]) -> Result<String, EditError> {
    var lines = lines
    let ordered = edits.sorted { ($0["line"] as? Int ?? 0) > ($1["line"] as? Int ?? 0) }
    for e in ordered {
        guard let n = e["line"] as? Int, n >= 1, n <= lines.count else {
            return .failure(EditError("line out of range: \(e["line"] ?? "nil")"))
        }
        let find = e["find"] as? String ?? ""
        let text = e["replace"] as? String ?? ""
        switch e["action"] as? String {
        case "change":
            let line = lines[n - 1]
            guard !find.isEmpty, let range = line.range(of: find) else {
                return .failure(EditError("line \(n) does not contain \"\(find.prefix(40))\""))
            }
            lines[n - 1] = line.replacingCharacters(in: range, with: text)
        case "insert_after": lines.insert(contentsOf: text.components(separatedBy: "\n"), at: n)
        case "delete": lines.remove(at: n - 1)
        default: return .failure(EditError("bad action"))
        }
    }
    return .success(lines.joined(separator: "\n"))
}

struct EditError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// Minimal YAML frontmatter reader: scalars, inline lists and dash lists.
func parseYAMLProperties(_ yaml: String) -> JSON {
    var out: JSON = [:]
    var listKey: String?
    for raw in yaml.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("- "), let key = listKey {
            var list = out[key] as? [String] ?? []
            list.append(unquote(String(line.dropFirst(2))))
            out[key] = list
            continue
        }
        guard let colon = raw.firstIndex(of: ":"), !raw.hasPrefix(" ") else { continue }
        let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
        let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        if value.isEmpty {
            listKey = key
            out[key] = [String]()
        } else if value.hasPrefix("["), value.hasSuffix("]") {
            listKey = nil
            out[key] = value.dropFirst().dropLast().split(separator: ",").map {
                unquote($0.trimmingCharacters(in: .whitespaces))
            }
        } else {
            listKey = nil
            out[key] = unquote(value)
        }
    }
    return out
}

func unquote(_ s: String) -> String {
    s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
}

func propertyMatches(_ actual: Any?, _ expected: Any) -> Bool {
    if let e = expected as? [String] {
        let a = (actual as? [String]) ?? (actual as? String).map { [$0] } ?? []
        return Set(a.map(normalize)) == Set(e.map(normalize))
    }
    let e = "\(expected)"
    if let a = actual as? String { return normalize(a) == normalize(e) }
    if let a = actual as? [String], a.count == 1 { return normalize(a[0]) == normalize(e) }
    return actual == nil && expected is NSNull
}

/// Evidence grounding is reported, not graded: quotes may drop Markdown or
/// join excerpts with ellipses.
nonisolated(unsafe) var groundingStats = (quotes: 0, ungrounded: 0)

func isGrounded(_ quote: String, in corpus: String) -> Bool {
    let strip = { (s: String) in
        normalize(s).filter { !"*_`|#>".contains($0) && !$0.isWhitespace }
    }
    let c = strip(corpus)
    let parts = quote.replacingOccurrences(of: "…", with: "...").components(separatedBy: "...")
        .map(strip).filter { $0.count >= 4 && !$0.hasPrefix("<note") && $0 != "</note>" }
    return !parts.isEmpty && parts.allSatisfy { c.contains($0) }
}
