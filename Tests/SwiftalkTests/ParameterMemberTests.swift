import Testing
@testable import Swiftalk

@Suite(".Element, .Key, .Value on a parameterized type (round 166)")
struct ParameterMemberTests {
    @Test("the parameters come back as type values, nested types included, and construct when called")
    func parameters() throws {
        #expect(try eval("[0].Type.Element == Int") == .bool(true))
        #expect(try eval("[Int].Element.String()") == .string("Int"))
        #expect(try eval("[1: \"a\"].Type.Key == Int") == .bool(true))
        #expect(try eval("[Int: String].Value == String") == .bool(true))
        #expect(try eval("Set([1]).Type.Element == Int") == .bool(true))
        #expect(try eval("[[Int]].Element == [Int]") == .bool(true))
        #expect(try eval("[[1]].Type.Element.Element == Int") == .bool(true))
        #expect(try eval("[[Int]: String].Key.Element == Int") == .bool(true))
        #expect(try eval("[Int].Element(\"42\")") == .int(42))
        #expect(try eval("[Int].Element()") == .int(0))
        #expect(try eval("let T = [0].Type\nlet E = T.Element\nE(\"7\") + 1") == .int(8))
        #expect(try eval("var xs = [[Int]].Element()\nxs.Type.String()") == .string("[Int]"))
        #expect(throws: SwiftalkError.self) { try eval("var xs = [[Int]].Element()\nxs.append(\"s\")") }
    }

    @Test("user types come back as themselves; the erased type has none to give; an annotation-only parameter is an error")
    func edges() throws {
        let point = "struct P { var x: Int = 0 }\n"
        #expect(try eval(point + "[P()].Type.Element == P") == .bool(true))
        #expect(try eval(point + "let E = [P()].Type.Element\nE(x: 3).x") == .int(3))
        #expect(try eval("enum C { case a, b }\n[C.a].Type.Element == C") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("Array.Element") }
        #expect(throws: SwiftalkError.self) { try eval("Dictionary.Key") }
        #expect(throws: SwiftalkError.self) { try eval("[].Type.Element") }
        #expect(throws: SwiftalkError.self) { try eval("[Int].Key") }             // an Array has no Key
        #expect(throws: SwiftalkError.self) { try eval("[Int: String].Element") } // a Dictionary has no Element
        #expect(try eval("[nil, 1].Type.Element == Int?") == .bool(true))         // Int? is a value since round 167
        #expect(throws: SwiftalkError.self) { try eval("let a: [Any] = [1]\na.Type.Element") }
    }
}
