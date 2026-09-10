import Testing
@testable import Swiftalk

@Suite("** — exponentiation on Int and Double (round 142)")
struct PowerTests {
    @Test("Int ** Int is an Int, trapping on overflow; Double ** Double is pow; mixed and negative Int exponents are errors")
    func values() throws {
        #expect(try eval("2 ** 10") == .int(1024))
        #expect(try eval("3 ** 0") == .int(1))
        #expect(try eval("0 ** 0") == .int(1))
        #expect(try eval("(-2) ** 3") == .int(-8))
        #expect(try eval("(-2) ** 2") == .int(4))
        #expect(try eval("7 ** 1") == .int(7))
        #expect(try eval("2 ** 62") == .int(4611686018427387904))
        #expect(try eval("(-2) ** 63 == Int.min") == .bool(true))
        #expect(try eval("2.0 ** 0.5") == .double(2.0.squareRoot()))
        #expect(try eval("2.0 ** -1.0") == .double(0.5))
        #expect(try eval("10.0 ** 3.0") == .double(1000))
        #expect(try eval("(-8.0) ** (1.0 / 3.0)").isNaN)
        #expect(try eval("0.0 ** 0.0") == .double(1))
        #expect(try eval("2 ** 3 ** 2") == .int(512))                      // right-associative: 2 ** 9
        #expect(try eval("2 * 3 ** 2") == .int(18))                        // above *
        #expect(try eval("2 ** 3 * 2") == .int(16))
        #expect(try eval("-2 ** 2") == .int(-4))                           // -(2 ** 2), Python's reading
        #expect(try eval("2.0 ** -1.0") == .double(0.5))                   // the right side may carry its sign
        #expect(try eval("var x = 3\nx **= 2\nx") == .int(9))
        #expect(try eval("var d = 2.0\nd **= 3.0\nd") == .double(8))
        #expect(try eval("[1, 2, 3].map { $0 ** 2 }") == .array([.int(1), .int(4), .int(9)]))
        #expect(try eval("2 **\n3") == .int(8))                            // continues the line
        #expect(throws: SwiftalkError.self) { try eval("2 ** 63") }       // overflow
        #expect(throws: SwiftalkError.self) { try eval("10 ** 19") }
        #expect(throws: SwiftalkError.self) { try eval("2 ** -1") }       // no Int answer
        #expect(throws: SwiftalkError.self) { try eval("2 ** 2.0") }      // mixed
        #expect(throws: SwiftalkError.self) { try eval("2.0 ** 2") }
        #expect(throws: SwiftalkError.self) { try eval("\"a\" ** 2") }
        #expect(throws: SwiftalkError.self) { try eval("true ** true") }
        #expect(throws: SwiftalkError.self) { try eval("Byte(2) ** Byte(2)") }
    }
}

private extension Value {
    var isNaN: Bool { if case .double(let d) = self { return d.isNaN }; return false }
}
