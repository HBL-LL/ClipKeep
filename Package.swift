// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClipKeep",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipKeep",
            path: "Sources/ClipKeep",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
