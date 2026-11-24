import XCTest
import AppKit
@testable import Zerus_Native

@MainActor final class MacExternalMoveTests: XCTestCase {
    private func withMove(_ work: (MacWorkspace, MacExternalSession, URL, URL) async throws -> Void) async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-Mac-move-" + UUID().uuidString)
        let project = base.appendingPathComponent("Project"), vault = base.appendingPathComponent("Vault")
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        defer {
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            defaults.removeObject(forKey: MacNavigationState.key(vault))
            defaults.removeObject(forKey: MacNewNotePreferences.key(vault))
            defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(vault.path))
            try? FileManager.default.removeItem(at: base)
        }
        for url in [project, vault] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let source = project.appendingPathComponent("Original.md")
        try Data("---\nforeign: 'Keep: exact'\nzerus-id: move-\(UUID().uuidString.lowercased())\n---\n# Original café\n\n![Icon](icon.png)\n".utf8).write(to: source)
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!.write(to: project.appendingPathComponent("icon.png"))
        let workspace = MacWorkspace(); await workspace.openVault(vault); await workspace.external.open(source)
        let session = workspace.external.selected
        let outcome: Result<Void, Error>
        do {
            let session = try XCTUnwrap(session)
            await session.chooseProject(project)
            try await work(workspace, session, source, vault)
            outcome = .success(())
        } catch { outcome = .failure(error) }
        let owned = vault.resolvingSymlinksInPath().standardizedFileURL
        // Settle startup/cache/navigation work before restoring preferences or
        // removing the owned vault, including any peer opened by the scenario.
        let peers = MacWorkspace.windows.compactMap(\.value).filter { $0.root?.resolvingSymlinksInPath().standardizedFileURL == owned }
        for peer in peers {
            _ = await peer.prepareToCloseWindow()
            if let directory = peer.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
        }
        await MacStartupCache.shared.invalidate(vault)
        if let session {
            await cleanup(workspace, session: session, project: project)
        }
        try outcome.get()
    }
    private func cleanup(_ workspace: MacWorkspace, session: MacExternalSession, project: URL) async {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: project.path)
        session.deactivate(); workspace.external.selected?.deactivate()
        if let records = try? await workspace.external.moveStore.pending() {
            for record in records where record.sourceID == session.id { try? await workspace.external.moveStore.finish(record) }
        }
        try? await workspace.external.store.forget(session.id)
    }
    func testMacMoveVerifiesPortableCopyKeepsIdentityAndMakesOtherEditorsReadOnly() async throws {
        try await withMove { workspace, session, source, vault in
            let original = try Data(contentsOf: source), image = try Data(contentsOf: source.deletingLastPathComponent().appendingPathComponent("icon.png"))
            let peer = MacWorkspace(); await peer.openVault(vault); await peer.external.open(source)
            let other = try XCTUnwrap(peer.external.selected)
            defer { other.deactivate() }
            let review = try await workspace.prepareExternalTransfer(session, folder: "Inbox", mode: .move)
            let outcome = try await workspace.commitExternalTransfer(review, session: session)
            XCTAssertTrue(outcome.sourceRemoved); XCTAssertFalse(outcome.recoveryPending)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(outcome.note.stableID, session.document.stableID)
            XCTAssertTrue(outcome.note.content.contains("foreign: 'Keep: exact'"))
            let reference = try XCTUnwrap(MacExternalImages.references(in: outcome.note.parts.body).first)
            let imported = try await XCTUnwrap(workspace.io).resolveResource(reference, notePath: outcome.note.path)
            XCTAssertEqual(try Data(contentsOf: imported), image)
            XCTAssertEqual(try Data(contentsOf: source.deletingLastPathComponent().appendingPathComponent("icon.png")), image)
            XCTAssertTrue(session.moved); XCTAssertTrue(other.moved); XCTAssertFalse(other.active)
            other.changeBody("This must not recreate a removed original."); await other.save()
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(session.snapshot.bytes, original)
            let pending = try await workspace.external.moveStore.pending(); XCTAssertFalse(pending.contains { $0.sourceID == session.id })
            let entries = try await workspace.external.store.entries(); XCTAssertFalse(entries.contains { $0.id == session.id })
            let closed = await peer.external.close(); XCTAssertTrue(closed)
        }
    }
    func testMacMoveRetainsDurableRecoveryOnRemovalFailureAndResumesWithoutAnotherCopy() async throws {
        try await withMove { workspace, session, source, vault in
            let original = try Data(contentsOf: source)
            let review = try await workspace.prepareExternalTransfer(session, folder: "", mode: .move)
            let project = source.deletingLastPathComponent()
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: project.path)
            let outcome = try await workspace.commitExternalTransfer(review, session: session)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: project.path)
            XCTAssertFalse(outcome.sourceRemoved); XCTAssertTrue(outcome.recoveryPending)
            XCTAssertEqual(try Data(contentsOf: source), original)
            let records = try await workspace.external.moveStore.pending(), record = try XCTUnwrap(records.first { $0.sourceID == session.id })
            XCTAssertEqual(record.phase, .copied); XCTAssertEqual(record.sourceBytes, original)
            let exported = project.appendingPathComponent("Recovery.md")
            try await workspace.external.exportPendingOriginal(record, to: exported)
            XCTAssertEqual(try Data(contentsOf: exported), original)
            let restarted = MacWorkspace(); await restarted.openVault(vault); await restarted.external.restore()
            XCTAssertTrue(restarted.external.pendingMoves.contains(record))
            await restarted.external.open(session.snapshot.entry)
            let reopened = try XCTUnwrap(restarted.external.selected)
            defer { reopened.deactivate() }
            let retry = try await restarted.preparePendingExternalMove(record, session: reopened)
            let finished = try await restarted.commitExternalTransfer(retry, session: reopened)
            XCTAssertTrue(finished.sourceRemoved); XCTAssertFalse(finished.recoveryPending)
            XCTAssertEqual(finished.note.path, outcome.note.path)
            let notes = try await XCTUnwrap(restarted.io).scan().notes
            XCTAssertEqual(notes.filter { $0.stableID == finished.note.stableID }.count, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            let remaining = try await restarted.external.moveStore.pending(); XCTAssertFalse(remaining.contains { $0.sourceID == session.id })
        }
    }
    func testMacPendingMoveCanKeepBothFilesOnlyAfterVerifyingTheSavedCopy() async throws {
        try await withMove { workspace, session, source, vault in
            let review = try await workspace.prepareExternalTransfer(session, folder: "", mode: .move)
            let project = source.deletingLastPathComponent()
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: project.path)
            let outcome = try await workspace.commitExternalTransfer(review, session: session)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: project.path)
            XCTAssertTrue(outcome.recoveryPending); XCTAssertFalse(outcome.sourceRemoved)
            let records = try await workspace.external.moveStore.pending(), record = try XCTUnwrap(records.first { $0.sourceID == session.id })
            let copied = vault.appendingPathComponent(outcome.note.path), saved = try Data(contentsOf: copied)
            try Data("# A changed vault copy\n".utf8).write(to: copied)
            do { try await workspace.finishPendingExternalMove(record); XCTFail("A changed destination cannot authorize closing its recovery record") } catch {}
            let retained = try await workspace.external.moveStore.pending(); XCTAssertTrue(retained.contains(record))
            try saved.write(to: copied)
            let outside = Data("# Later original writing\n".utf8); try outside.write(to: source)
            do { _ = try await workspace.preparePendingExternalMove(record, session: session); XCTFail("A later original cannot be removed by the old move") } catch {}
            try await workspace.finishPendingExternalMove(record)
            XCTAssertEqual(try Data(contentsOf: source), outside)
            XCTAssertEqual(try Data(contentsOf: copied), saved)
            XCTAssertFalse(session.active); XCTAssertFalse(session.moved)
            let remaining = try await workspace.external.moveStore.pending(); XCTAssertFalse(remaining.contains { $0.sourceID == session.id })
            let entries = try await workspace.external.store.entries(); XCTAssertFalse(entries.contains { $0.id == session.id })
        }
    }
    func testMacMoveRejectsChangedOriginalAndExportsPreparedRecoveryWithoutOverwritingFiles() async throws {
        try await withMove { workspace, session, source, vault in
            let original = try Data(contentsOf: source)
            let review = try await workspace.prepareExternalTransfer(session, folder: "", mode: .move)
            let outside = Data("# Outside change\n".utf8); try outside.write(to: source)
            do { _ = try await workspace.commitExternalTransfer(review, session: session); XCTFail("The changed source must remain") } catch {}
            XCTAssertEqual(try Data(contentsOf: source), outside)
            XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(review.transfer.path).path))
            let records = try await workspace.external.moveStore.pending(), record = try XCTUnwrap(records.first { $0.sourceID == session.id })
            XCTAssertEqual(record.phase, .prepared); XCTAssertEqual(record.sourceBytes, original)
            do { try await workspace.finishPendingExternalMove(record); XCTFail("A missing vault copy cannot authorize cleanup") } catch {}
            do { try await workspace.external.exportPendingOriginal(record, to: source); XCTFail("Recovery export cannot overwrite the current original") } catch {}
            do { try await workspace.external.exportPendingOriginal(record, to: vault.appendingPathComponent(record.destinationPath)); XCTFail("Recovery export cannot replace the imported note") } catch {}
            let export = source.deletingLastPathComponent().appendingPathComponent("Retained.md")
            try await workspace.external.exportPendingOriginal(record, to: export)
            XCTAssertEqual(try Data(contentsOf: export), original)
            XCTAssertEqual(try Data(contentsOf: source), outside)
        }
    }
}
