import XCTest
import ZerusChatGPTCore

final class NativeChatGPTCompletionTests: XCTestCase {
    func testCompletedToolOnlyTurnsRemainValidForAgentsWhilePlainChatAndIncompleteStreamsKeepTheirChecks() async throws {
        let events: [[String:Any]] = [
            ["type":"response.output_item.done", "output_index":0, "item":["type":"reasoning", "id":"reasoning-final", "summary":[]]],
            ["type":"response.completed", "response":["status":"completed", "output":[], "usage":["input_tokens":17,"output_tokens":3]]]
        ]
        let wire = try events.map { "data: " + String(decoding: try JSONSerialization.data(withJSONObject:$0),as:UTF8.self) + "\n\n" }.joined()
        let bytes = AsyncStream<UInt8> { continuation in for byte in wire.utf8 { continuation.yield(byte) }; continuation.finish() }
        let completed = try await ChatGPTResponseStream.consume(bytes) { _ in }
        let agent = try ChatGPTResponses.completedResult(completed, streamedText:"", agent:true)
        XCTAssertEqual(agent["content"] as? String, "")
        XCTAssertEqual((agent["toolCalls"] as? [[String:String]])?.count, 0)
        XCTAssertEqual(agent["finishReason"] as? String, "stop")
        XCTAssertEqual(agent["usage"] as? [String:Int], ["inputTokens":17,"outputTokens":3])
        XCTAssertThrowsError(try ChatGPTResponses.completedResult(completed, streamedText:"", agent:false))
        let fallback = try ChatGPTResponses.completedResult(completed, streamedText:"Visible streamed answer", agent:false)
        XCTAssertEqual(fallback["content"] as? String, "Visible streamed answer")
        let tool: [String:Any] = ["status":"completed", "output":[["type":"function_call","call_id":"plan-call","name":"update_plan","arguments":"{}"]]]
        let toolResult = try ChatGPTResponses.completedResult(tool, streamedText:"", agent:false)
        XCTAssertEqual((toolResult["toolCalls"] as? [[String:String]])?.first?["id"], "plan-call")
        for status in ["incomplete","failed","in_progress"] {
            XCTAssertThrowsError(try ChatGPTResponses.completedResult(["status":status,"output":[]], streamedText:"", agent:true))
        }
    }
}
