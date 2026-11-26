import XCTest
@testable import Zerus_Native

final class MacTitleFileSyncTests: XCTestCase {
    func testUntitledFilesFollowTheirNewTitle() {
        XCTAssertEqual(MacTitleFileSync.title(path: "Inbox/Untitled.md", title: "WeldCloud & OZ Steps Integration", openedTitle: "Untitled"), "WeldCloud & OZ Steps Integration")
        XCTAssertEqual(MacTitleFileSync.title(path: "Untitled 3.md", title: "Plan", openedTitle: "Plan"), "Plan")
    }
    func testFilesNamedAfterTheirPreviousTitleFollowTheTitle() {
        XCTAssertEqual(MacTitleFileSync.title(path: "Work/Draft: plan.md".replacingOccurrences(of: ":", with: "-"), title: "Final plan", openedTitle: "Draft: plan"), "Final plan")
        XCTAssertEqual(MacTitleFileSync.title(path: "Work/Meeting 2.md", title: "Kickoff", openedTitle: "Meeting"), "Kickoff")
    }
    func testIndependentlyNamedFilesAndUnchangedTitlesKeepTheirName() {
        XCTAssertNil(MacTitleFileSync.title(path: "Work/Specs.md", title: "Project X", openedTitle: "Project W"))
        XCTAssertNil(MacTitleFileSync.title(path: "Work/Plan.md", title: "plan", openedTitle: "Plan"), "Case-only differences keep the file")
        XCTAssertNil(MacTitleFileSync.title(path: "Work/Plan.md", title: "Plan", openedTitle: "Plan"))
        XCTAssertNil(MacTitleFileSync.title(path: ".zerus/links/Untitled.md", title: "Link", openedTitle: "Untitled"))
        XCTAssertNil(MacTitleFileSync.title(path: ".trash/Untitled.md", title: "Gone", openedTitle: "Untitled"))
    }
}
