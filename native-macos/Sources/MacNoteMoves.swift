import SwiftUI

struct MacNoteMove: Identifiable, Codable, Sendable {
    let source: String
    let destination: String
    let title: String
    var id: String { source }
}
struct MacNoteMoveIssue: Identifiable, Sendable {
    let path: String
    let reason: String
    var id: String { path }
}
struct MacNoteMoveReview: Identifiable, Sendable {
    let id = UUID()
    let workspaceID: UUID
    let snapshot: NativeRelationDefinitionSnapshot
    let moves: [MacNoteMove]
    let skipped: [MacNoteMoveIssue]
    let warnings: [String]
    let sidecars: [VaultFileChange]
    let bindings: [NativeMoveResourceBinding]
    let recoveryDrafts: [String: URL]
}
struct MacNoteMoveResult: Sendable {
    let moved: [MacNoteMove]
    let skipped: [MacNoteMoveIssue]
    let failed: [MacNoteMoveIssue]
    let warnings: [MacNoteMoveIssue]
    let snapshot: VaultSnapshot
    let undoRecord: MacNoteMoveRecord?
}

extension VaultFiles {
    /// A coordinated note rewrite creates the destination file. Retain its
    /// original birth date without overwriting a subsequent outside edit.
    func retainMacMoveCreationDate(_ date: Date, destination: String, expected: Data) -> String? {
        do {
            let access = root.startAccessingSecurityScopedResource()
            defer { if access { root.stopAccessingSecurityScopedResource() } }
            let file = try url(for: destination)
            var coordination: NSError?, failure: Error?
            NSFileCoordinator().coordinate(writingItemAt: file, options: .forMerging, error: &coordination) { location in
                do {
                    guard try Data(contentsOf: location) == expected else { throw VaultFailure(message: "The moved file changed before its original creation date could be restored.") }
                    try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: location.path)
                } catch { failure = error }
            }
            if let error = coordination ?? failure as NSError? { throw error }
            return nil
        } catch { return "The note moved, but its creation date could not be retained: " + error.localizedDescription }
    }
    func applyMacNoteMove(_ plan: NativeRelationMaintenancePlan, source: String, destination: String) throws -> (snapshot: VaultSnapshot, warnings: [MacNoteMoveIssue]) {
        var snapshot = try applyRelationMaintenance(plan), warnings: [MacNoteMoveIssue] = []
        for change in plan.changes where (change.path as NSString).pathExtension.lowercased() == "md" {
            guard let bytes = change.after,
                  let date = plan.snapshot.notes.first(where: { $0.path == (change.path == destination ? source : change.path) })?.created else { continue }
            if let warning = retainMacMoveCreationDate(date, destination: change.path, expected: bytes) { warnings.append(.init(path: change.path, reason: warning)) }
        }
        snapshot = (try? scan()) ?? snapshot
        return (snapshot, warnings)
    }
    private func macMoveData(_ path: String) throws -> Data? {
        let file = try url(for: path)
        return FileManager.default.fileExists(atPath: file.path) ? try read(path) : nil
    }
    func prepareMacNoteMoves(paths: Set<String>, folder: String, workspaceID: UUID, recoveryDrafts: [String: URL]) throws -> MacNoteMoveReview {
        let folder = folder.isEmpty ? "" : try NativeFolderPath.clean(folder)
        if !folder.isEmpty { _ = try NativeFolderPath.location(folder, root: root) }
        let snapshot = try relationDefinitionSnapshot()
        var moves: [MacNoteMove] = [], skipped: [MacNoteMoveIssue] = [], warnings = Set<String>(), bindings: [NativeMoveResourceBinding] = []
        var dependencies: [String: VaultFileChange] = [:]
        for path in [".zerus/properties.json", ".zerus/links.json"] { let data = try macMoveData(path); dependencies[path] = .init(path: path, before: data, after: data) }
        func folded(_ path: String) -> String { path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        var reserved = Set(snapshot.notes.map { folded($0.path) })
        for path in paths.sorted() {
            try Task.checkCancellation()
            guard let note = snapshot.notes.first(where: { $0.path == path }), !note.trashed else { skipped.append(.init(path: path, reason: "The note is missing or in Trash.")); continue }
            if let draft = recoveryDrafts[path], FileManager.default.fileExists(atPath: draft.path) { skipped.append(.init(path: path, reason: "Resolve or export this note’s retained recovery draft before moving it.")); continue }
            let name = (path as NSString).lastPathComponent, base = folder.isEmpty ? name : folder + "/" + name
            guard path.caseInsensitiveCompare(base) != .orderedSame else { skipped.append(.init(path: path, reason: "Already in this folder.")); continue }
            let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            var suffix = 1, destination: String
            while true {
                try Task.checkCancellation()
                let ending = (suffix == 1 ? "" : " \(suffix)") + (ext.isEmpty ? "" : "." + ext)
                var bounded = ""
                for character in stem { let next = bounded + String(character); guard (next + ending).decomposedStringWithCanonicalMapping.utf8.count <= 240 else { break }; bounded = next }
                let candidate = (folder.isEmpty ? "" : folder + "/") + (bounded.isEmpty ? "Note" : bounded) + ending
                let location = root.appendingPathComponent(candidate)
                let linked = (try? FileManager.default.destinationOfSymbolicLink(atPath: location.path)) != nil
                if !reserved.contains(folded(candidate)), !linked, !FileManager.default.fileExists(atPath: location.path) { destination = candidate; break }
                suffix += 1
            }
            do {
                let plan = try prepareMove(snapshot, source: path, destination: destination)
                for change in plan.changes where (change.path as NSString).pathExtension.lowercased() != "md" { dependencies[change.path] = .init(path: change.path, before: change.before, after: change.before) }
                for issue in plan.issues { warnings.insert(issue.path + ": " + issue.reason) }
                bindings += plan.resourceBindings
                moves.append(.init(source: path, destination: destination, title: note.title)); reserved.insert(folded(destination))
            } catch { skipped.append(.init(path: path, reason: error.localizedDescription)) }
        }
        return .init(workspaceID: workspaceID, snapshot: snapshot, moves: moves, skipped: skipped, warnings: warnings.sorted(), sidecars: dependencies.values.sorted { $0.path < $1.path }, bindings: bindings, recoveryDrafts: recoveryDrafts)
    }
    /// Match desktop batch semantics: each accepted note move is coordinated;
    /// earlier successes remain explicit if a later source or dependency changes.
    func applyMacNoteMoves(_ review: MacNoteMoveReview, progress: @Sendable (Int, Int) -> Void) throws -> MacNoteMoveResult {
        guard review.snapshot.schema.root == root else { throw VaultFailure(message: "The vault changed. Reopen the move review.") }
        var expected = Dictionary(uniqueKeysWithValues: review.snapshot.notes.map { ($0.path, Data($0.content.utf8)) })
        var sidecars = Dictionary(uniqueKeysWithValues: review.sidecars.map { ($0.path, $0.before) })
        var moved: [MacNoteMove] = [], failed: [MacNoteMoveIssue] = [], warnings: [MacNoteMoveIssue] = []
        var last = try scan()
        var record = MacNoteMoveRecord(id: UUID().uuidString.lowercased(), date: Date(), moves: [], changes: [], noteHashes: [:], created: [:], undone: false)
        var recordBytes: Data?
        for (index, move) in review.moves.enumerated() {
            do {
                try Task.checkCancellation()
                if !(try MacNoteRecoveryStore.locations(root: root, path: move.source)).isEmpty { throw VaultFailure(message: "A recovery draft appeared for this note. Resolve it before moving.") }
                let current = try relationDefinitionSnapshot()
                let actual = Dictionary(uniqueKeysWithValues: current.notes.map { ($0.path, Data($0.content.utf8)) })
                guard actual == expected else { throw VaultFailure(message: "Notes changed after review. Review the remaining moves again.") }
                for (path, bytes) in sidecars where try macMoveData(path) != bytes { throw VaultFailure(message: "Shared settings or link records changed. Review the remaining moves again.") }
                if index == 0 {
                    for binding in review.bindings where NativeMoveResourceBinding.path(binding.reference, notePath: binding.notePath, root: root) != binding.resolved { throw VaultFailure(message: "A linked file changed after review. Reopen the move review.") }
                }
                var plan = try prepareMove(current, source: move.source, destination: move.destination)
                var nextRecord = record
                nextRecord.moves.append(move)
                var composed = Dictionary(uniqueKeysWithValues: record.changes.map { ($0.path, $0) })
                for change in plan.changes {
                    if let previous = composed[change.path] { composed[change.path] = .init(path: change.path, before: previous.before, after: change.after) }
                    else { composed[change.path] = change }
                }
                nextRecord.changes = composed.values.filter { $0.before != $0.after || !$0.path.lowercased().hasSuffix(".md") }.sorted { $0.path < $1.path }
                nextRecord.noteHashes = expected.mapValues { MacNoteMoveRecord.noteHash(String(decoding: $0, as: UTF8.self)) }
                // Dictionary subscripting removes deleted sources and inserts the moved destination.
                for change in plan.changes where change.path.lowercased().hasSuffix(".md") { nextRecord.noteHashes[change.path] = change.after.map { MacNoteMoveRecord.noteHash(String(decoding: $0, as: UTF8.self)) } }
                for note in review.snapshot.notes where nextRecord.created[note.path] == nil { nextRecord.created[note.path] = note.created }
                let nextBytes = try JSONEncoder().encode(nextRecord)
                plan = NativeRelationMaintenancePlan(snapshot: plan.snapshot, changes: plan.changes + [.init(path: record.path, before: recordBytes, after: nextBytes)], sourcePath: plan.sourcePath, destination: plan.destination, summaries: plan.summaries, issues: plan.issues, resourceBindings: plan.resourceBindings)
                let applied = try applyMacNoteMove(plan, source: move.source, destination: move.destination)
                last = applied.snapshot; warnings += applied.warnings
                for change in plan.changes {
                    if (change.path as NSString).pathExtension.lowercased() == "md" { expected[change.path] = change.after }
                    else { sidecars[change.path] = .some(change.after) }
                }
                record = nextRecord; recordBytes = nextBytes
                moved.append(move); progress(index + 1, review.moves.count)
            } catch {
                if let fresh = try? scan() { last = fresh }
                let reason = error.localizedDescription
                failed += review.moves[index...].map { .init(path: $0.source, reason: $0.source == move.source ? reason : "Not attempted after a move was blocked. Review this note again.") }
                break
            }
        }
        return .init(moved: moved, skipped: review.skipped, failed: failed, warnings: warnings, snapshot: last, undoRecord: moved.isEmpty ? nil : record)
    }
}

extension MacWorkspace {
    func prepareNoteMoves(paths: Set<String>, folder: String, workspaceID expected: UUID) async throws -> MacNoteMoveReview {
        guard expected == workspaceID, !noteMovesSaving, !imageSaving, await save(), expected == workspaceID, let io, !isDirty else { throw VaultFailure(message: "Save the note or reopen Move in its original vault.") }
        let review = try await io.prepareMacNoteMoves(paths: paths, folder: folder, workspaceID: expected, recoveryDrafts: noteMoveDraftLocations(paths))
        guard expected == workspaceID, !isDirty else { throw VaultFailure(message: "The note or vault changed. Reopen Move.") }
        return review
    }
    func commitNoteMoves(_ review: MacNoteMoveReview) async throws -> MacNoteMoveResult {
        guard review.workspaceID == workspaceID, !noteMovesSaving, !imageSaving, !isDirty, let io else { throw VaultFailure(message: "The note or vault changed. Reopen Move.") }
        let rootPath = root?.resolvingSymlinksInPath().standardizedFileURL.path
        let peers = Self.windows.compactMap(\.value).filter { $0.root?.resolvingSymlinksInPath().standardizedFileURL.path == rootPath }
        guard peers.allSatisfy({ !$0.isDirty && $0.noteDiskChange == nil && !$0.busy && !$0.schemaMaintenanceSaving && !$0.noteMovesSaving && !$0.imageSaving && !$0.externalCopySaving && !$0.recoverySaving && !$0.preparingToClose }) else { throw VaultFailure(message: "Save or resolve open drafts and finish other vault changes before moving notes.") }
        peers.forEach { $0.noteMovesSaving = true }; noteMoveProgress = (0, review.moves.count)
        defer { peers.forEach { $0.noteMovesSaving = false } }
        let origin = workspaceID
        let previousFolders = try await io.scan().folders
        let applied = try await io.applyMacNoteMoves(review) { [weak self] done, total in Task { @MainActor in if let self, self.workspaceID == origin, done >= self.noteMoveProgress.0 { self.noteMoveProgress = (done, total) } } }
        guard origin == workspaceID else { throw CancellationError() }
        let decorated = await suggestingFolderIcons(in: applied.snapshot, destinations: applied.moved.map { ($0.destination as NSString).deletingLastPathComponent }, previousFolders: previousFolders, using: io)
        guard origin == workspaceID else { throw CancellationError() }
        let result = MacNoteMoveResult(moved: applied.moved, skipped: applied.skipped, failed: applied.failed, warnings: applied.warnings + (decorated.warning.map { [.init(path: "Destination folders", reason: $0)] } ?? []), snapshot: decorated.snapshot, undoRecord: applied.undoRecord)
        let mapping = Dictionary(uniqueKeysWithValues: result.moved.map { ($0.source, $0.destination) })
        noteMoveProgress = (result.moved.count + result.failed.count, review.moves.count)
        for peer in peers { peer.remapMovedNotePaths(mapping); await peer.adoptSchemaMaintenanceSnapshot(result.snapshot); await peer.reconcileNavigation() }
        return result
    }
}
