import XCTest
import Combine
@testable import Zerus_Native

@MainActor final class MacCLISetupTests: XCTestCase {
    func testRegistrationIsReviewedPreservesOtherVaultsAndRejectsStaleCatalog() async throws {
        try await withVault { root, store in
            let catalog = root.appendingPathComponent("catalog.json"), registry = MacCLIVaultRegistry(file: catalog)
            let other = UUID().uuidString.lowercased()
            let original = Data(("{\"version\":1,\"future\":42,\"defaultVaultId\":\"" + other + "\",\"vaults\":[{\"id\":\"" + other + "\",\"name\":\"Other\",\"path\":\"/other\",\"foreign\":true}]}").utf8)
            try original.write(to: catalog)
            let review = try await store.prepareCLIRegistration(name: "My notes", makeDefault: false, registry: registry)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus/vault.json").path))
            XCTAssertEqual(try Data(contentsOf: catalog), original)
            try await store.commitCLIRegistration(review, registry: registry)
            let object = try json(catalog), rows = try XCTUnwrap(object["vaults"] as? [[String: Any]])
            XCTAssertEqual(object["future"] as? Int, 42); XCTAssertEqual(object["defaultVaultId"] as? String, other)
            XCTAssertEqual(rows.first { $0["id"] as? String == other }?["foreign"] as? Bool, true)
            XCTAssertEqual(rows.first { $0["name"] as? String == "My notes" }?["path"] as? String, root.resolvingSymlinksInPath().path)
            XCTAssertEqual(try json(root.appendingPathComponent(".zerus/vault.json"))["vaultId"] as? String, review.manifest.id.uuidString.lowercased())
            let update = try await store.prepareCLIRegistration(name: "Renamed", makeDefault: true, registry: registry)
            XCTAssertEqual(update.registry.previousName, "My notes")
            try await store.commitCLIRegistration(update, registry: registry)
            XCTAssertEqual(try json(catalog)["defaultVaultId"] as? String, review.manifest.id.uuidString.lowercased())
            XCTAssertEqual((try json(catalog)["vaults"] as? [[String: Any]])?.count, 2)
            let stale = try await store.prepareCLIRegistration(name: "Stale", makeDefault: false, registry: registry)
            try original.write(to: catalog)
            do { try await store.commitCLIRegistration(stale, registry: registry); XCTFail("Must retain a changed catalog") }
            catch { XCTAssertTrue(error.localizedDescription.contains("registry changed after review"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: catalog), original)
            for bad in [Data("not JSON".utf8), Data("{\"version\":2,\"vaults\":[]}".utf8)] {
                try bad.write(to: catalog)
                do { _ = try await store.prepareCLIRegistration(name: "Blocked", makeDefault: false, registry: registry); XCTFail("Unsupported registries must survive") } catch {}
                XCTAssertEqual(try Data(contentsOf: catalog), bad)
            }
        }
    }

    func testMetadataPreparationPreservesBodiesAndForeignYamlAndAdoptsOpenNoteIdentity() async throws {
        let uuid = "36d50b20-5ef7-4e0c-b121-1aacfa26187c"
        let source = "\u{feff}---\r\nForeign: 'keep: this' # comment\r\ngrimoire-id: '" + uuid + "' # keep ID\r\ngrimoire-pinned: 'true' # pinned\r\n---\r\n# Original\r\n\r\nBody **unchanged**.\r\n"
        try await withVault(source: source) { root, store in
            try write("Trash body\n", root: root, path: ".trash/Old.md")
            try write("Managed body\n", root: root, path: ".zerus/files/Managed.md")
            let review = try await store.prepareCLIMetadata()
            XCTAssertTrue(review.issues.isEmpty, review.issues.joined(separator: "\n"))
            XCTAssertEqual(review.idsAdded, 1); XCTAssertEqual(review.keysRenamed, 2)
            XCTAssertEqual(Set(review.notes.map(\.path)), ["Work/A.md", ".trash/Old.md"])
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.utf8))
            try await store.commitCLIMetadata(review)
            let saved = try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8)
            let bytes = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
            XCTAssertTrue(bytes.starts(with: Data("\u{feff}---\r\n".utf8)))
            XCTAssertTrue(saved.contains("Foreign: 'keep: this' # comment\r\n")); XCTAssertTrue(saved.contains("# keep ID")); XCTAssertTrue(saved.contains("# pinned"))
            XCTAssertEqual(NativeFrontmatter(NoteDocument.decodeUTF8(bytes)!).body, "# Original\r\n\r\nBody **unchanged**.\r\n")
            XCTAssertEqual(store.notes.first { $0.path == "Work/A.md" }?.stableID, uuid)
            XCTAssertNil(store.noteDiskChange); XCTAssertFalse(store.isDirty)
            let manifest = try json(root.appendingPathComponent(".zerus/vault.json"))
            XCTAssertEqual(manifest["metadataVersion"] as? Int, 1); XCTAssertEqual(manifest["idsRequired"] as? Bool, true)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/files/Managed.md")), Data("Managed body\n".utf8))
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("CLI/zerus")
            process.arguments = ["--vault", root.path, "--json", "note", "get", "--id", uuid, "--body"]
            process.standardOutput = output; process.standardError = errors
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
            let response = try XCTUnwrap(JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile()) as? [String: Any])
            XCTAssertEqual(response["ok"] as? Bool, true)
            let data = try XCTUnwrap(response["data"] as? [String: Any])
            XCTAssertEqual(data["content"] as? String, "# Original\r\n\r\nBody **unchanged**.\r\n")
            XCTAssertEqual((data["properties"] as? [String: Any])?["zerus-pinned"] as? Bool, true)
            let again = try await store.prepareCLIMetadata()
            XCTAssertTrue(again.issues.isEmpty); XCTAssertTrue(again.noteChanges.isEmpty); XCTAssertEqual(again.idsAdded, 0)
            store.changed(store.body + "Later writing.\r\n"); let savedLater = await store.save(); XCTAssertTrue(savedLater)
            XCTAssertTrue(try Data(contentsOf: root.appendingPathComponent("Work/A.md")).starts(with: Data("\u{feff}---\r\n".utf8)))
        }
    }

    func testInvalidMetadataBlocksAllWrites() async throws {
        for source in ["---\nzerus-id: invalid\n---\nBody\n", "---\nzerus-id: [one, two]\n---\nBody\n", "---\nForeign: never closed\n", "---\nzerus-pinned: yes\n---\nBody\n", "---\ngrimoire-id: one\nzerus-id: two\n---\nBody\n"] {
            try await withVault(source: source) { root, store in
                let review = try await store.prepareCLIMetadata(); XCTAssertFalse(review.issues.isEmpty, source)
                do { try await store.commitCLIMetadata(review); XCTFail("Blocked metadata must not apply") }
                catch { XCTAssertTrue(error.localizedDescription.contains("blocked CLI metadata review"), error.localizedDescription) }
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.utf8))
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus/vault.json").path))
            }
        }
        try await withVault(source: "---\nzerus-id: 36d50b20-5ef7-4e0c-b121-1aacfa26187c\n---\nA\n") { root, store in
            try write("---\nzerus-id: 36D50B205EF74E0CB1211AACFA26187C\n---\nB\n", root: root, path: "B.md")
            let review = try await store.prepareCLIMetadata()
            XCTAssertTrue(review.issues.contains { $0.contains("shares its note ID") })
        }
    }

    func testMetadataCommitRefusesChangedNotesNewNotesAndRetainedDrafts() async throws {
        for hazard in ["edit", "own-edit", "new", "draft", "activation"] {
            try await withVault { root, store in
                let original = try Data(contentsOf: root.appendingPathComponent("Work/A.md")), review = try await store.prepareCLIMetadata()
                if hazard == "edit" { try write("External writing\n", root: root, path: "Work/A.md") }
                if hazard == "own-edit" { store.changed("Own later writing\n") }
                if hazard == "new" { try write("New note\n", root: root, path: "New.md") }
                if hazard == "draft" { try MacNoteRecoveryStore.checkpoint(root: root, note: XCTUnwrap(store.notes.first), body: "Retained writing", windowID: "cli-setup-test") }
                if hazard == "activation" { await store.openVault(root) }
                do { try await store.commitCLIMetadata(review); XCTFail("Must reject " + hazard) }
                catch {
                    let reason = ["edit": "changed after CLI metadata review", "own-edit": "changed after CLI metadata review", "new": "Notes were added or removed", "draft": "retained note draft", "activation": "vault changed"][hazard]!
                    XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains(reason), error.localizedDescription)
                }
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus/vault.json").path))
                if hazard == "own-edit" { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data("Own later writing\n".utf8)) }
                if hazard != "edit" && hazard != "own-edit" { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), original) }
            }
        }
    }

    func testCLIReadinessIncludesMarkdownExtensionsAndHiddenNotesAndRefusesNoncanonicalIDs() async throws {
        try await withVault { root, store in
            let readyManifest = "{\"version\":1,\"vaultId\":\"36d50b20-5ef7-4e0c-b121-1aacfa26187c\",\"metadataVersion\":1,\"idsRequired\":true,\"future\":42}"
            try write(readyManifest, root: root, path: ".zerus/vault.json")
            for path in ["B.markdown", ".hidden.md", "Work/.secret.MD", ".trash/Old.markdown"] { try write("# Keep " + path + "\n", root: root, path: path) }
            let review = try await store.prepareCLIMetadata()
            XCTAssertTrue(review.issues.isEmpty, review.issues.joined(separator: "\n"))
            XCTAssertEqual(Set(review.notes.map(\.path)), ["Work/A.md", "B.markdown", ".hidden.md", "Work/.secret.MD", ".trash/Old.markdown"])
            XCTAssertEqual(review.changes.first { $0.path == ".zerus/vault.json" }?.after, Data(readyManifest.utf8), "Already-prepared CLI manifests must stay byte-identical")
            try await store.commitCLIMetadata(review)
            for note in review.notes {
                let text = try XCTUnwrap(NoteDocument.decodeUTF8(Data(contentsOf: root.appendingPathComponent(note.path))))
                XCTAssertNotNil(UUID(uuidString: NativeFrontmatter(text).entry("zerus-id")?.value?.display ?? ""))
                XCTAssertEqual(NativeFrontmatter(text).body, note.parts.body)
            }
            let second = try await store.prepareCLIMetadata()
            XCTAssertTrue(second.changes.allSatisfy { $0.before == $0.after })
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("CLI/zerus")
            process.arguments = ["--vault", root.path, "--json", "doctor"]
            process.standardOutput = output; process.standardError = errors
            try process.run(); process.waitUntilExit()
            let diagnostic = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, diagnostic + String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(diagnostic.utf8)) as? [String: Any])
            XCTAssertEqual(result["ok"] as? Bool, true)

        }
        for id in ["36D50B20-5EF7-4E0C-B121-1AACFA26187C", "36d50b205ef74e0cb1211aacfa26187c", "{36d50b20-5ef7-4e0c-b121-1aacfa26187c}", "urn:uuid:36d50b20-5ef7-4e0c-b121-1aacfa26187c"] {
            let source = "---\nzerus-id: '" + id + "'\n---\n# Keep links to this exact ID\n"
            try await withVault(source: source) { root, store in
                let review = try await store.prepareCLIMetadata()
                XCTAssertTrue(review.issues.contains { $0.contains("lowercase hyphenated UUID") }, id)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.utf8))
            }
        }
    }

    func testWritingArrivingDuringMetadataHoldIsRetainedAndBlocksCommit() async throws {
        try await withVault { root, store in
            let review = try await store.prepareCLIMetadata(), original = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
            var arrived = false
            let subscription = store.busyPublisher.sink { busy in
                if busy && store.agentWritingHeld && !arrived { arrived = true; store.changed("Late writing must survive\n") }
            }
            defer { subscription.cancel() }
            do { try await store.commitCLIMetadata(review); XCTFail("Late writing must block setup") }
            catch { XCTAssertTrue(error.localizedDescription.contains("draft is retained"), error.localizedDescription) }
            XCTAssertTrue(arrived); XCTAssertEqual(store.body, "Late writing must survive\n")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), original)
            XCTAssertFalse(try MacNoteRecoveryStore.locations(root: root, path: "Work/A.md").isEmpty)
            XCTAssertFalse(store.busy); XCTAssertFalse(store.agentWritingHeld)
        }
    }

    private func json(_ file: URL) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]) }
    private func write(_ text: String, root: URL, path: String) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
    func testMetadataTransactionKeepsPrivateRecoveryAndRefusesDraftsArrivingAfterReview() async throws {
        for state in ["absent", "clean", "dirty", "unreadable"] {
            try await withVault { root, _ in
                let io = VaultFiles(root: root)
                let review = try await io.cliMetadataReview(workspaceID: UUID())
                let original = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
                let privateRoot = root.deletingLastPathComponent().appendingPathComponent("Zerus-CLI-private-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: privateRoot) }
                let id = UUID(), file = privateRoot.appendingPathComponent("Drafts/" + id.uuidString + ".json")
                let dependency = MacAgentExternalDraftGuard(file: file, id: id, name: "Connected note")
                try dependency.validate(action: "CLI metadata changes")
                // This record arrives after review, as another window could save
                // recovery while the metadata sheet is open.
                var kept: Data?
                if state != "absent" {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let draft = NativeExternalDraft(version: 1, noteID: id, name: "Connected note", baseline: Data("Saved body".utf8), content: state == "dirty" ? "Unsaved body" : "Saved body", updated: Date())
                    kept = state == "unreadable" ? Data("unreadable draft".utf8) : try JSONEncoder().encode(draft)
                    try kept!.write(to: file)
                }
                if state == "dirty" || state == "unreadable" {
                    do { _ = try await io.applyCLIMetadata(review, connected: [dependency]); XCTFail("Recovery must block metadata changes: " + state) }
                    catch { XCTAssertTrue(error.localizedDescription.contains(state == "dirty" ? "recovery draft exists" : "unreadable"), error.localizedDescription) }
                    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), original)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus/vault.json").path))
                } else {
                    _ = try await io.applyCLIMetadata(review, connected: [dependency])
                    let changed = try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8)
                    XCTAssertEqual(NativeFrontmatter(changed).body, "# Original\n\nBody.\n")
                    XCTAssertNotNil(UUID(uuidString: NativeFrontmatter(changed).entry("zerus-id")?.value?.display ?? ""))
                }
                XCTAssertEqual(try FileManager.default.fileExists(atPath: file.path) ? Data(contentsOf: file) : nil, kept, state)
            }
        }
    }
    private func withVault(source: String = "# Original\n\nBody.\n", _ operation: (URL, MacWorkspace) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-CLI-setup-" + UUID().uuidString)
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try write(source, root: root, path: "Work/A.md")
        let store = MacWorkspace(); await store.openVault(root); await store.openNote("Work/A.md")
        defer {
            for note in store.notes {
                for file in (try? MacNoteRecoveryStore.locations(root: root, path: note.path)) ?? [] { try? FileManager.default.removeItem(at: file) }
            }
            defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
            if let directory = store.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            try? FileManager.default.removeItem(at: root)
        }
        let outcome: Result<Void, Error>
        do { try await operation(root, store); outcome = .success(()) } catch { outcome = .failure(error) }
        _ = await store.prepareToCloseWindow()
        try outcome.get()
    }
}
