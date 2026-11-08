import Foundation
import Markdown
import ImageIO
import UniformTypeIdentifiers

enum NativeExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf, docx, html
    var id: String { rawValue }
    var title: String { switch self { case .pdf: return "PDF document"; case .docx: return "Word document"; case .html: return "Web page" } }
    var detail: String { switch self {
    case .pdf: return "A paginated document for printing and sharing."
    case .docx: return "An editable Word document with headings, lists, tables and images."
    case .html: return "A self-contained web page with local images embedded."
    } }
}

struct NativeExportStyle: OptionSet, Sendable { let rawValue: Int; static let bold = Self(rawValue: 1); static let italic = Self(rawValue: 2); static let strike = Self(rawValue: 4); static let code = Self(rawValue: 8) }
struct NativeExportRun: Sendable {
    var text: String = ""
    var style: NativeExportStyle = []
    var link: String?
    var image: String?
}
indirect enum NativeExportBlock: Sendable {
    case paragraph([NativeExportRun], heading: Int = 0)
    case quote([NativeExportBlock])
    case list(start: Int?, items: [NativeExportListItem])
    case code(String, language: String?)
    case table(rows: [[[NativeExportRun]]], alignments: [String])
    case rule
}
struct NativeExportListItem: Sendable { let checked: Bool?; let blocks: [NativeExportBlock] }
struct NativeExportImage: Sendable { let bytes: Data; let width: Double; let height: Double }
struct NativeExportDocument: Sendable {
    let title: String
    var blocks: [NativeExportBlock]
    let properties: [(String, String)]
    var images: [String: NativeExportImage] = [:]
    var warnings: [String] = []
}
struct NativeExportArtifact: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let warnings: [String]
    let format: NativeExportFormat
}

/// A static export never runs note HTML or fetches remote resources. The same
/// semantic document feeds all three writers, including their warnings.
struct NativeExportParser {
    var warnings: [String] = []
    var imageReferences = Set<String>()
    mutating func blocks(_ node: any Markup) -> [NativeExportBlock] {
        if let heading = node as? Heading { return [.paragraph(inlines(heading), heading: heading.level)] }
        if let paragraph = node as? Paragraph { return [.paragraph(inlines(paragraph))] }
        if let quote = node as? BlockQuote { return [.quote(quote.children.flatMap { blocks($0) })] }
        if node is UnorderedList || node is OrderedList {
            let start = (node as? OrderedList).map { Int(clamping: $0.startIndex) }
            let items = node.children.compactMap { $0 as? ListItem }.map { item -> NativeExportListItem in
                let checked = item.checkbox.map { $0 == .checked }
                return .init(checked: checked, blocks: item.children.flatMap { blocks($0) })
            }
            return [.list(start: start, items: items)]
        }
        if let code = node as? CodeBlock { return [.code(code.code, language: code.language)] }
        if let table = node as? Markdown.Table {
            let rows = [table.head.children.map { inlines($0) }] + table.body.children.map { row in row.children.map { inlines($0) } }
            let alignments = table.columnAlignments.map { alignment -> String in switch alignment { case .center: return "center"; case .right: return "right"; default: return "left" } }
            return [.table(rows: rows, alignments: alignments)]
        }
        if node is ThematicBreak { return [.rule] }
        if let html = node as? HTMLBlock {
            let literal = Self.withoutLeadingComments(html.rawHTML)
            guard !literal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            warnings.append("Embedded HTML is included as text; active content is not run.")
            return [.code(literal, language: "html")]
        }
        return node.children.flatMap { blocks($0) }
    }
    mutating func inlines(_ node: any Markup, style: NativeExportStyle = [], link: String? = nil) -> [NativeExportRun] {
        if let text = node as? Markdown.Text { return [.init(text: text.string, style: style, link: link)] }
        if let code = node as? InlineCode { return [.init(text: code.code, style: style.union(.code), link: link)] }
        if node is SoftBreak { return [.init(text: " ", style: style, link: link)] }
        if node is LineBreak { return [.init(text: "\n", style: style, link: link)] }
        if let html = node as? InlineHTML {
            let literal = Self.withoutLeadingComments(html.rawHTML)
            guard !literal.isEmpty else { return [] }
            warnings.append("Embedded HTML is included as text; active content is not run.")
            return [.init(text: literal, style: style, link: link)]
        }
        if let image = node as? Markdown.Image {
            let reference = image.source ?? ""
            imageReferences.insert(reference)
            return [.init(text: image.plainText.isEmpty ? "Image" : image.plainText, style: style, image: reference)]
        }
        var nextStyle = style, nextLink = link
        if node is Strong { nextStyle.insert(.bold) }
        if node is Emphasis { nextStyle.insert(.italic) }
        if node is Strikethrough { nextStyle.insert(.strike) }
        if let value = node as? Markdown.Link, let target = value.destination {
            if let safe = Self.safeLink(target) { nextLink = safe }
            else if target.hasPrefix("zerus-note:") { warnings.append("Internal note links are included as labels.") }
            else { warnings.append("A local or unsupported link is included as text; its target is not bundled.") }
        }
        let tags = NativeInlineHTML.paired(in: node)
        var current = nextStyle, stack: [NativeExportStyle] = [], output: [NativeExportRun] = []
        for (index, child) in node.children.enumerated() {
            if let tag = tags[index] {
                if tag.closing { current = stack.removeLast() }
                else { stack.append(current); current.formUnion(.init(rawValue: tag.flags)) }
            } else { output += inlines(child, style: current, link: nextLink) }
        }
        return output
    }
    private static func withoutLeadingComments(_ raw: String) -> String {
        var value = raw
        while value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!--") {
            guard let start = value.range(of: "<!--"), let end = value.range(of: "-->", range: start.upperBound..<value.endIndex) else { return "" }
            value = String(value[end.upperBound...])
        }
        return value
    }
    static func safeLink(_ target: String) -> String? {
        guard !target.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), let url = URL(string: target), let scheme = url.scheme?.lowercased(), ["https", "http", "mailto", "tel"].contains(scheme) else { return nil }
        return target
    }
}

extension VaultFiles {
    func exportDocument(_ note: NoteDocument, includeProperties: Bool) throws -> NativeExportDocument {
        let access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
        _ = try url(for: note.path)
        guard note.content.utf8.count <= 10 * 1024 * 1024 else { throw VaultFailure(message: "Export a note smaller than 10 MB.") }
        var parser = NativeExportParser()
        var body = note.parts.body
        // Editor-hidden URL cards remain meaningful in a standalone export.
        if let saved = note.savedLink { body = NativeSavedLink.withURL(body, address: saved.address) }
        // Use actual source ranges so tilde/indented code, escaped examples,
        // image labels and HTML cannot acquire an unintended note connection.
        let edits = try MarkdownMoveLinks.links(in: body).compactMap { link -> (MarkdownMoveLinks.Link, String)? in
            guard case .wiki = link.kind else { return nil }
            return (link, NoteReference.inlineMarkdown(link.value))
        }
        let blocks = parser.blocks(Document(parsing: MarkdownMoveLinks.replacing(body, edits: edits)))
        var properties: [(String, String)] = []
        if includeProperties {
            for entry in NativeFrontmatter(note.content).entries where !entry.key.lowercased().hasPrefix("zerus-") {
                guard let value = entry.value else { parser.warnings.append("Property ‘\(entry.key)’ has an unsupported value and was not included."); continue }
                let display = value.selections.map { item -> String in
                    guard item.hasPrefix("zerus:"), let split = item.firstIndex(of: "|") else { return item }
                    return String(item[item.index(after: split)...])
                }.joined(separator: ", ")
                properties.append((entry.key, display))
            }
        }
        var result = NativeExportDocument(title: note.title, blocks: blocks, properties: properties, warnings: parser.warnings)
        if let hub = note.fileHub {
            result.blocks.append(.paragraph([.init(text: "Document: " + hub.name, style: .italic)]))
            result.warnings.append("The linked document is named in this export; share the document separately to include its original file.")
        }
        var total = 0
        for reference in parser.imageReferences.sorted() {
            try Task.checkCancellation()
            guard let parsed = URL(string: reference), parsed.scheme == nil else {
                result.warnings.append("Remote or embedded image ‘\(reference.prefix(120))’ is included as a label; no network request was made."); continue
            }
            do {
                let bytes = try resourceData(reference, notePath: note.path)
                total += bytes.count
                guard total <= 50 * 1024 * 1024 else { throw VaultFailure(message: "Export images totaling less than 50 MB.") }
                guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw VaultFailure(message: "Unsupported image format.") }
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw VaultFailure(message: "Could not prepare the image.") }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw VaultFailure(message: "Could not prepare the image.") }
                result.images[reference] = .init(bytes: output as Data, width: Double(image.width), height: Double(image.height))
            } catch let error as VaultFailure where error.message.contains("totaling") { throw error }
            catch { result.warnings.append("Could not include image ‘\(reference.prefix(120))’; its label is kept.") }
        }
        result.warnings = Array(Set(result.warnings)).sorted()
        return result
    }
}

enum NativeNoteExport {
    static func artifact(_ document: NativeExportDocument, format: NativeExportFormat) throws -> NativeExportArtifact {
        try Task.checkCancellation()
        let bytes: Data
        switch format {
        case .html: bytes = Data(NativeHTMLExport.render(document).utf8)
        case .docx: bytes = try NativeWordExport.render(document)
        case .pdf: bytes = try NativePDFExport.render(document)
        }
        try Task.checkCancellation()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Shared URLs remain available after the sheet closes. Only expired
        // artifacts in this app-owned cache are cleaned on a subsequent export.
        for child in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let date = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < Date().addingTimeInterval(-2 * 86_400) { try? FileManager.default.removeItem(at: child) }
        }
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(stem(document.title) + "." + format.rawValue)
        do { try bytes.write(to: file, options: .atomic) } catch { try? FileManager.default.removeItem(at: directory); throw error }
        return .init(url: file, warnings: document.warnings, format: format)
    }
    static func stem(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: #"[<>:"/\\|?*\x00-\x1F\x7F]"#, with: "-", options: .regularExpression).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var result = String(cleaned.prefix(100))
        while result.utf8.count > 180 { result.removeLast() }
        return result.isEmpty ? "Untitled note" : result
    }
    static func escape(_ value: String) -> String {
        String(value.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || ($0.value >= 32 && $0.value != 0xFFFE && $0.value != 0xFFFF) }).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
}

enum NativeHTMLExport {
    static func render(_ document: NativeExportDocument) -> String {
        let e = NativeNoteExport.escape
        func inline(_ runs: [NativeExportRun]) -> String { runs.map { run in
            if let key = run.image {
                guard let image = document.images[key] else { return "<span class=\"missing-image\">[" + e(run.text) + "]</span>" }
                return "<img src=\"data:image/png;base64," + image.bytes.base64EncodedString() + "\" alt=\"" + e(run.text) + "\" width=\"" + String(Int(min(image.width, 720))) + "\" />"
            }
            var value = e(run.text).replacingOccurrences(of: "\n", with: "<br />")
            if run.style.contains(.code) { value = "<code>" + value + "</code>" }
            if run.style.contains(.bold) { value = "<strong>" + value + "</strong>" }
            if run.style.contains(.italic) { value = "<em>" + value + "</em>" }
            if run.style.contains(.strike) { value = "<s>" + value + "</s>" }
            if let link = run.link { value = "<a href=\"" + e(link) + "\" rel=\"noreferrer\">" + value + "</a>" }
            return value
        }.joined() }
        func blocks(_ values: [NativeExportBlock]) -> String { values.map { block in switch block {
        case .paragraph(let runs, let heading): let tag = heading > 0 ? "h\(min(6, heading))" : "p"; return "<\(tag)>" + inline(runs) + "</\(tag)>"
        case .quote(let children): return "<blockquote>" + blocks(children) + "</blockquote>"
        case .list(let start, let items): let tag = start == nil ? "ul" : "ol"; return "<\(tag)" + (start.map { " start=\"\($0)\"" } ?? "") + ">" + items.map { item in "<li>" + (item.checked.map { $0 ? "<span aria-label=\"Completed\">☑ </span>" : "<span aria-label=\"Not completed\">☐ </span>" } ?? "") + blocks(item.blocks) + "</li>" }.joined() + "</\(tag)>"
        case .code(let text, let language): return "<pre><code" + (language.map { " data-language=\"" + e($0) + "\"" } ?? "") + ">" + e(text) + "</code></pre>"
        case .table(let rows, let alignments): return "<table>" + rows.enumerated().map { row, cells in "<tr>" + cells.enumerated().map { column, runs in let tag = row == 0 ? "th" : "td"; let align = column < alignments.count ? alignments[column] : "left"; return "<\(tag) style=\"text-align:\(align)\">" + inline(runs) + "</\(tag)>" }.joined() + "</tr>" }.joined() + "</table>"
        case .rule: return "<hr />"
        } }.joined(separator: "\n") }
        let properties = document.properties.isEmpty ? "" : "<table class=\"properties\" aria-label=\"Note properties\">" + document.properties.map { "<tr><th>" + e($0.0) + "</th><td>" + e($0.1) + "</td></tr>" }.joined() + "</table>"
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" /><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'" /><title>\(e(document.title))</title><style>
        :root{color-scheme:light}*{box-sizing:border-box}body{max-width:800px;margin:0 auto;padding:48px 28px 72px;color:#252321;background:#fff;font:16px/1.65 -apple-system,BlinkMacSystemFont,Arial,sans-serif;overflow-wrap:anywhere}h1,h2,h3,h4,h5,h6{line-height:1.22;break-after:avoid;margin:1.5em 0 .6em}h1{font-size:2.1em}h2{font-size:1.6em}a{color:#9a4526}img{display:block;max-width:100%;height:auto;margin:1em 0}blockquote{margin:1em 0;padding:0 1em;border-left:3px solid #bd6945;color:#555}code{font-family:ui-monospace,monospace;background:#f4f1ef;padding:.1em .25em}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f4f1ef;padding:1em;border-radius:8px}pre code{padding:0}table{width:100%;border-collapse:collapse;margin:1.2em 0}th,td{border:1px solid #ddd7d2;padding:.5em .65em;vertical-align:top;overflow-wrap:anywhere}th{background:#f6f3f1;text-align:left}.properties{font-size:.88em}.properties th{width:28%}.missing-image{color:#777;font-style:italic}li>p{margin:.3em 0}hr{border:0;border-top:1px solid #ddd;margin:2em 0}@media print{body{max-width:none;padding:0}thead{display:table-header-group}}
        </style></head><body>\(properties)\(blocks(document.blocks))</body></html>
        """
    }
}
