import Foundation
import SwiftUI

/// Informational Markdown views retain one running snapshot and only the newest
/// pending input. Parsing never runs while SwiftUI builds the window body.
@MainActor final class MacMarkdownSnapshotState<Value: Equatable & Sendable>: ObservableObject {
    @Published private(set) var value: Value?
    private let queue: DispatchQueue
    private let compute: @Sendable (String) -> Value
    private var revision: UInt64 = 0
    private var pending: (revision: UInt64, text: String)?
    private var running = false
    private var scheduled: Task<Void, Never>?
    init(queue: DispatchQueue, compute: @escaping @Sendable (String) -> Value) {
        self.queue = queue; self.compute = compute
    }
    func request(_ text: String) {
        revision &+= 1; pending = (revision, text)
        scheduled?.cancel()
        scheduled = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.scheduled = nil; self.startIfReady()
        }
    }
    func cancel() {
        revision &+= 1; pending = nil; scheduled?.cancel(); scheduled = nil
    }
    private func startIfReady() {
        guard !running, scheduled == nil, let work = pending else { return }
        pending = nil; running = true
        let compute = compute
        queue.async { [weak self] in
            let result = compute(work.text), token = work.revision
            DispatchQueue.main.async { [weak self] in self?.finished(result, revision: token) }
        }
    }
    private func finished(_ result: Value, revision token: UInt64) {
        running = false
        if token == revision, value != result { value = result }
        startIfReady()
    }
}
