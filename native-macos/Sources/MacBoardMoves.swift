import Foundation

/// A card shown in its target column before its note is written.
struct MacBoardPendingMove: Equatable {
    let token: UUID
    let values: [String]
}

struct MacBoardSnapshotKey: Equatable {
    let collection: UInt64
    let workspace: UUID
    let destination: String
    let folder: Bool
    let query: String
    let field: [String]
    let order: [String]
    let overrides: [String: [String]]
}

enum MacBoardMoveOutcome: Sendable {
    /// The move needs the review sheet, for example an invalid choice.
    case review(NativeBulkPlan)
    case applied(VaultSnapshot)
}

extension VaultFiles {
    /// Plan and write a single-card board move in one actor turn. The plan and
    /// the write share one inventory read, so the identity re-check that a
    /// reviewed plan needs is unnecessary; the transaction still verifies each
    /// file's expected bytes and records bulk history for undo.
    func macBoardMove(path: String, mutation: NativeBulkMutation, workspaceID: UUID) throws -> MacBoardMoveOutcome {
        let raw = try bulkSnapshot()
        var schema = raw.source.schema; schema.workspaceID = workspaceID
        let notes = raw.source.notes.map { note in var value = note; value.workspaceID = workspaceID; return value }
        let snapshot = NativeBulkSnapshot(source: .init(schema: schema, notes: notes), historyBytes: raw.historyBytes, records: raw.records)
        guard let selected = notes.first(where: { $0.path == path }) else { throw VaultFailure(message: "This note is no longer available.") }
        let plan = try snapshot.plan(selected: [selected], mutation: mutation)
        guard plan.issues.isEmpty else { return .review(plan) }
        try applyTransaction(plan.changes)
        return .applied(try scan())
    }
}

extension MacWorkspace {
    /// Move one card immediately and write it in the background. Moves are
    /// written in drop order. A failed write returns the card to its saved
    /// column and reports the error; a move that needs review hands its plan
    /// to `review` without writing.
    func moveBoardCard(_ transfer: MacBoardTransfer, target: String?, scope: MacBoardScope, review: @escaping @MainActor (NativeBulkPlan) -> Void) {
        guard acceptsBoardDrop(transfer, target: target, scope: scope), case .notes(let paths) = transfer.item,
              paths.count == 1, let path = paths.first, let field = boardField else { return }
        let token = UUID(), origin = workspaceID
        boardPendingMoves[path] = .init(token: token, values: target.map { [$0] } ?? [])
        let value: NativePropertyValue?
        if let target {
            switch field.type { case .checkbox: value = .checkbox(target == "true"); case .number: value = .number(target); default: value = .text(target) }
        } else { value = nil }
        let mutation = NativeBulkMutation(properties: [.init(name: field.name, operation: value == nil ? .clear : .set, value: value)])
        let title = notes.first { $0.path == path }?.title ?? path
        let previous = boardMoveChain
        boardMoveChain = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            defer { if self.boardPendingMoves[path]?.token == token { self.boardPendingMoves[path] = nil } }
            do {
                if let plan = try await self.writeBoardMove(path: path, mutation: mutation, workspaceID: origin) {
                    if self.boardPendingMoves[path]?.token == token { self.boardPendingMoves[path] = nil }
                    review(plan)
                }
            } catch {
                if origin == self.workspaceID { self.issue = "Couldn’t move “\(title)”. It was returned to its column. " + error.localizedDescription }
            }
        }
    }
    private func writeBoardMove(path: String, mutation: NativeBulkMutation, workspaceID origin: UUID) async throws -> NativeBulkPlan? {
        guard origin == workspaceID, !preparingToClose, !agentWritingHeld, await save(), origin == workspaceID, let io else {
            throw VaultFailure(message: "The vault changed or saving is blocked.")
        }
        boardSaving = true; defer { boardSaving = false }
        let outcome = try await io.macBoardMove(path: path, mutation: mutation, workspaceID: origin)
        guard origin == workspaceID else { throw VaultFailure(message: "The vault changed.") }
        switch outcome {
        case .review(let plan): return plan
        case .applied(let snapshot):
            apply(snapshot)
            await reloadCurrent()
            return nil
        }
    }
}
