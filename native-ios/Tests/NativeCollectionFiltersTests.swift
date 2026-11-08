import XCTest
@testable import ZerusNative

final class NativeCollectionFiltersTests: XCTestCase {
    func testScannedCollectionsRetainTypedPropertyDatesFoldersBirthDatesAndFileFiltersWithoutChangingBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let io = VaultFiles(root: root)
        let fixtures = [
            "Work/Alpha.md": "---\nScore: 1\nReady: true\nLabels: [Red, Blue]\nDue: 2026-11-01\n---\n# Alpha 2\nCafé evidence.",
            "Work/Sub/Beta.md": "---\nScore: \"1\"\nReady: \"true\"\nLabels: [Blue]\nDue: 2026-11-08\nzerus-archived: true\n---\n# Alpha 10\nArchived evidence.",
            "Work/Gamma.md": "---\nScore: 2\nReady: false\nLabels: [Green]\nDue: 2026-11-05\n---\n# Gamma\nOther evidence.",
            "Pinned.md": "---\nzerus-pinned: true\n---\n# Pinned\nAlways first.",
            ".trash/Old.md": "# Old\nNever in ordinary collections.",
            "Reports/Old.pdf": "Old document", "Reports/New.txt": "New document"
        ]
        func day(_ value: String) -> Date { ISO8601DateFormatter().date(from: value + "T12:00:00Z")! }
        for (path, text) in fixtures {
            try await io.write(path, data: Data(text.utf8), expected: nil)
            let modified = path.contains("Gamma") || path.contains("Old") || path.contains("Pinned") ? day("2026-10-31") : day("2026-11-01")
            let created = path.contains("Alpha") || path.contains("Old") ? day("2026-10-01") : day("2026-10-15")
            try FileManager.default.setAttributes([.creationDate: created, .modificationDate: modified], ofItemAtPath: root.appendingPathComponent(path).path)
        }
        let snapshot = try await io.scan(), notes = snapshot.notes
        let alpha = try XCTUnwrap(notes.first { $0.path == "Work/Alpha.md" })
        XCTAssertEqual(alpha.created, day("2026-10-01")); XCTAssertEqual(alpha.modified, day("2026-11-01"))
        XCTAssertEqual(snapshot.fileDates["Reports/Old.pdf"]?.created, day("2026-10-01"))
        func paths(_ filters: NativeCollectionFilters, query: String = "") -> [String] { filters.apply(notes, query: query, now: day("2026-11-07"), calendar: Calendar(identifier: .gregorian)).map(\.path) }
        var filters = NativeCollectionFilters()
        XCTAssertEqual(paths(filters).first, "Pinned.md"); XCTAssertFalse(paths(filters).contains("Work/Sub/Beta.md")); XCTAssertFalse(paths(filters).contains(".trash/Old.md"))
        XCTAssertEqual(paths(filters, query: "cafe"), ["Work/Alpha.md"])
        filters.includeArchived = true; filters.folders = ["Work"]
        XCTAssertEqual(Set(paths(filters)), ["Work/Alpha.md", "Work/Gamma.md"], "Exact folder filters must not silently include child folders")
        filters.folders = []; filters.date = .week
        XCTAssertEqual(Set(paths(filters)), ["Work/Alpha.md", "Work/Sub/Beta.md"])
        filters.date = .today; XCTAssertTrue(paths(filters).isEmpty)
        filters.date = .any
        let number = NativeCollectionValue(kind: .number, value: "1"), text = NativeCollectionValue(kind: .text, value: "1")
        filters.properties = [.init(name: "score", values: [number])]
        XCTAssertEqual(paths(filters), ["Work/Alpha.md"])
        filters.properties = [.init(name: "Score", values: [text])]
        XCTAssertEqual(paths(filters), ["Work/Sub/Beta.md"], "Text and numeric values with the same label are distinct")
        filters.properties.append(.init(name: "Ready", values: [.init(kind: .checkbox, value: "false")]))
        XCTAssertTrue(paths(filters).isEmpty)
        filters.matchAnyProperty = true; XCTAssertEqual(Set(paths(filters)), ["Work/Sub/Beta.md", "Work/Gamma.md"])
        filters.matchAnyProperty = false
        filters.properties = [.init(name: "Labels", values: [.init(kind: .text, value: "Blue"), .init(kind: .text, value: "Green")])]
        XCTAssertEqual(Set(paths(filters)), ["Work/Alpha.md", "Work/Sub/Beta.md", "Work/Gamma.md"])
        filters.properties = [.init(name: "Ready")]; XCTAssertEqual(paths(filters).count, 3)
        filters.properties = [.init(name: "Ready", values: [])]; XCTAssertTrue(paths(filters).isEmpty)
        let comparisons: [(NativePropertyDateComparison, String, String, Set<String>)] = [
            (.on, "2026-11-05", "", ["Work/Gamma.md"]), (.before, "2026-11-05", "", ["Work/Alpha.md"]),
            (.after, "2026-11-05", "", ["Work/Sub/Beta.md"]), (.onOrBefore, "2026-11-05", "", ["Work/Alpha.md", "Work/Gamma.md"]),
            (.onOrAfter, "2026-11-05", "", ["Work/Gamma.md", "Work/Sub/Beta.md"]),
            (.between, "2026-11-08", "2026-11-05", ["Work/Gamma.md", "Work/Sub/Beta.md"])
        ]
        for (comparison, date, end, expected) in comparisons {
            filters.properties = [.init(name: "Due", dateComparison: comparison, date: date, endDate: end)]
            XCTAssertEqual(Set(paths(filters)), expected, comparison.rawValue)
        }
        let options = NativeCollectionFilters.options(notes)
        XCTAssertTrue(try XCTUnwrap(options.first { $0.name == "Due" }).isDate)
        XCTAssertFalse(options.contains { $0.name.hasPrefix("zerus-") })
        XCTAssertEqual(try XCTUnwrap(options.first { $0.name == "Score" }).values.count, 3)
        filters = .init(); filters.includeArchived = true
        let unpinned = notes.filter { !$0.pinned && !$0.trashed }
        let expected: [(NativeNoteSort, [String])] = [
            (.titleAscending, ["Work/Alpha.md", "Work/Sub/Beta.md", "Work/Gamma.md"]),
            (.titleDescending, ["Work/Gamma.md", "Work/Sub/Beta.md", "Work/Alpha.md"]),
            (.createdAscending, ["Work/Alpha.md", "Work/Gamma.md", "Work/Sub/Beta.md"]),
            (.createdDescending, ["Work/Gamma.md", "Work/Sub/Beta.md", "Work/Alpha.md"]),
            (.updatedAscending, ["Work/Gamma.md", "Work/Alpha.md", "Work/Sub/Beta.md"]),
            (.updatedDescending, ["Work/Alpha.md", "Work/Sub/Beta.md", "Work/Gamma.md"])
        ]
        for (sort, order) in expected { filters.sort = sort; XCTAssertEqual(filters.apply(unpinned).map(\.path), order, sort.rawValue) }
        filters = .init(); filters.extensions = ["pdf"]
        XCTAssertEqual(filters.applyFiles(snapshot.files, dates: snapshot.fileDates), ["Reports/Old.pdf"])
        filters.extensions = []; filters.sort = .createdDescending
        XCTAssertEqual(filters.applyFiles(snapshot.files, dates: snapshot.fileDates), ["Reports/New.txt", "Reports/Old.pdf"])
        filters.date = .week
        XCTAssertEqual(filters.applyFiles(snapshot.files, dates: snapshot.fileDates, now: day("2026-11-07"), calendar: Calendar(identifier: .gregorian)), ["Reports/New.txt"])
        filters.date = .any; filters.properties = [.init(name: "Ready")]
        XCTAssertTrue(filters.applyFiles(snapshot.files, dates: snapshot.fileDates).isEmpty)
        let declaredText = NativeSchemaSnapshot(root: root, bytes: Data(#"{"Work":[{"name":"Due","type":"text"}]}"#.utf8))
        XCTAssertFalse(try XCTUnwrap(NativeCollectionFilters.options(notes, schema: declaredText).first { $0.name == "Due" }).isDate, "Date-looking text should respect an explicit text definition")
        let hubs = [
            ".zerus/files/Manual.md": "---\nzerus-file-id: manual\nzerus-file-name: Manual.PDF\nzerus-file-kind: vault\nzerus-file-path: Reports/Old.pdf\n---\n# Zed\nPortable document note.",
            ".zerus/files/Text.md": "---\nzerus-file-id: text\nzerus-file-name: Zeta.txt\nzerus-file-kind: vault\nzerus-file-path: Reports/New.txt\n---\n# Aardvark\nAnother document note."
        ]
        for (path, text) in hubs { try await io.write(path, data: Data(text.utf8), expected: nil) }
        let hubNotes = try await io.scan().notes.filter { $0.fileHub != nil }
        filters = .init(); filters.extensions = ["pdf"]
        XCTAssertEqual(filters.apply(hubNotes).map(\.path), [".zerus/files/Manual.md"])
        filters.extensions = []; filters.sort = .titleAscending
        XCTAssertEqual(filters.apply(hubNotes, fileNames: true).map(\.title), ["Zed", "Aardvark"], "File collections sort by document filename")
        // Reading collection cards must show labels, not storage destinations,
        // while code remains literal and the original files remain untouched.
        let previews: [(String, String)] = [
            ("# Preview\n\nSee [[zerus:private-id|Roadmap]] and [**bold** `code` plain](#zerus-note:zerus%3Aprivate-id%7Cbold%20code%20plain); [web](https://example.com/a_(b)).\n\n![Chart](assets/private-image.png)", "See Roadmap and bold code plain; web. Chart"),
            ("# Preview\n\n`keep_this [[literal|source]]`\n\n~~~swift\nlet snake_case = \"[[literal|target]]\"\n~~~\n\n- [x] Complete\n> Quoted **words** &amp; more.", "keep_this [[literal|source]] let snake_case = \"[[literal|target]]\" Complete Quoted words & more."),
            ("# Preview\n\n[![Chart caption][img]][page]\n\n[img]: assets/private-image.png\n[page]: https://example.com/private\n\n| Topic | Detail |\n| --- | --- |\n| [[zerus:private-id\\|Table alias]] | **Ready** |\n<!-- zerus-table-widths: [160, 220] -->", "Chart caption Topic Detail Table alias Ready"),
            ("# Preview\r\n\r\n## Details\r\nA \\[literal\\] and [bracket \\] label](#zerus-note:zerus%3Aprivate-id%7Cbracket%20%5D%20label).\r\n", "Details A [literal] and bracket ] label."),
            ("---\nzerus-link-id: preview-link\nzerus-link-url: https://example.com/private\nforeign: keep\n---\n# Preview\n\nhttps://example.com/private\n\nA [[zerus:private-id|readable saved page]].\n\n`https://example.com/private`\n\nVisit https://example.com/private today.", "A readable saved page. https://example.com/private Visit https://example.com/private today."),
            ("---\nzerus-link-id: invalid-preview\nzerus-link-url: https://\n---\n# Preview\n\nKeep this paragraph.", "Keep this paragraph."),
        ]
        for (index, fixture) in previews.enumerated() {
            let path = "Preview/Case\(index).md", bytes = Data(fixture.0.utf8)
            try await io.write(path, data: bytes, expected: nil)
            let scanned = try await io.scan(), card = try XCTUnwrap(scanned.notes.first { $0.path == path })
            XCTAssertEqual(card.snippet, fixture.1, path)
            let after = try await io.read(path); XCTAssertEqual(after, bytes, "Browsing a preview must not rewrite its Markdown")
        }
        for (path, text) in hubs { let actual = try await io.read(path); XCTAssertEqual(actual, Data(text.utf8)) }
        for (path, text) in fixtures { let actual = try await io.read(path); XCTAssertEqual(actual, Data(text.utf8), path) }
    }
}
