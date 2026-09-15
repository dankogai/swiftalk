import Testing
@testable import Swiftalk

/// Round 158: `_` discards — `_ = expr` and `let _ = expr` evaluate and
/// bind nothing, in a script and at the REPL alike; `_` is never a
/// variable to read, lock, or redeclare.
@Suite("_ discards — no binding, no type lock (round 158)")
struct DiscardTests {
    @Test("_ = expr and let _ = expr evaluate, bind nothing, may repeat with any type")
    func discard() throws {
        #expect(try eval("_ = 1\n_ = \"a\"\nlet _ = 2.0\nlet _ = [1]\nvar _ = nil\n42") == .int(42))
        #expect(try eval("var n = 0\n_ = { n += 1; return \"x\" }()\nlet _ = { n += 1; return 2 }()\nn") == .int(2))   // evaluated
        #expect(throws: SwiftalkError.self) { try eval("_ = 1\n_") }
        #expect(throws: SwiftalkError.self) { try eval("let _ = 1\n_") }
        #expect(try eval("var n = 5\n(_, n) = (9, 6)\nn") == .int(6))                                            // in a tuple target
        #expect(try eval("let (_, b) = (1, 2)\nb") == .int(2))
        #expect(try eval("let f = { _ = $0; return 1 }\nf(7)") == .int(1))
        #expect(try eval("let _: Int = 1\n0") == .int(0))
        #expect(throws: SwiftalkError.self) { try eval("let _: Int = \"s\"") }                                   // an annotation still checks
        #expect(throws: SwiftalkError.self) { try eval("_ += 1") }                                               // nothing to combine with
    }

    @Test("the REPL's relaxed mode: _ = never declares a var")
    func relaxed() throws {
        let i = Swiftalk.Interpreter(relaxed: true)
        #expect(try i.eval("_ = 1") == .int(1))
        #expect(try i.eval("_ = \"a\"") == .string("a"))                  // the round-156 wart: was "cannot assign String to '_' of type Int"
        #expect(try i.eval("let _ = 2") == .int(2))
        #expect(try i.eval("let _ = 3") == .int(3))
        #expect(throws: SwiftalkError.self) { try i.eval("_") }
        #expect(try i.eval("x = 1\nx") == .int(1))                          // other names still declare on assignment
    }
}
