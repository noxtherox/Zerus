import XCTest

final class NativeNoteLinkJourneyTests: NativeJourneyTestCase {
    @MainActor
    func testCaretPickerTypingShortcutsKeyboardUndoPreferenceAndRelaunchKeepPortableLinks() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        func tap(_ element: XCUIElement) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription); element.tap()
        }
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { tap(app.buttons["vault.create"]) }
        func general() {
            openNativeNotes(app)
            let closeSearch = app.navigationBars["Notes"].buttons["Close"]
            if closeSearch.exists { tap(closeSearch) }
            tap(app.buttons["Settings"]); tap(app.buttons["settings.general"])
        }
        func closeSettings() { tap(app.navigationBars["General"].buttons["BackButton"]); tap(app.buttons["Done"]) }
        general()
        let toggle = app.switches["settings.noteLinkShortcuts"]
        if toggle.value as? String == "0" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        closeSettings()
        let suffix = String(UUID().uuidString.prefix(6)), alpha = "Alpha fixture " + suffix, beta = "Beta fixture " + suffix, title = "Link writing " + suffix
        let editor = app.textViews["note.editor"]
        func create(_ title: String, body: String) {
            tap(app.buttons["navigation.newNote"]); tap(app.textFields["note.title"]); app.textFields["note.title"].typeText(title); tap(app.buttons["note.create"])
            XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.typeText(body)
        }
        func close() { if app.buttons["Dismiss keyboard"].exists { tap(app.buttons["Dismiss keyboard"]) }; tap(app.buttons["Close note"]) }
        func source() -> String {
            tap(app.buttons["Note actions"]); tap(app.buttons["Markdown source"])
            return editor.value as? String ?? ""
        }
        func rich() { tap(app.buttons["Note actions"]); tap(app.buttons["Markdown source"]) }
        func end() {
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            editor.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.9)).tap()
            editor.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
        }
        func option(_ title: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "note.links.option.", title)).firstMatch }
        func picker(_ title: String) {
            tap(app.buttons["Note actions"]); tap(app.buttons["Insert note link"])
            let search = app.textFields["note.picker.search"]; tap(search); search.typeText(title)
            tap(app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch)
        }
        create(alpha, body: "Alpha body stays."); close()
        create(beta, body: "Beta body stays."); close()
        create(title, body: "Before bold plain after.")
        end()
        editor.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: [.command, .shift])
        let selected = XCTAttachment(screenshot: app.screenshot()); selected.name = "Cross-paragraph selection before native link validation"; selected.lifetime = .keepAlways; add(selected)
        tap(app.buttons["Note actions"]); tap(app.buttons["Insert note link"])
        let invalidSelection = app.alerts["Note link"]
        XCTAssertTrue(invalidSelection.waitForExistence(timeout: 5), app.debugDescription)
        tap(invalidSelection.buttons["OK"])
        end()
        for _ in 0..<13 { editor.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: []) }
        for _ in 0..<4 { editor.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: .shift) }
        tap(app.buttons["Bold"])
        editor.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
        for _ in 0..<7 { editor.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: []) }
        for _ in 0..<10 { editor.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: .shift) }
        picker(alpha)
        let manual = source()
        XCTAssertTrue(manual.contains("Before [**bold** plain](#zerus-note:zerus%3A"), manual)
        XCTAssertTrue(manual.contains("%7Cbold%20plain) after."), manual)
        rich(); end(); editor.typeText("\n\nTouch @" + alpha)
        tap(option(alpha))
        XCTAssertTrue((editor.value as? String ?? "").contains("Touch " + alpha))
        tap(app.buttons["Undo"])
        XCTAssertTrue((editor.value as? String ?? "").contains("Touch @" + alpha), editor.value as? String ?? "")
        tap(app.buttons["Redo"])
        XCTAssertTrue((editor.value as? String ?? "").contains("Touch " + alpha))
        end(); editor.typeText("\n\nKeys [[fixture " + suffix)
        XCTAssertTrue(option(beta).waitForExistence(timeout: 10))
        let keyboardScreenshot = XCTAttachment(screenshot: app.screenshot()); keyboardScreenshot.name = "Native link suggestions before hardware keyboard selection"; keyboardScreenshot.lifetime = .keepAlways; add(keyboardScreenshot)
        editor.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(option(beta).isSelected, "Down Arrow must highlight the next suggested note")
        tap(app.keyboards.buttons["Return"])
        XCTAssertTrue((editor.value as? String ?? "").contains("Keys " + beta), editor.value as? String ?? "")
        let linked = source()
        XCTAssertTrue(linked.contains("Touch [[zerus:")); XCTAssertTrue(linked.contains("|" + alpha + "]]"))
        XCTAssertTrue(linked.contains("Keys [[zerus:")); XCTAssertTrue(linked.contains("|" + beta + "]]"))
        XCTAssertTrue(linked.contains("Before [**bold** plain](#zerus-note:"), linked)
        rich(); close(); general(); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); XCTAssertEqual(toggle.value as? String, "0"); closeSettings()
        app.terminate(); app.launch()
        let search = app.searchFields.firstMatch; tap(search); search.typeText(title)
        tap(app.buttons.containing(.staticText, identifier: title).firstMatch)
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); end(); editor.typeText("\n\nLiteral @Alpha")
        XCTAssertFalse(option(alpha).waitForExistence(timeout: 2), "Disabled shortcuts must leave typed text alone")
        picker(beta)
        let disabled = source()
        XCTAssertTrue(disabled.contains("Literal @Alpha[[zerus:"), disabled)
        XCTAssertTrue(disabled.contains("|" + beta + "]]"))
        XCTAssertTrue(disabled.contains("Before [**bold** plain](#zerus-note:"), disabled)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Caret insertion and typed native links remain portable while shortcuts can be disabled"; attachment.lifetime = .keepAlways; add(attachment)
        rich(); close(); general(); XCTAssertEqual(toggle.value as? String, "0"); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); closeSettings()
        app.terminate(); app.launch()
        let reopened = app.searchFields.firstMatch; tap(reopened); reopened.typeText(title)
        tap(app.buttons.containing(.staticText, identifier: title).firstMatch)
        let saved = source()
        XCTAssertEqual(saved, disabled, "Reopening must preserve both literal shortcuts and all three chosen link targets")
        rich(); close()
    }
}
