import Testing
@testable import Swiftalk

@Suite("class: the open reference, with single inheritance (§4, round 55)")
struct ClassTests {
    @Test("a reference, unserialized and unsealed: aliasing, identity, open writes")
    func openReference() throws {
        #expect(try eval("""
            class Box { var v = 0 }
            let a = Box()
            let b = a
            a.v = 42
            [b.v, a == b]
            """) == .array([.int(42), .bool(true)]))
        #expect(try eval("class Box { var v = 0 }\nBox() == Box()") == .bool(false))
        // let properties still refuse writes — var/let governs, as ever
        #expect(throws: SwiftalkError.self) {
            try eval("class Box { let tag = \"x\" }\nBox().tag = \"y\"")
        }
    }

    @Test("what values never could: cyclic and shared structures")
    func cycles() throws {
        #expect(try eval("""
            class Node {
                var value = 0
                var next: Node? = nil
            }
            let a = Node(value: 1)
            let b = Node(value: 2)
            a.next = b
            b.next = a
            [a.next.next == a, a.next.value]
            """) == .array([.bool(true), .int(2)]))
        // the cyclic echo elides instead of recursing forever
        #expect(try eval("""
            class N { var next: N? = nil }
            let a = N()
            a.next = a
            a.String()
            """) == .string("N { next: N { ... } }"))
    }

    @Test("single inheritance: merged properties, memberwise init, subtype locks")
    func inheritance() throws {
        #expect(try eval("""
            class Animal { var name = "?" }
            class Dog: Animal { var trick = "sit" }
            let d = Dog(name: "Rex", trick: "roll")
            [d.name, d.trick]
            """) == .array([.string("Rex"), .string("roll")]))
        // a Dog IS an Animal: annotations accept up the chain
        #expect(try eval("""
            class Animal { var name = "?" }
            class Dog: Animal { }
            let pet: Animal = Dog(name: "Rex")
            pet.name
            """) == .string("Rex"))
        #expect(throws: SwiftalkError.self) {
            try eval("class A { var x = 0 }\nclass B { }\nlet a: A = B()")
        }
        // .Type is the exact class, not the superclass
        #expect(try eval("""
            class Animal { var name = "?" }
            class Dog: Animal { }
            let d = Dog()
            [d.Type == Dog, d.Type == Animal]
            """) == .array([.bool(true), .bool(false)]))
    }

    @Test("dynamic dispatch: an override wins even from an inherited method")
    func dynamicDispatch() throws {
        #expect(try eval("""
            class Animal {
                var name = "?"
                let speak = { "..." }
                let intro = { "\\(.name) says \\(.speak())" }
            }
            class Dog: Animal { let speak = { "woof" } }
            Dog(name: "Rex").intro()
            """) == .string("Rex says woof"))
        // not overridden → the superclass's method serves
        #expect(try eval("""
            class Animal { var name = "?"
            let greet = { "hi, \\(.name)" } }
            class Cat: Animal { }
            Cat(name: "Tama").greet()
            """) == .string("hi, Tama"))
    }

    @Test("inheritance guards: unknown supers, non-classes, property shadowing")
    func inheritanceGuards() throws {
        #expect(throws: SwiftalkError.self) { try eval("class D: Missing { var x = 0 }") }
        #expect(throws: SwiftalkError.self) {
            try eval("actor A { var x = 0 }\nclass D: A { var y = 0 }")
        }
        #expect(throws: SwiftalkError.self) {
            try eval("struct S { var x = 0 }\nclass D: S { var y = 0 }")
        }
        #expect(throws: SwiftalkError.self) {
            try eval("class A { var x = 0 }\nclass D: A { var x = 1 }")
        }
    }

    @Test("no serialization — a class is NOT an actor (and needs no context)")
    func notAnActor() throws {
        // the round-54 lost update returns when the state is a class:
        // classes give identity, actors give safety — pick on purpose
        #expect(try eval("""
            class C {
                var n = 0
                let bump = { let c = .n; sleep(0.01); .n = c + 1 }
            }
            let c = C()
            let t1 = async { c.bump() }
            let t2 = async { c.bump() }
            await t1
            await t2
            c.n
            """) == .int(1))
        // ...and precisely because there is no baton to take, class
        // methods work inside a coroutine body, where actors cannot
        #expect(try eval("""
            class B { var v = 41
            let next = { .v = .v + 1; .v } }
            let b = B()
            Sequence({ yield b.next() }).Array()
            """) == .array([.int(42)]))
    }

    @Test("the rest of the family carries over: init, extension, echo form")
    func machinery() throws {
        #expect(try eval("""
            class P { var x: Int = 0
            init { v in self.x = v * 2 } }
            P(21).x
            """) == .int(42))
        #expect(try eval("""
            class P { var x = 3 }
            extension P { let doubled = { self.x * 2 } }
            P().doubled()
            """) == .int(6))
        // an extension on the superclass reaches subclasses
        #expect(try eval("""
            class A { var x = 5 }
            class B: A { }
            extension A { let sq = { self.x * self.x } }
            B().sq()
            """) == .int(25))
        #expect(try eval("class E { var a = 1\nvar b = 2 }\nE().String()")
            == .string("E { a: 1, b: 2 }"))
    }
}
