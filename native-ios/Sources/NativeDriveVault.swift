import Foundation
import CryptoKit

struct NativeDriveBaseline: Codable, Sendable {
    var item: NativeDriveItem
    var hash: String?
    var stableID: String?
}
struct NativeDriveSentUpload: Codable, Sendable {
    let id: String
    let hash: String
}
struct NativeDriveVaultState: Codable, Sendable {
    let version: Int
    let selection: NativeDriveFolder
    var ready: Bool
    var baseline: [String: NativeDriveBaseline]
    var pendingFiles: [String: String]
    var pendingFolders: [String: String]
    // Optional for working copies written before sent-byte recovery existed.
    var sentUploads: [String: NativeDriveSentUpload]?
}
struct NativeDriveLocalFile: Sendable {
    let hash: String
    let count: Int
    let stableID: String?
}
struct NativeDriveConflict: Identifiable, Sendable {
    let path: String
    let local: Data?
    let remote: Data?
    let item: NativeDriveItem?
    var id: String { path }
}
struct NativeDriveConflictReview: Identifiable, Sendable {
    let id = UUID()
    let files: [NativeDriveConflict]
}
struct NativeDriveConflictRequired: LocalizedError {
    let review: NativeDriveConflictReview
    var errorDescription: String? { "Some files changed both on this iPhone and in Google Drive. Review both versions before syncing." }
}

extension VaultFiles {
    nonisolated static func driveHash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func driveSnapshot() throws -> [String: NativeDriveLocalFile] {
        try recoverTransactions()
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard let files = FileManager.default.enumerator(at: root.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { throw VaultFailure(message: "The Drive working copy is unavailable.") }
        var result: [String: NativeDriveLocalFile] = [:]
        for case let location as URL in files {
            let values = try location.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw VaultFailure(message: "A link appeared in the private Drive working copy. No sync was attempted.") }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= NativeDriveFiles.downloadLimit else { throw VaultFailure(message: "A Drive working-copy file exceeds the 50 MB limit or is not an ordinary file.") }
            let canonical = try Self.confinedPath(for: location, root: root)
            let path = String(canonical.dropFirst(canonicalRoot.count + 1))
            let bytes = try read(path)
            guard bytes.count <= NativeDriveFiles.downloadLimit else { throw VaultFailure(message: "This working-copy file exceeds the 50 MB limit.") }
            let id = (path as NSString).pathExtension.lowercased() == "md" ? String(data: bytes, encoding: .utf8).flatMap { NoteDocument(path: path, content: $0, modified: .distantPast).stableID } : nil
            result[path] = .init(hash: Self.driveHash(bytes), count: bytes.count, stableID: id)
        }
        return result
    }
    func driveRead(_ path: String, hash: String) throws -> Data {
        let data = try read(path)
        guard Self.driveHash(data) == hash else { throw VaultFailure(message: "The iPhone copy changed while syncing. Its latest writing is kept; sync again.") }
        return data
    }
    /// Initial cache materialization runs before activation. Do not recover a
    /// remote journal until its complete referenced snapshot is downloaded.
    func materializeDriveFile(_ path: String, data: Data, expected: Data?) throws {
        let target = try url(for: path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var error: NSError?, result: Result<Void, Error> = .failure(VaultFailure(message: "The Drive cache could not be prepared."))
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &error) { actual in
            result = Result {
                _ = try Self.confinedPath(for: actual, root: root)
                let current = FileManager.default.fileExists(atPath: actual.path) ? try Data(contentsOf: actual) : nil
                guard current == expected else { throw VaultFailure(message: "The initial Drive copy changed independently. Its writing is preserved.") }
                try data.write(to: actual, options: [.atomic, .completeFileProtection])
            }
        }
        if let error { throw error }; try result.get()
    }
    func applyDriveDates(_ path: String, hash: String, modified: Date?, created: Date?) throws {
        guard modified != nil || created != nil else { return }
        let target = try url(for: path)
        var error: NSError?, result: Result<Void, Error> = .success(())
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forMerging, error: &error) { actual in
            result = Result {
                _ = try Self.confinedPath(for: actual, root: root)
                guard FileManager.default.fileExists(atPath: actual.path), Self.driveHash(try Data(contentsOf: actual)) == hash else { return }
                var attributes: [FileAttributeKey: Any] = [:]
                if let modified { attributes[.modificationDate] = modified }
                if let created { attributes[.creationDate] = created }
                try FileManager.default.setAttributes(attributes, ofItemAtPath: actual.path)
            }
        }
        if let error { throw error }; try result.get()
    }
}

actor NativeDriveVaultRecords {
    let directory: URL
    let root: URL
    private var file: URL { directory.appendingPathComponent("state.json") }
    init(directory: URL) { self.directory = directory; root = directory.appendingPathComponent("Vault", isDirectory: true) }
    private func load() throws -> NativeDriveVaultState? {
        for location in [directory, root] where FileManager.default.fileExists(atPath: location.path) {
            guard try location.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "The private Drive cache was replaced by a link. Its original sync records are preserved.") }
        }
        if FileManager.default.fileExists(atPath: file.path), try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw VaultFailure(message: "The Drive sync record cannot be read safely.") }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(NativeDriveVaultState.self, from: Data(contentsOf: file))
    }
    private func validated(_ state: NativeDriveVaultState, matching selection: NativeDriveFolder) throws -> NativeDriveVaultState {
        _ = try state.selection.validated()
        guard state.version == 1, state.selection.accountID == selection.accountID, state.selection.folderID == selection.folderID else { throw VaultFailure(message: "This Drive working copy belongs to a different account or uses a newer format. Its files are preserved.") }
        for (path, entry) in state.baseline {
            guard NativeFileHub.relative(path) == path, NativeDriveFiles.validID(entry.item.id),
                  entry.hash.map({ $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }) != false else { throw VaultFailure(message: "The saved Drive sync paths are unreadable. Original records are preserved.") }
        }
        for values in [state.pendingFiles, state.pendingFolders] {
            guard values.allSatisfy({ NativeFileHub.relative($0.key) == $0.key && NativeDriveFiles.validID($0.value) }) else { throw VaultFailure(message: "A pending Drive identity record is unreadable. It has been kept unchanged.") }
        }
        for (path, sent) in state.sentUploads ?? [:] {
            guard NativeFileHub.relative(path) == path, NativeDriveFiles.validID(sent.id),
                  sent.hash.utf8.count == 64, sent.hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  state.pendingFiles[path] == sent.id || state.baseline[path]?.item.id == sent.id else { throw VaultFailure(message: "An interrupted Drive upload record is unreadable. Its working copy is preserved.") }
        }
        return state
    }
    func read(_ selection: NativeDriveFolder) throws -> NativeDriveVaultState {
        guard let state = try load() else { return .init(version: 1, selection: selection, ready: false, baseline: [:], pendingFiles: [:], pendingFolders: [:]) }
        return try validated(state, matching: selection)
    }
    func savedSelection() throws -> NativeDriveFolder {
        guard let state = try load(), state.ready else { throw VaultFailure(message: "This Drive working copy has no completed sync record. Its files are kept; open the original Google Drive folder again.") }
        return try validated(state, matching: state.selection).selection
    }
    func save(_ state: NativeDriveVaultState) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: file, options: [.atomic, .completeFileProtection])
    }
}

/// All remote effects follow a durable baseline/identity record. A lost upload
/// acknowledgement is reconciled by identity and bytes on the next pass, never
/// by blindly replaying a mutation. Native note transactions stay in VaultFiles.
@MainActor
final class NativeDriveVault {
    let selection: NativeDriveFolder
    let root: URL
    let io: VaultFiles
    private let records: NativeDriveVaultRecords
    private let client: () async throws -> NativeDriveFiles
    private(set) var busy = false
    private(set) var review: NativeDriveConflictReview?
    static func directory(for selection: NativeDriveFolder) -> URL {
        let key = VaultFiles.driveHash(Data((selection.accountID + ":" + selection.folderID).utf8))
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeDriveVaults/" + key, isDirectory: true)
    }
    /// Only app-owned cache roots can confer a Drive association. Ordinary
    /// selected folders may contain arbitrary state.json files of their own.
    static func savedSelection(for root: URL) async throws -> NativeDriveFolder? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent("NativeDriveVaults", isDirectory: true)
        let rawBase = support.standardizedFileURL.appendingPathComponent("NativeDriveVaults", isDirectory: true)
        let raw = root.standardizedFileURL, canonical = root.resolvingSymlinksInPath().standardizedFileURL
        let rawParent = raw.deletingLastPathComponent().deletingLastPathComponent()
        guard rawParent == base || rawParent == rawBase || canonical.deletingLastPathComponent().deletingLastPathComponent() == base else { return nil }
        do {
            if rawParent == base || rawParent == rawBase {
                for location in [raw.deletingLastPathComponent(), raw] {
                    guard try location.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "The private Drive cache was replaced by a link.") }
                }
            }
            guard canonical.lastPathComponent == "Vault", canonical.deletingLastPathComponent().deletingLastPathComponent() == base,
                  try base.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "The private Drive working-copy location changed.") }
            let selection = try await NativeDriveVaultRecords(directory: canonical.deletingLastPathComponent()).savedSelection()
            let expected = base.appendingPathComponent(directory(for: selection).lastPathComponent, isDirectory: true).appendingPathComponent("Vault", isDirectory: true)
            guard canonical == expected else { throw VaultFailure(message: "The private Drive record belongs to another account or folder.") }
            return selection
        } catch { throw VaultFailure(message: "Couldn’t restore this Google Drive working copy. Its files and sync record are kept. Open the original Drive folder again. " + error.localizedDescription) }
    }
    init(selection: NativeDriveFolder, directory: URL, client: @escaping () async throws -> NativeDriveFiles) throws {
        _ = try selection.validated(); self.selection = selection; self.client = client
        records = NativeDriveVaultRecords(directory: directory); root = directory.appendingPathComponent("Vault", isDirectory: true); io = VaultFiles(root: root)
    }
    private func baseline(_ item: NativeDriveItem, bytes: Data?) -> NativeDriveBaseline {
        let id = bytes.flatMap { String(data: $0, encoding: .utf8) }.flatMap { NoteDocument(path: item.name, content: $0, modified: .distantPast).stableID }
        return .init(item: item, hash: bytes.map(VaultFiles.driveHash), stableID: id)
    }
    private func ordinary(_ item: NativeDriveItem) -> Bool { !item.folder && !item.mimeType.hasPrefix("application/vnd.google-apps.") }
    private func applyDates(_ path: String, entry: NativeDriveBaseline) async throws {
        guard let hash = entry.hash else { return }
        try await io.applyDriveDates(path, hash: hash, modified: entry.item.modifiedTime.flatMap(NativeRevisionIndex.date), created: entry.item.createdTime.flatMap(NativeRevisionIndex.date))
    }
    func prepare() async throws {
        try Task.checkCancellation()
        var state = try await records.read(selection)
        try Task.checkCancellation()
        if state.ready { return }
        guard !busy else { throw VaultFailure(message: "This Drive vault is already opening.") }; busy = true; defer { busy = false }
        let api = try await client(), tree = try await api.tree(selection)
        try await records.save(state)
        // An incomplete initial cache is never activated as a vault. Progress
        // is retained file by file, with expected-byte checks on every retry.
        for path in tree.keys.sorted() {
            try Task.checkCancellation()
            let item = tree[path]!
            guard ordinary(item) else { state.baseline[path] = baseline(item, bytes: nil); continue }
            if let old = state.baseline[path], old.item == item, let hash = old.hash, let current = try? await io.read(path), VaultFiles.driveHash(current) == hash { continue }
            let bytes = try await api.readObserved(item)
            let current = try? await io.read(path)
            guard current == nil || state.baseline[path]?.hash == current.map(VaultFiles.driveHash) else { throw VaultFailure(message: "The incomplete Drive cache has independent edits. They have been kept; reconnect this vault for review.") }
            try await io.materializeDriveFile(path, data: bytes, expected: current)
            state.baseline[path] = baseline(item, bytes: bytes)
            try await applyDates(path, entry: state.baseline[path]!)
            try await records.save(state)
        }
        let fresh = try await api.tree(selection)
        guard fresh == tree else { throw VaultFailure(message: "Google Drive changed while opening this vault. Retry to finish its working copy.") }
        for path in Set(state.baseline.keys).subtracting(tree.keys) {
            if let hash = state.baseline[path]?.hash, let current = try? await io.read(path) {
                guard VaultFiles.driveHash(current) == hash else { throw VaultFailure(message: "An incomplete cached file has independent writing. Its bytes are kept.") }
                try await io.applyTransaction([.init(path: path, before: current, after: nil)], historySource: "drive")
            }
            state.baseline.removeValue(forKey: path)
        }
        state.ready = true; try await records.save(state)
    }
    func sync() async throws -> Bool {
        guard !busy else { return true }; busy = true; defer { busy = false }
        var state = try await records.read(selection)
        guard state.ready else { throw VaultFailure(message: "Finish opening the Drive vault before syncing.") }
        let api = try await client()
        var remote = try await api.tree(selection), local = try await io.driveSnapshot(), dates: [String: NativeDriveBaseline] = [:]
        // A completed move may have lost its HTTP acknowledgement. Adopt it
        // only when the same remote identity has the old or intended bytes.
        for (old, target) in movePairs(state: state, local: local) {
            guard remote[old] == nil, let base = state.baseline[old], let item = remote[target], item.id == base.item.id else { continue }
            let bytes = try await api.readObserved(item), hash = VaultFiles.driveHash(bytes)
            guard hash == base.hash || hash == local[target]?.hash else { continue }
            state.baseline.removeValue(forKey: old); state.sentUploads?.removeValue(forKey: old)
            state.baseline[target] = baseline(item, bytes: bytes)
            dates[target] = state.baseline[target]
        }
        var incoming: [VaultFileChange] = [], conflicts: [NativeDriveConflict] = [], downloaded = 0
        for path in Set(state.baseline.keys).union(remote.keys).union(local.keys).sorted() {
            try Task.checkCancellation()
            let base = state.baseline[path], current = remote[path], own = local[path]
            if let current, !ordinary(current) {
                if own != nil { conflicts.append(.init(path: path, local: try await io.driveRead(path, hash: own!.hash), remote: nil, item: current)) }
                else { state.baseline[path] = baseline(current, bytes: nil); state.sentUploads?.removeValue(forKey: path); state.pendingFiles.removeValue(forKey: path) }
                continue
            }
            let remoteChanged = current?.id != base?.item.id || current?.version != base?.item.version || current?.name != base?.item.name || current?.parents != base?.item.parents
            guard remoteChanged else { continue }
            let bytes: Data?
            if let current { bytes = try await api.readObserved(current) } else { bytes = nil }
            downloaded += bytes?.count ?? 0
            guard downloaded <= 256 * 1024 * 1024 else { throw VaultFailure(message: "This refresh exceeds the native preview's 256 MB change limit. Your current working copy is kept.") }
            let remoteHash = bytes.map(VaultFiles.driveHash)
            let ownBytes: Data?
            if let own { ownBytes = try await io.driveRead(path, hash: own.hash) } else { ownBytes = nil }
            if let current, let sent = state.sentUploads?[path], current.id == sent.id, remoteHash == sent.hash {
                // The service accepted the prior upload, even if its response
                // was lost and writing continued (or the file was removed).
                // Adopt only the sent bytes as the new baseline; the latest
                // local draft/deletion still needs its own conditional write.
                state.baseline[path] = baseline(current, bytes: bytes)
                state.pendingFiles.removeValue(forKey: path); state.sentUploads?.removeValue(forKey: path)
                dates[path] = state.baseline[path]
                continue
            }
            if own?.hash == base?.hash {
                state.sentUploads?.removeValue(forKey: path); state.pendingFiles.removeValue(forKey: path)
                if ownBytes != bytes { incoming.append(.init(path: path, before: ownBytes, after: bytes)) }
                if let current { state.baseline[path] = baseline(current, bytes: bytes) } else { state.baseline.removeValue(forKey: path) }
            } else if own?.hash == remoteHash && (base != nil || current?.id == state.pendingFiles[path]) {
                if let current { state.baseline[path] = baseline(current, bytes: bytes); state.pendingFiles.removeValue(forKey: path); state.sentUploads?.removeValue(forKey: path) } else { state.baseline.removeValue(forKey: path) }
            } else if let base, let current, current.id == base.item.id, remoteHash == base.hash {
                // A Drive metadata/version change with identical body bytes
                // does not conflict with newer local writing. Lock the fresh
                // version for the eventual media-only upload instead.
                state.baseline[path] = baseline(current, bytes: bytes)
            } else { conflicts.append(.init(path: path, local: ownBytes, remote: bytes, item: current)) }
            if let current, let accepted = state.baseline[path], accepted.item == current, accepted.hash == remoteHash { dates[path] = accepted }
        }
        guard conflicts.isEmpty else { let value = NativeDriveConflictReview(files: conflicts); review = value; throw NativeDriveConflictRequired(review: value) }
        if !incoming.isEmpty { try await io.applyTransaction(incoming, historySource: "drive", preservingRemoteBytes: true) }
        for path in dates.keys.sorted() { try await applyDates(path, entry: dates[path]!) }
        try await records.save(state)
        local = try await io.driveSnapshot()
        for (old, target) in movePairs(state: state, local: local) {
            guard let base = state.baseline[old], remote[old]?.id == base.item.id, remote[target] == nil else { continue }
            let parent = try await ensureParent(target, api: api, remote: &remote, state: &state)
            let item = try await api.move(base.item, name: (target as NSString).lastPathComponent, parent: parent, root: selection.folderID)
            state.baseline.removeValue(forKey: old); state.sentUploads?.removeValue(forKey: old)
            state.baseline[target] = .init(item: item, hash: base.hash, stableID: base.stableID)
            try await applyDates(target, entry: state.baseline[target]!)
            remote.removeValue(forKey: old); remote[target] = item
            try await records.save(state)
        }
        let changed = Set(local.keys).union(state.baseline.keys).filter { local[$0]?.hash != state.baseline[$0]?.hash }
        guard changed.allSatisfy({ local[$0]?.count ?? 0 <= NativeDriveFiles.uploadLimit }) else { throw VaultFailure(message: "A pending file exceeds the 25 MB Drive upload limit. Its iPhone copy is kept.") }
        for path in changed.sorted() {
            try Task.checkCancellation()
            let own = local[path], base = state.baseline[path]
            if let own {
                let bytes = try await io.driveRead(path, hash: own.hash)
                let item: NativeDriveItem
                if let base {
                    guard ordinary(base.item) else { throw VaultFailure(message: "A native Google document cannot be overwritten by an iPhone file.") }
                    if state.sentUploads == nil { state.sentUploads = [:] }
                    state.sentUploads?[path] = .init(id: base.item.id, hash: own.hash); try await records.save(state)
                    item = try await api.put(base.item, root: selection.folderID, data: bytes)
                } else {
                    let parent = try await ensureParent(path, api: api, remote: &remote, state: &state)
                    let id: String
                    if let pending = state.pendingFiles[path] { id = pending }
                    else { id = try await api.allocateID(); state.pendingFiles[path] = id }
                    if state.sentUploads == nil { state.sentUploads = [:] }
                    state.sentUploads?[path] = .init(id: id, hash: own.hash); try await records.save(state)
                    item = try await api.create(id: id, name: (path as NSString).lastPathComponent, parent: parent, root: selection.folderID, data: bytes)
                }
                state.baseline[path] = baseline(item, bytes: bytes); state.pendingFiles.removeValue(forKey: path); state.sentUploads?.removeValue(forKey: path); remote[path] = item
                try await applyDates(path, entry: state.baseline[path]!)
            } else if let base, ordinary(base.item) {
                try await api.trash(base.item, root: selection.folderID); state.baseline.removeValue(forKey: path); state.sentUploads?.removeValue(forKey: path); remote.removeValue(forKey: path)
            }
            try await records.save(state)
        }
        review = nil
        let latest = try await io.driveSnapshot()
        return Set(latest.keys).union(state.baseline.keys).contains { latest[$0]?.hash != state.baseline[$0]?.hash }
    }
    private func movePairs(state: NativeDriveVaultState, local: [String: NativeDriveLocalFile]) -> [(String, String)] {
        let old = state.baseline.keys.filter { local[$0] == nil && state.baseline[$0]?.hash != nil && ordinary(state.baseline[$0]!.item) }
        let new = local.keys.filter { state.baseline[$0] == nil }
        func liveNote(_ path: String) -> Bool {
            let parts = path.split(separator: "/").map(String.init)
            guard (path as NSString).pathExtension.lowercased() == "md", parts.last?.hasPrefix(".") == false else { return false }
            return parts.dropLast().enumerated().allSatisfy { index, component in
                !component.hasPrefix(".") || VaultFiles.visibleHiddenDirectory(parts.prefix(index + 1).joined(separator: "/"))
            }
        }
        // Revision/history snapshots are resources, not additional live notes.
        // Prefer a unique live-note identity before considering content hashes.
        let oldIDs = Dictionary(grouping: state.baseline.keys.filter { liveNote($0) && state.baseline[$0]?.stableID != nil }, by: { state.baseline[$0]!.stableID! })
        let newIDs = Dictionary(grouping: local.keys.filter { liveNote($0) && local[$0]?.stableID != nil }, by: { local[$0]!.stableID! })
        var result: [(String, String)] = [], claimedOld = Set<String>(), claimedNew = Set<String>()
        for id in oldIDs.keys.sorted() {
            guard let sources = oldIDs[id], sources.count == 1, let targets = newIDs[id], targets.count == 1,
                  old.contains(sources[0]), new.contains(targets[0]) else { continue }
            result.append((sources[0], targets[0])); claimedOld.insert(sources[0]); claimedNew.insert(targets[0])
        }
        let oldHashes = Dictionary(grouping: old.filter { !claimedOld.contains($0) }, by: { state.baseline[$0]!.hash! })
        let newHashes = Dictionary(grouping: new.filter { !claimedNew.contains($0) }, by: { local[$0]!.hash })
        for hash in oldHashes.keys.sorted() {
            guard let sources = oldHashes[hash], sources.count == 1, let targets = newHashes[hash], targets.count == 1 else { continue }
            result.append((sources[0], targets[0]))
        }
        return result
    }
    private func ensureParent(_ path: String, api: NativeDriveFiles, remote: inout [String: NativeDriveItem], state: inout NativeDriveVaultState) async throws -> String {
        var parent = selection.folderID, prefix = ""
        for component in path.split(separator: "/").dropLast() {
            prefix = prefix.isEmpty ? String(component) : prefix + "/" + component
            if let item = remote[prefix] {
                guard item.folder else { throw VaultFailure(message: "A Drive file occupies a required folder path.") }; parent = item.id
            } else {
                let id: String
                if let pending = state.pendingFolders[prefix] { id = pending }
                else { id = try await api.allocateID(); state.pendingFolders[prefix] = id; try await records.save(state) }
                let folder = try await api.create(id: id, name: String(component), parent: parent, root: selection.folderID, data: nil)
                remote[prefix] = folder; state.baseline[prefix] = baseline(folder, bytes: nil); state.pendingFolders.removeValue(forKey: prefix); try await records.save(state); parent = folder.id
            }
        }
        return parent
    }
    func resolve(_ reviewed: NativeDriveConflictReview, keepLocal: Set<String>) async throws {
        guard !busy, review?.id == reviewed.id else { throw VaultFailure(message: "The Drive review changed. Open it again.") }; busy = true; defer { busy = false }
        let api = try await client(), tree = try await api.tree(selection)
        var state = try await records.read(selection), changes: [VaultFileChange] = []
        for file in reviewed.files {
            guard tree[file.path] == file.item, (try? await io.read(file.path)) == file.local else { throw VaultFailure(message: "One of the reviewed versions changed. Sync again for a fresh review.") }
            guard file.item == nil || ordinary(file.item!) else { throw VaultFailure(message: "A Google document or folder cannot be replaced. Rename the iPhone copy before syncing.") }
            state.sentUploads?.removeValue(forKey: file.path); state.pendingFiles.removeValue(forKey: file.path)
            if !keepLocal.contains(file.path) { changes.append(.init(path: file.path, before: file.local, after: file.remote)) }
            if let item = file.item { state.baseline[file.path] = baseline(item, bytes: file.remote) } else { state.baseline.removeValue(forKey: file.path) }
        }
        // These are reviewed remote bytes, including history/index resources.
        // Native local saves already captured supported drafts in history;
        // synthesizing it here can conflict with a chosen history record.
        if !changes.isEmpty { try await io.applyTransaction(changes, historySource: "drive", preservingRemoteBytes: true) }
        for file in reviewed.files where !keepLocal.contains(file.path) {
            if let entry = state.baseline[file.path] { try await applyDates(file.path, entry: entry) }
        }
        try await records.save(state); review = nil
    }
}
