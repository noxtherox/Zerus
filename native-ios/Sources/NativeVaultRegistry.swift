import Foundation

/// Device-private access records. Nothing is written into the selected vault.
struct NativeSavedVault: Identifiable, Sendable {
    let id: UUID
    var name: String?
    var folder: String
    var location: String
    var bookmark: Data
    var lastOpened: Date
    var drive: NativeDriveFolder? = nil
    var title: String { name ?? folder }
    var locationDescription: String {
        if let drive { return "Google Drive · " + drive.email }
        guard let url = URL(string: location) else { return "Files" }
        let parts = url.pathComponents
        if let cloud = parts.firstIndex(of: "com~apple~CloudDocs") {
            let parent = parts.dropFirst(cloud + 1).dropLast().joined(separator: "/")
            return parent.isEmpty ? "iCloud Drive" : "iCloud Drive · " + parent
        }
        if parts.contains("Application"), parts.contains("Documents"), parts.contains("Containers") { return "On this device" }
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty || parent == "/" || UUID(uuidString: parent) != nil || parent.contains("~") ? "Files" : parent
    }
}

struct NativeVaultRegistry {
    static let key = "zerus.native.vault.registry"
    private var object: [String: Any]
    private var rows: [[String: Any]]
    var entries: [NativeSavedVault] {
        rows.map { row in
            NativeSavedVault(id: UUID(uuidString: row["id"] as! String)!, name: row["name"] as? String,
                             folder: row["folder"] as! String, location: row["location"] as! String,
                             bookmark: Data(base64Encoded: row["bookmark"] as! String)!,
                             lastOpened: Date(timeIntervalSince1970: row["lastOpened"] as! Double),
                             drive: (row["drive"] as? [String: Any]).flatMap { try? JSONDecoder().decode(NativeDriveFolder.self, from: JSONSerialization.data(withJSONObject: $0)) })
        }.sorted { $0.lastOpened > $1.lastOpened }
    }
    var activeID: UUID? { (object["activeID"] as? String).flatMap(UUID.init(uuidString:)) }
    init() throws {
        guard let bytes = UserDefaults.standard.data(forKey: Self.key) else {
            object = ["version": 1]; rows = []; return
        }
        let problem = VaultFailure(message: "The saved vault list uses an unreadable or newer format. Its original data is preserved. You can still open a vault in Files or Google Drive.")
        guard let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              NativeHistory.integer(value["version"]) == 1, let records = value["entries"] as? [[String: Any]] else { throw problem }
        var ids = Set<UUID>()
        for row in records {
            guard let text = row["id"] as? String, let id = UUID(uuidString: text), ids.insert(id).inserted,
                  let folder = row["folder"] as? String, !folder.isEmpty,
                  let location = row["location"] as? String, URL(string: location)?.isFileURL == true,
                  let bookmark = row["bookmark"] as? String, let data = Data(base64Encoded: bookmark), !data.isEmpty,
                  let opened = row["lastOpened"] as? Double, opened.isFinite,
                  row["name"] == nil || row["name"] is String else { throw problem }
            if let drive = row["drive"] { _ = try JSONDecoder().decode(NativeDriveFolder.self, from: JSONSerialization.data(withJSONObject: drive)).validated() }
        }
        if let active = value["activeID"] { guard let text = active as? String, let id = UUID(uuidString: text), ids.contains(id) else { throw problem } }
        object = value; rows = records
    }
    private func save() throws {
        var value = object; value["entries"] = rows
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), forKey: Self.key)
    }
    /// Resolve on a worker: file-provider bookmarks can perform synchronous IPC.
    /// The stored location is only a last-opened spelling, not a stable identity
    /// across app-container updates or provider moves.
    func registrationID(for canonical: URL) throws -> UUID? {
        let matches = entries.filter { entry in
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: entry.bookmark, options: [], bookmarkDataIsStale: &stale) {
                return resolved.resolvingSymlinksInPath().standardizedFileURL == canonical
            }
            // Explicitly choosing the recorded folder can renew a bookmark
            // that no longer resolves. A working bookmark always wins.
            return URL(string: entry.location)?.resolvingSymlinksInPath().standardizedFileURL == canonical
        }
        guard matches.count <= 1 else { throw VaultFailure(message: "More than one saved vault refers to this folder. Open the intended entry in Saved vaults to keep its conversations and drafts separate.") }
        return matches.first?.id
    }
    mutating func activate(url: URL, canonical: URL, bookmark: Data, registeredID: UUID?, drive: NativeDriveFolder? = nil) throws -> UUID {
        let index: Int?
        if let registeredID {
            guard let found = entries.first(where: { $0.id == registeredID }) else { throw VaultFailure(message: "This vault was removed from the list. Open it again in Files.") }
            index = rows.firstIndex { $0["id"] as? String == found.id.uuidString }
        } else { index = nil } // The worker already resolved folder identity.
        let id = index.flatMap { UUID(uuidString: rows[$0]["id"] as! String) } ?? UUID()
        var row = index.map { rows[$0] } ?? ["id": id.uuidString]
        row["folder"] = url.lastPathComponent; row["location"] = canonical.absoluteString
        row["bookmark"] = bookmark.base64EncodedString(); row["lastOpened"] = Date().timeIntervalSince1970
        if let drive { row["drive"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(drive)); row["folder"] = drive.name }
        if let index { rows[index] = row } else { rows.append(row) }
        object["activeID"] = id.uuidString; try save(); return id
    }
    mutating func rename(_ id: UUID, to name: String) throws {
        guard let index = rows.firstIndex(where: { $0["id"] as? String == id.uuidString }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 100, !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw VaultFailure(message: "Use a vault name of up to 100 characters without line breaks.") }
        rows[index]["name"] = trimmed.isEmpty ? nil : trimmed
        try save()
    }
    mutating func remove(_ id: UUID) throws {
        rows.removeAll { $0["id"] as? String == id.uuidString }
        if activeID == id { object.removeValue(forKey: "activeID") }
        try save()
    }
}
