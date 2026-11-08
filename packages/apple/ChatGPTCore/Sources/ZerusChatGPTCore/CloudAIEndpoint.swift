import Foundation

/// Device settings can select a native account connection or an HTTPS API.
public enum CloudAIEndpoint {
  public static let chatGPT = "codex://chatgpt"

  public static func restored(_ stored: String?, fallback: String) -> String {
    if stored == chatGPT { return chatGPT }
    return (try? normalizedHTTP(stored ?? fallback)) ?? fallback
  }

  public static func normalizedHTTP(_ endpoint: String) throws -> String {
    let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let url = URL(string: trimmed), url.scheme == "https", url.host != nil else {
      throw ChatGPTError.message("Enter a valid HTTPS AI endpoint.")
    }
    return trimmed
  }
}
