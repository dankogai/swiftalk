import Testing
@testable import Swiftalk

@Suite(".String() formats: .quoted, .hex/.oct/.bin, radix: (rounds 20-21, 42)")
struct StringFormatTests {
    @Test("str.String() is str; .String(.quoted) quotes and escapes; the law relocates")
    func quoted() throws {
        #expect(try eval(#""foo".String()"#) == .string("foo"))
        #expect(try eval(#""foo".String(.quoted)"#) == .string(#""foo""#))
        // the round-trip law, restated (round 42): eval(x.String(.quoted)) == x
        let original = try eval(#""line\nbreak \"q\" \\slash""#)
        guard case .string(let quoted) = try eval(#""line\nbreak \"q\" \\slash".String(.quoted)"#) else {
            throw SwiftalkError.type("expected string")
        }
        #expect(try eval(quoted) == original)
        // non-Strings: .String(.quoted) == .String(), both still round-trip
        #expect(try eval("42.String(.quoted)") == .string("42"))
        #expect(try eval("[1, 2].String(.quoted)") == .string("[1, 2]"))
    }

    @Test(".String() now agrees with String(x) and print everywhere (round 39's asymmetry dissolved)")
    func unifiedDescription() throws {
        #expect(try eval(#""a".String() == String("a")"#) == .bool(true))
        #expect(try eval("42.String() == String(42)") == .bool(true))
        #expect(try eval(#""a".String() == "a".description"#) == .bool(true))
    }

    @Test(".hex/.oct/.bin are prefixed and literal-ready; radix: is bare (round 20)")
    func radixFormats() throws {
        #expect(try eval("255.String(.hex)") == .string("0xff"))
        #expect(try eval("255.String(.oct)") == .string("0o377"))
        #expect(try eval("255.String(.bin)") == .string("0b11111111"))
        #expect(try eval("(-16).String(.hex)") == .string("-0x10"))
        #expect(try eval("255.String(radix: 16)") == .string("ff"))
        #expect(try eval("255.String(radix: 36)") == .string("73"))
        #expect(try eval("(-255).String(radix: 16)") == .string("-ff"))
        #expect(try eval("(255.0).String(.hex)") == .string("0x1.fep7"))
        #expect(try eval("(1.5).String(.hex)") == .string("0x1.8p0"))
    }

    @Test("the round-21 invariant, now executable: prefixed strings round-trip")
    func prefixedRoundTrip() throws {
        #expect(try eval("Int(255.String(.hex)) == 255") == .bool(true))
        #expect(try eval("Int((-42).String(.oct)) == -42") == .bool(true))
        #expect(try eval("Int(9.String(.bin)) == 9") == .bool(true))
        #expect(try eval("Double((255.5).String(.hex)) == 255.5") == .bool(true))
    }

    @Test("format errors: wrong receiver, unknown format, bad radix")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval(#""s".String(.hex)"#) }
        #expect(throws: SwiftalkError.self) { try eval("42.String(.nope)") }
        #expect(throws: SwiftalkError.self) { try eval("42.String(radix: 1)") }
        #expect(throws: SwiftalkError.self) { try eval("(1.5).String(radix: 16)") }
        #expect(throws: SwiftalkError.self) { try eval("42.String(.hex, .oct)") }
    }
}
