import Foundation
import Security
import CryptoKit

struct CloudAIStatusResponse: Encodable {
  let endpoint: String
  let model: String
  let configured: Bool
}

struct CloudAIConfigureRequest: Decodable {
  let endpoint: String
  let model: String
  let apiKey: String?
}

struct CloudAIImageRequest: Decodable {
  let bytes: [UInt8]
  let mimeType: String
}

struct CloudAIGenerateRequest: Decodable {
  let prompt: String
  let images: [CloudAIImageRequest]?
  let streamId: String
}

struct CloudAIGenerateResponse: Encodable {
  let answer: String
}

struct CloudAIModelResponse: Encodable {
  let id: String
  let name: String
}

struct CloudAIModelsResponse: Encodable {
  let models: [CloudAIModelResponse]
}

final class CloudAIManager {
  private let endpointKey = "zerus.cloudAI.endpoint.v1"
  private let modelKey = "zerus.cloudAI.model.v1"
  private let keychainService = "com.zerus.notes.cloud-ai"
  private let defaultEndpoint = "https://openrouter.ai/api/v1"
  private let defaultModel = "openai/gpt-5-mini"

  func status() -> CloudAIStatusResponse {
    let endpoint = storedEndpoint()
    let configured = (try? readAPIKey(endpoint: endpoint))?.isEmpty == false
    return CloudAIStatusResponse(
      endpoint: endpoint,
      model: storedModel(),
      configured: configured
    )
  }

  func configure(_ request: CloudAIConfigureRequest) throws -> CloudAIStatusResponse {
    let endpoint = try normalizedEndpoint(request.endpoint)
    let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !model.isEmpty else { throw CloudAIError.emptyModel }

    UserDefaults.standard.set(endpoint, forKey: endpointKey)
    UserDefaults.standard.set(model, forKey: modelKey)
    if let apiKey = request.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
      try saveAPIKey(apiKey, endpoint: endpoint)
    }
    return status()
  }

  func connectOpenRouter(code: String, verifier: String) async throws -> CloudAIStatusResponse {
    var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "code": code,
      "code_verifier": verifier,
      "code_challenge_method": "S256",
    ])
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let key = json["key"] as? String, !key.isEmpty else {
      throw CloudAIError.oauthFailed
    }
    UserDefaults.standard.set(defaultEndpoint, forKey: endpointKey)
    try saveAPIKey(key, endpoint: defaultEndpoint)
    return status()
  }

  func models() async throws -> CloudAIModelsResponse {
    let endpoint = storedEndpoint()
    guard let apiKey = try readAPIKey(endpoint: endpoint), !apiKey.isEmpty,
          let url = URL(string: "\(endpoint)/models") else { throw CloudAIError.missingAPIKey }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let entries = json["data"] as? [[String: Any]] else { throw CloudAIError.invalidResponse }
    let models = entries.compactMap { entry -> CloudAIModelResponse? in
      guard let id = entry["id"] as? String, !id.isEmpty else { return nil }
      return CloudAIModelResponse(id: id, name: (entry["name"] as? String) ?? id)
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return CloudAIModelsResponse(models: models)
  }

  func generate(_ request: CloudAIGenerateRequest, onDelta: @escaping (String) -> Void) async throws -> String {
    let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else { throw CloudAIError.emptyPrompt }
    let endpoint = storedEndpoint()
    guard let apiKey = try readAPIKey(endpoint: endpoint), !apiKey.isEmpty else {
      throw CloudAIError.missingAPIKey
    }

    var content: [[String: Any]] = [["type": "text", "text": prompt]]
    for image in (request.images ?? []).prefix(4) where !image.bytes.isEmpty {
      let dataURL = "data:\(image.mimeType);base64,\(Data(image.bytes).base64EncodedString())"
      content.append(["type": "image_url", "image_url": ["url": dataURL]])
    }
    let body: [String: Any] = [
      "model": storedModel(),
      "messages": [["role": "user", "content": content]],
      "stream": true,
    ]
    let text = try await performStreamingRequest(
      body: body,
      apiKey: apiKey,
      baseEndpoint: endpoint,
      onDelta: onDelta
    )
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CloudAIError.emptyResponse
    }
    return text
  }

  private func performStreamingRequest(
    body: [String: Any],
    apiKey: String,
    baseEndpoint: String,
    onDelta: @escaping (String) -> Void
  ) async throws -> String {
    let base = try normalizedEndpoint(baseEndpoint)
    guard let endpoint = URL(string: "\(base)/chat/completions") else {
      throw CloudAIError.invalidEndpoint
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw CloudAIError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw CloudAIError.requestFailed(
        status: http.statusCode,
        message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      )
    }
    var answer = ""
    for try await line in bytes.lines {
      try Task.checkCancellation()
      guard line.hasPrefix("data:") else { continue }
      let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
      if payload == "[DONE]" { break }
      guard let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let delta = choices.first?["delta"] as? [String: Any],
            let text = delta["content"] as? String,
            !text.isEmpty else { continue }
      answer += text
      onDelta(text)
    }
    return answer
  }

  private func performRequest(
    body: [String: Any],
    apiKey: String,
    baseEndpoint: String
  ) async throws -> [String: Any] {
    let base = try normalizedEndpoint(baseEndpoint)
    guard let endpoint = URL(string: "\(base)/chat/completions") else {
      throw CloudAIError.invalidEndpoint
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw CloudAIError.invalidResponse }
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard (200..<300).contains(http.statusCode) else {
      let errorObject = json["error"] as? [String: Any]
      let message = errorObject?["message"] as? String
        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw CloudAIError.requestFailed(status: http.statusCode, message: message)
    }
    return json
  }

  private func storedEndpoint() -> String {
    (try? normalizedEndpoint(UserDefaults.standard.string(forKey: endpointKey) ?? defaultEndpoint))
      ?? defaultEndpoint
  }

  private func storedModel() -> String {
    let value = UserDefaults.standard.string(forKey: modelKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value?.isEmpty == false ? value! : defaultModel
  }

  private func normalizedEndpoint(_ endpoint: String) throws -> String {
    let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let url = URL(string: trimmed), url.scheme == "https", url.host != nil else {
      throw CloudAIError.invalidEndpoint
    }
    return trimmed
  }

  private func saveAPIKey(_ apiKey: String, endpoint: String) throws {
    let account = credentialAccount(endpoint: endpoint)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: true,
    ]
    SecItemDelete(query as CFDictionary)
    var insert = query
    insert[kSecValueData as String] = apiKey.data(using: .utf8)
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
      throw CloudAIError.keychainFailure
    }
  }

  private func readAPIKey(endpoint: String) throws -> String? {
    if let synchronized = try readAPIKey(account: credentialAccount(endpoint: endpoint), synchronized: true) {
      return synchronized
    }
    // Migrate the device-only v1 entry, whose account was the raw endpoint.
    if let legacy = try readAPIKey(account: endpoint, synchronized: false) {
      try saveAPIKey(legacy, endpoint: endpoint)
      return legacy
    }
    return nil
  }

  private func credentialAccount(endpoint: String) -> String {
    let digest = SHA256.hash(data: Data(endpoint.utf8))
    return "provider-" + digest.map { String(format: "%02x", $0) }.joined()
  }

  private func readAPIKey(account: String, synchronized: Bool) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: synchronized,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw CloudAIError.keychainFailure
    }
    return String(data: data, encoding: .utf8)
  }
}

private enum CloudAIError: LocalizedError {
  case emptyModel
  case emptyPrompt
  case emptyResponse
  case invalidEndpoint
  case invalidResponse
  case keychainFailure
  case missingAPIKey
  case oauthFailed
  case requestFailed(status: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .emptyModel: "Enter a model ID."
    case .emptyPrompt: "Enter a message first."
    case .emptyResponse: "The cloud model returned an empty response."
    case .invalidEndpoint: "Enter a valid HTTPS OpenAI-compatible API endpoint."
    case .invalidResponse: "The cloud endpoint returned an invalid response."
    case .keychainFailure: "The API key could not be saved or read from the iOS Keychain."
    case .missingAPIKey: "Add your cloud API key in Chat settings."
    case .oauthFailed: "OpenRouter sign-in could not be completed."
    case .requestFailed(let status, let message): "Cloud request failed (\(status)): \(message)"
    }
  }
}
