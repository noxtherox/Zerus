import Foundation

/// Translate Zerus's shared notes-agent protocol to the public Responses API.
public enum ChatGPTResponses {
  public static func request(model: String, agent: [String: Any], completedOutputs: [String: [[String: Any]]] = [:]) throws -> [String: Any] {
    guard !model.isEmpty, let instructions = agent["systemPrompt"] as? String,
          !instructions.isEmpty, let messages = agent["messages"] as? [[String: Any]],
          !messages.isEmpty, messages.count <= 256 else { throw invalid() }
    var input: [[String: Any]] = []
    for message in messages {
      guard let role = message["role"] as? String, let text = message["content"] as? String else { throw invalid() }
      switch role {
      case "user":
        var content: [[String: Any]] = [["type": "input_text", "text": text]]
        let images = message["images"] as? [[String: String]] ?? []
        guard images.count <= 4 else { throw invalid() }
        for image in images {
          guard let media = image["mediaType"], ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(media),
                let data = image["data"], data.count <= 4_200_000, Data(base64Encoded: data) != nil else { throw invalid() }
          content.append(["type": "input_image", "image_url": "data:\(media);base64,\(data)"])
        }
        input.append(["role": "user", "content": content])
      case "assistant":
        let calls = message["toolCalls"] as? [[String: String]] ?? []
        guard calls.count <= 32 else { throw invalid() }
        for call in calls {
          guard let id = call["id"], !id.isEmpty, let name = call["name"], validName(name),
                let arguments = call["arguments"], arguments.count <= 200_000,
                let data = arguments.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw invalid() }
        }
        if let firstID = calls.first?["id"], let output = completedOutputs[firstID],
           Set(output.filter { $0["type"] as? String == "function_call" }.compactMap { $0["call_id"] as? String }) == Set(calls.compactMap { $0["id"] }) {
          // Exact server output, including reasoning and message phase, stays native.
          input += output
        } else {
          if !text.isEmpty { input.append(["role": "assistant", "content": [["type": "output_text", "text": text]]]) }
          for call in calls {
            input.append(["type": "function_call", "namespace": "zerus", "name": call["name"]!, "call_id": call["id"]!, "arguments": call["arguments"]!])
          }
        }
      case "tool":
        guard let id = message["toolCallId"] as? String, !id.isEmpty else { throw invalid() }
        input.append(["type": "function_call_output", "call_id": id, "output": text])
      default: throw invalid()
      }
    }
    var body: [String: Any] = ["model": model, "input": input, "instructions": instructions,
                              "store": false, "stream": true, "include": ["reasoning.encrypted_content"]]
    let tools = agent["tools"] as? [[String: Any]] ?? []
    guard tools.count <= 50 else { throw invalid() }
    if !tools.isEmpty {
      let functions = try tools.map { tool -> [String: Any] in
        guard let name = tool["name"] as? String, validName(name),
              let schema = tool["inputSchema"] as? [String: Any] else { throw invalid() }
        return ["type": "function", "name": name, "description": tool["description"] as? String ?? "",
                "parameters": schema, "strict": false]
      }
      body["tools"] = [["type": "namespace", "name": "zerus", "description": "Zerus's scoped note tools.", "tools": functions]]
      body["tool_choice"] = agent["toolChoice"] as? String == "none" ? "none" : "auto"
    }
    if let effort = agent["effort"] as? String, ["none", "minimal", "low", "medium", "high", "xhigh"].contains(effort) {
      body["reasoning"] = ["effort": effort]
    }
    if let ceiling = agent["maxOutputTokens"] as? Int {
      guard (1...32768).contains(ceiling) else { throw invalid() }
      // This flow rejects max_output_tokens; the run budget still checks each step.
      body["instructions"] = instructions + "\nKeep this response within approximately \(ceiling) output tokens."
    }
    return body
  }

  public static func result(_ response: [String: Any]) throws -> [String: Any] {
    guard response["status"] as? String == "completed", let output = response["output"] as? [[String: Any]] else { throw invalid() }
    var text = ""
    var reasoning = ""
    var calls: [[String: String]] = []
    for item in output {
      switch item["type"] as? String {
      case "message":
        for part in item["content"] as? [[String: Any]] ?? [] where part["type"] as? String == "output_text" { text += part["text"] as? String ?? "" }
      case "reasoning":
        for part in item["summary"] as? [[String: Any]] ?? [] { reasoning += part["text"] as? String ?? "" }
      case "function_call":
        guard item["namespace"] == nil || item["namespace"] as? String == "zerus",
              let id = item["call_id"] as? String, !id.isEmpty,
              let name = item["name"] as? String, validName(name),
              let arguments = item["arguments"] as? String, arguments.count <= 200_000 else { throw invalid() }
        calls.append(["id": id, "name": name, "arguments": arguments])
      default: break
      }
    }
    let reported = response["usage"] as? [String: Any] ?? [:]
    var usage: [String: Int] = [:]
    usage["inputTokens"] = reported["input_tokens"] as? Int
    usage["outputTokens"] = reported["output_tokens"] as? Int
    return ["content": text, "reasoning": reasoning, "toolCalls": calls, "usage": usage,
            "finishReason": calls.isEmpty ? "stop" : "tool_calls"]
  }

  private static func validName(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil }
  private static func invalid() -> ChatGPTError { .message("ChatGPT returned or received an invalid notes-agent response.") }
}
