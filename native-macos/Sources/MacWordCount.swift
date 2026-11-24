import Foundation
import SwiftUI
import Markdown

/// Counts whitespace-separated content words, excluding Markdown control syntax.
enum MacWordCount {
    private static let cache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 32; cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()
    // Code bodies commonly stay unchanged while adjacent prose is edited.
    // Keep their expensive grapheme-based count independently of the note key.
    private static let codeCounts: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 32; cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()
    private static func codeWordCount(_ body: String) -> Int {
        let key = body as NSString
        if let saved = codeCounts.object(forKey: key) { return saved.intValue }
        let count = body.split(whereSeparator: \.isWhitespace).count
        codeCounts.setObject(NSNumber(value: count), forKey: key, cost: key.length * 2)
        return count
    }
    static func count(_ markdown: String) -> Int {
        let key = markdown as NSString
        if let saved = cache.object(forKey: key) { return saved.intValue }
        let edits = ((try? MarkdownMoveLinks.links(in: markdown)) ?? []).compactMap { link -> (MarkdownMoveLinks.Link, String)? in
            guard case .wiki = link.kind else { return nil }
            return (link, NoteReference.inlineMarkdown(link.value))
        }
        let document = Document(parsing: MarkdownMoveLinks.replacing(markdown, edits: edits))
        var plain = "", codeWords = 0
        func visit(_ node: any Markup) {
            if node is Markdown.Image || node is HTMLBlock { return }
            if let html = node as? InlineHTML {
                if html.rawHTML.range(of: #"(?i)^<br\s*/?>$"#, options: .regularExpression) != nil { plain += " " }
                return
            }
            if let text = node as? Markdown.Text {
                if text.string != MacMarkdown.emptyParagraphMarker || text.parent.map({ !MacMarkdown.isEmptyParagraphMarker($0) }) != false { plain += text.string }
                return
            }
            if let code = node as? InlineCode { plain += code.code; return }
            if let code = node as? CodeBlock {
                let body = code.code
                // A leading ASCII scalar cannot join the preceding space's
                // grapheme. The final LF also ends the last code word. Other
                // shapes retain the original whole-text counting path.
                if (plain.isEmpty || plain.hasSuffix(" ")), body.hasSuffix("\n"),
                   body.unicodeScalars.first.map({ $0.value < 128 }) == true {
                    codeWords += codeWordCount(body); plain += " "
                } else { plain += body + " " }
                return
            }
            if node is SoftBreak || node is LineBreak { plain += " "; return }
            for child in node.children {
                visit(child)
                if child is BlockMarkup || child is Markdown.Table.Cell { plain += " " }
            }
        }
        visit(document)
        let count = codeWords + plain.split(whereSeparator: \.isWhitespace).count
        cache.setObject(NSNumber(value: count), forKey: key, cost: key.length * 2)
        return count
    }
}


@MainActor struct MacWordCountLabel: View {
    let markdown: String
    private static let queue = DispatchQueue(label: "com.zerus.notes.footer-word-count", qos: .userInitiated)
    @StateObject private var state = MacMarkdownSnapshotState<Int>(queue: queue, compute: { MacWordCount.count($0) })
    var body: some View {
        Group {
            if let count = state.value { SwiftUI.Text("\(count) words") }
            else { SwiftUI.Text("Counting words…") }
        }
        .onChange(of: markdown, initial: true) { _, value in state.request(value) }
        .onDisappear { state.cancel() }
    }
}
