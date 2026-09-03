import Testing
@testable import Swiftalk

@Suite("trailing closures and map/filter/reduce")
struct SequenceTests {
    @Test("trailing closures: bare, after args, on methods, chained (§2.3)")
    func trailingForms() throws {
        #expect(try eval("let f = { $0 * 2 }\nlet g = { h in h(21) }\ng { $0 * 2 }") == .int(42))
        #expect(try eval("let call2 = { a, f in f(a) }\ncall2(21) { $0 * 2 }") == .int(42))
        #expect(try eval("[1, 2, 3].map { $0 * 10 }") == .array([.int(10), .int(20), .int(30)]))
        #expect(try eval("[1, 2, 3].map() { $0 * 10 }[0]") == .int(10))   // parens + trailing
    }

    @Test("control-flow headers don't swallow trailing closures (Swift's rule)")
    func conditionsSafe() throws {
        #expect(try eval("var n = 0\nif [1].count == 1 { n = 42 }\nn") == .int(42))
        #expect(try eval("var d = [\"k\": 1]\nvar n = 0\nwhile d.has(\"k\") { d.remove(\"k\")\nn = n + 1 }\nn") == .int(1))
        // in a for-in header, parenthesize to use a trailing closure
        #expect(try eval("var s = 0\nfor x in ([1, 2].map { $0 * 2 }) { s = s + x }\ns") == .int(6))
    }

    @Test("map over the Sequence conformers (§10)")
    func map() throws {
        #expect(try eval("[1, 2, 3].map { x in x * x }") == .array([.int(1), .int(4), .int(9)]))
        #expect(try eval("\"abc\".map { $0 }") == .array([.string("a"), .string("b"), .string("c")]))
        #expect(try eval("[\"a\": 1].map { $0.1 }") == .array([.int(1)]))
        #expect(try eval("(1...3).map { $0 * $0 }") == .array([.int(1), .int(4), .int(9)]))
        #expect(throws: SwiftalkError.self) { try eval("42.map { $0 }") }
        #expect(throws: SwiftalkError.self) { try eval("[1].map(2)") }
    }

    @Test("filter: Array→Array, String→String, Dictionary→Dictionary (Swift-compatible)")
    func filter() throws {
        #expect(try eval("(1...6).filter { $0 / 2 * 2 == $0 }") == .array([.int(2), .int(4), .int(6)]))
        #expect(try eval("\"hello world\".filter { $0 != \" \" }") == .string("helloworld"))
        #expect(try eval("[\"a\": 1, \"b\": 2].filter { $0.1 == 1 }")
            == .dictionary([.string("a"): .int(1)]))
        #expect(throws: SwiftalkError.self) { try eval("[1].filter { 42 }") }   // must return Bool
    }

    @Test("reduce — and §13's fact20 example finally runs verbatim")
    func reduce() throws {
        #expect(try eval("(1...20).reduce(1) { $0 * $1 }") == .int(2432902008176640000))
        #expect(try eval("(1...10).reduce(0) { $0 + $1 }") == .int(55))
        #expect(try eval("[\"s\", \"w\", \"t\"].reduce(\"\") { $0 + $1 }") == .string("swt"))
        #expect(try eval("let sum = { $.reduce(0) { $0 + $1 } }\nsum(1, 2, 3)") == .int(6))
        #expect(throws: SwiftalkError.self) { try eval("[1].reduce(0)") }
    }

    @Test("chaining: filter → map → reduce")
    func chaining() throws {
        #expect(try eval("(1...10).filter { $0 / 2 * 2 == $0 }.map { $0 * $0 }.reduce(0) { $0 + $1 }")
            == .int(220))   // 4 + 16 + 36 + 64 + 100
    }

    @Test("d.remove(k): mutating, returns the removed value (round 37)")
    func remove() throws {
        #expect(try eval("var d = [\"a\": 1, \"b\": 2]\nd.remove(\"a\")\nd.count") == .int(1))
        #expect(try eval("var d = [\"a\": 1]\nd.remove(\"a\")") == .int(1))
        #expect(try eval("var d = [\"a\": 1]\nd.remove(\"x\")") == .nil)
        #expect(try eval("var d = [\"a\": 1]\nd.remove(\"a\")\nd.has(\"a\")") == .bool(false))
        #expect(try eval("var m = [\"d\": [\"x\": 1]]\nm[\"d\"].remove(\"x\")\nm[\"d\"]")
            == .dictionary([:]))   // mutating through a subscript path
        #expect(throws: SwiftalkError.self) { try eval("let d = [\"a\": 1]\nd.remove(\"a\")") }
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1].remove(\"a\")") }
    }

    @Test("description/debugDescription: decimal for humans, hex for programmers (round 37)")
    func descriptions() throws {
        #expect(try eval("255.description") == .string("255"))
        #expect(try eval("255.debugDescription") == .string("0xff"))
        #expect(try eval("(-16).debugDescription") == .string("-0x10"))
        #expect(try eval("(255.0).debugDescription") == .string("0x1.fep7"))
        #expect(try eval("(1.5).debugDescription") == .string("0x1.8p0"))
        #expect(try eval("(0.5).debugDescription") == .string("0x1p-1"))
        #expect(try eval("\"a\".description") == .string("a"))
        #expect(try eval("\"a\".debugDescription") == .string("\"a\""))
        #expect(try eval("[255].debugDescription") == .string("[0xff]"))
        // debug Int notation round-trips (§3d); hex floats: lexer support OPEN
        #expect(try eval("0xff") == .int(255))
    }

    @Test("debugPrint uses debugDescription: hex numbers")
    func debugPrintHex() throws {
        let interp = Interpreter()
        var out = ""
        interp.output = { out += $0 }
        _ = try interp.eval("debugPrint(255, 1.5, \"a\")")
        #expect(out == "0xff 0x1.8p0 \"a\"\n")
    }
}
