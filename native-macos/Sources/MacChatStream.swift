import Foundation

struct MacAICompletion: Sendable { let text: String; let reasoning: String; let finishReason: String? }
struct MacAIMessage: Sendable {
    let role: String
    let content: String
    var images: [Data] = []
    var object: [String: Any] {
        if images.isEmpty { return ["role": role, "content": content] }
        var parts: [[String: Any]] = [["type": "text", "text": content]]
        parts += images.map { ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + $0.base64EncodedString()]] }
        return ["role": role, "content": parts]
    }
}

/// Chat-completions SSE has different payloads from the ChatGPT Responses API.
/// Keep event framing strict, bounded and independent of UI/network chunk sizes.
struct MacSSEFrames {
    private var line = Data(), dataLines: [String] = [], eventBytes = 0, total = 0
    private var carriageReturn = false
    mutating func accept(_ byte: UInt8) throws -> String? {
        total += 1; guard total <= 64 * 1024 * 1024 else { throw VaultFailure(message: "The provider stream exceeded its supported size. The partial reply is retained.") }
        if byte == 10 && carriageReturn { carriageReturn = false; return nil }
        if byte == 10 || byte == 13 { carriageReturn = byte == 13; return try endLine() }
        carriageReturn = false
        guard line.count < 1024 * 1024 else { throw VaultFailure(message: "The provider returned an oversized stream line.") }
        line.append(byte); return nil
    }
    private mutating func endLine() throws -> String? {
        guard let value = String(data: line, encoding: .utf8) else { throw VaultFailure(message: "The provider returned invalid UTF-8 text.") }
        line.removeAll(keepingCapacity: true)
        if value.isEmpty { return flush() }
        if value.hasPrefix("data:") {
            var data = String(value.dropFirst(5)); if data.hasPrefix(" ") { data.removeFirst() }
            eventBytes += data.utf8.count
            guard eventBytes <= 2 * 1024 * 1024 else { throw VaultFailure(message: "The provider returned an oversized stream event.") }
            dataLines.append(data)
        }
        return nil
    }
    private mutating func flush() -> String? {
        guard !dataLines.isEmpty else { return nil }
        let data = dataLines.joined(separator: "\n"); dataLines = []; eventBytes = 0
        return data
    }
    mutating func finish() throws -> String? {
        if !line.isEmpty, let event = try endLine() { return event }
        return flush()
    }
}

struct MacChatStream {
    private var frames = MacSSEFrames()
    private(set) var text = "", reasoning = "", finishReason: String?, completed = false
    private var tools = false
    mutating func accept(_ byte: UInt8) throws -> String? { try frames.accept(byte).flatMap { try event($0) } }
    private mutating func event(_ data: String) throws -> String? {
        if data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" { completed = true; return nil }
        guard let bytes = data.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "The provider returned an unsupported stream event.") }
        if object["error"] != nil { throw VaultFailure(message: "The provider reported an error during the reply. Check its connection and model; the partial reply is retained.") }
        guard let choices = object["choices"] as? [[String: Any]], let choice = choices.first else { return nil }
        if let finish = choice["finish_reason"] as? String { finishReason = finish }
        guard let delta = choice["delta"] as? [String: Any] else { return nil }
        if let calls = delta["tool_calls"] as? [Any], !calls.isEmpty { tools = true }
        reasoning += delta["reasoning_content"] as? String ?? delta["reasoning"] as? String ?? ""
        let piece = delta["content"] as? String ?? delta["refusal"] as? String ?? ""
        text += piece
        guard text.utf8.count <= 2 * 1024 * 1024, reasoning.utf8.count <= 2 * 1024 * 1024 else { throw VaultFailure(message: "The provider reply exceeded 2 MB. Its partial text is retained.") }
        return piece.isEmpty ? nil : piece
    }
    mutating func finish() throws -> (MacAICompletion, String?) {
        let delta = try frames.finish().flatMap { try event($0) }
        if tools { throw VaultFailure(message: "The provider requested tools. Native tool execution is still being connected; the partial reply is retained.") }
        guard completed || finishReason != nil else { throw VaultFailure(message: "The connection ended before the provider completed its reply. Partial text is retained.") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VaultFailure(message: "The provider completed without a text reply.") }
        return (.init(text: text, reasoning: reasoning, finishReason: finishReason), delta)
    }
}

private final class MacAIHTTPPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class MacAIClient: @unchecked Sendable {
    let session: URLSession
    private let ownsSession: Bool
    init(session: URLSession? = nil) {
        if let session { self.session = session; ownsSession = false }
        else {
            self.session = Self.protectedSession(); ownsSession = true
        }
    }
    static func protectedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 120; configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: MacAIHTTPPolicy(), delegateQueue: nil)
    }
    deinit { if ownsSession { session.invalidateAndCancel() } }
    static func endpoint(_ value: String) throws -> URL {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw VaultFailure(message: "Enter an HTTPS API endpoint without credentials, query parameters or fragments.") }
        return url
    }
    func stream(endpoint: String, model: String, apiKey: String, messages: [MacAIMessage], format: MacAIFormat = .compatible, maxOutputTokens: Int = 4096, onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws -> MacAICompletion {
        let request = try MacAIRequest.make(endpoint: endpoint, model: model, apiKey: apiKey, messages: messages, format: format, maxOutputTokens: maxOutputTokens)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw VaultFailure(message: "The provider returned an unsupported response.") }
        guard (200..<300).contains(http.statusCode) else { throw VaultFailure(message: "The provider returned HTTP \(http.statusCode). Check the endpoint, model and connection.") }
        if http.mimeType?.lowercased().contains("json") == true {
            var data = Data()
            for try await byte in bytes { try Task.checkCancellation(); guard data.count < 4 * 1024 * 1024 else { throw VaultFailure(message: "The provider response exceeded 4 MB.") }; data.append(byte) }
            if format == .anthropic {
                let response = try MacAnthropicStream.response(data), result = response.completion
                try Task.checkCancellation(); await onDelta(result.text)
                try MacAnthropicStream.validate(text: result.text, tools: response.tools, reason: result.finishReason)
                return result
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], choice = (object?["choices"] as? [[String: Any]])?.first, message = choice?["message"] as? [String: Any]
            guard object?["error"] == nil, (message?["tool_calls"] as? [Any])?.isEmpty != false,
                  let text = message?["content"] as? String ?? message?["refusal"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 2 * 1024 * 1024 else { throw VaultFailure(message: "The provider returned an unsupported text response.") }
            try Task.checkCancellation(); await onDelta(text)
            return .init(text: text, reasoning: message?["reasoning_content"] as? String ?? message?["reasoning"] as? String ?? "", finishReason: choice?["finish_reason"] as? String)
        }
        if format == .anthropic {
            var stream = MacAnthropicStream()
            for try await byte in bytes {
                try Task.checkCancellation()
                if let delta = try stream.accept(byte) { await onDelta(delta) }
                if stream.completed { break }
            }
            let (result, final) = try stream.finish(); if let final, !final.isEmpty { await onDelta(final) }; try Task.checkCancellation(); return result
        }
        var stream = MacChatStream()
        for try await byte in bytes {
            try Task.checkCancellation()
            if let delta = try stream.accept(byte) { await onDelta(delta) }
            if stream.completed { break }
        }
        let (result, final) = try stream.finish(); if let final, !final.isEmpty { await onDelta(final) }; try Task.checkCancellation(); return result
    }
}
