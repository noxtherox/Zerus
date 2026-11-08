import Foundation

struct NativeFolderTrashRecord: Codable, Sendable {
    enum Phase: String, Codable, Sendable { case movingToTrash, trashed, restoring, purging }
    let version: Int
    let id: UUID
    let folder: String
    let deletedAt: Date
    let tree: NativeFolderTree
    let notes: [String]
    let metadata: [VaultFileChange]
    var phase: Phase
    var directory: String { ".zerus/native-folder-trash/" + id.uuidString.lowercased() }
    var path: String { directory + "/record.json" }
    var pendingPath: String { ".zerus/native-folder-trash-pending/" + id.uuidString.lowercased() + ".json" }
    var files: String { directory + "/files" }
}
struct NativeFolderTrashEntry: Identifiable, Sendable {
    let record: NativeFolderTrashRecord
    let bytes: Data
    var id: UUID { record.id }
}
struct NativeFolderTrashSnapshot: Sendable {
    let root: URL
    let entries: [NativeFolderTrashEntry]
    let issues: [String]
}
struct NativeFolderTrashPlan: Identifiable, Sendable {
    enum Action: Sendable { case trash, restore, purge }
    let id = UUID()
    let root: URL
    let action: Action
    let entry: NativeFolderTrashEntry
    let changes: [VaultFileChange]
    var workspaceID: UUID?
}

extension VaultFiles {
    private static var folderMetadataPaths: [String] { [".zerus/properties.json", ".zerus/type-icons.json", ".zerus/views.json", ".zerus/saved-views.json"] }
    private nonisolated static func folderOwns(_ key: String, folder: String) -> Bool { key == folder || key.hasPrefix(folder + "/") }
    private nonisolated static func folderMetadata(_ bytes: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "Folder settings use an unsupported format. Their original file is preserved.") }
        return object
    }
    private nonisolated static func folderJSON(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) }
    private func checkedFolderTrash(_ bytes: Data, path: String) throws -> NativeFolderTrashRecord {
        let value = try JSONDecoder().decode(NativeFolderTrashRecord.self, from: bytes)
        guard value.version == 1, value.path == path, try NativeFolderPath.clean(value.folder) == value.folder,
              value.tree.directories.contains(""), value.tree.files.values.allSatisfy({ $0.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil }),
              value.deletedAt.timeIntervalSince1970.isFinite, Set(value.metadata.map(\.path)).count == value.metadata.count,
              value.metadata.allSatisfy({ Self.folderMetadataPaths.contains($0.path) && $0.before != nil && $0.after != nil }) else { throw VaultFailure(message: "A folder Trash record uses an unsupported format. Its files and settings are preserved.") }
        for change in value.metadata {
            let original = try Self.folderMetadata(change.before!), removed = original.filter { !Self.folderOwns($0.key, folder: value.folder) }
            guard NSDictionary(dictionary: removed).isEqual(to: try Self.folderMetadata(change.after!)) else { throw VaultFailure(message: "A folder Trash record contains unsupported settings changes and is preserved.") }
        }
        return value
    }
    private nonisolated static func folderTrashBytes(_ record: NativeFolderTrashRecord) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(record)
    }
    func folderTrashSnapshot() throws -> NativeFolderTrashSnapshot {
        try recoverTransactions()
        let path = ".zerus/native-folder-trash", directory = try NativeFolderPath.location(path, root: root)
        guard FileManager.default.fileExists(atPath: directory.path) else { return .init(root: root, entries: [], issues: []) }
        var entries: [NativeFolderTrashEntry] = [], issues: [String] = []
        for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where UUID(uuidString: child.lastPathComponent) != nil {
            let recordPath = path + "/" + child.lastPathComponent + "/record.json"
            do {
                _ = try NativeFolderPath.location(recordPath, root: root)
                guard let bytes = try historyData(recordPath) else { continue }
                let record = try checkedFolderTrash(bytes, path: recordPath)
                guard record.phase == .trashed else { throw VaultFailure(message: "This folder archive needs recovery before it can be restored.") }
                entries.append(.init(record: record, bytes: bytes))
            } catch { issues.append("Folder archive " + child.lastPathComponent + ": " + error.localizedDescription) }
        }
        return .init(root: root, entries: entries.sorted { $0.record.deletedAt > $1.record.deletedAt }, issues: issues.sorted())
    }
    /// Only unfinished receipts participate in ordinary save recovery. Retained
    /// manifests can be large or from newer versions and are read by Trash UI.
    func finishFolderTrash() throws {
        let pendingDirectory = try NativeFolderPath.location(".zerus/native-folder-trash-pending", root: root)
        guard FileManager.default.fileExists(atPath: pendingDirectory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            let path = ".zerus/native-folder-trash/" + id.uuidString.lowercased() + "/record.json"
            let pendingPath = ".zerus/native-folder-trash-pending/" + file.lastPathComponent
            _ = try NativeFolderPath.location(pendingPath, root: root)
            let bytes = try read(pendingPath), record = try checkedFolderTrash(bytes, path: path)
            guard record.pendingPath == pendingPath, record.phase != .trashed else { throw VaultFailure(message: "An unsupported pending folder record is kept for recovery.") }
            let recordURL = try NativeFolderPath.location(record.path, root: root), stored = try NativeFolderPath.location(record.files, root: root)
            var completed = record; completed.phase = .trashed
            let completedBytes = try Self.folderTrashBytes(completed), originalRoot = root
            if record.phase == .purging {
                try Self.coordinateTransaction(locations: [stored, recordURL, file], root: root) { urls in
                    guard try Data(contentsOf: urls[2]) == bytes else { throw VaultFailure(message: "The folder cleanup record changed. Reopen the vault before continuing.") }
                    if let current = try Self.existingData(urls[1]) {
                        guard try Self.folderTrashBytes(JSONDecoder().decode(NativeFolderTrashRecord.self, from: current)) == completedBytes else { throw VaultFailure(message: "The deleted folder record changed. Its remaining files are preserved.") }
                    } else if FileManager.default.fileExists(atPath: urls[0].path) { throw VaultFailure(message: "The deleted folder record is missing. Its remaining files and pending cleanup are preserved.") }
                    if FileManager.default.fileExists(atPath: urls[0].path) {
                        let remaining = try NativeFolderTree.inspect(record.files, root: originalRoot)
                        guard remaining.files.allSatisfy({ record.tree.files[$0.key] == $0.value }), Set(remaining.directories).isSubset(of: Set(record.tree.directories)) else { throw VaultFailure(message: "Files changed during folder cleanup. Remaining files and their record are kept; reconnect the reviewed files before retrying.") }
                        try FileManager.default.removeItem(at: urls[0])
                    }
                    if FileManager.default.fileExists(atPath: urls[1].path) { try FileManager.default.removeItem(at: urls[1]) }
                    try FileManager.default.removeItem(at: urls[2])
                }
                continue
            }
            let original = try NativeFolderPath.location(record.folder, root: root), restoring = record.phase == .restoring
            let from = restoring ? stored : original, to = restoring ? original : stored
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.coordinateTransaction(locations: [from, to, recordURL, file], root: root) { urls in
                guard try Data(contentsOf: urls[3]) == bytes else { throw VaultFailure(message: "The folder recovery record changed. Reopen the vault before continuing.") }
                let archive = try Self.existingData(urls[2])
                if let archive {
                    guard try Self.folderTrashBytes(JSONDecoder().decode(NativeFolderTrashRecord.self, from: archive)) == completedBytes else { throw VaultFailure(message: "The folder archive record changed. Its files and pending operation are preserved.") }
                    if !restoring {
                        // The move and final manifest were committed before a
                        // termination; only the small pending receipt remains.
                        try FileManager.default.removeItem(at: urls[3]); return
                    }
                }
                let sourceExists = FileManager.default.fileExists(atPath: urls[0].path), targetExists = FileManager.default.fileExists(atPath: urls[1].path)
                if sourceExists, !targetExists {
                    guard !restoring || archive != nil else { throw VaultFailure(message: "The folder archive record is missing. Its files and pending restoration are kept.") }
                    guard try NativeFolderTree.inspect(restoring ? record.files : record.folder, root: originalRoot) == record.tree else { throw VaultFailure(message: "The confirmed folder change is waiting because its reviewed files changed. All files and its record are kept. Restore the reviewed files in Files, then reopen this vault.") }
                    try FileManager.default.moveItem(at: urls[0], to: urls[1])
                } else if !sourceExists, targetExists {
                    guard try NativeFolderTree.inspect(restoring ? record.folder : record.files, root: originalRoot) == record.tree else { throw VaultFailure(message: "The moved folder changed before recovery finished. Its files and recovery record are kept.") }
                } else { throw VaultFailure(message: "The folder change is waiting for its source or an available destination. Keep both locations in Files and reopen this vault; its record is preserved.") }
                if restoring { if archive != nil { try FileManager.default.removeItem(at: urls[2]) } }
                else { try completedBytes.write(to: urls[2], options: .atomic) }
                try FileManager.default.removeItem(at: urls[3])
            }
        }
    }
    func prepareFolderTrash(_ folder: String) throws -> NativeFolderTrashPlan {
        let snapshot = try scan()
        guard try NativeFolderPath.clean(folder) == folder, snapshot.folders.contains(folder) else { throw VaultFailure(message: "Choose an existing folder in this vault.") }
        let tree = try NativeFolderTree.inspect(folder, root: root)
        var metadata: [VaultFileChange] = [], changes: [VaultFileChange] = []
        for path in Self.folderMetadataPaths {
            let before = try historyData(path)
            var after = before
            if let before {
                let object = try Self.folderMetadata(before), next = object.filter { !Self.folderOwns($0.key, folder: folder) }
                if next.count != object.count { after = try Self.folderJSON(next) }
            }
            let change = VaultFileChange(path: path, before: before, after: after)
            changes.append(change); if before != after { metadata.append(change) }
        }
        let record = NativeFolderTrashRecord(version: 1, id: UUID(), folder: folder, deletedAt: Date(), tree: tree, notes: snapshot.notes.filter { $0.path.hasPrefix(folder + "/") }.map { String($0.path.dropFirst(folder.count + 1)) }.sorted(), metadata: metadata, phase: .movingToTrash)
        let bytes = try Self.folderTrashBytes(record)
        changes.append(.init(path: record.pendingPath, before: nil, after: bytes))
        return .init(root: root, action: .trash, entry: .init(record: record, bytes: bytes), changes: changes)
    }
    func prepareFolderRestore(_ entry: NativeFolderTrashEntry, purge: Bool = false) throws -> NativeFolderTrashPlan {
        try recoverTransactions()
        let record = try checkedFolderTrash(entry.bytes, path: entry.record.path)
        guard record.phase == .trashed, try read(record.path) == entry.bytes else { throw VaultFailure(message: "This deleted folder changed. Reload Recently Deleted.") }
        guard try NativeFolderTree.inspect(record.files, root: root) == record.tree else { throw VaultFailure(message: "The deleted folder changed outside Zerus. Its current files are kept; reconnect the reviewed files before continuing.") }
        var changes: [VaultFileChange] = []
        if !purge {
            let original = try NativeFolderPath.location(record.folder, root: root)
            guard !FileManager.default.fileExists(atPath: original.path) else { throw VaultFailure(message: "A file or folder already exists at \(record.folder). Rename it or move it in Files before restoring; neither copy has been changed.") }
            for saved in record.metadata {
                let current = try historyData(saved.path)
                let before = try Self.folderMetadata(saved.before!), owned = before.filter { Self.folderOwns($0.key, folder: record.folder) }
                var object = try current.map(Self.folderMetadata) ?? [:]
                for (key, value) in owned {
                    guard object[key] == nil || NSDictionary(dictionary: [key: object[key]!]).isEqual(to: [key: value]) else { throw VaultFailure(message: "Folder settings already exist for \(key). Review them in Files before restoring; current settings are preserved.") }
                    object[key] = value
                }
                let after = current == saved.after ? saved.before : try Self.folderJSON(object)
                changes.append(.init(path: saved.path, before: current, after: after))
            }
        }
        var next = record; next.phase = purge ? .purging : .restoring
        changes.append(.init(path: record.path, before: entry.bytes, after: entry.bytes))
        changes.append(.init(path: record.pendingPath, before: nil, after: try Self.folderTrashBytes(next)))
        return .init(root: root, action: purge ? .purge : .restore, entry: entry, changes: changes)
    }
    func applyFolderTrash(_ plan: NativeFolderTrashPlan) throws -> VaultSnapshot {
        guard plan.root == root else { throw VaultFailure(message: "The vault changed. Reload this folder review.") }
        let record = plan.entry.record, originalRoot = root, trashing = plan.action == .trash
        let location = trashing ? record.folder : record.files
        try applyTransaction(plan.changes, validate: {
            guard try NativeFolderTree.inspect(location, root: originalRoot) == record.tree else { throw VaultFailure(message: "Folder files changed since review. Nothing was changed; reload this review.") }
            if plan.action != .purge {
                let destination = try NativeFolderPath.location(trashing ? record.files : record.folder, root: originalRoot)
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw VaultFailure(message: "The destination is now occupied. Nothing was changed; reload this review.") }
            }
        })
        return try scan()
    }
}
