import Testing
@testable import Swiftalk

@Suite("Array(x) and x.Array() keep or infer the stamp (round 171)")
struct MaterializeStampTests {
    @Test("a Sequence materializes with the stamp its elements infer — or the one its source is known to yield; mixed, or unknowable and empty, erased")
    func sequences() throws {
        #expect(try eval("(1...3).Array().Type.String()") == .string("[Int]"))
        #expect(try eval("(1...3).map { \"\\($0)\" }.Array().Type.String()") == .string("[String]"))
        #expect(try eval("var a = (1...3).Array().filter { false }\na.Type.String()") == .string("[Int]"))
        #expect(throws: SwiftalkError.self) { try eval("var a = Array((1...3).filter { false })\na.append(\"s\")") }
        #expect(try eval("(1...).prefix(0).Array().Type.String()") == .string("[Int]"))         // a Range yields Ints, and prefix keeps that
        #expect(try eval("(1...3).dropFirst(9).Array().Type.String()") == .string("[Int]"))
        #expect(try eval("(1...3).filter { false }.Type.String()") == .string("[Int]"))         // eager on a bounded Range, stamped the same
        #expect(try eval("(1...3).filter { false }.map { $0 }.Array().Type.String()") == .string("Array"))   // map: unknowable
        #expect(try eval("Sequence { }.Array().Type.String()") == .string("Array"))                       // a coroutine: unknowable
        #expect(try eval("\"\".Array().Type.String()") == .string("[String]"))
        #expect(try eval("Data().Array().Type.String()") == .string("[Byte]"))
        #expect(try eval("Sequence { yield(1); yield(\"a\") }.Array().Type.String()") == .string("Array"))
        #expect(try eval("Sequence { yield(1); yield(\"a\") }.Array()") == .array([.int(1), .string("a")]))
    }

    @Test("the identity conversions keep what they were handed; a Set's Array carries its element type")
    func identity() throws {
        #expect(try eval("Array([Int]()).Type.String()") == .string("[Int]"))
        #expect(try eval("[Int]().Array().Type.String()") == .string("[Int]"))
        #expect(try eval("Set(Set<Int>()).Type.String()") == .string("Set<Int>"))
        #expect(try eval("Dictionary([Int: String]()).Type.String()") == .string("[Int: String]"))
        #expect(try eval("Set<Int>().Array().Type.String()") == .string("[Int]"))
        #expect(try eval("Array(Set<Set<Int>>()).Type.String()") == .string("[Set<Int>]"))
        #expect(throws: SwiftalkError.self) { try eval("var a = Set<Int>().Array()\na.append(\"s\")") }
        #expect(try eval("Array(Set(1, 2)).count") == .int(2))
        #expect(try eval("[Int]().Set().Type.String()") == .string("Set<Int>"))   // the mirror: round 172
    }
}
