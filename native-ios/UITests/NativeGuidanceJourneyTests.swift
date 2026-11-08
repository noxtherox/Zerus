import XCTest

final class NativeGuidanceJourneyTests: XCTestCase {
    @MainActor
    func testNativeInstructionsAndMemorySaveCancelReloadRelaunchAndStayWithTheirVault() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let ui = NativeAgentJourneyDriver(app: app)
        let suffix = String(UUID().uuidString.prefix(6)), first = "Guidance A " + suffix, second = "Guidance B " + suffix
        let instructions = "Use short exact answers. Preserve quoted writing. " + suffix
        let memory = "Cedar is the current project. " + suffix
        func tap(_ element: XCUIElement) { ui.tap(element) }
        func reveal(_ element: XCUIElement) {
            for _ in 0..<7 {
                if element.exists, element.isHittable, element.frame.maxY < app.windows.firstMatch.frame.maxY - 95 { return }
                app.collectionViews.element(boundBy: app.collectionViews.count - 1).swipeUp()
            }
            XCTAssertTrue(element.isHittable, app.debugDescription)
        }
        func fill(_ field: XCUIElement, _ text: String) {
            reveal(field); tap(field); field.typeKey("a", modifierFlags: .command); field.typeText(text)
            XCTAssertEqual(field.value as? String, text)
            if app.buttons["Dismiss keyboard"].exists { tap(app.buttons["Dismiss keyboard"]) }
        }
        func vaults() { openNativeLibrary(app); tap(app.buttons["library.vaults"]) }
        func create(_ name: String) {
            reveal(app.buttons["vaults.create"]); tap(app.buttons["vaults.create"])
            app.alerts.textFields["Vault name"].typeText(name); tap(app.alerts.buttons["Create"])
            XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        }
        func fromAsk() {
            tap(app.buttons["navigation.ask"]); tap(app.buttons["Settings"]); tap(app.buttons["chat.aiGuidance"])
            XCTAssertTrue(app.textViews["guidance.instructions"].waitForExistence(timeout: 10))
        }
        func select(_ name: String) {
            let button = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "vault.saved.", name)).firstMatch
            for _ in 0..<8 { if button.isHittable { break }; app.swipeDown() }
            tap(button); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        }
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { tap(app.buttons["vault.create"]) }
        vaults(); create(first); fromAsk()
        let a = app.textViews["guidance.instructions"], b = app.textViews["guidance.memory"]
        XCTAssertEqual(a.value as? String, ""); XCTAssertFalse(app.buttons["guidance.save"].isEnabled)
        fill(a, instructions); fill(b, memory); tap(app.buttons["guidance.save"])
        XCTAssertTrue(app.staticTexts["guidance.saved"].waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons["guidance.save"].isEnabled)
        app.terminate(); app.launch(); tap(app.buttons["Settings"])
        reveal(app.buttons["settings.aiGuidance"]); tap(app.buttons["settings.aiGuidance"])
        XCTAssertTrue(a.waitForExistence(timeout: 10)); XCTAssertEqual(a.value as? String, instructions); XCTAssertEqual(b.value as? String, memory)
        fill(a, "Unsaved style"); tap(app.buttons["guidance.close"]); tap(app.buttons["Keep editing"])
        XCTAssertEqual(a.value as? String, "Unsaved style")
        tap(app.buttons["guidance.close"]); tap(app.buttons["Discard changes"])
        tap(app.buttons["settings.aiGuidance"]); XCTAssertTrue(a.waitForExistence(timeout: 10)); XCTAssertEqual(a.value as? String, instructions)
        fill(b, "Unsaved memory"); reveal(app.buttons["guidance.reload"]); tap(app.buttons["guidance.reload"])
        tap(app.alerts.buttons["Reload saved version"])
        XCTAssertEqual(b.value as? String, memory); XCTAssertFalse(app.buttons["guidance.save"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Native saved instructions and memory survive restart and preserve canceled drafts"; shot.lifetime = .keepAlways; add(shot)
        tap(app.buttons["guidance.close"]); tap(app.buttons["Done"])
        vaults(); create(second); fromAsk()
        XCTAssertEqual(a.value as? String, ""); XCTAssertEqual(b.value as? String, "")
        tap(app.buttons["guidance.close"]); vaults(); select(first); fromAsk()
        XCTAssertEqual(a.value as? String, instructions); XCTAssertEqual(b.value as? String, memory)
        tap(app.buttons["guidance.close"])
        if let original = ProcessInfo.processInfo.environment["ZERUS_NATIVE_QA_RESTORE_VAULT_NAME"] { vaults(); select(original) }
    }
}
