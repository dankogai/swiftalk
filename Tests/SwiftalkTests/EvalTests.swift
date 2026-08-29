import Testing
@testable import Swiftalk

@Suite("Milestone 0: eval() over primitives")
struct EvalTests {
    @Test("scalar literals")
    func scalars() throws {
        #expect(try eval("nil") == .nil)
        #expect(try eval("true") == .bool(true))
        #expect(try eval("false") == .bool(false))
        #expect(try eval("42") == .int(42))
        #expect(try eval("-42") == .int(-42))
        #expect(try eval("1_000_000") == .int(1_000_000))
        #expect(try eval("1.5") == .double(1.5))
        #expect(try eval("1e3") == .double(1000.0))
        #expect(try eval("\"café 🍰\"") == .string("café 🍰"))
        #expect(try eval(#""a\nb\t\"q\" \u{1F600}""#) == .string("a\nb\t\"q\" 😀"))
    }

    @Test("radix-prefixed integer literals (§3d round-trip partners)")
    func radixLiterals() throws {
        #expect(try eval("0xff") == .int(255))
        #expect(try eval("0o377") == .int(255))
        #expect(try eval("0b11111111") == .int(255))
        #expect(try eval("-0x10") == .int(-16))
    }

    @Test("collection literals: [element], [Key: Value], [], [:]")
    func collections() throws {
        #expect(try eval("[1, 2, 3]") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval("[]") == .array([]))
        #expect(try eval("[:]") == .dictionary([:]))
        #expect(try eval(#"["swift": 2014, "smalltalk": 1972]"#)
            == .dictionary([.string("swift"): .int(2014), .string("smalltalk"): .int(1972)]))
        // non-String keys, as SION demands (§3c)
        #expect(try eval("[1: \"one\", true: \"yes\"]")
            == .dictionary([.int(1): .string("one"), .bool(true): .string("yes")]))
        // heterogeneous array — [Primitives] in language terms (§3c)
        #expect(try eval(#"[1, "one", 2.0]"#)
            == .array([.int(1), .string("one"), .double(2.0)]))
        // nesting
        #expect(try eval(#"[[1, 2], [3, [4]]]"#)
            == .array([.array([.int(1), .int(2)]), .array([.int(3), .array([.int(4)])])]))
    }

    @Test("same-type arithmetic; mixing is a type error (§3)")
    func arithmetic() throws {
        #expect(try eval("1 + 2 * 3") == .int(7))
        #expect(try eval("(1 + 2) * 3") == .int(9))
        #expect(try eval("7 / 2") == .int(3))
        #expect(try eval("0.1 + 0.2") == .double(0.30000000000000004))
        #expect(try eval("\"swift\" + \"alk\"") == .string("swiftalk"))
        #expect(try eval("[1] + [2]") == .array([.int(1), .int(2)]))
        #expect(throws: SwiftalkError.self) { try eval("1 + 1.5") }
        #expect(throws: SwiftalkError.self) { try eval("1 + \"1\"") }
        #expect(throws: SwiftalkError.self) { try eval("true + true") }
    }

    @Test("Int is 64-bit and overflow traps (§3b)")
    func overflow() throws {
        #expect(try eval("9223372036854775807") == .int(Int64.max))
        #expect(throws: SwiftalkError.self) { try eval("9223372036854775807 + 1") }
        #expect(throws: SwiftalkError.self) { try eval("9223372036854775808") }
        #expect(throws: SwiftalkError.self) { try eval("1 / 0") }
        // 20! fits; Double stays IEEE
        #expect(try eval("2432902008176640000") == .int(2432902008176640000))
    }

    @Test(".String() is description; .String(.quoted) is source form (§3d, round 42)")
    func stringMethod() throws {
        #expect(try eval("(0.1 + 0.2).String()") == .string("0.30000000000000004"))
        #expect(try eval("42.String()") == .string("42"))
        #expect(try eval("nil.String()") == .string("nil"))
        #expect(try eval(#""foo".String()"#) == .string("foo"))          // identity (round 42)
        #expect(try eval(#""a\nb".String()"#) == .string("a\nb"))
        #expect(try eval(#""a\nb".String(.quoted)"#) == .string(#""a\nb""#))
        #expect(try eval("[1, 2].String()") == .string("[1, 2]"))
        #expect(try eval("[:].String()") == .string("[:]"))
        #expect(try eval(#"[1, "a"].String()"#) == .string(#"[1, "a"]"#))  // nested strings stay quoted
    }

    @Test(".Type reports the runtime type (§3; flat — never Primitives; a constructor Function since round 39)")
    func typeProperty() throws {
        #expect(try eval("42.Type == Int") == .bool(true))
        #expect(try eval("1.5.Type == Double") == .bool(true))
        #expect(try eval("nil.Type == Nil") == .bool(true))
        #expect(try eval(#""s".Type == String"#) == .bool(true))
        #expect(try eval("[1, \"one\"].Type == Array") == .bool(true))
        #expect(try eval("42.Type == Double") == .bool(false))
    }

    @Test("the round-trip law: eval(x.String()) == x (§3d)")
    func roundTripLaw() throws {
        let samples: [Value] = [
            .nil, .bool(true), .bool(false),
            .int(0), .int(-1), .int(Int64.max), .int(Int64.min + 1),
            .double(0.30000000000000004), .double(-2.5), .double(1e-300),
            .string(""), .string("café 🍰"), .string("line\nbreak \"quoted\" \\slash"),
            .array([]), .array([.int(1), .string("one"), .double(2.0), .nil]),
            .dictionary([:]),
            .dictionary([.string("k"): .array([.int(1)]), .int(2): .bool(false)]),
            .array([.dictionary([.string("nested"): .string("deep")]), .array([.nil])]),
        ]
        for x in samples {
            #expect(try eval(x.sourceString()) == x, "failed for \(x.sourceString())")
        }
    }

    @Test("comments are skipped (SION heritage, §3c)")
    func comments() throws {
        #expect(try eval("42 // the answer") == .int(42))
        #expect(try eval("/* leading */ 42 /* trailing /* nested */ */") == .int(42))
    }

    @Test("malformed input is a syntax error, not a crash")
    func syntaxErrors() throws {
        for bad in ["", "[1, 2", "[1: ]", "\"unterminated", "1 +", "@", "42..String()", "x"] {
            #expect(throws: SwiftalkError.self, "expected error for: \(bad)") {
                try eval(bad)
            }
        }
    }
}
