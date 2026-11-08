import XCTest
@testable import ZerusNative

final class NativeFolderTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testEmptyNestedFoldersSurviveReopeningWithoutPlaceholderNotesAndLinkedFoldersAreRefused() async throws {
        let io = VaultFiles(root: root)
        let created = try await io.createFolder("Projects/Empty")
        XCTAssertEqual(created.folders, ["Projects", "Projects/Empty"])
        XCTAssertTrue(created.notes.isEmpty); XCTAssertTrue(created.files.isEmpty)
        let cold = try await VaultFiles(root: root).scan()
        XCTAssertEqual(cold.folders, ["Projects", "Projects/Empty"])
        for path in ["../Outside", ".zerus/Secret", "assets/Hidden", "Projects//Bad", "Projects/Empty", "Projects/Bad:name", "Projects/Bad\nname"] {
            do { _ = try await io.createFolder(path); XCTFail("Invalid or occupied folder must be refused: \(path)") } catch {}
        }
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Outside link"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Inside link"), withDestinationURL: root.appendingPathComponent("Projects"))
        for path in ["Outside link/New", "Inside link/New"] {
            do { _ = try await io.createFolder(path); XCTFail("A linked descendant must not create an invisible/outside folder") } catch {}
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("New").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Projects/New").path))
        let final = try await io.scan(); XCTAssertEqual(final.folders, ["Projects", "Projects/Empty"])
    }

    func testSharedIconChangesPreserveForeignFieldsAndRejectStaleOrUnsupportedData() async throws {
        let io = VaultFiles(root: root); _ = try await io.createFolder("Work")
        let original: [String: Any] = ["Work": "🧠", "Other": "tabler:Star", "future": ["version": 2, "keep": true]]
        let bytes = try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys])
        try await io.write(".zerus/type-icons.json", data: bytes, expected: nil)
        let snapshot = try await io.folderIconSnapshot()
        _ = try await io.setFolderIcon(snapshot, folder: "Work", value: "tabler:Briefcase")
        let actual = try await io.read(".zerus/type-icons.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: actual) as? [String: Any])
        XCTAssertEqual(object["Work"] as? String, "tabler:Briefcase")
        XCTAssertEqual(object["Other"] as? String, "tabler:Star")
        XCTAssertTrue(NSDictionary(dictionary: try XCTUnwrap(object["future"] as? [String: Any])).isEqual(original["future"]))
        do { _ = try await io.setFolderIcon(snapshot, folder: "Work", value: "🎨"); XCTFail("An old picker must not overwrite newer icon bytes") } catch {}
        let afterStale = try await io.read(".zerus/type-icons.json"); XCTAssertEqual(afterStale, actual)
        let current = try await io.folderIconSnapshot()
        do { _ = try await io.setFolderIcon(current, folder: "Work", value: "not an icon"); XCTFail("Plain text must not become a broken icon") } catch {}
        _ = try await io.setFolderIcon(current, folder: "Work", value: nil)
        let reopened = try await VaultFiles(root: root).scan()
        XCTAssertNil(reopened.folderIcons["Work"]); XCTAssertEqual(reopened.folderIcons["Other"], "tabler:Star")
        let malformed = Data("[\"future format\"]".utf8)
        let reset = try await io.read(".zerus/type-icons.json")
        try await io.write(".zerus/type-icons.json", data: malformed, expected: reset)
        let protected = try await io.scan(); XCTAssertNotNil(protected.folderIssue); XCTAssertTrue(protected.folders.contains("Work"))
        do { _ = try await io.folderIconSnapshot(); XCTFail("Unsupported icon files cannot be silently replaced") } catch {}
        let untouched = try await io.read(".zerus/type-icons.json"); XCTAssertEqual(untouched, malformed)
    }

    @MainActor
    func testLibraryOrderingKeepsSubtreesTogetherSurvivesColdOpenAndRejectsOldWorkspaceForms() async throws {
        let original = Data("# Existing\n\nKeep the note bytes.\n".utf8)
        try original.write(to: root.appendingPathComponent("Existing.md"))
        let store = VaultStore(); await store.open(root)
        let workspace = store.workspaceID, id = try XCTUnwrap(store.activeVaultID)
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: NativeFolderOrder.key(id)) }
        try await store.createFolder("Alpha/Child", workspace: workspace)
        try await store.createFolder("Beta/Child", workspace: workspace)
        XCTAssertEqual(store.notes.count, 1)
        store.reorderFolder("Beta", direction: -1, workspace: workspace)
        XCTAssertEqual(store.folders, ["Beta", "Beta/Child", "Alpha", "Alpha/Child", "Inbox"])
        let cold = VaultStore(); await cold.open(root)
        XCTAssertEqual(cold.activeVaultID, id); XCTAssertEqual(cold.folders, store.folders)
        let oldIconPicker = try await store.folderIconSnapshot(workspace: workspace)
        let other = root.appendingPathComponent("OtherVault")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await store.open(other)
        do { try await store.createFolder("Stale", workspace: workspace); XCTFail("An old form must not create in a different vault") } catch {}
        do { try await store.setFolderIcon(oldIconPicker, folder: "Alpha", value: "📚"); XCTFail("An old icon picker must not mutate a different vault") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Stale").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.appendingPathComponent("Stale").path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Existing.md")), original)
    }
}
