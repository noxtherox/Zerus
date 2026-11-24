import Foundation
import Markdown

/// One source-ordered identity for each code card owned by the document or quotes. Menus, rendering
/// and sheet commits use the same discovery, including indented source.
struct MacCodeBlock {
    let range: NSRange
    let code: FencedCode
    let indented: MacIndentedCode?
    var quote: MacQuoteContext? = nil
    var container: MacListCardSource? = nil

    static func blocks(in source: String, document: Document? = nil, ownedCards: [MacListOwnedCard]? = nil) -> [Self] {
        let document = document ?? Document(parsing: source)
        let quoted = MacQuotedCards.blocks(in: source, document: document).compactMap { card -> Self? in
            guard let code = card.code else { return nil }
            return .init(range: card.range, code: code.code, indented: code.indented, quote: card.quote)
        }
        let owned = (ownedCards ?? MacListCards.blocks(in: source, document: document)).compactMap { card -> Self? in
            guard let code = card.code else { return nil }
            return .init(range: card.source.range, code: code.code, indented: code.indented, container: card.source)
        }
        return (rootBlocks(in: source, document: document) + quoted + owned).sorted { $0.range.location < $1.range.location }
    }
    static func rootBlocks(in source: String, document: Document) -> [Self] {
        let lines = MacMarkdownLines(source)
        let indented = MacIndentedCode.blocks(in: source, document: document)
        return document.children.compactMap { node -> Self? in
            guard node is CodeBlock, let span = node.range else { return nil }
            let first = span.lowerBound.line - 1, last = min(span.upperBound.line - 1, lines.lines.count - 1)
            guard first >= 0, first <= last else { return nil }
            if let block = indented.first(where: { $0.range.location == lines.lines[first].offset }) {
                return .init(range: block.range, code: block.code, indented: block)
            }
            let raw = lines.fragment(first..<(last + 1), includeLastEnding: false)
            guard let located = FencedCode.blocks(in: raw).first, located.range.location == 0 else { return nil }
            return .init(range: NSRange(location: lines.lines[first].offset, length: located.range.length), code: located.code, indented: nil)
        }
    }
    func replacing(body: String, info: String) -> String {
        let inner = indented.flatMap { info.isEmpty ? $0.markdown(body: body) : nil } ?? code.replacing(body: body, info: info).markdown
        return container == nil ? quote?.spelling(inner) ?? inner : inner
    }
}
