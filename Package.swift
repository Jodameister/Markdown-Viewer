// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkdownViewerNative",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "MarkdownViewerNative", targets: ["MarkdownViewerNative"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.7.1")
    ],
    targets: [
        .executableTarget(
            name: "MarkdownViewerNative",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark")
            ]
        )
    ]
)
