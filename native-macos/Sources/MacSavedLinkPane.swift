import SwiftUI
import AppKit
import WebKit

struct MacSavedLinkPane<Notes: View>: View {
    @Bindable var store: MacWorkspace
    let note: NoteDocument
    @ViewBuilder let notes: () -> Notes
    @State private var rendersPage = false
    @State private var expanded = false
    @State private var edit: LinkEdit?
    @State private var reload = UUID()
    private var preferenceKey: String { "zerus.mac.linkPreview." + NativeHistory.hash((store.root?.path ?? "") + "/" + (note.savedLink?.id ?? note.path)) }
    var body: some View {
        VStack(spacing: 0) {
            if let link = note.savedLink {
                HStack(spacing: 12) {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    Text(link.address).macFont(.caption).lineLimit(1).truncationMode(.middle).help(link.address)
                    Spacer()
                    Button("Edit URL") { Task { if await store.save(), let fresh = store.current { edit = .init(note: fresh, workspaceID: store.workspaceID) } } }
                    Button(rendersPage ? "Hide page" : "Render page") { rendersPage.toggle(); expanded = false; UserDefaults.standard.set(rendersPage ? link.address : nil, forKey: preferenceKey) }
                    Menu { Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link.address, forType: .string) }; Button("Open in browser") { if let url = link.url { NSWorkspace.shared.open(url) } } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }.padding(12)
                Divider()
                if rendersPage {
                    if expanded { page(link) } else {
                        MacZoomSplitView(axis: .vertical) { page(link).frame(minHeight: 150, idealHeight: 300); notes().frame(minHeight: 160) }
                    }
                } else { notes() }
            }
        }
        .onAppear { restorePreference() }
        .onChange(of: note.savedLink?.address) { restorePreference(); expanded = false; reload = UUID() }
        .macSheet(item: $edit) { MacLinkEditView(store: store, edit: $0) }
    }
    private func restorePreference() { rendersPage = UserDefaults.standard.string(forKey: preferenceKey) == note.savedLink?.address }
    private func page(_ link: NativeSavedLink) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Live page").macFont(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reload") { reload = UUID() }
                Button(expanded ? "Show notes" : "Expand page") { expanded.toggle() }
                Button("Open in browser") { if let url = link.url { NSWorkspace.shared.open(url) } }
            }.padding(8)
            if let url = link.url { MacLivePageReader(url: url).id(link.address + reload.uuidString) } else { Text("This saved link has an invalid web address. Use Edit URL to repair it.").padding() }
        }
    }
}
private struct LinkEdit: Identifiable {
    let id = UUID()
    let note: NoteDocument
    let workspaceID: UUID
}
private struct MacLinkEditView: View {
    @Bindable var store: MacWorkspace
    let edit: LinkEdit
    @State private var address = ""
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit saved link").macFont(.title2.bold())
            TextField("Web address", text: $address).textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red).macFont(.caption).textSelection(.enabled) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save URL") {
                saving = true
                Task { do { try await store.updateLink(edit.note, address: address, workspaceID: edit.workspaceID); dismiss() } catch { self.error = error.localizedDescription }; saving = false }
            }.keyboardShortcut(.defaultAction).disabled(saving || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 480).onAppear { address = edit.note.savedLink?.address ?? "" }
    }
}
private final class MacPageStatus: ObservableObject {
    @Published var message = "Loading page…"
}
private struct MacLivePageReader: View {
    let url: URL
    @StateObject private var status = MacPageStatus()
    var body: some View {
        VStack(spacing: 0) {
            if !status.message.isEmpty { Text(status.message).macFont(.caption).foregroundStyle(.secondary).padding(8).frame(maxWidth: .infinity) }
            MacLivePage(url: url, status: status)
        }
    }
}
private struct MacLivePage: NSViewRepresentable {
    let url: URL
    let status: MacPageStatus
    func makeCoordinator() -> Coordinator { Coordinator(status: status) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        view.load(URLRequest(url: url)); return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { view.stopLoading(); view.navigationDelegate = nil; view.uiDelegate = nil }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let status: MacPageStatus
        init(status: MacPageStatus) { self.status = status }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { status.message = "Loading page…" }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { status.message = "" }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        private func failed(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            status.message = "Page unavailable: " + error.localizedDescription + " Use Open in browser."
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            decisionHandler(scheme == "http" || scheme == "https" ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
    }
}
