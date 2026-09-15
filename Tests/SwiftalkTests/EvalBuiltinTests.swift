import Testing
@testable import Swiftalk

@Suite("eval() in the language — source in, a Result out, at the top level (rounds 122, 159)")
struct EvalBuiltinTests {
    @Test("the last statement's value; the round-trip law, in the language")
    func basics() throws {
        #expect(try eval("eval(\"1 + 2\")!") == .int(3))
        #expect(try eval("eval(\"let x = 40\\nx + 2\")!") == .int(42))
        #expect(try eval("eval(\"\").failure != nil") == .bool(true))                 // an empty program, as at the top — a failure now
        #expect(try eval("eval(\"eval(\\\"3\\\")!\")!") == .int(3))
        let v = "let v: SION = [\"a\": [1, 2.5, nil], \"d\": Data(\"AQID\"), \"t\": .Date(0.0)]\n"
        #expect(try eval(v + "eval(v.String())! == v") == .bool(true))
        #expect(try eval(v + "eval(v.String(.pretty))! == v") == .bool(true))
        #expect(try eval("eval(\"hi\".String(.quoted)) == Result.success(\"hi\")") == .bool(true))
        #expect(try eval("eval(255.String(.hex))! == 255") == .bool(true))
        #expect(try eval("struct P { var x: Int = 0 }\nlet p = P(x: 3)\neval(p.String())! == p") == .bool(true))
        #expect(try eval("enum E { case v(Int) }\neval(E.v(7).String())! == E.v(7)") == .bool(true))
        #expect(try eval("eval((x: 1, [2]).String())! == (x: 1, [2])") == .bool(true))
    }

    @Test("it runs at the program's top level: sees it, declares into it, not a caller's locals")
    func scope() throws {
        #expect(try eval("let n = 5\neval(\"n * 2\")!") == .int(10))
        #expect(try eval("var n = 5\neval(\"n = 6\")\nn") == .int(6))
        #expect(try eval("eval(\"let y = 1\")\ny") == .int(1))
        #expect(try eval("eval(\"struct Q { var a: Int = 1 }\")\nQ().a") == .int(1))
        #expect(try eval("let f = { a in eval(\"a\") }\nf(1).failure") == .string("type error: undefined variable 'a'"))
        #expect(try eval("let z = 1\neval(\"let z = 2\").failure != nil") == .bool(true))       // redeclaration, as at the top
        #expect(try eval("let e = eval\ne(\"2\")!") == .int(2))
        #expect(try eval("eval.Type == Function") == .bool(true))
        #expect(try eval("[\"1\", \"2\"].map(eval).map { $0! }") == .array([.int(1), .int(2)]))
        #expect(try eval("[\"1\", \"x\"].map(eval).map { $0.success }") == .array([.int(1), .nil]))
    }

    @Test("in a module, eval runs at the module's own top level (round 123) — while it loads, and from its functions after")
    func moduleScope() throws {
        let files = ["m.swt": """
            let secret = 7
            export let peek = { eval("secret") }
            export let define = { eval("let minted = 1") }
            export let made = { eval("minted") }
            export let outside = { eval("mainName") }
            export let loaded = eval("secret + 1")
            let f = { a in eval("a") }
            """]
        let i = Swiftalk.Interpreter()
        i.moduleLoader = { spec in
            guard let source = files[spec] else { throw SwiftalkError.type("no module '\(spec)'") }
            return source
        }
        #expect(try i.eval("import M from \"./m.swt\"\nM.loaded!") == .int(8))                // while loading
        #expect(try i.eval("M.peek()!") == .int(7))                                          // the module's top, not exported
        #expect(throws: SwiftalkError.self) { try i.eval("secret") }
        #expect(try i.eval("let mainName = 1\nmainName") == .int(1))
        #expect(try i.eval("M.outside().failure != nil") == .bool(true))                    // the module's top, not the program's
        #expect(try i.eval("M.define()\nM.made()!") == .int(1))                                // declared into the module's top
        #expect(throws: SwiftalkError.self) { try i.eval("minted") }
        #expect(try i.eval("eval(\"mainName\")!") == .int(1))                                 // back in the program, its own top
    }

    @Test("errors are the language's: a syntax error, a wrong argument, control flow outside its place")
    func errors() throws {
        #expect(try eval("eval(\"1 +\").failure") == .string("syntax error: unexpected token end of input"))
        #expect(throws: SwiftalkError.self) { try eval("eval(1)") }
        #expect(throws: SwiftalkError.self) { try eval("eval()") }
        #expect(throws: SwiftalkError.self) { try eval("eval(\"a\", \"b\")") }
        #expect(try eval("eval(\"break\").failure") == .string("syntax error: 'break'/'continue' outside a loop"))
        #expect(try eval("eval(\"return 1\").failure") == .string("syntax error: 'return' outside a function"))
        #expect(try eval("eval(\"nope\").failure") == .string("type error: undefined variable 'nope'"))
        #expect(try eval("eval(\"1 / 0\").failure") == .string("division by zero"))
        #expect(try eval("eval(\"1 + 1\")") == (try eval("Result.success(2)")))
        #expect(try eval("eval(\"1 + 1\") ?? 0") == .int(2))
        #expect(try eval("eval(\"1 +\") ?? 0") == .int(0))
        #expect(try eval("let f = { eval(\"boom\")?; 1 }\nf().failure != nil") == .bool(true))   // ? propagates the failure
        #expect(throws: SwiftalkError.self) { try eval("eval(\"boom\")!") }                        // ! traps
    }
}
