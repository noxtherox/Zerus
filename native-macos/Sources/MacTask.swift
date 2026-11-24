import Foundation
import CoreFoundation

struct NativeTask: Identifiable {
    var raw: [String: Any]
    let baseline: [String: Any]?
    var workspaceID: UUID? = nil
    var id: String { raw["id"] as? String ?? "" }
    var title: String { get { raw["title"] as? String ?? "" } set { raw["title"] = newValue; touch() } }
    var completed: Bool { get { raw["completed"] as? Bool ?? false } set { raw["completed"] = newValue; raw["completedAt"] = newValue ? ISO8601DateFormatter().string(from: Date()) : NSNull(); touch() } }
    var priority: String { get { raw["priority"] as? String ?? "none" } set { raw["priority"] = newValue; touch() } }
    var category: String { get { (raw["category"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) } set { raw["category"] = newValue.isEmpty ? NSNull() : newValue as Any; touch() } }
    var listID: String { get { raw["listId"] as? String ?? "" } set { raw["listId"] = newValue.isEmpty ? NSNull() : newValue as Any; touch() } }
    var linkedNoteIDs: [String] { get { raw["linkedNoteIds"] as? [String] ?? [] } set { raw["linkedNoteIds"] = newValue; touch() } }
    var dueDate: String { get { raw["dueDate"] as? String ?? "" } set { raw["dueDate"] = newValue.isEmpty ? NSNull() : newValue as Any; touch() } }
    var date: String { get { (raw["date"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Self.day(createdAt) } set { raw["date"] = newValue; touch() } }
    var createdAt: Date { (raw["createdAt"] as? String).flatMap(NativeRevisionIndex.date) ?? Date(timeIntervalSince1970: 0) }
    var completedAt: Date? { (raw["completedAt"] as? String).flatMap(NativeRevisionIndex.date) }
    init?(_ raw: [String: Any]) {
        guard Self.supports(raw) else { return nil }; self.raw = raw; baseline = raw
    }
    init?(restoring raw: [String: Any], baseline: [String: Any]?, workspace: UUID? = nil) {
        guard Self.supports(raw), baseline == nil || Self.supports(baseline!), baseline == nil || (baseline?["id"] as? String == raw["id"] as? String && NativeTaskData.equal(baseline?["createdAt"], raw["createdAt"])) else { return nil }
        self.raw = raw; self.baseline = baseline; workspaceID = workspace
    }
    static func supports(_ raw: [String: Any]) -> Bool {
        guard let id = raw["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, raw["title"] is String else { return false }
        for key in ["priority", "date", "dueDate", "listId", "category", "createdAt", "updatedAt", "completedAt"] where raw[key] != nil && !(raw[key] is NSNull) {
            guard raw[key] is String else { return false }
        }
        if let value = raw["completed"], !(value is NSNull) { guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false } }
        if let value = raw["linkedNoteIds"], !(value is [String]) { return false }
        return true
    }
    init(title: String) {
        baseline = nil
        raw = ["id": UUID().uuidString.lowercased(), "title": title, "completed": false, "priority": "none", "date": Self.day(Date()), "createdAt": ISO8601DateFormatter().string(from: Date()), "linkedNoteIds": [String]()]
    }
    mutating func touch() { raw["updatedAt"] = ISO8601DateFormatter().string(from: Date()) }
    static func parseDay(_ value: String, calendar: Calendar = .current) -> Date? {
        MacTaskDayFormatter.shared.withFormatter(timeZone: calendar.timeZone) { formatter in
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }; return date
        }
    }
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        MacTaskDayFormatter.shared.withFormatter(timeZone: calendar.timeZone) { $0.string(from: date) }
    }
}


/// Calendar-only task values use Gregorian/POSIX spelling in the caller's zone.
/// Keep one formatter, changing its zone under the same lock used for parsing.
private final class MacTaskDayFormatter: @unchecked Sendable {
    static let shared = MacTaskDayFormatter()
    private let lock = NSLock()
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()
    private init() {}
    func withFormatter<T>(timeZone: TimeZone, _ operation: (DateFormatter) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        if formatter.timeZone != timeZone { formatter.timeZone = timeZone }
        return operation(formatter)
    }
}
