import ImageIO
import SwiftUI
import AppKit
import QuickLookUI
import UniformTypeIdentifiers

struct MacFileHubEditor: View {
    @Bindable var workspace: MacWorkspace
    let request: MacFileHubRequest
    var initialSource: URL? = nil
    var saved: (NoteDocument) -> Void
    @State private var source: NativeFileLease?
    @State private var title = ""
    @State private var folder: String
    @State private var storage: NativeFileStorage = .copy
    @State private var issue: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    init(workspace: MacWorkspace, request: MacFileHubRequest, initialSource: URL? = nil, saved: @escaping (NoteDocument) -> Void) {
        self.workspace = workspace; self.request = request; self.initialSource = initialSource; self.saved = saved
        _folder = State(initialValue: request.defaultFolder)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.note == nil ? "Add document" : request.note?.fileHub == nil ? "Link document" : "Replace document").font(.title2.bold())
            Text("Keep your notes beside a document. Replacing its connection keeps the note’s content.").font(.callout).foregroundStyle(.secondary)
            HStack { VStack(alignment: .leading, spacing: 4) { Text(source?.url.lastPathComponent ?? "Choose a document").font(.headline); if let source { Text(source.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }; Spacer(); Button("Choose file…") { choose() } }
            Picker("Storage", selection: $storage) { ForEach(NativeFileStorage.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Text(storage.detail).font(.caption).foregroundStyle(.secondary)
            if request.note == nil {
                TextField("Note title", text: $title).textFieldStyle(.roundedBorder)
                Picker("Folder", selection: $folder) { Text("Files (unfiled)").tag(".zerus/files"); ForEach(Array(Set([request.defaultFolder] + workspace.defaultNoteFolderOptions)).sorted(), id: \.self) { MacFolderLabel(path: $0, icon: workspace.folderIcon($0)).tag($0) } }
            }
            if let locationIssue = request.locationIssue { Text(locationIssue).font(.caption).foregroundStyle(.secondary) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack { if busy { ProgressView().controlSize(.small) }; Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save document") {
                busy = true
                Task { defer { busy = false }; do { let note = try await workspace.saveFileHub(request, source: source, storage: storage, title: title, folder: folder); saved(note); dismiss() } catch { issue = error.localizedDescription } }
            }.keyboardShortcut(.defaultAction).disabled(source == nil) }
        }.padding(26).frame(width: 560).disabled(busy).interactiveDismissDisabled(busy)
        .onAppear { if let initialSource { select(initialSource) }; title = request.note?.title ?? title }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.item]; panel.canChooseDirectories = false; panel.prompt = "Choose document"
        if panel.runModal() == .OK, let url = panel.url { select(url) }
    }
    private func select(_ url: URL) {
        do { source = try NativeFileLease(scope: url); if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }; issue = nil } catch { issue = error.localizedDescription }
    }
}

struct MacFileHubPane<Notes: View>: View {
    @Bindable var workspace: MacWorkspace
    let note: NoteDocument
    let workspaceID: UUID
    @ViewBuilder let notes: () -> Notes
    init(workspace: MacWorkspace, note: NoteDocument, @ViewBuilder notes: @escaping () -> Notes) {
        self.workspace = workspace; self.note = note; self.workspaceID = workspace.workspaceID; self.notes = notes
    }
    @StateObject private var preview = MacFileHubPreview()
    @State private var issue: String?
    @State private var showsDocument = true
    @State private var expanded = false
    @State private var locations = false
    @State private var replacing: MacFileHubRequest?
    @State private var detaching: MacFileHubRequest?
    private enum Refresh: Equatable {
        case check(UUID), reload(UUID)
        var forced: Bool { if case .reload = self { return true }; return false }
    }
    @State private var refresh = Refresh.check(UUID())
    private struct Request: Equatable {
        let source: MacFileHubPreview.Source
        let mappingRevision: Int
        let refresh: Refresh
    }
    private var request: Request { .init(source: .init(workspaceID: workspaceID, path: note.path, reference: note.fileHub), mappingRevision: workspace.fileMappingRevision, refresh: refresh) }
    private var lease: NativeFileLease? { preview.source == request.source ? preview.lease : nil }
    var body: some View {
        VStack(spacing: 0) {
            if let hub = note.fileHub {
                HStack(spacing: 10) {
                    Image(systemName: "doc").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hub.name).font(.caption.bold()).lineLimit(1)
                        HStack(spacing: 5) {
                            Text(hub.kind == .vault ? (hub.managed ? "Vault copy" : "Vault file connection") : hub.kind == .location ? "Folder connection" : "Original connection on this Mac").lineLimit(1)
                            if let lease { Text("· " + ByteCountFormatter.string(fromByteCount: lease.size, countStyle: .file)) }
                            else { Text("· File unavailable") }
                            if preview.refreshing { ProgressView().controlSize(.mini) }
                        }.font(.caption2).foregroundStyle(.secondary)
                        if let lease { Text(lease.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(lease.url.path).textSelection(.enabled) }
                    }
                    Spacer()
                    Button(showsDocument ? "Hide document" : "Show document") { showsDocument.toggle(); expanded = false }
                    Menu {
                        Button("Open externally") { if let lease { NSWorkspace.shared.open(lease.url) } }.disabled(lease == nil)
                        Button("Reveal document in Finder") { if let lease { NSWorkspace.shared.activateFileViewerSelecting([lease.url]) } }.disabled(lease == nil)
                        Button("Locate original…") { locate() }
                        Button("File locations…") { locations = true }
                        if hub.kind == .location, lease?.locatedOnDevice == true {
                            Button("Use folder mapping again") { Task { do { try await workspace.useFolderMapping(note, workspaceID: workspaceID) } catch { issue = error.localizedDescription } } }
                        }
                        Button("Replace document…") { Task { do { guard workspaceID == workspace.workspaceID else { throw CancellationError() }; replacing = try await workspace.prepareFileHub(note) } catch { issue = error.localizedDescription } } }
                        Button("Detach document…") { Task { do { guard workspaceID == workspace.workspaceID else { throw CancellationError() }; detaching = try await workspace.prepareFileHub(note) } catch { issue = error.localizedDescription } } }
                        Divider()
                        Button("Reload preview") { issue = nil; refresh = .reload(UUID()) }
                        ForEach(NativeFileAttachment.all(in: note.content)) { backup in Button("Open backup: " + backup.name) { Task { await workspace.previewAttachment(backup) } } }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Document actions")
                }.padding(12)
                Divider()
                if let problem = issue ?? (preview.source == request.source ? preview.issue : nil) { HStack { Image(systemName: "exclamationmark.triangle"); Text(problem).font(.caption).textSelection(.enabled); Spacer(); Button("Locate file…") { locate() } }.foregroundStyle(.secondary).padding(10) }
                if showsDocument, let lease {
                    if ["html", "htm"].contains(lease.url.pathExtension.lowercased()) || ["html", "htm"].contains((hub.name as NSString).pathExtension.lowercased()) {
                        MacHTMLPreviewView(lease: lease, preferenceKey: MacHTMLPreviewSession.key(root: workspace.root, identity: hub.id), expanded: $expanded, notes: notes)
                            .id(lease.id)
                    } else {
                        // Keep the document in one layout branch so expanding it
                        // preserves the PDF reader's search, page and manual zoom.
                        MacZoomSplitView(axis: .vertical) {
                            document(lease).frame(minHeight: expanded ? 0 : 180, idealHeight: expanded ? nil : 330)
                            if !expanded { notes().frame(minHeight: 160) }
                        }
                    }
                } else { notes() }
            }
        }
        .task(id: request) { issue = nil; await preview.refresh(note, workspace: workspace, workspaceID: workspaceID, force: request.refresh.forced) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh = .check(UUID()) }
        .onDisappear { preview.cancel() }
        .macSheet(isPresented: $locations) { MacFileLocationsView(workspace: workspace) }
        .macSheet(item: $replacing) { request in MacFileHubEditor(workspace: workspace, request: request) { _ in } }
        .alert("Detach this document?", isPresented: Binding(get: { detaching != nil }, set: { if !$0 { detaching = nil } })) {
            Button("Cancel", role: .cancel) { detaching = nil }
            Button("Detach document") { if let request = detaching { Task { do { _ = try await workspace.saveFileHub(request, source: nil, storage: .copy, title: note.title, folder: note.folder, detach: true) } catch { workspace.issue = error.localizedDescription } } }; detaching = nil }
        } message: { Text("The note and its backup attachments stay in place. The original document and existing vault copy are kept.") }
    }
    private func document(_ lease: NativeFileLease) -> some View {
        VStack(spacing: 0) {
            HStack { Text("Document preview").font(.caption).foregroundStyle(.secondary); Spacer(); Button(expanded ? "Show notes" : "Expand document") { expanded.toggle() }; Button("Open externally") { NSWorkspace.shared.open(lease.url) } }.padding(8)
            MacDocumentSurface(lease: lease).id(lease.id)
        }
    }
    private func locate() {
        let origin = workspaceID
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.item]; panel.canChooseDirectories = false; panel.message = "Locate this document on this Mac. The shared note’s connection details stay the same."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { do { let selected = try NativeFileLease(scope: url); try await workspace.locateFileHub(note, source: selected, workspaceID: origin); issue = nil } catch { issue = error.localizedDescription } }
    }
}

struct MacLeasedPreview: View {
    let lease: NativeFileLease
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(lease.url.lastPathComponent).font(.headline); Spacer(); Button("Open externally") { NSWorkspace.shared.open(lease.url) }; Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([lease.url]) }; Button("Done") { dismiss() } }.padding(15)
            Divider(); MacDocumentSurface(lease: lease)
        }.frame(minWidth: 850, minHeight: 680).onDisappear { withExtendedLifetime(lease) {} }
    }
}
private struct MacDocumentSurface: View {
    let lease: NativeFileLease
    var body: some View {
        Group {
            if lease.url.pathExtension.lowercased() == "pdf" { MacPDFView(url: lease.url) }
            else if ["html", "htm"].contains(lease.url.pathExtension.lowercased()) { MacHTMLStandalonePreview(lease: lease) }
            else if UTType(filenameExtension: lease.url.pathExtension)?.conforms(to: .image) == true { MacPreviewImage(url: lease.url) }
            else { MacQuickLook(url: lease.url) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
/// Decodes a display-sized image off the main thread and keeps recent ones,
/// so opening a large photo, or redrawing its sheet, never blocks the window.
private struct MacPreviewImage: View {
    let url: URL
    @State private var loaded: (url: URL, image: NSImage?)?
    var body: some View {
        Group {
            if let loaded, loaded.url == url {
                if let image = loaded.image {
                    let width = min(image.size.width, 1000)
                    ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().frame(width: width, height: image.size.height * width / max(1, image.size.width)) }
                } else { MacQuickLook(url: url) }
            } else { ProgressView().controlSize(.small) }
        }.task(id: url) { loaded = (url, await MacPreviewImageCache.shared.image(url)) }
    }
}
actor MacPreviewImageCache {
    static let shared = MacPreviewImageCache()
    private let cache: NSCache<NSString, NSImage> = { let value = NSCache<NSString, NSImage>(); value.totalCostLimit = 96 * 1024 * 1024; return value }()
    /// Keyed by path, modification date and size so an edited file is decoded again.
    func image(_ url: URL) async -> NSImage? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = "\(url.path)|\(values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)|\(values?.fileSize ?? 0)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let decoded = await Task.detached(priority: .userInitiated) { () -> (NSImage, Int)? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                           kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: 2400] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            // Show at the original point size, as the full decode did.
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            var width = (properties?[kCGImagePropertyPixelWidth] as? Double) ?? Double(image.width)
            var height = (properties?[kCGImagePropertyPixelHeight] as? Double) ?? Double(image.height)
            if let orientation = properties?[kCGImagePropertyOrientation] as? UInt32, orientation >= 5 { swap(&width, &height) }
            return (NSImage(cgImage: image, size: .init(width: width, height: height)), image.bytesPerRow * image.height)
        }.value
        guard let decoded else { return nil }
        cache.setObject(decoded.0, forKey: key, cost: decoded.1)
        return decoded.0
    }
}
private struct MacQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { let view = QLPreviewView(frame: .zero, style: .normal)!; view.previewItem = url as NSURL; return view }
    func updateNSView(_ view: QLPreviewView, context: Context) {}
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}
