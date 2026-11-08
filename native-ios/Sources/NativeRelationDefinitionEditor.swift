import SwiftUI

struct NativeRelationDefinitionEditor: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let owner: String
    let originalName: String?
    @State private var snapshot: NativeRelationDefinitionSnapshot?
    @State private var name = ""
    @State private var originalType: NativePropertyType = .relation
    @State private var type: NativePropertyType = .relation
    @State private var options: [String] = []
    @State private var listMultiple = false
    @State private var choice = ""
    @State private var target = ""
    @State private var multiple = false
    @State private var inverseHidden = false
    @State private var hidden = false
    @State private var busy = false
    @State private var failure: String?
    @State private var plan: NativeRelationDefinitionPlan?
    @State private var reviewing = false
    @FocusState private var editingName: Bool
    private var folders: [String] {
        var folders = Set([target, owner] + (snapshot?.schema.owners ?? []))
        for note in snapshot?.notes ?? [] where !note.trashed && !note.path.hasPrefix(".zerus/") {
            let parts = NativeRelationSnapshot.owner(note).split(separator: "/")
            for count in 1..<(parts.count + 1) { folders.insert(parts.prefix(count).joined(separator: "/")) }
        }
        return folders.filter { !$0.isEmpty }.sorted()
    }
    var body: some View {
        NavigationStack {
            Form {
                if let failure {
                    Section { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.orange); Button("Reload definition") { Task { await reload() } } }
                }
                if snapshot != nil {
                    Section {
                        LabeledContent("Folder", value: owner.isEmpty ? "Inbox (unfiled)" : owner)
                        TextField("Name", text: $name).focused($editingName).accessibilityIdentifier("relation.definition.name")
                        if originalName != nil, originalType == .relation {
                            Picker("Type", selection: $type) {
                                ForEach(NativePropertyType.allCases.filter { $0 != .unsupported }) { Text($0.label).tag($0) }
                            }.accessibilityIdentifier("relation.definition.type")
                        }
                    } footer: { Text("Applies to this folder and its subfolders, except child overrides.") }
                    if type == .relation {
                        Section {
                            Picker("Links to", selection: $target) {
                                Text("Any folder").tag("")
                                ForEach(folders, id: \.self) { Text($0).tag($0) }
                            }.accessibilityIdentifier("relation.definition.target")
                            Toggle("Allow multiple notes", isOn: $multiple).accessibilityIdentifier("relation.definition.multiple")
                        } footer: { Text("Changing the target folder or allowing only one note preserves existing links; new selections follow the updated rules.") }
                        Section {
                            Toggle("Hide on related notes", isOn: $inverseHidden).accessibilityIdentifier("relation.definition.inverseHidden")
                            Toggle("Hide on this folder’s notes", isOn: $hidden).accessibilityIdentifier("relation.definition.hidden")
                        } footer: { Text("Relations always save both ways. Hidden fields retain their values. You can reveal them again here in Folder properties.") }
                    } else {
                        Section {
                            Text("Converting to \(type.label) removes reciprocal links from related notes and keeps your stored values. Values that do not fit the new type can be edited afterward.")
                            if type == .list && !listMultiple { Text("A single-choice list keeps only the first stored value. The review lists every affected note.").foregroundStyle(.secondary) }
                        }
                        if type == .list { NativeDefinitionChoicesSection(options: $options, multiple: $listMultiple, draft: $choice, addChoice: addChoice) }
                    }
                    if originalName != nil, originalType == .relation {
                        Section { Button("Delete relation", role: .destructive) { prepare(removing: true) }.accessibilityIdentifier("relation.definition.delete") } footer: {
                            Text("Child overrides and inverse definitions remain. If a parent definition exists, values inherit it; otherwise values and their paired links are removed together.")
                        }
                    }
                } else if failure == nil { ProgressView("Loading definition…") }
            }
            .disabled(busy)
            .navigationTitle(originalName == nil ? "New relation" : "Edit property").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy).accessibilityIdentifier("relation.definition.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button { prepare(removing: false) } label: {
                        if busy { ProgressView().accessibilityLabel("Preparing relation definition") }
                        else { Text("Save") }
                    }.disabled(busy || snapshot == nil).accessibilityIdentifier("relation.definition.save")
                }
            }
            .interactiveDismissDisabled(busy)
            .task { await reload() }
            .sheet(isPresented: $reviewing) { review }
        }
    }
    private var review: some View {
        NavigationStack {
            List {
                Section {
                    Text(plan?.removing == true ? "Remove this relation definition?" : "Save this property definition?").font(.headline)
                    LabeledContent("Notes in scope", value: String(plan?.affectedCount ?? 0))
                    LabeledContent("Note files changed", value: String(plan?.changedNotes.count ?? 0))
                    Text("Folder definitions and all affected note values are saved together. Cancel leaves every file unchanged.").foregroundStyle(.secondary)
                }
                Section("Definition") {
                    if let originalName, originalName != name && plan?.removing != true { LabeledContent("Previous name", value: originalName) }
                    LabeledContent("Name", value: plan?.removing == true ? originalName ?? name : name)
                    LabeledContent("Folder", value: owner.isEmpty ? "Inbox (unfiled)" : owner)
                    if plan?.removing != true {
                        LabeledContent("Type", value: type.label)
                        if originalType != type { LabeledContent("Previous type", value: originalType.label) }
                        if type != .relation {
                            Text("Reciprocal links are removed. Source values and child overrides are preserved; a single-choice list keeps its first value.").foregroundStyle(.secondary)
                            if type == .list { LabeledContent("Choices", value: options.joined(separator: ", ")); LabeledContent("Selection", value: listMultiple ? "Multiple choices" : "One choice") }
                        }
                    }
                    if plan?.removing != true, type == .relation {
                        LabeledContent("Links to", value: target.isEmpty ? "Any folder" : target)
                        LabeledContent("Selection", value: multiple ? "Multiple notes" : "One note")
                        LabeledContent("On this folder’s notes", value: hidden ? "Hidden" : "Visible")
                        LabeledContent("On related notes", value: inverseHidden ? "Hidden" : "Visible")
                    }
                }
                if let plan, !plan.changedNotes.isEmpty {
                    Section("Files to update") { ForEach(plan.changedNotes, id: \.self) { Text($0).font(.subheadline) } }
                }
                if let failure { Section { Text(failure).foregroundStyle(.orange) } }
            }
            .navigationTitle("Review changes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reviewing = false }.disabled(busy).accessibilityIdentifier("relation.definition.review.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() }
                    else { Button(plan?.removing == true ? "Delete relation" : "Save changes", role: plan?.removing == true ? .destructive : nil) { commit() }.accessibilityIdentifier("relation.definition.confirm") }
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }
    private func reload() async {
        busy = true
        defer { busy = false }
        do {
            let snapshot = try await vault.relationDefinitionSnapshot()
            if let originalName {
                guard let definition = try snapshot.schema.definitions(owner: owner).first(where: { $0.id == originalName.lowercased() }), definition.type != .unsupported else { throw VaultFailure(message: "This relation changed. Reopen folder properties.") }
                originalType = definition.type; type = .relation
                options = definition.options; listMultiple = definition.multiple
                name = definition.name; target = definition.relationTypeKey ?? ""; multiple = definition.relationMultiple
                inverseHidden = definition.relationInverseHidden; hidden = definition.hidden
            }
            self.snapshot = snapshot; failure = nil; plan = nil
        } catch { snapshot = nil; failure = error.localizedDescription }
    }
    private func prepare(removing: Bool) {
        guard let snapshot else { return }
        editingName = false; addChoice()
        let definition = NativePropertyDefinition(name: name.trimmingCharacters(in: .whitespacesAndNewlines), type: type, owner: owner, options: options, multiple: listMultiple, hidden: hidden, relationTypeKey: target.isEmpty ? nil : target, relationMultiple: multiple, relationInverseHidden: inverseHidden)
        busy = true; failure = nil
        Task {
            defer { busy = false }
            do {
                let originalName = originalName, owner = owner
                let plan = try await Task.detached { try snapshot.plan(owner: owner, originalName: originalName, definition: removing ? nil : definition) }.value
                if !plan.hasChanges { dismiss() }
                else { self.plan = plan; reviewing = true }
            } catch { failure = error.localizedDescription }
        }
    }
    private func addChoice() {
        let value = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && !options.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { options.append(value) }
        choice = ""
    }
    private func commit() {
        guard let plan else { return }
        busy = true; failure = nil
        Task {
            defer { busy = false }
            do { try await vault.saveRelationDefinition(plan); reviewing = false; dismiss() }
            catch { failure = error.localizedDescription }
        }
    }
}
