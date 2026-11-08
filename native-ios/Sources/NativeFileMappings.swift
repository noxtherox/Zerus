import Foundation
import CryptoKit

/// Retain the selected security scope for as long as Quick Look, sharing or a
/// coordinated copy needs it. The scope may be a mapped parent directory.
final class NativeFileLease: Identifiable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date?
    let canonicalPath: String
    let locatedOnDevice: Bool
    let temporaryDirectory: URL?
    private let scope: URL
    private let scoped: Bool
    init(scope: URL, url: URL? = nil, locatedOnDevice: Bool = false, temporaryDirectory: URL? = nil) throws {
        self.scope = scope; self.url = url ?? scope; self.locatedOnDevice = locatedOnDevice; self.temporaryDirectory = temporaryDirectory
        scoped = scope.startAccessingSecurityScopedResource()
        canonicalPath = self.url.resolvingSymlinksInPath().standardizedFileURL.path
        do {
            let values = try self.url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true, values.isDirectory != true else { throw VaultFailure(message: "Choose an available document rather than a folder or package.") }
            size = Int64(values.fileSize ?? 0); modified = values.contentModificationDate
        } catch { if scoped { scope.stopAccessingSecurityScopedResource() }; throw error }
    }
    deinit { if scoped { scope.stopAccessingSecurityScopedResource() }; if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) } }
    func readForCopy() throws -> Data {
        guard size <= 50 * 1024 * 1024 else { throw VaultFailure(message: "Choose a file smaller than 50 MB to copy into this native preview.") }
        var error: NSError?, result: Result<Data, Error> = .failure(VaultFailure(message: "The selected file is unavailable."))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { coordinated in result = Result {
            guard coordinated.resolvingSymlinksInPath().standardizedFileURL.path == canonicalPath else { throw VaultFailure(message: "The selected document moved. Choose it again before copying.") }
            let current = try coordinated.resourceValues(forKeys: [.fileSizeKey])
            guard (current.fileSize ?? 0) <= 50 * 1024 * 1024 else { throw VaultFailure(message: "Choose a file smaller than 50 MB to copy.") }
            let bytes = try Data(contentsOf: coordinated)
            guard bytes.count <= 50 * 1024 * 1024 else { throw VaultFailure(message: "Choose a file smaller than 50 MB to copy.") }
            return bytes
        } }
        if let error { throw error }; return try result.get()
    }
}

actor NativeFileMappings {
    let root: URL
    private(set) var file: URL
    private var storageResolved = false
    init(root: URL) {
        self.root = root
        let key = SHA256.hash(data: Data(root.standardizedFileURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeFiles/" + key + "/bookmarks.json")
    }
    /// Bookmarks follow this selected vault when iOS relocates its app data
    /// container or the same folder is renamed. A same-named different vault
    /// never inherits another folder's private access records.
    private func resolveStorage() throws {
        guard !storageResolved else { return }
        let ownDirectory = file.deletingLastPathComponent(), parent = ownDirectory.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: file.path), FileManager.default.fileExists(atPath: parent.path) {
            var matches: [URL] = []
            for candidate in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                guard try candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
                let registration = candidate.appendingPathComponent("vault.bookmark")
                guard let data = try? Data(contentsOf: registration), data.count < 256 * 1024 else { continue }
                var stale = false
                guard let registered = try? URL(resolvingBookmarkData: data, options: [], bookmarkDataIsStale: &stale) else { continue }
                let access = registered.startAccessingSecurityScopedResource(); defer { if access { registered.stopAccessingSecurityScopedResource() } }
                if registered.resolvingSymlinksInPath().standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL { matches.append(candidate.appendingPathComponent("bookmarks.json")) }
            }
            guard matches.count <= 1 else { throw VaultFailure(message: "More than one saved access record refers to this vault. Original records are preserved; choose the file again after resolving the duplicate records.") }
            if let match = matches.first { file = match }
        }
        storageResolved = true
    }
    private func registerRoot() throws {
        let scope = root.startAccessingSecurityScopedResource(); defer { if scope { root.stopAccessingSecurityScopedResource() } }
        let data = try root.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        try data.write(to: file.deletingLastPathComponent().appendingPathComponent("vault.bookmark"), options: .atomic)
    }
    private func object() throws -> [String: Any] {
        try resolveStorage()
        guard FileManager.default.fileExists(atPath: file.path) else { return ["version": 1, "bookmarks": [String: String]()] }
        guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any], NativeHistory.integer(object["version"]) == 1, object["bookmarks"] is [String: String] else {
            throw VaultFailure(message: "Saved file access uses an unsupported format. Its original data is preserved.")
        }
        return object
    }
    private func update(_ change: (inout [String: Any]) throws -> Void) throws {
        try resolveStorage()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinatorError: NSError?, result: Result<Void, Error> = .failure(VaultFailure(message: "Could not save file access."))
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinatorError) { target in
            result = Result {
                var value = try object()
                try change(&value)
                try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: target, options: .atomic)
            }
        }
        if let coordinatorError { throw coordinatorError }; try result.get()
        try registerRoot()
    }
    func set(_ key: String, url: URL?) throws {
        let bookmark = try url.map { try $0.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil).base64EncodedString() }
        try update { value in
            var bookmarks = value["bookmarks"] as! [String: String]
            bookmarks[key] = bookmark; value["bookmarks"] = bookmarks
            if key.hasPrefix("location:") {
                var folders = try driveFolders(value); folders.removeValue(forKey: String(key.dropFirst(9)))
                value["driveFolders"] = folders
            }
        }
    }
    private func driveFolders(_ value: [String: Any]) throws -> [String: Any] {
        guard let raw = value["driveFolders"] else { return [:] }
        guard let rows = raw as? [String: Any] else { throw VaultFailure(message: "Saved Google Drive mappings use an unreadable format. Original records are preserved.") }
        for item in rows.values { _ = try JSONDecoder().decode(NativeDriveFolder.self, from: JSONSerialization.data(withJSONObject: item)).validated() }
        return rows
    }
    func driveFolder(_ id: String) throws -> NativeDriveFolder? {
        guard let value = try driveFolders(object())[id] else { return nil }
        return try JSONDecoder().decode(NativeDriveFolder.self, from: JSONSerialization.data(withJSONObject: value)).validated()
    }
    func mapDriveLocation(_ id: String, selection: NativeDriveFolder) throws {
        _ = try selection.validated()
        try update { value in
            var bookmarks = value["bookmarks"] as! [String: String], folders = try driveFolders(value)
            bookmarks.removeValue(forKey: "location:" + id)
            folders[id] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(selection))
            value["bookmarks"] = bookmarks; value["driveFolders"] = folders
        }
    }
    func driveFolder(for reference: NativeFileHub) throws -> NativeDriveFolder? {
        guard reference.kind == .location, let id = reference.locationID, try mapped("file:" + reference.id) == nil else { return nil }
        return try driveFolder(id)
    }
    private func mapped(_ key: String) throws -> URL? {
        let values = try object()["bookmarks"] as! [String: String]
        guard let encoded = values[key] else { return nil }
        guard let bytes = Data(base64Encoded: encoded) else { throw VaultFailure(message: "Choose this file or folder again in Files to renew its saved access.") }
        var stale = false
        return try URL(resolvingBookmarkData: bytes, options: [], bookmarkDataIsStale: &stale)
    }
    func locationLabel(_ id: String) throws -> String? {
        if let drive = try driveFolder(id) { return "Google Drive · " + drive.name }
        return try mapped("location:" + id)?.lastPathComponent
    }
    func mapLocation(_ id: String, url: URL?) throws {
        if let url {
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw VaultFailure(message: "Choose a folder for this file location.") }
            try set("location:" + id, url: url)
        } else { try set("location:" + id, url: nil) }
    }
    func locate(_ reference: NativeFileHub, source: NativeFileLease) throws { try set("file:" + reference.id, url: source.url) }
    func resolve(_ reference: NativeFileHub) throws -> NativeFileLease {
        if let override = try mapped("file:" + reference.id) { return try NativeFileLease(scope: override, locatedOnDevice: true) }
        switch reference.kind {
        case .vault:
            guard let path = reference.path else { throw VaultFailure(message: "This file needs a valid vault path.") }
            let location = root.appendingPathComponent(path)
            _ = try VaultFiles.confinedPath(for: location, root: root)
            return try NativeFileLease(scope: root, url: location)
        case .location:
            guard let id = reference.locationID, let path = reference.path, let scope = try mapped("location:" + id) else { throw VaultFailure(message: "Map this file's folder in File locations, or locate this document on the device.") }
            let scoped = scope.startAccessingSecurityScopedResource(); defer { if scoped { scope.stopAccessingSecurityScopedResource() } }
            let url = scope.appendingPathComponent(path); _ = try VaultFiles.confinedPath(for: url, root: scope)
            return try NativeFileLease(scope: scope, url: url)
        case .local: throw VaultFailure(message: "Locate this document on this device. The shared note keeps its original connection details.")
        }
    }
    func reference(for selection: NativeFileLease, id: String, locations: [NativeFileLocation]) throws -> NativeFileHub {
        let name = selection.url.lastPathComponent
        if let path = Self.relative(selection.url, inside: root) { return .init(id: id, name: name, kind: .vault, path: path) }
        var matches: [(id: String, path: String, length: Int)] = []
        for location in locations {
            guard let folder = try mapped("location:" + location.id) else { continue }
            let access = folder.startAccessingSecurityScopedResource(); defer { if access { folder.stopAccessingSecurityScopedResource() } }
            if let path = Self.relative(selection.url, inside: folder) { matches.append((location.id, path, folder.path.count)) }
        }
        if let match = matches.max(by: { $0.length < $1.length }) { return .init(id: id, name: name, kind: .location, path: match.path, locationID: match.id) }
        return .init(id: id, name: name, kind: .local)
    }
    private static func relative(_ url: URL, inside root: URL) -> String? {
        guard let canonical = try? VaultFiles.confinedPath(for: url, root: root) else { return nil }
        let prefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard canonical.hasPrefix(prefix) else { return nil }
        return NativeFileHub.relative(String(canonical.dropFirst(prefix.count)))
    }
    func selected(_ url: URL) throws -> NativeFileLease { try NativeFileLease(scope: url) }
    func downloaded(_ data: Data, name: String) throws -> NativeFileLease {
        guard data.count <= NativeDriveFiles.downloadLimit, !name.isEmpty, name.utf8.count <= 255,
              name != ".", name != "..", !name.contains("/"), !name.contains("\\"), name.rangeOfCharacter(from: .controlCharacters) == nil else { throw VaultFailure(message: "This Google Drive filename or download cannot be previewed on this device.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ZerusDrive-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name); try data.write(to: url, options: [.atomic, .completeFileProtection])
            return try NativeFileLease(scope: directory, url: url, temporaryDirectory: directory)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
