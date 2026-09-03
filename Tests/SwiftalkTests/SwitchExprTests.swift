import Testing
@testable import Swiftalk

@Suite("switch is an expression (round 79, Swift 5.9's)")
struct SwitchExprTests {
    let shape = """
        enum Shape {
            case circle(r: Double)
            case rect(w: Double, h: Double)
        }
        """

    @Test("let x = switch ...; return switch ...; a bare switch yields at top level")
    func expressionPositions() throws {
        #expect(try eval("""
            let name = switch 2 { case 1: "one" case 2: "two" default: "many" }
            name
            """) == .string("two"))
        #expect(try eval("""
            let sign = { n in return switch n { case 0: 0 case 1...100: 1 default: -1 } }
            [sign(0), sign(7), sign(-7)]
            """) == .array([.int(0), .int(1), .int(-1)]))
        #expect(try eval("switch 3 { case 3: \"three\" }") == .string("three"))
        #expect(try eval("1 + switch true { case true: 1 case false: 2 }") == .int(2))
    }

    @Test("implicit return: { s in switch s { ... } } — §14's area example, verbatim")
    func implicitReturn() throws {
        #expect(try eval("""
            \(shape)
            let area = { s in
                switch s {
                case let r = .circle:    3.14159265358979 * r * r
                case let (w, h) = .rect: w * h
                }
            }
            [area(Shape.rect(w: 3.0, h: 4.0)), area(Shape.circle(r: 1.0))]
            """) == .array([.double(12.0), .double(3.14159265358979)]))
        #expect(try eval("[1, 2, 3].map { switch $0 { case 2: \"two\" default: \"other\" } }")
                == .array([.string("other"), .string("two"), .string("other")]))
    }

    @Test("a branch's value is its last statement's — the closure-body rule; a non-expression ends in nil")
    func branchValue() throws {
        #expect(try eval("switch 1 { case 1: let x = 10; x * 2 }") == .int(20))
        #expect(try eval("switch 1 { case 1: var x = 1; x = 2 }") == .int(2))   // an assignment's value, as everywhere
        #expect(try eval("switch 1 { case 1: if false { 1 } }") == .nil)
        #expect(try eval("switch 1 { default: 5 }") == .int(5))
        #expect(try eval("switch 1 { case 2: 2 default: 5 }") == .int(5))
        // a bound case value flows out
        #expect(try eval("\(shape)\nswitch Shape.circle(r: 2.0) { case r = .circle: r * 2.0 default: 0.0 }")
                == .double(4.0))
    }

    @Test("nesting, and the value in a struct method")
    func nesting() throws {
        #expect(try eval("""
            let nested = switch 1 { case 1: switch 2 { case 2: "inner" default: "no" } default: "outer" }
            nested
            """) == .string("inner"))
        #expect(try eval("""
            \(shape)
            extension Shape {
                let kind = { switch self { case .circle: "round" case .rect: "boxy" } }
            }
            [Shape.circle(r: 1.0).kind(), Shape.rect(w: 1.0, h: 1.0).kind()]
            """) == .array([.string("round"), .string("boxy")]))
    }

    @Test("still a statement: return inside a branch returns from the function; exhaustiveness holds")
    func statementUse() throws {
        #expect(try eval("""
            let f = { n in
                switch n {
                case 0: return "zero"
                default: 1
                }
                "nonzero"
            }
            [f(0), f(1)]
            """) == .array([.string("zero"), .string("nonzero")]))
        #expect(throws: SwiftalkError.self) { try eval("let x = switch 9 { case 1: 1 }") }
    }
}
