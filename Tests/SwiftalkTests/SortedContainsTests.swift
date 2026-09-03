import Testing
@testable import Swiftalk

@Suite("sorted and contains on every Sequence conformer (round 83)")
struct SortedContainsTests {
    @Test("sorted(): Comparable elements ascending; always an Array; sorted(by:) / trailing closure decide order")
    func sorted() throws {
        #expect(try eval("[3, 1, 2].sorted()") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval("[1.5, 0.5].sorted()") == .array([.double(0.5), .double(1.5)]))
        #expect(try eval("[\"b\", \"a\"].sorted()") == .array([.string("a"), .string("b")]))
        #expect(try eval("\"hello\".sorted()")
                == .array(["e", "h", "l", "l", "o"].map(Value.string)))
        #expect(try eval("(1...5).sorted { $0 > $1 }") == .array([5, 4, 3, 2, 1].map { .int($0) }))
        #expect(try eval("[3, 1, 2].sorted(by: { a, b in a > b })") == .array([.int(3), .int(2), .int(1)]))
        #expect(try eval("[].sorted()") == .array([]))
        // a lazy Sequence is drained
        #expect(try eval("Sequence { yield 3; yield 1; yield 2 }.sorted()")
                == .array([.int(1), .int(2), .int(3)]))
        // the source is untouched
        #expect(try eval("let a = [2, 1]\nlet b = a.sorted()\n[a, b]")
                == .array([.array([.int(2), .int(1)]), .array([.int(1), .int(2)])]))
    }

    @Test("Dictionary sorts its (key:, value:) pairs — with a Function, since tuples are not Comparable")
    func dictionarySorted() throws {
        #expect(try eval("let d = [\"b\": 2, \"a\": 1]\nd.sorted { $0.key < $1.key }.map { $0 }")
                == .array([.string("a"), .string("b")]))     // $0 is the key: a sole tuple argument splats (round 73)
        #expect(try eval("let d = [\"b\": 2, \"a\": 1]\nd.sorted { a, b in a.value > b.value }.map { k, v in v }")
                == .array([.int(2), .int(1)]))
        #expect(throws: SwiftalkError.self) { try eval("[\"b\": 2, \"a\": 1].sorted()") }
    }

    @Test("sorted refuses what < refuses: mixed elements, a non-Bool Function, extra arguments")
    func sortedErrors() throws {
        #expect(throws: SwiftalkError.self) { try eval("let m: [Primitives] = [1, \"a\"]\nm.sorted()") }
        #expect(throws: SwiftalkError.self) { try eval("[[1], [2]].sorted()") }
        #expect(throws: SwiftalkError.self) { try eval("[3, 1, 2].sorted { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("[3, 1, 2].sorted(1)") }
        #expect(throws: SwiftalkError.self) { try eval("[3, 1, 2].sorted(1, 2)") }
    }

    @Test("contains(x) by equality on every conformer; contains { } / contains(where:) by predicate")
    func contains() throws {
        #expect(try eval("[3, 1, 2].contains(2)") == .bool(true))
        #expect(try eval("[3, 1, 2].contains(5)") == .bool(false))
        #expect(try eval("[3, 1, 2].contains { $0 > 2 }") == .bool(true))
        #expect(try eval("[3, 1, 2].contains(where: { $0 > 5 })") == .bool(false))
        #expect(try eval("(1...10).contains(7)") == .bool(true))
        #expect(try eval("(1..<10).contains(10)") == .bool(false))
        #expect(try eval("[].contains(1)") == .bool(false))
        #expect(try eval("[[1, 2], [3]].contains([3])") == .bool(true))
        // a pair is a value: tuples are Equatable
        #expect(try eval("let d = [\"b\": 2, \"a\": 1]\nd.contains((\"a\", 1))") == .bool(true))
        #expect(try eval("let d = [\"b\": 2, \"a\": 1]\nd.contains((\"a\", 2))") == .bool(false))
        #expect(try eval("let d = [\"b\": 2, \"a\": 1]\nd.contains { k, v in v == 2 }") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].contains { 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].contains()") }
    }

    @Test("String.contains looks for a substring (Swift's), or a grapheme predicate")
    func stringContains() throws {
        #expect(try eval("\"hello\".contains(\"ell\")") == .bool(true))
        #expect(try eval("\"hello\".contains(\"l\")") == .bool(true))
        #expect(try eval("\"hello\".contains(\"z\")") == .bool(false))
        #expect(try eval("\"hello\".contains(\"\")") == .bool(true))
        #expect(try eval("\"hello\".contains(\"hello!\")") == .bool(false))
        #expect(try eval("\"héllo\".contains(\"é\")") == .bool(true))
        #expect(try eval("\"hello\".contains { $0 == \"o\" }") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("\"hello\".contains(1)") }
    }

    @Test("contains short-circuits: an infinite Sequence answers on the first hit")
    func lazyContains() throws {
        #expect(try eval("""
            let naturals = Sequence { var n = 0; while true { n = n + 1; yield n } }
            [naturals.contains(1000), naturals.contains { $0 * $0 > 50 }]
            """) == .array([.bool(true), .bool(true)]))
    }
}
