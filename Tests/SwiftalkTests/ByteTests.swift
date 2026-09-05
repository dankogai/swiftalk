import Testing
@testable import Swiftalk

@Suite("Byte — Data's element type, an Int that fits a byte (round 116)")
struct ByteTests {
    let d = "let d = \"hé!\".Data(.utf8)\n"     // [104, 195, 169, 33]

    @Test("construction, statics, and the source form")
    func construction() throws {
        #expect(try eval("Byte(104)") == .byte(104))
        #expect(try eval("Byte()") == .byte(0))
        #expect(try eval("Byte(256)") == .nil)
        #expect(try eval("Byte(-1)") == .nil)
        #expect(try eval("Byte(\"0xff\")") == .byte(255))
        #expect(try eval("Byte(3.9)") == .byte(3))
        #expect(try eval("Byte(Byte(7))") == .byte(7))
        #expect(try eval("Byte.max") == .byte(255))
        #expect(try eval("Byte.min") == .byte(0))
        #expect(try eval("Byte.bitWidth") == .int(8))
        #expect(try eval("Byte.isSigned") == .bool(false))
        #expect(try eval("Byte(5).String()") == .string("Byte(5)"))
        #expect(try eval("Byte(255).debugDescription") == .string("Byte(0xff)"))
        #expect(try eval("Byte(5).Type == Byte") == .bool(true))
        #expect(try eval("Byte(5).Int()") == .int(5))
        #expect(try eval("Byte(5).Double()") == .double(5))
        guard case .string(let src) = try eval("Byte(9).String()") else { throw SwiftalkError.type("expected string") }
        #expect(try eval(src) == .byte(9))                                    // the round-trip law
        #expect(throws: SwiftalkError.self) { try eval("Byte([1])") }
    }

    @Test("Byte op Byte is a Byte and traps; Byte op Int is an Int; comparison and equality by value; hashing to match")
    func interop() throws {
        #expect(try eval("Byte(3) + Byte(4)") == .byte(7))
        #expect(try eval("(Byte(3) + Byte(4)).Type == Byte") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("Byte(200) + Byte(100)") }
        #expect(throws: SwiftalkError.self) { try eval("Byte(3) - Byte(5)") }
        #expect(throws: SwiftalkError.self) { try eval("Byte(7) / Byte(0)") }
        #expect(try eval("Byte(7) % Byte(4)") == .byte(3))
        #expect(try eval("Byte(200) + 100") == .int(300))
        #expect(try eval("1 + Byte(2)") == .int(3))
        #expect(try eval("Byte(5) < 7") == .bool(true))
        #expect(try eval("7 > Byte(5)") == .bool(true))
        #expect(try eval("Byte(33) == 33") == .bool(true))
        #expect(try eval("33 == Byte(33)") == .bool(true))
        #expect(try eval("Byte(3) != 3") == .bool(false))
        #expect(try eval("Byte(3) == Byte(3)") == .bool(true))
        #expect(try eval("[Byte(1): \"one\"][1]") == .string("one"))            // the same hash
        #expect(try eval("[1: \"one\"][Byte(1)]") == .string("one"))
        #expect(throws: SwiftalkError.self) { try eval("Byte(1) == 1.0") }        // Doubles stay apart
        #expect(throws: SwiftalkError.self) { try eval("Byte(1) + 1.0") }
        // locks tell them apart
        #expect(throws: SwiftalkError.self) { try eval("let x: Int = Byte(1)") }
        #expect(throws: SwiftalkError.self) { try eval("var n = 5\nn = Byte(1)") }
        #expect(throws: SwiftalkError.self) { try eval("let s: SION = Byte(1)") }
        #expect(try eval("Double.sqrt(Byte(16))") == .double(4))
        #expect(try eval("[Byte(1), Byte(2)].String(.json)") == .string("[1,2]"))
    }

    @Test("Data speaks Byte: subscripts, writes, iteration, slices, literals; round 115's ergonomics survive")
    func data() throws {
        #expect(try eval(d + "d[0]") == .byte(104))
        #expect(try eval(d + "d[0] == 104") == .bool(true))
        #expect(try eval(d + "d[0] + 1") == .int(105))
        #expect(try eval(d + "d.filter { $0 > 127 }") == .data([195, 169]))
        #expect(try eval(d + "d.reduce(0) { $0 + $1 }") == .int(501))
        #expect(try eval(d + "d.contains(33)") == .bool(true))
        #expect(try eval(d + "d.sorted()") == .array([33, 104, 169, 195].map { .byte($0) }))
        #expect(try eval(d + "d.map { $0 * 2 }") == .array([208, 390, 338, 66].map { .int($0) }))
        #expect(try eval("Data([Byte(1), 2])") == .data([1, 2]))
        #expect(try eval("var e = Data([1, 2])\ne[0] = Byte(9)\ne[1] = 8\ne") == .data([9, 8]))
        #expect(throws: SwiftalkError.self) { try eval("var e = Data([1])\ne[0] = 300") }
        #expect(try eval("Data([104, 105]).map(String.fromCodePoint).joined()") == .string("hi"))
    }

    @Test("bitwise on a Byte masks to 8 bits; Data.random(n)")
    func bitsAndRandom() throws {
        #expect(try eval("Byte(0xF0).bitAnd(0x3C)") == .byte(0x30))
        #expect(try eval("Byte(0xF0).bitOr(Byte(0x0F))") == .byte(0xFF))
        #expect(try eval("Byte(1).shifted(by: 9)") == .byte(0))
        #expect(try eval("Byte(1).shifted(by: 3)") == .byte(8))
        #expect(try eval("Byte(1).bitNot()") == .byte(254))
        #expect(try eval("Data.random(4).count") == .int(4))
        #expect(try eval("Data.random(0)") == .data([]))
        #expect(try eval("Data.random(64).Type == Data") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("Data.random(-1)") }
        #expect(throws: SwiftalkError.self) { try eval("Data.random()") }
    }
}
