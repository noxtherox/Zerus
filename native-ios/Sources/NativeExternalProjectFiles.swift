import Foundation
import ImageIO

/// This capability comes only from the explicit project-folder picker, which
/// explains both reading existing attachments and adding new ones. Generic
/// document previews and mapped read capabilities cannot create project files.
final class NativeExternalProjectFiles: @unchecked Sendable {
    let id = UUID()
    let root: URL
    let source: URL
    private let canonicalRoot: URL
    private let rootIdentity: AnyHashable?
    private let scoped: Bool
    init(selectedProject root: URL, source: URL) throws {
        self.root = root; self.source = source; scoped = root.startAccessingSecurityScopedResource()
        canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        rootIdentity = try? root.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? AnyHashable
        do {
            guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw VaultFailure(message: "Choose a project folder containing this Markdown file and its attachments.") }
            _ = try VaultFiles.confinedPath(for: source, root: root)
        } catch { if scoped { root.stopAccessingSecurityScopedResource() }; throw error }
    }
    deinit { if scoped { root.stopAccessingSecurityScopedResource() } }
    private func validate(_ url: URL) throws {
        var currentRoot = root; currentRoot.removeAllCachedResourceValues()
        let values = try currentRoot.resourceValues(forKeys: [.isDirectoryKey, .fileResourceIdentifierKey])
        guard values.isDirectory == true, root.resolvingSymlinksInPath().standardizedFileURL == canonicalRoot,
              rootIdentity == nil || (values.fileResourceIdentifier as? AnyHashable) == rootIdentity else { throw VaultFailure(message: "The project folder moved or became a link. Choose it again before accessing its attachments.") }
        _ = try VaultFiles.confinedPath(for: url, root: root)
    }
    func location(_ reference: String) throws -> URL {
        guard let parsed = URL(string: reference), parsed.scheme == nil || (parsed.isFileURL && (parsed.host == nil || parsed.host == "" || parsed.host == "localhost")) else { throw VaultFailure(message: "This attachment is not a local project file.") }
        let path = parsed.relativePath
        guard !path.isEmpty, !path.contains("\\") else { throw VaultFailure(message: "This attachment path is unsupported.") }
        let url = parsed.isFileURL ? parsed : path.hasPrefix("/") ? URL(fileURLWithPath: path) : source.deletingLastPathComponent().appendingPathComponent(path)
        try validate(url); return url.standardizedFileURL
    }
    private func read(_ url: URL, preview: NativeCoordinatedRead<Data>? = nil) throws -> Data {
        try preview?.check()
        try validate(url)
        var coordination: NSError?, result: Result<Data, Error> = .failure(VaultFailure(message: "This attachment is unavailable in the project folder."))
        let coordinator = NSFileCoordinator()
        let coordinate = {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordination) { location in result = Result {
                try preview?.check()
                try self.validate(location)
                let values = try location.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, (values.fileSize ?? 0) <= NativeClipboardFragment.limit else { throw VaultFailure(message: "Project attachments must be available files below 50 MB.") }
                let handle = try FileHandle(forReadingFrom: location); defer { try? handle.close() }
                let bytes = try handle.read(upToCount: NativeClipboardFragment.limit + 1) ?? Data()
                guard bytes.count <= NativeClipboardFragment.limit else { throw VaultFailure(message: "This attachment exceeds the 50 MB limit.") }
                return bytes
            } }
        }
        if let preview { try preview.coordinating(coordinator, coordinate) } else { coordinate() }
        try preview?.check()
        if let coordination { throw coordination }; return try result.get()
    }
    func transferLease(_ reference: String) throws -> NativeFileLease {
        try NativeFileLease(scope: root, url: location(reference))
    }
    func validateTransferResource(_ reference: String) throws { _ = try location(reference) }
    func data(_ reference: String) async throws -> Data {
        let job = Task.detached(priority: .userInitiated) { try self.read(self.location(reference)) }
        let value = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
        try Task.checkCancellation(); return value
    }
    struct ImageVersion: Sendable, Equatable {
        let modified: Date?
        let created: Date?
        let byteCount: Int?
    }
    /// Inspect local provider metadata without materializing unchanged image
    /// bytes. A stalled metadata lookup still obeys the preview deadline.
    func imageVersion(_ reference: String) async throws -> ImageVersion {
        let version = try await NativeCoordinatedRead<ImageVersion>().value(timeout: 15) { operation in
            var url = try self.location(reference); url.removeAllCachedResourceValues()
            try operation.check()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey])
            try self.validate(url); try operation.check()
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= NativeClipboardFragment.limit else { throw VaultFailure(message: "Project attachments must be available files below 50 MB.") }
            return ImageVersion(modified: values.contentModificationDate, created: values.creationDate, byteCount: values.fileSize)
        }
        try Task.checkCancellation(); return version
    }
    func thumbnail(_ reference: String) async throws -> CGImage {
        // A provider may keep materializing after the editor leaves. Stop
        // waiting within the preview deadline; the worker retains this scoped
        // capability until the coordinated read has actually finished.
        let bytes = try await NativeCoordinatedRead<Data>().value(timeout: 15) { operation in
            try self.read(self.location(reference), preview: operation)
        }
        try Task.checkCancellation()
        let job = Task.detached(priority: .userInitiated) { () throws -> CGImage in
            guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary) else { throw VaultFailure(message: "This attachment cannot be displayed as an image.") }
            return image
        }
        let result = try await job.value; try Task.checkCancellation(); return result
    }
    func preview(_ reference: String) async throws -> NativeFileLease {
        let job = Task.detached(priority: .userInitiated) { () throws -> NativeFileLease in
            let url = try self.location(reference)
            return try NativeFileLease(scope: self.root, url: url)
        }
        let lease = try await job.value; try Task.checkCancellation(); return lease
    }
    private func relative(_ target: URL) -> String {
        let base = source.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.pathComponents, components = target.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var common = 0
        while common < min(base.count, components.count), base[common] == components[common] { common += 1 }
        let path = (Array(repeating: "..", count: base.count - common) + components.dropFirst(common)).joined(separator: "/")
        return path.hasPrefix("../") ? path : "./" + path
    }
    func fragment(_ markdown: String) async throws -> NativeClipboardFragment {
        let job = Task.detached(priority: .userInitiated) { () throws -> NativeClipboardFragment in
            var resources: [NativeClipboardFragment.Resource] = [], size = markdown.utf8.count
            guard size <= NativeClipboardFragment.limit else { throw VaultFailure(message: "Copy a smaller selection.") }
            for reference in Set(MarkdownResources.localReferences(in: markdown)).sorted() {
                try Task.checkCancellation()
                let url = try self.location(reference), bytes = try self.read(url)
                size += bytes.count
                guard size <= NativeClipboardFragment.limit else { throw VaultFailure(message: "The copied attachments exceed 50 MB. Copy a smaller selection.") }
                let path = String(url.resolvingSymlinksInPath().standardizedFileURL.path.dropFirst(self.canonicalRoot.path.count + 1))
                resources.append(.init(reference: reference, path: path, name: url.lastPathComponent, bytes: bytes))
            }
            return .init(markdown: markdown, vault: NativeClipboardFragment.vaultID(self.root), resources: resources)
        }
        let fragment = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
        try Task.checkCancellation(); return fragment
    }
    func importFragment(_ fragment: NativeClipboardFragment) async throws -> String {
        let job = Task.detached(priority: .userInitiated) { () throws -> String in
            try fragment.validate()
            let references = Set(MarkdownResources.localReferences(in: fragment.markdown))
            guard references.isSubset(of: Set(fragment.resources.map(\.reference))), fragment.resources.allSatisfy({ $0.bytes != nil }) else { throw VaultFailure(message: "The clipboard does not contain all attachment files. Paste Markdown source to keep its references unchanged.") }
            var replacements: [String: String] = [:], created: [(URL, Data)] = []
            do {
                for resource in fragment.resources {
                    try Task.checkCancellation()
                    let bytes = resource.bytes!, target: URL
                    if fragment.vault == NativeClipboardFragment.vaultID(self.root), let path = resource.path, NativeRevisionIndex.validPath(path),
                       let candidate = try? self.locationForProjectPath(path), (try? self.read(candidate)) == bytes {
                        target = candidate
                    } else {
                        let name = String(resource.name.replacingOccurrences(of: #"[/\\:\x00-\x1F]"#, with: "-", options: .regularExpression).prefix(180))
                        target = self.root.appendingPathComponent("assets/" + UUID().uuidString.lowercased() + "-" + (name.isEmpty ? "Attachment" : name))
                        try self.validate(target)
                        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        var coordination: NSError?, result: Result<Void, Error> = .failure(VaultFailure(message: "The attachment could not be added."))
                        NSFileCoordinator().coordinate(writingItemAt: target, options: [], error: &coordination) { url in result = Result {
                            try self.validate(url); try Task.checkCancellation()
                            guard !FileManager.default.fileExists(atPath: url.path) else { throw VaultFailure(message: "An attachment file already exists. Paste again to choose a new filename.") }
                            try bytes.write(to: url, options: .withoutOverwriting)
                        } }
                        if let coordination { throw coordination }; try result.get()
                        created.append((target, bytes))
                    }
                    replacements[resource.reference] = MarkdownResources.encodedPath(self.relative(target), preservingSuffixOf: resource.reference)
                }
                try Task.checkCancellation()
                return MarkdownResources.replacing(fragment.markdown, references: replacements)
            } catch {
                // Only remove new files still equal to this operation's bytes.
                // Outside changes, originals and shared files are never removed.
                for (url, bytes) in created.reversed() {
                    var coordination: NSError?
                    NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordination) { location in
                        if (try? self.validate(location)) != nil, (try? Data(contentsOf: location)) == bytes { try? FileManager.default.removeItem(at: location) }
                    }
                }
                throw error
            }
        }
        return try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
    }
    private func locationForProjectPath(_ path: String) throws -> URL { let url = root.appendingPathComponent(path); try validate(url); return url }
}
