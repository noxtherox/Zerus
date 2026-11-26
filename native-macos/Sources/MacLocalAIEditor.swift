import AppKit

/// Synchronous, scoped request to the open note's editor (same pattern as
/// `MacTableChange`): read the selection, or replace the whole Markdown as one
/// undoable edit after the user approved the diff.
@MainActor final class MacLocalAIEditorRequest {
    enum Kind {
        case read
        /// Replaces the note text when it still equals `expected`.
        case replace(expected: String, replacement: String, actionName: String)
    }

    struct Snapshot {
        /// The editor's Markdown (the note body).
        let markdown: String
        /// The selected passage as Markdown, if any text is selected.
        let selection: String?
    }

    let scope: UUID
    let path: String
    let kind: Kind
    var result: Result<Snapshot, Error>?

    init(scope: UUID, path: String, kind: Kind) {
        self.scope = scope
        self.path = path
        self.kind = kind
    }

    /// Posts the request to the open editor and returns its answer.
    @discardableResult
    static func perform(scope: UUID, path: String, kind: Kind) throws -> Snapshot {
        let request = MacLocalAIEditorRequest(scope: scope, path: path, kind: kind)
        NotificationCenter.default.post(name: .macEditorAction, object: request)
        guard let result = request.result else {
            throw VaultFailure(message: "Open the note in the editor and try again.")
        }
        return try result.get()
    }
}
