import SwiftUI
import Combine

@MainActor
final class NativeExternalNoteSession: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var presentationID = UUID()
    @Published private(set) var resourceRevision = 0
    @Published private(set) var document: NoteDocument
    @Published private(set) var dirty: Bool
    @Published private(set) var saving = false
    @Published private(set) var failure: String?
    @Published private(set) var conflict = false
    @Published private(set) var transferring = false
    @Published private(set) var moved = false
    private(set) var snapshot: NativeExternalSnapshot
    private let store: NativeExternalNotesStore
    @Published private var draft: NativeExternalDraft?
    private var draftJob: Task<Bool, Never>?
    private var debounce: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    @Published private(set) var active = true
    private var editors: [UUID: WeakExternalEditor] = [:]
    var canCloseSafely: Bool { !dirty || draft?.content == document.content }
    init(snapshot: NativeExternalSnapshot, draft: NativeExternalDraft?, store: NativeExternalNotesStore) {
        id = snapshot.entry.id; self.snapshot = snapshot; self.store = store; self.draft = draft
        let text = draft?.hasUnsavedChanges == true ? draft!.content : snapshot.content
        document = .init(path: snapshot.entry.name, content: text, modified: snapshot.modified)
        dirty = text != snapshot.content
        if let draft, dirty, draft.baseline != snapshot.bytes {
            conflict = true; failure = "The file changed while your draft was closed. Your draft is kept; share or copy it before reloading the current file."
        }
    }
    func updateBody(_ body: String) { updateContent(document.replacingBody(body)) }
    func updateContent(_ content: String) {
        guard active, !transferring else { return }
        guard snapshot.encoded(content).count <= 10 * 1024 * 1024, !content.utf8.contains(0) else { failure = "Keep this file below 10 MB and use valid Markdown text. The previous file and recovery draft are unchanged."; return }
        document.content = content; dirty = snapshot.encoded(content) != snapshot.bytes
        _ = keepDraft(content)
        debounce?.cancel()
        debounce = Task { [weak self] in do { try await Task.sleep(for: .milliseconds(600)); await self?.save() } catch {} }
    }
    @discardableResult
    private func keepDraft(_ content: String) -> Task<Bool, Never> {
        let previous = draftJob
        let job = Task { [weak self] in
            if let previous, !(await previous.value) { return false }
            guard let self, active else { return false }
            // A conflicted recovered draft retains the original comparison
            // bytes; observing a new file never silently accepts its contents.
            let baseline = conflict ? (draft?.baseline ?? snapshot.bytes) : snapshot.bytes
            let next = NativeExternalDraft(version: 1, noteID: id, name: document.path, baseline: baseline, content: content, updated: Date())
            do { try await store.keepDraft(next, replacing: draft); draft = next; return true }
            catch { failure = "Could not keep the recovery draft: " + error.localizedDescription; return false }
        }
        draftJob = job; return job
    }
    func save() async {
        if let operation { await operation.value; return }
        let job = Task<Void, Never> { [weak self] in await self?.savePending() }
        operation = job; await job.value; operation = nil
        if dirty && failure == nil { await save() }
    }
    private func savePending() async {
        guard active, !transferring, dirty, !conflict else { return }
        if let draftJob, !(await draftJob.value) { return }
        guard active, !transferring, dirty, !conflict else { return }
        saving = true; defer { saving = false }
        let text = document.content
        do {
            let result = try await store.save(snapshot, content: text)
            guard active else { return }
            snapshot = result; document.modified = result.modified; dirty = document.content != result.content; failure = nil
            _ = await keepDraft(document.content).value
        } catch {
            failure = error.localizedDescription
            if let current = try? await store.refresh(snapshot), current.bytes != snapshot.bytes || current.identity.value != snapshot.identity.value { conflict = true }
        }
    }
    func retry() async {
        guard active, !conflict else { return }
        if let draftJob { _ = await draftJob.value }
        if !dirty { await refresh(); return }
        self.draftJob = nil; failure = nil
        guard await keepDraft(document.content).value else { return }
        await save()
    }
    func adopt(_ current: NativeExternalSnapshot) {
        guard active else { return }
        let previous = snapshot
        if previous.access.canonical != current.access.canonical || previous.entry.name != current.entry.name { presentationID = UUID() }
        if dirty {
            snapshot = .init(entry: current.entry, access: current.access, bytes: previous.bytes, modified: current.modified, identity: previous.identity)
            if current.bytes != previous.bytes || current.identity.value != previous.identity.value {
                conflict = true; debounce?.cancel()
                failure = "This file changed or was replaced in another editor. Your unsaved draft is kept on this device. Share or copy it before reloading."
            }
        } else {
            snapshot = current; document = .init(path: current.entry.name, content: current.content, modified: current.modified)
            failure = nil; conflict = false
        }
    }
    func refresh() async {
        guard active, !saving, !transferring else { return }
        do {
            let current = try await store.refresh(snapshot)
            guard active else { return }
            adopt(current); resourceRevision += 1
        } catch { failure = error.localizedDescription }
    }
    /// Called only after the UI's discard-draft confirmation. Reads first;
    /// an unavailable file must not discard the user's only readable draft.
    func reloadDiscardingDraft() async throws {
        debounce?.cancel(); if let operation { await operation.value }
        if let draftJob { _ = await draftJob.value }
        let current = try await store.refresh(snapshot)
        guard active else { throw CancellationError() }
        snapshot = current; document = .init(path: current.entry.name, content: current.content, modified: current.modified)
        dirty = false; conflict = false; failure = nil; self.draftJob = nil
        guard await keepDraft(current.content).value else { throw VaultFailure(message: failure ?? "The recovery draft could not be updated.") }
    }
    func flushDraft() async {
        if let draftJob { _ = await draftJob.value }
        if active, !dirty, !conflict, draft?.hasUnsavedChanges == true { _ = await keepDraft(document.content).value }
    }
    private final class WeakExternalEditor {
        weak var actions: NativeEditorActions?
        init(_ actions: NativeEditorActions) { self.actions = actions }
    }
    func registerEditor(_ id: UUID, actions: NativeEditorActions) { editors[id] = WeakExternalEditor(actions) }
    func unregisterEditor(_ id: UUID) { editors.removeValue(forKey: id) }
    func finishEditors() {
        editors = editors.filter { $0.value.actions != nil }
        for editor in editors.values {
            guard let actions = editor.actions else { continue }
            if actions.coordinator?.clipboardCopyOnly == false { actions.coordinator?.cancelClipboard() }
            actions.finishEditing()
        }
    }
    func beginTransfer(_ reviewed: NativeExternalSnapshot) throws {
        guard active, !transferring, !dirty, !saving, !conflict,
              reviewed.entry.id == id, reviewed.bytes == snapshot.bytes,
              reviewed.identity.value == snapshot.identity.value,
              reviewed.access.canonical == snapshot.access.canonical, document.content == reviewed.content else {
            throw VaultFailure(message: "This file or its draft changed after the review. Save it and review the transfer again.")
        }
        debounce?.cancel(); transferring = true
    }
    func endTransfer() { transferring = false }
    func markMoved() { moved = true; deactivate() }
    func deactivate() { active = false; debounce?.cancel() }
}

@MainActor
final class NativeExternalNotesModel: ObservableObject {
    @Published private(set) var entries: [NativeExternalEntry] = []
    @Published private(set) var issue: String?
    private let store: NativeExternalNotesStore
    let moveStore: NativeExternalMoveStore
    @Published private(set) var pendingMoves: [NativeExternalMoveRecord] = []
    private var sessions: [UUID: NativeExternalNoteSession] = [:]
    private var refreshTask: Task<Void, Never>?
    @Published private(set) var searchRevision = UUID()
    @Published private(set) var searching = false
    private var searchCache: [UUID: NativeExternalSearchRecord] = [:]
    private var searchObservedDocuments: [UUID: NoteDocument] = [:]
    private var searchJob: Task<Void, Never>?
    private var searchEpoch = UUID()
    private var sessionObservers: [UUID: AnyCancellable] = [:]
    var searchRecords: [NativeExternalSearchRecord] {
        entries.map { entry in
            let session = sessions[entry.id]
            if session?.dirty != true, session?.conflict != true, session?.transferring != true,
               let cached = searchCache[entry.id], cached.entry == entry, searchObservedDocuments[entry.id] == session?.document { return cached }
            if let session, session.active { return .init(entry: entry, document: session.document, draft: session.dirty, issue: session.failure) }
            return .init(entry: entry, document: nil, draft: false, issue: nil)
        }
    }
    func searchRecord(_ id: UUID) async throws -> NativeExternalSearchRecord {
        guard let entry = entries.first(where: { $0.id == id }) else { throw VaultFailure(message: "This external connection changed. Refresh search or open it in Files.") }
        if let session = sessions[id], session.active, session.dirty || session.conflict {
            return .init(entry: entry, document: session.document, draft: session.dirty, issue: session.failure)
        }
        let record = await NativeExternalSearchRecord.read(entry, store: store)
        try Task.checkCancellation()
        guard entries.contains(entry) else { throw CancellationError() }
        return record
    }
    func refreshSearchIndex() async {
        searchJob?.cancel(); let epoch = UUID(); searchEpoch = epoch
        await restore()
        guard !Task.isCancelled, epoch == searchEpoch else {
            if epoch == searchEpoch { searching = false }
            return
        }
        let entries = entries, store = store
        let observed = sessions.mapValues(\.document)
        searching = !entries.isEmpty
        let job = Task { [weak self] in
            await withTaskGroup(of: NativeExternalSearchRecord.self) { group in
                var next = entries.makeIterator()
                for _ in 0..<4 { if let entry = next.next() { group.addTask { await NativeExternalSearchRecord.read(entry, store: store) } } }
                while let record = await group.next() {
                    guard !Task.isCancelled, let self, self.searchEpoch == epoch else { group.cancelAll(); return }
                    if self.entries.contains(record.entry) {
                        self.searchCache[record.entry.id] = record
                        self.searchObservedDocuments[record.entry.id] = observed[record.entry.id]
                        self.searchRevision = UUID()
                    }
                    if let entry = next.next() { group.addTask { await NativeExternalSearchRecord.read(entry, store: store) } }
                }
            }
            guard let self, self.searchEpoch == epoch else { return }
            self.searching = false
        }
        searchJob = job
        await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
    }
    init(directory: URL = NativeExternalNotesStore.defaultDirectory) {
        store = NativeExternalNotesStore(directory: directory)
        moveStore = NativeExternalMoveStore(directory: directory.appendingPathComponent("Moves"))
    }
    func restore() async {
        let previous = entries
        do { entries = try await store.entries(); pendingMoves = try await moveStore.pending(); issue = nil } catch { issue = error.localizedDescription }
        if previous != entries {
            let ids = Set(entries.map(\.id)); searchCache = searchCache.filter { ids.contains($0.key) }; searchObservedDocuments = searchObservedDocuments.filter { ids.contains($0.key) }
            searchRevision = UUID()
        }
    }
    func open(_ url: URL) async throws -> NativeExternalNoteSession {
        let snapshot = try await store.open(selected: url)
        let result = try await session(snapshot); await restore(); return result
    }
    func open(_ entry: NativeExternalEntry) async throws -> NativeExternalNoteSession {
        let result = try await session(store.reopen(entry.id)); await restore(); return result
    }
    private func session(_ snapshot: NativeExternalSnapshot) async throws -> NativeExternalNoteSession {
        if let existing = sessions[snapshot.entry.id] {
            guard !existing.transferring else { throw VaultFailure(message: "This file is transferring. Wait for its current review to finish.") }
            await existing.save()
            existing.adopt(try await store.refresh(snapshot)); return existing
        }
        let result = NativeExternalNoteSession(snapshot: snapshot, draft: try await store.draft(snapshot.entry.id), store: store)
        sessions[snapshot.entry.id] = result
        sessionObservers[result.id] = result.objectWillChange.debounce(for: .milliseconds(200), scheduler: RunLoop.main).sink { [weak self] in self?.searchRevision = UUID() }
        searchRevision = UUID()
        return result
    }
    func locate(_ entry: NativeExternalEntry, url: URL) async throws -> NativeExternalNoteSession {
        guard sessions[entry.id]?.transferring != true else { throw VaultFailure(message: "Wait for this file’s transfer to finish before reconnecting it.") }
        let result = try await session(store.locate(entry.id, selected: url)); await restore(); return result
    }
    func project(_ snapshot: NativeExternalSnapshot) async throws -> NativeExternalProjectFiles? { try await store.project(snapshot) }
    func mapProject(_ snapshot: NativeExternalSnapshot, folder: URL) async throws -> NativeExternalProjectFiles { try await store.mapProject(snapshot, selected: folder) }
    func recoveryDraft(_ entry: NativeExternalEntry) async throws -> NativeExternalDraft? { try await store.draft(entry.id) }
    func forget(_ entry: NativeExternalEntry) async throws {
        if let session = sessions[entry.id] {
            guard !session.transferring else { throw VaultFailure(message: "Wait for this file’s transfer to finish before stopping its connection.") }
            session.finishEditors()
            await session.save(); await session.flushDraft()
            guard !session.dirty, session.failure == nil else { throw VaultFailure(message: "Keep or reload this file’s draft before removing it from the list.") }
        }
        try await store.forget(entry.id); sessions.removeValue(forKey: entry.id)?.deactivate(); sessionObservers.removeValue(forKey: entry.id); await restore()
    }
    func finishImportedMove(_ id: UUID, sourceRemoved: Bool = true) async throws {
        sessions[id]?.finishEditors()
        guard sessions[id]?.dirty != true else { throw VaultFailure(message: "An unsaved original draft must be kept before finishing this move.") }
        try await store.forget(id)
        if let session = sessions.removeValue(forKey: id) {
            if sourceRemoved { session.markMoved() } else { session.deactivate() }
        }
        sessionObservers.removeValue(forKey: id)
        await restore()
    }
    func flush() async { for session in sessions.values { await session.save(); await session.flushDraft() } }
    func refresh() async { await restore(); for session in sessions.values { await session.refresh() } }
    func startRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
            }
        }
    }
    func stopRefresh() { refreshTask?.cancel(); refreshTask = nil }
}
