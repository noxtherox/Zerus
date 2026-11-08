import XCTest
@testable import ZerusNative

final class NativeRelationTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testLegacyRelationCreatesHiddenNonCollidingInverseAndUnlinksBothSides() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"futureMetadata":{"keep":7},"Unrelated":{"unsupported":true},"Work/Tasks":[{"name":"Epic","type":"relation","relationTypeKey":"Work/Epics","relationInverseHidden":true,"futureFlag":{"keep":true}}],"Work/Epics":[{"name":"Tasks","type":"relation","relationTypeKey":"Work/Other","relationMultiple":false},{"name":"Tasks 2","type":"text"}]}"#
        let a = "---\r\n# foreign comment\r\nzerus-id: task-a\r\nForeign:\r\n  nested: [one, two]\r\n---\r\n# Task A\r\n\r\nA **body** with a table.\r\n| A | B |\r\n| - | - |\r\n| α | β |\r\n"
        let b = "---\nzerus-id: epic-b\nTasks: 'zerus:other|Other task' # keep occupied inverse\nTasks 2: foreign value\n---\n# Epic B\n\nBody stays.\n"
        let c = "---\nzerus-id: epic-c\n---\n# Epic C\n\nChild folder body.\n"
        for (path, value) in [(".zerus/properties.json", schema), ("Work/Tasks/A.md", a), ("Work/Epics/B.md", b), ("Work/Epics/Sub/C.md", c)] { try await io.write(path, data: Data(value.utf8), expected: nil) }
        let snapshot = try await io.relationSnapshot(notePath: "Work/Tasks/A.md", name: "Epic")
        _ = try await io.applyRelation(snapshot.plan(selected: ["Work/Epics/B.md"], unresolved: []))
        let savedA = try await io.read("Work/Tasks/A.md"), savedB = try await io.read("Work/Epics/B.md")
        XCTAssertEqual(String(data: savedA, encoding: .utf8), a.replacingOccurrences(of: "---\r\n# Task A", with: "Epic: \"zerus:epic-b|Epic B\"\r\n---\r\n# Task A"))
        XCTAssertEqual(String(data: savedB, encoding: .utf8), b.replacingOccurrences(of: "---\n# Epic B", with: "Tasks 3: [\"zerus:task-a|Task A\"]\n---\n# Epic B"))
        let schemaAfter = try await io.read(".zerus/properties.json")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: schemaAfter) as? [String: Any])
        XCTAssertEqual((object["futureMetadata"] as? [String: Int])?["keep"], 7)
        let sourceDef = try XCTUnwrap((object["Work/Tasks"] as? [[String: Any]])?.first)
        let inverse = try XCTUnwrap((object["Work/Epics"] as? [[String: Any]])?.first { $0["name"] as? String == "Tasks 3" })
        let pair = try XCTUnwrap(sourceDef["relationPairId"] as? String)
        XCTAssertNotNil(UUID(uuidString: pair)); XCTAssertEqual(inverse["relationPairId"] as? String, pair)
        XCTAssertEqual(inverse["relationHidden"] as? Bool, true)
        XCTAssertEqual(inverse["relationTypeKey"] as? String, "Work/Tasks")
        XCTAssertEqual((sourceDef["futureFlag"] as? [String: Bool])?["keep"], true)
        let modified = try root.appendingPathComponent(".zerus/properties.json").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let change = try await io.relationSnapshot(notePath: "Work/Tasks/A.md", name: "Epic")
        _ = try await io.applyRelation(change.plan(selected: ["Work/Epics/Sub/C.md"], unresolved: []))
        let switchedB = try await io.read("Work/Epics/B.md"), switchedC = try await io.read("Work/Epics/Sub/C.md")
        XCTAssertEqual(String(data: switchedB, encoding: .utf8), b)
        XCTAssertEqual(String(data: switchedC, encoding: .utf8), c.replacingOccurrences(of: "---\n# Epic C", with: "Tasks 3: [\"zerus:task-a|Task A\"]\n---\n# Epic C"))
        let unchangedSchema = try await io.read(".zerus/properties.json"); XCTAssertEqual(unchangedSchema, schemaAfter)
        XCTAssertEqual(try root.appendingPathComponent(".zerus/properties.json").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified, "An unchanged schema used for conflict validation must not be rewritten")
        let clear = try await io.relationSnapshot(notePath: "Work/Tasks/A.md", name: "Epic")
        _ = try await io.applyRelation(clear.plan(selected: [], unresolved: []))
        let clearedA = try await io.read("Work/Tasks/A.md"), clearedC = try await io.read("Work/Epics/Sub/C.md")
        XCTAssertEqual(clearedA, Data(a.utf8)); XCTAssertEqual(clearedC, Data(c.utf8))
    }

    func testPairedInverseRetainsOtherLinksAndRejectsStaleNotesAndSchemas() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"Tasks":[{"name":"Epic","type":"relation","relationTypeKey":"Epics","relationPairId":"shared-pair"}],"Epics":[{"name":"Tasks","type":"relation","relationTypeKey":"Tasks","relationPairId":"shared-pair","relationMultiple":false,"foreignSetting":42}]}"#
        let a = "---\nzerus-id: t1\n---\n# Task One\nBody one.\n"
        let b = "---\nzerus-id: e1\nTasks: [\"zerus:t2|Task Two\", \"zerus:t3|Task Three\"]\n---\n# Epic One\nBody epic.\n"
        for (path, text) in [(".zerus/properties.json", schema), ("Tasks/A.md", a), ("Epics/B.md", b), ("Tasks/Other.md", "---\nzerus-id: t2\n---\n# Task Two\n"), ("Tasks/Third.md", "---\nzerus-id: t3\n---\n# Task Three\n")] { try await io.write(path, data: Data(text.utf8), expected: nil) }
        let snapshot = try await io.relationSnapshot(notePath: "Tasks/A.md", name: "Epic"), plan = try snapshot.plan(selected: ["Epics/B.md"], unresolved: [])
        let outside = Data((b + "An outside paragraph.\n").utf8)
        try await io.write("Epics/B.md", data: outside, expected: Data(b.utf8))
        do { _ = try await io.applyRelation(plan); XCTFail("A paired change must not overwrite an outside edit") }
        catch { XCTAssertTrue(error.localizedDescription.contains("changed outside")) }
        let retainedA = try await io.read("Tasks/A.md"), retainedSchema = try await io.read(".zerus/properties.json")
        XCTAssertEqual(retainedA, Data(a.utf8)); XCTAssertEqual(retainedSchema, Data(schema.utf8))
        try await io.write("Epics/B.md", data: Data(b.utf8), expected: outside)
        let changedSchema = Data((schema + "\n").utf8)
        try await io.write(".zerus/properties.json", data: changedSchema, expected: Data(schema.utf8))
        do { _ = try await io.applyRelation(plan); XCTFail("A schema changed after review invalidates the whole paired operation") }
        catch { XCTAssertTrue(error.localizedDescription.contains("properties.json changed outside")) }
        let stillA = try await io.read("Tasks/A.md"), stillB = try await io.read("Epics/B.md")
        XCTAssertEqual(stillA, Data(a.utf8)); XCTAssertEqual(stillB, Data(b.utf8))
        let fresh = try await io.relationSnapshot(notePath: "Tasks/A.md", name: "Epic")
        _ = try await io.applyRelation(fresh.plan(selected: ["Epics/B.md"], unresolved: []))
        let joined = try await io.read("Epics/B.md")
        XCTAssertTrue(String(decoding: joined, as: UTF8.self).contains("Tasks: [\"zerus:t2|Task Two\", \"zerus:t3|Task Three\", \"zerus:t1|Task One\"]\n"))
        let promotedSchema = try await io.read(".zerus/properties.json")
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: promotedSchema) as? [String: Any])
        var defs = try XCTUnwrap(object["Epics"] as? [[String: Any]])
        XCTAssertEqual(defs[0]["relationMultiple"] as? Bool, true); XCTAssertEqual(defs[0]["foreignSetting"] as? Int, 42)
        // Older clients may have kept multiple values on a single-note inverse.
        // Removing one edge must promote and retain the remaining two values.
        defs[0]["relationMultiple"] = false; object["Epics"] = defs
        let schemaBytes = try await io.read(".zerus/properties.json")
        try await io.write(".zerus/properties.json", data: JSONSerialization.data(withJSONObject: object), expected: schemaBytes)
        let clear = try await io.relationSnapshot(notePath: "Tasks/A.md", name: "Epic")
        _ = try await io.applyRelation(clear.plan(selected: [], unresolved: []))
        let retained = try await io.read("Epics/B.md")
        XCTAssertEqual(retained, Data(b.utf8))
    }

    func testLegacyIdentifiersUnknownReferencesAndEligibilityStayProtected() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"Tasks":[{"name":"Related","type":"relation","relationTypeKey":"Epics","relationMultiple":true}],"Tasks/Child":[{"name":"Related","type":"relation","relationTypeKey":"Other","relationMultiple":false}]}"#
        for (path, text) in [(".zerus/properties.json", schema), ("Tasks/A.md", "---\nRelated: [\"Missing note\"]\n---\n# Legacy task\n"), ("Epics/B.md", "# Legacy epic\n"), ("Other/X.md", "# Other\n"), ("Tasks/Child/C.md", "# Child task\n"), (".trash/Epics/Deleted.md", "# Deleted epic\n")] { try await io.write(path, data: Data(text.utf8), expected: nil) }
        let snapshot = try await io.relationSnapshot(notePath: "Tasks/A.md", name: "Related")
        XCTAssertEqual(try snapshot.selection().unresolved, ["Missing note"])
        for path in ["Other/X.md", "Tasks/A.md", ".trash/Epics/Deleted.md"] {
            XCTAssertThrowsError(try snapshot.plan(selected: [path], unresolved: ["Missing note"]))
        }
        _ = try await io.applyRelation(snapshot.plan(selected: ["Epics/B.md"], unresolved: ["Missing note"]))
        let a = String(decoding: try await io.read("Tasks/A.md"), as: UTF8.self), b = String(decoding: try await io.read("Epics/B.md"), as: UTF8.self)
        let sourceID = try XCTUnwrap(NoteDocument(path: "Tasks/A.md", content: a, modified: Date()).stableID), targetID = try XCTUnwrap(NoteDocument(path: "Epics/B.md", content: b, modified: Date()).stableID)
        XCTAssertNotNil(UUID(uuidString: sourceID)); XCTAssertNotNil(UUID(uuidString: targetID))
        XCTAssertTrue(a.contains("Related: [\"zerus:\(targetID)|Legacy epic\", \"Missing note\"]\n"))
        XCTAssertTrue(b.contains("Tasks: [\"zerus:\(sourceID)|Legacy task\"]\n"))
        let child = try await io.relationSnapshot(notePath: "Tasks/Child/C.md", name: "Related")
        XCTAssertEqual(try child.definition().owner, "Tasks/Child")
        XCTAssertThrowsError(try child.plan(selected: ["Epics/B.md"], unresolved: []))
        let beforeDuplicate = try await io.relationSnapshot(notePath: "Tasks/A.md", name: "Related")
        let identityPlan = try beforeDuplicate.plan(selected: ["Epics/B.md"], unresolved: ["Missing note"])
        try await io.write("Epics/Duplicate.md", data: Data("---\nzerus-id: \(targetID)\n---\n# Another epic\n".utf8), expected: nil)
        let duplicate = try await io.relationSnapshot(notePath: "Tasks/A.md", name: "Related")
        XCTAssertThrowsError(try duplicate.plan(selected: ["Epics/B.md"], unresolved: []))
        // New targets and renamed titles invalidate reference resolution even
        // when the already reviewed source and target bytes are unchanged.
        do { _ = try await io.applyRelation(identityPlan); XCTFail("The target identity set changed after review") }
        catch { XCTAssertTrue(error.localizedDescription.contains("added, moved or renamed")) }
    }
}
