import XCTest
#if os(macOS)
@testable import Zerus_Native
#else
@testable import ZerusNative
#endif

/// A bulk relation transaction can change another selected note through an
/// inverse before that note's own field is processed. Receipts and later-edit
/// checks must use the transaction boundary, not those intermediate values.
final class NativeBulkRelationBatchTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testUndoAndRedoRestoreBothInitiallyRelatedSelectedNotes() async throws {
        let io = try await fixture()
        let changed = try await io.bulkSnapshot(), receipt = try XCTUnwrap(changed.records.first)
        let undo = try changed.transition(receipt.id, undo: true)
        print("Paired selected-note undo issues:", undo.issues.map(\.reason))
        XCTAssertTrue(undo.issues.isEmpty)
        _ = try await io.applyBulk(undo)
        let restored = try await io.bulkSnapshot()
        XCTAssertEqual(try references(restored, path: "Work/A.md"), ["zerus:b|B"])
        XCTAssertEqual(try references(restored, path: "Work/B.md"), ["zerus:a|A"])
        XCTAssertEqual(restored.records[0].appliedCount, 0)
        let redo = try restored.transition(receipt.id, undo: false)
        XCTAssertTrue(redo.issues.isEmpty)
        _ = try await io.applyBulk(redo)
        let redone = try await io.bulkSnapshot()
        XCTAssertEqual(try references(redone, path: "Work/A.md"), ["zerus:c|C"])
        XCTAssertEqual(try references(redone, path: "Work/B.md"), ["zerus:c|C"])
        XCTAssertEqual(redone.records[0].appliedCount, 2)
    }
    func testUndoRetainsALaterRelationEditWhileRestoringTheUnchangedPeer() async throws {
        let io = try await fixture()
        let changed = try await io.bulkSnapshot(), id = try XCTUnwrap(changed.records.first?.id)
        let editing = try await io.relationSnapshot(notePath: "Work/B.md", name: "Related")
        _ = try await io.applyRelation(editing.plan(selected: ["Work/D.md"], unresolved: []))
        let current = try await io.bulkSnapshot(), undo = try current.transition(id, undo: true)
        XCTAssertEqual(undo.issues.count, 1)
        XCTAssertTrue(undo.issues[0].reason.contains("changed later"))
        _ = try await io.applyBulk(undo)
        let result = try await io.bulkSnapshot()
        XCTAssertEqual(try references(result, path: "Work/A.md"), ["zerus:b|B"])
        let retained = try references(result, path: "Work/B.md")
        XCTAssertTrue(retained.contains("zerus:d|D"), "Undo must preserve the later relationship")
        XCTAssertTrue(retained.contains("zerus:a|A"), "The restored peer must keep its inverse")
        XCTAssertFalse(retained.contains("zerus:c|C"))
        XCTAssertEqual(result.records[0].appliedCount, 1)
    }
    func testLegacyIntermediateReceiptsKeepTheirConservativeGuard() async throws {
        let io = try await fixture(), current = try await io.bulkSnapshot()
        var object = try JSONSerialization.jsonObject(with: current.historyBytes!) as! [String: Any]
        var records = object["records"] as! [[String: Any]], record = records[0]
        record.removeValue(forKey: "boundaryVersion")
        var entries = record["entries"] as! [[String: Any]], second = entries[1], fields = second["fields"] as! [[String: Any]]
        fields[0].removeValue(forKey: "before"); second["fields"] = fields; entries[1] = second; record["entries"] = entries; records[0] = record; object["records"] = records
        try await io.write(NativeBulkHistory.path, data: JSONSerialization.data(withJSONObject: object), expected: current.historyBytes)
        let legacy = try await io.bulkSnapshot(), undo = try legacy.transition(legacy.records[0].id, undo: true)
        XCTAssertEqual(undo.issues.count, 1, "An old incomplete receipt must not clear an inverse restored by the preceding field")
        _ = try await io.applyBulk(undo)
        let result = try await io.bulkSnapshot(), retained = try references(result, path: "Work/B.md")
        XCTAssertTrue(retained.contains("zerus:a|A"))
        XCTAssertTrue(retained.contains("zerus:c|C"))
    }
    private func fixture() async throws -> VaultFiles {
        let io = VaultFiles(root: root)
        for letter in ["A", "B", "C", "D"] {
            try await io.write("Work/\(letter).md", data: Data("---\nzerus-id: \(letter.lowercased())\n---\n# \(letter)\n\nBody \(letter).\n".utf8), expected: nil)
        }
        let schema = Data(#"{"Work":[{"name":"Related","type":"relation","relationTypeKey":"Work","relationMultiple":true,"relationInverseName":"Related","relationPairId":"paired"}]}"#.utf8)
        try await io.write(".zerus/properties.json", data: schema, expected: nil)
        let linking = try await io.relationSnapshot(notePath: "Work/A.md", name: "Related")
        _ = try await io.applyRelation(linking.plan(selected: ["Work/B.md"], unresolved: []))
        let snapshot = try await io.bulkSnapshot()
        let selected = snapshot.source.notes.filter { ["Work/A.md", "Work/B.md"].contains($0.path) }.sorted { $0.path < $1.path }
        let plan = try snapshot.plan(selected: selected, mutation: .init(properties: [.init(name: "Related", value: .list(["zerus:c|C"]))]))
        XCTAssertTrue(plan.issues.isEmpty)
        _ = try await io.applyBulk(plan)
        return io
    }
    private func references(_ snapshot: NativeBulkSnapshot, path: String) throws -> [String] {
        try NativeRelationSnapshot.values(XCTUnwrap(snapshot.source.notes.first { $0.path == path }), name: "Related")
    }
}
