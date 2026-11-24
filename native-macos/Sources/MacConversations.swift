import Foundation

struct MacChatDevice: Codable, Equatable, Sendable { let id: String; let name: String }
struct MacConversationMessage: Identifiable, Sendable {
    let id: String
    let turnID: String
    let role: String
    let text: String
    let createdAt: String
    let interrupted: Bool
    let raw: Data
}
struct MacConversation: Identifiable, Sendable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
    let owner: MacChatDevice
    let generation: Int
    let ownerEventID: String
    let messages: [MacConversationMessage]
    let archivedAt: String?
    let deletedAt: String?
    let scope: Data
    let summary: String?
}
struct MacConversationSnapshot: Sendable {
    let root: URL
    let conversation: MacConversation
    let descriptor: Data
    let records: [String: Data]
}
struct MacConversationList: Sendable {
    let conversations: [MacConversationListEntry]
    let issues: [String]
    var purgedIDs: Set<String> = []
}
/// Lists and search retain searchable message text, without pinning every
/// extracted document snapshot in memory. Open a snapshot for full message data.
struct MacConversationListEntry: Identifiable, Sendable {
    struct Message: Sendable { let role: String; let text: String }
    let id: String
    let title: String
    let updatedAt: String
    let owner: MacChatDevice
    let archivedAt: String?
    let deletedAt: String?
    let messages: [Message]
    init(_ conversation: MacConversation) {
        id = conversation.id; title = conversation.title; updatedAt = conversation.updatedAt; owner = conversation.owner
        archivedAt = conversation.archivedAt; deletedAt = conversation.deletedAt
        messages = conversation.messages.map { .init(role: $0.role, text: $0.text) }
    }
}
enum MacConversationChange: Sendable {
    case rename(String), archive, restore, delete, claim
    case message(Data)
    case scope(Data)
}

enum MacConversations {
    static let recordLimit = 256 * 1024 * 1024
    static let historyLimit = 512 * 1024 * 1024
    static func object(_ bytes: Data) throws -> [String: Any] {
        guard bytes.count <= recordLimit, let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw VaultFailure(message: "A saved conversation record is unsupported. Its original bytes are preserved.") }
        return value
    }
    static func data(_ object: [String: Any]) throws -> Data {
        let result = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard result.count <= recordLimit else { throw VaultFailure(message: "This conversation record exceeds 256 MB. Its existing history is unchanged.") }; return result
    }
    static func entryExists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil }
    static func checkedID(_ value: String) throws -> String {
        guard NativeHistory.identity(value) else { throw VaultFailure(message: "This conversation identity is unsupported. Its files are preserved.") }; return value
    }
    static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = object[key] as? String, !value.isEmpty else { throw VaultFailure(message: "A saved conversation is incomplete. Wait for its other files, then refresh.") }; return value
    }
    static func date(_ value: String) throws -> Date {
        guard let result = NativeRevisionIndex.date(value) else { throw VaultFailure(message: "A saved conversation has an unsupported timestamp. Its records are preserved.") }; return result
    }
    static func fold(id: String, descriptor bytes: Data, records: [String: Data]) throws -> MacConversation? {
        let descriptor = try object(bytes)
        guard NativeHistory.integer(descriptor["version"]) == 1, descriptor["id"] as? String == id else { throw VaultFailure(message: "This conversation uses an unsupported format. Its files are preserved.") }
        let created = try string(descriptor, "createdAt"); _ = try date(created)
        struct Event {
            let id: String; let at: String; let generation: Int; let device: String; let kind: String; let object: [String: Any]
        }
        var events: [Event] = [], identities = Set<String>()
        for (path, raw) in records {
            let item = try object(raw), eventID = try checkedID(string(item, "id")), at = try string(item, "at")
            guard NativeHistory.integer(item["version"]) == 1, item["conversationId"] as? String == id,
                  (path as NSString).lastPathComponent == eventID + ".json", identities.insert(eventID).inserted,
                  let generation = NativeHistory.integer(item["ownerGeneration"]), generation >= 1, generation < Int.max,
                  let kind = item["kind"] as? String, ["ownership", "message", "rename", "scope", "archive", "restore", "delete", "summary"].contains(kind) else { throw VaultFailure(message: "Some conversation events are still syncing or use a newer format. Their original files are preserved.") }
            _ = try date(at)
            events.append(.init(id: eventID, at: at, generation: generation, device: try string(item, "deviceId"), kind: kind, object: item))
        }
        events.sort { a, b in a.generation != b.generation ? a.generation < b.generation : a.at != b.at ? a.at < b.at : a.id < b.id }
        var owners: [Int: Event] = [:]
        for event in events where event.kind == "ownership" {
            guard let owner = event.object["owner"] as? [String: Any], owner["id"] is String, owner["name"] is String else { throw VaultFailure(message: "Conversation ownership is incomplete. Refresh after its files finish syncing.") }
            if owners[event.generation] == nil || event.id > owners[event.generation]!.id { owners[event.generation] = event }
        }
        guard let current = owners.values.max(by: { $0.generation != $1.generation ? $0.generation < $1.generation : $0.id < $1.id }), let ownerObject = current.object["owner"] as? [String: Any] else { return nil }
        let owner = MacChatDevice(id: try string(ownerObject, "id"), name: try string(ownerObject, "name"))
        var title: String?, archived: String?, deleted: String?, summary: String?, scope = descriptor["scope"] as? [String: Any] ?? ["kind": "vault"], messages: [String: MacConversationMessage] = [:], activity = created
        for event in events {
            let generationOwner = owners[event.generation]?.object["owner"] as? [String: Any]
            guard event.kind == "ownership" || event.kind == "message" || generationOwner?["id"] as? String == event.device else { continue }
            switch event.kind {
            case "ownership": activity = event.at
            case "message":
                guard let message = event.object["message"] as? [String: Any], let role = message["role"] as? String, ["user", "assistant"].contains(role), let text = message["text"] as? String,
                      message["deviceId"] is String, NativeHistory.integer(message["ownerGeneration"]) != nil else { throw VaultFailure(message: "A saved message is unsupported. Its conversation is preserved without rewriting it.") }
                let messageID = try checkedID(string(message, "id")), turn = try checkedID(string(message, "turnId")), timestamp = try string(message, "createdAt"); _ = try date(timestamp)
                messages[messageID] = .init(id: messageID, turnID: turn, role: role, text: text, createdAt: timestamp, interrupted: message["interrupted"] as? Bool ?? false, raw: try data(message)); activity = event.at
            case "rename": title = try string(event.object, "title")
            case "scope": guard let next = event.object["scope"] as? [String: Any], next["kind"] is String else { throw VaultFailure(message: "A conversation scope is unsupported.") }; scope = next
            case "archive": archived = event.at
            case "delete": deleted = event.at
            case "restore": archived = nil; deleted = nil
            case "summary": guard let value = event.object["text"] as? String, event.object["coveredMessageIds"] is [String] else { throw VaultFailure(message: "A conversation summary is unsupported.") }; summary = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            default: break
            }
        }
        let ordered = messages.values.sorted { a, b in a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.turnID == b.turnID && a.role != b.role ? a.role == "user" : a.id < b.id }
        guard !ordered.isEmpty else { return nil }
        let question = ordered.first { $0.role == "user" }?.text ?? "New chat", compact = question.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let inferred = compact.isEmpty ? "New chat" : compact.count > 64 ? String(compact.prefix(61)).trimmingCharacters(in: .whitespaces) + "…" : compact
        return .init(id: id, title: title ?? inferred, createdAt: created, updatedAt: activity, owner: owner, generation: current.generation, ownerEventID: current.id, messages: ordered, archivedAt: archived, deletedAt: deleted, scope: try data(scope), summary: summary)
    }
    static func timestamp(after records: [String: Data], fallback: String? = nil) throws -> String {
        var latest = Date().timeIntervalSince1970
        for raw in records.values { let object = try self.object(raw); latest = max(latest, try date(string(object, "at")).timeIntervalSince1970 + 0.001) }
        if let fallback { latest = max(latest, try date(fallback).timeIntervalSince1970 + 0.001) }
        guard latest < 253_402_300_000 else { throw VaultFailure(message: "This conversation’s clock is outside the supported range. Its files are preserved.") }
        return NativeRevisionIndex.timestamp(Date(timeIntervalSince1970: latest))
    }
}

extension VaultFiles {
    nonisolated static func conversationEventPaths(root: URL, id: String) throws -> Set<String> {
        _ = try MacConversations.checkedID(id)
        for path in [".zerus/chats", ".zerus/chats/" + id] {
            let location = root.appendingPathComponent(path)
            if MacConversations.entryExists(location), try location.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw VaultFailure(message: "Linked conversation folders are preserved without writing through them.") }
        }
        let path = ".zerus/chats/" + id + "/events", folder = root.appendingPathComponent(path)
        _ = try confinedPath(for: folder, root: root)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "Linked conversation events cannot be changed safely.") }
        var result = Set<String>()
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]) {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true else { throw VaultFailure(message: "Linked conversation data is preserved.") }
            if file.pathExtension == "json" { guard values.isRegularFile == true else { throw VaultFailure(message: "A conversation record is unavailable.") }; result.insert(path + "/" + file.lastPathComponent) }
            else if !file.lastPathComponent.hasPrefix(".") { throw VaultFailure(message: "Unrecognized conversation records were preserved. Use the newer client before writing here.") }
        }
        return result
    }
    private func conversationData(_ path: String) throws -> Data {
        let file = try url(for: path), values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= MacConversations.recordLimit else { throw VaultFailure(message: "A conversation record is linked, unavailable or larger than 256 MB. Its files are preserved.") }
        let bytes = try read(path); guard bytes.count <= MacConversations.recordLimit else { throw VaultFailure(message: "A conversation record grew while loading. Refresh to retry.") }; return bytes
    }
    func conversationSnapshot(_ id: String) throws -> MacConversationSnapshot {
        _ = try MacConversations.checkedID(id)
        let prefix = ".zerus/chats/" + id
        guard !MacConversations.entryExists(try url(for: ".zerus/chat-tombstones/" + id + ".json")) else { throw VaultFailure(message: "This conversation was permanently removed on another device. Its remaining files are preserved.") }
        let descriptor = try conversationData(prefix + "/conversation.json"), paths = try Self.conversationEventPaths(root: root, id: id)
        guard paths.count <= 20_000 else { throw VaultFailure(message: "This conversation is too large for the native preview. Its history remains intact.") }
        var records: [String: Data] = [:], size = 0
        for path in paths { try Task.checkCancellation(); let bytes = try conversationData(path); size += bytes.count; guard size <= MacConversations.historyLimit else { throw VaultFailure(message: "This saved conversation exceeds the native loading limit. Its files are preserved.") }; records[path] = bytes }
        guard let conversation = try MacConversations.fold(id: id, descriptor: descriptor, records: records) else { throw VaultFailure(message: "This conversation is still syncing its first message or ownership record.") }
        return .init(root: root, conversation: conversation, descriptor: descriptor, records: records)
    }
    func conversations() throws -> MacConversationList {
        let directory = try url(for: ".zerus/chats")
        guard FileManager.default.fileExists(atPath: directory.path) else { return .init(conversations: [], issues: []) }
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "Linked conversation history is unavailable. Its files are preserved.") }
        var conversations: [MacConversationListEntry] = [], issues: [String] = []
        for folder in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            try Task.checkCancellation()
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let id = folder.lastPathComponent
            if (try? url(for: ".zerus/chat-tombstones/" + id + ".json")).map({ MacConversations.entryExists($0) }) == true { continue }
            do { conversations.append(.init(try conversationSnapshot(id).conversation)) } catch { issues.append(id + ": " + error.localizedDescription) }
        }
        return .init(conversations: conversations.sorted { $0.updatedAt > $1.updatedAt }, issues: issues)
    }
    func createConversation(device: MacChatDevice, text: String, scope: Data, sources: Data? = nil, images: [MacChatImage] = [], documents: [MacChatDocument] = []) throws -> MacConversationSnapshot {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 500_000 else { throw VaultFailure(message: "Enter a message smaller than 500 KB.") }
        let id = UUID().uuidString.lowercased(), turn = UUID().uuidString.lowercased(), time = NativeRevisionIndex.timestamp(), prefix = ".zerus/chats/" + id
        _ = try Self.conversationEventPaths(root: root, id: id)
        let scopeObject = try MacConversations.object(scope)
        guard scopeObject["kind"] is String else { throw VaultFailure(message: "Choose a conversation context first.") }
        let descriptor = try MacConversations.data(["version": 1, "id": id, "createdAt": time, "scope": scopeObject])
        let ownershipID = UUID().uuidString.lowercased(), messageID = UUID().uuidString.lowercased(), eventID = UUID().uuidString.lowercased()
        let ownership = try MacConversations.data(["version": 1, "id": ownershipID, "conversationId": id, "at": time, "deviceId": device.id, "ownerGeneration": 1, "kind": "ownership", "owner": ["id": device.id, "name": device.name]])
        var message: [String: Any] = ["id": messageID, "turnId": turn, "role": "user", "text": text, "createdAt": time, "deviceId": device.id, "ownerGeneration": 1]
        if let sources { message["sources"] = try JSONSerialization.jsonObject(with: sources) }
        if !images.isEmpty { message["attachments"] = images.map { $0.metadata(conversationID: id) } }
        if !documents.isEmpty { _ = try MacChatDocument.decode(documents.map(\.object)); message["documents"] = documents.map(\.object) }
        let event = try MacConversations.data(["version": 1, "id": eventID, "conversationId": id, "at": time, "deviceId": device.id, "ownerGeneration": 1, "kind": "message", "message": message])
        let assets = try Self.chatImageChanges(images, conversationID: id, root: root)
        try applyTransaction([.init(path: prefix + "/conversation.json", before: nil, after: descriptor), .init(path: prefix + "/events/" + ownershipID + ".json", before: nil, after: ownership), .init(path: prefix + "/events/" + eventID + ".json", before: nil, after: event), .init(path: ".zerus/chat-tombstones/" + id + ".json", before: nil, after: nil)] + assets)
        return try conversationSnapshot(id)
    }
    func changeConversation(_ snapshot: MacConversationSnapshot, device: MacChatDevice, change: MacConversationChange, images: [MacChatImage] = []) throws -> MacConversationSnapshot {
        guard snapshot.root == root else { throw VaultFailure(message: "Reopen this conversation in its original vault.") }
        let chat = snapshot.conversation, prefix = ".zerus/chats/" + chat.id
        let claiming: Bool; if case .claim = change { claiming = true } else { claiming = false }
        guard claiming || chat.owner.id == device.id else { throw VaultFailure(message: "Move this conversation to this Mac before changing it.") }
        if case .message = change { guard chat.archivedAt == nil, chat.deletedAt == nil else { throw VaultFailure(message: "Restore this conversation before sending a message.") } }
        var object: [String: Any] = ["version": 1, "id": UUID().uuidString.lowercased(), "conversationId": chat.id, "at": try MacConversations.timestamp(after: snapshot.records), "deviceId": device.id, "ownerGeneration": chat.generation]
        switch change {
        case .claim: guard chat.generation < Int.max - 1 else { throw VaultFailure(message: "Conversation ownership has reached its supported limit.") }; object["kind"] = "ownership"; object["ownerGeneration"] = chat.generation + 1; object["owner"] = ["id": device.id, "name": device.name]
        case .rename(let text): let name = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty, name.utf8.count <= 4096 else { throw VaultFailure(message: "Enter a conversation name smaller than 4 KB.") }; object["kind"] = "rename"; object["title"] = name
        case .archive: object["kind"] = "archive"
        case .restore: object["kind"] = "restore"
        case .delete: object["kind"] = "delete"
        case .scope(let bytes): let scope = try MacConversations.object(bytes); guard scope["kind"] is String else { throw VaultFailure(message: "The selected context is unsupported.") }; object["kind"] = "scope"; object["scope"] = scope
        case .message(let bytes):
            let message = try MacConversations.object(bytes)
            guard ["user", "assistant"].contains(message["role"] as? String ?? ""), message["text"] is String, message["deviceId"] as? String == device.id, NativeHistory.integer(message["ownerGeneration"]) == chat.generation else { throw VaultFailure(message: "The outgoing message no longer belongs to this conversation owner.") }
            _ = try MacConversations.checkedID(MacConversations.string(message, "id")); _ = try MacConversations.checkedID(MacConversations.string(message, "turnId")); _ = try MacConversations.date(MacConversations.string(message, "createdAt"))
            object["kind"] = "message"; object["message"] = message
        }
        if !images.isEmpty {
            guard case .message(let messageBytes) = change else { throw VaultFailure(message: "Images must be saved with a user message.") }
            let message = try MacConversations.object(messageBytes)
            guard message["role"] as? String == "user", let metadata = message["attachments"] as? [[String: Any]], try JSONSerialization.data(withJSONObject: metadata, options: .sortedKeys) == JSONSerialization.data(withJSONObject: images.map { $0.metadata(conversationID: chat.id) }, options: .sortedKeys) else { throw VaultFailure(message: "The selected images changed. Review them before sending.") }
        }
        let bytes = try MacConversations.data(object), eventPath = prefix + "/events/" + (object["id"] as! String) + ".json"
        guard snapshot.records.count < 20_000, snapshot.records.values.reduce(bytes.count, { $0 + $1.count }) <= MacConversations.historyLimit else { throw VaultFailure(message: "This conversation reached the native history loading limit. Start a new conversation; its existing files remain readable.") }
        var changes = snapshot.records.map { VaultFileChange(path: $0.key, before: $0.value, after: $0.value) }
        changes += [.init(path: prefix + "/conversation.json", before: snapshot.descriptor, after: snapshot.descriptor), .init(path: ".zerus/chat-tombstones/" + chat.id + ".json", before: nil, after: nil), .init(path: eventPath, before: nil, after: bytes)]
        changes += try Self.chatImageChanges(images, conversationID: chat.id, root: root)
        let expected = Set(snapshot.records.keys), origin = root, id = chat.id
        try applyTransaction(changes) { guard try Self.conversationEventPaths(root: origin, id: id) == expected else { throw VaultFailure(message: "Conversation events changed. Refresh before continuing; no history was overwritten.") } }
        return try conversationSnapshot(chat.id)
    }
}
