import Foundation

struct NativeAgentLimits: Codable, Equatable, Sendable {
    enum Effort: String, Codable, CaseIterable, Identifiable, Sendable {
        case low, medium, high
        var id: String { rawValue }
    }
    var maxSteps = 30
    var maxOutputTokens = 8192
    var maxInputTokens = 48_000
    var maxMinutes = 10
    var maxTotalTokens = 160_000
    var effort = Effort.medium
    static let defaults = NativeAgentLimits()
    static let problem = VaultFailure(message: "The saved AI limits are unsupported or out of range. Their original file is kept; correct it in Files or reload a valid version before starting a new request.")
    func validate() throws {
        guard (2...100).contains(maxSteps), (1024...32768).contains(maxOutputTokens),
              (4096...200_000).contains(maxInputTokens), (1...30).contains(maxMinutes), (8000...1_000_000).contains(maxTotalTokens) else { throw Self.problem }
    }
    static func read(_ bytes: Data?) throws -> Self {
        guard let bytes else { return defaults }
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw problem }
        var value = defaults
        for (key, path) in [("maxSteps", \Self.maxSteps), ("maxOutputTokens", \Self.maxOutputTokens), ("maxInputTokens", \Self.maxInputTokens), ("maxMinutes", \Self.maxMinutes), ("maxTotalTokens", \Self.maxTotalTokens)] {
            if let item = object[key] { guard let number = NativeHistory.integer(item) else { throw problem }; value[keyPath: path] = number }
        }
        if let raw = object["effort"] { guard let text = raw as? String, let effort = Effort(rawValue: text) else { throw problem }; value.effort = effort }
        try value.validate(); return value
    }
}

struct NativeAgentLimitsSnapshot: Sendable {
    let root: URL
    let bytes: Data?
    let limits: NativeAgentLimits
}

struct NativeAgentRequestReservation: Codable, Sendable {
    let id: UUID
    let input: Int
    let output: Int
}

extension VaultFiles {
    func agentLimits() throws -> NativeAgentLimitsSnapshot {
        let bytes = try agentMetadata([(".zerus/ai/settings.json", 256_000)])[0]
        return .init(root: root, bytes: bytes, limits: try NativeAgentLimits.read(bytes))
    }
    func saveAgentLimits(_ value: NativeAgentLimits, expected: NativeAgentLimitsSnapshot) throws -> NativeAgentLimitsSnapshot {
        guard expected.root == root else { throw VaultFailure(message: "These AI limits belong to another vault. Reopen its settings here.") }
        try value.validate()
        var bytes = expected.bytes
        if value != expected.limits {
            var object: [String: Any] = [:]
            if let original = expected.bytes {
                guard let decoded = try JSONSerialization.jsonObject(with: original) as? [String: Any] else { throw NativeAgentLimits.problem }; object = decoded
            }
            guard let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] else { throw NativeAgentLimits.problem }
            for (key, field) in fields { object[key] = field }
            bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
            guard bytes!.count <= 256_000 else { throw NativeAgentLimits.problem }
        }
        try applyTransaction([.init(path: ".zerus/ai/settings.json", before: expected.bytes, after: bytes)], historySource: "ai-settings")
        return .init(root: root, bytes: bytes, limits: value)
    }
    func agentElapsed(_ record: NativeAgentRecord, owner: String, seconds: Double) throws -> NativeAgentRecord {
        guard seconds.isFinite, seconds >= 0 else { throw VaultFailure(message: "This AI run has an invalid elapsed time. Its journal was kept.") }
        var run = try agentChecked(record, owner: owner)
        guard seconds > 0 else { return record }; run.activeSeconds += seconds
        return try agentStore(run, previous: record.bytes)
    }
    func agentReserveRequest(_ record: NativeAgentRecord, owner: String, input: Int, output: Int) throws -> NativeAgentRecord {
        var run = try agentChecked(record, owner: owner)
        guard run.canRequest, run.pendingCalls.isEmpty, run.question == nil,
              input >= 0, input <= run.budget.maxInputTokens, (1...run.budget.maxOutputTokens).contains(output),
              input + output <= run.budget.maxTotalTokens - run.inputTokens - run.outputTokens else { throw VaultFailure(message: "This run cannot reserve another request within its saved limits. Its journal is kept.") }
        run.requestReservation = .init(id: UUID(), input: input, output: output); run.steps += 1
        run.event("Requested model step \(run.steps), reserving \(input) input and \(output) output tokens.")
        return try agentStore(run, previous: record.bytes)
    }
}
