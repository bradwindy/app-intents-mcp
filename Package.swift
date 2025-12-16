// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "app-intents-mcp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "app-intents-mcp", targets: ["AppIntentsMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "AppIntentsMCP",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "AppIntentsMCPTests",
            dependencies: ["AppIntentsMCP"]
        )
    ]
)
