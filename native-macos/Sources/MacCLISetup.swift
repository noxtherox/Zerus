import Foundation
import Darwin

private func cliASCIIKey(_ value: String) -> String {
    String(decoding: value.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }, as: UTF8.self)
}
private func cliNoteUUID(_ value: String) -> UUID? {
    var value = value
    if value.hasPrefix("urn:uuid:"), value.utf8.count == 45 { value = String(value.dropFirst(9)) }
    else if value.hasPrefix("{"), value.hasSuffix("}"), value.utf8.count == 38 { value = String(value.dropFirst().dropLast()) }
    if value.utf8.count == 32, value.range(of: #"^[0-9a-fA-F]{32}$"#, options: .regularExpression) != nil {
        value = value.enumerated().map { ([8, 12, 16, 20].contains($0.offset) ? "-" : "") + String($0.element) }.joined()
    }
    guard value.range(of: #"^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil else { return nil }
    return UUID(uuidString: value)
}

struct MacCLIRegistryReview: Identifiable, Sendable {
    let id = UUID()
    let file: URL
    let before: Data?
    let after: Data
    let name: String
    let root: URL
    let vaultID: UUID
    let previousPath: String?
    let previousName: String?
    let isDefault: Bool
}

actor MacCLIVaultRegistry {
    static let shared = MacCLIVaultRegistry(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("zerus/vaults.json"))
    let file: URL
    init(file: URL) { self.file = file }
    private func read(_ url: URL) throws -> Data? {
        let info: [FileAttributeKey: Any]
        do { info = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
        guard info[.type] as? FileAttributeType == .typeRegular, ((info[.size] as? NSNumber)?.intValue ?? Int.max) <= 8 * 1024 * 1024 else { throw VaultFailure(message: "The CLI vault registry is not an ordinary file within the supported size. It was kept unchanged.") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 8 * 1024 * 1024 else { throw VaultFailure(message: "The CLI vault registry is too large. It was kept unchanged.") }
        return bytes
    }
    func prepare(root: URL, vaultID: UUID, name: String, makeDefault: Bool) throws -> MacCLIRegistryReview {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 250, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw VaultFailure(message: "Use a vault name of 1–250 characters without control characters.") }
        let before = try read(file)
        var object: [String: Any] = ["version": 1, "vaults": []]
        if let before {
            guard let raw = try NativeJSON.object(with: before) as? [String: Any] else { throw VaultFailure(message: "The CLI vault registry is unreadable. It was kept unchanged.") }
            object = raw
        }
        guard NativeHistory.integer(object["version"]) == 1, var rows = object["vaults"] as? [[String: Any]],
              rows.allSatisfy({ ($0["id"] as? String).flatMap(UUID.init(uuidString:)) != nil && $0["name"] is String && $0["path"] is String }),
              Set(rows.compactMap { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) }).count == rows.count,
              object["defaultVaultId"] == nil || object["defaultVaultId"] is NSNull || (object["defaultVaultId"] as? String).flatMap(UUID.init(uuidString:)) != nil else { throw VaultFailure(message: "The CLI vault registry uses an unsupported format. It was kept unchanged.") }
        guard !rows.contains(where: { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) != vaultID && ($0["name"] as? String).map(cliASCIIKey) == cliASCIIKey(name) }) else { throw VaultFailure(message: "Another registered vault already uses this name. Choose a different name.") }
        let index = rows.firstIndex { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == vaultID }
        let previousPath = index.flatMap { rows[$0]["path"] as? String }
        let previousName = index.flatMap { rows[$0]["name"] as? String }
        var record = index.map { rows[$0] } ?? [:]
        record["id"] = vaultID.uuidString.lowercased(); record["name"] = name; record["path"] = root.resolvingSymlinksInPath().standardizedFileURL.path
        if let index { rows[index] = record } else { rows.append(record) }
        rows.sort { ($0["name"] as? String ?? "").localizedStandardCompare($1["name"] as? String ?? "") == .orderedAscending }
        object["vaults"] = rows
        if makeDefault || object["defaultVaultId"] == nil || object["defaultVaultId"] is NSNull { object["defaultVaultId"] = vaultID.uuidString.lowercased() }
        let isDefault = (object["defaultVaultId"] as? String).flatMap(UUID.init(uuidString:)) == vaultID
        return .init(file: file, before: before, after: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), name: name, root: root, vaultID: vaultID, previousPath: previousPath, previousName: previousName, isDefault: isDefault)
    }
    func validate(_ review: MacCLIRegistryReview) throws {
        guard review.file == file, try read(file) == review.before else { throw VaultFailure(message: "The CLI vaults.json registry changed after review. Refresh and register again; nothing was replaced.") }
    }
    func apply(_ review: MacCLIRegistryReview) throws {
        try Task.checkCancellation(); try validate(review)
        let fm = FileManager.default, folder = file.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var failure: Error?, coordination: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordination) { target in
            do {
                guard try read(target) == review.before else { throw VaultFailure(message: "The CLI vaults.json registry changed after review. Refresh and register again; nothing was replaced.") }
                let temporary = folder.appendingPathComponent(".zerus-registry-" + UUID().uuidString)
                defer { try? fm.removeItem(at: temporary) }
                try review.after.write(to: temporary, options: .withoutOverwriting)
                let mode = (try? fm.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
                try fm.setAttributes([.posixPermissions: mode & 0o777], ofItemAtPath: temporary.path)
                try Task.checkCancellation()
                guard try read(target) == review.before else { throw VaultFailure(message: "The CLI vaults.json registry changed after review. Refresh and register again; nothing was replaced.") }
                let result = review.before == nil ? Darwin.renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) : Darwin.rename(temporary.path, target.path)
                guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            } catch { failure = error }
        }
        if let error = coordination ?? failure as NSError? { throw error }
    }
}

struct MacCLIVaultManifest: Sendable {
    let id: UUID
    let change: VaultFileChange
}
struct MacCLIRegistrationReview: Identifiable, Sendable {
    let id = UUID()
    let workspaceID: UUID
    let root: URL
    let identity: MacAgentFileIdentity
    let manifest: MacCLIVaultManifest
    let registry: MacCLIRegistryReview
}
struct MacCLIMetadataReview: Identifiable, Sendable {
    let id = UUID()
    let workspaceID: UUID
    let root: URL
    let identity: MacAgentFileIdentity
    let notes: [NoteDocument]
    let changes: [VaultFileChange]
    let issues: [String]
    let idsAdded: Int
    let keysRenamed: Int
    var noteChanges: [VaultFileChange] { changes.filter { $0.path.lowercased().hasSuffix(".md") || $0.path.lowercased().hasSuffix(".markdown") }.filter { $0.before != $0.after } }
}

extension VaultFiles {
    func cliVaultManifest(prepared: Bool = false) throws -> MacCLIVaultManifest {
        let path = ".zerus/vault.json", location = try url(for: path)
        let before = FileManager.default.fileExists(atPath: location.path) ? try read(path) : nil
        var object: [String: Any] = ["version": 1, "vaultId": UUID().uuidString.lowercased(), "metadataVersion": 0, "idsRequired": false]
        if let before {
            guard let raw = try NativeJSON.object(with: before) as? [String: Any] else { throw VaultFailure(message: "The vault identity is unreadable. It was kept unchanged.") }
            object = raw
        }
        guard NativeHistory.integer(object["version"]) == 1,
              let id = (object["vaultId"] as? String).flatMap(UUID.init(uuidString:)),
              let metadataVersion = NativeHistory.integer(object["metadataVersion"]), (0...1).contains(metadataVersion),
              NativeRevisions.boolean(object["idsRequired"]) != nil else { throw VaultFailure(message: "The vault identity uses an unsupported format. It was kept unchanged.") }
        let unchanged = before != nil && (!prepared || NativeHistory.integer(object["metadataVersion"]) == 1 && NativeRevisions.boolean(object["idsRequired"]) == true)
        if prepared { object["metadataVersion"] = 1; object["idsRequired"] = true }
        let after = unchanged ? before! : try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return .init(id: id, change: .init(path: path, before: before, after: after))
    }
    /// The CLI counts hidden-name files and both Markdown suffixes, but skips
    /// hidden directories except Trash. Keep setup's inventory at that boundary.
    private func cliNotes() throws -> [NoteDocument] {
        try recoverTransactions()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey, .creationDateKey]
        var directories = [""], notes: [NoteDocument] = []
        while let directory = directories.popLast() {
            try Task.checkCancellation()
            let parent = directory.isEmpty ? root : try url(for: directory)
            for file in try FileManager.default.contentsOfDirectory(at: parent.resolvingSymlinksInPath(), includingPropertiesForKeys: Array(keys)) {
                let values = try file.resourceValues(forKeys: keys), name = file.lastPathComponent
                if values.isSymbolicLink == true { continue }
                let path = directory.isEmpty ? name : directory + "/" + name
                if values.isDirectory == true {
                    if !name.hasPrefix(".") || name == ".trash" { directories.append(path) }
                } else if values.isRegularFile == true, ["md", "markdown"].contains(file.pathExtension.lowercased()) {
                    guard let content = NoteDocument.decodeUTF8(try read(path)) else { throw VaultFailure(message: path + " is not a UTF-8 Markdown file.") }
                    notes.append(.init(path: path, content: content, modified: values.contentModificationDate ?? .distantPast, created: values.creationDate))
                }
            }
        }
        return notes.sorted { $0.path < $1.path }
    }
    func cliMetadataReview(workspaceID: UUID) throws -> MacCLIMetadataReview {
        let identity = try MacAgentFileIdentity(root), notes = try cliNotes()
        var changes: [VaultFileChange] = [], issues: [String] = [], ids: [UUID: String] = [:], added = 0, renamed = 0
        for note in notes {
            try Task.checkCancellation()
            let before = try read(note.path)
            do {
                guard before == Data(note.content.utf8) else { throw VaultFailure(message: "The note changed while preparing CLI metadata. Review again.") }
                var content = note.content, header = NativeFrontmatter(content)
                var noteAdded = 0, noteRenamed = 0
                let logical = String(content.unicodeScalars.drop(while: { $0.value == 0xfeff }))
                guard !(logical.hasPrefix("---\n") || logical.hasPrefix("---\r\n")) || header.hasHeader else { throw VaultFailure(message: "Frontmatter is not terminated.") }
                for entry in header.entries where entry.id.hasPrefix("grimoire-") {
                    content = try NativeFrontmatter(content).renaming(entry.key, to: "zerus-" + String(cliASCIIKey(entry.key).dropFirst(9)))
                    noteRenamed += 1
                }
                header = NativeFrontmatter(content)
                for key in ["zerus-id", "zerus-pinned", "zerus-archived"] {
                    if let entry = header.entry(key) {
                        guard header.entries.filter({ $0.id == key }).count == 1, let value = entry.value else { throw VaultFailure(message: key + " uses duplicate or complex YAML.") }
                        if case .list = value { throw VaultFailure(message: key + " must be a scalar, not a list.") }
                    }
                }
                let id: UUID
                if let value = header.entry("zerus-id")?.value?.display {
                    guard let parsed = cliNoteUUID(value) else { throw VaultFailure(message: "zerus-id must contain a valid UUID before CLI setup.") }; id = parsed
                } else { id = UUID(); content = try header.setting("zerus-id", value: .text(id.uuidString.lowercased())); noteAdded += 1 }
                if let other = ids[id] { issues.append(note.path + ": shares its note ID with " + other) } else { ids[id] = note.path }
                guard NativeFrontmatter(content).entry("zerus-id")?.value?.display == id.uuidString.lowercased() else {
                    throw VaultFailure(message: "zerus-id must use a lowercase hyphenated UUID for shared CLI access. Resolve this ID and its existing links together before setup; no IDs were changed.")
                }
                for key in ["zerus-pinned", "zerus-archived"] {
                    let current = NativeFrontmatter(content)
                    if let entry = current.entry(key), let value = entry.value {
                        let text = value.display.lowercased()
                        guard ["true", "false", ""].contains(text) else { throw VaultFailure(message: key + " must be true or false.") }
                        content = try current.setting(key, value: .checkbox(text == "true"))
                    }
                }
                changes.append(.init(path: note.path, before: before, after: Data(content.utf8)))
                added += noteAdded; renamed += noteRenamed
            } catch { issues.append(note.path + ": " + error.localizedDescription) }
        }
        let manifest = try cliVaultManifest(prepared: true); changes.append(manifest.change)
        return .init(workspaceID: workspaceID, root: root, identity: identity, notes: notes, changes: changes, issues: issues, idsAdded: added, keysRenamed: renamed)
    }
    /// Private recovery files are explicit app-owned dependencies, rather than
    /// vault-relative reads. An exclusive coordination also covers a record
    /// that does not exist yet, preventing a new draft during the commit.
    private func coordinatingCLIRecovery<T>(_ guards: [MacAgentExternalDraftGuard], operation: () throws -> T) throws -> T {
        let files = Array(Set(guards.map(\.file))).sorted { $0.path < $1.path }
        func visit(_ index: Int) throws -> T {
            guard index < files.count else { return try operation() }
            let file = files[index], canonical = file.resolvingSymlinksInPath().standardizedFileURL
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var coordination: NSError?
            var result: Result<T, Error> = .failure(VaultFailure(message: "Connected recovery coordination did not run."))
            NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordination) { target in
                result = Result {
                    guard target.resolvingSymlinksInPath().standardizedFileURL == canonical else {
                        throw VaultFailure(message: "Connected recovery storage moved. Review CLI metadata again.")
                    }
                    return try visit(index + 1)
                }
            }
            if let coordination { throw coordination }
            return try result.get()
        }
        return try visit(0)
    }
    func applyCLIMetadata(_ review: MacCLIMetadataReview, connected: [MacAgentExternalDraftGuard]) throws -> VaultSnapshot {
        guard review.root == root, review.issues.isEmpty, try MacAgentFileIdentity(root) == review.identity else { throw VaultFailure(message: "The CLI metadata review is blocked or the vault changed. Review again.") }
        let current = try cliNotes()
        guard Set(current.map(\.path)) == Set(review.notes.map(\.path)) else { throw VaultFailure(message: "Notes were added or removed after CLI metadata review. Review again.") }
        let paths = review.noteChanges.map(\.path), root = self.root, identity = review.identity
        do {
            try coordinatingCLIRecovery(connected) {
                try applyTransaction(review.changes, historySource: "macos-cli-setup") {
                    guard try MacAgentFileIdentity(root) == identity else { throw VaultFailure(message: "The vault changed after CLI metadata review.") }
                    for path in paths where !(try MacNoteRecoveryStore.locations(root: root, path: path)).isEmpty { throw VaultFailure(message: "A retained note draft exists for " + path + ". Save or resolve it before preparing CLI metadata.") }
                    for guardFile in connected { try guardFile.validate(action: "CLI metadata changes") }
                }
            }
        } catch {
            let old = "changed outside Zerus. No files were changed; reload the folder properties and try again."
            if error.localizedDescription.contains(old) {
                throw VaultFailure(message: error.localizedDescription.replacingOccurrences(of: old, with: "changed after CLI metadata review. No metadata changes were applied; review again."))
            }
            throw error
        }
        do { return try scan() }
        catch { throw VaultFailure(message: "CLI metadata was applied, but refreshing the notes failed: " + error.localizedDescription + " Reopen the vault to refresh the view.") }
    }
}

/// Both AI changes and CLI setup prevent opening new connected editors while
/// their file admission is held. A late edit is retained as a draft/conflict.
@MainActor enum MacVaultFileAdmission { static var active = 0 }

extension MacWorkspace {
    func prepareCLIRegistration(name: String, makeDefault: Bool, registry: MacCLIVaultRegistry = .shared) async throws -> MacCLIRegistrationReview {
        let origin = workspaceID
        guard !busy, !preparingToClose, let root, let io else { throw VaultFailure(message: "Open an idle vault before registering it for the CLI.") }
        let identity = try MacAgentFileIdentity(root)
        let manifest = try await io.cliVaultManifest()
        let prepared = try await registry.prepare(root: root, vaultID: manifest.id, name: name, makeDefault: makeDefault)
        guard origin == workspaceID, try MacAgentFileIdentity(root) == identity else { throw VaultFailure(message: "The vault changed. Review CLI registration again.") }
        return .init(workspaceID: origin, root: root, identity: identity, manifest: manifest, registry: prepared)
    }
    func commitCLIRegistration(_ review: MacCLIRegistrationReview, registry: MacCLIVaultRegistry = .shared) async throws {
        guard !busy, !preparingToClose, review.workspaceID == workspaceID, root == review.root, let io,
              try MacAgentFileIdentity(review.root) == review.identity else { throw VaultFailure(message: "The vault changed or is busy. Review CLI registration again.") }
        busy = true; defer { busy = false }
        try await registry.validate(review.registry)
        let root = review.root, identity = review.identity
        try await io.applyTransaction([review.manifest.change], historySource: "macos-cli-setup") {
            guard try MacAgentFileIdentity(root) == identity else { throw VaultFailure(message: "The vault changed after CLI registration review.") }
        }
        do { try await registry.apply(review.registry) }
        catch { throw VaultFailure(message: "The vault identity is ready, but CLI registration did not finish: " + error.localizedDescription + " Refresh and register again. Your notes were not changed.") }
    }
    private func cliSetupHeld<T: Sendable>(workspace expected: UUID, paths: [String], operation: (VaultFiles, [MacWorkspace], [MacAgentExternalDraftGuard], [MacExternalSession]) async throws -> T) async throws -> T {
        guard expected == workspaceID, let root, let io else { throw VaultFailure(message: "The vault changed. Review CLI metadata again.") }
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL, identity = try MacAgentFileIdentity(root)
        let peers = Self.windows.compactMap(\.value).filter { peer in
            guard let root = peer.root else { return false }
            return root.resolvingSymlinksInPath().standardizedFileURL == canonical || (try? MacAgentFileIdentity(root)) == identity
        }
        guard peers.allSatisfy({ !$0.busy && !$0.preparingToClose && !$0.editorSheetActive && !$0.schemaMaintenanceSaving && !$0.noteMovesSaving && !$0.imageSaving && !$0.externalCopySaving && !$0.recoverySaving && !$0.paneLayoutSaving && !$0.tasksSaving && $0.noteDiskChange == nil }) else { throw VaultFailure(message: "Finish changes and resolve note conflicts in every vault window before CLI setup.") }
        var seen = Set<ObjectIdentifier>()
        let connected = Self.windows.compactMap { $0.value?.external.selected }.filter {
            seen.insert(ObjectIdentifier($0)).inserted && $0.active && MacAgentExternalDrafts.related($0.snapshot.access.canonical, root: root, identity: identity, paths: paths)
        }
        guard connected.allSatisfy({ !$0.agentLocked && !$0.transferring && !$0.exporting && !$0.conflict && !$0.dirty && !$0.saving }) else { throw VaultFailure(message: "Save or resolve connected-file drafts before CLI setup.") }
        let activations = peers.map { ($0, $0.workspaceID) }
        MacVaultFileAdmission.active += 1
        peers.forEach { $0.agentWritingHeld = true; $0.busy = true }; connected.forEach { $0.holdForAgent(true) }
        defer {
            MacVaultFileAdmission.active -= 1; connected.forEach { $0.holdForAgent(false) }
            for (peer, id) in activations where peer.workspaceID == id { peer.agentWritingHeld = false; peer.busy = false }
        }
        await Task.yield()
        for peer in peers { guard await peer.save() else { throw VaultFailure(message: "An open note could not be saved for CLI setup. Its draft is retained; resolve it before reviewing again.") } }
        try Task.checkCancellation()
        guard expected == workspaceID, try MacAgentFileIdentity(root) == identity,
              activations.allSatisfy({ $0.0.workspaceID == $0.1 && !$0.0.isDirty && $0.0.noteDiskChange == nil }) else { throw VaultFailure(message: "Writing or a vault change arrived during CLI setup. Drafts are retained; review again.") }
        let guards = try await MacAgentExternalDrafts.capture(stores: peers.map { $0.external.store }, root: root, paths: paths, action: "CLI metadata changes")
        let result = try await operation(io, peers, guards, connected)
        guard expected == workspaceID else { throw VaultFailure(message: "The vault changed during CLI setup.") }
        return result
    }
    func prepareCLIMetadata() async throws -> MacCLIMetadataReview {
        let origin = workspaceID, paths = notes.map(\.path)
        return try await cliSetupHeld(workspace: origin, paths: paths) { io, _, _, _ in try await io.cliMetadataReview(workspaceID: origin) }
    }
    func commitCLIMetadata(_ review: MacCLIMetadataReview) async throws {
        guard review.issues.isEmpty, root == review.root else { throw VaultFailure(message: "Resolve the blocked CLI metadata review before applying it.") }
        try await cliSetupHeld(workspace: review.workspaceID, paths: review.noteChanges.map(\.path)) { io, peers, guards, connected in
            let snapshot = try await io.applyCLIMetadata(review, connected: guards)
            for peer in peers { await peer.adoptCLISetupSnapshot(snapshot, changes: review.noteChanges) }
            for session in connected { await session.refreshForAgent() }
        }
    }
}
