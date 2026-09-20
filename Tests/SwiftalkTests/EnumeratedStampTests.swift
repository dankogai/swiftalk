import Testing
@testable import Swiftalk

@Suite("enumerated() keeps the stamp (round 175)")
struct EnumeratedStampTests {
    @Test("an Array's enumeration is [Tuple] even when empty; a Dictionary's is itself, stamp and all; a lazy one's Array() knows too")
    func stamped() throws {
        #expect(try eval("[1, 2].enumerated().Type.String()") == .string("[Tuple]"))
        #expect(try eval("[Int]().enumerated().Type.String()") == .string("[Tuple]"))
        #expect(try eval("Set<Int>().enumerated().Type.String()") == .string("[Tuple]"))
        #expect(try eval("\"\".enumerated().Type.String()") == .string("[Tuple]"))
        #expect(throws: SwiftalkError.self) { try eval("var e = [Int]().enumerated()\ne.append(1)") }
        #expect(try eval("var e = [Int]().enumerated()\ne.append((key: 0, value: 1))\ne.count") == .int(1))
        #expect(try eval("[Int: String]().enumerated().Type.String()") == .string("[Int: String]"))
        #expect(try eval("(1...).enumerated().prefix(0).Array().Type.String()") == .string("[Tuple]"))
        #expect(try eval("[1, 2].enumerated().map { i, x in i * x }") == .array([.int(0), .int(2)]))
        #expect(try eval("Dictionary([\"a\", \"b\"].enumerated()).Type.String()") == .string("[Int: String]"))
    }
}
