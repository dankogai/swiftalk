import Testing
@testable import Swiftalk

@Suite("super: class-only, by construction (§4, round 56)")
struct SuperTests {
    @Test("an override reaches the implementation it covered")
    func basicSuper() throws {
        #expect(try eval("""
            class Animal { let speak = { "..." } }
            class Dog: Animal { let speak = { "woof, then " + super.speak() } }
            Dog().speak()
            """) == .string("woof, then ..."))
    }

    @Test("super pins the lookup; self stays dynamic inside — as in Swift")
    func superPinsSelfStaysDynamic() throws {
        #expect(try eval("""
            class Animal {
                var name = "?"
                let speak = { "..." }
                let intro = { "\\(.name) says \\(.speak())" }
            }
            class Dog: Animal {
                let speak = { "woof" }
                let intro = { "[dog] " + super.intro() }
            }
            Dog(name: "Rex").intro()
            """) == .string("[dog] Rex says woof"))
    }

    @Test("a three-level chain resolves from the DECLARING class — no loop")
    func threeLevel() throws {
        #expect(try eval("""
            class A { let who = { "A" } }
            class B: A { let who = { "B>" + super.who() } }
            class C: B { let who = { "C>" + super.who() } }
            C().who()
            """) == .string("C>B>A"))
        // the middle class's method runs on a C instance, and its
        // super still means A's — declaring class, not dynamic type
        #expect(try eval("""
            class A { let who = { "A" } }
            class B: A { let who = { "B>" + super.who() } }
            class C: B { }
            C().who()
            """) == .string("B>A"))
    }

    @Test("super.init runs a declared superclass init on self")
    func superInit() throws {
        #expect(try eval("""
            class P { var x: Int = 0
            init { v in self.x = v } }
            class Q: P { var y: Int = 0
            init { v in super.init(v)
            self.y = v * 2
            } }
            let q = Q(21)
            [q.x, q.y]
            """) == .array([.int(21), .int(42)]))
        // no declared init to reach — memberwise already prefilled
        #expect(throws: SwiftalkError.self) {
            try eval("""
                class P { var x = 0 }
                class Q: P { init { v in super.init(v) } }
                Q(1)
                """)
        }
    }

    @Test("class extensions may use super; uncalled super.m extracts bound")
    func extensionsAndExtraction() throws {
        #expect(try eval("""
            class A { let f = { "a" } }
            class B: A { let f = { "b" } }
            extension B { let g = { super.f() } }
            B().g()
            """) == .string("a"))
        #expect(try eval("""
            class A { let f = { "a" } }
            class B: A { let f = { "b" }
            let g = { let h = super.f; h() } }
            B().g()
            """) == .string("a"))
    }

    @Test("where super does not belong: everywhere else")
    func guards() throws {
        // top level, root class, struct, actor — and bare super
        #expect(throws: SwiftalkError.self) { try eval("super.f()") }
        #expect(throws: SwiftalkError.self) {
            try eval("class R { let f = { super.g() } }\nR().f()")
        }
        #expect(throws: SwiftalkError.self) {
            try eval("struct S { let f = { super.g() } }\nS().f()")
        }
        #expect(throws: SwiftalkError.self) {
            try eval("actor A { let f = { super.g() } }\nA().f()")
        }
        #expect(throws: SwiftalkError.self) {
            try eval("class A { let f = { \"a\" } }\nclass B: A { let g = { super } }\nB().g()")
        }
        // properties are never overridden — super.prop is a guided error
        #expect(throws: SwiftalkError.self) {
            try eval("""
                class A { var x = 1 }
                class B: A { let f = { super.x } }
                B().f()
                """)
        }
    }

    @Test("a nested class never inherits an outer class's superclass")
    func noLexicalLeak() throws {
        // R is declared inside B's method body; R has no superclass,
        // and B's @superclass must not leak into R's methods
        #expect(throws: SwiftalkError.self) {
            try eval("""
                class A { let f = { "a" } }
                class B: A {
                    let make = {
                        class R { let g = { super.f() } }
                        return R().g()
                    }
                }
                B().make()
                """)
        }
    }
}
