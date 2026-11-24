import Foundation
import Darwin

/// Inactive window state can leave the bounded preferences domain without
/// losing its original bytes. Current preferences always take precedence.
enum MacNavigationArchive {
    private static let prefix = "zerus.mac.navigation.v1."
    private enum Failure: LocalizedError {
        case invalidKey, unsafeFile, changed, differentArchive
        var errorDescription: String? {
            switch self {
            case .invalidKey: "Invalid window-state archive key."
            case .unsafeFile: "The saved window-state archive is not an ordinary file or folder."
            case .changed: "Saved window state changed; no preferences were removed."
            case .differentArchive: "A different window-state archive already exists; no preferences were removed."
            }
        }
    }
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zerus Native", isDirectory: true)
            .appendingPathComponent("Navigation Archive", isDirectory: true)
    }
    static func location(forKey key: String) throws -> URL {
        let suffix = key.dropFirst(prefix.count)
        guard key.hasPrefix(prefix), suffix.utf8.count == 64,
              suffix.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Failure.invalidKey }
        return directory.appendingPathComponent(String(suffix) + ".json")
    }
    private static func attributes(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
    }
    private static func prepare(create: Bool) throws -> Bool {
        for url in [directory.deletingLastPathComponent(), directory] {
            if let attributes = try attributes(url) {
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw Failure.unsafeFile }
            } else if create {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } else { return false }
        }
        return true
    }
    static func data(forKey key: String) throws -> Data? {
        let file = try location(forKey: key)
        guard try prepare(create: false), let attributes = try attributes(file) else { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure.unsafeFile }
        return try Data(contentsOf: file)
    }
    /// Call only while legacy application writers are stopped. A changed value
    /// or a conflicting archive is retained rather than overwritten or removed.
    @discardableResult static func archiveLegacy(_ expected: Data, forKey key: String, defaults: UserDefaults) throws -> URL {
        let file = try location(forKey: key)
        guard defaults.data(forKey: key) == expected else { throw Failure.changed }
        if let existing = try data(forKey: key) {
            guard existing == expected else { throw Failure.differentArchive }
        } else {
            _ = try prepare(create: true)
            let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try expected.write(to: temporary, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            try FileManager.default.moveItem(at: temporary, to: file)
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.synchronize()
        let folder = Darwin.open(directory.path, O_RDONLY)
        guard folder >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { _ = Darwin.close(folder) }
        guard Darwin.fsync(folder) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard try data(forKey: key) == expected, defaults.data(forKey: key) == expected else { throw Failure.changed }
        defaults.removeObject(forKey: key)
        guard defaults.data(forKey: key) == nil else { throw Failure.changed }
        return file
    }
}
