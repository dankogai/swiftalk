import Testing
@testable import Swiftalk

@Suite(".enumerated(), and the tuple-is-a-rigid-Array rule for $ (round 73)")
struct EnumeratedTests {
    @Test("Array in, Array of (index, element) out; destructures every way")
    func eager() throws {
        #expect(try eval("[\"a\", \"b\"].enumerated()")
            == .array([.tuple([.int(0), .string("a")]), .tuple([.int(1), .string("b")])]))
        #expect(try eval("[\"a\", \"b\"].enumerated().map { i, x in \"\\(i):\\(x)\" }")
            == .array([.string("0:a"), .string("1:b")]))
        #expect(try eval("[\"a\", \"b\"].enumerated().map { \"\\($0):\\($1)\" }")
            == .array([.string("0:a"), .string("1:b")]))
        #expect(try eval("""
            var out = []
            for i, x in ["a", "b"].enumerated() { out.append("\\(i)\\(x)") }
            out
            """) == .array([.string("0a"), .string("1b")]))
        #expect(try eval("\"héllo\".enumerated().count") == .int(5))
        #expect(try eval("(10...12).enumerated()")
            == .array([.tuple([.int(0), .int(10)]), .tuple([.int(1), .int(11)]), .tuple([.int(2), .int(12)])]))
    }

    @Test("Sequence in, lazy Sequence out — infinite is fine, and re-iterable")
    func lazy() throws {
        #expect(try eval("""
            let naturals = Sequence { var n = 10; while true { yield n; n = n + 1 } }
            naturals.enumerated().prefix(3)
            """) == .array([.tuple([.int(0), .int(10)]), .tuple([.int(1), .int(11)]), .tuple([.int(2), .int(12)])]))
        #expect(try eval("""
            let s = Sequence([0]) { $ = [$0 + 1]; return $0 }.enumerated()
            [s.prefix(2), s.prefix(2)]
            """) == .array([.array([.tuple([.int(0), .int(0)]), .tuple([.int(1), .int(1)])]),
                            .array([.tuple([.int(0), .int(0)]), .tuple([.int(1), .int(1)])])]))
        #expect(try eval("Sequence { yield \"x\" }.enumerated().map { i, x in x + \"\\(i)\" }.Array()")
            == .array([.string("x0")]))
    }

    @Test("the rigid-Array rule: a sole tuple argument is the argument list")
    func rigidArray() throws {
        #expect(try eval("[\"k\": 7].map { $0 }") == .array([.string("k")]))       // $0 is k
        #expect(try eval("[\"k\": 7].map { $1 }") == .array([.int(7)]))            // $1 is v
        #expect(try eval("[\"k\": 7].map { $ }") == .array([.array([.string("k"), .int(7)])]))  // $ is the Array
        #expect(try eval("[(1, 2), (3, 4)].map { $0 + $1 }") == .array([.int(3), .int(7)]))
        // to get the pair back, rebuild it: ($0, $1) or $.Tuple()
        #expect(try eval("[(1, 2)].map { ($0, $1) }") == .array([.tuple([.int(1), .int(2)])]))
        #expect(try eval("[(1, 2)].map { $.Tuple() }") == .array([.tuple([.int(1), .int(2)])]))
        // reduce passes two arguments — no sole-tuple, no splat: $1 is the pair
        #expect(try eval("[\"a\": 1, \"b\": 2].reduce(0) { $0 + $1.1 }") == .int(3))
    }
}
