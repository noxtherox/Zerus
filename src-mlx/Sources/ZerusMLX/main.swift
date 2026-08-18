import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

private let modelConfiguration = LLMRegistry.qwen3_1_7b_4bit

private struct RequestMessage: Decodable {
    let role: String
    let content: String
    let imagePaths: [String]
}

private struct Request: Decodable {
    let id: UInt64
    let command: String
    let systemPrompt: String?
    let messages: [RequestMessage]?
}

private struct Response: Encodable {
    let id: UInt64
    let type: String
    let content: String?
    let reasoning: String?
    let message: String?
    let downloadedBytes: Int64?
    let totalBytes: Int64?
    let phase: String?
}

private final class Runtime {
    private let hub: HubClient
    private let readyMarker: URL
    private var model: ModelContainer?

    init(cacheDirectory: URL) {
        hub = HubClient(cache: HubCache(cacheDirectory: cacheDirectory))
        readyMarker = cacheDirectory.appendingPathComponent("zerus-qwen3-1.7b-4bit.ready")
    }

    func load(requestID: UInt64) async throws -> ModelContainer {
        if let model { return model }
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(hub),
            using: #huggingFaceTokenizerLoader(),
            configuration: modelConfiguration
        ) { progress in
            write(
                Response(
                    id: requestID,
                    type: "progress",
                    content: nil,
                    reasoning: nil,
                    message: nil,
                    downloadedBytes: progress.completedUnitCount,
                    totalBytes: progress.totalUnitCount,
                    phase: progress.isFinished ? "installing" : "downloading"
                )
            )
        }
        model = loaded
        try Data().write(to: readyMarker, options: .atomic)
        return loaded
    }

    func chat(requestID: UInt64, systemPrompt: String, messages: [RequestMessage]) async throws
        -> String
    {
        let model = try await load(requestID: requestID)
        let session = ChatSession(
            model,
            generateParameters: GenerateParameters(
                maxTokens: 1_024,
                temperature: 0.2,
                topK: 40
            ),
            additionalContext: ["enable_thinking": false]
        )
        var chat = [Chat.Message.system(systemPrompt)]
        for message in messages {
            if !message.imagePaths.isEmpty {
                throw RuntimeError.imagesUnsupported
            }
            switch message.role {
            case "assistant":
                chat.append(.assistant(message.content))
            case "user":
                chat.append(.user(message.content))
            default:
                throw RuntimeError.invalidRole(message.role)
            }
        }
        return try await session.respond(to: chat)
    }
}

private enum RuntimeError: LocalizedError {
    case invalidArguments
    case invalidCommand(String)
    case invalidRole(String)
    case imagesUnsupported
    case missingConversation

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            "Zerus MLX requires --cache-dir PATH"
        case .invalidCommand(let command):
            "Unknown MLX command: \(command)"
        case .invalidRole(let role):
            "Unknown chat role: \(role)"
        case .imagesUnsupported:
            "Qwen3 1.7B is text-only and cannot read image attachments"
        case .missingConversation:
            "The MLX conversation is empty"
        }
    }
}

private let encoder = JSONEncoder()

private func write(_ response: Response) {
    guard let data = try? encoder.encode(response),
          let line = String(data: data, encoding: .utf8)
    else { return }
    FileHandle.standardOutput.write(Data("\(line)\n".utf8))
}

private func cacheDirectory() throws -> URL {
    guard let index = CommandLine.arguments.firstIndex(of: "--cache-dir"),
          CommandLine.arguments.indices.contains(index + 1)
    else { throw RuntimeError.invalidArguments }
    return URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
}

@main
private enum ZerusMLX {
    static func main() async {
        do {
            let runtime = Runtime(cacheDirectory: try cacheDirectory())
            while let line = readLine() {
                guard let data = line.data(using: .utf8) else { continue }
                do {
                    let request = try JSONDecoder().decode(Request.self, from: data)
                    switch request.command {
                    case "load", "download":
                        _ = try await runtime.load(requestID: request.id)
                        write(Response(
                            id: request.id, type: "result", content: "ready", reasoning: nil,
                            message: nil, downloadedBytes: nil, totalBytes: nil, phase: nil))
                    case "chat":
                        guard let systemPrompt = request.systemPrompt,
                              let messages = request.messages,
                              !messages.isEmpty
                        else { throw RuntimeError.missingConversation }
                        let content = try await runtime.chat(
                            requestID: request.id,
                            systemPrompt: systemPrompt,
                            messages: messages
                        )
                        write(Response(
                            id: request.id, type: "result", content: content, reasoning: nil,
                            message: nil, downloadedBytes: nil, totalBytes: nil, phase: nil))
                    default:
                        throw RuntimeError.invalidCommand(request.command)
                    }
                } catch {
                    let requestID = (try? JSONDecoder().decode(Request.self, from: data).id) ?? 0
                    write(Response(
                        id: requestID, type: "error", content: nil, reasoning: nil,
                        message: error.localizedDescription, downloadedBytes: nil,
                        totalBytes: nil, phase: nil))
                }
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }
}
