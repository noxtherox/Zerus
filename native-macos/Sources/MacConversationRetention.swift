import Foundation

extension VaultFiles {
    /// The shared desktop policy expires Trash after thirty days on its owner.
    /// A failed or unsupported conversation never prevents healthy history loading.
    func conversations(device: MacChatDevice, protectedIDs: Set<String> = [], now: Date = Date()) throws -> MacConversationList {
        let listed = try conversations()
        var issues = listed.issues, removed = Set<String>()
        for entry in listed.conversations where entry.owner.id == device.id && !protectedIDs.contains(entry.id) {
            guard let deleted = entry.deletedAt, now.timeIntervalSince(try MacConversations.date(deleted)) >= 30 * 24 * 60 * 60 else { continue }
            try Task.checkCancellation()
            do {
                let snapshot = try conversationSnapshot(entry.id)
                try purgeExpiredConversation(snapshot, device: device, now: now)
                removed.insert(entry.id)
            } catch is CancellationError { throw CancellationError() }
            catch { issues.append(entry.id + ": Automatic Trash cleanup preserved this conversation: " + error.localizedDescription) }
        }
        return .init(conversations: listed.conversations.filter { !removed.contains($0.id) }, issues: issues, purgedIDs: removed)
    }

    /// Includes directories as well as files: even a newly appearing empty
    /// folder invalidates the inventory checked inside the coordinated commit.
    private nonisolated static func conversationPurgeInventory(root: URL, paths: [String]) throws -> Set<String> {
        let manager = FileManager.default
        var result = Set<String>()
        func visit(_ path: String) throws {
            try Task.checkCancellation()
            let file = root.appendingPathComponent(path)
            _ = try confinedPath(for: file, root: root)
            guard MacConversations.entryExists(file) else { return }
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard values.isSymbolicLink != true else { throw VaultFailure(message: "Linked history or run files cannot be purged automatically.") }
            guard result.count < 50_000 else { throw VaultFailure(message: "The saved history inventory exceeds the automatic cleanup limit.") }
            if values.isDirectory == true {
                result.insert(path + "/")
                for child in try manager.contentsOfDirectory(atPath: file.path).sorted() { try visit(path + "/" + child) }
            } else {
                guard values.isRegularFile == true else { throw VaultFailure(message: "An unavailable history file was preserved.") }
                result.insert(path)
            }
        }
        for path in paths {
            // Refuse a linked ancestor too, including an in-vault alias.
            var parent = root
            for part in path.split(separator: "/") {
                parent.appendPathComponent(String(part))
                if MacConversations.entryExists(parent), try parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw VaultFailure(message: "Linked history or run folders cannot be purged automatically.")
                }
            }
            try visit(path)
        }
        return result
    }

    private func purgeExpiredConversation(_ snapshot: MacConversationSnapshot, device: MacChatDevice, now: Date) throws {
        let chat = snapshot.conversation
        guard chat.owner.id == device.id, let deleted = chat.deletedAt,
              now.timeIntervalSince(try MacConversations.date(deleted)) >= 30 * 24 * 60 * 60 else {
            throw VaultFailure(message: "The conversation was restored, claimed or has not expired.")
        }
        let identity = try MacAgentFileIdentity(root)
        let trees = [".zerus/chats/" + chat.id, ".zerus/ai/runs/" + chat.id]
        let inventory = try Self.conversationPurgeInventory(root: root, paths: trees)
        let nativeInventory = try Self.conversationPurgeInventory(root: root, paths: [NativeAgentJournal.directory])
        var changes: [String: VaultFileChange] = [:], total = 0
        func add(_ change: VaultFileChange) throws {
            if let previous = changes[change.path] {
                guard previous.before == change.before, previous.after == previous.before || change.after == change.before || previous.after == change.after else {
                    throw VaultFailure(message: "Saved run status changed while preparing cleanup.")
                }
                if change.before != change.after { changes[change.path] = change }
            } else { changes[change.path] = change }
        }
        for path in inventory.sorted() where !path.hasSuffix("/") {
            let file = try url(for: path), values = try file.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? Int.max) <= MacConversations.recordLimit else { throw VaultFailure(message: "A history file exceeds the automatic cleanup size limit.") }
            let bytes = try read(path); total += bytes.count
            guard bytes.count <= MacConversations.recordLimit, total <= MacConversations.historyLimit else { throw VaultFailure(message: "The conversation and web runs exceed the automatic cleanup size limit.") }
            try add(.init(path: path, before: bytes, after: nil))
        }
        // Reuse the exact ownership/event snapshot that established eligibility.
        guard changes[trees[0] + "/conversation.json"]?.before == snapshot.descriptor,
              snapshot.records.allSatisfy({ changes[$0.key]?.before == $0.value }),
              try Self.conversationEventPaths(root: root, id: chat.id) == Set(snapshot.records.keys) else {
            throw VaultFailure(message: "Conversation events changed while preparing cleanup. Refresh to retry.")
        }
        var manifestBytes = 0
        for path in nativeInventory.sorted() where !path.hasSuffix("/") {
            try Task.checkCancellation()
            do {
                let file = try url(for: path), values = try file.resourceValues(forKeys: [.fileSizeKey])
                guard file.deletingLastPathComponent().lastPathComponent == "runs", file.pathExtension == "json",
                      let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      path == NativeAgentJournal.path(id),
                      (values.fileSize ?? Int.max) <= 8_000_000 else { throw VaultFailure(message: "Unknown run file") }
                let bytes = try agentJournalData(path); manifestBytes += bytes.count
                guard bytes.count <= 8_000_000, manifestBytes <= 64 * 1024 * 1024,
                      let header = try NativeJSON.object(with: bytes) as? [String: Any],
                      (1...8).contains(NativeHistory.integer(header["version"]) ?? 0),
                      let chatID = header["chatID"] as? String else { throw VaultFailure(message: "Unsupported run header or inventory size") }
                // Reading only unrelated headers avoids expanding all of their
                // immutable message/proposal payloads on a history refresh.
                try add(.init(path: path, before: bytes, after: bytes))
                if chatID == chat.id {
                    let record = try agentDecode(bytes, id: id)
                    guard record.run.chatID == chat.id else { throw VaultFailure(message: "The decoded run association disagrees with its saved header") }
                    total += bytes.count
                    guard total <= MacConversations.historyLimit else { throw VaultFailure(message: "Saved run size limit") }
                    try add(.init(path: path, before: bytes, after: nil))
                    for change in try deleteMacWebAgentImportIndex(record) { try add(change) }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { throw VaultFailure(message: "An unreadable native run or unsupported run inventory may belong to this conversation. Resolve saved-run warnings before automatic cleanup. " + error.localizedDescription) }
        }
        let tombstone = VaultFileChange(path: ".zerus/chat-tombstones/" + chat.id + ".json", before: nil,
            after: try MacConversations.data(["version": 1, "conversationId": chat.id, "purgedAt": NativeRevisionIndex.timestamp(now)]))
        let origin = root
        try Task.checkCancellation()
        try applyTransaction([tombstone] + changes.values.sorted { $0.path < $1.path }, historySource: "chat-retention") {
            guard try MacAgentFileIdentity(origin) == identity,
                  try Self.conversationPurgeInventory(root: origin, paths: trees) == inventory,
                  try Self.conversationPurgeInventory(root: origin, paths: [NativeAgentJournal.directory]) == nativeInventory else {
                throw VaultFailure(message: "Conversation or run files changed. Automatic cleanup was canceled.")
            }
        }
        // Empty directories contain no retained data and are harmless to keep.
        // Archives, immutable payloads and private input grants are intentionally
        // retained; they can also be referenced by other saved/recovery state.
    }
}
