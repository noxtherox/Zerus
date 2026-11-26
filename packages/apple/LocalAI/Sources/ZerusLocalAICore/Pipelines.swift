import Foundation
import NaturalLanguage

/// A local language model (MLX in `ZerusLocalAI`, scripted fakes in tests).
/// Generation is greedy; JSON output is grammar-constrained to `schema`.
public protocol LocalAILanguageModel: Sendable {
    func generateJSON(system: String, user: String, schema: String, maxTokens: Int) async throws -> String
    func generateText(system: String, user: String, maxTokens: Int, onText: (@Sendable (String) -> Void)?) async throws -> String
}

public enum LocalAIPipelineError: LocalizedError, Equatable {
    case invalidOutput
    case editNotApplicable(String)
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .invalidOutput: "The on-device model returned an unusable answer. Try rephrasing."
        case .editNotApplicable(let reason): "The change couldn't be applied safely (\(reason)). Try a more specific instruction."
        case .emptyResult: "The on-device model returned nothing. Try rephrasing."
        }
    }
}

public enum LocalAIIntent: String, Sendable { case ask, summarize, edit }

public struct LocalAIAskSource: Sendable, Hashable {
    /// Short identifier shown to the model and returned in `sources`.
    public let id: String
    public let path: String
    /// Full note text or its most relevant passages.
    public let content: String

    public init(id: String, path: String, content: String) {
        self.id = id
        self.path = path
        self.content = content
    }
}

public struct LocalAIAnswer: Sendable, Equatable {
    public let answer: String
    /// False when the notes do not contain the answer.
    public let found: Bool
    /// Passages quoted from the notes.
    public let evidence: [String]
    /// Paths of the cited notes.
    public let sources: [String]
    /// Every evidence quote was found in the notes (soft check; quotes may
    /// drop Markdown).
    public let verified: Bool
}

public enum LocalAIPropertyValue: Sendable, Hashable, Codable {
    case text(String)
    case list([String])

    var json: Any {
        switch self {
        case .text(let s): s
        case .list(let l): l
        }
    }
}

public struct LocalAIPropertyOperation: Sendable, Hashable {
    public enum Kind: String, Sendable { case set, remove }
    public let kind: Kind
    public let key: String
    public let values: [String]

    public init(kind: Kind, key: String, values: [String]) {
        self.kind = kind
        self.key = key
        self.values = values
    }
}

public struct LocalAIFindReplace: Sendable, Hashable {
    public let find: String
    public let replace: String

    public init(find: String, replace: String) {
        self.find = find
        self.replace = replace
    }
}

public struct LocalAIEditResult: Sendable, Equatable {
    public let edits: [LocalAIFindReplace]
    public let result: String
}

/// The fixed pipelines (no agent loop): one router call, then Ask,
/// Summarize or an edit, each with constrained JSON output. Prompts and
/// schemas are the phase 1 winners (`evals/local-ai/`).
public struct LocalAIPipelines: Sendable {
    public let model: LocalAILanguageModel

    public init(model: LocalAILanguageModel) {
        self.model = model
    }

    // MARK: Route

    public func route(_ request: String) async throws -> LocalAIIntent {
        let out = try await json(system: LocalAIPrompts.route, user: request, schema: LocalAISchemas.route, maxTokens: 40)
        guard let intent = (out["intent"] as? String).flatMap(LocalAIIntent.init(rawValue:)) else { throw LocalAIPipelineError.invalidOutput }
        return intent
    }

    // MARK: Ask

    public func ask(_ question: String, sources: [LocalAIAskSource], language: String? = nil) async throws -> LocalAIAnswer {
        let language = language ?? LocalAILanguage.detect(question)
        let ids = Self.uniqueIDs(sources.map(\.id))
        let context = zip(ids, sources).map { "<note id=\"\($0)\">\n\($1.content)\n</note>" }.joined(separator: "\n\n")
        let user = "\(context)\n\nQuestion: \(question)\nAnswer in \(LocalAILanguage.name(language))."
        let out = try await json(system: LocalAIPrompts.ask, user: user, schema: LocalAISchemas.ask(ids: ids), maxTokens: 700)
        let found = out["found"] as? Bool ?? false
        let evidence = (out["evidence"] as? [String] ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let byID = Dictionary(uniqueKeysWithValues: zip(ids, sources.map(\.path)))
        var paths: [String] = []
        for id in out["sources"] as? [String] ?? [] { if let p = byID[id], !paths.contains(p) { paths.append(p) } }
        // Small models sometimes answer without citing: cite the notes that
        // contain the quoted evidence.
        if found, paths.isEmpty {
            paths = sources.filter { source in evidence.contains { LocalAIGrounding.isGrounded($0, in: source.content) } }.map(\.path)
        }
        let corpus = sources.map(\.content).joined(separator: "\n")
        let verified = !found || (!evidence.isEmpty && evidence.allSatisfy { LocalAIGrounding.isGrounded($0, in: corpus) })
        return LocalAIAnswer(
            answer: (out["answer"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            found: found, evidence: found ? evidence : [], sources: found ? paths : [], verified: verified)
    }

    // MARK: Summarize

    public func summarize(_ text: String, language: String? = nil, maxWords: Int = 80, onText: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let language = language ?? LocalAILanguage.detect(text)
        let out = try await model.generateText(
            system: LocalAIPrompts.summarize(language: language, maxWords: maxWords),
            user: "\(text)\n\n(Write the summary in \(LocalAILanguage.name(language)).)",
            maxTokens: maxWords * 2 + 40, onText: onText)
        let summary = Self.stripThinking(out)
        guard !summary.isEmpty else { throw LocalAIPipelineError.emptyResult }
        return summary
    }

    // MARK: Edits

    /// Rewrites `selection` (a passage of `note`); returns only the new passage.
    public func rewrite(selection: String, in note: String, instruction: String) async throws -> String {
        let user = "Note (context only):\n\(note)\n\nSelection to rewrite:\n\(selection)\n\nInstruction: \(instruction)\nReturn only the rewritten selection."
        let out = try await json(system: LocalAIPrompts.rewrite, user: user, schema: LocalAISchemas.text,
                                 maxTokens: max(600, selection.count / 2 + 200))
        guard let text = out["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalAIPipelineError.emptyResult }
        return text
    }

    /// New Markdown to append to `note`.
    public func append(to note: String, instruction: String) async throws -> String {
        let out = try await json(system: LocalAIPrompts.append, user: "Note:\n\(note)\n\nInstruction: \(instruction)",
                                 schema: LocalAISchemas.text, maxTokens: 600)
        guard let text = out["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalAIPipelineError.emptyResult }
        return text
    }

    /// `note` with `text` appended as a new paragraph.
    public static func appending(_ text: String, to note: String) -> String {
        let base = note.hasSuffix("\n") ? note : note + "\n"
        return base + (base.hasSuffix("\n\n") || base == "\n" ? "" : "\n") + text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Free-form instruction edit as exact find/replace pairs. One retry with
    /// the failure reason when an excerpt is missing or ambiguous.
    public func edit(_ note: String, instruction: String) async throws -> LocalAIEditResult {
        var user = "Note:\n\(note)\n\nInstruction: \(instruction)"
        var lastReason = ""
        for attempt in 0 ..< 2 {
            let out = try await json(system: LocalAIPrompts.findReplace, user: user, schema: LocalAISchemas.findReplace, maxTokens: 600)
            let edits = (out["edits"] as? [[String: Any]] ?? []).map {
                LocalAIFindReplace(find: $0["find"] as? String ?? "", replace: $0["replace"] as? String ?? "")
            }
            switch Self.applyFindReplace(note, edits) {
            case .success(let result) where result != note:
                return LocalAIEditResult(edits: edits, result: result)
            case .success:
                lastReason = "no change"
            case .failure(let error):
                lastReason = error.reason
            }
            if attempt == 0 {
                user += "\n\nYour previous edits could not be applied (\(lastReason)). Copy each \"find\" exactly from the note."
            }
        }
        throw LocalAIPipelineError.editNotApplicable(lastReason)
    }

    public struct FindReplaceFailure: Error, Equatable { public let reason: String }

    /// Applies edits in order; each `find` must occur exactly once.
    public static func applyFindReplace(_ text: String, _ edits: [LocalAIFindReplace]) -> Result<String, FindReplaceFailure> {
        guard !edits.isEmpty else { return .failure(.init(reason: "no edits")) }
        var text = text
        for edit in edits {
            guard !edit.find.isEmpty else { return .failure(.init(reason: "empty excerpt")) }
            let count = text.components(separatedBy: edit.find).count - 1
            guard count == 1, let range = text.range(of: edit.find) else {
                return .failure(.init(reason: count == 0 ? "excerpt not found: \(edit.find.prefix(50))" : "excerpt occurs \(count) times: \(edit.find.prefix(50))"))
            }
            text.replaceSubrange(range, with: edit.replace)
        }
        return .success(text)
    }

    /// A new note: title and Markdown body.
    public func create(instruction: String, reference: String? = nil) async throws -> (title: String, body: String) {
        let prefix = reference.map { "Reference note:\n\($0)\n\n" } ?? ""
        let out = try await json(system: LocalAIPrompts.create, user: "\(prefix)Instruction: \(instruction)",
                                 schema: LocalAISchemas.create, maxTokens: 1200)
        let title = (out["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = out["body"] as? String ?? ""
        guard !title.isEmpty || !body.isEmpty else { throw LocalAIPipelineError.emptyResult }
        return (title, body)
    }

    /// Property (frontmatter) changes as operations; the app writes them with
    /// its own frontmatter code.
    public func properties(_ current: [String: LocalAIPropertyValue], instruction: String) async throws -> [LocalAIPropertyOperation] {
        let data = try JSONSerialization.data(withJSONObject: current.mapValues(\.json), options: [.sortedKeys])
        let user = "Current properties:\n\(String(decoding: data, as: UTF8.self))\n\nInstruction: \(instruction)"
        let out = try await json(system: LocalAIPrompts.properties, user: user, schema: LocalAISchemas.properties, maxTokens: 200)
        let ops: [LocalAIPropertyOperation] = (out["ops"] as? [[String: Any]] ?? []).compactMap { op in
            guard let key = (op["key"] as? String)?.trimmingCharacters(in: .whitespaces), !key.isEmpty,
                  let kind = (op["op"] as? String).flatMap(LocalAIPropertyOperation.Kind.init(rawValue:)) else { return nil }
            return LocalAIPropertyOperation(kind: kind, key: key, values: op["value"] as? [String] ?? [])
        }
        guard !ops.isEmpty else { throw LocalAIPipelineError.invalidOutput }
        return ops
    }

    /// Lists stay lists; a single value on a scalar property stays scalar.
    public static func applying(_ ops: [LocalAIPropertyOperation], to current: [String: LocalAIPropertyValue]) -> [String: LocalAIPropertyValue] {
        var updated = current
        for op in ops {
            switch op.kind {
            case .remove: updated.removeValue(forKey: op.key)
            case .set:
                if case .list = current[op.key] { updated[op.key] = .list(op.values) }
                else if op.values.count == 1 { updated[op.key] = .text(op.values[0]) }
                else { updated[op.key] = .list(op.values) }
            }
        }
        return updated
    }

    // MARK: Helpers

    private func json(system: String, user: String, schema: String, maxTokens: Int) async throws -> [String: Any] {
        let raw: String
        do {
            raw = try await model.generateJSON(system: system, user: user, schema: schema, maxTokens: maxTokens)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // e.g. the constrained output hit its token budget.
            throw LocalAIPipelineError.invalidOutput
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { throw LocalAIPipelineError.invalidOutput }
        return object
    }

    static func uniqueIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.enumerated().map { index, raw in
            var id = raw.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\", with: "")
            if id.isEmpty { id = "n\(index + 1)" }
            var candidate = id
            var n = 2
            while !seen.insert(candidate).inserted { candidate = "\(id)-\(n)"; n += 1 }
            return candidate
        }
    }

    public static func stripThinking(_ s: String) -> String {
        var out = s
        while let open = out.range(of: "<think>"), let close = out.range(of: "</think>", range: open.upperBound ..< out.endIndex) {
            out.removeSubrange(open.lowerBound ..< close.upperBound)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum LocalAILanguage {
    /// Dominant language code of `text` (on-device NaturalLanguage), "en" if unsure.
    public static func detect(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return "en" }
        let code = language.rawValue
        return code.hasPrefix("zh") ? "zh" : code
    }

    /// English name of a language code ("pt" → "Portuguese").
    public static func name(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }
}

public enum LocalAIGrounding {
    /// A quote is grounded when each of its parts (split on ellipses) appears
    /// in the notes, ignoring case, accents, whitespace and Markdown marks.
    public static func isGrounded(_ quote: String, in corpus: String) -> Bool {
        let strip = { (s: String) in LocalAIText.normalize(s).filter { !"*_`|#>".contains($0) && !$0.isWhitespace } }
        let c = strip(corpus)
        let parts = quote.replacingOccurrences(of: "…", with: "...").components(separatedBy: "...")
            .map(strip).filter { $0.count >= 4 && !$0.hasPrefix("<note") && $0 != "</note>" }
        return !parts.isEmpty && parts.allSatisfy { c.contains($0) }
    }
}
