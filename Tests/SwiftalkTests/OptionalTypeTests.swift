import Testing
@testable import Swiftalk

@Suite("Optional<T>, T?, and Set<T> as expressions (round 167)")
struct OptionalTypeTests {
    @Test("Int? and Optional<Int> are one type value; it is its own type, prints as Int?, and constructs through Int with nil allowed")
    func optionalType() throws {
        #expect(try eval("(Int?).String()") == .string("Int?"))              // Int?.String() would chain: ?. is optional chaining
        #expect(try eval("Optional<Int>.String()") == .string("Int?"))
        #expect(try eval("Optional<Int> == Int?") == .bool(true))
        #expect(try eval("Int? == Int") == .bool(false))
        #expect(try eval("Int? == String?") == .bool(false))
        #expect(try eval("((Int?)?).String()") == .string("Int?"))            // flat: an optional of an optional is itself
        #expect(try eval("Int?(\"42\")") == .int(42))
        #expect(try eval("Int?(\"x\")") == .nil)
        #expect(try eval("([Int]?).String()") == .string("[Int]?"))
        #expect(try eval("(Set<Int>?).String()") == .string("Set<Int>?"))
        #expect(try eval("Optional(3)") == .int(3))                        // the bare name: identity, the flat union
        #expect(try eval("Optional()") == .nil)
        #expect(throws: SwiftalkError.self) { try eval("Optional<Int, String>") }
        #expect(throws: SwiftalkError.self) { try eval("let z: Optional = 1") }
        #expect(try eval("let f = { let v = 3?; return v + 1 }\nf()") == .int(4))   // a value's ? still propagates, not types
    }

    @Test("[Int?] gets its spelling: Element is Int?, the binding admits nil and refuses a String")
    func optionalElement() throws {
        #expect(try eval("[Int?].String()") == .string("[Int?]"))
        #expect(try eval("[nil, 1].Type == [Int?]") == .bool(true))
        #expect(try eval("[nil, 1].Type.Element == Int?") == .bool(true))
        #expect(try eval("[Int?].Element.String()") == .string("Int?"))
        #expect(try eval("var a = [Int?]()\na.append(nil)\na.append(1)\na") == .array([.nil, .int(1)]))
        #expect(throws: SwiftalkError.self) { try eval("var a = [Int?]()\na.append(\"s\")") }
        #expect(throws: SwiftalkError.self) { try eval("let e: [Int] = [Int?]()") }
        #expect(try eval("let e: [Int?] = [Int]()\ne.Type.String()") == .string("[Int?]"))
    }

    @Test("Set<Int>, Dictionary<K, V>: the generic spelling as an expression; a < b > c stays two comparisons")
    func generic() throws {
        #expect(try eval("Set<Int>.String()") == .string("Set<Int>"))
        #expect(try eval("Set<Int> == Set([1]).Type") == .bool(true))
        #expect(try eval("Set<Int> == Set") == .bool(true))
        #expect(try eval("Set<Int> == Set<String>") == .bool(false))
        #expect(try eval("Set<Int>.Element == Int") == .bool(true))
        #expect(try eval("var s = Set<Int>()\ns.insert(2)\ns") == .set([.int(2)]))
        #expect(throws: SwiftalkError.self) { try eval("var s = Set<Int>()\ns.insert(\"x\")") }
        #expect(try eval("Set<Int>(1, 2).count") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("Set<Int>(\"abc\")") }
        #expect(try eval("Set<Set<Int>>.String()") == .string("Set<Set<Int>>"))
        #expect(try eval("Dictionary<Int, String> == [Int: String]") == .bool(true))
        #expect(try eval("[Set<Int>]().Type.String()") == .string("[Set<Int>]"))
        #expect(try eval("let S = Set<Int>\nS(3).Type.String()") == .string("Set<Int>"))
        #expect(try eval("let a = 1\nlet b = 2\na < b") == .bool(true))
        #expect(try eval("let a = 1\nlet b = 2\na<b") == .bool(true))
        #expect(try eval("let a = 1\nlet b = 2\nlet c = a >\n b\nc") == .bool(false))    // a spaced > still continues the line
        #expect(try eval("Set<Int>\n1") == .int(1))                                        // an unspaced closing > does not
        #expect(try eval("3 > 2 ? \"yes\" : \"no\"") == .string("yes"))
    }

    @Test("a user type's T?: the same type, optional — constructs as it does, and annotates")
    func userOptional() throws {
        let p = "struct P { var x: Int = 0 }\n"
        #expect(try eval(p + "(P?).String()") == .string("P?"))
        #expect(try eval(p + "P? == P?") == .bool(true))
        #expect(try eval(p + "P? == P") == .bool(false))
        #expect(try eval(p + "let OP = P?\nOP(x: 2).x") == .int(2))
        #expect(try eval(p + "let OP = P?\nvar v: OP = nil\nv = P(x: 1)\nv.x") == .int(1))
        #expect(throws: SwiftalkError.self) { try eval(p + "let OP = P?\nvar v: OP = nil\nv = 1") }
        #expect(try eval(p + "[P?].Element == P?") == .bool(true))
        #expect(try eval("let OI = Int?\nvar v: OI = nil\nv = 3\nv") == .int(3))
        #expect(try eval("let x: Optional<Int> = nil\nx") == .nil)
    }
}
