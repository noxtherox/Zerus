import XCTest
@testable import ZerusNative

@MainActor
final class NativeNoteResumeTests: XCTestCase {
    func testPersistedVisitsFollowUniqueIdentitiesProtectOtherVaultsAndRefuseUnavailableOrUnknownState() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        UserDefaults.standard.removeObject(forKey: NativeNoteResumeStore.key)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Resume-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let io = VaultFiles(root: root)
        var original: [String: Data] = [:]
        for name in ["A", "B", "C"] {
            let data = Data(("---\nzerus-id: " + name.lowercased() + "\nforeign: keep\n---\n# " + name + "\n\nOriginal bytes.\n").utf8)
            try await io.write(name + ".md", data: data, expected: nil); original[name] = data
        }
        let vault = VaultStore(); await vault.open(root)
        let id = try XCTUnwrap(vault.activeVaultID)
        func note(_ identity: String, in store: VaultStore) throws -> NoteDocument { try XCTUnwrap(store.notes.first { $0.stableID == identity }) }
        let navigation = NativeNoteNavigation(vault: vault, session: try XCTUnwrap(vault.session(for: note("a", in: vault))), originTab: 2)
        navigation.activatePersistence()
        await navigation.open(try note("b", in: vault), from: navigation.current.id)
        let bVisit = navigation.current
        let position = NativeReadingPosition(bodyHash: NativeReadingPosition.hash(bVisit.session.document.parts.body), source: true, selection: 4, selectionLength: 1, top: 0, lineOffset: 0)
        navigation.recordPosition(position, for: bVisit.id)
        await navigation.open(try note("c", in: vault), from: bVisit.id)
        await navigation.jump(to: bVisit.id, from: navigation.current.id)
        try await io.move("B.md", to: "Renamed B.md", expected: try XCTUnwrap(original["B"])); await vault.refresh(); navigation.checkpoint()
        let fresh = VaultStore(); await fresh.open(root)
        XCTAssertNotEqual(vault.workspaceID, fresh.workspaceID); XCTAssertEqual(fresh.activeVaultID, id)
        let restored = try XCTUnwrap(NativeNoteNavigation.restore(vault: fresh))
        XCTAssertEqual(restored.current.session.document.path, "Renamed B.md"); XCTAssertEqual(restored.originTab, 2)
        XCTAssertEqual(restored.history.map(\.stableID), ["a", "b", "c"]); XCTAssertEqual(restored.forward.last?.stableID, "c")
        XCTAssertEqual(restored.position(for: restored.current.id), position)
        restored.activatePersistence()
        let leasedBytes = try XCTUnwrap(UserDefaults.standard.data(forKey: NativeNoteResumeStore.key))
        navigation.checkpoint(); navigation.close()
        XCTAssertEqual(UserDefaults.standard.data(forKey: NativeNoteResumeStore.key), leasedBytes, "An older window cannot replace or clear the newly restored session")
        await restored.jump(to: try XCTUnwrap(restored.forward.last?.id), from: restored.current.id)
        XCTAssertEqual(restored.current.stableID, "c")
        for (name, bytes) in original { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name == "B" ? "Renamed B.md" : name + ".md")), bytes) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("A.md"))
        try XCTUnwrap(original["B"]).write(to: root.appendingPathComponent("Duplicate B.md"))
        await fresh.refresh()
        let surviving = try XCTUnwrap(NativeNoteNavigation.restore(vault: fresh))
        XCTAssertEqual(surviving.history.map(\.stableID), ["c"]); XCTAssertNotNil(surviving.issue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("A.md").path))
        let beforeRefusal = UserDefaults.standard.data(forKey: NativeNoteResumeStore.key)
        try XCTUnwrap(original["C"]).write(to: root.appendingPathComponent("Duplicate C.md")); await fresh.refresh()
        XCTAssertThrowsError(try NativeNoteNavigation.restore(vault: fresh))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Duplicate C.md"))
        let replacement = Data("---\nzerus-id: replacement\n---\n# Different file\n".utf8)
        try replacement.write(to: root.appendingPathComponent("C.md")); await fresh.refresh()
        XCTAssertThrowsError(try NativeNoteNavigation.restore(vault: fresh))
        XCTAssertEqual(UserDefaults.standard.data(forKey: NativeNoteResumeStore.key), beforeRefusal)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("C.md")), replacement)
        let other = root.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try XCTUnwrap(original["C"]).write(to: other.appendingPathComponent("C.md"))
        await fresh.open(other); XCTAssertNil(try NativeNoteNavigation.restore(vault: fresh))
        restored.activatePersistence(); restored.checkpoint(); restored.close()
        XCTAssertEqual(UserDefaults.standard.data(forKey: NativeNoteResumeStore.key), beforeRefusal, "A previous activation cannot resume ownership after a vault switch")
        await fresh.open(root)
        let saved = try XCTUnwrap(beforeRefusal), object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        var newer = object; newer["version"] = 2
        var foreign = object; foreign["future-layout"] = ["preserve": true]
        var escaping = object, rows = try XCTUnwrap(object["vaults"] as? [String: [String: Any]])
        var row = try XCTUnwrap(rows[id.uuidString]), entries = try XCTUnwrap(row["entries"] as? [[String: Any]])
        entries[0]["path"] = "../outside.md"; row["entries"] = entries; rows[id.uuidString] = row; escaping["vaults"] = rows
        var outOfBounds = object; row["entries"] = try XCTUnwrap((object["vaults"] as? [String: [String: Any]])?[id.uuidString]?["entries"] as? [[String: Any]])
        row["current"] = 1000; rows[id.uuidString] = row; outOfBounds["vaults"] = rows
        var malformed = try [newer, foreign, escaping, outOfBounds].map { try JSONSerialization.data(withJSONObject: $0) }
        malformed.append(Data("{".utf8)); malformed.append(Data(repeating: 0, count: 2_000_001))
        for bytes in malformed {
            UserDefaults.standard.set(bytes, forKey: NativeNoteResumeStore.key)
            XCTAssertThrowsError(try NativeNoteResumeStore.load(id))
            XCTAssertThrowsError(try NativeNoteNavigation.restore(vault: fresh))
            let ordinary = NativeNoteNavigation(vault: fresh, session: try XCTUnwrap(fresh.session(for: fresh.notes.first { $0.path == "C.md" }!)))
            ordinary.activatePersistence(); XCTAssertNotNil(ordinary.issue)
            ordinary.issue = nil; ordinary.checkpoint(); XCTAssertNil(ordinary.issue, "A dismissed resume warning must not recur on the next viewport update")
            ordinary.close(); XCTAssertNil(ordinary.issue, "Closing a view must not repeat its already dismissed resume warning")
            XCTAssertEqual(UserDefaults.standard.data(forKey: NativeNoteResumeStore.key), bytes)
        }
        UserDefaults.standard.set("future representation", forKey: NativeNoteResumeStore.key)
        XCTAssertThrowsError(try NativeNoteResumeStore.load(id))
        XCTAssertEqual(UserDefaults.standard.string(forKey: NativeNoteResumeStore.key), "future representation")
    }

    func testLegacyViewsRequireTheirOriginalBytesAndPersistedHistoryIsBoundedAndExplicitlyClosed() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        UserDefaults.standard.removeObject(forKey: NativeNoteResumeStore.key)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyResume-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = Data("---\nforeign: keep\n---\n# Legacy\nRead without modifying me.\n".utf8)
        try legacy.write(to: root.appendingPathComponent("Legacy.md"))
        try Data("---\nzerus-id: second\n---\n# Second\n".utf8).write(to: root.appendingPathComponent("Second.md"))
        let vault = VaultStore(); await vault.open(root)
        let navigation = NativeNoteNavigation(vault: vault, session: try XCTUnwrap(vault.session(for: vault.notes.first { $0.path == "Legacy.md" }!)))
        navigation.activatePersistence(); let id = try XCTUnwrap(vault.activeVaultID)
        XCTAssertEqual(try NativeNoteNavigation.restore(vault: vault)?.current.session.document.path, "Legacy.md")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Legacy.md")), legacy, "Reading/restoring a legacy note does not add an identity")
        let changed = Data("# Legacy\nAn outside replacement.\n".utf8)
        try changed.write(to: root.appendingPathComponent("Legacy.md"))
        let replacedVault = VaultStore(); await replacedVault.open(root)
        XCTAssertThrowsError(try NativeNoteNavigation.restore(vault: replacedVault))
        try legacy.write(to: root.appendingPathComponent("Legacy.md")); await vault.refresh()
        for index in 0..<109 {
            let path = index.isMultiple(of: 2) ? "Second.md" : "Legacy.md"
            await navigation.open(try XCTUnwrap(vault.notes.first { $0.path == path }), from: navigation.current.id)
        }
        let record = try XCTUnwrap(NativeNoteResumeStore.load(id))
        XCTAssertEqual(record.entries.count, 100); XCTAssertEqual(record.current, 99)
        let restored = try XCTUnwrap(NativeNoteNavigation.restore(vault: vault)); restored.activatePersistence(); restored.close(); restored.checkpoint()
        XCTAssertNil(try NativeNoteNavigation.restore(vault: vault)); XCTAssertNil(try NativeNoteResumeStore.load(id))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Legacy.md")), legacy)
    }
}
