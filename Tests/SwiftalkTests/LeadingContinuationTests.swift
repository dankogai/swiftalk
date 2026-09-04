import Testing
@testable import Swiftalk

@Suite("a leading binary operator continues the previous line — Swift's whitespace rule (round 96)")
struct LeadingContinuationTests {
    @Test("arithmetic, logical, ??, =, comparison, and the spaced ternary lead lines")
    func continues() throws {
        #expect(try eval("let t = 1\n    + 2\n    + 3\nt") == .int(6))
        #expect(try eval("let ok = 6 > 5\n    && 6 < 7\n    || false\nok") == .bool(true))
        #expect(try eval("let n = nil\n    ?? \"default\"\nn") == .string("default"))
        #expect(try eval("let x\n    = 42\nx") == .int(42))
        #expect(try eval("let s = 6 > 0\n    ? \"positive\"\n    : \"not\"\ns") == .string("positive"))
        #expect(try eval("1\n    == 1") == .bool(true))
        #expect(try eval("7\n % 3") == .int(1))
        // mixed with trailing continuation
        #expect(try eval("let t = 1 +\n    2\n    + 3\nt") == .int(6))
    }

    @Test("no whitespace after the operator: a prefix, a new statement; implicit-self .x stays a statement")
    func prefixes() throws {
        #expect(try eval("let y = 5\n-y\ny") == .int(5))
        #expect(try eval("let y = 5\n-y") == .int(-5))
        #expect(try eval("let f = false\n!f") == .bool(true))
        #expect(try eval("let f = false\n!f\nf") == .bool(false))
        #expect(try eval("struct P { var x = 0; let bump = { .x = .x + 1; return .x } }\nvar p = P()\np.bump()") == .int(1))
        // 0... at a line's end is still the unbounded range; ... never leads
        #expect(try eval("let r = 0...\nr.String()") == .string("0..."))
        #expect(throws: SwiftalkError.self) { try eval("let r = 0\n...5") }
    }
}
