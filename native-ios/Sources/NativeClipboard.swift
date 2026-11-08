import UIKit
import UniformTypeIdentifiers
import CryptoKit
import ImageIO

struct NativeClipboardFragment: Codable, Sendable {
    struct Resource: Codable, Sendable {
        let reference: String
        let path: String?
        let name: String
        let bytes: Data?
    }
    static let type = "com.zerus.notes.markdown-fragment"
    static let limit = 50 * 1024 * 1024
    let version: Int
    let markdown: String
    let vault: String?
    let resources: [Resource]

    init(markdown: String, vault: String? = nil, resources: [Resource] = []) {
        version = 1; self.markdown = markdown; self.vault = vault; self.resources = resources
    }
    var includesLocalResources: Bool {
        Set(MarkdownResources.localReferences(in: markdown)).isSubset(of: Set(resources.map(\.reference))) &&
        Set(resources.map(\.reference)).isSubset(of: Set(MarkdownResources.localReferences(in: markdown, includeNoteFiles: true))) && resources.allSatisfy { $0.bytes != nil }
    }
    func validate() throws {
        guard version == 1, markdown.utf8.count <= Self.limit, resources.count <= 1000,
              resources.reduce(markdown.utf8.count, { $0 + ($1.bytes?.count ?? 0) }) <= Self.limit,
              Set(resources.map(\.reference)).count == resources.count else {
            throw VaultFailure(message: "This clipboard selection is too large or uses an unsupported format.")
        }
        let actual = Set(MarkdownResources.localReferences(in: markdown, includeNoteFiles: true))
        guard resources.allSatisfy({ actual.contains($0.reference) }) else { throw VaultFailure(message: "The clipboard attachment references are invalid.") }
    }
    static func decode(_ data: Data) throws -> NativeClipboardFragment {
        guard data.count <= limit * 3 / 2 else { throw VaultFailure(message: "This clipboard selection is too large.") }
        let fragment = try JSONDecoder().decode(Self.self, from: data)
        try fragment.validate(); return fragment
    }
    static func vaultID(_ root: URL) -> String {
        SHA256.hash(data: Data(root.standardizedFileURL.resolvingSymlinksInPath().path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class NativeCopyOperation {
    var task: Task<Void, Never>?
    var finished = false
    var written = false
    var failure: String?
}

@MainActor
enum NativeClipboard {
    private(set) static var latestCopy: NativeCopyOperation?
    static var pendingCopy: NativeCopyOperation? { latestCopy.flatMap { $0.finished ? nil : $0 } }
    static func beginCopy() -> NativeCopyOperation {
        latestCopy?.task?.cancel()
        let operation = NativeCopyOperation(); latestCopy = operation; return operation
    }
    static func isCurrentCopy(_ operation: NativeCopyOperation) -> Bool { latestCopy === operation }
    static func finishCopy(_ operation: NativeCopyOperation) { operation.finished = true; operation.task = nil }
    static func selection(_ text: NSAttributedString, range: NSRange) -> NSAttributedString {
        let selected = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
        if range.length > 0, (text.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 0)).location != range.location {
            let first = (selected.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            selected.addAttribute(.zerusBlock, value: "", range: first)
        }
        return selected
    }

    static func importRich(_ value: NSAttributedString) throws -> NativeClipboardFragment {
        let rich = NSMutableAttributedString(attributedString: value)
        var resources: [NativeClipboardFragment.Resource] = []
        rich.addAttribute(.zerusBlock, value: "", range: NSRange(location: 0, length: rich.length))
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
            if let link = attributes[.link] as? String, let url = URL(string: link) { rich.addAttribute(.link, value: url, range: range) }
            for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle] where (attributes[key] as? NSNumber)?.intValue == 0 { rich.removeAttribute(key, range: range) }
        }
        var failure: Error?
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { item, range, _ in
            guard let attachment = item as? NSTextAttachment else { return }
            let contents = attachment.fileWrapper?.regularFileContents ?? attachment.contents ?? attachment.image?.pngData()
            guard let bytes = contents else { failure = VaultFailure(message: "A pasted attachment could not be read. Your note is unchanged; paste plain text or source instead."); return }
            let image = UIImage(data: bytes) != nil || attachment.image != nil
            let name = attachment.fileWrapper?.preferredFilename ?? (image ? "Image.png" : "Attachment")
            let reference = "assets/clipboard-" + UUID().uuidString.lowercased()
            let label = name.replacingOccurrences(of: #"([\\\[\]])"#, with: #"\\$1"#, options: .regularExpression)
            rich.addAttribute(.zerusImageMarkdown, value: (image ? "!" : "") + "[" + label + "](" + reference + ")", range: range)
            resources.append(.init(reference: reference, path: nil, name: name, bytes: bytes))
        }
        if let failure { throw failure }
        let markdown = MarkdownText.serialize(rich)
        guard !markdown.contains("\u{fffc}") else { throw VaultFailure(message: "This rich text includes an unsupported attachment. Paste plain text or source to keep its available text.") }
        let fragment = NativeClipboardFragment(markdown: markdown, resources: resources)
        try fragment.validate(); return fragment
    }

    static func insertion(_ value: NSAttributedString, into original: NSAttributedString, range: NSRange) -> NSAttributedString {
        let text = value.string as NSString
        guard text.length > 0 else { return value }
        var first = 0, last = text.length - 1
        while first < text.length && [10, 13].contains(text.character(at: first)) { first += 1 }
        while last >= 0 && [10, 13].contains(text.character(at: last)) { last -= 1 }
        guard first < text.length, last >= 0 else { return value }
        func block(_ index: Int) -> Bool {
            value.attribute(.zerusRichBlockMarkdown, at: index, effectiveRange: nil) != nil || !(value.attribute(.zerusBlock, at: index, effectiveRange: nil) as? String ?? "").isEmpty
        }
        let full = original.string as NSString
        let before = full.substring(to: range.location), after = full.substring(from: NSMaxRange(range))
        func normalized(_ string: String) -> String { string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
        let beforeLines = normalized(before).reversed().prefix(while: { $0 == "\n" }).count
        let afterLines = normalized(after).prefix(while: { $0 == "\n" }).count
        let firstLines = normalized(text.substring(to: first)).count
        let lastLines = normalized(text.substring(from: last + 1)).count
        let leading = block(first) && !before.isEmpty ? max(0, 2 - firstLines - beforeLines) : 0
        let trailing = block(last) ? max(0, 2 - lastLines - afterLines) : 0
        let attributes: [NSAttributedString.Key: Any] = [.font: MarkdownText.font(), .foregroundColor: UIColor.label, .zerusBlock: "", .paragraphStyle: MarkdownText.paragraphStyle(prefix: "")]
        let result = NSMutableAttributedString(string: String(repeating: "\n", count: leading), attributes: attributes)
        result.append(value)
        result.append(NSAttributedString(string: String(repeating: "\n", count: trailing), attributes: attributes))
        return result
    }

    static func items(fragment: NativeClipboardFragment, rich: NSAttributedString?) throws -> [[String: Any]] {
        try fragment.validate()
        let encoded = try JSONEncoder().encode(fragment)
        guard encoded.count <= NativeClipboardFragment.limit * 3 / 2 else { throw VaultFailure(message: "Copy a smaller selection; its clipboard attachments are too large.") }
        var item: [String: Any] = [
            NativeClipboardFragment.type: encoded,
            UTType.utf8PlainText.identifier: fragment.markdown,
            "net.daringfireball.markdown": Data(fragment.markdown.utf8)
        ]
        if let rich {
            // External rich text gets standard image attachments. Zerus' private
            // block classes and callbacks never cross the pasteboard boundary.
            let portable = NSMutableAttributedString(attributedString: rich)
            var richBytes = rich.string.utf8.count, allowRich = true
            rich.enumerateAttributes(in: NSRange(location: 0, length: rich.length)) { attributes, range, _ in
                if let attachment = attributes[.attachment] as? NSTextAttachment {
                    let reference = (attributes[.zerusImageMarkdown] as? String).flatMap { MarkdownResources.localReferences(in: $0).first }
                    let resource = fragment.resources.first { $0.reference == reference }
                    if attributes[.zerusImageMarkdown] != nil && resource?.bytes == nil { allowRich = false; return }
                    let bytes = resource?.bytes ?? attachment.image?.pngData()
                    guard let bytes else { allowRich = false; return }
                    richBytes += bytes.count
                    guard richBytes <= NativeClipboardFragment.limit else { allowRich = false; return }
                    let type = resource.flatMap { UTType(filenameExtension: ($0.name as NSString).pathExtension) } ?? .png
                    let replacement = NSTextAttachment(data: bytes, ofType: type.identifier)
                    let wrapper = FileWrapper(regularFileWithContents: bytes)
                    wrapper.preferredFilename = resource?.name ?? "Image.png"; replacement.fileWrapper = wrapper
                    if let source = CGImageSourceCreateWithData(bytes as CFData, nil), let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                        replacement.image = UIImage(cgImage: preview)
                    } else { replacement.image = attachment.image }
                    replacement.bounds = attachment.bounds
                    portable.addAttribute(.attachment, value: replacement, range: range)
                }
                for key in attributes.keys where key.rawValue.hasPrefix("Zerus") { portable.removeAttribute(key, range: range) }
            }
            let range = NSRange(location: 0, length: portable.length)
            if allowRich {
                if let data = try? portable.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]), data.count <= NativeClipboardFragment.limit { item[UTType.flatRTFD.identifier] = data }
                if let data = try? portable.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), data.count <= NativeClipboardFragment.limit { item[UTType.rtf.identifier] = data }
            }
        }
        return [item]
    }
}

extension VaultFiles {
    func clipboardFragment(_ markdown: String, notePath: String) throws -> NativeClipboardFragment {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        guard markdown.utf8.count <= NativeClipboardFragment.limit else { throw VaultFailure(message: "Copy a selection smaller than 50 MB.") }
        var portable = markdown, forced = Set<String>()
        let attachments = MarkdownResources.attachmentReferences(in: markdown)
        let ordinary = Set(MarkdownResources.localReferences(in: markdown))
        let all = Set(MarkdownResources.localReferences(in: markdown, includeNoteFiles: true))
        if !attachments.isEmpty || all != ordinary {
            let content = (try? read(notePath)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let note = NoteDocument(path: notePath, content: content, modified: Date())
            let records = NativeFileAttachment.all(in: content)
            var replacements: [String: String] = [:]
            for reference in attachments {
                let id = String(reference.dropFirst("zerus-attachment:".count))
                guard let record = records.first(where: { $0.id == id }) else { throw VaultFailure(message: "A copied attachment needs the original note's file details. Reopen the source note before copying it.") }
                let path = MarkdownResources.encodedPath(record.path, preservingSuffixOf: "")
                replacements[reference] = path; forced.insert(path)
            }
            portable = MarkdownResources.replacing(markdown, references: replacements)
            if let file = note.fileHub, file.kind == .vault, let path = file.path { forced.insert(MarkdownResources.encodedPath(path, preservingSuffixOf: "")) }
        }
        let available = Set(MarkdownResources.localReferences(in: portable, includeNoteFiles: true))
        let references = Set(MarkdownResources.localReferences(in: portable)).union(available.intersection(forced))
        var resources: [NativeClipboardFragment.Resource] = [], size = portable.utf8.count
        for reference in references.sorted() {
            try Task.checkCancellation()
            do {
                let location = try resolveResource(reference, notePath: notePath)
                let bytes = try resourceData(reference, notePath: notePath)
                size += bytes.count
                guard size <= NativeClipboardFragment.limit else { throw VaultFailure(message: "Copy a selection with less than 50 MB of attachments.") }
                let path = String(location.path.dropFirst(root.standardizedFileURL.path.count + 1))
                resources.append(.init(reference: reference, path: path, name: location.lastPathComponent, bytes: bytes))
            } catch let error as VaultFailure where error.message.contains("50 MB") { throw error }
            catch { resources.append(.init(reference: reference, path: nil, name: URL(string: reference)?.lastPathComponent ?? "Attachment", bytes: nil)) }
        }
        let fragment = NativeClipboardFragment(markdown: portable, vault: NativeClipboardFragment.vaultID(root), resources: resources)
        try fragment.validate(); return fragment
    }

    func importClipboard(_ fragment: NativeClipboardFragment) throws -> String {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        try fragment.validate()
        let references = Set(MarkdownResources.localReferences(in: fragment.markdown))
        guard references.isSubset(of: Set(fragment.resources.map(\.reference))) else {
            throw VaultFailure(message: "The copied attachments were not included. Paste into Markdown source to keep the references unchanged.")
        }
        guard fragment.resources.allSatisfy({ $0.bytes != nil }) else {
            throw VaultFailure(message: "An attachment was unavailable when copied. The clipboard still contains the Markdown; paste into source mode to keep those references.")
        }
        var replacements: [String: String] = [:], created: [(String, Data)] = []
        do {
            for resource in fragment.resources {
                try Task.checkCancellation()
                let bytes = resource.bytes!
                let path: String
                if fragment.vault == NativeClipboardFragment.vaultID(root), let existing = resource.path, (existing.hasPrefix("assets/") || existing.hasPrefix(".zerus/attachments/")), (try? read(existing)) == bytes {
                    path = existing
                } else {
                    let name = resource.name.replacingOccurrences(of: #"[/\\:\x00-\x1F]"#, with: "-", options: .regularExpression)
                    let opaqueNote = ["md", "markdown"].contains((name as NSString).pathExtension.lowercased())
                    path = (opaqueNote ? ".zerus/attachments/clipboard-" : "assets/") + UUID().uuidString.lowercased() + "-" + name
                    try write(path, data: bytes, expected: nil); created.append((path, bytes))
                }
                replacements[resource.reference] = MarkdownResources.encodedPath(path, preservingSuffixOf: resource.reference)
            }
            let markdown = MarkdownResources.replacing(fragment.markdown, references: replacements)
            try Task.checkCancellation()
            return markdown
        } catch {
            for (path, bytes) in created { try? removeClipboardAsset(path, expected: bytes) }
            throw error
        }
    }

    private func removeClipboardAsset(_ path: String, expected: Data) throws {
        let location = try url(for: path)
        var coordinationError: NSError?, failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: location, options: .forDeleting, error: &coordinationError) { url in
            do {
                guard try Data(contentsOf: url) == expected else { return }
                try FileManager.default.removeItem(at: url)
            } catch { failure = error }
        }
        if let failure { throw failure }; if let coordinationError { throw coordinationError }
    }
}
