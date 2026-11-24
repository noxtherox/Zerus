import Foundation

/// Called inside the vault writer's existing coordinated/CAS operation.
/// Replacing an existing file must retain its birth date and access metadata;
/// ordinary Data.write(.atomic) gives the replacement a new birth date.
enum MacAtomicFileWrite {
    static func write(_ data: Data, to url: URL) throws {
        let files = FileManager.default
        guard files.fileExists(atPath: url.path) else {
            try data.write(to: url, options: .atomic)
            return
        }
        let staging = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        let payload = staging.appendingPathComponent(UUID().uuidString)
        try data.write(to: payload, options: .withoutOverwriting)
        // Default replacement options preserve original creation date,
        // permissions and Finder metadata while using the new file contents.
        _ = try files.replaceItemAt(url, withItemAt: payload, options: [])
        // On failure Foundation may retain the original in this directory.
        // Never delete that recovery material from a defer/error handler.
        try? files.removeItem(at: staging)
    }
}
