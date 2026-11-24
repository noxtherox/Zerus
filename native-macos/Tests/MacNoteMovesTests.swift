import XCTest
@testable import Zerus_Native

@MainActor final class MacNoteMovesTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    func testBatchMoveComposesReciprocalRelationsBodyLinksResourcesAndOpenNavigation() async throws {
        let schema = #"{"metadata":{"keep":true},"Source":[{"name":"Related","type":"relation","relationTypeKey":"Source","relationMultiple":true,"relationInverseName":"Related","relationPairId":"paired","foreignFlag":42}]}"#
        try await fixture([
            "Source/A.md": "---\nzerus-id: a\nRelated: [\"zerus:b|B\"]\nforeign: {keep: [1, 2]} # retained\n---\n# A\n\n[B](B.md) and ![Plot](../assets/plot.png).\n",
            "Source/B.md": "---\nzerus-id: b\nRelated: [\"zerus:a|A\"]\n---\n# B\n\nBack to [[zerus:a|A]].\n",
            "Watch.md": "# Watch\n\n[A](Source/A.md) and [[Source/B|B]].\n",
            ".zerus/properties.json": schema,
        ]) { root, workspace in
            await workspace.openNote("Source/A.md"); await workspace.openNote("Source/B.md", newTab: true)
            workspace.selectedPaths = ["Source/A.md", "Source/B.md"]
            let review = try await workspace.prepareNoteMoves(paths: workspace.selectedPaths, folder: "Deep/Nested", workspaceID: workspace.workspaceID)
            XCTAssertEqual(review.moves.count, 2); XCTAssertTrue(review.skipped.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Source/A.md").path)); XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Deep/Nested/A.md").path))
            let result = try await workspace.commitNoteMoves(review)
            XCTAssertEqual(result.moved.count, 2); XCTAssertTrue(result.failed.isEmpty); XCTAssertTrue(workspace.selectedPaths.isEmpty)
            let a = try XCTUnwrap(workspace.notes.first { $0.path == "Deep/Nested/A.md" }), b = try XCTUnwrap(workspace.notes.first { $0.path == "Deep/Nested/B.md" })
            XCTAssertEqual(a.created, Date(timeIntervalSince1970: 1_600_000_000)); XCTAssertEqual(b.created, Date(timeIntervalSince1970: 1_600_000_000))
            XCTAssertEqual(a.stableID, "a"); XCTAssertEqual(b.stableID, "b"); XCTAssertTrue(a.content.contains("foreign: {keep: [1, 2]} # retained"))
            XCTAssertTrue(a.property("Related")?.contains("zerus:b") == true); XCTAssertTrue(b.property("Related")?.contains("zerus:a") == true)
            for reference in MarkdownResources.localReferences(in: a.parts.body, includeNoteFiles: true) { XCTAssertNoThrow(try VaultFiles.resolveResource(reference, notePath: a.path, root: root)) }
            let plot = try XCTUnwrap(MarkdownText.imageReferences(a.parts.body).first)
            XCTAssertEqual(try VaultFiles.resolveResource(plot, notePath: a.path, root: root), root.appendingPathComponent("assets/plot.png"))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/plot.png")), self.png)
            let watch = try XCTUnwrap(workspace.notes.first { $0.path == "Watch.md" })
            XCTAssertEqual(watch.created, Date(timeIntervalSince1970: 1_600_000_000))
            XCTAssertFalse(watch.parts.body.contains("Source/A.md")); XCTAssertFalse(watch.parts.body.contains("[[Source/B|"))
            XCTAssertTrue(workspace.tabs.contains(.note(a.path))); XCTAssertTrue(workspace.tabs.contains(.note(b.path))); XCTAssertEqual(workspace.selection, b.path)
            await workspace.historyStep(-1); XCTAssertEqual(workspace.selection, a.path)
            await workspace.follow("./B.md")
            XCTAssertEqual(workspace.selection, b.path)
            await workspace.openNote("Watch.md", newTab: true)
            await workspace.follow("./Deep/Nested/A.md")
            XCTAssertEqual(workspace.selection, a.path)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/properties.json"))) as? [String: Any]
            XCTAssertEqual((object?["metadata"] as? [String: Bool])?["keep"], true)
            let forwardNotes = Dictionary(uniqueKeysWithValues: result.snapshot.notes.map { ($0.path, $0.content) })
            let forwardSchema = try Data(contentsOf: root.appendingPathComponent(".zerus/properties.json"))
            let record = try XCTUnwrap(result.undoRecord)
            let peer = MacWorkspace(); await peer.openVault(root); await peer.openNote("Deep/Nested/B.md")
            let io = try XCTUnwrap(workspace.io)
            let damagedName = UUID().uuidString.lowercased() + ".json"
            try Data("{damaged".utf8).write(to: root.appendingPathComponent(".zerus/mac-move-history/" + damagedName))
            let saved = try await io.macNoteMoveHistory()
            XCTAssertEqual(saved.records.map(\.id), [record.id])
            XCTAssertTrue(saved.issues.contains { $0.contains(damagedName) })
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(".zerus/mac-move-history/" + damagedName), encoding: .utf8), "{damaged")
            let undo = try await peer.prepareNoteMoveHistory(record.id)
            XCTAssertTrue(undo.noteChanges.contains { $0.path == "Watch.md" })
            XCTAssertTrue(undo.settingChanges.contains { $0.path == ".zerus/properties.json" })
            try await peer.commitNoteMoveHistory(undo)
            XCTAssertEqual(peer.selection, "Source/B.md"); XCTAssertEqual(workspace.selection, "Source/A.md")
            XCTAssertTrue(workspace.tabs.contains(.note("Source/B.md")))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Deep/Nested/A.md").path))
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(".zerus/properties.json"), encoding: .utf8), schema)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Watch.md"), encoding: .utf8), "# Watch\n\n[A](Source/A.md) and [[Source/B|B]].\n")
            XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("Source/A.md"), encoding: .utf8).contains("[B](B.md) and ![Plot](../assets/plot.png)."))
            XCTAssertEqual(workspace.notes.first { $0.path == "Source/A.md" }?.created, Date(timeIntervalSince1970: 1_600_000_000))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/plot.png")), self.png)
            let undone = try await io.macNoteMoveHistory(); XCTAssertTrue(try XCTUnwrap(undone.records.first).undone)
            do { try await workspace.commitNoteMoveHistory(undo); XCTFail("Undo must not apply twice") } catch {}
            let redo = try await peer.prepareNoteMoveHistory(record.id, undo: false)
            XCTAssertFalse(redo.undo)
            try await peer.commitNoteMoveHistory(redo)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: workspace.notes.map { ($0.path, $0.content) }), forwardNotes)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/properties.json")), forwardSchema)
            XCTAssertEqual(peer.selection, "Deep/Nested/B.md"); XCTAssertEqual(workspace.selection, "Deep/Nested/A.md")
            XCTAssertTrue(workspace.tabs.contains(.note("Deep/Nested/B.md")))
            XCTAssertEqual(workspace.notes.first { $0.path == "Deep/Nested/A.md" }?.created, Date(timeIntervalSince1970: 1_600_000_000))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("assets/plot.png")), self.png)
            let redoneRecords = try await io.macNoteMoveHistory()
            XCTAssertFalse(try XCTUnwrap(redoneRecords.records.first).undone)
            do { try await workspace.commitNoteMoveHistory(redo); XCTFail("Redo must not apply twice") } catch {}
            let secondUndo = try await peer.prepareNoteMoveHistory(record.id)
            try await peer.commitNoteMoveHistory(secondUndo)
            XCTAssertEqual(workspace.selection, "Source/A.md")
        }
    }
    func testMovesSuggestIconsOnlyForNewSuccessfulDestinationsAndKeepSharedMetadata() async throws {
        let icons = #"{"Recipes/Travel":"tabler:Heart","Café":"☕","Cafe\u0301":"🧠","future":{"text":"\uFEFFkeep"}}"#
        try await fixture(["Source/A.md": "---\nzerus-id: a\n---\n# A\n", "Work/B.md": "---\nzerus-id: b\n---\n# B\n", ".zerus/type-icons.json": icons]) { root, workspace in
            let peer = MacWorkspace(); await peer.openVault(root)
            let review = try await workspace.prepareNoteMoves(paths: ["Source/A.md"], folder: "Recipes/Travel", workspaceID: workspace.workspaceID)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/type-icons.json")), Data(icons.utf8), "Review never writes suggestions")
            let result = try await workspace.commitNoteMoves(review)
            XCTAssertEqual(result.moved.map(\.destination), ["Recipes/Travel/A.md"]); XCTAssertTrue(result.failed.isEmpty)
            XCTAssertEqual(workspace.folderIcon("Recipes"), "tabler:ChefHat"); XCTAssertEqual(peer.folderIcon("Recipes"), "tabler:ChefHat")
            XCTAssertEqual(workspace.folderIcon("Recipes/Travel"), "tabler:Heart", "An existing override wins even before its folder exists")
            XCTAssertNil(workspace.folderIcon("Work"), "Existing uncustomized folders are not suggested retroactively")
            let expected = String(icons.dropLast()) + ",\n  \"Recipes\": \"tabler:ChefHat\"}"
            let actual = try Data(contentsOf: root.appendingPathComponent(".zerus/type-icons.json"))
            XCTAssertEqual(actual, Data(expected.utf8), "Only the new ancestor's icon token is inserted")
            let record = try XCTUnwrap(result.undoRecord)
            for undo in [true, false] { let history = try await workspace.prepareNoteMoveHistory(record.id, undo: undo); try await workspace.commitNoteMoveHistory(history); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/type-icons.json")), actual) }
            let stale = try await workspace.prepareNoteMoves(paths: ["Work/B.md"], folder: "Finance", workspaceID: workspace.workspaceID)
            try Data("# Outside edit\n".utf8).write(to: root.appendingPathComponent("Work/B.md"))
            let failed = try await workspace.commitNoteMoves(stale)
            XCTAssertTrue(failed.moved.isEmpty); XCTAssertEqual(failed.failed.count, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Finance").path))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/type-icons.json")), actual, "A refused move creates no suggestions")
        }
    }
    func testBatchMoveNumbersCollisionsAndReportsSkippedSourcesWithoutOverwriting() async throws {
        try await fixture([
            "Source/A.md": "---\nzerus-id: one\n---\n# A\n",
            "Other/A.md": "---\nzerus-id: two\n---\n# Other A\n",
            "Destination/A.md": "---\nzerus-id: existing\n---\n# Existing\n",
            "Source/Missing.md": "# Missing file\n\n![Missing](../assets/not-there.png)\n",
        ]) { root, workspace in
            let before = try Data(contentsOf: root.appendingPathComponent("Destination/A.md")), skipped = try Data(contentsOf: root.appendingPathComponent("Source/Missing.md"))
            workspace.selectedPaths = ["Source/A.md", "Other/A.md", "Destination/A.md", "Source/Missing.md"]
            let review = try await workspace.prepareNoteMoves(paths: workspace.selectedPaths, folder: "Destination", workspaceID: workspace.workspaceID)
            XCTAssertEqual(Set(review.moves.map(\.destination)), ["Destination/A 2.md", "Destination/A 3.md"])
            XCTAssertEqual(Set(review.skipped.map(\.path)), ["Destination/A.md", "Source/Missing.md"])
            let result = try await workspace.commitNoteMoves(review)
            XCTAssertEqual(result.moved.count, 2); XCTAssertEqual(result.skipped.count, 2); XCTAssertTrue(result.failed.isEmpty)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Destination/A.md")), before)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Source/Missing.md")), skipped)
            XCTAssertEqual(workspace.selectedPaths, ["Destination/A.md", "Source/Missing.md"])
        }
    }
    func testOutsideEditsRecoveryDraftsAndOldWorkspaceReviewsCannotSilentlyMoveNotes() async throws {
        try await fixture(["Source/A.md": "---\nzerus-id: a\n---\n# A\n\nOriginal.\n", "Source/B.md": "---\nzerus-id: b\n---\n# B\n"]) { root, workspace in
            await workspace.openNote("Source/A.md")
            let paths: Set<String> = ["Source/A.md", "Source/B.md"]
            let review = try await workspace.prepareNoteMoves(paths: paths, folder: "Destination", workspaceID: workspace.workspaceID)
            let file = root.appendingPathComponent("Source/B.md"), changed = try Data(contentsOf: file) + Data("\nOutside edit.\n".utf8); try changed.write(to: file)
            let result = try await workspace.commitNoteMoves(review)
            XCTAssertTrue(result.moved.isEmpty); XCTAssertEqual(result.failed.count, 2); XCTAssertEqual(try Data(contentsOf: file), changed)
            let peer = MacWorkspace(); await peer.openVault(root); await peer.openNote("Source/A.md")
            let originalBody = peer.body
            peer.changed(originalBody + "\nPrivate retained draft.\n")
            let a = root.appendingPathComponent("Source/A.md"), outsideA = try Data(contentsOf: a) + Data("\nOutside A.\n".utf8); try outsideA.write(to: a)
            let saved = await peer.save(); XCTAssertFalse(saved)
            let privateDraft = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/Drafts/" + NativeHistory.hash(root.standardizedFileURL.path + "/Source/A.md") + ".json")
            defer { peer.changed(originalBody); try? FileManager.default.removeItem(at: privateDraft); for file in (try? MacNoteRecoveryStore.locations(root: root, path: "Source/A.md")) ?? [] { try? FileManager.default.removeItem(at: file) } }
            let guarded = try await workspace.prepareNoteMoves(paths: paths, folder: "Destination", workspaceID: workspace.workspaceID)
            XCTAssertEqual(guarded.moves.map(\.source), ["Source/B.md"])
            XCTAssertTrue(guarded.skipped.contains { $0.path == "Source/A.md" && $0.reason.contains("recovery draft") })
            await workspace.openVault(root)
            do { _ = try await workspace.commitNoteMoves(guarded); XCTFail("A previous activation's move review must not apply") } catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
            XCTAssertEqual(try Data(contentsOf: a), outsideA); XCTAssertEqual(try Data(contentsOf: file), changed)
        }
    }
    func testAnotherWindowCheckpointAppearingAfterReviewBlocksTheMove() async throws {
        try await fixture(["Source/A.md": "# A\n\nOriginal.\n"]) { root, workspace in
            let peer = MacWorkspace(); await peer.openVault(root); await peer.openNote("Source/A.md")
            let review = try await workspace.prepareNoteMoves(paths: ["Source/A.md"], folder: "Destination", workspaceID: workspace.workspaceID)
            XCTAssertEqual(review.moves.count, 1)
            peer.changed("# A\n\nText in another window.\n")
            do { _ = try await workspace.commitNoteMoves(review); XCTFail("Dirty peer must block the batch") } catch { XCTAssertTrue(error.localizedDescription.contains("drafts")) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Source/A.md").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Destination/A.md").path))
            _ = await peer.save()
        }
    }
    func testSingleNoteMoveRebasesResourcesAndIncomingBodyLinks() async throws {
        try await fixture(["Source/A.md": "---\nzerus-id: a\n---\n# A\n\n![Plot](../assets/plot.png)\n", "Watch.md": "# Watch\n\n[A](Source/A.md)\n"]) { root, workspace in
            let note = try XCTUnwrap(workspace.notes.first { $0.path == "Source/A.md" })
            await workspace.move(note, folder: "Deep/Nested")
            XCTAssertNil(workspace.issue)
            let moved = try XCTUnwrap(workspace.notes.first { $0.path == "Deep/Nested/A.md" }), reference = try XCTUnwrap(MarkdownText.imageReferences(moved.parts.body).first)
            XCTAssertEqual(try VaultFiles.resolveResource(reference, notePath: moved.path, root: root), root.appendingPathComponent("assets/plot.png"))
            XCTAssertFalse(try XCTUnwrap(workspace.notes.first { $0.path == "Watch.md" }).parts.body.contains("Source/A.md"))
        }
    }
    func testMoveHistoryRejectsLaterWorkStaleReviewsAndRetainedDraftsWithoutWriting() async throws {
        for undoing in [true, false] {
            for hazard in ["later edit", "occupied path", "settings", "review edit", "private draft", "reopen", "peer draft", "symlink occupant", "receipt path", "new incoming link"] {
                try await fixture(["Source/A.md": "---\nzerus-id: a\n---\n# A\n\nOriginal.\n", "Watch.md": "# Watch\n\n[A](Source/A.md)\n"]) { root, workspace in
                    let review = try await workspace.prepareNoteMoves(paths: ["Source/A.md"], folder: "Destination", workspaceID: workspace.workspaceID)
                    let moved = try await workspace.commitNoteMoves(review), record = try XCTUnwrap(moved.undoRecord)
                    if !undoing {
                        let undo = try await workspace.prepareNoteMoveHistory(record.id)
                        try await workspace.commitNoteMoveHistory(undo)
                    }
                    let active = undoing ? "Destination/A.md" : "Source/A.md"
                    let occupied = undoing ? "Source/A.md" : "Destination/A.md"
                    let a = root.appendingPathComponent(active), watch = root.appendingPathComponent("Watch.md")
                    let undo = try await workspace.prepareNoteMoveHistory(record.id, undo: undoing)
                    let peer = MacWorkspace(); await peer.openVault(root); await peer.openNote(active)
                    if hazard == "peer draft" { peer.changed(peer.body + "\nPrivate peer work.\n") }
                    var retained: URL?
                    if hazard == "later edit" || hazard == "review edit" { try Data("# Watch\n\nNew work.\n".utf8).write(to: watch) }
                    if hazard == "occupied path" { try Data("# New source occupant\n".utf8).write(to: root.appendingPathComponent(occupied)) }
                    if hazard == "symlink occupant" { try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent(occupied).path, withDestinationPath: root.appendingPathComponent("assets/plot.png").path) }
                    if hazard == "new incoming link" { try Data(("# Later reference\n\n[A](" + active + ")\n").utf8).write(to: root.appendingPathComponent("New.md")) }
                    if hazard == "receipt path" { let file = root.appendingPathComponent(record.path); var bad = try JSONDecoder().decode(MacNoteMoveRecord.self, from: Data(contentsOf: file)); bad.changes.append(.init(path: "unrelated.txt", before: nil, after: Data("Unreviewed".utf8))); try JSONEncoder().encode(bad).write(to: file) }
                    if hazard == "settings" { try Data("{\"keep\":42}".utf8).write(to: root.appendingPathComponent(".zerus/properties.json")) }
                    if hazard == "private draft" { try MacNoteRecoveryStore.checkpoint(root: root, note: NoteDocument(path: active, content: String(contentsOf: a, encoding: .utf8), modified: Date()), body: "# Private unsaved text", windowID: "undo-test"); retained = MacNoteRecoveryStore.location(root: root.resolvingSymlinksInPath(), path: active, windowID: "undo-test") }
                    if hazard == "reopen" { await workspace.openVault(root) }
                    defer { if let retained { try? FileManager.default.removeItem(at: retained) } }
                    let beforeA = try Data(contentsOf: a), beforeWatch = try Data(contentsOf: watch), receipt = try Data(contentsOf: root.appendingPathComponent(record.path))
                    let reason: String
                    switch hazard {
                    case "settings": reason = ".zerus/properties.json"
                    case "private draft": reason = "retained draft"
                    case "peer draft": reason = "draft"
                    case "reopen": reason = "vault changed"
                    case "receipt path": reason = "receipt is invalid"
                    default: reason = "changed"
                    }
                    if ["later edit", "occupied path", "settings", "symlink occupant", "receipt path", "new incoming link"].contains(hazard) {
                        do { _ = try await workspace.prepareNoteMoveHistory(record.id, undo: undoing); XCTFail(hazard) } catch { XCTAssertTrue(error.localizedDescription.lowercased().contains(reason), hazard + ": " + error.localizedDescription) }
                    } else { do { try await workspace.commitNoteMoveHistory(undo); XCTFail(hazard) } catch { XCTAssertTrue(error.localizedDescription.lowercased().contains(reason), hazard + ": " + error.localizedDescription) } }
                    if hazard == "private draft" {
                        do { _ = try await workspace.prepareNoteMoveHistory(record.id, undo: undoing); XCTFail("Draft must block preparation too") } catch { XCTAssertTrue(error.localizedDescription.contains("retained draft")) }
                    }
                    XCTAssertEqual(try Data(contentsOf: a), beforeA, hazard); XCTAssertEqual(try Data(contentsOf: watch), beforeWatch, hazard)
                    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(record.path)), receipt, hazard)
                    XCTAssertFalse(workspace.noteMovesSaving, hazard)
                    if let retained { XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path), hazard) }
                    if hazard == "peer draft" { XCTAssertTrue(peer.body.contains("Private peer work.")); _ = await peer.save() }
                }
        }
        }
    }
    func testPartialBatchReceiptCanUndoOnlyCompletedMovesAfterRestart() async throws {
        try await fixture(["Source/A.md": "# A\n", "Source/B.md": "# B\n"]) { root, workspace in
            let review = try await workspace.prepareNoteMoves(paths: ["Source/A.md", "Source/B.md"], folder: "Destination", workspaceID: workspace.workspaceID)
            let io = try XCTUnwrap(workspace.io), b = root.appendingPathComponent("Source/B.md"), originalB = try Data(contentsOf: b)
            let result = try await io.applyMacNoteMoves(review) { done, _ in if done == 1 { try? Data("# B\n\nOutside change.\n".utf8).write(to: b) } }
            XCTAssertEqual(result.moved.map(\.source), ["Source/A.md"]); XCTAssertEqual(result.failed.map(\.path), ["Source/B.md"])
            let record = try XCTUnwrap(result.undoRecord); XCTAssertEqual(record.moves.count, 1)
            try originalB.write(to: b)
            let reopened = MacWorkspace(); await reopened.openVault(root)
            let undo = try await reopened.prepareNoteMoveHistory(record.id)
            try await reopened.commitNoteMoveHistory(undo)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Source/A.md"), encoding: .utf8), "# A\n")
            XCTAssertEqual(try Data(contentsOf: b), originalB)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Destination/A.md").path))
            let restarted = MacWorkspace(); await restarted.openVault(root)
            let redo = try await restarted.prepareNoteMoveHistory(record.id, undo: false)
            try await restarted.commitNoteMoveHistory(redo)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Destination/A.md"), encoding: .utf8), "# A\n")
            XCTAssertEqual(try Data(contentsOf: b), originalB)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Destination/B.md").path))
        }
    }
    func testMoveHistoryPreservesUnrelatedBomBytesAndDoesNotTouchAnUnrelatedPrivateDraft() async throws {
        for variant in ["BOM", "unrelated draft", "unrelated edit", "new unrelated note", "new stable link"] {
            do {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-raw-move-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: root.appendingPathComponent("Source"), withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: root) }
                try Data("# A\n".utf8).write(to: root.appendingPathComponent("Source/A.md"))
                let file = root.appendingPathComponent("Unrelated.md")
                var before = Data("# Unrelated\n".utf8); try before.write(to: file)
                if variant == "new stable link" { try Data("# Watch\n\n[[Source/A|A]]\n".utf8).write(to: root.appendingPathComponent("Watch.md")) }
                let io = VaultFiles(root: root), workspaceID = UUID()
                let move = try await io.prepareMacNoteMoves(paths: ["Source/A.md"], folder: "Destination", workspaceID: workspaceID, recoveryDrafts: [:])
                let result = try await io.applyMacNoteMoves(move) { _, _ in }, record = try XCTUnwrap(result.undoRecord)
                if variant == "new stable link" {
                    let id = try XCTUnwrap(result.snapshot.notes.first { $0.path == "Destination/A.md" }?.stableID)
                    let later = Data(("# New\n\n[[zerus:" + id + "|A]]\n").utf8), path = root.appendingPathComponent("New.md")
                    try later.write(to: path)
                    do { _ = try await io.prepareMacNoteMoveHistory(record.id, undo: true, workspaceID: workspaceID); XCTFail("Undo must not remove an identity used by a new link") }
                    catch { XCTAssertTrue(error.localizedDescription.contains("changed"), error.localizedDescription) }
                    XCTAssertEqual(try Data(contentsOf: path), later)
                    continue
                }
                // An external editor can add a BOM without changing scanned text.
                if variant == "BOM" { before = Data([0xEF, 0xBB, 0xBF]) + before; try before.write(to: file) }
                if variant == "unrelated edit" { before = Data("# Unrelated\n\nLater writing café.\n".utf8); try before.write(to: file) }
                let added = root.appendingPathComponent("New.md"), addedBytes = Data("# Later note\n\nKeep new writing.\n".utf8)
                if variant == "new unrelated note" { try addedBytes.write(to: added) }
                let draft = MacNoteRecoveryStore.location(root: root.resolvingSymlinksInPath(), path: "Unrelated.md", windowID: "move-unrelated")
                defer { try? FileManager.default.removeItem(at: draft) }
                if variant == "unrelated draft" {
                    let note = NoteDocument(path: "Unrelated.md", content: String(decoding: before, as: UTF8.self), modified: Date())
                    try MacNoteRecoveryStore.checkpoint(root: root, note: note, body: "# Private unrelated work\n", windowID: "move-unrelated")
                }
                for undo in [true, false] {
                    let review = try await io.prepareMacNoteMoveHistory(record.id, undo: undo, workspaceID: workspaceID)
                    _ = try await io.applyMacNoteMoveHistory(review)
                    XCTAssertEqual(try Data(contentsOf: file), before, variant)
                    if variant == "new unrelated note" { XCTAssertEqual(try Data(contentsOf: added), addedBytes) }
                    if variant == "unrelated draft" { XCTAssertTrue(FileManager.default.fileExists(atPath: draft.path)) }
                }
                XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Destination/A.md").path))
            } catch { XCTFail(variant + " must not block move history: " + error.localizedDescription) }
        }
    }
    private func fixture(_ notes: [String: String], operation: (URL, MacWorkspace) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-note-moves-" + UUID().uuidString), defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        for (path, text) in notes { let file = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(text.utf8).write(to: file); try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: file.path) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true); try png.write(to: root.appendingPathComponent("assets/plot.png"))
        let workspace = MacWorkspace(); await workspace.openVault(root); let drafts = workspace.taskDraftStore?.directory
        defer { if let drafts { try? FileManager.default.removeItem(at: drafts) }; defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path)); try? FileManager.default.removeItem(at: root) }
        try await operation(root, workspace)
    }
}
