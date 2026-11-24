import Foundation

/// Connected-file recovery belongs to its explicitly supplied registry, not to
/// the vault's private draft store. Ambiguous dirty connections fail closed.
enum MacAgentExternalDrafts {
    static func related(_ file: URL, root: URL, identity: MacAgentFileIdentity, paths: [String]) -> Bool {
        let file = file.resolvingSymlinksInPath().standardizedFileURL, base = root.resolvingSymlinksInPath().standardizedFileURL
        if file.pathComponents.starts(with: base.pathComponents) { return true }
        var directory = file.deletingLastPathComponent()
        while directory.path != "/" {
            if (try? MacAgentFileIdentity(directory)) == identity { return true }
            directory.deleteLastPathComponent()
        }
        return matches(file, root: root, paths: paths)
    }
    private static func matches(_ file: URL, root: URL, paths: [String]) -> Bool {
        let canonical = file.resolvingSymlinksInPath().standardizedFileURL, identity = try? MacAgentFileIdentity(file)
        return paths.contains { path in
            let candidate = root.appendingPathComponent(path)
            return candidate.resolvingSymlinksInPath().standardizedFileURL == canonical || (identity != nil && (try? MacAgentFileIdentity(candidate)) == identity)
        }
    }
    static func capture(stores: [NativeExternalNotesStore], root: URL, paths: [String], action: String = "AI changes") async throws -> [MacAgentExternalDraftGuard] {
        var directories = Set<URL>(), files = Set<URL>(), result: [MacAgentExternalDraftGuard] = []
        guard !paths.isEmpty else { return [] }
        for store in stores {
            let directory = store.directory.resolvingSymlinksInPath().standardizedFileURL
            guard directories.insert(directory).inserted else { continue }
            for entry in try await store.entries() {
                var stale = false
                let bookmark = try? URL(resolvingBookmarkData: entry.bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
                let location = URL(string: entry.location)
                let identity = try MacAgentFileIdentity(root)
                // Atomic replacement can sever a bookmark before a later rename.
                // A dirty draft with unresolved provenance must remain protected.
                let candidates = [bookmark, location].compactMap { $0 }
                guard bookmark == nil || candidates.contains(where: { related($0, root: root, identity: identity, paths: paths) }) else { continue }
                let current = try await store.draft(entry.id)
                let guardFile = MacAgentExternalDraftGuard(file: directory.appendingPathComponent("Drafts/" + entry.id.uuidString + ".json"), id: entry.id, name: entry.name)
                let loaded = try guardFile.load(action: action)
                // Fail closed if the native storage contract ever moves its draft.
                guard (current == nil && loaded == nil) || (current?.baseline == loaded?.baseline && current?.content == loaded?.content && current?.noteID == loaded?.noteID) else {
                    throw VaultFailure(message: "The connected-file recovery draft changed while preparing \(action). Reopen the review.")
                }
                try guardFile.validate(action: action)
                if files.insert(guardFile.file).inserted { result.append(guardFile) }
            }
        }
        return result
    }
}
struct MacAgentExternalDraftGuard: Sendable {
    let file: URL
    let id: UUID
    let name: String
    func load(action: String = "AI changes") throws -> NativeExternalDraft? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 80 * 1024 * 1024,
              let draft = try? JSONDecoder().decode(NativeExternalDraft.self, from: Data(contentsOf: file)),
              draft.version == 1, draft.noteID == id, draft.baseline.count <= 10 * 1024 * 1024, draft.content.utf8.count <= 10 * 1024 * 1024 else { throw VaultFailure(message: "The connected-file recovery draft for \(name) is unreadable. Resolve it before applying \(action).") }
        return draft
    }
    func validate(action: String = "AI changes") throws {
        if try load(action: action)?.hasUnsavedChanges == true { throw VaultFailure(message: "A connected-file recovery draft exists for \(name). Save or resolve it before applying \(action).") }
    }
}
