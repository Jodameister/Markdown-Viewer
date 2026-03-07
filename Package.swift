// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkdownViewerNative",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MarkdownViewerNative", targets: ["MarkdownViewerNative"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1")
    ],
    targets: [
        .executableTarget(
            name: "MarkdownViewerNative",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]
        )
    ]
)
