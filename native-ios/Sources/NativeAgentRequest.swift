import Foundation

struct NativeAgentRequest: Sendable {
    let json: String
    let estimatedInput: Int
    let outputLimit: Int
    static func prepare(_ run: NativeAgentRun, store: NativeChatAttachmentStore) async throws -> Self {
        let worker = Task.detached(priority: .userInitiated) { () async throws -> Self in
            try await prepared(run, store: store)
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
    private static func prepared(_ run: NativeAgentRun, store: NativeChatAttachmentStore) async throws -> Self {
        try Task.checkCancellation()
        guard run.requestReservation == nil else { throw VaultFailure(message: "An earlier request has not finished. Reopen its saved journal and explicitly continue to account for the interrupted allowance.") }
        guard run.canRequest else { throw VaultFailure(message: "This run reached its saved step, time or token limit. Its journal and proposals are kept; start a new request with different limits.") }
        guard run.messages.count <= 240 else { throw VaultFailure(message: "This run’s conversation is too large to send. Its full journal is kept; start a new request with the relevant notes.") }
        let prompt = NativeAgentController.systemPrompt(run), limits = run.budget
        let text = try JSONEncoder().encode(run.messages)
        guard text.count <= 2_000_000 else { throw VaultFailure(message: "This run’s text exceeds the native request size limit. Its full journal is kept.") }
        let prepared = try NativeChatAttachmentInput.providerMessages(run, store: store)
        var request: [String: Any] = ["continuationID": run.id.uuidString.lowercased(), "systemPrompt": prompt, "messages": prepared.messages, "tools": NativeAgentTools.schemas(mode: run.mode), "maxOutputTokens": limits.maxOutputTokens, "effort": limits.effort.rawValue]
        var estimate = request
        estimate["messages"] = prepared.messages.map { message in
            var next = message
            if let images = message["images"] as? [[String: String]] { next["images"] = images.map { ["mediaType": $0["mediaType"] ?? ""] } }
            return next
        }
        let estimateBytes = try JSONSerialization.data(withJSONObject: estimate, options: [.sortedKeys, .withoutEscapingSlashes])
        let input = Int(ceil(Double(try await NativeAgentTokenizer.shared.count(String(decoding: estimateBytes, as: UTF8.self))) * 1.2)) + prepared.imageCount * 4096
        guard input <= limits.maxInputTokens else { throw VaultFailure(message: "The next request needs about \(input.formatted()) input tokens, above this run’s \(limits.maxInputTokens.formatted()) context limit. Its journal is kept; use less context or start a new request with a larger limit.") }
        let remaining = limits.maxTotalTokens - run.inputTokens - run.outputTokens
        guard remaining - input >= 1000 else { throw VaultFailure(message: "This run’s remaining token budget cannot fit another response. Its journal and proposals are kept; start a new request with a larger limit or less context.") }
        let output = min(limits.maxOutputTokens, remaining - input); request["maxOutputTokens"] = output
        let bytes = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys, .withoutEscapingSlashes])
        guard bytes.count <= 18_000_000 else { throw VaultFailure(message: "This request exceeds the native size limit. Its full journal is kept; choose fewer or shorter attachments.") }
        try Task.checkCancellation(); return .init(json: String(decoding: bytes, as: UTF8.self), estimatedInput: input, outputLimit: output)
    }
    static func outputTokens(content: String, calls: [NativeAgentCall]) async throws -> Int {
        let bytes = try JSONEncoder().encode(calls)
        return Int(ceil(Double(try await NativeAgentTokenizer.shared.count(content + String(decoding: bytes, as: UTF8.self))) * 1.2))
    }
}
