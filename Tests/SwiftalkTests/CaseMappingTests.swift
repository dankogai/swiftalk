import Testing
@testable import Swiftalk

// Round 195: String case mapping — uppercased(), lowercased() (Swift's),
// ucfirst(), lcfirst() (Perl's).
struct CaseMappingTests {
    @Test("uppercased and lowercased: Unicode's full mappings; ucfirst and lcfirst touch the first grapheme only")
    func mapping() throws {
        #expect(try eval("\"Hello, World\".uppercased()") == .string("HELLO, WORLD"))
        #expect(try eval("\"Hello, World\".lowercased()") == .string("hello, world"))
        #expect(try eval("\"straße\".uppercased()") == .string("STRASSE"))
        #expect(try eval("\"ÉCOLE\".lowercased()") == .string("école"))
        #expect(try eval("\"hello world\".ucfirst()") == .string("Hello world"))
        #expect(try eval("\"Hello World\".lcfirst()") == .string("hello World"))
        #expect(try eval("\"élan\".ucfirst()") == .string("Élan"))
        #expect(try eval("\"e\\u{301}lan\".ucfirst().count") == .int(4))                 // one grapheme mapped, the count kept
        #expect(try eval("\"\".uppercased() + \"\".ucfirst() + \"\".lcfirst()") == .string(""))
        #expect(try eval("\"123\".ucfirst()") == .string("123"))
        #expect(try eval("\"日本\".uppercased()") == .string("日本"))
        #expect(try eval("[\"a\", \"b\"].map { $0.uppercased() }") == .array([.string("A"), .string("B")]))
        #expect(try eval("\"abc\".uppercased().Type == String") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("\"abc\".uppercased(1)") }
        #expect(throws: SwiftalkError.self) { try eval("1.uppercased()") }
        #expect(throws: SwiftalkError.self) { try eval("\"abc\".uppercased") }                 // a method, as escaped() is
    }
}
