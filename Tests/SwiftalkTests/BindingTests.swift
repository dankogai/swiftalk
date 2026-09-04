import Testing
@testable import Swiftalk

@Suite("let/var bindings with type locks (§2.2, §3, §3a)")
struct BindingTests {
    @Test("let binds; var rebinds; programs return the last value")
    func basics() throws {
        #expect(try eval("let x = 42\nx") == .int(42))
        #expect(try eval("var x = 1\nx = 2\nx") == .int(2))
        #expect(try eval("let a = 1; let b = 2; a + b") == .int(3))
        #expect(try eval("let x = 42") == .int(42))          // declaration yields its value
        #expect(try eval("var s = \"swift\"\ns = s + \"alk\"\ns") == .string("swiftalk"))
    }

    @Test("the type lock: x = 1 then x = \"1\" is a runtime error (§3)")
    func typeLock() throws {
        #expect(throws: SwiftalkError.self) { try eval("var x = 1\nx = \"1\"") }
        #expect(throws: SwiftalkError.self) { try eval("var x = 1\nx = 1.5") }
        #expect(throws: SwiftalkError.self) { try eval("var x = 1\nx = nil") }
        #expect(try eval("var x = 1\nx = 2\nx") == .int(2))  // same type is fine
    }

    @Test("let is immutable; redeclaration is an error; undeclared assignment is an error (§2.2 file mode)")
    func bindingErrors() throws {
        #expect(throws: SwiftalkError.self) { try eval("let x = 1\nx = 2") }
        #expect(throws: SwiftalkError.self) { try eval("let x = 1\nlet x = 2") }
        #expect(throws: SwiftalkError.self) { try eval("var x = 1\nvar x = 2") }
        #expect(throws: SwiftalkError.self) { try eval("x = 1") }
        #expect(throws: SwiftalkError.self) { try eval("y") }
    }

    @Test("annotations are enforced at runtime (§3)")
    func annotations() throws {
        #expect(try eval("var x: Int = 1\nx + 1") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("var x: Int = 1.5") }
        #expect(throws: SwiftalkError.self) { try eval("var x: Nonsense = 1") }
        #expect(try eval("let d: Dictionary = [\"a\": 1]\nd.Type == Dictionary") == .bool(true))
    }

    @Test("flat optionals: Int? admits Int and nil; bare nil has nothing to infer (§3a)")
    func optionals() throws {
        #expect(try eval("var x: Int? = nil\nx = 2\nx") == .int(2))
        #expect(try eval("var x: Int? = 2\nx = nil\nx") == .nil)
        #expect(try eval("var x: Int? = 2\nx.Type == Int") == .bool(true))   // flat — never Optional<Int>
        #expect(try eval("var x: Int? = nil\nx.Type == Nil") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("var x: Int? = \"s\"") }
        #expect(try eval("var x = nil\nx = 1\nx = \"s\"\nx") == .string("s"))   // nil infers Any since round 101
    }

    @Test("an Interpreter's environment persists across eval calls (the REPL's engine)")
    func persistence() throws {
        let interp = Interpreter()
        #expect(try interp.eval("var count = 1") == .int(1))
        #expect(try interp.eval("count = count + 1") == .int(2))
        #expect(try interp.eval("count * 10") == .int(20))
        #expect(throws: SwiftalkError.self) { try interp.eval("count = \"three\"") }
        #expect(try interp.eval("count") == .int(2))         // failed assignment left it intact
        // the free function stays one-shot
        #expect(throws: SwiftalkError.self) { try eval("count") }
    }

    @Test("newlines separate statements but flow freely inside brackets")
    func newlines() throws {
        #expect(try eval("let a = [\n  1,\n  2,\n]\na") == .array([.int(1), .int(2)]))
        #expect(try eval("\n\nlet x = 1\n\n\nx\n") == .int(1))
        #expect(throws: SwiftalkError.self) { try eval("let x = 1 let y = 2") }
    }

    @Test("bindings round-trip through .String() like any value (§3d)")
    func roundTripThroughBindings() throws {
        #expect(try eval("let x = [1: \"one\"]\nx.String()") == .string("[1: \"one\"]"))
        let interp = Interpreter()
        // round 59: a mixed literal binds only under an annotation
        _ = try interp.eval("let v: [Primitives] = [1, \"one\", 2.0]")
        let src = try interp.eval("v.String()")
        guard case .string(let s) = src else { throw SwiftalkError.type("expected string") }
        #expect(try interp.eval(s) == interp.eval("v"))      // eval(v.String()) == v
    }
}
