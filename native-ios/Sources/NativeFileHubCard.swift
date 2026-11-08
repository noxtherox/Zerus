import SwiftUI
import UniformTypeIdentifiers

struct NativeFileHubCard: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var session: NoteSession
    @State private var accessible: NativeFileLease?
    @State private var preview: NativeFileLease?
    @State private var sharing: NativeFileLease?
    @State private var issue: String?
    @State private var loading = false
    @State private var loadCancelled = false
    @State private var readTask: Task<Void, Never>?
    @State private var refreshID = UUID()
    @State private var replacing: NativeFileNoteRequest?
    @State private var locating = false
    @State private var locatingNote: NoteDocument?
    @State private var locations = false
    @State private var detaching: NativeFileHub?
    @State private var confirmingDetach = false
    private var reference: NativeFileHub? { session.document.fileHub }
    private var attachments: [NativeFileAttachment] { NativeFileAttachment.all(in: session.document.content) }
    private var controlLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reference {
                VStack(alignment: .leading, spacing: 10) {
                    fileHeader(reference)
                    if let accessible {
                        controlLayout {
                            Button { preview = accessible } label: {
                                if dynamicTypeSize.isAccessibilitySize { Text("Preview document") }
                                else { Label("Preview document", systemImage: "doc.text.magnifyingglass") }
                            }.buttonStyle(.bordered).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("file.preview")
                            Button { sharing = accessible } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share document").frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    if let issue {
                        Text(issue).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Locate document") { locatingNote = session.document; locating = true }.font(.caption.bold()).accessibilityIdentifier("file.locate")
                    }
                    if loading {
                        controlLayout {
                            ProgressView("Loading document…")
                            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                            Button("Cancel") { loadCancelled = true; cancelRead() }.accessibilityLabel("Cancel file loading").accessibilityIdentifier("file.loading.cancel")
                        }.font(.caption)
                    } else if accessible == nil {
                        Button("Retry loading", systemImage: "arrow.clockwise") { refresh() }
                            .accessibilityIdentifier("file.loading.retry")
                    }
                }.padding(14).background(Accent.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            } else if NativeFrontmatter(session.document.content).entries.contains(where: { NativeFileHub.keys.contains($0.key.lowercased()) }) {
                Label("This file connection has unsupported details. The note and original metadata are preserved.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary).padding(12)
            }
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack { ForEach(attachments) { attachment in Button { Task { do { preview = try await vault.attachmentLease(attachment, workspace: session.document.workspaceID ?? UUID()) } catch { issue = error.localizedDescription } } } label: { Label(attachment.name, systemImage: "doc") }.buttonStyle(.bordered).accessibilityIdentifier("file.backup." + attachment.id) } }
                }.accessibilityLabel("Attached file snapshots")
            }
            if reference == nil, let issue { Text(issue).font(.caption).foregroundStyle(.red) }
        }.padding(.horizontal, 20).padding(.bottom, reference != nil || !attachments.isEmpty ? 8 : 0)
            .task(id: reference) { refresh() }
            .onDisappear { cancelRead() }
            .onChange(of: vault.searchRevision) { _, _ in
                // Polling must neither replace an in-flight lookup nor undo
                // the user's explicit cancellation. Retry starts a new one.
                if !loading && !loadCancelled { refresh() }
            }
            .sheet(item: $preview) { NativeFilePreview(lease: $0) }
            .sheet(item: $sharing) { NativeFileShare(lease: $0) }
            .sheet(item: $replacing) { request in NativeFileNoteForm(workspaceID: vault.workspaceID, session: session, source: request.source) { _ in refresh() } }
            .sheet(isPresented: $locations, onDismiss: refresh) { NavigationStack { NativeFileLocationsView(workspaceID: vault.workspaceID) } }
            .fileImporter(isPresented: $locating, allowedContentTypes: [.item]) { result in
                guard let note = locatingNote, let origin = note.workspaceID else { return }
                switch result {
                case .success(let url): Task { do { let source = try await vault.selectFile(url, workspace: origin); try await vault.locateFile(note, source: source, workspace: origin); refresh() } catch is CancellationError {} catch { issue = error.localizedDescription } }
                case .failure(let error): issue = error.localizedDescription
                }
            }
            .confirmationDialog("Detach this document?", isPresented: $confirmingDetach, titleVisibility: .visible) {
                Button("Detach document", role: .destructive) {
                    let original = detaching
                    Task { do { _ = try await vault.saveFileHub(session: session, original: original, source: nil, detach: true, workspace: session.document.workspaceID ?? UUID()); accessible = nil; issue = nil } catch { issue = error.localizedDescription } }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your notes, the original document and existing backup snapshots are kept.") }
    }
    private func fileInformation(_ reference: NativeFileHub) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reference.name).font(.subheadline.weight(.semibold)).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal: false, vertical: true)
            Text(location(reference)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let accessible { Text(ByteCountFormatter.string(fromByteCount: accessible.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func fileActions(_ reference: NativeFileHub) -> some View {
        Menu {
            Button("Refresh file access", systemImage: "arrow.clockwise") { refresh() }
            Button("Locate on this device", systemImage: "location.magnifyingglass") { locatingNote = session.document; locating = true }
            if reference.kind == .location { Button("File locations", systemImage: "folder.badge.gearshape") { locations = true } }
            Button("Replace linked file", systemImage: "arrow.triangle.2.circlepath") { replacing = .init(source: nil) }
            if accessible != nil && (reference.kind != .vault || !reference.managed) { Button("Copy into vault", systemImage: "doc.on.doc") { replacing = .init(source: accessible) } }
            Button("Detach file from note", systemImage: "link.badge.minus", role: .destructive) { detaching = reference; confirmingDetach = true }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("File actions").accessibilityIdentifier("file.actions")
    }
    @ViewBuilder private func fileHeader(_ reference: NativeFileHub) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text").font(.title3).foregroundStyle(Accent.color)
                    Spacer()
                    fileActions(reference)
                }
                fileInformation(reference)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text").font(.title3).foregroundStyle(Accent.color)
                fileInformation(reference)
                fileActions(reference)
            }
        }
    }
    private func location(_ reference: NativeFileHub) -> String {
        if reference.kind == .local { return "Original file connection on this device" }
        if accessible?.locatedOnDevice == true { return "Located on this device" }
        switch reference.kind {
        case .vault: return reference.managed ? "Portable vault copy" : "Linked inside the vault"
        case .local: return "Original file connection on this device"
        case .location: return (vault.fileLocations.first { $0.id == reference.locationID }?.name ?? "Mapped folder") + " · " + (reference.path ?? "")
        }
    }
    private func refresh() {
        let note = session.document, reference = note.fileHub, origin = note.workspaceID, request = UUID()
        loadCancelled = false
        cancelRead(); refreshID = request
        guard reference != nil, let origin else { accessible = nil; issue = nil; return }
        accessible = nil; issue = nil; loading = true
        readTask = Task {
            defer { if refreshID == request { loading = false } }
            do {
                let lease = try await vault.fileHubLease(note, workspace: origin)
                guard !Task.isCancelled, refreshID == request, session.document.fileHub == reference, vault.workspaceID == origin else { return }
                accessible = lease; issue = nil
            } catch is CancellationError {} catch {
                guard !Task.isCancelled, refreshID == request, session.document.fileHub == reference, vault.workspaceID == origin else { return }
                accessible = nil; issue = error.localizedDescription
            }
        }
    }
    private func cancelRead() {
        // A provider can finish after cancellation. Retire this request before
        // cancelling its task so a late result cannot repopulate the card.
        refreshID = UUID()
        readTask?.cancel(); readTask = nil; loading = false
    }
}
