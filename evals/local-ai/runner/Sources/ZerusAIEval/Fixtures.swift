import Foundation

typealias JSON = [String: Any]

struct Note {
    let id: String
    let raw: String
    let frontmatter: String  // YAML text without the --- fences ("" if none)
    let body: String
    var title: String {
        for line in frontmatter.split(separator: "\n") where line.hasPrefix("title:") {
            return line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return id
    }

    init(id: String, raw: String) {
        self.id = id
        self.raw = raw
        let (fm, body) = splitFrontmatter(raw)
        self.frontmatter = fm
        self.body = body
    }
}

func splitFrontmatter(_ raw: String) -> (String, String) {
    guard raw.hasPrefix("---\n") else { return ("", raw) }
    let rest = raw.dropFirst(4)
    guard let end = rest.range(of: "\n---\n") ?? rest.range(of: "\n---", options: .backwards)
    else { return ("", raw) }
    let fm = String(rest[rest.startIndex ..< end.lowerBound])
    var body = String(rest[end.upperBound...])
    if body.hasPrefix("\n") { body.removeFirst() }
    return (fm, body)
}

func joinFrontmatter(_ fm: String, _ body: String) -> String {
    fm.isEmpty ? body : "---\n\(fm)\n---\n\(body)"
}

struct Fixtures {
    let root: URL
    let notes: [String: Note]
    var orderedNotes: [Note] { notes.values.sorted { $0.id < $1.id } }

    init(root: URL) throws {
        self.root = root
        let dir = root.appendingPathComponent("fixtures/notes")
        var notes: [String: Note] = [:]
        for url in try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) where url.pathExtension == "md"
        {
            let id = url.deletingPathExtension().lastPathComponent
            notes[id] = Note(id: id, raw: try String(contentsOf: url, encoding: .utf8))
        }
        self.notes = notes
    }

    /// Optional cap on tasks per file (used by the iOS probe for quick runs).
    nonisolated(unsafe) static var taskLimit: Int?

    func tasks(_ name: String) throws -> [JSON] {
        let url = root.appendingPathComponent("tasks/\(name).jsonl")
        let all = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as! JSON
            }
        return Self.taskLimit.map { Array(all.prefix($0)) } ?? all
    }
}

// MARK: - Matching helpers

func normalize(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        .replacingOccurrences(of: "\u{00A0}", with: " ")
}

func containsNormalized(_ haystack: String, _ needle: String) -> Bool {
    let h = normalize(haystack), n = normalize(needle)
    if h.contains(n) { return true }
    // Tolerate spacing differences ("11 月 4 日" vs "11月4日", "1 350" vs "1350").
    let squash = { (s: String) in s.filter { !$0.isWhitespace } }
    return squash(h).contains(squash(n))
}

/// A `contains` spec element is either a string (must appear) or a list of
/// alternatives (any must appear). Returns the specs that failed.
func failedGroups(_ text: String, _ spec: Any?) -> [String] {
    guard let items = spec as? [Any] else { return [] }
    var failed: [String] = []
    for item in items {
        if let s = item as? String {
            if !containsNormalized(text, s) { failed.append(s) }
        } else if let alts = item as? [String], !alts.isEmpty {
            if !alts.contains(where: { containsNormalized(text, $0) }) {
                failed.append(alts.joined(separator: " | "))
            }
        }
    }
    return failed
}

func presentForbidden(_ text: String, _ spec: Any?) -> [String] {
    guard let items = spec as? [String] else { return [] }
    return items.filter { containsNormalized(text, $0) }
}

/// Word count that treats CJK scripts as ~2 characters per word.
func approxWordCount(_ s: String) -> Int {
    var words = 0
    var cjk = 0
    for token in s.split(whereSeparator: { $0.isWhitespace }) {
        let scalars = token.unicodeScalars
        let c = scalars.filter(isCJK).count
        if c > 0 {
            cjk += c
            if c < scalars.count { words += 1 }
        } else {
            words += 1
        }
    }
    return words + (cjk + 1) / 2
}

func isCJK(_ u: Unicode.Scalar) -> Bool {
    switch u.value {
    case 0x3040 ... 0x30FF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xAC00 ... 0xD7AF,
        0xF900 ... 0xFAFF:
        return true
    default: return false
    }
}
