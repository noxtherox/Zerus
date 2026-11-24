import Foundation

struct NativeInventoryEntry {
    let path: String
    let modified: Date
    let created: Date?
    /// Inode change time. The kernel updates it on every write, replace and
    /// rename; user space cannot set it back.
    let changed: Date?
    let size: Int?
}

/// Note text from the last coordinated read, keyed by vault root and exact path
/// bytes. An entry is reused only while modification time, change time and size
/// are all unchanged; any write, replacement or download changes the change
/// time. Writes never trust this cache: transactions re-read and compare the
/// bytes on disk before replacing a file. A full fresh read still happens when
/// a vault is first scanned in this process and at least every two minutes.
/// Shared by the iOS and Mac inventories.
final class NativeInventoryCache: @unchecked Sendable {
    struct Stamp: Equatable { let modified: Date; let changed: Date; let size: Int }
    private struct Vault { var notes: [Data: (stamp: Stamp, path: String, content: String)] = [:]; var lastFull = Date.distantPast }
    static let shared = NativeInventoryCache()
    static let fullReadInterval: TimeInterval = 120
    private let lock = NSLock()
    private var vaults: [String: Vault] = [:]

    /// Cached text for `entry`, or nil when it must be read again.
    func content(root: String, entry: NativeInventoryEntry, now: Date) -> String? {
        guard let stamp = Self.stamp(entry) else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let vault = vaults[root], now.timeIntervalSince(vault.lastFull) < Self.fullReadInterval,
              let cached = vault.notes[Data(entry.path.utf8)], cached.stamp == stamp, cached.path.utf8.elementsEqual(entry.path.utf8) else { return nil }
        return cached.content
    }
    func needsFullRead(root: String, now: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return vaults[root].map { now.timeIntervalSince($0.lastFull) >= Self.fullReadInterval } ?? true
    }
    /// Replace the vault's entries with this inventory. Notes absent from it are dropped.
    func store(root: String, entries: [NativeInventoryEntry], notes: [NoteDocument], full: Bool, now: Date) {
        var values: [Data: (stamp: Stamp, path: String, content: String)] = [:]
        values.reserveCapacity(entries.count)
        for (entry, note) in zip(entries, notes) {
            guard let stamp = Self.stamp(entry) else { continue }
            values[Data(entry.path.utf8)] = (stamp, entry.path, note.content)
        }
        lock.lock(); defer { lock.unlock() }
        var vault = vaults[root] ?? Vault()
        vault.notes = values
        if full { vault.lastFull = now }
        vaults[root] = vault
    }
    func reset() { lock.lock(); vaults = [:]; lock.unlock() }
    private static func stamp(_ entry: NativeInventoryEntry) -> Stamp? {
        guard let changed = entry.changed, let size = entry.size else { return nil }
        return .init(modified: entry.modified, changed: changed, size: size)
    }
}
