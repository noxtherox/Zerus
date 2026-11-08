import Foundation
import CryptoKit

struct NativeReadingPosition: Codable, Equatable, Sendable {
    let bodyHash: String
    let source: Bool
    let selection: Int
    let selectionLength: Int
    let top: Int
    let lineOffset: Double
    static func hash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    var valid: Bool {
        bodyHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil &&
        [selection, selectionLength, top].allSatisfy { (0...50_000_000).contains($0) } && lineOffset.isFinite && abs(lineOffset) <= 4096
    }
}

/// Device-private UI state. A record never supplies file access or note bodies.
struct NativeNoteResumeStore {
    static let key = "zerus.native.note.resume"
    struct Entry: Codable, Sendable {
        let path: String
        let stableID: String?
        let legacyHash: String?
        let position: NativeReadingPosition?
        var valid: Bool {
            NativeRevisionIndex.validPath(path) && path.utf8.count <= 4096 &&
            (stableID.map { !$0.isEmpty && $0.utf8.count <= 4096 } ?? (legacyHash?.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil)) &&
            (position?.valid ?? true)
        }
        @MainActor func resolve(in vault: VaultStore) -> NoteDocument? {
            let matches = vault.notes.filter { !$0.trashed && (stableID == nil ? $0.path == path : $0.stableID == stableID) }
            guard matches.count == 1, let note = matches.first else { return nil }
            if stableID == nil {
                guard note.stableID == nil, legacyHash == NativeReadingPosition.hash(note.content) else { return nil }
            }
            return note
        }
    }
    struct Record: Codable, Sendable {
        let owner: UUID
        let entries: [Entry]
        let current: Int
        let originTab: Int
        var valid: Bool { (0...4).contains(originTab) && !entries.isEmpty && entries.count <= 100 && entries.indices.contains(current) && entries.allSatisfy(\.valid) }
    }
    private struct Container: Codable { var version = 1; var vaults: [String: Record] = [:] }
    private static func unreadable() -> VaultFailure { .init(message: "The saved note view uses an unreadable or newer format. It is preserved; you can still choose your notes from Library.") }
    private static func container() throws -> Container {
        guard let stored = UserDefaults.standard.object(forKey: key) else { return Container() }
        guard let bytes = stored as? Data else { throw unreadable() }
        guard bytes.count <= 2_000_000,
              let raw = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(raw.keys).isSubset(of: ["version", "vaults"]),
              let rows = raw["vaults"] as? [String: [String: Any]], rows.count <= 1000 else { throw unreadable() }
        for (id, row) in rows {
            guard UUID(uuidString: id) != nil, Set(row.keys).isSubset(of: ["owner", "entries", "current", "originTab"]), let entries = row["entries"] as? [[String: Any]] else { throw unreadable() }
            for entry in entries {
                guard Set(entry.keys).isSubset(of: ["path", "stableID", "legacyHash", "position"]) else { throw unreadable() }
                if let position = entry["position"] {
                    guard let position = position as? [String: Any], Set(position.keys).isSubset(of: ["bodyHash", "source", "selection", "selectionLength", "top", "lineOffset"]) else { throw unreadable() }
                }
            }
        }
        guard let value = try? JSONDecoder().decode(Container.self, from: bytes), value.version == 1, value.vaults.values.allSatisfy(\.valid) else { throw unreadable() }
        return value
    }
    private static func save(_ value: Container) throws {
        let bytes = try JSONEncoder().encode(value)
        guard bytes.count <= 2_000_000 else { throw unreadable() }
        UserDefaults.standard.set(bytes, forKey: key)
    }
    static func load(_ vault: UUID) throws -> Record? { try container().vaults[vault.uuidString] }
    @discardableResult static func write(_ record: Record, vault: UUID, claim: Bool = false) throws -> Bool {
        guard record.valid else { throw unreadable() }
        var value = try container()
        guard claim || value.vaults[vault.uuidString]?.owner == record.owner else { return false }
        value.vaults[vault.uuidString] = record; try save(value); return true
    }
    static func close(_ vault: UUID, owner: UUID) throws {
        var value = try container()
        guard value.vaults[vault.uuidString]?.owner == owner else { return }
        value.vaults.removeValue(forKey: vault.uuidString); try save(value)
    }
}
