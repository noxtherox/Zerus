import Foundation
import SwiftUI

struct NativeTaskDraft: Identifiable {
    let id: UUID
    let date: Date
    let task: NativeTask
    let seed: [String: Any]
    let pendingCopyID: String?
    let bytes: Data
    var title: String { task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled task" : task.title }
}

@MainActor
final class NativeTaskDraftStore: ObservableObject {
    @Published private(set) var records: [NativeTaskDraft] = []
    @Published private(set) var unreadable: [URL] = []
    @Published private(set) var issue: String?
    let directory: URL
    private struct Changed: Error {}
    init(vaultRoot: URL, vaultID: UUID?) throws {
        let fm = FileManager.default, base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeTaskDrafts", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let root = Self.identity(vaultRoot), identifier = vaultID?.uuidString.lowercased()
        var matches: [(URL, [String: Any])] = [], unknown = false
        for folder in try fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey]) where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let file = folder.appendingPathComponent("vault.json")
            guard let bytes = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], let roots = object["roots"] as? [String], let ids = object["vaultIDs"] as? [String] else { if (try? fm.contentsOfDirectory(atPath: folder.path).isEmpty) != true { unknown = true }; continue }
            let owners = Set(ids.map { $0.lowercased() })
            let matchesVault = identifier.map { owners.contains($0) || owners.isEmpty && roots.contains(root) } ?? roots.contains(root)
            if matchesVault {
                guard NativeHistory.integer(object["version"]) == 1 else { throw VaultFailure(message: "This vault’s task drafts use a newer format and were preserved. Share your task before closing until draft access is restored.") }
                guard owners.count <= 1 else { throw VaultFailure(message: "These task drafts identify several saved vaults. Their files are preserved without assigning them to a vault. Save or share your current task before closing.") }
                matches.append((folder, object))
            }
        }
        guard matches.count <= 1 else { throw VaultFailure(message: "More than one task-draft folder identifies this vault. They were preserved without merging.") }
        guard !matches.isEmpty || !unknown else { throw VaultFailure(message: "Some task-draft folders could not be identified. Their files are preserved; share your task before closing until draft access is restored.") }
        directory = matches.first?.0 ?? base.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        var descriptor = matches.first?.1 ?? ["version": 1, "roots": [String](), "vaultIDs": [String]()]
        descriptor["roots"] = Array(Set((descriptor["roots"] as! [String]) + [root])).sorted()
        descriptor["vaultIDs"] = Array(Set((descriptor["vaultIDs"] as! [String]) + (identifier.map { [$0] } ?? []))).sorted()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: descriptor, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("vault.json"), options: .atomic)
        reload()
    }
    static func identity(_ root: URL) -> String {
        let path = root.standardizedFileURL.resolvingSymlinksInPath().path
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL.resolvingSymlinksInPath().path
        if path == documents { return "documents:" }
        if path.hasPrefix(documents + "/") { return "documents:" + String(path.dropFirst(documents.count + 1)) }
        return "files:" + path
    }
    func reload() {
        do {
            var records: [NativeTaskDraft] = [], unreadable: [URL] = []
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.lastPathComponent != "vault.json" && file.pathExtension == "json" {
                do { records.append(try decode(Data(contentsOf: file), at: file)) } catch { unreadable.append(file) }
            }
            self.records = records.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }; self.unreadable = unreadable; issue = nil
        } catch { issue = "Task drafts could not be read: " + error.localizedDescription }
    }
    func latest(for taskID: String) -> NativeTaskDraft? { records.first { $0.task.id == taskID } }
    private func decode(_ bytes: Data, at file: URL) throws -> NativeTaskDraft {
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], NativeHistory.integer(object["version"]) == 1,
              let id = (object["id"] as? String).flatMap(UUID.init(uuidString:)), UUID(uuidString: file.deletingPathExtension().lastPathComponent) == id,
              let raw = object["task"] as? [String: Any], let seed = object["seed"] as? [String: Any],
              let modified = object["modified"] as? Double, modified.isFinite,
              object["baseline"] is NSNull || object["baseline"] is [String: Any],
              let task = NativeTask(restoring: raw, baseline: object["baseline"] as? [String: Any]),
              object["pendingCopyID"] == nil || (object["pendingCopyID"] as? String).flatMap(UUID.init(uuidString:)) != nil else { throw VaultFailure(message: "Unsupported task draft.") }
        return .init(id: id, date: Date(timeIntervalSince1970: modified), task: task, seed: seed, pendingCopyID: object["pendingCopyID"] as? String, bytes: bytes)
    }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString.lowercased() + ".json") }
    private func replace(_ id: UUID, expected: Data?, next: Data?) throws {
        let url = file(id)
        var coordination: NSError?, result: Result<Void, Error> = .failure(Changed())
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordination) { location in
            result = Result {
                let current = FileManager.default.fileExists(atPath: location.path) ? try Data(contentsOf: location) : nil
                guard current == expected else { throw Changed() }
                if let next { try next.write(to: location, options: .atomic) }
                else if current != nil { try FileManager.default.removeItem(at: location) }
            }
        }
        if let coordination { throw coordination }; try result.get()
    }
    func keep(_ task: NativeTask, seed: [String: Any], previous: NativeTaskDraft?, pendingCopyID: String?) throws -> (NativeTaskDraft, forked: Bool) {
        func encoded(_ id: UUID) throws -> Data {
            let raw = task.draftFields
            var object: [String: Any] = ["version": 1, "id": id.uuidString, "modified": Date().timeIntervalSince1970, "task": raw, "baseline": task.draftBaseline as Any? ?? NSNull(), "seed": seed]
            object["pendingCopyID"] = pendingCopyID
            return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        }
        var id = previous?.id ?? UUID(), data = try encoded(id), forked = false
        do { try replace(id, expected: previous?.bytes, next: data) }
        catch is Changed { id = UUID(); data = try encoded(id); try replace(id, expected: nil, next: data); forked = true }
        let record = try decode(data, at: file(id)); reload(); return (record, forked)
    }
    @discardableResult
    func remove(_ record: NativeTaskDraft) throws -> Bool {
        do { try replace(record.id, expected: record.bytes, next: nil); reload(); return true }
        catch is Changed { reload(); return false }
    }
    func url(_ record: NativeTaskDraft) -> URL { file(record.id) }
}

extension NativeTask {
    static let editableFields: Set<String> = ["title", "completed", "priority", "date", "dueDate", "listId", "category", "linkedNoteIds"]
    private var recoveryKeys: Set<String> {
        let changed = baseline.map { base in Set(raw.keys).union(base.keys).filter { !NativeTaskData.equal(raw[$0], base[$0]) } } ?? Set(raw.keys)
        return Self.editableFields.union(["id", "createdAt", "updatedAt", "completedAt"]).union(changed)
    }
    var draftFields: [String: Any] { let keys = recoveryKeys; return raw.filter { keys.contains($0.key) } }
    var draftBaseline: [String: Any]? { let keys = recoveryKeys; return baseline.map { base in base.filter { keys.contains($0.key) } } }
    func hasEdits(seed: [String: Any]) -> Bool {
        if baseline == nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let original = baseline ?? seed
        return Set(raw.keys).union(original.keys).subtracting(["id", "createdAt", "updatedAt", "completedAt"]).contains { !NativeTaskData.equal(raw[$0], original[$0]) }
    }
    func alreadySaved(as current: NativeTask) -> Bool {
        guard id == current.id, NativeTaskData.equal(raw["createdAt"], current.raw["createdAt"]) else { return false }
        let keys = baseline.map { base in Set(raw.keys).union(base.keys).subtracting(["id", "createdAt", "updatedAt", "completedAt"]).filter { !NativeTaskData.equal(raw[$0], base[$0]) } } ?? Set(raw.keys).subtracting(["id", "createdAt", "updatedAt", "completedAt"])
        return keys.allSatisfy { NativeTaskData.equal(raw[$0], current.raw[$0]) }
    }
    func rebased(on current: NativeTask?) -> NativeTask {
        guard let baseline, let current, id == current.id, NativeTaskData.equal(baseline["createdAt"], current.raw["createdAt"]) else { return self }
        var raw = self.raw, base = baseline
        for key in Set(raw.keys).union(base.keys).union(current.raw.keys) where NativeTaskData.equal(raw[key], base[key]) {
            raw[key] = current.raw[key]; base[key] = current.raw[key]
        }
        return NativeTask(restoring: raw, baseline: base, workspace: workspaceID) ?? self
    }
    var shareDraft: String {
        let data = try? JSONSerialization.data(withJSONObject: ["task": raw, "original": baseline as Any? ?? NSNull()], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? title
    }
}

@MainActor
final class NativeTaskDraftSession: ObservableObject {
    @Published var task: NativeTask {
        didSet {
            guard !paused else { return }
            if Set(task.raw.keys).union(oldValue.raw.keys).subtracting(["updatedAt", "completedAt"]).contains(where: { !NativeTaskData.equal(task.raw[$0], oldValue.raw[$0]) }) { pendingCopyID = nil }
            keep()
        }
    }
    @Published private(set) var issue: String?
    @Published private(set) var recovered = false
    private(set) var record: NativeTaskDraft?
    let store: NativeTaskDraftStore?
    private let seed: [String: Any]
    private var pendingCopyID: String?
    private var paused = false
    var dirty: Bool { task.hasEdits(seed: seed) }
    init(task: NativeTask, store: NativeTaskDraftStore?, canonical: NativeTask? = nil, recovered explicit: NativeTaskDraft? = nil, accessIssue: String? = nil) {
        self.store = store
        let record = explicit ?? store?.latest(for: task.id)
        self.seed = record?.seed ?? task.draftFields
        self.record = record; pendingCopyID = record?.pendingCopyID; issue = accessIssue
        if let record {
            var restored = record.task.rebased(on: canonical); restored.workspaceID = task.workspaceID
            self.task = restored; recovered = true
            if let canonical, record.task.alreadySaved(as: canonical) {
                self.task = canonical; self.record = nil; pendingCopyID = nil; recovered = false
                do { if try store?.remove(record) == false { issue = "A newer draft is still available in Drafts." } } catch { issue = error.localizedDescription }
            }
        } else { self.task = task }
    }
    func keep() {
        guard !paused else { return }
        guard let store else { issue = issue ?? "Task drafts are unavailable on this iPhone. Save or share this task before closing."; return }
        do {
            if dirty || pendingCopyID != nil {
                let result = try store.keep(task, seed: seed, previous: record, pendingCopyID: pendingCopyID); record = result.0
                issue = result.forked ? "Another window changed this draft. Both versions have been kept in Drafts." : nil
            } else if let record {
                if try store.remove(record) { self.record = nil; issue = nil }
                else { self.record = nil; issue = "A newer draft is still available in Drafts." }
            }
        } catch { issue = "Could not keep this task draft: " + error.localizedDescription }
    }
    func committed(_ saved: NativeTask) {
        paused = true; defer { paused = false }
        issue = nil
        if let record { do { if try store?.remove(record) == false { issue = "A newer draft is still available in Drafts." } } catch { issue = error.localizedDescription } }
        record = nil; pendingCopyID = nil; recovered = false; task = saved
    }
    func discard() throws {
        if let record, try store?.remove(record) == false { throw VaultFailure(message: "This draft changed in another window. Reopen Drafts before discarding it.") }
        record = nil; paused = true
    }
    func copyIntent() throws -> NativeTask {
        if pendingCopyID == nil { pendingCopyID = UUID().uuidString.lowercased() }
        keep()
        guard let record, record.pendingCopyID == pendingCopyID else { throw VaultFailure(message: "The copy could not be staged on this iPhone. Share this draft or restore draft access before saving a copy.") }
        var copy = NativeTask(title: task.title)
        for key in task.raw.keys where !["id", "createdAt", "updatedAt", "completedAt"].contains(key) { copy.raw[key] = task.raw[key] }
        if task.completed { copy.completed = true }
        copy.raw["id"] = pendingCopyID!; copy.workspaceID = task.workspaceID
        return copy
    }
    func completedCopy(in current: [NativeTask]) -> NativeTask? {
        guard let pendingCopyID else { return nil }
        return current.first { candidate in candidate.id == pendingCopyID && NativeTask.editableFields.allSatisfy { key in NativeTaskData.equal(task.raw[key], candidate.raw[key]) } }
    }
}
