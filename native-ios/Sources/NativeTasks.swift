import Foundation

struct NativeTaskList: Identifiable {
    let raw: [String: Any]
    var id: String { raw["id"] as! String }
    var name: String { (raw["name"] as! String).trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct NativeTaskData: @unchecked Sendable {
    // Immutable JSON values loaded by the file actor; foreign fields are never
    // normalized away when a supported task or collection changes.
    let object: [String: Any]
    init(_ bytes: Data?) throws {
        guard let bytes else { object = ["tasks": [Any]()]; return }
        let value = try JSONSerialization.jsonObject(with: bytes)
        if let array = value as? [Any] {
            var seen = Set<String>()
            let categories = array.compactMap { ($0 as? [String: Any]).flatMap(NativeTask.init)?.category }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            object = ["tasks": array, "lists": [[String: Any]](), "categoryOptions": categories]
        }
        else if let dictionary = value as? [String: Any], dictionary["tasks"] is [Any] { object = dictionary }
        else { throw VaultFailure(message: "The tasks file uses an unsupported format. Its contents were preserved.") }
    }
    init(object: [String: Any]) { self.object = object }
    var records: [Any] { object["tasks"] as? [Any] ?? [] }
    var tasks: [NativeTask] {
        let decoded = records.compactMap { ($0 as? [String: Any]).flatMap(NativeTask.init) }
        let groups = Dictionary(grouping: decoded, by: \.id)
        return decoded.filter { groups[$0.id]?.count == 1 }
    }
    var lists: [NativeTaskList] {
        let decoded = (object["lists"] as? [Any] ?? []).compactMap { raw -> NativeTaskList? in
            guard let value = raw as? [String: Any], let id = value["id"] as? String, !id.isEmpty, let name = value["name"] as? String, !name.isEmpty else { return nil }
            return .init(raw: value)
        }
        let groups = Dictionary(grouping: decoded, by: \.id)
        return decoded.filter { groups[$0.id]?.count == 1 }
    }
    var generalName: String { (object["generalListName"] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } ?? "General" }
    var categories: [String] {
        let values = object["categoryOptions"] as? [String] ?? []
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
    var warning: String? {
        let unknown = records.count - tasks.count
        return unknown == 0 ? nil : "\(unknown) tasks could not be opened. Their data is preserved; resolve them in the app that created them."
    }
    static func equal(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil || b == nil { return a == nil && b == nil }
        return (a as? NSObject)?.isEqual(b) == true
    }
}

enum NativeTaskChange {
    case save(NativeTask, delete: Bool)
    case createList(id: String, name: String)
    case renameList(NativeTaskList?, originalName: String, name: String)
    case deleteList(NativeTaskList, assigned: Set<String>)
    case addCategory(String)
    case deleteCategory(String, assigned: Set<String>)
}

extension VaultFiles {
    func taskData() throws -> NativeTaskData { try .init(historyData(".zerus/tasks.json")) }

    func changeTasks(_ change: NativeTaskChange) throws -> NativeTaskData {
        let path = ".zerus/tasks.json", bytes = try historyData(path), data = try NativeTaskData(bytes)
        var object = data.object, records = data.records
        let now = ISO8601DateFormatter().string(from: Date())
        func clean(_ value: String) throws -> String {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.contains("\n"), !value.contains("\r") else { throw VaultFailure(message: "Enter a name on one line.") }
            return value
        }
        func listRecords() throws -> [[String: Any]] {
            guard object["lists"] == nil || object["lists"] is [[String: Any]] else { throw VaultFailure(message: "The task lists use an unsupported format. Their data is preserved.") }
            let lists = object["lists"] as? [[String: Any]] ?? []
            guard lists.count == data.lists.count else { throw VaultFailure(message: "Resolve unsupported or duplicate task lists before changing the list collection.") }
            return lists
        }
        func affected(_ key: String, matching: (String) -> Bool) throws -> Set<String> {
            let values = records.compactMap { $0 as? [String: Any] }.filter { ($0[key] as? String).map(matching) == true }
            let ids = Set(values.compactMap { $0["id"] as? String })
            guard values.count == ids.count, values.allSatisfy({ raw in data.tasks.contains { $0.id == raw["id"] as? String } }) else { throw VaultFailure(message: "Some affected tasks are unsupported or ambiguous. They were left unchanged.") }
            return ids
        }
        switch change {
        case .save(let task, let delete):
            guard let id = task.raw["id"] as? String, !id.isEmpty else { throw VaultFailure(message: "This task has no usable identity.") }
            let matches = records.indices.filter { (records[$0] as? [String: Any])?["id"] as? String == id }
            guard matches.count <= 1 else { throw VaultFailure(message: "This task identity is duplicated. Its records are preserved.") }
            if let baseline = task.baseline {
                guard baseline["id"] as? String == id, let index = matches.first, var current = records[index] as? [String: Any] else { throw VaultFailure(message: "This task was removed or replaced in another editor. Keep your draft before reloading.") }
                guard NativeTask.supports(current), NativeTask.supports(task.raw), NativeTaskData.equal(current["createdAt"], baseline["createdAt"]) else { throw VaultFailure(message: "This task was replaced or has unsupported fields. Its shared data is preserved and your draft remains available.") }
                if delete {
                    guard NativeTaskData.equal(current, baseline) else { throw VaultFailure(message: "The task changed after deletion was reviewed. Reopen it before deleting.") }
                    records.remove(at: index)
                } else {
                    let changed = Set(task.raw.keys).union(baseline.keys).filter { $0 != "updatedAt" && $0 != "completedAt" && !NativeTaskData.equal(task.raw[$0], baseline[$0]) }
                    for key in changed {
                        let field = ["title": "title", "completed": "completion", "priority": "priority", "date": "scheduled date", "dueDate": "due date", "listId": "list", "category": "category", "linkedNoteIds": "supporting notes"][key] ?? "details"
                        guard key != "createdAt", NativeTaskData.equal(current[key], baseline[key]) || NativeTaskData.equal(current[key], task.raw[key]) else { throw VaultFailure(message: "The task’s \(field) changed in another editor. Your draft remains open; reload it before replacing that value.") }
                        if key == "listId", !task.listID.isEmpty, !data.lists.contains(where: { $0.id == task.listID }) { throw VaultFailure(message: "The selected task list is no longer available. Choose an existing list or the default list.") }
                        if key == "category", !task.category.isEmpty, !data.categories.contains(where: { $0.caseInsensitiveCompare(task.category) == .orderedSame }) { throw VaultFailure(message: "The selected task category is no longer available. Choose another category or None.") }
                        if key == "title" { guard !(task.raw[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VaultFailure(message: "Give the task a title.") } }
                        if key == "priority", !["none", "low", "medium", "high"].contains(task.raw[key] as? String ?? "") { throw VaultFailure(message: "Choose a supported task priority.") }
                        if ["date", "dueDate"].contains(key), let day = task.raw[key] as? String, !day.isEmpty, NativeTask.parseDay(day) == nil { throw VaultFailure(message: "Choose a valid calendar date.") }
                        current[key] = task.raw[key]
                    }
                    if changed.contains("completed") {
                        current["completedAt"] = task.completed ? (current["completedAt"] as? String ?? now) as Any : NSNull()
                    }
                    if !changed.isEmpty { current["updatedAt"] = now }
                    records[index] = current
                }
            } else if !delete {
                guard matches.isEmpty, !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VaultFailure(message: "Give the new task a unique identity and a title.") }
                guard NativeTask.supports(task.raw), ["none", "low", "medium", "high"].contains(task.priority), NativeTask.parseDay(task.date) != nil,
                      task.dueDate.isEmpty || NativeTask.parseDay(task.dueDate) != nil else { throw VaultFailure(message: "The new task contains unsupported fields, priority or dates. Correct its values before saving.") }
                guard task.listID.isEmpty || data.lists.contains(where: { $0.id == task.listID }) else { throw VaultFailure(message: "The selected task list is no longer available. Choose an existing list or the default list.") }
                guard task.category.isEmpty || data.categories.contains(where: { $0.caseInsensitiveCompare(task.category) == .orderedSame }) else { throw VaultFailure(message: "The selected task category is no longer available. Choose another category or None.") }
                var raw = task.raw; raw["updatedAt"] = now; records.append(raw)
            }
        case .createList(let id, let name):
            var lists = try listRecords(); let name = try clean(name)
            guard !id.isEmpty, !lists.contains(where: { $0["id"] as? String == id || ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame }), data.generalName.caseInsensitiveCompare(name) != .orderedSame else { throw VaultFailure(message: "A task list already has that name.") }
            lists.append(["id": id, "name": name]); object["lists"] = lists
        case .renameList(let original, let oldName, let next):
            let name = try clean(next); var lists = try listRecords()
            guard !lists.contains(where: { $0["id"] as? String != original?.id && ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame }), original == nil || data.generalName.caseInsensitiveCompare(name) != .orderedSame else { throw VaultFailure(message: "A task list already has that name.") }
            if let original {
                guard let index = lists.firstIndex(where: { $0["id"] as? String == original.id }), (lists[index]["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == oldName else { throw VaultFailure(message: "The list changed. Reload it before renaming.") }
                lists[index]["name"] = name; object["lists"] = lists
            } else {
                guard data.generalName == oldName, object["generalListName"] == nil || object["generalListName"] is String else { throw VaultFailure(message: "The default list name changed or uses an unsupported format.") }
                object["generalListName"] = name
            }
        case .deleteList(let list, let assigned):
            var lists = try listRecords()
            guard let index = lists.firstIndex(where: { $0["id"] as? String == list.id }), NativeTaskData.equal(lists[index], list.raw), try affected("listId", matching: { $0 == list.id }) == assigned else { throw VaultFailure(message: "The list or its tasks changed after review. Review deletion again.") }
            lists.remove(at: index); object["lists"] = lists
            records = records.map { raw in
                guard var task = raw as? [String: Any], task["listId"] as? String == list.id else { return raw }
                task["listId"] = NSNull(); task["updatedAt"] = now; return task
            }
        case .addCategory(let name):
            guard object["categoryOptions"] == nil || object["categoryOptions"] is [String] else { throw VaultFailure(message: "The task categories use an unsupported format and are preserved.") }
            let name = try clean(name); var categories = object["categoryOptions"] as? [String] ?? data.categories
            guard !categories.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { throw VaultFailure(message: "That category already exists.") }
            categories.append(name); object["categoryOptions"] = categories
        case .deleteCategory(let name, let assigned):
            guard object["categoryOptions"] == nil || object["categoryOptions"] is [String] else { throw VaultFailure(message: "The task categories use an unsupported format and are preserved.") }
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { throw VaultFailure(message: "Choose a category to remove.") }
            guard try affected("category", matching: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }) == assigned else { throw VaultFailure(message: "Tasks in this category changed. Review removal again.") }
            object["categoryOptions"] = (object["categoryOptions"] as? [String] ?? data.categories).filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != key }
            records = records.map { raw in
                guard var task = raw as? [String: Any], (task["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key else { return raw }
                task["category"] = NSNull(); task["updatedAt"] = now; return task
            }
        }
        object["tasks"] = records
        if !NativeTaskData.equal(object, data.object) {
            let after = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try write(path, data: after, expected: bytes)
        }
        return .init(object: object)
    }
}

enum NativeTaskSort: String, CaseIterable {
    case created = "Recently created", completed = "Recently completed", title = "Title A–Z", reverseTitle = "Title Z–A"
}
enum NativeTaskView: String, CaseIterable { case today = "Today", all = "All", completed = "Completed" }

struct NativeTaskQuery {
    var view = NativeTaskView.today
    var sort = NativeTaskSort.created
    var list: String? = nil
    var category: String? = nil
    var priority: String? = nil
    var search = ""
    var showOlderCompleted = false
    func results(_ tasks: [NativeTask], now: Date = Date(), calendar: Calendar = .current) -> [NativeTask] {
        let today = NativeTask.day(now, calendar: calendar), cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter {
            (list == nil || $0.listID == list) && (category == nil || $0.category.caseInsensitiveCompare(category!) == .orderedSame) && (priority == nil || $0.priority == priority) &&
            (search.isEmpty || $0.title.localizedStandardContains(search)) &&
            (view != .today || $0.date == today) && (view != .completed || $0.completed) &&
            (!$0.completed || showOlderCompleted || $0.completedAt.map { $0 >= cutoff } == true)
        }.enumerated().sorted { left, right in
            let a = left.element, b = right.element
            if a.completed != b.completed { return !a.completed }
            if sort == .title || sort == .reverseTitle {
                let order = a.title.localizedCaseInsensitiveCompare(b.title)
                if order != .orderedSame { return sort == .title ? order == .orderedAscending : order == .orderedDescending }
            } else {
                let left = sort == .completed ? a.completedAt ?? a.createdAt : a.createdAt, right = sort == .completed ? b.completedAt ?? b.createdAt : b.createdAt
                if left != right { return left > right }
            }
            return a.createdAt != b.createdAt ? a.createdAt > b.createdAt : left.offset < right.offset
        }.map(\.element)
    }
}
