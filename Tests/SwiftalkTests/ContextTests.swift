import Testing
@testable import Swiftalk

@Suite("Context — an execution state: global, Context(), eval(source, ctx) (round 237)")
struct ContextTests {
    @Test("the round's example: a disposable eval, global, a kept context")
    func example() throws {
        #expect(try eval("""
            var v = 0.0
            eval("v = 1.0")
            let a = v
            eval("v += 1.0", global)
            let b = v
            var ctx = Context()
            eval("v = 42.0", ctx)
            let c = v
            let d = eval("v += 0.5", ctx)!
            [a, b, c, d]
            """) == .array([.double(0.0), .double(1.0), .double(1.0), .double(42.5)]))
    }

    @Test("the default context is a copy, gone when eval returns; global is the program's own")
    func disposable() throws {
        #expect(throws: SwiftalkError.self) { try eval("eval(\"let fresh = 1\")\nfresh") }
        #expect(try eval("eval(\"let fresh = 1\\nfresh\")!") == .int(1))
        #expect(try eval("eval(\"let kept = 2\", global)\nkept") == .int(2))
        #expect(try eval("var n = 5\neval(\"n = 6\")\nn") == .int(5))
        #expect(try eval("var n = 5\neval(\"n = 6\", global)\nn") == .int(6))
        #expect(try eval("let n = 5\neval(\"n * 2\")!") == .int(10))                        // a copy sees what the top level has
        #expect(throws: SwiftalkError.self) { try eval("eval(\"struct Q { var a: Int = 1 }\")\nQ().a") }
        #expect(try eval("eval(\"struct Q { var a: Int = 1 }\", global)\nQ().a") == .int(1))
    }

    @Test("a kept context holds its declarations and assignments; its eval defaults to a copy of it")
    func kept() throws {
        #expect(try eval("let ctx = Context()\neval(\"let x = 3\", ctx)\neval(\"x\", ctx)!") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval("let ctx = Context()\neval(\"let x = 3\", ctx)\nx") }
        #expect(try eval("let ctx = Context()\neval(\"let x = 3\", ctx)\neval(\"eval(\\\"x\\\")!\", ctx)!") == .int(3))
        #expect(try eval("let ctx = Context()\neval(\"eval(\\\"let deeper = 4\\\")\\ndeeper\", ctx).failure != nil") == .bool(true))
        #expect(try eval("let ctx = Context()\neval(\"struct Pt { var x: Int = 0 }\", ctx)\neval(\"Pt(x: 1).x\", ctx)!") == .int(1))
        #expect(try eval("let ctx = Context()\nlet other = Context()\neval(\"let x = 3\", ctx)\neval(\"x\", other).failure != nil") == .bool(true))
    }

    @Test("a copy is taken when the context is made: bindings as they are, locks included")
    func copy() throws {
        #expect(try eval("var v = 1\nlet ctx = Context()\nv = 2\neval(\"v\", ctx)!") == .int(1))
        #expect(try eval("let ctx = Context()\nvar later = 1\neval(\"later\", ctx).failure != nil") == .bool(true))
        #expect(try eval("var v = 1\nlet ctx = Context()\neval(\"v = \\\"s\\\"\", ctx).failure") == .string("type error: cannot assign String to 'v' of type Int"))
        #expect(try eval("let k = 1\nlet ctx = Context()\neval(\"k = 2\", ctx).failure") == .string("type error: cannot assign to let constant 'k'"))
        #expect(try eval("let z = 1\neval(\"let z = 2\").failure != nil") == .bool(true))      // redeclaration, in the copy as at the top
        #expect(try eval("var a = [1]\neval(\"a.append(2)\")\na") == .array([.int(1)]))
        #expect(try eval("var a = [1]\nlet c = Context()\neval(\"a.append(2); a\", c)!") == .array([.int(1), .int(2)]))
        #expect(try eval("var a = [1]\nlet c = Context()\neval(\"a.append(2)\", c)\na") == .array([.int(1)]))
        #expect(try eval("var v = 0\nlet bump = { v += 1 }\neval(\"bump()\")\nv") == .int(1))  // a Function keeps the scope it was made in
    }

    @Test("Context as a value: type, identity, printing, annotations, and what is refused")
    func value() throws {
        #expect(try eval("global.Type == Context") == .bool(true))
        #expect(try eval("Context().Type == Context") == .bool(true))
        #expect(try eval("global == global") == .bool(true))
        #expect(try eval("Context() == Context()") == .bool(false))
        #expect(try eval("let c = Context()\nc == c") == .bool(true))
        #expect(try eval("global.String()") == .string("global"))
        #expect(try eval("Context().String()") == .string("Context()"))
        #expect(try eval("[global: 1][global]") == .int(1))
        #expect(try eval("let c: Context = Context()\nc.Type.name") == .string("Context"))
        #expect(try eval("let g: Context = global\ng == global") == .bool(true))
        #expect(try eval("Context.name") == .string("Context"))
        #expect(throws: SwiftalkError.self) { try eval("let bad: Context = 1") }
        #expect(throws: SwiftalkError.self) { try eval("global = Context()") }
        #expect(throws: SwiftalkError.self) { try eval("let global = 1") }
        #expect(throws: SwiftalkError.self) { try eval("Context(1)") }
        #expect(throws: SwiftalkError.self) { try eval("[1].map(Context)") }
        #expect(throws: SwiftalkError.self) { try eval("Context()()") }
        #expect(throws: SwiftalkError.self) { try eval("eval(\"1\", 2)") }
        #expect(throws: SwiftalkError.self) { try eval("eval(\"1\", global, 3)") }
        #expect(throws: SwiftalkError.self) { try eval("eval(1, global)") }
    }

    @Test("a module: Context() copies the module's top level, global reaches the program's")
    func module() throws {
        let files = ["m.swt": """
            let secret = 7
            let scope = Context()
            export let keep = { eval("let minted = 1", scope) }
            export let read = { eval("minted", scope) }
            export let peek = { eval("secret") }
            export let leak = { eval("let leaked = 9", global) }
            export let fromGlobal = { eval("mainName", global) }
            """]
        let i = Swiftalk.Interpreter()
        i.moduleLoader = { spec in
            guard let source = files[spec] else { throw SwiftalkError.type("no module '\(spec)'") }
            return source
        }
        #expect(try i.eval("import M from \"./m.swt\"\nM.peek()!") == .int(7))               // a copy of the module's top level sees secret
        #expect(try i.eval("M.keep()\nM.read()!") == .int(1))                                  // kept in the module's own context
        #expect(throws: SwiftalkError.self) { try i.eval("minted") }
        #expect(try i.eval("M.leak()\nleaked") == .int(9))                                     // global is the program's, from anywhere
        #expect(try i.eval("let mainName = 1\nM.fromGlobal()!") == .int(1))
    }
}
