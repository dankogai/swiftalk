// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swiftalk",
    products: [
        .library(name: "Swiftalk", targets: ["Swiftalk"]),
    ],
    targets: [
        .target(name: "Swiftalk"),
        .testTarget(name: "SwiftalkTests", dependencies: ["Swiftalk"]),
    ]
)
