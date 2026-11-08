import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Frozen representations delivered by the system Paste button, or by the
/// standard text-view paste action. No asynchronous stage rereads the clipboard.
struct NativeClipboardPayload: Sendable {
    var fragment: Data?
    var html: Data?
    var rtfd: Data?
    var rtf: Data?
    var text: String?
    var image: Data?
}

extension NativeClipboard {
    static var supportedTypes: [UTType] { [UTType(exportedAs: NativeClipboardFragment.type, conformingTo: .data), .html, .flatRTFD, .rtf, .plainText, .url, .image] }
    static func snapshot(_ board: UIPasteboard, source: Bool) throws -> NativeClipboardPayload {
        let count = board.changeCount
        var value = NativeClipboardPayload()
        if source { value.text = board.string }
        value.fragment = source && value.text != nil ? nil : board.data(forPasteboardType: NativeClipboardFragment.type)
        if value.fragment == nil, !source || value.text == nil {
            value.html = board.types.contains(UTType.html.identifier) ? board.data(forPasteboardType: UTType.html.identifier) : nil
            let needsRich = try value.html.map(NativeHTMLClipboard.needsCompanionAttachments) ?? true
            value.rtfd = needsRich && board.types.contains(UTType.flatRTFD.identifier) ? board.data(forPasteboardType: UTType.flatRTFD.identifier) : nil
            if needsRich, value.rtfd == nil, board.types.contains(UTType.rtf.identifier) { value.rtf = board.data(forPasteboardType: UTType.rtf.identifier) }
            if value.html == nil, value.rtfd == nil, value.rtf == nil, board.hasImages { value.image = board.image?.pngData() }
        }
        if value.text == nil, value.fragment == nil, value.html == nil { value.text = board.string }
        guard board.changeCount == count else { throw VaultFailure(message: "The clipboard changed while loading. Paste again to use the new selection.") }
        return value
    }
    static func payload(_ providers: [NSItemProvider], source: Bool) async throws -> NativeClipboardPayload {
        func provider(_ type: String) -> NSItemProvider? { providers.first { $0.registeredTypeIdentifiers.contains(type) } }
        func text() async throws -> String? {
            guard let item = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return nil }
            let bytes = try await NativeClipboardProviderRead.load { complete in
                item.loadObject(ofClass: NSString.self) { value, error in complete((value as? String).map { Data($0.utf8) }, error) }
            }
            return String(data: bytes, encoding: .utf8)
        }
        if source, let string = try await text() { return .init(text: string) }
        if let item = provider(NativeClipboardFragment.type) { return .init(fragment: try await NativeClipboardProviderRead.data(item, type: NativeClipboardFragment.type)) }
        if let item = provider(UTType.html.identifier) {
            let html = try await NativeClipboardProviderRead.data(item, type: UTType.html.identifier)
            var value = NativeClipboardPayload(html: html)
            if try NativeHTMLClipboard.needsCompanionAttachments(html) {
                if let companion = provider(UTType.flatRTFD.identifier) { value.rtfd = try await NativeClipboardProviderRead.data(companion, type: UTType.flatRTFD.identifier) }
                else if let companion = provider(UTType.rtf.identifier) { value.rtf = try await NativeClipboardProviderRead.data(companion, type: UTType.rtf.identifier) }
            }
            return value
        }
        var value = NativeClipboardPayload(text: try await text())
        if let item = provider(UTType.flatRTFD.identifier) { value.rtfd = try await NativeClipboardProviderRead.data(item, type: UTType.flatRTFD.identifier) }
        else if let item = provider(UTType.rtf.identifier) { value.rtf = try await NativeClipboardProviderRead.data(item, type: UTType.rtf.identifier) }
        else if let item = providers.first(where: { $0.registeredTypeIdentifiers.contains { UTType($0)?.conforms(to: .image) == true } }) {
            let type = item.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
            let bytes = try await NativeClipboardProviderRead.data(item, type: type)
            guard let image = UIImage(data: bytes), let png = image.pngData() else { throw VaultFailure(message: "The copied image could not be read.") }
            value.image = png
        }
        return value
    }
    static func htmlAttachments(_ payload: NativeClipboardPayload) -> [NativeHTMLClipboard.Attachment] {
        var result: [NativeHTMLClipboard.Attachment] = []
        for (bytes, format) in [(payload.rtfd, NSAttributedString.DocumentType.rtfd), (payload.rtf, .rtf)] {
            guard let bytes, bytes.count <= NativeClipboardFragment.limit,
                  let rich = try? NSAttributedString(data: bytes, options: [.documentType: format], documentAttributes: nil) else { continue }
            rich.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
                guard let attachment = value as? NSTextAttachment,
                      let name = attachment.fileWrapper?.preferredFilename ?? attachment.fileWrapper?.filename,
                      let data = attachment.fileWrapper?.regularFileContents ?? attachment.contents else { return }
                result.append(.init(name: (name as NSString).lastPathComponent, bytes: data))
            }
            break
        }
        return result
    }
}

private final class NativeClipboardProviderRead: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var progress: Progress?
    private var timeout: DispatchWorkItem?
    private var cancelled = false
    static func data(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await load(limit: type == NativeClipboardFragment.type ? NativeClipboardFragment.limit * 3 / 2 : NativeClipboardFragment.limit) { complete in provider.loadDataRepresentation(forTypeIdentifier: type, completionHandler: complete) }
    }
    static func load(limit: Int = NativeClipboardFragment.limit, _ start: @escaping (@escaping @Sendable (Data?, Error?) -> Void) -> Progress) async throws -> Data {
        let reader = NativeClipboardProviderRead()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in reader.start(start, limit: limit, continuation: continuation) }
        }, onCancel: { reader.cancel() })
    }
    private func start(_ start: (@escaping @Sendable (Data?, Error?) -> Void) -> Progress, limit: Int, continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(VaultFailure(message: "The clipboard took too long to load. Copy a smaller selection and try again."))) }
        self.timeout = timeout; lock.unlock()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 15, execute: timeout)
        let progress = start { [self] data, error in
            if let data, error == nil, data.count <= limit { finish(.success(data)) }
            else { finish(.failure(VaultFailure(message: data == nil || error != nil ? "The clipboard could not be read. Copy the selection again." : "Copy a clipboard selection smaller than 50 MB."))) }
        }
        let cancel = lock.withLock { () -> Bool in
            guard self.continuation != nil else { return true }
            self.progress = progress; return false
        }
        if cancel { progress.cancel() }
    }
    private func finish(_ result: Result<Data, Error>) {
        let state = lock.withLock { () -> (CheckedContinuation<Data, Error>?, Progress?, DispatchWorkItem?) in
            let state = (continuation, progress, timeout); continuation = nil; progress = nil; timeout = nil; return state
        }
        state.2?.cancel(); state.1?.cancel(); state.0?.resume(with: result)
    }
    private func cancel() { lock.withLock { cancelled = true }; finish(.failure(CancellationError())) }
}

/// UIKit delivers every representation of the granted clipboard item. SwiftUI's
/// menu PasteButton currently wraps only its preferred representation.
struct NativeClipboardPasteControl: UIViewRepresentable {
    var receive: ([NSItemProvider]) -> Void
    func makeUIView(context: Context) -> Recipient { Recipient(receive: receive) }
    func updateUIView(_ view: Recipient, context: Context) { view.receive = receive }
    final class Recipient: UIView {
        var receive: ([NSItemProvider]) -> Void
        init(receive: @escaping ([NSItemProvider]) -> Void) {
            self.receive = receive
            super.init(frame: .zero)
            pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: NativeClipboard.supportedTypes.map(\.identifier))
            let configuration = UIPasteControl.Configuration()
            configuration.displayMode = .iconAndLabel
            configuration.cornerStyle = .capsule
            let control = UIPasteControl(configuration: configuration)
            control.target = self
            control.accessibilityIdentifier = "clipboard.paste"
            control.translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
            NSLayoutConstraint.activate([control.centerXAnchor.constraint(equalTo: centerXAnchor), control.centerYAnchor.constraint(equalTo: centerYAnchor)])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func paste(itemProviders: [NSItemProvider]) { receive(itemProviders) }
        override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool { !itemProviders.isEmpty }
    }
}
struct NativeClipboardPasteSheet: View {
    @Environment(\.dismiss) private var dismiss
    var receive: ([NSItemProvider]) -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("Paste text, formatting, and images into your note.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    NativeClipboardPasteControl { receive($0); dismiss() }.frame(height: 56)
                }
                .padding(24).frame(maxWidth: .infinity)
            }
            .navigationTitle("Paste into note").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
