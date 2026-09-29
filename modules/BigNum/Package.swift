// swift-tools-version:5.9
// (5.9, not 6: the vendored sources are Swift 5 code — language mode 5, as upstream declares)
import PackageDescription

// swift-bignum, vendored (rounds 201, 203): the arithmetic behind the
// BigInt and BigRat modules, a dynamic library of its own so that both
// modules share one copy of the types — the round-182 lesson, again:
// a same-package dependency would be linked statically into each.
// See README.md for provenance; not an SPM dependency by decision.
let package = Package(
    name: "BigNum",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BigNum", type: .dynamic, targets: ["BigNum"]),
    ],
    targets: [
        .target(name: "BigNum"),
    ]
)
