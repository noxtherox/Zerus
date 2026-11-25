import Foundation

/// The production app took over the `com.zerus.notes` identity from the retired
/// Tauri desktop app. Earlier native builds ran as `com.zerus.notes.macos.native`
/// ("Zerus Native"), so carry their preferences over once, before any view reads
/// `@AppStorage`. Private files under Application Support keep their existing
/// "Zerus Native" folder names and need no move; Keychain service names are unchanged.
enum MacIdentityMigration {
    static let legacyDomain = "com.zerus.notes.macos.native"
    static let marker = "zerus.mac.identityMigration.v1"

    static func run(defaults: UserDefaults = .standard, legacy: [String: Any]? = UserDefaults.standard.persistentDomain(forName: legacyDomain)) {
        guard Bundle.main.bundleIdentifier != legacyDomain, !defaults.bool(forKey: marker) else { return }
        // Native preferences win over keys the Tauri app's web view left in this domain.
        for (key, value) in legacy ?? [:] { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: marker)
    }
}
