import ZerusIOSServices
import XCTest
@testable import ZerusNative

final class NativeDriveFilesTests: XCTestCase {
    @MainActor
    func testDrivePaginationPathReadsAndPrivateFolderMappingsProducePortableCopiesWithoutChangingOriginalNotes() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let fixture = DriveFileFixture(), api = NativeDriveFiles(accountID: "account-id", send: fixture.respond)
        let folders = try await api.children("root-id")
        XCTAssertEqual(folders.map(\.id), ["folder-id", "last-id"])
        XCTAssertEqual(fixture.commands.prefix(2).map { $0.query?["pageToken"] }, [nil, "next-page"])
        let selection = NativeDriveFolder(accountID: "account-id", email: "tester@example.invalid", folderID: "root-id", name: "Documents")
        let (bytes, file) = try await api.download(selection, path: "Réseau's/Report.bin")
        XCTAssertEqual(bytes, Data([0, 255, 1, 2, 3, 4, 5, 6])); XCTAssertEqual(file.name, "Report.bin")
        XCTAssertTrue(fixture.commands.contains { $0.query?["q"] == "'root-id' in parents and trashed = false and name = 'Réseau\\'s'" })
        XCTAssertTrue(fixture.commands.allSatisfy { $0.method == "GET" && $0.accountId == "account-id" && $0.operation == "request" && $0.body == nil })
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = temporary.appendingPathComponent("Vault"), local = temporary.appendingPathComponent("Originals")
        for url in [root, local] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let original = Data("---\r\nforeign: 'Keep: exact'\r\n---\r\n# Original\r\n\r\nWriting stays here.\r\n".utf8)
        let originalURL = root.appendingPathComponent("Original.md"); try original.write(to: originalURL)
        let mappings = NativeFileMappings(root: root), privateFile = await mappings.file
        defer { try? FileManager.default.removeItem(at: privateFile.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: privateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["version": 1, "bookmarks": [String: String](), "foreign": ["untouched": true]]).write(to: privateFile)
        try await mappings.mapLocation("other-location", url: local)
        try await mappings.mapDriveLocation("reports", selection: selection)
        let reopened = NativeFileMappings(root: root), restored = try await reopened.driveFolder("reports")
        XCTAssertEqual(restored, selection)
        let label = try await reopened.locationLabel("reports"); XCTAssertEqual(label, "Google Drive · Documents")
        let privateValue = try JSONSerialization.jsonObject(with: Data(contentsOf: privateFile)) as! [String: Any]
        XCTAssertEqual((privateValue["foreign"] as? [String: Bool])?["untouched"], true)
        XCTAssertNotNil((privateValue["bookmarks"] as? [String: String])?["location:other-location"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Original.md"], "Drive mappings must stay outside the shared vault")
        var lease: NativeFileLease? = try await mappings.downloaded(bytes, name: file.name)
        let downloadURL = lease!.url, directory = try XCTUnwrap(lease!.temporaryDirectory)
        XCTAssertEqual(try lease!.readForCopy(), bytes)
        let vault = VaultStore(); await vault.open(root)
        let copy = try await vault.saveFileHub(source: lease, storage: .copy, title: "Portable report", workspace: vault.workspaceID)
        let copyPath = try XCTUnwrap(copy.fileHub?.path)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(copyPath)), bytes)
        XCTAssertFalse(copy.content.contains(directory.path)); XCTAssertFalse(copy.content.contains("account-id"))
        do { _ = try await vault.saveFileHub(source: lease, storage: .external, title: "Unsafe temporary connection", workspace: vault.workspaceID); XCTFail("A preview must not become an original connection to a disposable file") }
        catch { XCTAssertTrue(error.localizedDescription.contains("downloaded preview")) }
        weak var released = lease
        let sharing = NativeFileShare.controller(for: lease!)
        lease = nil
        XCTAssertNotNil(released); XCTAssertEqual(try Data(contentsOf: downloadURL), bytes, "A share extension owns its snapshot after the originating view releases it")
        sharing.completionWithItemsHandler?(nil, false, nil, nil)
        XCTAssertNil(released); XCTAssertFalse(FileManager.default.fileExists(atPath: downloadURL.path))
        try await reopened.mapLocation("reports", url: local)
        let removedDrive = try await reopened.driveFolder("reports"); XCTAssertNil(removedDrive)
        let localLabel = try await reopened.locationLabel("reports"); XCTAssertEqual(localLabel, "Originals")
        try await reopened.mapDriveLocation("reports", selection: selection)
        let replaced = try JSONSerialization.jsonObject(with: Data(contentsOf: privateFile)) as! [String: Any]
        XCTAssertNil((replaced["bookmarks"] as? [String: String])?["location:reports"])
        try await reopened.mapLocation("reports", url: nil)
        let disconnected = try await reopened.locationLabel("reports"); XCTAssertNil(disconnected)
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
    }

    @MainActor
    func testDriveReadsRejectAmbiguousUnsupportedChangedAndIncompleteResultsBeforePublishingAFile() async throws {
        let selection = NativeDriveFolder(accountID: "account-id", email: "tester@example.invalid", folderID: "root-id", name: "Documents")
        for (mode, expected) in [("duplicate", "duplicate"), ("shortcut", "ordinary"), ("large", "50 MB"), ("changed-file", "changed while downloading"), ("moved-folder", "folders changed"), ("wrong-root", "changed during lookup"), ("invalid-body", "unreadable")] {
            let fixture = DriveFileFixture(mode: mode), api = NativeDriveFiles(accountID: "account-id", send: fixture.respond)
            do { _ = try await api.download(selection, path: "Réseau's/Report.bin"); XCTFail("Accepted " + mode) }
            catch { XCTAssertTrue(error.localizedDescription.contains(expected), mode + ": " + error.localizedDescription) }
            if ["duplicate", "shortcut", "large", "invalid-body"].contains(mode) { XCTAssertFalse(fixture.commands.contains { $0.query?["alt"] == "media" }) }
        }
        for (mode, expected) in [("repeated-page", "repeated"), ("incomplete", "part of this folder")] {
            let fixture = DriveFileFixture(mode: mode), api = NativeDriveFiles(accountID: "account-id", send: fixture.respond)
            do { _ = try await api.children("root-id"); XCTFail("Accepted " + mode) }
            catch { XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription) }
        }
        let fixture = DriveFileFixture(), api = NativeDriveFiles(accountID: "account-id", send: fixture.respond)
        for path in ["../Secret.bin", "/Outside.bin", "Réseau's/../Secret.bin", "Réseau's\\Report.bin"] {
            do { _ = try await api.download(selection, path: path); XCTFail("Accepted outside path") } catch { XCTAssertTrue(error.localizedDescription.contains("invalid")) }
        }
        XCTAssertTrue(fixture.commands.isEmpty, "Invalid paths must fail before contacting Drive")
        let waiting = DriveFileFixture(mode: "waiting"), pending = NativeDriveFiles(accountID: "account-id", send: waiting.respond)
        let read = Task { try await pending.download(selection, path: "Réseau's/Report.bin") }
        await fulfillment(of: [waiting.mediaRequested], timeout: 3); read.cancel()
        do { _ = try await read.value; XCTFail("Cancelled download exposed bytes") } catch { XCTAssertTrue(error is CancellationError) }
    }
}

@MainActor
private final class DriveFileFixture {
    let mode: String
    var commands: [GoogleDriveCommand] = []
    var mediaDelivered = false
    let mediaRequested = XCTestExpectation(description: "The Drive reader requested the actual media after resolving its path")
    init(mode: String = "normal") { self.mode = mode }
    private var root: [String: Any] { ["id": mode == "wrong-root" ? "other-root" : "root-id", "name": "Documents", "mimeType": "application/vnd.google-apps.folder", "parents": ["outside-id"], "version": "10"] }
    private var folder: [String: Any] { ["id": "folder-id", "name": "Réseau's", "mimeType": "application/vnd.google-apps.folder", "parents": mode == "moved-folder" && mediaDelivered ? ["outside-id"] : ["root-id"], "version": "11"] }
    private var document: [String: Any] { ["id": "document-id", "name": "Report.bin", "mimeType": mode == "shortcut" ? "application/vnd.google-apps.shortcut" : "application/octet-stream", "parents": ["folder-id"], "version": mode == "changed-file" && mediaDelivered ? "13" : "12", "size": mode == "large" ? "52428801" : "8"] }
    func respond(_ command: GoogleDriveCommand) async throws -> [String: Any] {
        commands.append(command)
        if mode == "invalid-body" { return ["status": 200, "body": "not-base64"] }
        if command.query?["alt"] == "media" {
            mediaRequested.fulfill()
            if mode == "waiting" { try await Task.sleep(for: .seconds(60)) }
            mediaDelivered = true
            return ["status": 200, "body": Data([0, 255, 1, 2, 3, 4, 5, 6]).base64EncodedString()]
        }
        let value: [String: Any]
        switch command.path {
        case "/drive/v3/files/root-id": value = root
        case "/drive/v3/files/folder-id": value = folder
        case "/drive/v3/files/document-id": value = document
        case "/drive/v3/files":
            if command.query?["q"]?.hasPrefix("'folder-id'") == true {
                var rows = [document]
                if mode == "duplicate" { var copy = document; copy["id"] = "duplicate-id"; rows.append(copy) }
                value = ["files": rows]
            } else if command.query?["q"]?.contains("and name =") == true { value = ["files": [folder]] }
            else if command.query?["pageToken"] == nil { value = ["files": [folder], "nextPageToken": "next-page", "incompleteSearch": mode == "incomplete"] }
            else { value = mode == "repeated-page" ? ["files": [folder], "nextPageToken": "next-page"] : ["files": [folder, ["id": "last-id", "name": "Last", "mimeType": "application/vnd.google-apps.folder", "parents": ["root-id"]]]] }
        default: throw VaultFailure(message: "Unexpected Drive fixture endpoint")
        }
        return ["status": 200, "body": try JSONSerialization.data(withJSONObject: value).base64EncodedString()]
    }
}
