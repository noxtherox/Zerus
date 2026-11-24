import XCTest
@testable import Zerus_Native

@MainActor final class MacSchemaMaintenanceTests: XCTestCase {
    private func fixture(_ work: (URL, MacWorkspace) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-Mac-schema-" + UUID().uuidString)
        let files = [
            ".zerus/properties.json": #"{"metadata":{"keep":7},"Projects":[{"name":"Status","type":"list","listOptions":["Alpha,beta","Gamma"],"listMultiple":true,"futureChoiceSetting":7},{"name":"Owner","type":"relation","relationTypeKey":"Contacts","relationPairId":"owners","relationMultiple":false,"relationHidden":true,"relationInverseHidden":true,"futureRelationSetting":8}],"Projects/Child":[{"name":"Status","type":"text","futureChildSetting":9}],"Contacts":[{"name":"Projects","type":"relation","relationTypeKey":"Projects","relationPairId":"owners","relationMultiple":true,"relationHidden":true}]}"#,
            "Projects/A.md": "---\nzerus-id: a\nStatus: [\"Alpha,beta\", \"Gamma\"]\nOwner: \"zerus:contact|Contact\"\nforeign: {keep: [1, 2]} # retained\n---\n# Project A\n\nOriginal project body.\n",
            "Projects/Empty.md": "# Empty\n\nUnchanged empty note.\n",
            "Projects/Child/C.md": "---\nStatus: Child override\n---\n# Child\n\nOriginal child body.\n",
            "Contacts/Contact.md": "---\nzerus-id: contact\nProjects: [\"zerus:a|Project A\"]\n---\n# Contact\n\nOriginal contact body.\n",
        ]
        for (path, text) in files { let url = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(text.utf8).write(to: url) }
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        let workspace = MacWorkspace(); await workspace.openVault(root)
        defer {
            for path in files.keys where path.hasSuffix(".md") { for file in (try? MacNoteRecoveryStore.locations(root: root, path: path)) ?? [] { try? FileManager.default.removeItem(at: file) } }
            if let drafts = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: drafts) }
            defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
            try? FileManager.default.removeItem(at: root)
        }
        try await work(root, workspace)
    }
    private func form(_ snapshot: NativeRelationDefinitionSnapshot, name: String) throws -> MacSchemaForm {
        MacSchemaForm(try XCTUnwrap(try snapshot.schema.definitions(owner: "Projects").first { $0.name == name }))
    }
    func testMacChoiceRowsSupportLiteralCommasNoOpRenameSingleChoiceAndReviewedRemoval() async throws {
        try await fixture { root, workspace in
            await workspace.openNote("Projects/A.md")
            let schemaFile = root.appendingPathComponent(".zerus/properties.json"), before = try Data(contentsOf: schemaFile)
            let child = root.appendingPathComponent("Projects/Child/C.md"), originalChild = try Data(contentsOf: child)
            let contact = root.appendingPathComponent("Contacts/Contact.md"), originalContact = try Data(contentsOf: contact)
            var snapshot = try await workspace.schemaDefinitionSnapshot(), draft = try form(snapshot, name: "Status")
            XCTAssertEqual(draft.choices.map(\.value), ["Alpha,beta", "Gamma"])
            let unchanged = try await workspace.prepareSchemaReview(snapshot, owner: "Projects", originalName: "Status", definition: draft.definition(owner: "Projects"))
            XCTAssertFalse(unchanged.plan.hasChanges)
            try await workspace.commitSchemaMaintenance(unchanged.plan)
            XCTAssertEqual(try Data(contentsOf: schemaFile), before, "An unchanged form must not normalize or rewrite the schema")
            draft.name = "Stage"
            let rename = try await workspace.prepareSchemaReview(snapshot, owner: "Projects", originalName: "Status", definition: draft.definition(owner: "Projects"))
            XCTAssertTrue(rename.noteChanges.contains { $0.path == "Projects/A.md" })
            try await workspace.commitSchemaMaintenance(rename.plan)
            let renamed = try XCTUnwrap(workspace.current)
            XCTAssertEqual(NativeFrontmatter(renamed.content).entry("Stage")?.value?.selections, ["Alpha,beta", "Gamma"])
            XCTAssertNil(NativeFrontmatter(renamed.content).entry("Status"))
            snapshot = try await workspace.schemaDefinitionSnapshot(); draft = try form(snapshot, name: "Stage"); draft.multiple = false
            let single = try await workspace.prepareSchemaReview(snapshot, owner: "Projects", originalName: "Stage", definition: draft.definition(owner: "Projects"))
            try await workspace.commitSchemaMaintenance(single.plan)
            XCTAssertEqual(workspace.current?.property("Stage"), "Alpha,beta")
            snapshot = try await workspace.schemaDefinitionSnapshot()
            let remove = try await workspace.prepareSchemaReview(snapshot, owner: "Projects", originalName: "Stage", definition: nil)
            XCTAssertTrue(remove.noteChanges.contains { $0.path == "Projects/A.md" })
            try await workspace.commitSchemaMaintenance(remove.plan)
            XCTAssertNil(NativeFrontmatter(try XCTUnwrap(workspace.current).content).entry("Stage"))
            XCTAssertEqual(workspace.body, "# Project A\n\nOriginal project body.\n")
            XCTAssertTrue(try XCTUnwrap(workspace.current).content.contains("foreign: {keep: [1, 2]} # retained"))
            XCTAssertEqual(try Data(contentsOf: child), originalChild); XCTAssertEqual(try Data(contentsOf: contact), originalContact)
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: schemaFile)) as? [String: Any])
            XCTAssertEqual((raw["metadata"] as? [String: Int])?["keep"], 7)
            XCTAssertEqual((raw["Projects"] as? [[String: Any]])?.first?["futureRelationSetting"] as? Int, 8)
        }
    }
    func testMacRelationFormPreservesHiddenPairAndUnknownSettingsThroughRenameAndRemoval() async throws {
        try await fixture { root, workspace in
            var snapshot = try await workspace.schemaDefinitionSnapshot(), draft = try form(snapshot, name: "Owner")
            XCTAssertTrue(draft.hidden); XCTAssertTrue(draft.inverseHidden)
            draft.name = "Contact"
            let review = try await workspace.prepareSchemaReview(snapshot, owner: "Projects", originalName: "Owner", definition: draft.definition(owner: "Projects"))
            try await workspace.commitSchemaMaintenance(review.plan)
            let schema = try await XCTUnwrap(workspace.io).schemaSnapshot(), definition = try XCTUnwrap(try schema.definitions(owner: "Projects").first { $0.name == "Contact" })
            XCTAssertTrue(definition.hidden); XCTAssertTrue(definition.relationInverseHidden); XCTAssertEqual(definition.relationPairID, "owners")
            let inverse = try XCTUnwrap(try schema.definitions(owner: "Contacts").first { $0.relationPairID == "owners" }); XCTAssertTrue(inverse.hidden)
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/properties.json"))) as? [String: Any])
            XCTAssertEqual((raw["Projects"] as? [[String: Any]])?.first { $0["name"] as? String == "Contact" }?["futureRelationSetting"] as? Int, 8)
            snapshot = try await workspace.schemaDefinitionSnapshot()
            let removal = try await workspace.prepareSchemaReview(snapshot, owner: "Projects", originalName: "Contact", definition: nil)
            XCTAssertEqual(Set(removal.noteChanges.map(\.path)), ["Projects/A.md", "Contacts/Contact.md"])
            try await workspace.commitSchemaMaintenance(removal.plan)
            let notes = try await XCTUnwrap(workspace.io).scan().notes
            let source = try XCTUnwrap(notes.first { $0.path == "Projects/A.md" }), target = try XCTUnwrap(notes.first { $0.path == "Contacts/Contact.md" })
            XCTAssertNil(NativeFrontmatter(source.content).entry("Contact"))
            XCTAssertEqual(try NativeRelationSnapshot.values(target, name: "Projects"), [])
            XCTAssertEqual(source.parts.body, "# Project A\n\nOriginal project body.\n"); XCTAssertEqual(target.parts.body, "# Contact\n\nOriginal contact body.\n")
        }
    }
    func testMacSchemaReviewRejectsOutsideSchemaNewValuesPrivateDraftsAndReopenedVault() async throws {
        for hazard in ["schema", "empty-value", "draft", "activation"] {
            try await fixture { root, workspace in
                let schemaURL = root.appendingPathComponent(".zerus/properties.json"), sourceURL = root.appendingPathComponent("Projects/A.md")
                var expectedSchema = try Data(contentsOf: schemaURL); let source = try Data(contentsOf: sourceURL)
                let snapshot = try await workspace.schemaDefinitionSnapshot(), review = try await workspace.prepareSchemaReview(snapshot, owner: "Projects", originalName: "Status", definition: nil)
                XCTAssertTrue(review.plan.hasChanges)
                var draft: URL?, draftBytes: Data?
                switch hazard {
                case "schema":
                    var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: expectedSchema) as? [String: Any]); raw["outside"] = true
                    expectedSchema = try JSONSerialization.data(withJSONObject: raw); try expectedSchema.write(to: schemaURL)
                case "empty-value":
                    try Data("---\nStatus: Alpha,beta\n---\n# Empty\n\nUnchanged empty note.\n".utf8).write(to: root.appendingPathComponent("Projects/Empty.md"))
                case "draft":
                    let owner = UUID().uuidString, note = NoteDocument(path: "Projects/A.md", content: String(decoding: source, as: UTF8.self), modified: .now)
                    try MacNoteRecoveryStore.checkpoint(root: root, note: note, body: "Retained writing.", windowID: owner)
                    draft = try MacNoteRecoveryStore.locations(root: root, path: note.path).first { $0.lastPathComponent.contains(owner) }; draftBytes = try draft.map { try Data(contentsOf: $0) }
                default: await workspace.openVault(root)
                }
                do { try await workspace.commitSchemaMaintenance(review.plan); XCTFail("The \(hazard) review must not apply") } catch {}
                XCTAssertEqual(try Data(contentsOf: schemaURL), expectedSchema); XCTAssertEqual(try Data(contentsOf: sourceURL), source)
                if let draft { XCTAssertEqual(try Data(contentsOf: draft), draftBytes) }
                XCTAssertFalse(workspace.schemaMaintenanceSaving)
            }
        }
    }
}
