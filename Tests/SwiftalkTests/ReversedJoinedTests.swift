import Testing
@testable import Swiftalk

@Suite("reversed and joined on every Sequence conformer (round 84)")
struct ReversedJoinedTests {
    @Test("reversed(): always an Array — Array, String graphemes, Range, Dictionary pairs, a drained Sequence")
    func reversed() throws {
        #expect(try eval("[1, 2, 3].reversed()") == .array([.int(3), .int(2), .int(1)]))
        #expect(try eval("\"héllo\".reversed()") == .array(["o", "l", "l", "é", "h"].map(Value.string)))
        #expect(try eval("(1...4).reversed()") == .array([4, 3, 2, 1].map { .int($0) }))
        #expect(try eval("Sequence { yield 1; yield 2 }.reversed()") == .array([.int(2), .int(1)]))
        #expect(try eval("[].reversed()") == .array([]))
        #expect(try eval("let d = [\"a\": 1]\nd.reversed()")
                == .array([.tuple([.string("a"), .int(1)], labels: ["key", "value"])]))
        // the source is untouched; reversed twice is identity
        #expect(try eval("let a = [1, 2]\nlet b = a.reversed()\n[a, b.reversed() == a]")
                == .array([.array([.int(1), .int(2)]), .bool(true)]))
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].reversed(1)") }
    }

    @Test("joined(): Strings concatenate, with an optional separator (bare or separator:)")
    func joinedStrings() throws {
        #expect(try eval("[\"a\", \"b\", \"c\"].joined()") == .string("abc"))
        #expect(try eval("[\"a\", \"b\", \"c\"].joined(\", \")") == .string("a, b, c"))
        #expect(try eval("[\"a\", \"b\", \"c\"].joined(separator: \"-\")") == .string("a-b-c"))
        #expect(try eval("[].joined()") == .string(""))
        #expect(try eval("[\"only\"].joined(\"-\")") == .string("only"))
        // a String's elements are graphemes: joining them with a separator interleaves
        #expect(try eval("\"abc\".joined(\"-\")") == .string("a-b-c"))
        #expect(try eval("\"héllo\".reversed().joined()") == .string("olléh"))
        #expect(try eval("(1...3).map { \"\\($0)\" }.joined(\"+\")") == .string("1+2+3"))
        #expect(try eval("Sequence { yield \"x\"; yield \"y\" }.joined()") == .string("xy"))
    }

    @Test("joined(): Arrays flatten, with an optional Array separator")
    func joinedArrays() throws {
        #expect(try eval("[[1, 2], [3], []].joined()") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval("[[1, 2], [3]].joined([0])") == .array([.int(1), .int(2), .int(0), .int(3)]))
        #expect(try eval("[[1, 2], [3]].joined(separator: [0, 0])")
                == .array([.int(1), .int(2), .int(0), .int(0), .int(3)]))
        #expect(try eval("[].joined([0])") == .array([]))
    }

    @Test("joined refuses a mix, a wrong separator, and non-joinable elements")
    func joinedErrors() throws {
        #expect(throws: SwiftalkError.self) { try eval("let m: [Primitives] = [\"a\", 1]\nm.joined()") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].joined()") }
        #expect(throws: SwiftalkError.self) { try eval("[[1], \"a\"].joined()") }
        #expect(throws: SwiftalkError.self) { try eval("[\"a\", \"b\"].joined([0])") }
        #expect(throws: SwiftalkError.self) { try eval("[[1], [2]].joined(\"-\")") }
        #expect(throws: SwiftalkError.self) { try eval("[\"a\"].joined(1, 2)") }
    }
}
