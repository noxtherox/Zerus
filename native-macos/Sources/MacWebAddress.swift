import Foundation
import WebURL
import WebURLFoundationExtras

/// Match the desktop's trim/default-scheme wrapper around the browser URL
/// constructor. Parsing is local and does not load a page or make a request.
enum MacWebAddress {
    private static let whitespace = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
    private static func parsed(_ raw: String) -> WebURL? {
        var value = raw.trimmingCharacters(in: whitespace)
        if value.hasPrefix("<") { value.removeFirst() }
        if value.hasSuffix(">") { value.removeLast() }
        guard !value.isEmpty else { return nil }
        if value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) == nil { value = "https://" + value }
        guard let url = WebURL(value), ["http", "https"].contains(url.scheme), url.hostname?.isEmpty == false else { return nil }
        return url
    }
    static func canonical(_ raw: String) -> String? { parsed(raw)?.serialized() }
    static func foundationURL(_ raw: String) -> URL? { parsed(raw).flatMap { URL($0) } }
}
