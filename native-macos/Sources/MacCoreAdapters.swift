import Foundation
import CryptoKit
import Markdown

struct NativeClipboardFragment: Codable, Sendable {
    struct Resource: Codable, Sendable {
        let reference: String
        let path: String?
        let name: String
        let bytes: Data?
    }
    static let type = "com.zerus.notes.markdown-fragment"
    static let limit = 50 * 1024 * 1024
    let version: Int
    let markdown: String
    let vault: String?
    let resources: [Resource]

    init(markdown: String, vault: String? = nil, resources: [Resource] = []) {
        version = 1; self.markdown = markdown; self.vault = vault; self.resources = resources
    }
    var includesLocalResources: Bool {
        Set(MarkdownResources.localReferences(in: markdown)).isSubset(of: Set(resources.map(\.reference))) &&
        Set(resources.map(\.reference)).isSubset(of: Set(MarkdownResources.localReferences(in: markdown, includeNoteFiles: true))) && resources.allSatisfy { $0.bytes != nil }
    }
    func validate() throws {
        guard version == 1, markdown.utf8.count <= Self.limit, resources.count <= 1000,
              resources.reduce(markdown.utf8.count, { $0 + ($1.bytes?.count ?? 0) }) <= Self.limit,
              Set(resources.map(\.reference)).count == resources.count else {
            throw VaultFailure(message: "This clipboard selection is too large or uses an unsupported format.")
        }
        let actual = Set(MarkdownResources.localReferences(in: markdown, includeNoteFiles: true))
        guard resources.allSatisfy({ actual.contains($0.reference) }) else { throw VaultFailure(message: "The clipboard attachment references are invalid.") }
    }
    static func decode(_ data: Data) throws -> NativeClipboardFragment {
        guard data.count <= limit * 3 / 2 else { throw VaultFailure(message: "This clipboard selection is too large.") }
        let fragment = try JSONDecoder().decode(Self.self, from: data)
        try fragment.validate(); return fragment
    }
    static func vaultID(_ root: URL) -> String {
        SHA256.hash(data: Data(root.standardizedFileURL.resolvingSymlinksInPath().path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct NativeDriveFolder: Codable, Equatable, Sendable {
    let accountID: String
    let email: String
    let folderID: String
    let name: String
    func validated() throws -> Self {
        guard !accountID.isEmpty, !folderID.isEmpty, !email.isEmpty, !name.isEmpty,
              email.utf8.count <= 1024, name.utf8.count <= 4096 else { throw VaultFailure(message: "This saved Google Drive folder is unreadable. Choose it again.") }
        return self
    }
}


// Shared file-location records can reference Drive IDs even when resolved through Finder.
enum NativeDriveFiles {
    static let downloadLimit = 50 * 1024 * 1024
    static func validID(_ value: String) -> Bool { value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil }
}

enum MarkdownText {
    private static let literalBlockStart = try! NSRegularExpression(pattern: #"^ {0,3}(?:#{1,6}(?=[ \t]|$)|>|\||[-+](?=[ \t]|$)|[-=]+[ \t]*$|\d{1,9}([.)])(?=[ \t]|$))"#)
    private static let literalTableDelimiter = try! NSRegularExpression(pattern: #"^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*$"#)
    static func escapeLiteralBlockStart(_ value: String) -> String {
        // ASCII letters cannot begin either Markdown block-marker pattern.
        // Leave ordinary prose unchanged without trimming/scanning the line.
        if let first = value.utf8.first,
           (65...90).contains(first) || (97...122).contains(first) { return value }
        let content = value.trimmingCharacters(in: .newlines)
        let spaces = content.prefix(while: { $0 == " " }).count
        guard spaces <= 3, let first = content.dropFirst(spaces).first else { return value }
        let text = content as NSString, range = NSRange(location: 0, length: text.length)
        var marker: Int?
        if "#>|+-=0123456789".contains(first), let match = literalBlockStart.firstMatch(in: content, range: range) {
            let ordered = match.range(at: 1)
            marker = ordered.location == NSNotFound ? spaces : ordered.location
        } else if content.contains("|"), literalTableDelimiter.firstMatch(in: content, range: range) != nil {
            marker = text.range(of: "|").location
        }
        guard let marker else { return value }
        let escaped = NSMutableString(string: value)
        escaped.insert("\\", at: marker)
        return escaped as String
    }


    static func imageReferences(_ markdown: String) -> [String] {
        guard markdown.contains("!") else { return [] }
        let masked = NSMutableString(string: markdown)
        for block in FencedCode.blocks(in: markdown).reversed() { masked.replaceCharacters(in: block.range, with: "") }
        guard let parsed = try? AttributedString(markdown: masked as String, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return [] }
        return Array(Set(parsed.runs.compactMap { $0.imageURL?.relativeString })).sorted()
    }
}

enum NativeInlineHTML {
    struct Tag { let name: String; let flags: Int; let closing: Bool }
    static func paired(in node: any Markup) -> [Int: Tag] {
        var opened: [(Int, Tag)] = [], pairs: [Int: Tag] = [:]
        for (index, child) in node.children.enumerated() {
            guard let html = child as? InlineHTML else { continue }
            let raw = html.rawHTML, closing = raw.hasPrefix("</")
            guard raw.hasSuffix(">") else { continue }
            let name = String(raw.dropFirst(closing ? 2 : 1).dropLast())
            let flags: Int
            switch name { case "strong", "b": flags = 1; case "em", "i": flags = 2; case "s", "del", "strike": flags = 4; case "u": flags = 16; default: continue }
            let tag = Tag(name: name, flags: flags, closing: closing)
            if !closing { opened.append((index, tag)) }
            else if let last = opened.last, last.1.name == name { opened.removeLast(); pairs[last.0] = last.1; pairs[index] = tag }
            else { opened = [] }
        }
        return pairs
    }
}

// Search only consumes message text. The Mac chat/history migration will replace
// this adapter with the shared Apple message model when that UI is connected.
struct ChatMessage: Sendable { let role: String; var content: String }
