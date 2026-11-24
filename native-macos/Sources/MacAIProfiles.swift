import SwiftUI

enum MacAIProvider: String, CaseIterable, Identifiable, Sendable {
    case openai, anthropic, openrouter, compatible
    var id: String { rawValue }
    var label: String { switch self { case .openai: "OpenAI"; case .anthropic: "Anthropic"; case .openrouter: "OpenRouter"; case .compatible: "Compatible API" } }
    var format: MacAIFormat { self == .anthropic ? .anthropic : .compatible }
    var endpoint: String { switch self { case .openai: MacAIFormat.compatible.defaultEndpoint; case .anthropic: MacAIFormat.anthropic.defaultEndpoint; case .openrouter: "https://openrouter.ai/api/v1/chat/completions"; case .compatible: "" } }
}
struct MacAIProfile: Equatable, Sendable {
    var provider: MacAIProvider
    var endpoint: String
    var model: String
    var contextWindow = 32_768
    var favorites: [String] = []
    init(provider: MacAIProvider, endpoint: String? = nil, model: String = "", contextWindow: Int = 32_768, favorites: [String] = []) {
        self.provider = provider; self.endpoint = endpoint ?? provider.endpoint; self.model = model; self.contextWindow = contextWindow; self.favorites = favorites
    }
    static func legacy(endpoint: String, model: String, contextWindow: Int, format: MacAIFormat) -> Self {
        let host = URL(string: endpoint)?.host?.lowercased()
        let provider: MacAIProvider = format == .anthropic ? .anthropic : host == "api.openai.com" ? .openai : host == "openrouter.ai" ? .openrouter : .compatible
        return .init(provider: provider, endpoint: endpoint, model: model, contextWindow: contextWindow)
    }
    static func capacityPrefix(root: URL) -> String { "zerus.mac.ai.capacity." + NativeHistory.hash(root.standardizedFileURL.resolvingSymlinksInPath().path) + "." }
    static func endpointKey(root: URL, provider: MacAIProvider, baseURL: String, model: String) -> String { capacityPrefix(root: root) + "endpoint." + NativeHistory.hash(provider.rawValue + "\n" + baseURL + "\n" + model) }
    func capacityKey(root: URL) -> String { Self.capacityPrefix(root: root) + NativeHistory.hash(provider.rawValue + "\n" + endpoint + "\n" + model) }
    var baseURL: String {
        for ending in ["/chat/completions", "/messages"] where endpoint.hasSuffix(ending) { return String(endpoint.dropLast(ending.count)) }
        return endpoint
    }
    func validated() throws -> Self {
        var value = self; value.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines); value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try MacAIClient.endpoint(value.endpoint)
        guard !value.model.isEmpty, (4096...2_000_000).contains(value.contextWindow) else { throw VaultFailure(message: "Enter a model ID and a context window between 4,096 and 2,000,000 tokens.") }
        value.favorites = Self.choices(favorites); return value
    }
    static func choices(_ values: [String]) -> [String] { var seen = Set<String>(); return Array(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(50)) }
}
struct MacAIProfileSnapshot: Sendable {
    let root: URL
    let workspaceID: UUID
    let bytes: Data?
    let active: MacAIProvider?
    let profiles: [MacAIProvider: MacAIProfile]
    static let path = ".zerus/ai-settings.json"
    init(root: URL, workspaceID: UUID, bytes: Data?) throws {
        self.root = root; self.workspaceID = workspaceID; self.bytes = bytes
        let object = try Self.object(bytes)
        let entries = object["profiles"] as? [String: Any] ?? [:]
        var profiles: [MacAIProvider: MacAIProfile] = [:]
        for provider in MacAIProvider.allCases {
            guard let raw = entries[provider.rawValue] else { continue }
            guard let raw = raw as? [String: Any], let base = raw["baseUrl"] as? String, let rawModel = raw["model"] as? String else { throw VaultFailure(message: "A shared AI profile is unsupported. Its original settings are preserved.") }
            let normalized = base.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let suffix = provider == .anthropic ? "/messages" : "/chat/completions"
            let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let endpoint: String
            if let override = raw["macEndpoint"] as? String, raw["macEndpointBaseUrl"] as? String == base { endpoint = override }
            else if let kept = UserDefaults.standard.string(forKey: MacAIProfile.endpointKey(root: root, provider: provider, baseURL: base, model: model)) { endpoint = kept }
            else { endpoint = normalized.isEmpty ? "" : normalized.hasSuffix(suffix) ? normalized : normalized + suffix }
            let identity = MacAIProfile(provider: provider, endpoint: endpoint, model: model)
            let capacity = raw["macContextWindow"] as? Int ?? UserDefaults.standard.object(forKey: identity.capacityKey(root: root)) as? Int ?? 32_768
            profiles[provider] = .init(provider: provider, endpoint: endpoint, model: model, contextWindow: capacity, favorites: MacAIProfile.choices(raw["favoriteModels"] as? [String] ?? []))
        }
        self.profiles = profiles; active = (object["activeProvider"] as? String).flatMap(MacAIProvider.init(rawValue:))
    }
    private static func object(_ bytes: Data?) throws -> [String: Any] {
        guard let bytes else { return [:] }
        guard bytes.count <= 2 * 1024 * 1024, let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], NativeHistory.integer(object["version"]) == 1, object["profiles"] is [String: Any], object["activeProvider"] is String else { throw VaultFailure(message: "Shared AI settings use an unsupported format. Their original file is preserved.") }
        return object
    }
    func saving(_ chosen: MacAIProfile, preserving seed: MacAIProfile? = nil) throws -> VaultFileChange {
        let chosen = try chosen.validated()
        var object = try Self.object(bytes), profiles = object["profiles"] as? [String: Any] ?? [:]
        if let seed, seed.provider != chosen.provider, profiles[seed.provider.rawValue] == nil {
            let seeded = try MacAIProfileSnapshot(root: root, workspaceID: workspaceID, bytes: nil).saving(seed)
            if let data = seeded.after, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], let entries = value["profiles"] as? [String: Any] { profiles.merge(entries) { old, _ in old } }
        }
        var entry = profiles[chosen.provider.rawValue] as? [String: Any] ?? [:]
        entry["baseUrl"] = chosen.baseURL; entry["model"] = chosen.model; entry["favoriteModels"] = chosen.favorites; entry["macContextWindow"] = chosen.contextWindow
        // Preserve arbitrary legacy Mac request paths without inventing a new
        // shared API format. Other clients continue using the normal baseUrl.
        if chosen.endpoint == chosen.baseURL { entry["macEndpoint"] = chosen.endpoint; entry["macEndpointBaseUrl"] = chosen.baseURL }
        else { entry.removeValue(forKey: "macEndpoint"); entry.removeValue(forKey: "macEndpointBaseUrl") }
        profiles[chosen.provider.rawValue] = entry
        object["version"] = 1; object["activeProvider"] = chosen.provider.rawValue; object["profiles"] = profiles; object["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        return .init(path: Self.path, before: bytes, after: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
    }
}
extension VaultFiles {
    func macAIProfiles(workspaceID: UUID) throws -> MacAIProfileSnapshot {
        let file = try url(for: MacAIProfileSnapshot.path)
        let bytes: Data?
        if FileManager.default.fileExists(atPath: file.path) {
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 2 * 1024 * 1024 else { throw VaultFailure(message: "Shared AI settings exceed 2 MB. Their original file is preserved.") }
            bytes = try read(MacAIProfileSnapshot.path)
        } else { bytes = nil }
        return try .init(root: root, workspaceID: workspaceID, bytes: bytes)
    }
    func saveMacAIProfile(_ profile: MacAIProfile, snapshot: MacAIProfileSnapshot, preserving seed: MacAIProfile? = nil) throws -> MacAIProfileSnapshot {
        guard snapshot.root == root else { throw VaultFailure(message: "The vault changed. Reopen Connection.") }
        try applyTransaction([snapshot.saving(profile, preserving: seed)])
        let selected = try profile.validated()
        UserDefaults.standard.set(selected.contextWindow, forKey: selected.capacityKey(root: root))
        UserDefaults.standard.set(selected.endpoint, forKey: MacAIProfile.endpointKey(root: root, provider: selected.provider, baseURL: selected.baseURL, model: selected.model))
        if let seed = try? seed?.validated() {
            UserDefaults.standard.set(seed.contextWindow, forKey: seed.capacityKey(root: root))
            UserDefaults.standard.set(seed.endpoint, forKey: MacAIProfile.endpointKey(root: root, provider: seed.provider, baseURL: seed.baseURL, model: seed.model))
        }
        return try macAIProfiles(workspaceID: snapshot.workspaceID)
    }
}
extension MacWorkspace {
    func aiProfiles() async throws -> MacAIProfileSnapshot {
        let origin = workspaceID
        guard let io else { throw VaultFailure(message: "Open a vault before configuring AI.") }
        let value = try await io.macAIProfiles(workspaceID: origin)
        guard origin == workspaceID else { throw CancellationError() }; return value
    }
    func saveAIProfile(_ profile: MacAIProfile, snapshot: MacAIProfileSnapshot, preserving seed: MacAIProfile? = nil) async throws -> MacAIProfileSnapshot {
        guard snapshot.workspaceID == workspaceID, snapshot.root == root, let io else { throw VaultFailure(message: "The vault changed. Reopen Connection.") }
        let result = try await io.saveMacAIProfile(profile, snapshot: snapshot, preserving: seed)
        guard snapshot.workspaceID == workspaceID else { throw CancellationError() }
        return result
    }
    func aiProfile(legacy: MacAIProfile) async throws -> MacAIProfile {
        let snapshot = try await aiProfiles()
        return try (snapshot.active.flatMap { snapshot.profiles[$0] } ?? legacy).validated()
    }
}
