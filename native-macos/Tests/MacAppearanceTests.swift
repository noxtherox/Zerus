import XCTest
import SwiftUI
import AppKit
import Vision
@testable import Zerus_Native

final class MacAppearanceTests: XCTestCase {
    @MainActor func testDesktopSettingsImportValidatesTheSnapshotAndRefusesStaleReviewWithoutReplacingOtherPreferences() throws {
        let suite = "Zerus-desktop-import-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let palette: [String: String] = ["accent":"#123456", "link":"#234567", "text":"#345678", "editorBg":"#456789", "surface":"#56789A", "sidebarBg":"#6789AB", "sidebarFg":"#789ABC"]
        let object: [String: Any] = ["format":"zerus-desktop-settings", "version":1, "settings":["dateFormat":"MM/DD/YYYY", "interfaceZoom":125, "noteWidth":60, "noteAlignment":"left", "codeBlocks":true, "noteLinkShortcuts":false, "appearance":"dark", "lightTheme":palette, "darkTheme":palette, "savedThemes":[["name":"Existing", "theme":palette], ["name":"Imported café", "theme":palette]]]]
        let data = try JSONSerialization.data(withJSONObject: object)
        defaults.set("kept", forKey: "unrelated.preference")
        defaults.set(100, forKey: "zerus.mac.interfaceZoom")
        defaults.set(##"{"version":1,"lightTheme":{"colors":{"futureRole":"#ABCDEF"}},"saved":[{"name":"Existing","palette":{"colors":{"accent":"#112233","futurePreset":"#AABBCC"}}}]}"##, forKey: "zerus.mac.themes")
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let review = try MacDesktopSettingsReview(data: data, name: "Chosen.json", defaults: defaults)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before, "Preparing or cancelling a review does not change preferences")
        defaults.set(90, forKey: "zerus.mac.interfaceZoom")
        XCTAssertThrowsError(try review.apply(defaults: defaults)) { error in XCTAssertTrue(error.localizedDescription.contains("changed after review")) }
        XCTAssertNil(defaults.object(forKey: "zerus.mac.dateFormat")); XCTAssertEqual(defaults.integer(forKey: "zerus.mac.interfaceZoom"), 90)
        let fresh = try MacDesktopSettingsReview(data: data, name: "Chosen.json", defaults: defaults)
        try fresh.apply(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "zerus.mac.dateFormat"), "MM/DD/YYYY")
        XCTAssertEqual(defaults.integer(forKey: "zerus.mac.interfaceZoom"), 125)
        XCTAssertEqual(defaults.integer(forKey: "zerus.mac.noteWidth"), 60)
        XCTAssertEqual(defaults.string(forKey: "zerus.mac.noteAlignment"), "left")
        XCTAssertTrue(defaults.bool(forKey: "zerus.mac.codeBlocks")); XCTAssertFalse(defaults.bool(forKey: "zerus.mac.noteLinkShortcuts"))
        XCTAssertEqual(defaults.string(forKey: "zerus.mac.appearance"), "dark")
        let themes = try MacThemePreferences.decode(try XCTUnwrap(defaults.string(forKey: "zerus.mac.themes")))
        XCTAssertEqual(themes.lightTheme?.colors[.accent], "#123456"); XCTAssertEqual(themes.darkTheme?.colors[.sidebarFg], "#789ABC")
        XCTAssertEqual(themes.lightTheme?.additionalColors["futureRole"], "#ABCDEF")
        XCTAssertEqual(themes.saved.map(\.name), ["Existing", "Imported café"])
        XCTAssertEqual(themes.saved.first?.palette.colors[.accent], "#123456", "A matching named palette is replaced once")
        XCTAssertEqual(themes.saved.first?.palette.additionalColors["futurePreset"], "#AABBCC")
        XCTAssertEqual(defaults.string(forKey: "unrelated.preference"), "kept")
        let applied = defaults.dictionaryRepresentation() as NSDictionary
        for broken in [Data("{}".utf8), Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "zerus-desktop-settings", with: "other-format").utf8), Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "#123456", with: "red").utf8), Data(repeating: 32, count: 256 * 1024 + 1)] {
            XCTAssertThrowsError(try MacDesktopSettingsReview(data: broken, name: "Broken.json", defaults: defaults))
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, applied)
        }
    }
    @MainActor func testColourSettingsApplyLiveWithoutLosingPartialInputOrOtherPalettes() async throws {
        let suite = "Zerus-live-colours-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite)), key = "zerus.mac.themes"
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set("light", forKey: "zerus.mac.appearance")
        preferences.set(##"{"version":1,"lightTheme":{"colors":{"editorBg":"#FAFBFC","futureRole":"#123456"}},"darkTheme":{"colors":{"editorBg":"#112233"}},"saved":[{"name":"Existing","palette":{"colors":{"editorBg":"#14171D","surface":"#191D24","accent":"#AC1234"}}}]}"##, forKey: key)
        func settings() -> NSHostingView<AnyView> {
            NSHostingView(rootView: AnyView(MacThemeSettingsView().defaultAppStorage(preferences).environment(\.colorScheme, .dark).background(Color.black)))
        }
        var host = settings(), publishedText: [String] = []
        let preview = NSHostingView(rootView: MacRichEditor(markdown: "# Preview\n\nUnchanged text.\n", source: false, editable: true, onChange: { publishedText.append($0) }, onLink: { _ in }).modifier(MacThemeHost()).defaultAppStorage(preferences).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 580, height: 950), styleMask: .borderless, backing: .buffered, defer: false)
        let peer = NSWindow(contentRect: NSRect(x: -21000, y: 0, width: 450, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        for item in [window, peer] { item.isReleasedWhenClosed = false; item.appearance = NSAppearance(named: .aqua) }
        window.contentView = host; peer.contentView = preview; window.orderFront(nil); peer.orderFront(nil)
        defer { window.contentView = nil; peer.contentView = nil; window.close(); peer.close() }
        func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
        func settle() async throws { for _ in 0..<15 { host.layoutSubtreeIfNeeded(); preview.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) } }
        var backgroundField: NSTextField?
        func field() throws -> NSTextField {
            if let backgroundField { return backgroundField }
            let fields = nodes(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
            // The unique fixture colour identifies the real background field;
            // SwiftUI Form may expose its label on an accessibility wrapper.
            let expected = try MacThemePreferences.decode(try XCTUnwrap(preferences.string(forKey: key))).lightTheme?.colors[.editorBg]
            let result = try XCTUnwrap(fields.first { $0.stringValue == expected }, "Native fields: " + fields.map { $0.stringValue + " / " + ($0.placeholderString ?? "nil") }.joined(separator: ", "))
            backgroundField = result; return result
        }
        func saved() throws -> MacThemePreferences { try .decode(try XCTUnwrap(preferences.string(forKey: key))) }
        func replace(_ text: String) async throws -> NSTextView {
            let target = try field(); XCTAssertTrue(window.makeFirstResponder(target)); try await settle()
            let editor = try XCTUnwrap(window.fieldEditor(true, for: target) as? NSTextView)
            editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count)); try await settle()
            return editor
        }
        func rgb(_ hex: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
        try await settle()
        let nativeEditor = try XCTUnwrap(nodes(preview).compactMap { $0 as? NSTextView }.first { !$0.isFieldEditor })
        XCTAssertEqual(nativeEditor.backgroundColor.usingColorSpace(.sRGB), rgb(0xFAFBFC))
        let editor = try await replace("#abc")
        XCTAssertEqual(try saved().lightTheme?.colors[.editorBg], "#AABBCC", "A valid colour is saved without an Apply action")
        XCTAssertEqual(nativeEditor.backgroundColor.usingColorSpace(.sRGB), rgb(0xAABBCC), "A separate native editor previews the change immediately")
        XCTAssertEqual(editor.string, "#abc", "Normalization must not move the caret or rewrite a focused short hex value")
        editor.insertText("1", replacementRange: NSRange(location: editor.string.utf16.count, length: 0)); try await settle()
        XCTAssertEqual(editor.string, "#abc1"); XCTAssertEqual(try saved().lightTheme?.colors[.editorBg], "#AABBCC")
        editor.insertText("23", replacementRange: NSRange(location: editor.string.utf16.count, length: 0)); try await settle()
        XCTAssertEqual(try saved().lightTheme?.colors[.editorBg], "#ABC123")
        _ = try await replace("#12")
        XCTAssertEqual(try saved().lightTheme?.colors[.editorBg], "#ABC123")
        window.makeFirstResponder(nil); try await settle()
        XCTAssertEqual(try field().stringValue, "#ABC123", "Incomplete text resets to the saved colour on blur")
        _ = try await replace("#1")
        var changedElsewhere = try saved(); changedElsewhere.lightTheme?.colors[.accent] = "#778899"
        preferences.set(try changedElsewhere.encoded(), forKey: key); try await settle()
        XCTAssertEqual((window.firstResponder as? NSTextView)?.string, "#1", "A peer preference update keeps focused partial text")
        _ = try await replace("#010203"); window.makeFirstResponder(nil); try await settle()
        XCTAssertEqual(try saved().lightTheme?.colors[.accent], "#778899")
        XCTAssertEqual(try saved().lightTheme?.additionalColors["futureRole"], "#123456")
        window.contentView = nil; host = settings(); backgroundField = nil; window.contentView = host; try await settle()
        XCTAssertEqual(try field().stringValue, "#010203", "Closing and reopening settings retains the last valid edit")
        let picker = try XCTUnwrap(nodes(host).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 2 && $0.label(forSegment: 0) == "Light" })
        func palette(_ segment: Int) async throws { window.makeFirstResponder(nil); picker.selectedSegment = segment; _ = picker.sendAction(picker.action, to: picker.target); try await settle() }
        try await palette(1)
        XCTAssertEqual(try field().stringValue, "#112233")
        _ = try await replace("#a0b0c0"); window.makeFirstResponder(nil); try await settle()
        XCTAssertEqual(try saved().darkTheme?.colors[.editorBg], "#A0B0C0")
        XCTAssertEqual(try saved().lightTheme?.colors[.editorBg], "#010203")
        XCTAssertEqual(nativeEditor.backgroundColor.usingColorSpace(.sRGB), rgb(0x010203), "Editing the dark palette cannot recolour a light editor")
        try await palette(0)
        func click(_ title: String) async throws {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.cgImage), request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = false; request.usesCPUOnly = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = try XCTUnwrap(request.results?.compactMap { $0.topCandidates(1).first }.first { $0.string.contains(title) && (title != "Load" || !$0.string.contains("preset") && !$0.string.contains("Loading")) })
            let range = try XCTUnwrap(text.string.range(of: title)), box = try XCTUnwrap(try text.boundingBox(for: range)?.boundingBox)
            let point = host.convert(NSPoint(x: box.midX * host.bounds.width, y: (host.isFlipped ? 1 - box.midY : box.midY) * host.bounds.height), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                NSApp.postEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)), atStart: false)
            }
            try await settle()
        }
        try await click("Load")
        XCTAssertEqual(preferences.string(forKey: "zerus.mac.appearance"), "dark", "Loading a dark palette switches native window chrome and controls too")
        XCTAssertEqual(try saved().darkTheme?.colors[.editorBg], "#14171D")
        XCTAssertEqual(try saved().lightTheme?.colors[.editorBg], "#010203", "The inactive light palette stays intact")
        XCTAssertEqual(nativeEditor.backgroundColor.usingColorSpace(.sRGB), rgb(0x14171D))
        for (label, view) in [("Live native colour settings", host as NSView), ("Live palette in another native editor", preview as NSView)] {
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.cgImage), attachment = XCTAttachment(image: NSImage(cgImage: image, size: .zero))
            attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(try saved().lightTheme?.additionalColors["futureRole"], "#123456")
        XCTAssertEqual(try saved().darkTheme?.colors[.editorBg], "#14171D")
        try await click("Use Mac defaults")
        XCTAssertNil(try saved().darkTheme); XCTAssertEqual(try saved().lightTheme?.colors[.editorBg], "#010203")
        XCTAssertEqual(try saved().saved.map(\.name), ["Existing"])
        preferences.set("{broken", forKey: key); try await settle()
        XCTAssertFalse(try field().isEnabled); XCTAssertEqual(preferences.string(forKey: key), "{broken")
        XCTAssertTrue(publishedText.isEmpty, "Theme previews must not publish document edits")
    }

    func testIndependentPalettesAndNamedThemesSurviveReloadWithoutAcceptingInvalidRecords() throws {
        var preferences = MacThemePreferences()
        var light = MacThemePalette.defaults(dark: false), dark = MacThemePalette.defaults(dark: true)
        light.colors[.accent] = "#abc"; dark.colors[.text] = "#fedcba"
        preferences.lightTheme = try light.validated(); preferences.darkTheme = try dark.validated()
        try preferences.save(name: "  Writing  ", palette: light)
        let encoded = try preferences.encoded(), reloaded = try MacThemePreferences.decode(encoded)
        XCTAssertEqual(reloaded.lightTheme?.colors[.accent], "#AABBCC")
        XCTAssertEqual(reloaded.darkTheme?.colors[.text], "#FEDCBA")
        XCTAssertEqual(reloaded.saved.first?.name, "Writing")
        XCTAssertEqual(reloaded.saved.first?.palette.colors[.accent], "#AABBCC")
        XCTAssertThrowsError(try preferences.save(name: "WRITING", palette: dark))
        try preferences.save(name: "Writing", palette: dark, replacing: true)
        XCTAssertEqual(preferences.saved.count, 1)
        XCTAssertEqual(preferences.saved.first?.palette.colors[.text], "#FEDCBA")
        XCTAssertThrowsError(try preferences.save(name: "Paper", palette: light))
        XCTAssertThrowsError(try preferences.save(name: "\n", palette: dark))
        XCTAssertThrowsError(try preferences.save(name: "Two\nlines", palette: dark))
        var invalid = light; invalid.colors[.text] = "red"
        XCTAssertThrowsError(try preferences.save(name: "Bad", palette: invalid))
        invalid.colors.removeValue(forKey: .text)
        preferences.lightTheme = invalid
        let partial = try MacThemePreferences.decode(preferences.encoded())
        XCTAssertNil(partial.lightTheme?.colors[.text])
        XCTAssertThrowsError(try MacThemePreferences.decode("{broken"))
        XCTAssertThrowsError(try MacThemePreferences.decode(encoded.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")))
        preferences = reloaded; preferences.lightTheme = nil; preferences.saved.removeAll()
        let reset = try MacThemePreferences.decode(preferences.encoded())
        XCTAssertNil(reset.lightTheme)
        XCTAssertEqual(reset.darkTheme, reloaded.darkTheme)
        XCTAssertTrue(reset.saved.isEmpty)
        XCTAssertEqual(try MacThemePreferences.decode(""), MacThemePreferences())
        let future = ##"{"version":1,"lightTheme":{"colors":{"accent":"#abc","futureRole":"#123456"}},"saved":[]}"##
        let compatible = try MacThemePreferences.decode(future)
        XCTAssertEqual(compatible.lightTheme?.color(.accent), MacThemePalette(colors: [.accent: "#AABBCC"]).color(.accent))
        XCTAssertEqual(compatible.lightTheme?.color(.text), MacThemeRole.text.fallback)
        let object = try JSONSerialization.jsonObject(with: Data(compatible.encoded().utf8)) as? [String: Any]
        let colors = (object?["lightTheme"] as? [String: Any])?["colors"] as? [String: String]
        XCTAssertEqual(colors?["futureRole"], "#123456")
    }
}
