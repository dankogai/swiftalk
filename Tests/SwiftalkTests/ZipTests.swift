import Testing
@testable import Swiftalk

@Suite("zip(a, b) — Swift's, stamped [Tuple] (round 174)")
struct ZipTests {
    @Test("pairs until the shorter side ends; eager on Arrays, an Array of unlabeled tuples stamped [Tuple], even when empty")
    func eager() throws {
        #expect(try eval("zip([1, 2], [\"a\", \"b\"])") == .array([.tuple([.int(1), .string("a")]), .tuple([.int(2), .string("b")])]))
        #expect(try eval("zip([1, 2, 3], [\"a\"]).count") == .int(1))
        #expect(try eval("zip([1, 2], [\"a\", \"b\"]).Type.String()") == .string("[Tuple]"))
        #expect(try eval("zip([Int](), [String]()).Type.String()") == .string("[Tuple]"))
        #expect(try eval("zip([], []).Type.String()") == .string("[Tuple]"))
        #expect(try eval("zip([1, 2], [\"a\", \"b\"]).map { n, s in \"\\(n)\\(s)\" }") == .array([.string("1a"), .string("2b")]))
        #expect(try eval("zip([1, 2], [\"a\", \"b\"])[0].0") == .int(1))
        #expect(try eval("zip(1...3, \"abc\").map { $1 }") == .array([.string("a"), .string("b"), .string("c")]))
        #expect(try eval("Dictionary(zip([1, 2], [\"a\", \"b\"]))") == .dictionary([.int(1): .string("a"), .int(2): .string("b")]))
        #expect(try eval("Dictionary(zip([1, 2], [\"a\", \"b\"])).Type.String()") == .string("[Int: String]"))
        #expect(throws: SwiftalkError.self) { try eval("var z = zip([1], [2])\nz.append(3)") }
        #expect(throws: SwiftalkError.self) { try eval("zip([1], 2)") }
        #expect(throws: SwiftalkError.self) { try eval("zip([1])") }
    }

    @Test("lazy when either side is: an infinite side is fine, the pairs come on demand, and Array() of it is [Tuple]")
    func lazy() throws {
        #expect(try eval("zip(1..., [\"a\", \"b\"]).Type.String()") == .string("Sequence"))
        #expect(try eval("zip(1..., [\"a\", \"b\"]).Array()") == .array([.tuple([.int(1), .string("a")]), .tuple([.int(2), .string("b")])]))
        #expect(try eval("zip([\"a\", \"b\"], 1...).Array().count") == .int(2))
        #expect(try eval("zip(1..., 10...).prefix(2).Array()") == .array([.tuple([.int(1), .int(10)]), .tuple([.int(2), .int(11)])]))
        #expect(try eval("zip(1..., []).Array().Type.String()") == .string("[Tuple]"))
        #expect(try eval("let z = zip(1..., \"ab\")\n[z.Array().count, z.Array().count]") == .array([.int(2), .int(2)]))   // re-iterable
        #expect(try eval("zip((1...).map { $0 * 2 }, \"abc\").map { n, s in \"\\(s)\\(n)\" }.Array()") == .array([.string("a2"), .string("b4"), .string("c6")]))
        #expect(try eval("Dictionary(zip(1..., [\"a\", \"b\"]))") == .dictionary([.int(1): .string("a"), .int(2): .string("b")]))
    }
}
