import XCTest

final class NativeChatAttachmentJourneyTests: XCTestCase {
    @MainActor
    private func chooseFixtureFile(in app: XCUIApplication) throws {
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Zerus attachment owner")).firstMatch
        for _ in 0..<5 {
            if file.waitForExistence(timeout: 1) { break }
            let local = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "On My iPhone")).firstMatch
            if local.exists { local.tap() }
            else if app.buttons["Zerus Native"].exists { app.buttons["Zerus Native"].tap() }
            else { let bars = app.navigationBars; XCTAssertGreaterThan(bars.count, 0, app.debugDescription); bars.element(boundBy: bars.count - 1).buttons.firstMatch.tap() }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 5), app.debugDescription); file.tap()
        if app.buttons["Open"].waitForExistence(timeout: 2) { app.buttons["Open"].tap() }
    }

    @MainActor
    private func importFixtureFile(in app: XCUIApplication) throws -> String {
        let prior = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","chat.attachment.preview.")).allElementsBoundByIndex.map(\.identifier)
        let ui = NativeAgentJourneyDriver(app:app)
        ui.tap(app.buttons["chat.attach"]); ui.tap(app.buttons["chat.attach.files"]); try chooseFixtureFile(in:app)
        let imported = app.buttons.matching(NSPredicate(format:"label == %@ AND NOT (identifier IN %@)","Preview Zerus attachment owner.txt",prior)).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout:20)); return imported.identifier
    }

    @MainActor
    func testFilesAttachmentPreviewAndUnsentDraftSurviveRelaunchWithoutChangingTheOriginal() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        if app.buttons["Close note"].waitForExistence(timeout: 5) { app.buttons["Close note"].tap() }
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.ask"].waitForExistence(timeout: 15)); app.buttons["navigation.ask"].tap()
        let attach = app.buttons["chat.attach"]
        XCTAssertTrue(attach.waitForExistence(timeout: 5), "Native Ask must offer real Files and Photos attachments")
        let identity = try importFixtureFile(in:app)
        let preview = app.buttons[identity], remove = app.buttons[identity.replacingOccurrences(of:"chat.attachment.preview.",with:"chat.attachment.remove.")]
        XCTAssertTrue(preview.exists); XCTAssertEqual(app.keyboards.count, 0)
        app.terminate(); app.launch(); app.buttons["navigation.ask"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 15), "An unsent file attachment must survive app relaunch")
        for _ in 0..<5 { if preview.isHittable { break }; app.scrollViews.containing(.button,identifier:preview.identifier).firstMatch.swipeLeft() }
        preview.tap(); XCTAssertTrue(app.buttons["file.preview.done"].waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Native frozen attachment preview after relaunch"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["file.preview.done"].tap()
        for _ in 0..<5 { if remove.isHittable { break }; app.scrollViews.containing(.button,identifier:remove.identifier).firstMatch.swipeLeft() }
        remove.tap()
        XCTAssertFalse(preview.exists)
        app.terminate(); app.launch(); app.buttons["navigation.ask"].tap(); XCTAssertFalse(preview.exists)
    }
    @MainActor
    func testPhotosAndFilesReachTheActualProviderAcrossModesAndRelaunch() async throws {
        let endpoint = "https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/native-attachment-qa"
        let (health, response) = try await URLSession.shared.data(from: try XCTUnwrap(URL(string: endpoint + "/models")))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: health) as? [String: Any])?["zerusNativeAgentFixture"] as? Bool, true)
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); let ui = NativeAgentJourneyDriver(app: app)
        if app.buttons["Close note"].waitForExistence(timeout: 5) { ui.tap(app.buttons["Close note"]) }
        ui.tap(app.buttons["navigation.ask"])
        // This dedicated QA simulator contains only synthetic native journey data.
        for button in app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat.attachment.remove.")).allElementsBoundByIndex { if button.isHittable { button.tap() } }
        ui.connection()
        let originalEndpoint = try XCTUnwrap(app.textFields["ai.endpoint"].value as? String), originalModel = try XCTUnwrap(app.textFields["ai.model"].value as? String)
        ui.fill(app.textFields["ai.endpoint"], endpoint); ui.fill(app.textFields["ai.model"], "zerus-native-attachment-fixture")
        ui.fill(app.secureTextFields["ai.key"], "local-synthetic-fixture-only"); ui.tap(app.buttons["Save connection"]); ui.tap(app.navigationBars["AI connection"].buttons["Done"])
        ui.tap(app.buttons["chat.attach"]); ui.tap(app.buttons["chat.attach.files"]); try chooseFixtureFile(in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Preview Zerus attachment owner.txt")).firstMatch.waitForExistence(timeout: 15))
        ui.tap(app.buttons["chat.attach"]); ui.tap(app.buttons["chat.attach.photos"])
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15), app.debugDescription)
        // Photos exposes a visible image with no AX hit point on this OS; use its observed frame.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let pickerTree = XCTAttachment(string: app.debugDescription); pickerTree.name = "System Photos picker selected synthetic image"; pickerTree.lifetime = .keepAlways; add(pickerTree)
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Add' OR label == 'Done' OR label BEGINSWITH 'Add ('")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription); ui.tap(confirm)
        let two = app.staticTexts["2 attached"]; XCTAssertTrue(two.waitForExistence(timeout: 20), app.debugDescription)
        let photoShot = XCTAttachment(screenshot: app.screenshot()); photoShot.name = "Native file and Photos attachments before sending"; photoShot.lifetime = .keepAlways; add(photoShot)
        ui.tap(app.segmentedControls.buttons["Ask"])
        // An empty prompt still sends the selected files with a useful default request.
        ui.tap(app.buttons["Send message"]); ui.waitFinished()
        let answer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic attachment transport verified")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 15), app.debugDescription)
        app.terminate(); app.launch(); ui.tap(app.buttons["navigation.ask"])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Preview Zerus attachment owner.txt")).firstMatch.waitForExistence(timeout: 15))
        for mode in ["Review", "Edit"] {
            ui.tap(app.segmentedControls.buttons[mode]); ui.send("Read the attached image and Cobalt document again in " + mode + ". Do not change any notes."); ui.waitFinished()
        }
        let finalShot = XCTAttachment(screenshot: app.screenshot()); finalShot.name = "Native attachment conversation after cold reopen and three provider modes"; finalShot.lifetime = .keepAlways; add(finalShot)
        ui.connection(); ui.fill(app.textFields["ai.endpoint"], originalEndpoint); ui.fill(app.textFields["ai.model"], originalModel)
        ui.tap(app.buttons["Save connection"]); ui.tap(app.navigationBars["AI connection"].buttons["Done"])
    }

    @MainActor
    func testUnsentChatAndFrozenFileSurviveAppInstallationAndContainerRelocation() async throws {
        let endpoint = "https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/native-chat-update-qa"
        let (health, response) = try await URLSession.shared.data(from: try XCTUnwrap(URL(string: endpoint + "/status")))
        guard (response as? HTTPURLResponse)?.statusCode == 200, (try JSONSerialization.jsonObject(with: health) as? [String: Any])?["zerusNativeContainerFixture"] as? Bool == true else { throw XCTSkip("Start the dedicated QA app-container fixture.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); let ui = NativeAgentJourneyDriver(app:app)
        if app.buttons["Close note"].waitForExistence(timeout:5) { ui.tap(app.buttons["Close note"]) }
        ui.tap(app.buttons["navigation.ask"])
        let previewID = try importFixtureFile(in:app)
        let prompt = "Native conversation continuity through an app update 🌿"
        ui.fill(app.descendants(matching:.any).matching(identifier:"chat.prompt").firstMatch,prompt)
        if app.buttons["chat.keyboard.dismiss"].exists { ui.tap(app.buttons["chat.keyboard.dismiss"]) }
        app.terminate()
        var request = URLRequest(url:try XCTUnwrap(URL(string:endpoint+"/install"))); request.httpMethod = "POST"; request.timeoutInterval = 90
        let (data, installed) = try await URLSession.shared.data(for:request)
        let receipt = XCTAttachment(data:data,uniformTypeIdentifier:"public.json"); receipt.name = "Actual QA reinstall and data-container relocation"; receipt.lifetime = .keepAlways; add(receipt)
        XCTAssertEqual((installed as? HTTPURLResponse)?.statusCode,200)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]); XCTAssertEqual(result["containerChanged"] as? Bool,true)
        app.launch(); XCTAssertTrue(app.buttons["navigation.ask"].waitForExistence(timeout:20),app.debugDescription); ui.tap(app.buttons["navigation.ask"])
        XCTAssertEqual(app.descendants(matching:.any).matching(identifier:"chat.prompt").firstMatch.value as? String,prompt)
        let preview = app.buttons[previewID]; XCTAssertTrue(preview.waitForExistence(timeout:15),app.debugDescription)
        for _ in 0..<5 { if preview.isHittable { break }; app.scrollViews.containing(.button,identifier:preview.identifier).firstMatch.swipeLeft() }
        preview.tap(); XCTAssertTrue(app.buttons["file.preview.done"].waitForExistence(timeout:10)); ui.tap(app.buttons["file.preview.done"])
        XCTAssertEqual(app.keyboards.count,0)
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "Native draft and frozen file after actual app-container relocation"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

}
