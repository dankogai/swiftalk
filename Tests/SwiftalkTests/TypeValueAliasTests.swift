import Testing
@testable import Swiftalk

@Suite("let I = Int is the alias — a type is a value (round 111; typealias retracted)")
struct TypeValueAliasTests {
    @Test("a binding that holds a type constructs, compares, and annotates — declarations, struct properties, enum payloads, nested")
    func aliasing() throws {
        #expect(try eval("let I = Int\nlet n: I = 42\nn") == .int(42))
        #expect(try eval("let I = Int\nI(\"7\")") == .int(7))
        #expect(try eval("let I = Int\n3.Type == I") == .bool(true))
        #expect(try eval("let I = Int\nI == Int") == .bool(true))
        #expect(try eval("struct Point { var x: Int }\nlet P = Point\nlet p: P = P(x: 1)\np.x") == .int(1))
        #expect(try eval("enum Shape { case circle(r: Double); case point }\nlet Sh = Shape\nlet s: Sh = .circle(r: 1.0)\n[s.circle, Sh.point == Shape.point]") == .array([.double(1), .bool(true)]))
        #expect(try eval("let R = Double\nstruct C { var r: R }\nC(r: 2.0).r") == .double(2))
        #expect(try eval("let N = Int\nenum Box { case some(N) }\nBox.some(3).some") == .int(3))
        #expect(try eval("let N = Int\nlet xs: [N] = [1, 2]\nxs.count") == .int(2))
        #expect(try eval("let f = { let T = Int; let v: T = 5; return v }\nf()") == .int(5))
        // the lock is the real type
        #expect(throws: SwiftalkError.self) { try eval("let I = Int\nlet x: I = \"s\"") }
        #expect(throws: SwiftalkError.self) { try eval("let R = Double\nstruct C { var r: R }\nC(r: 1)") }
        #expect(throws: SwiftalkError.self) { try eval("let N = Int\nenum Box { case some(N) }\nBox.some(\"s\")") }
    }

    @Test("the conversion law through a binding: with let S = String, 42.S() is 42.String(); a missing conversion fails by the real name")
    func conversionLaw() throws {
        #expect(try eval("let S = String\n42.S()") == .string("42"))
        #expect(try eval("let S = String\n[1, 2].S()") == .string("[1, 2]"))
        #expect(try eval("let S = String\n255.S(.hex)") == .string("0xff"))
        #expect(try eval("let D = Data\n\"hi\".D(.utf8).count") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("let D = Data\n42.D()") }
        #expect(throws: SwiftalkError.self) { try eval("let S = 3\n42.S()") }            // not a type: no law
        // a user method of the same name wins
        #expect(try eval("let S = String\nstruct Q { let S = { \"mine\" } }\nQ().S()") == .string("mine"))
    }

    @Test("what a binding cannot alias, and the keyword that is gone")
    func limits() throws {
        #expect(throws: SwiftalkError.self) { try eval("let Names = [String]\nlet xs: Names = []") }
        #expect(throws: SwiftalkError.self) { try eval("let n = 3\nlet x: n = 1") }
        #expect(throws: SwiftalkError.self) { try eval("typealias N = Int") }
        #expect(try eval("let typealias = 1\ntypealias") == .int(1))                 // just an identifier again
    }
}
