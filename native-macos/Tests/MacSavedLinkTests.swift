import XCTest
@testable import Zerus_Native

final class MacSavedLinkTests: XCTestCase {
    func testBrowserEquivalentAddressesReuseTheExistingLinkAndRefuseDuplicateUpdatesWithoutWriting() async throws {
        let cases = [
            ("http://127.0.0.1/", "http://127.1/"),
            ("http://127.0.0.1/", "http://0x7f.1/"),
            ("https://example.test/a/b", "https://example.test/a\\b"),
            ("https://example.test/#{}", "https://example.test/#{}")
        ]
        for (canonical, alias) in cases { for operation in ["create", "update"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-address429-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let io = VaultFiles(root: root)
            let first = try await io.createSavedLink(address: canonical, title: "Original café")
            let other = try await io.createSavedLink(address: "https://other.example.test/", title: "Other")
            let noteBytes = try await io.read(first.path), otherBytes = try await io.read(other.path)
            let index = root.appendingPathComponent(".zerus/links.json"), indexBytes = try Data(contentsOf: index)
            XCTAssertEqual(first.savedLink?.address, canonical, "Stored metadata must keep the browser's canonical spelling")
            if operation == "create" {
                let duplicate = try await io.createSavedLink(address: alias, title: "Must not replace the title")
                XCTAssertEqual(duplicate.path, first.path, alias)
                XCTAssertEqual(duplicate.title, "Original café")
            } else {
                do { _ = try await io.updateSavedLink(other, address: alias); XCTFail("An equivalent browser address is already saved: " + alias) }
                catch { XCTAssertTrue(error.localizedDescription.contains("already saved")) }
            }
            XCTAssertEqual(try Data(contentsOf: index), indexBytes)
            let count = try await io.scan().notes.count; XCTAssertEqual(count, 2)
            let afterFirst = try await io.read(first.path), afterOther = try await io.read(other.path)
            XCTAssertEqual(afterFirst, noteBytes); XCTAssertEqual(afterOther, otherBytes)
        } }
    }
}
