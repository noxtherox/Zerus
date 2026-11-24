import SwiftUI
import AppKit

struct MacAgentSettingsView: View {
    let workspace: MacAgentWorkspace
    @State private var selected = 3
    @State private var blocked: Set<Int> = []
    @State private var notice: String?
    @State private var refusedSwitches = 0
    var body: some View {
        VStack(alignment: .leading) {
            TabView(selection: Binding(get: { selected }, set: { next in
                if blocked.isEmpty { selected = next; notice = nil }
                else { refusedSwitches += 1; notice = "Save or discard the current draft before changing settings tabs." }
            })) {
                MacAgentPreferencesEditor(workspace: workspace, status: { update(3, $0) }).tabItem { Text("Run defaults") }.tag(3)
                MacAgentLimitsEditor(workspace: workspace, status: { update(0, $0) }).tabItem { Text("Limits") }.tag(0)
                MacAgentGuidanceEditor(workspace: workspace, status: { update(1, $0) }).tabItem { Text("Instructions & memory") }.tag(1)
                MacAgentWorkflowsEditor(workspace: workspace, status: { update(2, $0) }).tabItem { Text("Workflows") }.tag(2)
            }
            if let notice { Text(notice).id(refusedSwitches).font(.caption).foregroundStyle(.orange) }
        }.padding(16).frame(width: 740, height: 650).interactiveDismissDisabled(!blocked.isEmpty).onDisappear { workspace.setSettingsDraftHeld(false) }
    }
    private func update(_ tab: Int, _ value: Bool) {
        if value { blocked.insert(tab) } else { blocked.remove(tab) }
        workspace.setSettingsDraftHeld(!blocked.isEmpty)
        if blocked.isEmpty { notice = nil }
    }
}

private struct MacAgentLimitsEditor: View {
    let workspace: MacAgentWorkspace
    let status: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: NativeAgentLimitsSnapshot?
    @State private var steps = "30"
    @State private var minutes = "10"
    @State private var total = "160000"
    @State private var input = "48000"
    @State private var output = "8192"
    @State private var effort = NativeAgentLimits.Effort.medium
    @State private var busy = false
    @State private var saved = false
    @State private var discard = false
    @State private var reload = false
    @State private var issue: String?
    private var value: NativeAgentLimits? {
        guard let a = Int(steps), let b = Int(minutes), let c = Int(total), let d = Int(input), let e = Int(output) else { return nil }
        let limits = NativeAgentLimits(maxSteps: a, maxOutputTokens: e, maxInputTokens: d, maxMinutes: b, maxTotalTokens: c, effort: effort)
        return (try? limits.validate()) != nil ? limits : nil
    }
    private var dirty: Bool { snapshot != nil && value != snapshot?.limits }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Limits for new runs").font(.title2.bold())
            Text("Existing runs keep the limits they started with. These settings travel with this vault.").font(.caption).foregroundStyle(.secondary)
            Form {
                TextField("Model steps · 2–100", text: $steps)
                TextField("Active minutes · 1–30", text: $minutes)
                TextField("Total tokens · 8,000–1,000,000", text: $total)
                TextField("Context tokens per response · 4,096–200,000", text: $input)
                TextField("Output tokens per response · 1,024–32,768", text: $output)
                Picker("Reasoning effort", selection: $effort) { ForEach(NativeAgentLimits.Effort.allCases) { Text($0.rawValue.capitalized).tag($0) } }
            }.disabled(busy || snapshot == nil)
            Text("Context uses a local estimate, margin and image allowance. Providers may count differently. Compatible APIs receive an output cap; ChatGPT receives an approximate output target. Reasoning effort applies where supported.").font(.caption).foregroundStyle(.secondary)
            if dirty && value == nil { Text("Enter whole numbers within the displayed ranges.").foregroundStyle(.orange) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if saved && !dirty { Label("Saved", systemImage: "checkmark.circle") }
            Spacer()
            HStack {
                Button("Use defaults") { populate(.defaults); saved = false }.disabled(busy || snapshot == nil)
                Button("Reload") { if dirty { reload = true } else { load() } }.disabled(busy)
                Spacer(); Button("Done") { if dirty { discard = true } else { dismiss() } }.disabled(busy)
                Button("Save limits") { run { guard let value, let snapshot else { return }; self.snapshot = try await workspace.saveLimits(value, expected: snapshot); saved = true } }.disabled(busy || !dirty || value == nil)
            }
        }.padding(12).onAppear { if !dirty { load() } }.onChange(of: busy || dirty, initial: true) { _, value in status(value) }.interactiveDismissDisabled(busy || dirty)
        .confirmationDialog("Discard unsaved limits?", isPresented: $discard) { Button("Discard changes", role: .destructive) { dismiss() } }
        .confirmationDialog("Reload and replace these unsaved limits?", isPresented: $reload) { Button("Reload", role: .destructive) { load() } }
    }
    private func populate(_ value: NativeAgentLimits) { steps = String(value.maxSteps); minutes = String(value.maxMinutes); total = String(value.maxTotalTokens); input = String(value.maxInputTokens); output = String(value.maxOutputTokens); effort = value.effort }
    private func load() { run { let next = try await workspace.limits(); snapshot = next; populate(next.limits); saved = false } }
    private func run(_ action: @escaping @MainActor () async throws -> Void) { guard !busy else { return }; busy = true; issue = nil; Task { defer { busy = false }; do { NSApp.keyWindow?.makeFirstResponder(nil); await Task.yield(); try await action() } catch { issue = error.localizedDescription } } }
}

private struct MacAgentGuidanceEditor: View {
    let workspace: MacAgentWorkspace
    let status: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: NativeAgentGuidanceSnapshot?
    @State private var value = NativeAgentGuidance()
    @State private var busy = false
    @State private var saved = false
    @State private var discard = false
    @State private var reload = false
    @State private var issue: String?
    private var dirty: Bool { snapshot.map { $0.guidance != value } ?? false }
    private var valid: Bool { (try? value.validate()) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vault instructions & memory").font(.title2.bold())
            Text("Saved text is shared with your provider for new runs. Existing runs keep their starting instructions; an explicit memory read can retrieve newer saved reference data. Guidance cannot grant note access or override your request.").font(.caption).foregroundStyle(.secondary)
            Text("Vault instructions · \(value.instructions.utf16.count)/12,000").font(.headline)
            TextEditor(text: $value.instructions).disabled(snapshot == nil).font(.system(.body, design: .monospaced)).accessibilityLabel("Vault instructions")
            Text("Editable memory · \(value.memory.utf16.count)/8,000").font(.headline)
            TextEditor(text: $value.memory).disabled(snapshot == nil).font(.system(.body, design: .monospaced)).accessibilityLabel("Editable memory")
            Text("Memory is reference information. Only you edit these saved preferences.").font(.caption).foregroundStyle(.secondary)
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if saved && !dirty { Label("Saved", systemImage: "checkmark.circle") }
            HStack {
                ShareLink("Export draft", item: "Vault instructions\n\n" + value.instructions + "\n\nEditable memory\n\n" + value.memory)
                Button("Reload") { if dirty { reload = true } else { load() } }.disabled(busy)
                Spacer(); Button("Done") { if dirty { discard = true } else { dismiss() } }.disabled(busy)
                Button("Save guidance") { guard let snapshot else { return }; run { self.snapshot = try await workspace.saveGuidance(value, expected: snapshot); saved = true } }.disabled(busy || !dirty || !valid)
            }
        }.padding(12).disabled(busy).onAppear { if !dirty { load() } }.onChange(of: busy || dirty, initial: true) { _, value in status(value) }.interactiveDismissDisabled(busy || dirty)
        .confirmationDialog("Discard unsaved guidance?", isPresented: $discard) { Button("Discard changes", role: .destructive) { dismiss() } }
        .confirmationDialog("Reload and replace unsaved guidance?", isPresented: $reload) { Button("Reload", role: .destructive) { load() } }
    }
    private func load() { run { let next = try await workspace.guidance(); snapshot = next; value = next.guidance; saved = false } }
    private func run(_ action: @escaping @MainActor () async throws -> Void) { guard !busy else { return }; busy = true; issue = nil; Task { defer { busy = false }; do { NSApp.keyWindow?.makeFirstResponder(nil); await Task.yield(); try await action() } catch { issue = error.localizedDescription } } }
}

private struct MacAgentWorkflowsEditor: View {
    let workspace: MacAgentWorkspace
    let status: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: NativeAgentWorkflowCatalog?
    @State private var selected = ""
    @State private var title = ""
    @State private var source = ""
    @State private var document: NativeAgentWorkflowDocument?
    @State private var busy = false
    @State private var discard = false
    @State private var discardDraft = false
    @State private var reload = false
    @State private var issue: String?
    private var workflowDirty: Bool { document.map { $0.source != source || $0.bytes == nil } ?? false }
    private var dirty: Bool { workflowDirty || (catalog.map { selected != $0.selectedID } ?? false) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workflows").font(.title2.bold())
            Text("Choose instructions for new runs or edit a Markdown workflow. Workflow text cannot expand note permissions.").font(.caption).foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading, spacing: 10) {
                if let catalog {
                    Picker("New-run workflow", selection: $selected) { Text("General notes task").tag(""); ForEach(catalog.workflows) { Text($0.title).tag($0.id) }; if !selected.isEmpty && !catalog.workflows.contains(where: { $0.id == selected }) { Text("Unavailable saved workflow").tag(selected) } }
                    Button("Save selection") { run { self.catalog = try await workspace.selectWorkflow(selected, expected: catalog) } }.disabled(selected == catalog.selectedID || !selected.isEmpty && !catalog.workflows.contains(where: { $0.id == selected }))
                    DisclosureGroup("Available workflows") {
                        ForEach(catalog.workflows) { workflow in HStack {
                            Text(workflow.title); Spacer()
                            if let saved = catalog.custom.first(where: { $0.id == workflow.id }) {
                                Button("Edit") { document = saved; source = saved.source }.disabled(workflowDirty)
                            } else {
                                Button("Make custom copy") { run {
                                    let draft = try await workspace.newWorkflow(title: String(workflow.title.prefix(90)) + " copy")
                                    document = draft; source = draft.source + workflow.instructions + "\n"
                                } }.disabled(workflowDirty)
                            }
                        } }
                    }
                    HStack { TextField("New workflow name", text: $title); Button("Create draft") { run { let new = try await workspace.newWorkflow(title: title); document = new; source = new.source } }.disabled(workflowDirty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    ForEach(catalog.notices, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }
                if let document {
                    Text("Editing: " + URL(fileURLWithPath: document.id).lastPathComponent).font(.headline).textSelection(.enabled)
                    Text("\(source.utf16.count)/12,000 characters").font(.caption).foregroundStyle(source.utf16.count > 12_000 ? .red : .secondary)
                    if source.utf16.count > 12_000 { Text("Shorten the workflow before saving. You can export the full draft.").font(.caption).foregroundStyle(.orange) }
                    TextEditor(text: $source).font(.system(.body, design: .monospaced)).frame(minHeight: 230).accessibilityLabel("Workflow Markdown")
                    HStack {
                        ShareLink("Export workflow draft", item: source)
                        Button("Discard workflow draft") { if workflowDirty { discardDraft = true } else { clearDraft() } }
                        Button("Save workflow") { run {
                            let isNew = document.bytes == nil
                            self.document = try await workspace.saveWorkflow(source, expected: document)
                            let fresh = try await workspace.workflows(); catalog = fresh
                            if isNew {
                                do { catalog = try await workspace.selectWorkflow(document.id, expected: fresh); selected = document.id }
                                catch { throw VaultFailure(message: "The workflow was saved, but could not be selected: " + error.localizedDescription) }
                            }
                        } }.disabled(!workflowDirty || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source.utf16.count > 12_000)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Button("Reload") { if dirty { reload = true } else { load() } }; Spacer(); Button("Done") { if dirty { discard = true } else { dismiss() } } }
        }.padding(12).disabled(busy).onAppear { if !dirty { load() } }.onChange(of: busy || dirty, initial: true) { _, value in status(value) }.interactiveDismissDisabled(busy || dirty)
        .confirmationDialog("Discard unsaved workflow changes?", isPresented: $discard) { Button("Discard changes", role: .destructive) { dismiss() } }
        .confirmationDialog("Reload and replace the unsaved workflow draft?", isPresented: $reload) { Button("Reload", role: .destructive) { load() } }
        .confirmationDialog("Discard only this workflow draft?", isPresented: $discardDraft) { Button("Discard draft", role: .destructive) { clearDraft() } } message: { Text("The new-run workflow selection will be kept.") }
    }
    private func clearDraft() { document = nil; source = "" }
    private func load() { run { let next = try await workspace.workflows(); catalog = next; selected = next.selectedID; clearDraft() } }
    private func run(_ action: @escaping @MainActor () async throws -> Void) { guard !busy else { return }; busy = true; issue = nil; Task { defer { busy = false }; do { NSApp.keyWindow?.makeFirstResponder(nil); await Task.yield(); try await action() } catch { issue = error.localizedDescription } } }
}

private struct MacAgentPreferencesEditor: View {
    let workspace: MacAgentWorkspace
    let status: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: NativeAgentPreferencesSnapshot?
    @State private var value = NativeAgentPreferences()
    @State private var busy = false
    @State private var discard = false
    @State private var reload = false
    @State private var issue: String?
    private var dirty: Bool { snapshot.map { $0.value != value } ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Defaults for new runs").font(.title2.bold())
            Text("Defaults travel with this vault. Each run keeps the preferences it started with; its chosen mode and note permissions remain authoritative.").font(.caption).foregroundStyle(.secondary)
            if snapshot?.needsNormalization == true { Text("Unsupported saved preference values use the web defaults shown here. Save defaults to apply those values; reading has kept the original file unchanged.").font(.caption).foregroundStyle(.orange) }
            Form {
                Picker("Default mode", selection: $value.mode) { ForEach(NativeAgentPreferences.Mode.allCases) { Text($0.native.rawValue).tag($0) } }
                Picker("Write scope", selection: $value.writeScope) { Text("Notes in read access").tag(NativeAgentPreferences.WriteScope.context); Text("Current note only").tag(NativeAgentPreferences.WriteScope.current) }
                Toggle("Text tool fallback", isOn: $value.textFallback)
                Text("For connections without native tool calls. Text requests still use the selected mode, note permissions, read revisions and approval flow.").font(.caption).foregroundStyle(.secondary)
                Toggle("Independent note analysis workers", isOn: $value.workers)
                Text("Allows additional read-only provider requests within a run's chosen note context and budget. Analysis cannot save changes or expand access.").font(.caption).foregroundStyle(.secondary)
            }.disabled(snapshot == nil)
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Spacer()
            HStack { Button("Reload") { if dirty { reload = true } else { load() } }; Spacer(); Button("Done") { if dirty { discard = true } else { dismiss() } }; Button("Save defaults") { guard let snapshot else { return }; run { self.snapshot = try await workspace.savePreferences(value, expected: snapshot) } }.disabled(!dirty && snapshot?.needsNormalization != true) }
        }.padding(12).disabled(busy).onAppear { if !dirty { load() } }.onChange(of: busy || dirty, initial: true) { _, value in status(value) }.interactiveDismissDisabled(busy || dirty)
        .confirmationDialog("Discard unsaved run defaults?", isPresented: $discard) { Button("Discard", role: .destructive) { dismiss() } }
        .confirmationDialog("Reload and replace unsaved run defaults?", isPresented: $reload) { Button("Reload", role: .destructive) { load() } }
    }
    private func load() { run { let next = try await workspace.preferences(); snapshot = next; value = next.value } }
    private func run(_ action: @escaping @MainActor () async throws -> Void) { guard !busy else { return }; busy = true; issue = nil; Task { defer { busy = false }; do { NSApp.keyWindow?.makeFirstResponder(nil); await Task.yield(); try await action() } catch { issue = error.localizedDescription } } }
}
