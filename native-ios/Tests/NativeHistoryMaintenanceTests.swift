import XCTest
import CryptoKit
@testable import ZerusNative

final class NativeHistoryMaintenanceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func blob(_ io: VaultFiles, _ name: String) async throws -> String {
        let bytes = Data(name.utf8), path = ".zerus/history/blobs/" + hash(bytes)
        try await io.write(path, data: bytes, expected: nil); return path
    }
    private func record(_ io: VaultFiles, note: String, id: String, ordinal: Int, image: String? = nil, kept: Bool = false) async throws -> String {
        let text = "# Saved \(id)\nBody \(ordinal)\n", path = ".zerus/history/notes/" + note + "/" + id + ".json"
        let images: [[String: Any]] = image.map { [["path":"assets/live.png", "hash":($0 as NSString).lastPathComponent, "extension":"png"]] } ?? []
        let object: [String: Any] = ["schema":1, "id":id, "noteId":note, "timestamp":String(format: "2026-11-01T12:00:%02d.000Z", ordinal), "source":"desktop", "originId":"fixture", "parentId":NSNull(), "depth":0, "kind":"checkpoint", "baseHash":NSNull(), "resultHash":hash(Data(text.utf8)), "content":text, "images":images, "kept":kept, "label":kept ? "Milestone" as Any : NSNull(), "foreign":["retain":[1,2,3]]]
        try await io.write(path, data: JSONSerialization.data(withJSONObject: object), expected: nil); return path
    }
    private func fixture(_ folder: URL) async throws -> (VaultFiles, String, String) {
        let io = VaultFiles(root: folder)
        try await io.write("Note.md", data: Data("---\nzerus-id: history-note\n---\n# Note\nCurrent\n".utf8), expected: nil)
        let unused = try await blob(io, "unused"), record = try await record(io, note: "history-note", id: "saved", ordinal: 1)
        return (io, unused, record)
    }

    func testImmediateVaultRetentionPrunesOrphansAndTrashWhileProtectingKeptSharedLiveRevisionAndRecoveryImages() async throws {
        let io = VaultFiles(root: root!)
        let a = "---\nzerus-id: a\n---\n# A\nCurrent A\n", b = "---\nzerus-id: b\n---\n# B\nCurrent B\n", trash = "---\nzerus-id: trash\n---\n# Deleted\nCurrent trash\n"
        for (path, text) in [("A.md",a), ("B.md",b), (".trash/Deleted.md",trash)] { try await io.write(path, data: Data(text.utf8), expected: nil) }
        try await io.write("assets/live.png", data: Data([137,80,78,71,9]), expected: nil)
        var images: [String: String] = [:]
        for name in ["kept", "shared", "obsolete", "orphan-old", "trash-old", "loose", "live", "revision", "recovery", "audit"] { images[name] = try await blob(io, name) }
        let a0 = try await record(io, note: "a", id: "a0", ordinal: 0, image: images["kept"])
        let keptDelta = try await record(io, note: "a", id: "kept-delta", ordinal: 1, image: images["kept"], kept: true)
        let parentBytes = try await io.read(a0), deltaBytes = try await io.read(keptDelta)
        let parentText = (try JSONSerialization.jsonObject(with: parentBytes) as! [String: Any])["content"] as! String
        var delta = try JSONSerialization.jsonObject(with: deltaBytes) as! [String: Any]
        let deltaText = delta.removeValue(forKey: "content") as! String
        delta["kind"] = "delta"; delta["depth"] = 1; delta["parentId"] = "a0"; delta["baseHash"] = hash(Data(parentText.utf8))
        delta["delta"] = ["start":0, "removed":parentText, "inserted":deltaText]
        try await io.write(keptDelta, data: JSONSerialization.data(withJSONObject: delta), expected: deltaBytes)
        let a1 = try await record(io, note: "a", id: "a1", ordinal: 2, image: images["obsolete"])
        let a2 = try await record(io, note: "a", id: "a2", ordinal: 3, image: images["shared"])
        let b0 = try await record(io, note: "b", id: "b0", ordinal: 0, image: images["kept"])
        let b1 = try await record(io, note: "b", id: "b1", ordinal: 1, image: images["shared"])
        let o0 = try await record(io, note: "orphan", id: "o0", ordinal: 0, image: images["orphan-old"])
        let o1 = try await record(io, note: "orphan", id: "o1", ordinal: 1, image: images["shared"])
        let t0 = try await record(io, note: "trash", id: "t0", ordinal: 0, image: images["trash-old"])
        let t1 = try await record(io, note: "trash", id: "t1", ordinal: 1, image: images["shared"])
        let encodedHash = (images["live"]! as NSString).lastPathComponent.utf8.map { String(format: "%%%02X", $0) }.joined()
        let incoming = "# Incoming\n![Still used](.zerus/history/blobs/" + encodedHash + ")\n"
        try await io.write("Incoming.md", data: Data(incoming.utf8), expected: nil)
        let metadata: [(String, [String: Any])] = [
            (".zerus/revisions/notes/legacy/index.json", ["schema":99,"foreign":images["revision"]!]),
            (".zerus/native-recovery/retained.json", ["data":Data(("# Recovery\n![Image](" + images["recovery"]! + ")\n").utf8).base64EncodedString()]),
            (".zerus/history/audit.json", ["receipt":["content":"---\nImage: \"" + images["audit"]!.replacingOccurrences(of:"/",with:"\\/") + "\"\n---\n# Audit\n"]]),
            (".zerus/history-settings.json", ["enabled":true,"checkpointLimit":10,"foreign":["keep":true]])
        ]
        for (path, object) in metadata { try await io.write(path, data: JSONSerialization.data(withJSONObject: object), expected: nil) }
        let snapshot = try await io.historyMaintenanceSnapshot()
        let plan = try await io.prepareHistoryMaintenance(snapshot, intent: .settings(enabled: true, limit: 1))
        XCTAssertEqual(Set(plan.removedRecords), [a1,b0,o0,t0])
        XCTAssertEqual(Set(plan.removedBlobs), Set(["obsolete","orphan-old","trash-old","loose"].map { images[$0]! }))
        XCTAssertEqual(plan.keptRemoved, 0)
        for (path, bytes) in snapshot.records { let actual = try await io.read(path); XCTAssertEqual(actual, bytes, "Review preparation must not remove versions") }
        _ = try await io.applyHistoryMaintenance(plan)
        let final = try await VaultFiles(root: root!).historyMaintenanceSnapshot()
        XCTAssertEqual(Set(final.records.keys), [a0,keptDelta,a2,b1,o1,t1])
        XCTAssertTrue(final.groups.flatMap(\.versions).allSatisfy { !$0.incomplete })
        let configuration = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(final.configuration.bytes)) as? [String: Any])
        XCTAssertNotNil(configuration["foreign"]); XCTAssertEqual(configuration["checkpointLimit"] as? Int, 1)
        for name in ["kept","shared","live","revision","recovery","audit"] { let bytes = try await io.read(images[name]!); XCTAssertEqual(bytes, Data(name.utf8)) }
        for path in plan.removedBlobs { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)) }
        for (path, text) in [("A.md",a),("B.md",b),(".trash/Deleted.md",trash),("Incoming.md",incoming)] { let bytes = try await io.read(path); XCTAssertEqual(bytes, Data(text.utf8)) }
        let live = try await io.read("assets/live.png"); XCTAssertEqual(live, Data([137,80,78,71,9]))
        for (path, _) in metadata where path != ".zerus/history-settings.json" { let bytes = try await io.read(path); XCTAssertEqual(bytes, snapshot.metadata[path]) }
        // Clearing one note must keep an image still used by other histories.
        let bHistory = try await io.historySnapshot(notePath: "B.md")
        let bClear = try await io.prepareHistory(bHistory, action: .clear)
        XCTAssertTrue(bClear.maintenance?.removedBlobs.isEmpty == true)
        _ = try await io.applyHistory(bClear)
        let shared = try await io.read(images["shared"]!); XCTAssertEqual(shared, Data("shared".utf8))
        // Ambiguous live identities suspend pruning on later ordinary saves too.
        try await io.write("Duplicate.md", data: Data(a.utf8), expected: nil)
        let prior = final.records
        try await io.write("A.md", data: Data((a + "New body\n").utf8), expected: Data(a.utf8))
        let duplicated = try await io.historyMaintenanceSnapshot()
        XCTAssertTrue(Set(prior.keys).subtracting([b1]).isSubset(of: Set(duplicated.records.keys)))
        let clearAll = try await io.prepareHistoryMaintenance(duplicated, intent: .clearAll)
        XCTAssertEqual(clearAll.keptRemoved, 1)
        XCTAssertEqual(Set(clearAll.removedBlobs), Set(["kept", "shared"].map { images[$0]! }))
        _ = try await io.applyHistoryMaintenance(clearAll)
        let cleared = try await io.historyMaintenanceSnapshot(); XCTAssertTrue(cleared.records.isEmpty)
        for name in ["live","revision","recovery","audit"] { let bytes = try await io.read(images[name]!); XCTAssertEqual(bytes, Data(name.utf8)) }
    }

    func testUnsupportedHistoryProtectsImagesAndVaultClearPreservesAuditAndOpaqueFiles() async throws {
        let (io, unused, _) = try await fixture(root!)
        let future = Data("{\"schema\":99,\"future\":true}".utf8)
        try await io.write(".zerus/history/notes/future/future.json", data: future, expected: nil)
        let snapshot = try await io.historyMaintenanceSnapshot()
        let cleanup = try await io.prepareHistoryMaintenance(snapshot, intent: .cleanup)
        XCTAssertTrue(cleanup.removedBlobs.isEmpty); XCTAssertFalse(cleanup.warnings.isEmpty)
        _ = try await io.applyHistoryMaintenance(cleanup)
        let retained = try await io.read(unused); XCTAssertEqual(retained, Data("unused".utf8))
        let opaque = Data([0,255,7]), audit = Data("{\"transaction\":\"preserve\"}".utf8)
        try await io.write(".zerus/history/notes/legacy/opaque.bin", data: opaque, expected: nil)
        try await io.write(".zerus/history/receipt.json", data: audit, expected: nil)
        let clear = try await io.prepareHistoryMaintenance(io.historyMaintenanceSnapshot(), intent: .clearAll)
        XCTAssertEqual(clear.removedRecords.count, 2); XCTAssertEqual(clear.unrecognizedRemoved, 1); XCTAssertTrue(clear.removedBlobs.isEmpty)
        _ = try await io.applyHistoryMaintenance(clear)
        let final = try await io.historyMaintenanceSnapshot(); XCTAssertTrue(final.records.isEmpty)
        let opaqueAfter = try await io.read(".zerus/history/notes/legacy/opaque.bin"), auditAfter = try await io.read(".zerus/history/receipt.json")
        XCTAssertEqual(opaqueAfter, opaque); XCTAssertEqual(auditAfter, audit)
        let note = try await io.read("Note.md"); XCTAssertTrue(String(decoding: note, as: UTF8.self).contains("Current"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(unused).path))
        let journals = root.appendingPathComponent(".zerus/native-transactions")
        let pending = FileManager.default.fileExists(atPath: journals.path) ? try FileManager.default.contentsOfDirectory(atPath: journals.path) : []
        XCTAssertTrue(pending.isEmpty, "A no-op cleanup must not leave an empty recovery record")
    }

    func testCleanupRejectsNewNotesRecordsBlobsMetadataAndChangedBytesBeforeAnyDeletion() async throws {
        for scenario in ["note-added","note-changed","record-added","record-changed","metadata-added","metadata-changed","blob-added","blob-changed","draft-added"] {
            let folder = root.appendingPathComponent(scenario); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let (io, unused, recordPath) = try await fixture(folder)
            let settings = Data("{\"enabled\":true,\"checkpointLimit\":10}".utf8)
            try await io.write(".zerus/history-settings.json", data: settings, expected: nil)
            let plan = try await io.prepareHistoryMaintenance(io.historyMaintenanceSnapshot(), intent: .cleanup)
            XCTAssertEqual(plan.removedBlobs, [unused])
            var session: NoteSession?
            switch scenario {
            case "note-added": try Data(("# Incoming\n![Keep](" + unused + ")\n").utf8).write(to: folder.appendingPathComponent("New.md"))
            case "note-changed": try Data(("# Note\n![Keep](" + unused + ")\n").utf8).write(to: folder.appendingPathComponent("Note.md"))
            case "record-added": _ = try await record(io, note: "history-note", id: "late", ordinal: 2, image: unused)
            case "record-changed": try Data("{\"schema\":99}".utf8).write(to: folder.appendingPathComponent(recordPath))
            case "metadata-added": try Data(("\"" + unused + "\"").utf8).write(to: folder.appendingPathComponent(".zerus/late.json"))
            case "metadata-changed": try (settings + Data("\n".utf8)).write(to: folder.appendingPathComponent(".zerus/history-settings.json"))
            case "blob-added": _ = try await blob(io, "new image")
            case "blob-changed": try Data("Outside bytes".utf8).write(to: folder.appendingPathComponent(unused))
            case "draft-added":
                let document = NoteDocument(path: "Note.md", content: String(decoding: try await io.read("Note.md"), as: UTF8.self), modified: Date())
                session = await MainActor.run {
                    let editor = NoteSession(note: document, root: folder, io: io, onSave: { _ in })
                    editor.updateBody("# Draft\\n![Keep](" + unused + ")\\n")
                    editor.holdForMutation(true)
                    return editor
                }
            default: XCTFail("Unexpected fixture")
            }
            do { _ = try await io.applyHistoryMaintenance(plan); XCTFail("Stale cleanup accepted: " + scenario) } catch {}
            let preserved = try await io.read(unused); XCTAssertEqual(preserved, Data((scenario == "blob-changed" ? "Outside bytes" : "unused").utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(recordPath).path))
            if let session {
                let protected = try await io.prepareHistoryMaintenance(io.historyMaintenanceSnapshot(), intent: .cleanup)
                XCTAssertTrue(protected.removedBlobs.isEmpty, "Unsaved recovery drafts protect their history images")
                await session.reload(); await session.deactivate()
            }
        }
    }

    @MainActor
    func testVaultWideDeletionReviewCannotApplyAfterSwitchingAwayAndReturning() async throws {
        let bookmark = UserDefaults.standard.data(forKey: "zerus.native.vault.bookmark")
        defer { if let bookmark { UserDefaults.standard.set(bookmark, forKey: "zerus.native.vault.bookmark") } else { UserDefaults.standard.removeObject(forKey: "zerus.native.vault.bookmark") } }
        let (io, unused, record) = try await fixture(root!), other = root.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let store = VaultStore(); await store.open(root)
        let snapshot = try await store.historyMaintenanceSnapshot(workspace: store.workspaceID)
        let plan = try await store.prepareHistoryMaintenance(snapshot, intent: .clearAll)
        await store.open(other)
        do { try await store.saveHistoryMaintenance(plan); XCTFail("An old permanent review must not affect the new vault") } catch {}
        await store.open(root)
        do { try await store.saveHistoryMaintenance(plan); XCTFail("Returning to the same path must not reauthorize the review") } catch {}
        let image = try await io.read(unused); XCTAssertEqual(image, Data("unused".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(record).path))
    }
}
