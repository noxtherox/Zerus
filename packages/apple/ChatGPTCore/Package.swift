// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "ZerusChatGPTCore",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [.library(name: "ZerusChatGPTCore", targets: ["ZerusChatGPTCore"])],
  targets: [
    .target(name: "ZerusChatGPTCore"),
    .testTarget(name: "ZerusChatGPTCoreTests", dependencies: ["ZerusChatGPTCore"])
  ]
)
