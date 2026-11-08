import XCTest

final class NativeWorkspaceTests: NativeJourneyTestCase {
    @MainActor
    func testTaskDraftCloseRelaunchResumeSaveAndReviewedDiscardKeepVaultTaskUnchanged() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let title = "Draft lifecycle " + String(UUID().uuidString.prefix(6)), changed = title + " unsaved"
        func tap(_ element: XCUIElement) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, app.debugDescription); element.tap()
        }
        func field() -> XCUIElement { app.descendants(matching: .any).matching(identifier: "task.title").firstMatch }
        func draft(_ name: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.draft.", name)).firstMatch }
        func tasks() { tap(app.buttons["navigation.tasks"]); tap(app.buttons["tasks.drafts"]) }
        tap(app.buttons["navigation.tasks"]); tap(app.buttons["Settings"]); tap(app.buttons["New task"])
        tap(field()); field().typeText(title); tap(app.buttons["task.keyboard.dismiss"])
        tap(app.buttons["task.cancel"])
        app.terminate(); app.launch(); tasks(); tap(draft(title))
        XCTAssertEqual(field().value as? String, title)
        attach(app, name: "Private native task draft survives app restart")
        tap(app.buttons["task.save"])
        XCTAssertTrue(app.navigationBars["Task drafts"].waitForExistence(timeout: 10))
        XCTAssertFalse(draft(title).exists); tap(app.buttons["tasks.drafts.done"])
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "task.open.", title)).firstMatch
        tap(row); tap(field()); field().typeKey("a", modifierFlags: .command); field().typeText(changed)
        tap(app.buttons["task.keyboard.dismiss"]); tap(app.buttons["task.cancel"])
        app.terminate(); app.launch(); tasks(); tap(draft(changed))
        XCTAssertEqual(field().value as? String, changed)
        func revealDiscard() -> XCUIElement {
            let button = app.buttons["task.draft.discard"]
            for _ in 0..<6 {
                let window = app.windows.firstMatch.frame, frame = button.frame
                if button.isHittable && frame.minY > window.minY + 120 && frame.maxY < window.maxY - 90 { return button }
                app.collectionViews.element(boundBy: max(0, app.collectionViews.count - 1)).swipeUp()
            }
            return button
        }
        tap(revealDiscard()); tap(app.alerts.buttons["Cancel"])
        XCTAssertTrue(app.buttons["task.draft.discard"].exists, "Cancel retains the recovered form")
        XCTAssertEqual(field().value as? String, changed)
        attach(app, name: "Cancel keeps the recovered task form open")
        tap(revealDiscard()); tap(app.alerts.buttons["Discard draft"])
        XCTAssertTrue(app.navigationBars["Task drafts"].waitForExistence(timeout: 10)); XCTAssertFalse(draft(changed).exists)
        tap(app.buttons["tasks.drafts.done"]); tap(row)
        XCTAssertEqual(field().value as? String, title, "Discard cannot replace the canonical task")
        tap(app.buttons["task.cancel"]); app.terminate(); app.launch(); tasks()
        XCTAssertFalse(draft(changed).exists); XCTAssertFalse(draft(title).exists)
        attach(app, name: "Explicit task-draft discard survives restart")
    }

    @MainActor
    func testNativeBulkReviewCancelPinUndoRedoPropertiesAndRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let suffix = String(UUID().uuidString.prefix(6)), prefix = "Batch " + suffix, fieldName = "Owner " + suffix
        func tap(_ button: XCUIElement) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, app.debugDescription); button.tap()
        }
        func create(_ title: String, definition: Bool = false) {
            tap(app.buttons["navigation.newNote"]); let field = app.textFields["note.title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title); app.buttons["note.create"].tap()
            let editor = app.textViews["note.editor"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("Bulk actions preserve this writing."); app.buttons["Dismiss keyboard"].tap()
            if definition {
                app.buttons["Note information"].tap(); app.buttons["schema.manage"].tap(); tap(app.buttons["schema.add"])
                let name = app.textFields["schema.name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(fieldName)
                tap(app.buttons["schema.type"]); tap(app.buttons["Number"])
                app.buttons["schema.save"].tap(); tap(app.buttons["schema.done"]); tap(app.buttons["note.info.done"])
            }
            tap(app.buttons["Close note"])
        }
        create(prefix + " Alpha", definition: true); create(prefix + " Beta")
        func selectPair() {
            func reveal(_ button: XCUIElement, direction: Bool) {
                for _ in 0..<12 where !button.isHittable { if direction { app.swipeUp() } else { app.swipeDown() } }
                tap(button)
            }
            openNativeCollectionSettings(app); reveal(app.buttons["bulk.select"], direction: false)
            for title in [prefix + " Alpha", prefix + " Beta"] {
                reveal(app.buttons["bulk.note." + title + ".md"], direction: true)
            }
            reveal(app.buttons["bulk.actions"], direction: false)
        }
        selectPair(); tap(app.buttons["Pin"]); tap(app.buttons["bulk.review"]); tap(app.buttons["bulk.cancel"])
        XCTAssertTrue(app.buttons["bulk.actions"].waitForExistence(timeout: 5)); tap(app.buttons["bulk.actions"]); tap(app.buttons["Pin"]); tap(app.buttons["bulk.review"])
        attach(app, name: "Native bulk change review")
        tap(app.buttons["bulk.apply"]); openNativeBulkHistory(app)
        let undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bulk.undo.")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        let pinRecordID = undo.identifier.replacingOccurrences(of: "bulk.undo.", with: "")
        tap(undo); XCTAssertTrue(app.navigationBars["Review changes"].waitForExistence(timeout: 5)); tap(app.navigationBars["Review changes"].buttons.firstMatch)
        XCTAssertTrue(app.navigationBars["Recent actions"].waitForExistence(timeout: 5))
        let canceledReview = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Review changes"])
        XCTAssertEqual(XCTWaiter.wait(for: [canceledReview], timeout: 10), .completed, app.debugDescription)
        tap(app.buttons["bulk.undo." + pinRecordID])
        XCTAssertTrue(app.navigationBars["Review changes"].waitForExistence(timeout: 10), app.debugDescription)
        attach(app, name: "Bulk undo review reopened after canceling its first preview")
        tap(app.buttons["bulk.apply"])
        let pinRedo = app.buttons["bulk.redo." + pinRecordID]
        XCTAssertTrue(pinRedo.waitForExistence(timeout: 10), app.debugDescription)
        tap(pinRedo); tap(app.buttons["bulk.apply"]); closeNativeBulkHistory(app)
        selectPair(); tap(app.buttons["Edit properties and relations"]); tap(app.buttons["bulk.property." + fieldName.lowercased()])
        tap(app.buttons["bulk.property.value"])
        let value = app.textFields["property.value"].exists ? app.textFields["property.value"] : app.textViews["property.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5)); value.tap(); value.typeText("42.5"); XCTAssertEqual(value.value as? String, "42.5", "The actual numeric input must remain open while typing")
        app.buttons["property.save"].tap()
        XCTAssertTrue(app.buttons["bulk.property.value"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["bulk.property.value"].label.contains("42.5"), app.debugDescription)
        tap(app.buttons["bulk.property.use"]); tap(app.buttons["bulk.review"]); tap(app.buttons["bulk.apply"])
        app.terminate(); app.launch(); openNativeBulkHistory(app); tap(undo); tap(app.buttons["bulk.apply"])
        attach(app, name: "Durable native bulk history after relaunch and property undo")
        closeNativeBulkHistory(app)
    }

    @MainActor
    func testCollectionPropertyFiltersSortAndFolderScopeKeepNotesUnchangedAfterRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let suffix = String(UUID().uuidString.prefix(6)), prefix = "Collection " + suffix
        let first = prefix + " Alpha", second = prefix + " Beta"
        func create(_ title: String, stage: String) {
            XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
            let field = app.textFields["note.title"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title)
            app.buttons["note.folder"].tap(); app.buttons["Inbox"].tap(); app.buttons["note.create"].tap()
            let editor = app.textViews["note.editor"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("Collection body must stay intact.")
            app.buttons["Dismiss keyboard"].tap(); app.buttons["Note information"].tap(); app.buttons["property.add"].tap()
            let name = app.textFields["property.name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Stage")
            let value = app.textFields["property.value"].exists ? app.textFields["property.value"] : app.textViews["property.value"]
            value.tap(); value.typeText(stage); app.buttons["property.save"].tap()
            XCTAssertTrue(app.buttons["property.stage"].waitForExistence(timeout: 5)); app.buttons["Done"].tap(); app.buttons["Close note"].tap()
        }
        create(first, stage: "Ready " + suffix); create(second, stage: "Later " + suffix)
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(prefix)
        let alpha = app.buttons.containing(.staticText, identifier: first).firstMatch
        let beta = app.buttons.containing(.staticText, identifier: second).firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 5)); XCTAssertTrue(beta.waitForExistence(timeout: 5))
        openNativeFilters(app)
        app.buttons["collection.property.add"].tap(); app.buttons["Stage"].tap()
        XCTAssertTrue(app.navigationBars["Stage"].waitForExistence(timeout: 5))
        app.buttons["collection.property.mode"].tap(); XCTAssertTrue(app.buttons["Selected values"].waitForExistence(timeout: 5)); app.buttons["Selected values"].tap()
        let ready = app.switches["collection.value.text:Ready " + suffix]
        XCTAssertTrue(ready.waitForExistence(timeout: 5)); ready.switches.firstMatch.tap()
        app.buttons["collection.property.apply"].tap(); closeNativeFilters(app)
        XCTAssertTrue(alpha.waitForExistence(timeout: 5)); XCTAssertFalse(beta.exists)
        attach(app, name: "Native collection property filter while searching")
        openNativeFilters(app); app.buttons["collection.property.edit.stage"].tap()
        XCTAssertTrue(app.navigationBars["Stage"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["collection.property.edit.stage"].waitForExistence(timeout: 5))
        app.buttons["collection.clear"].tap()
        app.buttons["collection.sort"].tap(); app.buttons["Title: Z–A"].tap()
        closeNativeFilters(app)
        XCTAssertTrue(beta.waitForExistence(timeout: 5)); XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertLessThan(beta.frame.minY, alpha.frame.minY)
        openNativeFilters(app); app.buttons["collection.folders"].tap()
        let inbox = app.switches["collection.folder.Inbox"]; XCTAssertTrue(inbox.waitForExistence(timeout: 5)); inbox.switches.firstMatch.tap()
        app.navigationBars["Folders"].buttons.firstMatch.tap(); closeNativeFilters(app)
        XCTAssertTrue(alpha.waitForExistence(timeout: 5)); alpha.tap()
        let editor = app.textViews["note.editor"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue((editor.value as? String ?? "").contains("Collection body must stay intact."))
        app.buttons["Close note"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        openNativeLibrary(app)
        let folder = app.buttons.containing(.staticText, identifier: "Inbox").firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5)); folder.tap()
        openNativeCollectionSettings(app)
        XCTAssertTrue(app.buttons["collection.filters"].waitForExistence(timeout: 5))
        attach(app, name: "Library folder collection has native sort and filters in Settings")
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.navigationBars["Inbox"].buttons.firstMatch.tap()
        app.buttons["library.links"].tap(); openNativeFilters(app)
        XCTAssertTrue(app.buttons["collection.sort"].waitForExistence(timeout: 5)); closeNativeFilters(app)
        app.navigationBars["Saved links"].buttons.firstMatch.tap()
        app.buttons["library.files"].tap(); openNativeFilters(app)
        XCTAssertTrue(app.buttons["collection.date"].waitForExistence(timeout: 5))
        attach(app, name: "File library shares native collection filters")
        closeNativeFilters(app)
    }

    @MainActor
    func testReviewedNoteRenameCancelContinuedEditingIncomingLinksAndRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let suffix = String(UUID().uuidString.prefix(6)), old = "Rename source " + suffix, new = "Renamed thought " + suffix, incoming = "Rename reference " + suffix
        let editor = app.textViews["note.editor"]
        func create(_ title: String, body: String, source: Bool = false) {
            XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
            let field = app.textFields["note.title"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title); app.buttons["note.create"].tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            if source { app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap(); editor.tap(); editor.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command) }
            editor.typeText(body); app.buttons["Dismiss keyboard"].tap(); app.buttons["Close note"].tap()
        }
        func open(_ title: String) {
            XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 10))
            let search = app.searchFields.firstMatch
            if !search.exists { app.swipeDown() }
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeKey("a", modifierFlags: .command); search.typeText(title)
            let result = app.buttons.containing(.staticText, identifier: title).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap(); XCTAssertTrue(editor.waitForExistence(timeout: 5))
        }
        func reviewRename() {
            app.buttons["Note actions"].tap(); XCTAssertTrue(app.buttons["note.rename"].waitForExistence(timeout: 5)); app.buttons["note.rename"].tap()
            let field = app.textFields["rename.title"]; XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeKey("a", modifierFlags: .command); field.typeText(new)
            app.buttons["rename.review"].tap(); XCTAssertTrue(app.buttons["rename.commit"].waitForExistence(timeout: 15))
        }
        create(old, body: "A body retained through renaming.")
        create(incoming, body: "Follow [[" + old + "|Keep this label]].", source: true)
        open(old); reviewRename(); attach(app, name: "Reviewed title and Markdown filename change")
        app.buttons["rename.cancel"].tap(); XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue((editor.value as? String ?? "").contains(old))
        reviewRename(); app.buttons["rename.commit"].tap()
        XCTAssertTrue(app.navigationBars[new].waitForExistence(timeout: 15)); XCTAssertTrue((editor.value as? String ?? "").contains(new))
        editor.tap(); editor.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command); editor.typeText("\nAdded after rename.")
        app.buttons["Dismiss keyboard"].tap(); app.buttons["Close note"].tap()
        app.terminate(); app.launch(); open(new)
        XCTAssertTrue((editor.value as? String ?? "").contains("Added after rename.")); app.buttons["Close note"].tap()
        open(incoming)
        let link = app.links["Keep this label"]
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue((editor.value as? String ?? "").contains(new))
        XCTAssertTrue((editor.value as? String ?? "").contains("Added after rename."))
        attach(app, name: "Incoming link opens the renamed note after relaunch")
        editor.tap(); editor.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command); editor.typeText("\nSaved through native Back.")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.4)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.4)))
        XCTAssertTrue(app.navigationBars[incoming].waitForExistence(timeout: 10))
        app.buttons["Note actions"].tap(); XCTAssertTrue(app.buttons["note.navigation"].waitForExistence(timeout: 5)); app.buttons["note.navigation"].tap()
        XCTAssertTrue(app.buttons["note.navigation.forward"].waitForExistence(timeout: 5)); app.buttons["note.navigation.forward"].tap()
        XCTAssertTrue(app.navigationBars[new].waitForExistence(timeout: 10)); XCTAssertTrue((editor.value as? String ?? "").contains("Saved through native Back."))
        attach(app, name: "Native forward history returns to the renamed note")
        app.buttons["Close note"].tap(); XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 10))

    }
    @MainActor
    func testSavedVaultsCreateSwitchRenameRemoveAndRelaunchKeepSeparateNotes() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        if app.buttons["Close note"].waitForExistence(timeout: 3) { app.buttons["Close note"].tap() }
        let suffix = String(UUID().uuidString.prefix(6)), a = "Personal " + suffix, b = "Projects " + suffix
        func vaults() {
            XCTAssertTrue(app.buttons["navigation.notes"].waitForExistence(timeout: 15)); openNativeLibrary(app)
            XCTAssertTrue(app.buttons["library.vaults"].waitForExistence(timeout: 5)); app.buttons["library.vaults"].tap()
            XCTAssertTrue(app.buttons["vaults.create"].waitForExistence(timeout: 5))
        }
        func createVault(_ name: String) {
            app.buttons["vaults.create"].tap()
            let field = app.alerts.textFields["Vault name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(name); app.alerts.buttons["Create"].tap()
            XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        }
        func createNote(_ title: String, body: String) {
            app.buttons["navigation.newNote"].tap(); let field = app.textFields["note.title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title); app.buttons["note.create"].tap()
            let editor = app.textViews["note.editor"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText(body)
            app.buttons["Dismiss keyboard"].tap(); app.buttons["Close note"].tap()
        }
        vaults(); createVault(a)
        createNote("Personal evidence " + suffix, body: "Only in the personal vault.")
        vaults(); createVault(b)
        createNote("Project evidence " + suffix, body: "Only in the project vault.")
        vaults()
        let personal = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "vault.saved.", a)).firstMatch
        XCTAssertTrue(personal.waitForExistence(timeout: 5)); personal.tap()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        openNativeNotes(app)
        XCTAssertTrue(app.staticTexts["Personal evidence " + suffix].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Project evidence " + suffix].exists)
        vaults()
        app.buttons["Manage " + a].tap(); app.buttons["Rename in list"].tap()
        let name = app.alerts.textFields["Vault name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: a.count)); name.typeText("My thoughts " + suffix); app.alerts.buttons["Save"].tap()
        attach(app, name: "Saved vaults with separate local folders")
        app.buttons["Done"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); XCTAssertTrue(app.staticTexts["Personal evidence " + suffix].exists)
        vaults()
        app.buttons["Manage " + b].tap(); app.buttons["Remove from list"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Manage " + b].exists)
        app.buttons["Manage " + b].tap(); app.buttons["Remove from list"].tap()
        app.buttons["Remove from list"].tap()
        XCTAssertFalse(app.buttons["Manage " + b].exists)
        XCTAssertTrue(app.buttons["Manage My thoughts " + suffix].exists)
        app.buttons["Done"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); XCTAssertTrue(app.staticTexts["Personal evidence " + suffix].exists)
    }
    @MainActor
    func testNativeExportsSaveCopyPreviewAllFormatsAndRetainTheNoteAfterRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let title = "Export evidence " + String(UUID().uuidString.prefix(6))
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
        app.textFields["note.title"].tap(); app.textFields["note.title"].typeText(title); app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("A portable thought that must survive exporting."); app.buttons["Dismiss keyboard"].tap()
        app.buttons["Note actions"].tap(); app.buttons["note.export"].tap()
        XCTAssertTrue(app.buttons["export.prepare"].waitForExistence(timeout: 5)); app.buttons["export.prepare"].tap()
        XCTAssertTrue(app.staticTexts[title + ".pdf"].waitForExistence(timeout: 15))
        app.buttons["export.preview"].tap()
        let closePreview = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(closePreview.waitForExistence(timeout: 10)); attach(app, name: "Native PDF export opened in system preview"); closePreview.tap()
        XCTAssertTrue(app.buttons["export.prepare"].waitForExistence(timeout: 5))
        app.buttons["export.save"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        attach(app, name: "Native PDF export system save picker")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: app.buttons["export.save"])
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["Saved a copy to Files"].exists)
        func saveCopy(_ format: String) {
            app.buttons["export.save"].tap()
            XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
            app.buttons["Save"].tap()
            XCTAssertTrue(app.staticTexts["Saved a copy to Files"].waitForExistence(timeout: 15))
            attach(app, name: "Native " + format + " copy saved through Files")
        }
        saveCopy("PDF")
        let picker = app.buttons["export.format"]
        func chooseFormat(_ label: String) {
            picker.tap()
            let choice = app.buttons[label]
            XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", label), object: picker)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        }
        chooseFormat("Word document (.docx)"); app.buttons["export.prepare"].tap()
        XCTAssertTrue(app.staticTexts[title + ".docx"].waitForExistence(timeout: 15)); attach(app, name: "Native editable Word export ready to share")
        app.buttons["export.preview"].tap(); XCTAssertTrue(closePreview.waitForExistence(timeout: 10)); attach(app, name: "Native Word export opened in system preview"); closePreview.tap()
        saveCopy("Word")
        chooseFormat("Web page (.html)")
        let properties = app.switches["export.properties"]; XCTAssertTrue(properties.exists)
        properties.switches.firstMatch.tap()
        XCTAssertEqual(properties.value as? String, "0", "The export must use the requested property inclusion setting")
        app.buttons["export.prepare"].tap(); XCTAssertTrue(app.staticTexts[title + ".html"].waitForExistence(timeout: 15)); XCTAssertTrue(app.buttons["export.share"].exists)
        attach(app, name: "Native self-contained HTML export with optional properties")
        app.buttons["export.preview"].tap(); XCTAssertTrue(closePreview.waitForExistence(timeout: 10)); attach(app, name: "Native HTML export opened in system preview"); closePreview.tap()
        saveCopy("HTML")
        app.buttons["export.done"].tap(); XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue((editor.value as? String ?? "").contains("must survive exporting")); app.buttons["Close note"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); let search = app.searchFields.firstMatch; search.tap(); search.typeText(title)
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8)); result.tap(); XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue((editor.value as? String ?? "").contains("must survive exporting"))
    }

    @MainActor
    func testUnifiedSearchBodyTaskFiltersRecentRelaunchAndAskPreservesPromptWithoutSending() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let suffix = String(UUID().uuidString.prefix(6)).lowercased(), title = "Search evidence " + suffix, token = "quasar" + suffix, taskTitle = "Review " + token
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
        app.textFields["note.title"].tap(); app.textFields["note.title"].typeText(title); app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        let original = "# " + title + "\n\nA native body match for " + token + ". [**Roadmap** `code`](#zerus-note:zerus%3Apreview-hidden-target%7CRoadmap%20code) and [[zerus:preview-hidden-target|Readable alias]]."
        editor.tap(); editor.typeKey("a", modifierFlags: .command); editor.typeText(original)
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        app.buttons["Dismiss keyboard"].tap(); app.buttons["Close note"].tap()
        app.buttons["navigation.tasks"].tap(); app.buttons["Settings"].tap(); app.buttons["New task"].tap()
        let taskField = app.descendants(matching: .any).matching(identifier: "task.title").firstMatch
        XCTAssertTrue(taskField.waitForExistence(timeout: 5)); taskField.tap(); taskField.typeText(taskTitle); app.buttons["task.keyboard.dismiss"].tap(); app.buttons["task.save"].tap()
        app.buttons["navigation.ask"].tap()
        app.buttons["Settings"].tap(); XCTAssertTrue(app.buttons["New conversation"].waitForExistence(timeout: 5)); app.buttons["New conversation"].tap()
        let prompt = app.descendants(matching: .any).matching(identifier: "chat.prompt").firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5)); prompt.tap(); prompt.typeKey("a", modifierFlags: .command); prompt.typeText("Keep this prompt " + suffix)
        app.buttons["chat.keyboard.dismiss"].tap()
        app.buttons["navigation.search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(token)
        XCTAssertTrue(app.buttons["search.keyboard.dismiss"].waitForExistence(timeout: 5)); app.buttons["search.keyboard.dismiss"].tap()
        XCTAssertEqual(search.value as? String, token, "Dismissing the keyboard must retain the search query")
        let noteResult = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        let taskResult = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", taskTitle)).firstMatch
        XCTAssertTrue(noteResult.waitForExistence(timeout: 10)); XCTAssertTrue(taskResult.waitForExistence(timeout: 10))
        XCTAssertTrue(noteResult.label.contains("Roadmap code and Readable alias."), noteResult.label)
        XCTAssertFalse(noteResult.label.contains("preview-hidden-target"), noteResult.label)
        attach(app, name: "Unified native search shows readable formatted and wiki link labels")
        noteResult.tap(); XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue((editor.value as? String ?? "").contains(token)); app.buttons["Close note"].tap()
        XCTAssertTrue(app.buttons["search.filters"].waitForExistence(timeout: 5)); app.buttons["search.filters"].tap()
        let collection = app.descendants(matching: .any).matching(identifier: "search.collection").firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 5)); collection.tap(); app.buttons["Tasks"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(taskResult.waitForExistence(timeout: 5)); XCTAssertFalse(noteResult.exists)
        taskResult.tap(); XCTAssertTrue(taskField.waitForExistence(timeout: 5)); XCTAssertEqual(taskField.value as? String, taskTitle); app.buttons["task.cancel"].tap()
        app.buttons["search.filters"].tap(); app.buttons["Reset filters"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(noteResult.waitForExistence(timeout: 5)); noteResult.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Ask Zerus about this"].waitForExistence(timeout: 5)); app.buttons["Ask Zerus about this"].tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 5)); XCTAssertTrue((prompt.value as? String ?? "").contains("Keep this prompt " + suffix)); XCTAssertTrue((prompt.value as? String ?? "").contains(title))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "1 note selected")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["YOU"].exists, "Preparing search context must not send a message")
        attach(app, name: "Search prepares explicit AI context and retains the existing prompt")
        app.terminate(); app.launch(); app.buttons["navigation.search"].tap()
        XCTAssertTrue(noteResult.waitForExistence(timeout: 10)); XCTAssertTrue(taskResult.waitForExistence(timeout: 5))
        XCTAssertTrue(noteResult.label.contains("Roadmap code and Readable alias."), noteResult.label)
        XCTAssertFalse(noteResult.label.contains("preview-hidden-target"), noteResult.label)
        noteResult.tap(); XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        XCTAssertEqual(editor.value as? String, original, "Browsing excerpts and relaunching must preserve the original Markdown")
        attach(app, name: "Search preview and relaunch preserve original Markdown destinations")
        app.buttons["Close note"].tap()
    }

    @MainActor
    func testNativeTaskListsScheduleCategoriesSupportingNoteReturnCompletionAndRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let suffix = String(UUID().uuidString.prefix(6)), support = "Task evidence " + suffix, title = "Plan native check " + suffix
        let list = "Projects " + suffix, category = "Research " + suffix, general = "Inbox " + suffix
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
        app.textFields["note.title"].tap(); app.textFields["note.title"].typeText(support); app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("Evidence for the task."); app.buttons["Dismiss keyboard"].tap(); app.buttons["Close note"].tap()
        app.buttons["navigation.tasks"].tap(); app.buttons["Settings"].tap(); XCTAssertTrue(app.buttons["tasks.manage"].waitForExistence(timeout: 5)); app.buttons["tasks.manage"].tap()
        func name(_ value: String, replacing: Bool = false) {
            let field = app.textFields["tasks.collection.name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
            if replacing { field.typeKey("a", modifierFlags: .command) }
            field.typeText(value); app.buttons["tasks.collection.save"].tap()
            XCTAssertTrue(app.buttons["tasks.list.add"].waitForExistence(timeout: 10))
        }
        app.buttons["tasks.general.rename"].tap(); name(general, replacing: true)
        app.buttons["tasks.list.add"].tap(); name(list)
        app.buttons["tasks.category.add"].tap(); name(category)
        attach(app, name: "Native task list and category management")
        app.navigationBars.buttons["Tasks"].tap()
        app.buttons["Settings"].tap(); XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 5)); app.buttons["New task"].tap()
        let taskTitle = app.descendants(matching: .any).matching(identifier: "task.title").firstMatch
        XCTAssertTrue(taskTitle.waitForExistence(timeout: 5)); taskTitle.tap(); taskTitle.typeText(title)
        XCTAssertTrue(app.buttons["task.keyboard.dismiss"].waitForExistence(timeout: 5)); app.buttons["task.keyboard.dismiss"].tap()
        func pick(_ identifier: String, _ label: String) {
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if !element.isHittable { app.swipeUp() }
            element.tap(); XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5)); app.buttons[label].tap()
        }
        pick("task.list", list); pick("task.priority", "High"); pick("task.category", category)
        app.buttons["task.schedule"].tap(); attach(app, name: "Native quick-schedule menu"); XCTAssertTrue(app.buttons["Tomorrow"].waitForExistence(timeout: 5)); app.buttons["Tomorrow"].tap()
        let due = app.switches["task.hasDueDate"]
        if !due.isHittable { app.swipeUp() }
        XCTAssertTrue(due.waitForExistence(timeout: 5)); due.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let choose = app.buttons["task.chooseNotes"]; if !choose.isHittable { app.swipeUp() }; choose.tap()
        let note = app.buttons[support]
        let pickerSearch = app.textFields["note.picker.search"]; XCTAssertTrue(pickerSearch.waitForExistence(timeout: 5)); pickerSearch.tap(); pickerSearch.typeText(support)
        XCTAssertTrue(app.navigationBars["Supporting notes"].buttons["Done"].isHittable, "Picker actions must remain reachable while searching with the keyboard")
        XCTAssertTrue(note.waitForExistence(timeout: 5)); note.tap(); app.buttons["Done"].tap()
        let linked = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.note.", support)).firstMatch
        XCTAssertTrue(linked.waitForExistence(timeout: 5)); linked.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10)); XCTAssertTrue((editor.value as? String ?? "").contains("Evidence for the task.")); app.buttons["Close note"].tap()
        XCTAssertTrue(app.buttons["task.save"].waitForExistence(timeout: 10)); attach(app, name: "Return from supporting note to native task planning"); app.buttons["task.save"].tap()
        app.segmentedControls.buttons["All"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.open.", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let completed = app.switches["task.completed"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5)); completed.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); app.buttons["task.save"].tap()
        app.terminate(); app.launch(); app.buttons["navigation.tasks"].tap(); app.segmentedControls.buttons["Completed"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.switches["task.completed"].waitForExistence(timeout: 5)); XCTAssertEqual(app.switches["task.completed"].value as? String, "1")
        XCTAssertTrue(app.switches["task.hasDueDate"].exists); XCTAssertEqual(app.switches["task.hasDueDate"].value as? String, "1")
        attach(app, name: "Completed task preserves scheduling, list and category after relaunch")
    }

    @MainActor
    func testSavedLinkCreationNotesAddressCancelUpdateFilingBrowserAndRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let suffix = String(UUID().uuidString.prefix(6)).lowercased(), title = "Native link " + suffix
        let first = "https://example.com/native-" + suffix, updated = first + "?saved=yes"
        func links() {
            XCTAssertTrue(app.buttons["navigation.notes"].waitForExistence(timeout: 15)); openNativeLibrary(app)
            XCTAssertTrue(app.buttons["library.links"].waitForExistence(timeout: 5)); app.buttons["library.links"].tap()
            XCTAssertTrue(app.buttons["savedlink.add"].waitForExistence(timeout: 5))
        }
        func address() -> XCUIElement {
            let fields = app.descendants(matching: .any).matching(identifier: "savedlink.address")
            return fields.firstMatch
        }
        func replaceAddress(_ value: String) {
            let field = address(); XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
            field.typeKey("a", modifierFlags: .command); field.typeText(value)
        }
        func row() -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "savedlink.note.", title)).firstMatch }
        links(); app.buttons["savedlink.add"].tap()
        let field = address(); XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText(first)
        app.textFields["savedlink.title"].tap(); app.textFields["savedlink.title"].typeText(title)
        app.buttons["savedlink.save"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15)); XCTAssertTrue(app.buttons["savedlink.edit"].waitForExistence(timeout: 5))
        XCTAssertFalse((editor.value as? String ?? "").contains(first), "The managed URL belongs in the link card, outside the editable prose")
        editor.tap(); editor.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: .command); editor.typeText("\nNotes worth keeping."); app.buttons["Dismiss keyboard"].tap()
        app.buttons["savedlink.edit"].tap(); replaceAddress(updated); app.buttons["savedlink.cancel"].tap()
        XCTAssertTrue(app.links["savedlink.open"].waitForExistence(timeout: 5) || app.buttons["savedlink.open"].waitForExistence(timeout: 5))
        let open = app.descendants(matching: .any).matching(identifier: "savedlink.open").firstMatch
        XCTAssertTrue(open.label.contains(first)); XCTAssertFalse(open.label.contains("saved=yes"))
        app.buttons["savedlink.edit"].tap(); replaceAddress(updated); app.buttons["savedlink.save"].tap()
        XCTAssertTrue(app.buttons["savedlink.edit"].waitForExistence(timeout: 15)); XCTAssertTrue(open.label.contains(updated))
        XCTAssertTrue((editor.value as? String ?? "").contains("Notes worth keeping.")); attach(app, name: "Native saved-link card and notes after address update")
        open.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15), "The explicit Open action must hand the saved URL to the system browser")
        app.activate(); XCTAssertTrue(app.buttons["savedlink.edit"].waitForExistence(timeout: 15))
        app.buttons["Note actions"].tap(); app.buttons["Move to folder"].tap()
        let folder = "Bookmarks " + suffix
        XCTAssertTrue(app.textFields["move.newFolder"].waitForExistence(timeout: 10)); app.textFields["move.newFolder"].tap(); app.textFields["move.newFolder"].typeText(folder)
        app.buttons["move.review"].tap()
        XCTAssertTrue(app.buttons["maintenance.confirm"].waitForExistence(timeout: 15)); attach(app, name: "Saved-link filing review"); app.buttons["maintenance.confirm"].tap()
        XCTAssertTrue(app.buttons["savedlink.add"].waitForExistence(timeout: 15))
        app.terminate(); app.launch(); links()
        XCTAssertTrue(row().waitForExistence(timeout: 10)); row().tap()
        XCTAssertTrue(app.buttons["savedlink.edit"].waitForExistence(timeout: 10)); XCTAssertTrue(open.label.contains(updated))
        XCTAssertTrue((editor.value as? String ?? "").contains("Notes worth keeping.")); XCTAssertTrue(app.staticTexts[folder].exists)
        attach(app, name: "Filed saved link preserves its address and notes after relaunch")
    }

    @MainActor
    func testVaultHistorySettingsReviewCancelPersistenceAndDestructiveConfirmationCancel() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let title = "History settings " + String(UUID().uuidString.prefix(6))
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
        let titleField = app.textFields["note.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5)); titleField.tap(); titleField.typeText(title); app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("Preserved during settings and cleanup reviews."); app.buttons["Dismiss keyboard"].tap(); app.buttons["Close note"].tap()
        func settings() {
            openNativeLibrary(app)
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5)); app.buttons["Settings"].tap()
            XCTAssertTrue(app.buttons["settings.history"].waitForExistence(timeout: 5)); app.buttons["settings.history"].tap()
            XCTAssertTrue(app.switches["history.management.enabled"].waitForExistence(timeout: 15))
        }
        func unlimited() {
            app.descendants(matching: .any).matching(identifier: "history.management.limit").firstMatch.tap()
            XCTAssertTrue(app.buttons["Unlimited"].waitForExistence(timeout: 5)); app.buttons["Unlimited"].tap()
        }
        let toggle = app.switches["history.management.enabled"], review = app.buttons["history.management.settings"], commit = app.buttons["history.management.commit"], cancel = app.buttons["history.management.cancel"]
        settings()
        let initial = toggle.value as? String ?? "1", changed = initial == "1" ? "0" : "1"
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); XCTAssertEqual(toggle.value as? String, changed); unlimited()
        XCTAssertTrue(review.waitForExistence(timeout: 5)); review.tap()
        XCTAssertTrue(commit.waitForExistence(timeout: 15)); attach(app, name: "Vault-wide history settings review"); cancel.tap()
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); settings()
        XCTAssertEqual(toggle.value as? String, initial, "Cancel must not persist a new vault-wide capture policy")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); unlimited()
        XCTAssertTrue(review.waitForExistence(timeout: 5)); review.tap()
        XCTAssertTrue(commit.waitForExistence(timeout: 15)); commit.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 15)); XCTAssertEqual(toggle.value as? String, changed)
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); settings()
        XCTAssertEqual(toggle.value as? String, changed, "Capture settings must survive relaunch")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "history.management.limit").firstMatch.label.contains("Unlimited"))
        // Leave this isolated UI vault recording history for sibling journeys.
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); XCTAssertTrue(review.waitForExistence(timeout: 5)); review.tap()
            XCTAssertTrue(commit.waitForExistence(timeout: 15)); commit.tap()
            XCTAssertTrue(toggle.waitForExistence(timeout: 15)); XCTAssertEqual(toggle.value as? String, "1")
        }
        let cleanup = app.buttons["history.management.cleanup"]
        if !cleanup.isHittable { app.swipeUp() }
        XCTAssertTrue(cleanup.waitForExistence(timeout: 5)); cleanup.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 15)); cancel.tap()
        let clear = app.buttons["history.management.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5)); clear.tap()
        XCTAssertTrue(commit.waitForExistence(timeout: 15)); commit.tap()
        let delete = app.buttons["history.management.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); attach(app, name: "Second confirmation before clearing vault history")
        let keep = app.buttons["history.management.confirm.cancel"]
        if keep.exists { keep.tap() }
        else {
            let buttons = app.buttons.matching(identifier: "Cancel")
            XCTAssertGreaterThan(buttons.count, 0); buttons.element(boundBy: buttons.count - 1).tap()
        }
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(clear.waitForExistence(timeout: 5)); attach(app, name: "History retained after canceling permanent cleanup")
    }

    @MainActor
    func testAutomaticHistoryLabelsKeepPreviewCancelRestoreAndRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let title = "History journey " + String(UUID().uuidString.prefix(6))
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
        let titleField = app.textFields["note.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5)); titleField.tap(); titleField.typeText(title); app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("First draft body."); app.buttons["Dismiss keyboard"].tap()
        func history() {
            app.buttons["Note actions"].tap(); app.buttons["note.history"].tap()
            XCTAssertTrue(app.navigationBars["Version history"].waitForExistence(timeout: 10))
        }
        history()
        let firstVersion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.version.")).firstMatch
        XCTAssertTrue(firstVersion.waitForExistence(timeout: 10)); firstVersion.tap()
        XCTAssertTrue(app.textViews["history.preview"].waitForExistence(timeout: 5))
        let label = app.textFields["history.label"]
        label.tap(); label.typeText("First draft")
        app.buttons["history.keep"].tap()
        XCTAssertEqual(app.buttons["history.keep"].value as? String, "Kept")
        app.buttons["history.label.save"].tap()
        let confirm = app.buttons["history.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        let labeled = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "history.version.", "First draft")).firstMatch
        XCTAssertTrue(labeled.waitForExistence(timeout: 10)); labeled.tap()
        XCTAssertTrue(app.buttons["history.keep"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["history.keep"].value as? String, "Kept", "The retention choice must survive the review and reopen")
        app.navigationBars["Saved version"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(labeled.waitForExistence(timeout: 5)); attach(app, name: "Kept and labeled automatic history")
        app.buttons["Done"].tap()
        editor.tap(); editor.typeText(" Later changes."); app.buttons["Dismiss keyboard"].tap()
        history(); XCTAssertTrue(labeled.waitForExistence(timeout: 10)); labeled.tap()
        app.buttons["Changes"].tap()
        XCTAssertTrue(app.staticTexts["Compared with the current note"].waitForExistence(timeout: 5))
        app.buttons["Source"].tap()
        XCTAssertTrue(app.textViews["history.preview"].waitForExistence(timeout: 5))
        app.buttons["history.restore"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["history.restore"].waitForExistence(timeout: 5)); app.buttons["history.restore"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); attach(app, name: "Native history restore review"); confirm.tap()
        XCTAssertTrue(labeled.waitForExistence(timeout: 10)); app.buttons["Done"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue((editor.value as? String ?? "").contains("First draft body.")); XCTAssertFalse((editor.value as? String ?? "").contains("Later changes."))
        app.buttons["Close note"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let search = app.searchFields.firstMatch; if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(title)
        let result = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue((editor.value as? String ?? "").contains("First draft body.")); XCTAssertFalse((editor.value as? String ?? "").contains("Later changes."))
        history(); XCTAssertTrue(labeled.waitForExistence(timeout: 10))
        let clear = app.buttons["history.clear"]; if !clear.isHittable { app.swipeUp() }
        XCTAssertTrue(clear.waitForExistence(timeout: 5)); clear.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); app.buttons["Cancel"].tap()
        XCTAssertTrue(labeled.waitForExistence(timeout: 5)); attach(app, name: "Restored history survives relaunch and clear review cancellation")
    }

    @MainActor
    func testRecentlyDeletedRestoresRevisionsReviewsCleanupRestoresAndPermanentlyDeletesAWholeNote() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let token = String(UUID().uuidString.prefix(6)), title = "Trash revision " + token, single = "Only revision " + token
        func create(_ title: String) {
            XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
            let field = app.textFields["note.title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title); app.buttons["note.create"].tap()
            let editor = app.textViews["note.editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("Kept with every revision."); app.buttons["Dismiss keyboard"].tap()
        }
        func revisions() {
            app.buttons["Note actions"].tap(); app.buttons["note.revisions"].tap()
            let ready = app.buttons["revision.create"].waitForExistence(timeout: 10)
            if !ready { attach(app, name: "Revision presentation after restoring a whole note failed") }
            XCTAssertTrue(ready, app.debugDescription)
        }
        func recentlyDeleted() {
            openNativeLibrary(app)
            XCTAssertTrue(app.buttons["library.trash"].waitForExistence(timeout: 5)); app.buttons["library.trash"].tap()
        }
        func reveal(_ element: XCUIElement, down: Bool) {
            for _ in 0..<12 {
                if element.exists && element.isHittable { return }
                if down { app.swipeUp() } else { app.swipeDown() }
            }
            XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
        }
        let confirm = app.buttons["revision.confirm"]
        create(title); revisions(); app.buttons["revision.create"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        XCTAssertTrue(app.buttons["revision.row.1"].waitForExistence(timeout: 15)); app.buttons["revision.row.1"].tap()
        XCTAssertTrue(app.buttons["revision.trash"].waitForExistence(timeout: 5)); app.buttons["revision.trash"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        XCTAssertTrue(app.buttons["revision.row.2"].waitForExistence(timeout: 15)); app.buttons["Done"].tap(); app.buttons["Close note"].tap()
        recentlyDeleted()
        let discarded = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "trash.revision.", title)).firstMatch
        reveal(discarded, down: true)
        XCTAssertTrue(discarded.waitForExistence(timeout: 10)); attach(app, name: "Native Recently Deleted with discarded revision")
        reveal(app.buttons["trash.revisions.review"], down: true); app.buttons["trash.revisions.review"].tap()
        XCTAssertTrue(app.buttons["trash.revisions.delete"].waitForExistence(timeout: 10))
        app.buttons["trash.revisions.cancel"].tap()
        reveal(discarded, down: false); discarded.tap()
        XCTAssertTrue(app.buttons["revision.restore"].waitForExistence(timeout: 10)); app.buttons["revision.restore"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        XCTAssertTrue(app.buttons["revision.row.1"].waitForExistence(timeout: 15)); app.buttons["Done"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: discarded)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        openNativeNotes(app); create(single); revisions(); app.buttons["revision.row.1"].tap()
        XCTAssertTrue(app.buttons["revision.trash"].waitForExistence(timeout: 5)); app.buttons["revision.trash"].tap()
        let wholeNote = app.buttons["Move note to Trash"]
        XCTAssertTrue(wholeNote.waitForExistence(timeout: 5)); wholeNote.tap()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        openNativeLibrary(app)
        if app.buttons["library.trash"].exists { app.buttons["library.trash"].tap() }
        let restore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@", "trash.restoreNote.", single)).firstMatch
        reveal(restore, down: false); restore.tap()
        openNativeNotes(app)
        let search = app.searchFields.firstMatch; if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(single)
        let result = app.buttons.containing(.staticText, identifier: single).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap(); revisions()
        XCTAssertTrue(app.buttons["revision.row.1"].waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons["revision.row.2"].exists)
        attach(app, name: "Whole note and its only revision restored together")
        app.buttons["revision.row.1"].tap(); app.buttons["revision.trash"].tap()
        XCTAssertTrue(wholeNote.waitForExistence(timeout: 5)); wholeNote.tap()
        let closeSearch = app.navigationBars["Notes"].buttons["Close"]
        XCTAssertTrue(closeSearch.waitForExistence(timeout: 5)); closeSearch.tap()
        openNativeLibrary(app)
        if app.buttons["library.trash"].exists { app.buttons["library.trash"].tap() }
        let purge = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@", "trash.note.review.", single)).firstMatch
        reveal(purge, down: false); purge.tap()
        XCTAssertTrue(app.buttons["trash.notes.delete"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Review note cleanup"].exists)
        attach(app, name: "Native whole-note cleanup reviews notes versions and unused files")
        app.buttons["trash.notes.cancel"].tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "Cancel must keep the whole note restorable")
        purge.tap(); XCTAssertTrue(app.buttons["trash.notes.delete"].waitForExistence(timeout: 10)); app.buttons["trash.notes.delete"].tap()
        let finalDelete = app.buttons["Delete notes and listed files"].firstMatch
        XCTAssertTrue(finalDelete.waitForExistence(timeout: 5), "Permanent deletion requires the final confirmation")
        attach(app, name: "Native permanent note cleanup requires a second confirmation")
        finalDelete.tap()
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Review note cleanup"])
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 15), .completed)
        XCTAssertTrue(app.navigationBars["Recently Deleted"].waitForExistence(timeout: 5))
        XCTAssertFalse(purge.exists)
        app.terminate(); app.launch(); openNativeLibrary(app)
        XCTAssertTrue(app.buttons["library.trash"].waitForExistence(timeout: 5)); app.buttons["library.trash"].tap()
        XCTAssertFalse(purge.waitForExistence(timeout: 2)); XCTAssertFalse(restore.exists)
        openNativeNotes(app)
        let finalSearch = app.searchFields.firstMatch; if !finalSearch.exists { app.swipeDown() }
        XCTAssertTrue(finalSearch.waitForExistence(timeout: 5)); finalSearch.tap(); finalSearch.typeKey("a", modifierFlags: .command); finalSearch.typeText(single)
        XCTAssertFalse(result.waitForExistence(timeout: 2), "The deleted note must stay gone after reopening")
        finalSearch.typeKey("a", modifierFlags: .command); finalSearch.typeText(title)
        let survivor = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(survivor.waitForExistence(timeout: 5)); survivor.tap()
        let survivingEditor = app.textViews["note.editor"]; XCTAssertTrue(survivingEditor.waitForExistence(timeout: 5))
        XCTAssertTrue((survivingEditor.value as? String ?? "").contains("Kept with every revision."))
        revisions(); XCTAssertTrue(app.buttons["revision.row.1"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["revision.row.2"].exists)
        attach(app, name: "Permanent note deletion survives relaunch and preserves another note with its revisions")
        app.buttons["Done"].tap(); app.buttons["Close note"].tap()
    }

    @MainActor
    func testNativeRevisionReviewCancelPromoteTrashRestoreAndRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let title = "Revision journey " + String(UUID().uuidString.prefix(6))
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
        let titleField = app.textFields["note.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5)); titleField.tap(); titleField.typeText(title); app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("Before milestone."); app.buttons["Dismiss keyboard"].tap()
        func revisions() {
            app.buttons["Note actions"].tap(); app.buttons["note.revisions"].tap()
            XCTAssertTrue(app.buttons["revision.create"].waitForExistence(timeout: 10))
        }
        let confirm = app.buttons["revision.confirm"]
        revisions(); app.buttons["revision.create"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["revision.row.1"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["revision.row.2"].exists)
        app.buttons["revision.create"].tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        XCTAssertTrue(app.buttons["revision.row.2"].waitForExistence(timeout: 15)); app.buttons["Done"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: .command); editor.typeText(" After milestone."); app.buttons["Dismiss keyboard"].tap()
        revisions(); app.buttons["revision.row.1"].tap()
        let preview = app.textViews["revision.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5)); XCTAssertTrue((preview.value as? String)?.contains("Before milestone.") == true)
        XCTAssertFalse((preview.value as? String)?.contains("After milestone.") == true)
        app.buttons["revision.promote"].tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 10)); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["revision.promote"].waitForExistence(timeout: 5)); app.buttons["revision.promote"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        XCTAssertTrue(app.buttons["revision.row.3"].waitForExistence(timeout: 15)); app.buttons["revision.row.3"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5)); XCTAssertFalse((preview.value as? String)?.contains("After milestone.") == true)
        attach(app, name: "Native revision promoted read-only preview")
        app.buttons["revision.trash"].tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        XCTAssertTrue(app.buttons["revision.row.2"].waitForExistence(timeout: 15)); XCTAssertTrue(app.buttons["revision.row.2"].label.contains("Current"))
        app.buttons["revision.row.3"].tap(); XCTAssertTrue(app.buttons["revision.restore"].waitForExistence(timeout: 5))
        app.buttons["revision.restore"].tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        XCTAssertTrue(app.buttons["revision.row.3"].waitForExistence(timeout: 15)); XCTAssertTrue(app.buttons["revision.row.2"].label.contains("Current"))
        app.buttons["Done"].tap(); app.buttons["Close note"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let search = app.searchFields.firstMatch; if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(title)
        let result = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue((editor.value as? String)?.contains("After milestone.") == true)
        revisions(); XCTAssertTrue(app.buttons["revision.row.3"].exists); XCTAssertTrue(app.buttons["revision.row.2"].label.contains("Current"))
        attach(app, name: "Native revisions after trash restoration and relaunch")
    }

    @MainActor
    func testNativeRelationDefinitionReviewCancelRenameMoveAndDelete() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        let token = String(UUID().uuidString.prefix(6))
        let source = "Relation source " + token, target = "Relation target " + token
        let relation = "Related " + token, renamed = "Connected " + token
        func create(_ title: String) {
            XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
            let field = app.textFields["note.title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title); app.buttons["note.create"].tap()
            XCTAssertTrue(app.textViews["note.editor"].waitForExistence(timeout: 5))
            app.textViews["note.editor"].typeText("Relation controls preserve this body.")
            app.buttons["Dismiss keyboard"].tap()
        }
        create(target); app.buttons["Close note"].tap(); create(source)
        app.buttons["Note information"].tap(); app.buttons["schema.manage"].tap()
        XCTAssertTrue(app.buttons["schema.relation.add"].waitForExistence(timeout: 5)); app.buttons["schema.relation.add"].tap()
        let name = app.textFields["relation.definition.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(relation)
        let multiple = app.switches["relation.definition.multiple"]
        multiple.switches.firstMatch.tap(); XCTAssertEqual(multiple.value as? String, "1")
        app.buttons["relation.definition.save"].tap()
        let confirm = app.buttons["relation.definition.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); app.buttons["relation.definition.review.cancel"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.buttons["relation.definition.save"].tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        let definition = app.buttons["schema.definition." + relation.lowercased()]
        reveal(definition, in: app); XCTAssertTrue(definition.waitForExistence(timeout: 15)); app.buttons["schema.done"].tap()
        let property = app.buttons["property." + relation.lowercased()]
        reveal(property, in: app); XCTAssertTrue(property.waitForExistence(timeout: 5)); property.tap()
        let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "relation.target.", target)).firstMatch
        let search = app.textFields["relation.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText(target)
        XCTAssertTrue(candidate.waitForExistence(timeout: 10)); candidate.tap()
        XCTAssertTrue(app.buttons["relation.save"].waitForExistence(timeout: 5), "Selecting a search result must restore the Save action")
        app.buttons["relation.save"].tap()
        XCTAssertTrue(app.buttons["Save paired links"].waitForExistence(timeout: 10)); app.buttons["Save paired links"].tap()
        reveal(property, in: app); XCTAssertTrue(property.waitForExistence(timeout: 15)); XCTAssertTrue(property.label.contains(target))
        app.buttons["schema.manage"].tap(); reveal(definition, in: app); XCTAssertTrue(definition.waitForExistence(timeout: 5)); definition.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: relation.count) + renamed)
        app.buttons["relation.definition.save"].tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        let renamedDefinition = app.buttons["schema.definition." + renamed.lowercased()]
        reveal(renamedDefinition, in: app); XCTAssertTrue(renamedDefinition.waitForExistence(timeout: 15)); app.buttons["schema.done"].tap()
        let renamedProperty = app.buttons["property." + renamed.lowercased()]
        reveal(renamedProperty, in: app); XCTAssertTrue(renamedProperty.waitForExistence(timeout: 5)); XCTAssertTrue(renamedProperty.label.contains(target))
        attach(app, name: "Native relation after definition rename")
        app.buttons["note.info.done"].tap(); app.buttons["Note actions"].tap(); app.buttons["Move to folder"].tap()
        let folder = "Relation moved " + token
        let folderField = app.textFields["move.newFolder"]
        XCTAssertTrue(folderField.waitForExistence(timeout: 10)); folderField.tap(); folderField.typeText(folder)
        app.buttons["move.review"].tap()
        let moveConfirm = app.buttons["maintenance.confirm"]
        XCTAssertTrue(moveConfirm.waitForExistence(timeout: 10)); app.buttons["maintenance.cancel"].tap()
        XCTAssertTrue(folderField.waitForExistence(timeout: 5)); app.buttons["move.review"].tap()
        XCTAssertTrue(moveConfirm.waitForExistence(timeout: 10)); moveConfirm.tap()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let collectionSearch = app.searchFields.firstMatch; if !collectionSearch.exists { app.swipeDown() }
        XCTAssertTrue(collectionSearch.waitForExistence(timeout: 5)); collectionSearch.tap(); collectionSearch.typeText(source)
        let result = app.buttons.containing(.staticText, identifier: source).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap(); app.buttons["Note information"].tap()
        XCTAssertTrue(app.staticTexts[folder].waitForExistence(timeout: 5))
        reveal(renamedProperty, in: app); XCTAssertTrue(renamedProperty.waitForExistence(timeout: 5)); XCTAssertTrue(renamedProperty.label.contains(target))
        attach(app, name: "Native relation after folder move and relaunch")
        app.buttons["schema.manage"].tap(); reveal(renamedDefinition, in: app); XCTAssertTrue(renamedDefinition.waitForExistence(timeout: 5)); renamedDefinition.tap()
        XCTAssertTrue(app.buttons["relation.definition.delete"].waitForExistence(timeout: 5)); app.buttons["relation.definition.delete"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: renamedDefinition)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 15), .completed)
        app.buttons["schema.done"].tap()
        let removedProperty = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: renamedProperty)
        XCTAssertEqual(XCTWaiter.wait(for: [removedProperty], timeout: 15), .completed)
        app.buttons["note.info.done"].tap(); app.buttons["Close note"].tap()
    }

    @MainActor
    func testFolderDefinitionCreationRenameSingleChoiceAndDeletionAfterRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
        let token = String(UUID().uuidString.prefix(6)), title = "Schema check " + token
        let status = "Status " + token, stage = "Stage " + token
        let titleField = app.textFields["note.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5)); titleField.tap(); titleField.typeText(title); app.buttons["note.create"].tap()
        XCTAssertTrue(app.textViews["note.editor"].waitForExistence(timeout: 5))
        app.textViews["note.editor"].typeText("Definition changes keep this body.")
        app.buttons["Dismiss keyboard"].tap(); app.buttons["Note information"].tap(); app.buttons["schema.manage"].tap()
        XCTAssertTrue(app.buttons["schema.add"].waitForExistence(timeout: 5)); app.buttons["schema.add"].tap()
        let name = app.textFields["schema.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(status)
        app.buttons["schema.type"].tap(); app.buttons["List"].tap()
        let choice = app.textFields["schema.choice"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap(); choice.typeText("Planned"); app.buttons["schema.choice.add"].tap()
        choice.tap(); choice.typeText("Active"); app.buttons["schema.choice.add"].tap()
        let multiple = app.switches["schema.multiple"]
        XCTAssertTrue(multiple.waitForExistence(timeout: 5)); multiple.switches.firstMatch.tap()
        XCTAssertEqual(multiple.value as? String, "1")
        app.buttons["schema.save"].tap()
        let definition = app.buttons["schema.definition." + status.lowercased()]
        reveal(definition, in: app); XCTAssertTrue(definition.waitForExistence(timeout: 15)); app.buttons["schema.done"].tap()
        let property = app.buttons["property." + status.lowercased()]
        reveal(property, in: app); XCTAssertTrue(property.waitForExistence(timeout: 5)); property.tap()
        app.buttons["Planned"].tap(); app.buttons["Active"].tap(); app.buttons["property.save"].tap()
        reveal(property, in: app); XCTAssertTrue(property.waitForExistence(timeout: 5)); XCTAssertTrue(property.label.contains("Planned, Active"))
        app.buttons["schema.manage"].tap(); reveal(definition, in: app); XCTAssertTrue(definition.waitForExistence(timeout: 5)); definition.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: status.count) + stage)
        multiple.switches.firstMatch.tap(); XCTAssertEqual(multiple.value as? String, "0")
        app.buttons["schema.save"].tap(); app.buttons["Update definition"].tap()
        let renamed = app.buttons["schema.definition." + stage.lowercased()]
        reveal(renamed, in: app); XCTAssertTrue(renamed.waitForExistence(timeout: 15)); XCTAssertFalse(definition.exists)
        app.buttons["schema.done"].tap()
        let migrated = app.buttons["property." + stage.lowercased()]
        reveal(migrated, in: app); XCTAssertTrue(migrated.waitForExistence(timeout: 5)); XCTAssertTrue(migrated.label.contains("Planned")); XCTAssertFalse(migrated.label.contains("Active"))
        attach(app, name: "Native inherited property definition")
        app.buttons["note.info.done"].tap(); app.buttons["Close note"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let search = app.searchFields.firstMatch; if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(title)
        let result = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap(); app.buttons["Note information"].tap()
        reveal(migrated, in: app); XCTAssertTrue(migrated.waitForExistence(timeout: 5)); XCTAssertTrue(migrated.label.contains("Planned"))
        app.buttons["schema.manage"].tap(); reveal(renamed, in: app); XCTAssertTrue(renamed.waitForExistence(timeout: 5)); renamed.tap()
        app.buttons["schema.delete"].tap(); app.sheets.buttons["Delete definition"].tap()
        let removedDefinition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: renamed)
        XCTAssertEqual(XCTWaiter.wait(for: [removedDefinition], timeout: 15), .completed)
        app.buttons["schema.done"].tap()
        let removedValue = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: migrated)
        XCTAssertEqual(XCTWaiter.wait(for: [removedValue], timeout: 15), .completed)
        app.buttons["note.info.done"].tap(); app.buttons["Close note"].tap()
    }

    @MainActor
    func testNativePropertiesSaveCancelRemoveAndReopen() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        func reveal(_ identifier: String) -> XCUIElement {
            let control = app.buttons[identifier]
            if control.waitForExistence(timeout: 2) && control.isHittable { return control }
            for _ in 0..<12 {
                app.swipeUp()
                if control.waitForExistence(timeout: 1) && control.isHittable { return control }
            }
            XCTFail("Could not reveal " + identifier + "\n" + app.debugDescription)
            return control
        }
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
        let title = "Properties check " + String(UUID().uuidString.prefix(6))
        let field = app.textFields["note.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title); app.buttons["note.create"].tap()
        XCTAssertTrue(app.textViews["note.editor"].waitForExistence(timeout: 5))
        app.textViews["note.editor"].typeText("Body stays **bold**.")
        app.buttons["Dismiss keyboard"].tap(); app.buttons["Note information"].tap()
        reveal("property.add").tap()
        let name = app.textFields["property.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Owner")
        let value = app.textFields["property.value"].exists ? app.textFields["property.value"] : app.textViews["property.value"]
        value.tap(); value.typeText("Alex: Design #1")
        app.buttons["property.save"].tap()
        let owner = app.buttons["property.owner"]
        reveal("property.owner").tap()
        let editValue = app.textFields["property.value"].exists ? app.textFields["property.value"] : app.textViews["property.value"]
        editValue.tap(); editValue.typeText(" not saved")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(owner.waitForExistence(timeout: 5))
        XCTAssertTrue(owner.label.contains("Alex: Design #1")); XCTAssertFalse(owner.label.contains("not saved"))
        reveal("property.add").tap(); XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Ready")
        app.buttons["property.type"].tap(); app.buttons["Checkbox"].tap()
        let checked = app.switches["property.checked"]
        XCTAssertTrue(checked.waitForExistence(timeout: 5)); checked.switches.firstMatch.tap()
        XCTAssertEqual(checked.value as? String, "1", checked.debugDescription)
        app.buttons["property.save"].tap()
        _ = reveal("property.ready")
        reveal("property.add").tap(); XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Labels")
        app.buttons["property.type"].tap(); app.buttons["List"].tap()
        let choice = app.textFields["property.choice"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap(); choice.typeText("A, B"); app.buttons["property.choice.add"].tap()
        choice.tap(); choice.typeText("Review"); app.buttons["property.save"].tap()
        _ = reveal("property.labels")
        attach(app, name: "Native note properties")
        app.buttons["Done"].tap(); app.buttons["Close note"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let search = app.searchFields.firstMatch; if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(title)
        let result = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap(); app.buttons["Note information"].tap()
        _ = reveal("property.owner")
        XCTAssertTrue(reveal("property.ready").label.contains("Checked"))
        XCTAssertTrue(reveal("property.labels").label.contains("A, B, Review"))
        reveal("property.owner").tap(); app.buttons["Remove value"].tap()
        app.buttons["Remove value"].firstMatch.tap()
        _ = reveal("property.add"); XCTAssertFalse(app.buttons["property.owner"].exists)
        app.buttons["Done"].tap(); app.buttons["Close note"].tap()
    }

    @MainActor
    private func codePreference(_ app: XCUIApplication, _ enabled: Bool? = nil) -> Bool {
        let closeSearch = app.navigationBars["Notes"].buttons["Close"]
        if closeSearch.exists { closeSearch.tap() }
        app.buttons["Settings"].tap(); app.buttons["settings.general"].tap()
        let toggle = app.switches["settings.codeBlocks"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "General must offer the code creation preference")
        let before = toggle.value as? String == "1"
        if let enabled, enabled != before { toggle.switches.firstMatch.tap() }
        if let enabled { XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0") }
        app.navigationBars["General"].buttons["BackButton"].tap(); app.buttons["Done"].tap()
        return before
    }

    @MainActor
    func testNativeNoteCopyPasteAndUndoKeepFormattedBlocksAfterRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let originalCodePreference = codePreference(app, true)
        app.buttons["navigation.newNote"].tap()
        let title = "Clipboard check " + String(UUID().uuidString.prefix(6)), destination = title + " destination"
        let titleField = app.textFields["note.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5)); titleField.tap(); titleField.typeText(title)
        app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        editor.typeText("A **bold** thought with [[zerus:clipboard-target|Connected note]].\n\n- [ ] Review the draft\n\n```swift\nlet clipboardValue = \"<literal> **code**\"\n```\n\n<!-- zerus-table-widths: 120,240 -->\n| A | B |\n| --- | --- |\n| one | two |\n\nThe end.")
        app.buttons["Dismiss keyboard"].tap()
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        app.buttons["Note actions"].tap(); app.buttons["Clipboard"].tap(); app.buttons["Copy note"].tap()
        let busy = app.progressIndicators["Preparing clipboard"]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: busy)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
        XCTAssertFalse(app.alerts["Clipboard"].exists)
        app.buttons["Close note"].tap()
        app.buttons["navigation.newNote"].tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 5)); titleField.tap(); titleField.typeText(destination)
        app.buttons["note.create"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("Destination text.\n\n")
        app.buttons["Note actions"].tap(); app.buttons["Clipboard"].tap(); app.buttons["Paste"].tap(); XCTAssertTrue(app.buttons["clipboard.paste"].waitForExistence(timeout: 10)); app.buttons["clipboard.paste"].tap()
        let code = app.buttons["Edit swift code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Edit table"].exists)
        app.buttons["Undo"].tap()
        XCTAssertFalse(code.exists)
        XCTAssertTrue((editor.value as? String ?? "").contains("Destination text."))
        app.buttons["Redo"].tap()
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        app.buttons["Dismiss keyboard"].tap()
        attach(app, name: "Native pasted note")
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        let saved = editor.value as? String ?? ""
        XCTAssertTrue(saved.hasPrefix("# " + destination + "\n\nDestination text."), saved)
        XCTAssertTrue(saved.contains("A **bold** thought with [[zerus:clipboard-target|Connected note]]."), saved)
        XCTAssertTrue(saved.contains("let clipboardValue = \"<literal> **code**\""))
        XCTAssertTrue(saved.contains("<!-- zerus-table-widths: 120,240 -->"))
        XCTAssertTrue(saved.contains("- [ ] Review the draft"))
        XCTAssertFalse(saved.contains("\u{fffc}"))
        app.buttons["Close note"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(destination)
        let result = app.buttons.containing(.staticText, identifier: destination).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(app.buttons["Edit swift code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit table"].exists)
        app.buttons["Close note"].tap()
        _ = codePreference(app, originalCodePreference)
    }
    @MainActor
    func testNativeTableEditingPaginationUndoAndLinkedNoteCreation() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        app.buttons["navigation.newNote"].tap()
        let title = "Table check " + String(UUID().uuidString.prefix(6)), linkedTitle = title + " linked"
        let titleField = app.textFields["note.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap(); titleField.typeText(title); app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        let linkedImage = #"[![Diagram](assets/diagram.png "caption")](https://example.com/diagram)"#
        let rows = (1...22).map { "| \($0 == 2 ? linkedImage : "Row \($0)") | \($0 == 1 ? "[[" + linkedTitle + "]]" : "Owner \($0)") |" }.joined(separator: "\n")
        editor.typeText("Before the table.\n\n<!-- zerus-table-widths: 120,240 -->\n| Item | Owner |\n| :--- | ---: |\n" + rows + "\n\nAfter the table.")
        app.buttons["Dismiss keyboard"].tap()
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        XCTAssertFalse(app.staticTexts["Source editing preserves this note’s advanced Markdown."].exists)
        let table = app.buttons["Edit table"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        if !table.isHittable { editor.swipeUp() }
        table.tap()
        let firstCell = app.buttons["table.cell.1.0"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5)); firstCell.tap()
        let input = app.descendants(matching: .any).matching(identifier: "table.cell.content").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap()
        XCTAssertEqual(input.value as? String, "Row 1")
        input.typeKey("a", modifierFlags: .command); input.typeText("Row 1 Edited | value ")
        app.buttons["table.cell.bold"].tap(); input.typeText("Native bold"); app.buttons["table.cell.bold"].tap()
        input.typeText(" and "); app.buttons["table.cell.code"].tap(); input.typeText("`literal` | pipe"); app.buttons["table.cell.code"].tap()
        input.typeText(" done.")
        app.buttons["table.cell.link"].tap()
        let linkLabel = app.textFields["table.cell.link.label"], linkAddress = app.textFields["table.cell.link.address"]
        XCTAssertTrue(linkLabel.waitForExistence(timeout: 5)); linkLabel.tap(); linkLabel.typeText("Docs")
        linkAddress.tap(); linkAddress.typeText("https://example.com/report?x=1&y=2"); app.buttons["table.cell.link.save"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let editedCell = try XCTUnwrap(input.value as? String)
        XCTAssertTrue(editedCell.contains("Edited | value"))
        XCTAssertTrue(editedCell.contains("Native bold and `literal` | pipe done.Docs"), editedCell)
        attach(app, name: "Native rich table cell with formatted text code and link")
        app.buttons["table.cell.done"].tap()
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        XCTAssertTrue(firstCell.label.contains("Edited | value"), firstCell.label)
        app.buttons["table.cell.2.0"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["table.cell.source"].value as? String, "1", "Linked images must keep their complete source until their rich editor can retain both destinations")
        XCTAssertEqual(input.value as? String, linkedImage)
        input.tap(); input.typeKey("a", modifierFlags: .command); input.typeText(linkedImage + " retained"); app.buttons["table.cell.done"].tap()
        app.buttons["Next rows"].tap()
        XCTAssertTrue(app.buttons["table.cell.21.0"].waitForExistence(timeout: 5))
        app.buttons["Previous rows"].tap()
        app.buttons["Table actions"].tap(); app.buttons["Add column"].tap()
        XCTAssertTrue(app.buttons["table.cell.0.2"].waitForExistence(timeout: 5))
        app.buttons["Table actions"].tap(); app.buttons["Undo"].tap()
        XCTAssertFalse(app.buttons["table.cell.0.2"].exists)
        attach(app, name: "Native table grid")
        app.buttons["table.save"].tap()
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        let saved = editor.value as? String ?? ""
        XCTAssertTrue(saved.hasPrefix("# " + title + "\n\nBefore the table."), saved)
        XCTAssertTrue(saved.contains("<!-- zerus-table-widths: 120,240 -->"))
        XCTAssertTrue(saved.contains("**Native bold**"), saved)
        XCTAssertTrue(saved.contains("`literal`"), saved)
        XCTAssertTrue(saved.contains("[Docs](https://example.com/report?x=1&y=2)"), saved)
        XCTAssertTrue(saved.contains(linkedImage + " retained"), saved)
        XCTAssertTrue(saved.contains(" | [[" + linkedTitle + "]] |"), saved)
        XCTAssertTrue(saved.contains("| Row 22 | Owner 22 |\n\nAfter the table."))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        attach(app, name: "Native table in a formatted note")
        table.tap()
        XCTAssertTrue(app.buttons["table.cell.1.1"].waitForExistence(timeout: 5))
        app.buttons["table.cell.1.1"].press(forDuration: 1)
        app.buttons["Open " + linkedTitle].tap()
        XCTAssertTrue(app.buttons["Create linked note"].waitForExistence(timeout: 5))
        app.buttons["Create linked note"].tap()
        XCTAssertTrue(app.navigationBars[linkedTitle].waitForExistence(timeout: 5))
        app.buttons["Close note"].tap()
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        app.buttons["navigation.newNote"].tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap(); titleField.typeText(title + " from toolbar"); app.buttons["note.create"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("A native table example.\n\n")
        app.buttons["Paragraph style"].tap(); app.buttons["Table"].tap()
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5)); firstCell.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Native ")
        app.buttons["table.cell.bold"].tap(); input.typeText("table"); app.buttons["table.cell.bold"].tap()
        input.typeKey("a", modifierFlags: .command); app.buttons["table.cell.bold"].tap()
        app.buttons["table.cell.done"].tap(); app.buttons["table.save"].tap()
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        XCTAssertTrue((editor.value as? String ?? "").contains("| **Native table** |  |"), editor.value as? String ?? "")
        app.buttons["Close note"].tap()
    }

    @MainActor
    func testNativeCodeEditorSavesAndCancelsWithoutChangingSurroundingProse() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let originalPreference = codePreference(app, false)
        app.buttons["navigation.newNote"].tap()
        let title = "Code check " + String(UUID().uuidString.prefix(6))
        let titleField = app.textFields["note.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap(); titleField.typeText(title)
        app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["Paragraph style"].tap()
        XCTAssertFalse(app.buttons["Code block"].exists, "Off hides new code insertion without hiding existing code")
        app.buttons["Quote"].tap()
        app.buttons["Paragraph style"].tap(); app.buttons["Quote"].tap()
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        editor.typeText("Before the code.\n\n```swift\nlet message = \"**literal**\"\n```\n\nAfter the code.")
        XCTAssertTrue((editor.value as? String ?? "").hasPrefix("# " + title + "\n\nBefore the code."), "Switching to source must keep the end-of-note caret after the title and blank line")
        app.buttons["Dismiss keyboard"].tap()
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        XCTAssertFalse(app.staticTexts["Source editing preserves this note’s advanced Markdown."].exists)
        let code = app.buttons["Edit swift code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap()
        let body = app.textViews["code.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "let message = \"**literal**\"")
        XCTAssertTrue(app.buttons["code.toText"].exists, "Existing code offers conversion to ordinary text even when new code creation is off")
        body.tap(); body.typeText("cancelled")
        app.buttons["Cancel"].tap()
        code.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "let message = \"**literal**\"")
        body.tap(); body.typeText("edited")
        let edited = try XCTUnwrap(body.value as? String)
        app.buttons["code.save"].tap()
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        attach(app, name: "Native code block")
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        let saved = editor.value as? String ?? ""
        XCTAssertTrue(saved.contains("Before the code.\n\n```swift\n" + edited + "\n```\n\nAfter the code."), saved)
        app.buttons["Close note"].tap()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 5))
        _ = codePreference(app, true)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        XCTAssertTrue(codePreference(app), "Code creation stays enabled across relaunch")
        app.buttons["navigation.newNote"].tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap(); titleField.typeText(title + " from toolbar")
        app.buttons["note.create"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("A native code example.\n\n")
        app.buttons["Paragraph style"].tap(); app.buttons["Code block"].tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let language = app.textFields["code.language"]
        language.tap(); language.typeText("javascript")
        body.tap(); body.typeText("const raw = \"hello\";")
        app.buttons["code.save"].tap()
        XCTAssertTrue(app.buttons["Edit javascript code"].waitForExistence(timeout: 5))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        XCTAssertTrue((editor.value as? String ?? "").contains("A native code example.\n\n```javascript\nconst raw = \"hello\";\n```"))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        editor.tap(); editor.typeText("\n\n```python\n")
        XCTAssertTrue(body.waitForExistence(timeout: 5), "Return after a fence opens the native code editor")
        XCTAssertEqual(language.value as? String, "python")
        body.tap(); body.typeText("print(42)"); app.buttons["code.save"].tap()
        XCTAssertTrue(app.buttons["Edit python code"].waitForExistence(timeout: 5))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5)); app.buttons["Undo"].tap()
        XCTAssertFalse(app.buttons["Edit python code"].exists)
        XCTAssertTrue((editor.value as? String ?? "").contains("```python"))
        app.buttons["Redo"].tap(); XCTAssertTrue(app.buttons["Edit python code"].waitForExistence(timeout: 5))
        if app.buttons["Dismiss keyboard"].exists { app.buttons["Dismiss keyboard"].tap() }
        app.buttons["Close note"].tap()
        _ = codePreference(app, false)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        XCTAssertFalse(codePreference(app), "Disabling code creation survives relaunch")
        func findToolbarNote() {
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText(title + " from toolbar")
        }
        findToolbarNote()
        let result = app.buttons.containing(.staticText, identifier: title + " from toolbar").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        let existing = app.buttons["Edit javascript code"]
        XCTAssertTrue(existing.waitForExistence(timeout: 5)); existing.tap()
        XCTAssertEqual(body.value as? String, "const raw = \"hello\";")
        app.buttons["Cancel"].tap()
        attach(app, name: "Existing native code remains editable with creation disabled")
        existing.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap(); body.typeText("\n# Literal heading\n- [ ] Keep literal\n**literal**")
        let convertedDraft = try XCTUnwrap(body.value as? String)
        attach(app, name: "Code conversion action remains above the keyboard")
        app.buttons["code.toText"].tap()
        XCTAssertFalse(existing.exists)
        XCTAssertTrue((editor.value as? String ?? "").contains(convertedDraft), "Conversion uses the unsaved code draft as literal text")
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5)); app.buttons["Undo"].tap()
        XCTAssertTrue(existing.waitForExistence(timeout: 5))
        app.buttons["Redo"].tap(); XCTAssertFalse(existing.exists)
        if app.buttons["Dismiss keyboard"].exists { app.buttons["Dismiss keyboard"].tap() }
        attach(app, name: "Code converted to literal native text with creation disabled")
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        let convertedSource = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(convertedSource.contains("\\# Literal heading\n\\- \\[ \\] Keep literal\n\\*\\*literal\\*\\*"), convertedSource)
        XCTAssertTrue(convertedSource.contains("```python\nprint(42)\n```"), "Converting one block preserves its neighbor")
        app.buttons["Close note"].tap()
        app.terminate(); app.launch()
        findToolbarNote()
        XCTAssertTrue(result.waitForExistence(timeout: 15)); result.tap()
        XCTAssertFalse(existing.exists)
        XCTAssertTrue(app.buttons["Edit python code"].waitForExistence(timeout: 5))
        app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
        XCTAssertEqual(editor.value as? String, convertedSource, "The converted source survives relaunch exactly")
        app.buttons["Close note"].tap()
        _ = codePreference(app, originalPreference)
    }
    @MainActor
    func testCreateEditRelaunchSearchAndTaskCapture() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        attach(app, name: "Native notes")
        try auditAccessibility(app)
        app.buttons["navigation.newNote"].tap()
        let title = "Native check " + String(UUID().uuidString.prefix(6))
        let field = app.textFields["note.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(title)
        app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        // Use the actual editing surface and keyboard to exercise TextKit binding.
        editor.typeText("\nA thought that must survive reopening.\n\n")
        app.buttons["Paragraph style"].tap()
        app.buttons["Checklist"].tap()
        editor.typeText("Capture an idea\nFinish review\n\nA plain paragraph.")
        app.buttons["Dismiss keyboard"].tap()
        attach(app, name: "Native rich text editor")
        try auditAccessibility(app)
        app.buttons["Close note"].tap()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText(title)
        let result = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains("A thought that must survive reopening."))
        app.buttons["Note actions"].tap()
        app.buttons["Markdown source"].tap()
        let checklistSource = editor.value as? String ?? ""
        XCTAssertTrue(checklistSource.contains("- [ ] Capture an idea\n- [ ] Finish review\n\nA plain paragraph."), checklistSource)
        let linkedTitle = title + " linked"
        editor.tap()
        editor.typeText("\n\nIn **Productivity** reports.\n\n- [ ] Read the plan\n  - [x] Collect ideas\n\nSee [[\(linkedTitle)]].\n\n![diagram](assets/not-present.png)\n\n## Acceptance Criteria\n")
        app.buttons["Dismiss keyboard"].tap()
        app.buttons["Note actions"].tap()
        app.buttons["Markdown source"].tap()
        let formatted = editor.value as? String ?? ""
        attach(app, name: "Formatted note after source toggle")
        XCTAssertTrue(formatted.contains("Productivity"))
        XCTAssertFalse(formatted.contains("**Productivity**"))
        XCTAssertFalse(formatted.contains("![diagram]"))
        XCTAssertFalse(app.staticTexts["Source editing preserves this note’s advanced Markdown."].exists)
        let checkbox = app.buttons["Complete: Read the plan"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.tap()
        XCTAssertTrue(app.buttons["Mark incomplete: Read the plan"].waitForExistence(timeout: 5))
        app.buttons["Note actions"].tap()
        app.buttons["Markdown source"].tap()
        XCTAssertTrue((editor.value as? String ?? "").contains("- [x] Read the plan"))
        XCTAssertTrue((editor.value as? String ?? "").contains("[[\(linkedTitle)]]"))
        app.buttons["Note actions"].tap()
        app.buttons["Markdown source"].tap()
        attach(app, name: "Formatted image and checklist note")
        let retryImages = app.buttons["note.images.retry"]
        XCTAssertTrue(retryImages.waitForExistence(timeout: 20), "An unavailable image offers a visible retry without reopening the note")
        retryImages.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "note.images.loading").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(retryImages.waitForExistence(timeout: 5), "Retry stays available while a provider is loading")
        retryImages.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "note.images.loading").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Mark incomplete: Read the plan"].exists)
        attach(app, name: "Native image retry keeps the editor and checklist available")
        let linkedNote = app.links[linkedTitle]
        if !linkedNote.isHittable { editor.swipeUp() }
        linkedNote.tap()
        XCTAssertTrue(app.buttons["Create linked note"].waitForExistence(timeout: 5))
        app.buttons["Create linked note"].tap()
        XCTAssertTrue(app.navigationBars[linkedTitle].waitForExistence(timeout: 5))
        app.buttons["Close note"].tap()
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        app.buttons["navigation.tasks"].tap()
        app.buttons["Settings"].tap(); XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 5))
        app.buttons["New task"].tap()
        let taskTitle = "Finish the native check"
        let taskField = app.textFields["task.title"]
        XCTAssertTrue(taskField.waitForExistence(timeout: 5))
        taskField.tap(); taskField.typeText(taskTitle)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons[taskTitle].waitForExistence(timeout: 5))
        attach(app, name: "Native tasks")
        try auditAccessibility(app)
        openNativeLibrary(app)
        XCTAssertTrue(app.staticTexts["Recently Deleted"].waitForExistence(timeout: 5))
        attach(app, name: "Native library")
        try auditAccessibility(app)
    }
    @MainActor
    private func auditAccessibility(_ app: XCUIApplication) throws {
        let previous = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previous }
        try app.performAccessibilityAudit { issue in
            let detail = XCTAttachment(string: """
                Audit type: \(issue.auditType.rawValue)
                Summary: \(issue.compactDescription)
                Details: \(issue.detailedDescription)
                Element: \(issue.element?.debugDescription ?? "<unavailable>")
                """)
            detail.name = "Accessibility issue detail: " + issue.compactDescription
            detail.lifetime = .keepAlways; self.add(detail)
            // Retain XCTest's failure for every issue; this only adds evidence.
            return false
        }
    }
    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if element.waitForExistence(timeout: 2) { return }
        for _ in 0..<16 {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) { return }
        }
        XCTFail("The requested row was not reachable by scrolling: " + app.debugDescription)
    }

}
