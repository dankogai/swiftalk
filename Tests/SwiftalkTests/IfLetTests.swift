import Testing
@testable import Swiftalk

@Suite("if let — and no guard, which is only `if not` (§9, round 60)")
struct IfLetTests {
    @Test("binds non-nil into the then-scope; nil takes the else")
    func basics() throws {
        #expect(try eval("""
            let ages = ["alice": 42]
            var out = "?"
            if let age = ages["alice"] { out = "is \\(age)" } else { out = "unknown" }
            out
            """) == .string("is 42"))
        #expect(try eval("""
            let ages = ["alice": 42]
            var out = "?"
            if let age = ages["bob"] { out = "is \\(age)" } else { out = "unknown" }
            out
            """) == .string("unknown"))
        // flat optionals: the bound value IS itself, no unwrap layer
        #expect(try eval("""
            var out = 0
            if let v = [1, 2][0] { out = v + 1 }
            out
            """) == .int(2))
    }

    @Test("the Swift 5.7 shorthand: if let x { } shadows the optional x")
    func shorthand() throws {
        #expect(try eval("""
            let x: Int? = 41
            var out = 0
            if let x { out = x + 1 }
            out
            """) == .int(42))
        #expect(try eval("""
            let x: Int? = nil
            var out = 0
            if let x { out = x } else { out = -1 }
            out
            """) == .int(-1))
    }

    @Test("comma chains: bindings and booleans mix, short-circuiting")
    func chains() throws {
        #expect(try eval("""
            let d = ["a": 1, "b": 5]
            var out = "?"
            if let a = d["a"], let b = d["b"], a < b { out = "\\(a) < \\(b)" }
            out
            """) == .string("1 < 5"))
        // a failed clause stops evaluation — later clauses never run
        #expect(try eval("""
            var hit = false
            let probe = { hit = true\nreturn 1 }
            let d = [:]
            if let a = d["missing"], let b = probe() { }
            hit
            """) == .bool(false))
        // a boolean clause is still strictly Bool — nothing is truthy
        #expect(throws: SwiftalkError.self) {
            try eval("if let x = [1][0], 1 { }")
        }
    }

    @Test("if var binds mutable; else if let chains compose")
    func varAndChains() throws {
        #expect(try eval("""
            var out = 0
            if var n = [41][0] { n = n + 1\nout = n }
            out
            """) == .int(42))
        #expect(try eval("""
            let d = ["b": 2]
            var out = "?"
            if let a = d["a"] { out = "a" }
            else if let b = d["b"] { out = "b\\(b)" }
            else { out = "none" }
            out
            """) == .string("b2"))
    }

    @Test("the non-goal, proven: guard never became a keyword")
    func guardIsJustAnIdentifier() throws {
        #expect(try eval("let guard = \"just an identifier\"\nguard")
            == .string("just an identifier"))
    }
}
