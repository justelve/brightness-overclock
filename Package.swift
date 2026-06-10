// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BrightnessOverclock",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OverclockCore"),
        .executableTarget(
            name: "BrightnessOverclock",
            dependencies: ["OverclockCore"]
        ),
        .testTarget(
            name: "OverclockCoreTests",
            dependencies: ["OverclockCore"]
        ),
    ]
)
