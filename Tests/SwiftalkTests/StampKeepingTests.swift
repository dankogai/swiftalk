import Testing
@testable import Swiftalk

@Suite("filter and the slicing family keep the stamp (rounds 168–169)")
struct StampKeepingTests {
    @Test("an Array, Set, or Dictionary filtered or dropped from a stamped one is stamped the same, even when empty")
    func kept() throws {
        #expect(try eval("var a = [Int]()\nlet b = a.filter { $0 > 0 }\nb.Type.String()") == .string("[Int]"))
        #expect(throws: SwiftalkError.self) { try eval("var a = [Int]()\nvar b = a.filter { $0 > 0 }\nb.append(\"s\")") }
        #expect(try eval("var a = [1]\nlet b = a.dropFirst()\nb.Type.String()") == .string("[Int]"))
        #expect(throws: SwiftalkError.self) { try eval("var a = [1]\nvar b = a.dropFirst()\nb.append(\"s\")") }
        #expect(try eval("var a = [1, 2]\nlet b = a.dropFirst { $0 < 3 }\nb.Type.String()") == .string("[Int]"))
        #expect(try eval("var s = Set<Int>()\nlet t = s.filter { $0 > 0 }\nt.Type.String()") == .string("Set<Int>"))
        #expect(throws: SwiftalkError.self) { try eval("var s = Set<Int>()\nvar t = s.filter { $0 > 0 }\nt.insert(\"x\")") }
        #expect(try eval("var d = [Int: String]()\nlet e = d.filter { k, v in k > 0 }\ne.Type.String()") == .string("[Int: String]"))
        #expect(throws: SwiftalkError.self) { try eval("var d = [Int: String]()\nvar e = d.filter { k, v in k > 0 }\ne[\"x\"] = \"y\"") }
        #expect(try eval("var d = [1: \"a\"]\nlet e = d.dropFirst()\ne.Type.String()") == .string("[Int: String]"))
        // dropLast, suffix, prefix (round 169)
        #expect(try eval("var a = [Int]()\na.dropLast().Type.String()") == .string("[Int]"))
        #expect(try eval("var a = [Int]()\na.suffix(1).Type.String()") == .string("[Int]"))
        #expect(try eval("var a = [Int]()\na.prefix(1).Type.String()") == .string("[Int]"))
        #expect(try eval("var a = [1, 2]\na.prefix { $0 < 2 }.Type.String()") == .string("[Int]"))
        #expect(throws: SwiftalkError.self) { try eval("var a = [1]\nvar b = a.prefix(0)\nb.append(\"s\")") }
        #expect(try eval("var s = Set<Int>()\ns.prefix(1).Type.String()") == .string("Set<Int>"))    // a Set's slice is a Set, and keeps it
        #expect(try eval("var d = [Int: String]()\nd.suffix(1).Type.String()") == .string("[Int: String]"))
        // the elements travel with the stamp
        #expect(try eval("var a = [1, 2, 3]\na.dropFirst(2)") == .array([.int(3)]))
        #expect(try eval("var a = [1, 2, 3]\na.filter { $0 != 2 }") == .array([.int(1), .int(3)]))
    }

    @Test("what does not carry a stamp: map (a new element type), an unstamped receiver, a lazy Sequence")
    func notKept() throws {
        #expect(try eval("var a = [Int]()\na.map { $0 }.Type.String()") == .string("Array"))
        #expect(try eval("[].filter { $0 > 0 }.Type.String()") == .string("Array"))
        #expect(try eval("(1...).filter { $0 > 0 }.Type.String()") == .string("Sequence"))
        #expect(try eval("\"abc\".filter { $0 != \"b\" }") == .string("ac"))
    }
}
