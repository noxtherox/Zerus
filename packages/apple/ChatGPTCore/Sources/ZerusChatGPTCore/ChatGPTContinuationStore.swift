import Foundation
import CryptoKit

/// Device-private response items. Account credentials and vault journals are separate.
public final class ChatGPTContinuationStore {
  private let directory: URL

  public init(root: URL, account: String, model: String, conversation: String = "") {
    directory = Self.accountDirectory(root: root, account: account).appendingPathComponent(Self.hash(Data(model.utf8)), isDirectory: true).appendingPathComponent(Self.hash(Data(conversation.utf8)), isDirectory: true)
  }
  public static func removeAccount(root: URL, account: String) throws {
    let directory = accountDirectory(root: root, account: account)
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }
  public func save(messages: [[String: Any]], response: [String: Any], streamedText: String) throws {
    let result = try ChatGPTResponses.completedResult(response, streamedText: streamedText, agent: true)
    let assistant: [String: Any] = ["role": "assistant", "content": result["content"] as? String ?? "", "toolCalls": result["toolCalls"] as? [[String: String]] ?? []]
    var output = response["output"] as? [[String: Any]] ?? []
    // Some transports report final text only through their streaming deltas.
    let parsed = try ChatGPTResponses.result(response)
    if (parsed["content"] as? String ?? "").isEmpty, let text = result["content"] as? String, !text.isEmpty {
      output.append(["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]])
    }
    let bytes = try JSONSerialization.data(withJSONObject: ["version": 1, "output": output], options: [.sortedKeys, .withoutEscapingSlashes])
    guard bytes.count <= 4_000_000 else { throw invalid() }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      var protected = directory
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      try protected.setResourceValues(values)
      let file = directory.appendingPathComponent(try key(messages + [assistant]) + ".json")
      if FileManager.default.fileExists(atPath: file.path) { _ = try load(messages: messages + [assistant]) }
      #if os(iOS)
      try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      #else
      try bytes.write(to: file, options: .atomic)
      #endif
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    } catch {
      throw ChatGPTError.message("ChatGPT’s response could not be saved for reliable continuation. No new tool calls were run. Check available device storage and try again.")
    }
  }
  func load(messages: [[String: Any]]) throws -> [[String: Any]]? { try load(key: key(messages)) }
  func load(key: String) throws -> [[String: Any]]? {
    let file = directory.appendingPathComponent(key + ".json")
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    do {
      let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard (1...4_000_000).contains(size) else { throw invalid() }
      let bytes = try Data(contentsOf: file)
      guard let saved = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], saved["version"] as? Int == 1,
            let output = saved["output"] as? [[String: Any]] else { throw invalid() }
      _ = try ChatGPTResponses.result(["status": "completed", "output": output])
      return output
    } catch { throw invalid() }
  }
  private func invalid() -> ChatGPTError {
    .message("This ChatGPT continuation is unreadable or from an unsupported version. Its data and run journal were kept. Start a new request.")
  }
  /// Hash the same v1 canonical JSON array, without reserializing its entire
  /// prefix for every assistant turn. SHA256 snapshots leave the prefix reusable.
  struct Transcript {
    private var hash = SHA256()
    private var count = 0
    init() { hash.update(data: Data("[".utf8)) }
    mutating func append(_ message: [String: Any]) throws {
      let normalized: [String: Any] = ["role": message["role"] ?? "", "content": message["content"] ?? "", "images": message["images"] ?? [],
                                     "toolCalls": message["toolCalls"] ?? [], "toolCallId": message["toolCallId"] ?? NSNull()]
      let bytes = try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys, .withoutEscapingSlashes])
      if count > 0 { hash.update(data: Data(",".utf8)) }
      hash.update(data: bytes); count += 1
    }
    var key: String {
      var snapshot = hash; snapshot.update(data: Data("]".utf8))
      return snapshot.finalize().map { String(format: "%02x", $0) }.joined()
    }
  }
  private func key(_ messages: [[String: Any]]) throws -> String {
    var transcript = Transcript()
    for message in messages { try transcript.append(message) }
    return transcript.key
  }
  private static func accountDirectory(root: URL, account: String) -> URL { root.appendingPathComponent(hash(Data(account.utf8)), isDirectory: true) }
  private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
