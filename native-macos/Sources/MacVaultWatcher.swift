import Foundation
import CoreServices

/// Signals when the vault folder may have changed: on FSEvents for anything
/// under the root (sync downloads, the CLI, other apps), and at least every
/// `fallback` seconds in case an event is missed. Bursts coalesce into one
/// signal; the consumer runs an incremental refresh for each.
final class MacVaultWatcher: @unchecked Sendable {
    static let fallback: Duration = .seconds(120)
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.zerus.native.vault-watcher")
    private let continuation: AsyncStream<Void>.Continuation
    let changes: AsyncStream<Void>
    private var timer: Task<Void, Never>?

    init(root: URL) {
        var continuation: AsyncStream<Void>.Continuation!
        changes = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        self.continuation = continuation
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<MacVaultWatcher>.fromOpaque(info).takeUnretainedValue().continuation.yield()
        }
        let path = root.resolvingSymlinksInPath().path as CFString
        if let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [path] as CFArray,
                                            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)) {
            FSEventStreamSetDispatchQueue(stream, queue)
            if FSEventStreamStart(stream) { self.stream = stream }
            else { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        }
        // Without a live event stream, fall back to the old 8-second poll.
        let interval: Duration = stream == nil ? .seconds(8) : Self.fallback
        let signal = self.continuation
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if !Task.isCancelled { signal.yield() }
            }
        }
    }
    func stop() {
        timer?.cancel(); timer = nil
        if let stream { queue.sync { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) } }
        stream = nil
        continuation.finish()
    }
    deinit { stop() }
}
