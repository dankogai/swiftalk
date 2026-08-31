import Testing
@testable import Swiftalk

@Suite("actors: serialized state, swiftalk's first reference type (§12, round 54)", .disabled("shelved — round 62: actor/class/super are off the surface"))
struct ActorTests {
    @Test("declaration, memberwise init, defaults, property reads, .Type")
    func basics() throws {
        #expect(try eval("""
            actor Counter { var count = 0 }
            Counter(count: 3).count
            """) == .int(3))
        #expect(try eval("actor A { var x = 1 }\nA().x") == .int(1))
        #expect(try eval("actor A { var x = 1 }\nA().Type == A") == .bool(true))
        #expect(try eval("actor A { var x = 1 }\nA.name") == .string("A"))
        #expect(try eval("actor A { var x = 1 }\nA.conforms(to: Equatable)") == .bool(true))
    }

    @Test("declared inits multi-dispatch, memberwise last — round 48 machinery")
    func inits() throws {
        #expect(try eval("""
            actor P {
                var x: Int = 0
                var y: Int = 0
                init { v in self.x = v
                self.y = v
                }
            }
            P(7).y
            """) == .int(7))
        #expect(try eval("""
            actor P { var x: Int = 0
            var y: Int = 0 }
            P(x: 1, y: 2).y
            """) == .int(2))
    }

    @Test("a reference at last: let b = a aliases; equality is identity")
    func referenceSemantics() throws {
        #expect(try eval("""
            actor Counter {
                var count = 0
                let inc = { self.count = self.count + 1 }
            }
            let a = Counter()
            let b = a
            a.inc()
            [b.count, a == b]
            """) == .array([.int(1), .bool(true)]))
        #expect(try eval("actor A { var x = 0 }\nA() == A()") == .bool(false))
        // in-place mutation needs no var binding — the reference never changes
        #expect(try eval("""
            actor Box { var v = 0
            let put = { n in self.v = n } }
            let box = Box()
            box.put(42)
            box.v
            """) == .int(42))
    }

    @Test("isolation: reads are open, writes only from the actor's own methods")
    func isolation() throws {
        #expect(throws: SwiftalkError.self) {
            try eval("actor A { var x = 0 }\nlet a = A()\na.x = 1")
        }
        // ...including mutation reached through a property path
        #expect(throws: SwiftalkError.self) {
            try eval("actor A { var list = [1] }\nlet a = A()\na.list.append(2)")
        }
        // let properties refuse writes even from inside
        #expect(throws: SwiftalkError.self) {
            try eval("""
                actor A { let tag = "fixed"
                let poke = { self.tag = "changed" } }
                A().poke()
                """)
        }
        // implicit self (round 49) works in actor bodies: .x is self.x
        #expect(try eval("""
            actor A { var x = 0
            let set = { n in .x = n } }
            let a = A()
            a.set(9)
            a.x
            """) == .int(9))
    }

    @Test("the marquee: serialization under interleaving — and the hazard without it")
    func serialization() throws {
        // read-sleep-write from two tasks: an actor holds each call to
        // the end, so no update is lost
        #expect(try eval("""
            actor Counter {
                var count = 0
                let bump = { let c = .count; sleep(0.01); .count = c + 1 }
            }
            let a = Counter()
            let t1 = async { a.bump() }
            let t2 = async { a.bump() }
            await t1
            await t2
            a.count
            """) == .int(2))
        // the identical pattern on a bare shared var loses an update —
        // the interleaving hazard actors exist to remove
        #expect(try eval("""
            var g = 0
            let racy = { let c = g; sleep(0.01); g = c + 1 }
            let u1 = async { racy() }
            let u2 = async { racy() }
            await u1
            await u2
            g
            """) == .int(1))
    }

    @Test("self-calls re-enter freely — no self-deadlock")
    func reentrancy() throws {
        #expect(try eval("""
            actor A {
                var n = 0
                let outer = { self.n = self.n + 1; self.inner() }
                let inner = { self.n = self.n * 10 }
            }
            let a = A()
            a.outer()
            a.n
            """) == .int(10))
    }

    @Test("a circular wait is a deadlock error, not a hang")
    func deadlock() throws {
        // outer holds the actor and awaits a task that needs the actor
        #expect(throws: SwiftalkError.self) {
            try eval("""
                actor D {
                    var n = 0
                    let inner = { self.n }
                    let outer = { await async { self.inner() } }
                }
                D().outer()
                """)
        }
    }

    @Test("a method error releases the actor — it stays usable")
    func errorReleases() throws {
        #expect(try eval("""
            actor A {
                var x = 0
                let boom = { nil! }
                let fine = { self.x = self.x + 1 }
            }
            let a = A()
            let r = async { a.boom() }
            a.fine()
            a.x
            """) == .int(1))
    }

    @Test("extraction keeps serialization; extensions add methods")
    func extractionAndExtension() throws {
        #expect(try eval("""
            actor Counter { var count = 0
            let inc = { self.count = self.count + 1 } }
            let a = Counter()
            let f = a.inc
            f()
            f()
            a.count
            """) == .int(2))
        #expect(try eval("""
            actor Counter { var count = 3 }
            extension Counter { let doubled = { self.count * 2 } }
            Counter().doubled()
            """) == .int(6))
    }

    @Test("echo form: an informative placeholder — reference, not round-trip")
    func sourceForm() throws {
        #expect(try eval("actor A { var x = 1\nvar y = 2 }\nA().String()")
            == .string("A { x: 1, y: 2 }"))
    }
}
