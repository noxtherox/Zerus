import SwiftUI
import QuickLook
import CoreTransferable
import UniformTypeIdentifiers

struct NativeExportView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: NoteSession
    @State private var format = NativeExportFormat.pdf
    @State private var includeProperties = true
    @State private var prepared: NativeExportArtifact?
    @State private var preview: URL?
    @State private var saving = false
    @State private var savedCopy = false
    @State private var issue: String?
    @State private var busy = false
    @State private var job: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(session.document.title).font(.headline)
                    Picker("Format", selection: $format) { ForEach(NativeExportFormat.allCases) { value in Text("\(value.title) (.\(value.rawValue))").tag(value) } }.disabled(busy).accessibilityIdentifier("export.format")
                } footer: { Text(format.detail) }
                Section {
                    Toggle("Include properties", isOn: $includeProperties).disabled(busy).accessibilityIdentifier("export.properties")
                } footer: { Text("Adds supported note properties as a compact table. Internal Zerus metadata stays hidden.") }
                if let prepared {
                    Section {
                        Label(prepared.url.lastPathComponent, systemImage: "doc").font(.subheadline).accessibilityIdentifier("export.ready")
                        Button("Preview", systemImage: "doc.text.magnifyingglass") { preview = prepared.url }.accessibilityIdentifier("export.preview")
                        Button("Save to Files", systemImage: "folder") { saving = true }.accessibilityIdentifier("export.save")
                        ShareLink(item: prepared.url) { Label("Share", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("export.share")
                        if savedCopy { Label("Saved a copy to Files", systemImage: "checkmark.circle").foregroundStyle(.secondary).accessibilityIdentifier("export.saved") }
                    } header: { Text("Ready to share") } footer: { Text("This is a snapshot of the note when you prepared it. Prepare again after making changes.") }
                    if !prepared.warnings.isEmpty {
                        Section("Items to review") { ForEach(prepared.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) } }
                    }
                }
                if let issue { Section { Text(issue).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("export.error") } }
                Section {
                    Button { prepare() } label: { HStack { if busy { ProgressView() }; Text(busy ? "Preparing…" : prepared == nil ? "Prepare export" : "Prepare again") } }.disabled(busy).accessibilityIdentifier("export.prepare")
                } footer: { Text("Images are read from this vault. Remote images are kept as labels; exporting makes no network requests.") }
            }
            .navigationTitle("Export note").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { job?.cancel(); dismiss() }.accessibilityIdentifier("export.done") } }
            .onChange(of: format) { _, _ in prepared = nil; issue = nil; savedCopy = false }
            .onChange(of: includeProperties) { _, _ in prepared = nil; issue = nil; savedCopy = false }
            .onDisappear { job?.cancel() }
            .quickLookPreview($preview)
            .fileExporter(isPresented: $saving, item: prepared.map(NativeExportTransfer.init), contentTypes: [format.contentType], defaultFilename: prepared?.url.deletingPathExtension().lastPathComponent) { result in
                switch result {
                case .success: savedCopy = true
                case .failure(let error): issue = error.localizedDescription
                }
            }
        }
    }
    private func prepare() {
        job?.cancel(); busy = true; issue = nil; prepared = nil; savedCopy = false
        let note = session.document, choice = format, properties = includeProperties
        job = Task {
            defer { busy = false }
            do { prepared = try await vault.exportNote(note, format: choice, includeProperties: properties) }
            catch is CancellationError {} catch { issue = error.localizedDescription }
        }
    }
}

private extension NativeExportFormat {
    var contentType: UTType { switch self {
    case .pdf: return .pdf
    case .docx: return UTType(filenameExtension: "docx") ?? .data
    case .html: return .html
    } }
}

private struct NativeExportTransfer: Transferable {
    let artifact: NativeExportArtifact
    init(_ artifact: NativeExportArtifact) { self.artifact = artifact }
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: NativeExportFormat.pdf.contentType) { SentTransferredFile($0.artifact.url) }
            .suggestedFileName { $0.artifact.url.lastPathComponent }
            .exportingCondition { $0.artifact.format == .pdf }
        FileRepresentation(exportedContentType: NativeExportFormat.docx.contentType) { SentTransferredFile($0.artifact.url) }
            .suggestedFileName { $0.artifact.url.lastPathComponent }
            .exportingCondition { $0.artifact.format == .docx }
        FileRepresentation(exportedContentType: NativeExportFormat.html.contentType) { SentTransferredFile($0.artifact.url) }
            .suggestedFileName { $0.artifact.url.lastPathComponent }
            .exportingCondition { $0.artifact.format == .html }
    }
}
