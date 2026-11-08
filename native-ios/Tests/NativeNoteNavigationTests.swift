import XCTest
import Combine
@testable import ZerusNative

final class NativeNoteNavigationTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func files() async throws -> VaultFiles {
        let io = VaultFiles(root: root!)
        for name in ["A", "B", "C", "D"] { try await io.write(name + ".md", data: Data(("---\nzerus-id: " + name.lowercased() + "\n---\n# " + name + "\n\nOriginal " + name + ".").utf8), expected: nil) }
        return io
    }
    @MainActor
    func testHeadingReferencesKeepExactNamesAndCrossNoteVisitsCarryOnlyCurrentHeadingRequests() async throws {
        let io = try await files()
        try await io.write("C# Notes.md", data: Data("---\nzerus-id: sharp\n---\n# C# Notes\n".utf8), expected: nil)
        try await io.write("Hash.md", data: Data("---\nzerus-id: hash\n---\n# #Literal\n".utf8), expected: nil)
        let store = VaultStore(); await store.open(root)
        let literal = try XCTUnwrap(NoteReference(wikilink: "[[#Literal]]"))
        XCTAssertEqual(store.targets(for: literal).map(\.stableID), ["hash"])
        let a = try XCTUnwrap(store.notes.first { $0.stableID == "a" }), b = try XCTUnwrap(store.notes.first { $0.stableID == "b" })
        let reference = try XCTUnwrap(NoteReference(wikilink: "[[B#Details|Keep this label]]"))
        XCTAssertEqual(reference.targets(in: store.notes, includeHeadingFragments: true).map(\.stableID), ["b"]); XCTAssertEqual(reference.heading(in: b), "Details")
        XCTAssertTrue(reference.targets(in: store.notes).isEmpty, "Property and relation consumers retain exact-target semantics")
        let sharp = try XCTUnwrap(NoteReference(wikilink: "[[C# Notes]]"))
        XCTAssertEqual(sharp.targets(in: store.notes).map(\.stableID), ["sharp"])
        XCTAssertNil(sharp.heading(in: try XCTUnwrap(store.notes.first { $0.stableID == "sharp" })))
        let linked = await store.linkedNote("B.md#Details", notePath: a.path, workspace: store.workspaceID); XCTAssertEqual(linked?.stableID, "b")
        XCTAssertEqual(NoteReference.retarget("Follow [[B#Details|Keep this label]].", from: reference, to: "b", heading: reference.heading(in: b)), "Follow [[zerus:b#Details|Keep this label]].")
        let session = try XCTUnwrap(store.session(for: a)), navigation = NativeNoteNavigation(vault: store, session: session), first = navigation.current.id
        session.updateBody("# A\nSaved before heading navigation.")
        await navigation.open(b, from: first, heading: "Details")
        let visit = navigation.current.id, request = try XCTUnwrap(navigation.headingRequest(for: visit))
        XCTAssertEqual(request.fragment, "Details"); XCTAssertNil(navigation.headingRequest(for: first))
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("A.md"), encoding: .utf8).contains("Saved before heading navigation."))
        await navigation.open(b, from: visit, heading: "Details")
        XCTAssertEqual(navigation.path.count, 1); XCTAssertNotEqual(navigation.headingRequest(for: visit)?.id, request.id)
        let latest = navigation.headingRequest(for: visit)?.id
        await navigation.open(a, from: first, heading: "stale")
        XCTAssertEqual(navigation.current.id, visit); XCTAssertEqual(navigation.headingRequest(for: visit)?.id, latest)
        let other = root.appendingPathComponent("Other"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await store.open(other); XCTAssertNil(navigation.headingRequest(for: visit))
    }
    @MainActor
    func testVisitsSaveFollowRenamesBranchBackForwardAndProtectDeletedOrReplacedIdentities() async throws {
        let io = try await files()
        try await io.write("Legacy.md", data: Data("# Legacy\nOriginal legacy text.".utf8), expected: nil)
        let store = VaultStore(); await store.open(root)
        let legacy = try XCTUnwrap(store.session(for: XCTUnwrap(store.notes.first { $0.path == "Legacy.md" })))
        legacy.updateBody("# Legacy\nMy unsaved legacy draft.")
        try Data("# Legacy\nOutside legacy edit.".utf8).write(to: root.appendingPathComponent("Legacy.md"), options: .atomic)
        await legacy.save(); XCTAssertTrue(legacy.dirty); XCTAssertNotNil(legacy.failure)
        let recovered = NativeNoteNavigation(vault: store, session: legacy)
        XCTAssertTrue(recovered.editor(recovered.root) === legacy, "A failed first ID write must not hide the retained draft")
        XCTAssertTrue(legacy.document.content.contains("My unsaved legacy draft."))
        await legacy.reload()
        func note(_ name: String) throws -> NoteDocument { try XCTUnwrap(store.notes.first { $0.stableID == name.lowercased() }) }
        let session = try XCTUnwrap(store.session(for: note("A"))), navigation = NativeNoteNavigation(vault: store, session: session)
        session.updateBody("# A\nSaved before following B.")
        await navigation.open(try note("B"), from: navigation.current.id)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("A.md"), encoding: .utf8), "---\nzerus-id: a\n---\n# A\nSaved before following B.")
        let b = navigation.current
        await navigation.open(try note("C"), from: b.id)
        let c = navigation.current
        navigation.updatePath([b])
        XCTAssertEqual(navigation.current.id, b.id); XCTAssertEqual(navigation.forward.last?.id, c.id)
        let snapshot = try await store.relationDefinitionSnapshot(), rename = try await store.prepareRename(snapshot, source: "B.md", title: "Better B", renameFile: true)
        try await store.saveRelationMaintenance(rename.maintenance)
        XCTAssertEqual(navigation.title(b), "Better B"); XCTAssertEqual(navigation.editor(b)?.document.path, "Better B.md")
        await navigation.jump(to: c.id, from: b.id)
        XCTAssertEqual(navigation.current.id, c.id); XCTAssertTrue(navigation.forward.isEmpty)
        let currentEditor = try XCTUnwrap(navigation.editor(c)); currentEditor.updateBody("# C\nSaved before Back.")
        await navigation.jump(to: b.id, from: c.id)
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("C.md"), encoding: .utf8).hasSuffix("Saved before Back."))
        await navigation.open(try note("D"), from: b.id)
        XCTAssertTrue(navigation.forward.isEmpty, "Following a new link replaces the forward branch")
        let d = navigation.current
        await navigation.open(try note("A"), from: b.id)
        XCTAssertEqual(navigation.current.id, d.id, "A late callback from a hidden editor must not navigate the current screen")
        let bBeforeTrash = try note("B")
        let trashed = await store.move(bBeforeTrash, trash: true); XCTAssertTrue(trashed)
        XCTAssertNil(navigation.target(b)); XCTAssertNil(navigation.editor(b)); XCTAssertNil(store.session(for: bBeforeTrash))
        await navigation.jump(to: b.id, from: d.id)
        XCTAssertNil(navigation.target(navigation.current), "A native Back destination must show unavailable rather than recreate a trashed file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Better B.md").path))
        let deleted = try XCTUnwrap(store.notes.first { $0.trashed && $0.stableID == "b" })
        let restoredFile = await store.move(deleted, restore: true); XCTAssertTrue(restoredFile)
        var restored = try XCTUnwrap(navigation.editor(b))
        restored.updateBody("# Better B\nRestored editor still saves."); await restored.save()
        XCTAssertFalse(restored.dirty); XCTAssertNil(restored.failure)
        // Foreground refresh retains old path aliases for an externally moved
        // editor. Restoring that note must retire every alias of the old editor.
        let savedBeforeExternalTrash = try await io.read("Better B.md")
        try await io.move("Better B.md", to: ".trash/Better B.md", expected: savedBeforeExternalTrash)
        await store.refresh()
        let outsideTrash = try XCTUnwrap(store.notes.first { $0.path == ".trash/Better B.md" })
        let outsideRestored = await store.move(outsideTrash, restore: true); XCTAssertTrue(outsideRestored)
        restored = try XCTUnwrap(navigation.editor(b))
        XCTAssertEqual(restored.document.path, "Better B.md", "A restored editor must not read the removed Trash path through a retained alias")
        _ = try await store.revisionSnapshot(note: restored.document)
        restored.updateBody("# Better B\nRestored after an external move."); await restored.save()
        let savedAfterExternalTrash = try await io.read("Better B.md")
        XCTAssertTrue(String(decoding: savedAfterExternalTrash, as: UTF8.self).contains("Restored after an external move."))
        restored.updateBody("# Better B\nMy draft before an outside replacement.")
        // Replacing this path with another identified note must not retarget a
        // visit, even when foreground refresh reconciles the old cached editor.
        try Data("---\nzerus-id: replacement\n---\n# Different note\nKeep me.".utf8).write(to: root.appendingPathComponent("Better B.md"), options: .atomic)
        await store.refresh()
        XCTAssertNil(navigation.target(b)); XCTAssertEqual(navigation.title(b), "Better B")
        XCTAssertTrue(navigation.editor(b) === restored); XCTAssertTrue(restored.dirty)
        XCTAssertTrue(restored.document.content.contains("My draft before an outside replacement."))
        let replacement = try Data(contentsOf: root.appendingPathComponent("Better B.md"))
        await navigation.jump(to: navigation.root.id, from: b.id)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Better B.md")), replacement)
        await restored.reload()
        XCTAssertNil(navigation.target(b), "Explicitly reloading a replacement must not retarget an identified visit")
        let duplicate = root.appendingPathComponent("Copy A.md")
        try Data("---\nzerus-id: a\n---\n# Another A\nIndependent file.".utf8).write(to: duplicate)
        await store.refresh()
        let duplicateTarget = try note("A")
        XCTAssertNil(navigation.target(navigation.root)); XCTAssertNil(store.session(for: duplicateTarget))
        await navigation.open(duplicateTarget, from: navigation.current.id)
        XCTAssertTrue(navigation.issue?.contains("ambiguous") == true)
        XCTAssertEqual(navigation.current.id, navigation.root.id)
        try FileManager.default.removeItem(at: duplicate); await store.refresh()
        let other = root.appendingPathComponent("Other", isDirectory: true); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await store.open(other); await store.open(root)
        XCTAssertNil(navigation.target(navigation.root))
        let previousPath = navigation.path
        await navigation.open(try XCTUnwrap(store.notes.first { $0.stableID == "d" }), from: navigation.current.id)
        XCTAssertEqual(navigation.path, previousPath, "Returning to the same folder must not revive a previous activation’s history")
    }

    @MainActor
    func testARealSaveFinishingAfterNativeBackCannotPushItsDelayedDestination() async throws {
        _ = try await files(); let store = VaultStore(); await store.open(root)
        let a = try XCTUnwrap(store.notes.first { $0.stableID == "a" }), b = try XCTUnwrap(store.notes.first { $0.stableID == "b" }), c = try XCTUnwrap(store.notes.first { $0.stableID == "c" })
        let navigation = NativeNoteNavigation(vault: store, session: try XCTUnwrap(store.session(for: a)))
        await navigation.open(b, from: navigation.current.id)
        let visit = navigation.current, editor = try XCTUnwrap(navigation.editor(visit))
        let gate = FileWriteGate(url: root.appendingPathComponent("B.md")); defer { gate.release() }
        await fulfillment(of: [gate.acquired], timeout: 5)
        let began = expectation(description: "Navigation waits for the actual coordinated save")
        let observation = editor.$saving.filter { $0 }.prefix(1).sink { _ in began.fulfill() }; defer { observation.cancel() }
        editor.updateBody("# B\nTyped just before following C.")
        let open = Task { @MainActor in await navigation.open(c, from: visit.id) }
        await fulfillment(of: [began], timeout: 5)
        navigation.updatePath([])
        gate.release(); await open.value; await fulfillment(of: [gate.finished], timeout: 5)
        XCTAssertEqual(navigation.current.id, navigation.root.id); XCTAssertEqual(navigation.forward.last?.id, visit.id)
        XCTAssertFalse(navigation.opening)
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("B.md"), encoding: .utf8).hasSuffix("Typed just before following C."))
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("C.md"), encoding: .utf8).hasSuffix("Original C."))
    }
}
