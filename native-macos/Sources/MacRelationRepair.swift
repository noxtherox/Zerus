import SwiftUI

extension VaultFiles {
    func prepareMacRelationRepair(workspaceID: UUID) throws -> NativeRelationMaintenancePlan {
        let raw = try relationDefinitionSnapshot()
        var schema = raw.schema; schema.workspaceID = workspaceID
        return try NativeRelationDefinitionSnapshot(schema: schema, notes: raw.notes).repairPlan()
    }
    func applyMacSchemaMaintenance(_ plan: NativeRelationMaintenancePlan) throws -> VaultSnapshot {
        let paths = plan.changes.filter { $0.path.lowercased().hasSuffix(".md") }.map(\.path), root = self.root
        return try applyRelationChanges(schema: plan.snapshot.schema, notes: plan.snapshot.notes, changes: plan.changes) {
            if let path = try MacNoteRecoveryStore.firstRetained(root: root, paths: paths) {
                throw VaultFailure(message: "A retained draft exists for \(path). Resolve or export it before changing folder definitions.")
            }
        }
    }
}

extension MacWorkspace {
    func prepareRelationRepair() async throws -> NativeRelationMaintenancePlan {
        let origin = workspaceID
        guard !busy, !schemaMaintenanceSaving, !noteMovesSaving, !imageSaving, !externalCopySaving, !preparingToClose,
              await save(), let io, origin == workspaceID else { throw VaultFailure(message: "Save the current note and finish other changes before reviewing relations.") }
        let plan = try await io.prepareMacRelationRepair(workspaceID: origin)
        guard origin == workspaceID, !isDirty else { throw VaultFailure(message: "The note or vault changed. Review relations again.") }
        return plan
    }
    func commitSchemaMaintenance(_ plan: NativeRelationMaintenancePlan) async throws {
        guard let io, plan.snapshot.schema.workspaceID == workspaceID, plan.snapshot.schema.root == root,
              plan.sourcePath == nil, plan.destination == nil else { throw VaultFailure(message: "The vault changed. Review these changes again.") }
        let rootPath = root?.resolvingSymlinksInPath().standardizedFileURL.path
        let peers = Self.windows.compactMap(\.value).filter { $0.root?.resolvingSymlinksInPath().standardizedFileURL.path == rootPath }
        guard peers.allSatisfy({ !$0.isDirty && $0.noteDiskChange == nil && !$0.busy && !$0.schemaMaintenanceSaving && !$0.noteMovesSaving && !$0.imageSaving && !$0.externalCopySaving && !$0.recoverySaving && !$0.preparingToClose }) else {
            throw VaultFailure(message: "Save or resolve open drafts and finish other vault changes before applying these changes.")
        }
        peers.forEach { $0.schemaMaintenanceSaving = true }
        defer { peers.forEach { $0.schemaMaintenanceSaving = false } }
        let snapshot = try await io.applyMacSchemaMaintenance(plan)
        for peer in peers { await peer.adoptSchemaMaintenanceSnapshot(snapshot) }
    }
}

struct MacRelationRepairView: View {
    @Bindable var workspace: MacWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var plan: NativeRelationMaintenancePlan?
    @State private var issue: String?
    @State private var busy = false
    @State private var applied = false
    private var noteChanges: [VaultFileChange] { plan?.changes.filter { $0.path.lowercased().hasSuffix(".md") && $0.before != $0.after } ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Repair relations").macFont(.title2.bold()); Spacer(); Button(applied ? "Done" : "Cancel") { dismiss() }.disabled(busy).keyboardShortcut(.cancelAction) }
            Text("Review relation definitions left behind after notes moved between folders. Only unambiguous relations are restored; unresolved values stay unchanged.").foregroundStyle(.secondary)
            if applied { Label("Reviewed repairs saved", systemImage: "checkmark.circle").macFont(.headline) }
            if let plan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if plan.summaries.isEmpty { Text("No unambiguous repairs found.").macFont(.headline) }
                        else { ForEach(Array(plan.summaries.enumerated()), id: \.offset) { _, summary in Label(summary, systemImage: "arrow.triangle.branch") } }
                        if !noteChanges.isEmpty {
                            Divider(); Text("Affected notes (\(noteChanges.count))").macFont(.headline)
                            ForEach(noteChanges, id: \.path) { change in
                                DisclosureGroup(change.path) { MacHistoryDifferenceView(before: change.before.map { String(decoding: $0, as: UTF8.self) } ?? "", after: change.after.map { String(decoding: $0, as: UTF8.self) } ?? "") }
                            }
                        }
                        if !plan.issues.isEmpty {
                            Divider(); Text("Needs attention (\(plan.issues.count))").macFont(.headline)
                            ForEach(plan.issues) { item in
                                VStack(alignment: .leading, spacing: 4) { Text(item.name + " · " + item.path).macFont(.subheadline.bold()); Text(item.reason).macFont(.caption).foregroundStyle(.secondary) }.textSelection(.enabled)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 120, maxHeight: 410)
            }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                if !applied { Button(plan == nil ? "Review repairs" : "Review again") { prepare() }.disabled(busy) }
                if let plan, plan.hasChanges, !applied { Button("Apply reviewed repairs") { commit(plan) }.buttonStyle(.borderedProminent).disabled(busy).keyboardShortcut(.defaultAction) }
            }
        }.padding(24).frame(width: 720).interactiveDismissDisabled(busy)
        .onChange(of: workspace.workspaceID) { _, _ in plan = nil; applied = false; issue = "The vault changed. Prepare a fresh review." }
    }
    private func prepare() {
        busy = true; issue = nil
        Task { defer { busy = false }; do { plan = try await workspace.prepareRelationRepair() } catch { issue = error.localizedDescription } }
    }
    private func commit(_ plan: NativeRelationMaintenancePlan) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await workspace.commitSchemaMaintenance(plan); applied = true } catch { issue = error.localizedDescription } }
    }
}
