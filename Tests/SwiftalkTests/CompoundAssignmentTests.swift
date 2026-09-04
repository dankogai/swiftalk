import Testing
@testable import Swiftalk

@Suite("+= -= *= /= %= — compound assignment (round 102)")
struct CompoundAssignmentTests {
    @Test("the five, on Ints and Doubles; += on Strings and Arrays; the value is the value written")
    func basics() throws {
        #expect(try eval("var n = 10\nn += 5\nn -= 3\nn *= 2\nn /= 5\nn %= 3\nn") == .int(1))
        #expect(try eval("var f = 1.5\nf *= 2.0\nf /= 4.0\nf") == .double(0.75))
        #expect(try eval("var s = \"ab\"\ns += \"c\"\ns") == .string("abc"))
        #expect(try eval("var a = [1, 2]\na += [3]\na") == .array([1, 2, 3].map { .int($0) }))
        #expect(try eval("var n = 1\nn += 1") == .int(2))                          // its value, as an assignment's
        #expect(throws: SwiftalkError.self) { try eval("var n = 1\nlet r = n += 1") }   // a statement, not an expression (as Swift)
    }

    @Test("through paths: subscripts, nested subscripts, struct properties — the target evaluated once")
    func paths() throws {
        #expect(try eval("var a = [1, 2]\na[0] += 10\na") == .array([.int(11), .int(2)]))
        #expect(try eval("var d = [\"k\": 1]\nd[\"k\"] *= 7\nd[\"k\"]") == .int(7))
        #expect(try eval("var m = [[1], [2]]\nm[1][0] -= 5\nm") == .array([.array([.int(1)]), .array([.int(-3)])]))
        #expect(try eval("struct P { var x: Int }\nvar p = P(x: 2)\np.x *= 21\np.x") == .int(42))
        #expect(try eval("""
            var calls = 0
            let idx = { calls += 1; return 0 }
            var a = [1]
            a[idx()] += 100
            [a[0], calls]
            """) == .array([.int(101), .int(1)]))
    }

    @Test("the operator's own answers: type lock, / 0, overflow, % on Doubles; a let refuses; no implicit declaration")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("let k = 1\nk += 1") }
        #expect(throws: SwiftalkError.self) { try eval("var n = 1\nn += \"x\"") }
        #expect(throws: SwiftalkError.self) { try eval("var n = 1\nn /= 0") }
        #expect(throws: SwiftalkError.self) { try eval("var n = 9223372036854775807\nn += 1") }
        #expect(throws: SwiftalkError.self) { try eval("var x = 1.5\nx %= 1.0") }
        #expect(throws: SwiftalkError.self) { try eval("var (a, b) = (1, 2)\n(a, b) += (1, 1)") }
        #expect(throws: SwiftalkError.self) { try eval("z += 1") }
        let repl = Swiftalk.Interpreter(relaxed: true)
        #expect(throws: SwiftalkError.self) { try repl.eval("z += 1") }          // no implicit var through op=
        #expect(try repl.eval("var y = 1\ny +=\n2\ny") == .int(3))               // a trailing op= continues
    }

    @Test("/= is not a regex: after an operand, / is division")
    func slash() throws {
        #expect(try eval("var q = 9\nq /= 2\nq") == .int(4))
        #expect(try eval("var q = 9.0\nq /= 2.0\nq") == .double(4.5))
    }
}
