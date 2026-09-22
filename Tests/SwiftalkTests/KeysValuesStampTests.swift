import Testing
@testable import Swiftalk

@Suite("keys and values keep the stamp (round 180)")
struct KeysValuesStampTests {
    @Test("a [K: V]'s keys are a Set<K> and its values a [V], even when empty; an unstamped Dictionary's infer")
    func stamped() throws {
        #expect(try eval("[Int: String]().keys.Type.String()") == .string("Set<Int>"))
        #expect(try eval("[Int: String]().values.Type.String()") == .string("[String]"))
        #expect(try eval("[Int: [Int]]().values.Type.String()") == .string("[[Int]]"))
        #expect(try eval("[1: \"a\"].keys.Type.String()") == .string("Set<Int>"))
        #expect(try eval("[1: \"a\"].values.Type.String()") == .string("[String]"))
        #expect(try eval("[1: \"a\"].values.filter { false }.Type.String()") == .string("[String]"))   // the stamp survives
        #expect(try eval("var d: [String: Int] = [:]\nd.keys.Type.String()") == .string("Set<String>"))
        #expect(try eval("Dictionary(zip([1, 2], [\"a\", \"b\"])).values.sorted()") == .array([.string("a"), .string("b")]))
        #expect(throws: SwiftalkError.self) { try eval("var v = [Int: String]().values\nv.append(1)") }
        #expect(throws: SwiftalkError.self) { try eval("var k = [Int: String]().keys\nk.insert(\"x\")") }
        #expect(try eval("var k = [Int: String]().keys\nk.insert(1)\nk") == .set([.int(1)]))
        #expect(try eval("[:].keys.Type.String()") == .string("Set"))                     // nothing known, nothing to infer
        #expect(try eval("[:].values.Type.String()") == .string("Array"))
        #expect(try eval("[1: nil].values.Type.String()") == .string("[Any?]"))            // nil values shape nothing (round 101)
    }
}
