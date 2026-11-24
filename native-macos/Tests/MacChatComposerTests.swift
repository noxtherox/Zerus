import XCTest
import AppKit
@testable import Zerus_Native

@MainActor final class MacChatComposerTests: XCTestCase {
    func testPasteboardFilesPrepareOneMixedSelectionAndRecoverWithoutOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-chat-input-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let draft = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/Drafts/Chat/" + NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.absoluteString) + ".json")
        let board = NSPasteboard.withUniqueName()
        defer {
            board.releaseGlobally()
            for folder in ["Images", "Documents"] { try? FileManager.default.removeItem(at: draft.deletingLastPathComponent().appendingPathComponent(folder + "/" + draft.deletingPathExtension().lastPathComponent)) }
            try? FileManager.default.removeItem(at: draft); try? FileManager.default.removeItem(at: root)
        }
        _ = try makeChatTestImage(in: root)
        let imageURL = root.appendingPathComponent("Synthetic.png"), documentURL = root.appendingPathComponent("Decision.md")
        let originalImage = try Data(contentsOf: imageURL), content = "# Decision\nKeep images and documents together.\n"
        try Data(content.utf8).write(to: documentURL)
        XCTAssertTrue(board.writeObjects([imageURL as NSURL, documentURL as NSURL]))
        let inputs = try XCTUnwrap(MacChatAttachmentInput.read(board)); XCTAssertEqual(inputs.count, 2)
        let dropped = try await MacChatAttachmentInput.read([NSItemProvider(object: imageURL as NSURL), NSItemProvider(object: documentURL as NSURL)])
        XCTAssertEqual(dropped.count, 2)
        let prepared = try await MacChatAttachmentInput.prepare(dropped, imageCount: 0, documentCount: 0, documentBytes: 0)
        let chat = MacChatController(root: root, device: .init(id: "input-test", name: "Input test"))
        chat.draft = "Unsent local question"
        try chat.addAttachments(images: prepared.images, documents: prepared.documents)
        XCTAssertEqual(try Data(contentsOf: imageURL), originalImage)
        XCTAssertEqual(try String(contentsOf: documentURL, encoding: .utf8), content)
        try FileManager.default.removeItem(at: imageURL); try FileManager.default.removeItem(at: documentURL)
        let recovered = MacChatController(root: root, device: .init(id: "input-test", name: "Input test"))
        XCTAssertEqual(recovered.draft, "Unsent local question")
        XCTAssertEqual(recovered.selectedImages.first?.bytes, prepared.images.first?.bytes)
        XCTAssertEqual(recovered.selectedDocuments.first?.name, "Decision.md"); XCTAssertEqual(recovered.selectedDocuments.first?.text, content)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus/chats").path), "Attaching must not create portable events or contact a provider")
        let bad = MacChatDocument(id: UUID().uuidString.lowercased(), name: "Empty.txt", text: "")
        XCTAssertThrowsError(try recovered.addAttachments(images: prepared.images, documents: [bad]))
        XCTAssertEqual(recovered.selectedImages.count, 1); XCTAssertEqual(recovered.selectedDocuments.count, 1)
        let afterFailure = MacChatController(root: root, device: .init(id: "input-test", name: "Input test"))
        XCTAssertEqual(afterFailure.selectedImages.count, 1); XCTAssertEqual(afterFailure.selectedDocuments.first?.text, content)
    }
    func testAppKitSelectionReaderAcceptsImagePasteWithoutReplacingText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-chat-AppKit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally(); try? FileManager.default.removeItem(at: root) }
        _ = try makeChatTestImage(in: root)
        board.setData(try Data(contentsOf: root.appendingPathComponent("Synthetic.png")), forType: .png)
        let view = MacChatTextView(); view.isRichText = false; view.string = "Keep my question"; view.acceptsAttachments = true
        var attached: [MacChatAttachmentInput] = []; view.attach = { attached += $0 }
        XCTAssertTrue(view.readSelection(from: board, type: .png), "AppKit must be able to read the image type advertised to Paste validation")
        XCTAssertEqual(attached.count, 1); XCTAssertEqual(view.string, "Keep my question")
    }
    func testClipboardImageRepresentationsAreDeduplicatedAndTextURLsStayText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-chat-clipboard-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally(); try? FileManager.default.removeItem(at: root) }
        _ = try makeChatTestImage(in: root)
        let png = try Data(contentsOf: root.appendingPathComponent("Synthetic.png")), item = NSPasteboardItem()
        item.setData(png, forType: .png); item.setData(try XCTUnwrap(NSImage(data: png)?.tiffRepresentation), forType: .tiff)
        XCTAssertTrue(board.writeObjects([item]))
        let inputs = try XCTUnwrap(MacChatAttachmentInput.read(board)); XCTAssertEqual(inputs.count, 1)
        // Snapshot bytes survive a later clipboard change.
        board.clearContents(); board.setString("https://example.com/reference.png", forType: .string)
        XCTAssertNil(try MacChatAttachmentInput.read(board))
        let prepared = try await MacChatAttachmentInput.prepare(inputs, imageCount: 0, documentCount: 0, documentBytes: 0)
        XCTAssertEqual(prepared.images.count, 1); XCTAssertEqual(prepared.images.first?.width, 12); XCTAssertEqual(prepared.images.first?.height, 8)
        do { _ = try await MacChatAttachmentInput.prepare(inputs, imageCount: 4, documentCount: 0, documentBytes: 0); XCTFail("Pasting cannot exceed the message image limit") } catch {}
        let cancelled = Task { try await MacChatAttachmentInput.prepare(inputs, imageCount: 0, documentCount: 0, documentBytes: 0) }; cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled preparation must not publish a selection") } catch is CancellationError {} catch { XCTFail("Expected cancellation, got \(error)") }
    }
}
