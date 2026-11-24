import AppKit

/// Spreadsheet transport is plain cell text; the Zerus fragment retains inline Markdown.
@MainActor enum MacTableClipboard {
    static func spreadsheet(_ text: String, explicit: Bool = false) throws -> MarkdownTable? {
        guard explicit || text.contains("\t") else { return nil }
        guard text.utf8.count <= NativeClipboardFragment.limit else { throw VaultFailure(message: "Copy a spreadsheet selection smaller than 50 MB.") }
        let input = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false, index = 0, count = 0
        func finishCell() throws {
            count += 1
            guard count <= 10_000 else { throw VaultFailure(message: "Paste at most 10,000 spreadsheet cells at a time.") }
            let body = NSAttributedString(string: cell, attributes: [.font: MacMarkdown.font(""), .macBlock: ""])
            row.append(MacMarkdown.tableCellMarkdown(body)); cell = ""
        }
        while index < input.count {
            let character = input[index]
            if character == "\"", quoted || cell.isEmpty {
                if quoted, index + 1 < input.count, input[index + 1] == "\"" { cell.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if !quoted, character == "\t" || character == "\n" {
                try finishCell()
                if character == "\n" { rows.append(row); row = [] }
            } else { cell.append(character) }
            index += 1
        }
        guard !quoted else { throw VaultFailure(message: "The spreadsheet selection has an unfinished quoted cell. Copy it again or use Paste and Match Style.") }
        if !cell.isEmpty || !row.isEmpty || input.last != "\n" { try finishCell(); rows.append(row) }
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0, columns * rows.count <= 10_000 else { throw VaultFailure(message: "Paste at most 10,000 spreadsheet cells at a time.") }
        return MarkdownTable(rows: rows.map { $0 + Array(repeating: "", count: columns - $0.count) })
    }
    static func table(_ markdown: String) -> MarkdownTable? {
        let blocks = MacMarkdown.tables(in: markdown), raw = markdown as NSString
        guard blocks.count == 1, let block = blocks.first,
              raw.substring(to: block.range.location).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              raw.substring(from: NSMaxRange(block.range)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return block.table
    }
    struct Selection {
        let rich: NSAttributedString
        let tsv: String
    }
    /// A full table, full rows, or complete adjacent cells in one row form a grid.
    /// Partial words and irregular cross-row selections retain ordinary text copy.
    static func selection(_ text: NSAttributedString, range: NSRange, root: URL?, path: String, images: [String: NSImage] = [:]) -> Selection? {
        guard range.length > 0, let start = MacRichTable.at(text, range.location) else { return nil }
        var tableRange = NSRange()
        _ = text.attribute(.macTable, at: range.location, longestEffectiveRange: &tableRange, in: NSRange(location: 0, length: text.length))
        guard NSIntersectionRange(range, tableRange) == range else { return nil }
        var cells: [(MacRichTable.Cell, NSRange, NSAttributedString)] = []
        text.enumerateAttribute(.macCell, in: tableRange) { value, cellRange, _ in
            guard let cell = value as? MacRichTable.Cell, NSIntersectionRange(range, cellRange).length > 0 else { return }
            cells.append((cell, cellRange, MacRichTable.body(text.attributedSubstring(from: cellRange))))
        }
        guard cells.count > 1 || range == tableRange, let first = cells.first, let last = cells.last, range.location == first.1.location,
              NSMaxRange(range) >= last.1.location + last.2.length,
              first.0.row == last.0.row || first.0.column == 0 && last.0.column == start.table.original.columns - 1 else { return nil }
        let model = start.table.model(text.attributedSubstring(from: tableRange))
        let columns = first.0.row == last.0.row ? first.0.column...last.0.column : 0...(model.columns - 1)
        let rows = first.0.row...last.0.row
        let copied = range == tableRange ? model : MarkdownTable(rows: rows.map { r in columns.map { model.rows[r][$0] } }, alignments: columns.map { model.alignments[$0] }, widths: model.widths.map { widths in columns.map { widths[$0] } }, newline: model.newline)
        var rendered = MacRichTable.render(copied, ending: "", root: root, path: path, images: images, quote: range == tableRange ? start.table.quote : nil)
        if range == tableRange { rendered = MacListCardPlacement.detached(rendered, from: text.attributes(at: range.location, effectiveRange: nil)) }
        let bodies = Dictionary(uniqueKeysWithValues: cells.map { ($0.0.row * model.columns + $0.0.column, $0.2.string) })
        var values: [String] = []
        for row in rows {
            let line = columns.map { column -> String in
                let body = bodies[row * model.columns + column] ?? ""
                let value = body.replacingOccurrences(of: "\u{2028}", with: "\n").replacingOccurrences(of: "\u{2029}", with: "\n")
                if value.contains("\t") || value.contains("\n") || value.contains("\"") { return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                return value
            }.joined(separator: "\t")
            values.append(line)
        }
        return Selection(rich: rendered, tsv: values.joined(separator: "\n"))
    }
    static func pasting(_ pasted: MarkdownTable, into original: NSAttributedString, range: NSRange, root: URL?, path: String, images: [String: NSImage] = [:]) throws -> (NSAttributedString, NSRange)? {
        guard let cell = MacRichTable.at(original, range.location) else { return nil }
        var tableRange = NSRange()
        _ = original.attribute(.macTable, at: range.location, longestEffectiveRange: &tableRange, in: NSRange(location: 0, length: original.length))
        guard NSIntersectionRange(range, tableRange) == range else { return nil }
        var model = cell.table.model(original.attributedSubstring(from: tableRange))
        let row: Int, column: Int
        if range == tableRange { model = pasted; row = 0; column = 0 }
        else {
            row = cell.row; column = cell.column
            let totalRows = max(model.rows.count, row + pasted.rows.count), totalColumns = max(model.columns, column + pasted.columns)
            guard totalRows * totalColumns <= 10_000 else { throw VaultFailure(message: "This paste would exceed 10,000 table cells. Paste a smaller selection.") }
            while model.columns < totalColumns { model.insertColumn(at: model.columns) }
            while model.rows.count < totalRows { model.insertRow(at: model.rows.count) }
            for r in pasted.rows.indices { for c in 0..<pasted.columns { model.rows[row + r][column + c] = pasted.rows[r][c] } }
        }
        let replacement = MacListCardPlacement.carrying(MacRichTable.render(model, ending: cell.table.ending, root: root, path: path, images: images, quote: cell.table.quote), from: original.attributedSubstring(from: tableRange))
        var destination = 0
        replacement.enumerateAttribute(.macCell, in: NSRange(location: 0, length: replacement.length)) { value, range, stop in
            if let cell = value as? MacRichTable.Cell, cell.row == row, cell.column == column { destination = range.location; stop.pointee = true }
        }
        let output = NSMutableAttributedString(attributedString: original); output.replaceCharacters(in: tableRange, with: replacement)
        return (output, NSRange(location: tableRange.location + destination, length: 0))
    }
}
