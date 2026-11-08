import ZerusIOSServices
import XCTest
@testable import ZerusNative

@MainActor
final class NativeDriveVaultTests: XCTestCase {
    private let selection = NativeDriveFolder(accountID: "account-id", email: "tester@example.invalid", folderID: "root-id", name: "Remote vault")
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NativeDriveOwner-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func backend(_ provider: DriveVaultFixture, directory: URL) throws -> NativeDriveVault {
        let api = NativeDriveFiles(accountID: "account-id", send: provider.respond)
        return try NativeDriveVault(selection: selection, directory: directory) { api }
    }
    func testNativeDriveVaultOpensEditsMovesRefreshesAndReopensOfflineWithExactForeignFiles() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let provider = DriveVaultFixture(), directory = try directory(), connection = try backend(provider, directory: directory)
        let originalForeign = try provider.bytes(".zerus/foreign.json"), asset = try provider.bytes("assets/plot.bin")
        let store = VaultStore(); let opened = await store.openDrive(connection); XCTAssertTrue(opened)
        XCTAssertEqual(try Data(contentsOf: connection.root.appendingPathComponent("Note.md")), provider.original)
        XCTAssertEqual(try Data(contentsOf: connection.root.appendingPathComponent(".zerus/foreign.json")), originalForeign)
        let record = try XCTUnwrap(store.savedVaults.first { $0.id == store.activeVaultID }); XCTAssertEqual(record.drive, selection); XCTAssertTrue(record.locationDescription.contains("Google Drive"))
        let note = try XCTUnwrap(store.notes.first { $0.path == "Note.md" }), session = try XCTUnwrap(store.session(for: note))
        XCTAssertEqual(note.modified, Date(timeIntervalSince1970: 1_700_000_001), "Native recent sorting must use the Drive modified time rather than download time")
        XCTAssertEqual(note.created, Date(timeIntervalSince1970: 1_699_000_000))
        session.updateBody("# Original\n\nWritten **on iPhone**.\n"); await session.save(); await store.syncDrive()
        XCTAssertEqual(try provider.bytes("Note.md"), Data("---\r\nzerus-id: primary-id\r\nforeign: 'Keep: exact'\r\n---\r\n# Original\n\nWritten **on iPhone**.\n".utf8))
        XCTAssertEqual(try provider.bytes(".zerus/foreign.json"), originalForeign)
        let moved = await store.move(session.document, folder: "Projects"); XCTAssertTrue(moved); await store.syncDrive()
        XCTAssertEqual(try provider.id("Projects/Note.md"), "note-id", "Moving a native note must keep its existing Drive file identity")
        XCTAssertFalse(provider.exists("Note.md"))
        let outside = Data("---\r\nzerus-id: primary-id\r\nforeign: 'Keep: exact'\r\n---\r\n# Original\r\n\r\nChanged on the desktop.\r\n".utf8)
        try provider.overwrite("Projects/Note.md", bytes: outside); await store.refresh()
        let loaded = try XCTUnwrap(store.notes.first { $0.path == "Projects/Note.md" }); XCTAssertEqual(loaded.content, String(decoding: outside, as: UTF8.self))
        let editor = try XCTUnwrap(store.session(for: loaded)); editor.updateBody("# Original\n\nOffline iPhone writing.\n"); await editor.save()
        provider.offline = true; await store.syncDrive()
        XCTAssertTrue(store.driveStatus?.contains("Saved on this iPhone") == true)
        let local = try Data(contentsOf: connection.root.appendingPathComponent("Projects/Note.md")); XCTAssertTrue(String(decoding: local, as: UTF8.self).contains("Offline iPhone writing."))
        let requests = provider.commands.count
        let restored = try backend(provider, directory: directory); try await restored.prepare()
        XCTAssertEqual(provider.commands.count, requests, "A complete working copy must reopen without a network request")
        let reopened = VaultStore(); let didReopen = await reopened.openDrive(restored); XCTAssertTrue(didReopen)
        XCTAssertEqual(reopened.notes.first { $0.path == "Projects/Note.md" }?.content, String(decoding: local, as: UTF8.self))
        XCTAssertEqual(try provider.bytes("Projects/Note.md"), outside); XCTAssertEqual(try provider.bytes("assets/plot.bin"), asset)
        XCTAssertEqual(try provider.bytes(".zerus/foreign.json"), originalForeign)
    }
    func testLostAcknowledgementsResumeByIdentityAndBytesWhileConflictsAndStaleReviewsKeepBothVersions() async throws {
        let provider = DriveVaultFixture(stableID: false), directory = try directory(), connection = try backend(provider, directory: directory)
        try await connection.prepare()
        let created = Data("# New\n\nCafé and literal **writing**.\n".utf8)
        try await connection.io.write("Café 'draft'.md", data: created, expected: nil)
        provider.dropCreate = "Café 'draft'.md"
        do { _ = try await connection.sync(); XCTFail("Lost create acknowledgement should keep pending work") } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        let identity = try provider.id("Café 'draft'.md"), restored = try backend(provider, directory: directory)
        try await restored.prepare()
        let continuedCreate = Data("# New\n\nContinued writing after the connection dropped.\n".utf8)
        try await restored.io.write("Café 'draft'.md", data: continuedCreate, expected: created)
        _ = try await restored.sync()
        XCTAssertEqual(try provider.bytes("Café 'draft'.md"), continuedCreate)
        XCTAssertEqual(try provider.id("Café 'draft'.md"), identity); XCTAssertEqual(provider.creates.filter { $0 == "Café 'draft'.md" }.count, 1)
        try await restored.io.applyTransaction([.init(path: "Café 'draft'.md", before: continuedCreate, after: nil), .init(path: "Café moved.md", before: nil, after: continuedCreate)])
        provider.dropMove = "Café moved.md"
        do { _ = try await restored.sync(); XCTFail("Lost move acknowledgement should keep its original identity record") } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        let moved = try backend(provider, directory: directory); try await moved.prepare(); _ = try await moved.sync()
        XCTAssertEqual(try provider.id("Café moved.md"), identity); XCTAssertEqual(provider.moves.filter { $0 == identity }.count, 1)
        var own = Data("# Original\n\nFirst iPhone update.\n".utf8)
        try await restored.io.write("Note.md", data: own, expected: provider.original); provider.dropPut = "Note.md"
        do { _ = try await restored.sync(); XCTFail("Lost update acknowledgement should keep pending work") } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        let next = try backend(provider, directory: directory); try await next.prepare()
        let continuedUpdate = Data("# Original\n\nMore writing before the lost upload was acknowledged.\n".utf8)
        try await next.io.write("Note.md", data: continuedUpdate, expected: own)
        own = continuedUpdate; _ = try await next.sync()
        XCTAssertEqual(provider.puts.filter { $0 == "note-id" }.count, 2); XCTAssertEqual(try provider.bytes("Note.md"), own)
        let metadataEdit = Data("# Original\n\nWriting after a Drive metadata change.\n".utf8)
        try await next.io.write("Note.md", data: metadataEdit, expected: own)
        provider.entries["note-id"]!.version += 1
        _ = try await next.sync()
        XCTAssertEqual(try provider.bytes("Note.md"), metadataEdit, "An unchanged remote body must not conflict with local writing after a metadata-only version change")
        own = metadataEdit
        let phone = Data("# Original\n\nPending iPhone version.\n".utf8), desktop = Data("# Original\n\nIndependent desktop version.\n".utf8)
        try await next.io.write("Note.md", data: phone, expected: own); try provider.overwrite("Note.md", bytes: desktop)
        do { _ = try await next.sync(); XCTFail("Both writers require review") } catch { XCTAssertTrue(error is NativeDriveConflictRequired) }
        let review = try XCTUnwrap(next.review); XCTAssertEqual(review.files.first?.local, phone); XCTAssertEqual(review.files.first?.remote, desktop)
        let newer = Data("# Original\n\nNewer desktop version.\n".utf8); try provider.overwrite("Note.md", bytes: newer)
        do { try await next.resolve(review, keepLocal: ["Note.md"]); XCTFail("An obsolete review must not change either copy") } catch { XCTAssertTrue(error.localizedDescription.contains("changed")) }
        let preserved = try await next.io.read("Note.md"); XCTAssertEqual(preserved, phone); XCTAssertEqual(try provider.bytes("Note.md"), newer)
        do { _ = try await next.sync(); XCTFail("Fresh conflicting versions still require review") } catch { XCTAssertTrue(error is NativeDriveConflictRequired) }
        try await next.resolve(try XCTUnwrap(next.review), keepLocal: ["Note.md"]); _ = try await next.sync()
        XCTAssertEqual(try provider.bytes("Note.md"), phone)
        let finalDesktop = Data("# Original\n\nChoose this Drive copy.\n".utf8)
        try await next.io.write("Note.md", data: Data("# Local choice\n".utf8), expected: phone); try provider.overwrite("Note.md", bytes: finalDesktop)
        do { _ = try await next.sync(); XCTFail("Both changed again") } catch { XCTAssertTrue(error is NativeDriveConflictRequired) }
        try await next.resolve(try XCTUnwrap(next.review), keepLocal: []); _ = try await next.sync()
        let chosen = try await next.io.read("Note.md"); XCTAssertEqual(chosen, finalDesktop)
        try await next.io.applyTransaction([.init(path: "Note.md", before: finalDesktop, after: nil)]); _ = try await next.sync(); _ = try await next.sync()
        XCTAssertFalse(provider.exists("Note.md")); XCTAssertEqual(provider.trashes.filter { $0 == "note-id" }.count, 1)
        XCTAssertEqual(try provider.bytes("Café moved.md"), continuedCreate)
        let removedBeforeRetry = Data("# Remove after interrupted upload\n".utf8)
        try await next.io.write("Removed.md", data: removedBeforeRetry, expected: nil); provider.dropCreate = "Removed.md"
        do { _ = try await next.sync(); XCTFail("Lost create must retain its recovery record") } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        let removedID = try provider.id("Removed.md")
        try await next.io.applyTransaction([.init(path: "Removed.md", before: removedBeforeRetry, after: nil)])
        let reopened = try backend(provider, directory: directory); try await reopened.prepare(); _ = try await reopened.sync()
        XCTAssertFalse(provider.exists("Removed.md")); XCTAssertEqual(provider.trashes.filter { $0 == removedID }.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.root.appendingPathComponent("Removed.md").path))
        let disputed = Data("# Original submitted draft\n".utf8), disputedLocal = Data("# Continued local draft\n".utf8), disputedRemote = Data("# Independent Drive writing\n".utf8)
        try await reopened.io.write("Disputed.md", data: disputed, expected: nil); provider.dropCreate = "Disputed.md"
        do { _ = try await reopened.sync(); XCTFail("Create response is lost") } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        try provider.overwrite("Disputed.md", bytes: disputedRemote)
        try await reopened.io.write("Disputed.md", data: disputedLocal, expected: disputed)
        do { _ = try await reopened.sync(); XCTFail("A pending identity must not authorize overwriting different Drive bytes") } catch { XCTAssertTrue(error is NativeDriveConflictRequired) }
        let disputedReview = try XCTUnwrap(reopened.review)
        XCTAssertEqual(disputedReview.files.first?.local, disputedLocal); XCTAssertEqual(disputedReview.files.first?.remote, disputedRemote)
        try await reopened.resolve(disputedReview, keepLocal: [])
        let afterReview = try backend(provider, directory: directory); try await afterReview.prepare(); _ = try await afterReview.sync()
        let accepted = try await afterReview.io.read("Disputed.md")
        XCTAssertEqual(accepted, disputedRemote); XCTAssertEqual(try provider.bytes("Disputed.md"), disputedRemote)
    }
    func testReviewedDriveNoteAndHistoryKeepExactChosenBytesDatesAndPriorDraftsAcrossOfflineReopen() async throws {
        let provider = DriveVaultFixture(), directory = try directory(), connection = try backend(provider, directory: directory)
        try await connection.prepare()
        let first = Data("---\r\nzerus-id: primary-id\r\nforeign: 'Keep: exact'\r\n---\r\n# Original\r\n\r\nFirst saved phone draft.\r\n".utf8)
        try await connection.io.write("Note.md", data: first, expected: provider.original); _ = try await connection.sync()
        let initialHistory = try await connection.io.historySnapshot(notePath: "Note.md")
        let historyPath = try XCTUnwrap(initialHistory.versions.last?.path), historyOriginal = try XCTUnwrap(initialHistory.records[historyPath])
        var localRecord = try XCTUnwrap(JSONSerialization.jsonObject(with: historyOriginal) as? [String: Any])
        localRecord["label"] = "Phone label"; localRecord["kept"] = true
        let localHistory = try JSONSerialization.data(withJSONObject: localRecord)
        try await connection.io.write(historyPath, data: localHistory, expected: historyOriginal)
        var remoteRecord = localRecord; remoteRecord["label"] = "Chosen Drive label"; remoteRecord["foreign"] = ["keep": "exact JSON formatting"]
        let remoteHistory = Data((String(decoding: try JSONSerialization.data(withJSONObject: remoteRecord, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self).replacingOccurrences(of: "\n", with: "\r\n") + "\r\n").utf8)
        try provider.overwrite(historyPath, bytes: remoteHistory)
        let phone = Data("---\r\nzerus-id: primary-id\r\nforeign: 'Keep: exact'\r\n---\r\n# Original\r\n\r\nKeep this discarded phone draft recoverable.\r\n".utf8)
        let remote = Data("---\r\nzerus-id: primary-id\r\nforeign: 'Keep: exact'\r\n---\r\n# Original\r\n\r\nChoose these **exact** Drive bytes.\r\n".utf8)
        try await connection.io.write("Note.md", data: phone, expected: first)
        let beforeReviewHistory = try await connection.io.historySnapshot(notePath: "Note.md")
        try provider.overwrite("Note.md", bytes: remote); provider.entries["note-id"]!.version = 9
        do { _ = try await connection.sync(); XCTFail("Both the note and history metadata changed independently") } catch { XCTAssertTrue(error is NativeDriveConflictRequired) }
        let review = try XCTUnwrap(connection.review)
        XCTAssertEqual(Set(review.files.map(\.path)), ["Note.md", historyPath])
        try await connection.resolve(review, keepLocal: [])
        let chosenNote = try await connection.io.read("Note.md"), chosenHistory = try await connection.io.read(historyPath)
        XCTAssertEqual(chosenNote, remote); XCTAssertEqual(chosenHistory, remoteHistory)
        for (path, bytes) in beforeReviewHistory.records where path != historyPath {
            let retained = try await connection.io.read(path); XCTAssertEqual(retained, bytes)
        }
        provider.offline = true
        let reopened = try backend(provider, directory: directory); try await reopened.prepare()
        let scanned = try await reopened.io.scan(), note = try XCTUnwrap(scanned.notes.first { $0.path == "Note.md" })
        XCTAssertEqual(note.content, String(decoding: remote, as: UTF8.self))
        XCTAssertEqual(note.modified, Date(timeIntervalSince1970: 1_700_000_009), "Choosing Drive must retain the reviewed server date across offline reopen")
        XCTAssertEqual(note.created, Date(timeIntervalSince1970: 1_699_000_000))
        let recovered = try await reopened.io.historySnapshot(notePath: "Note.md")
        XCTAssertTrue(recovered.versions.contains { $0.content == String(decoding: phone, as: UTF8.self) }, "The previously saved phone draft must remain recoverable")
        XCTAssertEqual(try provider.bytes("Note.md"), remote); XCTAssertEqual(try provider.bytes(historyPath), remoteHistory)
    }
    func testPrivateDriveCacheRestoresItsAssociationWithoutAReadableRegistryAndRejectsMisboundRecords() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let rootID = "restore-" + UUID().uuidString
        let selection = NativeDriveFolder(accountID: "account-id", email: "tester@example.invalid", folderID: rootID, name: "Recovered Drive vault")
        let provider = DriveVaultFixture(rootID: rootID), directory = NativeDriveVault.directory(for: selection)
        guard !FileManager.default.fileExists(atPath: directory.path) else { XCTFail("The isolated cache identity must be unused"); return }
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let api = NativeDriveFiles(accountID: selection.accountID, send: provider.respond)
        let connection = try NativeDriveVault(selection: selection, directory: directory) { api }
        let original = VaultStore(); let opened = await original.openDrive(connection); XCTAssertTrue(opened)
        let savedID = try XCTUnwrap(original.activeVaultID)
        let registered = try XCTUnwrap(UserDefaults.standard.data(forKey: NativeVaultRegistry.key))
        let bookmark = try connection.root.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let stateFile = directory.appendingPathComponent("state.json"), stateBytes = try Data(contentsOf: stateFile)
        provider.offline = true
        let unavailableRegistries: [Data?] = [nil, Data("not readable JSON".utf8), Data(#"{"version":91,"entries":[],"foreign":"preserve"}"#.utf8)]
        for (index, registry) in unavailableRegistries.enumerated() {
            if let registry { UserDefaults.standard.set(registry, forKey: NativeVaultRegistry.key) } else { UserDefaults.standard.removeObject(forKey: NativeVaultRegistry.key) }
            UserDefaults.standard.set(bookmark, forKey: "zerus.native.vault.bookmark")
            let restarted = VaultStore(); await restarted.restore()
            XCTAssertEqual(restarted.driveSelection, selection, "The private working copy must not become an ordinary Files vault")
            XCTAssertEqual(restarted.vaultName, selection.name)
            XCTAssertEqual(restarted.root?.resolvingSymlinksInPath(), connection.root.resolvingSymlinksInPath())
            let session = try XCTUnwrap(restarted.session(for: XCTUnwrap(restarted.notes.first { $0.path == "Note.md" })))
            session.updateBody("# Original\n\nOffline after registry recovery \(index).\n"); await session.save(); await restarted.syncDrive()
            XCTAssertTrue(restarted.driveStatus?.hasPrefix("Saved on this iPhone") == true)
            XCTAssertTrue(try String(contentsOf: connection.root.appendingPathComponent("Note.md"), encoding: .utf8).contains("Offline after registry recovery \(index)."))
            if let registry { XCTAssertEqual(UserDefaults.standard.data(forKey: NativeVaultRegistry.key), registry); XCTAssertNotNil(restarted.savedVaultIssue) }
            else { XCTAssertEqual(try NativeVaultRegistry().entries.first { $0.id == restarted.activeVaultID }?.drive, selection) }
        }
        var oldList = try XCTUnwrap(JSONSerialization.jsonObject(with: registered) as? [String: Any])
        var entries = try XCTUnwrap(oldList["entries"] as? [[String: Any]])
        let row = try XCTUnwrap(entries.firstIndex { $0["id"] as? String == savedID.uuidString }); entries[row].removeValue(forKey: "drive"); oldList["entries"] = entries
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: oldList), forKey: NativeVaultRegistry.key)
        let fromList = VaultStore(); await fromList.openSavedVault(savedID)
        XCTAssertEqual(fromList.activeVaultID, savedID); XCTAssertEqual(fromList.driveSelection, selection)
        let direct = VaultStore(); await direct.open(connection.root)
        XCTAssertEqual(direct.driveSelection, selection, "A direct folder open must retain the private Drive association too")
        // A copied ledger in an ordinary Files folder conveys no Drive authority.
        let ordinaryParent = try self.directory(), ordinaryRoot = ordinaryParent.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: ordinaryRoot, withIntermediateDirectories: true)
        try stateBytes.write(to: ordinaryParent.appendingPathComponent("state.json"))
        let ordinaryBytes = Data("# Ordinary Files folder\n".utf8); try ordinaryBytes.write(to: ordinaryRoot.appendingPathComponent("Note.md"))
        UserDefaults.standard.removeObject(forKey: NativeVaultRegistry.key)
        UserDefaults.standard.set(try ordinaryRoot.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "zerus.native.vault.bookmark")
        let files = VaultStore(); await files.restore()
        XCTAssertNil(files.driveSelection); XCTAssertEqual(files.notes.first?.content, String(decoding: ordinaryBytes, as: UTF8.self))
        // Malformed or differently bound private records must not fall back to Files.
        var mismatched = try XCTUnwrap(JSONSerialization.jsonObject(with: stateBytes) as? [String: Any])
        var wrongSelection = try XCTUnwrap(mismatched["selection"] as? [String: Any]); wrongSelection["folderID"] = "another-folder"; mismatched["selection"] = wrongSelection
        let cachedNote = try Data(contentsOf: connection.root.appendingPathComponent("Note.md"))
        for damaged in [Data("unreadable private record".utf8), try JSONSerialization.data(withJSONObject: mismatched)] {
            try damaged.write(to: stateFile, options: .atomic)
            UserDefaults.standard.removeObject(forKey: NativeVaultRegistry.key); UserDefaults.standard.set(bookmark, forKey: "zerus.native.vault.bookmark")
            let refused = VaultStore(); await refused.restore()
            XCTAssertNil(refused.root); XCTAssertNotNil(refused.restorationIssue)
            XCTAssertEqual(try Data(contentsOf: stateFile), damaged); XCTAssertEqual(try Data(contentsOf: connection.root.appendingPathComponent("Note.md")), cachedNote)
        }
        try stateBytes.write(to: stateFile, options: .atomic)
        let held = directory.appendingPathComponent("HeldVault", isDirectory: true)
        try FileManager.default.moveItem(at: connection.root, to: held)
        defer { try? FileManager.default.removeItem(at: connection.root); try? FileManager.default.moveItem(at: held, to: connection.root) }
        try FileManager.default.createSymbolicLink(at: connection.root, withDestinationURL: ordinaryRoot)
        UserDefaults.standard.removeObject(forKey: NativeVaultRegistry.key); UserDefaults.standard.set(bookmark, forKey: "zerus.native.vault.bookmark")
        let redirected = VaultStore(); await redirected.open(connection.root)
        XCTAssertNil(redirected.root); XCTAssertNotNil(redirected.restorationIssue)
        XCTAssertEqual(try Data(contentsOf: ordinaryRoot.appendingPathComponent("Note.md")), ordinaryBytes)
    }
    func testCancelledCachedDriveOpeningKeepsTheCurrentFilesVaultAndItsSavedAccess() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let local = try directory(), provider = DriveVaultFixture(), connection = try backend(provider, directory: directory())
        try Data("# Keep this Files vault\n".utf8).write(to: local.appendingPathComponent("Local.md"))
        try await connection.prepare()
        let store = VaultStore(); await store.open(local)
        let registry = UserDefaults.standard.data(forKey: NativeVaultRegistry.key), bookmark = UserDefaults.standard.data(forKey: "zerus.native.vault.bookmark")
        let opening = Task { await store.openDrive(connection) }; opening.cancel()
        let opened = await opening.value
        XCTAssertFalse(opened); XCTAssertEqual(store.root, local); XCTAssertNil(store.error)
        XCTAssertEqual(UserDefaults.standard.data(forKey: NativeVaultRegistry.key), registry)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "zerus.native.vault.bookmark"), bookmark)
        XCTAssertEqual(try Data(contentsOf: local.appendingPathComponent("Local.md")), Data("# Keep this Files vault\n".utf8))
    }
    func testVersionAndAncestorChangesStopWritesAndEquivalentPathsStopInitialMaterialization() async throws {
        for ancestor in [false, true] {
            let provider = DriveVaultFixture(stableID: false, nested: ancestor), connection = try backend(provider, directory: directory())
            try await connection.prepare()
            let path = ancestor ? "Nested/Note.md" : "Note.md", own = Data("# iPhone\n".utf8)
            try await connection.io.write(path, data: own, expected: provider.original)
            provider.beforeLock = {
                if ancestor { provider.entries["nested-id"]!.parent = "outside-id" }
                else { provider.entries["note-id"]!.data = Data("# Outside change\n".utf8); provider.entries["note-id"]!.version += 1 }
            }
            do { _ = try await connection.sync(); XCTFail("A changed lock/scope must stop the mutation") } catch { XCTAssertTrue(error.localizedDescription.contains(ancestor ? "outside" : "changed"), error.localizedDescription) }
            XCTAssertTrue(provider.puts.isEmpty); let kept = try await connection.io.read(path); XCTAssertEqual(kept, own)
        }
        let provider = DriveVaultFixture(), directory = try directory()
        provider.entries["duplicate-id"] = .init(id: "duplicate-id", name: "note.md", parent: "root-id", data: Data("# Other\n".utf8))
        let connection = try backend(provider, directory: directory)
        do { try await connection.prepare(); XCTFail("Case-equivalent Drive paths cannot be materialized on this device") } catch { XCTAssertTrue(error.localizedDescription.contains("equivalent")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: connection.root.path)); XCTAssertTrue(provider.creates.isEmpty); XCTAssertTrue(provider.puts.isEmpty)
    }
}

@MainActor
private final class DriveVaultFixture {
    struct Entry {
        var id: String; var name: String; var parent: String?; var data: Data
        var folder = false; var version = 1; var trashed = false
        var json: [String: Any] { ["id": id, "name": name, "mimeType": folder ? "application/vnd.google-apps.folder" : "application/octet-stream", "parents": parent.map { [$0] } ?? [], "version": String(version), "size": String(data.count), "trashed": trashed, "modifiedTime": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000 + Double(version))), "createdTime": "2023-11-03T08:26:40Z", "capabilities": ["canEdit": true, "canAddChildren": folder]] }
        var v2: [String: Any] { ["id": id, "title": name, "mimeType": folder ? "application/vnd.google-apps.folder" : "application/octet-stream", "parents": parent.map { [["id": $0]] } ?? [], "version": String(version), "etag": "etag-" + String(version), "labels": ["trashed": trashed]] }
    }
    let original: Data
    private let rootID: String
    var entries: [String: Entry] = [:]
    var commands: [GoogleDriveCommand] = [], creates: [String] = [], puts: [String] = [], trashes: [String] = [], moves: [String] = []
    var offline = false, dropCreate: String?, dropPut: String?, dropMove: String?, beforeLock: (() -> Void)?
    private var generated = 0
    init(stableID: Bool = true, nested: Bool = false, rootID: String = "root-id") {
        self.rootID = rootID
        original = Data((stableID ? "---\r\nzerus-id: primary-id\r\nforeign: 'Keep: exact'\r\n---\r\n# Original\r\n\r\nOriginal writing.\r\n" : "# Original\n").utf8)
        entries["root-id"] = .init(id: "root-id", name: "Remote vault", parent: nil, data: Data(), folder: true)
        entries["outside-id"] = .init(id: "outside-id", name: "Outside", parent: nil, data: Data(), folder: true)
        entries["nested-id"] = .init(id: "nested-id", name: "Nested", parent: "root-id", data: Data(), folder: true)
        entries["note-id"] = .init(id: "note-id", name: "Note.md", parent: nested ? "nested-id" : "root-id", data: original)
        entries["assets-id"] = .init(id: "assets-id", name: "assets", parent: "root-id", data: Data(), folder: true)
        entries["asset-id"] = .init(id: "asset-id", name: "plot.bin", parent: "assets-id", data: Data([0, 255, 1, 42]))
        entries["metadata-id"] = .init(id: "metadata-id", name: ".zerus", parent: "root-id", data: Data(), folder: true)
        entries["foreign-id"] = .init(id: "foreign-id", name: "foreign.json", parent: "metadata-id", data: Data("{\"foreign\": [true, 42], \"keep\": \"exact bytes\"}\r\n".utf8))
        if stableID {
            entries["revisions-id"] = .init(id: "revisions-id", name: "revisions", parent: "metadata-id", data: Data(), folder: true)
            entries["snapshot-id"] = .init(id: "snapshot-id", name: "snapshot.md", parent: "revisions-id", data: original)
        }
        if rootID != "root-id" {
            var root = entries.removeValue(forKey: "root-id")!; root.id = rootID; entries[rootID] = root
            for id in entries.keys where entries[id]?.parent == "root-id" { entries[id]!.parent = rootID }
        }
    }
    private func path(_ id: String, seen: Set<String> = []) -> String? {
        guard id != rootID, !seen.contains(id), let entry = entries[id], !entry.trashed, let parent = entry.parent else { return nil }
        if parent == rootID { return entry.name }
        return path(parent, seen: seen.union([id])).map { $0 + "/" + entry.name }
    }
    func id(_ path: String) throws -> String { try XCTUnwrap(entries.keys.first { self.path($0) == path }) }
    func bytes(_ path: String) throws -> Data { entries[try id(path)]!.data }
    func exists(_ path: String) -> Bool { entries.keys.contains { self.path($0) == path } }
    func overwrite(_ path: String, bytes: Data) throws { let id = try id(path); entries[id]!.data = bytes; entries[id]!.version += 1 }
    private func json(_ value: Any, status: Int = 200) throws -> [String: Any] { ["status": status, "body": try JSONSerialization.data(withJSONObject: value).base64EncodedString()] }
    func respond(_ command: GoogleDriveCommand) async throws -> [String: Any] {
        commands.append(command); if offline { throw URLError(.notConnectedToInternet) }
        guard command.accountId == "account-id", let endpoint = command.path else { throw VaultFailure(message: "Wrong fixture account") }
        let method = command.method ?? "GET", id = (endpoint as NSString).lastPathComponent
        if endpoint == "/drive/v3/files/generateIds" { generated += 1; return try json(["ids": ["generated-" + String(generated)]]) }
        if method == "GET", endpoint == "/drive/v3/files" {
            let q = command.query?["q"] ?? "", parent = q.split(separator: "'").first.map(String.init) ?? ""
            var items = entries.values.filter { $0.parent == parent && !$0.trashed }
            if let range = q.range(of: " and name = '") { let name = String(q[range.upperBound...].dropLast()).replacingOccurrences(of: "\\'", with: "'").replacingOccurrences(of: "\\\\", with: "\\"); items = items.filter { $0.name == name } }
            return try json(["files": items.sorted { $0.id < $1.id }.map(\.json)])
        }
        if method == "GET", endpoint.hasPrefix("/drive/v2/") { let hook = beforeLock; beforeLock = nil; hook?() }
        if method == "GET" {
            guard let entry = entries[id], !entry.trashed else { return try json(["error": "missing"], status: 404) }
            if command.query?["alt"] == "media" { return ["status": 200, "body": entry.data.base64EncodedString()] }
            return try json(endpoint.hasPrefix("/drive/v2/") ? entry.v2 : entry.json)
        }
        let body = command.body.flatMap { Data(base64Encoded: $0) } ?? Data()
        if method == "POST" {
            let metadata: [String: Any], content: Data
            if endpoint.hasPrefix("/upload/") {
                let boundary = try XCTUnwrap(command.contentType?.components(separatedBy: "boundary=").last)
                let head = try XCTUnwrap(body.range(of: Data("\r\n\r\n".utf8)))
                let metadataEnd = try XCTUnwrap(body.range(of: Data(("\r\n--" + boundary + "\r\n").utf8), in: head.upperBound..<body.endIndex))
                metadata = try JSONSerialization.jsonObject(with: body[head.upperBound..<metadataEnd.lowerBound]) as! [String: Any]
                let mediaHead = try XCTUnwrap(body.range(of: Data("\r\n\r\n".utf8), in: metadataEnd.upperBound..<body.endIndex))
                let suffix = Data(("\r\n--" + boundary + "--\r\n").utf8); XCTAssertTrue(body.suffix(suffix.count) == suffix)
                content = Data(body[mediaHead.upperBound..<(body.endIndex - suffix.count)])
            } else { metadata = try JSONSerialization.jsonObject(with: body) as! [String: Any]; content = Data() }
            let newID = metadata["id"] as! String; if entries[newID] != nil { return try json(["error": "exists"], status: 409) }
            let name = metadata["name"] as! String, parent = (metadata["parents"] as! [String])[0]
            let entry = Entry(id: newID, name: name, parent: parent, data: content, folder: metadata["mimeType"] as? String == "application/vnd.google-apps.folder")
            entries[newID] = entry; creates.append(name)
            if dropCreate == name { dropCreate = nil; throw URLError(.networkConnectionLost) }
            return try json(entry.json)
        }
        guard var entry = entries[id], !entry.trashed else { return try json(["error": "missing"], status: 404) }
        guard command.ifMatch == "etag-" + String(entry.version) else { return try json(["error": "precondition"], status: 412) }
        if method == "PUT" {
            entry.data = body; entry.version += 1; entries[id] = entry; puts.append(id)
            if dropPut == entry.name { dropPut = nil; throw URLError(.networkConnectionLost) }
        } else if method == "PATCH" {
            let value = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            if (value["labels"] as? [String: Bool])?["trashed"] == true { entry.trashed = true; trashes.append(id) }
            if let title = value["title"] as? String { entry.name = title; moves.append(id) }
            if let parent = command.query?["addParents"] { entry.parent = parent }
            entry.version += 1; entries[id] = entry
            if dropMove == entry.name { dropMove = nil; throw URLError(.networkConnectionLost) }
        } else { throw VaultFailure(message: "Unexpected fixture mutation") }
        return try json(entry.v2)
    }
}
