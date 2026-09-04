import Testing
@testable import Swiftalk

@Suite("&&= and ||= — the op= family completed (round 104)")
struct LogicalAssignmentTests {
    @Test("Bools in, Bools out; short-circuit like the operators — the right side evaluated only when it decides")
    func basics() throws {
        #expect(try eval("var ok = true\nok &&= 1 < 2\nok") == .bool(true))
        #expect(try eval("var ok = true\nok &&= false\nok") == .bool(false))
        #expect(try eval("var any = false\nany ||= 3 > 4\nany") == .bool(false))
        #expect(try eval("var any = false\nany ||= true\nany") == .bool(true))
        #expect(try eval("""
            var calls = 0
            let probe = { calls += 1; return true }
            var f = false
            f &&= probe()
            var t = true
            t ||= probe()
            let before = calls
            t &&= probe()
            [before, calls, t]
            """) == .array([.int(0), .int(1), .bool(true)]))
        #expect(try eval("var flags = [\"x\": true]\nflags[\"x\"] &&= false\nflags[\"x\"]") == .bool(false))
        #expect(try eval("var b = true\nb &&= false") == .bool(false))          // its value
        // the short-circuit skips the right side's type check too, as && does
        #expect(try eval("var b = false\nb &&= 1\nb") == .bool(false))
    }

    @Test("nothing is truthy: a non-Bool target or right side is a type error; a let refuses; the REPL continues after a trailing op=")
    func rules() throws {
        #expect(throws: SwiftalkError.self) { try eval("var n = 1\nn &&= true") }
        #expect(throws: SwiftalkError.self) { try eval("var b = true\nb &&= 1") }
        #expect(throws: SwiftalkError.self) { try eval("var b = false\nb ||= \"s\"") }
        #expect(throws: SwiftalkError.self) { try eval("let b = true\nb ||= false") }
        #expect(throws: SwiftalkError.self) { try eval("var b = true\nlet v = b &&= false") }
        let repl = Swiftalk.Interpreter(relaxed: true)
        #expect(try repl.eval("var b = true\nb &&=\nfalse\nb") == .bool(false))
        #expect(try repl.eval("true && false") == .bool(false))               // && itself untouched
    }
}
