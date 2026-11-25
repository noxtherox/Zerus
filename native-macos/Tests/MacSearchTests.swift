import XCTest
import CoreText
@testable import Zerus_Native

@MainActor final class MacSearchTests: XCTestCase {
    func testConversationSearchFiltersAndOpensCurrentSharedHistoryWithoutClaimingOwnership() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-chat-search-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults"), workspace = MacWorkspace()
        defer {
            if let directory = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            for key in [MacNavigationState.key(root), "zerus.mac.bookmark." + NativeHistory.hash(root.path), "zerus.mac.search.recent." + NativeHistory.hash(root.path)] { defaults.removeObject(forKey: key) }
            let draft = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/Drafts/Chat/" + NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.absoluteString) + ".json")
            try? FileManager.default.removeItem(at: draft); try? FileManager.default.removeItem(at: root)
        }
        let io = VaultFiles(root: root), owner = MacChatDevice(id: "other-client", name: "Other client"), scope = try MacConversations.data(["kind": "vault"])
        let active = try await io.createConversation(device: owner, text: "Quasar active conversation", scope: scope)
        let archived = try await io.createConversation(device: owner, text: "Quasar archived conversation", scope: scope)
        _ = try await io.changeConversation(archived, device: owner, change: .archive)
        let deleted = try await io.createConversation(device: owner, text: "Quasar deleted conversation", scope: scope)
        _ = try await io.changeConversation(deleted, device: owner, change: .delete)
        let damaged = root.appendingPathComponent(".zerus/chats/incomplete/conversation.json")
        try FileManager.default.createDirectory(at: damaged.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unsupported".utf8).write(to: damaged)
        await workspace.openVault(root)
        let model = MacSearchModel(external: workspace.external.store)
        model.query = "quasar"; model.filters.collection = .chats; await model.rebuild(workspace)
        guard CloudAIFeature.enabled else {
            // Cloud AI is hidden: conversations are neither read nor listed.
            XCTAssertEqual(model.result?.items.count, 0); XCTAssertEqual(model.result?.problems, [])
            model.filters.collection = nil; await model.run()
            XCTAssertFalse(model.result?.items.contains { $0.collection == .chats } ?? true)
            return
        }
        XCTAssertEqual(model.result?.items.map(\.title), ["Quasar active conversation"])
        XCTAssertFalse(try XCTUnwrap(model.result).problems.isEmpty)
        let target = try XCTUnwrap(model.result?.items.first)
        guard case .conversation(let conversation) = target.target else { return XCTFail("Conversation result must retain its opening target") }
        let chat = try await workspace.openSearchConversation(conversation, workspaceID: workspace.workspaceID)
        XCTAssertEqual(chat.selectedID, active.conversation.id); XCTAssertFalse(chat.writable)
        XCTAssertEqual(chat.messages.first?.text, "Quasar active conversation")
        let unchanged = try await io.conversationSnapshot(active.conversation.id)
        XCTAssertEqual(unchanged.records, active.records)
        model.filters.archived = true; await model.run()
        XCTAssertEqual(Set(model.result?.items.map(\.title) ?? []), ["Quasar active conversation", "Quasar archived conversation"])
        do { _ = try await workspace.openSearchConversation(conversation, workspaceID: UUID()); XCTFail("Stale vault result must not open") } catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
        _ = try await io.changeConversation(unchanged, device: owner, change: .delete)
        do { _ = try await workspace.openSearchConversation(conversation, workspaceID: workspace.workspaceID); XCTFail("Newly trashed conversation must not open from stale search") } catch { XCTAssertTrue(error.localizedDescription.contains("Trash")) }
        XCTAssertEqual(try Data(contentsOf: damaged), Data("unsupported".utf8))
    }
    func testWorkspaceSearchIndexesDraftsAndEveryConnectedCollectionWithoutSavingSources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-search-" + UUID().uuidString)
        let privateRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-search-private-" + UUID().uuidString)
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: privateRoot, withIntermediateDirectories: true)
        let workspace = MacWorkspace()
        defer {
            if let directory = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path)); defaults.removeObject(forKey: "zerus.mac.search.recent." + NativeHistory.hash(root.path))
            try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: privateRoot)
        }
        func write(_ path: String, _ value: String) throws {
            let url = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(value.utf8).write(to: url)
        }
        try write("Work/Café plan.md", "---\nzerus-id: cafe\nStatus: Draft\n---\n# Café plan\n\nNebula discoveries.\n")
        try write("Work/Other.md", "# Other\n\nCafe plan in the body.\n")
        try write("Work/Archived.md", "---\nzerus-archived: true\n---\n# Archived nebula\n")
        try write(".trash/Hidden.md", "# Hidden nebula\n")
        try write(".zerus/links/Reference.md", "---\nzerus-link-id: link\nzerus-link-url: https://example.com/nebula\n---\n# Nebula reference\n")
        try write("assets/nebula.txt", "Not implicitly extracted")
        try write(".zerus/tasks.json", #"{"tasks":[{"id":"research","title":"Review nebula","priority":"high","completed":true,"createdAt":"2020-01-01T00:00:00Z"}]}"#)
        await workspace.openVault(root)
        await workspace.openNote("Work/Café plan.md")
        let noteBytes = try Data(contentsOf: root.appendingPathComponent("Work/Café plan.md"))
        // An in-memory native draft is indexed without waiting for its autosave.
        workspace.body += "\nUnsaved pulsar"
        let external = NativeExternalNotesStore(directory: privateRoot.appendingPathComponent("registry"))
        let original = privateRoot.appendingPathComponent("External.md")
        try Data("# Outside research\n\nExternal nebula body.\n".utf8).write(to: original)
        let snapshot = try await external.open(selected: original), originalBytes = try Data(contentsOf: original)
        let model = MacSearchModel(external: external)
        model.query = "cafe plan"; await model.rebuild(workspace)
        XCTAssertEqual(model.result?.items.first?.title, "Café plan")
        model.query = "discovreies"; await model.run()
        XCTAssertEqual(model.result?.items.map(\.title), ["Café plan"])
        model.query = "pulsar"; await model.run()
        XCTAssertEqual(model.result?.items.first?.draft, true)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Café plan.md")), noteBytes)
        model.query = "nebula"; await model.run()
        XCTAssertEqual(Set(model.result?.items.map(\.collection) ?? []), [.notes, .links, .files, .tasks, .external])
        XCTAssertFalse(model.result?.items.contains { $0.title == "Hidden nebula" || $0.title == "Archived nebula" } ?? true)
        model.filters = .init(collection: .tasks, status: "completed", priority: "high"); await model.run()
        XCTAssertEqual(model.result?.items.map(\.title), ["Review nebula"])
        model.filters = .init(collection: .notes, property: "Status", value: "Draft"); model.query = ""; await model.run()
        XCTAssertEqual(model.result?.items.map(\.title), ["Café plan"])
        let draft = NativeExternalDraft(version: 1, noteID: snapshot.entry.id, name: snapshot.entry.name, baseline: snapshot.bytes, content: "# Kept external\n\nUnavailable quasar draft.\n", updated: Date())
        try await external.keepDraft(draft, replacing: nil)
        try FileManager.default.copyItem(at: original, to: privateRoot.appendingPathComponent("Preserved.md"))
        try FileManager.default.removeItem(at: original)
        model.filters = .init(collection: .external); model.query = "quasar"; await model.rebuild(workspace)
        XCTAssertEqual(model.result?.items.first?.title, "Kept external"); XCTAssertEqual(model.result?.items.first?.draft, true); XCTAssertNotNil(model.result?.items.first?.issue)
        XCTAssertEqual(try Data(contentsOf: privateRoot.appendingPathComponent("Preserved.md")), originalBytes)
    }

    func testFileContentsSearchFindsPDFUnicodeTextAndKeepsNamesForUnavailableInputsThenRefreshes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-file-search-" + UUID().uuidString)
        let privateRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-file-search-private-" + UUID().uuidString)
        let workspace = MacWorkspace(), defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Reports"), withIntermediateDirectories: true)
        defer {
            if let directory = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            for key in [MacNavigationState.key(root), "zerus.mac.bookmark." + NativeHistory.hash(root.path), "zerus.mac.search.recent." + NativeHistory.hash(root.path)] { defaults.removeObject(forKey: key) }
            try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: privateRoot)
        }
        var inputs: [String: Data] = [
            "Reports/Log.txt": Data([0xff, 0xfe]) + "Café violetquasar is inside this UTF-16 document.\n".data(using: .utf16LittleEndian)!,
            "Reports/Archive.zip": Data([0x50, 0x4b, 0, 1]),
            "Reports/Broken.txt": Data([0xc3, 0x28]),
            "Reports/Limit.txt": Data(repeating: 65, count: 2 * 1024 * 1024 + 1),
            "Hub.md": Data("---\nzerus-id: hub\nzerus-file-id: file-hub\nzerus-file-name: Source\nzerus-file-kind: vault\nzerus-file-path: Reports/Log.txt\n---\n# Hub\n\nVioletquasar reference.\n".utf8)
        ]
        let pdf = NSMutableData(), consumer = try XCTUnwrap(CGDataConsumer(data: pdf))
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil)); context.beginPDFPage(nil); context.textPosition = CGPoint(x: 30, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "PDF violetquasar independent evidence", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)])), context)
        context.endPDFPage(); context.closePDF(); inputs["Reports/Reference.pdf"] = pdf as Data
        for (path, bytes) in inputs { try bytes.write(to: root.appendingPathComponent(path)) }
        let oversize = root.appendingPathComponent("Reports/Large.pdf"); FileManager.default.createFile(atPath: oversize.path, contents: Data())
        let handle = try FileHandle(forWritingTo: oversize); try handle.truncate(atOffset: 20 * 1024 * 1024 + 1); try handle.close()
        let external = NativeExternalNotesStore(directory: privateRoot)
        await workspace.openVault(root)
        let model = MacSearchModel(external: external); model.filters.collection = .files; model.query = "violetquasar"; await model.rebuild(workspace)
        XCTAssertEqual(Set(model.result?.items.map(\.title) ?? []), ["Log.txt", "Reference.pdf", "Hub"])
        let text = try XCTUnwrap(model.result?.items.first { $0.title == "Log.txt" }); XCTAssertTrue(NativeSearch.excerpt(text, query: "violetquasar").contains("Café violetquasar"))
        XCTAssertEqual(model.filesLoading, false)
        model.query = "cafe"; await model.run(); XCTAssertEqual(model.result?.items.map(\.title), ["Log.txt"])
        model.query = ""; model.filters.folder = "Reports"; await model.run()
        for name in ["Archive.zip", "Broken.txt", "Limit.txt", "Large.pdf"] {
            let item = try XCTUnwrap(model.result?.items.first { $0.title == name }); XCTAssertFalse(item.issue?.isEmpty ?? true, name)
        }
        for (path, bytes) in inputs { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), bytes) }
        let request = try await workspace.searchChatRequest(query: "What does it say?", item: text, workspaceID: workspace.workspaceID)
        XCTAssertEqual(request.documents.first?.text, "Café violetquasar is inside this UTF-16 document.\n")
        try Data("Replacement cometvector text.\n".utf8).write(to: root.appendingPathComponent("Reports/Log.txt"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Reports/Reference.pdf"))
        await workspace.refresh(); model.query = "violetquasar"; await model.rebuild(workspace)
        XCTAssertTrue(model.result?.items.isEmpty == true)
        model.query = "cometvector"; await model.run(); XCTAssertEqual(model.result?.items.map(\.title), ["Log.txt"])
        let stale = NativeSearchEngine()
        let sources = workspace.searchSources(); try await stale.rebuild(sources, supplement: .init(files: [], conversations: [], problems: []))
        do { try await stale.replaceFiles([.init(path: "Wrong.txt", modified: Date(), content: "secret", issue: nil)], workspace: UUID()); XCTFail("Old workspace indexing must not replace current files") } catch is CancellationError {}
    }

    func testSearchNavigationFollowsStableIdentityAndRejectsAmbiguousOrStaleResults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-search-navigation-" + UUID().uuidString)
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let workspace = MacWorkspace()
        defer { if let directory = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }; defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path)); try? FileManager.default.removeItem(at: root) }
        let content = Data("---\nzerus-id: stable\n---\n# Target\n".utf8)
        try content.write(to: root.appendingPathComponent("Old.md"))
        await workspace.openVault(root); let origin = workspace.workspaceID
        try FileManager.default.moveItem(at: root.appendingPathComponent("Old.md"), to: root.appendingPathComponent("Moved.md"))
        try await workspace.openSearchNote(path: "Old.md", stableID: "stable", workspaceID: origin)
        XCTAssertEqual(workspace.selection, "Moved.md")
        try content.write(to: root.appendingPathComponent("Duplicate.md"))
        do { try await workspace.openSearchNote(path: "Old.md", stableID: "stable", workspaceID: origin); XCTFail("Ambiguous IDs must not choose an arbitrary note") } catch { XCTAssertTrue(error.localizedDescription.contains("result changed")) }
        do { try await workspace.openSearchNote(path: "Moved.md", stableID: "stable", workspaceID: UUID()); XCTFail("Old workspace results must not navigate") } catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
        do { _ = try await workspace.searchFile("../outside.txt", workspaceID: origin); XCTFail("Unindexed file paths must not resolve") } catch { XCTAssertTrue(error.localizedDescription.contains("file or vault changed")) }
    }
}
