import Foundation
import CryptoKit
import SwiftUI

enum MacHTMLPreviewMode: String, Codable, CaseIterable, Sendable { case link, safe, full }

struct MacHTMLPreviewDocument: Sendable {
    static let maximum = 10 * 1024 * 1024
    let source: String
    private let safeSource: String
    let fingerprint: String
    let hasScripts: Bool
    let origins: [String]
    var domains: [String] { Array(Set(origins.compactMap { URL(string: $0)?.host })).sorted() }
    var needsChoice: Bool { hasScripts || !origins.isEmpty }
    var fullReady: Bool { origins.count <= 128 }

    private final class Scanner {
        let deadline = Date().addingTimeInterval(2)
        var remaining = 50_000
        func matches(_ pattern: String, _ text: String) throws -> [NSTextCheckingResult] {
            let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            var result: [NSTextCheckingResult] = [], exceeded = false
            expression.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(text.startIndex..., in: text)) { match, _, stop in
                if Task.isCancelled || Date() > self.deadline || self.remaining <= 0 { exceeded = true; stop.pointee = true; return }
                if let match { result.append(match); self.remaining -= 1 }
            }
            try Task.checkCancellation()
            guard !exceeded else { throw VaultFailure(message: "This HTML document is too complex for preview analysis. Choose Only link or Open externally.") }
            return result
        }
        func attribute(_ name: String, in text: String) throws -> String? {
            guard let match = try matches("\\b" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", text).first else { return nil }
            let value = text as NSString
            return (1...3).first(where: { match.range(at: $0).location != NSNotFound }).map { value.substring(with: match.range(at: $0)) }
        }
    }
    static func origin(_ text: String) -> String? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("//") { text = "https:" + text }
        guard var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty else { return nil }
        parts.scheme = scheme; parts.host = host.lowercased(); parts.user = nil; parts.password = nil
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        parts.path = ""; parts.query = nil; parts.fragment = nil
        return parts.url?.absoluteString
    }
    init(bytes: Data) throws {
        guard bytes.count <= Self.maximum, let source = NoteDocument.decodeUTF8(bytes) else { throw VaultFailure(message: "HTML preview requires a UTF-8 file of at most 10 MB. Use Only link or Open externally for this file.") }
        self.source = source; fingerprint = NativeHistory.hash(bytes)
        var origins = Set<String>(), scripts = false
        func add(_ text: String?) { if let text, let origin = Self.origin(text) { origins.insert(origin) } }
        let ns = source as NSString, scanner = Scanner()
        for match in try scanner.matches(#"<script\b([^>]*)>"#, source) {
            let attributes = ns.substring(with: match.range(at: 1)), type = try scanner.attribute("type", in: attributes)?.lowercased()
            if !["application/json", "application/ld+json"].contains(type ?? "") { scripts = true; add(try scanner.attribute("src", in: attributes)) }
        }
        for match in try scanner.matches(#"<(?:img|iframe|embed|source|video|audio|input|link|object)\b([^>]*)>"#, source) {
            let attributes = ns.substring(with: match.range(at: 1))
            for name in ["src", "poster", "href", "data"] { add(try scanner.attribute(name, in: attributes)) }
            if let srcset = try scanner.attribute("srcset", in: attributes) { for item in srcset.split(separator: ",") { add(item.split(whereSeparator: \.isWhitespace).first.map(String.init)) } }
        }
        for pattern in [#"(?:url\(|@import\s+)(?:\s*["']?)(https?://|//)([^\s"')]+)"#, #"\b(?:fetch|EventSource|WebSocket)\s*\(\s*["'](https?://|//)([^"']+)"#] {
            for match in try scanner.matches(pattern, source) { add(ns.substring(with: match.range(at: 1)) + ns.substring(with: match.range(at: 2))) }
        }
        if try !scanner.matches(#"\bon[a-z]+\s*=|javascript\s*:"#, source).isEmpty { scripts = true }
        let safe = NSMutableString(string: source)
        for match in try scanner.matches(#"<meta\b(?=[^>]*\bhttp-equiv\s*=\s*(?:["']?refresh["']?))[^>]*>"#, source).reversed() { safe.deleteCharacters(in: match.range) }
        safeSource = safe as String
        self.origins = origins.sorted(); hasScripts = scripts
    }
    static func load(_ lease: NativeFileLease) async throws -> Self {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard lease.size <= maximum else { throw VaultFailure(message: "This HTML file exceeds the 10 MB preview limit. Use Only link or Open externally.") }
            var error: NSError?, result: Result<Data, Error> = .failure(VaultFailure(message: "The HTML document is unavailable."))
            NSFileCoordinator().coordinate(readingItemAt: lease.url, options: [], error: &error) { file in result = Result {
                guard file.resolvingSymlinksInPath().standardizedFileURL.path == lease.canonicalPath else { throw VaultFailure(message: "The HTML document moved. Reload its preview.") }
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= maximum else { throw VaultFailure(message: "This HTML file exceeds the 10 MB preview limit. Use Only link or Open externally.") }
                let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
                var bytes = Data()
                while bytes.count <= maximum {
                    let chunk = try handle.read(upToCount: min(64 * 1024, maximum + 1 - bytes.count)) ?? Data()
                    if chunk.isEmpty { break }; bytes.append(chunk)
                }
                guard bytes.count <= maximum else { throw VaultFailure(message: "This HTML file exceeds the 10 MB preview limit. Use Only link or Open externally.") }
                return bytes
            } }
            if let error { throw error }
            return try Self(bytes: result.get())
        }.value
    }

    /// Safe content has JavaScript disabled at the WebKit level. Full content
    /// inherits the outer policy in an opaque sandbox frame, outside the app DOM.
    func isolatedHTML(mode: MacHTMLPreviewMode) throws -> String {
        guard mode != .link, mode != .full || fullReady else { throw VaultFailure(message: "This file has too many external origins for Full preview. Choose Safe preview or Only link.") }
        let allowed = mode == .full ? origins.joined(separator: " ") : ""
        func list(_ directive: String, _ base: String = "") -> String { directive + " " + [base, allowed].filter { !$0.isEmpty }.joined(separator: " ") }
        let policy = ["default-src 'none'", mode == .full ? list("script-src", "'unsafe-inline' 'unsafe-eval' blob:") : "script-src 'none'",
                      mode == .full && !allowed.isEmpty ? list("connect-src") : "connect-src 'none'",
                      list("img-src", "data: blob:"), list("media-src", "data: blob:"), list("style-src", "'unsafe-inline'"), list("font-src", "data:"),
                      mode == .full ? list("frame-src", "about: data: blob:") : "frame-src 'none'", mode == .full ? "worker-src blob:" : "worker-src 'none'",
                      "object-src 'none'", "base-uri 'none'", "form-action 'none'"].joined(separator: "; ")
        func escaped(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        if mode == .safe {
            return "<!doctype html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"Content-Security-Policy\" content=\"" + escaped(policy) + "\"><meta name=\"referrer\" content=\"no-referrer\"></head><body>" + safeSource + "</body></html>"
        }
        let sandbox = mode == .full ? "allow-scripts allow-downloads" : ""
        return "<!doctype html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"Content-Security-Policy\" content=\"" + escaped(policy) + "\"><meta name=\"referrer\" content=\"no-referrer\"><style>html,body,iframe{border:0;margin:0;width:100%;height:100%;display:block;background:white}</style></head><body><iframe title=\"HTML file preview\" sandbox=\"" + sandbox + "\" allow=\"camera 'none'; microphone 'none'; geolocation 'none'; clipboard-read 'none'; clipboard-write 'none'\" referrerpolicy=\"no-referrer\" srcdoc=\"" + escaped(source) + "\"></iframe></body></html>"
    }
    func contentRules(mode: MacHTMLPreviewMode) throws -> String {
        guard mode != .link, mode != .full || fullReady else { throw VaultFailure(message: "Choose Safe preview or Only link for this HTML document.") }
        var rules: [[String: Any]] = [["trigger": ["url-filter": ".*"], "action": ["type": "block"]]]
        for prefix in ["^about:", "^data:", "^blob:"] { rules.append(["trigger": ["url-filter": prefix], "action": ["type": "ignore-previous-rules"]]) }
        if mode == .full {
            for origin in origins {
                let escaped = origin.reduce("") { $0 + (".[](){}?+*^$\\|".contains($1) ? "\\" : "") + String($1) }
                rules.append(["trigger": ["url-filter": "^" + escaped + "/"], "action": ["type": "ignore-previous-rules"]])
            }
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
}

@MainActor final class MacHTMLPreviewSession: ObservableObject {
    private static let policyVersion = 1
    struct State {
        var document: MacHTMLPreviewDocument?
        var mode: MacHTMLPreviewMode?
        var loading = false
        var issue: String?
        var approvalExpired = false
    }
    @Published private(set) var state = State()
    private var lease: NativeFileLease?
    private var preferenceKey: String?
    private var request = UUID()
    static func key(root: URL?, identity: String) -> String { "zerus.mac.htmlPreview.v1." + NativeHistory.hash((root?.resolvingSymlinksInPath().standardizedFileURL.absoluteString ?? "standalone") + "\0" + identity) }
    func prepare(lease: NativeFileLease, key: String) async {
        guard !Task.isCancelled else { return }
        let token = UUID(); request = token
        if preferenceKey != key || self.lease?.canonicalPath != lease.canonicalPath { state = .init() }
        self.lease = lease; preferenceKey = key; state.loading = true
        do {
            let document = try await MacHTMLPreviewDocument.load(lease)
            try Task.checkCancellation(); guard request == token else { return }
            let saved = UserDefaults.standard.dictionary(forKey: key), prior = (saved?["mode"] as? String).flatMap(MacHTMLPreviewMode.init)
            let expired = prior == .full && (saved?["fingerprint"] as? String != document.fingerprint || NativeHistory.integer(saved?["policyVersion"]) != Self.policyVersion || saved?["origins"] as? [String] != document.origins)
            let mode: MacHTMLPreviewMode? = expired ? nil : prior ?? (document.needsChoice ? nil : .safe)
            if prior == nil, mode == .safe { var automatic = saved ?? [:]; automatic["mode"] = "safe"; UserDefaults.standard.set(automatic, forKey: key) }
            state = .init(document: document, mode: mode, loading: false, issue: nil, approvalExpired: expired)
        } catch {
            guard request == token else { return }
            if error is CancellationError { state.loading = false; return }
            let saved = UserDefaults.standard.dictionary(forKey: key)
            state = .init(document: nil, mode: saved?["mode"] as? String == "link" ? .link : nil, loading: false, issue: error.localizedDescription)
        }
    }
    func choose(_ mode: MacHTMLPreviewMode) async throws {
        guard let key = preferenceKey else { throw VaultFailure(message: "Reload this HTML document before choosing its preview.") }
        let token = request
        if mode != .link {
            guard let lease, let document = state.document else { throw VaultFailure(message: "Only link is available until this HTML document can be reviewed.") }
            guard mode != .full || document.fullReady else { throw VaultFailure(message: "Full preview supports up to 128 external origins. Choose Safe preview or Only link.") }
            let current = try await MacHTMLPreviewDocument.load(lease)
            try Task.checkCancellation(); guard request == token, preferenceKey == key else { throw CancellationError() }
            guard current.fingerprint == document.fingerprint else {
                state = .init(document: current, mode: nil, loading: false, issue: nil, approvalExpired: true)
                throw VaultFailure(message: "This HTML file changed during review. Choose its preview again.")
            }
        }
        var saved = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        saved["mode"] = mode.rawValue; saved["fingerprint"] = mode == .full ? state.document?.fingerprint : nil
        saved["policyVersion"] = mode == .full ? Self.policyVersion : nil
        saved["origins"] = mode == .full ? state.document?.origins : nil
        UserDefaults.standard.set(saved, forKey: key)
        state.mode = mode; state.approvalExpired = false
    }
    func cancel() { request = UUID(); lease = nil; preferenceKey = nil; state = .init() }
}
