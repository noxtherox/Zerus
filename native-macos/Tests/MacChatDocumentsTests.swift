import XCTest
import CoreText
@testable import Zerus_Native

final class MacChatDocumentsTests: XCTestCase {
    func testSelectedTextEncodingsAndPDFExtractionKeepOriginalsAndRefuseUnreadableInputs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-chat-documents-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let text = "Café 日本語\r\nOriginal text remains intact.\n"
        let cases: [(String, Data)] = [("UTF8.txt", Data([0xef, 0xbb, 0xbf]) + Data(text.utf8)), ("UTF16LE.txt", Data([0xff, 0xfe]) + text.data(using: .utf16LittleEndian)!), ("UTF16BE.txt", Data([0xfe, 0xff]) + text.data(using: .utf16BigEndian)!) ]
        for (name, bytes) in cases {
            let file = root.appendingPathComponent(name); try bytes.write(to: file)
            let document = try await MacChatDocument.prepare(file)
            XCTAssertEqual(document.name, name); XCTAssertEqual(document.text, text); XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
        for (name, bytes) in [("Binary.zip", Data([0x50, 0x4b, 0, 1])), ("Bad.txt", Data([0xc3, 0x28])), ("Empty.md", Data("  \n".utf8)), ("Surrogate.txt", Data([0xff, 0xfe, 0, 0xd8]))] {
            let file = root.appendingPathComponent(name); try bytes.write(to: file)
            do { _ = try await MacChatDocument.prepare(file); XCTFail("Unreadable input must not become empty context: " + name) } catch {}
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
        let pdf = root.appendingPathComponent("Reference.pdf"), bytes = try pdfData("Independent PDF evidence")
        try bytes.write(to: pdf); let extracted = try await MacChatDocument.prepare(pdf)
        XCTAssertTrue(extracted.text.contains("Independent PDF evidence")); XCTAssertEqual(try Data(contentsOf: pdf), bytes)
        let blank = root.appendingPathComponent("Scan.pdf"); try pdfData(nil).write(to: blank)
        do { _ = try await MacChatDocument.prepare(blank); XCTFail("A PDF without text must request OCR instead of sending empty context") } catch { XCTAssertTrue(error.localizedDescription.contains("OCR")) }
        let oversized = root.appendingPathComponent("Oversized.txt"); FileManager.default.createFile(atPath: oversized.path, contents: Data())
        let handle = try FileHandle(forWritingTo: oversized); try handle.truncate(atOffset: 50 * 1024 * 1024 + 1); try handle.close()
        do { _ = try await MacChatDocument.prepare(oversized); XCTFail("Inputs above 50 MB must fail before extraction") } catch { XCTAssertTrue(error.localizedDescription.contains("50 MB")) }
        XCTAssertEqual(try oversized.resourceValues(forKeys: [.fileSizeKey]).fileSize, 50 * 1024 * 1024 + 1)
    }
    func testLargePortableDocumentRetainsFullTextWhileRequestContextSelectsLabeledRelevantExcerpts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-large-chat-document-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let text = String(repeating: "Ordinary production record.\n", count: 200_000) + "\nUNIQUE_WELDCLOUD_SETTING: current is 45 amps.\n"
        XCTAssertGreaterThan(text.utf8.count, 4 * 1024 * 1024)
        let document = MacChatDocument(id: UUID().uuidString.lowercased(), name: "Records.txt", text: text), io = VaultFiles(root: root)
        let saved = try await io.createConversation(device: .init(id: "mac", name: "Mac"), text: "Find UNIQUE_WELDCLOUD_SETTING", scope: MacConversations.data(["kind": "selection", "noteIds": []]), documents: [document])
        let reopened = try await io.conversationSnapshot(saved.conversation.id), input = try await io.conversationInput(XCTUnwrap(reopened.conversation.messages.first), conversationID: saved.conversation.id)
        XCTAssertEqual(input.documents.first?.text, text)
        let context = try MacChatDocumentContext.select(input.documents, question: "UNIQUE_WELDCLOUD_SETTING", existingText: "Question and system instructions", imageCount: 0, capacity: 32_768)
        XCTAssertTrue(context.excerpts); XCTAssertTrue(context.text.contains("UNIQUE_WELDCLOUD_SETTING: current is 45 amps.")); XCTAssertTrue(context.text.contains("not the full document")); XCTAssertLessThanOrEqual(context.text.utf8.count, context.budget)
        XCTAssertThrowsError(try MacChatDocumentContext.select(input.documents, question: "setting", existingText: String(repeating: "x", count: 40_000), imageCount: 0, capacity: 32_768))
        let short = MacChatDocument(id: "short", name: "Small.md", text: "Complete reference text")
        let full = try MacChatDocumentContext.select([short], question: "summarize", existingText: "", imageCount: 0, capacity: 4096)
        XCTAssertFalse(full.excerpts); XCTAssertTrue(full.text.contains("Complete reference text")); XCTAssertFalse(full.text.contains("excerpts only"))
        for (path, bytes) in saved.records { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), bytes) }
    }
    private func pdfData(_ text: String?) throws -> Data {
        let data = NSMutableData(), consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil)); context.beginPDFPage(nil)
        if let text {
            context.textPosition = CGPoint(x: 30, y: 700)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)]))
            CTLineDraw(line, context)
        }
        context.endPDFPage(); context.closePDF(); return data as Data
    }
}
