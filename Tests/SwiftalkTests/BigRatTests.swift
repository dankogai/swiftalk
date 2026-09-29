import Testing
@testable import Swiftalk

// Round 203: `BigRat` — exact rationals as a prelude module beside BigInt,
// the same engine (swift-bignum, vendored as modules/BigNum).

@Suite("BigRat: construction and the source form")
struct BigRatConstructionTests {
    @Test("BigRat(n, d) reduces; the sign lives in the numerator; the source form re-enters")
    func construct() throws {
        #expect(try eval("BigRat(2, 6).String()") == .string("BigRat(1, 3)"))
        #expect(try eval("BigRat(1, -3).String()") == .string("BigRat(-1, 3)"))
        #expect(try eval("BigRat(6, 3).String()") == .string("BigRat(2, 1)"))
        #expect(try eval("BigRat(2n ** 70n, 3).numerator") == (try eval("2n ** 70n")))
        #expect(try eval("BigRat(3).String()") == .string("BigRat(3, 1)"))
        #expect(try eval("BigRat().isZero") == .bool(true))
        #expect(try eval("BigRat(7n).denominator") == (try eval("1n")))
        #expect(try eval("BigRat(Byte(3)) == BigRat(3)") == .bool(true))
        #expect(try eval("BigRat(BigRat(1, 3)) == BigRat(1, 3)") == .bool(true))
        #expect(try eval("BigRat(1, 3).Type == BigRat") == .bool(true))
        #expect(try eval("BigRat(7, 3).debugDescription") == .string("BigRat(+0x7n, +0x3n)"))
        #expect(try eval("eval(\"BigRat(-7, 3)\")! == BigRat(-7, 3)") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1, 0)") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1.0, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(true)") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1, 2, 3)") }
    }

    @Test("from a Double, exactly; from text: n/d, an integer, a decimal, an exponent")
    func fromDoubleAndText() throws {
        #expect(try eval("BigRat(0.1).String()") == .string("BigRat(3602879701896397, 36028797018963968)"))
        #expect(try eval("BigRat(0.5) == BigRat(1, 2)") == .bool(true))
        #expect(try eval("BigRat(-2.0).String()") == .string("BigRat(-2, 1)"))
        #expect(try eval("BigRat(\"0.1\") == BigRat(1, 10)") == .bool(true))
        #expect(try eval("BigRat(\"-2/3\") == BigRat(-2, 3)") == .bool(true))
        #expect(try eval("BigRat(\"1e-2\") == BigRat(1, 100)") == .bool(true))
        #expect(try eval("BigRat(\"1.5e3\") == BigRat(1500)") == .bool(true))
        #expect(try eval("BigRat(\"0x10/3n\") == BigRat(16, 3)") == .bool(true))
        #expect(try eval("BigRat(\"42\") == BigRat(42)") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("BigRat(\"1/0\")") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(\"third\")") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(Double.infinity)") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(Double.nan)") }
    }

    @Test("the literal is nothing; the module is what the CLI preimports, importable bare")
    func module() throws {
        let bare = Swiftalk.Interpreter()
        #expect(throws: SwiftalkError.self) { try bare.eval("BigRat(1, 2)") }
        bare.modulePath = [buildDirectory()].compactMap { $0 }
        #expect(try bare.eval("import from \"BigRat\"\nBigRat(1, 2).Double()") == .double(0.5))
        // r.numerator is the BigInt module's value — without it, an error naming the module
        #expect(throws: SwiftalkError.self) { try bare.eval("BigRat(1, 2).numerator") }
        #expect(try bare.eval("import from \"BigInt\"\nBigRat(1, 2).numerator") == (try bare.eval("1n")))
    }
}

@Suite("BigRat: arithmetic and members")
struct BigRatArithmeticTests {
    @Test("+ - * / exact; ** with a negative exponent; the prefixes")
    func operators() throws {
        #expect(try eval("BigRat(1, 3) + BigRat(1, 6) == BigRat(1, 2)") == .bool(true))
        #expect(try eval("BigRat(1, 3) + BigRat(1, 3) + BigRat(1, 3) == BigRat(1)") == .bool(true))
        #expect(try eval("BigRat(1, 3) - BigRat(1, 2) == BigRat(-1, 6)") == .bool(true))
        #expect(try eval("BigRat(2, 3) * BigRat(3, 4) == BigRat(1, 2)") == .bool(true))
        #expect(try eval("BigRat(2, 3) / BigRat(4, 3) == BigRat(1, 2)") == .bool(true))
        #expect(try eval("BigRat(7, 3) ** 2 == BigRat(49, 9)") == .bool(true))
        #expect(try eval("BigRat(7, 3) ** -2 == BigRat(9, 49)") == .bool(true))
        #expect(try eval("BigRat(7, 3) ** 2n == BigRat(49, 9)") == .bool(true))
        #expect(try eval("(-BigRat(1, 3)).String()") == .string("BigRat(-1, 3)"))
        #expect(try eval("+BigRat(1, 3) == BigRat(1, 3)") == .bool(true))
        #expect(try eval("var r = BigRat(1)\nr += BigRat(1, 2)\nr *= BigRat(2)\nr") == (try eval("BigRat(3)")))
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1) / BigRat(0)") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(0) ** -1") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1, 2) ** BigRat(1, 2)") }
    }

    @Test("strict: a BigRat meets a BigRat — an Int, a Double, a BigInt must convert")
    func strict() throws {
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1, 2) + 1") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1, 2) * 3n") }
        #expect(throws: SwiftalkError.self) { try eval("3n * BigRat(1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1, 2) + 0.5") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1, 2) == 0.5") }
        #expect(try eval("BigRat(1, 2) * BigRat(3n) == BigRat(3, 2)") == .bool(true))
    }

    @Test("comparison; sorting, min, max; Dictionary keys; switch")
    func comparable() throws {
        #expect(try eval("BigRat(1, 3) < BigRat(1, 2)") == .bool(true))
        #expect(try eval("BigRat(1, 3) >= BigRat(1, 2)") == .bool(false))
        #expect(try eval("BigRat(2, 4) == BigRat(1, 2)") == .bool(true))
        #expect(try eval("[BigRat(1, 2), BigRat(1, 3), BigRat(2, 3)].sorted().String()") == .string("[BigRat(1, 3), BigRat(1, 2), BigRat(2, 3)]"))
        #expect(try eval("[BigRat(1, 2), BigRat(1, 3)].min() == BigRat(1, 3)") == .bool(true))
        #expect(try eval("[BigRat(2, 4): \"half\"][BigRat(1, 2)]") == .string("half"))
        #expect(try eval("Set([BigRat(1, 2), BigRat(2, 4)]).count") == .int(1))
        #expect(try eval("switch BigRat(7, 3) { case BigRat(14, 6): \"same\" default: \"no\" }") == .string("same"))
        #expect(try eval("switch 2 { case BigRat(2): 1 default: 2 }") == .int(2))
    }

    @Test("conversions: Double, BigInt, Int (truncation); rounding rules; the members")
    func members() throws {
        #expect(try eval("BigRat(7, 3).Double()") == .double(2.3333333333333335))
        #expect(try eval("Double(BigRat(1, 4))") == .double(0.25))
        #expect(try eval("BigRat(7, 3).BigInt()") == (try eval("2n")))
        #expect(try eval("BigRat(-7, 3).BigInt()") == (try eval("-2n")))
        #expect(try eval("BigInt(BigRat(7, 3))") == (try eval("2n")))
        #expect(try eval("BigRat(-7, 3).Int()") == .int(-2))
        #expect(throws: SwiftalkError.self) { try eval("BigRat(2n ** 70n, 1).Int()") }
        #expect(try eval("BigRat(7, 3).rounded() == BigRat(2)") == .bool(true))
        #expect(try eval("BigRat(5, 2).rounded() == BigRat(3)") == .bool(true))              // away from zero
        #expect(try eval("BigRat(5, 2).rounded(.toNearestOrEven) == BigRat(2)") == .bool(true))
        #expect(try eval("BigRat(-7, 3).rounded(.down) == BigRat(-3)") == .bool(true))
        #expect(try eval("BigRat(-7, 3).rounded(.up) == BigRat(-2)") == .bool(true))
        #expect(try eval("BigRat(-7, 3).rounded(.towardZero) == BigRat(-2)") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1, 2).rounded(.sideways)") }
        #expect(try eval("BigRat(7, 3).numerator") == (try eval("7n")))
        #expect(try eval("BigRat(7, 3).denominator") == (try eval("3n")))
        #expect(try eval("BigRat(6, 3).isInteger && !BigRat(7, 3).isInteger") == .bool(true))
        #expect(try eval("BigRat(-7, 3).magnitude == BigRat(7, 3)") == .bool(true))
        #expect(try eval("BigRat(-7, 3).signum") == .int(-1))
        #expect(try eval("BigRat(7, 3).reciprocal == BigRat(3, 7)") == .bool(true))
        #expect(try eval("BigRat(7, 3).power(-2) == BigRat(9, 49)") == .bool(true))
        #expect(try eval("BigRat(7, 3).String(.fraction)") == .string("7/3"))
        #expect(try eval("BigRat(7, 3).String(.mixed)") == .string("2 1/3"))
        #expect(try eval("BigRat(-7, 3).String(.mixed)") == .string("-2 1/3"))
        #expect(try eval("BigRat(-1, 3).String(.mixed)") == .string("-1/3"))
        #expect(try eval("BigRat(6, 3).String(.mixed)") == .string("2"))
        #expect(throws: SwiftalkError.self) { try eval("BigRat(0).reciprocal") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1, 2).String(.hex)") }
        #expect(throws: SwiftalkError.self) { try eval("BigRat(1, 2).nope") }
    }
}
