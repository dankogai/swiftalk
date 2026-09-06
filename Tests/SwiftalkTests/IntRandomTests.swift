import Testing
@testable import Swiftalk

@Suite("Int.random(in:) (round 109); Int.random(), (to:), (from:to:) (round 119)")
struct IntRandomTests {
    @Test("a Range's worth of Ints, closed or half-open; the in: label optional; a Function value uncalled")
    func random() throws {
        #expect(try eval("(1...300).map { Int.random(in: 1...6) }.filter { $0 < 1 || $0 > 6 }.count") == .int(0))
        #expect(try eval("(1...300).map { Int.random(0..<3) }.filter { $0 < 0 || $0 > 2 }.count") == .int(0))
        #expect(try eval("(1...300).map { Int.random(in: 1...6) }.contains(6)") == .bool(true))
        #expect(try eval("(1...300).map { Int.random(0..<3) }.contains(2)") == .bool(true))
        #expect(try eval("Int.random(in: 5...5)") == .int(5))
        #expect(try eval("Int.random(in: -3...(-3))") == .int(-3))
        #expect(try eval("let f = Int.random\nf(7...7)") == .int(7))
        #expect(try eval("Int.random.Type == Function") == .bool(true))
        #expect(try eval("Int.random(in: 1...6).Type == Int") == .bool(true))
    }

    @Test("an empty or unbounded Range, or anything but a Range, is an error; Double has no Range to give")
    func errors() throws {
        #expect(throws: SwiftalkError.self) { try eval("Int.random(in: 1..<1)") }
        #expect(throws: SwiftalkError.self) { try eval("Int.random(in: 0...)") }
        #expect(throws: SwiftalkError.self) { try eval("Int.random(to: 1...6)") }        // a Range is in:, not to:
        #expect(throws: SwiftalkError.self) { try eval("Int.random(from: 1...6)") }
        #expect(throws: SwiftalkError.self) { try eval("Double.random(in: 1...6)") }   // Double's bounds are arguments (round 112)
    }

    @Test("random() in [0, 1], random(to:) in [0, to], random(from:to:) in [from, to] — closed (round 119); labels optional, wrong ones errors")
    func bounds() throws {
        #expect(try eval("(1...100).map { Int.random() }.filter { $0 != 0 && $0 != 1 }.count") == .int(0))
        #expect(try eval("(1...100).map { Int.random() }.contains(1)") == .bool(true))
        #expect(try eval("(1...300).map { Int.random(to: 6) }.filter { $0 < 0 || $0 > 6 }.count") == .int(0))
        #expect(try eval("(1...300).map { Int.random(to: 6) }.contains(6)") == .bool(true))
        #expect(try eval("(1...300).map { Int.random(from: -2, to: 2) }.filter { $0 < -2 || $0 > 2 }.count") == .int(0))
        #expect(try eval("(1...300).map { Int.random(from: -2, to: 2) }.contains(-2)") == .bool(true))
        #expect(try eval("Int.random(from: 5, to: 5)") == .int(5))
        #expect(try eval("Int.random(to: 0)") == .int(0))
        #expect(try eval("Int.random(from: Int.min, to: Int.max).Type == Int") == .bool(true))    // the whole line, closed
        #expect(try eval("Int.random(from: Int.max, to: Int.max) == Int.max") == .bool(true))
        #expect(try eval("Int.random(3, 3)") == .int(3))                                          // positional is (from, to)
        #expect(try eval("Int.random(Byte(4), Byte(4))") == .int(4))
        #expect(try eval("let f = Int.random\nf(9, 9)") == .int(9))
        #expect(throws: SwiftalkError.self) { try eval("Int.random(from: 3, to: 1)") }
        #expect(throws: SwiftalkError.self) { try eval("Int.random(to: -1)") }
        #expect(throws: SwiftalkError.self) { try eval("Int.random(to: 1, from: 0)") }
        #expect(throws: SwiftalkError.self) { try eval("Int.random(max: 6)") }
        #expect(throws: SwiftalkError.self) { try eval("Int.random(1, 2, 3)") }
        #expect(throws: SwiftalkError.self) { try eval("Int.random(to: 1.5)") }
    }
}
