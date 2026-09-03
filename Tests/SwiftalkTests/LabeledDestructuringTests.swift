import Testing
@testable import Swiftalk

@Suite("labeled destructuring: let (x: a, y: b) = t — by label, reorderable (round 75)")
struct LabeledDestructuringTests {
    @Test("let/var bind by label; order is free; positions still bind unlabeled")
    func declarations() throws {
        #expect(try eval("let (x: a, y: b) = (x: 1, y: 2)\n[a, b]") == .array([.int(1), .int(2)]))
        #expect(try eval("let (y: b, x: a) = (x: 1, y: 2)\n[a, b]") == .array([.int(1), .int(2)]))
        #expect(try eval("var (x: a, y: b) = (x: 1, y: 2)\na = a + b\na") == .int(3))
        #expect(try eval("let (a, y: b) = (1, y: 2)\n[a, b]") == .array([.int(1), .int(2)]))
        #expect(try eval("let (x: _, y: b) = (x: 1, y: 2)\nb") == .int(2))
        #expect(try eval("let (p: (x: a, y: b), n: c) = (p: (x: 1, y: 2), n: 3)\na + b + c") == .int(6))
    }

    @Test("guards: missing label, duplicate label, arity still rigid")
    func guards() throws {
        #expect(throws: SwiftalkError.self) { try eval("let (x: a, z: b) = (x: 1, y: 2)") }
        #expect(throws: SwiftalkError.self) { try eval("let (x: a, x: b) = (x: 1, y: 2)") }
        #expect(throws: SwiftalkError.self) { try eval("let (x: a) = (x: 1, y: 2)") }
        #expect(throws: SwiftalkError.self) { try eval("let (x: a, y: b) = (1, 2)") }
    }

    @Test("everywhere patterns live: if let, for, and assignment")
    func everywhere() throws {
        #expect(try eval("""
            var out = 0
            if let (value: v, key: k) = ["a": 41].Array()[0] { out = v + k.count }
            out
            """) == .int(42))
        #expect(try eval("""
            var total = 0
            for (value: v, key: _) in ["a": 40, "b": 2] { total = total + v }
            total
            """) == .int(42))
        #expect(try eval("""
            var out = []
            for (element: x, offset: i) in ["p", "q"].enumerated() { out.append("\\(i)\\(x)") }
            out
            """) == .array([.string("0p"), .string("1q")]))
        // assignment by label — the swap, spelled by name
        #expect(try eval("var a = 0\nvar b = 0\n(y: b, x: a) = (x: 1, y: 2)\n[a, b]") == .array([.int(1), .int(2)]))
        #expect(throws: SwiftalkError.self) { try eval("var a = 0\nvar b = 0\n(x: a, z: b) = (x: 1, y: 2)") }
    }

    @Test("the REPL's relaxed mode destructures by label too")
    func relaxed() throws {
        let repl = Swiftalk.Interpreter(relaxed: true)
        _ = try repl.eval("(y: q, x: p) = (x: 1, y: 2)")
        #expect(try repl.eval("[p, q]") == .array([.int(1), .int(2)]))
    }
}
