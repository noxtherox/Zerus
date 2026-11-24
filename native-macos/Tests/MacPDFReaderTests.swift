import XCTest
import AppKit
import PDFKit
import CoreText
@testable import Zerus_Native

@MainActor final class MacPDFReaderTests: XCTestCase {
    // Exercises asynchronous PDFKit callbacks and selection navigation against a real, searchable PDF.
    func testSearchReplacementCaseMatchingAndPageNavigation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try pdfData(["Alpha alpha on page one\n😀 Office résumé ＡＢＣ\nTwo words\nLine\nbreak\nCafé file", "Alpha on page two"]).write(to: url)
        let reader = MacPDFReader(url: url)
        reader.search("alpha", matchCase: false)
        try await finish(reader)
        XCTAssertEqual(reader.matches.count, 3)
        reader.moveMatch(1); reader.moveMatch(1)
        XCTAssertEqual(reader.currentPage, 2)
        XCTAssertEqual(reader.matchIndex, 2)
        reader.moveMatch(1)
        XCTAssertEqual(reader.currentPage, 1)
        reader.search("Alpha", matchCase: true)
        try await finish(reader)
        XCTAssertEqual(reader.matches.count, 2)
        reader.search("Alpha", matchCase: false)
        await Task.yield() // Allow an in-flight page search before replacement.
        reader.cancelSearch()
        reader.search("unmatched", matchCase: false)
        try await finish(reader)
        XCTAssertTrue(reader.matches.isEmpty)
        XCTAssertEqual(reader.searchStatus, "No matches")
        reader.goToPage("2")
        XCTAssertEqual(reader.currentPage, 2)
        reader.goToPage("999")
        XCTAssertEqual(reader.currentPage, 2)
        // The desktop's NFKD/whitespace search must highlight the original PDF
        // text, including characters and line breaks absent from the query.
        for (query, expected) in [
            ("Alpha   alpha", ["Alpha alpha"]),
            ("alpha\talpha", ["Alpha alpha"]),
            ("ABC", ["ＡＢＣ"]),
            ("ＡＢＣ", ["ＡＢＣ"]),
            ("Two\nwords", ["Two words"]),
            ("Line break", ["Line\nbreak"]),
            ("oﬃce", ["Office"]),
            ("re\u{301}sume\u{301}", ["résumé"]),
            ("CAFÉ", ["Café"]),
            ("ﬁle", ["file"]),
            ("😀", ["😀"]),
            ("   ", [])
        ] {
            reader.search(query, matchCase: false); try await finish(reader)
            XCTAssertEqual(reader.matches.compactMap(\.string), expected, query)
            if !expected.isEmpty { XCTAssertEqual(reader.currentPage, 1, query) }
        }
        reader.search("OFFICE", matchCase: true); try await finish(reader)
        XCTAssertTrue(reader.matches.isEmpty, "The native Match case option remains effective after normalization")
        reader.search("ABC", matchCase: true); try await finish(reader)
        XCTAssertEqual(reader.matches.compactMap(\.string), ["ＡＢＣ"])
    }
    func testPasswordUnlockEnablesSearchAndNavigationWithoutChangingEncryptedOriginal() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let plain = try XCTUnwrap(PDFDocument(data: pdfData(["Private alpha on page one", "Private beta on page two"])))
        let encrypted = try XCTUnwrap(plain.dataRepresentation(options: [PDFDocumentWriteOption.ownerPasswordOption: "owner-fixture", PDFDocumentWriteOption.userPasswordOption: "reader-fixture"]))
        try encrypted.write(to: url)
        let reader = MacPDFReader(url: url)
        XCTAssertTrue(reader.locked); XCTAssertNil(reader.view.document)
        reader.search("Private", matchCase: false); XCTAssertFalse(reader.searching); XCTAssertTrue(reader.matches.isEmpty)
        XCTAssertFalse(reader.unlock(password: "wrong")); XCTAssertTrue(reader.locked)
        XCTAssertTrue(reader.unlockIssue?.contains("did not unlock") == true)
        XCTAssertTrue(reader.unlock(password: "reader-fixture")); XCTAssertFalse(reader.locked); XCTAssertNil(reader.unlockIssue)
        XCTAssertNotNil(reader.view.document)
        reader.search("Private", matchCase: true); try await finish(reader)
        XCTAssertEqual(reader.matches.count, 2)
        reader.moveMatch(1); XCTAssertEqual(reader.currentPage, 2)
        reader.goToPage("1"); XCTAssertEqual(reader.currentPage, 1)
        XCTAssertEqual(try Data(contentsOf: url), encrypted)
        let reopened = MacPDFReader(url: url); XCTAssertTrue(reopened.locked, "Unlocking a preview must not decrypt the original")
    }
    private func pdfData(_ texts: [String]) throws -> Data {
        let bytes = NSMutableData()
        let output = try XCTUnwrap(CGDataConsumer(data: bytes as CFMutableData))
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = try XCTUnwrap(CGContext(consumer: output, mediaBox: &page, nil))
        for text in texts {
            context.beginPDFPage(nil)
            let rich = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 20)])
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(rich), CFRange(location: 0, length: rich.length), CGPath(rect: page.insetBy(dx: 40, dy: 50), transform: nil), nil)
            CTFrameDraw(frame, context); context.endPDFPage()
        }
        context.closePDF(); return bytes as Data
    }
    private func finish(_ reader: MacPDFReader) async throws {
        for _ in 0..<150 {
            if !reader.searching { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("PDF search did not finish")
    }
}
