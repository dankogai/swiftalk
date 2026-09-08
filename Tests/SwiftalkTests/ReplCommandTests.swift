import Testing
@testable import Swiftalk

@Suite("REPL commands: :r redefines a top-level binding, :d undefines it (round 131)")
struct ReplCommandTests {
    @Test(":r replaces a binding whatever its type or mutability; :d removes it")
    func redefineUndefine() throws {
        let i = Swiftalk.Interpreter(relaxed: true)
        #expect(try i.eval("var x = 1") == .int(1))
        #expect(throws: SwiftalkError.self) { try i.eval("x = \"one\"") }
        #expect(try i.redefine("let x = \"one\"") == .string("one"))
        #expect(try i.eval("x.Type == String") == .bool(true))
        #expect(throws: SwiftalkError.self) { try i.eval("x = \"two\"") }        // a let now
        #expect(try i.redefine("var x = 2.5") == .double(2.5))
        #expect(try i.eval("x = 3.5\nx") == .double(3.5))
        try i.undefine("x")
        #expect(throws: SwiftalkError.self) { try i.eval("x") }
        #expect(try i.eval("let x = true") == .bool(true))                        // fresh after :d
        #expect(try i.redefine("let (a, b) = (1, \"b\")") == .tuple([.int(1), .string("b")]))
        #expect(try i.redefine("var (a, b) = (2, 3)") == .tuple([.int(2), .int(3)]))
        #expect(try i.eval("a + b") == .int(5))
        #expect(try i.redefine("let fresh = 1") == .int(1))                     // :r on a new name is a declaration
    }

    @Test("a failed :r keeps the old binding; :d of a missing or builtin name, and a non-declaration :r, are errors")
    func errors() throws {
        let i = Swiftalk.Interpreter(relaxed: true)
        #expect(try i.eval("let y = 1") == .int(1))
        #expect(throws: SwiftalkError.self) { try i.redefine("let y = Int(\"z\")!") }
        #expect(try i.eval("y") == .int(1))
        #expect(throws: SwiftalkError.self) { try i.redefine("let y: String = 2") }
        #expect(try i.eval("y") == .int(1))
        #expect(throws: SwiftalkError.self) { try i.redefine("y = 2") }
        #expect(throws: SwiftalkError.self) { try i.redefine("let y = 2\nlet z = 3") }
        #expect(throws: SwiftalkError.self) { try i.redefine("struct S { }") }
        #expect(throws: SwiftalkError.self) { try i.redefine("") }
        #expect(throws: SwiftalkError.self) { try i.undefine("nope") }
        #expect(throws: SwiftalkError.self) { try i.undefine("print") }          // a builtin, not a top-level binding
        #expect(throws: SwiftalkError.self) { try i.redefine("let print = 1") }   // still refused, nothing lost
        #expect(try i.eval("print.Type == Function") == .bool(true))
    }
}
