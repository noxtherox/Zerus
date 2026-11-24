import XCTest
import Combine
@testable import Zerus_Native

@MainActor final class MacAIProfilesTests: XCTestCase {
    func testSharedProfilesPreserveOtherClientsUnknownFieldsFavoritesAndPerVaultRouting() async throws {
        try await fixture { root, workspace, client in
            let legacy = MacAIProfile(provider: .compatible, endpoint: "https://legacy.invalid/custom-inference", model: "legacy-model", contextWindow: 65_536)
            let router = MacAIProfile(provider: .openrouter, model: "router-model", favorites: ["router-model"])
            let empty = try await workspace.aiProfiles()
            _ = try await workspace.saveAIProfile(router, snapshot: empty, preserving: legacy)
            let file = root.appendingPathComponent(MacAIProfileSnapshot.path)
            var object = try MacConversations.object(Data(contentsOf: file))
            object["futureRoot"] = ["keep": 7]
            var profiles = object["profiles"] as! [String: Any], raw = profiles["openrouter"] as! [String: Any]
            raw["futureOption"] = true; profiles["openrouter"] = raw
            profiles["codex"] = ["baseUrl": "codex://chatgpt", "model": "device-selection", "favoriteModels": ["favorite"]]; object["profiles"] = profiles
            try JSONSerialization.data(withJSONObject: object).write(to: file)
            let model = MacAIConnectionModel(legacy: legacy, usingChatGPT: false, client: client); await model.load(workspace)
            XCTAssertEqual(model.profile, router)
            model.choose(.anthropic); model.profile.model = "anthropic-model"; model.profile.contextWindow = 128_000; model.toggleFavorite()
            _ = try await model.save(workspace)
            let saved = try MacConversations.object(Data(contentsOf: file)), savedProfiles = try XCTUnwrap(saved["profiles"] as? [String: [String: Any]])
            XCTAssertEqual((saved["futureRoot"] as? [String: Int])?["keep"], 7); XCTAssertEqual(savedProfiles["openrouter"]?["futureOption"] as? Bool, true)
            XCTAssertEqual(savedProfiles["codex"]?["model"] as? String, "device-selection"); XCTAssertEqual(savedProfiles["anthropic"]?["baseUrl"] as? String, "https://api.anthropic.com/v1")
            let reopened = MacAIConnectionModel(legacy: legacy, usingChatGPT: false); await reopened.load(workspace)
            XCTAssertEqual(reopened.profile.provider, .anthropic); XCTAssertEqual(reopened.profile.favorites, ["anthropic-model"])
            var webSettings = saved, webProfiles = savedProfiles, webAnthropic = try XCTUnwrap(savedProfiles["anthropic"])
            webAnthropic.removeValue(forKey: "macContextWindow"); webProfiles["anthropic"] = webAnthropic
            var webLegacy = try XCTUnwrap(webProfiles["compatible"]); webLegacy.removeValue(forKey: "macEndpoint"); webLegacy.removeValue(forKey: "macEndpointBaseUrl"); webProfiles["compatible"] = webLegacy
            webSettings["profiles"] = webProfiles
            try JSONSerialization.data(withJSONObject: webSettings).write(to: file)
            await reopened.load(workspace); XCTAssertEqual(reopened.profile.contextWindow, 128_000, "A standard shared-profile rewrite must not discard this Mac’s model capacity")
            reopened.choose(.compatible); XCTAssertEqual(reopened.profile, legacy, "Arbitrary legacy request endpoints must remain usable")
            reopened.profile.model = "unsaved compatible model"; reopened.choose(.anthropic); reopened.choose(.compatible); XCTAssertEqual(reopened.profile.model, "unsaved compatible model")
            let active = try await workspace.aiProfile(legacy: legacy); XCTAssertEqual(active.provider, .anthropic); XCTAssertEqual(active.contextWindow, 128_000)
            let localChatGPT = MacAIConnectionModel(legacy: legacy, usingChatGPT: true); await localChatGPT.load(workspace)
            XCTAssertTrue(localChatGPT.usingChatGPT); XCTAssertEqual(localChatGPT.profile.provider, legacy.provider)
            try await fixture { secondRoot, second, _ in
                let secondSnapshot = try await second.aiProfiles()
                _ = try await second.saveAIProfile(router, snapshot: secondSnapshot)
                let other = try await second.aiProfile(legacy: legacy); XCTAssertEqual(other.provider, .openrouter)
                let original = try await workspace.aiProfile(legacy: legacy); XCTAssertEqual(original.provider, .anthropic)
                XCTAssertNotEqual(secondRoot, root)
            }
            let stale = try await workspace.aiProfiles(), outside = try Data(contentsOf: file) + Data("\n".utf8); try outside.write(to: file)
            do { _ = try await workspace.saveAIProfile(router, snapshot: stale); XCTFail("An outside profile edit must block the old save") } catch {}
            XCTAssertEqual(try Data(contentsOf: file), outside)
            let fresh = try await workspace.aiProfiles(); await workspace.openVault(root)
            do { _ = try await workspace.saveAIProfile(router, snapshot: fresh); XCTFail("Same-root reopen invalidates the form snapshot") } catch {}
            let unsupported = Data(#"{"version":2,"activeProvider":"future","profiles":{},"keep":true}"#.utf8); try unsupported.write(to: file)
            do { _ = try await workspace.aiProfiles(); XCTFail("Unsupported settings must not be replaced") } catch {}
            XCTAssertEqual(try Data(contentsOf: file), unsupported)
        }
    }
    func testModelDiscoveryPaginatesAnthropicPreservesManualChoiceAndPersistsExplicitSelection() async throws {
        try await fixture { root, workspace, client in
            let route = "/models-" + UUID().uuidString, endpoint = "https://native-models.invalid" + route + "/messages"
            let second = ChatHTTPFixture.Script(first: #"{"data":[{"id":"model-b","display_name":"Model B","max_input_tokens":128000}],"has_more":false}"#, remaining: [], contentType: "application/json")
            ChatHTTPFixture.register(.init(first: #"{"data":[{"id":"model-a","display_name":"Model A","max_input_tokens":64000}],"has_more":true,"last_id":"cursor one"}"#, remaining: [], contentType: "application/json", next: second), path: route + "/models")
            defer { ChatHTTPFixture.remove(route + "/models") }
            let model = MacAIConnectionModel(legacy: .init(provider: .anthropic, endpoint: endpoint, model: "manual-kept"), usingChatGPT: false, client: client); await model.load(workspace); model.key = "synthetic-secret"
            let loaded = expectation(description: "all model pages loaded"), subscription = model.$discovering.drop(while: { !$0 }).dropFirst().filter { !$0 }.prefix(1).sink { _ in loaded.fulfill() }
            model.discover(); await fulfillment(of: [loaded], timeout: 5); withExtendedLifetime(subscription) {}
            XCTAssertEqual(Set(model.models.map(\.id)), ["model-a", "model-b"]); XCTAssertEqual(model.profile.model, "manual-kept")
            let request = try XCTUnwrap(ChatHTTPFixture.captured(route + "/models")); XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "synthetic-secret"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "after_id" }?.value, "cursor one")
            model.select(try XCTUnwrap(model.models.first { $0.id == "model-b" })); model.toggleFavorite(); model.key = ""
            _ = try await model.save(workspace)
            let saved = try String(contentsOf: root.appendingPathComponent(MacAIProfileSnapshot.path), encoding: .utf8); XCTAssertFalse(saved.contains("synthetic-secret"))
            let reopened = MacAIConnectionModel(legacy: .init(provider: .openai, model: "unrelated"), usingChatGPT: false); await reopened.load(workspace)
            XCTAssertEqual(reopened.profile.model, "model-b"); XCTAssertEqual(reopened.profile.contextWindow, 128_000); XCTAssertEqual(reopened.profile.favorites, ["model-b"])
            model.choose(.openrouter); XCTAssertTrue(model.key.isEmpty); XCTAssertTrue(model.models.isEmpty)
        }
    }
    func testModelDiscoveryCancellationAndFailuresKeepManualModelsAndIgnoreOldProviderResults() async throws {
        try await fixture { _, workspace, client in
            let route = "/models-" + UUID().uuidString, endpoint = "https://native-models.invalid" + route + "/chat/completions"
            let model = MacAIConnectionModel(legacy: .init(provider: .compatible, endpoint: endpoint, model: "manual-model"), usingChatGPT: false, client: client); await model.load(workspace)
            defer { ChatHTTPFixture.remove(route + "/models") }
            for change in ["provider", "key"] {
                let began = expectation(description: "model HTTP request began " + change), canceled = expectation(description: "old model HTTP request canceled " + change)
                ChatHTTPFixture.register(.init(first: "{\"data\":[", remaining: ["{\"id\":\"wrong-provider-model\"}]}"], paused: true, contentType: "application/json", onStart: { began.fulfill() }, onStop: { canceled.fulfill() }), path: route + "/models")
                model.key = "synthetic"; model.discover(); await fulfillment(of: [began], timeout: 5)
                if change == "provider" { model.choose(.openrouter) } else { model.key = "different-key" }
                await fulfillment(of: [canceled], timeout: 5)
                XCTAssertTrue(model.models.isEmpty)
                if change == "provider" { XCTAssertEqual(model.profile.provider, .openrouter); XCTAssertTrue(model.key.isEmpty); model.choose(.compatible) }
                else { XCTAssertEqual(model.key, "different-key") }
                XCTAssertEqual(model.profile.model, "manual-model")
            }
            for response in [ChatHTTPFixture.Script(first: #"{"error":"server-secret-must-not-be-shown"}"#, remaining: [], status: 401, contentType: "application/json"), .init(first: #"{"unexpected":[]}"#, remaining: [], contentType: "application/json")] {
                ChatHTTPFixture.register(response, path: route + "/models"); model.key = "synthetic"
                let done = expectation(description: "failed model discovery ended"), subscription = model.$discovering.drop(while: { !$0 }).dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
                model.discover(); await fulfillment(of: [done], timeout: 5); withExtendedLifetime(subscription) {}
                XCTAssertEqual(model.profile.model, "manual-model"); XCTAssertTrue(model.models.isEmpty); XCTAssertNotNil(model.issue); XCTAssertFalse(model.issue?.contains("server-secret") ?? true)
            }
            ChatHTTPFixture.register(.init(first: #"{"data":[{"id":"compatible-model","name":"Compatible Model","context_length":96000}]}"#, remaining: [], contentType: "application/json"), path: route + "/models")
            model.key = "synthetic"
            let loaded = expectation(description: "compatible models loaded"), subscription = model.$discovering.drop(while: { !$0 }).dropFirst().filter { !$0 }.prefix(1).sink { _ in loaded.fulfill() }
            model.discover(); await fulfillment(of: [loaded], timeout: 5); withExtendedLifetime(subscription) {}
            XCTAssertEqual(model.models.first?.contextWindow, 96_000); XCTAssertEqual(model.profile.model, "manual-model")
            XCTAssertEqual(ChatHTTPFixture.captured(route + "/models")?.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic")
            ChatHTTPFixture.register(.init(first: #"{"data":[{"id":"public-model","context_length":96000}]}"#, remaining: [], contentType: "application/json"), path: "/api/v1/models")
            defer { ChatHTTPFixture.remove("/api/v1/models") }
            model.choose(.openrouter)
            let publicDone = expectation(description: "public model catalog loaded"), publicSubscription = model.$discovering.drop(while: { !$0 }).dropFirst().filter { !$0 }.prefix(1).sink { _ in publicDone.fulfill() }
            model.discover(); await fulfillment(of: [publicDone], timeout: 5); withExtendedLifetime(publicSubscription) {}
            XCTAssertEqual(model.models.map(\.id), ["public-model"])
            XCTAssertNil(ChatHTTPFixture.captured("/api/v1/models")?.value(forHTTPHeaderField: "Authorization"))

        }
    }
    private func fixture(_ operation: (URL, MacWorkspace, MacAIClient) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-AI-profiles-" + UUID().uuidString), defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ChatHTTPFixture.self]
        let session = URLSession(configuration: configuration), workspace = MacWorkspace(); await workspace.openVault(root)
        defer { session.invalidateAndCancel(); for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(MacAIProfile.capacityPrefix(root: root)) { defaults.removeObject(forKey: key) }; if let folder = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: folder) }; defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path)); try? FileManager.default.removeItem(at: root) }
        try await operation(root, workspace, MacAIClient(session: session))
    }
}
