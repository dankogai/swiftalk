import Testing
@testable import Swiftalk

@Suite("Int.min, Int.max, … — Swift's static properties (round 113)")
struct IntStaticsTests {
    @Test("Int's: min, max, bitWidth, zero, isSigned; Double's zero, radix, and bit counts")
    func statics() throws {
        #expect(try eval("Int.min") == .int(Int64.min))
        #expect(try eval("Int.max") == .int(Int64.max))
        #expect(try eval("Int.bitWidth") == .int(64))
        #expect(try eval("Int.zero") == .int(0))
        #expect(try eval("Int.isSigned") == .bool(true))
        #expect(try eval("Int.max == 9223372036854775807") == .bool(true))
        #expect(try eval("Int.min == -9223372036854775807 - 1") == .bool(true))
        #expect(try eval("let I = Int\nI.max == Int.max") == .bool(true))          // through a type binding (round 111)
        #expect(try eval("Double.zero") == .double(0))
        #expect(try eval("Double.radix") == .double(2))
        #expect(try eval("Double.exponentBitCount") == .double(11))
        #expect(try eval("Double.significandBitCount") == .double(52))
        #expect(throws: SwiftalkError.self) { try eval("Int.max + 1") }             // the overflow trap, as ever
        #expect(throws: SwiftalkError.self) { try eval("Int.max()") }
        #expect(throws: SwiftalkError.self) { try eval("Int.nope") }
    }
}
