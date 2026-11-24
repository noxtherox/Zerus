import XCTest
@testable import Zerus_Native

final class MacUpdatesTests: XCTestCase {
    func testNativeChannelReadsBundleAndRefusesPartialInsecureOrDesktopFeeds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-update-channel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Data(repeating: 17, count: 32).base64EncodedString()
        let cases: [(String?, String?, Bool)] = [
            ("https://updates.example.org/native/appcast.xml", key, true),
            (nil, nil, false), ("", "", false),
            ("https://updates.example.org/native/appcast.xml", nil, false),
            (nil, key, false),
            ("http://updates.example.org/appcast.xml", key, false),
            ("file:///tmp/appcast.xml", key, false),
            ("https://updates.example.org/latest.json", key, false),
            ("https://user:password@updates.example.org/appcast.xml", key, false),
            ("https://updates.example.org/appcast.xml#other", key, false),
            ("https://updates.example.org/appcast.xml", "not-a-public-key", false),
            ("https://updates.example.org/appcast.xml", Data(repeating: 17, count: 31).base64EncodedString(), false),
        ]
        for (index, entry) in cases.enumerated() {
            let folder = root.appendingPathComponent("Case\(index).bundle")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var metadata: [String: Any] = ["CFBundleIdentifier": "com.zerus.update-fixture.\(index)"]
            metadata["SUFeedURL"] = entry.0; metadata["SUPublicEDKey"] = entry.1
            try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0).write(to: folder.appendingPathComponent("Info.plist"))
            let bundle = try XCTUnwrap(Bundle(url: folder))
            if entry.2 {
                XCTAssertEqual(try MacUpdateChannel(bundle: bundle).feed.absoluteString, entry.0)
            } else {
                XCTAssertThrowsError(try MacUpdateChannel(bundle: bundle), "Case \(index) must not start a native updater")
            }
        }
    }
}
