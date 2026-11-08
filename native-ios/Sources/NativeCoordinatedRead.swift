import Foundation

enum NativeCoordinatedReadFailure: Error { case timedOut }

/// A read may stop waiting even when a provider is still materializing its
/// file. The worker owns its scope; this object admits exactly one completion.
final class NativeCoordinatedRead<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var coordinator: NSFileCoordinator?
    private var deadline: DispatchWorkItem?

    func value(timeout: TimeInterval, _ read: @escaping @Sendable (NativeCoordinatedRead<Value>) throws -> Value) async throws -> Value {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result { lock.unlock(); continuation.resume(with: result); return }
                self.continuation = continuation
                let deadline = DispatchWorkItem { [weak self] in self?.finish(.failure(NativeCoordinatedReadFailure.timedOut)) }
                self.deadline = deadline
                lock.unlock()
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: deadline)
                DispatchQueue.global(qos: .userInitiated).async { self.finish(Result { try self.check(); return try read(self) }) }
            }
        }, onCancel: { self.finish(.failure(CancellationError())) })
    }
    func check() throws {
        lock.lock(); let result = result; lock.unlock()
        if let result {
            switch result { case .failure(let error): throw error; case .success: throw CancellationError() }
        }
    }
    func coordinating<T>(_ coordinator: NSFileCoordinator, _ body: () throws -> T) throws -> T {
        lock.lock()
        if let result { lock.unlock(); _ = try result.get(); throw CancellationError() }
        self.coordinator = coordinator
        lock.unlock()
        defer { lock.lock(); self.coordinator = nil; lock.unlock() }
        try check()
        return try body()
    }
    private func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = continuation, coordinator = coordinator, deadline = deadline
        self.continuation = nil; self.deadline = nil
        lock.unlock()
        deadline?.cancel()
        if case .failure = result { coordinator?.cancel() }
        continuation?.resume(with: result)
    }
}
