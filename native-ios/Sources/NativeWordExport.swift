import Foundation

/// Writes standard editable OOXML, with stored ZIP entries. No web runtime or
/// office application is involved in exporting the user's note.
struct NativeWordExport {
    let document: NativeExportDocument
    private var relationships: [(String, String, String, Bool)] = []
    private var media: [(String, Data)] = []
    private var imageIDs: [String: (String, Int)] = [:]
    private var numbering: [(Int, Int?)] = []
    private var drawingID = 0
    private let e = NativeNoteExport.escape

    static func render(_ document: NativeExportDocument) throws -> Data {
        var writer = Self(document: document)
        return try writer.render()
    }
    private mutating func relationship(_ kind: String, target: String, external: Bool = false) -> String {
        let id = "rId\(relationships.count + 3)"
        relationships.append((id, kind, target, external)); return id
    }
    private mutating func inline(_ runs: [NativeExportRun], bold: Bool = false, imageWidth: Double = 600) -> String {
        runs.map { run -> String in
            if let reference = run.image, let image = document.images[reference] {
                let binding: (String, Int)
                if let existing = imageIDs[reference] { binding = existing }
                else {
                    let index = media.count + 1, name = "image\(index).png"
                    let id = relationship("image", target: "media/" + name)
                    media.append(("word/media/" + name, image.bytes)); binding = (id, index); imageIDs[reference] = binding
                }
                drawingID += 1
                let factor = min(1, imageWidth / max(1, image.width), 750 / max(1, image.height))
                let width = Int(image.width * factor * 9144), height = Int(image.height * factor * 9144)
                return """
                <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(width)" cy="\(height)"/><wp:docPr id="\(drawingID)" name="Image \(drawingID)" descr="\(e(run.text))"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(drawingID)" name="Image \(drawingID)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(binding.0)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(width)" cy="\(height)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
                """
            }
            let text = run.image != nil ? "[" + run.text + "]" : run.text
            var properties = ""
            let family = run.style.contains(.code) ? "Courier New" : "Arial"
            properties += "<w:rFonts w:ascii=\"\(family)\" w:hAnsi=\"\(family)\"/>"
            if bold || run.style.contains(.bold) { properties += "<w:b/>" }
            if run.style.contains(.italic) { properties += "<w:i/>" }
            if run.style.contains(.strike) { properties += "<w:strike/>" }
            if run.link != nil { properties += "<w:color w:val=\"9A4526\"/><w:u w:val=\"single\"/>" }
            if run.style.contains(.code) { properties += "<w:shd w:fill=\"F4F1EF\"/>" }
            let pieces = text.components(separatedBy: "\n").enumerated().map { index, line in
                (index > 0 ? "<w:br/>" : "") + line.components(separatedBy: "\t").enumerated().map { index, segment in (index > 0 ? "<w:tab/>" : "") + "<w:t xml:space=\"preserve\">" + e(segment) + "</w:t>" }.joined()
            }.joined()
            let value = "<w:r><w:rPr>" + properties + "</w:rPr>" + pieces + "</w:r>"
            if let link = run.link { let id = relationship("hyperlink", target: link, external: true); return "<w:hyperlink r:id=\"" + id + "\">" + value + "</w:hyperlink>" }
            return value
        }.joined()
    }
    private mutating func paragraph(_ runs: [NativeExportRun], heading: Int = 0, indent: Int = 0, num: Int? = nil, code: Bool = false, align: String? = nil, imageWidth: Double = 600) -> String {
        var properties = ""
        if heading > 0 { properties += "<w:pStyle w:val=\"Heading\(min(6, heading))\"/><w:keepNext/>" }
        if let num { properties += "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(num)\"/></w:numPr>" }
        if code { properties += "<w:shd w:fill=\"F4F1EF\"/>" }
        properties += "<w:spacing w:after=\"160\" w:line=\"280\" w:lineRule=\"auto\"/>"
        if indent > 0 { properties += "<w:ind w:left=\"\(indent * 360)\"/>" }
        if let align { properties += "<w:jc w:val=\"\(align)\"/>" }
        return "<w:p><w:pPr>" + properties + "</w:pPr>" + inline(runs, imageWidth: imageWidth) + "</w:p>"
    }
    private mutating func blocks(_ values: [NativeExportBlock], indent: Int = 0, propertyTable: Bool = false) -> String {
        var result = ""
        for value in values {
            switch value {
            case .paragraph(let runs, let heading): result += paragraph(runs, heading: heading, indent: indent)
            case .quote(let children): result += blocks(children, indent: indent + 1)
            case .code(let text, _): result += paragraph([.init(text: text, style: .code)], indent: indent, code: true)
            case .rule: result += "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"4\" w:color=\"DDD7D2\"/></w:pBdr></w:pPr></w:p>"
            case .list(let start, let items):
                let number = numbering.count + 1; numbering.append((number, start))
                for item in items {
                    var first = true
                    for block in item.blocks {
                        if case .paragraph(let runs, let heading) = block, first {
                            let prefix = item.checked.map { [NativeExportRun(text: $0 ? "☑ " : "☐ ")] } ?? []
                            result += paragraph(prefix + runs, heading: heading, indent: indent + 1, num: item.checked == nil ? number : nil); first = false
                        } else { result += blocks([block], indent: indent + 1) }
                    }
                    if first { result += paragraph([.init(text: item.checked.map { $0 ? "☑" : "☐" } ?? "")], indent: indent + 1, num: item.checked == nil ? number : nil) }
                }
            case .table(let rows, let alignments):
                let columns = max(1, rows.map(\.count).max() ?? 1), cellWidth = max(1, 9360 / columns)
                result += "<w:tbl><w:tblPr><w:tblW w:w=\"9360\" w:type=\"dxa\"/><w:tblBorders>" + ["top", "left", "bottom", "right", "insideH", "insideV"].map { "<w:\($0) w:val=\"single\" w:sz=\"4\" w:color=\"DDD7D2\"/>" }.joined() + "</w:tblBorders><w:tblLayout w:type=\"fixed\"/></w:tblPr><w:tblGrid>" + (0..<columns).map { _ in "<w:gridCol w:w=\"\(cellWidth)\"/>" }.joined() + "</w:tblGrid>"
                for (row, cells) in rows.enumerated() {
                    let isHeader = row == 0 && !propertyTable
                    result += "<w:tr>" + (isHeader ? "<w:trPr><w:tblHeader/></w:trPr>" : "")
                    for column in 0..<columns {
                        let runs = column < cells.count ? cells[column] : []
                        result += "<w:tc><w:tcPr><w:tcW w:w=\"\(cellWidth)\" w:type=\"dxa\"/>" + (isHeader ? "<w:shd w:fill=\"F6F3F1\"/>" : "") + "</w:tcPr>" + paragraph(runs.map { var run = $0; if isHeader { run.style.insert(.bold) }; return run }, align: column < alignments.count ? alignments[column] : "left", imageWidth: max(10, Double(cellWidth) / 15 - 12)) + "</w:tc>"
                    }
                    result += "</w:tr>"
                }
                result += "</w:tbl>" + paragraph([])
            }
        }
        return result
    }
    private mutating func render() throws -> Data {
        var body = ""
        if !document.properties.isEmpty { body += blocks([.table(rows: document.properties.map { [[.init(text: $0.0, style: .bold)], [.init(text: $0.1)]] }, alignments: ["left", "left"])], propertyTable: true) }
        body += blocks(document.blocks)
        let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        let ns = "http://schemas.openxmlformats.org/"
        let xml = header + "<w:document xmlns:w=\"\(ns)wordprocessingml/2006/main\" xmlns:r=\"\(ns)officeDocument/2006/relationships\" xmlns:wp=\"\(ns)drawingml/2006/wordprocessingDrawing\" xmlns:a=\"\(ns)drawingml/2006/main\" xmlns:pic=\"\(ns)drawingml/2006/picture\"><w:body>" + body + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1080\" w:right=\"1080\" w:bottom=\"1080\" w:left=\"1080\"/></w:sectPr></w:body></w:document>"
        var types = "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/>"
        for (part, kind) in [("document", "document.main"), ("styles", "styles"), ("numbering", "numbering")] { types += "<Override PartName=\"/word/\(part).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.\(kind)+xml\"/>" }
        types += "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
        let rels = relationships.map { id, kind, target, external in "<Relationship Id=\"\(id)\" Type=\"\(ns)officeDocument/2006/relationships/\(kind)\" Target=\"\(e(target))\"" + (external ? " TargetMode=\"External\"" : "") + "/>" }.joined()
        let documentRels = "<Relationships xmlns=\"\(ns)package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(ns)officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"rId2\" Type=\"\(ns)officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>" + rels + "</Relationships>"
        let definitions = numbering.map { id, start in "<w:abstractNum w:abstractNumId=\"\(id)\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"\(start ?? 1)\"/><w:numFmt w:val=\"\(start == nil ? "bullet" : "decimal")\"/><w:lvlText w:val=\"\(start == nil ? "•" : "%1.")\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"360\"/></w:tabs><w:ind w:left=\"360\" w:hanging=\"240\"/></w:pPr></w:lvl></w:abstractNum>" }.joined()
        let instances = numbering.map { id, _ in "<w:num w:numId=\"\(id)\"><w:abstractNumId w:val=\"\(id)\"/></w:num>" }.joined()
        let styles = "<w:styles xmlns:w=\"\(ns)wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Calibri\" w:hAnsi=\"Calibri\"/><w:sz w:val=\"22\"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style>" + (1...6).map { level in "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(level)\"><w:name w:val=\"heading \(level)\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:qFormat/><w:pPr><w:keepNext/><w:outlineLvl w:val=\"\(level - 1)\"/></w:pPr><w:rPr><w:b/><w:sz w:val=\"\([40, 32, 27, 24, 23, 22][level - 1])\"/></w:rPr></w:style>" }.joined() + "</w:styles>"
        var entries: [(String, Data)] = [
            ("[Content_Types].xml", Data((header + "<Types xmlns=\"\(ns)package/2006/content-types\">" + types + "</Types>").utf8)),
            ("_rels/.rels", Data((header + "<Relationships xmlns=\"\(ns)package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(ns)officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/><Relationship Id=\"rId2\" Type=\"\(ns)package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/></Relationships>").utf8)),
            ("docProps/core.xml", Data((header + "<cp:coreProperties xmlns:cp=\"\(ns)package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>" + e(document.title) + "</dc:title><dc:creator>Zerus</dc:creator></cp:coreProperties>").utf8)),
            ("word/document.xml", Data(xml.utf8)), ("word/_rels/document.xml.rels", Data((header + documentRels).utf8)),
            ("word/styles.xml", Data((header + styles).utf8)),
            ("word/numbering.xml", Data((header + "<w:numbering xmlns:w=\"\(ns)wordprocessingml/2006/main\">" + definitions + instances + "</w:numbering>").utf8))
        ]
        entries += media
        return try NativeStoredZIP.archive(entries)
    }
}

enum NativeStoredZIP {
    static func archive(_ entries: [(String, Data)]) throws -> Data {
        var result = Data(), central = Data()
        func append(_ value: UInt32, to data: inout Data, bytes: Int = 4) { for index in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (index * 8))) } }
        for (name, bytes) in entries {
            try Task.checkCancellation()
            let path = Data(name.utf8)
            guard path.count <= Int(UInt16.max), bytes.count < 100 * 1024 * 1024, result.count < 100 * 1024 * 1024 else { throw VaultFailure(message: "This Word export is too large.") }
            var crc: UInt32 = 0xffffffff
            for byte in bytes { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) } }
            crc ^= 0xffffffff
            let offset = UInt32(result.count), length = UInt32(bytes.count)
            append(0x04034b50, to: &result); append(20, to: &result, bytes: 2); append(0x800, to: &result, bytes: 2); append(0, to: &result, bytes: 2); append(0, to: &result, bytes: 2); append(33, to: &result, bytes: 2); append(crc, to: &result); append(length, to: &result); append(length, to: &result); append(UInt32(path.count), to: &result, bytes: 2); append(0, to: &result, bytes: 2); result.append(path); result.append(bytes)
            append(0x02014b50, to: &central); append(20, to: &central, bytes: 2); append(20, to: &central, bytes: 2); append(0x800, to: &central, bytes: 2); append(0, to: &central, bytes: 2); append(0, to: &central, bytes: 2); append(33, to: &central, bytes: 2); append(crc, to: &central); append(length, to: &central); append(length, to: &central); append(UInt32(path.count), to: &central, bytes: 2); append(0, to: &central, bytes: 2); append(0, to: &central, bytes: 2); append(0, to: &central, bytes: 2); append(0, to: &central, bytes: 2); append(0, to: &central); append(offset, to: &central); central.append(path)
        }
        let offset = UInt32(result.count); result.append(central)
        append(0x06054b50, to: &result); append(0, to: &result, bytes: 2); append(0, to: &result, bytes: 2); append(UInt32(entries.count), to: &result, bytes: 2); append(UInt32(entries.count), to: &result, bytes: 2); append(UInt32(central.count), to: &result); append(offset, to: &result); append(0, to: &result, bytes: 2)
        return result
    }
}
