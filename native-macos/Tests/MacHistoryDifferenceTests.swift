import XCTest
@testable import Zerus_Native

final class MacHistoryDifferenceTests: XCTestCase {
    func testLineComparisonKeepsSourceAlignmentBlankLinesRepeatedLinesAndUnicodeHighlights() throws {
        for (before, after, added, removed) in [
            ("", "First line", 1, 0), ("Only line", "", 0, 1),
            ("First\nrepeat\nrepeat\nLast\n", "First\nrepeat\nchanged\nLast\n", 1, 1),
            ("# Title\n\nCafé 🧑🏽‍💻\n", "# Title\n\n日本語 🧑🏽‍💻\n", 1, 1),
            ("Unchanged\n\n", "Unchanged\n\n", 0, 0),
        ] {
            let report = try MacHistoryDifference.compare(before: before, after: after)
            try assertSources(report, before: before, after: after)
            XCTAssertEqual(report.added, added); XCTAssertEqual(report.removed, removed)
        }
        let highlight = MacHistoryDifference.highlight("Status: 🧑🏽‍💻 café done", comparedWith: "Status: 🧑🏽‍🎨 tea done")
        XCTAssertEqual(highlight.prefix, "Status: "); XCTAssertEqual(highlight.changed, "🧑🏽‍💻 café"); XCTAssertEqual(highlight.suffix, " done")
    }
    func testLargeComparisonsRetainCommonContextAndEveryChangedLine() async throws {
        let prefix = (0..<1000).map { "Before context \($0)" }.joined(separator: "\n") + "\n", suffix = "\n" + (0..<1000).map { "After context \($0)" }.joined(separator: "\n")
        let before = prefix + "Original paragraph" + suffix, after = prefix + "Updated paragraph" + suffix
        let localized = try MacHistoryDifference.compare(before: before, after: after)
        try assertSources(localized, before: before, after: after)
        XCTAssertEqual(localized.added, 1); XCTAssertEqual(localized.removed, 1); XCTAssertEqual(localized.lines.filter { $0.kind == .same }.count, 2000)
        let broadBefore = "Shared header\n" + (0..<600).map { "Original \($0)" }.joined(separator: "\n") + "\nShared footer"
        let broadAfter = "Shared header\n" + (0..<600).map { "Replacement \($0)" }.joined(separator: "\n") + "\nShared footer"
        let broad = try MacHistoryDifference.compare(before: broadBefore, after: broadAfter)
        try assertSources(broad, before: broadBefore, after: broadAfter)
        XCTAssertEqual(broad.added, 600); XCTAssertEqual(broad.removed, 600); XCTAssertEqual(broad.lines.filter { $0.kind == .same }.count, 2)
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try MacHistoryDifference.compare(before: broadBefore, after: broadAfter)
        }
        do { _ = try await canceled.value; XCTFail("A canceled comparison must stop without returning a partial report") } catch is CancellationError {}

    }
    private func assertSources(_ report: MacHistoryDifference.Report, before: String, after: String) throws {
        let oldLines = before.isEmpty ? [] : before.components(separatedBy: "\n"), newLines = after.isEmpty ? [] : after.components(separatedBy: "\n")
        XCTAssertEqual(report.lines.filter { $0.kind != .added }.map(\.text), oldLines)
        XCTAssertEqual(report.lines.filter { $0.kind != .removed }.map(\.text), newLines)
        XCTAssertEqual(report.lines.compactMap(\.before), Array(1..<(oldLines.count + 1)))
        XCTAssertEqual(report.lines.compactMap(\.after), Array(1..<(newLines.count + 1)))
    }
}
