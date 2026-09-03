import Testing
@testable import Swiftalk

@Suite("enums: declaration, construction, switch (§7, round 45; case let r = .circle since round 78)")
struct EnumTests {
    private let shape = """
        enum Shape {
            case circle(r: Double)
            case rect(w: Double, h: Double)
            case point
        }
        """

    @Test("declaration and case construction, labels optional and reorderable (§2.3)")
    func construction() throws {
        #expect(try eval("\(shape)\nShape.circle(r: 3.0) == Shape.circle(3.0)") == .bool(true))
        #expect(try eval("\(shape)\nShape.rect(h: 2.0, w: 1.0) == Shape.rect(w: 1.0, h: 2.0)") == .bool(true))
        #expect(try eval("\(shape)\nShape.point == Shape.point") == .bool(true))
        #expect(try eval("\(shape)\nShape.circle(r: 1.0) == Shape.point") == .bool(false))
        #expect(try eval("enum E { case a, b }\nE.a != E.b") == .bool(true))
    }

    @Test("construction errors: unknown case, arity, associated types, calling the type")
    func constructionErrors() throws {
        #expect(throws: SwiftalkError.self) { try eval("\(shape)\nShape.triangle") }
        #expect(throws: SwiftalkError.self) { try eval("\(shape)\nShape.circle(1.0, 2.0)") }
        #expect(throws: SwiftalkError.self) { try eval("\(shape)\nShape.circle(r: 1)") }   // Int ≠ Double
        #expect(throws: SwiftalkError.self) { try eval("\(shape)\nShape.circle") }         // call it
        #expect(throws: SwiftalkError.self) { try eval("\(shape)\nShape.point(1)") }
        #expect(throws: SwiftalkError.self) { try eval("\(shape)\nShape(1)") }             // via a case
        #expect(throws: SwiftalkError.self) { try eval("\(shape)\nShape.circle(x: 1.0)") }
    }

    @Test("enums are values: type identity, .name, synthesized conformance, dict keys")
    func enumsAsValues() throws {
        #expect(try eval("\(shape)\nShape.point.Type == Shape") == .bool(true))
        #expect(try eval("\(shape)\nShape.point.Type.name") == .string("Shape"))
        #expect(try eval("\(shape)\nShape.Type == Function") == .bool(true))
        #expect(try eval("\(shape)\nShape.conforms(to: Equatable)") == .bool(true))
        #expect(try eval("\(shape)\nShape.conforms(to: Hashable)") == .bool(true))
        #expect(try eval("\(shape)\nShape.conforms(to: Sequence)") == .bool(false))
        #expect(try eval("\(shape)\n[Shape.point: \"origin\"][Shape.point]") == .string("origin"))
        #expect(try eval("\(shape)\nvar s: Shape = .point\ns = Shape.circle(r: 1.0)\ns == Shape.circle(r: 1.0)") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("\(shape)\nvar s: Shape = .point\ns = 42") }
    }

    @Test("source form round-trips where the enum is declared (§3d)")
    func roundTrip() throws {
        let interp = Interpreter()
        _ = try interp.eval(shape)
        let v = try interp.eval("Shape.circle(r: 3.0)")
        #expect(v.sourceString() == "Shape.circle(r: 3.0)")
        #expect(try interp.eval(v.sourceString()) == v)
        let p = try interp.eval("Shape.point")
        #expect(p.sourceString() == "Shape.point")
        #expect(try interp.eval("Shape.rect(w: 1.0, h: 2.0).String()") == .string("Shape.rect(w: 1.0, h: 2.0)"))
    }

    @Test("switch destructures with case let; §14's area example runs")
    func switchDestructuring() throws {
        #expect(try eval("""
            \(shape)
            let area = { s in
                switch s {
                case let r = .circle: return 3.14159265358979 * r * r
                case let (w, h) = .rect: return w * h
                case .point: return 0.0
                }
            }
            [area(Shape.rect(w: 3.0, h: 4.0)), area(Shape.point)]
            """) == .array([.double(12.0), .double(0.0)]))
    }

    @Test("runtime exhaustiveness: no match and no default is an error (§7)")
    func exhaustiveness() throws {
        #expect(throws: SwiftalkError.self) {
            try eval("\(shape)\nswitch Shape.point { case let r = .circle: r }")
        }
        #expect(try eval("""
            \(shape)
            var r = 0
            switch Shape.point {
            case let x = .circle: r = 1
            default: r = 2
            }
            r
            """) == .int(2))
    }

    @Test("bare .case matches any payload; patterns share a clause")
    func patternForms() throws {
        #expect(try eval("""
            \(shape)
            var kind = ""
            switch Shape.circle(r: 9.0) {
            case .circle: kind = "round"
            case .rect, .point: kind = "angular"
            }
            kind
            """) == .string("round"))
    }

    @Test("switch also matches plain values: literals, ranges, wildcard")
    func valueSwitch() throws {
        #expect(try eval("""
            var out = []
            for i in 1...6 {
                switch i {
                case 1, 2: out = out + ["low"]
                case 3...4: out = out + ["mid"]
                case _: out = out + ["high"]
                }
            }
            out
            """) == .array([.string("low"), .string("low"), .string("mid"),
                            .string("mid"), .string("high"), .string("high")]))
        #expect(throws: SwiftalkError.self) { try eval("switch 9 { case 1: 1 }") }
    }

    @Test("annotation-directed .case initializers; Swift's if case / .case(let x) are gone (round 78)")
    func ifCase() throws {
        #expect(try eval("""
            \(shape)
            let s: Shape = .circle(r: 5.0)
            var r = 0.0
            if let radius = s.circle { r = radius } else { r = -1.0 }
            r
            """) == .double(5.0))
        #expect(try eval("""
            \(shape)
            let s: Shape = .point
            var r = 0.0
            if radius = s.circle { r = radius } else { r = -1.0 }
            r
            """) == .double(-1.0))
        #expect(throws: SwiftalkError.self) {
            try eval("\(shape)\nif case .circle(let r) = Shape.point { }")
        }
        #expect(throws: SwiftalkError.self) {
            try eval("\(shape)\nswitch Shape.point { case .circle(let r): r }")
        }
    }

    @Test("boxing, not flat: an enum value's typeName is its enum (§3c contrast)")
    func boxing() throws {
        #expect(try eval("enum Wrap { case just(Int) }\nWrap.just(42).Type.name") == .string("Wrap"))
        // the payload stays inside until destructured
        #expect(try eval("""
            enum Wrap { case just(Int) }
            var n = 0
            if x = Wrap.just(42).just { n = x }
            n
            """) == .int(42))
        #expect(throws: SwiftalkError.self) { try eval("enum W { case a }\nW.a + 1") }
    }
}

@Suite("case accessors: .casename gives the value or nil (round 46)")
struct CaseAccessorTests {
    private let shape = """
        enum Shape {
            case circle(r: Double)
            case rect(w: Double, h: Double)
            case point
        }
        """

    @Test("one payload comes bare; a mismatched case is nil")
    func single() throws {
        #expect(try eval("\(shape)\nShape.circle(r: 3.0).circle") == .double(3.0))
        #expect(try eval("\(shape)\nShape.circle(r: 3.0).rect") == .nil)
        #expect(try eval("\(shape)\nShape.point.circle") == .nil)
        #expect(try eval("\(shape)\nlet s = Shape.circle(r: 2.0)\ns.circle * 10.0") == .double(20.0))
    }

    @Test("several payloads come as an Array")
    func multiple() throws {
        // several payloads: a tuple, labeled as the case declares (round 77)
        #expect(try eval("\(shape)\nShape.rect(w: 3.0, h: 4.0).rect")
            == .tuple([.double(3.0), .double(4.0)], labels: ["w", "h"]))
        #expect(try eval("\(shape)\nShape.rect(w: 3.0, h: 4.0).rect.h") == .double(4.0))
        #expect(try eval("\(shape)\nShape.rect(w: 3.0, h: 4.0).rect.1") == .double(4.0))
        #expect(try eval("\(shape)\nShape.rect(w: 3.0, h: 4.0).rect.String()")
            == .string("(w: 3.0, h: 4.0)"))
        #expect(try eval("\(shape)\nShape.point.rect") == .nil)
    }

    @Test("a payload-less case answers with itself — s.point != nil asks 'is it .point?'")
    func payloadLess() throws {
        #expect(try eval("\(shape)\nShape.point.point == Shape.point") == .bool(true))
        #expect(try eval("\(shape)\nShape.point.point != nil") == .bool(true))
        #expect(try eval("\(shape)\nShape.circle(r: 1.0).point == nil") == .bool(true))
    }

    @Test("accessors replace if-case ceremony in real flow")
    func flow() throws {
        #expect(try eval("""
            \(shape)
            let shapes = [Shape.circle(r: 1.0), Shape.point, Shape.circle(r: 3.0)]
            var total = 0.0
            for s in shapes {
                if s.circle != nil { total = total + s.circle }
            }
            total
            """) == .double(4.0))
    }

    @Test("non-case members still behave: unknown errors, builtins reachable")
    func boundaries() throws {
        #expect(throws: SwiftalkError.self) { try eval("\(shape)\nShape.point.triangle") }
        #expect(try eval("\(shape)\nShape.point.Type == Shape") == .bool(true))
        #expect(try eval("\(shape)\nShape.circle(r: 1.0).String()") == .string("Shape.circle(r: 1.0)"))
    }
}
