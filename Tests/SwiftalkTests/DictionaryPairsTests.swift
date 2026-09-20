import Testing
@testable import Swiftalk

@Suite("Dictionary(pairs) — from a Sequence of tuples, stamped by what they infer (round 173)")
struct DictionaryPairsTests {
    @Test("Array(d) round-trips, any (k, v) tuples build, and the stamp is [K: V]")
    func pairs() throws {
        #expect(try eval("Dictionary([(1, \"a\"), (2, \"b\")])") == .dictionary([.int(1): .string("a"), .int(2): .string("b")]))
        #expect(try eval("Dictionary([(1, \"a\")]).Type.String()") == .string("[Int: String]"))
        #expect(try eval("let d = [1: \"a\", 2: \"b\"]\nDictionary(Array(d)) == d") == .bool(true))
        #expect(try eval("Dictionary(Array([1: \"a\"])).Type.String()") == .string("[Int: String]"))
        #expect(try eval("[(1, \"a\")].Dictionary().Type.String()") == .string("[Int: String]"))      // the conversion law's spelling
        #expect(try eval("Dictionary([1: \"a\"].map { k, v in (v, k) })") == .dictionary([.string("a"): .int(1)]))
        #expect(try eval("Dictionary((1...3).map { ($0, $0 * $0) })[3]") == .int(9))
        #expect(try eval("Dictionary([(k: 1, v: \"a\")]).Type.String()") == .string("[Int: String]"))  // labels are ignored
        #expect(try eval("Dictionary([(1, nil)]).Type.String()") == .string("[Int: Any?]"))            // nil values shape nothing (round 101)
        #expect(throws: SwiftalkError.self) { try eval("var d = Dictionary([(1, \"a\")])\nd[\"x\"] = \"b\"") }
        #expect(throws: SwiftalkError.self) { try eval("var d = Dictionary([(1, \"a\")])\nd[2] = 2") }
        #expect(try eval("var d = Dictionary([(1, \"a\")])\nd[2] = \"b\"\nd.count") == .int(2))
    }

    @Test("what it refuses, and what stays erased")
    func edges() throws {
        #expect(throws: SwiftalkError.self) { try eval("Dictionary([(1, \"a\"), (1, \"b\")])") }   // duplicate key
        #expect(throws: SwiftalkError.self) { try eval("Dictionary([1, 2])") }                      // not pairs
        #expect(throws: SwiftalkError.self) { try eval("Dictionary([(1, 2, 3)])") }                 // not 2-tuples
        #expect(throws: SwiftalkError.self) { try eval("Dictionary(3)") }
        #expect(try eval("Dictionary([]).Type.String()") == .string("Dictionary"))                   // nothing to infer
        #expect(try eval("Dictionary([(1, \"a\"), (\"b\", 2)]).Type.String()") == .string("Dictionary"))   // mixed: erased, still built
        #expect(try eval("Dictionary([(1, \"a\"), (\"b\", 2)]).count") == .int(2))
    }
}
