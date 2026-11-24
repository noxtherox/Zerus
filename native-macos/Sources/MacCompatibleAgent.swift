import Foundation

/// The prepared run contains frozen context; credentials remain request headers.
enum MacCompatibleAgentRequest {
    static func make(endpoint: String, model: String, apiKey: String, agent: MacAgentRequest) throws -> URLRequest {
        let url = try MacAIClient.endpoint(endpoint), key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines), model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let failure = VaultFailure(message: "This agent request or API connection is unsupported. Its saved run is retained.")
        guard !key.isEmpty, key.rangeOfCharacter(from: .controlCharacters) == nil, !model.isEmpty, agent.json.utf8.count <= 18_000_000,
              let source = try JSONSerialization.jsonObject(with: Data(agent.json.utf8)) as? [String: Any],
              let system = source["systemPrompt"] as? String, !system.isEmpty,
              let incoming = source["messages"] as? [[String: Any]], !incoming.isEmpty, incoming.count <= 240,
              let tools = source["tools"] as? [[String: Any]], tools.count <= 50,
              let output = NativeHistory.integer(source["maxOutputTokens"]), (1...32768).contains(output) else { throw failure }
        var messages: [[String: Any]] = [["role": "system", "content": system]], imageCount = 0
        for message in incoming {
            guard let role = message["role"] as? String, ["user", "assistant", "tool"].contains(role), let text = message["content"] as? String else { throw failure }
            var item: [String: Any] = ["role": role, "content": text]
            if let images = message["images"] as? [[String: String]], !images.isEmpty {
                imageCount += images.count
                guard role == "user", imageCount <= 4 else { throw failure }
                var parts: [[String: Any]] = [["type": "text", "text": text]]
                for image in images {
                    guard let media = image["mediaType"], ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(media), let data = image["data"], data.count <= 4_200_000, Data(base64Encoded: data) != nil else { throw failure }
                    parts.append(["type": "image_url", "image_url": ["url": "data:\(media);base64,\(data)"]])
                }
                item["content"] = parts
            }
            if let calls = message["toolCalls"] as? [[String: String]], !calls.isEmpty {
                guard role == "assistant", calls.count <= 12 else { throw failure }
                item["tool_calls"] = try calls.map { call -> [String: Any] in
                    guard let id = call["id"], !id.isEmpty, let name = call["name"], let arguments = call["arguments"] else { throw failure }
                    return ["id": id, "type": "function", "function": ["name": name, "arguments": arguments]]
                }
            }
            if role == "tool" { guard let id = message["toolCallId"] as? String, !id.isEmpty else { throw failure }; item["tool_call_id"] = id }
            messages.append(item)
        }
        let functions = try tools.map { tool -> [String: Any] in
            guard let name = tool["name"] as? String, let schema = tool["inputSchema"] as? [String: Any] else { throw failure }
            return ["type": "function", "function": ["name": name, "description": tool["description"] as? String ?? "", "parameters": schema]]
        }
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true, "max_tokens": output, "stream_options": ["include_usage": true]]
        if !functions.isEmpty { body["tools"] = functions; body["tool_choice"] = "auto" }
        if url.host?.lowercased() == "openrouter.ai", let effort = source["effort"] as? String, ["low", "medium", "high"].contains(effort) { body["reasoning"] = ["effort": effort] }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        guard (request.httpBody?.count ?? 0) <= 18_000_000 else { throw failure }
        return request
    }
}

struct MacCompatibleAgentStream {
    private var frames = MacSSEFrames()
    private var content = "", reasoning = "", calls: [Int: NativeAgentCall] = [:], usage: [String: Any] = [:], finishReason: String?
    private(set) var completed = false
    private static func malformed() -> VaultFailure { VaultFailure(message: "The API returned incomplete or unsupported agent calls. Its saved run and partial text are retained.") }
    mutating func accept(_ byte: UInt8) throws -> String? { try frames.accept(byte).flatMap { try event($0) } }
    private mutating func event(_ data: String) throws -> String? {
        if data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" { completed = true; return nil }
        guard let object = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any], object["error"] == nil else { throw Self.malformed() }
        if let reported = object["usage"] as? [String: Any] { usage.merge(reported) { _, new in new } }
        guard let choices = object["choices"] as? [[String: Any]] else {
            if object["choices"] == nil, object["usage"] is [String: Any] { return nil }
            throw Self.malformed()
        }
        guard !choices.isEmpty else { return nil }
        guard choices.count == 1, let choice = choices.first, choice["index"] == nil || NativeHistory.integer(choice["index"]) == 0 else { throw Self.malformed() }
        let delta = choice["delta"] as? [String: Any] ?? [:]
        try Self.validateFields(delta)
        let piece = delta["content"] as? String ?? delta["refusal"] as? String ?? "", thought = delta["reasoning_content"] as? String ?? delta["reasoning"] as? String ?? ""
        let fragments = delta["tool_calls"] as? [[String: Any]] ?? []
        guard finishReason == nil || piece.isEmpty && thought.isEmpty && fragments.isEmpty else { throw Self.malformed() }
        for fragment in fragments {
            let explicit = NativeHistory.integer(fragment["index"])
            let id = fragment["id"] as? String
            let known = calls.first { $0.value.id == id }?.key
            let single = calls.count == 1 && (id == nil || calls.values.first?.id == id) ? calls.keys.first : nil
            guard let index = explicit ?? (fragment["index"] == nil ? known ?? single ?? (calls.isEmpty ? 0 : nil) : nil), (0..<12).contains(index), fragment["type"] == nil || fragment["type"] as? String == "function" else { throw Self.malformed() }
            var call = calls[index] ?? .init(id: "", name: "", arguments: "")
            if let id = fragment["id"] as? String { guard call.id.isEmpty || call.id == id else { throw Self.malformed() }; call.id = id }
            if let function = fragment["function"] as? [String: Any] {
                for key in ["name", "arguments"] where function[key] != nil { guard function[key] is String else { throw Self.malformed() } }
                if let name = function["name"] as? String { guard call.name.isEmpty || call.name == name else { throw Self.malformed() }; call.name = name }
                call.arguments += function["arguments"] as? String ?? ""
            } else if fragment["function"] != nil { throw Self.malformed() }
            guard call.id.count <= 200, call.name.count <= 64, call.arguments.utf8.count <= 400_000 else { throw Self.malformed() }
            calls[index] = call
        }
        if let reason = choice["finish_reason"] as? String { guard finishReason == nil || finishReason == reason else { throw Self.malformed() }; finishReason = reason }
        content += piece; reasoning += thought
        guard content.utf8.count <= 400_000, reasoning.utf8.count <= 400_000 else { throw Self.malformed() }
        return piece.isEmpty ? nil : piece
    }
    mutating func finish() throws -> (MacAgentCompletion, String?) {
        let last = try frames.finish().flatMap { try event($0) }
        guard Set(calls.keys) == Set(0..<calls.count) else { throw Self.malformed() }
        return (try Self.normalized(content: content, reasoning: reasoning, calls: calls.keys.sorted().compactMap { calls[$0] }, usage: usage, reason: finishReason), last)
    }
    private static func normalized(content: String, reasoning: String, calls: [NativeAgentCall], usage: [String: Any], reason: String?) throws -> MacAgentCompletion {
        if ["length", "model_context_window_exceeded"].contains(reason ?? "") { throw VaultFailure(message: "The API reached its reply or context limit. Its saved run and partial text are retained.") }
        guard ["stop", "tool_calls"].contains(reason ?? ""), reason != "tool_calls" || !calls.isEmpty else { throw malformed() }
        var counts: [String: Any] = [:]; counts["inputTokens"] = usage["prompt_tokens"]; counts["outputTokens"] = usage["completion_tokens"]
        let calls = calls.map { call in var call = call; if call.arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { call.arguments = "{}" }; return call }
        let callObjects = try JSONSerialization.jsonObject(with: JSONEncoder().encode(calls))
        let object: [String: Any] = ["content": content, "reasoning": reasoning, "toolCalls": callObjects, "usage": counts]
        return try MacAgentCompletion(json: String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    private static func validateFields(_ value: [String: Any]) throws {
        for key in ["content", "refusal", "reasoning_content", "reasoning"] {
            if let raw = value[key], !(raw is NSNull), !(raw is String) { throw malformed() }
        }
        if let raw = value["tool_calls"], !(raw is NSNull), !(raw is [[String: Any]]) { throw malformed() }
        if let role = value["role"], !(role is NSNull), role as? String != "assistant" { throw malformed() }
    }
    static func response(_ data: Data) throws -> MacAgentCompletion {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] == nil, let choices = object["choices"] as? [[String: Any]], choices.count == 1, let choice = choices.first, choice["index"] == nil || NativeHistory.integer(choice["index"]) == 0, let message = choice["message"] as? [String: Any] else { throw malformed() }
        try validateFields(message)
        let calls = try (message["tool_calls"] as? [[String: Any]] ?? []).map { call -> NativeAgentCall in
            guard call["type"] == nil || call["type"] as? String == "function", let id = call["id"] as? String, let function = call["function"] as? [String: Any], let name = function["name"] as? String, let arguments = function["arguments"] as? String else { throw malformed() }
            return .init(id: id, name: name, arguments: arguments)
        }
        return try normalized(content: message["content"] as? String ?? message["refusal"] as? String ?? "", reasoning: message["reasoning_content"] as? String ?? message["reasoning"] as? String ?? "", calls: calls, usage: object["usage"] as? [String: Any] ?? [:], reason: choice["finish_reason"] as? String)
    }
}

extension MacAIClient {
    func streamCompatibleAgent(endpoint: String, model: String, apiKey: String, request agent: MacAgentRequest, onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws -> MacAgentCompletion {
        let request = try MacCompatibleAgentRequest.make(endpoint: endpoint, model: model, apiKey: apiKey, agent: agent)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw VaultFailure(message: "The API refused this agent request. Check the selected connection; its saved run is retained.") }
        if http.mimeType?.lowercased().contains("json") == true {
            var data = Data()
            for try await byte in bytes { try Task.checkCancellation(); guard data.count < 2_000_000 else { throw VaultFailure(message: "The API agent reply exceeded its size limit.") }; data.append(byte) }
            let result = try MacCompatibleAgentStream.response(data)
            try Task.checkCancellation(); if !result.content.isEmpty { await onDelta(result.content) }; return result
        }
        var stream = MacCompatibleAgentStream()
        for try await byte in bytes { try Task.checkCancellation(); if let text = try stream.accept(byte) { await onDelta(text) }; if stream.completed { break } }
        let (result, last) = try stream.finish(); if let last { await onDelta(last) }; try Task.checkCancellation(); return result
    }
}
