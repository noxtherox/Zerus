import XCTest
import Combine
import Security
import ZerusChatGPTCore
@testable import Zerus_Native

@MainActor final class MacChatGPTConnectionTests: XCTestCase {
    private let modelPath = "/v1/models", responsePath = "/v1/responses", tokenPath = "/api/accounts/oauth/token"
    private let catalog = #"{"models":[{"visibility":"list","slug":"fixture-chatgpt","display_name":"Fixture ChatGPT","context_window":32768},{"visibility":"list","slug":"fixture-other","display_name":"Other fixture"},{"visibility":"hidden","slug":"hidden-model"}]}"#
    private let first = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello account \"}\n\n"
    private let finish = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"日本語\"}\n\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[]}}\n\n"
    func testPassiveConnectionCheckDoesNotCreateAKeychainRegistrationBeforeSignIn() async throws {
        let service = "com.zerus.notes.passive-test." + UUID().uuidString
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "accounts-v1", kSecAttrSynchronizable as String: false]
        defer { SecItemDelete(query as CFDictionary) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ChatHTTPFixture.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        let connection = MacChatGPTConnection(manager: ChatGPTManager(service: service, session: session))
        await connection.refreshStatus()
        XCTAssertEqual(connection.state?.configured, false); XCTAssertTrue(connection.state?.accounts?.isEmpty == true)
        var attributes = query; attributes[kSecReturnAttributes as String] = true
        XCTAssertEqual(SecItemCopyMatching(attributes as CFDictionary, nil), errSecItemNotFound, "Passive browsing must not create a registration that later builds need permission to read")
    }
    func testColdRestoredModelRemovedFromCatalogDoesNotSilentlyUseItsReplacement() async throws {
        try await fixture(model: "retired-model") { root, connection, _, _ in
            let chat = MacChatController(root: root, device: .init(id: "account-test-mac", name: "Fixture Mac")); chat.draft = "Keep this question for the selected model"
            let stopped = expectation(description: "catalog mismatch stopped"), subscription = chat.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in stopped.fulfill() }
            try await chat.send(endpoint: "", model: "", apiKey: "", sources: [], chatGPT: connection)
            await fulfillment(of: [stopped], timeout: 5); withExtendedLifetime(subscription) {}
            XCTAssertNil(ChatHTTPFixture.captured(self.responsePath), "Discovery must not silently send a question to the first replacement model")
            XCTAssertTrue(chat.issue?.contains("changed") == true)
            XCTAssertEqual(chat.messages.first?.text, "Keep this question for the selected model"); XCTAssertTrue(try XCTUnwrap(chat.messages.last).interrupted)
        }
    }
    func testAccountRouteStreamsStopsRetriesAndKeepsImagesAndDocumentsOutOfCredentialStorage() async throws {
        try await fixture { root, connection, query, _ in
            ChatHTTPFixture.register(.init(first: self.first, remaining: [self.finish], paused: true), path: self.responsePath)
            let chat = MacChatController(root: root, device: .init(id: "account-test-mac", name: "Fixture Mac"))
            chat.draft = "Review the synthetic account context"
            let image = try makeChatTestImage(in: root); try chat.addImages([image])
            try chat.addDocuments([.init(id: UUID().uuidString.lowercased(), name: "Evidence.txt", text: "Synthetic document evidence.")])
            let visible = expectation(description: "account stream partial"), subscription = chat.livePublisher.compactMap { $0?.text }.filter { $0 == "Hello account " }.prefix(1).sink { _ in visible.fulfill() }
            try await chat.send(endpoint: "", model: "", apiKey: "", sources: [], chatGPT: connection)
            await fulfillment(of: [visible], timeout: 5); withExtendedLifetime(subscription) {}
            XCTAssertEqual(connection.activeRequests, 1)
            do { try await connection.selectModel("fixture-other", owner: UUID()); XCTFail("Account/model changes must not redirect an active reply") } catch { XCTAssertTrue(error.localizedDescription.contains("active ChatGPT")) }
            let stopped = await chat.prepareToLeave(); XCTAssertTrue(stopped); XCTAssertFalse(chat.hasUnsavedReply); XCTAssertEqual(connection.activeRequests, 0)
            let request = try XCTUnwrap(ChatHTTPFixture.captured(self.responsePath)); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-access")
            let body = try MacConversations.object(try self.body(request)); XCTAssertEqual(body["store"] as? Bool, false); XCTAssertEqual(body["model"] as? String, "fixture-chatgpt")
            let input = try XCTUnwrap(body["input"] as? [[String: Any]]), parts = input.compactMap { $0["content"] as? [[String: Any]] }.flatMap { $0 }
            XCTAssertTrue(parts.contains { $0["text"] as? String == "Review the synthetic account context" })
            XCTAssertTrue(parts.contains { ($0["text"] as? String)?.contains("Synthetic document evidence.") == true })
            XCTAssertTrue(parts.contains { $0["image_url"] as? String == "data:image/jpeg;base64," + image.bytes.base64EncodedString() })
            let saved = try await VaultFiles(root: root).conversationSnapshot(XCTUnwrap(chat.selectedID))
            for bytes in saved.records.values { let text = String(decoding: bytes, as: UTF8.self); XCTAssertFalse(text.contains("synthetic-access")); XCTAssertFalse(text.contains("synthetic-refresh")) }
            let accountState = try self.saved(query), privateRecord = String(decoding: try JSONSerialization.data(withJSONObject: accountState), as: UTF8.self)
            XCTAssertFalse(privateRecord.contains("Review the synthetic account context")); XCTAssertFalse(privateRecord.contains("Synthetic document evidence.")); XCTAssertFalse(privateRecord.contains(image.bytes.base64EncodedString()))
            ChatHTTPFixture.register(.init(first: self.first, remaining: [self.finish]), path: self.responsePath)
            let completed = expectation(description: "account retry completed"), completion = chat.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in completed.fulfill() }
            try await chat.retry(endpoint: "", model: "", apiKey: "", chatGPT: connection)
            await fulfillment(of: [completed], timeout: 5); withExtendedLifetime(completion) {}
            XCTAssertEqual(chat.messages.count, 2); XCTAssertEqual(chat.messages.last?.text, "Hello account 日本語"); XCTAssertFalse(try XCTUnwrap(chat.messages.last).interrupted)
            let previous = try await connection.selection()
            try await connection.selectModel("fixture-other", owner: UUID())
            ChatHTTPFixture.remove(self.responsePath)
            do { _ = try await connection.stream(selection: previous, conversationID: saved.conversation.id, messages: [.init(role: "system", content: "Fixture instructions"), .init(role: "user", content: "Do not send")]) { _ in }; XCTFail("A stale selected account/model must not start a request") } catch { XCTAssertTrue(error.localizedDescription.contains("changed")) }
            XCTAssertNil(ChatHTTPFixture.captured(self.responsePath))
        }
    }
    func testRefreshRotationSignOutAndExpiredGrantKeepTheSavedAccountRegistration() async throws {
        try await fixture(expired: true) { _, connection, query, registration in
            ChatHTTPFixture.register(.init(first: #"{"access_token":"synthetic-refreshed","refresh_token":"synthetic-rotated","expires_in":3600,"token_type":"bearer","scope":"resource.invoke chatgpt.tokens.use.direct"}"#, remaining: [], contentType: "application/json"), path: self.tokenPath)
            try await connection.refreshModels(owner: UUID())
            XCTAssertEqual(connection.models.map(\.id), ["fixture-chatgpt", "fixture-other"])
            XCTAssertEqual(ChatHTTPFixture.captured(self.modelPath)?.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-refreshed")
            let token = try XCTUnwrap(ChatHTTPFixture.captured(self.tokenPath)), form = String(decoding: try self.body(token), as: UTF8.self)
            XCTAssertTrue(form.contains("grant_type=refresh_token")); XCTAssertTrue(form.contains("client_id=" + registration["clientID"]!))
            let refreshed = try self.saved(query), accounts = try XCTUnwrap(refreshed["accounts"] as? [[String: Any]])
            XCTAssertEqual((accounts.first?["credentials"] as? [String: Any])?["refreshToken"] as? String, "synthetic-rotated")
            ChatHTTPFixture.register(.init(first: #"{"revocation_endpoint":"https://auth.openai.com/oauth/revoke"}"#, remaining: [], contentType: "application/json"), path: "/.well-known/openid-configuration")
            ChatHTTPFixture.register(.init(first: "", remaining: [], contentType: "application/json"), path: "/oauth/revoke")
            try await connection.signOut(owner: UUID())
            XCTAssertEqual(connection.state?.configured, false); XCTAssertEqual(connection.state?.revocationUnconfirmed, false)
            var current = try self.saved(query), signedOut = try XCTUnwrap(current["accounts"] as? [[String: Any]])
            XCTAssertNil(signedOut.first?["credentials"]); XCTAssertEqual(signedOut.first?["registration"] as? [String: String], registration)
            let revoke = try XCTUnwrap(ChatHTTPFixture.captured("/oauth/revoke")); XCTAssertTrue(String(decoding: try self.body(revoke), as: UTF8.self).contains("synthetic-rotated"))
            current = self.state(registration: registration, expired: true)
            XCTAssertEqual(SecItemUpdate(query as CFDictionary, [kSecValueData as String: try JSONSerialization.data(withJSONObject: current)] as CFDictionary), errSecSuccess)
            ChatHTTPFixture.register(.init(first: #"{"error":"invalid_grant"}"#, remaining: [], status: 400, contentType: "application/json"), path: self.tokenPath)
            do { try await connection.refreshModels(owner: UUID()); XCTFail("An expired grant must require reconnecting") } catch { XCTAssertTrue(error.localizedDescription.contains("expired")) }
            let expired = try self.saved(query), remaining = try XCTUnwrap(expired["accounts"] as? [[String: Any]])
            XCTAssertNil(remaining.first?["credentials"]); XCTAssertEqual(remaining.first?["registration"] as? [String: String], registration)
            XCTAssertEqual(connection.state?.configured, false)
        }
    }
    func testAgentToolOnlyReplyAndResultContinuationUseTheFrozenRun() async throws {
        try await fixture { root, connection, query, _ in
            let original = "---\nzerus-id: alpha\n---\n# Alpha\n\nScoped evidence.\n"
            let file = root.appendingPathComponent("Alpha.md"); try Data(original.utf8).write(to: file)
            let io = VaultFiles(root: root), attachments = NativeChatAttachmentStore(directory: root.appendingPathComponent("PrivateAttachments"))
            var record = try await io.agentStart(objective: "Read Alpha", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "agent-fixture", owner: "owner")
            let prepared = try await MacAgentRequest.prepare(record.run, store: attachments)
            record = try await io.agentReserveRequest(record, owner: "owner", input: prepared.estimatedInput, output: prepared.outputLimit)
            let selected = try await connection.selection()
            func completed(_ output: [[String: Any]], input: Int, outputTokens: Int) throws -> String {
                let object: [String: Any] = ["type": "response.completed", "response": ["status": "completed", "output": output, "usage": ["input_tokens": input, "output_tokens": outputTokens]]]
                return "data: " + String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n\n"
            }
            let call: [String: Any] = ["type": "function_call", "id": "fc-fixture", "namespace": "zerus", "call_id": "read-alpha", "name": "note_get", "arguments": "{\"selector\":\"alpha\"}"]
            let reasoning: [String: Any] = ["type": "reasoning", "id": "rs-fixture", "encrypted_content": "synthetic-encrypted-reasoning", "summary": []]
            ChatHTTPFixture.register(.init(first: try completed([reasoning, call], input: 205, outputTokens: 5), remaining: []), path: self.responsePath)
            let reply = try await connection.streamAgent(selection: selected, request: prepared) { _ in XCTFail("A tool-only response has no text delta") }
            XCTAssertEqual(reply.content, ""); XCTAssertEqual(reply.calls.map(\.id), ["read-alpha"])
            XCTAssertEqual(reply.inputTokens, 205); XCTAssertEqual(reply.outputTokens, 5); XCTAssertEqual(connection.activeRequests, 0)
            let firstBody = try MacConversations.object(self.body(XCTUnwrap(ChatHTTPFixture.captured(self.responsePath))))
            let namespaces = try XCTUnwrap(firstBody["tools"] as? [[String: Any]])
            let functions = try XCTUnwrap(namespaces.first?["tools"] as? [[String: Any]])
            XCTAssertTrue(functions.contains { $0["name"] as? String == "note_get" })
            XCTAssertFalse(functions.contains { $0["name"] as? String == "note_append" }, "Ask must not advertise writing tools")
            record = try await io.agentResponse(record, owner: "owner", content: reply.content, calls: reply.calls, input: XCTUnwrap(reply.inputTokens), output: XCTUnwrap(reply.outputTokens), seconds: 0)
            record = try await io.agentTool(record, owner: "owner", call: XCTUnwrap(reply.calls.first))
            let next = try await MacAgentRequest.prepare(record.run, store: attachments)
            let answer: [String: Any] = ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "Alpha contains scoped evidence."]]]
            ChatHTTPFixture.register(.init(first: try completed([answer], input: 250, outputTokens: 8), remaining: []), path: self.responsePath)
            let final = try await connection.streamAgent(selection: selected, request: next) { _ in }
            let secondBody = try MacConversations.object(self.body(XCTUnwrap(ChatHTTPFixture.captured(self.responsePath))))
            let input = try XCTUnwrap(secondBody["input"] as? [[String: Any]])
            XCTAssertTrue(input.contains { $0["encrypted_content"] as? String == "synthetic-encrypted-reasoning" })
            XCTAssertTrue(input.contains { $0["type"] as? String == "function_call" && $0["call_id"] as? String == "read-alpha" })
            XCTAssertTrue(input.contains { $0["type"] as? String == "function_call_output" && $0["call_id"] as? String == "read-alpha" && ($0["output"] as? String)?.contains("Scoped evidence.") == true })
            record = try await io.agentResponse(record, owner: "owner", content: final.content, calls: final.calls, input: XCTUnwrap(final.inputTokens), output: XCTUnwrap(final.outputTokens), seconds: 0)
            XCTAssertEqual(record.run.status, "complete"); XCTAssertEqual(record.run.inputTokens, 455)
            XCTAssertEqual(try Data(contentsOf: file), Data(original.utf8)); XCTAssertTrue(record.run.receipts.isEmpty)
            let credentials = String(decoding: try JSONSerialization.data(withJSONObject: self.saved(query)), as: UTF8.self)
            XCTAssertFalse(credentials.contains("Scoped evidence.")); XCTAssertFalse(credentials.contains("read-alpha"))
            XCTAssertFalse(String(decoding: record.bytes, as: UTF8.self).contains("synthetic-access"))
            ChatHTTPFixture.remove(self.responsePath)
            var reserved = record.run
            reserved.requestReservation = .init(id: UUID(), input: 1, output: 1)
            do { _ = try await MacAgentRequest.prepare(reserved, store: attachments); XCTFail("An unfinished reservation cannot be sent again") }
            catch { XCTAssertTrue(error.localizedDescription.contains("earlier request")) }
            XCTAssertNil(ChatHTTPFixture.captured(self.responsePath))
            try await connection.selectModel("fixture-other", owner: UUID())
            do { _ = try await connection.streamAgent(selection: selected, request: next) { _ in }; XCTFail("A saved run cannot silently switch its selected model") }
            catch { XCTAssertTrue(error.localizedDescription.contains("changed")) }
            XCTAssertEqual(connection.activeRequests, 0); XCTAssertNil(ChatHTTPFixture.captured(self.responsePath))
        }
    }
    func testOversizedAgentReplyDoesNotCancelItsCaller() async throws {
        try await fixture { root, connection, _, _ in
            let io = VaultFiles(root: root)
            let record = try await io.agentStart(objective: "Answer", mode: .ask, scope: .init(), chatID: "oversize-fixture", owner: "owner")
            let request = try await MacAgentRequest.prepare(record.run, store: .init(directory: root.appendingPathComponent("PrivateAttachments")))
            let event: [String: Any] = ["type": "response.output_text.delta", "delta": String(repeating: "x", count: 400_001)]
            let wire = "data: " + String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self) + "\n\n"
            ChatHTTPFixture.register(.init(first: wire, remaining: [self.finish]), path: self.responsePath)
            let selected = try await connection.selection()
            let task = Task { () -> Bool in
                do { _ = try await connection.streamAgent(selection: selected, request: request) { _ in }; XCTFail("An oversized reply must fail") }
                catch { XCTAssertTrue(error.localizedDescription.contains("size limit"), error.localizedDescription) }
                return Task.isCancelled
            }
            let cancelled = await task.value
            XCTAssertFalse(cancelled, "Provider limits must leave the caller able to save its failure journal")
            XCTAssertEqual(connection.activeRequests, 0)
        }
    }
    func testAgentCapacityDiscoveryStopsBeforeSendingAndRechecksTheRestoredModel() async throws {
        for retired in [false, true] {
            try await fixture(model: retired ? "retired-model" : "fixture-chatgpt") { root, connection, _, _ in
                ChatHTTPFixture.register(.init(first: self.catalog.replacingOccurrences(of: "32768", with: "8192"), remaining: [], contentType: "application/json"), path: self.modelPath)
                let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
                defer {
                    if let recent { defaults.set(recent, forKey: "zerus.mac.recentVaults") } else { defaults.removeObject(forKey: "zerus.mac.recentVaults") }
                    defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
                }
                let workspace = MacWorkspace(); await workspace.openVault(root)
                let controller = try MacAgentController(workspace: workspace, owner: "account-fixture")
                let selected = try await connection.selection(), provider = MacAgentProvider.chatGPT(connection: connection, selection: selected)
                let stopped = expectation(description: "account capacity refused"), observer = controller.$running.dropFirst().filter { !$0 }.prefix(1).sink { _ in stopped.fulfill() }
                XCTAssertTrue(controller.start(prompt: "Answer", mode: .ask, scope: .init(), chatID: "capacity-fixture", store: .init(directory: root.appendingPathComponent("PrivateAttachments")), provider: provider))
                await fulfillment(of: [stopped], timeout: 5); withExtendedLifetime(observer) {}
                XCTAssertTrue(controller.issue?.contains(retired ? "changed after discovery" : "model's context capacity") == true, controller.issue ?? "missing issue")
                XCTAssertNotNil(ChatHTTPFixture.captured(self.modelPath)); XCTAssertNil(ChatHTTPFixture.captured(self.responsePath))
                XCTAssertEqual(connection.activeRequests, 0)
                let record = try XCTUnwrap(controller.current)
                XCTAssertEqual(record.run.steps, 0); XCTAssertNil(record.run.requestReservation)
                XCTAssertEqual(record.run.inputTokens, 0); XCTAssertEqual(record.run.outputTokens, 0)
                _ = await workspace.prepareToCloseWindow()
                if let directory = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            }
        }
    }
    private func fixture(expired: Bool = false, model: String = "fixture-chatgpt", operation: (URL, MacChatGPTConnection, [String: Any], [String: String]) async throws -> Void) async throws {
        let nonce = UUID().uuidString.lowercased(), root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-account-chat-" + nonce)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let registration = ["clientID": "oaiapp_fixture_" + nonce, "subject": "fixture-subject-" + nonce, "email": "fixture@example.invalid"]
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.zerus.notes.account-test." + nonce, kSecAttrAccount as String: "accounts-v1", kSecAttrSynchronizable as String: false]
        var item = query; item[kSecValueData as String] = try JSONSerialization.data(withJSONObject: state(registration: registration, expired: expired, model: model))
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw VaultFailure(message: "The isolated account fixture could not use Keychain.") }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ChatHTTPFixture.self]
        let session = URLSession(configuration: configuration), manager = ChatGPTManager(service: query[kSecAttrService as String] as! String, session: session), connection = MacChatGPTConnection(manager: manager)
        ChatHTTPFixture.register(.init(first: catalog, remaining: [], contentType: "application/json"), path: modelPath)
        defer {
            session.invalidateAndCancel(); SecItemDelete(query as CFDictionary)
            for path in [modelPath, responsePath, tokenPath, "/.well-known/openid-configuration", "/oauth/revoke"] { ChatHTTPFixture.remove(path) }
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0], key = NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.absoluteString)
            for folder in ["Images", "Documents"] { try? FileManager.default.removeItem(at: base.appendingPathComponent("Zerus Native/Drafts/Chat/" + folder + "/" + key)) }
            try? FileManager.default.removeItem(at: base.appendingPathComponent("Zerus Native/Drafts/Chat/" + key + ".json"))
            try? ChatGPTContinuationStore.removeAccount(root: base.appendingPathComponent("ZerusChatGPTContinuations"), account: registration["clientID"]! + "\u{0}" + registration["subject"]!)
            try? FileManager.default.removeItem(at: root)
        }
        try await operation(root, connection, query, registration)
    }
    private func state(registration: [String: String], expired: Bool, model: String = "fixture-chatgpt") -> [String: Any] {
        ["hostID": "urn:uuid:" + registration["subject"]!, "activeClientID": registration["clientID"]!, "accounts": [["registration": registration, "label": "Synthetic account", "model": model, "credentials": ["registration": registration, "accessToken": "synthetic-access", "refreshToken": "synthetic-refresh", "idToken": "synthetic-id-token", "scopes": ["resource.invoke", "chatgpt.tokens.use.direct"], "expiresAt": Date().addingTimeInterval(expired ? -3600 : 3600).timeIntervalSinceReferenceDate]]]]
    }
    private func saved(_ query: [String: Any]) throws -> [String: Any] {
        var attributes = query; attributes[kSecReturnData as String] = true; attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; XCTAssertEqual(SecItemCopyMatching(attributes as CFDictionary, &result), errSecSuccess)
        return try MacConversations.object(XCTUnwrap(result as? Data))
    }
    private func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
        return data
    }
}
