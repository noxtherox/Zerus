import SwiftUI

enum NativeAgentScopeChoice: String, CaseIterable, Identifiable {
    case selected = "Selected notes", folder = "Folder", vault = "Entire vault"
    var id: String { rawValue }
}

struct NativeAgentPermissionsView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @Binding var scope: NativeAgentScopeChoice
    @Binding var folder: String
    @Binding var create: Bool
    @Binding var creationFolder: String
    @Binding var currentOnly: Bool
    @Binding var currentPath: String
    let selected: Set<String>
    private var folders: [String] { Array(Set([""] + vault.notes.filter { NativeAgentNote.ordinary($0.path) && !$0.trashed }.map { ($0.path as NSString).deletingLastPathComponent })).sorted() }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Read context", selection: $scope) { ForEach(NativeAgentScopeChoice.allCases) { Text($0.rawValue).tag($0) } }.accessibilityIdentifier("agent.scope")
                    if scope == .folder { Picker("Folder", selection: $folder) { ForEach(folders, id: \.self) { Text($0.isEmpty ? "Inbox" : $0).tag($0) } }.accessibilityIdentifier("agent.folder") }
                    Text(scope == .selected ? "Only notes explicitly selected beside the prompt are available to the tools." : scope == .folder ? "The selected folder and its child folders are readable. New notes may be created in this folder." : "Notes across this vault are readable. Review and Edit may create ordinary Markdown notes in its folders.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Context shared when you send") }
                Section {
                    Toggle("Edit only one chosen note", isOn: $currentOnly).accessibilityIdentifier("agent.currentOnly")
                    if currentOnly {
                        Picker("Writable note", selection: $currentPath) {
                            Text("Choose a note").tag("")
                            ForEach(vault.notes.filter { note in
                                NativeAgentNote.ordinary(note.path) && !note.trashed && !note.archived && note.fileHub == nil && (scope == .vault || scope == .selected && selected.contains(note.path) || scope == .folder && (folder.isEmpty ? !note.path.contains("/") : note.path.hasPrefix(folder + "/")))
                            }) { Text($0.title).tag($0.path) }
                        }.accessibilityIdentifier("agent.writeTarget")
                        Text("The agent can read the context above, but only this note can be changed. New-note creation is disabled.").font(.caption).foregroundStyle(.secondary)
                    } else if scope == .selected {
                        Toggle("Allow new notes", isOn: $create).accessibilityIdentifier("agent.allowCreate")
                        if create { Picker("Creation folder", selection: $creationFolder) { ForEach(folders, id: \.self) { Text($0.isEmpty ? "Inbox" : $0).tag($0) } }.accessibilityIdentifier("agent.createFolder") }
                    }
                    Text("Ask always stays read-only. Archived notes, managed collections and connected documents cannot be edited by these note tools.").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Write boundary") }
            }.navigationTitle("Agent permissions").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("agent.permissions.done") } }
        }
    }
}

struct NativeAgentRunsView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: NativeAgentController
    @ObservedObject var chat: NativeChat
    let workspaceID: UUID
    var body: some View {
        NavigationStack {
            List {
                if let issue = controller.issue { Text(issue).foregroundStyle(.orange).font(.caption).textSelection(.enabled) }
                if controller.records.isEmpty && controller.unreadable.isEmpty { ContentUnavailableView("No AI runs", systemImage: "sparkles", description: Text("Requests sent from Ask keep their proposals, activity and verified receipts here.")) }
                ForEach(controller.records) { record in
                    NavigationLink { NativeAgentRunView(controller: controller, chat: chat, record: record, workspaceID: workspaceID) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.run.objective).lineLimit(3)
                            Text(record.run.mode.rawValue + " · " + record.run.scopeLabel).font(.caption).foregroundStyle(.secondary)
                            Text(Self.status(record, controller: controller)).font(.caption).foregroundStyle(record.run.pending.isEmpty ? Color.secondary : Color.orange)
                            Text(record.run.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("agent.run." + record.id.uuidString)
                }
                if !controller.unreadable.isEmpty {
                    Section { ForEach(controller.unreadable, id: \.self) { path in
                        NativeAgentJournalShare(path: path, workspaceID: workspaceID)
                    } } header: { Text("Needs attention") } footer: { Text("Unsupported journals are kept intact and are never resumed or overwritten.") }
                }
            }.navigationTitle("AI runs").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("agent.runs.done") } }
                .task { await controller.reload(vault: vault, workspace: workspaceID) }
                .refreshable { await controller.reload(vault: vault, workspace: workspaceID) }
        }
    }
    static func status(_ record: NativeAgentRecord, controller: NativeAgentController) -> String {
        if controller.running && controller.current?.id == record.id { return "Running" }
        if record.run.question != nil { return "Waiting for your answer" }
        if !record.run.pending.isEmpty { return "\(record.run.pending.count) proposed changes" }
        if !record.run.canRequest && record.run.status != "complete" { return "Saved run limit reached" }
        if record.run.status == "partial", record.run.trackedPlan?.contains(where: { $0.status != .complete }) == true { return "Plan unfinished" }
        return record.run.status == "running" ? "Interrupted — ready to continue" : record.run.status.capitalized
    }
}

private struct NativeAgentRunView: View {
    @EnvironmentObject private var vault: VaultStore
    @ObservedObject var controller: NativeAgentController
    @ObservedObject var chat: NativeChat
    @State var record: NativeAgentRecord
    let workspaceID: UUID
    @State private var review: NativeAgentReview?
    @State private var error: String?
    @State private var busy = false
    @State private var answer = ""
    @State private var resume = false
    @State private var rejecting: UUID?
    private var active: Bool { vault.workspaceID == workspaceID }
    private var unavailable: Bool { !active || busy || controller.running || chat.running }
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("agent.error") }
            if busy { ProgressView("Preparing review…").accessibilityIdentifier("agent.preparing") }
            if let question = record.run.question {
                Section("Your answer") {
                    Text(question).textSelection(.enabled)
                    ForEach(record.run.questionOptions, id: \.self) { value in Button(value) { answer = value }.disabled(unavailable) }
                    TextField("Answer", text: $answer, axis: .vertical).accessibilityIdentifier("agent.answer")
                    Button("Answer and continue") { resume = true }
                        .disabled(unavailable || !record.run.canResume || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("agent.resume")
                }
            }
            Section {
                Text(record.run.objective).font(.headline).textSelection(.enabled)
                LabeledContent("Mode", value: record.run.mode.rawValue)
                LabeledContent("Context", value: record.run.scopeLabel)
                LabeledContent("Read notes", value: String(record.run.readIDs.count))
                LabeledContent("Writable notes", value: String(record.run.writeIDs.count))
                if !record.run.createFolders.isEmpty { LabeledContent("New notes", value: record.run.createFolders.map { $0 == "*" ? "Any ordinary folder" : $0.isEmpty ? "Inbox" : $0 }.joined(separator: ", ")) }
                Text(record.run.mode.explanation).font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Exact note permissions") {
                    ForEach(record.run.readIDs, id: \.self) { id in
                        let matches = vault.notes.filter { NativeAgentNote.identity($0) == id && !$0.trashed && record.run.permitsPath($0.path) }
                        LabeledContent(matches.count == 1 ? matches[0].title : id, value: matches.count != 1 ? "Unavailable" : record.run.writeIDs.contains(id) ? "Read and edit" : "Read only").font(.caption)
                    }
                }
                Text(NativeAgentRunsView.status(record, controller: controller)).font(.subheadline)
            }
            if let steps = record.run.trackedPlan, !steps.isEmpty {
                Section {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: step.status.symbol).font(.title3).foregroundStyle(step.status == .running ? Accent.color : Color.secondary).frame(width: 25).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(index + 1). " + step.text).fixedSize(horizontal: false, vertical: true)
                                Text(step.status.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 3)
                            .accessibilityElement(children: .ignore).accessibilityLabel("Step \(index + 1). " + step.text).accessibilityValue(step.status.title).accessibilityIdentifier("agent.plan.step.\(index)")
                    }
                } header: { Text("Plan") } footer: { Text("Progress is reported by AI. Verified receipts confirm saved note changes.") }
            } else if !record.run.plan.isEmpty {
                Section { ForEach(Array(record.run.plan.enumerated()), id: \.offset) { index, step in Text("\(index + 1). " + step) } }
                header: { Text("Plan") } footer: { Text("Step statuses aren’t available for this saved plan.") }
            }
            if !record.run.pending.isEmpty {
                Section {
                    ForEach(record.run.pending) { proposal in
                        DisclosureGroup(proposal.label) {
                            LabeledContent("File", value: proposal.after.path).font(.caption)
                            if let companions = proposal.companions, !companions.isEmpty {
                                Text("Linked notes in this same review").font(.caption.bold())
                                ForEach(companions) { companion in Label(companion.after.title,systemImage:"link").font(.subheadline); Text(companion.after.path).font(.caption).foregroundStyle(.secondary) }
                            }
                            let propertiesChanged = proposal.before.map { $0.document.parts.header != proposal.after.document.parts.header } ?? false
                            if let before = proposal.before { Text(propertiesChanged ? "Before, including properties" : "Before").font(.caption.bold()); Text(propertiesChanged ? before.content : before.document.parts.body).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                            Text(propertiesChanged ? "Proposed, including properties" : "Proposed").font(.caption.bold()); Text(propertiesChanged ? proposal.after.content : proposal.after.document.parts.body).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Button("Review this change") { prepare(ids: [proposal.id]) }.disabled(unavailable).accessibilityIdentifier("agent.proposal.review." + proposal.id.uuidString)
                            Button("Reject proposal", role: .destructive) { rejecting = proposal.id }.disabled(unavailable)
                        }.accessibilityIdentifier("agent.proposal." + proposal.id.uuidString)
                    }
                    Button("Review all changes") { prepare(ids: Set(record.run.pending.map(\.id))) }.disabled(unavailable).accessibilityIdentifier("agent.reviewAll")
                } header: { Text("Proposed changes") } footer: { Text("These changes have not been saved. Review the exact files before approving.") }
            }
            if !record.run.receipts.isEmpty {
                Section("Verified receipts") {
                    ForEach(record.run.receipts) { receipt in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(receipt.after.map(\.title).joined(separator: ", ")).font(.subheadline)
                            Text(receipt.undoneAt == nil ? "Saved " + receipt.date.formatted(date: .abbreviated, time: .shortened) : "Undone").font(.caption).foregroundStyle(.secondary)
                            Text(receipt.id.uuidString).font(.caption2.monospaced()).textSelection(.enabled)
                            if receipt.undoneAt == nil { Button("Review undo") { prepareUndo(receipt.id) }.buttonStyle(.borderless).disabled(unavailable).accessibilityIdentifier("agent.undo." + receipt.id.uuidString) }
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section {
                if record.run.question == nil { Button("Continue this run") { resume = true }.disabled(unavailable || !record.run.canResume).accessibilityIdentifier("agent.resume") }
                NativeAgentJournalShare(path: NativeAgentJournal.path(record.id), workspaceID: workspaceID)
                LabeledContent("Workflow", value: record.run.workflow?.title ?? "General notes task")
                if let workflow = record.run.workflow { DisclosureGroup("Saved workflow instructions") { Text(workflow.instructions).textSelection(.enabled) } }
                LabeledContent("Model steps", value: "\(record.run.steps) / \(record.run.budget.maxSteps)")
                LabeledContent("Reported/estimated tokens", value: "\((record.run.inputTokens + record.run.outputTokens).formatted()) / \(record.run.budget.maxTotalTokens.formatted())")
                LabeledContent("Active seconds", value: "\(record.run.activeSeconds.rounded(.up).formatted(.number.precision(.fractionLength(0)))) / \(record.run.budget.maxMinutes * 60)")
                LabeledContent("Context token limit", value: record.run.budget.maxInputTokens.formatted())
                LabeledContent("Output token limit", value: record.run.budget.maxOutputTokens.formatted())
                LabeledContent("Reasoning effort", value: record.run.budget.effort.rawValue.capitalized)
                if let reservation = record.run.requestReservation {
                    LabeledContent("Reserved for current request", value: (reservation.input + reservation.output).formatted())
                    Text("If the request was interrupted without final usage, continuing keeps this allowance as an estimate before requesting more work.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Continuing uses this run’s displayed context and mode. Files, revisions and ownership are checked again. Existing pending proposals always remain reviewable.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Activity") { ForEach(record.run.events.reversed()) { event in VStack(alignment: .leading, spacing: 4) { Text(event.text).font(.caption); Text(event.date, style: .time).font(.caption2).foregroundStyle(.secondary) } } }
        }.navigationTitle("AI run").navigationBarTitleDisplayMode(.inline)
            .refreshable { await refresh() }
            .onChange(of: controller.records.first(where: { $0.id == record.id })?.bytes) { _, _ in if let latest = controller.records.first(where: { $0.id == record.id }) { record = latest } }
            .fullScreenCover(item: $review) { value in NativeAgentReviewView(controller: controller, plan: value, completed: { record = $0 }, close: { review = nil }) }
            .alert("Continue this \(record.run.mode.rawValue) run?", isPresented: $resume) {
                Button("Continue") {
                    guard chat.status.configured else { error = "Connect your AI account in Ask settings before continuing."; return }
                    controller.resume(record, answer: record.run.question == nil ? nil : answer, chat: chat, vault: vault, workspace: workspaceID)
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text(record.run.objective + "\n\n" + record.run.mode.explanation + "\nRead context: " + record.run.scopeLabel + ". Open Exact note permissions to inspect its boundaries. Continuing here supersedes an older writer of this journal.") }
            .confirmationDialog("Reject this proposal?", isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } }), titleVisibility: .visible) {
                if let rejecting { Button("Reject proposal", role: .destructive) { Task { busy = true; defer { busy = false }; do { record = try await vault.agentReject(record, owner: controller.owner, proposalID: rejecting, workspace: workspaceID); controller.accept(record) } catch { self.error = error.localizedDescription } } } }
            } message: { Text("Its note stays unchanged, and the rejection remains in the journal.") }
    }
    private func refresh() async { await controller.reload(vault: vault, workspace: workspaceID); if let latest = controller.records.first(where: { $0.id == record.id }) { record = latest } }
    private func prepare(ids: Set<UUID>) {
        Task { busy = true; defer { busy = false }; do { review = try await vault.agentReview(record, owner: controller.owner, ids: ids, workspace: workspaceID); error = nil } catch { self.error = error.localizedDescription } }
    }
    private func prepareUndo(_ receipt: UUID) {
        Task { busy = true; defer { busy = false }; do { review = try await vault.agentUndoReview(record, owner: controller.owner, receiptID: receipt, workspace: workspaceID); error = nil } catch { self.error = error.localizedDescription } }
    }
}

private struct NativeAgentReviewView: View {
    @EnvironmentObject private var vault: VaultStore
    @ObservedObject var controller: NativeAgentController
    let plan: NativeAgentReview
    let completed: (NativeAgentRecord) -> Void
    let close: () -> Void
    @State private var confirmation = false
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section { Text(plan.label).font(.headline); Text("Only the changes below are approved. Zerus will reject changed files or a newer run journal.").font(.caption).foregroundStyle(.secondary) }
                ForEach(plan.changedNotes, id: \.path) { change in
                    Section {
                        let current = change.before.flatMap { String(data: $0, encoding: .utf8) }, proposed = change.after.flatMap { String(data: $0, encoding: .utf8) }
                        let propertiesChanged = current != nil && proposed != nil && NoteDocument.split(current!).header != NoteDocument.split(proposed!).header
                        if propertiesChanged, let current, let proposed {
                            let schemaBytes = plan.changes.first(where:{$0.path == ".zerus/properties.json"})?.before
                            let definitions = (try? NativeSchemaSnapshot(root:plan.root,bytes:schemaBytes).checkedEffective(notePath:change.path)) ?? []
                            NativeAgentPropertyComparison(before: current, after: proposed, definitions:definitions, notes:plan.identities)
                            DisclosureGroup("Full Markdown source") {
                                Text("Current").font(.caption.bold()); Text(current).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                Text("After approval").font(.caption.bold()); Text(proposed).font(.system(.caption, design: .monospaced)).textSelection(.enabled).accessibilityIdentifier("agent.review.after." + change.path)
                            }.accessibilityIdentifier("agent.review.source." + change.path)
                        } else {
                            if let current { DisclosureGroup("Current") { Text(NoteDocument.split(current).body).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }
                            if let proposed { VStack(alignment: .leading, spacing: 8) { Text("After approval").font(.caption.bold()); Text(NoteDocument.split(proposed).body).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }
                            else { Text("Move this unchanged created note to Recently Deleted.").font(.caption) }
                        }
                    } header: { Text(change.path).accessibilityIdentifier("agent.review.file." + change.path) }
                }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }.navigationTitle("Review AI changes").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() }.disabled(saving).accessibilityIdentifier("agent.review.cancel") }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") { confirmation = true }.disabled(saving || controller.running).accessibilityIdentifier("agent.review.apply") }
                }
                .alert("Apply these exact changes?", isPresented: $confirmation) {
                    Button("Apply changes") {
                        Task { saving = true; defer { saving = false }; do { let saved = try await vault.applyAgent(plan, owner: controller.owner); controller.accept(saved); completed(saved); close() } catch { self.error = error.localizedDescription } }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("The note changes and verified receipt are committed together. Undo checks for newer work before restoring anything.") }
                .interactiveDismissDisabled(saving)
        }
    }
}

private struct NativeAgentPropertyComparison: View {
    let before: String
    let after: String
    var definitions: [NativePropertyDefinition] = []
    var notes: [NoteDocument] = []
    private struct Field: Identifiable {
        let id: String
        let name: String
        let before: NativePropertyValue?
        let after: NativePropertyValue?
    }
    private var fields: [Field] {
        let old = NativeFrontmatter(before), next = NativeFrontmatter(after)
        return Set((old.entries + next.entries).map(\.id)).sorted().compactMap { key in
            let a = old.entry(key), b = next.entry(key)
            guard !key.hasPrefix("zerus-"), a?.value != b?.value else { return nil }
            return .init(id: key, name: b?.key ?? a!.key, before: a?.value, after: b?.value)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Property changes").font(.headline).accessibilityIdentifier("agent.review.properties")
            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: 8) {
                    Text(field.name).font(.subheadline.weight(.semibold))
                    HStack(alignment: .top, spacing: 18) {
                        value(field.before, label: "Before", relation:definitions.first(where:{$0.id == field.id})?.type == .relation).frame(maxWidth: .infinity, alignment: .leading)
                        value(field.after, label: "After", relation:definitions.first(where:{$0.id == field.id})?.type == .relation).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.accessibilityElement(children: .combine).accessibilityIdentifier("agent.review.property." + field.id)
            }
            if NoteDocument.split(before).body == NoteDocument.split(after).body { Text("Your writing stays unchanged.").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 6)
    }
    private func value(_ value: NativePropertyValue?, label: String, relation: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if relation, let value, !value.selections.isEmpty {
                ForEach(Array(value.selections.enumerated()),id:\.offset) { _, raw in
                    let reference = NoteReference(wikilink:"[[" + raw + "]]")
                    let found = reference?.targets(in:notes) ?? []
                    Label(found.count == 1 ? found[0].title : reference?.label ?? raw,systemImage:"link").font(.body)
                }
            } else { Text(value.map { $0.display.isEmpty ? "Empty" : $0.display } ?? "Not set").font(.body).textSelection(.enabled) }
            if let value { Text(relation ? "Relation" : NativePropertyType.inferred(value).label).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

private struct NativeAgentJournalShare: View {
    @EnvironmentObject private var vault: VaultStore
    let path: String
    let workspaceID: UUID
    @State private var copy: URL?
    @State private var issue: String?
    @State private var preparing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let copy { ShareLink(item: copy) { Label("Share journal copy", systemImage: "square.and.arrow.up") } }
            else { Button { Task { preparing = true; defer { preparing = false }; do { copy = try await vault.exportAgentJournal(path, workspace: workspaceID); issue = nil } catch { issue = error.localizedDescription } } } label: { Label(preparing ? "Preparing copy…" : "Prepare journal for sharing", systemImage: "square.and.arrow.up") }.disabled(preparing) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.orange) }
        }
    }
}
