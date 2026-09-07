import Testing
@testable import Swiftalk

@Suite("eval() in the language — source in, value out, at the top level (round 122)")
struct EvalBuiltinTests {
    @Test("the last statement's value; the round-trip law, in the language")
    func basics() throws {
        #expect(try eval("eval(\"1 + 2\")") == .int(3))
        #expect(try eval("eval(\"let x = 40\\nx + 2\")") == .int(42))
        #expect(throws: SwiftalkError.self) { try eval("eval(\"\")") }              // an empty program, as at the top
        #expect(try eval("eval(\"eval(\\\"3\\\")\")") == .int(3))
        let v = "let v: SION = [\"a\": [1, 2.5, nil], \"d\": Data(\"AQID\"), \"t\": .Date(0.0)]\n"
        #expect(try eval(v + "eval(v.String()) == v") == .bool(true))
        #expect(try eval(v + "eval(v.String(.pretty)) == v") == .bool(true))
        #expect(try eval("eval(\"hi\".String(.quoted)) == \"hi\"") == .bool(true))
        #expect(try eval("eval(255.String(.hex)) == 255") == .bool(true))
        #expect(try eval("struct P { var x: Int = 0 }\nlet p = P(x: 3)\neval(p.String()) == p") == .bool(true))
        #expect(try eval("enum E { case v(Int) }\neval(E.v(7).String()) == E.v(7)") == .bool(true))
        #expect(try eval("eval((x: 1, [2]).String()) == (x: 1, [2])") == .bool(true))
    }

    @Test("it runs at the program's top level: sees it, declares into it, not a caller's locals")
    func scope() throws {
        #expect(try eval("let n = 5\neval(\"n * 2\")") == .int(10))
        #expect(try eval("var n = 5\neval(\"n = 6\")\nn") == .int(6))
        #expect(try eval("eval(\"let y = 1\")\ny") == .int(1))
        #expect(try eval("eval(\"struct Q { var a: Int = 1 }\")\nQ().a") == .int(1))
        #expect(throws: SwiftalkError.self) { try eval("let f = { a in eval(\"a\") }\nf(1)") }
        #expect(throws: SwiftalkError.self) { try eval("let z = 1\neval(\"let z = 2\")") }      // redeclaration, as at the top
        #expect(try eval("let e = eval\ne(\"2\")") == .int(2))
        #expect(try eval("eval.Type == Function") == .bool(true))
        #expect(try eval("[\"1\", \"2\"].map(eval)") == .array([.int(1), .int(2)]))
    }

    @Test("errors are the language's: a syntax error, a wrong argument, control flow outside its place")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("eval(\"1 +\")") }
        #expect(throws: SwiftalkError.self) { try eval("eval(1)") }
        #expect(throws: SwiftalkError.self) { try eval("eval()") }
        #expect(throws: SwiftalkError.self) { try eval("eval(\"a\", \"b\")") }
        #expect(throws: SwiftalkError.self) { try eval("eval(\"break\")") }
        #expect(throws: SwiftalkError.self) { try eval("eval(\"return 1\")") }
        #expect(throws: SwiftalkError.self) { try eval("eval(\"nope\")") }
    }
}
