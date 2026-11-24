import SwiftUI
import AppKit

struct MacHTMLPreviewView<Notes: View>: View {
    let lease: NativeFileLease
    let preferenceKey: String
    @Binding var expanded: Bool
    var hasNotes = true
    @ViewBuilder let notes: () -> Notes
    @StateObject private var session = MacHTMLPreviewSession()
    @State private var refresh = UUID()
    @State private var choosing = false
    @State private var savingChoice = false
    @State private var issue: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if session.state.loading { ProgressView().controlSize(.mini) }
                Spacer()
                Button("Downloads…") { MacHTMLDownloads.shared.show() }
                Button("Choose HTML preview…") { choosing = true }
                if rendered { Button(expanded ? "Show notes" : "Expand HTML") { expanded.toggle() }.disabled(!hasNotes) }
            }.padding(8)
            if let problem = issue ?? session.state.issue { Text(problem).font(.caption).foregroundStyle(.red).textSelection(.enabled).padding(8) }
            if rendered, let document = session.state.document, let mode = session.state.mode {
                if expanded || !hasNotes { page(document, mode: mode) }
                else { MacZoomSplitView(axis: .vertical) { page(document, mode: mode).frame(minHeight: 180, idealHeight: 330); notes().frame(minHeight: 160) } }
            } else if hasNotes { notes() }
            else { ContentUnavailableView("HTML file linked", systemImage: "doc", description: Text("Choose a preview mode, or use Open externally.")) }
        }
        .task(id: refresh) {
            await session.prepare(lease: lease, key: preferenceKey)
            if !Task.isCancelled, session.state.mode == nil { choosing = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh = UUID() }
        .onDisappear { session.cancel() }
        .macSheet(isPresented: $choosing, onDismiss: {
            if session.state.mode == nil { Task { do { try await session.choose(.link) } catch { issue = error.localizedDescription } } }
        }) { chooser }
    }
    private var rendered: Bool { session.state.document != nil && (session.state.mode == .safe || session.state.mode == .full) }
    private var label: String {
        switch session.state.mode {
        case .safe: "Safe preview · scripts and external resources disabled"
        case .full: "Full preview · isolated"
        case .link: "HTML · only linked"
        case nil: "Choose how to preview this HTML file"
        }
    }
    private func page(_ document: MacHTMLPreviewDocument, mode: MacHTMLPreviewMode) -> some View {
        MacHTMLPageView(document: document, mode: mode).id(document.fingerprint + ":" + mode.rawValue)
    }
    private var chooser: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose HTML preview").font(.title2.bold())
            Text(lease.url.lastPathComponent).font(.headline).textSelection(.enabled)
            if session.state.approvalExpired { Text("This file changed since it was reviewed. Choose its preview again.").foregroundStyle(.orange) }
            if let document = session.state.document {
                Text(document.needsChoice ? "This file contains scripts or external resources. Full preview can run its scripts and download files; external requests are limited to the origins below." : "No scripts or external dependencies were detected.").font(.callout)
                if !document.origins.isEmpty {
                    ScrollView { VStack(alignment: .leading, spacing: 5) { ForEach(document.origins, id: \.self) { Text($0).font(.caption).textSelection(.enabled) } } }.frame(maxHeight: 180)
                }
                if !document.fullReady { Text("Full preview supports up to 128 external origins. Safe preview and Only link remain available.").font(.caption).foregroundStyle(.orange) }
            } else { Text(session.state.issue ?? "Wait for this document to finish loading.").font(.callout).foregroundStyle(.secondary) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            choice("Only link the file", detail: "Keep the connection without rendering HTML.", mode: .link)
            choice("Safe preview", detail: "Render with scripts and external resources disabled.", mode: .safe)
            choice("Full preview", detail: "Allow scripts, downloads and the reviewed external origins in an isolated preview.", mode: .full)
            HStack { if savingChoice { ProgressView().controlSize(.small) }; Spacer(); Button("Cancel") { choosing = false }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 570).disabled(savingChoice).interactiveDismissDisabled(savingChoice)
    }
    private func choice(_ title: String, detail: String, mode: MacHTMLPreviewMode) -> some View {
        Button {
            savingChoice = true; issue = nil
            Task {
                defer { savingChoice = false }
                do { try await session.choose(mode); choosing = false } catch { issue = error.localizedDescription }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }.disabled(mode != .link && (session.state.document == nil || mode == .full && session.state.document?.fullReady != true))
    }
}

struct MacHTMLStandalonePreview: View {
    let lease: NativeFileLease
    @State private var expanded = true
    var body: some View {
        MacHTMLPreviewView(lease: lease, preferenceKey: MacHTMLPreviewSession.key(root: nil, identity: lease.canonicalPath), expanded: $expanded, hasNotes: false) { EmptyView() }
    }
}

struct MacWebPreview: View {
    let url: URL
    @State private var lease: NativeFileLease?
    @State private var issue: String?
    @State private var loadedFor: URL?
    var body: some View {
        Group {
            if loadedFor == url, let lease { MacHTMLStandalonePreview(lease: lease) }
            else if let issue { Text(issue).font(.caption).foregroundStyle(.secondary).padding() }
            else { ProgressView("Loading HTML…") }
        }.task(id: url) {
            lease = nil; loadedFor = nil; issue = nil
            do {
                guard url.isFileURL else { throw VaultFailure(message: "Choose a local HTML document for preview.") }
                let value = try await Task.detached { try NativeFileLease(scope: url) }.value
                try Task.checkCancellation(); loadedFor = url; lease = value
            } catch { if !(error is CancellationError) { issue = error.localizedDescription } }
        }
    }
}
