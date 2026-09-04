import Testing
@testable import Swiftalk

@Suite("a trailing binary operator continues the line (round 95)")
struct ContinuationTests {
    @Test("arithmetic, comparison, logical, ??, and = continue across a newline")
    func continues() throws {
        #expect(try eval("let t = 1 +\n    2 +\n    3\nt") == .int(6))
        #expect(try eval("let ok = 6 > 5 &&\n    6 < 7 ||\n    false\nok") == .bool(true))
        #expect(try eval("let n = nil ??\n    \"default\"\nn") == .string("default"))
        #expect(try eval("let x =\n    42\nx") == .int(42))
        #expect(try eval("3 *\n  4 -\n  1") == .int(11))
        #expect(try eval("let a = 1 ==\n 1\na") == .bool(true))
        #expect(try eval("7 %\n 3") == .int(1))
        // the sion parser's long conditions, unparenthesized
        #expect(try eval("let c = \"x\"\nlet letter = (\"a\" <= c && c <= \"f\") ||\n    c == \"x\" || c == \"X\"\nletter") == .bool(true))
    }

    @Test("not after postfix ! or ?, and not after ... — 0... at a line's end stays the unbounded range")
    func stops() throws {
        #expect(try eval("let o: Int? = 7\nlet v = o!\nv") == .int(7))
        #expect(try eval("let r = 0...\nr.String()") == .string("0..."))
        #expect(try eval("let r = 0...\n(1...3).count") == .int(3))
        // a leading operator continues too since round 96 (Swift's rule)
        #expect(try eval("let s = 1\n + 2\ns") == .int(3))
        // a dangling operator at the end of the program is an error, not a hang
        #expect(throws: SwiftalkError.self) { try eval("let s = 1 +") }
    }

    @Test("the REPL keeps reading after a trailing operator")
    func repl() throws {
        #expect(Swiftalk.needsMoreInput("1 +") == true)
        #expect(Swiftalk.needsMoreInput("a &&") == true)
        #expect(Swiftalk.needsMoreInput("let x =") == true)
        #expect(Swiftalk.needsMoreInput("let r = 0...") == false)
        #expect(Swiftalk.needsMoreInput("o!") == false)
        #expect(Swiftalk.needsMoreInput("1 + 2") == false)
    }
}
