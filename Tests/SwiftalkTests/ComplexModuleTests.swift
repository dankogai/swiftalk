import Testing
@testable import Swiftalk

/// modules/Complex.swt, loaded from the repository as a script would load it.
@Suite("modules/Complex.swt — std::complex<double> in swiftalk (round 147)")
struct ComplexModuleTests {
    static let root: String = {
        var parts = #filePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        parts.removeLast(3)                      // Tests/SwiftalkTests/ComplexModuleTests.swift
        return parts.joined(separator: "/")
    }()

    func interpreter() -> Swiftalk.Interpreter {
        let i = Swiftalk.Interpreter()
        i.scriptPath = Self.root + "/eg/_.swt"   // imports resolve beside this
        return i
    }
    let prelude = "import from \"../modules/Complex.swt\"\nlet near = { a, b in (Complex.lift(a) - Complex.lift(b)).abs < 1e-9 }\n"

    @Test("arithmetic, either side a scalar; conj, norm, abs, arg, polar, proj; i")
    func arithmetic() throws {
        let i = interpreter()
        _ = try i.eval(prelude)
        #expect(try i.eval("let z = Complex(1.0, 2.0)\nz * z.conj == z.norm") == .bool(true))
        #expect(try i.eval("Complex(0.0, 1.0) * Complex(0.0, 1.0) == Complex(-1.0)") == .bool(true))
        #expect(try i.eval("(Complex(1.0, 2.0) + 1) == Complex(2.0, 2.0)") == .bool(true))
        #expect(try i.eval("(2.0 * Complex(1.0, 2.0)) == Complex(2.0, 4.0)") == .bool(true))
        #expect(try i.eval("(Complex(4.0, 2.0) / 2) == Complex(2.0, 1.0)") == .bool(true))
        #expect(try i.eval("near(Complex(1.0, 2.0) / Complex(3.0, 4.0), Complex(0.44, 0.08))") == .bool(true))
        #expect(try i.eval("(1 - Complex(0.0, 1.0)) == Complex(1.0, -1.0)") == .bool(true))
        #expect(try i.eval("-Complex(1.0, -2.0) == Complex(-1.0, 2.0)") == .bool(true))
        #expect(try i.eval("+Complex(1.0, 2.0) == Complex(1.0, 2.0)") == .bool(true))
        #expect(try i.eval("Complex(3.0, 4.0).abs") == .double(5))
        #expect(try i.eval("Complex.abs(Complex(3.0, 4.0))") == .double(5))
        #expect(try i.eval("Complex(3.0, 4.0).norm") == .double(25))
        #expect(try i.eval("Complex(0.0, 1.0).arg == Double.pi / 2.0") == .bool(true))
        #expect(try i.eval("Complex.arg(-1.0) == Double.pi") == .bool(true))
        #expect(try i.eval("near(Complex.polar(2.0, Double.pi), Complex(-2.0, 0.0))") == .bool(true))
        #expect(try i.eval("Complex(Double.infinity, -3.0).proj == Complex(Double.infinity, -0.0)") == .bool(true))
        #expect(try i.eval("Complex(1.0, 2.0).proj == Complex(1.0, 2.0)") == .bool(true))
        #expect(try i.eval("Complex(1.0, 2.0).i == Complex(-2.0, 1.0)") == .bool(true))
        #expect(try i.eval("Double.pi.i == Complex(0.0, Double.pi)") == .bool(true))       // a module's extension Double reaches the importer
        #expect(try i.eval("3.i == Complex(0.0, 3.0)") == .bool(true))
        #expect(try i.eval("Complex(1.0) != Complex(1.0, 0.1)") == .bool(true))
        #expect(try i.eval("Complex(2.0) == 2.0") == .bool(true))
        #expect(try i.eval("var w = Complex(1.0)\nw *= Complex(0.0, 1.0)\nw += 1\nw == Complex(1.0, 1.0)") == .bool(true))
        #expect(try i.eval("[Complex(1.0), Complex(0.0, 1.0)].reduce(Complex(), +) == Complex(1.0, 1.0)") == .bool(true))
        #expect(try i.eval("(*)(Complex(0.0, 1.0), Complex(0.0, 1.0)).real") == .double(-1))
        #expect(try i.eval("Complex(1.0, 2.0).String()") == .string("Complex(real: 1.0, imag: 2.0)"))
        #expect(throws: SwiftalkError.self) { try i.eval("Complex(1, 2)") }                 // Doubles, as std::complex<double>
        #expect(throws: SwiftalkError.self) { try i.eval("Complex(1.0) < Complex(2.0)") }   // no order, as in C++
    }

    @Test("exp, log, log10, pow, sqrt, **; the trigonometric and hyperbolic functions and their inverses — C99 values, cuts included")
    func functions() throws {
        let i = interpreter()
        _ = try i.eval(prelude)
        #expect(try i.eval("near(Complex.exp(Double.pi.i), -1.0)") == .bool(true))          // Euler
        #expect(try i.eval("near(Complex.log(Complex(-1.0)), Double.pi.i)") == .bool(true))
        #expect(try i.eval("near(Complex.log10(Complex(100.0)), 2.0)") == .bool(true))
        #expect(try i.eval("Complex.sqrt(Complex(-4.0)) == Complex(0.0, 2.0)") == .bool(true))
        #expect(try i.eval("near(Complex.sqrt(Complex(0.0, 2.0)), Complex(1.0, 1.0))") == .bool(true))
        #expect(try i.eval("near(Complex.pow(Complex(0.0, 1.0), 2.0), -1.0)") == .bool(true))
        #expect(try i.eval("near(Complex(0.0, 1.0) ** 2, -1.0)") == .bool(true))
        #expect(try i.eval("near(Complex.pow(2.0, Complex(0.0, 0.0)), 1.0)") == .bool(true))
        #expect(try i.eval("Complex.pow(Complex(), Complex(2.0)) == Complex()") == .bool(true))
        #expect(try i.eval("near(Complex.pow(Complex(0.0, 1.0), Complex(0.0, 1.0)), Double.exp(-Double.pi / 2.0))") == .bool(true))   // i^i
        #expect(try i.eval("near(Complex.sin(Complex(1.0, 2.0)), Complex(3.165778513216168, 1.9596010414216063))") == .bool(true))
        #expect(try i.eval("near(Complex.cos(Complex(1.0, 2.0)), Complex(2.0327230070196656, -3.0518977991518))") == .bool(true))
        #expect(try i.eval("near(Complex.tan(Complex(1.0, 2.0)), Complex(0.0338128260798967, 1.0147936161466335))") == .bool(true))
        #expect(try i.eval("near(Complex.sinh(Complex(1.0, 2.0)), Complex(-0.4890562590412937, 1.4031192506220405))") == .bool(true))
        #expect(try i.eval("near(Complex.cosh(Complex(1.0, 2.0)), Complex(-0.64214812471552, 1.0686074213827783))") == .bool(true))
        #expect(try i.eval("near(Complex.tanh(Complex(1.0, 2.0)), Complex(1.16673625724092, -0.2434582011857252))") == .bool(true))
        #expect(try i.eval("near(Complex.asin(Complex(2.0)), Complex(1.5707963267948966, 1.3169578969248166))") == .bool(true))     // the cut: +0i from above
        #expect(try i.eval("near(Complex.asin(Complex(2.0, -0.0)), Complex(1.5707963267948966, -1.3169578969248166))") == .bool(true))
        #expect(try i.eval("near(Complex.acos(Complex(2.0)), Complex(0.0, -1.3169578969248166))") == .bool(true))
        #expect(try i.eval("near(Complex.atan(Complex(0.0, 2.0)), Complex(1.5707963267948966, 0.5493061443340549))") == .bool(true))
        #expect(try i.eval("near(Complex.asinh(Complex(0.0, -2.0)), Complex(1.3169578969248166, -1.5707963267948966))") == .bool(true))
        #expect(try i.eval("near(Complex.acosh(Complex(0.5)), Complex(0.0, 1.0471975511965979))") == .bool(true))
        #expect(try i.eval("near(Complex.atanh(Complex(2.0)), Complex(0.5493061443340549, 1.5707963267948966))") == .bool(true))
        #expect(try i.eval("near(Complex.asin(Complex.sin(Complex(0.3, -0.7))), Complex(0.3, -0.7))") == .bool(true))
        #expect(try i.eval("near(Complex.atanh(Complex.tanh(Complex(0.3, -0.7))), Complex(0.3, -0.7))") == .bool(true))
        #expect(try i.eval("near(Complex.exp(Complex.log(Complex(-3.0, 4.0))), Complex(-3.0, 4.0))") == .bool(true))
        #expect(try i.eval("Complex.sqrt.Type == Function && Complex.exp(1.0).Type == Complex") == .bool(true))
        #expect(try i.eval("[1.0, 2.0].map(Complex.sqrt).count") == .int(2))
    }
}
