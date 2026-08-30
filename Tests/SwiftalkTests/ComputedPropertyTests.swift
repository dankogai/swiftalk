import Testing
@testable import Swiftalk

@Suite("computed properties: the paren-less last quarter (round 57)")
struct ComputedPropertyTests {
    @Test("a bare block is the getter — read without parens, at last")
    func getterOnly() throws {
        #expect(try eval("""
            struct Circle {
                var r = 2.0
                var area { 3.141592653589793 * .r * .r }
            }
            Circle().area
            """) == .double(12.566370614359172))
        // reads run code every time — not a snapshot
        #expect(try eval("""
            struct P { var x = 1
            var loud { .x * 100 } }
            var p = P()
            let before = p.loud
            p.x = 3
            [before, p.loud]
            """) == .array([.int(100), .int(300)]))
    }

    @Test("get/set blocks: assignment runs code, value semantics hold")
    func getSet() throws {
        #expect(try eval("""
            struct Temp {
                var celsius = 0.0
                var fahrenheit {
                    get { .celsius * 1.8 + 32.0 }
                    set { .celsius = (newValue - 32.0) / 1.8 }
                }
            }
            var t = Temp()
            t.fahrenheit = 212.0
            t.celsius
            """) == .double(100.0))
        // set(v) names the incoming value
        #expect(try eval("""
            struct Box { var v = 0
            var twice { get { .v * 2 } set(w) { .v = w / 2 } } }
            var b = Box()
            b.twice = 42
            [b.v, b.twice]
            """) == .array([.int(21), .int(42)]))
        // a struct is still a value: the setter writes back COW-style
        #expect(try eval("""
            struct Box { var v = 0
            var twice { get { .v * 2 } set { .v = newValue / 2 } } }
            var a = Box()
            let b = a
            a.twice = 10
            [a.v, b.v]
            """) == .array([.int(5), .int(0)]))
    }

    @Test("guards: read-only write, let-declared, annotation checks")
    func guards() throws {
        #expect(throws: SwiftalkError.self) {
            try eval("struct S { var x = 1\nvar y { .x } }\nvar s = S()\ns.y = 2")
        }
        #expect(throws: SwiftalkError.self) {
            try eval("struct S { let y { 1 } }")
        }
        // an annotated computed property checks what the setter is fed
        #expect(throws: SwiftalkError.self) {
            try eval("""
                struct S { var x = 1
                var y: Int { get { .x } set { .x = newValue } } }
                var s = S()
                s.y = "nope"
                """)
        }
    }

    @Test("classes: computed with inheritance and super in the getter")
    func classes() throws {
        #expect(try eval("""
            class Counter { var n = 10
            var doubled { .n * 2 } }
            let c = Counter()
            c.doubled
            """) == .int(20))
        // inherited computed reaches subclasses; override reaches super's
        #expect(try eval("""
            class A { var x = 3
            var sq { .x * .x } }
            class B: A { var sq { super.sq * 10 } }
            [A().sq, B().sq]
            """) == .array([.int(9), .int(90)]))
    }

    @Test("actors: getter/setter are the actor's own code — serialized, and allowed from outside")
    func actors() throws {
        #expect(try eval("""
            actor Bank {
                var balance = 100
                var dollars { get { .balance } set { .balance = newValue } }
            }
            let b = Bank()
            b.dollars = 250
            b.dollars
            """) == .int(250))
        // ...while direct storage writes stay isolated (round 54)
        #expect(throws: SwiftalkError.self) {
            try eval("""
                actor Bank { var balance = 100
                var dollars { get { .balance } set { .balance = newValue } } }
                let b = Bank()
                b.balance = 1
                """)
        }
    }

    @Test("extensions: user types get get/set; builtins get read-only")
    func extensions() throws {
        #expect(try eval("""
            struct P { var x = 4 }
            extension P { var sq { .x * .x } }
            P().sq
            """) == .int(16))
        #expect(try eval("extension Int { var squared { self * self } }\n12.squared")
            == .int(144))
        #expect(try eval("""
            extension String { var shouted { self + "!" } }
            "hey".shouted
            """) == .string("hey!"))
        // a computed setter on a builtin is refused at declaration
        #expect(throws: SwiftalkError.self) {
            try eval("extension Int { var z { get { 1 } set { } } }")
        }
        // ...and on enums, computed properties are not (yet) a thing
        #expect(throws: SwiftalkError.self) {
            try eval("enum E { case a }\nextension E { var z { 1 } }")
        }
    }

    @Test("paths: get-modify-set through a computed property")
    func paths() throws {
        #expect(try eval("""
            struct S {
                var items = [0, 0]
                var list { get { .items } set { .items = newValue } }
            }
            var s = S()
            s.list[1] = 42
            s.items
            """) == .array([.int(0), .int(42)]))
    }
}
