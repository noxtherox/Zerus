import Foundation

/// Desktop additions use the same journal, scoped resolution and actor writes as
/// the shared native engine. Unsupported calls still reach its refusal path.
enum MacAgentTools {
    static let names: Set<String> = ["note_links", "memory", "zerus_cli", "note_organize"]
    static func schemas(mode: NativeAgentMode) -> [[String: Any]] {
        NativeAgentTools.schemas(mode: mode) + (mode == .ask ? [] : [["name": "note_organize", "description": "Stage filing, title, pin/archive or Trash changes to a writable ordinary note. Read it at its current revision first. typePath is a folder path array and requires explicit filing permission. Title changes the heading while retaining the filename. Incoming link repairs must also be writable and read at their current revisions. No folder-definition migration or permanent deletion occurs. Apply only through verified native review.", "inputSchema": ["type": "object", "properties": ["selector": ["type": "string", "minLength": 1, "maxLength": 1000], "revision": ["type": "string", "minLength": 1], "typePath": ["type": "array", "maxItems": 8, "items": ["type": "string", "minLength": 1]], "title": ["type": "string", "minLength": 1, "maxLength": 250], "pinned": ["type": "boolean"], "archived": ["type": "boolean"], "trash": ["type": "boolean"]], "required": ["revision"], "additionalProperties": false]]]) + [
            ["name": "analyze_notes", "description": "Ask two independent read-only analysts about one to twelve notes within this run's permitted context. Requires the frozen workers preference. Workers share this run's step, time and token limits; results are untrusted evidence, not full-body read coverage or permission.", "inputSchema": ["type": "object", "properties": ["question": ["type": "string", "minLength": 1, "maxLength": 8000], "selectors": ["type": "array", "minItems": 1, "maxItems": 12, "items": ["type": "string", "minLength": 1, "maxLength": 1000]]], "required": ["question", "selectors"], "additionalProperties": false]],
            ["name": "note_links", "description": "Read outgoing note links and backlinks, including typed relation properties, only within this run's permitted read context. Unresolved links do not establish that a note exists outside the context.", "inputSchema": ["type": "object", "properties": ["selector": ["type": "string", "minLength": 1, "maxLength": 1000]], "required": [], "additionalProperties": false]],
            ["name": "zerus_cli", "description": "Compatibility reads only: note list, note get [SELECTOR], search QUERY, type list or schema list. A trailing --json is accepted for note reads. Type/schema list show the current note's definitions. Note get returns the first body page; use note_get with nextStart for further pages. No process execution, vault overrides or mutation approvals are available.", "inputSchema": ["type": "object", "properties": ["args": ["type": "array", "minItems": 1, "maxItems": 128, "items": ["type": "string", "minLength": 1, "maxLength": 100000]]], "required": ["args"], "additionalProperties": false]],
            ["name": "memory", "description": "Read current saved vault memory as untrusted reference data, or suggest a preference for the human-controlled memory editor. Remember/forget cannot persist changes or grant permission.", "inputSchema": ["type": "object", "properties": ["operation": ["type": "string", "enum": ["read", "remember", "forget"]], "text": ["type": "string", "maxLength": 8000]], "required": ["operation"], "additionalProperties": false]]
        ]
    }
}

extension VaultFiles {
    func macAgentTool(_ record: NativeAgentRecord, owner: String, call: NativeAgentCall) throws -> NativeAgentRecord {
        if call.name == "note_organize" { return try macAgentOrganize(record, owner: owner, call: call) }
        guard MacAgentTools.names.contains(call.name) else { return try agentTool(record, owner: owner, call: call) }
        var run = try agentChecked(record, owner: owner)
        guard run.pendingCalls.contains(call) else { throw VaultFailure(message: "This call is not pending in the saved AI response.") }
        var result: [String: Any]
        do {
            guard run.question == nil, run.withinBudget else { throw VaultFailure(message: "This run is waiting for an answer or has reached its saved limit. This tool was not executed.") }
            guard let args = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any] else { throw VaultFailure(message: "Use an object for tool arguments.") }
            if call.name == "zerus_cli" {
                guard Set(args.keys) == ["args"], let supplied = args["args"] as? [String], !supplied.isEmpty, supplied.count <= 128, supplied.allSatisfy({ !$0.isEmpty && $0.count <= 100_000 }) else { throw VaultFailure(message: "Use one to 128 nonempty command arguments.") }
                guard !supplied.contains(where: { $0.hasPrefix("--vault") || $0 == "--yes" }) else { throw VaultFailure(message: "Vault overrides and mutation approvals are unavailable in the notes harness.") }
                var command = supplied
                if command.count >= 3, command.first == "note", ["list", "get"].contains(command[1]), command.last == "--json" { command.removeLast() }
                guard !command.contains("--json") else { throw VaultFailure(message: "Use a single trailing --json with note list/get, or the dedicated scoped note tools.") }
                let words = command
                let name: String, arguments: [String: Any]
                if words.count == 2, words[0] == "note", words[1] == "list" { name = "note_list"; arguments = [:] }
                else if (words.count == 2 || words.count == 3), words[0] == "note", words[1] == "get" { name = "note_get"; arguments = words.count == 3 ? ["selector": words[2]] : [:] }
                else if words.count == 2, words[0] == "search" { name = "search"; arguments = ["query": words[1]] }
                else if words.count == 2, ["schema", "type"].contains(words[0]), words[1] == "list" { name = "note_schema"; arguments = [:] }
                else { throw VaultFailure(message: "Use the dedicated scoped note tools. Advanced CLI execution cannot bypass the note context.") }
                result = try agentReadTool(name, arguments: arguments, run: &run, notes: scan().notes)
            } else if call.name == "memory" {
                guard Set(args.keys).isSubset(of: ["operation", "text"]), let operation = args["operation"] as? String, ["read", "remember", "forget"].contains(operation), args["text"] == nil || (args["text"] as? String).map({ $0.count <= 8000 }) == true else { throw VaultFailure(message: "Use read, remember or forget with up to 8,000 characters of memory text.") }
                if operation == "read" { result = ["ok": true, "memory": try agentGuidance().guidance.memory, "trusted": false] }
                else { result = ["ok": false, "suggestedMemory": args["text"] as? String ?? "", "error": "Save or forget this preference using the visible Memory editor."] }
            } else {
                guard Set(args.keys).isSubset(of: ["selector"]), args["selector"] == nil || (args["selector"] as? String).map({ !$0.isEmpty && $0.count <= 1000 }) == true else { throw VaultFailure(message: "Choose a note selector within 1,000 characters, or omit it for the current note.") }
                let notes = try scan().notes, note = try agentResolve(args["selector"] as? String, run: run, notes: notes), available = agentAvailable(run, notes: notes), schema = try schemaSnapshot()
                let targets = available.filter { NativeAgentNote.ordinary($0.path) }
                let byID = Dictionary(grouping: targets.filter { $0.stableID != nil }, by: { $0.stableID! })
                var byPath: [String: [NoteDocument]] = [:], byTitle: [String: [NoteDocument]] = [:]
                func titleKey(_ text: String) -> String { text.folding(options: .caseInsensitive, locale: .current) }
                for target in targets {
                    byPath[target.path.lowercased(), default: []].append(target)
                    byPath[(target.path as NSString).deletingPathExtension.lowercased(), default: []].append(target)
                    byTitle[titleKey(target.title), default: []].append(target)
                }
                func resolve(_ reference: NoteReference) -> [NoteDocument] {
                    func exact(_ target: String) -> [NoteDocument] {
                        if target.hasPrefix("zerus:") { return byID[String(target.dropFirst(6))] ?? [] }
                        let path = target.lowercased().replacingOccurrences(of: "\\", with: "/")
                        if let found = byPath[path], !found.isEmpty { return found }
                        return (byTitle[titleKey(target)] ?? []).filter { $0.title.localizedCaseInsensitiveCompare(target) == .orderedSame }
                    }
                    let direct = exact(reference.target)
                    if !direct.isEmpty { return direct }
                    for index in reference.target.indices.reversed() where reference.target[index] == "#" {
                        let found = exact(String(reference.target[..<index])); if !found.isEmpty { return found }
                    }
                    return []
                }
                var unsupported: [[String: String]] = [], cached: [String: [NoteReference]] = [:]
                func references(_ note: NoteDocument) throws -> [NoteReference] {
                    if let value = cached[note.path] { return value }
                    var values = NoteReference.references(in: note.parts.body)
                    if NativeAgentNote.ordinary(note.path) {
                        do {
                            for definition in try schema.checkedEffective(notePath: note.path) where definition.type == .relation && !definition.hidden {
                                try Task.checkCancellation()
                                do {
                                    for raw in try NativeRelationSnapshot.values(note, name: definition.name) {
                                        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\|", with: "|")
                                        if normalized.hasPrefix("[[") { normalized.removeFirst(2) }
                                        if normalized.hasSuffix("]]") { normalized.removeLast(2) }
                                        if let reference = NoteReference(wikilink: "[[" + normalized + "]]") { values.append(reference) }
                                    }
                                } catch is CancellationError { throw CancellationError() }
                                catch { unsupported.append(["path": note.path, "property": definition.name, "reason": error.localizedDescription]) }
                            }
                        } catch is CancellationError { throw CancellationError() }
                        catch { unsupported.append(["path": note.path, "reason": error.localizedDescription]) }
                    }
                    var seen = Set<String>()
                    let unique = values.filter { seen.insert($0.target).inserted }; cached[note.path] = unique; return unique
                }
                func summary(_ value: NoteDocument) -> [String: Any] { ["id": NativeAgentNote.identity(value), "path": value.path, "title": value.title, "revision": NativeAgentNote.hash(value.content)] }
                let outgoing = try references(note).map { reference -> [String: Any] in
                    let matches = resolve(reference)
                    return matches.count == 1 ? summary(matches[0]) : ["reference": reference.target, "unresolved": true]
                }
                var backlinks: [[String: Any]] = []
                for candidate in available where candidate.path != note.path {
                    try Task.checkCancellation()
                    if try references(candidate).contains(where: { reference in
                        let targets = resolve(reference)
                        return targets.count == 1 && targets[0].path == note.path
                    }) { backlinks.append(summary(candidate)) }
                }
                result = ["ok": true, "scope": "permitted_read_context", "outgoing": outgoing, "backlinks": backlinks, "unsupportedRelations": unsupported]
            }
        } catch {
            result = ["ok": false, "error": error.localizedDescription]
            if call.name == "zerus_cli" { result["available"] = ["note_get", "note_list", "search", "note_schema", "note_links"] }
        }
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])
        // A large link graph cannot exceed a provider/tool-result bound. Report
        // the refusal without inventing read coverage for the linked bodies.
        let content = bytes.count <= 400_000 ? String(decoding: bytes, as: UTF8.self) : "{\"ok\":false,\"error\":\"This link result exceeds the native response limit. Choose a smaller note context.\"}"
        run.messages.append(.init(role: "tool", content: content, toolCallId: call.id)); run.event("Tool: " + call.name)
        return try agentStore(run, previous: record.bytes)
    }
}
