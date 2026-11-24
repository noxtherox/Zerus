import SwiftUI

struct MacNoteListScope: Equatable {
    let workspace: UUID
    let destination: String
    let folder: Bool
    let query: String
    let filters: NativeCollectionFilters
    let hideSubtypes: Bool
}

/// Keep SwiftUI's initial row inventory bounded, as the desktop note list does.
/// Selection and filtering still use the complete collection in the workspace.
struct MacProgressiveNoteList<Row: View>: View {
    let notes: [NoteDocument]
    let scope: MacNoteListScope
    let row: (NoteDocument) -> Row
    @State private var count = 40
    @State private var activeScope: MacNoteListScope
    @State private var position = ScrollPosition(edge: .top)

    init(notes: [NoteDocument], scope: MacNoteListScope, row: @escaping (NoteDocument) -> Row) {
        self.notes = notes; self.scope = scope; self.row = row
        _activeScope = State(initialValue: scope)
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(notes.prefix(count)) { note in row(note) }
                if count < notes.count {
                    let shown = count
                    Button("Show more notes") { reveal(after: shown) }
                        .font(.caption).padding(12)
                        .onAppear { reveal(after: shown) }
                }
            }
        }
        .scrollPosition($position)
        .onChange(of: scope) { _, next in
            activeScope = next; count = 40
            position.scrollTo(edge: .top)
        }
    }
    private func reveal(after shown: Int) {
        guard activeScope == scope, count == shown else { return }
        count = min(notes.count, shown + 40)
    }
}

/// Gallery cards retain their complete collection order and selection domain,
/// while the lazy grid receives only the pages reached by scrolling.
struct MacProgressiveNoteGrid<Card: View>: View {
    let notes: [NoteDocument]
    let scope: MacNoteListScope
    let card: (NoteDocument) -> Card
    @State private var count = 40
    @State private var activeScope: MacNoteListScope
    init(notes: [NoteDocument], scope: MacNoteListScope, card: @escaping (NoteDocument) -> Card) {
        self.notes = notes; self.scope = scope; self.card = card
        _activeScope = State(initialValue: scope)
    }
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], alignment: .leading) {
            ForEach(notes.prefix(count)) { card($0) }
            if count < notes.count {
                let shown = count
                Button("Show more notes") { reveal(after: shown) }
                    .font(.caption).padding(12)
                    .onScrollVisibilityChange(threshold: 0.1) { visible in
                        if visible { reveal(after: shown) }
                    }.id(shown)
            }
        }.onChange(of: scope) { _, next in activeScope = next; count = 40 }
    }
    private func reveal(after shown: Int) {
        guard activeScope == scope, count == shown else { return }
        count = min(notes.count, shown + 40)
    }
}
