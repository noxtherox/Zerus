import XCTest
@testable import ZerusNative

/// Restore real app preferences after real store tests, including failed tests.
struct NativeVaultPreferencesBackup: Sendable {
    private let values: [String: Data]
    private let searchRecents: Data
    private static let keys = ["zerus.native.vault.bookmark", "zerus.native.vault.registry", "zerus.native.note.resume"]
    private static let recentPrefix = "zerus.native.search.recent."
    init() {
        values = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in UserDefaults.standard.data(forKey: key).map { (key, $0) } })
        let recents = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix(Self.recentPrefix) }
        searchRecents = try! PropertyListSerialization.data(fromPropertyList: recents, format: .binary, options: 0)
    }
    func restore() {
        for key in Self.keys {
            if let bytes = values[key] { UserDefaults.standard.set(bytes, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(Self.recentPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let recents = try! PropertyListSerialization.propertyList(from: searchRecents, options: [], format: nil) as! [String: Any]
        for (key, value) in recents { UserDefaults.standard.set(value, forKey: key) }
    }
}

final class NativeVaultRegistryTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        UserDefaults.standard.removeObject(forKey: NativeVaultRegistry.key)
        UserDefaults.standard.removeObject(forKey: "zerus.native.vault.bookmark")
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    @MainActor
    func testOpeningRelocatedBookmarkRetainsRegistrationAndAmbiguousAliasesRequireExplicitSelection() async throws {
        let folder = root.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = Data("# Relocated\nOriginal bytes.".utf8)
        try original.write(to: folder.appendingPathComponent("Note.md"))
        let store = VaultStore(); await store.open(folder)
        let id = try XCTUnwrap(store.activeVaultID)
        store.renameSavedVault(id, to: "My saved library")
        // A bookmark resolves in the current container, but the last recorded
        // location can still name the container used before the update.
        var value = try JSONSerialization.jsonObject(with: XCTUnwrap(UserDefaults.standard.data(forKey: NativeVaultRegistry.key))) as! [String: Any]
        var rows = value["entries"] as! [[String: Any]]
        let previousLocation = root.appendingPathComponent("Previous container/Moved", isDirectory: true)
        rows[0]["location"] = previousLocation.absoluteString
        rows[0]["foreign"] = ["retain": true]; value["entries"] = rows
        let relocatedBytes = try JSONSerialization.data(withJSONObject: value)
        UserDefaults.standard.set(relocatedBytes, forKey: NativeVaultRegistry.key)
        // Reusing the old path must not attach the moved vault's identity to
        // an unrelated folder when its bookmark identifies the new location.
        try FileManager.default.createDirectory(at: previousLocation, withIntermediateDirectories: true)
        try Data("# Independent\nOther folder.".utf8).write(to: previousLocation.appendingPathComponent("Other.md"))
        let independent = VaultStore(); await independent.open(previousLocation)
        XCTAssertNotEqual(independent.activeVaultID, id)
        XCTAssertEqual(independent.savedVaults.count, 2)
        UserDefaults.standard.set(relocatedBytes, forKey: NativeVaultRegistry.key)
        let reopened = VaultStore(); await reopened.open(folder)
        XCTAssertEqual(reopened.activeVaultID, id)
        XCTAssertEqual(reopened.savedVaults.count, 1)
        XCTAssertEqual(reopened.vaultName, "My saved library")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Note.md")), original)
        let updated = try JSONSerialization.jsonObject(with: XCTUnwrap(UserDefaults.standard.data(forKey: NativeVaultRegistry.key))) as! [String: Any]
        XCTAssertEqual(((updated["entries"] as? [[String: Any]])?.first?["foreign"] as? [String: Bool])?["retain"], true)

        // Historical duplicates have separate private namespaces. Never pick
        // one by list order or merge them when opening a folder in Files.
        var ambiguous = updated, aliases = updated["entries"] as! [[String: Any]]
        var alias = aliases[0]; let aliasID = UUID(); alias["id"] = aliasID.uuidString
        aliases.append(alias); ambiguous["entries"] = aliases
        let ambiguousBytes = try JSONSerialization.data(withJSONObject: ambiguous)
        UserDefaults.standard.set(ambiguousBytes, forKey: NativeVaultRegistry.key)
        let reader = VaultStore(); await reader.open(folder)
        XCTAssertNil(reader.root)
        XCTAssertTrue(reader.restorationIssue?.contains("Saved vaults") == true)
        XCTAssertEqual(UserDefaults.standard.data(forKey: NativeVaultRegistry.key), ambiguousBytes)
        await reader.openSavedVault(aliasID)
        XCTAssertEqual(reader.activeVaultID, aliasID)
        XCTAssertEqual(reader.savedVaults.count, 2)
        let relaunched = VaultStore(); await relaunched.restore()
        XCTAssertEqual(relaunched.activeVaultID, aliasID)
        XCTAssertEqual(relaunched.savedVaults.count, 2)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Note.md")), original)
    }

    @MainActor
    func testLegacyVaultMigratesAndSavedSwitchingRetainsDraftsNamesIdentityAndFilesAcrossRelaunch() async throws {
        let a = root.appendingPathComponent("A", isDirectory: true), b = root.appendingPathComponent("B", isDirectory: true)
        for url in [a, b] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let originalA = "---\nzerus-id: a\n---\n# A\nOriginal A.", originalB = "# B\nOriginal B."
        try Data(originalA.utf8).write(to: a.appendingPathComponent("Note.md"))
        try Data(originalB.utf8).write(to: b.appendingPathComponent("Note.md"))
        UserDefaults.standard.set(try a.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "zerus.native.vault.bookmark")
        let store = VaultStore(); await store.restore()
        let aID = try XCTUnwrap(store.activeVaultID)
        XCTAssertEqual(store.savedVaults.map(\.title), ["A"])
        let session = try XCTUnwrap(store.session(for: XCTUnwrap(store.notes.first)))
        session.updateBody("# A\nSaved before switching.")
        await store.open(b)
        let bID = try XCTUnwrap(store.activeVaultID)
        XCTAssertNotEqual(aID, bID); XCTAssertEqual(store.savedVaults.count, 2)
        XCTAssertEqual(try String(contentsOf: a.appendingPathComponent("Note.md"), encoding: .utf8), "---\nzerus-id: a\n---\n# A\nSaved before switching.")
        store.renameSavedVault(aID, to: "Personal thoughts")
        let restarted = VaultStore(); await restarted.restore()
        XCTAssertEqual(restarted.activeVaultID, bID); XCTAssertEqual(restarted.notes.first?.content, originalB)
        await restarted.openSavedVault(aID)
        XCTAssertEqual(restarted.vaultName, "Personal thoughts")
        XCTAssertEqual(restarted.notes.first?.content, "---\nzerus-id: a\n---\n# A\nSaved before switching.")
        // Selecting an alias for the same folder does not create a second vault.
        let alias = root.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
        await restarted.open(alias)
        XCTAssertEqual(restarted.activeVaultID, aID); XCTAssertEqual(restarted.savedVaults.count, 2)
        XCTAssertEqual(restarted.vaultName, "Personal thoughts")
        // A conflict keeps the draft and active vault instead of switching away.
        let draft = try XCTUnwrap(restarted.session(for: XCTUnwrap(restarted.notes.first)))
        draft.updateBody("# A\nMy unresolved draft.")
        try Data("# A\nAn outside edit.".utf8).write(to: a.appendingPathComponent("Note.md"), options: .atomic)
        await restarted.openSavedVault(bID)
        XCTAssertEqual(restarted.activeVaultID, aID); XCTAssertTrue(draft.dirty)
        XCTAssertTrue(restarted.error?.contains("unsaved drafts") == true)
        XCTAssertEqual(try String(contentsOf: b.appendingPathComponent("Note.md"), encoding: .utf8), originalB)
        // Removal is registration-only, even for the currently open vault.
        restarted.removeSavedVault(bID)
        XCTAssertEqual(try String(contentsOf: b.appendingPathComponent("Note.md"), encoding: .utf8), originalB)
        restarted.removeSavedVault(aID)
        XCTAssertNil(restarted.activeVaultID); XCTAssertEqual(restarted.savedVaults.count, 0)
        XCTAssertTrue(draft.dirty); XCTAssertNotNil(restarted.root)
        let afterRemoval = VaultStore(); await afterRemoval.restore()
        XCTAssertNil(afterRemoval.root)
        XCTAssertEqual(try String(contentsOf: a.appendingPathComponent("Note.md"), encoding: .utf8), "# A\nAn outside edit.")
    }

    @MainActor
    func testUnavailableVaultAndUnsupportedRegistryRetainOriginalAccessWhileOtherFoldersRemainUsable() async throws {
        let a = root.appendingPathComponent("Unavailable", isDirectory: true), b = root.appendingPathComponent("Available", isDirectory: true)
        for url in [a, b] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        try Data("# Available\nIndependent bytes.".utf8).write(to: b.appendingPathComponent("Note.md"))
        let store = VaultStore(); await store.open(a)
        let aID = try XCTUnwrap(store.activeVaultID), original = try XCTUnwrap(UserDefaults.standard.data(forKey: NativeVaultRegistry.key))
        await store.open(b)
        let bID = try XCTUnwrap(store.activeVaultID)
        try FileManager.default.removeItem(at: a)
        await store.openSavedVault(aID)
        XCTAssertEqual(store.activeVaultID, bID); XCTAssertEqual(store.notes.first?.title, "Available")
        XCTAssertNotNil(store.error); XCTAssertEqual(store.savedVaults.count, 2)
        // Future/malformed formats stay byte-exact while manual Files opens work.
        let future = Data(#"{"version":91,"entries":[],"foreign":"must survive"}"#.utf8)
        for bytes in [future, Data("not JSON".utf8)] {
            UserDefaults.standard.set(bytes, forKey: NativeVaultRegistry.key)
            let restarted = VaultStore(); XCTAssertNotNil(restarted.savedVaultIssue)
            await restarted.open(b)
            XCTAssertEqual(restarted.notes.first?.title, "Available")
            XCTAssertEqual(UserDefaults.standard.data(forKey: NativeVaultRegistry.key), bytes)
        }
        // Version-one records retain foreign fields on rename and activation.
        var value = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        value["future"] = ["keep": true]
        var rows = value["entries"] as! [[String: Any]]; rows[0]["foreign"] = 42; value["entries"] = rows
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: value), forKey: NativeVaultRegistry.key)
        let reader = VaultStore(); reader.renameSavedVault(aID, to: "Keep access")
        let final = try JSONSerialization.jsonObject(with: XCTUnwrap(UserDefaults.standard.data(forKey: NativeVaultRegistry.key))) as! [String: Any]
        XCTAssertEqual((final["future"] as? [String: Bool])?["keep"], true)
        XCTAssertEqual((final["entries"] as? [[String: Any]])?.first?["foreign"] as? Int, 42)
        XCTAssertEqual((final["entries"] as? [[String: Any]])?.first?["bookmark"] as? String, rows[0]["bookmark"] as? String)
    }
}
