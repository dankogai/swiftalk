// swift-tools-version:6.0
import PackageDescription

// The core: the Swiftalk library as a DYNAMIC product (round 182), so
// the CLI, the tests, and every native module share one copy of it —
// a module loaded with dlopen must see the same Value the host does.
let package = Package(
    name: "Core",
    // Regex (round 86) rides the stdlib's Regex, which wants macOS 13.
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Swiftalk", type: .dynamic, targets: ["Swiftalk"]),
    ],
    targets: [
        .target(name: "Swiftalk"),
    ]
)
