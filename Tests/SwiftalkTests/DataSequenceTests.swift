import Testing
@testable import Swiftalk

@Suite("Data is a Sequence of its bytes, as Ints (round 115)")
struct DataSequenceTests {
    let d = "let d = \"hé!\".Data(.utf8)\n"     // [104, 195, 169, 33]

    @Test("for-in, map, filter, reduce, contains, sorted, reversed, enumerated, Array(), Tuple(), conformance")
    func members() throws {
        #expect(try eval(d + "var s = 0\nfor b in d { s += b }\ns") == .int(501))
        #expect(try eval(d + "d.map { $0 + 1 }") == .array([105, 196, 170, 34].map { .int($0) }))
        #expect(try eval(d + "d.filter { $0 > 127 }") == .data([195, 169]))          // a Data back, as Swift's
        #expect(try eval(d + "d.reduce(0) { $0 + $1 }") == .int(501))
        #expect(try eval(d + "d.contains(33)") == .bool(true))
        #expect(try eval(d + "d.contains { $0 > 200 }") == .bool(false))
        #expect(try eval(d + "d.sorted()") == .array([33, 104, 169, 195].map { .int($0) }))
        #expect(try eval(d + "d.reversed()") == .array([33, 169, 195, 104].map { .int($0) }))
        #expect(try eval(d + "d.enumerated().prefix(1)") == .array([.tuple([.int(0), .int(104)], labels: ["offset", "element"])]))
        #expect(try eval(d + "d.Array()") == .array([104, 195, 169, 33].map { .int($0) }))
        #expect(try eval(d + "Tuple(d)") == .tuple([104, 195, 169, 33].map { .int($0) }))
        #expect(try eval("Data.conforms(to: Sequence)") == .bool(true))
        #expect(try eval("Data([104, 105]).map(String.fromCodePoint).joined()") == .string("hi"))
    }

    @Test("the slicing family and prefix/dropFirst with a predicate give a Data back; split cuts into Datas")
    func slices() throws {
        #expect(try eval(d + "d.prefix(2)") == .data([104, 195]))
        #expect(try eval(d + "d.suffix(1)") == .data([33]))
        #expect(try eval(d + "d.dropFirst()") == .data([195, 169, 33]))
        #expect(try eval(d + "d.dropLast(2)") == .data([104, 195]))
        #expect(try eval(d + "d.prefix { $0 < 200 }") == .data([104, 195, 169, 33]))
        #expect(try eval(d + "d.dropFirst { $0 < 150 }") == .data([195, 169, 33]))
        #expect(try eval("Data([1, 0, 2, 0, 3]).split(0)") == .array([.data([1]), .data([2]), .data([3])]))
        #expect(try eval(d + "d.prefix(2).Type == Data") == .bool(true))
        #expect(try eval(d + "for x in d where x > 127 { }\nd.count") == .int(4))
        #expect(throws: SwiftalkError.self) { try eval(d + "d.joined()") }               // bytes are Ints, not Strings
        #expect(throws: SwiftalkError.self) { try eval("let (a, b) = Data([1, 2])") }       // destructuring is a tuple's
    }
}
