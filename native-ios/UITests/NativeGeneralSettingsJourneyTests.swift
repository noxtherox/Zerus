import XCTest

final class NativeGeneralSettingsJourneyTests: NativeJourneyTestCase {
    @MainActor
    func testDefaultFoldersStayWithEachVaultAndDateDisplayChangesWithoutRewritingProperties() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        func tap(_ element: XCUIElement) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription); element.tap()
        }
        func fill(_ field: XCUIElement, _ value: String) { tap(field); field.typeKey("a", modifierFlags: .command); field.typeText(value) }
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { tap(app.buttons["vault.create"]) }
        let suffix = String(UUID().uuidString.prefix(6)), a = "Defaults A " + suffix, b = "Defaults B " + suffix
        let title = "Default folder evidence " + suffix, other = "Other vault evidence " + suffix
        let folder = "Projects/Ideas " + suffix
        func vaults() { openNativeLibrary(app); tap(app.buttons["library.vaults"]) }
        func createVault(_ name: String) {
            let create = app.buttons["vaults.create"]
            for _ in 0..<6 {
                if create.isHittable { break }
                app.swipeUp()
            }
            tap(create)
            let alert = app.alerts["New vault on this iPhone"], nameField = alert.textFields["Vault name"]
            tap(nameField); nameField.typeText(name); tap(alert.buttons["Create"])
            XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        }
        func general() { openNativeNotes(app); tap(app.buttons["Settings"]); tap(app.buttons["settings.general"]) }
        func closeSettings() { tap(app.navigationBars["General"].buttons["BackButton"]); tap(app.buttons["Done"]) }
        func create(_ title: String, expected: String) {
            tap(app.buttons["navigation.newNote"])
            XCTAssertTrue(app.buttons["note.folder"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["note.folder"].label.contains(expected), app.buttons["note.folder"].debugDescription)
            fill(app.textFields["note.title"], title); tap(app.buttons["note.create"])
            XCTAssertTrue(app.textViews["note.editor"].waitForExistence(timeout: 10))
        }
        vaults(); createVault(a); general()
        tap(app.buttons["settings.defaultFolder"])
        fill(app.textFields["settings.folder.path"], "../Outside"); tap(app.buttons["settings.folder.use"])
        XCTAssertTrue(app.staticTexts["settings.folder.error"].waitForExistence(timeout: 5))
        fill(app.textFields["settings.folder.path"], folder); tap(app.buttons["settings.folder.use"])
        XCTAssertTrue(app.buttons["settings.defaultFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.defaultFolder"].label.contains(folder))
        tap(app.buttons["settings.dateFormat"]); tap(app.buttons["YYYY-MM-DD"])
        XCTAssertTrue(app.staticTexts["settings.dateExample"].label.hasSuffix("2026-12-31"))
        closeSettings(); app.terminate(); app.launch()
        create(title, expected: folder)
        if app.buttons["Dismiss keyboard"].exists { tap(app.buttons["Dismiss keyboard"]) }
        tap(app.buttons["Note information"]); tap(app.buttons["property.add"])
        fill(app.textFields["property.name"], "Review day"); tap(app.buttons["property.type"]); tap(app.buttons["Date"]); tap(app.buttons["property.save"])
        let property = app.buttons["property.review day"]
        XCTAssertTrue(property.waitForExistence(timeout: 5), app.debugDescription)
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: Date()); XCTAssertTrue(property.label.contains(day), property.label)
        tap(app.buttons["note.info.done"]); tap(app.buttons["Close note"])
        vaults(); createVault(b); general()
        XCTAssertTrue(app.buttons["settings.defaultFolder"].label.contains("Inbox"))
        XCTAssertTrue(app.staticTexts["settings.dateExample"].label.hasSuffix("2026-12-31"), "The date preference applies across vaults on this device")
        closeSettings(); create(other, expected: "Inbox")
        if app.buttons["Dismiss keyboard"].exists { tap(app.buttons["Dismiss keyboard"]) }
        tap(app.buttons["Close note"]); vaults()
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "vault.saved.", a)).firstMatch)
        general(); XCTAssertTrue(app.buttons["settings.defaultFolder"].label.contains(folder))
        tap(app.buttons["settings.dateFormat"]); tap(app.buttons["DD.MM.YYYY"])
        XCTAssertTrue(app.staticTexts["settings.dateExample"].label.hasSuffix("31.12.2026"))
        closeSettings(); app.terminate(); app.launch()
        let result = app.buttons.containing(.staticText, identifier: title).firstMatch
        tap(result); tap(app.buttons["Note information"])
        formatter.dateFormat = "dd.MM.yyyy"
        XCTAssertTrue(property.waitForExistence(timeout: 5)); XCTAssertTrue(property.label.contains(formatter.string(from: Date())), property.label)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Native date preference changes displayed property with its original calendar value"; attachment.lifetime = .keepAlways; add(attachment)
        tap(app.buttons["note.info.done"]); tap(app.buttons["Close note"])
        general(); tap(app.buttons["settings.dateFormat"]); tap(app.buttons["DD/MM/YYYY"]); closeSettings()
    }
}
