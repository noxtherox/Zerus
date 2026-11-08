import XCTest

/// Reset the starting presentation through the real app. Reopening inside a
/// journey remains untouched and continues to exercise the saved session.
class NativeJourneyTestCase: XCTestCase {
    @MainActor
    func launchNativeJourney() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launch()
        let close = app.buttons["Close note"]
        // Vault restoration runs asynchronously after the initial launch frame.
        if close.waitForExistence(timeout: 15) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: close)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription)
            close.tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        }
        let notes = app.buttons["navigation.notes"]
        if notes.exists {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: notes)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription)
            openNativeNotes(app)
        }
        return app
    }

}

extension XCTestCase {
    @MainActor
    func openNativeLibrary(_ app: XCUIApplication) {
        if app.buttons["navigation.library"].exists { app.buttons["navigation.library"].tap() }
        else {
            app.buttons["navigation.notes"].tap()
            for _ in 0..<6 {
                if app.navigationBars["Library"].exists { break }
                let back = app.navigationBars.buttons["BackButton"].firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
                back.tap()
            }
        }
        let allNotes = app.buttons["library.notes"]
        for _ in 0..<6 where !allNotes.isHittable { app.swipeDown() }
        XCTAssertTrue(allNotes.waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor
    func openNativeNotes(_ app: XCUIApplication) {
        app.buttons["navigation.notes"].tap()
        if !app.navigationBars["Notes"].exists {
            openNativeLibrary(app)
            app.buttons["library.notes"].tap()
        }
    }

    @MainActor
    func openNativeCollectionSettings(_ app: XCUIApplication) {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["collection.filters"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func openNativeFilters(_ app: XCUIApplication) {
        openNativeCollectionSettings(app)
        app.buttons["collection.filters"].tap()
    }

    @MainActor
    func closeNativeFilters(_ app: XCUIApplication) {
        app.buttons["collection.filters.done"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
    }

    @MainActor
    func openNativeBulkHistory(_ app: XCUIApplication) {
        openNativeCollectionSettings(app)
        app.buttons["bulk.history"].tap()
    }

    @MainActor
    func closeNativeBulkHistory(_ app: XCUIApplication) {
        app.buttons["bulk.history.done"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
    }
}
