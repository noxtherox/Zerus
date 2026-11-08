import SwiftUI

struct NativeAgentGuidanceView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let workspaceID: UUID
    @State private var snapshot: NativeAgentGuidanceSnapshot?
    @State private var value = NativeAgentGuidance()
    @State private var busy = false
    @State private var saved = false
    @State private var issue: String?
    @State private var discard = false
    @State private var reload = false
    @FocusState private var focused: Field?
    private enum Field { case instructions, memory }
    private var active: Bool { vault.workspaceID == workspaceID && !vault.switchingVault }
    private var dirty: Bool { snapshot.map { $0.guidance != value } ?? false }
    private var valid: Bool { value.instructions.utf16.count <= 12_000 && value.memory.utf16.count <= 8_000 }
    private var sharedDraft: String { "Vault instructions\n\n" + value.instructions + "\n\nEditable memory (reference data)\n\n" + value.memory }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Shape how Zerus answers in this vault. New requests use your saved instructions and memory; existing runs keep the version they started with.")
                        .foregroundStyle(.secondary)
                }
                if snapshot != nil {
                    Section {
                        TextEditor(text: $value.instructions).frame(minHeight: 170).focused($focused, equals: .instructions)
                            .accessibilityLabel("Vault instructions").accessibilityIdentifier("guidance.instructions")
                        counter(value.instructions.utf16.count, limit: 12_000)
                    } header: { Text("Vault instructions") } footer: {
                        Text("Writing style, language and working preferences. Instructions cannot change the chosen AI mode, note permissions or your current request.")
                    }
                    Section {
                        TextEditor(text: $value.memory).frame(minHeight: 150).focused($focused, equals: .memory)
                            .accessibilityLabel("Editable memory").accessibilityIdentifier("guidance.memory")
                        counter(value.memory.utf16.count, limit: 8_000)
                    } header: { Text("Editable memory") } footer: {
                        Text("Useful project facts and reference information. Memory does not grant permission or issue commands. Edit this text yourself; saved changes apply to future requests.")
                    }
                    Section {
                        if saved && !dirty { Label("Saved", systemImage: "checkmark.circle").foregroundStyle(.secondary).accessibilityIdentifier("guidance.saved") }
                        ShareLink(item: sharedDraft) { Label("Share this draft", systemImage: "square.and.arrow.up") }
                        Button("Reload saved version") { focused = nil; if dirty { reload = true } else { Task { await load() } } }
                            .accessibilityIdentifier("guidance.reload")
                    } footer: { Text("Kept as ordinary Markdown in this vault, shared with the existing Zerus app. These saved texts are sent to your chosen AI provider with a new request.") }
                }
                if let issue {
                    Section {
                        Text(issue).foregroundStyle(.orange).textSelection(.enabled).accessibilityIdentifier("guidance.error")
                        if snapshot == nil { Button("Retry") { Task { await load() } }.accessibilityIdentifier("guidance.retry") }
                    }
                }
                if busy { ProgressView(snapshot == nil ? "Opening instructions…" : "Saving…") }
            }.disabled(busy || !active)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("AI instructions").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(dirty ? "Cancel" : "Done") { focused = nil; if dirty { discard = true } else { dismiss() } }.disabled(busy)
                            .accessibilityIdentifier("guidance.close")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.disabled(busy || !active || !dirty || !valid).accessibilityIdentifier("guidance.save")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if focused != nil {
                        HStack { Spacer(); Button("Done") { focused = nil }.fontWeight(.semibold).accessibilityLabel("Dismiss keyboard") }
                            .padding(.horizontal).padding(.vertical, 8).background(.bar)
                    }
                }
                .interactiveDismissDisabled(dirty || busy)
                .alert("Discard your unsaved instructions and memory?", isPresented: $discard) {
                    Button("Discard changes", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) { }
                }
                .alert("Reload the saved version and discard this draft?", isPresented: $reload) {
                    Button("Reload saved version", role: .destructive) { Task { await load() } }
                    Button("Keep editing", role: .cancel) { }
                }
                .task { await load() }
                .onChange(of: vault.workspaceID) { _, current in if current != workspaceID { dismiss() } }
        }
    }
    private func counter(_ count: Int, limit: Int) -> some View {
        Text("\(count.formatted()) / \(limit.formatted()) characters").font(.caption).foregroundStyle(count > limit ? Color.red : Color.secondary)
    }
    private func load() async {
        guard active, !busy else { return }; busy = true; defer { busy = false }
        do {
            let next = try await vault.agentGuidance(workspace: workspaceID)
            guard active else { return }; snapshot = next; value = next.guidance; issue = nil; saved = false
        } catch { if active { issue = error.localizedDescription } }
    }
    private func save() {
        guard let snapshot, active, !busy else { return }
        focused = nil; busy = true
        Task { @MainActor in
            await Task.yield()
            defer { busy = false }
            do {
                let next = try await vault.saveAgentGuidance(value, expected: snapshot, workspace: workspaceID)
                guard active else { return }; self.snapshot = next; value = next.guidance; issue = nil; saved = true
            } catch { if active { issue = error.localizedDescription; saved = false } }
        }
    }
}
