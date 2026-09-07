import Testing
@testable import Swiftalk

@Suite("prefix +, a signed .hex, and === / !== (round 121)")
struct PrefixPlusIdentityTests {
    @Test("prefix + is the number itself — Int, Double, Byte; anything else is a type error")
    func prefixPlus() throws {
        #expect(try eval("+1.0") == .double(1))
        #expect(try eval("+1") == .int(1))
        #expect(try eval("+(-1)") == .int(-1))
        #expect(try eval("-+1") == .int(-1))
        #expect(try eval("+Byte(3)") == .byte(3))
        #expect(try eval("[+1, -1, +0.0]") == .array([.int(1), .int(-1), .double(0)]))
        #expect(try eval("let x = 2\nx +1") == .int(3))                  // still binary after an operand
        #expect(try eval("let x = 2\nx + +1") == .int(3))
        #expect(try eval("(+0.0).String(.hex)") == .string("+0x0p0"))
        #expect(try eval("SION(\"[+1, +2.5]\")") == .array([.int(1), .double(2.5)]))
        #expect(throws: SwiftalkError.self) { try eval("+\"a\"") }
        #expect(throws: SwiftalkError.self) { try eval("+true") }
        #expect(throws: SwiftalkError.self) { try eval("+nil") }
    }

    @Test(".String(.hex) carries its sign: +0xff, -0x10, +0x0p0, -0x0p0; nan and inf as they are; still re-enters")
    func signedHex() throws {
        #expect(try eval("255.String(.hex)") == .string("+0xff"))
        #expect(try eval("0.String(.hex)") == .string("+0x0"))
        #expect(try eval("(-16).String(.hex)") == .string("-0x10"))
        #expect(try eval("(0.0).String(.hex)") == .string("+0x0p0"))
        #expect(try eval("(-0.0).String(.hex)") == .string("-0x0p0"))
        #expect(try eval("(-1.5).String(.hex)") == .string("-0x1.8p0"))
        #expect(try eval("Double.nan.String(.hex)") == .string("nan"))
        #expect(try eval("Double.infinity.String(.hex)") == .string("inf"))
        #expect(try eval("(-Double.infinity).String(.hex)") == .string("-inf"))
        #expect(try eval("Int(255.String(.hex))") == .int(255))
        #expect(try eval("Double((-0.0).String(.hex)).String(.hex)") == .string("-0x0p0"))
        #expect(try eval("255.debugDescription") == .string("0xff"))       // the debug form is unchanged
        #expect(try eval("16.String(.oct)") == .string("0o20"))            // .oct/.bin unchanged
    }

    @Test("=== / !==: the same type and the same bits — nan === nan, +0.0 !== -0.0; never a type error")
    func identity() throws {
        #expect(try eval("1.0 === 1.0") == .bool(true))
        #expect(try eval("0.0 === -0.0") == .bool(false))
        #expect(try eval("+0.0 !== -0.0") == .bool(true))
        #expect(try eval("0.0 == -0.0") == .bool(true))
        #expect(try eval("Double.nan === Double.nan") == .bool(true))
        #expect(try eval("Double.nan == Double.nan") == .bool(false))
        #expect(try eval("Double.nan !== Double.nan") == .bool(false))
        #expect(try eval("1 === 1") == .bool(true))
        #expect(try eval("1 === 1.0") == .bool(false))                     // different types: false, not an error
        #expect(throws: SwiftalkError.self) { try eval("1 == 1.0") }
        #expect(try eval("Byte(1) === 1") == .bool(false))
        #expect(try eval("Byte(1) == 1") == .bool(true))
        #expect(try eval("\"a\" === \"a\"") == .bool(true))
        #expect(try eval("nil === nil") == .bool(true))
        #expect(try eval("1 === nil") == .bool(false))
        #expect(try eval("[0.0] === [-0.0]") == .bool(false))
        #expect(try eval("[0.0] == [-0.0]") == .bool(true))
        #expect(try eval("[0.0: 1] === [-0.0: 1]") == .bool(false))
        #expect(try eval("[\"k\": [Double.nan]] === [\"k\": [Double.nan]]") == .bool(true))
        #expect(try eval("(x: 0.0) === (-0.0,)") == .bool(false))
        #expect(try eval("(x: 1) === (1,)") == .bool(true))                 // labels are cosmetic, as for ==
        #expect(try eval("struct P { var x: Double = 0.0 }\nP(x: 0.0) === P(x: -0.0)") == .bool(false))
        #expect(try eval("struct P { var x: Double = 0.0 }\nP(x: 0.0) === P(x: 0.0)") == .bool(true))
        #expect(try eval("enum E { case v(Double) }\nE.v(0.0) === E.v(-0.0)") == .bool(false))
        #expect(try eval("let x = 1.0\nx === 1.0 && x !== 2.0") == .bool(true))
        #expect(try eval("1.0 ===\n1.0") == .bool(true))                  // continues the line, as == does
    }
}
