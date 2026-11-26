import SwiftUI

struct MacSchemaChoice: Identifiable {
    let id = UUID()
    var value: String
}
struct MacSchemaForm {
    var name: String
    var kind: NativePropertyType
    var choices: [MacSchemaChoice]
    var multiple: Bool
    var target: String
    var hidden: Bool
    var inverseHidden: Bool
    init(_ definition: NativePropertyDefinition? = nil) {
        name = definition?.name ?? ""; kind = definition?.type ?? .text
        choices = (definition?.options.isEmpty == false ? definition!.options : [""]).map { .init(value: $0) }
        multiple = definition.map { $0.type == .relation ? $0.relationMultiple : $0.multiple } ?? false
        target = definition?.relationTypeKey ?? ""; hidden = definition?.hidden ?? false; inverseHidden = definition?.relationInverseHidden ?? false
    }
    func definition(owner: String) throws -> NativePropertyDefinition {
        let value = NativePropertyDefinition(name: name, type: kind, owner: owner, options: choices.map(\.value), multiple: multiple,
            hidden: hidden, relationTypeKey: target, relationMultiple: multiple, relationInverseHidden: inverseHidden)
        return try kind == .relation ? value.validatedRelation() : value.validated()
    }
}
struct MacSchemaReview: Identifiable, Sendable {
    var id: UUID { plan.id }
    let plan: NativeRelationMaintenancePlan
    let owner: String
    let originalName: String?
    let definition: NativePropertyDefinition?
    let summaries: [String]
    var noteChanges: [VaultFileChange] { plan.changes.filter { $0.path.lowercased().hasSuffix(".md") && $0.before != $0.after } }
    var title: String { definition == nil ? "Remove folder property" : originalName == nil ? "Add folder property" : originalName != definition?.name ? "Rename folder property" : "Update folder property" }
}

extension VaultFiles {
    func macSchemaDefinitionSnapshot(workspaceID: UUID) throws -> NativeRelationDefinitionSnapshot {
        let raw = try relationDefinitionSnapshot(); var schema = raw.schema; schema.workspaceID = workspaceID
        return .init(schema: schema, notes: raw.notes)
    }
    func prepareMacSchemaReview(_ snapshot: NativeRelationDefinitionSnapshot, owner: String, originalName: String?, definition: NativePropertyDefinition?) throws -> MacSchemaReview {
        guard snapshot.schema.root == root else { throw VaultFailure(message: "The vault changed. Reopen folder properties.") }
        let owned = try snapshot.schema.definitions(owner: owner)
        guard Set(owned.map(\.id)).count == owned.count else { throw VaultFailure(message: "This folder has duplicate definition names. Resolve them before editing properties.") }
        let original = owned.first { $0.name.caseInsensitiveCompare(originalName ?? "") == .orderedSame }
        let changes: [VaultFileChange]
        if original?.type == .relation || definition?.type == .relation {
            changes = try snapshot.plan(owner: owner, originalName: originalName, definition: definition).changes
        } else {
            let unchanged = original.map { old in definition.map { next in old.name == next.name && old.type == next.type && (next.type != .list || old.options == next.options && old.multiple == next.multiple) } ?? false } ?? false
            var prepared = unchanged ? [VaultFileChange(path: ".zerus/properties.json", before: snapshot.schema.bytes, after: snapshot.schema.bytes)] : try snapshot.schema.changes(owner: owner, originalName: originalName, definition: definition, notes: snapshot.notes)
            let covered = Set(prepared.map(\.path))
            // Keep currently empty values in the reviewed folder frozen too:
            // a later value must not silently escape a removal or conversion.
            for note in snapshot.notes where !note.trashed && !note.path.hasPrefix(".zerus/") && !covered.contains(note.path) && (owner.isEmpty ? !note.path.contains("/") : note.path.hasPrefix(owner + "/")) {
                let bytes = Data(note.content.utf8); prepared.append(.init(path: note.path, before: bytes, after: bytes))
            }
            changes = prepared
        }
        let updated = NativeSchemaSnapshot(root: root, bytes: changes.first { $0.path == ".zerus/properties.json" }?.after ?? snapshot.schema.bytes)
        func detail(_ value: NativePropertyDefinition) -> String {
            var parts = [value.type.label]
            if value.type == .list { parts += [value.options.map { "“" + $0 + "”" }.joined(separator: ", "), value.multiple ? "multiple choices" : "single choice"] }
            if value.type == .relation { parts += [(value.relationTypeKey?.isEmpty == false ? value.relationTypeKey! : "any folder"), value.relationMultiple ? "multiple notes" : "one note", value.hidden ? "hidden" : "visible", value.relationInverseHidden ? "inverse hidden" : "inverse visible"] }
            return parts.joined(separator: " · ")
        }
        var summaries: [String] = []
        for folder in Set(snapshot.schema.owners + updated.owners).sorted() {
            let before = try snapshot.schema.definitions(owner: folder), after = try updated.definitions(owner: folder)
            for id in Set(before.map(\.id) + after.map(\.id)).sorted() {
                let old = before.first { $0.id == id }, new = after.first { $0.id == id }, location = folder.isEmpty ? "Vault root" : folder
                if let old, new == nil { summaries.append("Remove \(location) · \(old.name) (\(detail(old)))") }
                else if let new, old == nil { summaries.append("Add \(location) · \(new.name): \(detail(new))") }
                else if let old, let new, old.name != new.name || detail(old) != detail(new) || old.relationPairID != new.relationPairID { summaries.append("Update \(location) · \(new.name): \(detail(old)) → \(detail(new))") }
            }
        }
        let plan = NativeRelationMaintenancePlan(snapshot: snapshot, changes: changes, sourcePath: nil, destination: nil, summaries: summaries, issues: [])
        return .init(plan: plan, owner: owner, originalName: originalName, definition: definition, summaries: summaries)
    }
}

extension MacWorkspace {
    func schemaDefinitionSnapshot() async throws -> NativeRelationDefinitionSnapshot {
        let origin = workspaceID
        guard !busy, !schemaMaintenanceSaving, await save(), let io, origin == workspaceID else { throw VaultFailure(message: "Save open changes before loading folder properties.") }
        let snapshot = try await io.macSchemaDefinitionSnapshot(workspaceID: origin)
        guard origin == workspaceID else { throw VaultFailure(message: "The vault changed. Reopen folder properties.") }
        return snapshot
    }
    func prepareSchemaReview(_ snapshot: NativeRelationDefinitionSnapshot, owner: String, originalName: String?, definition: NativePropertyDefinition?) async throws -> MacSchemaReview {
        guard snapshot.schema.workspaceID == workspaceID, !schemaMaintenanceSaving, let io else { throw VaultFailure(message: "The vault changed. Reopen folder properties.") }
        let review = try await io.prepareMacSchemaReview(snapshot, owner: owner, originalName: originalName, definition: definition)
        guard snapshot.schema.workspaceID == workspaceID else { throw VaultFailure(message: "The vault changed. Reopen folder properties.") }
        return review
    }
}

struct MacSchemaReviewView: View {
    @Bindable var store: MacWorkspace
    let review: MacSchemaReview
    var saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(review.title).macFont(.title2.bold()); Spacer(); Button("Cancel") { dismiss() }.disabled(busy).keyboardShortcut(.cancelAction) }
            Text(review.definition == nil ? "Review the definition and stored values that will be removed. Paired relations are updated together; an inherited definition can keep a value in place." : "Review folder definitions and note values before applying. Paired relations are updated together.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if review.summaries.isEmpty { Text("No definition changes.").foregroundStyle(.secondary) }
                    ForEach(Array(review.summaries.enumerated()), id: \.offset) { _, text in Text(text).textSelection(.enabled) }
                    if !review.noteChanges.isEmpty {
                        Divider(); Text("Notes with value changes (\(review.noteChanges.count))").macFont(.headline)
                        ForEach(review.noteChanges, id: \.path) { change in
                            DisclosureGroup(change.path) { MacHistoryDifferenceView(before: change.before.map { String(decoding: $0, as: UTF8.self) } ?? "", after: change.after.map { String(decoding: $0, as: UTF8.self) } ?? "") }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 120, maxHeight: 400)
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack { if busy { ProgressView().controlSize(.small) }; Spacer(); Button(review.definition == nil ? "Remove reviewed property" : "Apply reviewed changes", role: review.definition == nil ? .destructive : nil) { commit() }.buttonStyle(.borderedProminent).disabled(busy || !review.plan.hasChanges) }
        }.padding(24).frame(width: 720).interactiveDismissDisabled(busy)
    }
    private func commit() {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await store.commitSchemaMaintenance(review.plan); saved(); dismiss() } catch { issue = error.localizedDescription } }
    }
}
