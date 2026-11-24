import SwiftUI

/// Parsing stays on one worker, rather than competing with input or starting
/// one parser per visible card. The shared full-text preview cache and search
/// semantics remain unchanged; only collection display gets a short excerpt.
private actor MacCollectionExcerptLoader {
    static let shared = MacCollectionExcerptLoader()
    func text(_ note: NoteDocument) throws -> String {
        try Task.checkCancellation()
        let full = note.snippet
        try Task.checkCancellation()
        let end = full.index(full.startIndex, offsetBy: 512, limitedBy: full.endIndex) ?? full.endIndex
        return String(full[..<end]) + (end < full.endIndex ? "…" : "")
    }
}

struct MacCollectionExcerpt: View {
    let note: NoteDocument
    let workspaceID: UUID
    let lines: Int
    private struct Owner: Equatable { let workspace: UUID; let path: String }
    private struct Request: Equatable {
        let owner: Owner
        let content: String
        static func == (lhs: Self, rhs: Self) -> Bool {
            guard lhs.owner == rhs.owner else { return false }
            // String value copies share immutable UTF-8 storage. Avoid scanning
            // the whole note again when SwiftUI compares that same snapshot.
            if lhs.content.utf8.withContiguousStorageIfAvailable({ left in
                rhs.content.utf8.withContiguousStorageIfAvailable { right in
                    left.count == right.count && left.baseAddress == right.baseAddress
                } ?? false
            }) == true { return true }
            return lhs.content.utf8.elementsEqual(rhs.content.utf8)
        }
    }
    private struct Loaded { let request: Request; let text: String }
    @State private var loaded: Loaded?
    private var request: Request { Request(owner: Owner(workspace: workspaceID, path: note.path), content: note.content) }
    var body: some View {
        let current = request
        // Keep this note's previous excerpt while autosave refreshes it, but
        // never display another path's or another vault's old result.
        Text(loaded?.request.owner == current.owner ? loaded?.text ?? "" : "")
            .lineLimit(lines)
            .task(id: current) {
                guard loaded?.request != current else { return }
                guard let text = try? await MacCollectionExcerptLoader.shared.text(note), !Task.isCancelled else { return }
                loaded = Loaded(request: current, text: text)
            }
    }
}
