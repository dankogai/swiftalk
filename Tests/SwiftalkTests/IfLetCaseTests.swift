import Testing
@testable import Swiftalk

@Suite("if let r = s.circle — the accessor form, not `if case` (round 77)")
struct IfLetCaseTests {
    let shape = """
        enum Shape {
            case circle(r: Double)
            case rect(w: Double, h: Double)
            case pair(Int, Int)
            case point
        }
        """

    @Test("one payload: if let r = s.circle")
    func single() throws {
        #expect(try eval("""
            \(shape)
            let s = Shape.circle(r: 2.0)
            var out = "?"
            if let r = s.circle { out = "circle \\(r)" } else { out = "not a circle" }
            out
            """) == .string("circle 2.0"))
        #expect(try eval("""
            \(shape)
            let s = Shape.rect(w: 1.0, h: 2.0)
            var out = "?"
            if let r = s.circle { out = "circle \\(r)" } else { out = "not a circle" }
            out
            """) == .string("not a circle"))
    }

    @Test("several payloads: a tuple — if let (w, h) = s.rect, by position or label")
    func several() throws {
        #expect(try eval("""
            \(shape)
            let s = Shape.rect(w: 3.0, h: 4.0)
            var area = 0.0
            if let (w, h) = s.rect { area = w * h }
            area
            """) == .double(12.0))
        #expect(try eval("""
            \(shape)
            let s = Shape.rect(w: 3.0, h: 4.0)
            var out = ""
            if let (h: h, w: w) = s.rect { out = "\\(w)x\\(h)" }
            out
            """) == .string("3.0x4.0"))
        // unlabeled payloads make an unlabeled tuple
        #expect(try eval("\(shape)\nShape.pair(1, 2).pair") == .tuple([.int(1), .int(2)]))
        #expect(try eval("\(shape)\nlet (a, b) = Shape.pair(1, 2).pair!\na + b") == .int(3))
    }

    @Test("inside a method, .circle is self.circle; while let drains too")
    func implicitSelfAndWhile() throws {
        #expect(try eval("""
            enum Shape {
                case circle(r: Double)
                case rect(w: Double, h: Double)
                let area = {
                    if let r = .circle { return 3.0 * r * r }
                    if let (w, h) = .rect { return w * h }
                    return 0.0
                }
            }
            [Shape.circle(r: 1.0).area(), Shape.rect(w: 2.0, h: 3.0).area()]
            """) == .array([.double(3.0), .double(6.0)]))
    }
}
