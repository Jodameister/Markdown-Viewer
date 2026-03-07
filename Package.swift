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
    targets: [
        .executableTarget(
            name: "MarkdownViewerNative"
        )
    ]
)
