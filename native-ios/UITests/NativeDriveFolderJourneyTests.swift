import XCTest

final class NativeDriveFolderJourneyTests: XCTestCase {
    @MainActor
    func testUnconfiguredDriveExplainsSetupAndReturnsToAnUnmappedLocationAcrossRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let name = "Drive location " + String(UUID().uuidString.prefix(6))
        func reveal(_ element: XCUIElement) {
            if !element.waitForExistence(timeout: 2) {
                for _ in 0..<12 { app.swipeUp(); if element.waitForExistence(timeout: 1) { break } }
            }
        }
        func tap(_ element: XCUIElement) {
            reveal(element)
            XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription); XCTAssertTrue(element.isEnabled); element.tap()
        }
        func locations() {
            tap(app.buttons["Settings"]); tap(app.buttons["File locations"])
            reveal(app.buttons["filelocation.add"])
            XCTAssertTrue(app.buttons["filelocation.add"].waitForExistence(timeout: 10))
        }
        func inspectSetup() {
            XCTAssertTrue(app.staticTexts["drive.setup"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["drive.connect"].exists); XCTAssertFalse(app.buttons["drive.connect"].isEnabled)
            XCTAssertFalse(app.buttons["drive.choose"].exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Native Drive setup explains the missing developer client without changing folder access"; screenshot.lifetime = .keepAlways; add(screenshot)
            tap(app.buttons["drive.done"])
        }
        locations(); tap(app.buttons["filelocation.add"])
        let field = app.alerts.textFields.firstMatch; tap(field); field.typeText(name); tap(app.alerts.buttons["Save"])
        let label = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", name)).firstMatch
        reveal(label); XCTAssertTrue(label.waitForExistence(timeout: 10))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "filelocation.drive.")).matching(NSPredicate(format: "identifier != %@", "filelocation.drive.account")).firstMatch
        tap(row); inspectSetup()
        tap(app.buttons["filelocation.drive.account"]); inspectSetup()
        reveal(label); XCTAssertTrue(label.exists)
        tap(app.buttons["Done"]); tap(app.buttons["Done"])
        app.terminate(); app.launch(); locations()
        reveal(label); XCTAssertTrue(label.waitForExistence(timeout: 10))
        tap(app.buttons["filelocation.drive.account"]); inspectSetup()
        tap(app.buttons["Done"]); tap(app.buttons["Done"])
        openNativeLibrary(app); tap(app.buttons["library.vaults"])
        tap(app.buttons["vaults.drive"]); inspectSetup()
        tap(app.buttons["Done"])
    }
}
