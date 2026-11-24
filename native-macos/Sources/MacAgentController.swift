import SwiftUI

/// Owns one window's active run. Providers receive frozen connection snapshots;
/// all note operations go through the Mac workspace's admission/commit boundary.
@MainActor final class MacAgentController: ObservableObject {
    @Published private(set) var current: NativeAgentRecord? {
        didSet {
            guard let current else { return }
            if let index = records.firstIndex(where: { $0.id == current.id }) { records[index] = current }
            else { records.insert(current, at: 0) }
        }
    }
    @Published private(set) var records: [NativeAgentRecord] = []
    @Published private(set) var unreadable: [String] = []
    @Published private(set) var running = false
    @Published private(set) var live = "" { didSet { transcript?.agentDidChange(live) } }
    @Published private(set) var issue: String?
    @Published private(set) var analysisProgress: String?
    @Published private(set) var contextProgress: String?
    @Published private(set) var review: NativeAgentReview?
    @Published private(set) var hasUnsavedState = false
    let workspace: MacAgentWorkspace
    private let client: MacAIClient
    private weak var host: MacWorkspace?
    private var retired = false, leaving = false
    private var transcript: MacAgentTranscript?
    private var operation: Task<Void, Never>?
    private var mark: TimeInterval?
    private var deadlineExpired = false

    init(workspace: MacWorkspace, owner: String, client: MacAIClient = .init()) throws {
        guard workspace.agentController?.running != true, workspace.agentController?.hasUnsavedState != true, workspace.agentController?.leaving != true else { throw VaultFailure(message: "Finish or preserve the active AI run before opening another controller.") }
        self.workspace = try .init(workspace: workspace, owner: owner, externalFiles: workspace.external.store)
        self.client = client; host = workspace
        workspace.agentController?.retire()
        workspace.agentController = self
    }
    private func retire() { retired = true; stop() }
    func cancelLeaving() { if !retired, host?.agentController === self { leaving = false } }
    private func canBegin() -> Bool {
        guard !running, !hasUnsavedState else { return false }
        deadlineExpired = false
        guard !retired, !leaving, let host, host.agentController === self, host.workspaceID == workspace.workspaceID else { issue = "This AI controller is leaving or was replaced. Reopen the current vault's run controls."; return false }
        guard !host.busy, !host.preparingToClose, !host.editorSheetActive, !host.agentSettingsActive, !host.imageSaving, !host.recoverySaving, !host.schemaMaintenanceSaving, !host.noteMovesSaving, !host.externalCopySaving, !host.paneLayoutSaving, !host.tasksSaving else { issue = "Finish the current vault change before starting or resuming an AI run."; return false }
        return true
    }
    func reload() async {
        guard !running, !hasUnsavedState else { return }
        let original = current?.bytes
        do {
            let result = try await workspace.records()
            guard !Task.isCancelled, !running, !hasUnsavedState, current?.bytes == original else { return }
            records = result.records; unreadable = result.unreadable
            if let id = current?.id {
                current = records.first(where: { $0.id == id })
                if current == nil { review = nil; live = "" }
            }
        } catch { if !(error is CancellationError), !running, current?.bytes == original, issue == nil { issue = error.localizedDescription } }
    }
    @discardableResult func start(prompt: String, mode: NativeAgentMode, scope: NativeAgentScope, chatID: String, attachments: [NativeChatAttachment] = [], imageIDs: [String] = [], history: String = "", reference: String = "", store: NativeChatAttachmentStore, provider: MacAgentProvider, transcript: MacAgentTranscript? = nil) -> Bool {
        guard canBegin() else { return false }
        self.transcript = transcript
        running = true; issue = nil; review = nil; current = nil; live = ""
        operation = Task { [self] in
            do {
                let binding = try provider.binding
                current = try await workspace.start(objective: prompt, mode: mode, scope: scope, chatID: chatID, history: history, reference: reference, attachments: attachments, imageIDs: imageIDs)
                // A saved run must keep its inputs even if Stop arrives before
                // the next journal await. These synchronous writes do not inherit
                // cancellation from provider binding.
                if !attachments.isEmpty {
                    try store.authorize(run: current!.id, chat: chatID, items: attachments)
                    for item in attachments { try store.retain(item) }
                }
                current = try await workspace.bindProvider(current!, binding: binding)
                try await transcript?.agentWillExecute(current!)
                try await execute(current!, store: store, provider: provider)
            } catch { await stopped(error) }
            let sink = self.transcript, record = current, text = live, message = issue
            await Task { @MainActor in await sink?.agentDidFinish(record, text: text, issue: message) }.value
            self.transcript = nil; running = false; mark = nil
            await reload()
        }
        return true
    }
    func validateResume(_ record: NativeAgentRecord, useSelectedConnection: Bool, provider: MacAgentProvider) throws {
        guard canBegin() else { throw VaultFailure(message: issue ?? "Finish the active run before resuming.") }
        let binding = try provider.binding
        let saved = useSelectedConnection ? nil : try MacAgentProviderBinding.read(record)
        guard useSelectedConnection || saved == binding else { throw VaultFailure(message: "The selected connection or model differs from this run. Review its saved context and explicitly choose the new connection before resuming.") }
    }
    @discardableResult func resume(_ record: NativeAgentRecord, answer: String? = nil, useSelectedConnection: Bool = false, store: NativeChatAttachmentStore, provider: MacAgentProvider, transcript: MacAgentTranscript? = nil) -> Bool {
        guard canBegin() else { return false }
        self.transcript = transcript
        running = true; issue = nil; review = nil; live = ""; current = nil
        operation = Task { [self] in
            do {
                let binding = try provider.binding
                let saved = useSelectedConnection ? nil : try MacAgentProviderBinding.read(record)
                guard useSelectedConnection || saved == binding else { throw VaultFailure(message: "The selected connection or model differs from this run. Review its saved context and explicitly choose the new connection before resuming.") }
                current = try await workspace.resume(record, answer: answer)
                if useSelectedConnection { current = try await workspace.bindProvider(current!, binding: binding) }
                try await transcript?.agentWillExecute(current!)
                try await execute(current!, store: store, provider: provider)
            } catch { await stopped(error) }
            // An admission failure keeps the selected run visible without
            // checkpointing a journal this attempt never acquired.
            if current == nil { current = record }
            let sink = self.transcript, record = current, text = live, message = issue
            await Task { @MainActor in await sink?.agentDidFinish(record, text: text, issue: message) }.value
            self.transcript = nil; running = false; mark = nil
            await reload()
        }
        return true
    }
    func stop() { operation?.cancel() }
    func prepareToLeave() async -> Bool {
        leaving = true
        return await stopAndCheckpoint()
    }
    func stopAndCheckpoint() async -> Bool {
        stop(); await operation?.value
        if hasUnsavedState { return await retryJournalFinalization() }
        return true
    }
    @discardableResult func retryJournalFinalization() async -> Bool {
        guard !running, !retired, hasUnsavedState, let id = current?.id else { return !hasUnsavedState }
        do {
            guard !MacWorkspace.windows.compactMap({ $0.value?.agentController }).contains(where: { $0 !== self && $0.running && $0.current?.id == id }) else { throw VaultFailure(message: "Another window is still using this run. Stop it before retrying the journal checkpoint.") }
            let latest = try await workspace.records()
            guard let saved = latest.records.first(where: { $0.id == id }), saved.run.owner == workspace.owner else { throw VaultFailure(message: "The saved run is unreadable, missing or owned elsewhere. Restore it before retrying, or explicitly discard only this window's unsaved state.") }
            let finalizer = Task { try await self.workspace.pause(saved, reason: "Recovered the run journal after a failed checkpoint.") }
            current = try await finalizer.value; hasUnsavedState = false
            issue = nil
            return true
        } catch { issue = "The run journal still needs recovery: " + error.localizedDescription; return false }
    }
    /// Only the explicit discard action may clear unsaved local state. Saved
    /// journal bytes and note changes are never deleted or rewritten here.
    func discardUnsavedState() {
        guard !running, hasUnsavedState else { return }
        current = nil; live = ""; review = nil; mark = nil; hasUnsavedState = false
        issue = "Unsaved local run state discarded. The saved journal was not changed."
    }
    func open(_ record: NativeAgentRecord) async throws {
        guard canBegin() else { throw VaultFailure(message: issue ?? "Finish the active run before opening another run.") }
        let saved = try await workspace.records()
        guard let latest = saved.records.first(where: { $0.id == record.id }), latest.run.owner == workspace.owner else { throw VaultFailure(message: "This saved run is missing or belongs to another device.") }
        current = latest; review = nil; issue = nil; live = ""
        try await preparePendingReview()
    }
    func importWebMigration(_ prepared: MacWebAgentMigrationReview, store: NativeChatAttachmentStore) async throws {
        guard canBegin() else { throw VaultFailure(message: issue ?? "Finish the active run before importing another run.") }
        running = true; defer { running = false }
        current = try await workspace.importWebMigration(prepared, store: store)
        review = nil; issue = nil; live = ""
        // Imported proposals are reviewed individually so one stale historical
        // proposal cannot hide the rest of the successfully imported history.
    }
    func refreshReview() async throws {
        guard canBegin() else { throw VaultFailure(message: issue ?? "Finish the active run before rebuilding its review.") }
        running = true; defer { running = false }
        try await preparePendingReview(); issue = nil
    }
    func reviewProposals(_ ids: Set<UUID>) async throws {
        guard canBegin(), let record = current else { throw VaultFailure(message: issue ?? "Open a saved run before reviewing its proposals.") }
        running = true; defer { running = false }
        review = try await workspace.review(record, ids: ids); issue = nil
    }
    private func checkpoint(_ record: NativeAgentRecord) async throws -> NativeAgentRecord {
        let now = ProcessInfo.processInfo.systemUptime, interval = mark.map { max(0, now - $0) } ?? 0
        let updated = try await workspace.elapsed(record, seconds: interval); mark = now; return updated
    }
    private func execute(_ initial: NativeAgentRecord, store: NativeChatAttachmentStore, provider: MacAgentProvider) async throws {
        let remaining = Double(initial.run.budget.maxMinutes * 60) - initial.run.activeSeconds
        guard remaining > 0 else { throw VaultFailure(message: "This run reached its saved time limit.") }
        mark = ProcessInfo.processInfo.systemUptime; deadlineExpired = false
        let deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(remaining), clock: .suspending) } catch { return }
            self?.deadlineExpired = true; self?.stop()
        }
        defer { deadline.cancel() }
        var record = initial, compacted = false
        while true {
            try Task.checkCancellation()
            if record.run.compactionPending == true {
                try await executeCompaction(record, store: store, provider: provider)
                record = current!; compacted = true; continue
            }
            let existing = Set(record.run.pending.map(\.id)), calls = record.run.pendingCalls
            for call in calls {
                try await transcript?.agentCheckAuthority(record)
                current = try await checkpoint(record); record = current!
                if call.name == "analyze_notes" { try await executeAnalysis(record, call: call, store: store, provider: provider) }
                else { current = try await workspace.tool(record, call: call) }
                record = current!
                if record.run.question != nil { break }
            }
            let added = record.run.pending.filter { !existing.contains($0.id) }
            if record.run.mode == .edit, record.run.question == nil, record.run.pending.count == 1, added.count == 1, !added.contains(where: { $0.after.document.trashed }) {
                let affected = Set(record.run.receipts.filter { $0.undoneAt == nil }.flatMap { $0.after.map(\.id) } + added.flatMap(\.afters).map(\.id))
                if affected.count == 1 {
                    let automatic = try await workspace.review(record, ids: Set(added.map(\.id)), automatic: true)
                    try Task.checkCancellation(); try await transcript?.agentCheckAuthority(record)
                    current = try await workspace.apply(automatic); record = current!
                }
            }
            if record.run.question != nil || calls.contains(where: { ["preview_changes", "apply_changes", "note_organize"].contains($0.name) }) && !record.run.pending.isEmpty {
                current = try await checkpoint(record); try await preparePendingReview(); return
            }
            current = try await checkpoint(record); record = current!
            let prepared: MacAgentRequest
            do {
                prepared = try await MacAgentRequest.prepare(record.run, store: store)
                try await provider.validateCapacity(prepared)
            } catch is MacAgentContextLimit {
                guard !compacted else { throw VaultFailure(message: "The compacted recent request, frozen instructions or image inputs still exceed this run/model's context allowance. All history and summaries are kept; choose a larger-capacity connection or start with larger input limits.") }
                try await minimumContextFits(record, store: store, provider: provider)
                let capacity = try await provider.contextCapacity()
                current = try await workspace.beginCompaction(record, inputLimit: capacity.map { $0 - record.run.budget.maxOutputTokens }); record = current!; continue
            }
            try await transcript?.agentCheckAuthority(record)
            current = try await workspace.reserveRequest(record, input: prepared.estimatedInput, output: prepared.outputLimit); record = current!
            live = ""
            let fallback = record.run.preferences?.textFallback == true
            var streamed = "", hidingTextCall = false
            let wire = try await provider.send(prepared, client: client, continuations: workspace.continuations) { [weak self] text in
                if hidingTextCall { return }
                streamed += text
                let visible = fallback ? MacAgentTextFallback.visible(streamed) : streamed
                hidingTextCall = visible.utf16.count < streamed.utf16.count
                self?.live = visible
            }
            let parsed = Result { try MacAgentTextFallback.parse(wire, run: record.run) }
            let accepted = try? parsed.get()
            let toolError: String?
            switch parsed { case .success: toolError = nil; case .failure(let error): toolError = error.localizedDescription }
            let reply = accepted?.reply ?? wire
            // A fully received reply is durable before honoring Stop. Only the
            // subsequent tool/request work is cancelled; reported usage is kept.
            let finalized = Task { [self] () throws -> (NativeAgentRecord, TimeInterval) in
                let input = reply.inputTokens ?? prepared.estimatedInput
                let output: Int
                if let reported = wire.outputTokens { output = reported }
                else { output = try await MacAgentRequest.outputTokens(content: wire.content, reasoning: wire.reasoning, calls: wire.calls) }
                let now = ProcessInfo.processInfo.systemUptime, interval = mark.map { max(0, now - $0) } ?? 0
                return (try await workspace.response(record, content: reply.content, calls: accepted == nil ? [] : reply.calls, input: input, output: output, seconds: interval, textToolSource: accepted?.source, toolError: toolError), now)
            }
            let (received, receivedAt) = try await finalized.value
            current = received; record = received; mark = receivedAt
            _ = try parsed.get()
            live = reply.content
            try Task.checkCancellation()
            if record.run.pendingCalls.isEmpty { current = try await checkpoint(record); try await preparePendingReview(); return }
        }
    }
    private func minimumContextFits(_ record: NativeAgentRecord, store: NativeChatAttachmentStore, provider: MacAgentProvider) async throws {
        var probe = record.run; probe.compactionPending = nil
        probe.messages = [.init(role: "user", content: "Original user request:\n" + probe.objective, images: record.run.messages.flatMap(\.images))]
        if let index = record.run.messages.indices.last(where: { $0 > 0 && record.run.messages[$0].role == "user" }) {
            var latest = record.run.messages[index]; latest.images = []
            probe.messages.append(latest)
        }
        do { let request = try await MacAgentRequest.prepare(probe, store: store); try await provider.validateCapacity(request) }
        catch is MacAgentContextLimit { throw VaultFailure(message: "The original request, latest user answer, frozen instructions/tools and retained images exceed the model's context capacity or this run's input allowance. Compaction cannot reduce them; nothing was sent. Choose a larger-capacity connection or start with larger input limits.") }
    }
    private func executeCompaction(_ initial: NativeAgentRecord, store: NativeChatAttachmentStore, provider: MacAgentProvider) async throws {
        defer { contextProgress = nil }
        try await minimumContextFits(initial, store: store, provider: provider)
        let capacity = try await provider.contextCapacity()
        let limit = min(initial.run.budget.maxInputTokens, capacity.map { $0 - initial.run.budget.maxOutputTokens } ?? initial.run.budget.maxInputTokens)
        current = try await workspace.retileCompaction(initial, inputLimit: limit)
        while let state = try MacAgentCompaction.read(current!) {
            try Task.checkCancellation()
            if state.complete { current = try await workspace.finishCompaction(current!); return }
            contextProgress = "Summarizing archived context \(state.next + 1) of \(state.ranges.count)…"
            current = try await checkpoint(current!)
            let request: MacAgentRequest
            do {
                request = try await workspace.compactionRequest(current!)
                try await provider.validateCapacity(request)
            } catch is MacAgentContextLimit {
                let smaller = state.inputLimit * 3 / 4
                guard smaller >= 1024 else { throw VaultFailure(message: "This saved reference summary cannot fit the model's minimum compaction context. Its progress and original archive are kept; choose a larger-capacity connection.") }
                current = try await workspace.retileCompaction(current!, inputLimit: smaller); continue
            }
            try await transcript?.agentCheckAuthority(current!)
            var probe = current!.run; probe.compactionPending = nil
            let reference = String(repeating: "reference ", count: state.outputLimit)
            probe.messages = MacAgentCompaction.continuation(probe, state: state, summary: reference)
            let finalInput: Int
            do {
                let finalRequest = try await MacAgentRequest.prepare(probe, store: store)
                try await provider.validateCapacity(finalRequest)
                finalInput = finalRequest.estimatedInput
            }
            catch let error as MacAgentContextLimit { throw VaultFailure(message: "The recent continuation state and retained inputs exceed this run/model's context allowance. No summary request was sent; all history and completed summaries are kept. " + error.localizedDescription) }
            current = try await workspace.reserveCompaction(current!, request: request, finalInput: finalInput)
            let reserved = current!
            let reply = try await provider.send(request, client: client, continuations: workspace.continuations, onDelta: { _ in })
            let saved = Task { [self] () throws -> (NativeAgentRecord, String?, TimeInterval) in
                let input = reply.inputTokens ?? request.estimatedInput
                let output: Int
                if let reported = reply.outputTokens { output = reported }
                else { output = try await MacAgentRequest.outputTokens(content: reply.content, reasoning: reply.reasoning, calls: reply.calls) }
                let now = ProcessInfo.processInfo.systemUptime, seconds = mark.map { max(0, now - $0) } ?? 0
                let (record, refusal) = try await workspace.compactionReply(reserved, reply: reply, input: input, output: output, seconds: seconds)
                return (record, refusal, now)
            }
            let (record, refusal, receivedAt) = try await saved.value
            current = record; mark = receivedAt
            try? workspace.continuations.remove(run: state.continuationID)
            if let refusal { throw VaultFailure(message: refusal) }
        }
    }
    private func executeAnalysis(_ initial: NativeAgentRecord, call: NativeAgentCall, store: NativeChatAttachmentStore, provider: MacAgentProvider) async throws {
        defer { analysisProgress = nil }
        current = try await workspace.beginAnalysis(initial, call: call)
        while let state = try MacAgentAnalysisState.read(current!) {
            try Task.checkCancellation()
            guard let index = state.next else {
                var limit = 16_000
                while limit > 0 {
                    var synthesis = current!.run
                    synthesis.messages.append(.init(role: "tool", content: try state.resultContent(maxAnswerBytes: limit), toolCallId: state.callID))
                    if let request = try? await MacAgentRequest.prepare(synthesis, store: store), (try? await provider.validateCapacity(request)) != nil { break }
                    try Task.checkCancellation(); limit /= 2
                }
                current = try await workspace.endAnalysis(current!, maxAnswerBytes: limit); return
            }
            try await transcript?.agentCheckAuthority(current!)
            current = try await checkpoint(current!)
            var child = state.children[index]
            child.activeSeconds = state.startedAtParentSeconds.map { max(0, current!.run.activeSeconds - $0) } ?? 0
            if !child.withinBudget || child.activeSeconds >= Double(child.budget.maxMinutes * 60) || child.pendingCalls.isEmpty && !child.canRequest || current!.run.steps >= current!.run.budget.maxSteps - 1 || Double(current!.run.budget.maxMinutes * 60) - current!.run.activeSeconds <= 30 {
                current = try await workspace.endAnalysisChild(current!, index: index, reason: "The saved worker limit was reached."); continue
            }
            if let read = child.pendingCalls.first {
                current = try await workspace.analysisRead(current!, index: index, call: read); continue
            }
            let request: MacAgentRequest
            do {
                request = try await MacAgentRequest.prepare(child, store: store, analysis: true)
                try await provider.validateCapacity(request)
            } catch {
                try Task.checkCancellation()
                current = try await workspace.endAnalysisChild(current!, index: index, reason: error.localizedDescription); continue
            }
            if request.estimatedInput + request.outputLimit + current!.run.budget.maxInputTokens + 1000 > current!.run.budget.maxTotalTokens - current!.run.inputTokens - current!.run.outputTokens {
                current = try await workspace.endAnalysisChild(current!, index: index, reason: "The parent's synthesis token allowance must be retained."); continue
            }
            try await transcript?.agentCheckAuthority(current!)
            current = try await workspace.reserveAnalysis(current!, index: index, input: request.estimatedInput, output: request.outputLimit)
            let reserved = current!
            analysisProgress = "Independent analysis \(index + 1) of 2…"
            let remaining = min(Double(child.budget.maxMinutes * 60) - child.activeSeconds, Double(reserved.run.budget.maxMinutes * 60) - reserved.run.activeSeconds - 30)
            let worker = Task { try await provider.send(request, client: client, continuations: workspace.continuations) { _ in } }
            var reachedWorkerDeadline = false
            let deadline = Task {
                do { try await Task.sleep(for: .seconds(remaining), clock: .suspending) } catch { return }
                reachedWorkerDeadline = true
                worker.cancel()
            }
            let wire: MacAgentCompletion
            do { wire = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() }) }
            catch {
                deadline.cancel(); try Task.checkCancellation()
                current = try await checkpoint(current!)
                current = try await workspace.endAnalysisChild(current!, index: index, reason: reachedWorkerDeadline ? "The worker reached its time limit." : error.localizedDescription)
                continue
            }
            deadline.cancel()
            let parsed = Result { try MacAgentTextFallback.parse(wire, run: child) }
            let accepted = try? parsed.get(), refusal: String?
            switch parsed { case .success: refusal = nil; case .failure(let error): refusal = error.localizedDescription }
            let finalized = Task { [self] in
                let output: Int
                if let reported = wire.outputTokens { output = reported }
                else { output = try await MacAgentRequest.outputTokens(content: wire.content, reasoning: wire.reasoning, calls: wire.calls) }
                let seconds = mark.map { max(0, ProcessInfo.processInfo.systemUptime - $0) } ?? 0
                return try await workspace.analysisReply(reserved, index: index, reply: accepted?.reply ?? wire, source: accepted?.source, refusal: refusal, input: wire.inputTokens ?? request.estimatedInput, output: output, seconds: seconds)
            }
            current = try await finalized.value
        }
    }
    private func stopped(_ error: Error) async {
        if case MacAnthropicAgentFailure.refused = error { live = "" }
        let message = deadlineExpired ? "This run reached its saved time limit. Its journal and proposals are retained." : error is CancellationError || (error as? URLError)?.code == .cancelled ? "Stopped. The run journal, proposals and receipts are retained." : error.localizedDescription
        issue = message
        guard let record = current else { return }
        let finalizer = Task { [self] in
            let timed = try await checkpoint(record)
            current = timed
            return try await workspace.pause(timed, reason: message)
        }
        do { current = try await finalizer.value }
        catch { hasUnsavedState = true; issue = message + " The run journal could not be updated: " + error.localizedDescription }
    }
    private func preparePendingReview() async throws {
        guard let record = current, !record.run.pending.isEmpty, record.run.question == nil else { review = nil; return }
        review = try await workspace.review(record, ids: Set(record.run.pending.map(\.id)))
    }
    func reviewUndo(_ receiptID: UUID) async throws {
        guard canBegin(), let record = current else { throw VaultFailure(message: issue ?? "Open a saved run before reviewing Undo.") }
        running = true; defer { running = false }
        review = try await workspace.undoReview(record, receiptID: receiptID); issue = nil
    }
    func deleteCurrent() async throws {
        guard canBegin(), let record = current else { throw VaultFailure(message: issue ?? "Finish the active run before deleting its journal.") }
        running = true; defer { running = false }
        let warning = try await workspace.delete(record)
        current = nil; review = nil; live = ""; records.removeAll { $0.id == record.id }; issue = warning
    }
    func approve(_ prepared: NativeAgentReview) async throws {
        guard !running, !hasUnsavedState, prepared.record.id == current?.id else { throw VaultFailure(message: "Finish the active run and reopen the current review before approving.") }
        running = true; defer { running = false }
        current = try await workspace.apply(prepared); review = nil
        running = false; await reload()
    }
    func reject(_ id: UUID) async throws {
        guard !running, !hasUnsavedState, let record = current else { throw VaultFailure(message: "Finish the active run before rejecting a proposal.") }
        running = true; defer { running = false }
        current = try await workspace.reject(record, proposalID: id); review = nil
    }
}
