import Testing
@testable import Swiftalk

@Suite("Dictionary merging / merge (round 126)")
struct MergeTests {
    @Test("merging: a new Dictionary; the combine function gets (current, new); without one, new wins")
    func merging() throws {
        #expect(try eval("[\"a\": 1].merging([\"b\": 2])") == .dictionary([.string("a"): .int(1), .string("b"): .int(2)]))
        #expect(try eval("[\"a\": 1, \"b\": 2].merging([\"b\": 3]) { v0, v1 in v0 + v1 }[\"b\"]") == .int(5))
        #expect(try eval("[\"a\": 1].merging([\"a\": 10]) { $0 * $1 }[\"a\"]") == .int(10))
        #expect(try eval("[\"a\": 1].merging([\"a\": 10]) { current, new in current }[\"a\"]") == .int(1))
        #expect(try eval("[\"a\": 1].merging([\"a\": 10], uniquingKeysWith: { a, b in a })[\"a\"]") == .int(1))
        #expect(try eval("[\"a\": 1].merging([\"a\": 2])[\"a\"]") == .int(2))                   // new wins by default
        #expect(try eval("let d = [\"a\": 1]\nlet e = d.merging([\"b\": 2])\n[d.count, e.count]") == .array([.int(1), .int(2)]))
        #expect(try eval("[\"a\": nil].merging([\"a\": 1]) { a, b in a ?? b }[\"a\"]") == .int(1))
        #expect(try eval("[:].merging([:]).count") == .int(0))
        #expect(try eval("[1: \"x\"].merging([2: \"y\"]).count") == .int(2))
        #expect(try eval("let f = { a, b in a + b }\n[\"k\": 1].merging([\"k\": 2], uniquingKeysWith: f)[\"k\"]") == .int(3))
    }

    @Test("merge: in place, on a var; returns nil; the lock still holds")
    func merge() throws {
        #expect(try eval("var d = [\"a\": 1]\nd.merge([\"a\": 5, \"b\": 2]) { $0 + $1 }\nd")
                == .dictionary([.string("a"): .int(6), .string("b"): .int(2)]))
        #expect(try eval("var d = [\"a\": 1]\nd.merge([\"c\": 3])\nd.count") == .int(2))
        #expect(try eval("var d = [\"a\": 1]\nd.merge([\"a\": 3])\nd[\"a\"]") == .int(3))
        #expect(try eval("var d = [\"a\": 1]\nd.merge([\"a\": 3], uniquingKeysWith: { a, b in a })\nd[\"a\"]") == .int(1))
        #expect(try eval("var d = [\"a\": 1]\nd.merge([\"b\": 2]) == nil") == .bool(true))
        #expect(try eval("var s = (d: [\"a\": 1], n: 0)\ns.d.merge([\"b\": 2])\ns.d.count") == .int(2))     // through a path
        #expect(throws: SwiftalkError.self) { try eval("let d = [\"a\": 1]\nd.merge([\"b\": 2])") }
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1].merge([\"b\": 2])") }
        #expect(throws: SwiftalkError.self) { try eval("var d: [String: Int] = [\"a\": 1]\nd.merge([\"b\": \"x\"])") }
    }

    @Test("errors: not a Dictionary, not a function, too many arguments, a wrong label")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1].merging([1, 2])") }
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1].merging([\"b\": 2], 3)") }
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1].merging()") }
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1].merging([\"b\": 2], [\"c\": 3])") }
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1].merging(with: [\"b\": 2])") }
        #expect(throws: SwiftalkError.self) { try eval("[1].merging([2])") }
        #expect(throws: SwiftalkError.self) { try eval("var a = [1]\na.merge([2])") }
    }
}
