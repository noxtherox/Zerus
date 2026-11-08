import XCTest
@testable import ZerusNative

final class NativeRelationDefinitionTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testDefinitionRenameVisibilityAndConstraintsPreserveLinksAndChildOverrides() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"metadata":{"future":true},"Unrelated":{"futureFormat":true},"Tasks":[{"name":"Epics","type":"relation","relationMultiple":true,"relationTypeKey":"Epics","relationPairId":"pair-one","custom":42}],"Tasks/Child":[{"name":"Epics","type":"relation","relationPairId":"child-pair","relationTypeKey":"Epics"}],"Epics":[{"name":"Tasks","type":"relation","relationMultiple":true,"relationPairId":"pair-one","custom":"inverse"}]}"#
        let source = "---\r\n# Foreign header\r\nzerus-id: task\r\nEpics: [\"zerus:one|One\", \"zerus:two|Two\"] # preserve comment\r\nForeign:\r\n  nested: true\r\n---\r\n# Task\r\n\r\nA **body**.\r\n"
        let child = "---\nzerus-id: child\nEpics: zerus:one|One\n---\n# Child\n"
        let one = "---\nzerus-id: one\nTasks: [\"zerus:task|Task\", \"zerus:other|Other\"]\n---\n# One\n"
        let two = "---\nzerus-id: two\nTasks: [\"zerus:task|Task\"]\n---\n# Two\n"
        for (path, text) in [(".zerus/properties.json", schema), ("Tasks/A.MD", source), ("Tasks/Child/C.md", child), ("Tasks/Other.md", "---\nzerus-id: other\n---\n# Other\n"), ("Epics/One.md", one), ("Epics/Two.md", two), ("Unrelated/X.md", "# Foreign format\n")] { try await io.write(path, data: Data(text.utf8), expected: nil) }
        let snapshot = try await io.relationDefinitionSnapshot()
        let definition = NativePropertyDefinition(name: "Initiatives", type: .relation, owner: "Tasks", relationTypeKey: "New folder", relationMultiple: false, relationPairID: "untrusted-form-value", relationInverseHidden: true)
        let plan = try snapshot.plan(owner: "Tasks", originalName: "Epics", definition: definition)
        XCTAssertEqual(plan.affectedCount, 2)
        XCTAssertTrue(plan.changedNotes.contains("Tasks/A.MD"), "The review must list changed notes with uppercase Markdown extensions")
        _ = try await io.applyRelationDefinition(plan)
        let saved = try await io.read("Tasks/A.MD"), savedChild = try await io.read("Tasks/Child/C.md")
        XCTAssertEqual(saved, Data(source.replacingOccurrences(of: "Epics:", with: "Initiatives:").utf8))
        XCTAssertEqual(savedChild, Data(child.utf8))
        let savedOne = try await io.read("Epics/One.md"), savedTwo = try await io.read("Epics/Two.md")
        XCTAssertEqual(savedOne, Data(one.utf8)); XCTAssertEqual(savedTwo, Data(two.utf8))
        let after = try await io.schemaSnapshot(), definitions = try after.definitions(owner: "Tasks"), inverse = try XCTUnwrap(try after.definitions(owner: "Epics").first)
        XCTAssertEqual(definitions[0].relationPairID, "pair-one"); XCTAssertFalse(definitions[0].relationMultiple)
        XCTAssertEqual(definitions[0].relationTypeKey, "New folder"); XCTAssertTrue(inverse.hidden)
        let schemaBytes = try await io.read(".zerus/properties.json")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: schemaBytes) as? [String: Any])
        XCTAssertEqual((object["metadata"] as? [String: Bool])?["future"], true)
        XCTAssertEqual((object["Tasks"] as? [[String: Any]])?[0]["custom"] as? Int, 42)
        XCTAssertEqual((object["Epics"] as? [[String: Any]])?[0]["custom"] as? String, "inverse")
        let reopen = try await io.relationSnapshot(notePath: "Tasks/A.MD", name: "Initiatives")
        XCTAssertEqual(try reopen.selection().paths, ["Epics/One.md", "Epics/Two.md"], "Narrowing a definition must not silently discard existing targets")
    }

    func testCreateOverrideAndDeleteReconcileBothPairsAndInheritance() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"Tasks":[{"name":"Epic","type":"relation","relationTypeKey":"Epics","relationPairId":"parent-pair"}],"Tasks/Protected":[{"name":"Epic","type":"relation","relationTypeKey":"Epics","relationPairId":"parent-pair"}],"Epics":[{"name":"Tasks","type":"relation","relationMultiple":true,"relationPairId":"parent-pair"}]}"#
        let source = "---\nzerus-id: child\nEpic: zerus:one|One\n---\n# Child\nOriginal child body.\n"
        let target = "---\nzerus-id: one\nTasks: [\"zerus:child|Child\", \"zerus:other|Other\", \"zerus:protected|Protected\"]\n---\n# One\nOriginal epic body.\n"
        let protected = "---\nzerus-id: protected\nEpic: zerus:one|One\n---\n# Protected\n"
        for (path, text) in [(".zerus/properties.json", schema), ("Tasks/Child/A.md", source), ("Tasks/Protected/P.md", protected), ("Tasks/Other.md", "---\nzerus-id: other\nEpic: zerus:one|One\n---\n# Other\n"), ("Epics/One.md", target)] { try await io.write(path, data: Data(text.utf8), expected: nil) }
        let initial = try await io.relationDefinitionSnapshot()
        let new = NativePropertyDefinition(name: "Epic", type: .relation, owner: "Tasks/Child", relationTypeKey: "Epics", relationInverseHidden: true)
        let create = try initial.plan(owner: "Tasks/Child", originalName: nil, definition: new)
        _ = try await io.applyRelationDefinition(create)
        let override = try await io.schemaSnapshot()
        let childDefinition = try XCTUnwrap(try override.definitions(owner: "Tasks/Child").first)
        XCTAssertNotEqual(childDefinition.relationPairID, "parent-pair"); XCTAssertNotNil(childDefinition.relationPairID)
        let inverse = try XCTUnwrap(try override.definitions(owner: "Epics").first { $0.relationPairID == childDefinition.relationPairID })
        XCTAssertTrue(inverse.hidden)
        var epic = NoteDocument(path: "Epics/One.md", content: String(decoding: try await io.read("Epics/One.md"), as: UTF8.self), modified: Date())
        XCTAssertEqual(try NativeRelationSnapshot.values(epic, name: "Tasks"), ["zerus:other|Other", "zerus:protected|Protected"])
        XCTAssertEqual(try NativeRelationSnapshot.values(epic, name: inverse.name), ["zerus:child|Child"])
        let removeChildSnapshot = try await io.relationDefinitionSnapshot()
        _ = try await io.applyRelationDefinition(removeChildSnapshot.plan(owner: "Tasks/Child", originalName: "Epic", definition: nil))
        epic.content = String(decoding: try await io.read("Epics/One.md"), as: UTF8.self)
        XCTAssertEqual(Set(try NativeRelationSnapshot.values(epic, name: "Tasks")), ["zerus:other|Other", "zerus:child|Child", "zerus:protected|Protected"])
        XCTAssertEqual(try NativeRelationSnapshot.values(epic, name: inverse.name), [])
        let sourceAfter = String(decoding: try await io.read("Tasks/Child/A.md"), as: UTF8.self)
        XCTAssertEqual(NativeFrontmatter(sourceAfter).body, NativeFrontmatter(source).body)
        XCTAssertEqual(try NativeRelationSnapshot.values(NoteDocument(path: "Tasks/Child/A.md", content: sourceAfter, modified: Date()), name: "Epic"), ["zerus:one|One"])
        // Removing the inherited definition clears both source values and their
        // inverse edges, while preserving unrelated content and inverse schemas.
        let removeParentSnapshot = try await io.relationDefinitionSnapshot()
        _ = try await io.applyRelationDefinition(removeParentSnapshot.plan(owner: "Tasks", originalName: "Epic", definition: nil))
        let deleted = String(decoding: try await io.read("Tasks/Child/A.md"), as: UTF8.self)
        XCTAssertNil(NativeFrontmatter(deleted).entry("Epic"))
        XCTAssertEqual(NativeFrontmatter(deleted).body, NativeFrontmatter(source).body)
        epic.content = String(decoding: try await io.read("Epics/One.md"), as: UTF8.self)
        XCTAssertEqual(try NativeRelationSnapshot.values(epic, name: "Tasks"), ["zerus:protected|Protected"])
        let protectedAfter = try await io.read("Tasks/Protected/P.md")
        XCTAssertEqual(protectedAfter, Data(protected.utf8), "Deleting a parent definition must leave child overrides and their edges intact")
        XCTAssertEqual(NativeFrontmatter(epic.content).body, NativeFrontmatter(target).body)
        let reopenedSchema = try await io.schemaSnapshot()
        XCTAssertEqual(try reopenedSchema.definitions(owner: "Tasks").count, 0)
        XCTAssertEqual(try reopenedSchema.definitions(owner: "Epics").count, 2)
    }

    func testDefinitionReviewRejectsStaleFilesAndHiddenRenameCollisionsWithoutPartialWrites() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"Tasks":[{"name":"Epic","type":"relation","relationTypeKey":"Epics","relationPairId":"pair"}],"Tasks/Child":[{"name":"Initiative","type":"text"}],"Epics":[{"name":"Tasks","type":"relation","relationMultiple":true,"relationPairId":"pair"}]}"#
        let source = "---\nzerus-id: task\nEpic: zerus:one|One\n---\n# Task\n"
        let target = "---\nzerus-id: one\nTasks: [\"zerus:task|Task\"]\n---\n# One\n"
        for (path, text) in [(".zerus/properties.json", schema), ("Tasks/Child/A.md", source), ("Epics/One.md", target)] { try await io.write(path, data: Data(text.utf8), expected: nil) }
        let snapshot = try await io.relationDefinitionSnapshot()
        XCTAssertThrowsError(try snapshot.plan(owner: "Tasks", originalName: "Epic", definition: NativePropertyDefinition(name: "Initiative", type: .relation, owner: "Tasks"))) { error in
            XCTAssertTrue(error.localizedDescription.contains("overrides Initiative"))
        }
        let renamed = NativePropertyDefinition(name: "Program", type: .relation, owner: "Tasks", relationTypeKey: "Epics")
        let plan = try snapshot.plan(owner: "Tasks", originalName: "Epic", definition: renamed)
        let outside = Data((target + "Outside edit.\n").utf8)
        try await io.write("Epics/One.md", data: outside, expected: Data(target.utf8))
        do { _ = try await io.applyRelationDefinition(plan); XCTFail("A reviewed inverse changed before save") }
        catch { XCTAssertTrue(error.localizedDescription.contains("changed outside")) }
        let unchangedSource = try await io.read("Tasks/Child/A.md"), unchangedSchema = try await io.read(".zerus/properties.json"), unchangedOutside = try await io.read("Epics/One.md")
        XCTAssertEqual(unchangedSource, Data(source.utf8)); XCTAssertEqual(unchangedSchema, Data(schema.utf8)); XCTAssertEqual(unchangedOutside, outside)
        try await io.write("Epics/One.md", data: Data(target.utf8), expected: outside)
        try await io.write(".zerus/properties.json", data: Data((schema + "\n").utf8), expected: Data(schema.utf8))
        do { _ = try await io.applyRelationDefinition(plan); XCTFail("A reviewed schema changed before save") }
        catch { XCTAssertTrue(error.localizedDescription.contains("properties.json changed outside")) }
        let stillSource = try await io.read("Tasks/Child/A.md")
        XCTAssertEqual(stillSource, Data(source.utf8))
    }
    func testConvertingRelationToOrdinaryPropertyPreservesValuesAndOverridesRetiresOnlyAffectedInverseLinksAndRejectsStaleReview() async throws {
        let io = VaultFiles(root: root!)
        let schema = #"{"metadata":{"future":true},"Work":[{"name":"Related","type":"relation","relationTypeKey":"Targets","relationMultiple":true,"relationPairId":"pair","relationHidden":true,"custom":42}],"Work/Child":[{"name":"Related","type":"relation","relationTypeKey":"Targets","relationPairId":"pair"}],"Targets":[{"name":"Work","type":"relation","relationMultiple":true,"relationPairId":"pair","custom":"inverse"}]}"#
        let source = "---\r\n# Foreign header\r\nzerus-id: work\r\nRelated: [\"zerus:target|Target\", \"Missing note\"] # keep this comment\r\nForeign:\r\n  nested: true\r\n---\r\n# Work\r\n\r\nOriginal **writing**.\r\n"
        let child = "---\nzerus-id: child\nRelated: zerus:target|Target\n---\n# Child\n"
        let target = "---\nzerus-id: target\nWork: [\"zerus:work|Work\", \"zerus:child|Child\"]\n---\n# Target\nUnchanged target writing.\n"
        for (path, text) in [(".zerus/properties.json", schema), ("Work/A.MD", source), ("Work/Child/C.md", child), ("Targets/T.md", target)] {
            try await io.write(path, data: Data(text.utf8), expected: nil)
        }
        let before = try await io.relationDefinitionSnapshot()
        let converted = NativePropertyDefinition(name: "References", type: .text, owner: "Work")
        let plan = try before.plan(owner: "Work", originalName: "Related", definition: converted)
        XCTAssertEqual(Set(plan.changedNotes), ["Work/A.MD", "Targets/T.md"])
        XCTAssertEqual(plan.affectedCount, 1)
        let untouchedBeforeConfirmation = try await io.read("Work/A.MD")
        XCTAssertEqual(untouchedBeforeConfirmation, Data(source.utf8), "Preparing and cancelling a review must not write files")
        let outside = target + "Outside edit.\n"
        try await io.write("Targets/T.md", data: Data(outside.utf8), expected: Data(target.utf8))
        do { _ = try await io.applyRelationDefinition(plan); XCTFail("A changed inverse must reject the complete reviewed conversion") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        let refusedSource = try await io.read("Work/A.MD"), refusedSchema = try await io.read(".zerus/properties.json")
        XCTAssertEqual(refusedSource, Data(source.utf8)); XCTAssertEqual(refusedSchema, Data(schema.utf8))
        let current = try await io.relationDefinitionSnapshot()
        _ = try await io.applyRelationDefinition(current.plan(owner: "Work", originalName: "Related", definition: converted))
        let sourceBytes = try await io.read("Work/A.MD"), childBytes = try await io.read("Work/Child/C.md"), targetBytes = try await io.read("Targets/T.md")
        XCTAssertEqual(sourceBytes, Data(source.replacingOccurrences(of: "Related:", with: "References:").utf8))
        XCTAssertEqual(childBytes, Data(child.utf8))
        let savedTarget = NoteDocument(path: "Targets/T.md", content: String(decoding: targetBytes, as: UTF8.self), modified: .now)
        XCTAssertEqual(try NativeRelationSnapshot.values(savedTarget, name: "Work"), ["zerus:child|Child"])
        XCTAssertEqual(NativeFrontmatter(savedTarget.content).body, NativeFrontmatter(outside).body)
        let fresh = try await io.schemaSnapshot(), definitions = try fresh.definitions(owner: "Work")
        XCTAssertEqual(definitions.first?.type, .text); XCTAssertEqual(definitions.first?.name, "References")
        let schemaData = try await io.read(".zerus/properties.json")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: schemaData) as? [String: Any])
        let raw = try XCTUnwrap((object["Work"] as? [[String: Any]])?.first)
        XCTAssertEqual(raw["custom"] as? Int, 42)
        XCTAssertFalse(raw.keys.contains(where: { $0.hasPrefix("relation") }))
        XCTAssertEqual((object["metadata"] as? [String: Bool])?["future"], true)
        XCTAssertEqual((object["Targets"] as? [[String: Any]])?.first?["custom"] as? String, "inverse")
        XCTAssertEqual(try fresh.definitions(owner: "Work/Child").first?.type, .relation)
        XCTAssertEqual(try fresh.definitions(owner: "Targets").first?.type, .relation)
        let ordinarySnapshot = try await io.relationDefinitionSnapshot()
        let restored = NativePropertyDefinition(name: "References", type: .relation, owner: "Work", relationTypeKey: "Targets", relationMultiple: true, relationPairID: "pair")
        _ = try await io.applyRelationDefinition(ordinarySnapshot.plan(owner: "Work", originalName: "References", definition: restored))
        let relationAgain = try await io.relationSnapshot(notePath: "Work/A.MD", name: "References")
        XCTAssertEqual(try relationAgain.selection().paths, ["Targets/T.md"])
        XCTAssertEqual(try relationAgain.selection().unresolved, ["Missing note"])
        let newSchema = try await io.schemaSnapshot(), newDefinition = try XCTUnwrap(try newSchema.definitions(owner: "Work").first)
        XCTAssertNotNil(newDefinition.relationPairID); XCTAssertNotEqual(newDefinition.relationPairID, "pair")
        let inverse = try XCTUnwrap(try newSchema.definitions(owner: "Targets").first { $0.relationPairID == newDefinition.relationPairID })
        let restoredTargetBytes = try await io.read("Targets/T.md")
        let restoredTarget = NoteDocument(path: "Targets/T.md", content: String(decoding: restoredTargetBytes, as: UTF8.self), modified: .now)
        XCTAssertEqual(try NativeRelationSnapshot.values(restoredTarget, name: inverse.name), ["zerus:work|Work"])
        XCTAssertEqual(try NativeRelationSnapshot.values(restoredTarget, name: "Work"), ["zerus:child|Child"])
        let relationSnapshot = try await io.relationDefinitionSnapshot()
        let list = NativePropertyDefinition(name: "References", type: .list, owner: "Work", options: ["zerus:target|Target", "Missing note"], multiple: false)
        _ = try await io.applyRelationDefinition(relationSnapshot.plan(owner: "Work", originalName: "References", definition: list))
        let singleBytes = try await io.read("Work/A.MD"), single = String(decoding: singleBytes, as: UTF8.self)
        XCTAssertEqual(NativeFrontmatter(single).entry("References")?.value, .text("zerus:target|Target"))
        XCTAssertTrue(single.contains("# keep this comment\r\n"))
        XCTAssertEqual(NativeFrontmatter(single).body, NativeFrontmatter(source).body)
        let listSchema = try await io.schemaSnapshot()
        XCTAssertEqual(try listSchema.definitions(owner: "Work").first?.options, list.options)
        XCTAssertEqual(try listSchema.definitions(owner: "Work").first?.multiple, false)
        let listSnapshot = try await io.relationDefinitionSnapshot()
        _ = try await io.applyRelationDefinition(listSnapshot.plan(owner: "Work", originalName: "References", definition: restored))
        let finalSchemaBytes = try await io.read(".zerus/properties.json")
        let finalObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: finalSchemaBytes) as? [String: Any])
        let finalRaw = try XCTUnwrap((finalObject["Work"] as? [[String: Any]])?.first)
        XCTAssertNil(finalRaw["listOptions"]); XCTAssertNil(finalRaw["listMultiple"])
        XCTAssertEqual(finalRaw["custom"] as? Int, 42)
        let finalChild = try await io.read("Work/Child/C.md")
        XCTAssertEqual(finalChild, Data(child.utf8))
    }

}
