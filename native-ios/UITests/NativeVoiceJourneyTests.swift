import XCTest

final class NativeVoiceJourneyTests: XCTestCase {
    @MainActor
    func testDeniedDictationPreservesEditablePromptAcrossRelaunchWithoutSending() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        func tap(_ element: XCUIElement) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription); element.tap()
        }
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { tap(app.buttons["vault.create"]) }
        tap(app.buttons["navigation.ask"])
        XCTAssertFalse(app.staticTexts["agent.issue"].exists, app.debugDescription)
        tap(app.buttons["Settings"]); tap(app.buttons["New conversation"])
        let field = app.descendants(matching: .any).matching(identifier: "chat.prompt").firstMatch
        let prompt = "Keep my unsent voice prompt " + String(UUID().uuidString.prefix(6))
        tap(field); field.typeKey("a", modifierFlags: .command); field.typeText(prompt)
        tap(app.buttons["chat.keyboard.dismiss"]); tap(app.buttons["voice.start"])
        // Refuse the genuine system request; never grant speech/microphone
        // access or capture the host microphone in this interaction journey.
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(20)
        while !app.staticTexts["voice.error"].exists, Date() < deadline {
            let deny = system.alerts.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Don’t Allow", "Don't Allow")).firstMatch
            if deny.waitForExistence(timeout: 1) { deny.tap() }
        }
        XCTAssertTrue(app.staticTexts["voice.error"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["voice.error"].label.contains("permission"), app.staticTexts["voice.error"].label)
        XCTAssertEqual(field.value as? String, prompt)
        XCTAssertFalse(app.staticTexts["YOU"].exists); XCTAssertFalse(app.buttons["Stop generating"].exists)
        XCTAssertTrue(app.buttons["voice.start"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Native dictation denial preserves the unsent prompt"; attachment.lifetime = .keepAlways; add(attachment)
        tap(app.buttons["voice.error.dismiss"]); tap(field); field.typeKey("a", modifierFlags: .command); field.typeText(prompt + " Still editable."); tap(app.buttons["chat.keyboard.dismiss"])
        app.terminate(); app.launch(); tap(app.buttons["navigation.ask"])
        XCTAssertEqual(field.value as? String, prompt + " Still editable.")
        XCTAssertFalse(app.staticTexts["YOU"].exists); XCTAssertTrue(app.buttons["voice.start"].exists)
    }
}
