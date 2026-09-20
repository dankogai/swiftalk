import Testing
@testable import Swiftalk

@Suite("parameterized container types (round 165): [Int], [K: V], Set<T> are values, and a container remembers its element type")
struct ParameterizedTypeTests {
    @Test(".Type of a container carries its element type; a mixed or empty literal is the erased type; Function stays Function")
    func typeOf() throws {
        #expect(try eval("[0].Type.String()") == .string("[Int]"))
        #expect(try eval("[1: \"a\"].Type.String()") == .string("[Int: String]"))
        #expect(try eval("Set([1]).Type.String()") == .string("Set<Int>"))
        #expect(try eval("[[1, 2], [3]].Type.String()") == .string("[[Int]]"))
        #expect(try eval("[1, \"one\"].Type.String()") == .string("Array"))
        #expect(try eval("[].Type.String()") == .string("Array"))
        #expect(try eval("[nil, 1].Type.String()") == .string("[Int?]"))
        #expect(try eval("[0].Type.name") == .string("Array"))
        #expect(try eval("{ $0 }.Type.String()") == .string("Function"))
        #expect(try eval("[Int].Type == Function") == .bool(true))
    }

    @Test("type values: [Int] and [K: V] spell the types; equality by name, the erased name admitting any parameters")
    func typeValues() throws {
        #expect(try eval("[0].Type == [Int]") == .bool(true))
        #expect(try eval("[0].Type == Array") == .bool(true))
        #expect(try eval("[0].Type == [String]") == .bool(false))
        #expect(try eval("[Int] == [String]") == .bool(false))
        #expect(try eval("[Int] == Array") == .bool(true))
        #expect(try eval("[Int: String] == [1: \"a\"].Type") == .bool(true))
        #expect(try eval("[[Int]: String].String()") == .string("[[Int]: String]"))
        #expect(try eval("[Int, String].count") == .int(2))          // two types: an Array of them, not a type
        #expect(try eval("[Int].String()") == .string("[Int]"))
        #expect(try eval("Set([[Int], [Int]]).count") == .int(1))   // equal, so one — and hashable
    }

    @Test("calling a parameterized type builds a container that remembers: T() is empty but typed, and the binding enforces it")
    func construction() throws {
        #expect(throws: SwiftalkError.self) { try eval("var a = [0]\nvar T = a.Type\nvar a1 = T()\na1.append(\"one\")") }
        #expect(try eval("var a = [0]\nvar T = a.Type\nvar a1 = T()\na1.append(1)\na1") == .array([.int(1)]))
        #expect(try eval("var a1 = [Int]()\na1.Type.String()") == .string("[Int]"))
        #expect(throws: SwiftalkError.self) { try eval("var d = [Int: String]()\nd[1] = 1") }
        #expect(throws: SwiftalkError.self) { try eval("var d = [Int: String]()\nd[\"x\"] = \"a\"") }
        #expect(try eval("var d = [Int: String]()\nd[1] = \"one\"\nd") == .dictionary([.int(1): .string("one")]))
        #expect(throws: SwiftalkError.self) { try eval("var m = [[Int]]()\nm.append([\"x\"])") }
        #expect(throws: SwiftalkError.self) { try eval("var m = [[Int]]()\nm.append([1])\nm[0].append(\"y\")") }
        #expect(try eval("[Int](1...3)") == .array([.int(1), .int(2), .int(3)]))
        #expect(throws: SwiftalkError.self) { try eval("[Int]([1, \"a\"])") }
        #expect(try eval("let S = Set([1]).Type\nvar s = S()\ns.insert(2)\ns.count") == .int(1))
        #expect(throws: SwiftalkError.self) { try eval("let S = Set([1]).Type\nvar s = S()\ns.insert(\"x\")") }
    }

    @Test("the stamp travels through bindings, struct properties, and annotations; a lock refuses a differently stamped empty")
    func stamps() throws {
        #expect(try eval("var a: [Int] = []\nlet b = a\nb.Type.String()") == .string("[Int]"))
        #expect(throws: SwiftalkError.self) { try eval("var a: [Int] = []\nvar b = a\nb.append(\"s\")") }
        #expect(try eval("struct S { var xs: [Int] = [] }\nS().xs.Type.String()") == .string("[Int]"))
        #expect(throws: SwiftalkError.self) { try eval("struct S { var xs: [Int] = [] }\nvar s = S()\ns.xs.append(\"z\")") }
        #expect(throws: SwiftalkError.self) { try eval("let e: [Int] = [String]()") }
        #expect(try eval("let f: Any = [String]()\nf") == .array([]))
        #expect(try eval("let g: [Any] = [String]()\ng.Type.String()") == .string("[Any]"))     // the lock's word wins
        #expect(try eval("let h: Array = [String]()\nh.Type.String()") == .string("[String]"))  // an erased lock keeps the stamp
        #expect(try eval("[Int]() == [String]()") == .bool(true))                    // equality ignores the stamp
        #expect(try eval("[Int]().map { $0 }.Type.String()") == .string("Array"))    // a derived empty is erased
    }

    @Test("a binding holding [String] is an alias for annotations — lifting round 111's one limit")
    func alias() throws {
        #expect(try eval("let Names = [String]\nvar xs: Names = []\nxs.append(\"a\")\nxs.Type.String()") == .string("[String]"))
        #expect(throws: SwiftalkError.self) { try eval("let Names = [String]\nvar xs: Names = []\nxs.append(1)") }
        #expect(try eval("let Names = [String]\nlet xs: Names? = nil\nxs") == .nil)
        #expect(try eval("let Names = [String]\nstruct P { var names: Names = [] }\nP().names.Type.String()") == .string("[String]"))
    }
}
