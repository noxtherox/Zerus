import SwiftUI

struct MacAgentRunHost: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject var chat: MacChatController
    @State private var controller: MacAgentController?
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let controller { MacAgentRunView(workspace: workspace, chat: chat, controller: controller) }
            else { VStack(spacing: 16) { Text(issue ?? "Opening saved runs…"); Button("Done") { dismiss() } }.padding(30).frame(width: 560) }
        }.task {
            do {
                if let existing = workspace.agentController, existing.workspace.owner == chat.device.id { controller = existing }
                else { controller = try MacAgentController(workspace: workspace, owner: chat.device.id) }
                await controller?.reload()
            } catch { issue = error.localizedDescription }
        }
    }
}

private struct MacAgentRunView: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject var chat: MacChatController
    @ObservedObject var controller: MacAgentController
    @StateObject private var defaults = MacAgentRunDefaults()
    @State private var permissions = MacAgentPermissions()
    @State private var answer = ""
    @State private var busy = false
    @State private var issue: String?
    @State private var confirmingDiscard = false
    @State private var settings = false
    @State private var deleting = false
    @State private var replacement: MacAgentProvider?
    @State private var replacementRecord: NativeAgentRecord?
    @State private var replacing = false
    @State private var webRuns: [MacWebAgentRunSummary] = []
    @State private var webIssues: [String] = []
    @State private var migration: MacWebAgentMigrationReview?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("zerus.mac.ai.use-chatgpt") private var usingChatGPT = false
    @AppStorage("zerus.mac.ai.endpoint") private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("zerus.mac.ai.model") private var model = ""
    @AppStorage("zerus.mac.ai.context-window") private var capacity = 32_768
    @AppStorage("zerus.mac.ai.format") private var format = MacAIFormat.compatible.rawValue
    private var locked: Bool { busy || controller.running || chat.isBusy }
    private var paths: Set<String> { chat.contextPaths ?? [] }
    private var folders: [String] { Array(Set([""] + workspace.folders.filter { $0.split(separator: "/").allSatisfy { !$0.hasPrefix(".") } })).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Button("Run settings…") { settings = true }.disabled(locked)
                Label("Agent runs", systemImage: "sparkles").macFont(.title2.bold()); Spacer(); if controller.running || chat.isBusy { ProgressView().controlSize(.small); Button("Stop") { chat.stop(); controller.stop() } }; Button("Done") { perform { if await chat.prepareToLeave(), await controller.stopAndCheckpoint() { dismiss() } } }.disabled(busy) }
            HSplitView {
                ScrollView { LazyVStack(alignment: .leading, spacing: 8) {
                    Text("Saved in this vault").macFont(.headline)
                    ForEach(controller.records) { record in
                        Button { perform { try await chat.select(record.run.chatID); try await controller.open(record) } } label: {
                            VStack(alignment: .leading, spacing: 4) { Text(record.run.objective).lineLimit(2); Text(record.run.mode.rawValue + " · " + record.run.status).macFont(.caption).foregroundStyle(.secondary) }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(controller.current?.id == record.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(MacBoxButtonStyle()).accessibilityElement(children: .combine).accessibilityAddTraits(controller.current?.id == record.id ? .isSelected : []).disabled(locked || controller.hasUnsavedState || record.run.owner != chat.device.id)
                    }
                    ForEach(controller.unreadable, id: \.self) { Text($0).macFont(.caption).foregroundStyle(.orange) }
                    if !webRuns.isEmpty { Text("Web runs in this conversation").macFont(.headline).padding(.top, 8) }
                    ForEach(webRuns) { record in
                        Button {
                            let activation = workspace.workspaceID, selected = chat.selectedID
                            perform {
                                let connection = try await provider()
                                let prepared = try await controller.workspace.prepareWebMigration(path: record.path, binding: connection.binding, contextCapacity: connection.contextCapacity())
                                guard activation == workspace.workspaceID, selected == chat.selectedID, selected == prepared.record.run.chatID else { throw VaultFailure(message: "The vault or conversation changed. Reopen the web run in its original conversation.") }
                                migration = prepared
                            }
                        } label: { VStack(alignment: .leading, spacing: 4) {
                            Text(record.objectivePreview).lineLimit(2)
                            Text(record.mode.rawValue + " · " + record.status).macFont(.caption).foregroundStyle(.secondary)
                            Text("Review import…").macFont(.caption)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(MacBoxButtonStyle()).disabled(locked || !chat.writable || controller.hasUnsavedState)
                    }
                    ForEach(webIssues, id: \.self) { Text($0).macFont(.caption).foregroundStyle(.orange) }
                } }.frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
                ScrollView { VStack(alignment: .leading, spacing: 14) {
                    GroupBox("New run") {
                        VStack(alignment: .leading, spacing: 9) {
                            Picker("Mode", selection: $defaults.mode) { ForEach(NativeAgentMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                            Text(defaults.mode.explanation).macFont(.caption).foregroundStyle(.secondary)
                            Button("Use saved defaults") { defaults.useSaved() }.disabled(!defaults.ready)
                            Picker("Write scope", selection: $defaults.writeScope) { Text("Notes in read access").tag(NativeAgentPreferences.WriteScope.context); Text("Current note only").tag(NativeAgentPreferences.WriteScope.current) }
                            Picker("Read access", selection: $permissions.readScope) { ForEach(MacAgentPermissions.ReadScope.allCases) { Text($0.rawValue).tag($0) } }
                            if permissions.readScope == .folder {
                                Picker("Read folder", selection: $permissions.folder) { ForEach(folders, id: \.self) { Text($0.isEmpty ? "Inbox" : $0).tag($0) } }
                            }
                            Text(permissions.readScope == .selected ? "Only the \(paths.count) notes chosen with Context are readable." : permissions.readScope == .folder ? (permissions.folder.isEmpty ? "Only notes directly in Inbox are readable." : "Notes in this folder and its child folders are readable.") : "All readable notes in this vault are available to the agent.").macFont(.caption)
                            if defaults.mode != .ask { Text(defaults.writeScope == .current ? "Only the current note can be changed." : permissions.readScope == .vault ? "Every ordinary, unarchived vault note can be changed." : permissions.readScope == .folder ? "Every ordinary, unarchived note in this folder and its child folders can be changed." : "Only the chosen context notes can be changed.").macFont(.caption).foregroundStyle(.secondary) }
                            if defaults.mode != .ask { Text("Archived notes in the write scope can only be unarchived; their body stays protected until then.").macFont(.caption2).foregroundStyle(.secondary) }
                            if defaults.mode != .ask && defaults.writeScope != .current {
                                Toggle("Allow new notes", isOn: $permissions.create)
                                if permissions.create {
                                    if permissions.readScope == .selected { Picker("Creation folder", selection: $permissions.creationFolder) { ForEach(folders, id: \.self) { Text($0.isEmpty ? "Inbox" : $0).tag($0) } } }
                                    Text(permissions.readScope == .vault ? "New notes may be created in any ordinary folder." : "New notes may be created only in " + ((permissions.readScope == .folder ? permissions.folder : permissions.creationFolder).isEmpty ? "Inbox." : (permissions.readScope == .folder ? permissions.folder : permissions.creationFolder) + ".")).macFont(.caption)
                                }
                            } else { Text("New-note creation is disabled for Ask and current-note-only writes.").macFont(.caption).foregroundStyle(.secondary) }
                            if defaults.mode != .ask && defaults.writeScope != .current {
                                Toggle("Allow filing notes into other folders", isOn: $permissions.fileNotes)
                                if permissions.fileNotes {
                                    if permissions.readScope == .selected { Picker("Filing destination", selection: $permissions.filingFolder) { ForEach(folders, id: \.self) { Text($0.isEmpty ? "Inbox" : $0).tag($0) } } }
                                    Text(permissions.readScope == .vault ? "Filing is permitted into ordinary vault folders." : "Filing is permitted into the chosen folder and its child folders; Inbox permits only root-level notes.").macFont(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text("Permissions apply to this saved run. Other clients choose permissions again for a new run.").macFont(.caption2).foregroundStyle(.secondary)
                            Text(chat.draft.isEmpty ? "Enter your request in the conversation composer before starting." : chat.draft).lineLimit(4).textSelection(.enabled)
                            Button("Start \(defaults.mode.rawValue)") { start() }.disabled(locked || !chat.writable || chat.hasUnsavedReply || controller.hasUnsavedState || !defaults.ready || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.selectedImages.isEmpty && chat.selectedDocuments.isEmpty)
                        }.padding(5)
                    }.disabled(locked || defaults.loading || defaults.snapshot == nil)
                    if let record = controller.current {
                        Text(record.run.objective).macFont(.headline).textSelection(.enabled)
                        Text("\(record.run.status) · \(record.run.steps) steps · \(record.run.inputTokens + record.run.outputTokens) tokens").macFont(.caption).foregroundStyle(.secondary)
                        Text("Read access: " + record.run.scopeLabel).macFont(.caption)
                        if let context = try? MacAgentCompaction.read(record) {
                            Text("Saved context compaction: \(context.next) of \(context.ranges.count) summaries complete. Resume continues within this run's paid request limits; original messages remain archived.").macFont(.caption).foregroundStyle(.secondary)
                        }
                        Text(record.run.createFolders.isEmpty ? "New-note creation is disabled for this run." : "New notes: " + record.run.createFolders.map { $0 == "*" ? "Any ordinary folder" : $0.isEmpty ? "Inbox" : $0 }.joined(separator: ", ")).macFont(.caption).foregroundStyle(.secondary)
                        Text((record.run.organizationFolders ?? []).isEmpty ? "Filing into other folders is disabled for this run." : "Filing destinations: " + (record.run.organizationFolders ?? []).map { $0 == "*" ? "Any ordinary folder" : $0.isEmpty ? "Inbox" : $0 + " and child folders" }.joined(separator: ", ")).macFont(.caption).foregroundStyle(.secondary)
                        if !controller.live.isEmpty { Text(controller.live).textSelection(.enabled) }
                        if let progress = controller.analysisProgress { Text(progress).macFont(.caption).foregroundStyle(.secondary) }
                        if let progress = controller.contextProgress { Text(progress).macFont(.caption).foregroundStyle(.secondary) }
                        if let question = record.run.question { Text(question).macFont(.headline); TextField("Your answer", text: $answer) }
                        if let review = controller.review {
                            Text(review.label).macFont(.headline)
                            Text("Approval saves these exact files. Changed files or a newer journal will be refused.").macFont(.caption).foregroundStyle(.secondary)
                            ForEach(review.reviewedFiles, id: \.path) { change in
                                GroupBox(change.path) { VStack(alignment: .leading, spacing: 8) {
                                    DisclosureGroup("Current") { Text(change.before.map { String(decoding: $0, as: UTF8.self) } ?? "File does not exist").macFont(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                                    Text("After approval").macFont(.caption.bold())
                                    Text(change.after.map { String(decoding: $0, as: UTF8.self) } ?? "Remove file").macFont(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading) }
                            }
                            Button("Apply reviewed changes") { perform { try await chat.validateAgentConversation(review.record); try await controller.approve(review) } }.disabled(locked || !chat.writable)
                        }
                        if !record.run.pending.isEmpty {
                            ForEach(record.run.pending) { proposal in HStack { Text(proposal.label).macFont(.caption); Spacer(); Button("Review") { perform { try await chat.validateAgentConversation(record); try await controller.reviewProposals([proposal.id]) } }.disabled(locked || !chat.writable); Button("Reject") { perform { try await chat.validateAgentConversation(record); try await controller.reject(proposal.id) } }.disabled(locked || !chat.writable) } }
                            if controller.review == nil, record.run.question == nil { Button("Rebuild review") { perform { try await controller.refreshReview() } }.disabled(locked || !chat.writable) }
                        }
                        if !record.run.receipts.isEmpty {
                            DisclosureGroup("Saved change receipts") {
                                ForEach(record.run.receipts) { receipt in
                                    HStack {
                                        VStack(alignment: .leading) { Text(receipt.date.formatted()).macFont(.caption); Text(receipt.undoneAt == nil ? "\(receipt.after.count) notes saved" : "Undone").macFont(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        if receipt.undoneAt == nil { Button("Review Undo") { perform { try await chat.validateAgentConversation(record); try await controller.reviewUndo(receipt.id) } }.disabled(locked || !chat.writable) }
                                    }
                                }
                            }
                        }
                        Button("Delete run journal…", role: .destructive) { deleting = true }.disabled(locked || controller.hasUnsavedState)
                        if record.run.status != "complete" {
                            Button(record.run.question == nil ? "Resume run" : "Send answer and resume") { resume(record) }.disabled(locked || !chat.writable || controller.hasUnsavedState || record.run.question != nil && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("Resume with current connection…") {
                                perform { replacement = try await provider(); replacementRecord = record; replacing = true }
                            }.disabled(locked || !chat.writable || controller.hasUnsavedState || record.run.question != nil && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    if controller.hasUnsavedState {
                        Text("The run journal needs recovery before more work can start.").foregroundStyle(.orange)
                        Button("Retry journal checkpoint") { perform { _ = await controller.retryJournalFinalization() } }.disabled(locked)
                        Button("Discard unsaved local run state…", role: .destructive) { confirmingDiscard = true }.disabled(locked)
                    }
                    if defaults.issue != nil { Button("Retry run defaults") { Task { await loadDefaults() } }.disabled(locked || defaults.loading) }
                    if let message = issue ?? defaults.issue ?? controller.issue { Text(message).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
                }.padding(.horizontal, 10) }.frame(minWidth: 460)
            }
            Text("Uses your configured connection. Requests share the allowed note context and frozen attachments with that provider. Stop keeps the run journal and partial conversation reply.").macFont(.caption2).foregroundStyle(.secondary)
        }.padding(20).frame(width: 940, height: 700).interactiveDismissDisabled(locked || controller.hasUnsavedState)
        .task { await loadDefaults() }
        .task(id: chat.selectedID) { await loadWebRuns() }
        .onChange(of: controller.records.map(\.id)) { Task { await loadWebRuns() } }
        .onChange(of: locked) { _, value in if !value && !defaults.ready { Task { await loadDefaults() } } }
        .onChange(of: settings) { _, shown in if !shown { Task { await loadDefaults() } } }
        .macSheet(isPresented: $settings) { MacAgentSettingsView(workspace: controller.workspace) }
        .macSheet(item: $migration, onDismiss: { Task { await loadWebRuns() } }) { prepared in
            MacWebAgentMigrationView(review: prepared) {
                try await chat.validateAgentConversation(prepared.record)
                try await controller.importWebMigration(prepared, store: MacAgentChatInput.store(root: prepared.root))
            }
        }
        .confirmationDialog("Resume using this connection?", isPresented: $replacing, titleVisibility: .visible) {
            Button("Use this connection and resume") {
                if let replacement, let replacementRecord { resume(replacementRecord, replacement: replacement) }
                replacement = nil; replacementRecord = nil
            }
            Button("Cancel", role: .cancel) { replacement = nil; replacementRecord = nil }
        } message: {
            Text("The run's frozen context and attachments will be shared with " + ((try? replacement?.binding.model) ?? "the selected model") + ". Existing permissions and limits stay in effect. Provider-specific continuations may require the original connection.")
        }
        .alert("Delete this run journal?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) {}
            Button("Delete journal", role: .destructive) { perform { try await controller.deleteCurrent() } }
        } message: { Text("Deleting the journal removes its native progress and Undo access. Applied notes and the conversation stay intact. Source/context archives and attachment files are retained. Private provider continuations are removed.") }
        .alert("Discard unsaved local run state?", isPresented: $confirmingDiscard) { Button("Cancel", role: .cancel) {}; Button("Discard local state", role: .destructive) { controller.discardUnsavedState() } } message: { Text("Unsaved run progress in this window will be lost. Saved journals and note files are kept.") }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; issue = nil
        Task { defer { busy = false }; do { try await action() } catch { issue = error.localizedDescription } }
    }
    private func provider() async throws -> MacAgentProvider {
        if usingChatGPT { return .chatGPT(connection: .shared, selection: try await MacChatGPTConnection.shared.selection()) }
        let profile = try await workspace.aiProfile(legacy: .legacy(endpoint: endpoint, model: model, contextWindow: capacity, format: MacAIFormat(rawValue: format) ?? .compatible))
        return .api(profile: profile, key: try await MacCredentials.read(profile.endpoint))
    }
    private func loadDefaults() async { await defaults.load(controller.workspace, available: !locked) }
    private func start() {
        let origin = workspace.workspaceID, selected = chat.selectedID, stamp = chat.inputStamp, currentPath = workspace.selection
        let requestedMode = defaults.mode, chosenPermissions = permissions, chosenWriteScope = defaults.writeScope
        perform {
            let connection = try await provider(), snapshot = try await workspace.chatContextSnapshot()
            guard origin == workspace.workspaceID, selected == chat.selectedID, stamp == chat.inputStamp, currentPath == workspace.selection else { throw VaultFailure(message: "The vault or request changed. Review the current context before starting.") }
            let sources = chosenPermissions.readScope == .selected ? try chat.resolveNoteContext(snapshot) : []
            let resolvedPaths = chat.contextPaths ?? []
            let scope = try chosenPermissions.scope(mode: requestedMode, writes: chosenWriteScope, current: currentPath, paths: resolvedPaths, notes: snapshot.notes)
            try await chat.sendAgent(controller: controller, mode: requestedMode, scope: scope, sources: sources, provider: connection, capacity: capacity)
        }
    }
    private func resume(_ record: NativeAgentRecord, replacement: MacAgentProvider? = nil) {
        let origin = workspace.workspaceID, selected = chat.selectedID
        perform {
            let connection: MacAgentProvider
            if let replacement { connection = replacement } else { connection = try await provider() }
            guard origin == workspace.workspaceID, selected == chat.selectedID else { throw VaultFailure(message: "The vault or conversation changed. Open the saved run again.") }
            try await chat.resumeAgent(record, controller: controller, answer: record.run.question == nil ? nil : answer, useSelectedConnection: replacement != nil, provider: connection)
            answer = ""
        }
    }
    private func loadWebRuns() async {
        guard let id = chat.selectedID else { webRuns = []; webIssues = []; return }
        let activation = workspace.workspaceID
        do {
            let catalog = try await controller.workspace.webRecords(chatID: id)
            guard activation == workspace.workspaceID, chat.selectedID == id else { return }
            let imported = Set(controller.records.compactMap { $0.run.webMigration?.sourcePath })
            webRuns = catalog.records.filter { $0.parentRunID == nil && !imported.contains($0.path) }; webIssues = catalog.issues
        } catch { if activation == workspace.workspaceID, chat.selectedID == id, !(error is CancellationError) { webIssues = [error.localizedDescription] } }
    }
}
