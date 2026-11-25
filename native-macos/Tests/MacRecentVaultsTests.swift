import XCTest
import AppKit
@testable import Zerus_Native

@MainActor final class MacRecentVaultsTests: XCTestCase {
    func testTemporaryFoldersStayOutOfRecents() {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-chat-controller-" + UUID().uuidString)
        XCTAssertTrue(MacRecentVaults.isTemporary(temporary.path))
        XCTAssertTrue(MacRecentVaults.isTemporary(temporary.resolvingSymlinksInPath().path))
        XCTAssertTrue(MacRecentVaults.isTemporary("/private/tmp/preview"))
        XCTAssertFalse(MacRecentVaults.isTemporary(NSHomeDirectory() + "/Documents/Notes"))
        XCTAssertFalse(MacRecentVaults.isTemporary("/tmpfiles/Notes"))
    }

    func testLocationDistinguishesSameNamedVaults() {
        let home = NSHomeDirectory()
        XCTAssertEqual(MacRecentVaults.location(home + "/Documents/Vault"), "~/Documents")
        XCTAssertEqual(MacRecentVaults.location(home + "/Vault"), "~")
        XCTAssertEqual(MacRecentVaults.location("/Volumes/Data/Vault"), "/Volumes/Data")
        XCTAssertEqual(MacRecentVaults.letter("/x/_zerus notes"), "Z")
        XCTAssertEqual(MacRecentVaults.letter("/x/__"), "V")
    }

    func testForgettingRemovesVaultAndItsIcon() throws {
        let defaults = UserDefaults.standard
        let oldRecents = defaults.object(forKey: MacRecentVaults.recentsKey), oldIcons = defaults.object(forKey: MacRecentVaults.iconsKey)
        defer { defaults.set(oldRecents, forKey: MacRecentVaults.recentsKey); defaults.set(oldIcons, forKey: MacRecentVaults.iconsKey) }
        let path = NSHomeDirectory() + "/Zerus-recents-test-" + UUID().uuidString
        let workspace = MacWorkspace()
        workspace.recentVaults = [path, "/Volumes/Other/Vault"]
        workspace.setVaultIcon(path, "emoji:🌿")
        XCTAssertEqual((defaults.dictionary(forKey: MacRecentVaults.iconsKey) as? [String: String])?[path], "emoji:🌿")
        workspace.forgetRecentVault(path)
        XCTAssertEqual(workspace.recentVaults, ["/Volumes/Other/Vault"])
        XCTAssertEqual(defaults.stringArray(forKey: MacRecentVaults.recentsKey), ["/Volumes/Other/Vault"])
        XCTAssertNil(workspace.vaultIcons[path])
    }

    func testImageIconsAreStoredAsSquareThumbnails() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("vault-icon-" + UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: source) }
        let image = NSImage(size: NSSize(width: 400, height: 200)); image.lockFocus(); NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: 400, height: 200).fill(); image.unlockFocus()
        let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: source)
        let data = try MacRecentVaults.squarePNG(from: source)
        let thumbnail = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(thumbnail.pixelsWide, 160); XCTAssertEqual(thumbnail.pixelsHigh, 160)
        XCTAssertThrowsError(try MacRecentVaults.squarePNG(from: URL(fileURLWithPath: "/nonexistent.png")))
    }
}
