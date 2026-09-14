import Testing
@testable import Swiftalk

/// Round 156: `label: for|while|repeat`, `break label`, `continue label`
/// (Swift's spelling); and `.forEach { }`, the eager walk that `_ =
/// s.map { }` is not on a lazy Sequence.
@Suite("loop labels and forEach (round 156)")
struct LoopLabelTests {
    @Test("break label and continue label reach the named loop through the inner ones")
    func labels() throws {
        #expect(try eval("""
            var out = []
            outer: for i in 1...3 {
                for j in 1...3 {
                    if j == 2 { continue outer }
                    if i == 3 { break outer }
                    out.append([i, j])
                }
            }
            out
            """) == .array([.array([.int(1), .int(1)]), .array([.int(2), .int(1)])]))
        #expect(try eval("""
            var n = 0
            loop: while true {
                n += 1
                repeat {
                    if n > 3 { break loop }
                    n += 10
                } while false
            }
            n
            """) == .int(12))
        #expect(try eval("""
            var k = 0
            again: repeat {
                k += 1
                for x in 0... { if x == 2 { continue again }; if k > 2 { break again } }
            } while true
            k
            """) == .int(3))
        #expect(try eval("""
            var m = 0
            found: for row in [[1, 2], [3, 4]] { for v in row where v == 3 { m = v; break found } }
            m
            """) == .int(3))
        #expect(try eval("""
            var s = 0
            w: while let x = [1, 2, 3].first { for y in 1...3 { if y == 2 { break w }; s += x * y } }
            s
            """) == .int(1))
        #expect(try eval("var c = 0\nouter: for i in 0..<3 { for j in 0..<3 { if j == 1 { break }; c += 1 } }\nc") == .int(3))   // bare break: the innermost, as ever
        #expect(try eval("var c = 0\nouter: for i in 0..<3 { for j in 0..<3 { if j == 1 { continue }; c += 1 } }\nc") == .int(6))
        #expect(try eval("var c = 0\nouter: for i in 0..<3 { c += 1; break outer }\nc") == .int(1))      // a label on the loop broken directly
    }

    @Test("a label is checked at parse time: unknown, out of scope, or reused in a nested loop")
    func labelErrors() throws {
        #expect(throws: SwiftalkError.self) { try eval("for i in 0..<2 { break outer }") }
        #expect(throws: SwiftalkError.self) { try eval("outer: for i in 0..<2 { }\nbreak outer") }
        #expect(throws: SwiftalkError.self) { try eval("outer: for i in 0..<2 { outer: for j in 0..<2 { } }") }
        #expect(throws: SwiftalkError.self) { try eval("outer: for i in 0..<2 { let f = { break outer } }") }   // a closure is not a loop
        #expect(try eval("a: for i in 0..<1 { }\na: for j in 0..<1 { }\n1") == .int(1))                  // sequential reuse is fine
        #expect(try eval("let outer = 1\nouter: for i in 0..<1 { }\nouter") == .int(1))                   // labels and names do not clash
        #expect(try eval("let t = true ? 1 : 2\nt") == .int(1))                                            // a ternary's colon is not a label
    }

    @Test("forEach: eager, nil, each element as map sees it; no break inside")
    func forEach() throws {
        #expect(try eval("var n = 0\n[1, 2, 3].forEach { n += $0 }\nn") == .int(6))
        #expect(try eval("var n = 0\nSequence { yield 1; yield 2 }.forEach { n += $0 }\nn") == .int(3))     // eager where map would defer
        #expect(try eval("var n = 0\nlet _ = Sequence { yield 1; yield 2 }.map { n += $0 }\nn") == .int(0))     // the reason forEach exists
        #expect(try eval("[1, 2].forEach { $0 }") == .nil)
        #expect(try eval("var s = \"\"\n\"hi\".forEach { s = $0 + s }\ns") == .string("ih"))
        #expect(try eval("var s = 0\n[\"a\": 1, \"b\": 2].forEach { k, v in s += v }\ns") == .int(3))
        #expect(try eval("var s = 0\n(1...4).forEach { s += $0 }\ns") == .int(10))
        #expect(try eval("var s = 0\nSet(1, 2).forEach { s += $0 }\ns") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval("[1].forEach { break }") }
        #expect(throws: SwiftalkError.self) { try eval("[1].forEach(1)") }
    }
}
