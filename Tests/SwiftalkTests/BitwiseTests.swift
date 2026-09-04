import Testing
@testable import Swiftalk

@Suite("bitwise, as methods: and/or/xor/not, shifted(by:), bit, bits, Int(bits:), Bool(Int) (round 105)")
struct BitwiseTests {
    @Test("and, or, xor, not — Swift's semantics on 64-bit Ints")
    func logic() throws {
        #expect(try eval("0b1100.and(0b1010)") == .int(0b1000))
        #expect(try eval("0b1100.or(0b1010)") == .int(0b1110))
        #expect(try eval("0b1100.xor(0b1010)") == .int(0b0110))
        #expect(try eval("5.not()") == .int(-6))
        #expect(try eval("(-1).and(255)") == .int(255))
        #expect(try eval("0xff.or(0x100)") == .int(0x1ff))
    }

    @Test("shifted(by:): positive left, negative right (arithmetic); overshifts give 0 or -1, never a trap")
    func shifts() throws {
        #expect(try eval("1.shifted(by: 10)") == .int(1024))
        #expect(try eval("1.shifted(10)") == .int(1024))
        #expect(try eval("1024.shifted(by: -3)") == .int(128))
        #expect(try eval("(-16).shifted(by: -2)") == .int(-4))
        #expect(try eval("1.shifted(by: 64)") == .int(0))
        #expect(try eval("(-1).shifted(by: -70)") == .int(-1))
        #expect(try eval("1.shifted(by: 63)") == .int(Int64.min))          // discards high bits, as << does
        #expect(try eval("0xE0.or(0x1F600.shifted(by: -12))") == .int(0xFF))      // a UTF-8 lead byte, from the example
        #expect(try eval("0x80.or(0x1F600.shifted(by: -6).and(63))") == .int(0x98))
    }

    @Test("bit(i), the [Bool] view, and Int(bits:) round-trip; the Swift bit counts")
    func views() throws {
        #expect(try eval("0b1010.bit(1)") == .bool(true))
        #expect(try eval("0b1010.bit(0)") == .bool(false))
        #expect(try eval("5.bits.prefix(4)") == .array([.bool(true), .bool(false), .bool(true), .bool(false)]))
        #expect(try eval("(-1).bits.count") == .int(64))
        #expect(try eval("Int(bits: [true, false, true])") == .int(5))
        #expect(try eval("Int(bits: [])") == .int(0))
        #expect(try eval("Int(bits: (-1).bits)") == .int(-1))
        #expect(try eval("Int(bits: 42.bits) == 42") == .bool(true))
        #expect(try eval("255.nonzeroBitCount") == .int(8))
        #expect(try eval("1.leadingZeroBitCount") == .int(63))
        #expect(try eval("8.trailingZeroBitCount") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval("5.bit(64)") }
        #expect(throws: SwiftalkError.self) { try eval("Int(bits: [1])") }
        #expect(throws: SwiftalkError.self) { try eval("Int(bits: (0...64).map { true })") }
    }

    @Test("Bool(Int) is a conversion — false for 0, true otherwise — and not truthiness; Ints only elsewhere")
    func boolAndErrors() throws {
        #expect(try eval("Bool(0)") == .bool(false))
        #expect(try eval("Bool(-3)") == .bool(true))
        #expect(try eval("3.Bool()") == .bool(true))                       // the round-47 law
        #expect(throws: SwiftalkError.self) { try eval("if 3 { }") }         // §3b stands
        #expect(throws: SwiftalkError.self) { try eval("Bool(1.5)") }
        #expect(throws: SwiftalkError.self) { try eval("5.and(1.5)") }
        #expect(throws: SwiftalkError.self) { try eval("\"x\".and(1)") }
        #expect(throws: SwiftalkError.self) { try eval("5.not(1)") }
        #expect(throws: SwiftalkError.self) { try eval("5.shifted()") }
    }
}
