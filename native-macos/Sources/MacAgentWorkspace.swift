import Foundation
import Darwin

/// A run keeps the vault activation it started with. Provider requests do not
/// hold window locks; individual file operations admit and release them.
@MainActor final class MacAgentWorkspace {
    // An opening connection may have no selected session to hold yet. Check this
    // at both entry and presentation so it cannot slip through an actor await.
    static var fileOperations: Int { MacVaultFileAdmission.active }
    private weak var workspace: MacWorkspace?
    let workspaceID: UUID
    let root: URL
    let owner: String
    let continuations: MacAnthropicContinuations
    private let files: VaultFiles
    private let externalFiles: NativeExternalNotesStore
    private let identity: MacAgentFileIdentity

    init(workspace: MacWorkspace, owner: String, externalFiles: NativeExternalNotesStore) throws {
        guard let root = workspace.root, let files = workspace.io, !workspace.busy,
              !workspace.preparingToClose, !owner.isEmpty else { throw VaultFailure(message: "Open a writable vault before starting an AI run.") }
        self.workspace = workspace; workspaceID = workspace.workspaceID
        self.root = root; self.files = files; self.externalFiles = externalFiles; self.owner = owner; let identity = try MacAgentFileIdentity(root); self.identity = identity; continuations = .vault(identity)
    }
    private func current() throws -> MacWorkspace {
        guard let workspace, workspace.workspaceID == workspaceID,
              workspace.root?.resolvingSymlinksInPath().standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL,
              (try? MacAgentFileIdentity(root)) == identity else {
            throw VaultFailure(message: "The vault changed. Reopen this AI run in its original vault.")
        }
        return workspace
    }
    /// Journals may finish during another ordinary operation. Their actor and
    /// expected bytes serialize them; they cannot modify a note through this path.
    private func journal<T: Sendable>(_ operation: @Sendable (VaultFiles) async throws -> T) async throws -> T {
        _ = try current(); try Task.checkCancellation()
        let value = try await operation(files)
        _ = try current(); return value
    }
    private func admitted<T: Sendable>(flush: Bool, paths: [String] = [], _ operation: @Sendable (VaultFiles, [MacWorkspace], [MacExternalSession]) async throws -> T) async throws -> T {
        _ = try current(); try Task.checkCancellation()
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        let identity = identity
        let peers = MacWorkspace.windows.compactMap(\.value).filter { peer in
            guard let root = peer.root else { return false }
            return root.resolvingSymlinksInPath().standardizedFileURL == canonical || (try? MacAgentFileIdentity(root)) == identity
        }
        guard peers.allSatisfy({ !$0.busy && !$0.preparingToClose && !$0.editorSheetActive && !$0.schemaMaintenanceSaving && !$0.noteMovesSaving && !$0.imageSaving && !$0.externalCopySaving && !$0.recoverySaving && !$0.paneLayoutSaving && !$0.tasksSaving }) else {
            throw VaultFailure(message: "Finish the current change in every vault window before continuing this AI run.")
        }
        guard peers.allSatisfy({ $0.noteDiskChange == nil && (flush || !$0.isDirty) }) else {
            throw VaultFailure(message: "Save or resolve note drafts in every vault window before applying AI changes.")
        }
        var seen = Set<ObjectIdentifier>()
        let external = MacWorkspace.windows.compactMap { $0.value?.external.selected }.filter { session in
            seen.insert(ObjectIdentifier(session)).inserted && session.active && MacAgentExternalDrafts.related(session.snapshot.access.canonical, root: root, identity: identity, paths: paths)
        }
        guard external.allSatisfy({ !$0.agentLocked && !$0.transferring && !$0.exporting && !$0.conflict && (flush || !$0.dirty && !$0.saving) }) else {
            throw VaultFailure(message: "Save or resolve the connected-file draft and finish its current change before continuing this AI run.")
        }
        let activations = peers.map { ($0, $0.workspaceID) }
        MacVaultFileAdmission.active += 1
        peers.forEach { $0.agentWritingHeld = true; $0.busy = true }; external.forEach { $0.holdForAgent(true) }
        defer {
            MacVaultFileAdmission.active -= 1
            external.forEach { $0.holdForAgent(false) }
            for (peer, id) in activations where peer.workspaceID == id { peer.agentWritingHeld = false; peer.busy = false }
        }
        // Let the editor release focus/commit marked text before taking saved snapshots.
        await Task.yield()
        if flush { for peer in peers { guard await peer.save() else { throw VaultFailure(message: "An open note could not be saved. Its draft is retained; resolve it before continuing this AI run.") } } }
        if flush {
            for session in external {
                await session.saveForAgent()
                if session.dirty, let failure = session.failure { throw VaultFailure(message: "The connected file could not be saved: " + failure) }
            }
            if !external.isEmpty {
                let snapshot = try await files.scan()
                for peer in peers { await peer.adoptSchemaMaintenanceSnapshot(snapshot) }
            }
        }
        _ = try current(); try Task.checkCancellation()
        guard external.allSatisfy({ $0.active && !$0.dirty && !$0.conflict && !$0.saving }) else { throw VaultFailure(message: "Writing arrived in a connected-file editor. Its draft is retained; review the run again.") }
        guard activations.allSatisfy({ $0.0.workspaceID == $0.1 && !$0.0.isDirty && $0.0.noteDiskChange == nil }) else {
            throw VaultFailure(message: "Writing arrived during the AI operation. Your draft is retained; review the run again.")
        }
        let result = try await operation(files, peers, external)
        _ = try current(); return result
    }
    private func relatedStores(paths: [String] = []) -> [NativeExternalNotesStore] {
        MacWorkspace.windows.compactMap { $0.value?.external.selected }.filter {
            MacAgentExternalDrafts.related($0.snapshot.access.canonical, root: root, identity: identity, paths: paths)
        }.map(\.store)
    }
    func records() async throws -> NativeAgentRuns {
        let records = try await journal { try await $0.agentRuns() }
        try Task.checkCancellation()
        let activeChildren = try records.records.flatMap { try MacAgentAnalysisState.continuationIDs($0, includingFinished: false) }
        let retained = Set(records.records.map(\.id) + activeChildren + records.unreadable.compactMap { UUID(uuidString: URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent) })
        let cache = continuations
        do { try await Task.detached { try cache.prune(retaining: retained) }.value }
        catch { try current().issue = "Private Anthropic cache cleanup failed: " + error.localizedDescription }
        try Task.checkCancellation(); _ = try current(); return records
    }
    func webRecords(chatID: String) async throws -> MacWebAgentRunCatalog {
        try await journal { try await $0.macWebAgentRuns(chatID: chatID) }
    }
    func prepareWebMigration(path: String, binding: MacAgentProviderBinding, contextCapacity: Int? = nil) async throws -> MacWebAgentMigrationReview {
        let owner = owner
        return try await journal { try await $0.prepareMacWebAgentMigration(path: path, owner: owner, binding: binding, contextCapacity: contextCapacity) }
    }
    func importWebMigration(_ review: MacWebAgentMigrationReview, store: NativeChatAttachmentStore) async throws -> NativeAgentRecord {
        _ = try current()
        guard review.root == root else { throw VaultFailure(message: "Reopen this import review in its original vault.") }
        let owner = owner
        // Once private inputs are committed, finish the grant and public journal
        // together even if the sheet's task is cancelled. No provider is sent.
        return try await Task { @MainActor in
            let items = try await store.commit(review.attachments)
            do {
                if !items.isEmpty {
                    try store.authorize(run: review.id, chat: review.record.run.chatID, items: items)
                    for item in items { try store.retain(item) }
                }
                return try await self.admitted(flush: false) { io, _, _ in try await io.importMacWebAgentMigration(review, owner: owner) }
            } catch {
                // Never remove inputs if a transaction has become visible. The
                // exact saved record is the authority for a successful import.
                if let saved = try? await self.files.agentRuns().records.first(where: { $0.id == review.id }), saved.bytes == review.record.bytes { return saved }
                if !FileManager.default.fileExists(atPath: self.root.appendingPathComponent(NativeAgentJournal.path(review.id)).path) {
                    try? store.discardUncommittedWebInputs(run: review.id, chat: review.record.run.chatID, items: items)
                }
                throw error
            }
        }.value
    }
    private func settingsWrite<T: Sendable>(_ operation: @Sendable (VaultFiles) async throws -> T) async throws -> T {
        let window = try current(), activation = workspaceID
        guard !window.busy, !window.preparingToClose else { throw VaultFailure(message: "Finish the current change before saving AI settings.") }
        window.busy = true
        defer { if window.workspaceID == activation { window.busy = false } }
        do { let result = try await operation(files); _ = try current(); return result }
        catch {
            let message = error.localizedDescription
            if message.contains(".zerus/ai/"), message.contains("changed outside Zerus") {
                throw VaultFailure(message: "AI settings (.zerus/ai/settings.json or guidance/workflow files) changed. Reload the saved settings before trying again. Your draft is kept.")
            }
            throw error
        }
    }
    func setSettingsDraftHeld(_ held: Bool) { (try? current())?.agentSettingsActive = held }
    func preferences() async throws -> NativeAgentPreferencesSnapshot { try await journal { try await $0.agentPreferences() } }
    func savePreferences(_ value: NativeAgentPreferences, expected: NativeAgentPreferencesSnapshot) async throws -> NativeAgentPreferencesSnapshot {
        try await settingsWrite { io in try await io.saveAgentPreferences(value, expected: expected) }
    }
    func limits() async throws -> NativeAgentLimitsSnapshot { try await journal { try await $0.agentLimits() } }
    func guidance() async throws -> NativeAgentGuidanceSnapshot { try await journal { try await $0.agentGuidance() } }
    func workflows() async throws -> NativeAgentWorkflowCatalog { try await journal { try await $0.agentWorkflows() } }
    func saveLimits(_ value: NativeAgentLimits, expected: NativeAgentLimitsSnapshot) async throws -> NativeAgentLimitsSnapshot {
        try await settingsWrite { io in try await io.saveAgentLimits(value, expected: expected) }
    }
    func saveGuidance(_ value: NativeAgentGuidance, expected: NativeAgentGuidanceSnapshot) async throws -> NativeAgentGuidanceSnapshot {
        try await settingsWrite { io in try await io.saveAgentGuidance(value, expected: expected) }
    }
    func selectWorkflow(_ id: String, expected: NativeAgentWorkflowCatalog) async throws -> NativeAgentWorkflowCatalog {
        try await settingsWrite { io in try await io.saveAgentWorkflowSelection(id, expected: expected) }
    }
    func newWorkflow(title: String) async throws -> NativeAgentWorkflowDocument { try await journal { try await $0.newAgentWorkflow(title: title) } }
    func saveWorkflow(_ source: String, expected: NativeAgentWorkflowDocument) async throws -> NativeAgentWorkflowDocument {
        try await settingsWrite { io in try await io.saveAgentWorkflow(source, expected: expected) }
    }
    func bindProvider(_ record: NativeAgentRecord, binding: MacAgentProviderBinding) async throws -> NativeAgentRecord {
        let owner = owner
        return try await journal { try await $0.bindMacAgentProvider(record, owner: owner, binding: binding) }
    }
    func start(objective: String, mode: NativeAgentMode, scope: NativeAgentScope, chatID: String, history: String = "", reference: String = "", attachments: [NativeChatAttachment] = [], imageIDs: [String] = []) async throws -> NativeAgentRecord {
        let owner = owner
        var configured = scope; configured.allowArchivedOrganization = true
        let scope = configured
        return try await admitted(flush: true) { io, _, _ in
            try await io.agentStart(objective: objective, mode: mode, scope: scope, chatID: chatID, owner: owner, history: history, reference: reference, attachments: attachments, imageIDs: imageIDs)
        }
    }
    func response(_ record: NativeAgentRecord, content: String, calls: [NativeAgentCall], input: Int, output: Int, seconds: Double, textToolSource: String? = nil, toolError: String? = nil) async throws -> NativeAgentRecord {
        let owner = owner
        try MacAgentCompaction.checkNewCalls(record, calls: calls)
        return try await journal { try await $0.agentResponse(record, owner: owner, content: content, calls: calls, input: input, output: output, seconds: seconds, textToolSource: textToolSource, toolError: toolError) }
    }
    func beginCompaction(_ record: NativeAgentRecord, inputLimit: Int? = nil) async throws -> NativeAgentRecord {
        let owner = owner; return try await journal { try await $0.beginMacCompaction(record, owner: owner, inputLimit: inputLimit) }
    }
    func retileCompaction(_ record: NativeAgentRecord, inputLimit: Int) async throws -> NativeAgentRecord {
        let owner = owner; return try await journal { try await $0.retileMacCompaction(record, owner: owner, inputLimit: inputLimit) }
    }
    func compactionRequest(_ record: NativeAgentRecord) async throws -> MacAgentRequest {
        let owner = owner; return try await journal { try await $0.macCompactionRequest(record, owner: owner) }
    }
    func reserveCompaction(_ record: NativeAgentRecord, request: MacAgentRequest, finalInput: Int) async throws -> NativeAgentRecord {
        let owner = owner; return try await journal { try await $0.reserveMacCompaction(record, owner: owner, input: request.estimatedInput, output: request.outputLimit, finalInput: finalInput) }
    }
    func compactionReply(_ record: NativeAgentRecord, reply: MacAgentCompletion, input: Int, output: Int, seconds: Double) async throws -> (NativeAgentRecord, String?) {
        let owner = owner; return try await journal { try await $0.receiveMacCompaction(record, owner: owner, reply: reply, input: input, output: output, seconds: seconds) }
    }
    func finishCompaction(_ record: NativeAgentRecord) async throws -> NativeAgentRecord {
        let owner = owner; return try await journal { try await $0.finishMacCompaction(record, owner: owner) }
    }
    func tool(_ record: NativeAgentRecord, call: NativeAgentCall) async throws -> NativeAgentRecord {
        let owner = owner
        return try await admitted(flush: true) { io, _, _ in try await io.macAgentTool(record, owner: owner, call: call) }
    }
    func beginAnalysis(_ record: NativeAgentRecord, call: NativeAgentCall) async throws -> NativeAgentRecord {
        let owner = owner
        return try await admitted(flush: true) { io, _, _ in try await io.beginMacAnalysis(record, owner: owner, call: call) }
    }
    func analysisRead(_ record: NativeAgentRecord, index: Int, call: NativeAgentCall) async throws -> NativeAgentRecord {
        let owner = owner
        return try await admitted(flush: true) { io, _, _ in try await io.readMacAnalysis(record, owner: owner, index: index, call: call) }
    }
    func reserveAnalysis(_ record: NativeAgentRecord, index: Int, input: Int, output: Int) async throws -> NativeAgentRecord {
        let owner = owner
        return try await journal { try await $0.reserveMacAnalysis(record, owner: owner, index: index, input: input, output: output) }
    }
    func analysisReply(_ record: NativeAgentRecord, index: Int, reply: MacAgentCompletion, source: String?, refusal: String?, input: Int, output: Int, seconds: Double) async throws -> NativeAgentRecord {
        let owner = owner
        return try await journal { try await $0.replyMacAnalysis(record, owner: owner, index: index, reply: reply, source: source, refusal: refusal, input: input, output: output, seconds: seconds) }
    }
    func endAnalysisChild(_ record: NativeAgentRecord, index: Int, reason: String) async throws -> NativeAgentRecord {
        let owner = owner
        return try await journal { try await $0.finishMacAnalysisChild(record, owner: owner, index: index, reason: reason) }
    }
    func endAnalysis(_ record: NativeAgentRecord, maxAnswerBytes: Int) async throws -> NativeAgentRecord {
        let owner = owner
        let children = try MacAgentAnalysisState.continuationIDs(record, includingFinished: false)
        let saved = try await journal { try await $0.finishMacAnalysis(record, owner: owner, maxAnswerBytes: maxAnswerBytes) }
        do { for id in children { try continuations.remove(run: id) } }
        catch { try current().issue = "Independent analysis finished, but its private continuation cleanup failed: " + error.localizedDescription }
        return saved
    }
    func review(_ record: NativeAgentRecord, ids: Set<UUID>, automatic: Bool = false) async throws -> NativeAgentReview {
        let owner = owner, activation = workspaceID
        return try await admitted(flush: true) { io, _, _ in
            var review = try await io.macAgentReview(record, owner: owner, ids: ids, automatic: automatic)
            review.workspaceID = activation; try await io.checkMacAgentDrafts(review)
            _ = try await MacAgentExternalDrafts.capture(stores: [self.externalFiles] + self.relatedStores(paths: review.changedNotes.map(\.path)), root: self.root, paths: review.changedNotes.map(\.path))
            return review
        }
    }
    func undoReview(_ record: NativeAgentRecord, receiptID: UUID) async throws -> NativeAgentReview {
        let owner = owner, activation = workspaceID
        return try await admitted(flush: true) { io, _, _ in
            var review = try await io.macAgentUndoReview(record, owner: owner, receiptID: receiptID)
            review.workspaceID = activation; try await io.checkMacAgentDrafts(review)
            _ = try await MacAgentExternalDrafts.capture(stores: [self.externalFiles] + self.relatedStores(paths: review.changedNotes.map(\.path)), root: self.root, paths: review.changedNotes.map(\.path))
            return review
        }
    }
    func apply(_ review: NativeAgentReview) async throws -> NativeAgentRecord {
        _ = try current(); try Task.checkCancellation()
        guard review.workspaceID == workspaceID, review.root.resolvingSymlinksInPath().standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else {
            throw VaultFailure(message: "The vault changed. Review the AI changes again.")
        }
        let owner = owner, identity = identity
        // Hold new presentations while the guard inventory is captured, including
        // pending opens whose store actor work began before this approval.
        MacVaultFileAdmission.active += 1
        defer { MacVaultFileAdmission.active -= 1 }
        let guards = try await MacAgentExternalDrafts.capture(stores: [externalFiles] + relatedStores(paths: review.changedNotes.map(\.path)), root: root, paths: review.changedNotes.map(\.path))
        return try await admitted(flush: false, paths: review.changedNotes.map(\.path)) { io, peers, external in
            let (record, snapshot, warnings) = try await io.applyMacAgent(review, owner: owner, identity: identity, external: guards)
            // Reconciliation retains any writing that arrives after the admission
            // check; it must never replace a newer body with the saved snapshot.
            for peer in peers { await peer.adoptAgentReview(review, snapshot: snapshot) }
            if !warnings.isEmpty { await MainActor.run { for peer in peers { peer.issue = warnings.joined(separator: "\n") } } }
            for session in external { await session.refreshForAgent() }
            return record
        }
    }
    func delete(_ record: NativeAgentRecord) async throws -> String? {
        let owner = owner
        let childIDs = try MacAgentAnalysisState.continuationIDs(record, includingFinished: true)
        try await admitted(flush: true) { io, _, _ in
            try await MainActor.run {
                guard !MacWorkspace.windows.compactMap({ $0.value?.agentController }).contains(where: { $0.workspace !== self && $0.workspace.identity == self.identity && $0.running && $0.current?.id == record.id }) else { throw VaultFailure(message: "Stop this run in every window before deleting its journal.") }
            }
            try await io.deleteMacAgentJournal(record, owner: owner)
        }
        do { for id in [record.id] + childIDs { try continuations.remove(run: id) }; return nil }
        catch { return "The run journal was deleted, but its private provider continuation could not be removed: " + error.localizedDescription }
    }
    func reserveRequest(_ record: NativeAgentRecord, input: Int, output: Int) async throws -> NativeAgentRecord {
        let owner = owner; return try await journal { try await $0.agentReserveRequest(record, owner: owner, input: input, output: output) }
    }
    func elapsed(_ record: NativeAgentRecord, seconds: Double) async throws -> NativeAgentRecord {
        let owner = owner; return try await journal { try await $0.agentElapsed(record, owner: owner, seconds: seconds) }
    }
    func pause(_ record: NativeAgentRecord, reason: String) async throws -> NativeAgentRecord {
        let owner = owner; return try await journal { try await $0.agentPause(record, owner: owner, reason: reason) }
    }
    func resume(_ record: NativeAgentRecord, answer: String? = nil) async throws -> NativeAgentRecord {
        let owner = owner
        return try await admitted(flush: true) { io, _, _ in try await io.agentResume(record, owner: owner, answer: answer) }
    }
    func reject(_ record: NativeAgentRecord, proposalID: UUID) async throws -> NativeAgentRecord {
        let owner = owner; return try await journal { try await $0.agentReject(record, owner: owner, proposalID: proposalID) }
    }
}

extension VaultFiles {
    fileprivate func deleteMacAgentJournal(_ record: NativeAgentRecord, owner: String) throws {
        _ = try agentChecked(record, owner: owner, requiresActiveImport: false)
        let status = try deleteMacWebAgentImportIndex(record)
        try applyTransaction(status + [.init(path: NativeAgentJournal.path(record.id), before: record.bytes, after: nil)], historySource: "ai-run-delete")
    }
    func checkMacAgentDrafts(_ review: NativeAgentReview) throws {
        if let path = try MacNoteRecoveryStore.firstRetained(root: root, paths: review.changedNotes.map(\.path)) {
            throw VaultFailure(message: "A retained draft exists for \(path). Save or resolve it before applying AI changes.")
        }
    }
    /// The native engine owns proposal/receipt construction. This Mac commit
    /// boundary adds private-draft admission inside the coordinated transaction.
    fileprivate func applyMacAgent(_ review: NativeAgentReview, owner: String, identity: MacAgentFileIdentity, external: [MacAgentExternalDraftGuard]) throws -> (NativeAgentRecord, VaultSnapshot, [String]) {
        guard review.root.resolvingSymlinksInPath().standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else { throw VaultFailure(message: "The AI review belongs to a different vault.") }
        guard (try? MacAgentFileIdentity(root)) == identity else { throw VaultFailure(message: "The vault changed since this AI review. Reopen it and review again.") }
        _ = try agentChecked(review.record, owner: owner)
        let notes = try scan().notes
        let noteIdentity: (NoteDocument) -> String = { $0.path + "\u{0}" + NativeAgentNote.identity($0) }
        guard Set(notes.map(noteIdentity)) == Set(review.identities.map(noteIdentity)) else { throw VaultFailure(message: "Notes moved, appeared or changed identity after this review. Reopen the latest run before applying it.") }
        let root = root, paths = review.changedNotes.map(\.path)
        try Task.checkCancellation()
        try applyTransaction(review.changes, historySource: "ai", reading: external.map(\.file), validate: {
            guard (try? MacAgentFileIdentity(root)) == identity else { throw VaultFailure(message: "The vault changed since this AI review. Reopen it and review again.") }
            for guardFile in external { try guardFile.validate() }
            if let path = try MacNoteRecoveryStore.firstRetained(root: root, paths: paths) {
                throw VaultFailure(message: "A retained draft exists for \(path). Save or resolve it before applying AI changes.")
            }
        })
        var warnings: [String] = []
        for (path, date) in MacAgentOrganizationReconciliation.creationDates(review) {
            if let bytes = review.changes.first(where: { $0.path == path })?.after,
               let warning = retainMacMoveCreationDate(date, destination: path, expected: bytes) { warnings.append(path + ": " + warning) }
        }
        let record = try agentDecode(agentJournalData(NativeAgentJournal.path(review.record.id)), id: review.record.id)
        return (record, try scan(), warnings)
    }
}

struct MacAgentFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    init(_ root: URL) throws {
        // Identity checks need device/inode only. Foundation's full attribute
        // lookup also reads extended attributes, which can block on providers.
        let path = root.resolvingSymlinksInPath().path
        var value = stat()
        guard stat(path, &value) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: path]) }
        device = UInt64(truncatingIfNeeded: value.st_dev); inode = UInt64(value.st_ino)
    }
}
