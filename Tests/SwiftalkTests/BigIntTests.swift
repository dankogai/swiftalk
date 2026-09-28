import Testing
@testable import Swiftalk

// Round 201: `BigInt` — arbitrary-precision integers as a prelude module
// (swift-bignum vendored, not depended on); the literal `123n`, JS's
// spelling, is the core's grammar and the module's meaning.

@Suite("BigInt: the literal")
struct BigIntLiteralTests {
    @Test("123n is a BigInt; every radix prefix; underscores; any size")
    func literal() throws {
        #expect(try eval("123n.Type == BigInt") == .bool(true))
        #expect(try eval("123n.Type.name") == .string("BigInt"))
        #expect(try eval("0xffn == 255n") == .bool(true))
        #expect(try eval("0o17n == 15n") == .bool(true))
        #expect(try eval("0b101n == 5n") == .bool(true))
        #expect(try eval("1_000_000n == 1000000n") == .bool(true))
        #expect(try eval("123456789012345678901234567890n.String()") == .string("123456789012345678901234567890n"))
        // the suffix is mandatory: without it, 20 digits are an Int overflow
        #expect(throws: SwiftalkError.self) { try eval("123456789012345678901234567890") }
    }

    @Test("the literal is grammar; the meaning is the module's")
    func needsModule() throws {
        let bare = Interpreter()                                      // no prelude
        #expect(throws: SwiftalkError.self) { try bare.eval("1n") }
        #expect(throws: SwiftalkError.self) { try eval("1.5n") }
        #expect(throws: SwiftalkError.self) { try eval("1e3n") }
    }

    @Test("what is not a literal")
    func notLiteral() throws {
        #expect(throws: SwiftalkError.self) { try eval("0xn") }
        // `n` is a hex digit? No — a, b, c, d, e, f only; but in radix 36 strings it is
        #expect(try eval("BigInt(\"n\", 36)") == (try eval("23n")))
    }

    @Test("the source form re-enters, hex under debug")
    func printing() throws {
        #expect(try eval("(-42n).String()") == .string("-42n"))
        #expect(try eval("255n.debugDescription") == .string("+0xffn"))
        #expect(try eval("(-255n).debugDescription") == .string("-0xffn"))
        #expect(try eval("[1n, 2n].String()") == .string("[1n, 2n]"))
        #expect(try eval("\"\\(2n ** 64n)\"") == .string("18446744073709551616n"))
        #expect(try eval("eval(\"12345678901234567890n\")!  == 12345678901234567890n") == .bool(true))
    }
}

@Suite("BigInt: arithmetic")
struct BigIntArithmeticTests {
    @Test("+ - * / % ** and the prefixes, never overflowing")
    func operators() throws {
        #expect(try eval("BigInt(Int.max) + 1n") == (try eval("9223372036854775808n")))
        #expect(try eval("BigInt(Int.min) - 1n") == (try eval("-9223372036854775809n")))
        #expect(try eval("2n ** 256n") == (try eval("115792089237316195423570985008687907853269984665640564039457584007913129639936n")))
        #expect(try eval("(2n ** 64n) * (2n ** 64n) == 2n ** 128n") == .bool(true))
        #expect(try eval("-7n / 2n") == (try eval("-3n")))         // truncating, as Int's
        #expect(try eval("-7n % 2n") == (try eval("-1n")))         // the dividend's sign, as Int's
        #expect(try eval("-(5n)") == (try eval("-5n")))
        #expect(try eval("+(5n)") == (try eval("5n")))
        #expect(try eval("(1...30).reduce(1n) { acc, i in acc * BigInt(i) }") == (try eval("265252859812191058636308480000000n")))
        #expect(try eval("let f = { n in n <= 1n ? 1n : n * $(n - 1n) }\nf(12n)") == (try eval("479001600n")))
        #expect(try eval("var x = 1n\nx += 1n\nx *= 10n\nx **= 2n\nx") == (try eval("400n")))
    }

    @Test("dividing by zero and negative exponents are errors")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("1n / 0n") }
        #expect(throws: SwiftalkError.self) { try eval("1n % 0n") }
        #expect(throws: SwiftalkError.self) { try eval("2n ** -1n") }
    }

    @Test("strict: a BigInt meets a BigInt — an Int or a Double must convert")
    func strict() throws {
        #expect(throws: SwiftalkError.self) { try eval("1n + 1") }
        #expect(throws: SwiftalkError.self) { try eval("1 + 1n") }
        #expect(throws: SwiftalkError.self) { try eval("1n * 2.0") }
        #expect(throws: SwiftalkError.self) { try eval("1n == 1") }
        #expect(throws: SwiftalkError.self) { try eval("1n < 2") }
        #expect(try eval("1n + BigInt(1)") == (try eval("2n")))
        #expect(try eval("1n.Int() + 1") == .int(2))
    }

    @Test("comparison and equality; sorting, min, max; Dictionary keys and switch")
    func comparable() throws {
        #expect(try eval("7n < 8n") == .bool(true))
        #expect(try eval("7n >= 8n") == .bool(false))
        #expect(try eval("7n == 7n && 7n != 8n") == .bool(true))
        #expect(try eval("[3n, 1n, 2n].sorted()") == (try eval("[1n, 2n, 3n]")))
        #expect(try eval("[3n, 1n, 2n].max()") == (try eval("3n")))
        #expect(try eval("BigInt.conforms(to: Comparable)") == .bool(false))   // the protocol table is the core's; `<` is answered all the same
        #expect(try eval("[42n: \"answer\"][42n]") == .string("answer"))
        #expect(try eval("Set([1n, 1n, 2n]).count") == .int(2))
        #expect(try eval("switch 3n { case 3n: \"three\" default: \"other\" }") == .string("three"))
        #expect(try eval("switch 4 { case 4n: 1 default: 2 }") == .int(2))     // an Int subject is no match
        #expect(throws: SwiftalkError.self) { try eval("switch 4 { case let m = 4n: 1 default: 2 }") }
    }

    @Test("bitwise, Raku's spelling, at any width")
    func bitwise() throws {
        #expect(try eval("(1n +< 100n) +> 99n") == (try eval("2n")))
        #expect(try eval("0xf0n +& 0x3cn") == (try eval("0x30n")))
        #expect(try eval("0xf0n +| 0x0fn") == (try eval("255n")))
        #expect(try eval("0xffn +^ 0x0fn") == (try eval("0xf0n")))
        #expect(try eval("+^0n") == (try eval("-1n")))
    }
}

@Suite("BigInt: conversions and members")
struct BigIntMemberTests {
    @Test("BigInt(x) from Int, Byte, Double, String, BigInt; radix digits")
    func construct() throws {
        #expect(try eval("BigInt(42)") == (try eval("42n")))
        #expect(try eval("BigInt(Byte(255))") == (try eval("255n")))
        #expect(try eval("BigInt(1e3)") == (try eval("1000n")))
        #expect(try eval("BigInt(\"0xdead_beef\")") == (try eval("3735928559n")))
        #expect(try eval("BigInt(\"-12n\")") == (try eval("-12n")))
        #expect(try eval("BigInt(\"ff\", 16)") == (try eval("255n")))
        #expect(try eval("BigInt(\"zz\", 36)") == (try eval("1295n")))
        #expect(try eval("BigInt(7n) == 7n") == .bool(true))
        #expect(try eval("BigInt()") == (try eval("0n")))
        #expect(try eval("42.BigInt()") == (try eval("42n")))
        #expect(throws: SwiftalkError.self) { try eval("BigInt(1.5)") }
        #expect(throws: SwiftalkError.self) { try eval("BigInt(\"twelve\")") }
        #expect(throws: SwiftalkError.self) { try eval("BigInt(true)") }
        #expect(throws: SwiftalkError.self) { try eval("BigInt(\"ff\", 10)") }
    }

    @Test("back to Int (or an overflow), to Double, to String in a radix")
    func convert() throws {
        #expect(try eval("(2n ** 62n).Int()") == .int(4611686018427387904))
        #expect(try eval("Int(-1n)") == .int(-1))
        #expect(throws: SwiftalkError.self) { try eval("(2n ** 64n).Int()") }
        #expect(try eval("(2n ** 100n).Double()") == .double(1.2676506002282294e+30))
        #expect(try eval("Double(3n)") == .double(3.0))
        #expect(try eval("String(255n)") == .string("255n"))
        #expect(try eval("255n.String(.hex)") == .string("0xffn"))
        #expect(try eval("(-255n).String(.oct)") == .string("-0o377n"))
        #expect(try eval("5n.String(.bin)") == .string("0b101n"))
        #expect(try eval("255n.String(16)") == .string("ff"))
        #expect(try eval("255n.String(radix: 36)") == .string("73"))
        #expect(try eval("42n.String(.sign)") == .string("+42"))
        #expect(throws: SwiftalkError.self) { try eval("255n.String(1)") }
        #expect(try eval("BigInt(255n.String(.hex)) == 255n") == .bool(true))   // hex re-enters
    }

    @Test("the number-theory members")
    func members() throws {
        #expect(try eval("10n.power(20)") == (try eval("100000000000000000000n")))
        #expect(try eval("3n.power(100n, 7n)") == (try eval("4n")))
        #expect(try eval("(10n ** 40n).squareRoot()") == (try eval("100000000000000000000n")))
        #expect(try eval("12n.gcd(18n)") == (try eval("6n")))
        #expect(try eval("(-7n).magnitude") == (try eval("7n")))
        #expect(try eval("(-7n).signum") == .int(-1))
        #expect(try eval("0n.isZero") == .bool(true))
        #expect(try eval("255n.bitWidth") == .int(9))
        #expect(try eval("8n.trailingZeroBitCount") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval("(-4n).squareRoot()") }
        #expect(throws: SwiftalkError.self) { try eval("2n.power(-1)") }
        #expect(throws: SwiftalkError.self) { try eval("2n.gcd(3)") }
        #expect(throws: SwiftalkError.self) { try eval("2n.nope") }
    }

    @Test("a module like any: importable by name into a bare interpreter")
    func importable() throws {
        let bare = Interpreter()
        bare.modulePath = [buildDirectory()].compactMap { $0 }
        #expect(try bare.eval("import from \"BigInt\"\n(2n ** 70n).String()") == .string("1180591620717411303424n"))
        #expect(try bare.eval("import B from \"BigInt\"\nB.BigInt(\"9\") ** 30n == 9n ** 30n") == .bool(true))
    }
}
