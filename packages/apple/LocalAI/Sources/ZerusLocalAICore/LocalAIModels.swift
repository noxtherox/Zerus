import Foundation

/// One file of a pinned model snapshot. Large (LFS) files are checked with
/// SHA-256; small files with their git blob SHA-1, both as published by
/// Hugging Face for the pinned revision.
public struct LocalAIModelFile: Sendable, Hashable, Codable {
    public enum Digest: Sendable, Hashable, Codable {
        case sha256(String)
        case gitBlobSHA1(String)
    }

    public let path: String
    public let size: Int64
    public let digest: Digest

    public init(_ path: String, size: Int64, digest: Digest) {
        self.path = path
        self.size = size
        self.digest = digest
    }
}

/// A model the app can download, pinned to an exact Hugging Face revision.
public struct LocalAIModelSpec: Sendable, Hashable, Identifiable {
    public enum Role: String, Sendable { case language, embedding }

    public let id: String
    public let displayName: String
    public let role: Role
    public let repository: String
    public let revision: String
    public let license: String
    public let files: [LocalAIModelFile]

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    /// `https://huggingface.co/<repo>/resolve/<revision>/<path>`; the only
    /// remote location the local AI code ever contacts.
    public func url(for file: LocalAIModelFile) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = LocalAIModelSpec.downloadHost
        components.path = "/\(repository)/resolve/\(revision)/\(file.path)"
        return components.url!
    }

    public static let downloadHost = "huggingface.co"
}

extension LocalAIModelSpec {
    /// Qwen3.5-2B, 4-bit MLX (Apache-2.0). Chosen in phase 1: 103/126 on the
    /// eval suite, ~1.75 GB peak on iPhone.
    public static let qwen35_2B = LocalAIModelSpec(
        id: "qwen3.5-2b-4bit",
        displayName: "Qwen3.5 2B",
        role: .language,
        repository: "mlx-community/Qwen3.5-2B-4bit",
        revision: "674aaa7240b91e8012fcad5d791b7dfe5ba90207",
        license: "Apache-2.0",
        files: [
            .init("chat_template.jinja", size: 7755, digest: .gitBlobSHA1("0ef09f214eaa6d9bca297988afc1454b5827b2c7")),
            .init("config.json", size: 3113, digest: .gitBlobSHA1("6d901903a287e72c3677c1f8242a9f30c39dd117")),
            .init("model.safetensors", size: 1_722_271_785, digest: .sha256("713fe7e5d3c3965f7106b0d0ee17615f7869c23c8d327996df8c1196fbcf07d5")),
            .init("model.safetensors.index.json", size: 81722, digest: .gitBlobSHA1("2d9ef9d4c10685ab801a5d2011821d700b688d5f")),
            .init("preprocessor_config.json", size: 390, digest: .gitBlobSHA1("2ea84a437d448ff71b08df68fdd949d5cc4ebb64")),
            .init("processor_config.json", size: 1300, digest: .gitBlobSHA1("7ad6acdf4203f22b7b990e36ccc3a1fe38563d5e")),
            .init("tokenizer.json", size: 19_989_343, digest: .sha256("87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4")),
            .init("tokenizer_config.json", size: 1139, digest: .gitBlobSHA1("a068e2468cff426a9b105006e74e044030a6faf4")),
            .init("video_preprocessor_config.json", size: 385, digest: .gitBlobSHA1("3ba673a5ad7d4d13f54155ecd38b2a94a6dac8fe")),
            .init("vocab.json", size: 6_722_759, digest: .gitBlobSHA1("0aa0ce0658d60ac4a5d609f4eadb0e8e43514176")),
        ])

    /// EmbeddingGemma 300M, 4-bit MLX (Gemma Terms of Use), used unmodified.
    /// Recall@5 1.00 on the phase 1 retrieval set.
    public static let embeddingGemma300M = LocalAIModelSpec(
        id: "embeddinggemma-300m-4bit",
        displayName: "EmbeddingGemma 300M",
        role: .embedding,
        repository: "mlx-community/embeddinggemma-300m-4bit",
        revision: "5d9ef074df3957afc5c77127f208fddbc3c54187",
        license: "Gemma Terms of Use",
        files: [
            .init("added_tokens.json", size: 35, digest: .gitBlobSHA1("e17bde03d42feda32d1abfca6d3b598b9a020df7")),
            .init("config.json", size: 1726, digest: .gitBlobSHA1("f88b299518f3938a3b8e235028fc6fffec53164b")),
            .init("config_sentence_transformers.json", size: 997, digest: .gitBlobSHA1("3552ab1b79dc8571d0ecf200db12e5208eda5bdd")),
            .init("generation_config.json", size: 133, digest: .gitBlobSHA1("562150c0903db92148e95aeed8292bbfbf3c93d9")),
            .init("model.safetensors", size: 173_210_751, digest: .sha256("f2366c4c0dfdac15b30548ee44c9e06d7e7c0eb0bd13d26279f953fe2c9b278a")),
            .init("model.safetensors.index.json", size: 46809, digest: .gitBlobSHA1("4cab4425b10e0d45318af63aa99c8a8cead5e7d8")),
            .init("modules.json", size: 573, digest: .gitBlobSHA1("bb668a9a3aacb3090f2f8e73f870f556569f9066")),
            .init("sentence_bert_config.json", size: 58, digest: .gitBlobSHA1("b37b06424c6e0c0e880b24f3e313ebd85b601dcc")),
            .init("special_tokens_map.json", size: 662, digest: .gitBlobSHA1("1a6193244714d3d78be48666cb02cdbfac62ad86")),
            .init("tokenizer.json", size: 33_385_008, digest: .sha256("6852f8d561078cc0cebe70ca03c5bfdd0d60a45f9d2e0e1e4cc05b68e9ec329e")),
            .init("tokenizer_config.json", size: 1_155_346, digest: .gitBlobSHA1("33786d29ae85b05bc37772cd10876d66afbe905e")),
        ])

    public static let all: [LocalAIModelSpec] = [.embeddingGemma300M, .qwen35_2B]
}

/// Text templates EmbeddingGemma was trained with (retrieval task).
public enum EmbeddingPrompt {
    public static func query(_ text: String) -> String { "task: search result | query: \(text)" }
    public static func document(title: String, text: String) -> String {
        "title: \(title.isEmpty ? "none" : title) | text: \(text)"
    }
}
