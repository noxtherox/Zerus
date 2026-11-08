import Foundation

public enum ChatGPTModelCatalog {
  public static func request(accessToken: String) -> URLRequest {
    // Catalog compatibility level, independent of Zerus's marketing version.
    // An unversioned request currently returns the legacy account catalog. Pin
    // the level supported by this Responses transport; do not advertise a
    // future/maximal version or replace discovery with a hardcoded model list.
    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models?client_version=0.159.2")!, cachePolicy: .reloadIgnoringLocalCacheData)
    request.timeoutInterval = 30
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    return request
  }
}
