import SwiftUI

struct MacChatGPTSettings: View {
    @ObservedObject var connection: MacChatGPTConnection
    @State private var owner = UUID()
    @State private var operation: Task<Void, Never>?
    @State private var issue: String?
    private var disabled: Bool { connection.busy || connection.activeRequests > 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect a ChatGPT account in the system sign-in browser. Credentials stay in this Mac’s Keychain; conversation files contain no account tokens.").macFont(.callout).foregroundStyle(.secondary)
            if let state = connection.state {
                if let accounts = state.accounts, !accounts.isEmpty {
                    Picker("Account", selection: Binding(get: { accounts.first { $0.active }?.id ?? "" }, set: { id in perform { try await connection.selectAccount(id, owner: owner) } })) {
                        ForEach(accounts, id: \.id) { account in Text(account.label + (account.connected ? "" : " · reconnect")).tag(account.id) }
                    }.disabled(disabled)
                }
                HStack {
                    Button(state.configured ? "Reconnect ChatGPT" : "Continue with ChatGPT") { perform { try await connection.connect(owner: owner) } }.disabled(disabled)
                    if state.accounts?.isEmpty == false { Button("Add another account") { perform { try await connection.connect(owner: owner, addAccount: true) } }.disabled(disabled) }
                    if connection.busy { ProgressView().controlSize(.small); Button("Cancel sign-in") { operation?.cancel(); connection.cancel(owner: owner) } }
                }
                if state.configured {
                    Picker("Model", selection: Binding(get: { connection.state?.model ?? "" }, set: { id in perform { try await connection.selectModel(id, owner: owner) } })) {
                        if !connection.models.contains(where: { $0.id == state.model }) { Text(state.model.isEmpty ? "Choose a model" : state.model).tag(state.model) }
                        ForEach(connection.models, id: \.id) { model in Text(model.name).tag(model.id) }
                    }.disabled(disabled)
                    HStack {
                        Button("Refresh account models") { perform { try await connection.refreshModels(owner: owner) } }.disabled(disabled)
                        Spacer(); Button("Sign out") { perform { try await connection.signOut(owner: owner) } }.disabled(disabled)
                    }
                    if let capacity = connection.contextWindow { Text("Reported context window: \(capacity.formatted()) tokens").macFont(.caption).foregroundStyle(.secondary) }
                }
                if state.revocationUnconfirmed == true { Text("Local credentials were removed. Server revocation could not be confirmed; review connected apps in ChatGPT settings.").macFont(.caption).foregroundStyle(.orange) }
            }
            if connection.activeRequests > 0 { Text("Finish active ChatGPT replies before changing this connection.").macFont(.caption).foregroundStyle(.secondary) }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if let issue = connection.accessIssue { Text(issue).macFont(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            Text("Model availability and plan permission are checked through the shared Apple account service. Native tool execution is still being connected.").macFont(.caption).foregroundStyle(.secondary)
        }
        .task { await connection.refreshStatus() }
        .onDisappear { operation?.cancel(); connection.cancel(owner: owner) }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        issue = nil
        operation = Task { do { try await action() } catch is CancellationError {} catch { issue = error.localizedDescription }; operation = nil }
    }
}
