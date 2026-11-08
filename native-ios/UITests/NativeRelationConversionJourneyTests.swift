import XCTest

final class NativeRelationConversionJourneyTests: NativeJourneyTestCase {
    @MainActor
    func testReviewedTypeConversionKeepsBothNotesValuesAndRestoresReciprocalEditingAfterRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let token = String(UUID().uuidString.prefix(6))
        let source = "Conversion source " + token, target = "Conversion target " + token, field = "Conversion " + token
        let property = app.buttons["property." + field.lowercased()], definition = app.buttons["schema.definition." + field.lowercased()]
        func reveal(_ element: XCUIElement) {
            if !element.waitForExistence(timeout: 3) {
                for _ in 0..<16 {
                    app.swipeUp()
                    if element.waitForExistence(timeout: 1) { break }
                }
            }
        }
        func tap(_ element: XCUIElement) {
            reveal(element)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription); element.tap()
        }
        func create(_ title: String) {
            XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); tap(app.buttons["navigation.newNote"])
            tap(app.textFields["note.title"]); app.textFields["note.title"].typeText(title); tap(app.buttons["note.create"])
            let editor = app.textViews["note.editor"]; XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.typeText("Type conversion keeps this **writing**.")
            tap(app.buttons["Dismiss keyboard"])
        }
        func open(_ title: String) {
            let search = app.searchFields.firstMatch
            if !search.exists { app.swipeDown() }
            tap(search)
            let old = search.value as? String ?? ""
            if old != search.placeholderValue { search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
            search.typeText(title)
            tap(app.buttons.containing(.staticText, identifier: title).firstMatch)
            XCTAssertTrue(app.textViews["note.editor"].waitForExistence(timeout: 10))
        }
        func close() { tap(app.buttons["note.info.done"]); tap(app.buttons["Close note"]) }
        func manage() { tap(app.buttons["schema.manage"]); tap(definition) }
        create(target); tap(app.buttons["Close note"]); create(source)
        tap(app.buttons["Note information"]); tap(app.buttons["schema.manage"]); tap(app.buttons["schema.relation.add"])
        let name = app.textFields["relation.definition.name"]; tap(name); name.typeText(field)
        tap(app.switches["relation.definition.multiple"].switches.firstMatch)
        tap(app.buttons["relation.definition.save"]); tap(app.buttons["relation.definition.confirm"])
        tap(app.buttons["schema.done"]); tap(property)
        let filter = app.textFields["relation.search"]; tap(filter); filter.typeText(target); filter.typeText("\n")
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "relation.target.", target)).firstMatch)
        tap(app.buttons["relation.save"]); tap(app.buttons["Save paired links"])
        reveal(property); XCTAssertTrue(property.waitForExistence(timeout: 10)); XCTAssertTrue(property.label.contains(target))
        manage(); tap(app.buttons["relation.definition.type"]); tap(app.buttons["Text"])
        tap(app.buttons["relation.definition.save"]); tap(app.buttons["relation.definition.review.cancel"])
        tap(app.buttons["relation.definition.cancel"]); tap(app.buttons["schema.done"])
        tap(property); XCTAssertTrue(app.textFields["relation.search"].waitForExistence(timeout: 10)); tap(app.buttons["Cancel"])
        manage(); tap(app.buttons["relation.definition.type"]); tap(app.buttons["Text"])
        tap(app.buttons["relation.definition.save"]); tap(app.buttons["relation.definition.confirm"])
        tap(app.buttons["schema.done"]); reveal(property); XCTAssertTrue(property.waitForExistence(timeout: 10)); XCTAssertTrue(property.label.contains(target))
        tap(property); XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "property.value").firstMatch.waitForExistence(timeout: 10)); tap(app.buttons["Cancel"])
        close(); open(target); tap(app.buttons["Note information"])
        reveal(property); XCTAssertTrue(property.waitForExistence(timeout: 10)); XCTAssertTrue(property.label.contains(source), "Converting a shared same-folder definition must preserve the other note's stored values too")
        manage(); tap(app.buttons["schema.convert.relation"])
        XCTAssertTrue(name.waitForExistence(timeout: 10)); tap(app.buttons["relation.definition.save"]); tap(app.buttons["relation.definition.confirm"])
        tap(app.buttons["schema.done"]); tap(property)
        let selectedSource = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "relation.selected.", source)).firstMatch
        XCTAssertTrue(selectedSource.waitForExistence(timeout: 10))
        tap(app.buttons["Cancel"])
        close(); app.terminate(); app.launch(); open(source); tap(app.buttons["Note information"])
        reveal(property); XCTAssertTrue(property.waitForExistence(timeout: 10)); XCTAssertTrue(property.label.contains(target)); tap(property)
        let selectedTarget = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "relation.selected.", target)).firstMatch
        XCTAssertTrue(selectedTarget.waitForExistence(timeout: 10))
        tap(app.buttons["Cancel"])
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Native property conversion keeps reciprocal values after relaunch"; screenshot.lifetime = .keepAlways; add(screenshot)
        close()
    }
}
