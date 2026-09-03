import Testing
@testable import Swiftalk

@Suite("a... — the unbounded range (round 88)")
struct UnboundedRangeTests {
    @Test("literal, source form, type, subscript, containment; lazy through map/filter/enumerated/prefix")
    func basics() throws {
        #expect(try eval("(0...).String()") == .string("0..."))
        #expect(try eval("let r = 0...\nr.Type == Range") == .bool(true))
        #expect(try eval("(0...).prefix(5)") == .array([0, 1, 2, 3, 4].map { .int($0) }))
        #expect(try eval("(1...)[3]") == .int(4))
        #expect(try eval("(0...).contains(7)") == .bool(true))
        #expect(try eval("(0...).map { $0 * $0 }.prefix(4)") == .array([0, 1, 4, 9].map { .int($0) }))
        #expect(try eval("(0...).filter { $0 / 2 * 2 == $0 }.prefix(3)") == .array([0, 2, 4].map { .int($0) }))
        #expect(try eval("(0...).enumerated().prefix(1)")
                == .array([.tuple([.int(0), .int(0)], labels: ["offset", "element"])]))
        #expect(try eval("var s = 0\nfor i in 10... { if i > 12 { break }; s = s + i }\ns") == .int(33))
        #expect(try eval("switch 42 { case 40...: \"big\" default: \"small\" }") == .string("big"))
        #expect(try eval("(3...) == (3...)") == .bool(true))
        #expect(try eval("[0...].count") == .int(1))
    }

    @Test("the eager terminals refuse it; ..< needs a bound; the top of Int is the end")
    func limits() throws {
        #expect(throws: SwiftalkError.self) { try eval("(0...).count") }
        #expect(throws: SwiftalkError.self) { try eval("(0...).reduce(0) { $0 + $1 }") }
        #expect(throws: SwiftalkError.self) { try eval("(0...).sorted()") }
        #expect(throws: SwiftalkError.self) { try eval("(0...).Array()") }
        #expect(throws: SwiftalkError.self) { try eval("0..<") }
        #expect(throws: SwiftalkError.self) { try eval("(3...)[-1]") }
        #expect(try eval("(9223372036854775806...).prefix(2)")
                == .array([.int(9223372036854775806), .int(9223372036854775807)]))
        #expect(throws: SwiftalkError.self) { try eval("(9223372036854775806...).prefix(3)") }
    }
}
