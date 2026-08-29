import Testing
@testable import Swiftalk

@Suite("if/else and loops — Swift-style")
struct ControlFlowTests {
    @Test("if / else if / else; Bool-only conditions")
    func ifElse() throws {
        #expect(try eval("var r = 0\nif true { r = 1 }\nr") == .int(1))
        #expect(try eval("var r = 0\nif false { r = 1 } else { r = 2 }\nr") == .int(2))
        #expect(try eval("""
            var r = ""
            let n = 5
            if n < 0 { r = "neg" } else if n == 0 { r = "zero" } else { r = "pos" }
            r
            """) == .string("pos"))
        // `else` may sit on the next line
        #expect(try eval("var r = 0\nif false { r = 1 }\nelse { r = 2 }\nr") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("if 1 { }") }
        #expect(throws: SwiftalkError.self) { try eval("if \"yes\" { }") }
    }

    @Test("blocks are child scopes")
    func scoping() throws {
        #expect(throws: SwiftalkError.self) { try eval("if true { let x = 1 }\nx") }
        #expect(try eval("var x = 1\nif true { x = 2 }\nx") == .int(2))
        #expect(try eval("let x = 1\nvar r = 0\nif true { let x = 10\nr = x }\nr + x") == .int(11))
    }

    @Test("while, repeat-while, break, continue")
    func whileLoops() throws {
        #expect(try eval("var s = 0\nvar i = 1\nwhile i <= 10 { s = s + i; i = i + 1 }\ns") == .int(55))
        #expect(try eval("var n = 0\nrepeat { n = n + 1 } while false\nn") == .int(1))
        #expect(try eval("var i = 0\nwhile true { i = i + 1\nif i == 5 { break } }\ni") == .int(5))
        #expect(try eval("""
            var s = 0
            var i = 0
            while i < 10 {
                i = i + 1
                if i / 2 * 2 == i { continue }
                s = s + i
            }
            s
            """) == .int(25))   // 1 + 3 + 5 + 7 + 9
        #expect(throws: SwiftalkError.self) { try eval("break") }
        #expect(throws: SwiftalkError.self) { try eval("let f = { break }\nvar i = 0\nwhile i < 1 { i = i + 1\nf() }") }
    }

    @Test("for-in over Array, String (graphemes), Dictionary (pairs), and _")
    func forIn() throws {
        #expect(try eval("var s = 0\nfor x in [1, 2, 3] { s = s + x }\ns") == .int(6))
        #expect(try eval("var s = \"\"\nfor c in \"ab🍰\" { s = c + s }\ns") == .string("🍰ba"))
        #expect(try eval("var s = 0\nfor pair in [\"a\": 40, \"b\": 2] { s = s + pair[1] }\ns") == .int(42))
        #expect(try eval("var n = 0\nfor _ in [1, 2, 3] { n = n + 1 }\nn") == .int(3))
        #expect(try eval("var s = 0\nfor x in [1, 2, 3, 4] { if x == 3 { break }\ns = s + x }\ns") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval("for x in 42 { }") }
        // the loop variable is a let
        #expect(throws: SwiftalkError.self) { try eval("for x in [1] { x = 2 }") }
    }

    @Test("ranges: ... and ..< as first-class lazy Range values (round 38)")
    func ranges() throws {
        #expect(try eval("(1...5).Array() == [1, 2, 3, 4, 5]") == .bool(true))
        #expect(try eval("(1..<5).Array() == [1, 2, 3, 4]") == .bool(true))
        #expect(try eval("(3..<3).count") == .int(0))
        #expect(try eval("(1...5).count") == .int(5))
        #expect(try eval("(1...3)[0]") == .int(1))
        #expect(throws: SwiftalkError.self) { try eval("3...1") }
        #expect(throws: SwiftalkError.self) { try eval("1.5...3") }
        // range binds looser than additive: 1...2+2 is 1...4
        #expect(try eval("(1...2 + 2).count") == .int(4))
    }

    @Test("the iterative factorial: for + range (§13's loop idiom)")
    func iterativeFactorial() throws {
        #expect(try eval("var f = 1\nfor i in 1...20 { f = f * i }\nf")
            == .int(2432902008176640000))
        #expect(throws: SwiftalkError.self) {
            try eval("var f = 1\nfor i in 1...21 { f = f * i }")   // 21! still traps
        }
    }

    @Test("control flow inside functions")
    func inFunctions() throws {
        #expect(try eval("""
            let sum = {
                var s = 0
                for x in $ { s = s + x }
                s
            }
            sum(1, 2, 3, 4)
            """) == .int(10))
        #expect(try eval("""
            let fizzbuzzish = { n in
                var count = 0
                for i in 1...n {
                    if i / 3 * 3 == i { count = count + 1 }
                }
                count
            }
            fizzbuzzish(10)
            """) == .int(3))
    }
}
