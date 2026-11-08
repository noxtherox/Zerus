@testable import ZerusIOSServices
import XCTest
@testable import ZerusNative

final class NativeDriveHTTPTests: XCTestCase {
    func testBoundedDriveResponsesEnforceAdvertisedAndActualByteLimitsAndCancelAnUnfinishedStream() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [DriveResponseProtocol.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        func request(_ path: String) -> URLRequest { URLRequest(url: URL(string: "https://drive-read.invalid/" + path)!) }
        let (bytes, response) = try await GoogleDriveManager.boundedResponse(for: request("ok"), session: session, limit: 8)
        XCTAssertEqual(bytes, Data([0, 255, 1, 2, 3, 4, 5, 6])); XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        for path in ["advertised", "stream"] {
            do { _ = try await GoogleDriveManager.boundedResponse(for: request(path), session: session, limit: 512); XCTFail("Accepted " + path + " overflow") }
            catch { XCTAssertTrue(error.localizedDescription.contains("download limit"), error.localizedDescription) }
        }
        let started = expectation(description: "Real URLSession receives the unfinished download's headers and first chunk")
        DriveResponseProtocol.pending = { started.fulfill() }; defer { DriveResponseProtocol.pending = nil }
        let read = Task { try await GoogleDriveManager.boundedResponse(for: request("pending"), session: session, limit: 512) }
        await fulfillment(of: [started], timeout: 3); read.cancel()
        do { _ = try await read.value; XCTFail("Cancelled HTTP stream completed") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled, error.localizedDescription) }
    }
}

private final class DriveResponseProtocol: URLProtocol, @unchecked Sendable {
    static var pending: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "drive-read.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.lastPathComponent
        let headers = path == "advertised" ? ["Content-Length": "513"] : [String: String]()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        if path == "ok" { client?.urlProtocol(self, didLoad: Data([0, 255, 1, 2, 3, 4, 5, 6])) }
        if path == "stream" { client?.urlProtocol(self, didLoad: Data(repeating: 42, count: 513)) }
        if path == "pending" { client?.urlProtocol(self, didLoad: Data(repeating: 42, count: 64)); Self.pending?(); return }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
