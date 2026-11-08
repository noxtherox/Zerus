// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "ZerusIOSServices",
  platforms: [.iOS(.v17)],
  products: [.library(name: "ZerusIOSServices", targets: ["ZerusIOSServices"])],
  dependencies: [.package(path: "../ChatGPTCore")],
  targets: [
    .target(
      name: "ZerusIOSServices",
      dependencies: [.product(name: "ZerusChatGPTCore", package: "ChatGPTCore")]
    )
  ]
)
