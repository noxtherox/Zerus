import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Snapshot pasteboard values before asynchronous preparation: never reread a
/// user's later clipboard and never interpret a text URL as an attachment.
enum MacChatAttachmentInput: Sendable {
    case file(URL)
    case image(Data, String)
    @MainActor static func read(_ board: NSPasteboard) throws -> [Self]? {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            guard urls.count <= 104 else { throw VaultFailure(message: "Choose up to four images and 100 documents per message.") }
            return urls.map(Self.file)
        }
        var inputs: [Self] = [], size = 0
        for item in board.pasteboardItems ?? [] {
            guard let type = item.types.first(where: { UTType($0.rawValue)?.conforms(to: .image) == true }), let bytes = item.data(forType: type) else { continue }
            size += bytes.count
            guard bytes.count <= 50 * 1024 * 1024, size <= MacChatDocument.totalLimit, inputs.count < 4 else { throw VaultFailure(message: "Paste up to four images below 50 MB each and 100 MB total.") }
            let ext = UTType(type.rawValue)?.preferredFilenameExtension ?? "png"
            inputs.append(.image(bytes, "Pasted image.\(ext)"))
        }
        return inputs.isEmpty ? nil : inputs
    }
    @MainActor static func read(_ providers: [NSItemProvider]) async throws -> [Self] {
        guard providers.count <= 104 else { throw VaultFailure(message: "Choose up to four images and 100 documents per message.") }
        var inputs: [Self] = [], total = 0
        for provider in providers {
            try Task.checkCancellation()
            let isFile = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            guard let type = isFile ? UTType.fileURL.identifier : provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { throw VaultFailure(message: "Drop local images, PDF or text files.") }
            let bytes = try await MacChatDropRead().value(provider, type: type)
            if isFile {
                guard let url = URL(dataRepresentation: bytes, relativeTo: nil), url.isFileURL else { throw VaultFailure(message: "The dropped file is unavailable. Choose it through the file picker.") }
                inputs.append(.file(url))
            } else {
                total += bytes.count
                guard bytes.count <= MacChatDocument.fileLimit, total <= MacChatDocument.totalLimit else { throw VaultFailure(message: "The dropped images exceed the attachment processing budget.") }
                let ext = UTType(type)?.preferredFilenameExtension ?? "png"
                inputs.append(.image(bytes, provider.suggestedName ?? "Dropped image.\(ext)"))
            }
        }
        try Task.checkCancellation(); return inputs
    }
    static func prepare(_ inputs: [Self], imageCount: Int, documentCount: Int, documentBytes: Int) async throws -> (images: [MacChatImage], documents: [MacChatDocument]) {
        guard inputs.count <= 104 else { throw VaultFailure(message: "Choose up to four images and 100 documents per message.") }
        var images: [MacChatImage] = [], documents: [MacChatDocument] = [], total = 0
        for input in inputs {
            try Task.checkCancellation()
            switch input {
            case .image(let bytes, let name):
                guard imageCount + images.count < 4 else { throw VaultFailure(message: "Choose up to four images per message.") }
                total += bytes.count
                guard total <= MacChatDocument.totalLimit else { throw VaultFailure(message: "The attachment batch exceeds 100 MB. Send separate batches.") }
                let worker = NativeCoordinatedRead<MacChatImage>()
                let image = try await worker.value(timeout: 120) { worker in try worker.check(); return try MacChatImage.prepare(bytes, name: name) }
                images.append(image)
            case .file(let url):
                guard url.isFileURL else { throw VaultFailure(message: "Choose local files; web addresses can be pasted as text.") }
                let worker = NativeCoordinatedRead<(Bool, Int)>()
                let (image, size) = try await worker.value(timeout: 120) { worker in
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try worker.check()
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
                    guard values.isRegularFile == true, let size = values.fileSize, size <= MacChatDocument.fileLimit else { throw VaultFailure(message: "\(url.lastPathComponent): choose a regular file below 50 MB.") }
                    return (values.contentType?.conforms(to: .image) == true || UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true, size)
                }
                total += size
                guard total <= MacChatDocument.totalLimit else { throw VaultFailure(message: "The attachment batch exceeds 100 MB. Send separate batches.") }
                if image {
                    guard imageCount + images.count < 4 else { throw VaultFailure(message: "Choose up to four images per message.") }
                    let reader = NativeCoordinatedRead<MacChatImage>()
                    let prepared = try await reader.value(timeout: 120) { reader in
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let coordinator = NSFileCoordinator()
                        return try reader.coordinating(coordinator) {
                            var result: Result<MacChatImage, Error>?, failure: NSError?
                            coordinator.coordinate(readingItemAt: url, options: [], error: &failure) { file in result = Result { try reader.check(); return try MacChatImage.prepare(file) } }
                            if let failure { throw failure }
                            guard let result else { throw VaultFailure(message: "The image is unavailable.") }; return try result.get()
                        }
                    }
                    images.append(prepared)
                } else {
                    guard documentCount + documents.count < 100 else { throw VaultFailure(message: "Choose up to 100 documents per message.") }
                    documents.append(try await MacChatDocument.prepare(url))
                }
            }
            guard documentBytes + documents.reduce(0, { $0 + $1.text.utf8.count }) <= MacChatDocument.totalLimit else { throw VaultFailure(message: "The document selection exceeds 100 MB. Send separate batches.") }
        }
        try Task.checkCancellation()
        return (images, documents)
    }
}

struct MacChatComposer: NSViewRepresentable {
    @Binding var text: String
    var enabled: Bool
    var acceptsAttachments: Bool
    var textColor: NSColor = .labelColor
    var attach: ([MacChatAttachmentInput]) -> Void
    var issue: (String) -> Void
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(), view = MacChatTextView()
        scroll.hasVerticalScroller = true; scroll.borderType = .noBorder; scroll.drawsBackground = false; scroll.autohidesScrollers = true
        view.isRichText = false; view.allowsUndo = true; view.font = .systemFont(ofSize: 13); view.textContainerInset = NSSize(width: 0, height: 0); view.drawsBackground = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true; view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel("Ask about your notes…")
        view.delegate = context.coordinator; view.registerForDraggedTypes([.fileURL, .png, .tiff])
        scroll.documentView = view; update(view); return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.parent = self; if let view = scroll.documentView as? MacChatTextView { update(view) } }
    private func update(_ view: MacChatTextView) {
        if view.string != text, !view.hasMarkedText() { let selection = view.selectedRange(); view.string = text; view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0)) }
        view.textColor = textColor; view.insertionPointColor = textColor; view.isEditable = enabled; view.acceptsAttachments = acceptsAttachments; view.attach = attach; view.issue = issue
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let view = scroll.documentView as? MacChatTextView { view.delegate = nil; view.attach = nil; view.issue = nil }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacChatComposer
        init(_ parent: MacChatComposer) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.text = view.string } }
    }
}
final class MacChatTextView: NSTextView {
    var acceptsAttachments = false
    var attach: (([MacChatAttachmentInput]) -> Void)?
    var issue: ((String) -> Void)?
    private func consume(_ board: NSPasteboard) -> Bool {
        do {
            guard let inputs = try MacChatAttachmentInput.read(board) else { return false }
            guard isEditable, acceptsAttachments else { issue?("Finish the current operation in a writable conversation before adding attachments."); return true }
            attach?(inputs); return true
        } catch { issue?(error.localizedDescription); return true }
    }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.fileURL, .png, .tiff, .init(UTType.jpeg.identifier), .init(UTType.heic.identifier)] + super.readablePasteboardTypes }
    override func readSelection(from board: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .fileURL || UTType(type.rawValue)?.conforms(to: .image) == true { return consume(board) }
        return super.readSelection(from: board, type: type)
    }
    override func paste(_ sender: Any?) { if !consume(.general) { super.paste(sender) } }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.availableType(from: [.fileURL, .png, .tiff]) != nil { return isEditable && acceptsAttachments ? .copy : [] }
        return super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { consume(sender.draggingPasteboard) || super.performDragOperation(sender) }
}

/// Item-provider callbacks can outlive a drag or never finish. Cancellation and
/// timeout release the composer promptly; a late callback cannot attach data.
private final class MacChatDropRead: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var result: Result<Data, Error>?
    private var progress: Progress?
    private func finish(_ result: Result<Data, Error>) {
        lock.lock(); guard self.result == nil else { lock.unlock(); return }
        self.result = result; let continuation = continuation, progress = progress
        self.continuation = nil; self.progress = nil; lock.unlock()
        if case .failure = result { progress?.cancel() }
        continuation?.resume(with: result)
    }
    func value(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock(); if let result { lock.unlock(); continuation.resume(with: result); return }
                self.continuation = continuation; lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + 120) { [weak self] in self?.finish(.failure(VaultFailure(message: "The dropped attachment timed out. Choose it again when its provider is available."))) }
                let progress = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    if let error { self.finish(.failure(error)) }
                    else if let data { self.finish(.success(data)) }
                    else { self.finish(.failure(VaultFailure(message: "The dropped attachment could not be read."))) }
                }
                lock.lock(); if result == nil { self.progress = progress; lock.unlock() } else { lock.unlock(); progress.cancel() }
            }
        }, onCancel: { self.finish(.failure(CancellationError())) })
    }
}
