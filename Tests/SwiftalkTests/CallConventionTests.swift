import Testing
@testable import Swiftalk

@Suite("the call convention, simplified (§2.3/§2.4, round 61)")
struct CallConventionTests {
    @Test("one function notation: { x, y in }; labels optional, reorderable")
    func oneNotation() throws {
        let f = "let f = { x, y in x * x + y * y }"
        #expect(try eval("\(f)\nf(x: 3, y: 4)") == .int(25))
        #expect(try eval("\(f)\nf(y: 4, x: 3)") == .int(25))
        #expect(try eval("\(f)\nf(3, 4)") == .int(25))          // omitted = positional
        #expect(try eval("\(f)\nf(3, y: 4)") == .int(25))       // mixed fills in order
        // round 61 REVERTED round 58a: the (x:y:) declaration notation
        // is gone — swiftalk was getting too close to Swift
        #expect(throws: SwiftalkError.self) { try eval("let g(x:y:) { x + y }") }
    }

    @Test("_ parameters are positional-only: no label, no binding, $N only")
    func wildcardParameters() throws {
        let g = #"let g = { _, x, y in "\($0) \(x) \(y)" }"#
        #expect(try eval("\(g)\ng(5, x: 4, y: 3)") == .string("5 4 3"))
        #expect(try eval("\(g)\ng(5, y: 3, x: 4)") == .string("5 4 3"))
        #expect(try eval("\(g)\ng(5, 4, 3)") == .string("5 4 3"))
        // `_` repeats; named parameters may not
        #expect(try eval(#"let h = { _, _, z in "\($0)\($1)\(z)" }"# + "\nh(1, 2, 3)")
            == .string("123"))
        #expect(throws: SwiftalkError.self) { try eval("let h = { x, x in x }") }
        // no label reaches a `_` slot — and `_` itself is not a label
        #expect(throws: SwiftalkError.self) { try eval("\(g)\ng(_: 5, x: 4, y: 3)") }
    }

    @Test("undefined labels raise; arity stays strict")
    func undefinedLabels() throws {
        let f = "let f = { x, y in x + y }"
        #expect(throws: SwiftalkError.self) { try eval("\(f)\nf(x: 1, z: 2)") }
        #expect(throws: SwiftalkError.self) { try eval("\(f)\nf(1)") }
        #expect(throws: SwiftalkError.self) { try eval("let v = { $0 }\nv(tag: 1)") }
    }

    @Test("multi-dispatch is for Type inits, and Type inits only")
    func multiDispatchOnlyInits() throws {
        // one name, one function (round 3): a second declaration of f
        // is an error, not an overload set
        #expect(throws: SwiftalkError.self) {
            try eval("let f = { x in x }\nlet f = { x, y in x + y }")
        }
        // ...while a type's inits still multi-dispatch (round 48)
        #expect(try eval("""
            struct P { var x: Int = 0
            var y: Int = 0
            init { v in self.x = v
            self.y = v }
            }
            [P(7).y, P(x: 1, y: 2).y]
            """) == .array([.int(7), .int(2)]))
    }
}
