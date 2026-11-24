import XCTest
@testable import Zerus_Native

final class MacJSONTests: XCTestCase {
    func testPersistedJsonRetainsFoundationScalarAndDuplicateKeySemantics() async throws {
        var samples = [
            #"{"boolean":true,"number":1,"negative":-42,"float":0.125,"null":null,"text":"Café 👩🏽‍💻","array":[false,0,"x"]}"#,
            #"{"signed":-9223372036854775808,"unsigned":18446744073709551615,"exponent":1e3,"fraction":1.0}"#,
            #"{"value":1,"value":2,"nested":{"text":"first","text":"second"}}"#,
            #"{"quoted":"brackets [ { and escaped quote \" stay text","empty":{}}"#
        ]
        let manyBrackets = try JSONSerialization.data(withJSONObject: ["text": String(repeating: "[{", count: 600)])
        samples.append(String(decoding: manyBrackets, as: UTF8.self))
        for sample in samples {
            let bytes = Data(sample.utf8)
            let actual = try await Task.detached { try NativeJSON.object(with: bytes) as! NSDictionary }.value
            let expected = try JSONSerialization.jsonObject(with: bytes) as! NSDictionary
            XCTAssertEqual(actual, expected, sample)
        }
        let booleans = try XCTUnwrap(NativeJSON.object(with: Data(#"{"flag":true,"number":1}"#.utf8)) as? [String: Any])
        XCTAssertEqual(NativeRevisions.boolean(booleans["flag"]), true)
        XCTAssertNil(NativeRevisions.boolean(booleans["number"]))
    }
    func testDeepPersistedJsonIsRefusedBeforeRecursiveDecoding() async throws {
        for depth in [65, 512] {
            let bytes = Data((String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)).utf8)
            do {
                _ = try await Task.detached { try NativeJSON.object(with: bytes) as! NSArray }.value
                XCTFail("Deep synced/model JSON must be refused before recursive decoding")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("nesting exceeds"), error.localizedDescription)
            }
        }
        let boundary = Data((String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)).utf8)
        _ = try await Task.detached { try NativeJSON.object(with: boundary) as! NSArray }.value
    }
}
