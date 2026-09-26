// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "SquireCore", targets: ["SquireCore"])
]

var targets: [Target] = [
    // Platform-independent logic: sources, scanning, agents, installs, lock files.
    .target(name: "SquireCore"),
    .testTarget(
        name: "SquireCoreTests",
        dependencies: ["SquireCore"]
    )
]

#if os(macOS)
// The SwiftUI application only builds on macOS; SquireCore and its tests also build on Linux.
products.append(.executable(name: "Squire", targets: ["Squire"]))
targets.append(
    .executableTarget(
        name: "Squire",
        dependencies: ["SquireCore"]
    )
)
#endif

let package = Package(
    name: "Squire",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    targets: targets
)
