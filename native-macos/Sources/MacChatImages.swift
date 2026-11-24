import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MacChatImage: Identifiable, Sendable {
    let id: String
    let name: String
    let width: Int
    let height: Int
    let bytes: Data
    var metadata: [String: Any] { ["id": id, "name": name, "mimeType": "image/jpeg", "width": width, "height": height, "byteLength": bytes.count] }
    func metadata(conversationID: String) -> [String: Any] {
        var result = metadata; result["path"] = ".zerus/chats/" + conversationID + "/assets/" + id + ".jpg"; return result
    }
    static func restore(_ metadata: [String: Any], bytes: Data) throws -> MacChatImage {
        let id = try MacConversations.checkedID(MacConversations.string(metadata, "id"))
        guard metadata["mimeType"] as? String == "image/jpeg", NativeHistory.integer(metadata["byteLength"]) == bytes.count,
              !bytes.isEmpty, bytes.count <= 3 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = NativeHistory.integer(properties[kCGImagePropertyPixelWidth]), let height = NativeHistory.integer(properties[kCGImagePropertyPixelHeight]),
              width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 40_000_000,
              NativeHistory.integer(metadata["width"]) == width, NativeHistory.integer(metadata["height"]) == height else { throw VaultFailure(message: "A chat image is incomplete or unsupported. Its existing files are preserved; locate the original before retrying.") }
        return .init(id: id, name: String((metadata["name"] as? String ?? "Image.jpg").prefix(255)), width: width, height: height, bytes: bytes)
    }
    static func prepare(_ url: URL) throws -> MacChatImage {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 50 * 1024 * 1024 else { throw VaultFailure(message: "Choose an image smaller than 50 MB.") }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw VaultFailure(message: "This image could not be opened.") }
        return try prepare(source, name: url.lastPathComponent)
    }
    static func prepare(_ bytes: Data, name: String) throws -> MacChatImage {
        guard !bytes.isEmpty, bytes.count <= 50 * 1024 * 1024, let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw VaultFailure(message: "Choose a supported image smaller than 50 MB.") }
        return try prepare(source, name: name)
    }
    private static func prepare(_ source: CGImageSource, name: String) throws -> MacChatImage {
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw VaultFailure(message: "This image could not be opened. Choose a supported photo or screenshot.") }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard let flattened = context.makeImage() else { throw VaultFailure(message: "The image could not be prepared.") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw VaultFailure(message: "JPEG encoding is unavailable.") }
        CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length <= 3 * 1024 * 1024 else { throw VaultFailure(message: "The prepared image is too large. Choose a smaller image.") }
        return .init(id: UUID().uuidString.lowercased(), name: String(name.prefix(255)), width: flattened.width, height: flattened.height, bytes: data as Data)
    }
}

extension VaultFiles {
    nonisolated static func chatImageChanges(_ images: [MacChatImage], conversationID: String, root: URL) throws -> [VaultFileChange] {
        guard images.count <= 4, Set(images.map(\.id)).count == images.count else { throw VaultFailure(message: "Choose up to four different images per message.") }
        return try images.map { image in
            _ = try MacChatImage.restore(image.metadata, bytes: image.bytes)
            let path = image.metadata(conversationID: conversationID)["path"] as! String
            let folder = root.appendingPathComponent(".zerus/chats/" + conversationID + "/assets")
            if MacConversations.entryExists(folder), try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw VaultFailure(message: "Linked chat image folders are preserved without writing through them.") }
            _ = try confinedPath(for: root.appendingPathComponent(path), root: root)
            return .init(path: path, before: nil, after: image.bytes)
        }
    }
    func conversationImages(_ message: MacConversationMessage, conversationID: String) throws -> [MacChatImage] {
        let raw = try MacConversations.object(message.raw)
        return try conversationImages(raw["attachments"], conversationID: conversationID)
    }
    func conversationImages(_ value: Any?, conversationID: String) throws -> [MacChatImage] {
        guard let value, !(value is NSNull) else { return [] }
        guard let metadata = value as? [[String: Any]], metadata.count <= 4 else { throw VaultFailure(message: "This message has unsupported image attachments. Its original data is preserved.") }
        return try metadata.map { item in
            try Task.checkCancellation()
            let id = try MacConversations.checkedID(MacConversations.string(item, "id")), path = ".zerus/chats/" + conversationID + "/assets/" + id + ".jpg"
            guard item["path"] as? String == path else { throw VaultFailure(message: "This image points outside its conversation. Its original data is preserved.") }
            let file = try url(for: path), values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            let folder = file.deletingLastPathComponent()
            guard values.isRegularFile == true, values.isSymbolicLink != true, try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true, (values.fileSize ?? Int.max) <= 3 * 1024 * 1024 else { throw VaultFailure(message: "A chat image is linked, unavailable or too large. Locate its original before retrying.") }
            return try MacChatImage.restore(item, bytes: read(path))
        }
    }
}
