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
        .library(name: "IO", type: .dynamic, targets: ["IOModule"]),         // round 189: print, debugPrint
        .library(name: "Net", type: .dynamic, targets: ["NetModule"]),       // round 189: fetch, Response
        .library(name: "Sequence", type: .dynamic, targets: ["SequenceModule"]),   // round 192: Sequence.zip
        .library(name: "Task", type: .dynamic, targets: ["TaskModule"]),           // round 192: Task.sleep
        .library(name: "POSIX", type: .dynamic, targets: ["POSIXModule"]),   // round 188: Env grown up — the environment and file I/O
        .library(name: "Regex", type: .dynamic, targets: ["RegexModule"]),    // round 186: the regex engine
        .library(name: "BigInt", type: .dynamic, targets: ["BigIntModule"]),  // round 201: arbitrary-precision Ints, swift-bignum vendored
        .library(name: "BigRat", type: .dynamic, targets: ["BigRatModule"]),  // round 203: exact rationals, the same engine
    ],
    dependencies: [
        .package(path: "Core"),
        .package(path: "modules/BigNum"),   // swift-bignum vendored, a dynamic library both BigInt and BigRat share (round 203)
    ],
    targets: [
        .executableTarget(name: "SwiftalkCLI", dependencies: [.product(name: "Swiftalk", package: "Core")]),
        .target(name: "IOModule", dependencies: [.product(name: "Swiftalk", package: "Core")], path: "modules/IO"),
        .target(name: "NetModule", dependencies: [.product(name: "Swiftalk", package: "Core")], path: "modules/Net"),
        .target(name: "SequenceModule", dependencies: [.product(name: "Swiftalk", package: "Core")], path: "modules/Sequence"),
        .target(name: "TaskModule", dependencies: [.product(name: "Swiftalk", package: "Core")], path: "modules/Task"),
        .target(name: "POSIXModule", dependencies: [.product(name: "Swiftalk", package: "Core")], path: "modules/POSIX"),
        .target(name: "RegexModule", dependencies: [.product(name: "Swiftalk", package: "Core")], path: "modules/Regex"),
        .target(name: "BigIntModule", dependencies: [.product(name: "Swiftalk", package: "Core"), .product(name: "BigNum", package: "BigNum")], path: "modules/BigInt"),
        .target(name: "BigRatModule", dependencies: [.product(name: "Swiftalk", package: "Core"), .product(name: "BigNum", package: "BigNum")], path: "modules/BigRat"),
        .testTarget(name: "SwiftalkTests", dependencies: [.product(name: "Swiftalk", package: "Core")]),
    ]
)
