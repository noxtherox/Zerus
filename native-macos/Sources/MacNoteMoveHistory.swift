import SwiftUI

/// The receipt is committed with each successful move, including a partial batch.
/// Original bytes allow Undo and Redo to restore settings and link spelling exactly.
struct MacNoteMoveRecord: Identifiable, Codable, Sendable {
    let id: String
    let date: Date
    var moves: [MacNoteMove]
    var changes: [VaultFileChange]
    static func noteHash(_ content: String) -> String { NativeHistory.hash(String(content.unicodeScalars.drop(while: { $0.value == 0xfeff }))) }
    var noteHashes: [String: String]
    var created: [String: Date]
    var undone: Bool
    var path: String { ".zerus/mac-move-history/" + id + ".json" }
}
struct MacNoteMoveHistoryListing: Sendable {
    var records: [MacNoteMoveRecord] = []
    var issues: [String] = []
}
struct MacNoteMoveHistoryReview: Identifiable, Sendable {
    let id = UUID()
    let record: MacNoteMoveRecord
    let undo: Bool
    var action: String { undo ? "Undo" : "Redo" }
    let plan: NativeRelationMaintenancePlan
    var noteChanges: [VaultFileChange] { plan.changes.filter { $0.path.lowercased().hasSuffix(".md") && $0.before != $0.after } }
    var settingChanges: [VaultFileChange] { plan.changes.filter { [".zerus/properties.json", ".zerus/links.json"].contains($0.path) && $0.before != $0.after } }
}

extension VaultFiles {
    func macNoteMoveHistory() throws -> MacNoteMoveHistoryListing {
        let folder = try url(for: ".zerus/mac-move-history")
        guard FileManager.default.fileExists(atPath: folder.path) else { return .init() }
        var listing = MacNoteMoveHistoryListing()
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try Task.checkCancellation()
            do {
                let record = try JSONDecoder().decode(MacNoteMoveRecord.self, from: read(".zerus/mac-move-history/" + file.lastPathComponent))
                guard UUID(uuidString: record.id) != nil, file.lastPathComponent == record.id + ".json" else { throw VaultFailure(message: "The move history identity is invalid.") }
                listing.records.append(record)
            } catch { listing.issues.append(file.lastPathComponent + ": " + error.localizedDescription + " Original file preserved.") }
        }
        listing.records.sort { $0.date > $1.date }
        return listing
    }
    func prepareMacNoteMoveHistory(_ id: String, undo: Bool, workspaceID: UUID) throws -> MacNoteMoveHistoryReview {
        guard UUID(uuidString: id) != nil else { throw VaultFailure(message: "This move record is unavailable.") }
        let path = ".zerus/mac-move-history/" + id + ".json", bytes = try read(path)
        let record = try JSONDecoder().decode(MacNoteMoveRecord.self, from: bytes)
        let action = undo ? "Undo" : "Redo"
        guard record.id == id, record.undone != undo, !record.moves.isEmpty else { throw VaultFailure(message: "These moves are no longer available for " + action + ". Refresh history.") }
        guard Set(record.changes.map(\.path)).count == record.changes.count,
              Set(record.moves.map(\.source)).count == record.moves.count,
              Set(record.moves.map(\.destination)).count == record.moves.count,
              record.moves.allSatisfy({ $0.source != $0.destination }),
              record.changes.allSatisfy({ ($0.path.lowercased().hasSuffix(".md") || [".zerus/properties.json", ".zerus/links.json"].contains($0.path)) && !$0.path.lowercased().hasPrefix(".zerus/mac-move-history/") && !$0.path.lowercased().hasPrefix(".zerus/native-transactions/") }) else { throw VaultFailure(message: "This move receipt is invalid. No files were changed.") }
        let raw = try relationDefinitionSnapshot()
        let hashes = Dictionary(uniqueKeysWithValues: raw.notes.map { ($0.path, MacNoteMoveRecord.noteHash($0.content)) })
        var expected = record.noteHashes
        if !undo {
            // Receipts store the forward result. Reconstruct the exact pre-move
            // note set from their original bytes, including deleted destinations.
            for change in record.changes where change.path.lowercased().hasSuffix(".md") {
                expected[change.path] = change.before.map { MacNoteMoveRecord.noteHash(String(decoding: $0, as: UTF8.self)) }
            }
        }
        var schema = raw.schema; schema.workspaceID = workspaceID
        let snapshot = NativeRelationDefinitionSnapshot(schema: schema, notes: raw.notes)
        if hashes != expected {
            let affected = Set(record.changes.filter { $0.before != $0.after }.map(\.path))
            // Later work in notes that the receipt rewrites must stay protected.
            guard affected.filter({ $0.lowercased().hasSuffix(".md") }).allSatisfy({ hashes[$0] == expected[$0] }) else {
                throw VaultFailure(message: "Notes changed after these moves. " + action + " cannot replace later work. Move the notes using a fresh move review instead.")
            }
            let displacedIDs = Set(record.changes.compactMap { change -> String? in
                guard change.path.lowercased().hasSuffix(".md"), let bytes = undo ? change.after : change.before else { return nil }
                return NoteDocument(path: change.path, content: String(decoding: bytes, as: UTF8.self), modified: Date()).stableID
            })
            let restoredIDs = Set(record.changes.compactMap { change -> String? in
                guard change.path.lowercased().hasSuffix(".md"), let bytes = undo ? change.before : change.after else { return nil }
                return NoteDocument(path: change.path, content: String(decoding: bytes, as: UTF8.self), modified: Date()).stableID
            })
            // Keep an identity assigned by the move if later work mentions it.
            // As with organization receipts, a fresh review is needed to remove it.
            for id in displacedIDs.subtracting(restoredIDs) {
                guard !raw.notes.contains(where: { !affected.contains($0.path) && $0.content.contains(id) }) else {
                    throw VaultFailure(message: "Note references changed after these moves. " + action + " cannot remove an identity used by newer work. Use a fresh move review.")
                }
            }
            // Unrelated edits and new notes may remain. Replan each direction
            // against the current graph: a new incoming link or relation must
            // not require a write outside this receipt's reviewed changes.
            for move in record.moves {
                let plan = try prepareMove(snapshot, source: undo ? move.destination : move.source, destination: undo ? move.source : move.destination)
                guard plan.changes.filter({ $0.before != $0.after }).allSatisfy({ affected.contains($0.path) }) else {
                    throw VaultFailure(message: "Note references changed after these moves. " + action + " needs a fresh move review to preserve the newer links.")
                }
            }
        }
        var changes = undo ? record.changes.map { VaultFileChange(path: $0.path, before: $0.after, after: $0.before) } : record.changes
        // Freeze every note through review, including those with no link changes.
        let guarded = Set(changes.map(\.path))
        changes += try raw.notes.filter { !guarded.contains($0.path) }.map {
            let bytes = try read($0.path)
            return .init(path: $0.path, before: bytes, after: bytes)
        }
        for change in changes where change.path.lowercased().hasSuffix(".md") && change.before != change.after {
            guard try MacNoteRecoveryStore.locations(root: root, path: change.path).isEmpty else { throw VaultFailure(message: "A retained draft exists for \(change.path). Save or resolve it before changing these moves.") }
        }
        var updated = record; updated.undone = undo
        changes.append(.init(path: path, before: bytes, after: try JSONEncoder().encode(updated)))
        // Detect an occupied target or changed shared setting before presenting the review.
        for change in changes {
            let file = try url(for: change.path)
            let actual = FileManager.default.fileExists(atPath: file.path) ? try read(change.path) : nil
            guard actual == change.before else { throw VaultFailure(message: change.path + " changed after these moves. " + action + " preserves the newer file; use a fresh move review.") }
        }
        return .init(record: record, undo: undo, plan: .init(snapshot: snapshot, changes: changes, sourcePath: nil, destination: nil, summaries: [], issues: []))
    }
    func applyMacNoteMoveHistory(_ review: MacNoteMoveHistoryReview) throws -> VaultSnapshot {
        let root = self.root, paths = review.plan.changes.filter { $0.path.lowercased().hasSuffix(".md") && $0.before != $0.after }.map(\.path)
        let snapshot = try applyRelationChanges(schema: review.plan.snapshot.schema, notes: review.plan.snapshot.notes, changes: review.plan.changes) {
            if let path = try MacNoteRecoveryStore.firstRetained(root: root, paths: paths) {
                throw VaultFailure(message: "A retained draft exists for \(path). Save or resolve it before changing these moves.")
            }
        }
        for change in review.plan.changes where change.path.lowercased().hasSuffix(".md") && change.before != change.after {
            let original = review.undo ? change.path : review.record.moves.first(where: { $0.destination == change.path })?.source ?? change.path
            if let bytes = change.after, let date = review.record.created[original] { _ = retainMacMoveCreationDate(date, destination: change.path, expected: bytes) }
        }
        return (try? scan()) ?? snapshot
    }
}

extension MacWorkspace {
    func prepareNoteMoveHistory(_ id: String, undo: Bool = true) async throws -> MacNoteMoveHistoryReview {
        let origin = workspaceID, action = undo ? "Undo" : "Redo"
        guard await save(), let io, origin == workspaceID, !isDirty else { throw VaultFailure(message: "Save the note before reviewing " + action + ".") }
        let review = try await io.prepareMacNoteMoveHistory(id, undo: undo, workspaceID: origin)
        guard origin == workspaceID, !isDirty else { throw VaultFailure(message: "The note or vault changed. Review " + action + " again.") }
        return review
    }
    func commitNoteMoveHistory(_ review: MacNoteMoveHistoryReview) async throws {
        let action = review.action
        guard let io, review.plan.snapshot.schema.workspaceID == workspaceID, review.plan.snapshot.schema.root == root else { throw VaultFailure(message: "The vault changed. Review " + action + " again.") }
        let rootPath = root?.resolvingSymlinksInPath().standardizedFileURL.path
        let peers = Self.windows.compactMap(\.value).filter { $0.root?.resolvingSymlinksInPath().standardizedFileURL.path == rootPath }
        guard peers.allSatisfy({ !$0.isDirty && $0.noteDiskChange == nil && !$0.busy && !$0.schemaMaintenanceSaving && !$0.noteMovesSaving && !$0.imageSaving && !$0.externalCopySaving && !$0.recoverySaving && !$0.preparingToClose }) else { throw VaultFailure(message: "Save or resolve drafts and finish other changes in every vault window before " + action + ".") }
        peers.forEach { $0.noteMovesSaving = true }; defer { peers.forEach { $0.noteMovesSaving = false } }
        let snapshot = try await io.applyMacNoteMoveHistory(review)
        let mapping = Dictionary(uniqueKeysWithValues: review.record.moves.map { review.undo ? ($0.destination, $0.source) : ($0.source, $0.destination) })
        for peer in peers { peer.remapMovedNotePaths(mapping); await peer.adoptSchemaMaintenanceSnapshot(snapshot); await peer.reconcileNavigation() }
    }
}

struct MacNoteMoveHistoryView: View {
    @Bindable var workspace: MacWorkspace
    let review: MacNoteMoveHistoryReview
    var saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(review.action + " note moves").macFont(.title2.bold()); Spacer(); Button("Cancel") { dismiss() }.disabled(busy).keyboardShortcut(.cancelAction) }
            Text(review.undo ? "Restore original paths, folder definitions and reference text together. Attachment files stay in place. Later edits to affected notes or settings block Undo. Unrelated notes are preserved." : "Repeat the saved moves, folder definitions and reference changes together. Attachment files stay in place. Later edits to affected notes or settings, new incoming references or occupied paths block Redo. Unrelated notes are preserved.").foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                ForEach(review.record.moves) { move in Label(review.undo ? move.destination + " → " + move.source : move.source + " → " + move.destination, systemImage: review.undo ? "arrow.uturn.backward" : "arrow.uturn.forward").macFont(.callout) }
                Divider(); Text("Note changes").macFont(.headline)
                ForEach(review.noteChanges, id: \.path) { change in DisclosureGroup(change.path) { MacHistoryDifferenceView(before: change.before.map { String(decoding: $0, as: UTF8.self) } ?? "", after: change.after.map { String(decoding: $0, as: UTF8.self) } ?? "") } }
                if !review.settingChanges.isEmpty {
                    Divider(); Text("Shared settings").macFont(.headline)
                    ForEach(review.settingChanges, id: \.path) { change in DisclosureGroup(change.path) { MacHistoryDifferenceView(before: change.before.map { String(decoding: $0, as: UTF8.self) } ?? "", after: change.after.map { String(decoding: $0, as: UTF8.self) } ?? "") } }
                }
            }.frame(maxWidth: .infinity, alignment: .leading) }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red) }
            HStack { if busy { ProgressView().controlSize(.small) }; Spacer(); Button(review.action + " reviewed moves") { busy = true; issue = nil; Task { defer { busy = false }; do { try await workspace.commitNoteMoveHistory(review); saved(); dismiss() } catch { issue = error.localizedDescription } } }.disabled(busy) }
        }.padding(24).frame(width: 720, height: 530).interactiveDismissDisabled(busy)
    }
}
