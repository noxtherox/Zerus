import XCTest
@testable import Zerus_Native

final class MacIdentityMigrationTests: XCTestCase {
    private func defaults() -> (UserDefaults, String) {
        let suite = "zerus.tests.identity." + UUID().uuidString
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testCopiesPreviewPreferencesOnceAndPrefersThemOverExistingKeys() {
        let (store, suite) = defaults()
        defer { store.removePersistentDomain(forName: suite) }
        store.set("tauri", forKey: "zerus.mac.appearance")
        store.set(7, forKey: "unrelated")
        MacIdentityMigration.run(defaults: store, legacy: ["zerus.mac.appearance": "dark", "zerus.mac.recentVaults": ["/v"]])
        XCTAssertEqual(store.string(forKey: "zerus.mac.appearance"), "dark")
        XCTAssertEqual(store.stringArray(forKey: "zerus.mac.recentVaults"), ["/v"])
        XCTAssertEqual(store.integer(forKey: "unrelated"), 7)
        XCTAssertTrue(store.bool(forKey: MacIdentityMigration.marker))

        // A later launch must not overwrite preferences changed after migration.
        store.set("light", forKey: "zerus.mac.appearance")
        MacIdentityMigration.run(defaults: store, legacy: ["zerus.mac.appearance": "dark"])
        XCTAssertEqual(store.string(forKey: "zerus.mac.appearance"), "light")
    }

    func testMarksMigrationDoneWithoutPreviewDomain() {
        let (store, suite) = defaults()
        defer { store.removePersistentDomain(forName: suite) }
        MacIdentityMigration.run(defaults: store, legacy: nil)
        XCTAssertTrue(store.bool(forKey: MacIdentityMigration.marker))
    }
}
