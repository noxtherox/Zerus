import Foundation

enum MacAnthropicAgentFailure: LocalizedError {
    case refused, limited, paused, provider(String), http(Int)
    var errorDescription: String? {
        switch self {
        case .refused: return "Anthropic refused this reply. Its partial output was discarded; the saved run is retained."
        case .limited: return "Anthropic reached its reply or context limit. The saved run and partial text are retained."
        case .paused: return "Anthropic paused before finishing the turn. The saved run is retained; retry explicitly."
        case .provider(let kind): return "Anthropic reported " + kind + ". The saved run and partial text are retained."
        case .http(let status): return "Anthropic returned HTTP \(status). Check the selected connection and model; the saved run is retained."
        }
    }
}
struct MacAnthropicAgentStream {
    private var frames = MacSSEFrames(), started = false
    private var payloadBytes = 0
    private var blocks: [Int: [String: Any]] = [:], input: [Int: String] = [:], open = Set<Int>(), usage: [String: Any] = [:], reason: String?
    private(set) var completed = false
    private static func malformed() -> VaultFailure { VaultFailure(message: "Anthropic returned incomplete or unsupported agent blocks. The saved run and partial text are retained.") }
    mutating func accept(_ byte: UInt8) throws -> String? { try frames.accept(byte).flatMap { try event($0) } }
    private mutating func event(_ data: String) throws -> String? {
        guard !completed, let object = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any], let type = object["type"] as? String else { throw Self.malformed() }
        var piece: String?
        switch type {
        case "error": throw MacAnthropicAgentFailure.provider((object["error"] as? [String: Any])?["type"] as? String ?? "a stream error")
        case "message_start":
            guard !started, let message = object["message"] as? [String: Any], message["role"] as? String == "assistant", (message["content"] as? [Any])?.isEmpty == true else { throw Self.malformed() }
            started = true; usage = message["usage"] as? [String: Any] ?? [:]
        case "content_block_start":
            guard started, reason == nil, let index = NativeHistory.integer(object["index"]), index == blocks.count, index < 48, let block = object["content_block"] as? [String: Any], let kind = block["type"] as? String, ["text", "thinking", "redacted_thinking", "tool_use"].contains(kind) else { throw Self.malformed() }
            payloadBytes += try JSONSerialization.data(withJSONObject: block).count
            blocks[index] = block; open.insert(index)
            if kind == "text" { guard let text = block["text"] as? String else { throw Self.malformed() }; piece = text }
            if kind == "tool_use" { guard block["input"] is [String: Any] else { throw Self.malformed() } }
        case "content_block_delta":
            guard started, reason == nil, let index = NativeHistory.integer(object["index"]), open.contains(index), var block = blocks[index], let kind = block["type"] as? String, let delta = object["delta"] as? [String: Any], let deltaType = delta["type"] as? String else { throw Self.malformed() }
            payloadBytes += ["text", "thinking", "signature", "partial_json"].compactMap { delta[$0] as? String }.reduce(0) { $0 + $1.utf8.count }
            switch deltaType {
            case "text_delta":
                guard kind == "text", let text = delta["text"] as? String else { throw Self.malformed() }; block["text"] = (block["text"] as? String ?? "") + text; piece = text
            case "thinking_delta":
                guard kind == "thinking", let text = delta["thinking"] as? String else { throw Self.malformed() }; block["thinking"] = (block["thinking"] as? String ?? "") + text
            case "signature_delta":
                guard kind == "thinking", let signature = delta["signature"] as? String else { throw Self.malformed() }; block["signature"] = (block["signature"] as? String ?? "") + signature
            case "input_json_delta":
                guard kind == "tool_use", let partial = delta["partial_json"] as? String, (block["input"] as? [String: Any])?.isEmpty == true else { throw Self.malformed() }
                input[index, default: ""] += partial
                guard (input[index]?.utf8.count ?? 0) <= 400_000 else { throw Self.malformed() }
            default: throw Self.malformed()
            }
            blocks[index] = block
        case "content_block_stop":
            guard started, let index = NativeHistory.integer(object["index"]), open.remove(index) != nil, var block = blocks[index] else { throw Self.malformed() }
            if let json = input[index], !json.isEmpty {
                guard let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { throw Self.malformed() }; block["input"] = value
            }
            blocks[index] = block
        case "message_delta":
            guard started, open.isEmpty, let delta = object["delta"] as? [String: Any] else { throw Self.malformed() }
            if let next = delta["stop_reason"] as? String { guard reason == nil || reason == next else { throw Self.malformed() }; reason = next }
            if let reported = object["usage"] as? [String: Any] { usage.merge(reported.filter { !($0.value is NSNull) }) { _, new in new } }
        case "message_stop":
            guard started, open.isEmpty, reason != nil else { throw Self.malformed() }; completed = true
        default: break // Future event types do not change known block transitions.
        }
        guard payloadBytes <= 2_000_000 else { throw Self.malformed() }
        return piece?.isEmpty == true ? nil : piece
    }
    mutating func finish() throws -> (MacAgentCompletion, [[String: Any]], String?) {
        let last = try frames.finish().flatMap { try event($0) }
        guard completed, open.isEmpty else { throw Self.malformed() }
        let ordered = blocks.keys.sorted().compactMap { blocks[$0] }
        return (try Self.normalized(blocks: ordered, usage: usage, reason: reason), ordered, last)
    }
    static func normalized(blocks: [[String: Any]], usage: [String: Any], reason: String?) throws -> MacAgentCompletion {
        if reason == "refusal" { throw MacAnthropicAgentFailure.refused }
        if ["max_tokens", "model_context_window_exceeded"].contains(reason ?? "") { throw MacAnthropicAgentFailure.limited }
        if reason == "pause_turn" { throw MacAnthropicAgentFailure.paused }
        guard blocks.count <= 48, ["end_turn", "stop_sequence", "tool_use"].contains(reason ?? "") else { throw malformed() }
        var content = "", thinking = "", calls: [[String: String]] = []
        for block in blocks {
            switch block["type"] as? String {
            case "text": guard let text = block["text"] as? String else { throw malformed() }; content += text
            case "thinking":
                guard let text = block["thinking"] as? String, let signature = block["signature"] as? String, !signature.isEmpty, signature.utf8.count <= 400_000 else { throw malformed() }; thinking += text
            case "redacted_thinking": guard let data = block["data"] as? String, !data.isEmpty, data.utf8.count <= 400_000 else { throw malformed() }
            case "tool_use":
                guard let id = block["id"] as? String, let name = block["name"] as? String, let input = block["input"] as? [String: Any] else { throw malformed() }
                calls.append(["id": id, "name": name, "arguments": String(decoding: try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)])
            default: throw malformed()
            }
        }
        guard (reason == "tool_use") == !calls.isEmpty else { throw malformed() }
        func count(_ key: String) throws -> Int? {
            guard let raw = usage[key], !(raw is NSNull) else { return nil }
            guard let value = NativeHistory.integer(raw), (0...1_000_000).contains(value) else { throw malformed() }; return value
        }
        var reported: [String: Int] = [:]
        let input = try count("input_tokens"), cached = try count("cache_read_input_tokens"), created = try count("cache_creation_input_tokens")
        if let input { reported["inputTokens"] = input + (cached ?? 0) + (created ?? 0) }
        reported["outputTokens"] = try count("output_tokens")
        let result: [String: Any] = ["content": content, "reasoning": thinking, "toolCalls": calls, "usage": reported]
        return try MacAgentCompletion(json: String(decoding: JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
    static func response(_ data: Data) throws -> (MacAgentCompletion, [[String: Any]]) {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["type"] as? String == "message", object["role"] as? String == "assistant", let blocks = object["content"] as? [[String: Any]] else { throw malformed() }
        return (try normalized(blocks: blocks, usage: object["usage"] as? [String: Any] ?? [:], reason: object["stop_reason"] as? String), blocks)
    }
}

extension MacAIClient {
    func streamAnthropicAgent(endpoint: String, model: String, apiKey: String, request agent: MacAgentRequest, continuations: MacAnthropicContinuations, onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws -> MacAgentCompletion {
        guard let source = try JSONSerialization.jsonObject(with: Data(agent.json.utf8)) as? [String: Any], let id = source["continuationID"] as? String, let run = UUID(uuidString: id) else { throw VaultFailure(message: "This Anthropic run has no valid continuation identity.") }
        let cache = continuations.bound(endpoint: try Self.endpoint(endpoint).absoluteString, model: model.trimmingCharacters(in: .whitespacesAndNewlines), apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines), run: run)
        let (request, messages, system) = try MacAnthropicAgentRequest.make(endpoint: endpoint, model: model, apiKey: apiKey, agent: agent, continuations: cache)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw VaultFailure(message: "Anthropic returned an unsupported HTTP response.") }
        guard (200..<300).contains(http.statusCode) else { throw MacAnthropicAgentFailure.http(http.statusCode) }
        let result: MacAgentCompletion, blocks: [[String: Any]]
        if http.mimeType?.lowercased().contains("json") == true {
            var data = Data()
            for try await byte in bytes { try Task.checkCancellation(); guard data.count < 2_000_000 else { throw VaultFailure(message: "The Anthropic agent reply exceeded its size limit.") }; data.append(byte) }
            (result, blocks) = try MacAnthropicAgentStream.response(data)
            try Task.checkCancellation(); if !result.content.isEmpty { await onDelta(result.content) }
        } else {
            var stream = MacAnthropicAgentStream()
            for try await byte in bytes { try Task.checkCancellation(); if let text = try stream.accept(byte) { await onDelta(text) }; if stream.completed { break } }
            let (reply, content, last) = try stream.finish(); if let last { await onDelta(last) }; result = reply; blocks = content
        }
        try Task.checkCancellation()
        try cache.save(messages: messages, reply: result, blocks: blocks, system: system)
        return result
    }
}
