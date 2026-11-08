import XCTest
import UIKit
import Markdown
@testable import ZerusNative

final class NativeCellEditingTests: XCTestCase {
    @MainActor
    func testNativeCellFormattingKeepsPortableTableTextLinksImagesLiteralCodeAndAdjacentStyles() throws {
        XCTAssertEqual(NativeCellMarkdown.render("").string, "")
        XCTAssertEqual(NativeCellMarkdown.render("  ").string, "  ")
        let asset = UIGraphicsImageRenderer(size: CGSize(width: 17, height: 29)).image { context in UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 17, height: 29)) }
        let spacedImage = NativeCellMarkdown.render("![Space](<assets/plot space.png>)", images: ["assets/plot%20space.png": asset])
        XCTAssertEqual((spacedImage.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?.image?.size, asset.size, "Cell editing must use the same normalized asset key as the note image loader")
        let firstImage = #"![π](assets/plot.png "first")"#, secondImage = #"![other](assets/plot.png "second")"#
        let source = "## Literal | 🧭 " + firstImage + " " + secondImage + #" [docs](https://example.com/a_(b) "Guide") [[zerus:stable|Some note]] `[[Do not link]]`"#
        XCTAssertTrue(NativeCellMarkdown.supports(source))
        let rich = NSMutableAttributedString(attributedString: NativeCellMarkdown.render(source))
        XCTAssertTrue(rich.string.hasPrefix("## Literal | 🧭 "), rich.string)
        XCTAssertTrue(rich.string.contains("Some note [[Do not link]]"), rich.string)
        let edited = (rich.string as NSString).range(of: "Literal")
        rich.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 17), range: edited)
        let cell = try NativeCellMarkdown.serialize(rich)
        XCTAssertTrue(cell.contains(firstImage), cell); XCTAssertTrue(cell.contains(secondImage), cell)
        let table = MarkdownTable(rows: [["Text", "Untouched"], [cell, "original"]], widths: [120, 240])
        let document = Document(parsing: table.markdown)
        var images: [Markdown.Image] = [], links: [Markdown.Link] = [], codes: [InlineCode] = [], strong: [Strong] = []
        func inspect(_ node: any Markup) {
            if let image = node as? Markdown.Image { images.append(image) }
            if let link = node as? Markdown.Link { links.append(link) }
            if let code = node as? InlineCode { codes.append(code) }
            if let value = node as? Strong { strong.append(value) }
            for child in node.children { inspect(child) }
        }
        inspect(document)
        XCTAssertEqual(images.map(\.source), ["assets/plot.png", "assets/plot.png"])
        XCTAssertEqual(images.map(\.title), ["first", "second"])
        XCTAssertEqual(codes.map(\.code), ["[[Do not link]]"])
        XCTAssertEqual(strong.first?.plainText, "Literal")
        let web = try XCTUnwrap(links.first)
        XCTAssertEqual(URL(string: try XCTUnwrap(web.destination))?.path, "/a_(b)")
        XCTAssertEqual(web.title, "Guide")
        XCTAssertEqual(NoteReference.references(in: table.markdown).map(\.target), ["zerus:stable"])
        XCTAssertTrue(table.markdown.contains("<!-- zerus-table-widths: 120,240 -->"))
        XCTAssertEqual(MarkdownTable.blocks(in: table.markdown).first?.table.rows.last?.last, "original")

        // Parse the actual table as GFM, then inspect its rendered HTML using
        // Foundation's XML parser. Inline-only Foundation Markdown does not
        // implement HTML or all GFM strikethrough boundaries.
        for left in 0..<8 { for right in 0..<8 {
            let value = NSMutableAttributedString(string: "ab")
            for (index, flags) in [left, right].enumerated() {
                var traits: UIFontDescriptor.SymbolicTraits = []
                if flags & 1 != 0 { traits.insert(.traitBold) }; if flags & 2 != 0 { traits.insert(.traitItalic) }
                value.addAttribute(.font, value: MarkdownText.font(traits: traits), range: NSRange(location: index, length: 1))
                if flags & 4 != 0 { value.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: index, length: 1)) }
            }
            let encoded = try NativeCellMarkdown.serialize(value)
            let html = HTMLFormatter.format(MarkdownTable(rows: [["Header"], [encoded]]).markdown)
            let reader = CellHTMLReader(), parser = XMLParser(data: Data(("<root>" + html + "</root>").utf8)); parser.delegate = reader
            XCTAssertTrue(parser.parse(), html)
            XCTAssertEqual(reader.text, "ab", "\(left),\(right): \(encoded)")
            XCTAssertEqual(reader.styles, [left, right], encoded)
            XCTAssertTrue(NativeCellMarkdown.supports(encoded), encoded)
            XCTAssertEqual(String(TableCellContent.rich(encoded).characters), "ab", encoded)
        } }
        for literal in ["`edge", "``inside``", " both ", "   ", "[[Not a link]]"] {
            let value = NSAttributedString(string: literal, attributes: [.font: UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)])
            let encoded = try NativeCellMarkdown.serialize(value), parsed = Document(parsing: encoded)
            XCTAssertEqual((parsed.child(at: 0)?.child(at: 0) as? InlineCode)?.code, literal, encoded)
        }
        for (source, expectedText, expectedStyles, destination) in [
            ("[**bold** plain](#zerus-note:zerus%3Aalpha%7Cbold%20plain)", "bold plain", Array(repeating: 1, count: 4) + Array(repeating: 0, count: 6), "#zerus-note:zerus%3Aalpha%7Cbold%20plain"),
            ("[`code` plain](#zerus-note:zerus%3Aalpha%7Ccode%20plain)", "code plain", Array(repeating: 8, count: 4) + Array(repeating: 0, count: 6), "#zerus-note:zerus%3Aalpha%7Ccode%20plain"),
            ("[`code`](#zerus-note:zerus%3Aalpha%7Ccode)", "code", Array(repeating: 8, count: 4), "#zerus-note:zerus%3Aalpha%7Ccode")
        ] {
            let encoded = try NativeCellMarkdown.serialize(NativeCellMarkdown.render(source))
            let html = HTMLFormatter.format(MarkdownTable(rows: [["Header"], [encoded]]).markdown)
            let reader = CellHTMLReader(), parser = XMLParser(data: Data(("<root>" + html + "</root>").utf8)); parser.delegate = reader
            XCTAssertTrue(parser.parse(), html)
            XCTAssertEqual(reader.text, expectedText, encoded)
            XCTAssertEqual(reader.styles, expectedStyles, encoded)
            XCTAssertEqual(reader.links, [destination], "One selected label must stay one link: " + encoded)
            XCTAssertTrue(NativeCellMarkdown.supports(encoded), encoded)
            XCTAssertEqual(NativeCellMarkdown.render(encoded).string, expectedText)
        }
        let boldCode = NativeCellMarkdown.render("**`bold`**")
        XCTAssertTrue((boldCode.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertFalse(NativeCellMarkdown.supports("<u>preserve HTML</u>"))
        XCTAssertFalse(NativeCellMarkdown.supports("before <!-- keep this comment --> after"))
        XCTAssertFalse(NativeCellMarkdown.supports("[caption][shared-definition]"))
        XCTAssertTrue(NativeCellMarkdown.supports(#"\[caption\]\[literal\]"#))
        XCTAssertThrowsError(try NativeCellMarkdown.serialize(NSAttributedString(attachment: NSTextAttachment())))
        XCTAssertThrowsError(try NativeCellMarkdown.serialize(NSAttributedString(string: "one\ntwo")))
        XCTAssertThrowsError(try NativeCellMarkdown.serialize(NSAttributedString(string: "underlined", attributes: [.underlineStyle: 1])))
    }
}

private final class CellHTMLReader: NSObject, XMLParserDelegate {
    var tags: [String] = [], text = "", styles: [Int] = [], links: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) { tags.append(elementName); if elementName == "a", let href = attributeDict["href"] { links.append(href) } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { tags.removeLast() }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard tags.contains("td") else { return }
        let flags = (tags.contains("strong") || tags.contains("b") ? 1 : 0) | (tags.contains("em") || tags.contains("i") ? 2 : 0) | (tags.contains("del") || tags.contains("s") || tags.contains("strike") ? 4 : 0) | (tags.contains("code") ? 8 : 0)
        text += string; styles += Array(repeating: flags, count: string.count)
    }
}
