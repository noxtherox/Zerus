import SwiftUI
import AppKit
import PDFKit
import WebKit
import Security
import UniformTypeIdentifiers
import CoreText

@MainActor final class MacFilePreviewDraft: ObservableObject {
    let url: URL
    @Published var text = ""
    @Published private(set) var original: Data?
    @Published private(set) var issue: String?
    var canSave: Bool { original != nil }
    init(url: URL) { self.url = url }
    func load() {
        do {
            let data = try Data(contentsOf: url), bom = Data([0xef, 0xbb, 0xbf])
            let payload = data.starts(with: bom) ? Data(data.dropFirst(3)) : data
            guard let decoded = NoteDocument.decodeUTF8(payload) else { throw VaultFailure(message: "This file is not valid UTF-8. Its original bytes are preserved; use Open externally to view it.") }
            text = decoded; original = data; issue = nil
        } catch { original = nil; issue = error.localizedDescription }
    }
    func save() {
        do {
            guard let original else { return }
            let bom = Data([0xef, 0xbb, 0xbf])
            let data = (original.starts(with: bom) ? bom : Data()) + Data(text.utf8)
            var coordination: NSError?, failure: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordination) { location in
                do {
                    guard try Data(contentsOf: location) == original else { throw VaultFailure(message: "This file changed externally. Your draft remains open.") }
                    if data != original { try MacAtomicFileWrite.write(data, to: location) }
                } catch { failure = error }
            }
            if let error = failure ?? coordination { throw error }
            self.original = data; issue = "Saved"
        } catch { issue = error.localizedDescription }
    }
}

struct MacFilePreview: View {
    let url: URL
    @StateObject private var draft: MacFilePreviewDraft
    init(url: URL) { self.url = url; _draft = StateObject(wrappedValue: MacFilePreviewDraft(url: url)) }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(url.lastPathComponent).font(.headline); Spacer(); Button("Open externally") { NSWorkspace.shared.open(url) }; Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }; Button("Done") { dismiss() } }.padding(15)
            Divider()
            if url.pathExtension.lowercased() == "pdf" { MacPDFView(url: url) }
            else if ["html", "htm"].contains(url.pathExtension.lowercased()) { MacWebPreview(url: url) }
            else if ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) {
                if draft.canSave { TextEditor(text: $draft.text).font(.system(.body, design: .monospaced)).padding(15) }
                else { ContentUnavailableView("Text preview unavailable", systemImage: "doc.text", description: Text("Open this file externally to view its encoding.")) }
                HStack { Text(draft.issue ?? "External file — edits stay at the original location").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Save") { draft.save() }.disabled(!draft.canSave) }.padding(15)
            } else if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit().padding(20) }
            else { ContentUnavailableView("Preview unavailable", systemImage: "doc", description: Text("Use Open externally to view this file in its associated app.")) }
        }.task {
            guard ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) else { return }
            draft.load()
        }
    }
}

struct MacExportRequest: Identifiable {
    let id = UUID()
    let note: NoteDocument
    let root: URL
    init(note: NoteDocument, body: String, root: URL) {
        var snapshot = note
        snapshot.content = note.replacingBody(body)
        self.note = snapshot
        self.root = root
    }
}

struct MacPrintDocument {
    let document: PDFDocument
    let warnings: [String]
}

@MainActor enum MacExport {
    static func write(_ request: MacExportRequest, format: NativeExportFormat, includeProperties: Bool, to url: URL) async throws -> [String] {
        let document = try await VaultFiles(root: request.root).exportDocument(request.note, includeProperties: includeProperties)
        let artifact = try NativeNoteExport.artifact(document, format: format)
        defer { try? FileManager.default.removeItem(at: artifact.url.deletingLastPathComponent()) }
        try Data(contentsOf: artifact.url).write(to: url, options: .atomic)
        return artifact.warnings
    }
    static func preparePrint(_ request: MacExportRequest) async throws -> MacPrintDocument {
        let source = try await VaultFiles(root: request.root).exportDocument(request.note, includeProperties: false)
        try Task.checkCancellation()
        let data = try NativePDFExport.render(source)
        try Task.checkCancellation()
        guard let document = PDFDocument(data: data) else { throw VaultFailure(message: "Could not prepare the printed note.") }
        return .init(document: document, warnings: source.warnings)
    }
}

struct MacNotePrintView: View {
    let request: MacExportRequest
    @Environment(\.dismiss) private var dismiss
    @State private var preparing = false
    @State private var prepared: MacPrintDocument?
    @State private var issue: String?
    @State private var attempt = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Print note").font(.title2.bold())
            Text(request.note.title).font(.headline).lineLimit(2)
            Text("Prints the note as it was when this dialog opened.").font(.caption).foregroundStyle(.secondary)
            if preparing { HStack { ProgressView().controlSize(.small); Text("Preparing pages…") } }
            if let prepared {
                Text("\(prepared.document.pageCount) \(prepared.document.pageCount == 1 ? "page" : "pages") ready")
                Text("Choose your printer or save a PDF in the print dialog.").font(.caption).foregroundStyle(.secondary)
                MacNoteExportWarnings(warnings: prepared.warnings)
            }
            if let issue {
                Text(issue).foregroundStyle(.red).textSelection(.enabled)
                Button("Retry") { attempt += 1 }.disabled(preparing)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Print…", action: printNote).keyboardShortcut(.defaultAction).disabled(prepared == nil || preparing)
            }
        }.padding(22).frame(width: 470).task(id: attempt) { await prepare() }
    }
    private func prepare() async {
        guard !preparing else { return }
        preparing = true; issue = nil; prepared = nil
        defer { preparing = false }
        do { prepared = try await MacExport.preparePrint(request) }
        catch is CancellationError {}
        catch { if !Task.isCancelled { issue = "Could not prepare note: " + error.localizedDescription } }
    }
    private func printNote() {
        guard let prepared else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        guard let operation = prepared.document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else {
            issue = "Could not open the print dialog. Your note is unchanged."; return
        }
        operation.jobTitle = request.note.title
        operation.showsPrintPanel = true; operation.showsProgressPanel = true
        operation.run()
        dismiss()
    }
}

private struct MacNoteExportWarnings: View {
    let warnings: [String]
    var body: some View {
        if !warnings.isEmpty {
            Text("Some content could not be fully included:").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 120)
        }
    }
}

struct MacNoteExportView: View {
    let request: MacExportRequest
    @Environment(\.dismiss) private var dismiss
    @State private var format = NativeExportFormat.pdf
    @State private var includeProperties = true
    @State private var busy = false
    @State private var issue: String?
    @State private var warnings: [String] = []
    @State private var exported: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export note").font(.title2.bold())
            Text(request.note.title).font(.headline).lineLimit(2)
            Text("Exports the note as it was when this dialog opened.").font(.caption).foregroundStyle(.secondary)
            Picker("Format", selection: $format) {
                ForEach(NativeExportFormat.allCases) { format in Text(format.title + " (." + format.rawValue + ")").tag(format) }
            }.accessibilityIdentifier("note.export.format")
            Text(format.detail).font(.caption).foregroundStyle(.secondary)
            Toggle("Include properties", isOn: $includeProperties).accessibilityIdentifier("note.export.properties")
            Text("Adds visible note properties as a compact table. Zerus metadata stays hidden.").font(.caption).foregroundStyle(.secondary)
            if busy { HStack { ProgressView().controlSize(.small); Text("Preparing export…") } }
            if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
            if let exported {
                Label("Exported " + exported.lastPathComponent, systemImage: "checkmark.circle").textSelection(.enabled)
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([exported]) }
            }
            MacNoteExportWarnings(warnings: warnings)
            HStack {
                Button(exported == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(exported == nil ? "Export…" : "Export again…", action: save).keyboardShortcut(.defaultAction).accessibilityIdentifier("note.export.save")
            }
        }.padding(22).frame(width: 470).disabled(busy).interactiveDismissDisabled(busy)
    }
    private func save() {
        let selectedFormat = format, properties = includeProperties
        let panel = NSSavePanel(); panel.title = "Export note"; panel.prompt = "Export"
        panel.nameFieldStringValue = NativeNoteExport.stem(request.note.title) + "." + selectedFormat.rawValue
        panel.allowedContentTypes = [UTType(filenameExtension: selectedFormat.rawValue)!]
        panel.allowsOtherFileTypes = false; panel.isExtensionHidden = false; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; issue = nil; warnings = []; exported = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                warnings = try await MacExport.write(request, format: selectedFormat, includeProperties: properties, to: url)
                exported = url
            } catch { issue = "Could not export note: " + error.localizedDescription }
        }
    }
}

private final class MacPDFImageCell: NSTextAttachmentCell {
    private let displaySize: NSSize
    init(size: NSSize) { displaySize = size; super.init(imageCell: nil) }
    required init(coder: NSCoder) { displaySize = .zero; super.init(coder: coder) }
    override func cellSize() -> NSSize { displaySize }
    override func cellBaselineOffset() -> NSPoint { .zero }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
}

private final class MacPDFImageSpacer: NSTextAttachment {
    init(size: NSSize) { super.init(data: nil, ofType: nil); bounds = NSRect(origin: .zero, size: size); attachmentCell = MacPDFImageCell(size: size) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect { bounds }
}

/// AppKit intentionally omits underlines on line-edge whitespace. Exported
/// Markdown can explicitly style those spaces, so retain its decoration while
/// leaving AppKit's word, font and by-word drawing behavior intact.
private final class MacPDFLayoutManager: NSLayoutManager {
    override func underlineGlyphRange(_ glyphs: NSRange, underlineType: NSUnderlineStyle, lineFragmentRect: NSRect, lineFragmentGlyphRange: NSRange, containerOrigin: NSPoint) {
        super.underlineGlyphRange(glyphs, underlineType: underlineType, lineFragmentRect: lineFragmentRect, lineFragmentGlyphRange: lineFragmentGlyphRange, containerOrigin: containerOrigin)
        guard !underlineType.contains(.byWord), let storage = textStorage, let graphics = NSGraphicsContext.current?.cgContext else { return }
        let raw = storage.string as NSString
        let line = characterRange(forGlyphRange: lineFragmentGlyphRange, actualGlyphRange: nil)
        var end = NSMaxRange(line)
        // A line break is not a space to decorate, including HTML <br> breaks.
        while end > line.location && [10, 13, 0x2028, 0x2029].contains(Int(raw.character(at: end - 1))) { end -= 1 }
        func space(_ index: Int) -> Bool { let unit = raw.character(at: index); return unit == 32 || unit == 9 }
        var leading = line.location
        while leading < end && space(leading) { leading += 1 }
        var trailing = end
        while trailing > leading && space(trailing - 1) { trailing -= 1 }
        graphics.saveGState(); defer { graphics.restoreGState() }
        // Hanging spaces must not draw through the page margin.
        graphics.clip(to: lineFragmentRect.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y))
        for characters in [NSRange(location: line.location, length: leading - line.location), NSRange(location: trailing, length: end - trailing)] where characters.length > 0 {
            let edge = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
            let visible = NSIntersectionRange(glyphs, edge)
            guard visible.length > 0 else { continue }
            // This API measures the baseline from the fragment's bottom, not
            // the attributed string's baselineOffset or the glyph's top origin.
            let offset = lineFragmentRect.height - location(forGlyphAt: visible.location).y
            drawUnderline(forGlyphRange: visible, underlineType: underlineType, baselineOffset: offset, lineFragmentRect: lineFragmentRect, lineFragmentGlyphRange: lineFragmentGlyphRange, containerOrigin: containerOrigin)
        }
    }
}

enum NativePDFExport {
    static func render(_ document: NativeExportDocument) throws -> Data {
        let html = Data(NativeHTMLExport.render(document).utf8)
        let rich = try NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
        let storage = NSTextStorage(attributedString: rich), manager = MacPDFLayoutManager()
        storage.addLayoutManager(manager)
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.paragraphSpacing = max(10, paragraph.paragraphSpacing)
            paragraph.lineSpacing = max(3, paragraph.lineSpacing)
            storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }
        let page = CGRect(x: 0, y: 0, width: 595, height: 842), margin: CGFloat = 48
        let content = NSSize(width: page.width - margin * 2, height: page.height - margin * 2)
        func images(_ blocks: [NativeExportBlock]) -> [NativeExportRun] {
            blocks.flatMap { block in
                switch block {
                case .paragraph(let runs, _): return runs.filter { $0.image.flatMap { document.images[$0] } != nil }
                case .quote(let children): return images(children)
                case .list(_, let items): return items.flatMap { images($0.blocks) }
                case .table(let rows, _): return rows.flatMap { $0.flatMap { $0.filter { $0.image.flatMap { document.images[$0] } != nil } } }
                default: return []
                }
            }
        }
        let occurrences = images(document.blocks)
        var index = 0, imageRanges: [(NSRange, CGImage, NSSize)] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value is NSTextAttachment, occurrences.indices.contains(index), let key = occurrences[index].image,
                  let resource = document.images[key], let image = NSImage(data: resource.bytes) else { return }
            let size = occurrences[index].imageSize(resource), factor = min(1, content.width / max(1, size.width), content.height / max(1, size.height))
            guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let display = NSSize(width: size.width * factor, height: size.height * factor)
            storage.addAttribute(.attachment, value: MacPDFImageSpacer(size: display), range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            imageRanges.append((range, bitmap, display)); index += 1
        }
        guard index == occurrences.count else { throw VaultFailure(message: "An image could not be laid out for PDF export. Export HTML or Word while this image is reviewed.") }
        let bytes = NSMutableData(); guard let consumer = CGDataConsumer(data: bytes as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw VaultFailure(message: "Could not create PDF output.") }
        var covered = 0
        repeat {
            try Task.checkCancellation()
            let container = NSTextContainer(size: content); container.lineFragmentPadding = 0; manager.addTextContainer(container)
            let range = manager.glyphRange(for: container)
            guard range.length > 0 || storage.length == 0 else { throw VaultFailure(message: "A PDF block does not fit on a page. Reduce its image size or table width.") }
            var media = page; context.beginPDFPage([kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            context.saveGState(); context.translateBy(x: margin, y: page.height - margin); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            manager.drawBackground(forGlyphRange: range, at: .zero); manager.drawGlyphs(forGlyphRange: range, at: .zero)
            // Spacer attachments reserve layout; each prepared bitmap is painted
            // once, independent of NSTextView/attachment-cell drawing behavior.
            for (characters, bitmap, display) in imageRanges {
                let glyphs = manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
                guard NSIntersectionRange(glyphs, range).length > 0 else { continue }
                let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                context.saveGState(); context.translateBy(x: rect.minX, y: rect.minY + display.height); context.scaleBy(x: 1, y: -1)
                context.draw(bitmap, in: CGRect(origin: .zero, size: display)); context.restoreGState()
            }
            NSGraphicsContext.restoreGraphicsState(); context.restoreGState(); context.endPDFPage()
            covered = NSMaxRange(range)
        } while covered < manager.numberOfGlyphs

        context.closePDF(); return bytes as Data
    }
}

/// Keys stay in this app's Keychain domain, outside the Markdown vault.
enum MacCredentials {
    static func read(_ account: String) async throws -> String {
        guard let data = try await AppleKeychainIO.read(service: "com.zerus.notes.macos.native.ai", account: account, allowInteraction: true) else { return "" }
        guard let value = String(data: data, encoding: .utf8) else { throw VaultFailure(message: "The saved API key is unreadable. Its original Keychain entry is preserved.") }
        return value
    }
    static func save(_ value: String, account: String) async throws {
        try await AppleKeychainIO.save(Data(value.utf8), service: "com.zerus.notes.macos.native.ai", account: account)
    }
}
