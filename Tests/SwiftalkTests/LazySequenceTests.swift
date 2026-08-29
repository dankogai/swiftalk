import Testing
@testable import Swiftalk

@Suite("lazy Sequences by default (round 41)")
struct LazySequenceTests {
    @Test("the marquee: fib as Sequence(state) { next }, lazy through map, until prefix")
    func marquee() throws {
        let fib = #"Sequence([0, 1]) { $ = [$1, $0 + $1]; return $1 }.map { "\($0)" }"#
        #expect(try eval("\(fib).prefix(5)")
            == .array([.string("1"), .string("1"), .string("2"), .string("3"), .string("5")]))
        // without .prefix, it is still a Sequence — nothing has run
        #expect(try eval("\(fib).Type == Sequence") == .bool(true))
    }

    @Test("lazy means lazy: nothing runs until pulled, and only as much as pulled")
    func laziness() throws {
        let source = """
            var calls = 0
            let s = Sequence([0]) { calls = calls + 1
            $ = [$0 + 1]
            return $0 }.map { $0 * 10 }
            let before = calls
            let taken = s.prefix(3)
            [before, calls, taken]
            """
        #expect(try eval(source)
            == .array([.int(0), .int(3), .array([.int(0), .int(10), .int(20)])]))
    }

    @Test("returning nil ends the sequence")
    func termination() throws {
        #expect(try eval("Sequence([0]) { $ = [$0 + 1]\nreturn $0 < 3 ? $0 : nil }.Array()")
            == .array([.int(0), .int(1), .int(2)]))
        #expect(try eval("Sequence([9]) { return nil }.Array()") == .array([]))
    }

    @Test("filter is lazy too; chains stay Sequences until a terminal")
    func lazyFilter() throws {
        let naturals = "Sequence([1]) { $ = [$0 + 1]\nreturn $0 }"
        #expect(try eval("\(naturals).filter { $0 / 3 * 3 == $0 }.prefix(3)")
            == .array([.int(3), .int(6), .int(9)]))
        #expect(try eval("\(naturals).filter { true }.map { $0 }.Type == Sequence") == .bool(true))
    }

    @Test("a Sequence value is re-iterable: each iteration restarts")
    func reiterable() throws {
        #expect(try eval("""
            let s = Sequence([0]) { $ = [$0 + 1]\nreturn $0 < 2 ? $0 : nil }
            s.Array() + s.Array()
            """) == .array([.int(0), .int(1), .int(0), .int(1)]))
    }

    @Test("for-in drives a lazy Sequence; break escapes an infinite one")
    func forIn() throws {
        // (parenthesized: for-in headers don't take trailing closures)
        #expect(try eval("""
            var out = []
            for x in (Sequence([1]) { $ = [$0 * 2]\nreturn $0 }) {
                if x > 8 { break }
                out = out + [x]
            }
            out
            """) == .array([.int(1), .int(2), .int(4), .int(8)]))
    }

    @Test("count refuses a possibly-infinite Sequence; prefix works on every conformer")
    func countAndPrefix() throws {
        #expect(throws: SwiftalkError.self) { try eval("Sequence([0]) { return $0 }.count") }
        #expect(try eval("(1...100).prefix(3)") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval("\"abc\".prefix(2)") == .array([.string("a"), .string("b")]))
        #expect(try eval("[1, 2].prefix(9)") == .array([.int(1), .int(2)]))   // short is fine
        #expect(try eval("Sequence([0]) { return $0 }.Type.conforms(to: Sequence)") == .bool(true))
        #expect(try eval("Sequence.name") == .string("Sequence"))
    }

    @Test("return works in ordinary functions too (round 41's other newcomer)")
    func returnStatement() throws {
        #expect(try eval("let sign = { x in if x < 0 { return \"neg\" }\nreturn \"pos\" }\nsign(-5)")
            == .string("neg"))
        #expect(try eval("let sign = { x in if x < 0 { return \"neg\" }\nreturn \"pos\" }\nsign(5)")
            == .string("pos"))
        #expect(try eval("{ return }()") == .nil)
        #expect(try eval("let f = { for i in 1...100 { if i == 7 { return i } }\n0 }\nf()") == .int(7))
        #expect(throws: SwiftalkError.self) { try eval("return 1") }
    }

    @Test("$ is reassignable; $N stay entry snapshots (refines rounds 10/32)")
    func dollarSemantics() throws {
        #expect(try eval("{ $ = [9]\n$[0] }(1)") == .int(9))    // $[N] is live
        #expect(try eval("{ $ = [9]\n$0 }(1)") == .int(1))      // $N is the entry snapshot
        #expect(throws: SwiftalkError.self) { try eval("{ $ = 9 }(1)") }   // $ stays an Array
    }
}
