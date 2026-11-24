import Foundation

/// Keep legacy working copies and mappings readable without reconnecting to the
/// retired direct Drive service. Existing Keychain records remain untouched.
@MainActor
final class NativeDriveAccount {
    static let shared = NativeDriveAccount()
    private init() {}
    func files(account: String? = nil) async throws -> NativeDriveFiles {
        throw VaultFailure(message: "Direct Google Drive connections are no longer supported. Choose the document or map its folder in Files. Existing files and saved records have been kept.")
    }
}
