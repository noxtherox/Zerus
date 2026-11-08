import SwiftUI

struct NativeAgentWorkflowsView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let workspaceID: UUID
    @State private var catalog: NativeAgentWorkflowCatalog?
    @State private var selected = ""
    @State private var busy = false
    @State private var issue: String?
    @State private var saved = false
    @State private var discard = false
    @State private var reload = false
    @State private var creating = false
    @State private var title = ""
    @State private var editor: NativeAgentWorkflowDocument?
    private var active: Bool { vault.workspaceID == workspaceID && !vault.switchingVault }
    private var dirty: Bool { catalog.map { $0.selectedID != selected } ?? false }
    private var chosen: NativeAgentWorkflow? { catalog?.workflows.first { $0.id == selected } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose a reusable approach for new AI requests in this vault. Existing runs retain their original workflow. Your request, mode and note permissions still apply.").foregroundStyle(.secondary)
                }
                if let catalog {
                    Section {
                        Button { title = ""; creating = true } label: { Label("New custom workflow", systemImage: "plus") }.accessibilityIdentifier("workflow.new")
                        choice(nil)
                    }
                    Section("Built-in workflows") { ForEach(NativeAgentWorkflow.builtins) { choice($0) } }
                    if !catalog.custom.isEmpty {
                        Section("Custom workflows") {
                            ForEach(catalog.custom) { document in
                                HStack {
                                    choice(document.workflow)
                                    Button { editor = document } label: { Image(systemName: "pencil") }
                                        .accessibilityLabel("Edit " + document.workflow.title).accessibilityIdentifier("workflow.edit." + document.id)
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                    if let chosen {
                        Section {
                            Text(chosen.instructions).textSelection(.enabled).accessibilityIdentifier("workflow.preview")
                            if NativeAgentWorkflow.builtins.contains(where: { $0.id == chosen.id }) {
                                Button("Make a custom copy") { copy(chosen) }.accessibilityIdentifier("workflow.copy")
                            }
                        } header: { Text(chosen.title).lineLimit(3) } footer: { Text("This text is included with a new request to your chosen AI provider. It does not grant extra permissions or run anything on its own.") }
                    } else if !selected.isEmpty {
                        Section { Text("The saved workflow is unavailable. Choose another workflow or General notes task before sending a new request.").foregroundStyle(.orange).accessibilityIdentifier("workflow.unavailable") }
                    }
                    ForEach(Array(catalog.notices.enumerated()), id: \.offset) { _, notice in Text(notice).font(.caption).foregroundStyle(.secondary) }
                    Section {
                        if saved && !dirty { Label("Saved", systemImage: "checkmark.circle").foregroundStyle(.secondary).accessibilityIdentifier("workflow.saved") }
                        Button("Reload saved workflows") { if dirty { reload = true } else { Task { await load() } } }.accessibilityIdentifier("workflow.reload")
                    } footer: { Text("Custom workflows are ordinary Markdown files in this vault. Saving a workflow edits its file; Save here changes the selection for future requests. Other AI settings are preserved.") }
                }
                if let issue { Section { Text(issue).foregroundStyle(.orange).textSelection(.enabled).accessibilityIdentifier("workflow.error"); if catalog == nil { Button("Retry") { Task { await load() } } } } }
                if busy { ProgressView(catalog == nil ? "Opening workflows…" : "Saving…") }
            }.disabled(busy || !active)
                .navigationTitle("Workflows").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(dirty ? "Cancel" : "Done") { if dirty { discard = true } else { dismiss() } }.disabled(busy).accessibilityIdentifier("workflow.close") }
                    ToolbarItem(placement: .confirmationAction) { Button(saved && !dirty ? "Saved" : "Save") { saveSelection() }.disabled(busy || !active || !dirty || !selected.isEmpty && chosen == nil).accessibilityIdentifier("workflow.save") }
                }
                .interactiveDismissDisabled(dirty || busy)
                .alert("Discard this workflow selection?", isPresented: $discard) { Button("Discard selection", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} } message: { Text("Saved workflow files remain in the vault.") }
                .alert("Reload and discard this selection?", isPresented: $reload) { Button("Reload workflows", role: .destructive) { Task { await load() } }; Button("Keep editing", role: .cancel) {} }
                .alert("New workflow", isPresented: $creating) {
                    TextField("Workflow name", text: $title).accessibilityIdentifier("workflow.newTitle")
                    Button("Create") { copy(nil) }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel", role: .cancel) {}
                }
                .sheet(item: $editor) { document in
                    NativeAgentWorkflowEditor(document: document, workspaceID: workspaceID) { updated in
                        guard let original = self.catalog, active else { return }
                        var documents = original.custom.filter { $0.id != updated.id }; documents.append(updated); documents.sort { $0.workflow.title.localizedStandardCompare($1.workflow.title) == .orderedAscending }
                        self.catalog = .init(root: original.root, settingsBytes: original.settingsBytes, selectedID: original.selectedID, custom: documents, notices: original.notices)
                        if document.bytes == nil { selected = updated.id; saved = false }
                    }
                }
                .task { await load() }
                .onChange(of: vault.workspaceID) { _, next in if next != workspaceID { dismiss() } }
        }
    }
    private func choice(_ value: NativeAgentWorkflow?) -> some View {
        Button { selected = value?.id ?? ""; saved = false } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) { Text(value?.title ?? "General notes task").lineLimit(2); if let value, NativeAgentWorkflow.customPath(value.id) { Text(String(value.id.dropFirst(NativeAgentWorkflow.directory.count + 1))).font(.caption).foregroundStyle(.secondary) } }
                Spacer(); if selected == (value?.id ?? "") { Image(systemName: "checkmark").accessibilityHidden(true) }
            }.contentShape(Rectangle())
        }.accessibilityIdentifier("workflow.choice." + (value?.id ?? "general"))
            .accessibilityAddTraits(selected == (value?.id ?? "") ? .isSelected : [])
    }
    private func load() async {
        guard active, !busy else { return }; busy = true; defer { busy = false }
        do { let next = try await vault.agentWorkflows(workspace: workspaceID); guard active else { return }; catalog = next; selected = next.selectedID; saved = false; issue = nil }
        catch { if active { issue = error.localizedDescription } }
    }
    private func saveSelection() {
        guard active, !busy, let catalog else { return }; busy = true
        Task { @MainActor in
            defer { busy = false }
            do { let next = try await vault.saveAgentWorkflowSelection(selected, expected: catalog, workspace: workspaceID); guard active else { return }; self.catalog = next; selected = next.selectedID; saved = true; issue = nil }
            catch { if active { issue = error.localizedDescription; saved = false } }
        }
    }
    private func copy(_ workflow: NativeAgentWorkflow?) {
        guard active, !busy else { return }; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                var next = try await vault.newAgentWorkflow(title: workflow?.title ?? title, workspace: workspaceID)
                if let workflow { next = .init(root: next.root, id: next.id, bytes: nil, source: "# " + workflow.title + "\n\n" + workflow.instructions + "\n") }
                guard active else { return }; editor = next; issue = nil
            } catch { if active { issue = error.localizedDescription } }
        }
    }
}

private struct NativeAgentWorkflowEditor: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let workspaceID: UUID
    let didSave: (NativeAgentWorkflowDocument) -> Void
    @State private var snapshot: NativeAgentWorkflowDocument
    @State private var source: String
    @State private var busy = false
    @State private var issue: String?
    @State private var saved = false
    @State private var discard = false
    @State private var reload = false
    @FocusState private var focused: Bool
    init(document: NativeAgentWorkflowDocument, workspaceID: UUID, didSave: @escaping (NativeAgentWorkflowDocument) -> Void) {
        self.workspaceID = workspaceID; self.didSave = didSave; _snapshot = State(initialValue: document); _source = State(initialValue: document.source)
    }
    private var active: Bool { vault.workspaceID == workspaceID && !vault.switchingVault }
    private var dirty: Bool { snapshot.bytes == nil || source != snapshot.source }
    private var valid: Bool { !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && source.utf16.count <= 12_000 }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $source).frame(minHeight: 280).focused($focused).accessibilityLabel("Workflow Markdown").accessibilityIdentifier("workflow.editor")
                    Text("\(source.utf16.count.formatted()) / 12,000 characters").font(.caption).foregroundStyle(valid ? Color.secondary : .orange)
                } header: { Text("Markdown instructions") } footer: { Text("The first # heading names this workflow. Existing files longer than 12,000 characters are kept intact; only their first 12,000 characters are used in requests. Reduce the draft to save an edit.") }
                Section {
                    if saved && !dirty { Label("Saved", systemImage: "checkmark.circle").accessibilityIdentifier("workflow.editor.saved") }
                    ShareLink(item: source) { Label("Share this draft", systemImage: "square.and.arrow.up") }
                    if snapshot.bytes != nil { Button("Reload saved workflow") { focused = false; if dirty { reload = true } else { Task { await reloadFile() } } }.accessibilityIdentifier("workflow.editor.reload") }
                    Text(snapshot.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let issue { Text(issue).foregroundStyle(.orange).textSelection(.enabled).accessibilityIdentifier("workflow.editor.error") }
                if busy { ProgressView("Saving…") }
            }.disabled(busy || !active).scrollDismissesKeyboard(.interactively)
                .navigationTitle("Edit workflow").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(dirty ? "Cancel" : "Done") { focused = false; if dirty { discard = true } else { dismiss() } }.disabled(busy).accessibilityIdentifier("workflow.editor.close") }
                    ToolbarItem(placement: .confirmationAction) { Button(saved && !dirty ? "Saved" : "Save") { save() }.disabled(busy || !active || !dirty || !valid).accessibilityIdentifier("workflow.editor.save") }
                }
                .safeAreaInset(edge: .bottom) { if focused { HStack { Spacer(); Button("Done") { focused = false }.fontWeight(.semibold).accessibilityLabel("Dismiss keyboard") }.padding(.horizontal).padding(.vertical, 8).background(.bar) } }
                .interactiveDismissDisabled(dirty || busy)
                .alert("Discard this workflow draft?", isPresented: $discard) { Button("Discard draft", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} }
                .alert("Reload and discard this draft?", isPresented: $reload) { Button("Reload workflow", role: .destructive) { Task { await reloadFile() } }; Button("Keep editing", role: .cancel) {} }
                .onChange(of: vault.workspaceID) { _, next in if next != workspaceID { dismiss() } }
        }
    }
    private func save() {
        guard active, !busy, valid else { return }; focused = false; busy = true
        Task { @MainActor in
            await Task.yield(); defer { busy = false }
            do { let next = try await vault.saveAgentWorkflow(source, expected: snapshot, workspace: workspaceID); guard active else { return }; snapshot = next; source = next.source; issue = nil; saved = true; didSave(next) }
            catch { if active { issue = error.localizedDescription; saved = false } }
        }
    }
    private func reloadFile() async {
        guard active, !busy else { return }; busy = true; defer { busy = false }
        do { let next = try await vault.agentWorkflowDocument(snapshot.id, workspace: workspaceID); guard active else { return }; snapshot = next; source = next.source; issue = nil; saved = false; didSave(next) }
        catch { if active { issue = error.localizedDescription } }
    }
}
