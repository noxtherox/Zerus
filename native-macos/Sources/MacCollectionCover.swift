import SwiftUI
import ImageIO
import Markdown

struct MacCollectionResourceVersion: Hashable, Sendable {
    let path: String
    let modified: Date?
    let created: Date?
}
struct MacCollectionCoverImage: Sendable {
    let image: CGImage
    let caption: String
    let reference: String
}

/// Card previews share two permits and a bounded decoded-image cache. A stalled
/// provider does not reserve a lane for later cards; cancelled waiters leave FIFO.
actor MacCollectionCoverLoader {
    static let shared = MacCollectionCoverLoader()
    private struct Waiter { let id: UUID; let continuation: CheckedContinuation<Void, Error> }
    private struct Key: Hashable { let workspace: UUID; let note: String; let reference: String; let versions: [MacCollectionResourceVersion] }
    private struct Cached { let image: CGImage; var used: UInt64 }
    private var active = 0
    private var waiters: [Waiter] = []
    private var cache: [Key: Cached] = [:]
    private var clock: UInt64 = 0
    private var cacheBytes = 0
    private func acquire() async throws {
        try Task.checkCancellation()
        if active < 2 { active += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append(.init(id: id, continuation: continuation)) }
            }
        }, onCancel: { Task { await self.cancel(id) } })
    }
    private func cancel(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) { waiters.remove(at: index).continuation.resume(throwing: CancellationError()) }
    }
    private func release() {
        if waiters.isEmpty { active -= 1 }
        else { waiters.removeFirst().continuation.resume() }
    }
    nonisolated static func versions(reference: String, notePath: String, dates: [String: NativeFileDates]) -> [MacCollectionResourceVersion] {
        guard let parsed = URL(string: reference), parsed.scheme == nil else { return [] }
        let decoded = parsed.relativePath
        guard !decoded.isEmpty, !decoded.hasPrefix("/"), !decoded.contains("\\") else { return [] }
        let logical = notePath.hasPrefix(".trash/") ? String(notePath.dropFirst(7)) : notePath
        let folder = (logical as NSString).deletingLastPathComponent
        func path(_ folder: String) -> String { String(URL(fileURLWithPath: "/" + folder, isDirectory: true).appendingPathComponent(parsed.relativePath).standardizedFileURL.path.dropFirst()) }
        let relative = path(folder), absolute = path("")
        let paths = decoded.hasPrefix("assets/") || decoded.hasPrefix(".zerus/") ? [absolute, relative] : [relative, absolute]
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }.map { .init(path: $0, modified: dates[$0]?.modified, created: dates[$0]?.created) }
    }
    func load(note: NoteDocument, io: VaultFiles, workspaceID: UUID, fileDates: [String: NativeFileDates]) async throws -> MacCollectionCoverImage? {
        try Task.checkCancellation()
        var pending: [any Markup] = [Document(parsing: note.parts.body)]
        var first: MacInlineImage?
        while let node = pending.popLast() {
            try Task.checkCancellation()
            if let image = node as? Markdown.Image { first = MacInlineImage(image); break }
            if let html = node as? InlineHTML, let image = MacInlineImage(html: html.rawHTML) { first = image; break }
            if let html = node as? HTMLBlock, let image = MacInlineImage(html: html.rawHTML) { first = image; break }
            pending.append(contentsOf: node.children.reversed())
        }
        guard let first else { return nil }
        let key = Key(workspace: workspaceID, note: note.path, reference: first.reference, versions: Self.versions(reference: first.reference, notePath: note.path, dates: fileDates))
        func cached() -> MacCollectionCoverImage? {
            guard var value = cache[key] else { return nil }
            clock &+= 1; value.used = clock; cache[key] = value
            return .init(image: value.image, caption: first.caption, reference: first.reference)
        }
        if let image = cached() { return image }
        try await acquire(); defer { release() }
        try Task.checkCancellation()
        if let image = cached() { return image }
        let bytes = try await io.imagePreviewData(first.reference, notePath: note.path)
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = NativeHistory.integer(properties[kCGImagePropertyPixelWidth]), let height = NativeHistory.integer(properties[kCGImagePropertyPixelHeight]),
              width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 40_000_000 else {
            throw VaultFailure(message: "This card image exceeds the supported dimensions (16,384 pixels per side or 40 megapixels).")
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 720, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw VaultFailure(message: "The card image could not be previewed.") }
        try Task.checkCancellation()
        let cost = image.bytesPerRow * image.height
        let versionDate = key.versions.compactMap(\.modified).first
        if cost <= 32_000_000, let versionDate, versionDate != .distantPast {
            if let old = cache.removeValue(forKey: key) { cacheBytes -= old.image.bytesPerRow * old.image.height }
            while cacheBytes + cost > 32_000_000, let oldest = cache.min(by: { $0.value.used < $1.value.used }) {
                cacheBytes -= oldest.value.image.bytesPerRow * oldest.value.image.height; cache.removeValue(forKey: oldest.key)
            }
            clock &+= 1; cache[key] = .init(image: image, used: clock); cacheBytes += cost
        }
        return .init(image: image, caption: first.caption, reference: first.reference)
    }
}

struct MacCollectionCover: View {
    let note: NoteDocument
    let io: VaultFiles?
    let workspaceID: UUID
    let fileDates: [String: NativeFileDates]
    private struct Identity: Hashable { let workspace: UUID; let path: String }
    private struct Request: Hashable { let identity: Identity; let body: String; let versions: [MacCollectionResourceVersion] }
    @State private var loaded: MacCollectionCoverImage?
    @State private var loadedFor: Identity?
    private var identity: Identity { .init(workspace: workspaceID, path: note.path) }
    private var request: Request {
        let versions = loadedFor == identity ? loaded.map { MacCollectionCoverLoader.versions(reference: $0.reference, notePath: note.path, dates: fileDates) } ?? [] : []
        return .init(identity: identity, body: note.parts.body, versions: versions)
    }
    var body: some View {
        VStack(spacing: 0) {
            if loadedFor == identity, let loaded {
                GeometryReader { geometry in
                    Image(loaded.image, scale: 1, label: Text(loaded.caption.isEmpty ? "Image in " + note.title : loaded.caption))
                        .resizable().scaledToFill().frame(width: max(0, geometry.size.width), height: 140).clipped()
                }.frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 6))
            } else { Color.clear.frame(height: 0) }
        }.task(id: request) {
            guard let io else { loaded = nil; loadedFor = nil; return }
            do {
                let image = try await MacCollectionCoverLoader.shared.load(note: note, io: io, workspaceID: workspaceID, fileDates: fileDates)
                try Task.checkCancellation()
                loaded = image; loadedFor = identity
            } catch is CancellationError { /* Keep the current cover during a newer request. */ }
            catch { loaded = nil; loadedFor = identity }
        }
    }
}
