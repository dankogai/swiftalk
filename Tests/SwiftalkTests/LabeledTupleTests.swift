import Testing
@testable import Swiftalk

@Suite("labeled tuples: (x: 1, y: 2).x — labels name positions (round 74)")
struct LabeledTupleTests {
    @Test("labels read and write; positions still work; mixed is fine")
    func access() throws {
        #expect(try eval("(x: 1, y: 2).x") == .int(1))
        #expect(try eval("(x: 1, y: 2).y") == .int(2))
        #expect(try eval("(x: 1, y: 2).1") == .int(2))
        #expect(try eval("(1, y: 2).y") == .int(2))
        #expect(try eval("var p = (x: 1, y: 2)\np.x = 10\np") == .tuple([.int(10), .int(2)], labels: ["x", "y"]))
        #expect(try eval("(x: 1, y: 2).count") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("(x: 1, y: 2).z") }
        #expect(throws: SwiftalkError.self) { try eval("(x: 1, x: 2)") }
    }

    @Test("labels are cosmetic: equality, hashing, destructuring, splat ignore them")
    func cosmetic() throws {
        #expect(try eval("(x: 1, y: 2) == (1, 2)") == .bool(true))
        #expect(try eval("[(x: 0, y: 0): \"origin\"][(0, 0)]") == .string("origin"))
        #expect(try eval("let (a, b) = (x: 1, y: 2)\n[a, b]") == .array([.int(1), .int(2)]))
        #expect(try eval("let f = { p, q in p - q }\nf((y: 1, x: 5))") == .int(-4))  // positional splat: p = 1, q = 5
        #expect(try eval("(x: 1, y: 2).Array()") == .array([.int(1), .int(2)]))
    }

    @Test("source form keeps labels and round-trips; (x: 1) is a 1-tuple")
    func sourceForm() throws {
        #expect(try eval("(x: 1, y: 2).String()") == .string("(x: 1, y: 2)"))
        #expect(try eval("(1, y: 2).String()") == .string("(1, y: 2)"))
        #expect(try eval("(x: 1).count") == .int(1))
        #expect(try eval("(x: 1).String()") == .string("(x: 1)"))
        #expect(try eval("(7,).String()") == .string("(7,)"))
        let t = try eval("(x: 1, y: \"two\")")
        #expect(try eval(t.sourceString()) == t)
    }

    @Test("Dictionary pairs are (key:, value:); enumerated is (offset:, element:)")
    func builtinLabels() throws {
        #expect(try eval("var s = 0\nfor pair in [\"a\": 40, \"b\": 2] { s = s + pair.value }\ns") == .int(42))
        #expect(try eval("[\"a\": 1].map { $ }") == .array([.array([.string("a"), .int(1)])]))
        #expect(try eval("[\"a\": 1].Array()[0].key") == .string("a"))
        #expect(try eval("[\"a\": 1].Array()[0].String()") == .string("(key: \"a\", value: 1)"))
        #expect(try eval("[\"x\", \"y\"].enumerated()[1].offset") == .int(1))
        #expect(try eval("[\"x\", \"y\"].enumerated()[1].element") == .string("y"))
        #expect(try eval("var out = []\nfor e in [\"x\"].enumerated() { out.append(\"\\(e.offset)\\(e.element)\") }\nout")
            == .array([.string("0x")]))
        // ...and the positional/destructuring/splat forms still hold
        #expect(try eval("[\"a\": 1].map { k, v in \"\\(k)\\(v)\" }") == .array([.string("a1")]))
        #expect(try eval("for (i, x) in [\"q\"].enumerated() { }\n1") == .int(1))
    }
}
