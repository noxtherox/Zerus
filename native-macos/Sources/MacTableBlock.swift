import Foundation
import Markdown

struct MacTableBlock {
    let range: NSRange
    let table: MarkdownTable
    var quote: MacQuoteContext? = nil
    var container: MacListCardSource? = nil
    static func rootBlocks(in source: String, excluding: [NSRange]) -> [Self] {
        MarkdownTable.blocks(in: source, excluding: excluding).map { located in
            var table = located.table
            let ending = MacMarkdownLines(table.markdown).lines.first(where: { $0.text.contains("|") })?.ending
            if ending == "\r", table.newline != ending {
                table = MarkdownTable(rows: table.rows, alignments: table.alignments, widths: table.widths, widthMarker: table.widthMarker, newline: "\r", original: table.markdown)
            }
            return .init(range: located.range, table: table)
        }
    }
    static func blocks(in source: String, excluding: [NSRange], document: Document? = nil, ownedCards: [MacListOwnedCard]? = nil) -> [Self] {
        let document = document ?? Document(parsing: source)
        let quoted = MacQuotedCards.blocks(in: source, document: document).compactMap { card -> Self? in
            guard let table = card.table else { return nil }
            return .init(range: card.range, table: table, quote: card.quote)
        }
        let owned = (ownedCards ?? MacListCards.blocks(in: source, document: document)).compactMap { card -> Self? in
            guard let table = card.table else { return nil }
            return .init(range: card.source.range, table: table, container: card.source)
        }
        let embedded = quoted + owned
        let roots = rootBlocks(in: source, excluding: excluding).filter { root in !embedded.contains { NSIntersectionRange(root.range, $0.range).length > 0 } }
        return (roots + embedded).sorted { $0.range.location < $1.range.location }
    }
}

// Table-sheet structure actions preserve cell content and portable metadata.
extension MarkdownTable {
    @discardableResult mutating func moveRow(from source: Int, to destination: Int) -> Bool {
        guard rows.indices.contains(source), rows.indices.contains(destination), source != destination else { return false }
        let row = rows.remove(at: source); rows.insert(row, at: destination)
        // A body row may retain extra cells from imported Markdown. If it
        // becomes the header, expose those cells without dropping old columns.
        if columns > alignments.count {
            let extra = columns - alignments.count
            alignments.append(contentsOf: Array(repeating: .automatic, count: extra))
            widths?.append(contentsOf: Array(repeating: 160, count: extra))
            for index in rows.indices { rows[index].append(contentsOf: Array(repeating: "", count: max(0, columns - rows[index].count))) }
        }
        return true
    }
    @discardableResult mutating func moveColumn(from source: Int, to destination: Int) -> Bool {
        guard (0..<columns).contains(source), (0..<columns).contains(destination), source != destination else { return false }
        for index in rows.indices {
            let cell = rows[index].remove(at: source); rows[index].insert(cell, at: destination)
        }
        let alignment = alignments.remove(at: source); alignments.insert(alignment, at: destination)
        if var values = widths { let width = values.remove(at: source); values.insert(width, at: destination); widths = values }
        return true
    }
}
