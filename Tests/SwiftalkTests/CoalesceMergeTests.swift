import Testing
@testable import Swiftalk

@Suite("?? and !! — on Dictionaries per key; !! is the mirror, b ?? a (round 130)")
struct CoalesceMergeTests {
    let d = "let d0 = [\"a\": 1, \"b\": 2]\nlet d1 = [\"b\": 20, \"c\": 30]\n"

    @Test("d0 ?? d1 keeps d0's values and fills from d1; d0 !! d1 is d1 ?? d0")
    func dictionaries() throws {
        #expect(try eval(d + "d0 ?? d1") == .dictionary([.string("a"): .int(1), .string("b"): .int(2), .string("c"): .int(30)]))
        #expect(try eval(d + "d0 !! d1") == .dictionary([.string("a"): .int(1), .string("b"): .int(20), .string("c"): .int(30)]))
        #expect(try eval(d + "(d0 !! d1) == (d1 ?? d0)") == .bool(true))
        #expect(try eval(d + "(d1 !! d0) == (d0 ?? d1)") == .bool(true))
        #expect(try eval(d + "(d0 ?? d1) == d0.merging(d1) { $0 }") == .bool(true))
        #expect(try eval(d + "(d0 !! d1) == d0.merging(d1) { $1 }") == .bool(true))
        #expect(try eval(d + "[d0, d1] == [d0, d1]") == .bool(true))                              // operands untouched
        #expect(try eval("[\"k\": nil] ?? [\"k\": 1]") == .dictionary([.string("k"): .int(1)]))       // a stored nil is absent
        #expect(try eval("[\"k\": 1] !! [\"k\": nil]") == .dictionary([.string("k"): .int(1)]))       // nil does not override
        #expect(try eval("[:] ?? [\"a\": 1]") == .dictionary([.string("a"): .int(1)]))
        #expect(try eval("[\"a\": 1] ?? [:]") == .dictionary([.string("a"): .int(1)]))
        #expect(try eval("[\"a\": 1] ?? [\"b\": 2] ?? [\"c\": 3]") == .dictionary([.string("a"): .int(1), .string("b"): .int(2), .string("c"): .int(3)]))
        #expect(try eval("[\"a\": 1] !! [\"a\": 2] !! [\"a\": 3]") == .dictionary([.string("a"): .int(3)]))
        #expect(try eval("var n = 0\nlet r = [\"a\": 1] ?? { n = n + 1; return [:] }()\nn") == .int(1))   // the right side runs
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1] ?? 1") }
        #expect(try eval("[\"a\": 1] !! [1]") == .array([.int(1)]))                        // [1] ?? d: the Array provides
        #expect(throws: SwiftalkError.self) { try eval("[1] !! [\"a\": 1]") }              // d ?? [1]: a Dictionary coalesces with a Dictionary
    }

    @Test("??= fills in place, !!= overrides in place; a var path; the lock holds")
    func assignment() throws {
        #expect(try eval("var d = [\"a\": 1]\nd ??= [\"a\": 9, \"b\": 2]\nd") == .dictionary([.string("a"): .int(1), .string("b"): .int(2)]))
        #expect(try eval("var d = [\"a\": 1]\nd !!= [\"a\": 9, \"b\": 2]\nd") == .dictionary([.string("a"): .int(9), .string("b"): .int(2)]))
        #expect(try eval("var d = [\"a\": 1]\nd !!= [\"a\": nil]\nd") == .dictionary([.string("a"): .int(1)]))
        #expect(try eval("var s = (d: [\"a\": 1], n: 0)\ns.d ??= [\"b\": 2]\ns.d.count") == .int(2))
        #expect(try eval("var s = (d: [\"a\": 1], n: 0)\ns.d !!= [\"a\": 5]\ns.d[\"a\"]") == .int(5))
        #expect(throws: SwiftalkError.self) { try eval("let d = [\"a\": 1]\nd ??= [\"b\": 2]") }
        #expect(throws: SwiftalkError.self) { try eval("let d = [\"a\": 1]\nd !!= [\"b\": 2]") }
        #expect(throws: SwiftalkError.self) { try eval("var d: [String: Int] = [\"a\": 1]\nd !!= [\"b\": \"x\"]") }
        #expect(throws: SwiftalkError.self) { try eval("var d = [\"a\": 1]\nd ??= 1") }
        #expect(throws: SwiftalkError.self) { try eval("var d = [\"a\": 1]\nd !!= 1") }        // 1 ?? d is 1 — and the lock refuses it
        #expect(try eval("var d: Any = [\"a\": 1]\nd !!= 1\nd") == .int(1))
    }

    @Test("on anything else, a !! b is b ?? a: the right side's value when it has one")
    func scalars() throws {
        #expect(try eval("1 !! 2") == .int(2))
        #expect(try eval("1 !! nil") == .int(1))
        #expect(try eval("nil !! 2") == .int(2))
        #expect(try eval("nil !! nil") == .nil)
        #expect(try eval("let x: Int? = nil\nlet y: Int? = 7\n(x !! y) == (y ?? x)") == .bool(true))
        #expect(try eval("var x = 1\nx !!= nil\nx") == .int(1))
        #expect(try eval("var x = 1\nx !!= 5\nx") == .int(5))
        #expect(try eval("var x: Int? = nil\nx !!= 5\nx") == .int(5))
        #expect(try eval("(Result.success(1) !! Result.failure(\"e\")) == Result.success(1)") == .bool(true))   // a failure does not override
        #expect(try eval("(Result.success(1) !! 2) == 2") == .bool(true))
    }

    @Test("lexing: infix only after an operand with whitespace before — x!! and !!b are still the unary forms")
    func lexing() throws {
        #expect(try eval("let x: Int? = 3\nx!! == 3") == .bool(true))             // hmm: x!! is two force-unwraps
        #expect(try eval("!!true") == .bool(true))
        #expect(try eval("let b = false\n!!b") == .bool(false))
        #expect(try eval("let a = 1\nlet b = 2\na !! b") == .int(2))
        #expect(try eval("let a = 1\nlet b = 2\na !!b") == .int(2))
        #expect(try eval("[1] !! [2]") == .array([.int(2)]))                        // Arrays are values, not Dictionaries: b ?? a
        #expect(try eval("let d = [\"a\": 1]\nd !!\n[\"b\": 2]") == .dictionary([.string("a"): .int(1), .string("b"): .int(2)]))   // continues the line
        #expect(try eval("1 !== 1.0") == .bool(true))                                // !== is untouched
        #expect(try eval("1 != 2") == .bool(true))
    }
}
