import Testing
@testable import Swiftalk

@Suite("map infers a stamp from the closure's results (round 170)")
struct MapStampTests {
    @Test("homogeneous results stamp the Array, and the stamp survives an emptying filter or slice")
    func inferred() throws {
        #expect(try eval("[0, 1, 2, 3].map { \"\\($0)\" }.Type.String()") == .string("[String]"))
        #expect(try eval("[0, 1, 2, 3].map { \"\\($0)\" }.filter { false }.Type.String()") == .string("[String]"))
        #expect(try eval("[0, 1].map { $0 * 2 }.dropFirst(2).Type.String()") == .string("[Int]"))
        #expect(try eval("[1, nil].map { $0 }.Type.String()") == .string("[Int?]"))
        #expect(try eval("[[1], [2]].map { $0 }.prefix(0).Type.String()") == .string("[[Int]]"))
        #expect(try eval("Set(1, 2).map { \"\\($0)\" }.filter { false }.Type.String()") == .string("[String]"))
        #expect(try eval("[1: \"a\"].map { k, v in v }.filter { false }.Type.String()") == .string("[String]"))
        #expect(throws: SwiftalkError.self) { try eval("var a = [0, 1].map { \"\\($0)\" }.filter { false }\na.append(1)") }
        #expect(try eval("var a = [0, 1].map { \"\\($0)\" }.filter { false }\na.append(\"x\")\na") == .array([.string("x")]))
    }

    @Test("nothing to infer: no results take the data default (round 181), mixed ones leave the Array erased; a lazy Sequence's map stays a Sequence")
    func erased() throws {
        #expect(try eval("[Int]().map { \"\\($0)\" }.Type.String()") == .string("[SION]"))
        #expect(try eval("[1, 2].map { $0 == 1 ? 1 : \"a\" }.Type.String()") == .string("Array"))
        #expect(try eval("[1, 2].map { $0 == 1 ? 1 : \"a\" }") == .array([.int(1), .string("a")]))   // still evaluates
        #expect(try eval("(1...).map { $0 }.Type.String()") == .string("Sequence"))
    }
}
