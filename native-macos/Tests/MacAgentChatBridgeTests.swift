import XCTest
import Combine
@testable import Zerus_Native

@MainActor final class MacAgentChatBridgeTests: XCTestCase {
    func testAgentConversationPersistsTheChosenReadScope() async throws {
        for kind in ["selection", "folder", "inbox", "vault"] {
            try await fixture { root, chat, controller, provider, route, _ in
                ChatHTTPFixture.register(.init(first: self.answer, remaining: []), path: route)
                chat.draft = "Inspect this scope"
                let scope = NativeAgentScope(paths: ["Alpha.md"], folder: kind == "folder" ? "Work" : kind == "inbox" ? "" : nil, entireVault: kind == "vault", allowCreation: false)
                let done = self.expectation(description: "scope turn saved")
                let observation = controller.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
                try await chat.sendAgent(controller: controller, mode: .ask, scope: scope, sources: [], provider: provider, capacity: 128_000)
                await self.fulfillment(of: [done], timeout: 5); withExtendedLifetime(observation) {}
                XCTAssertNil(controller.issue)
                let saved = try await VaultFiles(root: root).conversationSnapshot(XCTUnwrap(chat.selectedID))
                let storedScope = try MacConversations.object(saved.conversation.scope)
                XCTAssertEqual(storedScope["kind"] as? String, kind == "folder" || kind == "inbox" ? "type" : kind)
                if kind == "folder" || kind == "inbox" { XCTAssertEqual(storedScope["path"] as? [String], kind == "folder" ? ["Work"] : []) }
                if kind == "selection" { XCTAssertEqual(storedScope["noteIds"] as? [String], []) }
                XCTAssertTrue(controller.current?.run.createFolders.isEmpty == true)
            }
        }
    }

    private let device = MacChatDevice(id: "agent-chat-fixture", name: "Fixture Mac")
    private let partial = "data: {\"choices\":[{\"delta\":{\"content\":\"Retained partial\"}}]}\n\n"
    private let answer = "data: {\"choices\":[{\"delta\":{\"content\":\"Finished answer\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"

    func testAgentConversationLinksRunAndRetainsPortableInputsOnReopen() async throws {
        try await fixture { root, chat, controller, provider, route, client in
            ChatHTTPFixture.register(.init(first: self.partial, remaining: [], paused: true), path: route)
            let image = try makeChatTestImage(in: root)
            try chat.addImages([image]); try chat.addDocuments([.init(id: "evidence", name: "Evidence.txt", text: "Frozen document evidence.")]); chat.draft = "Read this evidence"
            let visible = self.expectation(description: "agent partial reaches conversation")
            let observation = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Retained partial" }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.sendAgent(controller: controller, mode: .ask, scope: .init(paths: ["Alpha.md"]), sources: [], provider: provider, capacity: 128_000)
            await self.fulfillment(of: [visible], timeout: 5); withExtendedLifetime(observation) {}
            let record = try XCTUnwrap(controller.current), saved = try await VaultFiles(root: root).conversationSnapshot(XCTUnwrap(chat.selectedID))
            let reply = try XCTUnwrap(saved.conversation.messages.last)
            XCTAssertEqual(try MacConversations.object(reply.raw)["runId"] as? String, record.id.uuidString.lowercased())
            XCTAssertEqual(reply.turnID, saved.conversation.messages.first?.turnID)
            XCTAssertEqual(record.run.chatID, saved.conversation.id)
            let store = MacAgentChatInput.store(root: root), inputs = try XCTUnwrap(record.run.attachments)
            XCTAssertEqual(try store.read(XCTUnwrap(inputs.first { $0.kind == .image })), image.bytes)
            XCTAssertEqual(try store.read(XCTUnwrap(inputs.first { $0.kind == .document }), text: true), Data("Frozen document evidence.".utf8))
            XCTAssertNotNil(ChatHTTPFixture.captured(route)); XCTAssertFalse(String(decoding: record.bytes, as: UTF8.self).contains("synthetic-key"))
            let stopped = await chat.prepareToLeave(); XCTAssertTrue(stopped)
            let reopened = MacChatController(root: root, device: self.device, client: client); await reopened.reload()
            XCTAssertEqual(reopened.messages.last?.text, "Retained partial"); XCTAssertTrue(reopened.selectedImages.isEmpty); XCTAssertTrue(reopened.selectedDocuments.isEmpty)
            XCTAssertEqual(try MacConversations.object(XCTUnwrap(reopened.messages.last).raw)["runId"] as? String, record.id.uuidString.lowercased())
        }
    }

    func testStopAndResumeKeepInterruptedTurnAndUnsentDraft() async throws {
        try await fixture { root, chat, controller, provider, route, client in
            ChatHTTPFixture.register(.init(first: self.partial, remaining: [], paused: true), path: route)
            chat.draft = "Read Alpha"
            let visible = self.expectation(description: "partial before stop")
            let observation = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Retained partial" }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.sendAgent(controller: controller, mode: .ask, scope: .init(paths: ["Alpha.md"]), sources: [], provider: provider, capacity: 128_000)
            await self.fulfillment(of: [visible], timeout: 5); withExtendedLifetime(observation) {}
            chat.draft = "Unsent next question"
            let stopped = await chat.prepareToLeave(); XCTAssertTrue(stopped)
            let paused = try XCTUnwrap(controller.current)
            XCTAssertEqual(paused.run.status, "interrupted"); XCTAssertNil(paused.run.requestReservation)
            XCTAssertTrue(try XCTUnwrap(chat.messages.last).interrupted)
            try chat.addDocuments([.init(id: "unsent", name: "Unsent.txt", text: "Do not send this draft yet.")])
            ChatHTTPFixture.register(.init(first: self.answer, remaining: []), path: route)
            let done = self.expectation(description: "resumed conversation saved")
            let finished = chat.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
            try await chat.resumeAgent(paused, controller: controller, provider: provider)
            await self.fulfillment(of: [done], timeout: 5); withExtendedLifetime(finished) {}
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.current?.run.status, "complete")
            XCTAssertEqual(chat.messages.map(\.text), ["Read Alpha", "Retained partial", "Continue: Read Alpha", "Finished answer"])
            XCTAssertEqual(chat.draft, "Unsent next question"); XCTAssertEqual(chat.selectedDocuments.first?.name, "Unsent.txt")
            let reopened = MacChatController(root: root, device: self.device, client: client); await reopened.reload()
            XCTAssertEqual(reopened.messages.last?.text, "Finished answer"); XCTAssertEqual(reopened.draft, "Unsent next question"); XCTAssertEqual(reopened.selectedDocuments.first?.text, "Do not send this draft yet.")
        }
    }

    func testOrdinaryRetryCannotDetachAnAgentReplyFromItsRun() async throws {
        try await fixture { root, chat, controller, provider, route, _ in
            ChatHTTPFixture.register(.init(first: self.partial, remaining: [], paused: true), path: route)
            chat.draft = "Read Alpha"
            let visible = self.expectation(description: "linked partial")
            let observation = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Retained partial" }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.sendAgent(controller: controller, mode: .ask, scope: .init(paths: ["Alpha.md"]), sources: [], provider: provider, capacity: 128_000)
            await self.fulfillment(of: [visible], timeout: 5); withExtendedLifetime(observation) {}
            let stopped = await chat.prepareToLeave(); XCTAssertTrue(stopped)
            let before = try await VaultFiles(root: root).conversationSnapshot(XCTUnwrap(chat.selectedID))
            ChatHTTPFixture.remove(route)
            do {
                try await chat.retry(endpoint: "https://fixture.invalid" + route, model: "fixture-model", apiKey: "synthetic-key")
                XCTFail("An agent reply must resume its saved run instead of ordinary Retry")
            } catch { XCTAssertTrue(error.localizedDescription.contains("Resume"), error.localizedDescription) }
            XCTAssertFalse(chat.running)
            let after = try await VaultFiles(root: root).conversationSnapshot(XCTUnwrap(chat.selectedID))
            XCTAssertEqual(after.records, before.records)
        }
    }

    func testOwnershipTransferStopsFurtherToolsAndProviderRequests() async throws {
        try await fixture { root, chat, controller, provider, route, _ in
            let tool = "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"read-alpha\",\"type\":\"function\",\"function\":{\"name\":\"note_get\",\"arguments\":\"{\\\"selector\\\":\\\"alpha\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n"
            let sentAgain = self.expectation(description: "no provider request after ownership transfer"); sentAgain.isInverted = true
            let script = ChatHTTPFixture.Script(first: self.partial, remaining: [tool], paused: true, next: .init(first: self.answer, remaining: [], onStart: { sentAgain.fulfill() }))
            ChatHTTPFixture.register(script, path: route); chat.draft = "Read Alpha"
            let visible = self.expectation(description: "partial before transfer")
            let observation = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Retained partial" }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.sendAgent(controller: controller, mode: .ask, scope: .init(paths: ["Alpha.md"]), sources: [], provider: provider, capacity: 128_000)
            await self.fulfillment(of: [visible], timeout: 5); withExtendedLifetime(observation) {}
            let io = VaultFiles(root: root), current = try await io.conversationSnapshot(XCTUnwrap(chat.selectedID))
            _ = try await io.changeConversation(current, device: .init(id: "other", name: "Other Mac"), change: .claim)
            let done = self.expectation(description: "run stops after authority changes")
            let finished = controller.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
            script.gate?.signal()
            await self.fulfillment(of: [done], timeout: 5); withExtendedLifetime(finished) {}
            await self.fulfillment(of: [sentAgain], timeout: 0.1)
            XCTAssertEqual(controller.current?.run.status, "interrupted")
            XCTAssertTrue(controller.current?.run.messages.filter { $0.role == "tool" }.isEmpty == true)
            XCTAssertTrue(controller.issue?.contains("conversation") == true)
        }
    }

    func testEarlyStopKeepsAttachmentGrantForResume() async throws {
        try await fixture { root, chat, controller, provider, route, _ in
            try chat.addDocuments([.init(id: "early", name: "Evidence.txt", text: "Frozen early evidence.")]); chat.draft = "Read evidence"
            let cancelled = controller.$current.compactMap { $0 }.prefix(1).sink { _ in controller.stop() }
            let stopped = self.expectation(description: "early stop saved")
            let observation = controller.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in stopped.fulfill() }
            try await chat.sendAgent(controller: controller, mode: .ask, scope: .init(paths: ["Alpha.md"]), sources: [], provider: provider, capacity: 128_000)
            await self.fulfillment(of: [stopped], timeout: 5); withExtendedLifetime((cancelled, observation)) {}
            let record = try XCTUnwrap(controller.current), store = MacAgentChatInput.store(root: root)
            XCTAssertNil(ChatHTTPFixture.captured(route))
            XCTAssertNoThrow(try store.validate(run: record.id, chat: record.run.chatID, items: record.run.attachments ?? []))
            ChatHTTPFixture.register(.init(first: self.answer, remaining: []), path: route)
            let done = self.expectation(description: "early stopped run resumed")
            let finished = controller.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
            try await chat.resumeAgent(record, controller: controller, useSelectedConnection: true, provider: provider)
            await self.fulfillment(of: [done], timeout: 5); withExtendedLifetime(finished) {}
            XCTAssertNil(controller.issue); XCTAssertEqual(controller.current?.run.status, "complete")
        }
    }

    func testRejectedResumeDoesNotWriteConversationOrClearSavedRun() async throws {
        try await fixture { root, chat, controller, provider, route, _ in
            ChatHTTPFixture.register(.init(first: self.partial, remaining: [], paused: true), path: route); chat.draft = "Read Alpha"
            let visible = self.expectation(description: "partial before rejected resume")
            let observation = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Retained partial" }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.sendAgent(controller: controller, mode: .ask, scope: .init(paths: ["Alpha.md"]), sources: [], provider: provider, capacity: 128_000)
            await self.fulfillment(of: [visible], timeout: 5); withExtendedLifetime(observation) {}
            let stopped = await chat.prepareToLeave(); XCTAssertTrue(stopped)
            let record = try XCTUnwrap(controller.current), before = try await VaultFiles(root: root).conversationSnapshot(XCTUnwrap(chat.selectedID))
            let changed = MacAgentProvider.api(profile: .init(provider: .compatible, endpoint: "https://fixture.invalid" + route, model: "other-model"), key: "synthetic-key")
            do { try await chat.resumeAgent(record, controller: controller, answer: "Keep this answer", provider: changed); XCTFail("Changed connection must be rejected before a conversation write") }
            catch { XCTAssertTrue(error.localizedDescription.contains("differs"), error.localizedDescription) }
            _ = await controller.stopAndCheckpoint()
            let after = try await VaultFiles(root: root).conversationSnapshot(XCTUnwrap(chat.selectedID))
            XCTAssertEqual(after.records, before.records); XCTAssertEqual(controller.current?.id, record.id)
            XCTAssertEqual(controller.current?.bytes, record.bytes)
            ChatHTTPFixture.register(.init(first: self.answer, remaining: []), path: route)
            let done = self.expectation(description: "explicit replacement saved")
            let finished = controller.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
            try await chat.resumeAgent(record, controller: controller, answer: "Use the new model", useSelectedConnection: true, provider: changed)
            await self.fulfillment(of: [done], timeout: 5); withExtendedLifetime(finished) {}
            let rebound = try XCTUnwrap(controller.current)
            XCTAssertNil(controller.issue); XCTAssertEqual(rebound.run.status, "complete")
            XCTAssertEqual(try MacAgentProviderBinding.read(rebound)?.model, "other-model")
            XCTAssertEqual(rebound.run.readIDs, record.run.readIDs); XCTAssertEqual(rebound.run.writeIDs, record.run.writeIDs); XCTAssertEqual(rebound.run.limits, record.run.limits)
            XCTAssertEqual(chat.messages.suffix(2).map(\.text), ["Continue: Use the new model", "Finished answer"])
            XCTAssertEqual(try MacConversations.object(XCTUnwrap(chat.messages.last).raw)["runId"] as? String, record.id.uuidString.lowercased())
        }
    }

    func testConversationOwnershipTransferKeepsPartialInPrivateRecovery() async throws {
        try await fixture { root, chat, controller, provider, route, client in
            ChatHTTPFixture.register(.init(first: self.partial, remaining: [], paused: true), path: route)
            chat.draft = "A shared conversation"
            let visible = self.expectation(description: "partial before owner transfer")
            let observation = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Retained partial" }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.sendAgent(controller: controller, mode: .ask, scope: .init(paths: ["Alpha.md"]), sources: [], provider: provider, capacity: 128_000)
            await self.fulfillment(of: [visible], timeout: 5); withExtendedLifetime(observation) {}
            let io = VaultFiles(root: root), before = try await io.conversationSnapshot(XCTUnwrap(chat.selectedID))
            let transferred = try await io.changeConversation(before, device: .init(id: "other", name: "Other Mac"), change: .claim)
            let stopped = await chat.prepareToLeave(); XCTAssertTrue(stopped)
            XCTAssertTrue(chat.hasUnsavedReply); XCTAssertEqual(chat.recoveredReply, "Retained partial")
            XCTAssertEqual(controller.current?.run.status, "interrupted"); XCTAssertNil(controller.current?.run.requestReservation)
            for (path, bytes) in transferred.records { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), bytes) }
            let reopened = MacChatController(root: root, device: self.device, client: client)
            XCTAssertEqual(reopened.recoveredReply, "Retained partial")
        }
    }

    private func fixture(_ operation: (URL, MacChatController, MacAgentController, MacAgentProvider, String, MacAIClient) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-agent-chat-" + UUID().uuidString), defaults = UserDefaults.standard
        let recent = defaults.stringArray(forKey: "zerus.mac.recentVaults") ?? []
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("---\nzerus-id: alpha\n---\n# Alpha\n\nOriginal.\n".utf8).write(to: root.appendingPathComponent("Alpha.md"))
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ChatHTTPFixture.self]
        let session = URLSession(configuration: configuration), client = MacAIClient(session: session), route = "/" + UUID().uuidString + "/chat/completions"
        let workspace = MacWorkspace(); await workspace.openVault(root); await workspace.openNote("Alpha.md")
        let controller = try MacAgentController(workspace: workspace, owner: device.id, client: client), chat = MacChatController(root: root, device: device, client: client)
        let provider = MacAgentProvider.api(profile: .init(provider: .compatible, endpoint: "https://fixture.invalid" + route, model: "fixture-model", contextWindow: 128_000), key: "synthetic-key")
        let result: Result<Void, Error>
        do { try await operation(root, chat, controller, provider, route, client); result = .success(()) } catch { result = .failure(error) }
        _ = await chat.prepareToLeave(); _ = await workspace.prepareToCloseWindow()
        for record in controller.records { try? controller.workspace.continuations.remove(run: record.id) }
        session.invalidateAndCancel(); ChatHTTPFixture.remove(route)
        let draft = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/Drafts/Chat/" + NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.absoluteString) + ".json")
        for folder in ["Images", "Documents"] { try? FileManager.default.removeItem(at: draft.deletingLastPathComponent().appendingPathComponent(folder + "/" + draft.deletingPathExtension().lastPathComponent)) }
        for location in [draft, MacAgentChatInput.store(root: root).directory, workspace.taskDraftStore?.directory, root].compactMap({ $0 }) { try? FileManager.default.removeItem(at: location) }
        defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path)); defaults.set(recent, forKey: "zerus.mac.recentVaults")
        try result.get()
    }
}
