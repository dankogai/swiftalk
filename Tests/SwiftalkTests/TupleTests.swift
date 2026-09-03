import Testing
@testable import Swiftalk

@Suite("tuples: a grab bag of values (round 70)")
struct TupleTests {
    @Test("literal, .0/.1, count, one loose Tuple type")
    func basics() throws {
        #expect(try eval("(1, \"a\").0") == .int(1))
        #expect(try eval("(1, \"a\").1") == .string("a"))
        #expect(try eval("(1, \"a\", 2.0).count") == .int(3))
        #expect(try eval("(1, \"a\").Type == Tuple") == .bool(true))
        #expect(try eval("(1, 2).Type == (\"x\", true, nil).Type") == .bool(true))   // no (T0, T1) typing
        #expect(try eval("let t = (1, 2)\nt.Type.name") == .string("Tuple"))
    }

    @Test("nesting: t.0.1 is two member accesses, not t then 0.1")
    func nested() throws {
        #expect(try eval("((1, 2), (3, 4)).0.1") == .int(2))
        #expect(try eval("((1, 2), (3, 4)).1.0") == .int(3))
        #expect(try eval("1.5") == .double(1.5))                       // decimals untouched
    }

    @Test("parentheses: (x) groups, (x,) is a 1-tuple, () is empty")
    func parenForms() throws {
        #expect(try eval("(42)") == .int(42))
        #expect(try eval("(42).Type == Int") == .bool(true))
        #expect(try eval("(42,).count") == .int(1))
        #expect(try eval("().count") == .int(0))
        #expect(try eval("(1, 2,).count") == .int(2))                    // trailing comma
    }

    @Test("a value: equality, dictionary keys, source form round-trips")
    func valueSemantics() throws {
        #expect(try eval("(1, \"a\") == (1, \"a\")") == .bool(true))
        #expect(try eval("(1, 2) == (2, 1)") == .bool(false))
        #expect(try eval("[(0, 0): \"origin\"][(0, 0)]") == .string("origin"))
        #expect(try eval("(1, \"a\", [2]).String()") == .string("(1, \"a\", [2])"))
        #expect(try eval("(7,).String()") == .string("(7,)"))
        #expect(try eval("(1, (2, 3))") == .tuple([.int(1), .tuple([.int(2), .int(3)])]))
    }

    @Test("writes: t.0 = v on a var, refused on a let; out of range errors")
    func writes() throws {
        #expect(try eval("var t = (1, 2)\nt.0 = 9\nt") == .tuple([.int(9), .int(2)]))
        #expect(throws: SwiftalkError.self) { try eval("let t = (1, 2)\nt.0 = 9") }
        #expect(throws: SwiftalkError.self) { try eval("(1, 2).5") }
        #expect(throws: SwiftalkError.self) { try eval("var t = (1, 2)\nt.5 = 0") }
    }

    @Test("a grab bag is a Sequence: for-in, map, Array(), and Tuple(seq) back")
    func sequence() throws {
        #expect(try eval("var s = 0\nfor x in (1, 2, 3) { s = s + x }\ns") == .int(6))
        #expect(try eval("(1, 2, 3).map { $0 * 2 }") == .array([.int(2), .int(4), .int(6)]))
        #expect(try eval("(1, \"a\").Array()") == .array([.int(1), .string("a")]))
        #expect(try eval("Tuple([1, 2])") == .tuple([.int(1), .int(2)]))
        #expect(try eval("[1, 2].Tuple()") == .tuple([.int(1), .int(2)]))
        #expect(try eval("Tuple().count") == .int(0))
        #expect(try eval("Tuple.conforms(to: Sequence)") == .bool(true))
    }

    @Test("Dictionary pairs are (key, value) tuples — and a tuple is a rigid Array of arguments (round 73)")
    func dictionaryPairs() throws {
        #expect(try eval("var s = 0\nfor pair in [\"a\": 40, \"b\": 2] { s = s + pair.1 }\ns") == .int(42))
        #expect(try eval("[\"a\": 1].map { $0 }") == .array([.string("a")]))          // $0 is the key
        #expect(try eval("[\"a\": 1].map { $1 }") == .array([.int(1)]))               // $1 the value
        #expect(try eval("[\"a\": 1].map { ($0, $1) }") == .array([.tuple([.string("a"), .int(1)])]))
        #expect(try eval("[\"a\": 1, \"b\": 2].filter { $1 == 2 }") == .dictionary([.string("b"): .int(2)]))
        #expect(try eval("[\"a\": 1, \"b\": 2].reduce(0) { $0 + $1.1 }") == .int(3))  // two args: no splat
        #expect(try eval("[\"a\": 1].map { $.Tuple().Type == Tuple }") == .array([.bool(true)]))
    }

    @Test("a tuple literal is an expression pattern: switch matches by equality")
    func switchPattern() throws {
        #expect(try eval("""
            var out = ""
            switch (1, "x") {
            case (1, "x"): out = "hit"
            default: out = "miss"
            }
            out
            """) == .string("hit"))
    }
}
