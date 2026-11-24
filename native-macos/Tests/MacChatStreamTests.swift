import XCTest
@testable import Zerus_Native

final class MacChatStreamTests: XCTestCase {
    func testFramingHandlesCRLFCommentsMultilineDataAndUTF8WithoutMixingReasoning() throws {
        let pretty = try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": "日本語 🧑🏽‍💻", "reasoning_content": "Private reasoning"]]]], options: [.prettyPrinted])
        let multiline = try XCTUnwrap(String(data: pretty, encoding: .utf8)).components(separatedBy: "\n").map { "data: " + $0 }.joined(separator: "\r\n")
        let input = ": keepalive\r\ndata: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\r\n\r\ndata: {\"choices\":[{\"delta\":{\"content\":\"Café \"}}]}\r\n\r\n" + multiline + "\r\n\r\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        var stream = MacChatStream(), visible = ""
        for byte in input.utf8 { if let delta = try stream.accept(byte) { visible += delta } }
        let (result, last) = try stream.finish(); visible += last ?? ""
        XCTAssertEqual(visible, "Café 日本語 🧑🏽‍💻"); XCTAssertEqual(result.text, visible); XCTAssertEqual(result.reasoning, "Private reasoning"); XCTAssertEqual(result.finishReason, "stop")
    }
    func testTruncatedMalformedAndToolStreamsDoNotReportACompletedTextReply() throws {
        let first = "data: {\"choices\":[{\"delta\":{\"content\":\"Retained partial\"}}]}\n\n"
        var truncated = MacChatStream(), visible = ""
        for byte in first.utf8 { if let delta = try truncated.accept(byte) { visible += delta } }
        XCTAssertEqual(visible, "Retained partial"); XCTAssertThrowsError(try truncated.finish())
        for suffix in ["data: {\"error\":{\"message\":\"Denied\"}}\n\n", "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0}]},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n", "data: invalid-json\n\n"] {
            var stream = MacChatStream()
            XCTAssertThrowsError(try { for byte in (first + suffix).utf8 { _ = try stream.accept(byte) }; _ = try stream.finish() }())
        }
        var invalid = MacChatStream(); _ = try invalid.accept(0xff); XCTAssertThrowsError(try invalid.accept(10))
        var empty = MacChatStream(); for byte in "data: [DONE]\n\n".utf8 { _ = try empty.accept(byte) }; XCTAssertThrowsError(try empty.finish())
    }
    func testAnthropicBlocksHandleUnicodeReasoningUnknownEventsAndStrictCompletion() throws {
        func event(_ value: [String: Any]) throws -> String { "event: ignored-name\r\ndata: " + String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) + "\r\n\r\n" }
        let start = try event(["type": "message_start", "message": ["role": "assistant", "content": []]])
        let textStart = try event(["type": "content_block_start", "index": 1, "content_block": ["type": "text", "text": "Café "]])
        let textDelta = try event(["type": "content_block_delta", "index": 1, "delta": ["type": "text_delta", "text": "日本語 🧑🏽‍💻"]])
        let textStop = try event(["type": "content_block_stop", "index": 1])
        let finish = try event(["type": "message_delta", "delta": ["stop_reason": "end_turn"]]) + event(["type": "message_stop"])
        let thinking = try event(["type": "content_block_start", "index": 0, "content_block": ["type": "thinking", "thinking": ""]]) + event(["type": "content_block_delta", "index": 0, "delta": ["type": "thinking_delta", "thinking": "Separate reasoning"]]) + event(["type": "content_block_delta", "index": 0, "delta": ["type": "signature_delta", "signature": "signature"]]) + event(["type": "content_block_stop", "index": 0])
        var stream = MacAnthropicStream(), visible = ""
        for byte in (": ping\r\n\r\n" + start + thinking + (try event(["type": "future_event"])) + textStart + textDelta + textStop + finish).utf8 { if let delta = try stream.accept(byte) { visible += delta } }
        let (reply, last) = try stream.finish(); visible += last ?? ""
        XCTAssertEqual(visible, "Café 日本語 🧑🏽‍💻"); XCTAssertEqual(reply.text, visible); XCTAssertEqual(reply.reasoning, "Separate reasoning"); XCTAssertEqual(reply.finishReason, "end_turn")
        let tool = try event(["type": "content_block_start", "index": 2, "content_block": ["type": "tool_use", "id": "tool", "name": "unrequested"]]) + event(["type": "content_block_stop", "index": 2])
        let failure = try event(["type": "error", "error": ["type": "overloaded_error"]])
        let limit = try event(["type": "message_delta", "delta": ["stop_reason": "max_tokens"]]) + event(["type": "message_stop"])
        for suffix in ["", textStop, textStop + failure, textStop + limit, textStop + tool + finish, textStop + "data: invalid-json\n\n"] {
            var partial = MacAnthropicStream(), kept = ""
            XCTAssertThrowsError(try { for byte in (start + textStart + textDelta + suffix).utf8 { if let delta = try partial.accept(byte) { kept += delta } }; _ = try partial.finish() }())
            XCTAssertEqual(kept, "Café 日本語 🧑🏽‍💻")
        }
        var invalid = MacAnthropicStream(); XCTAssertThrowsError(try { for byte in textDelta.utf8 { _ = try invalid.accept(byte) } }())
    }

}
