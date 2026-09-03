import Testing
@testable import Swiftalk

@Suite("where guards on switch cases (round 81)")
struct SwitchWhereTests {
    let shape = """
        enum Shape {
            case circle(r: Double)
            case rect(w: Double, h: Double)
        }
        """

    @Test("a guard sees the pattern's bindings; false falls through to the next alternative")
    func guardsOnBindings() throws {
        #expect(try eval("""
            \(shape)
            let describe = { s in
                switch s {
                case let r = .circle where r > 1.0:   "big circle"
                case .circle:                         "small circle"
                case let (w, h) = .rect where w == h: "square \\(w)"
                case let (w, h) = .rect:              "rect \\(w)x\\(h)"
                }
            }
            [describe(Shape.circle(r: 2.0)), describe(Shape.circle(r: 0.5)),
             describe(Shape.rect(w: 2.0, h: 2.0)), describe(Shape.rect(w: 1.0, h: 2.0))]
            """) == .array([.string("big circle"), .string("small circle"),
                            .string("square 2.0"), .string("rect 1.0x2.0")]))
    }

    @Test("guards on wildcards, values, and ranges")
    func guardsOnValues() throws {
        #expect(try eval("""
            let classify = { n in
                switch n {
                case _ where n < 0:                     "negative"
                case 0:                                 "zero"
                case 1...9 where n / 2 * 2 == n:        "small even"
                case 1...9:                             "small odd"
                default:                                "large"
                }
            }
            [classify(-3), classify(0), classify(4), classify(7), classify(50)]
            """) == .array([.string("negative"), .string("zero"), .string("small even"),
                            .string("small odd"), .string("large")]))
    }

    @Test("a guard belongs to the pattern it follows (Swift's rule): case 1, 2 where c guards only the 2")
    func perPattern() throws {
        #expect(try eval("let flag = false\nswitch 2 { case 1, 2 where flag: \"guarded\" default: \"not\" }")
                == .string("not"))
        #expect(try eval("let flag = false\nswitch 1 { case 1, 2 where flag: \"guarded\" default: \"not\" }")
                == .string("guarded"))
        #expect(try eval("let flag = false\nswitch 1 { case 1 where flag, 2 where flag: \"guarded\" default: \"not\" }")
                == .string("not"))
    }

    @Test("a guard must be a Bool; a guarded miss with no default is non-exhaustive; where is contextual")
    func rules() throws {
        #expect(throws: SwiftalkError.self) { try eval("switch 2 { case 2 where 1: \"x\" }") }
        #expect(throws: SwiftalkError.self) { try eval("let flag = false\nswitch 2 { case 2 where flag: \"x\" }") }
        #expect(try eval("let where = 3\nwhere + 1") == .int(4))
        // the guard is parsed below the ternary: the clause's colon stays the clause's
        #expect(try eval("switch 2 { case 2 where true || false: \"x\" }") == .string("x"))
    }
}
