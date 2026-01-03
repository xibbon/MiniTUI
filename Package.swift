// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MiniTui",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "MiniTui",
            targets: ["MiniTui"]
        ),
        .executable(
            name: "MiniTuiDemo",
            targets: ["MiniTuiDemo"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "MiniTui",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .testTarget(
            name: "MiniTuiTests",
            dependencies: ["MiniTui"]
        ),
        .executableTarget(
            name: "MiniTuiDemo",
            dependencies: ["MiniTui"]
        ),
    ]
)
