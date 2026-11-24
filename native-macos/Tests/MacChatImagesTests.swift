import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Zerus_Native

final class MacChatImagesTests: XCTestCase {
    func testImagePreparationAndPortableStoragePreserveOriginalAndRejectMissingOrEscapingAssets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-chat-images-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Original.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 2048, height: 512, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5)); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        let source = try XCTUnwrap(context.makeImage()), destination = try XCTUnwrap(CGImageDestinationCreateWithURL(original as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, source, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 40.0]] as CFDictionary); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let originalBytes = try Data(contentsOf: original), prepared = try MacChatImage.prepare(original)
        XCTAssertEqual(prepared.width, 1024); XCTAssertEqual(prepared.height, 256)
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        let jpeg = try XCTUnwrap(CGImageSourceCreateWithData(prepared.bytes as CFData, nil)), properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(jpeg, 0, nil) as? [CFString: Any])
        XCTAssertEqual(CGImageSourceGetType(jpeg) as String?, UTType.jpeg.identifier); XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let io = VaultFiles(root: root), device = MacChatDevice(id: "mac", name: "Mac")
        let saved = try await io.createConversation(device: device, text: "Review this image", scope: MacConversations.data(["kind": "vault"]), images: [prepared])
        let message = try XCTUnwrap(saved.conversation.messages.first), loaded = try await io.conversationImages(message, conversationID: saved.conversation.id)
        XCTAssertEqual(loaded.first?.bytes, prepared.bytes); XCTAssertEqual(loaded.first?.name, "Original.png")
        let asset = root.appendingPathComponent(".zerus/chats/" + saved.conversation.id + "/assets/" + prepared.id + ".jpg"), preserved = root.appendingPathComponent("Preserved.jpg")
        try FileManager.default.moveItem(at: asset, to: preserved)
        do { _ = try await io.conversationImages(message, conversationID: saved.conversation.id); XCTFail("A missing image must not be silently omitted") } catch {}
        try FileManager.default.createSymbolicLink(at: asset, withDestinationURL: preserved)
        do { _ = try await io.conversationImages(message, conversationID: saved.conversation.id); XCTFail("Image aliases must not be sent") } catch {}
        var raw = try MacConversations.object(message.raw), metadata = prepared.metadata(conversationID: saved.conversation.id)
        metadata["path"] = "Original.png"; raw["attachments"] = [metadata]
        let changed = try await io.changeConversation(saved, device: device, change: .message(MacConversations.data(raw)))
        do { _ = try await io.conversationImages(XCTUnwrap(changed.conversation.messages.first), conversationID: saved.conversation.id); XCTFail("An attachment cannot read another vault file") } catch {}
        XCTAssertEqual(try Data(contentsOf: preserved), prepared.bytes)
        for (path, bytes) in saved.records { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), bytes) }
        do { _ = try await io.createConversation(device: device, text: "Too many images", scope: MacConversations.data(["kind": "vault"]), images: Array(repeating: prepared, count: 5)); XCTFail("Image limit must be checked before committing a conversation") } catch {}
        let all = try await io.conversations(); XCTAssertEqual(all.conversations.count, 1)
    }
}
