import Testing
@testable import Swiftalk

@Suite("let name(x:y:) { body } — labels are the bindings (§2.4, round 58a)")
struct DeclSugarTests {
    @Test("labels bind straight into the body; call by label, order, or position")
    func basics() throws {
        let hyp = "let hypotenuse(x:y:) { x * x + y * y }"
        #expect(try eval("\(hyp)\nhypotenuse(x: 3, y: 4)") == .int(25))
        #expect(try eval("\(hyp)\nhypotenuse(y: 4, x: 3)") == .int(25))
        #expect(try eval("\(hyp)\nhypotenuse(3, 4)") == .int(25))
        // pure sugar: it IS the one function form, and echoes as such
        #expect(try eval("\(hyp)\nhypotenuse.String()") == .string("{ x, y in ... }"))
        #expect(try eval("\(hyp)\nhypotenuse.Type == Function") == .bool(true))
    }

    @Test("empty labels = variadic (round 17); $ still works inside")
    func variadic() throws {
        #expect(try eval("let count() { $.count }\ncount(1, 2, 3)") == .int(3))
    }

    @Test("the bonus: named recursion without .todo")
    func namedRecursion() throws {
        #expect(try eval("""
            let fact(n:) { n < 2 ? 1 : n * fact(n: n - 1) }
            fact(n: 20)
            """) == .int(2432902008176640000))
    }

    @Test("guards: arity still strict; duplicate labels refused")
    func guards() throws {
        #expect(throws: SwiftalkError.self) {
            try eval("let f(x:y:) { x + y }\nf(1)")
        }
        #expect(throws: SwiftalkError.self) {
            try eval("let f(x:x:) { x }")
        }
    }
}
