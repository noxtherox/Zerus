import Foundation
import CryptoKit

enum NativeExternalTransferMode: String, Codable, Sendable { case copy, move }

/// This scope authorizes writes only inside the reviewed destination vault.
final class NativeExternalDestination: @unchecked Sendable {
    let root: URL
    private let canonical: URL
    private let identity: NativeExternalFileIdentity
    private let scoped: Bool
    init(root: URL) throws {
        self.root = root; canonical = root.resolvingSymlinksInPath().standardizedFileURL
        scoped = root.startAccessingSecurityScopedResource()
        identity = .init(value: try? root.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? AnyHashable)
        do { try validate() } catch { if scoped { root.stopAccessingSecurityScopedResource() }; throw error }
    }
    deinit { if scoped { root.stopAccessingSecurityScopedResource() } }
    func validate() throws {
        var fresh = root; fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [.isDirectoryKey, .fileResourceIdentifierKey])
        guard values.isDirectory == true, fresh.resolvingSymlinksInPath().standardizedFileURL == canonical,
              identity.value == nil || values.fileResourceIdentifier as? AnyHashable == identity.value else {
            throw VaultFailure(message: "The destination vault moved or was replaced. Reopen it before importing this file.")
        }
    }
}

struct NativeExternalTransferAsset: Sendable {
    let reference: String
    let lease: NativeFileLease
    let bytes: Data
    let path: String
}

struct NativeExternalTransferReview: Identifiable, Sendable {
    let id: UUID
    let mode: NativeExternalTransferMode
    let workspaceID: UUID
    let destination: NativeExternalDestination
    let source: NativeExternalSnapshot
    let sourceLease: NativeFileLease
    let project: NativeExternalProjectFiles?
    let path: String
    let content: String
    let noteID: String
    let assets: [NativeExternalTransferAsset]
    let existingNotePaths: Set<String>
    let noteInventory: Set<String>
    let warnings: [String]
    var pendingMove: NativeExternalMoveRecord? = nil
    var changes: [VaultFileChange] {
        [.init(path: path, before: nil, after: Data(content.utf8))] + assets.map { .init(path: $0.path, before: nil, after: $0.bytes) }
    }
    var byteCount: Int { content.utf8.count + assets.reduce(0) { $0 + $1.bytes.count } }
}

enum NativeExternalTransferFiles {
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: #"[/\\:\x00-\x1F]"#, with: "-", options: .regularExpression)
        var result = ""
        for character in cleaned { if result.utf8.count + String(character).utf8.count > 160 { break }; result.append(character) }
        return result.isEmpty || result == "." || result == ".." ? "Untitled" : result
    }
    static func assetName(_ name: String) -> String {
        let ext = String((name as NSString).pathExtension.prefix(20))
        return safeName((name as NSString).deletingPathExtension) + (ext.isEmpty ? "" : "." + safeName(ext))
    }
    static func boundedData(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: limit + 1) ?? Data()
        guard bytes.count <= limit else { throw VaultFailure(message: "This file grew beyond the transfer limit. Review it again.") }
        return bytes
    }
    static func validateSource(_ snapshot: NativeExternalSnapshot, at url: URL) throws {
        try snapshot.access.validate(url)
        var fresh = url; fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .fileResourceIdentifierKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= 10 * 1024 * 1024,
              snapshot.identity.value == nil || values.fileResourceIdentifier as? AnyHashable == snapshot.identity.value,
              try boundedData(fresh, limit: 10 * 1024 * 1024) == snapshot.bytes else {
            throw VaultFailure(message: "The original changed or was replaced after this review. No original was removed. Reload the file and review the import again.")
        }
    }
    static func localURL(_ value: String) -> URL? {
        guard let url = URL(string: value), !url.relativePath.isEmpty else { return nil }
        return url.scheme == nil || url.isFileURL ? url : nil
    }
}

extension VaultFiles {
    func prepareExternalTransfer(_ source: NativeExternalSnapshot, project: NativeExternalProjectFiles?, folder: String,
                                 mode: NativeExternalTransferMode, workspaceID: UUID) throws -> NativeExternalTransferReview {
        try Task.checkCancellation()
        let destination = try NativeExternalDestination(root: root)
        guard (try? Self.confinedPath(for: source.access.canonical, root: root)) == nil else {
            throw VaultFailure(message: "This file already belongs to the destination vault. Open it from Notes to duplicate or move it.")
        }
        let snapshot = try scan()
        let document = NoteDocument(path: source.entry.name, content: source.content, modified: source.modified)
        guard document.fileHub == nil, NativeFileAttachment.all(in: document.content).isEmpty else {
            throw VaultFailure(message: "This file contains a connected-file card or stored attachment records. Make those files portable through Library → Files before importing this Markdown.")
        }
        let parent: String
        if folder == "Inbox" || folder.isEmpty { parent = "" }
        else {
            guard NativeFileHub.relative(folder) != nil, !folder.split(separator: "/").contains(where: { $0.hasPrefix(".") }), folder.split(separator: "/").first != "assets" else {
                throw VaultFailure(message: "Choose a regular note folder in the destination vault.")
            }
            parent = folder + "/"
        }
        let stem = NativeExternalTransferFiles.safeName((source.entry.name as NSString).deletingPathExtension)
        var path = parent + stem + ".md", index = 2
        while FileManager.default.fileExists(atPath: try url(for: path).path) { path = parent + stem + " \(index).md"; index += 1 }
        let originalID = document.stableID.flatMap { $0.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil ? $0 : nil }
        let noteID = mode == .move ? originalID ?? source.entry.id.uuidString.lowercased() : UUID().uuidString.lowercased()
        guard !snapshot.notes.contains(where: { $0.stableID == noteID }) else {
            throw VaultFailure(message: "A note with this identity already exists in the vault. Copy the file to give the new note its own identity.")
        }
        let sourceLease = try NativeFileLease(scope: source.access.url)
        try NativeExternalTransferFiles.validateSource(source, at: sourceLease.url)
        var assets: [NativeExternalTransferAsset] = [], byLocation: [String: String] = [:]
        var edits: [(MarkdownMoveLinks.Link, String)] = [], noteLinks = false, size = source.bytes.count
        for link in try MarkdownMoveLinks.links(in: document.parts.body) {
            try Task.checkCancellation()
            if case .wiki = link.kind { continue }
            guard let parsed = NativeExternalTransferFiles.localURL(link.value) else { continue }
            if ["md", "markdown"].contains(parsed.pathExtension.lowercased()) { noteLinks = true; continue }
            guard let project else { throw VaultFailure(message: "Choose this file’s project folder before importing its local images or linked files.") }
            let lease = try project.transferLease(link.value)
            let target: String
            if let existing = byLocation[lease.canonicalPath] { target = existing }
            else {
                let bytes = try lease.readForCopy(); size += bytes.count
                guard size <= NativeClipboardFragment.limit, assets.count < 1000 else { throw VaultFailure(message: "Import less than 50 MB of Markdown and attachments at a time.") }
                target = "assets/" + UUID().uuidString.lowercased() + "-" + NativeExternalTransferFiles.assetName(lease.url.lastPathComponent)
                assets.append(.init(reference: link.value, lease: lease, bytes: bytes, path: target)); byLocation[lease.canonicalPath] = target
            }
            edits.append((link, MarkdownResources.encodedPath(target, preservingSuffixOf: link.value)))
        }
        let body = MarkdownMoveLinks.replacing(document.parts.body, edits: edits)
        let content = try NativeFrontmatter(document.replacingBody(body)).setting("zerus-id", value: .text(noteID))
        guard content.utf8.count <= 10 * 1024 * 1024, content.utf8.count + assets.reduce(0, { $0 + $1.bytes.count }) <= NativeClipboardFragment.limit else { throw VaultFailure(message: "The imported note and attachments exceed 50 MB.") }
        var warnings: [String] = []
        if document.archived { warnings.append("The imported note retains its Archive setting.") }
        if noteLinks { warnings.append("Links to other Markdown notes keep their source paths. Check those connections in the destination vault before moving the original.") }
        if source.hasBOM { warnings.append("The vault copy uses UTF-8 without a byte-order marker.") }
        return .init(id: UUID(), mode: mode, workspaceID: workspaceID, destination: destination, source: source, sourceLease: sourceLease,
                     project: project, path: path, content: content, noteID: noteID, assets: assets,
                     existingNotePaths: Set(snapshot.notes.map(\.path)), noteInventory: try Self.notePathInventory(root: root), warnings: warnings)
    }

    func commitExternalCopy(_ review: NativeExternalTransferReview) throws -> NoteDocument {
        guard review.destination.root == root else { throw VaultFailure(message: "The destination vault changed. Review the import again.") }
        try review.destination.validate()
        let root = self.root
        let paths = try Self.notePathInventory(root: root)
        guard paths == review.noteInventory else { throw VaultFailure(message: "Notes were added or removed after this review. Prepare the import again.") }
        let readers = try review.existingNotePaths.map { try url(for: $0) }
        try applyTransaction(review.changes, reading: readers, selectedReading: [review.sourceLease] + review.assets.map(\.lease), validate: {
            try review.destination.validate()
            try NativeExternalTransferFiles.validateSource(review.source, at: review.sourceLease.url)
            guard try Self.notePathInventory(root: root) == paths else { throw VaultFailure(message: "Notes changed while importing. Review the destination again.") }
            for path in review.existingNotePaths {
                let data = try Data(contentsOf: root.appendingPathComponent(path))
                if let text = String(data: data, encoding: .utf8), NoteDocument(path: path, content: text, modified: .now).stableID == review.noteID {
                    throw VaultFailure(message: "A note with this identity was added after the review. No import was saved.")
                }
            }
            for asset in review.assets {
                try review.project?.validateTransferResource(asset.reference)
                guard try Data(contentsOf: asset.lease.url) == asset.bytes else { throw VaultFailure(message: "A source attachment changed after the review. No import was saved.") }
            }
        })
        return .init(path: review.path, content: review.content, modified: .now)
    }
}

struct NativeExternalTransferOutcome: Sendable {
    var note: NoteDocument
    let sourceRemoved: Bool
    let recoveryPending: Bool
    let message: String?
}

extension VaultFiles {
    func pendingExternalMoveNote(_ record: NativeExternalMoveRecord) throws -> NoteDocument {
        try recoverTransactions()
        let access = try record.destination()
        guard access.root.resolvingSymlinksInPath().standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else {
            throw VaultFailure(message: "Open this move’s destination vault before continuing.")
        }
        return try NativeExternalTransferFiles.verifyDestination(record, access: access)
    }
}
