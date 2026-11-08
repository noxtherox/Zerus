import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
import ZerusChatGPTCore
@testable import ZerusNative

@MainActor
final class NativeChatAttachmentTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: NativeChat.directory(for: root))
        try FileManager.default.removeItem(at: root)
    }
    private func image() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let cg = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        }.cgImage)
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, [kCGImagePropertyOrientation: 6, kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 38.7, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination)); return bytes as Data
    }
    private func stage(_ values: [NativePreparedChatAttachment], in chat: NativeChat) async throws {
        let id = try XCTUnwrap(chat.beginAttachmentImport()); defer { chat.cancelAttachmentImport(id) }
        let admitted = try await chat.addAttachments(values, importID: id); XCTAssertTrue(admitted)
    }
    func testRealFilesExtractTextAndNormalizeOrientedPixelsWithoutChangingOriginals() async throws {
        let text = "Cobalt café 🌿 漢字", url = root.appendingPathComponent("UTF16.txt")
        let original = Data([0xff, 0xfe]) + (text.data(using: .utf16LittleEndian)!)
        try original.write(to: url)
        let prepared = try await NativePreparedChatAttachment.prepare(url)
        XCTAssertEqual(prepared.text, Data(text.utf8)); XCTAssertEqual(prepared.data, original)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 300))
        let pdf = renderer.pdfData { context in context.beginPage(); ("Cobalt PDF evidence" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 16)]) }
        let document = try NativePreparedChatAttachment.prepare(pdf, name: "Evidence.pdf")
        XCTAssertTrue(String(decoding: try XCTUnwrap(document.text), as: UTF8.self).contains("Cobalt PDF evidence")); XCTAssertEqual(document.descriptor.pages, 1)
        let blank = renderer.pdfData { $0.beginPage() }
        XCTAssertThrowsError(try NativePreparedChatAttachment.prepare(blank, name: "Scanned.pdf"))
        for data in [Data(), Data([1, 2, 3]), Data("   \n".utf8)] { XCTAssertThrowsError(try NativePreparedChatAttachment.prepare(data, name: "Unreadable.bin")) }
        let raw = try image(), source = root.appendingPathComponent("Camera.tiff"); try raw.write(to: source)
        let normalized = try await NativePreparedChatAttachment.prepare(source)
        XCTAssertEqual(normalized.descriptor.width, 683); XCTAssertEqual(normalized.descriptor.height, 1024)
        let jpg = try XCTUnwrap(CGImageSourceCreateWithData(normalized.data as CFData, nil))
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(jpg, 0, nil) as? [String: Any])
        XCTAssertNil(metadata[kCGImagePropertyGPSDictionary as String])
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(jpg, 0, nil))
        var pixels = [UInt8](repeating: 0, count: 16)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.draw(decoded, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let reds = stride(from: 0, to: 16, by: 4).map { pixels[$0] }, greens = stride(from: 1, to: 16, by: 4).map { pixels[$0] }
        XCTAssertGreaterThan(try XCTUnwrap(reds.min()), 220); XCTAssertLessThan(try XCTUnwrap(greens.min()), 40); XCTAssertGreaterThan(try XCTUnwrap(greens.max()), 220)
        XCTAssertEqual(try Data(contentsOf: source), raw); XCTAssertEqual(try Data(contentsOf: url), original)
        let oversized = root.appendingPathComponent("Large.txt"); FileManager.default.createFile(atPath: oversized.path, contents: Data())
        let handle = try FileHandle(forWritingTo: oversized); try handle.truncate(atOffset: UInt64(50 * 1024 * 1024 + 1)); try handle.close()
        do { _ = try await NativePreparedChatAttachment.prepare(oversized); XCTFail("Oversized provider files must be refused before extraction") } catch {}
    }
    func testFrozenDraftPreviewHistoryReuseAndStaleSessionProtection() async throws {
        let input = try NativePreparedChatAttachment.prepare(Data("Private source café".utf8), name: "Source.txt"), item = input.descriptor
        let chat = NativeChat(vaultRoot: root); chat.draft = "An unsent question"; try await stage([input], in: chat)
        let reopened = NativeChat(vaultRoot: root)
        XCTAssertEqual(reopened.attachments, [item]); XCTAssertEqual(reopened.draft, "An unsent question")
        let preview = try await chat.attachmentStore.preview(item)
        try Data("Changed preview only".utf8).write(to: preview.url)
        XCTAssertEqual(try chat.attachmentStore.read(item), input.data)
        let turn = try XCTUnwrap(chat.beginAgentTurn("Summarize source", attachments: [item])); chat.finishAgentTurn(turn, fallback: "Saved conversation")
        chat.consumeAttachments([item]); chat.clear()
        let archived = NativeChat(vaultRoot: root)
        XCTAssertEqual(archived.archives.first?.messages?.first?.attachments, [item]); archived.reuseAttachment(item)
        XCTAssertEqual(archived.attachments, [item])
        let stale = NativeChat(vaultRoot: root)
        archived.removeAttachment(item.id)
        XCTAssertNil(stale.beginAgentTurn("Stale send", attachments: [item])); XCTAssertTrue(stale.messages.isEmpty)
        XCTAssertEqual(try archived.attachmentStore.read(item), input.data, "Previously sent inputs remain available after removing a reused draft")
        let other = root.appendingPathComponent("OtherVault"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: NativeChat.directory(for: other)) }
        let second = NativeChat(vaultRoot: other); XCTAssertTrue(second.attachments.isEmpty)
        XCTAssertThrowsError(try second.attachmentStore.read(item))
        let unknown = Data(#"{"version":99,"items":[],"future":"keep"}"#.utf8)
        try FileManager.default.createDirectory(at: second.attachmentStore.directory, withIntermediateDirectories: true)
        try unknown.write(to: second.attachmentStore.draftURL)
        let protected = NativeChat(vaultRoot: other); protected.draft = "Keep my prompt"
        XCTAssertNil(protected.beginAttachmentImport()); XCTAssertEqual(try Data(contentsOf: second.attachmentStore.draftURL), unknown)
        protected.recoverAttachmentDraft(); XCTAssertNil(protected.attachmentProblem); XCTAssertEqual(protected.draft, "Keep my prompt")
        let recovery = try FileManager.default.contentsOfDirectory(at: second.attachmentStore.directory.appendingPathComponent("RecoveredAttachmentDrafts"), includingPropertiesForKeys: nil)
        XCTAssertEqual(recovery.count, 1); XCTAssertEqual(try Data(contentsOf: XCTUnwrap(recovery.first)), unknown)
    }
    func testHeldProviderCancellationAndExpiredImportCannotDeliverLateDrafts() async throws {
        let url = root.appendingPathComponent("Waiting.txt"), bytes = Data("Actual provider document".utf8); try bytes.write(to: url)
        for cancelTask in [true, false] {
            let chat = NativeChat(vaultRoot: root), id = try XCTUnwrap(chat.beginAttachmentImport()), gate = NativeProviderReadGate(url: url)
            NSFileCoordinator.addFilePresenter(gate)
            let returned = expectation(description: "The attachment caller returns")
            let read = Task { () -> Result<NativePreparedChatAttachment, Error> in
                let result: Result<NativePreparedChatAttachment, Error>
                do { result = .success(try await NativePreparedChatAttachment.prepare(url)) } catch { result = .failure(error) }
                returned.fulfill(); return result
            }
            await fulfillment(of: [gate.requested], timeout: 5)
            chat.cancelAttachmentImport(id)
            if cancelTask { read.cancel(); let result = await XCTWaiter.fulfillment(of: [returned], timeout: 1); XCTAssertEqual(result, .completed, "Cancel must release the UI while the provider is held") }
            gate.release(); NSFileCoordinator.removeFilePresenter(gate)
            if !cancelTask { await fulfillment(of: [returned], timeout: 5) }
            switch await read.value {
            case .success(let prepared):
                XCTAssertFalse(cancelTask)
                let admitted = try await chat.addAttachments([prepared], importID: id); XCTAssertFalse(admitted)
            case .failure(let error): XCTAssertTrue(cancelTask && error is CancellationError)
            }
            XCTAssertTrue(chat.attachments.isEmpty); XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }
    func testJournalAndActualResponsesRequestBindFrozenPixelsAndBoundedTextWithoutWriteAuthority() async throws {
        let image = try NativePreparedChatAttachment.prepare(try image(), name: "Evidence.tiff")
        let marker = "CobaltZebraLateEvidence"
        let text = String(repeating: "漢字 café reference text.\n", count: 12_000) + marker + " is the actual late document marker."
        let document = try NativePreparedChatAttachment.prepare(Data(text.utf8), name: "Long.txt")
        let store = NativeChatAttachmentStore(directory: NativeChat.directory(for: root))
        let items = try await store.commit([document, image])
        let input = try await NativeChatAttachmentInput.prepare(current: items, earlier: [], prompt: marker, store: store)
        XCTAssertLessThanOrEqual(input.reference.utf8.count, 61_000); XCTAssertTrue(input.reference.contains(marker)); XCTAssertTrue(input.reference.contains("excerpts only")); XCTAssertFalse(input.reference.contains("�"))
        let keep = root.appendingPathComponent("Keep.md"), original = Data("---\nzerus-id: keep\n---\n# Keep\nUnselected writing.\n".utf8); try original.write(to: keep)
        let io = VaultFiles(root: root), owner = "attachment-owner"
        var record = try await io.agentStart(objective: "Read " + marker, mode: .ask, scope: .init(), chatID: "attachment-chat", owner: owner, reference: input.reference, attachments: input.items, imageIDs: input.imageIDs)
        XCTAssertTrue(record.run.readIDs.isEmpty); XCTAssertTrue(record.run.writeIDs.isEmpty)
        XCTAssertThrowsError(try NativeChatAttachmentInput.providerMessages(record.run, store: store), "A vault journal cannot grant itself access to private image inputs")
        try store.authorize(run: record.id, chat: record.run.chatID, items: input.items)
        let cold = try NativeAgentJournal.decode(record.bytes, id: record.id)
        let payload = try NativeChatAttachmentInput.providerMessages(cold.run, store: store)
        XCTAssertEqual(payload.imageCount, 1)
        let request = try ChatGPTResponses.request(model: "synthetic-image-owner", agent: ["systemPrompt": "Read references within the frozen scope.", "messages": payload.messages])
        let content = try XCTUnwrap((request["input"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        XCTAssertTrue(try XCTUnwrap(content.first?["text"] as? String).contains(marker))
        let dataURL = try XCTUnwrap(content.first { $0["type"] as? String == "input_image" }?["image_url"] as? String)
        XCTAssertTrue(dataURL.hasPrefix("data:image/jpeg;base64,")); XCTAssertEqual(Data(base64Encoded: String(dataURL.dropFirst("data:image/jpeg;base64,".count))), image.data)
        let call = NativeAgentCall(id: "forbidden", name: "note_create", arguments: #"{"title":"Injected","body":"Attachment instructions","folder":""}"#)
        record = try await io.agentResponse(record, owner: owner, content: "", calls: [call], input: 1, output: 1, seconds: 0.1)
        record = try await io.agentTool(record, owner: owner, call: call)
        let refusal = try JSONSerialization.jsonObject(with: Data(XCTUnwrap(record.run.messages.last).content.utf8)) as? [String: Any]
        XCTAssertEqual(refusal?["ok"] as? Bool, false); XCTAssertTrue(record.run.proposals.isEmpty); XCTAssertTrue(record.run.receipts.isEmpty)
        var forgedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: cold.bytes) as? [String: Any]); forgedObject["chatID"] = "another-conversation"
        let forged = try NativeAgentJournal.decode(JSONSerialization.data(withJSONObject: forgedObject), id: cold.id).run
        XCTAssertThrowsError(try NativeChatAttachmentInput.providerMessages(forged, store: store))
        let frozen = store.directory.appendingPathComponent("Attachments/" + image.descriptor.id.uuidString.lowercased() + "/original.jpg")
        var tampered = image.data; tampered[tampered.count / 2] ^= 1; try tampered.write(to: frozen)
        XCTAssertThrowsError(try NativeChatAttachmentInput.providerMessages(cold.run, store: store))
        XCTAssertEqual(try Data(contentsOf: keep), original); XCTAssertEqual(try store.read(document.descriptor), document.data)
    }
}
