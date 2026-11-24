import Foundation
import Security
import AuthenticationServices
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import ZerusChatGPTCore

public struct ChatGPTAccountSummary: Encodable {
  public let id: String
  public let label: String
  public let connected: Bool
  public let active: Bool
}

public struct ChatGPTCommand: Decodable {
  public let operation: String
  public let accountID: String?

  public init(operation: String, accountID: String?) {
    self.operation = operation; self.accountID = accountID
  }
}

private struct ChatGPTSavedAccount: Codable, Sendable {
  let registration: ChatGPTRegistration
  let label: String
  var credentials: ChatGPTCredentials?
  var model: String
}

private struct ChatGPTAccountStore: Codable, Sendable {
  let hostID: String
  var activeClientID: String?
  var accounts: [ChatGPTSavedAccount]
  var pending: ChatGPTRegistration?
}

/// Account credentials and stateless reasoning never leave the native bridge.
@MainActor
final class ChatGPTManager: NSObject, ASWebAuthenticationPresentationContextProviding {
  static let endpoint = CloudAIEndpoint.chatGPT
  private let service: String
  private let http: URLSession
  init(service: String = "com.zerus.notes.chatgpt", session: URLSession = .shared) {
    self.service = service; self.http = session; super.init()
  }
  private var browser: ASWebAuthenticationSession?
  private var listener: ChatGPTLoopback?
  private var finishSignIn: ((Result<URL, Error>) -> Void)?
  private var signingIn = false
  private var refreshTasks: [String: Task<ChatGPTCredentials, Error>] = [:]
  private var catalogs: [String: [CloudAIModelResponse]] = [:]
  private var revocationUnconfirmed = false
  private var cachedStore: ChatGPTAccountStore?

  func status() -> CloudAIStatusResponse {
#if os(macOS)
    let state = cachedStore
#else
    let state = try? store()
#endif
    let active = state?.accounts.first { $0.registration.clientID == state?.activeClientID }
    return CloudAIStatusResponse(endpoint: Self.endpoint, model: active?.model ?? "", configured: active?.credentials != nil,
      account: active?.label, accounts: state?.accounts.map { account in
        ChatGPTAccountSummary(id: account.registration.clientID, label: account.label,
          connected: account.credentials != nil, active: account.registration.clientID == state?.activeClientID)
      } ?? [], revocationUnconfirmed: revocationUnconfirmed)
  }
  func restoreStatus(allowInteraction: Bool = false) async throws -> CloudAIStatusResponse {
#if os(macOS)
    do {
      let data = try await AppleKeychainIO.read(service: service, account: "accounts-v1", allowInteraction: allowInteraction)
      cachedStore = try data.map { try JSONDecoder().decode(ChatGPTAccountStore.self, from: $0) }
    } catch is CancellationError { throw CancellationError() }
    catch { cachedStore = nil; throw error }
#endif
    return status()
  }
  func configureModel(_ model: String) async throws {
    var state = try await asynchronousStore()
    guard let index = state.accounts.firstIndex(where: { $0.registration.clientID == state.activeClientID }) else { throw ChatGPTError.message("Continue with ChatGPT before choosing a model.") }
    if let catalog = catalogs[state.accounts[index].registration.clientID], !catalog.contains(where: { $0.id == model }) { throw ChatGPTError.message("Choose a model available to this ChatGPT account.") }
    state.accounts[index].model = model
    try await asynchronousPersist(state)
  }

  func configure(model: String) throws {
    var state = try store()
    guard let index = state.accounts.firstIndex(where: { $0.registration.clientID == state.activeClientID }) else {
      guard model.isEmpty else { throw ChatGPTError.message("Continue with ChatGPT before choosing a model.") }
      return
    }
    if let catalog = catalogs[state.accounts[index].registration.clientID], !catalog.contains(where: { $0.id == model }) {
      throw ChatGPTError.message("Choose a model available to this ChatGPT account.")
    }
    state.accounts[index].model = model
    try persist(state)
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
#if os(macOS)
    NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) ?? ASPresentationAnchor()
#else
    UIApplication.shared.connectedScenes.filter { $0.activationState == .foregroundActive }.compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
#endif
  }

  func cancelSignIn() { finishSignIn?(.failure(CancellationError())); listener?.stop() }

  func signIn(accountID: String? = nil, addAccount: Bool = false) async throws {
    guard !signingIn else { throw ChatGPTError.message("ChatGPT sign-in is already in progress.") }
    signingIn = true
    defer { signingIn = false }
    var state = try await asynchronousStore()
    let existing = addAccount ? nil : state.accounts.first { $0.registration.clientID == (accountID ?? state.activeClientID) }
    if accountID != nil && existing == nil { throw ChatGPTError.message("The selected ChatGPT account is no longer saved.") }
    let registration = existing?.registration ?? (addAccount ? nil : state.pending)
    try Task.checkCancellation()
    let loopback = ChatGPTLoopback()
    listener = loopback
    defer { loopback.stop(); listener = nil }
    let redirect = try await loopback.start()
    try Task.checkCancellation()
    let transaction = try ChatGPTAuthorization(redirectURI: redirect, registration: registration)
    let callback: URL = try await withCheckedThrowingContinuation { continuation in
      var completed = false
      var timeout: Task<Void, Never>?
      let finish: (Result<URL, Error>) -> Void = { [weak self] result in
        guard !completed else { return }
        completed = true; timeout?.cancel()
        self?.finishSignIn = nil
        loopback.onCallback = nil; loopback.onFailure = nil
        self?.browser?.cancel(); self?.browser = nil
        continuation.resume(with: result)
      }
      finishSignIn = finish
      loopback.onFailure = { finish(.failure($0)) }
      loopback.onCallback = { callback in
        guard URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "state" })?.value == transaction.state else { return false }
        do { _ = try transaction.callback(callback); finish(.success(callback)); return true }
        catch { finish(.failure(error)); return false }
      }
      let session = ASWebAuthenticationSession(url: transaction.authorizeURL(hostID: state.hostID, idTokenHint: existing?.credentials?.idToken), callbackURLScheme: nil) { _, _ in
        Task { @MainActor in finish(.failure(CancellationError())) }
      }
      session.presentationContextProvider = self
      browser = session
      if !session.start() { finish(.failure(ChatGPTError.message("The sign-in browser could not start."))) }
      timeout = Task { @MainActor in
        do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
        finish(.failure(ChatGPTError.message("ChatGPT sign-in timed out. Please try again.")))
      }
    }
    let result = try transaction.callback(callback)
    try Task.checkCancellation()
    state = try await asynchronousStore()
    state.pending = registration ?? ChatGPTRegistration(clientID: result.clientID, subject: "", email: "")
    try await asynchronousPersist(state)
    let token = try await form("https://auth.openai.com/api/accounts/oauth/token", ["grant_type": "authorization_code", "client_id": result.clientID,
      "code": result.code, "code_verifier": transaction.verifier, "redirect_uri": redirect.absoluteString, "resource": "https://api.openai.com/v1"])
    guard let idToken = token["id_token"] as? String else { throw ChatGPTError.message("ChatGPT did not return a verifiable account.") }
    let identity = try ChatGPTIdentity.verify(idToken, jwks: try await jsonGET("https://auth.openai.com/.well-known/jwks.json"), clientID: result.clientID, nonce: transaction.nonce)
    guard registration?.subject.isEmpty != false || registration?.subject == identity.subject else {
      throw ChatGPTError.message("ChatGPT returned a different account. Choose Add another account.")
    }
    let credentials = try session(from: token, identity: identity, retainedIDToken: idToken)
    try Task.checkCancellation()
    state = try await asynchronousStore()
    if let index = state.accounts.firstIndex(where: { $0.registration.clientID == identity.clientID }) {
      guard state.accounts[index].registration.subject == identity.subject else { throw ChatGPTError.message("The ChatGPT account registration did not match.") }
      state.accounts[index].credentials = credentials
    } else {
      state.accounts.append(ChatGPTSavedAccount(registration: identity, label: "\(identity.email) · Account \(state.accounts.count + 1)", credentials: credentials, model: ""))
    }
    state.activeClientID = identity.clientID; state.pending = nil
    try await asynchronousPersist(state)
    revocationUnconfirmed = false
    _ = try await models()
  }

  func selectAccount(_ id: String) async throws {
    let state = try await asynchronousStore()
    guard let account = state.accounts.first(where: { $0.registration.clientID == id }) else { throw ChatGPTError.message("The selected ChatGPT account is no longer saved.") }
    if account.credentials == nil { try await signIn(accountID: id); return }
    _ = try await accessToken(clientID: id)
    var updated = try await asynchronousStore(); updated.activeClientID = id
    try await asynchronousPersist(updated)
    revocationUnconfirmed = false
    _ = try await models()
  }

  func models() async throws -> CloudAIModelsResponse {
    let account = try await activeAccount()
    let request = ChatGPTModelCatalog.request(accessToken: try await accessToken(clientID: account.registration.clientID))
    let (data, response) = try await http.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ChatGPTError.message("The ChatGPT model catalog could not be reached.")
    }
    guard let entries = json["models"] as? [[String: Any]] else { throw ChatGPTError.message("ChatGPT did not return its model catalog.") }
    let available = entries.compactMap { entry -> CloudAIModelResponse? in
      guard entry["visibility"] as? String == "list", let slug = entry["slug"] as? String, !slug.isEmpty else { return nil }
      return CloudAIModelResponse(id: slug, name: entry["display_name"] as? String ?? slug,
        contextWindow: entry["context_window"] as? Int ?? entry["context_length"] as? Int)
    }
    guard !available.isEmpty else { throw ChatGPTError.message("No eligible models are available for this ChatGPT account.") }
    catalogs[account.registration.clientID] = available
    if !available.contains(where: { $0.id == account.model }) { try await configureModel(available[0].id) }
    return CloudAIModelsResponse(models: available)
  }

  func generate(_ request: CloudAIGenerateRequest, onDelta: @escaping (String) -> Void) async throws -> CloudAIGenerateResponse {
    var account = try await activeAccount()
    if catalogs[account.registration.clientID] == nil { _ = try await models(); account = try await activeAccount() }
    guard catalogs[account.registration.clientID]?.contains(where: { $0.id == account.model }) == true else { throw ChatGPTError.message("Choose an available ChatGPT model in Chat model settings.") }
    let agent: [String: Any]
    if let raw = request.agentRequestJSON, let data = raw.data(using: .utf8), let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] { agent = decoded }
    else {
      guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, (request.images ?? []).count <= 4 else { throw ChatGPTError.message("Enter a message with at most four images before asking ChatGPT.") }
      agent = ["systemPrompt": "Answer using the supplied Zerus note context. Keep replies concise.", "messages": [["role": "user", "content": request.prompt,
        "images": (request.images ?? []).map { ["mediaType": $0.mimeType, "data": Data($0.bytes).base64EncodedString()] }]]]
    }
    let continuations = request.agentRequestJSON == nil ? nil : ChatGPTContinuationStore(root: try continuationRoot(), account: continuationAccount(account), model: account.model, conversation: agent["continuationID"] as? String ?? "")
    let body = try ChatGPTResponses.request(model: account.model, agent: agent, continuations: continuations)
    var httpRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
    httpRequest.httpMethod = "POST"; httpRequest.timeoutInterval = 120
    httpRequest.setValue("Bearer \(try await accessToken(clientID: account.registration.clientID))", forHTTPHeaderField: "Authorization")
    httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    httpRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (bytes, response) = try await http.bytes(for: httpRequest)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw ChatGPTError.message("ChatGPT refused this request. Check your selected model, plan permissions and usage in ChatGPT settings.")
    }
    var streamedText = ""
    let completed = try await ChatGPTResponseStream.consume(bytes) { delta in streamedText += delta; onDelta(delta) }
    let result = try ChatGPTResponses.completedResult(completed, streamedText: streamedText, agent: request.agentRequestJSON != nil)
    if let continuations {
      try continuations.save(messages: agent["messages"] as? [[String: Any]] ?? [], response: completed, streamedText: streamedText)
    }
    let data = try JSONSerialization.data(withJSONObject: result)
    return CloudAIGenerateResponse(answer: result["content"] as? String ?? "", agentResponseJSON: request.agentRequestJSON == nil ? nil : String(decoding: data, as: UTF8.self))
  }

  func signOut() async throws {
    let id = try await activeAccount().registration.clientID
    refreshTasks[id]?.cancel()
    if let task = refreshTasks[id] { _ = try? await task.value }
    let current = try await activeAccount()
    revocationUnconfirmed = current.credentials == nil ? false : !(await revoke(current.credentials!))
    var state = try await asynchronousStore()
    if let index = state.accounts.firstIndex(where: { $0.registration.clientID == id }) { state.accounts[index].credentials = nil }
    try await asynchronousPersist(state)
    catalogs.removeValue(forKey: id)
    try ChatGPTContinuationStore.removeAccount(root: continuationRoot(), account: continuationAccount(current))
  }

  private func continuationRoot() throws -> URL {
    try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ZerusChatGPTContinuations", isDirectory: true)
  }
  private func continuationAccount(_ account: ChatGPTSavedAccount) -> String {
    // Neither OAuth tokens nor a readable account identifier enter cache names.
    account.registration.clientID + "\u{0}" + account.registration.subject
  }

  private func revoke(_ credentials: ChatGPTCredentials) async -> Bool {
    do {
      let discovery = try await jsonGET("https://auth.openai.com/.well-known/openid-configuration")
      guard let address = discovery["revocation_endpoint"] as? String, let url = URL(string: address), url.scheme == "https", url.host == "auth.openai.com" else { return false }
      for attempt in 0..<2 {
        do { _ = try await form(address, ["token": credentials.refreshToken, "token_type_hint": "refresh_token", "client_id": credentials.registration.clientID], allowEmpty: true); return true }
        catch { if attempt == 0 { try? await Task.sleep(nanoseconds: 500_000_000) } }
      }
    } catch {}
    return false
  }

  private func accessToken(clientID: String) async throws -> String {
    if let task = refreshTasks[clientID] { return try await task.value.accessToken }
    guard let current = try await asynchronousStore().accounts.first(where: { $0.registration.clientID == clientID })?.credentials else { throw ChatGPTError.message("Continue with ChatGPT in Chat model settings first.") }
    if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
    let task = Task { @MainActor in
      var token = try await self.form("https://auth.openai.com/api/accounts/oauth/token", ["grant_type": "refresh_token", "client_id": current.registration.clientID,
        "refresh_token": current.refreshToken, "resource": "https://api.openai.com/v1"])
      if token["scope"] == nil { token["scope"] = current.scopes.joined(separator: " ") }
      let next = try self.session(from: token, identity: current.registration, retainedIDToken: current.idToken)
      try Task.checkCancellation()
      var state = try await self.asynchronousStore()
      guard let index = state.accounts.firstIndex(where: { $0.registration.clientID == clientID }), state.accounts[index].credentials != nil else { throw CancellationError() }
      state.accounts[index].credentials = next; try await self.asynchronousPersist(state)
      return next
    }
    refreshTasks[clientID] = task
    defer { refreshTasks.removeValue(forKey: clientID) }
    do { return try await task.value.accessToken }
    catch ChatGPTSessionError.expired {
      var state = try await asynchronousStore()
      if let index = state.accounts.firstIndex(where: { $0.registration.clientID == clientID }) { state.accounts[index].credentials = nil; try await asynchronousPersist(state) }
      throw ChatGPTError.message("Your ChatGPT session expired. Reconnect in Chat model settings.")
    }
  }

  private func session(from json: [String: Any], identity: ChatGPTRegistration, retainedIDToken: String) throws -> ChatGPTCredentials {
    guard let access = json["access_token"] as? String, !access.isEmpty, let refresh = json["refresh_token"] as? String, !refresh.isEmpty,
          let expiry = json["expires_in"] as? Double, expiry > 0, (json["token_type"] as? String)?.lowercased() == "bearer",
          let scope = json["scope"] as? String else { throw ChatGPTError.message("ChatGPT returned incomplete credentials. Please reconnect.") }
    let scopes = scope.split(separator: " ").map(String.init)
    guard scopes.contains("chatgpt.tokens.use.direct"), scopes.contains("resource.invoke") else { throw ChatGPTError.message("ChatGPT plan usage was not granted. Enable it when signing in.") }
    return ChatGPTCredentials(registration: identity, accessToken: access, refreshToken: refresh, idToken: retainedIDToken, scopes: scopes, expiresAt: Date().addingTimeInterval(expiry))
  }

  private func activeAccount() async throws -> ChatGPTSavedAccount {
    let state = try await asynchronousStore()
    guard let account = state.accounts.first(where: { $0.registration.clientID == state.activeClientID }) else { throw ChatGPTError.message("Continue with ChatGPT in Chat model settings first.") }
    return account
  }

  private func asynchronousStore() async throws -> ChatGPTAccountStore {
#if os(macOS)
    if let data = try await AppleKeychainIO.read(service: service, account: "accounts-v1", allowInteraction: true) {
      let state = try JSONDecoder().decode(ChatGPTAccountStore.self, from: data); cachedStore = state; return state
    }
    let state = ChatGPTAccountStore(hostID: "urn:uuid:\(UUID().uuidString.lowercased())", activeClientID: nil, accounts: [], pending: nil)
    try await asynchronousPersist(state); return state
#else
    return try store()
#endif
  }
  private func asynchronousPersist(_ state: ChatGPTAccountStore) async throws {
#if os(macOS)
    try await AppleKeychainIO.save(JSONEncoder().encode(state), service: service, account: "accounts-v1")
    cachedStore = state
#else
    try persist(state)
#endif
  }

  private func store() throws -> ChatGPTAccountStore {
    if let data = try read("accounts-v1") { return try JSONDecoder().decode(ChatGPTAccountStore.self, from: data) }
    let state = ChatGPTAccountStore(hostID: "urn:uuid:\(UUID().uuidString.lowercased())", activeClientID: nil, accounts: [], pending: nil)
    try persist(state)
    return state
  }

  private func persist(_ state: ChatGPTAccountStore) throws { try save(JSONEncoder().encode(state), "accounts-v1") }

  private func jsonGET(_ address: String) async throws -> [String: Any] {
    var request = URLRequest(url: URL(string: address)!)
    request.timeoutInterval = 30
    let (data, response) = try await http.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ChatGPTError.message("The ChatGPT account service could not be reached.") }
    return json
  }

  private func form(_ address: String, _ values: [String: String], allowEmpty: Bool = false) async throws -> [String: Any] {
    var request = URLRequest(url: URL(string: address)!)
    request.httpMethod = "POST"; request.timeoutInterval = 30
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    request.httpBody = values.sorted(by: { $0.key < $1.key }).map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").data(using: .utf8)
    let (data, response) = try await http.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      if values["grant_type"] == "refresh_token", let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any], error["error"] as? String == "invalid_grant" { throw ChatGPTSessionError.expired }
      throw ChatGPTError.message("ChatGPT authorization could not be completed or renewed. Please reconnect.")
    }
    if allowEmpty && data.isEmpty { return [:] }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ChatGPTError.message("ChatGPT returned an invalid authorization response.") }
    return json
  }
  private func query(_ key: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false]
  }
  private func read(_ key: String) throws -> Data? {
    var attributes = query(key)
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    let status = SecItemCopyMatching(attributes as CFDictionary, &value)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = value as? Data else { throw ChatGPTError.message("Keychain could not read the ChatGPT connection.") }
    return data
  }
  private func save(_ data: Data, _ key: String) throws {
    let attributes = query(key)
    let update: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    let result = SecItemUpdate(attributes as CFDictionary, update as CFDictionary)
    if result == errSecSuccess { return }
    guard result == errSecItemNotFound else { throw ChatGPTError.message("Keychain could not save the ChatGPT connection.") }
    var insert = attributes
    for (key, value) in update { insert[key] = value }
    guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw ChatGPTError.message("Keychain could not save the ChatGPT connection.") }
  }
}

private enum ChatGPTSessionError: Error { case expired }
