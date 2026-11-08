import XCTest
import UIKit

final class NativeExternalNotesUITests: NativeJourneyTestCase {
    @MainActor
    func testExternalFileCreationNativeEditingReopenReloadCancelForgetAndFilesOpenKeepTheOriginal() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        collection(app); app.buttons["external.new"].tap()
        XCTAssertTrue(app.textFields["external.new.name"].waitForExistence(timeout: 5)); app.buttons["external.new.cancel"].tap()
        let suffix = String(UUID().uuidString.prefix(6)), title = "External check " + suffix, filename = title + ".md", needle = "outsidebody" + suffix
        create(app, title: title)
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["External note actions"].tap(); app.buttons["Full Markdown source"].tap()
        let text = "---\nforeign: 'Keep: this'\n---\n# " + title + "\n\nA **bold** outside thought.\n\n```swift\nlet outside = \"Keep <literal>\"\n```\n\n| A | B |\n| --- | --- |\n| one | two |\n\nSource stays in Files.\n\n" + needle + "\n"
        editor.tap(); editor.typeKey("a", modifierFlags: .command); editor.typeText(text)
        if app.buttons["Dismiss keyboard"].exists { app.buttons["Dismiss keyboard"].tap() }
        app.buttons["External note actions"].tap(); app.buttons["Full Markdown source"].tap()
        XCTAssertTrue(app.buttons["Edit swift code"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["Edit table"].exists)
        app.buttons["External note actions"].tap(); app.buttons["Reload file"].tap()
        XCTAssertTrue(app.alerts["Reload the current file?"].waitForExistence(timeout: 5)); app.alerts.buttons["Cancel"].tap()
        app.buttons["external.editor.done"].tap()
        let row = app.buttons.containing(.staticText, identifier: filename).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); collection(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 10))
        app.buttons["External note actions"].tap(); app.buttons["Full Markdown source"].tap()
        XCTAssertEqual(editor.value as? String, text, "The actual selected file must keep complete Markdown and foreign YAML after relaunch")
        app.buttons["external.editor.done"].tap(); XCTAssertTrue(row.waitForExistence(timeout: 10))
        app.buttons["navigation.ask"].tap()
        let prompt = app.descendants(matching: .any).matching(identifier: "chat.prompt").firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5)); let previousPrompt = prompt.value as? String ?? ""; let priorUserMessages = app.staticTexts.matching(identifier: "YOU").count
        app.buttons["navigation.search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(needle)
        app.buttons["search.keyboard.dismiss"].tap()
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "search.result.external:", title)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "Full body search must find the registered file after relaunch")
        app.buttons["search.filters"].tap(); app.descendants(matching: .any).matching(identifier: "search.collection").firstMatch.tap()
        app.buttons["External notes"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 10)); result.tap()
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 10))
        app.buttons["External note actions"].tap(); app.buttons["Full Markdown source"].tap()
        XCTAssertEqual(editor.value as? String, text, "Search must reopen the selected external original in its own editor")
        app.buttons["external.editor.done"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 10)); result.press(forDuration: 1); app.buttons["Preview"].tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5)); app.buttons["Ask Zerus"].tap()
        let reachedComposer = prompt.waitForExistence(timeout: 8)
        if !reachedComposer { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "External search reference handoff state"; shot.lifetime = .keepAlways; add(shot) }
        XCTAssertTrue(reachedComposer, app.debugDescription)
        XCTAssertTrue((prompt.value as? String ?? "").contains(title))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat.reference").firstMatch.exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "YOU").count, priorUserMessages, "Adding an external reference must leave the prompt unsent")
        app.buttons["Remove reference"].tap()
        prompt.tap(); prompt.typeKey("a", modifierFlags: .command); prompt.typeKey(.delete, modifierFlags: [])
        if !previousPrompt.isEmpty { prompt.typeText(previousPrompt) }
        if app.buttons["chat.keyboard.dismiss"].exists { app.buttons["chat.keyboard.dismiss"].tap() }
        let contextPrompt = try XCTUnwrap(prompt.value as? String)
        app.buttons["chat.chooseContext"].tap()
        XCTAssertTrue(app.buttons["context.external.choose"].waitForExistence(timeout: 5), "Ask's context chooser must offer connected external files")
        app.buttons["context.external.choose"].tap()
        let externalSearch = app.textFields["context.external.search"]
        XCTAssertTrue(externalSearch.waitForExistence(timeout: 5)); externalSearch.tap(); externalSearch.typeText(needle)
        app.buttons["context.external.keyboard.dismiss"].tap()
        let reference = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "context.external.option.", title)).firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 10)); reference.tap()
        XCTAssertTrue(app.navigationBars["Choose context"].waitForExistence(timeout: 10))
        app.navigationBars["Choose context"].buttons["Done"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat.reference").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(prompt.value as? String ?? "", contextPrompt, "Choosing context must preserve the prompt and leave it unsent")
        XCTAssertEqual(app.staticTexts.matching(identifier: "YOU").count, priorUserMessages)
        app.buttons["Remove reference"].tap()
        collection(app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1); app.buttons["Stop tracking"].tap()
        XCTAssertTrue(app.staticTexts["Stop tracking this file?"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap(); XCTAssertTrue(row.exists)
        row.press(forDuration: 1); app.buttons["Stop tracking"].tap()
        XCTAssertTrue(app.staticTexts["Stop tracking this file?"].waitForExistence(timeout: 5)); app.buttons["Stop tracking"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        app.buttons["external.open"].tap()
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        if !file.waitForExistence(timeout: 3) {
            let search = app.searchFields.firstMatch
            if !search.exists { app.swipeDown() }
            XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription); search.tap(); search.typeText(title)
        }
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription); file.tap()
        if app.buttons["Open"].exists && app.buttons["Open"].isHittable { app.buttons["Open"].tap() }
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 15), "Stopping tracking preserves the original file and it can be opened again through Files")
        XCTAssertTrue((editor.value as? String ?? "").contains("outside thought."))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "External Markdown reopened through Files in native editor"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["external.editor.done"].tap()
    }
    @MainActor
    func testCancelingAProviderBlockedSearchOpenRejectsItsLateEditorAndAllowsRetryAfterRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let name = "Search open " + String(UUID().uuidString.prefix(6)), token = "lookup" + UUID().uuidString
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Search originals")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent(name + ".md"), bytes = Data(("# " + name + "\n\n" + token + "\n").utf8)
        try bytes.write(to: source)
        app.terminate(); app.open(source)
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 15)); app.buttons["external.editor.done"].tap()
        app.buttons["navigation.search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(token); app.buttons["search.keyboard.dismiss"].tap()
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "search.result.external:", name)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        let identifier = result.identifier
        let indexing = app.descendants(matching: .any).matching(identifier: "search.external.loading").firstMatch
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: indexing)], timeout: 15), .completed)
        let gate = ExternalUISearchOpenGate(url: source)
        NSFileCoordinator.addFilePresenter(gate); var presenting = true
        defer { gate.release(); if presenting { NSFileCoordinator.removeFilePresenter(gate) } }
        result.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [gate.requested], timeout: 5), .completed)
        let cancel = app.buttons["search.external.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Opening a provider file must remain cancelable in Search")
        cancel.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cancel)], timeout: 5), .completed)
        gate.release(); NSFileCoordinator.removeFilePresenter(gate); presenting = false
        let late = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.buttons["external.editor.done"])
        late.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 2), .completed, "A canceled result must not present its editor when provider access later completes")
        XCTAssertTrue(result.waitForExistence(timeout: 10)); result.press(forDuration: 1); app.buttons["Preview"].tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5))
        let referenceGate = ExternalUISearchOpenGate(url: source)
        NSFileCoordinator.addFilePresenter(referenceGate)
        var referencePresenting = true
        defer { referenceGate.release(); if referencePresenting { NSFileCoordinator.removeFilePresenter(referenceGate) } }
        app.buttons["Ask Zerus"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [referenceGate.requested], timeout: 5), .completed)
        let cancelReference = app.buttons["search.reference.cancel"]
        XCTAssertTrue(cancelReference.waitForExistence(timeout: 5)); cancelReference.tap()
        referenceGate.release(); NSFileCoordinator.removeFilePresenter(referenceGate); referencePresenting = false
        let lateReference = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Preview"])
        lateReference.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [lateReference], timeout: 2), .completed, "Cancel keeps the preview open instead of sending a late reference to Ask")
        XCTAssertTrue(app.buttons["Ask Zerus"].isEnabled); app.buttons["Done"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 10)); result.tap()
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 15))
        XCTAssertTrue((app.textViews["note.editor"].value as? String ?? "").contains(token)); app.buttons["external.editor.done"].tap()
        app.terminate(); app.launch(); app.buttons["navigation.search"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(token); app.buttons["search.keyboard.dismiss"].tap()
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 15))
        if !app.buttons["navigation.ask"].exists { openNativeNotes(app) }
        XCTAssertTrue(app.buttons["navigation.ask"].waitForExistence(timeout: 5))
        app.buttons["navigation.ask"].tap()
        let prompt = app.descendants(matching: .any).matching(identifier: "chat.prompt").firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5)); let originalPrompt = prompt.value as? String
        app.buttons["chat.chooseContext"].tap(); app.buttons["context.external.choose"].tap()
        let referenceRow = app.buttons["context.external.option." + String(identifier.dropFirst("search.result.external:".count))]
        let referenceIndexing = app.descendants(matching: .any).matching(identifier: "context.external.indexing").firstMatch
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: referenceIndexing)], timeout: 15), .completed)
        let chooserGate = ExternalUISearchOpenGate(url: source)
        NSFileCoordinator.addFilePresenter(chooserGate); var chooserPresenting = true
        defer { chooserGate.release(); if chooserPresenting { NSFileCoordinator.removeFilePresenter(chooserGate) } }
        let chooserSearch = app.textFields["context.external.search"]
        XCTAssertTrue(chooserSearch.waitForExistence(timeout: 5)); chooserSearch.tap(); chooserSearch.typeText(token)
        app.buttons["context.external.keyboard.dismiss"].tap()
        XCTAssertTrue(referenceRow.waitForExistence(timeout: 5)); referenceRow.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [chooserGate.requested], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["context.external.loading.cancel"].waitForExistence(timeout: 5)); app.buttons["context.external.loading.cancel"].tap()
        chooserGate.release(); NSFileCoordinator.removeFilePresenter(chooserGate); chooserPresenting = false
        let lateChoice = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["External reference"])
        lateChoice.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [lateChoice], timeout: 2), .completed, "A canceled provider read must not select a reference when the provider later finishes")
        referenceRow.tap()
        XCTAssertTrue(app.navigationBars["Choose context"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "context.reference").firstMatch.exists)
        app.navigationBars["Choose context"].buttons["Cancel"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "chat.reference").firstMatch.exists, "Canceling the outer context review must discard the proposed external snapshot")
        XCTAssertEqual(prompt.value as? String, originalPrompt)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    @MainActor
    private func collection(_ app: XCUIApplication) {
        openNativeLibrary(app)
        if app.buttons["library.external"].waitForExistence(timeout: 2) { app.buttons["library.external"].tap() }
        XCTAssertTrue(app.buttons["external.open"].waitForExistence(timeout: 5))
    }
    @MainActor
    private func create(_ app: XCUIApplication, title: String) {
        app.buttons["external.new"].tap()
        let name = app.textFields["external.new.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(title)
        app.buttons["external.new.save"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10)); app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 15), app.debugDescription)
    }
    @MainActor
    func testExternalProjectFolderImagePasteUndoPreviewAndRelaunchUseNativeFiles() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); collection(app)
        let title = "External image " + String(UUID().uuidString.prefix(6)); create(app, title: title)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 50)).image { context in UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 50)) }
        UIPasteboard.general.image = image
        let permission = addUIInterruptionMonitor(withDescription: "Paste this disposable external-note image") { alert in
            if alert.buttons["Allow Paste"].exists { alert.buttons["Allow Paste"].tap(); return true }; return false
        }
        defer { removeUIInterruptionMonitor(permission) }
        func paste() {
            app.buttons["External note actions"].tap(); app.buttons["Clipboard"].tap(); app.buttons["Paste"].tap()
            let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            if system.alerts.buttons["Allow Paste"].waitForExistence(timeout: 2) { system.alerts.buttons["Allow Paste"].tap() }
        }
        paste()
        XCTAssertTrue(app.alerts["External file"].waitForExistence(timeout: 10), "An unselected project cannot receive outside attachment writes")
        app.alerts.buttons["OK"].tap()
        app.buttons["External note actions"].tap(); app.buttons["external.project.menu"].tap()
        XCTAssertTrue(app.buttons["external.project.select"].waitForExistence(timeout: 5)); app.buttons["external.project.select"].tap()
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10), app.debugDescription); app.buttons["Open"].tap()
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 15), app.debugDescription)
        paste()
        let editor = app.textViews["note.editor"]
        let pasted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "\u{fffc}"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [pasted], timeout: 10), .completed)
        app.buttons["Undo"].tap(); XCTAssertFalse((editor.value as? String ?? "").contains("\u{fffc}"))
        app.buttons["Redo"].tap()
        XCTAssertTrue((editor.value as? String ?? "").contains("\u{fffc}"))
        if app.buttons["Dismiss keyboard"].exists { app.buttons["Dismiss keyboard"].tap() }
        func preview() {
            app.buttons["External note actions"].tap(); app.buttons["external.attachments.menu"].tap()
            let attachment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "external.attachment.")).firstMatch
            XCTAssertTrue(attachment.waitForExistence(timeout: 10)); attachment.tap()
            XCTAssertTrue(app.buttons["file.preview.done"].waitForExistence(timeout: 10)); app.buttons["file.preview.done"].tap()
            XCTAssertTrue(app.buttons["external.attachments.done"].waitForExistence(timeout: 5)); app.buttons["external.attachments.done"].tap()
        }
        preview(); app.buttons["external.editor.done"].tap()
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); collection(app)
        let row = app.buttons.containing(.staticText, identifier: title + ".md").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap(); XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 10))
        preview()
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Native external project attachment access survives relaunch"; screenshot.lifetime = .keepAlways; add(screenshot)
        func transfer(_ action: String) {
            app.buttons["External note actions"].tap(); app.buttons[action].tap()
            XCTAssertTrue(app.buttons["external.transfer.review"].waitForExistence(timeout: 10)); app.buttons["external.transfer.review"].tap()
            XCTAssertTrue(app.buttons["external.transfer.confirm"].waitForExistence(timeout: 15), app.debugDescription)
        }
        transfer("external.transfer.copy")
        app.buttons["external.transfer.done"].tap()
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 10), "Canceling the review leaves the original editor open")
        transfer("external.transfer.copy")
        app.buttons["external.transfer.confirm"].tap()
        XCTAssertTrue(app.buttons["external.transfer.openCopy"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["external.transfer.openCopy"].tap()
        XCTAssertTrue(app.buttons["Close note"].waitForExistence(timeout: 10)); app.buttons["Close note"].tap()
        app.buttons["external.transfer.done"].tap()
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 10), "The original stays open after saving its independent vault copy")
        transfer("external.transfer.move")
        app.buttons["external.transfer.done"].tap()
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 10), "Canceling a move does not close or remove the original")
        transfer("external.transfer.move")
        app.buttons["external.transfer.confirm"].tap()
        XCTAssertTrue(app.buttons["external.transfer.openCopy"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["external.transfer.openCopy"].tap()
        XCTAssertTrue(app.buttons["Close note"].waitForExistence(timeout: 10)); app.buttons["Close note"].tap()
        app.buttons["external.transfer.done"].tap()
        XCTAssertTrue(app.buttons["external.open"].waitForExistence(timeout: 10), "Finishing a move closes the removed original’s editor")
        XCTAssertFalse(row.exists, "A completed move removes only this external connection")
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); collection(app)
        XCTAssertFalse(row.exists, "The original remains untracked after relaunch")
    }

    @MainActor
    func testColdSystemFileHandoffSurvivesVaultRestorationAndKeepsOriginalBytes() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        app.buttons["navigation.newNote"].tap()
        let previousTitle = "Previous vault view " + String(UUID().uuidString.prefix(6))
        let field = app.textFields["note.title"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(previousTitle); app.buttons["note.create"].tap()
        XCTAssertTrue(app.textViews["note.editor"].waitForExistence(timeout: 5))
        if app.buttons["Dismiss keyboard"].exists { app.buttons["Dismiss keyboard"].tap() }
        let title = "External handoff " + String(UUID().uuidString.prefix(6))
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(title + ".md")
        let text = "---\nforeign: 'Keep: handoff'\n---\n# " + title + "\n\nA **bold** file opened by iOS.\n"
        try Data(text.utf8).write(to: file, options: .atomic)
        for _ in 0..<2 {
            app.terminate(); app.open(file)
            XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 15), "The iOS file handoff must remain open after the saved vault finishes restoring. " + app.debugDescription)
            app.buttons["External note actions"].tap(); app.buttons["Full Markdown source"].tap()
            XCTAssertEqual(app.textViews["note.editor"].value as? String, text)
            XCTAssertEqual(try Data(contentsOf: file), Data(text.utf8), "Opening a source file must not rewrite it or inject vault metadata")
            app.buttons["external.editor.done"].tap()
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15), "A successful external file handoff must supersede the previously open vault view")
        XCTAssertFalse(app.textViews["note.editor"].exists)
    }

    @MainActor
    func testProviderRefusalKeepsOriginalAndCopyAndPendingMoveResumesAfterRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let title = "External provider " + String(UUID().uuidString.prefix(6)), name = title + ".md"
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        let bytes = Data(("---\nforeign: 'Provider recovery'\n---\n# " + title + "\n\nKeep the exact original until its vault copy is verified.\n").utf8)
        try bytes.write(to: file)
        let presenter = ExternalUITestDeletionRefusal(url: file)
        NSFileCoordinator.addFilePresenter(presenter)
        var presenting = true; defer { if presenting { NSFileCoordinator.removeFilePresenter(presenter) } }
        app.terminate(); app.open(file)
        XCTAssertTrue(app.buttons["external.editor.done"].waitForExistence(timeout: 15))
        app.buttons["External note actions"].tap(); app.buttons["external.transfer.move"].tap()
        XCTAssertTrue(app.buttons["external.transfer.review"].waitForExistence(timeout: 10)); app.buttons["external.transfer.review"].tap()
        XCTAssertTrue(app.buttons["external.transfer.confirm"].waitForExistence(timeout: 15)); app.buttons["external.transfer.confirm"].tap()
        XCTAssertTrue(app.buttons["external.transfer.openCopy"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "original has not been removed")).firstMatch.exists)
        XCTAssertGreaterThan(presenter.requests, 0, "The native app must coordinate its real removal with the sender's presenter")
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        NSFileCoordinator.removeFilePresenter(presenter); presenting = false
        app.buttons["external.transfer.done"].tap(); app.buttons["external.editor.done"].tap()
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); collection(app)
        let pending = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "external.pendingMove.", name)).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 10), app.debugDescription); pending.tap()
        XCTAssertTrue(app.buttons["external.move.export"].waitForExistence(timeout: 5))
        app.buttons["external.move.review"].tap()
        XCTAssertTrue(app.buttons["external.transfer.review"].waitForExistence(timeout: 10)); app.buttons["external.transfer.review"].tap()
        XCTAssertTrue(app.buttons["external.transfer.confirm"].waitForExistence(timeout: 15)); app.buttons["external.transfer.confirm"].tap()
        XCTAssertTrue(app.buttons["external.transfer.openCopy"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["external.transfer.openCopy"].tap()
        XCTAssertTrue(app.buttons["Close note"].waitForExistence(timeout: 10)); app.buttons["Close note"].tap()
        app.buttons["external.transfer.done"].tap()
        XCTAssertTrue(app.buttons["external.open"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(pending.exists); XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Provider-denied move recovered through native Pending moves"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

}


/// A real presenter in the sender process refuses deletion; the app must keep
/// both the original and its actual vault copy, then recover on another launch.
private final class ExternalUITestDeletionRefusal: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let lock = NSLock()
    private var count = 0
    var requests: Int { lock.lock(); defer { lock.unlock() }; return count }
    init(url: URL) { presentedItemURL = url; super.init(); presentedItemOperationQueue.maxConcurrentOperationCount = 1 }
    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        lock.lock(); count += 1; lock.unlock()
        completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError))
    }
}

private final class ExternalUISearchOpenGate: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    let requested = XCTestExpectation(description: "The source process is asked for the search-open read")
    private let lock = NSLock()
    private var waiting: [@Sendable (Error?) -> Void] = []
    private var released = false
    private var reported = false
    init(url: URL) { presentedItemURL = url; super.init(); presentedItemOperationQueue.maxConcurrentOperationCount = 1 }
    func savePresentedItemChanges(completionHandler: @escaping @Sendable (Error?) -> Void) {
        lock.lock(); let first = !reported; reported = true
        if released { lock.unlock(); completionHandler(nil) }
        else { waiting.append(completionHandler); lock.unlock() }
        if first { requested.fulfill() }
    }
    func release() { lock.lock(); released = true; let callbacks = waiting; waiting = []; lock.unlock(); callbacks.forEach { $0(nil) } }
}
