import Testing
@testable import Swiftalk

@Suite("takeWhile and dropWhile on every Sequence conformer (round 88)")
struct TakeDropWhileTests {
    @Test("eager on Array, Range, String (shaped like filter); the predicate is asked until its first miss")
    func eager() throws {
        #expect(try eval("[1, 2, 3, 4, 1].takeWhile { $0 < 3 }") == .array([.int(1), .int(2)]))
        #expect(try eval("[1, 2, 3, 4, 1].dropWhile { $0 < 3 }") == .array([.int(3), .int(4), .int(1)]))
        #expect(try eval("\"hello world\".takeWhile { $0 != \" \" }") == .string("hello"))
        #expect(try eval("\"hello world\".dropWhile { $0 != \" \" }") == .string(" world"))
        #expect(try eval("(1...10).takeWhile { $0 * $0 < 30 }") == .array([1, 2, 3, 4, 5].map { .int($0) }))
        #expect(try eval("(1...10).dropWhile { $0 < 8 }") == .array([8, 9, 10].map { .int($0) }))
        #expect(try eval("[].takeWhile { true }") == .array([]))
        #expect(try eval("[1, 2].dropWhile { true }") == .array([]))
        #expect(try eval("[1, 2].takeWhile { false }") == .array([]))
        #expect(try eval("[\"a\": 1, \"b\": 2].takeWhile { k, v in true }.count") == .int(2))
        // the predicate is never asked past the first miss
        #expect(try eval("""
            var asked = 0
            let r = [1, 5, 2, 6].takeWhile { asked = asked + 1; return $0 < 3 }
            [r, asked]
            """) == .array([.array([.int(1)]), .int(2)]))
    }

    @Test("lazy on a Sequence value and on a...: an infinite source is fine")
    func lazy() throws {
        #expect(try eval("(0...).takeWhile { $0 < 4 }.Array()") == .array([0, 1, 2, 3].map { .int($0) }))
        #expect(try eval("(0...).dropWhile { $0 < 4 }.prefix(3)") == .array([4, 5, 6].map { .int($0) }))
        #expect(try eval("(0...).takeWhile { $0 < 4 }.Type == Sequence") == .bool(true))
        #expect(try eval("""
            let fib = Sequence { var a = 0; var b = 1; while true { yield a; (a, b) = (b, a + b) } }
            [fib.takeWhile { $0 < 50 }.Array(), fib.dropWhile { $0 < 50 }.prefix(3)]
            """) == .array([.array([0, 1, 1, 2, 3, 5, 8, 13, 21, 34].map { .int($0) }),
                            .array([55, 89, 144].map { .int($0) })]))
        // composes with the rest of the lazy world
        #expect(try eval("(3...).enumerated().takeWhile { i, x in i < 2 }.Array()")
                == .array([.tuple([.int(0), .int(3)], labels: ["offset", "element"]),
                           .tuple([.int(1), .int(4)], labels: ["offset", "element"])]))
        #expect(try eval("(0...).map { $0 * 2 }.dropWhile { $0 < 5 }.takeWhile { $0 < 11 }.Array()")
                == .array([6, 8, 10].map { .int($0) }))
    }

    @Test("a predicate must return a Bool; exactly one Function")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].takeWhile { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].dropWhile { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].takeWhile()") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].dropWhile(1)") }
    }
}
