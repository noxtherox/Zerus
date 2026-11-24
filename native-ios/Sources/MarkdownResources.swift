import Foundation

/// Only actual inline destinations are rewritten. Code, escaped examples, link
/// labels, titles, and remote URLs retain their original text.
enum MarkdownResources {
    static func localReferences(in source: String, includeNoteFiles: Bool = false) -> [String] {
        var references = Set<String>()
        _ = transform(source) { url, image in
            if isLocalAsset(url, image: image, includeNoteFiles: includeNoteFiles) { references.insert(url.relativeString) }
            return nil
        }
        return references.sorted()
    }

    static func attachmentReferences(in source: String) -> [String] {
        var references = Set<String>()
        _ = transform(source) { url, _ in
            if url.scheme?.lowercased() == "zerus-attachment" { references.insert(url.absoluteString) }
            return nil
        }
        return references.sorted()
    }

    static func replacing(_ source: String, references: [String: String]) -> String {
        transform(source) { url, _ in references[url.relativeString] }
    }

    static func encodedPath(_ path: String, preservingSuffixOf reference: String) -> String {
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/-._~")
        var result = path.addingPercentEncoding(withAllowedCharacters: safe) ?? path
        if let parts = URLComponents(string: reference) {
            if let query = parts.percentEncodedQuery { result += "?" + query }
            if let fragment = parts.percentEncodedFragment { result += "#" + fragment }
        }
        return result
    }

    private static func isLocalAsset(_ url: URL, image: Bool, includeNoteFiles: Bool) -> Bool {
        guard url.scheme == nil, !url.relativePath.isEmpty, !url.relativePath.hasPrefix("/") else { return false }
        // Markdown-note destinations are connections, not attachment copies.
        return image || includeNoteFiles || !(url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown")
    }

    private static func transform(_ source: String, replacement: (URL, Bool) -> String?) -> String {
        guard let links = try? MarkdownMoveLinks.links(in: source) else { return source }
        let edits: [(MarkdownMoveLinks.Link, String)] = links.compactMap { link in
            switch link.kind {
            case .wiki: return nil
            case .html: guard link.image else { return nil }
            case .destination: break
            }
            guard let url = MarkdownMoveLinks.destinationURL(link.value), let value = replacement(url, link.image) else { return nil }
            return (link, value)
        }
        return MarkdownMoveLinks.replacing(source, edits: edits)
    }
}
