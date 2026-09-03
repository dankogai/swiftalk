import Testing
@testable import Swiftalk

@Suite("for x in s where cond ≡ for x in s.filter({ }) (round 82)")
struct ForWhereTests {
    @Test("Array and Range: the same elements as filter, in the same order")
    func arrayAndRange() throws {
        #expect(try eval("""
            var a = []
            for x in 1...10 where x / 2 * 2 == x { a.append(x) }
            var b = []
            for x in (1...10).filter({ $0 / 2 * 2 == $0 }) { b.append(x) }
            [a == b, a]
            """) == .array([.bool(true), .array([.int(2), .int(4), .int(6), .int(8), .int(10)])]))
        #expect(try eval("""
            var a = []
            for s in ["ant", "bee", "cat"] where s.count == 3 && s != "bee" { a.append(s) }
            a
            """) == .array([.string("ant"), .string("cat")]))
    }

    @Test("Dictionary: for k, v in d where v > 1 ≡ d.filter({ k, v in v > 1 }) — the same pairs (order is a Dictionary's own)")
    func dictionary() throws {
        #expect(try eval("""
            let d = ["a": 1, "b": 2, "c": 3]
            var kept = [:]
            for k, v in d where v > 1 { kept[k] = v }
            [kept == d.filter({ k, v in v > 1 }), kept.count]
            """) == .array([.bool(true), .int(2)]))
    }

    @Test("String graphemes; tuple patterns; the condition sees every loop name")
    func stringAndPatterns() throws {
        #expect(try eval("var s = \"\"\nfor c in \"hello\" where c != \"l\" { s = s + c }\ns") == .string("heo"))
        #expect(try eval("""
            var a = []
            for (x, y) in [(1, 2), (3, 4), (0, 0)] where x + y > 3 { a.append(x * y) }
            a
            """) == .array([.int(12)]))
    }

    @Test("lazy: an infinite coroutine Sequence is filtered element by element; break and continue still work")
    func lazy() throws {
        #expect(try eval("""
            let naturals = Sequence { var n = 0; while true { n = n + 1; yield n } }
            var a = []
            for n in naturals where n / 3 * 3 == n {
                if n > 10 { break }
                if n == 6 { continue }
                a.append(n)
            }
            a
            """) == .array([.int(3), .int(9)]))
    }

    @Test("a where clause must be a Bool; where stays an identifier elsewhere")
    func rules() throws {
        #expect(throws: SwiftalkError.self) { try eval("for x in [1, 2] where x { }") }
        #expect(try eval("let where = \"id\"\nvar r = \"\"\nfor w in [where] { r = w }\nr") == .string("id"))
    }
}
