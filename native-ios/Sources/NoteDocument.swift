import Foundation

/// Keeps foreign YAML and Markdown bytes intact until the user changes them.
struct NoteDocument: Identifiable, Hashable, Sendable {
    var path: String
    var content: String
    var modified: Date
    // Runtime provenance; never serialized into Markdown.
    var workspaceID: UUID? = nil
    var created: Date? = nil
    var id: String { path }
    var parts: (header: String, body: String) { Self.split(content) }
    var title: String {
        let body = parts.body as NSString
        var offset = 0
        while offset < body.length {
            let newline = body.rangeOfCharacter(from: .newlines, range: NSRange(location: offset, length: body.length - offset))
            let end = newline.location == NSNotFound ? body.length : newline.location
            if end - offset >= 2, body.character(at: offset) == 35, body.character(at: offset + 1) == 32 {
                let line = body.substring(with: NSRange(location: offset, length: end - offset))
                // Preserve Swift's grapheme-aware heading prefix and trimming.
                if line.hasPrefix("# ") { return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            }
            guard newline.location != NSNotFound else { break }
            offset = NSMaxRange(newline)
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
    var folder: String {
        let logical = trashed ? String(path.dropFirst(7)) : path
        if logical.hasPrefix(".zerus/links/") { return "Saved links" }
        if logical.hasPrefix(".zerus/files/") { return "Files" }
        let parent = (logical as NSString).deletingLastPathComponent
        return parent.isEmpty ? "Inbox" : parent
    }
    var pinned: Bool { property("zerus-pinned") == "true" }
    var archived: Bool { property("zerus-archived") == "true" }
    var trashed: Bool { path.hasPrefix(".trash/") }
    var stableID: String? { property("zerus-id") }
    var snippet: String {
        NativeMarkdownPreview.text(self)
    }

    func property(_ key: String) -> String? {
        guard let entry = NativeFrontmatter(content).entry(key), let value = entry.value else { return nil }
        // Preserve the legacy accessor's raw list spelling. Typed editors use
        // NativeFrontmatter directly, while flags and stable IDs are scalars.
        if case .list = value {
            let line = (content as NSString).substring(with: entry.range).components(separatedBy: .newlines).first ?? ""
            return line.firstIndex(of: ":").map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) }
        }
        return value.display
    }
    func replacingBody(_ body: String) -> String { parts.header + body }
    func setting(_ key: String, to value: String) throws -> String {
        let typed: NativePropertyValue = value == "true" || value == "false" ? .checkbox(value == "true") : .text(value)
        return try NativeFrontmatter(content).setting(key, value: typed)
    }
    static func split(_ text: String) -> (header: String, body: String) {
        let parsed = NativeFrontmatter(text)
        return (parsed.header, parsed.body)
    }
}

struct NativeFileDates: Sendable, Equatable { let modified: Date; let created: Date? }

struct VaultSnapshot: Sendable {
    var notes: [NoteDocument]
    var files: [String]
    var fileDates: [String: NativeFileDates] = [:]
    var folders: [String] = []
    var folderIcons: [String: String] = [:]
    var folderIssue: String?
}

struct VaultFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Mutations and snapshots are serialized off the UI actor; preview reads can
/// wait independently while retaining the original security scope. Every mutation
/// checks original bytes inside the coordinated write, including outside edits.
private final class VaultFileAccess: @unchecked Sendable {
    let root: URL
    let scoped: Bool
    init(_ root: URL) { self.root = root; scoped = root.startAccessingSecurityScopedResource() }
    deinit { if scoped { root.stopAccessingSecurityScopedResource() } }
}

actor VaultFiles {
    private let access: VaultFileAccess
    let root: URL
    var writesSuspendedForRecovery = false
    var pendingExternalHistory: [String: NativePendingExternalHistory] = [:]
    var externalHistoryBootstrapped = false
    let historyOriginID: String = {
        let key = "zerus.native.historyOriginId.v1"
        if let value = UserDefaults.standard.string(forKey: key) { return value }
        let value = UUID().uuidString.lowercased(); UserDefaults.standard.set(value, forKey: key); return value
    }()
    init(root: URL) { self.root = root; access = VaultFileAccess(root) }

    func url(for path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
            throw VaultFailure(message: "This path is outside the vault.")
        }
        let result = root.appendingPathComponent(path).standardizedFileURL
        _ = try Self.confinedPath(for: result, root: root)
        return result
    }

    nonisolated static func confinedPath(for location: URL, root: URL) throws -> String {
        // Foundation does not reliably resolve an aliased parent when the full
        // descendant does not exist yet. Resolve the nearest existing ancestor
        // before appending missing components; retain the scoped URL for IO.
        func canonicalPath(_ url: URL) throws -> String {
            var ancestor = url.standardizedFileURL
            var missing: [String] = []
            while !FileManager.default.fileExists(atPath: ancestor.path) {
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path)) != nil {
                    throw VaultFailure(message: "An unavailable link in the vault cannot be opened.")
                }
                let parent = ancestor.deletingLastPathComponent()
                guard parent.path != ancestor.path else { throw VaultFailure(message: "The vault location is unavailable.") }
                missing.append(ancestor.lastPathComponent)
                ancestor = parent
            }
            var resolved = ancestor.resolvingSymlinksInPath()
            for component in missing.reversed() { resolved.appendPathComponent(component) }
            return resolved.standardizedFileURL.path
        }
        let rootPath = try canonicalPath(root)
        let path = try canonicalPath(location)
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard path != rootPath, path.hasPrefix(prefix) else { throw VaultFailure(message: "Links outside the vault cannot be opened.") }
        return path
    }

    func resolveResource(_ reference: String, notePath: String) throws -> URL {
        try Self.resolveResource(reference, notePath: notePath, root: root)
    }
    nonisolated static func resourceCandidates(_ reference: String, notePath: String, root: URL) throws -> [URL] {
        guard let parsed = URL(string: reference), parsed.scheme == nil else { throw VaultFailure(message: "This file is not stored in the vault.") }
        // relativePath has already decoded percent escapes exactly once.
        let decoded = parsed.relativePath
        guard !decoded.isEmpty, !decoded.hasPrefix("/"), !decoded.contains("\\") else { throw VaultFailure(message: "This file is outside the vault.") }
        // Trashing a note preserves its logical folder and attachment base.
        let logical = notePath.hasPrefix(".trash/") ? String(notePath.dropFirst(7)) : notePath
        let note = root.appendingPathComponent(logical).standardizedFileURL
        _ = try confinedPath(for: note, root: root)
        let prefix = root.standardizedFileURL.path + "/"
        let relative = note.deletingLastPathComponent().appendingPathComponent(decoded).standardizedFileURL
        let absolute = root.appendingPathComponent(decoded).standardizedFileURL
        let candidates = decoded.hasPrefix("assets/") || decoded.hasPrefix(".zerus/") ? [absolute, relative] : [relative, absolute]
        var seen = Set<String>()
        return try candidates.filter { $0.path.hasPrefix(prefix) && seen.insert($0.path).inserted }.map {
            _ = try confinedPath(for: $0, root: root)
            return $0
        }
    }
    nonisolated static func resolveResource(_ reference: String, notePath: String, root: URL) throws -> URL {
        for candidate in try resourceCandidates(reference, notePath: notePath, root: root) where FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        throw VaultFailure(message: "The linked file is unavailable in this vault.")
    }

    func read(_ path: String) throws -> Data {
        let location = try url(for: path)
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(VaultFailure(message: "Could not read this file."))
        NSFileCoordinator().coordinate(readingItemAt: location, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    func resourceData(_ reference: String, notePath: String) throws -> Data {
        try Self.resourceBytes(reference, notePath: notePath, root: root)
    }

    /// Provider downloads may block a coordinated read. Inline previews use an
    /// independent reader so unrelated note/task writes can keep progressing.
    /// Retain the original security scope until even a canceled read finishes.
    func imagePreviewData(_ reference: String, notePath: String) async throws -> Data {
        let access = self.access, root = self.root
        let read = NativeCoordinatedRead<Data>()
        let bytes = try await read.value(timeout: 15) { operation in
            try withExtendedLifetime(access) { try Self.resourceBytes(reference, notePath: notePath, root: root, preview: operation) }
        }
        try Task.checkCancellation()
        return bytes
    }

    private nonisolated static func missingResource(_ error: Error) -> Bool {
        var value = error as NSError
        for _ in 0..<5 {
            if value.domain == NSCocoaErrorDomain, [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(value.code) { return true }
            if value.domain == NSPOSIXErrorDomain, value.code == Int(POSIXErrorCode.ENOENT.rawValue) { return true }
            guard let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError, underlying !== value else { break }
            value = underlying
        }
        return false
    }

    private nonisolated static func resourceBytes(_ reference: String, notePath: String, root: URL, preview: NativeCoordinatedRead<Data>? = nil) throws -> Data {
        let limit = 50 * 1024 * 1024
        let tooLarge = VaultFailure(message: "This image is larger than the 50 MB inline-preview limit.")
        var missing: Error = VaultFailure(message: "The linked file is unavailable in this vault.")
        for location in try resourceCandidates(reference, notePath: notePath, root: root) {
            try Task.checkCancellation()
            do {
                // Let the provider materialize the preferred URL before reading
                // its metadata or bytes. A preview deadline covers that wait.
                try preview?.check()
                var coordinationError: NSError?
                var result: Result<Data, Error> = .failure(VaultFailure(message: "Could not read this image."))
                let coordinator = NSFileCoordinator()
                let coordinate = {
                    coordinator.coordinate(readingItemAt: location, options: [], error: &coordinationError) { actual in
                        result = Result {
                            try preview?.check()
                            try Task.checkCancellation()
                            _ = try confinedPath(for: actual, root: root)
                            let size = try actual.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= limit else { throw tooLarge }
                            let file = try FileHandle(forReadingFrom: actual)
                            defer { try? file.close() }
                            var bytes = Data()
                            while bytes.count <= limit {
                                try preview?.check()
                                try Task.checkCancellation()
                                let part = try file.read(upToCount: min(1024 * 1024, limit + 1 - bytes.count)) ?? Data()
                                if part.isEmpty { break }
                                bytes.append(part)
                            }
                            guard bytes.count <= limit else { throw tooLarge }
                            return bytes
                        }
                    }
                }
                if let preview { try preview.coordinating(coordinator, coordinate) } else { coordinate() }
                try preview?.check()
                if let coordinationError { throw coordinationError }
                return try result.get()
            } catch {
                // An unavailable preferred item is not permission to show a
                // different folder's bytes after a size/access/provider error.
                guard missingResource(error) else { throw error }
                missing = error
            }
        }
        throw missing
    }

    func write(_ path: String, data: Data, expected: Data?) throws {
        guard !writesSuspendedForRecovery else { throw VaultFailure(message: "Review the interrupted change before saving. Your draft is kept on this device.") }
        if expected != nil || path.hasPrefix(".zerus/links/"), (path as NSString).pathExtension.lowercased() == "md", let text = String(data: data, encoding: .utf8), NoteDocument(path: path, content: text, modified: Date()).stableID != nil {
            try applyTransaction([.init(path: path, before: expected, after: data)])
            return
        }
        let location = try url(for: path)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var result: Result<Void, Error> = .failure(VaultFailure(message: "Could not save this file."))
        NSFileCoordinator().coordinate(writingItemAt: location, options: .forReplacing, error: &coordinationError) { url in
            result = Result {
                let exists = FileManager.default.fileExists(atPath: url.path)
                let current = exists ? try Data(contentsOf: url) : nil
                guard current == expected else {
                    throw VaultFailure(message: "This file changed outside Zerus. Your draft is kept here. Share it to keep a separate copy, then reopen the note to load the latest version.")
                }
                try data.write(to: url, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    func move(_ path: String, to destination: String, expected: Data) throws {
        guard !writesSuspendedForRecovery else { throw VaultFailure(message: "Review the interrupted change before moving files.") }
        if path.hasPrefix(".zerus/links/") || destination.hasPrefix(".zerus/links/") {
            try applyTransaction([.init(path: destination, before: nil, after: expected), .init(path: path, before: expected, after: nil)])
            return
        }
        let source = try url(for: path), target = try url(for: destination)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var result: Result<Void, Error> = .failure(VaultFailure(message: "Could not move this note."))
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forMoving, writingItemAt: target, options: [], error: &coordinationError) { from, to in
            result = Result {
                guard try Data(contentsOf: from) == expected else { throw VaultFailure(message: "The note changed outside Zerus. Refresh before moving it.") }
                guard !FileManager.default.fileExists(atPath: to.path) else { throw VaultFailure(message: "A note already exists at the destination.") }
                try FileManager.default.moveItem(at: from, to: to)
            }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    nonisolated static func visibleHiddenDirectory(_ path: String) -> Bool {
        [".trash", ".zerus", ".zerus/links", ".zerus/files", ".trash/.zerus", ".trash/.zerus/links", ".trash/.zerus/files"].contains(path)
    }
    func scan() throws -> VaultSnapshot {
        try recoverTransactions()
        var notes: [NoteDocument] = [], files: [String] = [], fileDates: [String: NativeFileDates] = [:], folders: [String] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey]
        var directories = [""]
        while let directory = directories.popLast() {
            let parent = directory.isEmpty ? root : try url(for: directory)
            // Directory enumeration does not follow a symbolic-link root on
            // all providers. The selected root retains its security scope;
            // enumerate its resolved directory and keep note IO scoped above.
            let children = try FileManager.default.contentsOfDirectory(at: parent.resolvingSymlinksInPath(), includingPropertiesForKeys: keys)
            for location in children {
                let name = location.lastPathComponent
                let path = directory.isEmpty ? name : directory + "/" + name
                let values = try location.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true {
                    let allowedHidden = Self.visibleHiddenDirectory(path)
                    if name.hasPrefix(".") && !allowedHidden { continue }
                    if (directory == ".zerus" || directory == ".trash/.zerus") && !allowedHidden { continue }
                    directories.append(path)
                    if !path.hasPrefix("."), path != "assets", !path.hasPrefix("assets/") { folders.append(path) }
                    continue
                }
                if name.hasPrefix(".") { continue }
                if location.pathExtension.lowercased() == "md" {
                    let bytes = try read(path)
                    guard let text = String(data: bytes, encoding: .utf8) else { throw VaultFailure(message: "\(path) is not a UTF-8 Markdown file.") }
                    notes.append(NoteDocument(path: path, content: text, modified: values.contentModificationDate ?? .distantPast, created: values.creationDate))
                } else if !path.hasPrefix(".zerus/") && !path.hasPrefix(".trash/") {
                    files.append(path); fileDates[path] = .init(modified: values.contentModificationDate ?? .distantPast, created: values.creationDate)
                }
            }
        }
        var icons: [String: String] = [:], folderIssue: String?
        do { icons = try folderIconSnapshot().icons }
        catch { folderIssue = "Folder icons could not be read. Their original file is preserved. " + error.localizedDescription }
        return VaultSnapshot(notes: notes.sorted { $0.modified > $1.modified }, files: files.sorted(), fileDates: fileDates, folders: folders.sorted(), folderIcons: icons, folderIssue: folderIssue)
    }
}
