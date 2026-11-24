import SwiftUI

struct MacBulkEditor: View {
    @Bindable var store: MacWorkspace
    let paths: Set<String>
    @State private var snapshot: NativeBulkSnapshot?
    @State private var fields: [NativePropertyDefinition] = []
    @State private var fieldName = ""
    @State private var operation: NativeBulkOperation = .set
    @State private var text = ""
    @State private var checked = false
    @State private var dateValid = true
    @State private var choices = Set<String>()
    @State private var targets = Set<String>()
    @State private var changes: [NativeBulkPropertyChange] = []
    @State private var plan: NativeBulkPlan?
    @State private var issue: String?
    @State private var busy = false
    @State private var reviewing = false
    @Environment(\.dismiss) private var dismiss
    var field: NativePropertyDefinition? { fields.first { $0.name == fieldName } }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Update \(paths.count) notes").font(.title2.bold())
            Text("Only properties shared by every selected note are available. Relations keep their paired links synchronized.").font(.caption).foregroundStyle(.secondary)
            if fields.isEmpty && snapshot != nil { Text("These notes have no shared editable property definitions. Add folder definitions first.").foregroundStyle(.secondary) }
            else {
                Picker("Property", selection: $fieldName) { Text("Choose property").tag(""); ForEach(fields) { Text($0.name).tag($0.name) } }
                if let field {
                    Picker("Action", selection: $operation) { ForEach(NativeBulkOperation.allCases.filter { $0 == .set || $0 == .clear || field.multiple || field.relationMultiple }) { Text($0.rawValue).tag($0) } }
                    if operation != .clear {
                        if field.type == .checkbox { Toggle("Checked", isOn: $checked) }
                        else if field.type == .list {
                            ScrollView { VStack(alignment: .leading) { ForEach(field.options, id: \.self) { option in Toggle(option, isOn: Binding(get: { choices.contains(option) }, set: { selected in if selected { if !field.multiple { choices = [] }; choices.insert(option) } else { choices.remove(option) } })) } } }.frame(maxHeight: 150)
                        } else if field.type == .relation {
                            ScrollView { LazyVStack(alignment: .leading) { ForEach(store.regularNotes.filter { !paths.contains($0.path) && NativeRelationSnapshot.eligible($0, for: field) }) { note in Toggle(note.title, isOn: Binding(get: { targets.contains(note.path) }, set: { selected in if selected { if !field.relationMultiple { targets = [] }; targets.insert(note.path) } else { targets.remove(note.path) } })) } } }.frame(height: 170)
                        } else if field.type == .date { MacDateField("Date", value: $text, valid: $dateValid, allowEmpty: false).id(field.id) }
                        else { TextField("Value", text: $text) }
                    }
                    Button("Add change") { addChange(field) }.disabled(operation != .clear && field.type == .date && !dateValid)
                }
            }
            if !changes.isEmpty {
                Divider()
                ForEach(changes) { change in HStack { Text(change.name).fontWeight(.medium); Text(change.operation.rawValue).foregroundStyle(.secondary); Spacer(); Button { changes.removeAll { $0.id == change.id } } label: { Image(systemName: "xmark.circle") }.buttonStyle(MacBoxButtonStyle()).help("Remove change") }.font(.caption) }
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
            HStack { if busy { ProgressView().controlSize(.small) }; Spacer(); Button("Cancel") { dismiss() }; Button("Review changes") { prepare() }.disabled(changes.isEmpty || busy) }
        }.padding(24).frame(width: 540).task { await load() }.onChange(of: fieldName) { _, _ in operation = .set; text = ""; choices = []; targets = []; checked = false }
        .confirmationDialog("Apply property changes?", isPresented: $reviewing) {
            if plan?.hasChanges == true { Button("Apply changes") { Task { await commit() } } }
            else { Button("Close", role: .cancel) {} }
        } message: {
            Text("Updates \(plan?.changedNotes.count ?? 0) notes:\n" + (plan?.changedNotes.joined(separator: "\n") ?? "") + (plan?.issues.isEmpty == false ? "\n\nSkipped:\n" + plan!.issues.map { $0.path + ": " + $0.reason }.joined(separator: "\n") : ""))
        }
    }
    private func load() async {
        guard store.io != nil else { return }
        do { let value = try await store.bulkReviewSnapshot(); snapshot = value; fields = try value.commonProperties(value.source.notes.filter { paths.contains($0.path) }) }
        catch { issue = error.localizedDescription }
    }
    private func addChange(_ field: NativePropertyDefinition) {
        guard operation == .clear || field.type != .date || dateValid else { issue = "Correct the date before adding this change."; return }
        do {
            var value: NativePropertyValue?
            if operation != .clear {
                switch field.type {
                case .checkbox: value = .checkbox(checked)
                case .number: guard Double(text) != nil else { throw VaultFailure(message: "Enter a number.") }; value = .number(text)
                case .list: value = field.multiple ? .list(choices.sorted()) : choices.first.map(NativePropertyValue.text)
                case .relation:
                    let references = targets.sorted().compactMap { path in store.notes.first { $0.path == path }.map { note in (note.stableID.map { "zerus:" + $0 } ?? note.path) + "|" + note.title } }
                    value = field.relationMultiple ? .list(references) : references.first.map(NativePropertyValue.text)
                default: value = .text(text)
                }
                guard let value else { throw VaultFailure(message: "Choose a value first.") }; try field.validateValue(value)
            }
            let change = NativeBulkPropertyChange(name: field.name, operation: operation, value: value)
            changes.removeAll { $0.id == change.id }; changes.append(change); issue = nil
        } catch { issue = error.localizedDescription }
    }
    private func prepare() {
        guard let snapshot else { return }
        do { plan = try snapshot.plan(selected: snapshot.source.notes.filter { paths.contains($0.path) }, mutation: .init(properties: changes)); reviewing = true }
        catch { issue = error.localizedDescription }
    }
    private func commit() async {
        guard let plan else { return }; busy = true; defer { busy = false }
        do { try await store.commitBulk(plan); dismiss() } catch { issue = error.localizedDescription }
    }
}

struct MacBulkHistoryView: View {
    @Bindable var store: MacWorkspace
    @State private var snapshot: NativeBulkSnapshot?
    @State private var moveRecords: [MacNoteMoveRecord] = []
    @State private var moveHistoryReview: MacNoteMoveHistoryReview?
    @State private var plan: NativeBulkPlan?
    @State private var reviewing = false
    @State private var issue: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Organization history").font(.title2.bold()); Spacer(); Button("Refresh") { Task { await load() } }; Button("Done") { dismiss() } }
            Text("Review Undo and Redo for note moves, pin, archive and property changes. Later changes to affected notes, settings or incoming references can block older move receipts. Unrelated notes are preserved.").font(.caption).foregroundStyle(.secondary)
            if !moveRecords.isEmpty {
                Text("Note moves").font(.headline)
                ScrollView { VStack(alignment: .leading, spacing: 10) { ForEach(moveRecords) { record in
                    HStack { VStack(alignment: .leading, spacing: 3) { Text("\(record.moves.count) notes moved"); Text(record.date, format: .dateTime).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(record.undone ? "Review move Redo" : "Review move Undo") { prepareMoveHistory(record) } }
                } } }.frame(maxHeight: 140).disabled(busy)
            }
            List(snapshot?.records ?? []) { record in
                HStack { VStack(alignment: .leading, spacing: 4) { Text(record.label); Text(record.date, format: .dateTime).font(.caption).foregroundStyle(.secondary); Text(record.status).font(.caption2).foregroundStyle(.tertiary) }; Spacer(); Button(record.appliedCount == 0 ? "Review redo" : "Review undo") { prepare(record, undo: record.appliedCount > 0) } }
            }.disabled(busy)
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
        }.padding(24).frame(width: 680, height: 470).task { await load() }
        .macSheet(item: $moveHistoryReview) { review in MacNoteMoveHistoryView(workspace: store, review: review) { Task { await load() } } }
        .confirmationDialog(plan?.label ?? "Apply change?", isPresented: $reviewing) {
            if plan?.hasChanges == true { Button("Apply") { Task { await commit() } } }
            else { Button("Close", role: .cancel) {} }
        } message: { Text((plan?.changedNotes.joined(separator: "\n") ?? "") + (plan?.issues.isEmpty == false ? "\n\nSkipped:\n" + plan!.issues.map { $0.path + ": " + $0.reason }.joined(separator: "\n") : "")) }
    }
    private func load() async {
        guard let io = store.io else { return }
        let origin = store.workspaceID
        do {
            let bulk = try await store.bulkReviewSnapshot(), moves = try await io.macNoteMoveHistory()
            guard origin == store.workspaceID, !Task.isCancelled else { return }
            snapshot = bulk; moveRecords = moves.records
            issue = moves.issues.isEmpty ? nil : moves.issues.joined(separator: "\n")
        } catch { if origin == store.workspaceID, !Task.isCancelled { issue = error.localizedDescription } }
    }
    private func prepareMoveHistory(_ record: MacNoteMoveRecord) { busy = true; issue = nil; Task { defer { busy = false }; do { moveHistoryReview = try await store.prepareNoteMoveHistory(record.id, undo: !record.undone) } catch { issue = error.localizedDescription } } }
    private func prepare(_ record: NativeBulkRecord, undo: Bool) { do { plan = try snapshot?.transition(record.id, undo: undo); reviewing = plan != nil } catch { issue = error.localizedDescription } }
    private func commit() async { guard let plan else { return }; busy = true; defer { busy = false }; do { try await store.commitBulk(plan); await load() } catch { issue = error.localizedDescription } }
}
