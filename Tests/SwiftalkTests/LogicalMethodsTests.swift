import Testing
@testable import Swiftalk

@Suite("^^, and not/and/or/xor on Bools (round 106)")
struct LogicalMethodsTests {
    @Test("^^ is logical xor: Bools only, both sides evaluated, between && and ||")
    func xor() throws {
        #expect(try eval("true ^^ false") == .bool(true))
        #expect(try eval("true ^^ true") == .bool(false))
        #expect(try eval("false ^^ false") == .bool(false))
        #expect(try eval("true && false ^^ true || false") == .bool(true))
        #expect(try eval("true ^^ true || true") == .bool(true))
        #expect(try eval("false || true ^^ true") == .bool(false))
        #expect(try eval("var calls = 0\nlet f = { calls += 1; return true }\nlet r = true ^^ f()\n[r, calls]") == .array([.bool(false), .int(1)]))
        #expect(try eval("var b = true\nb ^^= true\nb") == .bool(false))
        #expect(try eval("var b = false\nb ^^= true\nb") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("true ^^ 1") }
        #expect(throws: SwiftalkError.self) { try eval("1 ^^ 2") }
        #expect(throws: SwiftalkError.self) { try eval("var n = 1\nn ^^= true") }
        #expect(throws: SwiftalkError.self) { try eval("1 ^ 2") }
    }

    @Test("not/and/or/xor: logical on a Bool; the bitwise names are bit-prefixed (round 107); the methods are eager")
    func methods() throws {
        #expect(try eval("true.not()") == .bool(false))
        #expect(try eval("true.and(false)") == .bool(false))
        #expect(try eval("false.or(true)") == .bool(true))
        #expect(try eval("true.xor(false)") == .bool(true))
        #expect(try eval("true.xor(true)") == .bool(false))
        #expect(try eval("5.bitXor(3)") == .int(6))
        #expect(try eval("5.bitNot()") == .int(-6))
        #expect(try eval("var calls = 0\nlet f = { calls += 1; return true }\nlet r = false.and(f())\n[r, calls]") == .array([.bool(false), .int(1)]))
        #expect(try eval("var calls = 0\nlet f = { calls += 1; return true }\nlet r = false && f()\n[r, calls]") == .array([.bool(false), .int(0)]))
        #expect(throws: SwiftalkError.self) { try eval("true.and(1)") }
        #expect(throws: SwiftalkError.self) { try eval("true.shifted(1)") }
        #expect(throws: SwiftalkError.self) { try eval("true.not(1)") }
        #expect(throws: SwiftalkError.self) { try eval("\"s\".not()") }
    }
}
