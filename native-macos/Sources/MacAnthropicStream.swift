import Foundation

/// Messages API events use named content blocks rather than chat-completion
/// choices. Unknown future events are ignored; known transitions stay strict.
struct MacAnthropicStream {
    private var frames = MacSSEFrames()
    private var started = false, tools = false
    private var blocks: [Int: String] = [:]
    private(set) var text = "", reasoning = "", finishReason: String?, completed = false
    mutating func accept(_ byte: UInt8) throws -> String? { try frames.accept(byte).flatMap { try event($0) } }
    private mutating func event(_ data: String) throws -> String? {
        guard let bytes = data.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let type = object["type"] as? String else { throw VaultFailure(message: "Anthropic returned an unsupported stream event. The partial reply is retained.") }
        if type == "error" { throw VaultFailure(message: "Anthropic reported an error during the reply. Check the connection and model; the partial reply is retained.") }
        var piece = ""
        switch type {
        case "message_start":
            guard !started, let message = object["message"] as? [String: Any], message["role"] as? String == "assistant", (message["content"] as? [Any])?.isEmpty == true else { throw malformed() }
            started = true
        case "content_block_start":
            guard started, !completed, let index = object["index"] as? Int, index >= 0, blocks[index] == nil, let block = object["content_block"] as? [String: Any], let kind = block["type"] as? String else { throw malformed() }
            blocks[index] = kind
            if kind == "tool_use" || kind == "server_tool_use" { tools = true }
            if kind == "text" { guard let value = block["text"] as? String else { throw malformed() }; piece = value }
            if kind == "thinking" { reasoning += block["thinking"] as? String ?? "" }
        case "content_block_delta":
            guard started, !completed, let index = object["index"] as? Int, let kind = blocks[index], let delta = object["delta"] as? [String: Any], let deltaType = delta["type"] as? String else { throw malformed() }
            if deltaType == "text_delta" { guard kind == "text", let value = delta["text"] as? String else { throw malformed() }; piece = value }
            if deltaType == "thinking_delta" { guard kind == "thinking", let value = delta["thinking"] as? String else { throw malformed() }; reasoning += value }
        case "content_block_stop":
            guard started, let index = object["index"] as? Int, blocks.removeValue(forKey: index) != nil else { throw malformed() }
        case "message_delta":
            guard started, let delta = object["delta"] as? [String: Any] else { throw malformed() }
            if let reason = delta["stop_reason"] as? String { finishReason = reason; if reason == "tool_use" { tools = true } }
        case "message_stop":
            guard started, blocks.isEmpty, finishReason != nil else { throw malformed() }
            completed = true
        default: break
        }
        text += piece
        guard text.utf8.count <= 2 * 1024 * 1024, reasoning.utf8.count <= 2 * 1024 * 1024 else { throw VaultFailure(message: "The provider reply exceeded 2 MB. Its partial text is retained.") }
        return piece.isEmpty ? nil : piece
    }
    private func malformed() -> VaultFailure { VaultFailure(message: "Anthropic returned an incomplete or out-of-order reply. Its partial text is retained.") }
    mutating func finish() throws -> (MacAICompletion, String?) {
        let delta = try frames.finish().flatMap { try event($0) }
        guard completed else { throw VaultFailure(message: "The connection ended before Anthropic completed its reply. Partial text is retained.") }
        try Self.validate(text: text, tools: tools, reason: finishReason)
        return (.init(text: text, reasoning: reasoning, finishReason: finishReason), delta)
    }
    static func validate(text: String, tools: Bool, reason: String?) throws {
        if tools { throw VaultFailure(message: "Anthropic requested tools. Native tool execution is still being connected; partial text is retained.") }
        if reason == "max_tokens" || reason == "model_context_window_exceeded" { throw VaultFailure(message: "Anthropic reached its reply or context limit. Partial text is retained; ask a follow-up to continue.") }
        guard ["end_turn", "stop_sequence", "refusal"].contains(reason ?? "") else { throw VaultFailure(message: "Anthropic paused or returned an unsupported completion reason. Partial text is retained.") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 2 * 1024 * 1024 else { throw VaultFailure(message: "Anthropic completed without a supported text reply.") }
    }
    static func response(_ data: Data) throws -> (completion: MacAICompletion, tools: Bool) {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["type"] as? String == "message", object["role"] as? String == "assistant", let blocks = object["content"] as? [[String: Any]], let reason = object["stop_reason"] as? String else { throw VaultFailure(message: "Anthropic returned an unsupported text response.") }
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        let reasoning = blocks.filter { $0["type"] as? String == "thinking" }.compactMap { $0["thinking"] as? String }.joined()
        let tools = blocks.contains { ["tool_use", "server_tool_use"].contains($0["type"] as? String ?? "") } || reason == "tool_use"
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 2 * 1024 * 1024 else { throw VaultFailure(message: "Anthropic completed without a supported text reply.") }
        guard reasoning.utf8.count <= 2 * 1024 * 1024 else { throw VaultFailure(message: "Anthropic returned an oversized reasoning response.") }
        return (.init(text: text, reasoning: reasoning, finishReason: reason), tools)
    }
}
