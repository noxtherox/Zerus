import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
private enum NativeChatAttachmentThumbnails {
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.totalCostLimit = 16 * 1024 * 1024; return cache
    }()
    static func image(_ item: NativeChatAttachment, store: NativeChatAttachmentStore) -> UIImage? {
        guard item.kind == .image else { return nil }
        let key = (store.directory.absoluteString + item.id.uuidString + item.digest) as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let data = try? store.read(item), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: (item.width ?? 1) * (item.height ?? 1) * 4); return image
    }
}

struct NativeChatAttachmentCard: View {
    let item: NativeChatAttachment
    @ObservedObject var chat: NativeChat
    var remove: (() -> Void)? = nil
    let preview: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: preview) {
                HStack(spacing: 9) {
                    if let image = NativeChatAttachmentThumbnails.image(item, store: chat.attachmentStore) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                    } else { Image(systemName: item.kind == .image ? "photo" : "doc.text").font(.title2).frame(width: 35).accessibilityHidden(true) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.caption.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(item.kind == .image ? "Image · \(item.width ?? 0) × \(item.height ?? 0)" : item.pages.map { "PDF · \($0) \($0 == 1 ? "page" : "pages")" } ?? "Text document").font(.caption2).foregroundStyle(.secondary)
                    }
                }.frame(width: 190, alignment: .leading)
            }.buttonStyle(.plain).accessibilityLabel("Preview " + item.name).accessibilityIdentifier("chat.attachment.preview." + item.id.uuidString)
            if let remove {
                Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44) }.buttonStyle(.plain).accessibilityLabel("Remove " + item.name).accessibilityIdentifier("chat.attachment.remove." + item.id.uuidString)
            } else {
                Menu { Button("Use in message", systemImage: "plus") { chat.reuseAttachment(item) } } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.disabled(chat.running || chat.agent.running || chat.dictating || chat.importingAttachments).accessibilityLabel("Attachment actions for " + item.name)
            }
        }.padding(9).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct NativeChatMessageAttachments: View {
    let items: [NativeChatAttachment]
    @ObservedObject var chat: NativeChat
    @State private var preview: NativeFileLease?
    var body: some View {
        ScrollView(.horizontal) { HStack { ForEach(items) { item in NativeChatAttachmentCard(item: item, chat: chat, preview: { Task { do { preview = try await chat.attachmentStore.preview(item) } catch { chat.error = error.localizedDescription } } }) } } }
            .sheet(item: $preview) { NativeFilePreview(lease: $0) }
    }
}

struct NativeChatAttachmentComposer: View {
    @EnvironmentObject private var vault: VaultStore
    @ObservedObject var chat: NativeChat
    let workspaceID: UUID
    @State private var files = false
    @State private var photos = false
    @State private var selections: [PhotosPickerItem] = []
    @State private var preview: NativeFileLease?
    @State private var job: Task<Void, Never>?
    @State private var importID: UUID?
    @State private var recover = false
    private var busy: Bool { chat.running || chat.agent.running || chat.dictating || chat.importingAttachments || vault.workspaceID != workspaceID || vault.switchingVault }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    Button("Files", systemImage: "folder") { files = true }.accessibilityIdentifier("chat.attach.files")
                    Button("Photos", systemImage: "photo") { selections = []; photos = true }.disabled(chat.attachments.filter { $0.kind == .image }.count >= 4).accessibilityIdentifier("chat.attach.photos")
                } label: { Label("Attach", systemImage: "paperclip").frame(minHeight: 44) }.disabled(busy || !chat.attachmentDraftAvailable).accessibilityIdentifier("chat.attach")
                if chat.importingAttachments {
                    ProgressView().controlSize(.small)
                    Text("Preparing attachments…").foregroundStyle(.secondary).accessibilityIdentifier("chat.attach.progress")
                    Spacer()
                    Button("Cancel", action: cancel).accessibilityIdentifier("chat.attach.cancel")
                } else { Spacer(); Text(chat.attachments.isEmpty ? "PDF, text and images" : "\(chat.attachments.count) attached").foregroundStyle(.secondary) }
            }.font(.caption)
            if !chat.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack { ForEach(chat.attachments) { item in
                        NativeChatAttachmentCard(item: item, chat: chat, remove: { chat.removeAttachment(item.id) }, preview: { show(item) }).disabled(busy)
                    } }
                }
            }
            if let problem = chat.attachmentProblem {
                Text(problem).font(.caption).foregroundStyle(.orange).textSelection(.enabled).accessibilityIdentifier("chat.attach.issue")
                if let url = chat.attachmentRecoveryURL { ShareLink(item: url) { Label("Share saved attachment draft", systemImage: "square.and.arrow.up") }.font(.caption) }
                if !chat.attachmentDraftAvailable { Button("Keep a recovery copy and reset attachments") { recover = true }.font(.caption).disabled(busy) }
            }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): if !urls.isEmpty { start { try await prepareFiles(urls) } }
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { chat.error = error.localizedDescription }
            }
        }
        .photosPicker(isPresented: $photos, selection: $selections, maxSelectionCount: max(1, 4 - chat.attachments.filter { $0.kind == .image }.count), matching: .images)
        .onChange(of: photos) { _, shown in
            if !shown, !selections.isEmpty {
                let selected = selections; selections = []
                start {
                    var inputs: [NativePreparedChatAttachment] = []
                    for item in selected {
                        try Task.checkCancellation()
                        guard let photo = try await item.loadTransferable(type: NativeChatPhoto.self) else { throw VaultFailure(message: "This photo could not be loaded. Try it again or choose its file in Files.") }
                        inputs.append(photo.prepared); try NativeChatAttachment.validateBatch(chat.attachments + inputs.map(\.descriptor))
                    }
                    return inputs
                }
            }
        }
        .sheet(item: $preview) { NativeFilePreview(lease: $0) }
        .confirmationDialog("Reset the saved attachment draft?", isPresented: $recover) {
            Button("Keep recovery copy and reset") { chat.recoverAttachmentDraft() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The unreadable saved record will be kept in a recovery copy. Your message text and conversations stay available.") }
        .onDisappear(perform: cancel)
    }
    private func prepareFiles(_ urls: [URL]) async throws -> [NativePreparedChatAttachment] {
        var inputs: [NativePreparedChatAttachment] = []
        for url in urls {
            try Task.checkCancellation(); inputs.append(try await NativePreparedChatAttachment.prepare(url))
            try NativeChatAttachment.validateBatch(chat.attachments + inputs.map(\.descriptor))
        }
        return inputs
    }
    private func start(_ prepare: @escaping @MainActor () async throws -> [NativePreparedChatAttachment]) {
        guard !busy, let id = chat.beginAttachmentImport() else { return }
        importID = id
        job = Task { @MainActor in
            defer { chat.cancelAttachmentImport(id); if importID == id { importID = nil; job = nil } }
            do {
                let inputs = try await prepare(); try Task.checkCancellation()
                guard vault.workspaceID == workspaceID, !vault.switchingVault, importID == id else { return }
                _ = try await chat.addAttachments(inputs, importID: id)
            } catch is CancellationError {} catch { if importID == id, vault.workspaceID == workspaceID { chat.error = error.localizedDescription } }
        }
    }
    private func cancel() {
        job?.cancel(); job = nil
        if let importID { chat.cancelAttachmentImport(importID); self.importID = nil }
    }
    private func show(_ item: NativeChatAttachment) {
        Task { do { let lease = try await chat.attachmentStore.preview(item); if vault.workspaceID == workspaceID { preview = lease } } catch { if vault.workspaceID == workspaceID { chat.error = error.localizedDescription } } }
    }
}
