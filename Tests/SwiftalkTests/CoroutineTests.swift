import Testing
@testable import Swiftalk

@Suite("Coroutines and yield (§2.4, round 52)")
struct CoroutineTests {
    @Test("Sequence(f): yields are the elements, returning ends it")
    func basics() throws {
        #expect(try eval("""
            let f = { yield 1; yield 2; yield 3 }
            Sequence(f).Array()
            """) == .array([.int(1), .int(2), .int(3)]))
        // `return` *terminates* — its value is not an element
        #expect(try eval("""
            let f = { yield 1; return 99 }
            Sequence(f).Array()
            """) == .array([.int(1)]))
        // yield with no expression yields nil — nil is a value (§3a)
        #expect(try eval("Sequence({ yield; yield 2 }).Array()")
            == .array([.nil, .int(2)]))
    }

    @Test("the §2.4 marquee: infinite fib, driven lazily by .prefix")
    func fibonacci() throws {
        let fib = """
            let fib = {
                var a = 0
                var b = 1
                while true {
                    yield a
                    let t = a + b
                    a = b
                    b = t
                }
            }
            """
        #expect(try eval("\(fib)\nSequence(fib).prefix(8)")
            == .array([0, 1, 1, 2, 3, 5, 8, 13].map { .int($0) }))
        // the round-47 law's spelling: f.Sequence() == Sequence(f)
        #expect(try eval("\(fib)\nfib.Sequence().prefix(5)")
            == .array([0, 1, 1, 2, 3].map { .int($0) }))
        // lazy map/filter compose over an infinite coroutine
        #expect(try eval("\(fib)\nSequence(fib).filter { $0 / 2 * 2 == $0 }.prefix(3)")
            == .array([.int(0), .int(2), .int(8)]))
    }

    @Test("trailing-closure wrap and for-in with break over infinity")
    func forInBreak() throws {
        #expect(try eval("Sequence { yield 42 }.Array()") == .array([.int(42)]))
        #expect(try eval("""
            let nat = { var n = 0; while true { yield n; n = n + 1 } }
            var out = []
            for i in Sequence(nat) {
                if i == 5 { break }
                out.append(i)
            }
            out
            """) == .array([0, 1, 2, 3, 4].map { .int($0) }))
    }

    @Test("yield is dynamic (the Lua way): a helper yields on the body's behalf")
    func dynamicYield() throws {
        #expect(try eval("""
            let twice = { x in yield x; yield x }
            let g = { for i in 1...2 { twice(i) } }
            Sequence(g).Array()
            """) == .array([.int(1), .int(1), .int(2), .int(2)]))
    }

    @Test("coroutines nest: an outer one may drive an inner one")
    func nested() throws {
        #expect(try eval("""
            let inner = { yield 1; yield 2 }
            let outer = { for v in Sequence(inner) { yield v * 10 } }
            Sequence(outer).Array()
            """) == .array([.int(10), .int(20)]))
    }

    @Test("a Sequence value is re-iterable: each run starts the body fresh")
    func reIterable() throws {
        #expect(try eval("""
            let f = { yield 1; yield 2 }
            let s = Sequence(f)
            [s.Array(), s.Array()]
            """) == .array([.array([.int(1), .int(2)]), .array([.int(1), .int(2)])]))
    }

    @Test("it is a Sequence, nothing more: .Type and conformance")
    func typing() throws {
        #expect(try eval("Sequence({ yield 1 }).Type == Sequence") == .bool(true))
        #expect(try eval("Sequence({ yield 1 }).Type.conforms(to: Sequence)") == .bool(true))
    }

    @Test("yield outside a coroutine is an error — Lua's rule")
    func yieldOutside() throws {
        #expect(throws: SwiftalkError.self) { try eval("yield 1") }
        // an unwrapped call is a plain call: its yield has no coroutine
        #expect(throws: SwiftalkError.self) { try eval("let f = { yield 1 }\nf()") }
    }

    @Test("what Sequence(f) refuses: builtins, and declared parameters")
    func wrapGuards() throws {
        #expect(throws: SwiftalkError.self) { try eval("Sequence(print)") }
        #expect(throws: SwiftalkError.self) { try eval("let f = { x in yield x }\nSequence(f)") }
    }

    @Test("a body error surfaces at the pull; elements before it survive")
    func errorPropagation() throws {
        #expect(throws: SwiftalkError.self) {
            try eval("Sequence({ yield 1; nil! }).Array()")
        }
        #expect(try eval("Sequence({ yield 1; nil! }).prefix(1)")
            == .array([.int(1)]))
    }
}
