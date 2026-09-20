import Testing
@testable import Swiftalk

@Suite("reversed() and sorted() keep the stamp (round 176)")
struct ReorderStampTests {
    @Test("an Array of the receiver's element type, even when empty — from an Array, a Set, a Range, a String, a Dictionary")
    func stamped() throws {
        #expect(try eval("[Int]().reversed().Type.String()") == .string("[Int]"))
        #expect(try eval("[Int]().sorted().Type.String()") == .string("[Int]"))
        #expect(try eval("[Int]().sorted { $0 < $1 }.Type.String()") == .string("[Int]"))
        #expect(try eval("[3, 1, 2].sorted()") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval("[3, 1, 2].sorted().Type.String()") == .string("[Int]"))
        #expect(try eval("Set<Int>().sorted().Type.String()") == .string("[Int]"))
        #expect(try eval("Set<Int>().reversed().Type.String()") == .string("[Int]"))
        #expect(try eval("(1...3).filter { false }.reversed().Type.String()") == .string("[Int]"))
        #expect(try eval("\"\".reversed().Type.String()") == .string("[String]"))
        #expect(try eval("\"\".sorted().Type.String()") == .string("[String]"))
        #expect(try eval("[Int: String]().sorted { $0.key < $1.key }.Type.String()") == .string("[Tuple]"))
        #expect(try eval("[Int: String]().reversed().Type.String()") == .string("[Tuple]"))
        #expect(try eval("[[Int]]().reversed().Type.String()") == .string("[[Int]]"))
        #expect(throws: SwiftalkError.self) { try eval("var r = [Int]().reversed()\nr.append(\"s\")") }
        #expect(throws: SwiftalkError.self) { try eval("var r = Set<Int>().sorted()\nr.append(\"s\")") }
        #expect(try eval("var r = [Int]().sorted()\nr.append(1)\nr") == .array([.int(1)]))
    }

    @Test("what stays erased: nothing to infer and nothing known — an empty map's, a mixed Array's")
    func erased() throws {
        #expect(try eval("[].reversed().Type.String()") == .string("Array"))
        #expect(try eval("[Int]().map { $0 }.reversed().Type.String()") == .string("Array"))
        #expect(try eval("[1, \"a\"].reversed().Type.String()") == .string("Array"))
        #expect(try eval("[1, \"a\"].reversed()") == .array([.string("a"), .int(1)]))
    }
}
