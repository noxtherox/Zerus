import Foundation

struct MacAgentProviderBinding: Codable, Equatable, Sendable {
    let version: Int
    let kind: String
    let endpoint: String
    let model: String
    let account: String?
    static func read(_ record: NativeAgentRecord) throws -> Self? {
        let object = try NativeJSON.object(with: record.metadataBytes) as? [String: Any]
        guard let value = object?["macProvider"] else { return nil }
        let binding = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: value))
        guard binding.version == 1, ["compatible", "anthropic", "chatgpt"].contains(binding.kind), !binding.model.isEmpty else { throw VaultFailure(message: "This run's Mac provider binding is unreadable. Its journal is retained.") }
        return binding
    }
}

@MainActor enum MacAgentProvider {
    case api(profile: MacAIProfile, key: String)
    case chatGPT(connection: MacChatGPTConnection, selection: MacChatGPTSelection)
    var binding: MacAgentProviderBinding {
        get throws {
            switch self {
            case .api(let profile, let key):
                guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !profile.model.isEmpty else { throw VaultFailure(message: "Choose a saved model and API key before starting the run.") }
                return .init(version: 1, kind: profile.provider.format.rawValue, endpoint: try MacAIClient.endpoint(profile.endpoint).absoluteString, model: profile.model, account: nil)
            case .chatGPT(_, let selection):
                return .init(version: 1, kind: "chatgpt", endpoint: "https://api.openai.com/v1/responses", model: selection.model, account: NativeHistory.hash(Data(selection.accountID.utf8)))
            }
        }
    }
    func contextCapacity() async throws -> Int? {
        switch self {
        case .api(let profile, _): return profile.contextWindow
        case .chatGPT(let connection, let selection): return try await connection.agentContextWindow(selection: selection)
        }
    }
    func validateCapacity(_ request: MacAgentRequest) async throws {
        let capacity = try await contextCapacity()
        if let capacity, request.estimatedInput + request.outputLimit > capacity {
            throw MacAgentContextLimit("The prepared input and output allowance exceed this model's context capacity; nothing was sent.")
        }
    }
    func send(_ request: MacAgentRequest, client: MacAIClient, continuations: MacAnthropicContinuations, onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws -> MacAgentCompletion {
        switch self {
        case .api(let profile, let key):
            if profile.provider.format == .anthropic { return try await client.streamAnthropicAgent(endpoint: profile.endpoint, model: profile.model, apiKey: key, request: request, continuations: continuations, onDelta: onDelta) }
            return try await client.streamCompatibleAgent(endpoint: profile.endpoint, model: profile.model, apiKey: key, request: request, onDelta: onDelta)
        case .chatGPT(let connection, let selection): return try await connection.streamAgent(selection: selection, request: request, onDelta: onDelta)
        }
    }
}

extension VaultFiles {
    func bindMacAgentProvider(_ record: NativeAgentRecord, owner: String, binding: MacAgentProviderBinding) throws -> NativeAgentRecord {
        _ = try agentChecked(record, owner: owner)
        var object = try NativeJSON.object(with: agentEncode(record.run, previous: record.bytes)) as! [String: Any]
        object["macProvider"] = try NativeJSON.object(with: JSONEncoder().encode(binding))
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        let storage = try agentJournalChanges(bytes, previous: record.bytes, id: record.id)
        try applyTransaction(storage.changes, historySource: "ai-provider")
        return storage.record
    }
}
