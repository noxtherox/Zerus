import Foundation

struct MacSearchChatRequest: Sendable {
    let workspaceID: UUID
    let prompt: String
    let notes: Set<String>
    var references: [MacChatNoteReference] = []
    let images: [MacChatImage]
    let documents: [MacChatDocument]
}

extension MacWorkspace {
    /// Resolve the selected identity again, rather than sharing stale index text.
    /// This only prepares local context; Send remains a separate user action.
    func searchChatRequest(query: String, item: NativeSearchItem?, workspaceID origin: UUID) async throws -> MacSearchChatRequest {
        guard origin == workspaceID, let io else { throw VaultFailure(message: "The vault changed. Refresh search.") }
        let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.utf8.count <= 500_000 else { throw VaultFailure(message: "Enter a search question below 500 KB.") }
        var references: [MacChatNoteReference] = []
        var notes = Set<String>(), images: [MacChatImage] = [], documents: [MacChatDocument] = []
        if let item {
            switch item.target {
            case .note(let path, let stable):
                let fresh = try await io.scan()
                guard origin == workspaceID else { throw CancellationError() }
                let matches = fresh.notes.filter { !$0.trashed && (stable == nil ? $0.path == path : $0.stableID == stable) }
                guard matches.count == 1, let note = matches.first else { throw VaultFailure(message: "This result changed. Refresh search before choosing its context.") }
                notes = [note.path]; references = try MacChatNoteReference.capture(notes, notes: fresh.notes)
            case .external(let id):
                documents = [try await MacSearchContext.external(id: id, store: external.store, live: external.selected)]
            case .task(let id):
                _ = try await reloadTask(id: id, workspaceID: origin)
                let sources = searchSources(), items = try NativeSearch.items(sources, supplement: .init(files: [], conversations: [], problems: []))
                guard let current = items.first(where: { $0.id == item.id && $0.collection == .tasks }) else { throw VaultFailure(message: "This task changed. Refresh search.") }
                documents = [.init(id: UUID().uuidString.lowercased(), name: current.title + " (task)", text: current.text)]
            case .conversation(let conversation):
                guard case .shared(let id) = conversation.origin else { throw VaultFailure(message: "This conversation cannot be read in the native preview.") }
                let snapshot = try await io.conversationSnapshot(id)
                guard snapshot.conversation.deletedAt == nil else { throw VaultFailure(message: "This conversation moved to Trash. Restore it before using it as context.") }
                documents = [.init(id: UUID().uuidString.lowercased(), name: snapshot.conversation.title + " (conversation text)", text: snapshot.conversation.messages.map { $0.role + ": " + $0.text }.joined(separator: "\n\n"))]
            case .file(let path):
                let lease = try await searchFile(path, workspaceID: origin)
                let prepared = try await MacChatAttachmentInput.prepare([.file(lease.url)], imageCount: 0, documentCount: 0, documentBytes: 0)
                withExtendedLifetime(lease) {}
                images = prepared.images; documents = prepared.documents
            }
        }
        try Task.checkCancellation()
        guard origin == workspaceID else { throw CancellationError() }
        _ = try MacChatDocument.decode(documents.map(\.object))
        return .init(workspaceID: origin, prompt: prompt, notes: notes, references: references, images: images, documents: documents)
    }
}

@MainActor enum MacSearchContext {
    static func external(id: UUID, store: NativeExternalNotesStore, live: MacExternalSession?) async throws -> MacChatDocument {
        let entries = try await store.entries()
        guard let entry = entries.first(where: { $0.id == id }) else { throw VaultFailure(message: "The external connection changed. Refresh search.") }
        let record = await NativeExternalSearchRecord.read(entry, store: store)
        try Task.checkCancellation()
        let session = live.flatMap { $0.id == id ? $0 : nil }
        guard let document = session?.document ?? record.document else { throw VaultFailure(message: record.issue ?? "This external document is unavailable.") }
        return .init(id: UUID().uuidString.lowercased(), name: document.title + (session?.dirty == true || record.draft ? " (draft)" : ""), text: document.content)
    }
}
