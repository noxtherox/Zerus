import SwiftUI

@MainActor final class MacAIConnectionModel: ObservableObject {
    @Published var profile: MacAIProfile {
        didSet { if oldValue.provider != profile.provider || oldValue.endpoint != profile.endpoint { key = ""; cancelDiscovery(); models = [] } }
    }
    @Published var usingChatGPT: Bool
    @Published var key = "" { didSet { if oldValue != key { cancelDiscovery(); models = [] } } }
    @Published var modelQuery = ""
    @Published private(set) var models: [MacAIModel] = []
    @Published private(set) var loading = false
    @Published private(set) var discovering = false
    @Published private(set) var saving = false
    @Published private(set) var issue: String?
    private let legacy: MacAIProfile
    private var profiles: [MacAIProvider: MacAIProfile] = [:]
    private var basis: MacAIProfileSnapshot?
    private var discovery: Task<Void, Never>?
    private var request = UUID()
    private let client: MacAIClient
    init(legacy: MacAIProfile, usingChatGPT: Bool, client: MacAIClient = .init()) { profile = legacy; self.legacy = legacy; self.usingChatGPT = usingChatGPT; self.client = client }
    var visibleModels: [MacAIModel] { models.filter { modelQuery.isEmpty || $0.id.localizedCaseInsensitiveContains(modelQuery) || $0.name.localizedCaseInsensitiveContains(modelQuery) } }
    func load(_ workspace: MacWorkspace) async {
        cancelDiscovery(); key = ""; models = []; modelQuery = ""; loading = true; issue = nil; defer { loading = false }
        do {
            let snapshot = try await workspace.aiProfiles(); try Task.checkCancellation()
            profiles = Dictionary(uniqueKeysWithValues: MacAIProvider.allCases.map { ($0, MacAIProfile(provider: $0)) }); profiles[legacy.provider] = legacy
            profiles.merge(snapshot.profiles) { _, shared in shared }; basis = snapshot
            let provider = !usingChatGPT ? snapshot.active ?? legacy.provider : legacy.provider
            profile = profiles[provider] ?? legacy
        } catch is CancellationError {} catch { basis = nil; issue = error.localizedDescription }
    }
    func choose(_ provider: MacAIProvider) { profiles[profile.provider] = profile; profile = profiles[provider] ?? .init(provider: provider); issue = nil }
    func select(_ model: MacAIModel) { profile.model = model.id; if let capacity = model.contextWindow { profile.contextWindow = capacity } }
    func toggleFavorite() {
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines); guard !model.isEmpty else { return }
        if profile.favorites.contains(model) { profile.favorites.removeAll { $0 == model } }
        else { guard profile.favorites.count < 50 else { issue = "Keep up to 50 favorite models in each provider profile."; return }; profile.favorites = MacAIProfile.choices(profile.favorites + [model]) }
    }
    func cancelDiscovery() { request = UUID(); discovery?.cancel(); discovery = nil; discovering = false }
    func discover() {
        cancelDiscovery(); issue = nil; discovering = true
        let token = request, source = profile, supplied = key, client = client
        discovery = Task { [weak self] in
            guard let self else { return }
            defer { if self.request == token { self.discovering = false; self.discovery = nil } }
            do {
                _ = try MacAIClient.endpoint(source.endpoint)
                let publicCatalog = try MacAIClient.publicModelCatalog(endpoint: source.endpoint, format: source.provider.format)
                let key = supplied.isEmpty && !publicCatalog ? try await MacCredentials.read(source.endpoint) : supplied
                try Task.checkCancellation(); guard self.request == token else { return }
                let result = try await client.models(endpoint: source.endpoint, format: source.provider.format, apiKey: key)
                try Task.checkCancellation(); guard self.request == token else { return }
                self.models = result
                if result.isEmpty { self.issue = "No models were returned. Your entered model is kept." }
            } catch is CancellationError {} catch { if self.request == token { self.issue = error.localizedDescription } }
        }
    }
    func save(_ workspace: MacWorkspace) async throws -> MacAIProfile {
        guard !saving, !loading else { throw VaultFailure(message: "Wait for Connection to finish loading.") }
        saving = true; issue = nil; cancelDiscovery(); defer { saving = false }
        do {
            if usingChatGPT { _ = try await MacChatGPTConnection.shared.selection(); return legacy }
            guard let basis, basis.workspaceID == workspace.workspaceID else { throw VaultFailure(message: "Reload profiles in this vault before saving.") }
            let selected = try profile.validated(), supplied = key
            if !supplied.isEmpty { guard supplied.rangeOfCharacter(from: .controlCharacters) == nil else { throw VaultFailure(message: "The API key contains an unsupported control character.") }; try await MacCredentials.save(supplied, account: selected.endpoint) }
            try Task.checkCancellation()
            let seed = try? legacy.validated()
            self.basis = try await workspace.saveAIProfile(selected, snapshot: basis, preserving: seed)
            profiles[selected.provider] = selected; profile = selected; return selected
        } catch { issue = error.localizedDescription; throw error }
    }
}

struct MacChatConnection: View {
    @Bindable var workspace: MacWorkspace
    @StateObject private var connection: MacAIConnectionModel
    let saved: (String, String, Int, Bool, MacAIFormat) -> Void
    @Environment(\.dismiss) private var dismiss
    init(workspace: MacWorkspace, endpoint: String, model: String, contextWindow: Int, usingChatGPT: Bool, format: MacAIFormat, saved: @escaping (String, String, Int, Bool, MacAIFormat) -> Void) {
        self.workspace = workspace; self.saved = saved
        _connection = StateObject(wrappedValue: .init(legacy: .legacy(endpoint: endpoint, model: model, contextWindow: contextWindow, format: format), usingChatGPT: usingChatGPT))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("AI connection").macFont(.title2.bold()); Spacer(); if connection.loading || connection.saving { ProgressView().controlSize(.small) } }
            Picker("Connection", selection: $connection.usingChatGPT) { Text("API key").tag(false); Text("ChatGPT account").tag(true) }.pickerStyle(.segmented)
            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            if connection.usingChatGPT { MacChatGPTSettings(connection: .shared) }
            else {
                Picker("Provider", selection: Binding(get: { connection.profile.provider }, set: connection.choose)) { ForEach(MacAIProvider.allCases) { Text($0.label).tag($0) } }
                TextField("HTTPS request endpoint", text: $connection.profile.endpoint).textFieldStyle(.roundedBorder)
                HStack { TextField("Model ID", text: $connection.profile.model).textFieldStyle(.roundedBorder); Button(connection.profile.favorites.contains(connection.profile.model) ? "Unfavorite" : "Favorite") { connection.toggleFavorite() }.disabled(connection.profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                if !connection.profile.favorites.isEmpty { Menu("Favorite models") { ForEach(connection.profile.favorites, id: \.self) { model in Button(model) { connection.profile.model = model } } } }
                SecureField("New API key (optional)", text: $connection.key).textFieldStyle(.roundedBorder)
                HStack {
                    Button(connection.discovering ? "Cancel model discovery" : "Load models") { if connection.discovering { connection.cancelDiscovery() } else { connection.discover() } }
                    if connection.discovering { ProgressView().controlSize(.small) }
                    if !connection.models.isEmpty { Text("\(connection.models.count) models returned").macFont(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }
                if !connection.models.isEmpty {
                    TextField("Filter models", text: $connection.modelQuery).textFieldStyle(.roundedBorder)
                    ScrollView { LazyVStack(alignment: .leading, spacing: 8) { ForEach(connection.visibleModels) { model in Button { connection.select(model) } label: { HStack { VStack(alignment: .leading) { Text(model.name).macFont(.callout); Text(model.id).macFont(.caption).foregroundStyle(.secondary) }; Spacer(); if let capacity = model.contextWindow { Text("\(capacity) tokens").macFont(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(MacBoxButtonStyle()).accessibilityLabel("Choose model " + model.id) } } }.frame(height: 130)
                }
                HStack { Text("Model context window (tokens)"); TextField("Context window", value: $connection.profile.contextWindow, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 130) }
                Text("Profiles and favorite model IDs are shared with this vault. Keys stay in this Mac’s Keychain. Leave the key blank to use this endpoint’s saved key. Loading models contacts the selected provider; a model is changed only when you choose one.").macFont(.caption).foregroundStyle(.secondary)
                if connection.profile.provider == .openrouter { Text("OpenRouter’s public model catalog needs no key. Sending messages still requires your saved API key.").macFont(.caption).foregroundStyle(.secondary) }
                Text("Set context capacity for your model. File context reserves room for output and images; Anthropic replies use up to 4,096 output tokens. Native tool execution is still being connected.").macFont(.caption).foregroundStyle(.secondary)
            }
            }
            }.frame(maxHeight: 480)
            if let issue = connection.issue { Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Button("Cancel") { connection.cancelDiscovery(); dismiss() }; Button("Reload profiles") { Task { await connection.load(workspace) } }; Spacer(); Button("Save connection") { Task { do { let profile = try await connection.save(workspace); saved(profile.endpoint, profile.model, profile.contextWindow, connection.usingChatGPT, profile.provider.format); dismiss() } catch {} } } }
        }.padding(24).frame(width: 650).disabled(connection.loading || connection.saving).interactiveDismissDisabled(connection.saving)
        .task { await connection.load(workspace) }.onDisappear { connection.cancelDiscovery() }
        .onChange(of: workspace.workspaceID) { _, _ in connection.cancelDiscovery() }
        .onChange(of: connection.usingChatGPT) { _, _ in connection.cancelDiscovery() }
    }
}
