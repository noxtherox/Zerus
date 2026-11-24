import SwiftUI
import ZerusChatGPTCore

struct MacChatGPTSelection: Equatable, Sendable { let accountID: String; let model: String }

@MainActor final class MacChatGPTConnection: ObservableObject {
    static let shared = MacChatGPTConnection(manager: ChatGPTManager(service: "com.zerus.notes.macos.native.chatgpt", session: MacAIClient.protectedSession()))
    private let manager: ChatGPTManager
    @Published private(set) var state: CloudAIStatusResponse?
    @Published private(set) var models: [CloudAIModelResponse] = []
    @Published private(set) var busy = false
    @Published private(set) var activeRequests = 0
    @Published private(set) var accessIssue: String?
    private var operationOwner: UUID?
    private var catalogAccountID: String?
    init(manager: ChatGPTManager) { self.manager = manager }
    func refreshStatus() async {
        do { state = try await manager.restoreStatus(); accessIssue = nil }
        catch is CancellationError {} catch { state = manager.status(); accessIssue = error.localizedDescription }
    }
    func selection() async throws -> MacChatGPTSelection {
        guard !busy else { throw VaultFailure(message: "Finish the ChatGPT account operation before sending.") }
        let status = try await manager.restoreStatus(); state = status; accessIssue = nil
        guard !busy else { throw VaultFailure(message: "Finish the ChatGPT account operation before sending.") }
        guard status.configured, !status.model.isEmpty, let account = status.accounts?.first(where: { $0.active && $0.connected }) else { throw VaultFailure(message: "Continue with ChatGPT and choose a model in Connection before sending.") }
        return .init(accountID: account.id, model: status.model)
    }
    var contextWindow: Int? { models.first { $0.id == state?.model }?.contextWindow }
    private func loadModels() async throws {
        let available = try await manager.models().models
        let status = manager.status()
        models = available; state = status; catalogAccountID = status.accounts?.first(where: { $0.active })?.id
    }
    private func change(owner: UUID, _ action: () async throws -> Void) async throws {
        guard !busy, activeRequests == 0 else { throw VaultFailure(message: "Finish active ChatGPT replies before changing its accounts or model.") }
        operationOwner = owner; busy = true
        defer { operationOwner = nil; busy = false; state = manager.status() }
        try Task.checkCancellation(); try await action(); try Task.checkCancellation()
    }
    func connect(owner: UUID, addAccount: Bool = false) async throws {
        try await change(owner: owner) { try await manager.signIn(addAccount: addAccount); try await loadModels() }
    }
    func selectAccount(_ id: String, owner: UUID) async throws {
        try await change(owner: owner) { try await manager.selectAccount(id); try await loadModels() }
    }
    func refreshModels(owner: UUID) async throws {
        try await change(owner: owner) { try await loadModels() }
    }
    func selectModel(_ id: String, owner: UUID) async throws {
        try await change(owner: owner) { try await manager.configureModel(id) }
    }
    func signOut(owner: UUID) async throws {
        try await change(owner: owner) { try await manager.signOut(); models = []; catalogAccountID = nil }
    }
    func cancel(owner: UUID) { if operationOwner == owner { manager.cancelSignIn() } }
    func stream(selection expected: MacChatGPTSelection, conversationID: String, messages: [MacAIMessage], onDelta: @escaping @MainActor (String) -> Void) async throws -> MacAICompletion {
        return try await withRequest(selection: expected) {
            let input = messages.filter { $0.role != "system" }
            guard input.count <= 256, input.allSatisfy({ ["user", "assistant"].contains($0.role) && ($0.images.isEmpty || $0.role == "user" && $0.images.count <= 4) }) else { throw VaultFailure(message: "This conversation is too large for the ChatGPT account transport. Start a new conversation; its history is retained.") }
            let agent: [String: Any] = ["systemPrompt": messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n"), "continuationID": conversationID,
                "messages": input.map { message in ["role": message.role, "content": message.content, "images": message.images.map { ["mediaType": "image/jpeg", "data": $0.base64EncodedString()] }] }]
            let data = try JSONSerialization.data(withJSONObject: agent, options: [.withoutEscapingSlashes])
            let hasImages = input.contains { !$0.images.isEmpty }
            guard data.count <= (hasImages ? 24 : 2) * 1024 * 1024 else { throw VaultFailure(message: "The ChatGPT request exceeds the native context limit. Start a new conversation or reduce context; nothing was sent.") }
            let result = try await boundedGenerate(json: String(decoding: data, as: UTF8.self), limit: 2 * 1024 * 1024, onDelta: onDelta)
            guard result.answer.utf8.count <= 2 * 1024 * 1024, !result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VaultFailure(message: "ChatGPT returned an empty or oversized answer. Partial text is retained.") }
            let response = try result.agentResponseJSON.map { try MacConversations.object(Data($0.utf8)) }
            guard (response?["toolCalls"] as? [Any])?.isEmpty != false else { throw VaultFailure(message: "ChatGPT requested tools. Native tool execution is still being connected; partial text is retained.") }
            return .init(text: result.answer, reasoning: response?["reasoning"] as? String ?? "", finishReason: response?["finishReason"] as? String)
        }
    }
    private func withRequest<T>(selection expected: MacChatGPTSelection, operation: () async throws -> T) async throws -> T {
        guard try await selection() == expected else { throw VaultFailure(message: "The ChatGPT account or model changed while this question was saved. Review Connection, then retry the saved question.") }
        activeRequests += 1; defer { activeRequests -= 1; state = manager.status() }
        if catalogAccountID != expected.accountID || !models.contains(where: { $0.id == expected.model }) {
            try await loadModels()
            // Discovery can choose a new default if a restored model retired.
            // Publish that choice for review; never silently route this turn.
            guard try await selection() == expected else { throw VaultFailure(message: "The ChatGPT account or model changed after discovery. Review Connection, then retry the saved question.") }
        }
        try Task.checkCancellation()
        return try await operation()
    }
    func agentContextWindow(selection expected: MacChatGPTSelection) async throws -> Int? {
        try await withRequest(selection: expected) { models.first { $0.id == expected.model }?.contextWindow }
    }
    func streamAgent(selection expected: MacChatGPTSelection, request: MacAgentRequest, onDelta: @escaping @MainActor (String) -> Void) async throws -> MacAgentCompletion {
        try await withRequest(selection: expected) {
            guard request.json.utf8.count <= 18_000_000 else { throw VaultFailure(message: "This AI request exceeds the native context limit. Nothing was sent.") }
            let result = try await boundedGenerate(json: request.json, limit: 400_000, onDelta: onDelta)
            guard let json = result.agentResponseJSON else { throw VaultFailure(message: "ChatGPT returned an unsupported agent response. Its saved run is retained.") }
            return try MacAgentCompletion(json: json)
        }
    }

    private func boundedGenerate(json: String, limit: Int, onDelta: @escaping @MainActor (String) -> Void) async throws -> CloudAIGenerateResponse {
        var size = 0, exceeded = false
        // Provider-limit cancellation belongs to this child, so the caller can
        // still persist its failure journal. A user Stop cancels both tasks.
        let worker = Task {
            try await manager.generate(.init(prompt: "", images: nil, streamId: UUID().uuidString, agentRequestJSON: json)) { piece in
                size += piece.utf8.count
                guard size <= limit else { exceeded = true; withUnsafeCurrentTask { $0?.cancel() }; return }
                onDelta(piece)
            }
        }
        let result: CloudAIGenerateResponse
        do { result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() }) }
        catch {
            if exceeded { throw VaultFailure(message: "ChatGPT reached the reply size limit. Partial text and the saved run are retained.") }
            throw error
        }
        guard !exceeded else { throw VaultFailure(message: "ChatGPT reached the reply size limit. Partial text and the saved run are retained.") }
        try Task.checkCancellation(); return result
    }

}
