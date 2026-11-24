import XCTest
import Combine
@testable import Zerus_Native

@MainActor final class MacAgentWorkspaceTests: XCTestCase {
    func testManySmallMetadataFieldsStayExactBeyondTheManifestLimit() async throws {
        try await withVault { root, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "wide-metadata", externalFiles: store.external.store)
            let record = try await client.start(objective: "Preserve a wide saved manifest", mode: .ask, scope: .init(paths: ["Work/A.md"]), chatID: "wide-metadata")
            let io = try XCTUnwrap(store.io)
            var object = try XCTUnwrap(NativeJSON.object(with: record.bytes) as? [String: Any]), expected: [String: String] = [:]
            for index in 0..<50_000 {
                let key = "future-\(index)", value = "Kept \(index) " + String(repeating: "x", count: 160)
                object[key] = value; expected[key] = value
            }
            let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            XCTAssertGreaterThan(bytes.count, 8_000_000)
            let plan: NativeAgentStoragePlan
            do { plan = try await io.agentJournalChanges(bytes, previous: record.bytes, id: record.id) }
            catch { XCTFail("Many individually small fields must not block saving: \(String(reflecting: error))"); return }
            try await io.applyTransaction(plan.changes)
            XCTAssertLessThan(plan.record.bytes.count, 8_000_000)
            let saved = try await io.agentDecode(Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(record.id))), id: record.id)
            let expanded = try await io.agentEncode(saved.run, previous: saved.bytes)
            let actual = try XCTUnwrap(NativeJSON.object(with: expanded) as? [String: Any])
            let mismatches = expected.keys.filter { actual[$0] as? String != expected[$0] }
            XCTAssertTrue(mismatches.isEmpty, "Changed fields: " + mismatches.sorted().prefix(8).joined(separator: ", "))
            XCTAssertEqual(actual.keys.filter { $0.hasPrefix("future-") }.count, expected.count)
            XCTAssertEqual(saved.run.objective, record.run.objective); XCTAssertEqual(saved.run.readIDs, record.run.readIDs)
            XCTAssertTrue(saved.run.writeIDs.isEmpty)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(store.notes.first { $0.path == "Work/A.md" }!.content.utf8))
        }
    }

    func testAgentBodyEditAndUndoKeepBomBytesAndHistorySnapshots() async throws {
        let source = "\u{feff}---\r\nzerus-id: alpha\r\nForeign: 'keep: this' # comment\r\n---\r\n# Alpha\r\n\r\nOriginal.\r\n"
        try await withVault(source: source) { root, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "bom-agent", externalFiles: store.external.store)
            var record = try await client.start(objective: "Append safely", mode: .review, scope: .init(paths: ["Work/A.md"]), chatID: "bom-agent")
            record = try await tool(client, record, "note_get", ["selector": "alpha"])
            XCTAssertEqual(try result(record)["ok"] as? Bool, true, record.run.messages.last?.content ?? "")
            guard let revision = try result(record)["revision"] as? String else { return }
            record = try await tool(client, record, "note_append", ["selector": "alpha", "revision": revision, "text": "Later writing."])
            let pending = try XCTUnwrap(record.run.pending.first)
            record = try await client.apply(client.review(record, ids: [pending.id]))
            let io = try XCTUnwrap(store.io), saved = try await io.read("Work/A.md")
            XCTAssertTrue(saved.starts(with: Data("\u{feff}---\r\nzerus-id: alpha\r\nForeign: 'keep: this' # comment\r\n---\r\n".utf8)))
            let history = try await io.historySnapshot(notePath: "Work/A.md")
            XCTAssertEqual(Data(history.note.content.utf8), saved)
            XCTAssertTrue(history.versions.contains { $0.content == source }, "History must retain the exact original BOM/YAML text")
            XCTAssertTrue(history.versions.contains { $0.content.map { Data($0.utf8) } == saved }, "The new version must retain its encoding prefix")
            record = try await client.apply(client.undoReview(record, receiptID: XCTUnwrap(record.run.receipts.last).id))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.utf8))
        }
    }

    func testOrganizationUndoMergesTaskLinksAndRetainsUnrelatedSharedSettings() async throws {
        struct TaskTitles: Decodable { struct Row: Decodable { let title: String? }; let tasks: [Row] }
        for variant in ["independent", "link-edit"] {
            try await withVault { root, store in
                try FileManager.default.createDirectory(at: root.appendingPathComponent(".zerus"), withIntermediateDirectories: true)
                let taskPath = root.appendingPathComponent(".zerus/tasks.json")
                try Data(#"{"tasks":[{"id":"source-task","title":"\ufeffKeep task","linkedNoteIds":["Work/A.md"],"completed":false},{"id":"other-task","linkedNoteIds":[],"title":"Original"}],"future":"keep"}"#.utf8).write(to: taskPath)
                let client = try MacAgentWorkspace(workspace: store, owner: "organization-merge", externalFiles: store.external.store)
                var record = try await client.start(objective: "File Alpha", mode: .review, scope: .init(paths: ["Work/A.md"], organizationFolder: "Filed", allowOrganizationMoves: true), chatID: variant)
                record = try await tool(client, record, "note_get", ["selector": "alpha"])
                let revision = try XCTUnwrap(result(record)["revision"] as? String)
                record = try await tool(client, record, "note_organize", ["selector": "alpha", "revision": revision, "typePath": ["Filed"]])
                let id = try XCTUnwrap(record.run.pending.first).id
                record = try await client.apply(client.review(record, ids: [id]))
                XCTAssertEqual(try JSONDecoder().decode(TaskTitles.self, from: Data(contentsOf: taskPath)).tasks[0].title, "\u{feff}Keep task")
                let props = Data(#"{"Other":[{"name":"Later field","type":"text"}]}"#.utf8), links = Data(#"{"future":"later independent link settings"}"#.utf8)
                try props.write(to: root.appendingPathComponent(".zerus/properties.json")); try links.write(to: root.appendingPathComponent(".zerus/links.json"))
                var current = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: taskPath)) as? [String: Any]), rows = try XCTUnwrap(current["tasks"] as? [[String: Any]])
                rows[0]["title"] = "\u{feff}Keep task"
                rows[0]["completed"] = true; rows[1]["title"] = "Later writing"
                rows.append(["id": "new-task", "linkedNoteIds": ["Filed/A.md"], "title": "Keep this new task"])
                if variant == "link-edit" { rows[0]["linkedNoteIds"] = ["a-different-note"] }
                current["tasks"] = rows; current["newTopLevel"] = 42
                let currentBytes = try JSONSerialization.data(withJSONObject: current, options: [.sortedKeys]); try currentBytes.write(to: taskPath)
                let receipt = try XCTUnwrap(record.run.receipts.last)
                if variant == "link-edit" {
                    do { _ = try await client.undoReview(record, receiptID: receipt.id); XCTFail("Undo must not replace an independently edited supporting-note link") }
                    catch { XCTAssertTrue(error.localizedDescription.contains("supporting-note links changed"), error.localizedDescription) }
                    XCTAssertEqual(try Data(contentsOf: taskPath), currentBytes)
                } else {
                    record = try await client.apply(client.undoReview(record, receiptID: receipt.id))
                    let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: taskPath)) as? [String: Any]), tasks = try XCTUnwrap(restored["tasks"] as? [[String: Any]])
                    XCTAssertEqual(try JSONDecoder().decode(TaskTitles.self, from: Data(contentsOf: taskPath)).tasks[0].title, "\u{feff}Keep task")
                    XCTAssertEqual(tasks[0]["completed"] as? Bool, true); XCTAssertEqual(tasks[0]["linkedNoteIds"] as? [String], ["Work/A.md"])
                    XCTAssertEqual(tasks[1]["title"] as? String, "Later writing"); XCTAssertEqual(tasks[2]["linkedNoteIds"] as? [String], ["alpha"])
                    XCTAssertEqual(restored["newTopLevel"] as? Int, 42)
                    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/properties.json")), props); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/links.json")), links)
                    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/A.md").path))
                }
            }
        }
    }

    func testOrganizationJournalRejectsHiddenFileChangesAndDuplicateSnapshotPaths() async throws {
        try await withVault { _, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "organization-parser", externalFiles: store.external.store)
            var record = try await client.start(objective: "Pin Alpha", mode: .review, scope: .init(paths: ["Work/A.md"]), chatID: "organization-parser")
            record = try await tool(client, record, "note_get", ["selector": "alpha"])
            let source = try XCTUnwrap(record.run.messages.last).content
            let revision = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any])?["revision"] as? String)
            record = try await tool(client, record, "note_organize", ["selector": "alpha", "revision": revision, "pinned": true])
            let original = try XCTUnwrap(JSONSerialization.jsonObject(with: record.bytes) as? [String: Any])
            XCTAssertEqual(original["version"] as? Int, 2, "Older version-1 clients must refuse organization receipts")
            var oldFormat = original; oldFormat["version"] = 1
            XCTAssertThrowsError(try NativeAgentJournal.decode(JSONSerialization.data(withJSONObject: oldFormat), id: record.id)) { error in
                XCTAssertTrue(error.localizedDescription.contains("require format 2"), error.localizedDescription)
            }
            for variant in ["hidden-file", "duplicate-path"] {
                var object = original, proposals = try XCTUnwrap(original["proposals"] as? [[String: Any]])
                if variant == "hidden-file" {
                    var organization = try XCTUnwrap(proposals[0]["organization"] as? [String: Any]), changes = try XCTUnwrap(organization["changes"] as? [[String: Any]])
                    changes.append(["path": "Outside/Hidden.md", "after": Data("Injected".utf8).base64EncodedString()])
                    organization["changes"] = changes; proposals[0]["organization"] = organization
                } else {
                    let note = NativeAgentNote(NoteDocument(path: "Work/A.md", content: "---\nzerus-id: different\n---\n# Other\n", modified: .distantPast))
                    let companion = NativeAgentCompanion(before: note, after: note)
                    proposals[0]["companions"] = [try JSONSerialization.jsonObject(with: JSONEncoder().encode(companion))]
                }
                object["proposals"] = proposals
                do { _ = try NativeAgentJournal.decode(JSONSerialization.data(withJSONObject: object), id: record.id); XCTFail("Unsupported organization snapshots must not reach review") }
                catch { XCTAssertTrue(error.localizedDescription.contains(variant == "hidden-file" ? "displayed note snapshots" : "duplicate note paths"), error.localizedDescription) }
            }
        }
    }

    func testOrganizationLegacyIdentityReconciliationAndUndoProtectNewLinks() async throws {
        let source = "# Legacy\n\nOriginal legacy writing.\n"
        try await withVault(source: source) { root, store in
            let peer = "---\nzerus-id: beta\n---\n# Beta\n\n[[Legacy]]\n"
            try Data(peer.utf8).write(to: root.appendingPathComponent("Work/B.md"))
            let client = try MacAgentWorkspace(workspace: store, owner: "legacy-organization", externalFiles: store.external.store)
            var record = try await client.start(objective: "Rename Legacy", mode: .review, scope: .init(paths: ["Work/A.md", "Work/B.md"], currentReadPath: "Work/A.md"), chatID: "legacy-title")
            record = try await tool(client, record, "note_get", ["selector": "Work/A.md"]); record = try await tool(client, record, "note_get", ["selector": "beta"])
            record = try await tool(client, record, "note_organize", ["selector": "Work/A.md", "revision": NativeAgentNote.hash(source), "title": "Renamed"])
            XCTAssertEqual(try result(record)["ok"] as? Bool, true, record.run.messages.last?.content ?? "")
            let proposal = try XCTUnwrap(record.run.pending.first)
            record = try await client.apply(client.review(record, ids: [proposal.id]))
            let assigned = try XCTUnwrap(proposal.after.document.stableID), appliedBytes = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
            XCTAssertNil(store.noteDiskChange); XCTAssertEqual(record.run.currentTargetID, assigned)
            record = try await tool(client, record, "note_get", [:]); XCTAssertEqual(try result(record)["id"] as? String, assigned)
            let newer = root.appendingPathComponent("Later.md")
            for reference in ["zerus:" + assigned, "Renamed"] {
                try Data(("# Later\n\n[[" + reference + "]]\n").utf8).write(to: newer)
                do { _ = try await client.undoReview(record, receiptID: XCTUnwrap(record.run.receipts.last).id); XCTFail("Undo must not break new identity/title links") }
                catch { XCTAssertTrue(error.localizedDescription.contains("links") || error.localizedDescription.contains("Links"), error.localizedDescription) }
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), appliedBytes)
            }
            try FileManager.default.removeItem(at: newer)
            record = try await client.apply(client.undoReview(record, receiptID: XCTUnwrap(record.run.receipts.last).id))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.utf8)); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/B.md")), Data(peer.utf8))
            XCTAssertNil(store.noteDiskChange); XCTAssertNotNil(record.run.receipts.last?.undoneAt)
        }
    }

    func testOrganizationRefusesUnreadOrOutsideLinkRepairsAndStaleApproval() async throws {
        for variant in ["outside", "unread", "before-review", "after-review"] {
            try await withVault { root, store in
                let peer = "---\nzerus-id: beta\n---\n# Private linked title\n\n[[Alpha]]\n"
                try Data(peer.utf8).write(to: root.appendingPathComponent("Work/B.md"))
                let client = try MacAgentWorkspace(workspace: store, owner: "organization-refusal", externalFiles: store.external.store)
                let paths: Set<String> = variant == "outside" ? ["Work/A.md"] : ["Work/A.md", "Work/B.md"]
                var record = try await client.start(objective: "File Alpha", mode: .review, scope: .init(paths: paths, organizationFolder: "Filed", allowOrganizationMoves: true), chatID: variant)
                record = try await tool(client, record, "note_get", ["selector": "alpha"])
                if !["outside", "unread"].contains(variant) { record = try await tool(client, record, "note_get", ["selector": "beta"]) }
                let source = try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8)
                record = try await tool(client, record, "note_organize", ["selector": "alpha", "revision": NativeAgentNote.hash(source), "typePath": ["Filed"]])
                if ["outside", "unread"].contains(variant) {
                    XCTAssertEqual(try result(record)["ok"] as? Bool, false); XCTAssertTrue(record.run.pending.isEmpty)
                    XCTAssertTrue(record.run.messages.last?.content.contains("current revision") == true)
                    XCTAssertFalse(record.run.messages.last?.content.contains("Private linked title") == true)
                } else {
                    let id = try XCTUnwrap(record.run.pending.first).id
                    let review = variant == "after-review" ? try await client.review(record, ids: [id]) : nil
                    let edited = Data((peer + "\nNewer writing must survive.\n").utf8); try edited.write(to: root.appendingPathComponent("Work/B.md"))
                    do {
                        if let review { _ = try await client.apply(review) } else { _ = try await client.review(record, ids: [id]) }
                        XCTFail("A stale link repair must be refused")
                    } catch { XCTAssertTrue(error.localizedDescription.contains(variant == "before-review" ? "current revision" : "changed"), error.localizedDescription) }
                    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/B.md")), edited)
                }
                XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8), source)
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Filed/A.md").path))
            }
        }
    }

    func testOrganizationReviewFilesLinksTasksAndAttachmentThenUndoRestoresExactBytes() async throws {
        try await withVault { root, store in
            let source = "---\nzerus-id: alpha\nforeign: keep\n---\n# Alpha\n\n![Picture](assets/pixel.png)\n"
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".zerus"), withIntermediateDirectories: true)
            let peer = "---\nzerus-id: beta\n---\n# Beta\n\n[[Alpha]]\n"
            let tasks = Data(#"{"tasks":[{"id":"support","linkedNoteIds":["Work/A.md"],"foreign":17}],"future":{"keep":true}}"#.utf8)
            try Data(source.utf8).write(to: root.appendingPathComponent("Work/A.md")); try Data(peer.utf8).write(to: root.appendingPathComponent("Work/B.md"))
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Work/assets"), withIntermediateDirectories: true)
            let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jw1sAAAAASUVORK5CYII=")!
            try image.write(to: root.appendingPathComponent("Work/assets/pixel.png"))
            try tasks.write(to: root.appendingPathComponent(".zerus/tasks.json"))
            let date = Date(timeIntervalSince1970: 1_600_000_000)
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: root.appendingPathComponent("Work/A.md").path)
            await store.refresh()
            let client = try MacAgentWorkspace(workspace: store, owner: "organization-owner", externalFiles: store.external.store)
            var record = try await client.start(objective: "File and retitle Alpha", mode: .edit, scope: .init(paths: ["Work/A.md", "Work/B.md"], currentReadPath: "Work/A.md", organizationFolder: "Filed", allowOrganizationMoves: true), chatID: "organization")
            record = try await tool(client, record, "note_get", ["selector": "alpha"])
            record = try await tool(client, record, "note_get", ["selector": "beta"])
            record = try await tool(client, record, "note_organize", ["selector": "alpha", "revision": NativeAgentNote.hash(source), "title": "Renamed", "typePath": ["Filed", "Sub"], "pinned": true, "archived": true])
            XCTAssertEqual(try result(record)["ok"] as? Bool, true, record.run.messages.last?.content ?? "")
            let proposal = try XCTUnwrap(record.run.pending.first)
            XCTAssertEqual(proposal.afters.count, 2)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.utf8))
            do { _ = try await client.review(record, ids: [proposal.id], automatic: true); XCTFail("Linked-note edits must require review even in Edit mode") }
            catch { XCTAssertTrue(error.localizedDescription.contains("explicit native review"), error.localizedDescription) }
            do { _ = try await VaultFiles(root: root).agentReview(record, owner: "organization-owner", ids: [proposal.id]); XCTFail("Shared-only clients must not apply a partial organization snapshot") }
            catch { XCTAssertTrue(error.localizedDescription.contains("native Mac app"), error.localizedDescription) }
            let review = try await client.review(record, ids: [proposal.id])
            XCTAssertTrue(review.reviewedFiles.contains { $0.path == ".zerus/tasks.json" })
            record = try await client.apply(review)
            let movedPath = "Filed/Sub/A.md", moved = NoteDocument(path: movedPath, content: try String(contentsOf: root.appendingPathComponent(movedPath), encoding: .utf8), modified: .distantPast)
            XCTAssertEqual(moved.title, "Renamed"); XCTAssertEqual(moved.stableID, "alpha"); XCTAssertTrue(moved.pinned); XCTAssertTrue(moved.archived)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/A.md").path))
            XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("Work/B.md"), encoding: .utf8).contains("zerus:alpha"))
            XCTAssertEqual(store.selection, movedPath)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(movedPath).path)[.creationDate] as? Date, date)
            let attachment = try XCTUnwrap(MarkdownMoveLinks.links(in: moved.parts.body).first { $0.value.hasSuffix("pixel.png") })
            XCTAssertEqual(try VaultFiles.resolveResource(attachment.value, notePath: movedPath, root: root).standardizedFileURL, root.appendingPathComponent("Work/assets/pixel.png").standardizedFileURL)
            let taskObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))) as? [String: Any])
            XCTAssertEqual((taskObject["tasks"] as? [[String: Any]])?.first?["linkedNoteIds"] as? [String], ["alpha"])
            XCTAssertEqual((taskObject["future"] as? [String: Bool])?["keep"], true)
            let undo = try await client.undoReview(record, receiptID: XCTUnwrap(record.run.receipts.last).id)
            record = try await client.apply(undo)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.utf8)); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/B.md")), Data(peer.utf8))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), tasks)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/assets/pixel.png")), image)
            XCTAssertEqual(store.selection, "Work/A.md"); XCTAssertNotNil(record.run.receipts.last?.undoneAt)
        }
    }

    func testOrganizationTrashAndUnarchiveRespectModesAndDestinationPermission() async throws {
        for action in ["ask", "destination", "trash", "unarchive"] {
            try await withVault { root, store in
                let source = action == "unarchive" ? "---\nzerus-id: alpha\nzerus-archived: true\n---\n# Alpha\n\nOriginal.\n" : "---\nzerus-id: alpha\n---\n# Alpha\n\nOriginal.\n"
                try Data(source.utf8).write(to: root.appendingPathComponent("Work/A.md")); await store.refresh()
                let client = try MacAgentWorkspace(workspace: store, owner: "organization-" + action, externalFiles: store.external.store)
                if action == "unarchive" {
                    let portable = try await VaultFiles(root: root).agentStart(objective: "Read archived", mode: .review, scope: .init(paths: ["Work/A.md"]), chatID: "portable-default", owner: "portable-default")
                    XCTAssertTrue(portable.run.writeIDs.isEmpty, "The shared engine's default must preserve the iOS archived-note write boundary")
                }
                var record = try await client.start(objective: "Organize", mode: action == "ask" ? .ask : .review, scope: .init(paths: ["Work/A.md"]), chatID: action)
                record = try await tool(client, record, "note_get", ["selector": "alpha"])
                if action == "unarchive" {
                    record = try await tool(client, record, "note_append", ["selector": "alpha", "revision": NativeAgentNote.hash(source), "text": "Must not write archived notes"])
                    XCTAssertTrue(record.run.writeIDs.contains("alpha"))
                    XCTAssertEqual(try result(record)["ok"] as? Bool, false)
                    XCTAssertTrue((try result(record)["error"] as? String)?.contains("archived") == true)
                }
                var args: [String: Any] = ["selector": "alpha", "revision": NativeAgentNote.hash(source)]
                if action == "destination" { args["typePath"] = ["Elsewhere"] }
                else if action == "trash" { args["trash"] = true }
                else if action == "unarchive" { args["archived"] = false }
                else { args["pinned"] = true }
                record = try await tool(client, record, "note_organize", args)
                if ["ask", "destination"].contains(action) {
                    XCTAssertEqual(try result(record)["ok"] as? Bool, false)
                    XCTAssertTrue(record.run.pending.isEmpty)
                    XCTAssertTrue(record.run.messages.last?.content.contains(action == "ask" ? "writable context" : "explicit organization permission") == true)
                } else {
                    XCTAssertEqual(try result(record)["ok"] as? Bool, true, record.run.messages.last?.content ?? "")
                    let proposal = try XCTUnwrap(record.run.pending.first)
                    record = try await client.apply(client.review(record, ids: [proposal.id]))
                    if action == "trash" {
                        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".trash/Work/A.md")), Data(source.utf8))
                        XCTAssertNil(store.noteDiskChange, "An owned Trash move must not retain a false outside-deletion draft")
                        XCTAssertNil(store.selection); XCTAssertFalse(store.tabs.contains(.note(".trash/Work/A.md")))
                        record = try await tool(client, record, "note_get", ["selector": "alpha"]); XCTAssertEqual(try result(record)["ok"] as? Bool, false)
                    } else { XCTAssertFalse(NoteDocument(path: "Work/A.md", content: try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8), modified: .distantPast).archived) }
                    record = try await client.apply(client.undoReview(record, receiptID: XCTUnwrap(record.run.receipts.last).id))
                }
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.utf8))
            }
        }
    }

    func testWorkerTokenAllocationRetainsTheParentsFullInputAllowance() async throws {
        try await withVault { _, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "analysis-tokens", externalFiles: store.external.store)
            let saved = try await client.preferences(); var preferences = saved.value; preferences.workers = true
            _ = try await client.savePreferences(preferences, expected: saved)
            let snapshot = try await client.limits(); var limits = snapshot.limits; limits.maxInputTokens = 16_000; limits.maxOutputTokens = 1024; limits.maxTotalTokens = 60_000
            _ = try await client.saveLimits(limits, expected: snapshot)
            var record = try await client.start(objective: "Check", mode: .ask, scope: .init(paths: ["Work/A.md"]), chatID: "worker-token-quota")
            let analyze = NativeAgentCall(id: "analysis", name: "analyze_notes", arguments: #"{"question":"Check","selectors":["alpha"]}"#)
            record = try await client.response(record, content: "", calls: [analyze], input: 1, output: 1, seconds: 0)
            record = try await client.beginAnalysis(record, call: analyze)
            for step in 0..<2 {
                record = try await client.reserveAnalysis(record, index: 0, input: 7000, output: 1000)
                let call = NativeAgentCall(id: "read-\(step)", name: "note_list", arguments: "{}")
                let reply = try MacAgentCompletion(json: String(decoding: JSONSerialization.data(withJSONObject: ["content": "", "toolCalls": JSONSerialization.jsonObject(with: JSONEncoder().encode([call]))]), as: UTF8.self))
                record = try await client.analysisReply(record, index: 0, reply: reply, source: nil, refusal: nil, input: 7000, output: 1000, seconds: 0)
                record = try await client.analysisRead(record, index: 0, call: call)
            }
            let bytes = record.bytes
            do { _ = try await client.reserveAnalysis(record, index: 0, input: 7000, output: 1000); XCTFail("Workers must not spend the parent's synthesis allowance") }
            catch { XCTAssertTrue(error.localizedDescription.contains("saved parent and worker limits"), error.localizedDescription) }
            let records = try await client.records()
            XCTAssertEqual(records.records.first(where: { $0.id == record.id })?.bytes, bytes)
        }
    }

    func testAnalysisRetiresProgressDeclinedByALegacyClientBeforeStartingAnotherCall() async throws {
        try await withVault { root, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "analysis-legacy", externalFiles: store.external.store)
            let saved = try await client.preferences(); var value = saved.value; value.workers = true
            _ = try await client.savePreferences(value, expected: saved)
            var record = try await client.start(objective: "Inspect", mode: .ask, scope: .init(paths: ["Work/A.md"]), chatID: "legacy-analysis")
            let oldCall = NativeAgentCall(id: "old-analysis", name: "analyze_notes", arguments: #"{"question":"Check","selectors":["alpha"]}"#)
            record = try await client.response(record, content: "", calls: [oldCall], input: 1, output: 1, seconds: 0)
            record = try await client.beginAnalysis(record, call: oldCall)
            let oldIDs = try XCTUnwrap(MacAgentAnalysisState.read(record)).children.map(\.id)
            // Shared-only clients decline this unknown tool while retaining its metadata.
            record = try await VaultFiles(root: root).agentTool(record, owner: "analysis-legacy", call: oldCall)
            let next = NativeAgentCall(id: "new-analysis", name: "analyze_notes", arguments: oldCall.arguments)
            record = try await client.response(record, content: "", calls: [next], input: 1, output: 1, seconds: 0)
            XCTAssertTrue(try MacAgentAnalysisState.continuationIDs(record, includingFinished: false).isEmpty)
            record = try await client.beginAnalysis(record, call: next)
            let state = try XCTUnwrap(MacAgentAnalysisState.read(record))
            XCTAssertEqual(state.callID, next.id); XCTAssertTrue(Set(oldIDs).isDisjoint(with: state.children.map(\.id)))
            let archived = try MacAgentAnalysisState.continuationIDs(record, includingFinished: true)
            XCTAssertTrue(Set(oldIDs).isSubset(of: archived))
        }
    }

    func testRunPermissionChoicesEnforceFolderReadsAndExplicitCreation() async throws {
        try await withVault { root, store in
            for (path, id) in [("Work/Child/B.md", "beta"), ("Other/C.md", "outside"), ("Inbox note.md", "inbox")] {
                let file = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("---\nzerus-id: \(id)\n---\n# \(id)\n".utf8).write(to: file)
            }
            let client = try MacAgentWorkspace(workspace: store, owner: "permissions-owner", externalFiles: store.external.store)
            let notes = try await XCTUnwrap(store.io).scan().notes
            for kind in MacAgentPermissions.ReadScope.allCases {
                var choice = MacAgentPermissions(); choice.readScope = kind; choice.folder = "Work"; choice.creationFolder = "Work"
                let scope = try choice.scope(mode: .review, writes: .context, current: "Work/A.md", paths: ["Work/A.md"], notes: notes)
                var record = try await client.start(objective: "Inspect permissions", mode: .review, scope: scope, chatID: "scope-" + kind.rawValue)
                record = try await tool(client, record, "note_get", ["selector": "beta"])
                XCTAssertEqual(try result(record)["ok"] as? Bool, kind != .selected)
                record = try await tool(client, record, "note_get", ["selector": "outside"])
                XCTAssertEqual(try result(record)["ok"] as? Bool, kind == .vault)
                record = try await tool(client, record, "note_create", ["title": "Denied", "body": "Body", "folder": "Work"])
                XCTAssertEqual(try result(record)["ok"] as? Bool, false, "Creation requires the explicit toggle even for folder and vault scope")
                XCTAssertTrue(record.run.pending.isEmpty)
                choice.create = true
                let allowed = try choice.scope(mode: .review, writes: .context, current: "Work/A.md", paths: ["Work/A.md"], notes: notes)
                var creator = try await client.start(objective: "Create", mode: .review, scope: allowed, chatID: "create-" + kind.rawValue)
                creator = try await tool(client, creator, "note_create", ["title": "Proposed", "body": "Body", "folder": "Work"])
                XCTAssertEqual(try result(creator)["ok"] as? Bool, true); XCTAssertEqual(creator.run.pending.count, 1)
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/Proposed.md").path))
                creator = try await tool(client, creator, "note_create", ["title": "Elsewhere", "body": "Body", "folder": "Other"])
                XCTAssertEqual(try result(creator)["ok"] as? Bool, kind == .vault)
                creator = try await tool(client, creator, "note_create", ["title": "Child", "body": "Body", "folder": "Work/Child"])
                XCTAssertEqual(try result(creator)["ok"] as? Bool, kind == .vault, "Folder creation permits the exact folder, even when its children are readable")
                choice.create = false; choice.fileNotes = true; choice.filingFolder = "Filed"
                let filingScope = try choice.scope(mode: .review, writes: .context, current: "Work/A.md", paths: ["Work/A.md"], notes: notes)
                var filer = try await client.start(objective: "File without creating", mode: .review, scope: filingScope, chatID: "file-" + kind.rawValue)
                filer = try await tool(client, filer, "note_create", ["title": "Forbidden new note", "body": "Body", "folder": "Work"])
                XCTAssertEqual(try result(filer)["ok"] as? Bool, false, "Filing permission must not enable new-note creation")
                filer = try await tool(client, filer, "note_get", ["selector": "alpha"])
                let revision = try XCTUnwrap(result(filer)["revision"] as? String)
                let destination = kind == .folder ? ["Work", "Filed"] : kind == .vault ? ["Other"] : ["Filed"]
                filer = try await tool(client, filer, "note_organize", ["selector": "alpha", "revision": revision, "typePath": destination])
                XCTAssertEqual(try result(filer)["ok"] as? Bool, true, filer.run.messages.last?.content ?? "")
                XCTAssertEqual(filer.run.pending.count, 1)
                let single = try choice.scope(mode: .review, writes: .current, current: "Work/A.md", paths: ["Work/A.md"], notes: notes)
                XCTAssertFalse(single.allowCreation)
                XCTAssertFalse(try choice.scope(mode: .ask, writes: .context, current: nil, paths: [], notes: notes).allowCreation)
            }
            var folder = MacAgentPermissions(); folder.readScope = .folder; folder.folder = "Work"
            XCTAssertThrowsError(try folder.scope(mode: .review, writes: .current, current: "Other/C.md", paths: [], notes: notes))
            folder.folder = ""
            let inbox = try folder.scope(mode: .ask, writes: .context, current: "Inbox note.md", paths: [], notes: notes)
            var record = try await client.start(objective: "Inbox", mode: .ask, scope: inbox, chatID: "inbox-scope")
            record = try await tool(client, record, "note_get", [:]); XCTAssertEqual(try result(record)["id"] as? String, "inbox")
            record = try await tool(client, record, "note_get", ["selector": "alpha"]); XCTAssertEqual(try result(record)["ok"] as? Bool, false)
        }
    }

    func testRunDefaultsRecoverAfterBusyOrFailedLoadsWithoutReplacingUserChoices() async throws {
        try await withVault { root, store in
            let file = root.appendingPathComponent(".zerus/ai/settings.json")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: root.appendingPathComponent(".zerus/properties-pane.json"), options: .atomic)
            let saved = Data(#"{"mode":"edit","writeScope":"current"}"#.utf8)
            try saved.write(to: file)
            let client = try MacAgentWorkspace(workspace: store, owner: "defaults-owner", externalFiles: store.external.store)
            let model = MacAgentRunDefaults()
            await model.load(client, available: false)
            XCTAssertFalse(model.ready); XCTAssertNil(model.snapshot)
            await model.load(client, available: true)
            XCTAssertTrue(model.ready); XCTAssertEqual(model.mode, .edit); XCTAssertEqual(model.writeScope, .current)
            model.mode = .ask; model.writeScope = .context
            try Data("{".utf8).write(to: file)
            await model.load(client, available: true)
            XCTAssertFalse(model.ready); XCTAssertNotNil(model.issue)
            XCTAssertEqual(model.mode, .ask); XCTAssertEqual(model.writeScope, .context)
            try saved.write(to: file)
            await model.load(client, available: true)
            XCTAssertTrue(model.ready); XCTAssertNil(model.issue)
            XCTAssertEqual(model.mode, .ask); XCTAssertEqual(model.writeScope, .context)
            model.useSaved()
            XCTAssertEqual(model.mode, .edit); XCTAssertEqual(model.writeScope, .current)
        }
    }

    func testScopedAgentLinksIncludeRelationsWithoutReadingOrExposingOutsideNotes() async throws {
        for variant in ["number", "checkbox", "duplicate", "wrapped", "hidden", "managed", "optional"] {
        try await withVault { root, store in
            var sources = [
                "Work/A.md": "---\nzerus-id: alpha\nRelated: [\"zerus:delta\"]\n---\n# Alpha\n\n[[Beta]] and [[zerus:hidden]].\n",
                "Work/B.md": "---\nzerus-id: beta\nRelated: [\"zerus:alpha\"]\n---\n# Beta\n\nLinked by relation only.\n",
                "Work/D.md": "---\nzerus-id: delta\n---\n# Delta\n\n```text\n[[zerus:alpha]]\n```\n",
                "Other/Outside.md": "---\nzerus-id: hidden\n---\n# Outside secret title\n\n[[zerus:alpha]] Hidden writing.\n",
                ".zerus/properties.json": #"{"Work":[{"name":"Related","type":"relation","relationMultiple":true}]}"#
            ]
            var paths: Set<String> = ["Work/A.md", "Work/B.md", "Work/D.md"]
            if ["number", "checkbox", "duplicate"].contains(variant) {
                let raw = variant == "number" ? "Related: 42" : variant == "checkbox" ? "Related: true" : "Related: one\nRelated: two"
                sources["Work/E.md"] = "---\nzerus-id: invalid-relation\n" + raw + "\n---\n# Bad relation\n"
                paths.insert("Work/E.md")
            } else if variant == "wrapped" {
                sources["Work/A.md"] = sources["Work/A.md"]!.replacingOccurrences(of: "zerus:delta", with: "[[zerus:delta]]")
            } else if variant == "hidden" {
                sources["Work/F.md"] = "---\nzerus-id: hidden-relation\nInverse: [\"zerus:alpha\"]\n---\n# Hidden inverse\n"
                sources[".zerus/properties.json"] = #"{"Work":[{"name":"Related","type":"relation","relationMultiple":true},{"name":"Inverse","type":"relation","relationHidden":true,"relationMultiple":true}]}"#
                paths.insert("Work/F.md")
            } else if variant == "managed" {
                sources[".zerus/links/saved.md"] = "---\nzerus-id: managed-link\n---\n# Beta\n"
                paths.insert(".zerus/links/saved.md")
            }
            for (path, content) in sources { let url = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(content.utf8).write(to: url) }
            let client = try MacAgentWorkspace(workspace: store, owner: "tools-owner", externalFiles: store.external.store)
            var record = try await client.start(objective: "Find related notes", mode: .review, scope: .init(paths: paths), chatID: "links-fixture")
            record = try await tool(client, record, "note_links", variant == "optional" ? [:] : ["selector": "alpha"])
            let links = try result(record), outgoing = try XCTUnwrap(links["outgoing"] as? [[String: Any]]), backlinks = try XCTUnwrap(links["backlinks"] as? [[String: Any]])
            XCTAssertEqual(links["ok"] as? Bool, true); XCTAssertEqual(links["scope"] as? String, "permitted_read_context")
            if variant != "optional" {
            XCTAssertEqual(Set(outgoing.compactMap { $0["id"] as? String }), ["beta", "delta"])
            XCTAssertTrue(outgoing.contains { $0["reference"] as? String == "zerus:hidden" && $0["unresolved"] as? Bool == true })
            XCTAssertEqual(backlinks.compactMap { $0["id"] as? String }, ["beta"], "Code literals and notes outside scope must not appear as backlinks")
            } // Omitted selector uses the shared engine's frozen current target.
            XCTAssertTrue(record.run.reads.isEmpty, "A graph summary is not a full body read")
            record = try await tool(client, record, "note_set_body", ["selector": "alpha", "revision": NativeAgentNote.hash(sources["Work/A.md"]!), "body": "Replacement without reading"])
            XCTAssertEqual(try result(record)["ok"] as? Bool, false); XCTAssertTrue(record.run.proposals.isEmpty)
            record = try await tool(client, record, "note_links", ["selector": "hidden"])
            XCTAssertEqual(try result(record)["ok"] as? Bool, false)
            XCTAssertFalse(record.run.messages.last?.content.contains("Outside secret title") == true)
            for (path, content) in sources { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(content.utf8)) }
        }
        }
    }

    func testRunPreferencesPreserveSharedSettingsAndFreezeExplicitCurrentTarget() async throws {
        try await withVault { root, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "preferences-owner", externalFiles: store.external.store)
            let file = root.appendingPathComponent(".zerus/ai/settings.json")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"maxSteps":7,"workflow":"weekly","future":{"keep":17}}"#.utf8).write(to: file)
            let initial = try await client.preferences(); XCTAssertEqual(initial.value.mode, .review); XCTAssertEqual(initial.value.writeScope, .context)
            var value = initial.value; value.mode = .edit; value.writeScope = .current; value.textFallback = true; value.workers = true
            let saved = try await client.savePreferences(value, expected: initial)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual(json["mode"] as? String, "edit"); XCTAssertEqual(json["writeScope"] as? String, "current")
            XCTAssertEqual(json["maxSteps"] as? Int, 7); XCTAssertEqual(json["workflow"] as? String, "weekly"); XCTAssertEqual((json["future"] as? [String: Int])?["keep"], 17)
            let beta = "---\nzerus-id: beta\n---\n# Beta\n\nCurrent target body.\n"
            try Data(beta.utf8).write(to: root.appendingPathComponent("Work/B.md"))
            var record = try await client.start(objective: "Read current", mode: .ask, scope: .init(paths: ["Work/A.md", "Work/B.md"], currentReadPath: "Work/B.md"), chatID: "preferences-fixture")
            XCTAssertEqual(record.run.currentReadID, "beta"); XCTAssertEqual(record.run.preferences?.mode, .ask)
            record = try await tool(client, record, "note_get", [:])
            XCTAssertEqual(try result(record)["id"] as? String, "beta")
            _ = try await client.savePreferences(.init(), expected: saved)
            let paused = try await client.pause(record, reason: "Fixture pause"), resumed = try await client.resume(paused)
            XCTAssertEqual(resumed.run.currentReadID, "beta"); XCTAssertEqual(resumed.run.preferences?.textFallback, true); XCTAssertEqual(resumed.run.preferences?.workers, true)
            let next = try await client.start(objective: "Read again", mode: .ask, scope: .init(paths: ["Work/A.md"]), chatID: "next-preferences")
            XCTAssertEqual(next.run.preferences?.textFallback, false); XCTAssertEqual(next.run.preferences?.workers, false)
            let bytes = try Data(contentsOf: file)
            do { _ = try await client.savePreferences(value, expected: saved); XCTFail("A stale preferences editor must not overwrite newer settings") }
            catch { XCTAssertTrue(error.localizedDescription.contains("Reload the saved settings"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testSharedRunPreferencesNormalizeWebValuesWithoutChangingBytesOnRead() async throws {
        try await withVault { root, store in
            let file = root.appendingPathComponent(".zerus/ai/settings.json")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = Data(#"{"mode":"future","writeScope":"other","textFallback":"yes","workers":1,"maxSteps":7,"workflow":"weekly","future":{"keep":33}}"#.utf8)
            XCTAssertEqual(try NativeAgentPreferences.read(original), NativeAgentPreferences())
            try Data("{}".utf8).write(to: root.appendingPathComponent(".zerus/properties-pane.json"), options: .atomic)
            try original.write(to: file)
            let client = try MacAgentWorkspace(workspace: store, owner: "normalized-owner", externalFiles: store.external.store)
            let saved = try await client.preferences()
            XCTAssertEqual(saved.value, NativeAgentPreferences())
            XCTAssertEqual(try Data(contentsOf: file), original, "Reading web-compatible defaults must preserve the original bytes")
            let record = try await client.start(objective: "Read", mode: .ask, scope: .init(paths: ["Work/A.md"]), chatID: "normalized-preferences")
            XCTAssertEqual(record.run.preferences?.workers, false); XCTAssertEqual(record.run.preferences?.textFallback, false)
            _ = try await client.savePreferences(.init(), expected: saved)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual(object["mode"] as? String, "review"); XCTAssertEqual(object["writeScope"] as? String, "context")
            XCTAssertEqual((object["future"] as? [String: Int])?["keep"], 33); XCTAssertEqual(object["maxSteps"] as? Int, 7); XCTAssertEqual(object["workflow"] as? String, "weekly")
        }
    }

    func testAnUnavailableExplicitCurrentTargetDoesNotFallBackToAnotherNote() async throws {
        try await withVault { _, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "current-owner", externalFiles: store.external.store)
            var record = try await client.start(objective: "Read current", mode: .ask, scope: .init(paths: ["Work/A.md"], currentReadPath: "Missing.md"), chatID: "no-current")
            record = try await tool(client, record, "note_get", [:])
            XCTAssertEqual(try result(record)["ok"] as? Bool, false, "A missing explicit current target must not select Alpha")
            XCTAssertTrue(record.run.reads.isEmpty)
        }
    }

    func testCLICompatibilityUsesScopedReadsAndKeepsOriginalCallHistory() async throws {
        try await withVault { root, store in
            let outside = root.appendingPathComponent("Outside.md"), secret = "---\nzerus-id: outside\n---\n# Hidden\nNever disclose this writing.\n"
            try Data(secret.utf8).write(to: outside)
            let client = try MacAgentWorkspace(workspace: store, owner: "cli-owner", externalFiles: store.external.store)
            var record = try await client.start(objective: "Read with compatible commands", mode: .review, scope: .init(paths: ["Work/A.md"]), chatID: "cli-fixture")
            record = try await tool(client, record, "zerus_cli", ["args": ["note", "list"]])
            let listed = try XCTUnwrap(try result(record)["notes"] as? [[String: Any]])
            XCTAssertEqual(listed.compactMap { $0["id"] as? String }, ["alpha"])
            record = try await tool(client, record, "zerus_cli", ["args": ["note", "list", "--json"]])
            XCTAssertEqual((try result(record)["notes"] as? [[String: Any]])?.compactMap { $0["id"] as? String }, ["alpha"])
            for words in [["note", "get"], ["note", "get", "--json"], ["note", "get", "alpha", "--json"]] {
                record = try await tool(client, record, "zerus_cli", ["args": words])
                XCTAssertEqual(try result(record)["id"] as? String, "alpha", words.joined(separator: " "))
                XCTAssertTrue((try result(record)["body"] as? String)?.contains("Original.") == true)
            }
            record = try await tool(client, record, "zerus_cli", ["args": ["note", "get", "alpha"]])
            let read = try result(record), revision = try XCTUnwrap(read["revision"] as? String)
            XCTAssertTrue((read["body"] as? String)?.contains("Original.") == true)
            XCTAssertEqual(record.run.reads.first?.id, "alpha")
            XCTAssertEqual(record.run.messages.last(where: { $0.role == "assistant" })?.toolCalls?.first?.name, "zerus_cli")
            XCTAssertEqual(record.run.messages.last?.toolCallId, record.run.messages.last(where: { $0.role == "assistant" })?.toolCalls?.first?.id)
            record = try await tool(client, record, "zerus_cli", ["args": ["search", "Original"]])
            XCTAssertEqual((try result(record)["notes"] as? [[String: Any]])?.compactMap { $0["id"] as? String }, ["alpha"])
            record = try await tool(client, record, "zerus_cli", ["args": ["type", "list"]])
            XCTAssertEqual(try result(record)["ok"] as? Bool, true); XCTAssertNotNil(try result(record)["definitions"])
            let sentinel = root.appendingPathComponent("MustNotExecute")
            let refusals: [([String], String)] = [
                (["note", "get", "outside"], "outside the chosen context"),
                (["note", "list", "--vault=/tmp/other"], "Vault overrides"),
                (["note", "list", "--yes"], "mutation approvals"),
                (["note", "set-body", "alpha", "New writing"], "dedicated scoped note tools"),
                (["sh", "-c", "touch " + sentinel.path], "dedicated scoped note tools")
            ]
            for (words, reason) in refusals {
                record = try await tool(client, record, "zerus_cli", ["args": words])
                XCTAssertEqual(try result(record)["ok"] as? Bool, false)
                let refusal = try result(record)
                XCTAssertTrue((refusal["error"] as? String)?.contains(reason) == true, String(describing: refusal))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
            // The alias read gives exactly the shared read coverage; a dedicated
            // mutation can stage it, but the CLI itself never stages or saves.
            XCTAssertTrue(record.run.proposals.isEmpty)
            record = try await tool(client, record, "note_set_body", ["selector": "alpha", "revision": revision, "body": "Explicit dedicated proposal."])
            XCTAssertEqual(record.run.pending.count, 1)
            XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8).contains("Original."))
            XCTAssertEqual(try Data(contentsOf: outside), Data(secret.utf8))
            _ = try NativeAgentJournal.decode(record.bytes, id: record.id)
        }
    }

    func testAgentMemoryReadsSavedReferenceAndCannotPersistModelSuggestions() async throws {
        try await withVault { root, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "tools-owner", externalFiles: store.external.store)
            let initial = try await client.guidance()
            var saved = try await client.saveGuidance(.init(instructions: "Keep concise.", memory: "Initial project fact."), expected: initial)
            var record = try await client.start(objective: "Review preferences", mode: .ask, scope: .init(paths: ["Work/A.md"]), chatID: "memory-fixture")
            saved = try await client.saveGuidance(.init(instructions: "Changed future instructions.", memory: "Current saved project fact."), expected: saved)
            record = try await tool(client, record, "memory", ["operation": "read"])
            XCTAssertEqual(try result(record)["memory"] as? String, "Current saved project fact."); XCTAssertEqual(try result(record)["trusted"] as? Bool, false)
            XCTAssertEqual(record.run.guidance?.instructions, "Keep concise.", "A memory read cannot replace frozen instructions")
            for operation in ["remember", "forget"] {
                record = try await tool(client, record, "memory", ["operation": operation, "text": "Model suggestion"])
                XCTAssertEqual(try result(record)["ok"] as? Bool, false)
                XCTAssertTrue((try result(record)["error"] as? String)?.contains("visible Memory editor") == true)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/ai/memory.md")), saved.memoryBytes)
            }
            let request = try await MacAgentRequest.prepare(record.run, store: .init(directory: root.appendingPathComponent("PrivateAttachments")))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.json.utf8)) as? [String: Any]), schemas = try XCTUnwrap(json["tools"] as? [[String: Any]])
            XCTAssertTrue(schemas.contains { $0["name"] as? String == "memory" }); XCTAssertTrue(schemas.contains { $0["name"] as? String == "note_links" })
            XCTAssertFalse(schemas.contains { $0["name"] as? String == "note_set_body" })
        }
    }

    func testMacAgentSettingsReachRunStartAndRefuseStaleEditors() async throws {
        try await withVault { root, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "settings-owner", externalFiles: store.external.store)
            let settings = root.appendingPathComponent(".zerus/ai/settings.json")
            try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"workflow":"meeting","foreign":{"keep":42},"maxSteps":12}"#.utf8).write(to: settings)
            let original = try await client.limits(); var chosen = original.limits; chosen.maxSteps = 7; chosen.effort = .high
            let savedLimits = try await client.saveLimits(chosen, expected: original)
            let guidance = try await client.guidance(), value = NativeAgentGuidance(instructions: "Write concise Portuguese summaries.", memory: "Project café 日本語.")
            _ = try await client.saveGuidance(value, expected: guidance)
            let draft = try await client.newWorkflow(title: "Project review")
            let source = "# Project review\n\nRead sources; preserve dates and cite disagreements.\n"
            let document = try await client.saveWorkflow(source, expected: draft), catalog = try await client.workflows()
            _ = try await client.selectWorkflow(document.id, expected: catalog)
            let first = try await client.start(objective: "Review the project", mode: .ask, scope: .init(paths: ["Work/A.md"]), chatID: "settings-fixture")
            XCTAssertEqual(first.run.limits, chosen); XCTAssertEqual(first.run.guidance, value)
            XCTAssertEqual(first.run.workflow?.id, document.id); XCTAssertEqual(first.run.workflow?.instructions, source)
            let beforeConflict = try Data(contentsOf: settings)
            do { _ = try await client.saveLimits(chosen, expected: savedLimits); XCTFail("A stale settings editor must not overwrite workflow or limit changes") }
            catch { XCTAssertTrue(error.localizedDescription.contains("AI settings"), error.localizedDescription); XCTAssertTrue(error.localizedDescription.contains("Reload the saved settings"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: settings), beforeConflict)
        }
    }

    func testUnsavedAgentSettingsRefuseQuitUntilSavedOrDiscarded() async throws {
        try await withVault { _, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "settings-owner", externalFiles: store.external.store)
            client.setSettingsDraftHeld(true)
            let closed = await store.prepareToQuit()
            XCTAssertFalse(closed, "Quit must retain an unsaved guidance or workflow draft")
            if closed { return }
            XCTAssertTrue(store.issue?.contains("AI settings") == true)
            client.setSettingsDraftHeld(false)
            let allowed = await store.prepareToQuit(); XCTAssertTrue(allowed)
        }
    }

    func testMacAgentSettingsRefuseBusyOrReplacedVaultWithoutWriting() async throws {
        try await withVault { root, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "settings-owner", externalFiles: store.external.store)
            let guidance = try await client.guidance()
            store.busy = true
            do { _ = try await client.saveGuidance(.init(instructions: "Blocked", memory: ""), expected: guidance); XCTFail("Busy vault must refuse settings writes") }
            catch { XCTAssertTrue(error.localizedDescription.contains("Finish the current change"), error.localizedDescription) }
            store.busy = false
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus/ai/instructions.md").path))
            let other = root.appendingPathComponent("OtherVault"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            await store.openVault(other)
            do { _ = try await client.saveGuidance(.init(instructions: "Wrong vault", memory: ""), expected: guidance); XCTFail("An editor from an earlier activation must not write") }
            catch { XCTAssertTrue(error.localizedDescription.contains("vault changed"), error.localizedDescription) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus/ai/instructions.md").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: other.appendingPathComponent(".zerus/ai/instructions.md").path))
        }
    }

    func testConnectedFileDraftIsSavedBeforeAgentReadAndRefreshedAfterApply() async throws {
        try await withVault { root, store in
            try await connected(root: root, file: root.appendingPathComponent("Work/A.md")) { library, session, holder, _ in
                session.changeBody(session.document.parts.body + "\nConnected editor writing.\n")
                let checkpointed = await session.checkpoint(); XCTAssertTrue(checkpointed)
                let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: library.store)
                var record = try await client.start(objective: "Append", mode: .review, scope: .init(paths: ["Work/A.md"], currentWritePath: "Work/A.md"), chatID: "fixture")
                XCTAssertFalse(session.dirty); XCTAssertTrue(store.body.contains("Connected editor writing."))
                record = try await tool(client, record, "note_get", ["selector": "alpha"])
                let read = try result(record); XCTAssertTrue((read["body"] as? String)?.contains("Connected editor writing.") == true)
                record = try await tool(client, record, "note_append", ["selector": "alpha", "revision": XCTUnwrap(read["revision"] as? String), "text": "Agent addition."])
                let pending = try XCTUnwrap(record.run.pending.first)
                let review = try await client.review(record, ids: [pending.id])
                _ = try await client.apply(review)
                XCTAssertTrue(session.document.parts.body.contains("Agent addition.")); XCTAssertFalse(session.dirty); XCTAssertFalse(session.conflict)
                XCTAssertTrue(session.document.parts.body.contains("Connected editor writing."))
                XCTAssertFalse(session.agentLocked); XCTAssertTrue(holder.external.selected === session)
            }
        }
    }
    func testMovedConnectedFileStillProtectsItsClosedRecoveryDraft() async throws {
        for replaced in [false, true] {
            try await withVault { root, store in
                try await connected(root: root, file: root.appendingPathComponent("Work/A.md")) { library, session, holder, _ in
                    session.changeBody("Unsaved writing before the file moved.")
                    let kept = await session.checkpoint(); XCTAssertTrue(kept)
                    holder.external.selected = nil; let closed = await library.close(); XCTAssertTrue(closed)
                    if replaced {
                        let file = root.appendingPathComponent("Work/A.md")
                        try Data(contentsOf: file).write(to: file, options: .atomic)
                    }
                    let destination = root.appendingPathComponent("Work/B.md")
                    try FileManager.default.moveItem(at: root.appendingPathComponent("Work/A.md"), to: destination)
                    let before = try Data(contentsOf: destination)
                    let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: library.store)
                    var record = try await client.start(objective: "Append", mode: .review, scope: .init(paths: ["Work/B.md"], currentWritePath: "Work/B.md"), chatID: "fixture")
                    record = try await tool(client, record, "note_get", ["selector": "alpha"])
                    let revision = try XCTUnwrap(result(record)["revision"] as? String)
                    record = try await tool(client, record, "note_append", ["selector": "alpha", "revision": revision, "text": "Agent addition."])
                    let pending = try XCTUnwrap(record.run.pending.first)
                    do { _ = try await client.review(record, ids: [pending.id]); XCTFail("Bookmarks must follow a moved file's retained draft") }
                    catch { XCTAssertTrue(error.localizedDescription.contains("recovery draft"), error.localizedDescription) }
                    XCTAssertEqual(try Data(contentsOf: destination), before)
                }
            }
        }
    }
    func testCleanConnectedFileWithoutARecoveryRecordAllowsApproval() async throws {
        try await withVault { root, store in
            try await connected(root: root, file: root.appendingPathComponent("Work/A.md")) { library, session, _, directory in
                let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: library.store)
                let (_, review) = try await proposal(client)
                let file = directory.appendingPathComponent("Drafts/" + session.id.uuidString + ".json")
                XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
                _ = try await client.apply(review)
                XCTAssertTrue(store.body.contains("Agent addition.")); XCTAssertTrue(session.document.parts.body.contains("Agent addition."))
                XCTAssertFalse(session.dirty); XCTAssertFalse(session.agentLocked)
            }
        }
    }
    func testActiveAndClosedConnectedRecoveryDraftsBlockApproval() async throws {
        for closed in [false, true] {
            try await withVault { root, store in
                try await connected(root: root, file: root.appendingPathComponent("Work/A.md")) { library, session, holder, _ in
                    let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: library.store)
                    let (record, review) = try await proposal(client)
                    let before = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
                    let journal = try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(record.id)))
                    session.changeBody(session.document.parts.body + "\nUncommitted connected writing.\n")
                    let kept = await session.checkpoint(); XCTAssertTrue(kept)
                    if closed { holder.external.selected = nil; let didClose = await library.close(); XCTAssertTrue(didClose) }
                    do { _ = try await client.apply(review); XCTFail("Connected recovery must block an approval") }
                    catch { XCTAssertTrue(error.localizedDescription.contains("recovery draft"), error.localizedDescription) }
                    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), before)
                    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(record.id))), journal)
                    XCTAssertTrue(session.document.parts.body.contains("Uncommitted connected writing."))
                }
            }
        }
    }
    func testConnectedRecoveryAppearingAfterAdmissionIsCheckedAtCommit() async throws {
        try await withVault { root, store in
            try await connected(root: root, file: root.appendingPathComponent("Work/A.md")) { library, session, holder, directory in
                let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: library.store)
                let (record, review) = try await proposal(client)
                let before = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
                let journal = try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(record.id)))
                let id = session.id, file = directory.appendingPathComponent("Drafts/" + id.uuidString + ".json")
                session.changeBody("Recovered newer writing.")
                let keptDirty = await session.checkpoint(); XCTAssertTrue(keptDirty)
                let dirtyBytes = try Data(contentsOf: file)
                session.changeContent(String(decoding: before, as: UTF8.self))
                let keptClean = await session.checkpoint(); XCTAssertTrue(keptClean)
                holder.external.selected = nil; let closed = await library.close(); XCTAssertTrue(closed)
                var writeError: Error?, wrote = false
                let observer = store.busyPublisher.sink { busy in if busy && !wrote { wrote = true; do { try dirtyBytes.write(to: file, options: .atomic) } catch { writeError = error } } }
                defer { observer.cancel() }
                do { _ = try await client.apply(review); XCTFail("Commit must recheck recovery after admission") }
                catch { XCTAssertTrue(error.localizedDescription.contains("recovery draft"), error.localizedDescription) }
                XCTAssertTrue(wrote); XCTAssertNil(writeError)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), before)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(record.id))), journal)
                XCTAssertEqual(try Data(contentsOf: file), dirtyBytes)
            }
        }
    }
    func testUnrelatedUnreadableConnectedDraftDoesNotBlockAnotherNote() async throws {
        try await withVault { root, store in
            let outside = root.appendingPathExtension("md")
            try Data("# Outside\n\nOriginal.\n".utf8).write(to: outside)
            defer { try? FileManager.default.removeItem(at: outside) }
            try await connected(root: root, file: outside) { library, session, holder, directory in
                let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: library.store)
                let (_, review) = try await proposal(client)
                session.changeBody("Private outside writing."); let kept = await session.checkpoint(); XCTAssertTrue(kept)
                holder.external.selected = nil; let closed = await library.close(); XCTAssertTrue(closed)
                let draft = directory.appendingPathComponent("Drafts/" + session.id.uuidString + ".json")
                try Data("unreadable".utf8).write(to: draft)
                _ = try await client.apply(review)
                XCTAssertTrue(store.body.contains("Agent addition."))
                XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "# Outside\n\nOriginal.\n")
                XCTAssertEqual(try Data(contentsOf: draft), Data("unreadable".utf8))
            }
        }
    }
    func testAgentReadsSavedWindowDraftsStagesThenAppliesAndUndoesWithPeerReconciliation() async throws {
        try await withVault { root, store in
            let peer = MacWorkspace(); await peer.openVault(root); await peer.openNote("Work/A.md")
            peer.changed(peer.body + "\nPeer writing.\n")
            let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: NativeExternalNotesStore(directory: root.appendingPathComponent(".connections")))
            var record = try await client.start(objective: "Append a paragraph", mode: .review, scope: .init(paths: ["Work/A.md"], currentWritePath: "Work/A.md"), chatID: "fixture")
            XCTAssertFalse(peer.isDirty)
            XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8).contains("Peer writing."))
            record = try await tool(client, record, "note_get", ["selector": "alpha"])
            let read = try result(record)
            XCTAssertTrue((read["body"] as? String)?.contains("Peer writing.") == true)
            let revision = try XCTUnwrap(read["revision"] as? String)
            let before = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
            record = try await tool(client, record, "note_append", ["selector": "alpha", "revision": revision, "text": "Confirmed addition."])
            let proposal = try XCTUnwrap(record.run.pending.first)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), before, "A tool must stage rather than silently save Review changes")
            let review = try await client.review(record, ids: [proposal.id])
            record = try await client.apply(review)
            XCTAssertTrue(store.body.contains("Confirmed addition.")); XCTAssertEqual(store.body, peer.body)
            XCTAssertFalse(store.isDirty); XCTAssertFalse(peer.isDirty)
            let receipt = try XCTUnwrap(record.run.receipts.last)
            XCTAssertEqual(receipt.after.count, 1)
            let undo = try await client.undoReview(record, receiptID: receipt.id)
            record = try await client.apply(undo)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), before)
            XCTAssertFalse(store.body.contains("Confirmed addition.")); XCTAssertEqual(store.body, peer.body)
            XCTAssertNotNil(record.run.receipts.last?.undoneAt)
            XCTAssertFalse(store.busy); XCTAssertFalse(peer.busy)
        }
    }
    func testApprovalRejectsPeerWritingOutsideEditsAndRetainedDraftsWithoutChangingTheReceipt() async throws {
        for hazard in ["peer", "disk", "recovery"] {
            try await withVault { root, store in
                let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: NativeExternalNotesStore(directory: root.appendingPathComponent(".connections")))
                let (record, review) = try await proposal(client)
                let journal = try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(record.id)))
                let peer = MacWorkspace(); await peer.openVault(root); await peer.openNote("Work/A.md")
                var kept: Data?
                switch hazard {
                case "peer": peer.changed(peer.body + "\nNewer unsaved writing.\n")
                case "disk":
                    kept = Data("---\nzerus-id: alpha\n---\n# Alpha\n\nOutside newer writing.\n".utf8)
                    try XCTUnwrap(kept).write(to: root.appendingPathComponent("Work/A.md"))
                default:
                    try MacNoteRecoveryStore.checkpoint(root: root, note: XCTUnwrap(store.current), body: "Private retained writing.", windowID: "closed-fixture")
                }
                do { _ = try await client.apply(review); XCTFail("Approval must reject " + hazard) }
                catch {
                    let message = error.localizedDescription
                    if hazard == "peer" { XCTAssertTrue(message.contains("drafts"), message) }
                    else if hazard == "recovery" { XCTAssertTrue(message.contains("retained draft"), message) }
                    else { XCTAssertTrue(message.contains("changed"), message) }
                }
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(NativeAgentJournal.path(record.id))), journal)
                if let kept { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), kept) }
                if hazard == "peer" { XCTAssertTrue(peer.body.contains("Newer unsaved writing.")); XCTAssertTrue(peer.isDirty) }
                XCTAssertFalse(store.busy); XCTAssertFalse(peer.busy)
            }
        }
    }
    func testWritingTriggeredByAdmissionIsCheckpointedAndApprovalStops() async throws {
        try await withVault { root, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: NativeExternalNotesStore(directory: root.appendingPathComponent(".connections")))
            let (_, review) = try await proposal(client)
            let peer = MacWorkspace(); await peer.openVault(root); await peer.openNote("Work/A.md")
            let before = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
            var delivered = false
            let observation = peer.busyPublisher.sink { locked in
                if locked && !delivered { delivered = true; peer.changed(peer.body + "\nWriting committed as the editor locks.\n") }
            }
            defer { observation.cancel() }
            do { _ = try await client.apply(review); XCTFail("Late writing must stop approval") }
            catch { XCTAssertTrue(error.localizedDescription.contains("Writing arrived"), error.localizedDescription) }
            XCTAssertTrue(delivered); XCTAssertTrue(peer.isDirty)
            XCTAssertTrue(peer.body.contains("Writing committed as the editor locks."))
            XCTAssertFalse(try MacNoteRecoveryStore.locations(root: root, path: "Work/A.md").isEmpty)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), before)
            XCTAssertFalse(peer.busy); XCTAssertFalse(store.busy)
        }
    }
    func testAWindowOpenedThroughACaseAliasStillProtectsItsUnsavedWriting() async throws {
        try await withVault { root, store in
            let alias = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent.uppercased())
            guard FileManager.default.fileExists(atPath: alias.path) else { throw XCTSkip("The fixture volume is case-sensitive") }
            let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: NativeExternalNotesStore(directory: root.appendingPathComponent(".connections")))
            let (_, review) = try await proposal(client)
            let peer = MacWorkspace(); await peer.openVault(alias); await peer.openNote("Work/A.md")
            peer.changed(peer.body + "\nAlias window writing.\n")
            do { _ = try await client.apply(review); XCTFail("A path alias cannot hide an open draft") }
            catch { XCTAssertTrue(error.localizedDescription.contains("drafts"), error.localizedDescription) }
            XCTAssertTrue(peer.isDirty); XCTAssertTrue(peer.body.contains("Alias window writing."))
            XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8).contains("Agent addition."))
        }
    }
    func testOldVaultActivationAndSamePathReplacementInvalidateTheAgentContext() async throws {
        try await withVault { root, store in
            let client = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: NativeExternalNotesStore(directory: root.appendingPathComponent(".connections")))
            let (_, review) = try await proposal(client)
            await store.openVault(root)
            do { _ = try await client.apply(review); XCTFail("Reopening the same path must invalidate old reviews") }
            catch { XCTAssertTrue(error.localizedDescription.contains("vault changed"), error.localizedDescription) }
            let fresh = try MacAgentWorkspace(workspace: store, owner: "mac-test-owner", externalFiles: NativeExternalNotesStore(directory: root.appendingPathComponent(".connections")))
            let backup = root.appendingPathExtension("old")
            try FileManager.default.moveItem(at: root, to: backup)
            defer { try? FileManager.default.removeItem(at: backup) }
            try FileManager.default.copyItem(at: backup, to: root)
            do { _ = try await fresh.records(); XCTFail("A replacement directory must not inherit an active run context") }
            catch { XCTAssertTrue(error.localizedDescription.contains("vault changed"), error.localizedDescription) }
        }
    }
    func testRunCatalogBoundsReadsHonorsCancellationAndPreservesRecoveryCaches() async throws {
        try await withVault { root, workspace in
            let client = try MacAgentWorkspace(workspace: workspace, owner: "cache-owner", externalFiles: .init(directory: root.appendingPathComponent(".connections")))
            let record = try await client.start(objective: "Read", mode: .ask, scope: .init(paths: ["Work/A.md"]), chatID: "cache-fixture")
            let request = try await MacAgentRequest.prepare(record.run, store: .init(directory: root.appendingPathComponent("PrivateAttachments")))
            let source = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.json.utf8)) as? [String: Any])
            let messages = try XCTUnwrap(source["messages"] as? [[String: Any]]), system = try XCTUnwrap(source["systemPrompt"] as? String)
            let cache = client.continuations.bound(endpoint: "https://fixture.invalid/messages", model: "claude-fixture", apiKey: "synthetic-key", run: record.id)
            defer { try? client.continuations.remove(run: record.id) }
            let reply = try MacAgentCompletion(json: #"{"content":"Answer.","toolCalls":[],"usage":{}}"#)
            try cache.save(messages: messages, reply: reply, blocks: [["type": "text", "text": "Answer."]], system: system)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: cache.directory.path)
            let visible = try await client.records()
            XCTAssertTrue(visible.records.contains { $0.id == record.id }); XCTAssertTrue(FileManager.default.fileExists(atPath: cache.directory.path))
            let journal = root.appendingPathComponent(NativeAgentJournal.path(record.id)), io = try XCTUnwrap(workspace.io)
            let healthy = try await client.start(objective: "Healthy entry", mode: .ask, scope: .init(paths: ["Work/A.md"]), chatID: "healthy-catalog")
            let handle = try FileHandle(forWritingTo: journal)
            try handle.truncate(atOffset: 8_000_001); try handle.close()
            do { _ = try await io.agentJournalData(NativeAgentJournal.path(record.id)); XCTFail("Oversized manifests must be refused by the file reader") }
            catch { XCTAssertTrue(error.localizedDescription.contains("8 MB manifest limit"), error.localizedDescription) }
            let oversized = try await client.records()
            XCTAssertTrue(oversized.unreadable.contains(NativeAgentJournal.path(record.id)))
            XCTAssertEqual(oversized.records.map(\.id), [healthy.id])
            XCTAssertTrue(FileManager.default.fileExists(atPath: cache.directory.path), "An oversized synced journal must retain recovery continuations")
            do { _ = try await client.resume(record); XCTFail("Resume must use the same bounded journal read") }
            catch { XCTAssertTrue(error.localizedDescription.contains("8 MB manifest limit"), error.localizedDescription) }
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: journal.path)[.size] as? NSNumber)?.intValue, 8_000_001)
            let unchanged = try FileHandle(forReadingFrom: journal)
            XCTAssertEqual(try unchanged.read(upToCount: record.bytes.count), record.bytes); try unchanged.close()
            let canceled = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await io.agentRuns()
            }
            do { _ = try await canceled.value; XCTFail("A canceled scan must not publish a partial catalog or unreadable-file result") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: cache.directory.path))
            do {
                let reached = expectation(description: "catalog read reached a real coordinated file wait")
                let gate = MacCoordinatedReadGate(root.appendingPathComponent(NativeAgentJournal.path(healthy.id))) { reached.fulfill() }
                NSFileCoordinator.addFilePresenter(gate)
                defer { gate.release(); NSFileCoordinator.removeFilePresenter(gate) }
                let reading = Task { try await io.agentRuns() }
                await fulfillment(of: [reached], timeout: 5)
                reading.cancel(); gate.release()
                do { _ = try await reading.value; XCTFail("Cancellation during a file wait must discard the partial catalog") }
                catch { XCTAssertTrue(error is CancellationError) }
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: cache.directory.path))
            try Data("unreadable journal to recover".utf8).write(to: journal)
            let unreadable = try await client.records()
            XCTAssertTrue(unreadable.unreadable.contains { $0.contains(record.id.uuidString.lowercased()) })
            XCTAssertTrue(FileManager.default.fileExists(atPath: cache.directory.path), "A recoverable journal must retain its provider continuation")
            try FileManager.default.removeItem(at: journal)
            _ = try await client.records()
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.directory.path), "An old continuation whose journal was deleted must be removed")
        }
    }
    private func connected(root: URL, file: URL, operation: (MacExternalLibrary, MacExternalSession, MacWorkspace, URL) async throws -> Void) async throws {
        let directory = root.appendingPathComponent(".connections"), library = MacExternalLibrary(directory: directory)
        await library.open(file); XCTAssertNil(library.issue)
        let session = try XCTUnwrap(library.selected), holder = MacWorkspace()
        holder.external.selected = session
        let outcome: Result<Void, Error>
        do { try await operation(library, session, holder, directory); outcome = .success(()) }
        catch { outcome = .failure(error) }
        holder.external.selected = nil; _ = await library.close()
        try outcome.get()
    }
    private func proposal(_ client: MacAgentWorkspace) async throws -> (NativeAgentRecord, NativeAgentReview) {
        var record = try await client.start(objective: "Append", mode: .review, scope: .init(paths: ["Work/A.md"], currentWritePath: "Work/A.md"), chatID: "fixture")
        record = try await tool(client, record, "note_get", ["selector": "alpha"])
        let revision = try XCTUnwrap(result(record)["revision"] as? String)
        record = try await tool(client, record, "note_append", ["selector": "alpha", "revision": revision, "text": "Agent addition."])
        let pending = try XCTUnwrap(record.run.pending.first)
        return (record, try await client.review(record, ids: [pending.id]))
    }
    private func tool(_ client: MacAgentWorkspace, _ record: NativeAgentRecord, _ name: String, _ arguments: [String: Any]) async throws -> NativeAgentRecord {
        let call = NativeAgentCall(id: UUID().uuidString, name: name, arguments: String(decoding: try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]), as: UTF8.self))
        let received = try await client.response(record, content: "", calls: [call], input: 1, output: 1, seconds: 0)
        return try await client.tool(received, call: call)
    }
    private func result(_ record: NativeAgentRecord) throws -> [String: Any] {
        let message = try XCTUnwrap(record.run.messages.last)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(message.content.utf8)) as? [String: Any])
    }
    private func withVault(source: String? = nil, _ operation: (URL, MacWorkspace) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-Mac-agent-" + UUID().uuidString)
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work"), withIntermediateDirectories: true)
        try Data((source ?? "---\nzerus-id: alpha\n---\n# Alpha\n\nOriginal.\n").utf8).write(to: root.appendingPathComponent("Work/A.md"))
        defer {
            for file in (try? MacNoteRecoveryStore.locations(root: root, path: "Work/A.md")) ?? [] { try? FileManager.default.removeItem(at: file) }
            defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
            try? FileManager.default.removeItem(at: root)
        }
        let store = MacWorkspace(); await store.openVault(root); await store.openNote("Work/A.md")
        XCTAssertNil(store.issue)
        let outcome: Result<Void, Error>
        do { try await operation(root, store); outcome = .success(()) }
        catch { outcome = .failure(error) }
        let peers = MacWorkspace.windows.compactMap(\.value).filter { $0.root?.lastPathComponent.caseInsensitiveCompare(root.lastPathComponent) == .orderedSame }
        for peer in peers {
            _ = await peer.prepareToCloseWindow()
            if let directory = peer.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            if let peerRoot = peer.root {
                for file in (try? MacNoteRecoveryStore.locations(root: peerRoot, path: "Work/A.md")) ?? [] { try? FileManager.default.removeItem(at: file) }
                defaults.removeObject(forKey: MacNavigationState.key(peerRoot)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(peerRoot.path))
            }
        }
        try outcome.get()
    }
}
