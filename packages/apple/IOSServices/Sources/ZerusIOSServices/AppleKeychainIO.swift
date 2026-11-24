#if os(macOS)
import Foundation
import Security
import LocalAuthentication
import ZerusChatGPTCore

/// Legacy macOS Keychain authorization can wait for UI. Keep it off the main
/// actor, and never present authorization UI for a passive connection check.
enum AppleKeychainIO {
  private static let queue = DispatchQueue(label: "Zerus.Keychain.IO", qos: .userInitiated)
  private final class Work<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    func finish(_ result: Result<Value, Error>) {
      lock.lock(); guard self.result == nil else { lock.unlock(); return }
      self.result = result; let continuation = continuation; self.continuation = nil; lock.unlock()
      continuation?.resume(with: result)
    }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return result != nil }
    func run(timeout: TimeInterval?, _ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
      try await withTaskCancellationHandler(operation: {
        try await withCheckedThrowingContinuation { continuation in
          lock.lock()
          if let result { lock.unlock(); continuation.resume(with: result); return }
          self.continuation = continuation; lock.unlock()
          if let timeout { DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { self.finish(.failure(ChatGPTError.message("Keychain is busy. Retry the connection when its authorization prompt is finished."))) } }
          queue.async {
            guard !self.finished else { return }
            self.finish(Result { try operation() })
          }
        }
      }, onCancel: { self.finish(.failure(CancellationError())) })
    }
  }
  private static func query(service: String, account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
  }
  static func read(service: String, account: String, allowInteraction: Bool) async throws -> Data? {
    try await Work<Data?>().run(timeout: allowInteraction ? nil : 3) {
      var allowed = DarwinBoolean(true)
      if !allowInteraction {
        guard SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess, SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { throw ChatGPTError.message("Keychain status could not be checked without authorization UI.") }
      }
      defer { if !allowInteraction { SecKeychainSetUserInteractionAllowed(allowed.boolValue) } }
      var attributes = query(service: service, account: account)
      let context = LAContext(); context.interactionNotAllowed = !allowInteraction
      attributes[kSecUseAuthenticationContext as String] = context
      attributes[kSecReturnData as String] = true; attributes[kSecMatchLimit as String] = kSecMatchLimitOne
      var value: CFTypeRef?
      let status = SecItemCopyMatching(attributes as CFDictionary, &value)
      if status == errSecItemNotFound { return nil }
      if status == errSecUserCanceled { throw CancellationError() }
      guard status == errSecSuccess, let data = value as? Data else { throw ChatGPTError.message("Keychain access needs authorization. Use the connection controls to approve access; existing credentials are preserved.") }
      return data
    }
  }
  static func save(_ data: Data, service: String, account: String) async throws {
    try await Work<Void>().run(timeout: nil) {
      let attributes = query(service: service, account: account)
      let update: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
      let result = SecItemUpdate(attributes as CFDictionary, update as CFDictionary)
      if result == errSecSuccess { return }
      if result == errSecUserCanceled { throw CancellationError() }
      guard result == errSecItemNotFound else { throw ChatGPTError.message("Keychain could not save the connection. Existing credentials are preserved.") }
      var insert = attributes
      for (key, value) in update { insert[key] = value }
      let added = SecItemAdd(insert as CFDictionary, nil)
      if added == errSecUserCanceled { throw CancellationError() }
      guard added == errSecSuccess else { throw ChatGPTError.message("Keychain could not save the connection.") }
    }
  }
}
#endif
