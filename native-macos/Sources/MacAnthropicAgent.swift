import Foundation
import Darwin

/// Private provider state is never a portable grant to resume against a different
/// run, connection or model. The controller retains live runs during cleanup.
struct MacAnthropicContinuations: Sendable {
    let directory: URL
    var runID: UUID? = nil
    private static let fileLimit = 16_000_000
    static var defaultDirectory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/AgentContinuations/Anthropic") }
    static func vault(_ identity: MacAgentFileIdentity) -> Self {
        .init(directory: defaultDirectory.appendingPathComponent(NativeHistory.hash(Data("\(identity.device):\(identity.inode)".utf8))))
    }
    func bound(endpoint: String, model: String, apiKey: String, run: UUID) -> Self {
        .init(directory: directory.appendingPathComponent(NativeHistory.hash(Data((endpoint + "\u{0}" + model + "\u{0}" + apiKey + "\u{0}" + run.uuidString.lowercased()).utf8))), runID: run)
    }
    private func key(_ messages: [[String: Any]]) throws -> String {
        let normalized = messages.map { message in ["role": message["role"] ?? NSNull(), "content": message["content"] ?? "", "toolCalls": message["toolCalls"] ?? [], "toolCallId": message["toolCallId"] ?? NSNull(), "images": message["images"] ?? []] as [String: Any] }
        return NativeHistory.hash(try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys, .withoutEscapingSlashes]))
    }
    func load(_ messages: [[String: Any]]) throws -> (blocks: [[String: Any]], system: String) {
        let hash = try key(messages), file = directory.appendingPathComponent(hash + ".json")
        let failure = VaultFailure(message: "This run's original Anthropic continuation is unavailable for this connection and model on this Mac. Its journal and changes are kept; start a new request.")
        guard let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey]), values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= Self.fileLimit,
              let object = try? JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any], NativeHistory.integer(object["version"]) == 2, object["transcript"] as? String == hash,
              let system = object["system"] as? String, !system.isEmpty, system.utf8.count <= 400_000,
              let blocks = object["blocks"] as? [[String: Any]], let message = messages.last else { throw failure }
        let restored = try MacAnthropicAgentStream.normalized(blocks: blocks, usage: [:], reason: blocks.contains { $0["type"] as? String == "tool_use" } ? "tool_use" : "end_turn")
        let calls = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored.calls))
        guard NSDictionary(dictionary: ["content": restored.content, "toolCalls": calls]).isEqual(to: ["content": message["content"] ?? "", "toolCalls": message["toolCalls"] ?? []]) else { throw failure }
        return (blocks, system)
    }
    private func writePrivate(_ data: Data, to file: URL) throws {
        guard data.count <= Self.fileLimit else { throw VaultFailure(message: "The Anthropic continuation exceeded its private storage limit. The saved run is retained.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "The private Anthropic cache was replaced by a link.") }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent("." + UUID().uuidString)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor); try? FileManager.default.removeItem(at: temporary) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data); try handle.synchronize()
        guard rename(temporary.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    func save(messages: [[String: Any]], reply: MacAgentCompletion, blocks: [[String: Any]], system: String) throws {
        guard let runID, !system.isEmpty, system.utf8.count <= 400_000 else { throw VaultFailure(message: "The Anthropic continuation has no frozen run context.") }
        var transcript = messages
        transcript.append(["role": "assistant", "content": reply.content, "toolCalls": try JSONSerialization.jsonObject(with: JSONEncoder().encode(reply.calls))])
        let hash = try key(transcript), file = directory.appendingPathComponent(hash + ".json")
        let data = try JSONSerialization.data(withJSONObject: ["version": 2, "transcript": hash, "system": system, "blocks": blocks], options: [.sortedKeys, .withoutEscapingSlashes])
        try writePrivate(data, to: file)
        try writePrivate(JSONSerialization.data(withJSONObject: ["version": 1, "run": runID.uuidString.lowercased()]), to: directory.appendingPathComponent("binding.json"))
    }
    private func bindings() throws -> [(URL, UUID)] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).compactMap { child in
            guard child.lastPathComponent.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                  let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink != true,
                  let metadata = try? child.appendingPathComponent("binding.json").resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]), metadata.isSymbolicLink != true, (metadata.fileSize ?? Int.max) <= 1024,
                  let bytes = try? Data(contentsOf: child.appendingPathComponent("binding.json")), bytes.count <= 1024,
                  let manifest = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], NativeHistory.integer(manifest["version"]) == 1, let id = manifest["run"] as? String, let run = UUID(uuidString: id) else { return nil }
            return (child, run)
        }
    }
    func prune(retaining liveRuns: Set<UUID>, olderThan cutoff: Date = Date().addingTimeInterval(-14 * 86400)) throws {
        for (child, id) in try bindings() {
            guard !liveRuns.contains(id) else { continue }
            let modified = try child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantFuture
            if modified < cutoff { try FileManager.default.removeItem(at: child) }
        }
    }
    func remove(run: UUID) throws { for (child, id) in try bindings() where id == run { try FileManager.default.removeItem(at: child) } }
}

enum MacAnthropicAgentRequest {
    static func make(endpoint: String, model: String, apiKey: String, agent: MacAgentRequest, continuations: MacAnthropicContinuations) throws -> (URLRequest, [[String: Any]], String) {
        let url = try MacAIClient.endpoint(endpoint), key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines), model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let failure = VaultFailure(message: "This Anthropic agent request or connection is unsupported. Its saved run is retained.")
        guard !key.isEmpty, key.rangeOfCharacter(from: .controlCharacters) == nil, !model.isEmpty, agent.json.utf8.count <= 18_000_000,
              let source = try JSONSerialization.jsonObject(with: Data(agent.json.utf8)) as? [String: Any], let system = source["systemPrompt"] as? String, !system.isEmpty,
              let incoming = source["messages"] as? [[String: Any]], !incoming.isEmpty, incoming.count <= 240,
              let tools = source["tools"] as? [[String: Any]], tools.count <= 50,
              let output = NativeHistory.integer(source["maxOutputTokens"]), (1...32768).contains(output) else { throw failure }
        var messages: [[String: Any]] = [], pending = Set<String>(), imageCount = 0
        var frozenSystem: String?
        for (index, message) in incoming.enumerated() {
            guard let role = message["role"] as? String, let text = message["content"] as? String else { throw failure }
            var parts: [[String: Any]] = [], providerRole = role
            if role == "tool" {
                guard let id = message["toolCallId"] as? String, pending.remove(id) != nil else { throw failure }
                let result = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
                parts = [["type": "tool_result", "tool_use_id": id, "content": text, "is_error": result?["ok"] as? Bool == false]]; providerRole = "user"
            } else if role == "assistant" {
                guard pending.isEmpty else { throw failure }
                let prior = try continuations.load(Array(incoming.prefix(index + 1)))
                guard frozenSystem == nil || frozenSystem == prior.system else { throw VaultFailure(message: "The Anthropic run has inconsistent frozen system history. Its journal is retained.") }
                frozenSystem = prior.system; parts = prior.blocks
                let calls = message["toolCalls"] as? [[String: String]] ?? []
                guard calls.count <= 12, Set(calls.compactMap { $0["id"] }).count == calls.count else { throw failure }
                pending = Set(calls.compactMap { $0["id"] })
            } else if role == "user" {
                guard pending.isEmpty else { throw failure }
                for image in message["images"] as? [[String: String]] ?? [] {
                    imageCount += 1
                    guard imageCount <= 4, let media = image["mediaType"], ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(media), let data = image["data"], data.count <= 4_200_000, Data(base64Encoded: data) != nil else { throw failure }
                    parts.append(["type": "image", "source": ["type": "base64", "media_type": media, "data": data]])
                }
                if !text.isEmpty { parts.append(["type": "text", "text": text]) }
            } else { throw failure }
            guard !parts.isEmpty else { throw failure }
            if providerRole == "user", messages.last?["role"] as? String == "user", let prior = messages.last?["content"] as? [[String: Any]] { messages[messages.count - 1]["content"] = prior + parts }
            else { messages.append(["role": providerRole, "content": parts]) }
        }
        guard pending.isEmpty else { throw failure }
        let definitions = try tools.map { tool -> [String: Any] in
            guard let name = tool["name"] as? String, let schema = tool["inputSchema"] as? [String: Any] else { throw failure }
            return ["name": name, "description": tool["description"] as? String ?? "", "input_schema": schema]
        }
        var body: [String: Any] = ["model": model, "system": frozenSystem ?? system, "messages": messages, "max_tokens": output, "stream": true]
        if !definitions.isEmpty { body["tools"] = definitions; body["tool_choice"] = ["type": "auto"] }
        if let effort = source["effort"] as? String, ["low", "medium", "high"].contains(effort) { body["output_config"] = ["effort": effort] }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue(key, forHTTPHeaderField: "x-api-key"); request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        guard (request.httpBody?.count ?? 0) <= 18_000_000 else { throw failure }
        return (request, incoming, frozenSystem ?? system)
    }
}
