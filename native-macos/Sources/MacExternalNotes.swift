import SwiftUI
import AppKit

@MainActor final class MacExternalLibrary: ObservableObject {
    let store: NativeExternalNotesStore
    let moveStore: NativeExternalMoveStore
    @Published private(set) var pendingMoves: [NativeExternalMoveRecord] = []
    @Published var moveIssue: String?
    @Published private(set) var entries: [NativeExternalEntry] = []
    @Published var selected: MacExternalSession?
    @Published var issue: String?
    @Published private(set) var busy = false
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/ExternalNotes")) {
        store = NativeExternalNotesStore(directory: directory)
        moveStore = NativeExternalMoveStore(directory: directory.appendingPathComponent("Moves"))
    }
    func restore() async {
        do { entries = try await store.entries(); issue = nil } catch { issue = error.localizedDescription }
        do { pendingMoves = try await moveStore.pending(); moveIssue = nil } catch { moveIssue = error.localizedDescription }
    }
    func open(_ url: URL, replacing entry: NativeExternalEntry? = nil) async {
        guard !busy, MacAgentWorkspace.fileOperations == 0, selected?.agentLocked != true else { return }; busy = true; defer { busy = false }
        do {
            let snapshot: NativeExternalSnapshot
            if let entry { snapshot = try await store.locate(entry.id, selected: url) } else { snapshot = try await store.open(selected: url) }
            try await present(snapshot); await restore()
        } catch { issue = error.localizedDescription }
    }
    func open(_ entry: NativeExternalEntry) async {
        guard !busy, MacAgentWorkspace.fileOperations == 0, selected?.agentLocked != true else { return }; busy = true; defer { busy = false }
        do { let snapshot = try await store.reopen(entry.id); try await present(snapshot); await restore() } catch { issue = error.localizedDescription }
    }
    private func present(_ snapshot: NativeExternalSnapshot) async throws {
        guard MacAgentWorkspace.fileOperations == 0, selected?.agentLocked != true else { throw VaultFailure(message: "Finish the AI file operation before opening another connection.") }
        if let selected, !(await selected.checkpoint()) { throw VaultFailure(message: "The current draft could not be kept. Keep that editor open before opening another file.") }
        let draft = try await store.draft(snapshot.entry.id)
        guard MacAgentWorkspace.fileOperations == 0, selected?.agentLocked != true else { throw VaultFailure(message: "Finish the AI file operation before opening another connection.") }
        selected?.deactivate()
        selected = MacExternalSession(snapshot: snapshot, draft: draft, store: store)
    }
    func close() async -> Bool {
        guard let selected else { return true }
        guard !selected.agentLocked else { issue = "Finish the AI file operation before closing this connection."; return false }
        guard await selected.checkpoint(), self.selected === selected, !selected.agentLocked else { return false }
        selected.deactivate(); self.selected = nil; await restore(); return true
    }
    func finishImportedMove(_ id: UUID) async throws {
        guard selected?.id != id || selected?.dirty != true else { throw VaultFailure(message: "Keep or reload the original draft before closing this connection.") }
        try await store.forget(id)
    }
    func forget(_ entry: NativeExternalEntry) async {
        do { try await store.forget(entry.id); await restore() } catch { issue = error.localizedDescription }
    }
}

/// A Mac editor session keeps its original comparison bytes until an explicit reload.
/// Local draft writes and source-file writes use the shared coordinated storage service.
@MainActor final class MacExternalSession: ObservableObject, Identifiable {
    let id: UUID
    let presentationID = UUID()
    let store: NativeExternalNotesStore
    @Published private(set) var document: NoteDocument
    @Published private(set) var agentLocked = false
    @Published private(set) var dirty: Bool
    @Published private(set) var saving = false
    @Published private(set) var failure: String?
    @Published private(set) var conflict = false
    @Published private(set) var draftKept = false
    @Published private(set) var project: NativeExternalProjectFiles?
    @Published private(set) var projectFailure: String?
    @Published private(set) var exporting = false
    @Published private(set) var transferring = false
    @Published private(set) var moved = false
    @Published private var verifiedExport: MacExternalDraftExport?
    var exportReady: Bool { verifiedExport?.bytes == snapshot.encoded(document.content) }
    private var projectRequest = UUID()
    private(set) var snapshot: NativeExternalSnapshot
    private var draft: NativeExternalDraft?
    private var recoveryFailure: String?
    private var draftJob: Task<Bool, Never>?
    private var saveJob: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    @Published private(set) var active = true
    var safeToClose: Bool { !dirty || draftKept && draft?.content == document.content }
    init(snapshot: NativeExternalSnapshot, draft: NativeExternalDraft?, store: NativeExternalNotesStore) {
        self.id = snapshot.entry.id; self.snapshot = snapshot; self.store = store; self.draft = draft
        let text = draft?.hasUnsavedChanges == true ? draft!.content : snapshot.content
        document = .init(path: snapshot.entry.name, content: text, modified: snapshot.modified)
        dirty = snapshot.encoded(text) != snapshot.bytes; draftKept = draft?.content == text
        if dirty, let draft, draft.baseline != snapshot.bytes {
            conflict = true; failure = "The original changed while this draft was closed. Your recovered draft is kept. Export it before reloading the original."
        }
    }
    func restoreProject() async {
        let token = UUID(); projectRequest = token
        do {
            let access = try await store.project(snapshot)
            guard active, projectRequest == token else { return }
            project = access; projectFailure = nil
        } catch { if active, projectRequest == token { projectFailure = error.localizedDescription } }
    }
    func chooseProject(_ url: URL) async {
        let token = UUID(); projectRequest = token
        do {
            let access = try await store.mapProject(snapshot, selected: url)
            guard active, projectRequest == token else { return }
            project = access; projectFailure = nil
        } catch { if active, projectRequest == token { projectFailure = error.localizedDescription } }
    }
    func changeBody(_ body: String) { changeContent(document.replacingBody(body)) }
    func changeContent(_ content: String) {
        guard active, !transferring else { return }
        guard snapshot.encoded(content).count <= 10 * 1024 * 1024, !content.utf8.contains(0) else { failure = "Use UTF-8 Markdown below 10 MB. The previous file and recovery draft are unchanged."; return }
        if Data(document.content.utf8) != Data(content.utf8) {
            verifiedExport = nil
            if agentLocked {
                conflict = true
                failure = "Writing arrived during an AI file operation. Your draft is kept. Export it or reload the original before saving."
            }
        }
        document.content = content; dirty = snapshot.encoded(content) != snapshot.bytes; draftKept = false
        _ = keepDraft(content)
        debounce?.cancel(); debounce = Task { [weak self] in do { try await Task.sleep(for: .milliseconds(650)); await self?.save() } catch {} }
    }
    private func keepDraft(_ content: String) -> Task<Bool, Never> {
        let previous = draftJob
        let job = Task { [self] () -> Bool in
            if let previous, !(await previous.value) { return false }
            let baseline = conflict ? draft?.baseline ?? snapshot.bytes : snapshot.bytes
            let next = NativeExternalDraft(version: 1, noteID: id, name: document.path, baseline: baseline, content: content, updated: Date())
            do {
                try await store.keepDraft(next, replacing: draft); draft = next
                draftKept = document.content == content; recoveryFailure = nil; return true
            } catch { recoveryFailure = "Recovery draft could not be saved: " + error.localizedDescription; failure = recoveryFailure; draftKept = false; return false }
        }
        draftJob = job; return job
    }
    func holdForAgent(_ held: Bool) {
        agentLocked = held
        if !held, active, dirty, !conflict {
            debounce?.cancel(); debounce = Task { [weak self] in do { try await Task.sleep(for: .milliseconds(650)); await self?.save() } catch {} }
        }
    }
    func saveForAgent() async { guard agentLocked else { return }; await saveAccepted() }
    func save() async { guard !agentLocked else { return }; await saveAccepted() }
    private func saveAccepted() async {
        guard active, !transferring else { return }
        if let saveJob { await saveJob.value; return }
        let job = Task { [self] in await savePending() }
        saveJob = job; await job.value; saveJob = nil
        if active, dirty, failure == nil { await save() }
    }
    private func savePending() async {
        guard active, dirty, !conflict else { return }
        let text = document.content
        guard await keepDraft(text).value, active, !conflict else { return }
        saving = true; defer { saving = false }
        do {
            let current = try await store.save(snapshot, content: text)
            guard active else { return }
            snapshot = current; document.modified = current.modified; dirty = snapshot.encoded(document.content) != current.bytes; failure = nil
            _ = await keepDraft(document.content).value
        } catch {
            failure = error.localizedDescription
            if let current = try? await store.refresh(snapshot), current.bytes != snapshot.bytes || current.identity.value != snapshot.identity.value { conflict = true }
        }
    }
    func retry() async {
        if let draftJob { _ = await draftJob.value }; draftJob = nil
        guard active, !transferring else { return }
        failure = nil
        guard await keepDraft(document.content).value else { return }
        if conflict { failure = "The original changed. Export this draft or explicitly reload the current file before saving." }
        else { await save(); if !dirty { await refresh() } }
    }
    func refreshForAgent() async { guard agentLocked else { return }; await refreshAccepted() }
    func refresh() async { guard !agentLocked else { return }; await refreshAccepted() }
    private func refreshAccepted() async {
        guard active, !saving, !transferring else { return }
        do {
            let current = try await store.refresh(snapshot)
            guard active, !saving, !transferring else { return }
            if dirty {
                if current.bytes != snapshot.bytes || current.identity.value != snapshot.identity.value { conflict = true; failure = "The original changed or was replaced in another editor. Your draft is kept. Export it before reloading."; debounce?.cancel() }
            } else { snapshot = current; document = .init(path: current.entry.name, content: current.content, modified: current.modified); failure = nil; conflict = false }
        } catch { failure = error.localizedDescription }
    }
    /// Reads the current file before clearing any draft; called after the discard review.
    func reloadDiscardingDraft() async throws {
        guard active, !transferring else { throw VaultFailure(message: "Finish the move before reloading this file.") }
        debounce?.cancel(); if let saveJob { await saveJob.value }; if let draftJob { _ = await draftJob.value }
        let current = try await store.refresh(snapshot)
        guard active, !transferring else { throw CancellationError() }
        // Persist the clean replacement first. A draft-write failure must retain the visible draft.
        let clean = NativeExternalDraft(version: 1, noteID: id, name: current.entry.name, baseline: current.bytes, content: current.content, updated: Date())
        try await store.keepDraft(clean, replacing: draft)
        draft = clean; draftJob = nil; snapshot = current; document = .init(path: current.entry.name, content: current.content, modified: current.modified)
        dirty = false; conflict = false; failure = nil; draftKept = true
    }
    func exportDraft(to url: URL) async throws {
        guard active, !exporting else { throw VaultFailure(message: "Finish the current draft export before starting another one.") }
        exporting = true; defer { exporting = false }
        let bytes = snapshot.encoded(document.content)
        let export = try await MacExternalDraftExport.create(bytes: bytes, to: url, original: snapshot.access.canonical, privateDirectory: store.directory)
        guard active, snapshot.encoded(document.content) == bytes else { throw VaultFailure(message: "The draft changed while its copy was being exported. Export the current draft before closing.") }
        verifiedExport = export
        if let recoveryFailure { failure = recoveryFailure }
    }
    private func verifyExportBeforeClosing() async -> Bool {
        guard let export = verifiedExport, export.bytes == snapshot.encoded(document.content) else { return false }
        let matches = await export.matches()
        guard active, verifiedExport === export, export.bytes == snapshot.encoded(document.content) else { return false }
        guard matches else {
            verifiedExport = nil; failure = "The exported copy changed or is unavailable. Export the current draft again before closing."
            return false
        }
        return true
    }
    func checkpoint() async -> Bool {
        if moved { return true }
        guard !transferring else { return false }
        debounce?.cancel()
        if !dirty { if let draftJob { _ = await draftJob.value }; return safeToClose }
        if await keepDraft(document.content).value, safeToClose { return true }
        return await verifyExportBeforeClosing()
    }
    func beginTransfer(_ reviewed: NativeExternalSnapshot) async throws {
        debounce?.cancel()
        if let saveJob { await saveJob.value }
        if let draftJob, !(await draftJob.value) { throw VaultFailure(message: "The original recovery draft could not be kept. Export or resolve it before moving.") }
        guard active, !transferring, !dirty, !saving, !conflict, !exporting,
              reviewed.bytes == snapshot.bytes, reviewed.identity.value == snapshot.identity.value,
              reviewed.access.canonical == snapshot.access.canonical,
              snapshot.encoded(document.content) == reviewed.bytes else { throw VaultFailure(message: "The original or an open draft changed. Review the move again.") }
        transferring = true
    }
    func endTransfer() { transferring = false }
    func markMoved() { moved = true; deactivate() }
    func deactivate() { debounce?.cancel(); active = false }
}
