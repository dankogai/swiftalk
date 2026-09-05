import Testing
@testable import Swiftalk

@Suite("String.fromCodePoint, and the unicodeScalars / utf32 / utf8 views (round 114)")
struct StringStaticsTests {
    @Test("fromCodePoint builds a String from Unicode scalars; invalid ones are errors; uncalled, a Function value")
    func fromCodePoint() throws {
        #expect(try eval("String.fromCodePoint(0x1F600)") == .string("😀"))
        #expect(try eval("String.fromCodePoint(72, 105, 0x1F600)") == .string("Hi😀"))
        #expect(try eval("String.fromCodePoint()") == .string(""))
        #expect(try eval("[104, 105].map(String.fromCodePoint).joined()") == .string("hi"))
        #expect(try eval("let f = String.fromCodePoint\nf(65)") == .string("A"))
        #expect(try eval("String.fromCodePoint(0x301).count") == .int(1))            // a lone combining mark is a grapheme
        #expect(try eval("(\"e\" + String.fromCodePoint(0x301)).count") == .int(1))  // and joins the base
        #expect(throws: SwiftalkError.self) { try eval("String.fromCodePoint(0xD800)") }     // a surrogate
        #expect(throws: SwiftalkError.self) { try eval("String.fromCodePoint(0x110000)") }
        #expect(throws: SwiftalkError.self) { try eval("String.fromCodePoint(-1)") }
        #expect(throws: SwiftalkError.self) { try eval("String.fromCodePoint(\"a\")") }
        #expect(throws: SwiftalkError.self) { try eval("String.fromCodePoint(codes: 65)") }
    }

    @Test("the views: unicodeScalars and utf32 are the scalars, utf8 the bytes — as [Int]; no utf16 (§11)")
    func views() throws {
        #expect(try eval("\"hé😀\".unicodeScalars") == .array([104, 233, 128512].map { .int($0) }))
        #expect(try eval("\"hé😀\".utf32") == .array([104, 233, 128512].map { .int($0) }))
        #expect(try eval("\"hé😀\".utf8") == .array([104, 195, 169, 240, 159, 152, 128].map { .int($0) }))
        #expect(try eval("\"\".utf8") == .array([]))
        #expect(try eval("\"é\".unicodeScalars.map(String.fromCodePoint).joined() == \"é\"") == .bool(true))
        #expect(try eval("String.fromCodePoint(\"😀\".unicodeScalars[0]) == \"😀\"") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("\"a\".utf16") }
        #expect(throws: SwiftalkError.self) { try eval("42.unicodeScalars") }
    }
}
