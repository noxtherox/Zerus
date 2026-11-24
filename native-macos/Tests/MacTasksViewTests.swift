import XCTest
import SwiftUI
import AppKit
@testable import Zerus_Native

@MainActor final class MacTasksViewTests: XCTestCase {
    func testTaskFiltersFitACompactWindowAndSearchRemainsUsable() throws {
        let suite = "Zerus-tasks-zoom-" + UUID().uuidString, preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = MacWorkspace(), host = NSHostingView(rootView: MacZoomViewport { MacTasksView(store: store) }.defaultAppStorage(preferences))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 620), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
        var enteredQuery = false
        for (width, zoom): (CGFloat, Int) in [(600, 100), (900, 100), (600, 150), (600, 80), (600, 100)] {
            preferences.set(zoom, forKey: "zerus.mac.interfaceZoom")
            window.setContentSize(NSSize(width: width, height: 620))
            for _ in 0..<5 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            let controls = nodes(host).compactMap { $0 as? NSControl }.filter { !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 1 && $0.bounds.height > 1 }
            let search = try XCTUnwrap(controls.compactMap { $0 as? NSTextField }.first { $0.placeholderString?.contains("Search tasks") == true })
            XCTAssertGreaterThan(search.bounds.width, 120, "The search field must allow a useful query at compact widths")
            if enteredQuery { XCTAssertEqual(search.stringValue, "urgent", "Reflow must keep the typed query") }
            else {
                XCTAssertTrue(window.makeFirstResponder(search))
                let editor = try XCTUnwrap(window.fieldEditor(true, for: search) as? NSTextView)
                editor.insertText("urgent", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                window.makeFirstResponder(nil)
                enteredQuery = true
            }
            for control in controls {
                let rect = control.convert(control.bounds, to: host)
                XCTAssertGreaterThanOrEqual(rect.minX, -1)
                XCTAssertLessThanOrEqual(rect.maxX, host.bounds.maxX + 1, "Task controls must remain inside the viewport")
            }
        }
    }
    func testTaskDateClearingRetainsRequiredValuesAndKeepsDueEditorMounted() async throws {
        for due in [false, true] {
            try await withTaskEditor { root, store, task, host, window in
                let field = try dateField(due ? "05/01/2027" : "31/12/2026", in: host)
                XCTAssertTrue(window.makeFirstResponder(field))
                let editor = try XCTUnwrap(window.fieldEditor(true, for: field) as? NSTextView)
                editor.insertText("", replacementRange: NSRange(location: 0, length: editor.string.utf16.count)); settle(host)
                let changed = store.taskDraftStore?.latest(for: task.id)?.task ?? task
                if due { XCTAssertTrue(changed.raw["dueDate"] is NSNull, "Clearing an optional due date must reach the unsaved task model") }
                else { XCTAssertEqual(changed.raw["date"] as? String, "2026-12-31", "An invalid required date must leave the task unchanged") }
                XCTAssertEqual(editor.string, "", "The draft cannot jump to a fallback date")
                XCTAssertTrue(field.isDescendant(of: host), "The Due field must remain mounted while its text is being replaced")
                if due {
                    window.makeFirstResponder(nil); settle(host)
                    XCTAssertTrue(store.taskDraftStore?.latest(for: task.id)?.task.raw["dueDate"] is NSNull)
                    XCTAssertTrue(field.isDescendant(of: host))
                    XCTAssertTrue(window.makeFirstResponder(field))
                    let reopenedEditor = try XCTUnwrap(window.fieldEditor(true, for: field) as? NSTextView)
                    reopenedEditor.insertText("06/01/2027", replacementRange: NSRange(location: 0, length: reopenedEditor.string.utf16.count)); settle(host)
                    XCTAssertEqual(store.taskDraftStore?.latest(for: task.id)?.task.raw["dueDate"] as? String, "2027-01-06")
                } else {
                    editor.insertText("01/02/2026", replacementRange: NSRange(location: 0, length: editor.string.utf16.count)); settle(host)
                    XCTAssertEqual(store.taskDraftStore?.latest(for: task.id)?.task.raw["date"] as? String, "2026-02-01")
                }
                let data = try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let saved = try XCTUnwrap((object["tasks"] as? [[String: Any]])?.first)
                XCTAssertEqual(saved["date"] as? String, "2026-12-31"); XCTAssertEqual(saved["dueDate"] as? String, "2027-01-05")
            }
        }
    }
    func testEscapeRestoresTheDateDraftWithTheTaskFormsCancelActionPresent() async throws {
        try await withTaskEditor { _, store, task, host, window in
            let field = try dateField("31/12/2026", in: host)
            XCTAssertTrue(window.makeFirstResponder(field))
            let editor = try XCTUnwrap(window.fieldEditor(true, for: field) as? NSTextView)
            editor.insertText("01/02/2026", replacementRange: NSRange(location: 0, length: editor.string.utf16.count)); settle(host)
            XCTAssertEqual(store.taskDraftStore?.latest(for: task.id)?.task.raw["date"] as? String, "2026-02-01")
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
            editor.keyDown(with: event); settle(host)
            let result = store.taskDraftStore?.latest(for: task.id)?.task ?? task
            XCTAssertEqual(result.raw["date"] as? String, "2026-12-31")
            XCTAssertEqual(field.stringValue, "31/12/2026")
        }
    }
    func testVisitingLegacyScheduledFallbackDoesNotCreateADraft() async throws {
        try await withTaskEditor(legacy: true) { _, store, task, host, window in
            func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
            let field = try XCTUnwrap(nodes(host).compactMap { $0 as? NSTextField }.first { $0.isEditable && $0.placeholderString == "DD/MM/YYYY" })
            XCTAssertNil(task.raw["date"]); XCTAssertNil(store.taskDraftStore?.latest(for: task.id))
            XCTAssertTrue(window.makeFirstResponder(field)); settle(host)
            window.makeFirstResponder(nil); settle(host)
            XCTAssertNil(store.taskDraftStore?.latest(for: task.id), "Reading the created-date fallback must not add a date or updatedAt field")
        }
    }
    private func settle(_ host: NSView) { for _ in 0..<5 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) } }
    private func dateField(_ value: String, in host: NSView) throws -> NSTextField {
        func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
        return try XCTUnwrap(nodes(host).compactMap { $0 as? NSTextField }.first { $0.isEditable && $0.stringValue == value })
    }
    private func withTaskEditor(legacy: Bool = false, _ operation: (URL, MacWorkspace, NativeTask, NSView, NSWindow) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-date-task-" + UUID().uuidString)
        let suite = "Zerus-date-task-prefs-" + UUID().uuidString, preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let defaults = UserDefaults.standard, recent = defaults.object(forKey: "zerus.mac.recentVaults")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".zerus"), withIntermediateDirectories: true)
        let source = #"{"tasks":[{"id":"date-task","title":"Calendar task","date":"2026-12-31","dueDate":"2027-01-05","createdAt":"2026-11-01T00:00:00Z","completed":false,"priority":"none","linkedNoteIds":[]}],"lists":[],"categoryOptions":[]}"#
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any])
        if legacy {
            var rows = try XCTUnwrap(object["tasks"] as? [[String: Any]]); rows[0].removeValue(forKey: "date"); object["tasks"] = rows
        }
        try JSONSerialization.data(withJSONObject: object).write(to: root.appendingPathComponent(".zerus/tasks.json"))
        preferences.set("DD/MM/YYYY", forKey: "zerus.mac.dateFormat")
        let store = MacWorkspace(); await store.openVault(root)
        let task = try XCTUnwrap(store.tasks.first)
        let host = NSHostingView(rootView: MacTaskEditor(store: store, task: task).defaultAppStorage(preferences))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 850), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer {
            window.contentView = nil; window.close()
            if let directory = store.taskDraftStore?.directory { try? FileManager.default.removeItem(at: directory) }
            preferences.removePersistentDomain(forName: suite)
            defaults.set(recent, forKey: "zerus.mac.recentVaults"); defaults.removeObject(forKey: MacNavigationState.key(root)); defaults.removeObject(forKey: "zerus.mac.bookmark." + NativeHistory.hash(root.path))
            try? FileManager.default.removeItem(at: root)
        }
        settle(host)
        try await operation(root, store, task, host, window)
    }

}
