import Foundation

/// Cross-provider moves cannot share a filesystem rename. Keep the original
/// bytes and a verified destination receipt until source removal and private
/// registration cleanup both finish. Recovery never removes an original without
/// a fresh, explicit review.
struct NativeExternalMoveRecord: Codable, Identifiable, Sendable, Equatable {
    enum Phase: String, Codable, Sendable { case prepared, copied, removed }
    let version: Int
    let id: UUID
    let sourceID: UUID
    let sourceName: String
    let sourceBytes: Data
    let destinationBookmark: Data
    let destinationPath: String
    let noteID: String
    let hashes: [String: String]
    var phase: Phase
    let created: Date
    func destination() throws -> NativeExternalDestination {
        var stale = false
        return try .init(root: URL(resolvingBookmarkData: destinationBookmark, options: [], bookmarkDataIsStale: &stale))
    }
    func validate() throws {
        guard version == 1, sourceBytes.count <= 10 * 1024 * 1024,
              destinationBookmark.count <= 1024 * 1024, !destinationBookmark.isEmpty,
              NativeRevisionIndex.validPath(destinationPath), destinationPath.hasSuffix(".md"),
              !destinationPath.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
              hashes.count <= 1001, hashes[destinationPath] != nil,
              hashes.allSatisfy({ path, hash in
                  NativeRevisionIndex.validPath(path) && (path == destinationPath || path.hasPrefix("assets/")) &&
                  hash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
              }), noteID.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else {
            throw VaultFailure(message: "This pending move is unreadable or uses a newer format. Its recovery data has been preserved.")
        }
    }
}

actor NativeExternalMoveStore {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func read(_ url: URL) throws -> NativeExternalMoveRecord {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 16 * 1024 * 1024 else { throw VaultFailure(message: "A pending move record cannot be read. Its original recovery data is preserved.") }
        let record = try JSONDecoder().decode(NativeExternalMoveRecord.self, from: NativeExternalTransferFiles.boundedData(url, limit: 16 * 1024 * 1024))
        try record.validate(); guard url.lastPathComponent == record.id.uuidString + ".json" else { throw VaultFailure(message: "This pending move record has an unexpected identity.") }
        return record
    }
    func pending() throws -> [NativeExternalMoveRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map(read).sorted { $0.created > $1.created }
    }
    func save(_ record: NativeExternalMoveRecord, replacing previous: NativeExternalMoveRecord?) throws {
        try record.validate(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = file(record.id)
        var error: NSError?, result: Result<Void, Error> = .failure(VaultFailure(message: "The move recovery record could not be saved."))
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &error) { url in result = Result {
            let current = FileManager.default.fileExists(atPath: url.path) ? try read(url) : nil
            guard current == previous else { throw VaultFailure(message: "Another window changed this pending move. Reload it before continuing.") }
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
        } }
        if let error { throw error }; try result.get()
    }
    func finish(_ record: NativeExternalMoveRecord) throws {
        var error: NSError?, result: Result<Void, Error> = .failure(VaultFailure(message: "The move recovery record could not be closed."))
        NSFileCoordinator().coordinate(writingItemAt: file(record.id), options: .forDeleting, error: &error) { url in result = Result {
            guard try read(url) == record else { throw VaultFailure(message: "This pending move changed. Reload it before finishing.") }
            try FileManager.default.removeItem(at: url)
        } }
        if let error { throw error }; try result.get()
    }
}

private final class NativeExternalTransferCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw CancellationError() } }
}
private final class NativeExternalTransferResult: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    var value: Result<Void, Error> = .failure(VaultFailure(message: "The original could not be removed; its vault copy is kept."))
}

extension NativeExternalTransferFiles {
    static func record(for review: NativeExternalTransferReview) throws -> NativeExternalMoveRecord {
        try .init(version: 1, id: review.id, sourceID: review.source.entry.id, sourceName: review.source.entry.name,
                  sourceBytes: review.source.bytes, destinationBookmark: review.destination.root.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil),
                  destinationPath: review.path, noteID: review.noteID,
                  hashes: Dictionary(uniqueKeysWithValues: review.changes.map { ($0.path, hash($0.after!)) }), phase: .prepared, created: .now)
    }
    static func verifyDestination(_ record: NativeExternalMoveRecord, access: NativeExternalDestination) throws -> NoteDocument {
        try record.validate(); try access.validate()
        for (path, digest) in record.hashes {
            let url = access.root.appendingPathComponent(path)
            _ = try VaultFiles.confinedPath(for: url, root: access.root)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= NativeClipboardFragment.limit,
                  hash(try boundedData(url, limit: NativeClipboardFragment.limit)) == digest else { throw VaultFailure(message: "The vault copy or an imported attachment changed. The original has not been removed; review the current files before continuing.") }
        }
        let bytes = try boundedData(access.root.appendingPathComponent(record.destinationPath), limit: 10 * 1024 * 1024)
        guard let content = String(data: bytes, encoding: .utf8) else { throw VaultFailure(message: "The imported note is unreadable. The original is kept.") }
        let note = NoteDocument(path: record.destinationPath, content: content, modified: .now)
        guard note.stableID == record.noteID else { throw VaultFailure(message: "The vault copy has a different identity. The original is kept.") }
        return note
    }
    static func removeOriginal(_ source: NativeExternalSnapshot, record: NativeExternalMoveRecord, destination: NativeExternalDestination) async throws {
        let cancellation = NativeExternalTransferCancellation()
        let work = Task.detached(priority: .userInitiated) {
            try cancellation.check(); try destination.validate()
            guard source.entry.id == record.sourceID, source.bytes == record.sourceBytes else { throw VaultFailure(message: "The original does not match this pending move. No original was removed.") }
            let sourceIntent = NSFileAccessIntent.writingIntent(with: source.access.url, options: .forDeleting)
            let reads = try record.hashes.keys.sorted().map { path -> NSFileAccessIntent in
                let url = destination.root.appendingPathComponent(path)
                _ = try VaultFiles.confinedPath(for: url, root: destination.root)
                return .readingIntent(with: url, options: [])
            }
            let result = NativeExternalTransferResult(), queue = OperationQueue()
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(with: [sourceIntent] + reads, queue: queue) { error in
                defer { result.ready.signal() }
                result.value = Result {
                    if let error { throw error }
                    try cancellation.check()
                    try validateSource(source, at: sourceIntent.url)
                    for (path, intent) in zip(record.hashes.keys.sorted(), reads) {
                        guard intent.url.resolvingSymlinksInPath().standardizedFileURL == destination.root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL else {
                            throw VaultFailure(message: "The vault copy moved during source removal. The original is kept.")
                        }
                    }
                    // All destination files are held for reading while the
                    // selected original alone is held for deletion.
                    _ = try verifyDestination(record, access: destination)
                    try cancellation.check()
                    try FileManager.default.removeItem(at: sourceIntent.url)
                }
            }
            withExtendedLifetime(coordinator) { result.ready.wait() }; try result.value.get()
        }
        // Once deletion succeeds, deliver that receipt even if cancellation
        // arrives afterward; callers must not report that the original remains.
        try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { cancellation.cancel(); work.cancel() })
    }
}
