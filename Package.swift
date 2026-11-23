// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeAtAGlance",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GlanceCore", targets: ["GlanceCore"]),
        .executable(name: "ClaudeAtAGlance", targets: ["ClaudeAtAGlance"])
    ],
    targets: [
        .target(
            name: "GlanceCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ClaudeAtAGlance",
            dependencies: ["GlanceCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GlanceCoreTests",
            dependencies: ["GlanceCore"],
            resources: [.copy("Fixtures/usage-sample.json"), .copy("Fixtures/stats-sample.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
