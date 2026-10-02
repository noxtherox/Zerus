import XCTest
import CryptoKit
import Security
@testable import ZerusChatGPTCore

final class ChatGPTProtocolTests: XCTestCase {
  func testAccountCatalogRequestAdvertisesTheVerifiedCompatibilityVersion() throws {
    // The public account endpoint returned the legacy catalog without this query,
    // even with cache bypass. Versioned discovery exposes GPT-6 Sol/Luna and 6.1 Sol.
    let request = ChatGPTModelCatalog.request(accessToken: "test-account-token")
    XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models?client_version=0.159.2")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-account-token")
  }

  func testRestoringTheChatGPTConnectionDoesNotFallBackToAnAPIKeyProvider() throws {
    let fallback = "https://openrouter.ai/api/v1"
    XCTAssertEqual(CloudAIEndpoint.restored("codex://chatgpt", fallback: fallback), "codex://chatgpt")
    XCTAssertEqual(CloudAIEndpoint.restored(" https://ai.example.test/v1/ ", fallback: fallback), "https://ai.example.test/v1")
    XCTAssertEqual(CloudAIEndpoint.restored(nil, fallback: fallback), fallback)
    XCTAssertEqual(CloudAIEndpoint.restored("http://ai.example.test/v1", fallback: fallback), fallback)
    XCTAssertThrowsError(try CloudAIEndpoint.normalizedHTTP("codex://chatgpt"), "The native marker must never become a bearer-token HTTP destination.")
  }

  func testAuthorizationRejectsUnsolicitedOrAmbiguousCallbacksAndKeepsTheIssuedClient() throws {
    let redirect = URL(string: "http://127.0.0.1:1455/auth/callback")!
    let transaction = try ChatGPTAuthorization(redirectURI: redirect, registration: nil)
    func callback(_ query: String, path: String = "/auth/callback", host: String = "127.0.0.1") -> URL {
      URL(string: "http://\(host):1455\(path)?\(query)")!
    }
    let valid = "code=one-time-code&state=\(transaction.state)&client_id=oaiapp_demo"
    XCTAssertEqual(try transaction.callback(callback(valid)).clientID, "oaiapp_demo")
    for bad in [
      callback("code=x&state=unrelated&client_id=oaiapp_demo"),
      callback(valid + "&state=another"),
      callback("code=x&state=\(transaction.state)"),
      callback(valid, path: "/callback"),
      callback(valid, host: "localhost"),
      callback("error=access_denied&state=\(transaction.state)"),
      callback(valid.replacingOccurrences(of: "oaiapp_demo", with: "dynamic_agent_client")),
    ] { XCTAssertThrowsError(try transaction.callback(bad)) }
    let saved = ChatGPTRegistration(clientID: "oaiapp_demo", subject: "user", email: "user@example.test")
    let returning = try ChatGPTAuthorization(redirectURI: redirect, registration: saved)
    XCTAssertEqual(try returning.callback(callback("code=new-code&state=\(returning.state)")).clientID, saved.clientID)
    XCTAssertThrowsError(try returning.callback(callback("code=new-code&state=\(returning.state)&client_id=oaiapp_other")))
  }

  func testSignedIdentityRejectsWrongAudienceNonceExpiryAndModifiedSignature() throws {
    let key = P256.Signing.PrivateKey()
    let point = key.publicKey.x963Representation
    let jwks: [String: Any] = ["keys": [["kid": "test", "kty": "EC", "crv": "P-256", "alg": "ES256", "x": point.subdata(in: 1..<33).base64URL, "y": point.subdata(in: 33..<65).base64URL]]]
    let now = Date()
    let valid: [String: Any] = ["iss": "https://auth.openai.com", "aud": "oaiapp_demo", "sub": "verified-account", "nonce": "original", "exp": now.timeIntervalSince1970 + 300, "iat": now.timeIntervalSince1970 - 10]
    func token(_ claims: [String: Any]) throws -> String {
      let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": "test"]).base64URL
      let body = try JSONSerialization.data(withJSONObject: claims).base64URL
      let unsigned = "\(header).\(body)"
      return unsigned + "." + (try key.signature(for: Data(unsigned.utf8))).rawRepresentation.base64URL
    }
    XCTAssertEqual(try ChatGPTIdentity.verify(token(valid), jwks: jwks, clientID: "oaiapp_demo", nonce: "original", now: now).subject, "verified-account")
    for (claim, value) in [("aud", "oaiapp_other" as Any), ("nonce", "different"), ("iss", "https://example.test"), ("exp", now.timeIntervalSince1970 - 1), ("azp", "oaiapp_other")] {
      var invalid = valid; invalid[claim] = value
      XCTAssertThrowsError(try ChatGPTIdentity.verify(token(invalid), jwks: jwks, clientID: "oaiapp_demo", nonce: "original", now: now))
    }
    let signed = try token(valid)
    let components = signed.split(separator: ".")
    let forged = "\(components[0]).\(components[1]).\(Data(repeating: 0, count: 64).base64URL)"
    XCTAssertThrowsError(try ChatGPTIdentity.verify(forged, jwks: jwks, clientID: "oaiapp_demo", nonce: "original", now: now))
  }

  func testRS256IdentityUsesThePublishedRSAPublicKey() throws {
    let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
    let privateKey = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
    let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
    let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil)) as Data
    var position = 0
    func element() throws -> Data {
      _ = der[position]; position += 1
      let first = der[position]; position += 1
      var length = Int(first)
      if first & 0x80 != 0 {
        length = 0
        for _ in 0..<Int(first & 0x7f) { length = length * 256 + Int(der[position]); position += 1 }
      }
      let bytes = der.subdata(in: position..<(position + length))
      position += length
      return bytes
    }
    _ = try element()
    // Decode the sequence header again, then its two PKCS#1 INTEGERs.
    position = 1
    let sequenceLength = der[position]; position += 1
    if sequenceLength & 0x80 != 0 { position += Int(sequenceLength & 0x7f) }
    var modulus = try element()
    if modulus.first == 0 { modulus.removeFirst() }
    let exponent = try element()
    let jwks: [String: Any] = ["keys": [["kid": "rsa-test", "kty": "RSA", "alg": "RS256", "n": modulus.base64URL, "e": exponent.base64URL]]]
    let now = Date()
    let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": "rsa-test"]).base64URL
    let payload = try JSONSerialization.data(withJSONObject: ["iss": "https://auth.openai.com", "aud": "oaiapp_demo", "sub": "rsa-account", "nonce": "original", "exp": now.timeIntervalSince1970 + 300, "iat": now.timeIntervalSince1970]).base64URL
    let unsigned = Data("\(header).\(payload)".utf8)
    let signature = try XCTUnwrap(SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, unsigned as CFData, nil)) as Data
    let token = String(decoding: unsigned, as: UTF8.self) + "." + signature.base64URL
    XCTAssertEqual(try ChatGPTIdentity.verify(token, jwks: jwks, clientID: "oaiapp_demo", nonce: "original", now: now).subject, "rsa-account")
    let bad = String(decoding: unsigned, as: UTF8.self) + "." + Data(repeating: 0, count: signature.count).base64URL
    XCTAssertThrowsError(try ChatGPTIdentity.verify(bad, jwks: jwks, clientID: "oaiapp_demo", nonce: "original", now: now))
  }

  func testPartialOrFailedStreamCannotBeReportedAsSuccessful() throws {
    func feed(_ json: [String: Any], into stream: inout ChatGPTResponseStream) throws {
      let data = try JSONSerialization.data(withJSONObject: json)
      _ = try stream.line("data: " + String(decoding: data, as: UTF8.self))
      _ = try stream.line("")
    }
    var interrupted = ChatGPTResponseStream()
    try feed(["type": "response.output_text.delta", "delta": "Partial answer"], into: &interrupted)
    XCTAssertEqual(interrupted.text, "Partial answer")
    XCTAssertThrowsError(try interrupted.finish())
    XCTAssertThrowsError(try feed(["type": "response.failed", "response": ["error": ["code": "subscription_sharing_usage_limit_exceeded"]]], into: &interrupted))
    var completed = ChatGPTResponseStream()
    try feed(["type": "response.output_text.delta", "delta": "Complete answer"], into: &completed)
    try feed(["type": "response.completed", "response": ["status": "completed", "output": []]], into: &completed)
    XCTAssertEqual(try completed.finish()["status"] as? String, "completed")
  }

  @MainActor
  func testHTTPEventBytesPreserveBlankBoundariesThroughFoundationStreaming() async throws {
    let body = "event: response.output_text.delta\r\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello Zerus\"}\r\n\r\nevent: response.completed\r\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[]}}\r\n\r\n"
    let bytes = AsyncStream<UInt8> { continuation in
      for byte in body.utf8 { continuation.yield(byte) }
      continuation.finish()
    }
    var text = ""
    let response = try await ChatGPTResponseStream.consume(bytes) { text += $0 }
    XCTAssertEqual(text, "Hello Zerus")
    XCTAssertEqual(response["status"] as? String, "completed")
  }

  @MainActor
  func testCompletedStreamRetainsDoneToolAndReasoningItemsWhenTerminalOutputIsEmpty() async throws {
    let events: [[String: Any]] = [
      ["type": "response.output_item.done", "output_index": 0, "item": ["type": "reasoning", "id": "reasoning-demo", "summary": [], "encrypted_content": "opaque-demo"]],
      ["type": "response.output_item.done", "output_index": 1, "item": ["type": "function_call", "name": "read_note", "namespace": "zerus", "call_id": "call-demo", "arguments": "{\"note_id\":\"demo-note\"}"]],
      ["type": "response.completed", "response": ["status": "completed", "output": []]],
    ]
    let data = try events.map { "data: " + String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) + "\n\n" }.joined()
    let bytes = AsyncStream<UInt8> { continuation in
      for byte in data.utf8 { continuation.yield(byte) }
      continuation.finish()
    }
    let response = try await ChatGPTResponseStream.consume(bytes) { _ in }
    let output = try XCTUnwrap(response["output"] as? [[String: Any]])
    XCTAssertEqual(output.count, 2, "Completed tool items must survive into the next model request.")
    guard output.count == 2 else { return }
    XCTAssertEqual(output[0]["encrypted_content"] as? String, "opaque-demo")
    let result = try ChatGPTResponses.result(response)
    let calls = try XCTUnwrap(result["toolCalls"] as? [[String: String]])
    XCTAssertEqual(calls.first?["id"], "call-demo")
    XCTAssertEqual(calls.first?["arguments"], "{\"note_id\":\"demo-note\"}")
    var interrupted = ChatGPTResponseStream()
    let first = try JSONSerialization.data(withJSONObject: events[1])
    _ = try interrupted.line("data: " + String(decoding: first, as: UTF8.self))
    _ = try interrupted.line("")
    XCTAssertThrowsError(try interrupted.finish(), "A completed item alone must not authorize tool execution.")
  }

  @MainActor
  func testLoopbackReceivesOnlyARequestForItsExactHostAndCallbackPath() async throws {
    let listener = ChatGPTLoopback()
    let redirect = try await listener.start()
    defer { listener.stop() }
    XCTAssertEqual(redirect.host, "127.0.0.1")
    var accepted = [URL]()
    listener.onCallback = { url in accepted.append(url); return true }
    let (body, response) = try await URLSession.shared.data(from: URL(string: redirect.absoluteString + "?state=test&code=example")!)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    XCTAssertEqual(accepted.count, 1)
    XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("Sign-in received"))
    let (_, rejected) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(redirect.port!)/another?state=test")!)
    XCTAssertEqual((rejected as? HTTPURLResponse)?.statusCode, 400)
    XCTAssertEqual(accepted.count, 1)
    XCTAssertNil(ChatGPTLoopback.callbackURL(header: "GET /auth/callback?code=x HTTP/1.1\r\nHost: example.test", redirectURI: redirect))
    XCTAssertNil(ChatGPTLoopback.callbackURL(header: "GET http://evil.test/auth/callback?code=x HTTP/1.1\r\nHost: 127.0.0.1:\(redirect.port!)", redirectURI: redirect))
  }

  func testNotesAgentPreservesReasoningToolIDsResultsAndUsageAcrossResponses() throws {
    let output: [[String: Any]] = [
      ["type": "reasoning", "id": "reasoning-1", "summary": [], "encrypted_content": "opaque-reasoning"],
      ["type": "function_call", "namespace": "zerus", "name": "note_get", "call_id": "call-1", "arguments": "{\"id\":\"reminder\"}"]
    ]
    let first = try ChatGPTResponses.result(["status": "completed", "output": output, "usage": ["input_tokens": 120, "output_tokens": 22]])
    let calls = try XCTUnwrap(first["toolCalls"] as? [[String: String]])
    XCTAssertEqual(calls.first?["id"], "call-1")
    XCTAssertEqual((first["usage"] as? [String: Int])?["outputTokens"], 22)
    let agent: [String: Any] = ["systemPrompt": "Read only selected notes.", "maxOutputTokens": 1024, "temperature": 0.4, "messages": [
      ["role": "user", "content": "What is the reminder?", "images": []],
      ["role": "assistant", "content": "", "images": [], "toolCalls": calls],
      ["role": "tool", "content": "Bring the blue notebook to Friday's meeting.", "images": [], "toolCallId": "call-1"]
    ], "tools": [["name": "note_get", "inputSchema": ["type": "object", "properties": ["id": ["type": "string"]]]]]]
    let body = try ChatGPTResponses.request(model: "account-model", agent: agent, completedOutputs: ["call-1": output])
    XCTAssertEqual(body["store"] as? Bool, false)
    XCTAssertEqual(body["stream"] as? Bool, true)
    XCTAssertNil(body["max_output_tokens"])
    XCTAssertNil(body["temperature"])
    XCTAssertNil(body["previous_response_id"])
    let input = try XCTUnwrap(body["input"] as? [[String: Any]])
    XCTAssertEqual(input.count, 4)
    XCTAssertEqual(input[1]["encrypted_content"] as? String, "opaque-reasoning")
    XCTAssertEqual(input[2]["call_id"] as? String, "call-1")
    XCTAssertEqual(input[3]["call_id"] as? String, "call-1")
    XCTAssertEqual(input[3]["output"] as? String, "Bring the blue notebook to Friday's meeting.")
    let namespace = try XCTUnwrap((body["tools"] as? [[String: Any]])?.first)
    XCTAssertEqual(namespace["type"] as? String, "namespace")
    XCTAssertEqual(namespace["name"] as? String, "zerus")
    XCTAssertEqual((namespace["tools"] as? [[String: Any]])?.first?["name"] as? String, "note_get")
    var foreign = output[1]; foreign["namespace"] = "outside_scope"
    XCTAssertThrowsError(try ChatGPTResponses.result(["status": "completed", "output": [foreign]]))
  }
}
