// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Squire",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Squire", targets: ["Squire"]),
        .library(name: "SquireCore", targets: ["SquireCore"])
    ],
    targets: [
        // Platform-independent logic: sources, scanning, agents, installs, lock files.
        .target(name: "SquireCore"),
        // The macOS SwiftUI application.
        .executableTarget(
            name: "Squire",
            dependencies: ["SquireCore"]
        ),
        .testTarget(
            name: "SquireCoreTests",
            dependencies: ["SquireCore"]
        )
    ]
)
