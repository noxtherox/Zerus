import ZerusIOSServices
import Foundation

struct NativeDriveFolder: Codable, Equatable, Sendable {
    let accountID: String
    let email: String
    let folderID: String
    let name: String
    func validated() throws -> Self {
        guard NativeDriveFiles.validID(accountID), NativeDriveFiles.validID(folderID), !email.isEmpty, !name.isEmpty,
              email.utf8.count <= 1024, name.utf8.count <= 4096 else { throw VaultFailure(message: "This saved Google Drive folder is unreadable. Choose it again.") }
        return self
    }
}

struct NativeDriveItem: Codable, Equatable, Identifiable, Sendable {
    struct Capabilities: Codable, Equatable, Sendable { let canEdit: Bool?; let canAddChildren: Bool? }
    let id: String
    let name: String
    let mimeType: String
    let parents: [String]?
    let version: String?
    let size: String?
    let trashed: Bool?
    let modifiedTime: String?
    let createdTime: String?
    let capabilities: Capabilities?
    var folder: Bool { mimeType == "application/vnd.google-apps.folder" }
}

struct NativeDriveHTTPFailure: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

/// Drive's wire boundary is shared by the account browser, mapped document
/// reads and the upcoming vault backend. The account owns authorization and
/// rejects responses from a disconnected/replaced account before returning them.
@MainActor
struct NativeDriveFiles {
    let accountID: String
    let send: (GoogleDriveCommand) async throws -> [String: Any]
    nonisolated static let fields = "id,name,mimeType,parents,version,size,trashed,modifiedTime,createdTime,capabilities(canEdit,canAddChildren)"
    nonisolated static let downloadLimit = 50 * 1024 * 1024
    nonisolated static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 1024 && id.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }
    func response(_ path: String, query: [String: String] = [:], limit: Int = 2 * 1024 * 1024, method: String = "GET", body: Data? = nil, contentType: String? = nil, ifMatch: String? = nil) async throws -> Data {
        try Task.checkCancellation()
        guard Self.validID(accountID) else { throw VaultFailure(message: "Reconnect the original Google account.") }
        let raw = try await send(.init(operation: "request", accountId: accountID, path: path, method: method, query: query, body: body?.base64EncodedString(), contentType: contentType, ifMatch: ifMatch, responseLimit: limit))
        try Task.checkCancellation()
        guard let status = raw["status"] as? Int else { throw VaultFailure(message: "Google Drive returned an unreadable response.") }
        guard (200..<300).contains(status) else {
            let text: String
            switch status {
            case 401: text = "Google Drive sign-in expired. Reconnect your Google account."
            case 403: text = "Google Drive denied access. Check folder permissions and your account's storage."
            case 404: text = "This Google Drive item is no longer available."
            case 412: text = "This Google Drive file changed. Refresh before opening it."
            case 429: text = "Google Drive is busy. Wait a moment, then retry."
            default: text = "Google Drive could not finish this request. Check your connection and retry."
            }
            throw NativeDriveHTTPFailure(status: status, message: text)
        }
        guard let encoded = raw["body"] as? String, let bytes = Data(base64Encoded: encoded), bytes.count <= limit else { throw VaultFailure(message: "Google Drive returned an unreadable or oversized response.") }
        return bytes
    }
    private func item(_ bytes: Data) throws -> NativeDriveItem {
        let value = try JSONDecoder().decode(NativeDriveItem.self, from: bytes)
        guard Self.validID(value.id), !value.name.isEmpty, value.name.utf8.count <= 4096, value.trashed != true,
              value.parents?.allSatisfy(Self.validID) != false else { throw VaultFailure(message: "This Google Drive item is no longer available.") }
        return value
    }
    func metadata(_ id: String) async throws -> NativeDriveItem {
        guard Self.validID(id) else { throw VaultFailure(message: "Invalid Google Drive item.") }
        let value = try item(await response("/drive/v3/files/" + id, query: ["fields": Self.fields]))
        guard id == "root" || value.id == id else { throw VaultFailure(message: "This Google Drive item changed during lookup. Refresh and retry.") }
        return value
    }
    func children(_ folder: String, name: String? = nil) async throws -> [NativeDriveItem] {
        guard Self.validID(folder) else { throw VaultFailure(message: "Invalid Google Drive folder.") }
        struct Page: Decodable { let files: [NativeDriveItem]; let nextPageToken: String?; let incompleteSearch: Bool? }
        var result: [NativeDriveItem] = [], ids: [String: NativeDriveItem] = [:], tokens = Set<String>(), token: String?
        let nameClause = name.map { " and name = '" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'" } ?? ""
        repeat {
            var query = ["q": "'" + folder + "' in parents and trashed = false" + nameClause, "fields": "nextPageToken,incompleteSearch,files(" + Self.fields + ")", "pageSize": "1000", "spaces": "drive", "corpora": "user"]
            if let token { query["pageToken"] = token }
            let page = try JSONDecoder().decode(Page.self, from: await response("/drive/v3/files", query: query))
            guard page.incompleteSearch != true else { throw VaultFailure(message: "Google Drive returned only part of this folder. Retry before choosing a file.") }
            for value in page.files {
                guard Self.validID(value.id), !value.name.isEmpty, value.trashed != true else { throw VaultFailure(message: "Google Drive returned an invalid folder entry.") }
                if let previous = ids[value.id] {
                    guard previous == value else { throw VaultFailure(message: "This Google Drive folder changed while loading. Refresh and retry.") }
                } else { ids[value.id] = value; result.append(value) }
            }
            guard result.count <= 100_000, tokens.count < 1000 else { throw VaultFailure(message: "This Google Drive folder is too large to browse in this preview.") }
            token = page.nextPageToken
            if let token { guard !token.isEmpty, tokens.insert(token).inserted else { throw VaultFailure(message: "Google Drive repeated a folder page. Retry loading this folder.") } }
        } while token != nil
        return result
    }
    /// Resolve every path component freshly by ID. Never follow shortcuts or
    /// choose one of several identically named files. After downloading, verify
    /// the file version and the complete ancestor chain before exposing bytes.
    func download(_ selection: NativeDriveFolder, path: String) async throws -> (Data, NativeDriveItem) {
        _ = try selection.validated()
        guard selection.accountID == accountID, let relative = NativeFileHub.relative(path), relative == path else { throw VaultFailure(message: "This file has an invalid Google Drive path.") }
        let root = try await metadata(selection.folderID)
        guard root.folder else { throw VaultFailure(message: "This Google Drive location is no longer a folder.") }
        var chain = [root], parent = root
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count <= 64 else { throw VaultFailure(message: "This Google Drive path is too deep.") }
        for (index, part) in parts.enumerated() {
            let candidates = try await children(parent.id, name: part).filter { $0.name == part }
            guard candidates.count == 1 else { throw VaultFailure(message: candidates.isEmpty ? "The linked document is unavailable in this Google Drive folder." : "Google Drive contains duplicate names along this path. Rename the copies before opening this document.") }
            let next = candidates[0]
            guard next.parents == [parent.id], !chain.contains(where: { $0.id == next.id }),
                  index == parts.count - 1 || next.folder else { throw VaultFailure(message: "This Google Drive item moved or is not an ordinary folder. Refresh the connection.") }
            chain.append(next); parent = next
        }
        let before = try await metadata(parent.id)
        guard before == parent, !before.mimeType.hasPrefix("application/vnd.google-apps."),
              let version = before.version, !version.isEmpty, let size = before.size.flatMap(Int.init), size >= 0, size <= Self.downloadLimit else { throw VaultFailure(message: "Choose an ordinary Google Drive file up to 50 MB. Google documents, shortcuts or files changing during lookup cannot be previewed.") }
        let bytes = try await response("/drive/v3/files/" + before.id, query: ["alt": "media"], limit: Self.downloadLimit)
        guard bytes.count == size else { throw VaultFailure(message: "This Google Drive file changed while downloading. Refresh and retry.") }
        for observed in chain {
            let current = try await metadata(observed.id)
            guard current == observed else { throw VaultFailure(message: "This Google Drive file or one of its folders changed while downloading. Refresh and retry.") }
        }
        return (bytes, before)
    }
}
