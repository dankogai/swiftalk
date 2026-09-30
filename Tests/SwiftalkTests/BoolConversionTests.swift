import Testing
@testable import Swiftalk

// Round 204: `Bool(x)` takes a Bool or the two Strings, nothing else —
// `Bool(i)` as `i != 0` (round 105) is gone: `i != 0` is what it meant.

@Suite("Bool(): a Bool, \"true\", \"false\" — and nothing else (round 204)")
struct BoolConversionTests {
    @Test("what converts")
    func converts() throws {
        #expect(try eval("Bool()") == .bool(false))
        #expect(try eval("Bool(true)") == .bool(true))
        #expect(try eval("Bool(false)") == .bool(false))
        #expect(try eval("Bool(\"true\")") == .bool(true))
        #expect(try eval("Bool(\"false\")") == .bool(false))
        #expect(try eval("\"true\".Bool()") == .bool(true))
        #expect(try eval("Bool(\"yes\")") == .nil)                   // failable, as ever
        #expect(try eval("Bool(\"True\")") == .nil)
    }

    @Test("what does not: an Int names the idiom, the rest the type")
    func refuses() throws {
        #expect(throws: SwiftalkError.self) { try eval("Bool(1)") }
        #expect(throws: SwiftalkError.self) { try eval("Bool(0)") }
        #expect(throws: SwiftalkError.self) { try eval("0.Bool()") }
        #expect(throws: SwiftalkError.self) { try eval("Bool(1.0)") }
        #expect(throws: SwiftalkError.self) { try eval("Bool(nil)") }
        #expect(throws: SwiftalkError.self) { try eval("Bool([true])") }
        #expect(throws: SwiftalkError.self) { try eval("Bool(Byte(1))") }
        #expect(try eval("eval(\"Bool(1)\") == .failure(\"type error: cannot convert Int to Bool — write i != 0\")") == .bool(true))
        #expect(try eval("let i = 3\ni != 0") == .bool(true))
    }
}
