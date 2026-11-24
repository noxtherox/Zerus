import Foundation

struct MacWebAgentImportPlan: Sendable {
    let runID: UUID
    let change: VaultFileChange
    let dependencies: [VaultFileChange]
    let reimport: Bool
}
enum MacWebAgentImportIndex {
    static let directory = ".zerus/native-ai/web-imports"
    static func path(_ source: String) -> String { directory + "/" + NativeHistory.hash(source) + ".json" }
}
private struct MacWebAgentImportStatus: Decodable {
    let version: Int
    let sourcePath: String
    let sourceDigest: String
    let runID: UUID
    let state: String
}

extension VaultFiles {
    private func webImportData(_ path: String, maximum: Int) throws -> Data? {
        let url = try url(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= maximum else { throw VaultFailure(message: "The saved web import status or archive is unsupported. It was kept unchanged.") }
        let bytes = try read(path)
        guard bytes.count <= maximum else { throw VaultFailure(message: "The saved web import metadata exceeds its size allowance. It was kept unchanged.") }
        return bytes
    }
    private func webImportStatus(_ source: String) throws -> (bytes: Data, value: MacWebAgentImportStatus)? {
        guard let bytes = try webImportData(MacWebAgentImportIndex.path(source), maximum: 64_000) else { return nil }
        let value: MacWebAgentImportStatus
        do { value = try JSONDecoder().decode(MacWebAgentImportStatus.self, from: bytes) }
        catch { throw VaultFailure(message: "The saved web import status is unreadable or newer. Restore it before continuing; no files were changed.") }
        guard value.version == 1, value.sourcePath == source, ["active", "deleted"].contains(value.state), value.sourceDigest.count == 64, value.sourceDigest.allSatisfy(\.isHexDigit) else { throw VaultFailure(message: "The saved web import status is unsupported. It was kept unchanged.") }
        return (bytes, value)
    }
    private func webImportDocument(source: String, digest: String, id: UUID, state: String, previous: Data?) throws -> Data {
        var object = try previous.map { try NativeJSON.object(with: $0) as! [String: Any] } ?? [:]
        object["version"] = 1; object["sourcePath"] = source; object["sourceDigest"] = digest.lowercased()
        object["runID"] = id.uuidString.lowercased(); object["state"] = state; object["updatedAt"] = NativeRevisionIndex.timestamp()
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard bytes.count <= 64_000 else { throw VaultFailure(message: "The native web import status would exceed its size allowance. No files were changed.") }
        return bytes
    }
    func prepareMacWebAgentImportIndex(_ source: MacWebAgentRunRecord) throws -> MacWebAgentImportPlan {
        try recoverTransactions()
        let prior = try webImportStatus(source.path), legacy = MacWebAgentRun.nativeID(source.id)
        if prior?.value.state == "active" { throw VaultFailure(message: "This web run is already imported. Open its saved native run, or delete that journal before importing again. Wait for vault sync if the run is not visible yet.") }
        let retired = Set([legacy] + (prior.map { [$0.value.runID] } ?? []))
        for id in retired where FileManager.default.fileExists(atPath: try url(for: NativeAgentJournal.path(id)).path) {
            throw VaultFailure(message: "This web run is already imported or its retired journal is still syncing. Open or remove that native journal before importing again.")
        }
        var id = UUID()
        while true {
            let paths = [NativeAgentJournal.path(id), ".zerus/native-ai/web-sources/" + id.uuidString.lowercased() + ".json"]
            let occupied = try paths.contains { FileManager.default.fileExists(atPath: try url(for: $0).path) }
            if !retired.contains(id), !occupied { break }
            id = UUID()
        }
        let path = MacWebAgentImportIndex.path(source.path)
        let after = try webImportDocument(source: source.path, digest: source.digest, id: id, state: "active", previous: prior?.bytes)
        // Old clients require this exact legacy archive path to be absent when
        // importing. Reserve it without altering an older preserved source.
        let legacyArchive = ".zerus/native-ai/web-sources/" + legacy.uuidString.lowercased() + ".json"
        let before = try webImportData(legacyArchive, maximum: 64 * 1024 * 1024)
        let guards = retired.sorted { $0.uuidString < $1.uuidString }.map { VaultFileChange(path: NativeAgentJournal.path($0), before: nil, after: nil) }
        return .init(runID: id, change: .init(path: path, before: prior?.bytes, after: after), dependencies: guards + [.init(path: legacyArchive, before: before, after: before ?? source.bytes)], reimport: prior != nil || before != nil)
    }
    func validateMacWebAgentImportIndex(_ plan: MacWebAgentImportPlan) throws {
        guard try webImportData(plan.change.path, maximum: 64_000) == plan.change.before else { throw VaultFailure(message: "Another import or deletion changed this web run after review. Reopen saved runs before importing.") }
    }
    /// A missing active journal can be a partial sync, not a deletion. Only an
    /// explicit deleted status releases the source for another reviewed import.
    func macWebAgentImportGuard(_ run: NativeAgentRun) throws -> VaultFileChange? {
        guard let source = run.webMigration else { return nil }
        let path = MacWebAgentImportIndex.path(source.sourcePath), status = try webImportStatus(source.sourcePath)
        guard let status else {
            guard run.version < 7 else { throw VaultFailure(message: "This imported run's status is not yet available. Wait for vault sync or restore its import status before continuing.") }
            return .init(path: path, before: nil, after: nil)
        }
        guard status.value.state == "active", status.value.runID == run.id, status.value.sourceDigest.lowercased() == source.sourceDigest.lowercased() else { throw VaultFailure(message: "This imported run was deleted or replaced. Reopen saved runs before continuing; nothing was executed.") }
        return .init(path: path, before: status.bytes, after: status.bytes)
    }
    func deleteMacWebAgentImportIndex(_ record: NativeAgentRecord) throws -> [VaultFileChange] {
        guard let source = record.run.webMigration else { return [] }
        let path = MacWebAgentImportIndex.path(source.sourcePath), prior = try webImportStatus(source.sourcePath)
        if let prior, prior.value.runID != record.id || prior.value.state == "deleted" {
            // Removing a resurrected retired journal must not release its replacement.
            return [.init(path: path, before: prior.bytes, after: prior.bytes)]
        }
        if let prior, prior.value.sourceDigest.lowercased() != source.sourceDigest.lowercased() { throw VaultFailure(message: "The web import status changed. Reopen its latest native run before deleting it.") }
        let after = try webImportDocument(source: source.sourcePath, digest: source.sourceDigest, id: record.id, state: "deleted", previous: prior?.bytes)
        return [.init(path: path, before: prior?.bytes, after: after)]
    }
}
