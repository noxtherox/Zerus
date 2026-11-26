import ZerusMarkdown
import AppKit
import SwiftUI
import Markdown
import SwiftSoup
import ImageIO
import UniformTypeIdentifiers

typealias MacInlineImage = NativeImageMarkup
extension NativeImageMarkup {
    func size(for image: NSImage) -> NSSize {
        let value = displaySize(naturalWidth: image.size.width, naturalHeight: image.size.height)
        return NSSize(width: value.width, height: value.height)
    }
}

extension NSAttributedString.Key { static let macImageUnavailable = Self("ZerusMacImageUnavailable") }

enum MacUnavailableImage {
    static func image(caption: String) -> NSImage {
        let size = NSSize(width: 300, height: 44)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.quaternaryLabelColor.setFill(); NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?.draw(in: NSRect(x: 12, y: 13, width: 20, height: 18))
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
            ("Image unavailable · " + caption.replacingOccurrences(of: "\n", with: " ") as NSString).draw(in: NSRect(x: 42, y: 13, width: 246, height: 19), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
            return true
        }
        image.accessibilityDescription = "Image unavailable: " + caption
        return image
    }
}

final class MacImageAttachment: NSTextAttachment {
    init(image: NSImage, size: NSSize) { super.init(data: nil, ofType: nil); self.image = image; bounds = NSRect(origin: .zero, size: size) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let available = max(1, lineFrag.width - (textContainer?.lineFragmentPadding ?? 0) * 2)
        let scale = min(1, available / max(1, bounds.width), 1000 / max(1, bounds.height))
        return NSRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale)
    }
}

struct MacImageEditRequest {
    let range: NSRange
    let literal: String
    let baseline: String
    let token: UUID
    let value: MacInlineImage
    let image: NSImage
}

struct MacImageEditView: View {
    let request: MacImageEditRequest
    let apply: (MacInlineImage) throws -> Void
    let cancel: () -> Void
    @State private var reference: String
    @State private var caption: String
    @State private var title: String
    @State private var width: String
    @State private var height: String
    @State private var keepRatio: Bool
    @State private var issue: String?
    init(request: MacImageEditRequest, apply: @escaping (MacInlineImage) throws -> Void, cancel: @escaping () -> Void) {
        self.request = request; self.apply = apply; self.cancel = cancel
        _reference = State(initialValue: request.value.reference); _caption = State(initialValue: request.value.caption); _title = State(initialValue: request.value.title)
        _width = State(initialValue: request.value.width.map(String.init) ?? ""); _height = State(initialValue: request.value.height.map(String.init) ?? "")
        _keepRatio = State(initialValue: request.value.height == nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { SwiftUI.Text("Edit image").macFont(.title2.bold()); Spacer() }
            Image(nsImage: request.image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 140)
            Form {
                TextField("Image address", text: $reference)
                TextField("Description", text: $caption)
                TextField("Title", text: $title)
                HStack { TextField("Width", text: $width).accessibilityLabel("Image width"); SwiftUI.Text("px"); TextField("Height", text: $height).disabled(keepRatio).accessibilityLabel("Image height"); SwiftUI.Text("px") }
                Toggle("Keep aspect ratio", isOn: $keepRatio)
                SwiftUI.Text("Leave size blank for automatic sizing. The original image file is kept.").macFont(.caption).foregroundStyle(.secondary)
            }
            if let issue { SwiftUI.Text(issue).macFont(.caption).foregroundStyle(.red) }
            HStack {
                Button("Automatic size") { width = ""; height = ""; keepRatio = true }
                Spacer(); Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Apply") {
                    do { let value = try MacInlineImage(reference: reference, caption: caption, title: title, width: MacInlineImage.dimension(width), height: keepRatio ? nil : MacInlineImage.dimension(height)).validated(); try apply(value) }
                    catch { issue = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 580, height: 520)
    }
}

struct MacImagePixels: @unchecked Sendable {
    let image: CGImage
    static func decode(_ bytes: Data, maximumPixel: Int) throws -> Self {
        guard !bytes.isEmpty, bytes.count <= 50 * 1024 * 1024 else { throw VaultFailure(message: "Choose a supported image up to 50 MB.") }
        let prefix = String(decoding: bytes.prefix(16_384), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
        if prefix.range(of: #"(?is)^(?:<\?xml[^>]*>\s*)?(?:<!--.*?-->\s*)*<svg\b"#, options: .regularExpression) != nil {
            guard let image = NSImage(data: bytes), image.size.width.isFinite, image.size.height.isFinite,
                  image.size.width > 0, image.size.height > 0, image.size.width <= 16_384, image.size.height <= 16_384,
                  image.size.width * image.size.height <= 40_000_000 else { throw VaultFailure(message: "Choose a supported image up to 40 megapixels and 16,384 pixels per side.") }
            let scale = min(1, CGFloat(maximumPixel) / max(image.size.width, image.size.height))
            let width = max(1, Int((image.size.width * scale).rounded())), height = max(1, Int((image.size.height * scale).rounded()))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw VaultFailure(message: "This image could not be decoded.") }
            NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
            guard let raster = context.makeImage() else { throw VaultFailure(message: "This image could not be decoded.") }
            return .init(image: raster)
        }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0, width.intValue <= 16_384, height.intValue <= 16_384,
              width.intValue * height.intValue <= 40_000_000 else { throw VaultFailure(message: "Choose a supported image up to 50 MB, 40 megapixels and 16,384 pixels per side.") }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maximumPixel, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw VaultFailure(message: "This image could not be decoded.") }
        return .init(image: image)
    }
}

struct MacImageFile: @unchecked Sendable {
    let name: String
    let bytes: Data
    let preview: MacImagePixels
    static func read(_ url: URL) async throws -> Self {
        let result = try await Task.detached(priority: .userInitiated) {
            let lease = try NativeFileLease(scope: url), bytes = try lease.readForCopy()
            return Self(name: MacClipboard.importName(url.lastPathComponent), bytes: bytes, preview: try MacImagePixels.decode(bytes, maximumPixel: 512))
        }.value
        try Task.checkCancellation(); return result
    }
}

/// In-memory previews only. Original URLs remain in Markdown and no downloaded
/// image is written to the vault. Rendering does not share cookies or logins.
actor MacRemoteImageStore {
    static let shared = MacRemoteImageStore()
    private struct Cached { let pixels: MacImagePixels; let expires: Date; let cost: Int; let reference: String }
    private var cached: [String: Cached] = [:]
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }
    func forget(_ reference: String) { cached = cached.filter { $0.value.reference != reference } }
    func load(_ reference: String, maximumPixel: Int) async throws -> MacImagePixels {
        try Task.checkCancellation()
        let cap = min(2048, max(128, maximumPixel)), key = reference + "\n" + String(cap)
        cached = cached.filter { $0.value.expires > Date() }
        if let hit = cached[key] { return hit.pixels }
        guard let url = MacWebAddress.foundationURL(reference), let scheme = URL(string: reference)?.scheme?.lowercased(), ["http", "https"].contains(scheme) else { throw VaultFailure(message: "Use an http or https image URL.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false; request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (stream, response) = try await session.bytes(for: request)
        defer { stream.task.cancel() }
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              ["http", "https"].contains(response.url?.scheme?.lowercased() ?? ""),
              response.expectedContentLength <= 50 * 1024 * 1024 else { throw VaultFailure(message: "The remote image is unavailable or larger than 50 MB.") }
        var bytes = Data(), chunk: [UInt8] = []; chunk.reserveCapacity(16_384)
        for try await byte in stream {
            chunk.append(byte)
            if chunk.count == 16_384 {
                try Task.checkCancellation()
                guard bytes.count + chunk.count <= 50 * 1024 * 1024 else { throw VaultFailure(message: "The remote image is larger than 50 MB.") }
                bytes.append(contentsOf: chunk); chunk.removeAll(keepingCapacity: true)
            }
        }
        try Task.checkCancellation()
        guard bytes.count + chunk.count <= 50 * 1024 * 1024 else { throw VaultFailure(message: "The remote image is larger than 50 MB.") }
        bytes.append(contentsOf: chunk)
        let pixels = try MacImagePixels.decode(bytes, maximumPixel: cap)
        let control = response.value(forHTTPHeaderField: "Cache-Control")?.lowercased() ?? ""
        if !control.contains("no-store"), !control.contains("no-cache") {
            var lifetime = 60.0
            if let match = control.range(of: #"max-age\s*=\s*[0-9]+"#, options: .regularExpression), let value = Double(control[match].split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "") { lifetime = min(300, value) }
            let cost = pixels.image.bytesPerRow * pixels.image.height
            while cached.count >= 64 || cached.values.reduce(0, { $0 + $1.cost }) + cost > 64 * 1024 * 1024 {
                guard let oldest = cached.min(by: { $0.value.expires < $1.value.expires })?.key else { break }
                cached.removeValue(forKey: oldest)
            }
            if lifetime > 0, cost <= 64 * 1024 * 1024 { cached[key] = Cached(pixels: pixels, expires: Date().addingTimeInterval(lifetime), cost: cost, reference: reference) }
        }
        return pixels
    }
}

struct MacImageInsertRequest {
    let baseline: String
    let token: UUID
    let range: NSRange
}
struct MacImageInsertView: View {
    let apply: (MacInlineImage, MacImageFile?) async throws -> Void
    let chooseProject: (() async -> Void)?
    let cancel: () -> Void
    @State private var fromFile = false
    @State private var file: MacImageFile?
    @State private var reference = ""
    @State private var caption = ""
    @State private var title = ""
    @State private var width = ""
    @State private var height = ""
    @State private var keepRatio = true
    @State private var busy = false
    @State private var operation: Task<Void, Never>?
    @State private var issue: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SwiftUI.Text("Insert image").macFont(.headline)
            Picker("Image source", selection: $fromFile) { SwiftUI.Text("Image address").tag(false); SwiftUI.Text("Local file").tag(true) }.pickerStyle(.segmented).disabled(busy)
            if fromFile {
                HStack { Button("Choose image…") { chooseFile() }.disabled(busy); SwiftUI.Text(file?.name ?? "No image selected").macFont(.caption).lineLimit(1) }
                if let file { Image(nsImage: NSImage(cgImage: file.preview.image, size: .zero)).resizable().scaledToFit().frame(height: 120) }
                if let chooseProject { Button("Choose project folder…") { busy = true; operation = Task { await chooseProject(); busy = false } }.disabled(busy) }
            } else { TextField("Image address", text: $reference).focused($focused).disabled(busy) }
            TextField("Description", text: $caption).disabled(busy)
            TextField("Title", text: $title).disabled(busy)
            HStack { TextField("Width", text: $width).accessibilityLabel("Image width"); TextField("Height", text: $height).disabled(keepRatio).accessibilityLabel("Image height") }.disabled(busy)
            Toggle("Keep aspect ratio", isOn: $keepRatio).disabled(busy)
            SwiftUI.Text("Leave size blank for automatic sizing. Local files are copied only when you insert the image.").macFont(.caption).foregroundStyle(.secondary)
            if let issue { SwiftUI.Text(issue).macFont(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Spacer(); if busy { ProgressView().controlSize(.small) }; Button("Cancel") { operation?.cancel(); cancel() }.keyboardShortcut(.cancelAction)
                Button("Insert image") {
                    do {
                        guard !fromFile || file != nil else { throw VaultFailure(message: "Choose an image file first.") }
                        let value = try MacInlineImage(reference: fromFile ? "assets/pending-image" : reference, caption: caption, title: title, width: MacInlineImage.dimension(width), height: keepRatio ? nil : MacInlineImage.dimension(height)).validated()
                        busy = true; operation = Task {
                            defer { busy = false }
                            do { try await apply(value, fromFile ? file : nil) } catch { issue = error.localizedDescription }
                        }
                    } catch { issue = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(busy)
            }
        }.padding(24).frame(width: 580).task { focused = true }.onDisappear { operation?.cancel() }
    }
    private func chooseFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; operation = Task {
            defer { busy = false }
            do { file = try await MacImageFile.read(url); issue = nil } catch { issue = error.localizedDescription }
        }
    }
}
