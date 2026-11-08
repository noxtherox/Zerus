import SwiftUI

struct NativeNoteCollectionView: View {
    enum Scope { case pinned, archive, folder(String) }
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let title: String
    let scope: Scope
    let open: (NoteDocument) -> Void
    @StateObject private var selection = NativeBulkSelection()
    @State private var query = ""
    @State private var filters = NativeCollectionFilters()
    @State private var newNote = false
    @State private var settings = false
    private var archiveOnly: Bool { if case .archive = scope { return true }; return false }
    private var candidates: [NoteDocument] {
        vault.searchableNotes.filter { note in
            guard !note.trashed else { return false }
            switch scope {
            case .pinned: return note.pinned
            case .archive: return note.archived
            case .folder(let folder): return note.regularCollectionNote && (note.folder == folder || note.folder.hasPrefix(folder + "/"))
            }
        }
    }
    private var visible: [NoteDocument] { filters.apply(candidates, query: query, archiveOnly: archiveOnly) }
    var body: some View {
        List {
            if selection.active { Section { NativeBulkControls(selection: selection, visible: visible) } }
            if visible.isEmpty {
                emptyCollection
            } else {
                Section {
                    ForEach(visible) { note in
                        NativeBulkNoteRow(selection: selection, note: note, open: open).listRowBackground(Accent.card).contextMenu { if !selection.active { NoteActions(note: note) } }
                    }
                } header: { Text("\(visible.count) \(visible.count == 1 ? "note" : "notes")") }
            }
        }.navigationTitle(title).searchable(text: $query, prompt: "Search this collection")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Settings") }
            }
            .sheet(isPresented: $settings) {
                SettingsView(collection: .init(filters: $filters, notes: candidates, selection: selection, archiveOnly: archiveOnly))
            }
            .sheet(isPresented: $newNote) {
                if case .folder(let folder) = scope { NewNoteView(workspaceID: vault.workspaceID, folder: folder, open: open) }
            }
            .scrollContentBackground(.hidden).background(Accent.paper)
            .refreshable { await vault.refresh() }
            .onChange(of: query) { _, _ in selection.clear() }
            .onChange(of: filters) { _, _ in selection.clear() }
            .modifier(NativeBulkPresentation(selection: selection))
    }
    @ViewBuilder private var emptyCollection: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filters.activeCount > 0 {
            ContentUnavailableView {
                Label("No matching notes", systemImage: "doc.text.magnifyingglass")
            } description: { Text("Try another search or clear your filters.") }
            actions: { Button("Clear search and filters") { query = ""; filters = .init() } }
        } else {
            switch scope {
            case .archive:
                ContentUnavailableView {
                    Label("No archived notes", systemImage: "archivebox")
                } description: { Text("Notes you archive will appear here.") }
                actions: { Button("Back to Library") { dismiss() } }
            case .pinned:
                ContentUnavailableView {
                    Label("No pinned notes", systemImage: "pin")
                } description: { Text("Pin a note to keep it close at hand.") }
                actions: { Button("Back to Library") { dismiss() } }
            case .folder:
                ContentUnavailableView {
                    Label("No notes in this folder", systemImage: "folder")
                } description: { Text(candidates.contains(where: \.archived) ? "This folder's notes are archived. Show them here or return to Library." : "Notes you save in this folder will appear here.") }
                actions: {
                    if candidates.contains(where: \.archived) { Button("Show archived notes") { filters.includeArchived = true } }
                    Button("New note") { newNote = true }
                    Button("Back to Library") { dismiss() }
                }
            }
        }
    }
}
