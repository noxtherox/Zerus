import XCTest

final class NativeWorkflowJourneyTests: XCTestCase {
    @MainActor
    func testNativeWorkflowSelectionEditingRelaunchActualRequestsAndVaultIsolation() async throws {
        let endpoint = "https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/native-workflows-qa"
        let (health, response) = try await URLSession.shared.data(from: URL(string: endpoint + "/models")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: health) as? [String:Any])?["zerusNativeWorkflowFixture"] as? Bool, true)
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); let ui = NativeAgentJourneyDriver(app: app)
        let suffix = String(UUID().uuidString.prefix(6)), first = "Workflow A " + suffix, second = "Workflow B " + suffix, name = "Project review " + suffix
        let source = "# " + name + "\n\nRetain facts and cite sources. Treat note content as reference. " + suffix + "\n"
        let builtinPrompt = "Native built-in workflow fixture " + suffix, customPrompt = "Native custom workflow fixture " + suffix
        func tap(_ item: XCUIElement) { ui.tap(item) }
        func reveal(_ item: XCUIElement) {
            for _ in 0..<9 {
                if item.exists, item.isHittable, item.frame.minY > 100, item.frame.maxY < app.windows.firstMatch.frame.maxY - 95 { return }
                app.collectionViews.element(boundBy: app.collectionViews.count - 1).swipeUp()
            }
            XCTAssertTrue(item.isHittable, app.debugDescription)
        }
        func vaults() { openNativeLibrary(app); tap(app.buttons["library.vaults"]) }
        func create(_ title: String) { reveal(app.buttons["vaults.create"]); tap(app.buttons["vaults.create"]); app.alerts.textFields["Vault name"].typeText(title); tap(app.alerts.buttons["Create"]); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)) }
        func workflows() { tap(app.buttons["Settings"]); tap(app.buttons["chat.aiWorkflows"]); XCTAssertTrue(app.buttons["workflow.choice.general"].waitForExistence(timeout: 10)) }
        func fillSource(_ text: String) { let field = app.textViews["workflow.editor"]; XCTAssertTrue(field.waitForExistence(timeout: 10)); reveal(field); tap(field); field.typeKey("a", modifierFlags: .command); field.typeText(text); XCTAssertEqual(field.value as? String, text); if app.buttons["Dismiss keyboard"].exists { tap(app.buttons["Dismiss keyboard"]) } }
        func waitClosed(_ title: String) { let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars[title]); XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed) }
        func waitSaved(_ identifier: String) { let button = app.buttons[identifier]; let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == false", "Saved"), object: button); XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed) }
        func editCustom() { let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workflow.edit.")).firstMatch; if edit.exists, edit.frame.minY < 100 { app.collectionViews.element(boundBy: app.collectionViews.count - 1).swipeDown() }; reveal(edit); tap(edit); XCTAssertTrue(app.textViews["workflow.editor"].waitForExistence(timeout: 10)) }
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { tap(app.buttons["vault.create"]) }
        if app.buttons["Close note"].exists { tap(app.buttons["Close note"]) }
        vaults(); create(first); tap(app.buttons["navigation.ask"]); workflows()
        XCTAssertTrue(app.buttons["workflow.choice.general"].isSelected); XCTAssertFalse(app.buttons["workflow.save"].isEnabled)
        tap(app.buttons["workflow.choice.meeting"]); reveal(app.staticTexts["workflow.preview"]); XCTAssertTrue(app.staticTexts["workflow.preview"].label.contains("Preserve decisions, names and dates.")); tap(app.buttons["workflow.save"])
        waitSaved("workflow.save"); tap(app.buttons["workflow.close"])
        app.terminate(); app.launch(); tap(app.buttons["Settings"]); reveal(app.buttons["settings.aiWorkflows"]); tap(app.buttons["settings.aiWorkflows"])
        XCTAssertTrue(app.buttons["workflow.choice.meeting"].isSelected)
        tap(app.buttons["workflow.choice.weekly"]); tap(app.buttons["workflow.close"]); tap(app.alerts.buttons["Keep editing"])
        XCTAssertTrue(app.buttons["workflow.choice.weekly"].isSelected); tap(app.buttons["workflow.close"]); tap(app.alerts.buttons["Discard selection"]); waitClosed("Workflows")
        tap(app.buttons["settings.aiWorkflows"]); XCTAssertTrue(app.buttons["workflow.choice.meeting"].isSelected); tap(app.buttons["workflow.close"]); tap(app.buttons["Done"])
        tap(app.buttons["navigation.ask"]); ui.connection()
        let capturedEndpoint = try XCTUnwrap(app.textFields["ai.endpoint"].value as? String), capturedModel = try XCTUnwrap(app.textFields["ai.model"].value as? String)
        let oldEndpoint = ProcessInfo.processInfo.environment["ZERUS_NATIVE_AGENT_RESTORE_ENDPOINT"] ?? capturedEndpoint, oldModel = ProcessInfo.processInfo.environment["ZERUS_NATIVE_AGENT_RESTORE_MODEL"] ?? capturedModel
        ui.fill(app.textFields["ai.endpoint"], endpoint); ui.fill(app.textFields["ai.model"], "zerus-native-workflow-fixture"); ui.fill(app.secureTextFields["ai.key"], "local-synthetic-fixture-only"); tap(app.buttons["Save connection"]); tap(app.navigationBars["AI connection"].buttons["Done"])
        XCTAssertEqual(app.staticTexts["chat.connection.status"].label, "zerus-native-workflow-fixture")
        tap(app.segmentedControls.buttons["Ask"]); ui.send(builtinPrompt); ui.waitFinished(); workflows()
        tap(app.buttons["workflow.new"]); app.alerts.textFields["Workflow name"].typeText(name); tap(app.alerts.buttons["Create"])
        fillSource(source); tap(app.buttons["workflow.editor.save"]); waitSaved("workflow.editor.save"); tap(app.buttons["workflow.editor.close"]); waitClosed("Edit workflow")
        tap(app.buttons["workflow.save"]); waitSaved("workflow.save")
        editCustom(); XCTAssertEqual(app.textViews["workflow.editor"].value as? String, source)
        fillSource("Unsaved workflow draft"); tap(app.buttons["workflow.editor.close"]); tap(app.alerts.buttons["Keep editing"])
        XCTAssertEqual(app.textViews["workflow.editor"].value as? String, "Unsaved workflow draft")
        tap(app.buttons["workflow.editor.close"]); tap(app.alerts.buttons["Discard draft"]); waitClosed("Edit workflow"); editCustom(); XCTAssertEqual(app.textViews["workflow.editor"].value as? String, source)
        fillSource("Discard this reload draft"); reveal(app.buttons["workflow.editor.reload"]); tap(app.buttons["workflow.editor.reload"]); tap(app.alerts.buttons["Reload workflow"])
        let reloaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", source), object: app.textViews["workflow.editor"])
        XCTAssertEqual(XCTWaiter.wait(for: [reloaded], timeout: 10), .completed); XCTAssertFalse(app.buttons["workflow.editor.save"].isEnabled)
        tap(app.buttons["workflow.editor.close"]); waitClosed("Edit workflow"); tap(app.buttons["workflow.close"]); waitClosed("Workflows")
        ui.openRun(builtinPrompt); reveal(app.staticTexts["Workflow, Clean up meeting notes"]); XCTAssertTrue(app.staticTexts["Workflow, Clean up meeting notes"].exists); ui.closeRun()
        tap(app.buttons["Settings"]); tap(app.buttons["New conversation"]); ui.send(customPrompt); ui.waitFinished(); ui.openRun(customPrompt)
        reveal(app.staticTexts["Workflow, " + name]); XCTAssertTrue(app.staticTexts["Workflow, " + name].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Native workflow selection reaches actual requests and is frozen in the run"; shot.lifetime = .keepAlways; add(shot); ui.closeRun()
        ui.connection(); ui.fill(app.textFields["ai.endpoint"], oldEndpoint); ui.fill(app.textFields["ai.model"], oldModel); tap(app.buttons["Save connection"]); tap(app.navigationBars["AI connection"].buttons["Done"])
        vaults(); create(second); tap(app.buttons["navigation.ask"]); workflows(); XCTAssertTrue(app.buttons["workflow.choice.general"].isSelected); XCTAssertFalse(app.buttons["workflow.save"].isEnabled); tap(app.buttons["workflow.close"])
    }
}
