import Foundation

/// The web journal is an independent format, not a native run with renamed keys.
/// Keep its exact bytes: event details, provider metadata and historical snapshots
/// must remain recoverable even when native displays a different projection.
struct MacWebAgentRunRecord: Identifiable, Sendable {
    let path: String
    let bytes: Data
    let run: MacWebAgentRun
    var id: String { run.chatID + "/" + run.id }
    var digest: String { NativeHistory.hash(bytes) }

    static func path(chatID: String, runID: String) throws -> String {
        guard MacWebAgentRun.identity(chatID), MacWebAgentRun.identity(runID) else { throw MacWebAgentRun.problem("Invalid chat/run identity.") }
        return ".zerus/ai/runs/" + chatID + "/" + runID + ".json"
    }
    static func read(_ bytes: Data, path: String) throws -> Self {
        guard bytes.count <= 64 * 1024 * 1024,
              let object = try NativeJSON.object(with: bytes) as? [String: Any] else { throw MacWebAgentRun.problem("The journal is too large or is not a JSON object.") }
        let run = try MacWebAgentRun(object)
        guard path == (try Self.path(chatID: run.chatID, runID: run.id)) else { throw MacWebAgentRun.problem("The journal identity does not match its folder and filename.") }
        return .init(path: path, bytes: bytes, run: run)
    }
}

struct MacWebAgentRunCatalog: Sendable {
    let records: [MacWebAgentRunSummary]
    let issues: [String]
}

/// Sidebar discovery must not retain every journal's embedded image payloads.
/// The selected entry is reread in full before preparing migration.
struct MacWebAgentRunSummary: Identifiable, Sendable {
    let path: String
    let runID: String
    let chatID: String
    let parentRunID: String?
    let objectivePreview: String
    let mode: NativeAgentMode
    let status: String
    let updatedAt: Date
    let proposalCount: Int
    let receiptCount: Int
    var id: String { chatID + "/" + runID }
    init(_ record: MacWebAgentRunRecord) {
        path = record.path; runID = record.run.id; chatID = record.run.chatID; parentRunID = record.run.parentRunID
        objectivePreview = String(record.run.objective.prefix(2000)); mode = record.run.mode; status = record.run.status; updatedAt = record.run.updatedAt
        proposalCount = record.run.proposals.count; receiptCount = record.run.receipts.count
    }
}

struct MacWebAgentRun: Sendable {
    struct Snapshot: Sendable {
        let id: String
        let title: String
        let path: String
        let content: String
        let revision: String
        let pinned: Bool?
        let archived: Bool?
        init(_ object: [String: Any]) throws {
            id = try MacWebAgentRun.identifier(object, "id")
            title = try MacWebAgentRun.string(object, "title")
            path = try MacWebAgentRun.string(object, "path")
            guard NativeAgentOrganization.notePath(path) else { throw MacWebAgentRun.problem("A note snapshot has an unsupported path.") }
            content = try MacWebAgentRun.string(object, "content")
            revision = try MacWebAgentRun.string(object, "revision")
            pinned = try MacWebAgentRun.boolean(object, "pinned")
            archived = try MacWebAgentRun.boolean(object, "archived")
        }
        var document: NoteDocument { .init(path: path, content: content, modified: .distantPast) }
    }
    struct Call: Sendable {
        let name: String
        let arguments: Data
        init(_ object: [String: Any]) throws {
            name = try MacWebAgentRun.string(object, "name")
            guard !name.isEmpty, name.utf8.count <= 200, let arguments = object["arguments"] as? [String: Any] else { throw MacWebAgentRun.problem("A proposal has an unsupported tool call.") }
            self.arguments = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes])
        }
    }
    struct Proposal: Sendable {
        let id: String
        let call: Call
        let before: [Snapshot]
        let after: String
        let afterPath: String?
        let relatedAfter: [Snapshot]
        let label: String
        let targetID: String?
        let status: String
        init(_ object: [String: Any]) throws {
            id = try MacWebAgentRun.identifier(object, "id")
            call = try Call(MacWebAgentRun.object(object, "call"))
            before = try MacWebAgentRun.objects(object, "before").map(Snapshot.init)
            after = try MacWebAgentRun.string(object, "after")
            afterPath = try MacWebAgentRun.optionalString(object, "afterPath")
            if let afterPath, !NativeAgentOrganization.notePath(afterPath) { throw MacWebAgentRun.problem("A proposal has an unsupported destination.") }
            relatedAfter = try MacWebAgentRun.optionalObjects(object, "relatedAfter").map(Snapshot.init)
            label = try MacWebAgentRun.string(object, "label")
            targetID = try MacWebAgentRun.optionalIdentifier(object, "targetId")
            status = try MacWebAgentRun.string(object, "status")
            guard ["pending", "approved", "applying", "applied", "rejected", "conflict"].contains(status),
                  Set(before.map(\.id)).count == before.count,
                  Set(relatedAfter.map(\.id)).count == relatedAfter.count,
                  (call.name == "note_create" ? before.isEmpty && targetID != nil : !before.isEmpty && before.dropFirst().allSatisfy({ note in relatedAfter.contains { $0.id == note.id } })) else {
                throw MacWebAgentRun.problem("A proposal has inconsistent note snapshots or status.")
            }
        }
    }
    struct Receipt: Sendable {
        let id: String
        let operationKey: String
        let proposalID: String
        let before: [Snapshot]
        let after: [Snapshot]
        let date: Date
        let undoneAt: Date?
        init(_ object: [String: Any]) throws {
            id = try MacWebAgentRun.identifier(object, "id")
            operationKey = try MacWebAgentRun.string(object, "operationKey")
            proposalID = try MacWebAgentRun.identifier(object, "proposalId")
            before = try MacWebAgentRun.objects(object, "before").map(Snapshot.init)
            after = try MacWebAgentRun.objects(object, "after").map(Snapshot.init)
            date = try MacWebAgentRun.date(object, "at")
            undoneAt = try object["undoneAt"].map { _ in try MacWebAgentRun.date(object, "undoneAt") }
            guard !after.isEmpty, Set(before.map(\.id)).count == before.count, Set(after.map(\.id)).count == after.count else { throw MacWebAgentRun.problem("A receipt has inconsistent note snapshots.") }
        }
    }
    struct Event: Sendable {
        let id: String
        let date: Date
        let kind: String
        let text: String
        let original: Data
        init(_ object: [String: Any]) throws {
            id = try MacWebAgentRun.identifier(object, "id")
            date = try MacWebAgentRun.date(object, "at")
            kind = try MacWebAgentRun.string(object, "kind")
            text = try MacWebAgentRun.string(object, "text")
            guard ["started", "activity", "tool", "committed", "approval", "question", "steering", "compacted", "finished", "error"].contains(kind) else { throw MacWebAgentRun.problem("An event has an unsupported kind.") }
            original = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        }
    }
    struct Usage: Sendable {
        let inputTokens: Double
        let outputTokens: Double
        let steps: Double
        let elapsedMilliseconds: Double
        let budgetTokens: Double?
        init(_ object: [String: Any]) throws {
            inputTokens = try MacWebAgentRun.number(object, "inputTokens")
            outputTokens = try MacWebAgentRun.number(object, "outputTokens")
            steps = try MacWebAgentRun.number(object, "steps")
            elapsedMilliseconds = try MacWebAgentRun.number(object, "elapsedMs")
            budgetTokens = try object["budgetTokens"].map { _ in try MacWebAgentRun.number(object, "budgetTokens") }
        }
    }
    let id: String
    let chatID: String
    let ownerID: String
    let objective: String
    let mode: NativeAgentMode
    let readIDs: [String]
    let writeIDs: [String]
    let createTypes: [String]
    let scopeKey: String?
    let parentRunID: String?
    let status: String
    let plan: [NativeAgentPlanStep]
    let proposals: [Proposal]
    let receipts: [Receipt]
    let events: [Event]
    let messages: [Data]
    let question: String?
    let questionOptions: [String]
    let usage: Usage
    let updatedAt: Date

    init(_ object: [String: Any]) throws {
        guard NativeHistory.integer(object["version"]) == 1 else { throw Self.problem("The journal version is unsupported.") }
        id = try Self.identifier(object, "id"); chatID = try Self.identifier(object, "chatId"); ownerID = try Self.identifier(object, "ownerId")
        objective = try Self.string(object, "objective")
        switch try Self.string(object, "mode") {
        case "ask": mode = .ask
        case "review": mode = .review
        case "edit": mode = .edit
        default: throw Self.problem("The saved mode is unsupported.")
        }
        readIDs = try Self.identifiers(object, "readIds"); writeIDs = try Self.identifiers(object, "writeIds")
        guard Set(writeIDs).isSubset(of: Set(readIDs)) else { throw Self.problem("Writable note IDs are outside the saved read context.") }
        createTypes = try Self.strings(object, "createTypes")
        scopeKey = try Self.optionalString(object, "scopeKey"); parentRunID = try Self.optionalIdentifier(object, "parentRunId")
        status = try Self.string(object, "status")
        guard ["running", "waiting", "interrupted", "complete", "partial"].contains(status) else { throw Self.problem("The saved status is unsupported.") }
        let planNamespace = chatID + "/" + id
        plan = try Self.objects(object, "plan").enumerated().map { index, row in
            let text = try Self.string(row, "text"), value = try Self.string(row, "status")
            guard let status = NativeAgentPlanStatus(rawValue: value) else { throw Self.problem("A plan step has an unsupported status.") }
            return .init(id: Self.nativeID(planNamespace + "/plan/" + String(index)).uuidString, text: text, status: status)
        }
        proposals = try Self.objects(object, "proposals").map(Proposal.init)
        receipts = try Self.objects(object, "receipts").map(Receipt.init)
        events = try Self.objects(object, "events").map(Event.init)
        guard Set(proposals.map(\.id)).count == proposals.count, Set(receipts.map(\.id)).count == receipts.count, Set(events.map(\.id)).count == events.count else { throw Self.problem("The journal contains duplicate proposal, receipt or event identities.") }
        let rawMessages = try Self.objects(object, "messages")
        messages = try rawMessages.map { message in
            let role = try Self.string(message, "role")
            guard ["system", "user", "assistant", "tool"].contains(role), message["content"] is String || message["content"] is [[String: Any]] else { throw Self.problem("A saved model message is unsupported.") }
            return try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        if object["question"] != nil {
            let row = try Self.object(object, "question")
            question = try Self.string(row, "question")
            questionOptions = row["options"] == nil ? [] : try Self.strings(row, "options")
        } else { question = nil; questionOptions = [] }
        usage = try Usage(Self.object(object, "usage")); updatedAt = try Self.date(object, "updatedAt")
    }
    static func identity(_ value: String) -> Bool { value.range(of: #"^[A-Za-z0-9_-]{1,100}$"#, options: .regularExpression) != nil }
    /// Namespaces non-UUID web identities without changing their source values.
    static func nativeID(_ value: String) -> UUID {
        let hex = Array(NativeHistory.hash("zerus.web-agent-migration.v1/" + value).prefix(32))
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
        return UUID(uuidString: groups.joined(separator: "-"))!
    }
    static func problem(_ detail: String) -> VaultFailure { .init(message: "This web agent run cannot be migrated yet. " + detail + " Its original journal is preserved.") }
    static func object(_ row: [String: Any], _ key: String) throws -> [String: Any] {
        guard let value = row[key] as? [String: Any] else { throw problem("Missing or unsupported " + key + ".") }; return value
    }
    static func objects(_ row: [String: Any], _ key: String) throws -> [[String: Any]] {
        guard let value = row[key] as? [[String: Any]] else { throw problem("Missing or unsupported " + key + ".") }; return value
    }
    static func optionalObjects(_ row: [String: Any], _ key: String) throws -> [[String: Any]] { row[key] == nil ? [] : try objects(row, key) }
    static func string(_ row: [String: Any], _ key: String) throws -> String {
        guard let value = row[key] as? String else { throw problem("Missing or unsupported " + key + ".") }; return value
    }
    static func optionalString(_ row: [String: Any], _ key: String) throws -> String? { row[key] == nil ? nil : try string(row, key) }
    static func identifier(_ row: [String: Any], _ key: String) throws -> String {
        let value = try string(row, key); guard identity(value) else { throw problem("Invalid " + key + ".") }; return value
    }
    static func optionalIdentifier(_ row: [String: Any], _ key: String) throws -> String? { row[key] == nil ? nil : try identifier(row, key) }
    static func strings(_ row: [String: Any], _ key: String) throws -> [String] {
        guard let value = row[key] as? [String] else { throw problem("Missing or unsupported " + key + ".") }; return value
    }
    static func identifiers(_ row: [String: Any], _ key: String) throws -> [String] {
        let values = try strings(row, key); guard values.allSatisfy(identity) else { throw problem("Invalid note identities in " + key + ".") }; return values
    }
    static func boolean(_ row: [String: Any], _ key: String) throws -> Bool? {
        guard let raw = row[key] else { return nil }; guard let value = NativeRevisions.boolean(raw) else { throw problem("Unsupported " + key + ".") }; return value
    }
    static func number(_ row: [String: Any], _ key: String) throws -> Double {
        guard let value = row[key] as? NSNumber, NativeRevisions.boolean(value) == nil, value.doubleValue.isFinite, value.doubleValue >= 0 else { throw problem("Unsupported usage value " + key + ".") }; return value.doubleValue
    }
    static func date(_ row: [String: Any], _ key: String) throws -> Date {
        guard let value = NativeRevisionIndex.date(try string(row, key)) else { throw problem("Unsupported timestamp " + key + ".") }; return value
    }
}

extension VaultFiles {
    func macWebAgentRuns(chatID: String) throws -> MacWebAgentRunCatalog {
        guard MacWebAgentRun.identity(chatID) else { throw MacWebAgentRun.problem("Invalid conversation identity.") }
        try recoverTransactions()
        let directory = ".zerus/ai/runs/" + chatID, location = try url(for: directory)
        guard FileManager.default.fileExists(atPath: location.path) else { return .init(records: [], issues: []) }
        let entries = try FileManager.default.contentsOfDirectory(at: location, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]).filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard entries.count <= 1000 else { throw MacWebAgentRun.problem("This conversation has more than 1,000 saved web journals.") }
        var records: [MacWebAgentRunSummary] = [], issues: [String] = []
        for entry in entries {
            try Task.checkCancellation()
            let path = directory + "/" + entry.lastPathComponent
            do {
                let summary = try autoreleasepool { try MacWebAgentRunSummary(macWebAgentRun(path: path)) }
                records.append(summary)
            } catch is CancellationError { throw CancellationError() }
            catch { issues.append(path + ": " + error.localizedDescription) }
        }
        return .init(records: records.sorted { $0.updatedAt > $1.updatedAt }, issues: issues)
    }
    func macWebAgentRun(path: String) throws -> MacWebAgentRunRecord {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 5, parts.prefix(3) == [".zerus", "ai", "runs"], parts[4].hasSuffix(".json"),
              path == (try MacWebAgentRunRecord.path(chatID: String(parts[3]), runID: String(parts[4].dropLast(5)))) else { throw MacWebAgentRun.problem("Invalid source journal path.") }
        let entry = try url(for: path), values = try entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 64 * 1024 * 1024 else { throw MacWebAgentRun.problem("The entry is not an ordinary bounded journal file.") }
        return try MacWebAgentRunRecord.read(read(path), path: path)
    }
}
