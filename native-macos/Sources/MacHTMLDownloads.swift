import SwiftUI
import AppKit
import WebKit

/// Accepted transfers outlive the originating preview. Their network grant is
/// frozen, and only a completed transfer can replace the user-selected file.
@MainActor final class MacHTMLDownloads: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = MacHTMLDownloads()
    @Published private(set) var active: [MacHTMLTransfer] = []
    struct Recent: Identifiable { let id = UUID(); let name: String; let status: String; let url: URL? }
    @Published private(set) var recent: [Recent] = []
    fileprivate var choosingDestination = false
    private var window: NSWindow?
    func begin(_ download: WKDownload, origins: [String], report: @escaping (String) -> Bool) {
        guard active.count < 16, !choosingDestination else { _ = report("Choose the current download destination, or finish/cancel an active transfer before starting another HTML download."); download.cancel(nil); return }
        let transfer = MacHTMLTransfer(download: download, origins: origins, owner: self, report: report)
        active.append(transfer); download.delegate = transfer
    }
    fileprivate func finished(_ transfer: MacHTMLTransfer, status: String, saved: URL? = nil, issue: String? = nil) {
        guard active.contains(where: { $0 === transfer }) else { return }
        active.removeAll { $0 === transfer }
        recent.insert(.init(name: transfer.name, status: status, url: saved), at: 0); recent = Array(recent.prefix(30))
        if let issue, !transfer.report(issue) { show() }
    }
    func show() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let created = NSWindow(contentRect: .init(x: 0, y: 0, width: 620, height: 430), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        created.title = "HTML downloads"; created.isReleasedWhenClosed = false; created.delegate = self
        created.contentView = NSHostingView(rootView: MacZoomPresentation { MacHTMLDownloadsView(downloads: self) }.modifier(MacThemeHost()))
        created.center(); window = created; created.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { window = nil }
    func prepareToQuit() async -> Bool {
        guard !active.isEmpty else { return true }
        let alert = NSAlert(); alert.messageText = "HTML downloads are still active"
        alert.informativeText = "Keep Zerus open to finish them, or quit and cancel incomplete transfers. Existing destination files stay unchanged until a transfer completes."
        alert.addButton(withTitle: "Keep downloading"); alert.addButton(withTitle: "Quit and cancel downloads")
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        let transfers = active
        for transfer in transfers { await transfer.cancelAndWait() }
        return true
    }
}

@MainActor final class MacHTMLTransfer: NSObject, ObservableObject, Identifiable, WKDownloadDelegate {
    let id = UUID()
    let download: WKDownload
    @Published private(set) var name = "Download"
    @Published private(set) var status = "Choose destination"
    @Published private(set) var saving = false
    let report: (String) -> Bool
    private let origins: Set<String>
    private weak var owner: MacHTMLDownloads?
    private var target: MacHTMLDownloadTarget?
    private var canceled = false
    private var saveTask: Task<Void, Never>?
    private var preparation: Task<MacHTMLDownloadTarget, Error>?
    private weak var destinationPanel: NSSavePanel?
    init(download: WKDownload, origins: [String], owner: MacHTMLDownloads, report: @escaping (String) -> Bool) {
        self.download = download; self.origins = Set(origins); self.owner = owner; self.report = report
    }
    private func allowed(_ url: URL?) -> Bool {
        guard let url else { return false }
        if ["blob", "data"].contains(url.scheme?.lowercased() ?? "") { return true }
        return MacHTMLPreviewDocument.origin(url.absoluteString).map { origins.contains($0) } ?? false
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let memory = ["blob", "data"].contains(download.originalRequest?.url?.scheme?.lowercased() ?? "")
        guard !canceled, let owner, !owner.choosingDestination, allowed(response.url) || memory else { completionHandler(nil); finish("Canceled"); return }
        owner.choosingDestination = true
        let panel = NSSavePanel(); panel.title = "Save download from HTML preview"
        panel.nameFieldStringValue = suggestedFilename.components(separatedBy: CharacterSet(charactersIn: "/\\").union(.controlCharacters)).last.flatMap { $0.isEmpty ? nil : $0 } ?? "Download"
        destinationPanel = panel
        let choice = panel.runModal(); destinationPanel = nil; owner.choosingDestination = false
        guard choice == .OK, let destination = panel.url else { completionHandler(nil); finish("Canceled"); return }
        name = destination.lastPathComponent; status = "Preparing destination…"
        Task {
            do {
                let worker = Task.detached { try MacHTMLDownloadTarget(destination: destination) }
                preparation = worker
                let prepared = try await worker.value; preparation = nil
                guard !canceled else { completionHandler(nil); return }
                target = prepared; status = "Downloading…"; completionHandler(prepared.temporary)
            } catch {
                preparation = nil; completionHandler(nil)
                if canceled || error is CancellationError { finish("Canceled") }
                else { finish(error.localizedDescription, issue: error.localizedDescription) }
            }
        }
    }
    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) { decisionHandler(!canceled && allowed(request.url) ? .allow : .cancel) }
    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .rejectProtectionSpace, nil) }
    func downloadDidFinish(_ download: WKDownload) {
        guard !canceled, let target else { finish("Canceled"); return }
        saving = true; status = "Saving…"
        saveTask = Task {
            do { try await Task.detached { try target.commit() }.value; saveTask = nil; finish("Saved", saved: target.destination) }
            catch { saveTask = nil; finish(error.localizedDescription, issue: error.localizedDescription) }
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if canceled || (error as NSError).code == NSURLErrorCancelled { finish("Canceled") }
        else { finish(error.localizedDescription, issue: error.localizedDescription) }
    }
    private func finish(_ status: String, saved: URL? = nil, issue: String? = nil) { owner?.finished(self, status: status, saved: saved, issue: issue) }
    func cancel() { Task { await cancelAndWait() } }
    func cancelAndWait() async {
        if let saveTask { await saveTask.value; return }
        canceled = true; destinationPanel?.cancel(nil); preparation?.cancel()
        await withCheckedContinuation { continuation in download.cancel { _ in continuation.resume() } }
        finish("Canceled")
    }
}

private struct MacHTMLDownloadsView: View {
    @ObservedObject var downloads: MacHTMLDownloads
    @AppStorage("zerus.mac.appearance") private var appearance = "light"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("HTML downloads").macFont(.title2.bold())
                Text("Accepted downloads continue when you leave a preview. Files are saved only after the transfer finishes.").macFont(.callout).foregroundStyle(.secondary)
                ForEach(downloads.active) { MacHTMLTransferRow(transfer: $0) }
                ForEach(downloads.recent) { item in HStack {
                    VStack(alignment: .leading) { Text(item.name).macFont(.headline); Text(item.status).macFont(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    Spacer(); if let url = item.url { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                } }
                if downloads.active.isEmpty && downloads.recent.isEmpty { ContentUnavailableView("No HTML downloads", systemImage: "arrow.down.circle") }
            }.padding(24)
        }.frame(minWidth: 500, minHeight: 280).preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
    }
}
private struct MacHTMLTransferRow: View {
    @ObservedObject var transfer: MacHTMLTransfer
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(transfer.name).macFont(.headline); Text(transfer.status).macFont(.caption).foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in ProgressView(value: min(1, max(0, transfer.download.progress.fractionCompleted))) }
            }
            Spacer(); Button("Cancel") { transfer.cancel() }.disabled(transfer.saving)
        }
    }
}
