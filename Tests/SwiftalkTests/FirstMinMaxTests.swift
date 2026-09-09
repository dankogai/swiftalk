import Testing
@testable import Swiftalk

@Suite("first, min(), max() on every Sequence conformer (round 139)")
struct FirstMinMaxTests {
    @Test("first: the first element or nil, on Array, String, Range, Dictionary, Set, Data, Tuple, and a lazy Sequence — one pull")
    func first() throws {
        #expect(try eval("[3, 1, 2].first") == .int(3))
        #expect(try eval("[].first") == .nil)
        #expect(try eval("\"héllo\".first") == .string("h"))
        #expect(try eval("\"\".first == nil") == .bool(true))
        #expect(try eval("(5...9).first") == .int(5))
        #expect(try eval("(0...).first") == .int(0))                                            // infinite: one pull is enough
        #expect(try eval("[\"a\": 1].first") == .tuple([.string("a"), .int(1)], labels: ["key", "value"]))
        #expect(try eval("[:].first == nil") == .bool(true))
        #expect(try eval("Set(7).first") == .int(7))
        #expect(try eval("Set(1, 2, 3).first.Type == Int") == .bool(true))
        #expect(try eval("Set().first == nil") == .bool(true))
        #expect(try eval("Data(\"AQID\").first") == .byte(1))
        #expect(try eval("(1, \"a\").first") == .int(1))
        #expect(try eval("let n = Sequence { var i = 10; while true { yield i; i = i + 1 } }\nn.first") == .int(10))
        #expect(try eval("[1, 2].map { $0 * 10 }.first") == .int(10))
        #expect(try eval("let xs = [1, 2]\nlet f = xs.first\nf + 1") == .int(2))
        #expect(throws: SwiftalkError.self) { try eval("[1].first()") }                          // a property, as in Swift
        #expect(throws: SwiftalkError.self) { try eval("1.first") }
    }

    @Test("min() and max(): Comparable elements, nil when empty, an error for anything else; min(by:) with a Function")
    func minMax() throws {
        #expect(try eval("[3, 1, 2].min()") == .int(1))
        #expect(try eval("[3, 1, 2].max()") == .int(3))
        #expect(try eval("[].min() == nil") == .bool(true))
        #expect(try eval("[].max() == nil") == .bool(true))
        #expect(try eval("[2.5, -1.0].min()") == .double(-1))
        #expect(try eval("[\"pear\", \"apple\", \"fig\"].max()") == .string("pear"))
        #expect(try eval("\"hello\".min()") == .string("e"))
        #expect(try eval("(5...9).max()") == .int(9))
        #expect(try eval("Set(3, 1, 2).min()") == .int(1))
        #expect(try eval("Set(3, 1, 2).max()") == .int(3))
        #expect(try eval("Data(\"AQID\").max()") == .byte(3))
        #expect(try eval("[1, Byte(9), 3].max()") == .byte(9))                                   // Byte and Int compare by value
        #expect(try eval("[.Date(1.0), .Date(0.0)].min()") == .date(0))
        #expect(try eval("[1, 2].map { $0 * 10 }.max()") == .int(20))
        #expect(try eval("(1...5).filter { $0 > 2 }.min()") == .int(3))
        #expect(try eval("[\"bb\", \"a\", \"ccc\"].min { $0.count < $1.count }") == .string("a"))
        #expect(try eval("[\"bb\", \"a\", \"ccc\"].max(by: { $0.count < $1.count })") == .string("ccc"))
        #expect(try eval("[\"a\": 3, \"b\": 1].min { $0.value < $1.value }.key") == .string("b"))   // pairs, by a Function
        #expect(try eval("[(1, \"x\"), (1, \"y\")].min { $0.0 < $1.0 }") == .tuple([.int(1), .string("x")]))   // min keeps the first of equals…
        #expect(try eval("[(1, \"x\"), (1, \"y\")].max { $0.0 < $1.0 }") == .tuple([.int(1), .string("y")]))   // …max the last, as Swift's
        #expect(throws: SwiftalkError.self) { try eval("[(1, 2), (3, 4)].min()") }               // tuples are not Comparable
        #expect(throws: SwiftalkError.self) { try eval("[\"a\": 1].max()") }
        #expect(throws: SwiftalkError.self) { try eval("[[1], [2]].min()") }
        #expect(throws: SwiftalkError.self) { try eval("[1, \"a\"].min()") }                    // mixed: <'s type error
        #expect(throws: SwiftalkError.self) { try eval("[true, false].max()") }
        #expect(throws: SwiftalkError.self) { try eval("(0...).min()") }                         // infinite
        #expect(throws: SwiftalkError.self) { try eval("[1].min(1)") }
        #expect(throws: SwiftalkError.self) { try eval("[1, 2].min { 1 }") }                    // the Function must return a Bool
        #expect(try eval("[1].min { 1 }") == .int(1))                                             // …but one element asks nothing of it, as Swift's
        #expect(throws: SwiftalkError.self) { try eval("[(1, 2)].min()") }                       // a lone non-Comparable is still refused
        #expect(try eval("[7].max()") == .int(7))
        #expect(throws: SwiftalkError.self) { try eval("1.max()") }
        #expect(throws: SwiftalkError.self) { try eval("[1].min") }                               // methods, as in Swift
    }
}
