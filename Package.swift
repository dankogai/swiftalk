// swift-tools-version:6.0
import PackageDescription

// The umbrella (round 182): the CLI, the tests, and the native modules,
// all linking the core's dynamic library from Core/ — SwiftPM links a
// same-package library statically whatever its product type, so the
// core lives in a package of its own to be shared.
let package = Package(
    name: "swiftalk",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swiftalk", targets: ["SwiftalkCLI"]),
        // Native modules (round 182): one dynamic library per module,
        // `lib<Name>.dylib`, found by `import from "<Name>"` — a capital by
        // convention (round 183), like a type.
        .library(name: "Env", type: .dynamic, targets: ["EnvModule"]),
    ],
    dependencies: [
        .package(path: "Core"),
    ],
    targets: [
        .executableTarget(name: "SwiftalkCLI", dependencies: [.product(name: "Swiftalk", package: "Core")]),
        .target(name: "EnvModule", dependencies: [.product(name: "Swiftalk", package: "Core")], path: "modules/Env"),
        .testTarget(name: "SwiftalkTests", dependencies: [.product(name: "Swiftalk", package: "Core")]),
    ]
)
