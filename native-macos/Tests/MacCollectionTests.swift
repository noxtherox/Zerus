import XCTest
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import AppKit
import Vision
@testable import Zerus_Native

final class MacCollectionTests: XCTestCase {
    func testSavedViewConditionsRoundTripAndLeaveOlderClientsAPresenceFilter() throws {
        var filters = NativeCollectionFilters()
        filters.properties = [
            .init(name: "ADO ID", condition: .empty), .init(name: "Done", condition: .unchecked),
            .init(name: "Points", condition: .number, numberComparison: .between, number: "2", endNumber: "8"),
            .init(name: "Due", condition: .relativeDate, relativeDate: .overdue)
        ]
        XCTAssertTrue(MacSharedFilters.canPersist(filters))
        let raw = MacSharedFilters.patch(filters, into: ["properties": [["name": "Due", "date": ["operator": "on", "date": "2026-11-01"], "futureKey": 1]]])
        let json = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: raw))
        let properties = try XCTUnwrap((json as? [String: Any])?["properties"] as? [[String: Any]])
        XCTAssertTrue(properties.allSatisfy { $0["valueKeys"] is NSNull && $0["date"] == nil }, "Older clients must read conditions as a presence filter")
        XCTAssertEqual(properties.last?["futureKey"] as? Int, 1)
        XCTAssertEqual((properties[2]["condition"] as? [String: Any])?["endValue"] as? Double, 8)
        let decoded = MacSharedFilters.decode(json).properties
        XCTAssertEqual(decoded.map(\.condition), [.empty, .unchecked, .number, .relativeDate])
        XCTAssertEqual(decoded[2].numberComparison, .between); XCTAssertEqual(decoded[2].number, "2"); XCTAssertEqual(decoded[2].endNumber, "8")
        XCTAssertEqual(decoded[3].relativeDate, .overdue)
        filters.properties = [.init(name: "Points", condition: .number, number: "")]
        XCTAssertFalse(MacSharedFilters.canPersist(filters))
        let state = MacCollectionState(filters: .init(properties: [.init(name: "Due", condition: .relativeDate, relativeDate: .next7)]))
        let restored = try JSONDecoder().decode(MacCollectionState.self, from: JSONEncoder().encode(state)).filters.properties.first
        XCTAssertEqual(restored?.condition, .relativeDate); XCTAssertEqual(restored?.relativeDate, .next7)
    }
    func testCollectionSnippetsKeepWordsSeparateAcrossHTMLBreaksWithoutChangingFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-snippet-breaks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let examples = [
            ("First<br>Second", "First Second"),
            ("First<BR/>Second", "First Second"),
            ("First<br />Second", "First Second"),
            ("First<br class=\"soft\">Second", "First Second"),
            ("First<br><br>Second", "First Second"),
            ("First **bold**<br>*Second*", "First bold Second"),
            ("[First<br>Second](https://example.com/private)", "First Second"),
            ("First<strong>bold</strong>Second", "FirstboldSecond"),
            ("`First<br>Second`", "First<br>Second"),
            ("```html\nFirst<br>Second\n```", "First<br>Second")
        ]
        let io = try VaultFiles(root: root)
        for (index, example) in examples.enumerated() {
            let path = "Case-\(index).md", bytes = Data(("\u{feff}---\r\nforeign: keep\r\n---\r\n# Preview\r\n\r\n" + example.0.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n").utf8)
            try await io.write(path, data: bytes, expected: nil)
            let snapshot = try await io.scan()
            let note = try XCTUnwrap(snapshot.notes.first { $0.path == path })
            XCTAssertEqual(note.snippet, example.1, example.0)
            XCTAssertEqual(note.snippet, example.1, "The cached excerpt must retain the same separation")
            let actual = try await io.read(path); XCTAssertEqual(actual, bytes, "Preview extraction must never rewrite note bytes")
        }
    }
    func testReservedFlagScalarsControlPinnedAndArchiveMembershipWithoutChangingUserProperties() {
        for (raw, enabled) in [("true", true), ("TRUE", true), ("\"true\"", true), ("'TRUE'", true),
                               ("false", false), ("\"FALSE\"", false), ("", false), ("\" true \"", false),
                               ("1", false), ("[true]", false)] {
            let content = "\u{feff}---\r\nZeRuS-Id: 28500000-0000-4000-8000-000000000001\r\nZerus-Pinned: " + raw + "\r\nZERUS-ARCHIVED: " + raw + "\r\nStatus: \"true\"\r\n---\r\n# Synthetic\r\n"
            let note = NoteDocument(path: "Work/Flag.md", content: content, modified: .distantPast)
            var filters = NativeCollectionFilters(); filters.includeArchived = true
            func paths(_ destination: String) -> [String] { MacNoteCollection.filter([note], destination: destination, filters: filters, query: "").map(\.path) }
            XCTAssertEqual(paths("Pinned"), enabled ? [note.path] : [], raw)
            XCTAssertEqual(paths("Archive"), enabled ? [note.path] : [], raw)
            XCTAssertEqual(note.stableID, "28500000-0000-4000-8000-000000000001")
            XCTAssertEqual(NativeFrontmatter(note.content).entry("Status")?.value, .text("true"), "Reserved flag compatibility must not coerce user properties")
        }
    }

    func testGalleryRelationsProduceDistinctObservedGroupsInCollectionOrder() {
        func note(_ id: String, _ value: String?) -> NoteDocument {
            .init(path: id + ".md", content: "---\nzerus-id: " + id + "\n" + (value.map { "Related: " + $0 + "\n" } ?? "") + "---\n# " + id + "\n", modified: .distantPast)
        }
        let notes = [note("empty", "[]"), note("multiple", "[beta, alpha, beta]"), note("single", "alpha"), note("literal", "'No value'"), note("absent", nil)]
        let groups = MacCollectionValues.galleryGroups(notes: notes, name: "Related")
        XCTAssertEqual(groups.map(\.value), [nil, "beta", "alpha", "No value"])
        XCTAssertEqual(groups.map { $0.notes.map(\.path) }, [["empty.md", "absent.md"], ["multiple.md"], ["multiple.md", "single.md"], ["literal.md"]])
        XCTAssertEqual(Set(groups.map(\.id)).count, 4, "An absent relation is distinct from a literal No value")
        XCTAssertEqual(MacCollectionValues.galleryGroups(notes: [], name: "Related").count, 0)
        let typed = MacCollectionValues.galleryGroups(notes: [note("checked", "true"), note("text", "'true'"), note("unchecked", "false")], name: "Related")
        XCTAssertEqual(typed.map(\.checkbox), [true, nil, false])
        XCTAssertEqual(Set(typed.map(\.id)).count, 3, "Literal text must not be presented as a checkbox state")
        let target = NoteDocument(path: "Folder/A.md", content: "---\nzerus-id: beta\n---\n# Note A\n", modified: .distantPast)
        let aliases = note("aliases", "[zerus:beta, 'Note A', 'note a', 'Folder/A', 'zerus:beta|Alias', missing-one, missing-two]")
        let resolved = MacCollectionValues.galleryGroups(notes: [aliases], name: "Related", relationNotes: [target, aliases])
        XCTAssertEqual(resolved.count, 3)
        XCTAssertEqual(resolved[0].relationPath, "Folder/A.md")
        XCTAssertEqual(resolved[0].notes.map(\.path), ["aliases.md"], "Aliases of one target must not duplicate its card")
        XCTAssertEqual(resolved.suffix(2).map(\.value), ["missing-one", "missing-two"])
    }

    @MainActor func testCalendarRendersSelectedPropertiesForDatedAndUndatedNotes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-calendar-" + UUID().uuidString)
        for folder in ["Work", ".zerus"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true) }
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        defer {
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            defaults.removeObject(forKey: MacNavigationState.key(root))
            defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
            try? FileManager.default.removeItem(at: root)
        }
        let day = MacCollectionValues.wireDate(Calendar.current.date(byAdding: .day, value: 14, to: Calendar.current.dateInterval(of: .month, for: Date())!.start)!)
        let sources = ["Work/A.md": "---\nDue: \(day)\nOwner: Ada\nPriority: [High, Low]\nScore: 3\n---\n# Meeting A\n", "Work/B.md": "---\nDue: \(day)\nOwner: Ben\nPriority: Low\nScore: 4\n---\n# Meeting B\n", "Work/C.md": "---\nOwner: Grace\nPriority: High\nScore: 7\n---\n# Undated C\n"]
        for (path, text) in sources { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        try Data(#"{"Work":{"mode":"calendar","dateProperty":"Due","visibleProperties":["Owner","Priority","Score"]}}"#.utf8).write(to: root.appendingPathComponent(".zerus/views.json"))
        let store = MacWorkspace(); await store.openVault(root); await store.openCollection("Work", folder: true)
        defer { if let directory = store.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) } }
        XCTAssertEqual(store.viewMode, "Calendar")
        let host = NSHostingView(rootView: MacCollectionViews(store: store, noteMenu: { _ in AnyView(EmptyView()) }).background(Color.white).environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1250, height: 1100), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        // Read the real rendered pixels: this catches missing fields and clipping,
        // including the second dated card in a cell, without a view-only API.
        var observations: [VNRecognizedTextObservation] = []
        func renderedText() throws -> [String] {
            for _ in 0..<10 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.cgImage)
            let attachment = XCTAttachment(image: NSImage(cgImage: image, size: .zero)); attachment.name = "Native calendar selected properties"; attachment.lifetime = .keepAlways; add(attachment)
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            observations = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first.map { $0.string.applyingTransform(.toLatin, reverse: false) ?? $0.string } }
        }
        let shown = try renderedText().joined(separator: "\n")
        for text in ["Meeting A", "Owner: Ada", "Score: 3", "Meeting B", "Owner: Ben", "Priority: Low", "Score: 4", "Undated C", "Owner: Grace", "Score: 7"] {
            XCTAssertTrue(shown.contains(text), "Calendar must visibly render \(text). Recognized: \(shown)")
        }
        // Exercise the AppKit -> SwiftUI modifier transport on this owned
        // offscreen window; direct model calls cannot catch lost event flags.
        func click(_ label: String, modifiers: NSEvent.ModifierFlags = [], middle: Bool = false, count: Int = 1) async throws {
            // OCR can read bold Latin capitals as Cyrillic homoglyphs or add a
            // trailing stray glyph; fold to Latin and match the label inside.
            let box = try XCTUnwrap(observations.first { $0.topCandidates(1).first.map { ($0.string.applyingTransform(.toLatin, reverse: false) ?? $0.string).contains(label) } == true }?.boundingBox)
            let point = host.convert(NSPoint(x: box.midX * host.bounds.width, y: (host.isFlipped ? 1 - box.midY : box.midY) * host.bounds.height), to: nil)
            for type in middle ? [NSEvent.EventType.otherMouseDown, .otherMouseUp] : [.leftMouseDown, .leftMouseUp] {
                var event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1))
                if middle {
                    let cg = try XCTUnwrap(event.cgEvent); cg.setIntegerValueField(.mouseEventButtonNumber, value: 2)
                    event = try XCTUnwrap(NSEvent(cgEvent: cg))
                    XCTAssertEqual(event.buttonNumber, 2); XCTAssertTrue(event.window === window)
                }
                NSApp.postEvent(event, atStart: false)
            }
            for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
        }
        try await click("Meeting A", modifiers: .command)
        XCTAssertEqual(store.selectedPaths, ["Work/A.md"])
        XCTAssertNil(store.selection, "Command-click on a dated card must not open the editor")
        try await click("Meeting B", modifiers: .shift)
        XCTAssertEqual(store.selectedPaths, ["Work/A.md", "Work/B.md"])
        func key(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) async throws {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
                // Offscreen windows do not become the system key window.
                // Exercise their real key-equivalent/first-responder delivery.
                if type != .keyDown || !modifiers.contains(.command) || !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
            }
            for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
        }
        try await key("a", code: 0, modifiers: .command)
        XCTAssertEqual(store.selectedPaths, ["Work/A.md", "Work/B.md", "Work/C.md"], "Command-A selects the collection after a card click")
        try await key("\u{1b}", code: 53)
        XCTAssertTrue(store.selectedPaths.isEmpty); XCTAssertFalse(store.selecting)
        if window.firstResponder?.responds(to: #selector(NSText.selectAll(_:))) == true {
            XCTAssertTrue(NSApp.sendAction(#selector(NSText.selectAll(_:)), to: window.firstResponder, from: nil))
        } else { XCTFail("The collection first responder must accept Select All") }
        XCTAssertEqual(store.selectedPaths, ["Work/A.md", "Work/B.md", "Work/C.md"], "The standard Select All action reaches the collection responder")
        try await key("\u{1b}", code: 53)
        XCTAssertTrue(store.selectedPaths.isEmpty)
        store.clearCollectionSelection()
        try await click("Meeting A", modifiers: .command)
        try await click("Meeting B", modifiers: .shift)
        // A sibling text field has its own first responder. Collection shortcuts
        // must not consume its Select All or clear an unrelated bulk selection.
        let search = NSTextField(string: "Only this search text")
        search.frame = NSRect(x: 10, y: 5, width: 220, height: 24); host.addSubview(search)
        defer { search.removeFromSuperview() }
        XCTAssertTrue(window.makeFirstResponder(search))
        try await key("a", code: 0, modifiers: .command)
        let editor = try XCTUnwrap(window.fieldEditor(false, for: search) as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: (search.stringValue as NSString).length))
        XCTAssertEqual(store.selectedPaths, ["Work/A.md", "Work/B.md"])
        try await key("\u{1b}", code: 53)
        XCTAssertEqual(store.selectedPaths, ["Work/A.md", "Work/B.md"], "Escape in a text field must not clear the collection")
        // Peer reconciliation can remove selected members while editing. It
        // changes the model, not the user's current keyboard destination.
        XCTAssertTrue(window.makeFirstResponder(search))
        XCTAssertTrue(window.firstResponder === editor)
        store.selectedPaths.remove("Work/B.md")
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
        XCTAssertTrue(window.firstResponder === editor, "Membership reconciliation must not take text focus")
        try await key("a", code: 0, modifiers: .command)
        XCTAssertEqual(store.selectedPaths, ["Work/A.md"])
        store.selecting = true
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
        try await key("a", code: 0, modifiers: .command)
        XCTAssertEqual(store.selectedPaths, ["Work/A.md", "Work/B.md", "Work/C.md"], "Entering Select mode moves keyboard selection back to the collection")
        try await key("\u{1b}", code: 53)
        XCTAssertTrue(store.selectedPaths.isEmpty); XCTAssertFalse(store.selecting)
        search.removeFromSuperview()
        var layout = store.collectionLayout; layout.visibleProperties = []
        await store.updateCollectionLayout(layout)
        let hidden = try renderedText().joined(separator: "\n")
        XCTAssertTrue(hidden.contains("Meeting A")); XCTAssertTrue(hidden.contains("Meeting B")); XCTAssertTrue(hidden.contains("Undated C"))
        XCTAssertFalse(hidden.contains("Owner:")); XCTAssertFalse(hidden.contains("Score:"))
        store.selecting = true
        try await click("Meeting B", middle: true)
        for _ in 0..<30 where store.selection != "Work/B.md" { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(store.selection, "Work/B.md", "Middle-click opens a dated Calendar note even in Select mode")
        XCTAssertTrue(store.selectedPaths.isEmpty)
        await store.openCollection("Work", folder: true)
        await store.updateCollectionLayout(store.collectionLayout, mode: "Table")
        store.selecting = true
        _ = try renderedText()
        try await click("Undated C", middle: true)
        for _ in 0..<30 where store.selection != "Work/C.md" { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(store.selection, "Work/C.md", "Middle-click opens a Table title")
        try await click("Meeting A", count: 3)
        for _ in 0..<30 where store.selection != "Work/A.md" { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(store.selection, "Work/A.md", "Triple-click opens a Table title")
        XCTAssertTrue(store.selectedPaths.isEmpty)
        XCTAssertEqual(store.tabs.filter { $0 == .note("Work/A.md") }.count, 1)
        XCTAssertEqual(store.tabs.filter { $0 == .note("Work/C.md") }.count, 1)
        // Gallery uses its own event surface. Resolve targets from rendered
        // pixels after reflow so a stale or flipped hit region opens the wrong
        // note rather than passing through a model-only shortcut.
        for width: CGFloat in [900, 450] {
            await store.openCollection("Work", folder: true)
            await store.updateCollectionLayout(store.collectionLayout, mode: "Gallery")
            window.setContentSize(NSSize(width: width, height: 650))
            store.selecting = true
            let gallery = try renderedText().joined(separator: "\n")
            XCTAssertTrue(gallery.contains("Meeting A")); XCTAssertTrue(gallery.contains("Meeting B")); XCTAssertTrue(gallery.contains("Undated C"))
            try await click("Undated C", middle: true)
            for _ in 0..<30 where store.selection != "Work/C.md" { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertEqual(store.selection, "Work/C.md", "Gallery middle-click must resolve the visible card after reflow")
            _ = try renderedText()
            try await click("Meeting B", count: 3)
            for _ in 0..<30 where store.selection != "Work/B.md" { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertEqual(store.selection, "Work/B.md", "Gallery triple-click must resolve a different visible card")
            XCTAssertTrue(store.selectedPaths.isEmpty)
        }
        await store.openCollection("Work", folder: true)
        var grouped = store.collectionLayout; grouped.groupBy = "Priority"
        await store.updateCollectionLayout(grouped, mode: "Gallery")
        var sorted = store.filters; sorted.sort = .titleAscending; store.changeCollectionFilters(sorted)
        window.setContentSize(NSSize(width: 900, height: 1100))
        _ = try renderedText()
        // A has both High and Low, so its first visible card needs its own
        // region even while a second card for the same path is mounted below.
        try await click("Meeting A", middle: true)
        for _ in 0..<30 where store.selection != "Work/A.md" { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(store.selection, "Work/A.md", "Each visible occurrence of a multi-group note must receive alternate clicks")
        for (path, text) in sources { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(text.utf8)) }
        _ = await store.prepareToCloseWindow()
    }

    @MainActor func testCollectionExcerptResolvesFullSourceAndRefreshesAcrossNotesAndVaults() async throws {
        let roots = (0..<2).map { _ in FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-excerpt-" + UUID().uuidString) }
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        defer {
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            for root in roots {
                defaults.removeObject(forKey: MacNavigationState.key(root))
                defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
                try? FileManager.default.removeItem(at: root)
            }
        }
        for root in roots { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        let initial = "# Excerpt fixture\n\nVisible [roadmap label][page] appears here.\n\n" + String(repeating: "A later paragraph.\n\n", count: 2000) + "[page]: https://example.com/private-destination\n"
        let changed = "# Excerpt fixture\n\nUpdated **content** stays current.\n"
        let other = "# Excerpt fixture\n\nOther vault excerpt.\n"
        try Data(initial.utf8).write(to: roots[0].appendingPathComponent("Note.md"))
        try Data(other.utf8).write(to: roots[1].appendingPathComponent("Note.md"))
        let store = MacWorkspace(); await store.openVault(roots[0]); await store.openCollection("All Notes"); store.viewMode = "Gallery"
        let host = NSHostingView(rootView: MacCollectionViews(store: store, noteMenu: { _ in AnyView(EmptyView()) }).preferredColorScheme(.light))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1000, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        func expect(_ phrase: String, excluding old: String? = nil) async throws {
            var shown = ""
            for _ in 0..<30 {
                try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
                try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
                shown = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                if shown.contains(phrase) { break }
            }
            XCTAssertTrue(shown.contains(phrase), "The actual card must display its current parsed excerpt: \(shown)")
            if let old { XCTAssertFalse(shown.contains(old), "A previous note or vault must not replace the current excerpt") }
            XCTAssertFalse(shown.contains("private-destination"), "A late reference definition supplies a label, not a visible storage URL")
        }
        try await expect("Visible roadmap label appears here.")
        try Data(changed.utf8).write(to: roots[0].appendingPathComponent("Note.md"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: roots[0].appendingPathComponent("Note.md").path)
        await store.refresh()
        try await expect("Updated content stays current.", excluding: "Visible roadmap")
        await store.openVault(roots[1]); await store.openCollection("All Notes"); store.viewMode = "Gallery"
        try await expect("Other vault excerpt.", excluding: "Updated content")
        XCTAssertEqual(try Data(contentsOf: roots[0].appendingPathComponent("Note.md")), Data(changed.utf8))
        XCTAssertEqual(try Data(contentsOf: roots[1].appendingPathComponent("Note.md")), Data(other.utf8))
        _ = await store.prepareToCloseWindow()
    }

    @MainActor func testGalleryRendersItsLocalImageCoverInTheCard() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-gallery-render-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        defer {
            defaults.set(recent, forKey: "zerus.mac.recentVaults")
            defaults.removeObject(forKey: MacNavigationState.key(root))
            defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
            try? FileManager.default.removeItem(at: root)
        }
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0.8, blue: 0.2, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
        let imagePath = root.appendingPathComponent("cover.png")
        let image = try XCTUnwrap(CGImageDestinationCreateWithURL(imagePath as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(image, try XCTUnwrap(context.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(image))
        let source = "---\nzerus-id: gallery-note\n---\n# Design notes\n\n![A green illustration](cover.png)\n\nThe original note text stays intact.\n"
        try Data(source.utf8).write(to: root.appendingPathComponent("Design.md"))
        let store = MacWorkspace(); await store.openVault(root); await store.openCollection("All Notes")
        defer { if let directory = store.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) } }
        XCTAssertEqual(store.collection.map(\.path), ["Design.md"])
        store.viewMode = "Gallery"
        let view = MacCollectionViews(store: store, noteMenu: { _ in AnyView(EmptyView()) }).tint(Color(nsColor: MacMarkdown.accent)).preferredColorScheme(.light).background(Color.white)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 900, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        func settle() { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.015)) }
        func capture(blue: Bool) async throws -> NSBitmapImageRep {
            var matches = 0
            var rendered: NSBitmapImageRep?
            for _ in 0..<30 {
                try await Task.sleep(for: .milliseconds(50)); settle()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
                matches = 0
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) { for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent < 0.15,
                       blue ? color.blueComponent > 0.6 && color.blueComponent > color.greenComponent + 0.25 : color.greenComponent > 0.6 && color.greenComponent > color.blueComponent + 0.25 { matches += 1 }
                } }
                rendered = bitmap
                if matches > 400 { break }
            }
            XCTAssertGreaterThan(matches, 400, "The gallery must display its current cover, including external image replacements")
            return try XCTUnwrap(rendered)
        }
        let green = try await capture(blue: false)
        if let cg = green.cgImage { let attachment = XCTAttachment(image: NSImage(cgImage: cg, size: .zero)); attachment.name = "Native gallery cover fixture"; attachment.lifetime = .keepAlways; add(attachment) }
        let previousVersion = store.collectionFileDates["cover.png"]
        context.setFillColor(CGColor(red: 0, green: 0.2, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
        let replacement = try XCTUnwrap(CGImageDestinationCreateWithURL(imagePath as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(replacement, try XCTUnwrap(context.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(replacement))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: imagePath.path)
        await store.refresh()
        XCTAssertNotEqual(store.collectionFileDates["cover.png"], previousVersion)
        let blue = try await capture(blue: true)
        if let cg = blue.cgImage { let attachment = XCTAttachment(image: NSImage(cgImage: cg, size: .zero)); attachment.name = "Native gallery replaced cover fixture"; attachment.lifetime = .keepAlways; add(attachment) }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Design.md")), Data(source.utf8))
        _ = await store.prepareToCloseWindow()
    }

    func testCardCoverRejectsOversizedPixelDimensionsBeforeDecoding() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-cover-dimensions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (width, height): (UInt32, UInt32) in [(20_000, 1), (7_000, 7_000)] {
        var bytes = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        func word(_ value: UInt32) -> [UInt8] { [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)] }
        // A real PNG header can declare enormous dimensions in very few bytes.
        // The pre-fix baseline used only 20k x 1. The 49 MP case runs with
        // the guard present, so it is refused before pixel allocation.
        bytes.replaceSubrange(16..<24, with: word(width) + word(height))
        var crc = UInt32.max
        for byte in bytes[12..<29] { crc ^= UInt32(byte); for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 } }
        bytes.replaceSubrange(29..<33, with: word(~crc))
        // Keep ImageIO's header probe from rejecting the tiny, deliberately
        // truncated pixel payload before our dimension guard can inspect it.
        if height > 1 { bytes.append(Data(repeating: 0, count: 65_536)) }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, Int(width))
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, Int(height))
        let image = root.appendingPathComponent("oversized-\(width).png"); try bytes.write(to: image)
        let io = VaultFiles(root: root), loader = MacCollectionCoverLoader(), workspaceID = UUID()
        let fileDates = try await io.scan().fileDates
        do {
            _ = try await loader.load(note: .init(path: "Card.md", content: "![Large](oversized-\(width).png)\n", modified: .distantPast), io: io, workspaceID: workspaceID, fileDates: fileDates)
            XCTFail("A small compressed file must not bypass the pixel-dimension limit")
        } catch { XCTAssertTrue(error.localizedDescription.contains("supported dimensions"), error.localizedDescription) }
        XCTAssertEqual(try Data(contentsOf: image), bytes)
        }
    }

    func testCardCoverReadsFirstRealImageAndKeepsVaultBytesAcrossCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-card-cover-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 2400, height: 1200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0.8, blue: 0.2, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        let path = root.appendingPathComponent("Work/z-first.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let originalImage = try Data(contentsOf: path)
        let markdown = "# Card\n\n```md\n![Not a cover](missing.png)\n```\n\n![First illustration](z-first.png)\n\n![Later](a-unavailable.png)\n"
        let note = NoteDocument(path: "Work/A.md", content: markdown, modified: .distantPast)
        let notePath = root.appendingPathComponent(note.path); try Data(markdown.utf8).write(to: notePath)
        let io = VaultFiles(root: root), loader = MacCollectionCoverLoader(), workspaceID = UUID()
        let fileDates = try await io.scan().fileDates
        let loaded = try await loader.load(note: note, io: io, workspaceID: workspaceID, fileDates: fileDates)
        let cover = try XCTUnwrap(loaded)
        XCTAssertEqual(cover.caption, "First illustration")
        XCTAssertEqual(cover.image.width, 720); XCTAssertEqual(cover.image.height, 360)
        XCTAssertEqual(try Data(contentsOf: path), originalImage)
        // The UI still holds this version inventory. A text-only autosave and
        // an unrelated resource change must reuse the decoded image, not re-read it.
        try FileManager.default.removeItem(at: path)
        var edited = note; edited.content = markdown.replacingOccurrences(of: "First illustration", with: "Updated description") + "\nMore writing.\n"
        var unrelated = fileDates; unrelated["Elsewhere.pdf"] = .init(modified: Date(), created: nil)
        let reused = try await loader.load(note: edited, io: io, workspaceID: workspaceID, fileDates: unrelated)
        XCTAssertEqual(reused?.caption, "Updated description")
        XCTAssertEqual(reused?.image.width, 720)
        try originalImage.write(to: path)
        // Percent-encoded root assets use root-first resolution, even when a
        // note-relative asset exists too. Unknown root versions must not borrow
        // the fallback's timestamp and cache the preferred image indefinitely.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Work/assets"), withIntermediateDirectories: true)
        let preferred = root.appendingPathComponent("assets/cover.png")
        try originalImage.write(to: preferred)
        try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")).write(to: root.appendingPathComponent("Work/assets/cover.png"))
        var versions = try await io.scan().fileDates
        versions["assets/cover.png"] = .init(modified: .distantPast, created: nil)
        var encoded = NoteDocument(path: "Work/Encoded.md", content: "![Cover](%61ssets/cover.png)\n", modified: .distantPast)
        let preferredCover = try await loader.load(note: encoded, io: io, workspaceID: workspaceID, fileDates: versions)
        XCTAssertEqual(preferredCover?.image.width, 720); XCTAssertEqual(preferredCover?.image.height, 360)
        try FileManager.default.removeItem(at: preferred)
        encoded.content += "\nMore writing.\n"
        let fallbackImage = try await loader.load(note: encoded, io: io, workspaceID: workspaceID, fileDates: versions)
        let fallback = try XCTUnwrap(fallbackImage)
        XCTAssertEqual(fallback.image.width, fallback.image.height, "An unknown preferred version must be read again, then follow the reader's square fallback")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loader.load(note: note, io: io, workspaceID: workspaceID, fileDates: fileDates)
        }
        do { _ = try await cancelled.value; XCTFail("A cancelled preview must not be published") }
        catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        let next = try await loader.load(note: note, io: io, workspaceID: workspaceID, fileDates: fileDates)
        XCTAssertNotNil(next, "A cancelled queue entry must not block later covers")
        let codeOnly = NoteDocument(path: note.path, content: "```md\n![Example](missing.png)\n```\n", modified: .distantPast)
        let empty = try await loader.load(note: codeOnly, io: io, workspaceID: workspaceID, fileDates: fileDates); XCTAssertNil(empty)
        let remote = NoteDocument(path: note.path, content: "![Remote](https://example.invalid/cover.png)\n", modified: .distantPast)
        do { _ = try await loader.load(note: remote, io: io, workspaceID: workspaceID, fileDates: fileDates); XCTFail("Card rendering must use the vault resource reader") }
        catch { XCTAssertTrue(error.localizedDescription.contains("not stored in the vault"), error.localizedDescription) }
        XCTAssertEqual(try Data(contentsOf: path), originalImage)
        XCTAssertEqual(try Data(contentsOf: notePath), Data(markdown.utf8))
    }
}
