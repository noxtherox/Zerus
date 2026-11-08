import XCTest
import PDFKit
import ImageIO
import zlib
@testable import ZerusNative

final class NativeNoteExportTests: XCTestCase {
    private var root: URL!
    private var artifacts: [URL] = []
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
        for url in artifacts { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
    private func write(_ path: String, _ bytes: Data) throws {
        let url = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try bytes.write(to: url)
    }
    private func image(_ color: UIColor = .orange) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 160, height: 80)).pngData { context in UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 80)); color.setFill(); context.fill(CGRect(x: 12, y: 15, width: 90, height: 50)) }
    }
    @MainActor
    func testExportedFilesContainEditableStructuresEmbeddedImagesCurrentDraftAndOnlyVisiblePropertiesWithoutChangingTheVault() async throws {
        let original = "---\nzerus-id: export-note\nzerus-private: DO-NOT-EXPORT\nOwner: Tiago & team\nReady: true\n---\n# Export record\n\nDisk baseline.\n"
        let originalImage = image()
        try write("Work/Record.md", Data(original.utf8)); try write("Work/images/chart space.png", originalImage)
        let store = VaultStore(); await store.open(root)
        var note = try XCTUnwrap(store.notes.first)
        note.content = note.replacingBody("""
        # Export record

        A **bold** and *italic* thought with ~~removed~~ text, `literal <tag>`, and [a useful link](https://example.com/report?a=1&b=2).

        [[zerus:other|Related thought]]

        3. First ordered item
        4. Second ordered item
           - Nested item

        - [x] Completed step
        - [ ] Open step

        1234567. Large starting number

        <!-- zerus-table-widths: 120,240 -->

        | Item | Quantity |
        | :--- | ---: |
        | Evidence | **Two** |
        | <strong>Native cell</strong><em>adjacent</em><s>strike</s> | Safe styles |

        > A quoted thought.

        ![Orange diagram](images/chart%20space.png)

        ```swift
        let comparison = "<not markup>"
        ```

        ~~~text
        [[zerus:literal|Code alias]]
        ~~~

            [[zerus:indented|Indented alias]]

        <script>alert('never run')</script>

        Current unsaved draft.<!-- hidden-inline -->
        """)
        for format in NativeExportFormat.allCases {
            let result = try await store.exportNote(note, format: format, includeProperties: true); artifacts.append(result.url)
            let evidence = XCTAttachment(data: try Data(contentsOf: result.url), uniformTypeIdentifier: format == .pdf ? "com.adobe.pdf" : format == .docx ? "org.openxmlformats.wordprocessingml.document" : "public.html"); evidence.name = "Native rich note export." + format.rawValue; evidence.lifetime = .keepAlways; add(evidence)
            XCTAssertEqual(result.url.pathExtension, format.rawValue)
            XCTAssertTrue(result.warnings.contains { $0.contains("HTML") }); XCTAssertTrue(result.warnings.contains { $0.contains("Internal note") })
            switch format {
            case .html:
                let xml = try ExportXML(Data(contentsOf: result.url))
                XCTAssertTrue(xml.allText.contains("Current unsaved draft.")); XCTAssertTrue(xml.allText.contains("Tiago & team")); XCTAssertFalse(xml.allText.contains("DO-NOT-EXPORT"))
                XCTAssertFalse(xml.allText.contains("zerus-table-widths")); XCTAssertFalse(xml.allText.contains("hidden-inline"))
                XCTAssertEqual(xml.nodes("script").count, 0); XCTAssertTrue(xml.nodes("strong").contains { $0.text == "bold" })
                XCTAssertTrue(xml.nodes("strong").contains { $0.text == "Native cell" }); XCTAssertTrue(xml.nodes("em").contains { $0.text == "adjacent" }); XCTAssertTrue(xml.nodes("s").contains { $0.text == "strike" })
                XCTAssertEqual(xml.nodes("ol").first?.attributes["start"], "3"); XCTAssertEqual(xml.nodes("img").first?.attributes["alt"], "Orange diagram")
                XCTAssertTrue(xml.nodes("ol").contains { $0.attributes["start"] == "1234567" })
                let source = try XCTUnwrap(xml.nodes("img").first?.attributes["src"]); XCTAssertTrue(source.hasPrefix("data:image/png;base64,"))
                let embedded = try XCTUnwrap(Data(base64Encoded: String(source.dropFirst("data:image/png;base64,".count)))); XCTAssertNotNil(CGImageSourceCreateWithData(embedded as CFData, nil))
                XCTAssertTrue(xml.nodes("td").contains { $0.text == "Evidence" })
                XCTAssertTrue(xml.nodes("code").contains { $0.text.contains("[[zerus:literal|Code alias]]") }); XCTAssertTrue(xml.nodes("code").contains { $0.text.contains("[[zerus:indented|Indented alias]]") })
            case .docx:
                let entries = try unzip(Data(contentsOf: result.url)), document = try ExportXML(try XCTUnwrap(entries["word/document.xml"]))
                XCTAssertTrue(document.allText.contains("Current unsaved draft.")); XCTAssertTrue(document.allText.contains("Tiago & team")); XCTAssertFalse(document.allText.contains("DO-NOT-EXPORT"))
                XCTAssertFalse(document.allText.contains("zerus-table-widths")); XCTAssertFalse(document.allText.contains("hidden-inline"))
                XCTAssertTrue(document.nodes("w:pStyle").contains { $0.attributes["w:val"] == "Heading1" }); XCTAssertFalse(document.nodes("w:numPr").isEmpty)
                XCTAssertEqual(document.nodes("w:tbl").count, 2); XCTAssertEqual(document.nodes("wp:inline").count, 1)
                XCTAssertTrue(document.nodes("w:t").contains { $0.text.contains("☑") }); XCTAssertTrue(document.nodes("w:b").count >= 2)
                for (text, style) in [("Native cell", "w:b"), ("adjacent", "w:i"), ("strike", "w:strike")] {
                    XCTAssertTrue(document.nodes("w:r").contains { $0.text == text && $0.children.first(where: { $0.name == "w:rPr" })?.children.contains(where: { $0.name == style }) == true }, text)
                }
                XCTAssertFalse(document.allText.contains("<strong>"))
                let numbers = try ExportXML(try XCTUnwrap(entries["word/numbering.xml"])); XCTAssertTrue(numbers.nodes("w:start").contains { $0.attributes["w:val"] == "3" })
                XCTAssertTrue(numbers.nodes("w:start").contains { $0.attributes["w:val"] == "1234567" })
                let rels = try ExportXML(try XCTUnwrap(entries["word/_rels/document.xml.rels"])); XCTAssertTrue(rels.nodes("Relationship").contains { $0.attributes["Target"] == "https://example.com/report?a=1&b=2" && $0.attributes["TargetMode"] == "External" })
                XCTAssertNotNil(CGImageSourceCreateWithData(try XCTUnwrap(entries["word/media/image1.png"]) as CFData, nil))
                XCTAssertTrue(document.allText.contains("[[zerus:literal|Code alias]]")); XCTAssertTrue(document.allText.contains("[[zerus:indented|Indented alias]]"))
                for (name, bytes) in entries where name.hasSuffix(".xml") || name.hasSuffix(".rels") { _ = try ExportXML(bytes) }
            case .pdf:
                let pdf = try XCTUnwrap(PDFDocument(url: result.url)), text = pdf.string ?? ""
                XCTAssertTrue(text.contains("Current unsaved draft.")); XCTAssertTrue(text.contains("Tiago & team")); XCTAssertTrue(text.contains("Evidence")); XCTAssertFalse(text.contains("DO-NOT-EXPORT"))
                XCTAssertFalse(text.contains("zerus-table-widths")); XCTAssertFalse(text.contains("hidden-inline"))
                XCTAssertTrue(text.contains("Native cell")); XCTAssertTrue(text.contains("adjacent")); XCTAssertFalse(text.contains("<strong>"))
                XCTAssertGreaterThan(pdf.pageCount, 0); XCTAssertTrue((0..<pdf.pageCount).contains { pdfImages(pdf.page(at: $0)) > 0 }, "The actual diagram must be embedded in PDF resources")
            }
        }
        let hidden = try await store.exportNote(note, format: .html, includeProperties: false); artifacts.append(hidden.url)
        let hiddenXML = try ExportXML(Data(contentsOf: hidden.url)); XCTAssertFalse(hiddenXML.allText.contains("Tiago & team")); XCTAssertTrue(hiddenXML.allText.contains("Current unsaved draft."))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Record.md")), Data(original.utf8)); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/images/chart space.png")), originalImage)
    }

    func testPDFPaginatesLongParagraphsAndOversizedTableRowsWithoutDroppingOrRepeatingText() async throws {
        let paragraphs = (0..<40).map { "Paragraph-\($0)-start " + String(repeating: "A complete thought needs room to breathe. ", count: 25) + " Paragraph-\($0)-end" }
        let cells = (0..<180).map { "Cell-\($0)-evidence" }.joined(separator: " ")
        let body = "# Long export\n\n" + paragraphs.joined(separator: "\n\n") + "\n\n| Long cell | Other cell |\n| --- | --- |\n| " + cells + " | Short companion |\n\nLAST-SENTINEL\n"
        let note = NoteDocument(path: "Long.md", content: body, modified: Date())
        try write(note.path, Data(body.utf8))
        let snapshot = try await VaultFiles(root: root).exportDocument(note, includeProperties: false)
        let file = try NativeNoteExport.artifact(snapshot, format: .pdf); artifacts.append(file.url)
        let pdf = try XCTUnwrap(PDFDocument(url: file.url)), text = pdf.string ?? ""
        let attachment = XCTAttachment(data: try Data(contentsOf: file.url), uniformTypeIdentifier: "com.adobe.pdf"); attachment.name = "Native export pagination and oversized table row"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertGreaterThan(pdf.pageCount, 5); XCTAssertLessThan(pdf.pageCount, 100)
        for index in 0..<40 { XCTAssertTrue(text.contains("Paragraph-\(index)-start")); XCTAssertTrue(text.contains("Paragraph-\(index)-end")) }
        let continuous = text.filter { !$0.isWhitespace }
        for index in 0..<180 { XCTAssertEqual(continuous.components(separatedBy: "Cell-\(index)-evidence").count - 1, 1, "Every long-cell marker must survive once across PDF line wraps") }
        XCTAssertTrue(text.contains("Short companion")); XCTAssertTrue(text.contains("LAST-SENTINEL"))
    }

    @MainActor
    func testExportNeverReadsOutsideVaultOrFetchesRemoteImagesAndRejectsOldVaultProvenance() async throws {
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".png")
        try image(.blue).write(to: outside); defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.png"), withDestinationURL: outside)
        let content = "# Boundary / export:*? " + String(repeating: "🧑🏽‍💻", count: 40) + "\n\n![Outside](escape.png) ![Missing](missing.png) ![Remote](https://invalid.example/no-network.png)\n\n[Unsafe](javascript:alert(1))\n"
        try write("Boundary.md", Data(content.utf8))
        let store = VaultStore(); await store.open(root); let note = try XCTUnwrap(store.notes.first)
        let file = try await store.exportNote(note, format: .html, includeProperties: true); artifacts.append(file.url)
        let xml = try ExportXML(Data(contentsOf: file.url)); XCTAssertTrue(xml.nodes("img").isEmpty); XCTAssertTrue(xml.nodes("a").isEmpty)
        XCTAssertTrue(file.warnings.contains { $0.contains("escape.png") }); XCTAssertTrue(file.warnings.contains { $0.contains("missing.png") }); XCTAssertTrue(file.warnings.contains { $0.contains("no network") })
        XCTAssertFalse(String(decoding: try Data(contentsOf: file.url), as: UTF8.self).contains(outside.path))
        let other = root.appendingPathComponent("Other", isDirectory: true); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await store.open(other); await store.open(root)
        do { _ = try await store.exportNote(note, format: .docx, includeProperties: false); XCTFail("A→B→A must not publish a prior activation's export") } catch {}
        XCTAssertFalse(file.url.lastPathComponent.contains { "/:*?\n".contains($0) }); XCTAssertFalse(file.url.lastPathComponent.hasPrefix("."))
    }

    /// Independent ZIP reader checks entry lengths and zlib CRCs, then the tests
    /// parse OOXML with the platform XML parser rather than the export writer.
    private func unzip(_ bytes: Data) throws -> [String: Data] {
        func integer(_ offset: Int, _ count: Int) -> Int { (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) } }
        var offset = 0, entries: [String: Data] = [:]
        while offset + 30 <= bytes.count, integer(offset, 4) == 0x04034b50 {
            XCTAssertEqual(integer(offset + 8, 2), 0)
            let count = integer(offset + 18, 4), nameCount = integer(offset + 26, 2), extraCount = integer(offset + 28, 2), start = offset + 30 + nameCount + extraCount
            XCTAssertLessThanOrEqual(start + count, bytes.count)
            let name = String(decoding: bytes[(offset + 30)..<(offset + 30 + nameCount)], as: UTF8.self), data = Data(bytes[start..<(start + count)])
            let checksum = data.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)) }
            XCTAssertEqual(UInt32(checksum), UInt32(integer(offset + 14, 4))); XCTAssertNil(entries[name]); entries[name] = data; offset = start + count
        }
        XCTAssertEqual(integer(offset, 4), 0x02014b50); XCTAssertEqual(integer(bytes.count - 22, 4), 0x06054b50)
        XCTAssertEqual(integer(bytes.count - 12, 2), entries.count); return entries
    }
    private func pdfImages(_ page: PDFPage?) -> Int {
        guard let dictionary = page?.pageRef?.dictionary else { return 0 }
        var resources: CGPDFDictionaryRef?, objects: CGPDFDictionaryRef?, count = 0
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources, CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return 0 }
        CGPDFDictionaryApplyFunction(objects, { _, object, info in
            var stream: CGPDFStreamRef?, subtype: UnsafePointer<CChar>?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream), CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image", let info { info.assumingMemoryBound(to: Int.self).pointee += 1 }
        }, &count)
        return count
    }
}

private final class ExportXML: NSObject, XMLParserDelegate {
    final class Node { let name: String; let attributes: [String: String]; var text = ""; var children: [Node] = []; init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes } }
    private var stack: [Node] = [], values: [Node] = []
    var allText = ""
    init(_ data: Data) throws {
        super.init(); let parser = XMLParser(data: data); parser.delegate = self; parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw parser.parserError ?? NSError(domain: "Invalid export XML", code: 1) }
    }
    func nodes(_ name: String) -> [Node] { values.filter { $0.name == name } }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) { let node = Node(elementName, attributeDict); values.append(node); stack.last?.children.append(node); stack.append(node) }
    func parser(_ parser: XMLParser, foundCharacters string: String) { allText += string; for node in stack { node.text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { stack.removeLast() }
}
