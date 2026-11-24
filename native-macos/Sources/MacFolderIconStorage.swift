import Foundation

/// Keep top-level keys and unrelated JSON tokens verbatim. Swift dictionaries
/// merge Unicode-equivalent keys; JSONSerialization also trims leading FEFF in
/// string values. It validates the grammar here but never supplies saved values.
private struct MacFolderIconDocument: Sendable {
    struct Entry: Sendable { let key: Data; let start: Int; let valueRange: Range<Int>; let string: String? }
    let original: Data?
    let bytes: Data
    let entries: [Entry]
    let close: Int
    init(_ original: Data?) throws {
        let data = original ?? Data("{}".utf8)
        guard try JSONSerialization.jsonObject(with: data) is NSDictionary else { throw VaultFailure(message: "The icon file has an unsupported format.") }
        let raw = Array(data), decoder = JSONDecoder()
        var index = raw.starts(with: [239,187,191]) ? 3 : 0
        func whitespace() { while index < raw.count && [9,10,13,32].contains(raw[index]) { index += 1 } }
        func stringEnd(_ start: Int) throws -> Int {
            var end = start + 1
            while end < raw.count {
                if raw[end] == 34 { return end + 1 }
                end += raw[end] == 92 ? 2 : 1
            }
            throw VaultFailure(message: "The icon file has an unsupported format.")
        }
        whitespace()
        guard index < raw.count, raw[index] == 123 else { throw VaultFailure(message: "The icon file has an unsupported format.") }
        index += 1; whitespace()
        var values: [Entry] = []
        while index < raw.count && raw[index] != 125 {
            let start = index, keyEnd = try stringEnd(index)
            let key = try decoder.decode(String.self, from: data.subdata(in: index..<keyEnd))
            index = keyEnd; whitespace()
            guard index < raw.count, raw[index] == 58 else { throw VaultFailure(message: "The icon file has an unsupported format.") }
            index += 1; whitespace(); let valueStart = index
            guard index < raw.count else { throw VaultFailure(message: "The icon file has an unsupported format.") }
            let string: String?
            if raw[index] == 34 {
                index = try stringEnd(index)
                string = try decoder.decode(String.self, from: data.subdata(in: valueStart..<index))
            } else {
                string = nil
                if raw[index] == 123 || raw[index] == 91 {
                    var depth = 0
                    repeat {
                        guard index < raw.count else { throw VaultFailure(message: "The icon file has an unsupported format.") }
                        if raw[index] == 34 { index = try stringEnd(index); continue }
                        if raw[index] == 123 || raw[index] == 91 { depth += 1 }
                        else if raw[index] == 125 || raw[index] == 93 { depth -= 1 }
                        index += 1
                    } while depth > 0
                } else { while index < raw.count && ![9,10,13,32,44,125].contains(raw[index]) { index += 1 } }
            }
            values.append(.init(key: Data(key.utf8), start: start, valueRange: valueStart..<index, string: string))
            whitespace()
            guard index < raw.count else { throw VaultFailure(message: "The icon file has an unsupported format.") }
            if raw[index] == 44 { index += 1; whitespace() }
            else if raw[index] != 125 { throw VaultFailure(message: "The icon file has an unsupported format.") }
        }
        self.original = original; bytes = data; entries = values; close = index
    }
    func setting(_ folder: String, to value: String?) throws -> Data? {
        let key = Data(folder.utf8), matches = entries.indices.filter { entries[$0].key == key }
        guard matches.count <= 1 else { throw VaultFailure(message: "This folder’s icon key is duplicated. Its original file is preserved.") }
        var output = bytes
        let encoder = JSONEncoder()
        if let index = matches.first {
            let entry = entries[index]
            guard let previous = entry.string else { throw VaultFailure(message: "This folder’s icon uses an unsupported format. Its original value is preserved.") }
            if let value {
                if previous.utf8.elementsEqual(value.utf8) { return original }
                output.replaceSubrange(entry.valueRange, with: try encoder.encode(value))
            } else {
                let range: Range<Int>
                if index + 1 < entries.count { range = entry.start..<entries[index + 1].start }
                else if index > 0 { range = entries[index - 1].valueRange.upperBound..<entry.valueRange.upperBound }
                else { range = entry.start..<entry.valueRange.upperBound }
                output.removeSubrange(range)
            }
        } else if let value {
            let raw = Array(bytes), ending: String
            if let newline = raw.firstIndex(of: 10), newline > 0, raw[newline - 1] == 13 { ending = "\r\n" } else { ending = "\n" }
            let name = String(decoding: try encoder.encode(folder), as: UTF8.self)
            let text = String(decoding: try encoder.encode(value), as: UTF8.self)
            let insertion = entries.isEmpty ? "\(name): \(text)" : ",\(ending)  \(name): \(text)"
            let position = entries.last?.valueRange.upperBound ?? close
            output.insert(contentsOf: insertion.utf8, at: position)
        } else { return original }
        return output
    }
}
struct MacFolderIconSnapshot: Sendable {
    let root: URL
    let bytes: Data?
    let icons: [Data: String]
    var workspaceID: UUID?
    fileprivate let document: MacFolderIconDocument
    init(root: URL, bytes: Data?, workspaceID: UUID? = nil) throws {
        self.root = root; self.bytes = bytes; self.workspaceID = workspaceID
        document = try MacFolderIconDocument(bytes)
        var values: [Data: String] = [:]
        for entry in document.entries { if let value = entry.string { values[entry.key] = value } }
        icons = values
    }
    func icon(_ folder: String) -> String? { icons[Data(folder.utf8)] }
}
extension VaultFiles {
    func macFolderIconSnapshot() throws -> MacFolderIconSnapshot {
        let location = try url(for: ".zerus/type-icons.json")
        let bytes = FileManager.default.fileExists(atPath: location.path) ? try read(".zerus/type-icons.json") : nil
        return try .init(root: root, bytes: bytes)
    }
    /// Suggest in one metadata transaction, preserving any override written by
    /// another client before this step. The primary move/copy is already saved.
    func macSuggestFolderIcons(_ suggestions: [(String, String)], previousFolders: [String]) throws -> VaultSnapshot {
        let current = try scan(), existing = Set(previousFolders.map { Data($0.utf8) }), available = Set(current.folders.map { Data($0.utf8) })
        let original = try macFolderIconSnapshot(); var after = original.bytes
        for (folder, icon) in suggestions where !existing.contains(Data(folder.utf8)) && available.contains(Data(folder.utf8)) {
            try NativePropertyDefinition.validateOwner(folder)
            let document = try MacFolderIconDocument(after)
            // Unknown existing values are overrides too, never an invitation to
            // replace a newer client's setting with an automatic suggestion.
            guard !document.entries.contains(where: { $0.key == Data(folder.utf8) }) else { continue }
            after = try document.setting(folder, to: icon)
        }
        if original.bytes != after { try applyTransaction([.init(path: ".zerus/type-icons.json", before: original.bytes, after: after)]) }
        return try scan()
    }
    func macSetFolderIcon(_ snapshot: MacFolderIconSnapshot, folder: String, value: String?) throws -> VaultSnapshot {
        guard snapshot.root == root else { throw VaultFailure(message: "The vault changed. Reopen the icon picker.") }
        try NativePropertyDefinition.validateOwner(folder)
        let current = try scan()
        guard current.folders.contains(where: { $0.utf8.elementsEqual(folder.utf8) }) || current.notes.contains(where: { $0.regularCollectionNote && $0.folder.utf8.elementsEqual(folder.utf8) }) else { throw VaultFailure(message: "This folder is no longer available.") }
        if let value {
            let tabler = value.hasPrefix("tabler:") && value.dropFirst(7).range(of: #"^[A-Za-z][A-Za-z0-9]*$"#, options: .regularExpression) != nil
            let emoji = value.count == 1 && value.unicodeScalars.contains(where: { !$0.isASCII })
            guard value.utf8.count <= 128, tabler || emoji else { throw VaultFailure(message: "Choose an icon or enter one emoji.") }
        }
        let after = try snapshot.document.setting(folder, to: value)
        try applyTransaction([.init(path: ".zerus/type-icons.json", before: snapshot.bytes, after: after)])
        return try scan()
    }
}
