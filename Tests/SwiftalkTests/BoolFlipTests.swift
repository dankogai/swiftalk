import Testing
@testable import Swiftalk

@Suite("b.flip() on a Bool (round 276)")
struct BoolFlipTests {
    @Test("flip negates in place: b = !b, through a path too; the call is nil")
    func flips() throws {
        #expect(try eval("var b = true\nb.flip()\nb") == .bool(false))
        #expect(try eval("var b = false\nb.flip()\nb") == .bool(true))
        #expect(try eval("var b = false\nb.flip()\nb.flip()\nb") == .bool(false))
        #expect(try eval("var b = true\nb.flip()") == .nil)
        #expect(try eval("var a = [true, false]\na[1].flip()\na") == .array([.bool(true), .bool(true)]))
        #expect(try eval("var d = [\"on\": false]\nd[\"on\"].flip()\nd[\"on\"]") == .bool(true))
        #expect(try eval("struct S { var on = false }\nvar s = S()\ns.on.flip()\ns.on") == .bool(true))
        #expect(try eval("var b: Bool? = nil\nb = true\nb.flip()\nb") == .bool(false))
        #expect(try eval("var n = 0\nvar b = false\nwhile n < 3 { b.flip(); n += 1 }\nb") == .bool(true))
    }

    @Test("flip needs a var Bool and no arguments; other types have no flip")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("let b = true\nb.flip()") }
        #expect(throws: SwiftalkError.self) { try eval("true.flip()") }
        #expect(throws: SwiftalkError.self) { try eval("var b = true\nb.flip(false)") }
        #expect(throws: SwiftalkError.self) { try eval("var n = 1\nn.flip()") }
        #expect(throws: SwiftalkError.self) { try eval("var s = \"s\"\ns.flip()") }
        #expect(throws: SwiftalkError.self) { try eval("var b = true\nb.flip") }
        #expect(try eval("var n = 1\nlet r = eval(\"n.flip()\")\nr.failure.String().contains(\"Int.flip()\")") == .bool(true))
        #expect(try eval("let r = eval(\"true.flip()\")\nr.failure.String().contains(\"var Bool\")") == .bool(true))
    }
}
