import CryptoKit
import Foundation

/// A note as the local AI sees it: vault-relative path plus raw Markdown.
public struct LocalAINote: Sendable, Hashable {
    public let path: String
    public let content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }

    public var parts: (frontmatter: String, body: String) { MarkdownParts.split(content) }

    /// `title:` property, else the first `# ` heading, else the file name.
    public var title: String {
        let (frontmatter, body) = parts
        for line in frontmatter.split(separator: "\n") where line.hasPrefix("title:") {
            let value = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        for line in body.split(separator: "\n", omittingEmptySubsequences: true).prefix(5) where line.hasPrefix("# ") {
            return line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        }
        return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// SHA-256 of the content; the index re-embeds a note only when it changes.
    public var contentHash: String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum MarkdownParts {
    /// Splits YAML frontmatter (without the `---` fences) from the body.
    public static func split(_ raw: String) -> (frontmatter: String, body: String) {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard text.hasPrefix("---\n") else { return ("", text) }
        let rest = text.dropFirst(4)
        guard let end = rest.range(of: "\n---\n") ?? (rest.hasSuffix("\n---") ? rest.range(of: "\n---", options: .backwards) : nil)
        else { return ("", text) }
        let frontmatter = String(rest[rest.startIndex ..< end.lowerBound])
        var body = String(rest[end.upperBound...])
        if body.hasPrefix("\n") { body.removeFirst() }
        return (frontmatter, body)
    }
}

/// A searchable passage of a note.
public struct LocalAIChunk: Sendable, Hashable {
    public let path: String
    public let ordinal: Int
    public let title: String
    public let text: String

    public init(path: String, ordinal: Int, title: String, text: String) {
        self.path = path
        self.ordinal = ordinal
        self.title = title
        self.text = text
    }

    public var embeddingText: String { EmbeddingPrompt.document(title: title, text: text) }
}

public enum LocalAIChunker {
    /// Splits the body into heading sections, then packs paragraphs up to
    /// `maxCharacters`. The phase 1 retrieval results used 900.
    public static func chunks(for note: LocalAINote, maxCharacters: Int = 900) -> [LocalAIChunk] {
        let title = note.title
        let body = note.parts.body
        var sections: [String] = []
        var current = ""
        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("#"), !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append(current)
                current = ""
            }
            current += line + "\n"
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sections.append(current) }

        var texts: [String] = []
        for section in sections {
            var buffer = ""
            for paragraph in section.components(separatedBy: "\n\n") {
                if buffer.count + paragraph.count > maxCharacters, !buffer.isEmpty {
                    texts.append(buffer)
                    buffer = ""
                }
                if paragraph.count > maxCharacters {
                    var start = paragraph.startIndex
                    while start < paragraph.endIndex {
                        let end = paragraph.index(start, offsetBy: maxCharacters, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
                        texts.append(String(paragraph[start ..< end]))
                        start = end
                    }
                } else {
                    buffer += (buffer.isEmpty ? "" : "\n\n") + paragraph
                }
            }
            if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts.append(buffer) }
        }
        texts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if texts.isEmpty { texts = [title] }
        return texts.enumerated().map { LocalAIChunk(path: note.path, ordinal: $0.offset, title: title, text: $0.element) }
    }
}

// MARK: - Text normalisation

public enum LocalAIText {
    /// Case-, diacritic- and width-insensitive form used for matching.
    public static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    public static func isCJK(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x3040 ... 0x30FF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xAC00 ... 0xD7AF, 0xF900 ... 0xFAFF: true
        default: false
        }
    }

    /// Lowercased, diacritic-folded word tokens; CJK runs become bigrams.
    public static func tokens(_ s: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        var cjkRun: [Character] = []
        func flushWord() {
            if word.count > 1 || (word.count == 1 && word.first!.isNumber) { tokens.append(word) }
            word = ""
        }
        func flushCJK() {
            if cjkRun.count == 1 { tokens.append(String(cjkRun)) }
            if cjkRun.count > 1 { for i in 0 ..< cjkRun.count - 1 { tokens.append(String(cjkRun[i ... i + 1])) } }
            cjkRun = []
        }
        for ch in normalize(s) {
            if let u = ch.unicodeScalars.first, isCJK(u) {
                flushWord()
                cjkRun.append(ch)
            } else if ch.isLetter || ch.isNumber {
                flushCJK()
                word.append(ch)
            } else {
                flushWord()
                flushCJK()
            }
        }
        flushWord()
        flushCJK()
        return tokens
    }

    /// True when `needle` appears in `haystack` ignoring case, accents and
    /// whitespace differences ("11 月 4 日" vs "11月4日").
    public static func containsLoosely(_ haystack: String, _ needle: String) -> Bool {
        let h = normalize(haystack), n = normalize(needle)
        if h.contains(n) { return true }
        let squash = { (s: String) in s.filter { !$0.isWhitespace } }
        return squash(h).contains(squash(n))
    }
}

// MARK: - Keyword ranking

/// Okapi BM25 over chunk texts. Used while the embedding index builds and on
/// devices without semantic search.
public struct LocalAIBM25: Sendable {
    private let docs: [[String: Int]]
    private let lengths: [Int]
    private let df: [String: Int]
    private let averageLength: Double

    public init(_ texts: [String]) {
        var docs: [[String: Int]] = []
        var df: [String: Int] = [:]
        for text in texts {
            var tf: [String: Int] = [:]
            for token in LocalAIText.tokens(text) { tf[token, default: 0] += 1 }
            for key in tf.keys { df[key, default: 0] += 1 }
            docs.append(tf)
        }
        self.docs = docs
        self.df = df
        lengths = docs.map { $0.values.reduce(0, +) }
        averageLength = Double(lengths.reduce(0, +)) / Double(max(1, docs.count))
    }

    public func scores(_ query: String, k1: Double = 1.2, b: Double = 0.75) -> [Double] {
        let terms = Set(LocalAIText.tokens(query))
        let n = Double(docs.count)
        return docs.indices.map { i in
            var score = 0.0
            for term in terms {
                guard let f = docs[i][term] else { continue }
                let d = Double(df[term] ?? 0)
                let idf = Foundation.log(1 + (n - d + 0.5) / (d + 0.5))
                let tf = Double(f)
                score += idf * tf * (k1 + 1) / (tf + k1 * (1 - b + b * Double(lengths[i]) / averageLength))
            }
            return score
        }
    }
}
