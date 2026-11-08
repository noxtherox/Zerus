import XCTest

final class NativeMenuJourneyTests: NativeJourneyTestCase {
    @MainActor
    func testLibraryBackCollectionSettingsAndComposePreserveTheCurrentScreen() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        func tap(_ element: XCUIElement) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription)
            element.tap()
        }
        func attach(_ name: String) {
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        }
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { tap(app.buttons["vault.create"]) }
        let tabs = app.otherElements["workspace.navigation"].buttons
        XCTAssertTrue(tabs["New note"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(tabs.allElementsBoundByIndex.map(\.label), ["Notes", "Tasks", "Ask", "Search", "New note"])
        XCTAssertFalse(app.buttons["bulk.select"].exists)
        XCTAssertFalse(app.buttons["collection.filters"].exists)
        attach("Notes with Library back and five bottom actions")

        tap(app.buttons["Settings"])
        XCTAssertTrue(app.buttons["collection.filters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bulk.select"].exists)
        attach("Collection actions grouped inside Settings")
        tap(app.buttons["collection.filters"])
        tap(app.buttons["collection.sort"]); tap(app.buttons["Title: Z–A"])
        tap(app.buttons["collection.filters.done"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        tap(app.buttons["bulk.select"])
        XCTAssertTrue(app.buttons["bulk.all"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Settings"].exists)
        tap(app.buttons["bulk.select"])

        tap(app.navigationBars.buttons["Library"])
        XCTAssertTrue(app.buttons["library.notes"].waitForExistence(timeout: 5))
        attach("Folders Library behind Notes")
        tap(app.buttons["library.notes"])
        tap(tabs["New note"])
        XCTAssertTrue(app.textFields["note.title"].waitForExistence(timeout: 5))
        tap(app.buttons["Cancel"])
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabs["Notes"].isSelected)

        tap(tabs["Tasks"])
        tap(tabs["New note"])
        XCTAssertTrue(app.textFields["note.title"].waitForExistence(timeout: 5))
        tap(app.buttons["Cancel"])
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabs["Tasks"].isSelected)
        tap(app.buttons["navigation.library"])
        XCTAssertTrue(app.buttons["library.notes"].waitForExistence(timeout: 5))

        tap(tabs["Search"])
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
        tap(app.buttons["navigation.library"])
        XCTAssertTrue(app.buttons["library.notes"].waitForExistence(timeout: 5))
        tap(tabs["Ask"])
        XCTAssertTrue(app.buttons["navigation.library"].waitForExistence(timeout: 10))
        tap(app.buttons["navigation.library"])
        tap(app.buttons["library.files"])
        XCTAssertFalse(app.buttons["collection.filters"].exists)
        openNativeFilters(app)
        XCTAssertTrue(app.buttons["collection.sort"].waitForExistence(timeout: 5))
        closeNativeFilters(app)
        tap(tabs["Tasks"])
        tap(app.buttons["navigation.library"])
        XCTAssertTrue(app.buttons["library.notes"].waitForExistence(timeout: 5))
        tap(app.buttons["library.links"])
        openNativeCollectionSettings(app)
        XCTAssertFalse(app.buttons["bulk.select"].exists)
        tap(app.navigationBars["Settings"].buttons["Done"])
        openNativeLibrary(app)

        let folder = "Menu ideas " + String(UUID().uuidString.prefix(6))
        let createFolder = app.buttons["library.folder.new"]
        for _ in 0..<6 where !createFolder.isHittable { app.swipeUp() }
        tap(createFolder)
        tap(app.textFields["folder.new.name"]); app.textFields["folder.new.name"].typeText(folder)
        tap(app.buttons["folder.new.create"])
        tap(app.buttons.containing(.staticText, identifier: folder).firstMatch)
        tap(tabs["New note"])
        XCTAssertTrue(app.buttons["note.folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["note.folder"].label.contains(folder), app.debugDescription)
        tap(app.textFields["note.title"]); app.textFields["note.title"].typeText("Ideas for the week")
        tap(app.buttons["note.create"])
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.typeText("Arrange your thoughts. Plan what comes next.")
        if app.buttons["Dismiss keyboard"].exists { tap(app.buttons["Dismiss keyboard"]) }
        tap(app.buttons["Close note"])
        XCTAssertTrue(app.navigationBars[folder].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Ideas for the week").firstMatch.exists)
        attach("Bottom compose creates a note in the current folder")
        openNativeLibrary(app)
        tap(app.buttons["library.notes"])
        attach("Returned to Notes after all navigation actions")
    }
}
