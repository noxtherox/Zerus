import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct GoogleDriveCommand: Decodable {
  let operation: String
  let accountId: String?
  let path: String?
  let method: String?
  let query: [String: String]?
  let body: String?
  let contentType: String?
  let ifMatch: String?
}

private struct DriveCredentials: Codable {
  var accessToken: String
  var refreshToken: String
  var expiresAt: Date
  var accountId: String
  var email: String
  var clientId: String
}

private struct DriveFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// Google credentials never cross the Tauri bridge or leave the device except to Google.
@MainActor
final class GoogleDriveManager {
  private let scope = "https://www.googleapis.com/auth/drive"
  private let service = "com.zerus.notes.google-drive"
  private var session: ASWebAuthenticationSession?
  private var refreshTask: Task<String, Error>?
  private let http: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 45
    configuration.timeoutIntervalForResource = 120
    configuration.urlCache = nil
    return URLSession(configuration: configuration)
  }()

  private var clientId: String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "ZerusGoogleDriveClientID") as? String,
          value.range(of: #"^[0-9]+-[a-zA-Z0-9_-]+\.apps\.googleusercontent\.com$"#, options: .regularExpression) != nil else { return nil }
    return value
  }

  func run(_ command: GoogleDriveCommand, presenter: ASWebAuthenticationPresentationContextProviding) async throws -> [String: Any] {
    switch command.operation {
    case "status": return try status()
    case "connect":
      if let saved = try credentials(), saved.clientId == clientId {
        _ = try await token()
        return try status()
      }
      try await connect(presenter: presenter)
      return try status()
    case "reconnect":
      let expected = try credentials()?.accountId
      try await connect(presenter: presenter, expectedAccountId: expected)
      return try status()
    case "disconnect":
      refreshTask?.cancel()
      refreshTask = nil
      let result = SecItemDelete(keychainQuery() as CFDictionary)
      guard result == errSecSuccess || result == errSecItemNotFound else { throw DriveFailure(message: "Could not disconnect Google Drive from this device.") }
      return try status()
    case "request": return try await request(command)
    default: throw DriveFailure(message: "Unknown Google Drive operation.")
    }
  }

  private func status() throws -> [String: Any] {
    let saved = try credentials()
    var result: [String: Any] = ["configured": clientId != nil, "account": NSNull()]
    if let saved { result["account"] = ["accountId": saved.accountId, "email": saved.email] }
    return result
  }

  private func keychainQuery() -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "oauth"]
  }
  private func credentials() throws -> DriveCredentials? {
    var query = keychainQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else { throw DriveFailure(message: "Unlock your iPhone to access Google Drive credentials.") }
    return try JSONDecoder().decode(DriveCredentials.self, from: data)
  }
  private func save(_ value: DriveCredentials) throws {
    let data = try JSONEncoder().encode(value)
    let query = keychainQuery()
    let update = [kSecValueData as String: data] as [String: Any]
    var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var insert = query
      insert[kSecValueData as String] = data
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      status = SecItemAdd(insert as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw DriveFailure(message: "Could not save Google Drive credentials in the iOS Keychain.") }
  }

  private func randomURLString() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw DriveFailure(message: "Could not prepare secure Google sign-in.") }
    return base64URL(Data(bytes))
  }
  private func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  private func connect(presenter: ASWebAuthenticationPresentationContextProviding, expectedAccountId: String? = nil) async throws {
    guard session == nil else { throw DriveFailure(message: "Google sign-in is already open.") }
    guard let clientId else { throw DriveFailure(message: "Google Drive is not configured in this build. Set up the iOS OAuth client using docs/google-drive-ios.md.") }
    let callbackScheme = clientId.split(separator: ".").reversed().joined(separator: ".")
    let registered = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    guard registered.contains(callbackScheme) else { throw DriveFailure(message: "This build is missing the Google sign-in callback scheme.") }
    let redirect = "\(callbackScheme):/oauth2redirect"
    let verifier = try randomURLString()
    let state = try randomURLString()
    var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    url.queryItems = [
      "client_id": clientId, "redirect_uri": redirect, "response_type": "code",
      "scope": scope, "state": state, "code_challenge_method": "S256",
      "code_challenge": base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))),
      "access_type": "offline", "prompt": "consent",
    ].map { URLQueryItem(name: $0.key, value: $0.value) }
    defer { session = nil }
    let callback: URL = try await withCheckedThrowingContinuation { continuation in
      let authentication = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: callbackScheme) { callback, error in
        if let callback, error == nil { continuation.resume(returning: callback) }
        else { continuation.resume(throwing: DriveFailure(message: "Google sign-in was cancelled or could not finish.")) }
      }
      authentication.presentationContextProvider = presenter
      authentication.prefersEphemeralWebBrowserSession = false
      session = authentication
      if !authentication.start() {
        session = nil
        continuation.resume(throwing: DriveFailure(message: "Could not start Google sign-in."))
      }
    }
    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard callback.scheme == callbackScheme, callback.path == "/oauth2redirect",
          items.first(where: { $0.name == "state" })?.value == state,
          let code = items.first(where: { $0.name == "code" })?.value else { throw DriveFailure(message: "Google sign-in could not be verified. Please try again.") }
    let tokens = try await exchange(["client_id": clientId, "code": code, "code_verifier": verifier, "redirect_uri": redirect, "grant_type": "authorization_code"])
    guard let access = tokens["access_token"] as? String, let refresh = tokens["refresh_token"] as? String,
          (tokens["scope"] as? String ?? "").split(separator: " ").contains(Substring(scope)) else {
      throw DriveFailure(message: "Allow Google Drive access to open an existing vault.")
    }
    var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/about?fields=user(permissionId,emailAddress)")!)
    request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await http.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let about = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let user = about["user"] as? [String: Any], let accountId = user["permissionId"] as? String,
          let email = user["emailAddress"] as? String else { throw DriveFailure(message: "Could not verify your Google Drive account. Check that the Drive API is enabled.") }
    if let expectedAccountId, expectedAccountId != accountId {
      throw DriveFailure(message: "Sign in with the original Google account to reconnect this vault. The existing connection has been kept.")
    }
    try save(DriveCredentials(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(tokens["expires_in"] as? Double ?? 3600), accountId: accountId, email: email, clientId: clientId))
  }

  private func exchange(_ fields: [String: String]) async throws -> [String: Any] {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    request.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").data(using: .utf8)
    let (data, response) = try await http.data(for: request)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DriveFailure(message: "Google returned an invalid sign-in response.") }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      if json["error"] as? String == "invalid_grant" { throw DriveFailure(message: "Google Drive sign-in expired. Disconnect and reconnect your account.") }
      throw DriveFailure(message: "Google sign-in failed. Check the iOS OAuth client and test-user configuration.")
    }
    return json
  }

  private func token(force: Bool = false) async throws -> String {
    if let refreshTask { return try await refreshTask.value }
    guard var saved = try credentials(), saved.clientId == clientId else { throw DriveFailure(message: "Connect your Google Drive account first.") }
    if !force && saved.expiresAt.timeIntervalSinceNow > 60 { return saved.accessToken }
    let task = Task<String, Error> {
      let json = try await self.exchange(["client_id": saved.clientId, "refresh_token": saved.refreshToken, "grant_type": "refresh_token"])
      try Task.checkCancellation()
      guard let access = json["access_token"] as? String else { throw DriveFailure(message: "Google did not return an access token.") }
      saved.accessToken = access
      saved.refreshToken = json["refresh_token"] as? String ?? saved.refreshToken
      saved.expiresAt = Date().addingTimeInterval(json["expires_in"] as? Double ?? 3600)
      try self.save(saved)
      return access
    }
    refreshTask = task
    defer { refreshTask = nil }
    return try await task.value
  }

  private func request(_ command: GoogleDriveCommand) async throws -> [String: Any] {
    guard let saved = try credentials(), command.accountId == saved.accountId else { throw DriveFailure(message: "This vault belongs to a different Google account. Reconnect the original account.") }
    guard let path = command.path,
          path.range(of: #"^/(upload/)?drive/v[23]/files(/[a-zA-Z0-9_-]+)?$"#, options: .regularExpression) != nil,
          ["GET", "POST", "PATCH", "PUT"].contains(command.method ?? "GET") else { throw DriveFailure(message: "Invalid Google Drive request.") }
    var components = URLComponents(string: "https://www.googleapis.com\(path)")!
    components.queryItems = (command.query ?? [:]).map { URLQueryItem(name: $0.key, value: $0.value) }
    var request = URLRequest(url: components.url!)
    request.httpMethod = command.method ?? "GET"
    if let body = command.body {
      guard let data = Data(base64Encoded: body), data.count <= 25 * 1024 * 1024 else { throw DriveFailure(message: "Google Drive uploads are limited to 25 MB in this version.") }
      request.httpBody = data
    }
    request.setValue(command.contentType, forHTTPHeaderField: "Content-Type")
    request.setValue(command.ifMatch, forHTTPHeaderField: "If-Match")
    request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
    var (data, response) = try await http.data(for: request)
    // Retry only an explicit authentication rejection, never an ambiguous mutation.
    if (response as? HTTPURLResponse)?.statusCode == 401 {
      request.setValue("Bearer \(try await token(force: true))", forHTTPHeaderField: "Authorization")
      (data, response) = try await http.data(for: request)
    }
    guard let httpResponse = response as? HTTPURLResponse else { throw DriveFailure(message: "No response from Google Drive.") }
    var result: [String: Any] = ["status": httpResponse.statusCode, "body": data.base64EncodedString()]
    if let etag = httpResponse.value(forHTTPHeaderField: "ETag") { result["etag"] = etag }
    return result
  }
}
