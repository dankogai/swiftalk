import Testing
@testable import Swiftalk

@Suite("methods and init on user types; multi-dispatch inits (round 48)")
struct MethodTests {
    private let point = """
        struct Point {
            var x: Int = 0
            var y: Int = 0
            let norm2 = { self.x * self.x + self.y * self.y }
            let scaled = { k in self.x * k }
        }
        """

    @Test("methods: let name = { ... } with self bound at invocation")
    func methods() throws {
        #expect(try eval("\(point)\nPoint(x: 3, y: 4).norm2()") == .int(25))
        #expect(try eval("\(point)\nPoint(x: 6, y: 8).norm2()") == .int(100))
        #expect(try eval("\(point)\nPoint(x: 5, y: 0).scaled(9)") == .int(45))
        #expect(try eval("\(point)\nPoint(x: 5, y: 0).scaled(k: 9)") == .int(45))   // labels (§2.3)
        // uncalled access is a bound Function
        #expect(try eval("\(point)\nlet m = Point(x: 3, y: 4).norm2\nm()") == .int(25))
        #expect(try eval("\(point)\nPoint().norm2.Type == Function") == .bool(true))
        // methods chain with everything else
        #expect(try eval("\(point)\n[Point(x: 1, y: 0), Point(x: 2, y: 0)].map { $0.norm2() }")
            == .array([.int(1), .int(4)]))
    }

    @Test("self is a let in methods — mutating methods are OPEN")
    func selfImmutable() throws {
        #expect(throws: SwiftalkError.self) {
            try eval("struct S { var n: Int = 0\nlet bump = { self.n = 1 } }\nS().bump()")
        }
    }

    @Test("init { params in ... }: self.x assignment, defaults prefilled")
    func initBasics() throws {
        #expect(try eval("""
            struct P {
                var x: Int = 0
                var y: Int = 0
                init { v in self.x = v\nself.y = v }
            }
            P(7).y
            """) == .int(7))
        // defaults are visible before assignment
        #expect(try eval("""
            struct P {
                var x: Int = 10
                var y: Int = 0
                init { v in self.y = self.x + v }
            }
            P(5).y
            """) == .int(15))
    }

    @Test("multiple inits multi-dispatch on arity and labels; memberwise is the last candidate")
    func multiDispatch() throws {
        let p = """
            struct P {
                var x: Int = 0
                var y: Int = 0
                init { both in self.x = both\nself.y = both }
                init { a, b in self.x = a\nself.y = a * b }
            }
            """
        #expect(try eval("\(p)\nP(7).y") == .int(7))            // arity 1
        #expect(try eval("\(p)\nP(3, 4).y") == .int(12))        // arity 2
        #expect(try eval("\(p)\nP(a: 3, b: 4).y") == .int(12))  // labels pick the second
        #expect(try eval("\(p)\nP(x: 1, y: 2).y") == .int(2))   // memberwise fallback
        #expect(try eval("\(p)\nP().x") == .int(0))             // memberwise defaults
    }

    @Test("init leaves no non-optional property uninitialized")
    func initVerification() throws {
        #expect(try eval("struct Q { var a: Int\ninit { self.a = 1 } }\nQ().a") == .int(1))
        #expect(throws: SwiftalkError.self) {
            try eval("struct R { var a: Int\ninit { self.a * 0 } }\nR()")
        }
    }

    @Test("enum methods: switch self inside; case accessors still win")
    func enumMethods() throws {
        let shape = """
            enum Shape {
                case circle(r: Double)
                case point
                let area = {
                    switch self {
                    case .circle(let r): return 3.14159265358979 * r * r
                    case .point: return 0.0
                    }
                }
            }
            """
        #expect(try eval("\(shape)\nShape.circle(r: 1.0).area()") == .double(3.14159265358979))
        #expect(try eval("\(shape)\nShape.point.area()") == .double(0.0))
        #expect(try eval("\(shape)\nShape.circle(r: 2.0).circle") == .double(2.0))  // accessor intact
        #expect(try eval("\(shape)\n[Shape.circle(r: 1.0), Shape.point].map { $0.area() }.reduce(0.0) { $0 + $1 }")
            == .double(3.14159265358979))
    }

    @Test("methods may recurse by self-reference and by $()")
    func methodRecursion() throws {
        #expect(try eval("""
            struct F {
                var seed: Int = 0
                let fac = { n in n < 2 ? 1 : n * $(n - 1) }
                let tri = { n in n == 0 ? self.seed : n + self.tri(n - 1) }
            }
            [F().fac(10), F(seed: 100).tri(4)]
            """) == .array([.int(3628800), .int(110)]))
    }

    @Test("a stored Function wants var; let-with-closure means method")
    func storedVsMethod() throws {
        // var f = {...} is a stored property — no self, reassignable
        #expect(try eval("""
            struct S {
                var f: Function = .todo
            }
            var s = S(f: { 42 })
            s.f()
            """) == .int(42))
    }
}
