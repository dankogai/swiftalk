import Testing
@testable import Swiftalk

@Suite("structs: COW values with memberwise init (§4, round 46)")
struct StructTests {
    private let point = "struct Point {\nvar x: Int = 0\nvar y: Int = 0\n}"

    @Test("declaration and memberwise construction: labels, positionals, defaults")
    func construction() throws {
        #expect(try eval("\(point)\nPoint(x: 1, y: 2).x") == .int(1))
        #expect(try eval("\(point)\nPoint(y: 2, x: 1).x") == .int(1))       // reorderable (§2.3)
        #expect(try eval("\(point)\nPoint(1, 2).y") == .int(2))             // positional
        #expect(try eval("\(point)\nPoint().x") == .int(0))                 // defaults
        #expect(try eval("\(point)\nPoint(x: 5).y") == .int(0))             // partial
        #expect(try eval("struct S { var a: Int\nvar b = \"?\" }\nS(a: 1).b") == .string("?"))
        #expect(throws: SwiftalkError.self) { try eval("struct S { var a: Int }\nS()") }        // required
        #expect(throws: SwiftalkError.self) { try eval("\(point)\nPoint(z: 1)") }               // unknown
        #expect(throws: SwiftalkError.self) { try eval("\(point)\nPoint(x: 1.5)") }             // Int ≠ Double
        #expect(throws: SwiftalkError.self) { try eval("\(point)\nPoint(1, 2, 3)") }            // too many
        #expect(throws: SwiftalkError.self) { try eval("struct S { var a }") }                  // needs type or default
    }

    @Test("property mutation through var; let bindings and let properties refuse")
    func mutation() throws {
        #expect(try eval("\(point)\nvar p = Point()\np.x = 42\np.x") == .int(42))
        #expect(try eval("\(point)\nvar p = Point()\np.x = p.x + 1\np.x = p.x + 1\np.x") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("\(point)\nlet p = Point()\np.x = 1") }
        #expect(throws: SwiftalkError.self) {
            try eval("struct S { let k: Int = 1 }\nvar s = S()\ns.k = 2")
        }
        // the §3 lock reaches properties
        #expect(throws: SwiftalkError.self) { try eval("\(point)\nvar p = Point()\np.x = \"1\"") }
    }

    @Test("COW value semantics: a copy is a copy (§4)")
    func valueSemantics() throws {
        #expect(try eval("\(point)\nvar a = Point(x: 1, y: 1)\nlet b = a\na.x = 9\nb.x") == .int(1))
        #expect(try eval("\(point)\nvar a = Point(x: 1, y: 1)\nlet b = a\na.x = 9\na.x") == .int(9))
    }

    @Test("nested paths: struct in struct, arrays of structs, structs of arrays")
    func nestedPaths() throws {
        let rect = "\(point)\nstruct Rect {\nvar origin: Point = Point()\nvar w: Int = 0\n}"
        #expect(try eval("\(rect)\nvar r = Rect()\nr.origin.x = 5\nr.origin.x") == .int(5))
        #expect(try eval("\(point)\nvar ps = [Point(), Point()]\nps[1].y = 7\nps[1].y") == .int(7))
        #expect(try eval("\(point)\nvar ps = [Point(), Point()]\nps[1].y = 7\nps[0].y") == .int(0))
        #expect(try eval("struct Bag { var items: Array = [] }\nvar b = Bag()\nb.items = [1]\nb.items[0] = 9\nb.items") == .array([.int(9)]))
    }

    @Test("structural equality, dict keys, .Type/.name/conforms")
    func structsAsValues() throws {
        #expect(try eval("\(point)\nPoint(x: 1, y: 2) == Point(y: 2, x: 1)") == .bool(true))
        #expect(try eval("\(point)\nPoint(x: 1, y: 2) != Point()") == .bool(true))
        #expect(try eval("\(point)\n[Point(): \"origin\"][Point()]") == .string("origin"))
        #expect(try eval("\(point)\nPoint().Type == Point") == .bool(true))
        #expect(try eval("\(point)\nPoint().Type.name") == .string("Point"))
        #expect(try eval("\(point)\nPoint.conforms(to: Hashable)") == .bool(true))
        #expect(try eval("\(point)\nPoint.conforms(to: Sequence)") == .bool(false))
        #expect(try eval("\(point)\nvar p: Point = Point()\np = Point(x: 1)\np.x") == .int(1))
        #expect(throws: SwiftalkError.self) { try eval("\(point)\nvar p: Point = Point()\np = 42") }
    }

    @Test("source form round-trips where the struct is declared (§3d)")
    func roundTrip() throws {
        let interp = Interpreter()
        _ = try interp.eval(point)
        let v = try interp.eval("Point(x: 1, y: 2)")
        #expect(v.sourceString() == "Point(x: 1, y: 2)")
        #expect(try interp.eval(v.sourceString()) == v)
        // nested, with debug form
        _ = try interp.eval("struct Wrap { var p: Point = Point() }")
        #expect(try interp.eval("Wrap(p: Point(x: 255, y: 0)).String(.quoted)")
            == .string("Wrap(p: Point(x: 255, y: 0))"))
    }

    @Test("defaults evaluate at construction, in the declaring scope")
    func defaults() throws {
        #expect(try eval("""
            let base = 40
            struct S { var v: Int = base + 2 }
            S().v
            """) == .int(42))
    }
}
