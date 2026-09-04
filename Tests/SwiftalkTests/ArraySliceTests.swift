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
