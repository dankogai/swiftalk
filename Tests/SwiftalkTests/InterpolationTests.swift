import Testing
@testable import Swiftalk

@Suite("string interpolation, Swift-style (§2.5)")
struct InterpolationTests {
    @Test("expressions interpolate; Strings embed raw, other types as source form")
    func basics() throws {
        #expect(try eval(#""1 + 1 = \(1 + 1)""#) == .string("1 + 1 = 2"))
        #expect(try eval(#""hello, \("world")""#) == .string("hello, world"))
        #expect(try eval(#""\(1)\(2)""#) == .string("12"))
        #expect(try eval(#""\(0.1 + 0.2)""#) == .string("0.30000000000000004"))
        #expect(try eval(#""\(nil)/\(true)/\([1, "a"])""#) == .string(#"nil/true/[1, "a"]"#))
        #expect(try eval("let n = 6\n\"n * 7 = \\(n * 7)\"") == .string("n * 7 = 42"))
    }

    @Test("any expression fits: calls, subscripts, ternary, $")
    func expressions() throws {
        #expect(try eval("let sq = { x in x * x }\n\"\\(sq(8))\"") == .string("64"))
        #expect(try eval(#"let d = ["k": 42]"# + "\n" + #""\(d["k"])""#) == .string("42"))
        #expect(try eval(#""\(1 < 2 ? "y" : "n")""#) == .string("y"))
        #expect(try eval(#"{ "got \($.count)" }(1, 2, 3)"#) == .string("got 3"))
    }

    @Test("nesting: a string inside an interpolation may itself interpolate")
    func nesting() throws {
        #expect(try eval(#""\("a\(1)b")c""#) == .string("a1bc"))
        #expect(try eval(#""\("x\("y\(0)")")""#) == .string("xy0"))
    }

    @Test("escapes stay escapes: \\\\( is a literal backslash, not interpolation")
    func escapes() throws {
        #expect(try eval(#""\\(1)""#) == .string(#"\(1)"#))
        #expect(try eval(#""paren \(40 + 2) (bare)""#) == .string("paren 42 (bare)"))
    }

    @Test("results are ordinary Strings: type, count, round-trip (§3d)")
    func resultsAreStrings() throws {
        #expect(try eval(#""\(42)".type"#) == .string("String"))
        #expect(try eval(#""\(1...3)".count"#) == .int(5))   // "1...3" — Range's own form (round 38)
        let v = try eval(#""quote \" and \(1)""#)
        #expect(try eval(v.sourceString()) == v)             // eval(x.String()) == x
    }

    @Test("malformed interpolation is a syntax error")
    func errors() throws {
        for bad in [#""\(1""#, #""\()""#, #""\(1; 2)""#] {
            #expect(throws: SwiftalkError.self, "expected error for: \(bad)") {
                try eval(bad)
            }
        }
    }
}
