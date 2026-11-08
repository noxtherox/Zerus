import Foundation
import Markdown

/// Read-only, plain-text collection/search excerpts. Cache by exact source, so
/// repeated SwiftUI row evaluations do not reparse every visible note. NSCache
/// synchronizes access and can discard this display-only data under pressure.
enum NativeMarkdownPreview {
    private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 512; cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func text(_ note: NoteDocument) -> String {
        let key = note.content as NSString
        if let cached = cache.object(forKey: key) { return cached as String }
        let saved = note.savedLink
        let source = saved.map { NativeSavedLink.withoutURL(note.parts.body, address: $0.address) } ?? note.parts.body
        // Source-position recognition excludes code, image captions and HTML.
        // A regex over the whole note would mistake literal examples for links.
        let edits = ((try? MarkdownMoveLinks.links(in: source)) ?? []).compactMap { link -> (MarkdownMoveLinks.Link, String)? in
            guard case .wiki = link.kind else { return nil }
            return (link, NoteReference.inlineMarkdown(link.value))
        }
        let document = Document(parsing: MarkdownMoveLinks.replacing(source, edits: edits))
        var output = ""
        func visit(_ node: any Markup) {
            if let paragraph = node as? Paragraph, node.parent is Document, paragraph.childCount == 1,
               let text = paragraph.child(at: 0) as? Markdown.Text, let expected = saved?.url?.absoluteString,
               NativeSavedLink.normalizedURL(text.string)?.absoluteString == expected { return }
            if let heading = node as? Heading, heading.level == 1 { return }
            if node is HTMLBlock || node is InlineHTML { return }
            if let text = node as? Markdown.Text { output += text.string; return }
            if let code = node as? InlineCode { output += code.code; return }
            if let code = node as? CodeBlock { output += code.code; output += " "; return }
            if node is SoftBreak || node is LineBreak { output += " "; return }
            for child in node.children {
                visit(child)
                if child is BlockMarkup || child is Table.Cell { output += " " }
            }
        }
        visit(document)
        let plain = output.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        cache.setObject(plain as NSString, forKey: key, cost: key.length * 2 + plain.utf16.count * 2)
        return plain
    }
}
