import XCTest

final class NativeLimitsJourneyTests: XCTestCase {
    @MainActor
    func testNativeLimitEditingActualProviderCapsAndActiveDeadlinePreserveJournalsAndVaultIsolation() async throws {
        let endpoint = "https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/native-limits-qa"
        let (health, response) = try await URLSession.shared.data(from: URL(string:endpoint+"/models")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((try JSONSerialization.jsonObject(with:health) as? [String:Any])?["zerusNativeAgentFixture"] as? Bool, true)
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); let ui = NativeAgentJourneyDriver(app:app)
        let suffix = String(UUID().uuidString.prefix(6)), a = "Limits A "+suffix, b = "Limits B "+suffix, note = "Limits fixture "+suffix
        let normal = "Native limits ordinary fixture "+suffix, timeout = "Native limits timeout fixture "+suffix
        func tap(_ item: XCUIElement) { ui.tap(item) }
        func reveal(_ item: XCUIElement) {
            for _ in 0..<8 { if item.exists, item.isHittable, item.frame.maxY < app.windows.firstMatch.frame.maxY-95 { return }; app.collectionViews.element(boundBy:app.collectionViews.count-1).swipeUp() }
            XCTAssertTrue(item.isHittable, app.debugDescription)
        }
        func fill(_ name: String, _ value: String) { let field=app.textFields["limits."+name]; reveal(field); ui.fill(field,value); if app.buttons["Dismiss keyboard"].exists { tap(app.buttons["Dismiss keyboard"]) } }
        func vaults() { openNativeLibrary(app); tap(app.buttons["library.vaults"]) }
        func create(_ name: String) { reveal(app.buttons["vaults.create"]); tap(app.buttons["vaults.create"]); app.alerts.textFields["Vault name"].typeText(name); tap(app.alerts.buttons["Create"]); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout:15)) }
        func limits() { tap(app.buttons["Settings"]); tap(app.buttons["chat.aiLimits"]); XCTAssertTrue(app.textFields["limits.maxSteps"].waitForExistence(timeout:10)) }
        if app.buttons["vault.create"].waitForExistence(timeout:3) { tap(app.buttons["vault.create"]) }
        vaults(); create(a)
        tap(app.buttons["navigation.newNote"]); ui.fill(app.textFields["note.title"],note); tap(app.buttons["note.create"])
        XCTAssertTrue(app.textViews["note.editor"].waitForExistence(timeout:10)); app.textViews["note.editor"].typeText("Before native agent.\nKeep this original writing.")
        tap(app.buttons["Dismiss keyboard"]); tap(app.buttons["Close note"]); tap(app.buttons["navigation.ask"]); limits()
        fill("maxSteps","1"); XCTAssertFalse(app.buttons["limits.save"].isEnabled)
        fill("maxSteps","2"); fill("maxMinutes","1"); fill("maxTotalTokens","8000"); fill("maxInputTokens","12000"); fill("maxOutputTokens","2048")
        reveal(app.buttons["limits.effort"]); tap(app.buttons["limits.effort"]); tap(app.buttons["Low"]); tap(app.buttons["limits.save"])
        XCTAssertTrue(app.staticTexts["limits.saved"].waitForExistence(timeout:10)); tap(app.buttons["limits.close"])
        app.terminate(); app.launch(); tap(app.buttons["Settings"]); reveal(app.buttons["settings.aiLimits"]); tap(app.buttons["settings.aiLimits"])
        XCTAssertEqual(app.textFields["limits.maxSteps"].value as? String,"2")
        fill("maxSteps","3"); tap(app.buttons["limits.close"]); tap(app.alerts.buttons["Keep editing"])
        XCTAssertEqual(app.textFields["limits.maxSteps"].value as? String,"3")
        tap(app.buttons["limits.close"]); tap(app.alerts.buttons["Discard changes"]); tap(app.buttons["settings.aiLimits"])
        XCTAssertEqual(app.textFields["limits.maxSteps"].value as? String,"2")
        reveal(app.buttons["limits.defaults"]); tap(app.buttons["limits.defaults"]); reveal(app.buttons["limits.reload"]); tap(app.buttons["limits.reload"]); tap(app.alerts.buttons["Reload saved limits"])
        XCTAssertFalse(app.buttons["limits.save"].isEnabled); tap(app.buttons["limits.close"]); tap(app.buttons["Done"]); tap(app.buttons["navigation.ask"])
        ui.connection(); let oldEndpoint=try XCTUnwrap(app.textFields["ai.endpoint"].value as? String), oldModel=try XCTUnwrap(app.textFields["ai.model"].value as? String)
        ui.fill(app.textFields["ai.endpoint"],endpoint); ui.fill(app.textFields["ai.model"],"zerus-native-fixture"); ui.fill(app.secureTextFields["ai.key"],"local-synthetic-fixture-only"); tap(app.buttons["Save connection"]); tap(app.navigationBars["AI connection"].buttons["Done"])
        XCTAssertEqual(app.staticTexts["chat.connection.status"].label, "zerus-native-fixture")
        ui.choose([note]); tap(app.segmentedControls.buttons["Ask"]); ui.send(normal); ui.waitFinished(); ui.openRun(normal)
        reveal(app.staticTexts["Model steps, 2 / 2"]); XCTAssertTrue(app.staticTexts["Model steps, 2 / 2"].exists); ui.closeRun()
        tap(app.buttons["Settings"]); tap(app.buttons["New conversation"]); ui.send(timeout); let started=Date()
        let issue=app.staticTexts["agent.issue"]; XCTAssertTrue(issue.waitForExistence(timeout:75)); XCTAssertTrue(issue.label.contains("saved time limit"),issue.label)
        XCTAssertGreaterThan(Date().timeIntervalSince(started),50); XCTAssertLessThan(Date().timeIntervalSince(started),67)
        // The deadline publishes its reason before the final journal commit finishes.
        // Wait for that visible completion rather than racing the cancellation callback.
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Stop generating"])
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 10), .completed)
        ui.openRun(timeout)
        reveal(app.staticTexts["Model steps, 1 / 2"]); XCTAssertTrue(app.staticTexts["Model steps, 1 / 2"].exists)
        reveal(app.buttons["agent.resume"]); XCTAssertFalse(app.buttons["agent.resume"].isEnabled)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Native saved limits stop a held real provider request and preserve its run journal";shot.lifetime = .keepAlways;add(shot);ui.closeRun()
        ui.connection(); ui.fill(app.textFields["ai.endpoint"],oldEndpoint); ui.fill(app.textFields["ai.model"],oldModel); tap(app.buttons["Save connection"]); tap(app.navigationBars["AI connection"].buttons["Done"])
        vaults(); create(b); tap(app.buttons["navigation.ask"]); limits(); XCTAssertEqual(app.textFields["limits.maxSteps"].value as? String,"30"); tap(app.buttons["limits.close"])
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","LATE OUTPUT MUST NOT APPEAR")).firstMatch.exists)
    }
}
