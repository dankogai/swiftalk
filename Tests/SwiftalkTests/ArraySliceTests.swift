import Testing
@testable import Swiftalk

@Suite("a[1..<3], a[1...2], a[1...] — Range subscripts on Arrays (round 90)")
struct ArraySliceTests {
    let a = "let a = [10, 20, 30, 40, 50]\n"

    @Test("half-open, closed, and unbounded ranges slice; the result is a new Array")
    func slices() throws {
        #expect(try eval(a + "a[1..<3]") == .array([.int(20), .int(30)]))
        #expect(try eval(a + "a[1...2]") == .array([.int(20), .int(30)]))
        #expect(try eval(a + "a[3...]") == .array([.int(40), .int(50)]))
        #expect(try eval(a + "a[0...4]") == .array([10, 20, 30, 40, 50].map { .int($0) }))
        #expect(try eval(a + "a[1...][0]") == .int(20))
        #expect(try eval(a + "let r = 1...3\na[r]") == .array([20, 30, 40].map { .int($0) }))
        #expect(try eval(a + "a[1..<3].Type == Array") == .bool(true))
        #expect(try eval("[[\"x\", \"y\"], [\"z\"]][0..<1]") == .array([.array([.string("x"), .string("y")])]))
        // a value, not a view: the source is untouched
        #expect(try eval(a + "var b = a[1...2]\nb.append(0)\na") == .array([10, 20, 30, 40, 50].map { .int($0) }))
    }

    @Test("Swift's bounds rule: 0 ≤ from ≤ to ≤ count — a[count...] and a[2..<2] are empty, past the end is an error")
    func bounds() throws {
        #expect(try eval(a + "a[5...]") == .array([]))
        #expect(try eval(a + "a[2..<2]") == .array([]))
        #expect(try eval(a + "a[5..<5]") == .array([]))
        #expect(throws: SwiftalkError.self) { try eval(a + "a[1...5]") }
        #expect(throws: SwiftalkError.self) { try eval(a + "a[6...]") }
        #expect(throws: SwiftalkError.self) { try eval(a + "a[-1...1]") }
        #expect(throws: SwiftalkError.self) { try eval(a + "a[0...9223372036854775807]") }
        // reading only: a Range is not an assignment target (OPEN)
        #expect(throws: SwiftalkError.self) { try eval(a + "a[0..<1] = [9]") }
        #expect(throws: SwiftalkError.self) { try eval(a + "a[\"x\"]") }
    }
}

@Suite("a[0..<1] = [9] — assignment through a Range subscript (round 91)")
struct ArraySliceAssignTests {
    @Test("replaceSubrange: the slice grows, shrinks, or vanishes to fit the right side; a[count...] = xs appends")
    func replace() throws {
        #expect(try eval("var a = [10, 20, 30]\na[0..<1] = [9]\na") == .array([9, 20, 30].map { .int($0) }))
        #expect(try eval("var a = [10, 20, 30]\na[1...2] = [1, 2, 3, 4]\na") == .array([10, 1, 2, 3, 4].map { .int($0) }))
        #expect(try eval("var a = [10, 20, 30]\na[1...] = []\na") == .array([.int(10)]))
        #expect(try eval("var a = [10, 20, 30]\na[a.count...] = [7, 8]\na") == .array([10, 20, 30, 7, 8].map { .int($0) }))
        #expect(try eval("var a = [10, 20, 30]\na[0...] = [0]\na") == .array([.int(0)]))
        #expect(try eval("var a = [10, 20, 30]\na[1..<1] = [5]\na") == .array([10, 5, 20, 30].map { .int($0) }))
        #expect(try eval("var m = [[1], [2], [3]]\nm[0..<2] = [[9]]\nm") == .array([.array([.int(9)]), .array([.int(3)])]))
        #expect(try eval("var s: [Any] = [1, \"a\"]\ns[1...] = [2.5, true]\ns")
                == .array([.int(1), .double(2.5), .bool(true)]))
        // a nested path
        #expect(try eval("var d = [\"k\": [1, 2, 3]]\nd[\"k\"][1...] = [0]\nd[\"k\"]") == .array([.int(1), .int(0)]))
    }

    @Test("the right side must be an Array of the variable's element type; bounds as for reading")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2, 3]\na[0..<1] = [\"x\"]") }
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2, 3]\na[0..<1] = [1, \"x\"]") }
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2, 3]\na[0..<1] = 5") }
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2, 3]\na[2...5] = [1]") }
        #expect(throws: SwiftalkError.self) { try eval("var a = [1, 2, 3]\na[4...] = [1]") }
        #expect(throws: SwiftalkError.self) { try eval("let a = [1, 2, 3]\na[0..<1] = [9]") }   // a let stays a let
        // a failed write leaves the Array untouched
        #expect(try eval("var a = [1, 2, 3]\nvar r = \"\"\nif x = Result.failure(0).failure { }\na")
                == .array([1, 2, 3].map { .int($0) }))
    }
}
