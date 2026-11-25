import Foundation

/// Downloads pinned model files from Hugging Face. This is the only code in
/// the local AI packages allowed to touch the network (enforced by
/// `NetworkGuardTests`). Every file is checked against its published digest
/// before it is moved into place; nothing about the user or their notes is
/// sent (ephemeral session, no cookies, no cache, generic user agent).
public final class LocalAIModelDownloader: NSObject, @unchecked Sendable {
    public enum NetworkPolicy: Sendable {
        /// Default: no cellular, no personal hotspot, no Low Data Mode.
        case wifiOnly
        case anyNetwork
    }

    public struct Progress: Sendable {
        public let model: LocalAIModelSpec
        public let completedBytes: Int64
        public let totalBytes: Int64
        public var fraction: Double { totalBytes == 0 ? 1 : Double(completedBytes) / Double(totalBytes) }
    }

    public enum Failure: LocalizedError {
        case insufficientSpace(needed: Int64, available: Int64)
        case http(status: Int, file: String)

        public var errorDescription: String? {
            switch self {
            case .insufficientSpace(let needed, let available):
                let f = ByteCountFormatter()
                return "Downloading needs \(f.string(fromByteCount: needed)) of free space; \(f.string(fromByteCount: available)) is available."
            case .http(let status, let file):
                return "Hugging Face returned HTTP \(status) for \(file). Try again later."
            }
        }
    }

    private let store: LocalAIModelStore
    private let session: URLSession
    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]

    private struct Pending {
        let destination: URL
        let progress: (Int64) -> Void
        let continuation: CheckedContinuation<Void, Error>
        var moved = false
        var failure: Error?
    }

    public init(store: LocalAIModelStore, policy: NetworkPolicy = .wifiOnly) {
        self.store = store
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = policy == .anyNetwork
        configuration.allowsExpensiveNetworkAccess = policy == .anyNetwork
        configuration.allowsConstrainedNetworkAccess = policy == .anyNetwork
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = ["User-Agent": "ZerusLocalAI/1"]
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let box = DelegateBox()
        session = URLSession(configuration: configuration, delegate: box, delegateQueue: queue)
        super.init()
        box.owner = self
    }

    deinit { session.invalidateAndCancel() }

    /// Downloads whatever is missing for `spec`, verifies it and marks it
    /// installed. Already verified files are kept, so a cancelled download
    /// resumes file by file.
    public func install(_ spec: LocalAIModelSpec, progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws {
        try store.prepareDirectories(for: spec)
        let directory = store.directory(for: spec)
        var done: Int64 = 0
        var missing: [LocalAIModelFile] = []
        for file in spec.files {
            let url = directory.appendingPathComponent(file.path)
            if (try? LocalAIModelStore.verify(url, file)) != nil { done += file.size } else { missing.append(file) }
        }
        let needed = missing.reduce(0) { $0 + $1.size }
        if needed > 0 {
            let available = (try? store.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage) ?? Int64.max
            let margin = needed / 10 + 200_000_000
            if available < needed + margin { throw Failure.insufficientSpace(needed: needed + margin, available: available) }
        }
        progress(Progress(model: spec, completedBytes: done, totalBytes: spec.totalBytes))
        for file in missing {
            try Task.checkCancellation()
            let staged = store.stagingDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staged) }
            let base = done
            try await download(spec.url(for: file), to: staged, file: file.path) { written in
                progress(Progress(model: spec, completedBytes: base + written, totalBytes: spec.totalBytes))
            }
            do { try LocalAIModelStore.verify(staged, file) } catch { throw error }
            let final = directory.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
            try FileManager.default.moveItem(at: staged, to: final)
            done += file.size
        }
        try store.verifyAndMarkInstalled(spec)
        progress(Progress(model: spec, completedBytes: spec.totalBytes, totalBytes: spec.totalBytes))
    }

    private func download(_ url: URL, to destination: URL, file: String, progress: @escaping (Int64) -> Void) async throws {
        let task = session.downloadTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    pending[task.taskIdentifier] = Pending(destination: destination, progress: progress, continuation: continuation)
                }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: Delegate callbacks (serial delegate queue)

    fileprivate func wrote(_ task: URLSessionTask, total: Int64) {
        let callback = lock.withLock { pending[task.taskIdentifier]?.progress }
        callback?(total)
    }

    fileprivate func finished(_ task: URLSessionDownloadTask, at location: URL) {
        lock.withLock {
            guard var entry = pending[task.taskIdentifier] else { return }
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                entry.failure = Failure.http(status: status, file: task.originalRequest?.url?.lastPathComponent ?? "")
            } else {
                do {
                    try? FileManager.default.removeItem(at: entry.destination)
                    try FileManager.default.moveItem(at: location, to: entry.destination)
                    entry.moved = true
                } catch { entry.failure = error }
            }
            pending[task.taskIdentifier] = entry
        }
    }

    fileprivate func completed(_ task: URLSessionTask, error: Error?) {
        guard let entry = lock.withLock({ pending.removeValue(forKey: task.taskIdentifier) }) else { return }
        if let failure = entry.failure ?? error {
            entry.continuation.resume(throwing: (failure as? URLError)?.code == .cancelled ? CancellationError() : failure)
        } else if entry.moved {
            entry.continuation.resume()
        } else {
            entry.continuation.resume(throwing: URLError(.cannotCreateFile))
        }
    }
}

/// Breaks the URLSession → delegate retain cycle.
private final class DelegateBox: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var owner: LocalAIModelDownloader?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        owner?.wrote(downloadTask, total: totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        owner?.finished(downloadTask, at: location)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        owner?.completed(task, error: error)
    }
}
