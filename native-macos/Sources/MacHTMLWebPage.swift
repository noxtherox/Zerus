import SwiftUI
import WebKit
import AppKit
import CryptoKit
import Darwin

/// Stages a user-selected download beside its destination. Existing bytes are
/// replaced only after a complete transfer and a coordinated fingerprint check.
final class MacHTMLDownloadTarget: @unchecked Sendable {
    let destination: URL
    let temporary: URL
    private let original: String?
    private let parentIdentity: MacAgentFileIdentity
    private let scoped: Bool
    init(destination: URL) throws {
        self.destination = destination; scoped = destination.startAccessingSecurityScopedResource()
        temporary = destination.deletingLastPathComponent().appendingPathComponent(".zerus-html-download-" + UUID().uuidString)
        do { parentIdentity = try MacAgentFileIdentity(destination.deletingLastPathComponent()); original = try Self.fingerprint(destination) }
        catch { if scoped { destination.stopAccessingSecurityScopedResource() }; throw error }
    }
    deinit { try? FileManager.default.removeItem(at: temporary); if scoped { destination.stopAccessingSecurityScopedResource() } }
    private static func fingerprint(_ url: URL) throws -> String? {
        guard MacConversations.entryExists(url) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw VaultFailure(message: "Choose a regular destination file for this download.") }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty { try Task.checkCancellation(); hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func commit() throws {
        var coordination: NSError?, result: Result<Void, Error> = .failure(VaultFailure(message: "The download could not be saved."))
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, writingItemAt: temporary, options: .forMoving, error: &coordination) { target, staged in
            result = Result {
                guard try MacAgentFileIdentity(target.deletingLastPathComponent()) == parentIdentity else { throw VaultFailure(message: "The download folder changed. Its current files were preserved.") }
                guard try Self.fingerprint(target) == original else { throw VaultFailure(message: "The download destination changed while transferring. Its current file was preserved.") }
                let values = try staged.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw VaultFailure(message: "The downloaded file is unavailable.") }
                if original == nil {
                    guard renamex_np(staged.path, target.path, UInt32(RENAME_EXCL)) == 0 else { throw VaultFailure(message: "The download destination appeared or could not be saved. Its existing file was preserved.") }
                } else { _ = try FileManager.default.replaceItemAt(target, withItemAt: staged, backupItemName: nil, options: .usingNewMetadataOnly) }
            }
        }
        if let coordination { throw coordination }; try result.get()
    }
}

@MainActor final class MacHTMLWebPage: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let document: MacHTMLPreviewDocument
    let mode: MacHTMLPreviewMode
    let webView: WKWebView
    @Published private(set) var issue: String?
    @Published private(set) var ready = false
    private var active = false
    private var initialNavigation = false

    init(document: MacHTMLPreviewDocument, mode: MacHTMLPreviewMode) {
        self.document = document; self.mode = mode
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = mode == .full
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
    }
    func load() async {
        guard !Task.isCancelled else { return }
        active = true; ready = false; issue = nil; initialNavigation = false
        webView.navigationDelegate = self; webView.uiDelegate = self
        do {
            let html = try document.isolatedHTML(mode: mode), rules = try document.contentRules(mode: mode)
            let identifier = "zerus-local-html-v1-" + NativeHistory.hash(rules)
            let compiled: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
                WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { list, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let list { continuation.resume(returning: list) }
                    else { continuation.resume(throwing: VaultFailure(message: "HTML isolation rules could not be prepared.")) }
                }
            }
            try Task.checkCancellation(); guard active else { return }
            webView.configuration.userContentController.removeAllContentRuleLists()
            webView.configuration.userContentController.add(compiled)
            webView.loadHTMLString(html, baseURL: nil)
        } catch { if active, !(error is CancellationError) { issue = error.localizedDescription } }
    }
    func stop() {
        active = false; webView.stopLoading(); webView.navigationDelegate = nil; webView.uiDelegate = nil
    }
    private func allowed(_ url: URL?) -> Bool {
        guard mode == .full, let url else { return false }
        if ["blob", "data"].contains(url.scheme?.lowercased() ?? "") { return true }
        return MacHTMLPreviewDocument.origin(url.absoluteString).map { document.origins.contains($0) } ?? false
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if active { ready = true } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) { if active, (error as NSError).code != NSURLErrorCancelled { issue = "HTML preview unavailable: " + error.localizedDescription } }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard active else { decisionHandler(.cancel); return }
        if action.shouldPerformDownload { decisionHandler(allowed(action.request.url) ? .download : .cancel); return }
        let url = action.request.url, scheme = url?.scheme?.lowercased()
        if action.targetFrame?.isMainFrame != false {
            if !initialNavigation, url?.absoluteString == "about:blank" { initialNavigation = true; decisionHandler(.allow) }
            else { decisionHandler(.cancel) }
        } else if action.navigationType == .linkActivated { decisionHandler(allowed(url) ? .allow : .cancel) }
        else { decisionHandler(scheme == "about" || scheme == "data" || scheme == "blob" || allowed(url) ? .allow : .cancel) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard active else { decisionHandler(.cancel); return }
        let disposition = (response.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if disposition == "attachment" || !response.canShowMIMEType {
            decisionHandler(allowed(response.response.url) ? .download : .cancel)
        } else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .rejectProtectionSpace, nil) }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { accept(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { accept(download) }
    private func accept(_ download: WKDownload) {
        guard active, mode == .full else { download.cancel(nil); return }
        MacHTMLDownloads.shared.begin(download, origins: document.origins) { [weak self] message in
            guard let self, self.active else { return false }
            self.issue = message; return true
        }
    }
}

struct MacHTMLPageView: View {
    @StateObject private var page: MacHTMLWebPage
    init(document: MacHTMLPreviewDocument, mode: MacHTMLPreviewMode) { _page = StateObject(wrappedValue: MacHTMLWebPage(document: document, mode: mode)) }
    var body: some View {
        VStack(spacing: 0) {
            if let issue = page.issue { Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled).padding(8) }
            MacHTMLWebSurface(page: page)
        }.task { await page.load() }.onDisappear { page.stop() }
    }
}
private struct MacHTMLWebSurface: NSViewRepresentable {
    let page: MacHTMLWebPage
    func makeNSView(context: Context) -> WKWebView { page.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: ()) { view.stopLoading() }
}
