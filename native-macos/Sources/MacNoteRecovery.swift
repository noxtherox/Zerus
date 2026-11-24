import Foundation

struct MacNoteRecoveryRecord: Identifiable, Sendable {
    let windowID: String?
    let file: URL
    let bytes: Data
    let vault: URL
    let note: NoteDocument
    let body: String
    let modified: Date
    var id: String { file.lastPathComponent }
    var content: String { note.replacingBody(body) }
}
struct MacNoteRecoverySnapshot: Sendable {
    var records: [MacNoteRecoveryRecord] = []
    var warnings: [String] = []
}

/// Read the established private draft format, including legacy records without a vaultRoot.
enum MacNoteRecoveryStore {
    // Register work synchronously in edit order, but perform encoding and disk
    // I/O away from AppKit. Reads/removal drain this same queue so an older
    // checkpoint cannot resurrect a draft after Save.
    private static let checkpointQueue = DispatchQueue(label: "com.zerus.notes.recovery-checkpoints", qos: .userInitiated)
    private struct Checkpoint: Sendable {
        let root: URL
        let note: NoteDocument
        let body: String
        let windowID: String
        let onFailure: @Sendable (String) -> Void
    }
    // A queued slot retains only the newest edit for its exact recovery file.
    // Once claimed by the writer, a later edit receives a new ordered slot.
    private final class Pending: @unchecked Sendable {
        var request: Checkpoint // Accessed only under pendingLock.
        init(_ request: Checkpoint) { self.request = request }
    }
    private struct CheckpointKey: Hashable {
        // The same raw UTF-8 inputs used by location(), without constructing
        // or hashing an Application Support filename on the typing thread.
        let path: Data
        let windowID: Data
    }
    private static let pendingLock = NSLock()
    private static var pending: [CheckpointKey: Pending] = [:]
    // Typing enqueues a checkpoint per keystroke; resolve the vault root's
    // links once per root instead of walking its path on every edit.
    private static var canonicalRoot: (root: String, canonical: URL)?
    private static func canonical(_ root: URL) -> URL {
        let key = root.standardizedFileURL.path
        pendingLock.lock(); defer { pendingLock.unlock() }
        if let canonicalRoot, canonicalRoot.root.utf8.elementsEqual(key.utf8) { return canonicalRoot.canonical }
        let value = root.standardizedFileURL.resolvingSymlinksInPath()
        canonicalRoot = (key, value)
        return value
    }
    static func enqueueCheckpoint(root: URL, note: NoteDocument, body: String, windowID: String, onFailure: @escaping @Sendable (String) -> Void) {
        let canonical = canonical(root)
        let key = CheckpointKey(path: Data((canonical.standardizedFileURL.path + "/" + note.path).utf8), windowID: Data(windowID.utf8))
        let request = Checkpoint(root: canonical, note: note, body: body, windowID: windowID, onFailure: onFailure)
        pendingLock.lock(); defer { pendingLock.unlock() }
        if let slot = pending[key] { slot.request = request; return }
        let slot = Pending(request); pending[key] = slot
        checkpointQueue.async {
            pendingLock.lock()
            let request = slot.request
            if pending[key] === slot { pending.removeValue(forKey: key) }
            pendingLock.unlock()
            do { try writeCheckpoint(root: request.root, note: request.note, body: request.body, windowID: request.windowID) }
            catch { request.onFailure(error.localizedDescription) }
        }
    }
    private static func enqueueBarrier(_ completed: @escaping @Sendable () -> Void) {
        pendingLock.lock(); defer { pendingLock.unlock() }
        // Later edits must not merge into a slot before a read/save/close
        // boundary. Existing queued slots keep their requests and FIFO order.
        pending.removeAll(keepingCapacity: true)
        checkpointQueue.async(execute: completed)
    }
    static func waitForCheckpoints() async {
        await withCheckedContinuation { continuation in
            enqueueBarrier { continuation.resume() }
        }
    }
    static func flushCheckpoints() {
        let barrier = DispatchGroup(); barrier.enter()
        enqueueBarrier { barrier.leave() }
        barrier.wait()
    }

    static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/Drafts", isDirectory: true) }
    static func location(root: URL, path: String, windowID: String? = nil) -> URL {
        let key = NativeHistory.hash(root.standardizedFileURL.path + "/" + path)
        return directory.appendingPathComponent(key + (windowID.map { "-" + $0 } ?? "") + ".json")
    }
    /// Include unreadable matching files so moving a note fails closed.
    static func locations(root: URL, path: String) throws -> [URL] {
        flushCheckpoints()
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "The private drafts folder is a link.") }
        let roots = Set([root.standardizedFileURL, root.standardizedFileURL.resolvingSymlinksInPath()])
        let keys = roots.map { NativeHistory.hash($0.path + "/" + path) }
        // Note activation needs only matching recovery filenames. Avoid
        // constructing and decomposing a file URL for every unrelated draft.
        let folder = directory
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { name in
            keys.contains { name == $0 + ".json" || (name.hasPrefix($0 + "-") && name.hasSuffix(".json")) }
        }.map { folder.appendingPathComponent($0) }
    }
    static func checkpoint(root: URL, note: NoteDocument, body: String, windowID: String) throws {
        flushCheckpoints()
        try checkpointQueue.sync { try writeCheckpoint(root: root, note: note, body: body, windowID: windowID) }
    }
    private static func writeCheckpoint(root: URL, note: NoteDocument, body: String, windowID: String) throws {
        let manager = FileManager.default, canonical = root.standardizedFileURL.resolvingSymlinksInPath()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "The private drafts folder is a link.") }
        let file = location(root: canonical, path: note.path, windowID: windowID)
        let bytes = try JSONSerialization.data(withJSONObject: ["baseline": note.content, "body": body, "path": note.path, "vaultRoot": canonical.path, "windowID": windowID])
        try bytes.write(to: file, options: .atomic)
        guard try Data(contentsOf: file) == bytes else { throw VaultFailure(message: "The recovery checkpoint could not be verified.") }
    }
    static func snapshot(root: URL, notePath: String? = nil) throws -> MacNoteRecoverySnapshot {
        flushCheckpoints()
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return .init() }
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "The private drafts folder is a link. Its files are kept; reconnect the original folder before reviewing recovery.") }
        let canonical = root.standardizedFileURL.resolvingSymlinksInPath()
        var result = MacNoteRecoverySnapshot()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        // Automatic note opening needs only that note's established draft
        // filenames. Full recovery review still inventories every draft and
        // reports unreadable files. Never decode unrelated vaults on open.
        let candidates = try notePath.map { try locations(root: root, path: $0) }
            ?? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
        for file in candidates where file.pathExtension == "json" {
            try Task.checkCancellation()
            do {
                let values = try file.resourceValues(forKeys: keys)
                guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 32_000_000 else { throw VaultFailure(message: "Unreadable draft") }
                let bytes = try Data(contentsOf: file)
                guard let raw = try NativeJSON.object(with: bytes) as? [String: String], let path = raw["path"], let baseline = raw["baseline"], let body = raw["body"],
                      !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { throw VaultFailure(message: "Unreadable draft") }
                if let notePath, !path.utf8.elementsEqual(notePath.utf8) { continue }
                let owner = raw["vaultRoot"].map { URL(fileURLWithPath: $0).standardizedFileURL } ?? root.standardizedFileURL
                guard owner.resolvingSymlinksInPath() == canonical,
                      (raw["windowID"] == nil || UUID(uuidString: raw["windowID"]!) != nil),
                      file == location(root: owner, path: path, windowID: raw["windowID"]) else { continue }
                let note = NoteDocument(path: path, content: baseline, modified: values.contentModificationDate ?? .distantPast)
                result.records.append(.init(windowID: raw["windowID"], file: file, bytes: bytes, vault: canonical, note: note, body: body, modified: note.modified))
            } catch is CancellationError { throw CancellationError() }
            catch { result.warnings.append("A private note draft could not be read and was kept unchanged.") }
        }
        result.records.sort { $0.modified > $1.modified }
        result.warnings = Array(Set(result.warnings)).sorted()
        return result
    }
    static func export(_ record: MacNoteRecoveryRecord, root: URL, to destination: URL) throws {
        flushCheckpoints()
        guard record.vault == root.standardizedFileURL.resolvingSymlinksInPath(),
              record.file.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              try record.file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]).isSymbolicLink != true,
              try Data(contentsOf: record.file) == record.bytes else { throw VaultFailure(message: "This recovery draft or vault changed. Refresh before exporting; the saved draft is kept.") }
        let target = destination.standardizedFileURL.resolvingSymlinksInPath(), vault = root.standardizedFileURL.resolvingSymlinksInPath()
        guard !target.pathComponents.starts(with: vault.pathComponents), !target.pathComponents.starts(with: directory.resolvingSymlinksInPath().pathComponents) else { throw VaultFailure(message: "Export outside the vault and private drafts folder so the original files stay unchanged.") }
        let bytes = Data(record.content.utf8)
        try bytes.write(to: destination, options: .atomic)
        guard try Data(contentsOf: destination) == bytes else { throw VaultFailure(message: "The exported text could not be verified. The private recovery draft is kept.") }
    }
}
