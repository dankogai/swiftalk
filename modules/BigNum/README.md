# swift-bignum, vendored

`Sources/BigNum/` is copied unmodified from
[dankogai/swift-bignum](https://github.com/dankogai/swift-bignum) at
commit `3a5d4576631fdec53de85679c1659ae3be2e907e` (2026-08-21) — the
whole `BigNum` target: `BigInt`, `BigUInt`, `BigRat`, `BigFloat`, and
their number theory — under the MIT license (see [LICENSE](LICENSE)).
Not an SPM dependency by decision (round 201): the tree carries its own
copy, so the umbrella package fetches nothing. It is a **local package
with a dynamic library product**, because the BigInt and BigRat modules
both use it and a same-package target would be linked statically into
each — two copies of `BigInt`, the round-182 problem (round 203). The
`Bridge.swift` beside the vendored files is swiftalk's: the protocols
through which the two modules recognize each other's values.

To refresh: copy `Sources/BigNum/*.swift` over and update the commit above.
