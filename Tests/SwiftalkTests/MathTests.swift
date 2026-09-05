import Testing
@testable import Swiftalk

@Suite("Double.pi, Double.sqrt(x), … — libm and JS's Math as static members of Double (round 108)")
struct MathTests {
    @Test("constants: Swift's names, and JS's Math extras in lowerCamel")
    func constants() throws {
        #expect(try eval("Double.pi") == .double(.pi))
        #expect(try eval("Double.tau == 2.0 * Double.pi") == .bool(true))
        #expect(try eval("Double.e") == .double(2.718281828459045))
        #expect(try eval("Double.ln2 == Double.log(2)") == .bool(true))
        #expect(try eval("Double.sqrt2 == Double.sqrt(2)") == .bool(true))
        #expect(try eval("Double.isInfinite(Double.infinity)") == .bool(true))
        #expect(try eval("Double.isNaN(Double.nan)") == .bool(true))
        #expect(try eval("Double.greatestFiniteMagnitude > 1e308") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("Double.pi()") }        // a constant, not a function
    }

    @Test("functions: Int arguments promote, results are Doubles; JS's Math and libm alike")
    func functions() throws {
        #expect(try eval("Double.sqrt(2)") == .double(2.0.squareRoot()))
        #expect(try eval("Double.pow(2, 10)") == .double(1024))
        #expect(try eval("Double.abs(-3)") == .double(3))
        #expect(try eval("Double.floor(-2.5)") == .double(-3))
        #expect(try eval("Double.ceil(-2.5)") == .double(-2))
        #expect(try eval("Double.trunc(-2.5)") == .double(-2))
        #expect(try eval("Double.round(-2.5)") == .double(-3))                  // half away from zero (C, Swift); JS gives -2
        #expect(try eval("Double.round(2.5)") == .double(3))
        #expect(try eval("Double.rint(2.5)") == .double(2))                     // to even
        #expect(try eval("Double.sign(-7)") == .double(-1))
        #expect(try eval("Double.sign(0)") == .double(0))
        #expect(try eval("Double.max(1, 2.5, -3)") == .double(2.5))
        #expect(try eval("Double.min(1, 2.5, -3)") == .double(-3))
        #expect(try eval("Double.hypot(3, 4)") == .double(5))
        #expect(try eval("Double.hypot(1, 2, 2)") == .double(3))                // JS's n-ary hypot
        #expect(try eval("Double.atan2(1, 1) * 4.0 == Double.pi") == .bool(true))
        #expect(try eval("Double.exp(0)") == .double(1))
        #expect(try eval("Double.log10(1000)") == .double(3))
        #expect(try eval("Double.log2(8)") == .double(3))
        #expect(try eval("Double.cbrt(27)") == .double(3))
        #expect(try eval("Double.expm1(0)") == .double(0))
        #expect(try eval("Double.log1p(0)") == .double(0))
        #expect(try eval("Double.sin(0)") == .double(0))
        #expect(try eval("Double.cos(0)") == .double(1))
        #expect(try eval("Double.tanh(0)") == .double(0))
        #expect(try eval("Double.asinh(0)") == .double(0))
        #expect(try eval("Double.fround(0.1)") == .double(Double(Float(0.1))))
        #expect(try eval("Double.isNaN(Double.sqrt(-1))") == .bool(true))
        #expect(try eval("Double.log(0)") == .double(-.infinity))
    }

    @Test("the libm extras: gamma, erf, Bessel, fmod/remainder/remquo, ldexp/frexp/ilogb, modf, fma, copysign, nextafter")
    func libm() throws {
        #expect(try eval("Double.tgamma(5)") == .double(24))
        #expect(try eval("Double.gamma(5)") == .double(24))
        #expect(try eval("Double.abs(Double.lgamma(5) - Double.log(24)) < 1e-12") == .bool(true))
        #expect(try eval("Double.erf(0)") == .double(0))
        #expect(try eval("Double.erfc(0)") == .double(1))
        #expect(try eval("Double.j0(0)") == .double(1))
        #expect(try eval("Double.jn(1, 0.0)") == .double(0))
        #expect(try eval("Double.fmod(7, 2)") == .double(1))
        #expect(try eval("Double.remainder(7, 2)") == .double(-1))
        #expect(try eval("Double.remquo(7, 2)") == .tuple([.double(-1), .int(4)], labels: ["remainder", "quotient"]))
        #expect(try eval("Double.ldexp(1.5, 3)") == .double(12))
        #expect(try eval("Double.scalbn(1.5, 3)") == .double(12))
        #expect(try eval("Double.frexp(8.0)") == .tuple([.double(0.5), .int(4)], labels: ["fraction", "exponent"]))
        #expect(try eval("Double.ilogb(1000)") == .int(9))
        #expect(try eval("Double.modf(3.75)") == .tuple([.double(3), .double(0.75)], labels: ["integer", "fraction"]))
        #expect(try eval("let (integer: i, fraction: f) = Double.modf(-3.75)\n[i, f]") == .array([.double(-3), .double(-0.75)]))
        #expect(try eval("Double.fma(2, 3, 4)") == .double(10))
        #expect(try eval("Double.copysign(3, -1)") == .double(-3))
        #expect(try eval("Double.nextafter(1, 2) > 1.0") == .bool(true))
        #expect(try eval("Double.fdim(5, 3)") == .double(2))
        #expect(try eval("Double.fmax(1, Double.nan)") == .double(1))
    }

    @Test("Double.random() in [0, 1); a function member uncalled is a Function value; errors")
    func randomAndValues() throws {
        #expect(try eval("let r = Double.random()\nr >= 0.0 && r < 1.0") == .bool(true))
        #expect(try eval("(1...100).map { Double.random() }.filter { $0 >= 1.0 }.count") == .int(0))
        #expect(try eval("[1.0, 4.0, 9.0].map(Double.sqrt)") == .array([.double(1), .double(2), .double(3)]))
        #expect(try eval("let f = Double.pow\nf(2, 3)") == .double(8))
        #expect(try eval("Double.sqrt.Type == Function") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("Double.sqrt()") }
        #expect(throws: SwiftalkError.self) { try eval("Double.sqrt(1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("Double.sqrt(\"x\")") }
        #expect(throws: SwiftalkError.self) { try eval("Double.nope") }
        #expect(throws: SwiftalkError.self) { try eval("Double.pow(x: 1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("Double.random(1)") }
        #expect(throws: SwiftalkError.self) { try eval("Double.ldexp(1.5, 2.0)") }
        #expect(throws: SwiftalkError.self) { try eval("Int.sqrt(4)") }         // Double's, not Int's
        // the type's own members are untouched
        #expect(try eval("Double.name") == .string("Double"))
        #expect(try eval("Double.conforms(to: Comparable)") == .bool(true))
    }
}
