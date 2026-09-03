import Testing
@testable import Swiftalk

@Suite("Range<I>: first-class, lazy, Int-only (round 38) — and Sequence")
struct RangeTests {
    @Test("Range is its own type — not an Array")
    func rangeIsAType() throws {
        #expect(try eval("(1...5).Type == Range") == .bool(true))
        #expect(try eval("1...5") == .range(from: 1, to: 5, closed: true))
        #expect(try eval("1..<5") == .range(from: 1, to: 5, closed: false))
        #expect(try eval("(1...5) == (1...5)") == .bool(true))
        #expect(try eval("(1...5) == (1..<5)") == .bool(false))
        #expect(throws: SwiftalkError.self) { try eval("(1...5) == [1, 2, 3, 4, 5]") }  // Range ≠ Array
        // type-locked bindings and annotations work as for any type
        #expect(try eval("var r: Range = 1...5\nr = 2..<9\nr.count") == .int(7))
        #expect(throws: SwiftalkError.self) { try eval("var r = 1...5\nr = [1]") }
    }

    @Test("lazy: a huge Range costs nothing until walked")
    func lazy() throws {
        #expect(try eval("(1...1000000000000).count") == .int(1_000_000_000_000))
        #expect(try eval("(1...1000000000000)[999999999999]") == .int(1_000_000_000_000))
        #expect(try eval("var n = 0\nfor i in 1...1000000000000 { n = i\nbreak }\nn") == .int(1))
        #expect(try eval("(-5...5).count") == .int(11))
    }

    @Test("the round-trip law holds: Range prints as its literal (§3d)")
    func roundTrip() throws {
        #expect(try eval("(1...5).String()") == .string("1...5"))
        #expect(try eval("(1..<5).String()") == .string("1..<5"))
        for source in ["1...5", "1..<5", "-3...3"] {
            let v = try eval(source)
            #expect(try eval(v.sourceString()) == v)
        }
        #expect(try eval("(255...4096).debugDescription") == .string("0xff...0x1000"))
    }

    @Test("Range conforms to Sequence: for-in, map, filter, reduce, count, Array()")
    func rangeAsSequence() throws {
        #expect(try eval("var s = 0\nfor i in 1...4 { s = s + i }\ns") == .int(10))
        #expect(try eval("(1...4).map { $0 * $0 }") == .array([.int(1), .int(4), .int(9), .int(16)]))
        #expect(try eval("(1...9).filter { $0 / 3 * 3 == $0 }") == .array([.int(3), .int(6), .int(9)]))
        #expect(try eval("(1...20).reduce(1) { $0 * $1 }") == .int(2432902008176640000))
    }

    @Test(".Array() materializes any Sequence — the four conformers")
    func arrayMaterializer() throws {
        #expect(try eval("(1...3).Array()") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval("\"abc\".Array()") == .array([.string("a"), .string("b"), .string("c")]))
        #expect(try eval("[1, 2].Array()") == .array([.int(1), .int(2)]))
        #expect(try eval("[\"k\": 1].Array()") == .array([.tuple([.string("k"), .int(1)])]))   // pairs are tuples (round 70)
        #expect(throws: SwiftalkError.self) { try eval("42.Array()") }
    }
}
