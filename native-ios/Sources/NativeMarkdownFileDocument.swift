import SwiftUI
import UniformTypeIdentifiers

struct NativeMarkdownFileDocument: FileDocument {
    static let contentType = UTType(filenameExtension: "md") ?? UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    static var readableContentTypes: [UTType] { [contentType] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw VaultFailure(message: "This Markdown file is unavailable.") }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct NativeExternalCreateView: View {
    @Environment(\.dismiss) private var dismiss
    let saved: (URL) -> Void
    @State private var title = ""
    @State private var exporting = false
    @State private var document: NativeMarkdownFileDocument?
    @State private var issue: String?
    @FocusState private var focused: Bool
    private var filename: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { !filename.isEmpty && filename.count <= 120 && !filename.contains("/") && !filename.contains("\\") && !filename.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title).focused($focused).accessibilityIdentifier("external.new.name")
                    if focused { Button("Done") { focused = false }.accessibilityLabel("Dismiss filename keyboard") }
                } header: { Text("New Markdown file") } footer: { Text("Choose its location in Files. The file stays there and opens in the native editor.") }
                if let issue { Text(issue).foregroundStyle(.red).textSelection(.enabled) }
                Section {
                    Button("Choose location and save", systemImage: "folder") {
                        focused = false
                        let heading = (filename as NSString).pathExtension.lowercased() == "md" ? (filename as NSString).deletingPathExtension : filename
                        document = .init(data: Data(("# " + heading + "\n\n").utf8)); exporting = true
                    }.disabled(!valid).accessibilityIdentifier("external.new.save")
                }
            }
            .navigationTitle("New file").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("external.new.cancel") } }
            .fileDialogDefaultDirectory(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
            .fileDialogCustomizationID("zerus.external.markdown.creation")
            .fileExporter(isPresented: $exporting, document: document, contentType: NativeMarkdownFileDocument.contentType, defaultFilename: filename) { result in
                switch result {
                case .success(let url): saved(url); dismiss()
                case .failure(let error): issue = error.localizedDescription
                }
            }
        }
    }
}
