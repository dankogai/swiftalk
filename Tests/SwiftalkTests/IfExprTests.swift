import Testing
@testable import Swiftalk

@Suite("if is an expression, if let included; if o { } on a bare optional variable (round 80)")
struct IfExprTests {
    @Test("let x = if ...; else if chains; no branch taken is nil")
    func expressionPositions() throws {
        #expect(try eval("let o: Int? = 7\nlet x = if o { o * 2 } else { 0 }\nx") == .int(14))
        #expect(try eval("""
            let sign = { n in if n > 0 { 1 } else if n < 0 { -1 } else { 0 } }
            [sign(5), sign(-5), sign(0)]
            """) == .array([.int(1), .int(-1), .int(0)]))
        #expect(try eval("if false { 1 }") == .nil)
        #expect(try eval("1 + if true { 1 } else { 2 }") == .int(2))
        #expect(try eval("[1, 2, 3].map { if $0 > 1 { \"big\" } else { \"small\" } }")
                == .array([.string("small"), .string("big"), .string("big")]))
        // a branch's value is its last statement's (the closure-body rule)
        #expect(try eval("let o: Int? = 7\nif o { var q = 1; q = q + o; q }") == .int(8))
    }

    @Test("if let as an expression: bindings flow into the value")
    func ifLetExpression() throws {
        #expect(try eval("let d = [0: \"a\"]\nlet s = if v = d[0] { v + \"!\" } else { \"-\" }\ns")
                == .string("a!"))
        #expect(try eval("let d = [0: \"a\"]\nlet s = if let v = d[1] { v + \"!\" } else { \"-\" }\ns")
                == .string("-"))
        #expect(try eval("let t: Tuple? = (1, 2)\nif (a, b) = t { a + b }") == .int(3))
    }

    @Test("if o { }: a bare optional variable asks non-nil; inside, o is itself (flat optionals)")
    func bareVariable() throws {
        #expect(try eval("let o: Int? = 7\nif o { o + 1 }") == .int(8))
        #expect(try eval("let none: Int? = nil\nif none { none } else { \"nil\" }") == .string("nil"))
        #expect(try eval("let none: Int? = nil\nvar r = 0\nif none { r = 1 }\nr") == .int(0))
        // a Bool variable is a Bool test, false included (nil is still "no")
        #expect(try eval("let b: Bool? = false\nif b { \"yes\" } else { \"no\" }") == .string("no"))
        #expect(try eval("let b: Bool? = true\nif b { \"yes\" } else { \"no\" }") == .string("yes"))
        #expect(try eval("let b: Bool? = nil\nif b { \"yes\" } else { \"no\" }") == .string("no"))
        // in a condition list, later clauses see it as itself
        #expect(try eval("let o: Int? = 7\nif o, o > 5 { \"big\" }") == .string("big"))
        // no shadow: assignment inside writes through — the drain loop
        #expect(try eval("""
            struct Node { var value: Int; var next: Node? = nil }
            var node: Node? = Node(value: 1, next: Node(value: 2, next: nil))
            var seen = []
            while node { seen.append(node.value); node = node.next }
            seen
            """) == .array([.int(1), .int(2)]))
        #expect(try eval("var o: Int? = 7\nif o { o = nil }\no") == .nil)
    }

    @Test("only a bare variable: any other non-Bool condition needs a capture")
    func notBareVariable() throws {
        #expect(throws: SwiftalkError.self) { try eval("if 5 { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("if Int(\"x\") { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("let d = [0: 1]\nif d[0] { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("let d = [0: 1]\nvar i = 0\nwhile d[i] { i = i + 1 }") }
        #expect(try eval("if x = Int(\"x\") { x } else { -1 }") == .int(-1))
        #expect(try eval("if x = Int(\"4\") { x } else { -1 }") == .int(4))
    }
}
