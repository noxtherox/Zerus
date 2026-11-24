import Foundation

/// JSON tokens, rather than Swift string-keyed dictionaries, own shared folder
/// metadata. Unicode-equivalent keys and unknown value spellings stay distinct.
struct MacFolderMetadata {
    struct Member { let key: String; let keyRange: Range<Int>; let value: Node }
    indirect enum Kind { case object([Member]), array([Node]), string(String), scalar(String) }
    struct Node { let range: Range<Int>; let kind: Kind }
    let bytes: Data
    let members: [Member]
    let close: Int
    init(_ bytes: Data) throws {
        let raw = Array(bytes); var i = raw.starts(with: [239,187,191]) ? 3 : 0
        func fail() -> VaultFailure { .init(message: "Folder settings use an unsupported format. Their original file is preserved.") }
        func space() { while i < raw.count && [9,10,13,32].contains(raw[i]) { i += 1 } }
        func string() throws -> (String, Range<Int>) {
            let start = i; guard i < raw.count, raw[i] == 34 else { throw fail() }; i += 1
            while i < raw.count {
                if raw[i] == 34 { i += 1; let r = start..<i; return (try JSONDecoder().decode(String.self, from: bytes.subdata(in: r)), r) }
                i += raw[i] == 92 ? 2 : 1
            }
            throw fail()
        }
        func node(_ depth: Int) throws -> Node {
            guard depth < 64 else { throw fail() }; space(); let start = i
            guard i < raw.count else { throw fail() }
            if raw[i] == 34 { let (s,r) = try string(); return Node(range: r, kind: .string(s)) }
            if raw[i] == 123 {
                i += 1; space(); var entries: [Member] = []
                while i < raw.count && raw[i] != 125 {
                    let (key,r) = try string(); space(); guard i < raw.count, raw[i] == 58 else { throw fail() }; i += 1
                    entries.append(Member(key: key, keyRange: r, value: try node(depth + 1))); space()
                    if i < raw.count && raw[i] == 44 { i += 1; space(); guard i < raw.count, raw[i] != 125 else { throw fail() } }
                    else { break }
                }
                guard i < raw.count, raw[i] == 125 else { throw fail() }; i += 1
                return Node(range: start..<i, kind: .object(entries))
            }
            if raw[i] == 91 {
                i += 1; space(); var entries: [Node] = []
                while i < raw.count && raw[i] != 93 {
                    entries.append(try node(depth + 1)); space()
                    if i < raw.count && raw[i] == 44 { i += 1; space(); guard i < raw.count, raw[i] != 93 else { throw fail() } }
                    else { break }
                }
                guard i < raw.count, raw[i] == 93 else { throw fail() }; i += 1
                return Node(range: start..<i, kind: .array(entries))
            }
            while i < raw.count && ![9,10,13,32,44,125,93].contains(raw[i]) { i += 1 }
            let token = bytes.subdata(in: start..<i)
            _ = try JSONSerialization.jsonObject(with: token, options: [.fragmentsAllowed])
            return Node(range: start..<i, kind: .scalar(String(decoding: token, as: UTF8.self)))
        }
        let root = try node(0); space()
        guard i == raw.count, case .object(let entries) = root.kind else { throw fail() }
        self.bytes = bytes; members = entries; close = root.range.upperBound - 1
    }
    static func same(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    static func owns(_ key: String, _ folder: String) -> Bool { same(key, folder) || key.utf8.starts(with: (folder + "/").utf8) }
    static func equal(_ a: Node, _ b: Node) -> Bool {
        switch (a.kind, b.kind) {
        case (.string(let x), .string(let y)): return same(x,y)
        case (.scalar(let x), .scalar(let y)):
            if x == y { return true }
            // Compare decimal spelling without a floating-point/Decimal round trip:
            // receipt validation must not equate different large foreign numbers.
            return number(x).map { $0 == number(y) } ?? false
        case (.array(let x), .array(let y)): return x.count == y.count && zip(x,y).allSatisfy { equal($0,$1) }
        case (.object(let x), .object(let y)):
            guard x.count == y.count else { return false }; var remaining = y
            for member in x {
                guard let index = remaining.firstIndex(where: { same($0.key, member.key) }), equal(member.value, remaining[index].value) else { return false }
                remaining.remove(at: index)
            }
            return true
        default: return false
        }
    }
    private static func number(_ token: String) -> String? {
        guard token.first == "-" || token.first?.isNumber == true else { return nil }
        var text = token.lowercased(), negative = false
        if text.first == "-" { negative = true; text.removeFirst() }
        let parts = text.split(separator: "e", omittingEmptySubsequences: false)
        guard parts.count <= 2, let exponent = parts.count == 2 ? Int(parts[1]) : 0 else { return nil }
        let mantissa = String(parts[0]), fraction = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        var digits = mantissa.filter { $0 != "." }
        while digits.first == "0" { digits.removeFirst() }
        if digits.isEmpty { return "0" }
        let (initial, overflow) = exponent.subtractingReportingOverflow(fraction.count == 2 ? fraction[1].count : 0)
        guard !overflow else { return nil }; var scale = initial
        while digits.last == "0" {
            let (next, overflow) = scale.addingReportingOverflow(1); guard !overflow else { return nil }
            digits.removeLast(); scale = next
        }
        return (negative ? "-" : "") + digits + "e" + String(scale)
    }
    func equivalent(to other: MacFolderMetadata) -> Bool {
        Self.equal(Node(range: 0..<0, kind: .object(members)), Node(range: 0..<0, kind: .object(other.members)))
    }
    func removing(_ folder: String) -> Data {
        var result = bytes
        // Remove contiguous groups so their commas cannot overlap.
        var groups: [Range<Int>] = []; var start: Int?
        for index in 0...members.count {
            if index < members.count && Self.owns(members[index].key, folder) { if start == nil { start = index } }
            else if let first = start { groups.append(first..<index); start = nil }
        }
        for group in groups.reversed() {
            let end = group.upperBound
            let range: Range<Int>
            if end < members.count { range = members[group.lowerBound].keyRange.lowerBound..<members[end].keyRange.lowerBound }
            else if group.lowerBound > 0 { range = members[group.lowerBound - 1].value.range.upperBound..<members[end - 1].value.range.upperBound }
            else { range = members[0].keyRange.lowerBound..<members[end - 1].value.range.upperBound }
            result.removeSubrange(range)
        }
        return result
    }
    func renaming(_ source: String, to destination: String, relations: Bool) throws -> Data {
        func mapped(_ key: String) -> String { Self.owns(key,source) ? destination + String(decoding: key.utf8.dropFirst(source.utf8.count), as: UTF8.self) : key }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        var edits: [(Range<Int>,Data)] = []
        for member in members {
            let next = mapped(member.key)
            if !Self.same(next, member.key) {
                guard !members.contains(where: { !Self.owns($0.key,source) && $0.key.caseInsensitiveCompare(next) == .orderedSame }) else { throw VaultFailure(message: "Folder metadata already exists at \(next). Resolve the collision before renaming.") }
                edits.append((member.keyRange, try encoder.encode(next)))
            }
            if relations, case .array(let definitions) = member.value.kind {
                for definition in definitions {
                    guard case .object(let fields) = definition.kind,
                          fields.contains(where: { field in
                              guard Self.same(field.key,"type"), case .string(let value) = field.value.kind else { return false }; return value == "relation"
                          }) else { continue }
                    for field in fields where Self.same(field.key,"relationTypeKey") {
                        if case .string(let target) = field.value.kind, !Self.same(target,mapped(target)) { edits.append((field.value.range, try encoder.encode(mapped(target)))) }
                    }
                }
            }
        }
        var output = bytes
        for (range,value) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) { output.replaceSubrange(range, with: value) }
        return output
    }
    func restoring(from original: MacFolderMetadata, folder: String) throws -> Data {
        var additions: [Data] = []
        for member in original.members where Self.owns(member.key,folder) {
            let current = members.filter { Self.same($0.key,member.key) }
            guard current.count <= 1, current.first.map({ Self.equal($0.value,member.value) }) ?? true else { throw VaultFailure(message: "Folder settings already exist for \(member.key). Review them in Files before restoring; current settings are preserved.") }
            if current.isEmpty { additions.append(original.bytes.subdata(in: member.keyRange.lowerBound..<member.value.range.upperBound)) }
        }
        var output = bytes; var insertion = Data()
        for (index, addition) in additions.enumerated() { if !members.isEmpty || index > 0 { insertion.append(44) }; insertion.append(addition) }
        output.insert(contentsOf: insertion, at: members.last?.value.range.upperBound ?? close)
        return output
    }
    var requiresNewReceipt: Bool {
        guard let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let encoded = try? JSONSerialization.data(withJSONObject: value), let roundTrip = try? MacFolderMetadata(encoded) else { return true }
        return !equivalent(to: roundTrip)
    }
}
