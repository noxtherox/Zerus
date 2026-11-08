import XCTest
@testable import ZerusNative

final class NativeMoveResourcesTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testReviewedMovePreservesFileBindingsPortableLinksAndUntouchedSourceBytes() async throws {
        let io = VaultFiles(root: root!)
        let body = #"""
        # Move me
        ![Plot](./assets/local%2520.png "Caption")
        [PDF][report]

        [report]: <./files/report%20one.pdf?download=1#page=2> 'Report title'
        [Self](Note.MD#details) and [[Projects/Project.md|Project plan]].
        [Mixed **project**](#zerus-note:Projects%2FProject%2Emd%7CProject%20plan)
        |  Note   | Attachment |
        | :------ | ---------: |
        | [[Projects/Project.md\|Table caption]] | ![Plot](./assets/local%2520.png) |
        <img src="./assets/local%2520.png" alt="Original caption">
        <a href="./files/report%20one.pdf?download=1&amp;mode=print">HTML PDF</a>
        `![Literal](./assets/local%2520.png)`
        \[Escaped](./assets/local%2520.png)
        <!-- ![Comment](./assets/local%2520.png) -->
        > ```md
        > ![Code](./assets/local%2520.png)
        > ```

            [Indented](./files/report%20one.pdf)

        """#.replacingOccurrences(of: "\n", with: "\r\n")
        let original = "---\r\nzerus-id: moved\r\nForeign:\r\n  keep: [one, two] # comment\r\n---\r\n" + body
        let incoming = "# Incoming\r\n[Open](../Work/Note.MD?view=1#details \"Keep title\")\r\n[**Native** caption](#zerus-note:Work%2FNote%2EMD%7COld%20%5Bcaption%5D)\r\n|  Target  | Keep |\r\n| -------- | ---- |\r\n| [[Work/Note.MD\\|Old caption]] | same |\r\n"
        let deleted = "# Deleted\n[Open](../Work/Note.MD)\n"
        let project = "---\nzerus-id: project\n---\n# Project\nProject body.\n"
        let fixtures = [("Work/Note.MD", original), ("Inbox/Incoming.md", incoming), (".trash/Inbox/Deleted.md", deleted), ("Projects/Project.md", project)]
        for (path, content) in fixtures { try await io.write(path, data: Data(content.utf8), expected: nil) }
        let image = Data([137, 80, 78, 71, 0, 255]), pdf = Data("%PDF-original\n".utf8), shadow = Data("Wrong file".utf8)
        for (path, data) in [("Work/assets/local%20.png", image), ("Work/files/report one.pdf", pdf), ("assets/local%20.png", shadow)] { try await io.write(path, data: data, expected: nil) }
        let snapshot = try await io.relationDefinitionSnapshot()
        let plan = try await io.prepareMove(snapshot, source: "Work/Note.MD", destination: "Archive/Done/Note.MD")
        let unconfirmed = try await io.read("Work/Note.MD"); XCTAssertEqual(unconfirmed, Data(original.utf8))
        let moved = try await io.applyRelationMaintenance(plan)
        let saved = try XCTUnwrap(moved.notes.first { $0.path == "Archive/Done/Note.MD" })
        let expected = original
            .replacingOccurrences(of: "![Plot](./assets/local%2520.png", with: "![Plot](../../Work/assets/local%2520.png")
            .replacingOccurrences(of: "<./files/report%20one.pdf?", with: "<../../Work/files/report%20one.pdf?")
            .replacingOccurrences(of: "(Note.MD#details)", with: "(./Note.MD#details)")
            .replacingOccurrences(of: "[[Projects/Project.md|Project plan]]", with: "[[zerus:project|Project plan]]")
            .replacingOccurrences(of: "#zerus-note:Projects%2FProject%2Emd%7CProject%20plan", with: "#zerus-note:zerus%3Aproject%7CProject%20plan")
            .replacingOccurrences(of: "[[Projects/Project.md\\|Table caption]]", with: "[[zerus:project\\|Table caption]]")
            .replacingOccurrences(of: "src=\"./assets/local%2520.png\"", with: "src=\"../../Work/assets/local%2520.png\"")
            .replacingOccurrences(of: "href=\"./files/report%20one.pdf?", with: "href=\"../../Work/files/report%20one.pdf?")
        XCTAssertEqual(saved.content, expected)
        let incomingAfter = try await io.read("Inbox/Incoming.md"), deletedAfter = try await io.read(".trash/Inbox/Deleted.md")
        XCTAssertEqual(incomingAfter, Data(incoming.replacingOccurrences(of: "../Work/Note.MD?", with: "../Archive/Done/Note.MD?").replacingOccurrences(of: "[[Work/Note.MD\\|Old caption]]", with: "[[zerus:moved\\|Old caption]]").replacingOccurrences(of: "#zerus-note:Work%2FNote%2EMD%7COld%20%5Bcaption%5D", with: "#zerus-note:zerus%3Amoved%7COld%20%5Bcaption%5D").utf8))
        XCTAssertEqual(deletedAfter, Data(deleted.replacingOccurrences(of: "../Work/Note.MD", with: "../Archive/Done/Note.MD").utf8))
        let imageAfter = try await io.resourceData("../../Work/assets/local%2520.png", notePath: saved.path)
        let pdfAfter = try await io.resourceData("../../Work/files/report%20one.pdf?download=1#page=2", notePath: saved.path)
        XCTAssertEqual(imageAfter, image); XCTAssertEqual(pdfAfter, pdf)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/Note.MD").path))
        let projectAfter = try await io.read("Projects/Project.md"), shadowAfter = try await io.read("assets/local%20.png")
        XCTAssertEqual(projectAfter, Data(project.utf8)); XCTAssertEqual(shadowAfter, shadow)
    }

    func testReviewedMoveRejectsNewIncomingLinksAndReboundResourcesBeforeWriting() async throws {
        let io = VaultFiles(root: root!)
        let source = Data("# Moving\n![Plot](plot.png)\n".utf8), other = Data("# Observer\nUnlinked.\n".utf8)
        try await io.write("Work/Moving.md", data: source, expected: nil)
        try await io.write("Other.md", data: other, expected: nil)
        try await io.write("plot.png", data: Data("Root image".utf8), expected: nil)
        let snapshot = try await io.relationDefinitionSnapshot()
        let plan = try await io.prepareMove(snapshot, source: "Work/Moving.md", destination: "Archive/Moving.md")
        let outside = Data("# Observer\n[New link](Work/Moving.md)\n".utf8)
        try await io.write("Other.md", data: outside, expected: other)
        do { _ = try await io.applyRelationMaintenance(plan); XCTFail("An incoming link added during review must invalidate the move") }
        catch { XCTAssertTrue(error.localizedDescription.contains("changed outside")) }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/Moving.md").path) else { return }
        let sourceAfter = try await io.read("Work/Moving.md"); XCTAssertEqual(sourceAfter, source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Archive/Moving.md").path))
        try await io.write("Other.md", data: other, expected: outside)
        try await io.write("Work/plot.png", data: Data("New local image".utf8), expected: nil)
        do { _ = try await io.applyRelationMaintenance(plan); XCTFail("A resource that resolves to a different file must invalidate the move") }
        catch { XCTAssertTrue(error.localizedDescription.contains("linked file changed")) }
        let final = try await io.read("Work/Moving.md"); XCTAssertEqual(final, source)
    }
    func testMoveProtectsUnresolvedAndAmbiguousTargetsAndKeepsLiteralHTMLAndImageLabels() async throws {
        let io = VaultFiles(root: root!)
        let missing = Data("# Literal owner\n![Plot](plot.png)\n".utf8)
        try await io.write("Work/Owner.md", data: missing, expected: nil)
        var snapshot = try await io.relationDefinitionSnapshot()
        do { _ = try await io.prepareMove(snapshot, source: "Work/Owner.md", destination: "Archive/Owner.md"); XCTFail("Missing local resources must be resolved before moving") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unavailable")) }
        let originalAfter = try await io.read("Work/Owner.md"); XCTAssertEqual(originalAfter, missing)
        try await io.write("Work/plot.png", data: Data("Image".utf8), expected: nil)
        let project = "---\nzerus-id: project\n---\n# Duplicated\n"
        try await io.write("Projects/Project.md", data: Data(project.utf8), expected: nil)
        try await io.write("Other/Second.md", data: Data("# Duplicated\n".utf8), expected: nil)
        let ambiguous = Data("# Literal owner\n[[Duplicated]]\n".utf8)
        try await io.write("Work/Owner.md", data: ambiguous, expected: missing)
        snapshot = try await io.relationDefinitionSnapshot()
        do { _ = try await io.prepareMove(snapshot, source: "Work/Owner.md", destination: "Archive/Owner.md"); XCTFail("Ambiguous outgoing links must be resolved before moving") }
        catch { XCTAssertTrue(error.localizedDescription.contains("ambiguous")) }
        let source = #"""
        # Literal owner 👩🏾‍💻
        [[Projects/Project.md|Chosen project]]
        <img data-src="wrong.png" alt="src='wrong.png'" src="plot.png">
        ![Image [[Duplicated]]][plot]

        [plot]: plot.png

        ``example ` [[Duplicated]]``
        <pre><img src="wrong.png">[[Duplicated]]</pre>
        <script>let image = "![Plot](wrong.png)";</script>

        """#
        try await io.write("Work/wrong.png", data: Data("Literal example only".utf8), expected: nil)
        try await io.write("Work/Owner.md", data: Data(source.utf8), expected: ambiguous)
        snapshot = try await io.relationDefinitionSnapshot()
        let plan = try await io.prepareMove(snapshot, source: "Work/Owner.md", destination: "Archive/Owner.md")
        _ = try await io.applyRelationMaintenance(plan)
        let saved = try await io.read("Archive/Owner.md")
        let expected = source.replacingOccurrences(of: "[[Projects/Project.md|Chosen project]]", with: "[[zerus:project|Chosen project]]")
            .replacingOccurrences(of: "src=\"plot.png\"", with: "src=\"../Work/plot.png\"")
            .replacingOccurrences(of: "[plot]: plot.png", with: "[plot]: ../Work/plot.png")
        XCTAssertEqual(saved, Data(expected.utf8))
    }

}
