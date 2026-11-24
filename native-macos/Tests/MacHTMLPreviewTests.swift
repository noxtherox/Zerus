import XCTest
import AppKit
import WebKit
import Network
@testable import Zerus_Native

@MainActor final class MacHTMLPreviewTests: XCTestCase {
    func testHTMLChoicePersistsExactApprovalAndExpiresOnChangedBytesEvenWithUnchangedMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-html-choice-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("report.html"), key = MacHTMLPreviewSession.key(root: root, identity: "report")
        defer { UserDefaults.standard.removeObject(forKey: key); try? FileManager.default.removeItem(at: root) }
        try Data("<p>Plain document</p>".utf8).write(to: file)
        let session = MacHTMLPreviewSession()
        await session.prepare(lease: try NativeFileLease(scope: file), key: key)
        XCTAssertEqual(session.state.mode, .safe)
        let source = #"<script>document.title='A';fetch('https://api.example.test:8443/data')</script><img src='//images.example.test/p.png'>"#
        try Data(source.utf8).write(to: file)
        let lease = try NativeFileLease(scope: file)
        let automatic = MacHTMLPreviewSession(); await automatic.prepare(lease: lease, key: key)
        XCTAssertEqual(automatic.state.mode, .safe, "An automatically chosen Safe mode must remain Safe after reopening a file that now contains scripts")
        UserDefaults.standard.removeObject(forKey: key)
        await session.prepare(lease: lease, key: key)
        XCTAssertNil(session.state.mode)
        XCTAssertEqual(session.state.document?.origins, ["https://api.example.test:8443", "https://images.example.test"])
        try await session.choose(.full)
        let approved = try XCTUnwrap(session.state.document?.fingerprint)
        let reopened = MacHTMLPreviewSession(); await reopened.prepare(lease: lease, key: key)
        XCTAssertEqual(reopened.state.mode, .full); XCTAssertEqual(reopened.state.document?.fingerprint, approved)
        let preference = try XCTUnwrap(UserDefaults.standard.dictionary(forKey: key))
        var altered = preference; altered["origins"] = ["https://other.example.test"]
        UserDefaults.standard.set(altered, forKey: key); await reopened.prepare(lease: lease, key: key)
        XCTAssertNil(reopened.state.mode); XCTAssertTrue(reopened.state.approvalExpired)
        UserDefaults.standard.set(preference, forKey: key); await reopened.prepare(lease: lease, key: key)
        XCTAssertEqual(reopened.state.mode, .full)
        let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try Data(source.replacingOccurrences(of: "title='A'", with: "title='B'").utf8).write(to: file)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path) }
        await reopened.prepare(lease: lease, key: key)
        XCTAssertNil(reopened.state.mode); XCTAssertTrue(reopened.state.approvalExpired)
        XCTAssertNotEqual(reopened.state.document?.fingerprint, approved)
        try Data((source + " ").utf8).write(to: file)
        do { try await reopened.choose(.full); XCTFail("Changed review bytes cannot inherit approval") }
        catch { XCTAssertTrue(error.localizedDescription.contains("changed during review"), error.localizedDescription) }
        try await reopened.choose(.link)
        let linked = MacHTMLPreviewSession(); await linked.prepare(lease: lease, key: key)
        XCTAssertEqual(linked.state.mode, .link)
        try Data(repeating: 32, count: MacHTMLPreviewDocument.maximum + 1).write(to: file)
        await linked.prepare(lease: lease, key: key)
        XCTAssertNil(linked.state.document); XCTAssertEqual(linked.state.mode, .link); XCTAssertTrue(linked.state.issue?.contains("10 MB") == true)
        try await linked.choose(.link)
        let complex = Data(String(repeating: "<img>", count: 60_000).utf8)
        try complex.write(to: file); await linked.prepare(lease: lease, key: key)
        XCTAssertNil(linked.state.document); XCTAssertTrue(linked.state.issue?.contains("too complex") == true)
        XCTAssertEqual(try Data(contentsOf: file), complex)
        let manyOrigins = (0..<129).map { "<img src='https://site-\($0).example.test/image'>" }.joined()
        try Data(manyOrigins.utf8).write(to: file); await linked.prepare(lease: lease, key: key)
        XCTAssertEqual(linked.state.document?.fullReady, false)
        do { try await linked.choose(.full); XCTFail("An over-limit origin grant must be refused") }
        catch { XCTAssertTrue(error.localizedDescription.contains("128 external origins"), error.localizedDescription) }
        try await linked.choose(.safe); XCTAssertEqual(linked.state.mode, .safe)
        linked.cancel()
        do { try await linked.choose(.full); XCTFail("A closed preview cannot grant approval") } catch {}
    }

    func testSafeAndFullHTMLExecuteTheirActualWebKitPoliciesWithoutGrantingParentAccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-html-neighbor-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let neighbor = root.appendingPathComponent("private.txt"); try Data("private-fixture".utf8).write(to: neighbor)
        let source = #"<html><head><style>html,body{margin:0;height:100%;background:rgb(12,180,40)}</style><script>addEventListener('DOMContentLoaded',async()=>{let isolated=false;try{parent.document.title='escaped'}catch(e){isolated=true}let localBlocked=await fetch('\#(neighbor.absoluteString)').then(r=>r.text()).then(t=>!t.includes('private-fixture')).catch(()=>true);if(isolated&&localBlocked)document.body.style.background='rgb(30,50,220)'})</script></head><body>Visible fixture</body></html>"#
        for mode in [MacHTMLPreviewMode.safe, .full] {
            let page = MacHTMLWebPage(document: try .init(bytes: Data(source.utf8)), mode: mode)
            let window = NSWindow(contentRect: .init(x: -20000, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = page.webView; window.orderFront(nil)
            defer { page.stop(); window.contentView = nil; window.close() }
            await page.load()
            let color = try await renderedColor(page, matching: mode == .safe ? .green : .blue)
            XCTAssertGreaterThan(mode == .safe ? color.greenComponent : color.blueComponent, 0.5)
            XCTAssertNil(page.issue)
            let title = try await page.webView.evaluateJavaScript("document.title") as? String
            XCTAssertNotEqual(title, "escaped", "The opaque preview frame cannot modify its containing document")
        }
    }

    func testHTMLDownloadCommitsCompleteBytesAndPreservesChangedDestinations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-html-download-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        for variant in ["new", "replace", "changed", "appeared"] {
            let destination = root.appendingPathComponent(variant + ".txt"), original = Data("Original destination".utf8), received = Data("Completed HTML download".utf8), outside = Data("Outside edit".utf8)
            if variant == "replace" || variant == "changed" { try original.write(to: destination) }
            let target = try MacHTMLDownloadTarget(destination: destination)
            try received.write(to: target.temporary)
            if variant == "changed" || variant == "appeared" {
                try outside.write(to: destination)
                XCTAssertThrowsError(try target.commit()) { XCTAssertTrue($0.localizedDescription.contains("changed"), $0.localizedDescription) }
                XCTAssertEqual(try Data(contentsOf: destination), outside)
                XCTAssertEqual(try Data(contentsOf: target.temporary), received)
            } else {
                try target.commit(); XCTAssertEqual(try Data(contentsOf: destination), received)
                XCTAssertFalse(FileManager.default.fileExists(atPath: target.temporary.path))
            }
        }
    }

    func testRealWebKitLoadsOnlyApprovedOriginsIncludingInsideRemoteFrames() async throws {
        let denied = try HTMLHTTPFixture { _ in ("text/plain", Data("Unexpected request".utf8)) }
        let deniedPort = try await denied.start(); defer { denied.stop() }
        let child = "<script>const socket=new Promise(resolve=>{try{let s=new WebSocket('ws://'+'127.0.0.1:'+'\(deniedPort)'+'/child-socket');s.onerror=()=>resolve(true);s.onopen=()=>{s.close();resolve(false)};setTimeout(()=>{s.close();resolve(false)},3000)}catch(e){resolve(true)}});Promise.all([fetch('http://'+'127.0.0.1:'+'\(deniedPort)'+'/child-denied').then(()=>false).catch(()=>true),socket]).then(values=>parent.postMessage(values.every(Boolean)?'child-blocked':'child-escaped','*'))</script>"
        let allowed = try HTMLHTTPFixture { path in path == "/child" ? ("text/html", Data(child.utf8)) : ("text/plain", Data("Allowed response".utf8)) }
        let allowedPort = try await allowed.start(); defer { allowed.stop() }
        let origin = "http://127.0.0.1:\(allowedPort)"
        let source = #"""
        <html><head><style>html,body{margin:0;height:100%;background:rgb(12,180,40)}</style><script>
        let direct=false, child=false; const done=()=>{if(direct&&child)document.body.style.background='rgb(30,50,220)'};
        addEventListener('message',e=>{if(e.data==='child-blocked'){child=true;done()}});
        addEventListener('DOMContentLoaded',()=>{
          const socket=new Promise(resolve=>{try{let s=new WebSocket('ws://'+'127.0.0.1:'+'\#(deniedPort)'+'/socket');s.onerror=()=>resolve(true);s.onopen=()=>{s.close();resolve(false)};setTimeout(()=>{s.close();resolve(false)},3000)}catch(e){resolve(true)}});
          Promise.all([fetch('\#(origin)/data').then(r=>r.text()).then(t=>t==='Allowed response'),fetch('http://'+'127.0.0.1:'+'\#(deniedPort)'+'/direct-denied').then(()=>false).catch(()=>true),socket]).then(values=>{direct=values.every(Boolean);done()});
        });
        </script></head><body>Network fixture<iframe style="display:none" src="\#(origin)/child"></iframe></body></html>
        """#
        let document = try MacHTMLPreviewDocument(bytes: Data(source.utf8))
        XCTAssertEqual(document.origins, [origin])
        for mode in [MacHTMLPreviewMode.safe, .full] {
            let page = MacHTMLWebPage(document: document, mode: mode)
            let window = NSWindow(contentRect: .init(x: -20000, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = page.webView; window.orderFront(nil)
            defer { page.stop(); window.contentView = nil; window.close() }
            await page.load()
            _ = try await renderedColor(page, matching: mode == .safe ? .green : .blue)
            if mode == .safe { XCTAssertTrue(allowed.paths.isEmpty, "Safe preview must not contact even declared resource origins") }
            else { XCTAssertTrue(allowed.paths.contains("/data")); XCTAssertTrue(allowed.paths.contains("/child")) }
            XCTAssertTrue(denied.paths.isEmpty, "Unapproved fetch and WebSocket requests, including a remote frame's requests, must never reach the second origin: \(denied.paths)")
        }
    }

    func testRealWebKitResponsePolicyRequiresApprovedFullOriginsForServerAttachments() async throws {
        let server = try HTMLHTTPFixture(headers: { path in
            path == "/attachment.txt" ? ["Content-Disposition": "AtTaChMeNt; filename=fixture.txt"] :
                path == "/inline.txt" ? ["Content-Disposition": "inline; filename=attachment.txt"] : [:]
        }) { path in (path == "/binary" ? "application/octet-stream" : "text/plain", Data("Owned response fixture".utf8)) }
        let port = try await server.start(); defer { server.stop() }
        let other = try HTMLHTTPFixture { _ in ("application/octet-stream", Data("Unapproved origin fixture".utf8)) }
        let otherPort = try await other.start(); defer { other.stop() }
        let origin = "http://127.0.0.1:\(port)"
        let document = try MacHTMLPreviewDocument(bytes: Data("<p>Policy fixture</p><img src='\(origin)/probe'>".utf8))
        XCTAssertEqual(document.origins, [origin])
        @MainActor func response(_ address: String) async throws -> WKNavigationResponse {
            let probe = HTMLResponseProbe(), view = WKWebView()
            view.navigationDelegate = probe
            defer { view.stopLoading(); view.navigationDelegate = nil }
            view.load(URLRequest(url: try XCTUnwrap(URL(string: address))))
            let deadline = Date().addingTimeInterval(8)
            while probe.response == nil && probe.failure == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            if let failure = probe.failure { throw failure }
            return try XCTUnwrap(probe.response, "The real HTTP response must reach WebKit's navigation delegate")
        }
        let binary = try await response(origin + "/binary"), attachment = try await response(origin + "/attachment.txt")
        let inline = try await response(origin + "/inline.txt"), unapproved = try await response("http://127.0.0.1:\(otherPort)/binary")
        XCTAssertFalse(binary.canShowMIMEType); XCTAssertTrue(attachment.canShowMIMEType); XCTAssertTrue(inline.canShowMIMEType)
        for mode in [MacHTMLPreviewMode.safe, .full] {
            let page = MacHTMLWebPage(document: document, mode: mode)
            await page.load(); defer { page.stop() }
            for (received, expected) in [(binary, mode == .full ? WKNavigationResponsePolicy.download : .cancel),
                                         (attachment, mode == .full ? .download : .cancel), (unapproved, .cancel), (inline, .allow)] {
                // WebKit's default is to allow a response when this optional
                // delegate method is absent. Exercise the public SDK callback
                // with actual WebKit response metadata, without opening a save panel.
                var decision = WKNavigationResponsePolicy.allow
                _ = (page as WKNavigationDelegate).webView?(page.webView, decidePolicyFor: received, decisionHandler: { decision = $0 })
                XCTAssertEqual(decision, expected, "\(mode): \(received.response.url?.absoluteString ?? "missing URL") must receive its native response policy")
            }
            page.stop()
            var stopped = WKNavigationResponsePolicy.allow
            _ = (page as WKNavigationDelegate).webView?(page.webView, decidePolicyFor: attachment, decisionHandler: { stopped = $0 })
            XCTAssertEqual(stopped, .cancel, "A closed preview cannot start a server download")
        }
    }

    private enum ExpectedColor { case green, blue }
    private func renderedColor(_ page: MacHTMLWebPage, matching expected: ExpectedColor) async throws -> NSColor {
        let deadline = Date().addingTimeInterval(12)
        var latest = NSColor.white
        while Date() < deadline {
            if let issue = page.issue { throw VaultFailure(message: issue) }
            if page.ready {
                let image: NSImage = try await withCheckedThrowingContinuation { continuation in
                    page.webView.takeSnapshot(with: nil) { image, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let image { continuation.resume(returning: image) }
                        else { continuation.resume(throwing: VaultFailure(message: "WebKit did not return a preview snapshot.")) }
                    }
                }
                let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                latest = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
                if expected == .green ? latest.greenComponent > latest.blueComponent + 0.25 && latest.greenComponent > latest.redComponent + 0.25 : latest.blueComponent > latest.greenComponent + 0.25 && latest.blueComponent > latest.redComponent + 0.25 { return latest }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("HTML did not render the expected policy color: \(latest)")
        return latest
    }
}

@MainActor private final class HTMLResponseProbe: NSObject, WKNavigationDelegate {
    var response: WKNavigationResponse?
    var failure: Error?
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        self.response = response; decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if response == nil { failure = error }
    }
}

/// A real loopback HTTP peer reached by WebKit's separate network process.
/// The response protocol never simulates the app's filtering decisions.
final class HTMLHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "zerus.html-preview.http")
    private let lock = NSLock()
    private var requests: [String] = []
    private var connections: [NWConnection] = []
    private let response: @Sendable (String) -> (String, Data)
    private let headers: @Sendable (String) -> [String: String]
    private let cacheControl: @Sendable (String) -> String
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return requests }
    init(cacheControl: @escaping @Sendable (String) -> String = { _ in "no-store" }, headers: @escaping @Sendable (String) -> [String: String] = { _ in [:] }, response: @escaping @Sendable (String) -> (String, Data)) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any); self.response = response; self.headers = headers; self.cacheControl = cacheControl
    }
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    if let port = self.listener.port { continuation.resume(returning: port.rawValue) }
                    else { continuation.resume(throwing: VaultFailure(message: "The loopback fixture has no port.")) }
                case .failed(let error): self.listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.lock.lock(); self.connections.append(connection); self.lock.unlock()
                connection.start(queue: self.queue); self.read(connection, bytes: Data())
            }
            listener.start(queue: queue)
        }
    }
    private func read(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            let data = bytes + (chunk ?? Data())
            if data.range(of: Data("\r\n\r\n".utf8)) != nil {
                let path = String(decoding: data, as: UTF8.self).split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                self.lock.lock(); self.requests.append(path); self.lock.unlock()
                let (type, body) = self.response(path)
                let additional = self.headers(path).map { $0.key + ": " + $0.value + "\r\n" }.sorted().joined()
                let header = Data("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: \(self.cacheControl(path))\r\n".utf8) + Data(additional.utf8) + Data("Connection: close\r\n\r\n".utf8)
                connection.send(content: header + body, completion: .contentProcessed { _ in connection.cancel() })
            } else if error != nil || complete || data.count > 64_000 { connection.cancel() }
            else { self.read(connection, bytes: data) }
        }
    }
    func stop() {
        listener.cancel(); lock.lock(); let pending = connections; connections.removeAll(); lock.unlock()
        pending.forEach { $0.cancel() }
    }
}
