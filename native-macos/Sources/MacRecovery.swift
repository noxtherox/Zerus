import SwiftUI

/// Saved-version loading updates the revisions section, without invalidating
/// the folders, collection, editor and toolbar of the entire window.
@MainActor final class MacInspectorRecoveryState: ObservableObject {
    @Published var revisions: NativeRevisionSnapshot?
    @Published var history: NativeHistorySnapshot?
    @Published var revisionIssue: String?
    @Published var historyIssue: String?
}

@MainActor struct MacInspectorRecoveryContent<Content: View>: View {
    @ObservedObject var state: MacInspectorRecoveryState
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}

struct MacRecoveryRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let path: String
    var history = false
    var selectedID: String?
}
struct MacRecoverySnapshot {
    let workspaceID: UUID
    let root: URL
    let note: NoteDocument
    let revisions: NativeRevisionSnapshot?
    let history: NativeHistorySnapshot?
    let revisionIssue: String?
    let historyIssue: String?
}
enum MacRecoveryPlan {
    case revision(NativeRevisionPlan, NativeRevisionAction)
    case history(NativeHistoryPlan)
}
struct MacRecoveryReview: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let plan: MacRecoveryPlan
    var note: NoteDocument { switch plan { case .revision(let p, _): p.snapshot.note; case .history(let p): p.snapshot.note } }
    var content: String { switch plan { case .revision(let p, _): p.content; case .history(let p): p.content ?? p.snapshot.note.content } }
    var changes: [VaultFileChange] { switch plan { case .revision(let p, _): p.changes; case .history(let p): p.changes } }
    var label: String { switch plan {
        case .revision(_, .create): "Create revision"
        case .revision(_, .promote): "Make current"
        case .revision(_, .trash): "Move revision to Trash"
        case .revision(_, .restore): "Restore revision"
        case .history: "Restore version"
    } }
    var explanation: String { switch plan {
        case .revision(_, .create): "Preserve the current text and files, then continue in a new revision."
        case .revision(_, .promote): "Create a new current revision from the selected text and saved files. Today’s title and other properties stay in place."
        case .revision(_, .trash): "Keep this revision in Trash. If it is current, the most recent remaining revision becomes current."
        case .revision(_, .restore): "Return this revision to the list. The current revision stays selected."
        case .history: "Restore this saved text and its image snapshots. Current Zerus identity and file metadata stay in place; other historical properties can change. The current text remains in automatic history when history is enabled."
    } }
    var resources: [VaultFileChange] { changes.filter { $0.after != nil && ($0.path.contains("/files/") || $0.path.hasPrefix("assets/restored-")) } }
    var images: [String: NSImage] { Dictionary(uniqueKeysWithValues: resources.compactMap { item in item.after.flatMap(NSImage.init(data:)).map { (item.path, $0) } }) }
}

extension VaultFiles {
    func macRecoverySnapshot(notePath: String, workspaceID: UUID) throws -> MacRecoverySnapshot {
        try Task.checkCancellation()
        let before = try read(notePath)
        guard let content = NoteDocument.decodeUTF8(before) else { throw VaultFailure(message: "The note is not UTF-8 Markdown.") }
        var revisions: NativeRevisionSnapshot?, history: NativeHistorySnapshot?, revisionIssue: String?, historyIssue: String?
        do { revisions = try revisionSnapshot(notePath: notePath) } catch is CancellationError { throw CancellationError() } catch { revisionIssue = error.localizedDescription }
        do { history = try historySnapshot(notePath: notePath) } catch is CancellationError { throw CancellationError() } catch { historyIssue = error.localizedDescription }
        guard try read(notePath) == before, revisions.map({ $0.note.content == content }) ?? true, history.map({ $0.note.content == content }) ?? true else { throw VaultFailure(message: "The note changed while loading saved versions. Refresh recovery.") }
        let modified = (try? url(for: notePath).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return .init(workspaceID: workspaceID, root: root, note: NoteDocument(path: notePath, content: content, modified: modified), revisions: revisions, history: history, revisionIssue: revisionIssue, historyIssue: historyIssue)
    }
}

extension MacWorkspace {
    private func checkRecovery(_ expected: UUID, path: String) throws {
        guard expected == workspaceID, !isDirty, !recoverySaving, !imageSaving, !noteMovesSaving,
              notes.contains(where: { $0.path == path && !$0.trashed }) else { throw VaultFailure(message: "The note or vault changed, or another file change is in progress. Reopen recovery.") }
        if let draft = noteMoveDraftLocations([path])[path], FileManager.default.fileExists(atPath: draft.path) { throw VaultFailure(message: "Resolve or export this note’s retained recovery draft before restoring a version.") }
    }
    func recoverySnapshot(_ request: MacRecoveryRequest) async throws -> MacRecoverySnapshot {
        guard request.workspaceID == workspaceID, await save(), let io else { throw VaultFailure(message: "Save the note or reopen recovery in its original vault.") }
        try checkRecovery(request.workspaceID, path: request.path)
        let snapshot = try await io.macRecoverySnapshot(notePath: request.path, workspaceID: request.workspaceID)
        try checkRecovery(request.workspaceID, path: request.path)
        return snapshot
    }

    func prepareRecovery(_ snapshot: MacRecoverySnapshot, action: NativeRevisionAction) async throws -> MacRecoveryReview {
        guard let revisions = snapshot.revisions else { throw VaultFailure(message: snapshot.revisionIssue ?? "Revisions are unavailable. Refresh recovery.") }
        let path = revisions.note.path
        try checkRecovery(snapshot.workspaceID, path: path)
        guard let io else { throw VaultFailure(message: "Open a vault first.") }
        let plan = try await io.prepareRevision(revisions, action: action)
        try checkRecovery(snapshot.workspaceID, path: path)
        return .init(workspaceID: snapshot.workspaceID, plan: .revision(plan, action))
    }
    func prepareHistoryRecovery(_ snapshot: MacRecoverySnapshot, id: String) async throws -> MacRecoveryReview {
        guard let history = snapshot.history else { throw VaultFailure(message: snapshot.historyIssue ?? "Automatic history is unavailable. Refresh recovery.") }
        try checkRecovery(snapshot.workspaceID, path: history.note.path)
        guard let io else { throw VaultFailure(message: "Open a vault first.") }
        let plan = try await io.prepareHistory(history, action: .restore(id))
        try checkRecovery(snapshot.workspaceID, path: history.note.path)
        return .init(workspaceID: snapshot.workspaceID, plan: .history(plan))
    }
    func commitRecovery(_ review: MacRecoveryReview) async throws {
        try checkRecovery(review.workspaceID, path: review.note.path)
        guard let io else { throw VaultFailure(message: "Open a vault first.") }
        recoverySaving = true; defer { recoverySaving = false }
        let result: VaultSnapshot
        switch review.plan { case .revision(let plan, _): result = try await io.applyRevision(plan); case .history(let plan): result = try await io.applyHistory(plan) }
        guard review.workspaceID == workspaceID else { throw CancellationError() }
        apply(result)
        guard !isDirty else { throw VaultFailure(message: "The recovery was saved. Your newer note draft is retained; save or export it before reloading.") }
        await reloadCurrent(); await loadInspector()
    }
    func recoveryResource(_ item: VaultFileChange, review: MacRecoveryReview) throws -> NativeFileLease {
        guard review.workspaceID == workspaceID, let approved = review.resources.first(where: { $0.path == item.path }), let bytes = approved.after else { throw VaultFailure(message: "Reopen the saved-file preview in its original vault.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-recovery-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent((item.path as NSString).lastPathComponent)
            try bytes.write(to: file)
            return try NativeFileLease(scope: directory, url: file, temporaryDirectory: directory)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
