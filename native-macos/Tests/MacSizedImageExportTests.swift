import XCTest
import AppKit
import PDFKit
import ImageIO
@testable import Zerus_Native

@MainActor final class MacSizedImageExportTests: XCTestCase {
    func testExportsEmbedSizedOccurrencesIndependentlyWithoutChangingVaultFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<32 { for y in 0..<16 { bitmap.setColor((x / 4 + y / 4) % 2 == 0 ? NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1) : NSColor(deviceRed: 1, green: 0.5, blue: 0, alpha: 1), atX: x, y: y) } }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let evidence = (0..<25).map { "Paragraph-\($0)-start " + String(repeating: "A complete paragraph stays readable around image and page boundaries. ", count: 8) + " Paragraph-\($0)-end" }.joined(separator: "\n\n")
        let source = "# Sized export\n\n<img src=\"assets/plot.png\" alt=\"Wide\" title=\"Review\" width=\"240\" height=\"90\" />\n\n<img src=\"assets/plot.png\" alt=\"Small\" width=\"80\" height=\"30\" />\n\n![Legacy|120](assets/plot.png)\n\nEND-SENTINEL\n\nA <u>underlined</u> phrase.\n\nWhitespace A<u>&#32;&#32;&#32;</u>B.\n\n<u>&#32;&#32;&#32;</u>\n\nWhitespace end.\n" + evidence + "\n"
        let bytes = Data(source.utf8), note = NoteDocument(path: "Note.md", content: source, modified: Date())
        try bytes.write(to: root.appendingPathComponent(note.path)); try png.write(to: root.appendingPathComponent("assets/plot.png"))
        let document = try await VaultFiles(root: root).exportDocument(note, includeProperties: false)
        XCTAssertTrue(document.warnings.isEmpty)
        for format in NativeExportFormat.allCases {
            let artifact = try NativeNoteExport.artifact(document, format: format)
            defer { try? FileManager.default.removeItem(at: artifact.url.deletingLastPathComponent()) }
            switch format {
            case .html:
                let html = try String(contentsOf: artifact.url, encoding: .utf8)
                XCTAssertEqual(html.components(separatedBy: "src=\"data:image/png;base64,").count - 1, 3)
                for size in ["width=\"240\" height=\"90\"", "width=\"80\" height=\"30\"", "width=\"120\" height=\"60\""] { XCTAssertTrue(html.contains(size)) }
                XCTAssertTrue(html.contains("<u>underlined</u>"))
                let imported = try NSAttributedString(data: Data(html.utf8), options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
                let whitespace = (imported.string as NSString).range(of: "Whitespace A   B.")
                XCTAssertNotEqual(whitespace.location, NSNotFound, "HTML and the Mac PDF importer must preserve every underlined space")
                if whitespace.location != NSNotFound {
                    for index in (whitespace.location + 12)..<(whitespace.location + 15) {
                        XCTAssertEqual(imported.attribute(.underlineStyle, at: index, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
                    }
                }
                XCTAssertTrue(imported.string.contains("\n   \n"), "The HTML/PDF importer must retain a whitespace-only paragraph; glyph painting is verified separately")
                XCTAssertTrue(html.contains("title=\"Review\"")); XCTAssertFalse(html.contains("&lt;img"))
            case .docx:
                let pipe = Pipe(), process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-p", artifact.url.path, "word/document.xml"]; process.standardOutput = pipe
                try process.run(); let xml = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); process.waitUntilExit()
                XCTAssertEqual(process.terminationStatus, 0)
                let underlinedRun = xml.components(separatedBy: "<w:r>").first { $0.contains(">underlined</w:t>") }
                XCTAssertTrue(underlinedRun?.contains("<w:u w:val=\"single\"/>") == true, "The plain underlined phrase needs its own Word underline, independent of links")
                for size in ["cx=\"2194560\" cy=\"822960\"", "cx=\"731520\" cy=\"274320\"", "cx=\"1097280\" cy=\"548640\""] { XCTAssertTrue(xml.contains(size)) }
                XCTAssertEqual(xml.components(separatedBy: "<wp:inline ").count - 1, 3)
            case .pdf:
                let pdf = try XCTUnwrap(PDFDocument(url: artifact.url)); XCTAssertTrue(pdf.string?.contains("END-SENTINEL") ?? false)
                XCTAssertGreaterThan(pdf.pageCount, 1)
                let text = (pdf.string ?? "").filter { !$0.isWhitespace }
                for index in 0..<25 {
                    XCTAssertEqual(text.components(separatedBy: "Paragraph-\(index)-start").count - 1, 1)
                    XCTAssertEqual(text.components(separatedBy: "Paragraph-\(index)-end").count - 1, 1)
                }
                var imageCount = 0
                for index in 0..<pdf.pageCount {
                    var resources: CGPDFDictionaryRef?, objects: CGPDFDictionaryRef?
                    if let dictionary = pdf.page(at: index)?.pageRef?.dictionary, CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources, CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects {
                        CGPDFDictionaryApplyFunction(objects, { _, object, info in
                            var stream: CGPDFStreamRef?, subtype: UnsafePointer<CChar>?
                            if CGPDFObjectGetValue(object, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream), CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image", let info { info.assumingMemoryBound(to: Int.self).pointee += 1 }
                        }, &imageCount)
                    }
                }
                XCTAssertGreaterThan(imageCount, 0, "The exported PDF must contain image resources, not attachment placeholders")
            }
        }
        // A blank underlined run has no text glyphs that could accidentally
        // satisfy the raster check. The matching plain run must remain blank.
        for (text, underlined) in [("        ", false), ("        ", true), ("        X        ", true)] {
            let spacing = NativeExportDocument(title: "Spacing", blocks: [.paragraph([.init(text: text, style: underlined ? .underline : [])])], properties: [])
            let rendered = try NativePDFExport.render(spacing)
            let spacingPage = try XCTUnwrap(PDFDocument(data: rendered)?.page(at: 0))
            let bitmap = try XCTUnwrap(CGContext(data: nil, width: 595, height: 842, bitsPerComponent: 8, bytesPerRow: 595 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            bitmap.setFillColor(NSColor.white.cgColor); bitmap.fill(CGRect(x: 0, y: 0, width: 595, height: 842))
            bitmap.drawPDFPage(try XCTUnwrap(spacingPage.pageRef))
            let pixels = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
            var ink = 0
            for pixel in 0..<(595 * 842) {
                if pixels[pixel * 4] < 200 && pixels[pixel * 4 + 1] < 200 && pixels[pixel * 4 + 2] < 200 { ink += 1 }
            }
            if underlined {
                XCTAssertGreaterThan(ink, 20, "A PDF must paint explicitly underlined spaces even without a visible letter")
                var longest = 0
                for row in 0..<842 {
                    var run = 0
                    for column in 0..<595 {
                        let pixel = (row * 595 + column) * 4
                        if pixels[pixel] < 200 && pixels[pixel + 1] < 200 && pixels[pixel + 2] < 200 { run += 1; longest = max(longest, run) }
                        else { run = 0 }
                    }
                }
                XCTAssertGreaterThan(longest, 20, "The underline must cover the spaces; the letter X alone cannot satisfy this width")
            } else { XCTAssertEqual(ink, 0, "Unformatted whitespace must not gain a decoration") }
        }
        let printed = try await MacExport.preparePrint(MacExportRequest(note: note, body: source, root: root))
        XCTAssertTrue(printed.warnings.isEmpty)
        let page = try XCTUnwrap(printed.document.page(at: 0))
        // Read the top of the actual print document at natural point scale.
        // Scaling a long legacy text view down to a thumbnail would hide the
        // difference between a real image and its unavailable placeholder.
        let width = 600, height = 842
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let bounds = page.bounds(for: .mediaBox)
        context.translateBy(x: -bounds.minX, y: CGFloat(height) - bounds.maxY)
        context.drawPDFPage(try XCTUnwrap(page.pageRef))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var blue = 0, orange = 0
        for pixel in 0..<(width * height) {
            let r = pixels[pixel * 4], g = pixels[pixel * 4 + 1], b = pixels[pixel * 4 + 2]
            if b > 180 && r < 80 && g < 150 { blue += 1 }
            if r > 180 && g > 50 && g < 220 && b < 100 { orange += 1 }
        }
        XCTAssertGreaterThan(blue, 1000, "Printing must include the local blue/orange bitmap, not an unavailable-image placeholder")
        XCTAssertGreaterThan(orange, 1000, "Printing must include the local blue/orange bitmap, not syntax-coloured text")
        let missing = try await MacExport.preparePrint(MacExportRequest(note: note, body: source + "\n![Unavailable](assets/missing.png)\n", root: root))
        XCTAssertTrue(missing.warnings.contains { $0.contains("assets/missing.png") }, "Printing must report a missing image before opening the print panel")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(note.path)), bytes)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/plot.png")), png)

        // Compressed byte size is not a bound on the decoded bitmap. These are
        // real, valid, solid PNGs, rather than damaged headers that fail later.
        let dimensions = [("wide", 16_385, 1), ("tall", 1, 16_385), ("area", 6_401, 6_250), ("edge", 16_384, 1)]
        var imageBytes: [String: Data] = [:]
        for (name, w, h) in dimensions {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite, bytesPerRow: 0, bitsPerPixel: 0))
            memset(try XCTUnwrap(bitmap.bitmapData), 128, bitmap.bytesPerRow * h)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let decoded = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
            XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, w)
            XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, h)
            XCTAssertLessThan(data.count, 1_000_000, "The compressed file must be small enough to pass the existing byte budget")
            imageBytes[name] = data
            try data.write(to: root.appendingPathComponent("assets/\(name).png"))
        }
        let boundedBody = "![Ordinary](assets/plot.png)\n\n" + dimensions.map { "![Kept-\($0.0)](assets/\($0.0).png)" }.joined(separator: "\n\n")
        let bounded = try await VaultFiles(root: root).exportDocument(NoteDocument(path: note.path, content: boundedBody, modified: Date()), includeProperties: false)
        XCTAssertNotNil(bounded.images["assets/plot.png"])
        XCTAssertNotNil(bounded.images["assets/edge.png"], "An image exactly at the side limit remains supported")
        for name in ["wide", "tall", "area"] {
            XCTAssertNil(bounded.images["assets/\(name).png"], "An oversized source must not be decoded into an export thumbnail")
            XCTAssertTrue(bounded.warnings.contains { $0.contains("assets/\(name).png") && $0.contains("40 megapixels") }, "The user must be told why this image is omitted")
        }
        let boundedHTML = NativeHTMLExport.render(bounded)
        XCTAssertEqual(boundedHTML.components(separatedBy: "src=\"data:image/png;base64,").count - 1, 2)
        for name in ["wide", "tall", "area"] { XCTAssertTrue(boundedHTML.contains("[Kept-\(name)]")) }
        for (name, data) in imageBytes { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/\(name).png")), data) }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(note.path)), bytes)
    }
}
