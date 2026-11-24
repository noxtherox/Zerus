import Foundation

final class ChatHTTPFixture: URLProtocol, @unchecked Sendable {
    final class Script: @unchecked Sendable {
        let onStart: (@Sendable () -> Void)?
        let onStop: (@Sendable () -> Void)?
        let next: Script?
        let first: Data; let remaining: [Data]; let gate: DispatchSemaphore?; let status: Int; let contentType: String
        init(first: String, remaining: [String], paused: Bool = false, status: Int = 200, contentType: String = "text/event-stream", next: Script? = nil, onStart: (@Sendable () -> Void)? = nil, onStop: (@Sendable () -> Void)? = nil) { self.onStart = onStart; self.onStop = onStop; self.next = next; self.first = Data(first.utf8); self.remaining = remaining.map { Data($0.utf8) }; gate = paused ? DispatchSemaphore(value: 0) : nil; self.status = status; self.contentType = contentType }
    }
    private static let lock = NSLock()
    private static var scripts: [String: Script] = [:], requests: [String: URLRequest] = [:]
    private let state = NSLock()
    private var stopped = false
    private var script: Script?
    static func register(_ script: Script, path: String) { lock.lock(); defer { lock.unlock() }; scripts[path] = script }
    static func captured(_ path: String) -> URLRequest? { lock.lock(); defer { lock.unlock() }; return requests[path] }
    static func remove(_ path: String) { lock.lock(); defer { lock.unlock() }; scripts.removeValue(forKey: path); requests.removeValue(forKey: path) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let script = Self.scripts[request.url!.path]; Self.requests[request.url!.path] = request; if let next = script?.next { Self.scripts[request.url!.path] = next }; Self.lock.unlock()
        guard let script else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        self.script = script
        DispatchQueue(label: "Zerus-chat-http-fixture").async { [self] in
            guard let response = HTTPURLResponse(url: request.url!, statusCode: script.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": script.contentType]) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: script.first)
            script.onStart?()
            if let gate = script.gate { _ = gate.wait(timeout: .now() + 8) }
            state.lock(); let ended = stopped; state.unlock(); guard !ended else { return }
            for bytes in script.remaining { client?.urlProtocol(self, didLoad: bytes) }
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { state.lock(); stopped = true; let gate = script?.gate; state.unlock(); gate?.signal(); script?.onStop?() }
}

