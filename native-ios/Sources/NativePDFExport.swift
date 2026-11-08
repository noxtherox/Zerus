import UIKit
import CoreText

private final class NativePDFImageBox {
    let image: CGImage
    let width: CGFloat
    let height: CGFloat
    init(_ image: CGImage, width: CGFloat, height: CGFloat) { self.image = image; self.width = width; self.height = height }
}

/// Core Text lays out selectable text directly into native PDF pages. Tables
/// split at measured line boundaries, including a single row taller than a page.
final class NativePDFExport {
    private let document: NativeExportDocument
    private let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    private let margin: CGFloat = 48
    private var bottom: CGFloat { page.height - 52 }
    private var y: CGFloat = 48
    private var pageNumber = 0
    private var renderer: UIGraphicsPDFRendererContext!
    private var decoded: [String: CGImage] = [:]
    private init(_ document: NativeExportDocument) { self.document = document }
    static func render(_ document: NativeExportDocument) throws -> Data { try Self(document).render() }

    private func render() throws -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: document.title, kCGPDFContextCreator as String: "Zerus Native"]
        let pdf = UIGraphicsPDFRenderer(bounds: page, format: format)
        var failure: Error?
        let data = pdf.pdfData { context in
            renderer = context
            do {
                beginPage()
                if !document.properties.isEmpty { try table(document.properties.map { [[.init(text: $0.0, style: .bold)], [.init(text: $0.1)]] }, alignments: ["left", "left"], header: false, indent: 0) }
                try blocks(document.blocks)
                footer()
            } catch { failure = error }
        }
        renderer = nil
        if let failure { throw failure }
        return data
    }
    private func beginPage() {
        if pageNumber > 0 { footer() }
        renderer.beginPage(); pageNumber += 1; y = margin
        renderer.cgContext.setFillColor(UIColor.white.cgColor); renderer.cgContext.fill(page)
    }
    private func footer() {
        let text = "\(pageNumber)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: (page.width - size.width) / 2, y: page.height - 32), withAttributes: attributes)
    }
    private func attributed(_ runs: [NativeExportRun], size: CGFloat = 11, width: CGFloat, heading: Int = 0, align: String = "left") -> NSAttributedString {
        let value = NSMutableAttributedString(string: "")
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3; paragraph.alignment = align == "center" ? .center : align == "right" ? .right : .left
        for run in runs {
            if let key = run.image, let resource = document.images[key] {
                let image = decoded[key] ?? UIImage(data: resource.bytes)?.cgImage
                if let image {
                    decoded[key] = image
                    let factor = min(1, width / max(1, CGFloat(resource.width)), 560 / max(1, CGFloat(resource.height)))
                    let box = NativePDFImageBox(image, width: CGFloat(resource.width) * factor, height: CGFloat(resource.height) * factor)
                    var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { pointer in Unmanaged<NativePDFImageBox>.fromOpaque(pointer).release() }, getAscent: { pointer in Unmanaged<NativePDFImageBox>.fromOpaque(pointer).takeUnretainedValue().height }, getDescent: { _ in 0 }, getWidth: { pointer in Unmanaged<NativePDFImageBox>.fromOpaque(pointer).takeUnretainedValue().width })
                    let retained = Unmanaged.passRetained(box)
                    if let delegate = CTRunDelegateCreate(&callbacks, retained.toOpaque()) {
                        value.append(NSAttributedString(string: "\u{fffc}", attributes: [NSAttributedString.Key(kCTRunDelegateAttributeName as String): delegate, NSAttributedString.Key("ZerusExportImage"): box, .paragraphStyle: paragraph])); continue
                    }
                    retained.release()
                }
            }
            let text = run.image == nil ? run.text : "[" + run.text + "]"
            var traits: UIFontDescriptor.SymbolicTraits = []
            if heading > 0 || run.style.contains(.bold) { traits.insert(.traitBold) }
            if run.style.contains(.italic) { traits.insert(.traitItalic) }
            let base = run.style.contains(.code) ? UIFont.monospacedSystemFont(ofSize: size - 1, weight: .regular) : UIFont.systemFont(ofSize: size)
            let font = base.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: size) } ?? base
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: paragraph]
            if run.style.contains(.strike) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link; attributes[.foregroundColor] = UIColor(red: 0.55, green: 0.24, blue: 0.12, alpha: 1); attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            value.append(NSAttributedString(string: text, attributes: attributes))
        }
        return value
    }
    private func height(_ text: NSAttributedString, width: CGFloat, range: CFRange? = nil) -> CGFloat {
        guard text.length > 0 else { return 16 }
        return ceil(CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(text), range ?? CFRange(location: 0, length: 0), nil, CGSize(width: max(1, width), height: .greatestFiniteMagnitude), nil).height) + 2
    }
    @discardableResult
    private func draw(_ text: NSAttributedString, at rect: CGRect, offset: Int = 0) -> Int {
        guard offset < text.length else { return 0 }
        let context = renderer.cgContext
        context.saveGState(); defer { context.restoreGState() }
        context.textMatrix = .identity; context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(location: offset, length: 0), CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil), nil)
        CTFrameDraw(frame, context)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        for (index, line) in lines.enumerated() {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let range = CTRunGetStringRange(run)
                let x = CGFloat(CTLineGetOffsetForStringIndex(line, range.location, nil)) + origins[index].x
                if let box = attributes["ZerusExportImage"] as? NativePDFImageBox { context.draw(box.image, in: CGRect(x: x, y: origins[index].y, width: box.width, height: box.height)) }
                if let target = attributes[NSAttributedString.Key.link] as? String, let url = URL(string: target) {
                    var ascent: CGFloat = 0, descent: CGFloat = 0
                    let width = CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil)
                    context.setURL(url as CFURL, for: CGRect(x: x, y: origins[index].y - descent, width: width, height: ascent + descent))
                }
            }
        }
        return CTFrameGetVisibleStringRange(frame).length
    }
    private func paragraph(_ runs: [NativeExportRun], heading: Int = 0, indent: Int = 0, prefix: String = "", code: Bool = false) throws {
        let x = margin + min(CGFloat(indent) * 15, 150), width = page.width - margin - x
        let combined = prefix.isEmpty ? runs : [.init(text: prefix)] + runs
        let size: CGFloat = heading > 0 ? [25, 20, 16, 14, 12, 11][min(6, heading) - 1] : 11
        let text = attributed(combined, size: size, width: width, heading: heading)
        if heading > 0 { y += 9; if bottom - y < min(height(text, width: width) + 28, bottom - margin) { beginPage() } }
        var offset = 0
        if text.length == 0 { y += 12 }
        while offset < text.length {
            try Task.checkCancellation()
            if bottom - y < 20 { beginPage() }
            let available = bottom - y
            let h = min(available, height(text, width: width, range: CFRange(location: offset, length: 0)))
            if code { renderer.cgContext.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor); renderer.cgContext.fill(CGRect(x: x - 4, y: y - 2, width: width + 8, height: h + 4)) }
            let visible = draw(text, at: CGRect(x: x, y: y, width: width, height: h), offset: offset)
            if visible == 0 {
                guard y > margin else { throw VaultFailure(message: "A block could not fit into a PDF page.") }
                beginPage(); continue
            }
            offset += visible; y += h
            if offset < text.length { beginPage() }
        }
        y += heading > 0 ? 10 : 9
    }
    private func blocks(_ values: [NativeExportBlock], indent: Int = 0) throws {
        for block in values {
            try Task.checkCancellation()
            switch block {
            case .paragraph(let runs, let heading): try paragraph(runs, heading: heading, indent: indent)
            case .quote(let children): try blocks(children, indent: indent + 1)
            case .code(let text, _): try paragraph([.init(text: text, style: .code)], indent: indent, code: true)
            case .rule:
                if bottom - y < 20 { beginPage() }
                renderer.cgContext.setStrokeColor(UIColor.lightGray.cgColor); renderer.cgContext.setLineWidth(0.5); renderer.cgContext.move(to: CGPoint(x: margin, y: y + 6)); renderer.cgContext.addLine(to: CGPoint(x: page.width - margin, y: y + 6)); renderer.cgContext.strokePath(); y += 22
            case .table(let rows, let alignments): try table(rows, alignments: alignments, header: true, indent: indent)
            case .list(let start, let items):
                for (index, item) in items.enumerated() {
                    let marker = item.checked.map { $0 ? "☑  " : "☐  " } ?? start.map { "\($0 + index).  " } ?? "•  "
                    var first = true
                    for child in item.blocks {
                        if case .paragraph(let runs, let heading) = child, first { try paragraph(runs, heading: heading, indent: indent + 1, prefix: marker); first = false }
                        else { try blocks([child], indent: indent + 1) }
                    }
                    if first { try paragraph([.init(text: marker)], indent: indent + 1) }
                }
            }
        }
    }
    private func table(_ rows: [[[NativeExportRun]]], alignments: [String], header: Bool, indent: Int) throws {
        let columns = max(1, rows.map(\.count).max() ?? 1), x = margin + min(CGFloat(indent) * 15, 150)
        let width = (page.width - margin - x) / CGFloat(columns), textWidth = max(1, width - 12)
        let texts = rows.enumerated().map { row, cells in (0..<columns).map { column -> NSAttributedString in
            var runs = column < cells.count ? cells[column] : []
            if header && row == 0 { runs = runs.map { var run = $0; run.style.insert(.bold); return run } }
            return attributed(runs, size: 9, width: textWidth, align: column < alignments.count ? alignments[column] : "left")
        } }
        let firstHeight = (texts.first?.map { height($0, width: textWidth) }.max() ?? 16) + 12
        func row(_ cells: [NSAttributedString], isHeader: Bool, repeated: Bool = false) throws {
            var offsets = Array(repeating: 0, count: columns), first = true
            repeat {
                try Task.checkCancellation()
                if bottom - y < 30 { beginPage(); if header && !isHeader && firstHeight < 120, let first = texts.first { try row(first, isHeader: true, repeated: true) } }
                let remaining = cells.enumerated().map { column, text in offsets[column] < text.length ? height(text, width: textWidth, range: CFRange(location: offsets[column], length: 0)) : CGFloat(16) }.max() ?? 16
                let chunk = min(bottom - y, remaining + 12)
                var progress = 0
                for column in 0..<columns {
                    let rect = CGRect(x: x + CGFloat(column) * width, y: y, width: width, height: chunk)
                    if isHeader { renderer.cgContext.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor); renderer.cgContext.fill(rect) }
                    renderer.cgContext.setStrokeColor(UIColor(white: 0.8, alpha: 1).cgColor); renderer.cgContext.setLineWidth(0.4); renderer.cgContext.stroke(rect)
                    let count = draw(cells[column], at: rect.insetBy(dx: 6, dy: 6), offset: offsets[column]); offsets[column] += count; progress += count
                }
                let finished = cells.enumerated().allSatisfy { offsets[$0.offset] >= $0.element.length }
                if !finished && progress == 0 {
                    guard y > margin + (header && !isHeader && firstHeight < 120 ? firstHeight : 0) + 1 else { throw VaultFailure(message: "A table cell is too wide or tall for this PDF. Reduce its columns or image size.") }
                    beginPage(); continue
                }
                y += chunk; first = false
                if finished { break }
                beginPage()
                if header && !isHeader && firstHeight < 120, let first = texts.first { try row(first, isHeader: true, repeated: true) }
            } while !repeated || first
        }
        for (index, cells) in texts.enumerated() { try row(cells, isHeader: header && index == 0) }
        y += 12
    }
}
