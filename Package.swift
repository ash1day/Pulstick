// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pulstick",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "PulstickCore",
            path: "Sources/PulstickCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Pulstick",
            dependencies: ["PulstickCore"],
            path: "Sources/Pulstick",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PulstickTests",
            dependencies: ["PulstickCore"],
            path: "Tests/PulstickTests"
        ),
    ]
)
