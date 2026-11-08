import XCTest
@testable import ZerusNative

final class NativeRelationMaintenanceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testMoveCarriesRelationSchemaAndUpgradesIncomingPathLinksBeforeChangingLocation() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"metadata":{"keep":true},"Tasks":[{"name":"Epic","type":"relation","relationTypeKey":"Epics","relationPairId":"pair","relationInverseHidden":true,"foreignFlag":42}],"Epics":[{"name":"Tasks","type":"relation","relationTypeKey":"Tasks","relationPairId":"pair","relationMultiple":true,"relationHidden":true}]}"#
        let source = "---\r\n# foreign comment\r\nzerus-id: task\r\nEpic: 'zerus:epic|Epic'\r\nForeign:\r\n  nested: [one, two]\r\n---\r\n# Task\r\n\r\nA **body** and ![image](assets/one.png).\r\n"
        let target = "---\nzerus-id: epic\nTasks: [\"Tasks/A.MD\"]\n---\n# Epic\nOriginal epic body.\n"
        for (path, text) in [(".zerus/properties.json", schema), ("Tasks/A.MD", source), ("Epics/E.md", target)] { try await io.write(path, data: Data(text.utf8), expected: nil) }
        let snapshot = try await io.relationDefinitionSnapshot()
        let plan = try snapshot.movePlan(source: "Tasks/A.MD", destination: "Archive/Done/A.MD")
        XCTAssertEqual(Set(plan.changedNotes), ["Tasks/A.MD", "Archive/Done/A.MD", "Epics/E.md"])
        let beforeSave = try await io.read("Tasks/A.MD"), schemaBeforeSave = try await io.read(".zerus/properties.json")
        XCTAssertEqual(beforeSave, Data(source.utf8)); XCTAssertEqual(schemaBeforeSave, Data(schema.utf8), "Preparing or canceling a review must not write files")
        let after = try await io.applyRelationMaintenance(plan)
        XCTAssertFalse(after.notes.contains { $0.path == "Tasks/A.MD" })
        let moved = try XCTUnwrap(after.notes.first { $0.path == "Archive/Done/A.MD" })
        XCTAssertEqual(moved.content, source, "A schema-preserving move retains exact source bytes when links are already stable")
        let definitions = try await io.schemaSnapshot()
        let carried = try XCTUnwrap(try definitions.definitions(owner: "Archive/Done").first)
        XCTAssertEqual(carried.name, "Epic"); XCTAssertEqual(carried.relationPairID, "pair"); XCTAssertTrue(carried.relationInverseHidden)
        let inverse = try XCTUnwrap(try definitions.definitions(owner: "Epics").first)
        XCTAssertEqual(inverse.relationTypeKey, ""); XCTAssertTrue(inverse.hidden)
        XCTAssertTrue(NativeRelationSnapshot.eligible(moved, for: inverse), "The moved note must remain eligible when re-adding its inverse")
        let savedTarget = String(decoding: try await io.read("Epics/E.md"), as: UTF8.self)
        XCTAssertTrue(savedTarget.contains("Tasks: [\"zerus:task|Task\"]"))
        XCTAssertEqual(NativeFrontmatter(savedTarget).body, NativeFrontmatter(target).body)
        let schemaBytes = try await io.read(".zerus/properties.json")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: schemaBytes) as? [String: Any])
        XCTAssertEqual((object["Archive/Done"] as? [[String: Any]])?[0]["foreignFlag"] as? Int, 42)
        XCTAssertEqual((object["metadata"] as? [String: Bool])?["keep"], true)
        let reopened = try await io.relationSnapshot(notePath: moved.path, name: "Epic")
        _ = try await io.applyRelation(reopened.plan(selected: [], unresolved: []))
        let unlinkedTarget = String(decoding: try await io.read("Epics/E.md"), as: UTF8.self)
        XCTAssertNil(NativeFrontmatter(unlinkedTarget).entry("Tasks"))
    }

    func testMoveRespectsDestinationDefinitionsAndRefusesAnOccupiedReviewedDestination() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"Tasks":[{"name":"Epic","type":"relation","relationTypeKey":"Epics","relationPairId":"old-pair"}],"Epics":[{"name":"Tasks","type":"relation","relationPairId":"old-pair","relationMultiple":true}],"Archive":[{"name":"Epic","type":"text","custom":"keep"}],"New type":[{"name":"Epic","type":"relation","relationTypeKey":"Epics","relationPairId":"new-pair"}]}"#
        let source = "---\nzerus-id: task\nEpic: zerus:epic|Epic\nForeign: unchanged\n---\n# Task\nSource body.\n"
        let target = "---\nzerus-id: epic\nTasks: [\"zerus:task|Task\"]\n---\n# Epic\nTarget body.\n"
        for (path, text) in [(".zerus/properties.json", schema), ("Tasks/A.md", source), ("Epics/E.md", target)] { try await io.write(path, data: Data(text.utf8), expected: nil) }
        let initial = try await io.relationDefinitionSnapshot(), plan = try initial.movePlan(source: "Tasks/A.md", destination: "Archive/A.md")
        let outside = Data("# Outside note\nKeep me.\n".utf8)
        try await io.write("Archive/A.md", data: outside, expected: nil)
        do { _ = try await io.applyRelationMaintenance(plan); XCTFail("A reviewed move must never replace a newly occupied destination") }
        catch { XCTAssertTrue(error.localizedDescription.contains("added, moved or renamed")) }
        let originalStill = try await io.read("Tasks/A.md"), targetStill = try await io.read("Epics/E.md"), schemaStill = try await io.read(".zerus/properties.json"), outsideStill = try await io.read("Archive/A.md")
        XCTAssertEqual(originalStill, Data(source.utf8)); XCTAssertEqual(targetStill, Data(target.utf8)); XCTAssertEqual(schemaStill, Data(schema.utf8)); XCTAssertEqual(outsideStill, outside)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Archive/A.md"))
        let moved = try await io.applyRelationMaintenance(plan)
        let ordinary = try XCTUnwrap(moved.notes.first { $0.path == "Archive/A.md" })
        XCTAssertEqual(try NativeRelationSnapshot.values(ordinary, name: "Epic"), ["zerus:epic|Epic"])
        XCTAssertEqual(NativeFrontmatter(ordinary.content).body, NativeFrontmatter(source).body)
        let cleared = NoteDocument(path: "Epics/E.md", content: String(decoding: try await io.read("Epics/E.md"), as: UTF8.self), modified: Date())
        XCTAssertEqual(try NativeRelationSnapshot.values(cleared, name: "Tasks"), [])
        let definitions = try await io.schemaSnapshot()
        XCTAssertEqual(try definitions.definitions(owner: "Archive").first?.type, .text)
        let next = try await io.relationDefinitionSnapshot()
        _ = try await io.applyRelationMaintenance(next.movePlan(source: ordinary.path, destination: "New type/A.md"))
        let final = try await io.schemaSnapshot()
        let newInverse = try XCTUnwrap(try final.definitions(owner: "Epics").first { $0.relationPairID == "new-pair" })
        let epic = NoteDocument(path: "Epics/E.md", content: String(decoding: try await io.read("Epics/E.md"), as: UTF8.self), modified: Date())
        XCTAssertEqual(try NativeRelationSnapshot.values(epic, name: newInverse.name), ["zerus:task|Task"])
        XCTAssertEqual(try NativeRelationSnapshot.values(epic, name: "Tasks"), [])
        let beforeManagedSchema = try await io.read(".zerus/properties.json")
        var managedSchema = try XCTUnwrap(try JSONSerialization.jsonObject(with: beforeManagedSchema) as? [String: Any])
        managedSchema["Reviews"] = [["name": "Saved", "type": "relation", "relationPairId": "saved-pair"]]
        try await io.write(".zerus/properties.json", data: JSONSerialization.data(withJSONObject: managedSchema), expected: beforeManagedSchema)
        let savedLink = "---\nzerus-link-id: saved-link\nzerus-link-url: https://example.com\nEpic: zerus:epic|Epic\n---\n# Saved link\nOriginal saved-link body.\n"
        try await io.write(".zerus/links/Saved.md", data: Data(savedLink.utf8), expected: nil)
        try await io.write("Reviews/R.md", data: Data("---\nzerus-id: review\nSaved: '.zerus/links/Saved.md'\n---\n# Review\n".utf8), expected: nil)
        let managedSnapshot = try await io.relationDefinitionSnapshot()
        let managed = try await io.applyRelationMaintenance(managedSnapshot.movePlan(source: ".zerus/links/Saved.md", destination: "New type/Saved.md"))
        let filed = try XCTUnwrap(managed.notes.first { $0.path == "New type/Saved.md" })
        XCTAssertEqual(filed.property("zerus-link-id"), "saved-link")
        XCTAssertEqual(filed.property("zerus-link-url"), "https://example.com")
        XCTAssertEqual(NativeFrontmatter(filed.content).body, NativeFrontmatter(savedLink).body)
        let review = try XCTUnwrap(managed.notes.first { $0.path == "Reviews/R.md" })
        XCTAssertEqual(try NativeRelationSnapshot.values(review, name: "Saved"), ["zerus:\(try XCTUnwrap(filed.stableID))|Saved link"])
    }

    func testLegacyRepairInfersOnlyUnambiguousFolderScopesAndChecksEveryAdoptedNote() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"metadata":{"keep":7},"Tasks":[{"name":"Product","type":"relation","relationTypeKey":"Products","relationPairId":"product-pair","relationInverseHidden":true,"futureFlag":42},{"name":"FutureProduct","type":"relation","relationTypeKey":"Products"}],"Future":[{"name":"FutureProduct","type":"relation","relationMultiple":"unknown-future-format"}],"Products":[{"name":"Tasks","type":"relation","relationTypeKey":"Tasks","relationPairId":"product-pair","relationMultiple":true,"relationHidden":true}],"Clean/Protected":[{"name":"Product","type":"text"}],"One":[{"name":"Owner","type":"relation","relationTypeKey":"Products"}],"Two":[{"name":"Owner","type":"text"}],"Metadata one":[{"name":"MetadataRelation","type":"relation","relationPairId":"metadata-pair","futureBehavior":7}],"Metadata two":[{"name":"MetadataRelation","type":"relation","relationPairId":"metadata-pair","futureBehavior":8}]}"#
        // A non-relation with the same name makes Product ambiguous everywhere,
        // so first verify that no repair is proposed while it exists.
        let good = "---\nProduct: Fleet\nForeign:\n  nested: [keep]\n---\n# Feedback\nOriginal feedback body.\n"
        let empty = "# Untouched\nBody without a Product field.\n"
        let fixtures = [(".zerus/properties.json", schema), ("Malformed/Field.md", "---\nFutureProduct: Fleet\n---\n# Malformed definition\n"), ("Metadata/Field.md", "---\nMetadataRelation: Fleet\n---\n# Unknown settings\n"), ("Clean/Good.md", good), ("Clean/Empty.md", empty), ("Clean/Protected/P.md", "---\nProduct: ordinary text\n---\n# Protected\n"), ("Products/Fleet.md", "---\nzerus-id: fleet\n---\n# Fleet\nFleet body.\n"), ("Unsafe/Unknown.md", "---\nProduct: Missing\n---\n# Unknown\n"), ("Mixed/Good.md", "---\nProduct: Fleet\n---\n# Mixed good\n"), ("Mixed/Unknown.md", "---\nProduct: Missing\n---\n# Mixed unknown\n"), ("Mixed/Child/Good.md", "---\nProduct: Fleet\n---\n# Child good\n"), ("Conflict/Owner.md", "---\nOwner: Fleet\n---\n# Owner conflict\n"), (".trash/Old/Deleted.md", "---\nProduct: Fleet\n---\n# Deleted\n")]
        for (path, text) in fixtures { try await io.write(path, data: Data(text.utf8), expected: nil) }
        let ambiguous = try await io.relationDefinitionSnapshot(), rejected = try ambiguous.repairPlan()
        XCTAssertFalse(rejected.hasChanges); XCTAssertTrue(rejected.issues.contains { $0.name == "Product" })
        if rejected.hasChanges { return } // Further checks require the ambiguous plan to be read-only.
        // Remove the explicit competing ordinary definition; child overrides
        // with unrelated names remain protected below the inferred scope.
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])
        object["Clean/Protected"] = [["name": "Other", "type": "text"]]
        let unambiguousSchema = try JSONSerialization.data(withJSONObject: object)
        try await io.write(".zerus/properties.json", data: unambiguousSchema, expected: Data(schema.utf8))
        let protectedOriginal = try XCTUnwrap(fixtures.first { $0.0 == "Clean/Protected/P.md" }?.1)
        let protectedOther = protectedOriginal.replacingOccurrences(of: "Product:", with: "Other:")
        try await io.write("Clean/Protected/P.md", data: Data(protectedOther.utf8), expected: Data(protectedOriginal.utf8))
        let snapshot = try await io.relationDefinitionSnapshot(), plan = try snapshot.repairPlan()
        XCTAssertTrue(plan.hasChanges); XCTAssertTrue(plan.issues.contains { $0.path == "Unsafe/Unknown.md" })
        XCTAssertTrue(plan.issues.contains { $0.name == "Owner" }); XCTAssertTrue(plan.issues.contains { $0.path.hasPrefix("Mixed/") })
        let originalSchema = try await io.read(".zerus/properties.json"), untouched = try await io.read("Clean/Good.md")
        XCTAssertEqual(originalSchema, unambiguousSchema); XCTAssertEqual(untouched, Data(good.utf8))
        let changedEmpty = Data("---\nProduct: Missing\n---\n# Untouched\nBody without a Product field.\n".utf8)
        try await io.write("Clean/Empty.md", data: changedEmpty, expected: Data(empty.utf8))
        do { _ = try await io.applyRelationMaintenance(plan); XCTFail("A previously empty field changed within the adopted folder scope") }
        catch { XCTAssertTrue(error.localizedDescription.contains("changed outside")) }
        let unchangedSchema = try await io.read(".zerus/properties.json"); XCTAssertEqual(unchangedSchema, unambiguousSchema)
        try await io.write("Clean/Empty.md", data: Data(empty.utf8), expected: changedEmpty)
        _ = try await io.applyRelationMaintenance(plan)
        let repaired = try await io.schemaSnapshot()
        XCTAssertEqual(try repaired.definitions(owner: "Clean").first { $0.id == "product" }?.relationPairID, "product-pair")
        XCTAssertNotNil(try repaired.definitions(owner: "Mixed/Child").first { $0.id == "product" })
        XCTAssertFalse(try repaired.definitions(owner: "Mixed").contains { $0.id == "product" })
        let saved = NoteDocument(path: "Clean/Good.md", content: String(decoding: try await io.read("Clean/Good.md"), as: UTF8.self), modified: Date())
        XCTAssertEqual(NativeFrontmatter(saved.content).body, NativeFrontmatter(good).body)
        XCTAssertEqual(try NativeRelationSnapshot.values(saved, name: "Product"), ["zerus:fleet|Fleet"])
        let protectedAfter = try await io.read("Clean/Protected/P.md")
        XCTAssertEqual(protectedAfter, Data(protectedOther.utf8))
        let epic = NoteDocument(path: "Products/Fleet.md", content: String(decoding: try await io.read("Products/Fleet.md"), as: UTF8.self), modified: Date())
        XCTAssertTrue(try NativeRelationSnapshot.values(epic, name: "Tasks").contains("zerus:\(try XCTUnwrap(saved.stableID))|Feedback"))
        for (path, text) in fixtures where path.hasPrefix("Metadata/") || path.hasPrefix("Malformed/") || path.hasPrefix("Unsafe/") || path.hasPrefix("Mixed/Unknown") || path.hasPrefix("Mixed/Good") || path.hasPrefix("Conflict/") || path.hasPrefix(".trash/") {
            let current = try await io.read(path); XCTAssertEqual(current, Data(text.utf8))
        }
    }
}
