import XCTest
@testable import Zerus_Native

final class MacConversationsTests: XCTestCase {
    func testExpiredTrashPurgesOnlyOwnedUnprotectedHistoryAndRunsAndLeavesPortableTombstones() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-chat-retention-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let io = VaultFiles(root: root), device = MacChatDevice(id: "owner", name: "Mac"), other = MacChatDevice(id: "peer", name: "Peer")
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        func deleted(_ owner: MacChatDevice, at: Date) async throws -> MacConversationSnapshot {
            let created = try await io.createConversation(device: owner, text: "Retained evidence", scope: MacConversations.data(["kind": "vault"]))
            let removed = try await io.changeConversation(created, device: owner, change: .delete)
            return try await ageDeletedConversation(removed, at: at, root: root, io: io)
        }
        let expired = try await deleted(device, at: cutoff), recent = try await deleted(device, at: cutoff.addingTimeInterval(1))
        let foreign = try await deleted(other, at: cutoff), protected = try await deleted(device, at: cutoff)
        let restored = try await io.changeConversation(deleted(device, at: cutoff), device: device, change: .restore)
        let archived = try await io.changeConversation(io.createConversation(device: device, text: "Archived", scope: MacConversations.data(["kind": "vault"])), device: device, change: .archive)
        let malformed = try await deleted(device, at: cutoff), linked = try await deleted(device, at: cutoff)
        let unknown = root.appendingPathComponent(".zerus/chats/" + malformed.conversation.id + "/events/future.json"), unknownBytes = Data("{\"version\":99}".utf8)
        try unknownBytes.write(to: unknown)
        let outside = root.appendingPathComponent("Keep.txt"), outsideBytes = Data("External content".utf8)
        try outsideBytes.write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".zerus/chats/" + linked.conversation.id + "/linked"), withDestinationURL: outside)
        let asset = root.appendingPathComponent(".zerus/chats/" + expired.conversation.id + "/attachments/image.jpg")
        let web = root.appendingPathComponent(".zerus/ai/runs/" + expired.conversation.id + "/worker.json")
        for file in [asset, web] { try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("Saved payload".utf8).write(to: file) }
        var native = try await io.agentStart(objective: "Retained run", mode: .ask, scope: .init(), chatID: expired.conversation.id, owner: device.id)
        var large = try XCTUnwrap(NativeJSON.object(with: native.bytes) as? [String: Any])
        large["version"] = 5; large["retainedMetadata"] = String(repeating: "Exact retained metadata. ", count: 2000)
        let storage = try await io.agentJournalChanges(JSONSerialization.data(withJSONObject: large), previous: native.bytes, id: native.id)
        try await io.applyTransaction(storage.changes); native = storage.record
        let header = try XCTUnwrap(NativeJSON.object(with: native.bytes) as? [String: Any])
        XCTAssertEqual(NativeHistory.integer(header["version"]), 8)
        let groups = try XCTUnwrap(header["macFieldGroups"] as? [[String: Any]])
        let digest = try XCTUnwrap(groups.first?["digest"] as? String)
        let payloadFile = root.appendingPathComponent(MacAgentPayloads.path(native.id, digest: digest)), payloadBytes = try Data(contentsOf: payloadFile)
        let unrelated = try await io.agentStart(objective: "Other run", mode: .ask, scope: .init(), chatID: recent.conversation.id, owner: device.id)
        let archive = root.appendingPathComponent(".zerus/native-ai/web-sources/keep.json"), archiveBytes = Data("Exact retained source".utf8)
        try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true); try archiveBytes.write(to: archive)
        let result = try await io.conversations(device: device, protectedIDs: [protected.conversation.id], now: now)
        XCTAssertEqual(Set(result.conversations.map(\.id)), Set([recent, foreign, protected, restored, archived, linked].map { $0.conversation.id }))
        XCTAssertTrue(result.issues.contains { $0.hasPrefix(malformed.conversation.id + ":") })
        XCTAssertTrue(result.issues.contains { $0.contains(linked.conversation.id) && $0.contains("Linked history") })
        for path in Array(expired.records.keys) + [".zerus/chats/" + expired.conversation.id + "/conversation.json", NativeAgentJournal.path(native.id)] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: asset.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: web.path))
        let tombstone = try MacConversations.object(Data(contentsOf: root.appendingPathComponent(".zerus/chat-tombstones/" + expired.conversation.id + ".json")))
        XCTAssertEqual(tombstone["version"] as? Int, 1); XCTAssertEqual(tombstone["conversationId"] as? String, expired.conversation.id)
        XCTAssertEqual(try MacConversations.date(XCTUnwrap(tombstone["purgedAt"] as? String)).timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(unrelated.id))), unrelated.bytes)
        XCTAssertEqual(try Data(contentsOf: archive), archiveBytes); XCTAssertEqual(try Data(contentsOf: outside), outsideBytes); XCTAssertEqual(try Data(contentsOf: unknown), unknownBytes)
        XCTAssertEqual(try Data(contentsOf: payloadFile), payloadBytes, "Conversation expiry must retain immutable field payloads")
        for saved in [recent, foreign, protected, restored, archived, linked] {
            for (path, bytes) in saved.records { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), bytes) }
        }
        // A sync-delayed old event cannot resurrect a purged conversation.
        let oldPath = try XCTUnwrap(expired.records.keys.first)
        try expired.descriptor.write(to: root.appendingPathComponent(".zerus/chats/" + expired.conversation.id + "/conversation.json"))
        for (path, bytes) in expired.records { try bytes.write(to: root.appendingPathComponent(path)) }
        do { _ = try await io.changeConversation(expired, device: device, change: .restore); XCTFail("A purged chat cannot be restored") }
        catch { XCTAssertTrue(error.localizedDescription.contains("chat-tombstones"), error.localizedDescription) }
        let again = try await io.conversations(device: device, protectedIDs: [protected.conversation.id], now: now)
        XCTAssertFalse(again.conversations.contains { $0.id == expired.conversation.id })
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(oldPath)), expired.records[oldPath])
    }
    func testPortableEventsRetainUnknownBytesAndEnforceOwnershipAndLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-conversations-" + UUID().uuidString), io = VaultFiles(root: root), a = MacChatDevice(id: "device-a", name: "First Mac"), b = MacChatDevice(id: "device-b", name: "Second Mac")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        var snapshot = try await io.createConversation(device: a, text: "A question about café notes", scope: MacConversations.data(["kind": "selection", "noteIds": ["note-a"]]))
        let descriptorFile = root.appendingPathComponent(".zerus/chats/" + snapshot.conversation.id + "/conversation.json")
        var descriptor = try MacConversations.object(snapshot.descriptor); descriptor["futureDescriptor"] = ["keep": true]
        let descriptorBytes = try MacConversations.data(descriptor); try descriptorBytes.write(to: descriptorFile)
        snapshot = try await io.conversationSnapshot(snapshot.conversation.id)
        let original = snapshot.records, user = try XCTUnwrap(snapshot.conversation.messages.first)
        var message: [String: Any] = ["id": "assistant-one", "turnId": user.turnID, "role": "assistant", "text": "Partial café", "createdAt": try MacConversations.timestamp(after: snapshot.records), "deviceId": a.id, "ownerGeneration": 1, "interrupted": true, "futureMessage": ["nested": [1, 2]]]
        snapshot = try await io.changeConversation(snapshot, device: a, change: .message(MacConversations.data(message)))
        message["text"] = "Partial café completed."; message["interrupted"] = false
        snapshot = try await io.changeConversation(snapshot, device: a, change: .message(MacConversations.data(message)))
        XCTAssertEqual(snapshot.conversation.messages.count, 2); XCTAssertEqual(snapshot.conversation.messages.last?.text, "Partial café completed."); XCTAssertFalse(try XCTUnwrap(snapshot.conversation.messages.last).interrupted)
        let raw = try MacConversations.object(XCTUnwrap(snapshot.conversation.messages.last).raw)
        XCTAssertEqual((raw["futureMessage"] as? [String: [Int]])?["nested"], [1, 2])
        snapshot = try await io.changeConversation(snapshot, device: a, change: .rename("Research conversation"))
        snapshot = try await io.changeConversation(snapshot, device: a, change: .archive); XCTAssertNotNil(snapshot.conversation.archivedAt)
        do { _ = try await io.changeConversation(snapshot, device: a, change: .message(MacConversations.data(message))); XCTFail("Archived conversations must remain read-only") } catch {}
        snapshot = try await io.changeConversation(snapshot, device: a, change: .delete); XCTAssertNotNil(snapshot.conversation.deletedAt)
        snapshot = try await io.changeConversation(snapshot, device: a, change: .restore); XCTAssertNil(snapshot.conversation.archivedAt); XCTAssertNil(snapshot.conversation.deletedAt)
        let stale = snapshot
        snapshot = try await io.changeConversation(snapshot, device: b, change: .claim)
        XCTAssertEqual(snapshot.conversation.owner, b); XCTAssertEqual(snapshot.conversation.generation, 2)
        do { _ = try await io.changeConversation(stale, device: a, change: .rename("Stale rename")); XCTFail("New ownership events must invalidate an old writer") } catch {}
        do { _ = try await io.changeConversation(snapshot, device: a, change: .rename("Wrong owner")); XCTFail("A different owner cannot rename") } catch {}
        for (path, bytes) in original { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), bytes) }
        XCTAssertEqual(try Data(contentsOf: descriptorFile), descriptorBytes)
        let list = try await io.conversations(); XCTAssertEqual(list.conversations.first?.title, "Research conversation"); XCTAssertTrue(list.issues.isEmpty)
        let tombstone = root.appendingPathComponent(".zerus/chat-tombstones/" + snapshot.conversation.id + ".json"); try FileManager.default.createDirectory(at: tombstone.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("{}".utf8).write(to: tombstone)
        do { _ = try await io.changeConversation(snapshot, device: b, change: .rename("Removed")); XCTFail("A tombstone cannot be overwritten") } catch {}
        let removed = try await io.conversations(); XCTAssertTrue(removed.conversations.isEmpty)
    }
    func testUnsupportedEventsAndLinkedFoldersRemainPreservedWithoutBlockingHealthyChats() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-conversation-preservation-" + UUID().uuidString), io = VaultFiles(root: root), device = MacChatDevice(id: "mac", name: "Mac")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let good = try await io.createConversation(device: device, text: "Readable chat", scope: MacConversations.data(["kind": "selection", "noteIds": []]))
        let bad = try await io.createConversation(device: device, text: "Future chat", scope: MacConversations.data(["kind": "selection", "noteIds": []]))
        let unknown = root.appendingPathComponent(".zerus/chats/" + bad.conversation.id + "/events/unsupported.json"), bytes = Data("{\"version\":99,\"future\":true}".utf8); try bytes.write(to: unknown)
        let list = try await io.conversations(); XCTAssertEqual(list.conversations.map(\.id), [good.conversation.id]); XCTAssertEqual(list.issues.count, 1)
        do { _ = try await io.changeConversation(bad, device: device, change: .rename("Unsafe")); XCTFail("A future event must invalidate the write review") } catch {}
        XCTAssertEqual(try Data(contentsOf: unknown), bytes)
        let alias = root.appendingPathComponent(".zerus/chats/alias"); try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root.appendingPathComponent(".zerus/chats/" + good.conversation.id))
        do { _ = try await io.conversationSnapshot("alias"); XCTFail("A linked conversation cannot be adopted") } catch {}
        let unchanged = try await io.conversationSnapshot(good.conversation.id); XCTAssertEqual(unchanged.conversation.title, "Readable chat")
    }
}

/// Saved timestamps are fixture data, independent of the retention calculation.
func ageDeletedConversation(_ snapshot: MacConversationSnapshot, at: Date, root: URL, io: VaultFiles) async throws -> MacConversationSnapshot {
    for (path, bytes) in snapshot.records {
        var object = try MacConversations.object(bytes)
        if object["kind"] as? String == "delete" {
            object["at"] = NativeRevisionIndex.timestamp(at)
            try MacConversations.data(object).write(to: root.appendingPathComponent(path))
        }
    }
    return try await io.conversationSnapshot(snapshot.conversation.id)
}
