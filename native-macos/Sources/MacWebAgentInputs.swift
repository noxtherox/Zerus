import Foundation

extension NativeChatAttachmentStore {
    /// Only used for freshly prepared import inputs after confirming that no
    /// public journal exists. Other runs' or conversation inputs are untouched.
    func discardUncommittedWebInputs(run: UUID, chat: String, items: [NativeChatAttachment]) throws {
        guard !items.isEmpty else { return }
        let grant = directory.appendingPathComponent("AttachmentRunInputs/" + run.uuidString.lowercased() + ".json")
        if FileManager.default.fileExists(atPath: grant.path) {
            // A pre-existing grant may belong to an already imported record.
            // Clean only this attempt's fresh items when it does not match.
            if (try? validate(run: run, chat: chat, items: items)) != nil { try FileManager.default.removeItem(at: grant) }
        }
        for item in items {
            try manifest(item); _ = try read(item)
            let folder = directory.appendingPathComponent("Attachments/" + item.id.uuidString.lowercased())
            let retained = folder.appendingPathComponent("retained")
            if FileManager.default.fileExists(atPath: retained.path) { try FileManager.default.removeItem(at: retained) }
            discardUnreferenced(item)
        }
    }
}
