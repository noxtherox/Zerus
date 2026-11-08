import Foundation

struct NativeAgentGuidance: Codable, Equatable, Sendable {
    var instructions = ""
    var memory = ""
    func validate() throws {
        guard instructions.utf16.count <= 12_000, memory.utf16.count <= 8_000 else {
            throw VaultFailure(message: "Keep vault instructions within 12,000 characters and memory within 8,000 characters. The original files are kept.")
        }
    }
}

struct NativeAgentGuidanceSnapshot: Sendable {
    let root: URL
    let instructionsBytes: Data?
    let memoryBytes: Data?
    let guidance: NativeAgentGuidance
}

// The coordinator writes this once; its synchronous boundary waits before return.
private final class NativeAgentMetadataRead: @unchecked Sendable {
    var value: Result<[Data?], Error> = .failure(VaultFailure(message: "Could not read this vault’s AI configuration."))
}

extension VaultFiles {
    func agentMetadata(_ files: [(path: String, limit: Int)]) throws -> [Data?] {
        let root = root, result = NativeAgentMetadataRead()
        let locations = try files.map { try url(for: $0.path) }
        try Self.coordinateTransaction(locations: locations, root: root, reading: Set(locations.indices)) { urls in
            result.value = Result {
                try urls.enumerated().map { index, location in
                    let limit = files[index].limit
                    _ = try Self.confinedPath(for: location, root: root)
                    guard FileManager.default.fileExists(atPath: location.path) else { return nil }
                    let values = try location.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= limit else {
                        throw VaultFailure(message: "An AI configuration file is too large or is not an ordinary file. Its original is kept; check it in Files.")
                    }
                    let handle = try FileHandle(forReadingFrom: location); defer { try? handle.close() }
                    var bytes = Data()
                    while let part = try handle.read(upToCount: min(4096, limit + 1 - bytes.count)), !part.isEmpty {
                        bytes.append(part)
                        guard bytes.count <= limit else { throw VaultFailure(message: "An AI configuration file grew while opening. Its original is kept; reopen this screen.") }
                    }
                    guard bytes.count == values.fileSize else { throw VaultFailure(message: "An AI configuration file changed while opening. Its original is kept; reopen this screen.") }
                    return bytes
                }
            }
        }
        return try result.value.get()
    }
    func agentGuidance() throws -> NativeAgentGuidanceSnapshot {
        let bytes = try agentMetadata([(".zerus/ai/instructions.md", 48_000), (".zerus/ai/memory.md", 32_000)])
        func text(_ bytes: Data?) throws -> String {
            guard let bytes else { return "" }
            guard let text = String(data: bytes, encoding: .utf8) else { throw VaultFailure(message: "An AI guidance file is not readable UTF-8 text. Its original is kept; correct it in Files before sending a new AI request.") }
            return text
        }
        let value = NativeAgentGuidance(instructions: try text(bytes[0]), memory: try text(bytes[1])); try value.validate()
        return .init(root: root, instructionsBytes: bytes[0], memoryBytes: bytes[1], guidance: value)
    }

    func saveAgentGuidance(_ value: NativeAgentGuidance, expected: NativeAgentGuidanceSnapshot) throws -> NativeAgentGuidanceSnapshot {
        guard expected.root == root else { throw VaultFailure(message: "These instructions belong to another vault. Reopen AI instructions here.") }
        try value.validate()
        func bytes(_ text: String, original: Data?, previous: String) -> Data? { text == previous ? original : Data(text.utf8) }
        let a = bytes(value.instructions, original: expected.instructionsBytes, previous: expected.guidance.instructions)
        let b = bytes(value.memory, original: expected.memoryBytes, previous: expected.guidance.memory)
        try applyTransaction([
            .init(path: ".zerus/ai/instructions.md", before: expected.instructionsBytes, after: a),
            .init(path: ".zerus/ai/memory.md", before: expected.memoryBytes, after: b)
        ], historySource: "ai-guidance")
        return .init(root: root, instructionsBytes: a, memoryBytes: b, guidance: value)
    }
}
