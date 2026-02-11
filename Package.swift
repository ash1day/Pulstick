// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pulstick",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Pulstick",
            path: "Sources/Pulstick",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
