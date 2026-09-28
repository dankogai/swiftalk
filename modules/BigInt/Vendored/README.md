# Vendored from swift-bignum

These files are copied, unmodified except for `BigNum.swift` (reduced to
the one helper the integer files use), from
[dankogai/swift-bignum](https://github.com/dankogai/swift-bignum) at
commit `3a5d4576631fdec53de85679c1659ae3be2e907e` (2026-08-21) — the
`BigInt` and `BigUInt` types and their radix conversion, under the MIT
license (see [LICENSE](LICENSE)). Not an SPM dependency by decision
(round 201): the module carries its own copy, so the umbrella package
fetches nothing. `BigRat`, `BigFloat`, primality, and random numbers
stay out until swiftalk asks for them.

To refresh: copy `BigUInt.swift`, `BigInt.swift`, `BigIntType.swift`,
`Radix.swift` from `Sources/BigNum/` and update the commit above.
