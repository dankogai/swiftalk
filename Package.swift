// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swiftalk",
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
