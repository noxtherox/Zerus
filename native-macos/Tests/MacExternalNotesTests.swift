import XCTest
import AppKit
import SwiftUI
@testable import Zerus_Native

@MainActor final class MacExternalNotesTests: XCTestCase {
    func testExternalBlockControlsCommitToTheConnectedFileAndKeepUndoAndStaleDrafts() async throws {
        for fullSource in [false, true] { for ending in ["\n", "\r\n"] {
            try await withFiles { source, registry in
                let header = "---\nforeign: preserved # do not rewrite\n---\n".replacingOccurrences(of: "\n", with: ending)
                let body = ((fullSource ? "<details>\nforeign block\n</details>\n\n" : "") + "# External\n\n| Name |\n| --- |\n| Old |\n\n```swift\nlet n = 1\n```\n").replacingOccurrences(of: "\n", with: ending)
                let original = header + body, bom = Data([0xef, 0xbb, 0xbf])
                try (bom + Data(original.utf8)).write(to: source)
                let library = MacExternalLibrary(directory: registry); await library.open(source)
                let session = try XCTUnwrap(library.selected)
                let workspace = MacWorkspace()
                let host = NSHostingView(rootView: MacExternalEditor(workspace: workspace, library: library, session: session))
                let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1150, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
                defer { window.contentView = nil; window.close() }
                for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
                func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
                let editor = try XCTUnwrap(nodes(host).compactMap { $0 as? NSTextView }.first { $0.isEditable })
                XCTAssertNotNil(nodes(host).compactMap { $0 as? NSPopUpButton }.first { $0.toolTip == "Tables and code" }, "External notes expose the shared block sheets")
                window.makeFirstResponder(editor)
                let initial = fullSource ? original : body
                let block = try XCTUnwrap(MacCodeBlock.blocks(in: initial).first)
                let request = MacCodeRequest(workspaceID: session.presentationID, path: session.snapshot.entry.name, source: initial, range: block.range, code: block.code)
                let replacement = "```python\nvalue = 2\n```".replacingOccurrences(of: "\n", with: ending)
                let command = MacCodeChange(request: request, replacement: replacement)
                NotificationCenter.default.post(name: .macEditorAction, object: command)
                guard let result = command.result else { XCTFail("External editor did not receive its scoped code command"); _ = await library.close(); return }
                try result.get()
                let codeSaved = original.replacingOccurrences(of: "```swift" + ending + "let n = 1" + ending + "```", with: replacement)
                await session.save(); XCTAssertNil(session.failure)
                XCTAssertEqual(try Data(contentsOf: source), bom + Data(codeSaved.utf8))
                @MainActor func send(_ action: String) { NotificationCenter.default.post(name: .macEditorAction, object: MacEditorCommand(scope: session.presentationID, path: session.snapshot.entry.name, action: action)) }
                send("undo"); await session.save(); XCTAssertEqual(try Data(contentsOf: source), bom + Data(original.utf8))
                send("redo"); await session.save(); XCTAssertEqual(try Data(contentsOf: source), bom + Data(codeSaved.utf8))
                let stale = MacCodeChange(request: request, replacement: "```\nwrong\n```")
                NotificationCenter.default.post(name: .macEditorAction, object: stale)
                XCTAssertThrowsError(try XCTUnwrap(stale.result).get()) { XCTAssertTrue($0.localizedDescription.contains("note changed")) }
                let current = fullSource ? session.document.content : session.document.parts.body
                let table = try XCTUnwrap(MacMarkdown.tables(in: current).first)
                let tableReplacement = "| Name |\n| --- |\n| New |".replacingOccurrences(of: "\n", with: ending)
                let tableCommand = MacTableChange(request: .init(workspaceID: session.presentationID, path: session.snapshot.entry.name, source: current, range: table.range, table: table.table), replacement: tableReplacement)
                NotificationCenter.default.post(name: .macEditorAction, object: tableCommand)
                try XCTUnwrap(tableCommand.result).get()
                let final = codeSaved.replacingOccurrences(of: "| Old |", with: "| New |")
                await session.save(); XCTAssertEqual(try Data(contentsOf: source), bom + Data(final.utf8))
                send("undo"); await session.save(); XCTAssertEqual(try Data(contentsOf: source), bom + Data(codeSaved.utf8))
                send("redo"); await session.save(); XCTAssertEqual(try Data(contentsOf: source), bom + Data(final.utf8))
                let closed = await library.close(); XCTAssertTrue(closed)
                let retired = MacTableChange(request: tableCommand.request, replacement: tableReplacement)
                NotificationCenter.default.post(name: .macEditorAction, object: retired)
                XCTAssertNil(retired.result, "A closed external editor cannot accept a queued sheet command")
                XCTAssertEqual(try Data(contentsOf: source), bom + Data(final.utf8))
            }
        } }
    }

    func testDoubleBomConnectedDraftIsCleanUntilTextChanges() async throws {
        try await withFiles { source, registry in
            let bytes = Data("\u{feff}\u{feff}# External\n\nOriginal.\n".utf8)
            try bytes.write(to: source)
            let library = MacExternalLibrary(directory: registry); await library.open(source)
            let session = try XCTUnwrap(library.selected)
            await session.retry() // Persist the clean baseline through the normal recovery path.
            let original = try await library.store.draft(session.id)
            XCTAssertFalse(try XCTUnwrap(original).hasUnsavedChanges)
            session.changeBody(session.document.parts.body.replacingOccurrences(of: "Original", with: "Edited"))
            await session.save(); XCTAssertNil(session.failure); XCTAssertFalse(session.dirty)
            XCTAssertEqual(try Data(contentsOf: source), Data("\u{feff}\u{feff}# External\n\nEdited.\n".utf8))
            let savedDraft = try await library.store.draft(session.id)
            XCTAssertFalse(try XCTUnwrap(savedDraft).hasUnsavedChanges)
            _ = await library.close()
        }
    }

    func testOriginalFileEditingPreservesHeaderEncodingAndSavedConnectionAcrossRestart() async throws {
        try await withFiles { source, registry in
            let original = "---\r\nforeign: {keep: [1, 2]} # retained\r\n---\r\n# External\r\n\r\nOriginal body.\r\n"
            let bom = Data([0xef, 0xbb, 0xbf]); try (bom + Data(original.utf8)).write(to: source)
            let library = MacExternalLibrary(directory: registry)
            await library.open(source)
            let session = try XCTUnwrap(library.selected), id = session.id
            XCTAssertNil(library.issue)
            session.changeBody(session.document.parts.body.replacingOccurrences(of: "Original", with: "First"))
            let firstSave = Task { await session.save() }
            await Task.yield()
            session.changeBody(session.document.parts.body.replacingOccurrences(of: "First", with: "Latest"))
            await firstSave.value; await session.save()
            XCTAssertFalse(session.dirty)
            XCTAssertNil(session.failure)
            let saved = try Data(contentsOf: source)
            XCTAssertEqual(saved, bom + Data(original.replacingOccurrences(of: "Original", with: "Latest").utf8))
            XCTAssertFalse(session.document.content.contains("zerus-id:"))
            let closed = await library.close(); XCTAssertTrue(closed)
            session.changeBody("A stale closed editor must not write.")
            let restarted = MacExternalLibrary(directory: registry); await restarted.restore()
            XCTAssertEqual(restarted.entries.count, 1)
            await restarted.open(try XCTUnwrap(restarted.entries.first))
            let reopened = try XCTUnwrap(restarted.selected)
            XCTAssertEqual(reopened.id, id); XCTAssertFalse(reopened.dirty); XCTAssertFalse(reopened.conflict)
            XCTAssertTrue(reopened.document.content.contains("Latest body."))
            XCTAssertEqual(try Data(contentsOf: source), saved)
            _ = await restarted.close()
        }
    }
    func testOutsideEditRetainsRecoverableDraftAndFailedReloadDoesNotDiscardIt() async throws {
        try await withFiles { source, registry in
            let original = "# External\n\nOriginal.\n"; try Data(original.utf8).write(to: source)
            let library = MacExternalLibrary(directory: registry); await library.open(source)
            let session = try XCTUnwrap(library.selected)
            session.changeBody("# External\n\nMy unsaved draft.\n")
            let outside = "# External\n\nOutside change.\n"; try Data(outside.utf8).write(to: source)
            await session.save()
            XCTAssertTrue(session.dirty); XCTAssertTrue(session.conflict); XCTAssertNotNil(session.failure)
            XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), outside)
            let closed = await library.close(); XCTAssertTrue(closed)
            let restarted = MacExternalLibrary(directory: registry); await restarted.restore(); await restarted.open(try XCTUnwrap(restarted.entries.first))
            let recovered = try XCTUnwrap(restarted.selected)
            XCTAssertTrue(recovered.document.content.contains("My unsaved draft.")); XCTAssertTrue(recovered.conflict)
            let recoveryBefore = try await restarted.store.draft(recovered.id)
            try FileManager.default.removeItem(at: source)
            do { try await recovered.reloadDiscardingDraft(); XCTFail("An unavailable original must not discard the draft") } catch {}
            XCTAssertTrue(recovered.document.content.contains("My unsaved draft."))
            let recoveryAfter = try await restarted.store.draft(recovered.id)
            XCTAssertEqual(recoveryAfter?.content, recoveryBefore?.content); XCTAssertEqual(recoveryAfter?.baseline, recoveryBefore?.baseline)
            await restarted.forget(try XCTUnwrap(restarted.entries.first))
            XCTAssertNotNil(restarted.issue); XCTAssertEqual(restarted.entries.count, 1)
            try Data(outside.utf8).write(to: source)
            try await recovered.reloadDiscardingDraft()
            XCTAssertEqual(recovered.document.content, outside); XCTAssertFalse(recovered.dirty)
            _ = await restarted.close(); await restarted.forget(try XCTUnwrap(restarted.entries.first))
            XCTAssertTrue(restarted.entries.isEmpty); XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), outside)
        }
    }
    func testExternalImagePasteUsesChosenProjectAndKeepsOriginalEncodingUndoAndReopenedAccess() async throws {
        try await withFiles { source, registry in
            let original = "---\r\nforeign: preserved\r\n---\r\n# External\r\n\r\nBefore target after.\r\n", bom = Data([0xef, 0xbb, 0xbf])
            try (bom + Data(original.utf8)).write(to: source)
            let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
            let library = MacExternalLibrary(directory: registry); await library.open(source)
            let session = try XCTUnwrap(library.selected), root = source.deletingLastPathComponent()
            let parent = MacRichEditor(markdown: session.document.parts.body, source: false, editable: true, path: source.lastPathComponent, onChange: { session.changeBody($0) }, onLink: { _ in })
            let coordinator = MacRichEditor.Coordinator(parent), view = NSTextView()
            view.isRichText = true; view.allowsUndo = true; view.delegate = coordinator; coordinator.view = view
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view; window.makeFirstResponder(view)
            defer { coordinator.detach(); window.close() }
            coordinator.load(session.document.parts.body, source: false)
            view.setSelectedRange((view.string as NSString).range(of: "target"))
            let payload = MacClipboard.Payload.fragment(try MacClipboard.image(bytes, name: String(repeating: "Café", count: 70) + ".png"))
            do { try await coordinator.paste(payload); XCTFail("A file-only connection cannot create sibling images") } catch {}
            XCTAssertEqual(session.document.content, original); XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("assets").path))
            await session.chooseProject(root); coordinator.parent.project = try XCTUnwrap(session.project)
            try await coordinator.paste(payload)
            let reference = try XCTUnwrap(MacExternalImages.references(in: session.document.parts.body).first)
            XCTAssertTrue(reference.hasPrefix("./assets/"), reference)
            let imageFile = try XCTUnwrap(session.project).location(reference)
            XCTAssertEqual(try Data(contentsOf: imageFile), bytes)
            XCTAssertLessThanOrEqual(imageFile.lastPathComponent.decomposedStringWithCanonicalMapping.utf8.count, 255)
            await session.save(); XCTAssertFalse(session.dirty); XCTAssertNil(session.failure)
            let saved = try Data(contentsOf: source)
            XCTAssertTrue(saved.starts(with: bom + Data("---\r\nforeign: preserved\r\n---\r\n".utf8)))
            XCTAssertFalse(session.document.content.contains("zerus-id:")); XCTAssertFalse(session.document.content.contains("\u{fffc}"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus").path))
            let images = MacExternalImages(); await images.load(project: session.project, markdown: session.document.parts.body)
            XCTAssertNotNil(images.images[reference]); coordinator.parent.images = images.images; coordinator.refreshImages()
            XCTAssertEqual(try Data(contentsOf: source), saved, "A preview must not rewrite the source file")
            coordinator.action("undo"); await session.save(); XCTAssertEqual(try Data(contentsOf: source), bom + Data(original.utf8))
            XCTAssertEqual(try Data(contentsOf: imageFile), bytes, "Undo retains the image for Redo")
            coordinator.action("redo"); await session.save(); XCTAssertEqual(try Data(contentsOf: source), saved)
            _ = await library.close()
            let reopened = MacExternalLibrary(directory: registry); await reopened.restore(); await reopened.open(try XCTUnwrap(reopened.entries.first))
            let restored = try XCTUnwrap(reopened.selected); await restored.restoreProject()
            XCTAssertEqual(restored.project?.root.resolvingSymlinksInPath(), root.resolvingSymlinksInPath())
            let restoredBytes = try await XCTUnwrap(restored.project).data(reference)
            XCTAssertEqual(restoredBytes, bytes)
            _ = await reopened.close()
        }
    }
    func testVerifiedExportAllowsCloseWhenPrivateDraftStorageFailsWithoutOverwritingOriginal() async throws {
        try await withFiles { source, registry in
            let original = "---\nforeign: preserved\n---\n# External\n\nOriginal.\n", bom = Data([0xef, 0xbb, 0xbf])
            try (bom + Data(original.utf8)).write(to: source)
            let library = MacExternalLibrary(directory: registry); await library.open(source)
            let session = try XCTUnwrap(library.selected)
            let draft = registry.appendingPathComponent("Drafts/" + session.id.uuidString + ".json")
            try FileManager.default.createDirectory(at: draft.deletingLastPathComponent(), withIntermediateDirectories: true)
            let corrupt = Data("unreadable private draft".utf8); try corrupt.write(to: draft)
            session.changeBody("# External\n\nRetained café 🧑🏽‍💻.\n")
            let blocked = await library.close(); XCTAssertFalse(blocked); XCTAssertTrue(library.selected === session)
            let recoveryFailure = try XCTUnwrap(session.failure)
            let export = source.deletingLastPathComponent().appendingPathComponent("Recovered copy.md")
            try await session.exportDraft(to: export)
            XCTAssertEqual(try Data(contentsOf: export), bom + Data(session.document.content.utf8))
            XCTAssertTrue(session.exportReady)
            for unavailable in [false, true] {
                if unavailable { try FileManager.default.removeItem(at: export) }
                else { var bytes = try Data(contentsOf: export); bytes[bytes.count - 2] = 33; try bytes.write(to: export) }
                let changedExportClose = await library.close(); XCTAssertFalse(changedExportClose); XCTAssertTrue(library.selected === session); XCTAssertFalse(session.exportReady)
                XCTAssertNotEqual(session.failure, recoveryFailure)
                try await session.exportDraft(to: export)
                XCTAssertEqual(session.failure, recoveryFailure, "A successful re-export must replace the stale export warning with the recovery-storage issue")
            }
            try await session.exportDraft(to: export)
            session.changeBody(session.document.parts.body + "A later edit.\n")
            let laterEditClose = await library.close(); XCTAssertFalse(laterEditClose); XCTAssertFalse(session.exportReady)
            do { try await session.exportDraft(to: source); XCTFail("An export cannot overwrite the original") } catch {}
            do { try await session.exportDraft(to: draft); XCTFail("An export cannot overwrite private recovery data") } catch {}
            XCTAssertEqual(try Data(contentsOf: source), bom + Data(original.utf8)); XCTAssertEqual(try Data(contentsOf: draft), corrupt)
            try await session.exportDraft(to: export)
            let latest = bom + Data(session.document.content.utf8)
            let closed = await library.close(); XCTAssertTrue(closed); XCTAssertNil(library.selected)
            XCTAssertEqual(try Data(contentsOf: export), latest)
            XCTAssertEqual(try Data(contentsOf: source), bom + Data(original.utf8)); XCTAssertEqual(try Data(contentsOf: draft), corrupt)
        }
    }
    func testReviewedMacCopyImportsPortableAssetsAndKeepsTheConnectedOriginal() async throws {
        try await withFiles { source, registry in
            let root = source.deletingLastPathComponent(), vault = root.appendingPathComponent("Vault")
            try FileManager.default.createDirectory(at: vault.appendingPathComponent("Projects"), withIntermediateDirectories: true)
            try Data("# Existing\n".utf8).write(to: vault.appendingPathComponent("Projects/Standalone.md"))
            let original = Data("---\nforeign: 'Keep: exact'\nzerus-id: outside-source\n---\n# Source café\n\n![Icon](icon.png)\n".utf8)
            let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
            try original.write(to: source); try image.write(to: root.appendingPathComponent("icon.png"))
            let library = MacExternalLibrary(directory: registry); await library.open(source)
            let session = try XCTUnwrap(library.selected)
            let workspace = MacWorkspace(); await workspace.openVault(vault); workspace.external.selected = session
            defer { session.deactivate() }
            do { _ = try await workspace.prepareExternalTransfer(session, folder: "Projects", mode: .copy); XCTFail("Local attachments need a chosen project folder") } catch {}
            await session.chooseProject(root)
            let review = try await workspace.prepareExternalTransfer(session, folder: "Projects", mode: .copy)
            XCTAssertEqual(review.transfer.path, "Projects/Standalone 2.md")
            let copied = try await workspace.commitExternalTransfer(review, session: session).note
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("icon.png")), image)
            XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("Projects/Standalone.md")), Data("# Existing\n".utf8))
            XCTAssertNotEqual(copied.stableID, "outside-source"); XCTAssertNotNil(copied.stableID)
            XCTAssertTrue(copied.content.contains("foreign: 'Keep: exact'"))
            let reference = try XCTUnwrap(MacExternalImages.references(in: copied.parts.body).first)
            let imported = try await XCTUnwrap(workspace.io).resolveResource(reference, notePath: copied.path)
            XCTAssertEqual(try Data(contentsOf: imported), image)
            XCTAssertTrue(workspace.notes.contains { $0.path == copied.path })
            XCTAssertTrue(workspace.external.selected === session)
            let newFolder = try await workspace.prepareExternalTransfer(session, folder: "Travel/Recipes", mode: .copy)
            XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Travel").path))
            _ = try await workspace.commitExternalTransfer(newFolder, session: session)
            XCTAssertEqual(workspace.folderIcon("Travel"), "tabler:Plane")
            XCTAssertEqual(workspace.folderIcon("Travel/Recipes"), "tabler:ChefHat")
            XCTAssertNil(workspace.folderIcon("Projects"), "An existing folder keeps its previous default icon")
            XCTAssertEqual(try Data(contentsOf: source), original)
            do { _ = try await workspace.commitExternalTransfer(review, session: session); XCTFail("A consumed destination cannot be overwritten") } catch {}
        }
    }
    func testMacCopyRejectsDraftChangesReopenedSessionsAndChangedDestinations() async throws {
        try await withFiles { source, registry in
            let root = source.deletingLastPathComponent(), vault = root.appendingPathComponent("Vault")
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            let bytes = Data("# Original\n\nKeep source.\n".utf8); try bytes.write(to: source)
            let library = MacExternalLibrary(directory: registry); await library.open(source)
            let session = try XCTUnwrap(library.selected), workspace = MacWorkspace()
            await workspace.openVault(vault); workspace.external.selected = session
            let review = try await workspace.prepareExternalTransfer(session, folder: "", mode: .copy)
            session.changeBody("# New draft\n")
            do { _ = try await workspace.commitExternalTransfer(review, session: session); XCTFail("Later text requires a fresh review") } catch {}
            await session.save()
            XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(review.transfer.path).path))
            let fresh = try await workspace.prepareExternalTransfer(session, folder: "", mode: .copy)
            await library.open(source)
            let reopened = try XCTUnwrap(library.selected); workspace.external.selected = reopened
            do { _ = try await workspace.commitExternalTransfer(fresh, session: reopened); XCTFail("A new presentation cannot consume the old editor review") } catch {}
            let current = try await workspace.prepareExternalTransfer(reopened, folder: "Inbox", mode: .copy)
            XCTAssertEqual(current.transfer.path, "Inbox/Standalone.md")
            await workspace.openVault(vault)
            do { _ = try await workspace.commitExternalTransfer(current, session: reopened); XCTFail("Reopening the same vault invalidates the review") } catch {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(current.transfer.path).path))
            reopened.deactivate()
        }
    }
    func testLateWritingDuringAgentHoldRemainsAConflictAfterRefresh() async throws {
        try await withFiles { source, registry in
            let original = "# External\n\nOriginal writing.\n"
            try Data(original.utf8).write(to: source)
            let library = MacExternalLibrary(directory: registry); await library.open(source)
            let session = try XCTUnwrap(library.selected)
            session.holdForAgent(true)
            let closed = await library.close(); XCTAssertFalse(closed)
            await library.open(source)
            XCTAssertTrue(library.selected === session)
            let committed = "# External\n\nApproved AI writing.\n"
            _ = try await library.store.save(session.snapshot, content: committed)
            await session.refreshForAgent()
            XCTAssertEqual(session.document.content, committed)
            session.changeContent(original + "Late editor callback.\n")
            let kept = await session.checkpoint(); XCTAssertTrue(kept)
            session.holdForAgent(false)
            await session.save()
            XCTAssertTrue(session.dirty); XCTAssertTrue(session.conflict)
            XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), committed)
            XCTAssertTrue(session.document.content.contains("Late editor callback."))
            let draft = try await library.store.draft(session.id)
            XCTAssertTrue(draft?.content.contains("Late editor callback.") == true)
            _ = await library.close()
        }
    }
    private func withFiles(_ work: (URL, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-Mac-external-" + UUID().uuidString)
        let vault = root.appendingPathComponent("Vault")
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            defaults.removeObject(forKey: MacNavigationState.key(vault))
            defaults.removeObject(forKey: MacNewNotePreferences.key(vault))
            defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(vault.path))
            try? FileManager.default.removeItem(at: root)
        }
        let outcome: Result<Void, Error>
        do {
            try await work(root.appendingPathComponent("Standalone.md"), root.appendingPathComponent("Private registry"))
            outcome = .success(())
        } catch { outcome = .failure(error) }
        let owned = vault.resolvingSymlinksInPath().standardizedFileURL
        // A scenario can open multiple windows. Finish their delayed work
        // before deleting the fixture and restoring the recent-vault list.
        let peers = MacWorkspace.windows.compactMap(\.value).filter { $0.root?.resolvingSymlinksInPath().standardizedFileURL == owned }
        for peer in peers {
            _ = await peer.prepareToCloseWindow()
            peer.external.selected?.deactivate()
            if let directory = peer.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
        }
        await MacStartupCache.shared.invalidate(vault)
        try outcome.get()
    }
}
