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

    @Test(":r redefines a struct or enum, :d removes one; :r extension overwrites members (round 141)")
    func types() throws {
        let i = Swiftalk.Interpreter(relaxed: true)
        _ = try i.eval("struct P { var x: Int = 0 }\nlet p = P(x: 1)")
        #expect(try i.eval("p.x") == .int(1))
        _ = try i.redefine("struct P { var y: Int = 0; let twice = { .y * 2 } }")
        #expect(try i.eval("P(y: 2).twice()") == .int(4))
        #expect(throws: SwiftalkError.self) { try i.eval("P(x: 1)") }
        #expect(try i.eval("p.Type == P") == .bool(false))                                  // old values keep the old type
        #expect(try i.eval("p.x") == .int(1))
        _ = try i.eval("enum E { case a, b }")
        _ = try i.redefine("enum E { case c }")
        #expect(try i.eval("E.c == E.c") == .bool(true))
        #expect(throws: SwiftalkError.self) { try i.eval("E.a") }
        try i.undefine("P")
        #expect(throws: SwiftalkError.self) { try i.eval("P") }
        try i.undefine("E")
        #expect(try i.eval("struct P { }\nP().Type == P") == .bool(true))                   // fresh after :d
        // extension: overwrite a method, a computed property, on a struct and on a builtin
        _ = try i.eval("struct Q { var n: Int = 3; let show = { \"q\" }; var big { .n > 2 } }")
        #expect(throws: SwiftalkError.self) { try i.eval("extension Q { let show = { \"Q!\" } }") }   // plain extension: refused
        _ = try i.redefine("extension Q { let show = { \"Q!\" }; var big { .n > 100 } }")
        #expect(try i.eval("Q().show()") == .string("Q!"))
        #expect(try i.eval("Q().big") == .bool(false))
        _ = try i.redefine("extension Q { let big = { 1 } }")                                 // a computed property becomes a method
        #expect(try i.eval("Q().big()") == .int(1))
        #expect(throws: SwiftalkError.self) { try i.redefine("extension Q { let n = { 1 } }") }  // a stored property never gives way
        _ = try i.eval("extension Int { var twice { self * 2 } }")
        #expect(try i.eval("4.twice") == .int(8))
        #expect(throws: SwiftalkError.self) { try i.eval("extension Int { var twice { self * 3 } }") }
        _ = try i.redefine("extension Int { var twice { self * 3 } }")
        #expect(try i.eval("4.twice") == .int(12))
        _ = try i.eval("extension String { let shout = { self + \"!\" } }")
        _ = try i.redefine("extension String { let shout = { self + \"!!\" } }")
        #expect(try i.eval("\"hi\".shout()") == .string("hi!!"))
        #expect(throws: SwiftalkError.self) { try i.redefine("extension Nope { }") }
        #expect(try i.eval("extension Int { var thrice { self * 3 } }\n2.thrice") == .int(6))   // outside :r the rule stands
        #expect(throws: SwiftalkError.self) { try i.eval("extension Int { var thrice { self * 4 } }") }
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
        #expect(throws: SwiftalkError.self) { try i.redefine("") }
        #expect(throws: SwiftalkError.self) { try i.undefine("nope") }
        #expect(throws: SwiftalkError.self) { try i.undefine("print") }          // a builtin, not a top-level binding
        #expect(throws: SwiftalkError.self) { try i.redefine("let print = 1") }   // still refused, nothing lost
        #expect(try i.eval("print.Type == Function") == .bool(true))
    }
}
