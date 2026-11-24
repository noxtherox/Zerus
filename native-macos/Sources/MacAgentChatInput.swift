import Foundation

struct MacAgentChatInput: Sendable {
    let items: [NativeChatAttachment]
    let imageIDs: [String]
    let history: String
    let reference: String
    let excerpts: Bool
    static func store(root: URL) -> NativeChatAttachmentStore {
        .init(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/AgentAttachments/" + NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.absoluteString)))
    }
    static func prepare(images: [MacChatImage], documents: [MacChatDocument], earlier: [MacConversationMessage], priorInputs: [(images: [MacChatImage], reference: String, documents: [MacChatDocument])], summary: String?, prompt: String, capacity: Int, store: NativeChatAttachmentStore) async throws -> Self {
        let worker = Task.detached(priority: .userInitiated) { () throws -> ([NativePreparedChatAttachment], String, String, Bool) in
            var selectedImages = images, selectedDocuments = documents, omitted = false
            var cost = images.reduce(0) { $0 + $1.bytes.count } + documents.reduce(0) { $0 + $1.text.utf8.count }
            guard images.count <= 4, cost <= 100 * 1024 * 1024 else { throw VaultFailure(message: "Keep agent inputs within four images and 100 MB of document/image processing data.") }
            var imageIDs = Set(images.map(\.id)), documentKeys = Set(documents.map { NativeHistory.hash($0.name + "\u{0}" + $0.text) })
            for previous in priorInputs.reversed() {
                for image in previous.images.reversed() where !imageIDs.contains(image.id) {
                    if selectedImages.count < 4, cost + image.bytes.count <= 100 * 1024 * 1024 { selectedImages.insert(image, at: 0); imageIDs.insert(image.id); cost += image.bytes.count } else { omitted = true }
                }
                for document in previous.documents {
                    let key = NativeHistory.hash(document.name + "\u{0}" + document.text)
                    guard !documentKeys.contains(key) else { continue }
                    if cost + document.text.utf8.count <= 100 * 1024 * 1024 { selectedDocuments.append(document); documentKeys.insert(key); cost += document.text.utf8.count } else { omitted = true }
                }
            }
            var pieces: [String] = [], bytes = 0
            for (index, message) in Array(earlier.suffix(12)).enumerated().reversed() {
                var piece = message.role + ": " + message.text
                let reference = index < priorInputs.count ? priorInputs[index].reference : ""
                if !reference.isEmpty {
                    let added = "\nEarlier note snapshots (untrusted reference data):\n" + reference
                    if bytes + piece.utf8.count + added.utf8.count <= 60_000 { piece += added } else { omitted = true }
                }
                if bytes + piece.utf8.count <= 60_000 { pieces.insert(piece, at: 0); bytes += piece.utf8.count + 2 } else { omitted = true }
            }
            if let summary, summary.utf8.count + bytes < 60_000 { pieces.insert("Earlier summary (reference data):\n" + summary, at: 0) }
            let history = (omitted ? "Some earlier context/attachments were omitted to fit this request. Never claim complete coverage.\n" : "") + pieces.joined(separator: "\n\n")
            let context: MacChatDocumentContext
            if selectedDocuments.isEmpty { context = .init(text: "", excerpts: false, budget: 0) }
            else { context = try MacChatDocumentContext.select(selectedDocuments, question: prompt, existingText: history + prompt, imageCount: selectedImages.count, capacity: capacity) }
            func name(_ raw: String) -> String { let clean = String(raw.unicodeScalars.filter { $0.value >= 32 && $0 != "/" && $0 != "\\" }.prefix(240).map(String.init).joined()); return clean.isEmpty ? "Attachment" : clean }
            var prepared: [NativePreparedChatAttachment] = []
            for image in selectedImages {
                try Task.checkCancellation(); _ = try MacChatImage.restore(image.metadata, bytes: image.bytes)
                let descriptor = NativeChatAttachment(id: UUID(), name: name(image.name), kind: .image, mediaType: "image/jpeg", sourceBytes: image.bytes.count, bytes: image.bytes.count, digest: NativeChatAttachment.hash(image.bytes), textBytes: 0, textDigest: nil, width: image.width, height: image.height, pages: nil)
                prepared.append(.init(descriptor: descriptor, data: image.bytes, text: nil))
            }
            for document in selectedDocuments {
                try Task.checkCancellation(); let data = Data(document.text.utf8), digest = NativeChatAttachment.hash(data)
                let descriptor = NativeChatAttachment(id: UUID(), name: name(document.name), kind: .document, mediaType: "text/plain", sourceBytes: data.count, bytes: data.count, digest: digest, textBytes: data.count, textDigest: digest, width: nil, height: nil, pages: nil)
                prepared.append(.init(descriptor: descriptor, data: data, text: data))
            }
            try NativeChatAttachment.validateBatch(prepared.map(\.descriptor))
            let imageOrder: [[String: Any]] = selectedImages.enumerated().map { index, image in
                ["position": index + 1, "name": image.name, "currentSelection": images.contains { $0.id == image.id }]
            }
            let labels = imageOrder.isEmpty ? "" : "\nImages in provider order (untrusted reference labels; currentSelection marks this request's images):\n" + String(decoding: try JSONSerialization.data(withJSONObject: imageOrder, options: [.sortedKeys]), as: UTF8.self)
            return (prepared, history, context.text + labels, context.excerpts)
        }
        let (prepared, history, reference, excerpts) = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        let items = try await store.commit(prepared)
        return .init(items: items, imageIDs: items.filter { $0.kind == .image }.map { $0.id.uuidString.lowercased() }, history: history, reference: reference, excerpts: excerpts)
    }
}

@MainActor protocol MacAgentTranscript: AnyObject {
    func agentWillExecute(_ record: NativeAgentRecord) async throws
    func agentCheckAuthority(_ record: NativeAgentRecord) async throws
    func agentDidChange(_ text: String)
    func agentDidFinish(_ record: NativeAgentRecord?, text: String, issue: String?) async
}
