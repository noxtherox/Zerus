import XCTest
import SwiftUI
import UIKit
@testable import ZerusNative

final class NativeImageLoadingTests: XCTestCase {
    @MainActor
    func testOpenEditorRetriesLateImagesWithoutRewritingTextOrLosingPendingUndo() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = Data("---\nzerus-id: late-image\nforeign: keep\n---\n# Chart\n\nBefore **the image**.\n\n- [ ] Keep pending edit\n\n![Chart](assets/late.png)\n\nAfter the image.\n".utf8)
        let noteURL = root.appendingPathComponent("Chart.md"), imageURL = root.appendingPathComponent("assets/late.png")
        try source.write(to: noteURL)
        // File providers can expose an entry before its complete bytes arrive.
        try Data("Not an image yet".utf8).write(to: imageURL)
        let store = VaultStore(); await store.open(root)
        let session = try XCTUnwrap(store.session(for: try XCTUnwrap(store.notes.first)))
        let navigation = NativeNoteNavigation(vault: store, session: session)
        let observer = ImageReadObserver(url: imageURL)
        NSFileCoordinator.addFilePresenter(observer)
        var observing = true
        defer { if observing { NSFileCoordinator.removeFilePresenter(observer) } }
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        let host = UIHostingController(rootView: NativeNoteNavigationView(navigation: navigation).environmentObject(store).environment(\.scenePhase, ScenePhase.active))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { session.deactivate(); window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        await fulfillment(of: [observer.firstRead], timeout: 5)
        NSFileCoordinator.removeFilePresenter(observer); observing = false
        let editor = try XCTUnwrap(editor(in: host.view))
        editor.layoutIfNeeded(); XCTAssertTrue(editor.becomeFirstResponder())
        let toggle = try XCTUnwrap(editor.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Complete: Keep pending edit" })
        toggle.sendActions(for: .touchUpInside); await session.save()
        let edited = Data(String(decoding: source, as: UTF8.self).replacingOccurrences(of: "- [ ] Keep pending edit", with: "- [x] Keep pending edit").utf8)
        XCTAssertEqual(try Data(contentsOf: noteURL), edited)
        XCTAssertTrue(try XCTUnwrap(editor.undoManager).canUndo, "The user's checkbox edit owns an Undo step before the image arrives")
        let selection = (editor.text as NSString).range(of: "Before")
        editor.selectedRange = selection
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 320), format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 320))
        }
        let bytes = try XCTUnwrap(image.pngData()); try bytes.write(to: imageURL, options: .atomic)
        let deadline = ContinuousClock.now + .seconds(10)
        while !containsLoadedChart(host.view), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(containsLoadedChart(host.view), "The same open native editor must retry and replace its placeholder with the available image")
        XCTAssertEqual(try Data(contentsOf: noteURL), edited, "Loading and retrying previews must never rewrite Markdown or properties")
        XCTAssertEqual(editor.selectedRange, selection)
        XCTAssertTrue(try XCTUnwrap(editor.undoManager).canUndo, "Receiving a preview must keep the existing edit's Undo history")
        let replacement = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 640), format: format).image { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 640))
        }
        let replacementBytes = try XCTUnwrap(replacement.pngData())
        try replacementBytes.write(to: imageURL, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: imageURL.path)
        let gate = NativeProviderReadGate(url: imageURL)
        NSFileCoordinator.addFilePresenter(gate)
        var holdingReplacement = true
        defer { if holdingReplacement { gate.release(); NSFileCoordinator.removeFilePresenter(gate) } }
        await store.refresh()
        await fulfillment(of: [gate.requested], timeout: 5)
        XCTAssertTrue(containsLoadedChart(host.view), "Keep the previous preview visible while the real file provider holds the replacement")
        XCTAssertEqual(editor.selectedRange, selection)
        XCTAssertEqual(try Data(contentsOf: noteURL), edited)
        gate.release(); NSFileCoordinator.removeFilePresenter(gate); holdingReplacement = false
        let refreshed = ContinuousClock.now + .seconds(5)
        while !containsLoadedChart(host.view, width: 320, height: 640), ContinuousClock.now < refreshed { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(containsLoadedChart(host.view, width: 320, height: 640), "Refresh must replace an already-loaded image at the same path in the same open editor")
        XCTAssertTrue(self.editor(in: host.view) === editor, "Refreshing an image must retain the live text editor")
        XCTAssertEqual(editor.selectedRange, selection)
        XCTAssertEqual(try Data(contentsOf: noteURL), edited, "Refreshing an image must not rewrite its note")
        editor.undoManager?.undo(); await session.save()
        XCTAssertEqual(try Data(contentsOf: noteURL), source, "One Undo still restores the original checkbox and exact file")
        editor.undoManager?.redo(); await session.save()
        XCTAssertEqual(try Data(contentsOf: noteURL), edited, "Redo must survive image availability too")
        XCTAssertEqual(try Data(contentsOf: imageURL), replacementBytes)
        XCTAssertFalse(session.dirty)

        // A current revision owns its own image copy under .zerus/revisions.
        // That folder intentionally stays outside the ordinary Files inventory.
        let snapshot = try await store.revisionSnapshot(note: session.document)
        let milestone = try await store.prepareRevision(snapshot, action: .create)
        try await store.saveRevision(milestone)
        let reference = try XCTUnwrap(MarkdownText.imageReferences(session.document.parts.body).first)
        XCTAssertTrue(reference.hasPrefix(".zerus/revisions/"))
        let currentImage = root.appendingPathComponent(reference)
        XCTAssertEqual(try Data(contentsOf: currentImage), replacementBytes)
        let revisionBaseline = try Data(contentsOf: noteURL)
        let revisionReady = ContinuousClock.now + .seconds(5)
        var pendingCheckbox: UIButton?
        repeat {
            editor.layoutIfNeeded()
            pendingCheckbox = editor.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Mark incomplete: Keep pending edit" }
            if pendingCheckbox != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < revisionReady
        let currentCheckbox = try XCTUnwrap(pendingCheckbox, "Wait for the actual current-revision checklist layout before its next user edit")
        currentCheckbox.sendActions(for: .touchUpInside); await session.save()
        let revisionEdited = try Data(contentsOf: noteURL)
        XCTAssertNotEqual(revisionEdited, revisionBaseline)
        let revisionSelection = (editor.text as NSString).range(of: "Before")
        editor.selectedRange = revisionSelection
        XCTAssertTrue(editor.becomeFirstResponder())
        host.rootView = NativeNoteNavigationView(navigation: navigation).environmentObject(store).environment(\.scenePhase, .inactive)
        let backgrounded = ContinuousClock.now + .seconds(5)
        while editor.isFirstResponder, ContinuousClock.now < backgrounded { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(editor.isFirstResponder, "The production editor must actually observe the inactive scene before testing its return")

        try bytes.write(to: currentImage, options: .atomic)
        let resourceRevision = store.resourceRevision
        await store.refresh()
        XCTAssertEqual(store.resourceRevision, resourceRevision, "A revision image replacement must exercise the path omitted by the ordinary Files inventory")
        let foregroundRead = NativeProviderReadGate(url: currentImage)
        NSFileCoordinator.addFilePresenter(foregroundRead)
        var holdingForeground = true
        defer { if holdingForeground { foregroundRead.release(); NSFileCoordinator.removeFilePresenter(foregroundRead) } }
        host.rootView = NativeNoteNavigationView(navigation: navigation).environmentObject(store).environment(\.scenePhase, .active)
        await fulfillment(of: [foregroundRead.requested], timeout: 5)
        XCTAssertTrue(containsLoadedChart(host.view, width: 320, height: 640), "Keep the previous current-revision preview while foreground refresh waits for its provider")
        XCTAssertEqual(editor.selectedRange, revisionSelection)
        XCTAssertEqual(try Data(contentsOf: noteURL), revisionEdited)
        foregroundRead.release(); NSFileCoordinator.removeFilePresenter(foregroundRead); holdingForeground = false
        let returned = ContinuousClock.now + .seconds(5)
        while !containsLoadedChart(host.view), ContinuousClock.now < returned { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(containsLoadedChart(host.view), "Returning to the foreground must reload an already visible revision image even when the Files inventory did not change")
        XCTAssertTrue(self.editor(in: host.view) === editor)
        XCTAssertEqual(editor.selectedRange, revisionSelection)
        XCTAssertEqual(try Data(contentsOf: noteURL), revisionEdited)
        editor.undoManager?.undo(); await session.save()
        XCTAssertEqual(try Data(contentsOf: noteURL), revisionBaseline)
        editor.undoManager?.redo(); await session.save()
        XCTAssertEqual(try Data(contentsOf: noteURL), revisionEdited)
        XCTAssertEqual(try Data(contentsOf: currentImage), bytes)
    }

    @MainActor
    func testForegroundRefreshRereadsVisibleImageWhileAnotherProviderReadIsPending() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = Data("---\nzerus-id: foreground-overlap\nforeign: keep\n---\n# Chart\n\n![Chart](assets/a-chart.png)\n\n![Pending](assets/z-pending.png)\n".utf8)
        let note = root.appendingPathComponent("Chart.md"), chart = root.appendingPathComponent("assets/a-chart.png")
        let pending = root.appendingPathComponent("assets/z-pending.png")
        try source.write(to: note); try Data("Provider has not supplied this image".utf8).write(to: pending)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        func png(_ size: CGSize, _ color: UIColor) throws -> Data {
            try XCTUnwrap(UIGraphicsImageRenderer(size: size, format: format).image { context in
                color.setFill(); context.fill(CGRect(origin: .zero, size: size))
            }.pngData())
        }
        try png(CGSize(width: 640, height: 320), .systemOrange).write(to: chart)
        let store = VaultStore(); await store.open(root)
        let session = try XCTUnwrap(store.session(for: try XCTUnwrap(store.notes.first)))
        let navigation = NativeNoteNavigation(vault: store, session: session)
        let pendingRead = NativeProviderReadGate(url: pending)
        NSFileCoordinator.addFilePresenter(pendingRead)
        defer { pendingRead.release(); NSFileCoordinator.removeFilePresenter(pendingRead) }
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        let host = UIHostingController(rootView: NativeNoteNavigationView(navigation: navigation).environmentObject(store).environment(\.scenePhase, ScenePhase.active))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { session.deactivate(); window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        await fulfillment(of: [pendingRead.requested], timeout: 5)
        // The provider receipt does not wait for SwiftUI to display the prior
        // image update. Verify that image while the second read stays held.
        let firstVisible = ContinuousClock.now + .seconds(5)
        while !containsLoadedChart(host.view), ContinuousClock.now < firstVisible { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertTrue(containsLoadedChart(host.view), "The first image must become visible while the second real provider read is held")
        let view = try XCTUnwrap(editor(in: host.view))
        XCTAssertTrue(view.becomeFirstResponder())
        host.rootView = NativeNoteNavigationView(navigation: navigation).environmentObject(store).environment(\.scenePhase, .inactive)
        let inactive = ContinuousClock.now + .seconds(5)
        while view.isFirstResponder, ContinuousClock.now < inactive { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(view.isFirstResponder)
        let replacement = try png(CGSize(width: 320, height: 640), .systemBlue)
        try replacement.write(to: chart, options: .atomic)
        let foregroundRead = NativeProviderReadGate(url: chart)
        NSFileCoordinator.addFilePresenter(foregroundRead)
        defer { foregroundRead.release(); NSFileCoordinator.removeFilePresenter(foregroundRead) }
        host.rootView = NativeNoteNavigationView(navigation: navigation).environmentObject(store).environment(\.scenePhase, .active)
        await fulfillment(of: [foregroundRead.requested], timeout: 5)
        foregroundRead.release(); pendingRead.release()
        let refreshed = ContinuousClock.now + .seconds(5)
        while !containsLoadedChart(host.view, width: 320, height: 640), ContinuousClock.now < refreshed { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(containsLoadedChart(host.view, width: 320, height: 640), "Foreground refresh must replace the first image even while another resource is pending")
        XCTAssertEqual(try Data(contentsOf: note), source)
        XCTAssertEqual(try Data(contentsOf: chart), replacement)
    }

    @MainActor
    func testExternalEditorRefreshKeepsVisibleProjectImageSelectionAndUndoUntilReplacementArrives() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = Data([0xef, 0xbb, 0xbf]) + Data("---\nforeign: keep\n---\n# External chart\n\nBefore the image.\n\n- [ ] Keep pending edit\n\n![Chart](assets/chart.png)\n\nAfter the image.\n".utf8)
        let noteURL = root.appendingPathComponent("External.md"), imageURL = root.appendingPathComponent("assets/chart.png")
        try source.write(to: noteURL)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        func imageBytes(_ size: CGSize, _ color: UIColor) throws -> Data {
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                color.setFill(); context.fill(CGRect(origin: .zero, size: size))
            }
            return try XCTUnwrap(image.pngData())
        }
        let originalImage = try imageBytes(CGSize(width: 640, height: 320), .systemBlue)
        try originalImage.write(to: imageURL)
        let directory = root.appendingPathComponent("Private access"), model = NativeExternalNotesModel(directory: directory)
        let session = try await model.open(noteURL), registry = NativeExternalNotesStore(directory: directory)
        _ = try await registry.mapProject(session.snapshot, selected: root)
        let store = VaultStore()
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        let host = UIHostingController(rootView: NativeExternalEditorScreen(session: session).environmentObject(model).environmentObject(store))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { session.deactivate(); window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        let loaded = ContinuousClock.now + .seconds(5)
        while !containsLoadedChart(host.view), ContinuousClock.now < loaded { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(containsLoadedChart(host.view), "The actual external editor must load the mapped project image")
        let editor = try XCTUnwrap(editor(in: host.view)); editor.layoutIfNeeded()
        XCTAssertTrue(editor.becomeFirstResponder())
        let checkbox = try XCTUnwrap(editor.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Complete: Keep pending edit" })
        checkbox.sendActions(for: .touchUpInside); await session.save()
        let edited = Data(String(decoding: source, as: UTF8.self).replacingOccurrences(of: "- [ ] Keep pending edit", with: "- [x] Keep pending edit").utf8)
        XCTAssertEqual(try Data(contentsOf: noteURL), edited)
        let selection = (editor.text as NSString).range(of: "Before"); editor.selectedRange = selection
        let unchanged = NativeProviderReadGate(url: imageURL); unchanged.requested.isInverted = true
        NSFileCoordinator.addFilePresenter(unchanged)
        await model.refresh()
        await fulfillment(of: [unchanged.requested], timeout: 0.75)
        unchanged.release(); NSFileCoordinator.removeFilePresenter(unchanged)
        XCTAssertTrue(containsLoadedChart(host.view), "An unchanged resource stays visible without redownloading its bytes")
        let replacement = try imageBytes(CGSize(width: 320, height: 640), .systemOrange)
        try replacement.write(to: imageURL, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: imageURL.path)
        let gate = NativeProviderReadGate(url: imageURL)
        NSFileCoordinator.addFilePresenter(gate)
        var holding = true
        defer { if holding { gate.release(); NSFileCoordinator.removeFilePresenter(gate) } }
        await model.refresh()
        await fulfillment(of: [gate.requested], timeout: 5)
        XCTAssertTrue(containsLoadedChart(host.view), "Keep the old external preview visible while its replacement is held by the provider")
        XCTAssertEqual(editor.selectedRange, selection)
        XCTAssertEqual(try Data(contentsOf: noteURL), edited)
        gate.release(); NSFileCoordinator.removeFilePresenter(gate); holding = false
        let refreshed = ContinuousClock.now + .seconds(5)
        while !containsLoadedChart(host.view, width: 320, height: 640), ContinuousClock.now < refreshed { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(containsLoadedChart(host.view, width: 320, height: 640), "A periodic external refresh must deliver a changed same-path image in the open editor")
        XCTAssertTrue(self.editor(in: host.view) === editor)
        XCTAssertEqual(editor.selectedRange, selection)
        editor.undoManager?.undo(); await session.save()
        XCTAssertEqual(try Data(contentsOf: noteURL), source, "The external checkbox Undo must preserve the original BOM and foreign properties")
        editor.undoManager?.redo(); await session.save()
        XCTAssertEqual(try Data(contentsOf: noteURL), edited)
        XCTAssertEqual(try Data(contentsOf: imageURL), replacement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".zerus").path))
        XCTAssertFalse(session.dirty)
    }

    func testCoordinatedResourceReadLetsThePreferredImageMaterializeBeforeUsingAnotherFoldersCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for folder in ["assets", "Work/assets"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        let preferred = root.appendingPathComponent("assets/chart.png"), fallback = root.appendingPathComponent("Work/assets/chart.png")
        let original = Data("# Chart\n\n![Chart](assets/chart.png)".utf8)
        try original.write(to: root.appendingPathComponent("Work/Chart.md"))
        let olderCopy = Data("An older copy in another folder".utf8), materialized = Data("The preferred provider file".utf8)
        try olderCopy.write(to: fallback)
        #if !targetEnvironment(simulator)
        // This phone's coordinator does not notify a presenter for an absent
        // entry. Exercise its real provider placeholder; Simulator also covers
        // materializing an initially missing preferred URL.
        try Data().write(to: preferred)
        #endif
        let presenter = MaterializingImagePresenter(url: preferred, bytes: materialized)
        NSFileCoordinator.addFilePresenter(presenter)
        var presenting = true
        defer { if presenting { NSFileCoordinator.removeFilePresenter(presenter) } }
        let actual = try await VaultFiles(root: root).resourceData("assets/chart.png", notePath: "Work/Chart.md")
        XCTAssertEqual(actual, materialized, "Coordinate the preferred URL before deciding it is unavailable; an existence check must not select another folder's bytes")
        XCTAssertEqual(try Data(contentsOf: fallback), olderCopy)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Chart.md")), original)
        NSFileCoordinator.removeFilePresenter(presenter); presenting = false
        let large = try FileHandle(forWritingTo: preferred)
        try large.truncate(atOffset: UInt64(50 * 1024 * 1024 + 1)); try large.close()
        do { _ = try await VaultFiles(root: root).resourceData("assets/chart.png", notePath: "Work/Chart.md"); XCTFail("A known oversized preferred file must not fall through to another folder's image") }
        catch { XCTAssertTrue(error.localizedDescription.contains("50 MB")) }
        XCTAssertEqual(try Data(contentsOf: fallback), olderCopy)
    }

    func testAFileMaterializedDuringCoordinationCannotEscapeTheVaultThroughASymlink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".png")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        let bytes = Data("Outside the selected vault".utf8); try bytes.write(to: outside)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let location = root.appendingPathComponent("assets/chart.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
        #if !targetEnvironment(simulator)
        try Data().write(to: location)
        #endif
        let presenter = MaterializingImagePresenter(url: location, bytes: Data(), outside: outside)
        NSFileCoordinator.addFilePresenter(presenter); defer { NSFileCoordinator.removeFilePresenter(presenter) }
        do { _ = try await VaultFiles(root: root).resourceData("assets/chart.png", notePath: "Chart.md"); XCTFail("Materializing a file must not grant outside read access") }
        catch { }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: location.path), outside.path, "The presenter must actually introduce the alias during this coordinated read")
        XCTAssertEqual(try Data(contentsOf: outside), bytes)
    }

    @MainActor
    func testWaitingForAProviderImageDoesNotBlockSavingAnUnrelatedTask() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("---\nzerus-id: waiting\n---\n# Waiting\n\n![Chart](assets/chart.png)".utf8).write(to: root.appendingPathComponent("Waiting.md"))
        let imageURL = root.appendingPathComponent("assets/chart.png"), image = Data([1, 2, 3])
        try image.write(to: imageURL)
        let worker = VaultFiles(root: root)
        try await worker.write(".zerus/tasks.json", data: Data(#"{"tasks":[{"id":"image-task","title":"Original task","completed":false}],"foreign":{"keep":true}}"#.utf8), expected: nil)
        let store = VaultStore(); await store.open(root)
        let gate = NativeProviderReadGate(url: imageURL)
        NSFileCoordinator.addFilePresenter(gate)
        defer { gate.release(); NSFileCoordinator.removeFilePresenter(gate) }
        let preview = Task { @MainActor in try? await store.imageData("assets/chart.png", notePath: "Waiting.md", workspace: store.workspaceID) }
        await fulfillment(of: [gate.requested], timeout: 5)
        var task = try XCTUnwrap(store.tasks.first); task.title = "Saved during image download"
        let saved = expectation(description: "An unrelated task saves while the provider image is waiting")
        let save = Task { @MainActor in await store.saveTask(task); saved.fulfill() }
        let result = await XCTWaiter.fulfillment(of: [saved], timeout: 5)
        gate.release(); await save.value
        let loaded = await preview.value
        XCTAssertEqual(result, .completed, "A slow image preview must not occupy the vault's mutation worker")
        XCTAssertEqual(loaded, image)
        let disk = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))) as? [String: Any]
        XCTAssertEqual((disk?["tasks"] as? [[String: Any]])?.first?["title"] as? String, "Saved during image download")
        XCTAssertEqual((disk?["foreign"] as? [String: Bool])?["keep"], true)
    }

    func testSlowProviderReadCanBeCancelledOrTimeOutAndRetriedWithoutLateBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("assets/waiting.png")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let bytes = try XCTUnwrap(image.pngData()); try bytes.write(to: url)
        let note = root.appendingPathComponent("Waiting.md"), source = Data("# Waiting\n\n![Image](assets/waiting.png)".utf8)
        try source.write(to: note)
        let worker = VaultFiles(root: root), project = try NativeExternalProjectFiles(selectedProject: root, source: note)
        enum Preview: Equatable { case bytes(Data), image(Int, Int) }
        let readers: [(String, () async throws -> Preview, Preview)] = [
            ("Vault", { .bytes(try await worker.imagePreviewData("assets/waiting.png", notePath: "Waiting.md")) }, .bytes(bytes)),
            ("External project", { let image = try await project.thumbnail("assets/waiting.png"); return .image(image.width, image.height) }, .image(40, 20))
        ]
        for (name, load, expected) in readers {
            for cancel in [true, false] {
                let gate = NativeProviderReadGate(url: url)
                NSFileCoordinator.addFilePresenter(gate)
                let returned = expectation(description: name + (cancel ? " canceled preview stops waiting" : " slow preview offers recovery"))
                let read = Task { () -> Result<Preview, Error> in
                    let result: Result<Preview, Error>
                    do { result = .success(try await load()) }
                    catch { result = .failure(error) }
                    returned.fulfill(); return result
                }
                await fulfillment(of: [gate.requested], timeout: 5)
                if cancel { read.cancel() }
                let state = await XCTWaiter.fulfillment(of: [returned], timeout: cancel ? 1 : 17)
                gate.release(); NSFileCoordinator.removeFilePresenter(gate)
                let result = await read.value
                XCTAssertEqual(state, .completed, name + " must stop waiting while the real provider is still held")
                switch result {
                case .success: XCTFail(name + " canceled or expired preview must not deliver late output")
                case .failure(let error):
                    if cancel { XCTAssertTrue(error is CancellationError, name) }
                    else if case NativeCoordinatedReadFailure.timedOut = error { }
                    else { XCTFail(name + " must expire with its preview deadline, not an unrelated read failure: \(error)") }
                }
                let retry = try await load()
                XCTAssertEqual(retry, expected, name + " can recover the same resource without reopening its note")
                XCTAssertEqual(try Data(contentsOf: url), bytes)
                XCTAssertEqual(try Data(contentsOf: note), source)
            }
        }
    }

    @MainActor
    private func editor(in view: UIView) -> ZerusTextView? {
        if let value = view as? ZerusTextView { return value }
        return view.subviews.lazy.compactMap { self.editor(in: $0) }.first
    }

    @MainActor
    private func containsLoadedChart(_ view: UIView, width: Int = 640, height: Int = 320) -> Bool {
        if let editor = view as? ZerusTextView, let text = editor.attributedText {
            var loaded = false
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                if let image = (value as? NSTextAttachment)?.image, image.cgImage?.width == width, image.cgImage?.height == height { loaded = true }
            }
            if loaded { return true }
        }
        return view.subviews.contains { containsLoadedChart($0, width: width, height: height) }
    }
}

/// Observes the real coordinated read finishing before the provider supplies a
/// complete file. No loader, clock or thumbnail implementation is substituted.
private final class ImageReadObserver: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    let firstRead = XCTestExpectation(description: "The editor read the initial incomplete image")
    private let lock = NSLock()
    private var reported = false
    init(url: URL) { presentedItemURL = url; super.init(); presentedItemOperationQueue.maxConcurrentOperationCount = 1 }
    func relinquishPresentedItem(toReader reader: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        reader { [self] in
            lock.lock(); let first = !reported; reported = true; lock.unlock()
            if first { firstRead.fulfill() }
        }
    }
}

/// A real file presenter supplies its file when coordinated access asks it to
/// save/materialize. The other candidate already exists with different bytes.
private final class MaterializingImagePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    let bytes: Data
    let outside: URL?
    init(url: URL, bytes: Data, outside: URL? = nil) { presentedItemURL = url; self.bytes = bytes; self.outside = outside; super.init(); presentedItemOperationQueue.maxConcurrentOperationCount = 1 }
    func savePresentedItemChanges(completionHandler: @escaping @Sendable (Error?) -> Void) {
        do {
            if let outside {
                if FileManager.default.fileExists(atPath: presentedItemURL!.path) { try FileManager.default.removeItem(at: presentedItemURL!) }
                try FileManager.default.createSymbolicLink(at: presentedItemURL!, withDestinationURL: outside)
            }
            else { try bytes.write(to: presentedItemURL!, options: .atomic) }
            completionHandler(nil)
        }
        catch { completionHandler(error) }
    }
}

final class NativeProviderReadGate: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    let requested = XCTestExpectation(description: "A coordinated read is waiting on its provider")
    private let semaphore = DispatchSemaphore(value: 0)
    init(url: URL) { presentedItemURL = url; super.init(); presentedItemOperationQueue.maxConcurrentOperationCount = 1 }
    func savePresentedItemChanges(completionHandler: @escaping @Sendable (Error?) -> Void) {
        requested.fulfill(); _ = semaphore.wait(timeout: .now() + 20); completionHandler(nil)
    }
    func release() { semaphore.signal() }
}
