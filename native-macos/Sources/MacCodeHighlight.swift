import AppKit

/// Colour is presentation only: no source characters, fonts, fence metadata or
/// semantic Markdown attributes are changed by this lexical pass.
enum MacCodeHighlight {
    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("ZerusCode" + name)) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }
    private static let comment = adaptive("Comment", light: 0x62686e, dark: 0xa2a8ae)
    private static let string = adaptive("String", light: 0x237943, dark: 0x8bd49b)
    private static let keyword = adaptive("Keyword", light: 0x8b23ad, dark: 0xd59bf6)
    private static let number = adaptive("Number", light: 0x9c5000, dark: 0xf2b46d)
    private static let extra = adaptive("Extra", light: 0x006db0, dark: 0x85c6ef)
    private struct Grammar {
        var comments: String
        var strings: String = #"\"(?:\\[\s\S]|[^\"\\])*\"|'(?:\\[\s\S]|[^'\\])*'"#
        var words: String = ""
        var extra: String = "(?!)"
        var insensitive = false
    }
    private static func grammar(_ name: String) -> Grammar? {
        let c = #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|\z)"#
        let triples = #"\"\"\"[\s\S]*?(?:\"\"\"|\z)|'''[\s\S]*?(?:'''|\z)|`(?:\\[\s\S]|[^`\\])*(?:`|\z)|\"(?:\\[\s\S]|[^\"\\\r\n])*(?:\"|(?=\r?\n)|\z)|'(?:\\[\s\S]|[^'\\\r\n])*(?:'|(?=\r?\n)|\z)"#
        switch name.lowercased() {
        case "swift": return .init(comments: c, strings: triples, words: "actor any as associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate final for func guard if import in init inout internal is let mutating nil nonisolated open operator override private protocol public repeat required rethrows return self Self some static struct subscript super switch throws throw true try typealias var weak where while", extra: #"\b[A-Z][\w]*\b|@[A-Za-z_]\w*"#)
        case "js", "javascript", "jsx", "ts", "typescript", "tsx": return .init(comments: c, strings: triples, words: "abstract as async await boolean break case catch class const constructor continue debugger declare default delete do else enum export extends false finally for from function get if implements import in instanceof interface let namespace never new null number of private protected public readonly return set static string super switch symbol this throw true try type typeof undefined unknown var void while with yield", extra: #"\b[A-Z][\w]*\b"#)
        case "java": return .init(comments: c, strings: triples, words: "abstract assert boolean break byte case catch char class const continue default do double else enum extends false final finally float for if implements import instanceof int interface long native new null package private protected public return short static strictfp super switch synchronized this throw throws transient true try void volatile while", extra: #"\b[A-Z][\w]*\b|@[A-Za-z_]\w*"#)
        case "rust", "rs": return .init(comments: c, strings: triples, words: "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while", extra: #"\b[A-Z][\w]*\b|\b\w+!"#)
        case "python", "py": return .init(comments: #"[#][^\r\n]*"#, strings: triples, words: "and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield", extra: #"@[A-Za-z_]\w*"#)
        case "bash", "sh", "shell", "zsh": return .init(comments: #"[#][^\r\n]*"#, strings: triples, words: "if then else elif fi case esac for select while until do done in function time export local readonly return exit source", extra: #"\$\{[^}]*\}|\$[A-Za-z_]\w*"#)
        case "json": return .init(comments: "(?!)", strings: #"\"(?:\\[\s\S]|[^\"\\])*(?:\"|\z)"#, words: "true false null")
        case "yaml", "yml": return .init(comments: #"[#][^\r\n]*"#, words: "true false null yes no on off", extra: #"(?m)^[ \t-]*[A-Za-z_][\w.-]*(?=\s*:)"#, insensitive: true)
        case "sql": return .init(comments: #"--[^\r\n]*|/\*[\s\S]*?(?:\*/|\z)"#, words: "select from where insert into values update set delete create alter drop table index view join inner left right outer full on as and or not null is in exists between like order by group having limit offset union all distinct asc desc case when then else end primary key references default true false begin commit rollback", insensitive: true)
        case "css": return .init(comments: #"/\*[\s\S]*?(?:\*/|\z)"#, words: "important inherit initial unset revert", extra: #"[A-Za-z-]+(?=\s*:)|[.#][A-Za-z_][\w-]*"#)
        case "html", "xml": return .init(comments: #"<!--[\s\S]*?(?:-->|\z)"#, words: "", extra: #"</?[A-Za-z][\w:.-]*|/?>|[A-Za-z_:][\w:.-]*(?=\s*=)"#)
        case "markdown", "md": return .init(comments: #"<!--[\s\S]*?(?:-->|\z)"#, strings: #"`[^`\r\n]+`"#, extra: #"(?m)^#{1,6}[ \t]+[^\r\n]*|\[[^\]\r\n]*\]\([^\)\r\n]*\)"#)
        default: return nil
        }
    }
    static func apply(_ text: NSMutableAttributedString, range: NSRange, language: String) {
        text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        guard range.length <= 100_000, let grammar = grammar(language) else { return }
        let words = grammar.words.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "|")
        let keyword = words.isEmpty ? "(?!)" : "\\b(?:" + words + ")\\b"
        let pattern = "(?<comment>" + grammar.comments + ")|(?<string>" + grammar.strings + ")|(?<keyword>" + keyword + ")|(?<number>\\b(?:0[xX][0-9a-fA-F]+|[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\\b)|(?<extra>" + grammar.extra + ")"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: grammar.insensitive ? [.caseInsensitive] : []) else { return }
        // Match an isolated substring: unterminated tokens never consume prose
        // or a neighbouring code block outside this attributed code range.
        let body = (text.string as NSString).substring(with: range)
        expression.enumerateMatches(in: body, range: NSRange(location: 0, length: (body as NSString).length)) { match, _, _ in
            guard let match else { return }
            let categories: [(String, NSColor)] = [("comment", comment), ("string", string), ("keyword", self.keyword), ("number", number), ("extra", extra)]
            for (name, colour) in categories {
                let token = match.range(withName: name)
                if token.location != NSNotFound { text.addAttribute(.foregroundColor, value: colour, range: NSRange(location: range.location + token.location, length: token.length)); break }
            }
        }
    }
}
