import Foundation

/// Provider-neutral result; the workspace journal owns permission and execution.
struct MacAgentCompletion: Sendable {
    let content: String
    let reasoning: String
    let calls: [NativeAgentCall]
    let inputTokens: Int?
    let outputTokens: Int?
    init(json: String) throws {
        let failure = VaultFailure(message: "The provider returned unsupported agent calls or usage. The saved run is retained.")
        guard json.utf8.count <= 2_000_000,
              let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let content = value["content"] as? String, content.utf8.count <= 400_000,
              let raw = value["toolCalls"] as? [[String: Any]] else { throw failure }
        let calls = try JSONDecoder().decode([NativeAgentCall].self, from: JSONSerialization.data(withJSONObject: raw))
        guard calls.count <= 12, Set(calls.map(\.id)).count == calls.count,
              calls.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && $0.name.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil && $0.arguments.utf8.count <= 400_000 && (try? JSONSerialization.jsonObject(with: Data($0.arguments.utf8))) is [String: Any] }),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty else { throw failure }
        let usage = value["usage"] as? [String: Any] ?? [:]
        func tokens(_ key: String) throws -> Int? {
            guard let raw = usage[key], !(raw is NSNull) else { return nil }
            guard let count = NativeHistory.integer(raw), (0...1_000_000).contains(count) else { throw failure }
            return count
        }
        let reasoning = value["reasoning"] as? String ?? ""
        guard reasoning.utf8.count <= 400_000 else { throw failure }
        self.content = content; self.reasoning = reasoning; self.calls = calls
        inputTokens = try tokens("inputTokens"); outputTokens = try tokens("outputTokens")
    }
}
