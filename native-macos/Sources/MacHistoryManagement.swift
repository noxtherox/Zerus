import SwiftUI

/// Mac drafts live outside the portable vault and the shared iOS draft folder.
/// Capture their bytes for both resource protection and stale-review validation.
enum MacHistoryDrafts {
    static func capture() throws -> [String: Data] {
        try VaultFiles.historyRecoveryDrafts().filter { $0.key.hasPrefix("/") }
    }
}
struct MacHistoryManagementSnapshot: Sendable {
    let workspaceID: UUID
    let history: NativeHistoryMaintenanceSnapshot
    let drafts: [String: Data]
}
struct MacHistoryManagementReview: Identifiable, Sendable {
    let id = UUID()
    let workspaceID: UUID
    let plan: NativeHistoryMaintenancePlan
    let drafts: [String: Data]
    var deletes: Bool { !plan.removedRecords.isEmpty || !plan.removedBlobs.isEmpty }
    var hasChanges: Bool { plan.changes.contains { $0.before != $0.after } }
}
extension VaultFiles {
    func macHistoryManagementSnapshot(workspaceID: UUID) throws -> MacHistoryManagementSnapshot {
        .init(workspaceID: workspaceID, history: try historyMaintenanceSnapshot(), drafts: try MacHistoryDrafts.capture())
    }
    func prepareMacHistoryManagement(_ snapshot: MacHistoryManagementSnapshot, intent: NativeHistoryMaintenanceIntent) throws -> MacHistoryManagementReview {
        guard try MacHistoryDrafts.capture() == snapshot.drafts else { throw VaultFailure(message: "Mac recovery drafts changed. Refresh the history review.") }
        let plan = try prepareHistoryMaintenance(snapshot.history, intent: intent)
        let strings = snapshot.drafts.values.compactMap { NoteDocument.decodeUTF8($0) }
        let opaque = strings.count != snapshot.drafts.count
        let collects: Bool
        if case .settings = intent { collects = !plan.removedRecords.isEmpty } else { collects = true }
        let protected = Set((collects ? Array(snapshot.history.inventory.blobs) : []).filter { path in opaque || strings.contains { $0.contains((path as NSString).lastPathComponent) } })
        let changes = plan.changes.map { protected.contains($0.path) ? VaultFileChange(path: $0.path, before: $0.before, after: $0.before) : $0 }
        var warnings = plan.warnings
        if !protected.isEmpty { warnings.append("\(protected.count) history image " + (protected.count == 1 ? "file remains" : "files remain") + " protected by Mac recovery drafts.") }
        if opaque { warnings.append("An unreadable Mac recovery draft keeps all history images protected.") }
        let revised = NativeHistoryMaintenancePlan(snapshot: plan.snapshot, intent: plan.intent, changes: changes, removedRecords: plan.removedRecords, removedBlobs: plan.removedBlobs.filter { !protected.contains($0) }, warnings: warnings)
        return .init(workspaceID: snapshot.workspaceID, plan: revised, drafts: snapshot.drafts)
    }
    func applyMacHistoryManagement(_ review: MacHistoryManagementReview) throws -> VaultSnapshot {
        guard review.plan.snapshot.root == root else { throw VaultFailure(message: "The vault changed. Reopen history settings.") }
        try Self.validateHistoryMaintenance(review.plan.snapshot)
        let expected = review.drafts
        try applyTransaction(review.plan.changes, historyCleanupSnapshot: review.plan.snapshot) {
            guard try MacHistoryDrafts.capture() == expected else { throw VaultFailure(message: "Mac recovery drafts changed after review. No history files were removed; refresh the review.") }
        }
        forgetExternalHistory(review.plan.intent)
        return try scan()
    }
}
extension MacWorkspace {
    private func checkHistoryManagement(_ expected: UUID) throws {
        guard workspaceID == expected, root != nil, !isDirty, !recoverySaving, !imageSaving, !noteMovesSaving else { throw VaultFailure(message: "The note or vault changed, or another file change is saving. Reopen history settings.") }
    }
    func historyManagementSnapshot(workspaceID expected: UUID) async throws -> MacHistoryManagementSnapshot {
        guard expected == workspaceID, await save(), let io else { throw VaultFailure(message: "Save the note or reopen history settings in its original vault.") }
        try checkHistoryManagement(expected)
        let snapshot = try await io.macHistoryManagementSnapshot(workspaceID: expected)
        try checkHistoryManagement(expected); return snapshot
    }
    func prepareHistoryManagement(_ snapshot: MacHistoryManagementSnapshot, intent: NativeHistoryMaintenanceIntent) async throws -> MacHistoryManagementReview {
        try checkHistoryManagement(snapshot.workspaceID)
        guard let io else { throw VaultFailure(message: "Open a vault first.") }
        let review = try await io.prepareMacHistoryManagement(snapshot, intent: intent)
        try checkHistoryManagement(snapshot.workspaceID); return review
    }
    func commitHistoryManagement(_ review: MacHistoryManagementReview) async throws {
        try checkHistoryManagement(review.workspaceID)
        guard let io else { throw VaultFailure(message: "Open a vault first.") }
        recoverySaving = true; defer { recoverySaving = false }
        let result = try await io.applyMacHistoryManagement(review)
        guard review.workspaceID == workspaceID else { throw CancellationError() }
        apply(result); await loadInspector()
    }
    func saveHistoryAnnotation(_ snapshot: MacRecoverySnapshot, id: String, kept: Bool, label: String) async throws {
        guard let history = snapshot.history else { throw VaultFailure(message: snapshot.historyIssue ?? "Automatic history is unavailable. Refresh recovery.") }
        try checkHistoryManagement(snapshot.workspaceID)
        guard let io else { throw VaultFailure(message: "Open a vault first.") }
        recoverySaving = true; defer { recoverySaving = false }
        let plan = try await io.prepareHistory(history, action: .update(id, kept: kept, label: label))
        guard workspaceID == snapshot.workspaceID, !isDirty else { throw VaultFailure(message: "The note or vault changed. Reload the saved version before editing its label.") }
        let result = try await io.applyHistory(plan)
        guard workspaceID == snapshot.workspaceID else { throw CancellationError() }
        apply(result)
        await loadInspector()
    }
}
