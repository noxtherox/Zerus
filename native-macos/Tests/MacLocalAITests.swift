import AppKit
import XCTest
import ZerusLocalAICore
@testable import Zerus_Native

@MainActor final class MacLocalAITests: XCTestCase {
    private final class Box { var text = "" }

    func testEditorBridgeReadsSelectionAppliesOneUndoableEditAndRejectsStaleReplacements() throws {
        let scope = UUID(), box = Box()
        let text = "# Plan\n\nBook the train to Porto.\n\n- [ ] Pack the bags\n"
        let parent = MacRichEditor(markdown: text, source: false, editable: true, path: "Plan.md", onChange: { box.text = $0 }, onLink: { _ in }, commandScope: scope)
        let coordinator = MacRichEditor.Coordinator(parent), view = NSTextView()
        view.isRichText = true; view.allowsUndo = true; view.delegate = coordinator; coordinator.view = view
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeFirstResponder(view)
        defer { coordinator.detach(); window.close() }
        coordinator.load(text, source: false)

        view.setSelectedRange((view.string as NSString).range(of: "train to Porto"))
        let snapshot = try MacLocalAIEditorRequest.perform(scope: scope, path: "Plan.md", kind: .read)
        XCTAssertEqual(snapshot.selection, "train to Porto")
        XCTAssertTrue(snapshot.markdown.contains("Book the train to Porto."))

        // Another note or window gets no answer.
        XCTAssertThrowsError(try MacLocalAIEditorRequest.perform(scope: UUID(), path: "Plan.md", kind: .read))
        XCTAssertThrowsError(try MacLocalAIEditorRequest.perform(scope: scope, path: "Other.md", kind: .read))

        let replacement = snapshot.markdown.replacingOccurrences(of: "train to Porto", with: "flight to Madeira")
        try MacLocalAIEditorRequest.perform(scope: scope, path: "Plan.md", kind: .replace(expected: snapshot.markdown, replacement: replacement, actionName: "AI Edit"))
        XCTAssertTrue(box.text.contains("Book the flight to Madeira."))
        XCTAssertTrue(box.text.contains("- [ ] Pack the bags"), "the rest of the note is kept")
        XCTAssertEqual(view.undoManager?.undoActionName, "AI Edit")

        // The review compared against the old text: a second apply is refused.
        XCTAssertThrowsError(try MacLocalAIEditorRequest.perform(scope: scope, path: "Plan.md", kind: .replace(expected: snapshot.markdown, replacement: replacement, actionName: "AI Edit")))

        view.undoManager?.undo()
        let restored = try MacLocalAIEditorRequest.perform(scope: scope, path: "Plan.md", kind: .read)
        XCTAssertTrue(restored.markdown.contains("Book the train to Porto."), "one undo step reverts the AI edit")
    }

    func testPropertiesApplyAndUndoAndCreatedNotesKeepOneHeading() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-local-ai-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Trips"), withIntermediateDirectories: true)
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults"), workspace = MacWorkspace()
        defer {
            if let directory = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            for key in [MacNavigationState.key(root), "zerus.mac.bookmark." + NativeHistory.hash(root.path), "zerus.mac.search.recent." + NativeHistory.hash(root.path)] { defaults.removeObject(forKey: key) }
            try? FileManager.default.removeItem(at: root)
        }
        let original = "---\ntags: [travel]\nstatus: open\n---\n# Porto\n\nTrain on Friday.\n"
        try Data(original.utf8).write(to: root.appendingPathComponent("Trips/Porto.md"))
        await workspace.openVault(root)
        await workspace.openNote("Trips/Porto.md")
        XCTAssertEqual(workspace.current?.path, "Trips/Porto.md")
        XCTAssertEqual(MacLocalAIActionView.properties(original), ["tags": .list(["travel"]), "status": .text("open")])

        let ops = [LocalAIPropertyOperation(kind: .set, key: "tags", values: ["travel", "porto"]), LocalAIPropertyOperation(kind: .remove, key: "status", values: [])]
        let written = try await workspace.applyLocalAIProperties(ops, expectedPath: "Trips/Porto.md", workspaceID: workspace.workspaceID)
        let changed = try String(contentsOf: root.appendingPathComponent("Trips/Porto.md"), encoding: .utf8)
        XCTAssertEqual(written.after, changed)
        XCTAssertFalse(changed.contains("status:"))
        XCTAssertEqual(MacLocalAIActionView.properties(changed)["tags"], .list(["travel", "porto"]))
        XCTAssertTrue(changed.hasSuffix("# Porto\n\nTrain on Friday.\n"), "the body is untouched")

        // A stale target is refused.
        do {
            _ = try await workspace.applyLocalAIProperties(ops, expectedPath: "Trips/Other.md", workspaceID: workspace.workspaceID)
            XCTFail("a different open note must be refused")
        } catch {}

        let undone = await workspace.revertLocalAIWrite(before: written.before, after: written.after)
        XCTAssertTrue(undone)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Trips/Porto.md"), encoding: .utf8), original)

        let created = await workspace.createLocalAINote(title: "Packing list", body: "# Packing list\n\n- Passport\n- Charger", folder: "Trips")
        XCTAssertTrue(created)
        let path = try XCTUnwrap(workspace.current?.path)
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "# Packing list").count, 2, "one heading")
        XCTAssertTrue(text.hasSuffix("# Packing list\n\n- Passport\n- Charger\n"))
        XCTAssertTrue(text.contains("zerus-id:"))
    }

    func testAskSourceSlugs() {
        XCTAssertEqual(MacLocalAI.slug("Viagem a Lisboa — 2026 plano"), "viagem-a-lisboa-2026")
        XCTAssertEqual(MacLocalAI.slug("東京 出張"), "東京-出張")
        XCTAssertEqual(MacLocalAI.slug("!!!"), "note")
    }
}

/// End to end with the real models inside the app process (MLX Metal
/// library, model loading, indexing, search, Ask). Runs when the pinned
/// snapshots are in the local Hugging Face cache; uses a temporary store and
/// index (APFS clones), never the app's real Application Support data.
@MainActor final class MacLocalAIModelTests: XCTestCase {
    func testIndexSearchAndAskWithRealModels() async throws {
        let cache = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache/huggingface/hub")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-local-ai-models-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = LocalAIModelStore(root: temp.appendingPathComponent("Models"))
        for spec in LocalAIModelSpec.all {
            let snapshot = cache.appendingPathComponent("models--" + spec.repository.replacingOccurrences(of: "/", with: "--") + "/snapshots/" + spec.revision)
            guard FileManager.default.fileExists(atPath: snapshot.path) else { throw XCTSkip("pinned snapshots are not in the Hugging Face cache") }
            let target = store.directory(for: spec)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for file in spec.files {
                try FileManager.default.copyItem(at: snapshot.appendingPathComponent(file.path).resolvingSymlinksInPath(), to: target.appendingPathComponent(file.path))
            }
            try store.verifyAndMarkInstalled(spec)
        }
        let root = temp.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Home"), withIntermediateDirectories: true)
        let notes = [
            "Home/Garden.md": "# Garden\n\nPlant tomatoes and basil at the end of April, after the last frost.\n",
            "Home/Boiler.md": "# Boiler\n\nThe plumber Rui serviced the boiler on 12 March. Invoice INV-2291, 140 euros.\n",
            "Home/Porto trip.md": "# Porto trip\n\nTrain on Friday at 9:10. Hotel near the Ribeira, two nights.\n",
        ]
        for (path, text) in notes { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults"), workspace = MacWorkspace()
        defer {
            if let directory = workspace.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            for key in [MacNavigationState.key(root), "zerus.mac.bookmark." + NativeHistory.hash(root.path), "zerus.mac.search.recent." + NativeHistory.hash(root.path)] { defaults.removeObject(forKey: key) }
        }
        await workspace.openVault(root)

        let ai = MacLocalAI(store: store, indexDirectory: temp.appendingPathComponent("Index"))
        XCTAssertTrue(ai.installed)
        ai.sync(workspace)
        await ai.waitForIndex()
        XCTAssertEqual(ai.index.total, 3)
        XCTAssertEqual(ai.index.indexed, 3, ai.index.issue ?? "")
        XCTAssertTrue(ai.searchReady)

        let hits = await ai.search("when should I sow vegetables", in: workspace)
        XCTAssertEqual(hits.first?.path, "Home/Garden.md")
        let exact = await ai.search("INV-2291", in: workspace)
        XCTAssertEqual(exact.first?.path, "Home/Boiler.md")
        XCTAssertEqual(exact.first?.exactMatch, true)

        let sources = try await ai.askSources(for: "Who serviced the boiler?", in: workspace)
        XCTAssertEqual(sources.first?.path, "Home/Boiler.md")
        let answer = try await ai.pipelines().ask("Who serviced the boiler?", sources: sources, language: "en")
        XCTAssertTrue(answer.found)
        XCTAssertTrue(answer.answer.contains("Rui"), answer.answer)
        XCTAssertEqual(answer.sources.first, "Home/Boiler.md")
    }
}
