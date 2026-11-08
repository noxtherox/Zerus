import XCTest
import SwiftUI
import UIKit
@testable import ZerusNative

final class NativeAppearanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUpWithError() throws {
        suite = "ZerusAppearanceTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }
    override func tearDownWithError() throws { defaults.removePersistentDomain(forName: suite) }
    private func palette(_ accent: String = "#123456") -> NativeThemePalette {
        .init(accent: accent, link: "#2468AC", text: "#102030", editorBg: "#FAFBFC", surface: "#DDEEFF", sidebarBg: "#203040", sidebarFg: "#F0E0D0")
    }
    @MainActor
    func testModeAndIndependentPalettesSurviveColdOpenAndRejectInvalidUpdatesWithoutRewritingUnreadablePreferences() throws {
        defaults.set("dark", forKey: NativeAppearanceStore.modeKey)
        let store = NativeAppearanceStore(defaults: defaults)
        XCTAssertEqual(store.mode, .dark); XCTAssertNil(store.palettes.lightTheme); XCTAssertNil(store.palettes.darkTheme)
        XCTAssertNil(defaults.object(forKey: NativeAppearanceStore.palettesKey), "Opening existing native settings must not create custom colours")
        var light = palette(); light.accent = " #abc "; try store.setPalette(light, slot: .light)
        let dark = palette("#CC8844"); try store.setPalette(dark, slot: .dark)
        store.setMode(.system)
        let reopened = NativeAppearanceStore(defaults: defaults)
        XCTAssertEqual(reopened.mode, .system); XCTAssertEqual(reopened.palettes.lightTheme?.accent, "#AABBCC")
        XCTAssertEqual(reopened.palettes.darkTheme, dark); XCTAssertEqual(reopened.palettes.lightTheme?.surface, "#DDEEFF")
        let before = try XCTUnwrap(defaults.data(forKey: NativeAppearanceStore.palettesKey))
        for value in ["red", "#1234", "#abcdef00", "#GGGGGG", "", "rgb(1,2,3)"] {
            var invalid = light; invalid.sidebarFg = value
            XCTAssertThrowsError(try reopened.setPalette(invalid, slot: .light)); XCTAssertEqual(defaults.data(forKey: NativeAppearanceStore.palettesKey), before)
        }
        let unreadable = Data(#"{"lightTheme":{"newerColourModel":true},"future":42}"#.utf8)
        defaults.set(unreadable, forKey: NativeAppearanceStore.palettesKey)
        let protected = NativeAppearanceStore(defaults: defaults)
        XCTAssertNotNil(protected.paletteIssue); XCTAssertEqual(defaults.data(forKey: NativeAppearanceStore.palettesKey), unreadable)
        XCTAssertThrowsError(try protected.setPalette(dark, slot: .dark)); XCTAssertEqual(defaults.data(forKey: NativeAppearanceStore.palettesKey), unreadable)
        protected.reset(); XCTAssertNil(protected.paletteIssue); XCTAssertEqual(protected.mode, .system); XCTAssertNil(defaults.object(forKey: NativeAppearanceStore.palettesKey))
    }
    @MainActor
    func testNamedThemeReplacementDeleteUndoAndResetPreserveForeignRowsAndSavedThemes() throws {
        let store = NativeAppearanceStore(defaults: defaults), first = palette(), second = palette("#A1B2C3")
        try store.save("  Field Notes  ", theme: first)
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: NativeAppearanceStore.savedKey))) as? [[String: Any]])
        rows[0]["future"] = ["keep": true]
        let foreign: [String: Any] = ["name": "Future", "theme": ["newerModel": true], "foreign": [1, 2, 3]]
        rows.append(foreign)
        defaults.set(try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), forKey: NativeAppearanceStore.savedKey)
        let cold = NativeAppearanceStore(defaults: defaults)
        XCTAssertEqual(cold.saved.count, 1); XCTAssertNotNil(cold.savedIssue)
        try cold.save("field notes", theme: second)
        var updated = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: NativeAppearanceStore.savedKey))) as? [[String: Any]])
        XCTAssertEqual(updated.count, 2); XCTAssertEqual((updated[0]["future"] as? [String: Bool])?["keep"], true)
        XCTAssertTrue(NSDictionary(dictionary: updated[1]).isEqual(to: foreign)); XCTAssertEqual(cold.saved.first?.theme, second)
        XCTAssertThrowsError(try cold.save("Ocean", theme: first)); XCTAssertThrowsError(try cold.save(String(repeating: "a", count: 41), theme: first))
        let saved = try XCTUnwrap(cold.saved.first); try cold.delete(saved)
        XCTAssertTrue(cold.saved.isEmpty); XCTAssertNotNil(cold.undoName)
        try cold.undoDelete(); XCTAssertEqual(cold.saved.first?.theme, second)
        updated = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: NativeAppearanceStore.savedKey))) as? [[String: Any]])
        XCTAssertEqual((updated[0]["future"] as? [String: Bool])?["keep"], true); XCTAssertTrue(NSDictionary(dictionary: updated[1]).isEqual(to: foreign))
        try cold.setPalette(second, slot: .dark); cold.setMode(.dark)
        let savedBytes = defaults.data(forKey: NativeAppearanceStore.savedKey)
        cold.reset(); XCTAssertEqual(defaults.data(forKey: NativeAppearanceStore.savedKey), savedBytes); XCTAssertEqual(cold.mode, .system)
        let final = NativeAppearanceStore(defaults: defaults); XCTAssertEqual(final.saved.first?.theme, second)
        let malformed = Data(#"{"notAnArray":true}"#.utf8); defaults.set(malformed, forKey: NativeAppearanceStore.savedKey)
        let unsupported = NativeAppearanceStore(defaults: defaults); XCTAssertThrowsError(try unsupported.save("Keep original", theme: first)); XCTAssertEqual(defaults.data(forKey: NativeAppearanceStore.savedKey), malformed)
    }
    @MainActor
    func testSwiftUIPaletteBridgeUpdatesRealTextKitColoursAndAttachmentsWithoutChangingFileCaretOrUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let source = "---\r\nzerus-id: palette-owner\r\nforeign: keep\r\n---\r\n# Palette 🧭\r\n\r\nBefore **bold** [linked text](https://example.invalid) writing.\r\n\r\n- [ ] Keep this\r\n\r\n```swift\r\nlet value = 42\r\n```\r\n\r\n| Item | Owner |\r\n| --- | --- |\r\n| Native | Test |\r\n"
        let file = root.appendingPathComponent("Palette.md"); try Data(source.utf8).write(to: file)
        let session = NoteSession(note: .init(path: "Palette.md", content: source, modified: .now), root: root, io: VaultFiles(root: root), onSave: { _ in }); defer { session.deactivate() }
        let store = NativeAppearanceStore(defaults: defaults); store.setMode(.light)
        let actions = NativeEditorActions()
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        let host = UIHostingController(rootView: AppearanceWritingFixture(appearance: store, session: session, actions: actions))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        await settle { actions.coordinator?.view?.window != nil }
        let view = try XCTUnwrap(actions.coordinator?.view); view.layoutIfNeeded(); XCTAssertTrue(view.becomeFirstResponder())
        let toggle = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Complete: Keep this" }); toggle.sendActions(for: .touchUpInside)
        await session.save(); let checked = source.replacingOccurrences(of: "- [ ] Keep this", with: "- [x] Keep this")
        XCTAssertEqual(try Data(contentsOf: file), Data(checked.utf8)); XCTAssertTrue(try XCTUnwrap(view.undoManager).canUndo)
        let selection = (view.text as NSString).range(of: "Before"); view.selectedRange = selection
        let textBefore = view.text, code = try XCTUnwrap(attachments(view).compactMap { $0 as? CodeAttachment }.first), table = try XCTUnwrap(attachments(view).compactMap { $0 as? TableAttachment }.first)
        let oldImage = code.image?.pngData()
        var custom = palette("#AA3300"); custom.text = "#112233"; custom.surface = "#304050"
        try store.setPalette(custom, slot: .light)
        await settle { view.layoutIfNeeded(); return view.traitCollection[NativeThemeTrait.self].lightTheme == custom }
        XCTAssertEqual(view.traitCollection[NativeThemeTrait.self].lightTheme, custom, "The actual bridged environment must reach the owned UITextView")
        let ink = try XCTUnwrap(view.attributedText.attribute(.foregroundColor, at: selection.location, effectiveRange: nil) as? UIColor)
        assertRGB(ink.resolvedColor(with: view.traitCollection), [17, 34, 51])
        assertRGB(view.tintColor.resolvedColor(with: view.traitCollection), [170, 51, 0])
        assertRGB(try XCTUnwrap(view.linkTextAttributes[.foregroundColor] as? UIColor).resolvedColor(with: view.traitCollection), [36, 104, 172])
        XCTAssertFalse(code.image?.pngData() == oldImage, "A visible code preview must actually adopt the palette")
        assertRGB(try backgroundPixel(try XCTUnwrap(code.image)), [48, 64, 80])
        XCTAssertTrue(attachments(view).contains { $0 === code }); XCTAssertTrue(attachments(view).contains { $0 === table })
        XCTAssertEqual(view.selectedRange, selection); XCTAssertEqual(view.text, textBefore); XCTAssertFalse(session.dirty); XCTAssertEqual(try Data(contentsOf: file), Data(checked.utf8))
        XCTAssertTrue(view.isFirstResponder); XCTAssertTrue(try XCTUnwrap(view.undoManager).canUndo)
        view.undoManager?.undo(); await session.save(); view.layoutIfNeeded(); XCTAssertEqual(try Data(contentsOf: file), Data(source.utf8))
        view.undoManager?.redo(); await session.save(); view.layoutIfNeeded(); XCTAssertEqual(try Data(contentsOf: file), Data(checked.utf8))
        var dark = palette("#BBDDFF"); dark.text = "#E0C0A0"; dark.surface = "#152535"
        try store.setPalette(dark, slot: .dark); store.setMode(.dark)
        await settle { view.layoutIfNeeded(); return view.traitCollection.userInterfaceStyle == .dark }
        XCTAssertEqual(view.traitCollection.userInterfaceStyle, .dark)
        let currentRange = (view.text as NSString).range(of: "Before"), currentInk = try XCTUnwrap(view.attributedText.attribute(.foregroundColor, at: currentRange.location, effectiveRange: nil) as? UIColor)
        assertRGB(currentInk.resolvedColor(with: view.traitCollection), [224, 192, 160])
        XCTAssertEqual(try Data(contentsOf: file), Data(checked.utf8)); XCTAssertFalse(session.dirty)
    }
    @MainActor
    func testSwiftUIRendersAllSevenAppRolesFromTheSelectedPalette() async throws {
        let appearance = NativeAppearanceStore(defaults: defaults)
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene)), container = UIViewController()
        window.overrideUserInterfaceStyle = .light
        let host = UIHostingController(rootView: AppearanceSwatchesFixture(appearance: appearance))
        window.rootViewController = container; container.addChild(host); container.view.addSubview(host.view); host.view.frame = CGRect(x: 0, y: 0, width: 280, height: 100); host.didMove(toParent: container); window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        await Task.yield(); host.view.layoutIfNeeded()
        // The real failure appeared when choosing a preset on an already open
        // screen. Initial rendering alone does not prove live appearance.
        try appearance.setPalette(palette(), slot: .light)
        await Task.yield(); host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 280, height: 100), format: format).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Seven actual SwiftUI palette roles"; attachment.lifetime = .keepAlways; add(attachment)
        let pixels = try XCTUnwrap(image.cgImage)
        let expected = [[18,52,86], [36,104,172], [16,32,48], [250,251,252], [221,238,255], [32,48,64], [240,224,208]]
        for (index, rgb) in expected.enumerated() {
            let sample = try XCTUnwrap(pixels.cropping(to: CGRect(x: index * 40 + 20, y: 25, width: 1, height: 1)))
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)); context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            for channel in 0..<3 { XCTAssertEqual(Int(bytes[channel]), rgb[channel], accuracy: 2, "App role \(index), channel \(channel)") }
        }
        let tintSample = try XCTUnwrap(pixels.cropping(to: CGRect(x: 140, y: 75, width: 1, height: 1)))
        var tint = [UInt8](repeating: 0, count: 4)
        let tintContext = try XCTUnwrap(CGContext(data: &tint, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)); tintContext.draw(tintSample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(Array(tint.prefix(3)), [18, 52, 86], "The real app presentation modifier must resolve its tint inside the palette environment")
    }
    @MainActor
    func testPresentedSheetAdoptsPaletteAndUpdatesWhileOpen() async throws {
        let appearance = NativeAppearanceStore(defaults: defaults)
        try appearance.setPalette(palette(), slot: .light)
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        window.overrideUserInterfaceStyle = .light
        let host = UIHostingController(rootView: AppearanceSheetFixture(appearance: appearance))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        await settle { host.presentedViewController?.view.window != nil }
        let sheet = try XCTUnwrap(host.presentedViewController?.view)
        // A visible sheet is a different UIKit presentation boundary from the
        // root screen; a root-only raster cannot catch this regression.
        for expected in [[18, 52, 86], [170, 51, 0]] {
            if expected[0] == 170 { try appearance.setPalette(palette("#AA3300"), slot: .light) }
            await Task.yield(); sheet.setNeedsLayout(); sheet.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: sheet.bounds).image { _ in sheet.drawHierarchy(in: sheet.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "Actual sheet tint \(expected)"; attachment.lifetime = .keepAlways; add(attachment)
            assertRGB(try backgroundPixel(image), expected)
        }
    }
    @MainActor private func settle(_ predicate: () -> Bool) async {
        let end = ContinuousClock.now + .seconds(5)
        while !predicate(), ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(25)) }
    }
    @MainActor private func attachments(_ view: UITextView) -> [NSTextAttachment] {
        var result: [NSTextAttachment] = []; view.attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.attributedText.length)) { value, _, _ in if let item = value as? NSTextAttachment { result.append(item) } }; return result
    }
    private func assertRGB(_ color: UIColor, _ expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a), file: file, line: line)
        for (value, expected) in zip([r, g, b], expected) { XCTAssertEqual(Double(value * 255), Double(expected), accuracy: 2, file: file, line: line) }
    }
    private func backgroundPixel(_ image: UIImage) throws -> UIColor {
        let source = try XCTUnwrap(image.cgImage), pixel = try XCTUnwrap(source.cropping(to: CGRect(x: source.width / 2, y: source.height - max(2, Int(image.scale * 4)), width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4); let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)); context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UIColor(red: CGFloat(bytes[0]) / 255, green: CGFloat(bytes[1]) / 255, blue: CGFloat(bytes[2]) / 255, alpha: 1)
    }
}
private struct AppearanceWritingFixture: View {
    @ObservedObject var appearance: NativeAppearanceStore
    @ObservedObject var session: NoteSession
    let actions: NativeEditorActions
    var body: some View {
        NativeTextEditor(markdown: session.document.parts.body, source: false, onChange: session.updateBody, onImage: { _ in }, onLink: { _ in }, actions: actions, documentID: "appearance|Palette.md")
            .environment(\.nativeThemes, appearance.palettes).preferredColorScheme(appearance.mode.colorScheme)
    }
}

private struct AppearanceSwatchesFixture: View {
    let appearance: NativeAppearanceStore
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(Accent.color)
                Rectangle().fill(Accent.link)
                Rectangle().fill(Accent.text)
                Rectangle().fill(Accent.editor)
                Rectangle().fill(Accent.paper)
                Rectangle().fill(Accent.sidebar)
                Rectangle().fill(Accent.sidebarText)
            }.frame(height: 50)
            Rectangle().fill(.tint).frame(height: 50)
        }.frame(width: 280, height: 100).ignoresSafeArea()
            .modifier(NativeAppearancePresentation(appearance: appearance))
    }
}

private struct AppearanceSheetFixture: View {
    let appearance: NativeAppearanceStore
    var body: some View {
        Color.clear.sheet(isPresented: .constant(true)) {
            Rectangle().fill(.tint).ignoresSafeArea()
        }.modifier(NativeAppearancePresentation(appearance: appearance))
    }
}
