import Foundation
import CoreFoundation

enum NativeAgentProperties {
    static func changes(_ raw: Any) throws -> [String: NativePropertyValue?] {
        guard let values = raw as? [String: Any], !values.isEmpty, values.count <= 40,
              Set(values.keys.map { $0.lowercased() }).count == values.count else { throw VaultFailure(message: "Choose one to forty distinct property names.") }
        var result: [String: NativePropertyValue?] = [:]
        for (name, raw) in values {
            guard name.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_ .-]{0,59}$"#, options: .regularExpression) != nil,
                  !name.lowercased().hasPrefix("zerus-") else { throw VaultFailure(message: "Use ordinary property names. Zerus-managed properties are reserved.") }
            let value: NativePropertyValue?
            if raw is NSNull { value = nil }
            else if let text = raw as? String, text.count <= 10_000 { value = .text(text) }
            else if let number = raw as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { value = .checkbox(number.boolValue) }
                else {
                    let decimal = NSDecimalNumber(decimal: number.decimalValue)
                    guard number.doubleValue.isFinite, decimal.doubleValue.isFinite else { throw VaultFailure(message: "Use a finite property number.") }
                    value = .number(decimal.stringValue)
                }
            } else if let list = raw as? [String], list.count <= 100, list.allSatisfy({ $0.count <= 1000 }) { value = .list(list) }
            else { throw VaultFailure(message: "Property values must be text, finite numbers, checkboxes, text lists or null to remove a value.") }
            // A dictionary's nil subscript removes the key; preserve an explicit
            // optional value so JSON null remains a requested deletion.
            result.updateValue(value, forKey: name)
        }
        return result
    }
    static func changes(_ call: NativeAgentCall) throws -> [String: NativePropertyValue?] {
        guard call.name == "note_properties", let arguments = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any] else { throw VaultFailure(message: "Unsupported property proposal.") }
        try NativeAgentTools.validate(call.name, arguments: arguments)
        return try changes(arguments["values"] as Any)
    }
    static func properties(_ note: NoteDocument) -> ([String: Any], [String]) {
        var values: [String: Any] = [:], unsupported: [String] = []
        for entry in NativeFrontmatter(note.content).entries where !entry.key.lowercased().hasPrefix("zerus-") {
            switch entry.value {
            case .text(let text): values[entry.key] = text
            case .checkbox(let flag): values[entry.key] = flag
            case .list(let list): values[entry.key] = list
            case .number(let text):
                let number = NSDecimalNumber(string: text)
                if number.doubleValue.isFinite { values[entry.key] = number }
                else { unsupported.append(entry.key) }
            case nil: unsupported.append(entry.key)
            }
        }
        return (values, Array(Set(unsupported)).sorted())
    }
    static func definitions(_ schema: NativeSchemaSnapshot, path: String) throws -> [[String: Any]] {
        try schema.checkedEffective(notePath: path).filter { !$0.name.lowercased().hasPrefix("zerus-") }.map { definition in
            var value: [String: Any] = ["name": definition.name, "type": definition.type.rawValue, "owner": definition.owner,
                "editable": !definition.hidden && definition.type != .unsupported && (definition.type != .relation || definition.relationPairID != nil)]
            if definition.type == .list { value["options"] = definition.options; value["multiple"] = definition.multiple }
            if definition.type == .relation {
                value["multiple"] = definition.relationMultiple
                value["targetFolder"] = definition.relationTypeKey ?? ""
                value["notice"] = definition.relationPairID == nil ? "Configure the reciprocal relation in the native editor first." : "Every existing and chosen inverse note must be selected, writable and read at its current revision. Use zerus:ID references. Linked changes are reviewed together."
            }
            return value
        }
    }
    static func validateOrdinary(_ name: String, value: NativePropertyValue?, definitions: [NativePropertyDefinition]) throws {
        if let definition = definitions.first(where: { $0.id == name.lowercased() }) {
            guard definition.type != .relation else { throw VaultFailure(message: "Edit relations through the native relation editor so reciprocal values are updated together.") }
            try definition.validateValue(value)
        }
    }
    static func applying(_ call: NativeAgentCall, to note: NoteDocument, schema: NativeSchemaSnapshot) throws -> String {
        let values = try changes(call), definitions = try schema.checkedEffective(notePath: note.path)
        var content = note.content
        for name in values.keys.sorted() {
            let value = values[name]!
            try validateOrdinary(name, value: value, definitions: definitions)
            content = try NativeFrontmatter(content).setting(name, value: value)
        }
        guard NoteDocument.split(content).body == note.parts.body,
              NativeAgentNote.identity(.init(path: note.path, content: content, modified: note.modified)) == NativeAgentNote.identity(note) else { throw VaultFailure(message: "Property edits must preserve the note’s writing and identity.") }
        return content
    }
    static func undo(_ call: NativeAgentCall, before: NoteDocument, after: NoteDocument, current: NoteDocument, schema: NativeSchemaSnapshot) throws -> String {
        guard try applying(call, to: before, schema: schema) == after.content else { throw VaultFailure(message: "The property proposal or its definitions changed. Review the current values before restoring them.") }
        let values = try changes(call), definitions = try schema.checkedEffective(notePath: current.path)
        let old = NativeFrontmatter(before.content), saved = NativeFrontmatter(after.content), fresh = NativeFrontmatter(current.content)
        var content = current.content
        for name in values.keys.sorted() {
            let expected = saved.entry(name), present = fresh.entry(name), original = old.entry(name)
            guard expected == nil || expected?.value != nil, present == nil || present?.value != nil,
                  original == nil || original?.value != nil, present?.value == expected?.value else { throw VaultFailure(message: "\(name) changed after this receipt. Undo would replace newer work.") }
            try validateOrdinary(name, value: original?.value, definitions: definitions)
            content = try NativeFrontmatter(content).setting(name, value: original?.value)
        }
        // Restore exact original header bytes when no independent metadata was
        // edited, while still retaining the latest body.
        if fresh.header == saved.header { content = old.header + fresh.body }
        return content
    }
}
