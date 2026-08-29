import Testing
@testable import Swiftalk

@Suite("types as constructor Functions with .conforms(to:) (§10, round 39)")
struct TypeTests {
    @Test("x.Type is the constructor itself — identity comparison works")
    func typeIdentity() throws {
        #expect(try eval("42.Type == Int") == .bool(true))
        #expect(try eval("Int.Type == Function") == .bool(true))
        #expect(try eval("Int == Int") == .bool(true))
        #expect(try eval("Int == Double") == .bool(false))
        #expect(try eval("(1...3).Type == Range") == .bool(true))
        #expect(try eval("nil.Type == Nil") == .bool(true))
        #expect(try eval("Sequence.Type == Function") == .bool(true))
    }

    @Test("constructors MUST have .name; plain functions are anonymous (round 40)")
    func names() throws {
        #expect(try eval("Int.name") == .string("Int"))
        #expect(try eval("42.Type.name") == .string("Int"))
        #expect(try eval("(1...3).Type.name") == .string("Range"))
        #expect(try eval("Sequence.name") == .string("Sequence"))
        #expect(try eval("{ 42 }.name") == .nil)             // anonymous
        #expect(try eval("Int.name.Type == String") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("42.name") }   // .name is a Function's attribute
    }

    @Test("Type() constructs: conversions, spelled from the other end of §3d")
    func constructors() throws {
        #expect(try eval("Int(\"42\")") == .int(42))
        #expect(try eval("Int(\"0xff\")") == .int(255))       // the lexer's notations re-enter
        #expect(try eval("Int(\"-0b101\")") == .int(-5))
        #expect(try eval("Int(\"forty-two\")") == .nil)       // failable → nil
        #expect(try eval("Int(3.9)") == .int(3))              // truncation toward zero
        #expect(try eval("Int(-3.9)") == .int(-3))
        #expect(try eval("Double(2)") == .double(2.0))
        #expect(try eval("Double(\"1.5\")") == .double(1.5))
        #expect(try eval("Double(\"0x1.8p0\")") == .double(1.5))   // hex floats parse back
        #expect(try eval("String(42)") == .string("42"))
        #expect(try eval("String(\"a\")") == .string("a"))    // identity, not quoting
        #expect(try eval("Bool(\"true\")") == .bool(true))
        #expect(try eval("Array(1...3)") == .array([.int(1), .int(2), .int(3)]))
        #expect(throws: SwiftalkError.self) { try eval("Int([1])") }       // source type never converts
        #expect(throws: SwiftalkError.self) { try eval("Sequence()") }     // protocols don't construct
    }

    @Test("Type() with no arguments gives the Swift-style default")
    func defaults() throws {
        #expect(try eval("Int()") == .int(0))
        #expect(try eval("Double()") == .double(0))
        #expect(try eval("Bool()") == .bool(false))
        #expect(try eval("String()") == .string(""))
        #expect(try eval("Array()") == .array([]))
        #expect(try eval("Dictionary()") == .dictionary([:]))
    }

    @Test(".conforms(to:) — instanceof, the swiftalk way")
    func conforms() throws {
        #expect(try eval("Array.conforms(to: Sequence)") == .bool(true))
        #expect(try eval("\"abc\".Type.conforms(to: Sequence)") == .bool(true))
        #expect(try eval("Range.conforms(to: Sequence)") == .bool(true))
        #expect(try eval("Int.conforms(to: Sequence)") == .bool(false))
        #expect(try eval("Int.conforms(to: Comparable)") == .bool(true))
        #expect(try eval("Array.conforms(to: Comparable)") == .bool(false))
        #expect(try eval("Function.conforms(to: Equatable)") == .bool(true))
        #expect(try eval("Nil.conforms(to: Hashable)") == .bool(true))
        #expect(try eval("Int.conforms(Comparable)") == .bool(true))       // label optional (§2.3)
        #expect(throws: SwiftalkError.self) { try eval("42.conforms(to: Sequence)") }   // ask the type
        #expect(throws: SwiftalkError.self) { try eval("Int.conforms(to: Double)") }    // not a protocol
    }

    @Test("types are ordinary values: bind, pass, key, print")
    func typesAreValues() throws {
        #expect(try eval("let T = Int\nT(\"7\")") == .int(7))
        #expect(try eval("let make = { T, s in T(s) }\nmake(Int, \"7\")") == .int(7))
        #expect(try eval("[Int: \"whole\", Double: \"ieee\"][Int]") == .string("whole"))
        #expect(try eval("Int.String()") == .string("Int"))
        #expect(try eval("Sequence.String()") == .string("Sequence"))
        // a type's name round-trips: eval(Int.String()) is Int itself
        #expect(try eval("[42.Type.String()][0]") == .string("Int"))
        #expect(throws: SwiftalkError.self) { try eval("let Int = 5") }    // no global usurping
    }
}
