import Foundation
import SwiftSoup
#if os(macOS)
import Markdown
#endif
import ImageIO
import UniformTypeIdentifiers

/// Clipboard HTML is parsed as data, never executed in a browser. Only image
/// sources are fetched; links, stylesheets, scripts and embedded frames are not.
enum NativeHTMLClipboard {
    struct Attachment: Sendable { let name: String; let bytes: Data }
    private struct Image: Sendable {
        let reference: String
        let url: URL?
        let bytes: Data?
        let alt: String
        let attachmentName: String?
    }
    private struct Plan: Sendable {
        let markdown: String
        let images: [Image]
    }
    static func needsCompanionAttachments(_ data: Data) throws -> Bool {
        try Parser().parse(data).images.contains { $0.attachmentName != nil }
    }
    static func fragment(_ data: Data, attachments: [Attachment] = []) async throws -> NativeClipboardFragment {
        let plan = try Parser().parse(data)
        let budget = NativeHTMLImageBudget(limit: NativeClipboardFragment.limit - plan.markdown.utf8.count)
        var images = Array<NativeClipboardFragment.Resource?>(repeating: nil, count: plan.images.count)
        func resource(_ image: Image) async throws -> NativeClipboardFragment.Resource {
            let bytes: Data
            if let embedded = image.bytes { try budget.consume(embedded.count); bytes = embedded }
            else if let url = image.url { bytes = try await NativeHTMLImageDownload.fetch(url, budget: budget) }
            else {
                let matching = attachments.filter { $0.name == image.attachmentName }
                guard let first = matching.first, matching.allSatisfy({ $0.bytes == first.bytes }) else { throw VaultFailure(message: "A copied image needs access to its original app or file. Copy the image separately, or use Paste plain text.") }
                try budget.consume(first.bytes.count); bytes = first.bytes
            }
            guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(source) > 0, CGImageSourceGetStatus(source) == .statusComplete,
                  let type = CGImageSourceGetType(source), let format = UTType(type as String), format.conforms(to: .image) else {
                throw VaultFailure(message: "A copied image could not be read. Your writing is unchanged; copy the image separately or use Paste plain text.")
            }
            let ext = format.preferredFilenameExtension ?? "png"
            let original = image.alt.isEmpty ? image.url?.deletingPathExtension().lastPathComponent ?? "Image" : image.alt
            let clean = original.replacingOccurrences(of: #"[/\\:\x00-\x1F<>\"|?*]"#, with: "-", options: .regularExpression)
            var name = ""
            for character in clean {
                let next = name + String(character)
                // APFS normalizes Unicode; count decomposed bytes and keep the
                // imported UUID prefix plus extension below filename limits.
                guard next.decomposedStringWithCanonicalMapping.utf8.count <= 150 else { break }
                name = next
            }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            return .init(reference: image.reference, path: nil, name: (name.isEmpty ? "Image" : name) + "." + ext, bytes: bytes)
        }
        try await withThrowingTaskGroup(of: (Int, NativeClipboardFragment.Resource).self) { group in
            var next = 0
            func enqueue() {
                guard next < plan.images.count else { return }
                let index = next, image = plan.images[index]; next += 1
                group.addTask { (index, try await resource(image)) }
            }
            if !plan.images.isEmpty {
                group.addTask {
                    try await Task.sleep(for: .seconds(60))
                    throw VaultFailure(message: "The clipboard images took too long to load. Your writing is unchanged; retry or use Paste plain text.")
                }
            }
            for _ in 0..<min(4, plan.images.count) { enqueue() }
            var completed = 0
            while let (index, value) = try await group.next() {
                images[index] = value; completed += 1
                if completed == plan.images.count { group.cancelAll(); break }
                enqueue()
            }
        }
        try Task.checkCancellation()
        let result = NativeClipboardFragment(markdown: plan.markdown, resources: images.compactMap { $0 })
        try result.validate(); return result
    }

    private final class Parser {
        var images: [Image] = []
        var sources: [String: String] = [:]
        var visited = 0
        let ignored: Set<String> = ["head", "script", "style", "link", "meta", "base", "iframe", "object", "embed", "template", "noscript", "svg", "canvas"]
        let blocks: Set<String> = ["p", "div", "section", "article", "main", "header", "footer", "nav", "aside", "figure", "figcaption", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "table", "hr", "dl", "dt", "dd"]
        func trimmedContent(_ value: String) -> String {
            #if os(macOS)
            return value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.subtracting(CharacterSet(charactersIn: "\u{200B}")))
            #else
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
            #endif
        }
        func check(_ depth: Int) throws {
            try Task.checkCancellation(); visited += 1
            guard depth <= 128, visited <= 50_000 else { throw VaultFailure(message: "This HTML selection is too complex. Copy a smaller passage or use Paste plain text.") }
        }
        func parse(_ data: Data) throws -> Plan {
            guard data.count <= 10 * 1024 * 1024 else { throw VaultFailure(message: "Copy HTML smaller than 10 MB, or copy its images separately.") }
            var source = data, base = ""
            // Windows CF_HTML includes a source URL and byte-offset header. The
            // actual selection markers avoid treating that header as writing.
            if let text = String(data: data, encoding: .utf8), text.hasPrefix("Version:") {
                base = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("SourceURL:") }).map { String($0.dropFirst(10)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                if let start = text.range(of: "<!--StartFragment-->"), let end = text.range(of: "<!--EndFragment-->", range: start.upperBound..<text.endIndex) {
                    source = Data(text[start.upperBound..<end.lowerBound].utf8)
                } else if let start = text.firstIndex(of: "<") { source = Data(text[start...].utf8) }
            }
            let document = try SwiftSoup.parseHTML(source, base)
            guard let body = document.body() else { throw VaultFailure(message: "The clipboard HTML could not be read. Use Paste plain text.") }
            let markdown = trimmedContent(try content(body.getChildNodes(), depth: 0))
            guard !markdown.isEmpty else { throw VaultFailure(message: "This HTML selection has no supported writing. Use Paste plain text or copy the image separately.") }
            return Plan(markdown: markdown + "\n", images: images)
        }
        func content(_ nodes: [SwiftSoup.Node], depth: Int) throws -> String {
            var output: [String] = [], pending = ""
            func flush(nextBlock: Bool = false) {
                let rawValue = trimmedContent(pending)
                #if os(macOS)
                var value = breakWhitespace(rawValue)
                if let count = breakOnlyCount(value), nextBlock || !output.isEmpty {
                    value = emptyParagraphs(count)
                }
                #else
                let value = rawValue
                #endif
                if !value.isEmpty { output.append(MarkdownText.escapeLiteralBlockStart(value)) }
                pending = ""
            }
            for node in nodes {
                if let element = node as? SwiftSoup.Element, blocks.contains(element.tagNameNormal()) {
                    flush(nextBlock: true); let value = try block(element, depth: depth + 1)
                    if !value.isEmpty {
                        #if os(macOS)
                        // Child lists stay compact unless CommonMark would
                        // absorb a non-one ordered marker into preceding prose.
                        if let parent = element.parent(), parent.tagNameNormal() == "li", ["ul", "ol"].contains(element.tagNameNormal()) {
                            let separator = try childListSeparator(value, after: output, in: parent)
                            if output.isEmpty {
                                // Keep an empty item's child list on its own
                                // physical line, rather than inside the marker.
                                output.append(separator + value)
                            } else { output[output.count - 1] += separator + value }
                        } else { output.append(value) }
                        #else
                        output.append(value)
                        #endif
                    }
                } else { pending += try inline(node, depth: depth + 1) }
            }
            flush(); return output.joined(separator: "\n\n")
        }
        func block(_ element: SwiftSoup.Element, depth: Int) throws -> String {
            try check(depth)
            let tag = element.tagNameNormal()
            if try hidden(element) { return "" }
            switch tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                return String(repeating: "#", count: Int(tag.dropFirst())!) + " " + trimmedContent(try inlineChildren(element, depth: depth))
            case "ul", "ol":
                #if os(macOS)
                var number = tag == "ol" ? try listOrdinal(element.attr("start"), fallback: 1) : 1
                #else
                var number = Int(try element.attr("start")) ?? 1
                guard (1...999_999_999).contains(number) else { throw VaultFailure(message: "This copied list uses unsupported numbering. Use Paste plain text.") }
                #endif
                var lines: [String] = []
                for item in element.children() where item.tagNameNormal() == "li" {
                    #if os(macOS)
                    if tag == "ol" { number = try listOrdinal(item.attr("value"), fallback: number) }
                    // Overrides and implicit continuation share the start bound;
                    // check before emitting or incrementing an untrusted value.
                    guard (0...999_999_999).contains(number) else { throw VaultFailure(message: "This copied list uses unsupported numbering. Use Paste plain text.") }
                    let checked = try listCheckboxState(item)
                    let marker = checked.map { $0 ? "- [x] " : "- [ ] " } ?? (tag == "ol" ? "\(number). " : "- ")
                    // GFM task syntax is body text after the two-column bullet,
                    // not extra indentation for the item's child blocks.
                    let padding = checked == nil ? marker.count : 2
                    #else
                    if let explicit = Int(try item.attr("value")) { number = explicit }
                    let checkbox = try item.select("input[type=checkbox]").first()
                    let marker = checkbox.map { $0.hasAttr("checked") ? "- [x] " : "- [ ] " } ?? (tag == "ol" ? "\(number). " : "- ")
                    let padding = marker.count
                    #endif
                    let rawValue = try content(item.getChildNodes(), depth: depth + 1)
                    #if os(macOS)
                    let value = blockBreaks(rawValue, in: item)
                    #else
                    let value = rawValue
                    #endif
                    let parts = value.components(separatedBy: "\n")
                    #if os(macOS)
                    // An empty task needs a body for GFM to retain its state.
                    // Empty leaves also need a body so trimming cannot remove
                    // the marker's required space and force source editing.
                    let head = (checked != nil || parts.count == 1) && (parts.first ?? "").isEmpty ? emptyParagraphs(1) : parts.first ?? ""
                    #else
                    let head = parts.first ?? ""
                    #endif
                    lines.append(marker + head + parts.dropFirst().map { $0.isEmpty ? "\n" : "\n" + String(repeating: " ", count: padding) + $0 }.joined())
                    number += 1
                }
                return lines.joined(separator: "\n")
            case "blockquote":
                return try content(element.getChildNodes(), depth: depth + 1).components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
            case "pre":
                let text = try rawText(element, depth: depth).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                var fence = "```"; while text.contains(fence) { fence += "`" }
                let classes = try element.select("code").first()?.attr("class") ?? ""
                let language = classes.split(separator: " ").first(where: { $0.hasPrefix("language-") }).map { String($0.dropFirst(9)) } ?? ""
                let safe = language.range(of: #"^[A-Za-z0-9_+.-]{1,32}$"#, options: .regularExpression) != nil ? language : ""
                return fence + safe + "\n" + text + (text.hasSuffix("\n") ? "" : "\n") + fence
            case "table": return try table(element, depth: depth)
            case "hr": return "---"
            default:
                let value = try content(element.getChildNodes(), depth: depth + 1)
                #if os(macOS)
                return blockBreaks(value, in: element)
                #else
                return value
                #endif
            }
        }
        func inlineChildren(_ element: SwiftSoup.Element, depth: Int) throws -> String {
            let value = try element.getChildNodes().map { try inline($0, depth: depth + 1) }.joined()
            #if os(macOS)
            return breakWhitespace(value)
            #else
            return value
            #endif
        }
        func inline(_ node: SwiftSoup.Node, depth: Int) throws -> String {
            try check(depth)
            if let text = node as? SwiftSoup.TextNode {
                let plain = text.getWholeText().replacingOccurrences(of: #"[\t\r\n ]+"#, with: " ", options: .regularExpression)
                return plain.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: #"([\\`*_\[\]<>~$])"#, with: #"\\$1"#, options: .regularExpression)
            }
            guard let element = node as? SwiftSoup.Element else { return "" }
            let tag = element.tagNameNormal()
            if ignored.contains(tag) { return "" }
            if try hidden(element) { return "" }
            if tag == "br" {
                #if os(macOS)
                // Keep explicit breaks through paragraph and document trimming.
                // The Mac editor understands this portable inline HTML spelling.
                return "<br>"
                #else
                return "\n"
                #endif
            }
            if tag == "input" { return "" }
            if tag == "img" { return try image(element) }
            if tag == "code" {
                let text = try rawText(element, depth: depth).replacingOccurrences(of: "\n", with: " ")
                var fence = "`"; while text.contains(fence) { fence += "`" }
                let pad = text.hasPrefix("`") || text.hasSuffix("`") || text.hasPrefix(" ") && text.hasSuffix(" ") && !text.allSatisfy(\.isWhitespace)
                return fence + (pad ? " " : "") + text + (pad ? " " : "") + fence
            }
            var value = try inlineChildren(element, depth: depth)
            let style = try element.attr("style").lowercased().components(separatedBy: ";").reduce(into: [String: String]()) { values, item in
                let parts = item.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { values[parts[0]] = parts[1] }
            }
            if style["display"] == "none" || style["visibility"] == "hidden" { return "" }
            let bold = ["strong", "b"].contains(tag) || style["font-weight"].map { $0 == "bold" || (Int($0) ?? 0) >= 600 } == true
            let italic = ["em", "i"].contains(tag) || style["font-style"].map { $0.hasPrefix("italic") || $0.hasPrefix("oblique") } == true
            #if os(macOS)
            let underline = tag == "u" || style["text-decoration"]?.contains("underline") == true || style["text-decoration-line"]?.contains("underline") == true
            #endif
            let strike = ["s", "strike", "del"].contains(tag) || style["text-decoration"]?.contains("line-through") == true || style["text-decoration-line"]?.contains("line-through") == true
            if value.allSatisfy(\.isWhitespace) {
                #if os(macOS)
                if underline, !value.isEmpty {
                    let literal = value.map { $0 == " " ? "&#32;" : $0 == "\t" ? "&#9;" : String($0) }.joined()
                    return "<u>" + literal + "</u>"
                }
                #endif
                return value
            }
            let leading = String(value.prefix(while: \.isWhitespace)), trailing = String(value.reversed().prefix(while: \.isWhitespace).reversed())
            value = trimmedContent(value)
            #if os(macOS)
            var bodyStart = value.startIndex, bodyEnd = value.endIndex, leadingCount = 0, trailingCount = 0
            while value[bodyStart..<bodyEnd].hasPrefix("<br>") { leadingCount += 1; bodyStart = value.index(bodyStart, offsetBy: 4) }
            while value[bodyStart..<bodyEnd].hasSuffix("<br>") { trailingCount += 1; bodyEnd = value.index(bodyEnd, offsetBy: -4) }
            let leadingBreaks = String(repeating: "<br>", count: leadingCount), trailingBreaks = String(repeating: "<br>", count: trailingCount)
            value = String(value[bodyStart..<bodyEnd])
            #endif
            if !value.isEmpty {
                if bold { value = "**" + value + "**" }; if italic { value = "*" + value + "*" }; if strike { value = "~~" + value + "~~" }
                #if os(macOS)
                if underline { value = "<u>" + value + "</u>" }
                #endif
                if tag == "a", let address = try address(element, attribute: "href", image: false) {
                    let escaped = address.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
                    value = "[" + value + "](" + escaped + ")"
                }
            }
            #if os(macOS)
            return leading + leadingBreaks + value + trailingBreaks + trailing
            #else
            return leading + value + trailing
            #endif
        }
        #if os(macOS)
        func listOrdinal(_ raw: String, fallback: Int) throws -> Int {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ordinal = Int(value) {
                guard (0...999_999_999).contains(ordinal) else { throw VaultFailure(message: "This copied list uses unsupported numbering. Use Paste plain text.") }
                return ordinal
            }
            // Keep the existing default for a missing/noninteger attribute,
            // but do not disguise an overflowing integer as the default one.
            guard value.range(of: #"^[+-]?[0-9]+$"#, options: .regularExpression) == nil else { throw VaultFailure(message: "This copied list uses unsupported numbering. Use Paste plain text.") }
            return fallback
        }
        func listCheckboxState(_ item: SwiftSoup.Element) throws -> Bool? {
            // Wrapped controls belong to the nearest li, not its ancestors.
            let checkbox = try item.select("input[type=checkbox]").first { candidate in
                guard let owner = candidate.parents().first(where: { $0.tagNameNormal() == "li" }) else { return false }
                return owner === item
            }
            let aria = try item.attr("aria-checked").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return aria == "true" ? true : aria == "false" ? false : checkbox.map { $0.hasAttr("checked") }
        }
        func childListSeparator(_ value: String, after output: [String], in item: SwiftSoup.Element) throws -> String {
            let digits = value.prefix(while: \.isNumber)
            guard let ordinal = Int(digits), ordinal != 1, value.dropFirst(digits.count).hasPrefix(". ") else { return "\n" }
            var prefix = output.joined(separator: "\n\n")
            if prefix.isEmpty, try listCheckboxState(item) != nil {
                // Empty tasks acquire the shared blank body when their marker
                // is emitted; account for that paragraph before deciding here.
                prefix = emptyParagraphs(1)
            }
            let line = prefix.isEmpty ? 1 : prefix.utf8.filter { $0 == 10 }.count + 2
            let source = prefix.isEmpty ? value : prefix + "\n" + value
            var recognized = false
            func visit(_ node: any Markup) {
                if let listItem = node as? ListItem, listItem.range?.lowerBound.line == line, listItem.parent is OrderedList { recognized = true }
                for child in node.children { visit(child) }
            }
            visit(Markdown.Document(parsing: source))
            return recognized ? "\n" : "\n\n"
        }
        func breakWhitespace(_ value: String) -> String {
            value.replacingOccurrences(of: #"[ \t\r\n\f]*<br>[ \t\r\n\f]*"#, with: "<br>", options: .regularExpression)
        }
        func breakOnlyCount(_ value: String) -> Int? {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.replacingOccurrences(of: "<br>", with: "").isEmpty else { return nil }
            return clean.components(separatedBy: "<br>").count - 1
        }
        func emptyParagraphs(_ count: Int) -> String {
            // Existing Zerus web format for an intentional blank paragraph.
            Array(repeating: "\u{200B}", count: count).joined(separator: "\n\n")
        }
        func blockBreaks(_ value: String, in element: SwiftSoup.Element) -> String {
            // Child blocks already removed their own browser layout break.
            guard !element.children().contains(where: { blocks.contains($0.tagNameNormal()) }) else { return value }
            if let count = breakOnlyCount(value) { return "\u{200B}" + String(repeating: "<br>", count: max(0, count - 1)) }
            // A block's last br is a browser layout placeholder. A second br
            // remains as the actual visible empty line after its text.
            return value.hasSuffix("<br>") ? String(value.dropLast(4)) : value
        }
        #endif
        func address(_ element: SwiftSoup.Element, attribute: String, image: Bool) throws -> URL? {
            let raw = try element.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            let resolved = try element.absUrl(attribute)
            guard let url = URL(string: resolved.isEmpty ? raw : resolved), let scheme = url.scheme?.lowercased(),
                  (image ? ["https", "http"] : ["https", "http", "mailto", "tel"]).contains(scheme), url.user == nil, url.password == nil else { return nil }
            if ["http", "https"].contains(scheme), url.host == nil { return nil }
            return url
        }
        func image(_ element: SwiftSoup.Element) throws -> String {
            let src = try element.attr("src"), alt = try element.attr("alt")
            if let reference = sources[src] { return "![" + escapedLabel(alt) + "](" + reference + ")" }
            guard images.count < 100 else { throw VaultFailure(message: "Copy a selection with fewer than 100 images.") }
            let reference = "assets/clipboard-" + UUID().uuidString.lowercased()
            let bytes: Data?, url: URL?, attachmentName: String?
            if src.lowercased().hasPrefix("data:image/"), let comma = src.firstIndex(of: ","), src[..<comma].lowercased().hasSuffix(";base64"),
               let decoded = Data(base64Encoded: String(src[src.index(after: comma)...]).removingPercentEncoding ?? "", options: .ignoreUnknownCharacters) { bytes = decoded; url = nil; attachmentName = nil }
            else if let remote = try address(element, attribute: "src", image: true) { bytes = nil; url = remote; attachmentName = nil }
            else {
                let path = src.hasPrefix("cid:") ? (String(src.dropFirst(4)).removingPercentEncoding ?? String(src.dropFirst(4))) : URL(string: src)?.path ?? src
                attachmentName = (path as NSString).lastPathComponent
                bytes = nil; url = nil
            }
            images.append(.init(reference: reference, url: url, bytes: bytes, alt: alt, attachmentName: attachmentName)); sources[src] = reference
            return "![" + escapedLabel(alt) + "](" + reference + ")"
        }
        func escapedLabel(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: #"([\\`*_\[\]<>~$])"#, with: #"\\$1"#, options: .regularExpression).replacingOccurrences(of: "\n", with: " ")
        }
        func hidden(_ element: SwiftSoup.Element) throws -> Bool {
            let ariaHidden = try element.attr("aria-hidden")
            if element.hasAttr("hidden") || ariaHidden == "true" { return true }
            let style = try element.attr("style").lowercased().replacingOccurrences(of: " ", with: "")
            return style.contains("display:none") || style.contains("visibility:hidden")
        }
        func rawText(_ node: SwiftSoup.Node, depth: Int) throws -> String {
            try check(depth)
            if let text = node as? SwiftSoup.TextNode { return text.getWholeText() }
            if let element = node as? SwiftSoup.Element, element.tagNameNormal() == "br" { return "\n" }
            return try node.getChildNodes().map { try rawText($0, depth: depth + 1) }.joined()
        }
        func table(_ element: SwiftSoup.Element, depth: Int) throws -> String {
            var records: [SwiftSoup.Element] = []
            func rows(_ node: SwiftSoup.Element) {
                for child in node.children() {
                    if child.tagNameNormal() == "tr" { records.append(child) }
                    else if ["thead", "tbody", "tfoot"].contains(child.tagNameNormal()) { rows(child) }
                }
            }
            rows(element)
            var values: [[String]] = [], alignments: [MarkdownTable.Alignment] = []
            for row in records {
                var cells: [String] = []
                for cell in row.children() where ["td", "th"].contains(cell.tagNameNormal()) {
                    guard (Int(try cell.attr("colspan")) ?? 1) == 1, (Int(try cell.attr("rowspan")) ?? 1) == 1, try cell.select("table").isEmpty() else {
                        throw VaultFailure(message: "Merged or nested HTML tables need Paste plain text. Your note is unchanged.")
                    }
                    let text = try inlineChildren(cell, depth: depth + 1).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                    cells.append(text)
                    if values.isEmpty {
                        let align = try cell.attr("align").lowercased(), style = try cell.attr("style").lowercased()
                        alignments.append(align == "right" || style.contains("text-align: right") ? .right : align == "center" || style.contains("text-align: center") ? .center : .automatic)
                    }
                }
                if !cells.isEmpty { values.append(cells) }
            }
            guard !values.isEmpty else { return "" }
            let columns = values.map(\.count).max()!
            guard columns <= 80, values.count <= 1000, values.count * columns <= 20_000 else { throw VaultFailure(message: "Copy a smaller HTML table.") }
            values = values.map { $0 + Array(repeating: "", count: columns - $0.count) }
            let caption = try element.children().first(where: { $0.tagNameNormal() == "caption" }).map { try content($0.getChildNodes(), depth: depth + 1) } ?? ""
            return (caption.isEmpty ? "" : caption + "\n\n") + MarkdownTable(rows: values, alignments: alignments).markdown
        }
    }
}

private final class NativeHTMLImageBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    init(limit: Int) { remaining = limit }
    func consume(_ count: Int) throws {
        try lock.withLock {
            guard count <= remaining else { throw VaultFailure(message: "The copied images exceed 50 MB. Copy a smaller selection.") }
            remaining -= count
        }
    }
}

private final class NativeHTMLImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let budget: NativeHTMLImageBudget
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var data = Data()
    private var cancelled = false
    init(budget: NativeHTMLImageBudget) { self.budget = budget }
    static func fetch(_ url: URL, budget: NativeHTMLImageBudget) async throws -> Data {
        let operation = NativeHTMLImageDownload(budget: budget)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { operation.start(url, continuation: $0) }
        }, onCancel: { operation.cancel() })
    }
    private func start(_ url: URL, continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session; task = session.dataTask(with: url)
        let task = self.task; lock.unlock(); task?.resume()
    }
    private func finish(_ error: Error? = nil) {
        let result = lock.withLock { () -> (CheckedContinuation<Data, Error>?, Data, URLSession?) in
            let result = (continuation, data, session); continuation = nil; session = nil; task = nil; data = Data(); return result
        }
        result.2?.invalidateAndCancel()
        if let error { result.0?.resume(throwing: error) } else { result.0?.resume(returning: result.1) }
    }
    private func cancel() { lock.withLock { cancelled = true }; finish(CancellationError()) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), response.expectedContentLength <= NativeClipboardFragment.limit else {
            completionHandler(.cancel); finish(VaultFailure(message: "A copied image could not be downloaded. Your writing is unchanged; copy the image separately or use Paste plain text.")); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do { try budget.consume(data.count); lock.withLock { if continuation != nil { self.data.append(data) } } }
        catch { finish(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error.map { _ in VaultFailure(message: "A copied image could not be downloaded. Your writing is unchanged; copy the image separately or use Paste plain text.") })
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, let scheme = url.scheme, ["https", "http"].contains(scheme), url.user == nil, url.password == nil,
              response.url?.scheme != "https" || scheme == "https" else { completionHandler(nil); finish(VaultFailure(message: "A copied image redirected to an unsupported address. Your note is unchanged.")); return }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}
