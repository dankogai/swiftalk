import Testing
@testable import Swiftalk

/// Round 155: `not`, `and`, `or`, `xor` — Perl's word operators, the same
/// operations as `!`, `&&`, `||`, `^^`, at the bottom of the precedence
/// table (not > and > or = xor), all below the ternary.
@Suite("not / and / or / xor — the word operators (round 155)")
struct WordOperatorTests {
    @Test("the same operations as ! && || ^^: Bools only, short-circuit where the symbols do")
    func semantics() throws {
        #expect(try eval("not true") == .bool(false))
        #expect(try eval("not not true") == .bool(true))
        #expect(try eval("true and false") == .bool(false))
        #expect(try eval("true or false") == .bool(true))
        #expect(try eval("true xor true") == .bool(false))
        #expect(try eval("true xor false") == .bool(true))
        #expect(try eval("var n = 0\nlet probe = { n += 1; return true }\nlet a = false and probe()\nlet b = true or probe()\nlet c = false or probe()\nn") == .int(1))
        #expect(try eval("var m = 0\nlet probe = { m += 1; return true }\nlet a = true xor probe()\nm") == .int(1))   // xor evaluates both
        #expect(throws: SwiftalkError.self) { try eval("1 and 2") }
        #expect(throws: SwiftalkError.self) { try eval("not 1") }
        #expect(throws: SwiftalkError.self) { try eval("false or 0") }
        #expect(try eval("true or 0") == .bool(true))                        // short-circuit: the 0 is never seen
    }

    @Test("precedence: not binds below the ternary, and below not, or/xor loosest; left-associative")
    func precedence() throws {
        #expect(try eval("not 1 == 2") == .bool(true))                       // not (1 == 2)
        #expect(try eval("true or false and false") == .bool(true))          // true or (false and false)
        #expect(try eval("false and false or true") == .bool(true))          // (false and false) or true
        #expect(try eval("true xor true or true") == .bool(true))            // (true xor true) or true — same level, left to right
        #expect(try eval("true or true xor true") == .bool(false))           // (true or true) xor true
        #expect(try eval("not true and false") == .bool(false))              // (not true) and false
        #expect(try eval("not false or false") == .bool(true))               // (not false) or false
        #expect(try eval("true && false or true") == .bool(true))            // (true && false) or true — the symbols bind tighter
        #expect(try eval("nil ?? true and false") == .bool(false))           // (nil ?? true) and false
        #expect(try eval("true ? false : true or true") == .bool(true))      // (true ? false : true) or true — Perl's reading
        #expect(try eval("true ? false or true : false") == .bool(true))     // the middle may hold anything
        #expect(try eval("(not true) ? 1 : 2") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("not true ? 1 : 2") }  // not (true ? 1 : 2) — an Int negated
    }

    @Test("in conditions, where clauses, closures; across a line break; as method names still")
    func contexts() throws {
        #expect(try eval("let x = 3\nif not x == 4 and x > 0 { \"yes\" } else { \"no\" }") == .string("yes"))
        #expect(try eval("let x = 3\nif x > 2 and x < 4, x != 0 { \"both\" }") == .string("both"))
        #expect(try eval("[1, 2, 3, 4].filter { $0 > 1 and $0 < 4 }") == .array([.int(2), .int(3)]))
        #expect(try eval("var out = []\nfor i in 1...6 where i % 2 == 0 or i == 5 { out.append(i) }\nout") == .array([.int(2), .int(4), .int(5), .int(6)]))
        #expect(try eval("let x = 3\nswitch x { case 1...5 where x > 2 and x < 4: \"three\" default: \"other\" }") == .string("three"))
        #expect(try eval("let f = { a, b in a and not b }\nf(true, false)") == .bool(true))
        #expect(try eval("[true, false].map { not $0 }") == .array([.bool(false), .bool(true)]))
        #expect(try eval("let x = 3\nx > 2 and\n  x < 4") == .bool(true))           // a trailing word continues the line
        #expect(try eval("let x = 3\nx > 2\n  and x < 4") == .bool(true))           // a leading one with a space after it too
        #expect(try eval("let y = true\nnot y\n42") == .int(42))                    // `not` leading a line is a new statement
        #expect(try eval("var b = true\nb &&= false or true\nb") == .bool(true))    // no and=; the op= family is the symbols'
        #expect(try eval("true.and(false) == false && false.or(true) && true.xor(false) && false.not()") == .bool(true))   // round 106's methods keep their names
        #expect(throws: SwiftalkError.self) { try eval("let and = 1") }             // keywords now
        #expect(throws: SwiftalkError.self) { try eval("let not = 1") }
    }
}
