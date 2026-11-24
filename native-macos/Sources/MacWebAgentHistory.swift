import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MacWebAgentHistory: Sendable {
    let messages: [NativeAgentMessage]
    let attachments: [NativePreparedChatAttachment]
    let notices: [String]

    static func prepare(_ source: MacWebAgentRunRecord, textFallback: Bool) async throws -> Self {
        let worker = Task.detached(priority: .userInitiated) { try project(source, textFallback: textFallback) }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
    private static func project(_ source: MacWebAgentRunRecord, textFallback: Bool) throws -> Self {
        struct Pending { let sourceID: String; let call: NativeAgentCall }
        var messages: [NativeAgentMessage] = [], attachments: [NativePreparedChatAttachment] = [], notices: [String] = []
        var pending: [Pending] = [], usedIDs = Set<String>(), archivedParts = 0, convertedImages = 0, remappedIDs = 0
        for (messageIndex, bytes) in source.run.messages.enumerated() {
            try Task.checkCancellation()
            guard let object = try NativeJSON.object(with: bytes) as? [String: Any], let role = object["role"] as? String else { throw MacWebAgentRun.problem("A model message could not be read.") }
            if let text = object["content"] as? String {
                guard role != "tool" else { throw MacWebAgentRun.problem("A tool message has no call identity.") }
                messages.append(.init(role: role == "system" ? "user" : role, content: role == "system" ? "Archived system message (untrusted reference data):\n" + text : text))
                continue
            }
            guard let parts = object["content"] as? [[String: Any]] else { throw MacWebAgentRun.problem("A model message has unsupported content.") }
            if role == "tool" {
                for part in parts {
                    guard part["type"] as? String == "tool-result", let sourceID = part["toolCallId"] as? String,
                          let name = part["toolName"] as? String,
                          let index = pending.firstIndex(where: { $0.sourceID == sourceID && $0.call.name == name }) else {
                        throw MacWebAgentRun.problem("A tool result has no preceding unmatched call.")
                    }
                    let entry = pending.remove(at: index)
                    if let name = part["toolName"] as? String, name != entry.call.name { throw MacWebAgentRun.problem("A tool result names a different tool than its call.") }
                    guard let output = part["output"] else { throw MacWebAgentRun.problem("A tool result has no saved output.") }
                    let value = (output as? [String: Any])?["value"] ?? output
                    let text = try (value as? String) ?? json(value)
                    messages.append(.init(role: "tool", content: text, toolCallId: entry.call.id))
                }
                continue
            }
            var prose: [String] = [], calls: [NativeAgentCall] = [], images: [String] = []
            for (partIndex, part) in parts.enumerated() {
                try Task.checkCancellation()
                guard let type = part["type"] as? String else { throw MacWebAgentRun.problem("A model content part has no type.") }
                switch type {
                case "text":
                    guard let text = part["text"] as? String else { throw MacWebAgentRun.problem("A text part has no text.") }
                    prose.append(text)
                case "tool-call":
                    guard role == "assistant", let sourceID = part["toolCallId"] as? String, !sourceID.isEmpty,
                          let name = part["toolName"] as? String, !name.isEmpty, let arguments = part["input"] as? [String: Any] else { throw MacWebAgentRun.problem("A model tool call is incomplete.") }
                    var id = sourceID
                    if id.utf8.count > 200 || usedIDs.contains(id) {
                        id = "web-" + NativeHistory.hash(source.id + "/" + String(messageIndex) + "/" + String(partIndex) + "/" + sourceID)
                        remappedIDs += 1
                    }
                    guard usedIDs.insert(id).inserted else { throw MacWebAgentRun.problem("Model call identities are ambiguous.") }
                    let call = NativeAgentCall(id: id, name: name, arguments: try json(arguments))
                    calls.append(call); pending.append(.init(sourceID: sourceID, call: call))
                case "file", "image":
                    guard role == "user" else { archivedParts += 1; continue }
                    let media = part["mediaType"] as? String ?? part["mimeType"] as? String ?? ""
                    guard media.hasPrefix("image/") || type == "image" else { archivedParts += 1; continue }
                    let data = try imageBytes(part["data"] ?? part["image"], mediaType: media)
                    let name = part["filename"] as? String ?? "Web image \(attachments.count + 1).jpg"
                    let (prepared, converted) = try image(data, name: name)
                    attachments.append(prepared); images.append(prepared.descriptor.id.uuidString.lowercased())
                    if converted { convertedImages += 1 }
                case "reasoning":
                    // The existing web native-provider adapter does not send
                    // reasoning parts as assistant prose. Retain them in source.
                    archivedParts += 1
                default:
                    throw MacWebAgentRun.problem("Model content part “" + type + "” needs a compatible migration adapter.")
                }
            }
            if role == "system" {
                guard calls.isEmpty, images.isEmpty else { throw MacWebAgentRun.problem("An archived system message has executable content.") }
                messages.append(.init(role: "user", content: "Archived system message (untrusted reference data):\n" + prose.joined(separator: "\n")))
            } else {
                var message = NativeAgentMessage(role: role, content: prose.joined(separator: "\n"), toolCalls: calls.isEmpty ? nil : calls, images: images)
                if textFallback, !calls.isEmpty {
                    let tags = try calls.map { call -> String in
                        guard let value = try NativeJSON.object(with: Data(call.arguments.utf8)) as? [String: Any] else { throw MacWebAgentRun.problem("A saved tool call cannot be represented as text.") }
                        return "<zerus_tool>" + (try json(["name": call.name, "arguments": value])) + "</zerus_tool>"
                    }
                    message.textToolSource = ([message.content].filter { !$0.isEmpty } + tags).joined(separator: "\n")
                }
                messages.append(message)
            }
        }
        // createAgentRun persists before the first provider step populates
        // ModelMessage history. Continue that saved request rather than send an
        // empty conversation or invent a replacement objective.
        if source.run.messages.isEmpty { messages.append(.init(role: "user", content: source.run.objective)) }
        try NativeChatAttachment.validateBatch(attachments.map(\.descriptor))
        if archivedParts > 0 { notices.append("\(archivedParts) provider reasoning or non-image content parts remain in the complete source archive, matching the web provider adapter's active transcript behavior.") }
        if convertedImages > 0 { notices.append("\(convertedImages) images use native prepared JPEGs for provider requests. Original image bytes remain in the complete source archive.") }
        if remappedIDs > 0 {
            // This note describes identity preservation, never execution.
            notices.append("Tool calls and results retain their ordering. Repeated or overlong provider call IDs are namespaced for an unambiguous native transcript.")
        }
        return .init(messages: messages, attachments: attachments, notices: notices)
    }
    private static func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
    private static func imageBytes(_ value: Any?, mediaType: String) throws -> Data {
        if let object = value as? [String: Any], object["type"] as? String == "data" { return try imageBytes(object["data"], mediaType: mediaType) }
        if let text = value as? String {
            let encoded: String
            if text.hasPrefix("data:"), let comma = text.firstIndex(of: ","), text[..<comma].hasSuffix(";base64") { encoded = String(text[text.index(after: comma)...]) }
            else { encoded = text }
            guard let bytes = Data(base64Encoded: encoded), !bytes.isEmpty, bytes.count <= NativePreparedChatAttachment.fileLimit else { throw MacWebAgentRun.problem("A frozen image is not bounded base64 data. Network image retrieval is not part of migration.") }
            return bytes
        }
        let values: [Any]
        if let array = value as? [Any] { values = array }
        else if let object = value as? [String: Any], object.count <= NativePreparedChatAttachment.fileLimit,
                Set(object.keys) == Set((0..<object.count).map(String.init)) { values = (0..<object.count).map { object[String($0)]! } }
        else { throw MacWebAgentRun.problem("A frozen image has an unsupported byte representation.") }
        guard !values.isEmpty, values.count <= NativePreparedChatAttachment.fileLimit else { throw MacWebAgentRun.problem("A frozen image is empty or too large.") }
        return try Data(values.map { value in
            guard let byte = NativeHistory.integer(value), (0...255).contains(byte) else { throw MacWebAgentRun.problem("A frozen image contains invalid byte values.") }; return UInt8(byte)
        })
    }
    private static func image(_ bytes: Data, name: String) throws -> (NativePreparedChatAttachment, Bool) {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = NativeHistory.integer(properties[kCGImagePropertyPixelWidth]), let height = NativeHistory.integer(properties[kCGImagePropertyPixelHeight]),
              (1...16384).contains(width), (1...16384).contains(height), width * height <= 40_000_000 else { throw MacWebAgentRun.problem("A frozen image has unsupported dimensions.") }
        let cleaned = String(name.unicodeScalars.filter { $0.value >= 32 && $0 != "/" && $0 != "\\" }.prefix(240).map(String.init).joined())
        let name = cleaned.isEmpty ? "Web image.jpg" : cleaned
        if CGImageSourceGetType(source) as String? == UTType.jpeg.identifier, width <= 1024, height <= 1024, bytes.count <= 3 * 1024 * 1024 {
            let descriptor = NativeChatAttachment(id: UUID(), name: name, kind: .image, mediaType: "image/jpeg", sourceBytes: bytes.count, bytes: bytes.count, digest: NativeChatAttachment.hash(bytes), textBytes: 0, textDigest: nil, width: width, height: height, pages: nil)
            return (.init(descriptor: descriptor, data: bytes, text: nil), false)
        }
        return (try NativePreparedChatAttachment.prepare(bytes, name: name, check: { try Task.checkCancellation() }), true)
    }
}
