import Testing
@testable import Swiftalk

@Suite("while let: the drain loop, sharing if let's condition list (round 76)")
struct WhileLetTests {
    @Test("loops while the binding lands non-nil, fresh each iteration")
    func drain() throws {
        #expect(try eval("""
            let d = [0: "a", 1: "b", 2: "c"]
            var i = 0
            var out = ""
            while let x = d[i] { out = out + x; i = i + 1 }
            out
            """) == .string("abc"))
        #expect(try eval("var n = 0\nwhile let x = nil { n = n + 1 }\nn") == .int(0))
    }

    @Test("comma chains, while var, patterns, break/continue")
    func forms() throws {
        #expect(try eval("""
            let d = [0: 1, 1: 2, 2: 3, 3: 4]
            var i = 0
            var sum = 0
            while let x = d[i], x < 4 { sum = sum + x; i = i + 1 }
            sum
            """) == .int(6))
        #expect(try eval("""
            let d = [0: 5]
            var i = 0
            var got = 0
            while var x = d[i] { x = x * 2; got = x; i = i + 1 }
            got
            """) == .int(10))
        #expect(try eval("""
            let d = [0: (k: "a", v: 1), 1: (k: "b", v: 2)]
            var i = 0
            var out = ""
            while let (v: v, k: k) = d[i] { out = out + "\\(k)\\(v)"; i = i + 1 }
            out
            """) == .string("a1b2"))
        #expect(try eval("""
            let d = [0: 1, 1: 2, 2: 3, 3: 4, 4: 5]
            var i = 0
            var out = []
            while let x = d[i] {
                i = i + 1
                if x == 2 { continue }
                if x == 4 { break }
                out.append(x)
            }
            out
            """) == .array([.int(1), .int(3)]))
        #expect(throws: SwiftalkError.self) { try eval("while let x = 1, 2 { }") }
    }

    @Test("plain while is untouched; a lone boolean still parses to it")
    func plainWhile() throws {
        #expect(try eval("var n = 0\nwhile n < 3 { n = n + 1 }\nn") == .int(3))
        #expect(throws: SwiftalkError.self) { try eval("while 1 { }") }
    }
}
