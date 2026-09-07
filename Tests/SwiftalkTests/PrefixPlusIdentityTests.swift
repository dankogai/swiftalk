import Testing
@testable import Swiftalk

@Suite("prefix +, === / !== (round 121); .sign, the debug form as .String(.sign, .hex) (round 125)")
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
        #expect(try eval("(+0.0).String(.sign, .hex)") == .string("+0x0p0"))
        #expect(try eval("SION(\"[+1, +2.5]\")") == .array([.int(1), .double(2.5)]))
        #expect(throws: SwiftalkError.self) { try eval("+\"a\"") }
        #expect(throws: SwiftalkError.self) { try eval("+true") }
        #expect(throws: SwiftalkError.self) { try eval("+nil") }
    }

    @Test(".sign (round 125, revising 121/124): a positive number's + on request — plain, .hex/.oct/.bin, radix:; the debug form is .String(.sign, .hex)")
    func sign() throws {
        #expect(try eval("255.String(.hex)") == .string("0xff"))
        #expect(try eval("(-16).String(.hex)") == .string("-0x10"))
        #expect(try eval("255.String(.sign, .hex)") == .string("+0xff"))
        #expect(try eval("255.String(.hex, .sign)") == .string("+0xff"))
        #expect(try eval("0.String(.sign, .hex)") == .string("+0x0"))
        #expect(try eval("(0.0).String(.hex)") == .string("0x0p0"))
        #expect(try eval("(0.0).String(.sign, .hex)") == .string("+0x0p0"))
        #expect(try eval("(-0.0).String(.hex)") == .string("-0x0p0"))
        #expect(try eval("(-0.0).String(.sign, .hex)") == .string("-0x0p0"))
        #expect(try eval("Double.nan.String(.sign, .hex)") == .string("nan"))              // nan has no sign
        #expect(try eval("Double.infinity.String(.hex)") == .string("inf"))
        #expect(try eval("Double.infinity.String(.sign, .hex)") == .string("+inf"))
        #expect(try eval("(-Double.infinity).String(.sign, .hex)") == .string("-inf"))
        #expect(try eval("42.String(.sign)") == .string("+42"))
        #expect(try eval("(-42).String(.sign)") == .string("-42"))
        #expect(try eval("0.String(.sign)") == .string("+0"))
        #expect(try eval("(1.5).String(.sign)") == .string("+1.5"))
        #expect(try eval("(-0.0).String(.sign)") == .string("-0.0"))
        #expect(try eval("Double.nan.String(.sign)") == .string("nan"))
        #expect(try eval("Byte(7).String(.sign)") == .string("+7"))
        #expect(try eval("255.String(.sign, radix: 16)") == .string("+ff"))
        #expect(try eval("(-255).String(radix: 16)") == .string("-ff"))
        #expect(try eval("16.String(.sign, .oct)") == .string("+0o20"))
        #expect(try eval("16.String(.oct)") == .string("0o20"))
        #expect(try eval("(-5).String(.sign, .bin)") == .string("-0b101"))
        #expect(try eval("Int(255.String(.sign, .hex))") == .int(255))                     // prefix + re-enters (round 121)
        #expect(try eval("Int(\"+42\")") == .int(42))
        #expect(try eval("Double(\"+1.5\")") == .double(1.5))
        #expect(try eval("eval(255.String(.sign, .bin)) == 255") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("\"s\".String(.sign)") }
        #expect(throws: SwiftalkError.self) { try eval("[1].String(.sign)") }
        #expect(throws: SwiftalkError.self) { try eval("1.String(.sign, .json)") }
        #expect(throws: SwiftalkError.self) { try eval("1.String(.sign, .quoted)") }
        #expect(throws: SwiftalkError.self) { try eval("[1].String(.sign, .pretty)") }
        #expect(throws: SwiftalkError.self) { try eval("1.String(.sign, .sign)") }
        // debugDescription for Int and Double is .String(.sign, .hex) — through collections and Ranges
        #expect(try eval("255.debugDescription") == .string("+0xff"))
        #expect(try eval("(-16).debugDescription") == .string("-0x10"))
        #expect(try eval("(1.5).debugDescription") == .string("+0x1.8p0"))
        #expect(try eval("(0.5).debugDescription == (0.5).String(.sign, .hex)") == .bool(true))
        #expect(try eval("(-7).debugDescription == (-7).String(.sign, .hex)") == .bool(true))
        #expect(try eval("(255...4096).debugDescription") == .string("+0xff...+0x1000"))
        #expect(try eval("[255, -1].debugDescription") == .string("[+0xff, -0x1]"))
        #expect(try eval("Data([255]).debugDescription") == .string("Data([0xff])"))       // bytes have no sign
        #expect(try eval("Byte(255).debugDescription") == .string("Byte(0xff)"))
        #expect(try eval(".Date(1.0).debugDescription") == .string(".Date(0x1p0)"))       // SION's spelling, unsigned
        #expect(try eval("eval(255.debugDescription) == 255") == .bool(true))
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
