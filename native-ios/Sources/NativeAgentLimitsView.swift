import SwiftUI

struct NativeAgentLimitsView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let workspaceID: UUID
    private enum Field: String, CaseIterable {
        case maxSteps, maxMinutes, maxTotalTokens, maxInputTokens, maxOutputTokens
        var title: String {
            switch self { case .maxSteps: "Model steps"; case .maxMinutes: "Active minutes"; case .maxTotalTokens: "Total tokens"; case .maxInputTokens: "Context tokens"; case .maxOutputTokens: "Output tokens per response" }
        }
        var path: WritableKeyPath<NativeAgentLimits, Int> {
            switch self { case .maxSteps: \.maxSteps; case .maxMinutes: \.maxMinutes; case .maxTotalTokens: \.maxTotalTokens; case .maxInputTokens: \.maxInputTokens; case .maxOutputTokens: \.maxOutputTokens }
        }
        var range: String {
            switch self { case .maxSteps: "2–100"; case .maxMinutes: "1–30"; case .maxTotalTokens: "8,000–1,000,000"; case .maxInputTokens: "4,096–200,000"; case .maxOutputTokens: "1,024–32,768" }
        }
    }
    @State private var snapshot: NativeAgentLimitsSnapshot?
    @State private var fields: [Field: String] = [:]
    @State private var effort = NativeAgentLimits.Effort.medium
    @State private var busy = false
    @State private var issue: String?
    @State private var saved = false
    @State private var discard = false
    @State private var reload = false
    @FocusState private var focused: Field?
    private var active: Bool { vault.workspaceID == workspaceID && !vault.switchingVault }
    private var dirty: Bool { guard let snapshot else { return false }; return effort != snapshot.limits.effort || Field.allCases.contains { fields[$0] != String(snapshot.limits[keyPath: $0.path]) } }
    private var value: NativeAgentLimits? {
        var next = NativeAgentLimits()
        for field in Field.allCases {
            guard let text = fields[field], let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }; next[keyPath: field.path] = number
        }
        next.effort = effort; guard (try? next.validate()) != nil else { return nil }; return next
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("New AI runs keep a snapshot of these limits. Changing them here does not change a run that has already started.").foregroundStyle(.secondary)
                }
                if snapshot != nil {
                    Section {
                        row(.maxSteps); row(.maxMinutes); row(.maxTotalTokens)
                    } header: { Text("Run budget") } footer: {
                        Text("Active time includes preparing requests, model responses and tool work. Waiting for your review is excluded. Interrupted requests without final usage keep their reserved token allowance as an estimate. Reaching a limit keeps the journal and proposals; start a new request to use different limits.")
                    }
                    Section {
                        row(.maxInputTokens); row(.maxOutputTokens)
                        Picker("Reasoning effort", selection: $effort) { ForEach(NativeAgentLimits.Effort.allCases) { Text($0.rawValue.capitalized).tag($0) } }.accessibilityIdentifier("limits.effort")
                    } header: { Text("Each response") } footer: {
                        Text("Context uses an on-device token estimate with a margin and an image allowance; providers may count differently. Compatible APIs receive an output cap. ChatGPT subscription responses receive an approximate output target. Reasoning effort applies when supported by your connection.")
                    }
                    Section {
                        if dirty && value == nil { Text("Enter whole numbers within the displayed ranges.").foregroundStyle(.orange).accessibilityIdentifier("limits.validation") }
                        if saved && !dirty { Label("Saved", systemImage: "checkmark.circle").foregroundStyle(.secondary).accessibilityIdentifier("limits.saved") }
                        Button("Use default limits") { focused = nil; populate(.defaults); saved = false }.accessibilityIdentifier("limits.defaults")
                        Button("Reload saved limits") { focused = nil; if dirty { reload = true } else { Task { await load() } } }.accessibilityIdentifier("limits.reload")
                    } footer: { Text("Saved in this vault alongside the existing Zerus app’s AI settings. Other settings, workflows and permissions are preserved.") }
                }
                if let issue {
                    Section { Text(issue).foregroundStyle(.orange).textSelection(.enabled).accessibilityIdentifier("limits.error")
                        if snapshot == nil { Button("Retry") { Task { await load() } }.accessibilityIdentifier("limits.retry") }
                    }
                }
                if busy { ProgressView(snapshot == nil ? "Opening AI limits…" : "Saving…") }
            }.disabled(busy || !active).scrollDismissesKeyboard(.interactively)
                .navigationTitle("AI limits").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(dirty ? "Cancel" : "Done") { focused = nil; if dirty { discard = true } else { dismiss() } }.disabled(busy).accessibilityIdentifier("limits.close") }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(busy || !active || !dirty || value == nil).accessibilityIdentifier("limits.save") }
                }
                .safeAreaInset(edge: .bottom) { if focused != nil { HStack { Spacer(); Button("Done") { focused = nil }.fontWeight(.semibold).accessibilityLabel("Dismiss keyboard") }.padding(.horizontal).padding(.vertical, 8).background(.bar) } }
                .interactiveDismissDisabled(dirty || busy)
                .alert("Discard your unsaved AI limits?", isPresented: $discard) { Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) { } }
                .alert("Reload the saved limits and discard this draft?", isPresented: $reload) { Button("Reload saved limits", role: .destructive) { Task { await load() } }; Button("Keep editing", role: .cancel) { } }
                .task { await load() }
                .onChange(of: vault.workspaceID) { _, current in if current != workspaceID { dismiss() } }
        }
    }
    private func row(_ field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.title).font(.subheadline)
            TextField(field.title, text: Binding(get: { fields[field] ?? "" }, set: { fields[field] = $0; saved = false }))
                .keyboardType(.numberPad).focused($focused, equals: field).accessibilityIdentifier("limits." + field.rawValue)
            Text(field.range).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
    private func populate(_ limits: NativeAgentLimits) { for field in Field.allCases { fields[field] = String(limits[keyPath: field.path]) }; effort = limits.effort }
    private func load() async {
        guard active, !busy else { return }; busy = true; defer { busy = false }
        do { let next = try await vault.agentLimits(workspace: workspaceID); guard active else { return }; snapshot = next; populate(next.limits); saved = false; issue = nil }
        catch { if active { issue = error.localizedDescription } }
    }
    private func save() {
        guard let snapshot, active, !busy else { return }; focused = nil; busy = true
        Task { @MainActor in
            await Task.yield(); defer { busy = false }
            guard let value else { return }
            do { let next = try await vault.saveAgentLimits(value, expected: snapshot, workspace: workspaceID); guard active else { return }; self.snapshot = next; populate(next.limits); saved = true; issue = nil }
            catch { if active { issue = error.localizedDescription; saved = false } }
        }
    }
}
