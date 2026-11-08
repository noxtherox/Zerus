import Foundation

struct NativeExternalSearchRecord: Sendable {
    let entry: NativeExternalEntry
    let document: NoteDocument?
    let draft: Bool
    let issue: String?

    func referenceDocument() throws -> NativeSearchDocument {
        guard let document else { throw VaultFailure(message: issue ?? "This external file is unavailable. Locate it in Library → External notes.") }
        let excerpt = String(document.content.prefix(20_001))
        return .init(name: document.title + (draft ? " (draft)" : "") + (excerpt.count > 20_000 ? " (excerpt)" : ""), text: String(excerpt.prefix(20_000)))
    }

    static func read(_ entry: NativeExternalEntry, store: NativeExternalNotesStore) async -> Self {
        let draft: NativeExternalDraft?
        var issue: String?
        do { draft = try await store.draft(entry.id) }
        catch { draft = nil; issue = "The recovery draft could not be read. Open External notes to review it." }
        do {
            let snapshot = try await store.searchSnapshot(entry)
            let kept = draft?.hasUnsavedChanges == true
            if kept, draft?.baseline != snapshot.bytes { issue = "The original changed; search is showing your kept draft." }
            return .init(entry: entry, document: .init(path: snapshot.access.url.lastPathComponent, content: kept ? draft!.content : snapshot.content, modified: kept ? draft!.updated : snapshot.modified), draft: kept, issue: issue)
        } catch {
            if error is CancellationError { issue = "File access was interrupted. Refresh search to try again." }
            else if case NativeCoordinatedReadFailure.timedOut = error { issue = "This file provider is taking too long. Refresh search or check the file in Files." }
            else { issue = "The original is unavailable. Locate it in Library → External notes." }
            if let draft, draft.hasUnsavedChanges {
                return .init(entry: entry, document: .init(path: entry.name, content: draft.content, modified: draft.updated), draft: true, issue: issue)
            }
            return .init(entry: entry, document: nil, draft: false, issue: issue)
        }
    }
}
