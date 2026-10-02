import Foundation
import CryptoKit
import Security

public enum ChatGPTError: LocalizedError {
  case message(String)
  public var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

public struct ChatGPTRegistration: Codable {
  public let clientID: String
  public let subject: String
  public let email: String
  public init(clientID: String, subject: String, email: String) { self.clientID = clientID; self.subject = subject; self.email = email }
}

public struct ChatGPTCredentials: Codable {
  public let registration: ChatGPTRegistration
  public let accessToken: String
  public let refreshToken: String
  public let idToken: String
  public let scopes: [String]
  public let expiresAt: Date
  public init(registration: ChatGPTRegistration, accessToken: String, refreshToken: String, idToken: String, scopes: [String], expiresAt: Date) { self.registration = registration; self.accessToken = accessToken; self.refreshToken = refreshToken; self.idToken = idToken; self.scopes = scopes; self.expiresAt = expiresAt }
}

public struct ChatGPTAuthorization {
  public let state: String
  public let nonce: String
  public let verifier: String
  public let redirectURI: URL
  public let registration: ChatGPTRegistration?

  public init(redirectURI: URL, registration: ChatGPTRegistration?) throws {
    self.redirectURI = redirectURI
    self.registration = registration
    state = try Self.randomValue()
    nonce = try Self.randomValue()
    verifier = try Self.randomValue()
  }

  static func randomValue() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw ChatGPTError.message("Could not prepare secure sign-in.")
    }
    return Data(bytes).base64URL
  }

  public func authorizeURL(hostID: String, idTokenHint: String?) -> URL {
    var parts = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
    parts.queryItems = [
      .init(name: "client_id", value: registration?.clientID ?? "dynamic_agent_client"),
      .init(name: "ext_agent_host_id", value: hostID),
      .init(name: "response_type", value: "code"),
      .init(name: "redirect_uri", value: redirectURI.absoluteString),
      .init(name: "scope", value: "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),
      .init(name: "resource", value: "https://api.openai.com/v1"),
      .init(name: "state", value: state),
      .init(name: "nonce", value: nonce),
      .init(name: "code_challenge_method", value: "S256"),
      .init(name: "code_challenge", value: Data(SHA256.hash(data: Data(verifier.utf8))).base64URL),
    ]
    if registration == nil { parts.queryItems!.append(.init(name: "agent_name_hint", value: "Zerus")) }
    else if let hint = idTokenHint { parts.queryItems!.append(.init(name: "id_token_hint", value: hint)) }
    return parts.url!
  }

  /// Validate the complete callback before any code is exchanged or identity is replaced.
  public func callback(_ url: URL) throws -> (code: String, clientID: String) {
    guard url.scheme == redirectURI.scheme, url.host == redirectURI.host,
          url.port == redirectURI.port, url.path == redirectURI.path,
          url.user == nil, url.password == nil, url.fragment == nil,
          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
      throw ChatGPTError.message("The sign-in callback address did not match.")
    }
    var values: [String: String] = [:]
    for item in items {
      guard values[item.name] == nil, let value = item.value else {
        throw ChatGPTError.message("The sign-in callback was ambiguous.")
      }
      values[item.name] = value
    }
    guard values["state"] == state else { throw ChatGPTError.message("The sign-in callback could not be verified.") }
    if values["error"] != nil { throw ChatGPTError.message("ChatGPT sign-in was declined or could not be completed.") }
    guard let code = values["code"], !code.isEmpty, code.count < 16_384 else {
      throw ChatGPTError.message("ChatGPT did not return a sign-in code.")
    }
    let client = values["client_id"] ?? registration?.clientID
    guard let client, client.hasPrefix("oaiapp_"), client.count < 256,
          registration == nil || client == registration?.clientID else {
      throw ChatGPTError.message("ChatGPT did not return the expected client registration.")
    }
    return (code, client)
  }
}

public extension Data {
  var base64URL: String {
    base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
  init?(base64URL: String) {
    let raw = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    self.init(base64Encoded: raw + String(repeating: "=", count: (4 - raw.count % 4) % 4))
  }
}

public enum ChatGPTIdentity {
  public static func verify(_ token: String, jwks: [String: Any], clientID: String, nonce: String, now: Date = Date()) throws -> ChatGPTRegistration {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 3, let headerData = Data(base64URL: parts[0]), let claimsData = Data(base64URL: parts[1]),
          let signature = Data(base64URL: parts[2]),
          let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
          let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
          let algorithm = header["alg"] as? String, let kid = header["kid"] as? String,
          let keys = jwks["keys"] as? [[String: Any]] else { throw invalid() }
    let matches = keys.filter { $0["kid"] as? String == kid }
    guard matches.count == 1 else { throw invalid() }
    let key = matches[0]
    guard key["use"] == nil || key["use"] as? String == "sig",
          key["alg"] == nil || key["alg"] as? String == algorithm else { throw invalid() }
    let signed = Data("\(parts[0]).\(parts[1])".utf8)
    let verified: Bool
    if algorithm == "RS256", key["kty"] as? String == "RSA",
       let n = key["n"] as? String, let modulus = Data(base64URL: n), modulus.count >= 256,
       let e = key["e"] as? String, let exponent = Data(base64URL: e) {
      let der = asn1(0x30, integer(modulus) + integer(exponent))
      guard let rsa = SecKeyCreateWithData(der as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil) else { throw invalid() }
      verified = SecKeyVerifySignature(rsa, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, signature as CFData, nil)
    } else if algorithm == "ES256", key["kty"] as? String == "EC", key["crv"] as? String == "P-256",
              let x = key["x"] as? String, let xd = Data(base64URL: x), xd.count == 32,
              let y = key["y"] as? String, let yd = Data(base64URL: y), yd.count == 32 {
      let publicKey = try P256.Signing.PublicKey(x963Representation: Data([4]) + xd + yd)
      verified = publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: signature), for: signed)
    } else { throw invalid() }
    guard verified else { throw invalid() }
    let audiences = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
    guard claims["iss"] as? String == "https://auth.openai.com", audiences.contains(clientID),
          audiences.count == 1 || claims["azp"] as? String == clientID,
          claims["azp"] == nil || claims["azp"] as? String == clientID,
          let expiry = claims["exp"] as? Double, expiry > now.timeIntervalSince1970,
          let issued = claims["iat"] as? Double, issued <= now.timeIntervalSince1970 + 60,
          claims["nonce"] as? String == nonce,
          let subject = claims["sub"] as? String, !subject.isEmpty else { throw invalid() }
    if let nbf = claims["nbf"] as? Double, nbf > now.timeIntervalSince1970 { throw invalid() }
    return ChatGPTRegistration(clientID: clientID, subject: subject, email: claims["email"] as? String ?? "ChatGPT account")
  }

  private static func invalid() -> ChatGPTError { .message("ChatGPT's account identity could not be verified. Please sign in again.") }
  private static func integer(_ data: Data) -> Data { asn1(0x02, (data.first.map { $0 & 0x80 != 0 } == true ? Data([0]) : Data()) + data) }
  private static func asn1(_ tag: UInt8, _ data: Data) -> Data {
    var size = data.count
    var length = [UInt8]()
    repeat { length.insert(UInt8(size & 255), at: 0); size >>= 8 } while size > 0
    return Data([tag]) + (data.count < 128 ? Data([UInt8(data.count)]) : Data([0x80 | UInt8(length.count)]) + Data(length)) + data
  }
}

/// A stream is successful only after the API's terminal completion event.
public struct ChatGPTResponseStream {
  private(set) var text = ""
  private(set) var response: [String: Any]?
  private var dataLines: [String] = []
  private var size = 0
  private var lineBytes = Data()
  private var outputItems: [Int: [String: Any]] = [:]
  @MainActor
  public static func consume<Bytes: AsyncSequence>(_ bytes: Bytes, onDelta: (String) -> Void) async throws -> [String: Any] where Bytes.Element == UInt8 {
    var stream = ChatGPTResponseStream()
    // Foundation's AsyncLineSequence drops blank lines, which carry SSE event boundaries.
    for try await byte in bytes {
      try Task.checkCancellation()
      if let delta = try stream.byte(byte) { onDelta(delta) }
    }
    if let delta = try stream.byte(10) { onDelta(delta) }
    return try stream.finish()
  }

  mutating func byte(_ byte: UInt8) throws -> String? {
    if byte != 10 {
      guard lineBytes.count < 2_000_000 else { throw ChatGPTError.message("The response line was too large.") }
      lineBytes.append(byte)
      return nil
    }
    if lineBytes.last == 13 { lineBytes.removeLast() }
    guard let decoded = String(data: lineBytes, encoding: .utf8) else { throw ChatGPTError.message("ChatGPT returned an invalid text stream.") }
    lineBytes.removeAll(keepingCapacity: true)
    return try line(decoded)
  }

  mutating func line(_ line: String) throws -> String? {
    if line.isEmpty {
      guard !dataLines.isEmpty else { return nil }
      let payload = dataLines.joined(separator: "\n")
      dataLines.removeAll(); size = 0
      guard payload != "[DONE]" else { return nil }
      guard let data = payload.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data), let event = object as? [String: Any], let type = event["type"] as? String else {
        throw ChatGPTError.message("ChatGPT returned an invalid response stream.")
      }
      switch type {
      case "response.output_text.delta":
        let delta = event["delta"] as? String ?? ""
        text += delta
        return delta
      case "response.output_item.done":
        guard let index = event["output_index"] as? Int, (0..<1024).contains(index),
              let item = event["item"] as? [String: Any] else { throw ChatGPTError.message("ChatGPT returned an invalid completed output item.") }
        outputItems[index] = item
      case "response.completed":
        guard var completed = event["response"] as? [String: Any], completed["status"] as? String == "completed" else { throw ChatGPTError.message("ChatGPT did not complete the response.") }
        let terminalOutputCount = (completed["output"] as? [[String: Any]])?.count ?? 0
        // Some streaming responses carry output in item.done events only.
        // Keep the authoritative terminal array when supplied; never duplicate it.
        if terminalOutputCount == 0 {
          completed["output"] = outputItems.keys.sorted().compactMap { outputItems[$0] }
        }
        response = completed
      case "response.failed", "response.incomplete", "error":
        let failure = (event["response"] as? [String: Any])?["error"] as? [String: Any] ?? event["error"] as? [String: Any] ?? event
        let code = failure["code"] as? String ?? ""
        if code == "subscription_sharing_usage_limit_exceeded" || code == "subscription_sharing_usage_unavailable" {
          throw ChatGPTError.message("ChatGPT plan usage is unavailable or has reached its limit. Check ChatGPT Settings → Usage.")
        }
        throw ChatGPTError.message("ChatGPT stopped before completing the response.")
      default: break
      }
    } else if line.hasPrefix("data:") {
      let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
      size += data.utf8.count
      guard size <= 2_000_000 else { throw ChatGPTError.message("The response event was too large.") }
      dataLines.append(data)
    }
    return nil
  }

  mutating func finish() throws -> [String: Any] {
    _ = try line("")
    guard let response else { throw ChatGPTError.message("The connection ended before ChatGPT completed its response.") }
    return response
  }
}
