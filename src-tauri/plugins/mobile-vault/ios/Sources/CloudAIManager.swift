import Foundation
import Security

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

struct CloudAIGenerateRequest: Decodable {
  let prompt: String
  let imageBytes: [UInt8]?
  let imageMimeType: String?
}

struct CloudAIGenerateResponse: Encodable {
  let answer: String
}

final class CloudAIManager {
  private let endpointKey = "grimoire.cloudAI.endpoint.v1"
  private let modelKey = "grimoire.cloudAI.model.v1"
  private let keychainService = "com.grimoire.notes.cloud-ai"
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

  func generate(_ request: CloudAIGenerateRequest) async throws -> String {
    let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else { throw CloudAIError.emptyPrompt }
    let endpoint = storedEndpoint()
    guard let apiKey = try readAPIKey(endpoint: endpoint), !apiKey.isEmpty else {
      throw CloudAIError.missingAPIKey
    }

    var content: [[String: Any]] = [["type": "text", "text": prompt]]
    if let imageBytes = request.imageBytes, !imageBytes.isEmpty {
      let mimeType = request.imageMimeType ?? "image/jpeg"
      let dataURL = "data:\(mimeType);base64,\(Data(imageBytes).base64EncodedString())"
      content.append(["type": "image_url", "image_url": ["url": dataURL]])
    }
    let body: [String: Any] = [
      "model": storedModel(),
      "messages": [["role": "user", "content": content]],
      "stream": false,
    ]
    let json = try await performRequest(body: body, apiKey: apiKey, baseEndpoint: endpoint)
    guard let choices = json["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any]
    else { throw CloudAIError.emptyResponse }

    let text: String
    if let value = message["content"] as? String {
      text = value
    } else if let blocks = message["content"] as? [[String: Any]] {
      text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
    } else {
      text = ""
    }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CloudAIError.emptyResponse
    }
    return text
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
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: endpoint,
    ]
    SecItemDelete(query as CFDictionary)
    var insert = query
    insert[kSecValueData as String] = apiKey.data(using: .utf8)
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
      throw CloudAIError.keychainFailure
    }
  }

  private func readAPIKey(endpoint: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: endpoint,
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
    case .requestFailed(let status, let message): "Cloud request failed (\(status)): \(message)"
    }
  }
}
