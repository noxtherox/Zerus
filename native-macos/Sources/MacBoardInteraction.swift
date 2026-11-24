import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let zerusBoardItem = UTType(exportedAs: "com.zerus.notes.native.board-item", conformingTo: .data)
}

/// A drop belongs to the board that produced it, including its visible notes,
/// grouping schema and column order. Loading a drag must not retarget it.
struct MacBoardScope: Codable, Equatable, Sendable {
    let workspace: UUID
    let destination: String
    let folder: Bool
    let field: String
    let schema: String
    let membership: String
    let query: String
    let columns: [String?]
}

struct MacBoardTransfer: Codable, Transferable, Sendable {
    enum Item: Codable, Sendable { case notes(Set<String>); case column(String?) }
    let scope: MacBoardScope
    let item: Item
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .zerusBoardItem).visibility(.ownProcess)
    }
}

extension MacWorkspace {
    var boardField: NativePropertyDefinition? {
        collectionFields.first { !$0.hidden && $0.type != .unsupported && $0.type != .relation && !($0.type == .list && $0.multiple) && $0.name.caseInsensitiveCompare(collectionLayout.groupBy ?? "") == .orderedSame }
    }
    var boardScope: MacBoardScope? { boardSnapshot?.scope }
    /// Rendered columns and their scope come from the same grouping pass. The
    /// pass is cached per collection, layout and pending-move state, so hover
    /// and selection updates during a drag do not regroup the board.
    var boardSnapshot: (scope: MacBoardScope, groups: [MacCollectionGroup])? {
        guard viewMode == "Kanban", let field = boardField else { return nil }
        let order = collectionLayout.boardColumnOrder[field.id] ?? []
        let overrides = boardPendingMoves.mapValues(\.values)
        let key = MacBoardSnapshotKey(collection: collectionIdentity, workspace: workspaceID, destination: destination, folder: folderCollection, query: query,
                                      field: [field.name, field.type.rawValue, field.owner, String(field.multiple)] + field.options, order: order, overrides: overrides)
        if let cachedBoardSnapshot, cachedBoardSnapshot.key == key { return cachedBoardSnapshot.value }
        let value = freshBoardSnapshot(field: field, order: order, overrides: overrides)
        cachedBoardSnapshot = (key, value)
        return value
    }
    private func freshBoardSnapshot(field: NativePropertyDefinition, order: [String], overrides: [String: [String]]) -> (scope: MacBoardScope, groups: [MacCollectionGroup]) {
        let definition = [field.name, field.type.rawValue, field.owner, String(field.multiple)] + field.options
        let signature = (try? JSONEncoder().encode(definition)) ?? Data()
        let members = (try? JSONEncoder().encode(collection.map(\.path).sorted())) ?? Data()
        let groups = MacCollectionValues.boardGroups(notes: collection, field: field, order: order, overrides: overrides)
        let scope = MacBoardScope(workspace: workspaceID, destination: destination, folder: folderCollection, field: field.name,
                     schema: NativeHistory.hash(String(decoding: signature, as: UTF8.self)),
                     membership: NativeHistory.hash(String(decoding: members, as: UTF8.self)), query: query,
                     columns: groups.map(\.value))
        return (scope, groups)
    }
    /// Board values as shown, including a pending optimistic move.
    func boardValues(_ note: NoteDocument, name: String) -> [String] {
        boardPendingMoves[note.path]?.values ?? MacCollectionValues.boardValues(note, name: name)
    }
    func boardSelection(for note: NoteDocument) -> Set<String> {
        selectedPaths.contains(note.path) ? selectedPaths.intersection(Set(collection.map(\.path))) : [note.path]
    }
    func commitBoardDrop(_ plan: NativeBulkPlan, scope: MacBoardScope) async throws {
        guard !busy, !preparingToClose, !agentWritingHeld, scope == boardScope else {
            throw VaultFailure(message: "The board changed. Review the note move again.")
        }
        busy = true; defer { busy = false }
        try await commitBulk(plan)
    }
    func acceptsBoardDrop(_ transfer: MacBoardTransfer, target: String?, scope: MacBoardScope) -> Bool {
        guard !busy, !preparingToClose, !agentWritingHeld, scope == boardScope, transfer.scope == scope, scope.columns.contains(target) else { return false }
        switch transfer.item {
        case .notes(let paths):
            let targetValues = target.map { [$0] } ?? []
            return !paths.isEmpty && paths.isSubset(of: Set(collection.map(\.path))) && collection.contains { paths.contains($0.path) && boardValues($0, name: scope.field) != targetValues }
        case .column(let column): return column != target && scope.columns.contains(column)
        }
    }
    func prepareBoardDrop(_ transfer: MacBoardTransfer, target: String?, scope: MacBoardScope) async throws -> NativeBulkPlan {
        guard acceptsBoardDrop(transfer, target: target, scope: scope), case .notes(let paths) = transfer.item, let field = boardField else {
            throw VaultFailure(message: "The board changed. Drag the notes again.")
        }
        let value: NativePropertyValue?
        if let target {
            switch field.type { case .checkbox: value = .checkbox(target == "true"); case .number: value = .number(target); default: value = .text(target) }
        } else { value = nil }
        let plan = try await prepareCollectionMove(paths: paths, name: field.name, value: value, workspaceID: scope.workspace)
        guard acceptsBoardDrop(transfer, target: target, scope: scope) else { throw VaultFailure(message: "The board changed. Drag the notes again.") }
        return plan
    }
    func reorderBoardDrop(_ transfer: MacBoardTransfer, target: String?, scope: MacBoardScope) async throws {
        guard acceptsBoardDrop(transfer, target: target, scope: scope), case .column(let source) = transfer.item,
              let from = scope.columns.firstIndex(of: source), let to = scope.columns.firstIndex(of: target) else {
            throw VaultFailure(message: "The board changed. Drag the column again.")
        }
        busy = true; defer { busy = false }
        var columns = scope.columns
        let moved = columns.remove(at: from); columns.insert(moved, at: to)
        var layout = collectionLayout; layout.boardColumnOrder[scope.field.lowercased()] = columns.map { $0 ?? "__no_value__" }
        await updateCollectionLayout(layout)
    }
}
