import Testing
@testable import Swiftalk

@Suite("case let r = .circle, and let optional in conditions (round 78)")
struct SwitchBindTests {
    let shape = """
        enum Shape {
            case circle(r: Double)
            case rect(w: Double, h: Double)
            case pair(Int, Int)
            case point
        }
        """

    @Test("case let r = .circle / case let (w, h) = .rect: the accessor, then if let's rule")
    func caseLet() throws {
        #expect(try eval("""
            \(shape)
            let area = { s in
                switch s {
                case let r = .circle:    return 3.14159265358979 * r * r
                case let (w, h) = .rect: return w * h
                case .point:             return 0.0
                default:                 return -1.0
                }
            }
            [area(Shape.rect(w: 3.0, h: 4.0)), area(Shape.circle(r: 1.0)), area(Shape.point), area(Shape.pair(1, 2))]
            """) == .array([.double(12.0), .double(3.14159265358979), .double(0.0), .double(-1.0)]))
    }

    @Test("let is optional: case r = .circle; labeled and positional tuple patterns; var binds mutably")
    func bareBinding() throws {
        #expect(try eval("""
            \(shape)
            let describe = { s in
                switch s {
                case r = .circle:          return "circle \\(r)"
                case (h: h, w: w) = .rect: return "rect \\(w)x\\(h)"
                case (a, _) = .pair:       return "pair \\(a)"
                case var p = .point:       p = Shape.circle(r: 0.0); return "point -> \\(p)"
                }
            }
            [describe(Shape.circle(r: 2.0)), describe(Shape.rect(w: 3.0, h: 4.0)),
             describe(Shape.pair(7, 8)), describe(Shape.point)]
            """) == .array([.string("circle 2.0"), .string("rect 3.0x4.0"),
                            .string("pair 7"), .string("point -> Shape.circle(r: 0.0)")]))
    }

    @Test("a failed case binding leaves nothing behind; bare .name still matches any payload")
    func scopes() throws {
        #expect(try eval("""
            \(shape)
            var out = ""
            switch Shape.rect(w: 1.0, h: 2.0) {
            case r = .circle: out = "c"
            case .rect:       out = "r"
            }
            out
            """) == .string("r"))
        #expect(try eval("""
            \(shape)
            let r = "outer"
            var seen = ""
            switch Shape.point {
            case r = .circle: seen = "bound"
            default: seen = r
            }
            seen
            """) == .string("outer"))
        // no match, no default: runtime error (§7), as ever
        #expect(throws: SwiftalkError.self) {
            try eval("\(shape)\nswitch Shape.point { case r = .circle: r }")
        }
    }

    @Test("Result: case let e = .failure")
    func result() throws {
        #expect(try eval("""
            let classify = { r in
                switch r {
                case let v = .success: return "ok \\(v)"
                case let e = .failure: return "err \\(e)"
                }
            }
            [classify(Result.success(1)), classify(Result.failure("boom"))]
            """) == .array([.string("ok 1"), .string("err boom")]))
    }

    @Test("what a case may bind from: a case of the subject, or it is an error")
    func errors() throws {
        // the right side must be a .case of the subject
        #expect(throws: SwiftalkError.self) { try eval("switch 1 { case x = y: 1 }") }
        // a non-enum subject has no cases
        #expect(throws: SwiftalkError.self) { try eval("switch 1 { case let r = .c: 1 }") }
        // an enum subject lacking that case
        #expect(throws: SwiftalkError.self) {
            try eval("\(shape)\nswitch Shape.point { case r = .zzz: 1 }")
        }
        // a pattern that does not fit a non-nil payload is an error, not a mismatch
        #expect(throws: SwiftalkError.self) {
            try eval("\(shape)\nswitch Shape.circle(r: 1.0) { case (a, b) = .circle: 1 }")
        }
        // Swift's forms are gone, with hints
        #expect(throws: SwiftalkError.self) {
            try eval("\(shape)\nswitch Shape.point { case .circle(let r): r }")
        }
        #expect(throws: SwiftalkError.self) {
            try eval("\(shape)\nif case .circle(let r) = Shape.point { }")
        }
    }

    @Test("if v = opt / while x = d[i]: an = in a condition binds")
    func optionalLet() throws {
        #expect(try eval("""
            let opt: Int? = 7
            var r = 0
            if v = opt { r = v }
            r
            """) == .int(7))
        #expect(try eval("""
            let none: Int? = nil
            var r = 0
            if v = none { r = v } else { r = -1 }
            r
            """) == .int(-1))
        #expect(try eval("""
            let opt: Int? = 7
            var r = 0
            if var v = opt { v = v + 1; r = v }
            r
            """) == .int(8))
        #expect(try eval("""
            let t = (1, 2)
            var r = 0
            if (a, b) = t { r = a + b }
            r
            """) == .int(3))
        #expect(try eval("""
            let opt: Int? = 7
            var r = 0
            if v = opt, v > 5, w = opt { r = v + w }
            r
            """) == .int(14))
        #expect(try eval("""
            let d = [0: "a", 1: "b", 2: "c"]
            var i = 0
            var s = ""
            while c = d[i] { s = s + c; i = i + 1 }
            s
            """) == .string("abc"))
        // `if _ = opt` asks non-nil and binds nothing
        #expect(try eval("let opt: Int? = 7\nvar r = 0\nif _ = opt { r = 1 }\nr") == .int(1))
    }

    @Test("== is still a Bool test; a parenthesized expression is not a pattern")
    func stillBoolean() throws {
        #expect(try eval("let x = 3\nvar r = 0\nif x == 3 { r = 1 }\nr") == .int(1))
        #expect(try eval("let (a, b) = (1, 2)\nvar r = 0\nif (a, b) == (1, 2) { r = 1 }\nr") == .int(1))
        #expect(try eval("let a = 1\nvar r = 0\nif (a + 1) == 2 { r = 1 }\nr") == .int(1))
        // switch: `case x:` with x in scope is equality, `case (a, b):` a tuple to compare
        #expect(try eval("let x = 3\nswitch 3 { case x: \"eq\"\ndefault: \"ne\" }") == .string("eq"))
        #expect(try eval("""
            let x = 3
            var r = ""
            switch 3 { case x: r = "eq"
            default: r = "ne" }
            r
            """) == .string("eq"))
        #expect(try eval("""
            let (a, b) = (1, 2)
            var r = ""
            switch (1, 2) { case (a, b): r = "eq"
            default: r = "ne" }
            r
            """) == .string("eq"))
        // a bare optional variable asks non-nil since round 80 — see IfExprTests
        #expect(try eval("let v: Int? = 7\nif v { v }") == .int(7))
    }
}
