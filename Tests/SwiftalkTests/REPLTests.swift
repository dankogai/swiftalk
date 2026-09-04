import Testing
@testable import Swiftalk

@Suite("Milestone 1: REPL support")
struct REPLTests {
    @Test("relaxed mode: bare x = 1 declares a var — still type-locked (§2.2)")
    func relaxedMode() throws {
        let repl = Interpreter(relaxed: true)
        #expect(try repl.eval("x = 1") == .int(1))
        #expect(try repl.eval("x = x + 1") == .int(2))
        #expect(throws: SwiftalkError.self) { try repl.eval("x = \"1\"") }   // lock holds
        #expect(throws: SwiftalkError.self) { try repl.eval("y = nil") }     // nothing to infer
        #expect(throws: SwiftalkError.self) { try repl.eval("let x = 9") }   // still no redeclaration
        // file mode stays strict
        #expect(throws: SwiftalkError.self) { try Interpreter().eval("x = 1") }
    }

    @Test("needsMoreInput: open brackets continue, complete or broken input doesn't")
    func incompleteInput() {
        #expect(needsMoreInput("[1, 2,"))
        #expect(needsMoreInput("(1 + "))
        #expect(needsMoreInput("[\"key\": [1, 2"))
        #expect(!needsMoreInput("[1, 2]"))
        #expect(needsMoreInput("1 +"))        // a trailing operator continues since round 95            // malformed, not incomplete
        #expect(!needsMoreInput("\"unterminated")) // lex error → report, don't hang
        #expect(!needsMoreInput("42"))
    }

    @Test("the REPL's printer is source form: echo re-enters as what it was (§3d)")
    func printerRoundTrips() throws {
        let repl = Interpreter(relaxed: true)
        // round 59: a mixed literal binds only under an annotation
        _ = try repl.eval("var v: [Primitives] = [1, \"one\", [2.0, nil]]")
        let echo = try repl.eval("v").sourceString()
        #expect(try repl.eval(echo) == repl.eval("v"))
    }
}
