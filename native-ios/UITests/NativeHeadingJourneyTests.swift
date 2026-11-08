import XCTest
import Vision

final class NativeHeadingJourneyTests: NativeJourneyTestCase {
    @MainActor
    func testHeadingLinksOutlineSourceAndVisitHistoryKeepTheSavedNotes() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let suffix = String(UUID().uuidString.prefix(6)), target = "Heading target " + suffix, source = "Heading source " + suffix
        let editor = app.textViews["note.editor"]
        func create(_ title: String, _ body: String) {
            XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
            let field = app.textFields["note.title"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title); app.buttons["note.create"].tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 5)); app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
            editor.tap(); editor.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command); editor.typeText(body)
            app.buttons["Dismiss keyboard"].tap(); app.buttons["Close note"].tap()
        }
        func open(_ title: String) {
            XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 10))
            let search = app.searchFields.firstMatch; if !search.exists { app.swipeDown() }
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeKey("a", modifierFlags: .command); search.typeText(title)
            let result = app.buttons.containing(.staticText, identifier: title).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap(); XCTAssertTrue(editor.waitForExistence(timeout: 5))
        }
        func outline(_ slug: String) {
            app.buttons["Note actions"].tap(); XCTAssertTrue(app.buttons["note.outline"].waitForExistence(timeout: 5)); app.buttons["note.outline"].tap()
            let heading = app.buttons["note.heading." + slug]; XCTAssertTrue(heading.waitForExistence(timeout: 5)); heading.tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["On this note"])
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
        }
        @discardableResult func attach(_ name: String) -> XCUIScreenshot { let screenshot = app.screenshot(); let item = XCTAttachment(screenshot: screenshot); item.name = name; item.lifetime = .keepAlways; add(item); return screenshot }
        let body = "\n\n## First section\n[First marker](https://example.invalid/first)\n\n" + String(repeating: "A paragraph separating the two sections.\n\n", count: 18) + "## Deep section\n[Deep marker](https://example.invalid/deep)\n\nKeep all these source bytes.\n"
        create(target, body); create(source, "\n\n[[" + target + "#deep-section|Jump to deep]]\n")
        open(source); let link = app.links["Jump to deep"]; XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(app.navigationBars[target].waitForExistence(timeout: 10))
        let deep = app.links["Deep marker"], first = app.links["First marker"]
        attach("Cross-note heading location before visibility assertion")
        let revealed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: deep)
        XCTAssertEqual(XCTWaiter.wait(for: [revealed], timeout: 10), .completed); XCTAssertEqual(app.keyboards.count, 0)
        attach("Cross-note heading link reveals the deep section without a keyboard")
        outline("first-section"); XCTAssertTrue(first.isHittable); attach("Native outline returns to the first section")
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap(); outline("deep-section")
        let sourceScreenshot = attach("Native outline reveals the exact heading in Markdown source")
        let recognition = VNRecognizeTextRequest(); recognition.recognitionLevel = .accurate; recognition.recognitionLanguages = ["en-US"]; recognition.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(sourceScreenshot.image.cgImage), options: [:]).perform([recognition])
        let visibleText = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        XCTAssertTrue(visibleText.lowercased().contains("deep section"), "The source heading must appear in actual screenshot pixels. OCR: " + visibleText)
        XCTAssertTrue((editor.value as? String ?? "").contains("## Deep section"))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        app.buttons["Note actions"].tap(); app.buttons["note.navigation"].tap(); app.buttons["note.navigation.back"].tap()
        XCTAssertTrue(app.navigationBars[source].waitForExistence(timeout: 10))
        app.buttons["Note actions"].tap(); app.buttons["note.navigation"].tap(); app.buttons["note.navigation.forward"].tap()
        XCTAssertTrue(app.navigationBars[target].waitForExistence(timeout: 10)); XCTAssertTrue(deep.isHittable)
        app.buttons["Close note"].tap(); app.terminate(); app.launch(); open(target)
        XCTAssertTrue((editor.value as? String ?? "").contains("Keep all these source bytes.")); app.buttons["Close note"].tap()
    }
}
