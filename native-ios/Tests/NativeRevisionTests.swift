import XCTest
@testable import ZerusNative

final class NativeRevisionTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testRevisionsFreezeActualAssetBytesAndPromoteWithTodaysTitleAndProperties() async throws {
        let io = VaultFiles(root: root!)
        let attachment = #"{"id":"sheet","kind":"vault","name":"Costs.xlsx","path":"files/Costs.xlsx","managed":true,"foreign":"keep"}"#
        var original = "---\r\nzerus-id: proposal\r\nForeign:\r\n  nested: [one, two] # keep\r\ntags: [draft]\r\nzerus-file-id: doc\r\nzerus-file-name: Proposal.pdf\r\nzerus-file-kind: vault\r\nzerus-file-path: files/Proposal.pdf\r\nzerus-file-managed: true\r\n---\r\n# Proposal\r\n\r\nFirst proposal\r\n![Chart](assets/chart.png \"Caption\")\r\n[PDF][report]\r\n[report]: <files/spec%20one.pdf?download=1#page=2>\r\n<img src=\"assets/chart.png\" alt=\"Keep caption\">\r\n[Other note](Other.md)\r\n`![literal](missing.png)`\r\n"
        original = original.replacingOccurrences(of: "[PDF][report]\r\n[report]:", with: "[PDF][report]\r\n\r\n[report]:")
        original = try NativeFrontmatter(original).setting("zerus-attachments", value: .list([attachment]))
        try await io.write("Work/Proposal.md", data: Data(original.utf8), expected: nil)
        let bytes = Data([0, 1, 2, 255, 7])
        for path in ["assets/chart.png", "Work/files/spec one.pdf", "files/Costs.xlsx", "files/Proposal.pdf"] { try await io.write(path, data: bytes, expected: nil) }
        let first = try await io.revisionSnapshot(notePath: "Work/Proposal.md")
        let plan = try await io.prepareRevision(first, action: .create)
        let untouched = try await io.read("Work/Proposal.md"); XCTAssertEqual(untouched, Data(original.utf8))
        _ = try await io.applyRevision(plan)
        var second = try await io.revisionSnapshot(notePath: "Work/Proposal.md")
        XCTAssertEqual(second.index.revisions.map(\.number), [1, 2])
        XCTAssertEqual(second.note.property("zerus-revision-transaction"), second.index.object["commitToken"] as? String)
        XCTAssertEqual(Set(second.index.object["ownedFiles"] as? [String] ?? []), ["files/Costs.xlsx", "files/Proposal.pdf"])
        XCTAssertTrue(second.note.content.contains("Foreign:\r\n  nested: [one, two] # keep\r\n"))
        XCTAssertTrue(second.note.content.contains("[Other note](Other.md)\r\n`![literal](missing.png)`"))
        let old = try XCTUnwrap(second.index.revisions.first)
        let oldFiles = try snapshotFiles(old.content)
        let currentFiles = try snapshotFiles(second.note.content)
        XCTAssertEqual(oldFiles.count, 4, old.content); XCTAssertEqual(currentFiles.count, 4, second.note.content)
        XCTAssertTrue(Set(oldFiles).isDisjoint(with: currentFiles))
        for path in oldFiles { let saved = try await io.read(path); XCTAssertEqual(saved, bytes) }
        for path in currentFiles { try await io.write(path, data: Data([9]), expected: bytes) }
        var edit = second.note.content.replacingOccurrences(of: "# Proposal", with: "# Approved proposal").replacingOccurrences(of: "First proposal", with: "Second proposal")
        edit = try NativeFrontmatter(edit).setting("tags", value: .list(["approved"]))
        try await io.write(second.note.path, data: Data(edit.utf8), expected: Data(second.note.content.utf8))
        second = try await io.revisionSnapshot(notePath: second.note.path)
        let promoted = try await io.prepareRevision(second, action: .promote(old.id))
        _ = try await io.applyRevision(promoted)
        let third = try await io.revisionSnapshot(notePath: second.note.path)
        XCTAssertEqual(third.index.revisions.map(\.number), [1, 2, 3])
        XCTAssertTrue(third.note.parts.body.hasPrefix("# Approved proposal\r\n\r\nFirst proposal"))
        XCTAssertEqual(third.note.property("tags"), "[\"approved\"]")
        for path in try snapshotFiles(third.note.content) { let saved = try await io.read(path); XCTAssertEqual(saved, bytes) }
        let frozenSecond = try XCTUnwrap(third.index.revisions.first { $0.number == 2 })
        XCTAssertTrue(frozenSecond.content.contains("Second proposal"))
        for path in try snapshotFiles(frozenSecond.content) { let saved = try await io.read(path); XCTAssertEqual(saved, Data([9])) }
        let attachments = try XCTUnwrap(NativeFrontmatter(third.note.content).entry("zerus-attachments")?.value?.selections.first)
        let preserved = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(attachments.utf8)) as? [String: Any])
        XCTAssertEqual(preserved["foreign"] as? String, "keep")
        let reopened = try await VaultFiles(root: root!).revisionSnapshot(notePath: "Work/Proposal.md")
        XCTAssertEqual(reopened.index.currentID, third.index.currentID)
    }

    func testTrashFallbackRestorationMonotonicNumbersAndForeignManifestFieldsSurvive() async throws {
        let io = VaultFiles(root: root!), path = "Note.md"
        try await io.write(path, data: Data("# Note\nFirst body\n".utf8), expected: nil)
        var snapshot = try await io.revisionSnapshot(notePath: path)
        _ = try await io.applyRevision(io.prepareRevision(snapshot, action: .create))
        snapshot = try await io.revisionSnapshot(notePath: path)
        XCTAssertNotNil(snapshot.note.stableID)
        let secondID = snapshot.index.currentID
        let edited = snapshot.note.content.replacingOccurrences(of: "First body", with: "Second body")
        try await io.write(path, data: Data(edited.utf8), expected: Data(snapshot.note.content.utf8))
        snapshot = try await io.revisionSnapshot(notePath: path)
        _ = try await io.applyRevision(io.prepareRevision(snapshot, action: .create))
        snapshot = try await io.revisionSnapshot(notePath: path)
        var object = snapshot.index.object
        object["foreign"] = ["keep": [1, 2]]
        var rows = object["revisions"] as! [[String: Any]]; rows[0]["foreign"] = "retained"; object["revisions"] = rows
        try await io.write(snapshot.indexPath, data: JSONSerialization.data(withJSONObject: object), expected: snapshot.indexBytes)
        snapshot = try await io.revisionSnapshot(notePath: path)
        let thirdID = snapshot.index.currentID
        _ = try await io.applyRevision(io.prepareRevision(snapshot, action: .trash(thirdID)))
        snapshot = try await io.revisionSnapshot(notePath: path)
        XCTAssertEqual(snapshot.index.currentID, secondID)
        XCTAssertTrue(snapshot.note.content.contains("Second body"))
        XCTAssertNotNil(snapshot.index.revisions.first { $0.id == thirdID }?.deletedAt)
        _ = try await io.applyRevision(io.prepareRevision(snapshot, action: .restore(thirdID)))
        snapshot = try await io.revisionSnapshot(notePath: path)
        XCTAssertEqual(snapshot.index.currentID, secondID)
        XCTAssertNil(snapshot.index.revisions.first { $0.id == thirdID }?.deletedAt)
        _ = try await io.applyRevision(io.prepareRevision(snapshot, action: .create))
        snapshot = try await io.revisionSnapshot(notePath: path)
        XCTAssertEqual(snapshot.index.revisions.map(\.number), [1, 2, 3, 4])
        XCTAssertNotNil(snapshot.index.object["foreign"])
        XCTAssertEqual((snapshot.index.object["revisions"] as? [[String: Any]])?.first?["foreign"] as? String, "retained")
        for revision in snapshot.index.revisions where revision.id != snapshot.index.currentID {
            _ = try await io.applyRevision(io.prepareRevision(snapshot, action: .trash(revision.id)))
            snapshot = try await io.revisionSnapshot(notePath: path)
        }
        do { _ = try await io.prepareRevision(snapshot, action: .trash(snapshot.index.currentID)); XCTFail("The last revision must retain the whole-note Trash contract") }
        catch { XCTAssertTrue(error.localizedDescription.contains("whole note")) }
    }

    func testStaleAssetOrIndexReviewAndMissingFilesNeverPartiallyChangeTheNote() async throws {
        let io = VaultFiles(root: root!), path = "Note.md", body = "---\nzerus-id: safe\n---\n# Note\n![Image](assets/plot.png)\n"
        try await io.write(path, data: Data(body.utf8), expected: nil)
        let first = try await io.revisionSnapshot(notePath: path)
        do { _ = try await io.prepareRevision(first, action: .create); XCTFail("Missing assets must block preparation") } catch {}
        let original = try await io.read(path); XCTAssertEqual(original, Data(body.utf8))
        try await io.write("assets/plot.png", data: Data([1, 2, 3]), expected: nil)
        let plan = try await io.prepareRevision(first, action: .create)
        try await io.write("assets/plot.png", data: Data([4, 5]), expected: Data([1, 2, 3]))
        do { _ = try await io.applyRevision(plan); XCTFail("Asset bytes changed after review") } catch {}
        let unchanged = try await io.read(path); XCTAssertEqual(unchanged, Data(body.utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(first.indexPath).path))
        for change in plan.changes where change.before == nil && change.after != nil { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(change.path).path)) }
        let nextPlan = try await io.prepareRevision(first, action: .create)
        _ = try await io.applyRevision(nextPlan)
        let saved = try await io.revisionSnapshot(notePath: path)
        let stale = try await io.prepareRevision(saved, action: .create)
        let outside = Data("{\"schema\":99,\"foreign\":true}".utf8)
        try await io.write(saved.indexPath, data: outside, expected: saved.indexBytes)
        do { _ = try await io.applyRevision(stale); XCTFail("Outside manifest edit must be retained") } catch {}
        let actual = try await io.read(saved.indexPath); XCTAssertEqual(actual, outside)
        let note = try await io.read(path); XCTAssertEqual(note, Data(saved.note.content.utf8))
    }

    func testInterruptedWebCommitRecoversAccordingToLiveNoteWithoutOverwritingOutsideEdits() async throws {
        let io = VaultFiles(root: root!), path = "Note.md", before = "---\nzerus-id: web-note\n---\n# Note\nBefore\n"
        try await io.write(path, data: Data(before.utf8), expected: nil)
        let initial = try await io.revisionSnapshot(notePath: path)
        var next = initial.index.object; next["commitToken"] = "web-token"
        let after = try NativeFrontmatter(before.replacingOccurrences(of: "Before", with: "After")).setting("zerus-revision-transaction", value: .text("web-token"))
        let pending = try JSONSerialization.data(withJSONObject: ["token": "web-token", "before": before, "after": after, "previous": initial.index.object, "next": next])
        let pendingPath = ".zerus/revisions/notes/web-note/pending.json"
        try await io.write(pendingPath, data: pending, expected: nil)
        try await io.write(path, data: Data(after.utf8), expected: Data(before.utf8))
        let recovered = try await io.revisionSnapshot(notePath: path)
        XCTAssertEqual(recovered.index.object["commitToken"] as? String, "web-token")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(pendingPath).path))
        try await io.write(pendingPath, data: pending, expected: nil)
        try await io.write(path, data: Data(before.utf8), expected: Data(after.utf8))
        let rolledBack = try await io.revisionSnapshot(notePath: path)
        XCTAssertEqual(rolledBack.note.content, before)
        XCTAssertNil(rolledBack.index.object["commitToken"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(pendingPath).path))
        try await io.write(pendingPath, data: pending, expected: nil)
        let external = Data("---\nzerus-id: web-note\n---\n# Note\nOutside edit\n".utf8)
        try await io.write(path, data: external, expected: Data(before.utf8))
        do { _ = try await io.revisionSnapshot(notePath: path); XCTFail("Conflicting interrupted commit must require reconciliation") } catch {}
        let retained = try await io.read(path), record = try await io.read(pendingPath)
        XCTAssertEqual(retained, external); XCTAssertEqual(record, pending)
    }

    func testOwnershipRequiresActualBooleansAndPreservesUnsupportedAttachmentValues() async throws {
        let io = VaultFiles(root: root!)
        let attachment = #"{"id":"file","name":"File.txt","kind":"vault","path":"file.txt","managed":1}"#
        let content = try NativeFrontmatter("---\nzerus-id: malformed\n---\n# Note\nBody\n").setting("zerus-attachments", value: .list([attachment]))
        try await io.write("Note.md", data: Data(content.utf8), expected: nil)
        try await io.write("file.txt", data: Data("Original file".utf8), expected: nil)
        let snapshot = try await io.revisionSnapshot(notePath: "Note.md")
        do { _ = try await io.prepareRevision(snapshot, action: .create); XCTFail("JSON numbers must not be coerced into attachment ownership booleans") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unsupported")) }
        let actual = try await io.read("Note.md"); XCTAssertEqual(actual, Data(content.utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(snapshot.indexPath).path))
        let hub = "---\nzerus-id: quoted-ownership\nzerus-file-id: hub\nzerus-file-name: File.txt\nzerus-file-kind: vault\nzerus-file-path: file.txt\nzerus-file-managed: \"true\"\n---\n# File hub\n"
        try await io.write("File hub.md", data: Data(hub.utf8), expected: nil)
        let hubSnapshot = try await io.revisionSnapshot(notePath: "File hub.md")
        let plan = try await io.prepareRevision(hubSnapshot, action: .create)
        XCTAssertFalse((plan.next.object["ownedFiles"] as? [String] ?? []).contains("file.txt"), "A quoted YAML string is not a managed ownership Boolean")
    }

    private func snapshotFiles(_ content: String) throws -> [String] {
        var files = Set<String>()
        let props = NativeFrontmatter(content)
        if let path = props.entry("zerus-file-path")?.value?.display { files.insert(path) }
        if case .list(let values) = props.entry("zerus-attachments")?.value {
            for value in values { if let item = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any], let path = item["path"] as? String { files.insert(path) } }
        }
        for link in try MarkdownMoveLinks.links(in: NoteDocument.split(content).body) {
            if let url = URL(string: link.value), url.relativePath.hasPrefix(".zerus/revisions/") { files.insert(url.relativePath) }
        }
        return files.sorted()
    }
}
