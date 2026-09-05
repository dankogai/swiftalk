import Testing
@testable import Swiftalk

@Suite("Int.random(in:) (round 109)")
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
        #expect(throws: SwiftalkError.self) { try eval("Int.random(6)") }
        #expect(throws: SwiftalkError.self) { try eval("Int.random()") }
        #expect(throws: SwiftalkError.self) { try eval("Int.random(to: 1...6)") }
        #expect(throws: SwiftalkError.self) { try eval("Double.random(in: 1...6)") }   // Double's bounds are arguments (round 112)
    }
}
