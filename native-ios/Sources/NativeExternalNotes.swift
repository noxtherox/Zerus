import Foundation

struct NativeExternalEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let location: String
    let bookmark: Data
    let opened: Date
    var parent: String { URL(string: location)?.deletingLastPathComponent().lastPathComponent ?? "Files" }
}

/// Only a file explicitly selected for editing supplies this capability. File
/// previews and read-only image folder mappings cannot authorize a write.
final class NativeExternalAccess: @unchecked Sendable {
    let url: URL
    let canonical: URL
    private let scoped: Bool
    init(selected url: URL) throws {
        self.url = url; scoped = url.startAccessingSecurityScopedResource()
        canonical = url.resolvingSymlinksInPath().standardizedFileURL
        do {
            guard url.isFileURL, ["md", "markdown"].contains(url.pathExtension.lowercased()) else { throw VaultFailure(message: "Choose a Markdown file (.md or .markdown) to edit in place.") }
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "Choose the original Markdown file rather than a symbolic link.") }
        } catch { if scoped { url.stopAccessingSecurityScopedResource() }; throw error }
    }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
    func validate(_ coordinated: URL) throws {
        guard coordinated.resolvingSymlinksInPath().standardizedFileURL == canonical,
              try coordinated.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "The selected file moved or became a link. Open it again in Files; your draft is kept.") }
    }
}

struct NativeExternalFileIdentity: @unchecked Sendable { let value: AnyHashable? }

struct NativeExternalSnapshot: Sendable {
    let entry: NativeExternalEntry
    let access: NativeExternalAccess
    let bytes: Data
    let modified: Date
    let identity: NativeExternalFileIdentity
    var hasBOM: Bool { bytes.starts(with: [0xef, 0xbb, 0xbf]) }
    var content: String { String(decoding: hasBOM ? bytes.dropFirst(3) : bytes[...], as: UTF8.self) }
    func encoded(_ text: String) -> Data { (hasBOM ? Data([0xef, 0xbb, 0xbf]) : Data()) + Data(text.utf8) }
}

struct NativeExternalDraft: Codable, Sendable {
    let version: Int
    let noteID: UUID
    let name: String
    let baseline: Data
    let content: String
    let updated: Date
    var hasUnsavedChanges: Bool {
        let body = baseline.starts(with: [0xef, 0xbb, 0xbf]) ? baseline.dropFirst(3) : baseline[...]
        return content != String(data: Data(body), encoding: .utf8)
    }
}

/// Device-private registration and drafts. Source files are never assigned
/// Zerus IDs or accompanied by vault metadata. Fresh registry reads inside
/// coordination preserve extension fields and other windows' registrations.
private final class NativeExternalNotesStorage: @unchecked Sendable {
    let directory: URL
    private var registry: URL { directory.appendingPathComponent("files.json") }
    init(directory: URL) { self.directory = directory }
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeExternalNotes")
    }
    private struct Registry {
        var object: [String: Any]
        var rows: [[String: Any]]
        var entries: [NativeExternalEntry] {
            rows.map { .init(id: UUID(uuidString: $0["id"] as! String)!, name: $0["name"] as! String, location: $0["location"] as! String, bookmark: Data(base64Encoded: $0["bookmark"] as! String)!, opened: Date(timeIntervalSince1970: $0["opened"] as! Double)) }
                .sorted { $0.opened > $1.opened }
        }
        var data: Data { get throws { var object = object; object["entries"] = rows; return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) } }
    }
    private func readRegistry() throws -> Registry {
        guard FileManager.default.fileExists(atPath: registry.path) else { return .init(object: ["version": 1], rows: []) }
        let problem = VaultFailure(message: "The saved external-note list is unreadable or uses a newer format. Its original data and your files are preserved.")
        guard try registry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              let object = try? JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as? [String: Any], NativeHistory.integer(object["version"]) == 1, let rows = object["entries"] as? [[String: Any]] else { throw problem }
        var ids = Set<UUID>(), locations = Set<String>()
        for row in rows {
            guard let text = row["id"] as? String, let id = UUID(uuidString: text), ids.insert(id).inserted,
                  row["name"] is String, let location = row["location"] as? String, URL(string: location)?.isFileURL == true, locations.insert(location).inserted,
                  let bookmark = row["bookmark"] as? String, let data = Data(base64Encoded: bookmark), !data.isEmpty,
                  let opened = row["opened"] as? Double, opened.isFinite else { throw problem }
        }
        return .init(object: object, rows: rows)
    }
    private func mutateRegistry<T>(_ work: (inout Registry) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var coordination: NSError?, result: Result<T, Error> = .failure(VaultFailure(message: "The external-note list could not be saved."))
        NSFileCoordinator().coordinate(writingItemAt: registry, options: .forReplacing, error: &coordination) { url in result = Result {
            var value = try readRegistry(); let answer = try work(&value)
            try value.data.write(to: url, options: .atomic); return answer
        } }
        if let coordination { throw coordination }; return try result.get()
    }
    private nonisolated static func boundedData(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 10 * 1024 * 1024 + 1) ?? Data()
        guard bytes.count <= 10 * 1024 * 1024 else { throw VaultFailure(message: "This Markdown file exceeds the 10 MB native editing limit.") }
        return bytes
    }
    func entries() throws -> [NativeExternalEntry] { try readRegistry().entries }
    private func bytes(_ access: NativeExternalAccess, search: NativeCoordinatedRead<NativeExternalSnapshot>? = nil) throws -> (Data, Date, NativeExternalFileIdentity) {
        var coordination: NSError?, result: Result<(Data, Date, NativeExternalFileIdentity), Error> = .failure(VaultFailure(message: "This Markdown file is unavailable. Locate it again in Files."))
        let coordinator = NSFileCoordinator()
        let coordinate = {
            coordinator.coordinate(readingItemAt: access.url, options: [], error: &coordination) { url in result = Result {
                try search?.check()
                try access.validate(url)
                var freshURL = url; freshURL.removeAllCachedResourceValues()
                let attributes = try freshURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
                guard attributes.isRegularFile == true, (attributes.fileSize ?? 0) <= 10 * 1024 * 1024 else { throw VaultFailure(message: "Choose a Markdown file smaller than 10 MB for native editing.") }
                let data = try Self.boundedData(url)
                guard data.count <= 10 * 1024 * 1024, !data.contains(0), String(data: data, encoding: .utf8) != nil else { throw VaultFailure(message: "This file is too large or is not UTF-8 Markdown. The original is unchanged.") }
                return (data, attributes.contentModificationDate ?? Date(), .init(value: attributes.fileResourceIdentifier as? AnyHashable))
            } }
        }
        if let search { try search.coordinating(coordinator, coordinate) } else { coordinate() }
        try search?.check()
        if let coordination { throw coordination }; return try result.get()
    }
    func searchSnapshot(_ entry: NativeExternalEntry, read: NativeCoordinatedRead<NativeExternalSnapshot>) throws -> NativeExternalSnapshot {
        guard try readRegistry().entries.contains(entry) else { throw VaultFailure(message: "This saved connection changed. Refresh external notes.") }
        var stale = false
        let url = try URL(resolvingBookmarkData: entry.bookmark, options: [], bookmarkDataIsStale: &stale)
        let access = try NativeExternalAccess(selected: url)
        let (data, modified, identity) = try bytes(access, search: read)
        try read.check()
        guard try readRegistry().entries.contains(entry) else { throw CancellationError() }
        return .init(entry: entry, access: access, bytes: data, modified: modified, identity: identity)
    }
    func open(selected url: URL) throws -> NativeExternalSnapshot {
        let access = try NativeExternalAccess(selected: url), (data, modified, identity) = try bytes(access)
        try Task.checkCancellation()
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let matches = try readRegistry().entries.filter { entry in
            if entry.location == access.canonical.absoluteString { return true }
            var stale = false
            guard let saved = try? URL(resolvingBookmarkData: entry.bookmark, options: [], bookmarkDataIsStale: &stale) else { return false }
            let scoped = saved.startAccessingSecurityScopedResource(); defer { if scoped { saved.stopAccessingSecurityScopedResource() } }
            return saved.resolvingSymlinksInPath().standardizedFileURL == access.canonical
        }
        guard matches.count <= 1 else { throw VaultFailure(message: "Multiple saved entries refer to this file. Their original records are preserved.") }
        let entry = try mutateRegistry { value -> NativeExternalEntry in
            let index = value.rows.firstIndex { row in
                row["location"] as? String == access.canonical.absoluteString || matches.first.map { $0.id.uuidString == row["id"] as? String } == true
            }
            if let expected = matches.first, let index, value.rows[index]["id"] as? String == expected.id.uuidString {
                guard value.rows[index]["location"] as? String == expected.location,
                      value.rows[index]["bookmark"] as? String == expected.bookmark.base64EncodedString() else { throw VaultFailure(message: "Saved file access changed while opening. Open the selected file again.") }
            }
            var row = index.map { value.rows[$0] } ?? ["id": UUID().uuidString]
            row["name"] = url.lastPathComponent; row["location"] = access.canonical.absoluteString; row["bookmark"] = bookmark.base64EncodedString(); row["opened"] = Date().timeIntervalSince1970
            if let index { value.rows[index] = row } else { value.rows.append(row) }
            return value.entries.first { $0.location == access.canonical.absoluteString }!
        }
        return .init(entry: entry, access: access, bytes: data, modified: modified, identity: identity)
    }
    func reopen(_ id: UUID) throws -> NativeExternalSnapshot {
        guard let original = try readRegistry().entries.first(where: { $0.id == id }) else { throw VaultFailure(message: "This file is no longer tracked. Open it again in Files.") }
        var stale = false
        let url = try URL(resolvingBookmarkData: original.bookmark, options: [], bookmarkDataIsStale: &stale)
        let access = try NativeExternalAccess(selected: url), (data, modified, identity) = try bytes(access)
        try Task.checkCancellation()
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let entry = try mutateRegistry { value -> NativeExternalEntry in
            guard let index = value.rows.firstIndex(where: { $0["id"] as? String == id.uuidString }) else { throw VaultFailure(message: "This file was removed from the list. Open it again in Files.") }
            guard !value.entries.contains(where: { $0.id != id && $0.location == access.canonical.absoluteString }) else { throw VaultFailure(message: "Another saved entry already refers to this file. Original records are preserved.") }
            value.rows[index]["name"] = url.lastPathComponent; value.rows[index]["location"] = access.canonical.absoluteString
            value.rows[index]["bookmark"] = bookmark.base64EncodedString(); value.rows[index]["opened"] = Date().timeIntervalSince1970
            return value.entries.first { $0.id == id }!
        }
        return .init(entry: entry, access: access, bytes: data, modified: modified, identity: identity)
    }
    func locate(_ id: UUID, selected url: URL) throws -> NativeExternalSnapshot {
        let access = try NativeExternalAccess(selected: url), (data, modified, identity) = try bytes(access)
        try Task.checkCancellation()
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let entry = try mutateRegistry { value -> NativeExternalEntry in
            guard let index = value.rows.firstIndex(where: { $0["id"] as? String == id.uuidString }) else { throw VaultFailure(message: "This file is no longer tracked. Open it again in Files.") }
            guard !value.entries.contains(where: { $0.id != id && $0.location == access.canonical.absoluteString }) else { throw VaultFailure(message: "This selected file is already tracked by another entry.") }
            value.rows[index]["name"] = url.lastPathComponent; value.rows[index]["location"] = access.canonical.absoluteString
            value.rows[index]["bookmark"] = bookmark.base64EncodedString(); value.rows[index]["opened"] = Date().timeIntervalSince1970
            return value.entries.first { $0.id == id }!
        }
        return .init(entry: entry, access: access, bytes: data, modified: modified, identity: identity)
    }
    func project(_ snapshot: NativeExternalSnapshot) throws -> NativeExternalProjectFiles? {
        try validateRegistration(snapshot)
        guard let row = try readRegistry().rows.first(where: { $0["id"] as? String == snapshot.entry.id.uuidString }), let value = row["projectBookmark"] else { return nil }
        guard let encoded = value as? String, let data = Data(base64Encoded: encoded) else { throw VaultFailure(message: "Saved project access is unreadable. Its original record is preserved.") }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], bookmarkDataIsStale: &stale)
        return try NativeExternalProjectFiles(selectedProject: url, source: snapshot.access.canonical)
    }
    func mapProject(_ snapshot: NativeExternalSnapshot, selected url: URL) throws -> NativeExternalProjectFiles {
        let access = try NativeExternalProjectFiles(selectedProject: url, source: snapshot.access.canonical)
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        try mutateRegistry { value in
            guard let index = value.rows.firstIndex(where: { $0["id"] as? String == snapshot.entry.id.uuidString && $0["location"] as? String == snapshot.access.canonical.absoluteString }) else { throw VaultFailure(message: "This file moved or its saved access changed. Reopen it before choosing a project folder.") }
            value.rows[index]["projectBookmark"] = bookmark.base64EncodedString()
        }
        return access
    }
    func refresh(_ snapshot: NativeExternalSnapshot) throws -> NativeExternalSnapshot {
        try validateRegistration(snapshot)
        let (data, modified, identity) = try bytes(snapshot.access)
        return .init(entry: snapshot.entry, access: snapshot.access, bytes: data, modified: modified, identity: identity)
    }
    private func validateRegistration(_ snapshot: NativeExternalSnapshot) throws {
        guard try readRegistry().entries.contains(where: { $0.id == snapshot.entry.id && $0.location == snapshot.access.canonical.absoluteString }) else { throw VaultFailure(message: "This file is no longer tracked at its original location. Reopen it in Files; your draft is kept.") }
    }
    func save(_ snapshot: NativeExternalSnapshot, content: String) throws -> NativeExternalSnapshot {
        try validateRegistration(snapshot)
        let replacement = snapshot.encoded(content)
        guard replacement.count <= 10 * 1024 * 1024 else { throw VaultFailure(message: "The draft exceeds the 10 MB editing limit. Share it before making further changes.") }
        var coordination: NSError?, result: Result<Void, Error> = .failure(VaultFailure(message: "The file could not be saved; your draft is kept."))
        var savedIdentity = snapshot.identity, savedEntry = snapshot.entry
        NSFileCoordinator().coordinate(writingItemAt: snapshot.access.url, options: .forReplacing, error: &coordination) { url in
            var metadataError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: registry, options: .forReplacing, error: &metadataError) { metadataURL in result = Result {
                try snapshot.access.validate(url)
                var value = try readRegistry()
                guard let index = value.rows.firstIndex(where: { $0["id"] as? String == snapshot.entry.id.uuidString && $0["location"] as? String == snapshot.access.canonical.absoluteString }) else { throw VaultFailure(message: "Saved access changed. Your draft is kept; reopen the file.") }
                var freshURL = url; freshURL.removeAllCachedResourceValues()
                let values = try freshURL.resourceValues(forKeys: [.fileSizeKey, .fileResourceIdentifierKey])
                let currentIdentity = values.fileResourceIdentifier as? AnyHashable
                guard snapshot.identity.value == nil || currentIdentity == snapshot.identity.value else { throw VaultFailure(message: "The original file was replaced. Your draft is kept; reopen the selected file before editing it.") }
                guard (values.fileSize ?? 0) <= 10 * 1024 * 1024, try Self.boundedData(url) == snapshot.bytes else { throw VaultFailure(message: "This file changed in another editor. Your draft is kept on this device. Share the draft before reloading the current file.") }
                try Task.checkCancellation()
                try replacement.write(to: url, options: .atomic)
                freshURL.removeAllCachedResourceValues()
                savedIdentity = .init(value: try freshURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? AnyHashable)
                let bookmark = try freshURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                value.rows[index]["bookmark"] = bookmark.base64EncodedString()
                try value.data.write(to: metadataURL, options: .atomic)
                savedEntry = value.entries.first { $0.id == snapshot.entry.id }!
            } }
            if let metadataError { result = .failure(metadataError) }
        }
        if let coordination { throw coordination }; try result.get()
        return .init(entry: savedEntry, access: snapshot.access, bytes: replacement, modified: Date(), identity: savedIdentity)
    }
    private func draftURL(_ id: UUID) -> URL { directory.appendingPathComponent("Drafts/" + id.uuidString + ".json") }
    func draft(_ id: UUID) throws -> NativeExternalDraft? {
        let url = draftURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              let draft = try? JSONDecoder().decode(NativeExternalDraft.self, from: Data(contentsOf: url)), draft.version == 1, draft.noteID == id,
              draft.baseline.count <= 10 * 1024 * 1024, draft.content.utf8.count <= 10 * 1024 * 1024 else { throw VaultFailure(message: "This file has an unreadable recovery draft. Its original draft is preserved; share the file before editing it elsewhere.") }
        return draft
    }
    func keepDraft(_ draft: NativeExternalDraft, replacing expected: NativeExternalDraft?) throws {
        guard draft.version == 1, draft.baseline.count <= 10 * 1024 * 1024, draft.content.utf8.count <= 10 * 1024 * 1024,
              String(data: draft.baseline, encoding: .utf8) != nil, !draft.content.utf8.contains(0) else { throw VaultFailure(message: "This draft exceeds the supported UTF-8 Markdown limits. The previous recovery draft is preserved.") }
        let location = draftURL(draft.noteID)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordination: NSError?, result: Result<Void, Error> = .failure(VaultFailure(message: "The recovery draft could not be saved."))
        NSFileCoordinator().coordinate(readingItemAt: registry, options: [], writingItemAt: location, options: .forReplacing, error: &coordination) { _, target in result = Result {
            guard try readRegistry().entries.contains(where: { $0.id == draft.noteID }) else { throw VaultFailure(message: "This file is no longer tracked. Your current text remains open; share it before closing.") }
            let current = try self.draft(draft.noteID)
            guard current?.updated == expected?.updated, current?.content == expected?.content, current?.baseline == expected?.baseline else { throw VaultFailure(message: "Another window updated this recovery draft. Your current text remains open; share it before reloading.") }
            try JSONEncoder().encode(draft).write(to: target, options: .atomic)
        } }
        if let coordination { throw coordination }; try result.get()
    }
    func forget(_ id: UUID) throws {
        let location = draftURL(id)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordination: NSError?, result: Result<Void, Error> = .failure(VaultFailure(message: "Saved access could not be removed."))
        NSFileCoordinator().coordinate(writingItemAt: registry, options: .forReplacing, writingItemAt: location, options: .forDeleting, error: &coordination) { registryURL, draftURL in result = Result {
            var value = try readRegistry()
            if let draft = try self.draft(id), draft.hasUnsavedChanges { throw VaultFailure(message: "Save, share or discard this file’s recovery draft before removing its saved access.") }
            value.rows.removeAll { $0["id"] as? String == id.uuidString }
            try value.data.write(to: registryURL, options: .atomic)
            if FileManager.default.fileExists(atPath: draftURL.path) { try FileManager.default.removeItem(at: draftURL) }
        } }
        if let coordination { throw coordination }; try result.get()
    }
}


/// File-provider waits run independently. A delayed original-file save cannot
/// prevent another edit from reaching the device-private recovery draft.
actor NativeExternalNotesStore {
    let directory: URL
    private let storage: NativeExternalNotesStorage
    init(directory: URL) { self.directory = directory; storage = .init(directory: directory) }
    static var defaultDirectory: URL { NativeExternalNotesStorage.defaultDirectory }
    private nonisolated static func work<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        let job = Task.detached(priority: .userInitiated, operation: body)
        return try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
    }
    func searchSnapshot(_ entry: NativeExternalEntry) async throws -> NativeExternalSnapshot {
        let storage = storage, read = NativeCoordinatedRead<NativeExternalSnapshot>()
        return try await read.value(timeout: 5) { try storage.searchSnapshot(entry, read: $0) }
    }
    func entries() async throws -> [NativeExternalEntry] { let storage = storage; return try await Self.work { try storage.entries() } }
    func open(selected url: URL) async throws -> NativeExternalSnapshot { let storage = storage; return try await Self.work { try storage.open(selected: url) } }
    func reopen(_ id: UUID) async throws -> NativeExternalSnapshot { let storage = storage; return try await Self.work { try storage.reopen(id) } }
    func locate(_ id: UUID, selected url: URL) async throws -> NativeExternalSnapshot { let storage = storage; return try await Self.work { try storage.locate(id, selected: url) } }
    func refresh(_ snapshot: NativeExternalSnapshot) async throws -> NativeExternalSnapshot { let storage = storage; return try await Self.work { try storage.refresh(snapshot) } }
    func save(_ snapshot: NativeExternalSnapshot, content: String) async throws -> NativeExternalSnapshot { let storage = storage; return try await Self.work { try storage.save(snapshot, content: content) } }
    func draft(_ id: UUID) async throws -> NativeExternalDraft? { let storage = storage; return try await Self.work { try storage.draft(id) } }
    func keepDraft(_ draft: NativeExternalDraft, replacing expected: NativeExternalDraft?) async throws { let storage = storage; try await Self.work { try storage.keepDraft(draft, replacing: expected) } }
    func project(_ snapshot: NativeExternalSnapshot) async throws -> NativeExternalProjectFiles? { let storage = storage; return try await Self.work { try storage.project(snapshot) } }
    func mapProject(_ snapshot: NativeExternalSnapshot, selected url: URL) async throws -> NativeExternalProjectFiles { let storage = storage; return try await Self.work { try storage.mapProject(snapshot, selected: url) } }
    func forget(_ id: UUID) async throws { let storage = storage; try await Self.work { try storage.forget(id) } }
}
