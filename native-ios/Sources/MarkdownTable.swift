import Foundation

/// Portable GFM tables. Unedited tables retain their original bytes, including
/// the web editor's optional column-width comment and otherwise ignored cells.
struct MarkdownTable: Equatable {
    enum Alignment: String, CaseIterable, Identifiable {
        case automatic = "Automatic", left = "Left", center = "Center", right = "Right"
        var id: String { rawValue }
        var delimiter: String {
            switch self { case .automatic: return "---"; case .left: return ":---"; case .center: return ":---:"; case .right: return "---:" }
        }
    }
    var rows: [[String]]
    var alignments: [Alignment]
    var widths: [Int]?
    var widthMarker: String
    let newline: String
    private let original: String?
    private let originalRows: [[String]]
    private let originalAlignments: [Alignment]
    private let originalWidths: [Int]?
    private let originalMarker: String
    var columns: Int { rows[0].count }

    init(rows: [[String]], alignments: [Alignment] = [], widths: [Int]? = nil, widthMarker: String = "", newline: String = "\n", original: String? = nil) {
        let columns = max(1, rows.first?.count ?? 1)
        self.rows = (rows.isEmpty ? [[""]] : rows).map { row in row + Array(repeating: "", count: max(0, columns - row.count)) }
        self.alignments = (0..<columns).map { alignments.indices.contains($0) ? alignments[$0] : .automatic }
        self.widths = widths?.count == columns ? widths : nil
        self.widthMarker = widthMarker; self.newline = newline; self.original = original
        originalRows = self.rows; originalAlignments = self.alignments; originalWidths = self.widths; originalMarker = widthMarker
    }

    var markdown: String {
        if let original, rows == originalRows, alignments == originalAlignments, widths == originalWidths, widthMarker == originalMarker { return original }
        let marker: String
        if widths == originalWidths && !widthMarker.isEmpty { marker = widthMarker }
        else { marker = widths.map { "<!-- zerus-table-widths: " + $0.map(String.init).joined(separator: ",") + " -->" + newline } ?? "" }
        func row(_ cells: [String]) -> String { "| " + cells.map(Self.escapePipes).joined(separator: " | ") + " |" }
        return marker + ([row(rows[0]), row(alignments.map(\.delimiter))] + rows.dropFirst().map(row)).joined(separator: newline)
    }

    static func empty() -> MarkdownTable { MarkdownTable(rows: [["Column 1", "Column 2"], ["", ""]]) }

    mutating func insertRow(at index: Int) { rows.insert(Array(repeating: "", count: columns), at: min(max(0, index), rows.count)) }
    mutating func removeRow(at index: Int) {
        guard rows.count > 1 else { return }
        rows.remove(at: index)
        // Promoting a body row must also preserve any previously extra cells.
        if columns > alignments.count {
            let extra = columns - alignments.count
            alignments.append(contentsOf: Array(repeating: .automatic, count: extra))
            widths?.append(contentsOf: Array(repeating: 160, count: extra))
            for row in rows.indices { rows[row].append(contentsOf: Array(repeating: "", count: max(0, columns - rows[row].count))) }
        }
    }
    mutating func insertColumn(at index: Int) {
        for row in rows.indices { rows[row].insert("", at: index) }
        alignments.insert(.automatic, at: index); widths?.insert(160, at: index)
    }
    mutating func removeColumn(at index: Int) {
        guard columns > 1 else { return }
        for row in rows.indices { rows[row].remove(at: index) }
        alignments.remove(at: index); widths?.remove(at: index)
    }
    mutating func setWidth(_ width: Int, column: Int) {
        if widths == nil { widths = Array(repeating: 160, count: columns) }
        widths?[column] = min(720, max(80, width))
    }
    mutating func resetWidths() { widths = nil; widthMarker = "" }

    struct Located { let range: NSRange; let table: MarkdownTable }

    /// See https://github.github.com/gfm/#tables-extension- for pipe escaping,
    /// optional outer pipes, delimiter alignment, and row termination rules.
    static func blocks(in source: String, excluding: [NSRange] = []) -> [Located] {
        guard source.utf8.contains(0x7c) else { return [] }
        let text = source as NSString
        var lines: [(range: NSRange, text: String)] = [], cursor = 0
        while cursor < text.length {
            let range = text.lineRange(for: NSRange(location: cursor, length: 0))
            lines.append((range, text.substring(with: range).trimmingCharacters(in: .newlines)))
            cursor = NSMaxRange(range)
        }
        func excluded(_ index: Int) -> Bool { excluding.contains { NSIntersectionRange($0, lines[index].range).length > 0 } }
        var output: [Located] = [], index = 0
        while index + 1 < lines.count {
            guard lines[index].text.contains("|"), !excluded(index), !excluded(index + 1), !startsBlock(lines[index].text) else { index += 1; continue }
            let header = splitRow(lines[index].text), delimiter = splitRow(lines[index + 1].text)
            guard !header.isEmpty, header.count == delimiter.count,
                  delimiter.allSatisfy({ $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil }) else { index += 1; continue }
            let alignments: [Alignment] = delimiter.map { $0.hasPrefix(":") ? ($0.hasSuffix(":") ? .center : .left) : ($0.hasSuffix(":") ? .right : .automatic) }
            var rows = [header], endIndex = index + 2
            while endIndex < lines.count, !excluded(endIndex), !lines[endIndex].text.trimmingCharacters(in: .whitespaces).isEmpty, !startsBlock(lines[endIndex].text) {
                rows.append(splitRow(lines[endIndex].text)); endIndex += 1
            }
            var startIndex = index, previous = index - 1
            while previous >= 0 && lines[previous].text.trimmingCharacters(in: .whitespaces).isEmpty { previous -= 1 }
            var widths: [Int]?, marker = ""
            if previous >= 0 && !excluded(previous), let parsed = parseWidths(lines[previous].text) {
                startIndex = previous
                marker = text.substring(with: NSRange(location: lines[previous].range.location, length: lines[index].range.location - lines[previous].range.location))
                if parsed.count == header.count { widths = parsed }
            }
            let end = lines[endIndex - 1].range.location + (lines[endIndex - 1].text as NSString).length
            let range = NSRange(location: lines[startIndex].range.location, length: end - lines[startIndex].range.location)
            let newline = text.substring(with: lines[index].range).hasSuffix("\r\n") ? "\r\n" : "\n"
            let table = MarkdownTable(rows: rows, alignments: alignments, widths: widths, widthMarker: marker, newline: newline, original: text.substring(with: range))
            output.append(Located(range: range, table: table)); index = endIndex
        }
        return output
    }

    private static func startsBlock(_ line: String) -> Bool {
        line.range(of: #"^(?: {0,3}(?:#{1,6}(?:\s|$)|>|[-*+](?:\s|$)|\d+[.)] |`{3,}|~{3,}|<|\[[^]]+\]:)| {4}|\t)|^\s*(?:[-*_]\s*){3,}$"#, options: .regularExpression) != nil
    }

    static func splitRow(_ line: String) -> [String] {
        let line = line.trimmingCharacters(in: .whitespaces)
        var cells: [String] = [], cell = "", slashes = 0, endedWithPipe = false
        for character in line {
            if character == "|", slashes % 2 == 0 { cells.append(cell); cell = ""; endedWithPipe = true }
            else {
                if character == "|" { cell.removeLast() }
                cell.append(character); endedWithPipe = false
            }
            slashes = character == "\\" ? slashes + 1 : 0
        }
        cells.append(cell)
        if line.hasPrefix("|") { cells.removeFirst() }
        if endedWithPipe { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func escapePipes(_ value: String) -> String {
        var output = "", slashes = 0
        for character in value {
            if character == "|", slashes % 2 == 0 { output.append("\\") }
            output.append(character); slashes = character == "\\" ? slashes + 1 : 0
        }
        return output
    }

    private static func parseWidths(_ line: String) -> [Int]? {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard line.range(of: #"^<!--\s*zerus-table-widths:\s*[0-9]+(?:\s*,\s*[0-9]+)*\s*-->$"#, options: .regularExpression) != nil,
              let start = line.range(of: "zerus-table-widths:"), let end = line.range(of: "-->") else { return nil }
        let tokens = line[start.upperBound..<end.lowerBound].split(separator: ",")
        let widths = tokens.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return !widths.isEmpty && widths.count == tokens.count && widths.allSatisfy { (80...720).contains($0) } ? widths : nil
    }

    /// Spreadsheet values are plain text. Escape Markdown before writing GFM.
    static func spreadsheet(_ source: String) -> MarkdownTable? {
        guard source.contains("\t") else { return nil }
        let source = Array(source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false, index = 0
        func finishCell() {
            row.append(cell.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: #"([\\`*_\[\]<>~])"#, with: #"\\$1"#, options: .regularExpression)); cell = ""
        }
        while index < source.count {
            let character = source[index]
            if character == "\"" && (quoted || cell.isEmpty) {
                if quoted && index + 1 < source.count && source[index + 1] == "\"" { cell.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if !quoted && (character == "\t" || character == "\n") {
                finishCell()
                if character == "\n" { rows.append(row); row = [] }
            } else { cell.append(character) }
            index += 1
        }
        guard !quoted else { return nil }
        if !cell.isEmpty || !row.isEmpty || source.last != "\n" { finishCell(); rows.append(row) }
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0 else { return nil }
        rows = rows.map { $0 + Array(repeating: "", count: columns - $0.count) }
        return MarkdownTable(rows: rows)
    }
}
