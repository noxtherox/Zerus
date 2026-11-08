import XCTest
import Vision

final class NativeSessionJourneyTests: NativeJourneyTestCase {
    @MainActor
    func testOpenNoteForwardBranchAndReadingPositionRestoreUntilExplicitClose() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let suffix = String(UUID().uuidString.prefix(6)), target = "Resume target " + suffix, source = "Resume source " + suffix
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
        func go(_ direction: String) {
            app.buttons["Note actions"].tap(); app.buttons["note.navigation"].tap(); app.buttons["note.navigation." + direction].tap()
        }
        func attach(_ name: String) { let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item) }
        create(target, "\n\n" + String(repeating: "A paragraph before the reading position.\n\n", count: 22) + "## Resume section\n[Resume marker](https://example.invalid/resume)\n\nKeep this ending.\n")
        create(source, "\n\n[[" + target + "#resume-section|Continue reading]]\n")
        open(source); XCTAssertTrue(app.links["Continue reading"].waitForExistence(timeout: 5)); app.links["Continue reading"].tap()
        XCTAssertTrue(app.navigationBars[target].waitForExistence(timeout: 10)); XCTAssertTrue(app.links["Resume marker"].isHittable)
        go("back"); XCTAssertTrue(app.navigationBars[source].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars[source].waitForExistence(timeout: 15), "The open source note and its forward branch must survive process relaunch")
        XCTAssertEqual(app.keyboards.count, 0); go("forward")
        XCTAssertTrue(app.navigationBars[target].waitForExistence(timeout: 10)); XCTAssertTrue(app.links["Resume marker"].isHittable)
        attach("Restored forward visit returns to the deep reading position")
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        app.buttons["Note actions"].tap(); app.buttons["note.outline"].tap(); app.buttons["note.heading.resume-section"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars[target].waitForExistence(timeout: 15)); XCTAssertEqual(app.keyboards.count, 0)
        XCTAssertTrue((editor.value as? String ?? "").contains("## Resume section"), "The explicit source-mode choice must survive relaunch")
        let screenshot = app.screenshot(), recognition = VNRecognizeTextRequest(); recognition.recognitionLevel = .accurate; recognition.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(screenshot.image.cgImage), options: [:]).perform([recognition])
        let visible = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        XCTAssertTrue(visible.lowercased().contains("resume section"), "The restored source heading must be in screenshot pixels: " + visible)
        attach("Process relaunch restores the source mode and visible reading position")
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        app.buttons["Close note"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 15)); XCTAssertFalse(editor.exists, "Explicitly closing a note must keep it closed on the next launch")
    }
}
