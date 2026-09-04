import Testing
@testable import Swiftalk

@Suite("the slicing family: suffix, dropFirst, dropLast, split — Swift's names and shapes (round 89)")
struct SlicingTests {
    @Test("Array: n clamps; dropFirst()/dropLast() default to 1")
    func arrays() throws {
        #expect(try eval("[1, 2, 3, 4, 5].suffix(2)") == .array([.int(4), .int(5)]))
        #expect(try eval("[1, 2, 3, 4, 5].dropFirst()") == .array([2, 3, 4, 5].map { .int($0) }))
        #expect(try eval("[1, 2, 3, 4, 5].dropFirst(2)") == .array([3, 4, 5].map { .int($0) }))
        #expect(try eval("[1, 2, 3, 4, 5].dropLast()") == .array([1, 2, 3, 4].map { .int($0) }))
        #expect(try eval("[1, 2, 3, 4, 5].dropLast(2)") == .array([1, 2, 3].map { .int($0) }))
        #expect(try eval("[1, 2].suffix(5)") == .array([.int(1), .int(2)]))
        #expect(try eval("[1, 2].dropFirst(5)") == .array([]))
        #expect(try eval("[1, 2].dropLast(5)") == .array([]))
        #expect(try eval("[1, 2, 3].prefix(2)") == .array([.int(1), .int(2)]))
        // the source is untouched
        #expect(try eval("let a = [1, 2, 3]\nlet b = a.dropFirst()\na") == .array([1, 2, 3].map { .int($0) }))
    }

    @Test("shaped like the receiver: a String's slices are Strings — prefix too (revising round 41)")
    func strings() throws {
        #expect(try eval("\"héllo\".prefix(2)") == .string("hé"))
        #expect(try eval("\"héllo\".suffix(2)") == .string("lo"))
        #expect(try eval("\"héllo\".dropFirst()") == .string("éllo"))
        #expect(try eval("\"héllo\".dropLast(2)") == .string("hél"))
        #expect(try eval("\"héllo\".prefix(2).Type == String") == .bool(true))
        #expect(try eval("(1...5).suffix(2)") == .array([.int(4), .int(5)]))
        #expect(try eval("(1...5).dropFirst(3)") == .array([.int(4), .int(5)]))
        #expect(try eval("[\"a\": 1, \"b\": 2].dropFirst().count") == .int(1))
    }

    @Test("lazy: dropFirst defers on a Sequence and on a...; suffix and dropLast need the end")
    func lazy() throws {
        #expect(try eval("(0...).dropFirst(3).prefix(2)") == .array([.int(3), .int(4)]))
        #expect(try eval("(0...).dropFirst(3).Type == Sequence") == .bool(true))
        #expect(try eval("""
            let fib = Sequence { var a = 0; var b = 1; while true { yield a; (a, b) = (b, a + b) } }
            fib.dropFirst(5).prefix(3)
            """) == .array([5, 8, 13].map { .int($0) }))
        #expect(try eval("Sequence { yield 1; yield 2; yield 3 }.suffix(2)") == .array([.int(2), .int(3)]))
        #expect(try eval("Sequence { yield 1; yield 2; yield 3 }.dropLast()") == .array([.int(1), .int(2)]))
        #expect(throws: SwiftalkError.self) { try eval("(0...).suffix(2)") }
        #expect(throws: SwiftalkError.self) { try eval("(0...).dropLast()") }
    }

    @Test("split on every conformer: a value or a predicate as the separator; empty pieces omitted; labels accepted")
    func split() throws {
        #expect(try eval("[1, 0, 2, 0, 0, 3].split(0)")
                == .array([.array([.int(1)]), .array([.int(2)]), .array([.int(3)])]))
        #expect(try eval("[1, 0, 2].split(separator: 0)") == .array([.array([.int(1)]), .array([.int(2)])]))
        #expect(try eval("[1, 2, 3, 4, 5].split { $0 / 2 * 2 == $0 }")
                == .array([.array([.int(1)]), .array([.int(3)]), .array([.int(5)])]))
        #expect(try eval("[1, 2, 3].split(whereSeparator: { $0 == 2 })") == .array([.array([.int(1)]), .array([.int(3)])]))
        #expect(try eval("(1...7).split(4)") == .array([.array([1, 2, 3].map { .int($0) }), .array([5, 6, 7].map { .int($0) })]))
        #expect(try eval("\"a b  c\".split { $0 == \" \" }") == .array(["a", "b", "c"].map(Value.string)))
        #expect(try eval("\"a, b,,c\".split(/,\\s*/)") == .array(["a", "b", "c"].map(Value.string)))
        #expect(try eval("[].split(0)") == .array([]))
        #expect(try eval("[0, 0].split(0)") == .array([]))
        #expect(throws: SwiftalkError.self) { try eval("(0...).split(0)") }
    }

    @Test("arguments: non-negative Ints, one at most; a split predicate must return a Bool")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].suffix(-1)") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].suffix()") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].dropFirst(1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].dropLast(\"x\")") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].split(1, 2)") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].split { 1 }") }
    }
}
