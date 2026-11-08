import Foundation

/// Version-locked Drive operations used by the native working-copy synchronizer.
/// File IDs for creates are persisted by the caller before sending any bytes.
extension NativeDriveFiles {
    nonisolated static let uploadLimit = 25 * 1024 * 1024 - 65536
    private struct Lock: Decodable {
        struct Parent: Decodable { let id: String }
        struct Labels: Decodable { let trashed: Bool? }
        let id: String; let title: String; let mimeType: String; let parents: [Parent]?
        let version: String?; let etag: String?; let labels: Labels?
    }
    func assertInside(_ item: NativeDriveItem, root: String) async throws {
        var current = item, seen = Set<String>()
        while current.id != root {
            guard current.trashed != true, seen.insert(current.id).inserted, seen.count <= 64, let parents = current.parents, parents.count == 1 else { throw VaultFailure(message: "This Drive item moved outside the selected vault. Refresh before saving.") }
            current = try await metadata(parents[0])
        }
        guard current.folder, current.trashed != true else { throw VaultFailure(message: "The selected Google Drive vault is unavailable.") }
    }
    private func lock(_ observed: NativeDriveItem, root: String) async throws -> String {
        let bytes = try await response("/drive/v2/files/" + observed.id, query: ["fields": "id,title,mimeType,parents(id),version,etag,labels(trashed)"])
        let value = try JSONDecoder().decode(Lock.self, from: bytes)
        guard value.id == observed.id, value.title == observed.name, value.mimeType == observed.mimeType,
              value.parents?.map(\.id) == observed.parents, let version = value.version, version == observed.version,
              value.labels?.trashed != true, let etag = value.etag, !etag.isEmpty else { throw VaultFailure(message: "This file changed in Google Drive. Your iPhone copy has been kept.") }
        try await assertInside(observed, root: root)
        return etag
    }
    func readObserved(_ observed: NativeDriveItem) async throws -> Data {
        let before = try await metadata(observed.id)
        guard before == observed, !before.mimeType.hasPrefix("application/vnd.google-apps."), before.version != nil,
              let size = before.size.flatMap(Int.init), (0...Self.downloadLimit).contains(size) else { throw VaultFailure(message: "This Drive file changed or exceeds the 50 MB download limit.") }
        let bytes = try await response("/drive/v3/files/" + observed.id, query: ["alt": "media"], limit: Self.downloadLimit)
        let after = try await metadata(observed.id)
        guard before == after, bytes.count == size else { throw VaultFailure(message: "This Drive file changed while downloading. Retry the sync.") }
        return bytes
    }
    func tree(_ selection: NativeDriveFolder) async throws -> [String: NativeDriveItem] {
        _ = try selection.validated()
        guard selection.accountID == accountID else { throw VaultFailure(message: "Reconnect the original Google account for this vault.") }
        let root = try await metadata(selection.folderID)
        guard root.folder, root.capabilities?.canAddChildren == true else { throw VaultFailure(message: "Choose a writable Google Drive folder for this vault.") }
        var queue: [(String, String, Int)] = [(root.id, "", 0)], visited = Set<String>(), names = Set<String>(), result: [String: NativeDriveItem] = [:]
        while !queue.isEmpty {
            try Task.checkCancellation()
            let (id, parent, depth) = queue.removeFirst()
            guard depth <= 64, visited.insert(id).inserted else { throw VaultFailure(message: "This Drive folder tree repeats or is too deep.") }
            for child in try await children(id) {
                let path = parent.isEmpty ? child.name : parent + "/" + child.name
                let canonical = path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                guard child.name.utf8.count <= 255, NativeFileHub.relative(path) == path, child.parents == [id], path.utf8.count <= 4096 else { throw VaultFailure(message: "A Drive name cannot be represented on this iPhone. Rename it in Drive before opening this vault.") }
                guard names.insert(canonical).inserted else { throw VaultFailure(message: "Google Drive contains duplicate or case-equivalent paths: \(path). Rename the copies before opening this vault.") }
                result[path] = child
                guard result.count <= 100_000 else { throw VaultFailure(message: "This Drive vault is too large for this native preview.") }
                if child.folder { queue.append((child.id, path, depth + 1)) }
            }
        }
        return result
    }
    func allocateID() async throws -> String {
        struct IDs: Decodable { let ids: [String] }
        let ids = try JSONDecoder().decode(IDs.self, from: await response("/drive/v3/files/generateIds", query: ["count": "1", "space": "drive"])).ids
        guard ids.count == 1, let id = ids.first, Self.validID(id) else { throw VaultFailure(message: "Google Drive did not provide a new file identity.") }
        return id
    }
    func create(id: String, name: String, parent: String, root: String, data: Data?) async throws -> NativeDriveItem {
        guard Self.validID(id), !name.isEmpty, !name.contains("/"), data?.count ?? 0 <= Self.uploadLimit else { throw VaultFailure(message: "Drive uploads are limited to 25 MB per file in this preview.") }
        let folder = try await metadata(parent); try await assertInside(folder, root: root)
        guard folder.folder, folder.capabilities?.canAddChildren == true else { throw VaultFailure(message: "Google Drive no longer permits adding files here.") }
        let siblings = try await children(parent, name: name)
        guard siblings.isEmpty || siblings.count == 1 && siblings[0].id == id else { throw VaultFailure(message: "A file already has this name in Google Drive. Both copies have been kept for review.") }
        if let existing = siblings.first {
            if let data { guard !existing.folder, try await readObserved(existing) == data else { throw VaultFailure(message: "The pending Drive upload changed on another device. Both versions are kept.") } }
            else { guard existing.folder else { throw VaultFailure(message: "The pending Drive folder identity belongs to a file.") } }
            return existing
        }
        let metadata: [String: Any] = ["id": id, "name": name, "parents": [parent], "mimeType": data == nil ? "application/vnd.google-apps.folder" : "application/octet-stream"]
        let body: Data, contentType: String, endpoint: String, query: [String: String]
        if let data {
            let boundary = "zerus_" + UUID().uuidString
            var multipart = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
            multipart.append(try JSONSerialization.data(withJSONObject: metadata)); multipart.append(Data("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)); multipart.append(data); multipart.append(Data("\r\n--\(boundary)--\r\n".utf8))
            body = multipart; contentType = "multipart/related; boundary=" + boundary; endpoint = "/upload/drive/v3/files"; query = ["uploadType": "multipart", "fields": Self.fields]
        } else { body = try JSONSerialization.data(withJSONObject: metadata); contentType = "application/json"; endpoint = "/drive/v3/files"; query = ["fields": Self.fields] }
        let created = try JSONDecoder().decode(NativeDriveItem.self, from: await response(endpoint, query: query, method: "POST", body: body, contentType: contentType))
        guard created.id == id, created.name == name, created.parents == [parent], created.folder == (data == nil), created.version != nil else { throw VaultFailure(message: "The Drive upload returned an unexpected identity. Its pending record has been kept.") }
        return created
    }
    func put(_ observed: NativeDriveItem, root: String, data: Data) async throws -> NativeDriveItem {
        guard !observed.mimeType.hasPrefix("application/vnd.google-apps."), data.count <= Self.uploadLimit else { throw VaultFailure(message: "Only ordinary files up to 25 MB can be uploaded in this preview.") }
        let etag = try await lock(observed, root: root)
        struct Updated: Decodable { let id: String; let version: String }
        let ack = try JSONDecoder().decode(Updated.self, from: await response("/upload/drive/v2/files/" + observed.id, query: ["uploadType": "media", "fields": "id,version"], method: "PUT", body: data, contentType: "application/octet-stream", ifMatch: etag))
        let current = try await metadata(observed.id)
        guard ack.id == observed.id, current.version == ack.version, current.name == observed.name, current.parents == observed.parents else { throw VaultFailure(message: "The file changed after uploading. Its pending sync record has been kept.") }
        return current
    }
    func trash(_ observed: NativeDriveItem, root: String) async throws {
        let etag = try await lock(observed, root: root)
        _ = try await response("/drive/v2/files/" + observed.id, method: "PATCH", body: JSONSerialization.data(withJSONObject: ["labels": ["trashed": true]]), contentType: "application/json", ifMatch: etag)
    }
    func move(_ observed: NativeDriveItem, name: String, parent: String, root: String) async throws -> NativeDriveItem {
        guard !observed.folder, !observed.mimeType.hasPrefix("application/vnd.google-apps."), !name.isEmpty, !name.contains("/"), Self.validID(parent) else { throw VaultFailure(message: "This Drive item cannot be moved as an ordinary file.") }
        let destination = try await metadata(parent); try await assertInside(destination, root: root)
        guard destination.folder, destination.capabilities?.canAddChildren == true,
              try await children(parent, name: name).isEmpty else { throw VaultFailure(message: "A Drive item already occupies the move destination, or this folder is read-only.") }
        let etag = try await lock(observed, root: root)
        var query = ["fields": "id,version"]
        if observed.parents != [parent] { query["addParents"] = parent; query["removeParents"] = (observed.parents ?? []).joined(separator: ",") }
        struct Updated: Decodable { let id: String; let version: String }
        let ack = try JSONDecoder().decode(Updated.self, from: await response("/drive/v2/files/" + observed.id, query: query, method: "PATCH", body: JSONSerialization.data(withJSONObject: ["title": name]), contentType: "application/json", ifMatch: etag))
        let current = try await metadata(observed.id)
        guard ack.id == observed.id, current.version == ack.version, current.name == name, current.parents == [parent] else { throw VaultFailure(message: "The Drive move changed before it was acknowledged. Its working copy and sync record are kept.") }
        return current
    }
}
