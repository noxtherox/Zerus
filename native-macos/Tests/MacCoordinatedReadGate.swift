import Foundation

/// Holds a real coordinated read; production IO and actor methods stay intact.
final class MacCoordinatedReadGate: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    typealias Reader = @Sendable ((@Sendable () -> Void)?) -> Void
    private let lock = NSLock()
    private var pending: [Reader] = []
    private var released = false
    private var signaled = false
    private let reached: () -> Void
    init(_ url: URL, reached: @escaping () -> Void) { presentedItemURL = url; self.reached = reached; super.init() }
    func relinquishPresentedItem(toReader reader: @escaping Reader) {
        lock.lock()
        if released { lock.unlock(); reader(nil); return }
        pending.append(reader); let signal = !signaled; signaled = true; lock.unlock()
        if signal { reached() }
    }
    func release() {
        lock.lock(); released = true; let values = pending; pending = []; lock.unlock()
        for reader in values { reader(nil) }
    }
}
