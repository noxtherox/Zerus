import XCTest
@testable import Zerus_Native

@MainActor final class MacSearchChatTests: XCTestCase {
    func testSearchQuestionPreservesBothDraftsAttachmentsAndDurableExactNoteContext() async throws {
        try await fixture { root, workspace in
            let chosen = root.appendingPathComponent("Chosen.md"), original = Data("---\nzerus-id: chosen\n---\n# Chosen\nDisk text.\n".utf8)
            try original.write(to: chosen); try Data("# Other\nPrivate other note.\n".utf8).write(to: root.appendingPathComponent("Other.md"))
            await workspace.openVault(root); await workspace.openNote("Chosen.md"); workspace.body = "# Chosen\nUnsent selected evidence."
            let model = MacSearchModel(external: workspace.external.store); model.query = "Chosen"; await model.rebuild(workspace)
            let item = try XCTUnwrap(model.result?.items.first), origin = workspace.workspaceID
            let request = try await workspace.searchChatRequest(query: "What should I do next?", item: item, workspaceID: origin)
            XCTAssertEqual(request.notes, ["Chosen.md"]); XCTAssertTrue(request.documents.isEmpty)
            XCTAssertTrue(workspace.searchSources().notes.first { $0.path == "Chosen.md" }?.content.contains("Unsent selected evidence.") == true)
            XCTAssertEqual(try Data(contentsOf: chosen), original, "Preparing context must not save the note")
            let device = MacChatDevice(id: "search-test", name: "Search test"), io = VaultFiles(root: root)
            let existing = try await io.createConversation(device: device, text: "Previously saved question", scope: MacConversations.data(["kind": "vault"]))
            let chat = MacChatController(root: root, device: device), image = try makeChatTestImage(in: root)
            chat.draft = "Existing new-question draft"
            try chat.addAttachments(images: [image], documents: [.init(id: UUID().uuidString.lowercased(), name: "Kept.txt", text: "Kept unsent file")]); try chat.setContextReferences(MacChatNoteReference.capture(["Other.md"], notes: workspace.notes))
            try await chat.select(existing.conversation.id); chat.draft = "Unsent existing-conversation question"; try chat.setContextReferences(MacChatNoteReference.capture(["Other.md"], notes: workspace.notes))
            let stale = MacChatController(root: root, device: device)
            XCTAssertTrue(try chat.prepareSearchQuestion(request))
            XCTAssertNil(chat.selectedID); XCTAssertEqual(chat.draft, "Existing new-question draft\n\nWhat should I do next?")
            let restored = MacChatController(root: root, device: device)
            XCTAssertEqual(restored.contextPaths, ["Chosen.md"]); XCTAssertEqual(restored.selectedImages.first?.bytes, image.bytes); XCTAssertEqual(restored.selectedDocuments.first?.text, "Kept unsent file")
            XCTAssertThrowsError(try stale.prepareSearchQuestion(request), "A stale window must not replace a newer handoff")
            try restored.setContextReferences([])
            XCTAssertEqual(MacChatController(root: root, device: device).contextPaths, [], "Explicitly no note context must survive reopening")
            try await restored.select(existing.conversation.id)
            XCTAssertEqual(restored.draft, "Unsent existing-conversation question"); XCTAssertEqual(restored.contextPaths, ["Other.md"])
            let unchanged = try await io.conversationSnapshot(existing.conversation.id)
            XCTAssertEqual(unchanged.records, existing.records); XCTAssertEqual(try Data(contentsOf: chosen), original)
            let all = try await io.conversations(); XCTAssertEqual(all.conversations.count, 1, "Ask prepares a private draft; Send creates portable events")
        }
    }
    func testSearchContextRevalidatesMovedNotesConversationsAndCompleteFileSnapshots() async throws {
        try await fixture { root, workspace in
            let content = Data("---\nzerus-id: moving\n---\n# Moving\n".utf8), old = root.appendingPathComponent("Old.md")
            try content.write(to: old)
            let full = String(repeating: "Reference paragraph.\n", count: 1500) + "End-of-document decision: approved."
            try Data(full.utf8).write(to: root.appendingPathComponent("Evidence.txt"))
            await workspace.openVault(root)
            let model = MacSearchModel(external: workspace.external.store); model.query = "Moving"; await model.rebuild(workspace)
            let item = try XCTUnwrap(model.result?.items.first), origin = workspace.workspaceID
            try FileManager.default.moveItem(at: old, to: root.appendingPathComponent("Moved.md"))
            let moved = try await workspace.searchChatRequest(query: "Explain moving", item: item, workspaceID: origin)
            XCTAssertEqual(moved.notes, ["Moved.md"])
            try content.write(to: root.appendingPathComponent("Duplicate.md"))
            do { _ = try await workspace.searchChatRequest(query: "Explain moving", item: item, workspaceID: origin); XCTFail("Duplicate stable identities require review") } catch {}
            do { _ = try await workspace.searchChatRequest(query: "Old vault", item: nil, workspaceID: UUID()); XCTFail("Stale workspace must not prepare context") } catch {}
            model.query = "Evidence"; await model.rebuild(workspace)
            let file = try XCTUnwrap(model.result?.items.first { if case .file = $0.target { return true }; return false })
            let request = try await workspace.searchChatRequest(query: "What is the decision?", item: file, workspaceID: origin)
            XCTAssertEqual(request.documents.first?.text, full); XCTAssertTrue(request.notes.isEmpty)
            let owner = MacChatDevice(id: "other", name: "Other"), io = VaultFiles(root: root)
            let saved = try await io.createConversation(device: owner, text: "Current actual conversation text", scope: MacConversations.data(["kind": "vault"]))
            let reference = NativeSearchConversation(id: "shared:" + saved.conversation.id, title: "Old title", modified: Date(), archived: false, messages: [ChatMessage(role: "user", content: "Stale index text")], origin: .shared(saved.conversation.id))
            let row = NativeSearchItem(id: "chat:" + reference.id, collection: .chats, title: reference.title, text: reference.text, location: "AI conversations", modified: Date(), target: .conversation(reference))
            let renamed = try await io.changeConversation(saved, device: owner, change: .rename("Current title"))
            let context = try await workspace.searchChatRequest(query: "Explain conversation", item: row, workspaceID: origin)
            XCTAssertEqual(context.documents.first?.name, "Current title (conversation text)"); XCTAssertEqual(context.documents.first?.text, "user: Current actual conversation text")
            _ = try await io.changeConversation(renamed, device: owner, change: .delete)
            do { _ = try await workspace.searchChatRequest(query: "Explain conversation", item: row, workspaceID: origin); XCTFail("Newly trashed conversation must not be shared") } catch {}
            let noContext = try await workspace.searchChatRequest(query: "Question only", item: nil, workspaceID: origin)
            XCTAssertTrue(noContext.notes.isEmpty); XCTAssertTrue(noContext.documents.isEmpty); XCTAssertTrue(noContext.images.isEmpty)
        }
    }
    func testExternalSearchContextKeepsFullRecoveryDraftWhenOriginalIsUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-search-external-context-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let store = NativeExternalNotesStore(directory: root.appendingPathComponent("Private")), original = root.appendingPathComponent("Original.md")
        try Data("# Original\nSaved text.\n".utf8).write(to: original)
        let snapshot = try await store.open(selected: original), bytes = try Data(contentsOf: original)
        let full = "# Recovery draft\n" + String(repeating: "Unsaved evidence.\n", count: 1500) + "Final recovery decision."
        try await store.keepDraft(.init(version: 1, noteID: snapshot.entry.id, name: snapshot.entry.name, baseline: snapshot.bytes, content: full, updated: Date()), replacing: nil)
        try FileManager.default.moveItem(at: original, to: root.appendingPathComponent("Preserved.md"))
        let context = try await MacSearchContext.external(id: snapshot.entry.id, store: store, live: nil)
        XCTAssertEqual(context.text, full); XCTAssertTrue(context.name.contains("(draft)")); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Preserved.md")), bytes)
        let kept = try await store.draft(snapshot.entry.id)
        try await store.keepDraft(.init(version: 1, noteID: snapshot.entry.id, name: snapshot.entry.name, baseline: snapshot.bytes, content: snapshot.content, updated: Date()), replacing: kept)
        try await store.forget(snapshot.entry.id)
        do { _ = try await MacSearchContext.external(id: snapshot.entry.id, store: store, live: nil); XCTFail("Removed external connection must not share an old snapshot") } catch {}
    }
    func testSavedContextFollowsRenamedIdentityWithoutSharingItsReplacementPath() async throws {
        try await fixture { root, workspace in
            let original = Data("---\nzerus-id: original-context\n---\n# Original context\nOriginal disk evidence.\n".utf8)
            let replacement = Data("---\nzerus-id: replacement-context\n---\n# Replacement context\nUnrelated replacement text.\n".utf8)
            let old = root.appendingPathComponent("Selected.md"), moved = root.appendingPathComponent("Renamed.md")
            try original.write(to: old); await workspace.openVault(root); await workspace.openNote("Selected.md")
            workspace.body = "# Original context\nUnsaved original evidence."
            let device = MacChatDevice(id: "context-test", name: "Context test"), chat = MacChatController(root: root, device: device)
            chat.draft = "Keep this unsent question"
            try chat.setContextReferences(MacChatNoteReference.capture(["Selected.md"], notes: workspace.notes))
            try FileManager.default.moveItem(at: old, to: moved); try replacement.write(to: old)
            let indexed = try NativeSearch.items(workspace.searchSources(), supplement: .init(files: [], conversations: [], problems: []))
            let selected = try XCTUnwrap(indexed.first { if case .note(_, let id) = $0.target { return id == "original-context" }; return false })
            let handoff = try await workspace.searchChatRequest(query: "Keep the original context", item: selected, workspaceID: workspace.workspaceID)
            XCTAssertEqual(handoff.notes, ["Renamed.md"]); XCTAssertEqual(handoff.references.first?.noteID, "original-context")
            let reopened = MacChatController(root: root, device: device), fresh = try await workspace.chatContextSnapshot()
            let sources = try reopened.resolveNoteContext(fresh)
            XCTAssertEqual(sources.map(\.noteID), ["original-context"])
            XCTAssertEqual(sources.first?.content, "---\nzerus-id: original-context\n---\n# Original context\nUnsaved original evidence.")
            XCTAssertEqual(reopened.contextPaths, ["Renamed.md"])
            XCTAssertEqual(MacChatController(root: root, device: device).contextPaths, ["Renamed.md"])
            XCTAssertEqual(try Data(contentsOf: old), replacement); XCTAssertEqual(try Data(contentsOf: moved), original)
            XCTAssertEqual(workspace.body, "# Original context\nUnsaved original evidence.")
            try FileManager.default.removeItem(at: moved)
            let missing = try await workspace.chatContextSnapshot(), kept = reopened.inputStamp
            XCTAssertThrowsError(try reopened.resolveNoteContext(missing), "The replacement at the old path must not become context")
            XCTAssertEqual(reopened.inputStamp, kept)
            try original.write(to: root.appendingPathComponent("DuplicateOne.md")); try original.write(to: root.appendingPathComponent("DuplicateTwo.md"))
            let ambiguous = try await workspace.chatContextSnapshot()
            XCTAssertThrowsError(try reopened.resolveNoteContext(ambiguous), "A duplicate ID requires review")
            XCTAssertEqual(reopened.draft, "Keep this unsent question")
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus/chats").path))
        }
    }
    func testLegacyPathOnlyContextRequiresReviewAndIdlessNotesUseContentFingerprints() async throws {
        try await fixture { root, workspace in
            let original = Data("# Legacy context\nOriginal text.\n".utf8), path = root.appendingPathComponent("Legacy.md")
            try original.write(to: path); await workspace.openVault(root)
            let device = MacChatDevice(id: "legacy-context-test", name: "Legacy context test"), chat = MacChatController(root: root, device: device)
            chat.draft = "Keep legacy question"
            let image = try makeChatTestImage(in: root); try chat.addImages([image])
            let file = draftFile(root); var old = try MacConversations.object(Data(contentsOf: file))
            old["contextPaths"] = ["new": ["Legacy.md"]]; old.removeValue(forKey: "contextReferences")
            try MacConversations.data(old).write(to: file, options: .atomic)
            let recovered = MacChatController(root: root, device: device), first = try await workspace.chatContextSnapshot()
            XCTAssertThrowsError(try recovered.resolveNoteContext(first), "An old path selection must not silently bind a new identity")
            XCTAssertEqual(recovered.draft, "Keep legacy question"); XCTAssertEqual(recovered.selectedImages.first?.bytes, image.bytes)
            try recovered.setContextReferences(MacChatNoteReference.capture(["Legacy.md"], notes: first.notes))
            try FileManager.default.moveItem(at: path, to: root.appendingPathComponent("Legacy moved.md"))
            let moved = try await workspace.chatContextSnapshot(), sources = try recovered.resolveNoteContext(moved)
            XCTAssertEqual(sources.first?.content, String(decoding: original, as: UTF8.self)); XCTAssertEqual(recovered.contextPaths, ["Legacy moved.md"])
            let updated = "# Legacy context\nChanged text requires review.\n"
            try Data(updated.utf8).write(to: root.appendingPathComponent("Legacy moved.md"))
            let changed = try await workspace.chatContextSnapshot()
            XCTAssertThrowsError(try recovered.resolveNoteContext(changed))
            try recovered.setContextReferences(MacChatNoteReference.capture(["Legacy moved.md"], notes: changed.notes))
            XCTAssertEqual(try recovered.resolveNoteContext(changed).first?.content, updated)
            let foreign = MacChatContextSnapshot(workspaceID: changed.workspaceID, root: root.appendingPathComponent("Another vault"), notes: changed.notes, drafts: [])
            XCTAssertThrowsError(try recovered.resolveNoteContext(foreign))
            XCTAssertEqual(recovered.selectedImages.first?.bytes, image.bytes)
            try recovered.setContextReferences([])
            XCTAssertEqual(MacChatController(root: root, device: device).contextReferences, [])
        }
    }
    private func draftFile(_ root: URL) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zerus Native/Drafts/Chat/" + NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.absoluteString) + ".json")
    }
    private func fixture(_ operation: (URL, MacWorkspace) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-search-context-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults"), workspace = MacWorkspace()
        defer {
            if let directory = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            for key in [MacNavigationState.key(root), "zerus.mac.bookmark." + NativeHistory.hash(root.path), "zerus.mac.search.recent." + NativeHistory.hash(root.path)] { defaults.removeObject(forKey: key) }
            let draft = draftFile(root)
            for folder in ["Images", "Documents"] { try? FileManager.default.removeItem(at: draft.deletingLastPathComponent().appendingPathComponent(folder + "/" + draft.deletingPathExtension().lastPathComponent)) }
            try? FileManager.default.removeItem(at: draft); try? FileManager.default.removeItem(at: root)
        }
        try await operation(root, workspace)
    }
}
