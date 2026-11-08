import XCTest
@testable import ZerusNative

final class NativeTaskPlanningTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        let preferences = NativeVaultPreferencesBackup(); addTeardownBlock { preferences.restore() }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func write(_ value: Any) throws {
        let file = root.appendingPathComponent(".zerus/tasks.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: .sortedKeys).write(to: file, options: .atomic)
    }
    private func object() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))) as! [String: Any] }

    func testListAndCategoryChangesPreserveForeignDataAndTasksAndMigrateLegacyArrays() async throws {
        let io = VaultFiles(root: root)
        let legacy: [Any] = [["id": "a", "title": "Keep", "category": "Work", "foreign": ["preserve": true]], "future record"]
        try write(legacy)
        var saved = try await io.changeTasks(.createList(id: "work", name: "Projects"))
        XCTAssertEqual(saved.records.count, 2); XCTAssertEqual(saved.tasks.count, 1); XCTAssertNotNil(saved.warning)
        XCTAssertEqual(saved.records[1] as? String, "future record")
        XCTAssertEqual(saved.categories, ["Work"])
        XCTAssertEqual(try object()["categoryOptions"] as? [String], ["Work"], "The migrated object must retain legacy categories for the web client, not only in native memory")
        saved = try await io.changeTasks(.renameList(nil, originalName: "General", name: "Inbox"))
        let list = try XCTUnwrap(saved.lists.first)
        var task = try XCTUnwrap(saved.tasks.first); task.listID = list.id; task.date = "2026-11-07"; task.dueDate = "2026-11-09"
        saved = try await io.changeTasks(.save(task, delete: false))
        saved = try await io.changeTasks(.addCategory("Personal"))
        XCTAssertEqual(saved.categories, ["Work", "Personal"])
        let assigned = Set(saved.tasks.filter { $0.listID == list.id }.map(\.id))
        saved = try await io.changeTasks(.deleteList(list, assigned: assigned))
        XCTAssertTrue(saved.lists.isEmpty); XCTAssertEqual(saved.tasks.first?.listID, ""); XCTAssertEqual(saved.generalName, "Inbox")
        XCTAssertEqual(saved.tasks.first?.date, "2026-11-07"); XCTAssertEqual(saved.tasks.first?.dueDate, "2026-11-09")
        XCTAssertEqual((saved.tasks.first?.raw["foreign"] as? [String: Bool])?["preserve"], true)
        saved = try await io.changeTasks(.deleteCategory("work", assigned: ["a"]))
        XCTAssertEqual(saved.categories, ["Personal"]); XCTAssertEqual(saved.tasks.first?.category, "")
        XCTAssertEqual(saved.records[1] as? String, "future record")
        let bytes = try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))
        for name in [" inbox ", "Personal\nTwo lines", ""] {
            do { _ = try await io.changeTasks(.createList(id: UUID().uuidString, name: name)); XCTFail("Invalid/duplicate list should be rejected") } catch {}
        }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), bytes)
    }

    func testStaleManagementReviewsAndUnsupportedCollectionsCannotDiscardNewAssignmentsOrMetadata() async throws {
        let io = VaultFiles(root: root)
        let initial: [String: Any] = ["tasks": [["id": "a", "title": "First", "listId": "list", "category": "Work"]], "lists": [["id": "list", "name": "Original", "foreign": 17]], "categoryOptions": ["Work"], "foreignEnvelope": ["keep": true]]
        try write(initial)
        let original = try await io.taskData(), list = try XCTUnwrap(original.lists.first)
        var external = initial, tasks = initial["tasks"] as! [[String: Any]]
        tasks.append(["id": "b", "title": "Newly assigned", "listId": "list", "category": "work"]); external["tasks"] = tasks
        try write(external)
        let bytes = try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))
        for change in [NativeTaskChange.deleteList(list, assigned: ["a"]), .deleteCategory("Work", assigned: ["a"])] {
            do { _ = try await io.changeTasks(change); XCTFail("New assignments invalidate the review") } catch {}
        }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), bytes)
        let renamed = try await io.changeTasks(.renameList(list, originalName: "Original", name: "Renamed"))
        XCTAssertEqual(renamed.lists.first?.raw["foreign"] as? Int, 17)
        XCTAssertEqual((renamed.object["foreignEnvelope"] as? [String: Bool])?["keep"], true)
        do { _ = try await io.changeTasks(.renameList(list, originalName: "Original", name: "Stale rename")); XCTFail("Stale list names must not replace external names") } catch {}
        var unsupported = try object(); unsupported["lists"] = ["future format"]; unsupported["categoryOptions"] = ["future": true]; try write(unsupported)
        let preserved = try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))
        for change in [NativeTaskChange.createList(id: "new", name: "New"), .addCategory("New")] {
            do { _ = try await io.changeTasks(change); XCTFail("Unsupported containers must not be replaced") } catch {}
        }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), preserved)
    }

    func testUnsupportedTaskFieldsReplacementAndDeletedListAssignmentsLeaveOriginalBytesIntact() async throws {
        let initial: [String: Any] = ["id": "a", "title": "Original", "createdAt": "2026-11-01T12:00:00Z"]
        let io = VaultFiles(root: root)
        try write(["tasks": [initial], "lists": [["id": "work", "name": "Work"]], "categoryOptions": ["Research"]])
        let data = try await io.taskData(), baseline = try XCTUnwrap(data.tasks.first)
        var edited = baseline; edited.title = "Edited title"
        let malformed: [String: Any] = ["completed": 1, "priority": ["future": true], "date": 12, "dueDate": false, "listId": ["future"], "category": 12, "linkedNoteIds": ["valid", 1], "createdAt": 12, "completedAt": ["future"]]
        for (field, value) in malformed {
            var external = initial; external[field] = value
            try write(["tasks": [external], "foreignEnvelope": 42])
            let before = try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), loaded = try await io.taskData()
            XCTAssertTrue(loaded.tasks.isEmpty, "Unsupported field: " + field); XCTAssertNotNil(loaded.warning)
            do { _ = try await io.changeTasks(.save(edited, delete: false)); XCTFail("Unsupported field must block stale writes: " + field) } catch {}
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), before)
        }
        var replaced = initial; replaced["createdAt"] = "2026-11-02T12:00:00Z"
        try write(["tasks": [replaced]])
        let replacement = try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))
        do { _ = try await io.changeTasks(.save(edited, delete: false)); XCTFail("Reused task identities cannot receive an older draft") } catch {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), replacement)
        try write(["tasks": [initial], "lists": [], "categoryOptions": []])
        let removedCollections = try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json"))
        var list = baseline; list.listID = "work"
        var category = baseline; category.category = "Research"
        var new = NativeTask(title: "New task"); new.listID = "work"
        for task in [list, category, new] {
            do { _ = try await io.changeTasks(.save(task, delete: false)); XCTFail("Removed collections require another choice") } catch {}
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(".zerus/tasks.json")), removedCollections)
        }
    }

    func testTaskViewsUseScheduleRatherThanDeadlineAndCalendarBoundariesAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let parse = ISO8601DateFormatter(), now = try XCTUnwrap(parse.date(from: "2026-11-05T08:30:00Z"))
        func task(_ id: String, _ title: String, scheduled: String = "2026-11-05", created: String = "2026-11-01T12:00:00Z", done: String? = nil) -> NativeTask {
            NativeTask(["id": id, "title": title, "date": scheduled, "createdAt": created, "completed": done != nil, "completedAt": done as Any? ?? NSNull(), "category": id == "a" ? "work" : "Work", "priority": id == "b" ? "high" : "none", "listId": id == "b" ? "projects" : NSNull()])!
        }
        var deadline = task("c", "Deadline only", scheduled: "2026-11-04", created: "2026-11-05T12:00:00Z"); deadline.dueDate = "2026-11-05"
        let tasks = [task("a", "Zulu", created: "2026-11-03T12:00:00Z"), task("b", "Alpha", created: "2026-11-04T12:00:00Z"), deadline,
                     task("d", "Boundary", done: "2026-10-29T07:00:00Z"), task("e", "Old", done: "2026-10-29T06:59:59Z"), task("f", "Unrecognized completion", done: "unsupported")]
        var query = NativeTaskQuery()
        XCTAssertEqual(query.results(tasks, now: now, calendar: calendar).map(\.id), ["b", "a", "d"])
        query.view = .all
        XCTAssertEqual(query.results(tasks, now: now, calendar: calendar).map(\.id), ["c", "b", "a", "d"])
        query.view = .completed; query.showOlderCompleted = true
        XCTAssertEqual(query.results(tasks, now: now, calendar: calendar).map(\.id), ["d", "e", "f"])
        query.view = .all; query.showOlderCompleted = false; query.sort = .title
        XCTAssertEqual(query.results(tasks, now: now, calendar: calendar).map(\.id), ["b", "c", "a", "d"])
        query.category = "WORK"; query.priority = "high"; query.list = "projects"
        XCTAssertEqual(query.results(tasks, now: now, calendar: calendar).map(\.id), ["b"])
        XCTAssertNil(NativeTask.parseDay("2026-02-30")); XCTAssertEqual(NativeTask.day(now, calendar: calendar), "2026-11-05")
    }

    @MainActor
    func testQueuedTaskAndCollectionChangesMergeWithoutLosingOtherWindowFieldsAndRejectOldWorkspaceForms() async throws {
        try write(["tasks": [["id": "a", "title": "Original", "priority": "none", "foreign": 17]], "lists": [], "categoryOptions": []])
        let store = VaultStore(); await store.open(root)
        let origin = store.workspaceID, baseline = try XCTUnwrap(store.tasks.first)
        var title = baseline; title.title = "A title from one window"
        var priority = baseline; priority.priority = "high"
        async let first = store.saveTask(title)
        async let second = store.saveTask(priority)
        async let collection = store.changeTasks(.createList(id: "projects", name: "Projects"), workspace: origin)
        let results = await [first, second, collection]
        XCTAssertEqual(results, [true, true, true])
        XCTAssertEqual(store.tasks.first?.title, "A title from one window"); XCTAssertEqual(store.tasks.first?.priority, "high")
        XCTAssertEqual(store.tasks.first?.raw["foreign"] as? Int, 17); XCTAssertEqual(store.taskLists.first?.id, "projects")
        let actual = try object(), records = actual["tasks"] as! [[String: Any]]
        XCTAssertEqual(records[0]["title"] as? String, "A title from one window")
        let other = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: other) }
        await store.open(other); await store.open(root)
        let rejected = await store.changeTasks(.createList(id: "stale", name: "Stale"), workspace: origin)
        XCTAssertFalse(rejected); XCTAssertEqual(store.taskLists.map(\.id), ["projects"])
    }
}
