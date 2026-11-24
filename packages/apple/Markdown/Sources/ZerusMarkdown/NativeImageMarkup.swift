import Foundation
import Markdown
import SwiftSoup

public struct NativeImageMarkup: Sendable {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    public var reference: String
    public var caption: String
    public var title: String
    public var width: Int?
    public var height: Int?
    public init(reference: String, caption: String, title: String = "", width: Int? = nil, height: Int? = nil) {
        self.reference = reference; self.caption = caption; self.title = title; self.width = width; self.height = height
    }
    public init(_ image: Markdown.Image) {
        self.init(reference: image.source ?? "", caption: image.plainText, title: image.title ?? "")
        if let range = caption.range(of: #"\|[0-9]+$"#, options: .regularExpression), let value = Int(caption[range].dropFirst()), (1...8192).contains(value) {
            width = value; caption = String(caption[..<range.lowerBound])
        }
    }
    public init?(html: String) {
        guard html.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<img"),
              let body = try? SwiftSoup.parseBodyFragment(html).body(), body.children().count == 1,
              body.ownText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let image = body.children().first(), image.tagName() == "img",
              body.getChildNodes().allSatisfy({ $0 is SwiftSoup.Element || $0 is SwiftSoup.TextNode }),
              let attrs = image.getAttributes()?.asList(), Set(attrs.map { $0.getKey().lowercased() }).isSubset(of: ["src", "alt", "title", "width", "height"]),
              let reference = try? image.attr("src"), !reference.isEmpty else { return nil }
        var dimensions: [String: Int] = [:]
        for name in ["width", "height"] where image.hasAttr(name) {
            guard let text = try? image.attr(name), let number = Int(text), (1...8192).contains(number) else { return nil }
            dimensions[name] = number
        }
        self.init(reference: reference, caption: (try? image.attr("alt")) ?? "", title: (try? image.attr("title")) ?? "", width: dimensions["width"], height: dimensions["height"])
    }
    public struct HTMLImage: Sendable { public let range: NSRange; public let value: NativeImageMarkup }
    /// Image-only HTML fragments; examples inside other HTML are never editable occurrences.
    public static func htmlImages(in source: String) -> [HTMLImage] {
        guard let pattern = try? NSRegularExpression(pattern: #"(?is)<img\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>"#) else { return [] }
        let raw = source as NSString, matches = pattern.matches(in: source, range: NSRange(location: 0, length: raw.length))
        var images: [HTMLImage] = [], cursor = 0
        for match in matches {
            guard raw.substring(with: NSRange(location: cursor, length: match.range.location - cursor)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let value = Self(html: raw.substring(with: match.range)) else { return [] }
            images.append(.init(range: match.range, value: value)); cursor = NSMaxRange(match.range)
        }
        guard raw.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return images
    }
    public func displaySize(naturalWidth: Double, naturalHeight: Double) -> (width: Double, height: Double) {
        let ratio = max(0.001, naturalWidth) / max(0.001, naturalHeight)
        let width = self.width.map(Double.init) ?? height.map { Double($0) * ratio } ?? naturalWidth
        return (max(1, width), max(1, self.height.map(Double.init) ?? width / ratio))
    }
    public static func parse(_ literal: String) -> Self? {
        if let html = Self(html: literal) { return html }
        let document = Document(parsing: literal)
        guard let paragraph = document.child(at: 0) as? Paragraph, paragraph.childCount == 1, let image = paragraph.child(at: 0) as? Markdown.Image else { return nil }
        return .init(image)
    }
    public static func dimension(_ value: String) throws -> Int? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard text.allSatisfy(\.isNumber), let value = Int(text), (1...8192).contains(value) else { throw Failure(message: "Enter a whole-number size from 1 to 8192, or leave it blank for automatic sizing.") }
        return value
    }
    public func validated() throws -> Self {
        guard !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reference.count <= 4096,
              ![reference, caption, title].contains(where: { $0.unicodeScalars.contains(where: { $0.value < 32 }) }), caption.count <= 2000, title.count <= 2000,
              URL(string: reference)?.scheme.map({ ["http", "https"].contains($0.lowercased()) }) ?? true,
              [width, height].compactMap({ $0 }).allSatisfy({ (1...8192).contains($0) }) else { throw Failure(message: "Check the image address, description and size.") }
        return self
    }
    public var markdown: String {
        func html(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "&#10;").replacingOccurrences(of: "\r", with: "&#13;") }
        if width != nil || height != nil {
            return "<img src=\"" + html(reference) + "\" alt=\"" + html(caption) + "\"" + (title.isEmpty ? "" : " title=\"" + html(title) + "\"") + (width.map { " width=\"\($0)\"" } ?? "") + (height.map { " height=\"\($0)\"" } ?? "") + " />"
        }
        let alt = caption.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        let path = reference.replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
        let savedTitle = title.isEmpty ? "" : " \"" + title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return "![" + alt + "](<" + path + ">" + savedTitle + ")"
    }
}
