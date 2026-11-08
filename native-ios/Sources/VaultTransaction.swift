import Foundation

struct VaultFileChange: Codable, Sendable {
    let path: String
    let before: Data?
    let after: Data?
}

/// A write-ahead record makes a multi-file change recoverable after process
/// termination. Every target is coordinated together and checked before writes.
struct VaultTransactionRecord: Codable, Sendable {
    let version: Int
    var committed: Bool
    let changes: [VaultFileChange]
    var finishRecovery: Bool? = nil
}

enum VaultRecoveryChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case current, original, intended
    var id: String { rawValue }
    var label: String {
        switch self { case .current: "Keep current"; case .original: "Use original"; case .intended: "Use intended" }
    }
}

struct VaultRecoveryFile: Codable, Identifiable, Sendable {
    let path: String
    let original: Data?
    let intended: Data?
    let current: Data?
    var id: String { path }
    func data(for choice: VaultRecoveryChoice) -> Data? {
        switch choice { case .current: current; case .original: original; case .intended: intended }
    }
}

struct VaultRecoveryReview: Identifiable, Sendable {
    let id = UUID()
    let journalPath: String
    let journalBytes: Data
    let files: [VaultRecoveryFile]
}

struct VaultRecoveryRequired: LocalizedError {
    let review: VaultRecoveryReview
    var errorDescription: String? {
        let path = review.files.first { $0.current != $0.original && $0.current != $0.intended }?.path ?? "a file"
        return "A pending change conflicts with an outside edit to \(path). Review the saved versions before reopening this vault."
    }
}

struct VaultRecoveryArchive: Codable, Sendable {
    let version: Int
    let created: Date
    let journalPath: String
    let journalBytes: Data
    let files: [VaultRecoveryFile]
    let choices: [String: VaultRecoveryChoice]
    var drafts: [VaultRecoveryDraft]? = nil
}

struct VaultRecoveryDraft: Codable, Identifiable, Sendable {
    let path: String
    let data: Data
    var id: String { path }
}

struct VaultRecoveryCopy: Identifiable, Sendable {
    let path: String
    let modified: Date
    let bytes: Int
    var id: String { path }
}

private final class TransactionResult: @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)
    // Written once before signaling; read only after waiting.
    var value: Result<Void, Error> = .failure(VaultFailure(message: "The file transaction did not run."))
}

extension VaultFiles {
    func applyTransaction(_ changes: [VaultFileChange], historySource: String = "mobile", historyCleanupSnapshot: NativeHistoryMaintenanceSnapshot? = nil, reading: [URL] = [], selectedReading: [NativeFileLease] = [], preservingRemoteBytes: Bool = false, validate: @escaping @Sendable () throws -> Void = {}) throws {
        guard !changes.isEmpty else { return }
        guard Set(changes.map(\.path)).count == changes.count else { throw VaultFailure(message: "A file appears more than once in this change.") }
        try recoverTransactions()
        // A replicated snapshot already contains its remote indexes/history.
        // Deriving them again would change the bytes being synchronized.
        var preparedChanges = try preservingRemoteBytes ? changes : includingAutomaticHistory(includingSavedLinkIndex(changes), source: historySource)
        var cleanupSnapshot = historyCleanupSnapshot
        if !preservingRemoteBytes, cleanupSnapshot == nil, preparedChanges.contains(where: { $0.path.hasPrefix(".zerus/history/notes/") && $0.before != nil && $0.after == nil }) {
            let snapshot = try historyMaintenanceSnapshot()
            preparedChanges = try historyBlobCleanup(preparedChanges, snapshot: snapshot).changes
            cleanupSnapshot = snapshot
        }
        let changes = preparedChanges
        let historyValidation = cleanupSnapshot
        let journalPath = ".zerus/native-transactions/" + UUID().uuidString.lowercased() + ".json"
        let journal = try url(for: journalPath)
        let locations = try changes.map { change -> URL in
            guard !change.path.hasPrefix(".zerus/native-transactions/") else { throw VaultFailure(message: "A change cannot overwrite its recovery records.") }
            let location = try url(for: change.path)
            if change.before != change.after { try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true) }
            return location
        }
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        let internalReads = reading.filter { !locations.contains($0) }
        let selected = selectedReading.filter { !locations.contains($0.url) && !internalReads.contains($0.url) }
        let extra = internalReads + selected.map(\.url)
        let readOnly = Set(changes.indices.filter { changes[$0].before == changes[$0].after } + Array((locations.count + 1)..<(locations.count + 1 + extra.count)))
        let capabilities = Dictionary(uniqueKeysWithValues: selected.enumerated().map { (locations.count + 1 + internalReads.count + $0.offset, $0.element) })
        try Self.coordinateTransaction(locations: locations + [journal] + extra, root: root, reading: readOnly, selectedReading: capabilities) { urls in
            let journal = urls[changes.count], targets = Array(urls.prefix(changes.count))
            for (index, change) in changes.enumerated() {
                guard try Self.existingData(targets[index]) == change.before else {
                    throw VaultFailure(message: "\(change.path) changed outside Zerus. No files were changed; reload the folder properties and try again.")
                }
            }
            try validate()
            if let historyValidation { try Self.validateHistoryMaintenance(historyValidation) }
            guard changes.contains(where: { $0.before != $0.after }) else { return }
            // Read dependencies must be checked, but never become rollback
            // payloads or duplicate every unchanged note in the recovery record.
            var record = VaultTransactionRecord(version: 1, committed: false, changes: changes.filter { $0.before != $0.after })
            try JSONEncoder().encode(record).write(to: journal, options: .atomic)
            var attempted: [Int] = []
            do {
                for (index, change) in changes.enumerated() {
                    guard try Self.existingData(targets[index]) == change.before else { throw VaultFailure(message: "\(change.path) changed while this operation was preparing. The change was canceled.") }
                    if change.before != change.after {
                        attempted.append(index)
                        try Self.replaceFile(targets[index], data: change.after)
                    }
                }
                record.committed = true
                try JSONEncoder().encode(record).write(to: journal, options: .atomic)
            } catch {
                // Coordination still owns all targets. A partial failure can
                // roll back without overwriting an outside writer.
                var rollbackFailed = false
                for index in attempted.reversed() {
                    let change = changes[index]
                    do {
                        let current = try Self.existingData(targets[index])
                        if current == change.after { try Self.replaceFile(targets[index], data: change.before) }
                        else if current != change.before { rollbackFailed = true }
                    } catch { rollbackFailed = true }
                }
                if !rollbackFailed { try? FileManager.default.removeItem(at: journal) }
                if rollbackFailed { throw VaultFailure(message: "This change could not finish. Its recovery record is kept at \(journalPath). Reopen the vault to recover the original files.") }
                throw error
            }
            // A committed record is safe to clean up on a later launch.
            try? FileManager.default.removeItem(at: journal)
        }
    }

    func recoverTransactions() throws {
        writesSuspendedForRecovery = true
        try recoverPendingTransactions()
        try finishFolderRenames()
        try finishFolderTrash()
        writesSuspendedForRecovery = false
    }

    private func recoverPendingTransactions() throws {
        let folder = try url(for: ".zerus/native-transactions")
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let relative = ".zerus/native-transactions/" + file.lastPathComponent
            let original = try read(relative)
            let record = try validatedRecord(original, path: relative)
            let locations = try record.changes.map { try url(for: $0.path) }
            try Self.coordinateTransaction(locations: locations + [file], root: root) { urls in
                guard try Self.existingData(urls.last!) == original else { throw VaultFailure(message: "A recovery record changed outside Zerus. Reopen the vault to retry.") }
                if !record.committed {
                    // Validate every file first. Conflicting external changes
                    // and the original record are retained for reconciliation.
                    let current = try urls.dropLast().map(Self.existingData)
                    let files = zip(record.changes, current).map { VaultRecoveryFile(path: $0.0.path, original: $0.0.before, intended: $0.0.after, current: $0.1) }
                    guard files.allSatisfy({ $0.current == $0.original || $0.current == $0.intended }) else {
                        throw VaultRecoveryRequired(review: VaultRecoveryReview(journalPath: relative, journalBytes: original, files: files))
                    }
                    for (index, change) in record.changes.enumerated() {
                        // A confirmed recovery resumes its selected result;
                        // ordinary interrupted writes restore their originals.
                        let desired = record.finishRecovery == true ? change.after : change.before
                        if current[index] != desired { try Self.replaceFile(urls[index], data: desired) }
                    }
                }
                try FileManager.default.removeItem(at: urls.last!)
            }
        }
    }

    private func validatedRecord(_ bytes: Data, path: String) throws -> VaultTransactionRecord {
        let record = try JSONDecoder().decode(VaultTransactionRecord.self, from: bytes)
        guard (record.version == 1 && record.finishRecovery == nil || record.version == 2 && record.finishRecovery == true),
              !record.changes.isEmpty, Set(record.changes.map(\.path)).count == record.changes.count,
              !record.changes.contains(where: { $0.path == ".zerus/native-transactions" || $0.path.hasPrefix(".zerus/native-transactions/") || $0.path == ".zerus/native-recovery" || $0.path.hasPrefix(".zerus/native-recovery/") }) else {
            throw VaultFailure(message: "An unsupported recovery record was preserved at \(path).")
        }
        for change in record.changes { _ = try url(for: change.path) }
        return record
    }

    func resolveRecovery(_ review: VaultRecoveryReview, choices: [String: VaultRecoveryChoice], drafts: [VaultRecoveryDraft] = []) throws -> String {
        let record = try validatedRecord(review.journalBytes, path: review.journalPath)
        guard review.journalPath.hasPrefix(".zerus/native-transactions/"), review.journalPath.hasSuffix(".json"),
              review.files.map(\.path) == record.changes.map(\.path), Set(choices.keys) == Set(review.files.map(\.path)) else { throw VaultFailure(message: "Review every affected file before applying recovery.") }
        let changes = review.files.map { VaultFileChange(path: $0.path, before: $0.current, after: $0.data(for: choices[$0.path]!)) }
        let archivePath = ".zerus/native-recovery/" + UUID().uuidString.lowercased() + ".json"
        let archiveURL = try url(for: archivePath), journalURL = try url(for: review.journalPath)
        let targets = try changes.map { try url(for: $0.path) }
        for location in targets + [archiveURL] { try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true) }
        let archive = VaultRecoveryArchive(version: 1, created: Date(), journalPath: review.journalPath, journalBytes: review.journalBytes, files: review.files, choices: choices, drafts: drafts.isEmpty ? nil : drafts)
        try Self.coordinateTransaction(locations: targets + [journalURL, archiveURL], root: root) { urls in
            let journal = urls[changes.count], backup = urls[changes.count + 1]
            guard try Self.existingData(journal) == review.journalBytes else { throw VaultFailure(message: "The pending change was updated. Refresh this review before applying your choices.") }
            for (index, change) in changes.enumerated() {
                guard try Self.existingData(urls[index]) == change.before else { throw VaultFailure(message: "\(change.path) changed since this review. Refresh it before applying your choices; no files were changed.") }
            }
            guard try Self.existingData(backup) == nil else { throw VaultFailure(message: "The recovery copy already exists. Refresh this review and retry.") }
            // The copy retains every reviewed alternative, including binary
            // files and absent versions. Never replace the old journal first.
            try JSONEncoder().encode(archive).write(to: backup, options: .atomic)
            var resolution = VaultTransactionRecord(version: 2, committed: false, changes: changes, finishRecovery: true)
            try JSONEncoder().encode(resolution).write(to: journal, options: .atomic)
            // On interruption, version 2 resumes these confirmed choices.
            // An outside edit instead opens another review without overwriting.
            for (index, change) in changes.enumerated() where change.before != change.after {
                guard try Self.existingData(urls[index]) == change.before else { throw VaultFailure(message: "\(change.path) changed during recovery. Reopen the review to continue safely.") }
                try Self.replaceFile(urls[index], data: change.after)
            }
            resolution.committed = true
            try JSONEncoder().encode(resolution).write(to: journal, options: .atomic)
            try? FileManager.default.removeItem(at: journal)
        }
        return archivePath
    }

    func recoveryCopies() throws -> [VaultRecoveryCopy] {
        let folder = try url(for: ".zerus/native-recovery")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]).filter { $0.pathExtension == "json" }.compactMap { location in
            let values = try location.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { return nil }
            return VaultRecoveryCopy(path: ".zerus/native-recovery/" + location.lastPathComponent, modified: values.contentModificationDate ?? .distantPast, bytes: values.fileSize ?? 0)
        }.sorted { $0.modified > $1.modified }
    }

    nonisolated static func existingData(_ url: URL) throws -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }
    private nonisolated static func replaceFile(_ url: URL, data: Data?) throws {
        if let data { try data.write(to: url, options: .atomic) }
        else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    nonisolated static func coordinateTransaction(locations: [URL], root: URL, reading: Set<Int> = [], selectedReading: [Int: NativeFileLease] = [:], operation: @escaping @Sendable ([URL]) throws -> Void) throws {
        let coordinator = NSFileCoordinator(), queue = OperationQueue(), result = TransactionResult()
        queue.maxConcurrentOperationCount = 1
        let intents = locations.enumerated().map { reading.contains($0.offset) ? NSFileAccessIntent.readingIntent(with: $0.element, options: []) : NSFileAccessIntent.writingIntent(with: $0.element, options: .forReplacing) }
        @Sendable func checkedPath(_ url: URL, at index: Int) throws -> String {
            if let lease = selectedReading[index] {
                guard reading.contains(index), url.resolvingSymlinksInPath().standardizedFileURL.path == lease.canonicalPath else { throw VaultFailure(message: "The selected document moved. Choose it again before saving.") }
                return lease.canonicalPath
            }
            return try confinedPath(for: url, root: root)
        }
        let expectedPaths = try locations.enumerated().map { try checkedPath($0.element, at: $0.offset) }
        guard Set(expectedPaths).count == expectedPaths.count else { throw VaultFailure(message: "Two transaction paths refer to the same file.") }
        coordinator.coordinate(with: intents, queue: queue) { error in
            defer { result.finished.signal() }
            result.value = Result {
                if let error { throw error }
                let urls = intents.map(\.url)
                let actualPaths = try urls.enumerated().map { try checkedPath($0.element, at: $0.offset) }
                guard actualPaths == expectedPaths else { throw VaultFailure(message: "A transaction target moved. Refresh the vault before retrying.") }
                try operation(urls)
            }
        }
        // VaultFiles runs off the UI actor. Keeping this operation synchronous
        // also prevents its own scanner from recovering a still-live journal.
        result.finished.wait()
        try result.value.get()
    }
}
