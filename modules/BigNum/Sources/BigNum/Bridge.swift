//
//  Bridge.swift -- swiftalk's, not swift-bignum's (round 203): how the
//  BigInt and BigRat modules recognize each other's values. Each module
//  is a dynamic library of its own that cannot see the other's classes;
//  both see these protocols, which live in the library they share.
//

/// A module value that carries a `BigInt` — the BigInt module's.
public protocol BigIntCarrier: AnyObject {
    var bigInt: BigInt { get }
}

/// A module value that carries a `BigRat` — the BigRat module's.
public protocol BigRatCarrier: AnyObject {
    var bigRat: BigRat { get }
}
