import Testing
@testable import Swiftalk

@Suite("logical operators: && || and prefix !, Swift's semantics (round 69)")
struct LogicalTests {
    @Test("truth tables")
    func truthTables() throws {
        #expect(try eval("true && true") == .bool(true))
        #expect(try eval("true && false") == .bool(false))
        #expect(try eval("false || true") == .bool(true))
        #expect(try eval("false || false") == .bool(false))
        #expect(try eval("!true") == .bool(false))
        #expect(try eval("!false") == .bool(true))
        #expect(try eval("!!true") == .bool(true))
    }

    @Test("short-circuit: the right side runs only when it must")
    func shortCircuit() throws {
        #expect(try eval("var hit = false\nlet probe = { hit = true\nreturn true }\nlet r = false && probe()\n[r, hit]")
            == .array([.bool(false), .bool(false)]))
        #expect(try eval("var hit = false\nlet probe = { hit = true\nreturn true }\nlet r = true || probe()\n[r, hit]")
            == .array([.bool(true), .bool(false)]))
        #expect(try eval("var hit = false\nlet probe = { hit = true\nreturn false }\nlet r = true && probe()\n[r, hit]")
            == .array([.bool(false), .bool(true)]))
        // the classic guard: a nil check protecting a dereference
        #expect(try eval("let d = [:]\nd[\"k\"] != nil && d[\"k\"]! > 0") == .bool(false))
    }

    @Test("nothing is truthy: non-Bool operands are type errors, even unreached ones' kin")
    func boolOnly() throws {
        #expect(throws: SwiftalkError.self) { try eval("1 && true") }
        #expect(throws: SwiftalkError.self) { try eval("nil || true") }
        #expect(throws: SwiftalkError.self) { try eval("true && 1") }
        #expect(throws: SwiftalkError.self) { try eval("!0") }
        #expect(throws: SwiftalkError.self) { try eval("!nil") }
    }

    @Test("precedence, Swift's: ! > comparison > && > || > ternary; ?? above comparison")
    func precedence() throws {
        #expect(try eval("true || false && false") == .bool(true))      // || (&&)
        #expect(try eval("!true && false || true") == .bool(true))       // ((!t) && f) || t
        #expect(try eval("1 < 2 && 2 < 3") == .bool(true))              // comparison binds tighter
        #expect(try eval("!true == false") == .bool(true))               // (!true) == false
        #expect(try eval("true && false ? 1 : 2") == .int(2))           // ternary lowest
        #expect(try eval("nil ?? false || true") == .bool(true))         // (nil ?? false) || true
        #expect(try eval("let a = true\n!a || a") == .bool(true))
    }

    @Test("prefix ! and postfix ! coexist: position tells them apart")
    func prefixVersusPostfix() throws {
        #expect(try eval("let d = [\"k\": true]\n!d[\"k\"]!") == .bool(false))
        #expect(try eval("let x: Bool? = false\n!(x == nil)") == .bool(true))
    }

    @Test("a lone & or | is a syntax error, not a bitwise operator")
    func loneBars() throws {
        #expect(throws: SwiftalkError.self) { try eval("1 & 2") }
        #expect(throws: SwiftalkError.self) { try eval("true | false") }
    }

    @Test("in conditions, where they live")
    func inConditions() throws {
        #expect(try eval("""
            var out = []
            for i in 1...10 {
                if i / 2 * 2 == i && i / 3 * 3 == i || i == 1 { out.append(i) }
            }
            out
            """) == .array([.int(1), .int(6)]))
        #expect(try eval("var n = 0\nwhile n < 10 && !(n == 5) { n = n + 1 }\nn") == .int(5))
    }
}
