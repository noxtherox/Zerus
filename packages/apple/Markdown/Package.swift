// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ZerusMarkdown",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "ZerusMarkdown", targets: ["ZerusMarkdown"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.3")
    ],
    targets: [.target(name: "ZerusMarkdown", dependencies: [.product(name: "Markdown", package: "swift-markdown"), "SwiftSoup"])])
