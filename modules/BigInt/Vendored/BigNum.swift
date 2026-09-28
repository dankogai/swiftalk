//
//  BigNum.swift -- the one piece of swift-bignum's BigNum.swift that the
//  integer files use: the radix prefixes. The rest of that file is the
//  floating-point protocol, which BigRat and BigFloat need and BigInt does not.
//

public class BigNum {}

extension BigNum {
    /// The prefix that announces a radix, for the radices that have one.
    internal static func radixPrefix(_ radix:Int)->String {
        switch radix {
        case 2:     return "0b"
        case 8:     return "0o"
        case 16:    return "0x"
        default:    return ""
        }
    }
}
