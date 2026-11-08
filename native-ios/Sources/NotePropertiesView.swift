import SwiftUI

struct NativePropertyEdit: Identifiable {
    let id = UUID()
    let definition: NativePropertyDefinition?
    let name: String
    let value: NativePropertyValue?
    let save: (String, NativePropertyValue?) throws -> Void
}

struct NativePropertiesSection: View {
    @EnvironmentObject private var vault: VaultStore
    @ObservedObject var session: NoteSession
    @Binding var editing: NativePropertyEdit?
    let editRelation: (NativePropertyDefinition) -> Void
    let openRelated: (NoteDocument) -> Void
    @State private var definitions: [NativePropertyDefinition] = []
    @State private var loadError: String?
    @State private var loaded = false
    private var frontmatter: NativeFrontmatter { NativeFrontmatter(session.document.content) }
    private var properties: [NativePropertyDefinition] {
        var result = definitions
        for entry in frontmatter.entries where !result.contains(where: { $0.id == entry.id }) {
            result.append(NativePropertyDefinition(name: entry.key, type: .inferred(entry.value)))
        }
        return result.filter { !$0.hidden && !$0.name.lowercased().hasPrefix("zerus-") }
    }
    var body: some View {
        Section {
            if let loadError { Label(loadError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary) }
            ForEach(properties) { definition in
                let entry = frontmatter.entry(definition.name)
                if definition.type == .unsupported || (entry != nil && entry?.value == nil) {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(definition.name, value: entry == nil ? "Empty" : entry?.value?.display ?? "Preserved YAML")
                        Text(definition.type == .unsupported ? "This property type is preserved without changes." : "Complex or duplicate YAML is preserved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if definition.type == .relation {
                    Button { editRelation(definition) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(definition.name).foregroundStyle(.primary)
                                Text("Relation · " + (definition.relationTypeKey?.isEmpty == false ? definition.relationTypeKey! : "Any folder")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Text(relationLabels(entry?.value).nilIfEmpty ?? "Empty").foregroundStyle(Accent.relation).lineLimit(2).multilineTextAlignment(.trailing)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("property." + definition.id).disabled(!loaded || loadError != nil)
                    .contextMenu {
                        ForEach(relationTargets(entry?.value)) { target in Button("Open " + target.title, systemImage: "arrow.up.right") { openRelated(target) } }
                    }
                } else {
                    Button {
                        editing = edit(definition: definitions.first { $0.id == definition.id }, name: definition.name, value: entry?.value)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(definition.name).foregroundStyle(Color.primary)
                                if definitions.contains(where: { $0.id == definition.id }) {
                                    Text(definition.type.label + " · " + (definition.owner.isEmpty ? "Inbox" : definition.owner))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 12)
                            if case .checkbox(let checked) = entry?.value {
                                Image(systemName: checked ? "checkmark.circle.fill" : "circle").foregroundStyle(checked ? Color.accentColor : Color.secondary)
                                    .accessibilityLabel(checked ? "Checked" : "Unchecked")
                            } else {
                                if definition.type == .date, let day = entry?.value?.display.nilIfEmpty {
                                    NativeDateText(day: day).foregroundStyle(Color.secondary).lineLimit(2).multilineTextAlignment(.trailing)
                                } else {
                                    Text(entry?.value?.display.nilIfEmpty ?? "Empty").foregroundStyle(Color.secondary).lineLimit(2).multilineTextAlignment(.trailing)
                                }
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("property." + definition.id).disabled(!loaded || loadError != nil)
                }
            }
            Button("Add property", systemImage: "plus") { editing = edit(definition: nil, name: "", value: nil) }
                .accessibilityIdentifier("property.add").disabled(!loaded || loadError != nil)
            if session.dirty || session.failure != nil {
                Text(session.failure ?? "Saving properties…").font(.caption).foregroundStyle(session.failure == nil ? Color.secondary : .orange)
            }
            if !frontmatter.header.isEmpty {
                DisclosureGroup("Original metadata") { Text(frontmatter.header).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            }
        } header: { Text("Properties") } footer: { Text("Values are saved in this note. Folder definitions are shared with the desktop app.") }
        .task(id: session.document.path + "|" + String(vault.schemaRevision)) {
            loaded = false
            do { definitions = try await vault.propertyDefinitions(notePath: session.document.path, workspace: session.document.workspaceID); loadError = nil; loaded = true }
            catch { loadError = error.localizedDescription }
        }
    }
    private func relationTargets(_ value: NativePropertyValue?) -> [NoteDocument] {
        let ids = Set((value?.selections ?? []).compactMap { NoteReference(wikilink: "[[" + $0 + "]]") }.flatMap { vault.targets(for: $0) }.map(\.id))
        return vault.notes.filter { ids.contains($0.id) && !$0.trashed }
    }
    private func relationLabels(_ value: NativePropertyValue?) -> String {
        (value?.selections ?? []).map { raw in
            guard let link = NoteReference(wikilink: "[[" + raw + "]]") else { return raw }
            let targets = vault.targets(for: link)
            return targets.count == 1 ? targets[0].title : link.explicitLabel ? link.label : link.target.hasPrefix("zerus:") ? "Missing note" : link.label
        }.joined(separator: ", ")
    }
    private func edit(definition: NativePropertyDefinition?, name originalName: String, value originalValue: NativePropertyValue?) -> NativePropertyEdit {
        NativePropertyEdit(definition: definition, name: originalName, value: originalValue) { name, value in
            let current = NativeFrontmatter(session.document.content)
            guard !name.lowercased().hasPrefix("zerus-") else { throw VaultFailure(message: "Zerus manages this property automatically.") }
            if originalName.isEmpty {
                guard current.entry(name) == nil, !definitions.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw VaultFailure(message: "That property already exists. Edit its existing row.") }
            } else if current.entry(name)?.value != originalValue { throw VaultFailure(message: "This property changed while you were editing. Reopen it to use the latest value.") }
            session.updateContent(try current.setting(name, value: value))
            Task { await session.save() }
        }
    }
}

struct NativePropertyEditor: View {
    @Environment(\.dismiss) private var dismiss
    let edit: NativePropertyEdit
    let save: (String, NativePropertyValue?) throws -> Void
    @State private var name: String
    @State private var type: NativePropertyType
    @State private var text: String
    @State private var checked: Bool
    @State private var selections: [String]
    @State private var option = ""
    @State private var date: Date
    @State private var failure: String?
    @State private var confirmRemoval = false
    init(edit: NativePropertyEdit, save: @escaping (String, NativePropertyValue?) throws -> Void) {
        self.edit = edit; self.save = save
        _name = State(initialValue: edit.name)
        _type = State(initialValue: edit.definition?.type ?? .inferred(edit.value))
        _text = State(initialValue: edit.value?.display ?? "")
        _checked = State(initialValue: edit.value == .checkbox(true))
        _selections = State(initialValue: edit.value?.selections ?? [])
        _date = State(initialValue: Self.dateFormatter.date(from: edit.value?.display ?? "") ?? Date())
    }
    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter
    }
    private var multiple: Bool { edit.definition?.multiple ?? true }
    private var options: [String] {
        var values: [String] = []
        for item in (edit.definition?.options ?? []) + selections where !values.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) { values.append(item) }
        return values
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if edit.name.isEmpty { TextField("Name", text: $name).accessibilityIdentifier("property.name").textInputAutocapitalization(.sentences) }
                    else { LabeledContent("Name", value: name) }
                    if edit.definition == nil {
                        Picker("Type", selection: $type) { ForEach(NativePropertyType.allCases.filter { $0 != .relation && $0 != .unsupported }) { Text($0.label).tag($0) } }.accessibilityIdentifier("property.type")
                    } else { LabeledContent("Type", value: type.label) }
                }
                Section(type == .list ? "Choices" : "Value") {
                    switch type {
                    case .checkbox: Toggle("Checked", isOn: $checked).accessibilityIdentifier("property.checked")
                    case .date: DatePicker("Date", selection: $date, displayedComponents: .date).accessibilityIdentifier("property.date")
                    case .list:
                        ForEach(options, id: \.self) { choice in
                            Button {
                                if isSelected(choice) { selections.removeAll { $0.caseInsensitiveCompare(choice) == .orderedSame } }
                                else if multiple { selections.append(choice) }
                                else { selections = [choice] }
                            } label: {
                                HStack { Text(choice).foregroundStyle(.primary); Spacer(); if isSelected(choice) { Image(systemName: "checkmark") } }
                            }.accessibilityAddTraits(isSelected(choice) ? .isSelected : [])
                        }
                        HStack {
                            TextField("New choice", text: $option).accessibilityIdentifier("property.choice")
                            Button("Add") { addChoice() }.disabled(option.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("property.choice.add")
                        }
                    case .number:
                        TextField("Number", text: $text).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("property.value")
                    case .url:
                        TextField("https://example.com", text: $text, axis: .vertical).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("property.value")
                    default: TextField("Value", text: $text, axis: .vertical).lineLimit(2...8).accessibilityIdentifier("property.value")
                    }
                }
                if let failure { Section { Text(failure).foregroundStyle(.red).accessibilityIdentifier("property.error") } }
                if !edit.name.isEmpty, edit.value != nil {
                    Section { Button("Remove value", role: .destructive) { confirmRemoval = true } }
                }
            }
            .navigationTitle(edit.name.isEmpty ? "New property" : name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { commit() }.accessibilityIdentifier("property.save") }
            }
            .confirmationDialog("Remove this note’s value?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("Remove value", role: .destructive) { do { try save(name, nil); dismiss() } catch { failure = error.localizedDescription } }
            } message: { Text("The folder’s property definition will stay available.") }
        }
    }
    private func addChoice() {
        let value = option.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !selections.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            if multiple { selections.append(value) } else { selections = [value] }
        }
        option = ""
    }
    private func isSelected(_ choice: String) -> Bool {
        selections.contains { $0.caseInsensitiveCompare(choice) == .orderedSame }
    }
    private func commit() {
        do {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value: NativePropertyValue
            switch type {
            case .number: value = .number(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case .checkbox: value = .checkbox(checked)
            case .date: value = .text(Self.dateFormatter.string(from: date))
            case .list:
                addChoice(); value = multiple ? .list(selections) : .text(selections.first ?? "")
            case .url:
                let url = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard url.isEmpty || URL(string: url)?.scheme != nil else { throw VaultFailure(message: "Enter a complete URL, including its scheme, such as https://.") }
                value = .text(url)
            default: value = .text(text)
            }
            try save(key, value); dismiss()
        } catch { failure = error.localizedDescription }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
