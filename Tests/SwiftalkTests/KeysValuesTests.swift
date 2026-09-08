import Testing
@testable import Swiftalk

@Suite("d.keys and d.values — Swift's properties, as Arrays (round 127)")
struct KeysValuesTests {
    @Test("Arrays in the Dictionary's own order, aligned with each other and with iteration")
    func views() throws {
        #expect(try eval("[\"a\": 1, \"b\": 2].keys.sorted()") == .array([.string("a"), .string("b")]))
        #expect(try eval("[\"a\": 1, \"b\": 2].values.sorted()") == .array([.int(1), .int(2)]))
        #expect(try eval("[:].keys") == .array([]))
        #expect(try eval("[:].values.count") == .int(0))
        #expect(try eval("[\"k\": nil].values") == .array([.nil]))                       // a stored nil is a value
        #expect(try eval("[1: \"x\", 2.5: \"y\"].keys.count") == .int(2))               // any key type
        let d = "let d = [\"a\": 1, \"b\": 2, \"c\": 3]\n"
        #expect(try eval(d + "d.keys.count == d.count && d.values.count == d.count") == .bool(true))
        #expect(try eval(d + "d.keys.enumerated().map { i, k in d[k] == d.values[i] }.contains(false)") == .bool(false))
        #expect(try eval(d + "var ks = []\nfor k, v in d { ks.append(k) }\nks == d.keys") == .bool(true))
        #expect(try eval(d + "d.keys.contains(\"b\")") == .bool(true))
        #expect(try eval(d + "d.values.reduce(0) { $0 + $1 }") == .int(6))
        #expect(try eval(d + "d.keys.Type == Array") == .bool(true))
        #expect(try eval(d + "let ks: [String] = d.keys\nks.count") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval(d + "let ns: [Int] = d.keys") }
    }

    @Test("a property, as in Swift: the called form and other receivers are errors")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1].keys()") }
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1].values()") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].keys") }
        #expect(throws: SwiftalkError.self) { try eval("\"s\".values") }
    }
}
