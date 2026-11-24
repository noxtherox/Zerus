import XCTest
import Combine
import ImageIO
import UniformTypeIdentifiers
@testable import Zerus_Native

@MainActor final class MacChatControllerTests: XCTestCase {
    private let device = MacChatDevice(id: "native-test-mac", name: "Test Mac")
    private let first = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello café \"}}]}\n\n"
    private let finish = "data: {\"choices\":[{\"delta\":{\"content\":\"日本語\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
    private let anthropicFirst = "data: {\"type\":\"message_start\",\"message\":{\"role\":\"assistant\",\"content\":[]}}\n\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello café \"}}\n\n"
    private let anthropicFinish = "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"日本語\"}}\n\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n"
    func testHistoryRefreshExpiresTrashAfterPrivateDraftIsClearedAndPreservesUnreadableRuns() async throws {
        try await fixture { root, client, _ in
            let io = VaultFiles(root: root), chat = MacChatController(root: root, device: self.device, client: client)
            let initial = try await io.createConversation(device: self.device, text: "Old history", scope: MacConversations.data(["kind": "vault"]))
            try await chat.select(initial.conversation.id); chat.draft = "Keep this unsent question"
            let removed = try await io.changeConversation(initial, device: self.device, change: .delete)
            let aged = try await ageDeletedConversation(removed, at: Date().addingTimeInterval(-31 * 24 * 60 * 60), root: root, io: io)
            let descriptor = root.appendingPathComponent(".zerus/chats/" + initial.conversation.id + "/conversation.json")
            await chat.reload()
            XCTAssertEqual(chat.selectedID, initial.conversation.id); XCTAssertEqual(chat.draft, "Keep this unsent question")
            XCTAssertEqual(try Data(contentsOf: descriptor), aged.descriptor)
            // A private prompt in another selected conversation still protects it.
            try await chat.select(nil); await chat.reload(); XCTAssertTrue(chat.conversations.contains { $0.id == initial.conversation.id })
            try await chat.select(initial.conversation.id); XCTAssertEqual(chat.draft, "Keep this unsent question"); chat.draft = ""
            let badRun = root.appendingPathComponent(NativeAgentJournal.directory + "/" + UUID().uuidString.lowercased() + ".json"), badBytes = Data("{\"version\":99}".utf8)
            try FileManager.default.createDirectory(at: badRun.deletingLastPathComponent(), withIntermediateDirectories: true); try badBytes.write(to: badRun)
            await chat.reload()
            XCTAssertEqual(chat.selectedID, initial.conversation.id)
            XCTAssertTrue(chat.warnings.contains { $0.contains("unreadable native run") }, chat.warnings.joined(separator: "\n"))
            XCTAssertEqual(try Data(contentsOf: badRun), badBytes); XCTAssertEqual(try Data(contentsOf: descriptor), aged.descriptor)
            try FileManager.default.removeItem(at: badRun)
            let peer = MacWorkspace(); await peer.openVault(root)
            XCTAssertEqual(peer.root?.standardizedFileURL, root.standardizedFileURL)
            peer.busy = true
            await chat.reload()
            XCTAssertEqual(chat.selectedID, initial.conversation.id); XCTAssertEqual(try Data(contentsOf: descriptor), aged.descriptor)
            peer.busy = false
            await chat.reload()
            XCTAssertNil(chat.selectedID); XCTAssertTrue(chat.conversations.isEmpty); XCTAssertTrue(chat.draft.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: descriptor.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus/chat-tombstones/" + initial.conversation.id + ".json").path))
            let reopened = MacChatController(root: root, device: self.device, client: client); await reopened.reload()
            XCTAssertNil(reopened.selectedID); XCTAssertTrue(reopened.conversations.isEmpty)
        }
    }
    func testAnthropicRequestsKeepPortableImageDocumentAndNoteContextAndReopenWithoutKeys() async throws {
        for json in [false, true] {
            try await fixture { root, client, endpoint in
                let path = URL(string: endpoint)!.path
                let response = #"{"type":"message","role":"assistant","content":[{"type":"text","text":"Hello café 日本語"}],"stop_reason":"end_turn"}"#
                ChatHTTPFixture.register(.init(first: json ? response : self.anthropicFirst, remaining: json ? [] : [self.anthropicFinish], contentType: json ? "application/json" : "text/event-stream"), path: path)
                let chat = MacChatController(root: root, device: self.device, client: client), image = try makeChatTestImage(in: root)
                try chat.addImages([image]); try chat.addDocuments([.init(id: "doc", name: "Evidence.txt", text: "Independent document evidence.")]); chat.draft = "Review these sources"
                let done = expectation(description: "Anthropic reply saved"), subscription = chat.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
                try await chat.send(endpoint: endpoint, model: "fixture-model", apiKey: "synthetic-anthropic-key", sources: [.init(noteID: "source", title: "Context", folder: "Work", content: "# Context\n\nIndependent note evidence.\n")], format: .anthropic)
                await fulfillment(of: [done], timeout: 5); withExtendedLifetime(subscription) {}
                XCTAssertEqual(chat.messages.last?.text, "Hello café 日本語"); XCTAssertFalse(try XCTUnwrap(chat.messages.last).interrupted)
                let request = try XCTUnwrap(ChatHTTPFixture.captured(path)); XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "synthetic-anthropic-key"); XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }; var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
                let body = try MacConversations.object(data), messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                XCTAssertEqual(body["max_tokens"] as? Int, 4096); XCTAssertEqual(body["model"] as? String, "fixture-model"); XCTAssertTrue(body["system"] is String); XCTAssertFalse(messages.contains { $0["role"] as? String == "system" })
                let parts = messages.flatMap { $0["content"] as? [[String: Any]] ?? [] }, texts = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                XCTAssertTrue(texts.contains("Independent note evidence.")); XCTAssertTrue(texts.contains("Independent document evidence."))
                let source = try XCTUnwrap(parts.first { $0["type"] as? String == "image" }?["source"] as? [String: String]); XCTAssertEqual(source, ["type": "base64", "media_type": "image/jpeg", "data": image.bytes.base64EncodedString()])
                let reopened = MacChatController(root: root, device: self.device, client: client); await reopened.reload(); XCTAssertEqual(reopened.messages.last?.text, "Hello café 日本語")
                let saved = try await VaultFiles(root: root).conversationSnapshot(XCTUnwrap(chat.selectedID)); for bytes in saved.records.values { XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("synthetic-anthropic-key")) }
            }
        }
    }
    func testAnthropicJSONOutputLimitRetainsTextAndRetriesOneDurableTurn() async throws {
        try await fixture { root, client, endpoint in
            let path = URL(string: endpoint)!.path
            ChatHTTPFixture.register(.init(first: #"{"type":"message","role":"assistant","content":[{"type":"text","text":"Retained JSON partial"}],"stop_reason":"max_tokens"}"#, remaining: [], contentType: "application/json"), path: path)
            let chat = MacChatController(root: root, device: self.device, client: client); chat.draft = "A bounded reply"
            let partial = expectation(description: "JSON partial retained"), stopped = chat.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in partial.fulfill() }
            try await chat.send(endpoint: endpoint, model: "fixture-model", apiKey: "synthetic-key", sources: [], format: .anthropic)
            await fulfillment(of: [partial], timeout: 5); withExtendedLifetime(stopped) {}
            XCTAssertEqual(chat.messages.last?.text, "Retained JSON partial"); XCTAssertTrue(try XCTUnwrap(chat.messages.last).interrupted); XCTAssertTrue(chat.issue?.contains("limit") == true)
            let turn = try XCTUnwrap(chat.messages.last).turnID, id = try XCTUnwrap(chat.messages.last).id
            ChatHTTPFixture.register(.init(first: self.anthropicFirst, remaining: [self.anthropicFinish]), path: path)
            let done = expectation(description: "JSON reply retried"), finished = chat.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
            try await chat.retry(endpoint: endpoint, model: "fixture-model", apiKey: "synthetic-key", format: .anthropic)
            await fulfillment(of: [done], timeout: 5); withExtendedLifetime(finished) {}
            XCTAssertEqual(chat.messages.count, 2); XCTAssertEqual(chat.messages.last?.id, id); XCTAssertEqual(chat.messages.last?.turnID, turn); XCTAssertEqual(chat.messages.last?.text, "Hello café 日本語"); XCTAssertFalse(try XCTUnwrap(chat.messages.last).interrupted)
        }
    }
    func testDocumentDraftRecoveryAndRequestContextKeepPortableSnapshotsAfterSourceRemoval() async throws {
        try await fixture { root, client, endpoint in
            let path = URL(string: endpoint)!.path; ChatHTTPFixture.register(.init(first: self.first, remaining: [self.finish], paused: true), path: path)
            let original = root.appendingPathComponent("Review.md"), content = "# Review evidence\n\nThe verified launch date is Friday.\n"
            try Data(content.utf8).write(to: original)
            let document = try await MacChatDocument.prepare(original), draft = MacChatController(root: root, device: self.device, client: client)
            try draft.addDocuments([document]); let retained = await draft.prepareToLeave(); XCTAssertTrue(retained)
            try FileManager.default.removeItem(at: original)
            let chat = MacChatController(root: root, device: self.device, client: client)
            XCTAssertEqual(chat.selectedDocuments.first?.text, content); XCTAssertTrue(chat.draft.isEmpty)
            let visible = expectation(description: "document reply partial"), subscription = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Hello café " }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.send(endpoint: endpoint, model: "fixture-model", apiKey: "fixture-key", sources: [])
            await fulfillment(of: [visible], timeout: 5); withExtendedLifetime(subscription) {}
            let stopped = await chat.prepareToLeave(); XCTAssertTrue(stopped); XCTAssertTrue(chat.selectedDocuments.isEmpty)
            XCTAssertEqual(chat.documentContextStatus, "Full file context · conservative context budget")
            let recorded = try XCTUnwrap(ChatHTTPFixture.captured(path)), stream = try XCTUnwrap(recorded.httpBodyStream); stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
            let request = try MacConversations.object(data), messages = try XCTUnwrap(request["messages"] as? [[String: String]])
            XCTAssertTrue(messages.contains { $0["content"]?.contains("The verified launch date is Friday.") == true }); XCTAssertTrue(messages.contains { $0["content"]?.contains("untrusted reference data") == true })
            let io = VaultFiles(root: root), saved = try await io.conversationSnapshot(XCTUnwrap(chat.selectedID)), raw = try MacConversations.object(XCTUnwrap(saved.conversation.messages.first).raw)
            XCTAssertEqual((raw["documents"] as? [[String: String]])?.first, ["name": "Review.md", "text": content])
            let reopened = MacChatController(root: root, device: self.device, client: client); await reopened.reload(); XCTAssertTrue(reopened.selectedDocuments.isEmpty)
            ChatHTTPFixture.register(.init(first: self.first, remaining: [self.finish]), path: path)
            let finished = expectation(description: "document retry completed"), completed = chat.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
            try await chat.retry(endpoint: endpoint, model: "fixture-model", apiKey: "fixture-key")
            await fulfillment(of: [finished], timeout: 5); withExtendedLifetime(completed) {}
            XCTAssertEqual(chat.messages.count, 2); XCTAssertFalse(try XCTUnwrap(chat.messages.last).interrupted)
        }
    }
    func testStoppingDuringPreparationRetainsOneSavedQuestionWithoutStartingTheProvider() async throws {
        try await fixture { root, client, endpoint in
            let path = URL(string: endpoint)!.path; ChatHTTPFixture.register(.init(first: self.first, remaining: [self.finish], paused: true), path: path)
            let chat = MacChatController(root: root, device: self.device, client: client); chat.draft = "Keep this question when stopped"
            let stop = chat.$preparing.dropFirst().filter { $0 }.prefix(1).sink { _ in chat.stop() }
            do { try await chat.send(endpoint: endpoint, model: "fixture-model", apiKey: "fixture-key", sources: []); XCTFail("Stop during preparation must cancel provider startup") } catch is CancellationError {} catch { XCTFail("Expected cancellation, got \(error)") }
            let retained = await chat.prepareToLeave(); XCTAssertTrue(retained); withExtendedLifetime(stop) {}
            XCTAssertNil(ChatHTTPFixture.captured(path)); XCTAssertFalse(chat.running)
            let saved = try await VaultFiles(root: root).conversations(); XCTAssertEqual(saved.conversations.count, 1)
            XCTAssertEqual(saved.conversations.first?.messages.map(\.text), ["Keep this question when stopped"])
            let reopened = MacChatController(root: root, device: self.device, client: client); await reopened.reload()
            XCTAssertEqual(reopened.selectedID, saved.conversations.first?.id); XCTAssertTrue(reopened.draft.isEmpty)
            XCTAssertEqual(reopened.messages.first?.text, "Keep this question when stopped")
        }
    }
    func testUnsentImageRecoveryAndMultimodalRequestUseTheSavedPortableBytes() async throws {
        try await fixture { root, client, endpoint in
            let path = URL(string: endpoint)!.path; ChatHTTPFixture.register(.init(first: self.first, remaining: [self.finish], paused: true), path: path)
            let image = try makeChatTestImage(in: root), original = root.appendingPathComponent("Synthetic.png")
            let draft = MacChatController(root: root, device: self.device, client: client); try draft.addImages([image])
            let draftRetained = await draft.prepareToLeave(); XCTAssertTrue(draftRetained)
            let chat = MacChatController(root: root, device: self.device, client: client)
            XCTAssertEqual(chat.selectedImages.first?.bytes, image.bytes); XCTAssertTrue(chat.draft.isEmpty)
            let visible = expectation(description: "image reply partial"), subscription = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Hello café " }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.send(endpoint: endpoint, model: "fixture-vision", apiKey: "fixture-key", sources: [])
            await fulfillment(of: [visible], timeout: 5); withExtendedLifetime(subscription) {}
            let stopped = await chat.prepareToLeave(); XCTAssertTrue(stopped); XCTAssertTrue(chat.selectedImages.isEmpty)
            let request = try XCTUnwrap(ChatHTTPFixture.captured(path)), stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
            let body = try MacConversations.object(data), messages = try XCTUnwrap(body["messages"] as? [[String: Any]]), user = try XCTUnwrap(messages.first { $0["role"] as? String == "user" }), parts = try XCTUnwrap(user["content"] as? [[String: Any]])
            XCTAssertEqual(parts.first?["text"] as? String, "Describe the attached images.")
            XCTAssertEqual((parts.last?["image_url"] as? [String: String])?["url"], "data:image/jpeg;base64," + image.bytes.base64EncodedString())
            let io = VaultFiles(root: root), saved = try await io.conversationSnapshot(XCTUnwrap(chat.selectedID)), persisted = try await io.conversationImages(XCTUnwrap(saved.conversation.messages.first), conversationID: saved.conversation.id)
            XCTAssertEqual(persisted.first?.bytes, image.bytes)
            let reopened = MacChatController(root: root, device: self.device, client: client); await reopened.reload(); XCTAssertTrue(reopened.selectedImages.isEmpty)
            let asset = root.appendingPathComponent(image.metadata(conversationID: saved.conversation.id)["path"] as! String), keptAsset = root.appendingPathComponent("Kept.jpg")
            try FileManager.default.moveItem(at: asset, to: keptAsset)
            do { try await chat.retry(endpoint: endpoint + "/missing-image", model: "fixture-vision", apiKey: "fixture-key"); XCTFail("Missing images must fail before starting a request") } catch {}
            XCTAssertFalse(chat.running); XCTAssertNil(ChatHTTPFixture.captured(path + "/missing-image"))
            try FileManager.default.moveItem(at: keptAsset, to: asset)
            // Retry reuses the saved image; it does not depend on the original import.
            try FileManager.default.removeItem(at: original)
            ChatHTTPFixture.register(.init(first: self.first, remaining: [self.finish]), path: path)
            let finished = expectation(description: "image retry completed"), completed = chat.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
            try await chat.retry(endpoint: endpoint, model: "fixture-vision", apiKey: "fixture-key")
            await fulfillment(of: [finished], timeout: 5); withExtendedLifetime(completed) {}
            XCTAssertEqual(chat.messages.count, 2); XCTAssertFalse(try XCTUnwrap(chat.messages.last).interrupted)
        }
    }
    func testSuccessfulStreamingPersistsContextAndReopensWithoutCredentialsInHistory() async throws {
        try await fixture { root, client, endpoint in
            let path = URL(string: endpoint)!.path; ChatHTTPFixture.register(.init(first: self.first, remaining: [self.finish]), path: path)
            let chat = MacChatController(root: root, device: self.device, client: client)
            chat.draft = "Summarize this fixture note"
            let finished = expectation(description: "reply saved"), subscription = chat.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
            try await chat.send(endpoint: endpoint, model: "fixture-model", apiKey: "synthetic-test-key", sources: [.init(noteID: "note-one", title: "Fixture context", folder: "Work", content: "# Fixture context\n\nOnly synthetic notes.\n")])
            await fulfillment(of: [finished], timeout: 5)
            withExtendedLifetime(subscription) {}
            XCTAssertEqual(chat.messages.count, 2); XCTAssertEqual(chat.messages.last?.text, "Hello café 日本語"); XCTAssertFalse(try XCTUnwrap(chat.messages.last).interrupted)
            XCTAssertTrue(chat.draft.isEmpty); XCTAssertFalse(chat.hasUnsavedReply)
            let recorded = try XCTUnwrap(ChatHTTPFixture.captured(path)); XCTAssertEqual(recorded.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-key")
            let body: Data
            if let data = recorded.httpBody { body = data }
            else { let stream = try XCTUnwrap(recorded.httpBodyStream); stream.open(); defer { stream.close() }; var value = Data(), buffer = [UInt8](repeating: 0, count: 4096); while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; value.append(contentsOf: buffer.prefix(count)) }; body = value }
            let request = try MacConversations.object(body), messages = try XCTUnwrap(request["messages"] as? [[String: String]])
            XCTAssertEqual(request["stream"] as? Bool, true); XCTAssertTrue(messages.contains { $0["content"]?.contains("Only synthetic notes.") == true })
            let reopened = MacChatController(root: root, device: self.device, client: client); await reopened.reload()
            XCTAssertEqual(reopened.selectedID, chat.selectedID); XCTAssertEqual(reopened.messages.last?.text, "Hello café 日本語")
            let io = VaultFiles(root: root), saved = try await io.conversationSnapshot(XCTUnwrap(chat.selectedID))
            for bytes in saved.records.values { XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("synthetic-test-key")) }
            let user = try MacConversations.object(XCTUnwrap(saved.conversation.messages.first).raw), sources = try XCTUnwrap(user["sources"] as? [[String: String]])
            XCTAssertEqual(sources.first?["noteId"], "note-one"); XCTAssertEqual(sources.first?["excerpt"], "# Fixture context\n\nOnly synthetic notes.\n")
        }
    }
    func testStoppingStreamKeepsPartialReplyAndRetryCompletesSameTurn() async throws {
        for format in MacAIFormat.allCases {
        try await fixture { root, client, endpoint in
            let first = format == .anthropic ? self.anthropicFirst : self.first, finish = format == .anthropic ? self.anthropicFinish : self.finish
            let path = URL(string: endpoint)!.path; ChatHTTPFixture.register(.init(first: first, remaining: [finish], paused: true), path: path)
            let chat = MacChatController(root: root, device: self.device, client: client); chat.draft = "A cancellable question"
            let visible = expectation(description: "partial visible"), subscription = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Hello café " }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.send(endpoint: endpoint, model: "fixture-model", apiKey: "fixture-key", sources: [], format: format)
            await fulfillment(of: [visible], timeout: 5); withExtendedLifetime(subscription) {}
            let stopped = await chat.prepareToLeave(); XCTAssertTrue(stopped)
            XCTAssertFalse(chat.running); XCTAssertFalse(chat.hasUnsavedReply, "Stopping must finish the durable checkpoint outside the canceled network task"); XCTAssertEqual(chat.messages.last?.text, "Hello café "); XCTAssertTrue(try XCTUnwrap(chat.messages.last).interrupted)
            let turn = try XCTUnwrap(chat.messages.last).turnID, replyID = try XCTUnwrap(chat.messages.last).id
            ChatHTTPFixture.register(.init(first: first, remaining: [finish]), path: path)
            let finished = expectation(description: "retry completed"), retrySubscription = chat.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
            try await chat.retry(endpoint: endpoint, model: "fixture-model", apiKey: "fixture-key", format: format)
            await fulfillment(of: [finished], timeout: 5); withExtendedLifetime(retrySubscription) {}
            XCTAssertEqual(chat.messages.count, 2); XCTAssertEqual(chat.messages.last?.id, replyID); XCTAssertEqual(chat.messages.last?.turnID, turn); XCTAssertEqual(chat.messages.last?.text, "Hello café 日本語"); XCTAssertFalse(try XCTUnwrap(chat.messages.last).interrupted)
        }
        }
    }

    func testOwnershipChangeDuringReplyPreservesForeignEventAndPrivateRecovery() async throws {
        try await fixture { root, client, endpoint in
            let path = URL(string: endpoint)!.path; ChatHTTPFixture.register(.init(first: self.first, remaining: [self.finish], paused: true), path: path)
            let chat = MacChatController(root: root, device: self.device, client: client); chat.draft = "A shared-device question"
            let visible = expectation(description: "partial before transfer"), subscription = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Hello café " }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.send(endpoint: endpoint, model: "fixture-model", apiKey: "fixture-key", sources: [])
            await fulfillment(of: [visible], timeout: 5); withExtendedLifetime(subscription) {}
            let io = VaultFiles(root: root), before = try await io.conversationSnapshot(XCTUnwrap(chat.selectedID)), other = MacChatDevice(id: "other-device", name: "Other device")
            let transferred = try await io.changeConversation(before, device: other, change: .claim)
            let stopped = await chat.prepareToLeave(); XCTAssertTrue(stopped); XCTAssertTrue(chat.hasUnsavedReply); XCTAssertEqual(chat.recoveredReply, "Hello café ")
            let current = try await io.conversationSnapshot(transferred.conversation.id); XCTAssertEqual(current.conversation.owner, other)
            for (file, bytes) in transferred.records { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(file)), bytes) }
            let reopened = MacChatController(root: root, device: self.device, client: client); XCTAssertEqual(reopened.recoveredReply, "Hello café ")
            try chat.keepRecoveryAndContinue(); XCTAssertFalse(chat.hasUnsavedReply)
            // A later failed run must not replace the first recoverable reply.
            try await chat.change(.claim)
            ChatHTTPFixture.register(.init(first: "data: {\"choices\":[{\"delta\":{\"content\":\"Second recovery\"}}]}\n\n", remaining: [self.finish], paused: true), path: path)
            chat.draft = "A second shared-device question"
            let secondVisible = expectation(description: "second partial before transfer"), secondSubscription = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Second recovery" }.prefix(1).sink { _ in secondVisible.fulfill() }
            try await chat.send(endpoint: endpoint, model: "fixture-model", apiKey: "fixture-key", sources: [])
            await fulfillment(of: [secondVisible], timeout: 5); withExtendedLifetime(secondSubscription) {}
            _ = try await io.changeConversation(io.conversationSnapshot(XCTUnwrap(chat.selectedID)), device: other, change: .claim)
            let secondStopped = await chat.prepareToLeave(); XCTAssertTrue(secondStopped)
            let recoveredAgain = MacChatController(root: root, device: self.device, client: client)
            XCTAssertEqual(Set(recoveredAgain.recoveryArchive.map(\.text)), ["Hello café ", "Second recovery"])
        }
    }
    private func fixture(operation: (URL, MacAIClient, String) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-chat-controller-" + UUID().uuidString), path = "/fixture/" + UUID().uuidString
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ChatHTTPFixture.self]
        let session = URLSession(configuration: configuration), client = MacAIClient(session: session)
        let draft = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/Drafts/Chat/" + NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.absoluteString) + ".json")
        defer { session.invalidateAndCancel(); ChatHTTPFixture.remove(path); for folder in ["Images", "Documents"] { try? FileManager.default.removeItem(at: draft.deletingLastPathComponent().appendingPathComponent(folder + "/" + draft.deletingPathExtension().lastPathComponent)) }; try? FileManager.default.removeItem(at: draft); try? FileManager.default.removeItem(at: root) }
        try await operation(root, client, "https://native-chat-test.invalid" + path)
    }
}
