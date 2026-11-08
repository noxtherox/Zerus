import XCTest
import UIKit
import SwiftUI
@testable import ZerusNative

final class NativeExternalTransferTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let root: URL
        let project: URL
        let target: URL
        let source: URL
        let external: NativeExternalNotesModel
        let session: NativeExternalNoteSession
        let vault: VaultStore
        let projectAccess: NativeExternalProjectFiles
        let bytes: Data
    }
    @MainActor
    private func fixture(_ text: String = "---\nforeign: 'Keep: exact'\nzerus-id: external-source\n---\n# Source\n\nOriginal writing.\n", bom: Bool = false) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NativeExternalTransfer-" + UUID().uuidString)
        let project = root.appendingPathComponent("Project"), target = root.appendingPathComponent("Vault")
        for folder in [project, target, project.appendingPathComponent("figures")] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let source = project.appendingPathComponent("Original source.markdown"), bytes = (bom ? Data([0xef,0xbb,0xbf]) : Data()) + Data(text.utf8)
        try bytes.write(to: source)
        let external = NativeExternalNotesModel(directory: root.appendingPathComponent("Private")), session = try await external.open(source)
        let access = try await external.mapProject(session.snapshot, folder: project)
        let vault = VaultStore(); await vault.open(target)
        XCTAssertNotNil(vault.root)
        return .init(root: root, project: project, target: target, source: source, external: external, session: session, vault: vault, projectAccess: access, bytes: bytes)
    }
    @MainActor
    private func image() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 6, height: 3), format: format).image { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 6, height: 3))
        }.pngData())
    }
    @MainActor
    func testForgettingAnOpenConnectionMakesItsActualNativeEditorReadOnlyAndKeepsTheOriginal() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        let host = UIHostingController(rootView: NativeExternalEditorScreen(session: f.session).environmentObject(f.vault).environmentObject(f.external))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        func editor(_ view: UIView) -> UITextView? {
            if let view = view as? ZerusTextView { return view }
            return view.subviews.compactMap(editor).first
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while editor(host.view) == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let text = try XCTUnwrap(editor(host.view)); XCTAssertTrue(text.isEditable)
        XCTAssertTrue(text.becomeFirstResponder())
        text.selectedRange = NSRange(location: (text.text as NSString).range(of: "Original writing.").location, length: 0)
        text.setMarkedText("正在", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(text.markedTextRange)
        try await f.external.forget(f.session.snapshot.entry)
        let closed = ContinuousClock.now + .seconds(3)
        while text.isEditable, ContinuousClock.now < closed { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(text.isEditable, "Closing a connection in another window must not leave an editor accepting writing that can no longer be saved")
        let committed = String(decoding: f.bytes, as: UTF8.self).replacingOccurrences(of: "Original writing.", with: "正在Original writing.")
        XCTAssertEqual(try Data(contentsOf: f.source), Data(committed.utf8), "Closing the connection commits and saves active marked writing before it revokes the editor")
        XCTAssertTrue(f.external.entries.isEmpty)
    }
    @MainActor
    func testCopyCommitsPortableMarkdownAndDeduplicatedResourcesWithoutChangingTheOriginalOrForeignYAML() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let text = "---\r\nforeign: 'Keep: exact'\r\nzerus-id: external-source\r\n---\r\n# Source\r\n\r\n![Chart](figures/one%20chart.png#small)\r\n\r\n<img src=\"./figures/one%20chart.png\" alt=\"Keep &amp; exact\">\r\n\r\n[Report](report.pdf#page=2)\r\n\r\n[Other](Other.md)\r\n\r\n`![Literal](not-selected.png)`\r\n\r\n```md\r\n![Code](not-selected.png)\r\n```\r\n"
        let f = try await fixture(text, bom: true); defer { try? FileManager.default.removeItem(at: f.root) }
        let png = try image(), pdf = Data("%PDF-transfer-snapshot".utf8)
        try png.write(to: f.project.appendingPathComponent("figures/one chart.png")); try pdf.write(to: f.project.appendingPathComponent("report.pdf"))
        let review = try await f.vault.prepareExternalTransfer(session: f.session, project: f.projectAccess, folder: "Projects", mode: .copy, workspace: f.vault.workspaceID)
        XCTAssertEqual(review.assets.count, 2, "Two spellings of the same selected image copy one file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.target.appendingPathComponent("Projects").path), "Preparing a review does not write its destination")
        let result = try await f.vault.commitExternalTransfer(review, session: f.session, external: f.external)
        XCTAssertFalse(result.sourceRemoved); XCTAssertFalse(result.recoveryPending); XCTAssertNil(result.message)
        let data = try Data(contentsOf: f.target.appendingPathComponent(result.note.path)), copy = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(data.starts(with: [0xef,0xbb,0xbf])); XCTAssertTrue(copy.contains("foreign: 'Keep: exact'\r\n"))
        XCTAssertNotEqual(result.note.stableID, "external-source"); XCTAssertNotNil(result.note.stableID)
        XCTAssertTrue(copy.contains("[Other](Other.md)")); XCTAssertTrue(copy.contains("alt=\"Keep &amp; exact\""))
        XCTAssertTrue(copy.contains("#small")); XCTAssertTrue(copy.contains("#page=2"))
        XCTAssertTrue(copy.contains("`![Literal](not-selected.png)`")); XCTAssertTrue(copy.contains("```md\r\n![Code](not-selected.png)\r\n```"))
        for asset in review.assets { XCTAssertEqual(try Data(contentsOf: f.target.appendingPathComponent(asset.path)), asset.bytes) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.target.appendingPathComponent("assets").path).count, 2)
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes); XCTAssertEqual(try Data(contentsOf: f.project.appendingPathComponent("figures/one chart.png")), png)
        XCTAssertEqual(try Data(contentsOf: f.project.appendingPathComponent("report.pdf")), pdf)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.project.appendingPathComponent(".zerus").path))
        let reopened = try await VaultFiles(root: f.target).scan()
        XCTAssertEqual(reopened.notes.first(where: { $0.path == result.note.path })?.content, copy)
        XCTAssertTrue(f.external.entries.contains(where: { $0.id == f.session.id })); XCTAssertFalse(f.session.dirty)
    }
    @MainActor
    func testMoveRemovesOnlyTheReviewedMarkdownAfterItsVaultCopyAndKeepsProjectImagesAndOtherConnections() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let f = try await fixture("---\nforeign: 'Keep: exact'\nzerus-id: external-source\n---\n# Source\n\n![Chart](figures/chart.png)\n", bom: true)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let png = try image(); try png.write(to: f.project.appendingPathComponent("figures/chart.png"))
        let other = f.project.appendingPathComponent("Other.md"), otherBytes = Data("# Another original\n".utf8); try otherBytes.write(to: other)
        let otherSession = try await f.external.open(other)
        let review = try await f.vault.prepareExternalTransfer(session: f.session, project: f.projectAccess, folder: "Inbox", mode: .move, workspace: f.vault.workspaceID)
        let result = try await f.vault.commitExternalTransfer(review, session: f.session, external: f.external)
        XCTAssertTrue(result.sourceRemoved); XCTAssertFalse(result.recoveryPending); XCTAssertNil(result.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.path))
        XCTAssertEqual(result.note.stableID, "external-source")
        XCTAssertEqual(try Data(contentsOf: f.target.appendingPathComponent(result.note.path)), Data(review.content.utf8))
        XCTAssertEqual(try Data(contentsOf: f.project.appendingPathComponent("figures/chart.png")), png)
        XCTAssertEqual(try Data(contentsOf: other), otherBytes)
        XCTAssertEqual(f.external.entries.map(\.id), [otherSession.id]); XCTAssertTrue(f.external.pendingMoves.isEmpty)
        XCTAssertTrue(f.session.moved); XCTAssertFalse(f.session.transferring)
        f.session.updateBody("Do not recreate the removed original"); await f.session.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.path))
        let restarted = NativeExternalNotesModel(directory: f.root.appendingPathComponent("Private")); await restarted.restore()
        XCTAssertEqual(restarted.entries.map(\.id), [otherSession.id]); XCTAssertTrue(restarted.pendingMoves.isEmpty)
    }
    @MainActor
    func testStaleSourcesReplacementsDestinationChangesAndVaultReactivationRejectTransfersBeforeOriginalRemoval() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        for change in ["source", "replacement", "destination", "assetAlias", "reactivation", "rootMove", "draft"] {
            let f = try await fixture("# Source\n\n![Chart](figures/chart.png)\n")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let png = try image(); try png.write(to: f.project.appendingPathComponent("figures/chart.png"))
            let review = try await f.vault.prepareExternalTransfer(session: f.session, project: f.projectAccess, folder: "Projects", mode: .move, workspace: f.vault.workspaceID)
            var expectedSource = f.bytes
            let protected = f.root.appendingPathComponent("Outside"); try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
            try Data("Outside original".utf8).write(to: protected.appendingPathComponent("Keep.txt"))
            switch change {
            case "source": expectedSource = Data("# Newer outside writing\n".utf8); try expectedSource.write(to: f.source)
            case "replacement": try f.bytes.write(to: f.source, options: .atomic)
            case "destination":
                let target = f.target.appendingPathComponent(review.path); try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("# A different note\n".utf8).write(to: target)
            case "assetAlias": try FileManager.default.createSymbolicLink(at: f.target.appendingPathComponent("assets"), withDestinationURL: protected)
            case "reactivation": await f.vault.open(protected); await f.vault.open(f.target)
            case "rootMove": try FileManager.default.moveItem(at: f.target, to: f.root.appendingPathComponent("Moved vault"))
            default: f.session.updateBody("# Current unsaved draft\n"); await f.session.flushDraft()
            }
            do { _ = try await f.vault.commitExternalTransfer(review, session: f.session, external: f.external); XCTFail("A stale \(change) review must not remove or import an original") } catch { }
            XCTAssertEqual(try Data(contentsOf: f.source), expectedSource, change)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: protected.path), ["Keep.txt"])
            if change == "rootMove" { XCTAssertFalse(FileManager.default.fileExists(atPath: f.target.path)) }
            else if change == "destination" { XCTAssertEqual(try Data(contentsOf: f.target.appendingPathComponent(review.path)), Data("# A different note\n".utf8)) }
            else { XCTAssertFalse(FileManager.default.fileExists(atPath: f.target.appendingPathComponent(review.path).path), change) }
            if change == "draft" { XCTAssertTrue(f.session.document.content.contains("Current unsaved draft")); XCTAssertTrue(f.session.dirty) }
        }
    }
    @MainActor
    func testFinishingWithTheVerifiedCopyAfterAnInterruptedRemovalKeepsARecreatedOriginalUntouched() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let f = try await fixture(bom: true); defer { try? FileManager.default.removeItem(at: f.root) }
        let review = try await f.vault.prepareExternalTransfer(session: f.session, project: nil, folder: "Inbox", mode: .move, workspace: f.vault.workspaceID)
        let presenter = DeniedExternalDeletion(url: f.source); NSFileCoordinator.addFilePresenter(presenter)
        let partial = try await f.vault.commitExternalTransfer(review, session: f.session, external: f.external)
        NSFileCoordinator.removeFilePresenter(presenter)
        XCTAssertTrue(partial.recoveryPending)
        let record = try XCTUnwrap(f.external.pendingMoves.first)
        // Run the real removal stage, then simulate termination before its next
        // private journal write. The retained record still says "copied".
        try await NativeExternalTransferFiles.removeOriginal(f.session.snapshot, record: record, destination: record.destination())
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.path))
        let newer = Data("# A newly recreated original\nKeep this later writing.\n".utf8)
        try newer.write(to: f.source)
        let restarted = NativeExternalNotesModel(directory: f.root.appendingPathComponent("Private")); await restarted.restore()
        let pending = try XCTUnwrap(restarted.pendingMoves.first); XCTAssertEqual(pending.phase, .copied)
        try await f.vault.finishPendingExternalConnection(pending, external: restarted, workspace: f.vault.workspaceID)
        XCTAssertEqual(try Data(contentsOf: f.source), newer, "Finishing with a verified copy only cleans its saved connection; it never retries deletion of a recreated original")
        XCTAssertEqual(try Data(contentsOf: f.target.appendingPathComponent(review.path)), Data(review.content.utf8))
        XCTAssertTrue(restarted.entries.isEmpty); XCTAssertTrue(restarted.pendingMoves.isEmpty)
    }
    @MainActor
    func testDeniedSourceDeletionRetainsTheCopyAndRecoveryRecordAndAReopenedReviewCompletesTheSameMove() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let f = try await fixture(bom: true); defer { try? FileManager.default.removeItem(at: f.root) }
        let review = try await f.vault.prepareExternalTransfer(session: f.session, project: nil, folder: "Inbox", mode: .move, workspace: f.vault.workspaceID)
        let presenter = DeniedExternalDeletion(url: f.source)
        NSFileCoordinator.addFilePresenter(presenter)
        var presenting = true; defer { if presenting { NSFileCoordinator.removeFilePresenter(presenter) } }
        let partial = try await f.vault.commitExternalTransfer(review, session: f.session, external: f.external)
        XCTAssertFalse(partial.sourceRemoved); XCTAssertTrue(partial.recoveryPending); XCTAssertNotNil(partial.message)
        XCTAssertEqual(presenter.deletionRequests, 1, "The actual file coordinator must ask the original's presenter before removal")
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
        XCTAssertEqual(try Data(contentsOf: f.target.appendingPathComponent(partial.note.path)), Data(review.content.utf8))
        NSFileCoordinator.removeFilePresenter(presenter); presenting = false
        let external = NativeExternalNotesModel(directory: f.root.appendingPathComponent("Private")); await external.restore()
        let record = try XCTUnwrap(external.pendingMoves.first); XCTAssertEqual(record.phase, .copied); XCTAssertEqual(record.sourceBytes, f.bytes)
        let source = try await external.open(try XCTUnwrap(external.entries.first))
        let target = f.target.appendingPathComponent(partial.note.path), goodCopy = try Data(contentsOf: target)
        try Data("# A newer vault edit\n".utf8).write(to: target, options: .atomic)
        do { _ = try await f.vault.preparePendingExternalMove(record, session: source, workspace: f.vault.workspaceID); XCTFail("A changed copy cannot authorize removing the original") } catch { }
        XCTAssertEqual(try Data(contentsOf: f.source), f.bytes)
        try goodCopy.write(to: target, options: .atomic)
        let resumed = try await f.vault.preparePendingExternalMove(record, session: source, workspace: f.vault.workspaceID)
        let result = try await f.vault.commitExternalTransfer(resumed, session: source, external: external)
        XCTAssertTrue(result.sourceRemoved); XCTAssertFalse(result.recoveryPending); XCTAssertNil(result.message)
        XCTAssertEqual(result.note.path, partial.note.path, "Resuming uses the existing verified copy, without making a second note")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.path)); XCTAssertEqual(try Data(contentsOf: target), goodCopy)
        XCTAssertTrue(external.pendingMoves.isEmpty); XCTAssertTrue(external.entries.isEmpty)
        let notes = try await VaultFiles(root: f.target).scan().notes
        XCTAssertEqual(notes.count, 1)
    }
}

private final class DeniedExternalDeletion: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let lock = NSLock()
    private var requests = 0
    var deletionRequests: Int { lock.lock(); defer { lock.unlock() }; return requests }
    init(url: URL) { presentedItemURL = url; super.init(); presentedItemOperationQueue.maxConcurrentOperationCount = 1 }
    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        lock.lock(); requests += 1; lock.unlock()
        completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError))
    }
}
