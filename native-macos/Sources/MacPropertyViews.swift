import SwiftUI

struct MacPropertyEdit: Identifiable {
    let id = UUID()
    var name: String
    var value: NativePropertyValue?
    var definition: NativePropertyDefinition?
    var path: String? = nil
    var expected: String? = nil
    var workspaceID: UUID? = nil
}
struct MacPropertyEditor: View {
    @Bindable var store: MacWorkspace
    let edit: MacPropertyEdit
    @State private var name = ""
    @State private var text = ""
    @State private var checked = false
    @State private var dateValid = true
    @State private var choices = Set<String>()
    @State private var kind: NativePropertyType = .text
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit property").macFont(.headline)
            TextField("Name", text: $name).disabled(!edit.name.isEmpty)
            if edit.definition == nil { Picker("Type", selection: $kind) { ForEach([NativePropertyType.text, .url, .number, .date, .checkbox, .list], id: \.self) { Text($0.label).tag($0) } } }
            if kind == .checkbox { Toggle("Checked", isOn: $checked) }
            else if kind == .list, let definition = edit.definition, !definition.options.isEmpty {
                ForEach(definition.options, id: \.self) { option in Toggle(option, isOn: Binding(get: { choices.contains(option) }, set: { checked in if checked { if !definition.multiple { choices = [] }; choices.insert(option) } else { choices.remove(option) } })) }
            } else if kind == .date { MacDateField("Date", value: $text, valid: $dateValid, allowEmpty: false) }
            else { TextField(kind == .list ? "Values, separated by commas" : "Value", text: $text) }
            if let issue { Text(issue).foregroundStyle(.red).macFont(.caption) }
            HStack { if edit.value != nil { Button("Clear value") { Task { await commit(nil) } } }; Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(name.isEmpty || kind == .date && !dateValid) }
        }.padding(24).frame(width: 440).onAppear {
            name = edit.name; kind = edit.definition?.type ?? .inferred(edit.value); text = edit.value?.display ?? ""
            if case .checkbox(let value) = edit.value { checked = value }
            choices = Set(edit.value?.selections ?? [])
        }
    }
    private func save() {
        guard kind != .date || dateValid else { issue = "Correct the date before saving."; return }
        do {
            let value: NativePropertyValue
            switch kind {
            case .checkbox: value = .checkbox(checked)
            case .date: guard let day = MacNumericDateFormat.localDay(text) else { throw VaultFailure(message: "Choose a valid calendar date.") }; value = .text(day)
            case .number: guard Double(text) != nil else { throw VaultFailure(message: "Enter a number.") }; value = .number(text)
            case .list:
                let values = edit.definition?.options.isEmpty == false ? choices.sorted() : text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                value = .list(values)
            default: value = .text(text)
            }
            if let definition = edit.definition { try definition.validateValue(value) }
            Task { await commit(value) }
        } catch { issue = error.localizedDescription }
    }
    private func commit(_ value: NativePropertyValue?) async {
        if let path = edit.path, let expected = edit.expected, let workspaceID = edit.workspaceID {
            do { try await store.setCollectionProperty(path: path, expected: expected, workspaceID: workspaceID, name: name, value: value); dismiss() }
            catch { issue = error.localizedDescription }
        } else { await store.setProperty(name, value: value); if store.issue == nil { dismiss() } }
    }

}

struct MacRelationEditor: View {
    @Bindable var store: MacWorkspace
    let name: String
    var path: String? = nil
    @State private var workspaceID: UUID?
    @State private var snapshot: NativeRelationSnapshot?
    @State private var selected = Set<String>()
    @State private var unresolved = Set<String>()
    @State private var query = ""
    @State private var issue: String?
    @State private var plan: NativeRelationPlan?
    @State private var review = false
    @Environment(\.dismiss) private var dismiss
    var definition: NativePropertyDefinition? { try? snapshot?.definition() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(name).macFont(.title2.bold())
            Text("Both sides of this relation are saved together.").macFont(.caption).foregroundStyle(.secondary)
            TextField("Find notes", text: $query).textFieldStyle(.roundedBorder)
            List {
                if let snapshot, let definition {
                    ForEach(snapshot.notes.filter { !$0.trashed && $0.path != snapshot.sourcePath && (selected.contains($0.path) || NativeRelationSnapshot.eligible($0, for: definition)) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }) { note in
                        Toggle(isOn: Binding(get: { selected.contains(note.path) }, set: { enabled in if enabled { if !definition.relationMultiple { selected = [] }; selected.insert(note.path) } else { selected.remove(note.path) } })) { VStack(alignment: .leading) { Text(note.title); Text(note.folder).macFont(.caption).foregroundStyle(.secondary) } }
                    }
                }
            }
            if !unresolved.isEmpty { Text("Unresolved links are retained: " + unresolved.sorted().joined(separator: ", ")).macFont(.caption).foregroundStyle(.secondary) }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Review changes") {
                do { plan = try snapshot?.plan(selected: selected, unresolved: unresolved); review = plan != nil }
                catch { issue = error.localizedDescription }
            }.disabled(snapshot == nil) }
        }.padding(22).frame(width: 540, height: 540).task {
            guard let io = store.io, let path = path ?? store.selection else { return }
            workspaceID = store.workspaceID
            do { let value = try await io.relationSnapshot(notePath: path, name: name); snapshot = value; let current = try value.selection(); selected = current.paths; unresolved = Set(current.unresolved) }
            catch { issue = error.localizedDescription }
        }.confirmationDialog("Save paired links?", isPresented: $review) {
            Button("Save paired links") { Task {
                guard let io = store.io, let plan, workspaceID == store.workspaceID, await store.save(), workspaceID == store.workspaceID else { issue = "The vault changed. Reopen this relation."; return }
                do { store.apply(try await io.applyRelation(plan)); await store.reloadCurrent(); dismiss() }
                catch { issue = error.localizedDescription }
            } }
        } message: { Text("Updates these notes:\n" + (plan?.changedNotes.joined(separator: "\n") ?? "")) }
    }
}

struct MacSchemaEditor: View {
    @Bindable var store: MacWorkspace
    let owner: String
    @State private var snapshot: NativeRelationDefinitionSnapshot?
    @State private var definitions: [NativePropertyDefinition] = []
    @State private var openingWorkspaceID: UUID?
    @State private var selectedName: String?
    @State private var form = MacSchemaForm()
    @State private var review: MacSchemaReview?
    @State private var issue: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    private var unsupported: Bool { form.kind == .unsupported }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Folder properties · " + (owner.isEmpty ? "Vault root" : owner)).macFont(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Review changes to definitions and note values before applying. Inherited child overrides and unknown settings are preserved.").macFont(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(definitions) { definition in
                                Button { select(definition) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(definition.name).fontWeight(selectedName == definition.name ? .semibold : .regular)
                                        Text(definition.type.label).macFont(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10).contentShape(Rectangle())
                                }.buttonStyle(MacBoxButtonStyle()).background(selectedName == definition.name ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                    .accessibilityLabel(definition.name + " · " + definition.type.label)
                            }
                        }.padding(6)
                    }.frame(width: 230, height: 330).background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    Button("New definition") { selectedName = nil; form = .init(); issue = nil }.disabled(snapshot == nil)
                }
                ScrollView {
                    Form {
                        TextField("Name", text: $form.name)
                        Picker("Type", selection: $form.kind) {
                            ForEach(NativePropertyType.allCases.filter { $0 != .unsupported }) { Text($0.label).tag($0) }
                            if unsupported { Text("Unsupported").tag(NativePropertyType.unsupported) }
                        }
                        if form.kind == .list {
                            Text("Choices").macFont(.headline)
                            ForEach($form.choices) { $choice in
                                HStack {
                                    TextField("Choice", text: $choice.value)
                                    Button { form.choices.removeAll { $0.id == choice.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(MacBoxButtonStyle()).accessibilityLabel("Remove choice " + choice.value)
                                }
                            }
                            Button("Add choice") { form.choices.append(.init(value: "")) }
                            Text("Each row is one choice. Commas stay part of its name.").macFont(.caption).foregroundStyle(.secondary)
                            Toggle("Multiple choices", isOn: $form.multiple)
                        }
                        if form.kind == .relation {
                            TextField("Target folder (empty for any)", text: $form.target)
                            Toggle("Multiple notes", isOn: $form.multiple)
                            Toggle("Hide this relation", isOn: $form.hidden)
                            Toggle("Hide inverse relation", isOn: $form.inverseHidden)
                        }
                    }.disabled(unsupported).padding(4)
                }.frame(width: 360, height: 360)
            }
            if unsupported { Text("This definition uses an unsupported type and is preserved without changes.").macFont(.caption).foregroundStyle(.secondary) }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Reload definitions") { Task { await reload() } }
                if selectedName != nil { Button("Review removal…", role: .destructive) { prepare(removing: true) }.disabled(unsupported || snapshot == nil) }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Review changes") { prepare(removing: false) }.buttonStyle(.borderedProminent).disabled(form.name.isEmpty || unsupported || snapshot == nil)
            }
        }.padding(24).frame(width: 680).disabled(busy)
        .task { await reload() }
        .macSheet(item: $review) { review in MacSchemaReviewView(store: store, review: review) { Task { await reload(selecting: review.definition?.name) } } }
        .onChange(of: store.workspaceID) { _, _ in snapshot = nil; definitions = []; review = nil; issue = "The vault changed. Close and reopen folder properties." }
    }
    private func select(_ definition: NativePropertyDefinition) { selectedName = definition.name; form = .init(definition); issue = nil }
    private func reload(selecting name: String? = nil) async {
        guard openingWorkspaceID == nil || openingWorkspaceID == store.workspaceID else { issue = "The vault changed. Close and reopen folder properties."; return }
        if openingWorkspaceID == nil { openingWorkspaceID = store.workspaceID }
        busy = true; issue = nil; defer { busy = false }
        do {
            let fresh = try await store.schemaDefinitionSnapshot()
            guard fresh.schema.workspaceID == openingWorkspaceID else { throw VaultFailure(message: "The vault changed. Reopen folder properties.") }
            let values = try fresh.schema.definitions(owner: owner)
            guard Set(values.map(\.id)).count == values.count else { throw VaultFailure(message: "This folder has duplicate definition names. Resolve them before editing properties.") }
            snapshot = fresh; definitions = values
            if let name, let selected = values.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { select(selected) }
            else { selectedName = nil; form = .init() }
        } catch { snapshot = nil; definitions = []; issue = error.localizedDescription }
    }
    private func prepare(removing: Bool) {
        guard let snapshot else { return }; busy = true; issue = nil
        Task { defer { busy = false }; do {
            let definition = try removing ? nil : form.definition(owner: owner)
            review = try await store.prepareSchemaReview(snapshot, owner: owner, originalName: selectedName, definition: definition)
        } catch { issue = error.localizedDescription } }
    }
}
