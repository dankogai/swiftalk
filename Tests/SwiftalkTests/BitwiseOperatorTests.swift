import Testing
@testable import Swiftalk

// Round 193: Raku's numeric bitwise operators — +& +| +^ +< +>, prefix +^.
struct BitwiseOperatorTests {
    @Test("the five infix operators and the prefix, on Ints")
    func ints() throws {
        #expect(try eval("6 +& 3") == .int(2))
        #expect(try eval("6 +| 3") == .int(7))
        #expect(try eval("6 +^ 3") == .int(5))
        #expect(try eval("1 +< 4") == .int(16))
        #expect(try eval("256 +> 4") == .int(16))
        #expect(try eval("+^0") == .int(-1))
        #expect(try eval("+^ +^5") == .int(5))
        #expect(try eval("-1 +> 60") == .int(-1))                    // arithmetic shift
        #expect(try eval("1 +< 64") == .int(0))                      // Swift's smart shift: no trap
        #expect(try eval("16 +< -2") == .int(4))                     // a negative count shifts the other way
        #expect(try eval("0xff +& 0x0f") == .int(15))
    }

    @Test("precedence a la Raku: +& +< +> with * / %, +| +^ with + -; prefix +^ binds like a sign")
    func precedence() throws {
        #expect(try eval("1 +| 2 +& 3") == .int(3))                  // 1 +| (2 +& 3)
        #expect(try eval("1 + 2 +< 1") == .int(5))                   // 1 + (2 +< 1)
        #expect(try eval("2 +< 1 + 1") == .int(5))                   // (2 +< 1) + 1
        #expect(try eval("6 +& 3 * 2") == .int(4))                   // left to right at one level: (6 +& 3) * 2
        #expect(try eval("8 +> 1 +> 1") == .int(2))                  // left-assoc
        #expect(try eval("+^1 + 1") == .int(-1))                     // (+^1) + 1
        #expect(try eval("+^(1 + 1)") == .int(-3))
        #expect(try eval("1 +| 2 == 3") == .bool(true))              // above comparison
        #expect(try eval("2 ** 3 +& 12") == .int(8))                 // ** binds tighter: (2 ** 3) +& 12
    }

    @Test("Bytes come back as Bytes, masked; a Byte with an Int is an Int; anything else is a type error naming the right operator")
    func bytesAndErrors() throws {
        #expect(try eval("Byte(6) +& Byte(3)") == .byte(2))
        #expect(try eval("Byte(1) +< Byte(9)") == .byte(0))          // masked to 8 bits
        #expect(try eval("+^Byte(0)") == .byte(255))
        #expect(try eval("Byte(6) +| 8") == .int(14))
        #expect(try eval("(Byte(6) +& Byte(3)).Type == Byte") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("1.0 +& 1.0") }
        #expect(throws: SwiftalkError.self) { try eval("true +& false") }
        #expect(throws: SwiftalkError.self) { try eval("\"a\" +| \"b\"") }
        #expect(throws: SwiftalkError.self) { try eval("+^1.5") }
        #expect(throws: SwiftalkError.self) { try eval("1 | 2") }                        // still the Set operator
        #expect(try eval("Set([1, 2]) | Set([3])") == .set([.int(1), .int(2), .int(3)]))  // untouched
        #expect(try eval("Set([1, 2]) & Set([2])") == .set([.int(2)]))
        #expect(try eval("6.bitAnd(3)") == .int(2))                                     // the methods stay
    }

    @Test("compound forms, operator Functions, and a type's own infix(+&) / prefix(+^)")
    func compoundFunctionsMembers() throws {
        #expect(try eval("var x = 6\nx +&= 3\nx") == .int(2))
        #expect(try eval("var x = 6\nx +|= 1\nx +^= 4\nx") == .int(3))
        #expect(try eval("var x = 1\nx +<= 3\nx +>= 1\nx") == .int(4))
        #expect(try eval("(+&)(6, 3)") == .int(2))
        #expect(try eval("[1, 2, 4].reduce(0, +|)") == .int(7))
        #expect(try eval("[1, 2, 4].reduce(0, (+|))") == .int(7))
        #expect(try eval("(+^)(0)") == .int(-1))
        #expect(try eval("(+^)(6, 3)") == .int(5))
        #expect(try eval("(+&) == (+&) && (+&) != (+|)") == .bool(true))
        #expect(try eval("(+<).String()") == .string("(+<)"))
        #expect(try eval("struct Bits { var v: Int; infix(+&) = { a, b in Bits(v: a.v +& b.v) }; prefix(+^) = { x in Bits(v: +^x.v) } }\n(Bits(v: 6) +& Bits(v: 3)).v") == .int(2))
        #expect(try eval("struct Bits { var v: Int; prefix(+^) = { x in Bits(v: +^x.v) } }\n(+^Bits(v: 0)).v") == .int(-1))
        #expect(throws: SwiftalkError.self) { try eval("struct B { infix(+%) = { a, b in a } }") }   // not an operator
    }
}
