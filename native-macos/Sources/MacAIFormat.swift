import Foundation

enum MacAIFormat: String, CaseIterable, Identifiable, Sendable {
    case compatible, anthropic
    var id: String { rawValue }
    var label: String { self == .anthropic ? "Anthropic" : "Compatible API" }
    var defaultEndpoint: String { self == .anthropic ? "https://api.anthropic.com/v1/messages" : "https://api.openai.com/v1/chat/completions" }
}

/// Shared by live Send and Retry. Provider authentication never enters the
/// portable conversation or the provider-independent message history.
enum MacAIRequest {
    static func make(endpoint: String, model: String, apiKey: String, messages: [MacAIMessage], format: MacAIFormat, maxOutputTokens: Int) throws -> URLRequest {
        let url = try MacAIClient.endpoint(endpoint), model = model.trimmingCharacters(in: .whitespacesAndNewlines), key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !key.isEmpty, key.rangeOfCharacter(from: .controlCharacters) == nil else { throw VaultFailure(message: "Save a model and API key in Connection before sending.") }
        guard !messages.isEmpty, messages.count <= 512, messages.allSatisfy({ ["system", "user", "assistant"].contains($0.role) }) else { throw VaultFailure(message: "This conversation is too large or has unsupported message roles. Start a new conversation; its history is retained.") }
        let imageBytes = messages.flatMap(\.images).reduce(0) { $0 + $1.count }
        guard imageBytes <= 16 * 1024 * 1024, messages.allSatisfy({ $0.images.isEmpty || $0.role == "user" && $0.images.count <= 4 && $0.images.allSatisfy { !$0.isEmpty && $0.count <= 3 * 1024 * 1024 } }) else { throw VaultFailure(message: "This conversation has too many images for one request. Start a new conversation; its existing history is retained.") }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let body: [String: Any]
        if format == .anthropic {
            guard (1...4096).contains(maxOutputTokens) else { throw VaultFailure(message: "Choose an output budget between 1 and 4,096 tokens.") }
            request.setValue(key, forHTTPHeaderField: "x-api-key"); request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            let input: [[String: Any]] = messages.filter { $0.role != "system" }.map { message in
                var parts: [[String: Any]] = message.images.map { ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0.base64EncodedString()]] }
                if !message.content.isEmpty { parts.append(["type": "text", "text": message.content]) }
                return ["role": message.role, "content": parts]
            }
            guard !input.isEmpty, messages.filter({ $0.role != "system" }).allSatisfy({ !$0.content.isEmpty || !$0.images.isEmpty }) else { throw VaultFailure(message: "This conversation contains an empty message. Start a new conversation; its original history is kept.") }
            var value: [String: Any] = ["model": model, "messages": input, "stream": true, "max_tokens": maxOutputTokens]
            let system = messages.filter { $0.role == "system" }.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n\n")
            if !system.isEmpty { value["system"] = system }
            body = value
        } else {
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            body = ["model": model, "messages": messages.map(\.object), "stream": true]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let limit = imageBytes == 0 ? 2 * 1024 * 1024 : 24 * 1024 * 1024
        guard (request.httpBody?.count ?? 0) <= limit else { throw VaultFailure(message: "The selected conversation and context exceed the request limit. Reduce context or start a new conversation; nothing was sent.") }
        return request
    }
}
