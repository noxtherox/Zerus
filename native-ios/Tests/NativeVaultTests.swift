import XCTest
import Combine
import UIKit
@testable import ZerusNative

final class NativeVaultTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testNoteTitlesUseFirstMatchingHeadingOrFilenameWithUnicodeAndNewlines() {
        let cases: [(String, String)] = [
            ("# First\n# Second", "First"),
            ("Text without a heading", "Fallback.name"),
            ("", "Fallback.name"),
            ("# \n# Later", ""),
            ("## Deep\n# Top", "Top"),
            (" # Indented\n# Actual", "Actual"),
            ("---\nName: '# metadata'\n---\n# Café 👩🏽‍💻", "Café 👩🏽‍💻"),
            ("# \u{0301}Skip\n# Actual", "Actual"),
            ("# \u{FE0F}Skip", "Fallback.name"),
            ("# \u{200D}Skip", "Fallback.name"),
            ("# Café\u{00A0}", "Café")
        ]
        for (content, title) in cases {
            XCTAssertEqual(NoteDocument(path: "Folder/Fallback.name.md", content: content, modified: .distantPast).title, title, content.debugDescription)
        }
        for newline in ["\n", "\r", "\r\n", "\u{000B}", "\u{000C}", "\u{0085}", "\u{2028}", "\u{2029}"] {
            XCTAssertEqual(NoteDocument(path: "Fallback.md", content: "Intro" + newline + "# Heading" + newline + "# Later", modified: .distantPast).title, "Heading", newline.debugDescription)
        }
    }

    @MainActor
    func testUnavailableSavedVaultShowsRetryStateAndAValidBookmarkCanReopen() async throws {
        let defaults = UserDefaults.standard, key = "zerus.native.vault.bookmark"
        let previous = defaults.data(forKey: key)
        defer { if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) } }
        let unavailable = root.appendingPathComponent("Unavailable", isDirectory: true)
        try FileManager.default.createDirectory(at: unavailable, withIntermediateDirectories: true)
        let bookmark = try unavailable.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: key)
        try FileManager.default.removeItem(at: unavailable)
        let store = VaultStore()
        await store.restore()
        XCTAssertNil(store.root)
        XCTAssertNotNil(store.restorationIssue)
        XCTAssertFalse(store.restoringVault); XCTAssertFalse(store.loading)
        XCTAssertEqual(defaults.data(forKey: key), bookmark, "A failed restore must retain the original bookmark for retry")
        let io = VaultFiles(root: root!)
        try await io.write("Restored.md", data: Data("# Restored\n\nStill here.".utf8), expected: nil)
        defaults.set(try root.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: key)
        await store.restore()
        XCTAssertEqual(store.root?.standardizedFileURL, root.standardizedFileURL)
        XCTAssertEqual(store.notes.first?.title, "Restored")
        XCTAssertNil(store.restorationIssue)
        XCTAssertFalse(store.restoringVault); XCTAssertFalse(store.loading)
    }

    func testSchemaEditingMigratesOnlyInheritedValuesAndPreservesOtherClientsFields() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"Unrelated":{"unsupported":true},"futureMetadata":{"retain":true},"Work":[{"name":"Status","type":"list","listOptions":["Planned","Active"],"listMultiple":true,"futureFlag":{"keep":7}},{"name":"Priority","type":"text"},{"name":"Future","type":"currency","precision":3}],"Work/Child":[{"name":"status","type":"text"},{"name":"Priority","type":"text"}]}"#
        try await io.write(".zerus/properties.json", data: Data(schema.utf8), expected: nil)
        let a = "---\r\n# Keep comment\r\nStatus: [\"Planned\", \"Active\"] # keep status comment\r\nCollision: keep\r\nforeign:\r\n  nested: [one, two]\r\n---\r\n# A\r\n\r\nBody **stays**.\r\n"
        let b = "---\nStatus: [Active, Planned]\n---\n# B\n"
        let child = "---\nstatus: Child status\nPriority: High\n---\n# Child\n"
        let unrelated = "---\nStatus: Unrelated\n---\n# Other\n"
        for (path, text) in [("Work/A.md", a), ("Work/Sub/B.md", b), ("Work/Child/C.md", child), ("Other.md", unrelated), ("Unrelated/Other.md", unrelated), (".trash/Work/D.md", a)] { try await io.write(path, data: Data(text.utf8), expected: nil) }
        let original = try await io.schemaSnapshot()
        _ = try await io.applySchemaChange(snapshot: original, owner: "Work", originalName: "Status", definition: NativePropertyDefinition(name: "Stage", type: .list, options: [" Planned ", "planned", "Done"], multiple: false))
        let actualA = try await io.read("Work/A.md")
        XCTAssertEqual(String(data: actualA, encoding: .utf8), "---\r\n# Keep comment\r\nStage: \"Planned\" # keep status comment\r\nCollision: keep\r\nforeign:\r\n  nested: [one, two]\r\n---\r\n# A\r\n\r\nBody **stays**.\r\n")
        let actualB = try await io.read("Work/Sub/B.md")
        XCTAssertEqual(String(data: actualB, encoding: .utf8), "---\nStage: \"Active\"\n---\n# B\n")
        for (path, text) in [("Work/Child/C.md", child), ("Other.md", unrelated), ("Unrelated/Other.md", unrelated), (".trash/Work/D.md", a)] {
            let actual = try await io.read(path); XCTAssertEqual(actual, Data(text.utf8))
        }
        let schemaAfter = try await io.read(".zerus/properties.json")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: schemaAfter) as? [String: Any])
        XCTAssertEqual((object["futureMetadata"] as? [String: Bool])?["retain"], true)
        let work = try XCTUnwrap(object["Work"] as? [[String: Any]])
        XCTAssertEqual(work[0]["name"] as? String, "Stage")
        XCTAssertEqual(work[0]["listOptions"] as? [String], ["Planned", "Done"])
        XCTAssertEqual((work[0]["futureFlag"] as? [String: Int])?["keep"], 7)
        XCTAssertEqual(work[2]["type"] as? String, "currency")
        XCTAssertEqual(work[2]["precision"] as? Int, 3)
        // A stale schema snapshot must reject the entire operation.
        do {
            _ = try await io.applySchemaChange(snapshot: original, owner: "Work", originalName: nil, definition: NativePropertyDefinition(name: "New", type: .text))
            XCTFail("An outside schema edit must be retained")
        } catch { XCTAssertTrue(error.localizedDescription.contains("changed outside")) }
        let unchangedSchema = try await io.read(".zerus/properties.json"); XCTAssertEqual(unchangedSchema, schemaAfter)
        // Removing an override reveals its parent and retains that note's value.
        _ = try await io.applySchemaChange(snapshot: io.schemaSnapshot(), owner: "Work/Child", originalName: "Priority", definition: nil)
        let retainedChild = try await io.read("Work/Child/C.md"); XCTAssertEqual(retainedChild, Data(child.utf8))
        let beforeCollision = try await io.schemaSnapshot()
        do {
            _ = try await io.applySchemaChange(snapshot: beforeCollision, owner: "Work", originalName: "Stage", definition: NativePropertyDefinition(name: "Collision", type: .text))
            XCTFail("Renaming must not overwrite a separate existing value")
        } catch { XCTAssertTrue(error.localizedDescription.contains("separate Collision value")) }
        let afterCollision = try await io.read("Work/A.md"); XCTAssertEqual(afterCollision, actualA)
        let collisionSchema = try await io.read(".zerus/properties.json"); XCTAssertEqual(collisionSchema, beforeCollision.bytes)
        // Deletion strips only values with no remaining applicable definition.
        _ = try await io.applySchemaChange(snapshot: beforeCollision, owner: "Work", originalName: "Stage", definition: nil)
        let deletedA = String(data: try await io.read("Work/A.md"), encoding: .utf8)!
        XCTAssertFalse(deletedA.contains("Stage:")); XCTAssertTrue(deletedA.contains("# keep status comment\r\nCollision: keep"))
        XCTAssertTrue(deletedA.hasSuffix("# A\r\n\r\nBody **stays**.\r\n"))
        let finalChild = try await io.read("Work/Child/C.md"); XCTAssertEqual(finalChild, Data(child.utf8))
    }

    func testMultiFileChangesRejectConflictsAndRecoverPreparedJournalsBeforeScanning() async throws {
        let alias = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }
        let io = VaultFiles(root: alias)
        let a = Data("# A\nOriginal".utf8), b = Data("# B\nOriginal".utf8), nextA = Data("# A\nUpdated".utf8), nextB = Data("# B\nUpdated".utf8)
        try await io.write("A.md", data: a, expected: nil); try await io.write("B.md", data: b, expected: nil)
        try await io.applyTransaction([VaultFileChange(path: "A.md", before: a, after: nextA), VaultFileChange(path: "B.md", before: b, after: nextB)])
        let committedA = try await io.read("A.md"), committedB = try await io.read("B.md")
        XCTAssertEqual(committedA, nextA); XCTAssertEqual(committedB, nextB)
        do {
            try await io.applyTransaction([VaultFileChange(path: "A.md", before: nextA, after: a), VaultFileChange(path: "B.md", before: b, after: nextB)])
            XCTFail("All expected bytes must be checked before any write")
        } catch { XCTAssertTrue(error.localizedDescription.contains("B.md changed outside")) }
        let unchangedA = try await io.read("A.md"); XCTAssertEqual(unchangedA, nextA)
        // Persisted protocol fixture represents termination after only A was
        // written. It is consumed by the production scanner, not a test hook.
        let record: [String: Any] = ["version": 1, "committed": false, "changes": [
            ["path": "A.md", "before": a.base64EncodedString(), "after": nextA.base64EncodedString()],
            ["path": "B.md", "before": b.base64EncodedString(), "after": nextB.base64EncodedString()]
        ]]
        let journal = ".zerus/native-transactions/interrupted.json"
        try await io.write("B.md", data: b, expected: nextB)
        try await io.write(journal, data: JSONSerialization.data(withJSONObject: record), expected: nil)
        let reopened = VaultFiles(root: alias)
        let recovered = try await reopened.scan()
        XCTAssertEqual(recovered.notes.first { $0.path == "A.md" }?.content, "# A\nOriginal")
        XCTAssertEqual(recovered.notes.first { $0.path == "B.md" }?.content, "# B\nOriginal")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(journal).path))
        // A committed record never rolls back later legitimate outside edits.
        var committed = record; committed["committed"] = true
        let outside = Data("# A\nOutside edit".utf8)
        try await io.write("A.md", data: nextA, expected: a)
        try await io.write("B.md", data: nextB, expected: b)
        try await io.write("A.md", data: outside, expected: nextA)
        try await io.write(journal, data: JSONSerialization.data(withJSONObject: committed), expected: nil)
        _ = try await reopened.scan()
        let preservedOutside = try await io.read("A.md"); XCTAssertEqual(preservedOutside, outside)
        // A conflicting prepared record preserves all files and its evidence.
        try await io.write(journal, data: JSONSerialization.data(withJSONObject: record), expected: nil)
        do { _ = try await reopened.scan(); XCTFail("An outside edit must not be rolled back") }
        catch { XCTAssertTrue(error.localizedDescription.contains("conflicts with an outside edit to A.md")) }
        let preservedB = try await io.read("B.md"); XCTAssertEqual(preservedB, nextB)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(journal).path))
    }

    @MainActor
    func testRecoveryReviewRejectsStaleFilesAndRetainsEveryReviewedVersion() async throws {
        let defaults = UserDefaults.standard, key = "zerus.native.vault.bookmark", previous = defaults.data(forKey: "zerus.native.vault.bookmark")
        defer { if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) } }
        let io = VaultFiles(root: root!)
        let original = Data("# A\r\nOriginal **text**.\r\n".utf8), intended = Data("# A\r\nIntended text.\r\n".utf8)
        let outside = Data("# A\r\nOutside edit.\r\n".utf8), later = Data("# A\r\nEven newer outside edit.\r\n".utf8)
        let binary = Data([0, 255, 4, 8]), created = Data("# Created\nKept.".utf8)
        let journal = ".zerus/native-transactions/conflicted.json"
        let record: [String: Any] = ["version": 1, "committed": false, "changes": [
            ["path": "A.md", "before": original.base64EncodedString(), "after": intended.base64EncodedString()],
            ["path": "assets/file.bin", "before": binary.base64EncodedString(), "after": NSNull()],
            ["path": "Created.md", "before": NSNull(), "after": created.base64EncodedString()]
        ]]
        let journalBytes = try JSONSerialization.data(withJSONObject: record)
        try await io.write("A.md", data: outside, expected: nil)
        try await io.write("assets/file.bin", data: binary, expected: nil)
        try await io.write("Created.md", data: created, expected: nil)
        try await io.write(journal, data: journalBytes, expected: nil)
        let store = VaultStore(); await store.open(root!)
        XCTAssertNil(store.root, "A conflicted vault must be reviewed before it becomes editable")
        let review = try XCTUnwrap(store.recovery)
        XCTAssertEqual(review.files.first?.current, outside)
        let choices: [String: VaultRecoveryChoice] = ["A.md": .original, "assets/file.bin": .intended, "Created.md": .current]
        try await io.write("A.md", data: later, expected: outside)
        await store.resolveRecovery(choices: choices)
        XCTAssertNotNil(store.recovery); XCTAssertTrue(store.recoveryError?.contains("A.md changed since this review") == true)
        let unchangedBinary = try await io.read("assets/file.bin"), unchangedJournal = try await io.read(journal)
        XCTAssertEqual(unchangedBinary, binary); XCTAssertEqual(unchangedJournal, journalBytes)
        let noCopies = try await io.recoveryCopies(); XCTAssertTrue(noCopies.isEmpty)
        await store.reloadRecovery()
        let refreshed = try XCTUnwrap(store.recovery)
        XCTAssertNotEqual(refreshed.id, review.id); XCTAssertEqual(refreshed.files.first?.current, later)
        // Semantically identical JSON still has new bytes and must invalidate
        // the exact review rather than silently accepting a changed journal.
        let updatedJournal = journalBytes + Data("\n".utf8)
        try await io.write(journal, data: updatedJournal, expected: journalBytes)
        await store.resolveRecovery(choices: choices)
        XCTAssertTrue(store.recoveryError?.contains("pending change was updated") == true)
        let stillNoCopies = try await io.recoveryCopies(); XCTAssertTrue(stillNoCopies.isEmpty)
        await store.reloadRecovery(); await store.resolveRecovery(choices: choices)
        XCTAssertNil(store.recovery, store.recoveryError ?? "")
        XCTAssertEqual(store.root?.standardizedFileURL, root.standardizedFileURL)
        let finalA = try await io.read("A.md"), finalCreated = try await io.read("Created.md")
        XCTAssertEqual(finalA, original); XCTAssertEqual(finalCreated, created)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/file.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(journal).path))
        let copies = try await store.recoveryCopies(); XCTAssertEqual(copies.count, 1)
        let archive = try await store.recoveryCopy(XCTUnwrap(copies.first).path)
        XCTAssertEqual(archive.journalBytes, updatedJournal)
        XCTAssertEqual(archive.files.first?.current, later)
        XCTAssertEqual(archive.files.first?.original, original); XCTAssertEqual(archive.files.first?.intended, intended)
        XCTAssertEqual(archive.files.first { $0.path == "assets/file.bin" }?.current, binary)
        XCTAssertEqual(archive.choices["assets/file.bin"], .intended)
        XCTAssertEqual(Set(store.notes.map(\.path)), ["A.md", "Created.md"])
        let reopened = VaultFiles(root: root!)
        let finalScan = try await reopened.scan(); XCTAssertEqual(Set(finalScan.notes.map(\.path)), ["A.md", "Created.md"])
        // A delayed editor save must not replace the version the user just
        // chose, even when that chosen version matches its old baseline.
        let session = try XCTUnwrap(store.session(for: try XCTUnwrap(store.notes.first { $0.path == "A.md" })))
        session.updateContent("# A\nUnsaved local draft, kept separately.\n")
        try await io.write("A.md", data: outside, expected: original)
        let draftRecord: [String: Any] = ["version": 1, "committed": false, "changes": [
            ["path": "A.md", "before": original.base64EncodedString(), "after": intended.base64EncodedString()]
        ]]
        try await io.write(journal, data: JSONSerialization.data(withJSONObject: draftRecord), expected: nil)
        await store.refresh(); XCTAssertNotNil(store.recovery)
        XCTAssertEqual(store.recoveryDrafts.first?.data, Data("# A\nUnsaved local draft, kept separately.\n".utf8))
        await store.resolveRecovery(choices: ["A.md": .original])
        XCTAssertNil(store.recovery, store.recoveryError ?? "")
        await store.flush()
        let selectedAfterFlush = try await io.read("A.md")
        XCTAssertEqual(selectedAfterFlush, original, "A delayed draft must not overwrite the confirmed recovery choice")
        XCTAssertTrue(session.dirty, "The unsaved editor version must remain available after applying a different file version")
        let draftCopies = try await store.recoveryCopies()
        var draftArchived = false
        for copy in draftCopies {
            let saved = try await store.recoveryCopy(copy.path)
            if saved.drafts?.first?.data == Data("# A\nUnsaved local draft, kept separately.\n".utf8) { draftArchived = true }
        }
        XCTAssertTrue(draftArchived)
        await session.reload()
    }

    func testConfirmedRecoveryResumesChoicesAfterInterruptionAndProtectsNewOutsideEdits() async throws {
        let io = VaultFiles(root: root!)
        let currentA = Data("# A\nOutside before review".utf8), selectedA = Data("# A\nChosen original".utf8)
        let currentB = Data("# B\nOutside before review".utf8), selectedB = Data("# B\nChosen intended".utf8)
        let journal = ".zerus/native-transactions/resolving.json"
        let record: [String: Any] = ["version": 2, "committed": false, "finishRecovery": true, "changes": [
            ["path": "A.md", "before": currentA.base64EncodedString(), "after": selectedA.base64EncodedString()],
            ["path": "B.md", "before": currentB.base64EncodedString(), "after": selectedB.base64EncodedString()]
        ]]
        // Termination after A was replaced must finish B, rather than rolling
        // back an explicitly confirmed choice on the next launch.
        try await io.write("A.md", data: selectedA, expected: nil)
        try await io.write("B.md", data: currentB, expected: nil)
        let bytes = try JSONSerialization.data(withJSONObject: record)
        try await io.write(journal, data: bytes, expected: nil)
        let resumed = try await io.scan()
        XCTAssertEqual(resumed.notes.first { $0.path == "A.md" }?.content, "# A\nChosen original")
        XCTAssertEqual(resumed.notes.first { $0.path == "B.md" }?.content, "# B\nChosen intended")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(journal).path))
        let later = Data("# B\nA newer outside edit".utf8)
        try await io.write("B.md", data: later, expected: selectedB)
        try await io.write(journal, data: bytes, expected: nil)
        do { _ = try await io.scan(); XCTFail("A new outside edit requires a fresh decision") }
        catch let required as VaultRecoveryRequired {
            XCTAssertEqual(required.review.files.first { $0.path == "B.md" }?.current, later)
        }
        let retainedA = try await io.read("A.md"), retainedB = try await io.read("B.md"), retainedJournal = try await io.read(journal)
        XCTAssertEqual(retainedA, selectedA); XCTAssertEqual(retainedB, later); XCTAssertEqual(retainedJournal, bytes)
        // An unfamiliar record cannot acquire the confirmed-recovery behavior.
        var unsupported = record; unsupported["version"] = 3
        let unsupportedBytes = try JSONSerialization.data(withJSONObject: unsupported)
        do { try await io.write("B.md", data: selectedB, expected: later); XCTFail("Ordinary saves must pause while a recovery decision is pending") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Review the interrupted change")) }
        try unsupportedBytes.write(to: root.appendingPathComponent(journal), options: .atomic)
        do { _ = try await io.scan(); XCTFail("Unknown recovery protocols must be left untouched") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unsupported recovery record")) }
        let preservedUnknown = try await io.read(journal); XCTAssertEqual(preservedUnknown, unsupportedBytes)
    }

    @MainActor
    func testTypedPropertiesUseInheritedVaultDefinitionsAndPreserveForeignYAMLOnDisk() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"":[{"name":"Inbox only","type":"text"}],"Work":[{"name":"Status","type":"list","listOptions":["Planned","Active"],"listMultiple":false},{"name":"Estimate","type":"number"},{"name":"Hidden inverse","type":"relation","relationHidden":true}],"Work/Projects":[{"name":"status","type":"list","listOptions":["Review","Done"],"listMultiple":true},{"name":"Due","type":"date"}]}"#
        try await io.write(".zerus/properties.json", data: Data(schema.utf8), expected: nil)
        let original = "---\r\n# foreign metadata\r\nzerus-id: stable-typed\r\nStatus: Planned # keep this comment\r\nEstimate: 2.5\r\nTags:\r\n  - 'alpha, beta'\r\n  - plain\r\nforeign:\r\n  nested: [one, two]\r\nText: 'it''s preserved'\r\n...  \r\n# Project\r\n\r\n**Body**\r\n---\r\nStatus: body text\r\n"
        let path = "Work/Projects/Project.md"
        try await io.write(path, data: Data(original.utf8), expected: nil)
        let defs = try await io.propertyDefinitions(notePath: path)
        XCTAssertEqual(defs.map(\.name), ["status", "Estimate", "Hidden inverse", "Due"])
        XCTAssertEqual(defs.first?.options, ["Review", "Done"])
        XCTAssertEqual(defs.first?.owner, "Work/Projects")
        XCTAssertEqual(defs.first?.multiple, true)
        XCTAssertEqual(defs[2].hidden, true)
        let note = NoteDocument(path: path, content: original, modified: Date())
        let session = NoteSession(note: note, root: root!, io: io, onSave: { _ in })
        XCTAssertEqual(NativeFrontmatter(original).entry("Tags")?.value, .list(["alpha, beta", "plain"]))
        XCTAssertEqual(NativeFrontmatter(original).entry("Text")?.value, .text("it's preserved"))
        var content = try NativeFrontmatter(original).setting("status", value: .list(["Review", "A, B", "x\"y"]))
        content = try NativeFrontmatter(content).setting("Estimate", value: .number("-12.75"))
        content = try NativeFrontmatter(content).setting("Done", value: .checkbox(true))
        content = try NativeFrontmatter(content).setting("Due", value: .text("2026-11-09"))
        content = try NativeFrontmatter(content).setting("Tags", value: .list(["new tag"]))
        session.updateContent(content); await session.save()
        XCTAssertFalse(session.dirty, session.failure ?? "")
        let bytes = try await io.read(path)
        let saved = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertEqual(saved, "---\r\n# foreign metadata\r\nzerus-id: stable-typed\r\nStatus: [\"Review\", \"A, B\", \"x\\\"y\"] # keep this comment\r\nEstimate: -12.75\r\nTags: [\"new tag\"]\r\nforeign:\r\n  nested: [one, two]\r\nText: 'it''s preserved'\r\nDone: true\r\nDue: \"2026-11-09\"\r\n...  \r\n# Project\r\n\r\n**Body**\r\n---\r\nStatus: body text\r\n")
        XCTAssertEqual(NativeFrontmatter(saved).entry("Status")?.value, .list(["Review", "A, B", "x\"y"]))
        XCTAssertNil(NativeFrontmatter(saved).entry("foreign")?.value)
        let removed = try NativeFrontmatter(saved).setting("STATUS", value: nil)
        XCTAssertTrue(removed.contains("\r\n# keep this comment\r\nEstimate:"))
        XCTAssertFalse(removed.contains("  - plain"))
        XCTAssertEqual(NoteDocument.split(removed).body, "# Project\r\n\r\n**Body**\r\n---\r\nStatus: body text\r\n")
        XCTAssertThrowsError(try NativeFrontmatter(original).setting("foreign", value: .text("overwrite")))
        XCTAssertThrowsError(try NativeFrontmatter("---\nA: one\na: two\n---\nBody").setting("A", value: .text("overwrite")))
        XCTAssertThrowsError(try NativeFrontmatter(original).setting("Estimate", value: .number("nan")))
        XCTAssertThrowsError(try NativeFrontmatter(original).setting("Bad\nInjected", value: .text("no")))
        XCTAssertThrowsError(try NativeFrontmatter("---\nforeign:\n\n  nested: value\n---\nBody").setting("foreign", value: .text("no")))
        XCTAssertThrowsError(try NativeFrontmatter("---\nforeign:\n  - first\n    - continuation\n---\nBody").setting("foreign", value: .list(["no"])))
        XCTAssertEqual(try NativeFrontmatter("---\nTags:\n- one\n- 'two, three'\n---\nBody").setting("Tags", value: .list(["new"])), "---\nTags: [\"new\"]\n---\nBody")
        XCTAssertEqual(try note.setting("zerus-pinned", to: "true").components(separatedBy: "...  \r\n").last, "# Project\r\n\r\n**Body**\r\n---\r\nStatus: body text\r\n")
        let punctuation = try NativeFrontmatter(original).setting("Tags", value: .list(["first", "it's # a label", "a, b", "quote \" and slash \\" ]))
        XCTAssertEqual(NativeFrontmatter(punctuation).entry("Tags")?.value, .list(["first", "it's # a label", "a, b", "quote \" and slash \\" ]))
        XCTAssertEqual(NativeFrontmatter("---\nTags: ['it''s # stored', 'x, y'] # trailing\n---\nBody").entry("Tags")?.value, .list(["it's # stored", "x, y"]))
        // Reading/using definitions does not normalize away unknown schema fields.
        let schemaAfter = try await io.read(".zerus/properties.json")
        XCTAssertEqual(schemaAfter, Data(schema.utf8))
    }

    func testSaveRejectsOutsideEditAndDeletedFileWithoutLosingEitherVersion() async throws {
        let vault = VaultFiles(root: root!)
        try await vault.write("Project.md", data: Data("# Project\nOriginal".utf8), expected: nil)
        try Data("# Project\nChanged elsewhere".utf8).write(to: root.appendingPathComponent("Project.md"))
        do {
            try await vault.write("Project.md", data: Data("# Project\nMy draft".utf8), expected: Data("# Project\nOriginal".utf8))
            XCTFail("An outside edit must not be overwritten")
        } catch { XCTAssertTrue(error.localizedDescription.contains("changed outside")) }
        let actual = try await vault.read("Project.md")
        XCTAssertEqual(String(data: actual, encoding: .utf8), "# Project\nChanged elsewhere")
        try FileManager.default.removeItem(at: root.appendingPathComponent("Project.md"))
        do {
            try await vault.write("Project.md", data: Data("My draft".utf8), expected: Data("# Project\nOriginal".utf8))
            XCTFail("A note deleted outside Zerus must not be silently recreated")
        } catch { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Project.md").path)) }
    }

    func testTrashRestoreAndMetadataChangePreserveForeignYAMLAndBody() async throws {
        let vault = VaultFiles(root: root!)
        let original = "---\r\n# keep this comment\r\nforeign:\r\n  nested: [one, two]\r\nzerus-id: stable-123\r\n---\r\n# Project\r\n\r\n| A | B |\r\n| - | - |\r\n| α | 🪴 |\r\n"
        let note = NoteDocument(path: "Work/Project.md", content: original, modified: Date())
        let pinned = try note.setting("zerus-pinned", to: "true")
        XCTAssertEqual(pinned, "---\r\n# keep this comment\r\nforeign:\r\n  nested: [one, two]\r\nzerus-id: stable-123\r\nzerus-pinned: true\r\n---\r\n# Project\r\n\r\n| A | B |\r\n| - | - |\r\n| α | 🪴 |\r\n")
        try await vault.write("Work/Project.md", data: Data(pinned.utf8), expected: nil)
        try await vault.move("Work/Project.md", to: ".trash/Work/Project.md", expected: Data(pinned.utf8))
        let trashed = try await vault.scan()
        XCTAssertEqual(trashed.notes.map(\.title), ["Project"])
        XCTAssertTrue(try XCTUnwrap(trashed.notes.first).trashed)
        try await vault.move(".trash/Work/Project.md", to: "Work/Project.md", expected: Data(pinned.utf8))
        let restored = try await vault.read("Work/Project.md")
        XCTAssertEqual(restored, Data(pinned.utf8))
    }

    func testVaultDoesNotFollowSymlinksOrIndexRevisionCopies() async throws {
        let vault = VaultFiles(root: root!)
        try await vault.write("Real.md", data: Data("# Real".utf8), expected: nil)
        try await vault.write(".zerus/revisions/copy.md", data: Data("# Revision".utf8), expected: nil)
        try await vault.write(".zerus/links/example.md", data: Data("# Saved link".utf8), expected: nil)
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("private".utf8).write(to: outside.appendingPathComponent("secret.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        try await vault.write("assets/diagram.png", data: Data([1, 2, 3]), expected: nil)
        let resource = try await vault.resolveResource("assets/diagram.png", notePath: "Work/Project.md")
        XCTAssertEqual(resource.lastPathComponent, "diagram.png")
        let relative = try await vault.resolveResource("../assets/diagram.png", notePath: "Work/Project.md")
        XCTAssertEqual(relative, resource)
        let imageBytes = try await vault.resourceData("../assets/diagram.png", notePath: "Work/Project.md")
        XCTAssertEqual(imageBytes, Data([1, 2, 3]))
        let snapshot = try await vault.scan()
        XCTAssertEqual(Set(snapshot.notes.map(\.title)), ["Real", "Saved link"])
        do { _ = try await vault.read("escape/secret.md"); XCTFail("A symlink must not grant access outside the vault") }
        catch { XCTAssertTrue(error.localizedDescription.contains("outside")) }
        do { try await vault.write("../escape.md", data: Data(), expected: nil); XCTFail("Traversal must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("outside")) }
        // File-provider URLs and /var aliases can resolve to a different root
        // prefix. A missing child must stay inside that canonical root.
        let alias = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }
        let aliased = VaultFiles(root: alias)
        try await aliased.write("new/nested/example.txt", data: Data("inside the selected vault".utf8), expected: nil)
        let newFile = try await vault.read("new/nested/example.txt")
        XCTAssertEqual(newFile, Data("inside the selected vault".utf8))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dangling"), withDestinationURL: outside.appendingPathComponent("not-created"))
        do { try await aliased.write("dangling/secret.txt", data: Data("must not escape".utf8), expected: nil); XCTFail("A broken outside link must never create files outside the vault") }
        catch { XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("not-created/secret.txt").path)) }
    }

    @MainActor
    func testNativeRichTextRendersAndSerializesUserFormatting() throws {
        let inlineCode = "Before `@Al [[literal]]` after."
        XCTAssertEqual(MarkdownText.serialize(MarkdownText.render(inlineCode)), inlineCode, "Editing prose must not strip existing inline-code delimiters or turn literal shortcuts into links")
        let styledLink = "Before **[[zerus:one|Strong label]]** and *[[zerus:two|Italic label]]*."
        XCTAssertEqual(MarkdownText.serialize(MarkdownText.render(styledLink)), styledLink, "Saving a note must retain formatting inside its note links")
        XCTAssertFalse(MarkdownText.requiresSource("# Title\n\n\nA thought."))
        let linked = "# A saved page\n\n<https://example.com/page?q=one>\n"
        XCTAssertFalse(MarkdownText.requiresSource(linked), "A CommonMark autolink is a native text link, not unsupported HTML")
        let linkedRoundTrip = MarkdownText.serialize(MarkdownText.render(linked))
        XCTAssertTrue(linkedRoundTrip.contains("https://example.com/page?q=one"))
        for html in ["<div>HTML block</div>", "Text <span>inline HTML</span>", "<!-- Preserve unknown metadata -->"] {
            XCTAssertTrue(MarkdownText.requiresSource(html), "Actual HTML must remain lossless in source mode")
        }
        XCTAssertFalse(MarkdownText.requiresSource("# A small idea\n\nA **bold** thought and a [link](https://example.com).\n"))
        let rendered = MarkdownText.render("# A small idea\n\nA **bold** thought and a [link](https://example.com).\n")
        XCTAssertEqual(rendered.string, "A small idea\n\nA bold thought and a link.\n")
        let bold = (rendered.string as NSString).range(of: "bold")
        XCTAssertTrue(try XCTUnwrap(rendered.attribute(.font, at: bold.location, effectiveRange: nil) as? UIFont).fontDescriptor.symbolicTraits.contains(.traitBold))
        let edited = NSMutableAttributedString(attributedString: rendered)
        let thought = (edited.string as NSString).range(of: "thought")
        edited.addAttribute(.font, value: MarkdownText.font(traits: .traitItalic), range: thought)
        XCTAssertEqual(MarkdownText.serialize(edited), "# A small idea\n\nA **bold** *thought* and a [link](https://example.com).\n")
        XCTAssertFalse(MarkdownText.requiresSource("| A | B |\n| - | - |\n| α | β |"))
    }

    @MainActor
    func testTableNoteStaysRichAndKeepsWidthsEscapesAndCellsWhenProseChanges() throws {
        let table = "<!-- zerus-table-widths: 120,240 -->\n\n| Item | Owner |\n| :--- | ---: |\n| **Plan** | [[zerus:stable\\|Design]] |\n| A\\|B | `x\\|y` |"
        let source = "# Plan\n\nBefore the table.\n\n" + table + "\n\nAfter the table.\n"
        XCTAssertFalse(MarkdownText.requiresSource(source), "A portable table must not force the whole note into source mode")
        let rich = NSMutableAttributedString(attributedString: MarkdownText.render(source))
        XCTAssertFalse(rich.string.contains("zerus-table-widths"))
        XCTAssertFalse(rich.string.contains("| Item |"))
        rich.replaceCharacters(in: (rich.string as NSString).range(of: "Before"), with: "Above")
        XCTAssertEqual(MarkdownText.serialize(rich), "# Plan\n\nAbove the table.\n\n" + table + "\n\nAfter the table.\n")
        let links = NoteReference.references(in: source + "\n~~~md\n[[Literal code link]]\n~~~")
        XCTAssertEqual(links.map(\.target), ["zerus:stable"])
        XCTAssertEqual(links.first?.label, "Design")
        let reference = try XCTUnwrap(links.first)
        let retargeted = NoteReference.retarget(source, from: reference, to: "new-identity")
        XCTAssertTrue(retargeted.contains("[[zerus:new-identity\\|Design]]"))
        XCTAssertTrue(retargeted.contains("<!-- zerus-table-widths: 120,240 -->"))
    }

    func testTableEditsAndSpreadsheetPasteKeepPortableDataAndColumnSettings() throws {
        let raw = "<!-- zerus-table-widths: 120,240 -->\r\nName | Value\r\n:-- | --:\r\nA\\|B | `x\\|y` | preserve extra"
        var table = try XCTUnwrap(MarkdownTable.blocks(in: raw).first?.table)
        XCTAssertEqual(table.rows, [["Name", "Value"], ["A|B", "`x|y`", "preserve extra"]])
        XCTAssertEqual(table.alignments, [.left, .right])
        XCTAssertEqual(table.widths, [120, 240])
        XCTAssertEqual(table.markdown, raw)
        table.rows[1][0] = "Edited | value"
        XCTAssertEqual(table.markdown, "<!-- zerus-table-widths: 120,240 -->\r\n| Name | Value |\r\n| :--- | ---: |\r\n| Edited \\| value | `x\\|y` | preserve extra |")
        table.insertColumn(at: 1)
        XCTAssertEqual(table.columns, 3)
        XCTAssertTrue(table.markdown.hasPrefix("<!-- zerus-table-widths: 120,160,240 -->\r\n"))
        table.removeColumn(at: 1)
        table.setWidth(300, column: 1)
        XCTAssertTrue(table.markdown.hasPrefix("<!-- zerus-table-widths: 120,300 -->\r\n"))
        table.resetWidths()
        XCTAssertFalse(table.markdown.contains("zerus-table-widths"))
        table.insertRow(at: 1); table.removeRow(at: 1)
        XCTAssertTrue(table.markdown.contains("preserve extra"))
        table.removeRow(at: 0)
        XCTAssertEqual(table.columns, 3)
        XCTAssertEqual(table.alignments.count, 3)
        XCTAssertTrue(table.rows[0].contains("preserve extra"))
        XCTAssertTrue(MarkdownText.requiresSource("<!-- unknown table metadata -->\n\n| A | B |\n| - | - |"), "Unknown comments must survive editing through source mode")
        let spreadsheet = try XCTUnwrap(MarkdownTable.spreadsheet("Name\tValue\r\n\"A\tB\"\t\"**literal**\nnext \"\"quote\"\" | pipe\"\r\n"))
        XCTAssertEqual(spreadsheet.rows, [["Name", "Value"], ["A\tB", "\\*\\*literal\\*\\* next \"quote\" | pipe"]])
        XCTAssertEqual(spreadsheet.markdown, "| Name | Value |\n| --- | --- |\n| A\tB | \\*\\*literal\\*\\* next \"quote\" \\| pipe |")
        XCTAssertNil(MarkdownTable.spreadsheet("Name\t\"Unclosed"))
        let code = "~~~md\n" + raw + "\n~~~"
        XCTAssertTrue(MarkdownTable.blocks(in: code, excluding: FencedCode.blocks(in: code).map(\.range)).isEmpty)
    }

    @MainActor
    func testCutWaitsForOriginalAssetsAndKeepsTextWhenTheNoteChanges() async throws {
        // Own eager Simulator clipboard values. Reading another process's old
        // rich providers can block before the behavior under test even starts.
        let board = UIPasteboard.general
        board.items = []
        defer { board.items = [] }
        let io = VaultFiles(root: root!)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
        let bytes = try XCTUnwrap(image.pngData())
        let source = "A draft.\n\n![Original](assets/original.png)"
        try await io.write("Source.md", data: Data(source.utf8), expected: nil)
        try await io.write("assets/original.png", data: bytes, expected: nil)
        var completed = expectation(description: "Clipboard transfer finishes")
        var changes: [String] = [], failures: [String] = []
        let editor = NativeTextEditor(markdown: source, source: false, onChange: { changes.append($0) }, onImage: { _ in }, onLink: { _ in },
            copyFragment: { try await io.clipboardFragment($0, notePath: "Source.md") },
            onClipboardError: { failures.append($0) }, onClipboardBusy: { if !$0 { completed.fulfill() } })
        let coordinator = editor.makeCoordinator()
        let view = ZerusTextView(frame: .zero, textContainer: nil)
        coordinator.view = view; view.delegate = coordinator; coordinator.load(source, source: false)
        view.selectedRange = NSRange(location: 0, length: view.attributedText.length)
        coordinator.copySelection(view.selectedRange, cut: true)
        XCTAssertFalse(view.text.isEmpty, "Cut cannot remove text before the clipboard owns the attachments")
        view.text = "Changed while copying"; coordinator.textViewDidChange(view)
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertEqual(view.text, "Changed while copying")
        XCTAssertFalse(failures.isEmpty)
        let fragment = try NativeClipboardFragment.decode(try XCTUnwrap(board.data(forPasteboardType: NativeClipboardFragment.type)))
        XCTAssertEqual(fragment.markdown, source)
        XCTAssertEqual(fragment.resources.first?.bytes, bytes)
        completed = expectation(description: "A different note with identical content is protected")
        coordinator.load(source, source: false); coordinator.parent.documentID = "source"
        view.selectedRange = NSRange(location: 0, length: view.attributedText.length)
        coordinator.copySelection(view.selectedRange, cut: true)
        coordinator.parent.documentID = "another-note"
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertFalse(view.text.isEmpty)
        completed = expectation(description: "Older copy is superseded")
        let latest = expectation(description: "Newest note owns the clipboard")
        coordinator.load(source, source: false)
        coordinator.copySelection(NSRange(location: 0, length: view.attributedText.length), cut: false)
        let next = NativeTextEditor(markdown: "Newest clipboard choice", source: false, onChange: { _ in }, onImage: { _ in }, onLink: { _ in }, onClipboardBusy: { if !$0 { latest.fulfill() } }).makeCoordinator()
        let nextView = ZerusTextView(frame: .zero, textContainer: nil)
        next.view = nextView; next.load("Newest clipboard choice", source: false)
        next.copySelection(NSRange(location: 0, length: nextView.attributedText.length), cut: false)
        await fulfillment(of: [completed, latest], timeout: 10)
        XCTAssertEqual(board.string, "Newest clipboard choice", "An older note's slow copy must not replace a newer copy request")
        completed = expectation(description: "Original files are ready")
        let delivered = expectation(description: "Paste waits for the pending copy")
        coordinator.load(source, source: false)
        coordinator.copySelection(NSRange(location: 0, length: view.attributedText.length), cut: false)
        XCTAssertEqual(board.string, source, "Other apps receive current Markdown immediately")
        let receiver = ZerusTextView(frame: .zero, textContainer: nil)
        receiver.attributedText = NSAttributedString(string: "")
        var received: NativeClipboardFragment?
        receiver.onFragmentPaste = { data in received = try? NativeClipboardFragment.decode(data); delivered.fulfill() }
        receiver.paste(nil)
        XCTAssertNil(received)
        XCTAssertEqual(receiver.text, "")
        await fulfillment(of: [completed, delivered], timeout: 10)
        XCTAssertEqual(received?.resources.first?.bytes, bytes)
        completed = expectation(description: "Unchanged selection is cut")
        coordinator.load(source, source: false)
        view.selectedRange = NSRange(location: 0, length: view.attributedText.length)
        coordinator.copySelection(view.selectedRange, cut: true)
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertEqual(view.text, "")
        XCTAssertEqual(changes.last, "")
        let cut = try NativeClipboardFragment.decode(try XCTUnwrap(board.data(forPasteboardType: NativeClipboardFragment.type)))
        XCTAssertEqual(cut.resources.first?.bytes, bytes)
        completed = expectation(description: "An unavailable attachment cannot remove the text")
        coordinator.load("Keep ![Missing](assets/missing.png)", source: false)
        view.selectedRange = NSRange(location: 0, length: view.attributedText.length)
        coordinator.copySelection(view.selectedRange, cut: true)
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertFalse(view.text.isEmpty)

    }

    @MainActor
    func testExternalRTFDPasteKeepsNativeFormattingAndAttachmentFileBytes() throws {
        let board = UIPasteboard.general
        board.items = []
        defer { board.items = [] }
        let rich = NSMutableAttributedString(string: "A bold note and link.\n", attributes: [.font: MarkdownText.font()])
        rich.addAttribute(.font, value: MarkdownText.font(traits: .traitBold), range: (rich.string as NSString).range(of: "bold"))
        rich.addAttribute(.link, value: URL(string: "https://example.com")!, range: (rich.string as NSString).range(of: "link"))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in UIColor.systemGreen.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
        let bytes = try XCTUnwrap(image.pngData())
        let attachment = NSTextAttachment(data: bytes, ofType: "public.png")
        attachment.image = image; attachment.fileWrapper = FileWrapper(regularFileWithContents: bytes)
        attachment.fileWrapper?.preferredFilename = "Original.png"
        rich.append(NSAttributedString(attachment: attachment))
        let rtfd = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        board.items = [["com.apple.flat-rtfd": rtfd]]
        let view = ZerusTextView(frame: .zero, textContainer: nil)
        var result: Result<NativeClipboardFragment, Error>?
        view.onRichPaste = { value in result = Result { try NativeClipboard.importRich(value) } }
        view.paste(nil)
        let fragment = try XCTUnwrap(result).get()
        XCTAssertTrue(fragment.markdown.contains("**bold**"), fragment.markdown)
        XCTAssertTrue(fragment.markdown.contains("[link](https://example.com)"), fragment.markdown)
        XCTAssertFalse(fragment.markdown.contains("\u{fffc}"))
        XCTAssertEqual(fragment.resources.count, 1)
        XCTAssertEqual(fragment.resources.first?.bytes, bytes)
        XCTAssertEqual(fragment.resources.first?.name, "Original.png")
        let partial = NativeClipboard.selection(MarkdownText.render("# Important thought"), range: NSRange(location: 10, length: 7))
        XCTAssertEqual(MarkdownText.serialize(partial), "**thought**", "A partial heading is copied as styled text, without inventing a new heading")
        let original = MarkdownText.render("BeforeAfter")
        let code = MarkdownText.render("```swift\nlet x = 1\n```")
        let insertion = NativeClipboard.insertion(code, into: original, range: NSRange(location: 6, length: 0))
        let changed = NSMutableAttributedString(attributedString: original)
        changed.insert(insertion, at: 6)
        XCTAssertEqual(MarkdownText.serialize(changed), "Before\n\n```swift\nlet x = 1\n```\n\nAfter")
        let windowsProse = "First **bold** line.\r\n\r\nLast line.\r\n"
        XCTAssertEqual(MarkdownText.serialize(MarkdownText.render(windowsProse)), windowsProse)
        let windowsSource = "| A |\r\n| --- |\r\n| One |\r\n"
        let table = MarkdownText.render(windowsSource)
        let windows = NSMutableAttributedString(attributedString: original)
        windows.insert(NativeClipboard.insertion(table, into: original, range: NSRange(location: 6, length: 0)), at: 6)
        XCTAssertEqual(MarkdownText.serialize(windows), "Before\n\n" + windowsSource + "\nAfter", "Keep every original table byte while separating the surrounding paragraphs")
    }

    @MainActor
    func testClipboardTransfersOriginalResourcesAcrossVaultsAndKeepsCodeLiteral() async throws {
        let io = VaultFiles(root: root!)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 3)).image { context in UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3, height: 3)) }
        let bytes = try XCTUnwrap(image.pngData()), other = Data("a different file".utf8)
        try await io.write("Work/Source.md", data: Data("# Source".utf8), expected: nil)
        try await io.write("Work/art/(diagram%20draft) #é.png", data: bytes, expected: nil)
        try await io.write("Work/art/(diagram draft) #é.png", data: other, expected: nil)
        try await io.write("assets/root.png", data: bytes, expected: nil)
        let pdf = Data("%PDF-1.7\n%%EOF".utf8)
        try await io.write("Shared/report.pdf", data: pdf, expected: nil)
        let relative = "art/%28diagram%2520draft%29%20%23%C3%A9.png"
        let source = "![Diagram](<" + relative + "> \"Caption\")\n\n[![Linked](" + relative + ")](https://example.com)\n\n![Alt [example](assets/not-selected.txt)](assets/root.png)\n\n[Report](../Shared/report.pdf#page=2)\n\n<!-- zerus-table-widths: 120,240 -->\n| Image | Text |\n| --- | --- |\n| ![Root](assets/root.png) | A\\|B |\n\n`![Literal](assets/not-a-resource.png)`\n\n~~~md\n![Code](assets/not-a-resource.png)\n~~~"
        let fragment = try await io.clipboardFragment(source, notePath: "Work/Source.md")
        XCTAssertEqual(fragment.markdown, source)
        XCTAssertEqual(fragment.resources.count, 3)
        XCTAssertEqual(fragment.resources.first(where: { $0.reference.contains("diagram") })?.bytes, bytes, "A literal percent sequence in a file name must not resolve to a different file")
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let target = VaultFiles(root: destination)
        let pasted = try await target.importClipboard(fragment)
        XCTAssertTrue(pasted.contains("<!-- zerus-table-widths: 120,240 -->"))
        XCTAssertTrue(pasted.contains("`![Literal](assets/not-a-resource.png)`"))
        XCTAssertTrue(pasted.contains("~~~md\n![Code](assets/not-a-resource.png)\n~~~"))
        XCTAssertTrue(pasted.contains("#page=2"))
        XCTAssertTrue(pasted.contains("](https://example.com)"))
        let references = MarkdownResources.localReferences(in: pasted)
        XCTAssertEqual(references.count, 3)
        for reference in references {
            let copied = try await target.resourceData(reference, notePath: "Other/Note.md")
            XCTAssertTrue(copied == bytes || copied == pdf)
        }
        let unchanged = try await io.read("Work/art/(diagram%20draft) #é.png")
        XCTAssertEqual(unchanged, bytes)
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fragment)) as? [String: Any])
        future["version"] = 99
        XCTAssertThrowsError(try NativeClipboardFragment.decode(JSONSerialization.data(withJSONObject: future)))
        let beforeInvalid = try await target.scan().files
        let incomplete = NativeClipboardFragment(markdown: "![Missing](assets/missing.png)", resources: [])
        do { _ = try await target.importClipboard(incomplete); XCTFail("A paste without its declared asset must not write partial data") }
        catch { }
        let afterInvalid = try await target.scan().files
        XCTAssertEqual(beforeInvalid, afterInvalid)
        try await io.write("assets/root.png", data: other, expected: bytes)
        let sameVault = try await io.importClipboard(fragment)
        XCTAssertFalse(sameVault.contains("![Root](assets/root.png)"), "A changed original image must not replace the copied snapshot")
        let sameReferences = MarkdownResources.localReferences(in: sameVault)
        for reference in sameReferences {
            let copied = try await io.resourceData(reference, notePath: "Other/Note.md")
            XCTAssertTrue(copied == bytes || copied == pdf)
        }
    }

    @MainActor
    func testNativeCopyKeepsMarkdownInsteadOfAttachmentReplacementCharacters() throws {
        let board = UIPasteboard.general
        board.items = []
        defer { board.items = [] }
        let source = "A **bold** thought.\n\n```swift\nlet value = 1\n```\n\n| A | B |\n| --- | --- |\n| one | two |\n\n![Diagram](assets/diagram.png)\n"
        let view = ZerusTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), textContainer: nil)
        view.attributedText = MarkdownText.render(source)
        view.selectedRange = NSRange(location: 0, length: view.attributedText.length)
        view.copy(nil)
        let copied = try XCTUnwrap(board.string)
        XCTAssertEqual(copied, source)
        XCTAssertFalse(copied.contains("\u{fffc}"))
    }

    @MainActor
    func testNativePasteKeepsSpreadsheetCellsEditableWhenClipboardAlsoHasAnImage() throws {
        let clipboard = UIPasteboard.general
        clipboard.items = []
        defer { clipboard.items = [] }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let cells = "Name\tValue\nA\tB"
        clipboard.items = [["public.utf8-plain-text": cells, "public.png": try XCTUnwrap(image.pngData())]]
        let editor = ZerusTextView(frame: .zero, textContainer: nil)
        var pasted: String?, imageImported = false
        editor.onSpreadsheetPaste = { pasted = $0 }
        editor.onImagePaste = { _ in imageImported = true }
        editor.paste(nil)
        XCTAssertEqual(pasted, cells)
        XCTAssertFalse(imageImported, "Spreadsheet text must take priority over its screenshot representation")
        editor.sourceMode = true
        editor.paste(nil)
        XCTAssertEqual(editor.text, cells, "Source-mode paste must preserve the clipboard text verbatim")
    }

    @MainActor
    func testCodeNoteKeepsLiteralCodeAndFenceBytesWhenProseChanges() throws {
        let block = "~~~~swift title=Example\nlet pattern = \"**literal** [[not a link]] <tag>\"\n// | a | b |\n```\n~~~~"
        let source = "# Example\n\nBefore the code.\n\n" + block + "\n\nAfter the code.\n"
        XCTAssertFalse(MarkdownText.requiresSource(source), "A code block must not force surrounding prose into source mode")
        let rich = NSMutableAttributedString(attributedString: MarkdownText.render(source))
        XCTAssertFalse(rich.string.contains("~~~~swift"))
        rich.replaceCharacters(in: (rich.string as NSString).range(of: "Before"), with: "Above")
        XCTAssertEqual(MarkdownText.serialize(rich), "# Example\n\nAbove the code.\n\n" + block + "\n\nAfter the code.\n")
        let windows = "  ```python  \r\nprint(\"🪴\")\r\n  ```"
        XCTAssertEqual(MarkdownText.serialize(MarkdownText.render(windows)), windows)
        let parsed = try XCTUnwrap(FencedCode.blocks(in: windows).first?.code)
        XCTAssertEqual(parsed.body, "print(\"🪴\")")
        XCTAssertEqual(parsed.replacing(body: parsed.body, info: parsed.info).markdown, windows)
        let changed = parsed.replacing(body: "print(\"🪴\")\n```\nmore()", info: "python")
        XCTAssertEqual(changed.body, "print(\"🪴\")\n```\nmore()")
        XCTAssertEqual(changed.markdown, "  ````python\r\nprint(\"🪴\")\n```\nmore()\r\n  ````")
        let unfinished = "```js\nconst example = '<tag> **literal**';"
        XCTAssertFalse(MarkdownText.requiresSource(unfinished))
        XCTAssertEqual(MarkdownText.serialize(MarkdownText.render(unfinished)), unfinished)
        XCTAssertTrue(MarkdownText.imageReferences("```md\n![example](assets/literal.png)\n```").isEmpty)
        XCTAssertTrue(MarkdownText.requiresSource("> ```swift\n> let x = 1\n> ```"), "Unsupported nested fences must remain lossless in source mode")
    }

    @MainActor
    func testLinkedChecklistNoteKeepsItsTargetsAndTaskStateWhenEdited() throws {
        let source = "# Next steps\n\nSee [[zerus:project-123|Project plan]] and [[Daily review]].\n\n- [ ] Read the plan\n  - [x] Collect **ideas**\n\nAn ordinary paragraph.\n"
        XCTAssertFalse(MarkdownText.requiresSource(source))
        let rich = NSMutableAttributedString(attributedString: MarkdownText.render(source))
        XCTAssertTrue(rich.string.contains("See Project plan and Daily review."))
        XCTAssertFalse(rich.string.contains("[["))
        XCTAssertFalse(rich.string.contains("- [ ]"))
        let plan = (rich.string as NSString).range(of: "Project plan")
        let url = try XCTUnwrap(rich.attribute(.link, at: plan.location, effectiveRange: nil) as? URL)
        XCTAssertEqual(url.scheme, "zerus-note")
        // Styling part of a link must not split it into multiple link targets.
        rich.addAttribute(.font, value: MarkdownText.font(traits: .traitBold), range: NSRange(location: plan.location, length: 7))
        rich.replaceCharacters(in: (rich.string as NSString).range(of: "ordinary"), with: "edited")
        let saved = MarkdownText.serialize(rich)
        XCTAssertTrue(saved.contains("[**Project** plan](#zerus-note:zerus%3Aproject%2D123%7CProject%20plan)"), saved)
        XCTAssertEqual(MarkdownText.serialize(MarkdownText.render(saved)), saved, "Switching source/rich or reopening must retain the label's mixed styles")
        XCTAssertTrue(saved.contains("[[Daily review]]"))
        XCTAssertTrue(saved.contains("- [ ] Read the plan\n  - [x] Collect **ideas**"))
        XCTAssertTrue(saved.contains("An edited paragraph."))
        XCTAssertFalse(saved.contains("zerus-note://open?"), "Private editing URLs must not leak into portable Markdown")
        let literal = MarkdownText.render("Use `[[literal]]` in code and \\[\\[escaped\\]\\].")
        XCTAssertTrue(literal.string.contains("[[literal]]"))
        XCTAssertFalse(MarkdownText.serialize(literal).contains("zerus-note:"))
        let unresolved = try XCTUnwrap(NoteReference(wikilink: "[[Unwritten|A useful label]]"))
        XCTAssertEqual(NoteReference.retarget("See [[Unwritten|A useful label]]. [A **formatted** label](#zerus-note:Unwritten%7CA%20formatted%20label). Keep `[[Unwritten]]` literal.", from: unresolved, to: "new-identity"), "See [[zerus:new-identity|A useful label]]. [A **formatted** label](#zerus-note:zerus%3Anew%2Didentity%7CA%20formatted%20label). Keep `[[Unwritten]]` literal.")
    }

    @MainActor
    func testNativeNoteLinksResolveStableIDsAndOfferAmbiguousOrDeletedTargets() throws {
        let store = VaultStore()
        store.notes = [
            NoteDocument(path: "Work/Plan.md", content: "---\nzerus-id: stable\n---\n# Renamed plan", modified: Date()),
            NoteDocument(path: "Work/Review.md", content: "# Review", modified: Date()),
            NoteDocument(path: "Home/Review.md", content: "# Review", modified: Date()),
            NoteDocument(path: ".trash/Deleted.md", content: "---\nzerus-id: deleted\n---\n# Deleted", modified: Date())
        ]
        func reference(_ source: String) throws -> NoteReference { try XCTUnwrap(NoteReference(wikilink: source)) }
        XCTAssertEqual(store.targets(for: try reference("[[zerus:stable|Old title]]")).map(\.title), ["Renamed plan"])
        XCTAssertEqual(store.targets(for: try reference("[[Review]]")).count, 2)
        XCTAssertEqual(store.targets(for: try reference("[[Work/Review]]")).map(\.path), ["Work/Review.md"])
        XCTAssertTrue(store.targets(for: try reference("[[zerus:deleted|Deleted]]")).isEmpty)
        XCTAssertEqual(store.targets(for: try reference("[[zerus:deleted|Deleted]]"), includeTrash: true).map(\.path), [".trash/Deleted.md"])
        let label = "Plan [Q4] | café"
        let literal = NoteReference(target: "zerus:stable", label: label, explicitLabel: true).markdown(label: label)
        XCTAssertEqual(literal, "[Plan \\[Q4\\] | café](#zerus-note:zerus%3Astable%7CPlan%20%5BQ4%5D%20%7C%20caf%C3%A9)")
        let parsed = try AttributedString(markdown: literal)
        XCTAssertEqual(String(parsed.characters), label)
        let url = try XCTUnwrap(parsed.runs.first?.link), native = try XCTUnwrap(NoteReference(url: url))
        XCTAssertEqual(native.target, "zerus:stable"); XCTAssertEqual(native.label, label)
        XCTAssertEqual(store.targets(for: native).map(\.path), ["Work/Plan.md"])
    }

    @MainActor
    func testImageNoteStaysRichAndEditingProseKeepsItsImageReference() throws {
        let source = "# Collapse chart legend\n\nIn **Productivity** reports, compare **Operators**.\n\n![image.png](assets/pasted-20261103-105300.png)\n\n# Acceptance Criteria\n\n- Keep the chart readable\n"
        XCTAssertFalse(MarkdownText.requiresSource(source), "An embedded image must not force the entire note into source mode")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 320)).image { renderer in
            UIColor.systemBlue.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 640, height: 320))
        }
        let rich = NSMutableAttributedString(attributedString: MarkdownText.render(source, images: ["assets/pasted-20261103-105300.png": image], width: 300))
        XCTAssertFalse(rich.string.contains("**"))
        XCTAssertFalse(rich.string.contains("![image.png]"))
        let location = (rich.string as NSString).range(of: "\u{fffc}").location
        XCTAssertNotEqual(location, NSNotFound)
        let attachment = try XCTUnwrap(rich.attribute(.attachment, at: location, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(attachment.image?.size.width, 640)
        XCTAssertEqual(attachment.bounds.width, 300)
        XCTAssertEqual(attachment.bounds.height, 150)
        let phrase = (rich.string as NSString).range(of: "compare")
        rich.replaceCharacters(in: phrase, with: "choose")
        let saved = MarkdownText.serialize(rich)
        XCTAssertTrue(saved.contains("choose **Operators**"))
        XCTAssertTrue(saved.contains("![image.png](assets/pasted-20261103-105300.png)"))
        XCTAssertTrue(saved.contains("# Acceptance Criteria"))
        XCTAssertFalse(saved.contains("\u{fffc}"))
    }

    @MainActor
    func testRecoveryDraftSurvivesConflictAndCanBeReopened() async throws {
        let vault = VaultFiles(root: root!)
        let header = "---\nzerus-id: consistent-recovery\n---\n"
        let consistentOriginal = header + "# Recovered\n\nOriginal"
        let recoveredBody = "# Recovered\n\nRecovered idea"
        try await vault.write("Resumed.md", data: Data(consistentOriginal.utf8), expected: nil)
        let firstStore = VaultStore()
        await firstStore.open(root!)
        let interrupted = try XCTUnwrap(firstStore.session(for: XCTUnwrap(firstStore.notes.first)))
        interrupted.updateBody(recoveredBody)
        interrupted.deactivate()
        let saved = expectation(description: "A recovered draft resumes saving against its unchanged original file")
        let secondStore = VaultStore()
        await secondStore.open(root!)
        XCTAssertEqual(secondStore.activeVaultID, firstStore.activeVaultID)
        let subscription = secondStore.$notes.first(where: { $0.first?.content == header + recoveredBody }).sink { _ in saved.fulfill() }
        defer { subscription.cancel() }
        let resumed = try XCTUnwrap(secondStore.session(for: XCTUnwrap(secondStore.notes.first)))
        defer { resumed.deactivate() }
        XCTAssertEqual(resumed.document.parts.body, recoveredBody)
        XCTAssertTrue(resumed.dirty)
        await fulfillment(of: [saved], timeout: 3)
        let resumedBytes = try await vault.read("Resumed.md")
        XCTAssertEqual(resumedBytes, Data((header + recoveredBody).utf8))
        XCTAssertFalse(resumed.dirty)
        XCTAssertNil(resumed.failure)
        await resumed.reload()

        let original = "# Draft\n\nOriginal"
        try await vault.write("Draft.md", data: Data(original.utf8), expected: nil)
        let note = NoteDocument(path: "Draft.md", content: original, modified: Date())
        let session = NoteSession(note: note, root: root!, io: vault, onSave: { _ in })
        defer { session.deactivate() }
        session.updateBody("# Draft\n\nMy unsaved idea")
        try Data("# Draft\n\nOutside edit".utf8).write(to: root.appendingPathComponent("Draft.md"))
        await session.save()
        XCTAssertTrue(session.dirty)
        XCTAssertNotNil(session.failure)
        let reopened = NoteSession(note: NoteDocument(path: "Draft.md", content: "# Draft\n\nOutside edit", modified: Date()), root: root!, io: vault, onSave: { _ in })
        defer { reopened.deactivate() }
        XCTAssertEqual(reopened.document.parts.body, "# Draft\n\nMy unsaved idea")
        XCTAssertTrue(reopened.dirty)
        XCTAssertNotNil(reopened.failure)
        let disk = try await vault.read("Draft.md")
        XCTAssertEqual(String(data: disk, encoding: .utf8), "# Draft\n\nOutside edit")
    }

    @MainActor
    func testRecoveredDraftsFollowSavedVaultIdentityWhenAPathIsReused() async throws {
        let originalRoot = root.appendingPathComponent("Workspace", isDirectory: true)
        let movedRoot = root.appendingPathComponent("Moved Workspace", isDirectory: true)
        let original = "---\nzerus-id: shared-note-id\n---\n# Note\n\nOriginal"
        let recovered = "---\nzerus-id: shared-note-id\n---\n# Note\n\nRecovered idea"
        let firstIO = VaultFiles(root: originalRoot)
        try await firstIO.write("Note.md", data: Data(original.utf8), expected: nil)
        let first = VaultStore()
        await first.open(originalRoot)
        let owner = try XCTUnwrap(first.activeVaultID)
        let interrupted = try XCTUnwrap(first.session(for: XCTUnwrap(first.notes.first)))
        interrupted.updateBody("# Note\n\nRecovered idea")
        interrupted.deactivate()
        try FileManager.default.moveItem(at: originalRoot, to: movedRoot)
        // Renew access to the known saved vault at its new location. Simulator
        // minimal bookmarks can retain the old spelling after a filesystem move.
        let renewed = VaultStore()
        await renewed.open(movedRoot, registeredID: owner)
        XCTAssertEqual(renewed.activeVaultID, owner)
        try await VaultFiles(root: originalRoot).write("Note.md", data: Data(original.utf8), expected: nil)
        let replacement = VaultStore()
        await replacement.open(originalRoot)
        XCTAssertNotEqual(replacement.activeVaultID, owner)
        let replacementSession = try XCTUnwrap(replacement.session(for: XCTUnwrap(replacement.notes.first)))
        defer { replacementSession.deactivate() }
        XCTAssertEqual(replacementSession.document.content, original, "Another saved vault must not adopt the old folder's private draft")
        XCTAssertFalse(replacementSession.dirty)
        let returned = VaultStore()
        await returned.openSavedVault(owner)
        XCTAssertEqual(returned.activeVaultID, owner)
        XCTAssertEqual(returned.root?.standardizedFileURL, movedRoot.standardizedFileURL)
        let saved = expectation(description: "The original saved vault retains and resumes its draft after moving")
        let subscription = returned.$notes.first(where: { $0.first?.content == recovered }).sink { _ in saved.fulfill() }
        defer { subscription.cancel() }
        let resumed = try XCTUnwrap(returned.session(for: XCTUnwrap(returned.notes.first)))
        defer { resumed.deactivate() }
        XCTAssertEqual(resumed.document.content, recovered)
        await fulfillment(of: [saved], timeout: 3)
        let movedBytes = try await VaultFiles(root: movedRoot).read("Note.md")
        let replacementBytes = try await VaultFiles(root: originalRoot).read("Note.md")
        XCTAssertEqual(movedBytes, Data(recovered.utf8))
        XCTAssertEqual(replacementBytes, Data(original.utf8))
        XCTAssertFalse(resumed.dirty)
        // Clean up a failed pre-fix run without leaving its private draft.
        await resumed.reload()
        await replacementSession.reload()
    }

    @MainActor
    func testDuplicateKeepsPropertiesAndUnheadedTextWithANewIdentity() async throws {
        let vault = VaultFiles(root: root!)
        let content = "---\nzerus-id: original\ncustomer: Acme\ncustom: [one, two]\n---\nFirst paragraph with [[zerus:other|Other]].\n\nLast paragraph."
        try await vault.write("Work/Idea.md", data: Data(content.utf8), expected: nil)
        let bookmark = UserDefaults.standard.data(forKey: "zerus.native.vault.bookmark")
        defer { if let bookmark { UserDefaults.standard.set(bookmark, forKey: "zerus.native.vault.bookmark") } else { UserDefaults.standard.removeObject(forKey: "zerus.native.vault.bookmark") } }
        let store = VaultStore()
        await store.open(root!)
        await store.duplicate(try XCTUnwrap(store.notes.first))
        let snapshot = try await vault.scan()
        let copy = try XCTUnwrap(snapshot.notes.first { $0.path == "Work/Idea copy.md" })
        XCTAssertEqual(copy.property("customer"), "Acme")
        XCTAssertEqual(copy.property("custom"), "[one, two]")
        XCTAssertNotEqual(copy.stableID, "original")
        XCTAssertTrue(copy.parts.body.contains("First paragraph with [[zerus:other|Other]].\n\nLast paragraph."))
        XCTAssertEqual(snapshot.notes.first { $0.path == "Work/Idea.md" }?.content, content)
    }

    @MainActor
    func testTaskUpdatePreservesUnrecognizedFieldsAndOtherTasks() async throws {
        let vault = VaultFiles(root: root!)
        let bytes = Data(#"{"futureSetting":{"keep":true},"tasks":[{"id":"a","title":"Read","completed":false,"futureField":17},{"id":"b","title":"Write","completed":false}],"lists":[],"categoryOptions":[]}"#.utf8)
        try await vault.write(".zerus/tasks.json", data: bytes, expected: nil)
        let bookmark = UserDefaults.standard.data(forKey: "zerus.native.vault.bookmark")
        defer { if let bookmark { UserDefaults.standard.set(bookmark, forKey: "zerus.native.vault.bookmark") } else { UserDefaults.standard.removeObject(forKey: "zerus.native.vault.bookmark") } }
        let store = VaultStore()
        await store.open(root!)
        XCTAssertEqual(store.tasks.count, 2)
        var task = try XCTUnwrap(store.tasks.first)
        task.completed = true
        await store.saveTask(task)
        let saved = try await vault.read(".zerus/tasks.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual((json["futureSetting"] as? [String: Bool])?["keep"], true)
        let tasks = try XCTUnwrap(json["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks[0]["completed"] as? Bool, true)
        XCTAssertEqual(tasks[0]["futureField"] as? Int, 17)
        XCTAssertEqual(tasks[1]["title"] as? String, "Write")
        XCTAssertEqual(tasks.count, 2)
        let completedAt = tasks[0]["completedAt"] as? String
        var external = json, outsideTasks = tasks
        outsideTasks[0]["title"] = "Renamed elsewhere"; outsideTasks[0]["futureField"] = ["new": true]
        external["tasks"] = outsideTasks; external["generalListName"] = "Inbox"
        let outsideBytes = try JSONSerialization.data(withJSONObject: external)
        try outsideBytes.write(to: root!.appendingPathComponent(".zerus/tasks.json"), options: .atomic)
        task.priority = "high"
        let mergeSaved = await store.saveTask(task)
        XCTAssertTrue(mergeSaved, "An unchanged title from an old form must not replace a newer title")
        let merged = try JSONSerialization.jsonObject(with: await vault.read(".zerus/tasks.json")) as! [String: Any]
        let mergedTask = (merged["tasks"] as! [[String: Any]])[0]
        XCTAssertEqual(mergedTask["title"] as? String, "Renamed elsewhere")
        XCTAssertEqual(mergedTask["priority"] as? String, "high")
        XCTAssertEqual(mergedTask["completedAt"] as? String, completedAt)
        XCTAssertEqual((mergedTask["futureField"] as? [String: Bool])?["new"], true)
        XCTAssertEqual(store.generalTaskListName, "Inbox")
        task.title = "Conflicting phone title"
        let conflicted = await store.saveTask(task); XCTAssertFalse(conflicted)
        let afterConflict = try await vault.read(".zerus/tasks.json")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: afterConflict) as? NSDictionary, merged as NSDictionary)
        var freshReload = merged, freshRecords = merged["tasks"] as! [[String: Any]]
        freshRecords[0]["title"] = "Changed again before reload"; freshReload["tasks"] = freshRecords
        try JSONSerialization.data(withJSONObject: freshReload).write(to: root!.appendingPathComponent(".zerus/tasks.json"), options: .atomic)
        let reloaded = try await store.reloadTask(id: "a", workspace: store.workspaceID)
        XCTAssertEqual(reloaded.title, "Changed again before reload", "Explicit reload must read the file, not just the cached collection")
        let review = try XCTUnwrap(store.tasks.first)
        var latest = freshReload, changed = freshReload["tasks"] as! [[String: Any]]
        changed[0]["linkedNoteIds"] = ["New supporting note"]; latest["tasks"] = changed
        let changedBytes = try JSONSerialization.data(withJSONObject: latest)
        try changedBytes.write(to: root!.appendingPathComponent(".zerus/tasks.json"), options: .atomic)
        let deleted = await store.saveTask(review, delete: true)
        XCTAssertFalse(deleted, "Deleting a stale task must not remove a newly linked note relationship")
        let unchanged = try await vault.read(".zerus/tasks.json"); XCTAssertEqual(unchanged, changedBytes)
    }
}
