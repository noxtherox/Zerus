import Foundation

/// Exact organization snapshots travel with their proposal and Undo receipt.
/// Platforms without the planner can display them but cannot apply them.
struct NativeAgentOrganization: Codable, Sendable {
    struct Dependency: Codable, Equatable, Sendable {
        let path: String
        let sha256: String?
    }
    struct Binding: Codable, Equatable, Sendable {
        let notePath: String
        let reference: String
        let resolved: String?
    }
    var version = 1
    let changes: [VaultFileChange]
    let dependencies: [Dependency]
    let mappings: [String: String]
    let bindings: [Binding]
    let created: [String: Double]
    var schemaSemantics: [String: String]? = nil
    static func notePath(_ path: String) -> Bool {
        NativeAgentNote.ordinary(path) || path.hasPrefix(".trash/") && NativeAgentNote.ordinary(String(path.dropFirst(7)))
    }
    func validate() throws {
        let metadata: Set<String> = [".zerus/properties.json", ".zerus/links.json", ".zerus/tasks.json"]
        guard version == 1, !changes.isEmpty, changes.count <= 1000, Set(changes.map(\.path)).count == changes.count,
              changes.allSatisfy({ Self.notePath($0.path) || metadata.contains($0.path) }),
              Set(dependencies.map(\.path)).count == dependencies.count,
              dependencies.allSatisfy({ $0.sha256.map { $0.count == 64 && $0.allSatisfy(\.isHexDigit) } ?? true }),
              dependencies.allSatisfy({ NativeAgentNote.readable($0.path) || Self.notePath($0.path) || metadata.contains($0.path) }),
              schemaSemantics.map({ $0.count <= 1000 && $0.allSatisfy { Self.notePath($0.key) && $0.value.count == 64 && $0.value.allSatisfy(\.isHexDigit) } }) ?? true,
              mappings.allSatisfy({ Self.notePath($0.key) && Self.notePath($0.value) }) else {
            throw VaultFailure(message: "This organization proposal has unsupported file changes. Its journal is kept.")
        }
    }
    static func reboundTasks(_ bytes: Data, source: String, target: String) throws -> Data? {
        let raw = try NativeJSON.object(with: bytes); var object = raw as? [String: Any]
        guard var rows = (object?["tasks"] ?? raw) as? [Any] else { throw VaultFailure(message: "The supporting-note task index is unsupported. Resolve it before filing notes.") }
        var changed = false
        for index in rows.indices {
            guard var row = rows[index] as? [String: Any], let rawLinks = row["linkedNoteIds"] else { continue }
            guard let links = rawLinks as? [String] else { throw VaultFailure(message: "A task has unsupported supporting-note links.") }
            let updated = links.map { $0 == source ? target : $0 }
            if updated != links { row["linkedNoteIds"] = updated; rows[index] = row; changed = true }
        }
        guard changed else { return nil }
        if object != nil { object!["tasks"] = rows }
        return try JSONSerialization.data(withJSONObject: object.map { $0 as Any } ?? rows, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    /// Merge only the links changed by filing; later task writing remains intact.
    static func undoTasks(before: Data?, after: Data?, current: Data, source: NativeAgentNote, target: NativeAgentNote) throws -> Data {
        if let before, let after, current == after { return before }
        func rows(_ data: Data) throws -> ([String: Any]?, [[String: Any]]) {
            let raw = try NativeJSON.object(with: data), object = raw as? [String: Any]
            guard let values = (object?["tasks"] ?? raw) as? [[String: Any]] else { throw VaultFailure(message: "The supporting-note task index is unsupported.") }
            return (object, values)
        }
        var (object, values) = try rows(current)
        if let before, let after {
            let old = try rows(before).1, saved = try rows(after).1
            guard old.count == saved.count else { throw VaultFailure(message: "The receipt's supporting-note links changed.") }
            for index in old.indices where (old[index]["linkedNoteIds"] as? [String]) != (saved[index]["linkedNoteIds"] as? [String]) {
                guard let id = saved[index]["id"] as? String,
                      saved.filter({ $0["id"] as? String == id }).count == 1,
                      old.filter({ $0["id"] as? String == id }).count == 1 else {
                    if current == after { return before }
                    throw VaultFailure(message: "Ambiguous supporting-note links changed after organization.")
                }
                let matches = values.indices.filter { values[$0]["id"] as? String == id }
                if matches.isEmpty { continue } // A deleted task stays deleted.
                guard matches.count == 1, let currentIndex = matches.first,
                      values[currentIndex]["linkedNoteIds"] as? [String] == saved[index]["linkedNoteIds"] as? [String] else {
                    throw VaultFailure(message: "The supporting-note links changed after organization. Undo kept the newer links.")
                }
                values[currentIndex]["linkedNoteIds"] = old[index]["linkedNoteIds"]
            }
        }
        for index in values.indices {
            guard let raw = values[index]["linkedNoteIds"] else { continue }
            guard let links = raw as? [String] else { throw VaultFailure(message: "A task has unsupported supporting-note links.") }
            values[index]["linkedNoteIds"] = links.map { link in
                if source.path != target.path && link == target.path { return source.document.stableID ?? source.path }
                if source.id != target.id && link == target.id { return source.document.stableID ?? source.path }
                return link
            }
        }
        if object != nil { object!["tasks"] = values }
        let result = try JSONSerialization.data(withJSONObject: object.map { $0 as Any } ?? values, options: [.sortedKeys, .withoutEscapingSlashes])
        // Keep byte formatting when the semantic task document did not change.
        let original = try NativeJSON.object(with: current) as! NSObject
        return original.isEqual(try NativeJSON.object(with: result)) ? current : result
    }
    func validate(proposal: NativeAgentProposal) throws {
        try validate()
        guard Set(proposal.befores.map(\.path)).count == proposal.befores.count, Set(proposal.afters.map(\.path)).count == proposal.afters.count else { throw VaultFailure(message: "This organization proposal has duplicate note paths.") }
        let before = Dictionary(uniqueKeysWithValues: proposal.befores.map { ($0.path, Data($0.content.utf8)) })
        let after = Dictionary(uniqueKeysWithValues: proposal.afters.map { ($0.path, Data($0.content.utf8)) })
        let expected = Set(before.keys).union(after.keys).sorted().compactMap { path -> VaultFileChange? in
            before[path] == after[path] ? nil : .init(path: path, before: before[path], after: after[path])
        }
        guard changes.filter({ Self.notePath($0.path) }).sorted(by: { $0.path < $1.path }) == expected,
              created.keys.allSatisfy({ after[$0] != nil }), created.values.allSatisfy(\.isFinite) else { throw VaultFailure(message: "Organization file changes do not match their displayed note snapshots.") }
        for change in changes where !Self.notePath(change.path) {
            guard change.path == ".zerus/tasks.json", let original = change.before, let source = proposal.before,
                  source.path != proposal.after.path,
                  try Self.reboundTasks(original, source: source.path, target: proposal.after.document.stableID ?? proposal.after.path) == change.after else { throw VaultFailure(message: "Organization metadata contains changes beyond supporting-note link repair.") }
        }
    }
}
