// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesktopAgent",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DesktopAgent",
            path: "Sources/DesktopAgent",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
