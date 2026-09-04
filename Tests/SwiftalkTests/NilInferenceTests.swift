import Testing
@testable import Swiftalk

@Suite("nil infers Any: a strict let/var binds from nil (round 101)")
struct NilInferenceTests {
    @Test("let v = nil / a failed conversion binds; var x = nil takes anything later")
    func scalar() throws {
        #expect(try eval("let v = nil\nv") == .nil)
        #expect(try eval("let v = Int(\"x\")\nv == nil") == .bool(true))
        #expect(try eval("var x = nil\nx = 1\nx = \"s\"\nx") == .string("s"))
        #expect(try eval("var x = nil\nx = [1]\nx.count") == .int(1))
        #expect(try eval("let (p, q) = (nil, 2)\nq") == .int(2))
        #expect(try eval("let (p, q) = (nil, 2)\np") == .nil)
        // an annotation still narrows
        #expect(throws: SwiftalkError.self) { try eval("var x: Int? = nil\nx = \"s\"") }
        #expect(try eval("var x: Int? = nil\nx = 3\nx") == .int(3))
    }

    @Test("in containers: a nil beside typed elements makes the lock optional; nothing but nil is Any")
    func containers() throws {
        #expect(try eval("var a = [1, nil]\na.append(nil)\na.append(2)\na") == .array([.int(1), .nil, .nil, .int(2)]))
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, nil]\na.append(\"s\")") }
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2]\na.append(nil)") }        // no nil seen: [Int]
        #expect(try eval("var n = [nil]\nn.append(1)\nn.append(\"s\")\nn.count") == .int(3))
        #expect(try eval("var d = [nil: 1, \"a\": 2]\nd[nil]") == .int(1))
        #expect(try eval("var e = [\"k\": nil]\ne[\"k\"] = 5\ne[\"k\"]") == .int(5))
        #expect(try eval("var e = [\"k\": nil]\ne[\"k\"] = \"s\"\ne[\"k\"]") == .string("s"))     // values: Any
        // mixed literals still want an annotation (round 59 stands)
        #expect(throws: SwiftalkError.self) { try eval("let m = [1, \"a\"]") }
        #expect(throws: SwiftalkError.self) { try eval("let m = [1: \"a\", \"b\": 2]") }
    }

    @Test("the REPL's implicit var from nil")
    func relaxed() throws {
        let i = Swiftalk.Interpreter(relaxed: true)
        #expect(try i.eval("y = nil\ny = 1\ny") == .int(1))
    }
}
