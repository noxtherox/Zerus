import XCTest
import CryptoKit
@testable import ZerusNative

final class NativeChatIsolationTests: XCTestCase {
    @MainActor
    func testUUIDCasingAndReusedFormerPathsCannotHideOrLeakPrivateConversation() async throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let before = base.appendingPathComponent("Before"), after = base.appendingPathComponent("After")
        try FileManager.default.createDirectory(at:before,withIntermediateDirectories:true)
        let legacy = NativeChat.legacyDirectory(for:before), seed = NativeChat(vaultRoot:before)
        let turn = try XCTUnwrap(seed.beginAgentTurn("Identity-bound private question")); seed.finishAgentTurn(turn,fallback:"Private answer"); seed.draft = "Keep my private draft"
        let vault = VaultStore(); await vault.open(before); let id = try XCTUnwrap(vault.activeVaultID)
        let alternate = legacy.deletingLastPathComponent().appendingPathComponent("vault-"+id.uuidString.lowercased())
        defer { try? FileManager.default.removeItem(at:base); try? FileManager.default.removeItem(at:legacy); try? FileManager.default.removeItem(at:alternate) }
        let descriptor = legacy.appendingPathComponent("vault.json"), live = NativeChat.shared(for:before)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:descriptor)) as? [String:Any]); object["vaultIDs"] = [id.uuidString.uppercased()]
        try JSONSerialization.data(withJSONObject:object).write(to:descriptor,options:.atomic)
        await vault.prepareChatStorage(); XCTAssertTrue(vault.chatStorageReady,vault.chatStorageIssue ?? "")
        guard NativeChat(vaultRoot:before).messages.map(\.content) == ["Identity-bound private question","Private answer"] else { XCTFail("A valid UUID with different letter casing must not hide an existing conversation"); return }
        try FileManager.default.moveItem(at:before,to:after); await vault.open(after,registeredID:id)
        XCTAssertEqual(vault.activeVaultID,id); XCTAssertTrue(NativeChat.shared(for:after) === live)
        try FileManager.default.createDirectory(at:before,withIntermediateDirectories:true)
        try Data("# A different library at the old path".utf8).write(to:before.appendingPathComponent("New.md"))
        UserDefaults.standard.removeObject(forKey:NativeVaultRegistry.key)
        let reused = NativeChat.shared(for:before)
        XCTAssertTrue(reused.messages.isEmpty,"A former path cannot inherit the moved vault's live private conversation when its registration is unavailable")
        XCTAssertTrue(reused.draft.isEmpty); XCTAssertFalse(reused === live)
        XCTAssertEqual(try String(contentsOf:legacy.appendingPathComponent("prompt.txt"),encoding:.utf8),"Keep my private draft")
    }

    @MainActor
    func testLegacyChatFolderUpgradePreservesOpaqueBytesAndAppearsInSearch() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = NativeChat.legacyDirectory(for: root)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: directory) }
        let old = NativeChat(vaultRoot: root)
        let first = try XCTUnwrap(old.beginAgentTurn("Archived native question")); old.finishAgentTurn(first, fallback: "Archived answer"); old.clear()
        let current = try XCTUnwrap(old.beginAgentTurn("Current native question")); old.finishAgentTurn(current, fallback: "Current answer"); old.draft = "Keep this unsent thought"
        let foreign = directory.appendingPathComponent("Future/opaque.bin"); try FileManager.default.createDirectory(at: foreign.deletingLastPathComponent(), withIntermediateDirectories: true)
        let opaque = Data([255,0,19,75]); try opaque.write(to: foreign)
        let existing = try FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!.allObjects.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.map { ($0,try Data(contentsOf:$0)) }
        let vault = VaultStore(); await vault.open(root); XCTAssertTrue(vault.chatStorageReady, vault.chatStorageIssue ?? "")
        let upgraded = NativeChat.shared(for: root)
        XCTAssertEqual(upgraded.draft, "Keep this unsent thought"); XCTAssertEqual(upgraded.messages.map(\.content), ["Current native question","Current answer"])
        XCTAssertEqual(upgraded.archives.first?.messages?.map(\.content), ["Archived native question","Archived answer"])
        XCTAssertEqual(upgraded.attachmentStore.directory.standardizedFileURL.path, directory.standardizedFileURL.path)
        for (url, bytes) in existing { XCTAssertEqual(try Data(contentsOf:url), bytes) }
        let descriptor = directory.appendingPathComponent("vault.json")
        var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:descriptor)) as? [String:Any]); metadata["future"] = ["keep":[1,2,3]]
        try JSONSerialization.data(withJSONObject:metadata).write(to:descriptor,options:.atomic)
        await vault.prepareChatStorage(); XCTAssertTrue(vault.chatStorageReady)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:descriptor)) as? [String:Any]); XCTAssertEqual((saved["future"] as? [String:[Int]])?["keep"],[1,2,3])
        let supplemental = try await VaultFiles(root:root).searchSupplement(files:[],liveConversation:nil)
        XCTAssertEqual(Set(supplemental.conversations.map(\.title)),["Archived native question","Current native question"])
        XCTAssertEqual(try Data(contentsOf:foreign),opaque)
    }

    @MainActor
    func testAmbiguousNewerAndLinkedChatBindingsPreserveHistoryAndRefuseWrites() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let vault = VaultStore(); await vault.open(root); XCTAssertTrue(vault.chatStorageReady)
        let chat = NativeChat.shared(for:root), directory = chat.attachmentStore.directory
        let turn = try XCTUnwrap(chat.beginAgentTurn("Protected original question")); chat.finishAgentTurn(turn,fallback:"Protected answer"); chat.draft = "Protected draft"
        let current = directory.appendingPathComponent("current.json"), original = try Data(contentsOf:current), descriptor = directory.appendingPathComponent("vault.json"), metadata = try Data(contentsOf:descriptor)
        let duplicate = directory.deletingLastPathComponent().appendingPathComponent("duplicate-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root); try? FileManager.default.removeItem(at:directory); try? FileManager.default.removeItem(at:duplicate); try? FileManager.default.removeItem(at:NativeChat.legacyDirectory(for:root)) }
        try FileManager.default.copyItem(at:directory,to:duplicate)
        await vault.prepareChatStorage(); XCTAssertFalse(vault.chatStorageReady); XCTAssertNotNil(vault.chatStorageIssue)
        XCTAssertEqual(try Data(contentsOf:current),original); XCTAssertEqual(try Data(contentsOf:duplicate.appendingPathComponent("current.json")),original)
        try FileManager.default.removeItem(at:duplicate)
        var newer = try XCTUnwrap(JSONSerialization.jsonObject(with:metadata) as? [String:Any]); newer["version"] = 99
        var foreignOwner = try XCTUnwrap(JSONSerialization.jsonObject(with:metadata) as? [String:Any]); foreignOwner["vaultIDs"] = [UUID().uuidString.lowercased()]
        let future = try JSONSerialization.data(withJSONObject:newer), corrupt = Data([255,1,2]), foreign = try JSONSerialization.data(withJSONObject:foreignOwner)
        for bytes in [future,corrupt,foreign] {
            try bytes.write(to:descriptor,options:.atomic); await vault.prepareChatStorage()
            XCTAssertFalse(vault.chatStorageReady); XCTAssertNotNil(vault.chatStorageIssue)
            let protected = NativeChat(vaultRoot:root); XCTAssertNotNil(protected.storageProblem)
            protected.draft = "Cannot overwrite"; XCTAssertNil(protected.beginAgentTurn("Cannot send")); protected.clear(); protected.recoverAttachmentDraft()
            XCTAssertEqual(try Data(contentsOf:current),original); XCTAssertEqual(try Data(contentsOf:descriptor),bytes)
            XCTAssertEqual(try String(contentsOf:directory.appendingPathComponent("prompt.txt"),encoding:.utf8),"Protected draft")
        }
        let outside = root.appendingPathComponent("outside.json"); try metadata.write(to:outside)
        try FileManager.default.removeItem(at:descriptor); try FileManager.default.createSymbolicLink(at:descriptor,withDestinationURL:outside)
        await vault.prepareChatStorage(); XCTAssertFalse(vault.chatStorageReady); XCTAssertEqual(try Data(contentsOf:outside),metadata); XCTAssertEqual(try Data(contentsOf:current),original)
        try FileManager.default.removeItem(at:descriptor); try metadata.write(to:descriptor)
        await vault.prepareChatStorage(); XCTAssertTrue(vault.chatStorageReady); XCTAssertNil(vault.chatStorageIssue)
        XCTAssertEqual(NativeChat(vaultRoot:root).messages.map(\.content),["Protected original question","Protected answer"])
    }

    @MainActor
    func testRegisteredVaultMoveKeepsConversationPromptArchivesAndFrozenInputs() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let before = root.appendingPathComponent("Before/Notes"), after = root.appendingPathComponent("After/Notes"), foreign = root.appendingPathComponent("Other/Notes")
        for url in [before, foreign, after.deletingLastPathComponent()] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root); for url in [before, after, foreign] { try? FileManager.default.removeItem(at: NativeChat.directory(for: url)) } }
        let note = Data("---\nzerus-id: continuity\n---\n# Keep\nOriginal writing.\n".utf8); try note.write(to: before.appendingPathComponent("Keep.md"))
        let vault = VaultStore(); await vault.open(before)
        let identity = try XCTUnwrap(vault.activeVaultID), chat = NativeChat.shared(for: before)
        let first = try XCTUnwrap(chat.beginAgentTurn("Archive this first question")); chat.finishAgentTurn(first, fallback: "First answer"); chat.clear()
        let input = try NativePreparedChatAttachment.prepare(Data("Frozen reference café".utf8), name: "Reference.txt")
        let token = try XCTUnwrap(chat.beginAttachmentImport()); let admitted = try await chat.addAttachments([input], importID: token); XCTAssertTrue(admitted); chat.cancelAttachmentImport(token)
        let turn = try XCTUnwrap(chat.beginAgentTurn("Keep this conversation", attachments: chat.attachments)); chat.finishAgentTurn(turn, fallback: "Kept answer")
        chat.draft = "An unsent thought 🌿"
        let run = UUID(); try chat.attachmentStore.authorize(run: run, chat: chat.conversationID, items: [input.descriptor])
        let directory = chat.attachmentStore.directory, unknown = directory.appendingPathComponent("future-private-data.bin"), unknownBytes = Data([0, 255, 17]); try unknownBytes.write(to: unknown)
        let messages = chat.messages.map(\.id), archive = try XCTUnwrap(chat.archives.first?.messages?.map(\.content))
        try FileManager.default.moveItem(at: before, to: after)
        await vault.open(after, registeredID: identity)
        XCTAssertEqual(vault.activeVaultID, identity)
        let reopened = NativeChat.shared(for: after)
        XCTAssertEqual(reopened.messages.map(\.id), messages, "The same saved vault must retain its current conversation after its root moves")
        XCTAssertEqual(reopened.draft, "An unsent thought 🌿"); XCTAssertEqual(reopened.archives.first?.messages?.map(\.content), archive)
        XCTAssertEqual(reopened.attachments, [input.descriptor]); XCTAssertEqual(try reopened.attachmentStore.read(input.descriptor), input.data)
        try reopened.attachmentStore.validate(run: run, chat: reopened.conversationID, items: [input.descriptor])
        XCTAssertTrue(reopened === chat, "Two live paths to the same saved vault must share one streaming conversation")
        XCTAssertEqual(try Data(contentsOf: unknown), unknownBytes); XCTAssertEqual(try Data(contentsOf: after.appendingPathComponent("Keep.md")), note)
        await vault.open(foreign); XCTAssertNotEqual(vault.activeVaultID, identity)
        let independent = NativeChat.shared(for: foreign); XCTAssertTrue(independent.messages.isEmpty); XCTAssertTrue(independent.attachments.isEmpty); XCTAssertTrue(independent.draft.isEmpty)
    }

    @MainActor
    func testConversationHistoryIsScopedToTheWholeVaultPathAndEarlierHistoryRequiresAnExplicitRestore() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = support.appendingPathComponent("native-chat.json"), before = try? Data(contentsOf: legacy)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let aURL = root.appendingPathComponent("A/Notes"), bURL = root.appendingPathComponent("B/Notes")
        func directory(_ vault: URL) -> URL {
            let key = SHA256.hash(data: Data(vault.standardizedFileURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
            return support.appendingPathComponent("NativeChats/" + key)
        }
        defer {
            if let before { try? before.write(to: legacy, options: .atomic) } else { try? FileManager.default.removeItem(at: legacy) }
            for url in [aURL, bURL] { try? FileManager.default.removeItem(at: directory(url)) }
        }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let earlier = [ChatMessage(role: "user", content: "Earlier private question"), ChatMessage(role: "assistant", content: "Earlier answer")]
        let original = try JSONEncoder().encode(earlier)
        try original.write(to: legacy, options: .atomic)
        let a = NativeChat(vaultRoot: aURL), b = NativeChat(vaultRoot: bURL)
        XCTAssertTrue(a.messages.isEmpty, "Unassigned earlier context must not enter a vault automatically")
        XCTAssertTrue(b.messages.isEmpty, "Vaults with the same display name still have independent histories")
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        a.draft = "Unsent prompt belonging to workspace A"
        XCTAssertEqual(NativeChat(vaultRoot: aURL).draft, "Unsent prompt belonging to workspace A")
        XCTAssertTrue(b.draft.isEmpty)
        XCTAssertTrue(a.restoreEarlierConversation())
        XCTAssertEqual(a.messages.map(\.content), ["Earlier private question", "Earlier answer"])
        XCTAssertTrue(b.messages.isEmpty)
        let reopenedA = NativeChat(vaultRoot: aURL)
        XCTAssertEqual(reopenedA.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(reopenedA.messages.map(\.content), ["Earlier private question", "Earlier answer"])
        let firstWindow = NativeChat.shared(for: aURL), secondWindow = NativeChat.shared(for: aURL)
        firstWindow.draft = "A draft shared by windows of this vault"
        XCTAssertEqual(secondWindow.draft, "A draft shared by windows of this vault")
        firstWindow.clear()
        XCTAssertTrue(secondWindow.messages.isEmpty)
        let archive = try XCTUnwrap(secondWindow.archives.first)
        XCTAssertEqual(archive.messages?.map(\.content), ["Earlier private question", "Earlier answer"])
        XCTAssertTrue(secondWindow.open(archive))
        XCTAssertEqual(firstWindow.messages.map(\.content), ["Earlier private question", "Earlier answer"])
        XCTAssertTrue(NativeChat(vaultRoot: bURL).messages.isEmpty)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        let future = Data(#"{"version":99,"unrecognized":{"keep":[1,2,3]}}"#.utf8), current = directory(aURL).appendingPathComponent("current.json")
        try future.write(to: current, options: .atomic)
        firstWindow.clear()
        XCTAssertNotNil(firstWindow.error, "A stale window must not overwrite newer saved bytes")
        XCTAssertEqual(try Data(contentsOf: current), future)
        let unreadable = NativeChat(vaultRoot: aURL)
        XCTAssertNotNil(unreadable.error)
        unreadable.clear()
        XCTAssertTrue(unreadable.messages.isEmpty); XCTAssertNil(unreadable.error)
        let preserved = try XCTUnwrap(unreadable.archives.first { $0.messages == nil })
        XCTAssertEqual(try Data(contentsOf: preserved.url), future)
        XCTAssertEqual(try JSONDecoder().decode([ChatMessage].self, from: Data(contentsOf: current)).count, 0)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        let invalidDraft = Data([255, 254, 0]), promptFile = directory(bURL).appendingPathComponent("prompt.txt")
        try FileManager.default.createDirectory(at: directory(bURL), withIntermediateDirectories: true)
        try invalidDraft.write(to: promptFile, options: .atomic)
        let protected = NativeChat(vaultRoot: bURL)
        XCTAssertNotNil(protected.draftProblem)
        protected.draft = "A new in-memory draft"
        XCTAssertEqual(try Data(contentsOf: promptFile), invalidDraft)
        XCTAssertEqual(protected.draftRecoveryURL, promptFile)
    }

    @MainActor
    func testDictationPersistsPartialTextAndRejectsChangedPromptsStaleLeasesAndOtherWorkspaces() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let other = root.appendingPathComponent("Other")
        defer { try? FileManager.default.removeItem(at: NativeChat.directory(for: root)); try? FileManager.default.removeItem(at: NativeChat.directory(for: other)) }
        let chat = NativeChat(vaultRoot: root), foreign = NativeChat(vaultRoot: other), workspace = UUID()
        let turn = try XCTUnwrap(chat.beginAgentTurn("Earlier question")); chat.finishAgentTurn(turn, fallback: "Earlier answer")
        let existing = chat.messages.map(\.id)
        chat.draft = "Keep my 🧑🏽‍💻 thought."
        foreign.draft = "Other vault text"
        let first = try XCTUnwrap(chat.beginDictation(workspace: workspace))
        XCTAssertNil(chat.beginDictation(workspace: workspace))
        XCTAssertTrue(chat.acceptDictation("  A partial phrase  ", id: first, workspace: workspace))
        XCTAssertEqual(chat.draft, "Keep my 🧑🏽‍💻 thought. A partial phrase")
        XCTAssertEqual(NativeChat(vaultRoot: root).draft, chat.draft, "Partial text must survive a cold launch without sending")
        chat.clear(); XCTAssertEqual(chat.messages.map(\.id), existing)
        XCTAssertNil(chat.beginAgentTurn("Must not send while dictating"))
        XCTAssertFalse(chat.acceptDictation("Wrong workspace", id: first, workspace: UUID()))
        chat.draft = "Typed in another window\n"
        XCTAssertFalse(chat.acceptDictation("Late recognition", id: first, workspace: workspace))
        XCTAssertEqual(chat.draft, "Typed in another window\n")
        chat.endDictation(first)
        let next = try XCTUnwrap(chat.beginDictation(workspace: workspace))
        chat.endDictation(first)
        XCTAssertNil(chat.beginDictation(workspace: workspace), "A stale cleanup must not release a newer dictation")
        XCTAssertFalse(chat.acceptDictation("Old callback", id: first, workspace: workspace))
        XCTAssertTrue(chat.acceptDictation("新的文字", id: next, workspace: workspace))
        XCTAssertEqual(chat.draft, "Typed in another window\n新的文字")
        chat.endDictation(next)
        XCTAssertEqual(NativeChat(vaultRoot: root).draft, "Typed in another window\n新的文字")
        XCTAssertEqual(foreign.draft, "Other vault text")
        XCTAssertEqual(NativeChat(vaultRoot: root).messages.map(\.id), existing)
    }

    @MainActor
    func testCancelBeforeCaptureReleasesGlobalAudioOwnershipAndKeepsBothVaultDrafts() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let a = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), b = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for root in [a, b] { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        defer { for root in [a, b] { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: NativeChat.directory(for: root)) } }
        let vaultA = VaultStore(), vaultB = VaultStore(); await vaultA.open(a); await vaultB.open(b)
        let first = NativeChat(vaultRoot: a), second = NativeChat(vaultRoot: b)
        first.draft = "First prompt"; second.draft = "Second prompt"
        // All three calls run before yielding to the capture task: no microphone
        // or speech permission is requested by this ownership/lifecycle check.
        first.dictation.start(chat: first, vault: vaultA, workspace: vaultA.workspaceID)
        XCTAssertTrue(first.dictation.active); XCTAssertTrue(first.dictating)
        second.dictation.start(chat: second, vault: vaultB, workspace: vaultB.workspaceID)
        XCTAssertFalse(second.dictation.active); XCTAssertFalse(second.dictating); XCTAssertNotNil(second.dictation.issue)
        first.dictation.cancel()
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while first.dictation.active, ProcessInfo.processInfo.systemUptime < deadline { await Task.yield() }
        XCTAssertFalse(first.dictation.active); XCTAssertFalse(first.dictating)
        second.dictation.start(chat: second, vault: vaultB, workspace: vaultB.workspaceID)
        XCTAssertTrue(second.dictation.active, "The canceled capture must release the global audio owner")
        second.dictation.cancel()
        while second.dictation.active, ProcessInfo.processInfo.systemUptime < deadline { await Task.yield() }
        XCTAssertFalse(second.dictation.active); XCTAssertFalse(second.dictating)
        XCTAssertEqual(first.draft, "First prompt"); XCTAssertEqual(second.draft, "Second prompt")
        XCTAssertTrue(first.messages.isEmpty); XCTAssertTrue(second.messages.isEmpty)
    }

}
