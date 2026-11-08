import Foundation

/// Device-private identity for the whole chat folder, including opaque future records.
/// Legacy folders are adopted in place, so frozen attachment paths and live writers stay valid.
struct NativeChatStorage {
    private static var base: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeChats", isDirectory: true) }
    private static let problem = VaultFailure(message: "Some saved conversations could not be identified. Their files are kept. Reopen this vault to retry before using Ask.")
    private struct Binding { let folder: URL; let bytes: Data; var object: [String: Any]; let roots: [String]; let ids: [String] }
    private struct Scan { var matches: [Binding] = []; var unknown = false }
    static func registeredID(for root: URL) -> UUID? {
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL.absoluteString
        let matches = (try? NativeVaultRegistry().entries.filter { $0.location == canonical }) ?? []
        return matches.count == 1 ? matches.first?.id : nil
    }
    private static func identities(_ roots: [URL]) -> Set<String> {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath().standardizedFileURL
        var values = Set<String>()
        for root in roots {
            let literal = root.standardizedFileURL, canonical = literal.resolvingSymlinksInPath().standardizedFileURL
            values.insert(literal.absoluteString); values.insert(canonical.absoluteString)
            if canonical == documents { values.insert("documents:") }
            else if canonical.path.hasPrefix(documents.path + "/") { values.insert("documents:" + String(canonical.path.dropFirst(documents.path.count + 1))) }
        }
        return values
    }
    private static func checkedFolder(_ folder: URL) throws {
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              folder.resolvingSymlinksInPath().standardizedFileURL == base.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent(folder.lastPathComponent) else { throw problem }
    }
    private static func scan(roots: Set<String>, id: UUID?) throws -> Scan {
        guard FileManager.default.fileExists(atPath: base.path) else { return Scan() }
        let canonicalBase = base.resolvingSymlinksInPath().standardizedFileURL
        guard try base.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw problem }
        var result = Scan()
        for folder in try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let file = folder.appendingPathComponent("vault.json")
            let metadataExists = FileManager.default.fileExists(atPath: file.path)
            guard metadataExists || folder.lastPathComponent.hasPrefix("vault-") else { continue }
            do {
                try checkedFolder(folder)
                guard metadataExists else {
                    if !(try FileManager.default.contentsOfDirectory(atPath: folder.path)).isEmpty { result.unknown = true }
                    continue
                }
                let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true, (values.fileSize ?? Int.max) <= 65536,
                      file.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent() == canonicalBase.appendingPathComponent(folder.lastPathComponent) else { throw problem }
                let bytes = try Data(contentsOf: file)
                guard bytes.count <= 65536, let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let oldRoots = object["roots"] as? [String], let ids = object["vaultIDs"] as? [String],
                      oldRoots.count <= 128, ids.count <= 128, Set(oldRoots).count == oldRoots.count, Set(ids).count == ids.count,
                      oldRoots.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 8192 }), ids.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw problem }
                let canonicalIDs = ids.map { UUID(uuidString: $0)!.uuidString.lowercased() }
                guard Set(canonicalIDs).count == ids.count else { throw problem }
                if let id, folder.lastPathComponent == "vault-" + id.uuidString.lowercased(), !canonicalIDs.contains(id.uuidString.lowercased()) { throw problem }
                let matches = id.map { canonicalIDs.contains($0.uuidString.lowercased()) || canonicalIDs.isEmpty && !Set(oldRoots).isDisjoint(with: roots) } ?? !Set(oldRoots).isDisjoint(with: roots)
                guard NativeHistory.integer(object["version"]) == 1 else {
                    if matches { throw VaultFailure(message: "This vault’s saved conversations use a newer format. Their files are kept; use the newer app before continuing in Ask.") }
                    result.unknown = true; continue
                }
                if matches { result.matches.append(.init(folder: folder, bytes: bytes, object: object, roots: oldRoots, ids: canonicalIDs)) }
            } catch let error as VaultFailure where error.message != problem.message { throw error }
            catch { result.unknown = true }
        }
        guard result.matches.count <= 1 else { throw VaultFailure(message: "More than one saved conversation folder identifies this vault. They were kept without merging. Reopen its original vault before continuing in Ask.") }
        return result
    }
    static func location(for root: URL) throws -> URL? {
        let result = try scan(roots: identities([root]), id: registeredID(for: root))
        if let binding = result.matches.first { return binding.folder }
        guard !result.unknown else { throw problem }
        let legacy = NativeChat.legacyDirectory(for: root)
        if FileManager.default.fileExists(atPath: legacy.path) {
            try checkedFolder(legacy)
            guard !FileManager.default.fileExists(atPath: legacy.appendingPathComponent("vault.json").path) else { throw problem }
        }
        return nil
    }
    static func bind(root: URL, vaultID: UUID?, previousRoots: [URL]) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        var coordination: NSError?, result: Result<URL, Error> = .failure(problem)
        NSFileCoordinator().coordinate(writingItemAt: base, options: .forMerging, error: &coordination) { _ in
            result = Result {
                let roots = identities([root] + previousRoots), found = try scan(roots: roots, id: vaultID)
                var legacy: [URL] = []
                for url in [root] + previousRoots {
                    for candidate in [url.standardizedFileURL, url.resolvingSymlinksInPath().standardizedFileURL] {
                        let folder = NativeChat.legacyDirectory(for: candidate)
                        guard fm.fileExists(atPath: folder.path), !legacy.contains(folder) else { continue }
                        try checkedFolder(folder)
                        // A folder already bound to another saved vault is never adopted by path.
                        if fm.fileExists(atPath: folder.appendingPathComponent("vault.json").path) { continue }
                        if !(try fm.contentsOfDirectory(atPath: folder.path)).isEmpty { legacy.append(folder) }
                    }
                }
                guard legacy.count + found.matches.count <= 1 else { throw VaultFailure(message: "Several earlier conversation folders identify this vault. They were kept without merging. Reopen its original vault before continuing in Ask.") }
                guard !found.matches.isEmpty || !found.unknown else { throw problem }
                let binding = found.matches.first
                let folder = binding?.folder ?? legacy.first ?? base.appendingPathComponent("vault-" + (vaultID ?? UUID()).uuidString.lowercased(), isDirectory: true)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true); try checkedFolder(folder)
                var object = binding?.object ?? ["version": 1]
                let nextRoots = identities([root]), nextIDs = Set(binding?.ids ?? []).union(vaultID.map { [$0.uuidString.lowercased()] } ?? [])
                guard nextRoots.count <= 128, nextIDs.count <= 128 else { throw VaultFailure(message: "This conversation has reached its saved-location limit. Existing history is kept.") }
                object["roots"] = nextRoots.sorted(); object["vaultIDs"] = nextIDs.sorted()
                let next = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
                guard next.count <= 65536 else { throw problem }
                let file = folder.appendingPathComponent("vault.json")
                let current = fm.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
                guard current == binding?.bytes else { throw VaultFailure(message: "The saved conversation identity changed. Its original files are kept. Reopen this vault to retry.") }
                if current != next { try next.write(to: file, options: .atomic) }
                return folder
            }
        }
        if let coordination { throw coordination }; return try result.get()
    }
}
