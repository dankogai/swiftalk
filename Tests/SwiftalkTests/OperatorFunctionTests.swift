import Testing
@testable import Swiftalk

@Suite("operators are Functions: (+)(2, 4) (round 144)")
struct OperatorFunctionTests {
    @Test("(op) is a Function applying the operator; two arguments binary, one prefix for - + !")
    func apply() throws {
        #expect(try eval("(+)(2, 4)") == .int(6))
        #expect(try eval("(*)(2, 4)") == .int(8))
        #expect(try eval("(**)(2, 4)") == .int(16))
        #expect(try eval("(-)(9, 4)") == .int(5))
        #expect(try eval("(/)(9, 4)") == .int(2))
        #expect(try eval("(%)(9, 4)") == .int(1))
        #expect(try eval("(+)(1.5, 2.5)") == .double(4))
        #expect(try eval("(+)(\"a\", \"b\")") == .string("ab"))
        #expect(try eval("(+)([1], [2])") == .array([.int(1), .int(2)]))
        #expect(try eval("(==)(1, 1)") == .bool(true))
        #expect(try eval("(!=)(1, 2)") == .bool(true))
        #expect(try eval("(===)(0.0, -0.0)") == .bool(false))
        #expect(try eval("(<)(1, 2) && (>=)(2, 2)") == .bool(true))
        #expect(try eval("(&&)(true, false)") == .bool(false))
        #expect(try eval("(||)(true, false)") == .bool(true))
        #expect(try eval("(^^)(true, true)") == .bool(false))
        #expect(try eval("(??)(nil, 2)") == .int(2))
        #expect(try eval("(??)(1, 2)") == .int(1))
        #expect(try eval("(!!)(1, 2)") == .int(2))
        #expect(try eval("(!!)(1, nil)") == .int(1))
        #expect(try eval("(??)([\"a\": 1], [\"a\": 9, \"b\": 2])") == .dictionary([.string("a"): .int(1), .string("b"): .int(2)]))
        #expect(try eval("(|)(Set(1), Set(2))") == .set([.int(1), .int(2)]))
        #expect(try eval("(&)(Set(1, 2), Set(2))") == .set([.int(2)]))
        #expect(try eval("(^)(Set(1, 2), Set(2, 3))") == .set([.int(1), .int(3)]))
        #expect(try eval("(-)(5)") == .int(-5))                                  // prefix, with one argument
        #expect(try eval("(-)(2.5)") == .double(-2.5))
        #expect(try eval("(+)(5)") == .int(5))
        #expect(try eval("(!)(true)") == .bool(false))
        #expect(throws: SwiftalkError.self) { try eval("(+)(1, 2.0)") }          // the operator's own rules
        #expect(throws: SwiftalkError.self) { try eval("(**)(2, -1)") }
        #expect(throws: SwiftalkError.self) { try eval("(&&)(1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("(|)(1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("(*)(1)") }               // no prefix *
        #expect(throws: SwiftalkError.self) { try eval("(+)(1, 2, 3)") }
        #expect(throws: SwiftalkError.self) { try eval("(+)()") }
        #expect(throws: SwiftalkError.self) { try eval("(!)(1)") }
        #expect(throws: SwiftalkError.self) { try eval("(-)(Int.min)") }         // overflow, as -Int.min is
    }

    @Test("a Function value like any other: passed, bound, compared by identity; (+).String() re-enters")
    func values() throws {
        #expect(try eval("[1, 2, 3].reduce(0, (+))") == .int(6))
        #expect(try eval("[1, 2, 3].reduce(1, (*))") == .int(6))
        #expect(try eval("[3, 1, 2].sorted((<))") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval("[3, 1, 2].sorted((>))") == .array([.int(3), .int(2), .int(1)]))
        #expect(try eval("[1, 2].map((-))") == .array([.int(-1), .int(-2)]))
        #expect(try eval("[true, false].map((!))") == .array([.bool(false), .bool(true)]))
        #expect(try eval("[[1, 2], [3]].reduce([], (+))") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval("let add = (+)\nadd(1, 2)") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval("let add = (+)\nadd(x: 1, y: 2)") }   // no labels: a builtin takes values raw
        #expect(try eval("(+).Type == Function") == .bool(true))
        #expect(try eval("(+) == (+)") == .bool(true))                            // one Function per operator
        #expect(try eval("(+) == (-)") == .bool(false))
        #expect(try eval("(+).String()") == .string("(+)"))
        #expect(try eval("(**).String()") == .string("(**)"))
        #expect(try eval("eval((**).String())(2, 3)") == .int(8))               // the round-trip law
        #expect(try eval("(+).name") == .string("(+)"))
        #expect(try eval("[(+), (*)].map { $0(2, 3) }") == .array([.int(5), .int(6)]))
        #expect(try eval("( + )(1, 2)") == .int(3))                             // spacing is free
        #expect(try eval("(+1)") == .int(1))                                     // still prefix + applied to 1
        #expect(try eval("(-1)") == .int(-1))
        #expect(try eval("(1 + 2)") == .int(3))                                  // grouping is untouched
        #expect(throws: SwiftalkError.self) { try eval("(=)") }
        #expect(throws: SwiftalkError.self) { try eval("(...)") }
        #expect(throws: SwiftalkError.self) { try eval("(+=)") }
        #expect(throws: SwiftalkError.self) { try eval("(?)") }
    }

    @Test("the bare form (round 145): an operator alone as a call argument — reduce(0, +), sorted(by: <), map(-)")
    func bare() throws {
        #expect(try eval("[1, 2, 3].reduce(0, +)") == .int(6))
        #expect(try eval("[1, 2, 3].reduce(1, *)") == .int(6))
        #expect(try eval("[10, 2, 3].reduce(20, -)") == .int(5))
        #expect(try eval("[2, 3].reduce(1, **)") == .int(1))                      // ((1 ** 2) ** 3)
        #expect(try eval("[3, 1, 2].sorted(<)") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval("[3, 1, 2].sorted(by: >)") == .array([.int(3), .int(2), .int(1)]))
        #expect(try eval("[1, 2].map(-)") == .array([.int(-1), .int(-2)]))
        #expect(try eval("[true, false].map(!)") == .array([.bool(false), .bool(true)]))
        #expect(try eval("[\"b\", \"a\"].max(by: <)") == .string("b"))
        #expect(try eval("[[1], [2]].reduce([], +)") == .array([.int(1), .int(2)]))
        #expect(try eval("[8, 2].reduce(64, /)") == .int(4))                      // `/` before `)`: an operator, not a regex
        let apply = "let apply = { op, a, b in op(a, b) }\n"
        #expect(try eval(apply + "apply(+, 2, 3)") == .int(5))
        #expect(try eval(apply + "apply(**, 2, 3)") == .int(8))
        #expect(try eval(apply + "apply(==, 1, 1)") == .bool(true))
        #expect(try eval(apply + "apply(!!, nil, 4)") == .int(4))
        #expect(try eval(apply + "apply(??, nil, 4)") == .int(4))
        #expect(try eval(apply + "apply(|, Set(1), Set(2)).count") == .int(2))
        #expect(try eval(apply + "apply( + , 2, 3)") == .int(5))                  // spacing is free
        #expect(try eval(apply + "apply(+,2,3)") == .int(5))
        #expect(try eval("\"a,b\".split(/,/)") == .array([.string("a"), .string("b")]))   // a regex of a comma is still a regex
        #expect(try eval("[(+)][0](1, 2)") == .int(3))
        #expect(try eval("let f = { $0(2, 5) }\nf(-)") == .int(-3))                // -(2, 5): binary with two arguments
        #expect(try eval("[1, 2].map(+)") == .array([.int(1), .int(2)]))            // prefix + with one argument
        #expect(try eval("(1 + 2)") == .int(3))                                    // an operator with operands is not bare
        #expect(try eval("[1, 2].reduce(0, +) + 1") == .int(4))
        #expect(throws: SwiftalkError.self) { try eval("let apply = { op, a, b in op(a, b) }\napply(/, 6, 3)") }   // `/` then `,` reads as a regex — write (/)
        #expect(try eval("let apply = { op, a, b in op(a, b) }\napply((/), 6, 3)") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("[1].reduce(0, +=)") }
        #expect(throws: SwiftalkError.self) { try eval("[1].reduce(0, ...)") }
    }
}
