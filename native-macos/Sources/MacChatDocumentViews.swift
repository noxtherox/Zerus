import SwiftUI
import AppKit

struct MacChatDocumentPreview: View {
    let document: MacChatDocument
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(document.name).macFont(.headline); Spacer(); Button("Export extracted text…") { export() }; Button("Done") { dismiss() } }
            Text("\(document.text.utf8.count.formatted()) UTF-8 bytes · extracted text snapshot").macFont(.caption).foregroundStyle(.secondary)
            ScrollView { Text(String(document.text.prefix(80_000))).textSelection(.enabled).macFont(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) }
            if document.text.count > 80_000 { Text("Preview shows the first 80,000 characters. Export keeps the full extracted text; requests may use relevant excerpts.").macFont(.caption).foregroundStyle(.secondary) }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red) }
        }.padding(24).frame(width: 780, height: 600)
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = (document.name as NSString).deletingPathExtension + ".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(document.text.utf8).write(to: url, options: .atomic) } catch { issue = error.localizedDescription }
    }
}
