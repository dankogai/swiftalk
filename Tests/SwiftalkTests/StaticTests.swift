import Testing
@testable import Swiftalk

@Suite("static members and Self (round 143)")
struct StaticTests {
    let point = """
        struct Point {
            var x: Int = 0
            var y: Int = 0
            static let origin = Self(x: 0, y: 0)
            static let plus = { lhs, rhs in Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
            static var unit { Self(x: 1, y: 1) }
            static var count { 2 }
            let shifted = { Self(x: .x + 1, y: .y + 1) }
        }

        """

    @Test("static let is a value or a static method, static var a getter; Self is the type inside the body")
    func structStatics() throws {
        #expect(try eval(point + "Point.origin == Point(x: 0, y: 0)") == .bool(true))
        #expect(try eval(point + "Point.origin.x") == .int(0))
        #expect(try eval(point + "Point.plus(Point(x: 1, y: 2), Point(x: 3, y: 4)).x") == .int(4))
        #expect(try eval(point + "Point.plus(Point(1, 2), Point(3, 4)) == Point(4, 6)") == .bool(true))
        #expect(try eval(point + "Point.unit.y") == .int(1))
        #expect(try eval(point + "Point.count") == .int(2))
        #expect(try eval(point + "Point.plus.Type == Function") == .bool(true))              // uncalled: the Function
        #expect(try eval(point + "let f = Point.plus\nf(Point(1, 1), Point(1, 1)).y") == .int(2))
        #expect(try eval(point + "Point(x: 1, y: 1).shifted().x") == .int(2))                 // Self in an instance method
        #expect(try eval(point + "Point(1, 1).Type.origin.x") == .int(0))                     // through .Type
        #expect(throws: SwiftalkError.self) { try eval(point + "Point.count()") }             // a static var is read, not called
        #expect(throws: SwiftalkError.self) { try eval(point + "Point.origin()") }            // a value, not a Function
        #expect(throws: SwiftalkError.self) { try eval(point + "Point.nope") }
        #expect(throws: SwiftalkError.self) { try eval(point + "Point(1, 2).origin") }        // statics are the type's, not the instance's
        #expect(throws: SwiftalkError.self) { try eval("Self") }                              // no Self outside a type body
        #expect(throws: SwiftalkError.self) { try eval("struct S { static var n = 1 }") }     // a static var computes
        #expect(throws: SwiftalkError.self) { try eval("struct S { static let a = 1; static let a = 2 }") }
        #expect(throws: SwiftalkError.self) { try eval("struct S { static var v { get { 1 } set { } } }") }
        #expect(throws: SwiftalkError.self) { try eval("struct S { static func f() { } }") }
    }

    @Test("enums: statics beside cases, never sharing a case's name")
    func enumStatics() throws {
        let shape = "enum Shape { case circle(r: Double), dot; static let unitCircle = Self.circle(r: 1.0); static var names { [\"circle\", \"dot\"] } }\n"
        #expect(try eval(shape + "Shape.unitCircle == Shape.circle(r: 1.0)") == .bool(true))
        #expect(try eval(shape + "Shape.names.count") == .int(2))
        #expect(try eval(shape + "Shape.dot == Shape.dot") == .bool(true))                    // cases still construct
        #expect(throws: SwiftalkError.self) { try eval("enum E { case a; static let a = 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("enum E { case a }\nextension E { static let a = 1 }") }
    }

    @Test("extensions add statics — to user types and to builtins — and Self reaches the extended type; :r overwrites")
    func extensions() throws {
        #expect(try eval(point + "extension Point { static let zero = Self.origin; static var two { Self(x: 2, y: 2) } }\nPoint.zero == Point.origin && Point.two.x == 2") == .bool(true))
        #expect(try eval("extension Int { static let answer = 42; static var lucky { 7 }; static let twice = { n in n * 2 } }\n[Int.answer, Int.lucky, Int.twice(4)]") == .array([.int(42), .int(7), .int(8)]))
        #expect(try eval("extension Int { static let answer = 42 }\nInt.max > Int.answer") == .bool(true))       // beside the builtin statics
        #expect(try eval("extension String { static let empty = Self() }\nString.empty == \"\"") == .bool(true))
        #expect(try eval("extension Int { let double = { Self(self * 2) } }\n21.double()") == .int(42))      // Self in an extension method
        #expect(throws: SwiftalkError.self) { try eval(point + "extension Point { static let origin = 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("extension Int { static let a = 1 }\nextension Int { static let a = 2 }") }
        #expect(try eval("extension Int { static let e = 3 }\nInt.e") == .int(3))
        let i = Swiftalk.Interpreter(relaxed: true)
        _ = try i.eval(point)
        _ = try i.redefine("extension Point { static let origin = Self(x: 9, y: 9); static var unit { Self(x: 5, y: 5) } }")
        #expect(try i.eval("Point.origin.x + Point.unit.x") == .int(14))
        _ = try i.eval("extension Int { static let k = 1 }")
        _ = try i.redefine("extension Int { static let k = 2 }")
        #expect(try i.eval("Int.k") == .int(2))
        _ = try i.redefine("extension Int { static var k { 3 } }")                               // a let becomes a var
        #expect(try i.eval("Int.k") == .int(3))
    }
}
