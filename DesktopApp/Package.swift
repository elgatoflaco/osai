// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OSAIApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OSAIApp",
            path: "Sources/OSAIApp"
        )
    ]
)
