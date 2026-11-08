import XCTest
import UIKit

final class NativeHTMLClipboardJourneyTests: NativeJourneyTestCase {
    @MainActor
    func testHTMLPasteRejectsFailedImagesCancelsOnCloseAndKeepsNativeBlocksAndOriginalImagesAfterRelaunch() async throws {
        UIPasteboard.general.items = []
        let endpoint = ProcessInfo.processInfo.environment["ZERUS_NATIVE_CLIPBOARD_FIXTURE_ENDPOINT"] ?? "https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/native-clipboard-qa"
        var request = URLRequest(url: try XCTUnwrap(URL(string: endpoint + "/health"))); request.timeoutInterval = 5
        var fixtureImage: Data?
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let info = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            fixtureImage = (info?["imageBase64"] as? String).flatMap { Data(base64Encoded: $0) }
            guard (response as? HTTPURLResponse)?.statusCode == 200, info?["zerusNativeClipboardFixture"] as? Bool == true else { throw XCTSkip("Start the private clipboard image fixture before this integration journey.") }
        } catch { throw XCTSkip("Native clipboard fixture unavailable: " + error.localizedDescription) }
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let title = "HTML clipboard " + String(UUID().uuidString.prefix(6))
        func tap(_ element: XCUIElement) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription); element.tap()
        }
        func publish(_ html: String, plain: String, rtfd: Data? = nil) {
            var item: [String: Any] = ["public.html": Data(html.utf8), "public.utf8-plain-text": plain]
            if let rtfd { item["com.apple.flat-rtfd"] = rtfd }
            UIPasteboard.general.setItems([item], options: [.localOnly: true])
        }
        func paste() {
            tap(app.buttons["Note actions"]); tap(app.buttons["Clipboard"]); tap(app.buttons["Paste"]); tap(app.buttons["clipboard.paste"])
            let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            XCTAssertFalse(system.buttons["Allow Paste"].exists, "The system Paste button must use its granted item providers")
        }
        func reopen() {
            let search = app.searchFields.firstMatch
            if !search.exists { app.swipeDown() }
            tap(search); search.typeText(title)
            tap(app.buttons.containing(.staticText, identifier: title).firstMatch)
            XCTAssertTrue(app.textViews["note.editor"].waitForExistence(timeout: 10))
        }
        tap(app.buttons["navigation.newNote"])
        let field = app.textFields["note.title"]; tap(field); field.typeText(title); tap(app.buttons["note.create"])
        let editor = app.textViews["note.editor"]; XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.typeText("Keep original writing.\n\n")
        tap(app.buttons["Dismiss keyboard"])
        for route in ["missing.png", "large.png"] {
            publish("<p>Rejected HTML must stay absent.</p><img src=\"" + endpoint + "/" + route + "\" alt=\"Unavailable\">", plain: "Rejected HTML must stay absent.")
            paste(); XCTAssertTrue(app.alerts["Clipboard"].waitForExistence(timeout: 15), app.debugDescription)
            tap(app.alerts["Clipboard"].buttons["OK"])
            XCTAssertFalse((editor.value as? String ?? "").contains("Rejected HTML"))
            XCTAssertTrue((editor.value as? String ?? "").contains("Keep original writing."))
            if app.buttons["Dismiss keyboard"].exists { tap(app.buttons["Dismiss keyboard"]) }
        }
        publish("<p>Cancelled HTML must stay absent.</p><img src=\"" + endpoint + "/slow.png\" alt=\"Slow\">", plain: "Cancelled HTML must stay absent.")
        paste(); XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Preparing clipboard")).firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        tap(app.buttons["Close note"]); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 10)); reopen()
        XCTAssertFalse((editor.value as? String ?? "").contains("Cancelled HTML"))
        let heading = "Native HTML " + title
        let html = """
        <h2>\(heading)</h2><p>A <strong>bold</strong> passage with <a href="https://example.com/native">a link</a>.</p>
        <ul><li>First <em>item</em></li><li>Second item</li></ul>
        <table><caption>Formatted table</caption><tr><th>Name</th><th>Value</th></tr><tr><td><strong>Rich cell</strong></td><td>42</td></tr></table>
        <p><img src="\(endpoint)/redirect.png" alt="Original web image"></p>
        <p><img src="\(endpoint)/redirect.png" alt="Same original bytes"></p>
        <p><img src="file:///private/clipboard/Original.png" alt="Provided local image"></p>
        """
        let attachment = NSTextAttachment(data: try XCTUnwrap(fixtureImage), ofType: "public.png")
        attachment.image = UIImage(data: try XCTUnwrap(fixtureImage)); attachment.fileWrapper = FileWrapper(regularFileWithContents: try XCTUnwrap(fixtureImage)); attachment.fileWrapper?.preferredFilename = "Original.png"
        let rtfd = try NSAttributedString(attachment: attachment).data(from: NSRange(location: 0, length: 1), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        publish(html, plain: "Wrong plain table\tValue\nPlain\t0", rtfd: rtfd)
        paste()
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", heading), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 40), .completed, app.debugDescription)
        XCTAssertTrue(app.buttons["Edit table"].waitForExistence(timeout: 10)); XCTAssertFalse(app.alerts["Clipboard"].exists)
        XCTAssertFalse(app.staticTexts["Source editing preserves this note’s advanced Markdown."].exists)
        tap(app.buttons["Undo"]); XCTAssertFalse((editor.value as? String ?? "").contains(heading)); XCTAssertFalse(app.buttons["Edit table"].exists)
        tap(app.buttons["Redo"]); XCTAssertTrue(app.buttons["Edit table"].waitForExistence(timeout: 10))
        if app.buttons["Dismiss keyboard"].exists { tap(app.buttons["Dismiss keyboard"]) }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "HTML paste stays in the native rich editor"; shot.lifetime = .keepAlways; add(shot)
        tap(app.buttons["Note actions"]); tap(app.buttons["Markdown source"])
        let saved = editor.value as? String ?? ""
        XCTAssertTrue(saved.contains("## " + heading)); XCTAssertTrue(saved.contains("**bold**")); XCTAssertTrue(saved.contains("[a link](https://example.com/native)"))
        XCTAssertTrue(saved.contains("- First *item*")); XCTAssertTrue(saved.contains("| **Rich cell** | 42 |")); XCTAssertTrue(saved.contains("assets/"))
        XCTAssertFalse(saved.contains("redirect.png")); XCTAssertFalse(saved.contains("Rejected HTML")); XCTAssertFalse(saved.contains("Cancelled HTML")); XCTAssertFalse(saved.contains("Wrong plain table")); XCTAssertFalse(saved.contains("\u{fffc}"))
        tap(app.buttons["Close note"]); app.terminate(); app.launch(); reopen()
        XCTAssertTrue(app.buttons["Edit table"].waitForExistence(timeout: 10)); XCTAssertTrue((editor.value as? String ?? "").contains(heading))
        XCTAssertFalse(app.staticTexts["Source editing preserves this note’s advanced Markdown."].exists)
        tap(app.buttons["Close note"])
        UIPasteboard.general.items = []
    }
}
