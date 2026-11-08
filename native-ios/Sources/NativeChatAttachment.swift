import Foundation
import CryptoKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import CoreTransferable

struct NativeChatAttachment: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case image, document }
    let id: UUID
    let name: String
    let kind: Kind
    let mediaType: String
    let sourceBytes: Int
    let bytes: Int
    let digest: String
    let textBytes: Int
    let textDigest: String?
    let width: Int?
    let height: Int?
    let pages: Int?
    static let fields: Set<String> = ["id", "name", "kind", "mediaType", "sourceBytes", "bytes", "digest", "textBytes", "textDigest", "width", "height", "pages"]
    var cost: Int { max(sourceBytes, textBytes) }
    var fileExtension: String { kind == .image ? "jpg" : mediaType == "application/pdf" ? "pdf" : "txt" }
    var valid: Bool {
        !name.isEmpty && name.utf8.count <= 1024 && !name.contains("/") && !name.contains("\\") && !name.unicodeScalars.contains(where: { $0.value < 32 }) &&
        (1...NativePreparedChatAttachment.fileLimit).contains(sourceBytes) && (1...NativePreparedChatAttachment.fileLimit).contains(bytes) &&
        Self.validHash(digest) && (kind == .image
            ? mediaType == "image/jpeg" && bytes <= 3 * 1024 * 1024 && textBytes == 0 && textDigest == nil && (1...1024).contains(width ?? 0) && (1...1024).contains(height ?? 0)
            : ["text/plain", "application/pdf"].contains(mediaType) && (1...NativePreparedChatAttachment.fileLimit).contains(textBytes) && Self.validHash(textDigest ?? ""))
    }
    static func validHash(_ text: String) -> Bool { text.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func validateBatch(_ items: [Self]) throws {
        guard items.allSatisfy(\.valid), Set(items.map(\.id)).count == items.count,
              items.filter({ $0.kind == .image }).count <= 4,
              items.reduce(0, { $0 + $1.cost }) <= 100 * 1024 * 1024 else {
            throw VaultFailure(message: "Choose up to four images and keep the combined file processing size under 100 MB.")
        }
    }
}

struct NativePreparedChatAttachment: Sendable {
    static let fileLimit = 50 * 1024 * 1024
    let descriptor: NativeChatAttachment
    let data: Data
    let text: Data?
    static func prepare(_ url: URL) async throws -> Self {
        do {
            return try await NativeCoordinatedRead<Self>().value(timeout: 120) { operation in
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                let coordinator = NSFileCoordinator()
                let bytes: Data = try operation.coordinating(coordinator) {
                    var coordinationError: NSError?, result: Result<Data, Error> = .failure(VaultFailure(message: "This file is unavailable. Choose it again in Files."))
                    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { selected in
                        result = Result {
                            try operation.check()
                            let values = try selected.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                            guard values.isRegularFile == true, values.isSymbolicLink != true, selected.resolvingSymlinksInPath().standardizedFileURL == canonical else { throw VaultFailure(message: "Choose an original document rather than a folder or link.") }
                            guard (values.fileSize ?? 0) <= fileLimit else { throw VaultFailure(message: "Files must be smaller than 50 MB.") }
                            let handle = try FileHandle(forReadingFrom: selected); defer { try? handle.close() }
                            var data = Data()
                            while let part = try handle.read(upToCount: 65536), !part.isEmpty {
                                try operation.check(); guard data.count + part.count <= fileLimit else { throw VaultFailure(message: "Files must be smaller than 50 MB.") }; data.append(part)
                            }
                            return data
                        }
                    }
                    if let coordinationError { throw coordinationError }; return try result.get()
                }
                try operation.check()
                return try prepare(bytes, name: url.lastPathComponent, check: operation.check)
            }
        } catch NativeCoordinatedReadFailure.timedOut { throw VaultFailure(message: "Preparing this file took too long. Check it in Files, or try fewer files.") }
    }
    static func prepare(_ bytes: Data, name originalName: String, check: () throws -> Void = {}) throws -> Self {
        guard !bytes.isEmpty, bytes.count <= fileLimit else { throw VaultFailure(message: "Choose a nonempty file smaller than 50 MB.") }
        let name = String(originalName.unicodeScalars.filter { $0.value >= 32 && $0 != "/" && $0 != "\\" }.prefix(240).map(String.init).joined())
        guard !name.isEmpty else { throw VaultFailure(message: "This file has no usable name.") }
        if let source = CGImageSourceCreateWithData(bytes as CFData, nil),
           let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String), type.conforms(to: .image) {
            try check()
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceShouldCacheImmediately: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), image.width > 0, image.height > 0,
                  let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw VaultFailure(message: "This image could not be prepared.") }
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(bounds); context.draw(image, in: bounds)
            guard let flattened = context.makeImage() else { throw VaultFailure(message: "This image could not be prepared.") }
            func jpeg(_ quality: Double) throws -> Data {
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw VaultFailure(message: "This image could not be prepared.") }
                CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw VaultFailure(message: "This image could not be prepared.") }; return data as Data
            }
            var data = try jpeg(0.82); if data.count > 3 * 1024 * 1024 { data = try jpeg(0.68) }
            guard data.count <= 3 * 1024 * 1024 else { throw VaultFailure(message: "The prepared image is too large. Choose a smaller image.") }
            try check()
            return .init(descriptor: .init(id: UUID(), name: name, kind: .image, mediaType: "image/jpeg", sourceBytes: bytes.count, bytes: data.count, digest: NativeChatAttachment.hash(data), textBytes: 0, textDigest: nil, width: image.width, height: image.height, pages: nil), data: data, text: nil)
        }
        var pages: Int?, text = Data(), media = "text/plain"
        if bytes.starts(with: Data("%PDF-".utf8)) {
            guard let pdf = PDFDocument(data: bytes), !pdf.isLocked else { throw VaultFailure(message: "This PDF could not be read. Unlock it before attaching it.") }
            pages = pdf.pageCount; media = "application/pdf"
            for index in 0..<pdf.pageCount {
                try check(); let page = Data((pdf.page(at: index)?.string ?? "").utf8)
                guard text.count + page.count + 2 <= fileLimit else { throw VaultFailure(message: "Extracted text exceeds the 50 MB processing limit.") }
                if index > 0 { text.append(Data("\n\n".utf8)) }; text.append(page)
            }
        } else {
            let value: String?
            if bytes.starts(with: [0xff, 0xfe]) { value = String(data: bytes.dropFirst(2), encoding: .utf16LittleEndian) }
            else if bytes.starts(with: [0xfe, 0xff]) { value = String(data: bytes.dropFirst(2), encoding: .utf16BigEndian) }
            else { value = String(data: bytes.starts(with: [0xef, 0xbb, 0xbf]) ? bytes.dropFirst(3) : bytes, encoding: .utf8) }
            guard let value, !value.unicodeScalars.contains(where: { $0.value < 9 || (13 < $0.value && $0.value < 32) }) else { throw VaultFailure(message: "This format cannot be read. Use a PDF, image or text-based file.") }
            text = Data(value.utf8)
        }
        guard text.count <= fileLimit, !String(decoding: text, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VaultFailure(message: "No readable text was found. Scanned PDFs need text recognition before attaching.") }
        try check()
        return .init(descriptor: .init(id: UUID(), name: name, kind: .document, mediaType: media, sourceBytes: bytes.count, bytes: bytes.count, digest: NativeChatAttachment.hash(bytes), textBytes: text.count, textDigest: NativeChatAttachment.hash(text), width: nil, height: nil, pages: pages), data: bytes, text: text)
    }
}

struct NativeChatPhoto: Transferable, Sendable {
    let prepared: NativePreparedChatAttachment
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let prepared = try await NativePreparedChatAttachment.prepare(received.file)
            guard prepared.descriptor.kind == .image else { throw VaultFailure(message: "Choose an image from Photos.") }
            return NativeChatPhoto(prepared: prepared)
        }
    }
}

struct NativeChatAttachmentStore: Sendable {
    let directory: URL
    var draftURL: URL { directory.appendingPathComponent("attachment-draft.json") }
    private struct Manifest: Codable { var version = 1; let attachment: NativeChatAttachment }
    private struct Draft: Codable { var version = 1; let items: [NativeChatAttachment] }
    private struct Grant: Codable { var version = 1; let run: UUID; let chat: String; let items: [NativeChatAttachment] }
    private func folder(_ attachment: NativeChatAttachment) -> URL { directory.appendingPathComponent("Attachments/" + attachment.id.uuidString.lowercased(), isDirectory: true) }
    private func file(_ attachment: NativeChatAttachment) -> URL { folder(attachment).appendingPathComponent("original." + attachment.fileExtension) }
    private func checked(_ url: URL) throws -> URL {
        let base = directory.standardizedFileURL.path + "/", canonicalRoot = directory.resolvingSymlinksInPath().standardizedFileURL
        guard url.standardizedFileURL.path.hasPrefix(base) else { throw VaultFailure(message: "This attachment snapshot is outside its private storage.") }
        let relative = String(url.standardizedFileURL.path.dropFirst(base.count)), canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard canonical == canonicalRoot.appendingPathComponent(relative).standardizedFileURL, values.isSymbolicLink != true, values.isRegularFile == true else { throw VaultFailure(message: "This attachment snapshot is unavailable or was replaced. Attach the original again.") }
        return canonical
    }
    private func metadata(_ url: URL, limit: Int) throws -> Data {
        let file = try checked(url)
        guard let count = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, (0...limit).contains(count) else { throw VaultFailure(message: "This saved attachment record is too large or unavailable. Its original is preserved.") }
        let data = try Data(contentsOf: file); guard data.count <= limit else { throw VaultFailure(message: "This saved attachment record changed. Its original is preserved.") }; return data
    }
    func manifest(_ item: NativeChatAttachment) throws {
        guard item.valid else { throw VaultFailure(message: "This saved attachment uses an unsupported format.") }
        let bytes = try metadata(folder(item).appendingPathComponent("manifest.json"), limit: 16384)
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], Set(object.keys) == ["version", "attachment"],
              let fields = object["attachment"] as? [String: Any], Set(fields.keys).isSubset(of: NativeChatAttachment.fields), let value = try? JSONDecoder().decode(Manifest.self, from: bytes), value.version == 1, value.attachment == item else { throw VaultFailure(message: "This saved attachment changed. Attach the original again.") }
    }
    func read(_ item: NativeChatAttachment, text: Bool = false) throws -> Data {
        try manifest(item)
        let url = try checked(text ? folder(item).appendingPathComponent("text.txt") : file(item)), expected = text ? item.textBytes : item.bytes
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == expected, expected <= NativePreparedChatAttachment.fileLimit else { throw VaultFailure(message: "This attachment snapshot changed. Attach it again.") }
        let data = try Data(contentsOf: url)
        guard data.count == expected, NativeChatAttachment.hash(data) == (text ? item.textDigest : item.digest) else { throw VaultFailure(message: "This attachment snapshot changed. Attach it again.") }; return data
    }
    func commit(_ inputs: [NativePreparedChatAttachment]) async throws -> [NativeChatAttachment] {
        try NativeChatAttachment.validateBatch(inputs.map(\.descriptor))
        let store = self
        let worker = Task.detached(priority: .userInitiated) {
            var completed: [NativeChatAttachment] = []
            do {
                for input in inputs {
                    try Task.checkCancellation(); let item = input.descriptor
                    guard input.data.count == item.bytes, NativeChatAttachment.hash(input.data) == item.digest,
                          (input.text?.count ?? 0) == item.textBytes, input.text.map(NativeChatAttachment.hash) == item.textDigest else { throw VaultFailure(message: "The prepared attachment changed. Choose it again.") }
                    let parent = store.directory.appendingPathComponent("Attachments", isDirectory: true)
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                    let temporary = parent.appendingPathComponent("." + UUID().uuidString), target = store.folder(item)
                    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
                    do {
                        try input.data.write(to: temporary.appendingPathComponent("original." + item.fileExtension), options: .atomic)
                        if let text = input.text { try text.write(to: temporary.appendingPathComponent("text.txt"), options: .atomic) }
                        try JSONEncoder().encode(Manifest(attachment: item)).write(to: temporary.appendingPathComponent("manifest.json"), options: .atomic)
                        try Task.checkCancellation(); try FileManager.default.moveItem(at: temporary, to: target); completed.append(item)
                    } catch { try? FileManager.default.removeItem(at: temporary); throw error }
                }
                return completed
            } catch { for item in completed { store.discardUnreferenced(item) }; throw error }
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
    func retain(_ item: NativeChatAttachment) throws {
        _ = try read(item)
        try Data("Retained by a sent conversation or run.".utf8).write(to: folder(item).appendingPathComponent("retained"), options: .atomic)
    }
    func discardUnreferenced(_ item: NativeChatAttachment) {
        guard (try? manifest(item)) != nil, (try? read(item)) != nil,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder(item).path),
              Set(names) == Set(["manifest.json", "original." + item.fileExtension] + (item.kind == .document ? ["text.txt"] : [])),
              item.kind == .image || (try? read(item, text: true)) != nil else { return }
        try? FileManager.default.removeItem(at: folder(item))
    }
    func loadDraft() throws -> (Data?, [NativeChatAttachment]) {
        guard FileManager.default.fileExists(atPath: draftURL.path) else { return (nil, []) }
        let bytes = try metadata(draftURL, limit: 1_000_000)
        guard bytes.count <= 1_000_000, let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], Set(object.keys) == ["version", "items"],
              let items = object["items"] as? [[String: Any]], items.allSatisfy({ Set($0.keys).isSubset(of: NativeChatAttachment.fields) }), let draft = try? JSONDecoder().decode(Draft.self, from: bytes), draft.version == 1 else { throw VaultFailure(message: "The saved attachment draft uses an unreadable or newer format. Its original file is preserved.") }
        try NativeChatAttachment.validateBatch(draft.items); return (bytes, draft.items)
    }
    func saveDraft(_ items: [NativeChatAttachment], expected: Data?) throws -> Data {
        try NativeChatAttachment.validateBatch(items)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let current = FileManager.default.fileExists(atPath: draftURL.path) ? try Data(contentsOf: draftURL) : nil
        guard current == expected else { throw VaultFailure(message: "This attachment draft changed in another session. Reopen Ask before changing it.") }
        if current != nil { _ = try loadDraft() }
        let bytes = try JSONEncoder().encode(Draft(items: items)); guard bytes.count <= 1_000_000 else { throw VaultFailure(message: "There are too many attachment records in this message. Choose fewer files.") }; try bytes.write(to: draftURL, options: .atomic); return bytes
    }
    func recoverDraft() throws {
        let bytes = try Data(contentsOf: draftURL), destination = directory.appendingPathComponent("RecoveredAttachmentDrafts", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try bytes.write(to: destination.appendingPathComponent(UUID().uuidString.lowercased() + ".json"), options: .atomic)
        try JSONEncoder().encode(Draft(items: [])).write(to: draftURL, options: .atomic)
    }
    func authorize(run: UUID, chat: String, items: [NativeChatAttachment]) throws {
        let parent = directory.appendingPathComponent("AttachmentRunInputs", isDirectory: true), url = parent.appendingPathComponent(run.uuidString.lowercased() + ".json")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw VaultFailure(message: "This run already has frozen attachment inputs.") }
        let bytes = try JSONEncoder().encode(Grant(run: run, chat: chat, items: items)); guard bytes.count <= 1_000_000 else { throw VaultFailure(message: "There are too many attachment records for this run. Choose fewer files.") }; try bytes.write(to: url, options: .atomic)
    }
    func validate(run: UUID, chat: String, items: [NativeChatAttachment]) throws {
        guard !items.isEmpty else { return }
        let url = directory.appendingPathComponent("AttachmentRunInputs/" + run.uuidString.lowercased() + ".json")
        let bytes = try metadata(url, limit: 1_000_000)
        guard bytes.count <= 1_000_000, let grant = try? JSONDecoder().decode(Grant.self, from: bytes), grant.version == 1, grant.run == run, grant.chat == chat, grant.items == items else { throw VaultFailure(message: "The frozen attachment inputs for this run are unavailable or changed. Reattach them in a new request.") }
    }
    func preview(_ item: NativeChatAttachment) async throws -> NativeFileLease {
        let store = self
        return try await Task.detached(priority: .userInitiated) {
            let bytes = try store.read(item), temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ZerusAttachment-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            do {
                let url = temporary.appendingPathComponent((item.name as NSString).deletingPathExtension + "." + item.fileExtension)
                try bytes.write(to: url, options: .atomic); return try NativeFileLease(scope: url, locatedOnDevice: true, temporaryDirectory: temporary)
            } catch { try? FileManager.default.removeItem(at: temporary); throw error }
        }.value
    }
}
