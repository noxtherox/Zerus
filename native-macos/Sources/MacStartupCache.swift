import Foundation
import Darwin

/// Location alone is not a vault identity: a different directory may later
/// occupy it. Cache misses remain ordinary cold opens.
struct MacStartupIdentity: Codable, Equatable, Sendable {
    let path: String
    let device: UInt64
    let inode: UInt64
    let created: Date
    let volume: String?
    /// Private drafts follow this directory across a rename, not a path later
    /// occupied by another vault. Copies retain different directory identities.
    var taskDraftID: UUID {
        let location = volume.map { "volume:" + $0.lowercased() } ?? "device:\(device)"
        let key = "zerus.mac.task-drafts.v1|\(location)|\(inode)|\(created.timeIntervalSince1970.bitPattern)"
        let hex = Array(NativeHistory.hash(key).prefix(32))
        // SHA-256 supplies exactly 32 hexadecimal characters for this UUID.
        let value = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }.joined(separator: "-")
        return UUID(uuidString: value)!
    }
    static func read(_ root: URL) throws -> Self? {
        let url = root.resolvingSymlinksInPath().standardizedFileURL
        // Identity needs directory metadata only; Foundation also fetches
        // extended attributes, which can stall even a local cold open.
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_ino != 0 else { return nil }
        let created = Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec) + Double(info.st_birthtimespec.tv_nsec) / 1_000_000_000)
        let volume = try url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        return .init(path: url.path, device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(info.st_ino), created: created, volume: volume)
    }
}

struct MacStartupSnapshot: Sendable {
    let snapshot: VaultSnapshot
    var schema: Data?
    var views: Data?
    var tasks: Data?
}

/// This is disposable device state. Only complete UTF-8 note bodies enter the
/// cache; no list snippet can become an editor or a compare-and-swap baseline.
actor MacStartupCache {
    static let shared = MacStartupCache()
    static let maximumBodyBytes = 128 * 1024 * 1024
    private static let maximumFileBytes = 192 * 1024 * 1024
    nonisolated static var directory: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/Startup", isDirectory: true) }
    nonisolated static func location(_ root: URL) -> URL { directory.appendingPathComponent(NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.path) + ".plist") }
    private struct Note: Codable, Equatable { let path: String; let body: Data; let modified: Date; let created: Date? }
    private struct File: Codable, Equatable { let path: String; let modified: Date; let created: Date? }
    private struct Payload: Codable, Equatable {
        var version = 1
        let identity: MacStartupIdentity
        let notes: [Note]
        let files: [File]
        let folders: [String]
        var folderIconBytes: Data?
        var folderIssue: String?
        let schema: Data?
        let views: Data?
        let tasks: Data?
    }
    private var latest: [String: UInt64] = [:]
    private var previous: Payload?
    private func safeDirectory() throws {
        let manager = FileManager.default
        for url in [Self.directory.deletingLastPathComponent(), Self.directory] {
            if manager.fileExists(atPath: url.path), try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw VaultFailure(message: "The startup cache folder is a link.") }
            try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    private func valid(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count < 4096 && !path.hasPrefix("/") && !path.contains("\\") && !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
    func invalidate(_ root: URL) {
        let path = root.resolvingSymlinksInPath().standardizedFileURL.path
        latest[path] = DispatchTime.now().uptimeNanoseconds
        if previous?.identity.path == path { previous = nil }
        try? FileManager.default.removeItem(at: Self.location(root))
    }
    func load(_ identity: MacStartupIdentity) -> MacStartupSnapshot? {
        let root = URL(fileURLWithPath: identity.path), file = Self.location(root)
        previous = nil
        do {
            try safeDirectory()
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= Self.maximumFileBytes else { return nil }
            let payload = try PropertyListDecoder().decode(Payload.self, from: Data(contentsOf: file))
            guard payload.version == 1, payload.identity == identity, payload.notes.count <= 100_000, payload.files.count <= 100_000, payload.folders.count <= 100_000 else { return nil }
            var seen = Set<String>(), size = 0, notes: [NoteDocument] = []
            for note in payload.notes {
                size += note.body.count
                guard size <= Self.maximumBodyBytes, valid(note.path), note.path.lowercased().hasSuffix(".md"), seen.insert(note.path).inserted,
                      note.modified.timeIntervalSinceReferenceDate.isFinite, note.created?.timeIntervalSinceReferenceDate.isFinite != false,
                      let content = NoteDocument.decodeUTF8(note.body) else { return nil }
                notes.append(.init(path: note.path, content: content, modified: note.modified, created: note.created))
            }
            guard Set(payload.files.map(\.path)).count == payload.files.count, payload.files.allSatisfy({ valid($0.path) && !seen.contains($0.path) && $0.modified.timeIntervalSinceReferenceDate.isFinite && $0.created?.timeIntervalSinceReferenceDate.isFinite != false }), payload.folders.allSatisfy(valid) else { return nil }
            if let bytes = payload.folderIconBytes { _ = try MacFolderIconSnapshot(root: root, bytes: bytes) }
            // Decode known metadata through its normal reader before showing it.
            if let schema = payload.schema { _ = try NativePropertyDefinition.effective(path: "note.md", data: schema) }
            if let views = payload.views { guard try NativeJSON.object(with: views) is [String: Any] else { return nil } }
            if let tasks = payload.tasks { _ = try NativeTaskData(tasks) }
            guard try MacStartupIdentity.read(root) == identity else { return nil }
            previous = payload
            return .init(snapshot: .init(notes: notes.sorted { $0.modified > $1.modified }, files: payload.files.map(\.path), fileDates: Dictionary(uniqueKeysWithValues: payload.files.map { ($0.path, .init(modified: $0.modified, created: $0.created)) }), folders: payload.folders, folderIssue: payload.folderIssue, macFolderIconBytes: payload.folderIconBytes), schema: payload.schema, views: payload.views, tasks: payload.tasks)
        } catch { return nil }
    }
    func store(_ value: MacStartupSnapshot, identity: MacStartupIdentity, requested: UInt64) {
        guard requested >= (latest[identity.path] ?? 0) else { return }
        latest[identity.path] = requested
        do {
            guard try MacStartupIdentity.read(URL(fileURLWithPath: identity.path)) == identity,
                  value.snapshot.notes.count <= 100_000, value.snapshot.files.count <= 100_000, value.snapshot.folders.count <= 100_000 else { return }
            var size = 0, records: [Note] = []
            for note in value.snapshot.notes {
                let body = Data(note.content.utf8); size += body.count
                guard size <= Self.maximumBodyBytes else { invalidate(URL(fileURLWithPath: identity.path)); return }
                records.append(.init(path: note.path, body: body, modified: note.modified, created: note.created))
            }
            let payload = Payload(identity: identity, notes: records.sorted { $0.path < $1.path }, files: value.snapshot.files.map { path in .init(path: path, modified: value.snapshot.fileDates[path]?.modified ?? .distantPast, created: value.snapshot.fileDates[path]?.created) }, folders: value.snapshot.folders, folderIconBytes: value.snapshot.macFolderIconBytes, folderIssue: value.snapshot.folderIssue, schema: value.schema, views: value.views, tasks: value.tasks)
            let file = Self.location(URL(fileURLWithPath: identity.path))
            if payload == previous, FileManager.default.fileExists(atPath: file.path) { return }
            try safeDirectory()
            if FileManager.default.fileExists(atPath: file.path), try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { return }
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let bytes = try encoder.encode(payload)
            guard bytes.count <= Self.maximumFileBytes, try MacStartupIdentity.read(URL(fileURLWithPath: identity.path)) == identity else { return }
            try bytes.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path); previous = payload
        } catch { /* Cache failure must never fail a canonical vault operation. */ }
    }
}

extension VaultFiles {
    func macPrepareStartup() throws -> Bool {
        let folder = try url(for: ".zerus/native-folder-renames")
        let hadPendingRename: Bool
        if FileManager.default.fileExists(atPath: folder.path) {
            hadPendingRename = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).contains { $0.pathExtension == "json" }
        } else { hadPendingRename = false }
        try recoverTransactions()
        return hadPendingRename
    }
    func macReadStartupNote(_ path: String) throws -> NoteDocument {
        let bytes = try read(path), values = try url(for: path).resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        guard let content = NoteDocument.decodeUTF8(bytes) else { throw VaultFailure(message: "The saved note is not UTF-8.") }
        return .init(path: path, content: content, modified: values.contentModificationDate ?? .distantPast, created: values.creationDate)
    }
}
