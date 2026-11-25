// swift-tools-version: 6.2
// Local AI evaluation runner. Build with xcodebuild (SwiftPM alone cannot
// compile MLX's Metal shaders); see ../README.md. It runs the production
// pipelines, loader and search index from packages/apple/LocalAI.

import PackageDescription

let package = Package(
    name: "ZerusAIEval",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../../packages/apple/LocalAI"),
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.33.0",
            traits: []),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "zerus-ai-eval",
            dependencies: [
                .product(name: "ZerusLocalAICore", package: "LocalAI"),
                .product(name: "ZerusLocalAI", package: "LocalAI"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/ZerusAIEval",
            swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
