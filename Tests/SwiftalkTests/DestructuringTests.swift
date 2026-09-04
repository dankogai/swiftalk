import Testing
@testable import Swiftalk

@Suite("tuple destructuring: let (a, b) = t, and its companions (round 71)")
struct DestructuringTests {
    @Test("let (a, b) = t binds by position; var too; _ discards; nesting works")
    func declarations() throws {
        #expect(try eval("let (a, b) = (1, \"x\")\n[a, b]") == .array([.int(1), .string("x")]))
        #expect(try eval("var (a, b) = (1, 2)\na = a + b\na") == .int(3))
        #expect(try eval("let (_, b) = (1, 2)\nb") == .int(2))
        #expect(try eval("let ((a, b), c) = ((1, 2), 3)\na + b + c") == .int(6))
        #expect(try eval("let (x,) = (7,)\nx") == .int(7))
        // the names take their own type locks, as declarations do
        #expect(throws: SwiftalkError.self) { try eval("var (a, b) = (1, 2)\na = \"s\"") }
        #expect(throws: SwiftalkError.self) { try eval("let (a, b) = (1, 2)\na = 3") }
    }

    @Test("arity and kind are checked at runtime; nil elements need annotation")
    func guards() throws {
        #expect(throws: SwiftalkError.self) { try eval("let (a, b) = (1, 2, 3)") }
        #expect(throws: SwiftalkError.self) { try eval("let (a, b) = [1, 2]") }
        #expect(throws: SwiftalkError.self) { try eval("let (a, b) = 42") }
        #expect(try eval("let (a, b) = (1, nil)\nb") == .nil)      // a nil element binds since round 101 (Any)
        #expect(throws: SwiftalkError.self) { try eval("let (a, a) = (1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("let (a, b): Tuple = (1, 2)") }
    }

    @Test("destructuring assignment: the swap, and §2.4's fib verbatim at last")
    func assignment() throws {
        #expect(try eval("var a = 1\nvar b = 2\n(a, b) = (b, a)\n[a, b]") == .array([.int(2), .int(1)]))
        #expect(try eval("""
            let fib = { n in
                var (a, b) = (0, 1)
                for _ in 1...n { (a, b) = (b, a + b) }
                return a
            }
            fib(90)
            """) == .int(2880067194370816120))
        // element targets may be paths
        #expect(try eval("var xs = [0, 0]\nvar d = [:]\n(xs[1], d[\"k\"]) = (5, 6)\n[xs[1], d[\"k\"]]")
            == .array([.int(5), .int(6)]))
        #expect(throws: SwiftalkError.self) { try eval("var a = 1\nvar b = 2\n(a, b) = (1, 2, 3)") }
        #expect(throws: SwiftalkError.self) { try eval("var a = 1\n(a, 2) = (1, 2)") }
    }

    @Test("for (k, v) in dict — and over any sequence of tuples")
    func forIn() throws {
        #expect(try eval("""
            var total = 0
            for (k, v) in ["a": 40, "b": 2] { total = total + v }
            total
            """) == .int(42))
        #expect(try eval("""
            var out = []
            for (i, x) in [(0, "a"), (1, "b")] { out.append("\\(i)\\(x)") }
            out
            """) == .array([.string("0a"), .string("1b")]))
        #expect(try eval("var n = 0\nfor _ in (1, 2, 3) { n = n + 1 }\nn") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval("for (a, b) in [1, 2] { }") }
    }

    @Test("the REPL's relaxed mode distributes: (x, y) = (1, 2) declares both")
    func relaxed() throws {
        let repl = Swiftalk.Interpreter(relaxed: true)
        _ = try repl.eval("(x, y) = (1, 2)")
        #expect(try repl.eval("x + y") == .int(3))
        _ = try repl.eval("(x, y) = (y, x)")
        #expect(try repl.eval("[x, y]") == .array([.int(2), .int(1)]))
    }
}
