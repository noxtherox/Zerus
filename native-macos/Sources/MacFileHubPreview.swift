import SwiftUI

/// Owns the security-scoped preview across status refreshes. An unchanged file
/// keeps the same lease/view identity, preserving its page and search state.
@MainActor final class MacFileHubPreview: ObservableObject {
    struct Source: Equatable {
        let workspaceID: UUID
        let path: String
        let reference: NativeFileHub?
    }
    @Published private(set) var lease: NativeFileLease?
    @Published private(set) var issue: String?
    @Published private(set) var refreshing = false
    @Published private(set) var source: Source?
    private var request: UUID?

    func refresh(_ note: NoteDocument, workspace: MacWorkspace, workspaceID: UUID, force: Bool = false) async {
        let next = Source(workspaceID: workspaceID, path: note.path, reference: note.fileHub), token = UUID()
        guard !Task.isCancelled else { return }
        guard workspace.workspaceID == workspaceID, note.fileHub != nil,
              workspace.notes.first(where: { $0.path == note.path })?.fileHub == note.fileHub else {
            // A late callback from a retired view cannot supersede a newer one.
            if source == nil || source == next {
                source = next; request = nil; lease = nil; refreshing = false
                issue = "The document connection or vault changed. Reopen its preview."
            }
            return
        }
        request = token
        if source != next { source = next; lease = nil; issue = nil }
        refreshing = true
        defer { if request == token { refreshing = false } }
        do {
            let resolved = try await workspace.resolveFileHub(note, workspaceID: workspaceID)
            try Task.checkCancellation()
            guard request == token, source == next else { return }
            guard workspace.workspaceID == workspaceID,
                  workspace.notes.first(where: { $0.path == note.path })?.fileHub == note.fileHub else {
                lease = nil; return
            }
            if force || lease?.canonicalPath != resolved.canonicalPath || lease?.size != resolved.size || lease?.modified != resolved.modified || lease?.locatedOnDevice != resolved.locatedOnDevice {
                lease = resolved
            }
            issue = nil
        } catch is CancellationError {
            if request == token, workspace.workspaceID != workspaceID { lease = nil }
        } catch {
            guard request == token, source == next else { return }
            lease = nil; issue = error.localizedDescription
        }
    }
    func cancel() { request = nil; refreshing = false; lease = nil; issue = nil }
}
