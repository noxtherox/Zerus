import XCTest
import SwiftUI
import UIKit
import Vision
@testable import ZerusNative

final class NativeEditorPresentationTests: XCTestCase {
    @MainActor
    func testBulkSelectionLabelRemainsReadableAndGrowsAtPhoneWidthAcrossDynamicTypeSizes() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let store = VaultStore(), selection = NativeBulkSelection()
        let notes = ["First", "Second"].map { NoteDocument(path: $0 + ".md", content: "# " + $0, modified: .now) }
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene)), container = UIViewController()
        window.overrideUserInterfaceStyle = .light
        window.traitOverrides.preferredContentSizeCategory = .extraSmall
        let host = UIHostingController(rootView: List {
            NativeBulkControls(selection: selection, visible: notes)
        }.listStyle(.insetGrouped).environmentObject(store).tint(Accent.color))
        window.rootViewController = container; container.addChild(host); container.view.addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: 414, height: 896); host.didMove(toParent: container)
        window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }

        func inkHeight(_ image: CGImage, box: CGRect) throws -> CGFloat {
            let region = CGRect(x: box.minX - 2, y: CGFloat(image.height) - box.maxY - 4, width: box.width + 4, height: box.height + 8)
                .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let crop = try XCTUnwrap(image.cropping(to: region)), width = crop.width, height = crop.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            let rows = (0..<height).filter { y in
                (0..<width).contains { x in
                    let offset = (y * width + x) * 4
                    return bytes[offset + 3] > 128 && min(bytes[offset], min(bytes[offset + 1], bytes[offset + 2])) < 180
                }
            }
            let first = try XCTUnwrap(rows.first), last = try XCTUnwrap(rows.last)
            return CGFloat(last - first + 1)
        }

        func renderedLabels(_ required: [String]) throws -> (UIImage, [String: CGRect]) {
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size, format: format).image { _ in
                _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let pixels = try XCTUnwrap(image.cgImage)
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate; recognition.recognitionLanguages = ["en-US"]; recognition.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: pixels, options: [:]).perform([recognition])
            var words: [String: CGRect] = [:]
            for observation in recognition.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                for word in required {
                    guard let range = candidate.string.range(of: "\\b" + word + "\\b", options: [.regularExpression, .caseInsensitive]),
                          let bounds = try candidate.boundingBox(for: range)?.boundingBox else { continue }
                    var box = CGRect(x: bounds.minX * CGFloat(pixels.width), y: bounds.minY * CGFloat(pixels.height), width: bounds.width * CGFloat(pixels.width), height: bounds.height * CGFloat(pixels.height))
                    // OCR locates each word, but its approximate line boxes are
                    // too noisy to measure the small normal-size font change.
                    box.size.height = try inkHeight(pixels, box: box)
                    if box.height > (words[word]?.height ?? 0) { words[word] = box }
                }
            }
            return (image, words)
        }

        var heights: [Bool: [CGFloat]] = [:]
        var glyphHeights: [Bool: [[String: CGFloat]]] = [:]
        for (category, minimum) in [(UIContentSizeCategory.extraSmall, CGFloat(0)), (.large, CGFloat(1.05)), (.accessibilityExtraExtraExtraLarge, CGFloat(2))] {
            window.traitOverrides.preferredContentSizeCategory = category
            for selected in [false, true] {
                selection.active = selected
                if selected { selection.selectAll(notes) } else { selection.clear() }
                let required = selected ? ["select", "all", "clear", "selected"] : ["select", "notes"]
                let expectedMinimum = (heights[selected]?.last ?? 0) * minimum
                let deadline = ContinuousClock.now + .seconds(5)
                var latest: (UIImage, [String: CGRect])?
                repeat {
                    await Task.yield()
                    latest = try renderedLabels(required)
                    if let boxes = latest?.1, required.allSatisfy({ boxes[$0] != nil }),
                       let height = boxes.values.map(\.height).max(), height > expectedMinimum,
                       !selected || boxes["clear"]!.width > boxes["clear"]!.height * 2 { break }
                    try await Task.sleep(for: .milliseconds(50))
                } while ContinuousClock.now < deadline
                XCTAssertEqual(host.traitCollection.preferredContentSizeCategory, category)
                let captured = try XCTUnwrap(latest)
                record(captured.0, name: "Native bulk " + (selected ? "selected " : "inactive ") + category.rawValue)
                XCTAssertEqual(Set(captured.1.keys), Set(required), "Every essential bulk label must remain readable")
                if selected {
                    let clear = try XCTUnwrap(captured.1["clear"], "Clear must remain readable after selecting notes")
                    XCTAssertGreaterThan(clear.width, clear.height * 2, "The actual Clear word must not split across lines")
                }
                let sizes = captured.1.mapValues(\.height)
                glyphHeights[selected, default: []].append(sizes)
                heights[selected, default: []].append(try XCTUnwrap(sizes.values.max()))
            }
        }
        for values in heights.values {
            XCTAssertGreaterThan(values[1], values[0] * 1.05, "Normal text must grow from the small system size")
            XCTAssertGreaterThan(values[2], values[1] * 2, "The actual text raster must grow substantially at the maximum accessibility size")
        }
        for values in glyphHeights.values {
            for (word, small) in values[0] {
                XCTAssertGreaterThan(try XCTUnwrap(values[2][word]), small * 2, "Every essential label must grow at the maximum accessibility size: " + word)
            }
        }
    }

    @MainActor
    func testDocumentDetailsAtLargestTextSizeLeaveRoomToWriteWithoutReplacingTheEditor() async throws {
        let preferences = NativeVaultPreferencesBackup(); defer { preferences.restore() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "Product planning and customer research/Document.md"
        let header = "---\nzerus-id: details-viewport\nzerus-file-id: details-fixture\nzerus-file-name: Milestone preview.txt\nzerus-file-kind: vault\nzerus-file-path: assets/preview.txt\n---\n"
        let original = header + "# Writing\n\nAn independent paragraph."
        let io = VaultFiles(root: root)
        try await io.write(path, data: Data(original.utf8), expected: nil)
        try await io.write("assets/preview.txt", data: Data("Native document preview.".utf8), expected: nil)
        let store = VaultStore(); await store.open(root)
        let session = try XCTUnwrap(store.session(for: XCTUnwrap(store.notes.first)))
        let navigation = NativeNoteNavigation(vault: store, session: session)
        navigation.root.allowsInitialFocus = false
        defer { navigation.close(); session.deactivate() }
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene)), container = UIViewController()
        window.overrideUserInterfaceStyle = .light
        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        let host = UIHostingController(rootView: NativeNoteNavigationView(navigation: navigation).environmentObject(store))
        window.rootViewController = container; container.addChild(host); container.view.addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: 414, height: 896); host.didMove(toParent: container)
        window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        func editor(_ root: UIView) -> UITextView? {
            if let text = root as? UITextView, text.accessibilityIdentifier == "note.editor" { return text }
            return root.subviews.lazy.compactMap { editor($0) }.first
        }
        await waitUntil { editor(host.view)?.window != nil }
        let text = try XCTUnwrap(editor(host.view))
        await waitUntil { host.view.layoutIfNeeded(); return text.bounds.height > 20 && text.text.contains("independent") }
        XCTAssertEqual(text.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
        XCTAssertGreaterThan(text.bounds.height, host.view.bounds.height * 0.5, "Document details must leave useful writing space at the largest text size")
        record(UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }, name: "Document note at largest text size")

        window.traitOverrides.preferredContentSizeCategory = .large
        await waitUntil { text.traitCollection.preferredContentSizeCategory == .large }
        XCTAssertTrue(text.becomeFirstResponder())
        text.selectedRange = NSRange(location: text.attributedText.length, length: 0)
        text.insertText(" Checked")
        text.delegate?.textViewDidChange?(text)
        await session.save()
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data((original + " Checked").utf8))
        let selected = (text.text as NSString).range(of: "independent")
        text.selectedRange = selected
        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        await waitUntil { text.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge }
        XCTAssertTrue(editor(host.view) === text, "Changing the chrome must retain the existing UIKit editor")
        XCTAssertEqual(text.selectedRange, selected)
        XCTAssertTrue(try XCTUnwrap(text.undoManager).canUndo)
        text.undoManager?.undo()
        await session.save()
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(original.utf8))
        text.resignFirstResponder()
    }

    @MainActor
    func testReadOnlyPreviewKeepsTheSelectedTextWhenItsAppearanceChanges() async throws {
        let markdown = "# Revision\n\nBefore **bold** writing.\n\n```swift\nprint(42)\n```"
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        let host = UIHostingController(rootView: RevisionText(markdown: markdown, source: false, images: [:], open: { _ in }).preferredColorScheme(.light))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        func textView(_ root: UIView) -> UITextView? {
            if let view = root as? UITextView { return view }
            return root.subviews.compactMap(textView).first
        }
        await waitUntil { textView(host.view) != nil }
        let view = try XCTUnwrap(textView(host.view)), selected = (try XCTUnwrap(textView(host.view)?.text) as NSString).range(of: "bold")
        view.selectedRange = selected
        host.rootView = RevisionText(markdown: markdown, source: false, images: [:], open: { _ in }).preferredColorScheme(.dark)
        await waitUntil { view.traitCollection.userInterfaceStyle == .dark }
        XCTAssertEqual(view.traitCollection.userInterfaceStyle, .dark)
        XCTAssertTrue(textView(host.view) === view)
        XCTAssertFalse(view.isEditable)
        XCTAssertEqual(view.selectedRange, selected, "Changing appearance must not reset the read-only preview's selected text")
        XCTAssertEqual(view.text, "Revision\n\nBefore bold writing.\n\n\u{fffc}")
    }

    @MainActor
    func testLiveAppearanceTextSizeAndWidthRefreshPreserveFilesSelectionUndoAndMarkedWriting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = "---\nzerus-id: live-presentation\nforeign: keep\n---\n# Display 🧭\n\nBefore **bold** writing.\n\n- [ ] Keep the draft\n\n```swift\nlet plant = \"🪴\"\nprint(plant)\n```\n\n<!-- zerus-table-widths: 120,200 -->\n| Item | Owner |\n| --- | --- |\n| Native | Tiago |\n\nAfter."
        let file = root.appendingPathComponent("Display.md"); try Data(source.utf8).write(to: file)
        let session = NoteSession(note: .init(path: "Display.md", content: source, modified: .now), root: root, io: VaultFiles(root: root), onSave: { _ in })
        defer { session.deactivate() }
        let actions = NativeEditorActions()
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene)), container = UIViewController()
        window.overrideUserInterfaceStyle = .light; window.traitOverrides.preferredContentSizeCategory = .large
        let host = UIHostingController(rootView: PresentationEditor(session: session, actions: actions))
        window.rootViewController = container; container.addChild(host); container.view.addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700); host.didMove(toParent: container)
        window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        await waitUntil { actions.coordinator?.view?.window != nil }
        let view = try XCTUnwrap(actions.coordinator?.view)
        view.layoutIfNeeded(); XCTAssertTrue(view.becomeFirstResponder())
        let toggle = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Complete: Keep the draft" })
        toggle.sendActions(for: .touchUpInside)
        await session.save()
        let saved = source.replacingOccurrences(of: "- [ ] Keep", with: "- [x] Keep")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), saved)
        XCTAssertTrue(try XCTUnwrap(view.undoManager).canUndo)
        let selected = (view.text as NSString).range(of: "Before")
        view.selectedRange = selected
        let initialCodeHeight = try XCTUnwrap(code(view)).bounds.height
        let initialTableHeight = try XCTUnwrap(table(view)).bounds.height
        let initialCheckboxWidth = try XCTUnwrap(checklist(view)).bounds.width
        let initialFontSize = try XCTUnwrap(view.attributedText.attribute(.font, at: selected.location, effectiveRange: nil) as? UIFont).pointSize
        XCTAssertGreaterThan(try XCTUnwrap(brightness(code(view))), 0.8)
        XCTAssertGreaterThan(try XCTUnwrap(brightness(table(view))), 0.8)
        record(try XCTUnwrap(code(view)?.image), name: "Native code light default size")
        record(try XCTUnwrap(table(view)?.image), name: "Native table light default size")


        window.overrideUserInterfaceStyle = .dark
        await waitUntil { self.brightness(self.code(view)) ?? 1 < 0.3 && self.brightness(self.table(view)) ?? 1 < 0.3 }
        XCTAssertEqual(view.traitCollection.userInterfaceStyle, .dark, "The actual hosted editor must receive the changed UIKit trait")
        XCTAssertLessThan(try XCTUnwrap(brightness(code(view))), 0.3, "Code must follow the open editor's dark appearance")
        XCTAssertLessThan(try XCTUnwrap(brightness(table(view))), 0.3, "The table image must follow the same appearance")

        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        await waitUntil { (self.code(view)?.bounds.height ?? 0) > initialCodeHeight && (self.table(view)?.bounds.height ?? 0) > initialTableHeight }
        XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
        XCTAssertGreaterThan(try XCTUnwrap(code(view)).bounds.height, initialCodeHeight)
        XCTAssertGreaterThan(try XCTUnwrap(table(view)).bounds.height, initialTableHeight)
        XCTAssertGreaterThan(try XCTUnwrap(checklist(view)).bounds.width, initialCheckboxWidth)
        XCTAssertGreaterThan(try XCTUnwrap(view.attributedText.attribute(.font, at: selected.location, effectiveRange: nil) as? UIFont).pointSize, initialFontSize)
        var checkboxRange = NSRange(location: 0, length: 0)
        view.attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.attributedText.length)) { value, range, stop in
            if value is ChecklistAttachment { checkboxRange = range; stop.pointee = true }
        }
        view.scrollRangeToVisible(checkboxRange)
        await waitUntil { view.layoutIfNeeded(); return view.subviews.compactMap { $0 as? UIButton }.contains { $0.accessibilityLabel == "Mark incomplete: Keep the draft" && !$0.isHidden } }
        let largeTarget = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Mark incomplete: Keep the draft" && !$0.isHidden })
        XCTAssertGreaterThanOrEqual(largeTarget.frame.width, try XCTUnwrap(checklist(view)).bounds.width, "The tap target must cover the enlarged checkbox glyph")
        XCTAssertGreaterThanOrEqual(largeTarget.frame.height, try XCTUnwrap(checklist(view)).bounds.height)

        host.view.frame.size.width = 300; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        await waitUntil {
            view.layoutIfNeeded()
            return view.bounds.width <= 301 && (self.code(view)?.bounds.width ?? 1000) <= view.bounds.width - view.textContainerInset.left - view.textContainerInset.right + 1
        }
        XCTAssertLessThanOrEqual(view.bounds.width, 301, "The actual host must resize before checking its preview geometry")
        let available = view.bounds.width - view.textContainerInset.left - view.textContainerInset.right
        XCTAssertLessThanOrEqual(try XCTUnwrap(code(view)).bounds.width, available + 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(table(view)).bounds.width, available + 1)
        record(try XCTUnwrap(code(view)?.image), name: "Native code dark accessibility size narrow layout")
        record(try XCTUnwrap(table(view)?.image), name: "Native table dark accessibility size narrow layout")
        let tableImage = try XCTUnwrap(table(view)?.image?.cgImage)
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        recognition.recognitionLanguages = ["en-US"]
        recognition.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: tableImage, options: [:]).perform([recognition])
        let visible = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        let readable = visible.lowercased().filter { $0.isLetter || $0.isNumber }
        for fragment in ["1rows", "2columns", "taptoedit"] {
            XCTAssertTrue(readable.contains(fragment), "The table footer must remain readable at accessibility size and narrow width. Actual pixels: " + visible)
        }
        XCTAssertEqual(view.selectedRange, selected)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), saved)
        XCTAssertFalse(session.dirty, "Visual changes must not create a note edit")

        view.undoManager?.undo(); await session.save()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), source)
        await waitUntil { self.brightness(self.code(view)) ?? 1 < 0.3 }
        XCTAssertLessThan(try XCTUnwrap(brightness(code(view))), 0.3, "Undo must not restore an old light bitmap")
        XCTAssertGreaterThan(try XCTUnwrap(code(view)).bounds.height, initialCodeHeight)
        XCTAssertGreaterThan(try XCTUnwrap(view.attributedText.attribute(.font, at: selected.location, effectiveRange: nil) as? UIFont).pointSize, initialFontSize, "Undo must retain the editor's current text size")
        view.undoManager?.redo(); await session.save()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), saved)

        view.selectedRange = NSRange(location: selected.location, length: 0)
        view.setMarkedText("正在", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(view.markedTextRange)
        window.overrideUserInterfaceStyle = .light
        await Task.yield(); view.layoutIfNeeded()
        XCTAssertNotNil(view.markedTextRange, "A presentation refresh must not commit or discard active keyboard composition")
        XCTAssertTrue(view.text.contains("正在Before"))
        XCTAssertEqual(session.document.content, saved)
        actions.finishEditing()
        await waitUntil { self.brightness(self.code(view)) ?? 0 > 0.8 && self.brightness(self.table(view)) ?? 0 > 0.8 }
        await session.save()
        XCTAssertNil(view.markedTextRange)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), saved.replacingOccurrences(of: "Before", with: "正在Before"))
        XCTAssertGreaterThan(try XCTUnwrap(brightness(code(view))), 0.8)
        XCTAssertGreaterThan(try XCTUnwrap(brightness(table(view))), 0.8)
        let committed = try Data(contentsOf: file)
        host.rootView = PresentationEditor(session: session, actions: actions, source: true)
        await waitUntil { actions.coordinator?.source == true }
        XCTAssertEqual(view.text, session.document.parts.body)
        XCTAssertGreaterThan(try XCTUnwrap(view.font).pointSize, initialFontSize, "Source mode must start with the editor's current accessibility text size")
        window.traitOverrides.preferredContentSizeCategory = .large
        await waitUntil { (view.font?.pointSize ?? 100) <= initialFontSize + 1 }
        XCTAssertEqual(try XCTUnwrap(view.font).pointSize, initialFontSize, accuracy: 1)
        XCTAssertEqual(try Data(contentsOf: file), committed)
    }

    @MainActor
    func testRepeatedNativeEditsKeepDistantFormattingParagraphBoundariesAndCommittedComposition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let header = "---\nzerus-id: repeated-writing\nforeign: keep\n---\n"
        let middle = String(repeating: "Distant **bold** with `code` and [[zerus:other|Other]].\n\n", count: 180)
        let body = "# Writing\n\nFirst 😀 line.\nSecond line.\n\n" + middle + "Last café line."
        let file = root.appendingPathComponent("Writing.md")
        try Data((header + body).utf8).write(to: file)
        let session = NoteSession(note: .init(path: "Writing.md", content: header + body, modified: .now), root: root, io: VaultFiles(root: root), onSave: { _ in })
        defer { session.deactivate() }
        let editor = NativeTextEditor(markdown: body, source: false, onChange: session.updateBody, onImage: { _ in }, onLink: { _ in })
        let owner = editor.makeCoordinator(), view = ZerusTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), textContainer: nil)
        owner.view = view; view.delegate = owner; owner.load(body, source: false)
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene)), controller = UIViewController()
        window.rootViewController = controller; controller.view.addSubview(view); window.makeKeyAndVisible()
        defer { view.resignFirstResponder(); window.isHidden = true; previous?.makeKeyAndVisible() }
        XCTAssertTrue(view.becomeFirstResponder()); XCTAssertNotNil(view.textLayoutManager)
        view.selectedRange = NSRange(location: (view.text as NSString).range(of: "First").location, length: 0)
        view.typingAttributes = [.font: MarkdownText.font(), .foregroundColor: UIColor.label, .zerusBlock: ""]
        let started = ContinuousClock.now
        let burst = String(repeating: "typing ", count: 24)
        for character in burst { view.insertText(String(character)) }
        print("REPEATED_WRITING_BURST_SECONDS=\(started.duration(to: .now))")
        var expected = body.replacingOccurrences(of: "First", with: burst + "First")
        XCTAssertEqual(session.document.content, header + expected)
        await session.save(); XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), header + expected)

        // Deleting the boundary joins two formerly separate serialized lines.
        let boundary = (view.text as NSString).range(of: "line.\nSecond")
        view.selectedRange = NSRange(location: boundary.location + 5, length: 1); view.insertText("")
        expected = expected.replacingOccurrences(of: "line.\nSecond", with: "line.Second")
        XCTAssertEqual(session.document.parts.body, expected)
        view.selectedRange = NSRange(location: (view.text as NSString).range(of: "Last").location, length: 0)
        view.insertText("尾 🧭 ")
        expected = expected.replacingOccurrences(of: "Last", with: "尾 🧭 Last")
        XCTAssertEqual(session.document.parts.body, expected)

        // Attribute-only and batched edits may occur without the text-view
        // replacement delegate, as with Writing Tools or accessibility actions.
        let first = (view.text as NSString).range(of: "First")
        view.textStorage.addAttribute(.font, value: MarkdownText.font(traits: .traitItalic), range: first)
        owner.textViewDidChange(view)
        expected = expected.replacingOccurrences(of: "First", with: "*First*")
        XCTAssertEqual(session.document.parts.body, expected)
        view.textStorage.beginEditing()
        view.textStorage.replaceCharacters(in: (view.text as NSString).range(of: "café"), with: "café ☕️")
        view.textStorage.replaceCharacters(in: (view.text as NSString).range(of: "Second"), with: "Deuxième")
        view.textStorage.endEditing(); owner.textViewDidChange(view)
        expected = expected.replacingOccurrences(of: "café", with: "café ☕️").replacingOccurrences(of: "Second", with: "Deuxième")
        XCTAssertEqual(session.document.parts.body, expected)

        view.selectedRange = NSRange(location: view.attributedText.length, length: 0)
        view.typingAttributes = [.font: MarkdownText.font(), .foregroundColor: UIColor.label, .zerusBlock: ""]
        view.setMarkedText("正在", selectedRange: NSRange(location: 2, length: 0))
        view.setMarkedText("正在写", selectedRange: NSRange(location: 3, length: 0))
        XCTAssertNotNil(view.markedTextRange); XCTAssertEqual(session.document.parts.body, expected)
        view.unmarkText(); owner.textViewDidChange(view)
        expected += "正在写"
        await session.save(); XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), header + expected)
        XCTAssertNotNil(view.textLayoutManager, "Writing must continue using TextKit 2")
        owner.load(expected, source: false)
        view.selectedRange = NSRange(location: view.attributedText.length, length: 0); view.insertText("!")
        await session.save(); XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), header + expected + "!")
        owner.load(expected, source: true)
        view.selectedRange = NSRange(location: view.attributedText.length, length: 0); view.insertText(" source")
        await session.save(); XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), header + expected + " source")
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(30)) }
    }
    @MainActor private func record(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func attachment<T: NSTextAttachment>(_ view: UITextView, _ type: T.Type) -> T? {
        var result: T?
        view.attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.attributedText.length)) { value, _, stop in
            if let value = value as? T { result = value; stop.pointee = true }
        }
        return result
    }
    @MainActor private func code(_ view: UITextView) -> CodeAttachment? { attachment(view, CodeAttachment.self) }
    @MainActor private func table(_ view: UITextView) -> TableAttachment? { attachment(view, TableAttachment.self) }
    @MainActor private func checklist(_ view: UITextView) -> ChecklistAttachment? { attachment(view, ChecklistAttachment.self) }
    @MainActor private func brightness(_ attachment: NSTextAttachment?) -> Double? {
        guard let image = attachment?.image, let source = image.cgImage,
              let pixel = source.cropping(to: CGRect(x: source.width / 2, y: source.height - Int(image.scale * 5), width: 1, height: 1)) else { return nil }
        var bytes: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard bytes[3] > 240 else { return nil }
        return Double(Int(bytes[0]) + Int(bytes[1]) + Int(bytes[2])) / 765
    }
}

private struct PresentationEditor: View {
    @ObservedObject var session: NoteSession
    let actions: NativeEditorActions
    var source = false
    var body: some View {
        NativeTextEditor(markdown: session.document.parts.body, source: source, onChange: session.updateBody,
            onImage: { _ in }, onLink: { _ in }, actions: actions, documentID: "presentation|Display.md")
    }
}
