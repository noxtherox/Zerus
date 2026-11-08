import Foundation

struct NativeFolderIconSnapshot: Sendable {
    let root: URL
    let bytes: Data?
    let icons: [String: String]
    var workspaceID: UUID?
}

enum NativeFolderOrder {
    static func key(_ vault: UUID) -> String { "zerus.native.folder-order.vault." + vault.uuidString.lowercased() }
    static func load(vault: UUID) -> [String] { UserDefaults.standard.stringArray(forKey: key(vault)) ?? [] }
    static func sorted(_ paths: Set<String>, order: [String]) -> [String] {
        var rank: [String: Int] = [:]
        for (index, path) in order.enumerated() where rank[path] == nil { rank[path] = index }
        return paths.sorted { left, right in
            let a = left.split(separator: "/"), b = right.split(separator: "/")
            for index in 0..<min(a.count, b.count) where a[index] != b[index] {
                let x = a.prefix(index + 1).joined(separator: "/"), y = b.prefix(index + 1).joined(separator: "/")
                let xr = rank[x] ?? Int.max, yr = rank[y] ?? Int.max
                if xr != yr { return xr < yr }
                return String(a[index]).localizedStandardCompare(String(b[index])) == .orderedAscending
            }
            return a.count < b.count
        }
    }
    static func adjacent(_ folder: String, in paths: [String], direction: Int) -> String? {
        let parent = (folder as NSString).deletingLastPathComponent
        let siblings = paths.filter { ($0 as NSString).deletingLastPathComponent == parent }
        guard let index = siblings.firstIndex(of: folder), siblings.indices.contains(index + direction) else { return nil }
        return siblings[index + direction]
    }
}

extension VaultFiles {
    func folderIconSnapshot() throws -> NativeFolderIconSnapshot {
        let bytes = try historyData(".zerus/type-icons.json")
        var icons: [String: String] = [:]
        if let bytes {
            guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "The icon file has an unsupported format.") }
            icons = object.compactMapValues { $0 as? String }
        }
        return .init(root: root, bytes: bytes, icons: icons)
    }

    func createFolder(_ input: String) throws -> VaultSnapshot {
        guard !writesSuspendedForRecovery else { throw VaultFailure(message: "Review the interrupted file change before creating a folder.") }
        let folder = try NativeFolderPath.clean(input)
        let location = try url(for: folder)
        let parts = folder.split(separator: "/")
        for depth in 1...parts.count {
            let ancestor = root.appendingPathComponent(parts.prefix(depth).joined(separator: "/"))
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path)) == nil else { throw VaultFailure(message: "Choose a folder directly inside the vault instead of a linked folder.") }
        }
        var failure: NSError?
        var result: Result<Void, Error> = .failure(VaultFailure(message: "The folder could not be created."))
        NSFileCoordinator().coordinate(writingItemAt: location, options: [], error: &failure) { actual in
            result = Result {
                _ = try Self.confinedPath(for: actual, root: root)
                guard !FileManager.default.fileExists(atPath: actual.path) else { throw VaultFailure(message: "A file or folder with this name already exists.") }
                try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
            }
        }
        if let failure { throw failure }; try result.get()
        return try scan()
    }

    func setFolderIcon(_ snapshot: NativeFolderIconSnapshot, folder: String, value: String?) throws -> VaultSnapshot {
        guard snapshot.root == root else { throw VaultFailure(message: "The vault changed. Reopen the icon picker.") }
        try NativePropertyDefinition.validateOwner(folder)
        let current = try scan()
        guard current.folders.contains(folder) || current.notes.contains(where: { $0.regularCollectionNote && $0.folder == folder }) else { throw VaultFailure(message: "This folder is no longer available.") }
        if let value {
            let tabler = value.hasPrefix("tabler:") && value.dropFirst(7).range(of: #"^[A-Za-z][A-Za-z0-9]*$"#, options: .regularExpression) != nil
            let emoji = value.count == 1 && value.unicodeScalars.contains(where: { !$0.isASCII })
            guard value.utf8.count <= 128, tabler || emoji else { throw VaultFailure(message: "Choose an icon or enter one emoji.") }
        }
        var object: [String: Any] = [:]
        if let bytes = snapshot.bytes {
            guard let decoded = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "The icon file has an unsupported format.") }
            object = decoded
        }
        guard object[folder] == nil || object[folder] is String else { throw VaultFailure(message: "This folder’s icon uses an unsupported format. Its original value is preserved.") }
        if let value { object[folder] = value } else { object.removeValue(forKey: folder) }
        let unchanged = snapshot.icons[folder] == value
        let after = unchanged ? snapshot.bytes : try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try applyTransaction([.init(path: ".zerus/type-icons.json", before: snapshot.bytes, after: after)])
        return try scan()
    }
}
