import Testing
@testable import Swiftalk

@Suite("Set(seq) and Set(array) keep or infer the stamp (round 172)")
struct SetStampTests {
    @Test("a Set built from elements is stamped by what they infer, or — empty — by what the source is known to yield")
    func built() throws {
        #expect(try eval("Set([Int]()).Type.String()") == .string("Set<Int>"))
        #expect(try eval("[Int]().Set().Type.String()") == .string("Set<Int>"))
        #expect(try eval("Set([1, 2]).Type.String()") == .string("Set<Int>"))
        #expect(try eval("Set((1...3).filter { false }).Type.String()") == .string("Set<Int>"))
        #expect(try eval("Set((1...).prefix(0)).Type.String()") == .string("Set<Int>"))
        #expect(try eval("Set(\"\").Type.String()") == .string("Set<String>"))
        #expect(try eval("Set([Set<Int>]()).Type.String()") == .string("Set<Set<Int>>"))
        #expect(try eval("Set(1, 2).Type.String()") == .string("Set<Int>"))
        #expect(try eval("Set(\"one\").Type.String()") == .string("Set<String>"))     // one String: its graphemes
        #expect(try eval("Set(3).Type.String()") == .string("Set<Int>"))             // one Int: the one-element Set
        #expect(throws: SwiftalkError.self) { try eval("var s = Set([Int]())\ns.insert(\"x\")") }
        #expect(try eval("var s = Set([Int]())\ns.insert(1)\ns") == .set([.int(1)]))
        #expect(try eval("Set([1, 2]).filter { false }.Type.String()") == .string("Set<Int>"))
    }

    @Test("what stays erased: mixed elements, an empty result of an unknowable source, a mixed Set(a, b)")
    func erased() throws {
        #expect(try eval("Set([1, \"a\"]).Type.String()") == .string("Set"))
        #expect(try eval("Set([1, \"a\"]).count") == .int(2))
        #expect(try eval("Set([].map { $0 }).Type.String()") == .string("Set"))
        #expect(try eval("Set((1...3).filter { false }.map { $0 }).Type.String()") == .string("Set"))
        #expect(try eval("Set(1, \"a\").Type.String()") == .string("Set"))
    }
}
