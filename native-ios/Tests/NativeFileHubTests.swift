import XCTest
@testable import ZerusNative

final class NativeFileHubTests: XCTestCase {
    private var temporary: URL!
    private var root: URL { temporary.appendingPathComponent("Vault", isDirectory: true) }
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws {
        for vault in [root, temporary.appendingPathComponent("Other", isDirectory: true)] {
            let directory = await NativeFileMappings(root: vault).file.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        }
        try FileManager.default.removeItem(at: temporary)
    }
    private func source(_ name: String = "Original report.txt", bytes: String = "First document bytes") throws -> URL {
        let url = temporary.appendingPathComponent(name); try Data(bytes.utf8).write(to: url); return url
    }
    private func write(_ path: String, _ value: String) throws {
        let url = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(value.utf8).write(to: url)
    }

    @MainActor
    func testCopyCreatesPortableFileNotesAndDuplicatesMovesTrashRestoreAndDetachKeepOriginalBytes() async throws {
        let file = try source(), original = try Data(contentsOf: file), store = VaultStore(); await store.open(root)
        let origin = store.workspaceID, lease = try await store.selectFile(file, workspace: origin)
        let note = try await store.saveFileHub(source: lease, title: "Report context", workspace: origin)
        let hub = try XCTUnwrap(note.fileHub), path = try XCTUnwrap(hub.path)
        XCTAssertEqual(hub.kind, .vault); XCTAssertTrue(hub.managed); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), original)
        XCTAssertFalse(note.content.contains(temporary.path)); XCTAssertEqual(try Data(contentsOf: file), original)
        let privateFile = await NativeFileMappings(root: root).file
        XCTAssertFalse(FileManager.default.fileExists(atPath: privateFile.path), "A vault copy must not persist access to its original external file")
        let preview = try await store.fileHubLease(note, workspace: origin); XCTAssertEqual(try preview.readForCopy(), original)
        let same = try await store.saveFileHub(source: try await store.selectFile(preview.url, workspace: origin), storage: .external, title: "Duplicate request", workspace: origin)
        XCTAssertEqual(same.path, note.path)
        let session = try XCTUnwrap(store.session(for: note)); session.updateBody("# Report context\n\nMy **formatted** thoughts.\n"); await session.save()
        await store.duplicate(session.document)
        let duplicate = try XCTUnwrap(store.notes.first { $0.title == "Report context copy" })
        XCTAssertEqual(duplicate.fileHub?.path, path); XCTAssertEqual(duplicate.fileHub?.managed, false)
        let moved = await store.move(session.document, folder: "Research")
        XCTAssertTrue(moved)
        let filed = try XCTUnwrap(store.notes.first { $0.path == "Research/Report context.md" })
        XCTAssertEqual(filed.fileHub?.path, path)
        let trashed = await store.move(filed, trash: true); XCTAssertTrue(trashed)
        let deleted = try XCTUnwrap(store.notes.first { $0.trashed && $0.stableID == note.stableID })
        let didRestore = await store.move(deleted, restore: true); XCTAssertTrue(didRestore)
        let restored = try XCTUnwrap(store.notes.first { !$0.trashed && $0.stableID == note.stableID }), restoredSession = try XCTUnwrap(store.session(for: restored))
        let detached = try await store.saveFileHub(session: restoredSession, original: restored.fileHub, source: nil, detach: true, workspace: origin)
        XCTAssertNil(detached.fileHub); XCTAssertTrue(detached.content.contains("My **formatted** thoughts."))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), original); XCTAssertEqual(try Data(contentsOf: file), original)
        let document = try await VaultFiles(root: root).clipboardFragment(hub.portableBody("# Copy\n"), notePath: note.path)
        XCTAssertEqual(document.resources.count, 1); XCTAssertEqual(document.resources.first?.bytes, original)
        let markdownSource = try source("Opaque document.md", bytes: "# A Markdown document treated as a file\n")
        let markdownNote = try await store.saveFileHub(source: try await store.selectFile(markdownSource, workspace: origin), title: "Opaque document", workspace: origin)
        let markdownHub = try XCTUnwrap(markdownNote.fileHub)
        let fragment = try await VaultFiles(root: root).clipboardFragment(markdownHub.portableBody("# Document notes\n"), notePath: markdownNote.path)
        XCTAssertEqual(fragment.resources.count, 1, "An attached Markdown document is a file snapshot, not an ordinary note connection")
        let destination = temporary.appendingPathComponent("Other", isDirectory: true); try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let pasted = try await VaultFiles(root: destination).importClipboard(fragment)
        XCTAssertTrue(pasted.contains(".zerus/attachments/"), "Pasted document files stay opaque and do not become ordinary notes")
        let destinationScan = try await VaultFiles(root: destination).scan(); XCTAssertTrue(destinationScan.notes.isEmpty)
    }

    @MainActor
    func testExternalConnectionAndFrozenBackupSurviveRelaunchAndFailedReplacementCannotRedirectTheOldBinding() async throws {
        let file = try source(), store = VaultStore(); await store.open(root)
        let origin = store.workspaceID, lease = try await store.selectFile(file, workspace: origin)
        let note = try await store.saveFileHub(source: lease, storage: .backup, title: "Connected document", workspace: origin)
        let hub = try XCTUnwrap(note.fileHub), backup = try XCTUnwrap(NativeFileAttachment.all(in: note.content).first)
        XCTAssertEqual(hub.kind, .local); XCTAssertFalse(hub.managed)
        XCTAssertFalse(note.content.contains(temporary.path)); XCTAssertTrue(note.parts.body.contains("zerus-attachment:" + backup.id))
        let backupClipboard = try await VaultFiles(root: root).clipboardFragment(note.parts.body, notePath: note.path)
        XCTAssertEqual(backupClipboard.resources.count, 1, "A backup link carries its actual frozen file bytes when copied")
        XCTAssertEqual(backupClipboard.resources.first?.bytes, Data("First document bytes".utf8))
        XCTAssertFalse(backupClipboard.markdown.contains("zerus-attachment:"))
        try Data("New original bytes".utf8).write(to: file)
        let reopened = VaultStore(); await reopened.open(root)
        let loaded = try XCTUnwrap(reopened.notes.first { $0.stableID == note.stableID })
        let current = try await reopened.fileHubLease(loaded, workspace: reopened.workspaceID)
        XCTAssertEqual(try current.readForCopy(), Data("New original bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(backup.path)), Data("First document bytes".utf8))
        let session = try XCTUnwrap(reopened.session(for: loaded)), replacementURL = try source("Replacement.txt", bytes: "Replacement document")
        let replacement = try await reopened.selectFile(replacementURL, workspace: reopened.workspaceID)
        let newNote = try await reopened.saveFileHub(session: session, original: hub, source: replacement, storage: .external, workspace: reopened.workspaceID)
        XCTAssertNotEqual(newNote.fileHub?.id, hub.id); XCTAssertEqual(newNote.stableID, loaded.stableID)
        do { _ = try await reopened.saveFileHub(session: session, original: hub, source: lease, storage: .external, workspace: reopened.workspaceID); XCTFail("A stale file form must not replace the newer connection") } catch {}
        let oldAccess = try await NativeFileMappings(root: root).resolve(hub)
        XCTAssertEqual(oldAccess.url, file); XCTAssertEqual(try oldAccess.readForCopy(), Data("New original bytes".utf8))
        let other = temporary.appendingPathComponent("Other", isDirectory: true); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        do { _ = try await NativeFileMappings(root: other).resolve(hub); XCTFail("Private file mappings cannot leak into another vault") } catch {}
        let raw = try Data(contentsOf: root.appendingPathComponent(newNote.path))
        XCTAssertEqual(NativeFileAttachment.all(in: String(decoding: raw, as: UTF8.self)).map(\.path), [backup.path])
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(backup.path)), Data("First document bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: file), Data("New original bytes".utf8))
        let movedRoot = temporary.appendingPathComponent("MovedVault", isDirectory: true)
        try FileManager.default.moveItem(at: root, to: movedRoot)
        let movedAccess = try await NativeFileMappings(root: movedRoot).resolve(hub)
        XCTAssertEqual(try movedAccess.readForCopy(), Data("New original bytes".utf8), "Renaming the same vault must retain its private file access")
    }

    func testSharedLocationsPreserveForeignRecordsChooseSpecificMappedRootsAndProtectUsedOrEscapingConnections() async throws {
        try write(".zerus/file-locations.json", #"{"version":1,"foreign":{"keep":true},"locations":[{"id":"base","name":"Documents","foreign":17},"future record"]}"#)
        let io = VaultFiles(root: root), mappings = NativeFileMappings(root: root)
        var locations = try await io.fileLocations(); XCTAssertNotNil(locations.warning)
        locations = try await io.changeFileLocation(.rename(locations.locations[0], name: "Library"))
        locations = try await io.changeFileLocation(.add(id: "nested", name: "Projects"))
        let base = temporary.appendingPathComponent("Sources", isDirectory: true), nested = base.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("Brief.txt"); try Data("Portable document".utf8).write(to: file)
        try await mappings.mapLocation("base", url: base); try await mappings.mapLocation("nested", url: nested)
        let reference = try await mappings.reference(for: mappings.selected(file), id: "file", locations: locations.locations)
        XCTAssertEqual(reference.kind, .location); XCTAssertEqual(reference.locationID, "nested"); XCTAssertEqual(reference.path, "Brief.txt")
        let resolved = try await mappings.resolve(reference); XCTAssertEqual(try resolved.readForCopy(), Data("Portable document".utf8))
        let body = try reference.setting(in: "---\nzerus-id: linked\nforeign:\n  preserve: true\n---\n# Linked document\n")
        try write(".trash/Linked.md", body)
        let bytes = try Data(contentsOf: root.appendingPathComponent(NativeFileLocations.path))
        do { _ = try await io.changeFileLocation(.remove(locations.locations.first { $0.id == "nested" }!)); XCTFail("A trashed note still owns its portable location reference") } catch {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeFileLocations.path)), bytes)
        let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any], records = object["locations"] as! [Any]
        XCTAssertEqual((object["foreign"] as? [String: Bool])?["keep"], true); XCTAssertEqual((records[0] as? [String: Any])?["foreign"] as? Int, 17); XCTAssertEqual(records[1] as? String, "future record")
        try FileManager.default.createSymbolicLink(at: nested.appendingPathComponent("Escape.txt"), withDestinationURL: try source("Outside.txt"))
        do { _ = try await mappings.resolve(.init(id: "escape", name: "Escape.txt", kind: .location, path: "Escape.txt", locationID: "nested")); XCTFail("Mapped-folder descendants cannot escape their selected root") } catch {}
        try write(".zerus/file-locations.json", #"{"version":99,"locations":["future"]}"#)
        let unsupported = try Data(contentsOf: root.appendingPathComponent(NativeFileLocations.path))
        do { _ = try await io.changeFileLocation(.add(id: "no", name: "No")); XCTFail("Unknown location formats must not be overwritten") } catch {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeFileLocations.path)), unsupported)
    }

    @MainActor
    func testStaleTransactionsAndOldWorkspaceFormsCannotCreateOrRedirectFileNotesAndUnsupportedMetadataStaysIntact() async throws {
        let file = try source(), io = VaultFiles(root: root)
        try write("Note.md", "---\nzerus-id: note\nforeign:\n  keep: [one, two]\n---\n# Note\nOriginal prose.\n")
        let basis = try await io.scan(), note = try XCTUnwrap(basis.notes.first), selection = try await NativeFileMappings(root: root).selected(file)
        let originalBytes = try Data(contentsOf: file)
        do { try await io.applyTransaction([.init(path: "../Original report.txt", before: originalBytes, after: Data("Forbidden write".utf8))], selectedReading: [selection]); XCTFail("A selected read capability must never authorize writes outside the vault") } catch {}
        XCTAssertEqual(try Data(contentsOf: file), originalBytes)
        try write("Note.md", note.content + "Outside edit\n")
        do { _ = try await io.saveFileHub(basis: basis, note: note, original: nil, reference: .init(id: "new", name: file.lastPathComponent, kind: .local), title: "", folder: "Inbox", source: selection, storage: .copy); XCTFail("A copied file must not partially commit against changed note bytes") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus/attachments").path) && ((try? FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent(".zerus/attachments").path))?.contains(where: { $0.hasSuffix(".txt") }) == true))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Note.md"), encoding: .utf8), note.content + "Outside edit\n")
        let store = VaultStore(); await store.open(root); let old = store.workspaceID
        let other = temporary.appendingPathComponent("Other", isDirectory: true); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await store.open(other); await store.open(root)
        do { _ = try await store.saveFileHub(source: selection, title: "Stale", workspace: old); XCTFail("An old A form must remain invalid after A→B→A") } catch {}
        XCTAssertFalse(store.notes.contains { $0.title == "Stale" })
        for path in ["../outside.pdf", "/absolute.pdf", "C:\\outside.pdf", "a//b.pdf", "a/./b.pdf"] {
            let content = "---\nzerus-file-id: file\nzerus-file-name: File.pdf\nzerus-file-kind: vault\nzerus-file-path: \(path)\n---\n# Preserved\n"
            XCTAssertNil(NativeFileHub(NoteDocument(path: "Invalid.md", content: content, modified: Date())))
        }
    }
}
