import Testing
@testable import Swiftalk

@Suite("Regex: a core type with a literal (round 86)")
struct RegexTests {
    @Test("the literal, the constructor, flags, equality, and the source form round-trips")
    func literal() throws {
        #expect(try eval("/\\d+/.Type == Regex") == .bool(true))
        #expect(try eval("/\\d+/.pattern") == .string("\\d+"))
        #expect(try eval("/abc/xi.flags") == .string("ix"))              // sorted
        #expect(try eval("Regex(\"\\\\d+\") == /\\d+/") == .bool(true))
        #expect(try eval("Regex(\"a\", \"i\") == /a/i") == .bool(true))
        #expect(try eval("\"a\".Regex(\"i\") == /a/i") == .bool(true))   // the round-47 law
        #expect(try eval("/a/i == /a/") == .bool(false))
        #expect(try eval("/a\\/b/.pattern") == .string("a/b"))           // \\/ is a / in the pattern
        #expect(try eval("/a\\/b/.String()") == .string("/a\\/b/"))
        guard case .string(let src) = try eval("/a\\/b/.String()") else { throw SwiftalkError.type("expected string") }
        #expect(try eval(src) == eval("/a\\/b/"))                          // the round-trip law
        #expect(try eval("let d = [/a/: 1]\nd[/a/]") == .int(1))         // Hashable
        #expect(throws: SwiftalkError.self) { try eval("/(/") }            // a bad pattern is a syntax error
        #expect(throws: SwiftalkError.self) { try eval("/a/q") }
        #expect(throws: SwiftalkError.self) { try eval("Regex()") }
        #expect(throws: SwiftalkError.self) { try eval("Regex(1)") }
    }

    @Test("/ is division after an operand, a regex elsewhere — JavaScript's rule")
    func slashRule() throws {
        #expect(try eval("10 / 2") == .int(5))
        #expect(try eval("let x = 10\nx / 2 / 5") == .int(1))
        #expect(try eval("let x = 10\n(x) / 2") == .int(5))
        #expect(try eval("let x = 10\n[x][0] / 2") == .int(5))
        #expect(try eval("let r = /a/\nr.pattern") == .string("a"))
        #expect(try eval("[/a/, /b/].count") == .int(2))
        #expect(try eval("let f = { return /x/ }\nf().pattern") == .string("x"))
        #expect(try eval("\"x\".contains(/x/) ? /y/ : /z/") == .regex(try RegexObject(pattern: "y", flags: "")))
    }

    @Test("contains, firstMatch, wholeMatch, matches — Swift's names, of: accepted")
    func searching() throws {
        #expect(try eval("\"hello 42 world 7\".contains(/\\d+/)") == .bool(true))
        #expect(try eval("\"hello\".contains(/\\d+/)") == .bool(false))
        #expect(try eval("\"hello 42 world 7\".firstMatch(/\\d+/)") == .string("42"))
        #expect(try eval("\"hello 42\".firstMatch(of: /\\d+/)") == .string("42"))
        #expect(try eval("\"hello\".firstMatch(/\\d+/)") == .nil)
        #expect(try eval("\"hello 42 world 7\".matches(/\\d+/)") == .array([.string("42"), .string("7")]))
        #expect(try eval("\"hello 42 world 7\".wholeMatch(/\\d+/)") == .nil)
        #expect(try eval("\"42\".wholeMatch(/\\d+/)") == .string("42"))
    }

    @Test("captures come as a tuple: .0 the whole match, then the groups, named ones labeled, nil when absent")
    func captures() throws {
        #expect(try eval("\"2026-09-03\".firstMatch(/(\\d+)-(\\d+)-(\\d+)/)")
                == .tuple(["2026-09-03", "2026", "09", "03"].map(Value.string)))
        #expect(try eval("\"2026-09-03\".firstMatch(/(?<year>\\d+)-(?<month>\\d+)/).year") == .string("2026"))
        #expect(try eval("\"2026-09-03\".firstMatch(/(?<year>\\d+)-(?<month>\\d+)/).month") == .string("09"))
        #expect(try eval("\"ab\".firstMatch(/a(x)?b/)") == .tuple([.string("ab"), .nil]))
        // destructuring: positional, and labeled (arity rigid — the whole match is .0)
        #expect(try eval("""
            var r = ""
            if let (_, y, m, d) = "2026-09-03".firstMatch(/(\\d+)-(\\d+)-(\\d+)/) { r = d + m + y }
            r
            """) == .string("03092026"))
        #expect(try eval("""
            var r = ""
            if (_, year: y, month: m) = "2026-09-03".firstMatch(/(?<year>\\d+)-(?<month>\\d+)/) { r = m + y }
            r
            """) == .string("092026"))
        #expect(try eval("""
            var out = []
            for m in "x=1, y=22".matches(/(\\w)=(\\d+)/) { out.append(m.1 + m.2) }
            out
            """) == .array([.string("x1"), .string("y22")]))
    }

    @Test("flags: i, m, s, x")
    func flags() throws {
        #expect(try eval("\"Hello\".contains(/hello/i)") == .bool(true))
        #expect(try eval("\"Hello\".contains(/hello/)") == .bool(false))
        #expect(try eval("\"a\\nb\".contains(/a.b/s)") == .bool(true))
        #expect(try eval("\"a\\nb\".contains(/a.b/)") == .bool(false))
        #expect(try eval("\"a\\nb\".contains(/^b/m)") == .bool(true))
        #expect(try eval("\"abc\".contains(/a b c/x)") == .bool(true))
    }

    @Test("replacing and split — Swift's replacing(_:with:) and split(separator:), with a Regex or a String")
    func replacingAndSplit() throws {
        #expect(try eval("\"a1b22c\".replacing(/\\d+/, \"#\")") == .string("a#b#c"))
        #expect(try eval("\"a1b22c\".replacing(/\\d+/, with: \"#\")") == .string("a#b#c"))
        #expect(try eval("\"a1b22c\".replacing(\"b\", \"B\")") == .string("a1B22c"))
        // a Function of the match: a bare String without captures...
        #expect(try eval("\"a1b22c\".replacing(/\\d+/) { m in \"<\" + m + \">\" }") == .string("a<1>b<22>c"))
        // ...and a tuple with them — which splats, as any tuple argument does (round 73)
        #expect(try eval("\"a1b22c\".replacing(/(\\d)(\\d)?/) { _, first, _ in first + \"!\" }") == .string("a1!b2!c"))
        #expect(try eval("\"a1b22c\".replacing(/(\\d)(\\d)?/) { $1 + \"!\" }") == .string("a1!b2!c"))
        #expect(try eval("\"a, b,,c\".split(/,\\s*/)") == .array(["a", "b", "c"].map(Value.string)))
        #expect(try eval("\"a b  c\".split(\" \")") == .array(["a", "b", "c"].map(Value.string)))
        #expect(try eval("\"a b  c\".split(separator: /\\s+/)") == .array(["a", "b", "c"].map(Value.string)))
        #expect(throws: SwiftalkError.self) { try eval("\"x\".firstMatch(\"y\")") }
        #expect(throws: SwiftalkError.self) { try eval("\"x\".split(1)") }
        #expect(throws: SwiftalkError.self) { try eval("42.firstMatch(/x/)") }
        #expect(throws: SwiftalkError.self) { try eval("\"a1\".replacing(/\\d/) { 1 }") }
    }

    @Test("a character is a grapheme: . and \\X take one cluster; scalar ranges match single-scalar graphemes only (round 87)")
    func graphemes() throws {
        let s = "let s = \"e\\u{301}🇯🇵a\"\n"                      // 5 scalars, 3 graphemes
        #expect(try eval(s + "s.count") == .int(3))
        #expect(try eval(s + "s.matches(/./)") == .array(["é", "🇯🇵", "a"].map(Value.string)))
        #expect(try eval(s + "s.matches(/\\X/)") == .array(["é", "🇯🇵", "a"].map(Value.string)))
        #expect(try eval("\"👨‍👩‍👧\".matches(/./).count") == .int(1))
        // canonical equivalence, not scalar identity
        #expect(try eval("\"e\\u{301}\".contains(/^é$/)") == .bool(true))
        #expect(try eval("\"e\\u{301}\".contains(/^e$/)") == .bool(false))
        #expect(try eval("\"e\\u{301}\".matches(/[\\u{E9}]/)") == .array([.string("é")]))
        #expect(try eval("\"e\\u{301}\".matches(/[a-z]/)") == .array([]))
        // a scalar range matches a grapheme only when the grapheme is one scalar in it
        #expect(try eval("\"ひらがな and カタカナ\".matches(/[\\u{3040}-\\u{309F}]+/)") == .array([.string("ひらがな")]))
        #expect(try eval("\"か\\u{309A}き\".matches(/[\\u{3040}-\\u{309F}]/)") == .array([.string("き")]))
        #expect(try eval("\"🇯🇵🇺🇸\".matches(/[\\u{1F1E6}-\\u{1F1FF}]/)") == .array([]))
        // ...the property classes match whole graphemes
        #expect(try eval("\"か\\u{309A}き\".matches(/\\p{Hiragana}+/)") == .array([.string("か\u{309A}き")]))
        #expect(try eval("\"🇯🇵🇺🇸\".matches(/\\p{RegionalIndicator}/)") == .array([.string("🇯🇵"), .string("🇺🇸")]))
        #expect(try eval("\"漢字\".matches(/\\p{Han}+/)") == .array([.string("漢字")]))
        #expect(try eval("\"か\\u{309A}\".matches(/[か\\u{309A}]/)") == .array([.string("か\u{309A}")]))
        // no scalar mode: the stdlib rejects both inline switches
        #expect(throws: SwiftalkError.self) { try eval("/(?u)./") }
        #expect(throws: SwiftalkError.self) { try eval("/(?X)./") }
    }

    @Test("switch: case /re/: matches the whole String; case let (_, a, b) = /re/: binds the captures")
    func switchPatterns() throws {
        #expect(try eval("""
            let classify = { s in
                switch s {
                case /\\d+/:                          "number"
                case /[a-z]+/i:                       "word"
                case let (_, u, v) = /(\\w+)@(\\w+)/:   "mail \\(u) at \\(v)"
                default:                             "other"
                }
            }
            [classify("42"), classify("Hi"), classify("dan@example"), classify("?!"), classify("42x")]
            """) == .array(["number", "word", "mail dan at example", "other", "other"].map(Value.string)))
        #expect(try eval("switch \"ab\" { case m = /a(b)?/ where m.1 != nil: \"with b\" default: \"no\" }")
                == .string("with b"))
        // a Regex against a non-String is simply no match; a Regex binding needs a String subject
        #expect(try eval("switch 42 { case /x/: 1 default: 2 }") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("switch 42 { case let m = /x/: 1 default: 2 }") }
        #expect(throws: SwiftalkError.self) { try eval("switch \"a\" { case let m = 1: 1 default: 2 }") }
    }
}
