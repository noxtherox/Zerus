import SwiftUI

@MainActor
final class NativeBulkSelection: ObservableObject {
    @Published var active = false
    @Published var request: NativeBulkRequest?
    @Published var history = false
    @Published private(set) var selected: [String: NoteDocument] = [:]
    func toggle(_ note: NoteDocument) { if selected[note.path] == nil { selected[note.path] = note } else { selected.removeValue(forKey: note.path) } }
    func selectAll(_ notes: [NoteDocument]) { selected = Dictionary(uniqueKeysWithValues: notes.map { ($0.path, $0) }) }
    func clear() { selected = [:] }
    func finish() { clear(); active = false }
}
struct NativeBulkRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let selected: [NoteDocument]
    let mutation: NativeBulkMutation
}
struct NativeBulkControls: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var selection: NativeBulkSelection
    let visible: [NoteDocument]
    private var selectionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { if selection.active { selection.finish() } else { selection.active = true } } label: {
                    Text(selection.active ? "Done selecting" : "Select notes").frame(minHeight: 44).contentShape(Rectangle())
                }.accessibilityIdentifier("bulk.select")
                Spacer()
                Button { selection.history = true } label: {
                    Label("Recent actions", systemImage: "clock.arrow.circlepath").labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.accessibilityIdentifier("bulk.history")
            }
            if selection.active {
                selectionLayout {
                    Text("\(selection.selected.count) selected").font(.subheadline).foregroundStyle(Accent.secondaryText)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Button { selection.selectAll(visible.filter { !$0.unfiledSavedLink && (!$0.path.hasPrefix(".zerus/") || $0.fileHub != nil) }) } label: {
                        Text("Select all").frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("bulk.all")
                    if !selection.selected.isEmpty {
                        Button { selection.clear() } label: { Text("Clear").frame(minHeight: 44).contentShape(Rectangle()) }
                    }
                }
                Menu {
                    Button("Pin", systemImage: "pin") { present(.init(pinned: true)) }
                    Button("Unpin", systemImage: "pin.slash") { present(.init(pinned: false)) }
                    Button("Archive", systemImage: "archivebox") { present(.init(archived: true)) }
                    Button("Unarchive", systemImage: "tray.and.arrow.up") { present(.init(archived: false)) }
                    Button("Edit properties and relations", systemImage: "slider.horizontal.3") { present(.init()) }
                } label: { Label("Actions", systemImage: "ellipsis.circle").frame(minHeight: 44).contentShape(Rectangle()) }.disabled(selection.selected.isEmpty).accessibilityIdentifier("bulk.actions")
            }
        }.font(.body).buttonStyle(.borderless)
    }
    private func present(_ mutation: NativeBulkMutation) {
        selection.request = .init(workspaceID: vault.workspaceID, selected: selection.selected.values.sorted { $0.path < $1.path }, mutation: mutation)
    }
}
/// Present from the collection screen, not a reusable scrolling controls row.
/// Keyboard layout and background scans must not retire an in-progress review.
struct NativeBulkPresentation: ViewModifier {
    @EnvironmentObject private var vault: VaultStore
    @ObservedObject var selection: NativeBulkSelection
    func body(content: Content) -> some View {
        content
            .sheet(item: $selection.request) { request in
                NativeBulkActionView(request: request) { selection.finish() }
            }
            .sheet(isPresented: $selection.history) { NativeBulkHistoryView(workspaceID: vault.workspaceID) }
    }
}

struct NativeBulkNoteRow: View {
    @ObservedObject var selection: NativeBulkSelection
    let note: NoteDocument
    let open: (NoteDocument) -> Void
    private var selected: Bool { selection.selected[note.path] != nil }
    var body: some View {
        Button { if selection.active { selection.toggle(note) } else { open(note) } } label: {
            HStack(spacing: 12) {
                if selection.active { Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : .secondary).font(.title3) }
                NoteRow(note: note)
            }
        }.buttonStyle(.plain).accessibilityIdentifier("bulk.note." + note.path).accessibilityValue(selection.active ? (selected ? "Selected" : "Not selected") : "")
            .disabled(selection.active && (note.unfiledSavedLink || note.path.hasPrefix(".zerus/") && note.fileHub == nil))
    }
}

struct NativeBulkActionView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let request: NativeBulkRequest
    let applied: () -> Void
    @State private var snapshot: NativeBulkSnapshot?
    @State private var definitions: [NativePropertyDefinition] = []
    @State private var changes: [NativeBulkPropertyChange] = []
    @State private var editing: NativeBulkPropertyChoice?
    @State private var plan: NativeBulkPlan?
    @State private var busy = false
    @State private var failure: String?
    private var properties: Bool { request.mutation.pinned == nil && request.mutation.archived == nil }
    var body: some View {
        NavigationStack {
            Group {
                if let plan { NativeBulkReview(plan: plan) }
                else {
                    Form {
                        Section {
                            Text("\(request.selected.count) selected \(request.selected.count == 1 ? "note" : "notes")")
                            Text("Review the changes before applying them. Notes with incompatible values are listed separately.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        if properties {
                            Section {
                                ForEach(definitions) { definition in
                                    Button { editing = .init(definition: definition, existing: changes.first { $0.id == definition.id }, notes: snapshot?.source.notes ?? [], excluded: Set(request.selected.map(\.path))) } label: {
                                        HStack { Text(definition.name); Spacer(); Text(changes.first { $0.id == definition.id }.map { $0.operation.rawValue + ($0.value.map { ": " + $0.display } ?? "") } ?? "Unchanged").foregroundStyle(.secondary).lineLimit(2) }
                                    }.accessibilityIdentifier("bulk.property." + definition.id)
                                }
                                if definitions.isEmpty && snapshot != nil { Text("The selected notes do not share editable folder properties. Choose notes with matching definitions.").foregroundStyle(.secondary) }
                            } header: { Text("Common properties and relations") }
                        } else { Section { Label(request.mutation.label, systemImage: request.mutation.pinned == nil ? "archivebox" : "pin") } }
                        Section("Selected notes") { ForEach(request.selected) { note in VStack(alignment: .leading) { Text(note.title); Text(note.path).font(.caption).foregroundStyle(.secondary) } } }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if let failure { Text(failure).font(.callout).foregroundStyle(.red).padding().frame(maxWidth: .infinity).background(.bar).accessibilityIdentifier("bulk.error") } }
            .navigationTitle(plan == nil ? request.mutation.label : "Review changes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy).accessibilityIdentifier("bulk.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() }
                    else if let plan { Button("Apply") { Task { await commit(plan) } }.disabled(!plan.hasChanges).accessibilityIdentifier("bulk.apply") }
                    else { Button("Review") { prepare() }.disabled(snapshot == nil || properties && changes.isEmpty).accessibilityIdentifier("bulk.review") }
                }
            }.interactiveDismissDisabled(busy).disabled(busy)
                .task {
                    busy = true; defer { busy = false }
                    do { let value = try await vault.bulkSnapshot(workspace: request.workspaceID); snapshot = value; definitions = try value.commonProperties(request.selected) }
                    catch { failure = error.localizedDescription }
                }
                .sheet(item: $editing) { choice in NativeBulkPropertyComposer(choice: choice, remove: { changes.removeAll { $0.id == choice.definition.id } }) { change in changes.removeAll { $0.id == change.id }; changes.append(change) } }
        }
    }
    private func prepare() {
        guard let snapshot else { return }
        var mutation = request.mutation; mutation.properties = changes
        let selected = request.selected
        busy = true
        Task {
            defer { busy = false }
            do {
                let value = try await Task.detached(priority: .userInitiated) { try snapshot.plan(selected: selected, mutation: mutation) }.value
                guard request.workspaceID == vault.workspaceID else { throw CancellationError() }
                plan = value; failure = nil
            } catch { failure = error.localizedDescription }
        }
    }
    private func commit(_ plan: NativeBulkPlan) async {
        busy = true; defer { busy = false }
        do { try await vault.saveBulk(plan); applied(); dismiss() }
        catch { failure = error.localizedDescription }
    }
}
struct NativeBulkReview: View {
    let plan: NativeBulkPlan
    var body: some View {
        List {
            Section {
                Text(plan.label).font(.headline)
                Text("\(plan.changedNotes.count) note files will change. Your writing and unrelated properties are preserved. The action and its undo record are saved together.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(plan.changedNotes, id: \.self) { path in
                let change = plan.changes.first { $0.path == path }!
                DisclosureGroup {
                    if let before = change.before, let after = change.after {
                        Text("Before").font(.caption.weight(.semibold)); Text(NoteDocument.split(String(decoding: before, as: UTF8.self)).header).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Text("After").font(.caption.weight(.semibold)); Text(NoteDocument.split(String(decoding: after, as: UTF8.self)).header).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                } label: { VStack(alignment: .leading, spacing: 4) { Text(path); Text(plan.changedFields[path]?.joined(separator: ", ") ?? "Reciprocal relation or note identity").font(.caption).foregroundStyle(.secondary) } }
            }
            if !plan.issues.isEmpty { Section("Skipped or needs attention") { ForEach(plan.issues) { issue in VStack(alignment: .leading, spacing: 5) { Text(issue.path); Text(issue.reason).font(.caption).foregroundStyle(.secondary) } } } }
            Section { Text("Recent actions keeps the last ten actions for up to 90 days in this vault. Undo preserves later edits and reports any field it cannot safely change.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct NativeBulkReviewRoute: Hashable {
    let plan: NativeBulkPlan
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.plan.id == rhs.plan.id }
    func hash(into hasher: inout Hasher) { hasher.combine(plan.id) }
}

struct NativeBulkHistoryView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let workspaceID: UUID
    @State private var snapshot: NativeBulkSnapshot?
    @State private var path: [NativeBulkReviewRoute] = []
    @State private var failure: String?
    @State private var busy = false
    private var records: [NativeBulkRecord] { (snapshot?.records ?? []).filter { $0.date >= Date().addingTimeInterval(-90 * 86400) } }
    var body: some View {
        NavigationStack(path: $path) {
            List {
                if snapshot != nil {
                    if records.isEmpty { ContentUnavailableView("No recent bulk actions", systemImage: "clock.arrow.circlepath") }
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(record.label).font(.headline); Text(record.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            Text("\(record.entries.count) notes · \(record.status)").font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                if record.appliedCount > 0 { Button("Review undo") { prepare(record, undo: true) }.accessibilityIdentifier("bulk.undo." + record.id.uuidString) }
                                if record.appliedCount < record.fieldCount { Button("Review redo") { prepare(record, undo: false) }.accessibilityIdentifier("bulk.redo." + record.id.uuidString) }
                            }.buttonStyle(.borderless)
                        }.padding(.vertical, 5)
                    }
                } else { ProgressView("Loading actions…") }
            }.disabled(busy).navigationTitle("Recent actions").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if path.isEmpty { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy).accessibilityIdentifier("bulk.history.done") } }
                }
                .navigationDestination(for: NativeBulkReviewRoute.self) { route in
                    NativeBulkReview(plan: route.plan).navigationTitle("Review changes").navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(busy)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Apply") { Task { await commit(route.plan) } }.disabled(busy || !route.plan.hasChanges).accessibilityIdentifier("bulk.apply") } }
                        .safeAreaInset(edge: .bottom) { errorMessage }
                }
                .safeAreaInset(edge: .bottom) { if path.isEmpty { errorMessage } }
                .task { await reload() }
                .onChange(of: path) { _, value in if value.isEmpty { failure = nil } }
        }.interactiveDismissDisabled(busy)
    }
    @ViewBuilder private var errorMessage: some View {
        if let failure { Text(failure).foregroundStyle(.red).padding().background(.bar).accessibilityIdentifier("bulk.error") }
    }
    private func commit(_ plan: NativeBulkPlan) async {
        busy = true; defer { busy = false }
        do { try await vault.saveBulk(plan); path = []; await reload() }
        catch { failure = error.localizedDescription }
    }
    private func reload() async { do { snapshot = try await vault.bulkSnapshot(workspace: workspaceID); failure = nil } catch { failure = error.localizedDescription } }
    private func prepare(_ record: NativeBulkRecord, undo: Bool) {
        guard let snapshot else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let value = try await Task.detached(priority: .userInitiated) { try snapshot.transition(record.id, undo: undo) }.value
                guard workspaceID == vault.workspaceID else { throw CancellationError() }
                path = [NativeBulkReviewRoute(plan: value)]; failure = nil
            } catch { failure = error.localizedDescription }
        }
    }
}

struct NativeBulkPropertyChoice: Identifiable {
    let id = UUID()
    let definition: NativePropertyDefinition
    let existing: NativeBulkPropertyChange?
    let notes: [NoteDocument]
    let excluded: Set<String>
}
private struct NativeBulkPropertyComposer: View {
    @Environment(\.dismiss) private var dismiss
    let choice: NativeBulkPropertyChoice
    let remove: () -> Void
    let save: (NativeBulkPropertyChange) -> Void
    @State private var operation: NativeBulkOperation
    @State private var value: NativePropertyValue?
    @State private var editValue = false
    @State private var failure: String?
    init(choice: NativeBulkPropertyChoice, remove: @escaping () -> Void, save: @escaping (NativeBulkPropertyChange) -> Void) { self.choice = choice; self.remove = remove; self.save = save; _operation = State(initialValue: choice.existing?.operation ?? .set); _value = State(initialValue: choice.existing?.value) }
    private var multiple: Bool { choice.definition.type == .relation ? choice.definition.relationMultiple : choice.definition.type == .list && choice.definition.multiple }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Operation", selection: $operation) { ForEach(NativeBulkOperation.allCases.filter { multiple || $0 == .set || $0 == .clear }) { Text($0.rawValue).tag($0) } }.pickerStyle(.navigationLink).accessibilityIdentifier("bulk.property.operation")
                if operation != .clear { Button { editValue = true } label: { LabeledContent("Value", value: value?.display ?? "Choose…") }.accessibilityIdentifier("bulk.property.value") }
                if choice.existing != nil { Section { Button("Keep unchanged") { remove(); dismiss() }.accessibilityIdentifier("bulk.property.unchanged") } }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.navigationTitle(choice.definition.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Use change") { save(.init(name: choice.definition.name, operation: operation, value: value)); dismiss() }.disabled(operation != .clear && value == nil).accessibilityIdentifier("bulk.property.use") }
                }
                .sheet(isPresented: $editValue) {
                    if choice.definition.type == .relation { NativeBulkRelationPicker(choice: choice, value: value) { value = $0 } }
                    else {
                        NativePropertyEditor(edit: .init(definition: choice.definition, name: choice.definition.name, value: value, save: { _, next in value = next })) { _, next in value = next }
                    }
                }
        }
    }
}
private struct NativeBulkRelationPicker: View {
    @Environment(\.dismiss) private var dismiss
    let choice: NativeBulkPropertyChoice
    let save: (NativePropertyValue?) -> Void
    @State private var paths: Set<String>
    @State private var query = ""
    @State private var archived = false
    @FocusState private var searchFocused: Bool
    init(choice: NativeBulkPropertyChoice, value: NativePropertyValue?, save: @escaping (NativePropertyValue?) -> Void) {
        self.choice = choice; self.save = save
        let references = value?.selections ?? []
        _paths = State(initialValue: Set(choice.notes.filter { note in references.contains { raw in NoteReference(wikilink: "[[" + raw + "]]")?.targets(in: choice.notes).contains(where: { $0.path == note.path }) == true } }.map(\.path)))
    }
    var body: some View {
        NavigationStack {
            List {
                Toggle("Include archived", isOn: $archived)
                ForEach(choice.notes.filter { !choice.excluded.contains($0.path) && NativeRelationSnapshot.eligible($0, for: choice.definition) && (archived || !$0.archived || paths.contains($0.path)) && (query.isEmpty || ($0.title + " " + $0.folder).localizedStandardContains(query)) }.sorted { $0.path < $1.path }) { note in
                    Button { if paths.contains(note.path) { paths.remove(note.path) } else if choice.definition.relationMultiple { paths.insert(note.path) } else { paths = [note.path] } } label: {
                        HStack { VStack(alignment: .leading) { Text(note.title); Text(note.folder).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: paths.contains(note.path) ? "checkmark.circle.fill" : "circle") }
                    }.accessibilityIdentifier("bulk.relation." + note.path)
                }
            }.scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .top) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find related notes", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searchFocused).submitLabel(.done).onSubmit { searchFocused = false }.accessibilityIdentifier("bulk.relation.search")
                        if !query.isEmpty { Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }.labelStyle(.iconOnly) }
                    }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 20).padding(.vertical, 8).background(.bar)
                }.navigationTitle("Choose notes").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use notes") {
                            let references = choice.notes.filter { paths.contains($0.path) }.map { $0.stableID.map { "zerus:" + $0 } ?? $0.path }
                            save(choice.definition.relationMultiple ? .list(references) : .text(references.first ?? "")); dismiss()
                        }.accessibilityIdentifier("bulk.relation.use")
                    }
                }
        }
    }
}
