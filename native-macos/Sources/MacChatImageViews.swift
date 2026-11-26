import SwiftUI
import AppKit

struct MacChatMessageImages: View {
    let root: URL
    let conversationID: String
    let message: MacConversationMessage
    let version: UUID
    @State private var images: [MacChatImage] = []
    @State private var issue: String?
    @State private var preview: MacChatImage?
    @State private var documents: [MacChatDocument] = []
    @State private var documentPreview: MacChatDocument?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !images.isEmpty {
                ScrollView(.horizontal) { HStack { ForEach(images) { image in
                    Button { preview = image } label: { VStack {
                        if let bitmap = NSImage(data: image.bytes) { Image(nsImage: bitmap).resizable().scaledToFit().frame(width: 120, height: 90) }
                        Text(image.name).macFont(.caption).lineLimit(1).frame(width: 130)
                    } }.buttonStyle(MacBoxButtonStyle()).accessibilityLabel("Preview " + image.name)
                } } }
            }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            ForEach(documents) { document in Button { documentPreview = document } label: { Label(document.name, systemImage: "doc.text") }.macFont(.caption) }
        }
        .task(id: version) {
            do { let saved = try await VaultFiles(root: root).conversationInput(message, conversationID: conversationID); try Task.checkCancellation(); images = saved.images; documents = saved.documents; issue = nil }
            catch is CancellationError {} catch { images = []; documents = []; issue = error.localizedDescription }
        }
        .macSheet(item: $documentPreview) { document in MacChatDocumentPreview(document: document) }
        .macSheet(item: $preview) { image in
            VStack(spacing: 16) {
                HStack { Text(image.name).macFont(.headline); Spacer(); Button("Done") { preview = nil } }
                if let bitmap = NSImage(data: image.bytes) { Image(nsImage: bitmap).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
                Text("\(image.width) × \(image.height) · JPEG · \(image.bytes.count.formatted()) bytes").macFont(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 760, height: 600)
        }
    }
}
