import CryptoKit
import Foundation

/// Where downloaded models live: Application Support (never the vault),
/// excluded from iCloud/iTunes backups, one folder per pinned revision.
public struct LocalAIModelStore: Sendable {
    public enum State: Equatable, Sendable {
        case notInstalled
        /// Some files are present (an interrupted download).
        case partial(bytesPresent: Int64)
        case installed
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `Application Support/Zerus/LocalAI/Models`.
    public static func standard() throws -> LocalAIModelStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return LocalAIModelStore(root: support.appendingPathComponent("Zerus/LocalAI/Models", isDirectory: true))
    }

    public func directory(for spec: LocalAIModelSpec) -> URL {
        root.appendingPathComponent(
            spec.repository.replacingOccurrences(of: "/", with: "--") + "@" + spec.revision, isDirectory: true)
    }

    var stagingDirectory: URL { root.appendingPathComponent(".staging", isDirectory: true) }

    private func marker(for spec: LocalAIModelSpec) -> URL {
        directory(for: spec).appendingPathComponent(".verified")
    }

    /// Installed means every file passed its checksum and the marker was
    /// written afterwards; sizes are re-checked cheaply on every call.
    public func state(of spec: LocalAIModelSpec) -> State {
        let fm = FileManager.default
        let dir = directory(for: spec)
        var present: Int64 = 0
        var complete = true
        for file in spec.files {
            let url = dir.appendingPathComponent(file.path)
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            if size == file.size { present += file.size } else { complete = false }
        }
        if complete, fm.fileExists(atPath: marker(for: spec).path) { return .installed }
        return present == 0 ? .notInstalled : .partial(bytesPresent: present)
    }

    /// Bytes still to download for `spec`.
    public func remainingBytes(for spec: LocalAIModelSpec) -> Int64 {
        let dir = directory(for: spec)
        return spec.files.reduce(0) { total, file in
            let size = (try? FileManager.default.attributesOfItem(
                atPath: dir.appendingPathComponent(file.path).path)[.size] as? NSNumber)?.int64Value
            return total + (size == file.size ? 0 : file.size)
        }
    }

    /// Verifies every file of `spec` and writes the installed marker.
    public func verifyAndMarkInstalled(_ spec: LocalAIModelSpec) throws {
        let dir = directory(for: spec)
        for file in spec.files {
            try Self.verify(dir.appendingPathComponent(file.path), file)
        }
        try Data(spec.revision.utf8).write(to: marker(for: spec), options: .atomic)
    }

    public func delete(_ spec: LocalAIModelSpec) throws {
        let dir = directory(for: spec)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }

    /// Removes every model, including other revisions and partial downloads.
    public func deleteAll() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    /// Bytes on disk under the store (all revisions and staging files).
    public func diskUsage() -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    func prepareDirectories(for spec: LocalAIModelSpec) throws {
        let fm = FileManager.default
        for dir in [root, directory(for: spec), stagingDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var rootURL = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try rootURL.setResourceValues(values)
    }

    // MARK: Checksums

    public struct ChecksumMismatch: LocalizedError {
        public let file: String
        public var errorDescription: String? {
            "The downloaded file \(file) did not match its published checksum. It was removed; try the download again."
        }
    }

    /// Streams the file through SHA-256 (LFS files) or git's blob SHA-1.
    public static func verify(_ url: URL, _ file: LocalAIModelFile) throws {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        guard size == file.size else { throw ChecksumMismatch(file: file.path) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let actual: String
        switch file.digest {
        case .sha256:
            var hasher = SHA256()
            try stream(handle) { hasher.update(data: $0) }
            actual = hasher.finalize().hex
        case .gitBlobSHA1:
            var hasher = Insecure.SHA1()
            hasher.update(data: Data("blob \(file.size)\0".utf8))
            try stream(handle) { hasher.update(data: $0) }
            actual = hasher.finalize().hex
        }
        let expected: String
        switch file.digest {
        case .sha256(let value), .gitBlobSHA1(let value): expected = value
        }
        guard actual == expected.lowercased() else { throw ChecksumMismatch(file: file.path) }
    }

    private static func stream(_ handle: FileHandle, _ body: (Data) -> Void) throws {
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: 8 << 20) }
            guard let chunk, !chunk.isEmpty else { return }
            body(chunk)
        }
    }
}

extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
