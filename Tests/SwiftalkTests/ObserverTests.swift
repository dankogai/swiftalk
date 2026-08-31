import Testing
@testable import Swiftalk

@Suite("willSet/didSet observers on stored properties (round 58b)")
struct ObserverTests {
    @Test("order and payloads: willSet(new, old self) then didSet(old, new self)")
    func orderAndPayloads() throws {
        #expect(try eval("""
            var log = []
            struct Score {
                var points = 0 {
                    willSet { log.append("will \\(.points) -> \\(newValue)") }
                    didSet(old) { log.append("did \\(old) -> \\(.points)") }
                }
            }
            var s = Score()
            s.points = 50
            log
            """) == .array([.string("will 0 -> 50"), .string("did 0 -> 50")]))
    }

    @Test("the canonical clamp: didSet reassigning its own property terminates")
    func clamp() throws {
        #expect(try eval("""
            struct S { var x = 0 { didSet { if .x > 10 { .x = 10 } } } }
            var s = S()
            s.x = 42
            s.x
            """) == .int(10))
    }

    @Test("the clamp on a class", .disabled("shelved — round 62: actor/class/super are off the surface"))
    func clampOnClass() throws {
        #expect(try eval("""
            class Gauge { var level: Int = 0 { didSet { if .level > 9 { .level = 9 } } } }
            let g = Gauge()
            g.level = 42
            g.level
            """) == .int(9))
    }

    @Test("observers stay silent during init — memberwise and declared alike")
    func initSilence() throws {
        #expect(try eval("""
            var fired = 0
            struct S { var x = 0 { didSet { fired = fired + 1 } } }
            var s = S(x: 5)
            let afterInit = fired
            s.x = 6
            [afterInit, fired]
            """) == .array([.int(0), .int(1)]))
        #expect(try eval("""
            var fired = 0
            struct S { var x: Int = 0 { didSet { fired = fired + 1 } }
            init { v in self.x = v } }
            let s = S(9)
            [s.x, fired]
            """) == .array([.int(9), .int(0)]))
    }

    @Test("references: class inheritance carries observers; actors observe method writes", .disabled("shelved — round 62: actor/class/super are off the surface"))
    func referenceKinds() throws {
        #expect(try eval("""
            var log = []
            class A { var x = 0 { didSet { log.append(.x) } } }
            class B: A { }
            let b = B()
            b.x = 7
            log
            """) == .array([.int(7)]))
        #expect(try eval("""
            var log = []
            actor Bank {
                var balance = 0 { didSet(old) { log.append(.balance - old) } }
                let deposit = { n in .balance = .balance + n }
            }
            let b = Bank()
            b.deposit(30)
            b.deposit(12)
            log
            """) == .array([.int(30), .int(12)]))
    }

    @Test("annotated-only observed property; observers demand var")
    func forms() throws {
        #expect(try eval("""
            var seen: Int? = nil
            struct S { var x: Int { willSet { seen = newValue } } }
            var s = S(x: 1)
            s.x = 2
            seen
            """) == .int(2))
        #expect(throws: SwiftalkError.self) {
            try eval("struct S { let x = 0 { didSet { } } }")
        }
    }

    @Test("disambiguation: trailing closures in defaults still parse")
    func trailingClosuresSurvive() throws {
        #expect(try eval("""
            struct S { var squares = (1...3).map { $0 * $0 } }
            S().squares
            """) == .array([.int(1), .int(4), .int(9)]))
    }

    @Test("path writes observe too: s.list[0] = v fires list's didSet")
    func pathWrites() throws {
        #expect(try eval("""
            var fired = 0
            struct S { var list = [0, 0] { didSet { fired = fired + 1 } } }
            var s = S()
            s.list[1] = 42
            [s.list, fired]
            """) == .array([.array([.int(0), .int(42)]), .int(1)]))
    }
}
