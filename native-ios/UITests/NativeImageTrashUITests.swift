import XCTest
import UIKit

final class NativeImageTrashUITests: NativeJourneyTestCase {
    @MainActor
    func testPastedImageRemovalReviewCancelUndoTrashRestoreAndPermanentReviewSurviveRelaunch() throws {
        continueAfterFailure = false
        let app = launchNativeJourney()
        if app.buttons["vault.create"].waitForExistence(timeout: 3) { app.buttons["vault.create"].tap() }
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); app.buttons["navigation.newNote"].tap()
        let title = "Image lifecycle " + String(UUID().uuidString.prefix(6))
        let field = app.textFields["note.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title); app.buttons["note.create"].tap()
        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText("Before the image.\n\n")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 50)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 50))
        }
        UIPasteboard.general.image = image
        let permission = addUIInterruptionMonitor(withDescription: "Paste this disposable Simulator image") { alert in
            if alert.buttons["Allow Paste"].exists { alert.buttons["Allow Paste"].tap(); return true }; return false
        }
        defer { removeUIInterruptionMonitor(permission) }
        app.buttons["Note actions"].tap(); app.buttons["Clipboard"].tap(); app.buttons["Paste"].tap(); XCTAssertTrue(app.buttons["clipboard.paste"].waitForExistence(timeout: 10)); app.buttons["clipboard.paste"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.buttons["Allow Paste"].waitForExistence(timeout: 2) { springboard.alerts.buttons["Allow Paste"].tap() }
        if app.buttons["Dismiss keyboard"].exists { app.buttons["Dismiss keyboard"].tap() }
        func source() -> String {
            let interactive = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: editor)
            XCTAssertEqual(XCTWaiter.wait(for: [interactive], timeout: 15), .completed, app.debugDescription)
            app.buttons["Note actions"].tap()
            let action = app.buttons["Markdown source"]
            XCTAssertTrue(action.waitForExistence(timeout: 10)); action.tap()
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "!["), object: editor)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            let value = editor.value as? String ?? ""
            app.buttons["Note actions"].tap(); app.buttons["Markdown source"].tap()
            return value
        }
        let original = source()
        XCTAssertTrue(original.contains("Before the image."))
        func images() {
            app.buttons["Note actions"].tap()
            XCTAssertTrue(app.buttons["note.images.manage"].waitForExistence(timeout: 3), "Native notes must offer image removal and recovery")
            app.buttons["note.images.manage"].tap()
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "image.item.")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        }
        func remove() {
            app.buttons["image.remove.review"].tap()
            XCTAssertTrue(app.buttons["image.change.confirm"].waitForExistence(timeout: 10)); app.buttons["image.change.confirm"].tap()
            XCTAssertTrue(app.buttons["image.undo"].waitForExistence(timeout: 10))
        }
        images()
        app.buttons["image.preview"].tap(); XCTAssertTrue(app.buttons["file.preview.done"].waitForExistence(timeout: 10)); app.buttons["file.preview.done"].tap()
        app.buttons["image.remove.review"].tap(); XCTAssertTrue(app.buttons["image.change.cancel"].waitForExistence(timeout: 10)); app.buttons["image.change.cancel"].tap()
        remove(); app.buttons["image.undo"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "image.item.")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["images.done"].tap(); XCTAssertEqual(source(), original, "Undo restores the original note bytes represented in source")
        images(); remove(); app.buttons["images.done"].tap()
        XCTAssertFalse((editor.value as? String ?? "").contains("\u{fffc}"))
        app.buttons["Close note"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15))
        openNativeLibrary(app); if app.buttons["Recently Deleted"].waitForExistence(timeout: 2) { app.buttons["Recently Deleted"].tap() }
        let restoreQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "trash.image.restore.")).firstMatch
        XCTAssertTrue(restoreQuery.waitForExistence(timeout: 10))
        let restore = app.buttons[restoreQuery.identifier]
        let deletedPreview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "trash.image.preview.")).firstMatch
        XCTAssertTrue(deletedPreview.exists); deletedPreview.tap(); XCTAssertTrue(app.buttons["file.preview.done"].waitForExistence(timeout: 10)); app.buttons["file.preview.done"].tap()
        restore.tap()
        XCTAssertTrue(app.buttons["image.change.cancel"].waitForExistence(timeout: 10)); app.buttons["image.change.cancel"].tap()
        XCTAssertTrue(restore.exists); restore.tap(); XCTAssertTrue(app.buttons["image.change.confirm"].waitForExistence(timeout: 10)); app.buttons["image.change.confirm"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: restore)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        openNativeNotes(app)
        let note = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5)); note.tap()
        XCTAssertTrue(source().contains("!["), "Restore reattaches the image to its original note")
        images(); remove(); app.buttons["images.done"].tap(); app.buttons["Close note"].tap()
        openNativeLibrary(app); if app.buttons["Recently Deleted"].waitForExistence(timeout: 2) { app.buttons["Recently Deleted"].tap() }
        let purgeQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "trash.image.delete.")).firstMatch
        XCTAssertTrue(purgeQuery.waitForExistence(timeout: 10))
        let purge = app.buttons[purgeQuery.identifier]; purge.tap()
        XCTAssertTrue(app.buttons["image.change.cancel"].waitForExistence(timeout: 10)); app.buttons["image.change.cancel"].tap()
        XCTAssertTrue(purge.exists); purge.tap(); XCTAssertTrue(app.buttons["image.change.confirm"].waitForExistence(timeout: 10)); app.buttons["image.change.confirm"].tap()
        XCTAssertTrue(app.buttons["Delete images permanently"].waitForExistence(timeout: 5)); app.buttons["Delete images permanently"].tap()
        let purged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: purge)
        XCTAssertEqual(XCTWaiter.wait(for: [purged], timeout: 10), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Native image Trash after reviewed permanent deletion"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["navigation.newNote"].waitForExistence(timeout: 15)); openNativeNotes(app)
        XCTAssertTrue(note.waitForExistence(timeout: 5)); note.tap()
        XCTAssertTrue((editor.value as? String ?? "").contains("Before the image."))
        XCTAssertFalse((editor.value as? String ?? "").contains("\u{fffc}"))
        app.buttons["Close note"].tap()
    }
}
