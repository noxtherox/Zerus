// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tauri-plugin-mobile-vault",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "tauri-plugin-mobile-vault",
            type: .static,
            targets: ["tauri-plugin-mobile-vault"]),
    ],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api"),
        // 3.x adds Swift compiler macros that swift-rs incorrectly cross-compiles
        // for iOS. 2.31.3 is macro-free and supports Qwen3.5 vision-language models.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "2.31.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface", exact: "0.9.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "tauri-plugin-mobile-vault",
            dependencies: [
                .byName(name: "Tauri"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface")
            ],
            path: "Sources")
    ]
)
