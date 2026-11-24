import Foundation

/// A recovery export is a copy of exact encoded Markdown, not permission to
/// overwrite the connected original or any private recovery state.
final class MacExternalDraftExport: @unchecked Sendable {
    let lease: NativeFileLease
    let bytes: Data
    private init(lease: NativeFileLease, bytes: Data) { self.lease = lease; self.bytes = bytes }
    // Foundation may leave /var unresolved when the final file does not exist,
    // while a bookmark resolves the same parent through /private/var. Resolve
    // the nearest existing ancestor before comparing protected destinations.
    static func canonical(_ url: URL) -> URL {
        var ancestor = url.standardizedFileURL, suffix: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            suffix.append(ancestor.lastPathComponent); ancestor.deleteLastPathComponent()
        }
        var result = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for part in suffix.reversed() { result.appendPathComponent(part) }
        return result.standardizedFileURL
    }
    static func create(bytes: Data, to url: URL, original: URL, privateDirectory: URL) async throws -> MacExternalDraftExport {
        try await NativeCoordinatedRead<MacExternalDraftExport>().value(timeout: 15) { operation in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            func validate(_ target: URL) throws {
                let path = canonical(target)
                guard path.path != canonical(original).path,
                      !path.pathComponents.starts(with: canonical(privateDirectory).pathComponents) else { throw VaultFailure(message: "Export to a separate Markdown file outside the original and private recovery folder.") }
                if let sourceID = try? original.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? AnyHashable,
                   let targetID = try? target.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? AnyHashable,
                   sourceID == targetID { throw VaultFailure(message: "This destination refers to the original file. Choose a different export file.") }
            }
            try validate(url); try operation.check()
            var coordination: NSError?, result: Result<Void, Error> = .failure(VaultFailure(message: "The draft export could not be written."))
            let coordinator = NSFileCoordinator()
            try operation.coordinating(coordinator) {
                coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordination) { target in result = Result {
                    try validate(target); try operation.check(); try bytes.write(to: target, options: .atomic)
                } }
            }
            if let coordination { throw coordination }; try result.get(); try operation.check()
            let export = MacExternalDraftExport(lease: try NativeFileLease(scope: url, url: url), bytes: bytes)
            guard try export.readMatches(operation: operation) else { throw VaultFailure(message: "The exported copy could not be verified. Keep this editor open and export the draft again.") }
            return export
        }
    }
    private func readMatches<T: Sendable>(operation: NativeCoordinatedRead<T>) throws -> Bool {
        try operation.check()
        let coordinator = NSFileCoordinator()
        var coordination: NSError?, result: Result<Bool, Error> = .success(false)
        try operation.coordinating(coordinator) {
            coordinator.coordinate(readingItemAt: lease.url, options: [], error: &coordination) { location in result = Result {
                try operation.check()
                var fresh = location; fresh.removeAllCachedResourceValues()
                let values = try fresh.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard fresh.resolvingSymlinksInPath().standardizedFileURL.path == self.lease.canonicalPath, values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == self.bytes.count else { return false }
                let handle = try FileHandle(forReadingFrom: fresh); defer { try? handle.close() }
                let saved = try handle.read(upToCount: self.bytes.count + 1) ?? Data()
                try operation.check(); return saved == self.bytes
            } }
        }
        if let coordination { throw coordination }; return try result.get()
    }
    func matches() async -> Bool {
        (try? await NativeCoordinatedRead<Bool>().value(timeout: 15) { operation in try self.readMatches(operation: operation) }) == true
    }
}
