// swift-tools-version: 6.2
// On-device AI for the native apps (docs/local-ai-plan.md).
//
// - ZerusLocalAICore: model catalog, verified downloads, chunking, the per-device
//   search index and the Ask/Summarize/Edit pipelines. No MLX; `swift test` runs
//   its tests.
// - ZerusLocalAI: the MLX runtime (language model, embedder, device self-test).
//   MLX's Metal shaders only compile under xcodebuild, not plain SwiftPM.

import PackageDescription

let package = Package(
    name: "ZerusLocalAI",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "ZerusLocalAICore", targets: ["ZerusLocalAICore"]),
        .library(name: "ZerusLocalAI", targets: ["ZerusLocalAI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.33.0", traits: []),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.4.0"),
    ],
    targets: [
        .target(
            name: "ZerusLocalAICore",
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "ZerusLocalAI",
            dependencies: [
                "ZerusLocalAICore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "MLXGuidedGeneration", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "ZerusLocalAICoreTests",
            dependencies: ["ZerusLocalAICore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
