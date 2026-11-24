import Foundation

struct NativeAgentPreferences: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        case ask, review, edit
        var id: String { rawValue }
        var native: NativeAgentMode { switch self { case .ask: return .ask; case .review: return .review; case .edit: return .edit } }
        init(_ mode: NativeAgentMode) { switch mode { case .ask: self = .ask; case .review: self = .review; case .edit: self = .edit } }
    }
    enum WriteScope: String, Codable, CaseIterable, Identifiable, Sendable { case context, current; var id: String { rawValue } }
    var mode = Mode.review
    var writeScope = WriteScope.context
    var textFallback = false
    var workers = false
    init() {}
    private enum CodingKeys: String, CodingKey { case mode, writeScope, textFallback, workers }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? values.decode(Mode.self, forKey: .mode)) ?? .review
        writeScope = (try? values.decode(WriteScope.self, forKey: .writeScope)) ?? .context
        textFallback = (try? values.decode(Bool.self, forKey: .textFallback)) ?? false
        workers = (try? values.decode(Bool.self, forKey: .workers)) ?? false
    }
    static func read(_ bytes: Data?) throws -> Self {
        guard let bytes else { return .init() }
        do { return try JSONDecoder().decode(Self.self, from: bytes) }
        catch { throw VaultFailure(message: "The saved AI run preferences are unsupported. Their original file is kept; correct or reload it before starting a new run.") }
    }
}
struct NativeAgentPreferencesSnapshot: Sendable {
    let root: URL
    let bytes: Data?
    let value: NativeAgentPreferences
    var needsNormalization: Bool {
        guard let bytes, let original = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let encoded = try? JSONEncoder().encode(value), let normalized = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else { return false }
        return normalized.contains { key, value in
            guard let existing = original[key] else { return false }
            return (try? JSONSerialization.data(withJSONObject: [key: existing], options: .sortedKeys)) != (try? JSONSerialization.data(withJSONObject: [key: value], options: .sortedKeys))
        }
    }
}
extension VaultFiles {
    func agentPreferences() throws -> NativeAgentPreferencesSnapshot {
        let bytes = try agentMetadata([(".zerus/ai/settings.json", 256_000)])[0]
        return .init(root: root, bytes: bytes, value: try NativeAgentPreferences.read(bytes))
    }
    func saveAgentPreferences(_ value: NativeAgentPreferences, expected: NativeAgentPreferencesSnapshot) throws -> NativeAgentPreferencesSnapshot {
        guard expected.root == root else { throw VaultFailure(message: "These AI preferences belong to another vault. Reopen them here before saving.") }
        var bytes = expected.bytes
        if value != expected.value || expected.needsNormalization {
            var object: [String: Any] = [:]
            if let original = expected.bytes {
                guard let decoded = try JSONSerialization.jsonObject(with: original) as? [String: Any] else { throw VaultFailure(message: "AI settings must remain a JSON object. Their original file is kept.") }
                object = decoded
            }
            let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
            for (key, field) in fields { object[key] = field }
            bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
            guard bytes!.count <= 256_000 else { throw VaultFailure(message: "AI settings are too large. Their original file is kept.") }
        }
        try applyTransaction([.init(path: ".zerus/ai/settings.json", before: expected.bytes, after: bytes)], historySource: "ai-settings")
        return .init(root: root, bytes: bytes, value: value)
    }
}
