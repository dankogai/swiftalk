// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swiftalk",
    // Regex (round 86) rides the stdlib's Regex, which wants macOS 13.
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Swiftalk", targets: ["Swiftalk"]),
        .executable(name: "swiftalk", targets: ["SwiftalkCLI"]),
    ],
    targets: [
        .target(name: "Swiftalk"),
        .executableTarget(name: "SwiftalkCLI", dependencies: ["Swiftalk"]),
        .testTarget(name: "SwiftalkTests", dependencies: ["Swiftalk"]),
    ]
)
