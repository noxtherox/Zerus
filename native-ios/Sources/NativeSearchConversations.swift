import Foundation

extension VaultFiles {
    /// Shared web/mobile event history is read without claiming ownership,
    /// rewriting events, applying retention, or importing another vault's data.
    func searchSupplement(files: [String], liveConversation: NativeSearchConversation?) throws -> NativeSearchSupplement {
        var conversations: [NativeSearchConversation] = [], problems: [String] = [], documents: [NativeSearchFile] = []
        for path in files {
            try Task.checkCancellation()
            do {
                let values = try url(for: path).resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey])
                if values.isSymbolicLink != true { documents.append(.init(path: path, modified: values.contentModificationDate ?? .distantPast)) }
            } catch { problems.append("Some file details are still unavailable. Refresh to retry.") }
        }
        do {
        let directory = try url(for: ".zerus/chats")
        if FileManager.default.fileExists(atPath: directory.path) {
            for folder in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                try Task.checkCancellation()
                let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let id = folder.lastPathComponent
                guard NativeHistory.identity(id) else { problems.append("An unsupported conversation folder was preserved."); continue }
                if FileManager.default.fileExists(atPath: try url(for: ".zerus/chat-tombstones/" + id + ".json").path) { continue }
                do {
                    let prefix = ".zerus/chats/" + id
                    let descriptor = try JSONSerialization.jsonObject(with: read(prefix + "/conversation.json")) as? [String: Any]
                    guard let descriptor, NativeHistory.integer(descriptor["version"]) == 1, descriptor["id"] as? String == id, descriptor["createdAt"] is String else { throw VaultFailure(message: "Unsupported conversation format.") }
                    let eventsURL = try url(for: prefix + "/events")
                    guard FileManager.default.fileExists(atPath: eventsURL.path) else { continue }
                    guard try eventsURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "Linked conversation events are unavailable.") }
                    var events: [[String: Any]] = []
                    for file in try FileManager.default.contentsOfDirectory(at: eventsURL, includingPropertiesForKeys: [.isSymbolicLinkKey]) where file.pathExtension == "json" {
                        try Task.checkCancellation()
                        guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultFailure(message: "Linked conversation data is unavailable.") }
                        let bytes = try read(prefix + "/events/" + file.lastPathComponent)
                        guard let event = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                              NativeHistory.integer(event["version"]) == 1, event["id"] is String, event["conversationId"] as? String == id,
                              event["at"] is String, event["deviceId"] is String, NativeHistory.integer(event["ownerGeneration"]) != nil,
                              let kind = event["kind"] as? String, ["ownership", "message", "rename", "scope", "archive", "restore", "delete", "summary"].contains(kind) else { throw VaultFailure(message: "Some conversation events are still syncing or use a newer format.") }
                        events.append(event)
                    }
                    if let conversation = try Self.foldSearchConversation(id: id, descriptor: descriptor, events: events) { conversations.append(conversation) }
                } catch is CancellationError { throw CancellationError() } catch { problems.append("A conversation could not be searched yet. Its original files are preserved; refresh to retry.") }
            }
        }
        } catch is CancellationError { throw CancellationError() } catch { problems.append("Shared conversation history is unavailable. Other results remain searchable; refresh to retry.") }
        do {
            let native = try Self.privateSearchConversations(root: try NativeChatStorage.location(for: root) ?? NativeChat.legacyDirectory(for: root), live: liveConversation)
            conversations += native.conversations; problems += native.problems
        } catch is CancellationError { throw CancellationError() } catch { problems.append("Native conversation history is unavailable. Other results remain searchable; refresh to retry.") }
        return .init(files: documents, conversations: conversations, problems: Array(Set(problems)).sorted())
    }

    private nonisolated static func privateSearchConversations(root: URL, live: NativeSearchConversation?) throws -> (conversations: [NativeSearchConversation], problems: [String]) {
        var result: [NativeSearchConversation] = [], problems: [String] = []
        guard FileManager.default.fileExists(atPath: root.path) else { return (live.map { [$0] } ?? [], []) }
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { return ([], ["Linked native history is unavailable."]) }
        func load(_ url: URL, current: Bool) {
            do {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 50 * 1024 * 1024 else { throw VaultFailure(message: "Unavailable saved conversation.") }
                let messages = try JSONDecoder().decode([ChatMessage].self, from: Data(contentsOf: url))
                guard !messages.isEmpty else { return }
                let title = String((messages.first { $0.role == "user" }?.content ?? "Saved conversation").prefix(90))
                result.append(.init(id: current ? "native-current" : "native-archive:" + url.lastPathComponent, title: title, modified: values.contentModificationDate ?? .distantPast, archived: false, messages: messages, origin: current ? .current : .nativeArchive(url)))
            } catch { problems.append("A native conversation could not be searched. Its original file is preserved.") }
        }
        if let live { result.append(live) }
        else {
            let current = root.appendingPathComponent("current.json")
            if FileManager.default.fileExists(atPath: current.path) { load(current, current: true) }
        }
        let previous = root.appendingPathComponent("Previous")
        if FileManager.default.fileExists(atPath: previous.path), try previous.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true {
            for file in try FileManager.default.contentsOfDirectory(at: previous, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
                try Task.checkCancellation(); load(file, current: false)
            }
        }
        return (result, problems)
    }

    private nonisolated static func foldSearchConversation(id: String, descriptor: [String: Any], events input: [[String: Any]]) throws -> NativeSearchConversation? {
        func generation(_ event: [String: Any]) -> Int { NativeHistory.integer(event["ownerGeneration"])! }
        let events = input.sorted { a, b in
            if generation(a) != generation(b) { return generation(a) < generation(b) }
            if a["at"] as! String != b["at"] as! String { return (a["at"] as! String) < (b["at"] as! String) }
            return (a["id"] as! String) < (b["id"] as! String)
        }
        let ownership = events.filter { $0["kind"] as? String == "ownership" }
        guard !ownership.isEmpty else { return nil }
        var owners: [Int: [String: Any]] = [:]
        for event in ownership {
            guard let owner = event["owner"] as? [String: Any], owner["id"] is String else { throw VaultFailure(message: "Incomplete conversation ownership.") }
            let gen = generation(event)
            if owners[gen] == nil || (event["id"] as! String) > (owners[gen]!["id"] as! String) { owners[gen] = event }
        }
        let valid = events.filter { event in
            let kind = event["kind"] as! String
            return kind == "ownership" || kind == "message" || (owners[generation(event)]?["owner"] as? [String: Any])?["id"] as? String == event["deviceId"] as? String
        }
        var messages: [String: (role: String, text: String, created: String, turn: String)] = [:]
        var title: String?, archived = false, deleted = false, modified = descriptor["createdAt"] as! String
        for event in valid {
            switch event["kind"] as! String {
            case "message":
                guard let message = event["message"] as? [String: Any], let id = message["id"] as? String, let role = message["role"] as? String,
                      ["user", "assistant"].contains(role), let text = message["text"] as? String, let created = message["createdAt"] as? String, let turn = message["turnId"] as? String else { throw VaultFailure(message: "Incomplete conversation message.") }
                messages[id] = (role, text, created, turn); modified = event["at"] as! String
            case "ownership": modified = event["at"] as! String
            case "rename": guard let next = event["title"] as? String else { throw VaultFailure(message: "Incomplete conversation title.") }; title = next
            case "archive": archived = true
            case "delete": deleted = true
            case "restore": archived = false; deleted = false
            default: break
            }
        }
        guard !deleted, !messages.isEmpty else { return nil }
        let sorted = messages.sorted { a, b in
            if a.value.created != b.value.created { return a.value.created < b.value.created }
            if a.value.turn == b.value.turn, a.value.role != b.value.role { return a.value.role == "user" }
            return a.key < b.key
        }.map { ChatMessage(role: $0.value.role, content: $0.value.text) }
        let fallback = String((sorted.first { $0.role == "user" }?.content ?? "Saved conversation").prefix(90))
        return .init(id: "shared:" + id, title: title ?? fallback, modified: NativeRevisionIndex.date(modified) ?? .distantPast, archived: archived, messages: sorted, origin: .shared(id))
    }
}
