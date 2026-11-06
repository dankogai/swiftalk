import Testing
@testable import Swiftalk

@Suite("n.flip(i) on an Int and a BigInt (round 278)")
struct IntFlipTests {
    @Test("an Int's bit i flips in place, i in 0..<64; through a path; the call is nil")
    func int() throws {
        #expect(try eval("var n = 0\nn.flip(0)\nn") == .int(1))
        #expect(try eval("var n = 5\nn.flip(0)\nn") == .int(4))
        #expect(try eval("var n = 0\nn.flip(3)\nn.flip(3)\nn") == .int(0))
        #expect(try eval("var n = 0\nn.flip(63)\nn") == .int(Int64.min))
        #expect(try eval("var n = -1\nn.flip(63)\nn") == .int(Int64.max))
        #expect(try eval("var n = 0\nn.flip(4)") == .nil)
        #expect(try eval("var a = [0, 0]\na[1].flip(3)\na") == .array([.int(0), .int(8)]))
        #expect(try eval("struct S { var mask = 0 }\nvar s = S()\ns.mask.flip(1)\ns.mask") == .int(2))
        #expect(try eval("var n = 0\nfor i in 0..<4 { n.flip(i) }\nn") == .int(15))
    }

    @Test("beyond the width is the overflow trap; the index is one Int; the receiver a var")
    func intErrors() throws {
        do { _ = try eval("var n = 0\nn.flip(64)"); Issue.record("no trap") } catch SwiftalkError.overflow { }
        do { _ = try eval("var n = 0\nn.flip(-1)"); Issue.record("no trap") } catch SwiftalkError.overflow { }
        #expect(throws: SwiftalkError.self) { try eval("var n = 0\nn.flip()") }
        #expect(throws: SwiftalkError.self) { try eval("var n = 0\nn.flip(1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("var n = 0\nn.flip(1.0)") }
        #expect(throws: SwiftalkError.self) { try eval("var n = 0\nn.flip(bit: 1)") }
        #expect(throws: SwiftalkError.self) { try eval("let n = 0\nn.flip(1)") }
        #expect(throws: SwiftalkError.self) { try eval("1.flip(0)") }
        #expect(try eval("var n = 0\nlet r = eval(\"n.flip(64)\")\nr.failure.String().contains(\"0..<64\")") == .bool(true))
    }

    @Test("a BigInt's bit i flips at any width; composed from the type's own +< and +^")
    func bigInt() throws {
        #expect(try eval("var b = 0n\nb.flip(0)\nb == 1n") == .bool(true))
        #expect(try eval("var b = 0n\nb.flip(1024)\nb == 2n ** 1024n") == .bool(true))
        #expect(try eval("var b = 0n\nb.flip(1024)\nb.flip(1024)\nb == 0n") == .bool(true))
        #expect(try eval("var b = -1n\nb.flip(0)\nb == -2n") == .bool(true))
        #expect(try eval("var b = 0n\nb.flip(64)\nb.bitWidth") == .int(66))
        #expect(try eval("var b = 0n\nb.flip(5)") == .nil)
        #expect(try eval("var a = [0n]\na[0].flip(100)\na[0] == 2n ** 100n") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("var b = 0n\nb.flip(-1)") }
        #expect(throws: SwiftalkError.self) { try eval("var b = 0n\nb.flip(1n)") }
        #expect(throws: SwiftalkError.self) { try eval("var b = 0n\nb.flip()") }
        #expect(throws: SwiftalkError.self) { try eval("let b = 0n\nb.flip(1)") }
        #expect(throws: SwiftalkError.self) { try eval("0n.flip(1)") }
        #expect(throws: SwiftalkError.self) { try eval("var r = BigRat(1)\nr.flip(0)") }
        #expect(throws: SwiftalkError.self) { try eval("var d = 1.0\nd.flip(0)") }
        #expect(try eval("var r = BigRat(1)\nlet e = eval(\"r.flip(0)\")\ne.failure.String().contains(\"BigRat.flip()\")") == .bool(true))
    }
}
