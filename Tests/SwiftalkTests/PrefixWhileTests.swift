import Testing
@testable import Swiftalk

@Suite("prefix { } and dropFirst { } — round 88's takeWhile/dropWhile folded into prefix/dropFirst, the argument's type dispatching (round 98)")
struct PrefixWhileTests {
    @Test("eager on Array, Range, String (shaped like filter); the predicate is asked until its first miss")
    func eager() throws {
        #expect(try eval("[1, 2, 3, 4, 1].prefix { $0 < 3 }") == .array([.int(1), .int(2)]))
        #expect(try eval("[1, 2, 3, 4, 1].dropFirst { $0 < 3 }") == .array([.int(3), .int(4), .int(1)]))
        #expect(try eval("\"hello world\".prefix { $0 != \" \" }") == .string("hello"))
        #expect(try eval("\"hello world\".dropFirst { $0 != \" \" }") == .string(" world"))
        #expect(try eval("(1...10).prefix { $0 * $0 < 30 }") == .array([1, 2, 3, 4, 5].map { .int($0) }))
        #expect(try eval("(1...10).dropFirst { $0 < 8 }") == .array([8, 9, 10].map { .int($0) }))
        #expect(try eval("[].prefix { true }") == .array([]))
        #expect(try eval("[1, 2].dropFirst { true }") == .array([]))
        #expect(try eval("[1, 2].prefix { false }") == .array([]))
        #expect(try eval("[\"a\": 1, \"b\": 2].prefix { k, v in true }.count") == .int(2))
        // the predicate is never asked past the first miss
        #expect(try eval("""
            var asked = 0
            let r = [1, 5, 2, 6].prefix { asked = asked + 1; return $0 < 3 }
            [r, asked]
            """) == .array([.array([.int(1)]), .int(2)]))
    }

    @Test("lazy on a Sequence value and on a...: an infinite source is fine")
    func lazy() throws {
        #expect(try eval("(0...).prefix { $0 < 4 }.Array()") == .array([0, 1, 2, 3].map { .int($0) }))
        #expect(try eval("(0...).dropFirst { $0 < 4 }.prefix(3)") == .array([4, 5, 6].map { .int($0) }))
        #expect(try eval("(0...).prefix { $0 < 4 }.Type == Sequence") == .bool(true))
        #expect(try eval("""
            let fib = Sequence { var a = 0; var b = 1; while true { yield a; (a, b) = (b, a + b) } }
            [fib.prefix { $0 < 50 }.Array(), fib.dropFirst { $0 < 50 }.prefix(3)]
            """) == .array([.array([0, 1, 1, 2, 3, 5, 8, 13, 21, 34].map { .int($0) }),
                            .array([55, 89, 144].map { .int($0) })]))
        // composes with the rest of the lazy world
        #expect(try eval("(3...).enumerated().prefix { i, x in i < 2 }.Array()")
                == .array([.tuple([.int(0), .int(3)], labels: ["offset", "element"]),
                           .tuple([.int(1), .int(4)], labels: ["offset", "element"])]))
        #expect(try eval("(0...).map { $0 * 2 }.dropFirst { $0 < 5 }.prefix { $0 < 11 }.Array()")
                == .array([6, 8, 10].map { .int($0) }))
    }

    @Test("a predicate must return a Bool; exactly one Function")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].prefix { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].dropFirst { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].prefix()") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].dropFirst(\"x\")") }
    }

    @Test("one name, two argument types: an Int counts, a Function decides; Swift's while: label accepted; the old names are gone")
    func dispatch() throws {
        #expect(try eval("[1, 2, 3, 4].prefix(2)") == .array([.int(1), .int(2)]))
        #expect(try eval("[1, 2, 3, 4].prefix { $0 < 3 }") == .array([.int(1), .int(2)]))
        #expect(try eval("[1, 2, 3, 4].prefix(while: { $0 < 3 })") == .array([.int(1), .int(2)]))
        #expect(try eval("[1, 2, 3, 4].dropFirst(2)") == .array([.int(3), .int(4)]))
        #expect(try eval("[1, 2, 3, 4].dropFirst { $0 < 3 }") == .array([.int(3), .int(4)]))
        #expect(try eval("[1, 2, 3, 4].dropFirst(while: { $0 < 3 })") == .array([.int(3), .int(4)]))
        #expect(try eval("\"hello world\".prefix(2)") == .string("he"))
        #expect(try eval("\"hello world\".prefix { $0 != \" \" }") == .string("hello"))
        #expect(try eval("(0...).prefix { $0 < 3 }.Array()") == .array([.int(0), .int(1), .int(2)]))
        #expect(try eval("(0...).dropFirst { $0 < 3 }.prefix(2)") == .array([.int(3), .int(4)]))
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].takeWhile { true }") }   // round 88's names: gone
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].dropWhile { true }") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].prefix(\"x\")") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].prefix(1) { true }") }
    }
}
