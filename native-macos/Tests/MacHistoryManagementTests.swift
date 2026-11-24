import XCTest
@testable import Zerus_Native

@MainActor final class MacHistoryManagementTests: XCTestCase {
    func testKeepLabelsAndReviewedRetentionPreserveKeptLineageForeignSettingsAndDisabledCapture() async throws {
        try await fixture { root, workspace in
            for index in 1...12 { workspace.changed("# History note\n\nSaved observation \(index).\n"); let saved = await workspace.save(); XCTAssertTrue(saved) }
            let request = MacRecoveryRequest(workspaceID: workspace.workspaceID, path: "Work/Note.md", history: true)
            let recovery = try await workspace.recoverySnapshot(request), oldest = try XCTUnwrap(try XCTUnwrap(recovery.history).versions.last)
            let noteFile = root.appendingPathComponent(request.path), current = try Data(contentsOf: noteFile)
            try await workspace.saveHistoryAnnotation(recovery, id: oldest.id, kept: true, label: "  Research baseline  ")
            XCTAssertEqual(try Data(contentsOf: noteFile), current)
            let annotated = try await workspace.recoverySnapshot(request), version = try XCTUnwrap(try XCTUnwrap(annotated.history).versions.first { $0.id == oldest.id })
            XCTAssertTrue(version.kept); XCTAssertEqual(version.label, "Research baseline")
            let snapshot = try await workspace.historyManagementSnapshot(workspaceID: workspace.workspaceID)
            let review = try await workspace.prepareHistoryManagement(snapshot, intent: .settings(enabled: true, limit: 1))
            XCTAssertGreaterThan(review.plan.removedRecords.count, 0); XCTAssertEqual(review.plan.keptRemoved, 0)
            XCTAssertFalse(review.plan.removedRecords.contains(version.path))
            for path in review.plan.removedRecords { XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), "Preparing a review must not delete its listed records") }
            try await workspace.commitHistoryManagement(review)
            let retained = try await workspace.recoverySnapshot(request)
            XCTAssertTrue(try XCTUnwrap(retained.history).versions.contains { $0.id == oldest.id && $0.kept && $0.label == "Research baseline" })
            XCTAssertTrue(try XCTUnwrap(retained.history).versions.allSatisfy { !$0.incomplete })
            XCTAssertEqual(try Data(contentsOf: noteFile), current)
            let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/history-settings.json"))) as? [String: Any])
            XCTAssertEqual((settings["foreign"] as? [String: Bool])?["keep"], true); XCTAssertEqual(settings["checkpointLimit"] as? Int, 1)
            let fresh = try await workspace.historyManagementSnapshot(workspaceID: workspace.workspaceID), off = try await workspace.prepareHistoryManagement(fresh, intent: .settings(enabled: false, limit: nil))
            XCTAssertFalse(off.deletes); try await workspace.commitHistoryManagement(off)
            let count = try XCTUnwrap(retained.history).versions.count
            workspace.changed("# History note\n\nChanges while history is disabled.\n"); let saved = await workspace.save(); XCTAssertTrue(saved)
            let disabled = try await workspace.historyManagementSnapshot(workspaceID: workspace.workspaceID)
            XCTAssertFalse(disabled.history.configuration.enabled); XCTAssertNil(disabled.history.configuration.limit); XCTAssertEqual(disabled.history.records.count, count)
            let unlimited = try await workspace.prepareHistoryManagement(disabled, intent: .settings(enabled: true, limit: nil)); XCTAssertFalse(unlimited.deletes)
            try await workspace.commitHistoryManagement(unlimited)
            let enabled = try await workspace.historyManagementSnapshot(workspaceID: workspace.workspaceID)
            XCTAssertTrue(enabled.history.configuration.enabled); XCTAssertNil(enabled.history.configuration.limit)
        }
    }
    func testMacPrivateDraftsProtectOrphanedBlobsAndInvalidateChangedOrOldWorkspaceReviews() async throws {
        try await fixture { root, workspace in
            let bytes = Data(("private draft image " + UUID().uuidString).utf8), other = Data(("unused image " + UUID().uuidString).utf8)
            let protectedPath = ".zerus/history/blobs/" + NativeHistory.hash(bytes), unusedPath = ".zerus/history/blobs/" + NativeHistory.hash(other)
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".zerus/history/blobs"), withIntermediateDirectories: true)
            try bytes.write(to: root.appendingPathComponent(protectedPath)); try other.write(to: root.appendingPathComponent(unusedPath))
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/Drafts"), draft = folder.appendingPathComponent("history-test-" + UUID().uuidString + ".json")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let original = try JSONSerialization.data(withJSONObject: ["body": "![Recovery](" + protectedPath + ")"]); try original.write(to: draft)
            defer { try? FileManager.default.removeItem(at: draft) }
            let snapshot = try await workspace.historyManagementSnapshot(workspaceID: workspace.workspaceID), review = try await workspace.prepareHistoryManagement(snapshot, intent: .cleanup)
            XCTAssertFalse(review.plan.removedBlobs.contains(protectedPath)); XCTAssertTrue(review.plan.removedBlobs.contains(unusedPath))
            XCTAssertTrue(review.plan.warnings.contains { $0.contains("Mac recovery drafts") })
            try (original + Data(" ".utf8)).write(to: draft)
            do { try await workspace.commitHistoryManagement(review); XCTFail("Changing a private draft must invalidate a deletion review") } catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("drafts changed")) }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(unusedPath)), other)
            try original.write(to: draft); try await workspace.commitHistoryManagement(review)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(unusedPath).path)); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(protectedPath)), bytes)
            let limited = try await workspace.historyManagementSnapshot(workspaceID: workspace.workspaceID)
            let settings = try await workspace.prepareHistoryManagement(limited, intent: .settings(enabled: true, limit: 1))
            try await workspace.commitHistoryManagement(settings)
            for index in 1...9 { workspace.changed("# History note\n\nAutosaved change \(index).\n"); let saved = await workspace.save(); XCTAssertTrue(saved) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(protectedPath).path), "Automatic retention must protect blobs referenced only by a Mac private draft")
            try FileManager.default.removeItem(at: draft)
            let refreshed = try await workspace.historyManagementSnapshot(workspaceID: workspace.workspaceID), eligible = try await workspace.prepareHistoryManagement(refreshed, intent: .cleanup)
            XCTAssertTrue(eligible.plan.removedBlobs.contains(protectedPath))
            await workspace.openVault(root)
            do { try await workspace.commitHistoryManagement(eligible); XCTFail("A previous vault activation must not apply") } catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(protectedPath)), bytes)
        }
    }
    private func fixture(operation: (URL, MacWorkspace) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-history-management-" + UUID().uuidString), defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work"), withIntermediateDirectories: true); try FileManager.default.createDirectory(at: root.appendingPathComponent(".zerus"), withIntermediateDirectories: true)
        try Data("---\nzerus-id: history-managed-note\nforeign: retained\n---\n# History note\n\nOriginal observation.\n".utf8).write(to: root.appendingPathComponent("Work/Note.md"))
        try Data(#"{"enabled":true,"checkpointLimit":100,"foreign":{"keep":true}}"#.utf8).write(to: root.appendingPathComponent(".zerus/history-settings.json"))
        let workspace = MacWorkspace(); await workspace.openVault(root); await workspace.openNote("Work/Note.md"); let drafts = workspace.taskDraftStore?.directory
        defer { if let drafts { try? FileManager.default.removeItem(at: drafts) }; defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path)); try? FileManager.default.removeItem(at: root) }
        try await operation(root, workspace)
    }
}
