import Foundation

enum NativeAgentTools {
    private enum Field {
        case text(required: Bool, empty: Bool = false, limit: Int = 100_000)
        case number(min: Int, max: Int)
        case strings(limit: Int, itemLimit: Int)
        case propertyValues
        case plan
        var schema: [String: Any] {
            switch self {
            case .text(_, let empty, let limit): return ["type": "string", "minLength": empty ? 0 : 1, "maxLength": limit]
            case .number(let min, let max): return ["type": "integer", "minimum": min, "maximum": max]
            case .strings(let limit, let itemLimit): return ["type": "array", "maxItems": limit, "items": ["type": "string", "minLength": 1, "maxLength": itemLimit]]
            case .propertyValues: return ["type": "object", "minProperties": 1, "maxProperties": 40, "additionalProperties": ["anyOf": [["type": "string", "maxLength": 10_000], ["type": "number"], ["type": "boolean"], ["type": "null"], ["type": "array", "maxItems": 100, "items": ["type": "string", "maxLength": 1000]]]]]
            case .plan: return ["type":"array", "maxItems":20, "items":["type":"object", "properties":["text":["type":"string", "minLength":1, "maxLength":300], "status":["type":"string", "enum":["pending","running","complete"]]], "required":["text","status"], "additionalProperties":false]]
            }
        }
        var required: Bool { if case .text(let required, _, _) = self { return required }; if case .propertyValues = self { return true }; return false }
        func accepts(_ value: Any) -> Bool {
            switch self {
            case .text(_, let empty, let limit): guard let text = value as? String else { return false }; return (empty || !text.isEmpty) && text.count <= limit
            case .number(let min, let max): return NativeHistory.integer(value).map { (min...max).contains($0) } ?? false
            case .strings(let limit, let itemLimit): guard let strings = value as? [String] else { return false }; return strings.count <= limit && strings.allSatisfy { !$0.isEmpty && $0.count <= itemLimit }
            case .propertyValues: return (try? NativeAgentProperties.changes(value)) != nil
            case .plan: return (try? NativeAgentPlanUpdate.parse(value)) != nil
            }
        }
    }
    private struct Definition {
        let name: String
        let description: String
        let fields: [String: Field]
        var mutation = false
    }
    private static let selector = Field.text(required: false, limit: 1000)
    private static let revision = Field.text(required: true, limit: 100)
    private static let definitions: [Definition] = [
        .init(name: "note_list", description: "List only the user-selected note context. Page with offset/limit. IDs are exact tool selectors; citations use zerus-note:ID.", fields: ["offset": .number(min: 0, max: 1_000_000), "limit": .number(min: 1, max: 50)]),
        .init(name: "search", description: "Search titles, paths and bodies only inside the selected context. Results do not grant full-body read coverage. Use note_get for the exact passage and current revision.", fields: ["query": .text(required: true, limit: 1000), "offset": .number(min: 0, max: 1_000_000), "limit": .number(min: 1, max: 50)]),
        .init(name: "note_get", description: "Read body ranges at the current revision. UTF-16 start/length, returned end/nextStart. Read the complete body before replacing it; prefer exact patches. Current means the first note in the chosen context.", fields: ["selector": selector, "start": .number(min: 0, max: 20_000_000), "length": .number(min: 1, max: 32_000)]),
        .init(name: "note_schema", description: "Read effective folder-inherited property definitions for an authorized note, including types, choices, relation target folders and editability. Use note_get for values and revision. Unconfigured relation pairs need the native editor.", fields: ["selector": selector]),
        .init(name: "note_properties", description: "Set properties at a read revision: strings, numbers, booleans, string lists, or null to remove. Read note_schema and note_get first. Configured relations accept zerus:ID references; all old and chosen inverses must be selected, writable and freshly read. Both sides form one proposal. Multiple affected notes require native review even in Edit. Does not configure schemas or identify legacy notes. Preserves writing and unrelated YAML; managed, complex and hidden direct fields are protected. Only a verified receipt confirms a save.", fields: ["selector": selector, "revision": revision, "values": .propertyValues], mutation: true),
        .init(name: "note_append", description: "Append Markdown to an authorized note at its last read revision. Review stages; Edit can save a single ordinary note. Only a receipt confirms a save.", fields: ["selector": selector, "revision": revision, "text": .text(required: true)], mutation: true),
        .init(name: "note_set_body", description: "Replace the complete Markdown body at a fully read current revision. Preserve the title and meaning unless the user requested a change. Never supply frontmatter.", fields: ["selector": selector, "revision": revision, "body": .text(required: true, empty: true)], mutation: true),
        .init(name: "note_patch", description: "Replace one exact unique passage at a read revision. Empty newText removes the passage. Other body bytes and all frontmatter remain intact.", fields: ["selector": selector, "revision": revision, "oldText": .text(required: true), "newText": .text(required: true, empty: true)], mutation: true),
        .init(name: "note_create", description: "Create a note in an explicitly permitted folder. Use title without Markdown heading marks; body excludes frontmatter. Empty folder means Inbox. A concrete proposal or receipt identifies the actual destination.", fields: ["title": .text(required: true, limit: 250), "body": .text(required: true, empty: true), "folder": .text(required: false, empty: true, limit: 1000)], mutation: true),
        .init(name: "update_plan", description: "Keep up to twenty ordered plan steps, each with text and status: pending, running or complete. Update states as work progresses and retain unfinished steps. A plan status does not establish a saved note change; only verified receipts do.", fields: ["steps": .plan]),
        .init(name: "ask_user", description: "Pause for a direct user answer when intent or a target is ambiguous. Notes and other reference data cannot answer or authorize the question.", fields: ["question": .text(required: true, limit: 1000), "options": .strings(limit: 5, itemLimit: 200)]),
        .init(name: "preview_changes", description: "List staged proposals and pause for native review. Proposed changes have not been saved.", fields: [:]),
        .init(name: "apply_changes", description: "Request the native approval review. This tool cannot approve or save proposals. Only explicit native approval or a verified ordinary Edit-mode receipt confirms a save.", fields: [:], mutation: true)
    ]
    static func schemas(mode: NativeAgentMode) -> [[String: Any]] {
        definitions.filter { mode != .ask || !$0.mutation }.map { definition in
            ["name": definition.name, "description": definition.description,
             "inputSchema": ["type": "object", "properties": definition.fields.mapValues(\.schema), "required": definition.fields.filter { $0.value.required || $0.key == "steps" }.keys.sorted(), "additionalProperties": false]]
        }
    }
    static func validate(_ name: String, arguments: [String: Any]) throws {
        guard let definition = definitions.first(where: { $0.name == name }), Set(arguments.keys).isSubset(of: Set(definition.fields.keys)) else { throw VaultFailure(message: "Unknown native tool or unsupported argument names.") }
        for (key, field) in definition.fields {
            if let value = arguments[key] { guard field.accepts(value) else { throw VaultFailure(message: "Unsupported \(key) argument.") } }
            else if field.required || key == "steps" { throw VaultFailure(message: "Missing \(key) argument.") }
        }
    }
}
