import Foundation

enum NativePropertyValue: Equatable, Sendable, Codable {
    case text(String), number(String), checkbox(Bool), list([String])
    var display: String {
        switch self {
        case .text(let value), .number(let value): return value
        case .checkbox(let value): return value ? "true" : "false"
        case .list(let values): return values.joined(separator: ", ")
        }
    }
    var selections: [String] {
        if case .list(let values) = self { return values }
        return display.isEmpty ? [] : [display]
    }
    var yaml: String {
        switch self {
        case .text(let value): return Self.quote(value)
        case .number(let value): return value
        case .checkbox(let value): return value ? "true" : "false"
        case .list(let values): return "[" + values.map(Self.quote).joined(separator: ", ") + "]"
        }
    }
    private static func quote(_ text: String) -> String {
        // JSON strings are also YAML double-quoted strings.
        String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
    }
}

/// Tracks original ranges rather than serializing an entire foreign YAML header.
/// Unsupported values, duplicate keys, comments, ordering, body bytes and line
/// endings survive edits to other fields.
struct NativeFrontmatter {
    private static let keyPattern = try! NSRegularExpression(pattern: #"^([A-Za-z0-9_][A-Za-z0-9_ .-]*?)\s*:\s?(.*)$"#)
    struct Entry: Identifiable {
        let key: String
        var value: NativePropertyValue?
        let range: NSRange
        let comment: String
        var id: String { key.lowercased() }
    }
    let content: String
    let headerLength: Int
    let closingOffset: Int
    let newline: String
    private(set) var entries: [Entry] = []
    var header: String { (content as NSString).substring(to: headerLength) }
    var body: String { (content as NSString).substring(from: headerLength) }

    init(_ content: String) {
        self.content = content
        newline = content.hasPrefix("---\r\n") ? "\r\n" : "\n"
        let text = content as NSString
        let opening = "---" + newline
        guard content.hasPrefix(opening) else { headerLength = 0; closingOffset = 0; return }
        var lines: [(String, NSRange)] = [], offset = (opening as NSString).length
        var closing: NSRange?
        while offset < text.length {
            let end = text.range(of: "\n", range: NSRange(location: offset, length: text.length - offset))
            let length = end.location == NSNotFound ? text.length - offset : end.location + 1 - offset
            let range = NSRange(location: offset, length: length)
            let raw = text.substring(with: range).trimmingCharacters(in: .newlines)
            if ["---", "..."].contains(raw.trimmingCharacters(in: .whitespaces)) && !raw.hasPrefix(" ") && !raw.hasPrefix("\t") { closing = range; break }
            lines.append((raw, range)); offset += length
        }
        guard let closing else { headerLength = 0; closingOffset = 0; return }
        closingOffset = closing.location; headerLength = NSMaxRange(closing)
        var index = 0
        while index < lines.count {
            let (line, range) = lines[index]
            guard let match = Self.keyPattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { index += 1; continue }
            let key = (line as NSString).substring(with: match.range(at: 1))
            let raw = (line as NSString).substring(with: match.range(at: 2))
            let (scalar, comment) = Self.stripComment(raw)
            var next = index + 1
            // Indented continuation belongs to this value. Never leave orphaned
            // children behind when replacing a block list or nested mapping.
            while next < lines.count {
                let candidate = lines[next].0
                if candidate.hasPrefix(" ") || candidate.hasPrefix("\t") || candidate.hasPrefix("- ") { next += 1; continue }
                if candidate.isEmpty || candidate.hasPrefix("#") {
                    var lookahead = next + 1
                    while lookahead < lines.count && (lines[lookahead].0.isEmpty || lines[lookahead].0.hasPrefix("#")) { lookahead += 1 }
                    if lookahead < lines.count && (lines[lookahead].0.hasPrefix(" ") || lines[lookahead].0.hasPrefix("\t") || lines[lookahead].0.hasPrefix("- ")) { next = lookahead + 1; continue }
                }
                break
            }
            var value: NativePropertyValue?
            if next > index + 1 {
                if scalar.isEmpty {
                    var values: [String] = [], valid = true, indentation: Int?
                    for child in lines[(index + 1)..<next] {
                        let item = child.0.trimmingCharacters(in: .whitespaces)
                        let leading = child.0.prefix(while: { $0 == " " }).count
                        if let indentation, indentation != leading { valid = false; break }
                        indentation = leading
                        guard item.hasPrefix("- "), let parsed = Self.scalar(String(item.dropFirst(2))) else { valid = false; break }
                        values.append(parsed.display)
                    }
                    if valid { value = .list(values) }
                }
            } else { value = Self.value(scalar) }
            entries.append(Entry(key: key, value: value, range: NSRange(location: range.location, length: NSMaxRange(lines[next - 1].1) - range.location), comment: comment))
            index = next
        }
        let duplicates = Dictionary(grouping: entries, by: { $0.key.lowercased() }).filter { $0.value.count > 1 }
        for i in entries.indices where duplicates[entries[i].id] != nil { entries[i].value = nil }
    }

    func entry(_ key: String) -> Entry? { entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame } }

    func setting(_ key: String, value: NativePropertyValue?) throws -> String {
        guard key.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_ .-]{0,59}$"#, options: .regularExpression) != nil else {
            throw VaultFailure(message: "Use a property name of up to 60 letters, numbers, spaces, dots, hyphens or underscores.")
        }
        if case .number(let number) = value {
            guard number.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil, Double(number)?.isFinite == true else { throw VaultFailure(message: "Enter a valid finite number, using a dot for decimals.") }
        }
        if let existing = entry(key) {
            guard existing.value != nil else { throw VaultFailure(message: "This field uses complex or duplicate YAML. Its original contents are preserved; edit it with your desktop YAML editor.") }
            if existing.value == value { return content }
            let replacement = value.map { existing.key + ": " + $0.yaml + existing.comment + newline } ?? (existing.comment.isEmpty ? "" : existing.comment.trimmingCharacters(in: .whitespaces) + newline)
            return (content as NSString).replacingCharacters(in: existing.range, with: replacement)
        }
        guard let value else { return content }
        let line = key + ": " + value.yaml + newline
        if headerLength == 0 { return "---" + newline + line + "---" + newline + content }
        return (content as NSString).replacingCharacters(in: NSRange(location: closingOffset, length: 0), with: line)
    }

    func renaming(_ key: String, to name: String) throws -> String {
        guard let entry = entry(key) else { return content }
        guard entries.filter({ $0.id == entry.id }).count == 1 else { throw VaultFailure(message: "The property \(key) has duplicate YAML keys and cannot be renamed safely.") }
        if let target = self.entry(name), target.range != entry.range { throw VaultFailure(message: "The note already has a separate \(name) value. Rename it before changing this definition.") }
        return (content as NSString).replacingCharacters(in: NSRange(location: entry.range.location, length: (entry.key as NSString).length), with: name)
    }

    private static func stripComment(_ text: String) -> (String, String) {
        var quote: Character?, escaped = false, previous: Character?, startsToken = true
        for index in text.indices {
            let char = text[index]
            if escaped { escaped = false; previous = char; continue }
            if char == "\\", quote == "\"" { escaped = true }
            else if let current = quote, char == current {
                let next = text.index(after: index)
                if current == "'", next < text.endIndex, text[next] == "'" { escaped = true }
                else { quote = nil; startsToken = false }
            }
            else if quote != nil { /* Keep literal punctuation inside a quoted value. */ }
            else if (char == "\"" || char == "'"), startsToken { quote = char }
            else if char == "#", previous == nil || previous!.isWhitespace {
                return (String(text[..<index]).trimmingCharacters(in: .whitespaces), " " + String(text[index...]))
            }
            else if char == "[" || char == "," { startsToken = true }
            else if !char.isWhitespace { startsToken = false }
            previous = char
        }
        return (text.trimmingCharacters(in: .whitespaces), "")
    }
    private static func value(_ text: String) -> NativePropertyValue? {
        if text.hasPrefix("[") {
            guard text.hasSuffix("]") else { return nil }
            let inner = String(text.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespaces).isEmpty { return .list([]) }
            var values: [String] = [], token = "", quote: Character?, escaped = false
            for index in inner.indices {
                let char = inner[index]
                if escaped { token.append(char); escaped = false; continue }
                if char == "\\", quote == "\"" { token.append(char); escaped = true; continue }
                if let current = quote {
                    token.append(char)
                    if char == current {
                        let next = inner.index(after: index)
                        if current == "'", next < inner.endIndex, inner[next] == "'" { escaped = true }
                        else { quote = nil }
                    }
                    continue
                }
                if (char == "\"" || char == "'"), token.trimmingCharacters(in: .whitespaces).isEmpty { quote = char; token.append(char) }
                else if char == "," { guard let item = scalar(token) else { return nil }; values.append(item.display); token = "" }
                else { token.append(char) }
            }
            guard quote == nil, let item = scalar(token) else { return nil }
            values.append(item.display); return .list(values)
        }
        return scalar(text)
    }
    private static func scalar(_ raw: String) -> NativePropertyValue? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\"") {
            guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(String.self, from: data) else { return nil }
            return .text(value)
        }
        if text.hasPrefix("'") {
            guard text.count >= 2, text.hasSuffix("'") else { return nil }
            let inner = String(text.dropFirst().dropLast())
            guard !inner.replacingOccurrences(of: "''", with: "").contains("'") else { return nil }
            return .text(inner.replacingOccurrences(of: "''", with: "'"))
        }
        if ["true", "false"].contains(text.lowercased()) { return .checkbox(text.lowercased() == "true") }
        if text.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil { return .number(text) }
        if text.range(of: #"^(?:[&*!|>{}\[\]@`]|null$|~$)|:\s"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        return .text(text)
    }
}

enum NativePropertyType: String, CaseIterable, Identifiable, Sendable {
    case text, url, number, date, checkbox, list, relation, unsupported
    var id: String { rawValue }
    var label: String { self == .url ? "URL" : rawValue.capitalized }
    static func inferred(_ value: NativePropertyValue?) -> Self {
        switch value {
        case .number: return .number
        case .checkbox: return .checkbox
        case .list: return .list
        case .text(let text) where text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil: return .date
        default: return .text
        }
    }
}

struct NativePropertyDefinition: Identifiable, Sendable {
    let name: String
    let type: NativePropertyType
    var owner: String = ""
    var options: [String] = []
    var multiple = false
    var hidden = false
    var relationTypeKey: String? = nil
    var relationMultiple = false
    var relationPairID: String? = nil
    var relationInverseHidden = false
    var id: String { name.lowercased() }
    static func effective(path: String, data: Data?) throws -> [Self] {
        guard let data else { return [] }
        guard let schemas = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw VaultFailure(message: "The property definitions are not a valid JSON object.") }
        let logical = path.hasPrefix(".trash/") ? String(path.dropFirst(7)) : path
        let parts = logical.split(separator: "/").dropLast().prefix(8).map(String.init)
        let owners = parts.isEmpty ? [""] : (1...parts.count).map { parts.prefix($0).joined(separator: "/") }
        var result: [Self] = []
        for owner in owners {
            guard let raw = schemas[owner] else { continue }
            guard let definitions = raw as? [[String: Any]] else { throw VaultFailure(message: "The property definitions for \(owner.isEmpty ? "Inbox" : owner) are invalid.") }
            for definition in definitions {
                let value = try Self.decoded(definition, owner: owner)
                if let index = result.firstIndex(where: { $0.id == value.id }) { result[index] = value } else { result.append(value) }
            }
        }
        return result
    }
}

extension VaultFiles {
    func propertyDefinitions(notePath: String) throws -> [NativePropertyDefinition] {
        let url = try url(for: ".zerus/properties.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try NativePropertyDefinition.effective(path: notePath, data: read(".zerus/properties.json"))
    }
}

extension NativePropertyDefinition {
    func validateValue(_ value: NativePropertyValue?) throws {
        guard !hidden && type != .unsupported else { throw VaultFailure(message: "This property is hidden or unsupported.") }
        guard let value else { return }
        switch (type, value) {
        case (.checkbox, .checkbox): break
        case (.number, .number(let text)):
            guard let number = Double(text), number.isFinite else { throw VaultFailure(message: "Enter a finite number.") }
        case (.date, .text(let text)):
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard NativeCollectionPropertyFilter.isDate(text), formatter.date(from: text) != nil else { throw VaultFailure(message: "Choose a valid date.") }
        case (.url, .text(let text)):
            guard text.isEmpty || URL(string: text)?.scheme != nil else { throw VaultFailure(message: "Enter a complete URL including its scheme.") }
        case (.text, .text), (.relation, .text), (.relation, .list): break
        case (.list, .text), (.list, .list):
            guard multiple || value.selections.count <= 1 else { throw VaultFailure(message: "This list accepts one value.") }
            guard value.selections.allSatisfy({ item in options.contains { $0.caseInsensitiveCompare(item) == .orderedSame } }) else { throw VaultFailure(message: "A selected list choice is not available on this note.") }
        default: throw VaultFailure(message: "The value does not match this property’s type.")
        }
    }
}
