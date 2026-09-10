import Testing
@testable import Swiftalk

/// modules/Rational.swt, loaded from the repository as a script would load it.
@Suite("modules/Rational.swt — exact fractions in swiftalk (round 149)")
struct RationalModuleTests {
    static let root: String = {
        var parts = #filePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        parts.removeLast(3)
        return parts.joined(separator: "/")
    }()
    func interpreter() throws -> Swiftalk.Interpreter {
        let i = Swiftalk.Interpreter()
        i.scriptPath = Self.root + "/eg/_.swt"
        _ = try i.eval("import from \"../modules/Rational.swt\"")
        return i
    }

    @Test("construction normalizes; from Int, Double (exactly), String, Rational; statics and conversions")
    func construction() throws {
        let i = try interpreter()
        #expect(try i.eval("Rational(6, -8)") == .structValue(try sv(i, -3, 4)))
        #expect(try i.eval("Rational(2, 4) == Rational(1, 2)") == .bool(true))
        #expect(try i.eval("Rational(0, 5).fraction") == .string("0"))
        #expect(try i.eval("Rational(7).fraction") == .string("7"))
        #expect(try i.eval("Rational(0.75) == Rational(3, 4)") == .bool(true))
        #expect(try i.eval("Rational(-2.5) == Rational(-5, 2)") == .bool(true))
        #expect(try i.eval("Rational(0.1).num") == .int(3602879701896397))                 // 0.1 exactly, as the Double is
        #expect(try i.eval("Rational(0.1).den") == .int(36028797018963968))
        #expect(try i.eval("Rational(\"-6/8\").fraction") == .string("-3/4"))
        #expect(try i.eval("Rational(\"5\").isInteger") == .bool(true))
        #expect(try i.eval("Rational(Rational(1, 3)).fraction") == .string("1/3"))
        #expect(try i.eval("3.Rational() / 4 == Rational(3, 4)") == .bool(true))
        #expect(try i.eval("0.75.Rational().fraction") == .string("3/4"))
        #expect(try i.eval("Rational.zero == 0 && Rational.one == 1") == .bool(true))
        #expect(try i.eval("Rational.gcd(12, -18)") == .int(6))
        #expect(try i.eval("Rational.lcm(4, 6)") == .int(12))
        #expect(try i.eval("Rational(7, 4).Double()") == .double(1.75))
        #expect(try i.eval("Rational(-7, 4).Int()") == .int(-1))
        #expect(try i.eval("[Rational(1, 2): \"half\"][Rational(2, 4)]") == .string("half"))   // normalized, so a key
        #expect(throws: SwiftalkError.self) { try i.eval("Rational(1, 0)") }                 // division by zero
        #expect(throws: SwiftalkError.self) { try i.eval("Rational(\"x/y\")") }
        #expect(throws: SwiftalkError.self) { try i.eval("Rational(1, 2, 3)") }
    }

    @Test("arithmetic with Ints lifting and Doubles taking over; **; comparisons; sorted/min/max; properties")
    func arithmetic() throws {
        let i = try interpreter()
        #expect(try i.eval("Rational(1, 2) + Rational(1, 3)") == .structValue(try sv(i, 5, 6)))
        #expect(try i.eval("Rational(1, 2) - Rational(1, 3) == Rational(1, 6)") == .bool(true))
        #expect(try i.eval("Rational(2, 3) * Rational(3, 4) == Rational(1, 2)") == .bool(true))
        #expect(try i.eval("Rational(1, 2) / Rational(1, 4) == 2") == .bool(true))
        #expect(try i.eval("Rational(3, 4) + 1 == Rational(7, 4)") == .bool(true))
        #expect(try i.eval("1 - Rational(3, 4) == Rational(1, 4)") == .bool(true))
        #expect(try i.eval("2 * Rational(3, 4) == Rational(3, 2)") == .bool(true))
        #expect(try i.eval("Rational(1, 3) + 0.5") == .double(1.0 / 3.0 + 0.5))             // a Double wins
        #expect(try i.eval("0.5 * Rational(1, 2)") == .double(0.25))
        #expect(try i.eval("(Rational(3, 4) ** 2).fraction") == .string("9/16"))
        #expect(try i.eval("(Rational(3, 4) ** -2).fraction") == .string("16/9"))
        #expect(try i.eval("(Rational(3, 4) ** 0).fraction") == .string("1"))
        #expect(try i.eval("Rational(1, 4) ** 0.5") == .double(0.5))
        #expect(try i.eval("-Rational(1, 2) == Rational(-1, 2)") == .bool(true))
        #expect(try i.eval("var r = Rational(1, 2)\nr += Rational(1, 2)\nr *= 3\nr == 3") == .bool(true))
        #expect(try i.eval("Rational(1, 3) < Rational(1, 2) && Rational(1, 2) > Rational(1, 3)") == .bool(true))
        #expect(try i.eval("Rational(1, 2) <= Rational(2, 4) && Rational(1, 2) >= Rational(1, 3)") == .bool(true))
        #expect(try i.eval("Rational(1, 2) < 1 && Rational(3, 2) > 1") == .bool(true))
        #expect(try i.eval("Rational(1, 2) == 0.5 && Rational(1, 3) != 0.5") == .bool(true))
        #expect(try i.eval("[Rational(1, 2), Rational(1, 3), Rational(2, 3)].sorted().map { $0.fraction }") == .array([.string("1/3"), .string("1/2"), .string("2/3")]))
        #expect(try i.eval("[Rational(1, 2), Rational(1, 3)].min().fraction") == .string("1/3"))
        #expect(try i.eval("Rational.conforms(to: Comparable)") == .bool(true))
        #expect(try i.eval("[Rational(1, 2), Rational(1, 3)].reduce(Rational.zero, +).fraction") == .string("5/6"))
        #expect(try i.eval("Rational(-3, 4).abs.fraction") == .string("3/4"))
        #expect(try i.eval("[Rational(-1, 2).sign, Rational.zero.sign, Rational(1, 2).sign]") == .array([.int(-1), .int(0), .int(1)]))
        #expect(try i.eval("Rational(3, 4).reciprocal.fraction") == .string("4/3"))
        #expect(try i.eval("Rational(-7, 4).floor") == .int(-2))
        #expect(try i.eval("Rational(-7, 4).ceil") == .int(-1))
        #expect(try i.eval("Rational(-7, 4).truncated") == .int(-1))
        #expect(try i.eval("[Rational(5, 2).rounded, Rational(-5, 2).rounded, Rational(7, 4).rounded]") == .array([.int(3), .int(-3), .int(2)]))
        #expect(try i.eval("Rational(7, 4).mixed.whole") == .int(1))
        #expect(try i.eval("Rational(7, 4).mixed.part == Rational(3, 4)") == .bool(true))
        #expect(throws: SwiftalkError.self) { try i.eval("Rational(1, 2) / 0") }
        #expect(throws: SwiftalkError.self) { try i.eval("Rational(Int.max, 1) + Rational(1, 1)") }   // overflow traps, as Int's does
    }

    private func sv(_ i: Swiftalk.Interpreter, _ n: Int64, _ d: Int64) throws -> Swiftalk.StructValue {
        guard case .structValue(let v) = try i.eval("Rational(\(n), \(d))") else { throw SwiftalkError.type("no") }
        return v
    }
}
