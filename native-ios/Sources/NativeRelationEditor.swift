import SwiftUI

struct NativeRelationEdit: Identifiable {
    let id = UUID()
    let notePath: String
    let name: String
}

struct NativeRelationEditor: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let edit: NativeRelationEdit
    @State private var snapshot: NativeRelationSnapshot?
    @State private var definition: NativePropertyDefinition?
    @State private var selected = Set<String>()
    @State private var unresolved: [String] = []
    @State private var retained = Set<String>()
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var archived = false
    @State private var busy = false
    @State private var failure: String?
    @State private var plan: NativeRelationPlan?
    @State private var reviewing = false
    private var selectedNotes: [NoteDocument] { (snapshot?.notes ?? []).filter { selected.contains($0.path) }.sorted { ($0.title, $0.path) < ($1.title, $1.path) } }
    private var candidates: [NoteDocument] {
        guard let snapshot, let definition else { return [] }
        return snapshot.notes.filter { note in
            note.path != edit.notePath && !selected.contains(note.path) && NativeRelationSnapshot.eligible(note, for: definition) && (archived || !note.archived) && (query.isEmpty || (note.title + " " + note.folder).localizedStandardContains(query))
        }.sorted { ($0.title, $0.path) < ($1.title, $1.path) }
    }
    var body: some View {
        NavigationStack {
            List {
                if let failure {
                    Section { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.orange); Button("Reload relation") { Task { await reload() } }.accessibilityIdentifier("relation.reload") }
                }
                if let definition {
                    Section {
                        LabeledContent("Links to", value: definition.relationTypeKey?.isEmpty == false ? definition.relationTypeKey! : "Any folder")
                        Text(definition.relationMultiple ? "Choose one or more notes. Both sides of the relation are saved together." : "Choose one note. Both sides of the relation are saved together.").font(.subheadline).foregroundStyle(.secondary)
                        if definition.relationInverseHidden { Label("The inverse stays hidden on related notes.", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary) }
                    }
                    Section {
                        if selectedNotes.isEmpty && retained.isEmpty { Text("No linked notes").foregroundStyle(.secondary) }
                        ForEach(selectedNotes) { note in
                            Button { selected.remove(note.path); searchFocused = false } label: { row(note, selected: true) }.buttonStyle(.plain).accessibilityIdentifier("relation.selected." + note.path)
                        }
                        ForEach(unresolved.filter { retained.contains($0) }, id: \.self) { reference in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) { Text(reference).lineLimit(2); Text("Missing, ambiguous or self reference").font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Button { retained.remove(reference) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove unresolved reference " + reference)
                            }
                        }
                    } header: { Text("Selected") } footer: { Text("Tap a selected note to unlink it. Its other relations stay intact. Unresolved references are retained unless you remove them.") }
                    Section {
                        Toggle("Include archived notes", isOn: $archived).accessibilityIdentifier("relation.archived")
                        if candidates.isEmpty { Text(query.isEmpty ? "No more eligible notes" : "No matching notes").foregroundStyle(.secondary) }
                        ForEach(candidates) { note in
                            Button {
                                if definition.relationMultiple { selected.insert(note.path) }
                                else { selected = [note.path]; retained = [] }
                                searchFocused = false
                            } label: { row(note, selected: false) }.buttonStyle(.plain).accessibilityIdentifier("relation.target." + note.path)
                        }
                    } header: { Text("Choose notes") }
                } else if failure == nil { ProgressView("Loading relation…") }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search notes and folders", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($searchFocused).submitLabel(.done).onSubmit { searchFocused = false }
                        .accessibilityIdentifier("relation.search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20).padding(.vertical, 8).background(.bar)
            }
            .navigationTitle(edit.name).navigationBarTitleDisplayMode(.inline)
            .disabled(busy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy).accessibilityIdentifier("relation.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView().accessibilityLabel("Saving relation") }
                    else { Button("Save") { prepare() }.disabled(snapshot == nil || definition == nil).accessibilityIdentifier("relation.save") }
                }
            }
            .interactiveDismissDisabled(busy)
            .task { await reload() }
            .confirmationDialog("Update this relation?", isPresented: $reviewing, titleVisibility: .visible) {
                Button("Save paired links") { commit() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Updates \(plan?.changedNotes.count ?? 0) notes:\n" + (plan?.changedNotes.joined(separator: "\n") ?? "") + (plan?.updatesDefinitions == true ? "\n\nRelated folder definitions are updated to keep both directions synchronized." : ""))
            }
        }
    }
    private func row(_ note: NoteDocument, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title).foregroundStyle(.primary)
                Text(note.folder + (note.trashed ? " · Recently Deleted" : note.archived ? " · Archived" : "")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : .secondary)
        }.contentShape(Rectangle())
    }
    private func reload() async {
        busy = true
        defer { busy = false }
        do {
            let value = try await vault.relationSnapshot(notePath: edit.notePath, name: edit.name)
            let selection = try value.selection()
            definition = try value.definition(); snapshot = value
            selected = selection.paths; unresolved = selection.unresolved; retained = Set(selection.unresolved); failure = nil
        } catch { snapshot = nil; definition = nil; failure = error.localizedDescription }
    }
    private func prepare() {
        guard let snapshot else { return }
        let paths = selected, unknown = retained
        busy = true
        Task {
            defer { busy = false }
            do {
                let plan = try await Task.detached { try snapshot.plan(selected: paths, unresolved: unknown) }.value
                if plan.changedNotes.isEmpty && !plan.updatesDefinitions { dismiss() }
                else { self.plan = plan; reviewing = true }
            } catch { failure = error.localizedDescription }
        }
    }
    private func commit() {
        guard let plan else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await vault.saveRelation(plan); dismiss() }
            catch { failure = error.localizedDescription }
        }
    }
}
