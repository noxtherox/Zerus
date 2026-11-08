import XCTest
import CryptoKit
@testable import ZerusNative

final class NativeSearchTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root); let directory = NativeChat.directory(for: root); if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) } }
    private func write(_ path: String, _ bytes: Data) throws { let url = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try bytes.write(to: url) }
    private func json(_ path: String, _ value: Any) throws { try write(path, JSONSerialization.data(withJSONObject: value, options: .sortedKeys)) }

    @MainActor
    func testVaultSearchRanksBodyAndAccentsFiltersPropertiesAndIncludesTasksFilesLinksAndDrafts() async throws {
        try write("Research/Café plan.md", Data("---\nzerus-id: cafe\nstatus: Ready\nscore: 42.00\nactive: true\ntags: [Swift, iOS]\n---\n# Café plan\n\nNebula discoveries [[Target|Readable alias]]. [**bold** `code` label](#zerus-note:zerus%3Aprivate-id%7Cbold%20code%20label) [website](https://example.com/a_(b)).\n".utf8))
        try write("Other/Cafe planning.md", Data("# Cafe planning\n\nSupporting research".utf8))
        try write("Other/Body.md", Data("# Body\n\nCafe plan in prose.".utf8))
        try write("Other/Archived.md", Data("---\nzerus-archived: true\n---\n# Archived nebula".utf8))
        try write(".trash/Hidden.md", Data("# Hidden nebula".utf8))
        try write("assets/nebula.pdf", Data("File content is not implicitly extracted".utf8))
        try write(".zerus/links/nebula.md", Data("---\nzerus-link-id: saved\nzerus-link-url: https://example.com/nebula\n---\n# Nebula reference\n\nhttps://example.com/nebula\n\nA saved page".utf8))
        try json(".zerus/tasks.json", ["tasks": [["id": "task", "title": "Review nebula", "completed": true, "completedAt": "2020-01-01T00:00:00Z", "priority": "high", "createdAt": "2020-01-01T00:00:00Z"]]])
        let store = VaultStore(); await store.open(root)
        let note = try XCTUnwrap(store.notes.first { $0.stableID == "cafe" }), session = try XCTUnwrap(store.session(for: note))
        session.document.content += "\nUnsaved pulsar"; session.dirty = true
        let worker = VaultFiles(root: root), engine = NativeSearchEngine(), source = store.searchSources()
        let supplement = try await worker.searchSupplement(files: store.files, liveConversation: nil)
        try await engine.rebuild(source, supplement: supplement)
        let ranked = try await engine.search(workspace: store.workspaceID, query: "cafe plan", filters: .init(), recent: [])
        XCTAssertEqual(ranked.items.prefix(3).map(\.title), ["Café plan", "Cafe planning", "Body"])
        XCTAssertEqual(ranked.items.first?.id, "note-id:cafe")
        XCTAssertTrue(ranked.items.first?.preview.contains("Readable alias.") == true)
        XCTAssertFalse(ranked.items.first?.preview.contains("Readable aliasTarget") == true)
        XCTAssertTrue(ranked.items.first?.preview.contains("bold code label website.") == true)
        XCTAssertFalse(ranked.items.first?.preview.contains("#zerus-note:") == true)
        let destination = try await engine.search(workspace: store.workspaceID, query: "private-id", filters: .init(), recent: [])
        XCTAssertEqual(destination.items.map(\.title), ["Café plan"], "Readable excerpts must not remove original destinations from the search index")
        let stored = try await worker.read(note.path)
        XCTAssertEqual(stored, Data(note.content.utf8), "Indexing and previewing a draft must not save it")
        let fuzzy = try await engine.search(workspace: store.workspaceID, query: "discovreies", filters: .init(), recent: [])
        XCTAssertEqual(fuzzy.items.map(\.title), ["Café plan"])
        let short = try await engine.search(workspace: store.workspaceID, query: "cfe", filters: .init(), recent: [])
        XCTAssertTrue(short.items.isEmpty, "Short words must not use fuzzy matching")
        let draft = try await engine.search(workspace: store.workspaceID, query: "pulsar", filters: .init(), recent: [])
        XCTAssertEqual(draft.items.first?.draft, true)
        for (key, value) in [("status", "ready"), ("score", "42"), ("active", "true"), ("tags", "ios")] {
            var filters = NativeSearchFilters(); filters.property = key; filters.value = value
            let result = try await engine.search(workspace: store.workspaceID, query: "", filters: filters, recent: [])
            XCTAssertEqual(result.items.map(\.title), ["Café plan"], key)
        }
        let all = try await engine.search(workspace: store.workspaceID, query: "nebula", filters: .init(), recent: [])
        XCTAssertEqual(Set(all.items.map(\.collection)), [.notes, .tasks, .links, .files]); XCTAssertFalse(all.items.contains { $0.title == "Hidden nebula" || $0.archived })
        var filters = NativeSearchFilters(); filters.collection = .tasks; filters.status = "completed"; filters.priority = "high"
        let tasks = try await engine.search(workspace: store.workspaceID, query: "nebula", filters: filters, recent: [])
        XCTAssertEqual(tasks.items.map(\.id), ["task:task"], "Search includes completed tasks older than the task timeline")
        filters = .init(); filters.archived = true
        let archived = try await engine.search(workspace: store.workspaceID, query: "nebula", filters: filters, recent: [])
        XCTAssertTrue(archived.items.contains { $0.archived })
        filters = .init(); filters.folder = "Research"
        let folder = try await engine.search(workspace: store.workspaceID, query: "", filters: filters, recent: [])
        XCTAssertEqual(folder.items.map(\.title), ["Café plan"])
        filters = .init(); filters.days = 1
        let aged = try await engine.search(workspace: store.workspaceID, query: "nebula", filters: filters, recent: [], now: Date().addingTimeInterval(3 * 86400))
        XCTAssertTrue(aged.items.isEmpty)
        let recent = try await engine.search(workspace: store.workspaceID, query: "", filters: .init(), recent: ["task:task", "note-id:cafe", "missing"], limit: 1)
        XCTAssertEqual(recent.total, 2); XCTAssertEqual(recent.items.map(\.id), ["task:task"])
        do { _ = try await engine.search(workspace: UUID(), query: "nebula", filters: .init(), recent: []); XCTFail("A query must not return another workspace's index") } catch is CancellationError {}
    }

    func testSharedConversationProtocolOwnershipAmendmentsTombstonesAndPrivateVaultIsolationAreReadOnly() async throws {
        func event(_ id: String, _ kind: String, device: String = "owner", generation: Int = 1, fields: [String: Any] = [:]) -> [String: Any] {
            var value: [String: Any] = ["version": 1, "id": id, "conversationId": "shared", "at": "2026-11-05T12:00:00Z", "deviceId": device, "ownerGeneration": generation, "kind": kind]
            value.merge(fields) { _, new in new }; return value
        }
        let prefix = ".zerus/chats/shared"
        try json(prefix + "/conversation.json", ["version": 1, "id": "shared", "createdAt": "2026-11-01T00:00:00Z"])
        let events: [[String: Any]] = [
            event("001", "ownership", fields: ["owner": ["id": "loser", "name": "Old"]]),
            event("002", "ownership", fields: ["owner": ["id": "owner", "name": "Current"]]),
            event("010", "message", device: "other", fields: ["message": ["id": "u", "turnId": "turn", "role": "user", "text": "Old question", "createdAt": "2026-11-05T12:00:00Z"]]),
            event("011", "message", fields: ["message": ["id": "a", "turnId": "turn", "role": "assistant", "text": "Answer nebula", "createdAt": "2026-11-05T12:00:00Z"]]),
            event("012", "message", fields: ["message": ["id": "u", "turnId": "turn", "role": "user", "text": "Amended question", "createdAt": "2026-11-05T12:00:00Z"]]),
            event("020", "rename", fields: ["title": "Chosen title"]), event("021", "rename", device: "loser", fields: ["title": "Unauthorized title"]), event("022", "delete", device: "loser"), event("023", "archive")]
        for value in events { try json(prefix + "/events/" + (value["id"] as! String) + ".json", value) }
        let privateRoot = NativeChat.directory(for: root)
        try FileManager.default.createDirectory(at: privateRoot.appendingPathComponent("Previous"), withIntermediateDirectories: true)
        let privateBytes = try JSONEncoder().encode([ChatMessage(role: "user", content: "Only in this vault")])
        try privateBytes.write(to: privateRoot.appendingPathComponent("current.json")); try privateBytes.write(to: privateRoot.appendingPathComponent("Previous/one.json"))
        let unrelated = root.appendingPathComponent("OtherVault"), unrelatedDirectory = NativeChat.directory(for: unrelated)
        try FileManager.default.createDirectory(at: unrelatedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unrelatedDirectory) }
        try JSONEncoder().encode([ChatMessage(role: "user", content: "Secret other vault")]).write(to: unrelatedDirectory.appendingPathComponent("current.json"))
        // A cloud folder or linked history that cannot be read must not disable
        // ordinary note/file search or cross the original vault boundary.
        let isolated = root.appendingPathComponent("LinkedVault")
        try FileManager.default.createDirectory(at: isolated.appendingPathComponent(".zerus"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: isolated.appendingPathComponent(".zerus/chats"), withDestinationURL: root.appendingPathComponent(".zerus/chats"))
        let unavailable = try await VaultFiles(root: isolated).searchSupplement(files: [], liveConversation: nil)
        XCTAssertFalse(unavailable.problems.isEmpty); XCTAssertTrue(unavailable.conversations.isEmpty)
        let before = try Data(contentsOf: root.appendingPathComponent(prefix + "/events/012.json"))
        let worker = VaultFiles(root: root)
        var result = try await worker.searchSupplement(files: [], liveConversation: nil)
        let shared = try XCTUnwrap(result.conversations.first { $0.id == "shared:shared" })
        XCTAssertEqual(shared.title, "Chosen title"); XCTAssertTrue(shared.archived)
        XCTAssertEqual(shared.messages.map(\.content), ["Amended question", "Answer nebula"])
        XCTAssertEqual(result.conversations.filter { $0.text.contains("Only in this vault") }.count, 2)
        XCTAssertFalse(result.conversations.contains { $0.text.contains("Secret other vault") })
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(prefix + "/events/012.json")), before)
        try json(prefix + "/events/024.json", event("024", "restore"))
        result = try await worker.searchSupplement(files: [], liveConversation: nil)
        XCTAssertEqual(result.conversations.first { $0.id == "shared:shared" }?.archived, false)
        try json(prefix + "/events/025.json", event("025", "future-lifecycle"))
        result = try await worker.searchSupplement(files: [], liveConversation: nil)
        XCTAssertFalse(result.conversations.contains { $0.id == "shared:shared" }); XCTAssertFalse(result.problems.isEmpty)
        XCTAssertEqual(result.conversations.count, 2, "Unavailable shared history must not hide readable private conversations")
        try FileManager.default.removeItem(at: root.appendingPathComponent(prefix + "/events/025.json"))
        try json(".zerus/chat-tombstones/shared.json", ["version": 1])
        result = try await worker.searchSupplement(files: [], liveConversation: nil)
        XCTAssertFalse(result.conversations.contains { $0.id == "shared:shared" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(prefix + "/conversation.json").path))
    }

    @MainActor
    func testSearchModelVaultSwitchAndRecentVisitsDoNotLeakAcrossWorkspaceActivations() async throws {
        let firstRoot = root.appendingPathComponent("A"), second = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        // Matching identities make a leaked B visit visible in A, so the test
        // cannot pass merely because different paths filtered the visit out.
        try Data("---\nzerus-id: common\n---\n# Alpha nebula\n".utf8).write(to: firstRoot.appendingPathComponent("Same.md"))
        try Data("---\nzerus-id: common\n---\n# Beta pulsar\n".utf8).write(to: second.appendingPathComponent("Same.md"))
        let externalRoot = firstRoot.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalRoot) }
        let externalURL = externalRoot.appendingPathComponent("Global.md"), externalBytes = Data("# Shared satellite\n\nConnected across vaults.".utf8)
        try externalBytes.write(to: externalURL)
        let external = NativeExternalNotesModel(directory: externalRoot.appendingPathComponent("Private"))
        let externalSession = try await external.open(externalURL); await external.refreshSearchIndex()
        let store = VaultStore(), model = NativeSearchModel()
        await store.open(firstRoot); let first = store.workspaceID
        model.search(query: "nebula", filters: .init()); model.rebuild(vault: store, external: external.searchRecords)
        await store.open(second); model.search(query: "pulsar", filters: .init()); model.rebuild(vault: store, external: external.searchRecords)
        for _ in 0..<100 { if !model.loading { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.result?.workspaceID, store.workspaceID); XCTAssertNotEqual(model.result?.workspaceID, first)
        XCTAssertEqual(model.result?.items.map(\.title), ["Beta pulsar"])
        model.visited(try XCTUnwrap(model.result?.items.first))
        model.search(query: "satellite", filters: .init())
        for _ in 0..<100 { if !model.loading { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.result?.items.map(\.id), ["external:" + externalSession.id.uuidString])
        try await external.forget(externalSession.snapshot.entry)
        model.updateExternal(external.searchRecords); model.search(query: "satellite", filters: .init())
        for _ in 0..<100 { if !model.loading { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(model.result?.items.isEmpty == true, "A replacement external index must remove forgotten results rather than publish an older query")
        XCTAssertEqual(try Data(contentsOf: externalURL), externalBytes)
        await store.open(firstRoot); model.search(query: "", filters: .init()); model.rebuild(vault: store)
        for _ in 0..<100 { if !model.loading { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(model.result?.items.isEmpty == true, "A recent visit in B cannot appear in A after switching back")
        model.clearRecent()
    }

    @MainActor
    func testRecentVisitsMigrateAcrossSavedVaultRelocationAndClearWithoutLeakingToReusedPaths() async throws {
        let current = root.appendingPathComponent("Current", isDirectory: true)
        let previous = root.appendingPathComponent("Previous container", isDirectory: true)
        let relocated = root.appendingPathComponent("Relocated", isDirectory: true)
        let ambiguous = root.appendingPathComponent("Unclaimed legacy path", isDirectory: true)
        let originals = ["First.md": Data("---\nzerus-id: common\n---\n# First\nOriginal first.".utf8),
                         "Second.md": Data("---\nzerus-id: second\n---\n# Second\nOriginal second.".utf8)]
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        for (name, bytes) in originals { try bytes.write(to: current.appendingPathComponent(name)) }
        func legacyKey(_ url: URL) -> String {
            "zerus.native.search.recent." + SHA256.hash(data: Data(url.standardizedFileURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        func savedLocation(_ id: UUID, recorded: URL, bookmark: URL) throws {
            var registry = try JSONSerialization.jsonObject(with: XCTUnwrap(UserDefaults.standard.data(forKey: NativeVaultRegistry.key))) as! [String: Any]
            var entries = registry["entries"] as! [[String: Any]]
            let index = try XCTUnwrap(entries.firstIndex { $0["id"] as? String == id.uuidString })
            // A system-renewed bookmark can resolve in a new container while
            // the persisted last-opened location still spells the old one.
            entries[index]["location"] = recorded.standardizedFileURL.absoluteString
            entries[index]["bookmark"] = try bookmark.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil).base64EncodedString()
            registry["entries"] = entries
            UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: registry), forKey: NativeVaultRegistry.key)
        }
        func recents(_ vault: VaultStore) async throws -> NativeSearchModel {
            let model = NativeSearchModel(); model.search(query: "", filters: .init()); model.rebuild(vault: vault)
            for _ in 0..<150 { if !model.loading { break }; try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertFalse(model.loading); XCTAssertNil(model.problem)
            XCTAssertEqual(try XCTUnwrap(model.result).workspaceID, vault.workspaceID)
            return model
        }
        let initial = VaultStore(); await initial.open(current)
        let id = try XCTUnwrap(initial.activeVaultID)
        try savedLocation(id, recorded: previous, bookmark: current)
        // These are the legacy persisted format, not a receipt supplied to
        // the model: current visits precede older visits and duplicates coalesce.
        let currentLegacy = legacyKey(current), previousLegacy = legacyKey(previous)
        UserDefaults.standard.set(["note-id:second"], forKey: currentLegacy)
        UserDefaults.standard.set(["note-id:common", "note-id:second", "note-id:common"], forKey: previousLegacy)
        let reopened = VaultStore(); await reopened.openSavedVault(id)
        XCTAssertEqual(reopened.activeVaultID, id); XCTAssertEqual(reopened.notes.count, 2)
        let migrated = try await recents(reopened)
        XCTAssertEqual(migrated.result?.items.map(\.id), ["note-id:second", "note-id:common"], "The previous install's visits must survive renewal of the same saved vault")
        // Retry a partially completed migration: the model produced the new
        // saved list, but its earlier path-keyed source was not retired yet.
        UserDefaults.standard.set(["note-id:common"], forKey: currentLegacy)
        // Exercise a second changed root with the same registration and a new
        // model instance, rather than retaining an in-memory Recent list.
        try FileManager.default.copyItem(at: current, to: relocated)
        try savedLocation(id, recorded: current, bookmark: relocated)
        let moved = VaultStore(); await moved.openSavedVault(id)
        XCTAssertEqual(moved.activeVaultID, id); XCTAssertEqual(moved.root?.standardizedFileURL, relocated.standardizedFileURL)
        let restored = try await recents(moved)
        XCTAssertEqual(restored.result?.items.map(\.id), ["note-id:second", "note-id:common"])
        restored.clearRecent()
        let cleared = try await recents(moved)
        XCTAssertTrue(cleared.result?.items.isEmpty == true, "Clearing must survive recreation without importing the legacy visits again")
        // Reusing a previous path with matching note IDs must not inherit the
        // migrated vault's visits. Matching IDs make an accidental import visible.
        let reused = VaultStore(); await reused.open(current)
        XCTAssertNotEqual(reused.activeVaultID, id)
        let independent = try await recents(reused)
        XCTAssertTrue(independent.result?.items.isEmpty == true)
        // A still-unclaimed legacy key at a location recorded by a different
        // saved identity is ambiguous. Preserve it instead of assigning it to
        // a newly opened vault at that path.
        try FileManager.default.copyItem(at: current, to: ambiguous)
        try savedLocation(id, recorded: ambiguous, bookmark: relocated)
        let ambiguousKey = legacyKey(ambiguous), unclaimed = ["note-id:common"]
        UserDefaults.standard.set(unclaimed, forKey: ambiguousKey)
        let unrelated = VaultStore(); await unrelated.open(ambiguous)
        XCTAssertNotEqual(unrelated.activeVaultID, id)
        let isolated = try await recents(unrelated)
        XCTAssertTrue(isolated.result?.items.isEmpty == true, "An older path record for another saved vault must never leak matching note IDs")
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: ambiguousKey), unclaimed)
        for directory in [current, relocated, ambiguous] {
            for (name, bytes) in originals { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), bytes) }
        }
    }
}
