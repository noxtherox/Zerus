import AppKit

extension NSAttributedString.Key {
    static let macTable = Self("ZerusMacTable")
    static let macCell = Self("ZerusMacCell")
    static let macCellEnd = Self("ZerusMacCellEnd")
    static let macCellPlaceholder = Self("ZerusMacCellPlaceholder")
}

final class MacRichTable: NSObject {
    let original: MarkdownTable
    let ending: String
    let quote: MacQuoteContext?
    let layout = NSTextTable()
    init(_ original: MarkdownTable, ending: String, quote: MacQuoteContext? = nil) {
        self.original = original; self.ending = ending; self.quote = quote
        layout.numberOfColumns = original.columns; layout.collapsesBorders = true; layout.hidesEmptyCells = false
        layout.layoutAlgorithm = .fixed
        layout.setValue(100, type: .percentage, for: .width)
    }
    final class Cell: NSObject {
        let table: MacRichTable
        let row: Int
        let column: Int
        let block: NSTextTableBlock
        let source: String
        var fingerprint = ""
        init(table: MacRichTable, row: Int, column: Int) {
            self.table = table; self.row = row; self.column = column; source = table.original.rows[row][column]
            block = NSTextTableBlock(table: table.layout, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
            let widths = table.original.widths ?? Array(repeating: 160, count: table.original.columns)
            block.setValue(CGFloat(widths[column]) * 100 / CGFloat(max(1, widths.reduce(0, +))), type: .percentage, for: .width)
            block.setWidth(8, type: .absolute, for: .padding); block.setWidth(0.5, type: .absolute, for: .border)
            block.setBorderColor(.separatorColor)
            block.backgroundColor = row == 0 ? NSColor.quaternaryLabelColor.withAlphaComponent(0.07) : .textBackgroundColor
            block.verticalAlignment = .top
        }
        var attributes: [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle(); style.textBlocks = [block]; style.paragraphSpacing = 0; style.lineSpacing = 3; style.headIndent = CGFloat((table.quote?.depth ?? 0) * 18); style.firstLineHeadIndent = style.headIndent
            switch table.original.alignments[column] { case .center: style.alignment = .center; case .right: style.alignment = .right; default: style.alignment = .left }
            return [.macTable: table, .macCell: self, .macBlock: table.quote?.prefix ?? "", .macStrong: false, .font: NSFont.systemFont(ofSize: 14, weight: row == 0 ? .semibold : .regular), .paragraphStyle: style, .foregroundColor: NSColor.labelColor]
        }
    }
    static func render(_ model: MarkdownTable, ending: String, root: URL?, path: String, images: [String: NSImage] = [:], quote: MacQuoteContext? = nil) -> NSAttributedString {
        let table = MacRichTable(model, ending: ending, quote: quote), output = NSMutableAttributedString()
        for row in model.rows.indices {
            for column in 0..<model.columns {
                let cell = Cell(table: table, row: row, column: column)
                let body = NSMutableAttributedString(attributedString: MacMarkdown.renderTableCell(cell.source, attributes: cell.attributes, root: root, path: path, images: images))
                cell.fingerprint = Self.cellSignature(body)
                if body.length == 0 { body.append(NSAttributedString(string: "\u{200b}", attributes: cell.attributes)); body.addAttribute(.macCellPlaceholder, value: true, range: NSRange(location: 0, length: 1)) }
                var attrs = cell.attributes; attrs[.macCellEnd] = true
                body.append(NSAttributedString(string: "\n", attributes: attrs)); output.append(body)
            }
        }
        return output
    }
    func markdown(_ value: NSAttributedString) -> String {
        let inner = model(value).markdown
        return quote?.spelling(inner) ?? inner
    }
    static func at(_ text: NSAttributedString, _ index: Int) -> Cell? {
        guard index >= 0, index < text.length else { return nil }
        return text.attribute(.macCell, at: index, effectiveRange: nil) as? Cell
    }
    static func body(_ value: NSAttributedString) -> NSAttributedString {
        let output = NSMutableAttributedString(attributedString: value), raw = value.string as NSString
        for index in (0..<value.length).reversed() {
            if value.attribute(.macCellEnd, at: index, effectiveRange: nil) != nil && raw.character(at: index) == 10 || value.attribute(.macCellPlaceholder, at: index, effectiveRange: nil) != nil && raw.character(at: index) == 0x200b { output.deleteCharacters(in: NSRange(location: index, length: 1)) }
        }
        return output
    }
    /// Container placement does not edit a cell's inline text. Keep its exact
    /// source while list ownership/indentation changes around the table.
    private static func cellSignature(_ value: NSAttributedString) -> String {
        let inline = NSMutableAttributedString(attributedString: value)
        for key in [NSAttributedString.Key.macListContext, .macBlock] { inline.removeAttribute(key, range: NSRange(location: 0, length: inline.length)) }
        return MacMarkdown.signature(inline)
    }
    func model(_ value: NSAttributedString) -> MarkdownTable {
        var model = original
        value.enumerateAttribute(.macCell, in: NSRange(location: 0, length: value.length)) { item, range, _ in
            guard let cell = item as? Cell, cell.table === self else { return }
            let body = Self.body(value.attributedSubstring(from: range))
            model.rows[cell.row][cell.column] = Data(Self.cellSignature(body).utf8) == Data(cell.fingerprint.utf8) ? cell.source : MacMarkdown.tableCellMarkdown(body)
        }
        return model
    }
    static func insertion(_ value: NSAttributedString, cell: Cell) -> NSAttributedString {
        let output = NSMutableAttributedString(attributedString: value)
        let raw = output.string as NSString
        var index = raw.length - 1
        while index >= 0 {
            if raw.character(at: index) == 10, index > 0, raw.character(at: index - 1) == 13 { output.replaceCharacters(in: NSRange(location: index - 1, length: 2), with: "\u{2028}"); index -= 2 }
            else { if raw.character(at: index) == 10 || raw.character(at: index) == 13 { output.replaceCharacters(in: NSRange(location: index, length: 1), with: "\u{2028}") }; index -= 1 }
        }
        let full = NSRange(location: 0, length: output.length)
        for key in [NSAttributedString.Key.macOriginal, .macSignature, .macParagraphID, .macParagraphSource, .macParagraphSignature, .macCode, .macCodeSeparator, .macCodePlaceholder, .macCellEnd, .macCellPlaceholder] { output.removeAttribute(key, range: full) }
        output.addAttributes([.macTable: cell.table, .macCell: cell, .macBlock: "", .paragraphStyle: cell.attributes[.paragraphStyle]!], range: full)
        return output
    }
    /// Preserve cell terminators for partial selections; whole selected tables can be removed.
    static func replacing(_ original: NSAttributedString, range: NSRange, with replacement: NSAttributedString, preservingGrid: Bool = false) -> NSAttributedString {
        var protected = IndexSet()
        original.enumerateAttribute(.macTable, in: NSRange(location: 0, length: original.length)) { value, tableRange, _ in
            guard value is MacRichTable, NSIntersectionRange(range, tableRange).length > 0, (preservingGrid || NSIntersectionRange(range, tableRange) != tableRange) else { return }
            original.enumerateAttribute(.macCellEnd, in: NSIntersectionRange(range, tableRange)) { value, range, _ in if value != nil { protected.insert(integersIn: range.location..<NSMaxRange(range)) } }
        }
        var removed = IndexSet(integersIn: range.location..<NSMaxRange(range)); removed.subtract(protected)
        let output = NSMutableAttributedString(attributedString: original)
        for piece in removed.rangeView.reversed() { output.deleteCharacters(in: NSRange(location: piece.lowerBound, length: piece.count)) }
        output.insert(replacement, at: range.location)
        return output
    }
}
