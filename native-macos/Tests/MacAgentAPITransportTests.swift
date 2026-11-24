import XCTest
@testable import Zerus_Native

@MainActor final class MacAgentAPITransportTests: XCTestCase {
    func testCompatibleToolCallsAndResultsRoundTripThroughStreamingAndJSON() async throws {
        for streaming in [true, false] {
            try await withRun(image: true) { root, io, record, attachments, client, endpoint in
                var record = record
                let prepared = try await MacAgentRequest.prepare(record.run, store: attachments)
                let firstCall = ["id": "read-alpha", "type": "function", "function": ["name": "note_get", "arguments": "{\"selector\":\"alpha\"}"]] as [String: Any]
                let secondCall = ["id": "find-alpha", "type": "function", "function": ["name": "search", "arguments": "{\"query\":\"evidence\"}"]] as [String: Any]
                let json = try self.json(["choices": [["message": ["content": NSNull(), "tool_calls": [firstCall, secondCall]], "finish_reason": "tool_calls"]], "usage": ["prompt_tokens": 300, "completion_tokens": 20]])
                let wire = try self.event(["choices": [["index": 0, "delta": ["tool_calls": [["index": 0, "id": "read-alpha", "type": "function", "function": ["name": "note_get", "arguments": "{\"selector\":"]], ["index": 1, "id": "find-alpha", "type": "function", "function": ["name": "search", "arguments": "{\"query\":\"evi"]]]]]]])
                    + self.event(["choices": [["index": 0, "delta": ["tool_calls": [["index": 1, "function": ["arguments": "dence\"}"]], ["index": 0, "function": ["name": "note_get", "arguments": "\"alpha\"}"]]]], "finish_reason": "tool_calls"]]])
                    + self.event(["choices": [], "usage": ["prompt_tokens": 300, "completion_tokens": 20]]) + "data: [DONE]\n\n"
                let route = URL(string: endpoint)!.path
                ChatHTTPFixture.register(.init(first: streaming ? wire : json, remaining: [], contentType: streaming ? "text/event-stream" : "application/json"), path: route)
                let reply = try await client.streamCompatibleAgent(endpoint: endpoint, model: "fixture-agent", apiKey: "synthetic-key", request: prepared) { _ in XCTFail("A tool-only response must not manufacture text") }
                XCTAssertEqual(reply.calls.map(\.name), ["note_get", "search"]); XCTAssertEqual(reply.calls.map(\.id), ["read-alpha", "find-alpha"])
                XCTAssertEqual(reply.inputTokens, 300); XCTAssertEqual(reply.outputTokens, 20)
                let first = try XCTUnwrap(ChatHTTPFixture.captured(route)), body = try self.object(self.body(first))
                XCTAssertEqual(first.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
                XCTAssertEqual(body["max_tokens"] as? Int, prepared.outputLimit)
                let firstMessages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                let parts = firstMessages.compactMap { $0["content"] as? [[String: Any]] }.flatMap { $0 }
                let image = try XCTUnwrap(record.run.attachments?.first)
                let imageURL = "data:image/jpeg;base64," + (try attachments.read(image)).base64EncodedString()
                XCTAssertTrue(parts.contains { ($0["image_url"] as? [String: String])?["url"] == imageURL })
                XCTAssertEqual((body["stream_options"] as? [String: Bool])?["include_usage"], true)
                let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
                XCTAssertTrue(tools.contains { ($0["function"] as? [String: Any])?["name"] as? String == "note_get" })
                XCTAssertFalse(tools.contains { ($0["function"] as? [String: Any])?["name"] as? String == "note_append" })
                record = try await io.agentResponse(record, owner: "fixture-owner", content: reply.content, calls: reply.calls, input: XCTUnwrap(reply.inputTokens), output: XCTUnwrap(reply.outputTokens), seconds: 0)
                for call in reply.calls { record = try await io.agentTool(record, owner: "fixture-owner", call: call) }
                let next = try await MacAgentRequest.prepare(record.run, store: attachments)
                let finalJSON = try self.json(["choices": [["message": ["content": "Found 日本語 evidence."], "finish_reason": "stop"]]])
                ChatHTTPFixture.register(.init(first: finalJSON, remaining: [], contentType: "application/json"), path: route)
                var visible = ""
                let final = try await client.streamCompatibleAgent(endpoint: endpoint, model: "fixture-agent", apiKey: "synthetic-key", request: next) { visible += $0 }
                XCTAssertEqual(final.content, "Found 日本語 evidence."); XCTAssertEqual(visible, final.content); XCTAssertTrue(final.calls.isEmpty)
                XCTAssertNil(final.inputTokens, "Missing usage must remain distinguishable from zero")
                let second = try self.object(self.body(XCTUnwrap(ChatHTTPFixture.captured(route))))
                let messages = try XCTUnwrap(second["messages"] as? [[String: Any]])
                let results = messages.filter { $0["role"] as? String == "tool" }
                XCTAssertEqual(Set(results.compactMap { $0["tool_call_id"] as? String }), ["read-alpha", "find-alpha"])
                XCTAssertTrue(results.contains { ($0["content"] as? String)?.contains("Scoped evidence.") == true })
                let assistant = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
                XCTAssertEqual((assistant["tool_calls"] as? [[String: Any]])?.count, 2)
                XCTAssertFalse(String(decoding: record.bytes, as: UTF8.self).contains("synthetic-key"))
            }
        }
    }
    func testCancelledCompatibleAgentStreamStopsTransportWithoutReturningPartialCalls() async throws {
        try await withRun { root, io, initial, attachments, client, endpoint in
            let request = try await MacAgentRequest.prepare(initial.run, store: attachments)
            let visible = expectation(description: "partial text visible"), stopped = expectation(description: "transport cancelled")
            let first = try self.event(["choices": [["delta": ["content": "Retained café", "tool_calls": [["index": 0, "id": "partial", "function": ["name": "note_get", "arguments": "{"]]]]]]])
            ChatHTTPFixture.register(.init(first: first, remaining: [], paused: true, onStop: { stopped.fulfill() }), path: URL(string: endpoint)!.path)
            let task = Task { try await client.streamCompatibleAgent(endpoint: endpoint, model: "fixture-agent", apiKey: "synthetic-key", request: request) { text in if text == "Retained café" { visible.fulfill() } } }
            await fulfillment(of: [visible], timeout: 5); task.cancel()
            do { _ = try await task.value; XCTFail("Partial calls cannot complete after cancellation") } catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
            await fulfillment(of: [stopped], timeout: 5)
        }
    }
    func testMalformedOrTruncatedCompatibleCallsNeverProduceAnExecutableCompletion() async throws {
        try await withRun { _, _, record, attachments, client, endpoint in
            let request = try await MacAgentRequest.prepare(record.run, store: attachments), route = URL(string: endpoint)!.path
            let call: [String: Any] = ["id": "read", "type": "function", "function": ["name": "note_get", "arguments": "{}"]]
            let malformed: [(String, String, String)] = [
                (try self.json(["choices": [["index": 1, "message": ["tool_calls": [call]], "finish_reason": "tool_calls"]]]), "application/json", "API returned incomplete or unsupported agent calls"),
                (try self.event(["choices": [["delta": ["content": "answer", "tool_calls": "malformed"], "finish_reason": "stop"]]]) + "data: [DONE]\n\n", "text/event-stream", "API returned incomplete or unsupported agent calls"),
                (try self.event(["choices": [["delta": ["tool_calls": [["index": 0, "id": "read", "function": ["name": "note_get", "arguments": "{}"]]]]]]]), "text/event-stream", "API returned incomplete or unsupported agent calls"),
                (try self.json(["choices": [["message": ["tool_calls": [call]], "finish_reason": "length"]]]), "application/json", "API reached its reply or context limit"),
                (try self.json(["choices": [["message": ["tool_calls": [call, call]], "finish_reason": "tool_calls"]]]), "application/json", "provider returned unsupported agent calls or usage"),
                (try self.json(["choices": [["message": ["tool_calls": [["id": "read", "function": ["name": "note_get", "arguments": "[]"]]]], "finish_reason": "tool_calls"]]]), "application/json", "provider returned unsupported agent calls or usage"),
                (try self.json(["choices": [["message": ["content": "answer"], "finish_reason": "stop"]], "usage": ["prompt_tokens": -1]]), "application/json", "provider returned unsupported agent calls or usage")
            ]
            for (wire, type, expected) in malformed {
                ChatHTTPFixture.remove(route)
                ChatHTTPFixture.register(.init(first: wire, remaining: [], contentType: type), path: route)
                do { _ = try await client.streamCompatibleAgent(endpoint: endpoint, model: "fixture-agent", apiKey: "synthetic-key", request: request) { _ in }; XCTFail("Malformed/truncated calls must not be returned to the runtime") } catch { XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription) }
                XCTAssertNotNil(ChatHTTPFixture.captured(route), "The negative case must reach the HTTP reply parser")
            }
        }
    }
    func testCompatibleOptionalNullFieldsAndUnindexedSingleCallRemainUsable() async throws {
        try await withRun { _, _, record, attachments, client, endpoint in
            let request = try await MacAgentRequest.prepare(record.run, store: attachments)
            let wire = try self.event(["choices": [["delta": ["role": NSNull(), "tool_calls": [["id": "list", "function": ["name": "note_list", "arguments": ""]]]]]]])
                + self.event(["choices": [["delta": [:], "finish_reason": "tool_calls"]]])
                + self.event(["usage": ["prompt_tokens": NSNull(), "completion_tokens": 4]]) + "data: [DONE]\n\n"
            ChatHTTPFixture.register(.init(first: wire, remaining: []), path: URL(string: endpoint)!.path)
            let reply = try await client.streamCompatibleAgent(endpoint: endpoint, model: "fixture-agent", apiKey: "synthetic-key", request: request) { _ in }
            XCTAssertEqual(reply.calls.map(\.name), ["note_list"]); XCTAssertEqual(reply.calls.first?.arguments, "{}")
            XCTAssertNil(reply.inputTokens); XCTAssertEqual(reply.outputTokens, 4)
        }
    }
    func testAnthropicSignedThinkingAndGroupedToolResultsSurviveContinuation() async throws {
        for streaming in [true, false] {
            try await withRun(image: true) { root, io, initial, attachments, client, endpoint in
                var record = initial
                let cache = MacAnthropicContinuations(directory: root.appendingPathComponent("PrivateContinuations"))
                let request = try await MacAgentRequest.prepare(record.run, store: attachments), route = URL(string: endpoint)!.path
                let blocks: [[String: Any]] = [
                    ["type": "thinking", "thinking": "Private provider reasoning.", "signature": "signed-thinking-fixture"],
                    ["type": "redacted_thinking", "data": "opaque-redacted-fixture"],
                    ["type": "text", "text": "Read café 日本語."],
                    ["type": "tool_use", "id": "read", "name": "note_get", "input": ["selector": "alpha"]],
                    ["type": "tool_use", "id": "find", "name": "search", "input": ["query": "evidence"]]
                ]
                let usage = ["input_tokens": 10, "cache_read_input_tokens": 20, "cache_creation_input_tokens": 30, "output_tokens": 4]
                let json = try self.json(["type": "message", "role": "assistant", "content": blocks, "stop_reason": "tool_use", "usage": usage])
                var wire = try self.event(["type": "message_start", "message": ["role": "assistant", "content": [], "usage": ["input_tokens": 10, "cache_read_input_tokens": 20, "cache_creation_input_tokens": 30, "output_tokens": 1]]])
                for (index, block) in blocks.enumerated() {
                    let kind = block["type"] as! String
                    var start = block
                    if kind == "tool_use" { start["input"] = [:] as [String: Any] }
                    if kind == "text" { start["text"] = "" }
                    if kind == "thinking" { start["thinking"] = ""; start["signature"] = "" }
                    wire += try self.event(["type": "content_block_start", "index": index, "content_block": start])
                    if kind == "tool_use" {
                        let arguments = try self.json(block["input"] as! [String: Any]), middle = arguments.index(arguments.startIndex, offsetBy: arguments.count / 2)
                        for partial in [String(arguments[..<middle]), String(arguments[middle...])] { wire += try self.event(["type": "content_block_delta", "index": index, "delta": ["type": "input_json_delta", "partial_json": partial]]) }
                    }
                    if kind == "text" { wire += try self.event(["type": "content_block_delta", "index": index, "delta": ["type": "text_delta", "text": block["text"]!]]) }
                    if kind == "thinking" {
                        wire += try self.event(["type": "content_block_delta", "index": index, "delta": ["type": "thinking_delta", "thinking": block["thinking"]!]])
                        wire += try self.event(["type": "content_block_delta", "index": index, "delta": ["type": "signature_delta", "signature": block["signature"]!]])
                    }
                    wire += try self.event(["type": "content_block_stop", "index": index])
                }
                wire += try self.event(["type": "ping"]) + self.event(["type": "future_event"]) + self.event(["type": "message_delta", "delta": ["stop_reason": "tool_use"], "usage": ["output_tokens": 4]]) + self.event(["type": "message_stop"])
                ChatHTTPFixture.register(.init(first: streaming ? wire : json, remaining: [], contentType: streaming ? "text/event-stream" : "application/json"), path: route)
                var visible = ""
                let reply = try await client.streamAnthropicAgent(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", request: request, continuations: cache) { visible += $0 }
                XCTAssertEqual(visible, "Read café 日本語."); XCTAssertEqual(reply.reasoning, "Private provider reasoning.")
                XCTAssertEqual(reply.calls.map(\.id), ["read", "find"]); XCTAssertEqual(reply.inputTokens, 60); XCTAssertEqual(reply.outputTokens, 4, "Cumulative usage replaces earlier usage")
                let captured = try XCTUnwrap(ChatHTTPFixture.captured(route)), firstBody = try self.object(self.body(captured))
                XCTAssertEqual(captured.value(forHTTPHeaderField: "x-api-key"), "synthetic-key"); XCTAssertNil(captured.value(forHTTPHeaderField: "Authorization"))
                XCTAssertEqual(captured.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
                XCTAssertEqual(firstBody["max_tokens"] as? Int, request.outputLimit)
                XCTAssertEqual((firstBody["output_config"] as? [String: String])?["effort"], "medium")
                let userParts = (firstBody["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
                XCTAssertTrue(userParts?.contains { ($0["source"] as? [String: String])?["media_type"] == "image/jpeg" } == true)
                record = try await io.agentResponse(record, owner: "fixture-owner", content: reply.content, calls: reply.calls, input: XCTUnwrap(reply.inputTokens), output: XCTUnwrap(reply.outputTokens), seconds: 0)
                for call in reply.calls { record = try await io.agentTool(record, owner: "fixture-owner", call: call) }
                let next = try await MacAgentRequest.prepare(record.run, store: attachments)
                ChatHTTPFixture.remove(route)
                for (model, key) in [("other-model", "synthetic-key"), ("claude-fixture", "other-key")] {
                    do { _ = try await client.streamAnthropicAgent(endpoint: endpoint, model: model, apiKey: key, request: next, continuations: cache) { _ in }; XCTFail("A different connection/model cannot reuse signed continuation state") }
                    catch { XCTAssertTrue(error.localizedDescription.contains("original Anthropic continuation"), error.localizedDescription) }
                    XCTAssertNil(ChatHTTPFixture.captured(route))
                }
                let bound = cache.bound(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", run: record.id)
                let saved = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: bound.directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent != "binding.json" })
                let bytes = try Data(contentsOf: saved)
                try Data("unreadable continuation".utf8).write(to: saved)
                do { _ = try await client.streamAnthropicAgent(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", request: next, continuations: cache) { _ in }; XCTFail("An unreadable private continuation must not be reconstructed without signed thinking") }
                catch { XCTAssertTrue(error.localizedDescription.contains("original Anthropic continuation"), error.localizedDescription) }
                XCTAssertNil(ChatHTTPFixture.captured(route)); XCTAssertEqual(try Data(contentsOf: saved), Data("unreadable continuation".utf8))
                try bytes.write(to: saved)
                let answer = try self.json(["type": "message", "role": "assistant", "content": [["type": "text", "text": "Found scoped evidence."]], "stop_reason": "end_turn"])
                ChatHTTPFixture.register(.init(first: answer, remaining: [], contentType: "application/json"), path: route)
                let final = try await client.streamAnthropicAgent(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", request: next, continuations: cache) { _ in }
                XCTAssertEqual(final.content, "Found scoped evidence."); XCTAssertTrue(final.calls.isEmpty); XCTAssertNil(final.inputTokens)
                let secondBody = try self.object(self.body(XCTUnwrap(ChatHTTPFixture.captured(route))))
                let messages = try XCTUnwrap(secondBody["messages"] as? [[String: Any]])
                let restored = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" }?["content"] as? [[String: Any]])
                XCTAssertTrue(restored.contains { $0["signature"] as? String == "signed-thinking-fixture" }); XCTAssertTrue(restored.contains { $0["data"] as? String == "opaque-redacted-fixture" })
                let results = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
                XCTAssertEqual(Set(results.compactMap { $0["tool_use_id"] as? String }), ["read", "find"])
                XCTAssertTrue(results.allSatisfy { $0["type"] as? String == "tool_result" })
                XCTAssertTrue(results.contains { ($0["content"] as? String)?.contains("Scoped evidence.") == true })
            }
        }
    }
    func testAnthropicMalformedAndTruncatedBlocksDoNotReturnToolCalls() async throws {
        try await withRun { root, _, record, attachments, client, endpoint in
            let request = try await MacAgentRequest.prepare(record.run, store: attachments), route = URL(string: endpoint)!.path
            let cache = MacAnthropicContinuations(directory: root.appendingPathComponent("PrivateContinuations"))
            let tool: [String: Any] = ["type": "tool_use", "id": "read", "name": "note_get", "input": [:]]
            let cases: [(String, String)] = [
                (try self.event(["type": "message_start", "message": ["role": "assistant", "content": []]]) + self.event(["type": "content_block_start", "index": 0, "content_block": tool]), "text/event-stream"),
                (try self.json(["type": "message", "role": "assistant", "content": [tool], "stop_reason": "max_tokens"]), "application/json"),
                (try self.json(["type": "message", "role": "assistant", "content": [["type": "thinking", "thinking": "unsigned"], tool], "stop_reason": "tool_use"]), "application/json"),
                (try self.json(["type": "message", "role": "assistant", "content": [["type": "server_tool_use", "id": "server", "name": "unrequested", "input": [:]]], "stop_reason": "tool_use"]), "application/json"),
                (try self.json(["type": "message", "role": "assistant", "content": [["type": "tool_use", "id": "read", "name": "note_get", "input": []]], "stop_reason": "tool_use"]), "application/json")
            ]
            for (wire, type) in cases {
                ChatHTTPFixture.remove(route); ChatHTTPFixture.register(.init(first: wire, remaining: [], contentType: type), path: route)
                do { _ = try await client.streamAnthropicAgent(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", request: request, continuations: cache) { _ in }; XCTFail("Malformed Anthropic blocks cannot become executable calls") }
                catch { XCTAssertTrue(error.localizedDescription.contains(wire.contains("max_tokens") ? "Anthropic reached its reply or context limit" : "Anthropic returned incomplete or unsupported agent blocks"), error.localizedDescription) }
                XCTAssertNotNil(ChatHTTPFixture.captured(route))
            }
        }
    }
    func testCancelledAnthropicStreamDoesNotSaveAPartialContinuation() async throws {
        try await withRun { root, _, record, attachments, client, endpoint in
            let request = try await MacAgentRequest.prepare(record.run, store: attachments)
            let cache = MacAnthropicContinuations(directory: root.appendingPathComponent("PrivateContinuations"))
            let visible = expectation(description: "Anthropic partial visible"), stopped = expectation(description: "Anthropic transport cancelled")
            let first = try self.event(["type": "message_start", "message": ["role": "assistant", "content": []]])
                + self.event(["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]])
                + self.event(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "Retained café"]])
                + self.event(["type": "content_block_stop", "index": 0])
                + self.event(["type": "content_block_start", "index": 1, "content_block": ["type": "tool_use", "id": "partial", "name": "note_get", "input": [:]]])
            ChatHTTPFixture.register(.init(first: first, remaining: [], paused: true, onStop: { stopped.fulfill() }), path: URL(string: endpoint)!.path)
            let task = Task { try await client.streamAnthropicAgent(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", request: request, continuations: cache) { text in if text == "Retained café" { visible.fulfill() } } }
            await fulfillment(of: [visible], timeout: 5); task.cancel()
            do { _ = try await task.value; XCTFail("An incomplete Anthropic response cannot return partial calls") }
            catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
            await fulfillment(of: [stopped], timeout: 5)
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.directory.path), "Only complete provider responses may be saved for continuation")
        }
    }
    func testAnthropicRefusalNeverReturnsOrCachesPartialOutput() async throws {
        for text in ["", "Partial answer the classifier stopped"] {
            try await withRun { root, _, record, attachments, client, endpoint in
                let request = try await MacAgentRequest.prepare(record.run, store: attachments)
                let cache = MacAnthropicContinuations(directory: root.appendingPathComponent("PrivateContinuations"))
                let wire = try self.event(["type": "message_start", "message": ["role": "assistant", "content": []]])
                    + self.event(["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": text]])
                    + self.event(["type": "content_block_stop", "index": 0])
                    + self.event(["type": "message_delta", "delta": ["stop_reason": "refusal"]]) + self.event(["type": "message_stop"])
                let route = URL(string: endpoint)!.path
                ChatHTTPFixture.register(.init(first: wire, remaining: []), path: route)
                do { _ = try await client.streamAnthropicAgent(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", request: request, continuations: cache) { _ in }; XCTFail("A refusal cannot return the partial output as an answer") }
                catch { XCTAssertTrue(error.localizedDescription.contains("refused"), error.localizedDescription) }
                XCTAssertNotNil(ChatHTTPFixture.captured(route))
                let bound = cache.bound(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", run: record.id)
                let files = (try? FileManager.default.contentsOfDirectory(at: bound.directory, includingPropertiesForKeys: nil)) ?? []
                XCTAssertFalse(files.contains { $0.lastPathComponent != "system.json" && $0.lastPathComponent != "binding.json" }, "Refused blocks cannot be saved for a subsequent turn")
            }
        }
    }
    func testAnthropicNullableDeltaUsagePreservesPreviouslyReportedCounts() async throws {
        try await withRun { root, _, record, attachments, client, endpoint in
            let request = try await MacAgentRequest.prepare(record.run, store: attachments)
            let wire = try self.event(["type": "message_start", "message": ["role": "assistant", "content": [], "usage": ["input_tokens": 10, "cache_read_input_tokens": NSNull(), "cache_creation_input_tokens": 5, "output_tokens": 1]]])
                + self.event(["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": "Answer"]])
                + self.event(["type": "content_block_stop", "index": 0])
                + self.event(["type": "message_delta", "delta": ["stop_reason": "end_turn"], "usage": ["input_tokens": NSNull(), "cache_creation_input_tokens": NSNull(), "output_tokens": 4]]) + self.event(["type": "message_stop"])
            ChatHTTPFixture.register(.init(first: wire, remaining: []), path: URL(string: endpoint)!.path)
            let reply = try await client.streamAnthropicAgent(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", request: request, continuations: .init(directory: root.appendingPathComponent("PrivateContinuations"))) { _ in }
            XCTAssertEqual(reply.inputTokens, 15); XCTAssertEqual(reply.outputTokens, 4)
        }
    }
    func testAnthropicSystemStaysFrozenAfterAnEditRunCreatesANote() async throws {
        try await withRun { root, io, _, attachments, client, endpoint in
            var record = try await io.agentStart(objective: "Create a note", mode: .edit, scope: .init(paths: ["Alpha.md"], createFolder: ""), chatID: "create-fixture", owner: "fixture-owner")
            let cache = MacAnthropicContinuations(directory: root.appendingPathComponent("PrivateContinuations")), route = URL(string: endpoint)!.path
            let request = try await MacAgentRequest.prepare(record.run, store: attachments)
            let json = try self.json(["type": "message", "role": "assistant", "content": [["type": "thinking", "thinking": "Create the requested note.", "signature": "creation-signature"], ["type": "tool_use", "id": "create", "name": "note_create", "input": ["title": "Created", "body": "New writing.", "folder": ""]]], "stop_reason": "tool_use"])
            ChatHTTPFixture.register(.init(first: json, remaining: [], contentType: "application/json"), path: route)
            let reply = try await client.streamAnthropicAgent(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", request: request, continuations: cache) { _ in }
            let before = try self.object(self.body(XCTUnwrap(ChatHTTPFixture.captured(route))))
            record = try await io.agentResponse(record, owner: "fixture-owner", content: reply.content, calls: reply.calls, input: 100, output: 10, seconds: 0)
            record = try await io.agentTool(record, owner: "fixture-owner", call: XCTUnwrap(reply.calls.first))
            let review = try await io.agentReview(record, owner: "fixture-owner", ids: Set(record.run.pending.map(\.id)), automatic: true)
            record = try await io.agentApply(review, owner: "fixture-owner").0
            XCTAssertEqual(record.run.writeIDs.count, 2, "The real native create receipt must extend run permissions")
            let next = try await MacAgentRequest.prepare(record.run, store: attachments)
            let answer = try self.json(["type": "message", "role": "assistant", "content": [["type": "text", "text": "Created."]], "stop_reason": "end_turn"])
            ChatHTTPFixture.register(.init(first: answer, remaining: [], contentType: "application/json"), path: route)
            _ = try await client.streamAnthropicAgent(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", request: next, continuations: cache) { _ in }
            let after = try self.object(self.body(XCTUnwrap(ChatHTTPFixture.captured(route))))
            XCTAssertEqual(after["system"] as? String, before["system"] as? String, "Thinking history must use the original top-level system prompt")
        }
    }
    func testAnthropicCacheCleanupRetainsLiveRunsAndRemovesOnlyTheChosenRun() async throws {
        try await withRun { root, io, first, attachments, client, endpoint in
            let cache = MacAnthropicContinuations(directory: root.appendingPathComponent("PrivateContinuations")), route = URL(string: endpoint)!.path
            let second = try await io.agentStart(objective: "Another answer", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "second-cache", owner: "fixture-owner")
            var folders: [UUID: URL] = [:]
            for record in [first, second] {
                let request = try await MacAgentRequest.prepare(record.run, store: attachments)
                let json = try self.json(["type": "message", "role": "assistant", "content": [["type": "text", "text": "Answer."]], "stop_reason": "end_turn"])
                ChatHTTPFixture.register(.init(first: json, remaining: [], contentType: "application/json"), path: route)
                _ = try await client.streamAnthropicAgent(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", request: request, continuations: cache) { _ in }
                let folder = cache.bound(endpoint: endpoint, model: "claude-fixture", apiKey: "synthetic-key", run: record.id).directory
                folders[record.id] = folder
                let permissions = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber
                XCTAssertEqual(permissions?.intValue, 0o700)
                for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) { XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600) }
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: folder.path)
            }
            try cache.prune(retaining: [first.id])
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(folders[first.id]).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(folders[second.id]).path))
            try cache.remove(run: first.id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(folders[first.id]).path))
        }
    }
    private let original = "---\nzerus-id: alpha\n---\n# Alpha\n\nScoped evidence.\n"
    private func withRun(image: Bool = false, _ operation: (URL, VaultFiles, NativeAgentRecord, NativeChatAttachmentStore, MacAIClient, String) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zerus-agent-api-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(original.utf8).write(to: root.appendingPathComponent("Alpha.md"))
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ChatHTTPFixture.self]
        let session = URLSession(configuration: configuration), endpoint = "https://fixture.invalid/" + UUID().uuidString + "/chat/completions"
        defer { session.invalidateAndCancel(); ChatHTTPFixture.remove(URL(string: endpoint)!.path); try? FileManager.default.removeItem(at: root) }
        let io = VaultFiles(root: root), attachments = NativeChatAttachmentStore(directory: root.appendingPathComponent("PrivateAttachments"))
        let items = image ? try await attachments.commit([NativePreparedChatAttachment.prepare(makeChatTestImage(in: root).bytes, name: "Evidence.jpg")]) : []
        let record = try await io.agentStart(objective: "Read Alpha", mode: .ask, scope: .init(paths: ["Alpha.md"]), chatID: "api-fixture", owner: "fixture-owner", attachments: items, imageIDs: items.map { $0.id.uuidString.lowercased() })
        if !items.isEmpty { try attachments.authorize(run: record.id, chat: record.run.chatID, items: items) }
        try await operation(root, io, record, attachments, MacAIClient(session: session), endpoint)
    }
    private func json(_ value: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
    private func event(_ value: [String: Any]) throws -> String { "data: " + (try json(value)) + "\n\n" }
    private func object(_ data: Data) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
    private func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
        return data
    }
}
