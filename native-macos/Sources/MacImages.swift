import SwiftUI

struct MacImageReview: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let plan: NativeImagePlan
}

extension MacWorkspace {
    func imageSnapshot(workspaceID expected: UUID) async throws -> NativeImageSnapshot {
        guard expected == workspaceID, !imageSaving, await save(), expected == workspaceID, let io, !isDirty else { throw VaultFailure(message: "Save the note or reopen Images in its original vault.") }
        var snapshot = try await io.imageSnapshot()
        guard expected == workspaceID, !isDirty else { throw VaultFailure(message: "The note or vault changed. Refresh Images.") }
        snapshot.workspaceID = expected
        return snapshot
    }
    /// The deleted-image list alone, without the vault-wide reference check.
    func imageTrashIndex(workspaceID expected: UUID) async throws -> NativeImageTrashIndex {
        guard expected == workspaceID, let io else { throw VaultFailure(message: "Reopen Images in its original vault.") }
        let index = try await io.imageTrashIndex()
        guard expected == workspaceID else { throw CancellationError() }
        return index
    }
    func prepareImageChange(_ snapshot: NativeImageSnapshot, action: NativeImageChange) async throws -> MacImageReview {
        guard snapshot.workspaceID == workspaceID, snapshot.root == root, let io, !imageSaving, !isDirty else { throw VaultFailure(message: "The note or vault changed. Refresh Images.") }
        let origin = workspaceID, plan = try await io.prepareImageChange(snapshot, action: action)
        guard origin == workspaceID, !isDirty else { throw VaultFailure(message: "The note or vault changed. Refresh Images.") }
        return .init(workspaceID: origin, plan: plan)
    }
    func prepareImageUndo(_ review: MacImageReview) async throws -> MacImageReview {
        guard review.workspaceID == workspaceID, let io, !imageSaving, !isDirty else { throw VaultFailure(message: "The note or vault changed. Restore the image from its original vault’s Recently Deleted.") }
        let plan = try await io.prepareImageUndo(review.plan)
        guard review.workspaceID == workspaceID, !isDirty else { throw CancellationError() }
        return .init(workspaceID: review.workspaceID, plan: plan)
    }
    func applyImageChange(_ review: MacImageReview) async throws {
        guard review.workspaceID == workspaceID, review.plan.snapshot.root == root, let io, !imageSaving, !isDirty else { throw VaultFailure(message: "The note or vault changed. Reopen the image review.") }
        imageSaving = true; defer { imageSaving = false }
        let result = try await io.applyImageChange(review.plan)
        guard review.workspaceID == workspaceID else { throw CancellationError() }
        if case .remove = review.plan.action { imageUndo = review }
        else { imageUndo = nil }
        apply(result)
        guard !isDirty else { throw VaultFailure(message: "The image change was saved. Your newer note draft is kept; save or export it before reloading the note.") }
        await reloadCurrent()
    }
    func imageLease(_ reference: String, notePath: String? = nil, workspaceID expected: UUID) async throws -> NativeFileLease {
        guard expected == workspaceID, let root, let io else { throw VaultFailure(message: "Reopen this image in its original vault.") }
        let url: URL
        if let notePath { url = try await io.resolveResource(reference, notePath: notePath) }
        else { url = try await io.url(for: reference) }
        guard expected == workspaceID else { throw CancellationError() }
        return try NativeFileLease(scope: root, url: url)
    }
}

