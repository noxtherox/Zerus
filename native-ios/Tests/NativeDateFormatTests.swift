import XCTest
@testable import ZerusNative

final class NativeDateFormatTests: XCTestCase {
    func testCalendarDaysKeepTheirMeaningWhileInstantsUseTheDisplayTimezone() throws {
        // A stored calendar day must not be parsed as an instant and shifted
        // across midnight; a timestamp must use the person's display timezone.
        let leapDay = "2028-02-29"
        XCTAssertEqual(NativeDateFormat.dayFirst.string(day: leapDay), "29/02/2028")
        XCTAssertEqual(NativeDateFormat.monthFirst.string(day: leapDay), "02/29/2028")
        XCTAssertEqual(NativeDateFormat.iso.string(day: leapDay), leapDay)
        XCTAssertEqual(NativeDateFormat.dotted.string(day: leapDay), "29.02.2028")
        for invalid in ["2026-02-29", "2026-13-01", "2026-1-2", "unknown", ""] {
            XCTAssertEqual(NativeDateFormat.dotted.string(day: invalid), invalid)
        }
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-31T12:30:00Z"))
        var east = Calendar(identifier: .buddhist); east.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        var west = Calendar(identifier: .gregorian); west.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Pago_Pago"))
        XCTAssertEqual(NativeDateFormat.iso.string(date: instant, calendar: east), "2027-01-01", "Display timezones apply, but stored Gregorian years must not become Buddhist or week-based years")
        XCTAssertEqual(NativeDateFormat.dayFirst.string(date: instant, calendar: west), "31/12/2026")
    }
}
