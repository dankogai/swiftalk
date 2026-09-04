import Testing
@testable import Swiftalk

@Suite("destructuring without the parentheses: let a, b = t; case let w, h = .rect (round 99)")
struct BareDestructuringTests {
    @Test("let / var: a comma after the first name makes a tuple pattern; nesting and _ as before")
    func declarations() throws {
        #expect(try eval("let a, b = (1, 2)\na + b") == .int(3))
        #expect(try eval("var a, b = (1, 2)\na = 9\na + b") == .int(11))
        #expect(try eval("var x, (y, z) = (10, (20, 30))\nx + y + z") == .int(60))
        #expect(try eval("let _, second = (\"skip\", \"take\")\nsecond") == .string("take"))
        #expect(try eval("let a, b = (x: 1, y: 2)\n[a, b]") == .array([.int(1), .int(2)]))   // labels ignored by position
        #expect(try eval("let a, b, c = (1, 2, 3)\nc") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval("let a, b = 5") }
        #expect(throws: SwiftalkError.self) { try eval("let a, b = (1, 2, 3)") }
        #expect(throws: SwiftalkError.self) { try eval("let a, b: Int = (1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("let a, a = (1, 2)") }
    }

    @Test("for and closure parameters already had it; a switch's case let gains it; if/while keep the comma for conditions")
    func otherSites() throws {
        #expect(try eval("let d = [\"k\": 42]\nvar r = \"\"\nfor k, v in d { r = k + \"=\" + v.String() }\nr") == .string("k=42"))
        #expect(try eval("[\"k\": 42].map { k, v in k + v.String() }") == .array([.string("k42")]))
        #expect(try eval("""
            enum Shape { case rect(w: Double, h: Double); case point }
            let area = { s in switch s { case let w, h = .rect: w * h default: 0.0 } }
            [area(Shape.rect(w: 3.0, h: 4.0)), area(Shape.point)]
            """) == .array([.double(12.0), .double(0.0)]))
        #expect(try eval("switch \"2026-09\" { case let _, y, m = /(\\d+)-(\\d+)/: y + m default: \"\" }") == .string("202609"))
        // a bare comma in a case still separates alternatives
        #expect(try eval("switch 2 { case 1, 2: \"low\" default: \"high\" }") == .string("low"))
        // in if/while a comma is the condition list: `if let a, b = t` is two conditions
        #expect(try eval("let a = 1\nvar r = 0\nif let a, b = (5, 6) { r = b.0 }\nr") == .int(5))
    }
}
