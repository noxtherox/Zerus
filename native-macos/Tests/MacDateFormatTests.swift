import XCTest
import SwiftUI
import AppKit
@testable import Zerus_Native

@MainActor final class MacDateFormatTests: XCTestCase {
    private final class Model: ObservableObject {
        @Published var value = "2026-12-31"
        @Published var valid = true
    }
    private struct Fixture: View {
        @ObservedObject var model: Model
        let publishOnEdit: Bool
        let allowEmpty: Bool
        var body: some View { MacDateField("Scheduled", value: $model.value, valid: $model.valid, allowEmpty: allowEmpty, publishOnEdit: publishOnEdit).padding().frame(width: 400, height: 160) }
    }
    func testNumericDateFieldsPublishISOValuesAndRetainInvalidInput() throws {
        for (format, initial, entered, expected) in [
            ("DD/MM/YYYY", "31/12/2026", "1/2/2026", "2026-02-01"),
            ("MM/DD/YYYY", "12/31/2026", "2/1/2026", "2026-02-01"),
            ("YYYY-MM-DD", "2026-12-31", "2026-2-1", "2026-02-01"),
            ("DD.MM.YYYY", "31.12.2026", "1.2.2026", "2026-02-01"),
            ("unknown", "31/12/2026", "1/2/2026", "2026-02-01")
        ] {
            try withField(format: format) { model, _, host, window, field in
                XCTAssertEqual(field.stringValue, initial); XCTAssertEqual(model.value, "2026-12-31")
                let editor = try edit(entered, field: field, window: window); settle(host)
                XCTAssertEqual(model.value, expected); XCTAssertTrue(model.valid)
                let beforeInvalid = model.value
                editor.insertText("not a date", replacementRange: NSRange(location: 0, length: editor.string.utf16.count)); settle(host)
                XCTAssertEqual(model.value, beforeInvalid); XCTAssertFalse(model.valid)
                XCTAssertEqual(editor.string, "not a date", "Invalid text must remain visible so it can be corrected")
                window.makeFirstResponder(nil); settle(host)
                XCTAssertFalse(model.valid); XCTAssertEqual(field.stringValue, "not a date")
            }
        }
    }
    func testChangingFormatDuringTypingKeepsItsInterpretationAndFilterEditsCommitOnBlur() throws {
        try withField(format: "DD/MM/YYYY") { model, preferences, host, window, field in
            let editor = try edit("03/", field: field, window: window); settle(host)
            XCTAssertFalse(model.valid); XCTAssertEqual(model.value, "2026-12-31")
            preferences.set("MM/DD/YYYY", forKey: "zerus.mac.dateFormat"); settle(host)
            XCTAssertEqual(editor.string, "03/")
            editor.insertText("03/04/2026", replacementRange: NSRange(location: 0, length: editor.string.utf16.count)); settle(host)
            XCTAssertEqual(model.value, "2026-04-03", "The pending text began as day/month; a new preference cannot reinterpret it")
            window.makeFirstResponder(nil); settle(host)
            XCTAssertEqual(field.stringValue, "04/03/2026"); XCTAssertEqual(model.value, "2026-04-03")
        }
        try withField(format: "DD/MM/YYYY", publishOnEdit: false) { model, _, host, window, field in
            _ = try edit("01/02/2026", field: field, window: window); settle(host)
            XCTAssertEqual(model.value, "2026-12-31", "A filter must not persist intermediate valid prefixes")
            window.makeFirstResponder(nil); settle(host)
            XCTAssertEqual(model.value, "2026-02-01"); XCTAssertTrue(model.valid)
            let editor = try edit("02/03/2026", field: field, window: window); settle(host)
            XCTAssertEqual(model.value, "2026-02-01")
            editor.doCommand(by: NSSelectorFromString("insertNewline:")); settle(host)
            XCTAssertEqual(model.value, "2026-03-02"); XCTAssertTrue(model.valid)
        }
    }
    func testImportedTimestampDisplaysItsLocalDayWithoutRewritingOnFocusOrBlur() throws {
        let instant = try XCTUnwrap(NativeTask.parseDay("2026-01-01")).addingTimeInterval(12 * 3600)
        let source = ISO8601DateFormatter().string(from: instant)
        try withField(format: "DD/MM/YYYY", initialValue: source) { model, _, host, window, field in
            XCTAssertEqual(field.stringValue, "01/01/2026"); XCTAssertTrue(model.valid)
            XCTAssertTrue(window.makeFirstResponder(field)); settle(host)
            window.makeFirstResponder(nil); settle(host)
            XCTAssertEqual(model.value, source, "A display-only visit must preserve the original timestamp")
        }
        try withField(format: "DD/MM/YYYY", publishOnEdit: false, allowEmpty: false) { model, _, host, window, field in
            _ = try edit("", field: field, window: window); settle(host)
            window.makeFirstResponder(nil); settle(host)
            XCTAssertEqual(model.value, "2026-12-31"); XCTAssertFalse(model.valid); XCTAssertEqual(field.stringValue, "")
        }
    }
    func testDateFormattingKeepsCalendarDaysAndUsesLocalDaysForCompletionInstants() throws {
        for (format, expected): (MacNumericDateFormat, String) in [(.dayFirst, "31/12/2026"), (.monthFirst, "12/31/2026"), (.iso, "2026-12-31"), (.dotted, "31.12.2026")] {
            for zone in [-12, 0, 14] {
                XCTAssertEqual(format.display("2026-12-31", timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: zone * 3600))), expected)
            }
        }
        let west = try XCTUnwrap(TimeZone(secondsFromGMT: -10 * 3600)), east = try XCTUnwrap(TimeZone(secondsFromGMT: 14 * 3600))
        XCTAssertEqual(MacNumericDateFormat.dayFirst.display("2026-01-01T00:30:00.123Z", timeZone: west), "31/12/2025")
        XCTAssertEqual(MacNumericDateFormat.dayFirst.display("2026-01-01T23:30:00Z", timeZone: east), "02/01/2026")
        XCTAssertEqual(MacNumericDateFormat.dayFirst.display("2026-01-01T00:30Z", timeZone: west), "31/12/2025")
        XCTAssertEqual(MacNumericDateFormat.dayFirst.display("2026-01-01T00:30+05:30", timeZone: west), "31/12/2025")
        XCTAssertEqual(MacNumericDateFormat.dayFirst.display("2026-01-01T23:30:00", timeZone: west), "01/01/2026")
        XCTAssertEqual(MacNumericDateFormat.dayFirst.display("2026-02-30"), "2026-02-30")
        for value in ["29/02/2026", "29/02/1900", "31/04/2026", "1/13/2026", "12/31/2026", "1/2/26", "garbage"] { XCTAssertNil(MacNumericDateFormat.dayFirst.parse(value), value) }
        XCTAssertEqual(MacNumericDateFormat.dayFirst.parse("29/02/2000"), "2000-02-29")
        XCTAssertEqual(MacNumericDateFormat.dayFirst.parse("29/02/2024"), "2024-02-29")
        XCTAssertEqual(MacNumericDateFormat.dayFirst.parse("  "), "")
    }
    private func edit(_ value: String, field: NSTextField, window: NSWindow) throws -> NSTextView {
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(window.fieldEditor(true, for: field) as? NSTextView)
        editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        return editor
    }
    private func settle(_ host: NSView) { for _ in 0..<5 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.01)) } }
    private func withField(format: String, publishOnEdit: Bool = true, allowEmpty: Bool = true, initialValue: String = "2026-12-31", operation: (Model, UserDefaults, NSView, NSWindow, NSTextField) throws -> Void) throws {
        let suite = "Zerus-date-" + UUID().uuidString, preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(format, forKey: "zerus.mac.dateFormat")
        let model = Model(); model.value = initialValue
        let host = NSHostingView(rootView: Fixture(model: model, publishOnEdit: publishOnEdit, allowEmpty: allowEmpty).defaultAppStorage(preferences))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        settle(host)
        func nodes(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(nodes) }
        let field = try XCTUnwrap(nodes(host).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        try operation(model, preferences, host, window, field)
    }
}
