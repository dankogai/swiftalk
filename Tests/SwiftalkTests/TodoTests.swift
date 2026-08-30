import Testing
@testable import Swiftalk

@Suite(".todo: deferred initialization and named recursion (round 44)")
struct TodoTests {
    @Test("the marquee: named recursion via let ... = .todo, assigned once")
    func namedRecursion() throws {
        #expect(try eval("""
            let fact: Function = .todo
            fact = { n in n < 2 ? n : n * fact(n - 1) }
            fact(20)
            """) == .int(2432902008176640000))
    }

    @Test("a let holding .todo accepts exactly one assignment")
    func onceOnly() throws {
        #expect(throws: SwiftalkError.self) {
            try eval("""
                let f: Function = .todo
                f = { 1 }
                f = { 2 }
                """)
        }
        // ordinary lets are unaffected — no free assignment slot
        #expect(throws: SwiftalkError.self) { try eval("let f = { 1 }\nf = { 2 }") }
    }

    @Test("var with .todo overwrites as many times as you want")
    func varOverwrites() throws {
        #expect(try eval("""
            var f: Function = .todo
            f = { 1 }
            f = { 2 }
            f()
            """) == .int(2))
    }

    @Test("calling a .todo before initialization is an error; it displays as .todo")
    func uninitialized() throws {
        #expect(throws: SwiftalkError.self) { try eval("let f: Function = .todo\nf()") }
        #expect(try eval("let f: Function = .todo\nf.String()") == .string(".todo"))
        #expect(try eval("let f: Function = .todo\nf.Type == Function") == .bool(true))
        #expect(try eval("let f: Function = .todo\nf.name") == .nil)
    }

    @Test("mutual recursion — the payoff $() alone could never give")
    func mutualRecursion() throws {
        #expect(try eval("""
            let isEven: Function = .todo
            let isOdd: Function = .todo
            isEven = { n in n == 0 ? true : isOdd(n - 1) }
            isOdd = { n in n == 0 ? false : isEven(n - 1) }
            [isEven(10), isOdd(10), isEven(7)]
            """) == .array([.bool(true), .bool(false), .bool(false)]))
    }

    @Test("bare `let f = .todo` infers Function")
    func inference() throws {
        #expect(try eval("let f = .todo\nf = { 42 }\nf()") == .int(42))
        #expect(try eval("var g = .todo\ng.Type == Function") == .bool(true))
    }
}
