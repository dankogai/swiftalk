import Testing
@testable import Swiftalk

@Suite("{} functions with $ (§2.4)")
struct FunctionTests {
    @Test("{} always makes a Function; it is its value only when evaluated (round 12)")
    func braceMeansFunction() throws {
        #expect(try eval("{ 42 }.type == Function") == .bool(true))
        #expect(try eval("{ 42 }()") == .int(42))
        #expect(try eval("{ 42 }().type == Int") == .bool(true))
        #expect(try eval("let f = { 42 }\nf.type == Function") == .bool(true))
    }

    @Test("named parameters; labels optional, reorderable, mixable (§2.3)")
    func labels() throws {
        #expect(try eval("let add = { x, y in x + y }\nadd(2, 3)") == .int(5))
        #expect(try eval("let add = { x, y in x + y }\nadd(x: 2, y: 3)") == .int(5))
        #expect(try eval("let f = { x, y in x - y }\nf(y: 3, x: 10)") == .int(7))
        #expect(try eval("let f = { x, y in x - y }\nf(10, y: 3)") == .int(7))
        #expect(throws: SwiftalkError.self) { try eval("let f = { x in x }\nf(z: 1)") }
        #expect(throws: SwiftalkError.self) { try eval("let f = { x, y in x }\nf(x: 1, x: 2)") }
    }

    @Test("strict arity for declared params; no params means variadic (rounds 10 & 14)")
    func arity() throws {
        #expect(throws: SwiftalkError.self) { try eval("let f = { x, y in x + y }\nf(1)") }
        #expect(throws: SwiftalkError.self) { try eval("let f = { x, y in x + y }\nf(1, 2, 3)") }
        #expect(try eval("{ $.count }(1, 2, 3)") == .int(3))
        #expect(try eval("{ 0 }(1, 2, 3)") == .int(0))       // array.map { 0 } semantics
        #expect(try eval("{ $.count }()") == .int(0))
        #expect(throws: SwiftalkError.self) { try eval("{ $.count }(x: 1)") }
    }

    @Test("$ is the arguments; $0 is $[0] (§2.4)")
    func dollarArguments() throws {
        #expect(try eval("{ $0 + $1 }(40, 2)") == .int(42))
        #expect(try eval("{ $ }(1, \"one\")") == .array([.int(1), .string("one")]))
        #expect(try eval("let f = { x, y in $.count }\nf(1, 2)") == .int(2))  // $ works alongside names
        #expect(throws: SwiftalkError.self) { try eval("{ $2 }(1, 2)") }      // out of range
        #expect(throws: SwiftalkError.self) { try eval("$0") }                // no function around
    }

    @Test("$ is per-closure: inner shadows outer (round 22 discussion)")
    func dollarShadowing() throws {
        #expect(try eval("{ $0 + { $0 * 10 }(2) }(1)") == .int(21))
    }

    @Test("$() recurses: the marquee factorial (§2.4)")
    func recursion() throws {
        #expect(try eval("let fac = { n in n < 2 ? 1 : n * $(n - 1) }\nfac(20)")
            == .int(2432902008176640000))
        #expect(try eval("{ n in n < 2 ? n : $(n - 1) + $(n - 2) }(20)") == .int(6765))
        #expect(throws: SwiftalkError.self) { try eval("$(1)") }   // only inside a function
    }

    @Test("closures capture lexically, including mutation")
    func closures() throws {
        #expect(try eval("let a = 40\nlet f = { a + $0 }\nf(2)") == .int(42))
        #expect(try eval("var c = 0\nlet inc = { c = c + 1 }\ninc()\ninc()\nc") == .int(2))
        // the lock reaches through the closure too
        #expect(throws: SwiftalkError.self) {
            try eval("var c = 0\nlet bad = { c = \"one\" }\nbad()")
        }
    }

    @Test("multi-statement bodies evaluate to the last statement")
    func bodies() throws {
        #expect(try eval("let f = { x in\n  let y = x * 2\n  y + 1\n}\nf(3)") == .int(7))
        #expect(try eval("{ }()") == .nil)                   // empty body yields nil
    }

    @Test("functions are values: Function type lock, identity equality (§2.4, round 26)")
    func functionValues() throws {
        #expect(try eval("var f = { 1 }\nf = { 2 }\nf()") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("var f = { 1 }\nf = 3") }
        #expect(try eval("let f = { 1 }\nlet g = f\nf == g") == .bool(true))
        #expect(try eval("let f = { 1 }\nlet g = { 1 }\nf == g") == .bool(false))
    }

    @Test("comparisons: Equatable everywhere same-type, Comparable on Int/Double/String (§10)")
    func comparisons() throws {
        #expect(try eval("1 < 2") == .bool(true))
        #expect(try eval("\"a\" < \"b\"") == .bool(true))
        #expect(try eval("1.5 >= 1.5") == .bool(true))
        #expect(try eval("[1, 2] == [1, 2]") == .bool(true))
        #expect(try eval("1 != 2") == .bool(true))
        #expect(try eval("1 == nil") == .bool(false))        // valid of anything (§3a)
        #expect(try eval("nil == nil") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("1 == 1.0") }   // Int ≠ Double
        #expect(throws: SwiftalkError.self) { try eval("1 < \"2\"") }
        #expect(throws: SwiftalkError.self) { try eval("[1] < [2]") }  // Array isn't Comparable (yet)
    }

    @Test("ternary requires a Bool — nothing is truthy (§3b)")
    func ternary() throws {
        #expect(try eval("true ? 1 : 2") == .int(1))
        #expect(try eval("1 < 2 ? \"yes\" : \"no\"") == .string("yes"))
        #expect(try eval("false ? 1 : true ? 2 : 3") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("1 ? 2 : 3") }
        #expect(throws: SwiftalkError.self) { try eval("\"\" ? 2 : 3") }
    }

    @Test(".count on the Sequence conformers (§10)")
    func count() throws {
        #expect(try eval("[1, 2, 3].count") == .int(3))
        #expect(try eval("\"héllo🍰\".count") == .int(6))     // graphemes (§11)
        #expect(try eval("[\"a\": 1].count") == .int(1))
        #expect(throws: SwiftalkError.self) { try eval("42.count") }
    }

    @Test("REPL integration: multi-line function entry via open braces")
    func replContinuation() {
        #expect(needsMoreInput("let f = { x in"))
        #expect(!needsMoreInput("let f = { x in x }"))
    }
}
