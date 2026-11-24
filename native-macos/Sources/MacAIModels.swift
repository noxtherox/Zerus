import Foundation

struct MacAIModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let contextWindow: Int?
}
extension MacAIClient {
    func models(endpoint: String, format: MacAIFormat, apiKey: String) async throws -> [MacAIModel] {
        let endpoint = try Self.endpoint(endpoint), key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let publicCatalog = try Self.publicModelCatalog(endpoint: endpoint.absoluteString, format: format)
        guard (!key.isEmpty || publicCatalog), key.rangeOfCharacter(from: .controlCharacters) == nil else { throw VaultFailure(message: "Enter an API key or save this endpoint’s key before loading models.") }
        var components = try Self.modelComponents(endpoint)
        var models: [String: MacAIModel] = [:], seen = Set<String>(), cursor: String?
        for _ in 0..<20 {
            try Task.checkCancellation()
            if format == .anthropic { components.queryItems = [.init(name: "limit", value: "1000")] + (cursor.map { [.init(name: "after_id", value: $0)] } ?? []) }
            guard let url = components.url else { throw VaultFailure(message: "The model-list URL is invalid.") }
            var request = URLRequest(url: url); request.timeoutInterval = 30; request.setValue("application/json", forHTTPHeaderField: "Accept")
            if format == .anthropic { request.setValue(key, forHTTPHeaderField: "x-api-key"); request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version") }
            else if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw VaultFailure(message: "The provider returned an unsupported model response.") }
            guard (200..<300).contains(http.statusCode) else { throw VaultFailure(message: "Model discovery returned HTTP \(http.statusCode). Check the endpoint, API key and account access.") }
            var data = Data()
            for try await byte in bytes { try Task.checkCancellation(); guard data.count < 4 * 1024 * 1024 else { throw VaultFailure(message: "The model response exceeds 4 MB.") }; data.append(byte) }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] == nil, let records = object["data"] as? [[String: Any]] else { throw VaultFailure(message: "The provider returned an unsupported model list. Your entered model is kept.") }
            for record in records {
                try Task.checkCancellation()
                guard let raw = record["id"] as? String, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard id.utf8.count <= 1024, models.count < 10_000 || models[id] != nil else { throw VaultFailure(message: "The provider model list exceeds its supported limit. Your entered model is kept.") }
                let capacity = record["max_input_tokens"] as? Int ?? record["context_length"] as? Int ?? record["context_window"] as? Int
                let name = record["display_name"] as? String ?? record["name"] as? String ?? id
                models[id] = .init(id: id, name: String(name.prefix(512)), contextWindow: capacity.flatMap { (4096...2_000_000).contains($0) ? $0 : nil })
            }
            if object["has_more"] as? Bool != true { return models.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending } }
            guard format == .anthropic, let next = object["last_id"] as? String, !next.isEmpty, seen.insert(next).inserted else { throw VaultFailure(message: "Model pagination is incomplete. Your entered model is kept; retry discovery.") }
            cursor = next
        }
        throw VaultFailure(message: "Model discovery exceeded 20 pages. Your entered model is kept.")
    }
    static func publicModelCatalog(endpoint: String, format: MacAIFormat) throws -> Bool {
        let url = try Self.endpoint(endpoint)
        guard format == .compatible, url.host?.lowercased() == "openrouter.ai", url.port == nil || url.port == 443 else { return false }
        let components = try modelComponents(url)
        return components.path == "/api/v1/models"
    }
    private static func modelComponents(_ endpoint: URL) throws -> URLComponents {
        var path = endpoint.path
        if path.hasSuffix("/chat/completions") { path = String(path.dropLast("/chat/completions".count)) }
        else if path.hasSuffix("/messages") { path = String(path.dropLast("/messages".count)) }
        else { throw VaultFailure(message: "Model discovery needs a /chat/completions or /messages endpoint. You can still enter a model ID manually.") }
        guard var result = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw VaultFailure(message: "The model-list URL is invalid.") }
        result.path = path + "/models"; return result
    }
}
