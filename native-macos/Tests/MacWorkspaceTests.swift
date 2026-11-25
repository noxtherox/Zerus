import XCTest
import CoreTransferable
import Combine
import SwiftUI
import AppKit
import Vision
import PDFKit
@testable import Zerus_Native

@MainActor
final class MacWorkspaceTests: XCTestCase {
    func testNoteOpeningReusesCurrentTabUnlessNewTabIsRequested() async throws {
        try await withVault(["A.md": note("a", title: "A"), "B.md": note("b", title: "B"), "C.md": note("c", title: "C")]) { _, store in
            await store.openNote("A.md")
            let count = store.tabs.count
            await store.openNote("B.md")
            XCTAssertEqual(store.tabs.count, count)
            XCTAssertFalse(store.tabs.contains(.note("A.md")))
            XCTAssertEqual(store.activeTab, .note("B.md"))
            await store.openNote("C.md", newTab: true)
            XCTAssertEqual(store.tabs.count, count + 1)
            XCTAssertTrue(store.tabs.contains(.note("B.md")))
            await store.openNote("B.md")
            XCTAssertEqual(store.tabs.count, count + 1, "An already open note activates its existing tab")
            await store.historyStep(-1)
            XCTAssertEqual(store.activeTab, .note("C.md"))
            XCTAssertTrue(store.tabs.contains(.note("B.md")), "Back navigation preserves open tabs")
        }
    }

    func testVaultSettingsImportPreservesTabsFiltersAndFilesAndRefusesAChangedDestination() async throws {
        let suite = "Zerus-vault-import-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let palette = Dictionary(uniqueKeysWithValues: MacThemeRole.allCases.map { ($0.rawValue, "#123456") })
        let object: [String: Any] = ["format":"zerus-desktop-settings", "version":1,
            "vault":["name":"Selected Vault", "defaultNoteFolder":"Work/Research", "folderOrder":["Work", "Work/Research", "Inbox", "Absent"], "keptOpenFolders":["Work/Research", "Absent"], "hideSubtypeNotes":true],
            "settings":["dateFormat":"MM/DD/YYYY", "interfaceZoom":125, "noteWidth":60, "noteAlignment":"left", "codeBlocks":true, "noteLinkShortcuts":false, "appearance":"dark", "lightTheme":palette, "darkTheme":palette, "savedThemes":[]]]
        let data = try JSONSerialization.data(withJSONObject: object)
        try await withVault(["Inbox/A.md":"# A\n", "Work/Parent.md":"# Parent\n", "Work/Research/B.md":"# B\n"]) { root, store in
            await store.openCollection("Work", folder: true)
            store.query = "Parent"; store.collapsedFolders = ["Work"]
            let tabs = store.tabs, selection = store.selection
            let before = try store.vaultSettingsStamp()
            let review = try MacDesktopSettingsReview(data: data, name: "Vault.json", defaults: defaults, workspace: store)
            XCTAssertEqual(try store.vaultSettingsStamp(), before, "Review and Cancel are read-only")
            XCTAssertEqual(review.vaultReview?.missing, ["Absent", "Absent"])
            store.keptFolders = ["Inbox"]
            XCTAssertThrowsError(try review.apply(defaults: defaults)) { XCTAssertTrue($0.localizedDescription.contains("changed after review")) }
            XCTAssertNil(defaults.object(forKey: "zerus.mac.dateFormat"), "Vault conflict is checked before app-wide writes")
            let fresh = try MacDesktopSettingsReview(data: data, name: "Vault.json", defaults: defaults, workspace: store)
            try fresh.apply(defaults: defaults)
            XCTAssertEqual(store.defaultNoteFolder, "Work/Research")
            XCTAssertEqual(store.orderedFolders, ["Work", "Work/Research", "Inbox"])
            XCTAssertEqual(store.keptFolders, ["Work/Research"]); XCTAssertFalse(store.collapsedFolders.contains("Work"))
            XCTAssertTrue(store.hideSubtypes); XCTAssertEqual(store.query, "Parent")
            XCTAssertEqual(store.tabs, tabs); XCTAssertEqual(store.selection, selection)
            await store.openCollection("Work/Research", folder: true)
            XCTAssertTrue(store.hideSubtypes, "An unvisited folder uses the imported global desktop visibility")
            let reopened = MacWorkspace(); await reopened.openVault(root)
            XCTAssertEqual(reopened.defaultNoteFolder, "Work/Research")
            XCTAssertEqual(reopened.orderedFolders, ["Work", "Work/Research", "Inbox"])
            XCTAssertEqual(reopened.keptFolders, ["Work/Research"]); XCTAssertTrue(reopened.hideSubtypes)
            let staleVault = try MacDesktopSettingsReview(data: data, name: "Vault.json", defaults: defaults, workspace: store)
            await store.openVault(root)
            XCTAssertThrowsError(try staleVault.apply(defaults: defaults)) { XCTAssertTrue($0.localizedDescription.contains("changed after review")) }
            for (path, text) in ["Inbox/A.md":"# A\n", "Work/Parent.md":"# Parent\n", "Work/Research/B.md":"# B\n"] {
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(text.utf8))
            }
        }
    }

    func testWorkspaceSearchFieldsTakePointerFocusAndTypingAtInterfaceZoom() async throws {
        let suite = "Zerus-search-pointer-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        for (mode, zooms) in [("List", [80, 90, 100, 110, 125, 150]), ("Gallery", [80, 90, 100, 110, 125, 150]), ("Tasks", [100, 150]), ("External Notes", [100, 150])] { for zoom in zooms {
            preferences.set(zoom, forKey: "zerus.mac.interfaceZoom")
            try await withVault(["Work/Alpha.md": "# Alpha\n", "Work/Beta.md": "# Beta\n"]) { root, store in
                let standalone = mode == "Tasks" || mode == "External Notes"
                await store.openCollection(standalone ? mode : "Work", folder: !standalone)
                if !standalone { store.viewMode = mode }
                let host = NSHostingView(rootView: MacZoomViewport { MacWorkspaceView(store: store) }.defaultAppStorage(preferences))
                let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 960, height: 850), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
                defer { window.contentView = nil; window.close() }
                func settle() async throws {
                    for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
                }
                func descendants(_ node: NSView) -> [NSView] { [node] + node.subviews.flatMap(descendants) }
                try await settle()
                let placeholder = mode == "Tasks" ? "Search tasks…" : mode == "External Notes" ? "Search filenames or paths" : "Search notes…"
                let search = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextField }.first { $0.placeholderString == placeholder && !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty })
                window.makeFirstResponder(nil)
                let point = search.convert(NSPoint(x: search.bounds.midX, y: search.bounds.midY), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                    window.sendEvent(event)
                }
                try await settle()
                guard let fieldEditor = window.firstResponder as? NSTextView, fieldEditor.isFieldEditor else {
                    XCTFail("A pointer click must focus collection search at \(zoom)% in \(mode)"); return
                }
                for (key, code): (String, UInt16) in [("a", 0), ("l", 37), ("p", 35), ("h", 4), ("a", 0)] {
                    for type in [NSEvent.EventType.keyDown, .keyUp] {
                        let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
                        window.sendEvent(event)
                    }
                }
                try await settle()
                XCTAssertEqual(fieldEditor.string, "alpha", "Keystrokes must reach search at \(zoom)% in \(mode)")
                if !standalone {
                    XCTAssertEqual(store.query, "alpha")
                    XCTAssertEqual(store.collection.map(\.path), ["Work/Alpha.md"])
                }
                XCTAssertTrue(window.firstResponder === fieldEditor, "Filtering must keep search focus")
                XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/Alpha.md"), encoding: .utf8), "# Alpha\n")
                XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/Beta.md"), encoding: .utf8), "# Beta\n")
            }
        } }
    }

    func testNoteActivationFocusesEditorWithoutStealingSearchFocus() async throws {
        let alpha = "\u{feff}---\r\nzerus-id: focus-alpha\r\nforeign: keep\r\n---\r\n# Alpha\r\n\r\nAlpha body.\r\n"
        let beta = "# Beta\n\nBeta body.\n"
        try await withVault(["Work/Alpha.md": alpha, "Work/Beta.md": beta]) { root, store in
            await store.openCollection("Work", folder: true); store.viewMode = "List"
            let host = NSHostingView(rootView: MacWorkspaceView(store: store))
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
            defer { window.contentView = nil; window.close() }
            func settle() async throws {
                for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
            }
            func descendants(_ node: NSView) -> [NSView] { [node] + node.subviews.flatMap(descendants) }
            func editor() throws -> NSTextView {
                try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first { $0.isEditable && !$0.isFieldEditor })
            }
            try await settle()
            await store.openNote("Work/Alpha.md"); try await settle()
            var text = try editor()
            XCTAssertTrue(window.firstResponder === text, "Opening a note must direct immediate typing to its editor")
            let search = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Search notes…" })
            XCTAssertTrue(window.makeFirstResponder(search))
            let searchResponder = window.firstResponder
            store.query = "Alpha"; host.setFrameSize(NSSize(width: 1350, height: 850)); try await settle()
            XCTAssertTrue(window.firstResponder === searchResponder, "Search and layout updates must not repeat the activation focus request")
            await store.openNote("Work/Alpha.md"); try await settle()
            XCTAssertTrue(window.firstResponder === text, "Explicitly activating the current note must return focus from search")
            store.query = ""; try await settle()
            await store.openNote("Work/Beta.md"); try await settle()
            text = try editor()
            XCTAssertTrue(window.firstResponder === text, "A newly created editor needs its own activation focus")
            if let target = window.firstResponder as? NSTextView {
                target.setSelectedRange(NSRange(location: target.string.utf16.count, length: 0))
                target.insertText("Focused", replacementRange: target.selectedRange()); target.breakUndoCoalescing()
            }
            try await settle()
            XCTAssertEqual(store.body, "# Beta\n\nBeta body.\nFocused")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Alpha.md")), Data(alpha.utf8))
            text.undoManager?.undo(); try await settle()
            XCTAssertEqual(store.body, beta)
            store.viewMode = "Gallery"; store.browsingCollection = true; try await settle()
            let browsingSearch = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Search notes…" })
            XCTAssertTrue(window.makeFirstResponder(browsingSearch))
            store.query = "Beta"; try await settle()
            store.browsingCollection = false; try await settle()
            XCTAssertTrue(window.firstResponder === text, "Back to note must resume typing after collection search held focus")
            store.query = ""
            await store.openCollection("Work", folder: true); try await settle()
            let collectionSearch = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Search notes…" })
            XCTAssertTrue(window.makeFirstResponder(collectionSearch))
            let collectionResponder = window.firstResponder
            store.query = "Beta"; try await settle()
            XCTAssertTrue(window.firstResponder === collectionResponder, "A suspended note must not reclaim collection search focus")
            XCTAssertNil(store.current)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Beta.md")), Data(beta.utf8))
        }
    }

    func testOpenNoteUndoSurvivesCollectionAndTabNavigation() async throws {
        let source = "---\nzerus-id: navigation-undo-a\nforeign: keep\n---\n# A\n\nAlpha\n"
        let sourceB = "# B\n\nBeta\n\n![Live image](../pixel.png)\n"
        try await withVault(["Work/A.md": source, "Work/B.md": sourceB]) { root, store in
            func pixels(blue: Bool) throws -> Data {
                let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
                context.setFillColor(blue ? CGColor(red: 0, green: 0, blue: 1, alpha: 1) : CGColor(red: 0, green: 1, blue: 0, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
                return try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage())).representation(using: .png, properties: [:]))
            }
            try pixels(blue: false).write(to: root.appendingPathComponent("pixel.png"))
            await store.openCollection("Work", folder: true); store.viewMode = "Gallery"
            await store.openNote("Work/A.md")
            let host = NSHostingView(rootView: MacWorkspaceView(store: store))
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            func settle() async throws {
                for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
            }
            func editor(_ node: NSView) -> NSTextView? {
                if let text = node as? NSTextView, text.isEditable { return text }
                return node.subviews.lazy.compactMap(editor).first
            }
            try await settle()
            do {
                let first = try XCTUnwrap(editor(host))
                let alpha = (first.string as NSString).range(of: "Alpha")
                guard alpha.location != NSNotFound else { XCTFail("Missing initial editable body"); return }
                first.setSelectedRange(NSRange(location: NSMaxRange(alpha), length: 0))
                first.insertText("!", replacementRange: first.selectedRange()); first.breakUndoCoalescing()
            }
            try await settle()
            XCTAssertEqual(store.body, "# A\n\nAlpha!\n")
            let saved = await store.save(); XCTAssertTrue(saved)
            await store.openCollection("Work", folder: true)
            try await settle()
            XCTAssertNil(store.current, "Collection navigation must retain its own command scope")
            NotificationCenter.default.post(name: .macEditorAction, object: MacEditorCommand(scope: store.workspaceID, path: "Work/A.md", action: "quote"))
            try await settle()
            XCTAssertEqual(store.body, "", "A hidden editor must not publish into the collection's draft")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.replacingOccurrences(of: "Alpha", with: "Alpha!").utf8))
            await store.openNote("Work/A.md")
            try await settle()
            var current = try XCTUnwrap(editor(host))
            XCTAssertTrue(current.undoManager?.canUndo == true, "Returning from the collection must retain the open note's edit history")
            current.undoManager?.undo(); try await settle()
            XCTAssertEqual(store.body, "# A\n\nAlpha\n")
            let undoneSaved = await store.save(); XCTAssertTrue(undoneSaved)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(source.utf8))
            current.undoManager?.redo(); try await settle()
            XCTAssertEqual(store.body, "# A\n\nAlpha!\n")
            await store.openNote("Work/B.md", newTab: true); try await settle()
            let beta = try XCTUnwrap(editor(host)), betaRange = (beta.string as NSString).range(of: "Beta")
            guard betaRange.location != NSNotFound else { XCTFail("Missing second note body"); return }
            beta.setSelectedRange(NSRange(location: NSMaxRange(betaRange), length: 0)); beta.insertText("!", replacementRange: beta.selectedRange()); beta.breakUndoCoalescing()
            try await settle()
            await store.openNote("Work/A.md"); try await settle()
            current = try XCTUnwrap(editor(host))
            current.undoManager?.undo(); try await settle()
            XCTAssertEqual(store.body, "# A\n\nAlpha\n", "A different open tab must not discard this note's history")
            let finalSaved = await store.save(); XCTAssertTrue(finalSaved)
            await store.openCollection("Work", folder: true); try await settle()
            let outside = source.replacingOccurrences(of: "Alpha", with: "Outside")
            try Data(outside.utf8).write(to: root.appendingPathComponent("Work/A.md"))
            await store.refresh(); await store.openNote("Work/A.md"); try await settle()
            current = try XCTUnwrap(editor(host))
            XCTAssertEqual(store.body, "# A\n\nOutside\n")
            XCTAssertFalse(current.undoManager?.canUndo == true, "A changed saved body must invalidate retained native history")
            let end = (current.string as NSString).range(of: "Outside")
            guard end.location != NSNotFound else { XCTFail("Missing adopted outside body"); return }
            current.setSelectedRange(NSRange(location: NSMaxRange(end), length: 0))
            current.insertText("!", replacementRange: current.selectedRange()); current.breakUndoCoalescing()
            try await settle()
            let outsideSaved = await store.save(); XCTAssertTrue(outsideSaved)
            await store.closeTab(.note("Work/A.md")); try await settle()
            await store.openNote("Work/B.md"); try await settle()
            current = try XCTUnwrap(editor(host))
            await store.openNote("Work/A.md", newTab: true); try await settle()
            current = try XCTUnwrap(editor(host))
            XCTAssertEqual(store.body, "# A\n\nOutside!\n")
            XCTAssertFalse(current.undoManager?.canUndo == true, "Closing a tab releases its live edit history")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(outside.replacingOccurrences(of: "Outside", with: "Outside!").utf8))
            try pixels(blue: true).write(to: root.appendingPathComponent("pixel.png"))
            await store.openNote("Work/B.md"); try await settle()
            let imageEditor = try XCTUnwrap(editor(host))
            func expectBlue() throws {
                var image: NSImage?
                imageEditor.attributedString().enumerateAttribute(.attachment, in: NSRange(location: 0, length: imageEditor.attributedString().length)) { value, _, _ in
                    if let attachment = value as? MacImageAttachment { image = attachment.image }
                }
                let cg = try XCTUnwrap(image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let color = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
                XCTAssertGreaterThan(color.blueComponent, 0.8, "Retained editors must refresh changed image resources")
                XCTAssertGreaterThan(color.blueComponent, color.greenComponent + 0.3)
            }
            try expectBlue()
            imageEditor.undoManager?.undo(); try await settle()
            XCTAssertEqual(store.body, "# B\n\nBeta\n\n![Live image](../pixel.png)\n")
            try expectBlue()
            let imageNoteSaved = await store.save(); XCTAssertTrue(imageNoteSaved)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/B.md")), Data(sourceB.utf8))
            await store.openNote("Work/A.md"); try await settle()
            current = try XCTUnwrap(editor(host))
            let otherRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-Undo-vault-" + UUID().uuidString)
            var otherDrafts: URL?
            defer {
                UserDefaults.standard.removeObject(forKey: MacNavigationState.key(otherRoot))
                UserDefaults.standard.removeObject(forKey: MacNewNotePreferences.key(otherRoot))
                UserDefaults.standard.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(otherRoot.path))
                if let otherDrafts { try? FileManager.default.removeItem(at: otherDrafts) }
                try? FileManager.default.removeItem(at: otherRoot)
            }
            let outsideEnd = (current.string as NSString).range(of: "Outside!")
            guard outsideEnd.location != NSNotFound else { XCTFail("Missing reopened body"); return }
            current.setSelectedRange(NSRange(location: NSMaxRange(outsideEnd), length: 0))
            current.insertText("?", replacementRange: current.selectedRange()); current.breakUndoCoalescing()
            try await settle()
            let beforeSwitchSaved = await store.save(); XCTAssertTrue(beforeSwitchSaved)
            XCTAssertTrue(current.undoManager?.canUndo == true)
            let sameBytes = try Data(contentsOf: root.appendingPathComponent("Work/A.md")), oldScope = store.workspaceID
            try FileManager.default.createDirectory(at: otherRoot.appendingPathComponent("Work"), withIntermediateDirectories: true)
            try sameBytes.write(to: otherRoot.appendingPathComponent("Work/A.md"))
            await store.openVault(otherRoot); otherDrafts = store.taskDraftStore?.directory
            await store.openNote("Work/A.md"); try await settle()
            current = try XCTUnwrap(editor(host))
            XCTAssertEqual(store.body, "# A\n\nOutside!?\n")
            XCTAssertFalse(current.undoManager?.canUndo == true, "A new vault cannot inherit history even when path and saved bytes match")
            NotificationCenter.default.post(name: .macEditorAction, object: MacEditorCommand(scope: oldScope, path: "Work/A.md", action: "quote"))
            try await settle()
            XCTAssertEqual(store.body, "# A\n\nOutside!?\n", "Commands from the previous vault must be inert")
            XCTAssertEqual(try Data(contentsOf: otherRoot.appendingPathComponent("Work/A.md")), sameBytes)
            await store.openVault(root); try await settle()
            store.changed("- First\n- Second\n")
            let listSaved = await store.save(); XCTAssertTrue(listSaved)
            try await settle()
            current = try XCTUnwrap(editor(host))
            let text = current.string as NSString, firstRange = text.range(of: "First"), secondRange = text.range(of: "Second")
            guard firstRange.location != NSNotFound, secondRange.location != NSNotFound else { XCTFail("Missing composition fixture items"); return }
            let composition = NSRange(location: firstRange.location + 2, length: secondRange.location + 2 - firstRange.location - 2)
            current.setSelectedRange(composition)
            current.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: composition)
            XCTAssertTrue(current.hasMarkedText())
            await store.openCollection("Work", folder: true); try await settle()
            await store.openNote("Work/A.md"); try await settle()
            current = try XCTUnwrap(editor(host))
            XCTAssertFalse(current.hasMarkedText(), "Unfinished input must not be revived in a reopened note")
            XCTAssertEqual(current.string, "• First\n• Second\n")
            XCTAssertEqual(store.body, "- First\n- Second\n")
        }
    }

    func testTextFilePreviewRefusesInvalidEncodingAndKeepsBomAndOutsideEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-text-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bom = Data([0xef, 0xbb, 0xbf])
        for (name, bytes, visible) in [
            ("plain.txt", Data("Original\r\n".utf8), "Original\r\n" as String?),
            ("bom.txt", bom + Data("Original café\r\n".utf8), "Original café\r\n"),
            ("double.md", bom + bom + Data("Original\r\n".utf8), "\u{feff}Original\r\n"),
            ("invalid.txt", Data([0xff, 0xfe, 0x41, 0x00]), nil)
        ] {
            let file = root.appendingPathComponent(name); try bytes.write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600, .creationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: file.path)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let draft = MacFilePreviewDraft(url: file); draft.load()
            if let visible {
                XCTAssertEqual(draft.text, visible, name); XCTAssertTrue(draft.canSave)
                draft.save()
                XCTAssertEqual(try Data(contentsOf: file), bytes, "Opening and saving must retain the original BOM spelling")
                draft.text = "Edited café.\r\n"; draft.save()
                let prefix = bytes.starts(with: bom) ? bom : Data()
                XCTAssertEqual(try Data(contentsOf: file), prefix + Data("Edited café.\r\n".utf8), name)
                let after = try FileManager.default.attributesOfItem(atPath: file.path)
                XCTAssertEqual(after[.posixPermissions] as? NSNumber, attributes[.posixPermissions] as? NSNumber)
                XCTAssertEqual(after[.creationDate] as? Date, attributes[.creationDate] as? Date)
                let outside = Data("Outside current file\n".utf8); try outside.write(to: file)
                draft.text = "Private draft"; draft.save()
                XCTAssertEqual(try Data(contentsOf: file), outside); XCTAssertEqual(draft.text, "Private draft")
                XCTAssertTrue(draft.issue?.contains("changed") == true)
            } else {
                XCTAssertFalse(draft.canSave, "Undecodable bytes must never be eligible for an empty save")
                XCTAssertTrue(draft.issue?.contains("UTF-8") == true)
                draft.text = "Never overwrite unsupported bytes"; draft.save()
                XCTAssertEqual(try Data(contentsOf: file), bytes)
                let host = NSHostingView(rootView: MacFilePreview(url: file))
                let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 800, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
                defer { window.contentView = nil; window.close() }
                for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
                func hasEditor(_ view: NSView) -> Bool { view is NSTextView || view.subviews.contains(where: hasEditor) }
                XCTAssertFalse(hasEditor(host), "SwiftUI disabled TextEditor still accepts typing; unsupported data must not create a writable control")
            }
        }
    }

    func testExportCapturesTheVisibleDraftAndPropertyChoiceWithoutSavingOrFollowingLaterEdits() async throws {
        let original = "\u{feff}---\r\nzerus-id: 70000000-0000-4000-8000-000000000291\r\nOwner: VISIBLEPROPERTY\r\n---\r\n# Saved export\r\n\r\nSAVED-BODY\r\n"
        try await withVault(["Note.md": original]) { root, store in
            await store.openNote("Note.md")
            let draft = "# Draft export\r\n\r\nDRAFT-SNAPSHOT\r\n\r\n| A | B |\r\n| --- | --- |\r\n| One | Two |\r\n"
            store.changed(draft)
            let outside = original.replacingOccurrences(of: "SAVED-BODY", with: "OUTSIDE-DISK")
            try Data(outside.utf8).write(to: root.appendingPathComponent("Note.md"))
            await store.refresh()
            XCTAssertNotNil(store.noteDiskChange, "The real outside edit must block autosave before testing a retained draft export")
            XCTAssertEqual(store.body, draft)
            let request = MacExportRequest(note: try XCTUnwrap(store.current), body: store.body, root: root)
            // Both the note menu and native Print command capture this same
            // retained draft without saving it or replacing an open sheet.
            store.presentPrint()
            let print = try XCTUnwrap(store.printRequest)
            XCTAssertTrue(store.editorSheetActive)
            store.changed(draft + "LATER-EDIT\r\n")
            store.presentPrint()
            XCTAssertEqual(store.printRequest?.id, print.id)
            let printed = try await MacExport.preparePrint(print)
            let printedText = try XCTUnwrap(printed.document.string)
            XCTAssertTrue(printedText.contains("DRAFT-SNAPSHOT"))
            for absent in ["SAVED-BODY", "OUTSIDE-DISK", "LATER-EDIT", "VISIBLEPROPERTY", "zerus-id"] { XCTAssertFalse(printedText.contains(absent), absent) }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Note.md")), Data(outside.utf8))
            store.printRequest = nil; store.editorSheetActive = false
            store.busy = true; store.presentPrint(); XCTAssertNil(store.printRequest)
            store.busy = false
            await store.updateCollectionLayout(store.collectionLayout, mode: "Gallery")
            XCTAssertNotNil(store.selection, "Switching views retains the note for Back to note")
            store.presentPrint(); XCTAssertNil(store.printRequest, "Gallery must not print the retained hidden note")
            await store.openNote("Note.md")
            store.presentPrint(); XCTAssertNotNil(store.printRequest, "Returning to the note restores Print")
            store.printRequest = nil; store.editorSheetActive = false
            for includeProperties in [false, true] { for format in NativeExportFormat.allCases {
                let url = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + "." + format.rawValue)
                defer { try? FileManager.default.removeItem(at: url) }
                let warnings = try await MacExport.write(request, format: format, includeProperties: includeProperties, to: url)
                XCTAssertTrue(warnings.isEmpty)
                let text: String
                switch format {
                case .html: text = try String(contentsOf: url, encoding: .utf8)
                case .pdf: text = try XCTUnwrap(PDFKit.PDFDocument(url: url)?.string)
                case .docx:
                    let pipe = Pipe(), process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    process.arguments = ["-p", url.path, "word/document.xml"]; process.standardOutput = pipe
                    try process.run(); text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); process.waitUntilExit()
                    XCTAssertEqual(process.terminationStatus, 0)
                }
                XCTAssertTrue(text.contains("DRAFT-SNAPSHOT"), "\(format) must export the visible retained draft, not the saved baseline")
                for absent in ["SAVED-BODY", "OUTSIDE-DISK", "LATER-EDIT", "zerus-id", "70000000-0000-4000-8000-000000000291"] { XCTAssertFalse(text.contains(absent), "\(format): \(absent)") }
                XCTAssertEqual(text.contains("VISIBLEPROPERTY"), includeProperties, "The chosen property policy must reach \(format)")
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Note.md")), Data(outside.utf8), "Export must not save over the outside edit")
                XCTAssertEqual(store.body, draft + "LATER-EDIT\r\n", "Export must not replace or follow later editor text")
            } }
            let recovery = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + "-retained.md")
            defer { try? FileManager.default.removeItem(at: recovery) }
            try store.exportRetainedNote(to: recovery)
            try await store.useSavedNoteAfterExport()
            await store.openCollection("All Notes")
            store.presentPrint(); XCTAssertNil(store.printRequest, "Collection-only focus must not print a retained hidden note")
        }
    }
    func testLargeNoteListLoadsMoreWithoutLimitingSelectionAndResetsForSearch() async throws {
        let files = Dictionary(uniqueKeysWithValues: (0..<300).map { index in
            let label = String(format: "%04d", index)
            return ("Work/" + label + ".md", note(label, title: "Note " + label))
        })
        try await withVault(files) { root, store in
            await store.openCollection("All Notes")
            var filters = store.filters; filters.sort = .titleAscending; store.changeCollectionFilters(filters)
            store.inspector = false
            let host = NSHostingView(rootView: MacWorkspaceView(store: store).background(Color.white).environment(\.colorScheme, .light))
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            func settle() async throws {
                for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
            }
            func scrollViews(_ view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            try await settle()
            let scroll = try XCTUnwrap(scrollViews(host).first { $0.bounds.width >= 250 && $0.bounds.width <= 340 && $0.bounds.height > 400 })
            let document = try XCTUnwrap(scroll.documentView)
            let initialHeight = document.bounds.height
            XCTAssertEqual(store.collection.count, 300)
            XCTAssertLessThan(initialHeight, 10_000, "The first screen must not inventory the entire 300-row list")
            store.selectAllCollectionNotes()
            XCTAssertEqual(store.selectedPaths.count, 300, "All includes pages that have not been revealed")
            store.clearCollectionSelection()
            try await settle()
            for _ in 0..<12 {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await settle()
            }
            XCTAssertGreaterThan(document.bounds.height, initialHeight + 10_000, "Scrolling must expose the remaining pages")
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.cgImage)
            let attachment = XCTAttachment(image: NSImage(cgImage: image, size: .zero)); attachment.name = "Progressive native note list final page"; attachment.lifetime = .keepAlways; add(attachment)
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            let box = try XCTUnwrap(request.results?.first { $0.topCandidates(1).first?.string == "Note 0299" }?.boundingBox)
            let point = host.convert(NSPoint(x: box.midX * host.bounds.width, y: (host.isFlipped ? 1 - box.midY : box.midY) * host.bounds.height), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                NSApp.postEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)), atStart: false)
            }
            try await settle()
            XCTAssertEqual(store.selection, "Work/0299.md", "A row revealed by scrolling keeps its ordinary open action")
            store.selectAllCollectionNotes()
            XCTAssertEqual(store.selectedPaths.count, 300, "All applies to every filtered result, including unrevealed pages")
            store.query = "Note 0299"
            try await settle()
            XCTAssertEqual(store.collection.map(\.path), ["Work/0299.md"])
            XCTAssertLessThan(scroll.contentView.bounds.origin.y, 2)
            store.query = ""
            try await settle()
            XCTAssertEqual(store.collection.count, 300)
            XCTAssertLessThan(document.bounds.height, 10_000, "Clearing search starts a new bounded result list")
            XCTAssertLessThan(scroll.contentView.bounds.origin.y, 2)
            XCTAssertTrue(store.selectedPaths.isEmpty)
            for _ in 0..<6 {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                scroll.reflectScrolledClipView(scroll.contentView); try await settle()
            }
            XCTAssertGreaterThan(document.bounds.height, 10_000, "The filter control starts from an expanded list")
            filters.sort = .titleDescending; store.changeCollectionFilters(filters)
            try await settle()
            XCTAssertEqual(store.collection.first?.path, "Work/0299.md")
            XCTAssertLessThan(document.bounds.height, 10_000, "Changing filter order starts a bounded list")
            XCTAssertLessThan(scroll.contentView.bounds.origin.y, 2)
            for _ in 0..<6 {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                scroll.reflectScrolledClipView(scroll.contentView); try await settle()
            }
            XCTAssertGreaterThan(document.bounds.height, 10_000, "The activation control starts from an expanded list")
            await store.openVault(root); await store.refresh()
            try await settle()
            XCTAssertLessThan(document.bounds.height, 10_000, "A new vault activation must not reuse the previous page budget")
            XCTAssertLessThan(scroll.contentView.bounds.origin.y, 2)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/0299.md"), encoding: .utf8), files["Work/0299.md"])
        }
    }

    func testGalleryLoadsMoreWithoutLimitingSelectionAndResetsForSearch() async throws {
        let files = Dictionary(uniqueKeysWithValues: (0..<300).map { index in
            let label = String(format: "%04d", index)
            return ("Work/" + label + ".md", note(label, title: "Note " + label).replacingOccurrences(of: "zerus-id:", with: "Status: Ready\nzerus-id:"))
        })
        try await withVault(files) { root, store in
            await store.openCollection("All Notes")
            var filters = store.filters; filters.sort = .titleAscending; store.changeCollectionFilters(filters)
            store.viewMode = "Gallery"
            for (grouping, width): (String?, CGFloat) in [(nil, 900), ("Status", 900), (nil, 1600), ("Status", 1600)] {
                store.collectionLayout.groupBy = grouping
                store.clearCollectionSelection()
                let host = NSHostingView(rootView: MacWorkspaceView(store: store))
                let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: width, height: 976), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
                defer { window.contentView = nil; window.close() }
                func settle() async throws {
                    for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
                }
                func scrollViews(_ view: NSView) -> [NSScrollView] {
                    (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
                }
                try await settle()
                let scroll = try XCTUnwrap(scrollViews(host).first { $0.bounds.width > 400 && $0.bounds.height > 400 })
                let document = try XCTUnwrap(scroll.documentView), initialHeight = document.bounds.height
                XCTAssertEqual(store.collection.count, 300)
                XCTAssertLessThan(initialHeight, 3000, "The initial gallery must not lay out the entire 300-card inventory")
                // Scroll before changing selection: selection updates must not
                // be needed to refresh a page footer or reveal later cards.
                for _ in 0..<12 {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                    scroll.reflectScrolledClipView(scroll.contentView); try await settle()
                }
                XCTAssertGreaterThan(document.bounds.height, initialHeight + 2000, "Scrolling must reveal the remaining cards")
                XCTAssertEqual(store.collection.last?.path, "Work/0299.md")
                store.query = "Note 0299"; try await settle()
                XCTAssertEqual(store.collection.map(\.path), ["Work/0299.md"])
                XCTAssertLessThan(document.bounds.height, 1500)
                XCTAssertLessThan(scroll.contentView.bounds.origin.y, 2)
                store.query = ""; try await settle()
                XCTAssertEqual(store.collection.count, 300)
                XCTAssertLessThan(document.bounds.height, 3000, "A new result set resets the gallery page budget")
                XCTAssertLessThan(scroll.contentView.bounds.origin.y, 2)
                store.selectAllCollectionNotes(); XCTAssertEqual(store.selectedPaths.count, 300)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/0299.md")), Data(files["Work/0299.md"]!.utf8))
            }
        }
    }

    func testFolderIconsPreserveSharedMetadataAndRefuseStaleOrChangedVaultReviews() async throws {
        let icons = #"{"Work":"tabler:Microscope","Work/Child":"📚","Other":"tabler:Dog","future":{"keep":true,"text":"\uFEFFkeep"},"Café":"tabler:Book","Cafe\u0301":"tabler:Flask"}"#
        try await withVault(["Work/A.md": note("icon-a", title: "A"), "Work/Child/B.md": note("icon-b", title: "B"), "Other/C.md": note("icon-c", title: "C"), ".zerus/type-icons.json": icons]) { root, store in
            await store.openNote("Work/A.md")
            let body = store.body, path = root.appendingPathComponent(".zerus/type-icons.json")
            let noteBytes = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
            XCTAssertEqual(store.folderIcon("Work"), "tabler:Microscope")
            XCTAssertEqual(store.folderIcon("Work/Child"), "📚")
            let peer = MacWorkspace(); await peer.openVault(root); await peer.refresh()
            let review = try await store.folderIconReview(.init(folder: "Work", workspaceID: store.workspaceID))
            try await store.changeFolderIcon(review, folder: "Work", value: "tabler:Flask")
            XCTAssertEqual(store.folderIcon("Work"), "tabler:Flask")
            XCTAssertEqual(peer.folderIcon("Work"), "tabler:Flask", "Peer artwork updates without replacing its editor")
            XCTAssertEqual(store.body, body); XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), noteBytes)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
            XCTAssertEqual(object["Work/Child"] as? String, "📚"); XCTAssertEqual(object["Other"] as? String, "tabler:Dog")
            XCTAssertEqual((object["future"] as? [String: Any])?["keep"] as? Bool, true)
            struct ForeignEnvelope: Decodable { struct Future: Decodable { let text: String }; let future: Future }
            XCTAssertEqual(try JSONDecoder().decode(ForeignEnvelope.self, from: Data(contentsOf: path)).future.text, "\u{feff}keep", "An unrelated string keeps its leading BOM scalar")
            XCTAssertEqual(try Data(contentsOf: path), Data(icons.replacingOccurrences(of: #""Work":"tabler:Microscope""#, with: #""Work":"tabler:Flask""#).utf8), "Only the selected value changes; unknown JSON tokens keep exact bytes")
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? NSDictionary)
            XCTAssertEqual(raw.object(forKey: "Caf\u{e9}" as NSString) as? String, "tabler:Book")
            XCTAssertEqual(raw.object(forKey: "Cafe\u{301}" as NSString) as? String, "tabler:Flask", "Unrelated Unicode-equivalent JSON keys retain their distinct bytes and values")
            let exact = try await store.folderIconReview(.init(folder: "Work", workspaceID: store.workspaceID))
            XCTAssertEqual(exact.icon("Caf\u{e9}"), "tabler:Book"); XCTAssertEqual(exact.icon("Cafe\u{301}"), "tabler:Flask")
            let stale = try await store.folderIconReview(.init(folder: "Work", workspaceID: store.workspaceID))
            let outside = Data(#"{"Work":"tabler:Coffee","Work/Child":"📚","Other":"tabler:Dog","future":{"keep":true}}"#.utf8)
            try outside.write(to: path)
            do { try await store.changeFolderIcon(stale, folder: "Work", value: nil); XCTFail("A stale picker must not replace another client's icon") } catch { XCTAssertTrue(error.localizedDescription.contains("type-icons.json changed outside Zerus")) }
            XCTAssertEqual(try Data(contentsOf: path), outside)
            await store.refresh(); XCTAssertEqual(store.folderIcon("Work"), "tabler:Coffee")
            let fresh = try await store.folderIconReview(.init(folder: "Work", workspaceID: store.workspaceID))
            try await store.changeFolderIcon(fresh, folder: "Work", value: nil)
            XCTAssertNil(store.folderIcon("Work")); XCTAssertEqual(peer.folderIcon("Work/Child"), "📚")
            let reset = try Data(contentsOf: path)
            let wrongVault = MacFolderIconRequest(folder: "Work", workspaceID: UUID())
            do { _ = try await store.folderIconReview(wrongVault); XCTFail("A changed vault refuses the picker") } catch { XCTAssertTrue(error.localizedDescription.contains("vault or folder changed")) }
            XCTAssertEqual(try Data(contentsOf: path), reset)
            let malformed = Data("[]".utf8); try malformed.write(to: path)
            await store.refresh(); XCTAssertNotNil(store.folderIconIssue)
            do { _ = try await store.folderIconReview(.init(folder: "Work", workspaceID: store.workspaceID)); XCTFail("Unsupported metadata is not replaced") } catch { XCTAssertTrue(error.localizedDescription.contains("icon file has an unsupported format")) }
            XCTAssertEqual(try Data(contentsOf: path), malformed)
            try reset.write(to: path); await store.refresh()
            await store.createFolder("Recipes")
            XCTAssertEqual(store.folderIcon("Recipes"), "tabler:ChefHat", "New folders use the desktop concept suggestions")
            XCTAssertEqual(store.folderIcon("Work/Child"), "📚")
            let catalog = MacFolderIconCatalog.shared
            XCTAssertNotNil(catalog.image("tabler:ChefHat"), "The app contains renderable offline artwork")
            XCTAssertEqual(catalog.matches("micro scope").first?.name, "Microscope")
            XCTAssertEqual(catalog.suggestion("Work projects"), "tabler:Briefcase")
            XCTAssertNil(catalog.suggestion("zyxwvu"))
            let removals: [(String, String)] = [
                (#"{"Work":"tabler:Book","after":false}"#, #"{"after":false}"#),
                (#"{"before":[{"text":"escaped \" quote, brace }"}],"Work":"tabler:Book","after":null}"#, #"{"before":[{"text":"escaped \" quote, brace }"}],"after":null}"#),
                ("{\"before\":true,\r\n \"Work\":\"tabler:Book\"\r\n}", "{\"before\":true\r\n}"),
                ("\u{feff}{\r\n \"Work\":\"tabler:Book\"\r\n}", "\u{feff}{\r\n \r\n}")
            ]
            for (source, expected) in removals {
                try Data(source.utf8).write(to: path); await store.refresh()
                let removing = try await store.folderIconReview(.init(folder: "Work", workspaceID: store.workspaceID))
                try await store.changeFolderIcon(removing, folder: "Work", value: nil)
                XCTAssertEqual(try Data(contentsOf: path), Data(expected.utf8), "Reset preserves other JSON tokens in every key position")
            }
            try Data("{}".utf8).write(to: path); await store.refresh()
            let empty = try await store.folderIconReview(.init(folder: "Work", workspaceID: store.workspaceID))
            try await store.changeFolderIcon(empty, folder: "Work", value: "tabler:Dog")
            XCTAssertEqual(try Data(contentsOf: path), Data(#"{"Work": "tabler:Dog"}"#.utf8))
            let duplicate = Data(#"{"Work":"tabler:Book","Work":"tabler:Dog"}"#.utf8)
            try duplicate.write(to: path); await store.refresh()
            let ambiguous = try await store.folderIconReview(.init(folder: "Work", workspaceID: store.workspaceID))
            do { try await store.changeFolderIcon(ambiguous, folder: "Work", value: nil); XCTFail("A duplicate selected key must remain unchanged") } catch { XCTAssertTrue(error.localizedDescription.contains("duplicated")) }
            XCTAssertEqual(try Data(contentsOf: path), duplicate)
        }
    }

    func testWarmStartupUsesFullBodiesAndKeepsSavesMadeDuringAnOlderScan() async throws {
        let original = "\u{feff}---\r\nzerus-id: early\r\nForeign: true # keep\r\n---\r\n# Cached title\r\n\r\nOriginal body.\r\n"
        try await withVault(["Work/A.md": original, ".zerus/type-icons.json": #"{"Work":"tabler:Briefcase"}"#, ".zerus/properties.json": #"{"Work":[{"name":"Status","type":"text"}]}"#]) { root, cold in
            await cold.openNote("Work/A.md")
            let closed = await cold.prepareToCloseWindow(); XCTAssertTrue(closed)
            XCTAssertTrue(FileManager.default.fileExists(atPath: MacStartupCache.location(root).path))
            let iconCache = await MacStartupCache.shared.load(try XCTUnwrap(MacStartupIdentity.read(root)))
            XCTAssertEqual(iconCache?.snapshot.macFolderIconBytes, Data(#"{"Work":"tabler:Briefcase"}"#.utf8), "Warm startup keeps shared folder artwork before the provider scan finishes")
            let reached = expectation(description: "authoritative scan has read its note bodies")
            let gate = MacCoordinatedReadGate(root.appendingPathComponent(".zerus/type-icons.json")) { reached.fulfill() }
            NSFileCoordinator.addFilePresenter(gate)
            defer { gate.release(); NSFileCoordinator.removeFilePresenter(gate) }
            let warm = MacWorkspace(), opened = expectation(description: "cached vault is usable before the scan finishes")
            let opening = Task { await warm.openVault(root); opened.fulfill() }
            await fulfillment(of: [opened, reached], timeout: 5)
            XCTAssertTrue(warm.usingStartupCache); XCTAssertTrue(warm.startupRefreshing); XCTAssertFalse(warm.busy)
            XCTAssertEqual(warm.body, "# Cached title\r\n\r\nOriginal body.\r\n")
            XCTAssertEqual(Data(try XCTUnwrap(warm.notes.first { $0.path == "Work/A.md" }).content.utf8), Data(original.utf8))
            XCTAssertEqual(try warm.schema?.effective(notePath: "Work/A.md").first?.name, "Status")
            warm.changed("# Cached title\r\n\r\nSaved while scanning.\r\n")
            let saved = expectation(description: "an unrelated provider read does not block a note save")
            var didSave = false
            let saving = Task { didSave = await warm.save(); saved.fulfill() }
            await fulfillment(of: [saved], timeout: 5)
            gate.release(); _ = await opening.value; _ = await saving.value
            XCTAssertTrue(didSave, warm.issue ?? warm.saveStatus)
            for _ in 0..<150 where warm.startupRefreshing { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertFalse(warm.usingStartupCache); XCTAssertNil(warm.startupIssue); XCTAssertNil(warm.noteDiskChange)
            XCTAssertEqual(warm.body, "# Cached title\r\n\r\nSaved while scanning.\r\n")
            let expected = original.replacingOccurrences(of: "Original body.", with: "Saved while scanning.")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(expected.utf8))
            XCTAssertEqual(Data(try XCTUnwrap(warm.notes.first { $0.path == "Work/A.md" }).content.utf8), Data(expected.utf8))
            let warmClosed = await warm.prepareToCloseWindow(); XCTAssertTrue(warmClosed)
            let reopened = MacWorkspace(); await reopened.openVault(root)
            XCTAssertEqual(reopened.body, warm.body)
            for _ in 0..<150 where reopened.startupRefreshing { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertNil(reopened.noteDiskChange)
            _ = await reopened.prepareToCloseWindow()
        }
    }

    func testStartupCacheSurvivesInventoryFailureButRefusesAReplacedRoot() async throws {
        try await withVault(["A.md": note("a", title: "Cached A")]) { root, cold in
            await cold.openNote("A.md"); let closed = await cold.prepareToCloseWindow(); XCTAssertTrue(closed)
            try Data([0xff, 0xfe]).write(to: root.appendingPathComponent("Broken.md"))
            let warm = MacWorkspace(); await warm.openVault(root)
            XCTAssertEqual(warm.current?.title, "Cached A"); XCTAssertTrue(warm.usingStartupCache)
            for _ in 0..<150 where warm.startupRefreshing { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertNotNil(warm.startupIssue); XCTAssertTrue(warm.usingStartupCache)
            try Data("# Fixed B\n".utf8).write(to: root.appendingPathComponent("Broken.md"))
            await warm.refresh()
            for _ in 0..<150 where warm.startupRefreshing { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertFalse(warm.usingStartupCache); XCTAssertEqual(Set(warm.notes.map(\.path)), ["A.md", "Broken.md"])
            _ = await warm.prepareToCloseWindow()
            try FileManager.default.removeItem(at: root.appendingPathComponent("A.md"))
            let removed = MacWorkspace(); await removed.openVault(root)
            for _ in 0..<150 where removed.startupRefreshing { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertFalse(removed.usingStartupCache); XCTAssertNil(removed.noteDiskChange)
            XCTAssertEqual(removed.notes.map(\.path), ["Broken.md"])
            XCTAssertNil(removed.selection, "An untouched cached note deleted between launches is disposable, not a retained draft")
            XCTAssertTrue(try MacNoteRecoveryStore.snapshot(root: root).records.isEmpty)
            _ = await removed.prepareToCloseWindow()
            try Data([0, 1, 2]).write(to: MacStartupCache.location(root))
            let corrupt = MacWorkspace(); await corrupt.openVault(root)
            XCTAssertFalse(corrupt.usingStartupCache); XCTAssertEqual(corrupt.notes.first?.title, "Fixed B")
            _ = await corrupt.prepareToCloseWindow()
            let repairedCache = await MacStartupCache.shared.load(try XCTUnwrap(MacStartupIdentity.read(root)))
            XCTAssertNotNil(repairedCache)
            let moved = root.appendingPathExtension("old")
            try FileManager.default.moveItem(at: root, to: moved)
            defer { try? FileManager.default.removeItem(at: moved) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("# A different vault\n".utf8).write(to: root.appendingPathComponent("New.md"))
            let replacement = MacWorkspace(); await replacement.openVault(root)
            XCTAssertFalse(replacement.usingStartupCache)
            XCTAssertEqual(replacement.notes.map(\.path), ["New.md"])
            XCTAssertEqual(replacement.notes.first?.title, "A different vault")
            _ = await replacement.prepareToCloseWindow()
        }
    }

    func testStartupRefreshKeepsMarkedTextAndItsOriginalByteBaseline() async throws {
        let original = "---\nzerus-id: composing\n---\n# Cached title\n\nOriginal body.\n"
        try await withVault(["A.md": original, ".zerus/type-icons.json": "{}"]) { root, cold in
            await cold.openNote("A.md"); _ = await cold.prepareToCloseWindow()
            let outside = original.replacingOccurrences(of: "Original body.", with: "Outside body.")
            try Data(outside.utf8).write(to: root.appendingPathComponent("A.md"))
            let reached = expectation(description: "fresh scan is waiting after reading outside bytes")
            let gate = MacCoordinatedReadGate(root.appendingPathComponent(".zerus/type-icons.json")) { reached.fulfill() }
            NSFileCoordinator.addFilePresenter(gate)
            defer { gate.release(); NSFileCoordinator.removeFilePresenter(gate) }
            let warm = MacWorkspace(); await warm.openVault(root)
            await fulfillment(of: [reached], timeout: 5)
            let host = NSHostingView(rootView: MacWorkspaceView(store: warm).environment(\.colorScheme, .light))
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer {
                window.contentView = nil; window.close()
                for record in (try? MacNoteRecoveryStore.snapshot(root: root).records) ?? [] { try? FileManager.default.removeItem(at: record.file) }
            }
            func editor(_ node: NSView) -> NSTextView? {
                if let view = node as? NSTextView, !view.isFieldEditor { return view }
                return node.subviews.lazy.compactMap(editor).first
            }
            for _ in 0..<30 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
            let view = try XCTUnwrap(editor(host)), range = (view.string as NSString).range(of: "Original")
            XCTAssertNotEqual(range.location, NSNotFound)
            window.makeFirstResponder(view); view.setSelectedRange(range)
            view.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: range)
            XCTAssertTrue(view.hasMarkedText())
            XCTAssertEqual(warm.body, "# Cached title\n\nOriginal body.\n", "Provisional text stays out of persistence")
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let image = bitmap.cgImage { let attachment = XCTAttachment(image: NSImage(cgImage: image, size: .zero)); attachment.name = "Native cached vault while checking saved files"; attachment.lifetime = .keepAlways; add(attachment) }
            }
            gate.release()
            for _ in 0..<150 where warm.startupRefreshing { try await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
            XCTAssertTrue(view.hasMarkedText(), "The background result cannot replace active input")
            XCTAssertTrue(view.string.contains("仮")); XCTAssertNotNil(warm.noteDiskChange)
            view.unmarkText()
            for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
            XCTAssertTrue(warm.body.contains("仮"))
            let saved = await warm.save(); XCTAssertFalse(saved)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("A.md")), Data(outside.utf8))
            XCTAssertTrue(try MacNoteRecoveryStore.snapshot(root: root).records.contains { $0.body.contains("仮") })
        }
    }

    func testCollectionModifiedSelectionUsesDisplayedRangesAndRejectsHiddenNotes() async throws {
        try await withVault(Dictionary(uniqueKeysWithValues: ["A", "B", "C", "D", "E"].map { ("Work/" + $0 + ".md", note($0.lowercased(), title: $0 == "E" ? "UniqueNeedle" : $0)) })) { root, store in
            await store.openCollection("Work", folder: true)
            let order = ["Work/A.md", "Work/B.md", "Work/C.md", "Work/D.md", "Work/E.md"]
            let original = try Data(contentsOf: root.appendingPathComponent("Work/B.md"))
            await store.activateCollectionNote("Work/B.md", modifiers: .command, order: order)
            XCTAssertNil(store.selection, "Command-click selects without opening the editor")
            XCTAssertEqual(store.selectedPaths, ["Work/B.md"])
            await store.activateCollectionNote("Work/D.md", modifiers: .shift, order: order)
            XCTAssertEqual(store.selectedPaths, ["Work/B.md", "Work/C.md", "Work/D.md"])
            await store.activateCollectionNote("Work/A.md", modifiers: .shift, order: order)
            XCTAssertEqual(store.selectedPaths, ["Work/A.md", "Work/B.md", "Work/C.md", "Work/D.md"], "Ranges are additive and retain the original anchor")
            await store.activateCollectionNote("Work/C.md", modifiers: .command, order: order)
            XCTAssertEqual(store.selectedPaths, ["Work/A.md", "Work/B.md", "Work/D.md"])
            // A column/group passes its own order. An anchor outside that group
            // toggles the target rather than spanning unrelated cards.
            await store.activateCollectionNote("Work/E.md", modifiers: .shift, order: ["Work/B.md", "Work/E.md"])
            XCTAssertEqual(store.selectedPaths, ["Work/A.md", "Work/B.md", "Work/D.md", "Work/E.md"])
            await store.activateCollectionNote("Work/B.md", modifiers: .shift, order: ["Work/B.md", "Work/E.md"])
            XCTAssertEqual(store.selectedPaths, ["Work/A.md", "Work/B.md", "Work/D.md", "Work/E.md"])
            store.query = "UniqueNeedle"
            XCTAssertTrue(store.selectedPaths.isEmpty, "Changing the filter clears bulk selection and its anchor")
            await store.activateCollectionNote("Work/A.md", modifiers: .command, order: order)
            XCTAssertTrue(store.selectedPaths.isEmpty, "A stale rendered row cannot select a filtered-out note")
            await store.activateCollectionNote("Work/E.md", modifiers: .command, order: order)
            XCTAssertEqual(store.selectedPaths, ["Work/E.md"])
            store.query = ""
            store.selecting = true
            await store.activateCollectionNote("Work/B.md", order: order)
            await store.activateCollectionNote("Work/D.md", modifiers: .shift, order: order)
            XCTAssertEqual(store.selectedPaths, ["Work/B.md", "Work/C.md", "Work/D.md"])
            store.selecting = false
            await store.activateCollectionNote("Work/A.md", order: order)
            XCTAssertTrue(store.selectedPaths.isEmpty, "An ordinary click opens the note and clears bulk selection")
            XCTAssertEqual(store.selection, "Work/A.md")
            await store.openCollection("Work", folder: true)
            await store.activateCollectionNote("Work/E.md", modifiers: .command, order: order)
            await store.openCollection("All Notes")
            XCTAssertTrue(store.selectedPaths.isEmpty)
            await store.activateCollectionNote("Work/B.md", modifiers: .shift, order: order)
            XCTAssertEqual(store.selectedPaths, ["Work/B.md"], "Changing collections clears the range anchor")
            store.selectAllCollectionNotes()
            XCTAssertEqual(store.selectedPaths, Set(order)); XCTAssertTrue(store.selecting)
            store.clearCollectionSelection()
            XCTAssertTrue(store.selectedPaths.isEmpty); XCTAssertFalse(store.selecting)
            await store.activateCollectionNote("Work/E.md", modifiers: .shift, order: order)
            XCTAssertEqual(store.selectedPaths, ["Work/E.md"], "Clear removes the range anchor")
            var next = store.filters; next.sort = .titleAscending; store.changeCollectionFilters(next)
            XCTAssertTrue(store.selectedPaths.isEmpty)
            await store.activateCollectionNote("Work/B.md", modifiers: .command, order: order)
            store.hideSubtypes.toggle()
            XCTAssertTrue(store.selectedPaths.isEmpty)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/B.md")), original)
        }
    }

    func testEmbeddedCodeAndTablesOpenInTheModeThatPreservesTheirListContainer() async throws {
        let fixtures: [(body: String, source: Bool)] = [
            ("- Parent\n  - Child\n\n  Tail paragraph.\n- Sibling\n", false),
            ("> - Parent\n>   - Child\n>\n>   Tail paragraph.\n> - Sibling\n", false),
            ("10. Parent\n    - Child\n\n    Tail paragraph.\n11. Sibling\n", false),
            ("-     [ ] Parent\n", false),
            ("1.     [ ] Parent\n", false),
            ("> -     [ ] Parent\n", false),
            ("- Parent\n  ```\n  x\n  ```\n  - Child\n", false),
            ("- Parent\n  ```\n  x\n  ```\n- Sibling\n", false),
            ("- Parent\n\n  | A | B |\n  | --- | --- |\n  | One | Two |\n\n  - Child\n", false),
            ("> - Parent\n>   ```\n>   x\n>   ```\n>   - Child\n", false),
            ("- Parent\n\n      x\n\n  - Child\n", false),
            ("```\n- Parent\n  - Example\n```\n\n- Actual\n", false),
            ("| A | B |\n| --- | --- |\n| - Parent | Text |\n\n- Actual\n", false),
            ("- Parent\n\n```\nx\n```\n\n- Sibling\n", false),
            ("> Before\n>\n> ```swift\n> let x = 1\n> ```\n>\n> After\n", false),
            ("> > | A | B |\n> > | --- | --- |\n> > | One | Two |\n", false),
            ("- Parent\n  > Quote prose\n\n  ```\n  x\n  ```\n", false),
            ("- # Heading\n\n  ```\n  x\n  ```\n", false),
            ("- Parent\n  ```\n  x\n  ```\n\nOutside\n\n  Kept\n", false),
            ("- Parent\n\n  | A |\n  | --- |\n  | <script>bad</script> |\n", false),
            ("- ```swift\n  Parent\n  ```\n- Sibling\n", false),
            ("- | A | B |\n  | --- | --- |\n  | Parent | Keep |\n- Sibling\n", false),
            ("- - ```swift\n    Parent\n    ```\n- Sibling\n", false),
            (">10. ```swift\n>     Parent\n>     ```\n>11. Sibling\n", false),
            ("-\t```swift\n\tParent\n\t```\n- Sibling\n", false),
            ("- > ```swift\n  > Parent\n  > ```\n- Sibling\n", false),
            ("- Parent\n  ```swift\n  x\n  ```\n\n  | A |\n  | --- |\n  | One |\n\n  Tail\n- Sibling\n", false),
            ("- Parent\n  > 1. Child\n  >    ```\n  >    x\n  >    ```\n", false),
            ("- Parent\n  ```\n  x\n  ```\n\n[ref]: target\n", false)
        ]
        let cases = fixtures.flatMap { entry in ["\n", "\r\n", "\r"].map { (body: entry.body.replacingOccurrences(of: "\n", with: $0), source: entry.source) } }
        let files = Dictionary(uniqueKeysWithValues: cases.enumerated().map { index, entry in
            ("Container-\(index).md", "---\nzerus-id: container-\(index)\n---\n" + entry.body)
        })
        try await withVault(files) { root, store in
            for (index, entry) in cases.enumerated() {
                let path = "Container-\(index).md"
                await store.openNote(path)
                XCTAssertEqual(store.body, entry.body)
                XCTAssertEqual(store.sourceMode, entry.source, entry.body)
                // Opening and reopening choose the editing mode from the
                // original parser-owned containers without changing note bytes.
                let edited = entry.body.replacingOccurrences(of: "Parent", with: "Rewritten")
                store.changed(edited)
                let saved = await store.save(); XCTAssertTrue(saved, store.issue ?? store.saveStatus)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(files[path]!.replacingOccurrences(of: "Parent", with: "Rewritten").utf8))
                await store.openNote("Container-\((index + 1) % cases.count).md")
                await store.openNote(path)
                XCTAssertEqual(store.body, edited)
                XCTAssertEqual(store.sourceMode, entry.source, "Reopening must retain the admitted mode")
            }
            // Repeated warm navigation must still choose admission from the
            // current bytes, including an outside edit that changes the mode.
            let path = "Container-0.md", other = "Container-1.md"
            for body in ["# Warm café\n", "<script>literal</script>\n", "> Warm cafe\u{301}\n"] {
                await store.openNote(other)
                let bytes = Data(("---\nzerus-id: container-0\n---\n" + body).utf8)
                try bytes.write(to: root.appendingPathComponent(path))
                await store.refresh()
                for _ in 0..<2 {
                    await store.openNote(path)
                    XCTAssertEqual(Data(store.body.utf8), Data(body.utf8))
                    XCTAssertFalse(store.sourceMode, "Rich text is the default; Source is only an explicit choice")
                    await store.openNote(other)
                }
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), bytes)
            }
        }
    }

    func testBulkPropertyHistoryKeepsLeadingUnicodeMarksThroughUndoAndRedo() async throws {
        let original = "---\nzerus-id: marked\nMarker: \"\u{feff}Original\"\n---\n# Marked\n"
        try await withVault(["Marked.md": original, ".zerus/properties.json": #"{"": [{"name":"Marker","type":"text"}]}"#]) { _, store in
            let snapshot = try await store.bulkReviewSnapshot()
            let plan = try snapshot.plan(selected: snapshot.source.notes, mutation: .init(properties: [.init(name: "Marker", value: .text("\u{feff}Updated"))]))
            XCTAssertTrue(plan.issues.isEmpty, plan.issues.map(\.reason).joined(separator: "; "))
            XCTAssertEqual(plan.changedNotes, ["Marked.md"])
            try await store.commitBulk(plan)
            var history = try await store.bulkReviewSnapshot()
            let record = try XCTUnwrap(history.records.first)
            XCTAssertEqual(record.entries.first?.fields.first?.before, .text("\u{feff}Original"))
            XCTAssertEqual(record.entries.first?.fields.first?.after, .text("\u{feff}Updated"))
            try await store.commitBulk(history.transition(record.id, undo: true))
            XCTAssertEqual(store.notes.first?.property("Marker"), "\u{feff}Original")
            history = try await store.bulkReviewSnapshot()
            try await store.commitBulk(history.transition(record.id, undo: false))
            XCTAssertEqual(store.notes.first?.property("Marker"), "\u{feff}Updated")
        }
    }

    func testVaultEditingKeepsUtf8PrefixesForeignYamlLineEndingsAndFileMetadata() async throws {
        for count in [1, 2] { for newline in ["\n", "\r\n"] { for yaml in [false, true] {
            let prefix = String(repeating: "\u{feff}", count: count)
            let header = yaml ? "---" + newline + "zerus-id: bom-note" + newline + "Foreign: 'keep: this' # comment" + newline + "---" + newline : ""
            let body = "# Café 👩🏽‍💻" + newline + newline + "Original." + newline
            let original = prefix + header + body
            try await withVault(["BOM.md": original, "Control.md": "# Newer control\n"]) { root, store in
                let location = root.appendingPathComponent("BOM.md")
                let created = Date(timeIntervalSince1970: 1_000_000_000)
                try FileManager.default.setAttributes([.creationDate: created, .modificationDate: created.addingTimeInterval(60), .posixPermissions: 0o640], ofItemAtPath: location.path)
                try FileManager.default.setAttributes([.creationDate: created.addingTimeInterval(86_400), .modificationDate: created.addingTimeInterval(86_460)], ofItemAtPath: root.appendingPathComponent("Control.md").path)
                func assertMetadata() throws {
                    let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
                    XCTAssertEqual(try XCTUnwrap(attributes[.creationDate] as? Date).timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 1, "Editing must preserve filesystem creation date")
                    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640, "Editing must preserve existing permissions")
                }
                try assertMetadata()
                await store.refresh()
                var filters = store.filters; filters.sort = .createdDescending; store.changeCollectionFilters(filters)
                XCTAssertEqual(store.collection.map(\.path), ["Control.md", "BOM.md"])
                await store.openNote("BOM.md")
                let scanned = try XCTUnwrap(store.notes.first { $0.path == "BOM.md" })
                XCTAssertEqual(Data(scanned.content.utf8), Data(original.utf8))
                XCTAssertEqual(scanned.title, "Café 👩🏽‍💻"); XCTAssertEqual(store.body, body)
                if yaml { XCTAssertEqual(scanned.stableID, "bom-note"); XCTAssertEqual(scanned.property("Foreign"), "keep: this") }
                store.changed(body.replacingOccurrences(of: "Original", with: "Edited"))
                let saved = await store.save(); XCTAssertTrue(saved, store.issue ?? store.saveStatus)
                guard saved else { return }
                try assertMetadata()
                XCTAssertEqual(try Data(contentsOf: location), Data(original.replacingOccurrences(of: "Original", with: "Edited").utf8))
                await store.setProperty("Extra", value: .text("kept"))
                XCTAssertNil(store.issue)
                try assertMetadata()
                let updated = try Data(contentsOf: location)
                XCTAssertTrue(updated.starts(with: Data(prefix.utf8)))
                XCTAssertEqual(Array(updated.prefix(count * 3 + 3).suffix(3)), Array("---".utf8))
                await store.refresh(); await store.openNote("BOM.md")
                XCTAssertEqual(store.collection.map(\.path), ["Control.md", "BOM.md"], "Newest ordering must remain based on original creation dates after a fresh scan")
                XCTAssertEqual(store.notes.first(where: { $0.path == "BOM.md" })?.property("Extra"), "kept")
                XCTAssertEqual(store.body, body.replacingOccurrences(of: "Original", with: "Edited"))
                if yaml { XCTAssertTrue(String(decoding: updated, as: UTF8.self).contains("Foreign: 'keep: this' # comment" + newline)) }
            }
        } } }
    }

    func testPropertiesPaneMergesSharedLayoutAndUpdatesOtherVaultWindowsWithoutEditingNotes() async throws {
        let raw = #"{"order":["outline",42,"properties","outline","future"],"collapsed":["relations","future",false],"foreign":{"keep":true}}"#
        let content = note("pane", title: "Pane")
        try await withVault(["Pane.md": content, ".zerus/properties-pane.json": raw]) { root, store in
            XCTAssertEqual(store.paneLayout.order, [.outline, .properties, .revisions, .relations, .attachments])
            XCTAssertEqual(store.paneLayout.collapsed, [.relations])
            XCTAssertTrue(store.paneLayoutReady)
            let peer = MacWorkspace(); await peer.openVault(root)
            try await store.changePane(.step(.attachments, -1), workspaceID: store.workspaceID)
            XCTAssertEqual(store.paneLayout.order, [.outline, .properties, .revisions, .attachments, .relations])
            XCTAssertEqual(peer.paneLayout, store.paneLayout)
            try await peer.changePane(.collapse(.outline, true), workspaceID: peer.workspaceID)
            XCTAssertEqual(store.paneLayout.collapsed, [.outline, .relations])
            let file = root.appendingPathComponent(".zerus/properties-pane.json")
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            object["collapsed"] = ["attachments", "future"]
            object["externalEdit"] = "retained"
            try JSONSerialization.data(withJSONObject: object).write(to: file)
            try await store.changePane(.collapse(.revisions, true), workspaceID: store.workspaceID)
            XCTAssertEqual(store.paneLayout.collapsed, [.attachments, .revisions])
            try await peer.changePane(.move(.attachments, .outline), workspaceID: peer.workspaceID)
            XCTAssertEqual(store.paneLayout.order.first, .attachments)
            try await store.changePane(.reset, workspaceID: store.workspaceID)
            XCTAssertEqual(store.paneLayout.order, [.properties, .revisions, .relations, .outline, .attachments])
            XCTAssertTrue(store.paneLayout.collapsed.isEmpty)
            object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual((object["foreign"] as? [String: Bool])?["keep"], true)
            XCTAssertEqual(object["externalEdit"] as? String, "retained")
            XCTAssertEqual((object["order"] as? [String])?.filter { $0 == "future" }.count, 1)
            XCTAssertEqual(object["collapsed"] as? [String], ["future"])
            let reopened = MacWorkspace(); await reopened.openVault(root)
            XCTAssertEqual(reopened.paneLayout, store.paneLayout)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Pane.md"), encoding: .utf8), content)
        }
    }
    func testPropertiesPaneRejectsUnreadableDataAndOldVaultActionsThenRefreshesExternalChanges() async throws {
        try await withVault(["Pane.md": note("pane", title: "Pane")]) { root, store in
            let file = root.appendingPathComponent(".zerus/properties-pane.json"), origin = store.workspaceID
            try await store.changePane(.collapse(.relations, true), workspaceID: origin)
            let saved = store.paneLayout
            try Data("{broken".utf8).write(to: file)
            await store.refreshPaneLayout()
            XCTAssertFalse(store.paneLayoutReady); XCTAssertNotNil(store.paneLayoutIssue)
            do { try await store.changePane(.reset, workspaceID: origin); XCTFail("Unreadable settings must stay intact") } catch {}
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{broken")
            XCTAssertEqual(store.paneLayout, saved)
            try Data(#"{"order":["attachments","properties"],"collapsed":["outline"]}"#.utf8).write(to: file)
            await store.refreshPaneLayout()
            XCTAssertEqual(store.paneLayout.order.first, .attachments)
            XCTAssertEqual(store.paneLayout.collapsed, [.outline]); XCTAssertNil(store.paneLayoutIssue)
            let before = try Data(contentsOf: file)
            await store.openVault(root)
            do { try await store.changePane(.reset, workspaceID: origin); XCTFail("An old vault action must not write") }
            catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
            XCTAssertEqual(try Data(contentsOf: file), before)
        }
    }
    func testFooterWordCountIgnoresMarkdownMarkersAndCheckboxState() async throws {
        let examples: [(String, Int)] = [
            ("# Title\n\n- [ ] First task\n- [x] Second task\n", 5),
            ("# Title\n\n- [x] First task\n- [ ] Second task\n", 5),
            ("# Title\n\n> First **task**\n>\n> Second *task*\n", 5),
            ("[Two words](https://example.com/not-extra-words) file_**name**\n", 3),
            ("[[zerus:id|Two words]]\n", 2),
            ("| One | Two |\n| --- | --- |\n| Three | Four |\n", 4),
            ("```swift\nlet value = 42\n```\n", 4),
            ("Before\n\n```swift\nlet café = \"🧑🏽‍💻\"\n```\n\nAfter\n", 6),
            ("Before more\n\n```swift\nlet café = \"🧑🏽‍💻\"\n```\n\nAfter\n", 7),
            ("Before\n\n```swift\nlet two words = 42\n```\n\nAfter\n", 7),
            ("P\n\n```\n\u{0301}\n```\n", 1),
            ("P\n\n```\n\u{0301}x\n```\n", 2),
            ("P\n\n```\n \u{0301}\n```\n", 1),
            ("Before\n\n```\n\n```\n\nAfter\n", 2),
            ("---\n\n![Not note words](assets/image.png)\n", 0),
            ("Before<br>After\n", 2),
            ("A\n\n\u{200B}\n\nB\n", 2),
            ("A\n\n\u{200B}<br>\n\nB\n", 2),
            ("\u{200B}\n", 0),
        ]
        for (body, expected) in examples { XCTAssertEqual(MacWordCount.count(body), expected, body) }
        let first = "# First note\n", second = "# Three small words\n"
        try await withVault(["Work/A.md": first, "Work/B.md": second]) { root, store in
            await store.openNote("Work/A.md")
            let host = NSHostingView(rootView: MacWorkspaceView(store: store).environment(\.colorScheme, .light))
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            @MainActor func expectWords(_ expected: Int) async throws {
                var observed: [String] = []
                for _ in 0..<20 {
                    try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded()
                    // Keep the logical view bounds and clipping, while giving
                    // Vision enough pixels to recognize the small footer caption.
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                    bitmap.size = host.bounds.size
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let image = try XCTUnwrap(bitmap.cgImage)
                    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
                    request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 0.1)
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    observed = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    let pattern = #"(?i)(?<![0-9])"# + String(expected) + #"\s*words\b"#
                    if observed.contains(where: { $0.range(of: pattern, options: .regularExpression) != nil }) { return }
                }
                XCTFail("The visible footer must settle on \(expected); observed: \(observed)")
            }
            try await expectWords(2)
            store.changed("# Interim edit\n")
            try await expectWords(2)
            let latest = "# Newest draft five words here\n"
            store.changed(latest)
            try await expectWords(5)
            XCTAssertEqual(store.body, latest, "Counting must not alter the draft")
            let saved = await store.save(); XCTAssertTrue(saved)
            await store.openNote("Work/B.md")
            try await expectWords(3)
            XCTAssertEqual(store.body, second)
            await store.openNote("Work/A.md")
            try await expectWords(5)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8), latest)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/B.md"), encoding: .utf8), second)
        }
    }
    func testOpeningContainerParagraphsChoosesRichOnlyForEditableNativeStructure() async throws {
        // Up to three root spaces are Markdown layout, not list ownership or code.
        // Exercise public opening, editing, Save and reopening, not just admission.
        let rootProse: [(body: String, edited: String)] = [
            ("  Nested prose\n", "Edited prose\n"),
            ("   Nested prose\n", "Edited prose\n"),
            ("  Nested prose\n  continued text.\n", "Edited prose\ncontinued text.\n"),
            ("- Parent\n\nOutside\n\n  Nested prose\n", "- Parent\n\nOutside\n\nEdited prose\n"),
            ("- Parent\n\nOutside\n\n   Nested prose\n", "- Parent\n\nOutside\n\nEdited prose\n"),
            ("  ## Nested heading\n", "  ## Edited heading\n")
        ].flatMap { body, edited in ["\n", "\r\n", "\r"].map { ending in
            (body.replacingOccurrences(of: "\n", with: ending), edited.replacingOccurrences(of: "\n", with: ending))
        } }
        let tabLists: [(body: String, edited: String)] = [
            ("-\t-\tNested item\n", "-\t-\tEdited item\n"),
            ("- -\tNested item\n", "- -\tEdited item\n"),
            ("> -\t-\tNested item\n", "> -\t-\tEdited item\n"),
            ("```swift\n\tlet literal = 1\n```\n\n-\t-\tNested item\n", "```swift\n\tlet literal = 1\n```\n\n-\t-\tEdited item\n"),
            ("-\tNested item\n", "-   Edited item\n"),
            ("1.\tNested item\n", "1.  Edited item\n"),
            ("-\t[ ] Nested item\n", "-   [ ] Edited item\n"),
            ("-\t[x] Nested item\n", "-   [x] Edited item\n"),
            ("-\tNested item\n\t-\tChild\n", "-   Edited item\n\t-\tChild\n"),
            ("- Parent\n\t-\tNested item\n", "- Parent\n    -   Edited item\n"),
            ("> -\tNested item\n>\t- Child\n", "> - Edited item\n>\t- Child\n"),
            ("-\tNested item\n\n\tTail paragraph.\n", "-   Edited item\n\n    Tail paragraph.\n"),
            ("-\t**Nested** [link](https://example.com/)\n", "-   **Edited** [link](https://example.com/)\n"),
            ("-\t## Nested heading\n", "-   ## Edited heading\n"),
            ("-\t##\tNested heading\n", "-   ## Edited heading\n"),
            ("-\tNested item\n\n```swift\n\tlet literal = 1\n```\n", "-   Edited item\n\n```swift\n\tlet literal = 1\n```\n"),
            ("```swift\n\tlet literal = 1\n```\n\n-\tNested item\n", "```swift\n\tlet literal = 1\n```\n\n-   Edited item\n"),
            ("-\tNested item\n\n| A | B |\n| --- | --- |\n| old | Keep |\n", "-   Edited item\n\n| A | B |\n| --- | --- |\n| old | Keep |\n"),
            ("| A | B |\n| --- | --- |\n| old | Keep |\n\n-\tNested item\n", "| A | B |\n| --- | --- |\n| old | Keep |\n\n-   Edited item\n"),
            ("> ```swift\n> \tlet literal = 1\n> ```\n\n-\tNested item\n", "> ```swift\n> \tlet literal = 1\n> ```\n\n-   Edited item\n")
        ].flatMap { body, edited in ["\n", "\r\n", "\r"].map { ending in
            (body.replacingOccurrences(of: "\n", with: ending), edited.replacingOccurrences(of: "\n", with: ending))
        } }
        let deferredHeads: [(body: String, edited: String)] = [
            ("- \n  Nested item\n- Sibling\n", "- Edited item\n- Sibling\n"),
            ("-\n  Nested item\n- Sibling\n", "- Edited item\n- Sibling\n"),
            ("1.\n   Nested item\n2. Sibling\n", "1. Edited item\n2. Sibling\n"),
            ("> - \n>   Nested item\n> - Sibling\n", "> - Edited item\n> - Sibling\n"),
            ("- Root\n\n  - \n    Nested item\n  - Peer\n- Sibling\n", "- Root\n\n  - Edited item\n  - Peer\n- Sibling\n"),
            ("- \n  **Nested** [link](https://example.com/)\n- Sibling\n", "- **Edited** [link](https://example.com/)\n- Sibling\n")
        ].flatMap { body, edited in ["\n", "\r\n", "\r"].map { ending in
            (body.replacingOccurrences(of: "\n", with: ending), edited.replacingOccurrences(of: "\n", with: ending))
        } }
        let examples: [(String, Bool)] = [
            (">     # Indented code\n", false),
            ("-\tFirst\n\n\tSecond\n", false),
            ("- First\nLazy continuation.\n", false),
            ("> First\nLazy continuation.\n", false),
            ("> First\n> Explicit continuation.\n", false),
            ("- First\n  Indented continuation.\n", false),
            ("- First\n\n  Second paragraph.\n", false),
            ("- # Nested heading\n", false),
            ("- > Nested quote\n", false),
            ("- Parent\n  > Quote\n  >\n  > - Nested child\n  >   - Grandchild\n- Sibling\n", false),
            ("- > - Nested child\n  >   - Grandchild\n- Sibling\n", false),
            ("> 10. Parent\n>     > Quote\n>     >\n>     > 9. Nested child\n> 11. Sibling\n", false),
            ("- Parent\n  > Quote\n  >\n  > > - Nested child\n- Sibling\n", false),
            ("- Parent\n  > - Nested child\n  >   ```swift\n  >   let value = 1\n  >   ```\n- Sibling\n", false),
            ("- Parent\n  > - Nested child\n  >\n  >   | A | B |\n  >   | --- | --- |\n  >   | old | Other |\n- Sibling\n", false),
            ("- > - Nested child\n  >   ```swift\n  >   let value = 1\n  >   ```\n- Sibling\n", false),
            ("- > - # Nested heading\n- Sibling\n", false),
            ("- > - <div>Unsupported HTML</div>\n- Sibling\n", false),
            ("> - First\n>   Continuation.\n", false),
            ("- Parent\n  - Child\n  - [ ] Task\n", false),
            ("> # Heading\n> - Item\n>   - Child\n", false),
            ("> First\n>\n> Separate paragraph.\n", false),
            ("Ordinary prose\nwith a soft break.\n", false),
            ("-\n", false), // Rich text is the default; Source is only an explicit choice.
            ("1.\n", false),
            ("[reference]: https://example.com\n\n[Link][reference]\n", false),
        ] + (rootProse + tabLists + deferredHeads).map { ($0.body, false) }
        for (body, needsSource) in examples {
            let original = note("container", title: "Container", body: body)
            try await withVault(["Work/Container.md": original]) { root, store in
                await store.openNote("Work/Container.md")
                XCTAssertEqual(store.sourceMode, needsSource, body)
                let file = root.appendingPathComponent("Work/Container.md")
                XCTAssertEqual(try Data(contentsOf: file), Data(original.utf8), "Opening must leave the file intact")
                if body.contains("Nested") && !store.sourceMode {
                    let host = NSHostingView(rootView: MacWorkspaceView(store: store).environment(\.colorScheme, .light))
                    let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
                    defer { window.contentView = nil; window.close() }
                    for _ in 0..<12 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
                    func editor(_ node: NSView) -> NSTextView? {
                        if let view = node as? NSTextView, !view.isFieldEditor { return view }
                        return node.subviews.lazy.compactMap(editor).first
                    }
                    let view = try XCTUnwrap(editor(host)); XCTAssertTrue(view.isRichText)
                    XCTAssertEqual(MacMarkdown.markdown(view.attributedString()), store.body, "Untouched native rendering keeps the source bytes")
                    if deferredHeads.contains(where: { $0.body == body }) {
                        XCTAssertFalse(view.string.contains("• \n"), "A delayed first paragraph is the item's body, not an extra empty bullet")
                    }
                    let word = (view.string as NSString).range(of: "Nested")
                    guard word.location != NSNotFound else { return XCTFail("The public workspace must render the item body") }
                    window.makeFirstResponder(view); view.setSelectedRange(word); view.insertText("Edited", replacementRange: word)
                    let saved = await store.save(); XCTAssertTrue(saved)
                    let expected = (rootProse + tabLists + deferredHeads).first { $0.body == body }.map { note("container", title: "Container", body: $0.edited) }
                        ?? original.replacingOccurrences(of: "Nested", with: "Edited")
                    XCTAssertEqual(try Data(contentsOf: file), Data(expected.utf8), "Saved spelling for \(body.debugDescription)")
                    let reopened = MacWorkspace(); await reopened.openVault(root); await reopened.openNote("Work/Container.md")
                    XCTAssertFalse(reopened.sourceMode); XCTAssertEqual(reopened.body, store.body)
                }
                if needsSource {
                    store.changed(store.body + "\nOutside paragraph.\n")
                    let saved = await store.save()
                    XCTAssertTrue(saved)
                    XCTAssertEqual(try Data(contentsOf: file), Data((original + "\nOutside paragraph.\n").utf8))
                }
            }
        }
    }
    func testBacklinksRecognizeStyledIdentityAndIgnoreCodePrefixesAndAmbiguousTitles() async throws {
        let source = note("source", title: "Source") + "\n[**Project** plan](#zerus-note:zerus%3Atarget%7CProject%20plan)\n"
        try await withVault([
            "Work/Target.md": note("target", title: "Same"),
            "Work/Other.md": note("other", title: "Same"),
            "Work/Source.md": source,
            "Work/Examples.md": note("examples", title: "Examples") + "\n```md\n[[zerus:target|Same]]\n```\n\n`[[zerus:target|Same]]`\n\nA literal zerus:target in prose.\n",
            "Work/Prefix.md": note("prefix", title: "Prefix") + "\n[[zerus:target-other|A different ID]]\n",
            "Work/Ambiguous.md": note("ambiguous", title: "Ambiguous") + "\n[[Same]]\n"
        ]) { root, store in
            await store.openNote("Work/Target.md")
            XCTAssertEqual(store.backlinks.map(\.path), ["Work/Source.md"])
            let file = root.appendingPathComponent("Work/Source.md")
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), source, "Indexing must not normalize the source file")
            try Data(self.note("source", title: "Source").utf8).write(to: file)
            await store.refresh()
            XCTAssertTrue(store.backlinks.isEmpty, "An outside edit must invalidate the parsed source link cache")
        }
    }
    func testRefreshFollowsUniqueExternalRenameWithoutLosingTabsOrRequiringRelaunch() async throws {
        for context in ["selected", "background-note", "collection", "reused-path"] {
            try await withVault(["Work/A.md": note("external-rename", title: "A"), "Work/B.md": note("b", title: "B")]) { root, store in
                await store.openNote("Work/A.md")
                store.togglePinnedTab(.note("Work/A.md"))
                let position = try XCTUnwrap(store.tabs.firstIndex(of: .note("Work/A.md")))
                if context == "background-note" { await store.openNote("Work/B.md") }
                else if context != "selected" { await store.openCollection("Work", folder: true); store.query = "B" }
                let previousSelection = store.selection, previousBody = store.body, previousActive = store.activeTab
                let previousDestination = store.destination, previousQuery = store.query
                let original = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
                try FileManager.default.createDirectory(at: root.appendingPathComponent("Other"), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: root.appendingPathComponent("Work/A.md"), to: root.appendingPathComponent("Other/Renamed.md"))
                let replacement = Data(self.note("replacement", title: "Different note").utf8)
                if context == "reused-path" { try replacement.write(to: root.appendingPathComponent("Work/A.md")) }
                await store.refresh()
                XCTAssertEqual(store.tabs.dropFirst(position).first, .note("Other/Renamed.md"), context)
                XCTAssertFalse(store.tabs.contains(.note("Work/A.md")), context)
                XCTAssertEqual(store.pinnedTabs, [.note("Other/Renamed.md")], context)
                if context == "selected" {
                    XCTAssertEqual(store.selection, "Other/Renamed.md")
                    XCTAssertEqual(store.current?.stableID, "external-rename")
                } else {
                    XCTAssertEqual(store.selection, previousSelection, context)
                    XCTAssertEqual(store.body, previousBody, context)
                    XCTAssertEqual(store.activeTab, previousActive, context)
                    XCTAssertEqual(store.destination, previousDestination, context)
                    XCTAssertEqual(store.query, previousQuery, context)
                    await store.historyStep(-1)
                    XCTAssertEqual(store.selection, "Other/Renamed.md", "Back must follow the original note, \(context)")
                    await store.historyStep(1)
                    XCTAssertEqual(store.activeTab, previousActive, context)
                }
                await store.activateTab(.note("Other/Renamed.md"))
                XCTAssertEqual(store.selection, "Other/Renamed.md", context)
                XCTAssertEqual(store.current?.stableID, "external-rename", context)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Other/Renamed.md")), original, context)
                if context == "reused-path" { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), replacement) }
                let reopened = MacWorkspace(); await reopened.openVault(root); await reopened.refresh()
                XCTAssertTrue(reopened.tabs.contains(.note("Other/Renamed.md")), context)
                XCTAssertFalse(reopened.tabs.contains(.note("Work/A.md")), context)
                XCTAssertEqual(reopened.pinnedTabs, [.note("Other/Renamed.md")], context)
                let outside = String(decoding: original, as: UTF8.self) + "\n```swift\nlet outside = true\n```\n"
                try Data(outside.utf8).write(to: root.appendingPathComponent("Other/Renamed.md"))
                await store.refresh(); XCTAssertEqual(store.current?.content, outside); XCTAssertFalse(store.sourceMode)
            }
        }
        for selected in [false, true] {
            try await withVault(["Work/A.md": note("a", title: "A"), "Work/B.md": note("b", title: "B")]) { root, store in
                await store.openNote("Work/A.md"); store.togglePinnedTab(.note("Work/A.md"))
                await store.openNote("Work/B.md")
                if selected { await store.openNote("Work/A.md") } else { await store.openCollection("Work", folder: true) }
                let a = try XCTUnwrap(store.tabs.firstIndex(of: .note("Work/A.md")))
                let b = try XCTUnwrap(store.tabs.firstIndex(of: .note("Work/B.md")))
                let tabCount = store.tabs.count
                let originalA = try Data(contentsOf: root.appendingPathComponent("Work/A.md")), originalB = try Data(contentsOf: root.appendingPathComponent("Work/B.md"))
                try FileManager.default.moveItem(at: root.appendingPathComponent("Work/A.md"), to: root.appendingPathComponent("Work/Temporary.md"))
                try FileManager.default.moveItem(at: root.appendingPathComponent("Work/B.md"), to: root.appendingPathComponent("Work/A.md"))
                try FileManager.default.moveItem(at: root.appendingPathComponent("Work/Temporary.md"), to: root.appendingPathComponent("Work/B.md"))
                await store.refresh()
                XCTAssertEqual(store.tabs.dropFirst(a).first, .note("Work/B.md"))
                XCTAssertEqual(store.tabs.dropFirst(b).first, .note("Work/A.md"))
                XCTAssertEqual(store.tabs.count, tabCount)
                XCTAssertEqual(Set(store.tabs).count, store.tabs.count)
                XCTAssertEqual(store.pinnedTabs, [.note("Work/B.md")])
                XCTAssertEqual(store.selection, selected ? "Work/B.md" : nil)
                await store.activateTab(.note("Work/A.md")); XCTAssertEqual(store.current?.stableID, "b")
                await store.activateTab(.note("Work/B.md")); XCTAssertEqual(store.current?.stableID, "a")
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), originalB)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/B.md")), originalA)
            }
        }
        for scenario in ["duplicate-before", "duplicate-after", "no-id", "retained-destination"] {
            var files = ["Work/A.md": scenario == "no-id" ? "# A\n\nNo identity.\n" : note("a", title: "A"), "Work/B.md": note("b", title: "B")]
            if scenario == "duplicate-before" { files["Work/Duplicate.md"] = note("a", title: "Duplicate") }
            try await withVault(files) { root, store in
                await store.openNote("Work/A.md"); store.togglePinnedTab(.note("Work/A.md"))
                if scenario == "retained-destination" { await store.openNote("Work/B.md") }
                else { await store.openCollection("Work", folder: true) }
                let active = store.activeTab, body = store.body
                let original = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
                let target = scenario == "retained-destination" ? "Work/B.md" : "Work/Moved.md"
                if scenario == "retained-destination" { try FileManager.default.removeItem(at: root.appendingPathComponent(target)) }
                try FileManager.default.moveItem(at: root.appendingPathComponent("Work/A.md"), to: root.appendingPathComponent(target))
                if scenario == "duplicate-before" { try FileManager.default.removeItem(at: root.appendingPathComponent("Work/Duplicate.md")) }
                if scenario == "duplicate-after" { try Data(self.note("a", title: "Duplicate").utf8).write(to: root.appendingPathComponent("Work/Duplicate.md")) }
                await store.refresh()
                XCTAssertTrue(store.tabs.contains(.note("Work/A.md")), scenario)
                XCTAssertEqual(store.pinnedTabs, [.note("Work/A.md")], scenario)
                XCTAssertEqual(store.activeTab, active, scenario); XCTAssertEqual(store.body, body, scenario)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(target)), original, scenario)
                if scenario == "retained-destination" {
                    XCTAssertEqual(store.noteDiskChange, .replaced)
                    let saved = await store.save(); XCTAssertFalse(saved)
                    let copy = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".md")
                    defer { try? FileManager.default.removeItem(at: copy) }
                    try store.exportRetainedNote(to: copy); try await store.useSavedNoteAfterExport()
                }
            }
        }
    }
    func testRefreshKeepsConflictingDraftUntilItsCurrentExportCanBeVerified() async throws {
        let original = note("conflict", title: "A")
        try await withVault(["Work/A.md": original]) { root, store in
            let file = root.appendingPathComponent("Work/A.md")
            let copy = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".md")
            defer { try? FileManager.default.removeItem(at: copy) }
            await store.openNote("Work/A.md"); store.changed("# A\n\nLocal café draft.\n")
            let local = store.body, outside = original + "\nOutside update.\n"
            try Data(outside.utf8).write(to: file); await store.refresh()
            XCTAssertEqual(store.noteDiskChange, .modified); XCTAssertEqual(store.body, local)
            let saved = await store.save(); XCTAssertFalse(saved); XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), outside)
            XCTAssertThrowsError(try store.exportRetainedNote(to: file))
            try store.exportRetainedNote(to: copy)
            XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), NoteDocument(path: "Work/A.md", content: original, modified: .distantPast).replacingBody(local))
            store.changed(local + "New draft line.\n"); XCTAssertFalse(store.retainedExportReady)
            do { try await store.useSavedNoteAfterExport(); XCTFail("A stale copy cannot release changed text") } catch {}
            XCTAssertTrue(store.body.hasSuffix("New draft line.\n"))
            for tamper in [false, true] {
                try store.exportRetainedNote(to: copy)
                if tamper { try Data("Changed exported copy".utf8).write(to: copy) } else { try FileManager.default.removeItem(at: copy) }
                do { try await store.useSavedNoteAfterExport(); XCTFail("A missing or changed export cannot release retained text") } catch {}
                XCTAssertNotNil(store.noteDiskChange)
            }
            try store.exportRetainedNote(to: copy); try await store.useSavedNoteAfterExport()
            XCTAssertNil(store.noteDiskChange); XCTAssertEqual(store.current?.content, outside); XCTAssertEqual(store.body, store.current?.parts.body)
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), outside)
            XCTAssertTrue(try String(contentsOf: copy, encoding: .utf8).hasSuffix("New draft line.\n"))
        }
    }
    func testRefreshRetainsDirtyMovedAndCleanReplacedOrMissingNotesBeforeExport() async throws {
        for scenario in ["moved", "replaced", "missing", "ambiguous", "restored", "trashed"] {
            let original = note("retained", title: "A")
            let notePath = scenario == "trashed" ? ".trash/A.md" : "Work/A.md"
            var files = [notePath: original]
            if scenario == "ambiguous" || scenario == "trashed" { files["Work/Duplicate.md"] = note("retained", title: "Duplicate") }
            try await withVault(files) { root, store in
                await store.openNote(notePath)
                if scenario == "moved" { store.changed(store.body + "\nLocal moved draft.\n") }
                let retained = store.body, file = root.appendingPathComponent(notePath), moved = root.appendingPathComponent("Work/Moved.md")
                if scenario == "moved" || scenario == "ambiguous" { try FileManager.default.moveItem(at: file, to: moved) }
                else if scenario == "replaced" { try Data(self.note("new-identity", title: "Replacement").utf8).write(to: file) }
                else { try FileManager.default.removeItem(at: file) }
                await store.refresh()
                XCTAssertEqual(store.selection, notePath); XCTAssertEqual(store.body, retained)
                XCTAssertEqual(store.noteDiskChange, scenario == "moved" ? .moved("Work/Moved.md") : scenario == "replaced" ? .replaced : .missing)
                if scenario == "restored" {
                    try Data((original + "\nReturned outside version.\n").utf8).write(to: file)
                    await store.refresh(); XCTAssertEqual(store.body, retained); XCTAssertEqual(store.noteDiskChange, .modified)
                }
                let saved = await store.save(); XCTAssertFalse(saved)
                if scenario != "replaced" && scenario != "restored" { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path)) }
                let copy = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".md")
                defer { try? FileManager.default.removeItem(at: copy) }
                try store.exportRetainedNote(to: copy); try await store.useSavedNoteAfterExport()
                XCTAssertNil(store.noteDiskChange)
                if scenario == "moved" { XCTAssertEqual(store.selection, "Work/Moved.md"); XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), original) }
                else if scenario == "replaced" { XCTAssertEqual(store.current?.stableID, "new-identity") }
                else if scenario == "restored" { XCTAssertTrue(store.body.contains("Returned outside version.")) }
                else { XCTAssertNil(store.current); XCTAssertFalse(store.tabs.contains(.note(notePath))) }
                XCTAssertTrue(try String(contentsOf: copy, encoding: .utf8).hasSuffix(retained))
            }
        }
    }
    func testOutlineFollowsLatestDraftAndNoteSwitches() async throws {
        let first = "# Original outline\n\n## Repeated heading\nOne.\n\n```md\n## Hidden code heading\n```\n\n> ## Quoted heading\n\n- ### Item heading\n\n## Repeated heading\nTwo.\n"
        let second = "# Other note\n"
        try await withVault(["Work/A.md": first, "Work/B.md": second]) { root, store in
            await store.openNote("Work/A.md")
            let host = NSHostingView(rootView: MacWorkspaceView(store: store).environment(\.colorScheme, .light))
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            @MainActor func expectOutline(_ titles: [String]) async throws {
                let known = ["Original outline", "Repeated heading", "Quoted heading", "Item heading", "Hidden code heading", "Interim draft", "Latest draft", "Destination", "Other note"]
                var observed: [String] = []
                for _ in 0..<20 {
                    try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
                    let image = try XCTUnwrap(bitmap.cgImage)
                    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
                    // The inspector column begins near 74% of the 1400-point window.
                    request.regionOfInterest = CGRect(x: 0.745, y: 0, width: 0.255, height: 1)
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    observed = text.compactMap { value in known.first { $0.caseInsensitiveCompare(value) == .orderedSame } }
                    if observed == titles { return }
                }
                XCTFail("The rendered Outline must reflect the current draft; observed: \(observed)")
            }
            try await expectOutline(["Original outline", "Repeated heading", "Quoted heading", "Item heading", "Repeated heading"])
            store.changed("# Interim draft\n")
            try await expectOutline(["Interim draft"])
            @MainActor func editor(_ node: NSView) -> NSTextView? {
                if let text = node as? NSTextView, text.isEditable { return text }
                return node.subviews.lazy.compactMap(editor).first
            }
            let originalEditor = try XCTUnwrap(editor(host))
            XCTAssertTrue(originalEditor.string.contains("Interim draft"))
            let latest = "# Latest draft\n\n## Destination\nCurrent text.\n"
            store.changed(latest)
            try await expectOutline(["Latest draft", "Destination"])
            XCTAssertTrue(editor(host) === originalEditor, "Further draft edits must keep the live editor instance")
            XCTAssertTrue(originalEditor.string.contains("Latest draft"), "The editor must update even while save status remains Unsaved changes")
            XCTAssertFalse(originalEditor.string.contains("Interim draft"))
            XCTAssertEqual(store.body, latest)
            let saved = await store.save(); XCTAssertTrue(saved)
            await store.openNote("Work/B.md")
            try await expectOutline(["Other note"])
            await store.openNote("Work/A.md")
            try await expectOutline(["Latest draft", "Destination"])
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8), latest)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/B.md"), encoding: .utf8), second)
        }
    }
    func testFollowingHeadingLinksRetainsFragmentsAndLocalUnsavedText() async throws {
        try await withVault(["Work/Source.md": note("source", title: "Source"), "Work/Target.md": note("target", title: "Target") + "\n## Café plan\nFirst.\n\n## Café plan\nSecond.\n"]) { root, store in
            await store.openNote("Work/Source.md")
            store.body += "\n## Local draft\nNot saved.\n"
            let sourceBytes = try Data(contentsOf: root.appendingPathComponent("Work/Source.md"))
            await store.follow("#local-draft")
            XCTAssertEqual(store.selection, "Work/Source.md"); XCTAssertEqual(store.headingRequest?.fragment, "local-draft")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Source.md")), sourceBytes)
            // Ordinary file links emitted by Add file are attachments, not
            // note-title lookups. Opening them must keep this unsaved editor.
            try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
            let attachment = root.appendingPathComponent("assets/report café.txt"), bytes = Data("Attachment café.\n".utf8)
            try bytes.write(to: attachment)
            let draft = store.body
            for link in ["../assets/report%20caf%C3%A9.txt", "assets/report%20caf%C3%A9.txt"] {
                store.previewDocument = nil; store.issue = nil
                await store.follow(link)
                XCTAssertEqual(store.previewDocument?.url.standardizedFileURL, attachment.standardizedFileURL, "A local attachment link must open the file preview")
                XCTAssertEqual(store.selection, "Work/Source.md"); XCTAssertEqual(store.body, draft)
                XCTAssertEqual(try Data(contentsOf: attachment), bytes)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Source.md")), sourceBytes)
            }
            store.previewDocument = nil; store.issue = nil
            await store.follow("../../outside.txt")
            XCTAssertNil(store.previewDocument); XCTAssertNotNil(store.issue)
            store.issue = nil
            await store.follow("zerus:target#café-plan-1")
            XCTAssertEqual(store.selection, "Work/Target.md"); XCTAssertEqual(store.headingRequest?.fragment, "café-plan-1")
            XCTAssertEqual(store.headingRequest?.path, "Work/Target.md")
            await store.openNote("Work/Source.md"); await store.follow("Target.md#caf%C3%A9-plan")
            XCTAssertEqual(store.selection, "Work/Target.md"); XCTAssertEqual(store.headingRequest?.fragment, "café-plan")
            await store.openNote("Work/Source.md"); await store.follow("zerus:target#missing")
            XCTAssertEqual(store.selection, "Work/Target.md"); XCTAssertNil(store.headingRequest)
            XCTAssertTrue(store.issue?.contains("heading") ?? false)
        }
    }
    func testLinkedNoteCreationKeepsEditorAndRejectsCollisionsAndOldVaultRequests() async throws {
        try await withVault(["Work/Source.md": note("source", title: "Source"), "Work/Taken.md": note("taken", title: "Different title")]) { root, store in
            await store.openNote("Work/Source.md"); store.body = "# Source\nUnsaved source text."
            let before = try Data(contentsOf: root.appendingPathComponent("Work/Source.md")), taken = try Data(contentsOf: root.appendingPathComponent("Work/Taken.md")), origin = store.workspaceID
            let created = try await store.createLinkedNote(title: "New linked note", folder: "Work", workspaceID: origin)
            XCTAssertEqual(created.path, "Work/New linked note.md"); XCTAssertNotNil(created.stableID)
            XCTAssertEqual(store.selection, "Work/Source.md"); XCTAssertEqual(store.body, "# Source\nUnsaved source text.")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Source.md")), before)
            let reused = try await store.createLinkedNote(title: "New linked note", folder: "Work", workspaceID: origin)
            XCTAssertEqual(reused.path, created.path); XCTAssertEqual(reused.stableID, created.stableID)
            do { _ = try await store.createLinkedNote(title: "Taken", folder: "Work", workspaceID: origin); XCTFail("A matching filename with another title must not be overwritten") } catch {}
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/Taken.md")), taken)
            do { _ = try await store.createLinkedNote(title: "Wrong vault", folder: "Work", workspaceID: UUID()); XCTFail("A stale picker cannot create in another vault") } catch {}
            await store.follow("Missing linked note")
            XCTAssertEqual(store.missingNoteLink?.title, "Missing linked note"); XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/Missing linked note.md").path), "Following a missing link must ask before creation")
        }
    }
    /// The shared filter has its own tests; this protects the Mac Trash integration
    /// that previously passed trashed paths into a filter that always rejects them.
    func testTrashShowsAndRestoresTheDeletedNote() async throws {
        try await withVault(["Work/A.md": note("a", title: "A")]) { root, store in
            let original = try XCTUnwrap(store.notes.first)
            await store.trash(original)
            await store.openCollection("Trash")
            XCTAssertEqual(store.collection.map(\.path), [".trash/Work/A.md"])
            guard let deleted = store.collection.first else { return }
            await store.trash(deleted)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/A.md").path))
            XCTAssertFalse(store.notes.contains(where: \.trashed))
        }
    }
    func testLoadingRefusesNewNotesButRetainsLateWritingAndRecoveryDraft() async throws {
        try await withVault(["Work/A.md": note("loading", title: "A")]) { root, store in
            await store.openNote("Work/A.md")
            let before = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
            let draft = store.body + "\nLate writing already accepted by the editor.\n"
            store.busy = true
            let created = await store.createNote(title: "Must not create")
            XCTAssertNil(created, "Commands must not create a note while the workspace is loading")
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Inbox/Must not create.md").path))
            XCTAssertEqual(store.selection, "Work/A.md")
            store.changed(draft)
            XCTAssertEqual(store.body, draft, "Late callbacks must retain writing even while loading")
            let locations = try MacNoteRecoveryStore.locations(root: root, path: "Work/A.md")
            XCTAssertFalse(locations.isEmpty, "Late writing needs a durable recovery checkpoint before switching")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), before)
            store.busy = false
            let saved = await store.save(); XCTAssertTrue(saved)
            XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8).contains("Late writing already accepted"))
        }
    }
    func testNavigationRestoresDistinctFolderAndGlobalTabsAndTheirFilters() async throws {
        try await withVault(["Tasks/A.md": "---\nzerus-id: a\nStatus: Draft\nDue: 2026-11-16\n---\n# A\n\nBody.\n", "Work/B.md": note("b", title: "B"), "Root.md": note("root", title: "Root")]) { root, store in
            await store.openNote("Work/B.md")
            await store.openCollection("External Notes")
            await store.openNote("Root.md")
            XCTAssertEqual(store.selection, "Root.md")
            XCTAssertEqual(store.destination, "All Notes", "A root-level imported note must not select a nonexistent Inbox directory")
            XCTAssertFalse(store.folderCollection)
            XCTAssertTrue(store.collection.contains { $0.path == "Root.md" }, "The opened root note remains visible in its collection")
            await store.openCollection("Tasks")
            await store.openCollection("Tasks", folder: true)
            store.query = "A"; store.filters.sort = .titleDescending; store.hideSubtypes = true
            store.filters.properties = [.init(name: "Status", values: [.init(kind: .text, value: "Draft"), .init(kind: .text, value: "Done")]), .init(name: "Due", dateComparison: .between, date: "2026-11-01", endDate: "2026-11-30")]
            await store.openNote("Work/B.md")
            XCTAssertFalse(store.browsingCollection)
            let draft = store.body + "\nPrivate writing.\n"
            store.browsingCollection = true; store.changed(draft)
            XCTAssertFalse(store.browsingCollection, "Writing in the editor must make the note the active compact pane")
            store.browsingCollection = true
            await store.openNote("Work/B.md")
            XCTAssertFalse(store.browsingCollection, "Choosing the selected note must reveal its editor")
            XCTAssertEqual(store.body, draft); XCTAssertTrue(store.isDirty, "Revealing the same note must not reload or save its draft")
            await store.openCollection("Tasks", folder: true)
            XCTAssertTrue(store.browsingCollection)
            store.inspector = false; store.keepFolderOpen("Tasks")
            let restored = MacWorkspace(); await restored.openVault(root)
            XCTAssertEqual(restored.activeTab, .folder("Tasks"))
            XCTAssertTrue(restored.tabs.contains(.collection("Tasks")))
            XCTAssertTrue(restored.tabs.contains(.note("Work/B.md")))
            XCTAssertTrue(restored.folderCollection)
            XCTAssertEqual(restored.collection.map(\.path), ["Tasks/A.md"])
            XCTAssertEqual(restored.query, "A")
            XCTAssertEqual(restored.filters.sort, .titleDescending)
            XCTAssertTrue(restored.hideSubtypes)
            XCTAssertEqual(restored.filters.properties.count, 2)
            XCTAssertEqual(restored.filters.properties.first?.values?.count, 2)
            XCTAssertEqual(restored.filters.properties.last?.dateComparison, .between)
            XCTAssertFalse(restored.inspector)
            XCTAssertTrue(restored.keptFolders.contains("Tasks"))
            await restored.activateTab(.collection("Tasks"))
            XCTAssertFalse(restored.folderCollection)
            XCTAssertNil(restored.selection)
            // Search results update immediately, while navigation and normal
            // close/reopen must retain the latest query during rapid changes.
            restored.query = "Recent"; restored.query = "Latest"
            XCTAssertTrue(restored.collection.isEmpty)
            await restored.openCollection("Tasks", folder: true)
            XCTAssertEqual(restored.query, "A")
            await restored.activateTab(.collection("Tasks"))
            XCTAssertEqual(restored.query, "Latest")
            restored.query = "Closing query"
            let closed = await restored.prepareToCloseWindow(); XCTAssertTrue(closed)
            let reopened = MacWorkspace(); await reopened.openVault(root)
            XCTAssertEqual(reopened.query, "Closing query")
            reopened.query = "Across windows"
            let peer = MacWorkspace(); await peer.openVault(root)
            XCTAssertEqual(peer.query, "Across windows")
            reopened.query = "Older pending query"
            peer.query = "Newer window query"; peer.inspector.toggle()
            // Allow the older window's pending save to become runnable. The
            // assertion concerns the retained value, not elapsed performance.
            try await Task.sleep(for: .milliseconds(500))
            let latest = MacWorkspace(); await latest.openVault(root)
            XCTAssertEqual(latest.query, "Newer window query", "An older delayed write must not replace newer navigation")
            latest.query = ""
            _ = await latest.prepareToCloseWindow()
        }
    }
    func testMiddleClickClosesWorkspaceTabsWithoutInterceptingOtherGesturesOrLosingFailedSaves() async throws {
        let original = note("middle-a", title: "Active Alpha")
        try await withVault(["Work/A.md": original, "Work/C.md": note("middle-c", title: "Background Charlie"), "Work/D.md": note("middle-d", title: "Next Delta"), "Work/E.md": note("middle-e", title: "Last Echo")]) { root, store in
            for tab in store.tabs { await store.closeTab(tab) }
            await store.openCollection("Work", folder: true)
            await store.openNote("Work/C.md", newTab: true); await store.openNote("Work/A.md", newTab: true)
            await store.openNote("Work/D.md", newTab: true); await store.openNote("Work/E.md", newTab: true); await store.openNote("Work/A.md")
            store.togglePinnedTab(.note("Work/A.md")); store.togglePinnedTab(.note("Work/C.md"))
            // Tabs live in the window toolbar; host the strip itself at the top of the fixture.
            let host = NSHostingView(rootView: MacTabBar(store: store, available: 1200).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            @MainActor func settle() async throws {
                for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
            }
            @MainActor func clickTab(_ title: String, middle: Bool, count: Int = 1) async throws {
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
                try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
                let observed = request.results ?? []
                let match = try XCTUnwrap(observed.compactMap { value -> CGRect? in
                    guard value.boundingBox.midY > 0.9, let text = value.topCandidates(1).first, let range = text.string.range(of: title) else { return nil }
                    return try text.boundingBox(for: range)?.boundingBox
                }.first, "Missing rendered tab \(title): \(observed.compactMap { $0.topCandidates(1).first?.string })")
                let point = host.convert(NSPoint(x: match.midX * host.bounds.width, y: (host.isFlipped ? 1 - match.midY : match.midY) * host.bounds.height), to: nil)
                for clicks in middle ? [count] : Array(1...count) {
                for type in middle ? [NSEvent.EventType.otherMouseDown, .otherMouseUp] : [.leftMouseDown, .leftMouseUp] {
                    var event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
                    if middle {
                        let cg = try XCTUnwrap(event.cgEvent); cg.setIntegerValueField(.mouseEventButtonNumber, value: 2)
                        event = try XCTUnwrap(NSEvent(cgEvent: cg)); XCTAssertEqual(event.buttonNumber, 2); XCTAssertTrue(event.window === window)
                    }
                    NSApp.postEvent(event, atStart: false)
                }
                }
                try await settle()
            }
            try await settle()
            let tabs = store.tabs
            try await clickTab("Background Charlie", middle: false, count: 3)
            XCTAssertEqual(store.tabs, tabs, "A triple left click activates rather than closes a tab")
            XCTAssertEqual(store.selection, "Work/C.md")
            await store.openNote("Work/A.md"); try await settle()
            try await clickTab("Background Charlie", middle: true)
            XCTAssertEqual(store.tabs, tabs.filter { $0 != .note("Work/C.md") })
            XCTAssertEqual(store.selection, "Work/A.md", "Closing a background tab keeps the current editor")
            XCTAssertFalse(store.pinnedTabs.contains(.note("Work/C.md")), "Explicit middle close also closes pinned tabs, like desktop")
            let kept = "# Active Alpha\n\nBody.\nKept.\n"
            store.changed(kept)
            let outside = Data(original.replacingOccurrences(of: "Body.", with: "Outside.").utf8)
            try outside.write(to: root.appendingPathComponent("Work/A.md"))
            try await clickTab("Active Alpha", middle: true)
            XCTAssertTrue(store.tabs.contains(.note("Work/A.md")))
            XCTAssertTrue(store.pinnedTabs.contains(.note("Work/A.md")))
            XCTAssertEqual(store.body, kept, "Middle close cannot discard a draft when saving fails")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), outside)
            try Data(original.utf8).write(to: root.appendingPathComponent("Work/A.md"))
            store.issue = nil; store.changed("# Active Alpha\n\nBody.\n")
            // Restoring disk bytes does not synchronously clear the retained
            // outside-change state. Reconcile through the real refresh before
            // retrying Save, rather than racing the periodic watcher.
            await store.refresh()
            let saved = await store.save(); XCTAssertTrue(saved)
            try await settle(); try await clickTab("Active Alpha", middle: true)
            XCTAssertFalse(store.tabs.contains(.note("Work/A.md")))
            XCTAssertFalse(store.pinnedTabs.contains(.note("Work/A.md")))
            XCTAssertEqual(store.activeTab, .note("Work/D.md"), "Closing the active tab selects its next neighbour, not the final tab")
            XCTAssertEqual(store.selection, "Work/D.md")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(original.utf8))
        }
    }

    func testPinnedTabsRestoreFollowPathsAndStaySeparateFromNoteFlags() async throws {
        try await withVault(["Work/A.md": note("a", title: "A"), "Work/C.md": note("c", title: "C"), "Other/B.md": note("b", title: "B")]) { root, store in
            let original = try Data(contentsOf: root.appendingPathComponent("Work/A.md"))
            await store.openCollection("All Notes")
            await store.openCollection("Work", folder: true)
            await store.openNote("Work/C.md", newTab: true)
            await store.openNote("Work/A.md", newTab: true)
            let order = store.tabs, active = store.activeTab
            let pins: Set<MacTab> = [.collection("All Notes"), .folder("Work"), .note("Work/A.md"), .note("Work/C.md")]
            for tab in pins { store.togglePinnedTab(tab) }
            store.togglePinnedTab(.note("Missing.md"))
            XCTAssertEqual(store.pinnedTabs, pins)
            XCTAssertEqual(store.tabs, order); XCTAssertEqual(store.activeTab, active)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), original)
            XCTAssertFalse(try XCTUnwrap(store.current).pinned, "Pinning a tab must not pin the note")
            do {
                let reopened = MacWorkspace(); await reopened.openVault(root); await reopened.refresh()
                XCTAssertEqual(reopened.pinnedTabs, pins)
                XCTAssertEqual(reopened.tabs, order)
            }
            store.reorderTab(.note("Work/A.md"), before: .collection("All Notes"))
            let index = try XCTUnwrap(store.tabs.firstIndex(of: .note("Work/A.md")))
            XCTAssertEqual(Array(store.tabs.dropFirst(index).prefix(2)), [.note("Work/A.md"), .collection("All Notes")])
            XCTAssertEqual(store.pinnedTabs, pins)
            let move = try await store.prepareNoteMoves(paths: ["Work/A.md"], folder: "Other", workspaceID: store.workspaceID)
            let moved = try await store.commitNoteMoves(move)
            XCTAssertEqual(moved.moved.count, 1)
            XCTAssertEqual(store.pinnedTabs, [.collection("All Notes"), .folder("Work"), .note("Other/A.md"), .note("Work/C.md")])
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Other/A.md")), original)
            let rename = try await store.prepareFolderRename("Work", destination: "Projects")
            try await store.commitFolderRename(rename)
            let renamed: Set<MacTab> = [.collection("All Notes"), .folder("Projects"), .note("Other/A.md"), .note("Projects/C.md")]
            XCTAssertEqual(store.pinnedTabs, renamed)
            do {
                let reopened = MacWorkspace(); await reopened.openVault(root); await reopened.refresh()
                XCTAssertEqual(reopened.pinnedTabs, renamed)
            }
            let otherRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-pinned-tabs-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
            defer {
                UserDefaults.standard.removeObject(forKey: MacNavigationState.key(otherRoot))
                UserDefaults.standard.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(otherRoot.path))
                try? FileManager.default.removeItem(at: otherRoot)
            }
            try Data(self.note("d", title: "D").utf8).write(to: otherRoot.appendingPathComponent("D.md"))
            await store.openVault(otherRoot)
            XCTAssertTrue(store.pinnedTabs.isEmpty)
            await store.openNote("D.md"); store.togglePinnedTab(.note("D.md"))
            await store.openVault(root)
            XCTAssertEqual(store.pinnedTabs, renamed, "Another vault's pins must stay separate")
            await MacStartupCache.shared.invalidate(otherRoot)
            await store.closeTab(.note("Other/A.md"))
            XCTAssertFalse(store.pinnedTabs.contains(.note("Other/A.md")), "Explicit context-menu close is allowed for pinned tabs")
            await store.openNote("Other/A.md")
            XCTAssertFalse(store.pinnedTabs.contains(.note("Other/A.md")), "A closed tab must not silently regain its pin")
            store.togglePinnedTab(.folder("Projects"))
            XCTAssertEqual(store.pinnedTabs, [.collection("All Notes"), .note("Projects/C.md")])

            // A pre-feature version-1 preference has no pinnedTabs field.
            let legacy = #"{"version":1,"tabs":[{"collection":{"_0":"All Notes"}},{"folder":{"_0":"Projects"}}],"active":{"folder":{"_0":"Projects"}},"collections":{},"inspector":false,"currentCollection":"Projects","currentCollectionIsFolder":true,"keptFolders":[],"collapsedFolders":[]}"#
            let legacyState = try JSONDecoder().decode(MacNavigationState.self, from: Data(legacy.utf8)).validated(notes: store.notes, folders: store.folders)
            XCTAssertEqual(legacyState.tabs, [.collection("All Notes"), .folder("Projects")])
            XCTAssertEqual(legacyState.active, .folder("Projects"))
            XCTAssertNil(legacyState.pinnedTabs)
        }
    }

    func testArchivedNavigationRestoresStateAndKeepsLegacyUpdatesAndBookmarks() async throws {
        let files = ["Work/A.md": note("a", title: "A", body: "Needle body.\n"), "Work/B.md": note("b", title: "B"), "Other/C.md": note("c", title: "C")]
        try await withVault(files) { root, store in
            let closed = await store.prepareToCloseWindow(); XCTAssertTrue(closed)
            let defaults = UserDefaults.standard, key = MacNavigationState.key(root)
            let bookmarkKey = "zerus.mac.bookmark." + NativeHistory.hash(root.path)
            let bookmark = try XCTUnwrap(defaults.data(forKey: bookmarkKey))
            let source = #"{"version":1,"tabs":[{"folder":{"_0":"Work"}},{"note":{"_0":"Work/A.md"}}],"active":{"note":{"_0":"Work/A.md"}},"pinnedTabs":[{"note":{"_0":"Work/A.md"}}],"collections":{"folder:Work":{"query":"Needle","mode":"Gallery","sort":"Title: A–Z","date":"Any time","includeArchived":false,"folders":[],"extensions":[],"matchAnyProperty":false,"properties":[],"hideSubtypes":false}},"inspector":false,"currentCollection":"Work","currentCollectionIsFolder":true,"keptFolders":["Work"],"collapsedFolders":["Other"]}"#
            let original = Data(source.utf8)
            defaults.set(original, forKey: key)
            let archive = try MacNavigationArchive.archiveLegacy(original, forKey: key, defaults: defaults)
            defer { try? FileManager.default.removeItem(at: archive) }
            XCTAssertNil(defaults.data(forKey: key))
            XCTAssertEqual(try Data(contentsOf: archive), original, "Migration keeps the exact legacy bytes")
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: archive.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            XCTAssertEqual(defaults.data(forKey: bookmarkKey), bookmark, "Navigation migration cannot alter folder-access bookmarks")
            let reopened = MacWorkspace(); await reopened.openVault(root); await reopened.refresh()
            XCTAssertEqual(reopened.tabs, [.folder("Work"), .note("Work/A.md")])
            XCTAssertEqual(reopened.activeTab, .note("Work/A.md"))
            XCTAssertEqual(reopened.pinnedTabs, [.note("Work/A.md")])
            XCTAssertEqual(reopened.destination, "Work"); XCTAssertTrue(reopened.folderCollection)
            XCTAssertEqual(reopened.query, "Needle"); XCTAssertEqual(reopened.viewMode, "Gallery")
            XCTAssertEqual(reopened.filters.sort, .titleAscending)
            XCTAssertEqual(reopened.keptFolders, ["Work"]); XCTAssertEqual(reopened.collapsedFolders, ["Other"])
            XCTAssertFalse(reopened.inspector)
            XCTAssertEqual(reopened.selection, "Work/A.md")
            let reopenedClosed = await reopened.prepareToCloseWindow(); XCTAssertTrue(reopenedClosed)

            let updated = Data(#"{"version":1,"tabs":[{"folder":{"_0":"Other"}}],"active":{"folder":{"_0":"Other"}},"collections":{},"inspector":true,"currentCollection":"Other","currentCollectionIsFolder":true,"keptFolders":[],"collapsedFolders":[]}"#.utf8)
            defaults.set(updated, forKey: key)
            XCTAssertThrowsError(try MacNavigationArchive.archiveLegacy(original, forKey: key, defaults: defaults)) { XCTAssertTrue($0.localizedDescription.contains("changed")) }
            XCTAssertEqual(defaults.data(forKey: key), updated)
            XCTAssertThrowsError(try MacNavigationArchive.archiveLegacy(updated, forKey: key, defaults: defaults)) { XCTAssertTrue($0.localizedDescription.contains("different")) }
            XCTAssertEqual(defaults.data(forKey: key), updated)
            XCTAssertEqual(try Data(contentsOf: archive), original)
            let newer = MacWorkspace(); await newer.openVault(root); await newer.refresh()
            XCTAssertEqual(newer.destination, "Other", "A newer preference value wins over an older archive")
            XCTAssertTrue(newer.pinnedTabs.isEmpty); XCTAssertEqual(newer.viewMode, "List")
            let newerClosed = await newer.prepareToCloseWindow(); XCTAssertTrue(newerClosed)

            try FileManager.default.removeItem(at: archive)
            let foreign = root.appendingPathComponent("foreign-state.bin"), foreignBytes = Data("Do not read or replace this file".utf8)
            try foreignBytes.write(to: foreign)
            try FileManager.default.createSymbolicLink(at: archive, withDestinationURL: foreign)
            let retained = try XCTUnwrap(defaults.data(forKey: key))
            XCTAssertThrowsError(try MacNavigationArchive.data(forKey: key)) { XCTAssertTrue($0.localizedDescription.contains("ordinary")) }
            XCTAssertThrowsError(try MacNavigationArchive.archiveLegacy(retained, forKey: key, defaults: defaults)) { XCTAssertTrue($0.localizedDescription.contains("ordinary")) }
            XCTAssertEqual(defaults.data(forKey: key), retained)
            XCTAssertEqual(try Data(contentsOf: foreign), foreignBytes)
            for (path, value) in files { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(value.utf8)) }
        }
    }

    func testConfiguredNewNoteFolderPersistsPerVaultAcrossWindowsAndRespectsExplicitDestinations() async throws {
        try await withVault(["Work/A.md": note("a", title: "A"), "Other/B.md": note("b", title: "B")]) { root, store in
            XCTAssertEqual(store.defaultNoteFolder, "Inbox")
            try store.setDefaultNoteFolder("Work", workspace: store.workspaceID)
            let peer = MacWorkspace(); await peer.openVault(root)
            XCTAssertEqual(peer.defaultNoteFolder, "Work")
            for (index, section) in MacNavigationState.globalViews.sorted().enumerated() {
                await store.openCollection(section)
                let created = await store.createNote(title: "From global \(index)")
                XCTAssertEqual(created, "Work/From global \(index).md", section)
                let expectedSection = ["Trash", "Tasks", "External Notes", "Files", "Links"].contains(section) ? "All Notes" : section
                XCTAssertEqual(store.destination, expectedSection, "Creation must preserve the desktop section contract")
                XCTAssertFalse(store.folderCollection)
                if ["Archive", "Pinned"].contains(section) {
                    let reopened = MacWorkspace(); await reopened.openVault(root)
                    // A warm cache can predate the new file. Refresh waits for
                    // its authoritative startup reconciliation before checking it.
                    await reopened.refresh()
                    XCTAssertEqual(reopened.destination, section, "Reopening must retain the accepted section even if the new note is outside its filter")
                    XCTAssertFalse(reopened.folderCollection); XCTAssertEqual(reopened.selection, created)
                }
                XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/From global \(index).md").path))
            }
            await peer.openCollection("All Notes")
            let peerCreated = await peer.createNote(title: "From peer")
            XCTAssertEqual(peerCreated, "Work/From peer.md")
            await store.openCollection("All Notes")
            var changedDuringCreation = false
            let subscription = store.busyPublisher.sink { busy in
                if busy && !changedDuringCreation {
                    changedDuringCreation = true
                    do { try peer.setDefaultNoteFolder("Other", workspace: peer.workspaceID) }
                    catch { XCTFail(error.localizedDescription) }
                }
            }
            let captured = await store.createNote(title: "Captured default")
            subscription.cancel()
            XCTAssertTrue(changedDuringCreation)
            XCTAssertEqual(captured, "Work/Captured default.md", "A new default in a peer window applies to the next note, not an already accepted creation")
            XCTAssertEqual(store.defaultNoteFolder, "Other")
            await store.openCollection("Other", folder: true)
            let inFolder = await store.createNote(title: "From folder")
            XCTAssertEqual(inFolder, "Other/From folder.md")
            let explicit = await store.createNote(title: "Explicit", folder: "Work")
            XCTAssertEqual(explicit, "Work/Explicit.md")
            try peer.setDefaultNoteFolder("Other", workspace: peer.workspaceID)
            XCTAssertEqual(store.defaultNoteFolder, "Other")
            let restored = MacWorkspace(); await restored.openVault(root)
            await restored.openCollection("All Notes")
            let afterRestart = await restored.createNote(title: "After restart")
            XCTAssertEqual(afterRestart, "Other/After restart.md")
            try await withVault(["Separate/A.md": note("separate", title: "Separate")]) { _, separate in
                XCTAssertEqual(separate.defaultNoteFolder, "Inbox")
                let created = await separate.createNote(title: "Separate default")
                XCTAssertEqual(created, "Inbox/Separate default.md")
            }
        }
    }
    func testRootNoteLinkCreationUsesConfiguredDefaultWhenNoFolderWasChosen() async throws {
        try await withVault(["Root.md": note("root", title: "Root"), "Work/A.md": note("a", title: "A")]) { root, store in
            try store.setDefaultNoteFolder("Work", workspace: store.workspaceID)
            await store.openNote("Root.md")
            await store.follow("Missing from root")
            let request = try XCTUnwrap(store.missingNoteLink)
            XCTAssertEqual(request.folder, "Work")
            let completion = try await store.createLinkedNote(title: "From completion", folder: "", workspaceID: store.workspaceID)
            XCTAssertEqual(completion.path, "Work/From completion.md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/From completion.md").path))
            let explicit = try await store.createLinkedNote(title: "Explicit Inbox", folder: "Inbox", workspaceID: store.workspaceID)
            XCTAssertEqual(explicit.path, "Inbox/Explicit Inbox.md")
        }
    }
    func testDocumentCreationFreezesDefaultFolderBeforePeerPreferenceChanges() async throws {
        try await withVault(["Work/A.md": note("a", title: "A"), "Other/B.md": note("b", title: "B"), "Reference.txt": "Keep this original document."]) { root, store in
            try store.setDefaultNoteFolder("Work", workspace: store.workspaceID)
            let request = try await store.prepareFileHub(), source = try NativeFileLease(scope: root.appendingPathComponent("Reference.txt"))
            let peer = MacWorkspace(); await peer.openVault(root)
            try peer.setDefaultNoteFolder("Other", workspace: peer.workspaceID)
            let saved = try await store.saveFileHub(request, source: source, storage: .copy, title: "Reference", folder: request.defaultFolder)
            XCTAssertEqual(saved.path, "Work/Reference.md")
            XCTAssertNotNil(saved.fileHub)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/Reference.md").path))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Reference.txt")), Data("Keep this original document.".utf8))
        }
    }
    func testDefaultInboxUsesTheExistingFolderSpellingAndOpensTheCreatedNote() async throws {
        try await withVault(["inbox/Existing.md": note("existing", title: "Existing"), "Work/A.md": note("a", title: "A")]) { root, store in
            XCTAssertEqual(store.defaultNoteFolder, "inbox")
            XCTAssertEqual(store.defaultNoteFolderOptions.filter { $0.caseInsensitiveCompare("Inbox") == .orderedSame }, ["inbox"])
            await store.openCollection("All Notes")
            let created = await store.createNote(title: "Inbox spelling")
            XCTAssertEqual(created, "inbox/Inbox spelling.md")
            XCTAssertEqual(store.selection, created, "The created path must match the scanned path so its editor can open")
            XCTAssertTrue(store.body.contains("# Inbox spelling"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("inbox/Inbox spelling.md").path))
            try store.setDefaultNoteFolder("inbox", workspace: store.workspaceID)
            await store.openCollection("All Notes")
            var renamed = false
            let subscription = store.busyPublisher.sink { busy in
                if busy && !renamed {
                    renamed = true
                    do {
                        try FileManager.default.moveItem(at: root.appendingPathComponent("inbox"), to: root.appendingPathComponent("Temporary case move"))
                        try FileManager.default.moveItem(at: root.appendingPathComponent("Temporary case move"), to: root.appendingPathComponent("INBOX"))
                    } catch { XCTFail(error.localizedDescription) }
                }
            }
            let recased = await store.createNote(title: "Changed case", folder: "inbox")
            subscription.cancel(); XCTAssertTrue(renamed)
            let actual = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]).first {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && FileManager.default.fileExists(atPath: $0.appendingPathComponent("Changed case.md").path)
            })
            XCTAssertEqual(recased, actual.lastPathComponent + "/Changed case.md")
            XCTAssertEqual(store.defaultNoteFolder, actual.lastPathComponent)
            XCTAssertEqual(store.selection, recased); XCTAssertTrue(store.body.contains("# Changed case"))
        }
    }
    func testNewNoteFolderRefusesStaleOrBusySettingsAndInvalidStoredPathsFallBackToInbox() async throws {
        try await withVault(["Work/A.md": note("a", title: "A")]) { root, store in
            let origin = store.workspaceID
            try store.setDefaultNoteFolder("Work", workspace: origin)
            store.busy = true
            XCTAssertThrowsError(try store.setDefaultNoteFolder("Inbox", workspace: origin)) { XCTAssertTrue($0.localizedDescription.contains("busy")) }
            store.busy = false
            await store.openVault(root)
            XCTAssertThrowsError(try store.setDefaultNoteFolder("Inbox", workspace: origin)) { XCTAssertTrue($0.localizedDescription.contains("vault changed")) }
            XCTAssertEqual(store.defaultNoteFolder, "Work")
            XCTAssertThrowsError(try store.setDefaultNoteFolder("../Outside", workspace: store.workspaceID)) { XCTAssertTrue($0.localizedDescription.contains("available note folder")) }
            UserDefaults.standard.set("../Outside", forKey: MacNewNotePreferences.key(root))
            await store.openCollection("All Notes")
            let created = await store.createNote(title: "Safe default")
            XCTAssertEqual(created, "Inbox/Safe default.md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Inbox/Safe default.md").path))
        }
    }
    func testFolderOrderingMovesWholeSubtreesOnlyAmongSiblingsAndPersistsAcrossPeerWindows() async throws {
        let files = ["Alpha/A.md": note("order-a", title: "A"), "Alpha/One/A.md": note("order-one", title: "One"), "Alpha/Two/A.md": note("order-two", title: "Two"), "Beta/B.md": note("order-b", title: "B"), "Beta/Child/B.md": note("order-bc", title: "Child"), "Gamma/G.md": note("order-g", title: "G")]
        try await withVault(files) { root, store in
            let peer = MacWorkspace(); await peer.openVault(root)
            XCTAssertEqual(store.orderedFolders, ["Alpha", "Alpha/One", "Alpha/Two", "Beta", "Beta/Child", "Gamma"])
            store.collapsedFolders.insert("Alpha")
            let payload = MacFolderOrderTransfer(scope: store.folderOrderScope, source: "Gamma")
            let provider = NSItemProvider(); provider.register(payload)
            let loaded: MacFolderOrderTransfer = try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadTransferable(type: MacFolderOrderTransfer.self) { continuation.resume(with: $0) }
            }
            XCTAssertTrue(store.dropFolder(loaded, target: "Alpha"))
            XCTAssertEqual(store.orderedFolders, ["Gamma", "Alpha", "Alpha/One", "Alpha/Two", "Beta", "Beta/Child"])
            XCTAssertEqual(store.visibleFolders, ["Gamma", "Alpha", "Beta", "Beta/Child"], "Moving a folder cannot expand its collapsed descendants")
            XCTAssertEqual(peer.orderedFolders, store.orderedFolders)
            XCTAssertFalse(store.dropFolder(loaded, target: "Beta"), "A payload with the previous order is stale")
            store.collapsedFolders = []
            let children = MacFolderOrderTransfer(scope: store.folderOrderScope, source: "Alpha/Two")
            XCTAssertFalse(store.dropFolder(children, target: "Beta/Child"), "Ordering never reparents folders")
            XCTAssertTrue(store.dropFolder(children, target: "Alpha/One"))
            XCTAssertEqual(store.orderedFolders, ["Gamma", "Alpha", "Alpha/Two", "Alpha/One", "Beta", "Beta/Child"])
            XCTAssertTrue(store.reorderFolder(.init(scope: store.folderOrderScope, source: "Gamma"), target: "Beta", before: false))
            XCTAssertEqual(store.orderedFolders, ["Alpha", "Alpha/Two", "Alpha/One", "Beta", "Beta/Child", "Gamma"])
            XCTAssertTrue(store.reorderFolder(.init(scope: store.folderOrderScope, source: "Gamma"), target: "Alpha", before: true))
            let busy = MacFolderOrderTransfer(scope: store.folderOrderScope, source: "Beta")
            store.busy = true; XCTAssertFalse(store.dropFolder(busy, target: "Gamma")); store.busy = false
            store.editorSheetActive = true; XCTAssertFalse(store.dropFolder(busy, target: "Gamma")); store.editorSheetActive = false
            let reopened = MacWorkspace(); await reopened.openVault(root)
            XCTAssertEqual(reopened.orderedFolders, store.orderedFolders)
            XCTAssertFalse(reopened.dropFolder(busy, target: "Gamma"), "Another window's drag cannot adopt this workspace")
            let earlier = store.folderOrderScope
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Added"), withIntermediateDirectories: true)
            await store.refresh()
            XCTAssertEqual(store.orderedFolders, ["Gamma", "Alpha", "Alpha/Two", "Alpha/One", "Beta", "Beta/Child", "Added"])
            XCTAssertFalse(store.dropFolder(.init(scope: earlier, source: "Beta"), target: "Gamma"), "A changed folder inventory invalidates a pending drag")
            for (path, text) in files { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(text.utf8), "Folder ordering never changes files") }
            try await withVault(["Alpha/A.md": note("other-order-a", title: "A"), "Gamma/G.md": note("other-order-g", title: "G")]) { _, other in
                XCTAssertEqual(other.orderedFolders, ["Alpha", "Gamma"], "Another vault has its own folder preference")
            }
            let remembered = store.orderedFolders
            await store.openVault(root)
            XCTAssertEqual(store.orderedFolders, remembered)
            XCTAssertFalse(store.dropFolder(busy, target: "Gamma"), "A reopened vault activation refuses its old drag")
        }
    }
    func testDesktopFileOpeningDefersUntilReadyAndKeepsVaultExternalAndDocumentSources() async throws {
        let original = note("desktop-a", title: "A", body: "Original.\n")
        try await withVault(["Work/A.md": original, "Other/B.md": note("desktop-b", title: "B")]) { root, store in
            let outside = root.deletingLastPathComponent().appendingPathComponent("Zerus-Desktop-open-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: outside) }
            let markdown = outside.appendingPathComponent("Outside.markdown"), document = outside.appendingPathComponent("Original.txt")
            let markdownBytes = Data("\u{feff}---\r\nforeign: keep\r\n---\r\n# Outside\r\n\r\nOriginal external.\r\n".utf8), documentBytes = Data("Original document bytes.\r\n".utf8)
            try markdownBytes.write(to: markdown); try documentBytes.write(to: document)
            let waiting = MacWorkspace()
            waiting.desktopFiles.enqueue(root.appendingPathComponent("Work/A.md"))
            waiting.desktopFiles.enqueue(URL(string: "https://example.invalid/ignored.md")!)
            await waiting.desktopFiles.drain(in: waiting)
            XCTAssertEqual(waiting.desktopFiles.pending.count, 1)
            XCTAssertNil(waiting.root)
            await waiting.openVault(root); await waiting.desktopFiles.drain(in: waiting)
            XCTAssertEqual(waiting.selection, "Work/A.md"); XCTAssertTrue(waiting.desktopFiles.pending.isEmpty)
            _ = await waiting.prepareToCloseWindow()
            await store.openNote("Work/A.md")
            let kept = "# A\n\nKept before desktop open.\n"
            store.changed(kept); store.busy = true
            store.desktopFiles.enqueue(root.appendingPathComponent("Work/A.md"))
            store.desktopFiles.enqueue(root.appendingPathComponent("Work/A.md"))
            await store.desktopFiles.drain(in: store)
            XCTAssertEqual(store.desktopFiles.pending.count, 1)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(original.utf8))
            store.busy = false
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 400, height: 300), styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MacWindowCloseProtector(workspace: store))
            let sheet = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 200, height: 100), styleMask: .titled, backing: .buffered, defer: false)
            sheet.isReleasedWhenClosed = false
            defer { window.endSheet(sheet); sheet.close(); window.contentView = nil; window.close() }
            window.beginSheet(sheet, completionHandler: { _ in })
            await store.desktopFiles.drain(in: store)
            XCTAssertEqual(store.desktopFiles.pending.count, 1, "An open receiving-window review keeps the file queued")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(original.utf8))
            window.endSheet(sheet); sheet.orderOut(nil)
            await store.desktopFiles.drain(in: store)
            XCTAssertTrue(store.desktopFiles.pending.isEmpty); XCTAssertEqual(store.selection, "Work/A.md")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(original.replacingOccurrences(of: "Original.", with: "Kept before desktop open.").utf8))
            try store.setDefaultNoteFolder("Work", workspace: store.workspaceID)
            await store.external.restore()
            let existingConnections = Set(store.external.entries.map(\.id))
            store.desktopFiles.enqueue(document); store.desktopFiles.enqueue(markdown)
            await store.desktopFiles.drain(in: store)
            XCTAssertNil(store.issue)
            let hub = try XCTUnwrap(store.current), reference = try XCTUnwrap(hub.fileHub)
            XCTAssertEqual(hub.folder, "Work"); XCTAssertEqual(reference.name, "Original.txt")
            XCTAssertEqual(reference.kind, .local, "Desktop file-open connects the original rather than copying it")
            let connected = try XCTUnwrap(store.external.selected)
            XCTAssertEqual(connected.document.content, String(decoding: markdownBytes.dropFirst(3), as: UTF8.self))
            XCTAssertEqual(Set(store.external.entries.map(\.id)).subtracting(existingConnections), [connected.id])
            let count = store.notes.count, connection = connected.id
            store.desktopFiles.enqueue(document); store.desktopFiles.enqueue(markdown)
            await store.desktopFiles.drain(in: store)
            XCTAssertEqual(store.notes.count, count); XCTAssertEqual(store.current?.path, hub.path)
            XCTAssertEqual(store.external.selected?.id, connection)
            let resolved = try await store.resolveFileHub(hub, workspaceID: store.workspaceID)
            XCTAssertEqual(resolved.canonicalPath, document.resolvingSymlinksInPath().path)
            XCTAssertEqual(try Data(contentsOf: document), documentBytes); XCTAssertEqual(try Data(contentsOf: markdown), markdownBytes)
            store.desktopFiles.enqueue(outside); await store.desktopFiles.drain(in: store)
            XCTAssertTrue(store.issue?.contains("folder or package") == true)
            XCTAssertEqual(store.notes.count, count); XCTAssertTrue(store.desktopFiles.pending.isEmpty)
            XCTAssertEqual(try Data(contentsOf: document), documentBytes); XCTAssertEqual(try Data(contentsOf: markdown), markdownBytes)
            let entry = try XCTUnwrap(store.external.entries.first { $0.id == connection })
            _ = await store.external.close(); await store.external.forget(entry)
            XCTAssertEqual(Set(store.external.entries.map(\.id)), existingConnections)
            if let mappings = store.fileMappings { let file = await mappings.file; try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        }
    }
    func testFolderRenameRemapsOpenNoteAndFolderStateWhileKeepingFileBytes() async throws {
        for interruptedCommit in [false, true] {
            let content = interruptedCommit
                ? "\u{feff}---\r\nforeign: keep\r\n---\r\n# A\r\n\r\nA note with an attachment: [file](document.txt).\r\n"
                : note("a", title: "A", body: "A note with an attachment: [file](document.txt).\n")
            try await withVault(["Work/A.md": content, "Work/document.txt": "retained attachment", "Work/Empty/.keep": "empty folder marker"]) { root, store in
                try FileManager.default.createDirectory(at: root.appendingPathComponent("Other"), withIntermediateDirectories: true)
                await store.refresh()
                XCTAssertTrue(store.reorderFolder(.init(scope: store.folderOrderScope, source: "Work"), target: "Other", before: true))
                await store.openCollection("Work", folder: true)
                store.keepFolderOpen("Work"); store.query = "A"
                await store.openNote("Work/A.md")
                try store.setDefaultNoteFolder("Work/Empty", workspace: store.workspaceID)
                let plan = try await store.prepareFolderRename("Work", destination: "Projects/Work")
                let active: MacWorkspace
                if interruptedCommit {
                    // The real planner and transaction writer produce the committed
                    // rename receipt; stop before the physical-directory finish.
                    // Opening a new workspace must recover both files and navigation.
                    let closed = await store.prepareToCloseWindow(); XCTAssertTrue(closed)
                    try await VaultFiles(root: root).applyTransaction(plan.changes)
                    active = MacWorkspace(); await active.openVault(root)
                } else {
                    try await store.commitFolderRename(plan)
                    active = store
                }
                XCTAssertEqual(active.selection, "Projects/Work/A.md")
                XCTAssertEqual(active.activeTab, .note("Projects/Work/A.md"))
                XCTAssertTrue(active.tabs.contains(.folder("Projects/Work")))
                XCTAssertTrue(active.keptFolders.contains("Projects/Work"))
                XCTAssertEqual(active.destination, "Projects/Work")
                XCTAssertEqual(active.query, "A")
                XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Projects/Work/document.txt"), encoding: .utf8), "retained attachment")
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work").path))
                XCTAssertTrue(active.body.contains("document.txt"))
                let restored = MacWorkspace(); await restored.openVault(root)
                XCTAssertEqual(restored.selection, "Projects/Work/A.md")
                XCTAssertEqual(restored.defaultNoteFolder, "Projects/Work/Empty")
                XCTAssertEqual(restored.orderedFolders.filter { MacFolderOrdering.parent($0) == "Projects/Work" }, ["Projects/Work/Empty"])
                try FileManager.default.createDirectory(at: root.appendingPathComponent("Work"), withIntermediateDirectories: true)
                await restored.refresh()
                XCTAssertEqual(restored.orderedFolders.filter { MacFolderOrdering.parent($0).isEmpty }, ["Other", "Projects", "Work"], "A new folder at the old path cannot inherit its old ordering position")
                await restored.openCollection("All Notes")
                let created = await restored.createNote(title: "Renamed default")
                XCTAssertEqual(created, "Projects/Work/Empty/Renamed default.md")
            }
        }
    }
    func testFolderLifecycleKeepsExactForeignMetadataKeysAndRestoresAcrossUnrelatedEdits() async throws {
        let foreign = #"{"text":"\uFEFFkeep","Café":1,"Cafe\u0301":2,"literal":"Work"}"#
        let definition = #"[{"name":"Related","type":"relation","relationTypeKey":"Work","future":FOREIGN}]"#.replacingOccurrences(of: "FOREIGN", with: foreign)
        let view = #"{"mode":"gallery","future":FOREIGN}"#.replacingOccurrences(of: "FOREIGN", with: foreign)
        let preset = #"[{"id":"kept-view","name":"Kept","config":VIEW}]"#.replacingOccurrences(of: "VIEW", with: view)
        let specs: [(String, String, String, String)] = [
            (".zerus/properties.json", definition, definition, "[]"),
            (".zerus/type-icons.json", #""tabler:Briefcase""#, #""\uFEFFkeep""#, #""tabler:Rocket""#),
            (".zerus/views.json", view, view, #"{"mode":"list"}"#),
            (".zerus/saved-views.json", preset, preset, "[]")
        ]
        var files = ["Work/A.md": "\u{feff}" + note("43600000-0000-4000-8000-000000000001", title: "A").replacingOccurrences(of: "\n", with: "\r\n"), "Other/B.md": note("43600000-0000-4000-8000-000000000002", title: "B")]
        var tails: [String: String] = [:], later: [String: String] = [:]
        for (path, owned, kept, added) in specs {
            let tail = #""Other":KEPT,"Café":KEPT,"Cafe\u0301":KEPT"#.replacingOccurrences(of: "KEPT", with: kept)
            files[path] = #"{"Work":OWNED,"Work/Child":OWNED,TAIL}"#.replacingOccurrences(of: "OWNED", with: owned).replacingOccurrences(of: "TAIL", with: tail)
            tails[path] = "{" + tail + "}"; later[path] = added
        }
        try await withVault(files) { root, store in
            await store.openNote("Work/A.md")
            let rename = try await store.prepareFolderRename("Work", destination: "Projects")
            for (path, _, _, _) in specs { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(files[path]!.utf8), "Review is read-only") }
            try await store.commitFolderRename(rename)
            for (path, _, _, _) in specs {
                let expected = files[path]!.replacingOccurrences(of: #""Work":"#, with: #""Projects":"#).replacingOccurrences(of: #""Work/Child":"#, with: #""Projects/Child":"#).replacingOccurrences(of: #""relationTypeKey":"Work""#, with: #""relationTypeKey":"Projects""#)
                let data = try Data(contentsOf: root.appendingPathComponent(path))
                XCTAssertEqual(data, Data(expected.utf8), path + " keeps unknown tokens while only folder keys/relation targets change")
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
                XCTAssertNotNil(object.object(forKey: "Caf\u{e9}" as NSString)); XCTAssertNotNil(object.object(forKey: "Cafe\u{301}" as NSString))
                XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#"\uFEFFkeep"#), path + " retains the unrelated BOM string")
            }
            let back = try await store.prepareFolderRename("Projects", destination: "Work"); try await store.commitFolderRename(back)
            for (path, _, _, _) in specs { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(files[path]!.utf8)) }
            let trash = try await store.prepareFolderTrash("Work"); try await store.commitFolderTrash(trash)
            for (path, _, _, _) in specs {
                let data = try Data(contentsOf: root.appendingPathComponent(path))
                XCTAssertEqual(data, Data(tails[path]!.utf8), path + " removes only the trashed subtree's settings")
                let text = String(decoding: data, as: UTF8.self)
                let changed = String(text.dropLast()) + #", "Later":"# + later[path]! + "}"
                try Data(changed.utf8).write(to: root.appendingPathComponent(path))
            }
            let io = VaultFiles(root: root), deleted = try await io.folderTrashSnapshot()
            XCTAssertTrue(deleted.issues.isEmpty); let entry = try XCTUnwrap(deleted.entries.first)
            XCTAssertEqual(entry.record.version, 2, "Older clients must not re-encode metadata requiring exact Unicode/BOM preservation")
            let conflictFile = root.appendingPathComponent(".zerus/type-icons.json"), kept = try Data(contentsOf: conflictFile)
            let conflict = Data((String(String(decoding: kept, as: UTF8.self).dropLast()) + #", "Work":"tabler:Heart"}"#).utf8)
            try conflict.write(to: conflictFile)
            do { _ = try await store.prepareFolderRestore(entry); XCTFail("Conflicting current folder settings must not be replaced") } catch { XCTAssertTrue(error.localizedDescription.contains("settings already exist")) }
            XCTAssertEqual(try Data(contentsOf: conflictFile), conflict)
            try kept.write(to: conflictFile)
            let restore = try await store.prepareFolderRestore(entry); try await store.commitFolderTrash(restore)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/A.md")), Data(files["Work/A.md"]!.utf8))
            for (path, owned, _, _) in specs {
                let data = try Data(contentsOf: root.appendingPathComponent(path)), text = String(decoding: data, as: UTF8.self)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
                XCTAssertNotNil(object.object(forKey: "Caf\u{e9}" as NSString)); XCTAssertNotNil(object.object(forKey: "Cafe\u{301}" as NSString)); XCTAssertNotNil(object.object(forKey: "Later"))
                XCTAssertTrue(text.contains(#"\uFEFFkeep"#)); XCTAssertTrue(text.contains(owned), path + " restores original owned value tokens")
            }
        }
    }

    func testFolderTrashAndRestoreKeepsAttachmentsAndReconcilesOpenTabs() async throws {
        try await withVault(["Work/A.md": note("a", title: "A"), "Work/file.txt": "keep these bytes", "Other/B.md": note("b", title: "B")]) { root, store in
            XCTAssertTrue(store.reorderFolder(.init(scope: store.folderOrderScope, source: "Work"), target: "Other", before: true))
            await store.openNote("Work/A.md")
            try store.setDefaultNoteFolder("Work", workspace: store.workspaceID)
            let io = try XCTUnwrap(store.io), trash = try await store.prepareFolderTrash("Work")
            try await store.commitFolderTrash(trash)
            XCTAssertFalse(store.tabs.contains(.note("Work/A.md")))
            XCTAssertNotEqual(store.selection, "Work/A.md")
            XCTAssertFalse(store.folders.contains("Work"))
            let deleted = try await io.folderTrashSnapshot(), entry = try XCTUnwrap(deleted.entries.first)
            let restore = try await store.prepareFolderRestore(entry)
            try await store.commitFolderTrash(restore)
            XCTAssertTrue(store.folders.contains("Work"))
            XCTAssertEqual(store.orderedFolders, ["Other", "Work"], "Restoring a folder does not revive its discarded private ordering")
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/file.txt"), encoding: .utf8), "keep these bytes")
            await store.openNote("Work/A.md")
            XCTAssertEqual(store.current?.stableID, "a")
            XCTAssertEqual(store.defaultNoteFolder, "Inbox")
            await store.openCollection("All Notes")
            let created = await store.createNote(title: "After folder restore")
            XCTAssertEqual(created, "Inbox/After folder restore.md")
        }
    }
    func testReviewedChangesRejectAReopenedVaultActivation() async throws {
        try await withVault(["Work/A.md": note("a", title: "A")]) { root, store in
            let snapshot = try await store.bulkReviewSnapshot()
            let bulk = try snapshot.plan(selected: snapshot.source.notes, mutation: .init(pinned: true))
            let rename = try await store.prepareFolderRename("Work", destination: "Renamed")
            await store.openVault(root)
            do { try await store.commitBulk(bulk); XCTFail("An old activation's bulk review must not apply") } catch {}
            do { try await store.commitFolderRename(rename); XCTFail("An old activation's folder review must not apply") } catch {}
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/A.md").path))
            XCTAssertFalse(store.notes.first!.pinned)
        }
    }
    func testCollectionLayoutsRoundTripDesktopSettingsWithoutReplacingForeignFields() async throws {
        let views = #"{"Work":{"mode":"board","groupBy":"Status","visibleProperties":["Status","Due"],"dateProperty":"Due","boardColumnOrder":{"status":["Done","__no_value__","Draft"]},"filters":{"sort":"title-asc","properties":[{"name":"Owner","values":["Ada"]}]},"future":{"retained":true}},"Other":{"mode":"gallery","future":42}}"#
        try await withVault(["Work/A.md": note("a", title: "A"), ".zerus/views.json": views]) { root, store in
            await store.openCollection("Work", folder: true)
            XCTAssertEqual(store.viewMode, "Kanban")
            XCTAssertEqual(store.collectionLayout.groupBy, "Status")
            XCTAssertEqual(store.collectionLayout.boardColumnOrder["status"], ["Done", "__no_value__", "Draft"])
            var layout = store.collectionLayout; layout.dateProperty = "Published"; layout.visibleProperties = ["Due"]
            await store.updateCollectionLayout(layout, mode: "Calendar")
            let data = try Data(contentsOf: root.appendingPathComponent(".zerus/views.json"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let work = try XCTUnwrap(object["Work"] as? [String: Any])
            XCTAssertEqual(work["mode"] as? String, "calendar")
            XCTAssertEqual((work["future"] as? [String: Bool])?["retained"], true)
            XCTAssertEqual((work["filters"] as? [String: Any])?["sort"] as? String, "title-asc")
            XCTAssertEqual((object["Other"] as? [String: Any])?["future"] as? Int, 42)
            let reopened = MacWorkspace(); await reopened.openVault(root)
            XCTAssertEqual(reopened.activeTab, .folder("Work"))
            XCTAssertNil(reopened.selection)
            await reopened.openCollection("Work", folder: true)
            XCTAssertEqual(reopened.viewMode, "Calendar")
            XCTAssertEqual(reopened.collectionLayout.dateProperty, "Published")
            XCTAssertEqual(reopened.collectionLayout.visibleProperties, ["Due"])
        }
    }
    func testTableCellEditsAnUnopenedNoteAndRejectsOutsideEdits() async throws {
        let original = "---\nzerus-id: b\nStatus: Draft # keep comment\nforeign: {nested: true}\n---\n# B\n\nKeep this body.\n"
        try await withVault(["Work/A.md": note("a", title: "A"), "Work/B.md": original]) { root, store in
            await store.openNote("Work/A.md")
            try await store.setCollectionProperty(path: "Work/B.md", expected: original, workspaceID: store.workspaceID, name: "Status", value: .text("Done"))
            let changed = try String(contentsOf: root.appendingPathComponent("Work/B.md"), encoding: .utf8)
            XCTAssertTrue(changed.contains("Status: \"Done\" # keep comment"))
            XCTAssertTrue(changed.contains("foreign: {nested: true}"))
            XCTAssertTrue(changed.hasSuffix("Keep this body.\n"))
            XCTAssertEqual(store.selection, "Work/A.md")
            let external = changed + "Outside edit.\n"
            try Data(external.utf8).write(to: root.appendingPathComponent("Work/B.md"))
            do { try await store.setCollectionProperty(path: "Work/B.md", expected: changed, workspaceID: store.workspaceID, name: "Status", value: .text("Lost")); XCTFail("Outside edits must survive a stale cell editor") } catch {}
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/B.md"), encoding: .utf8), external)
        }
    }
    func testBoardDropsKeepTheirOriginalScopeAndPersistColumnMoves() async throws {
        let schema = #"{"Work":[{"name":"Status","type":"list","listOptions":["Draft","Review","Done"],"listMultiple":false}]}"#
        let views = #"{"Work":{"mode":"board","groupBy":"Status","future":42},"Other":{"mode":"gallery","future":"keep"}}"#
        try await withVault(["Work/A.md": "---\nzerus-id: a\nStatus: Draft\n---\n# A\n", ".zerus/properties.json": schema, ".zerus/views.json": views]) { root, store in
            await store.openCollection("Work", folder: true)
            let scope = try XCTUnwrap(store.boardScope)
            let column = MacBoardTransfer(scope: scope, item: .column(nil))
            let provider = NSItemProvider(); provider.register(column)
            let delivered: MacBoardTransfer = try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadTransferable(type: MacBoardTransfer.self) { continuation.resume(with: $0) }
            }
            try await store.reorderBoardDrop(delivered, target: "Done", scope: scope)
            XCTAssertEqual(store.boardScope?.columns, ["Draft", "Review", "Done", nil], "Moving a column shifts intervening columns rather than swapping the endpoints")
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/views.json"))) as? [String: Any])
            XCTAssertEqual((raw["Work"] as? [String: Any])?["future"] as? Int, 42)
            XCTAssertEqual((raw["Other"] as? [String: Any])?["future"] as? String, "keep")
            let after = try Data(contentsOf: root.appendingPathComponent(".zerus/views.json"))
            do { try await store.reorderBoardDrop(column, target: "Review", scope: scope); XCTFail("An old column order cannot retarget a delayed drop") }
            catch { XCTAssertTrue(error.localizedDescription.contains("board changed"), error.localizedDescription) }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/views.json")), after)
            let current = try XCTUnwrap(store.boardScope), boardLayout = store.collectionLayout
            let card = MacBoardTransfer(scope: current, item: .notes(["Work/A.md"]))
            await store.openCollection("All Notes")
            // Keep the same property and membership: the collection identity itself must reject it.
            store.viewMode = "Kanban"; store.collectionLayout = boardLayout
            XCTAssertEqual(store.boardScope?.columns, current.columns)
            XCTAssertEqual(store.boardScope?.schema, current.schema)
            XCTAssertEqual(store.boardScope?.membership, current.membership)
            do { _ = try await store.prepareBoardDrop(card, target: "Done", scope: current); XCTFail("A delayed card must not land in a different collection") }
            catch { XCTAssertTrue(error.localizedDescription.contains("board changed"), error.localizedDescription) }
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8), "---\nzerus-id: a\nStatus: Draft\n---\n# A\n")
            await store.openCollection("Work", folder: true)
            XCTAssertEqual(store.boardScope?.columns, ["Draft", "Review", "Done", nil])
            let reopened = try XCTUnwrap(store.boardScope)
            store.selectedPaths = ["Work/A.md", "Outside.md"]
            XCTAssertEqual(store.boardSelection(for: try XCTUnwrap(store.notes.first { $0.path == "Work/A.md" })), ["Work/A.md"])
            XCTAssertFalse(store.acceptsBoardDrop(.init(scope: reopened, item: .notes(["Work/A.md"])), target: "Draft", scope: reopened), "Dropping on the current column is a no-op")
            XCTAssertFalse(store.acceptsBoardDrop(.init(scope: reopened, item: .notes([])), target: "Done", scope: reopened))
            XCTAssertFalse(store.acceptsBoardDrop(.init(scope: reopened, item: .notes(["Outside.md"])), target: "Done", scope: reopened))
            XCTAssertFalse(store.acceptsBoardDrop(.init(scope: reopened, item: .notes(["Work/A.md"])), target: "Missing", scope: reopened))
        }
    }
    func testBoardStoredArraysKeepDistinctColumnsAndMovesRemainUndoable() async throws {
        let schema = #"{"Work":[{"name":"Status","type":"list","listOptions":["Draft","Review","Done","Draft, Review"],"listMultiple":false}]}"#
        let views = #"{"Work":{"mode":"board","groupBy":"Status","boardColumnOrder":{"status":["Review","Draft","__no_value__"]}}}"#
        let original = "---\nzerus-id: a\nStatus: [Draft, Review] # keep status\nforeign: {nested: true}\n---\n# A\n\nKeep this body.\n"
        try await withVault(["Work/A.md": original, "Work/B.md": "---\nStatus: \"Draft, Review\"\n---\n# B\n", "Work/C.md": "---\nStatus: []\n---\n# C\n", "Work/D.md": "---\nStatus: [Draft, Draft]\n---\n# D\n", "Work/E.md": "---\nStatus: Queued\n---\n# E\n", "Work/F.md": "---\nStatus: Draft\n---\n# F\n", ".zerus/properties.json": schema, ".zerus/views.json": views]) { root, store in
            await store.openCollection("Work", folder: true)
            let field = try XCTUnwrap(store.boardField), scope = try XCTUnwrap(store.boardScope)
            XCTAssertFalse(field.multiple, "Existing array data must not require enabling a multi-value definition")
            XCTAssertEqual(scope.columns, ["Review", "Draft", nil, "Done", "Draft, Review", "Queued"])
            @MainActor func members(_ column: String?) -> [String] {
                MacCollectionValues.boardGroups(notes: store.collection, field: field, order: scope.columns.map { $0 ?? "__no_value__" }).first { $0.value == column }?.notes.map(\.path).sorted() ?? []
            }
            XCTAssertEqual(members("Review"), ["Work/A.md"])
            XCTAssertEqual(members("Draft"), ["Work/A.md", "Work/D.md", "Work/F.md"])
            XCTAssertEqual(members("Draft, Review"), ["Work/B.md"], "A literal comma label stays distinct from two array values")
            XCTAssertEqual(members(nil), ["Work/C.md"])
            XCTAssertEqual(members("Queued"), ["Work/E.md"])
            XCTAssertEqual(members("Done"), [])
            let invalid = try await store.prepareCollectionMove(paths: ["Work/E.md"], name: "Status", value: .text("Not an option"), workspaceID: store.workspaceID)
            XCTAssertTrue(invalid.changedNotes.isEmpty)
            XCTAssertTrue(invalid.issues.contains { $0.reason.contains("choice") })
            let queued = try await store.prepareBoardDrop(.init(scope: scope, item: .notes(["Work/E.md"])), target: "Done", scope: scope)
            try await store.commitBoardDrop(queued, scope: scope)
            let queuedHistory = try await store.bulkReviewSnapshot(), queuedRecord = try XCTUnwrap(queuedHistory.records.first)
            let restoreQueued = try queuedHistory.transition(queuedRecord.id, undo: true)
            XCTAssertTrue(restoreQueued.issues.isEmpty, restoreQueued.issues.map(\.reason).joined(separator: "; "))
            try await store.commitBulk(restoreQueued)
            XCTAssertEqual(members("Queued"), ["Work/E.md"], "Undo preserves an existing observed value without allowing it as a new selection")
            let file = root.appendingPathComponent("Work/A.md")
            XCTAssertEqual(try Data(contentsOf: file), Data(original.utf8), "Displaying array-valued notes must not rewrite them")
            let transfer = MacBoardTransfer(scope: scope, item: .notes(["Work/A.md"]))
            XCTAssertTrue(store.acceptsBoardDrop(transfer, target: "Draft, Review", scope: scope), "Two selected values are not already the literal comma value")
            let plan = try await store.prepareBoardDrop(transfer, target: "Draft, Review", scope: scope)
            XCTAssertTrue(plan.issues.isEmpty)
            try await store.commitBoardDrop(plan, scope: scope)
            let changed = try String(contentsOf: file, encoding: .utf8)
            XCTAssertTrue(changed.contains("Status: \"Draft, Review\" # keep status"))
            XCTAssertTrue(changed.contains("foreign: {nested: true}"))
            XCTAssertTrue(changed.hasSuffix("Keep this body.\n"))
            XCTAssertEqual(members("Review"), [])
            XCTAssertEqual(members("Draft, Review"), ["Work/A.md", "Work/B.md"])
            let current = try XCTUnwrap(store.boardScope)
            XCTAssertFalse(store.acceptsBoardDrop(.init(scope: current, item: .notes(["Work/A.md"])), target: "Draft, Review", scope: current))
            let history = try await store.bulkReviewSnapshot(), record = try XCTUnwrap(history.records.first)
            let undo = try history.transition(record.id, undo: true)
            XCTAssertTrue(undo.issues.isEmpty, undo.issues.map(\.reason).joined(separator: "; "))
            try await store.commitBulk(undo)
            XCTAssertEqual(MacCollectionValues.value(try XCTUnwrap(store.notes.first { $0.path == "Work/A.md" }), name: "Status"), .list(["Draft", "Review"]))
            XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("# keep status"))
            XCTAssertEqual(members("Review"), ["Work/A.md"])
            XCTAssertEqual(members("Draft, Review"), ["Work/B.md"])
            var snapshot = try await store.bulkReviewSnapshot()
            try await store.commitBulk(snapshot.transition(record.id, undo: false))
            // Only the relevant definition constrains restoration; a different
            // property may change without making Undo unusable.
            let schemaFile = root.appendingPathComponent(".zerus/properties.json")
            var definitions = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: [[String: Any]]])?["Work"])
            definitions.append(["name": "Other", "type": "text"])
            try JSONSerialization.data(withJSONObject: ["Work": definitions], options: [.sortedKeys]).write(to: schemaFile)
            snapshot = try await store.bulkReviewSnapshot()
            let unrelated = try snapshot.transition(record.id, undo: true)
            XCTAssertTrue(unrelated.issues.isEmpty, unrelated.issues.map(\.reason).joined(separator: "; "))
            try await store.commitBulk(unrelated)
            XCTAssertEqual(members("Review"), ["Work/A.md"])
            snapshot = try await store.bulkReviewSnapshot()
            try await store.commitBulk(snapshot.transition(record.id, undo: false))
            let beforeRefusal = try Data(contentsOf: file)
            // Legacy receipts lack definition provenance and keep the strict
            // restoration guard, even if the current definition looks similar.
            let historyFile = root.appendingPathComponent(NativeBulkHistory.path), historyBytes = try Data(contentsOf: historyFile)
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: historyBytes) as? [String: Any])
            var rows = try XCTUnwrap(raw["records"] as? [[String: Any]])
            var entries = try XCTUnwrap(rows[0]["entries"] as? [[String: Any]])
            var fields = try XCTUnwrap(entries[0]["fields"] as? [[String: Any]])
            fields[0].removeValue(forKey: "definitionKey"); entries[0]["fields"] = fields; rows[0]["entries"] = entries; raw["records"] = rows
            try JSONSerialization.data(withJSONObject: raw).write(to: historyFile)
            snapshot = try await store.bulkReviewSnapshot()
            let legacy = try snapshot.transition(record.id, undo: true)
            XCTAssertTrue(legacy.changedNotes.isEmpty)
            XCTAssertTrue(legacy.issues.contains { $0.reason.contains("accepts one value") })
            XCTAssertEqual(try Data(contentsOf: file), beforeRefusal)
            // Raw numeric spelling is never a way to inject another YAML key,
            // even through an edited receipt carrying a definition fingerprint.
            fields[0]["definitionKey"] = try XCTUnwrap(record.entries[0].fields[0].definitionKey)
            fields[0]["before"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NativePropertyValue.number("1\nInjected: true")))
            entries[0]["fields"] = fields; rows[0]["entries"] = entries; raw["records"] = rows
            try JSONSerialization.data(withJSONObject: raw).write(to: historyFile)
            snapshot = try await store.bulkReviewSnapshot()
            let malformed = try snapshot.transition(record.id, undo: true)
            XCTAssertTrue(malformed.changedNotes.isEmpty)
            XCTAssertFalse(malformed.issues.isEmpty)
            XCTAssertEqual(try Data(contentsOf: file), beforeRefusal)
            try historyBytes.write(to: historyFile)
            definitions[0]["listOptions"] = ["Draft", "Review", "Done", "Draft, Review", "Later"]
            try JSONSerialization.data(withJSONObject: ["Work": definitions], options: [.sortedKeys]).write(to: schemaFile)
            snapshot = try await store.bulkReviewSnapshot()
            let refused = try snapshot.transition(record.id, undo: true)
            XCTAssertTrue(refused.changedNotes.isEmpty)
            XCTAssertTrue(refused.issues.contains { $0.reason.contains("definition changed") })
            XCTAssertEqual(try Data(contentsOf: file), beforeRefusal)
            let reopened = MacWorkspace(); await reopened.openVault(root); await reopened.openCollection("Work", folder: true)
            // The schema was edited outside this window. Cached UI becomes
            // authoritative only after the explicitly awaited inventory.
            await reopened.refresh()
            XCTAssertEqual(reopened.boardScope?.columns, ["Review", "Draft", nil, "Done", "Draft, Review", "Later", "Queued"])
        }
    }
    func testBoardAndCalendarMovesWriteTypedPropertiesWithUndo() async throws {
        let schema = #"{"Work":[{"name":"Status","type":"list","listOptions":["Draft","Done"],"listMultiple":false},{"name":"Due","type":"date"},{"name":"Score","type":"number"},{"name":"Checked","type":"checkbox"}]}"#
        try await withVault(["Work/A.md": "---\nzerus-id: a\nStatus: Draft\n---\n# A\n", "Work/B.md": "---\nzerus-id: b\nScore: 2\nChecked: true\n---\n# B\n", ".zerus/properties.json": schema]) { root, store in
            let paths: Set<String> = ["Work/A.md", "Work/B.md"]
            await store.openCollection("Work", folder: true)
            var layout = store.collectionLayout; layout.groupBy = "Status"
            await store.updateCollectionLayout(layout, mode: "Kanban")
            let board = try XCTUnwrap(store.boardScope)
            let move = try await store.prepareBoardDrop(.init(scope: board, item: .notes(paths)), target: "Done", scope: board)
            XCTAssertTrue(move.issues.isEmpty)
            store.busy = true
            do { try await store.commitBoardDrop(move, scope: board); XCTFail("A busy workspace cannot commit a board review") }
            catch { XCTAssertTrue(error.localizedDescription.contains("board changed"), error.localizedDescription) }
            XCTAssertEqual(store.notes.filter { $0.property("Status") == "Done" }.count, 0)
            store.busy = false
            try await store.commitBoardDrop(move, scope: board)
            XCTAssertFalse(store.busy)
            XCTAssertEqual(store.notes.filter { $0.property("Status") == "Done" }.count, 2)
            let date = try await store.prepareCollectionMove(paths: ["Work/A.md"], name: "Due", value: .text("2026-12-31"), workspaceID: store.workspaceID)
            try await store.commitBulk(date)
            let dated = try XCTUnwrap(store.notes.first { $0.path == "Work/A.md" })
            XCTAssertEqual(MacCollectionValues.day(dated, name: "Due").map(MacCollectionValues.wireDate), "2026-12-31")
            let history = try await store.bulkReviewSnapshot(), record = try XCTUnwrap(history.records.first)
            try await store.commitBulk(history.transition(record.id, undo: true))
            XCTAssertNil(store.notes.first { $0.path == "Work/A.md" }?.property("Due"))
            XCTAssertEqual(store.notes.first { $0.path == "Work/A.md" }?.property("Status"), "Done")
            for (name, target, expected) in [("Score", "2", NativePropertyValue.number("2")), ("Checked", "true", .checkbox(true))] {
                layout = store.collectionLayout; layout.groupBy = name
                await store.updateCollectionLayout(layout, mode: "Kanban")
                let typed = try XCTUnwrap(store.boardScope)
                let payload = MacBoardTransfer(scope: typed, item: .notes(["Work/A.md"]))
                let set = try await store.prepareBoardDrop(payload, target: target, scope: typed)
                XCTAssertTrue(set.issues.isEmpty)
                try await store.commitBoardDrop(set, scope: typed)
                XCTAssertEqual(MacCollectionValues.value(try XCTUnwrap(store.notes.first { $0.path == "Work/A.md" }), name: name), expected)
                let clearing = try XCTUnwrap(store.boardScope)
                let clear = try await store.prepareBoardDrop(.init(scope: clearing, item: .notes(["Work/A.md"])), target: nil, scope: clearing)
                try await store.commitBoardDrop(clear, scope: clearing)
                XCTAssertNil(store.notes.first { $0.path == "Work/A.md" }?.property(name))
            }
            let invalid = try await store.prepareCollectionMove(paths: paths, name: "Due", value: .text("2026-02-31"), workspaceID: store.workspaceID)
            XCTAssertEqual(invalid.issues.count, 2)
            XCTAssertTrue(invalid.changedNotes.isEmpty)
        }
    }
    func testBlockMenuUsesTheCurrentSnapshotAndRefusesStaleChoices() async throws {
        let source = "# A\n\n| Name |\n| --- |\n| Value |\n\n```swift\nlet n = 1\n```\n"
        for savedLink in [false, true] {
        let stored = savedLink ? "---\nzerus-id: block-link\nzerus-link-id: block-link\nzerus-link-url: https://example.test/managed\n---\n" + source.replacingOccurrences(of: "# A\n", with: "# A\n\n<https://example.test/managed>\n") : source
        try await withVault(["Work/A.md": stored]) { _, store in
            await store.openNote("Work/A.md")
            var tables: [MacTableRequest] = [], codes: [MacCodeRequest] = []
            let host = NSHostingView(rootView: MacBlockMenu(workspace: store, codeBlocks: true, openTable: { tables.append($0) }, openCode: { codes.append($0) }))
            host.frame = NSRect(x: 0, y: 0, width: 40, height: 25); host.layoutSubtreeIfNeeded()
            func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
            let button = try XCTUnwrap(nodes(host).compactMap { $0 as? NSPopUpButton }.first)
            let menu = try XCTUnwrap(button.menu)
            let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 80, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            func openMenu() {
                let timer = Timer(timeInterval: 0.05, repeats: false) { _ in MainActor.assumeIsolated { menu.cancelTracking() } }
                RunLoop.main.add(timer, forMode: .eventTracking)
                defer { timer.invalidate() }
                _ = menu.popUp(positioning: nil, at: .zero, in: button)
            }
            openMenu()
            let tableIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Edit table 1" })
            menu.performActionForItem(at: tableIndex)
            let table = try XCTUnwrap(tables.last)
            XCTAssertEqual(table.path, "Work/A.md"); XCTAssertEqual(table.workspaceID, store.workspaceID)
            XCTAssertEqual(table.source, source); XCTAssertEqual(table.table.rows, [["Name"], ["Value"]])
            XCTAssertEqual((table.source as NSString).substring(with: try XCTUnwrap(table.range)), "| Name |\n| --- |\n| Value |")
            store.editorSheetActive = false
            store.changedEditor(source.replacingOccurrences(of: "let n = 1", with: "let n = 2"))
            openMenu()
            let codeIndex = try XCTUnwrap(menu.items.firstIndex { $0.title.hasPrefix("Edit code 1") })
            menu.performActionForItem(at: codeIndex)
            let code = try XCTUnwrap(codes.last)
            XCTAssertEqual(code.source, source.replacingOccurrences(of: "let n = 1", with: "let n = 2")); XCTAssertEqual(code.code?.body, "let n = 2")
            XCTAssertEqual((code.source as NSString).substring(with: try XCTUnwrap(code.range)), "```swift\nlet n = 2\n```")
            store.editorSheetActive = false
            openMenu(); store.body += "Changed while the menu was open.\n"
            menu.performActionForItem(at: codeIndex)
            XCTAssertEqual(codes.count, 1); XCTAssertFalse(store.editorSheetActive)
            XCTAssertTrue(store.issue?.contains("changed") == true)
        }
        }
    }
    func testInventoryRefreshRetainsCanonicalUnicodeByteChanges() async throws {
        try await withVault(["Work/A.md": "---\nOwner: Caf\u{e9}\n---\n# Caf\u{e9}\n"]) { _, store in
            var note = try XCTUnwrap(store.notes.first)
            note.path = "Work/Caf\u{e9}.md"
            let first = VaultSnapshot(notes: [note], files: [], folders: ["Work"])
            store.apply(first)
            _ = store.collection
            note.content = "---\nOwner: Cafe\u{301}\n---\n# Cafe\u{301}\n"
            note.path = "Work/Cafe\u{301}.md"
            // A provider may keep timestamps while changing UTF-8 spelling.
            store.apply(VaultSnapshot(notes: [note], files: [], folders: ["Work"]))
            let refreshed = try XCTUnwrap(store.collection.first)
            XCTAssertEqual(Data(refreshed.content.utf8), Data(note.content.utf8))
            XCTAssertEqual(Data(refreshed.path.utf8), Data(note.path.utf8))
            let oldFolder = "Caf\u{e9}", newFolder = "Cafe\u{301}"
            store.apply(VaultSnapshot(notes: [], files: [], folders: [oldFolder, "Zed"]))
            let drag = MacFolderOrderTransfer(scope: store.folderOrderScope, source: oldFolder)
            store.apply(VaultSnapshot(notes: [], files: [], folders: [newFolder, "Zed"]))
            XCTAssertEqual(store.visibleFolders.map { Data($0.utf8) }, [Data(newFolder.utf8), Data("Zed".utf8)], "The sidebar must publish the refreshed path bytes")
            XCTAssertFalse(store.dropFolder(drag, target: "Zed"), "A byte-spelling change invalidates the old folder drag")
            store.apply(VaultSnapshot(notes: [], files: [], folders: [oldFolder, oldFolder + "/Child", newFolder, newFolder + "/Other"]))
            XCTAssertEqual(store.visibleFolders.map { Data($0.utf8) }, [newFolder, newFolder + "/Other", oldFolder, oldFolder + "/Child"].map { Data($0.utf8) }, "Distinct byte-spelled paths keep distinct subtrees")
            XCTAssertTrue(store.dropFolder(.init(scope: store.folderOrderScope, source: oldFolder), target: newFolder))
            XCTAssertEqual(store.visibleFolders.map { Data($0.utf8) }, [oldFolder, oldFolder + "/Child", newFolder, newFolder + "/Other"].map { Data($0.utf8) })
        }
    }
    func testDesktopFiltersSelectTypedValuesAndPersistLatestEditsAcrossCollections() async throws {
        let views = #"{"Work":{"mode":"list","filters":{"sort":"title-asc","future":99,"propertyMatch":"all","properties":[{"name":"Owner","valueKey":"string:Ada","future":42},{"name":"Score","valueKeys":["number:4"]},{"name":"Checked","valueKeys":["boolean:true"]},{"name":"Due","valueKeys":null,"date":{"operator":"between","date":"2026-11-01","endDate":"2026-11-30","future":"keep"}}]},"future":"active"},"Other":{"mode":"gallery","future":"other"}}"#
        let files = ["Work/A.md": "---\nOwner: Ada\nScore: 4\nChecked: true\nDue: 2026-11-16\n---\n# A\n", "Work/B.md": "---\nOwner: Grace\nScore: 4\nChecked: true\nDue: 2026-11-16\n---\n# B\n", "Work/C.md": "---\nOwner: Ada\nScore: \"4\"\nChecked: \"true\"\nDue: 2026-11-16\n---\n# C\n", "Work/D.md": "---\nOwner: Ada\nScore: 4\nChecked: true\nDue: 2026-12-16\n---\n# D\n", ".zerus/views.json": views]
        try await withVault(files) { root, store in
            await store.openCollection("Work", folder: true)
            XCTAssertEqual(store.collection.map(\.title), ["A"])
            let original = try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8)
            try original.replacingOccurrences(of: "Owner: Ada", with: "Owner: Grace").write(to: root.appendingPathComponent("Work/A.md"), atomically: true, encoding: .utf8)
            await store.refresh()
            XCTAssertTrue(store.collection.isEmpty, "A refreshed property change must invalidate the already displayed collection")
            try original.write(to: root.appendingPathComponent("Work/A.md"), atomically: true, encoding: .utf8)
            await store.refresh()
            XCTAssertEqual(store.collection.map(\.title), ["A"], "Restored file properties must become visible again")
            var next = store.filters; next.properties[0].values = [.init(kind: .text, value: "Grace")]
            store.changeCollectionFilters(next)
            next.sort = .titleDescending; store.changeCollectionFilters(next)
            await store.openCollection("Other", folder: true)
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/views.json"))) as? [String: Any])
            let config = try XCTUnwrap(raw["Work"] as? [String: Any]), filters = try XCTUnwrap(config["filters"] as? [String: Any])
            XCTAssertEqual(filters["sort"] as? String, "title-desc")
            XCTAssertEqual(filters["future"] as? Int, 99)
            let properties = try XCTUnwrap(filters["properties"] as? [[String: Any]])
            XCTAssertEqual(properties[0]["valueKeys"] as? [String], ["string:Grace"])
            XCTAssertEqual(properties[0]["future"] as? Int, 42)
            XCTAssertEqual((properties[3]["date"] as? [String: Any])?["future"] as? String, "keep")
            XCTAssertEqual((raw["Other"] as? [String: Any])?["future"] as? String, "other")
            let reopened = MacWorkspace(); await reopened.openVault(root); await reopened.openCollection("Work", folder: true)
            XCTAssertEqual(reopened.collection.map(\.title), ["B"])
            XCTAssertEqual(reopened.filters.sort, .titleDescending)
        }
    }
    func testNamedViewsApplyOverwriteRenameAndRejectStaleDeletionWithoutChangingNotes() async throws {
        let saved = #"{"Work":[{"id":"desktop-preset","name":"Legacy","future":"record","config":{"mode":"gallery","visibleProperties":["Owner"],"future":"config","filters":{"sort":"title-asc","properties":[{"name":"Owner","valueKeys":["string:Ada"]}]}}}],"Other":{"future":"opaque"}}"#
        let active = #"{"Work":{"futureActive":"retained","mode":"list"}}"#
        let a = "---\nOwner: Ada\n---\n# A\n", b = "---\nOwner: Grace\n---\n# B\n"
        try await withVault(["Work/A.md": a, "Work/B.md": b, ".zerus/views.json": active, ".zerus/saved-views.json": saved]) { root, store in
            await store.openCollection("Work", folder: true)
            let initial = try XCTUnwrap(store.savedViews.first)
            await store.openNote("Work/A.md")
            await store.applySavedView(initial)
            XCTAssertTrue(store.browsingCollection, "Choosing a saved view reveals that collection")
            XCTAssertEqual(store.selection, "Work/A.md", "The open note remains available when returning from a special view")
            XCTAssertEqual(store.viewMode, "Gallery")
            XCTAssertEqual(store.collection.map(\.title), ["A"])
            // Another client adds preset-only metadata after it was applied.
            let presetLocation = root.appendingPathComponent(".zerus/saved-views.json")
            var presetObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: presetLocation)) as? [String: Any])
            var presetRecords = try XCTUnwrap(presetObject["Work"] as? [[String: Any]])
            var presetConfig = try XCTUnwrap(presetRecords[0]["config"] as? [String: Any])
            presetConfig["futurePresetOnly"] = "keep this too"; presetRecords[0]["config"] = presetConfig; presetObject["Work"] = presetRecords
            try JSONSerialization.data(withJSONObject: presetObject).write(to: presetLocation)
            var filters = store.filters; filters.properties[0].values = [.init(kind: .text, value: "Grace")]
            store.changeCollectionFilters(filters)
            await store.openNote("Work/A.md")
            await store.updateCollectionLayout(store.collectionLayout, mode: "Table")
            XCTAssertTrue(store.browsingCollection, "Choosing a layout reveals that collection")
            XCTAssertEqual(store.selection, "Work/A.md")
            let savedOK = await store.saveCurrentView(name: "LEGACY")
            XCTAssertTrue(savedOK); XCTAssertEqual(store.savedViews.count, 1)
            let updated = try XCTUnwrap(store.savedViews.first)
            XCTAssertEqual(updated.id, "desktop-preset")
            store.changeCollectionFilters(.init())
            await store.applySavedView(updated)
            XCTAssertEqual(store.viewMode, "Table"); XCTAssertEqual(store.collection.map(\.title), ["B"])
            let renamedOK = await store.changeSavedView(updated, name: "Grace view", owner: "Work", workspaceID: store.workspaceID)
            XCTAssertTrue(renamedOK)
            let renamed = try XCTUnwrap(store.savedViews.first)
            let location = root.appendingPathComponent(".zerus/saved-views.json")
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? [String: Any])
            var records = try XCTUnwrap(raw["Work"] as? [[String: Any]])
            XCTAssertEqual(records[0]["future"] as? String, "record")
            XCTAssertEqual((records[0]["config"] as? [String: Any])?["future"] as? String, "config")
            XCTAssertEqual((records[0]["config"] as? [String: Any])?["futurePresetOnly"] as? String, "keep this too")
            records[0]["name"] = "Outside edit"; raw["Work"] = records
            let external = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]); try external.write(to: location)
            let staleDelete = await store.changeSavedView(renamed, name: nil, owner: "Work", workspaceID: store.workspaceID)
            XCTAssertFalse(staleDelete); XCTAssertEqual(try Data(contentsOf: location), external)
            store.issue = nil; await store.refreshMetadata()
            let fresh = try XCTUnwrap(store.savedViews.first)
            let viewBytes = try Data(contentsOf: root.appendingPathComponent(".zerus/views.json"))
            let deleted = await store.changeSavedView(fresh, name: nil, owner: "Work", workspaceID: store.workspaceID)
            XCTAssertTrue(deleted); XCTAssertTrue(store.savedViews.isEmpty)
            let remaining = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? [String: Any])
            XCTAssertEqual((remaining["Other"] as? [String: Any])?["future"] as? String, "opaque")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/views.json")), viewBytes)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8), a)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/B.md"), encoding: .utf8), b)
        }
    }
    func testTaskFormsUseVaultIdentityAndQueuedWritesMergeWithCollectionChanges() async throws {
        let tasks = #"{"tasks":[{"id":"a","title":"Original","priority":"none","date":"2026-11-16","createdAt":"2026-11-01T12:00:00Z","foreign":{"keep":true}},"future record"],"lists":[],"categoryOptions":[],"foreignEnvelope":42}"#
        try await withVault(["Work/A.md": note("stable-a", title: "A"), ".zerus/tasks.json": tasks]) { root, store in
            let origin = store.workspaceID, baseline = try XCTUnwrap(store.tasks.first)
            XCTAssertEqual(baseline.workspaceID, origin)
            var title = baseline; title.title = "Title from one window"
            var priority = baseline; priority.priority = "high"
            async let first = store.saveTask(title)
            async let second = store.saveTask(priority)
            async let collection = store.changeTasks(.createList(id: "projects", name: "Projects"), workspaceID: origin)
            async let refresh: Void = store.refreshMetadata()
            let results = await [first, second, collection]; await refresh
            XCTAssertEqual(results, [true, true, true])
            XCTAssertEqual(store.tasks.first?.title, "Title from one window")
            XCTAssertEqual(store.tasks.first?.priority, "high")
            XCTAssertEqual(store.taskLists.first?.id, "projects")
            XCTAssertFalse(store.tasksSaving)
            let categoryOK = await store.changeTasks(.addCategory("Research"), workspaceID: origin)
            XCTAssertTrue(categoryOK); XCTAssertEqual(store.taskCategories, ["Research"])
            let note = try XCTUnwrap(store.notes.first)
            var linked = store.newTask(title: "Review supporting note", listID: "projects")
            linked.category = "Research"; linked.linkedNoteIDs = [MacTaskNotes.token(note, notes: store.notes)]
            let saved = await store.saveTask(linked); XCTAssertTrue(saved)
            let data = try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let records = try XCTUnwrap(object["tasks"] as? [Any])
            XCTAssertEqual(records[1] as? String, "future record")
            XCTAssertEqual(object["foreignEnvelope"] as? Int, 42)
            let linkedRaw = try XCTUnwrap(records.compactMap { $0 as? [String: Any] }.first { $0["id"] as? String == linked.id })
            XCTAssertEqual(linkedRaw["linkedNoteIds"] as? [String], ["stable-a"])
            XCTAssertEqual(linkedRaw["listId"] as? String, "projects")
            XCTAssertEqual(linkedRaw["category"] as? String, "Research")
            let unsaved = store.newTask(title: "Old unsaved form")
            await store.openVault(root)
            XCTAssertNotEqual(store.workspaceID, origin)
            let staleTask = await store.saveTask(unsaved)
            let staleList = await store.changeTasks(.createList(id: "stale", name: "Stale list"), workspaceID: origin)
            XCTAssertFalse(staleTask); XCTAssertFalse(staleList)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), data)
            XCTAssertEqual(store.tasks.count, 2)
        }
    }
    // Covers the Mac editor lifecycle; URL normalization/duplicate handling belongs to the shared vault engine.
    func testSavedLinkUpdateKeepsEditorInSyncAndRejectsOldVaultForms() async throws {
        let original = "---\nzerus-id: link-note\nzerus-link-id: saved-link\nzerus-link-url: https://example.com/\nforeign: retained\n---\n# Reference\n\n<https://example.com/>\n\nMy **annotations**.\n"
        try await withVault([".zerus/links/link.md": original, "Work/A.md": note("a", title: "A")]) { root, store in
            await store.openNote(".zerus/links/link.md")
            let baseline = try XCTUnwrap(store.current), origin = store.workspaceID
            try await store.updateLink(baseline, address: "https://example.org/reference", workspaceID: origin)
            XCTAssertEqual(store.current?.savedLink?.address, "https://example.org/reference")
            XCTAssertTrue(store.body.contains("My **annotations**."))
            XCTAssertTrue(store.current?.content.contains("foreign: retained") == true)
            XCTAssertTrue(store.body.contains("<https://example.org/reference>"))
            do {
                let host = NSHostingView(rootView: MacWorkspaceView(store: store))
                let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1400, height: 850), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
                defer { window.contentView = nil; window.close() }
                func settle() async throws { for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) } }
                func descendants(_ node: NSView) -> [NSView] { [node] + node.subviews.flatMap(descendants) }
                func editor() throws -> NSTextView { try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first { $0.isEditable && !$0.isFieldEditor }) }
                try await settle()
                let text = try editor()
                XCTAssertFalse(text.string.contains("https://example.org/reference"), "The managed URL belongs in its URL bar, not the editable note")
                XCTAssertTrue(text.string.contains("My annotations."))
                text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
                text.insertText("Added annotation.", replacementRange: text.selectedRange()); text.breakUndoCoalescing()
                try await settle()
                let success = await store.save(); XCTAssertTrue(success)
                let written = try String(contentsOf: root.appendingPathComponent(baseline.path), encoding: .utf8)
                XCTAssertEqual(written.components(separatedBy: "<https://example.org/reference>").count - 1, 1, "Editing keeps exactly one managed URL on disk")
                XCTAssertTrue(written.contains("Added annotation.")); XCTAssertTrue(written.contains("foreign: retained"))
                text.undoManager?.undo(); try await settle()
                let undoSaved = await store.save(); XCTAssertTrue(undoSaved)
                XCTAssertFalse(store.body.contains("Added annotation."))
                XCTAssertTrue(store.body.contains("<https://example.org/reference>"))
                store.sourceMode = true; try await settle()
                XCTAssertFalse(try editor().string.contains("https://example.org/reference"), "Source edits use the same managed-URL boundary")
                XCTAssertTrue(try editor().string.contains("My **annotations**."))
                store.sourceMode = false
            }
            let saved = try Data(contentsOf: root.appendingPathComponent(baseline.path))
            XCTAssertEqual(String(data: saved, encoding: .utf8), store.current?.content)
            await store.openVault(root)
            do { try await store.updateLink(baseline, address: "https://stale.example/", workspaceID: origin); XCTFail("A form from the previous vault activation must fail") } catch {}
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(baseline.path)), saved)
            await store.openNote(baseline.path)
            let fresh = try XCTUnwrap(store.current)
            store.changed(store.body + "\nNew unsaved annotation.\n")
            do { try await store.updateLink(fresh, address: "https://stale.example/", workspaceID: store.workspaceID); XCTFail("Changed editor content must require reopening the URL form") } catch {}
            XCTAssertTrue(store.body.contains("New unsaved annotation."))
            XCTAssertEqual(store.current?.savedLink?.address, "https://example.org/reference")
        }
    }
    func testFileHubStorageModesKeepSourcesAndNotesWhileSupportingDetachAndStaleReviews() async throws {
        for storage in NativeFileStorage.allCases {
            let ordinary = note("a", title: "A")
            try await withVault(["Work/A.md": ordinary]) { root, store in
                let source = root.deletingLastPathComponent().appendingPathComponent("Zerus-source-" + UUID().uuidString + ".txt")
                let bytes = Data("Original document bytes".utf8); try bytes.write(to: source)
                let mappings = try XCTUnwrap(store.fileMappings), mappingFile = await mappings.file
                defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: mappingFile.deletingLastPathComponent()) }
                let request = try await store.prepareFileHub()
                let saved = try await store.saveFileHub(request, source: NativeFileLease(scope: source), storage: storage, title: "Document", folder: "Work")
                let hub = try XCTUnwrap(saved.fileHub)
                XCTAssertEqual(try Data(contentsOf: source), bytes)
                await store.openCollection("Files")
                XCTAssertEqual(store.collection.map(\.path), [saved.path], "Filed document notes belong in the Files collection")
                XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Work/A.md"), encoding: .utf8), ordinary)
                let resolved = try await store.resolveFileHub(saved, workspaceID: store.workspaceID)
                let preview = MacFileHubPreview(), origin = store.workspaceID
                await preview.refresh(saved, workspace: store, workspaceID: origin)
                let firstPreview = try XCTUnwrap(preview.lease)
                XCTAssertEqual(firstPreview.canonicalPath, resolved.canonicalPath)
                XCTAssertEqual(firstPreview.size, Int64(bytes.count)); XCTAssertNil(preview.issue)
                await preview.refresh(saved, workspace: store, workspaceID: origin)
                XCTAssertTrue(preview.lease === firstPreview, "Unchanged status must preserve the document view's page/search identity")
                let changedBytes = Data(repeating: 88, count: bytes.count), changedAt = Date().addingTimeInterval(10)
                try changedBytes.write(to: resolved.url)
                try FileManager.default.setAttributes([.modificationDate: changedAt], ofItemAtPath: resolved.url.path)
                await preview.refresh(saved, workspace: store, workspaceID: origin)
                let changedPreview = try XCTUnwrap(preview.lease)
                XCTAssertFalse(changedPreview === firstPreview, "Same-size outside edits still refresh when their modification date changes")
                XCTAssertEqual(try Data(contentsOf: changedPreview.url), changedBytes)
                XCTAssertEqual(changedPreview.size, firstPreview.size)
                await preview.refresh(saved, workspace: store, workspaceID: origin, force: true)
                XCTAssertFalse(preview.lease === changedPreview, "Explicit reload must refresh even an unchanged document")
                try FileManager.default.removeItem(at: resolved.url)
                await preview.refresh(saved, workspace: store, workspaceID: origin)
                XCTAssertNil(preview.lease); XCTAssertNotNil(preview.issue, "Unavailable files must disable original-file actions")
                try bytes.write(to: resolved.url)
                if storage != .copy { try await store.locateFileHub(saved, source: NativeFileLease(scope: resolved.url), workspaceID: origin) }
                await preview.refresh(saved, workspace: store, workspaceID: origin)
                XCTAssertNotNil(preview.lease); XCTAssertNil(preview.issue)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(saved.path)), Data(saved.content.utf8), "Status and preview refreshes must leave the Markdown note unchanged")
                if storage == .copy {
                    XCTAssertEqual(hub.kind, .vault); XCTAssertTrue(hub.managed)
                    XCTAssertEqual(try Data(contentsOf: resolved.url), bytes)
                    XCTAssertNotEqual(resolved.canonicalPath, source.path)
                } else {
                    XCTAssertEqual(hub.kind, .local); XCTAssertEqual(resolved.canonicalPath, source.path)
                    let duplicateRequest = try await store.prepareFileHub()
                    let duplicate = try await store.saveFileHub(duplicateRequest, source: NativeFileLease(scope: source), storage: storage, title: "Duplicate", folder: "Work")
                    XCTAssertEqual(duplicate.path, saved.path)
                }
                if storage == .backup {
                    let backup = try XCTUnwrap(NativeFileAttachment.all(in: saved.content).first)
                    try Data("New original version".utf8).write(to: source)
                    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(backup.path)), bytes)
                }
                let detach = try await store.prepareFileHub(saved)
                let detached = try await store.saveFileHub(detach, source: nil, storage: .copy, title: saved.title, folder: saved.folder, detach: true)
                XCTAssertNil(detached.fileHub); XCTAssertEqual(detached.parts.body, saved.parts.body)
                await preview.refresh(saved, workspace: store, workspaceID: origin)
                XCTAssertNil(preview.lease); XCTAssertTrue(preview.issue?.contains("connection or vault changed") == true)
                preview.cancel(); XCTAssertNil(preview.lease); XCTAssertFalse(preview.refreshing)
                XCTAssertEqual(NativeFileAttachment.all(in: detached.content).count, storage == .backup ? 1 : 0)
                let oldReview = try await store.prepareFileHub(detached), before = try Data(contentsOf: root.appendingPathComponent(detached.path))
                await store.openVault(root)
                do { _ = try await store.saveFileHub(oldReview, source: NativeFileLease(scope: source), storage: .copy, title: "Stale", folder: "Work"); XCTFail("A review from an earlier vault activation must fail") } catch {}
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(detached.path)), before)
            }
        }
    }
    func testConnectedPreviewKeepsTheNewVaultActivationWhenAnOldRefreshArrives() async throws {
        let content = "---\nzerus-id: doc\nzerus-file-id: ref\nzerus-file-name: source.txt\nzerus-file-kind: vault\nzerus-file-path: assets/source.txt\n---\n# Document\n"
        try await withVault(["Doc.md": content, "assets/source.txt": "Source document"]) { root, store in
            let origin = store.workspaceID, oldNote = try XCTUnwrap(store.notes.first), preview = MacFileHubPreview()
            await preview.refresh(oldNote, workspace: store, workspaceID: origin)
            let first = try XCTUnwrap(preview.lease)
            await store.openVault(root)
            let currentNote = try XCTUnwrap(store.notes.first)
            await preview.refresh(currentNote, workspace: store, workspaceID: store.workspaceID)
            let current = try XCTUnwrap(preview.lease)
            XCTAssertFalse(current === first)
            await preview.refresh(oldNote, workspace: store, workspaceID: origin)
            XCTAssertTrue(preview.lease === current, "A stale request must not clear the current activation's preview")
            XCTAssertNil(preview.issue)
            let canceled = Task { await preview.refresh(currentNote, workspace: store, workspaceID: store.workspaceID, force: true) }
            canceled.cancel(); await canceled.value
            XCTAssertTrue(preview.lease === current, "A canceled refresh must not replace the visible document")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Doc.md")), Data(content.utf8))
        }
    }
    func testFiledSavedLinkRemainsInTheGlobalLinksCollection() async throws {
        let content = "---\nzerus-id: filed-link\nzerus-link-id: saved-address\nzerus-link-url: https://example.com/\n---\n# Filed reference\n"
        try await withVault(["Work/Reference.md": content]) { _, store in
            await store.openCollection("Links")
            XCTAssertEqual(store.collection.map(\.path), ["Work/Reference.md"])
        }
    }
    func testLocationMappingsKeepSharedBytesAndExplicitFileOverridesWhileRenamingPreservesForeignRecords() async throws {
        let locations = #"{"version":1,"foreignEnvelope":42,"locations":[{"id":"contracts","name":"Contracts","foreignField":7},"future record"]}"#
        let document = "---\nzerus-id: document\nzerus-file-id: reference\nzerus-file-name: contract.txt\nzerus-file-kind: location\nzerus-file-location: contracts\nzerus-file-path: contract.txt\n---\n# Contract\n\nAnnotations stay.\n"
        try await withVault(["Work/Contract.md": document, ".zerus/file-locations.json": locations]) { root, store in
            let external = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-location-folders-" + UUID().uuidString)
            let alpha = external.appendingPathComponent("Alpha"), beta = external.appendingPathComponent("Beta"), override = external.appendingPathComponent("Override.txt")
            try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
            try Data("Alpha version".utf8).write(to: alpha.appendingPathComponent("contract.txt")); try Data("Beta version!".utf8).write(to: beta.appendingPathComponent("contract.txt")); try Data("Explicit override".utf8).write(to: override)
            for folder in [alpha, beta] { try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: folder.appendingPathComponent("contract.txt").path) }
            let mappings = try XCTUnwrap(store.fileMappings), mappingFile = await mappings.file
            defer { try? FileManager.default.removeItem(at: external); try? FileManager.default.removeItem(at: mappingFile.deletingLastPathComponent()) }
            let origin = store.workspaceID, snapshot = try await store.fileLocationsSnapshot(workspaceID: store.workspaceID)
            let location = try XCTUnwrap(snapshot.definitions.locations.first), note = try XCTUnwrap(store.notes.first)
            XCTAssertEqual(snapshot.usages[location.id], 1); XCTAssertNil(snapshot.labels[location.id]); XCTAssertNotNil(snapshot.definitions.warning)
            try await store.mapFileLocation(location, folder: alpha, workspaceID: origin)
            let first = try await store.resolveFileHub(note, workspaceID: origin)
            XCTAssertEqual(try String(contentsOf: first.url, encoding: .utf8), "Alpha version")
            let preview = MacFileHubPreview()
            await preview.refresh(note, workspace: store, workspaceID: origin)
            let alphaPreview = try XCTUnwrap(preview.lease)
            try await store.mapFileLocation(location, folder: beta, workspaceID: origin)
            await preview.refresh(note, workspace: store, workspaceID: origin)
            let betaPreview = try XCTUnwrap(preview.lease)
            XCTAssertEqual(betaPreview.size, alphaPreview.size); XCTAssertEqual(betaPreview.modified, alphaPreview.modified)
            XCTAssertNotEqual(betaPreview.canonicalPath, alphaPreview.canonicalPath)
            XCTAssertEqual(try String(contentsOf: betaPreview.url, encoding: .utf8), "Beta version!", "Remapping must follow the new folder even when size and date match")
            try await store.mapFileLocation(location, folder: alpha, workspaceID: origin)
            try await store.locateFileHub(note, source: NativeFileLease(scope: override), workspaceID: origin)
            try await store.mapFileLocation(location, folder: beta, workspaceID: origin)
            let overridden = try await store.resolveFileHub(note, workspaceID: origin)
            XCTAssertTrue(overridden.locatedOnDevice); XCTAssertEqual(try String(contentsOf: overridden.url, encoding: .utf8), "Explicit override")
            await preview.refresh(note, workspace: store, workspaceID: origin)
            XCTAssertEqual(preview.lease?.canonicalPath, overridden.canonicalPath); XCTAssertEqual(preview.lease?.locatedOnDevice, true)
            try await store.useFolderMapping(note, workspaceID: origin)
            let remapped = try await store.resolveFileHub(note, workspaceID: origin)
            XCTAssertFalse(remapped.locatedOnDevice); XCTAssertEqual(try String(contentsOf: remapped.url, encoding: .utf8), "Beta version!")
            await preview.refresh(note, workspace: store, workspaceID: origin)
            XCTAssertEqual(preview.lease?.canonicalPath, remapped.canonicalPath); XCTAssertEqual(preview.lease?.locatedOnDevice, false)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(".zerus/file-locations.json"), encoding: .utf8), locations)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(note.path), encoding: .utf8), document)
            try await store.changeFileLocation(.rename(location, name: "Reference documents"), workspaceID: origin)
            let changed = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/file-locations.json"))) as! [String: Any]
            XCTAssertEqual(changed["foreignEnvelope"] as? Int, 42)
            let rows = try XCTUnwrap(changed["locations"] as? [Any]); XCTAssertEqual(rows.last as? String, "future record")
            XCTAssertEqual((rows.first as? [String: Any])?["foreignField"] as? Int, 7)
            do { try await store.mapFileLocation(location, folder: alpha, workspaceID: origin); XCTFail("A renamed location invalidates an old folder review") } catch { XCTAssertTrue(error.localizedDescription.contains("changed")) }
            let renamedSnapshot = try await store.fileLocationsSnapshot(workspaceID: origin)
            let renamed = try XCTUnwrap(renamedSnapshot.definitions.locations.first)
            await store.trash(note)
            let deletedReference = try await store.fileLocationsSnapshot(workspaceID: origin)
            XCTAssertEqual(deletedReference.usages[renamed.id], 1, "Trash references still block location removal")
            do { try await store.changeFileLocation(.remove(renamed), workspaceID: origin); XCTFail("Used locations cannot be removed") } catch { XCTAssertTrue(error.localizedDescription.contains("still use")) }
            try await store.mapFileLocation(renamed, folder: nil, workspaceID: origin)
            let disconnected = try await store.fileLocationsSnapshot(workspaceID: origin)
            XCTAssertNil(disconnected.labels[renamed.id])
            XCTAssertEqual(try String(contentsOf: alpha.appendingPathComponent("contract.txt"), encoding: .utf8), "Alpha version")
            XCTAssertEqual(try String(contentsOf: beta.appendingPathComponent("contract.txt"), encoding: .utf8), "Beta version!")
        }
    }
    func testCopiedVaultDoesNotInheritLocationMappingAndRejectsThePreviousVaultReview() async throws {
        let definitions = #"{"version":1,"locations":[{"id":"same-id","name":"Same name"}]}"#
        let content = "---\nzerus-id: doc\nzerus-file-id: ref\nzerus-file-name: source.txt\nzerus-file-kind: location\nzerus-file-location: same-id\nzerus-file-path: source.txt\n---\n# Document\n"
        try await withVault(["Doc.md": content, ".zerus/file-locations.json": definitions]) { root, store in
            let source = root.deletingLastPathComponent().appendingPathComponent("Zerus-mapped-" + UUID().uuidString), clone = root.deletingLastPathComponent().appendingPathComponent("Zerus-clone-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true); try Data("Original".utf8).write(to: source.appendingPathComponent("source.txt"))
            try FileManager.default.copyItem(at: root, to: clone)
            let firstMappings = try XCTUnwrap(store.fileMappings), firstFile = await firstMappings.file
            defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: clone); try? FileManager.default.removeItem(at: firstFile.deletingLastPathComponent()); UserDefaults.standard.removeObject(forKey: MacNavigationState.key(clone)); UserDefaults.standard.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(clone.path)) }
            let old = try await store.fileLocationsSnapshot(workspaceID: store.workspaceID), location = try XCTUnwrap(old.definitions.locations.first)
            try await store.mapFileLocation(location, folder: source, workspaceID: old.workspaceID)
            let before = try Data(contentsOf: firstFile)
            await store.openVault(clone)
            let current = try await store.fileLocationsSnapshot(workspaceID: store.workspaceID)
            XCTAssertNil(current.labels[location.id])
            do { _ = try await store.resolveFileHub(try XCTUnwrap(store.notes.first), workspaceID: store.workspaceID); XCTFail("A copied vault must choose its own folder") } catch { XCTAssertTrue(error.localizedDescription.contains("Map this file")) }
            do { try await store.mapFileLocation(location, folder: source, workspaceID: old.workspaceID); XCTFail("The previous vault's review must not write") } catch { XCTAssertTrue(error.localizedDescription.contains("vault changed")) }
            XCTAssertEqual(try Data(contentsOf: firstFile), before)
            let secondMappings = try XCTUnwrap(store.fileMappings), secondFile = await secondMappings.file
            XCTAssertFalse(FileManager.default.fileExists(atPath: secondFile.path))
            XCTAssertEqual(try String(contentsOf: clone.appendingPathComponent("Doc.md"), encoding: .utf8), content)
        }
    }
    func testTaskDraftSurvivesWorkspaceRestartAndConflictRecoveryWithoutChangingVaultUntilCommit() async throws {
        try await withVault(["Inbox/A.md": note("a", title: "A"), ".zerus/tasks.json": "{\"tasks\":[],\"lists\":[],\"categoryOptions\":[]}"]) { root, first in
            let file = root.appendingPathComponent(".zerus/tasks.json"), before = try Data(contentsOf: file)
            let editing = try first.taskDraftSession(first.newTask())
            editing.task.title = "Retained research"; editing.task.priority = "high"; editing.task.linkedNoteIDs = ["a"]
            XCTAssertNil(editing.issue)
            XCTAssertEqual(try Data(contentsOf: file), before)
            let privateStore = try XCTUnwrap(first.taskDraftStore), record = try XCTUnwrap(privateStore.records.first)
            let closed = await first.prepareToCloseWindow(); XCTAssertTrue(closed)
            // Compatibility input from earlier Mac builds: a path-only owner.
            let descriptorURL = privateStore.directory.appendingPathComponent("vault.json")
            var legacy = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: descriptorURL)) as? [String: Any])
            legacy["vaultIDs"] = [String]()
            try JSONSerialization.data(withJSONObject: legacy).write(to: descriptorURL, options: .atomic)
            do {
                let adopting = MacWorkspace(); await adopting.openVault(root)
                XCTAssertEqual(adopting.taskDraftStore?.directory, privateStore.directory)
                XCTAssertEqual(adopting.taskDraftStore?.latest(for: record.task.id)?.task.title, "Retained research")
                let descriptor = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: descriptorURL)) as? [String: Any])
                XCTAssertEqual((descriptor["vaultIDs"] as? [String])?.count, 1, "Opening the original folder binds a legacy draft before it moves")
                let closed = await adopting.prepareToCloseWindow(); XCTAssertTrue(closed)
            }
            let moved = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-moved")
            defer {
                if FileManager.default.fileExists(atPath: moved.path) {
                    if FileManager.default.fileExists(atPath: root.path) { try? FileManager.default.removeItem(at: root) }
                    try? FileManager.default.moveItem(at: moved, to: root)
                }
                UserDefaults.standard.removeObject(forKey: MacNavigationState.key(moved))
                UserDefaults.standard.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(moved.path))
            }
            try FileManager.default.moveItem(at: root, to: moved)
            do {
                let relocated = MacWorkspace(); await relocated.openVault(moved)
                let relocatedStore = try XCTUnwrap(relocated.taskDraftStore)
                XCTAssertEqual(relocatedStore.directory, privateStore.directory, "A folder rename must retain this Mac's task drafts")
                XCTAssertEqual(relocatedStore.latest(for: record.task.id)?.task.title, "Retained research")
                XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent(".zerus/tasks.json")), before)
                let closed = await relocated.prepareToCloseWindow(); XCTAssertTrue(closed)
                await MacStartupCache.shared.invalidate(moved)
                if relocatedStore.directory != privateStore.directory { try FileManager.default.removeItem(at: relocatedStore.directory) }
            }
            // A separate copy at the old path must not inherit private work.
            try FileManager.default.copyItem(at: moved, to: root)
            do {
                let replacement = MacWorkspace(); await replacement.openVault(root)
                let replacementStore = try XCTUnwrap(replacement.taskDraftStore)
                XCTAssertNotEqual(replacementStore.directory, privateStore.directory)
                XCTAssertTrue(replacementStore.records.isEmpty, "A different folder at the old path has no right to these private drafts")
                let closed = await replacement.prepareToCloseWindow(); XCTAssertTrue(closed)
                if replacementStore.directory != privateStore.directory { try FileManager.default.removeItem(at: replacementStore.directory) }
                await MacStartupCache.shared.invalidate(root)
            }
            try FileManager.default.removeItem(at: root)
            try FileManager.default.moveItem(at: moved, to: root)
            let restarted = MacWorkspace(); await restarted.openVault(root)
            let draftStore = try XCTUnwrap(restarted.taskDraftStore)
            XCTAssertEqual(draftStore.directory, privateStore.directory)
            var task = record.task; task.workspaceID = restarted.workspaceID
            let recovery = try restarted.taskDraftSession(task)
            XCTAssertTrue(recovery.recovered); XCTAssertEqual(recovery.task.title, "Retained research"); XCTAssertEqual(recovery.task.priority, "high"); XCTAssertEqual(recovery.task.linkedNoteIDs, ["a"])
            let saved = await restarted.commitTaskDraft(recovery)
            XCTAssertTrue(saved); XCTAssertTrue(draftStore.records.isEmpty)
            let canonical = try XCTUnwrap(restarted.tasks.first)
            let local = try restarted.taskDraftSession(canonical); local.task.title = "Local draft"
            let outside = VaultFiles(root: root); var external = canonical; external.title = "Outside title"
            _ = try await outside.changeTasks(.save(external, delete: false))
            let outsideBytes = try Data(contentsOf: file)
            let conflicted = await restarted.commitTaskDraft(local); XCTAssertFalse(conflicted)
            XCTAssertEqual(try Data(contentsOf: file), outsideBytes)
            XCTAssertEqual(draftStore.latest(for: canonical.id)?.task.title, "Local draft")
            let copied = await restarted.commitTaskDraft(local, copy: true); XCTAssertTrue(copied)
            XCTAssertTrue(draftStore.records.isEmpty)
            XCTAssertEqual(restarted.tasks.count, 2)
            XCTAssertEqual(restarted.tasks.first { $0.id == canonical.id }?.title, "Outside title")
            let copy = try XCTUnwrap(restarted.tasks.first { $0.id != canonical.id })
            XCTAssertEqual(copy.title, "Local draft")
            let deleting = try restarted.taskDraftSession(copy); deleting.task.title = "Unsaved before delete"
            let removed = await restarted.commitTaskDraft(deleting, delete: true); XCTAssertTrue(removed); deleting.keep()
            XCTAssertTrue(draftStore.records.isEmpty, "Closing after deletion must not recreate the task draft")
            for copyDuringSave in [false, true] {
                let label = copyDuringSave ? "copy" : "save", count = restarted.tasks.count
                let racing = try restarted.taskDraftSession(restarted.newTask(title: "Snapshot " + label))
                racing.task.priority = "high"
                var delivered = false
                // Observe the real save boundary after its task snapshot was
                // captured, before the file actor completes the transaction.
                let observer = restarted.tasksSavingPublisher.filter { $0 }.first().sink { _ in
                    racing.task.title = "Newer during " + label
                    delivered = true
                }
                let finished = await restarted.commitTaskDraft(racing, copy: copyDuringSave)
                withExtendedLifetime(observer) {}
                XCTAssertTrue(delivered)
                XCTAssertFalse(finished, "The form must remain open for an edit delivered while saving")
                XCTAssertTrue(restarted.issue?.contains("Newer task changes remain open") == true)
                let written = try XCTUnwrap(restarted.tasks.first { $0.title == "Snapshot " + label })
                XCTAssertEqual(written.priority, "high")
                XCTAssertEqual(racing.task.title, "Newer during " + label)
                XCTAssertEqual(draftStore.latest(for: racing.task.id)?.task.title, "Newer during " + label, "A completed earlier snapshot must not remove newer private text")
                let retry = await restarted.commitTaskDraft(racing)
                XCTAssertTrue(retry)
                XCTAssertEqual(restarted.tasks.count, count + 1, "Retry must update the saved task or copy, without creating another record")
                XCTAssertEqual(restarted.tasks.first { $0.id == written.id }?.title, "Newer during " + label)
                XCTAssertTrue(draftStore.records.isEmpty)
            }
        }
    }
    private func note(_ id: String, title: String, body: String = "Body.\n") -> String { "---\nzerus-id: \(id)\n---\n# \(title)\n\n" + body }
    private func withVault(_ files: [String: String], operation: (URL, MacWorkspace) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-Mac-tests-" + UUID().uuidString)
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            defaults.removeObject(forKey: MacNavigationState.key(root))
            defaults.removeObject(forKey: MacNewNotePreferences.key(root))
            defaults.removeObject(forKey: MacFolderOrdering.key(root))
            defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
            try? FileManager.default.removeItem(at: root)
        }
        for (path, text) in files { let url = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(text.utf8).write(to: url) }
        let store = MacWorkspace(); await store.openVault(root)
        XCTAssertNil(store.issue)
        let draftDirectory = store.taskDraftStore?.directory
        defer { if let draftDirectory { try? FileManager.default.removeItem(at: draftDirectory) } }
        let outcome: Result<Void, Error>
        do { try await operation(root, store); outcome = .success(()) }
        catch { outcome = .failure(error) }
        // Warm reopen fixtures may still reconcile their disposable startup
        // snapshots. Settle every peer before removing this vault's preferences,
        // otherwise a late navigation write can recreate an already-cleaned key.
        let owned = root.resolvingSymlinksInPath().standardizedFileURL
        let peers = MacWorkspace.windows.compactMap(\.value).filter { $0.root?.resolvingSymlinksInPath().standardizedFileURL == owned }
        for peer in peers {
            _ = await peer.prepareToCloseWindow()
            if let directory = peer.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
        }
        await MacStartupCache.shared.invalidate(root)
        try outcome.get()
    }
}
