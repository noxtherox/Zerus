import SwiftUI

private struct DefinitionEdit: Identifiable {
    let id = UUID()
    let owner: String
    let original: NativePropertyDefinition?
}

struct NativeSchemaManager: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let notePath: String
    @State private var snapshot: NativeSchemaSnapshot?
    @State private var owner = ""
    @State private var failure: String?
    @State private var editing: DefinitionEdit?
    @State private var relationEditing: DefinitionEdit?
    @State private var pendingRelationConversion: DefinitionEdit?
    private var owners: [String] {
        var choices = Set(["", owner] + (snapshot?.owners ?? []))
        for note in vault.notes where !note.trashed && !note.path.hasPrefix(".zerus/") {
            let parts = note.path.split(separator: "/").dropLast().prefix(8)
            if !parts.isEmpty { for count in 1...parts.count { choices.insert(parts.prefix(count).joined(separator: "/")) } }
        }
        return choices.sorted()
    }
    private var owned: [NativePropertyDefinition] { (try? snapshot?.definitions(owner: owner)) ?? [] }
    private var inherited: [NativePropertyDefinition] {
        ((try? snapshot?.effective(notePath: (owner.isEmpty ? "" : owner + "/") + "note.md")) ?? []).filter { $0.owner != owner }
    }
    private var scopeError: String? {
        guard let snapshot else { return nil }
        do {
            _ = try snapshot.definitions(owner: owner)
            _ = try snapshot.effective(notePath: (owner.isEmpty ? "" : owner + "/") + "note.md")
            return nil
        } catch { return error.localizedDescription }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Folder", selection: $owner) { ForEach(owners, id: \.self) { Text(label($0)).tag($0) } }.accessibilityIdentifier("schema.folder")
                } footer: { Text("Folder definitions also apply to subfolders. Inbox definitions apply to unfiled notes.") }
                if let failure { Section { Text(failure).foregroundStyle(.red); Button("Reload definitions") { Task { await reload() } } } }
                if snapshot != nil {
                    if let scopeError { Section { Text(scopeError).foregroundStyle(.red) } }
                    Section("Defined on \(label(owner))") {
                        if owned.isEmpty { Text("No definitions on this folder").foregroundStyle(.secondary) }
                        Button("Add definition", systemImage: "plus") { editing = DefinitionEdit(owner: owner, original: nil) }.accessibilityIdentifier("schema.add").disabled(scopeError != nil)
                        Button("Add relation", systemImage: "point.3.connected.trianglepath.dotted") { relationEditing = DefinitionEdit(owner: owner, original: nil) }.accessibilityIdentifier("schema.relation.add").disabled(scopeError != nil)
                        ForEach(Array(owned.enumerated()), id: \.offset) { _, definition in row(definition) }
                    }
                    if !inherited.isEmpty {
                        Section("Inherited") { ForEach(inherited) { definition in row(definition) } }
                    }
                } else if failure == nil { ProgressView("Loading definitions…") }
            }
            .navigationTitle("Folder properties").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("schema.done") } }
        }
        .task {
            let logical = notePath.hasPrefix(".trash/") ? String(notePath.dropFirst(7)) : notePath
            owner = logical.split(separator: "/").dropLast().prefix(8).joined(separator: "/")
            await reload()
        }
        .sheet(item: $editing, onDismiss: {
            if let edit = pendingRelationConversion { pendingRelationConversion = nil; relationEditing = edit }
        }) { edit in
            NativeDefinitionEditor(owner: edit.owner, original: edit.original, affectedNotes: affected(edit), convertToRelation: {
                pendingRelationConversion = edit; editing = nil
            }) { definition in
                guard let snapshot else { throw VaultFailure(message: "Reload folder properties before saving.") }
                try await vault.saveSchema(snapshot: snapshot, owner: edit.owner, originalName: edit.original?.name, definition: definition)
                await reload()
            }
        }
        .sheet(item: $relationEditing, onDismiss: { Task { await reload() } }) { edit in
            NativeRelationDefinitionEditor(owner: edit.owner, originalName: edit.original?.name)
        }
    }
    @ViewBuilder private func row(_ definition: NativePropertyDefinition) -> some View {
        if definition.type == .unsupported || definition.name.lowercased().hasPrefix("zerus-") {
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.name)
                Text(definition.type.label + " · " + label(definition.owner)).font(.caption).foregroundStyle(.secondary)
                Text("Manage this definition with its dedicated editor on your desktop.").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Button {
                if definition.type == .relation { relationEditing = DefinitionEdit(owner: definition.owner, original: definition) }
                else { editing = DefinitionEdit(owner: definition.owner, original: definition) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(definition.name).foregroundStyle(Color.primary)
                        Text(definition.type.label + " · " + label(definition.owner)).font(.caption).foregroundStyle(Color.secondary)
                        if definition.type == .relation && definition.hidden { Label("Hidden on notes", systemImage: "eye.slash").font(.caption).foregroundStyle(Color.secondary) }
                    }
                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("schema.definition." + definition.id).disabled(scopeError != nil)
        }
    }
    private func label(_ owner: String) -> String { owner.isEmpty ? "Inbox (unfiled)" : owner }
    private func affected(_ edit: DefinitionEdit) -> Int {
        guard let original = edit.original, let snapshot else { return 0 }
        return vault.notes.filter { note in
            !note.trashed && !note.path.hasPrefix(".zerus/") && ((try? snapshot.effective(notePath: note.path).first(where: { $0.id == original.id })?.owner) == edit.owner)
        }.count
    }
    private func reload() async {
        do { snapshot = try await vault.schemaSnapshot(); failure = nil }
        catch { failure = error.localizedDescription; snapshot = nil }
    }
}

private struct NativeDefinitionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let owner: String
    let original: NativePropertyDefinition?
    let affectedNotes: Int
    let convertToRelation: () -> Void
    let save: (NativePropertyDefinition?) async throws -> Void
    @State private var name: String
    @State private var type: NativePropertyType
    @State private var options: [String]
    @State private var multiple: Bool
    @State private var draft = ""
    @State private var saving = false
    @State private var failure: String?
    @State private var review = false
    @State private var deletion = false
    init(owner: String, original: NativePropertyDefinition?, affectedNotes: Int, convertToRelation: @escaping () -> Void, save: @escaping (NativePropertyDefinition?) async throws -> Void) {
        self.owner = owner; self.original = original; self.affectedNotes = affectedNotes; self.convertToRelation = convertToRelation; self.save = save
        _name = State(initialValue: original?.name ?? "")
        _type = State(initialValue: original?.type ?? .text)
        _options = State(initialValue: original?.options ?? [])
        _multiple = State(initialValue: original?.multiple ?? false)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Folder", value: owner.isEmpty ? "Inbox (unfiled)" : owner)
                    TextField("Name", text: $name).accessibilityIdentifier("schema.name")
                    Picker("Type", selection: $type) {
                        ForEach(NativePropertyType.allCases.filter { $0 != .relation && $0 != .unsupported }) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("schema.type")
                } footer: {
                    Text(original == nil ? (owner.isEmpty ? "This definition will be available to unfiled notes." : "This definition will be available to notes in this folder and its subfolders.") : "Applies to \(affectedNotes) notes. Renaming migrates their property keys. Child-folder overrides keep their own definitions.")
                }
                if type == .list {
                    NativeDefinitionChoicesSection(options: $options, multiple: $multiple, draft: $draft, addChoice: addChoice)
                }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
                if original != nil {
                    Section { Button("Convert to relation", systemImage: "point.3.connected.trianglepath.dotted") { convertToRelation() }.accessibilityIdentifier("schema.convert.relation") }
                    Section { Button("Delete definition", role: .destructive) { deletion = true }.accessibilityIdentifier("schema.delete") }
                }
            }
            .disabled(saving)
            .navigationTitle(original == nil ? "New definition" : "Edit definition").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView().accessibilityLabel("Saving folder properties") }
                    else { Button("Save") { prepareSave() }.accessibilityIdentifier("schema.save") }
                }
            }
            .interactiveDismissDisabled(saving)
            .confirmationDialog("Update this definition for \(affectedNotes) notes?", isPresented: $review, titleVisibility: .visible) {
                Button("Update definition") { commit(removing: false) }
            } message: { Text(type == .list && !multiple ? "Each affected note will keep only its first list choice. Renamed keys will be updated in those notes." : "Property keys will be renamed in notes that inherit this definition.") }
            .confirmationDialog("Delete \(original?.name ?? "this definition")?", isPresented: $deletion, titleVisibility: .visible) {
                Button("Delete definition", role: .destructive) { commit(removing: true) }
            } message: { Text("This affects \(affectedNotes) notes. Values are removed only when no parent definition remains. Child-folder overrides are preserved.") }
        }
    }
    private func addChoice() {
        let choice = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !choice.isEmpty && !options.contains(where: { $0.caseInsensitiveCompare(choice) == .orderedSame }) { options.append(choice) }
        draft = ""
    }
    private func definition() throws -> NativePropertyDefinition {
        try NativePropertyDefinition(name: name.trimmingCharacters(in: .whitespacesAndNewlines), type: type, owner: owner, options: options, multiple: multiple).validated()
    }
    private func prepareSave() {
        addChoice()
        do {
            let next = try definition()
            if let original, next.name != original.name || (next.type == .list && !next.multiple && (original.type != .list || original.multiple)) { review = true }
            else { commit(removing: false) }
        } catch { failure = error.localizedDescription }
    }
    private func commit(removing: Bool) {
        do {
            let next = removing ? nil : try definition()
            saving = true; failure = nil
            Task {
                do { try await save(next); saving = false; dismiss() }
                catch { failure = error.localizedDescription; saving = false }
            }
        } catch { failure = error.localizedDescription }
    }
}

struct NativeDefinitionChoicesSection: View {
    @Binding var options: [String]
    @Binding var multiple: Bool
    @Binding var draft: String
    let addChoice: () -> Void
    var body: some View {
        Section("Choices") {
            ForEach(options, id: \.self) { choice in
                HStack {
                    Text(choice); Spacer()
                    Button { options.removeAll { $0 == choice } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }.buttonStyle(.borderless).accessibilityLabel("Remove choice " + choice)
                }
            }
            HStack {
                TextField("New choice", text: $draft).accessibilityIdentifier("schema.choice")
                Button("Add", action: addChoice).accessibilityIdentifier("schema.choice.add").disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Toggle("Allow multiple choices", isOn: $multiple).accessibilityIdentifier("schema.multiple")
        }
    }
}
