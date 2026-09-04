import Testing
@testable import Swiftalk

@Suite("% — the remainder operator (round 93)")
struct RemainderTests {
    @Test("Swift's %: the sign of the dividend; multiplicative precedence")
    func remainder() throws {
        #expect(try eval("7 % 3") == .int(1))
        #expect(try eval("-7 % 3") == .int(-1))
        #expect(try eval("7 % -3") == .int(1))
        #expect(try eval("6 % 3") == .int(0))
        #expect(try eval("1 + 7 % 3") == .int(2))
        #expect(try eval("7 % 3 * 2") == .int(2))
        #expect(try eval("2 * 7 % 3") == .int(2))
        #expect(try eval("(1...10).filter { $0 % 2 == 0 }") == .array([2, 4, 6, 8, 10].map { .int($0) }))
        #expect(try eval("let x = 17\nx % 5") == .int(2))
    }

    @Test("% 0 is a zero-division, Int.min % -1 an overflow; Ints only")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("7 % 0") }
        #expect(throws: SwiftalkError.self) { try eval("-9223372036854775808 % -1") }
        #expect(throws: SwiftalkError.self) { try eval("7.5 % 2") }
        #expect(throws: SwiftalkError.self) { try eval("7 % 2.0") }
        #expect(throws: SwiftalkError.self) { try eval("\"a\" % 2") }
        #expect(throws: SwiftalkError.self) { try eval("[1] % 2") }
    }
}
