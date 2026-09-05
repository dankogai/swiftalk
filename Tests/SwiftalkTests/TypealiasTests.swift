import Testing
@testable import Swiftalk

@Suite("typealias — a name for any annotation (round 110)")
struct TypealiasTests {
    @Test("an alias works wherever an annotation goes; an alias to a plain type is the type's value too")
    func aliases() throws {
        #expect(try eval("typealias Number = Int\nlet n: Number = 42\nn") == .int(42))
        #expect(try eval("typealias Number = Int\nNumber(\"7\")") == .int(7))
        #expect(try eval("typealias Number = Int\n3.Type == Number") == .bool(true))
        #expect(try eval("typealias Number = Int\nNumber == Int") == .bool(true))
        #expect(try eval("typealias Names = [String]\nvar xs: Names = [\"a\"]\nxs.append(\"b\")\nxs.count") == .int(2))
        #expect(try eval("typealias Number = Int\ntypealias MaybeInt = Number?\nvar m: MaybeInt = nil\nm = 3\nm") == .int(3))
        #expect(try eval("typealias Names = [String]\ntypealias Table = [String: Names]\nlet t: Table = [\"k\": [\"x\"]]\nt[\"k\"]") == .array([.string("x")]))
        #expect(try eval("typealias Names = [String]\nlet nested: [Names] = [[\"p\"]]\nnested[0][0]") == .string("p"))
        #expect(try eval("typealias Doc = SION\nlet d: Doc = SION(\"[nil: 1, \\\"a\\\": 2]\")\nd.count") == .int(2))
        #expect(try eval("enum Shape { case circle(r: Double); case point }\ntypealias S = Shape\nlet s: S = .circle(r: 1.0)\n[s.circle, S.point == Shape.point]") == .array([.double(1), .bool(true)]))
        #expect(try eval("typealias Radius = Double\nstruct C { var r: Radius }\nC(r: 2.0).r") == .double(2))
        #expect(try eval("typealias Number = Int\nenum Box { case some(Number) }\nBox.some(3).some") == .int(3))
        // scoped like a binding
        #expect(try eval("let f = { typealias T = Int; let x: T = 1; return x }\nf()") == .int(1))
    }

    @Test("the lock is the resolved type; errors: unknown, redeclared, parameters, an optional payload alias")
    func rules() throws {
        #expect(throws: SwiftalkError.self) { try eval("typealias Names = [String]\nvar xs: Names = [\"a\"]\nxs.append(1)") }
        #expect(throws: SwiftalkError.self) { try eval("typealias N = Int\nstruct P { var v: N }\nP(v: \"s\")") }
        #expect(throws: SwiftalkError.self) { try eval("typealias Bad = Nope") }
        #expect(throws: SwiftalkError.self) { try eval("typealias N = Int\ntypealias N = Double") }
        #expect(throws: SwiftalkError.self) { try eval("typealias N = Int\nlet N = 1") }
        #expect(throws: SwiftalkError.self) { try eval("let N = 1\ntypealias N = Int") }
        #expect(throws: SwiftalkError.self) { try eval("typealias M = Int?\nenum E { case c(M) }") }
        #expect(throws: SwiftalkError.self) { try eval("typealias X = 3") }
        #expect(throws: SwiftalkError.self) { try eval("typealias Names = [String]\nNames(1)") }   // annotation-only: no value
    }
}
