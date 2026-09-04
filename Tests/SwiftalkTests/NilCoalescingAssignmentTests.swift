import Testing
@testable import Swiftalk

@Suite("??= — assign only when absent (round 103)")
struct NilCoalescingAssignmentTests {
    @Test("writes when nil, leaves a present value alone, and does not evaluate the right side then")
    func basics() throws {
        #expect(try eval("var s: String? = nil\ns ??= \"a\"\ns ??= \"b\"\ns") == .string("a"))
        #expect(try eval("var d = [\"a\": 1]\nd[\"b\"] ??= 0\nd[\"a\"] ??= 99\nd")
                == .dictionary([.string("a"): .int(1), .string("b"): .int(0)]))
        #expect(try eval("""
            var calls = 0
            let make = { calls += 1; return 7 }
            var x: Int? = 5
            x ??= make()
            var y: Int? = nil
            y ??= make()
            [x, y, calls]
            """) == .array([.int(5), .int(7), .int(1)]))
        #expect(try eval("var m: [[Int?]] = [[nil], [2]]\nm[0][0] ??= 9\nm") == .array([.array([.int(9)]), .array([.int(2)])]))
        #expect(try eval("var x: Int? = 5\nx ??= 3") == .int(5))       // its value: what the target holds after
        #expect(try eval("var x: Int? = nil\nx ??= 3") == .int(3))
    }

    @Test("a Result failure is absent too, as for ??; the lock still holds; a let refuses; a statement")
    func rules() throws {
        #expect(try eval("var r = Result.failure(\"e\")\nr ??= Result.success(1)\nr.success") == .int(1))
        #expect(try eval("var r = Result.success(2)\nr ??= Result.success(1)\nr.success") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("var r = Result.failure(\"e\")\nr ??= 0") }   // a Result takes a Result
        #expect(throws: SwiftalkError.self) { try eval("var n: Int? = nil\nn ??= \"s\"") }
        #expect(throws: SwiftalkError.self) { try eval("let k: Int? = nil\nk ??= 1") }
        #expect(throws: SwiftalkError.self) { try eval("var a: Int? = nil\nlet v = a ??= 1") }
        #expect(throws: SwiftalkError.self) { try eval("q ??= 1") }
        let repl = Swiftalk.Interpreter(relaxed: true)
        #expect(try repl.eval("var z: Int? = nil\nz ??=\n4\nz") == .int(4))            // a trailing ??= continues
        #expect(try repl.eval("nil ?? 1") == .int(1))                                  // ?? itself is untouched
    }
}
