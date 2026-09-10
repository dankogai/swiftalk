import Testing
@testable import Swiftalk

@Suite("operators on structs and enums: infix(+) = { lhs, rhs in }, prefix(-), postfix(!) (round 146)")
struct OperatorDeclTests {
    let complex = """
        struct Complex {
            var real: Double = 0.0
            var imag: Double = 0.0
            infix(+) = { lhs, rhs in Self(lhs.real + rhs.real, lhs.imag + rhs.imag) }
            infix(*) = { lhs, rhs in Self(lhs.real * rhs.real - lhs.imag * rhs.imag, lhs.real * rhs.imag + lhs.imag * rhs.real) }
            prefix(-) = { z in Self(-z.real, -z.imag) }
            var abs { (.real * .real + .imag * .imag) ** 0.5 }
        }
        let i = Complex(0.0, 1.0)
        let one = Complex(1.0, 0.0)

        """

    @Test("infix and prefix operators on a struct; every spelling reaches them: infix, +=, (op), reduce(+)")
    func complexOps() throws {
        #expect(try eval(complex + "i * i == Complex(-1.0, 0.0)") == .bool(true))
        #expect(try eval(complex + "(one + i).imag") == .double(1))
        #expect(try eval(complex + "(-i).imag") == .double(-1))
        #expect(try eval(complex + "var z = one\nz += i\nz *= i\nz == Complex(-1.0, 1.0)") == .bool(true))
        #expect(try eval(complex + "(+)(one, i) == one + i") == .bool(true))
        #expect(try eval(complex + "(*)(i, i).real") == .double(-1))
        #expect(try eval(complex + "(-)(i).imag") == .double(-1))
        #expect(try eval(complex + "[one, i, i].reduce(Complex(), +).imag") == .double(2))
        #expect(try eval(complex + "[one, i].map(-)[1].imag") == .double(-1))
        #expect(try eval(complex + "(i * i * i * i) == one") == .bool(true))
        #expect(try eval(complex + "Complex(3.0, 4.0).abs") == .double(5))
        #expect(throws: SwiftalkError.self) { try eval(complex + "one - i") }              // not implemented: the builtin meaning's type error
        #expect(throws: SwiftalkError.self) { try eval(complex + "one / i") }
        #expect(throws: SwiftalkError.self) { try eval(complex + "one < i") }
        #expect(throws: SwiftalkError.self) { try eval(complex + "!one") }
        #expect(throws: SwiftalkError.self) { try eval(complex + "one ** i") }
        #expect(throws: SwiftalkError.self) { try eval(complex + "one + 1.0") }             // the closure's own error: 1.0.real
    }

    @Test("either operand's type answers, so 2 * z and z * 2 both reach the type; ** and the Set operators are implementable")
    func mixedOperands() throws {
        let scaled = """
            struct V { var x: Int = 0
                infix(*) = { a, b in
                    if a.Type == Int { return V(a * b.x) }
                    if b.Type == Int { return V(a.x * b) }
                    return V(a.x * b.x)
                }
                infix(**) = { a, n in V(a.x ** n) }
                infix(|) = { a, b in V(a.x.bitOr(b.x)) }
            }

            """
        #expect(try eval(scaled + "(2 * V(3)).x") == .int(6))
        #expect(try eval(scaled + "(V(3) * 2).x") == .int(6))
        #expect(try eval(scaled + "(V(3) * V(4)).x") == .int(12))
        #expect(try eval(scaled + "(V(2) ** 10).x") == .int(1024))
        #expect(try eval(scaled + "(V(1) | V(2)).x") == .int(3))
        #expect(try eval(scaled + "2 * 3") == .int(6))                                       // builtins untouched
    }

    @Test("comparison: == overrides the synthesized one; != is derived from ==; > <= >= from <; sorted(), min(), max(), Comparable follow")
    func comparisons() throws {
        let money = """
            struct Money {
                var cents: Int = 0
                infix(<) = { a, b in a.cents < b.cents }
            }
            struct Approx {
                var v: Double = 0.0
                infix(==) = { a, b in (a.v - b.v) ** 2.0 < 0.0001 }
            }

            """
        #expect(try eval(money + "Money(1) < Money(2)") == .bool(true))
        #expect(try eval(money + "Money(2) > Money(1)") == .bool(true))
        #expect(try eval(money + "Money(1) <= Money(1) && Money(2) >= Money(1) && !(Money(1) >= Money(2))") == .bool(true))
        #expect(try eval(money + "[Money(3), Money(1), Money(2)].sorted().map { $0.cents }") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval(money + "[Money(3), Money(1)].min().cents") == .int(1))
        #expect(try eval(money + "[Money(3), Money(1)].max().cents") == .int(3))
        #expect(try eval(money + "Money.conforms(to: Comparable)") == .bool(true))
        #expect(try eval(money + "Approx.conforms(to: Comparable)") == .bool(false))
        #expect(try eval(money + "Approx(1.0) == Approx(1.000001)") == .bool(true))
        #expect(try eval(money + "Approx(1.0) != Approx(1.000001)") == .bool(false))          // != derived from ==
        #expect(try eval(money + "Approx(1.0) === Approx(1.000001)") == .bool(false))         // identity is not overridable
        #expect(try eval(money + "Money(1) == Money(1)") == .bool(true))                      // synthesized == still
        #expect(try eval(money + "Money(1) != Money(2)") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("struct B { var x: Int = 0; infix(<) = { a, b in 1 } }\nB(1) > B(2)") }   // must return a Bool
    }

    @Test("enums, extensions, postfix, Self, and :r; refusals")
    func enumsExtensionsErrors() throws {
        let sign = "enum Sign { case plus, minus; prefix(-) = { s in s == Sign.plus ? Sign.minus : Sign.plus }; postfix(!) = { s in s == Sign.plus ? 1 : -1 } }\n"
        #expect(try eval(sign + "-Sign.plus == Sign.minus") == .bool(true))
        #expect(try eval(sign + "Sign.minus!") == .int(-1))
        #expect(try eval(sign + "(-Sign.minus)!") == .int(1))
        #expect(try eval(complex + "extension Complex { infix(-) = { a, b in a + (-b) } }\n(one - i) == Complex(1.0, -1.0)") == .bool(true))
        #expect(try eval(complex + "extension Complex { postfix(?) = { z in z.real } }\ni?") == .double(0))
        #expect(throws: SwiftalkError.self) { try eval(complex + "extension Complex { infix(+) = { a, b in a } }") }   // already implemented
        let i = Swiftalk.Interpreter(relaxed: true)
        _ = try i.eval(complex)
        _ = try i.redefine("extension Complex { infix(+) = { a, b in Self(a.real + b.real, 0.0) } }")
        #expect(try i.eval("(one + i).imag") == .double(0))
        #expect(throws: SwiftalkError.self) { try eval("struct S { infix(&&) = { a, b in a } }") }
        #expect(throws: SwiftalkError.self) { try eval("struct S { infix(??) = { a, b in a } }") }
        #expect(throws: SwiftalkError.self) { try eval("struct S { infix(===) = { a, b in true } }") }
        #expect(throws: SwiftalkError.self) { try eval("struct S { prefix(*) = { a in a } }") }
        #expect(throws: SwiftalkError.self) { try eval("struct S { postfix(-) = { a in a } }") }
        #expect(throws: SwiftalkError.self) { try eval("struct S { infix(+) = 1 }") }
        #expect(throws: SwiftalkError.self) { try eval("struct S { infix(+) = { a in a } }") }          // two parameters
        #expect(throws: SwiftalkError.self) { try eval("struct S { infix(+) = { a, b in a }; infix(+) = { a, b in b } }") }
        #expect(throws: SwiftalkError.self) { try eval("extension Int { infix(+) = { a, b in 0 } }") }   // builtins keep theirs
        #expect(throws: SwiftalkError.self) { try eval("struct S { static infix(+) = { a, b in a } }") } // no static: always the type's
        #expect(throws: SwiftalkError.self) { try eval("struct S { infix + = { a, b in a } }") }
    }
}
