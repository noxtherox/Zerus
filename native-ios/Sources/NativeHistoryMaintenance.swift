import Foundation

struct NativeHistoryConfiguration: Sendable {
    let bytes: Data?
    let enabled: Bool
    let limit: Int?
}
struct NativeHistoryInventory: Equatable, Sendable {
    var records = Set<String>()
    var blobs = Set<String>()
    var metadata = Set<String>()
    var unexpected = Set<String>()
}
struct NativeHistoryGroup: Sendable {
    let id: String
    let title: String
    let versions: [NativeHistoryVersion]
    let problems: [String]
}
struct NativeHistoryMaintenanceSnapshot: Sendable {
    let root: URL
    var workspaceID: UUID?
    let inventory: NativeHistoryInventory
    let notes: [NoteDocument]
    let records: [String: Data]
    let metadata: [String: Data]
    let groups: [NativeHistoryGroup]
    let configuration: NativeHistoryConfiguration
    let localDrafts: [String: Data]
    var problems: [String] { inventory.unexpected.sorted().map { "Linked or unrecognized metadata file preserved: " + $0 } + groups.flatMap(\.problems) }
}
enum NativeHistoryMaintenanceIntent: Sendable {
    case settings(enabled: Bool, limit: Int?), cleanup, clearAll, clearNote(String)
}
struct NativeHistoryMaintenancePlan: Sendable {
    let snapshot: NativeHistoryMaintenanceSnapshot
    let intent: NativeHistoryMaintenanceIntent
    let changes: [VaultFileChange]
    let removedRecords: [String]
    let removedBlobs: [String]
    let warnings: [String]
    var bytesRemoved: Int { changes.filter { $0.after == nil }.reduce(0) { $0 + ($1.before?.count ?? 0) } }
    var keptRemoved: Int { snapshot.groups.flatMap(\.versions).filter { $0.kept && removedRecords.contains($0.path) }.count }
    var unrecognizedRemoved: Int { removedRecords.count - snapshot.groups.flatMap(\.versions).filter { removedRecords.contains($0.path) }.count }
}

extension VaultFiles {
    func historyConfiguration() throws -> NativeHistoryConfiguration {
        let bytes = try historyData(".zerus/history-settings.json")
        guard let bytes else { return .init(bytes: nil, enabled: true, limit: 10) }
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let enabled = NativeRevisions.boolean(object["enabled"]), object["checkpointLimit"] is NSNull || NativeHistory.integer(object["checkpointLimit"]) != nil else { throw VaultFailure(message: "History settings are unsupported. The original settings are preserved.") }
        return .init(bytes: bytes, enabled: enabled, limit: object["checkpointLimit"] is NSNull ? nil : min(100, max(1, NativeHistory.integer(object["checkpointLimit"])!)))
    }
    nonisolated static func historyMaintenanceInventory(root: URL) throws -> NativeHistoryInventory {
        var result = NativeHistoryInventory(), directories = [".zerus"]
        while let directory = directories.popLast() {
            let folder = root.appendingPathComponent(directory)
            _ = try confinedPath(for: folder, root: root)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            let folderValues = try folder.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard folderValues.isSymbolicLink != true else { throw VaultFailure(message: "A linked metadata folder cannot be cleaned safely. Its files are preserved.") }
            for child in try FileManager.default.contentsOfDirectory(at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) {
                let path = directory + "/" + child.lastPathComponent
                let values = try child.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { result.unexpected.insert(path); continue }
                if values.isDirectory == true {
                    if path == ".zerus/native-transactions" || path == ".zerus/files" || path.range(of: #"^\.zerus/revisions/notes/[^/]+/files$"#, options: .regularExpression) != nil { continue }
                    if path.hasPrefix(".zerus/history/blobs/") { result.unexpected.insert(path); continue }
                    directories.append(path); continue
                }
                guard values.isRegularFile == true else { continue }
                if path.hasPrefix(".zerus/history/notes/") {
                    if child.pathExtension == "json" { result.records.insert(path) }
                    else if !child.lastPathComponent.hasPrefix(".") { result.unexpected.insert(path) }
                } else if path.hasPrefix(".zerus/history/blobs/") {
                    if child.lastPathComponent.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil { result.blobs.insert(path) }
                    else if !child.lastPathComponent.hasPrefix(".") { result.unexpected.insert(path) }
                } else if child.pathExtension == "json" { result.metadata.insert(path) }
            }
        }
        return result
    }
    nonisolated static func historyRecoveryDrafts() throws -> [String: Data] {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeDrafts")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [:] }
        var result: [String: Data] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]) where file.pathExtension == "json" {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else { throw VaultFailure(message: "An unreadable recovery draft prevents history cleanup. Its data is preserved.") }
            result[file.lastPathComponent] = try Data(contentsOf: file)
        }
        return result
    }
    func historyMaintenanceSnapshot(includeVersions: Bool = true) throws -> NativeHistoryMaintenanceSnapshot {
        try Task.checkCancellation()
        let notes = try scan().notes, configuration = try historyConfiguration()
        let inventory = try Self.historyMaintenanceInventory(root: root)
        var records: [String: Data] = [:], metadata: [String: Data] = [:], groups: [NativeHistoryGroup] = []
        for path in inventory.records { try Task.checkCancellation(); records[path] = try read(path) }
        for path in inventory.metadata { try Task.checkCancellation(); metadata[path] = try read(path) }
        if includeVersions {
            for (id, entries) in Dictionary(grouping: records.keys, by: { $0.components(separatedBy: "/")[3] }).sorted(by: { $0.key < $1.key }) {
                let matching = notes.filter { $0.stableID == id }
                let title = matching.count == 1 ? matching[0].title : "History · " + id
                let raw = Dictionary(uniqueKeysWithValues: entries.map { ($0, records[$0]!) })
                if NativeHistory.identity(id), entries.allSatisfy({ $0.components(separatedBy: "/").count == 5 }) {
                    let decoded = try historyVersions(noteID: id, records: raw)
                    var problems = decoded.problems.map { title + ": " + $0 }
                    if matching.count > 1 { problems.append(title + ": duplicate live note identities; automatic pruning is suspended.") }
                    groups.append(.init(id: id, title: title, versions: decoded.versions, problems: problems))
                } else { groups.append(.init(id: id, title: title, versions: [], problems: [title + ": unrecognized record layout is preserved during retention changes."])) }
            }
        }
        return .init(root: root, inventory: inventory, notes: notes, records: records, metadata: metadata, groups: groups, configuration: configuration, localDrafts: try Self.historyRecoveryDrafts())
    }
    nonisolated static func validateHistoryMaintenance(_ snapshot: NativeHistoryMaintenanceSnapshot) throws {
        guard try historyRecoveryDrafts() == snapshot.localDrafts else { throw VaultFailure(message: "Recovery drafts changed. Reload the history review before removing files.") }
        guard try historyMaintenanceInventory(root: snapshot.root) == snapshot.inventory else { throw VaultFailure(message: "History or metadata files were added, removed or moved. Reload the review before continuing.") }
        guard try notePathInventory(root: snapshot.root) == Set(snapshot.notes.map(\.path)) else { throw VaultFailure(message: "Notes were added, moved or removed. Reload the history review before continuing.") }
    }
    nonisolated static func notePathInventory(root: URL) throws -> Set<String> {
        var paths = Set<String>(), directories = [""]
        while let directory = directories.popLast() {
            let folder = root.appendingPathComponent(directory).resolvingSymlinksInPath()
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                let path = directory.isEmpty ? file.lastPathComponent : directory + "/" + file.lastPathComponent
                let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true {
                    let allowedHidden = visibleHiddenDirectory(path)
                    if file.lastPathComponent.hasPrefix(".") && !allowedHidden || (directory == ".zerus" || directory == ".trash/.zerus") && !allowedHidden { continue }
                    directories.append(path)
                } else if !file.lastPathComponent.hasPrefix("."), file.pathExtension.lowercased() == "md" { paths.insert(path) }
            }
        }
        return paths
    }

    /// Shared blobs are collected only after inspecting surviving records,
    /// current/trashed notes, deliberate revisions and recovery/audit metadata.
    func historyBlobCleanup(_ original: [VaultFileChange], snapshot: NativeHistoryMaintenanceSnapshot, collectBlobs: Bool = true, blobCandidates: Set<String>? = nil) throws -> (changes: [VaultFileChange], removed: [String], warnings: [String]) {
        var changes = original, known = Set(original.map(\.path)), references: [String] = [], warnings: [String] = []
        var futureRecords = snapshot.records, futureMetadata = snapshot.metadata
        var futureNotes = Dictionary(uniqueKeysWithValues: snapshot.notes.map { ($0.path, Data($0.content.utf8)) })
        for change in original {
            if change.path.hasPrefix(".zerus/history/notes/"), change.path.hasSuffix(".json") { futureRecords[change.path] = change.after }
            else if snapshot.metadata[change.path] != nil || change.path.hasPrefix(".zerus/") && change.path.hasSuffix(".json") && !change.path.hasPrefix(".zerus/history/blobs/") { futureMetadata[change.path] = change.after }
            if (change.path as NSString).pathExtension.lowercased() == "md" { futureNotes[change.path] = change.after }
        }
        let blobPaths = snapshot.inventory.blobs.intersection(blobCandidates ?? snapshot.inventory.blobs)
        let shouldCollect = collectBlobs && !blobPaths.isEmpty
        var canClean = snapshot.inventory.unexpected.isEmpty
        if shouldCollect {
            for (path, data) in futureRecords {
                try Task.checkCancellation()
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], NativeHistory.integer(object["schema"]) == 1, object["images"] is [[String: Any]] else { canClean = false; warnings.append("Unsupported history keeps image files protected: " + path); continue }
                do { references += try Self.retentionStrings(object) }
                catch { canClean = false; warnings.append("Deeply nested history metadata keeps image files protected.") }
            }
            for data in Array(futureMetadata.values) + Array(snapshot.localDrafts.values) {
                try Task.checkCancellation()
                guard let object = try? JSONSerialization.jsonObject(with: data) else { canClean = false; warnings.append("Unreadable metadata keeps history image files protected."); continue }
                do { references += try Self.retentionStrings(object) } catch { canClean = false; warnings.append("Deeply nested metadata keeps history image files protected.") }
            }
            for data in futureNotes.values {
                try Task.checkCancellation()
                guard let text = String(data: data, encoding: .utf8) else { throw VaultFailure(message: "A note is not UTF-8. No history files were removed.") }
                references += try Self.retentionStrings(text)
            }
        }
        for (path, data) in snapshot.records.merging(snapshot.metadata, uniquingKeysWith: { a, _ in a }) where known.insert(path).inserted { changes.append(.init(path: path, before: data, after: data)) }
        for note in snapshot.notes where known.insert(note.path).inserted { let bytes = Data(note.content.utf8); changes.append(.init(path: note.path, before: bytes, after: bytes)) }
        if known.insert(".zerus/history-settings.json").inserted { changes.append(.init(path: ".zerus/history-settings.json", before: snapshot.configuration.bytes, after: snapshot.configuration.bytes)) }
        var removed: [String] = []
        if shouldCollect && canClean {
            for path in blobPaths.sorted() {
                try Task.checkCancellation()
                let hash = (path as NSString).lastPathComponent
                guard !references.contains(where: { $0.contains(hash) }), !known.contains(path) else { continue }
                changes.append(.init(path: path, before: try read(path), after: nil)); removed.append(path)
            }
        } else if shouldCollect { warnings += snapshot.inventory.unexpected.sorted().map { "Unrecognized file prevents image cleanup: " + $0 } }
        return (changes, removed, Array(Set(warnings)).sorted())
    }
    func prepareHistoryMaintenance(_ snapshot: NativeHistoryMaintenanceSnapshot, intent: NativeHistoryMaintenanceIntent) throws -> NativeHistoryMaintenancePlan {
        guard snapshot.root == root else { throw VaultFailure(message: "The vault changed. Reload history settings.") }
        try Self.validateHistoryMaintenance(snapshot)
        var changes: [VaultFileChange] = [], removed = Set<String>(), warnings = snapshot.problems
        switch intent {
        case .settings(let enabled, let limit):
            var object = try snapshot.configuration.bytes.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] } ?? [:]
            object["enabled"] = enabled; object["checkpointLimit"] = limit.map { min(100, max(1, $0)) } as Any? ?? NSNull()
            changes.append(.init(path: ".zerus/history-settings.json", before: snapshot.configuration.bytes, after: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])))
            if enabled, let limit {
                for group in snapshot.groups {
                    guard group.problems.isEmpty, !group.versions.contains(where: \.incomplete) else { warnings.append(group.title + ": incomplete or unsupported versions were preserved."); continue }
                    removed.formUnion(NativeHistory.prunedPaths(group.versions, limit: min(100, max(1, limit))))
                }
            }
        case .clearAll:
            removed = Set(snapshot.records.keys)
            warnings = snapshot.inventory.unexpected.sorted().map { "Unrecognized file remains protected: " + $0 }
        case .clearNote(let id):
            removed = Set(snapshot.records.keys.filter { $0.hasPrefix(".zerus/history/notes/" + id + "/") })
            warnings = snapshot.groups.filter { $0.id != id }.flatMap(\.problems)
        case .cleanup: break
        }
        let recognized = Set(snapshot.groups.flatMap(\.versions).map(\.path))
        let unknown = removed.subtracting(recognized).count
        if unknown > 0 { warnings.append("\(unknown) unsupported version records are included in this deletion. Their saved bytes will be removed; their Keep status cannot be verified.") }
        for path in removed.sorted() { changes.append(.init(path: path, before: snapshot.records[path], after: nil)) }
        let collectBlobs: Bool
        if case .settings = intent { collectBlobs = !removed.isEmpty } else { collectBlobs = true }
        let cleanup = try historyBlobCleanup(changes, snapshot: snapshot, collectBlobs: collectBlobs)
        return .init(snapshot: snapshot, intent: intent, changes: cleanup.changes, removedRecords: removed.sorted(), removedBlobs: cleanup.removed, warnings: Array(Set(warnings + cleanup.warnings)).sorted())
    }
    func applyHistoryMaintenance(_ plan: NativeHistoryMaintenancePlan) throws -> VaultSnapshot {
        guard plan.snapshot.root == root else { throw VaultFailure(message: "The vault changed. Reload history settings.") }
        try Self.validateHistoryMaintenance(plan.snapshot)
        try applyTransaction(plan.changes, historyCleanupSnapshot: plan.snapshot)
        forgetExternalHistory(plan.intent)
        return try scan()
    }
}
