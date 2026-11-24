import AppKit
import ImageIO

/// Read-only, selected-version pixels. Never resolves an uncaptured reference
/// against today's files. Pages bound decoded memory without hiding later images.
struct MacHistoryPreview: @unchecked Sendable {
    let content: String
    let images: [String: NSImage]
    let warnings: [String]
    let page: Int
    let pages: Int
    let imageCount: Int
    static let pageSize = 8
}

extension VaultFiles {
    func macHistoryPreview(_ snapshot: MacRecoverySnapshot, id: String, page: Int = 0) async throws -> MacHistoryPreview {
        try Task.checkCancellation()
        guard root == snapshot.root, let history = snapshot.history, history.root == root,
              history.versions.filter({ $0.id == id }).count == 1,
              let version = history.versions.first(where: { $0.id == id }), version.content != nil else {
            throw VaultFailure(message: "This saved version is unavailable. Refresh history in its original vault.")
        }
        guard try historyData(version.path) == version.bytes else { throw VaultFailure(message: "This history record changed. Refresh before previewing its saved images.") }
        let content = try historyPreview(version)
        let references = Set(MarkdownText.imageReferences(NoteDocument.split(content).body))
        var hashes: [String] = [], seen = Set<String>()
        for row in version.object["images"] as? [[String: Any]] ?? [] {
            if let hash = row["hash"] as? String, hash.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
               references.contains(".zerus/history/blobs/" + hash), seen.insert(hash).inserted { hashes.append(hash) }
        }
        let pages = max(1, (hashes.count + MacHistoryPreview.pageSize - 1) / MacHistoryPreview.pageSize)
        let page = min(max(0, page), pages - 1), start = page * MacHistoryPreview.pageSize
        var images: [String: NSImage] = [:], warnings: [String] = []
        for hash in hashes.dropFirst(start).prefix(MacHistoryPreview.pageSize) {
            try Task.checkCancellation()
            let path = ".zerus/history/blobs/" + hash
            do {
                let bytes = try await imagePreviewData(path, notePath: snapshot.note.path)
                guard NativeHistory.hash(bytes) == hash else { throw VaultFailure(message: "Its saved bytes changed or are still syncing.") }
                guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = NativeHistory.integer(properties[kCGImagePropertyPixelWidth]), let height = NativeHistory.integer(properties[kCGImagePropertyPixelHeight]),
                      width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 40_000_000 else {
                    throw VaultFailure(message: "Its image dimensions are unsupported (maximum 16,384 pixels per side and 40 megapixels).")
                }
                guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 720, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                    throw VaultFailure(message: "Its saved image could not be decoded.")
                }
                try Task.checkCancellation()
                images[path] = NSImage(cgImage: thumbnail, size: .init(width: thumbnail.width, height: thumbnail.height))
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("Saved image " + String(hash.prefix(12)) + ": " + error.localizedDescription) }
        }
        try Task.checkCancellation()
        guard try historyData(version.path) == version.bytes else { throw VaultFailure(message: "This history record changed. Refresh before previewing its saved images.") }
        return .init(content: content, images: images, warnings: warnings, page: page, pages: pages, imageCount: hashes.count)
    }
}

extension MacWorkspace {
    func historyPreview(_ snapshot: MacRecoverySnapshot, id: String, page: Int = 0) async throws -> MacHistoryPreview {
        guard snapshot.workspaceID == workspaceID, snapshot.root == root, let io else { throw VaultFailure(message: "The vault changed. Reopen history before previewing saved images.") }
        let preview = try await io.macHistoryPreview(snapshot, id: id, page: page)
        try Task.checkCancellation()
        guard snapshot.workspaceID == workspaceID, snapshot.root == root else { throw CancellationError() }
        return preview
    }
}
