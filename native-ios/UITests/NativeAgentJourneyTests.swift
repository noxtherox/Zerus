import XCTest

final class NativeAgentJourneyTests: XCTestCase {
    @MainActor
    func testNativeProviderToolsReviewCancelCommitRestartUndoAndExplicitEditMode() async throws {
        let endpoint = try await NativeAgentJourneyDriver.fixtureEndpoint()
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let ui = NativeAgentJourneyDriver(app: app)
        let tap = ui.tap, visible = ui.visible, fill = ui.fill
        let connection = ui.connection, send = ui.send, waitFinished = ui.waitFinished
        let openRun = ui.openRun, closeRun = ui.closeRun, apply = ui.apply
        func assertLatestReply(_ prompt: String, _ answer: String) throws {
            // No manual scrolling: the latest answer and its actions must fit
            // above the composer after reopening or dismissing a run sheet.
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Latest answer before visibility check"; shot.lifetime = .keepAlways; add(shot)
            let latestPrompt = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", String(prompt.prefix(90)))).firstMatch
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: latestPrompt)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, "The reopened conversation must show the latest turn.")
            let reply = try XCTUnwrap(app.staticTexts.matching(NSPredicate(format: "label == %@", answer)).allElementsBoundByIndex.last)
            let share = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "label == %@", "Share answer")).allElementsBoundByIndex.last)
            let composer = app.descendants(matching: .any).matching(identifier: "chat.composer").firstMatch
            XCTAssertTrue(composer.exists && reply.isHittable && share.isHittable, app.debugDescription)
            XCTAssertGreaterThan(reply.frame.minY, latestPrompt.frame.maxY)
            XCTAssertGreaterThan(share.frame.minY, reply.frame.maxY)
            XCTAssertLessThanOrEqual(share.frame.maxY, composer.frame.minY)
        }
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { tap(app.buttons["vault.create"]) }
        let suffix = String(UUID().uuidString.prefix(6)), title = "Agent fixture " + suffix
        let reviewPrompt = "Review the passage in my selected note. " + suffix
        let visibilityPrompt = ("Read my selected synthetic note. " + suffix + " " + String(repeating: "Synthetic reading context keeps this conversation longer than the phone viewport. ", count: 12)).trimmingCharacters(in: .whitespacesAndNewlines)
        let editPrompt = "Update the passage in my selected note now. " + suffix
        tap(app.buttons["navigation.newNote"]); fill(app.textFields["note.title"], title); tap(app.buttons["note.create"])
        let editor = app.textViews["note.editor"]; XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.typeText("Before native agent.\n\nKeep this independent line.")
        tap(app.buttons["Dismiss keyboard"]); tap(app.buttons["Close note"]); tap(app.buttons["navigation.ask"])
        connection()
        let originalEndpoint = try XCTUnwrap(app.textFields["ai.endpoint"].value as? String), originalModel = try XCTUnwrap(app.textFields["ai.model"].value as? String)
        fill(app.textFields["ai.endpoint"], endpoint); fill(app.textFields["ai.model"], "zerus-native-fixture")
        fill(app.secureTextFields["ai.key"], "local-synthetic-fixture-only")
        tap(app.buttons["Save connection"])
        XCTAssertFalse(app.staticTexts["The API key could not be saved or read from the iOS Keychain."].exists, app.debugDescription)
        tap(app.navigationBars["AI connection"].buttons["Done"])
        XCTAssertEqual(app.staticTexts["chat.connection.status"].label, "zerus-native-fixture")
        func choose() { ui.choose([title]) }
        choose(); tap(app.segmentedControls.buttons["Ask"]); send(visibilityPrompt); waitFinished()
        app.terminate(); app.launch(); tap(app.buttons["navigation.ask"])
        try assertLatestReply(visibilityPrompt, "The selected synthetic note contains the original passage. No notes were changed.")
        let conversation = app.scrollViews["chat.history"]
        conversation.swipeDown()
        XCTAssertTrue(app.buttons["chat.latest"].waitForExistence(timeout: 5))
        tap(app.buttons["chat.latest"])
        try assertLatestReply(visibilityPrompt, "The selected synthetic note contains the original passage. No notes were changed.")
        choose(); tap(app.segmentedControls.buttons["Review"]); send(reviewPrompt); waitFinished()
        openRun(reviewPrompt)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).count, 0)
        visible(app.buttons["agent.reviewAll"]); tap(app.buttons["agent.review.cancel"])
        XCTAssertTrue(app.buttons["agent.reviewAll"].waitForExistence(timeout: 10))
        visible(app.buttons["agent.reviewAll"])
        let reviewShot = XCTAttachment(screenshot: app.screenshot()); reviewShot.name = "Native AI exact-change review before approval"; reviewShot.lifetime = .keepAlways; add(reviewShot)
        apply()
        var undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 15))
        app.terminate(); app.launch(); tap(app.buttons["navigation.ask"]); openRun(reviewPrompt)
        undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).firstMatch
        visible(undo); tap(app.buttons["agent.review.cancel"])
        XCTAssertTrue(undo.waitForExistence(timeout: 10)); visible(undo); apply()
        XCTAssertTrue(app.staticTexts["Undone"].waitForExistence(timeout: 15)); closeRun()
        try assertLatestReply(reviewPrompt, "A focused change is ready for your review.")
        // Mode is an explicit native control; the same provider tools can now save one requested edit.
        choose(); tap(app.segmentedControls.buttons["Edit"]); send(editPrompt); waitFinished(); openRun(editPrompt)
        XCTAssertFalse(app.buttons["agent.reviewAll"].exists)
        undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 15), app.debugDescription)
        let receiptShot = XCTAttachment(screenshot: app.screenshot()); receiptShot.name = "Native Edit mode returns a durable verified receipt"; receiptShot.lifetime = .keepAlways; add(receiptShot)
        visible(undo); apply(); XCTAssertTrue(app.staticTexts["Undone"].waitForExistence(timeout: 15)); closeRun()
        // The provider's property call must reach an exact native header review,
        // keep Cancel non-mutating, and survive restart with a durable undo.
        let propertyPrompt = "Update properties for my selected note. " + suffix
        XCTAssertTrue(app.buttons["chat.chooseContext"].label.contains("1 note"), "Retain the already-selected synthetic note instead of toggling it off")
        tap(app.segmentedControls.buttons["Review"]); send(propertyPrompt); waitFinished(); openRun(propertyPrompt)
        visible(app.buttons["agent.reviewAll"])
        XCTAssertTrue(app.staticTexts["agent.review.properties"].waitForExistence(timeout: 10))
        let statusChange = app.descendants(matching: .any).matching(identifier: "agent.review.property.status").firstMatch
        XCTAssertTrue(statusChange.waitForExistence(timeout: 5)); XCTAssertTrue(statusChange.label.contains("Ready"))
        let source = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.review.source.")).firstMatch
        visible(source)
        let proposed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "# " + title, "Status: \"Ready\"")).firstMatch
        for _ in 0..<6 {
            if proposed.exists { break }
            app.collectionViews.element(boundBy: app.collectionViews.count - 1).swipeUp()
        }
        XCTAssertTrue(proposed.waitForExistence(timeout: 5), app.debugDescription)
        let proposedText = proposed.label
        XCTAssertTrue(proposedText.contains("Status: \"Ready\"") && proposedText.contains("Score: 8") && proposedText.contains("Done: true"), proposedText)
        tap(app.buttons["agent.review.cancel"]); XCTAssertTrue(app.buttons["agent.reviewAll"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).count, 0)
        visible(app.buttons["agent.reviewAll"])
        let propertyShot = XCTAttachment(screenshot: app.screenshot()); propertyShot.name = "Native property review shows typed before and after values"; propertyShot.lifetime = .keepAlways; add(propertyShot)
        apply(); XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).firstMatch.waitForExistence(timeout: 15))
        app.terminate(); app.launch(); tap(app.buttons["navigation.ask"]); openRun(propertyPrompt)
        undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).firstMatch
        visible(undo); XCTAssertTrue(app.staticTexts["agent.review.properties"].waitForExistence(timeout: 10)); apply()
        XCTAssertTrue(app.staticTexts["Undone"].waitForExistence(timeout: 15)); closeRun()
        // Restore the previous provider choice without reading or replacing its existing credential.
        connection(); fill(app.textFields["ai.endpoint"], ProcessInfo.processInfo.environment["ZERUS_NATIVE_AGENT_RESTORE_ENDPOINT"] ?? originalEndpoint); fill(app.textFields["ai.model"], ProcessInfo.processInfo.environment["ZERUS_NATIVE_AGENT_RESTORE_MODEL"] ?? originalModel)
        tap(app.buttons["Save connection"]); tap(app.navigationBars["AI connection"].buttons["Done"])
        app.terminate(); app.launch(); openNativeNotes(app)
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        tap(search); search.typeText(title)
        let note = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        visible(note); XCTAssertTrue(editor.waitForExistence(timeout: 15))
        let text = editor.value as? String ?? ""
        XCTAssertTrue(text.contains("Before native agent.")); XCTAssertTrue(text.contains("Keep this independent line.")); XCTAssertFalse(text.contains("After native agent."))
    }

    @MainActor
    func testNativeEditModeReviewsBothReciprocalNotesAndRestoresTheirLinksAfterRestart() async throws {
        let endpoint = try await NativeAgentJourneyDriver.fixtureEndpoint()
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let ui = NativeAgentJourneyDriver(app: app)
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { ui.tap(app.buttons["vault.create"]) }
        let token = String(UUID().uuidString.prefix(6))
        let source = "Agent relation source " + token, target = "Agent relation target " + token
        let relation = "Agent link " + token
        func create(_ title: String) {
            ui.tap(app.buttons["navigation.newNote"]); ui.fill(app.textFields["note.title"], title); ui.tap(app.buttons["note.create"])
            let editor = app.textViews["note.editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10)); editor.typeText("Keep independent writing for " + title + ".")
            ui.tap(app.buttons["Dismiss keyboard"])
        }
        create(target); ui.tap(app.buttons["Close note"]); create(source)
        ui.tap(app.buttons["Note information"]); ui.tap(app.buttons["schema.manage"]); ui.tap(app.buttons["schema.relation.add"])
        ui.fill(app.textFields["relation.definition.name"], relation)
        let multiple = app.switches["relation.definition.multiple"]
        ui.tap(multiple.switches.firstMatch); XCTAssertEqual(multiple.value as? String, "1")
        ui.tap(app.buttons["relation.definition.save"]); ui.tap(app.buttons["relation.definition.confirm"]); ui.tap(app.buttons["schema.done"])
        let property = app.buttons["property." + relation.lowercased()]
        ui.tap(property); ui.fill(app.textFields["relation.search"], target); ui.tap(app.keyboards.buttons["Done"])
        ui.tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "relation.target.", target)).firstMatch)
        ui.tap(app.buttons["relation.save"]); ui.tap(app.buttons["Save paired links"])
        XCTAssertTrue(property.waitForExistence(timeout: 15)); XCTAssertTrue(property.label.contains(target))
        ui.tap(app.buttons["note.info.done"]); ui.tap(app.buttons["Close note"]); ui.tap(app.buttons["navigation.ask"])
        ui.connection()
        let originalEndpoint = try XCTUnwrap(app.textFields["ai.endpoint"].value as? String)
        let originalModel = try XCTUnwrap(app.textFields["ai.model"].value as? String)
        ui.fill(app.textFields["ai.endpoint"], endpoint); ui.fill(app.textFields["ai.model"], "zerus-native-fixture")
        ui.fill(app.secureTextFields["ai.key"], "local-synthetic-fixture-only")
        ui.tap(app.buttons["Save connection"]); ui.tap(app.navigationBars["AI connection"].buttons["Done"])
        ui.choose([source, target]); ui.tap(app.segmentedControls.buttons["Edit"])
        let prompt = "Unlink my two selected notes. " + token
        ui.send(prompt); ui.waitFinished(); ui.openRun(prompt)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).count, 0, "Both files must wait for approval in Edit mode")
        ui.visible(app.buttons["agent.reviewAll"])
        let row = app.descendants(matching: .any).matching(identifier: "agent.review.property." + relation.lowercased())
        XCTAssertTrue(row.firstMatch.waitForExistence(timeout: 10)); XCTAssertTrue(row.firstMatch.label.contains(target), app.debugDescription)
        XCTAssertTrue(row.firstMatch.label.contains("Not set")); XCTAssertFalse(row.firstMatch.label.contains("zerus:"), "The comparison must show linked note names")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Reciprocal relation review names the linked notes"; shot.lifetime = .keepAlways; add(shot)
        ui.tap(app.buttons["agent.review.cancel"])
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).count, 0)
        ui.visible(app.buttons["agent.reviewAll"]); ui.apply()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).firstMatch.waitForExistence(timeout: 15))
        app.terminate(); app.launch(); ui.tap(app.buttons["navigation.ask"]); ui.openRun(prompt)
        ui.visible(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agent.undo.")).firstMatch)
        XCTAssertTrue(app.staticTexts["agent.review.properties"].firstMatch.waitForExistence(timeout: 10)); ui.apply()
        XCTAssertTrue(app.staticTexts["Undone"].waitForExistence(timeout: 15)); ui.closeRun()
        ui.connection(); ui.fill(app.textFields["ai.endpoint"], originalEndpoint); ui.fill(app.textFields["ai.model"], originalModel)
        ui.tap(app.buttons["Save connection"]); ui.tap(app.navigationBars["AI connection"].buttons["Done"])
        app.terminate(); app.launch(); openNativeNotes(app)
        for (title, linked) in [(source, target), (target, source)] {
            let search = app.searchFields.firstMatch
            if !search.exists { app.swipeDown() }
            ui.fill(search, title)
            ui.visible(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch)
            let editor = app.textViews["note.editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10)); XCTAssertTrue((editor.value as? String)?.contains("Keep independent writing for " + title + ".") == true)
            ui.tap(app.buttons["Note information"])
            XCTAssertTrue(property.waitForExistence(timeout: 10)); XCTAssertTrue(property.label.contains(linked), app.debugDescription)
            ui.tap(app.buttons["note.info.done"]); ui.tap(app.buttons["Close note"])
        }
    }

}


@MainActor
final class NativeAgentJourneyDriver {
    let app: XCUIApplication
    init(app: XCUIApplication) { self.app = app }
    static func fixtureEndpoint() async throws -> String {
        let endpoint = ProcessInfo.processInfo.environment["ZERUS_NATIVE_AGENT_FIXTURE_ENDPOINT"] ?? "https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/native-agent-qa"
        var health = URLRequest(url: try XCTUnwrap(URL(string: endpoint + "/models"))); health.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: health)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["zerusNativeAgentFixture"] as? Bool == true else { throw XCTSkip("Start the private native agent HTTPS fixture before this integration journey.") }
        } catch { throw XCTSkip("Native agent HTTPS fixture is unavailable: " + error.localizedDescription) }
        return endpoint
    }
    func tap(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription); element.tap()
    }
    func visible(_ element: XCUIElement) {
        for _ in 0..<7 {
            if element.exists, element.isHittable, element.frame.minY > 110, element.frame.maxY < app.windows.firstMatch.frame.maxY - 85 { break }
            let lists = app.collectionViews
            if lists.count > 0 { lists.element(boundBy: lists.count - 1).swipeUp() } else { app.swipeUp() }
        }
        tap(element)
    }
    func fill(_ field: XCUIElement, _ text: String) {
        if field.exists, field.value as? String == text { return }
        tap(field)
        // Single-line fixture inputs: move to the end and erase the actual value.
        // Replacing a selection with typeText can retain URL fragments in XCTest.
        field.typeKey(.rightArrow, modifierFlags: .command)
        let existing = field.value as? String ?? ""
        if existing != field.placeholderValue, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            let cleared = field.value as? String ?? ""
            XCTAssertTrue(cleared.isEmpty || cleared == field.placeholderValue, "Fixture field must be empty before replacement")
        }
        field.typeText(text)
        if field.elementType != .secureTextField { XCTAssertEqual(field.value as? String, text, "Fixture input must be exact before saving or sending") }
    }
    func connection() { tap(app.buttons["Settings"]); tap(app.buttons["AI connection"]); XCTAssertTrue(app.textFields["ai.endpoint"].waitForExistence(timeout: 10)) }
    func choose(_ titles: [String]) {
        tap(app.buttons["chat.chooseContext"])
        for title in titles { fill(app.textFields["note.picker.search"], title); tap(app.buttons[title]) }
        tap(app.navigationBars["Choose context"].buttons["Done"])
    }
    func send(_ prompt: String) {
        fill(app.descendants(matching: .any).matching(identifier: "chat.prompt").firstMatch, prompt)
        tap(app.buttons["chat.keyboard.dismiss"]); tap(app.buttons["Send message"])
    }
    func waitFinished() {
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Stop generating"])
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 60), .completed, app.debugDescription)
        XCTAssertTrue(app.buttons["agent.current"].waitForExistence(timeout: 10), app.debugDescription)
    }
    func openRun(_ prompt: String) {
        tap(app.buttons["Settings"]); tap(app.buttons["agent.runs"])
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agent.run.", prompt)).firstMatch)
        XCTAssertTrue(app.navigationBars["AI run"].waitForExistence(timeout: 10))
    }
    func closeRun() { tap(app.navigationBars["AI run"].buttons.firstMatch); tap(app.buttons["agent.runs.done"]) }
    func apply() { tap(app.buttons["agent.review.apply"]); tap(app.alerts.buttons["Apply changes"]) }
}
