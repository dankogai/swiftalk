import Testing
@testable import Swiftalk

@Suite("if let (a, b) = t; for k, v in d; tuple splat into parameters (round 72)")
struct IfLetDestructureTests {
    @Test("if let destructures a non-nil tuple; nil takes the else; misfit is an error")
    func ifLet() throws {
        #expect(try eval("""
            let d = ["k": (1, 2)]
            var out = 0
            if let (a, b) = d["k"] { out = a + b } else { out = -1 }
            out
            """) == .int(3))
        #expect(try eval("""
            let d = ["k": (1, 2)]
            var out = 0
            if let (a, b) = d["x"] { out = a + b } else { out = -1 }
            out
            """) == .int(-1))
        #expect(try eval("var out = 0\nif var (a, b) = (1, 2) { a = a * 10\nout = a + b }\nout") == .int(12))
        // chains with booleans, later clauses seeing the names
        #expect(try eval("var out = \"?\"\nif let (a, b) = (1, 5), a < b { out = \"\\(a)<\\(b)\" }\nout")
            == .string("1<5"))
        #expect(throws: SwiftalkError.self) { try eval("if let (a, b) = (1, 2, 3) { }") }
        #expect(throws: SwiftalkError.self) { try eval("if let (a, b) = 42 { }") }
    }

    @Test("for k, v in d — parentheses optional; names must be distinct")
    func forCommaNames() throws {
        #expect(try eval("""
            var total = 0
            for k, v in ["a": 40, "b": 2] { total = total + v }
            total
            """) == .int(42))
        #expect(try eval("""
            var out = []
            for i, x in [(0, "a"), (1, "b")] { out.append("\\(i)\\(x)") }
            out
            """) == .array([.string("0a"), .string("1b")]))
        #expect(throws: SwiftalkError.self) { try eval("for k, k in [\"a\": 1] { }") }
    }

    @Test("d.map { k, v in } — the pair splats into two parameters; filter, too")
    func dictionaryClosures() throws {
        #expect(try eval("[\"a\": 1].map { k, v in \"\\(k)=\\(v)\" }") == .array([.string("a=1")]))
        #expect(try eval("[\"a\": 1, \"b\": 2].filter { k, v in v > 1 }")
            == .dictionary([.string("b"): .int(2)]))
        // reduce passes (accumulator, pair): the pair stays a tuple
        #expect(try eval("[\"a\": 1, \"b\": 2].reduce(0) { acc, kv in acc + kv.1 }") == .int(3))
        // a param-less closure gets the tuple itself as $0 — no splat
        #expect(try eval("[\"a\": 1].map { $0.Type == Tuple }") == .array([.bool(true)]))
    }

    @Test("the general rule: one N-tuple argument spreads into N parameters")
    func splat() throws {
        #expect(try eval("let f = { x, y in x + y }\nf((40, 2))") == .int(42))
        #expect(try eval("let f = { x, y in x + y }\nlet pair = (40, 2)\nf(pair)") == .int(42))
        #expect(try eval("[(1, 2), (3, 4)].map { a, b in a * b }") == .array([.int(2), .int(12)]))
        // arity still rules: a 3-tuple into two parameters is an error
        #expect(throws: SwiftalkError.self) { try eval("let f = { x, y in x }\nf((1, 2, 3))") }
        // a one-parameter function takes the tuple whole
        #expect(try eval("let g = { t in t.count }\ng((1, 2))") == .int(2))
        // $ sees the spread arguments
        #expect(try eval("let f = { x, y in $.count }\nf((1, 2))") == .int(2))
    }
}
