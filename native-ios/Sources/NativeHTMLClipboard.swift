import Foundation
import SwiftSoup
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
            let markdown = try content(body.getChildNodes(), depth: 0).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !markdown.isEmpty else { throw VaultFailure(message: "This HTML selection has no supported writing. Use Paste plain text or copy the image separately.") }
            return Plan(markdown: markdown + "\n", images: images)
        }
        func content(_ nodes: [SwiftSoup.Node], depth: Int) throws -> String {
            var output: [String] = [], pending = ""
            func flush() {
                let value = pending.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { output.append(MarkdownText.escapeLiteralBlockStart(value)) }
                pending = ""
            }
            for node in nodes {
                if let element = node as? SwiftSoup.Element, blocks.contains(element.tagNameNormal()) {
                    flush(); let value = try block(element, depth: depth + 1)
                    if !value.isEmpty { output.append(value) }
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
                return String(repeating: "#", count: Int(tag.dropFirst())!) + " " + (try inlineChildren(element, depth: depth)).trimmingCharacters(in: .whitespacesAndNewlines)
            case "ul", "ol":
                var number = Int(try element.attr("start")) ?? 1, lines: [String] = []
                guard (1...999_999_999).contains(number) else { throw VaultFailure(message: "This copied list uses unsupported numbering. Use Paste plain text.") }
                for item in element.children() where item.tagNameNormal() == "li" {
                    if let explicit = Int(try item.attr("value")) { number = explicit }
                    let checkbox = try item.select("input[type=checkbox]").first()
                    let marker = checkbox.map { $0.hasAttr("checked") ? "- [x] " : "- [ ] " } ?? (tag == "ol" ? "\(number). " : "- ")
                    let value = try content(item.getChildNodes(), depth: depth + 1)
                    let parts = value.components(separatedBy: "\n")
                    lines.append(marker + (parts.first ?? "") + parts.dropFirst().map { $0.isEmpty ? "\n" : "\n" + String(repeating: " ", count: marker.count) + $0 }.joined())
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
            default: return try content(element.getChildNodes(), depth: depth + 1)
            }
        }
        func inlineChildren(_ element: SwiftSoup.Element, depth: Int) throws -> String {
            try element.getChildNodes().map { try inline($0, depth: depth + 1) }.joined()
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
            if tag == "br" { return "\n" }
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
            let strike = ["s", "strike", "del"].contains(tag) || style["text-decoration"]?.contains("line-through") == true || style["text-decoration-line"]?.contains("line-through") == true
            if value.allSatisfy(\.isWhitespace) { return value }
            let leading = String(value.prefix(while: \.isWhitespace)), trailing = String(value.reversed().prefix(while: \.isWhitespace).reversed())
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                if bold { value = "**" + value + "**" }; if italic { value = "*" + value + "*" }; if strike { value = "~~" + value + "~~" }
                if tag == "a", let address = try address(element, attribute: "href", image: false) {
                    let escaped = address.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
                    value = "[" + value + "](" + escaped + ")"
                }
            }
            return leading + value + trailing
        }
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
